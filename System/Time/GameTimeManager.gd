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

# 当前天数，只负责记录第几天
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
	# 设置为白天
	current_phase = PHASE_DAY

	# Clinic 每次进入都从辰时开始
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
	clinic_time_accumulator = 0.0


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
	return "第 %d 天" % current_day


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
