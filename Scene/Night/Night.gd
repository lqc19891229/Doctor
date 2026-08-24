extends Control
class_name Night

signal night_finished
signal story_requested(story_path: String, return_target: String)

const TopBarControllerScript := preload("res://System/Unlock/TopBarController.gd")

# 夜晚四季背景；季节划分与 Clinic.gd 保持一致。
const NIGHT_SPRING_BACKGROUND: Texture2D = preload("res://Assets/Background/clinic/spring_night.png")
const NIGHT_SUMMER_BACKGROUND: Texture2D = preload("res://Assets/Background/clinic/summer_night.png")
const NIGHT_AUTUMN_BACKGROUND: Texture2D = preload("res://Assets/Background/clinic/autumn_night.png")
const NIGHT_WINTER_BACKGROUND: Texture2D = preload("res://Assets/Background/clinic/winter_night.png")

@onready var read_book_window: Window = find_child("ReadBook", true, false) as Window
@onready var info_window: Window = $InfoWindow
@onready var info_label: Label = $InfoWindow/Panel/VBoxContainer/InfoLabel

@onready var read_book_button: Button = find_child("ReadBookButton", true, false) as Button
@onready var next_day_button: Button = find_child("NextDayButton", true, false) as Button

@onready var day_label: Label = find_child("DayLabel", true, false) as Label
@onready var time_label: Label = find_child("TimeLabel", true, false) as Label
@onready var thoughts_point_label: Label = find_child("ThoughtsPoint", true, false) as Label
@onready var reputation_point_label: Label = find_child("ReputationPoint", true, false) as Label

# 复用 Night.tscn 中现有的背景节点，无需调整场景结构。
@onready var night_background: TextureRect = $Background/BackgroundImage

var topbar_controller = null

# 玩家提示窗口（Control 版 PlayerHintWindow，需作为 Night.tscn 的子节点存在）
var player_hint_window: Node = null

func _ready() -> void:
	_validate_scene_node_bindings()
	_setup_buttons()
	_setup_player_hint_dialog()
	_setup_read_book_window()
	_setup_topbar_controller()
	_refresh_topbar(true)


# =========================
# 节点绑定检查
# =========================

func _validate_scene_node_bindings() -> void:
	_check_node_binding(read_book_window, "ReadBook")
	_check_node_binding(read_book_button, "ReadBookButton")
	_check_node_binding(next_day_button, "NextDayButton")
	_check_node_binding(day_label, "DayLabel")
	_check_node_binding(time_label, "TimeLabel")
	_check_node_binding(thoughts_point_label, "ThoughtsPoint")
	_check_node_binding(reputation_point_label, "ReputationPoint")
	_check_node_binding(night_background, "BackgroundImage")
	_check_node_binding(info_window, "InfoWindow")
	_check_node_binding(info_label, "InfoWindow/InfoLabel")


func _check_node_binding(node: Node, node_name: String) -> void:
	if node == null:
		push_warning("Night.gd 找不到节点：%s，请检查 Night.tscn 节点名是否一致" % node_name)


# =========================
# 根据当前节气刷新夜晚背景
# =========================

func _update_night_background(day: int) -> void:
	if night_background == null:
		push_warning("Night.gd 未找到 TextureRect 类型的 BackgroundImage 节点，无法切换季节背景。")
		return

	# 每一天对应一个节气，每 24 天重新从春季开始循环。
	var solar_term_index: int = (maxi(day, 1) - 1) % 24

	if solar_term_index < 6:
		# 第 1～6 天：春季
		night_background.texture = NIGHT_SPRING_BACKGROUND
	elif solar_term_index < 12:
		# 第 7～12 天：夏季
		night_background.texture = NIGHT_SUMMER_BACKGROUND
	elif solar_term_index < 18:
		# 第 13～18 天：秋季
		night_background.texture = NIGHT_AUTUMN_BACKGROUND
	else:
		# 第 19～24 天：冬季
		night_background.texture = NIGHT_WINTER_BACKGROUND


func get_current_background_texture() -> Texture2D:
	# Main 在隐藏 Night 并播放 Story 前读取当前实际显示的季节背景。
	if night_background == null:
		return null
	return night_background.texture


# =========================
# 初始化按钮
# =========================

func _setup_buttons() -> void:
	if read_book_button != null:
		read_book_button.text = "读书"

		if not read_book_button.pressed.is_connected(_on_read_book_button_pressed):
			read_book_button.pressed.connect(_on_read_book_button_pressed)

	if next_day_button != null:
		next_day_button.text = "休息，进入明天"

		if not next_day_button.pressed.is_connected(_on_next_day_button_pressed):
			next_day_button.pressed.connect(_on_next_day_button_pressed)


# =========================
# 初始化玩家提示窗口
# =========================

func _setup_player_hint_dialog() -> void:
	if player_hint_window != null and is_instance_valid(player_hint_window):
		return

	player_hint_window = find_child("PlayerHintWindow", true, false)

	if player_hint_window == null:
		push_warning("Night.gd 找不到 PlayerHintWindow，请检查 Night.tscn 是否已经添加 PlayerHintWindow.tscn")
		return

	if player_hint_window.has_method("hide"):
		player_hint_window.hide()


func _show_player_hint(message: String) -> void:
	if player_hint_window == null or not is_instance_valid(player_hint_window):
		_setup_player_hint_dialog()

	if player_hint_window != null and player_hint_window.has_method("show_hint"):
		player_hint_window.call("show_hint", message)
	else:
		push_warning(message)


# =========================
# 开发测试窗口
# InfoWindow 已在 Night.tscn 中固定实例化，信号也由场景文件连接。
# =========================

func open_info_window() -> void:
	if not OS.is_debug_build():
		return

	if info_window == null:
		push_warning("Night.gd 找不到 Night.tscn 中固定实例化的 InfoWindow。")
		return

	if info_window.has_method("open_window"):
		info_window.call("open_window")
	else:
		info_window.popup_centered()


func _set_info_window_text(message: String) -> void:
	if info_label != null:
		info_label.text = message
	elif OS.is_debug_build():
		print(message)


func _on_info_window_end_today_requested() -> void:
	# 在 Night 中，“结束当天”作为测试用的“立即结束夜晚”。
	# 故意跳过未读条目检查，方便快速测试跨天流程。
	night_finished.emit()


func _on_info_window_unlock_all_entries_requested() -> void:
	if Unlock == null or not Unlock.has_method("unlock_all_entries_for_test"):
		_set_info_window_text("测试功能不可用：Unlock 缺少 unlock_all_entries_for_test()。")
		return

	var result: Dictionary = Unlock.call("unlock_all_entries_for_test")
	_set_info_window_text("测试功能：已解锁全部条目\n条目：%d\n药材：%d\n方剂：%d\n疾病：%d\n医理：%d" % [
		result.get("entry_count", 0),
		result.get("herb_count", 0),
		result.get("formula_count", 0),
		result.get("disease_count", 0),
		result.get("theory_count", 0)
	])

	_refresh_topbar(true)
	if read_book_window != null and read_book_window.has_method("_refresh_book_list"):
		read_book_window.call("_refresh_book_list")


func _on_info_window_npc_action_requested() -> void:
	_set_info_window_text("Night 场景没有当前病人；切换或生成病人的测试功能仅在 Clinic 可用。")


# =========================
# 初始化读书窗口
# =========================

func _setup_read_book_window() -> void:
	if read_book_window == null:
		push_warning("Night.gd 找不到 ReadBook 窗口")
		return

	# Night 场景刚进入时，ReadBook 作为子窗口先隐藏。
	read_book_window.hide()

	# ReadBook.gd 自定义关闭信号。
	if read_book_window.has_signal("window_closed"):
		if not read_book_window.is_connected("window_closed", Callable(self, "_on_read_book_window_closed")):
			read_book_window.connect("window_closed", Callable(self, "_on_read_book_window_closed"))

	# 读书消耗心得 / 解锁数据变化后，刷新 Night 外层 UI。
	if read_book_window.has_signal("player_data_changed"):
		if not read_book_window.is_connected("player_data_changed", Callable(self, "_on_player_data_changed")):
			read_book_window.connect("player_data_changed", Callable(self, "_on_player_data_changed"))


# =========================
# 初始化通用顶部栏
# =========================

func _setup_topbar_controller() -> void:
	if topbar_controller != null and is_instance_valid(topbar_controller):
		return

	topbar_controller = TopBarControllerScript.new()
	topbar_controller.name = "TopBarController"
	add_child(topbar_controller)
	topbar_controller.setup(
		day_label,
		time_label,
		thoughts_point_label,
		reputation_point_label,
		"夜晚"
	)


# =========================
# 刷新顶部栏
# =========================

func _refresh_topbar(force_refresh: bool = false) -> void:
	if topbar_controller == null:
		_setup_topbar_controller()

	if topbar_controller != null:
		topbar_controller.set_time_text_override("夜晚")
		topbar_controller.refresh_all(force_refresh)


# =========================
# 打开读书窗口
# =========================

func _on_read_book_button_pressed() -> void:
	open_read_book_window()


func open_read_book_window() -> void:
	if read_book_window == null:
		push_warning("Night.gd 无法打开读书窗口：read_book_window 为空")
		return

	# 每次打开前刷新一次窗口内显示，避免心得数量或书籍状态是旧的。
	if read_book_window.has_method("_update_day_label"):
		read_book_window.call("_update_day_label")

	if read_book_window.has_method("_update_thoughts_point_ui"):
		read_book_window.call("_update_thoughts_point_ui")

	if read_book_window.has_method("_refresh_book_list"):
		read_book_window.call("_refresh_book_list")

	# 和其他 Window 一样，由 ReadBook.gd 自己 open_window()，不再 popup_centered。
	if read_book_window.has_method("open_window"):
		read_book_window.call("open_window")
	else:
		read_book_window.show()


# =========================
# ReadBook 窗口关闭
# =========================

func _on_read_book_window_closed() -> void:
	if read_book_window == null:
		return

	# 注意：这里不要 queue_free。
	# ReadBook 是 Night.tscn 里固定存在的子节点，只需要隐藏。
	read_book_window.hide()


# =========================
# 读书数据变化
# =========================

func _on_player_data_changed() -> void:
	_refresh_topbar()


# =========================
# 开发测试快捷键
# Ctrl + T：打开 InfoWindow
# =========================

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not is_visible_in_tree():
		return

	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.ctrl_pressed and key_event.keycode == KEY_T:
		open_info_window()
		get_viewport().set_input_as_handled()


# =========================
# 进入下一天
# =========================

func _on_next_day_button_pressed() -> void:
	if _has_unread_entries():
		_show_player_hint("尚有未读条目，请先阅读后再休息。")
		return

	night_finished.emit()


func _has_unread_entries() -> bool:
	if Unlock == null:
		return false

	# 先刷新所有可能在当前夜晚新解锁的条目，避免旧存档或延迟刷新漏检。
	if Unlock.has_method("refresh_auto_unlocks_by_experience"):
		Unlock.refresh_auto_unlocks_by_experience()

	if Unlock.has_method("refresh_unlocks_by_dependencies"):
		Unlock.refresh_unlocks_by_dependencies()

	# 正式检查药材、方剂、疾病、理论四类未读条目。
	if Unlock.has_method("has_unread_readable_entries"):
		return Unlock.has_unread_readable_entries()

	if Unlock.has_method("get_unread_readable_entry_count"):
		return int(Unlock.get_unread_readable_entry_count()) > 0

	# 兼容尚未更新 UnlockManager 的旧版本。
	if Unlock.has_method("has_unread_unlocked_disease_or_formula_entries"):
		return Unlock.has_unread_unlocked_disease_or_formula_entries()

	if Unlock.has_method("get_unread_unlocked_disease_or_formula_entry_count"):
		return int(Unlock.get_unread_unlocked_disease_or_formula_entry_count()) > 0

	return false

# =========================
# 夜晚进入入口 / 自动剧情触发
# =========================

func start_night(day: int) -> void:
	# 由 Main._enter_night() 在连接好 story_requested 后调用。
	# 不在 _ready() 中触发剧情，避免信号尚未连接导致剧情请求丢失。
	_update_night_background(day)
	if topbar_controller != null:
		topbar_controller.set_fallback_day(day)
	_refresh_topbar(true)
	_try_start_auto_story("night", day)


func _try_start_auto_story(trigger_scene: String, day: int) -> bool:
	if StoryManager == null:
		push_warning("Night 无法访问 StoryManager。")
		return false

	if not StoryManager.has_method("find_trigger_story"):
		push_warning("StoryManager 缺少 find_trigger_story()，无法自动检查夜晚剧情。")
		return false

	var story: StoryData = StoryManager.find_trigger_story(trigger_scene, day)
	if story == null:
		return false

	var story_path := _find_registered_story_path(story)
	if story_path.is_empty():
		push_warning("找到可触发夜晚剧情，但没有找到对应资源路径。请检查 StoryManager.registered_story_paths。")
		return false

	var return_target := "night"
	if story.return_scene != "":
		return_target = story.return_scene

	emit_signal("story_requested", story_path, return_target)
	return true


func _find_registered_story_path(target_story: StoryData) -> String:
	if target_story == null:
		return ""

	var story_paths = StoryManager.get("registered_story_paths")
	if typeof(story_paths) != TYPE_ARRAY:
		push_warning("StoryManager 缺少 registered_story_paths。")
		return ""

	for story_path in story_paths:
		if typeof(story_path) != TYPE_STRING:
			continue

		var loaded_story: Resource = load(story_path)
		if loaded_story == null:
			continue

		if not loaded_story is StoryData:
			continue

		var story := loaded_story as StoryData

		# 同一路径资源通常会被缓存，优先用实例比较。
		if story == target_story:
			return story_path

		# 实例比较失败时，用 story_id 兜底。
		var target_story_id: String = target_story.get("story_id")
		var current_story_id: String = story.get("story_id")
		if not target_story_id.is_empty() and target_story_id == current_story_id:
			return story_path

	return ""
