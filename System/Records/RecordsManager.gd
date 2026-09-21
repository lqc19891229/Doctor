extends Node
class_name RecordsManager

## 医馆账册的持久化数据。
##
## 诊疗记录和统计与 UnlockManager 的经济/解锁状态分开保存，
## 但仍由 SaveManager 统一写入同一个存档，避免 UI 直接修改业务数据。

signal records_changed

var treatment_records: Dictionary = {}
var _next_record_serial: int = 1


func reset_progress() -> void:
	treatment_records.clear()
	_next_record_serial = 1
	records_changed.emit()


func record_treatment(day: int, data: Dictionary) -> Dictionary:
	var safe_day := maxi(day, 1)
	var day_key := str(safe_day)
	var day_records: Array = treatment_records.get(day_key, [])
	var record := data.duplicate(true)

	record["day"] = safe_day
	record["record_id"] = "%d_%d" % [safe_day, _next_record_serial]
	_next_record_serial += 1
	day_records.append(record)
	treatment_records[day_key] = day_records
	records_changed.emit()
	return record.duplicate(true)


func get_treatment_records(day: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if day > 0:
		var source: Array = treatment_records.get(str(day), [])
		for item in source:
			if typeof(item) == TYPE_DICTIONARY:
				result.append(item.duplicate(true))
		return result

	var days: Array[int] = []
	for key in treatment_records.keys():
		days.append(int(key))
	days.sort()
	for day_key in days:
		var source: Array = treatment_records.get(str(day_key), [])
		for item in source:
			if typeof(item) == TYPE_DICTIONARY:
				result.append(item.duplicate(true))
	return result


func get_record_days() -> Array[int]:
	var days: Array[int] = []
	for key in treatment_records.keys():
		days.append(int(key))
	days.sort()
	return days


func get_statistics() -> Dictionary:
	var total_patients := 0
	var successful_patients := 0
	var miaoshou_patients := 0
	var failed_patients := 0

	for record in get_treatment_records():
		total_patients += 1
		if bool(record.get("success", false)):
			successful_patients += 1
		else:
			failed_patients += 1
		if String(record.get("grade", "")) == "妙手回春":
			miaoshou_patients += 1

	var success_rate := 0.0
	if total_patients > 0:
		success_rate = float(successful_patients) * 100.0 / float(total_patients)

	var finance := {}
	if Unlock != null and Unlock.has_method("get_finance_totals"):
		finance = Unlock.get_finance_totals()

	return {
		"total_patients": total_patients,
		"successful_patients": successful_patients,
		"failed_patients": failed_patients,
		"miaoshou_patients": miaoshou_patients,
		"success_rate": success_rate,
		"total_income_wen": int(finance.get("total_income_wen", 0)),
		"total_expense_wen": int(finance.get("total_expense_wen", 0)),
		"net_change_wen": int(finance.get("net_change_wen", 0)),
		"finance_days": int(finance.get("finance_days", 0))
	}


func get_save_data() -> Dictionary:
	return {
		"treatment_records": treatment_records,
		"next_record_serial": _next_record_serial
	}


func load_save_data(data: Dictionary) -> void:
	treatment_records.clear()
	_next_record_serial = maxi(int(data.get("next_record_serial", 1)), 1)

	var loaded_records = data.get("treatment_records", {})
	if typeof(loaded_records) == TYPE_DICTIONARY:
		for key in loaded_records.keys():
			var source = loaded_records[key]
			if typeof(source) != TYPE_ARRAY:
				continue
			var clean_records: Array = []
			for item in source:
				if typeof(item) == TYPE_DICTIONARY:
					clean_records.append(item.duplicate(true))
			treatment_records[str(key)] = clean_records

	# 兼容手工编辑或旧版数据，保证序号不会覆盖现有记录。
	for record in get_treatment_records():
		var record_id := String(record.get("record_id", ""))
		var parts := record_id.split("_")
		if parts.size() >= 2 and String(parts[1]).is_valid_int():
			_next_record_serial = maxi(_next_record_serial, int(parts[1]) + 1)

	records_changed.emit()
