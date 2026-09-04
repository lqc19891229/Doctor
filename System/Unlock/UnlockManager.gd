extends Node
class_name UnlockManager

# 顶部栏使用这些信号按需刷新，避免 Clinic / Night 每帧轮询数值。
signal experience_points_changed(value: int)
signal reputation_points_changed(value: int)
signal money_wen_changed(value: int)

# =========================================================
# 解锁管理器
#
# 当前规则：
# - 心得点数改为“累计值”，不再作为读书消耗货币
# - BookEntryData.unlock_required_experience_points 控制条目自动解锁阈值
# - Herb / Theory 条目继续由累计心得与 unlock_required_experience_points 自动解锁
# - required_herb_ids / prerequisite_entry_ids 不参与 ReadBook 解锁判断
# - Herb 条目：条目已解锁后，可查看，首次查看后记为已读并同步解锁对应药材
# - Formula：方剂所含全部药材都已解锁时，自动解锁方剂及其医书条目
# - Disease：疾病的标准方（recommended_formula_id）已解锁时，自动解锁疾病及其医书条目
# - Formula / Disease 条目首次查看时只标记已读；实体可能已由依赖条件提前解锁
# - Theory 条目：条目已解锁后，可阅读，阅读后只标记已读
# - 行医记考（clinical_log）显示已同步解锁的实体内容
# - 名望点数同样作为累计值，用于剧情解锁和节奏控制
# - 剧情解锁条件写在 StoryData / 剧情 .tres 中，不再写死在 UnlockManager
# - StoryData.unlock_entry_id 现在表示剧情触发前置医书条目 ID
# - UnlockManager 不再因为剧情名望解锁而自动解锁 unlock_entry_id 对应条目
#
# 注意：
# - “解锁”和“已读”分开记录
# - unlocked_entry_ids：条目已解锁，可在读书界面显示/查看
# - read_entry_ids：条目已阅读/查看过
# - Herb 条目首次查看后会同步解锁药材，并记入 read_entry_ids 用于未读提示
# - Formula / Disease / Theory 条目在首次阅读后会记为已读
# - Formula / Disease 实体按依赖关系自动解锁，阅读时再次同步状态以兼容旧存档
# - Theory 阅读后只标记已读，不解锁任何实体
# - 所有实体一旦解锁，会同步进入 clinical_log
# =========================================================


# =========================================================
# 一、条目阅读状态
# =========================================================

var read_entry_ids: Dictionary = {}
var unlocked_entry_ids: Dictionary = {}


# =========================================================
# 二、实体解锁状态
# =========================================================

var unlocked_herb_ids: Dictionary = {}
var unlocked_disease_ids: Dictionary = {}
var unlocked_formula_ids: Dictionary = {}


# =========================================================
# 三、行医记考可见状态
# =========================================================

var clinical_log_unlocked_herb_ids: Dictionary = {}
var clinical_log_unlocked_disease_ids: Dictionary = {}
var clinical_log_unlocked_formula_ids: Dictionary = {}

# 防止“药材 -> 方剂 -> 疾病”级联刷新时重复进入。
var _is_refreshing_dependency_unlocks: bool = false

# =========================================================
# 运行时索引 / 缓存
# =========================================================
# 这些索引只描述静态 Data 资源之间的关系，不写入存档。
# 目的：避免每次解锁药材 / 方剂时重新遍历全部方剂、疾病和 200+ 医书条目。
var _unlock_indexes_ready: bool = false

var _formula_by_id: Dictionary = {}
var _formula_ids_by_herb_id: Dictionary = {}

var _disease_by_id: Dictionary = {}
var _disease_ids_by_formula_id: Dictionary = {}

var _book_entry_ids_by_herb_id: Dictionary = {}
var _book_entry_ids_by_formula_id: Dictionary = {}
var _book_entry_ids_by_disease_id: Dictionary = {}

# 只保存按心得门槛自动解锁的 Herb / Theory 条目，按门槛升序排列。
var _experience_unlock_entries: Array[BookEntryData] = []
var _experience_unlock_cursor: int = 0

# 夜晚“是否存在未读可阅读条目”改为 O(1)。
# 正常运行时由 unlock_entry / mark_entry_as_read 增量维护；
# 读档后统一重建一次，兼容旧存档。
var _unread_readable_count: int = 0
var _unread_readable_count_ready: bool = false

# ReadBook UI 只需要知道“医书可见/未读状态是否变化”，不需要每次打开都全量重算。
# 这个版本号只存在于运行时，不写入存档。
var _readbook_state_version: int = 0


func get_readbook_state_version() -> int:
	return _readbook_state_version


func _touch_readbook_state() -> void:
	_readbook_state_version += 1


func _emit_all_player_stat_signals() -> void:
	experience_points_changed.emit(experience_points)
	reputation_points_changed.emit(reputation_points)
	money_wen_changed.emit(money_wen)


func _ready() -> void:
	_ensure_unlock_indexes()
	_rebuild_unread_readable_count()


# =========================================================
# 四、静态依赖索引
# =========================================================

func _ensure_unlock_indexes() -> void:
	if _unlock_indexes_ready:
		return

	if BookEntryDB == null or FormulaDB == null or DiseaseDB == null:
		return

	if (
		not BookEntryDB.has_method("get_all_entries")
		or not FormulaDB.has_method("get_all_formulas")
		or not DiseaseDB.has_method("get_all_diseases")
	):
		return

	_build_unlock_indexes()


func _build_unlock_indexes() -> void:
	_formula_by_id.clear()
	_formula_ids_by_herb_id.clear()
	_disease_by_id.clear()
	_disease_ids_by_formula_id.clear()
	_book_entry_ids_by_herb_id.clear()
	_book_entry_ids_by_formula_id.clear()
	_book_entry_ids_by_disease_id.clear()
	_experience_unlock_entries.clear()

	var started_usec := Time.get_ticks_usec()

	var all_formulas: Array[FormulaData] = FormulaDB.get_all_formulas()
	for formula in all_formulas:
		if formula == null:
			continue

		var formula_id := formula.formula_id.strip_edges()
		if formula_id == "":
			continue

		_formula_by_id[formula_id] = formula

		for herb_id in formula.get_all_herb_ids():
			var clean_herb_id := herb_id.strip_edges()
			if clean_herb_id == "":
				continue
			_append_unique_index_value(_formula_ids_by_herb_id, clean_herb_id, formula_id)

	var all_diseases: Array[DiseaseData] = DiseaseDB.get_all_diseases()
	for disease in all_diseases:
		if disease == null:
			continue

		var disease_id := disease.disease_id.strip_edges()
		if disease_id == "":
			continue

		_disease_by_id[disease_id] = disease

		var formula_id := disease.recommended_formula_id.strip_edges()
		if formula_id != "":
			_append_unique_index_value(_disease_ids_by_formula_id, formula_id, disease_id)

	var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()
	for entry in all_entries:
		if entry == null:
			continue

		if entry is HerbBookEntryData:
			var herb_entry := entry as HerbBookEntryData
			var herb_id := herb_entry.herb_id.strip_edges()
			if herb_id != "":
				_append_unique_index_value(
					_book_entry_ids_by_herb_id,
					herb_id,
					herb_entry.entry_id.strip_edges()
				)

		elif entry is FormulaBookEntryData:
			var formula_entry := entry as FormulaBookEntryData
			var formula_id := formula_entry.formula_id.strip_edges()
			if formula_id != "":
				_append_unique_index_value(
					_book_entry_ids_by_formula_id,
					formula_id,
					formula_entry.entry_id.strip_edges()
				)

		elif entry is DiseaseBookEntryData:
			var disease_entry := entry as DiseaseBookEntryData
			var disease_id := disease_entry.disease_id.strip_edges()
			if disease_id != "":
				_append_unique_index_value(
					_book_entry_ids_by_disease_id,
					disease_id,
					disease_entry.entry_id.strip_edges()
				)

		# Formula / Disease 不按心得门槛自动解锁。
		if not (entry is FormulaBookEntryData or entry is DiseaseBookEntryData):
			if _get_entry_required_experience_points(entry) >= 0:
				_experience_unlock_entries.append(entry)

	_experience_unlock_entries.sort_custom(Callable(self, "_experience_entry_sort_before"))
	_experience_unlock_cursor = 0
	_unlock_indexes_ready = true

	if OS.is_debug_build():
		var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
		print(
			"[UnlockManager] 解锁索引完成：方剂=",
			_formula_by_id.size(),
			"，疾病=",
			_disease_by_id.size(),
			"，心得条目=",
			_experience_unlock_entries.size(),
			"，耗时 ",
			"%.2f" % elapsed_ms,
			" ms"
		)


func _append_unique_index_value(index: Dictionary, key: String, value: String) -> void:
	if key == "" or value == "":
		return

	var values: Array = index.get(key, [])
	if not values.has(value):
		values.append(value)
		index[key] = values


func _experience_entry_sort_before(a: BookEntryData, b: BookEntryData) -> bool:
	var a_points := _get_entry_required_experience_points(a)
	var b_points := _get_entry_required_experience_points(b)

	if a_points != b_points:
		return a_points < b_points

	return a.entry_id.strip_edges() < b.entry_id.strip_edges()


func _get_index_values(index: Dictionary, key: String) -> Array:
	var clean_key := key.strip_edges()
	if clean_key == "":
		return []

	var values = index.get(clean_key, [])
	if typeof(values) != TYPE_ARRAY:
		return []

	return values


# =========================================================
# 五、心得点数（累计值）
# =========================================================

var experience_points: int = 0


func get_experience_points() -> int:
	return experience_points


# 改变累计心得。
# - 正数：增加心得，并检查是否有新达到门槛的医书条目。
# - 负数：扣除心得，但最低保持为 0；已经解锁的条目不会被锁回。
# - 0：不做任何处理。
#
# 返回值：
# - 仅在增加心得时，返回本次新解锁的医书条目标题。
# - 扣除心得或变化量为 0 时，返回空数组。
func change_experience_points(amount: int) -> Array[String]:
	if amount == 0:
		return []

	var previous_points := experience_points
	experience_points = maxi(0, experience_points + amount)

	if experience_points != previous_points:
		experience_points_changed.emit(experience_points)

	if amount > 0:
		return refresh_auto_unlocks_by_experience()

	return []


func add_experience_point(amount: int = 1) -> Array[String]:
	if amount <= 0:
		return []

	return change_experience_points(amount)


# =========================================================
# 六、名望点数（累计值）
# 用于剧情解锁和节奏控制
# =========================================================

var reputation_points: int = 0


# =========================================================
# 七、银钱系统（第一版）
# =========================================================
# 内部统一使用“文”记账，TopBar 再换算成“两 + 文”显示。
# 第一版暂定：
# - 1 两 = 1000 文
# - random NPC 诊费 = 500 文 / 人
# - 陈皮工钱 = 500 文 / 2 个节气
# - 半夏工钱 = 500 文 / 2 个节气
# - 食费 = 2000 文 / 2 个节气
#
# 如果后续要调整平衡，只需改下面常量即可。
const WEN_PER_LIANG: int = 1000
const STARTING_MONEY_WEN: int = 0
const RANDOM_NPC_CONSULTATION_FEE_WEN: int = 500
const CHEN_PI_WAGE_PER_SOLAR_TERM_WEN: int = 500
const BAN_XIA_WAGE_PER_SOLAR_TERM_WEN: int = 500
const WAGE_INTERVAL_SOLAR_TERMS: int = 2
const FOOD_COST_WEN: int = 2000
const FOOD_COST_INTERVAL_SOLAR_TERMS: int = 2

# 当前持有银钱，单位：文。
# 允许出现负数；负数在 TopBar 中显示为“欠 X两 Y文”。
var money_wen: int = STARTING_MONEY_WEN

# 当前白天账本。
const FINANCE_ACCOUNTING_VERSION_GROSS: int = 2

var finance_ledger_day: int = 1
# 2 = 当前“销售额 / 进货成本”分开记账。
# 1 = 旧版“药材利润 + 失败成本”账本，仅用于兼容旧存档的当前未结算日。
var finance_ledger_accounting_version: int = FINANCE_ACCOUNTING_VERSION_GROSS

var daily_random_npc_count: int = 0
var daily_consultation_income_wen: int = 0

# 当前正式账本：
# 成功治疗时 medicine_sales 记实际售价总和；
# 无论成功或失败，medicine_purchase_cost 都记本张处方的进货成本。
var daily_medicine_sales_wen: int = 0
var daily_medicine_purchase_cost_wen: int = 0

# 旧存档兼容字段。新账本不再使用它们进行正式结算。
var daily_medicine_profit_wen: int = 0
var daily_failed_medicine_cost_wen: int = 0

# 最近一次已经完成夜间结算的天数。
# 用于防止切场景 / 读档时重复扣工钱和食费。
var last_finance_settled_day: int = 0
var last_finance_report: Dictionary = {}


func get_money_wen() -> int:
	return money_wen


func get_random_npc_consultation_fee_wen() -> int:
	return RANDOM_NPC_CONSULTATION_FEE_WEN


func format_money(amount_wen: int) -> String:
	var absolute_amount: int = absi(amount_wen)
	var liang: int = absolute_amount / WEN_PER_LIANG
	var wen: int = absolute_amount % WEN_PER_LIANG

	# 金额显示时省略数值为 0 的单位：
	# 500 文 -> 500文
	# 2000 文 -> 2两
	# 2474 文 -> 2两 474文
	# 0 文 -> 0文
	var parts: Array[String] = []
	if liang > 0:
		parts.append("%d两" % liang)
	if wen > 0:
		parts.append("%d文" % wen)
	if parts.is_empty():
		parts.append("0文")

	var text := " ".join(parts)

	if amount_wen < 0:
		return "欠 " + text

	return text


func format_money_change(amount_wen: int) -> String:
	if amount_wen > 0:
		return "+" + format_money(amount_wen)
	if amount_wen < 0:
		return "-" + format_money(-amount_wen)
	return "0文"


func _reset_daily_finance_ledger(day: int) -> void:
	finance_ledger_day = maxi(day, 1)
	finance_ledger_accounting_version = FINANCE_ACCOUNTING_VERSION_GROSS
	daily_random_npc_count = 0
	daily_consultation_income_wen = 0
	daily_medicine_sales_wen = 0
	daily_medicine_purchase_cost_wen = 0
	daily_medicine_profit_wen = 0
	daily_failed_medicine_cost_wen = 0


func _ensure_daily_finance_ledger(day: int) -> void:
	var safe_day := maxi(day, 1)
	if finance_ledger_day == safe_day:
		return

	_reset_daily_finance_ledger(safe_day)


# 每名 random NPC 第一次提交处方时调用一次。
#
# treatment_success:
# - true：妙手回春 / 治疗成功，药材售价总和计入收入。
# - false：治疗失败，药材销售收入为 0。
#
# prescription_sell_wen：本张处方按售价计算出的总和。
# prescription_cost_wen：本张处方按进价计算出的总和。
#
# 无论成功还是失败，药材进货成本都会进入当天支出；
# 但仍延续现有规则，在“正常白天结束”时统一扣除。
func record_random_npc_treatment_finance(
	day: int,
	treatment_success: bool,
	prescription_sell_wen: int,
	prescription_cost_wen: int
) -> Dictionary:
	_ensure_daily_finance_ledger(day)

	var consultation_fee := RANDOM_NPC_CONSULTATION_FEE_WEN
	var medicine_sales := maxi(prescription_sell_wen, 0) if treatment_success else 0
	var medicine_purchase_cost := maxi(prescription_cost_wen, 0)

	daily_random_npc_count += 1
	daily_consultation_income_wen += consultation_fee

	# 新账本直接记录销售额和进货成本。
	if finance_ledger_accounting_version >= FINANCE_ACCOUNTING_VERSION_GROSS:
		daily_medicine_sales_wen += medicine_sales
		daily_medicine_purchase_cost_wen += medicine_purchase_cost

		# 白天实时入账收入；所有支出在正常白天结束时统一扣除。
		var total_income := consultation_fee + medicine_sales
		money_wen += total_income
		money_wen_changed.emit(money_wen)

		return {
			"consultation_fee_wen": consultation_fee,
			"medicine_sales_wen": medicine_sales,
			"medicine_purchase_cost_wen": medicine_purchase_cost,
			"total_income_wen": total_income,
			"money_wen": money_wen
		}

	# 兼容旧存档：旧版当前日无法从“利润”反推出此前所有处方的销售额和成本。
	# 因此只在这一未结算日继续沿用旧口径，下一天自动切换到新版总账。
	var legacy_profit := (medicine_sales - medicine_purchase_cost) if treatment_success else 0
	var legacy_failed_cost := 0 if treatment_success else medicine_purchase_cost
	daily_medicine_profit_wen += legacy_profit
	daily_failed_medicine_cost_wen += legacy_failed_cost

	var legacy_total_income := consultation_fee + legacy_profit
	money_wen += legacy_total_income
	money_wen_changed.emit(money_wen)

	return {
		"consultation_fee_wen": consultation_fee,
		"medicine_sales_wen": medicine_sales,
		"medicine_purchase_cost_wen": medicine_purchase_cost,
		"total_income_wen": legacy_total_income,
		"money_wen": money_wen
	}


# 兼容非常旧的调用入口。
# 旧接口只提供“利润”，无法拆出售价和成本，因此仍按旧账本口径处理。
func record_random_npc_treatment_income(day: int, prescription_profit_wen: int) -> Dictionary:
	_ensure_daily_finance_ledger(day)
	finance_ledger_accounting_version = 1

	var consultation_fee := RANDOM_NPC_CONSULTATION_FEE_WEN
	var total_income := consultation_fee + prescription_profit_wen

	daily_random_npc_count += 1
	daily_consultation_income_wen += consultation_fee
	daily_medicine_profit_wen += prescription_profit_wen
	money_wen += total_income
	money_wen_changed.emit(money_wen)

	return {
		"consultation_fee_wen": consultation_fee,
		"medicine_profit_wen": prescription_profit_wen,
		"total_income_wen": total_income,
		"money_wen": money_wen
	}


# 白天结束、进入 Night 之前调用。
# 收入已在白天接诊时实时入账；这里负责扣除固定支出并生成当日账单。
func settle_day_finances(day: int) -> Dictionary:
	var safe_day := maxi(day, 1)

	# 同一天已经结算过时直接返回原报告，绝不重复扣款。
	if last_finance_settled_day == safe_day and not last_finance_report.is_empty():
		return last_finance_report.duplicate(true)

	_ensure_daily_finance_ledger(safe_day)

	# 陈皮、半夏工钱都改为每两个节气支付一次。
	# 第 2、4、6……个节气支付；其它节气为 0，不显示也不扣款。
	var chen_pi_wage := 0
	var ban_xia_wage := 0
	if safe_day % WAGE_INTERVAL_SOLAR_TERMS == 0:
		chen_pi_wage = CHEN_PI_WAGE_PER_SOLAR_TERM_WEN
		ban_xia_wage = BAN_XIA_WAGE_PER_SOLAR_TERM_WEN

	var food_cost := 0
	if safe_day % FOOD_COST_INTERVAL_SOLAR_TERMS == 0:
		food_cost = FOOD_COST_WEN

	var is_gross_accounting := (
		finance_ledger_accounting_version >= FINANCE_ACCOUNTING_VERSION_GROSS
	)

	var medicine_sales := daily_medicine_sales_wen if is_gross_accounting else 0
	var medicine_purchase_cost := (
		daily_medicine_purchase_cost_wen
		if is_gross_accounting
		else daily_failed_medicine_cost_wen
	)

	var total_income := (
		daily_consultation_income_wen
		+ (
			medicine_sales
			if is_gross_accounting
			else daily_medicine_profit_wen
		)
	)

	var total_expense := (
		chen_pi_wage
		+ ban_xia_wage
		+ food_cost
		+ medicine_purchase_cost
	)
	var net_change := total_income - total_expense

	money_wen -= total_expense
	money_wen_changed.emit(money_wen)

	last_finance_settled_day = safe_day
	last_finance_report = {
		"day": safe_day,
		"accounting_version": finance_ledger_accounting_version,
		"random_npc_count": daily_random_npc_count,
		"consultation_income_wen": daily_consultation_income_wen,
		"medicine_sales_wen": medicine_sales,
		"medicine_purchase_cost_wen": medicine_purchase_cost,
		# 保留旧字段，便于旧代码/旧存档兼容。
		"medicine_profit_wen": daily_medicine_profit_wen,
		"failed_medicine_cost_wen": daily_failed_medicine_cost_wen,
		"total_income_wen": total_income,
		"chen_pi_wage_wen": chen_pi_wage,
		"ban_xia_wage_wen": ban_xia_wage,
		"food_cost_wen": food_cost,
		"total_expense_wen": total_expense,
		"net_change_wen": net_change,
		"money_after_wen": money_wen
	}

	return last_finance_report.duplicate(true)


func get_last_finance_report_for_day(day: int) -> Dictionary:
	if last_finance_settled_day != maxi(day, 1):
		return {}
	return last_finance_report.duplicate(true)


func build_finance_report_text(day: int) -> String:
	var report := get_last_finance_report_for_day(day)
	if report.is_empty():
		return ""

	var accounting_version := int(report.get("accounting_version", 1))
	var consultation_income := int(report.get("consultation_income_wen", 0))
	var total_income := int(report.get("total_income_wen", 0))
	var chen_pi_wage := int(report.get("chen_pi_wage_wen", 0))
	var ban_xia_wage := int(report.get("ban_xia_wage_wen", 0))
	var food_cost := int(report.get("food_cost_wen", 0))
	var total_expense := int(report.get("total_expense_wen", 0))
	var net_change := int(report.get("net_change_wen", 0))

	var lines: Array[String] = []
	lines.append("今日银钱结算")
	lines.append("")
	lines.append("收入")
	lines.append("诊费：%s" % format_money_change(consultation_income))

	if accounting_version >= FINANCE_ACCOUNTING_VERSION_GROSS:
		var medicine_sales := int(report.get("medicine_sales_wen", 0))
		lines.append("药材销售：%s" % format_money_change(medicine_sales))
	else:
		# 仅用于无法还原销售额/成本拆分的旧存档当天。
		var medicine_profit := int(report.get("medicine_profit_wen", 0))
		lines.append("药材利润（旧账）：%s" % format_money_change(medicine_profit))

	lines.append("收入合计：%s" % format_money_change(total_income))
	lines.append("")
	lines.append("支出")

	if accounting_version >= FINANCE_ACCOUNTING_VERSION_GROSS:
		var medicine_purchase_cost := int(report.get("medicine_purchase_cost_wen", 0))
		if medicine_purchase_cost > 0:
			lines.append("药材进货成本：%s" % format_money_change(-medicine_purchase_cost))
	else:
		var failed_medicine_cost := int(report.get("failed_medicine_cost_wen", 0))
		if failed_medicine_cost > 0:
			lines.append("治疗失败药材成本（旧账）：%s" % format_money_change(-failed_medicine_cost))

	if chen_pi_wage > 0:
		lines.append("陈皮工钱：%s" % format_money_change(-chen_pi_wage))
	if ban_xia_wage > 0:
		lines.append("半夏工钱：%s" % format_money_change(-ban_xia_wage))
	if food_cost > 0:
		lines.append("食费：%s" % format_money_change(-food_cost))
	lines.append("支出合计：%s" % format_money_change(-total_expense))
	lines.append("")
	lines.append("本日变化：%s" % format_money_change(net_change))
	return "\n".join(lines)


# =========================================================
# 七、名望剧情解锁状态
#
# 剧情解锁条件现在写在每个剧情 .tres 对应的 StoryData 里。
# UnlockManager 不再维护 const STORY_UNLOCKS。
#
# StoryData 里主要使用这些字段：
# - story_id：剧情唯一 ID，用来记录是否已解锁。
# - title：剧情标题，用于提示文本。
# - required_reputation_points：需要达到的累计名望。
# - unlock_entry_id：可选，剧情触发前必须已经解锁的医书条目 ID。
#
# 流程：
# 1. 玩家获得名望，调用 add_reputation_points()。
# 2. 本脚本调用 refresh_story_unlocks_by_reputation()。
# 3. refresh_story_unlocks_by_reputation() 从 StoryManager.get_all_stories() 读取所有剧情资源。
# 4. 达到名望条件的剧情写入 unlocked_story_ids。
# 5. unlock_entry_id 不在这里自动解锁，由 StoryManager 在触发剧情前判断是否已解锁。
# =========================================================

# 已经由名望触发过的剧情 ID。
# 用 Dictionary 是为了快速判断，并且方便直接存档。
var unlocked_story_ids: Dictionary = {}


func get_reputation_points() -> int:
	return reputation_points


# 增加名望。
#
# 返回值：
# - 返回本次因为名望提升而“新解锁”的剧情数据列表。
# - 旧代码如果只是调用 Unlock.add_reputation_points(x)，不接返回值，也不会出错。
#
# 例：
# var newly_unlocked_stories := Unlock.add_reputation_points(5)
# if not newly_unlocked_stories.is_empty():
#     显示“新剧情解锁”提示
func add_reputation_points(amount: int = 1) -> Array[Dictionary]:
	if amount == 0:
		return []

	reputation_points += amount
	reputation_points_changed.emit(reputation_points)
	return refresh_story_unlocks_by_reputation()


func has_reputation_points(required_amount: int) -> bool:
	return reputation_points >= required_amount


# 判断某个剧情是否已经通过名望系统解锁。
# 注意：
# - 这里的“解锁”不是“已经播放”。
# - 是否已经播放，仍建议交给 StoryManager / played_story_ids 管理。
func is_story_unlocked(story_id: String) -> bool:
	var id := story_id.strip_edges()
	if id == "":
		return false

	return unlocked_story_ids.has(id)


# 手动解锁一个剧情。
#
# 返回值：
# - true：本次确实新增了解锁记录
# - false：ID 为空，或之前已经解锁过
func unlock_story(story_id: String) -> bool:
	var id := story_id.strip_edges()
	if id == "":
		return false

	if unlocked_story_ids.has(id):
		return false

	unlocked_story_ids[id] = true
	return true


# 根据当前累计名望检查所有 StoryData 剧情资源。
#
# 这个函数可以被多处安全调用：
# - 加名望后调用
# - 读档后调用
# - 调试时手动调用
#
# 因为它会先检查 unlocked_story_ids，所以不会重复解锁、重复返回。
func refresh_story_unlocks_by_reputation() -> Array[Dictionary]:
	var newly_unlocked: Array[Dictionary] = []

	# 剧情资源统一由 StoryManager 自动扫描 res://Data/Story。
	# 如果 StoryManager 还没准备好，直接返回空数组，避免报错。
	if StoryManager == null:
		return newly_unlocked

	if not StoryManager.has_method("get_all_stories"):
		push_warning("StoryManager 缺少 get_all_stories()，无法按名望解锁剧情。")
		return newly_unlocked

	var all_stories: Array[StoryData] = StoryManager.get_all_stories()

	for story in all_stories:
		if story == null:
			continue

		var story_id := story.story_id.strip_edges()
		if story_id == "":
			continue

		# 两种 day_reputation_*_over 都在进入场景时检查“当前天数 + 当前名望”，
		# 不写入永久解锁记录，也不显示普通的“新剧情解锁”提示。
		# 这样即使名望之后下降，也不会因为曾经解锁过而错误触发终局。
		var trigger_type := story.trigger_type.strip_edges().to_lower()
		if (
			trigger_type == StoryData.TRIGGER_TYPE_DAY_REPUTATION_OVER
			or trigger_type == StoryData.TRIGGER_TYPE_DAY_REPUTATION_BELOW_OVER
		):
			continue

		# 已解锁过的剧情不重复解锁，也不会重复返回提示。
		if is_story_unlocked(story_id):
			continue

		# required_reputation_points <= 0 表示不需要名望解锁。
		# 这种剧情继续交给 StoryManager 按场景 / 播放状态处理，
		# UnlockManager 不主动写入 unlocked_story_ids。
		var required_points := int(story.required_reputation_points)
		if required_points <= 0:
			continue

		# 名望不足，不解锁。
		if reputation_points < required_points:
			continue

		# 写入 unlocked_story_ids。
		if not unlock_story(story_id):
			continue

		# unlock_entry_id 现在是剧情触发前置条件，不在这里自动解锁条目。
		# 返回给调用处的数据，方便 Clinic / PlayerHintWindow 显示“新剧情解锁”。
		# - story_id：剧情唯一 ID，也作为当前提示显示名。
		newly_unlocked.append({
			"story_id": story_id,
			"title": story_id,
			"required_reputation_points": required_points,
			"entry_id": story.unlock_entry_id.strip_edges()
		})

	return newly_unlocked

# =========================================================
# 七、心得自动解锁条目
# =========================================================

func refresh_auto_unlocks_by_experience() -> Array[String]:
	var newly_unlocked_titles: Array[String] = []

	_ensure_unlock_indexes()

	# 索引尚未准备好时保留旧逻辑兜底，避免 Autoload 初始化顺序导致功能失效。
	if not _unlock_indexes_ready:
		if BookEntryDB == null:
			return newly_unlocked_titles

		var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()
		for entry in all_entries:
			if entry == null:
				continue
			if entry is FormulaBookEntryData or entry is DiseaseBookEntryData:
				continue
			if is_entry_unlocked(entry.entry_id):
				continue
			if not can_unlock_entry(entry):
				continue

			unlock_entry(entry.entry_id)
			var title := entry.title.strip_edges()
			if title == "":
				title = entry.entry_id
			newly_unlocked_titles.append(title)

		return newly_unlocked_titles

	# experience_points 只作为累计门槛；已经越过的索引不需要再次从头检查。
	while _experience_unlock_cursor < _experience_unlock_entries.size():
		var entry := _experience_unlock_entries[_experience_unlock_cursor]
		if entry == null:
			_experience_unlock_cursor += 1
			continue

		var required_points := _get_entry_required_experience_points(entry)
		if required_points > experience_points:
			break

		_experience_unlock_cursor += 1

		if is_entry_unlocked(entry.entry_id):
			continue

		unlock_entry(entry.entry_id)

		var title := entry.title.strip_edges()
		if title == "":
			title = entry.entry_id
		newly_unlocked_titles.append(title)

	return newly_unlocked_titles

func _get_entry_required_experience_points(entry: BookEntryData) -> int:
	if entry == null:
		return -1

	var value = entry.get("unlock_required_experience_points")
	if value == null:
		return -1

	return int(value)


# 判断条目是否满足“心得自动解锁”条件
# 规则：
# - unlock_required_experience_points < 0：不参与心得自动解锁
# - unlock_required_experience_points >= 0：累计心得达到该值后解锁
# - required_herb_ids / prerequisite_entry_ids 不参与判断
func can_unlock_entry(entry: BookEntryData) -> bool:
	if entry == null:
		return false

	# 方剂 / 疾病条目改由实体依赖关系解锁，不再接受心得门槛。
	if entry is FormulaBookEntryData or entry is DiseaseBookEntryData:
		return false

	var required_points := _get_entry_required_experience_points(entry)
	if required_points < 0:
		return false

	return experience_points >= required_points


func unlock_entry(entry_id: String) -> void:
	var id := entry_id.strip_edges()
	if id == "":
		return

	if unlocked_entry_ids.has(id):
		return

	var was_readable := false
	if _unread_readable_count_ready and not is_entry_read(id):
		was_readable = can_read_entry(id)

	unlocked_entry_ids[id] = true
	_touch_readbook_state()

	if (
		_unread_readable_count_ready
		and not is_entry_read(id)
		and not was_readable
		and can_read_entry(id)
	):
		_unread_readable_count += 1


func is_entry_unlocked(entry_id: String) -> bool:
	return unlocked_entry_ids.has(entry_id.strip_edges())


# =========================================================
# 七、基础状态函数
# =========================================================

func is_entry_read(entry_id: String) -> bool:
	return read_entry_ids.has(entry_id.strip_edges())


func mark_entry_as_read(entry_id: String) -> void:
	var id := entry_id.strip_edges()
	if id == "":
		return

	if read_entry_ids.has(id):
		return

	if _unread_readable_count_ready and can_read_entry(id):
		_unread_readable_count = maxi(0, _unread_readable_count - 1)

	read_entry_ids[id] = true
	_touch_readbook_state()


func unlock_herb(herb_id: String) -> void:
	var id := herb_id.strip_edges()
	if id == "":
		return

	var was_unlocked := unlocked_herb_ids.has(id)
	if was_unlocked:
		clinical_log_unlocked_herb_ids[id] = true
		return

	_ensure_unlock_indexes()

	# 兼容旧规则：药材实体本身也可能让 Herb 条目变得可读。
	var herb_entry_was_readable: Dictionary = {}
	if _unread_readable_count_ready:
		for entry_id in _get_index_values(_book_entry_ids_by_herb_id, id):
			var clean_entry_id := String(entry_id).strip_edges()
			if clean_entry_id == "" or is_entry_read(clean_entry_id):
				continue
			herb_entry_was_readable[clean_entry_id] = can_read_entry(clean_entry_id)

	unlocked_herb_ids[id] = true
	clinical_log_unlocked_herb_ids[id] = true
	_touch_readbook_state()

	# 只检查“包含这味新药材”的方剂，不再扫描全部方剂。
	_refresh_formulas_affected_by_herb(id)

	if _unread_readable_count_ready:
		for entry_id in herb_entry_was_readable.keys():
			var clean_entry_id := String(entry_id)
			if (
				not bool(herb_entry_was_readable[entry_id])
				and not is_entry_read(clean_entry_id)
				and can_read_entry(clean_entry_id)
			):
				_unread_readable_count += 1


func unlock_disease(disease_id: String) -> void:
	var id := disease_id.strip_edges()
	if id == "":
		return

	var was_unlocked := unlocked_disease_ids.has(id)
	if was_unlocked:
		clinical_log_unlocked_disease_ids[id] = true
		_unlock_matching_book_entries("disease", id)
		return

	_ensure_unlock_indexes()

	# 旧存档可能出现“条目已解锁、疾病实体未解锁”，记录其可读性变化。
	var preexisting_entry_was_readable: Dictionary = {}
	if _unread_readable_count_ready:
		for entry_id in _get_index_values(_book_entry_ids_by_disease_id, id):
			var clean_entry_id := String(entry_id).strip_edges()
			if (
				clean_entry_id != ""
				and is_entry_unlocked(clean_entry_id)
				and not is_entry_read(clean_entry_id)
			):
				preexisting_entry_was_readable[clean_entry_id] = can_read_entry(clean_entry_id)

	unlocked_disease_ids[id] = true
	clinical_log_unlocked_disease_ids[id] = true
	_touch_readbook_state()
	_unlock_matching_book_entries("disease", id)

	_update_preexisting_entry_readability(preexisting_entry_was_readable)


func unlock_formula(formula_id: String) -> void:
	var id := formula_id.strip_edges()
	if id == "":
		return

	var was_unlocked := unlocked_formula_ids.has(id)
	if was_unlocked:
		clinical_log_unlocked_formula_ids[id] = true
		_unlock_matching_book_entries("formula", id)
		return

	_ensure_unlock_indexes()

	# 旧存档可能出现“条目已解锁、方剂实体未解锁”，记录其可读性变化。
	var preexisting_entry_was_readable: Dictionary = {}
	if _unread_readable_count_ready:
		for entry_id in _get_index_values(_book_entry_ids_by_formula_id, id):
			var clean_entry_id := String(entry_id).strip_edges()
			if (
				clean_entry_id != ""
				and is_entry_unlocked(clean_entry_id)
				and not is_entry_read(clean_entry_id)
			):
				preexisting_entry_was_readable[clean_entry_id] = can_read_entry(clean_entry_id)

	unlocked_formula_ids[id] = true
	clinical_log_unlocked_formula_ids[id] = true
	_touch_readbook_state()
	_unlock_matching_book_entries("formula", id)

	_update_preexisting_entry_readability(preexisting_entry_was_readable)

	# 只检查以这个新方剂为标准方的疾病。
	# 全量修复 refresh_unlocks_by_dependencies() 自己会统一处理疾病，
	# 这里跳过可保持其返回的 disease_ids 语义与旧版一致。
	if not _is_refreshing_dependency_unlocks:
		_refresh_diseases_affected_by_formula(id)


func _update_preexisting_entry_readability(before_state: Dictionary) -> void:
	if not _unread_readable_count_ready:
		return

	for entry_id in before_state.keys():
		var clean_entry_id := String(entry_id).strip_edges()
		if clean_entry_id == "" or is_entry_read(clean_entry_id):
			continue

		if not bool(before_state[entry_id]) and can_read_entry(clean_entry_id):
			_unread_readable_count += 1


# 根据实体 ID 同步解锁对应医书条目，但不自动标记为已读。
# 这样新解锁内容仍会在读书界面显示【新】，并保留夜间未读限制。
func _unlock_matching_book_entries(entry_type: String, entity_id: String) -> void:
	var clean_id := entity_id.strip_edges()
	if clean_id == "":
		return

	_ensure_unlock_indexes()

	# 索引未准备好时保留旧逻辑兜底。
	if not _unlock_indexes_ready:
		if BookEntryDB == null:
			return

		var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()
		for entry in all_entries:
			if entry == null:
				continue

			if entry_type == "formula" and entry is FormulaBookEntryData:
				var formula_entry := entry as FormulaBookEntryData
				if formula_entry.formula_id.strip_edges() == clean_id:
					unlock_entry(formula_entry.entry_id)
				continue

			if entry_type == "disease" and entry is DiseaseBookEntryData:
				var disease_entry := entry as DiseaseBookEntryData
				if disease_entry.disease_id.strip_edges() == clean_id:
					unlock_entry(disease_entry.entry_id)
		return

	var index: Dictionary = {}
	match entry_type:
		"formula":
			index = _book_entry_ids_by_formula_id
		"disease":
			index = _book_entry_ids_by_disease_id
		_:
			return

	for entry_id in _get_index_values(index, clean_id):
		unlock_entry(String(entry_id))

# 方剂满足条件：君、臣、佐、使中包含的每一味药材都已经解锁。
func _are_all_formula_herbs_unlocked(formula: FormulaData) -> bool:
	if formula == null:
		return false

	var herb_ids: Array[String] = formula.get_all_herb_ids()
	if herb_ids.is_empty():
		return false

	for herb_id in herb_ids:
		var clean_herb_id := herb_id.strip_edges()
		if clean_herb_id == "" or not is_herb_unlocked(clean_herb_id):
			return false

	return true


func _refresh_formulas_affected_by_herb(herb_id: String) -> void:
	_ensure_unlock_indexes()
	if not _unlock_indexes_ready:
		refresh_unlocks_by_dependencies()
		return

	for formula_id_value in _get_index_values(_formula_ids_by_herb_id, herb_id):
		var formula_id := String(formula_id_value).strip_edges()
		if formula_id == "":
			continue

		if is_formula_unlocked(formula_id):
			clinical_log_unlocked_formula_ids[formula_id] = true
			_unlock_matching_book_entries("formula", formula_id)
			continue

		var formula = _formula_by_id.get(formula_id)
		if formula is FormulaData and _are_all_formula_herbs_unlocked(formula as FormulaData):
			unlock_formula(formula_id)


func _refresh_diseases_affected_by_formula(formula_id: String) -> void:
	_ensure_unlock_indexes()
	if not _unlock_indexes_ready:
		refresh_unlocks_by_dependencies()
		return

	for disease_id_value in _get_index_values(_disease_ids_by_formula_id, formula_id):
		var disease_id := String(disease_id_value).strip_edges()
		if disease_id == "":
			continue

		if is_disease_unlocked(disease_id):
			clinical_log_unlocked_disease_ids[disease_id] = true
			_unlock_matching_book_entries("disease", disease_id)
			continue

		unlock_disease(disease_id)


# 按依赖关系级联刷新：
# 1. 方剂全部药材已解锁 -> 解锁方剂及方剂条目
# 2. 疾病标准方已解锁 -> 解锁疾病及疾病条目
#
# 返回本轮新解锁的实体 ID，便于调试或后续做提示。
func refresh_unlocks_by_dependencies() -> Dictionary:
	var result := {
		"formula_ids": [],
		"disease_ids": []
	}

	if _is_refreshing_dependency_unlocks:
		return result

	_is_refreshing_dependency_unlocks = true
	_ensure_unlock_indexes()

	if _unlock_indexes_ready:
		# 全量刷新只保留给读档 / 调试修复使用。
		# 运行时普通药材解锁已经走反向索引的局部刷新。
		for formula_id_value in _formula_by_id.keys():
			var formula_id := String(formula_id_value).strip_edges()
			if formula_id == "":
				continue

			if is_formula_unlocked(formula_id):
				clinical_log_unlocked_formula_ids[formula_id] = true
				_unlock_matching_book_entries("formula", formula_id)
				continue

			var formula = _formula_by_id.get(formula_id)
			if formula is FormulaData and _are_all_formula_herbs_unlocked(formula as FormulaData):
				unlock_formula(formula_id)
				result["formula_ids"].append(formula_id)

		for disease_id_value in _disease_by_id.keys():
			var disease_id := String(disease_id_value).strip_edges()
			if disease_id == "":
				continue

			if is_disease_unlocked(disease_id):
				clinical_log_unlocked_disease_ids[disease_id] = true
				_unlock_matching_book_entries("disease", disease_id)
				continue

			var disease = _disease_by_id.get(disease_id)
			if not (disease is DiseaseData):
				continue

			var standard_formula_id := (disease as DiseaseData).recommended_formula_id.strip_edges()
			if standard_formula_id != "" and is_formula_unlocked(standard_formula_id):
				unlock_disease(disease_id)
				result["disease_ids"].append(disease_id)

		_is_refreshing_dependency_unlocks = false
		return result

	# 初始化顺序异常时保留旧的全扫描兜底。
	if FormulaDB != null and FormulaDB.has_method("get_all_formulas"):
		var all_formulas: Array[FormulaData] = FormulaDB.get_all_formulas()
		for formula in all_formulas:
			if formula == null:
				continue

			var formula_id := formula.formula_id.strip_edges()
			if formula_id == "":
				continue

			if is_formula_unlocked(formula_id):
				clinical_log_unlocked_formula_ids[formula_id] = true
				_unlock_matching_book_entries("formula", formula_id)
				continue

			if _are_all_formula_herbs_unlocked(formula):
				unlock_formula(formula_id)
				result["formula_ids"].append(formula_id)

	if DiseaseDB != null and DiseaseDB.has_method("get_all_diseases"):
		var all_diseases: Array[DiseaseData] = DiseaseDB.get_all_diseases()
		for disease in all_diseases:
			if disease == null:
				continue

			var disease_id := disease.disease_id.strip_edges()
			if disease_id == "":
				continue

			if is_disease_unlocked(disease_id):
				clinical_log_unlocked_disease_ids[disease_id] = true
				_unlock_matching_book_entries("disease", disease_id)
				continue

			var standard_formula_id := disease.recommended_formula_id.strip_edges()
			if standard_formula_id != "" and is_formula_unlocked(standard_formula_id):
				unlock_disease(disease_id)
				result["disease_ids"].append(disease_id)

	_is_refreshing_dependency_unlocks = false
	return result

func is_herb_unlocked(herb_id: String) -> bool:
	return unlocked_herb_ids.has(herb_id.strip_edges())


func is_disease_unlocked(disease_id: String) -> bool:
	return unlocked_disease_ids.has(disease_id.strip_edges())


func is_formula_unlocked(formula_id: String) -> bool:
	return unlocked_formula_ids.has(formula_id.strip_edges())


# 检查药材、方剂、疾病、理论四类中，是否存在“已解锁、可阅读但尚未读”的条目。
# 夜晚休息时使用此通用检查：只有四类都没有新未读条目时，才允许进入下一天。
func has_unread_readable_entries() -> bool:
	return get_unread_readable_entry_count() > 0


func get_unread_readable_entry_count() -> int:
	if not _unread_readable_count_ready:
		_rebuild_unread_readable_count()

	return _unread_readable_count


func _rebuild_unread_readable_count() -> void:
	_unread_readable_count = 0

	if BookEntryDB == null:
		_unread_readable_count_ready = true
		return

	var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()
	for entry in all_entries:
		if entry == null:
			continue

		if not (
			entry is HerbBookEntryData
			or entry is FormulaBookEntryData
			or entry is DiseaseBookEntryData
			or entry is TheoryBookEntryData
		):
			continue

		if is_entry_read(entry.entry_id):
			continue

		if can_read_entry(entry.entry_id):
			_unread_readable_count += 1

	_unread_readable_count_ready = true


# 保留旧的疾病/方剂专用接口，避免其他现有逻辑失效。
func has_unread_unlocked_disease_or_formula_entries() -> bool:
	return get_unread_unlocked_disease_or_formula_entry_count() > 0


func get_unread_unlocked_disease_or_formula_entry_count() -> int:
	if BookEntryDB == null:
		return 0

	_ensure_unlock_indexes()

	# 旧接口使用较少；有索引时只遍历 Formula / Disease 条目，不再扫全部 214 条。
	if _unlock_indexes_ready:
		var count := 0
		var seen_entry_ids: Dictionary = {}
		var entry_indexes: Array[Dictionary] = [
			_book_entry_ids_by_formula_id,
			_book_entry_ids_by_disease_id,
		]

		for entry_index in entry_indexes:
			for entry_ids_value in entry_index.values():
				if typeof(entry_ids_value) != TYPE_ARRAY:
					continue
				for entry_id_value in entry_ids_value:
					var entry_id := String(entry_id_value).strip_edges()
					if entry_id == "" or seen_entry_ids.has(entry_id):
						continue
					seen_entry_ids[entry_id] = true

					if not is_entry_read(entry_id) and can_read_entry(entry_id):
						count += 1

		return count

	var fallback_count := 0
	var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()
	for entry in all_entries:
		if entry == null:
			continue
		if not (entry is DiseaseBookEntryData or entry is FormulaBookEntryData):
			continue
		if is_entry_read(entry.entry_id):
			continue
		if can_read_entry(entry.entry_id):
			fallback_count += 1

	return fallback_count

# =========================================================
# 七、行医记考状态函数
# =========================================================

func is_herb_unlocked_in_clinical_log(herb_id: String) -> bool:
	return clinical_log_unlocked_herb_ids.has(herb_id.strip_edges())


func is_disease_unlocked_in_clinical_log(disease_id: String) -> bool:
	return clinical_log_unlocked_disease_ids.has(disease_id.strip_edges())


func is_formula_unlocked_in_clinical_log(formula_id: String) -> bool:
	return clinical_log_unlocked_formula_ids.has(formula_id.strip_edges())


# =========================================================
# 十、分类型判断逻辑
# =========================================================

func _can_read_herb(entry: HerbBookEntryData) -> bool:
	if entry == null:
		return false

	# 兼容旧存档：以前可能只记录了药材解锁，没有记录条目解锁。
	return is_entry_unlocked(entry.entry_id) or is_herb_unlocked(entry.herb_id)


func _can_read_formula(entry: FormulaBookEntryData) -> bool:
	if entry == null:
		return false

	if is_entry_read(entry.entry_id):
		return false

	# 方剂实体是依赖解锁的事实来源，条目状态负责界面显示。
	return is_formula_unlocked(entry.formula_id) and is_entry_unlocked(entry.entry_id)


func _can_read_disease(entry: DiseaseBookEntryData) -> bool:
	if entry == null:
		return false

	if is_entry_read(entry.entry_id):
		return false

	# 疾病实体是依赖解锁的事实来源，条目状态负责界面显示。
	return is_disease_unlocked(entry.disease_id) and is_entry_unlocked(entry.entry_id)


func _can_read_theory(entry: TheoryBookEntryData) -> bool:
	if entry == null:
		return false

	if is_entry_read(entry.entry_id):
		return false

	return is_entry_unlocked(entry.entry_id)


# =========================================================
# 十一、条目状态判断
# =========================================================

func can_read_entry(entry_id: String) -> bool:
	var clean_id := entry_id.strip_edges()
	if clean_id == "":
		return false

	var entry = BookEntryDB.get_entry(clean_id)
	if entry == null:
		return false

	if entry is HerbBookEntryData:
		return _can_read_herb(entry as HerbBookEntryData)

	if entry is FormulaBookEntryData:
		return _can_read_formula(entry as FormulaBookEntryData)

	if entry is DiseaseBookEntryData:
		return _can_read_disease(entry as DiseaseBookEntryData)

	if entry is TheoryBookEntryData:
		return _can_read_theory(entry as TheoryBookEntryData)

	return false


func is_entry_visible(entry_id: String) -> bool:
	var clean_id := entry_id.strip_edges()
	if clean_id == "":
		return false

	var entry = BookEntryDB.get_entry(clean_id)
	if entry == null:
		return false

	# 方剂 / 疾病以实体解锁状态为准，避免旧的心得条目记录绕过新规则。
	if entry is FormulaBookEntryData:
		var formula_entry := entry as FormulaBookEntryData
		return is_formula_unlocked(formula_entry.formula_id) or is_entry_read(clean_id)

	if entry is DiseaseBookEntryData:
		var disease_entry := entry as DiseaseBookEntryData
		return is_disease_unlocked(disease_entry.disease_id) or is_entry_read(clean_id)

	if is_entry_unlocked(clean_id):
		return true

	# 兼容旧存档：以前神农本草经阅读推进可能只解锁药材，未同步解锁书籍条目。
	if entry is HerbBookEntryData:
		var herb_entry := entry as HerbBookEntryData
		if is_herb_unlocked(herb_entry.herb_id):
			return true

	if is_entry_read(clean_id):
		return true

	return false


func is_entry_readable(entry_id: String) -> bool:
	return can_read_entry(entry_id)


# =========================================================
# 十二、执行阅读
# =========================================================

func read_entry(entry: BookEntryData) -> void:
	if entry == null:
		return

	if not can_read_entry(entry.entry_id):
		return

	mark_entry_as_read(entry.entry_id)

	if entry is HerbBookEntryData:
		var herb_entry := entry as HerbBookEntryData
		unlock_herb(herb_entry.herb_id)
		return

	if entry is TheoryBookEntryData:
		return

	if entry is FormulaBookEntryData:
		var formula_entry := entry as FormulaBookEntryData
		unlock_formula(formula_entry.formula_id)
		return

	if entry is DiseaseBookEntryData:
		var disease_entry := entry as DiseaseBookEntryData
		unlock_disease(disease_entry.disease_id)
		return


# =========================================================
# 十三、获取条目列表
# =========================================================

func get_readable_entries_by_book(book_id: String) -> Array[BookEntryData]:
	var result: Array[BookEntryData] = []
	var clean_book_id := book_id.strip_edges()

	if clean_book_id == "":
		return result

	var entries: Array = BookEntryDB.get_entries_by_book(clean_book_id)

	for entry in entries:
		if entry == null:
			continue

		if is_entry_visible(entry.entry_id):
			result.append(entry)

	return result


func get_unread_readable_entry_count_by_book(book_id: String) -> int:
	var clean_book_id := book_id.strip_edges()
	if clean_book_id == "":
		return 0

	if BookEntryDB == null:
		return 0

	var count := 0
	var entries: Array = BookEntryDB.get_entries_by_book(clean_book_id)

	for entry in entries:
		if entry == null:
			continue

		if is_entry_read(entry.entry_id):
			continue

		if can_read_entry(entry.entry_id):
			count += 1

	return count


func has_unread_readable_entries_by_book(book_id: String) -> bool:
	return get_unread_readable_entry_count_by_book(book_id) > 0


# =========================================================
# 十四、书籍显示判断
# =========================================================

func is_book_visible_in_readbook(book: BookData) -> bool:
	if book == null:
		return false

	if not book.visible_by_default:
		return false

	if not book.can_read_at_night():
		return false

	var initial_visible_book_ids: Array[String] = [
		"shen_nong_ben_cao_jing",
		"huang_di_nei_jing",
	]
	if initial_visible_book_ids.has(book.book_id.strip_edges()):
		return true

	if book.is_herb_book():
		return get_readable_entries_by_book(book.book_id).size() > 0 or not book.get_herb_unlock_order().is_empty()

	return get_readable_entries_by_book(book.book_id).size() > 0


# =========================================================
# 十五、给行医记考使用的辅助函数
# =========================================================

func _dict_keys_to_string_array(source: Dictionary) -> Array[String]:
	var result: Array[String] = []

	for key in source.keys():
		var clean_id := String(key).strip_edges()
		if clean_id == "":
			continue

		result.append(clean_id)

	return result


func get_unlocked_herb_id_list() -> Array[String]:
	return _dict_keys_to_string_array(unlocked_herb_ids)


func get_unlocked_formula_id_list() -> Array[String]:
	return _dict_keys_to_string_array(unlocked_formula_ids)


func get_unlocked_disease_id_list() -> Array[String]:
	return _dict_keys_to_string_array(unlocked_disease_ids)


func get_clinical_log_herb_id_list() -> Array[String]:
	return _dict_keys_to_string_array(clinical_log_unlocked_herb_ids)


func get_clinical_log_formula_id_list() -> Array[String]:
	return _dict_keys_to_string_array(clinical_log_unlocked_formula_ids)


func get_clinical_log_disease_id_list() -> Array[String]:
	return _dict_keys_to_string_array(clinical_log_unlocked_disease_ids)


# =========================================================
# 测试功能：一键解锁所有条目
# =========================================================

func unlock_all_entries_for_test() -> Dictionary:
	var result := {
		"entry_count": 0,
		"herb_count": 0,
		"formula_count": 0,
		"disease_count": 0,
		"theory_count": 0
	}

	# 条目层：全部解锁并统一标记为已读。
	if BookEntryDB != null:
		var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()

		for entry in all_entries:
			if entry == null:
				continue

			var entry_id := entry.entry_id.strip_edges()
			if entry_id == "":
				continue

			unlock_entry(entry_id)
			mark_entry_as_read(entry_id)
			result["entry_count"] += 1

			if entry is TheoryBookEntryData:
				result["theory_count"] += 1

	# Data 层：直接遍历各数据库，保证没有对应医书条目的实体也会解锁。
	if HerbDB != null and HerbDB.has_method("get_all_herbs"):
		var all_herbs: Array[HerbData] = HerbDB.get_all_herbs()

		for herb in all_herbs:
			if herb == null:
				continue

			var herb_id := herb.herb_id.strip_edges()
			if herb_id == "":
				continue

			unlock_herb(herb_id)
			result["herb_count"] += 1

	if FormulaDB != null and FormulaDB.has_method("get_all_formulas"):
		var all_formulas: Array[FormulaData] = FormulaDB.get_all_formulas()

		for formula in all_formulas:
			if formula == null:
				continue

			var formula_id := formula.formula_id.strip_edges()
			if formula_id == "":
				continue

			unlock_formula(formula_id)
			result["formula_count"] += 1

	if DiseaseDB != null and DiseaseDB.has_method("get_all_diseases"):
		var all_diseases: Array[DiseaseData] = DiseaseDB.get_all_diseases()

		for disease in all_diseases:
			if disease == null:
				continue

			var disease_id := disease.disease_id.strip_edges()
			if disease_id == "":
				continue

			unlock_disease(disease_id)
			result["disease_count"] += 1

	# 补齐实体之间的依赖关系及行医记考状态。
	refresh_unlocks_by_dependencies()

	print("[UnlockManager] 测试解锁并标记已读，已同步 Data 层：", result)
	return result


# =========================================================
# 十五、存档 / 读档
# =========================================================

func reset_progress() -> void:
	read_entry_ids.clear()
	unlocked_entry_ids.clear()
	unlocked_herb_ids.clear()
	unlocked_disease_ids.clear()
	unlocked_formula_ids.clear()
	clinical_log_unlocked_herb_ids.clear()
	clinical_log_unlocked_disease_ids.clear()
	clinical_log_unlocked_formula_ids.clear()
	unlocked_story_ids.clear()
	_is_refreshing_dependency_unlocks = false
	_experience_unlock_cursor = 0
	_unread_readable_count = 0
	_unread_readable_count_ready = true
	_touch_readbook_state()

	experience_points = 0
	reputation_points = 0

	money_wen = STARTING_MONEY_WEN
	_reset_daily_finance_ledger(1)
	last_finance_settled_day = 0
	last_finance_report.clear()
	_emit_all_player_stat_signals()

	# 新游戏也立即应用 0 点心得即可解锁的初始条目。
	# 这样 Night 不需要再承担“跨天前补做一次全量刷新”的职责。
	refresh_auto_unlocks_by_experience()


func get_save_data() -> Dictionary:
	return {
		"read_entry_ids": read_entry_ids,
		"unlocked_entry_ids": unlocked_entry_ids,
		"unlocked_herb_ids": unlocked_herb_ids,
		"unlocked_disease_ids": unlocked_disease_ids,
		"unlocked_formula_ids": unlocked_formula_ids,
		"clinical_log_unlocked_herb_ids": clinical_log_unlocked_herb_ids,
		"clinical_log_unlocked_disease_ids": clinical_log_unlocked_disease_ids,
		"clinical_log_unlocked_formula_ids": clinical_log_unlocked_formula_ids,
		"experience_points": experience_points,
		"reputation_points": reputation_points,
		"money_wen": money_wen,
		"finance_ledger_day": finance_ledger_day,
		"finance_ledger_accounting_version": finance_ledger_accounting_version,
		"daily_random_npc_count": daily_random_npc_count,
		"daily_consultation_income_wen": daily_consultation_income_wen,
		"daily_medicine_sales_wen": daily_medicine_sales_wen,
		"daily_medicine_purchase_cost_wen": daily_medicine_purchase_cost_wen,
		# 旧字段继续保存，便于回滚/兼容旧档。
		"daily_medicine_profit_wen": daily_medicine_profit_wen,
		"daily_failed_medicine_cost_wen": daily_failed_medicine_cost_wen,
		"last_finance_settled_day": last_finance_settled_day,
		"last_finance_report": last_finance_report,
		"unlocked_story_ids": unlocked_story_ids
	}


func load_save_data(data: Dictionary) -> void:
	reset_progress()

	read_entry_ids = _load_bool_dictionary(data.get("read_entry_ids", {}))
	unlocked_entry_ids = _load_bool_dictionary(data.get("unlocked_entry_ids", {}))
	unlocked_herb_ids = _load_bool_dictionary(data.get("unlocked_herb_ids", {}))
	unlocked_disease_ids = _load_bool_dictionary(data.get("unlocked_disease_ids", {}))
	unlocked_formula_ids = _load_bool_dictionary(data.get("unlocked_formula_ids", {}))
	clinical_log_unlocked_herb_ids = _load_bool_dictionary(data.get("clinical_log_unlocked_herb_ids", {}))
	clinical_log_unlocked_disease_ids = _load_bool_dictionary(data.get("clinical_log_unlocked_disease_ids", {}))
	clinical_log_unlocked_formula_ids = _load_bool_dictionary(data.get("clinical_log_unlocked_formula_ids", {}))
	unlocked_story_ids = _load_bool_dictionary(data.get("unlocked_story_ids", {}))

	experience_points = int(data.get("experience_points", 0))
	reputation_points = int(data.get("reputation_points", 0))

	money_wen = int(data.get("money_wen", STARTING_MONEY_WEN))
	finance_ledger_day = maxi(int(data.get("finance_ledger_day", 1)), 1)

	# 没有版本字段说明这是旧账本；当前未结算日继续按旧口径完成，
	# 到下一天 _reset_daily_finance_ledger() 会自动启用新版毛收入/成本账本。
	finance_ledger_accounting_version = int(
		data.get("finance_ledger_accounting_version", 1)
	)

	daily_random_npc_count = int(data.get("daily_random_npc_count", 0))
	daily_consultation_income_wen = int(data.get("daily_consultation_income_wen", 0))
	daily_medicine_sales_wen = int(data.get("daily_medicine_sales_wen", 0))
	daily_medicine_purchase_cost_wen = int(data.get("daily_medicine_purchase_cost_wen", 0))
	daily_medicine_profit_wen = int(data.get("daily_medicine_profit_wen", 0))
	daily_failed_medicine_cost_wen = int(data.get("daily_failed_medicine_cost_wen", 0))
	last_finance_settled_day = int(data.get("last_finance_settled_day", 0))
	_emit_all_player_stat_signals()

	var loaded_finance_report = data.get("last_finance_report", {})
	if typeof(loaded_finance_report) == TYPE_DICTIONARY:
		last_finance_report = loaded_finance_report.duplicate(true)
	else:
		last_finance_report = {}

	# 这些 Dictionary 是直接从旧存档恢复的，没有经过增量事件，
	# 因此先暂停未读计数维护，最后统一重建一次。
	_unread_readable_count_ready = false
	_experience_unlock_cursor = 0

	refresh_auto_unlocks_by_experience()
	refresh_unlocks_by_dependencies()
	refresh_story_unlocks_by_reputation()
	_rebuild_unread_readable_count()
	_touch_readbook_state()


func _load_bool_dictionary(source) -> Dictionary:
	var result := {}

	if typeof(source) != TYPE_DICTIONARY:
		return result

	for key in source.keys():
		var clean_key := String(key).strip_edges()
		if clean_key == "":
			continue

		result[clean_key] = bool(source[key])

	return result
