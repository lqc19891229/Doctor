## =========================================================
## DiseaseDataBase.gd
##
## 作用：
## 1. 自动加载指定文件夹下的所有 DiseaseData 资源
## 2. 用 disease_id 作为 key 存进字典
## 3. 提供获取单个疾病 / 获取全部疾病的方法
##
## 前提：
## - 你的疾病资源文件都是 .tres
## - 每个资源都挂的是 DiseaseData.gd
## - 每个资源都正确填写了 disease_id
##
## 建议目录：
## res://data/disease/
## =========================================================

class_name DiseaseDataBase
extends Node


## =========================================================
## 一、配置
## =========================================================

## 疾病资源所在目录
@export var disease_data_path: String = "res://Data/Disease"


## =========================================================
## 二、运行时数据
## =========================================================

## key = disease_id
## value = DiseaseData
var disease_map: Dictionary = {}


## =========================================================
## 三、初始化
## =========================================================

func _ready() -> void:
	load_all_diseases()


## =========================================================
## 四、加载全部疾病
## =========================================================

func load_all_diseases() -> void:
	## 每次重载前先清空，避免重复
	disease_map.clear()

	## 打开目录
	var dir := DirAccess.open(disease_data_path)
	if dir == null:
		push_error("DiseaseDataBase: 无法打开路径 -> " + disease_data_path)
		return

	## 开始遍历目录
	dir.list_dir_begin()

	var file_name: String = dir.get_next()

	while file_name != "":
		## 跳过文件夹
		if dir.current_is_dir():
			file_name = dir.get_next()
			continue

		## 只加载 .tres / .res 文件
		if file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var full_path := disease_data_path.path_join(file_name)
			_load_single_disease(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()

	print("DiseaseDataBase 加载完成，疾病数量：", disease_map.size())


## =========================================================
## 五、加载单个疾病资源
## =========================================================

func _load_single_disease(resource_path: String) -> void:
	var data = load(resource_path)

	## 判空
	if data == null:
		push_warning("DiseaseDataBase: 加载失败 -> " + resource_path)
		return

	## 类型检查
	if not data is DiseaseData:
		push_warning("DiseaseDataBase: 资源不是 DiseaseData -> " + resource_path)
		return

	var disease_data: DiseaseData = data

	## disease_id 必须存在
	if disease_data.disease_id.strip_edges() == "":
		push_warning("DiseaseDataBase: disease_id 为空 -> " + resource_path)
		return

	## 防止重复ID覆盖
	if disease_map.has(disease_data.disease_id):
		push_warning("DiseaseDataBase: 发现重复 disease_id -> " + disease_data.disease_id)

	disease_map[disease_data.disease_id] = disease_data


## =========================================================
## 六、查询接口
## =========================================================

## 根据 disease_id 获取单个疾病
func get_disease(disease_id: String) -> DiseaseData:
	if not disease_map.has(disease_id):
		push_warning("DiseaseDataBase: 找不到疾病 -> " + disease_id)
		return null

	return disease_map[disease_id]


## 根据 disease_id 获取单个疾病（兼容接口）
## 给 DiseaseBookEntryData.gd 使用
func get_disease_by_id(disease_id: String) -> DiseaseData:
	return get_disease(disease_id)


## 判断某个疾病是否存在
func has_disease(disease_id: String) -> bool:
	return disease_map.has(disease_id)


## 获取全部疾病ID
func get_all_disease_ids() -> Array[String]:
	var result: Array[String] = []

	for key in disease_map.keys():
		result.append(key)

	return result


## 获取全部疾病数据
func get_all_diseases() -> Array[DiseaseData]:
	var result: Array[DiseaseData] = []

	for data in disease_map.values():
		result.append(data)

	return result


## 返回当前疾病总数
func get_disease_count() -> int:
	return disease_map.size()


## =========================================================
## 七、调试
## =========================================================

func debug_print_all_diseases() -> void:
	print("===== DiseaseDataBase 疾病列表 =====")

	for disease_id in disease_map.keys():
		var data: DiseaseData = disease_map[disease_id]
		print(
			"ID: ", data.disease_id,
			" | 名称: ", data.disease_name,
			" | 方剂: ", data.recommended_formula_id
		)

	print("总数: ", disease_map.size())
