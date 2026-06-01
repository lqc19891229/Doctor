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
# 五、心得点数
# 说明：
# - 白天开方获得满分甲等评价时，获得 1 点心得
# - 夜间读书首次解锁条目时，消耗 1 点心得
# - 1 点心得解锁 1 条内容
# =========================================================

# 当前拥有的心得数量
var experience_points: int = 5


# 获取当前心得数量
func get_experience_points() -> int:
	return experience_points


# 增加心得
# amount: 增加数量，默认增加 1 点
func add_experience_point(amount: int = 1) -> void:
	# 防止传入 0 或负数导致异常加减
	if amount <= 0:
		return

	experience_points += amount


# 是否至少拥有 1 点心得
func has_experience_point() -> bool:
	return experience_points > 0


# 消耗 1 点心得
# 返回值：
# - true：消耗成功
# - false：心得不足，消耗失败
func consume_experience_point() -> bool:
	if experience_points <= 0:
		return false

	experience_points -= 1
	return true


# =========================================================
# 六、基础状态函数
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


# 是否存在“已解锁/可阅读，但还没阅读”的疾病或方剂条目
# 说明：
# - 这里的“已解锁”指条目已经满足显示/阅读条件。
# - 这些条目会阻止神农百草经继续解锁新药材，避免玩家一直只读药材书。
func has_unread_unlocked_disease_or_formula_entries() -> bool:
	return get_unread_unlocked_disease_or_formula_entry_count() > 0


# 获取当前待阅读的疾病 / 方剂条目数量
func get_unread_unlocked_disease_or_formula_entry_count() -> int:
	if BookEntryDB == null:
		return 0

	var count := 0
	var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()

	for entry in all_entries:
		if entry == null:
			continue

		if not (entry is DiseaseBookEntryData or entry is FormulaBookEntryData):
			continue

		if is_entry_read(entry.entry_id):
			continue

		if can_read_entry(entry.entry_id):
			count += 1

	return count


# =========================================================
# 七、行医记考状态函数
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
# 八、神农百草经阅读推进
# =========================================================

# 获取某本书已经读了多少天
func get_book_read_days(book_id: String) -> int:
	return int(book_read_days.get(book_id, 0))


# 给某本书增加一天阅读进度
func add_book_read_day(book_id: String) -> void:
	book_read_days[book_id] = get_book_read_days(book_id) + 1


# 药材书是否还能继续推进新条目
func can_continue_herb_book_reading(book: BookData) -> bool:
	if book == null:
		return false

	if not book.is_herb_book():
		return false

	if has_unread_unlocked_disease_or_formula_entries():
		return false

	var herb_unlock_order := book.get_herb_unlock_order()
	return get_book_read_days(book.book_id) < herb_unlock_order.size()


# 按“每日阅读”推进整本书，并按顺序解锁药材
func read_book_by_day(book: BookData) -> void:
	if book == null:
		return

	# 没有配置药材解锁顺序则直接返回
	var herb_unlock_order := book.get_herb_unlock_order()
	if herb_unlock_order.is_empty():
		return

	# 有待阅读的疾病 / 方剂条目时，不允许继续推进药材书。
	if has_unread_unlocked_disease_or_formula_entries():
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
# 九、条件判断函数
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
# 十、分类型判断逻辑
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
# 十一、条目状态判断
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
# 十二、执行阅读
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
# 十三、获取条目列表
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




# 获取某本书中“已解锁/可阅读，但还没阅读”的普通条目数量
# 说明：
# - Herb 条目不计入“新条目”，因为药材条目只查看、不标记已读。
# - Formula / Disease / Theory 条目满足首次阅读条件时，计为新条目。
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

		if entry is HerbBookEntryData:
			continue

		if is_entry_read(entry.entry_id):
			continue

		if can_read_entry(entry.entry_id):
			count += 1

	return count


# 某本书是否有新解锁、尚未阅读的普通条目
func has_unread_readable_entries_by_book(book_id: String) -> bool:
	return get_unread_readable_entry_count_by_book(book_id) > 0


# =========================================================
# 十四、书籍显示判断
# =========================================================

# ReadBook 左侧书籍是否应该显示
func is_book_visible_in_readbook(book: BookData) -> bool:
	if book == null:
		return false

	if not book.visible_by_default:
		return false

	if not book.can_read_at_night():
		return false

	# 初始入口书：即使暂时没有可读条目，也显示在左侧。
	var initial_visible_book_ids: Array[String] = [
		"shen_nong_ben_cao_jing",
		"huang_di_nei_jing",
	]
	if initial_visible_book_ids.has(book.book_id.strip_edges()):
		return true

	if book.is_herb_book():
		return not book.get_herb_unlock_order().is_empty()

	return get_readable_entries_by_book(book.book_id).size() > 0


# =========================================================
# 十五、给行医记考使用的辅助函数
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



# =========================================================
# 测试功能：一键解锁所有条目
# 说明：
# 1. 仅用于开发测试。
# 2. 药材条目：解锁对应药材。
# 3. 方剂条目：标记条目已读，并解锁对应方剂。
# 4. 病证条目：标记条目已读，并解锁对应疾病。
# 5. 医理条目：标记条目已读。
# 6. 神农百草经的阅读天数会补到全部药材已解锁。
# =========================================================
func unlock_all_entries_for_test() -> Dictionary:
	var result := {
		"entry_count": 0,
		"herb_count": 0,
		"formula_count": 0,
		"disease_count": 0,
		"theory_count": 0
	}

	# 防御：BookEntryDB 必须已经加载完成。
	if BookEntryDB == null:
		return result

	var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()

	for entry in all_entries:
		if entry == null:
			continue

		result["entry_count"] += 1

		# 药材条目：只解锁药材，不强行标记为已读。
		# 因为当前规则里 Herb 条目是“查看”，不是“阅读”。
		if entry is HerbBookEntryData:
			var herb_entry := entry as HerbBookEntryData
			unlock_herb(herb_entry.herb_id)
			result["herb_count"] += 1
			continue

		# 其他书籍条目：统一标记为已读，方便 NightStudy 直接回看。
		mark_entry_as_read(entry.entry_id)

		# 方剂条目：同步解锁方剂本体。
		if entry is FormulaBookEntryData:
			var formula_entry := entry as FormulaBookEntryData
			unlock_formula(formula_entry.formula_id)
			result["formula_count"] += 1
			continue

		# 病证条目：同步解锁疾病本体。
		if entry is DiseaseBookEntryData:
			var disease_entry := entry as DiseaseBookEntryData
			unlock_disease(disease_entry.disease_id)
			result["disease_count"] += 1
			continue

		# 医理条目：只需要已读状态。
		if entry is TheoryBookEntryData:
			result["theory_count"] += 1

	# 把带药材解锁顺序的书籍进度补满。
	# 这样 NightStudy 中“神农百草经”的进度也会显示为满。
	if BookDB != null:
		var all_books: Array[BookData] = BookDB.get_all_books()
		for book in all_books:
			if book == null:
				continue

			var herb_unlock_order := book.get_herb_unlock_order()
			if herb_unlock_order.is_empty():
				continue

			book_read_days[book.book_id] = herb_unlock_order.size()

	print("[UnlockManager] 测试解锁全部条目：", result)
	return result


# =========================================================
# 十五、存档 / 读档
# =========================================================

# 重置所有解锁与阅读进度
# 用于新游戏
func reset_progress() -> void:
	read_entry_ids.clear()
	unlocked_herb_ids.clear()
	unlocked_disease_ids.clear()
	unlocked_formula_ids.clear()
	clinical_log_unlocked_herb_ids.clear()
	clinical_log_unlocked_disease_ids.clear()
	clinical_log_unlocked_formula_ids.clear()
	book_read_days.clear()

	# 重置心得点数
	experience_points = 5


# 存档用：导出当前所有进度
func get_save_data() -> Dictionary:
	return {
		"read_entry_ids": read_entry_ids,
		"unlocked_herb_ids": unlocked_herb_ids,
		"unlocked_disease_ids": unlocked_disease_ids,
		"unlocked_formula_ids": unlocked_formula_ids,
		"clinical_log_unlocked_herb_ids": clinical_log_unlocked_herb_ids,
		"clinical_log_unlocked_disease_ids": clinical_log_unlocked_disease_ids,
		"clinical_log_unlocked_formula_ids": clinical_log_unlocked_formula_ids,
		"book_read_days": book_read_days,

		# 保存心得点数
		"experience_points": experience_points
	}


# 读档用：恢复所有进度
func load_save_data(data: Dictionary) -> void:
	reset_progress()

	read_entry_ids = _load_bool_dictionary(data.get("read_entry_ids", {}))
	unlocked_herb_ids = _load_bool_dictionary(data.get("unlocked_herb_ids", {}))
	unlocked_disease_ids = _load_bool_dictionary(data.get("unlocked_disease_ids", {}))
	unlocked_formula_ids = _load_bool_dictionary(data.get("unlocked_formula_ids", {}))
	clinical_log_unlocked_herb_ids = _load_bool_dictionary(data.get("clinical_log_unlocked_herb_ids", {}))
	clinical_log_unlocked_disease_ids = _load_bool_dictionary(data.get("clinical_log_unlocked_disease_ids", {}))
	clinical_log_unlocked_formula_ids = _load_bool_dictionary(data.get("clinical_log_unlocked_formula_ids", {}))
	book_read_days = _load_int_dictionary(data.get("book_read_days", {}))

	# 读取心得点数；旧存档没有该字段时默认为 0
	experience_points = int(data.get("experience_points", 0))


# 把 JSON 读出来的 Dictionary 转回 {String: true}
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


# 把 JSON 读出来的 Dictionary 转回 {String: int}
func _load_int_dictionary(source) -> Dictionary:
	var result := {}

	if typeof(source) != TYPE_DICTIONARY:
		return result

	for key in source.keys():
		var clean_key := String(key).strip_edges()
		if clean_key == "":
			continue

		result[clean_key] = int(source[key])

	return result
