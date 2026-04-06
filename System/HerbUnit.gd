extends RefCounted
class_name HerbUnit

# =========================================================
# HerbUnit.gd
# 药材单位工具
#
# 作用：
# 1. 统一处理药材剂量单位
# 2. 提供单位换算（底层统一为“分”）
# 3. 提供适合中药剂量的文本显示
#
# 底层统一单位：分
#
# 换算关系：
# 1钱 = 10分
# 1两 = 100分
# 1斤 = 1600分
# =========================================================


# =========================================================
# 一、单位常量
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
# 二、合法性检查
# 作用：
#   判断传入的单位字符串是否为系统支持的合法单位
# =========================================================
static func is_valid_unit(unit: String) -> bool:
	return unit in [UNIT_FEN, UNIT_QIAN, UNIT_LIANG, UNIT_JIN]


# =========================================================
# 三、单位显示名
# 作用：
#   把内部单位 key 转成界面显示文字
# 示例：
#   "fen"   -> "分"
#   "qian"  -> "钱"
#   "liang" -> "两"
#   "jin"   -> "斤"
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
# 四、换算倍率（转成分）
# 作用：
#   获取某个单位对应多少“分”
# 示例：
#   get_fen_rate("qian")  -> 10
#   get_fen_rate("liang") -> 100
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
# 五、转成总分
# 作用：
#   把“数量 + 单位”统一转换成底层总分值
#
# 示例：
#   to_fen(3, "qian")    = 30
#   to_fen(1.5, "liang") = 150
# =========================================================
static func to_fen(amount: float, unit: String) -> int:
	if amount <= 0.0:
		return 0

	var rate := get_fen_rate(unit)
	return int(round(amount * rate))


# =========================================================
# 六、从总分转换成某单位数量
# 作用：
#   把底层总分值换算回指定单位
#
# 示例：
#   from_fen(150, "liang") = 1.5
#   from_fen(30, "qian")   = 3.0
# =========================================================
static func from_fen(total_fen: int, unit: String) -> float:
	if total_fen <= 0:
		return 0.0

	var rate := float(get_fen_rate(unit))
	return total_fen / rate


# =========================================================
# 七、单位之间直接转换
# 作用：
#   在不同单位之间直接换算
#
# 示例：
#   convert(3, "qian", "fen")    = 30
#   convert(150, "fen", "liang") = 1.5
# =========================================================
static func convert(amount: float, from_unit: String, to_unit: String) -> float:
	var total_fen := to_fen(amount, from_unit)
	return from_fen(total_fen, to_unit)


# =========================================================
# 八、数字转中文
# 作用：
#   把整数转换成中文数字，供界面显示使用
#
# 当前支持：
#   0 ~ 9999 的常规显示
#
# 示例：
#   0   -> 零
#   1   -> 一
#   9   -> 九
#   10  -> 十
#   11  -> 十一
#   20  -> 二十
#   21  -> 二十一
#   105 -> 一百零五
# =========================================================
static func number_to_chinese(num: int) -> String:
	var digits := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
	var units := ["", "十", "百", "千"]

	if num == 0:
		return "零"

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
			var part = digits[digit] + units[unit_index]

			if need_zero:
				part = "零" + part
				need_zero = false

			result = part + result

		value /= 10
		unit_index += 1

	# 10~19 显示为“十、十一、十二”
	if result.begins_with("一十"):
		result = result.substr(1)

	return result


# =========================================================
# 九、浮点数转中文显示
# 作用：
#   把 float 转成中文数字文本
#
# 规则：
#   1. 整数：直接转中文整数
#   2. 小数：使用“点”逐位读法
#
# 示例：
#   1.0   -> 一
#   1.5   -> 一点五
#   12.25 -> 十二点二五
#
# 说明：
#   当前主要用于显示层，不影响内部数值计算
# =========================================================
static func float_to_chinese(amount: float) -> String:
	var int_part := int(amount)

	# 本质上是整数时，直接返回整数中文
	if is_equal_approx(amount, float(int_part)):
		return number_to_chinese(int_part)

	var digits := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

	# 限制到两位小数，避免浮点误差导致显示异常
	var rounded_amount = round(amount * 100.0) / 100.0
	var text := str(rounded_amount)

	if text.ends_with(".0"):
		return number_to_chinese(int(round(rounded_amount)))

	var parts := text.split(".")
	var integer_text := number_to_chinese(int(parts[0]))
	var decimal_text := ""

	if parts.size() > 1:
		for ch in parts[1]:
			if ch >= "0" and ch <= "9":
				decimal_text += digits[int(ch)]

	if decimal_text == "":
		return integer_text

	return integer_text + "点" + decimal_text


# =========================================================
# 十、总分转复合显示
# 作用：
#   把总分转换为“斤两钱分”的复合文本
#
# 示例：
#   1873分 = 一斤二两七钱三分
#   120分  = 一两二钱
#   30分   = 三钱
#   11分   = 一钱一分
# =========================================================
static func format_fen_as_compound(total_fen: int) -> String:
	if total_fen <= 0:
		return "零分"

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
		parts.append("%s斤" % number_to_chinese(jin))
	if liang > 0:
		parts.append("%s两" % number_to_chinese(liang))
	if qian > 0:
		parts.append("%s钱" % number_to_chinese(qian))
	if fen > 0:
		parts.append("%s分" % number_to_chinese(fen))

	return "".join(parts)


# =========================================================
# 十一、自动选一个较合适的显示方式
# 作用：
#   根据总分值自动选择更简洁的显示格式
#
# 示例：
#   1600 -> 一斤
#   200  -> 二两
#   30   -> 三钱
#   3    -> 三分
#   150  -> 一两五钱
# =========================================================
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


# =========================================================
# 十二、格式化“数量 + 单位”
# 作用：
#   把输入的 amount + unit 先转成总分，
#   再按中药进位规则显示成复合单位文本
#
# 示例：
#   format_amount(11, "fen")   -> 一钱一分
#   format_amount(20, "fen")   -> 二钱
#   format_amount(11, "qian")  -> 一两一钱
#   format_amount(10, "qian")  -> 一两
#   format_amount(1.5, "liang")-> 一两五钱
# =========================================================
static func format_amount(amount: float, unit: String) -> String:
	var total_fen := to_fen(amount, unit)
	return format_fen_as_compound(total_fen)
