extends Node

# =========================================================
# SaveManager
# 负责游戏存档：
# 1. 保存游戏时间
# 2. 读取游戏时间
# 3. 保存解锁进度
# 4. 读取解锁进度
# 5. 判断是否存在存档
# =========================================================


# 存档文件路径
# user:// 是 Godot 的用户数据目录
# Windows / Mac / Steam / 手机平台都会自动映射到安全位置
const SAVE_PATH: String = "user://save_game.json"


# =========================================================
# 判断是否存在存档
# =========================================================
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# =========================================================
# 保存游戏
# =========================================================
func save_game() -> void:
	# 组装要保存的数据
	# time：保存天数和白天/黑夜
	# progress：保存医书阅读、药材、疾病、方剂等解锁进度
	var save_data: Dictionary = {
		"time": {
			"current_day": GameTime.current_day,
			"current_phase": GameTime.current_phase
		},
		"progress": Unlock.get_save_data()
	}

	# 打开文件，WRITE 表示写入模式
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	# 如果文件打开失败，直接返回
	if file == null:
		print("存档失败：无法打开存档文件")
		return

	# 将 Dictionary 转成 JSON 字符串
	var json_text: String = JSON.stringify(save_data, "\t")

	# 写入文件
	file.store_string(json_text)

	# 关闭文件
	file.close()

	print("存档完成：第 %d 天，阶段：%s" % [GameTime.current_day, GameTime.current_phase])


# =========================================================
# 读取游戏
# =========================================================
func load_game() -> bool:
	# 没有存档时，读取失败
	if not has_save():
		print("读档失败：没有存档")
		return false

	# 打开存档文件，READ 表示读取模式
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)

	# 如果文件打开失败，读取失败
	if file == null:
		print("读档失败：无法打开存档文件")
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

	# 读取时间数据
	_load_time_data(save_data)

	# 读取进度数据
	_load_progress_data(save_data)

	print("读档完成：第 %d 天，阶段：%s" % [GameTime.current_day, GameTime.current_phase])

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
# 删除存档
# 以后做“重新开始游戏”按钮时会用到
# =========================================================
func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("已删除存档")
	else:
		print("没有可删除的存档")
