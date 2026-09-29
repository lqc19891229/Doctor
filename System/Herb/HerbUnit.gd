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
#   4. 提供本地化数字显示辅助函数。
#
# 底层统一单位：分
# 换算关系：
#   1钱 = 10分
#   1两 = 100分
#   1斤 = 1600分
# =========================================================

const UNIT_FEN := "fen"
const UNIT_QIAN := "qian"
const UNIT_LIANG := "liang"
const UNIT_JIN := "jin"

const FEN_PER_FEN := 1
const FEN_PER_QIAN := 10
const FEN_PER_LIANG := 100
const FEN_PER_JIN := 1600

const UNIT_DISPLAY_NAMES := {
	UNIT_FEN: "分",
	UNIT_QIAN: "钱",
	UNIT_LIANG: "两",
	UNIT_JIN: "斤",
}

const UNIT_FEN_RATES := {
	UNIT_FEN: FEN_PER_FEN,
	UNIT_QIAN: FEN_PER_QIAN,
	UNIT_LIANG: FEN_PER_LIANG,
	UNIT_JIN: FEN_PER_JIN,
}

const CHINESE_DIGITS := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
const CHINESE_UNITS := ["", "十", "百", "千"]
const KOREAN_DIGITS := ["영", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"]
const KOREAN_UNITS := ["", "십", "백", "천"]


static func is_valid_unit(unit: String) -> bool:
	return UNIT_FEN_RATES.has(unit)


static func get_unit_display_name(unit: String) -> String:
	return UNIT_DISPLAY_NAMES.get(unit, unit)


static func get_fen_rate(unit: String) -> int:
	if not is_valid_unit(unit):
		push_warning("HerbUnit.get_fen_rate: 未知单位 -> " + unit)
		return FEN_PER_FEN
	return UNIT_FEN_RATES[unit]


static func to_fen(amount: float, unit: String) -> int:
	if amount <= 0.0:
		return 0
	return int(round(amount * get_fen_rate(unit)))


static func from_fen(total_fen: int, unit: String) -> float:
	if total_fen <= 0:
		return 0.0
	return float(total_fen) / float(get_fen_rate(unit))


static func convert(amount: float, from_unit: String, to_unit: String) -> float:
	return from_fen(to_fen(amount, from_unit), to_unit)


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

		value = value / 10
		unit_index += 1

	if result.begins_with("一十"):
		result = result.substr(1)

	return result


static func number_to_korean(num: int) -> String:
	if num == 0:
		return KOREAN_DIGITS[0]

	if num < 0:
		return "마이너스 " + number_to_korean(-num)

	var result := ""
	var unit_index := 0
	var value := num

	while value > 0:
		var digit := value % 10
		if digit != 0:
			var unit_text := ""
			if unit_index < KOREAN_UNITS.size():
				unit_text = KOREAN_UNITS[unit_index]

			# 십/백/천 앞의 1은 보통 생략한다.
			var digit_text = KOREAN_DIGITS[digit]
			if digit == 1 and unit_index > 0:
				digit_text = ""

			result = digit_text + unit_text + result

		value = value / 10
		unit_index += 1

	return result


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


static func format_fen_auto(total_fen: int) -> String:
	var locale := TranslationServer.get_locale().to_lower().replace("-", "_")

	if locale.begins_with("en"):
		return _format_fen_localized(total_fen, "arabic")

	if locale.begins_with("ja"):
		return _format_fen_localized(total_fen, "kanji")

	if locale.begins_with("ko"):
		return _format_fen_localized(total_fen, "korean")

	if total_fen <= 0:
		return "零分"

	if total_fen % FEN_PER_JIN == 0:
		return "%s斤" % number_to_chinese(total_fen / FEN_PER_JIN)

	if total_fen % FEN_PER_LIANG == 0:
		return "%s两" % number_to_chinese(total_fen / FEN_PER_LIANG)

	if total_fen % FEN_PER_QIAN == 0:
		return "%s钱" % number_to_chinese(total_fen / FEN_PER_QIAN)

	return format_fen_as_compound(total_fen)


static func _format_fen_localized(total_fen: int, number_style: String) -> String:
	if total_fen <= 0:
		return TranslationServer.translate("UI_PRESCRIPTION_ZERO_FEN")

	var remainder := total_fen
	var parts: Array[String] = []

	for unit_data in [
		[FEN_PER_JIN, UNIT_JIN],
		[FEN_PER_LIANG, UNIT_LIANG],
		[FEN_PER_QIAN, UNIT_QIAN],
		[FEN_PER_FEN, UNIT_FEN],
	]:
		var count: int = remainder / int(unit_data[0])
		remainder %= int(unit_data[0])

		if count <= 0:
			continue

		var number_text := str(count)
		match number_style:
			"kanji":
				number_text = number_to_chinese(count)
			"korean":
				number_text = number_to_korean(count)

		var unit_text := _get_localized_unit_name(str(unit_data[1]))

		# 日文古籍风格不插空格：一銭五分；韩文/英文保留词间空格。
		if number_style == "kanji":
			parts.append("%s%s" % [number_text, unit_text])
		else:
			parts.append("%s %s" % [number_text, unit_text])

	return "".join(parts) if number_style == "kanji" else " ".join(parts)


static func format_amount(amount: float, unit: String) -> String:
	var locale := TranslationServer.get_locale().to_lower().replace("-", "_")

	if locale.begins_with("en"):
		return _format_amount_english(amount, unit)

	if locale.begins_with("ja"):
		return _format_amount_native(amount, unit, "kanji")

	if locale.begins_with("ko"):
		return _format_amount_native(amount, unit, "korean")

	return format_fen_as_compound(to_fen(amount, unit))


static func _format_amount_native(amount: float, unit: String, number_style: String) -> String:
	# 处方内部最终都能精确换算为分，统一走复合单位格式最稳定。
	return _format_fen_localized(to_fen(amount, unit), number_style)


static func _format_amount_english(amount: float, unit: String) -> String:
	var amount_text := _format_number_english(amount)
	var unit_text := _get_localized_unit_name(unit)

	if unit_text.strip_edges() == "":
		return amount_text

	return "%s %s" % [amount_text, unit_text]


static func _format_number_english(amount: float) -> String:
	var rounded_amount: float = round(amount * 100.0) / 100.0
	var int_amount: int = int(rounded_amount)

	if is_equal_approx(rounded_amount, float(int_amount)):
		return str(int_amount)

	var text: String = "%.2f" % rounded_amount
	while text.ends_with("0"):
		text = text.trim_suffix("0")
	if text.ends_with("."):
		text = text.trim_suffix(".")

	return text


static func _get_localized_unit_name(unit: String) -> String:
	var translation_key := ""

	match unit:
		UNIT_FEN:
			translation_key = "UI_PRESCRIPTION_UNIT_FEN"
		UNIT_QIAN:
			translation_key = "UI_PRESCRIPTION_UNIT_QIAN"
		UNIT_LIANG:
			translation_key = "UI_PRESCRIPTION_UNIT_LIANG"
		UNIT_JIN:
			translation_key = "UI_PRESCRIPTION_UNIT_JIN"
		_:
			return unit

	var translated := TranslationServer.translate(translation_key)

	if translated.strip_edges() == "" or translated == translation_key:
		return unit

	return translated


static func _append_compound_part(parts: Array[String], amount: int, unit_name: String) -> void:
	if amount <= 0:
		return

	parts.append("%s%s" % [number_to_chinese(amount), unit_name])
