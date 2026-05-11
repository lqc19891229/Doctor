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


# =========================================================
# 常量定义
# =========================================================

# 默认查看的脉象区域
const DEFAULT_DISPLAY_REGION := "浮脉"


# =========================================================
# 场景节点引用
# =========================================================

# ---------- 顶部时间显示 ----------
# 说明：
# 1. DayLabel 显示“第几天”
# 2. TimeLabel 显示“当前时辰”
# 3. 使用 find_child，避免你暂时还没在 TopBar 加 TimeLabel 时报错
@onready var day_label: Label = find_child("DayLabel", true, false) as Label
@onready var time_label: Label = find_child("TimeLabel", true, false) as Label

# ---------- 脉象窗口 ----------
@onready var pulse_window: PulseWindowUI = $PulseWindow
@onready var open_pulse_window_button: Button = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/ButtonRow/OpenPulseWindowButton

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
@onready var npc_manager = $NpcManager

# ---------- 开方窗口 ----------
@onready var open_prescription_window_button: Button = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/ButtonRow/OpenPrescriptionWindowButton
@onready var prescription_window: PrescriptionWindowUI = $PrescriptionWindow

# ---------- 行医记考 ----------
# 说明：
# 1. 这里使用 find_child，避免场景还没接好时报错
# 2. 按钮和窗口建议都挂在 NpcButtonRow 下，便于白天统一操作
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


# =========================================================
# 生命周期
# =========================================================

func _ready() -> void:
	_setup_time_system()
	_setup_prescription_window()
	_setup_clinical_log_window()
	_connect_signals()

	refresh_clinic_view()

	print("药材数量：", herb_database.get_all_herbs().size())
	formula_database.debug_print_all_formulas()


func _process(_delta: float) -> void:
	# Clinic 不在这里处理时间计时
	# 时间推进统一交给 GameTimeManager.gd

	# 只有脉象窗口打开时才处理键盘把脉逻辑
	if pulse_window != null and pulse_window.visible:
		_update_pulse_keyboard_display()


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

	# 如果脚本里有 open_window/close_window/refresh_view，则后续直接调用
	# 这里只做最基础的标题设置，避免未挂脚本时报错
	if "title" in clinical_log_window:
		clinical_log_window.title = "行医记考"


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
		print("InfoWindow 缺少信号：", signal_name)
		return

	if not target.is_connected(signal_name, callable_fn):
		target.connect(signal_name, callable_fn)


# =========================================================
# 统一刷新入口
# 切换病人 / 生成新病人后都走这里
# =========================================================

func refresh_clinic_view() -> void:
	current_npc = npc_manager.get_current_npc()
	current_prescription.clear()
	diagnosis_submitted = false
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


# =========================================================
# 病人有效性检查
# show_message = true 时会顺带更新 info_label
# =========================================================

func _ensure_current_npc_valid(show_message: bool = false) -> bool:
	if current_npc == null:
		current_npc = npc_manager.get_current_npc()

	if current_npc == null:
		if show_message:
			info_label.text = "当前没有病人数据"
			_clear_pulse()
		return false

	if current_npc.disease == null:
		if show_message:
			info_label.text = "病人：%s\n未绑定疾病数据" % current_npc.npc_name
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
	if not _ensure_current_npc_valid(true):
		return

	current_display_region_name = display_region_name

	if pulse_window == null:
		info_label.text = "脉象窗口不存在"
		return

	var result := pulse_window.show_region(display_region_name, current_npc.disease)

	if not result.get("ok", false):
		info_label.text = "病人：%s\n疾病：%s\n%s" % [
			current_npc.npc_name,
			current_npc.disease.disease_name,
			result.get("text", "")
		]
		return

	info_label.text = "病人：%s\n性别：%s  年龄：%d\n疾病：%s\n%s" % [
		current_npc.npc_name,
		current_npc.gender,
		current_npc.age,
		current_npc.disease.disease_name,
		result.get("text", "")
	]


# =========================================================
# 显示整只手的四宫格脉象
# =========================================================

func show_hand_group(hand_side: String) -> void:
	if not _ensure_current_npc_valid(true):
		return

	if pulse_window == null:
		info_label.text = "脉象窗口不存在"
		return

	var result := pulse_window.show_hand_group(hand_side, current_npc.disease)

	if not result.get("ok", false):
		info_label.text = "病人：%s\n疾病：%s\n%s" % [
			current_npc.npc_name,
			current_npc.disease.disease_name,
			result.get("text", "")
		]
		return

	info_label.text = "病人：%s\n性别：%s  年龄：%d\n疾病：%s\n%s" % [
		current_npc.npc_name,
		current_npc.gender,
		current_npc.age,
		current_npc.disease.disease_name,
		result.get("text", "")
	]


# =========================================================
# 键盘把脉
# =========================================================

func _update_pulse_keyboard_display() -> void:
	var right_cun_pressed := Input.is_action_pressed("pulse_right_cun")
	var right_guan_pressed := Input.is_action_pressed("pulse_right_guan")
	var right_chi_pressed := Input.is_action_pressed("pulse_right_chi")

	var left_cun_pressed := Input.is_action_pressed("pulse_left_cun")
	var left_guan_pressed := Input.is_action_pressed("pulse_left_guan")
	var left_chi_pressed := Input.is_action_pressed("pulse_left_chi")

	var signature := "%s%s%s|%s%s%s" % [
		"1" if right_cun_pressed else "0",
		"1" if right_guan_pressed else "0",
		"1" if right_chi_pressed else "0",
		"1" if left_cun_pressed else "0",
		"1" if left_guan_pressed else "0",
		"1" if left_chi_pressed else "0"
	]

	if signature == last_pulse_input_signature:
		return

	last_pulse_input_signature = signature

	var right_pressed_count := 0
	var left_pressed_count := 0

	if right_cun_pressed:
		right_pressed_count += 1
	if right_guan_pressed:
		right_pressed_count += 1
	if right_chi_pressed:
		right_pressed_count += 1

	if left_cun_pressed:
		left_pressed_count += 1
	if left_guan_pressed:
		left_pressed_count += 1
	if left_chi_pressed:
		left_pressed_count += 1

	var total_pressed_count := right_pressed_count + left_pressed_count

	if right_pressed_count == 3 and left_pressed_count == 0:
		pulse_keyboard_override_active = true
		show_hand_group("right")
		return

	if left_pressed_count == 3 and right_pressed_count == 0:
		pulse_keyboard_override_active = true
		show_hand_group("left")
		return

	if total_pressed_count == 1:
		pulse_keyboard_override_active = true

		if right_cun_pressed:
			show_region("右寸")
			return

		if right_guan_pressed:
			show_region("右关")
			return

		if right_chi_pressed:
			show_region("右尺")
			return

		if left_cun_pressed:
			show_region("左寸")
			return

		if left_guan_pressed:
			show_region("左关")
			return

		if left_chi_pressed:
			show_region("左尺")
			return

	if pulse_keyboard_override_active:
		pulse_keyboard_override_active = false
		show_region(current_display_region_name)


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
		info_label.text = "行医记考窗口不存在"
		print("ClinicalLogWindow 没找到，请检查节点名字和挂载位置")
		return

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


# =========================================================
# 提交处方并判定
# =========================================================

func submit_prescription() -> void:
	if current_npc == null:
		info_label.text = "当前没有病人，无法提交处方"
		return

	if current_npc.disease == null:
		info_label.text = "当前病人没有绑定疾病，无法提交处方"
		return

	if current_prescription.is_empty():
		info_label.text = "当前处方为空，请先开方"
		return

	var standard_formula := _get_current_standard_formula()
	if standard_formula == null:
		info_label.text = "未找到疾病【%s】对应的标准方" % current_npc.disease.disease_name
		return

	var result := formula_judge.judge_formula(current_prescription, standard_formula)
	diagnosis_submitted = true

	info_label.text = result.get_summary_text()
	result.debug_print()


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
# 调试函数
# 正式版可删
# =========================================================

func debug_print_current_prescription() -> void:
	current_prescription.debug_print()


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
	submit_prescription()


# =========================================================
# 脉象窗口
# =========================================================

func _on_open_pulse_window_button_pressed() -> void:
	if pulse_window == null:
		return

	pulse_window.open_window()

	show_region(current_display_region_name)
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
	info_label.text = text


# =========================================================
# 接收 PrescriptionWindow 发回的提交请求
# =========================================================

func _on_prescription_submit_requested() -> void:
	submit_prescription()


func _on_end_today_pressed() -> void:
	print("按钮被点击")
	finish_clinic_for_today()


# =========================================================
# 设置当前天数（由 Main 调用）
# =========================================================

func set_day(day: int) -> void:
	current_day = day

	# DayLabel / TimeLabel 统一从 GameTimeManager 刷新
	_update_time_ui()


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

	if info_label != null:
		info_label.text = "测试功能：已解锁全部条目\n条目：%d\n药材：%d\n方剂：%d\n疾病：%d\n医理：%d" % [
			result.get("entry_count", 0),
			result.get("herb_count", 0),
			result.get("formula_count", 0),
			result.get("disease_count", 0),
			result.get("theory_count", 0)
		]

	if clinical_log_window != null and clinical_log_window.has_method("refresh_view"):
		clinical_log_window.refresh_view()
