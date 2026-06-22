## =========================================================
## DiseaseData.gd
##
## 作用：
## 表示一种“疾病”的数据。
##
## 当前版本：
## 1. 保留七区独立脉象四轴
## 2. 新增供 PulseDrawer 直接使用的转换接口
## 3. 支持通过区域ID直接获取脉象
##
## 七区：
## - 表
## - 心
## - 肝
## - 脾
## - 肺
## - 肾阴
## - 肾阳
##
## 每个区域都有自己的四轴：
## - 气轴      -> 波峰高度
## - 血轴      -> 线条粗细
## - 寒热轴    -> 波形速度
## - 湿燥轴    -> 波峰间距
##
## 推荐给 PulseDrawer 使用的区域ID：
## - exterior
## - heart
## - liver
## - spleen
## - lung
## - kidney_yin
## - kidney_yang
## =========================================================

class_name DiseaseData
extends Resource


## =========================================================
## 一、基础信息
## =========================================================

@export var disease_id: String = ""
@export var disease_name: String = ""
@export var recommended_formula_id: String = ""

## 病证 / 症状自述
## 说明：
## 1. 每个元素填写一个症状，例如："咳嗽不止"、"胸中发闷"、"夜里难眠"。
## 2. Clinic 进入病人时会从这里随机抽取一个症状，用于组合 NPC 台词。
## 3. 为空时，Clinic 会回退显示 disease_name，避免旧疾病数据没有填写时出现空文本。
@export var Symptoms: Array[String] = []


## =========================================================
## 二、七区独立脉象四轴
## =========================================================

## -------------------------
## 1. 表区
## -------------------------
@export_group("表")
@export_range(0.0, 200.0, 0.1)
var exterior_qi: float = 1

@export_range(0.0, 200.0, 0.1)
var exterior_blood: float = 1

@export_range(0.0, 100.0, 0.1)
var exterior_cold_hot: float = 1

@export_range(0.0, 100.0, 0.1)
var exterior_wet_dry: float = 1


## -------------------------
## 2. 心区
## -------------------------
@export_group("心")
@export_range(0.0, 200.0, 0.1)
var heart_qi: float = 1

@export_range(0.0, 200.0, 0.1)
var heart_blood: float = 1

@export_range(0.0, 100.0, 0.1)
var heart_cold_hot: float = 1

@export_range(0.0, 100.0, 0.1)
var heart_wet_dry: float = 1


## -------------------------
## 3. 肝区
## -------------------------
@export_group("肝")
@export_range(0.0, 200.0, 0.1)
var liver_qi: float = 1

@export_range(0.0, 200.0, 0.1)
var liver_blood: float = 1

@export_range(0.0, 100.0, 0.1)
var liver_cold_hot: float = 1

@export_range(0.0, 100.0, 0.1)
var liver_wet_dry: float = 1


## -------------------------
## 4. 脾区
## -------------------------
@export_group("脾")
@export_range(0.0, 200.0, 0.1)
var spleen_qi: float = 1

@export_range(0.0, 200.0, 0.1)
var spleen_blood: float = 1

@export_range(0.0, 100.0, 0.1)
var spleen_cold_hot: float = 1

@export_range(0.0, 100.0, 0.1)
var spleen_wet_dry: float = 1


## -------------------------
## 5. 肺区
## -------------------------
@export_group("肺")
@export_range(0.0, 200.0, 0.1)
var lung_qi: float = 1

@export_range(0.0, 200.0, 0.1)
var lung_blood: float = 1

@export_range(0.0, 100.0, 0.1)
var lung_cold_hot: float = 1

@export_range(0.0, 100.0, 0.1)
var lung_wet_dry: float = 1


## -------------------------
## 6. 肾阴区
## -------------------------
@export_group("肾阴")
@export_range(0.0, 200.0, 0.1)
var kidney_yin_qi: float = 1

@export_range(0.0, 200.0, 0.1)
var kidney_yin_blood: float = 1

@export_range(0.0, 100.0, 0.1)
var kidney_yin_cold_hot: float = 1

@export_range(0.0, 100.0, 0.1)
var kidney_yin_wet_dry: float = 1


## -------------------------
## 7. 肾阳区
## -------------------------
@export_group("肾阳")
@export_range(0.0, 200.0, 0.1)
var kidney_yang_qi: float = 1

@export_range(0.0, 200.0, 0.1)
var kidney_yang_blood: float = 1

@export_range(0.0, 100.0, 0.1)
var kidney_yang_cold_hot: float = 1

@export_range(0.0, 100.0, 0.1)
var kidney_yang_wet_dry: float = 1


## =========================================================
## 三、病证文本接口
## =========================================================

func get_symptoms_text() -> String:
	var symptom_list := get_symptom_list()
	if symptom_list.is_empty():
		return disease_name.strip_edges()
	return "\n".join(symptom_list)


func get_symptom_list() -> Array[String]:
	var result: Array[String] = []
	for raw_symptom in Symptoms:
		var symptom := str(raw_symptom).strip_edges()
		if symptom != "":
			result.append(symptom)
	return result


func get_random_symptom_text() -> String:
	var symptom_list := get_symptom_list()
	if symptom_list.is_empty():
		return disease_name.strip_edges()
	return symptom_list.pick_random()


## =========================================================
## 四、区域名称 / 区域ID 对照
## =========================================================

const REGION_ID_TO_NAME := {
	"exterior": "表",
	"heart": "心",
	"liver": "肝",
	"spleen": "脾",
	"lung": "肺",
	"kidney_yin": "肾阴",
	"kidney_yang": "肾阳"
}

const REGION_NAME_TO_ID := {
	"表": "exterior",
	"心": "heart",
	"肝": "liver",
	"脾": "spleen",
	"肺": "lung",
	"肾阴": "kidney_yin",
	"肾阳": "kidney_yang"
}


## =========================================================
## 五、基础工具函数
## =========================================================

## 获取指定区域的四轴
## region_name 可传：
## "表" "心" "肝" "脾" "肺" "肾阴" "肾阳"
func get_region_pulse_values(region_name: String) -> Dictionary:
	match region_name:
		"表":
			return {
				"region_id": "exterior",
				"region_name": "表",
				"qi": exterior_qi,
				"blood": exterior_blood,
				"cold_hot": exterior_cold_hot,
				"wet_dry": exterior_wet_dry
			}
		"心":
			return {
				"region_id": "heart",
				"region_name": "心",
				"qi": heart_qi,
				"blood": heart_blood,
				"cold_hot": heart_cold_hot,
				"wet_dry": heart_wet_dry
			}
		"肝":
			return {
				"region_id": "liver",
				"region_name": "肝",
				"qi": liver_qi,
				"blood": liver_blood,
				"cold_hot": liver_cold_hot,
				"wet_dry": liver_wet_dry
			}
		"脾":
			return {
				"region_id": "spleen",
				"region_name": "脾",
				"qi": spleen_qi,
				"blood": spleen_blood,
				"cold_hot": spleen_cold_hot,
				"wet_dry": spleen_wet_dry
			}
		"肺":
			return {
				"region_id": "lung",
				"region_name": "肺",
				"qi": lung_qi,
				"blood": lung_blood,
				"cold_hot": lung_cold_hot,
				"wet_dry": lung_wet_dry
			}
		"肾阴":
			return {
				"region_id": "kidney_yin",
				"region_name": "肾阴",
				"qi": kidney_yin_qi,
				"blood": kidney_yin_blood,
				"cold_hot": kidney_yin_cold_hot,
				"wet_dry": kidney_yin_wet_dry
			}
		"肾阳":
			return {
				"region_id": "kidney_yang",
				"region_name": "肾阳",
				"qi": kidney_yang_qi,
				"blood": kidney_yang_blood,
				"cold_hot": kidney_yang_cold_hot,
				"wet_dry": kidney_yang_wet_dry
			}
		_:
			return {}


## 根据区域ID获取四轴
## region_id 可传：
## "exterior" "heart" "liver" "spleen" "lung" "kidney_yin" "kidney_yang"
func get_region_pulse_values_by_id(region_id: String) -> Dictionary:
	if not REGION_ID_TO_NAME.has(region_id):
		return {}

	return get_region_pulse_values(REGION_ID_TO_NAME[region_id])


## 获取所有区域中文名
func get_all_region_names() -> Array[String]:
	return ["表", "心", "肝", "脾", "肺", "肾阴", "肾阳"]


## 获取所有区域ID
func get_all_region_ids() -> Array[String]:
	return [
		"exterior",
		"heart",
		"liver",
		"spleen",
		"lung",
		"kidney_yin",
		"kidney_yang"
	]


## 获取所有区域四轴（数组形式）
func get_all_region_pulse_values() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for region_name in get_all_region_names():
		result.append(get_region_pulse_values(region_name))
	return result


## =========================================================
## 六、给 PulseDrawer 直接使用的接口
## =========================================================

## 返回 PulseDrawer 可直接使用的区域字典
## key 为按钮 / 绘图层使用的固定区域ID
##
## 返回结构示例：
## {
##     "exterior": {
##         "region_id": "exterior",
##         "region_name": "表",
##         "qi": 100.0,
##         "blood": 100.0,
##         "cold_hot": 1.3,
##         "wet_dry": 10.0
##     },
##     ...
## }
func get_pulse_regions_for_drawer() -> Dictionary:
	var result: Dictionary = {}

	for region_id in get_all_region_ids():
		result[region_id] = get_region_pulse_values_by_id(region_id)

	return result


## 兼容某些绘图层字段命名
## 如果你的 PulseDrawer 用的是 speed / width，而不是 cold_hot / wet_dry
## 可以直接调用这个函数，省得在绘图层再转换一次
func get_pulse_regions_for_drawer_visual() -> Dictionary:
	var result: Dictionary = {}

	for region_id in get_all_region_ids():
		var raw_data: Dictionary = get_region_pulse_values_by_id(region_id)

		result[region_id] = {
			"region_id": raw_data.get("region_id", region_id),
			"region_name": raw_data.get("region_name", ""),
			"qi": raw_data.get("qi", 100.0),
			"blood": raw_data.get("blood", 100.0),
			"speed": raw_data.get("cold_hot", 1.3),
			"width": raw_data.get("wet_dry", 10.0)
		}

	return result


## =========================================================
## 七、调试输出
## =========================================================

func debug_print() -> void:
	print("疾病ID:", disease_id)
	print("疾病名:", disease_name)
	print("推荐方剂:", recommended_formula_id)
	print("病证:", get_symptoms_text())

	print("【七区脉象】")
	for region_data in get_all_region_pulse_values():
		print(
			"  ",
			region_data["region_name"],
			" | 气:", region_data["qi"],
			" 血:", region_data["blood"],
			" 寒热:", region_data["cold_hot"],
			" 湿燥:", region_data["wet_dry"]
		)
