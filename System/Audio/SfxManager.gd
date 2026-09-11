extends Node

# 全局音效管理器。
# - 自动为场景树中的 BaseButton 播放轻量点击音。
# - 单独管理把脉心跳，避免与按钮音效互相打断。
#
# 若某个按钮不需要音效，在检查器中添加 bool 元数据：sfx_disabled = true。

const HEARTBEAT_STREAM: AudioStream = preload("res://Assets/hear_tbeat.mp3")
const BUTTON_PLAYER_COUNT := 4
const CLICK_SAMPLE_RATE := 44100
const CLICK_DURATION_SECONDS := 0.055

var _button_players: Array[AudioStreamPlayer] = []
var _next_button_player_index := 0
var _heartbeat_player: AudioStreamPlayer
var _button_click_stream: AudioStreamWAV


func _ready() -> void:
	# 暂停菜单中的按钮也需要正常发声。
	process_mode = Node.PROCESS_MODE_ALWAYS

	_button_click_stream = _create_button_click_stream()
	_create_audio_players()

	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)

	# 兼容 SfxManager 初始化前已经进入场景树的按钮。
	_connect_buttons_in_subtree(get_tree().root)


func play_button_click() -> void:
	if _button_players.is_empty() or _button_click_stream == null:
		return

	var player := _find_available_button_player()
	player.stream = _button_click_stream
	player.play()


func start_heartbeat() -> void:
	if _heartbeat_player == null or _heartbeat_player.stream == null:
		return
	if not _heartbeat_player.playing:
		_heartbeat_player.play()


func stop_heartbeat() -> void:
	if _heartbeat_player != null and _heartbeat_player.playing:
		_heartbeat_player.stop()


func set_heartbeat_active(active: bool) -> void:
	if active:
		start_heartbeat()
	else:
		stop_heartbeat()


func _create_audio_players() -> void:
	for index in range(BUTTON_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "ButtonPlayer%d" % (index + 1)
		player.bus = _get_sfx_bus_name()
		player.volume_db = -8.0
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_button_players.append(player)

	_heartbeat_player = AudioStreamPlayer.new()
	_heartbeat_player.name = "HeartbeatPlayer"
	_heartbeat_player.bus = _get_sfx_bus_name()
	_heartbeat_player.volume_db = -4.0
	_heartbeat_player.process_mode = Node.PROCESS_MODE_ALWAYS

	# duplicate 后再设置循环，避免修改预加载资源本身。
	var heartbeat_stream := HEARTBEAT_STREAM.duplicate() as AudioStream
	if heartbeat_stream is AudioStreamMP3:
		(heartbeat_stream as AudioStreamMP3).loop = true
	_heartbeat_player.stream = heartbeat_stream
	add_child(_heartbeat_player)


func _get_sfx_bus_name() -> StringName:
	return &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node as BaseButton)


func _connect_buttons_in_subtree(root: Node) -> void:
	if root == null:
		return
	if root is BaseButton:
		_connect_button(root as BaseButton)
	for child in root.get_children():
		_connect_buttons_in_subtree(child)


func _connect_button(button: BaseButton) -> void:
	if button == null or bool(button.get_meta("sfx_disabled", false)):
		return

	var callback := Callable(self, "_on_button_pressed").bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_button_pressed(button: BaseButton) -> void:
	if button == null or bool(button.get_meta("sfx_disabled", false)):
		return
	play_button_click()


func _find_available_button_player() -> AudioStreamPlayer:
	for player in _button_players:
		if not player.playing:
			return player

	var player := _button_players[_next_button_player_index]
	_next_button_player_index = (_next_button_player_index + 1) % _button_players.size()
	return player


func _create_button_click_stream() -> AudioStreamWAV:
	# 运行时生成一个短促、低侵入性的木质点击音，避免额外引入素材文件。
	var sample_count := int(CLICK_SAMPLE_RATE * CLICK_DURATION_SECONDS)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for sample_index in range(sample_count):
		var time := float(sample_index) / float(CLICK_SAMPLE_RATE)
		var envelope := exp(-58.0 * time)
		var transient := sin(TAU * 1450.0 * time) * 0.62
		var body := sin(TAU * 520.0 * time) * 0.28
		var sample := clampf((transient + body) * envelope, -1.0, 1.0)
		data.encode_s16(sample_index * 2, int(sample * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = CLICK_SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
