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

# 背景单次渐出或渐入的持续时间。
# 完整换图过程约为该数值的两倍。
@export_range(0.05, 2.0, 0.05) var background_fade_duration: float = 0.45

@onready var read_book_window: Window = find_child("ReadBook", true, false) as Window
@onready var info_window: Window = $InfoWindow
@onready var info_label: Label = $InfoWindow/Panel/VBoxContainer/InfoLabel

@onready var read_book_button: Button = find_child("ReadBookButton", true, false) as Button
@onready var next_day_button: Button = find_child("NextDayButton", true, false) as Button

# 顶部栏节点必须使用精确路径。
# InfoWindow 中也存在名为 DayLabel 的测试节点；使用递归 find_child() 会误绑定到
# 隐藏的测试窗口，导致屏幕左上角真正的日期一直停留在默认文字“天数”。
@onready var day_label: Label = $VBoxContainer/TopBar/HBoxContainer/DayLabel
@onready var time_label: Label = $VBoxContainer/TopBar/HBoxContainer/TimeLabel
@onready var thoughts_point_label: Label = $VBoxContainer/TopBar/HBoxContainer/ThoughtsPoint
@onready var reputation_point_label: Label = $VBoxContainer/TopBar/HBoxContainer/ReputationPoint
@onready var money_point_label: Label = $VBoxContainer/TopBar/HBoxContainer/MoneyPoint

# 复用 Night.tscn 中现有的背景节点，无需调整场景结构。
@onready var night_background: TextureRect = $Background/BackgroundImage

# 背景渐变状态。
var background_fade_tween: Tween = null
var background_fade_mask: ColorRect = null
var night_background_target_texture: Texture2D = null

var topbar_controller = null

# 玩家提示窗口。Night.tscn 中它是根节点的直接子节点，使用精确路径，
# 避免未来其它子窗口也出现同名节点时递归 find_child() 绑定错对象。
@onready var player_hint_window: Node = $PlayerHintWindow

# 进入夜晚时若存在当日银钱结算，必须先等玩家关闭结算窗口，
# 再检查 trigger_scene = "night" 的自动剧情，避免剧情把结算窗口立刻盖掉。
var waiting_finance_report_close: bool = false
var pending_night_auto_story_day: int = 0

func _ready() -> void:
	_validate_scene_node_bindings()
	_setup_night_background_fade_mask()
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
	_check_node_binding(money_point_label, "MoneyPoint")
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
	var target_texture: Texture2D = NIGHT_SPRING_BACKGROUND

	if solar_term_index < 6:
		# 第 1～6 天：春季
		target_texture = NIGHT_SPRING_BACKGROUND
	elif solar_term_index < 12:
		# 第 7～12 天：夏季
		target_texture = NIGHT_SUMMER_BACKGROUND
	elif solar_term_index < 18:
		# 第 13～18 天：秋季
		target_texture = NIGHT_AUTUMN_BACKGROUND
	else:
		# 第 19～24 天：冬季
		target_texture = NIGHT_WINTER_BACKGROUND

	night_background_target_texture = target_texture
	_change_night_background_with_fade(target_texture)


func _stop_night_background_fade() -> void:
	if background_fade_tween != null and background_fade_tween.is_valid():
		background_fade_tween.kill()

	background_fade_tween = null


func _set_night_background_texture(texture: Texture2D) -> void:
	night_background.texture = texture
	night_background.show()


func _setup_night_background_fade_mask() -> void:
	if background_fade_mask != null:
		return

	if night_background == null:
		return

	var background_parent := night_background.get_parent() as Control
	if background_parent == null:
		push_warning("Night.gd 无法为 BackgroundImage 创建背景渐变遮罩。")
		return

	background_fade_mask = ColorRect.new()
	background_fade_mask.name = "BackgroundFadeMask"
	background_fade_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_fade_mask.color = Color(0.0, 0.0, 0.0, 1.0)

	background_parent.add_child(background_fade_mask)
	background_parent.move_child(
		background_fade_mask,
		night_background.get_index() + 1
	)
	background_fade_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _set_night_background_mask_alpha(alpha: float) -> void:
	if background_fade_mask == null:
		return

	var mask_color := background_fade_mask.color
	mask_color.a = alpha
	background_fade_mask.color = mask_color


func _fade_night_background_in() -> void:
	if background_fade_mask == null:
		return

	background_fade_tween = create_tween()
	background_fade_tween.set_trans(Tween.TRANS_SINE)
	background_fade_tween.set_ease(Tween.EASE_IN_OUT)
	background_fade_tween.tween_property(
		background_fade_mask,
		"color:a",
		0.0,
		background_fade_duration
	)


func _change_night_background_with_fade(new_texture: Texture2D) -> void:
	if new_texture == null:
		return

	# 初次进入 Night 时没有旧背景，直接设置贴图并从黑色渐入。
	if night_background.texture == null:
		_stop_night_background_fade()
		_set_night_background_texture(new_texture)
		_set_night_background_mask_alpha(1.0)
		_fade_night_background_in()
		return

	# 相同贴图不重新播放动画，也不终止当前尚未完成的渐入。
	if night_background.texture == new_texture:
		night_background.show()
		if (
			background_fade_mask != null
			and background_fade_mask.color.a > 0.0
			and (
				background_fade_tween == null
				or not background_fade_tween.is_valid()
			)
		):
			_fade_night_background_in()
		return

	_stop_night_background_fade()

	if background_fade_mask == null:
		_set_night_background_texture(new_texture)
		return

	background_fade_tween = create_tween()
	background_fade_tween.set_trans(Tween.TRANS_SINE)
	background_fade_tween.set_ease(Tween.EASE_IN_OUT)

	# 旧背景渐出到黑色。
	background_fade_tween.tween_property(
		background_fade_mask,
		"color:a",
		1.0,
		background_fade_duration
	)

	# 完全变黑后替换季节背景。
	background_fade_tween.tween_callback(
		_set_night_background_texture.bind(new_texture)
	)

	# 新背景从黑色渐入。
	background_fade_tween.tween_property(
		background_fade_mask,
		"color:a",
		0.0,
		background_fade_duration
	)


func get_current_background_texture() -> Texture2D:
	# Main 在隐藏 Night 并播放 Story 前优先读取当前请求显示的季节背景。
	# 即使背景仍处于渐变中，Story 也能取得正确的新贴图。
	if night_background_target_texture != null:
		return night_background_target_texture
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
	if player_hint_window == null or not is_instance_valid(player_hint_window):
		push_warning("Night.gd 找不到根节点直属 PlayerHintWindow，请检查 Night.tscn。")
		return

	# 结算提示必须盖在夜晚背景 / TopBar / 按钮之上。
	if player_hint_window is CanvasItem:
		(player_hint_window as CanvasItem).z_index = 1000

	if player_hint_window.has_method("hide"):
		player_hint_window.hide()

	# PlayerHintWindow 自带 confirmed 信号，优先使用显式关闭事件推进流程。
	# visibility_changed 保留为兜底：若其它代码直接 hide()，仍然能够继续夜晚剧情。
	var confirmed_callable := Callable(self, "_on_player_hint_confirmed")
	if (
		player_hint_window.has_signal("confirmed")
		and not player_hint_window.is_connected("confirmed", confirmed_callable)
	):
		player_hint_window.connect("confirmed", confirmed_callable)

	var visibility_callable := Callable(self, "_on_player_hint_visibility_changed")
	if (
		player_hint_window.has_signal("visibility_changed")
		and not player_hint_window.is_connected("visibility_changed", visibility_callable)
	):
		player_hint_window.connect("visibility_changed", visibility_callable)


func _show_player_hint(message: String) -> void:
	if player_hint_window == null or not is_instance_valid(player_hint_window):
		_setup_player_hint_dialog()

	if player_hint_window != null and player_hint_window.has_method("show_hint"):
		player_hint_window.call("show_hint", message)
	else:
		push_warning(message)



func _is_player_hint_visible() -> bool:
	if player_hint_window == null or not is_instance_valid(player_hint_window):
		return false

	if player_hint_window is CanvasItem:
		return (player_hint_window as CanvasItem).visible

	if player_hint_window is Window:
		return (player_hint_window as Window).visible

	return false


func _show_finance_report_for_day(day: int) -> bool:
	if Unlock == null:
		push_warning("Night 无法访问 Unlock，不能生成银钱结算。")
		return false

	# Main 正常路径已经结算。这里再做一次幂等兜底：
	# 读夜晚存档、剧情特殊跳转、调试跳转等路径漏掉 Main 结算时，Night 仍能自己补齐。
	if Unlock.has_method("settle_day_finances"):
		Unlock.settle_day_finances(day)

	if not Unlock.has_method("build_finance_report_text"):
		push_warning("Unlock 缺少 build_finance_report_text()，不能显示银钱结算。")
		return false

	var report_text: String = Unlock.build_finance_report_text(day)
	if report_text.is_empty():
		push_warning("Night 未取得第 %d 天银钱结算报告。" % day)
		return false

	_show_player_hint(report_text)
	return _is_player_hint_visible()


func _continue_after_finance_report() -> void:
	if not waiting_finance_report_close:
		return

	var day := pending_night_auto_story_day
	waiting_finance_report_close = false
	pending_night_auto_story_day = 0

	if day > 0:
		# 先让 PlayerHintWindow.hide() 真正绘制到屏幕，
		# 再开始 StoryManager 的夜晚剧情检查。
		# 剧情资源较多时，即使后续同步扫描需要一些时间，
		# 玩家也会先立即看到结算窗口消失。
		call_deferred("_start_night_story_after_hint_closed", day)


func _start_night_story_after_hint_closed(day: int) -> void:
	# 等到下一帧。当前点击触发的 hide() 会先完成一次实际渲染，
	# 避免后续剧情扫描阻塞时表现成“点击后窗口很久才关闭”。
	await get_tree().process_frame

	if not is_inside_tree():
		return

	_try_start_auto_story("night", day)


func _on_player_hint_confirmed() -> void:
	_continue_after_finance_report()


func _on_player_hint_visibility_changed() -> void:
	if not waiting_finance_report_close:
		return

	# show() 也会触发 visibility_changed；只有隐藏时才作为 confirmed 的兜底。
	if _is_player_hint_visible():
		return

	_continue_after_finance_report()


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
		"夜晚",
		money_point_label
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

func start_night(day: int, show_finance_report: bool = true) -> void:
	# 由 Main._enter_night() 在连接好 story_requested 后调用。
	_update_night_background(day)
	if topbar_controller != null:
		topbar_controller.set_fallback_day(day)
	_refresh_topbar(true)

	waiting_finance_report_close = false
	pending_night_auto_story_day = 0

	# 剧情结束返回 Night 时，Main 会传 show_finance_report = false。
	# 只跳过结算窗口展示；当天财务结算本身已经由 Main / Unlock 完成。
	if not show_finance_report:
		call_deferred("_try_start_auto_story", "night", day)
		return

	pending_night_auto_story_day = day

	# 关键：不要在导致 Clinic 结束的同一个鼠标事件里立即 show_hint()。
	# 最后一位病人的 JudgementResult 是在 _input() 中关闭的；若这里同步弹窗，
	# 同一点击事件随后进入 GUI 阶段时会把刚出现的 PlayerHintWindow 也一起关掉。
	# 延后一拍后再显示，确保结算窗口至少真实渲染一帧。
	call_deferred("_show_finance_report_after_scene_enter", day)


func _show_finance_report_after_scene_enter(day: int) -> void:
	if not is_inside_tree():
		return

	waiting_finance_report_close = true
	pending_night_auto_story_day = day

	if _show_finance_report_for_day(day):
		return

	# 没有报告时不要卡死夜晚入口。
	waiting_finance_report_close = false
	pending_night_auto_story_day = 0
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
		push_warning("找到可触发夜晚剧情，但 StoryManager 没有返回对应资源路径。请检查剧情缓存索引。")
		return false

	var return_target := "night"
	if story.return_scene != "":
		return_target = story.return_scene

	emit_signal("story_requested", story_path, return_target)
	return true


func _find_registered_story_path(target_story: StoryData) -> String:
	if target_story == null:
		return ""

	# StoryManager 已在启动时建立 StoryData -> 路径索引。
	# 这里直接 O(1) 查询，不再遍历 registered_story_paths，也不再重复 load() 剧情资源。
	if StoryManager == null or not StoryManager.has_method("get_story_path"):
		push_warning("StoryManager 缺少 get_story_path()。")
		return ""

	return String(StoryManager.get_story_path(target_story))
