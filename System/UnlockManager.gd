extends Node
class_name UnlockManager

# =========================================================
# 解锁管理器
#
# 当前规则：
# - 心得点数改为“累计值”，不再作为读书消耗货币
# - BookEntryData.unlock_required_experience_points 控制条目自动解锁阈值
# - 条目解锁只依赖累计心得与 unlock_required_experience_points
# - required_herb_ids / prerequisite_entry_ids 不再参与 ReadBook 解锁判断
# - 达到累计心得阈值后，条目自动进入 unlocked_entry_ids
# - Herb 条目：条目已解锁后，可查看，首次查看后记为已读并同步解锁对应药材
# - Formula 条目：条目已解锁后，可阅读，阅读后解锁对应方剂
# - Disease 条目：条目已解锁后，可阅读，阅读后解锁对应疾病
# - Theory 条目：条目已解锁后，可阅读，阅读后只标记已读
# - 行医记考（clinical_log）显示已同步解锁的实体内容
#
# 注意：
# - “解锁”和“已读”分开记录
# - unlocked_entry_ids：条目已解锁，可在读书界面显示/查看
# - read_entry_ids：条目已阅读/查看过
# - Herb 条目首次查看后会同步解锁药材，并记入 read_entry_ids 用于未读提示
# - Formula / Disease / Theory 条目在首次阅读后会记为已读
# - Formula / Disease 阅读后会顺便解锁对应实体
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


# =========================================================
# 四、整本书阅读进度（神农百草经）
# =========================================================

var book_read_days: Dictionary = {}


# =========================================================
# 五、心得点数（累计值）
# =========================================================

var experience_points: int = 0


func get_experience_points() -> int:
	return experience_points


func add_experience_point(amount: int = 1) -> Array[String]:
	if amount <= 0:
		return []

	experience_points += amount
	return refresh_auto_unlocks_by_experience()


func has_experience_point() -> bool:
	return experience_points > 0


func consume_experience_point() -> bool:
	return true


# =========================================================
# 六、名望点数（累计值）
# 用于剧情解锁和节奏控制
# =========================================================

var reputation_points: int = 0


func get_reputation_points() -> int:
	return reputation_points


func add_reputation_points(amount: int = 1) -> void:
	if amount == 0:
		return

	reputation_points += amount


func has_reputation_points(required_amount: int) -> bool:
	return reputation_points >= required_amount


# =========================================================
# 七、心得自动解锁条目
# =========================================================

func refresh_auto_unlocks_by_experience() -> Array[String]:
	var newly_unlocked_titles: Array[String] = []

	if BookEntryDB == null:
		return newly_unlocked_titles

	var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()

	for entry in all_entries:
		if entry == null:
			continue

		if is_entry_unlocked(entry.entry_id):
			continue

		# 只根据累计心得判断是否自动解锁。
		# required_herb_ids / prerequisite_entry_ids 不参与这里的判断。
		if not can_unlock_entry(entry):
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

	var required_points := _get_entry_required_experience_points(entry)
	if required_points < 0:
		return false

	return experience_points >= required_points


func unlock_entry(entry_id: String) -> void:
	var id := entry_id.strip_edges()
	if id == "":
		return

	unlocked_entry_ids[id] = true


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

	read_entry_ids[id] = true


func unlock_herb(herb_id: String) -> void:
	var id := herb_id.strip_edges()
	if id == "":
		return

	unlocked_herb_ids[id] = true
	clinical_log_unlocked_herb_ids[id] = true


func unlock_disease(disease_id: String) -> void:
	var id := disease_id.strip_edges()
	if id == "":
		return

	unlocked_disease_ids[id] = true
	clinical_log_unlocked_disease_ids[id] = true


func unlock_formula(formula_id: String) -> void:
	var id := formula_id.strip_edges()
	if id == "":
		return

	unlocked_formula_ids[id] = true
	clinical_log_unlocked_formula_ids[id] = true


func is_herb_unlocked(herb_id: String) -> bool:
	return unlocked_herb_ids.has(herb_id.strip_edges())


func is_disease_unlocked(disease_id: String) -> bool:
	return unlocked_disease_ids.has(disease_id.strip_edges())


func is_formula_unlocked(formula_id: String) -> bool:
	return unlocked_formula_ids.has(formula_id.strip_edges())


func has_unread_unlocked_disease_or_formula_entries() -> bool:
	return get_unread_unlocked_disease_or_formula_entry_count() > 0


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

		if is_entry_unlocked(entry.entry_id):
			count += 1

	return count


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
# 八、神农百草经阅读推进
# =========================================================

func get_book_read_days(book_id: String) -> int:
	return int(book_read_days.get(book_id, 0))


func add_book_read_day(book_id: String) -> void:
	book_read_days[book_id] = get_book_read_days(book_id) + 1


func can_continue_herb_book_reading(book: BookData) -> bool:
	if book == null:
		return false

	if not book.is_herb_book():
		return false

	if has_unread_unlocked_disease_or_formula_entries():
		return false

	var herb_unlock_order := book.get_herb_unlock_order()
	return get_book_read_days(book.book_id) < herb_unlock_order.size()


func read_book_by_day(book: BookData) -> void:
	if book == null:
		return

	var herb_unlock_order := book.get_herb_unlock_order()
	if herb_unlock_order.is_empty():
		return

	if has_unread_unlocked_disease_or_formula_entries():
		return

	add_book_read_day(book.book_id)

	var index := get_book_read_days(book.book_id) - 1
	if index < 0 or index >= herb_unlock_order.size():
		return

	var herb_id := String(herb_unlock_order[index]).strip_edges()
	if herb_id == "":
		return

	unlock_herb(herb_id)
	unlock_entry(herb_id)
	
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

	return is_entry_unlocked(entry.entry_id)


func _can_read_disease(entry: DiseaseBookEntryData) -> bool:
	if entry == null:
		return false

	if is_entry_read(entry.entry_id):
		return false

	return is_entry_unlocked(entry.entry_id)


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

	var entry := BookEntryDB.get_entry(clean_id)
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

	var entry := BookEntryDB.get_entry(clean_id)
	if entry == null:
		return false

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

	if BookEntryDB == null:
		return result

	var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()

	for entry in all_entries:
		if entry == null:
			continue

		result["entry_count"] += 1
		unlock_entry(entry.entry_id)

		if entry is HerbBookEntryData:
			var herb_entry := entry as HerbBookEntryData
			unlock_herb(herb_entry.herb_id)
			result["herb_count"] += 1
			continue

		mark_entry_as_read(entry.entry_id)

		if entry is FormulaBookEntryData:
			var formula_entry := entry as FormulaBookEntryData
			unlock_formula(formula_entry.formula_id)
			result["formula_count"] += 1
			continue

		if entry is DiseaseBookEntryData:
			var disease_entry := entry as DiseaseBookEntryData
			unlock_disease(disease_entry.disease_id)
			result["disease_count"] += 1
			continue

		if entry is TheoryBookEntryData:
			result["theory_count"] += 1

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

func reset_progress() -> void:
	read_entry_ids.clear()
	unlocked_entry_ids.clear()
	unlocked_herb_ids.clear()
	unlocked_disease_ids.clear()
	unlocked_formula_ids.clear()
	clinical_log_unlocked_herb_ids.clear()
	clinical_log_unlocked_disease_ids.clear()
	clinical_log_unlocked_formula_ids.clear()
	book_read_days.clear()

	experience_points = 0
	reputation_points = 0


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
		"book_read_days": book_read_days,
		"experience_points": experience_points,
		"reputation_points": reputation_points
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
	book_read_days = _load_int_dictionary(data.get("book_read_days", {}))

	experience_points = int(data.get("experience_points", 0))
	reputation_points = int(data.get("reputation_points", 0))

	refresh_auto_unlocks_by_experience()


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
