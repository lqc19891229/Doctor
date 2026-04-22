extends BookEntryData
class_name HerbBookEntryData

# =========================================================
# 药材书条目
# =========================================================

# 对应药材ID
@export var herb_id: String = ""

func get_entry_type() -> String:
	return "herb"


func is_valid_data() -> bool:
	if not super.is_valid_data():
		return false

	if herb_id.strip_edges() == "":
		return false

	return true
