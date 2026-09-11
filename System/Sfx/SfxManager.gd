extends Node

# =========================================================
# SfxManager.gd
# 全局音效管理器
#
# 功能：
# 1. 自动为 BaseButton 播放点击音。
# 2. 管理把脉心跳音效。
# 3. 所有音效统一输出到 SFX Audio Bus。
#
# 使用方法：
# 将本脚本注册为 Autoload，名称必须为 SfxManager。
# 如果某个按钮不需要点击音，在按钮上添加：
# metadata/sfx_disabled = true
# =========================================================

const HEARTBEAT_STREAM: AudioStream = preload("res://Assets/hear_tbeat.mp3")

const BUTTON_PLAYER_COUNT: int = 4
const CLICK_SAMPLE_RATE: int = 44100
const CLICK_DURATION_SECONDS: float = 0.055

var button_players: Array[AudioStreamPlayer] = []
var heartbeat_player: AudioStreamPlayer = null
var button_click_stream: AudioStreamWAV = null
var next_button_player_index: int = 0


func _ready() -> void:
	# 暂停菜单显示期间也允许播放按钮音效。
	process_mode = Node.PROCESS_MODE_ALWAYS

	button_click_stream = _create_button_click_stream()
	_create_button_players()
	_create_heartbeat_player()

	var tree := get_tree()
	if tree != null:
		if not tree.node_added.is_connected(_on_node_added):
			tree.node_added.connect(_on_node_added)

		# 兼容 SfxManager 初始化前已经进入场景树的按钮。
		_register_buttons_in_subtree(tree.root)


# =========================================================
# 按钮音效
# =========================================================
func play_button_click() -> void:
	if button_click_stream == null or button_players.is_empty():
		return

	var player := _get_available_button_player()
	player.stream = button_click_stream
	player.play()


func _create_button_players() -> void:
	for index in range(BUTTON_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "ButtonSfxPlayer%d" % (index + 1)
		player.bus = _get_sfx_bus_name()
		player.volume_db = -8.0
		player.process_mode = Node.PROCESS_MODE_ALWAYS

		add_child(player)
		button_players.append(player)


func _get_available_button_player() -> AudioStreamPlayer:
	for player in button_players:
		if not player.playing:
			return player

	var player := button_players[next_button_player_index]
	next_button_player_index = (
		(next_button_player_index + 1)
		% button_players.size()
	)
	return player


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_register_button(node as BaseButton)


func _register_buttons_in_subtree(root: Node) -> void:
	if root == null:
		return

	if root is BaseButton:
		_register_button(root as BaseButton)

	for child in root.get_children():
		_register_buttons_in_subtree(child)


func _register_button(button: BaseButton) -> void:
	if button == null:
		return

	if bool(button.get_meta("sfx_disabled", false)):
		return

	var callback := Callable(self, "_on_button_pressed").bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_button_pressed(button: BaseButton) -> void:
	if button == null:
		return

	if bool(button.get_meta("sfx_disabled", false)):
		return

	play_button_click()


# =========================================================
# 把脉心跳
# =========================================================
func _create_heartbeat_player() -> void:
	heartbeat_player = AudioStreamPlayer.new()
	heartbeat_player.name = "HeartbeatPlayer"
	heartbeat_player.bus = _get_sfx_bus_name()
	heartbeat_player.volume_db = -4.0
	heartbeat_player.process_mode = Node.PROCESS_MODE_ALWAYS

	# 使用副本设置循环，避免修改原始预加载资源。
	var heartbeat_stream := HEARTBEAT_STREAM.duplicate() as AudioStream
	if heartbeat_stream is AudioStreamMP3:
		(heartbeat_stream as AudioStreamMP3).loop = true

	heartbeat_player.stream = heartbeat_stream
	add_child(heartbeat_player)


func start_heartbeat() -> void:
	if heartbeat_player == null or heartbeat_player.stream == null:
		return

	# 长按期间只启动一次，不会因为每帧检测而反复从头播放。
	if not heartbeat_player.playing:
		heartbeat_player.play()


func stop_heartbeat() -> void:
	if heartbeat_player != null and heartbeat_player.playing:
		heartbeat_player.stop()


func set_heartbeat_active(active: bool) -> void:
	if active:
		start_heartbeat()
	else:
		stop_heartbeat()


# =========================================================
# 公共辅助
# =========================================================
func _get_sfx_bus_name() -> StringName:
	if AudioServer.get_bus_index("SFX") >= 0:
		return &"SFX"
	return &"Master"


func _create_button_click_stream() -> AudioStreamWAV:
	# 项目目前没有通用按钮音素材，因此运行时生成一个短促点击音。
	# 后续如果准备了正式素材，只需要替换此函数返回的 AudioStream。
	var sample_count := int(CLICK_SAMPLE_RATE * CLICK_DURATION_SECONDS)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for sample_index in range(sample_count):
		var time := float(sample_index) / float(CLICK_SAMPLE_RATE)
		var envelope := exp(-58.0 * time)
		var transient := sin(TAU * 1450.0 * time) * 0.62
		var body := sin(TAU * 520.0 * time) * 0.28
		var sample := clampf(
			(transient + body) * envelope,
			-1.0,
			1.0
		)

		data.encode_s16(
			sample_index * 2,
			int(sample * 32767.0)
		)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = CLICK_SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
