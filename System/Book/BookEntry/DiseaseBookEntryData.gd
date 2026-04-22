extends BookEntryData
class_name DiseaseBookEntryData

# 对应病证ID
@export var disease_id: String = ""

# 前置条目（必须全部已读）
@export var prerequisite_entry_ids: Array[String] = []

func get_entry_type() -> String:
	return "disease"

func is_valid_data() -> bool:
	if not super.is_valid_data():
		return false

	if disease_id.strip_edges() == "":
		return false

	return true
