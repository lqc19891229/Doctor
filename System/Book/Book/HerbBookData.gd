extends BookData
class_name HerbBookData

@export var herb_unlock_order: Array[String] = []

func validate_data() -> Array[String]:
	var errors := super.validate_data()
	if book_type != "herb":
		errors.append("HerbBookData 的 book_type 必须为 herb")
	for i in range(herb_unlock_order.size()):
		if herb_unlock_order[i].strip_edges() == "":
			errors.append("herb_unlock_order 第 %d 项为空字符串" % i)
	return errors

func get_herb_unlock_order() -> Array[String]:
	return herb_unlock_order.duplicate()

func get_unlock_entry_ids() -> Array[String]:
	return herb_unlock_order.duplicate()
