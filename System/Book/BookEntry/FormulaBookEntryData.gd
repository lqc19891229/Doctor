extends BookEntryData
class_name FormulaBookEntryData

# 对应方剂ID
@export var formula_id: String = ""

func get_entry_type() -> String:
	return "formula"

func is_valid_data() -> bool:
	if not super.is_valid_data():
		return false

	if formula_id.strip_edges() == "":
		return false

	return true
