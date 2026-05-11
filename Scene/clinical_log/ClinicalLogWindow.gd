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
# 当前分页顺序：
# - 第 1 页：疾病
# - 第 2 页：方剂
# - 第 3 页：药材
# =========================================================


# =========================================================
# 一、节点引用
# =========================================================

@onready var tab_container: TabContainer = $Panel/MarginContainer/VBoxContainer/TabContainer

# 疾病页
@onready var disease_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Left/SearchBar
@onready var disease_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Left/DiseaseList
@onready var disease_name_label: Label = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Right/DiseaseName
@onready var disease_detail_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/TabContainer/DiseasePage/Right/DiseaseDetail

# 方剂页
@onready var formula_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Left/SearchBar
@onready var formula_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Left/FormulaList
@onready var formula_name_label: Label = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Right/FormulaName
@onready var formula_detail_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/TabContainer/FormulaPage/Right/FormulaDetail

# 药材页
@onready var herb_search_bar: LineEdit = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Left/SearchBar
@onready var herb_list: ItemList = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Left/HerbList
@onready var herb_name_label: Label = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Right/HerbName
@onready var herb_detail_label: RichTextLabel = $Panel/MarginContainer/VBoxContainer/TabContainer/HerbPage/Right/HerbDetail


# =========================================================
# 二、运行时缓存
# 说明：
# - all_xxx_entries: 当前分页的全部可显示条目
# - visible_xxx_entries: 当前搜索条件下，列表中实际显示的条目
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
	# -------------------------
	# 窗口基础设置
	# -------------------------
	# 作为嵌入 Clinic 的窗口，默认先隐藏
	visible = false

	# 关闭按钮使用 Window 自带 close_requested 信号
	close_requested.connect(_on_close_requested)

	# -------------------------
	# 页签标题
	# -------------------------
	tab_container.set_tab_title(0, "疾病")
	tab_container.set_tab_title(1, "方剂")
	tab_container.set_tab_title(2, "药材")

	# -------------------------
	# 搜索框信号
	# -------------------------
	disease_search_bar.text_changed.connect(_on_disease_search_changed)
	formula_search_bar.text_changed.connect(_on_formula_search_changed)
	herb_search_bar.text_changed.connect(_on_herb_search_changed)

	# -------------------------
	# 列表选择信号
	# -------------------------
	disease_list.item_selected.connect(_on_disease_list_item_selected)
	formula_list.item_selected.connect(_on_formula_list_item_selected)
	herb_list.item_selected.connect(_on_herb_list_item_selected)

	# -------------------------
	# 初始化空状态文案
	# -------------------------
	_clear_disease_detail()
	_clear_formula_detail()
	_clear_herb_detail()


# =========================================================
# 四、对外接口
# =========================================================

# 打开窗口
# 每次打开前重新刷新内容

func open_window() -> void:
	refresh_view()
	show()

# 关闭窗口
func close_window() -> void:
	hide()


# 刷新全部分页
func refresh_view() -> void:
	_load_all_entries_from_unlock_state()
	_refresh_disease_page()
	_refresh_formula_page()
	_refresh_herb_page()


# =========================================================
# 五、加载数据
# =========================================================

# 从 Unlock + BookEntryDB 中构建行医记考可见条目
func _load_all_entries_from_unlock_state() -> void:
	all_disease_entries.clear()
	all_formula_entries.clear()
	all_herb_entries.clear()

	# --------------------------------------------------
	# 先拿到所有对应类型的条目
	# --------------------------------------------------
	var disease_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("disease")
	var formula_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("formula")
	var herb_entries: Array[BookEntryData] = BookEntryDB.get_entries_by_type("herb")

	# --------------------------------------------------
	# 疾病：只显示已经同步到 clinical_log 的 disease_id
	# --------------------------------------------------
	for entry in disease_entries:
		if entry == null:
			continue

		if not (entry is DiseaseBookEntryData):
			continue

		var disease_entry := entry as DiseaseBookEntryData
		if Unlock.is_disease_unlocked_in_clinical_log(disease_entry.disease_id):
			all_disease_entries.append(disease_entry)

	# --------------------------------------------------
	# 方剂：只显示已经同步到 clinical_log 的 formula_id
	# --------------------------------------------------
	for entry in formula_entries:
		if entry == null:
			continue

		if not (entry is FormulaBookEntryData):
			continue

		var formula_entry := entry as FormulaBookEntryData
		if Unlock.is_formula_unlocked_in_clinical_log(formula_entry.formula_id):
			all_formula_entries.append(formula_entry)

	# --------------------------------------------------
	# 药材：只显示已经同步到 clinical_log 的 herb_id
	# --------------------------------------------------
	for entry in herb_entries:
		if entry == null:
			continue

		if not (entry is HerbBookEntryData):
			continue

		var herb_entry := entry as HerbBookEntryData
		if Unlock.is_herb_unlocked_in_clinical_log(herb_entry.herb_id):
			all_herb_entries.append(herb_entry)

	# --------------------------------------------------
	# 统一排序：按标题排序，便于查找
	# --------------------------------------------------
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

	# 没输入搜索词时直接返回全部
	if clean_keyword == "":
		for entry in source_entries:
			result.append(entry)
		return result

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

	disease_name_label.text = entry.title
	disease_detail_label.text = _build_entry_detail_text(entry)


func _show_formula_detail(index: int) -> void:
	if index < 0 or index >= visible_formula_entries.size():
		_clear_formula_detail()
		return

	var entry := visible_formula_entries[index]
	if entry == null:
		_clear_formula_detail()
		return

	formula_name_label.text = entry.title
	formula_detail_label.text = _build_entry_detail_text(entry)


func _show_herb_detail(index: int) -> void:
	if index < 0 or index >= visible_herb_entries.size():
		_clear_herb_detail()
		return

	var entry := visible_herb_entries[index]
	if entry == null:
		_clear_herb_detail()
		return

	herb_name_label.text = entry.title
	herb_detail_label.text = _build_entry_detail_text(entry)


func _build_entry_detail_text(entry: BookEntryData) -> String:
	if entry == null:
		return ""
		
	return entry.detail_text

# =========================================================
# 十、空状态显示
# =========================================================

func _clear_disease_detail() -> void:
	disease_name_label.text = "疾病名称"
	disease_detail_label.text = "请选择左侧疾病条目"


func _clear_formula_detail() -> void:
	formula_name_label.text = "方剂名称"
	formula_detail_label.text = "请选择左侧方剂条目"


func _clear_herb_detail() -> void:
	herb_name_label.text = "药材名称"
	herb_detail_label.text = "请选择左侧药材条目"


# =========================================================
# 十一、信号回调
# =========================================================

func _on_close_requested() -> void:
	# 作为嵌入式窗口时，关闭只隐藏，不销毁
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
