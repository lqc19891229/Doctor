extends Control

# =========================================================
# Clinic.gd
# 诊室主控制脚本（瘦身版）
#
# 主要职责：
# 1. 管理当前病人数据刷新
# 2. 管理脉象窗口的打开/关闭与键盘把脉逻辑
# 3. 管理开方窗口的打开/关闭
# 4. 持有当前处方数据，并接收 PrescriptionWindow 的信号
# 5. 提交处方并与标准方比较
# =========================================================


# =========================================================
# 常量定义
# =========================================================

# 默认查看的脉象区域
const DEFAULT_DISPLAY_REGION := "浮脉"


# =========================================================
# 场景节点引用
# =========================================================

# ---------- 脉象窗口 ----------
@onready var pulse_window: PulseWindowUI = $PulseWindow
@onready var open_pulse_window_button: Button = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/NpcButtonRow/OpenPulseWindowButton

# ---------- 信息显示 ----------
@onready var info_label: Label = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/InfoLabel

# ---------- 数据库 / 管理器 ----------
@onready var herb_database = $HerbDataBase
@onready var formula_database = $FormulaDataBase
@onready var npc_manager = $NpcManager

# ---------- 开方窗口 ----------
@onready var open_prescription_window_button: Button = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/NpcButtonRow/OpenPrescriptionWindowButton
@onready var prescription_window: PrescriptionWindowUI = $PrescriptionWindow


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


# =========================================================
# 生命周期
# =========================================================
func _ready() -> void:
	_setup_prescription_window()
	_connect_signals()

	refresh_clinic_view()

	print("药材数量：", herb_database.get_all_herbs().size())
	formula_database.debug_print_all_formulas()


func _process(_delta: float) -> void:
	# 只有脉象窗口打开时才处理键盘把脉逻辑
	if pulse_window != null and pulse_window.visible:
		_update_pulse_keyboard_display()


# =========================================================
# 初始化：开方窗口
# =========================================================
func _setup_prescription_window() -> void:
	if prescription_window != null:
		prescription_window.hide()


# =========================================================
# 初始化：信号连接
# =========================================================
func _connect_signals() -> void:
	_safe_connect_pressed(open_prescription_window_button, _on_open_prescription_window_button_pressed)
	_safe_connect_pressed(open_pulse_window_button, _on_open_pulse_window_button_pressed)

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


func _safe_connect_pressed(button: BaseButton, callable_fn: Callable) -> void:
	if button != null and not button.pressed.is_connected(callable_fn):
		button.pressed.connect(callable_fn)


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
# 具体区域映射和 Drawer 操作已交给 PulseWindowUI
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
# 具体区域映射和 Drawer 操作已交给 PulseWindowUI
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
# 右手：Q / A / Z
# 左手：U / J / M
# 三键同时按下时显示整手
# =========================================================
func _update_pulse_keyboard_display() -> void:
	# =========================================================
	# 读取输入动作（按“脉位语义”命名，而不是按键名命名）
	# 这样以后即使改键位，也不用再改下面的显示逻辑
	# =========================================================
	var right_cun_pressed := Input.is_action_pressed("pulse_right_cun")
	var right_guan_pressed := Input.is_action_pressed("pulse_right_guan")
	var right_chi_pressed := Input.is_action_pressed("pulse_right_chi")

	var left_cun_pressed := Input.is_action_pressed("pulse_left_cun")
	var left_guan_pressed := Input.is_action_pressed("pulse_left_guan")
	var left_chi_pressed := Input.is_action_pressed("pulse_left_chi")

	# =========================================================
	# 生成本帧输入签名
	# 作用：
	# 1. 如果本帧按键状态和上一帧完全一样，就不重复刷新显示
	# 2. 避免 _process() 每帧都重复调用 show_region()/show_hand_group()
	# =========================================================
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

	# =========================================================
	# 统计当前按下数量
	# 作用：
	# 1. 只允许“单键”或“单手三键”
	# 2. 其他混合按法一律视为无效输入
	# =========================================================
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

	# =========================================================
	# 优先级 1：单手三键 = 显示整只手
	# =========================================================
	if right_pressed_count == 3 and left_pressed_count == 0:
		pulse_keyboard_override_active = true
		show_hand_group("right")
		return

	if left_pressed_count == 3 and right_pressed_count == 0:
		pulse_keyboard_override_active = true
		show_hand_group("left")
		return

	# =========================================================
	# 优先级 2：只按了一个键 = 显示对应单脉象
	# =========================================================
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

	# =========================================================
	# 其他情况：
	# 例如：
	# 1. 同时按了左右手的键
	# 2. 按了两键但不是整手
	# 3. 全部松开
	# 都恢复到当前默认显示区域
	# =========================================================
	if pulse_keyboard_override_active:
		pulse_keyboard_override_active = false
		show_region(current_display_region_name)


func _reset_pulse_keyboard_state() -> void:
	pulse_keyboard_override_active = false
	last_pulse_input_signature = ""


# =========================================================
# 清空脉象显示
# 具体清空逻辑交给 PulseWindowUI
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
# 获取当前病人的 disease_id
# =========================================================
func _get_current_disease_id() -> String:
	if current_npc == null or current_npc.disease == null:
		return ""
	return current_npc.disease.disease_id.strip_edges()


# =========================================================
# 获取当前病人对应标准方
# 优先级：
# 1. recommended_formula_id
# 2. 根据 disease_id 查找
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
# 接收 PrescriptionWindow 发回的提示信息
# info_label 统一留在 Clinic.gd
# =========================================================
func _on_prescription_info_requested(text: String) -> void:
	info_label.text = text


# =========================================================
# 接收 PrescriptionWindow 发回的提交请求
# =========================================================
func _on_prescription_submit_requested() -> void:
	submit_prescription()
