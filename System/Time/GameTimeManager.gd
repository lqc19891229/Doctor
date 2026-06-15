extends Node

# =========================================================
# GameTimeManager
# 统一管理游戏时间
#
# 负责：
# 1. 当前第几天
# 2. 当前阶段：白天 / 夜晚
# 3. 十二时辰
# 4. Clinic 场景内自动计时
#
# Clinic.gd 不直接处理计时，只监听这里的信号
# =========================================================


# =========================================================
# 信号
# =========================================================

# 时间变化时发出，用于刷新 UI
signal time_changed

# Clinic 时间结束时发出
signal clinic_time_finished


# =========================================================
# 阶段常量
# =========================================================

const PHASE_DAY: String = "day"
const PHASE_NIGHT: String = "night"


# =========================================================
# 十二时辰
# 下标：
# 0 子，1 丑，2 寅，3 卯，4 辰，5 巳，
# 6 午，7 未，8 申，9 酉，10 戌，11 亥
# =========================================================

const SHICHEN_LIST: Array[String] = [
	"子时",
	"丑时",
	"寅时",
	"卯时",
	"辰时",
	"巳时",
	"午时",
	"未时",
	"申时",
	"酉时",
	"戌时",
	"亥时"
]


# =========================================================
# 日期显示设置
# 只影响日期文本，不影响白天 / 夜晚 / 十二时辰逻辑
#
# current_day = 1   嘉靖十九年春
# current_day = 2   嘉靖十九年夏
# current_day = 3   嘉靖十九年秋
# current_day = 4   嘉靖十九年冬
# current_day = 5   嘉靖二十年春
# ...
# 嘉靖四十五年冬之后进入万历元年春
# =========================================================

const START_ERA_NAME: String = "嘉靖"
const START_ERA_YEAR: int = 19
const START_ERA_LAST_YEAR: int = 45

const NEXT_ERA_NAME: String = "万历"
const NEXT_ERA_START_YEAR: int = 1

const SEASON_LIST: Array[String] = [
	"春",
	"夏",
	"秋",
	"冬"
]


# =========================================================
# Clinic 时间设置
# =========================================================

# Clinic 从辰时开始
const CLINIC_START_SHICHEN_INDEX: int = 4

# Clinic 到申时结束
const CLINIC_END_SHICHEN_INDEX: int = 8

# 现实 60 秒 = 游戏内 1 个时辰
const CLINIC_SECONDS_PER_SHICHEN: float = 60.0


# =========================================================
# 当前时间数据
# =========================================================

# 当前时间序号
# 这里只保留 current_day 变量名，方便兼容现有代码
# 实际显示时按“季度”解释：1 = 嘉靖十九年春，2 = 嘉靖十九年夏
var current_day: int = 1

# 当前阶段
var current_phase: String = PHASE_DAY

# 当前时辰
var current_shichen_index: int = CLINIC_START_SHICHEN_INDEX


# =========================================================
# Clinic 自动计时数据
# =========================================================

# Clinic 是否正在计时
var clinic_clock_running: bool = false

# Clinic 是否因为剧情而暂停
var clinic_clock_paused_by_story: bool = false

# Clinic 当前累计的现实秒数
var clinic_time_accumulator: float = 0.0


# =========================================================
# 每帧更新
# 因为 GameTimeManager 是 Autoload，所以这里会一直运行
# 但只有 clinic_clock_running = true 时才真正计时
# =========================================================
func _process(delta: float) -> void:
	_update_clinic_clock(delta)


# =========================================================
# 新游戏初始化
# =========================================================
func start_new_game() -> void:
	current_day = 1
	current_phase = PHASE_DAY
	current_shichen_index = CLINIC_START_SHICHEN_INDEX

	stop_clinic_clock()

	time_changed.emit()

	print("时间初始化：%s 白天 %s" % [get_day_text(), get_shichen_text()])


# =========================================================
# 玩家进入 Clinic 时调用
# =========================================================
func start_clinic_time() -> void:
	# 如果是从剧情返回 Clinic，则恢复原来的时辰和累计时间，不重置到辰时。
	if clinic_clock_paused_by_story:
		current_phase = PHASE_DAY
		clinic_clock_running = true
		clinic_clock_paused_by_story = false

		time_changed.emit()

		print("Clinic 从剧情恢复计时：%s %s，累计 %.2f 秒" % [
			get_day_text(),
			get_shichen_text(),
			clinic_time_accumulator
		])
		return

	# 设置为白天
	current_phase = PHASE_DAY

	# Clinic 每次正常进入都从辰时开始
	current_shichen_index = CLINIC_START_SHICHEN_INDEX

	# 清空累计时间
	clinic_time_accumulator = 0.0

	# 开始自动计时
	clinic_clock_running = true

	time_changed.emit()

	print("Clinic 开始计时：%s %s" % [get_day_text(), get_shichen_text()])


# =========================================================
# 停止 Clinic 计时
# =========================================================
func stop_clinic_clock() -> void:
	clinic_clock_running = false
	clinic_clock_paused_by_story = false
	clinic_time_accumulator = 0.0


# =========================================================
# 剧情期间暂停 Clinic 计时
# 说明：
# 1. 只暂停，不清空 current_shichen_index
# 2. 只暂停，不清空 clinic_time_accumulator
# 3. 剧情结束回 Clinic 时，可继续原来的时辰进度
# =========================================================
func pause_clinic_clock_for_story() -> bool:
	if not clinic_clock_running:
		return false

	clinic_clock_running = false
	clinic_clock_paused_by_story = true

	print("Clinic 因剧情暂停计时：%s %s，累计 %.2f 秒" % [
		get_day_text(),
		get_shichen_text(),
		clinic_time_accumulator
	])

	return true


func resume_clinic_clock_after_story() -> void:
	if not clinic_clock_paused_by_story:
		return

	if not is_day():
		clinic_clock_paused_by_story = false
		return

	clinic_clock_running = true
	clinic_clock_paused_by_story = false

	time_changed.emit()

	print("Clinic 剧情结束后恢复计时：%s %s，累计 %.2f 秒" % [
		get_day_text(),
		get_shichen_text(),
		clinic_time_accumulator
	])


func cancel_story_pause_state() -> void:
	# 剧情结束后如果不是回 Clinic，而是去 Night，就清掉暂停状态。
	clinic_clock_running = false
	clinic_clock_paused_by_story = false


# =========================================================
# Clinic 自动计时逻辑
# 每 60 秒推进 1 个时辰
# =========================================================
func _update_clinic_clock(delta: float) -> void:
	# 没有进入 Clinic 时，不计时
	if not clinic_clock_running:
		return

	# 只有白天阶段才计时
	if not is_day():
		return

	# 累加现实经过时间
	clinic_time_accumulator += delta

	# 未满 60 秒，不推进
	if clinic_time_accumulator < CLINIC_SECONDS_PER_SHICHEN:
		return

	# 扣除 60 秒，而不是直接归零
	# 这样低帧率时不会丢时间
	clinic_time_accumulator -= CLINIC_SECONDS_PER_SHICHEN

	advance_clinic_shichen()


# =========================================================
# 推进 Clinic 时辰
# =========================================================
func advance_clinic_shichen() -> void:
	current_shichen_index += 1

	# 超过申时，Clinic 时间结束
	if current_shichen_index > CLINIC_END_SHICHEN_INDEX:
		stop_clinic_clock()
		clinic_time_finished.emit()
		return

	time_changed.emit()

	print("Clinic 时间推进：%s %s" % [get_day_text(), get_shichen_text()])


# =========================================================
# 白天结束
# 注意：
# 这里只切换阶段，不增加天数
# =========================================================
func finish_day() -> void:
	stop_clinic_clock()

	current_phase = PHASE_NIGHT

	time_changed.emit()

	print("白天结束：%s 夜晚" % get_day_text())


# =========================================================
# 黑夜结束
# 注意：
# 天数只在这里 +1
# =========================================================
func finish_night() -> void:
	current_day += 1
	current_phase = PHASE_DAY
	current_shichen_index = CLINIC_START_SHICHEN_INDEX

	time_changed.emit()

	print("黑夜结束：进入 %s 白天" % get_day_text())


# =========================================================
# UI 显示文本
# =========================================================
func get_day_text() -> String:
	var passed_quarters: int = current_day - 1

	var year_offset: int = int(passed_quarters / 4)
	var season_index: int = passed_quarters % 4

	var era_year_from_jiajing_start: int = START_ERA_YEAR + year_offset
	var season_text: String = SEASON_LIST[season_index]

	if era_year_from_jiajing_start <= START_ERA_LAST_YEAR:
		return "%s%s年%s" % [
			START_ERA_NAME,
			era_year_to_chinese(era_year_from_jiajing_start),
			season_text
		]

	var years_after_start_era: int = era_year_from_jiajing_start - START_ERA_LAST_YEAR
	var next_era_year: int = NEXT_ERA_START_YEAR + years_after_start_era - 1

	return "%s%s年%s" % [
		NEXT_ERA_NAME,
		era_year_to_chinese(next_era_year),
		season_text
	]


func era_year_to_chinese(value: int) -> String:
	if value == 1:
		return "元"

	return number_to_chinese(value)


func number_to_chinese(value: int) -> String:
	var chinese_numbers: Array[String] = [
		"零",
		"一",
		"二",
		"三",
		"四",
		"五",
		"六",
		"七",
		"八",
		"九",
		"十"
	]

	if value <= 10:
		return chinese_numbers[value]

	if value < 20:
		return "十%s" % chinese_numbers[value - 10]

	var ten_digit: int = int(value / 10)
	var one_digit: int = value % 10

	if one_digit == 0:
		return "%s十" % chinese_numbers[ten_digit]

	return "%s十%s" % [
		chinese_numbers[ten_digit],
		chinese_numbers[one_digit]
	]


func get_shichen_text() -> String:
	if current_shichen_index < 0 or current_shichen_index >= SHICHEN_LIST.size():
		return "未知时辰"

	return SHICHEN_LIST[current_shichen_index]


func get_full_time_text() -> String:
	var phase_text := "白天" if is_day() else "夜晚"
	return "%s %s · %s" % [get_day_text(), phase_text, get_shichen_text()]


# =========================================================
# 阶段判断
# =========================================================
func is_day() -> bool:
	return current_phase == PHASE_DAY


func is_night() -> bool:
	return current_phase == PHASE_NIGHT
