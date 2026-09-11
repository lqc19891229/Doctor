extends Node

# =========================================================
# SfxManager.gd
#
# 指定音效：
#
# Clinic：
# - 按住 Q+A+Z / W+S+X：hear_tbeat
# - Openclinical_logWindowButton：turn_page
#
# Night：
# - ReadBookButton：turn_page
# - NextDayButton：male_yawning
# =========================================================


# =========================================================
# 音效资源
# =========================================================
const HEARTBEAT_STREAM: AudioStream = preload(
	"res://Assets/Sfx/hear_tbeat.mp3"
)

const TURN_PAGE_STREAM: AudioStream = preload(
	"res://Assets/Sfx/turn_page.mp3"
)

const MALE_YAWNING_STREAM: AudioStream = preload(
	"res://Assets/Sfx/male_yawning.mp3"
)

# =========================================================
# 按钮节点名称 -> 音效
# =========================================================
const BUTTON_SFX_BY_NAME: Dictionary = {
	&"Openclinical_logWindowButton": TURN_PAGE_STREAM,
	&"ReadBookButton": TURN_PAGE_STREAM,
	&"NextDayButton": MALE_YAWNING_STREAM
}


# 多个播放器可以避免快速点击时互相截断。
const BUTTON_PLAYER_COUNT: int = 4


var button_players: Array[AudioStreamPlayer] = []
var heartbeat_player: AudioStreamPlayer = null

var next_button_player_index: int = 0


# =========================================================
# 生命周期
# =========================================================
func _ready() -> void:
	# 暂停菜单出现时，音效系统仍然工作。
	process_mode = Node.PROCESS_MODE_ALWAYS

	_create_button_players()
	_create_heartbeat_player()

	var tree := get_tree()
	if tree == null:
		return

	# 监听之后动态进入场景树的按钮。
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)

	# 注册当前已经存在的按钮。
	_register_buttons_in_subtree(tree.root)


# =========================================================
# 创建普通音效播放器
# =========================================================
func _create_button_players() -> void:
	for index in range(BUTTON_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()

		player.name = "ButtonSfxPlayer%d" % (index + 1)
		player.bus = _get_sfx_bus_name()
		player.volume_db = -8.0
		player.process_mode = Node.PROCESS_MODE_ALWAYS

		add_child(player)
		button_players.append(player)


# =========================================================
# 创建心跳播放器
# =========================================================
func _create_heartbeat_player() -> void:
	heartbeat_player = AudioStreamPlayer.new()

	heartbeat_player.name = "HeartbeatPlayer"
	heartbeat_player.bus = _get_sfx_bus_name()
	heartbeat_player.volume_db = -4.0
	heartbeat_player.process_mode = Node.PROCESS_MODE_ALWAYS

	# 使用资源副本开启循环，不修改原始资源。
	var heartbeat_stream := HEARTBEAT_STREAM.duplicate() as AudioStream

	if heartbeat_stream is AudioStreamMP3:
		(heartbeat_stream as AudioStreamMP3).loop = true

	heartbeat_player.stream = heartbeat_stream

	add_child(heartbeat_player)


# =========================================================
# 按钮注册
# =========================================================
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

	# 只注册配置表中的按钮。
	if not BUTTON_SFX_BY_NAME.has(button.name):
		return

	var callback := Callable(
		self,
		"_on_button_pressed"
	).bind(button)

	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


# =========================================================
# 按钮按下
# =========================================================
func _on_button_pressed(button: BaseButton) -> void:
	if button == null:
		return

	var stream := BUTTON_SFX_BY_NAME.get(
		button.name,
		null
	) as AudioStream

	play_sfx(stream)


# =========================================================
# 播放普通音效
# =========================================================
func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return

	if button_players.is_empty():
		return

	var player := _get_available_button_player()

	player.stream = stream
	player.play()


func _get_available_button_player() -> AudioStreamPlayer:
	# 优先使用当前没有播放声音的播放器。
	for player in button_players:
		if not player.playing:
			return player

	# 所有播放器都在使用时，循环复用。
	var player := button_players[next_button_player_index]

	next_button_player_index = (
		(next_button_player_index + 1)
		% button_players.size()
	)

	return player


# =========================================================
# 心跳音效
# =========================================================
func start_heartbeat() -> void:
	if heartbeat_player == null:
		return

	if heartbeat_player.stream == null:
		return

	# 已经播放时不重新开始，避免每帧重复触发。
	if not heartbeat_player.playing:
		heartbeat_player.play()


func stop_heartbeat() -> void:
	if heartbeat_player == null:
		return

	if heartbeat_player.playing:
		heartbeat_player.stop()


func set_heartbeat_active(active: bool) -> void:
	if active:
		start_heartbeat()
	else:
		stop_heartbeat()


# =========================================================
# 音频总线
# =========================================================
func _get_sfx_bus_name() -> StringName:
	if AudioServer.get_bus_index("SFX") >= 0:
		return &"SFX"

	# 项目缺少 SFX Bus 时使用 Master，避免完全没有声音。
	return &"Master"
