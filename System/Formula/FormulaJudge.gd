extends RefCounted
class_name FormulaJudge

# =========================================================
# FormulaJudge.gd
# 方剂判定器（区域判定版 / 本地化兼容版）
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
#    - 60~99：治疗成功
#    - 0~59：治疗失败
#
# 本地化：
# - 内部逻辑仍使用稳定的中文角色值 / 英文 level。
# - JudgeResult 中同时保留中文兼容字段和英 / 日 / 韩显示字段。
# - 缺少 / 多余药材额外记录 herb_id，供 JudgeResult 在切换语言时重新本地化。
# =========================================================

const ROLE_ORDER: Array[String] = ["君", "臣", "佐", "使"]


# =========================================================
# 一、主入口
# =========================================================
func judge_formula(
	player_prescription: Prescription,
	standard_formula: FormulaData,
	standard_disease: DiseaseData = null
) -> JudgeResult:
	var result := JudgeResult.new()

	if player_prescription == null:
		result.success = false
		result.level = "fail"
		result.score = 0
		result.grade = "治疗失败"
		result.message = "玩家处方为空"
		result.english_message = "The prescription is empty."
		result.korean_message = "처방이 비어 있습니다."
		result.japanese_message = "処方が空です。"
		return result

	if standard_formula == null:
		result.success = false
		result.level = "fail"
		result.score = 0
		result.grade = "治疗失败"
		result.message = "未找到标准方剂"
		result.english_message = "No standard prescription was found."
		result.korean_message = "표준 처방을 찾을 수 없습니다."
		result.japanese_message = "標準処方が見つかりません。"
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
	result.matched_herb_count = _count_matched_herbs(
		player_fen_map,
		player_role_map,
		standard_fen_map,
		standard_role_map
	)

	var total_penalty := 0

	var penalty_lines: Array[String] = []
	var english_penalty_lines: Array[String] = []
	var japanese_penalty_lines: Array[String] = []
	var korean_penalty_lines: Array[String] = []

	var role_display_map := _make_empty_role_display_map()
	var english_role_display_map := _make_empty_role_display_map()
	var japanese_role_display_map := _make_empty_role_display_map()
	var korean_role_display_map := _make_empty_role_display_map()

	var disease_penalty := _judge_disease(
		player_prescription,
		standard_disease,
		result
	)

	total_penalty += disease_penalty

	if disease_penalty > 0:
		penalty_lines.append("疾病判断错误，扣 %d 分" % disease_penalty)
		english_penalty_lines.append(
			"Diagnosis error: -%d points" % disease_penalty
		)
		japanese_penalty_lines.append(
			"診断誤り：%d点減点" % disease_penalty
		)
		korean_penalty_lines.append(
			"진단 오류: %d점 감점" % disease_penalty
		)

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
			english_role_display_map[role_name].append("Correct")
			japanese_role_display_map[role_name].append("正解")
			korean_role_display_map[role_name].append("정확")
			continue

		var role_penalty := _get_role_penalty(role_name)
		total_penalty += role_penalty

		role_display_map[role_name].append("错误 -%d" % role_penalty)
		penalty_lines.append(
			"%s药区错误：%s，扣 %d 分"
			% [role_name, "；".join(role_problem_texts), role_penalty]
		)

		var english_problems := _get_role_problem_texts(
			role_name,
			player_fen_map,
			player_name_map,
			player_role_map,
			standard_fen_map,
			standard_name_map,
			standard_role_map,
			false,
			false,
			true
		)
		english_role_display_map[role_name].append(
			"Error -%d" % role_penalty
		)
		english_penalty_lines.append(
			"%s error: %s (-%d points)"
			% [
				_localized_role_name_for_locale(role_name, "en"),
				"; ".join(english_problems),
				role_penalty
			]
		)

		var japanese_problems := _get_role_problem_texts(
			role_name,
			player_fen_map,
			player_name_map,
			player_role_map,
			standard_fen_map,
			standard_name_map,
			standard_role_map,
			false,
			true,
			false
		)
		japanese_role_display_map[role_name].append(
			"誤り -%d" % role_penalty
		)
		japanese_penalty_lines.append(
			"%sの誤り：%s（%d点減点）"
			% [
				_localized_role_name_for_locale(role_name, "ja"),
				"；".join(japanese_problems),
				role_penalty
			]
		)

		var korean_problems := _get_role_problem_texts(
			role_name,
			player_fen_map,
			player_name_map,
			player_role_map,
			standard_fen_map,
			standard_name_map,
			standard_role_map,
			true,
			false,
			false
		)
		korean_role_display_map[role_name].append(
			"오류 -%d" % role_penalty
		)
		korean_penalty_lines.append(
			"%s 오류: %s (%d점 감점)"
			% [
				_localized_role_name_for_locale(role_name, "ko"),
				"; ".join(korean_problems),
				role_penalty
			]
		)

		_record_role_problems_to_result(
			role_name,
			player_fen_map,
			player_name_map,
			player_role_map,
			standard_fen_map,
			standard_name_map,
			standard_role_map,
			result
		)

	result.score = max(0, 100 - total_penalty)
	result.grade = _get_score_grade(result.score)

	if result.score == 100:
		result.success = true
		result.level = "perfect"
	elif result.score >= 60:
		result.success = true
		result.level = "pass"
	else:
		result.success = false
		result.level = "fail"

	result.message = _build_role_display_text(
		role_display_map,
		"zh_CN"
	)
	if not penalty_lines.is_empty():
		result.message += (
			"\n\n扣分明细：\n- "
			+ "\n- ".join(penalty_lines)
		)

	result.english_message = _build_role_display_text(
		english_role_display_map,
		"en"
	)
	if not english_penalty_lines.is_empty():
		result.english_message += (
			"\n\nDeductions:\n- "
			+ "\n- ".join(english_penalty_lines)
		)

	result.japanese_message = _build_role_display_text(
		japanese_role_display_map,
		"ja"
	)
	if not japanese_penalty_lines.is_empty():
		result.japanese_message += (
			"\n\n減点の内訳：\n- "
			+ "\n- ".join(japanese_penalty_lines)
		)

	result.korean_message = _build_role_display_text(
		korean_role_display_map,
		"ko"
	)
	if not korean_penalty_lines.is_empty():
		result.korean_message += (
			"\n\n감점 내역:\n- "
			+ "\n- ".join(korean_penalty_lines)
		)

	return result


# =========================================================
# 二、疾病诊断判定
# =========================================================
func _judge_disease(
	player_prescription: Prescription,
	standard_disease: DiseaseData,
	result: JudgeResult
) -> int:
	if result == null:
		return 0

	if standard_disease == null:
		result.disease_correct = false
		result.disease_penalty = 0
		result.disease_message = "标准疾病缺失"
		result.english_disease_message = "No standard disease is configured."
		result.japanese_disease_message = "標準の病名が設定されていません。"
		result.korean_disease_message = "표준 병증 정보가 없습니다."
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
		result.english_disease_message = "The standard disease has no disease_id."
		result.japanese_disease_message = "標準の病名IDがありません。"
		result.korean_disease_message = "표준 병증 ID가 없습니다."
		return 0

	var localized_standard_en := _localized_disease_for_locale(
		standard_disease_id,
		standard_disease_name,
		"en"
	)
	var localized_standard_ja := _localized_disease_for_locale(
		standard_disease_id,
		standard_disease_name,
		"ja"
	)
	var localized_standard_ko := _localized_disease_for_locale(
		standard_disease_id,
		standard_disease_name,
		"ko"
	)

	if player_disease_id == standard_disease_id:
		result.disease_correct = true
		result.disease_penalty = 0

		if player_disease_name == "":
			player_disease_name = standard_disease_name

		result.player_disease_name = player_disease_name
		result.disease_message = "%s✅️" % player_disease_name
		result.english_disease_message = "%s✅️" % localized_standard_en
		result.japanese_disease_message = "%s✅️" % localized_standard_ja
		result.korean_disease_message = "%s✅️" % localized_standard_ko
		return 0

	result.disease_correct = false
	result.disease_penalty = 100

	if player_disease_id == "":
		result.disease_message = (
			"未选择疾病❌️，正确：%s -100"
			% standard_disease_name
		)
		result.english_disease_message = (
			"No diagnosis selected❌️. Correct: %s (-100)"
			% localized_standard_en
		)
		result.japanese_disease_message = (
			"病名未選択❌️。正解：%s（-100）"
			% localized_standard_ja
		)
		result.korean_disease_message = (
			"병증을 선택하지 않았습니다❌️. 정답: %s (-100)"
			% localized_standard_ko
		)
		return result.disease_penalty

	var fallback_player_name := (
		player_disease_name
		if not player_disease_name.is_empty()
		else player_disease_id
	)

	var localized_player_en := _localized_disease_for_locale(
		player_disease_id,
		fallback_player_name,
		"en"
	)
	var localized_player_ja := _localized_disease_for_locale(
		player_disease_id,
		fallback_player_name,
		"ja"
	)
	var localized_player_ko := _localized_disease_for_locale(
		player_disease_id,
		fallback_player_name,
		"ko"
	)

	result.disease_message = (
		"%s❌️，正确：%s -100"
		% [fallback_player_name, standard_disease_name]
	)
	result.english_disease_message = (
		"%s❌️. Correct: %s (-100)"
		% [localized_player_en, localized_standard_en]
	)
	result.japanese_disease_message = (
		"%s❌️。正解：%s（-100）"
		% [localized_player_ja, localized_standard_ja]
	)
	result.korean_disease_message = (
		"%s❌️. 정답: %s (-100)"
		% [localized_player_ko, localized_standard_ko]
	)

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
	standard_role_map: Dictionary,
	korean: bool = false,
	japanese: bool = false,
	english: bool = false
) -> Array[String]:
	var problems: Array[String] = []

	for herb_id_value in standard_fen_map.keys():
		var herb_id := str(herb_id_value)

		if str(standard_role_map.get(herb_id_value, "")) != role_name:
			continue

		var herb_name := str(
			standard_name_map.get(herb_id_value, herb_id)
		)

		if english:
			herb_name = _localized_herb_for_locale(
				herb_id,
				herb_name,
				"en"
			)
		elif japanese:
			herb_name = _localized_herb_for_locale(
				herb_id,
				herb_name,
				"ja"
			)
		elif korean:
			herb_name = _localized_herb_for_locale(
				herb_id,
				herb_name,
				"ko"
			)

		var standard_fen := int(
			standard_fen_map.get(herb_id_value, 0)
		)

		if not player_fen_map.has(herb_id_value):
			if korean:
				problems.append("【%s】누락" % herb_name)
			elif japanese:
				problems.append("【%s】が不足" % herb_name)
			elif english:
				problems.append("Missing 【%s】" % herb_name)
			else:
				problems.append("缺少【%s】" % herb_name)
			continue

		var player_role_name := str(
			player_role_map.get(herb_id_value, "")
		)

		if player_role_name != role_name:
			if korean:
				problems.append(
					"【%s】잘못된 구역: %s"
					% [
						herb_name,
						_localized_role_name_for_locale(
							player_role_name,
							"ko"
						)
					]
				)
			elif japanese:
				problems.append(
					"【%s】の配置が違います。現在：%s"
					% [
						herb_name,
						_localized_role_name_for_locale(
							player_role_name,
							"ja"
						)
					]
				)
			elif english:
				problems.append(
					"【%s】 is in the wrong role: %s"
					% [
						herb_name,
						_localized_role_name_for_locale(
							player_role_name,
							"en"
						)
					]
				)
			else:
				problems.append(
					"【%s】放错区域，实际在%s药区"
					% [herb_name, player_role_name]
				)
			continue

		var player_fen := int(
			player_fen_map.get(herb_id_value, 0)
		)

		if player_fen != standard_fen:
			var standard_dose := _format_dose_for_locale(
				standard_fen,
				"ko" if korean else (
					"ja" if japanese else (
						"en" if english else "zh_CN"
					)
				)
			)
			var player_dose := _format_dose_for_locale(
				player_fen,
				"ko" if korean else (
					"ja" if japanese else (
						"en" if english else "zh_CN"
					)
				)
			)

			if korean:
				problems.append(
					"【%s】용량 오류: 기준 %s, 실제 %s"
					% [herb_name, standard_dose, player_dose]
				)
			elif japanese:
				problems.append(
					"【%s】の量が違います。基準：%s、実際：%s"
					% [herb_name, standard_dose, player_dose]
				)
			elif english:
				problems.append(
					"【%s】 dosage mismatch: standard %s, actual %s"
					% [herb_name, standard_dose, player_dose]
				)
			else:
				problems.append(
					"【%s】剂量错误，标准%s，实际%s"
					% [herb_name, standard_dose, player_dose]
				)
			continue

	for herb_id_value in player_fen_map.keys():
		var herb_id := str(herb_id_value)

		if str(player_role_map.get(herb_id_value, "")) != role_name:
			continue

		var herb_name := str(
			player_name_map.get(herb_id_value, herb_id)
		)

		if english:
			herb_name = _localized_herb_for_locale(
				herb_id,
				herb_name,
				"en"
			)
		elif japanese:
			herb_name = _localized_herb_for_locale(
				herb_id,
				herb_name,
				"ja"
			)
		elif korean:
			herb_name = _localized_herb_for_locale(
				herb_id,
				herb_name,
				"ko"
			)

		if not standard_fen_map.has(herb_id_value):
			if korean:
				problems.append("추가 약재【%s】" % herb_name)
			elif japanese:
				problems.append("余分な薬材【%s】" % herb_name)
			elif english:
				problems.append("Extra herb 【%s】" % herb_name)
			else:
				problems.append("多出【%s】" % herb_name)
			continue

		var standard_role_name := str(
			standard_role_map.get(herb_id_value, "")
		)

		if standard_role_name != role_name:
			if korean:
				problems.append(
					"【%s】%s 구역에 속하지 않습니다. 기준: %s"
					% [
						herb_name,
						_localized_role_name_for_locale(
							role_name,
							"ko"
						),
						_localized_role_name_for_locale(
							standard_role_name,
							"ko"
						)
					]
				)
			elif japanese:
				problems.append(
					"【%s】は%sではなく%sに配置します"
					% [
						herb_name,
						_localized_role_name_for_locale(
							role_name,
							"ja"
						),
						_localized_role_name_for_locale(
							standard_role_name,
							"ja"
						)
					]
				)
			elif english:
				problems.append(
					"【%s】 does not belong in %s; standard role: %s"
					% [
						herb_name,
						_localized_role_name_for_locale(
							role_name,
							"en"
						),
						_localized_role_name_for_locale(
							standard_role_name,
							"en"
						)
					]
				)
			else:
				problems.append(
					"【%s】不属于%s药区，标准为%s药区"
					% [
						herb_name,
						role_name,
						standard_role_name
					]
				)

	return problems


func _record_role_problems_to_result(
	role_name: String,
	player_fen_map: Dictionary,
	player_name_map: Dictionary,
	player_role_map: Dictionary,
	standard_fen_map: Dictionary,
	standard_name_map: Dictionary,
	standard_role_map: Dictionary,
	result: JudgeResult
) -> void:
	if result == null:
		return

	# 标准方中该区域应当存在的药材：
	# - 玩家没有：missing
	# - 玩家存在但角色错误：作为结构错误记录到 extra_herb_names
	# - 剂量不同：记录为 major dosage error
	for herb_id_value in standard_fen_map.keys():
		if str(standard_role_map.get(herb_id_value, "")) != role_name:
			continue

		var herb_id := str(herb_id_value)
		var herb_name := str(
			standard_name_map.get(herb_id_value, herb_id)
		)

		if not player_fen_map.has(herb_id_value):
			_append_unique(result.missing_herb_ids, herb_id)
			_append_unique(result.missing_herb_names, herb_name)
			continue

		var player_role_name := str(
			player_role_map.get(herb_id_value, "")
		)

		if player_role_name != role_name:
			_append_unique(result.extra_herb_ids, herb_id)
			_append_unique(
				result.extra_herb_names,
				"%s（%s→%s）"
				% [herb_name, player_role_name, role_name]
			)
			continue

		var player_fen := int(
			player_fen_map.get(herb_id_value, 0)
		)
		var standard_fen := int(
			standard_fen_map.get(herb_id_value, 0)
		)

		if player_fen != standard_fen:
			_append_unique(
				result.major_dosage_errors,
				"%s：%s → %s"
				% [
					herb_name,
					HerbUnit.format_fen_auto(player_fen),
					HerbUnit.format_fen_auto(standard_fen)
				]
			)
			result.major_dosage_error_data.append({
				"herb_id": herb_id,
				"herb_name": herb_name,
				"player_fen": player_fen,
				"standard_fen": standard_fen
			})

	# 玩家在该区域多放的药材。
	for herb_id_value in player_fen_map.keys():
		if str(player_role_map.get(herb_id_value, "")) != role_name:
			continue

		if standard_fen_map.has(herb_id_value):
			continue

		var herb_id := str(herb_id_value)
		var herb_name := str(
			player_name_map.get(herb_id_value, herb_id)
		)

		_append_unique(result.extra_herb_ids, herb_id)
		_append_unique(result.extra_herb_names, herb_name)


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
		_append_ingredient_info(
			ingredient,
			"君",
			fen_map,
			name_map,
			role_map
		)

	for ingredient in formula.chen_group:
		_append_ingredient_info(
			ingredient,
			"臣",
			fen_map,
			name_map,
			role_map
		)

	for ingredient in formula.zuo_group:
		_append_ingredient_info(
			ingredient,
			"佐",
			fen_map,
			name_map,
			role_map
		)

	for ingredient in formula.shi_group:
		_append_ingredient_info(
			ingredient,
			"使",
			fen_map,
			name_map,
			role_map
		)

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

	if score >= 60:
		return "治疗成功"

	return "治疗失败"


func _count_matched_herbs(
	player_fen_map: Dictionary,
	player_role_map: Dictionary,
	standard_fen_map: Dictionary,
	standard_role_map: Dictionary
) -> int:
	var count := 0

	for herb_id in standard_fen_map.keys():
		if not player_fen_map.has(herb_id):
			continue

		if (
			str(player_role_map.get(herb_id, ""))
			!= str(standard_role_map.get(herb_id, ""))
		):
			continue

		count += 1

	return count


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


func _build_role_display_text(
	role_display_map: Dictionary,
	locale: String
) -> String:
	var lines: Array[String] = []

	for role_name in ROLE_ORDER:
		var items: Array[String] = _to_string_array(
			role_display_map.get(role_name, [])
		)

		var separator := " · "
		var colon := ": "

		if locale.begins_with("zh"):
			separator = "、"
			colon = "："
		elif locale.begins_with("ja"):
			separator = "・"
			colon = "："

		lines.append(
			"%s%s%s"
			% [
				_localized_role_name_for_locale(
					role_name,
					locale
				),
				colon,
				separator.join(items)
			]
		)

	return "\n".join(lines)


func _localized_role_name_for_locale(
	role_name: String,
	locale: String
) -> String:
	var key := ""

	match role_name:
		"君":
			key = "UI_PRESCRIPTION_ROLE_JUN"
		"臣":
			key = "UI_PRESCRIPTION_ROLE_CHEN"
		"佐":
			key = "UI_PRESCRIPTION_ROLE_ZUO"
		"使":
			key = "UI_PRESCRIPTION_ROLE_SHI"
		_:
			return role_name

	return _translate_key_for_locale(
		key,
		locale,
		role_name
	)


func _localized_herb_for_locale(
	herb_id: String,
	fallback: String,
	locale: String
) -> String:
	if herb_id.strip_edges().is_empty():
		return fallback

	var key := "UI_BOOK_ENTRY_TITLE_" + herb_id.to_upper()

	return _translate_key_for_locale(
		key,
		locale,
		fallback
	)


func _localized_disease_for_locale(
	disease_id: String,
	fallback: String,
	locale: String
) -> String:
	if disease_id.strip_edges().is_empty():
		return fallback

	var key := "UI_BOOK_ENTRY_TITLE_" + disease_id.to_upper()

	return _translate_key_for_locale(
		key,
		locale,
		fallback
	)


func _translate_key_for_locale(
	key: String,
	locale: String,
	fallback: String
) -> String:
	if key.is_empty():
		return fallback

	# 不切换全局 locale，避免 judge_formula() 在生成多语言兼容字段时
	# 触发 NOTIFICATION_TRANSLATION_CHANGED。
	var translation := TranslationServer.get_translation_object(locale)
	if translation == null:
		return fallback

	var translated := str(translation.get_message(key))

	if translated.strip_edges().is_empty() or translated == key:
		return fallback

	return translated


func _format_dose_for_locale(
	total_fen: int,
	locale: String
) -> String:
	if total_fen <= 0:
		return _translate_key_for_locale(
			"UI_PRESCRIPTION_ZERO_FEN",
			locale,
			"0分"
		)

	var remaining := total_fen
	var parts: Array[String] = []

	for unit_data in [
		[HerbUnit.FEN_PER_JIN, "UI_PRESCRIPTION_UNIT_JIN", "斤"],
		[HerbUnit.FEN_PER_LIANG, "UI_PRESCRIPTION_UNIT_LIANG", "两"],
		[HerbUnit.FEN_PER_QIAN, "UI_PRESCRIPTION_UNIT_QIAN", "钱"],
		[HerbUnit.FEN_PER_FEN, "UI_PRESCRIPTION_UNIT_FEN", "分"]
	]:
		var unit_size: int = unit_data[0]
		var count: int = remaining / unit_size

		if count <= 0:
			continue

		var unit_text := _translate_key_for_locale(
			unit_data[1],
			locale,
			unit_data[2]
		)

		parts.append("%d %s" % [count, unit_text])
		remaining %= unit_size

	return " ".join(parts)


func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for item in value:
			result.append(str(item))

	return result


func _append_unique(array: Array[String], value: String) -> void:
	var clean_value := value.strip_edges()

	if clean_value.is_empty():
		return

	if not array.has(clean_value):
		array.append(clean_value)
