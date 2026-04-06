extends Node
class_name BookDataBase

# =========================================================
# BookDataBase.gd
#
# 作用：
# 1. 自动加载 Books 目录下的所有 BookData 资源
# 2. 按 book_id 建立索引
# 3. 提供按类型获取书籍列表的方法
#
# 建议作为 Autoload 使用，名字：
# BookDB
# =========================================================


# =========================================================
# 一、配置
# =========================================================

# 书本资源目录
@export var book_data_path: String = "res://Data/Book/"


# =========================================================
# 二、运行时数据
# =========================================================

# 全部书本列表
var books: Array[BookData] = []

# key = book_id
# value = BookData
var book_map: Dictionary = {}

# key = book_type
# value = Array[BookData]
var books_by_type: Dictionary = {}


# =========================================================
# 三、初始化
# =========================================================

func _ready() -> void:
	load_all_books()


# =========================================================
# 四、加载全部书本
# =========================================================

func load_all_books() -> void:
	books.clear()
	book_map.clear()
	books_by_type.clear()

	var dir := DirAccess.open(book_data_path)
	if dir == null:
		push_error("BookDataBase: 无法打开路径 -> " + book_data_path)
		return

	dir.list_dir_begin()

	var file_name := dir.get_next()

	while file_name != "":
		# 跳过文件夹
		if dir.current_is_dir():
			file_name = dir.get_next()
			continue

		# 只读取资源文件
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var full_path := book_data_path.path_join(file_name)
			_load_single_book(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()

	_sort_books()

	print("BookDataBase 加载完成，书籍数量：", books.size())


# 加载单个书本资源
func _load_single_book(resource_path: String) -> void:
	var data = load(resource_path)

	if data == null:
		push_warning("BookDataBase: 加载失败 -> " + resource_path)
		return

	if not data is BookData:
		push_warning("BookDataBase: 资源不是 BookData -> " + resource_path)
		return

	var book_data: BookData = data

	if not book_data.is_valid_data():
		push_warning("BookDataBase: 书本数据无效 -> " + resource_path)
		push_warning("错误详情：%s" % str(book_data.validate_data()))
		return

	if book_map.has(book_data.book_id):
		push_warning("BookDataBase: 发现重复 book_id -> " + book_data.book_id)

	books.append(book_data)
	book_map[book_data.book_id] = book_data

	if not books_by_type.has(book_data.book_type):
		books_by_type[book_data.book_type] = []

	(books_by_type[book_data.book_type] as Array).append(book_data)


# 对书本按 sort_index 排序
func _sort_books() -> void:
	books.sort_custom(func(a: BookData, b: BookData) -> bool:
		return a.sort_index < b.sort_index
	)

	for key in books_by_type.keys():
		var arr: Array = books_by_type[key]
		arr.sort_custom(func(a: BookData, b: BookData) -> bool:
			return a.sort_index < b.sort_index
		)


# =========================================================
# 五、查询接口
# =========================================================

# 获取单本书
func get_book(book_id: String) -> BookData:
	book_id = book_id.strip_edges()

	if not book_map.has(book_id):
		push_warning("BookDataBase: 找不到书籍 -> " + book_id)
		return null

	return book_map[book_id]


# 兼容命名
func get_book_by_id(book_id: String) -> BookData:
	return get_book(book_id)


# 判断书是否存在
func has_book(book_id: String) -> bool:
	return book_map.has(book_id.strip_edges())


# 获取全部书
func get_all_books() -> Array[BookData]:
	return books


# 获取指定类型的全部书
func get_books_by_type(book_type: String) -> Array[BookData]:
	var result: Array[BookData] = []

	book_type = book_type.strip_edges()
	if book_type == "":
		return result

	if not books_by_type.has(book_type):
		return result

	for book in books_by_type[book_type]:
		if book != null:
			result.append(book)

	return result


# 获取默认可见的书
func get_visible_books() -> Array[BookData]:
	var result: Array[BookData] = []

	for book in books:
		if book == null:
			continue

		if book.visible_by_default:
			result.append(book)

	return result


# 返回当前书本总数
func get_book_count() -> int:
	return books.size()


# =========================================================
# 六、调试
# =========================================================

func debug_print_all_books() -> void:
	print("===== BookDataBase 书籍列表 =====")

	for book in books:
		if book == null:
			continue

		print(
			"ID: ", book.book_id,
			" | 书名: ", book.book_name,
			" | 类型: ", book.book_type,
			" | 排序: ", book.sort_index
		)

	print("总数: ", books.size())
