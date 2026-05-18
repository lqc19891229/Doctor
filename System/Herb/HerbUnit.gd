extends RefCounted
class_name HerbUnit

# =========================================================
# 脚本功能：
#   药材剂量单位工具类。
#
# 主要职责：
#   1. 统一维护药材剂量单位常量。
#   2. 将不同单位统一换算为底层单位“分”。
#   3. 将底层“分”转换为适合界面显示的中药剂量文本。
#   4. 提供阿拉伯数字转中文数字的显示辅助函数。
#
# 底层统一单位：分
# 换算关系：
#   1钱 = 10分
#   1两 = 100分
#   1斤 = 1600分
# =========================================================

# =========================================================
# 一、单位常量
# =========================================================
const UNIT_FEN := "fen"      # 分
const UNIT_QIAN := "qian"    # 钱
const UNIT_LIANG := "liang"  # 两
const UNIT_JIN := "jin"      # 斤

const FEN_PER_FEN := 1        # 1分对应的分值
const FEN_PER_QIAN := 10      # 1钱对应的分值
const FEN_PER_LIANG := 100    # 1两对应的分值
const FEN_PER_JIN := 1600     # 1斤对应的分值

# 单位到显示名称的映射表。
const UNIT_DISPLAY_NAMES := {
	UNIT_FEN: "分",
	UNIT_QIAN: "钱",
	UNIT_LIANG: "两",
	UNIT_JIN: "斤",
}

# 单位到底层“分”的换算倍率映射表。
const UNIT_FEN_RATES := {
	UNIT_FEN: FEN_PER_FEN,
	UNIT_QIAN: FEN_PER_QIAN,
	UNIT_LIANG: FEN_PER_LIANG,
	UNIT_JIN: FEN_PER_JIN,
}

# 中文数字表，用于数字转中文显示。
const CHINESE_DIGITS := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

# 中文整数单位表，当前用于 0 ~ 9999 的常规数字显示。
const CHINESE_UNITS := ["", "十", "百", "千"]


# =========================================================
# 二、单位检查与换算
# =========================================================

# 函数功能：判断传入单位是否为系统支持的合法单位。
static func is_valid_unit(unit: String) -> bool:
	return UNIT_FEN_RATES.has(unit)


# 函数功能：把内部单位 key 转换为界面显示用中文名称。
static func get_unit_display_name(unit: String) -> String:
	return UNIT_DISPLAY_NAMES.get(unit, unit)


# 函数功能：获取指定单位换算为底层单位“分”的倍率。
static func get_fen_rate(unit: String) -> int:
	if not is_valid_unit(unit):
		push_warning("HerbUnit.get_fen_rate: 未知单位 -> " + unit)
		return FEN_PER_FEN

	return UNIT_FEN_RATES[unit]


# 函数功能：把“数量 + 单位”统一换算成底层总分值。
static func to_fen(amount: float, unit: String) -> int:
	if amount <= 0.0:
		return 0

	return int(round(amount * get_fen_rate(unit)))


# 函数功能：把底层总分值换算回指定单位的数量。
static func from_fen(total_fen: int, unit: String) -> float:
	if total_fen <= 0:
		return 0.0

	return float(total_fen) / float(get_fen_rate(unit))


# 函数功能：在两个单位之间直接换算。
static func convert(amount: float, from_unit: String, to_unit: String) -> float:
	return from_fen(to_fen(amount, from_unit), to_unit)


# =========================================================
# 三、中文数字显示
# =========================================================

# 函数功能：把整数转换成中文数字文本，主要用于剂量显示。
# 说明：当前适合 0 ~ 9999 的常规显示；超过该范围仍会尽量显示，但单位表只覆盖到“千”。
static func number_to_chinese(num: int) -> String:
	if num == 0:
		return CHINESE_DIGITS[0]

	if num < 0:
		return "负" + number_to_chinese(-num)

	var result := ""
	var unit_index := 0
	var need_zero := false
	var value := num

	while value > 0:
		var digit := value % 10

		if digit == 0:
			if result != "":
				need_zero = true
		else:
			var unit_text := ""
			if unit_index < CHINESE_UNITS.size():
				unit_text = CHINESE_UNITS[unit_index]

			var part: String = CHINESE_DIGITS[digit] + unit_text

			if need_zero:
				part = CHINESE_DIGITS[0] + part
				need_zero = false

			result = part + result

		# 使用整数除法，避免 Godot 4 中“/”产生浮点结果。
		value = value / 10
		unit_index += 1

	# 10 ~ 19 显示为“十、十一、十二”，而不是“一十、一十一、一十二”。
	if result.begins_with("一十"):
		result = result.substr(1)

	return result


# 函数功能：把浮点数转换成中文数字文本。
# 规则：整数直接使用中文整数；小数使用“点”逐位读取，最多保留两位小数。
static func float_to_chinese(amount: float) -> String:
	var rounded_amount = round(amount * 100.0) / 100.0
	var int_part := int(rounded_amount)

	if is_equal_approx(rounded_amount, float(int_part)):
		return number_to_chinese(int_part)

	var text := str(rounded_amount)
	var parts := text.split(".")
	var integer_text := number_to_chinese(int(parts[0]))
	var decimal_text := ""

	if parts.size() > 1:
		for ch in parts[1]:
			if ch >= "0" and ch <= "9":
				decimal_text += CHINESE_DIGITS[int(ch)]

	if decimal_text == "":
		return integer_text

	return integer_text + "点" + decimal_text


# =========================================================
# 四、剂量文本格式化
# =========================================================

# 函数功能：把底层总分值转换为“斤两钱分”的复合单位文本。
static func format_fen_as_compound(total_fen: int) -> String:
	if total_fen <= 0:
		return "零分"

	var remain := total_fen
	var parts: Array[String] = []

	var jin := remain / FEN_PER_JIN
	remain %= FEN_PER_JIN

	var liang := remain / FEN_PER_LIANG
	remain %= FEN_PER_LIANG

	var qian := remain / FEN_PER_QIAN
	remain %= FEN_PER_QIAN

	var fen := remain

	_append_compound_part(parts, jin, "斤")
	_append_compound_part(parts, liang, "两")
	_append_compound_part(parts, qian, "钱")
	_append_compound_part(parts, fen, "分")

	return "".join(parts)


# 函数功能：根据总分值自动选择较简洁的剂量显示格式。
static func format_fen_auto(total_fen: int) -> String:
	if total_fen <= 0:
		return "零分"

	if total_fen % FEN_PER_JIN == 0:
		return "%s斤" % number_to_chinese(total_fen / FEN_PER_JIN)

	if total_fen % FEN_PER_LIANG == 0:
		return "%s两" % number_to_chinese(total_fen / FEN_PER_LIANG)

	if total_fen % FEN_PER_QIAN == 0:
		return "%s钱" % number_to_chinese(total_fen / FEN_PER_QIAN)

	return format_fen_as_compound(total_fen)


# 函数功能：把输入的“数量 + 单位”格式化为中药剂量文本。
static func format_amount(amount: float, unit: String) -> String:
	return format_fen_as_compound(to_fen(amount, unit))


# 函数功能：向复合剂量文本数组中追加非零单位片段。
static func _append_compound_part(parts: Array[String], amount: int, unit_name: String) -> void:
	if amount <= 0:
		return

	parts.append("%s%s" % [number_to_chinese(amount), unit_name])
