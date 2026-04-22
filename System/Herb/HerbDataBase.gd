extends Node
class_name HerbDataBase

# =========================================================
# HerbDataBase.gd
# 负责：
# 1. 加载所有药材资源
# 2. 按 id 查找药材
# 3. 按名字查找药材
# 4. 返回全部药材列表
# =========================================================

const HERB_DATA_PATH := "res://Data/Herb"

# 药材列表
var herb_list: Array[HerbData] = []

# herb_id -> HerbData
var herb_id_map: Dictionary = {}

# herb_name -> HerbData
var herb_name_map: Dictionary = {}


func _ready() -> void:
	load_all_herbs()


# =========================================================
# 加载全部药材
# =========================================================
func load_all_herbs() -> void:
	herb_list.clear()
	herb_id_map.clear()
	herb_name_map.clear()

	var dir := DirAccess.open(HERB_DATA_PATH)

	if dir == null:
		print("Herb/data 文件夹不存在")
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var path := HERB_DATA_PATH + "/" + file_name
			var herb_res = load(path)

			if herb_res is HerbData:
				register_herb(herb_res)

		file_name = dir.get_next()

	dir.list_dir_end()

	print("HerbDataBase 已加载药材数量：", herb_list.size())


# =========================================================
# 注册单个药材
# =========================================================
func register_herb(herb: HerbData) -> void:
	if herb == null:
		return

	if not herb.is_valid_data():
		print("发现无效药材数据，跳过：", herb)
		return

	herb_list.append(herb)

	# 按 id 建索引
	if herb.herb_id != "":
		herb_id_map[herb.herb_id] = herb

	# 按名字建索引
	if herb.herb_name != "":
		herb_name_map[herb.herb_name] = herb


# =========================================================
# 按 id 获取药材
# =========================================================
func get_herb_by_id(herb_id: String) -> HerbData:
	if herb_id_map.has(herb_id):
		return herb_id_map[herb_id]
	return null


# =========================================================
# 按名字获取药材
# =========================================================
func get_herb_by_name(herb_name: String) -> HerbData:
	if herb_name_map.has(herb_name):
		return herb_name_map[herb_name]
	return null


# =========================================================
# 获取全部药材
# =========================================================
func get_all_herbs() -> Array[HerbData]:
	return herb_list


# =========================================================
# 是否存在某个药材 id
# =========================================================
func has_herb_id(herb_id: String) -> bool:
	return herb_id_map.has(herb_id)


# =========================================================
# 是否存在某个药材名
# =========================================================
func has_herb_name(herb_name: String) -> bool:
	return herb_name_map.has(herb_name)
