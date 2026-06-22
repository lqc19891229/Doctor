## =========================================================
## NpcData.gd
##
## NPC数据 + 台词系统（唯一来源）
## =========================================================

class_name NpcData
extends Resource

## =========================================================
## 一、基础身份信息
## =========================================================

@export var npc_id: String = ""
@export_enum("random", "story") var npc_type: String = "random"
@export var npc_name: String = ""
@export var gender: String = "男"
@export var age: int = 20

## =========================================================
## 二、外观信息
## =========================================================

# 治疗前立绘：病人刚进入诊室、尚未提交处方时显示。
@export var portrait_before_treatment: Texture2D

# 治疗后立绘：提交处方判定成功后显示。
@export var portrait_after_treatment: Texture2D


## =========================================================
## 三、疾病信息
## =========================================================

@export var disease: DiseaseData

## =========================================================
## 四、诊疗状态
## =========================================================

@export var is_treated: bool = false

# 本轮治疗是否失败。失败时保持治疗前立绘，但显示治疗失败台词。
var treatment_failed: bool = false

## =========================================================
## 五、台词系统（唯一入口）
## =========================================================

# 治疗前台词开头
@export_multiline var dialogue_prefix: String = ""

# 治疗前台词结尾
@export_multiline var dialogue_suffix: String = ""

# 治疗后台词。治愈后显示 portrait_after_treatment 时使用。
@export_multiline var dialogue_after_treatment: String = ""

# 治疗失败台词。治疗失败时保持治疗前立绘，但显示这段台词。
@export_multiline var dialogue_treatment_failed: String = ""

# 运行时缓存：保证同一名病人刷新 UI / 打开窗口时，台词不会反复随机变化。
var runtime_before_dialogue: String = ""
var runtime_after_dialogue: String = ""
var runtime_failed_dialogue: String = ""

## =========================================================
## 六、对外接口（唯一台词生成入口）
## =========================================================

func setup_clinic_visit() -> void:
	# 每次进入 Clinic 都是一轮新的诊疗。
	is_treated = false
	treatment_failed = false
	runtime_before_dialogue = _build_before_treatment_dialogue()
	runtime_after_dialogue = _build_after_treatment_dialogue()
	runtime_failed_dialogue = _build_treatment_failed_dialogue()


func get_dialogue() -> String:
	if treatment_failed:
		return get_treatment_failed_dialogue()
	if is_treated:
		return get_after_treatment_dialogue()
	return get_before_treatment_dialogue()


func get_before_treatment_dialogue() -> String:
	if runtime_before_dialogue.strip_edges() == "":
		runtime_before_dialogue = _build_before_treatment_dialogue()
	return runtime_before_dialogue


func get_after_treatment_dialogue() -> String:
	if runtime_after_dialogue.strip_edges() == "":
		runtime_after_dialogue = _build_after_treatment_dialogue()
	return runtime_after_dialogue


func get_treatment_failed_dialogue() -> String:
	if runtime_failed_dialogue.strip_edges() == "":
		runtime_failed_dialogue = _build_treatment_failed_dialogue()
	return runtime_failed_dialogue


func _build_before_treatment_dialogue() -> String:
	if disease == null:
		return _compose_dialogue("大夫，我近日身体不适。")

	var symptom := _get_random_symptom()
	if symptom == "":
		symptom = "身体不适"

	return _compose_dialogue(symptom)


func _build_after_treatment_dialogue() -> String:
	var text := dialogue_after_treatment.strip_edges()
	if text != "":
		return text
	return "多谢大夫，我觉得好多了。"


func _build_treatment_failed_dialogue() -> String:
	var text := dialogue_treatment_failed.strip_edges()
	if text != "":
		return text
	return "大夫，我这病怎么还不见好……"


func _compose_dialogue(core: String) -> String:
	var prefix_text := dialogue_prefix.strip_edges()
	var suffix_text := dialogue_suffix.strip_edges()

	var result := ""

	if prefix_text != "":
		result += prefix_text

	result += core

	if suffix_text != "":
		if not suffix_text.begins_with("，") and not suffix_text.begins_with("。"):
			result += "，"
		result += suffix_text

	return result


## =========================================================
## 七、症状获取（完全本地化）
## =========================================================

func _get_random_symptom() -> String:
	if disease == null:
		return ""

	if not disease.has_method("get_symptom_list"):
		return ""

	var list: Array = disease.get_symptom_list()
	if list.is_empty():
		return ""

	return str(list.pick_random()).strip_edges()



## =========================================================
## 八、立绘获取
## =========================================================

func get_current_portrait() -> Texture2D:
	# 治疗后优先显示 portrait_after_treatment。
	if is_treated and portrait_after_treatment != null:
		return portrait_after_treatment

	# 治疗前优先显示 portrait_before_treatment。
	if portrait_before_treatment != null:
		return portrait_before_treatment

	return null
