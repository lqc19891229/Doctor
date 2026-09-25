extends Window
class_name RecordsWindow

## 医馆账册：诊疗记录、账目明细、数据统计、预制方剂。

const FINANCE_START_DAY: int = 2
const SORT_INDEX_FALLBACK: int = 2147483647

@onready var tabs: TabContainer = %Tabs
@onready var close_button: Button = get_node_or_null("%CloseButton") as Button

@onready var treatment_day_list: ItemList = %TreatmentDayList
@onready var treatment_detail: RichTextLabel = %TreatmentDetail
@onready var finance_day_list: ItemList = %FinanceDayList
@onready var finance_detail: RichTextLabel = %FinanceDetail
@onready var preset_list: ItemList = %PresetList
@onready var preset_detail: RichTextLabel = %PresetDetail

@onready var total_patients_value: Label = %TotalPatientsValue
@onready var successful_patients_value: Label = %SuccessfulPatientsValue
@onready var miaoshou_patients_value: Label = %MiaoshouPatientsValue
@onready var failed_patients_value: Label = %FailedPatientsValue
@onready var success_rate_value: Label = %SuccessRateValue
@onready var total_income_value: Label = %TotalIncomeValue
@onready var total_expense_value: Label = %TotalExpenseValue
@onready var net_change_value: Label = %NetChangeValue

var treatment_days: Array[int] = []
var finance_days: Array[int] = []
var preset_formulas: Array[FormulaData] = []


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return
	_set_localized_titles()
	if not visible:
		return

	# 语言切换时重新生成显示文字，并恢复当前选中的日期与方剂。
	var treatment_selection := treatment_day_list.get_selected_items()
	var finance_selection := finance_day_list.get_selected_items()
	var preset_selection := preset_list.get_selected_items()
	var treatment_index: int = treatment_selection[0] if not treatment_selection.is_empty() else -1
	var finance_index: int = finance_selection[0] if not finance_selection.is_empty() else -1
	var preset_index: int = preset_selection[0] if not preset_selection.is_empty() else -1
	_refresh_all()
	if treatment_index >= 0 and treatment_index < treatment_days.size():
		treatment_day_list.select(treatment_index)
		_show_treatment_day(treatment_days[treatment_index])
	if finance_index >= 0 and finance_index < finance_days.size():
		finance_day_list.select(finance_index)
		_show_finance_day(finance_days[finance_index])
	if preset_index >= 0 and preset_index < preset_formulas.size():
		preset_list.select(preset_index)
		_show_preset(preset_index)


func _set_localized_titles() -> void:
	title = tr("UI_LOG_WINDOW_TITLE")
	tabs.set_tab_title(0, tr("UI_RECORDS_TAB_TREATMENT"))
	tabs.set_tab_title(1, tr("UI_RECORDS_TAB_FINANCE"))
	tabs.set_tab_title(2, tr("UI_RECORDS_TAB_STATS"))
	tabs.set_tab_title(3, tr("UI_RECORDS_TAB_PRESETS"))


func _localized_grade(value: String) -> String:
	match value:
		"妙手回春":
			return tr("UI_RESULT_GRADE_PERFECT")
		"治疗成功":
			return tr("UI_RESULT_GRADE_SUCCESS")
		"治疗失败":
			return tr("UI_RESULT_GRADE_FAILED")
	return value


func _ready() -> void:
	close_requested.connect(_on_close_requested)
	_set_localized_titles()
	if close_button != null:
		close_button.pressed.connect(_on_close_requested)
	treatment_day_list.item_selected.connect(_on_treatment_day_selected)
	finance_day_list.item_selected.connect(_on_finance_day_selected)
	preset_list.item_selected.connect(_on_preset_selected)
	hide()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_window()
		get_viewport().set_input_as_handled()


func open_window() -> void:
	_refresh_all()
	popup_centered()
	grab_focus()


func close_window() -> void:
	hide()


func _on_close_requested() -> void:
	hide()


func _refresh_all() -> void:
	_refresh_treatment_list()
	_refresh_finance_list()
	_refresh_stats()
	_refresh_preset_list()


func _refresh_treatment_list() -> void:
	treatment_days = Records.get_record_days() if Records != null else []
	treatment_day_list.clear()
	for day in treatment_days:
		treatment_day_list.add_item(_format_record_date(day))

	if treatment_days.is_empty():
		treatment_detail.text = tr("UI_RECORDS_TREATMENT_EMPTY")
		return
	treatment_day_list.select(treatment_days.size() - 1)
	_show_treatment_day(treatment_days.back())


func _on_treatment_day_selected(index: int) -> void:
	if index >= 0 and index < treatment_days.size():
		_show_treatment_day(treatment_days[index])


func _show_treatment_day(day: int) -> void:
	var records: Array[Dictionary] = Records.get_treatment_records(day)
	var lines: Array[String] = [tr("UI_RECORDS_TREATMENT_HEADER_FMT") % _format_record_date(day)]
	if records.is_empty():
		lines.append(tr("UI_RECORDS_TREATMENT_DAY_EMPTY"))
	else:
		for index in range(records.size()):
			var record: Dictionary = records[index]
			var status := tr("UI_RECORDS_STATUS_SUCCESS") if bool(record.get("success", false)) else tr("UI_RECORDS_STATUS_NOT_CURED")
			var grade := _localized_grade(_record_text(record, "grade", ""))
			lines.append("\n%d. [font_size=22][color=#fff1c7]%s[/color][/font_size]  %s  ·  %s" % [
				index + 1,
				_record_text(record, "patient_name", tr("UI_RECORDS_UNKNOWN_PATIENT")),
				status,
				grade
			])
			lines.append(tr("UI_RECORDS_DISEASE_FMT") % _record_text(record, "disease_name", tr("UI_RECORDS_NOT_RECORDED")))
			lines.append(tr("UI_RECORDS_FORMULA_FMT") % _record_text(record, "standard_formula_name", tr("UI_RECORDS_NOT_RECORDED")))
			lines.append(tr("UI_RECORDS_DIAGNOSIS_FMT") % _record_text(record, "diagnosis", tr("UI_RECORDS_NOT_RECORDED")))
			lines.append(tr("UI_RECORDS_PRESCRIPTION_FMT") % _record_text(record, "prescription", tr("UI_RECORDS_EMPTY_PRESCRIPTION")).replace("\n", tr("UI_RECORDS_LINE_SEPARATOR")))
			if index < records.size() - 1:
				lines.append("[color=#62482f]────────────────────────[/color]")
	treatment_detail.text = "\n".join(lines)


func _record_text(record: Dictionary, key: String, fallback: String) -> String:
	var value: Variant = record.get(key, null)
	if value == null:
		return fallback
	var text_value := str(value).strip_edges()
	return text_value if not text_value.is_empty() else fallback


func _refresh_finance_list() -> void:
	finance_days.clear()
	if Unlock != null and Unlock.has_method("get_finance_days"):
		for day_value in Unlock.get_finance_days():
			var recorded_day := int(day_value)
			if recorded_day >= FINANCE_START_DAY and not finance_days.has(recorded_day):
				finance_days.append(recorded_day)
	if GameTime != null and GameTime.current_day >= FINANCE_START_DAY and not finance_days.has(GameTime.current_day):
		finance_days.append(GameTime.current_day)
	finance_days.sort()
	finance_day_list.clear()
	for day in finance_days:
		finance_day_list.add_item(_format_record_date(day))
	if finance_days.is_empty():
		finance_detail.text = tr("UI_RECORDS_FINANCE_START_FMT") % _format_record_date(FINANCE_START_DAY)
		return
	finance_day_list.select(finance_days.size() - 1)
	_show_finance_day(finance_days.back())


func _on_finance_day_selected(index: int) -> void:
	if index >= 0 and index < finance_days.size():
		_show_finance_day(finance_days[index])


func _show_finance_day(day: int) -> void:
	if day < FINANCE_START_DAY:
		finance_detail.text = tr("UI_RECORDS_FINANCE_START_FMT") % _format_record_date(FINANCE_START_DAY)
		return
	var report: Dictionary = Unlock.get_finance_detail_for_day(day) if Unlock != null and Unlock.has_method("get_finance_detail_for_day") else {}
	if report.is_empty():
		finance_detail.text = tr("UI_RECORDS_FINANCE_EMPTY_FMT") % _format_record_date(day)
		return

	var settled := bool(report.get("settled", false))
	var lines: Array[String] = [tr("UI_RECORDS_FINANCE_HEADER_FMT") % _format_record_date(day)]
	if not settled:
		lines.append(tr("UI_RECORDS_FINANCE_UNSETTLED"))
	lines.append(tr("UI_RECORDS_INCOME_HEADER"))
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_CONSULTATION"), int(report.get("consultation_income_wen", 0)), true)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_MEDICINE"), int(report.get("medicine_income_wen", 0)), true)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_PATIENT_GIFT"), int(report.get("patient_thank_gift_income_wen", 0)), true)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_LI_JIAN_ZHONG"), int(report.get("li_jian_zhong_salary_wen", 0)), true)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_LI_YAN_WEN"), int(report.get("li_yan_wen_income_wen", 0)), true)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_LAND_RENT"), int(report.get("land_rent_wen", 0)), true)
	lines.append(tr("UI_RECORDS_TOTAL_INCOME_FMT") % _format_money(int(report.get("total_income_wen", 0))))
	lines.append(tr("UI_RECORDS_EXPENSE_HEADER"))
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_STAFF_WAGES"), -int(report.get("staff_wage_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_FOOD"), -int(report.get("food_cost_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_GIFTS"), -int(report.get("human_gift_cost_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_BOOKS"), -int(report.get("medical_book_cost_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_COAL"), -int(report.get("coal_cost_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_CLOTHING"), -int(report.get("clothing_cost_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_REPAIRS"), -int(report.get("house_repair_cost_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_ANCESTORS"), -int(report.get("ancestor_worship_cost_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_MOLDY_HERBS"), -int(report.get("moldy_herb_cost_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_SUMMER_TAX"), -int(report.get("summer_tax_wen", 0)), false)
	_append_money_line(lines, tr("UI_RECORDS_FINANCE_AUTUMN_TAX"), -int(report.get("autumn_tax_wen", 0)), false)
	lines.append(tr("UI_RECORDS_TOTAL_EXPENSE_FMT") % _format_money(-int(report.get("total_expense_wen", 0))))
	lines.append(tr("UI_RECORDS_NET_CHANGE_FMT") % _format_money(int(report.get("net_change_wen", 0))))
	finance_detail.text = "\n".join(lines)


func _append_money_line(lines: Array[String], label: String, amount: int, positive: bool) -> void:
	if amount == 0:
		return
	var color := "#9fe29f" if positive else "#f0a0a0"
	lines.append(tr("UI_RECORDS_MONEY_LINE_FMT") % [label, color, _format_money(amount)])


func _format_money(amount: int) -> String:
	var sign := "+" if amount > 0 else ("-" if amount < 0 else "")
	var absolute := absi(amount)
	return tr("UI_RECORDS_MONEY_FMT") % [sign, absolute / 1000, absolute % 1000]


func _format_money_without_positive_sign(amount: int) -> String:
	var sign := "-" if amount < 0 else ""
	var absolute := absi(amount)
	return tr("UI_RECORDS_MONEY_FMT") % [sign, absolute / 1000, absolute % 1000]


func _format_record_date(day: int) -> String:
	if GameTime != null and GameTime.has_method("get_day_text_by_index"):
		return str(GameTime.get_day_text_by_index(day))
	return tr("UI_RECORDS_DATE_UNKNOWN")


func _refresh_stats() -> void:
	var stats: Dictionary = Records.get_statistics() if Records != null else {}
	total_patients_value.text = tr("UI_RECORDS_PATIENT_COUNT_FMT") % int(stats.get("total_patients", 0))
	successful_patients_value.text = tr("UI_RECORDS_PATIENT_COUNT_FMT") % int(stats.get("successful_patients", 0))
	miaoshou_patients_value.text = tr("UI_RECORDS_PATIENT_COUNT_FMT") % int(stats.get("miaoshou_patients", 0))
	failed_patients_value.text = tr("UI_RECORDS_PATIENT_COUNT_FMT") % int(stats.get("failed_patients", 0))
	success_rate_value.text = "%.1f%%" % float(stats.get("success_rate", 0.0))
	total_income_value.text = _format_money_without_positive_sign(int(stats.get("total_income_wen", 0)))
	total_expense_value.text = _format_money_without_positive_sign(int(stats.get("total_expense_wen", 0)))
	net_change_value.text = _format_money(int(stats.get("net_change_wen", 0)))


func _refresh_preset_list() -> void:
	preset_formulas.clear()
	if FormulaDB != null and FormulaDB.has_method("get_all_formulas"):
		# 复制方剂列表，避免排序时改动 FormulaDB 内部数组的全局顺序。
		for formula in FormulaDB.get_all_formulas():
			if formula != null:
				preset_formulas.append(formula)
	var formula_sort_map := _build_formula_sort_map()
	preset_formulas.sort_custom(func(a: FormulaData, b: FormulaData) -> bool:
		var a_id := a.formula_id.strip_edges()
		var b_id := b.formula_id.strip_edges()
		var a_sort_index := int(formula_sort_map.get(a_id, SORT_INDEX_FALLBACK))
		var b_sort_index := int(formula_sort_map.get(b_id, SORT_INDEX_FALLBACK))
		if a_sort_index != b_sort_index:
			return a_sort_index < b_sort_index
		return a_id.naturalnocasecmp_to(b_id) < 0
	)
	preset_list.clear()
	for formula in preset_formulas:
		var unlocked := Unlock != null and Unlock.has_method("is_preset_formula_unlocked") and Unlock.is_preset_formula_unlocked(formula.formula_id)
		var count := Unlock.get_miaoshouhuichun_prescription_count(formula.formula_id) if Unlock != null and Unlock.has_method("get_miaoshouhuichun_prescription_count") else 0
		var localized_formula_name := LocalizedName.formula(
			formula.formula_id,
			formula.formula_name
		)
		preset_list.add_item("%s  [%d/5]%s" % [localized_formula_name, count, tr("UI_RECORDS_PRESET_UNLOCKED_BADGE") if unlocked else ""])
	if preset_formulas.is_empty():
		preset_detail.text = tr("UI_RECORDS_NO_FORMULAS")
		return
	preset_list.select(0)
	_show_preset(0)


func _build_formula_sort_map() -> Dictionary:
	var result: Dictionary = {}
	if BookEntryDB == null or not BookEntryDB.has_method("get_entries_by_type"):
		return result

	for entry in BookEntryDB.get_entries_by_type("formula"):
		if entry == null:
			continue
		var formula_id := str(entry.get("formula_id")).strip_edges()
		if formula_id.is_empty():
			continue
		result[formula_id] = int(entry.sort_index)

	return result


func _on_preset_selected(index: int) -> void:
	_show_preset(index)


func _show_preset(index: int) -> void:
	if index < 0 or index >= preset_formulas.size():
		return
	var formula := preset_formulas[index]
	var count := Unlock.get_miaoshouhuichun_prescription_count(formula.formula_id) if Unlock != null and Unlock.has_method("get_miaoshouhuichun_prescription_count") else 0
	var unlocked := Unlock.is_preset_formula_unlocked(formula.formula_id) if Unlock != null and Unlock.has_method("is_preset_formula_unlocked") else false
	var status := tr("UI_RECORDS_PRESET_UNLOCKED") if unlocked else tr("UI_RECORDS_PRESET_LOCKED")
	var localized_formula_name := LocalizedName.formula(
		formula.formula_id,
		formula.formula_name
	)
	var lines: Array[String] = [
		"[font_size=26][color=#e3b66b]%s[/color][/font_size]" % localized_formula_name,
		tr("UI_RECORDS_PRESET_PROGRESS_FMT") % count,
		tr("UI_RECORDS_PRESET_STATUS_FMT") % ["#9fe29f" if unlocked else "#c6ae83", status],
		tr("UI_RECORDS_PRESET_INGREDIENTS"),
		"[color=#e3d1aa]%s[/color]" % _formula_ingredients_text(formula)
	]
	preset_detail.text = "\n".join(lines)


func _formula_ingredients_text(formula: FormulaData) -> String:
	var parts: Array[String] = []
	for ingredient in formula.get_all_ingredients():
		if ingredient == null:
			continue

		var localized_herb_name := LocalizedName.herb(
			ingredient.get_herb_id(),
			ingredient.get_herb_name()
		)

		parts.append(
			tr("UI_RECORDS_INGREDIENT_FMT") % [
				localized_herb_name,
				ingredient.get_amount_text()
			]
		)

	return tr("UI_RESULT_UNLOCK_SEPARATOR").join(parts) if not parts.is_empty() else tr("UI_RECORDS_NO_INGREDIENTS")
