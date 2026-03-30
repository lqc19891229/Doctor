extends Control

# =========================================================
# Clinic.gd
# 诊室主场景控制器
#
# 本版新增：
# 1. 保留原有按钮点选脉象逻辑
# 2. 新增键盘把脉逻辑：
#    - Q = 右寸
#    - A = 右关
#    - Z = 右尺
#    - U = 左寸
#    - J = 左关
#    - M = 左尺
# 3. 当同时按下 Q+A+Z 时：
#    PulseDrawer 四等分显示 [表, 右寸, 右关, 右尺]
# 4. 当同时按下 U+J+M 时：
#    PulseDrawer 四等分显示 [表, 左寸, 左关, 左尺]
# 5. 松开组合键后，恢复到之前按钮选中的单脉象显示
# =========================================================

@onready var pulse_window: Window = $PulseWindow
@onready var pulse_panel = $PulseWindow/PulsePanel
@onready var pulse_drawer = $PulseWindow/PulsePanel/PulsePanelLayout/PulseDrawer
@onready var open_pulse_window_button: Button = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/NpcButtonRow/OpenPulseWindowButton
@onready var info_label: Label = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/InfoLabel
@onready var herb_database = $HerbDataBase
@onready var formula_database = $FormulaDataBase
@onready var npc_manager = $NpcManager

# =========================
# 开方 UI 节点
# =========================
@onready var herb_list: ItemList = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/HerbSelectRow/HerbList
@onready var amount_input: LineEdit = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/HerbSelectRow/HerbEditColumn/AmountInput
@onready var unit_option: OptionButton = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/HerbSelectRow/HerbEditColumn/UnitOption
@onready var add_herb_button: Button = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/HerbSelectRow/HerbEditColumn/AddHerbButton

# 四个区域列表
@onready var jun_list: ItemList = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/RoleContainer/JunPanel/VBoxContainer/JunList
@onready var chen_list: ItemList = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/RoleContainer/ChenPanel/VBoxContainer/ChenList
@onready var zuo_list: ItemList = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/RoleContainer/ZuoPanel/VBoxContainer/ZuoList
@onready var shi_list: ItemList = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/RoleContainer/ShiPanel/VBoxContainer/ShiList

@onready var jun_panel: Control = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/RoleContainer/JunPanel
@onready var chen_panel: Control = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/RoleContainer/ChenPanel
@onready var zuo_panel: Control = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/RoleContainer/ZuoPanel
@onready var shi_panel: Control = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/RoleContainer/ShiPanel

@onready var remove_herb_button: Button = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/PrescriptionActionRow/RemoveHerbButton
@onready var clear_prescription_button: Button = $VBoxContainer/DiagnosisPanel/DiagnosisLayout/PrescriptionLayout/PrescriptionView/PrescriptionActionRow/ClearPrescriptionButton

# 当前显示的脉诊区域名称（UI显示名）
var current_display_region_name: String = "浮脉"

# 当前接诊的病人
var current_npc: NpcData = null

# 当前诊疗流程是否已经提交
var diagnosis_submitted: bool = false

# 当前玩家处方
var current_prescription := Prescription.new()

# 方剂判定器
var formula_judge := FormulaJudge.new()

# 当前选中的配伍区域，默认君区
var current_selected_role: String = "君"

# =========================================================
# 键盘把脉状态
# =========================================================
var pulse_keyboard_override_active: bool = false
var last_pulse_input_signature: String = ""


func _ready() -> void:
	refresh_clinic_view()

	# 初始化开方 UI
	_setup_unit_option()
	_refresh_herb_list()
	_refresh_prescription_list()

	# 打开脉象窗口
	open_pulse_window_button.pressed.connect(_on_open_pulse_window_button_pressed)
	pulse_panel.region_selected.connect(_on_pulse_panel_region_selected)

	# 连接按钮逻辑
	add_herb_button.pressed.connect(_on_add_herb_button_pressed)
	remove_herb_button.pressed.connect(_on_remove_herb_button_pressed)
	clear_prescription_button.pressed.connect(_on_clear_prescription_button_pressed)

	# 四个区域点击选择
	jun_list.item_selected.connect(_on_jun_list_item_selected)
	chen_list.item_selected.connect(_on_chen_list_item_selected)
	zuo_list.item_selected.connect(_on_zuo_list_item_selected)
	shi_list.item_selected.connect(_on_shi_list_item_selected)

	# 空白点击时也切换当前区域
	jun_list.gui_input.connect(_on_jun_list_gui_input)
	chen_list.gui_input.connect(_on_chen_list_gui_input)
	zuo_list.gui_input.connect(_on_zuo_list_gui_input)
	shi_list.gui_input.connect(_on_shi_list_gui_input)

	# 默认选中君区
	_set_selected_role("君")

	print("药材数量：", herb_database.get_all_herbs().size())
	formula_database.debug_print_all_formulas()


func _process(_delta: float) -> void:
	# 只有脉象窗口打开时才检测键盘把脉
	if pulse_window != null and pulse_window.visible:
		_update_pulse_keyboard_display()


# =========================================================
# 统一刷新入口
# =========================================================
func refresh_clinic_view() -> void:
	current_npc = npc_manager.get_current_npc()
	current_prescription.clear()
	diagnosis_submitted = false
	_set_selected_role("君")

	# 刷新病人后，重置键盘状态
	pulse_keyboard_override_active = false
	last_pulse_input_signature = ""

	if current_npc == null:
		info_label.text = "当前没有病人数据"
		_clear_pulse()
		_refresh_prescription_list()
		return

	show_region(current_display_region_name)
	_refresh_prescription_list()


# =========================================================
# 设置当前选中区域
# =========================================================
func _set_selected_role(role_name: String) -> void:
	current_selected_role = role_name
	_refresh_role_highlight()


# =========================================================
# 刷新区域高亮
# 这里用 modulate 做简单高亮
# =========================================================
func _refresh_role_highlight() -> void:
	jun_panel.modulate = Color(0.35, 0.35, 0.35, 1.0)
	chen_panel.modulate = Color(0.35, 0.35, 0.35, 1.0)
	zuo_panel.modulate = Color(0.35, 0.35, 0.35, 1.0)
	shi_panel.modulate = Color(0.35, 0.35, 0.35, 1.0)

	match current_selected_role:
		"君":
			jun_panel.modulate = Color(0.95, 0.85, 0.45, 1.0)
		"臣":
			chen_panel.modulate = Color(0.95, 0.85, 0.45, 1.0)
		"佐":
			zuo_panel.modulate = Color(0.95, 0.85, 0.45, 1.0)
		"使":
			shi_panel.modulate = Color(0.95, 0.85, 0.45, 1.0)


# =========================================================
# UI显示名称 -> DiseaseData 内部区域名称
# =========================================================
func get_disease_region_name(display_region_name: String) -> String:
	match display_region_name:
		"浮脉":
			return "表"
		"左寸":
			return "心"
		"左关":
			return "肝"
		"左尺":
			return "肾阴"
		"右寸":
			return "肺"
		"右关":
			return "脾"
		"右尺":
			return "肾阳"
		_:
			return ""


# =========================================================
# UI显示名称 -> Drawer 区域 id
# =========================================================
func get_region_id_by_display_name(display_region_name: String) -> String:
	match display_region_name:
		"浮脉":
			return "exterior"
		"左寸":
			return "heart"
		"左关":
			return "liver"
		"左尺":
			return "kidney_yin"
		"右寸":
			return "lung"
		"右关":
			return "spleen"
		"右尺":
			return "kidney_yang"
		_:
			return ""


# =========================================================
# 刷新当前病人显示
# =========================================================
func refresh_current_patient() -> void:
	current_npc = npc_manager.get_current_npc()
	var npc: NpcData = current_npc

	if npc == null:
		info_label.text = "当前没有病人数据"
		_clear_pulse()
		return

	if npc.disease == null:
		info_label.text = "病人：%s\n未绑定疾病数据" % npc.npc_name
		_clear_pulse()
		return

	show_region(current_display_region_name)


# =========================================================
# 显示指定脉诊区域（单脉象）
# =========================================================
func show_region(display_region_name: String) -> void:
	var npc: NpcData = current_npc

	if npc == null:
		npc = npc_manager.get_current_npc()
		current_npc = npc

	if npc == null:
		info_label.text = "当前没有病人数据"
		_clear_pulse()
		return

	if npc.disease == null:
		info_label.text = "病人：%s\n未绑定疾病数据" % npc.npc_name
		_clear_pulse()
		return

	current_display_region_name = display_region_name

	var disease_region_name := get_disease_region_name(display_region_name)

	if disease_region_name == "":
		info_label.text = "未知脉诊区域：" + display_region_name
		_clear_pulse()
		return

	var region_data := npc.disease.get_region_pulse_values(disease_region_name)

	if region_data.is_empty():
		info_label.text = "病人：%s\n疾病：%s\n当前部位：%s\n对应区域：%s\n未找到区域数据" % [
			npc.npc_name,
			npc.disease.disease_name,
			display_region_name,
			disease_region_name
		]
		_clear_pulse()
		return

	pulse_drawer.set_pulse_regions(
		npc.disease.get_pulse_regions_for_drawer_visual()
	)

	var region_id := get_region_id_by_display_name(display_region_name)
	if region_id != "":
		pulse_drawer.set_region(region_id)

	info_label.text = "病人：%s\n性别：%s  年龄：%d\n疾病：%s\n当前查看：%s\n对应区域：%s\n气：%s  血：%s  寒热：%s  湿燥：%s" % [
		npc.npc_name,
		npc.gender,
		npc.age,
		npc.disease.disease_name,
		display_region_name,
		disease_region_name,
		region_data.get("qi", 0.0),
		region_data.get("blood", 0.0),
		region_data.get("cold_hot", 0.0),
		region_data.get("wet_dry", 0.0)
	]

	print("当前病人：", npc.npc_name, " | 查看部位：", display_region_name, " | 疾病区域：", disease_region_name)


# =========================================================
# 显示一整只手的四宫格脉象
# hand_side:
# "left"  -> [表, 左寸, 左关, 左尺]
# "right" -> [表, 右寸, 右关, 右尺]
# =========================================================
func show_hand_group(hand_side: String) -> void:
	var npc: NpcData = current_npc

	if npc == null:
		npc = npc_manager.get_current_npc()
		current_npc = npc

	if npc == null:
		info_label.text = "当前没有病人数据"
		_clear_pulse()
		return

	if npc.disease == null:
		info_label.text = "病人：%s\n未绑定疾病数据" % npc.npc_name
		_clear_pulse()
		return

	var region_ids: Array[String] = []
	var display_names: Array[String] = []
	var disease_names: Array[String] = []

	if hand_side == "right":
		region_ids = ["exterior", "lung", "spleen", "kidney_yang"]
		display_names = ["浮脉", "右寸", "右关", "右尺"]
		disease_names = ["表", "肺", "脾", "肾阳"]
	else:
		region_ids = ["exterior", "heart", "liver", "kidney_yin"]
		display_names = ["浮脉", "左寸", "左关", "左尺"]
		disease_names = ["表", "心", "肝", "肾阴"]

	pulse_drawer.set_pulse_regions(
		npc.disease.get_pulse_regions_for_drawer_visual()
	)
	pulse_drawer.set_group_regions(region_ids)

	info_label.text = "病人：%s\n性别：%s  年龄：%d\n疾病：%s\n当前查看：%s手整手脉象\n显示顺序：%s / %s / %s / %s\n对应区域：%s / %s / %s / %s" % [
		npc.npc_name,
		npc.gender,
		npc.age,
		npc.disease.disease_name,
		"右" if hand_side == "right" else "左",
		display_names[0],
		display_names[1],
		display_names[2],
		display_names[3],
		disease_names[0],
		disease_names[1],
		disease_names[2],
		disease_names[3]
	]


# =========================================================
# 键盘把脉：
# 右手：
# Q = 右寸, A = 右关, Z = 右尺
# Q+A+Z = 右手四宫格
#
# 左手：
# U = 左寸, J = 左关, M = 左尺
# U+J+M = 左手四宫格
# =========================================================
func _update_pulse_keyboard_display() -> void:
	var q_pressed := Input.is_key_pressed(KEY_Q)
	var a_pressed := Input.is_key_pressed(KEY_A)
	var z_pressed := Input.is_key_pressed(KEY_Z)

	var u_pressed := Input.is_key_pressed(KEY_U)
	var j_pressed := Input.is_key_pressed(KEY_J)
	var m_pressed := Input.is_key_pressed(KEY_M)

	# 生成一个简单签名，避免每帧重复刷新
	var signature := "%s%s%s|%s%s%s" % [
		"1" if q_pressed else "0",
		"1" if a_pressed else "0",
		"1" if z_pressed else "0",
		"1" if u_pressed else "0",
		"1" if j_pressed else "0",
		"1" if m_pressed else "0"
	]

	if signature == last_pulse_input_signature:
		return

	last_pulse_input_signature = signature

	# -------------------------------------------------
	# 三键优先：右手整手
	# -------------------------------------------------
	if q_pressed and a_pressed and z_pressed:
		pulse_keyboard_override_active = true
		show_hand_group("right")
		return

	# -------------------------------------------------
	# 三键优先：左手整手
	# -------------------------------------------------
	if u_pressed and j_pressed and m_pressed:
		pulse_keyboard_override_active = true
		show_hand_group("left")
		return

	# -------------------------------------------------
	# 单键：右手
	# 这里用优先级避免多键乱跳
	# -------------------------------------------------
	if q_pressed and not a_pressed and not z_pressed and not u_pressed and not j_pressed and not m_pressed:
		pulse_keyboard_override_active = true
		show_region("右寸")
		return

	if a_pressed and not q_pressed and not z_pressed and not u_pressed and not j_pressed and not m_pressed:
		pulse_keyboard_override_active = true
		show_region("右关")
		return

	if z_pressed and not q_pressed and not a_pressed and not u_pressed and not j_pressed and not m_pressed:
		pulse_keyboard_override_active = true
		show_region("右尺")
		return

	# -------------------------------------------------
	# 单键：左手
	# -------------------------------------------------
	if u_pressed and not q_pressed and not a_pressed and not z_pressed and not j_pressed and not m_pressed:
		pulse_keyboard_override_active = true
		show_region("左寸")
		return

	if j_pressed and not q_pressed and not a_pressed and not z_pressed and not u_pressed and not m_pressed:
		pulse_keyboard_override_active = true
		show_region("左关")
		return

	if m_pressed and not q_pressed and not a_pressed and not z_pressed and not u_pressed and not j_pressed:
		pulse_keyboard_override_active = true
		show_region("左尺")
		return

	# -------------------------------------------------
	# 没有符合规则的按法：
	# 如果刚刚处于键盘覆盖状态，则恢复到当前按钮/最后一次单脉象状态
	# -------------------------------------------------
	if pulse_keyboard_override_active:
		pulse_keyboard_override_active = false
		show_region(current_display_region_name)


# =========================================================
# 清空脉象显示
# =========================================================
func _clear_pulse() -> void:
	if pulse_drawer != null:
		if pulse_drawer.has_method("clear_display"):
			pulse_drawer.clear_display()

		if pulse_drawer.has_method("set_pulse_values"):
			pulse_drawer.set_pulse_values(0.0, 0.0, 1.0, 10.0)


# =========================================================
# 获取当前病人的 disease_id
# =========================================================
func _get_current_disease_id() -> String:
	if current_npc == null:
		return ""

	if current_npc.disease == null:
		return ""

	return current_npc.disease.disease_id.strip_edges()


# =========================================================
# 获取当前病人对应的标准方
# 优先级：
# 1. disease.recommended_formula_id
# 2. FormulaDataBase.get_formulas_by_disease(disease_id)
# =========================================================
func _get_current_standard_formula() -> FormulaData:
	if current_npc == null:
		return null

	if current_npc.disease == null:
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
# 清空当前玩家处方
# =========================================================
func clear_current_prescription() -> void:
	current_prescription.clear()
	_refresh_prescription_list()
	print("当前处方已清空")


# =========================================================
# 按 herb_id 添加药材
# =========================================================
func add_herb_by_id(herb_id: String, amount: float, unit: String = "qian") -> bool:
	var herb = herb_database.get_herb_by_id(herb_id)

	if herb == null:
		push_warning("Clinic.add_herb_by_id: 未找到药材 -> " + herb_id)
		return false

	return add_herb_to_prescription(herb, amount, unit)


# =========================================================
# 直接添加 HerbData 到当前处方
# 当前会加入到 current_selected_role 对应区域
# =========================================================
func add_herb_to_prescription(herb: HerbData, amount: float, unit: String = "qian") -> bool:
	if herb == null:
		push_warning("Clinic.add_herb_to_prescription: herb 为 null")
		return false

	var ok := current_prescription.add_herb(herb, amount, unit, current_selected_role)

	if ok:
		print("已加入药材：%s %s | 区域=%s" % [
			herb.herb_name,
			HerbUnit.format_amount(amount, unit),
			current_selected_role
		])
		print(current_prescription.get_display_text())
		_refresh_prescription_list()
	else:
		push_warning("加入药材失败：%s %s %s" % [herb.herb_name, amount, unit])

	return ok


# =========================================================
# 修改当前处方中的某味药剂量与单位
# =========================================================
func set_prescription_herb_amount(herb_id: String, amount: float, unit: String) -> bool:
	var ok := current_prescription.set_herb_amount_and_unit(herb_id, amount, unit)

	if ok:
		print("已修改药材：%s -> %s %s" % [herb_id, amount, unit])
		print(current_prescription.get_display_text())
		_refresh_prescription_list()

	return ok


# =========================================================
# 从当前处方移除某味药
# =========================================================
func remove_herb_from_prescription(herb_id: String) -> void:
	current_prescription.remove_herb(herb_id)
	print("已移除药材：", herb_id)
	print(current_prescription.get_display_text())
	_refresh_prescription_list()


# =========================================================
# 调试：打印当前处方
# =========================================================
func debug_print_current_prescription() -> void:
	current_prescription.debug_print()


# =========================================================
# 临时调试：手动拼一张麻黄汤
# =========================================================
func debug_build_ma_huang_tang_prescription() -> void:
	current_prescription.clear()

	print("开始生成麻黄汤测试处方")

	current_selected_role = "君"
	print("添加麻黄：", add_herb_by_id("ma_huang", 3, "qian"))

	current_selected_role = "臣"
	print("添加桂枝：", add_herb_by_id("gui_zhi", 2, "qian"))

	current_selected_role = "佐"
	print("添加杏仁：", add_herb_by_id("xing_ren", 3, "qian"))

	current_selected_role = "使"
	print("添加甘草：", add_herb_by_id("gan_cao", 1, "qian"))

	_set_selected_role("君")

	print("已生成测试处方：麻黄汤")
	current_prescription.debug_print()
	_refresh_prescription_list()


# =========================================================
# 初始化单位下拉框
# =========================================================
func _setup_unit_option() -> void:
	unit_option.clear()
	unit_option.add_item("分")
	unit_option.add_item("钱")
	unit_option.add_item("两")
	unit_option.add_item("斤")
	unit_option.select(1)


# =========================================================
# 刷新药材列表
# 左侧药材选择区
# metadata 里存 herb_id
# =========================================================
func _refresh_herb_list() -> void:
	herb_list.clear()

	var herbs = herb_database.get_all_herbs()

	for herb in herbs:
		if herb == null:
			continue

		herb_list.add_item("%s（%s）" % [herb.herb_name, herb.herb_id])

		var index := herb_list.item_count - 1
		herb_list.set_item_metadata(index, herb.herb_id)


# =========================================================
# 刷新当前处方四个区域
# =========================================================
func _refresh_prescription_list() -> void:
	jun_list.clear()
	chen_list.clear()
	zuo_list.clear()
	shi_list.clear()

	_fill_role_list(jun_list, current_prescription.get_herbs_by_role("君"))
	_fill_role_list(chen_list, current_prescription.get_herbs_by_role("臣"))
	_fill_role_list(zuo_list, current_prescription.get_herbs_by_role("佐"))
	_fill_role_list(shi_list, current_prescription.get_herbs_by_role("使"))

	_refresh_role_highlight()


# =========================================================
# 填充单个区域列表
# metadata 存 herb_id
# =========================================================
func _fill_role_list(list_node: ItemList, herb_items: Array[Dictionary]) -> void:
	for item in herb_items:
		var herb_name: String = item.get("herb_name", "")
		var herb_id: String = item.get("herb_id", "")
		var amount: float = float(item.get("amount", 0.0))
		var unit: String = item.get("unit", "")

		if herb_id == "":
			continue

		var text := "%s  %s" % [
			herb_name,
			HerbUnit.format_amount(amount, unit)
		]

		list_node.add_item(text)
		var index := list_node.item_count - 1
		list_node.set_item_metadata(index, herb_id)


# =========================================================
# 读取当前单位下拉框对应的内部单位 key
# =========================================================
func _get_selected_unit_key() -> String:
	match unit_option.selected:
		0:
			return "fen"
		1:
			return "qian"
		2:
			return "liang"
		3:
			return "jin"
		_:
			return "qian"


# =========================================================
# 点击“加入处方”
# =========================================================
func _on_add_herb_button_pressed() -> void:
	var selected := herb_list.get_selected_items()
	if selected.is_empty():
		info_label.text = "请先选择一味药材"
		return

	var herb_index: int = selected[0]
	var herb_id = herb_list.get_item_metadata(herb_index) as String

	var amount_text := amount_input.text.strip_edges()
	if amount_text == "":
		info_label.text = "请输入剂量"
		return

	var amount := amount_text.to_float()
	if amount <= 0.0:
		info_label.text = "剂量必须大于 0"
		return

	var unit := _get_selected_unit_key()
	var ok := add_herb_by_id(herb_id, amount, unit)

	if not ok:
		info_label.text = "加入药材失败：%s" % herb_id
		return

	info_label.text = "已加入%s区：%s %s" % [
		current_selected_role,
		herb_id,
		HerbUnit.format_amount(amount, unit)
	]


# =========================================================
# 点击“移除选中药材”
# 优先从当前选中区域移除
# 如果当前区域没有选中项，再尝试其他区域
# =========================================================
func _on_remove_herb_button_pressed() -> void:
	var herb_id := _get_selected_prescription_herb_id()

	if herb_id == "":
		info_label.text = "请先在当前处方中选择要移除的药材"
		return

	remove_herb_from_prescription(herb_id)
	info_label.text = "已移除药材：%s" % herb_id


# =========================================================
# 取四个区域中当前选中的药材 id
# 优先取当前选中区域
# =========================================================
func _get_selected_prescription_herb_id() -> String:
	var primary_list := _get_list_by_role(current_selected_role)
	var herb_id := _get_selected_herb_id_from_list(primary_list)
	if herb_id != "":
		return herb_id

	for role_name in ["君", "臣", "佐", "使"]:
		var list_node := _get_list_by_role(role_name)
		herb_id = _get_selected_herb_id_from_list(list_node)
		if herb_id != "":
			return herb_id

	return ""


# =========================================================
# 从单个列表获取选中 herb_id
# =========================================================
func _get_selected_herb_id_from_list(list_node: ItemList) -> String:
	var selected := list_node.get_selected_items()
	if selected.is_empty():
		return ""

	var index: int = selected[0]
	return list_node.get_item_metadata(index) as String


# =========================================================
# 根据角色取列表节点
# =========================================================
func _get_list_by_role(role_name: String) -> ItemList:
	match role_name:
		"君":
			return jun_list
		"臣":
			return chen_list
		"佐":
			return zuo_list
		"使":
			return shi_list
		_:
			return jun_list


# =========================================================
# 点击“清空处方”
# =========================================================
func _on_clear_prescription_button_pressed() -> void:
	clear_current_prescription()
	info_label.text = "当前处方已清空"


# =========================================================
# 切换到上一个病人
# =========================================================
func _on_prev_button_pressed() -> void:
	npc_manager.prev_npc()
	refresh_clinic_view()


# =========================================================
# 切换到下一个病人
# =========================================================
func _on_next_button_pressed() -> void:
	npc_manager.next_npc()
	refresh_clinic_view()


# =========================================================
# 生成随机病人
# =========================================================
func _on_spawn_npc_button_pressed() -> void:
	npc_manager.spawn_random_npc()
	refresh_clinic_view()


# =========================================================
# 提交按钮
# =========================================================
func _on_submit_button_pressed() -> void:
	submit_prescription()


# =========================================================
# 四个区域点击选择
# =========================================================
func _on_jun_list_item_selected(_index: int) -> void:
	_set_selected_role("君")


func _on_chen_list_item_selected(_index: int) -> void:
	_set_selected_role("臣")


func _on_zuo_list_item_selected(_index: int) -> void:
	_set_selected_role("佐")


func _on_shi_list_item_selected(_index: int) -> void:
	_set_selected_role("使")


# =========================================================
# 点击空白区域时也切换当前区域
# =========================================================
func _on_jun_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected_role("君")


func _on_chen_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected_role("臣")


func _on_zuo_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected_role("佐")


func _on_shi_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected_role("使")


# =========================================================
# 打开脉象窗口
# =========================================================
func _on_open_pulse_window_button_pressed() -> void:
	if pulse_window == null:
		return

	pulse_window.show()
	pulse_window.grab_focus()

	# 打开窗口时，刷新一次当前区域
	show_region(current_display_region_name)

	# 重置键盘签名，避免第一次不刷新
	last_pulse_input_signature = ""


# =========================================================
# 接收 PulsePanel 发来的区域切换信号
# =========================================================
func _on_pulse_panel_region_selected(display_region_name: String) -> void:
	# 手动点击按钮时，直接切回单脉象模式
	pulse_keyboard_override_active = false
	show_region(display_region_name)


func _on_pulse_window_close_requested() -> void:
	pulse_window.hide()
	pulse_keyboard_override_active = false
	last_pulse_input_signature = ""
