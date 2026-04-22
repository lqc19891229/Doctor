extends Node
class_name BookEntryDataBase

# =========================================================
# BookEntryDataBase.gd
# 医书条目数据库
#
# 作用：
# 1. 递归加载指定目录下的所有 BookEntryData 资源
# 2. 用 entry_id 作为 key 建立索引
# 3. 按 book_id / entry_type 分类存储
# 4. 提供查询接口给 NightStudy / UnlockManager 使用
# =========================================================


# =========================================================
# 一、配置
# =========================================================

# 条目资源根目录
@export var entry_data_path: String = "res://Data/Book/BookEntry/"


# =========================================================
# 二、运行时数据
# =========================================================

# key = entry_id
# value = BookEntryData
var entry_map: Dictionary = {}

# key = book_id
# value = Array[BookEntryData]
var entries_by_book: Dictionary = {}

# key = entry_type（herb / disease / formula）
# value = Array[BookEntryData]
var entries_by_type: Dictionary = {}


# =========================================================
# 三、生命周期
# =========================================================

func _ready() -> void:
	load_all_entries()


# =========================================================
# 四、加载入口
# =========================================================

func load_all_entries() -> void:
	# 每次重新加载前先清空
	entry_map.clear()
	entries_by_book.clear()
	entries_by_type.clear()

	# 递归扫描目录
	_load_entries_recursive(entry_data_path)

	print("[BookEntryDataBase] 已加载条目数量：", entry_map.size())


# =========================================================
# 五、递归加载
# =========================================================

func _load_entries_recursive(folder_path: String) -> void:
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_error("[BookEntryDataBase] 无法打开目录：%s" % folder_path)
		return

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break

		# 跳过 . 和 ..
		if file_name == "." or file_name == "..":
			continue

		var full_path := folder_path.path_join(file_name)

		if dir.current_is_dir():
			# 递归读取子文件夹
			_load_entries_recursive(full_path)
		else:
			# 只处理 .tres / .res
			if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
				continue

			var res := load(full_path)

			# 必须是 BookEntryData 或其子类
			if res == null:
				push_warning("[BookEntryDataBase] 资源加载失败：%s" % full_path)
				continue

			if not (res is BookEntryData):
				push_warning("[BookEntryDataBase] 资源不是 BookEntryData：%s" % full_path)
				continue

			var entry: BookEntryData = res
			_register_entry(entry, full_path)

	dir.list_dir_end()


# =========================================================
# 六、注册条目
# =========================================================

func _register_entry(entry: BookEntryData, full_path: String) -> void:
	if entry == null:
		return

	if not entry.is_valid_data():
		push_warning("[BookEntryDataBase] 条目数据不合法：%s" % full_path)
		return

	var clean_entry_id := entry.entry_id.strip_edges()
	var clean_book_id := entry.book_id.strip_edges()
	var clean_type := entry.get_entry_type().strip_edges()

	# 防止重复ID
	if entry_map.has(clean_entry_id):
		push_warning("[BookEntryDataBase] 重复的 entry_id：%s，路径：%s" % [clean_entry_id, full_path])
		return

	# 注册到总表
	entry_map[clean_entry_id] = entry

	# 按书分类
	if not entries_by_book.has(clean_book_id):
		entries_by_book[clean_book_id] = []
	entries_by_book[clean_book_id].append(entry)

	# 按类型分类
	if not entries_by_type.has(clean_type):
		entries_by_type[clean_type] = []
	entries_by_type[clean_type].append(entry)


# =========================================================
# 七、查询接口
# =========================================================

func get_entry(entry_id: String) -> BookEntryData:
	var clean_id := entry_id.strip_edges()
	if clean_id == "":
		return null

	return entry_map.get(clean_id, null)


func has_entry(entry_id: String) -> bool:
	var clean_id := entry_id.strip_edges()
	if clean_id == "":
		return false

	return entry_map.has(clean_id)


func get_all_entries() -> Array[BookEntryData]:
	var result: Array[BookEntryData] = []

	for entry in entry_map.values():
		result.append(entry)

	return result


func get_entries_by_book(book_id: String) -> Array[BookEntryData]:
	var clean_book_id := book_id.strip_edges()
	if clean_book_id == "":
		return []

	if not entries_by_book.has(clean_book_id):
		return []

	var result: Array[BookEntryData] = []
	for entry in entries_by_book[clean_book_id]:
		result.append(entry)

	return result


func get_entries_by_type(entry_type: String) -> Array[BookEntryData]:
	var clean_type := entry_type.strip_edges()
	if clean_type == "":
		return []

	if not entries_by_type.has(clean_type):
		return []

	var result: Array[BookEntryData] = []
	for entry in entries_by_type[clean_type]:
		result.append(entry)

	return result
