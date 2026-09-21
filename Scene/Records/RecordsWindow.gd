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


func _ready() -> void:
	close_requested.connect(_on_close_requested)
	tabs.set_tab_title(0, "诊疗记录")
	tabs.set_tab_title(1, "账目明细")
	tabs.set_tab_title(2, "数据统计")
	tabs.set_tab_title(3, "预制方剂")
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
		treatment_detail.text = "[color=#c6ae83]尚无诊疗记录。完成一次诊疗后，这里会按天保存病人、疾病、标准方、断病和开方。[/color]"
		return
	treatment_day_list.select(treatment_days.size() - 1)
	_show_treatment_day(treatment_days.back())


func _on_treatment_day_selected(index: int) -> void:
	if index >= 0 and index < treatment_days.size():
		_show_treatment_day(treatment_days[index])


func _show_treatment_day(day: int) -> void:
	var records: Array[Dictionary] = Records.get_treatment_records(day)
	var lines: Array[String] = ["[font_size=24][color=#e3b66b]%s · 诊疗记录[/color][/font_size]" % _format_record_date(day)]
	if records.is_empty():
		lines.append("\n[color=#c6ae83]本日暂无记录。[/color]")
	else:
		for index in range(records.size()):
			var record: Dictionary = records[index]
			var status := "成功" if bool(record.get("success", false)) else "未愈"
			var grade := _record_text(record, "grade", "")
			lines.append("\n%d. [font_size=22][color=#fff1c7]%s[/color][/font_size]  %s  ·  %s" % [
				index + 1,
				_record_text(record, "patient_name", "未知病人"),
				status,
				grade
			])
			lines.append("病人疾病：[color=#e3d1aa]%s[/color]" % _record_text(record, "disease_name", "未记录"))
			lines.append("标准方：[color=#e3d1aa]%s[/color]" % _record_text(record, "standard_formula_name", "未记录"))
			lines.append("断病：[color=#e3d1aa]%s[/color]" % _record_text(record, "diagnosis", "未记录"))
			lines.append("开方：[color=#e3d1aa]%s[/color]" % _record_text(record, "prescription", "（空方）").replace("\n", "；"))
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
		finance_detail.text = "[color=#c6ae83]账目自%s开始记录。[/color]" % _format_record_date(FINANCE_START_DAY)
		return
	finance_day_list.select(finance_days.size() - 1)
	_show_finance_day(finance_days.back())


func _on_finance_day_selected(index: int) -> void:
	if index >= 0 and index < finance_days.size():
		_show_finance_day(finance_days[index])


func _show_finance_day(day: int) -> void:
	if day < FINANCE_START_DAY:
		finance_detail.text = "[color=#c6ae83]账目自%s开始记录。[/color]" % _format_record_date(FINANCE_START_DAY)
		return
	var report: Dictionary = Unlock.get_finance_detail_for_day(day) if Unlock != null and Unlock.has_method("get_finance_detail_for_day") else {}
	if report.is_empty():
		finance_detail.text = "[color=#c6ae83]%s暂无账目数据。[/color]" % _format_record_date(day)
		return

	var settled := bool(report.get("settled", false))
	var lines: Array[String] = ["[font_size=24][color=#e3b66b]%s · 账目明细[/color][/font_size]" % _format_record_date(day)]
	if not settled:
		lines.append("[color=#c6ae83]本日尚未结算，支出将在进入夜晚时生成。[/color]")
	lines.append("\n[b]收入[/b]")
	_append_money_line(lines, "诊费", int(report.get("consultation_income_wen", 0)), true)
	_append_money_line(lines, "药材收入", int(report.get("medicine_income_wen", 0)), true)
	_append_money_line(lines, "病家谢礼", int(report.get("patient_thank_gift_income_wen", 0)), true)
	_append_money_line(lines, "李建中俸禄", int(report.get("li_jian_zhong_salary_wen", 0)), true)
	_append_money_line(lines, "李言闻收入", int(report.get("li_yan_wen_income_wen", 0)), true)
	_append_money_line(lines, "田租", int(report.get("land_rent_wen", 0)), true)
	lines.append("收入合计：[color=#9fe29f]%s[/color]" % _format_money(int(report.get("total_income_wen", 0))))
	lines.append("\n[b]支出[/b]")
	_append_money_line(lines, "陈皮半夏工钱", -int(report.get("staff_wage_wen", 0)), false)
	_append_money_line(lines, "食物", -int(report.get("food_cost_wen", 0)), false)
	_append_money_line(lines, "人情随礼", -int(report.get("human_gift_cost_wen", 0)), false)
	_append_money_line(lines, "购买医书", -int(report.get("medical_book_cost_wen", 0)), false)
	_append_money_line(lines, "煤炭", -int(report.get("coal_cost_wen", 0)), false)
	_append_money_line(lines, "布匹棉衣", -int(report.get("clothing_cost_wen", 0)), false)
	_append_money_line(lines, "修缮房屋", -int(report.get("house_repair_cost_wen", 0)), false)
	_append_money_line(lines, "扫墓祭祖", -int(report.get("ancestor_worship_cost_wen", 0)), false)
	_append_money_line(lines, "药材发霉", -int(report.get("moldy_herb_cost_wen", 0)), false)
	_append_money_line(lines, "夏税", -int(report.get("summer_tax_wen", 0)), false)
	_append_money_line(lines, "秋税", -int(report.get("autumn_tax_wen", 0)), false)
	lines.append("支出合计：[color=#f0a0a0]%s[/color]" % _format_money(-int(report.get("total_expense_wen", 0))))
	lines.append("\n本日变化：[color=#e3b66b]%s[/color]" % _format_money(int(report.get("net_change_wen", 0))))
	finance_detail.text = "\n".join(lines)


func _append_money_line(lines: Array[String], label: String, amount: int, positive: bool) -> void:
	if amount == 0:
		return
	var color := "#9fe29f" if positive else "#f0a0a0"
	lines.append("%s：[color=%s]%s[/color]" % [label, color, _format_money(amount)])


func _format_money(amount: int) -> String:
	var sign := "+" if amount > 0 else ("-" if amount < 0 else "")
	var absolute := absi(amount)
	return "%s%d两%d文" % [sign, absolute / 1000, absolute % 1000]


func _format_money_without_positive_sign(amount: int) -> String:
	var sign := "-" if amount < 0 else ""
	var absolute := absi(amount)
	return "%s%d两%d文" % [sign, absolute / 1000, absolute % 1000]


func _format_record_date(day: int) -> String:
	if GameTime != null and GameTime.has_method("get_day_text_by_index"):
		return str(GameTime.get_day_text_by_index(day))
	return "日期未载"


func _refresh_stats() -> void:
	var stats: Dictionary = Records.get_statistics() if Records != null else {}
	total_patients_value.text = "%d 人" % int(stats.get("total_patients", 0))
	successful_patients_value.text = "%d 人" % int(stats.get("successful_patients", 0))
	miaoshou_patients_value.text = "%d 人" % int(stats.get("miaoshou_patients", 0))
	failed_patients_value.text = "%d 人" % int(stats.get("failed_patients", 0))
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
		preset_list.add_item("%s  [%d/5]%s" % [formula.formula_name, count, "  · 已解锁" if unlocked else ""])
	if preset_formulas.is_empty():
		preset_detail.text = "[color=#c6ae83]暂无方剂数据。[/color]"
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
	var status := "已解锁：可在开方时一键使用" if unlocked else "未解锁：该方剂获得 5 次妙手回春后解锁"
	var lines: Array[String] = [
		"[font_size=26][color=#e3b66b]%s[/color][/font_size]" % formula.formula_name,
		"\n掌握次数：%d / 5" % count,
		"状态：[color=%s]%s[/color]" % ["#9fe29f" if unlocked else "#c6ae83", status],
		"\n标准方组成：",
		"[color=#e3d1aa]%s[/color]" % _formula_ingredients_text(formula)
	]
	preset_detail.text = "\n".join(lines)


func _formula_ingredients_text(formula: FormulaData) -> String:
	var parts: Array[String] = []
	for ingredient in formula.get_all_ingredients():
		if ingredient == null:
			continue
		parts.append("%s（%s）" % [ingredient.get_herb_name(), ingredient.get_display_text()])
	return "、".join(parts) if not parts.is_empty() else "（暂无组成数据）"
