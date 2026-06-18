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

	if FileAccess.file_exists(get_save_path(slot_index)):
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

	# 打开文件，WRITE 表示写入模式
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)

	# 如果文件打开失败，直接返回
	if file == null:
		print("存档失败：无法打开存档文件：", save_path)
		return false

	# 将 Dictionary 转成 JSON 字符串
	var json_text: String = JSON.stringify(save_data, "\t")

	# 写入文件
	file.store_string(json_text)

	# 关闭文件
	file.close()

	print("存档完成：槽位 %d，第 %d 天，阶段：%s" % [
		slot_index,
		GameTime.current_day,
		GameTime.current_phase
	])

	return true


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

	var save_path: String = get_save_path(slot_index)

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
