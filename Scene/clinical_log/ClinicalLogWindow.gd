extends Window
class_name ClinicalLogWindow

# =========================================================
# ClinicalLogWindow.gd
# 行医记考窗口
#
# 作用：
# 1. 在 Clinic 场景中作为子窗口使用
# 2. 白天显示已经同步到 clinical_log 的疾病 / 方剂 / 药材条目
# 3. 支持搜索、列表选择、详情显示
#
# 注意：
# - 数据表里的 detail_text 已经包含疾病名 / 方剂名 / 药材名
# - 所以本脚本不再额外拼接 entry.title，避免标题重复显示
# =========================================================


# =========================================================
# 一、节点引用
# =========================================================

@onready var tab_container: TabContainer = $Panel/MarginContainer/VBoxContainer/TabContainer

# 疾病页
@onready var disease_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Left/SearchBar
@onready var disease_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Left/DiseaseList
@onready var disease_detail_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Right/DiseaseDetailScroll/DiseaseDetail

# 方剂页
@onready var formula_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Left/SearchBar
@onready var formula_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Left/FormulaList
@onready var formula_detail_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Right/FormulaDetailScroll/FormulaDetail

# 药材页
@onready var herb_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Left/SearchBar
@onready var herb_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Left/HerbList
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
# 三、生命周期
# =========================================================

func _ready() -> void:
	# 窗口默认隐藏
	visible = false

	# 点击窗口关闭按钮时，只隐藏窗口，不销毁节点
	close_requested.connect(_on_close_requested)

	# 设置页签标题
	tab_container.set_tab_title(0, "疾病")
	tab_container.set_tab_title(1, "方剂")
	tab_container.set_tab_title(2, "药材")

	# 搜索框文本变化时，刷新对应分页
	disease_search_bar.text_changed.connect(_on_disease_search_changed)
	formula_search_bar.text_changed.connect(_on_formula_search_changed)
	herb_search_bar.text_changed.connect(_on_herb_search_changed)

	# 开启搜索框自带清除按钮
	disease_search_bar.clear_button_enabled = true
	formula_search_bar.clear_button_enabled = true
	herb_search_bar.clear_button_enabled = true

	# 搜索框获得焦点时，按 Esc 清空当前搜索框
	disease_search_bar.gui_input.connect(_on_search_bar_gui_input.bind(disease_search_bar))
	formula_search_bar.gui_input.connect(_on_search_bar_gui_input.bind(formula_search_bar))
	herb_search_bar.gui_input.connect(_on_search_bar_gui_input.bind(herb_search_bar))

	# 列表选择信号
	disease_list.item_selected.connect(_on_disease_list_item_selected)
	formula_list.item_selected.connect(_on_formula_list_item_selected)
	herb_list.item_selected.connect(_on_herb_list_item_selected)

	# 初始化空状态
	_clear_disease_detail()
	_clear_formula_detail()
	_clear_herb_detail()


# =========================================================
# 四、对外接口
# =========================================================

func open_window() -> void:
	refresh_view()
	show()


func close_window() -> void:
	hide()


func refresh_view() -> void:
	_load_all_entries_from_unlock_state()
	_refresh_disease_page()
	_refresh_formula_page()
	_refresh_herb_page()


# =========================================================
# 五、加载数据
# =========================================================

func _load_all_entries_from_unlock_state() -> void:
	all_disease_entries.clear()
	all_formula_entries.clear()
	all_herb_entries.clear()

	var disease_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("disease")
	var formula_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("formula")
	var herb_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("herb")

	# 疾病：只显示已经同步到 clinical_log 的疾病
	for entry in disease_entries:
		if entry == null:
			continue

		if not (entry is DiseaseBookEntryData):
			continue

		var disease_entry := entry as DiseaseBookEntryData

		if Unlock.is_disease_unlocked_in_clinical_log(disease_entry.disease_id):
			all_disease_entries.append(disease_entry)

	# 方剂：只显示已经同步到 clinical_log 的方剂
	for entry in formula_entries:
		if entry == null:
			continue

		if not (entry is FormulaBookEntryData):
			continue

		var formula_entry := entry as FormulaBookEntryData

		if Unlock.is_formula_unlocked_in_clinical_log(formula_entry.formula_id):
			all_formula_entries.append(formula_entry)

	# 药材：只显示已经同步到 clinical_log 的药材
	for entry in herb_entries:
		if entry == null:
			continue

		if not (entry is HerbBookEntryData):
			continue

		var herb_entry := entry as HerbBookEntryData

		if Unlock.is_herb_unlocked_in_clinical_log(herb_entry.herb_id):
			all_herb_entries.append(herb_entry)

	# 按标题排序，方便查找
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
# 六、分页刷新
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
# 七、搜索过滤
# =========================================================

func _filter_entries_by_keyword(source_entries: Array[BookEntryData], keyword: String) -> Array[BookEntryData]:
	var result: Array[BookEntryData] = []
	var clean_keyword := keyword.strip_edges().to_lower()

	# 搜索为空时，显示全部条目
	if clean_keyword == "":
		for entry in source_entries:
			result.append(entry)

		return result

	# 按标题和正文搜索
	for entry in source_entries:
		if entry == null:
			continue

		var title_text := entry.title.to_lower()
		var detail_text := entry.detail_text.to_lower()

		if title_text.contains(clean_keyword) or detail_text.contains(clean_keyword):
			result.append(entry)

	return result


# =========================================================
# 八、列表重建
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
# 九、详情显示
# =========================================================

func _show_disease_detail(index: int) -> void:
	if index < 0 or index >= visible_disease_entries.size():
		_clear_disease_detail()
		return

	var entry := visible_disease_entries[index]

	if entry == null:
		_clear_disease_detail()
		return

	# detail_text 中已经包含疾病名，所以不再额外拼接 entry.title
	_set_detail_text(
		disease_detail_label,
		_build_entry_detail_text(entry)
	)


func _show_formula_detail(index: int) -> void:
	if index < 0 or index >= visible_formula_entries.size():
		_clear_formula_detail()
		return

	var entry := visible_formula_entries[index]

	if entry == null:
		_clear_formula_detail()
		return

	# detail_text 中已经包含方剂名，所以不再额外拼接 entry.title
	_set_detail_text(
		formula_detail_label,
		_build_entry_detail_text(entry)
	)


func _show_herb_detail(index: int) -> void:
	if index < 0 or index >= visible_herb_entries.size():
		_clear_herb_detail()
		return

	var entry := visible_herb_entries[index]

	if entry == null:
		_clear_herb_detail()
		return

	# detail_text 中已经包含药材名，所以不再额外拼接 entry.title
	_set_detail_text(
		herb_detail_label,
		_build_entry_detail_text(entry)
	)


# 构建详情文本。
# 只返回数据表里的正文，不额外添加标题。
func _build_entry_detail_text(entry: BookEntryData) -> String:
	if entry == null:
		return ""

	return entry.detail_text


# 设置详情文本。
# 如果详情节点挂了 ClassicalVerticalRichTextLabel，
# 就调用 set_source_text 生成竖排古书文本。
# 如果没有挂脚本，则退回普通 RichTextLabel 显示。
func _set_detail_text(label: RichTextLabel, value: String) -> void:
	if label == null:
		return

	if label.has_method("set_source_text"):
		label.call("set_source_text", value)
		return

	label.text = value


# =========================================================
# 十、空状态显示
# =========================================================

func _clear_disease_detail() -> void:
	_set_detail_text(disease_detail_label, "请选择左侧疾病条目")


func _clear_formula_detail() -> void:
	_set_detail_text(formula_detail_label, "请选择左侧方剂条目")


func _clear_herb_detail() -> void:
	_set_detail_text(herb_detail_label, "请选择左侧药材条目")


# =========================================================
# 十一、信号回调
# =========================================================

func _on_search_bar_gui_input(event: InputEvent, search_bar: LineEdit) -> void:
	# 只处理键盘事件
	if not (event is InputEventKey):
		return

	# 只处理按下瞬间
	if not event.pressed:
		return

	# 只处理 Esc
	if event.keycode != KEY_ESCAPE:
		return

	# 搜索栏为空时不处理
	if search_bar.text == "":
		return

	# 清空搜索栏，会自动触发 text_changed
	search_bar.clear()

	# 清空后继续保持焦点，方便马上输入新搜索词
	search_bar.grab_focus()

	# 阻止 Esc 继续传递
	get_viewport().set_input_as_handled()


# 窗口显示时，按 Esc 关闭窗口
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
