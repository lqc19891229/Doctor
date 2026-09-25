## =========================================================
## NpcData.gd
##
## NPC数据 + 台词系统（唯一来源）
## 中文 / 英文使用同一结构：
## prefix + 随机症状 + suffix
## after / failed 独立本地化
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

@export var portrait_before_treatment: Texture2D
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
## 五、台词系统
## =========================================================

@export_multiline var dialogue_prefix: String = ""
@export_multiline var dialogue_suffix: String = ""
@export_multiline var dialogue_after_treatment: String = ""
@export_multiline var dialogue_treatment_failed: String = ""

# 同一轮诊疗中保持固定，避免刷新 UI 时重新随机症状。
var runtime_before_dialogue: String = ""
var runtime_after_dialogue: String = ""
var runtime_failed_dialogue: String = ""

## =========================================================
## 六、本地化辅助
## =========================================================

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


func _get_localized_dialogue_part(part: String, fallback: String) -> String:
	var clean_id := npc_id.strip_edges()
	if clean_id == "":
		return fallback.strip_edges()

	var translation_key := "UI_NPC_DIALOGUE_%s_%s" % [
		part.to_upper(),
		clean_id.to_upper()
	]

	var translated := TranslationServer.translate(translation_key)

	if translated.strip_edges() == "" or translated == translation_key:
		return fallback.strip_edges()

	return translated.strip_edges()


func _is_english_locale() -> bool:
	return TranslationServer.get_locale().to_lower().begins_with("en")


## =========================================================
## 七、对外接口
## =========================================================

func setup_clinic_visit() -> void:
	is_treated = false
	treatment_failed = false

	# 这里一次性随机好治疗前症状并组成台词。
	# 后续刷新 Clinic UI 不会再次随机。
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
	var symptom := LocalizedDiseaseSymptom.get_random_symptom(disease)
	if symptom.strip_edges() == "":
		var fallback_key := "UI_NPC_GENERIC_SYMPTOM"
		symptom = TranslationServer.translate(fallback_key)
		if symptom == fallback_key or symptom.strip_edges() == "":
			symptom = "身体不适"

	return _compose_dialogue(symptom)


func _build_after_treatment_dialogue() -> String:
	var fallback := dialogue_after_treatment.strip_edges()
	if fallback == "":
		fallback = "多谢大夫，我觉得好多了。"

	return _get_localized_dialogue_part("AFTER", fallback)


func _build_treatment_failed_dialogue() -> String:
	var fallback := dialogue_treatment_failed.strip_edges()
	if fallback == "":
		fallback = "大夫，我这病怎么还不见好……"

	return _get_localized_dialogue_part("FAILED", fallback)


func _compose_dialogue(core: String) -> String:
	var prefix_text := _get_localized_dialogue_part("PREFIX", dialogue_prefix)
	var suffix_text := _get_localized_dialogue_part("SUFFIX", dialogue_suffix)
	var symptom := core.strip_edges()

	# 英文使用自然的空格 / 句号连接。
	if _is_english_locale():
		var result := prefix_text

		if symptom != "":
			if result != "" and not result.ends_with(" "):
				result += " "
			result += symptom

		if result != "" and not (
			result.ends_with(".")
			or result.ends_with("!")
			or result.ends_with("?")
		):
			result += "."

		if suffix_text != "":
			if result != "":
				result += " "
			result += suffix_text

		return result.strip_edges()

	# 中文完全保留原有拼接规则。
	var result := ""

	if prefix_text != "":
		result += prefix_text

	result += symptom

	if suffix_text != "":
		if not suffix_text.begins_with("，") and not suffix_text.begins_with("。"):
			result += "，"
		result += suffix_text

	return result


## =========================================================
## 八、立绘获取
## =========================================================

func get_current_portrait() -> Texture2D:
	if is_treated and portrait_after_treatment != null:
		return portrait_after_treatment

	if portrait_before_treatment != null:
		return portrait_before_treatment

	return null
