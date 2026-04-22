extends BookData
class_name ClinicalLogData

func validate_data() -> Array[String]:
	var errors := super.validate_data()
	if book_type != "clinical_log":
		errors.append("ClinicalLogData 的 book_type 必须为 clinical_log")
	return errors
