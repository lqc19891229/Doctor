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
# 第一版建议区间：
# perfect = 100
# pass    = 60~99
# fail    = 0~59
var score: int = 0

# 给玩家或 UI 显示的主信息
var message: String = ""


# =========================================================
# 二、匹配到的标准方信息
# =========================================================

var matched_formula_id: String = ""
var matched_formula_name: String = ""


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

	if message != "":
		lines.append(message)

	lines.append("评分：%d" % score)

	if matched_formula_name != "":
		lines.append("标准方：%s" % matched_formula_name)
	elif matched_formula_id != "":
		lines.append("标准方 ID：%s" % matched_formula_id)

	if not missing_herb_names.is_empty():
		lines.append("缺少药材：%s" % "、".join(missing_herb_names))

	if not extra_herb_names.is_empty():
		lines.append("多余药材：%s" % "、".join(extra_herb_names))

	if not minor_dosage_errors.is_empty():
		lines.append("剂量轻微偏差：")
		for item in minor_dosage_errors:
			lines.append("- " + item)

	if not major_dosage_errors.is_empty():
		lines.append("剂量严重偏差：")
		for item in major_dosage_errors:
			lines.append("- " + item)

	return "\n".join(lines)


# =========================================================
# 七、调试输出
# =========================================================

func debug_print() -> void:
	print("===== JudgeResult =====")
	print("success: ", success)
	print("level: ", level)
	print("score: ", score)
	print("message: ", message)
	print("matched_formula_id: ", matched_formula_id)
	print("matched_formula_name: ", matched_formula_name)
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
		"message": message,

		"matched_formula_id": matched_formula_id,
		"matched_formula_name": matched_formula_name,

		"missing_herb_ids": missing_herb_ids.duplicate(),
		"missing_herb_names": missing_herb_names.duplicate(),

		"extra_herb_ids": extra_herb_ids.duplicate(),
		"extra_herb_names": extra_herb_names.duplicate(),

		"minor_dosage_errors": minor_dosage_errors.duplicate(),
		"major_dosage_errors": major_dosage_errors.duplicate(),

		"standard_herb_count": standard_herb_count,
		"player_herb_count": player_herb_count,
		"matched_herb_count": matched_herb_count
	}
