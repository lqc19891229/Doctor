extends RefCounted
class_name HerbUnit

# =========================================================
# HerbUnit.gd
# 药材单位工具
#
# 统一底层单位：分
#
# 换算关系：
# 1钱 = 10分
# 1两 = 100分
# 1斤 = 1600分
# =========================================================

const UNIT_FEN := "fen"
const UNIT_QIAN := "qian"
const UNIT_LIANG := "liang"
const UNIT_JIN := "jin"

const FEN_PER_FEN := 1
const FEN_PER_QIAN := 10
const FEN_PER_LIANG := 100
const FEN_PER_JIN := 1600


# =========================================================
# 一、合法性
# =========================================================
static func is_valid_unit(unit: String) -> bool:
	return unit in [UNIT_FEN, UNIT_QIAN, UNIT_LIANG, UNIT_JIN]


# =========================================================
# 二、显示名
# =========================================================
static func get_unit_display_name(unit: String) -> String:
	match unit:
		UNIT_FEN:
			return "分"
		UNIT_QIAN:
			return "钱"
		UNIT_LIANG:
			return "两"
		UNIT_JIN:
			return "斤"
		_:
			return unit


# =========================================================
# 三、换算倍率（转成分）
# =========================================================
static func get_fen_rate(unit: String) -> int:
	match unit:
		UNIT_FEN:
			return FEN_PER_FEN
		UNIT_QIAN:
			return FEN_PER_QIAN
		UNIT_LIANG:
			return FEN_PER_LIANG
		UNIT_JIN:
			return FEN_PER_JIN
		_:
			push_warning("HerbUnit.get_fen_rate: 未知单位 -> " + unit)
			return 1


# =========================================================
# 四、转成总分
# 例如：
# to_fen(3, "qian") = 30
# to_fen(1.5, "liang") = 150
# =========================================================
static func to_fen(amount: float, unit: String) -> int:
	if amount <= 0.0:
		return 0

	var rate := get_fen_rate(unit)
	return int(round(amount * rate))


# =========================================================
# 五、从总分转换成某单位数量
# 例如：
# from_fen(150, "liang") = 1.5
# from_fen(30, "qian") = 3.0
# =========================================================
static func from_fen(total_fen: int, unit: String) -> float:
	if total_fen <= 0:
		return 0.0

	var rate := float(get_fen_rate(unit))
	return total_fen / rate


# =========================================================
# 六、单位之间直接转换
# =========================================================
static func convert(amount: float, from_unit: String, to_unit: String) -> float:
	var total_fen := to_fen(amount, from_unit)
	return from_fen(total_fen, to_unit)


# =========================================================
# 七、单单位格式化
# 例如：
# format_amount(3, "qian") = "3钱"
# format_amount(1.5, "liang") = "1.5两"
# =========================================================
static func format_amount(amount: float, unit: String) -> String:
	var unit_name := get_unit_display_name(unit)

	if amount == int(amount):
		return "%d%s" % [int(amount), unit_name]

	return "%s%s" % [amount, unit_name]


# =========================================================
# 八、总分转复合显示
# 例如：
# 1873分 = 1斤2两7钱3分
# 120分 = 1两2钱
# 30分 = 3钱
# =========================================================
static func format_fen_as_compound(total_fen: int) -> String:
	if total_fen <= 0:
		return "0分"

	var remain := total_fen

	var jin: int = remain / FEN_PER_JIN
	remain = remain % FEN_PER_JIN

	var liang: int = remain / FEN_PER_LIANG
	remain = remain % FEN_PER_LIANG

	var qian: int = remain / FEN_PER_QIAN
	remain = remain % FEN_PER_QIAN

	var fen: int = remain

	var parts: Array[String] = []

	if jin > 0:
		parts.append("%d斤" % jin)
	if liang > 0:
		parts.append("%d两" % liang)
	if qian > 0:
		parts.append("%d钱" % qian)
	if fen > 0:
		parts.append("%d分" % fen)

	return "".join(parts)


# =========================================================
# 九、自动选一个较合适的显示方式
# 例如：
# 1600 -> 1斤
# 200 -> 2两
# 30 -> 3钱
# 3 -> 3分
# 150 -> 1两5钱
# =========================================================
static func format_fen_auto(total_fen: int) -> String:
	if total_fen <= 0:
		return "0分"

	if total_fen % FEN_PER_JIN == 0:
		return "%d斤" % (total_fen / FEN_PER_JIN)

	if total_fen % FEN_PER_LIANG == 0:
		return "%d两" % (total_fen / FEN_PER_LIANG)

	if total_fen % FEN_PER_QIAN == 0:
		return "%d钱" % (total_fen / FEN_PER_QIAN)

	return format_fen_as_compound(total_fen)
