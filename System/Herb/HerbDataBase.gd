extends Node
class_name HerbDataBase

# =========================================================
# 脚本功能：
# 药材数据库管理器。
# 负责从指定目录加载所有 HerbData 药材资源，并建立 id / 名称索引，
# 方便其他系统按药材 id、药材名称或完整列表快速查询药材数据。
#
# 使用方式：
# 1. 将本脚本挂载到场景中的数据库节点，或作为自动加载单例使用。
# 2. 启动时会在 _ready() 中自动加载 HERB_DATA_PATH 目录下的药材资源。
# 3. 其他脚本可通过 get_herb_by_id()、get_herb_by_name() 等函数查询数据。
# =========================================================

# 药材资源所在目录。
# 该目录下的 .tres / .res 文件会被尝试加载为 HerbData。
const HERB_DATA_PATH := "res://Data/Herb"

# 允许加载的 Godot 资源文件扩展名。
const HERB_RESOURCE_EXTENSIONS := [".tres", ".res"]

# 已加载的全部药材数据列表。
# 注意：该数组保存的是 HerbData 资源引用，不是深拷贝。
var herb_list: Array[HerbData] = []

# 药材 id 索引表。
# key: herb_id
# value: HerbData
var herb_id_map: Dictionary = {}

# 药材名称索引表。
# key: herb_name
# value: HerbData
var herb_name_map: Dictionary = {}


# =========================================================
# 生命周期函数
# =========================================================

# 函数功能：
# 节点进入场景树后自动加载全部药材数据。
func _ready() -> void:
	load_all_herbs()


# =========================================================
# 数据加载
# =========================================================

# 函数功能：
# 清空旧缓存，并重新加载 HERB_DATA_PATH 目录下的全部药材资源。
func load_all_herbs() -> void:
	_clear_cache()

	var dir := DirAccess.open(HERB_DATA_PATH)
	if dir == null:
		push_warning("药材数据目录不存在：%s" % HERB_DATA_PATH)
		return

	var file_names := _get_herb_resource_file_names(dir)
	for file_name in file_names:
		_load_and_register_herb_file(file_name)

	print("HerbDataBase 已加载药材数量：", herb_list.size())


# 函数功能：
# 清空药材列表和索引缓存，避免重复加载时留下旧数据。
func _clear_cache() -> void:
	herb_list.clear()
	herb_id_map.clear()
	herb_name_map.clear()


# 函数功能：
# 从目录中筛选出可加载的药材资源文件名，并排序保证加载顺序稳定。
func _get_herb_resource_file_names(dir: DirAccess) -> Array[String]:
	var file_names: Array[String] = []

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and _is_herb_resource_file(file_name):
			file_names.append(file_name)

		file_name = dir.get_next()

	dir.list_dir_end()
	file_names.sort()

	return file_names


# 函数功能：
# 判断文件名是否为药材资源文件。
func _is_herb_resource_file(file_name: String) -> bool:
	for extension in HERB_RESOURCE_EXTENSIONS:
		if file_name.ends_with(extension):
			return true

	return false


# 函数功能：
# 根据文件名加载单个资源，并在资源类型正确时注册为药材数据。
func _load_and_register_herb_file(file_name: String) -> void:
	var path := HERB_DATA_PATH.path_join(file_name)
	var herb_res := load(path)

	if herb_res is HerbData:
		register_herb(herb_res)
	else:
		push_warning("资源不是 HerbData，已跳过：%s" % path)


# =========================================================
# 数据注册
# =========================================================

# 函数功能：
# 注册单个药材数据，并建立 id 和名称索引。
func register_herb(herb: HerbData) -> void:
	if herb == null:
		return

	if not herb.is_valid_data():
		push_warning("发现无效药材数据，已跳过：%s" % str(herb))
		return

	if _is_duplicate_herb(herb):
		return

	herb_list.append(herb)
	_register_herb_id(herb)
	_register_herb_name(herb)


# 函数功能：
# 检查药材 id 或药材名称是否重复。
# 返回 true 表示发现重复并跳过注册。
func _is_duplicate_herb(herb: HerbData) -> bool:
	if herb.herb_id != "" and herb_id_map.has(herb.herb_id):
		push_warning("药材 id 重复，已跳过：%s" % herb.herb_id)
		return true

	if herb.herb_name != "" and herb_name_map.has(herb.herb_name):
		push_warning("药材名称重复，已跳过：%s" % herb.herb_name)
		return true

	return false


# 函数功能：
# 将药材注册到 id 索引表。
func _register_herb_id(herb: HerbData) -> void:
	if herb.herb_id == "":
		return

	herb_id_map[herb.herb_id] = herb


# 函数功能：
# 将药材注册到名称索引表。
func _register_herb_name(herb: HerbData) -> void:
	if herb.herb_name == "":
		return

	herb_name_map[herb.herb_name] = herb


# =========================================================
# 药材查询
# =========================================================

# 函数功能：
# 根据药材 id 获取对应药材数据。
# 未找到时返回 null。
func get_herb_by_id(herb_id: String) -> HerbData:
	return herb_id_map.get(herb_id, null)


# 函数功能：
# 根据药材名称获取对应药材数据。
# 未找到时返回 null。
func get_herb_by_name(herb_name: String) -> HerbData:
	return herb_name_map.get(herb_name, null)


# 函数功能：
# 获取全部药材数据列表。
# 注意：为了兼容旧代码，这里返回内部数组本身；外部不要直接修改该数组。
func get_all_herbs() -> Array[HerbData]:
	return herb_list


# 函数功能：
# 获取全部药材数据列表的浅拷贝。
# 适合只读遍历，避免外部误删或重排数据库内部数组。
func get_all_herbs_copy() -> Array[HerbData]:
	return herb_list.duplicate()


# =========================================================
# 存在性判断
# =========================================================

# 函数功能：
# 判断数据库中是否存在指定药材 id。
func has_herb_id(herb_id: String) -> bool:
	return herb_id_map.has(herb_id)


# 函数功能：
# 判断数据库中是否存在指定药材名称。
func has_herb_name(herb_name: String) -> bool:
	return herb_name_map.has(herb_name)


# 函数功能：
# 判断指定药材资源是否已经被注册。
func has_herb(herb: HerbData) -> bool:
	return herb != null and herb_list.has(herb)
