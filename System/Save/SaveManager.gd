extends Node

# =========================================================
# SaveManager
# 当前存档结构：
# 1号槽 = 自动存档
# 2～5号槽 = 手动存档
# 所有手动档共用同一个自动存档。
#
# 自动存档继续沿用原有“白天结束 / 夜晚结束”阶段保存机制，
# 自动档始终写入 1 号槽。
#
# 手动保存规则：
# - 白天：保存“本日刚开始”的状态（即上一夜结束后的状态）
# - 夜晚：保存当前实时状态
# =========================================================


# =========================================================
# 存档配置
# =========================================================
const SAVE_VERSION: int = 1
const SAVE_SLOT_COUNT: int = 5

const AUTO_SAVE_SLOT: int = 1
const MANUAL_SAVE_FIRST_SLOT: int = 2
const MANUAL_SAVE_LAST_SLOT: int = 5

const AUTO_SAVE_PATH: String = "user://save_auto.json"
const MANUAL_SAVE_PATH_TEMPLATE: String = "user://save_manual_%d.json"

const SAVE_TEMP_SUFFIX: String = ".tmp"
const SAVE_BACKUP_SUFFIX: String = ".bak"

# 旧版三槽位存档，仅用于兼容读取 / 清理。
const LEGACY_SLOT_PATH_TEMPLATE: String = "user://save_slot_%d.json"

# 更早的旧版单存档路径，仅用于兼容读取 / 清理。
const LEGACY_SAVE_PATH: String = "user://save_game.json"

# 后台存档工作器：只处理纯数据序列化和文件 I/O。
const SaveWorkerScript = preload("res://System/Save/SaveWorker.gd")
const GLOBAL_READBOOK_ARCHIVE_SCRIPT = preload(
	"res://System/Book/Book/GlobalReadBookArchive.gd"
)

# 保留此字段供旧代码兼容；新结构下它只表示“最近一次读取/显式操作的槽位”。
# 自动存档永远固定写入 AUTO_SAVE_SLOT，不受此值影响。
var current_slot_index: int = AUTO_SAVE_SLOT

# 白天手动保存必须使用“当天刚开始”的快照，不能保存白天进行中的诊疗状态。
var _day_start_checkpoint: Dictionary = {}

# =========================================================
# 后台自动存档状态
# =========================================================
var _save_thread: Thread = null
var _active_save_worker: RefCounted = null
var _active_async_request: Dictionary = {}
var _pending_async_requests: Array[Dictionary] = []


func _process(_delta: float) -> void:
	_poll_async_save()


func _exit_tree() -> void:
	# Thread 销毁前必须 wait_to_finish()；退出游戏时确保最后一次自动存档真正落盘。
	flush_async_saves()


# =========================================================
# 槽位定义
# =========================================================
func is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 1 and slot_index <= SAVE_SLOT_COUNT


func is_auto_slot(slot_index: int) -> bool:
	return slot_index == AUTO_SAVE_SLOT


func is_manual_slot(slot_index: int) -> bool:
	return (
		slot_index >= MANUAL_SAVE_FIRST_SLOT
		and slot_index <= MANUAL_SAVE_LAST_SLOT
	)


func get_slot_display_label(slot_index: int) -> String:
	if is_auto_slot(slot_index):
		return "自动存档"

	if is_manual_slot(slot_index):
		return "手动存档 %d" % (slot_index - 1)

	return "无效存档"


# =========================================================
# 存档路径
# =========================================================
func get_save_path(slot_index: int = -1) -> String:
	if slot_index <= 0:
		slot_index = AUTO_SAVE_SLOT

	if is_auto_slot(slot_index):
		return AUTO_SAVE_PATH

	if is_manual_slot(slot_index):
		return MANUAL_SAVE_PATH_TEMPLATE % slot_index

	return ""


func _get_legacy_save_paths(slot_index: int) -> Array[String]:
	var result: Array[String] = []

	# 旧版只有 1～3 号槽。
	if slot_index >= 1 and slot_index <= 3:
		result.append(LEGACY_SLOT_PATH_TEMPLATE % slot_index)

	# 最早的单存档只映射到现在的自动档。
	if slot_index == AUTO_SAVE_SLOT:
		result.append(LEGACY_SAVE_PATH)

	return result


func _resolve_existing_save_path(slot_index: int) -> String:
	if not is_valid_slot(slot_index):
		return ""

	var save_path := get_save_path(slot_index)
	if not save_path.is_empty():
		if not _recover_interrupted_save(save_path):
			push_warning("检查存档失败：无法恢复上次中断的存档事务：" + save_path)
			return ""

		if FileAccess.file_exists(save_path):
			return save_path

	for legacy_path in _get_legacy_save_paths(slot_index):
		if FileAccess.file_exists(legacy_path):
			return legacy_path

	return ""


# =========================================================
# 查询存档
# =========================================================
func has_save(slot_index: int = -1) -> bool:
	# 查询磁盘状态前先收尾后台任务，避免菜单看到旧档。
	flush_async_saves()

	if slot_index <= 0:
		slot_index = AUTO_SAVE_SLOT

	return not _resolve_existing_save_path(slot_index).is_empty()


func has_any_save() -> bool:
	flush_async_saves()

	for slot_index in range(1, SAVE_SLOT_COUNT + 1):
		if not _resolve_existing_save_path(slot_index).is_empty():
			return true

	return false


# 读取所有有效存档里的 progress，用于把旧档解锁内容迁入全局典籍。
# 只读 JSON，不会把任何一档加载到运行中的 GameTime / Unlock / StoryManager。
func get_all_saved_progress_data() -> Array[Dictionary]:
	flush_async_saves()
	var result: Array[Dictionary] = []
	for slot_index in range(1, SAVE_SLOT_COUNT + 1):
		var progress := _read_saved_progress_for_slot(slot_index)
		if not progress.is_empty():
			result.append(progress)
	return result


func _read_saved_progress_for_slot(slot_index: int) -> Dictionary:
	var save_path := _resolve_existing_save_path(slot_index)
	if save_path.is_empty():
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}

	var save_data: Dictionary = json.data
	if typeof(save_data.get("progress", null)) != TYPE_DICTIONARY:
		return {}
	return save_data["progress"].duplicate(true)


# =========================================================
# 快照
# =========================================================
func _make_current_save_data(slot_index: int = AUTO_SAVE_SLOT) -> Dictionary:
	var progress_data: Dictionary = Unlock.get_save_data().duplicate(true)
	var story_data: Dictionary = StoryManager.get_save_data().duplicate(true)
	var phase := String(GameTime.current_phase)
	var day := int(GameTime.current_day)

	return {
		"version": SAVE_VERSION,
		"meta": _make_save_meta_for_state(slot_index, day, phase),
		"time": {
			"current_day": day,
			"current_phase": phase
		},
		"progress": progress_data,
		"story": story_data
	}


func _prepare_snapshot_for_slot(
	source_data: Dictionary,
	slot_index: int
) -> Dictionary:
	var save_data: Dictionary = source_data.duplicate(true)
	save_data["version"] = SAVE_VERSION

	var time_data: Dictionary = {}
	if save_data.has("time") and typeof(save_data["time"]) == TYPE_DICTIONARY:
		time_data = save_data["time"]
	else:
		time_data = save_data

	var day := int(time_data.get("current_day", GameTime.current_day))
	var phase := String(time_data.get("current_phase", GameTime.current_phase))
	save_data["meta"] = _make_save_meta_for_state(slot_index, day, phase)

	return save_data


func capture_day_start_checkpoint() -> bool:
	if GameTime == null or not GameTime.is_day():
		return false

	_day_start_checkpoint = _make_current_save_data(AUTO_SAVE_SLOT).duplicate(true)
	return true


func clear_day_start_checkpoint() -> void:
	_day_start_checkpoint.clear()


func has_day_start_checkpoint() -> bool:
	return not _day_start_checkpoint.is_empty()


# =========================================================
# 保存请求构建
# =========================================================
func _make_save_request_from_data(
	slot_index: int,
	context: String,
	source_data: Dictionary
) -> Dictionary:
	var save_data := _prepare_snapshot_for_slot(source_data, slot_index)

	var time_data: Dictionary = {}
	if save_data.has("time") and typeof(save_data["time"]) == TYPE_DICTIONARY:
		time_data = save_data["time"]

	var day := int(time_data.get("current_day", GameTime.current_day))
	var phase := String(time_data.get("current_phase", GameTime.current_phase))

	var save_path := get_save_path(slot_index)
	var temp_path := save_path + SAVE_TEMP_SUFFIX
	var backup_path := save_path + SAVE_BACKUP_SUFFIX

	return {
		"slot_index": slot_index,
		"context": context,
		"day": day,
		"phase": phase,
		"save_data": save_data,
		"save_path": save_path,
		"temp_path": temp_path,
		"backup_path": backup_path,
		"save_absolute": ProjectSettings.globalize_path(save_path),
		"temp_absolute": ProjectSettings.globalize_path(temp_path),
		"backup_absolute": ProjectSettings.globalize_path(backup_path)
	}


func _make_save_request(slot_index: int, context: String) -> Dictionary:
	return _make_save_request_from_data(
		slot_index,
		context,
		_make_current_save_data(slot_index)
	)


# =========================================================
# 同步保存（兼容接口）
# =========================================================
func save_game(slot_index: int = -1) -> bool:
	# 不指定槽位时默认保存到自动档，避免“读取了某个手动档后，
	# 后续旧代码又把自动保存写回那个手动档”。
	if slot_index <= 0:
		slot_index = AUTO_SAVE_SLOT

	if not is_valid_slot(slot_index):
		print("存档失败：无效槽位 %d" % slot_index)
		return false

	# 同步接口返回时要求真正落盘，因此先等待后台自动存档。
	if not flush_async_saves():
		push_warning("同步存档前发现后台存档失败，将继续尝试写入当前快照。")

	current_slot_index = slot_index

	var request := _make_save_request(slot_index, "同步存档")
	var worker: RefCounted = SaveWorkerScript.new()
	var result = worker.call("write_request", request)

	if typeof(result) != TYPE_DICTIONARY:
		push_error("存档失败：SaveWorker 返回了无效结果。")
		return false

	var result_dict: Dictionary = result
	_handle_async_save_result(result_dict, false)
	return bool(result_dict.get("ok", false))


# =========================================================
# 自动保存
# =========================================================
func save_auto_game_async(context: String = "自动存档") -> bool:
	# 如果上一线程刚结束但还没等到下一帧 _process() 回收，先无阻塞回收。
	_poll_async_save()

	var save_data := _make_current_save_data(AUTO_SAVE_SLOT)

	# 夜晚结束进入白天后生成的自动档，同时就是新一天的“日初检查点”。
	# 新游戏第一天的日初检查点由 Main 在初始化完成后主动 capture。
	if GameTime.is_day():
		_day_start_checkpoint = save_data.duplicate(true)

	var request := _make_save_request_from_data(
		AUTO_SAVE_SLOT,
		context,
		save_data
	)

	if _save_thread != null and _save_thread.is_started():
		_queue_latest_async_request(request)
		return true

	return _start_async_save_request(request)


# 保留旧接口，Main 新代码会调用 save_auto_game_async()。
func save_game_async(
	slot_index: int = -1,
	context: String = "自动存档"
) -> bool:
	if slot_index <= 0 or slot_index == AUTO_SAVE_SLOT:
		return save_auto_game_async(context)

	if not is_valid_slot(slot_index):
		push_warning("后台存档失败：无效槽位 %d" % slot_index)
		return false

	_poll_async_save()
	current_slot_index = slot_index
	var request := _make_save_request(slot_index, context)

	if _save_thread != null and _save_thread.is_started():
		_queue_latest_async_request(request)
		return true

	return _start_async_save_request(request)


# =========================================================
# 手动保存
# =========================================================
func save_manual_game(slot_index: int) -> bool:
	if not is_manual_slot(slot_index):
		push_warning("手动保存失败：%d 号槽不是手动存档槽。" % slot_index)
		return false

	var save_data: Dictionary

	if GameTime.is_day():
		# 白天绝不保存当前诊疗进行中的状态，只保存该天刚开始时的快照。
		if _day_start_checkpoint.is_empty():
			push_warning("手动保存失败：当前白天缺少日初检查点。")
			return false

		save_data = _day_start_checkpoint.duplicate(true)
	else:
		# 夜晚允许保存当前实时状态。
		save_data = _make_current_save_data(slot_index)

	current_slot_index = slot_index
	var request := _make_save_request_from_data(
		slot_index,
		"手动保存",
		save_data
	)

	var worker: RefCounted = SaveWorkerScript.new()
	var result = worker.call("write_request", request)

	if typeof(result) != TYPE_DICTIONARY:
		push_error("手动保存失败：SaveWorker 返回了无效结果。")
		return false

	var result_dict: Dictionary = result
	_handle_async_save_result(result_dict, false)
	return bool(result_dict.get("ok", false))


func is_async_save_busy() -> bool:
	return (
		(_save_thread != null and _save_thread.is_started())
		or not _pending_async_requests.is_empty()
	)


# 需要“此函数返回后磁盘一定是最新状态”的场景调用：
# - 读档
# - 删除存档
# - 存档菜单读取摘要
# - 同步 save_game()
# - 游戏退出
func flush_async_saves() -> bool:
	var all_ok := true

	if _save_thread != null and _save_thread.is_started():
		var active_result = _save_thread.wait_to_finish()
		_save_thread = null
		_active_save_worker = null
		_active_async_request.clear()

		if typeof(active_result) == TYPE_DICTIONARY:
			var active_result_dict: Dictionary = active_result
			_handle_async_save_result(active_result_dict, true)
			all_ok = all_ok and bool(active_result_dict.get("ok", false))
		else:
			push_error("后台存档线程返回了无效结果。")
			all_ok = false

	while not _pending_async_requests.is_empty():
		var request: Dictionary = _pending_async_requests.pop_front()
		var worker: RefCounted = SaveWorkerScript.new()
		var pending_result = worker.call("write_request", request)

		if typeof(pending_result) != TYPE_DICTIONARY:
			push_error("等待中的后台存档返回了无效结果。")
			all_ok = false
			continue

		var pending_result_dict: Dictionary = pending_result
		_handle_async_save_result(pending_result_dict, true)
		all_ok = all_ok and bool(pending_result_dict.get("ok", false))

	return all_ok


func _queue_latest_async_request(request: Dictionary) -> void:
	var slot_index := int(request.get("slot_index", -1))

	# 同一个槽位如果已经有等待中的请求，旧快照没有继续写盘的价值，直接替换成最新状态。
	for index in range(_pending_async_requests.size() - 1, -1, -1):
		if int(_pending_async_requests[index].get("slot_index", -1)) == slot_index:
			_pending_async_requests[index] = request
			return

	_pending_async_requests.append(request)


func _start_async_save_request(request: Dictionary) -> bool:
	if _save_thread != null and _save_thread.is_started():
		_queue_latest_async_request(request)
		return true

	_save_thread = Thread.new()
	_active_save_worker = SaveWorkerScript.new()
	_active_async_request = request

	var callable := Callable(_active_save_worker, "write_request").bind(request)
	var start_error := _save_thread.start(callable, Thread.PRIORITY_LOW)

	if start_error == OK:
		return true

	# 极少数系统若无法创建线程，回退同步写入，优先保证存档可靠性。
	push_warning("无法启动后台存档线程，回退为同步存档。错误码：%d" % start_error)
	_save_thread = null
	_active_save_worker = null
	_active_async_request.clear()

	var fallback_worker: RefCounted = SaveWorkerScript.new()
	var fallback_result = fallback_worker.call("write_request", request)
	if typeof(fallback_result) != TYPE_DICTIONARY:
		push_error("同步回退存档返回了无效结果。")
		return false

	var fallback_result_dict: Dictionary = fallback_result
	_handle_async_save_result(fallback_result_dict, false)
	return bool(fallback_result_dict.get("ok", false))


func _poll_async_save() -> void:
	if _save_thread == null or not _save_thread.is_started():
		# 正常情况下 pending 都会由上一任务完成时接力启动；
		# 这里也做兜底，处理线程创建失败后的剩余队列。
		if not _pending_async_requests.is_empty():
			_start_next_queued_async_save()
		return

	# is_alive() == false 时 wait_to_finish() 不会阻塞主线程。
	if _save_thread.is_alive():
		return

	var result = _save_thread.wait_to_finish()
	_save_thread = null
	_active_save_worker = null
	_active_async_request.clear()

	if typeof(result) == TYPE_DICTIONARY:
		var result_dict: Dictionary = result
		_handle_async_save_result(result_dict, true)
	else:
		push_error("后台存档线程返回了无效结果。")

	_start_next_queued_async_save()


func _start_next_queued_async_save() -> void:
	if _pending_async_requests.is_empty():
		return

	var next_request: Dictionary = _pending_async_requests.pop_front()
	_start_async_save_request(next_request)


func _handle_async_save_result(result: Dictionary, was_async: bool) -> void:
	var slot_index := int(result.get("slot_index", -1))
	var day := int(result.get("day", 1))
	var phase := String(result.get("phase", ""))
	var context := String(result.get("context", ""))

	if bool(result.get("ok", false)):
		# 成功落盘后将这份存档的解锁并入全局典籍；不会反向写入本局进度。
		var progress := _read_saved_progress_for_slot(slot_index)
		if not progress.is_empty():
			var global_archive = GLOBAL_READBOOK_ARCHIVE_SCRIPT.new()
			global_archive.merge_progress(progress)

		if OS.is_debug_build():
			var mode_text := "后台" if was_async else "同步"
			print("[%s存档] 完成：槽位 %d，第 %d 天，阶段：%s%s" % [
				mode_text,
				slot_index,
				day,
				phase,
				("，" + context) if not context.is_empty() else ""
			])
		return

	var error_text := String(result.get("error", "未知错误"))
	var context_prefix := (context + "：") if not context.is_empty() else ""
	push_error("%s存档失败（槽位 %d）：%s" % [context_prefix, slot_index, error_text])


func _commit_temp_save(save_path: String, temp_path: String) -> bool:
	var backup_path: String = save_path + SAVE_BACKUP_SUFFIX
	var save_absolute: String = ProjectSettings.globalize_path(save_path)
	var temp_absolute: String = ProjectSettings.globalize_path(temp_path)
	var backup_absolute: String = ProjectSettings.globalize_path(backup_path)
	var had_previous_save: bool = FileAccess.file_exists(save_path)

	# 先把旧档移动成备份，让临时文件移动时的目标路径保持不存在。
	if had_previous_save:
		var backup_error: Error = DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			_remove_file_if_exists(temp_path)
			print("存档失败：无法备份旧存档：", save_path, "，错误码：", backup_error)
			return false

	var replace_error: Error = DirAccess.rename_absolute(temp_absolute, save_absolute)
	if replace_error != OK:
		# 正式替换失败时，优先把旧档恢复回原路径。
		if had_previous_save and FileAccess.file_exists(backup_path):
			var restore_error: Error = DirAccess.rename_absolute(backup_absolute, save_absolute)
			if restore_error != OK:
				push_error("存档替换和旧档恢复都失败。旧档仍保留在：%s，恢复错误码：%d" % [
					backup_path,
					restore_error
				])

		_remove_file_if_exists(temp_path)
		print("存档失败：无法替换正式存档：", save_path, "，错误码：", replace_error)
		return false

	# 新存档已经就位，旧备份可以清理。清理失败不影响本次存档有效性，
	# 下次访问该槽位时会再次清理。
	if had_previous_save and not _remove_file_if_exists(backup_path):
		push_warning("新存档已写入，但旧备份暂时无法删除：" + backup_path)

	return true


func _recover_interrupted_save(save_path: String) -> bool:
	var temp_path: String = save_path + SAVE_TEMP_SUFFIX
	var backup_path: String = save_path + SAVE_BACKUP_SUFFIX

	# 正式存档存在时，以正式存档为准，清理上次事务遗留文件。
	if FileAccess.file_exists(save_path):
		var temp_removed: bool = _remove_file_if_exists(temp_path)
		var backup_removed: bool = _remove_file_if_exists(backup_path)
		return temp_removed and backup_removed

	# 正式存档不存在但备份存在，说明上次可能中断在“旧档改名”之后。
	# 此时优先恢复旧档，不冒险使用尚未确认完整的临时文件。
	if FileAccess.file_exists(backup_path):
		var restore_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(backup_path),
			ProjectSettings.globalize_path(save_path)
		)
		if restore_error != OK:
			push_error("无法恢复中断事务留下的旧存档：%s，错误码：%d" % [
				backup_path,
				restore_error
			])
			return false

		_remove_file_if_exists(temp_path)
		return true

	# 第一次保存时如果在临时文件写完后中断，验证 JSON 完整性后再接管为正式存档。
	if FileAccess.file_exists(temp_path):
		if _is_valid_save_file(temp_path):
			var promote_error: Error = DirAccess.rename_absolute(
				ProjectSettings.globalize_path(temp_path),
				ProjectSettings.globalize_path(save_path)
			)
			if promote_error == OK:
				return true

			push_error("无法恢复中断事务留下的临时存档：%s，错误码：%d" % [
				temp_path,
				promote_error
			])
			return false

		return _remove_file_if_exists(temp_path)

	return true


func _is_valid_save_file(save_path: String) -> bool:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false

	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(json_text) != OK:
		return false

	return typeof(json.data) == TYPE_DICTIONARY


func _remove_file_if_exists(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true

	var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return remove_error == OK

# =========================================================
# 读取游戏
# =========================================================
func load_game(slot_index: int = -1) -> bool:
	# 读档前必须保证最后一次后台自动存档已经提交。
	if not flush_async_saves():
		push_warning("读档前有后台存档失败，将继续尝试读取磁盘上最后一个有效存档。")

	if slot_index <= 0:
		slot_index = AUTO_SAVE_SLOT

	if not is_valid_slot(slot_index):
		print("读档失败：无效槽位 %d" % slot_index)
		return false

	var save_path := _resolve_existing_save_path(slot_index)
	if save_path.is_empty():
		print("读档失败：%s 没有存档" % get_slot_display_label(slot_index))
		return false

	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		print("读档失败：无法打开存档文件：", save_path)
		return false

	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(json_text)
	if error != OK:
		print("读档失败：JSON 解析错误")
		return false

	var save_data = json.data
	if typeof(save_data) != TYPE_DICTIONARY:
		print("读档失败：存档数据格式错误")
		return false

	current_slot_index = slot_index

	_load_time_data(save_data)
	_load_progress_data(save_data)
	_load_story_data(save_data)

	# 白天档本身就是“当天开始状态”，读入后重建日初检查点。
	# 夜晚档不需要日初检查点；等夜晚结束进入下一天时由自动保存重新建立。
	if GameTime.is_day():
		_day_start_checkpoint = _make_current_save_data(AUTO_SAVE_SLOT).duplicate(true)
	else:
		_day_start_checkpoint.clear()

	print("读档完成：%s，第 %d 天，阶段：%s" % [
		get_slot_display_label(slot_index),
		GameTime.current_day,
		GameTime.current_phase
	])

	return true


func _load_time_data(save_data: Dictionary) -> void:
	var time_data: Dictionary = {}

	# 新格式
	if save_data.has("time") and typeof(save_data["time"]) == TYPE_DICTIONARY:
		time_data = save_data["time"]
	else:
		# 旧格式兼容
		time_data = save_data

	# 读取当前天数
	if time_data.has("current_day"):
		GameTime.current_day = int(time_data["current_day"])
	else:
		GameTime.current_day = 1

	# 读取当前时段
	if time_data.has("current_phase"):
		GameTime.current_phase = str(time_data["current_phase"])
	else:
		GameTime.current_phase = GameTime.PHASE_DAY

	# 防止存档里的阶段值写错
	if GameTime.current_phase != GameTime.PHASE_DAY and GameTime.current_phase != GameTime.PHASE_NIGHT:
		GameTime.current_phase = GameTime.PHASE_DAY

	# 防止天数异常
	if GameTime.current_day < 1:
		GameTime.current_day = 1


# =========================================================
# 读取进度数据
# =========================================================
func _load_progress_data(save_data: Dictionary) -> void:
	# 没有 progress 字段，说明是旧存档
	# 这时重置进度，避免保留内存里的旧数据
	if not save_data.has("progress"):
		Unlock.reset_progress()
		return

	# progress 字段格式不对，也重置进度
	if typeof(save_data["progress"]) != TYPE_DICTIONARY:
		Unlock.reset_progress()
		return

	# 恢复解锁和阅读进度
	Unlock.load_save_data(save_data["progress"])


# =========================================================
# 读取剧情数据
# =========================================================
func _load_story_data(save_data: Dictionary) -> void:
	# 没有 story 字段，说明是旧存档。
	# 这时清空剧情播放记录，避免内存残留。
	if not save_data.has("story"):
		StoryManager.load_save_data({})
		return

	# story 字段格式不对，也重置剧情状态。
	if typeof(save_data["story"]) != TYPE_DICTIONARY:
		StoryManager.load_save_data({})
		return

	# 恢复剧情播放记录。
	StoryManager.load_save_data(save_data["story"])

# =========================================================
# 删除存档
# =========================================================
func _remove_save_transaction_files(save_path: String) -> bool:
	if save_path.is_empty():
		return true

	var all_ok := true
	all_ok = _remove_file_if_exists(save_path) and all_ok
	all_ok = _remove_file_if_exists(save_path + SAVE_TEMP_SUFFIX) and all_ok
	all_ok = _remove_file_if_exists(save_path + SAVE_BACKUP_SUFFIX) and all_ok
	return all_ok


func delete_save(slot_index: int = -1) -> bool:
	flush_async_saves()

	if slot_index <= 0:
		slot_index = AUTO_SAVE_SLOT

	if not is_valid_slot(slot_index):
		print("删除存档失败：无效槽位 %d" % slot_index)
		return false

	var all_ok := true
	var removed_any := false

	var save_path := get_save_path(slot_index)
	if FileAccess.file_exists(save_path):
		removed_any = true
	if not _remove_save_transaction_files(save_path):
		all_ok = false

	for legacy_path in _get_legacy_save_paths(slot_index):
		if FileAccess.file_exists(legacy_path):
			removed_any = true
		if not _remove_save_transaction_files(legacy_path):
			all_ok = false

	if all_ok and removed_any:
		print("已删除：%s" % get_slot_display_label(slot_index))

	return all_ok and removed_any


func delete_all_saves() -> bool:
	# 新游戏会清空自动档、全部手动档，以及旧版兼容存档。
	flush_async_saves()

	var all_ok := true
	var paths: Array[String] = []

	for slot_index in range(1, SAVE_SLOT_COUNT + 1):
		var new_path := get_save_path(slot_index)
		if not new_path.is_empty() and not paths.has(new_path):
			paths.append(new_path)

		for legacy_path in _get_legacy_save_paths(slot_index):
			if not legacy_path.is_empty() and not paths.has(legacy_path):
				paths.append(legacy_path)

	for save_path in paths:
		if not _remove_save_transaction_files(save_path):
			all_ok = false

	_day_start_checkpoint.clear()
	current_slot_index = AUTO_SAVE_SLOT

	if all_ok:
		print("已清除自动存档和全部手动存档。")

	return all_ok


# =========================================================
# 存档摘要
# =========================================================
func get_save_meta(slot_index: int) -> Dictionary:
	# 菜单显示摘要前同步收尾后台自动存档。
	flush_async_saves()

	if not is_valid_slot(slot_index):
		return {
			"slot_index": slot_index,
			"exists": false,
			"slot_label": "无效存档",
			"display_name": "无效槽位"
		}

	var slot_label := get_slot_display_label(slot_index)
	var save_path := _resolve_existing_save_path(slot_index)

	if save_path.is_empty():
		return {
			"slot_index": slot_index,
			"exists": false,
			"slot_label": slot_label,
			"display_name": "空存档"
		}

	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {
			"slot_index": slot_index,
			"exists": false,
			"slot_label": slot_label,
			"display_name": "读取失败"
		}

	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var error: Error = json.parse(json_text)
	if error != OK:
		return {
			"slot_index": slot_index,
			"exists": false,
			"slot_label": slot_label,
			"display_name": "损坏存档"
		}

	var save_data = json.data
	if typeof(save_data) != TYPE_DICTIONARY:
		return {
			"slot_index": slot_index,
			"exists": false,
			"slot_label": slot_label,
			"display_name": "损坏存档"
		}

	var meta: Dictionary = {}
	if save_data.has("meta") and typeof(save_data["meta"]) == TYPE_DICTIONARY:
		meta = save_data["meta"].duplicate(true)
	else:
		meta = _make_meta_from_save_data(slot_index, save_data)

	meta["slot_index"] = slot_index
	meta["slot_label"] = slot_label
	meta["exists"] = true
	return meta


func get_all_save_meta() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for slot_index in range(1, SAVE_SLOT_COUNT + 1):
		result.append(get_save_meta(slot_index))

	return result


# =========================================================
# 生成存档摘要
# =========================================================
func _make_save_meta(slot_index: int) -> Dictionary:
	return _make_save_meta_for_state(
		slot_index,
		GameTime.current_day,
		String(GameTime.current_phase)
	)


func _make_save_meta_for_state(
	slot_index: int,
	day: int,
	phase: String
) -> Dictionary:
	var phase_text := _get_phase_display_text(phase)

	return {
		"slot_index": slot_index,
		"slot_label": get_slot_display_label(slot_index),
		"save_time": Time.get_datetime_string_from_system(false, true),
		"display_name": "%s %s" % [
			_get_day_display_text(day),
			phase_text
		],
		"current_day": day,
		"current_phase": phase
	}


# =========================================================
# 从旧存档数据生成摘要
# =========================================================
func _make_meta_from_save_data(slot_index: int, save_data: Dictionary) -> Dictionary:
	var time_data: Dictionary = {}

	if save_data.has("time") and typeof(save_data["time"]) == TYPE_DICTIONARY:
		time_data = save_data["time"]
	else:
		time_data = save_data

	var current_day: int = int(time_data.get("current_day", 1))
	var current_phase: String = str(time_data.get("current_phase", GameTime.PHASE_DAY))
	var phase_text: String = _get_phase_display_text(current_phase)

	return {
		"slot_index": slot_index,
		"slot_label": get_slot_display_label(slot_index),
		"save_time": "",
		"display_name": "%s %s" % [
			_get_day_display_text(current_day),
			phase_text
		],
		"current_day": current_day,
		"current_phase": current_phase
	}


func _get_day_display_text(day_index: int) -> String:
	if GameTime.has_method("get_day_text_by_index"):
		return GameTime.get_day_text_by_index(day_index)

	if GameTime.has_method("get_day_text"):
		return GameTime.get_day_text()

	return "第 %d 天" % day_index


# =========================================================
# 阶段显示文本
# =========================================================
func _get_phase_display_text(phase: String) -> String:
	if phase == GameTime.PHASE_NIGHT:
		return "夜晚"

	return "白天"
