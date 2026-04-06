extends Node
class_name DiseaseBookDataBase

# =========================================================
# DiseaseBookDataBase.gd
#
# 作用：
# 1. 自动加载指定目录下的所有 DiseaseBookEntryData 资源
# 2. 用 entry_id 建立索引
# 3. 提供按 book_id / disease_id 查询接口
# =========================================================


# =========================================================
# 一、配置
# =========================================================

# 病证书条目资源所在目录
@export var disease_book_entry_path: String = "res://Data/BookEntry"


# =========================================================
# 二、运行时数据
# =========================================================

# 全部条目
var entries: Array[DiseaseBookEntryData] = []

# entry_id -> DiseaseBookEntryData
var entry_map: Dictionary = {}

# book_id -> Array[DiseaseBookEntryData]
var entries_by_book: Dictionary = {}

# disease_id -> Array[DiseaseBookEntryData]
var entries_by_disease: Dictionary = {}


# =========================================================
# 三、生命周期
# =========================================================

func _ready() -> void:
	reload_database()


# =========================================================
# 四、加载
# =========================================================

# 重新加载数据库
func reload_database() -> void:
	entries.clear()
	entry_map.clear()
	entries_by_book.clear()
	entries_by_disease.clear()

	var dir := DirAccess.open(disease_book_entry_path)
	if dir == null:
		push_warning("DiseaseBookDataBase: 无法打开目录 -> " + disease_book_entry_path)
		return

	_scan_dir_recursive(disease_book_entry_path)


# 递归扫描目录
func _scan_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break

		if file_name.begins_with("."):
			continue

		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			_scan_dir_recursive(full_path)
			continue

		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue

		var res = load(full_path)
		if res == null:
			push_warning("DiseaseBookDataBase: 加载失败 -> " + full_path)
			continue

		if not (res is DiseaseBookEntryData):
			continue

		var entry: DiseaseBookEntryData = res
		_add_entry(entry, full_path)

	dir.list_dir_end()


# 加入数据库
func _add_entry(entry: DiseaseBookEntryData, source_path: String = "") -> void:
	if entry == null:
		return

	if not entry.is_valid_data():
		push_warning("DiseaseBookDataBase: 条目基础数据无效 -> " + source_path)
		return

	var clean_entry_id := entry.entry_id.strip_edges()
	if entry_map.has(clean_entry_id):
		push_warning("DiseaseBookDataBase: 存在重复 entry_id -> " + clean_entry_id + " | " + source_path)
		return

	entries.append(entry)
	entry_map[clean_entry_id] = entry

	var clean_book_id := entry.book_id.strip_edges()
	if not entries_by_book.has(clean_book_id):
		entries_by_book[clean_book_id] = []
	entries_by_book[clean_book_id].append(entry)

	var clean_disease_id := entry.disease_id.strip_edges()
	if not entries_by_disease.has(clean_disease_id):
		entries_by_disease[clean_disease_id] = []
	entries_by_disease[clean_disease_id].append(entry)


# =========================================================
# 五、查询接口
# =========================================================

# 获取全部条目
func get_all_entries() -> Array[DiseaseBookEntryData]:
	return entries.duplicate()


# 通过 entry_id 获取条目
func get_entry_by_id(entry_id: String) -> DiseaseBookEntryData:
	var clean_id := entry_id.strip_edges()
	if clean_id == "":
		return null

	if not entry_map.has(clean_id):
		return null

	return entry_map[clean_id]


# 获取某本书下的全部条目
func get_entries_by_book(book_id: String) -> Array[DiseaseBookEntryData]:
	var clean_id := book_id.strip_edges()
	if clean_id == "":
		return []

	if not entries_by_book.has(clean_id):
		return []

	var result: Array[DiseaseBookEntryData] = []
	for entry in entries_by_book[clean_id]:
		if entry != null:
			result.append(entry)

	return result


# 获取某个 disease_id 对应的全部条目
func get_entries_by_disease(disease_id: String) -> Array[DiseaseBookEntryData]:
	var clean_id := disease_id.strip_edges()
	if clean_id == "":
		return []

	if not entries_by_disease.has(clean_id):
		return []

	var result: Array[DiseaseBookEntryData] = []
	for entry in entries_by_disease[clean_id]:
		if entry != null:
			result.append(entry)

	return result


# 获取某本书下“尚未阅读”的条目
# 这里不直接依赖 UnlockManager，调用者把已读表传进来
func get_unread_entries_by_book(book_id: String, read_entry_ids: Dictionary) -> Array[DiseaseBookEntryData]:
	var result: Array[DiseaseBookEntryData] = []

	for entry in get_entries_by_book(book_id):
		if entry == null:
			continue

		if read_entry_ids.has(entry.entry_id):
			continue

		result.append(entry)

	return result


# =========================================================
# 六、调试接口
# =========================================================

func debug_print_all_entries() -> void:
	print("===== DiseaseBookDataBase 病证书条目列表 =====")
	print("总数：", entries.size())

	for entry in entries:
		if entry == null:
			continue

		print(
			"entry_id=", entry.entry_id,
			" | book_id=", entry.book_id,
			" | disease_id=", entry.disease_id,
			" | disease_name=", entry.get_display_name(),
			" | standard_formula_id=", entry.get_standard_formula_id()
		)

	print("============================================")
