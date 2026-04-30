extends Resource
class_name BookData

@export_enum("herb", "disease", "formula", "theory", "clinical_log")
var book_type: String = "disease"

@export var book_id: String = ""
@export var book_name: String = ""
@export_multiline var detail_text: String = ""
@export var author_name: String = ""
@export var sort_index: int = 0

@export var visible_by_default: bool = true
@export var read_once: bool = false
@export var allow_daytime_open: bool = true

func is_valid_data() -> bool:
	return validate_data().is_empty()

func validate_data() -> Array[String]:
	var errors: Array[String] = []
	if book_id.strip_edges() == "":
		errors.append("book_id 为空")
	if book_name.strip_edges() == "":
		errors.append("book_name 为空")
	if book_type.strip_edges() == "":
		errors.append("book_type 为空")
	return errors

func is_herb_book() -> bool:
	return book_type == "herb"

func is_disease_book() -> bool:
	return book_type == "disease"

func is_formula_book() -> bool:
	return book_type == "formula"
	
func is_theory_book() -> bool:
	return book_type == "theory"
	
func is_medical_theory_book() -> bool:
	return is_disease_book() or is_formula_book() or is_theory_book()

func is_clinical_log_book() -> bool:
	return book_type == "clinical_log"

func get_herb_unlock_order() -> Array[String]:
	return []

func get_unlock_entry_ids() -> Array[String]:
	return []

func uses_day_reading() -> bool:
	return is_herb_book() and not get_herb_unlock_order().is_empty()

func has_unlock_entries() -> bool:
	if is_herb_book():
		return not get_herb_unlock_order().is_empty()
	if is_medical_theory_book():
		return not get_unlock_entry_ids().is_empty()
	return false

func can_open_as_clinical_log() -> bool:
	return is_clinical_log_book() and allow_daytime_open

func can_open_in_daytime() -> bool:
	return is_clinical_log_book() and allow_daytime_open

func can_read_at_night() -> bool:
	return is_herb_book() or is_medical_theory_book()

func get_book_type_label() -> String:
	match book_type:
		"herb":
			return "药材书"
		"disease":
			return "病证书"
		"formula":
			return "方剂书"
		"theory":
			return "医理书"
		"clinical_log":
			return "行医记考"
		_:
			return "未知类型"
