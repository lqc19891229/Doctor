extends Window
class_name ClinicalLogWindow

# =========================================================
# ClinicalLogWindow.gd
# 行医记考窗口
#
# 作用：
# 1. 在 Clinic 场景中作为子窗口使用。
# 2. 白天显示已经同步到 clinical_log 的疾病 / 方剂 / 药材条目。
# 3. 支持搜索、列表选择、详情显示。
# 4. 支持疾病 / 方剂 / 药材详情翻页。
#
# 覆盖方式：
# 把本文件覆盖到：res://Scene/clinical_log/ClinicalLogWindow.gd
# 不需要手动修改 clinical_log_window.tscn。
# =========================================================


# =========================================================
# 一、节点引用
# =========================================================

@onready var tab_container: TabContainer = $Panel/MarginContainer/VBoxContainer/TabContainer

# 疾病页
@onready var disease_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Left/SearchBar
@onready var disease_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Left/DiseaseList
@onready var disease_right_panel: Control = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Right
@onready var disease_detail_scroll: ScrollContainer = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Right/DiseaseDetailScroll
@onready var disease_detail_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Right/DiseaseDetailScroll/DiseaseDetail

# 方剂页
@onready var formula_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Left/SearchBar
@onready var formula_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Left/FormulaList
@onready var formula_right_panel: Control = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Right
@onready var formula_detail_scroll: ScrollContainer = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Right/FormulaDetailScroll
@onready var formula_detail_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Right/FormulaDetailScroll/FormulaDetail

# 药材页
@onready var herb_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Left/SearchBar
@onready var herb_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Left/HerbList
@onready var herb_right_panel: Control = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Right
@onready var herb_detail_scroll: ScrollContainer = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Right/HerbDetailScroll
@onready var herb_detail_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Right/HerbDetailScroll/HerbDetail


# =========================================================
# 二、运行时缓存
# =========================================================

var all_disease_entries: Array[BookEntryData] = []
var all_formula_entries: Array[BookEntryData] = []
var all_herb_entries: Array[BookEntryData] = []

var visible_disease_entries: Array[BookEntryData] = []
var visible_formula_entries: Array[BookEntryData] = []
var visible_herb_entries: Array[BookEntryData] = []


# =========================================================
# 三、翻页状态
# =========================================================

# 每页显示多少竖列。
# 0 = 交给 ClassicalVerticalRichTextLabel 根据可见宽度自动估算。
# 如果画面仍然偏挤，可以改成 6、7、8。
@export var disease_columns_per_page: int = 0
@export var formula_columns_per_page: int = 0
@export var herb_columns_per_page: int = 0

# 普通 RichTextLabel 的兜底分页字符数。
# 只有详情节点没有挂 ClassicalVerticalRichTextLabel 时才会使用。
@export var fallback_chars_per_page: int = 220

# 疾病翻页控件和状态。
var disease_prev_page_button: Button
var disease_page_indicator: Label
var disease_next_page_button: Button
var _current_disease_detail_text: String = ""
var _disease_page_index: int = 0
var _disease_page_count: int = 1
var _disease_pages: Array[Dictionary] = []

# 方剂翻页控件和状态。
var formula_prev_page_button: Button
var formula_page_indicator: Label
var formula_next_page_button: Button
var _current_formula_detail_text: String = ""
var _formula_page_index: int = 0
var _formula_page_count: int = 1
var _formula_pages: Array[Dictionary] = []

# 药材翻页控件和状态。
var herb_prev_page_button: Button
var herb_page_indicator: Label
var herb_next_page_button: Button
var _current_herb_detail_text: String = ""
var _herb_page_index: int = 0
var _herb_page_count: int = 1
var _herb_pages: Array[Dictionary] = []


# =========================================================
# 四、生命周期
# =========================================================

func _ready() -> void:
	# 窗口默认隐藏。
	visible = false

	# 点击窗口关闭按钮时，只隐藏窗口，不销毁节点。
	close_requested.connect(_on_close_requested)

	# 设置页签标题。
	tab_container.set_tab_title(0, "疾病")
	tab_container.set_tab_title(1, "方剂")
	tab_container.set_tab_title(2, "药材")

	# 监听页签切换。
	# 方剂页和药材页第一次显示前处于隐藏状态，尺寸可能还是 0。
	# 切换页签后重新等待布局，再重新显示当前条目。
	if not tab_container.tab_changed.is_connected(_on_tab_changed):
		tab_container.tab_changed.connect(_on_tab_changed)

	# 搜索框文本变化时，刷新对应页面。
	disease_search_bar.text_changed.connect(_on_disease_search_changed)
	formula_search_bar.text_changed.connect(_on_formula_search_changed)
	herb_search_bar.text_changed.connect(_on_herb_search_changed)

	# 开启搜索框自带清除按钮。
	disease_search_bar.clear_button_enabled = true
	formula_search_bar.clear_button_enabled = true
	herb_search_bar.clear_button_enabled = true

	# 搜索框获得焦点时，按 Esc 清空当前搜索框。
	disease_search_bar.gui_input.connect(_on_search_bar_gui_input.bind(disease_search_bar))
	formula_search_bar.gui_input.connect(_on_search_bar_gui_input.bind(formula_search_bar))
	herb_search_bar.gui_input.connect(_on_search_bar_gui_input.bind(herb_search_bar))

	# 列表选择信号。
	disease_list.item_selected.connect(_on_disease_list_item_selected)
	formula_list.item_selected.connect(_on_formula_list_item_selected)
	herb_list.item_selected.connect(_on_herb_list_item_selected)

	# 初始化三类详情翻页控件。
	_setup_all_page_controls()

	# 初始化空状态。
	_clear_disease_detail()
	_clear_formula_detail()
	_clear_herb_detail()


# =========================================================
# 五、对外接口
# =========================================================

func open_window() -> void:
	# 先显示窗口，让 Godot 开始计算窗口和子节点尺寸。
	show()

	# 如果窗口已经处于显示状态，再次打开时也要强制置顶。
	_bring_self_to_front()
	grab_focus()

	# 等一帧，确保 Window / ScrollContainer / RichTextLabel 完成第一次布局。
	await get_tree().process_frame

	# 再等一帧更稳，避免 RichTextLabel 尺寸仍是旧值或 0。
	await get_tree().process_frame

	# 等待期间可能被关闭，避免关闭后又刷新。
	if not visible:
		return

	# 尺寸稳定后再刷新列表和详情分页。
	refresh_view()

	# refresh_view 后再置顶一次，避免异步等待期间被其它窗口抢到前面。
	_bring_self_to_front()
	grab_focus()
	

func close_window() -> void:
	hide()


func refresh_view() -> void:
	_load_all_entries_from_unlock_state()
	_refresh_disease_page()
	_refresh_formula_page()
	_refresh_herb_page()


func _bring_self_to_front() -> void:
	# ClinicalLogWindow 是 Clinic 场景中的子窗口。
	# visible 已经为 true 时，单独 show() 不会改变同级窗口层级。
	# 把自己移动到父节点最后，可以保证再次按 F3 时重新显示在最前。
	var parent_node := get_parent()
	if parent_node == null:
		return

	parent_node.move_child(self, parent_node.get_child_count() - 1)


# =========================================================
# 六、加载数据
# =========================================================

func _load_all_entries_from_unlock_state() -> void:
	all_disease_entries.clear()
	all_formula_entries.clear()
	all_herb_entries.clear()

	var disease_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("disease")
	var formula_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("formula")
	var herb_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("herb")

	# 疾病：只显示已经同步到 clinical_log 的疾病。
	for entry in disease_entries:
		if entry == null:
			continue
		if not (entry is DiseaseBookEntryData):
			continue

		var disease_entry := entry as DiseaseBookEntryData
		if Unlock.is_disease_unlocked_in_clinical_log(disease_entry.disease_id):
			all_disease_entries.append(disease_entry)

	# 方剂：只显示已经同步到 clinical_log 的方剂。
	for entry in formula_entries:
		if entry == null:
			continue
		if not (entry is FormulaBookEntryData):
			continue

		var formula_entry := entry as FormulaBookEntryData
		if Unlock.is_formula_unlocked_in_clinical_log(formula_entry.formula_id):
			all_formula_entries.append(formula_entry)

	# 药材：只显示已经同步到 clinical_log 的药材。
	for entry in herb_entries:
		if entry == null:
			continue
		if not (entry is HerbBookEntryData):
			continue

		var herb_entry := entry as HerbBookEntryData
		if Unlock.is_herb_unlocked_in_clinical_log(herb_entry.herb_id):
			all_herb_entries.append(herb_entry)

	# 按标题排序，方便查找。
	all_disease_entries.sort_custom(func(a: BookEntryData, b: BookEntryData) -> bool:
		return a.title < b.title
	)
	all_formula_entries.sort_custom(func(a: BookEntryData, b: BookEntryData) -> bool:
		return a.title < b.title
	)
	all_herb_entries.sort_custom(func(a: BookEntryData, b: BookEntryData) -> bool:
		return a.title < b.title
	)


# =========================================================
# 七、列表刷新
# =========================================================

func _refresh_disease_page() -> void:
	visible_disease_entries = _filter_entries_by_keyword(all_disease_entries, disease_search_bar.text)
	_rebuild_item_list(disease_list, visible_disease_entries)

	if visible_disease_entries.is_empty():
		_clear_disease_detail()
		return

	disease_list.select(0)
	_show_disease_detail(0)


func _refresh_formula_page() -> void:
	visible_formula_entries = _filter_entries_by_keyword(all_formula_entries, formula_search_bar.text)
	_rebuild_item_list(formula_list, visible_formula_entries)

	if visible_formula_entries.is_empty():
		_clear_formula_detail()
		return

	formula_list.select(0)
	_show_formula_detail(0)


func _refresh_herb_page() -> void:
	visible_herb_entries = _filter_entries_by_keyword(all_herb_entries, herb_search_bar.text)
	_rebuild_item_list(herb_list, visible_herb_entries)

	if visible_herb_entries.is_empty():
		_clear_herb_detail()
		return

	herb_list.select(0)
	_show_herb_detail(0)


# =========================================================
# 八、搜索过滤
# =========================================================

func _filter_entries_by_keyword(source_entries: Array[BookEntryData], keyword: String) -> Array[BookEntryData]:
	var result: Array[BookEntryData] = []
	var clean_keyword := _normalize_clinical_log_search_text(keyword)

	# 搜索为空时，显示全部条目。
	if clean_keyword == "":
		for entry in source_entries:
			result.append(entry)
		return result

	# 支持三种搜索方式：
	# 1. 中文标题：例如“白术”
	# 2. 完整拼音：例如“baizhu”匹配 herb_id “bai_zhu”
	# 3. 拼音首字母：例如“bz”匹配 herb_id “bai_zhu”
	for entry in source_entries:
		if entry == null:
			continue

		if _is_entry_match_clinical_log_search(entry, clean_keyword):
			result.append(entry)

	return result


func _is_entry_match_clinical_log_search(entry: BookEntryData, clean_keyword: String) -> bool:
	if entry == null:
		return false

	var title_text := _normalize_clinical_log_search_text(entry.title)
	var entry_id_raw := str(entry.entry_id).to_lower()
	var entry_id_text := _normalize_clinical_log_search_text(entry_id_raw)
	var entry_id_initials := _get_clinical_log_id_initials(entry_id_raw)
	var data_id_raw := _get_entry_data_id(entry).to_lower()
	var data_id_text := _normalize_clinical_log_search_text(data_id_raw)
	var data_id_initials := _get_clinical_log_id_initials(data_id_raw)

	# 列表搜索只匹配条目名称和条目 ID，不匹配正文 detail_text。
	# 否则搜索“杏仁”时，正文里提到杏仁的“苏叶、陈皮、麻黄”等也会出现在药材列表中。
	return (
		title_text.contains(clean_keyword)
		or entry_id_text.contains(clean_keyword)
		or entry_id_initials.contains(clean_keyword)
		or data_id_text.contains(clean_keyword)
		or data_id_initials.contains(clean_keyword)
	)


func _get_entry_data_id(entry: BookEntryData) -> String:
	if entry is DiseaseBookEntryData:
		return str((entry as DiseaseBookEntryData).disease_id)

	if entry is FormulaBookEntryData:
		return str((entry as FormulaBookEntryData).formula_id)

	if entry is HerbBookEntryData:
		return str((entry as HerbBookEntryData).herb_id)

	return ""


func _normalize_clinical_log_search_text(value: String) -> String:
	return value.strip_edges().to_lower() \
		.replace("_", "") \
		.replace("-", "") \
		.replace(" ", "")


func _get_clinical_log_id_initials(value: String) -> String:
	var parts := value.to_lower().split("_", false)
	var initials := ""

	for part in parts:
		if part.length() > 0:
			initials += part.substr(0, 1)

	return initials


# =========================================================
# 九、列表重建
# =========================================================

func _rebuild_item_list(target_list: ItemList, entries: Array[BookEntryData]) -> void:
	if target_list == null:
		return

	target_list.clear()

	for entry in entries:
		if entry == null:
			continue

		target_list.add_item(entry.title)


# =========================================================
# 十、翻页控件创建
# =========================================================

func _setup_all_page_controls() -> void:
	# 疾病页翻页栏。
	var disease_controls := _setup_page_controls(
		disease_right_panel,
		disease_detail_scroll,
		"PageControls",
		"PrevPageButton",
		"PageIndicator",
		"NextPageButton"
	)
	disease_prev_page_button = disease_controls["prev"] as Button
	disease_page_indicator = disease_controls["indicator"] as Label
	disease_next_page_button = disease_controls["next"] as Button

	# 方剂页翻页栏。
	var formula_controls := _setup_page_controls(
		formula_right_panel,
		formula_detail_scroll,
		"PageControls",
		"PrevPageButton",
		"PageIndicator",
		"NextPageButton"
	)
	formula_prev_page_button = formula_controls["prev"] as Button
	formula_page_indicator = formula_controls["indicator"] as Label
	formula_next_page_button = formula_controls["next"] as Button

	# 药材页翻页栏。
	var herb_controls := _setup_page_controls(
		herb_right_panel,
		herb_detail_scroll,
		"PageControls",
		"PrevPageButton",
		"PageIndicator",
		"NextPageButton"
	)
	herb_prev_page_button = herb_controls["prev"] as Button
	herb_page_indicator = herb_controls["indicator"] as Label
	herb_next_page_button = herb_controls["next"] as Button

	# 连接按钮点击信号。先判断是否已连接，避免重复连接报错。
	if disease_prev_page_button != null and not disease_prev_page_button.pressed.is_connected(_on_disease_prev_page_pressed):
		disease_prev_page_button.pressed.connect(_on_disease_prev_page_pressed)
	if disease_next_page_button != null and not disease_next_page_button.pressed.is_connected(_on_disease_next_page_pressed):
		disease_next_page_button.pressed.connect(_on_disease_next_page_pressed)

	if formula_prev_page_button != null and not formula_prev_page_button.pressed.is_connected(_on_formula_prev_page_pressed):
		formula_prev_page_button.pressed.connect(_on_formula_prev_page_pressed)
	if formula_next_page_button != null and not formula_next_page_button.pressed.is_connected(_on_formula_next_page_pressed):
		formula_next_page_button.pressed.connect(_on_formula_next_page_pressed)

	if herb_prev_page_button != null and not herb_prev_page_button.pressed.is_connected(_on_herb_prev_page_pressed):
		herb_prev_page_button.pressed.connect(_on_herb_prev_page_pressed)
	if herb_next_page_button != null and not herb_next_page_button.pressed.is_connected(_on_herb_next_page_pressed):
		herb_next_page_button.pressed.connect(_on_herb_next_page_pressed)


func _setup_page_controls(right_panel: Control, detail_scroll: ScrollContainer, controls_name: String, prev_name: String, indicator_name: String, next_name: String) -> Dictionary:
	if right_panel == null:
		return {}

	var page_controls := right_panel.get_node_or_null(controls_name) as HBoxContainer
	if page_controls == null:
		page_controls = HBoxContainer.new()
		page_controls.name = controls_name
		right_panel.add_child(page_controls)

	var prev_button := page_controls.get_node_or_null(prev_name) as Button
	if prev_button == null:
		prev_button = Button.new()
		prev_button.name = prev_name
		prev_button.text = "上一页"
		page_controls.add_child(prev_button)

	var indicator := page_controls.get_node_or_null(indicator_name) as Label
	if indicator == null:
		indicator = Label.new()
		indicator.name = indicator_name
		indicator.text = "1/1"
		page_controls.add_child(indicator)

	var next_button := page_controls.get_node_or_null(next_name) as Button
	if next_button == null:
		next_button = Button.new()
		next_button.name = next_name
		next_button.text = "下一页"
		page_controls.add_child(next_button)

	prev_button.mouse_filter = Control.MOUSE_FILTER_STOP
	next_button.mouse_filter = Control.MOUSE_FILTER_STOP
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return {
		"prev": prev_button,
		"indicator": indicator,
		"next": next_button,
	}


# =========================================================
# 十一、详情显示
# =========================================================

func _show_disease_detail(index: int) -> void:
	if index < 0 or index >= visible_disease_entries.size():
		_clear_disease_detail()
		return

	var entry := visible_disease_entries[index]
	if entry == null:
		_clear_disease_detail()
		return

	_set_disease_detail_text_with_pages(_build_entry_detail_text(entry))


func _show_formula_detail(index: int) -> void:
	if index < 0 or index >= visible_formula_entries.size():
		_clear_formula_detail()
		return

	var entry := visible_formula_entries[index]
	if entry == null:
		_clear_formula_detail()
		return

	_set_formula_detail_text_with_pages(_build_entry_detail_text(entry))


func _show_herb_detail(index: int) -> void:
	if index < 0 or index >= visible_herb_entries.size():
		_clear_herb_detail()
		return

	var entry := visible_herb_entries[index]
	if entry == null:
		_clear_herb_detail()
		return

	_set_herb_detail_text_with_pages(_build_entry_detail_text(entry))


# 构建详情文本。
# 数据表里的 detail_text 已经包含标题，所以这里不额外拼接 entry.title。
func _build_entry_detail_text(entry: BookEntryData) -> String:
	if entry == null:
		return ""

	return entry.detail_text


# 设置详情文本。
# 如果详情节点挂了 ClassicalVerticalRichTextLabel，优先直接显示“预构建竖排页”。
# 这样翻页单位是竖列，不是粗略字符数，可以避免底部裁字。
func _set_detail_page(label: RichTextLabel, page_data: Dictionary) -> void:
	if label == null:
		return

	if label.has_method("set_prebuilt_vertical_page"):
		label.call("set_prebuilt_vertical_page", page_data)
		return

	label.text = str(page_data.get("text", ""))


# 构建详情分页。
# 古书竖排节点：按真实行数和真实列数分页。
# 普通 RichTextLabel：退回字符数分页。
func _build_detail_pages(label: RichTextLabel, value: String, columns_per_page: int) -> Array[Dictionary]:
	if label != null and label.has_method("build_source_text_pages"):
		var vertical_pages = label.call("build_source_text_pages", value, columns_per_page)
		if vertical_pages is Array and not vertical_pages.is_empty():
			return vertical_pages

	var result: Array[Dictionary] = []
	var safe_chars_per_page: int = max(1, fallback_chars_per_page)
	var page_count := _calculate_page_count(value, safe_chars_per_page)

	for page_index in range(page_count):
		result.append({
			"text": _get_page_text(value, page_index, safe_chars_per_page),
			"column_count": 1,
		})

	return result


# =========================================================
# 十二、疾病翻页
# =========================================================

func _set_disease_detail_text_with_pages(value: String) -> void:
	_current_disease_detail_text = value
	_disease_page_index = 0
	_disease_pages = _build_detail_pages(disease_detail_label, value, disease_columns_per_page)
	_disease_page_count = max(1, _disease_pages.size())
	_refresh_disease_detail_page()


func _refresh_disease_detail_page() -> void:
	_disease_page_index = clamp(_disease_page_index, 0, max(0, _disease_page_count - 1))
	if _disease_pages.is_empty():
		_disease_pages = [{"text": "", "column_count": 1}]
	_set_detail_page(disease_detail_label, _disease_pages[_disease_page_index])
	_reset_scroll_position(disease_detail_scroll)
	_update_disease_page_controls()


func _update_disease_page_controls() -> void:
	_update_page_controls(disease_prev_page_button, disease_page_indicator, disease_next_page_button, _disease_page_index, _disease_page_count)


func _on_disease_prev_page_pressed() -> void:
	if _disease_page_index <= 0:
		return

	_disease_page_index -= 1
	_refresh_disease_detail_page()


func _on_disease_next_page_pressed() -> void:
	if _disease_page_index >= _disease_page_count - 1:
		return

	_disease_page_index += 1
	_refresh_disease_detail_page()


# =========================================================
# 十三、方剂翻页
# =========================================================

func _set_formula_detail_text_with_pages(value: String) -> void:
	_current_formula_detail_text = value
	_formula_page_index = 0
	_formula_pages = _build_detail_pages(formula_detail_label, value, formula_columns_per_page)
	_formula_page_count = max(1, _formula_pages.size())
	_refresh_formula_detail_page()


func _refresh_formula_detail_page() -> void:
	_formula_page_index = clamp(_formula_page_index, 0, max(0, _formula_page_count - 1))
	if _formula_pages.is_empty():
		_formula_pages = [{"text": "", "column_count": 1}]
	_set_detail_page(formula_detail_label, _formula_pages[_formula_page_index])
	_reset_scroll_position(formula_detail_scroll)
	_update_formula_page_controls()


func _update_formula_page_controls() -> void:
	_update_page_controls(formula_prev_page_button, formula_page_indicator, formula_next_page_button, _formula_page_index, _formula_page_count)


func _on_formula_prev_page_pressed() -> void:
	if _formula_page_index <= 0:
		return

	_formula_page_index -= 1
	_refresh_formula_detail_page()


func _on_formula_next_page_pressed() -> void:
	if _formula_page_index >= _formula_page_count - 1:
		return

	_formula_page_index += 1
	_refresh_formula_detail_page()


# =========================================================
# 十四、药材翻页
# =========================================================

func _set_herb_detail_text_with_pages(value: String) -> void:
	_current_herb_detail_text = value
	_herb_page_index = 0
	_herb_pages = _build_detail_pages(herb_detail_label, value, herb_columns_per_page)
	_herb_page_count = max(1, _herb_pages.size())
	_refresh_herb_detail_page()


func _refresh_herb_detail_page() -> void:
	_herb_page_index = clamp(_herb_page_index, 0, max(0, _herb_page_count - 1))
	if _herb_pages.is_empty():
		_herb_pages = [{"text": "", "column_count": 1}]
	_set_detail_page(herb_detail_label, _herb_pages[_herb_page_index])
	_reset_scroll_position(herb_detail_scroll)
	_update_herb_page_controls()


func _update_herb_page_controls() -> void:
	_update_page_controls(herb_prev_page_button, herb_page_indicator, herb_next_page_button, _herb_page_index, _herb_page_count)


func _on_herb_prev_page_pressed() -> void:
	if _herb_page_index <= 0:
		return

	_herb_page_index -= 1
	_refresh_herb_detail_page()


func _on_herb_next_page_pressed() -> void:
	if _herb_page_index >= _herb_page_count - 1:
		return

	_herb_page_index += 1
	_refresh_herb_detail_page()


# =========================================================
# 十五、翻页通用函数
# =========================================================

func _calculate_page_count(value: String, chars_per_page: int) -> int:
	var safe_chars_per_page: int = max(1, chars_per_page)
	var char_count: int = value.length()

	if char_count <= 0:
		return 1

	return int(ceil(float(char_count) / float(safe_chars_per_page)))


func _get_page_text(value: String, page_index: int, chars_per_page: int) -> String:
	var safe_chars_per_page: int = max(1, chars_per_page)
	var start_index: int = page_index * safe_chars_per_page

	return value.substr(start_index, safe_chars_per_page)


func _reset_scroll_position(scroll: ScrollContainer) -> void:
	if scroll == null:
		return

	# 竖排古书正文起点在最右侧。
	# 用 set_deferred 设置属性，比 call_deferred 调不存在的 setter 方法更稳。
	scroll.set_deferred("scroll_horizontal", 100000000)
	scroll.set_deferred("scroll_vertical", 0)


func _update_page_controls(prev_button: Button, indicator: Label, next_button: Button, page_index: int, page_count: int) -> void:
	if prev_button == null or indicator == null or next_button == null:
		return

	prev_button.disabled = page_index <= 0
	next_button.disabled = page_index >= page_count - 1
	indicator.text = "%d / %d" % [page_index + 1, page_count]


# =========================================================
# 十六、空状态显示
# =========================================================

func _clear_disease_detail() -> void:
	_current_disease_detail_text = "请选择左侧疾病条目"
	_disease_page_index = 0
	_disease_page_count = 1
	_disease_pages = _build_detail_pages(disease_detail_label, _current_disease_detail_text, disease_columns_per_page)
	_set_detail_page(disease_detail_label, _disease_pages[0])
	_update_disease_page_controls()


func _clear_formula_detail() -> void:
	_current_formula_detail_text = "请选择左侧方剂条目"
	_formula_page_index = 0
	_formula_page_count = 1
	_formula_pages = _build_detail_pages(formula_detail_label, _current_formula_detail_text, formula_columns_per_page)
	_set_detail_page(formula_detail_label, _formula_pages[0])
	_update_formula_page_controls()


func _clear_herb_detail() -> void:
	_current_herb_detail_text = "请选择左侧药材条目"
	_herb_page_index = 0
	_herb_page_count = 1
	_herb_pages = _build_detail_pages(herb_detail_label, _current_herb_detail_text, herb_columns_per_page)
	_set_detail_page(herb_detail_label, _herb_pages[0])
	_update_herb_page_controls()


# =========================================================
# 十七、信号回调
# =========================================================

func _on_search_bar_gui_input(event: InputEvent, search_bar: LineEdit) -> void:
	# 只处理键盘事件。
	if not (event is InputEventKey):
		return

	# 只处理按下瞬间。
	if not event.pressed:
		return

	# 只处理 Esc。
	if event.keycode != KEY_ESCAPE:
		return

	# 搜索栏为空时不处理。
	if search_bar.text == "":
		return

	# 清空搜索栏，会自动触发 text_changed。
	search_bar.clear()

	# 清空后继续保持焦点，方便马上输入新搜索词。
	search_bar.grab_focus()

	# 阻止 Esc 继续传递。
	get_viewport().set_input_as_handled()


# 窗口显示时，按 Esc 关闭窗口。

# =========================================================
# Clinic 主界面窗口快捷键转发
# =========================================================
const CLINIC_SHORTCUT_OPEN_PULSE := KEY_F1
const CLINIC_SHORTCUT_OPEN_PRESCRIPTION := KEY_F2
const CLINIC_SHORTCUT_OPEN_CLINICAL_LOG := KEY_F3


func _input(event: InputEvent) -> void:
	if _try_handle_clinic_window_shortcut(event):
		return


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
	if not visible:
		return

	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode != KEY_ESCAPE:
		return

	close_window()
	get_viewport().set_input_as_handled()


func _on_close_requested() -> void:
	close_window()


func _on_tab_changed(tab_index: int) -> void:
	# 等当前 Tab 真正显示出来。
	# 隐藏页签第一次显示时，ScrollContainer / RichTextLabel 的尺寸可能还没稳定。
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	# 不复用隐藏状态下生成的页面，直接重新显示当前选中的条目。
	# 这样会重新调用 build_source_text_pages，并拿到当前 Tab 的真实尺寸。
	match tab_index:
		0:
			_refresh_current_disease_detail_after_tab_visible()
		1:
			_refresh_current_formula_detail_after_tab_visible()
		2:
			_refresh_current_herb_detail_after_tab_visible()


func _refresh_current_disease_detail_after_tab_visible() -> void:
	# 如果列表有选中项，重新显示当前选中的条目。
	# 如果没有选中项但列表有内容，就选中第一个。
	var selected_items := disease_list.get_selected_items()

	if selected_items.size() > 0:
		_show_disease_detail(selected_items[0])
		return

	if not visible_disease_entries.is_empty():
		disease_list.select(0)
		_show_disease_detail(0)
		return

	_clear_disease_detail()


func _refresh_current_formula_detail_after_tab_visible() -> void:
	# 方剂 Tab 第一次打开时，原来隐藏状态下算出的分页可能是空的。
	# 这里重新显示当前条目，强制用可见后的尺寸重新分页。
	var selected_items := formula_list.get_selected_items()

	if selected_items.size() > 0:
		_show_formula_detail(selected_items[0])
		return

	if not visible_formula_entries.is_empty():
		formula_list.select(0)
		_show_formula_detail(0)
		return

	_clear_formula_detail()


func _refresh_current_herb_detail_after_tab_visible() -> void:
	# 药材 Tab 第一次打开时同理，重新显示当前条目。
	var selected_items := herb_list.get_selected_items()

	if selected_items.size() > 0:
		_show_herb_detail(selected_items[0])
		return

	if not visible_herb_entries.is_empty():
		herb_list.select(0)
		_show_herb_detail(0)
		return

	_clear_herb_detail()


func _on_disease_search_changed(_new_text: String) -> void:
	_refresh_disease_page()


func _on_formula_search_changed(_new_text: String) -> void:
	_refresh_formula_page()


func _on_herb_search_changed(_new_text: String) -> void:
	_refresh_herb_page()


func _on_disease_list_item_selected(index: int) -> void:
	_show_disease_detail(index)


func _on_formula_list_item_selected(index: int) -> void:
	_show_formula_detail(index)


func _on_herb_list_item_selected(index: int) -> void:
	_show_herb_detail(index)
