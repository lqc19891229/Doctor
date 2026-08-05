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

# 当前正在使用的槽位。
# 不传 slot_index 时，save_game / load_game / has_save / delete_save 默认使用这个槽位。
var current_slot_index: int = 1


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
	if slot_index <= 0:
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		return false

	var save_path: String = get_save_path(slot_index)
	_recover_interrupted_save(save_path)

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
	if slot_index <= 0:
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		print("存档失败：无效槽位 %d" % slot_index)
		return false

	current_slot_index = slot_index

	# 组装要保存的数据
	# meta：存档摘要，给存档选择界面显示用
	# time：保存天数和白天/黑夜
	# progress：保存医书阅读、药材、疾病、方剂等解锁进度
	# story：保存剧情播放状态
	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"meta": _make_save_meta(slot_index),
		"time": {
			"current_day": GameTime.current_day,
			"current_phase": GameTime.current_phase
		},
		"progress": Unlock.get_save_data(),
		"story": StoryManager.get_save_data()
	}

	var save_path: String = get_save_path(slot_index)
	if not _recover_interrupted_save(save_path):
		print("存档失败：无法恢复上次中断的存档事务：", save_path)
		return false

	# 将 Dictionary 转成 JSON 字符串。
	var json_text: String = JSON.stringify(save_data, "\t")
	var temp_path: String = save_path + SAVE_TEMP_SUFFIX

	# 先写临时文件，正式存档在完整写入前始终保持不变。
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)

	# 如果临时文件打开失败，直接返回。
	if file == null:
		print("存档失败：无法打开临时存档文件：", temp_path)
		return false

	# 写入并立即刷新到磁盘，再检查本次文件操作是否出错。
	file.store_string(json_text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()

	if write_error != OK:
		_remove_file_if_exists(temp_path)
		print("存档失败：临时存档写入错误：", temp_path, "，错误码：", write_error)
		return false

	# 临时文件写完后再替换正式存档；替换失败时恢复旧档。
	if not _commit_temp_save(save_path, temp_path):
		return false

	print("存档完成：槽位 %d，第 %d 天，阶段：%s" % [
		slot_index,
		GameTime.current_day,
		GameTime.current_phase
	])

	return true


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
	if slot_index <= 0:
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		print("读档失败：无效槽位 %d" % slot_index)
		return false

	var save_path: String = get_save_path(slot_index)
	_recover_interrupted_save(save_path)

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
	if slot_index <= 0:
		slot_index = current_slot_index

	if not is_valid_slot(slot_index):
		print("删除存档失败：无效槽位 %d" % slot_index)
		return false

	var slot_save_path: String = get_save_path(slot_index)
	_recover_interrupted_save(slot_save_path)
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
	if not is_valid_slot(slot_index):
		return {
			"slot_index": slot_index,
			"exists": false,
			"display_name": "无效槽位"
		}

	var save_path: String = get_save_path(slot_index)
	_recover_interrupted_save(save_path)

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
