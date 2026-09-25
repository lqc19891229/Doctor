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
var treatment_failed: bool = false

## =========================================================
## 五、台词系统（唯一入口）
## =========================================================

@export_multiline var dialogue_prefix: String = ""
@export_multiline var dialogue_suffix: String = ""
@export_multiline var dialogue_after_treatment: String = ""
@export_multiline var dialogue_treatment_failed: String = ""

var runtime_before_dialogue: String = ""
var runtime_after_dialogue: String = ""
var runtime_failed_dialogue: String = ""

## =========================================================
## 六、本地化辅助
## =========================================================

# UI 显示姓名统一通过这个方法获取。
# npc_name 本身仍保留 .tres 中的原始中文，避免把当前语言写进存档或业务数据。
func get_localized_name() -> String:
	var fallback := npc_name.strip_edges()
	var clean_id := npc_id.strip_edges()

	if clean_id == "":
		return fallback

	var translation_key := "UI_NPC_NAME_" + clean_id.to_upper()
	var translated := TranslationServer.translate(translation_key)

	if translated.strip_edges() == "" or translated == translation_key:
		return fallback

	return translated


func _is_english_locale() -> bool:
	return TranslationServer.get_locale().to_lower().begins_with("en")


func _get_localized_dialogue(dialogue_type: String) -> String:
	var clean_id := npc_id.strip_edges()
	if clean_id == "":
		return ""

	var translation_key := "UI_NPC_DIALOGUE_%s_%s" % [
		dialogue_type.to_upper(),
		clean_id.to_upper()
	]
	var translated := TranslationServer.translate(translation_key)

	if translated.strip_edges() == "" or translated == translation_key:
		return ""

	return translated


## =========================================================
## 七、对外接口（唯一台词生成入口）
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
	# 中文环境保持原来的 prefix + symptom + suffix 动态拼接。
	# 英文 random NPC 使用翻译表中的完整英文句，避免中文碎片混入英文。
	if _is_english_locale() and npc_type.strip_edges().to_lower() == "random":
		var translated := _get_localized_dialogue("BEFORE")
		if translated != "":
			return translated

	if runtime_before_dialogue.strip_edges() == "":
		runtime_before_dialogue = _build_before_treatment_dialogue()
	return runtime_before_dialogue


func get_after_treatment_dialogue() -> String:
	if _is_english_locale() and npc_type.strip_edges().to_lower() == "random":
		var translated := _get_localized_dialogue("AFTER")
		if translated != "":
			return translated

	if runtime_after_dialogue.strip_edges() == "":
		runtime_after_dialogue = _build_after_treatment_dialogue()
	return runtime_after_dialogue


func get_treatment_failed_dialogue() -> String:
	if _is_english_locale() and npc_type.strip_edges().to_lower() == "random":
		var translated := _get_localized_dialogue("FAILED")
		if translated != "":
			return translated

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
## 八、症状获取（完全本地化）
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
## 九、立绘获取
## =========================================================

func get_current_portrait() -> Texture2D:
	if is_treated and portrait_after_treatment != null:
		return portrait_after_treatment

	if portrait_before_treatment != null:
		return portrait_before_treatment

	return null
