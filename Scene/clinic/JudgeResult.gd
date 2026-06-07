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
# 甲等     = 90~99
# 乙等     = 70~89
# 丙等     = 40~69
# 丁等     = 0~39
var score: int = 0

# 评价等级
# 妙手回春：100分
# 甲等：90~99分
# 乙等：70~89分
# 丙等：40~69分
# 丁等：0~39分
var grade: String = "丁等"

# 给玩家或 UI 显示的主信息
var message: String = ""



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
	lines.append("评价：%s" % grade)

	if matched_formula_name != "":
		lines.append("标准方：%s" % matched_formula_name)
	elif matched_formula_id != "":
		lines.append("标准方 ID：%s" % matched_formula_id)

	if disease_message != "":
		lines.append("断病：%s" % disease_message)

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

		"standard_herb_count": standard_herb_count,
		"player_herb_count": player_herb_count,
		"matched_herb_count": matched_herb_count
	}
