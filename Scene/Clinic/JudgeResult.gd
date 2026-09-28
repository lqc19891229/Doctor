extends RefCounted
class_name JudgeResult

# =========================================================
# JudgeResult.gd
# 方剂判定结果
#
# 作用：
# - 统一存储 FormulaJudge 的判定结果
# - 给 UI、日志、调试输出使用
# =========================================================


# =========================================================
# 一、基础结果
# =========================================================

# 是否判定成功
# true  = 方剂合格（perfect / pass）
# false = 方剂失败（fail）
var success: bool = false

# 结果等级
# perfect = 完全正确
# pass    = 基本正确
# fail    = 不正确
var level: String = "fail"

# 总分
# 当前评价区间：
# 妙手回春 = 100
# 治疗成功 = 60~99
# 治疗失败 = 0~59
var score: int = 0

# 评价等级
# 妙手回春：100分
# 治疗成功：60~99分
# 治疗失败：0~59分
var grade: String = "治疗失败"

# 给玩家或 UI 显示的主信息
var message: String = ""
var english_message: String = ""
var english_disease_message: String = ""
var korean_message: String = ""
var korean_disease_message: String = ""
var japanese_message: String = ""
var japanese_disease_message: String = ""



# =========================================================
# 评价辅助
# =========================================================

# 是否为满分“妙手回春”
# 用于 Clinic.gd 判断是否奖励心得点。
func is_miaoshouhuichun() -> bool:
	return score == 100 and grade == "妙手回春"



# =========================================================
# 二、匹配到的标准方信息
# =========================================================

var matched_formula_id: String = ""
var matched_formula_name: String = ""


# =========================================================
# 二点五、疾病诊断判定
# =========================================================

# 玩家选择的疾病
var player_disease_id: String = ""
var player_disease_name: String = ""

# 标准疾病
var standard_disease_id: String = ""
var standard_disease_name: String = ""

# 疾病判断是否正确
var disease_correct: bool = false

# 疾病判断扣分
var disease_penalty: int = 0

# 疾病判断显示文本
var disease_message: String = ""


# =========================================================
# 三、错误明细
# =========================================================

# 缺失的药
# 结构示例：
# ["xing_ren", "gan_cao"]
var missing_herb_ids: Array[String] = []

# 缺失药名（方便 UI 直接显示）
# 结构示例：
# ["杏仁", "甘草"]
var missing_herb_names: Array[String] = []

# 多余的药
var extra_herb_ids: Array[String] = []
var extra_herb_names: Array[String] = []

# 剂量略有偏差
# 结构示例：
# ["麻黄：标准 3钱，实际 2.2钱"]
var minor_dosage_errors: Array[String] = []

# 剂量严重偏差
var major_dosage_errors: Array[String] = []

# 结构化剂量错误。
# 每项字段：herb_id / herb_name / player_fen / standard_fen
# 用于语言切换后重新本地化药名与剂量单位。
var major_dosage_error_data: Array[Dictionary] = []


# =========================================================
# 四、统计信息
# =========================================================

var standard_herb_count: int = 0
var player_herb_count: int = 0

# 命中多少味正确药材（只看 herb_id 是否存在）
var matched_herb_count: int = 0


# =========================================================
# 五、便捷判断
# =========================================================

func is_perfect() -> bool:
	return level == "perfect"


func is_pass() -> bool:
	return level == "pass"


func is_fail() -> bool:
	return level == "fail"


func has_missing_herbs() -> bool:
	return not missing_herb_ids.is_empty()


func has_extra_herbs() -> bool:
	return not extra_herb_ids.is_empty()


func has_minor_dosage_errors() -> bool:
	return not minor_dosage_errors.is_empty()


func has_major_dosage_errors() -> bool:
	return not major_dosage_errors.is_empty()


func has_any_problem() -> bool:
	return (
		has_missing_herbs()
		or has_extra_herbs()
		or has_minor_dosage_errors()
		or has_major_dosage_errors()
	)


# =========================================================
# 六、汇总文本
# =========================================================

func get_summary_text() -> String:
	var lines: Array[String] = []

	var localized_message := _localized_result_message()
	if not localized_message.is_empty():
		lines.append(localized_message)

	lines.append(_tr_fmt(
		"UI_JUDGE_SUMMARY_SCORE_FMT",
		_score_fallback_fmt(),
		[score]
	))

	var grade_key := _get_grade_translation_key()
	var localized_grade := _translate_with_fallback(grade_key, grade)
	lines.append(_tr_fmt(
		"UI_JUDGE_SUMMARY_GRADE_FMT",
		_grade_fallback_fmt(),
		[localized_grade]
	))

	var localized_formula_name := matched_formula_name
	if not matched_formula_id.is_empty():
		localized_formula_name = LocalizedName.formula(
			matched_formula_id,
			matched_formula_name
		)

	if not localized_formula_name.is_empty():
		# 优先复用 JudgementResult 界面已经使用的统一翻译 key。
		lines.append(_tr_fmt(
			"UI_RESULT_FORMULA_FMT",
			_formula_fallback_fmt(),
			[localized_formula_name]
		))
	elif not matched_formula_id.is_empty():
		lines.append(_tr_fmt(
			"UI_JUDGE_SUMMARY_FORMULA_ID_FMT",
			_formula_id_fallback_fmt(),
			[matched_formula_id]
		))

	var localized_disease_message := _localized_disease_result_message()
	if not localized_disease_message.is_empty():
		# UI_RESULT_DIAGNOSIS_FMT 已由当前判定结果窗口使用。
		lines.append(_tr_fmt(
			"UI_RESULT_DIAGNOSIS_FMT",
			_diagnosis_fallback_fmt(),
			[localized_disease_message]
		))

	# 下面几类详细误差目前主要用于调试/兼容旧结果。
	# 如果翻译表中已经加入对应 key，会自动使用；否则保持四语 fallback。
	if not missing_herb_names.is_empty():
		lines.append(_tr_fmt(
			"UI_JUDGE_SUMMARY_MISSING_HERBS_FMT",
			_missing_herbs_fallback_fmt(),
			[_localized_herb_list(missing_herb_ids, missing_herb_names)]
		))

	if not extra_herb_names.is_empty():
		lines.append(_tr_fmt(
			"UI_JUDGE_SUMMARY_EXTRA_HERBS_FMT",
			_extra_herbs_fallback_fmt(),
			[_localized_herb_list(extra_herb_ids, extra_herb_names)]
		))

	if not minor_dosage_errors.is_empty():
		lines.append(_translate_with_fallback(
			"UI_JUDGE_SUMMARY_MINOR_DOSAGE",
			_minor_dosage_fallback()
		))
		for item in minor_dosage_errors:
			lines.append("- " + item)

	if not major_dosage_error_data.is_empty():
		lines.append(_translate_with_fallback(
			"UI_JUDGE_SUMMARY_MAJOR_DOSAGE",
			_major_dosage_fallback()
		))
		for item in major_dosage_error_data:
			lines.append("- " + _localized_dosage_error_line(item))
	elif not major_dosage_errors.is_empty():
		lines.append(_translate_with_fallback(
			"UI_JUDGE_SUMMARY_MAJOR_DOSAGE",
			_major_dosage_fallback()
		))
		for item in major_dosage_errors:
			lines.append("- " + item)

	return "\n".join(lines)


func _localized_result_message() -> String:
	var locale := TranslationServer.get_locale().to_lower()

	if locale.begins_with("en") and not english_message.is_empty():
		return english_message
	if locale.begins_with("ja") and not japanese_message.is_empty():
		return japanese_message
	if locale.begins_with("ko") and not korean_message.is_empty():
		return korean_message

	return message


func _localized_disease_result_message() -> String:
	var locale := TranslationServer.get_locale().to_lower()

	if locale.begins_with("en") and not english_disease_message.is_empty():
		return english_disease_message
	if locale.begins_with("ja") and not japanese_disease_message.is_empty():
		return japanese_disease_message
	if locale.begins_with("ko") and not korean_disease_message.is_empty():
		return korean_disease_message

	return disease_message


func _get_grade_translation_key() -> String:
	match level:
		"perfect":
			return "UI_RESULT_GRADE_PERFECT"
		"pass":
			return "UI_RESULT_GRADE_SUCCESS"
		"fail":
			return "UI_RESULT_GRADE_FAILED"

	# 兼容旧数据：如果没有稳定 level，就继续读取中文 grade。
	match grade:
		"妙手回春":
			return "UI_RESULT_GRADE_PERFECT"
		"治疗成功":
			return "UI_RESULT_GRADE_SUCCESS"
		"治疗失败":
			return "UI_RESULT_GRADE_FAILED"

	return ""


func _translate_with_fallback(key: String, fallback: String) -> String:
	if key.is_empty():
		return fallback

	var translated := TranslationServer.translate(key)
	if translated.strip_edges().is_empty() or translated == key:
		return fallback

	return translated


func _tr_fmt(key: String, fallback_format: String, args: Array) -> String:
	var format_text := _translate_with_fallback(key, fallback_format)

	if args.size() == 1:
		return format_text % args[0]

	return format_text % args


func _localized_herb_list(
	herb_ids: Array[String],
	herb_names: Array[String]
) -> String:
	var names: Array[String] = []

	for index in range(herb_names.size()):
		var fallback := herb_names[index]
		var herb_id := herb_ids[index] if index < herb_ids.size() else ""

		if not herb_id.is_empty():
			names.append(LocalizedName.herb(herb_id, fallback))
		else:
			names.append(fallback)

	return _list_separator().join(names)


func _list_separator() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	return ", " if locale.begins_with("en") else "、"


func _localized_dosage_error_line(data: Dictionary) -> String:
	var herb_id := str(data.get("herb_id", "")).strip_edges()
	var fallback_name := str(data.get("herb_name", herb_id)).strip_edges()
	var herb_name := (
		LocalizedName.herb(herb_id, fallback_name)
		if not herb_id.is_empty()
		else fallback_name
	)

	return _tr_fmt(
		"UI_JUDGE_SUMMARY_DOSAGE_ERROR_FMT",
		_dosage_error_fallback_fmt(),
		[
			herb_name,
			HerbUnit.format_fen_auto(int(data.get("player_fen", 0))),
			HerbUnit.format_fen_auto(int(data.get("standard_fen", 0)))
		]
	)


func _dosage_error_fallback_fmt() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "%s: actual %s, standard %s"
	if locale.begins_with("ja"):
		return "%s：実際 %s、基準 %s"
	if locale.begins_with("ko"):
		return "%s: 실제 %s, 기준 %s"
	return "%s：实际 %s，标准 %s"


func _score_fallback_fmt() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Score: %d"
	if locale.begins_with("ja"):
		return "得点：%d"
	if locale.begins_with("ko"):
		return "점수: %d"
	return "评分：%d"


func _grade_fallback_fmt() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Grade: %s"
	if locale.begins_with("ja"):
		return "評価：%s"
	if locale.begins_with("ko"):
		return "평가: %s"
	return "评价：%s"


func _formula_fallback_fmt() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Standard Prescription: %s"
	if locale.begins_with("ja"):
		return "標準処方：%s"
	if locale.begins_with("ko"):
		return "표준 처방: %s"
	return "标准方：%s"


func _formula_id_fallback_fmt() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Standard Prescription ID: %s"
	if locale.begins_with("ja"):
		return "標準処方 ID：%s"
	if locale.begins_with("ko"):
		return "표준 처방 ID: %s"
	return "标准方 ID：%s"


func _diagnosis_fallback_fmt() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Diagnosis: %s"
	if locale.begins_with("ja"):
		return "診断：%s"
	if locale.begins_with("ko"):
		return "진단: %s"
	return "断病：%s"


func _missing_herbs_fallback_fmt() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Missing herbs: %s"
	if locale.begins_with("ja"):
		return "不足薬材：%s"
	if locale.begins_with("ko"):
		return "누락 약재: %s"
	return "缺少药材：%s"


func _extra_herbs_fallback_fmt() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Extra herbs: %s"
	if locale.begins_with("ja"):
		return "余分な薬材：%s"
	if locale.begins_with("ko"):
		return "불필요한 약재: %s"
	return "多余药材：%s"


func _minor_dosage_fallback() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Minor dosage deviations:"
	if locale.begins_with("ja"):
		return "用量の軽微なずれ："
	if locale.begins_with("ko"):
		return "경미한 용량 편차:"
	return "剂量轻微偏差："


func _major_dosage_fallback() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en"):
		return "Major dosage deviations:"
	if locale.begins_with("ja"):
		return "用量の大きなずれ："
	if locale.begins_with("ko"):
		return "심각한 용량 편차:"
	return "剂量严重偏差："

# =========================================================
# 七、调试输出
# =========================================================

func debug_print() -> void:
	print("===== JudgeResult =====")
	print("success: ", success)
	print("level: ", level)
	print("score: ", score)
	print("grade: ", grade)
	print("message: ", message)
	print("matched_formula_id: ", matched_formula_id)
	print("matched_formula_name: ", matched_formula_name)	
	print("player_disease_id: ", player_disease_id)
	print("player_disease_name: ", player_disease_name)
	print("standard_disease_id: ", standard_disease_id)
	print("standard_disease_name: ", standard_disease_name)
	print("disease_correct: ", disease_correct)
	print("disease_penalty: ", disease_penalty)
	print("disease_message: ", disease_message)
	print("standard_herb_count: ", standard_herb_count)
	print("player_herb_count: ", player_herb_count)
	print("matched_herb_count: ", matched_herb_count)

	print("missing_herb_names: ", missing_herb_names)
	print("extra_herb_names: ", extra_herb_names)
	print("minor_dosage_errors: ", minor_dosage_errors)
	print("major_dosage_errors: ", major_dosage_errors)
	print("=======================")


# =========================================================
# 八、转字典（可选，用于存档/日志）
# =========================================================

func to_dict() -> Dictionary:
	return {
		"success": success,
		"level": level,
		"score": score,
		"grade": grade,
		"message": message,

		"matched_formula_id": matched_formula_id,
		"matched_formula_name": matched_formula_name,

		"player_disease_id": player_disease_id,
		"player_disease_name": player_disease_name,
		"standard_disease_id": standard_disease_id,
		"standard_disease_name": standard_disease_name,
		"disease_correct": disease_correct,
		"disease_penalty": disease_penalty,
		"disease_message": disease_message,

		"missing_herb_ids": missing_herb_ids.duplicate(),
		"missing_herb_names": missing_herb_names.duplicate(),

		"extra_herb_ids": extra_herb_ids.duplicate(),
		"extra_herb_names": extra_herb_names.duplicate(),

		"minor_dosage_errors": minor_dosage_errors.duplicate(),
		"major_dosage_errors": major_dosage_errors.duplicate(),
		"major_dosage_error_data": major_dosage_error_data.duplicate(true),

		"standard_herb_count": standard_herb_count,
		"player_herb_count": player_herb_count,
		"matched_herb_count": matched_herb_count
	}
