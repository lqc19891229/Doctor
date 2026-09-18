extends RefCounted
class_name GlobalReadBookArchive

# 总图鉴独立于各局存档保存。此类不做 Autoload，调用方按需实例化。
const ARCHIVE_PATH: String = "user://global_readbook_archive.json"
const TEMP_PATH: String = ARCHIVE_PATH + ".tmp"
const BACKUP_PATH: String = ARCHIVE_PATH + ".bak"
const ARCHIVE_VERSION: int = 1

const INITIAL_BOOK_IDS: Array[String] = [
	"shen_nong_ben_cao_jing",
	"huang_di_nei_jing",
]

var unlocked_entry_ids: Dictionary = {}
var read_entry_ids: Dictionary = {}
var _loaded: bool = false


func reload() -> void:
	_loaded = false
	_ensure_loaded()


# 将多份旧存档一次性合并。合并只增加条目，不会因覆盖或删除存档而撤销解锁。
func merge_progress_list(progress_list: Array) -> bool:
	_ensure_loaded()
	var changed := false

	for progress_variant in progress_list:
		if typeof(progress_variant) != TYPE_DICTIONARY:
			continue
		changed = _merge_progress(progress_variant) or changed

	if changed:
		_save_archive()
	return changed


func merge_progress(progress: Dictionary) -> bool:
	_ensure_loaded()
	var changed := _merge_progress(progress)
	if changed:
		_save_archive()
	return changed


func is_entry_unlocked(entry_id: String) -> bool:
	_ensure_loaded()
	return unlocked_entry_ids.has(entry_id.strip_edges())


func is_entry_read(entry_id: String) -> bool:
	_ensure_loaded()
	return read_entry_ids.has(entry_id.strip_edges())


func mark_entry_as_read(entry_id: String) -> bool:
	_ensure_loaded()
	var clean_id := entry_id.strip_edges()
	if clean_id == "" or not unlocked_entry_ids.has(clean_id):
		return false
	if read_entry_ids.has(clean_id):
		return false

	read_entry_ids[clean_id] = true
	_save_archive()
	return true


func can_read_entry(entry_id: String) -> bool:
	return is_entry_unlocked(entry_id)


func get_readable_entries_by_book(book_id: String) -> Array[BookEntryData]:
	_ensure_loaded()
	var result: Array[BookEntryData] = []
	var clean_book_id := book_id.strip_edges()
	if clean_book_id == "":
		return result

	for entry in BookEntryDB.get_entries_by_book(clean_book_id):
		if entry == null:
			continue
		if unlocked_entry_ids.has(entry.entry_id.strip_edges()):
			result.append(entry)
	return result


func get_unread_readable_entry_count_by_book(book_id: String) -> int:
	var count := 0
	for entry in get_readable_entries_by_book(book_id):
		if entry != null and not is_entry_read(entry.entry_id):
			count += 1
	return count


func is_book_visible_in_readbook(book: BookData) -> bool:
	if book == null or not book.visible_by_default or not book.can_read_at_night():
		return false
	if INITIAL_BOOK_IDS.has(book.book_id.strip_edges()):
		return true
	if book.is_herb_book() and not book.get_herb_unlock_order().is_empty():
		return true
	return not get_readable_entries_by_book(book.book_id).is_empty()


func _merge_progress(progress: Dictionary) -> bool:
	var changed := false
	var saved_unlocked_entries = progress.get("unlocked_entry_ids", {})
	var saved_read_entries = progress.get("read_entry_ids", {})

	changed = _merge_ids(unlocked_entry_ids, saved_unlocked_entries) or changed
	changed = _merge_ids(read_entry_ids, saved_read_entries) or changed
	# 已读条目必定曾经解锁；旧存档也可能只保留了已读标记。
	changed = _merge_ids(unlocked_entry_ids, saved_read_entries) or changed

	var herb_sources: Array = [
		progress.get("unlocked_herb_ids", {}),
		progress.get("clinical_log_unlocked_herb_ids", {}),
	]
	var formula_sources: Array = [
		progress.get("unlocked_formula_ids", {}),
		progress.get("clinical_log_unlocked_formula_ids", {}),
	]

	var disease_sources: Array = [
		progress.get("unlocked_disease_ids", {}),
		progress.get("clinical_log_unlocked_disease_ids", {}),
	]
	# 使用 UnlockManager 已依赖的 get_all_entries()，兼容现有数据库实现。
	var all_entries: Array[BookEntryData] = BookEntryDB.get_all_entries()
	for entry in all_entries:
		if entry is HerbBookEntryData:
			var herb_entry := entry as HerbBookEntryData
			if _any_source_has_id(herb_sources, herb_entry.herb_id):
				changed = _add_id(unlocked_entry_ids, herb_entry.entry_id) or changed
		elif entry is FormulaBookEntryData:
			var formula_entry := entry as FormulaBookEntryData
			if _any_source_has_id(formula_sources, formula_entry.formula_id):
				changed = _add_id(unlocked_entry_ids, formula_entry.entry_id) or changed
		elif entry is DiseaseBookEntryData:
			var disease_entry := entry as DiseaseBookEntryData
			if _any_source_has_id(disease_sources, disease_entry.disease_id):
				changed = _add_id(unlocked_entry_ids, disease_entry.entry_id) or changed

	return changed


func _any_source_has_id(sources: Array, id: String) -> bool:
	for source in sources:
		if _source_has_id(source, id):
			return true
	return false


func _source_has_id(source, id: String) -> bool:
	var clean_id := id.strip_edges()
	if clean_id == "":
		return false
	if typeof(source) == TYPE_DICTIONARY:
		return bool(source.get(clean_id, false))
	if typeof(source) == TYPE_ARRAY:
		return source.has(clean_id)
	return false


func _merge_ids(target: Dictionary, source) -> bool:
	var changed := false
	if typeof(source) == TYPE_DICTIONARY:
		for key in source.keys():
			if bool(source[key]):
				changed = _add_id(target, String(key)) or changed
	elif typeof(source) == TYPE_ARRAY:
		for value in source:
			changed = _add_id(target, String(value)) or changed
	return changed


func _add_id(target: Dictionary, value: String) -> bool:
	var clean_id := value.strip_edges()
	if clean_id == "" or target.has(clean_id):
		return false
	target[clean_id] = true
	return true


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	unlocked_entry_ids.clear()
	read_entry_ids.clear()

	if _load_archive_file(ARCHIVE_PATH):
		return
	if _load_archive_file(BACKUP_PATH):
		push_warning("总图鉴主文件无法读取，已从备份恢复。")


func _load_archive_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or typeof(json.data) != TYPE_DICTIONARY:
		return false

	var data: Dictionary = json.data
	unlocked_entry_ids = _bool_dictionary(data.get("unlocked_entry_ids", {}))
	read_entry_ids = _bool_dictionary(data.get("read_entry_ids", {}))
	# 防止不完整文件造成“已读但不可见”。
	_merge_ids(unlocked_entry_ids, read_entry_ids)
	return true


func _bool_dictionary(source) -> Dictionary:
	var result: Dictionary = {}
	if typeof(source) != TYPE_DICTIONARY:
		return result
	for key in source.keys():
		var clean_id := String(key).strip_edges()
		if clean_id != "" and bool(source[key]):
			result[clean_id] = true
	return result


func _save_archive() -> bool:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入总图鉴临时文件：%s" % TEMP_PATH)
		return false

	file.store_string(JSON.stringify({
		"version": ARCHIVE_VERSION,
		"unlocked_entry_ids": unlocked_entry_ids,
		"read_entry_ids": read_entry_ids,
	}))
	file.close()

	var main_absolute := ProjectSettings.globalize_path(ARCHIVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_PATH)
	var had_previous_file := FileAccess.file_exists(ARCHIVE_PATH)

	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(backup_absolute)
	if had_previous_file:
		var backup_error := DirAccess.rename_absolute(main_absolute, backup_absolute)
		if backup_error != OK:
			push_error("无法备份总图鉴文件，错误码：%d" % backup_error)
			return false

	var commit_error := DirAccess.rename_absolute(temp_absolute, main_absolute)
	if commit_error != OK:
		if had_previous_file and FileAccess.file_exists(BACKUP_PATH):
			DirAccess.rename_absolute(backup_absolute, main_absolute)
		push_error("无法提交总图鉴文件，错误码：%d" % commit_error)
		return false

	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(backup_absolute)
	return true
