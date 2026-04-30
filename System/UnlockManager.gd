extends Node
class_name UnlockManager

# =========================================================
# 解锁管理器
#
# 当前规则：
# - Herb 条目：对应药材已解锁即可查看
# - Formula 条目：所需药材全部已解锁后可阅读
# - Disease 条目：前置条目全部已读后可阅读
# - Theory 条目：前置理论条目全部已读后可阅读
# - 病证书（disease）、方剂书（formula）、医理书（theory）为独立书籍类型
# - 行医记考（clinical_log）作为白天查看入口，显示夜晚已解锁内容
#
# 注意：
# - Herb 条目“查看”不记为已读
# - Formula / Disease / Theory 条目在首次阅读后会记为已读
# - Formula / Disease 阅读后会顺便解锁对应实体
# - Theory 阅读后只标记已读，不解锁任何实体
# - 所有实体一旦解锁，会同步进入 clinical_log
# =========================================================


# =========================================================
# 一、条目阅读状态
# =========================================================

# 记录已经读过的医书条目
# key: entry_id
# value: true
var read_entry_ids: Dictionary = {}


# =========================================================
# 二、实体解锁状态
# =========================================================

# 已解锁药材
# key: herb_id
# value: true
var unlocked_herb_ids: Dictionary = {}

# 已解锁疾病
# key: disease_id
# value: true
var unlocked_disease_ids: Dictionary = {}

# 已解锁方剂
# key: formula_id
# value: true
var unlocked_formula_ids: Dictionary = {}


# =========================================================
# 三、行医记考可见状态
# 说明：
# - 夜晚解锁实体后，同步加入这里
# - 白天 clinical_log 读取这里来展示内容
# =========================================================

# 已同步到行医记考的药材
# key: herb_id
# value: true
var clinical_log_unlocked_herb_ids: Dictionary = {}

# 已同步到行医记考的疾病
# key: disease_id
# value: true
var clinical_log_unlocked_disease_ids: Dictionary = {}

# 已同步到行医记考的方剂
# key: formula_id
# value: true
var clinical_log_unlocked_formula_ids: Dictionary = {}


# =========================================================
# 四、整本书阅读进度（神农百草经）
# =========================================================

# 记录每本书已经读了多少天
# key: book_id
# value: int
var book_read_days: Dictionary = {}


# =========================================================
# 五、基础状态函数
# =========================================================

# 判断某条医书条目是否已读
func is_entry_read(entry_id: String) -> bool:
	return read_entry_ids.has(entry_id.strip_edges())


# 标记某条医书条目为已读
func mark_entry_as_read(entry_id: String) -> void:
	var id := entry_id.strip_edges()
	if id == "":
		return

	read_entry_ids[id] = true


# 解锁药材
# 说明：
# 1. 解锁药材本体
# 2. 同步进入行医记考
func unlock_herb(herb_id: String) -> void:
	var id := herb_id.strip_edges()
	if id == "":
		return

	unlocked_herb_ids[id] = true
	clinical_log_unlocked_herb_ids[id] = true


# 解锁疾病
# 说明：
# 1. 解锁疾病本体
# 2. 同步进入行医记考
func unlock_disease(disease_id: String) -> void:
	var id := disease_id.strip_edges()
	if id == "":
		return

	unlocked_disease_ids[id] = true
	clinical_log_unlocked_disease_ids[id] = true


# 解锁方剂
# 说明：
# 1. 解锁方剂本体
# 2. 同步进入行医记考
func unlock_formula(formula_id: String) -> void:
	var id := formula_id.strip_edges()
	if id == "":
		return

	unlocked_formula_ids[id] = true
	clinical_log_unlocked_formula_ids[id] = true


# 判断药材是否已解锁
func is_herb_unlocked(herb_id: String) -> bool:
	return unlocked_herb_ids.has(herb_id.strip_edges())


# 判断疾病是否已解锁
func is_disease_unlocked(disease_id: String) -> bool:
	return unlocked_disease_ids.has(disease_id.strip_edges())


# 判断方剂是否已解锁
func is_formula_unlocked(formula_id: String) -> bool:
	return unlocked_formula_ids.has(formula_id.strip_edges())


# =========================================================
# 六、行医记考状态函数
# =========================================================

# 药材是否已同步到行医记考
func is_herb_unlocked_in_clinical_log(herb_id: String) -> bool:
	return clinical_log_unlocked_herb_ids.has(herb_id.strip_edges())


# 疾病是否已同步到行医记考
func is_disease_unlocked_in_clinical_log(disease_id: String) -> bool:
	return clinical_log_unlocked_disease_ids.has(disease_id.strip_edges())


# 方剂是否已同步到行医记考
func is_formula_unlocked_in_clinical_log(formula_id: String) -> bool:
	return clinical_log_unlocked_formula_ids.has(formula_id.strip_edges())


# =========================================================
# 七、神农百草经阅读推进
# =========================================================

# 获取某本书已经读了多少天
func get_book_read_days(book_id: String) -> int:
	return int(book_read_days.get(book_id, 0))


# 给某本书增加一天阅读进度
func add_book_read_day(book_id: String) -> void:
	book_read_days[book_id] = get_book_read_days(book_id) + 1


# 按“每日阅读”推进整本书，并按顺序解锁药材
func read_book_by_day(book: BookData) -> void:
	if book == null:
		return

	# 没有配置药材解锁顺序则直接返回
	var herb_unlock_order := book.get_herb_unlock_order()
	if herb_unlock_order.is_empty():
		return

	# 阅读天数 +1
	add_book_read_day(book.book_id)

	# 根据当前阅读天数决定这次应该解锁哪味药材
	var index := get_book_read_days(book.book_id) - 1

	# 越界保护
	if index < 0 or index >= herb_unlock_order.size():
		return

	var herb_id := String(herb_unlock_order[index]).strip_edges()
	if herb_id == "":
		return

	unlock_herb(herb_id)


# =========================================================
# 八、条件判断函数
# 说明：
# - Formula 条目：通常用于方剂书中的“方剂条目”
# - Disease 条目：通常用于病证书中的“病证条目”
# - Theory 条目：通常用于医理书中的“理论条目”
# =========================================================

# 判断前置条目是否全部已完成（已读）
# 供 Disease / Theory 条目使用
func are_prerequisites_completed(prerequisite_ids: Array[String]) -> bool:
	for entry_id in prerequisite_ids:
		var clean_id := String(entry_id).strip_edges()

		# 空 id 直接视为不合法
		if clean_id == "":
			return false

		# 只要有一个前置条目未读，就不能解锁
		if not is_entry_read(clean_id):
			return false

	return true


# 判断所需药材是否全部已解锁
# 供 Formula 条目使用
func are_required_herbs_unlocked(required_herb_ids: Array[String]) -> bool:
	for herb_id in required_herb_ids:
		var clean_id := String(herb_id).strip_edges()

		# 空 id 直接视为不合法
		if clean_id == "":
			return false

		# 只要有一个药材未解锁，就不能解锁
		if not is_herb_unlocked(clean_id):
			return false

	return true


# =========================================================
# 九、分类型判断逻辑
# =========================================================

# Herb 条目是否可查看
# 规则：对应药材已解锁即可
func _can_read_herb(entry: HerbBookEntryData) -> bool:
	if entry == null:
		return false

	return is_herb_unlocked(entry.herb_id)


# Formula 条目是否可首次阅读
# 规则：未读 + 所需药材全部已解锁
func _can_read_formula(entry: FormulaBookEntryData) -> bool:
	if entry == null:
		return false

	# 已读后不再走“首次阅读”
	if is_entry_read(entry.entry_id):
		return false

	return are_required_herbs_unlocked(entry.required_herb_ids)


# Disease 条目是否可首次阅读
# 规则：未读 + 前置条目全部已读
func _can_read_disease(entry: DiseaseBookEntryData) -> bool:
	if entry == null:
		return false

	# 已读后不再走“首次阅读”
	if is_entry_read(entry.entry_id):
		return false

	return are_prerequisites_completed(entry.prerequisite_entry_ids)


# Theory 条目是否可首次阅读
# 规则：未读 + 前置理论条目全部已读
func _can_read_theory(entry: TheoryBookEntryData) -> bool:
	if entry == null:
		return false

	# 已读后不再走“首次阅读”
	if is_entry_read(entry.entry_id):
		return false

	return are_prerequisites_completed(entry.prerequisite_entry_ids)


# =========================================================
# 十、条目状态判断
# =========================================================

# 是否满足“首次阅读 / 查看”条件
# 用于控制按钮是否可点击
func can_read_entry(entry_id: String) -> bool:
	var clean_id := entry_id.strip_edges()
	if clean_id == "":
		return false

	var entry := BookEntryDB.get_entry(clean_id)
	if entry == null:
		return false

	# 按条目类型分流判断，避免不同条目共用同一套条件
	if entry is HerbBookEntryData:
		return _can_read_herb(entry as HerbBookEntryData)

	if entry is FormulaBookEntryData:
		return _can_read_formula(entry as FormulaBookEntryData)

	if entry is DiseaseBookEntryData:
		return _can_read_disease(entry as DiseaseBookEntryData)

	if entry is TheoryBookEntryData:
		return _can_read_theory(entry as TheoryBookEntryData)

	return false


# 是否应该显示在条目列表中
# 规则：
# - Herb：药材解锁后显示
# - Formula / Disease / Theory：已读后始终显示；未读时满足阅读条件也显示
func is_entry_visible(entry_id: String) -> bool:
	var clean_id := entry_id.strip_edges()
	if clean_id == "":
		return false

	var entry := BookEntryDB.get_entry(clean_id)
	if entry == null:
		return false

	# Herb 条目：药材已解锁即可显示
	if entry is HerbBookEntryData:
		return _can_read_herb(entry as HerbBookEntryData)

	# 其他条目：已读后始终显示
	if is_entry_read(clean_id):
		return true

	# 未读时，满足首次阅读条件即可显示
	return can_read_entry(clean_id)


# 兼容旧调用
func is_entry_readable(entry_id: String) -> bool:
	return can_read_entry(entry_id)


# =========================================================
# 十一、执行阅读
# =========================================================

# 真正执行“阅读条目”
func read_entry(entry: BookEntryData) -> void:
	if entry == null:
		return

	# Herb 条目只查看，不记已读，也不触发普通阅读解锁链
	if entry is HerbBookEntryData:
		return

	# 不满足阅读条件则不能阅读
	if not can_read_entry(entry.entry_id):
		return

	# 标记条目为已读
	mark_entry_as_read(entry.entry_id)

	# Theory 条目：只标记已读，不解锁疾病 / 方剂 / 药材
	if entry is TheoryBookEntryData:
		return

	# Formula 条目：阅读后解锁对应方剂实体
	if entry is FormulaBookEntryData:
		var formula_entry := entry as FormulaBookEntryData
		unlock_formula(formula_entry.formula_id)
		return

	# Disease 条目：阅读后解锁对应疾病实体
	if entry is DiseaseBookEntryData:
		var disease_entry := entry as DiseaseBookEntryData
		unlock_disease(disease_entry.disease_id)
		return


# =========================================================
# 十二、获取条目列表
# 说明：
# - 这里返回的是“当前可在夜晚界面显示/阅读”的条目
# - clinical_log 不应调用这套夜读条目逻辑
# =========================================================

# 获取某本书下“当前可显示/可阅读”的条目
# 规则：
# - Herb：药材已解锁就显示
# - Formula / Disease / Theory：已读后显示；未读但满足条件也显示
func get_readable_entries_by_book(book_id: String) -> Array[BookEntryData]:
	var result: Array[BookEntryData] = []
	var clean_book_id := book_id.strip_edges()

	if clean_book_id == "":
		return result

	# 从 BookEntryDB 取出该书下所有条目
	var entries: Array = BookEntryDB.get_entries_by_book(clean_book_id)

	for entry in entries:
		if entry == null:
			continue

		if is_entry_visible(entry.entry_id):
			result.append(entry)

	return result


# =========================================================
# 十三、给行医记考使用的辅助函数
# =========================================================

# 把 Dictionary 的 key 安全转换成 Array[String]
# 说明：
# - Godot 4 中 Dictionary.keys() 返回普通 Array
# - 直接返回给 Array[String] 可能出现类型不匹配
# - 这里统一转成干净的 String 数组
func _dict_keys_to_string_array(source: Dictionary) -> Array[String]:
	var result: Array[String] = []

	for key in source.keys():
		var clean_id := String(key).strip_edges()

		# 跳过空 key，避免后续 UI 或查询数据库时报错
		if clean_id == "":
			continue

		result.append(clean_id)

	return result


# 获取所有已解锁的药材ID
func get_unlocked_herb_id_list() -> Array[String]:
	return _dict_keys_to_string_array(unlocked_herb_ids)


# 获取所有已解锁的方剂ID
func get_unlocked_formula_id_list() -> Array[String]:
	return _dict_keys_to_string_array(unlocked_formula_ids)


# 获取所有已解锁的疾病ID
func get_unlocked_disease_id_list() -> Array[String]:
	return _dict_keys_to_string_array(unlocked_disease_ids)


# 获取行医记考中可见的药材ID
func get_clinical_log_herb_id_list() -> Array[String]:
	return _dict_keys_to_string_array(clinical_log_unlocked_herb_ids)


# 获取行医记考中可见的方剂ID
func get_clinical_log_formula_id_list() -> Array[String]:
	return _dict_keys_to_string_array(clinical_log_unlocked_formula_ids)


# 获取行医记考中可见的疾病ID
func get_clinical_log_disease_id_list() -> Array[String]:
	return _dict_keys_to_string_array(clinical_log_unlocked_disease_ids)
