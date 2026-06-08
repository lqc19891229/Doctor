extends Control

# =========================================================
# Clinic.gd
# 诊室主控制脚本（接入 Main 流程版）
#
# 主要职责：
# 1. 管理当前病人数据刷新
# 2. 管理脉象窗口的打开/关闭与键盘把脉逻辑
# 3. 管理开方窗口的打开/关闭
# 4. 持有当前处方数据，并接收 PrescriptionWindow 的信号
# 5. 提交处方并与标准方比较
# 6. 管理行医记考窗口的打开/关闭
# 7. 管理信息测试窗口的打开/关闭
# 8. 向 Main 发出“当天接诊结束”信号
# 9. 接入 GameTimeManager 的 Clinic 自动计时显示
# =========================================================


# =========================================================
# 对外信号
# =========================================================

# 通知 Main：Clinic 当天流程结束
signal clinic_finished

# 通知 Main：Clinic 请求播放剧情
# Clinic 不直接切换 Story 场景，避免破坏 Main 管理的主流程。
signal story_requested(story_path: String, return_target: String)


# =========================================================
# 常量定义
# =========================================================

# 默认查看的脉象区域
const DEFAULT_DISPLAY_REGION := "浮脉"

# 判定结果弹窗场景路径
const JUDGEMENT_RESULT_SCENE_PATH := "res://Scene/JudgementResult/JudgementResult.tscn"


# =========================================================
# 场景节点引用
# =========================================================

# ---------- 顶部时间显示 ----------
# 说明：
# 1. DayLabel 显示“第几天”
# 2. TimeLabel 显示“当前时辰”
@onready var day_label: Label = find_child("DayLabel", true, false) as Label
@onready var time_label: Label = find_child("TimeLabel", true, false) as Label

# ---------- 心得显示 ----------
#  这个 Label 只负责显示 UnlockManager 中保存的心得数量。
@onready var thoughts_point_label: Label = find_child("ThoughtsPoint", true, false) as Label
@onready var reputation_point_label: Label = find_child("ReputationPoint", true, false) as Label

# ---------- 脉象窗口 ----------
@onready var pulse_window: PulseWindow = find_child("PulseWindow", true, false) as PulseWindow
@onready var open_pulse_window_button: Button = find_child("OpenPulseWindowButton", true, false) as Button

# ---------- 信息测试窗口 ----------
# 说明：
# 1. info_window 仍按 Window 接收，避免 InfoWindow.gd 未注册 class_name 时报错
# 2. info_label 使用 find_child 获取，兼容以下两种结构：
#    - InfoWindow/Panel/InfoLabel
#    - InfoWindow/Panel/VBoxContainer/InfoLabel
@onready var info_window: Window = find_child("InfoWindow", true, false) as Window
@onready var info_label: Label = find_child("InfoLabel", true, false) as Label

# ---------- 数据库 / 管理器 ----------
@onready var herb_database = HerbDB
@onready var formula_database = FormulaDB
@onready var npc_manager = find_child("NpcManager", true, false)

# ---------- 开方窗口 ----------
@onready var open_prescription_window_button: Button = find_child("OpenPrescriptionWindowButton", true, false) as Button
@onready var prescription_window: PrescriptionWindow = find_child("PrescriptionWindow", true, false) as PrescriptionWindow

# ---------- 行医记考 ----------
# 说明：
# 1. 这里使用 find_child，避免场景还没接好时报错
# 2. 按钮现在位于 Clinic/VBoxContainer/ButtonRow 下；使用 find_child 兼容后续 UI 调整
@onready var clinical_log_button: Button = find_child("Openclinical_logWindowButton", true, false) as Button
@onready var clinical_log_window: ClinicalLogWindow = find_child("ClinicalLogWindow", true, false) as ClinicalLogWindow

# ---------- 结束当天 ----------
# 结束当天按钮已经转移到 InfoWindow，这里不再直接引用旧按钮


# =========================================================
# 运行时状态
# =========================================================

# 当前显示的脉诊区域（UI显示名）
var current_display_region_name: String = DEFAULT_DISPLAY_REGION

# 当前接诊病人
var current_npc: NpcData = null

# 当前诊疗流程是否已提交
var diagnosis_submitted: bool = false

# 当前玩家处方（数据仍由 Clinic 持有）
var current_prescription := Prescription.new()

# 方剂判定器
var formula_judge := FormulaJudge.new()

# 键盘把脉是否处于覆盖显示状态
var pulse_keyboard_override_active: bool = false

# 上一帧按键签名，用于避免每帧重复刷新
var last_pulse_input_signature: String = ""

# 当前天数（由 Main 注入）
var current_day: int = 1

# 防止 Clinic 结束信号重复发出
var clinic_finished_emitted: bool = false

# 上一次显示在 UI 上的心得数量
# 说明：
# - 使用这个值避免每帧重复改 Label 文本。
# - 初始设为 -1，保证进入场景后一定刷新一次。
var last_displayed_thoughts_point: int = -1

# 上一次显示在 UI 上的名望数量
# 说明：
# - 名望允许为负数，所以初始值使用一个很小的值，保证进入场景后一定刷新一次。
var last_displayed_reputation_point: int = -999999

# 最近一次处方判定结果
# 说明：
# 1. submit_prescription() 负责生成判定结果。
# 2. _on_prescription_submit_requested() 负责把结果交给 JudgementResult 场景显示。
var last_formula_judge_result = null
var last_formula_judge_summary_text: String = ""

# 当前打开的判定结果窗口
var judgement_result_window: Control = null


# =========================================================
# 生命周期
# =========================================================

func _ready() -> void:
	_validate_scene_node_bindings()
	_setup_time_system()
	_setup_prescription_window()
	_setup_clinical_log_window()
	_connect_signals()

	refresh_clinic_view()
	_update_thoughts_point_ui(true)
	_update_reputation_point_ui(true)

	# 调试输出：仅在 Debug 构建中打印数据库加载情况，避免正式版刷屏。
	if OS.is_debug_build():
		print("药材数量：", herb_database.get_all_herbs().size())
		if formula_database != null and formula_database.has_method("debug_print_all_formulas"):
			formula_database.debug_print_all_formulas()

	# 注意：不要在 _ready() 里自动触发剧情。
	# Main 还没有连接 story_requested 信号时，_ready() 发出的信号会丢失。
	# 自动剧情统一放到 start_new_day()，由 Main 连接好信号后调用。


func _process(_delta: float) -> void:
	# Clinic 不在这里处理时间计时
	# 时间推进统一交给 GameTimeManager.gd

	# 每帧检查一次心得数量。
	# 说明：
	# - 只有数量变化时才会真正改 Label 文本。
	# - 这样即使心得来自读档、调试窗口或其它脚本，也能同步到 TopBar。
	_update_thoughts_point_ui(false)
	_update_reputation_point_ui(false)

	# 只有脉象窗口打开时才处理键盘把脉逻辑
	if pulse_window != null and pulse_window.visible:
		_update_pulse_keyboard_display()


# =========================================================
# 初始化：节点绑定检查
# =========================================================

func _validate_scene_node_bindings() -> void:
	# 现在 Clinic 的 UI 结构为：
	# Clinic
	# ├─ Background
	# ├─ VBoxContainer
	# │  ├─ TopBar
	# │  ├─ Panel        # 占位用
	# │  └─ ButtonRow
	# ├─ PrescriptionWindow
	# ├─ PulseWindow
	# ├─ ClinicalLogWindow
	# ├─ InfoWindow
	# └─ NpcManager
	#
	# 这里不要再写死 DiagnosisPanel/DiagnosisLayout 路径。
	# find_child 会按节点名查找，适合当前这种 UI 结构仍在调整的阶段。
	if not OS.is_debug_build():
		return

	var required_nodes := {
		"DayLabel": day_label,
		"TimeLabel": time_label,
		"ThoughtsPoint": thoughts_point_label,
		"ReputationPoint": reputation_point_label,
		"OpenPulseWindowButton": open_pulse_window_button,
		"OpenPrescriptionWindowButton": open_prescription_window_button,
		"Openclinical_logWindowButton": clinical_log_button,
		"PulseWindow": pulse_window,
		"PrescriptionWindow": prescription_window,
		"ClinicalLogWindow": clinical_log_window,
		"InfoWindow": info_window,
		"NpcManager": npc_manager
	}

	for node_name in required_nodes.keys():
		if required_nodes[node_name] == null:
			push_warning("Clinic.gd 未找到节点：%s，请检查 Clinic.tscn 中的节点名称。" % node_name)


# =========================================================
# 初始化：Clinic 时间系统
# =========================================================

func _setup_time_system() -> void:
	# 每次进入 Clinic，都重置为辰时，并由 GameTimeManager 开始自动计时
	if GameTime.has_method("start_clinic_time"):
		GameTime.start_clinic_time()

	# 监听 GameTimeManager 的时间变化，用于刷新 TopBar
	if GameTime.has_signal("time_changed"):
		if not GameTime.time_changed.is_connected(_on_game_time_changed):
			GameTime.time_changed.connect(_on_game_time_changed)

	# 监听 GameTimeManager 发出的 Clinic 时间结束信号
	# 例如：辰、巳、午、未、申结束后自动进入夜读
	if GameTime.has_signal("clinic_time_finished"):
		if not GameTime.clinic_time_finished.is_connected(_on_clinic_time_finished):
			GameTime.clinic_time_finished.connect(_on_clinic_time_finished)

	_update_time_ui()


# =========================================================
# 刷新 TopBar 时间显示
# =========================================================

func _update_time_ui() -> void:
	# DayLabel 只显示天数
	if day_label != null:
		if GameTime.has_method("get_day_text"):
			day_label.text = GameTime.get_day_text()
		else:
			day_label.text = "第 %d 天" % current_day

	# TimeLabel 只显示当前时辰
	if time_label != null:
		if GameTime.has_method("get_shichen_text"):
			time_label.text = GameTime.get_shichen_text()
		else:
			time_label.text = "辰时"



# =========================================================
# 刷新 TopBar 心得显示
# =========================================================
func _update_thoughts_point_ui(force_refresh: bool = false) -> void:
	# 如果 Label 没找到，直接返回，避免报错。
	# 正确路径应为：Clinic/VBoxContainer/TopBar/ThoughtsPoint
	if thoughts_point_label == null:
		return

	# 读取 UnlockManager 中的心得数量。
	# 这里不用 info_label 的文本，因为 info_label 只是提示窗口，不是数据源。
	var current_points := 0	
	if Unlock != null and Unlock.has_method("get_experience_points"):
		current_points = Unlock.get_experience_points()

	# 数量没变化且不是强制刷新时，不重复改文本。
	if not force_refresh and current_points == last_displayed_thoughts_point:
		return

	last_displayed_thoughts_point = current_points

	# 强制保证 Label 可见，并给一个最小尺寸，避免在 HBoxContainer 中被压到看不见。
	thoughts_point_label.visible = true
	thoughts_point_label.custom_minimum_size = Vector2(120, 24)
	thoughts_point_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	thoughts_point_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# 最终显示文本。
	thoughts_point_label.text = "心得：%d" % current_points

# =========================================================
# 刷新 TopBar 名望显示
# =========================================================
func _update_reputation_point_ui(force_refresh: bool = false) -> void:
	# 如果 Label 没找到，直接返回，避免报错。
	# 正确路径应为：Clinic/VBoxContainer/TopBar/ReputationPoint
	if reputation_point_label == null:
		return

	var current_points := 0
	if Unlock != null and Unlock.has_method("get_reputation_points"):
		current_points = Unlock.get_reputation_points()

	if not force_refresh and current_points == last_displayed_reputation_point:
		return

	last_displayed_reputation_point = current_points

	reputation_point_label.visible = true
	reputation_point_label.custom_minimum_size = Vector2(120, 24)
	reputation_point_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	reputation_point_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	reputation_point_label.text = "名望：%d" % current_points


# =========================================================
# GameTimeManager：时间变化回调
# =========================================================

func _on_game_time_changed() -> void:
	_update_time_ui()


# =========================================================
# GameTimeManager：Clinic 时间结束回调
# =========================================================

func _on_clinic_time_finished() -> void:
	finish_clinic_for_today()


# =========================================================
# 初始化：开方窗口
# =========================================================

func _setup_prescription_window() -> void:
	if prescription_window != null:
		prescription_window.hide()


# =========================================================
# 初始化：行医记考窗口
# =========================================================

func _setup_clinical_log_window() -> void:
	if clinical_log_window == null:
		return

	clinical_log_window.hide()

# =========================================================
# 初始化：信号连接
# =========================================================

func _connect_signals() -> void:
	_safe_connect_pressed(open_prescription_window_button, _on_open_prescription_window_button_pressed)
	_safe_connect_pressed(open_pulse_window_button, _on_open_pulse_window_button_pressed)
	_safe_connect_pressed(clinical_log_button, _on_clinical_log_button_pressed)

	# ---------- 脉象窗口信号 ----------
	if pulse_window != null:
		if not pulse_window.region_selected.is_connected(_on_pulse_panel_region_selected):
			pulse_window.region_selected.connect(_on_pulse_panel_region_selected)

		if not pulse_window.close_requested.is_connected(_on_pulse_window_close_requested):
			pulse_window.close_requested.connect(_on_pulse_window_close_requested)

	# ---------- 开方窗口信号 ----------
	if prescription_window != null:
		if not prescription_window.close_requested.is_connected(_on_prescription_window_close_requested):
			prescription_window.close_requested.connect(_on_prescription_window_close_requested)

		if not prescription_window.info_requested.is_connected(_on_prescription_info_requested):
			prescription_window.info_requested.connect(_on_prescription_info_requested)

		if not prescription_window.submit_requested.is_connected(_on_prescription_submit_requested):
			prescription_window.submit_requested.connect(_on_prescription_submit_requested)

	# ---------- 信息测试窗口信号 ----------
	if info_window != null:
		if not info_window.close_requested.is_connected(_on_info_window_close_requested):
			info_window.close_requested.connect(_on_info_window_close_requested)

		# 以下四个信号由 InfoWindow.gd 中的按钮发出
		_safe_connect_custom_signal(info_window, "prev_npc_requested", _on_prev_button_pressed)
		_safe_connect_custom_signal(info_window, "next_npc_requested", _on_next_button_pressed)
		_safe_connect_custom_signal(info_window, "spawn_npc_requested", _on_spawn_npc_button_pressed)
		_safe_connect_custom_signal(info_window, "end_today_requested", _on_end_today_pressed)
		_safe_connect_custom_signal(info_window, "unlock_all_entries_requested", _on_unlock_all_entries_requested)

func _safe_connect_pressed(button: BaseButton, callable_fn: Callable) -> void:
	if button != null and not button.pressed.is_connected(callable_fn):
		button.pressed.connect(callable_fn)


func _safe_connect_custom_signal(target: Object, signal_name: StringName, callable_fn: Callable) -> void:
	# 兼容自定义 InfoWindow.gd：
	# 如果 InfoWindow 没有声明该信号，就直接跳过，避免报错。
	if target == null:
		return

	if not target.has_signal(signal_name):
		if OS.is_debug_build():
			print("InfoWindow 缺少信号：", signal_name)
		return

	if not target.is_connected(signal_name, callable_fn):
		target.connect(signal_name, callable_fn)


# =========================================================
# 通用工具函数
# =========================================================

func _set_info_text(text: String) -> void:
	# 统一写入信息窗口文本。
	# 说明：
	# 1. 其它函数不再直接访问 info_label.text，减少空节点报错风险。
	# 2. 如果 InfoLabel 暂未接入场景，则在 Debug 构建中打印，方便排查。
	if info_label != null:
		info_label.text = text
	elif OS.is_debug_build():
		print(text)


func _get_pressed_action_count(action_names: Array[StringName]) -> int:
	# 统计一组输入动作中，当前被按下的动作数量。
	# 用于键盘把脉时判断左右手三键是否同时按下。
	var pressed_count := 0
	for action_name in action_names:
		if Input.is_action_pressed(action_name):
			pressed_count += 1
	return pressed_count


func _show_pulse_result(result: Dictionary) -> void:
	# 统一处理 PulseWindow 返回的脉象显示结果。
	# 说明：
	# 1. show_region() 与 show_hand_group() 原本有重复的信息拼接。
	# 2. 这里集中生成提示文本，后续新增病人字段时只需要改一处。
	if not _ensure_current_npc_valid(true):
		return

	var result_text: String = result.get("text", "")
	if not result.get("ok", false):
		_set_info_text("病人：%s\n疾病：%s\n%s" % [
			current_npc.npc_name,
			current_npc.disease.disease_name,
			result_text
		])
		return

	_set_info_text("病人：%s\n性别：%s  年龄：%d\n疾病：%s\n%s" % [
		current_npc.npc_name,
		current_npc.gender,
		current_npc.age,
		current_npc.disease.disease_name,
		result_text
	])


# =========================================================
# 统一刷新入口
# 切换病人 / 生成新病人后都走这里
# =========================================================

func refresh_clinic_view() -> void:
	current_npc = npc_manager.get_current_npc()
	current_prescription.clear()
	diagnosis_submitted = false
	last_formula_judge_result = null
	last_formula_judge_summary_text = ""
	current_display_region_name = DEFAULT_DISPLAY_REGION

	_reset_pulse_keyboard_state()

	if not _ensure_current_npc_valid(true):
		return

	show_region(current_display_region_name)

	# 病人切换后，如果处方窗口已经存在，也同步刷新它
	if prescription_window != null:
		prescription_window.setup(herb_database, current_prescription)

	# 病人切换后，如果行医记考窗口存在，也顺手刷新一次内容
	if clinical_log_window != null and clinical_log_window.has_method("refresh_view"):
		clinical_log_window.refresh_view()

	_update_thoughts_point_ui(true)
	_update_reputation_point_ui(true)


# =========================================================
# 病人有效性检查
# show_message = true 时会顺带更新 info_label
# =========================================================

func _ensure_current_npc_valid(show_message: bool = false) -> bool:
	if current_npc == null:
		current_npc = npc_manager.get_current_npc()

	if current_npc == null:
		if show_message:
			_set_info_text("当前没有病人数据")
			_clear_pulse()
		return false

	if current_npc.disease == null:
		if show_message:
			_set_info_text("病人：%s\n未绑定疾病数据" % current_npc.npc_name)
			_clear_pulse()
		return false

	return true


# =========================================================
# 刷新当前病人显示
# =========================================================

func refresh_current_patient() -> void:
	current_npc = npc_manager.get_current_npc()

	if not _ensure_current_npc_valid(true):
		return

	show_region(current_display_region_name)


# =========================================================
# 显示单个脉象区域
# =========================================================

func show_region(display_region_name: String) -> void:
	# 显示指定名称的单个脉象区域，并同步刷新信息提示。
	if not _ensure_current_npc_valid(true):
		return

	current_display_region_name = display_region_name

	if pulse_window == null:
		_set_info_text("脉象窗口不存在")
		return

	_show_pulse_result(pulse_window.show_region(display_region_name, current_npc.disease))


# =========================================================
# 显示整只手的四宫格脉象
# =========================================================

func show_hand_group(hand_side: String) -> void:
	# 显示整只手的脉象区域，并同步刷新信息提示。
	# hand_side 建议传入 "left" 或 "right"。
	if not _ensure_current_npc_valid(true):
		return

	if pulse_window == null:
		_set_info_text("脉象窗口不存在")
		return

	_show_pulse_result(pulse_window.show_hand_group(hand_side, current_npc.disease))


# =========================================================
# 键盘把脉
# =========================================================

func _update_pulse_keyboard_display() -> void:
	# 根据键盘输入刷新把脉窗口显示。
	# 规则：
	# 1. 右手 Q/A/Z 三键全按，且左手未按时，显示右手四宫格。
	# 2. 左手 W/S/X 三键全按，且右手未按时，显示左手四宫格。
	# 3. 其它状态显示提示页，避免松键时闪过单个脉象。
	var right_actions: Array[StringName] = [
		&"pulse_right_cun",
		&"pulse_right_guan",
		&"pulse_right_chi"
	]
	var left_actions: Array[StringName] = [
		&"pulse_left_cun",
		&"pulse_left_guan",
		&"pulse_left_chi"
	]

	var signature := ""
	for action_name in right_actions + left_actions:
		signature += "1" if Input.is_action_pressed(action_name) else "0"

	if signature == last_pulse_input_signature:
		return
	last_pulse_input_signature = signature

	var right_pressed_count := _get_pressed_action_count(right_actions)
	var left_pressed_count := _get_pressed_action_count(left_actions)
	var total_pressed_count := right_pressed_count + left_pressed_count

	if right_pressed_count == 3 and left_pressed_count == 0:
		pulse_keyboard_override_active = true
		show_hand_group("right")
		return

	if left_pressed_count == 3 and right_pressed_count == 0:
		pulse_keyboard_override_active = true
		show_hand_group("left")
		return

	if pulse_keyboard_override_active or total_pressed_count != 0:
		pulse_keyboard_override_active = false
		if pulse_window != null and pulse_window.has_method("show_hint_tab"):
			pulse_window.show_hint_tab()


func _reset_pulse_keyboard_state() -> void:
	pulse_keyboard_override_active = false
	last_pulse_input_signature = ""


# =========================================================
# 清空脉象显示
# =========================================================

func _clear_pulse() -> void:
	if pulse_window != null:
		pulse_window.clear_display()


# =========================================================
# 开方窗口开关
# =========================================================

func open_prescription_window() -> void:
	if prescription_window == null:
		return

	prescription_window.setup(herb_database, current_prescription)
	prescription_window.show()
	prescription_window.grab_focus()


func close_prescription_window() -> void:
	if prescription_window == null:
		return

	prescription_window.hide()


# =========================================================
# 行医记考窗口开关
# =========================================================

func open_clinical_log_window() -> void:
	if clinical_log_window == null:
		_set_info_text("行医记考窗口不存在")
		print("ClinicalLogWindow 没找到，请检查节点名字和挂载位置")
		return

	if OS.is_debug_build():
		print("找到 ClinicalLogWindow：", clinical_log_window)

	if clinical_log_window.has_method("refresh_view"):
		clinical_log_window.refresh_view()

	if clinical_log_window.has_method("open_window"):
		clinical_log_window.open_window()
	else:
		clinical_log_window.show()
		clinical_log_window.grab_focus()


func close_clinical_log_window() -> void:
	if clinical_log_window == null:
		return

	if clinical_log_window.has_method("close_window"):
		clinical_log_window.close_window()
	else:
		clinical_log_window.hide()


# =========================================================
# 提交处方后统一关闭诊疗窗口
# =========================================================

func close_treatment_windows_after_submit() -> void:
	# 关闭把脉窗口
	# 说明：
	# 1. 优先调用 PulseWindow 自己的 close_window()，保证窗口内部状态能正确处理。
	# 2. 如果以后把脉窗口脚本没有 close_window()，则退回到 hide()，避免报错。
	if pulse_window != null:
		if pulse_window.has_method("close_window"):
			pulse_window.close_window()
		else:
			pulse_window.hide()

	# 重置键盘把脉状态。
	# 说明：
	# 防止窗口已经关闭，但 pulse_keyboard_override_active 或 last_pulse_input_signature 仍保留旧状态。
	_reset_pulse_keyboard_state()

	# 关闭开方窗口
	close_prescription_window()

	# 关闭行医记考窗口
	close_clinical_log_window()


# =========================================================
# 信息测试窗口开关
# =========================================================

func open_info_window() -> void:
	if info_window == null:
		return

	info_window.popup_centered()
	info_window.grab_focus()


func close_info_window() -> void:
	if info_window == null:
		return

	info_window.hide()


# =========================================================
# 获取当前病人的 disease_id
# =========================================================

func _get_current_disease_id() -> String:
	if current_npc == null or current_npc.disease == null:
		return ""
	return current_npc.disease.disease_id.strip_edges()


# =========================================================
# 获取当前病人对应标准方
# =========================================================

func _get_current_standard_formula() -> FormulaData:
	if current_npc == null or current_npc.disease == null:
		return null

	var recommended_formula_id := current_npc.disease.recommended_formula_id.strip_edges()
	if recommended_formula_id != "":
		var recommended_formula = formula_database.get_formula_by_id(recommended_formula_id)
		if recommended_formula != null:
			return recommended_formula

	var disease_id := _get_current_disease_id()
	if disease_id == "":
		return null

	var formula_list = formula_database.get_formulas_by_disease(disease_id)
	if formula_list.is_empty():
		return null

	return formula_list[0]

func _get_reputation_reward_by_judge_result(result) -> int:
	if result == null:
		return 0

	var grade := ""
	var raw_grade = result.get("grade")
	if raw_grade != null:
		grade = str(raw_grade).strip_edges()

	match grade:
		"妙手回春":
			return 10
		"甲等":
			return 5
		"乙等":
			return 1
		"丙等":
			return 0
		"丁等":
			return -10
		_:
			return 0



# =========================================================
# 提交处方并判定
# =========================================================

func submit_prescription() -> bool:
	if current_npc == null:
		_set_info_text("当前没有病人，无法提交处方")
		return false

	if current_npc.disease == null:
		_set_info_text("当前病人没有绑定疾病，无法提交处方")
		return false

	if current_prescription.is_empty():
		_set_info_text("当前处方为空，请先开方")
		return false

	var standard_formula := _get_current_standard_formula()
	if standard_formula == null:
		_set_info_text("未找到疾病【%s】对应的标准方" % current_npc.disease.disease_name)
		return false

	var was_already_submitted := diagnosis_submitted
	var result := formula_judge.judge_formula(current_prescription, standard_formula, current_npc.disease)
	diagnosis_submitted = true

	var summary_text := result.get_summary_text()
	last_formula_judge_result = result
	last_formula_judge_summary_text = summary_text

	# 提交判定后根据评级改变名望。
	# was_already_submitted 用于防止同一名病人重复提交刷名望。
	var reputation_reward := _get_reputation_reward_by_judge_result(result)
	if reputation_reward != 0 and not was_already_submitted:
		if Unlock != null and Unlock.has_method("add_reputation_points"):
			Unlock.add_reputation_points(reputation_reward)
			_update_reputation_point_ui(true)

			if reputation_reward > 0:
				summary_text += "\n获得名望：+%d" % reputation_reward
			else:
				summary_text += "\n损失名望：%d" % reputation_reward

			if Unlock.has_method("get_reputation_points"):
				summary_text += "\n当前名望：%d" % Unlock.get_reputation_points()

			if SaveManager != null and SaveManager.has_method("save_game"):
				SaveManager.save_game()
	elif reputation_reward != 0 and was_already_submitted:
		summary_text += "\n本病人已提交过处方，不重复改变名望。"
		if Unlock != null and Unlock.has_method("get_reputation_points"):
			summary_text += "\n当前名望：%d" % Unlock.get_reputation_points()

	# 妙手回春时获得 1 点心得，并立刻按累计心得自动解锁条目。
	# was_already_submitted 用于防止同一名病人重复提交刷心得。
	var is_miaoshouhuichun := false
	if result != null and result.has_method("is_miaoshouhuichun"):
		is_miaoshouhuichun = result.is_miaoshouhuichun()
	else:
		is_miaoshouhuichun = result.grade == "妙手回春" and result.score == 100

	if is_miaoshouhuichun and not was_already_submitted:
		var newly_unlocked_titles: Array[String] = []
		if Unlock != null and Unlock.has_method("add_experience_point"):
			newly_unlocked_titles = Unlock.add_experience_point(1)

		_update_thoughts_point_ui(true)
		summary_text += "\n获得心得：+1"
		summary_text += "\n当前累计心得：%d" % Unlock.get_experience_points()

		if not newly_unlocked_titles.is_empty():
			summary_text += "\n新解锁条目：%s" % "、".join(newly_unlocked_titles)

		if clinical_log_window != null and clinical_log_window.has_method("refresh_view"):
			clinical_log_window.refresh_view()

		# 获得心得和自动解锁后立即存档，避免切场景或退出时丢失。
		if SaveManager != null and SaveManager.has_method("save_game"):
			SaveManager.save_game()
	elif is_miaoshouhuichun and was_already_submitted:
		_update_thoughts_point_ui(true)
		summary_text += "\n本病人已提交过处方，不重复获得心得。"
		summary_text += "\n当前累计心得：%d" % Unlock.get_experience_points()

	last_formula_judge_summary_text = summary_text

	_set_info_text(summary_text)
	if OS.is_debug_build():
		result.debug_print()
	return true

# =========================================================
# 判定结果窗口
# =========================================================

func _show_judgement_result_window(judge_result = null, summary_text: String = "") -> void:
	# 提交成功后，弹出专门的 JudgementResult 场景。
	# 玩家点击任意位置关闭该场景后，再刷新到下一名病人。
	if judgement_result_window != null and is_instance_valid(judgement_result_window):
		judgement_result_window.queue_free()
		judgement_result_window = null

	if not ResourceLoader.exists(JUDGEMENT_RESULT_SCENE_PATH):
		_set_info_text("未找到判定结果场景：%s\n%s" % [
			JUDGEMENT_RESULT_SCENE_PATH,
			summary_text
		])
		_go_to_next_patient_after_judgement()
		return

	var packed_scene := load(JUDGEMENT_RESULT_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_set_info_text("判定结果场景加载失败：%s\n%s" % [
			JUDGEMENT_RESULT_SCENE_PATH,
			summary_text
		])
		_go_to_next_patient_after_judgement()
		return

	judgement_result_window = packed_scene.instantiate() as Control
	if judgement_result_window == null:
		_set_info_text("判定结果场景根节点必须继承 Control。\n%s" % summary_text)
		_go_to_next_patient_after_judgement()
		return

	add_child(judgement_result_window)

	if not judgement_result_window.tree_exited.is_connected(_on_judgement_result_window_closed):
		judgement_result_window.tree_exited.connect(
			_on_judgement_result_window_closed,
			Object.CONNECT_ONE_SHOT
		)

	var result_data := _build_judgement_result_data(judge_result, summary_text)

	if judgement_result_window.has_method("show_result"):
		judgement_result_window.call("show_result", result_data)
	else:
		# 兜底：如果 JudgementResult.gd 还没有 show_result()，至少把场景显示出来。
		judgement_result_window.visible = true


func _build_judgement_result_data(judge_result = null, summary_text: String = "") -> Dictionary:
	# JudgementResult 只负责显示，这里把当前病人、标准方和玩家输入整理成文本。
	var npc_name := ""
	var disease_name := ""
	var standard_formula_name := ""
	var standard_formula_text := ""
	var player_disease_name := ""
	var player_prescription_text := ""
	var grade := ""
	var total_score := 0

	if current_npc != null:
		npc_name = current_npc.npc_name
		if current_npc.disease != null:
			disease_name = current_npc.disease.disease_name

	var standard_formula := _get_current_standard_formula()
	if standard_formula != null:
		standard_formula_name = standard_formula.formula_name
		standard_formula_text = _build_standard_formula_display_text(standard_formula)
	else:
		standard_formula_text = "（未找到标准方）"

	if current_prescription != null:
		player_disease_name = current_prescription.disease_name.strip_edges()
		if player_disease_name == "":
			player_disease_name = current_prescription.disease_id.strip_edges()
		if player_disease_name == "":
			player_disease_name = "未选择疾病"
		player_prescription_text = current_prescription.get_display_text()
	else:
		player_disease_name = "未选择疾病"
		player_prescription_text = "（无）"

	if judge_result != null:
		var raw_grade = judge_result.get("grade")
		if raw_grade != null:
			grade = str(raw_grade)

		var raw_score = judge_result.get("score")
		if raw_score != null:
			total_score = int(raw_score)

	return {
		"npc_name": npc_name,
		"disease_name": disease_name,
		"standard_formula_name": standard_formula_name,
		"standard_formula_text": standard_formula_text,
		"player_disease_name": player_disease_name,
		"player_prescription_text": player_prescription_text,
		"grade": grade,
		"total_score": total_score,
		"summary_text": summary_text
	}


func _build_standard_formula_display_text(formula: FormulaData) -> String:
	if formula == null:
		return "（无）"

	var lines: Array[String] = []
	lines.append("君：" + _build_formula_group_display_text(formula.jun_group))
	lines.append("臣：" + _build_formula_group_display_text(formula.chen_group))
	lines.append("佐：" + _build_formula_group_display_text(formula.zuo_group))
	lines.append("使：" + _build_formula_group_display_text(formula.shi_group))
	return "\n".join(lines)


func _build_formula_group_display_text(group: Array) -> String:
	if group.is_empty():
		return "（无）"

	var parts: Array[String] = []
	for ingredient in group:
		if ingredient == null:
			continue
		if ingredient.has_method("is_valid_data") and not ingredient.is_valid_data():
			continue

		var herb_name := ""
		var amount_text := ""

		if ingredient.has_method("get_herb_name"):
			herb_name = str(ingredient.get_herb_name()).strip_edges()
		if herb_name == "" and ingredient.has_method("get_herb_id"):
			herb_name = str(ingredient.get_herb_id()).strip_edges()

		if ingredient.has_method("get_amount_in_fen"):
			amount_text = HerbUnit.format_fen_auto(int(ingredient.get_amount_in_fen()))

		if herb_name == "":
			continue
		if amount_text == "":
			parts.append(herb_name)
		else:
			parts.append("%s %s" % [herb_name, amount_text])

	if parts.is_empty():
		return "（无）"
	return "、".join(parts)


func _on_judgement_result_window_closed() -> void:
	judgement_result_window = null

	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false

	if is_inside_tree():
		_go_to_next_patient_after_judgement()


func _go_to_next_patient_after_judgement() -> void:
	if npc_manager != null:
		npc_manager.spawn_random_npc()
		refresh_clinic_view()


# =========================================================
# 结束当天接诊
# 作用：
# 1. 停止 Clinic 自动计时
# 2. 告诉 Main：Clinic 已完成当前阶段
# 3. 后面 Main 收到后可切到 Bookshelf / 夜晚流程
# =========================================================

func finish_clinic_for_today() -> void:
	# 防止时间结束和按钮点击同时触发，导致重复切场景
	if clinic_finished_emitted:
		return

	clinic_finished_emitted = true

	# Clinic 结束时停止 GameTimeManager 里的 Clinic 计时器
	if GameTime.has_method("stop_clinic_clock"):
		GameTime.stop_clinic_clock()

	print("Clinic 发出 clinic_finished")
	emit_signal("clinic_finished")

# =========================================================
# 病人切换按钮
# =========================================================

func _on_prev_button_pressed() -> void:
	npc_manager.prev_npc()
	refresh_clinic_view()


func _on_next_button_pressed() -> void:
	npc_manager.next_npc()
	refresh_clinic_view()


func _on_spawn_npc_button_pressed() -> void:
	npc_manager.spawn_random_npc()
	refresh_clinic_view()


func _on_submit_button_pressed() -> void:
	# 兼容旧提交按钮。当前主要由 PrescriptionWindow 的 submit_requested 信号触发。
	submit_prescription()


# =========================================================
# 脉象窗口
# =========================================================

func _on_open_pulse_window_button_pressed() -> void:
	if pulse_window == null:
		return

	# 打开脉诊窗口时，只显示按键提示页。
	# 不再自动调用 show_region()，避免窗口一打开就跳到脉象图。
	pulse_window.open_window()

	if pulse_window.has_method("show_hint_tab"):
		pulse_window.show_hint_tab()

	last_pulse_input_signature = ""


func _on_pulse_panel_region_selected(display_region_name: String) -> void:
	pulse_keyboard_override_active = false
	show_region(display_region_name)


func _on_pulse_window_close_requested() -> void:
	pulse_window.close_window()
	_reset_pulse_keyboard_state()


# =========================================================
# 开方窗口
# =========================================================

func _on_open_prescription_window_button_pressed() -> void:
	open_prescription_window()


func _on_prescription_window_close_requested() -> void:
	close_prescription_window()


# =========================================================
# 行医记考窗口
# =========================================================

func _on_clinical_log_button_pressed() -> void:
	open_clinical_log_window()


# =========================================================
# 信息测试窗口
# =========================================================

func _on_info_window_close_requested() -> void:
	close_info_window()


# =========================================================
# 接收 PrescriptionWindow 发回的提示信息
# =========================================================

func _on_prescription_info_requested(text: String) -> void:
	_set_info_text(text)


# =========================================================
# 接收 PrescriptionWindow 发回的提交请求
# =========================================================

func _on_prescription_submit_requested() -> void:
	# 接收开方窗口的提交请求。
	# 只有处方成功判定后，才关闭治疗窗口并弹出 JudgementResult。
	# 玩家点击任意位置关闭 JudgementResult 后，再刷新到下一名随机病人。
	if not submit_prescription():
		return

	close_treatment_windows_after_submit()
	_show_judgement_result_window(last_formula_judge_result, last_formula_judge_summary_text)


func _on_end_today_pressed() -> void:
	# InfoWindow 中“结束当天”按钮的回调。
	finish_clinic_for_today()


# =========================================================
# 设置当前天数（由 Main 调用）
# =========================================================

func set_day(day: int) -> void:
	current_day = day

	# DayLabel / TimeLabel 统一从 GameTimeManager 刷新
	_update_time_ui()
	_update_thoughts_point_ui(true)
	_update_reputation_point_ui(true)


# =========================================================
# 快捷键输入
# Ctrl + T 打开信息测试窗口
# =========================================================

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		# 只在按下瞬间触发，避免长按重复弹出
		if event.pressed and not event.echo:
			# 判断是否按下 Ctrl + T
			if event.ctrl_pressed and event.keycode == KEY_T:
				open_info_window()

# =========================================================
# 测试功能：一键解锁所有条目
# =========================================================
func _on_unlock_all_entries_requested() -> void:
	var result: Dictionary = Unlock.unlock_all_entries_for_test()

	_set_info_text("测试功能：已解锁全部条目\n条目：%d\n药材：%d\n方剂：%d\n疾病：%d\n医理：%d" % [
		result.get("entry_count", 0),
		result.get("herb_count", 0),
		result.get("formula_count", 0),
		result.get("disease_count", 0),
		result.get("theory_count", 0)
	])

	if clinical_log_window != null and clinical_log_window.has_method("refresh_view"):
		clinical_log_window.refresh_view()


# =========================================================
# 剧情系统入口
# 说明：
# 1. Clinic 只负责在合适时机请求剧情。
# 2. 剧情是否满足触发条件，统一交给 StoryManager 判断。
# 3. Clinic 仍然通过 story_requested 通知 Main 切换到 Story.tscn。
# 4. 为了兼容你现在的 Main.gd，这里仍然传 story_path，不传空路径。
# =========================================================

func start_story_from_clinic(story_path: String, return_target: String = "clinic") -> void:
	# story_path 示例：res://Data/Story/teaching_test.tres
	# Clinic 不直接切换 Story 场景，只向 Main 发出请求。
	# return_target 使用逻辑名，例如："clinic" / "night"。
	if story_path.is_empty():
		push_warning("Clinic.start_story_from_clinic 收到空剧情路径。")
		return

	emit_signal("story_requested", story_path, return_target)

func start_new_day(day: int) -> void:
	# 记录当前天数。
	current_day = day

	# 每天开始时，允许 Clinic 结束信号重新发出。
	# 否则第一天结束后，第二天可能无法再次进入夜晚流程。
	clinic_finished_emitted = false

	# 刷新时间、心得和名望显示。
	_update_time_ui()
	_update_thoughts_point_ui(true)
	_update_reputation_point_ui(true)

	# 自动剧情触发入口.
	# 具体触发条件不再写死在 Clinic.gd，改由 StoryData + StoryManager 决定。
	_try_start_auto_story("clinic", current_day)


func _try_start_auto_story(trigger_scene: String, day: int) -> bool:
	# StoryManager 没有接好时，直接跳过，避免阻塞诊室流程。
	if StoryManager == null:
		push_warning("Clinic 无法访问 StoryManager。")
		return false

	# 需要使用之前修改过的 StoryManager.gd。
	# 其中必须包含 find_trigger_story(trigger_scene, current_day)。
	if not StoryManager.has_method("find_trigger_story"):
		push_warning("StoryManager 缺少 find_trigger_story()，无法自动检查剧情触发条件。")
		return false

	# 让 StoryManager 统一检查是否有满足条件的剧情。
	var story: StoryData = StoryManager.find_trigger_story(trigger_scene, day)
	if story == null:
		return false

	# 找到这个 StoryData 对应的资源路径。
	# 这样可以继续兼容 Main.gd 当前的 story_requested(story_path, return_target) 逻辑。
	var story_path := _find_registered_story_path(story)
	if story_path.is_empty():
		push_warning("找到可触发剧情，但没有找到对应资源路径。请检查 StoryManager.registered_story_paths。")
		return false

	# 优先使用 StoryData 自己配置的 return_scene。
	# 如果没有配置，就默认返回 clinic。
	var return_target := "clinic"
	if story.return_scene != "":
		return_target = story.return_scene

	# 仍然只发信号给 Main，不在 Clinic 里直接切换场景。
	start_story_from_clinic(story_path, return_target)
	return true


func _find_registered_story_path(target_story: StoryData) -> String:
	# 从 StoryManager.registered_story_paths 中反查剧情资源路径。
	# 这样自动触发仍然由 StoryManager 管理剧情列表。
	if target_story == null:
		return ""

	# 如果 StoryManager 还没有 registered_story_paths，说明使用的不是新版 StoryManager。
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

		# Godot 资源通常会被缓存，同一路径加载到的是同一个资源实例。
		# 这里先用实例比较，最直接。
		if story == target_story:
			return story_path

		# 如果实例比较失败，就用 story_id 再兜底比较。
		var target_story_id: String = target_story.get("story_id")
		var current_story_id: String = story.get("story_id")
		if not target_story_id.is_empty() and target_story_id == current_story_id:
			return story_path

	return ""
