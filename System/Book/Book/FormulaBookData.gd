extends BookData
class_name FormulaBookData

@export var unlock_entry_ids: Array[String] = []

func validate_data() -> Array[String]:
	var errors := super.validate_data()
	if book_type != "formula":
		errors.append("FormulaBookData 的 book_type 必须为 formula")
	for i in range(unlock_entry_ids.size()):
		if unlock_entry_ids[i].strip_edges() == "":
			errors.append("unlock_entry_ids 第 %d 项为空字符串" % i)
	return errors

func get_unlock_entry_ids() -> Array[String]:
	return unlock_entry_ids.duplicate()
