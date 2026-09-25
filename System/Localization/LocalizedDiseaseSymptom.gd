extends RefCounted
class_name LocalizedDiseaseSymptom

# =========================================================
# 从已经本地化的疾病正文中读取 [Symptoms] / 【症状】。
# 这样不需要在 48 个 Disease .tres 中维护第二套英文症状。
# =========================================================


static func get_symptom_list(disease: DiseaseData) -> Array[String]:
	var result: Array[String] = []

	if disease == null:
		return result

	var disease_id := disease.disease_id.strip_edges()
	if disease_id != "":
		var translation_key := "UI_BOOK_ENTRY_BODY_" + disease_id.to_upper()
		var localized_body := TranslationServer.translate(translation_key)

		if localized_body.strip_edges() != "" and localized_body != translation_key:
			var section := _extract_symptoms_section(localized_body)
			result = _split_symptoms(section)
			if not result.is_empty():
				return result

	# 回退：如果 DiseaseData 本身已经填写 Symptoms，就继续使用原数据。
	if disease.has_method("get_symptom_list"):
		var source_list: Array = disease.get_symptom_list()
		for value in source_list:
			var symptom := str(value).strip_edges()
			if symptom != "":
				result.append(symptom)

	return result


static func get_random_symptom(disease: DiseaseData) -> String:
	var list := get_symptom_list(disease)

	if not list.is_empty():
		return str(list.pick_random()).strip_edges()

	var fallback_key := "UI_NPC_GENERIC_SYMPTOM"
	var fallback := TranslationServer.translate(fallback_key)
	if fallback.strip_edges() == "" or fallback == fallback_key:
		return "身体不适"

	return fallback


static func _extract_symptoms_section(value: String) -> String:
	var text := value.replace("\r\n", "\n").replace("\r", "\n")

	# 中文正文。
	var zh_marker := "【症状】"
	var zh_start := text.find(zh_marker)
	if zh_start >= 0:
		var content_start := zh_start + zh_marker.length()
		var rest := text.substr(content_start)
		var next_heading := rest.find("\n【")
		if next_heading >= 0:
			rest = rest.substr(0, next_heading)
		return rest.strip_edges()

	# 英文正文。
	var en_marker := "[Symptoms]"
	var en_start := text.to_lower().find(en_marker.to_lower())
	if en_start >= 0:
		var content_start := en_start + en_marker.length()
		var rest := text.substr(content_start)

		# 下一段英文 [Heading]。
		var next_heading := rest.find("\n[")
		if next_heading >= 0:
			rest = rest.substr(0, next_heading)

		return rest.strip_edges()

	return ""


static func _split_symptoms(value: String) -> Array[String]:
	var result: Array[String] = []
	var clean_text := value.replace("\n", " ").strip_edges()

	if clean_text == "":
		return result

	# 长症状段优先按分号拆分；没有分号时再按逗号拆。
	var raw_parts: PackedStringArray

	if clean_text.contains("；") or clean_text.contains(";"):
		var normalized := clean_text.replace("；", ";")
		raw_parts = normalized.split(";", false)
	else:
		var normalized := clean_text.replace("，", ",")
		raw_parts = normalized.split(",", false)

	for raw_part in raw_parts:
		var symptom := str(raw_part).strip_edges()

		# 清除句末标点。
		while (
			symptom.ends_with("。")
			or symptom.ends_with(".")
			or symptom.ends_with("；")
			or symptom.ends_with(";")
			or symptom.ends_with("，")
			or symptom.ends_with(",")
		):
			symptom = symptom.left(symptom.length() - 1).strip_edges()

		# 英文列表最后一项经常以 and / or 开头。
		var lower := symptom.to_lower()
		if lower.begins_with("and "):
			symptom = symptom.substr(4).strip_edges()
		elif lower.begins_with("or "):
			symptom = symptom.substr(3).strip_edges()

		if symptom != "":
			result.append(symptom)

	# 保险：如果拆分后仍然只有一项，就保留这一项作为合法症状。
	if result.is_empty() and clean_text != "":
		result.append(clean_text)

	return result
