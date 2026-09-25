extends RefCounted
class_name LocalizedDiseaseSymptom

# =========================================================
# 随机 NPC 症状本地化
#
# 唯一症状来源：
# DataTables/Data.xlsx -> Disease -> Symptoms
#
# import_data.py 会把 Symptoms 写入 DiseaseData.Symptoms。
# 本脚本不再从 DetailText / 【症状】 / [Symptoms] 中解析文本。
# =========================================================


static func get_symptom_list(disease: DiseaseData) -> Array[String]:
	var result: Array[String] = []

	if disease == null:
		return result

	if not disease.has_method("get_symptom_list"):
		return result

	var source_list: Array = disease.get_symptom_list()

	for value in source_list:
		var symptom := str(value).strip_edges()
		if symptom != "":
			result.append(symptom)

	return result


static func get_random_symptom(disease: DiseaseData) -> String:
	var list := get_symptom_list(disease)

	if list.is_empty():
		return _generic_symptom()

	var symptom_index: int = randi_range(0, list.size() - 1)
	return get_localized_symptom(disease, symptom_index)


static func get_localized_symptom(disease: DiseaseData, symptom_index: int) -> String:
	if disease == null:
		return _generic_symptom()

	var list := get_symptom_list(disease)
	if symptom_index < 0 or symptom_index >= list.size():
		return _generic_symptom()

	var fallback := str(list[symptom_index]).strip_edges()
	var clean_id := disease.disease_id.strip_edges()

	if clean_id == "":
		return fallback

	# 序号严格对应 Data.xlsx Disease!Symptoms 中按 | 分隔后的顺序。
	# 例如：
	# UI_DISEASE_SYMPTOM_FENG_HAN_BIAO_SHI_ZHENG_01
	var translation_key := "UI_DISEASE_SYMPTOM_%s_%02d" % [
		clean_id.to_upper(),
		symptom_index + 1
	]

	var translated := TranslationServer.translate(translation_key)

	if translated.strip_edges() == "" or translated == translation_key:
		return fallback

	return translated


static func _generic_symptom() -> String:
	var key := "UI_NPC_GENERIC_SYMPTOM"
	var translated := TranslationServer.translate(key)

	if translated.strip_edges() == "" or translated == key:
		return "身体不适"

	return translated
