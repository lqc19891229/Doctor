extends BookEntryData
class_name DiseaseBookEntryData

# 对应病证ID
@export var disease_id: String = ""

func get_entry_type() -> String:
	return "disease"

func is_valid_data() -> bool:
	if not super.is_valid_data():
		return false

	if disease_id.strip_edges() == "":
		return false

	return true
