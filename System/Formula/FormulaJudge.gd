extends RefCounted
class_name FormulaJudge

# =========================================================
# FormulaJudge.gd
# 方剂判定器（君臣佐使扣分版）
#
# 规则：
# 1. 满分 100
#
# 2. 配伍错误（缺少 / 多出）
# - 君药：-60
# - 臣药：-40
# - 佐药：-20
# - 使药：-10
#
# 3. 剂量错误
# - 严重错误：扣对应全值
# - 轻微错误：扣对应一半
#
# 4. 剂量严重错误判定
# error_ratio = abs(实际剂量 - 标准剂量) / 标准剂量
# - error_ratio >= 1/2 -> 严重错误
# - 0 < error_ratio < 1/2 -> 轻微错误
# - error_ratio == 0 -> 正确
#
# 5. 最终分数允许为负数
# score = 100 - total_penalty
#
# 6. 显示格式示例
# 君：麻黄✅️ 3钱✅️
# 臣：桂枝✅️ 3钱❌️ -40
# 佐：杏仁✅️、熟地黄❌️ -20
# 使：甘草✅️
# =========================================================


# =========================================================
# 一、主入口
# =========================================================
func judge_formula(player_prescription: Prescription, standard_formula: FormulaData) -> JudgeResult:
	var result := JudgeResult.new()

	# -------------------------
	# 1. 基础检查
	# -------------------------
	if player_prescription == null:
		result.success = false
		result.level = "fail"
		result.score = 0
		result.message = "玩家处方为空"
		return result

	if standard_formula == null:
		result.success = false
		result.level = "fail"
		result.score = 0
		result.message = "未找到标准方剂"
		return result

	result.matched_formula_id = standard_formula.formula_id
	result.matched_formula_name = standard_formula.formula_name

	# -------------------------
	# 2. 构建双方数据
	# -------------------------
	var player_info = player_prescription.build_role_maps()
	var standard_info := _build_standard_formula_info(standard_formula)

	var player_fen_map: Dictionary = player_info["fen_map"]
	var player_name_map: Dictionary = player_info["name_map"]
	var player_role_map: Dictionary = player_info["role_map"]

	var standard_fen_map: Dictionary = standard_info["fen_map"]
	var standard_name_map: Dictionary = standard_info["name_map"]
	var standard_role_map: Dictionary = standard_info["role_map"]

	result.standard_herb_count = standard_fen_map.size()
	result.player_herb_count = player_fen_map.size()

	var total_penalty: int = 0

	# 按标准方角色生成最终四行显示
	var role_display_map := {
		"君": [],
		"臣": [],
		"佐": [],
		"使": []
	}

	# -------------------------
	# 3. 遍历标准方
	# 处理：
	# - 缺少药材
	# - 角色错误（药材存在，但放错区）
	# - 剂量错误
	# -------------------------
	for herb_id in standard_fen_map.keys():
		var herb_name: String = standard_name_map.get(herb_id, herb_id)
		var standard_role_name: String = standard_role_map.get(herb_id, "使")
		var standard_fen: int = int(standard_fen_map[herb_id])

		# 3.1 玩家没有这味药 -> 缺少
		if not player_fen_map.has(herb_id):
			result.missing_herb_ids.append(herb_id)
			result.missing_herb_names.append(herb_name)

			var missing_penalty: int = _get_composition_penalty(standard_role_name)
			total_penalty += missing_penalty

			role_display_map[standard_role_name].append("%s❌️ -%d" % [herb_name, missing_penalty])
			continue

		# 3.2 玩家有这味药，先记为命中药材
		result.matched_herb_count += 1

		var player_role_name: String = player_role_map.get(herb_id, "")
		var player_fen: int = int(player_fen_map[herb_id])

		# 3.3 药材放错区 -> 按标准方视角，记为“该角色缺少”
		# 同时多出的那一侧会在第4步按玩家区再次结算
		if player_role_name != standard_role_name:
			result.missing_herb_ids.append(herb_id)
			result.missing_herb_names.append(herb_name)

			var wrong_role_penalty: int = _get_composition_penalty(standard_role_name)
			total_penalty += wrong_role_penalty

			role_display_map[standard_role_name].append("%s❌️ -%d" % [herb_name, wrong_role_penalty])
			continue

		# 3.4 角色正确，再检查剂量
		var error_type: String = _get_dose_error_type(player_fen, standard_fen)

		if error_type == "none":
			role_display_map[standard_role_name].append(
				"%s✅️ %s✅️" % [herb_name, HerbUnit.format_fen_auto(standard_fen)]
			)
			continue

		var full_penalty: int = _get_dose_penalty(standard_role_name)
		var actual_penalty: int = full_penalty
		if error_type == "minor":
			actual_penalty = int(full_penalty / 2)

		total_penalty += actual_penalty

		var detail_text := "%s药【%s】%s（标准 %s，实际 %s）" % [
			standard_role_name,
			herb_name,
			_get_dose_diff_text(player_fen, standard_fen),
			HerbUnit.format_fen_auto(standard_fen),
			HerbUnit.format_fen_auto(player_fen)
		]

		if error_type == "severe":
			result.major_dosage_errors.append(detail_text)
		else:
			result.minor_dosage_errors.append(detail_text)

		role_display_map[standard_role_name].append(
			"%s✅️ %s❌️ -%d" % [herb_name, HerbUnit.format_fen_auto(standard_fen), actual_penalty]
		)

	# -------------------------
	# 4. 遍历玩家处方
	# 处理：
	# - 多出的药材
	# - 放错区的药材，会在玩家所在区显示为“多出”
	# -------------------------
	for herb_id in player_fen_map.keys():
		var herb_name: String = player_name_map.get(herb_id, herb_id)
		var player_role_name: String = player_role_map.get(herb_id, "使")

		# 4.1 标准方没有这味药 -> 多出
		if not standard_fen_map.has(herb_id):
			result.extra_herb_ids.append(herb_id)
			result.extra_herb_names.append(herb_name)

			var extra_penalty: int = _get_composition_penalty(player_role_name)
			total_penalty += extra_penalty

			role_display_map[player_role_name].append("%s❌️ -%d" % [herb_name, extra_penalty])
			continue

		# 4.2 标准方有这味药，但玩家放错区 -> 在玩家区视角显示为多出
		var standard_role_name: String = standard_role_map.get(herb_id, "")
		if player_role_name != standard_role_name:
			result.extra_herb_ids.append(herb_id)
			result.extra_herb_names.append(herb_name)

			var wrong_place_penalty: int = _get_composition_penalty(player_role_name)
			total_penalty += wrong_place_penalty

			role_display_map[player_role_name].append("%s❌️ -%d" % [herb_name, wrong_place_penalty])

	# -------------------------
	# 5. 最终分数与等级
	# -------------------------
	result.score = 100 - total_penalty

	# 根据最终分数计算评价等级
	# 100分：甲等
	# 80~99分：乙等
	# 60~79分：丙等
	# 60分以下：丁等
	result.grade = _get_score_grade(result.score)

	# level 保留原本的 perfect / pass / fail 结构，方便旧逻辑继续使用
	if result.score == 100:
		result.success = true
		result.level = "perfect"
	elif result.score >= 60:
		result.success = true
		result.level = "pass"
	else:
		result.success = false
		result.level = "fail"

	# -------------------------
	# 6. 主显示文本
	# -------------------------
	result.message = _build_role_display_text(role_display_map)

	return result


# =========================================================
# 二、构建标准方信息
# 返回：
# {
#     "fen_map": herb_id -> total_fen,
#     "name_map": herb_id -> herb_name,
#     "role_map": herb_id -> role_name
# }
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


# =========================================================
# 三、追加单味药信息到映射
# =========================================================
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
# 四、配伍扣分
# =========================================================
func _get_composition_penalty(role_name: String) -> int:
	match role_name:
		"君":
			return 60
		"臣":
			return 40
		"佐":
			return 20
		"使":
			return 10
		_:
			return 10


# =========================================================
# 五、剂量扣分
# 严重错误扣全值，轻微错误扣一半
# =========================================================
func _get_dose_penalty(role_name: String) -> int:
	match role_name:
		"君":
			return 60
		"臣":
			return 40
		"佐":
			return 20
		"使":
			return 10
		_:
			return 10


# =========================================================
# 六、判断剂量错误类型
#
# 返回：
# - "none"   : 完全正确
# - "minor"  : 轻微错误
# - "severe" : 严重错误
# =========================================================
func _get_dose_error_type(player_fen: int, standard_fen: int) -> String:
	if standard_fen <= 0:
		return "none"

	var error_ratio: float = abs(float(player_fen - standard_fen)) / float(standard_fen)

	# 误差 >= 1/2：严重错误，扣对应全值
	# 误差 > 0 且 < 1/2：轻微错误，扣对应一半
	if error_ratio >= 0.5:
		return "severe"
	elif error_ratio > 0.0:
		return "minor"
	else:
		return "none"


# =========================================================
# 七、根据分数返回评价等级
#
# 100分：甲等
# 80~99分：乙等
# 60~79分：丙等
# 60分以下：丁等
# =========================================================
func _get_score_grade(score: int) -> String:
	if score == 100:
		return "甲等"

	if score >= 80:
		return "乙等"

	if score >= 60:
		return "丙等"

	return "丁等"


# =========================================================
# 八、剂量偏差方向文本
# =========================================================
func _get_dose_diff_text(player_fen: int, standard_fen: int) -> String:
	if player_fen > standard_fen:
		return "剂量过多"
	elif player_fen < standard_fen:
		return "剂量过少"
	return "剂量正确"


# =========================================================
# 九、生成四行显示文本
#
# 输出示例：
# 君：麻黄✅️ 3钱✅️
# 臣：桂枝✅️ 3钱❌️ -40
# 佐：杏仁✅️、熟地黄❌️ -20
# 使：甘草✅️
# =========================================================
func _build_role_display_text(role_display_map: Dictionary) -> String:
	var jun_items: Array[String] = _to_string_array(role_display_map.get("君", []))
	var chen_items: Array[String] = _to_string_array(role_display_map.get("臣", []))
	var zuo_items: Array[String] = _to_string_array(role_display_map.get("佐", []))
	var shi_items: Array[String] = _to_string_array(role_display_map.get("使", []))

	var lines: Array[String] = []
	lines.append("君：" + _join_or_placeholder(jun_items))
	lines.append("臣：" + _join_or_placeholder(chen_items))
	lines.append("佐：" + _join_or_placeholder(zuo_items))
	lines.append("使：" + _join_or_placeholder(shi_items))

	return "\n".join(lines)


# =========================================================
# 十、工具：转成 Array[String]
# =========================================================
func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for item in value:
			result.append(str(item))

	return result


# =========================================================
# 十一、工具：空数组时给一个占位符
# =========================================================
func _join_or_placeholder(items: Array[String]) -> String:
	if items.is_empty():
		return "（无）"
	return "、".join(items)


# =========================================================
# 十二、快速测试
# =========================================================
func judge_and_print(player_prescription: Prescription, standard_formula: FormulaData) -> JudgeResult:
	var result := judge_formula(player_prescription, standard_formula)
	result.debug_print()
	print(result.get_summary_text())
	return result
