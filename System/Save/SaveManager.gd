extends Node

# =========================================================
# SaveManager
# 负责游戏存档：
# 1. 保存游戏时间
# 2. 读取游戏时间
# 3. 保存解锁进度
# 4. 读取解锁进度
# 5. 保存剧情播放状态
# 6. 支持多个存档槽位
# =========================================================


# =========================================================
# 存档配置
# =========================================================
const SAVE_VERSION: int = 1
const SAVE_SLOT_COUNT: int = 3
const SAVE_PATH_TEMPLATE: String = "user://save_slot_%d.json"
const SAVE_TEMP_SUFFIX: String = ".tmp"
const SAVE_BACKUP_SUFFIX: String = ".bak"

# 旧版单存档路径，仅用于兼容读取旧存档。
const LEGACY_SAVE_PATH: String = "user://save_game.json"

# 后台存档工作器：只处理纯数据序列化和文件 I/O。
const SaveWorkerScript = preload("res://System/Save/SaveWorker.gd")

# 当前正在使用的槽位。
# 不传 slot_index 时，save_game / load_game / has_save / delete_save 默认使用这个槽位。
var current_slot_index: int = 1

# =========================================================
# 后台自动存档状态
# =========================================================
# save_game() 继续保留“同步落盘”语义，供需要立刻确认磁盘状态的旧代码使用。
# Main 的阶段自动存档改走 save_game_async()，避免把 JSON / flush 卡在切场景关键帧。
var _save_thread: Thread = null
var _active_save_worker: RefCounted = null
var _active_async_request: Dictionary = {}
var _pending_async_requests: Array[Dictionary] = []


func _process(_delta: float) -> void:
	_poll_async_save()


func _exit_tree() -> void:
	# Thread 销毁前必须 wait_to_finish()；退出游戏时确保最后一次存档真正落盘。
	flush_async_saves()


# =========================================================
# 判断槽位是否合法
# =========================================================
func is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 1 and slot_index <= SAVE_SLOT_COUNT


# =========================================================
# 获取指定槽位的存档路径
# =========================================================
func get_save_path(slot_index: int = -1) -> String:
	if slot_index <= 0:
		slot_index = current_slot_index

	return SAVE_PATH_TEMPLATE % slot_index


# =========================================================
# 判断是否存在存档
# =========================================================
func has_save(slot_index: int = -1) -> bool:
	# 查询磁盘状态前先收尾后台任务，避免菜单看到旧档。
	flush_async_saves()

	if slot_index <= 0:
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		return false

	var save_path: String = get_save_path(slot_index)
	if not _recover_interrupted_save(save_path):
		push_warning("检查存档失败：无法恢复上次中断的存档事务：" + save_path)
		return false

	if FileAccess.file_exists(save_path):
		return true

	# 兼容旧版单存档：只在 1 号槽判断旧路径。
	if slot_index == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH):
		return true

	return false


# =========================================================
# 保存游戏
# =========================================================
func save_game(slot_index: int = -1) -> bool:
	# 同步接口保持兼容：调用方返回时，数据已经真实写入磁盘。
	# 为避免和后台自动存档争用同一 .tmp / .bak，先等待后台队列清空。
	if not flush_async_saves():
		push_warning("同步存档前发现后台存档失败，将继续尝试写入当前快照。")

	if slot_index <= 0:
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		print("存档失败：无效槽位 %d" % slot_index)
		return false

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


# 非阻塞自动存档：
# 1. 主线程只创建一份纯数据快照；
# 2. JSON.stringify、FileAccess、flush、.tmp/.bak 原子替换全部在 Thread 中执行；
# 3. 同一槽位短时间连续请求时，只保留“当前正在写的一份 + 最新等待的一份”。
func save_game_async(slot_index: int = -1, context: String = "自动存档") -> bool:
	if slot_index <= 0:
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		push_warning("自动存档失败：无效槽位 %d" % slot_index)
		return false

	current_slot_index = slot_index

	# 如果上一线程已经结束但还没等到下一帧 _process() 回收，先无阻塞回收。
	_poll_async_save()

	var request := _make_save_request(slot_index, context)

	if _save_thread != null and _save_thread.is_started():
		_queue_latest_async_request(request)
		return true

	return _start_async_save_request(request)


func is_async_save_busy() -> bool:
	return (
		(_save_thread != null and _save_thread.is_started())
		or not _pending_async_requests.is_empty()
	)


# 需要“此函数返回后磁盘一定是最新状态”的场景调用：
# - 读档
# - 删除存档
# - 存档槽位菜单读取摘要
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

	# flush 本身就是一个显式同步点；剩余快照直接顺序写完，避免再启动线程后立刻等待。
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


func _make_save_request(slot_index: int, context: String) -> Dictionary:
	# 这里是唯一允许接触 Autoload / Node 状态的部分，始终在主线程运行。
	# duplicate(true) 把所有 Dictionary / Array 递归复制，后台线程不再共享运行时容器。
	var progress_data: Dictionary = Unlock.get_save_data().duplicate(true)
	var story_data: Dictionary = StoryManager.get_save_data().duplicate(true)
	var phase := String(GameTime.current_phase)
	var day := int(GameTime.current_day)

	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"meta": _make_save_meta(slot_index).duplicate(true),
		"time": {
			"current_day": day,
			"current_phase": phase
		},
		"progress": progress_data,
		"story": story_data
	}

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
		# 路径转换也在主线程完成，后台只使用已经准备好的字符串。
		"save_absolute": ProjectSettings.globalize_path(save_path),
		"temp_absolute": ProjectSettings.globalize_path(temp_path),
		"backup_absolute": ProjectSettings.globalize_path(backup_path)
	}


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
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		print("读档失败：无效槽位 %d" % slot_index)
		return false

	var save_path: String = get_save_path(slot_index)
	if not _recover_interrupted_save(save_path):
		print("读档失败：无法恢复上次中断的存档事务：", save_path)
		return false

	# 兼容旧版单存档：如果 1 号槽没有新存档，但旧路径存在，则读取旧存档。
	if not FileAccess.file_exists(save_path):
		if slot_index == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH):
			save_path = LEGACY_SAVE_PATH
		else:
			print("读档失败：槽位 %d 没有存档" % slot_index)
			return false

	# 打开存档文件，READ 表示读取模式
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)

	# 如果文件打开失败，读取失败
	if file == null:
		print("读档失败：无法打开存档文件：", save_path)
		return false

	# 读取全部文本
	var json_text: String = file.get_as_text()

	# 关闭文件
	file.close()

	# 解析 JSON
	var json: JSON = JSON.new()
	var error: Error = json.parse(json_text)

	# JSON 格式错误，读取失败
	if error != OK:
		print("读档失败：JSON 解析错误")
		return false

	# 获取解析后的数据
	var save_data = json.data

	# 如果解析结果不是 Dictionary，读取失败
	if typeof(save_data) != TYPE_DICTIONARY:
		print("读档失败：存档数据格式错误")
		return false

	current_slot_index = slot_index

	# 读取时间数据
	_load_time_data(save_data)

	# 读取进度数据
	_load_progress_data(save_data)

	# 读取剧情播放状态
	_load_story_data(save_data)

	print("读档完成：槽位 %d，第 %d 天，阶段：%s" % [
		slot_index,
		GameTime.current_day,
		GameTime.current_phase
	])

	return true


# =========================================================
# 读取时间数据
# 兼容两种格式：
# 1. 新格式：save_data["time"]["current_day"]
# 2. 旧格式：save_data["current_day"]
# =========================================================
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
# 以后做“重新开始游戏”按钮时会用到
# =========================================================
func delete_save(slot_index: int = -1) -> bool:
	# 删除前先结束可能正在写同一槽位的后台任务，避免文件竞争。
	flush_async_saves()

	if slot_index <= 0:
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		print("删除存档失败：无效槽位 %d" % slot_index)
		return false

	var slot_save_path: String = get_save_path(slot_index)
	if not _recover_interrupted_save(slot_save_path):
		print("删除存档失败：无法恢复上次中断的存档事务：", slot_save_path)
		return false
	var save_path: String = slot_save_path

	if not FileAccess.file_exists(save_path):
		# 兼容旧版单存档：只允许 1 号槽删除旧路径。
		if slot_index == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH):
			save_path = LEGACY_SAVE_PATH
		else:
			print("没有可删除的存档：槽位 %d" % slot_index)
			return false

	var err: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	if err != OK:
		print("删除存档失败：槽位 %d" % slot_index)
		return false

	# 删除新格式槽位时，同时清理可能遗留的事务文件。
	if save_path == slot_save_path:
		_remove_file_if_exists(slot_save_path + SAVE_TEMP_SUFFIX)
		_remove_file_if_exists(slot_save_path + SAVE_BACKUP_SUFFIX)

	print("已删除存档：槽位 %d" % slot_index)
	return true


# =========================================================
# 获取单个槽位的存档摘要
# 给存档选择界面显示用
# =========================================================
func get_save_meta(slot_index: int) -> Dictionary:
	# 存档菜单需要读取真实磁盘摘要；进入菜单时允许在这里同步收尾。
	flush_async_saves()

	if not is_valid_slot(slot_index):
		return {
			"slot_index": slot_index,
			"exists": false,
			"display_name": "无效槽位"
		}

	var save_path: String = get_save_path(slot_index)
	if not _recover_interrupted_save(save_path):
		return {
			"slot_index": slot_index,
			"exists": false,
			"display_name": "存档恢复失败"
		}

	# 兼容旧版单存档：只在 1 号槽读取旧路径摘要。
	if not FileAccess.file_exists(save_path):
		if slot_index == 1 and FileAccess.file_exists(LEGACY_SAVE_PATH):
			save_path = LEGACY_SAVE_PATH
		else:
			return {
				"slot_index": slot_index,
				"exists": false,
				"display_name": "空存档"
			}

	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {
			"slot_index": slot_index,
			"exists": false,
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
			"display_name": "损坏存档"
		}

	var save_data = json.data
	if typeof(save_data) != TYPE_DICTIONARY:
		return {
			"slot_index": slot_index,
			"exists": false,
			"display_name": "损坏存档"
		}

	var meta: Dictionary = {}
	if save_data.has("meta") and typeof(save_data["meta"]) == TYPE_DICTIONARY:
		meta = save_data["meta"].duplicate(true)
	else:
		meta = _make_meta_from_save_data(slot_index, save_data)

	meta["slot_index"] = slot_index
	meta["exists"] = true
	return meta


# =========================================================
# 获取全部槽位的存档摘要
# 给存档选择界面显示用
# =========================================================
func get_all_save_meta() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for slot_index in range(1, SAVE_SLOT_COUNT + 1):
		result.append(get_save_meta(slot_index))

	return result


# =========================================================
# 生成存档摘要
# =========================================================
func _make_save_meta(slot_index: int) -> Dictionary:
	var phase_text: String = _get_phase_display_text(GameTime.current_phase)

	return {
		"slot_index": slot_index,
		"save_time": Time.get_datetime_string_from_system(false, true),
		"display_name": "%s %s" % [
			GameTime.get_day_text(),
			phase_text
		],
		"current_day": GameTime.current_day,
		"current_phase": GameTime.current_phase
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
		"save_time": "",
		"display_name": "%s %s" % [_get_day_display_text(current_day), phase_text],
		"current_day": current_day,
		"current_phase": current_phase
	}


# =========================================================
# 日期显示文本
# =========================================================
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
