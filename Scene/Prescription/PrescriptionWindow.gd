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

# 没有对应医书条目的数据统一排在最后。
const SORT_INDEX_FALLBACK := 2147483647

# 方剂搜索与预制套方分开控制：
# - 方剂本身已解锁：搜索方名时即可显示该方剂包含的药材。
# - 同一方剂累计 5 次“妙手回春”：才开放该方剂的一键预制套方。

# 开方窗口固定位置，和场景中的初始坐标保持一致。
@export var fixed_window_position: Vector2i = Vector2i(5, 66)


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
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		title = tr("UI_PRESCRIPTION_WINDOW_TITLE")
		var selected_unit := unit_option.selected if unit_option != null else 1
		_setup_unit_option()
		unit_option.select(clampi(selected_unit, 0, unit_option.item_count - 1))
		_refresh_localized_dynamic_names()
		_refresh_prescription_list()


func _refresh_localized_dynamic_names() -> void:
	# 语言切换后，动态按钮文字和搜索缓存都必须按当前语言重建。
	_clear_herb_button_cache()
	_clear_formula_button_cache()
	_clear_disease_button_cache()

	_formula_search_records.clear()
	_cached_herb_db_instance_id = 0
	_cached_formula_db_instance_id = 0
	_cached_disease_db_instance_id = 0

	if herb_database != null:
		_ensure_herb_button_cache()
	if formula_database != null:
		_ensure_formula_search_cache()

	# all_diseases 已由 load_all_diseases() 缓存；这里只重建按钮即可。
	if not all_diseases.is_empty():
		_ensure_disease_button_cache()

	_apply_herb_filter()
	_apply_disease_filter()


func _is_english_search_locale() -> bool:
	return LocalizedName.is_english_locale()


func _build_localized_search_record(localized_name: String, original_name: String, entity_id: String) -> Dictionary:
	if _is_english_search_locale():
		return {
			"name": LocalizedName.normalize_search_text(localized_name),
			"initials": LocalizedName.english_initials(localized_name)
		}

	return {
		"name": _normalize_herb_search_text(original_name),
		"pinyin": _normalize_herb_search_text(entity_id.to_lower()),
		"initials": _get_id_initials(entity_id.to_lower())
	}


func _localized_search_record_matches(record: Dictionary, keyword: String) -> bool:
	if keyword == "":
		return false

	if _is_english_search_locale():
		return (
			str(record.get("name", "")).contains(keyword)
			or str(record.get("initials", "")).begins_with(keyword)
		)

	return (
		str(record.get("name", "")).contains(keyword)
		or str(record.get("pinyin", "")).begins_with(keyword)
		or str(record.get("initials", "")).begins_with(keyword)
	)


func _ready() -> void:
	title = tr("UI_PRESCRIPTION_WINDOW_TITLE")
	# 初始化时恢复固定位置。
	position = fixed_window_position

	# 每次开方窗口从隐藏变为显示时，默认把键盘焦点放到疾病搜索栏。
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

	_setup_unit_option()
	_setup_search_debounce_timers()
	_connect_signals()
	_setup_player_hint_dialog()
	_set_selected_role(ROLE_JUN)
	load_all_diseases()

# =========================================================
# 窗口位置锁定
# =========================================================
func _process(_delta: float) -> void:
	# 窗口显示期间，阻止玩家拖动标题栏改变窗口位置。
	if visible and position != fixed_window_position:
		position = fixed_window_position


func _on_visibility_changed() -> void:
	if not visible:
		return

	# 每次打开开方窗口都把单位恢复为“钱”。
	if unit_option != null and unit_option.item_count > 1:
		unit_option.select(1)

	# 延迟到本帧 UI 完成显示后再获取焦点，避免 show() 同帧被其它控件抢走。
	call_deferred("_focus_disease_search")


func _focus_disease_search() -> void:
	if not visible:
		return

	if disease_search == null:
		return

	disease_search.grab_focus()
	disease_search.caret_column = disease_search.text.length()


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

	# setup() 可能会在窗口复用时再次调用。
	# 先恢复上一次选中药材按钮的显示，避免旧按钮残留黄色高亮。
	if selected_herb_button != null and is_instance_valid(selected_herb_button):
		_set_herb_button_selected_style(selected_herb_button, false)

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
# 对外接口：清空搜索状态
# 用于 Clinic 当天结束时清除疾病 / 药材搜索残留。
# =========================================================
func clear_search_state() -> void:
	# 停止尚未执行的搜索 debounce，避免清空后旧关键词再次触发过滤。
	if _herb_search_timer != null:
		_herb_search_timer.stop()

	if _disease_search_timer != null:
		_disease_search_timer.stop()

	# 同时清空内部关键词与两个 LineEdit。
	herb_search_keyword = ""
	disease_search_keyword = ""

	# 修改 LineEdit 时暂时屏蔽 text_changed，避免重复启动 debounce。
	_suppress_search_signal = true

	if herb_search != null:
		herb_search.clear()

	if disease_search != null:
		disease_search.clear()

	_suppress_search_signal = false

	# 立即恢复完整的已解锁疾病 / 药材列表。
	_apply_herb_filter()
	_apply_disease_filter()


# =========================================================
# 初始化：单位下拉
# =========================================================
func _setup_unit_option() -> void:
	if unit_option == null:
		return

	unit_option.clear()
	unit_option.add_item(tr("UI_PRESCRIPTION_UNIT_FEN"))
	unit_option.add_item(tr("UI_PRESCRIPTION_UNIT_QIAN"))
	unit_option.add_item(tr("UI_PRESCRIPTION_UNIT_LIANG"))
	unit_option.add_item(tr("UI_PRESCRIPTION_UNIT_JIN"))
	unit_option.select(1)


# =========================================================
# 四、运行时界面显示：角色与药材剂量
# 内部处方仍使用中文角色和 fen/qian/liang/jin 单位。
# =========================================================
func _localized_role_name(role_name: String) -> String:
	match role_name:
		ROLE_JUN:
			return tr("UI_PRESCRIPTION_ROLE_JUN")
		ROLE_CHEN:
			return tr("UI_PRESCRIPTION_ROLE_CHEN")
		ROLE_ZUO:
			return tr("UI_PRESCRIPTION_ROLE_ZUO")
		ROLE_SHI:
			return tr("UI_PRESCRIPTION_ROLE_SHI")
	return role_name


func _format_amount_for_ui(amount: float, unit: String) -> String:
	if TranslationServer.get_locale().begins_with("zh"):
		return HerbUnit.format_amount(amount, unit)

	var remaining := HerbUnit.to_fen(amount, unit)
	if remaining <= 0:
		return tr("UI_PRESCRIPTION_ZERO_FEN")

	var parts: Array[String] = []
	for unit_data in [
		[HerbUnit.FEN_PER_JIN, "UI_PRESCRIPTION_UNIT_JIN"],
		[HerbUnit.FEN_PER_LIANG, "UI_PRESCRIPTION_UNIT_LIANG"],
		[HerbUnit.FEN_PER_QIAN, "UI_PRESCRIPTION_UNIT_QIAN"],
		[HerbUnit.FEN_PER_FEN, "UI_PRESCRIPTION_UNIT_FEN"]
	]:
		var unit_size: int = unit_data[0]
		var count: int = remaining / unit_size
		if count > 0:
			parts.append("%d %s" % [count, tr(unit_data[1])])
			remaining %= unit_size
	return " ".join(parts)


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
# 医书条目排序
# =========================================================
func _build_book_entry_sort_map(
	entry_type: String,
	data_id_property: String
) -> Dictionary:
	var result: Dictionary = {}

	if BookEntryDB == null:
		return result

	if not BookEntryDB.has_method("get_entries_by_type"):
		return result

	var entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type(entry_type)

	for entry in entries:
		if entry == null:
			continue

		var data_id := str(entry.get(data_id_property)).strip_edges()
		if data_id == "":
			continue

		result[data_id] = entry.sort_index

	return result


# =========================================================
# 药材按钮缓存 / 搜索
# =========================================================
func _ensure_herb_button_cache() -> void:
	if herb_list == null or herb_database == null:
		return
	if not herb_database.has_method("get_all_herbs"):
		emit_signal("info_requested", tr("UI_PRESCRIPTION_HERB_DB_METHOD_MISSING"))
		return

	var db_instance_id: int = int(herb_database.get_instance_id())
	if not _herb_button_by_id.is_empty() and db_instance_id == _cached_herb_db_instance_id:
		return

	_clear_herb_button_cache()
	_cached_herb_db_instance_id = db_instance_id

	var herbs = herb_database.get_all_herbs()
	var herb_sort_map := _build_book_entry_sort_map("herb", "herb_id")

	herbs.sort_custom(
		func(a, b) -> bool:
			var a_id := str(a.herb_id).strip_edges()
			var b_id := str(b.herb_id).strip_edges()
			var a_sort := int(herb_sort_map.get(a_id, SORT_INDEX_FALLBACK))
			var b_sort := int(herb_sort_map.get(b_id, SORT_INDEX_FALLBACK))

			if a_sort != b_sort:
				return a_sort < b_sort

			return a_id.naturalnocasecmp_to(b_id) < 0
	)

	for herb in herbs:
		if herb == null:
			continue

		var herb_id := str(herb.herb_id).strip_edges()
		if herb_id == "":
			continue

		var original_herb_name := str(herb.herb_name).strip_edges()
		var herb_name := LocalizedName.herb(herb_id, original_herb_name)

		_herb_search_record_by_id[herb_id] = _build_localized_search_record(
			herb_name,
			original_herb_name,
			herb_id
		)

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
	var formula_sort_map := _build_book_entry_sort_map("formula", "formula_id")

	formulas.sort_custom(
		func(a, b) -> bool:
			var a_id := str(a.formula_id).strip_edges()
			var b_id := str(b.formula_id).strip_edges()
			var a_sort := int(formula_sort_map.get(a_id, SORT_INDEX_FALLBACK))
			var b_sort := int(formula_sort_map.get(b_id, SORT_INDEX_FALLBACK))

			if a_sort != b_sort:
				return a_sort < b_sort

			return a_id.naturalnocasecmp_to(b_id) < 0
	)

	for formula in formulas:
		if formula == null:
			continue

		var formula_id := str(formula.formula_id).strip_edges()
		if formula_id == "":
			continue
		var original_formula_name := str(formula.formula_name).strip_edges()
		var localized_formula_name := LocalizedName.formula(formula_id, original_formula_name)
		var formula_search_record := _build_localized_search_record(
			localized_formula_name,
			original_formula_name,
			formula_id
		)
		formula_search_record["formula"] = formula
		formula_search_record["formula_id"] = formula_id
		_formula_search_records.append(formula_search_record)

		# 预制方剂按钮也只创建一次；搜索时仅切换 visible。
		var formula_button := Button.new()
		formula_button.text = localized_formula_name
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

	# 先收集“当前搜索词命中的已解锁方剂”中包含的全部药材 ID。
	# 方剂本身一旦解锁，输入方剂名就显示其组成药材；
	# 对应方剂累计 5 次“妙手回春”后，才额外显示可一键套用的方剂按钮。
	var formula_herb_ids: Dictionary = {}
	if herb_search_keyword != "":
		for record_value in _formula_search_records:
			if typeof(record_value) != TYPE_DICTIONARY:
				continue

			var formula_record: Dictionary = record_value
			var formula = formula_record.get("formula", null)
			if formula == null or not _is_formula_unlocked(formula):
				continue
			if not _formula_record_matches(formula_record):
				continue
			if not formula.has_method("get_all_ingredients"):
				continue

			for ingredient in formula.get_all_ingredients():
				if ingredient == null:
					continue

				if not ingredient.has_method("get_herb_id"):
					continue
				var ingredient_herb_id := str(ingredient.get_herb_id()).strip_edges()

				if ingredient_herb_id != "":
					formula_herb_ids[ingredient_herb_id] = true

	# 普通药材仍按自身名称 / 拼音 / 首字母匹配；
	# 若药材属于命中的方剂，也强制显示。
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

			var matches_herb_search := _localized_search_record_matches(
				record,
				herb_search_keyword
			)
			var belongs_to_matched_formula := bool(formula_herb_ids.get(herb_id, false))
			should_show = matches_herb_search or belongs_to_matched_formula

		button.visible = should_show

	_apply_formula_filter()


func _is_formula_preset_unlocked(formula) -> bool:
	if formula == null:
		return false
	if Unlock == null or not Unlock.has_method("is_preset_formula_unlocked"):
		return false

	var formula_id := str(formula.formula_id).strip_edges()
	if formula_id == "":
		return false

	return bool(Unlock.is_preset_formula_unlocked(formula_id))


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
	return _localized_search_record_matches(record, herb_search_keyword)


func _apply_formula_filter() -> void:
	# 无关键词时不显示全部预制方剂。
	# 每个方剂独立检查是否已累计 5 次“妙手回春”。
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
		if (
			formula != null
			and _is_formula_unlocked(formula)
			and _is_formula_preset_unlocked(formula)
		):
			should_show = _formula_record_matches(record)

		button_value.visible = should_show


func _on_formula_button_pressed(formula) -> void:
	if not _is_formula_unlocked(formula):
		emit_signal("info_requested", tr("UI_PRESCRIPTION_FORMULA_LOCKED"))
		_apply_herb_filter()
		return

	if not _is_formula_preset_unlocked(formula):
		emit_signal("info_requested", tr("UI_PRESCRIPTION_PRESET_LOCKED"))
		_apply_herb_filter()
		return

	if current_prescription == null:
		emit_signal("info_requested", tr("UI_PRESCRIPTION_NOT_INITIALIZED"))
		return

	if herb_database == null:
		emit_signal("info_requested", tr("UI_PRESCRIPTION_HERB_DB_NOT_INITIALIZED"))
		return

	if formula == null or not formula.has_method("get_group_by_role"):
		emit_signal("info_requested", tr("UI_PRESCRIPTION_INVALID_FORMULA"))
		return

	# 先完整校验所有组成药材，再修改玩家当前处方，避免半途中断破坏旧处方。
	var fill_items: Array = []
	for role_name in [ROLE_JUN, ROLE_CHEN, ROLE_ZUO, ROLE_SHI]:
		var ingredient_group = formula.get_group_by_role(role_name)

		for ingredient in ingredient_group:
			if ingredient == null:
				emit_signal("info_requested", tr("UI_PRESCRIPTION_EMPTY_INGREDIENT"))
				return

			var herb_id := str(ingredient.get_herb_id()).strip_edges()
			var amount := float(ingredient.amount)
			var unit := str(ingredient.unit).strip_edges()
			var herb = herb_database.get_herb_by_id(herb_id)

			if herb_id == "" or herb == null:
				emit_signal("info_requested", tr("UI_PRESCRIPTION_HERB_MISSING_FMT") % herb_id)
				return

			if amount <= 0.0 or not HerbUnit.is_valid_unit(unit):
				emit_signal("info_requested", tr("UI_PRESCRIPTION_INVALID_DOSE_FMT") % str(herb.herb_name))
				return

			fill_items.append({
				"herb": herb,
				"amount": amount,
				"unit": unit,
				"role": role_name
			})

	if fill_items.is_empty():
		emit_signal("info_requested", tr("UI_PRESCRIPTION_NO_INGREDIENTS"))
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

	emit_signal("info_requested", tr("UI_PRESCRIPTION_PRESET_FILLED_FMT") % str(formula.formula_name))


func _normalize_herb_search_text(value: String) -> String:
	return value.strip_edges().to_lower() \
		.replace("_", "") \
		.replace("-", "") \
		.replace(" ", "") \
		.replace("'", "")


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
		emit_signal("info_requested", tr("UI_PRESCRIPTION_NOT_INITIALIZED"))
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
			emit_signal("info_requested", tr("UI_PRESCRIPTION_INCREASE_FAILED_FMT") % herb_button.text)
			return

		emit_signal("info_requested", tr("UI_PRESCRIPTION_ADDED_TOTAL_FMT") % [
			_localized_role_name(current_selected_role),
			herb_button.text,
			_format_amount_for_ui(new_amount, add_unit)
		])
		return

	# 不存在：首次加入
	var ok_add := add_herb_by_id(selected_herb_id, add_amount, add_unit)
	if not ok_add:
		emit_signal("info_requested", tr("UI_PRESCRIPTION_ADD_FAILED_FMT") % herb_button.text)
		return

	emit_signal("info_requested", tr("UI_PRESCRIPTION_ADDED_FMT") % [
		_localized_role_name(current_selected_role),
		herb_button.text,
		_format_amount_for_ui(add_amount, add_unit)
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
		emit_signal("info_requested", tr("UI_PRESCRIPTION_NOT_INITIALIZED"))
		return

	if herb_id == "":
		emit_signal("info_requested", tr("UI_PRESCRIPTION_NOT_FOUND_TO_DECREASE"))
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
		emit_signal("info_requested", tr("UI_PRESCRIPTION_HERB_NOT_ADDED_FMT") % herb_name)
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
		emit_signal("info_requested", tr("UI_PRESCRIPTION_REMOVED_FMT") % [_localized_role_name(target_role), herb_name])
		return

	# 仍然大于 0，则保留并更新为当前单位显示
	var new_amount := HerbUnit.from_fen(new_total_fen, decrease_unit)
	var ok_update := set_prescription_herb_amount(herb_id, new_amount, decrease_unit)
	if not ok_update:
		emit_signal("info_requested", tr("UI_PRESCRIPTION_DECREASE_FAILED_FMT") % herb_name)
		return

	emit_signal("info_requested", tr("UI_PRESCRIPTION_DECREASED_FMT") % [
		_localized_role_name(target_role),
		herb_name,
		_format_amount_for_ui(new_amount, decrease_unit)
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

		var text := "%s  %s" % [herb_name, _format_amount_for_ui(amount, unit)]
		list_node.add_item(text)

		var index := list_node.item_count - 1
		list_node.set_item_metadata(index, herb_id)


# =========================================================
# 处方区辅助
# =========================================================
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
	emit_signal("info_requested", tr("UI_PRESCRIPTION_CLEARED"))


func _on_submit_button_pressed() -> void:
	if _is_disease_empty():
		_show_player_hint(tr("UI_PRESCRIPTION_ENTER_DISEASE"))
		return

	if _is_prescription_herbs_empty():
		_show_player_hint(tr("UI_PRESCRIPTION_ENTER_HERB"))
		return

	emit_signal("submit_requested")


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
		emit_signal("info_requested", tr("UI_PRESCRIPTION_NOT_FOUND_TO_REMOVE"))
		return

	var herb_name := list_node.get_item_text(index).split("  ")[0]
	remove_herb_from_prescription(herb_id)
	emit_signal("info_requested", tr("UI_PRESCRIPTION_REMOVED_FMT") % [_localized_role_name(role_name), herb_name])


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
	if _try_handle_escape(event):
		return

	if _try_handle_unit_shortcut(event):
		return

	if _try_handle_role_shortcut(event):
		return

	if _try_handle_clinic_window_shortcut(event):
		return


func _try_handle_escape(event: InputEvent) -> bool:
	if not visible:
		return false

	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	if key_event.keycode != KEY_ESCAPE:
		return false

	# 第一优先级：
	# 光标在药材搜索栏，并且搜索栏有内容时，Esc 只清空搜索。
	if herb_search != null and herb_search.has_focus() and herb_search.text != "":
		_on_herb_search_gui_input(event)
		return true

	# 光标在疾病搜索栏，并且搜索栏有内容时，Esc 只清空搜索。
	if disease_search != null and disease_search.has_focus() and disease_search.text != "":
		_on_disease_search_gui_input(event)
		return true

	# 第二优先级：
	# 搜索栏为空，或当前焦点不在搜索栏时，Esc 关闭整个开方窗口。
	# 本次 Esc 在这里结束，不继续传给 Main 的 PauseMenu。
	close_window()
	get_viewport().set_input_as_handled()
	return true


# =========================================================
# 单位快捷键
# `（数字 1 左边的键）：向上切换单位
# Tab：向下切换单位
# 单位顺序：分 → 钱 → 两 → 斤；默认单位为钱。
# =========================================================
func _try_handle_unit_shortcut(event: InputEvent) -> bool:
	# 只在开方窗口显示时处理，避免影响 Clinic 或其它窗口。
	if not visible:
		return false

	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	if key_event.alt_pressed or key_event.ctrl_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return false

	var direction: int = 0

	# 数字 1 左边的 ` 键：向上切换。
	# physical_keycode 优先保证按键物理位置；keycode 作为兼容兜底。
	if key_event.physical_keycode == KEY_QUOTELEFT or key_event.keycode == KEY_QUOTELEFT:
		direction = -1
	# Tab：向下切换，并在这里消费事件，避免 Tab 同时切换 UI 焦点。
	elif key_event.keycode == KEY_TAB or key_event.physical_keycode == KEY_TAB:
		direction = 1
	else:
		return false

	_shift_unit_selection(direction)
	get_viewport().set_input_as_handled()
	return true


func _shift_unit_selection(direction: int) -> void:
	if unit_option == null or unit_option.item_count <= 0:
		return

	var current_index: int = unit_option.selected
	if current_index < 0:
		current_index = 1

	# 到最上 / 最下时停止，不循环跳转。
	var next_index: int = clampi(
		current_index + direction,
		0,
		unit_option.item_count - 1
	)

	if next_index == current_index:
		return

	unit_option.select(next_index)


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

	var shortcut_target := _find_window_shortcut_target()
	if shortcut_target == null:
		return false

	var handled := false

	match key_event.keycode:
		CLINIC_SHORTCUT_OPEN_PULSE:
			handled = _open_shortcut_window(shortcut_target, "pulse")

		CLINIC_SHORTCUT_OPEN_PRESCRIPTION:
			handled = _open_shortcut_window(shortcut_target, "prescription")

		CLINIC_SHORTCUT_OPEN_CLINICAL_LOG:
			handled = _open_shortcut_window(shortcut_target, "clinical_log")

		_:
			return false

	if not handled:
		return false

	get_viewport().set_input_as_handled()
	return true


func _open_shortcut_window(shortcut_target: Node, window_type: String) -> bool:
	if shortcut_target == null:
		return false

	match window_type:
		"pulse":
			# Clinic 使用 ClinicWindowController 的公开接口。
			if shortcut_target.has_method("open_pulse_window"):
				shortcut_target.call("open_pulse_window")
				return true

			# Story 治疗模式直接复用 Story.gd 已有按钮回调。
			if shortcut_target.has_method("_on_pulse_button_pressed"):
				shortcut_target.call("_on_pulse_button_pressed")
				return true

		"prescription":
			if shortcut_target.has_method("open_prescription_window"):
				shortcut_target.call("open_prescription_window")
				return true

			if shortcut_target.has_method("_on_prescription_button_pressed"):
				shortcut_target.call("_on_prescription_button_pressed")
				return true

		"clinical_log":
			if shortcut_target.has_method("open_clinical_log_window"):
				shortcut_target.call("open_clinical_log_window")
				return true

			if shortcut_target.has_method("_on_clinical_log_button_pressed"):
				shortcut_target.call("_on_clinical_log_button_pressed")
				return true

	return false


func _find_window_shortcut_target() -> Node:
	var node := get_parent()

	while node != null:
		# Story 优先：
		# Story 与 Clinic 会同时常驻 Main。旧代码一路递归 find_child，
		# 最后会从 Main 找到隐藏 Clinic 的 ClinicWindowController，
		# 导致 Story 窗口把 F1/F2/F3 错发给 Clinic。
		#
		# 只要当前祖先就是 Story 治疗界面，就立刻返回 Story，
		# 不再继续向 Main 搜索。
		if (
			node.has_method("_on_pulse_button_pressed")
			and node.has_method("_on_prescription_button_pressed")
			and node.has_method("_on_clinical_log_button_pressed")
		):
			return node

		# Clinic 只允许查找“当前祖先的直接子节点”控制器，
		# 禁止递归搜索其它常驻场景，避免再次串到错误的 Clinic 实例。
		var controller := node.get_node_or_null("ClinicWindowController")
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
		emit_signal("info_requested", tr("UI_PRESCRIPTION_DISEASE_DB_NOT_INITIALIZED"))
		return

	if not DiseaseDB.has_method("get_all_diseases"):
		emit_signal("info_requested", tr("UI_PRESCRIPTION_DISEASE_DB_METHOD_MISSING"))
		return

	all_diseases = DiseaseDB.get_all_diseases()
	var disease_sort_map := _build_book_entry_sort_map("disease", "disease_id")

	all_diseases.sort_custom(
		func(a, b) -> bool:
			var a_id := _get_disease_id(a)
			var b_id := _get_disease_id(b)
			var a_sort := int(disease_sort_map.get(a_id, SORT_INDEX_FALLBACK))
			var b_sort := int(disease_sort_map.get(b_id, SORT_INDEX_FALLBACK))

			if a_sort != b_sort:
				return a_sort < b_sort

			return a_id.naturalnocasecmp_to(b_id) < 0
	)

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
		var original_disease_name := _get_disease_name(disease)
		var disease_id := _get_disease_id(disease)

		if original_disease_name == "" or disease_id == "":
			continue

		var disease_name := LocalizedName.disease(disease_id, original_disease_name)
		_disease_search_record_by_id[disease_id] = _build_localized_search_record(
			disease_name,
			original_disease_name,
			disease_id
		)

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
			should_show = _localized_search_record_matches(
				record,
				disease_search_keyword
			)

		button.visible = should_show


func _on_disease_selected(disease_name: String, disease_id: String = "") -> void:
	if current_prescription == null:
		emit_signal("info_requested", tr("UI_PRESCRIPTION_NOT_INITIALIZED"))
		return

	if disease_id.strip_edges() == "":
		emit_signal("info_requested", tr("UI_PRESCRIPTION_DISEASE_ID_MISSING"))
		return

	# 双保险：即使按钮被旧列表残留或外部调用触发，也不允许选择未解锁疾病。
	if not Unlock.is_disease_unlocked(disease_id):
		emit_signal("info_requested", tr("UI_PRESCRIPTION_DISEASE_LOCKED"))
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
	emit_signal("info_requested", tr("UI_PRESCRIPTION_DIAGNOSIS_SELECTED_FMT") % disease_name)


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


func _normalize_disease_search_text(value: String) -> String:
	return value.strip_edges().to_lower() \
		.replace("_", "") \
		.replace("-", "") \
		.replace(" ", "") \
		.replace("'", "")


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
