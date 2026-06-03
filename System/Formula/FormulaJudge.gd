extends RefCounted
class_name FormulaJudge

# =========================================================
# FormulaJudge.gd
# 方剂判定器（区域判定版）
#
# 当前规则：
# 1. 基础分 100
# 2. 疾病判断：
#    - 正确：扣 0 分
#    - 未选择或选择错误：统一扣 100 分
# 3. 处方判定：
#    - 按君、臣、佐、使四个区域整体判断
#    - 每个区域只要有任何错误，就扣该区域固定分
#    - 君：40，臣：30，佐：20，使：10
#    - 区域错误包括：缺少、多出、放错区域、剂量不一致
# 4. 综合评分 = max(0, 100 - 疾病扣分 - 处方扣分)
# 5. 等级：
#    - 100：妙手回春
#    - 90~99：甲等
#    - 70~89：乙等
#    - 40~69：丙等
#    - 0~39：丁等
# =========================================================

const ROLE_ORDER: Array[String] = ["君", "臣", "佐", "使"]


# =========================================================
# 一、主入口
# =========================================================
func judge_formula(player_prescription: Prescription, standard_formula: FormulaData, standard_disease: DiseaseData = null) -> JudgeResult:
	var result := JudgeResult.new()

	if player_prescription == null:
		result.success = false
		result.level = "fail"
		result.score = 0
		result.grade = "丁等"
		result.message = "玩家处方为空"
		return result

	if standard_formula == null:
		result.success = false
		result.level = "fail"
		result.score = 0
		result.grade = "丁等"
		result.message = "未找到标准方剂"
		return result

	result.matched_formula_id = standard_formula.formula_id
	result.matched_formula_name = standard_formula.formula_name

	var player_info: Dictionary = player_prescription.build_role_maps()
	var standard_info: Dictionary = _build_standard_formula_info(standard_formula)

	var player_fen_map: Dictionary = player_info.get("fen_map", {})
	var player_name_map: Dictionary = player_info.get("name_map", {})
	var player_role_map: Dictionary = player_info.get("role_map", {})

	var standard_fen_map: Dictionary = standard_info.get("fen_map", {})
	var standard_name_map: Dictionary = standard_info.get("name_map", {})
	var standard_role_map: Dictionary = standard_info.get("role_map", {})

	result.standard_herb_count = standard_fen_map.size()
	result.player_herb_count = player_fen_map.size()

	var total_penalty := 0
	var penalty_lines: Array[String] = []
	var role_display_map := _make_empty_role_display_map()

	var disease_penalty := _judge_disease(player_prescription, standard_disease, result)
	total_penalty += disease_penalty
	if disease_penalty > 0:
		penalty_lines.append("疾病判断错误，扣 %d 分" % disease_penalty)

	for role_name in ROLE_ORDER:
		var role_problem_texts: Array[String] = _get_role_problem_texts(
			role_name,
			player_fen_map,
			player_name_map,
			player_role_map,
			standard_fen_map,
			standard_name_map,
			standard_role_map
		)

		if role_problem_texts.is_empty():
			role_display_map[role_name].append("正确")
			continue

		var role_penalty := _get_role_penalty(role_name)
		total_penalty += role_penalty
		role_display_map[role_name].append("错误 -%d" % role_penalty)
		penalty_lines.append("%s药区错误：%s，扣 %d 分" % [role_name, "；".join(role_problem_texts), role_penalty])

		_record_role_problems_to_result(role_problem_texts, result)

	result.score = max(0, 100 - total_penalty)
	result.grade = _get_score_grade(result.score)

	if result.score == 100:
		result.success = true
		result.level = "perfect"
	elif result.score >= 40:
		result.success = true
		result.level = "pass"
	else:
		result.success = false
		result.level = "fail"

	if penalty_lines.is_empty():
		result.message = _build_role_display_text(role_display_map)
	else:
		result.message = _build_role_display_text(role_display_map) + "\n\n扣分明细：\n- " + "\n- ".join(penalty_lines)

	return result


# =========================================================
# 二、疾病诊断判定
# =========================================================
func _judge_disease(player_prescription: Prescription, standard_disease: DiseaseData, result: JudgeResult) -> int:
	if result == null:
		return 0

	if standard_disease == null:
		result.disease_correct = false
		result.disease_penalty = 0
		result.disease_message = "标准疾病缺失"
		return 0

	var player_disease_id := ""
	var player_disease_name := ""
	if player_prescription != null:
		player_disease_id = player_prescription.disease_id.strip_edges()
		player_disease_name = player_prescription.disease_name.strip_edges()

	var standard_disease_id := standard_disease.disease_id.strip_edges()
	var standard_disease_name := standard_disease.disease_name.strip_edges()

	result.player_disease_id = player_disease_id
	result.player_disease_name = player_disease_name
	result.standard_disease_id = standard_disease_id
	result.standard_disease_name = standard_disease_name

	if standard_disease_id == "":
		result.disease_correct = false
		result.disease_penalty = 0
		result.disease_message = "标准疾病缺少 disease_id"
		return 0

	if player_disease_id == standard_disease_id:
		result.disease_correct = true
		result.disease_penalty = 0
		if player_disease_name == "":
			player_disease_name = standard_disease_name
		result.player_disease_name = player_disease_name
		result.disease_message = "%s✅️" % player_disease_name
		return 0

	result.disease_correct = false
	result.disease_penalty = 100
	if player_disease_id == "":
		result.disease_message = "未选择疾病❌️，正确：%s -100" % standard_disease_name
	elif player_disease_name == "":
		result.disease_message = "%s❌️，正确：%s -100" % [player_disease_id, standard_disease_name]
	else:
		result.disease_message = "%s❌️，正确：%s -100" % [player_disease_name, standard_disease_name]
	return result.disease_penalty


# =========================================================
# 三、区域错误判断
# =========================================================
func _get_role_problem_texts(
	role_name: String,
	player_fen_map: Dictionary,
	player_name_map: Dictionary,
	player_role_map: Dictionary,
	standard_fen_map: Dictionary,
	standard_name_map: Dictionary,
	standard_role_map: Dictionary
) -> Array[String]:
	var problems: Array[String] = []

	for herb_id in standard_fen_map.keys():
		if str(standard_role_map.get(herb_id, "")) != role_name:
			continue

		var herb_name: String = str(standard_name_map.get(herb_id, herb_id))
		var standard_fen: int = int(standard_fen_map.get(herb_id, 0))

		if not player_fen_map.has(herb_id):
			problems.append("缺少【%s】" % herb_name)
			continue

		var player_role_name: String = str(player_role_map.get(herb_id, ""))
		if player_role_name != role_name:
			problems.append("【%s】放错区域，实际在%s药区" % [herb_name, player_role_name])
			continue

		var player_fen: int = int(player_fen_map.get(herb_id, 0))
		if player_fen != standard_fen:
			problems.append("【%s】剂量错误，标准%s，实际%s" % [
				herb_name,
				HerbUnit.format_fen_auto(standard_fen),
				HerbUnit.format_fen_auto(player_fen)
			])
			continue

	for herb_id in player_fen_map.keys():
		if str(player_role_map.get(herb_id, "")) != role_name:
			continue

		var herb_name: String = str(player_name_map.get(herb_id, herb_id))

		if not standard_fen_map.has(herb_id):
			problems.append("多出【%s】" % herb_name)
			continue

		var standard_role_name: String = str(standard_role_map.get(herb_id, ""))
		if standard_role_name != role_name:
			problems.append("【%s】不属于%s药区，标准为%s药区" % [herb_name, role_name, standard_role_name])
			continue

	return problems


func _record_role_problems_to_result(problem_texts: Array[String], result: JudgeResult) -> void:
	if result == null:
		return

	for text in problem_texts:
		if text.begins_with("缺少"):
			result.missing_herb_names.append(text)
		elif text.begins_with("多出"):
			result.extra_herb_names.append(text)
		elif text.find("剂量错误") >= 0:
			result.major_dosage_errors.append(text)
		else:
			result.extra_herb_names.append(text)


# =========================================================
# 四、构建标准方信息
# =========================================================
func _build_standard_formula_info(formula: FormulaData) -> Dictionary:
	var fen_map: Dictionary = {}
	var name_map: Dictionary = {}
	var role_map: Dictionary = {}

	if formula == null:
		return {
			"fen_map": fen_map,
			"name_map": name_map,
			"role_map": role_map
		}

	for ingredient in formula.jun_group:
		_append_ingredient_info(ingredient, "君", fen_map, name_map, role_map)
	for ingredient in formula.chen_group:
		_append_ingredient_info(ingredient, "臣", fen_map, name_map, role_map)
	for ingredient in formula.zuo_group:
		_append_ingredient_info(ingredient, "佐", fen_map, name_map, role_map)
	for ingredient in formula.shi_group:
		_append_ingredient_info(ingredient, "使", fen_map, name_map, role_map)

	return {
		"fen_map": fen_map,
		"name_map": name_map,
		"role_map": role_map
	}


func _append_ingredient_info(
	ingredient: FormulaIngredient,
	role_name: String,
	fen_map: Dictionary,
	name_map: Dictionary,
	role_map: Dictionary
) -> void:
	if ingredient == null:
		return
	if not ingredient.is_valid_data():
		return

	var herb_id := ingredient.get_herb_id()
	if herb_id == "":
		return

	var herb_name := ingredient.get_herb_name()
	if herb_name == "":
		herb_name = herb_id

	fen_map[herb_id] = ingredient.get_amount_in_fen()
	name_map[herb_id] = herb_name
	role_map[herb_id] = role_name


# =========================================================
# 五、扣分与等级
# =========================================================
func _get_role_penalty(role_name: String) -> int:
	match role_name:
		"君":
			return 40
		"臣":
			return 30
		"佐":
			return 20
		"使":
			return 10
		_:
			return 10


func _get_score_grade(score: int) -> String:
	if score == 100:
		return "妙手回春"
	if score >= 90:
		return "甲等"
	if score >= 70:
		return "乙等"
	if score >= 40:
		return "丙等"
	return "丁等"


# =========================================================
# 六、显示辅助
# =========================================================
func _make_empty_role_display_map() -> Dictionary:
	return {
		"君": [],
		"臣": [],
		"佐": [],
		"使": []
	}


func _build_role_display_text(role_display_map: Dictionary) -> String:
	var lines: Array[String] = []
	for role_name in ROLE_ORDER:
		var items: Array[String] = _to_string_array(role_display_map.get(role_name, []))
		lines.append("%s：%s" % [role_name, _join_or_placeholder(items)])
	return "\n".join(lines)


func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result


func _join_or_placeholder(items: Array[String]) -> String:
	if items.is_empty():
		return "（无）"
	return "、".join(items)


# =========================================================
# 七、快速测试
# =========================================================
func judge_and_print(player_prescription: Prescription, standard_formula: FormulaData) -> JudgeResult:
	var result := judge_formula(player_prescription, standard_formula)
	result.debug_print()
	print(result.get_summary_text())
	return result
