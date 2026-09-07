extends Window
class_name PrescriptionWindow

# =========================================================
# Prescription.gd
# 开方窗口独立控制脚本
#
# 主要职责：
# 1. 管理药材列表显示
# 2. 管理君臣佐使区域切换
# 3. 点击药材时加入当前处方
# 4. 同一味药连续点击时自动累加
# 5. 管理处方四区列表刷新
# 6. 向 Clinic.gd 发出提示信息和提交请求
#
# 说明：
# 1. info_label 不在本脚本内管理
# 2. 本脚本通过 signal 把文本发回 Clinic.gd
# 3. current_prescription / herb_database 由 Clinic.gd 注入
# =========================================================


# =========================================================
# 对外信号
# =========================================================

# 请求 Clinic.gd 更新 info_label
signal info_requested(text: String)

# 请求 Clinic.gd 执行 submit_prescription()
signal submit_requested()


# =========================================================
# 常量定义
# =========================================================
const ROLE_JUN := "君"
const ROLE_CHEN := "臣"
const ROLE_ZUO := "佐"
const ROLE_SHI := "使"

# 搜索框停止输入后再执行过滤，避免每个字符都触发布局刷新。
const SEARCH_DEBOUNCE_SECONDS := 0.10

# 解锁后才开放“搜索并套用预制方剂”功能的医书条目。
const FORMULA_FILL_FEATURE_ENTRY_ID := "yu_zhi_fang_ji"


# =========================================================
# 场景节点引用
# 注意：
# 这里默认你的 Prescription 场景根节点就是 Window，
# 并且下面挂着 PrescriptionLayout
# =========================================================

# ---------- 药材选择 ----------
@onready var prescription_layout: Control = $PrescriptionLayout

# 药材搜索框
@onready var herb_search: LineEdit = $PrescriptionLayout/HerbSelectRow/HerbSearchColumn/HerbSearch

# 药材按钮列表
@onready var herb_list: GridContainer = $PrescriptionLayout/HerbSelectRow/HerbSearchColumn/HerbListScroll/HerbList

# 疾病搜索框
@onready var disease_search: LineEdit = $PrescriptionLayout/DiseaseSelectRow/DiseaseSearch

# 疾病按钮列表
@onready var disease_list: GridContainer = $PrescriptionLayout/DiseaseSelectRow/DiseaseListScroll/DiseaseList

@onready var unit_option: OptionButton = $PrescriptionLayout/HerbSelectRow/HerbEditColumn/UnitOption

# ---------- 处方四区列表 ----------
@onready var jun_list: ItemList = $PrescriptionLayout/PrescriptionView/RoleContainer/JunPanel/VBoxContainer/JunList
@onready var chen_list: ItemList = $PrescriptionLayout/PrescriptionView/RoleContainer/ChenPanel/VBoxContainer/ChenList
@onready var zuo_list: ItemList = $PrescriptionLayout/PrescriptionView/RoleContainer/ZuoPanel/VBoxContainer/ZuoList
@onready var shi_list: ItemList = $PrescriptionLayout/PrescriptionView/RoleContainer/ShiPanel/VBoxContainer/ShiList

# ---------- 处方四区面板（用于高亮） ----------
@onready var jun_panel: Control = $PrescriptionLayout/PrescriptionView/RoleContainer/JunPanel
@onready var chen_panel: Control = $PrescriptionLayout/PrescriptionView/RoleContainer/ChenPanel
@onready var zuo_panel: Control = $PrescriptionLayout/PrescriptionView/RoleContainer/ZuoPanel
@onready var shi_panel: Control = $PrescriptionLayout/PrescriptionView/RoleContainer/ShiPanel

# ---------- 操作按钮 ----------
@onready var clear_prescription_button: Button = $PrescriptionLayout/HerbSelectRow/HerbEditColumn/ClearPrescriptionButton
@onready var submit_button: Button = $PrescriptionLayout/HerbSelectRow/HerbEditColumn/SubmitButton

# ---------- 玩家提示窗口（Control 版 PlayerHintWindow，需作为 PrescriptionWindow.tscn 的子节点存在） ----------
var player_hint_window: Node = null


# =========================================================
# 外部注入数据（由 Clinic.gd 传入）
# =========================================================

# 药材数据库
var herb_database = null

# 方剂数据库
# 用于支持在药材搜索栏输入方剂中文名 / 拼音 / 拼音首字母时，显示该方剂包含的药材
var formula_database = null

# 当前处方对象（Prescription 实例）
var current_prescription = null


# =========================================================
# 运行时状态
# =========================================================

# 当前选中的药材ID
var selected_herb_id: String = ""

# 当前选中的药材按钮
var selected_herb_button: Button = null

# 当前选中的配伍区域
var current_selected_role: String = ROLE_JUN

# 当前药材搜索关键词
# 用于过滤 HerbList 中显示的药材按钮
var herb_search_keyword: String = ""

# 当前疾病搜索关键词
var disease_search_keyword: String = ""

# 当前选中的疾病ID
var selected_disease_id: String = ""

# 当前选中的疾病名称
var selected_disease_name: String = ""

# 疾病数据列表
var all_diseases: Array = []

# 搜索 debounce。
var _herb_search_timer: Timer = null
var _disease_search_timer: Timer = null
var _suppress_search_signal: bool = false

# 药材按钮 / 搜索字段缓存。按钮只创建一次，搜索时仅切换 visible。
var _herb_button_by_id: Dictionary = {}
var _herb_search_record_by_id: Dictionary = {}
var _formula_search_records: Array = []
var _formula_button_by_id: Dictionary = {}
var _cached_herb_db_instance_id: int = 0
var _cached_formula_db_instance_id: int = 0

# 疾病按钮 / 搜索字段缓存。
var _disease_button_by_id: Dictionary = {}
var _disease_search_record_by_id: Dictionary = {}
var _cached_disease_db_instance_id: int = 0


# =========================================================
# 生命周期
# =========================================================
func _ready() -> void:
	_setup_unit_option()
	_setup_search_debounce_timers()
	_connect_signals()
	_setup_player_hint_dialog()
	_set_selected_role(ROLE_JUN)
	load_all_diseases()

# =========================================================
# 对外初始化接口
# 由 Clinic.gd 调用
#
# herb_db:
#   HerbDataBase 节点
#
# prescription:
#   当前共用的 Prescription 实例
# =========================================================
func setup(herb_db, prescription, formula_db = null) -> void:
	herb_database = herb_db
	current_prescription = prescription

	# 兼容旧调用：Clinic.gd 仍然可以只传 herb_db 和 prescription
	# 若外部没有显式传入 formula_db，则使用项目自动加载的 FormulaDB
	if formula_db != null:
		formula_database = formula_db
	else:
		formula_database = FormulaDB

	selected_herb_id = ""
	selected_herb_button = null

	# 数据库模板长期不变，按钮与搜索字段只在数据库实例变化时重建。
	_ensure_herb_button_cache()
	_ensure_formula_search_cache()
	_ensure_disease_button_cache()

	_sync_selected_disease_from_prescription()
	_set_selected_role(ROLE_JUN)

	_apply_herb_filter()
	_apply_disease_filter()
	_refresh_prescription_list()


# =========================================================
# 初始化：单位下拉
# =========================================================
func _setup_unit_option() -> void:
	if unit_option == null:
		return

	unit_option.clear()
	unit_option.add_item("分")
	unit_option.add_item("钱")
	unit_option.add_item("两")
	unit_option.add_item("斤")
	unit_option.select(1)


# =========================================================
# 初始化：搜索 debounce Timer
# =========================================================
func _setup_search_debounce_timers() -> void:
	if _herb_search_timer == null:
		_herb_search_timer = Timer.new()
		_herb_search_timer.name = "HerbSearchDebounceTimer"
		_herb_search_timer.one_shot = true
		_herb_search_timer.wait_time = SEARCH_DEBOUNCE_SECONDS
		add_child(_herb_search_timer)
		_herb_search_timer.timeout.connect(Callable(self, "_apply_herb_filter"))

	if _disease_search_timer == null:
		_disease_search_timer = Timer.new()
		_disease_search_timer.name = "DiseaseSearchDebounceTimer"
		_disease_search_timer.one_shot = true
		_disease_search_timer.wait_time = SEARCH_DEBOUNCE_SECONDS
		add_child(_disease_search_timer)
		_disease_search_timer.timeout.connect(Callable(self, "_apply_disease_filter"))


# =========================================================
# 初始化：信号连接
# =========================================================
func _connect_signals() -> void:
	_safe_connect_pressed(clear_prescription_button, _on_clear_prescription_button_pressed)
	_safe_connect_pressed(submit_button, _on_submit_button_pressed)

	# 搜索框文字变化时，刷新药材列表
	if herb_search != null and not herb_search.text_changed.is_connected(_on_herb_search_text_changed):
		herb_search.text_changed.connect(_on_herb_search_text_changed)

	# 搜索框获得焦点时，按 Esc 清空当前搜索内容
	if herb_search != null and not herb_search.gui_input.is_connected(_on_herb_search_gui_input):
		herb_search.gui_input.connect(_on_herb_search_gui_input)

	# 疾病搜索框文字变化时，刷新疾病列表
	if disease_search != null and not disease_search.text_changed.is_connected(_on_disease_search_text_changed):
		disease_search.text_changed.connect(_on_disease_search_text_changed)

	# 疾病搜索框获得焦点时，按 Esc 清空当前搜索内容
	if disease_search != null and not disease_search.gui_input.is_connected(_on_disease_search_gui_input):
		disease_search.gui_input.connect(_on_disease_search_gui_input)

	if close_requested != null and not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)

	_safe_connect_item_selected(jun_list, _on_jun_list_item_selected)
	_safe_connect_item_selected(chen_list, _on_chen_list_item_selected)
	_safe_connect_item_selected(zuo_list, _on_zuo_list_item_selected)
	_safe_connect_item_selected(shi_list, _on_shi_list_item_selected)

	_safe_connect_item_clicked(jun_list, _on_jun_list_item_clicked)
	_safe_connect_item_clicked(chen_list, _on_chen_list_item_clicked)
	_safe_connect_item_clicked(zuo_list, _on_zuo_list_item_clicked)
	_safe_connect_item_clicked(shi_list, _on_shi_list_item_clicked)

	_safe_connect_gui_input(jun_list, _on_jun_list_gui_input)
	_safe_connect_gui_input(chen_list, _on_chen_list_gui_input)
	_safe_connect_gui_input(zuo_list, _on_zuo_list_gui_input)
	_safe_connect_gui_input(shi_list, _on_shi_list_gui_input)


func _safe_connect_pressed(button: BaseButton, callable_fn: Callable) -> void:
	if button != null and not button.pressed.is_connected(callable_fn):
		button.pressed.connect(callable_fn)


func _safe_connect_item_selected(list_node: ItemList, callable_fn: Callable) -> void:
	if list_node != null and not list_node.item_selected.is_connected(callable_fn):
		list_node.item_selected.connect(callable_fn)


func _safe_connect_item_clicked(list_node: ItemList, callable_fn: Callable) -> void:
	if list_node != null and not list_node.item_clicked.is_connected(callable_fn):
		list_node.item_clicked.connect(callable_fn)


func _safe_connect_gui_input(control_node: Control, callable_fn: Callable) -> void:
	if control_node != null and not control_node.gui_input.is_connected(callable_fn):
		control_node.gui_input.connect(callable_fn)


# =========================================================
# 当前区域设置 / 高亮
# =========================================================
func _set_selected_role(role_name: String) -> void:
	current_selected_role = role_name
	_refresh_role_highlight()


func _refresh_role_highlight() -> void:
	var normal_color := Color(0.35, 0.35, 0.35, 1.0)
	var selected_color := Color(0.95, 0.85, 0.45, 1.0)

	if jun_panel != null:
		jun_panel.modulate = normal_color
	if chen_panel != null:
		chen_panel.modulate = normal_color
	if zuo_panel != null:
		zuo_panel.modulate = normal_color
	if shi_panel != null:
		shi_panel.modulate = normal_color

	match current_selected_role:
		ROLE_JUN:
			if jun_panel != null:
				jun_panel.modulate = selected_color
		ROLE_CHEN:
			if chen_panel != null:
				chen_panel.modulate = selected_color
		ROLE_ZUO:
			if zuo_panel != null:
				zuo_panel.modulate = selected_color
		ROLE_SHI:
			if shi_panel != null:
				shi_panel.modulate = selected_color


# =========================================================
# 获取当前选中的单位 key
# =========================================================
func _get_selected_unit_key() -> String:
	if unit_option == null:
		return "qian"

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
# 药材按钮缓存 / 搜索
# =========================================================
func _refresh_herb_list() -> void:
	# 兼容旧调用：不再销毁/创建按钮，只确保缓存存在并应用当前过滤条件。
	_ensure_herb_button_cache()
	_ensure_formula_search_cache()
	_apply_herb_filter()


func _ensure_herb_button_cache() -> void:
	if herb_list == null or herb_database == null:
		return
	if not herb_database.has_method("get_all_herbs"):
		emit_signal("info_requested", "药材数据库缺少 get_all_herbs()")
		return

	var db_instance_id: int = int(herb_database.get_instance_id())
	if not _herb_button_by_id.is_empty() and db_instance_id == _cached_herb_db_instance_id:
		return

	_clear_herb_button_cache()
	_cached_herb_db_instance_id = db_instance_id

	var herbs = herb_database.get_all_herbs()
	for herb in herbs:
		if herb == null:
			continue

		var herb_id := str(herb.herb_id).strip_edges()
		if herb_id == "":
			continue

		var herb_name := str(herb.herb_name).strip_edges()
		var herb_id_raw := herb_id.to_lower()

		_herb_search_record_by_id[herb_id] = {
			"name": _normalize_herb_search_text(herb_name),
			"pinyin": _normalize_herb_search_text(herb_id_raw),
			"initials": _get_id_initials(herb_id_raw)
		}

		var herb_button := Button.new()
		herb_button.text = herb_name
		herb_button.custom_minimum_size = Vector2(120, 44)
		herb_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		herb_button.focus_mode = Control.FOCUS_NONE
		herb_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		herb_button.set_meta("herb_id", herb_id)
		_set_herb_button_selected_style(herb_button, false)

		herb_button.pressed.connect(_on_herb_grid_button_pressed.bind(herb_button))
		herb_button.gui_input.connect(_on_herb_grid_button_gui_input.bind(herb_button))

		herb_list.add_child(herb_button)
		herb_button.hide()
		_herb_button_by_id[herb_id] = herb_button


func _clear_herb_button_cache() -> void:
	# 只销毁药材按钮；预制方剂按钮由独立缓存管理，避免互相误删。
	for button_value in _herb_button_by_id.values():
		if button_value is Button and is_instance_valid(button_value):
			button_value.queue_free()

	_herb_button_by_id.clear()
	_herb_search_record_by_id.clear()
	selected_herb_id = ""
	selected_herb_button = null


func _clear_formula_button_cache() -> void:
	for button_value in _formula_button_by_id.values():
		if button_value is Button and is_instance_valid(button_value):
			button_value.queue_free()
	_formula_button_by_id.clear()


func _ensure_formula_search_cache() -> void:
	if formula_database == null or not formula_database.has_method("get_all_formulas"):
		_clear_formula_button_cache()
		_formula_search_records.clear()
		_cached_formula_db_instance_id = 0
		return

	var db_instance_id: int = int(formula_database.get_instance_id())
	if not _formula_search_records.is_empty() and db_instance_id == _cached_formula_db_instance_id:
		return

	_clear_formula_button_cache()
	_formula_search_records.clear()
	_cached_formula_db_instance_id = db_instance_id

	var formulas = formula_database.get_all_formulas()
	for formula in formulas:
		if formula == null:
			continue

		var formula_id := str(formula.formula_id).strip_edges()
		if formula_id == "":
			continue
		var formula_id_raw := formula_id.to_lower()

		_formula_search_records.append({
			"formula": formula,
			"formula_id": formula_id,
			"name": _normalize_herb_search_text(str(formula.formula_name)),
			"pinyin": _normalize_herb_search_text(formula_id_raw),
			"initials": _get_id_initials(formula_id_raw)
		})

		# 预制方剂按钮也只创建一次；搜索时仅切换 visible。
		var formula_button := Button.new()
		formula_button.text = str(formula.formula_name)
		formula_button.custom_minimum_size = Vector2(180, 44)
		formula_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		formula_button.focus_mode = Control.FOCUS_NONE
		formula_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		formula_button.set_meta("formula_id", formula_id)
		if formula.has_method("get_display_text"):
			formula_button.tooltip_text = str(formula.get_display_text())
		formula_button.pressed.connect(_on_formula_button_pressed.bind(formula))
		herb_list.add_child(formula_button)
		formula_button.hide()
		_formula_button_by_id[formula_id] = formula_button


func _on_herb_search_text_changed(new_text: String) -> void:
	if _suppress_search_signal:
		return

	herb_search_keyword = _normalize_herb_search_text(new_text)
	if _herb_search_timer == null:
		_apply_herb_filter()
		return

	_herb_search_timer.start(SEARCH_DEBOUNCE_SECONDS)


func _on_herb_search_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	if herb_search == null or herb_search.text == "":
		return

	herb_search.clear()
	herb_search.grab_focus()

	# Esc 清空是明确操作，立即应用，不必再等待 debounce。
	if _herb_search_timer != null:
		_herb_search_timer.stop()
	herb_search_keyword = ""
	_apply_herb_filter()
	get_viewport().set_input_as_handled()


func _apply_herb_filter() -> void:
	if herb_list == null or herb_database == null:
		return

	_ensure_herb_button_cache()
	_ensure_formula_search_cache()

	if selected_herb_button != null and is_instance_valid(selected_herb_button):
		_set_herb_button_selected_style(selected_herb_button, false)
	selected_herb_id = ""
	selected_herb_button = null

	# 普通药材只按药材自身名称 / 拼音 / 首字母匹配。
	# 方剂命中不再拆成组成药材，使用独立的方剂按钮。
	for herb_id_value in _herb_button_by_id.keys():
		var herb_id := str(herb_id_value)
		var button_value = _herb_button_by_id.get(herb_id, null)
		if not (button_value is Button):
			continue
		var button = button_value

		var should_show = bool(Unlock.is_herb_unlocked(herb_id))
		if should_show and herb_search_keyword != "":
			var record = {}
			var record_value = _herb_search_record_by_id.get(herb_id, {})
			if typeof(record_value) == TYPE_DICTIONARY:
				record = record_value
			should_show = (
				str(record.get("name", "")).contains(herb_search_keyword)
				or str(record.get("pinyin", "")).begins_with(herb_search_keyword)
				or str(record.get("initials", "")).begins_with(herb_search_keyword)
			)

		button.visible = should_show

	_apply_formula_filter()


func _is_formula_fill_feature_unlocked() -> bool:
	if Unlock == null or not Unlock.has_method("is_entry_unlocked"):
		return false
	return bool(Unlock.is_entry_unlocked(FORMULA_FILL_FEATURE_ENTRY_ID))


func _is_formula_unlocked(formula) -> bool:
	if formula == null:
		return false
	if Unlock == null or not Unlock.has_method("is_formula_unlocked"):
		return false

	var formula_id := str(formula.formula_id).strip_edges()
	if formula_id == "":
		return false
	return bool(Unlock.is_formula_unlocked(formula_id))


func _formula_record_matches(record: Dictionary) -> bool:
	if herb_search_keyword == "":
		return false
	return (
		str(record.get("name", "")).contains(herb_search_keyword)
		or str(record.get("pinyin", "")).begins_with(herb_search_keyword)
		or str(record.get("initials", "")).begins_with(herb_search_keyword)
	)


func _apply_formula_filter() -> void:
	# 无关键词时不显示全部预制方剂；与优化前行为一致。
	var feature_unlocked := _is_formula_fill_feature_unlocked()

	for record_value in _formula_search_records:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_value
		var formula = record.get("formula", null)
		var formula_id := str(record.get("formula_id", ""))
		var button_value = _formula_button_by_id.get(formula_id, null)
		if not (button_value is Button):
			continue

		var should_show := false
		if feature_unlocked and formula != null and _is_formula_unlocked(formula):
			should_show = _formula_record_matches(record)

		button_value.visible = should_show


func _on_formula_button_pressed(formula) -> void:
	if not _is_formula_fill_feature_unlocked():
		emit_signal("info_requested", "尚未解锁预制方剂功能。")
		_apply_herb_filter()
		return

	if not _is_formula_unlocked(formula):
		emit_signal("info_requested", "该方剂尚未解锁。")
		_apply_herb_filter()
		return

	if current_prescription == null:
		emit_signal("info_requested", "当前处方未初始化")
		return

	if herb_database == null:
		emit_signal("info_requested", "药材数据库未初始化")
		return

	if formula == null or not formula.has_method("get_group_by_role"):
		emit_signal("info_requested", "方剂数据无效，无法填入处方。")
		return

	# 先完整校验所有组成药材，再修改玩家当前处方，避免半途中断破坏旧处方。
	var fill_items: Array = []
	for role_name in [ROLE_JUN, ROLE_CHEN, ROLE_ZUO, ROLE_SHI]:
		var ingredient_group = formula.get_group_by_role(role_name)

		for ingredient in ingredient_group:
			if ingredient == null:
				emit_signal("info_requested", "方剂数据存在空药材，无法填入处方。")
				return

			var herb_id := str(ingredient.get_herb_id()).strip_edges()
			var amount := float(ingredient.amount)
			var unit := str(ingredient.unit).strip_edges()
			var herb = herb_database.get_herb_by_id(herb_id)

			if herb_id == "" or herb == null:
				emit_signal("info_requested", "方剂中的药材资源缺失：%s" % herb_id)
				return

			if amount <= 0.0 or not HerbUnit.is_valid_unit(unit):
				emit_signal("info_requested", "方剂中的药材剂量无效：%s" % str(herb.herb_name))
				return

			fill_items.append({
				"herb": herb,
				"amount": amount,
				"unit": unit,
				"role": role_name
			})

	if fill_items.is_empty():
		emit_signal("info_requested", "该方剂没有可填入的药材。")
		return

	# clear() 只清空四区药材，不清除已经选中的疾病。
	current_prescription.clear()
	for item in fill_items:
		current_prescription.add_herb(
			item["herb"],
			float(item["amount"]),
			str(item["unit"]),
			str(item["role"])
		)

	selected_herb_id = ""
	selected_herb_button = null
	_set_selected_role(ROLE_JUN)
	_refresh_prescription_list()

	emit_signal("info_requested", "已按预制方剂填入：%s" % str(formula.formula_name))


func _normalize_herb_search_text(value: String) -> String:
	return value.strip_edges().to_lower() \
		.replace("_", "") \
		.replace("-", "") \
		.replace(" ", "")


func _get_id_initials(value: String) -> String:
	var parts := value.to_lower().split("_", false)
	var initials := ""

	for part in parts:
		if part.length() > 0:
			initials += part.substr(0, 1)

	return initials


# =========================================================
# 点击药材按钮
# 规则：
# 1. 左键点击一次，按当前 UnitOption 加入“1个单位”
# 2. 同一味药再次点击时，按底层“分”累加，避免换单位时出错
# =========================================================
func _on_herb_grid_button_pressed(herb_button: Button) -> void:
	if herb_button == null:
		return

	if current_prescription == null:
		emit_signal("info_requested", "当前处方未初始化")
		return

	# 取消上一个高亮
	if selected_herb_button != null and is_instance_valid(selected_herb_button):
		_set_herb_button_selected_style(selected_herb_button, false)

	# 更新当前选中
	selected_herb_button = herb_button
	selected_herb_id = str(herb_button.get_meta("herb_id"))

	# 当前按钮高亮
	_set_herb_button_selected_style(selected_herb_button, true)

	# 每次点击固定加 1 个当前单位
	var add_amount := 1.0
	var add_unit := _get_selected_unit_key()

	# 先看当前角色区域里是否已有这味药
	var exist_item := _find_prescription_item_in_role(current_selected_role, selected_herb_id)

	# 已存在：按“分”累加
	if not exist_item.is_empty():
		var old_amount: float = float(exist_item.get("amount", 0.0))
		var old_unit: String = str(exist_item.get("unit", "qian"))

		var old_total_fen := HerbUnit.to_fen(old_amount, old_unit)
		var add_total_fen := HerbUnit.to_fen(add_amount, add_unit)
		var new_total_fen := old_total_fen + add_total_fen

		var new_amount := HerbUnit.from_fen(new_total_fen, add_unit)

		var ok_update := set_prescription_herb_amount(selected_herb_id, new_amount, add_unit)
		if not ok_update:
			emit_signal("info_requested", "累加药材失败：%s" % herb_button.text)
			return

		emit_signal("info_requested", "已加入%s区：%s，当前%s" % [
			current_selected_role,
			herb_button.text,
			HerbUnit.format_amount(new_amount, add_unit)
		])
		return

	# 不存在：首次加入
	var ok_add := add_herb_by_id(selected_herb_id, add_amount, add_unit)
	if not ok_add:
		emit_signal("info_requested", "加入药材失败：%s" % herb_button.text)
		return

	emit_signal("info_requested", "已加入%s区：%s %s" % [
		current_selected_role,
		herb_button.text,
		HerbUnit.format_amount(add_amount, add_unit)
	])


# =========================================================
# 药材按钮右键事件
# 规则：
# 1. 右键下方药材按钮时，优先减少当前选中区域的一单位
# 2. 如果当前区域没有该药材，则自动到其它区域里查找并减少
# 3. 减到 0 或以下时，直接从处方中移除
# =========================================================
func _on_herb_grid_button_gui_input(event: InputEvent, herb_button: Button) -> void:
	if herb_button == null:
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return

	# 阻止右键触发其它默认行为
	herb_button.accept_event()

	# 右键时也同步当前高亮药材按钮，便于视觉反馈
	if selected_herb_button != null and is_instance_valid(selected_herb_button):
		_set_herb_button_selected_style(selected_herb_button, false)
	selected_herb_button = herb_button
	selected_herb_id = str(herb_button.get_meta("herb_id"))
	_set_herb_button_selected_style(selected_herb_button, true)

	_decrease_herb_by_id(selected_herb_id, herb_button.text)


# =========================================================
# 设置药材按钮选中样式
# =========================================================
func _set_herb_button_selected_style(herb_button: Button, is_selected: bool) -> void:
	if herb_button == null:
		return

	if is_selected:
		herb_button.modulate = Color(1.0, 0.95, 0.65, 1.0)
	else:
		herb_button.modulate = Color(1.0, 1.0, 1.0, 1.0)


# =========================================================
# 处方操作
# =========================================================
func add_herb_by_id(herb_id: String, amount: float, unit: String = "qian") -> bool:
	if herb_database == null:
		push_warning("PrescriptionWindow.add_herb_by_id: herb_database 未初始化")
		return false

	var herb = herb_database.get_herb_by_id(herb_id)
	if herb == null:
		push_warning("PrescriptionWindow.add_herb_by_id: 未找到药材 -> " + herb_id)
		return false

	return add_herb_to_prescription(herb, amount, unit)


func add_herb_to_prescription(herb, amount: float, unit: String = "qian") -> bool:
	if herb == null:
		push_warning("PrescriptionWindow.add_herb_to_prescription: herb 为 null")
		return false

	if current_prescription == null:
		push_warning("PrescriptionWindow.add_herb_to_prescription: current_prescription 为 null")
		return false

	var ok = current_prescription.add_herb(herb, amount, unit, current_selected_role)

	if ok:
		_refresh_prescription_list()
	else:
		push_warning("加入药材失败：%s %s %s" % [herb.herb_name, amount, unit])

	return ok


func set_prescription_herb_amount(herb_id: String, amount: float, unit: String) -> bool:
	if current_prescription == null:
		return false

	var ok = current_prescription.set_herb_amount_and_unit(herb_id, amount, unit)

	if ok:
		_refresh_prescription_list()

	return ok


func remove_herb_from_prescription(herb_id: String) -> void:
	if current_prescription == null:
		return

	current_prescription.remove_herb(herb_id)
	_refresh_prescription_list()


func clear_current_prescription() -> void:
	if current_prescription == null:
		return

	current_prescription.clear()	
	_refresh_prescription_list()


# =========================================================
# 减少药材逻辑
# =========================================================
func _decrease_herb_by_id(herb_id: String, herb_name: String = "") -> void:
	if current_prescription == null:
		emit_signal("info_requested", "当前处方未初始化")
		return

	if herb_id == "":
		emit_signal("info_requested", "未找到要减少的药材")
		return

	# 优先减少当前选中区域；若当前区域没有，再去其它区域里找
	var target_role := current_selected_role
	var target_item := _find_prescription_item_in_role(target_role, herb_id)

	if target_item.is_empty():
		for role_name in [ROLE_JUN, ROLE_CHEN, ROLE_ZUO, ROLE_SHI]:
			if role_name == current_selected_role:
				continue
			target_item = _find_prescription_item_in_role(role_name, herb_id)
			if not target_item.is_empty():
				target_role = role_name
				break

	if target_item.is_empty():
		emit_signal("info_requested", "该药材尚未加入处方：%s" % herb_name)
		return

	# 找到了实际所在区域后，同步当前选中区域高亮
	_set_selected_role(target_role)

	var old_amount: float = float(target_item.get("amount", 0.0))
	var old_unit: String = str(target_item.get("unit", "qian"))
	var decrease_unit := _get_selected_unit_key()
	var old_total_fen := HerbUnit.to_fen(old_amount, old_unit)
	var decrease_total_fen := HerbUnit.to_fen(1.0, decrease_unit)
	var new_total_fen := old_total_fen - decrease_total_fen

	# 减到 0 或以下，直接移除
	if new_total_fen <= 0.0:
		remove_herb_from_prescription(herb_id)
		emit_signal("info_requested", "已移除%s区药材：%s" % [target_role, herb_name])
		return

	# 仍然大于 0，则保留并更新为当前单位显示
	var new_amount := HerbUnit.from_fen(new_total_fen, decrease_unit)
	var ok_update := set_prescription_herb_amount(herb_id, new_amount, decrease_unit)
	if not ok_update:
		emit_signal("info_requested", "减少药材失败：%s" % herb_name)
		return

	emit_signal("info_requested", "已减少%s区药材：%s，当前%s" % [
		target_role,
		herb_name,
		HerbUnit.format_amount(new_amount, decrease_unit)
	])


# =========================================================
# 处方四区刷新
# =========================================================
func _refresh_prescription_list() -> void:
	if current_prescription == null:
		return

	if jun_list != null:
		jun_list.clear()
	if chen_list != null:
		chen_list.clear()
	if zuo_list != null:
		zuo_list.clear()
	if shi_list != null:
		shi_list.clear()

	_fill_role_list(jun_list, current_prescription.get_herbs_by_role(ROLE_JUN))
	_fill_role_list(chen_list, current_prescription.get_herbs_by_role(ROLE_CHEN))
	_fill_role_list(zuo_list, current_prescription.get_herbs_by_role(ROLE_ZUO))
	_fill_role_list(shi_list, current_prescription.get_herbs_by_role(ROLE_SHI))

	_refresh_role_highlight()


func _fill_role_list(list_node: ItemList, herb_items: Array[Dictionary]) -> void:
	if list_node == null:
		return

	for item in herb_items:
		var herb_name: String = item.get("herb_name", "")
		var herb_id: String = item.get("herb_id", "")
		var amount: float = float(item.get("amount", 0.0))
		var unit: String = item.get("unit", "")

		if herb_id == "":
			continue

		var text := "%s  %s" % [herb_name, HerbUnit.format_amount(amount, unit)]
		list_node.add_item(text)

		var index := list_node.item_count - 1
		list_node.set_item_metadata(index, herb_id)


# =========================================================
# 处方区辅助
# =========================================================
func _get_list_by_role(role_name: String) -> ItemList:
	match role_name:
		ROLE_JUN:
			return jun_list
		ROLE_CHEN:
			return chen_list
		ROLE_ZUO:
			return zuo_list
		ROLE_SHI:
			return shi_list
		_:
			return jun_list


func _get_selected_herb_id_from_list(list_node: ItemList) -> String:
	if list_node == null:
		return ""

	var selected := list_node.get_selected_items()
	if selected.is_empty():
		return ""

	var index: int = selected[0]
	return list_node.get_item_metadata(index) as String


func _get_selected_prescription_herb_id() -> String:
	# 先从当前高亮区域取
	var primary_list := _get_list_by_role(current_selected_role)
	var herb_id := _get_selected_herb_id_from_list(primary_list)
	if herb_id != "":
		return herb_id

	# 当前区域没选中，再遍历全部区域
	for role_name in [ROLE_JUN, ROLE_CHEN, ROLE_ZUO, ROLE_SHI]:
		var list_node := _get_list_by_role(role_name)
		herb_id = _get_selected_herb_id_from_list(list_node)
		if herb_id != "":
			return herb_id

	return ""


# =========================================================
# 在指定角色区域中查找某味药材
# 找到返回对应 Dictionary
# 找不到返回 {}
# =========================================================
func _find_prescription_item_in_role(role_name: String, herb_id: String) -> Dictionary:
	if current_prescription == null:
		return {}

	var herb_items: Array[Dictionary] = current_prescription.get_herbs_by_role(role_name)

	for item in herb_items:
		if str(item.get("herb_id", "")) == herb_id:
			return item

	return {}


# =========================================================
# UI按钮事件
# =========================================================
func _on_clear_prescription_button_pressed() -> void:
	clear_current_prescription()
	emit_signal("info_requested", "当前处方已清空")


func _on_submit_button_pressed() -> void:
	if _is_disease_empty():
		_show_player_hint("请先填入疾病。")
		return

	if _is_prescription_herbs_empty():
		_show_player_hint("请先填入药材。")
		return

	emit_signal("submit_requested")
	_clear_selected_disease()


func _setup_player_hint_dialog() -> void:
	if player_hint_window != null and is_instance_valid(player_hint_window):
		return

	player_hint_window = find_child("PlayerHintWindow", true, false)

	if player_hint_window == null:
		push_warning("PrescriptionWindow.gd 找不到 PlayerHintWindow，请检查 PrescriptionWindow.tscn 是否已经添加 PlayerHintWindow.tscn")
		return

	if player_hint_window.has_method("hide"):
		player_hint_window.hide()


func _show_player_hint(message: String) -> void:
	if player_hint_window == null or not is_instance_valid(player_hint_window):
		_setup_player_hint_dialog()

	if player_hint_window != null and player_hint_window.has_method("show_hint"):
		player_hint_window.call("show_hint", message)
	else:
		emit_signal("info_requested", message)


func _is_disease_empty() -> bool:
	if selected_disease_id.strip_edges() != "":
		return false

	if selected_disease_name.strip_edges() != "":
		return false

	if current_prescription == null:
		return true

	if _object_has_property(current_prescription, "disease_id"):
		if str(current_prescription.get("disease_id")).strip_edges() != "":
			return false

	if _object_has_property(current_prescription, "disease_name"):
		if str(current_prescription.get("disease_name")).strip_edges() != "":
			return false

	return true


func _is_prescription_herbs_empty() -> bool:
	if current_prescription == null:
		return true

	if current_prescription.has_method("is_empty"):
		return current_prescription.is_empty()

	if not current_prescription.has_method("get_herbs_by_role"):
		return true

	return (
		current_prescription.get_herbs_by_role(ROLE_JUN).is_empty()
		and current_prescription.get_herbs_by_role(ROLE_CHEN).is_empty()
		and current_prescription.get_herbs_by_role(ROLE_ZUO).is_empty()
		and current_prescription.get_herbs_by_role(ROLE_SHI).is_empty()
	)


# =========================================================
# 四区列表选中事件
# =========================================================
func _on_jun_list_item_selected(_index: int) -> void:
	_set_selected_role(ROLE_JUN)


func _on_chen_list_item_selected(_index: int) -> void:
	_set_selected_role(ROLE_CHEN)


func _on_zuo_list_item_selected(_index: int) -> void:
	_set_selected_role(ROLE_ZUO)


func _on_shi_list_item_selected(_index: int) -> void:
	_set_selected_role(ROLE_SHI)


func _remove_clicked_role_item(role_name: String, list_node: ItemList, index: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return

	if list_node == null:
		return

	if index < 0 or index >= list_node.item_count:
		return

	_set_selected_role(role_name)

	var herb_id := str(list_node.get_item_metadata(index))
	if herb_id == "":
		emit_signal("info_requested", "未找到要移除的药材")
		return

	var herb_name := list_node.get_item_text(index).split("  ")[0]
	remove_herb_from_prescription(herb_id)
	emit_signal("info_requested", "已移除%s区药材：%s" % [role_name, herb_name])


func _on_jun_list_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	_remove_clicked_role_item(ROLE_JUN, jun_list, index, mouse_button_index)


func _on_chen_list_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	_remove_clicked_role_item(ROLE_CHEN, chen_list, index, mouse_button_index)


func _on_zuo_list_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	_remove_clicked_role_item(ROLE_ZUO, zuo_list, index, mouse_button_index)


func _on_shi_list_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	_remove_clicked_role_item(ROLE_SHI, shi_list, index, mouse_button_index)


# =========================================================
# 点击空白时也切换当前区域
# =========================================================
func _on_jun_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected_role(ROLE_JUN)


func _on_chen_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected_role(ROLE_CHEN)


func _on_zuo_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected_role(ROLE_ZUO)


func _on_shi_list_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_selected_role(ROLE_SHI)


# =========================================================
# 窗口关闭
# 这里只负责隐藏自己，不处理 Clinic 的 info_label
# =========================================================
# 关闭开方窗口
func close_window() -> void:
	# 当前窗口关闭时只隐藏，不销毁
	hide()
# =========================================================
# Esc 快捷键关闭窗口
# =========================================================

# =========================================================
# Clinic 主界面窗口快捷键转发
# =========================================================
const CLINIC_SHORTCUT_OPEN_PULSE := KEY_F1
const CLINIC_SHORTCUT_OPEN_PRESCRIPTION := KEY_F2
const CLINIC_SHORTCUT_OPEN_CLINICAL_LOG := KEY_F3

const ROLE_SHORTCUT_JUN := KEY_1
const ROLE_SHORTCUT_CHEN := KEY_2
const ROLE_SHORTCUT_ZUO := KEY_3
const ROLE_SHORTCUT_SHI := KEY_4
const ROLE_SHORTCUT_KP_JUN := KEY_KP_1
const ROLE_SHORTCUT_KP_CHEN := KEY_KP_2
const ROLE_SHORTCUT_KP_ZUO := KEY_KP_3
const ROLE_SHORTCUT_KP_SHI := KEY_KP_4


func _input(event: InputEvent) -> void:
	if _try_handle_role_shortcut(event):
		return

	if _try_handle_clinic_window_shortcut(event):
		return


func _try_handle_role_shortcut(event: InputEvent) -> bool:
	# 只在开方窗口显示时处理 1/2/3/4，避免影响 Clinic 或其它窗口。
	if not visible:
		return false

	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	if key_event.alt_pressed or key_event.ctrl_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return false

	match key_event.keycode:
		ROLE_SHORTCUT_JUN, ROLE_SHORTCUT_KP_JUN:
			_set_selected_role(ROLE_JUN)
		ROLE_SHORTCUT_CHEN, ROLE_SHORTCUT_KP_CHEN:
			_set_selected_role(ROLE_CHEN)
		ROLE_SHORTCUT_ZUO, ROLE_SHORTCUT_KP_ZUO:
			_set_selected_role(ROLE_ZUO)
		ROLE_SHORTCUT_SHI, ROLE_SHORTCUT_KP_SHI:
			_set_selected_role(ROLE_SHI)
		_:
			return false

	get_viewport().set_input_as_handled()
	return true


func _try_handle_clinic_window_shortcut(event: InputEvent) -> bool:
	if not visible:
		return false

	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	if key_event.alt_pressed or key_event.ctrl_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return false

	var window_controller := _find_clinic_window_controller()
	if window_controller == null:
		return false

	match key_event.keycode:
		CLINIC_SHORTCUT_OPEN_PULSE:
			if window_controller.has_method("open_pulse_window"):
				window_controller.open_pulse_window()
			else:
				return false
		CLINIC_SHORTCUT_OPEN_PRESCRIPTION:
			if window_controller.has_method("open_prescription_window"):
				window_controller.open_prescription_window()
			else:
				return false
		CLINIC_SHORTCUT_OPEN_CLINICAL_LOG:
			if window_controller.has_method("open_clinical_log_window"):
				window_controller.open_clinical_log_window()
			else:
				return false
		_:
			return false

	get_viewport().set_input_as_handled()
	return true


func _find_clinic_window_controller() -> Node:
	var node := get_parent()
	while node != null:
		var controller := node.find_child("ClinicWindowController", true, false)
		if controller != null:
			return controller

		node = node.get_parent()

	return null

func _unhandled_input(event: InputEvent) -> void:
	# 窗口未显示时，不处理 Esc，避免影响其他界面
	if not visible:
		return

	# 只处理键盘事件
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey

	# 只处理按下瞬间，忽略长按重复触发
	if not key_event.pressed or key_event.echo:
		return

	# 只响应 Esc 键
	if key_event.keycode != KEY_ESCAPE:
		return

	# 关闭当前窗口
	close_window()

	# 阻止 Esc 继续向下传递，避免影响其他窗口或主场景
	get_viewport().set_input_as_handled()


func _on_close_requested() -> void:
	hide()

# =========================================================
# 疾病诊断搜索
# =========================================================
func load_all_diseases() -> void:
	all_diseases.clear()

	if typeof(DiseaseDB) == TYPE_NIL:
		emit_signal("info_requested", "疾病数据库未初始化")
		return

	if not DiseaseDB.has_method("get_all_diseases"):
		emit_signal("info_requested", "DiseaseDB 缺少 get_all_diseases()")
		return

	all_diseases = DiseaseDB.get_all_diseases()
	_ensure_disease_button_cache()
	_apply_disease_filter()


func _refresh_disease_list(filter_text: String = "") -> void:
	# 兼容旧调用：不再重建 Button，只更新搜索词和 visible。
	disease_search_keyword = _normalize_disease_search_text(filter_text)
	_ensure_disease_button_cache()
	_apply_disease_filter()


func _ensure_disease_button_cache() -> void:
	if disease_list == null:
		return
	if typeof(DiseaseDB) == TYPE_NIL:
		return

	var db_instance_id: int = int(DiseaseDB.get_instance_id())
	if not _disease_button_by_id.is_empty() and db_instance_id == _cached_disease_db_instance_id:
		return

	_clear_disease_button_cache()
	_cached_disease_db_instance_id = db_instance_id

	for disease in all_diseases:
		var disease_name := _get_disease_name(disease)
		var disease_id := _get_disease_id(disease)

		if disease_name == "" or disease_id == "":
			continue

		var disease_id_raw := disease_id.to_lower()
		_disease_search_record_by_id[disease_id] = {
			"name": _normalize_disease_search_text(disease_name),
			"pinyin": _normalize_disease_search_text(disease_id_raw),
			"initials": _get_disease_id_initials(disease_id_raw)
		}

		var btn := Button.new()
		btn.text = disease_name
		btn.custom_minimum_size = Vector2(120, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.set_meta("disease_id", disease_id)
		btn.set_meta("disease_name", disease_name)
		btn.pressed.connect(_on_disease_selected.bind(disease_name, disease_id))

		disease_list.add_child(btn)
		btn.hide()
		_disease_button_by_id[disease_id] = btn


func _clear_disease_button_cache() -> void:
	if disease_list != null:
		for child in disease_list.get_children():
			child.queue_free()

	_disease_button_by_id.clear()
	_disease_search_record_by_id.clear()


func _on_disease_search_text_changed(new_text: String) -> void:
	if _suppress_search_signal:
		return

	disease_search_keyword = _normalize_disease_search_text(new_text)
	if _disease_search_timer == null:
		_apply_disease_filter()
		return

	_disease_search_timer.start(SEARCH_DEBOUNCE_SECONDS)


func _on_disease_search_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	if disease_search == null or disease_search.text == "":
		return

	disease_search.clear()
	disease_search.grab_focus()

	if _disease_search_timer != null:
		_disease_search_timer.stop()
	disease_search_keyword = ""
	_apply_disease_filter()
	get_viewport().set_input_as_handled()


func _apply_disease_filter() -> void:
	if disease_list == null:
		return

	_ensure_disease_button_cache()

	for disease_id_value in _disease_button_by_id.keys():
		var disease_id := str(disease_id_value)
		var button_value = _disease_button_by_id.get(disease_id, null)
		if not (button_value is Button):
			continue
		var button = button_value

		var should_show = bool(Unlock.is_disease_unlocked(disease_id))
		if should_show and disease_search_keyword != "":
			var record = {}
			var record_value = _disease_search_record_by_id.get(disease_id, {})
			if typeof(record_value) == TYPE_DICTIONARY:
				record = record_value
			should_show = (
				str(record.get("name", "")).contains(disease_search_keyword)
				or str(record.get("pinyin", "")).contains(disease_search_keyword)
				or str(record.get("initials", "")).contains(disease_search_keyword)
			)

		button.visible = should_show


func _on_disease_selected(disease_name: String, disease_id: String = "") -> void:
	if current_prescription == null:
		emit_signal("info_requested", "当前处方未初始化")
		return

	if disease_id.strip_edges() == "":
		emit_signal("info_requested", "疾病数据缺少 disease_id，无法选择")
		return

	# 双保险：即使按钮被旧列表残留或外部调用触发，也不允许选择未解锁疾病。
	if not Unlock.is_disease_unlocked(disease_id):
		emit_signal("info_requested", "该疾病尚未解锁，不能用于断病")
		_refresh_disease_list(disease_search_keyword)
		return

	selected_disease_name = disease_name
	selected_disease_id = disease_id
	_set_current_prescription_disease(disease_id, disease_name)

	if disease_search != null:
		_suppress_search_signal = true
		disease_search.text = disease_name
		disease_search.caret_column = disease_search.text.length()
		_suppress_search_signal = false

	if _disease_search_timer != null:
		_disease_search_timer.stop()
	disease_search_keyword = _normalize_disease_search_text(disease_name)
	_apply_disease_filter()
	emit_signal("info_requested", "已选择疾病诊断：%s" % disease_name)


func _clear_selected_disease() -> void:
	disease_search_keyword = ""
	selected_disease_id = ""
	selected_disease_name = ""

	if current_prescription != null and current_prescription.has_method("clear_disease"):
		current_prescription.clear_disease()
	else:
		_set_current_prescription_disease("", "")

	if disease_search != null:
		_suppress_search_signal = true
		disease_search.clear()
		_suppress_search_signal = false

	if _disease_search_timer != null:
		_disease_search_timer.stop()
	_apply_disease_filter()


func _sync_selected_disease_from_prescription() -> void:
	selected_disease_id = ""
	selected_disease_name = ""

	if current_prescription == null:
		return

	var prescription_disease_id := ""
	var prescription_disease_name := ""

	if _object_has_property(current_prescription, "disease_id"):
		prescription_disease_id = str(current_prescription.get("disease_id")).strip_edges()

	if _object_has_property(current_prescription, "disease_name"):
		prescription_disease_name = str(current_prescription.get("disease_name")).strip_edges()

	selected_disease_id = prescription_disease_id
	selected_disease_name = prescription_disease_name
	disease_search_keyword = _normalize_disease_search_text(prescription_disease_name)

	if disease_search != null:
		_suppress_search_signal = true
		disease_search.text = prescription_disease_name
		disease_search.caret_column = disease_search.text.length()
		_suppress_search_signal = false


func _set_current_prescription_disease(disease_id: String, disease_name: String) -> void:
	if current_prescription == null:
		return

	# 新版 Prescription.gd 使用 disease_id + disease_name，后续评分优先比较 disease_id。
	if current_prescription.has_method("set_disease"):
		current_prescription.set_disease(disease_id, disease_name)
		return

	# 兼容旧版 Prescription.gd。
	if _object_has_property(current_prescription, "disease_id"):
		current_prescription.set("disease_id", disease_id)

	if _object_has_property(current_prescription, "disease_name"):
		current_prescription.set("disease_name", disease_name)
		return

	if current_prescription.has_method("set_disease_name"):
		current_prescription.set_disease_name(disease_name)


func _object_has_property(target, property_name: String) -> bool:
	if target == null:
		return false

	if not (target is Object):
		return false

	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true

	return false


func _is_disease_match_search(disease_name: String, disease_id: String = "") -> bool:
	if disease_search_keyword == "":
		return true

	var normalized_name := _normalize_disease_search_text(disease_name)
	var normalized_id := _normalize_disease_search_text(disease_id)
	var disease_id_initials := _get_disease_id_initials(disease_id)

	return (
		normalized_name.contains(disease_search_keyword)
		or normalized_id.contains(disease_search_keyword)
		or disease_id_initials.contains(disease_search_keyword)
	)


func _normalize_disease_search_text(value: String) -> String:
	return value.strip_edges().to_lower() \
		.replace("_", "") \
		.replace("-", "") \
		.replace(" ", "")


func _get_disease_id_initials(disease_id: String) -> String:
	var parts := disease_id.to_lower().split("_", false)
	var initials := ""

	for part in parts:
		if part.length() > 0:
			initials += part.substr(0, 1)

	return initials


func _get_disease_name(disease) -> String:
	if disease == null:
		return ""

	if disease is Dictionary:
		if disease.has("disease_name"):
			return str(disease.get("disease_name", "")).strip_edges()
		if disease.has("name"):
			return str(disease.get("name", "")).strip_edges()
		if disease.has("display_name"):
			return str(disease.get("display_name", "")).strip_edges()

	if _object_has_property(disease, "disease_name"):
		return str(disease.get("disease_name")).strip_edges()
	if _object_has_property(disease, "name"):
		return str(disease.get("name")).strip_edges()

	return str(disease).strip_edges()


func _get_disease_id(disease) -> String:
	if disease == null:
		return ""

	if disease is Dictionary:
		if disease.has("disease_id"):
			return str(disease.get("disease_id", "")).strip_edges()
		if disease.has("id"):
			return str(disease.get("id", "")).strip_edges()

	if _object_has_property(disease, "disease_id"):
		return str(disease.get("disease_id")).strip_edges()
	if _object_has_property(disease, "id"):
		return str(disease.get("id")).strip_edges()

	return ""
