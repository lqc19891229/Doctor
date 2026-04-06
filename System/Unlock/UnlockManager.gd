extends Node
class_name UnlockManager

# =========================================================
# UnlockManager.gd
#
# 新版解锁逻辑：
#
# 一、药材书
# - 解锁药材
#
# 二、疾病方剂书
# - 书内只有“病证条目”
# - 病证条目里自带“标准方”
# - 不再把方剂作为独立阅读条目
#
# 三、核心流程
# - 药材解锁
# - 刷新哪些病证条目变成“可阅读”
# - 玩家夜晚阅读某病证条目
# - 正式解锁病证
#
# 四、保留方剂解锁状态的原因
# - 虽然方剂不再是独立阅读条目
# - 但为了兼容旧系统/UI，仍保留“见过标准方”的记录
# - 当玩家阅读病证条目后，可顺带把该标准方标记为已解锁
# =========================================================


# =========================================================
# 一、运行时解锁状态
# =========================================================

# 已解锁药材
# key = herb_id
# value = true
var unlocked_herb_ids: Dictionary = {}

# 已解锁方剂（兼容旧逻辑，可选使用）
# key = formula_id
# value = true
var unlocked_formula_ids: Dictionary = {}

# 已解锁病证
# key = disease_id
# value = true
var unlocked_disease_ids: Dictionary = {}

# 已阅读整本书（例如神农百草经）
# 注意：对于“疾病方剂书”，建议只把它当作“打开过”
# 真正的核心是条目阅读状态
var read_book_ids: Dictionary = {}

# 已阅读病证书条目
# key = entry_id
# value = true
var read_book_entry_ids: Dictionary = {}

# 当前可阅读的病证书条目
# key = entry_id
# value = true
var readable_disease_entry_ids: Dictionary = {}


# =========================================================
# 二、工具：获取数据库单例
# =========================================================

# 获取 FormulaDB
# 用节点路径取，避免直接写死全局变量时报错
func _get_formula_db() -> Node:
	return get_node_or_null("/root/FormulaDB")


# 获取 DiseaseBookDB
# 需要你把 DiseaseBookDataBase.gd 配成 Autoload，名字建议：DiseaseBookDB
func _get_disease_book_db() -> Node:
	return get_node_or_null("/root/DiseaseBookDB")


# =========================================================
# 三、药材
# =========================================================

# 解锁一个药材
func unlock_herb(herb_id: String) -> void:
	var clean_id := herb_id.strip_edges()
	if clean_id == "":
		return

	unlocked_herb_ids[clean_id] = true

	# 药材解锁后，立刻刷新病证条目可读状态
	refresh_disease_book_entries()


# 判断药材是否已解锁
func is_herb_unlocked(herb_id: String) -> bool:
	return unlocked_herb_ids.has(herb_id.strip_edges())


# 批量解锁药材
func unlock_herbs(herb_ids: Array[String]) -> void:
	var changed := false

	for herb_id in herb_ids:
		var clean_id := herb_id.strip_edges()
		if clean_id == "":
			continue

		if unlocked_herb_ids.has(clean_id):
			continue

		unlocked_herb_ids[clean_id] = true
		changed = true

	if changed:
		refresh_disease_book_entries()


# =========================================================
# 四、方剂（兼容保留）
# =========================================================

# 解锁一个方剂
func unlock_formula(formula_id: String) -> void:
	var clean_id := formula_id.strip_edges()
	if clean_id == "":
		return

	unlocked_formula_ids[clean_id] = true


# 判断方剂是否已解锁
func is_formula_unlocked(formula_id: String) -> bool:
	return unlocked_formula_ids.has(formula_id.strip_edges())


# =========================================================
# 五、病证
# =========================================================

# 解锁一个病证
func unlock_disease(disease_id: String) -> void:
	var clean_id := disease_id.strip_edges()
	if clean_id == "":
		return

	unlocked_disease_ids[clean_id] = true


# 判断病证是否已解锁
func is_disease_unlocked(disease_id: String) -> bool:
	return unlocked_disease_ids.has(disease_id.strip_edges())


# =========================================================
# 六、书籍
# =========================================================

# 标记一本书已阅读
func mark_book_as_read(book_id: String) -> void:
	var clean_id := book_id.strip_edges()
	if clean_id == "":
		return

	read_book_ids[clean_id] = true


# 判断书籍是否已阅读
func is_book_read(book_id: String) -> bool:
	return read_book_ids.has(book_id.strip_edges())


# =========================================================
# 七、病证书条目
# =========================================================

# 标记病证书条目已阅读
func mark_entry_as_read(entry_id: String) -> void:
	var clean_id := entry_id.strip_edges()
	if clean_id == "":
		return

	read_book_entry_ids[clean_id] = true


# 判断病证书条目是否已阅读
func is_entry_read(entry_id: String) -> bool:
	return read_book_entry_ids.has(entry_id.strip_edges())


# 判断病证书条目当前是否可阅读
func is_disease_entry_readable(entry_id: String) -> bool:
	return readable_disease_entry_ids.has(entry_id.strip_edges())


# 获取全部当前可阅读条目ID
func get_all_readable_disease_entry_ids() -> Array[String]:
	var result: Array[String] = []

	for key in readable_disease_entry_ids.keys():
		result.append(key)

	return result


# 获取指定书籍下的可阅读条目
func get_readable_entry_ids_by_book(book_id: String) -> Array[String]:
	var result: Array[String] = []
	var disease_book_db := _get_disease_book_db()

	if disease_book_db == null:
		return result

	var entries = disease_book_db.get_entries_by_book(book_id)

	for entry in entries:
		if entry == null:
			continue

		if is_disease_entry_readable(entry.entry_id):
			result.append(entry.entry_id)

	return result


# =========================================================
# 八、刷新病证书条目可阅读状态
# =========================================================

# 重新计算：当前哪些病证条目是可阅读的
func refresh_disease_book_entries() -> void:
	readable_disease_entry_ids.clear()

	var disease_book_db := _get_disease_book_db()
	if disease_book_db == null:
		return

	var all_entries = disease_book_db.get_all_entries()

	for entry in all_entries:
		if entry == null:
			continue

		# 已经读过的，不再列入“可阅读”
		if is_entry_read(entry.entry_id):
			continue

		if _can_read_disease_entry(entry):
			readable_disease_entry_ids[entry.entry_id] = true


# 判断一个病证条目当前是否满足阅读条件
func _can_read_disease_entry(entry: DiseaseBookEntryData) -> bool:
	if entry == null:
		return false

	# 1. 必须先满足前置条目
	for pre_entry_id in entry.get_prerequisite_entry_ids_unique():
		if not is_entry_read(pre_entry_id):
			return false

	# 2. 必须满足所需药材
	for herb_id in entry.get_required_herb_ids_unique():
		if not is_herb_unlocked(herb_id):
			return false

	return true


# =========================================================
# 九、阅读病证条目
# =========================================================

# 阅读一个病证书条目
# 效果：
# 1. 标记条目已读
# 2. 解锁对应病证
# 3. 如果有标准方，则顺带标记该方已解锁（兼容旧系统）
# 4. 刷新其它条目的可阅读状态
func read_disease_entry(entry: DiseaseBookEntryData) -> void:
	if entry == null:
		return

	var clean_entry_id := entry.entry_id.strip_edges()
	if clean_entry_id == "":
		return

	# 已读过则不重复处理
	if is_entry_read(clean_entry_id):
		return

	# 当前不可读，也不处理
	if not _can_read_disease_entry(entry):
		return

	mark_entry_as_read(clean_entry_id)

	var clean_disease_id := entry.disease_id.strip_edges()
	if clean_disease_id != "":
		unlock_disease(clean_disease_id)

	var formula_id := entry.get_standard_formula_id().strip_edges()
	if formula_id != "":
		unlock_formula(formula_id)

	refresh_disease_book_entries()


# =========================================================
# 十、旧接口兼容：阅读整本书
# =========================================================

# 这个接口保留给“神农百草经”或旧书籍系统使用
#
# 注意：
# - 新规则下，不建议再用它批量解锁病证/方剂
# - 更适合只给药材书用
func read_book(book_data: BookData) -> void:
	if book_data == null:
		return

	# 只能阅读一次的书，已读则跳过
	if book_data.read_once and is_book_read(book_data.book_id):
		return

	mark_book_as_read(book_data.book_id)

	# 新版 BookData 只保留 herb_unlock_order
	# 因此整本书阅读逻辑只处理药材书解锁
	for herb_id in book_data.herb_unlock_order:
		unlock_herb(herb_id)

	# 阅读普通书后也刷新一次病证条目可读状态
	refresh_disease_book_entries()


# =========================================================
# 十一、百科 / 图鉴辅助接口
# =========================================================

# 获取已解锁药材ID列表
func get_unlocked_herb_ids() -> Array[String]:
	var result: Array[String] = []

	for herb_id in unlocked_herb_ids.keys():
		result.append(herb_id)

	return result


# 获取已解锁方剂ID列表
func get_unlocked_formula_ids() -> Array[String]:
	var result: Array[String] = []

	for formula_id in unlocked_formula_ids.keys():
		result.append(formula_id)

	return result


# 获取已解锁病证ID列表
func get_unlocked_disease_ids() -> Array[String]:
	var result: Array[String] = []

	for disease_id in unlocked_disease_ids.keys():
		result.append(disease_id)

	return result


# 获取已阅读书籍ID列表
func get_read_book_ids() -> Array[String]:
	var result: Array[String] = []

	for book_id in read_book_ids.keys():
		result.append(book_id)

	return result


# 获取已阅读病证条目ID列表
func get_read_book_entry_ids() -> Array[String]:
	var result: Array[String] = []

	for entry_id in read_book_entry_ids.keys():
		result.append(entry_id)

	return result
