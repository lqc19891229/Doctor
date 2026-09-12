extends Node

# =========================================================
# SfxManager.gd
#
# 指定音效：
#
# Clinic / Story：
# - 按住 Q+A+Z / W+S+X：hear_tbeat
# - 打开行医记考：turn_page
#
# Night：
# - 打开读书窗口：turn_page
# - 确认进入下一天：male_yawning
#
# 普通音效由实际业务动作显式调用，不再依赖隐藏按钮的 pressed 信号。
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

const ROOSTER_CROWS_STREAM: AudioStream = preload(
	"res://Assets/Sfx/rooster_crows.mp3"
)

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


func play_turn_page() -> void:
	play_sfx(TURN_PAGE_STREAM)


func play_male_yawning() -> void:
	play_sfx(MALE_YAWNING_STREAM)


func play_rooster_crows() -> void:
	play_sfx(ROOSTER_CROWS_STREAM)


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
