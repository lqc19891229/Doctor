extends Resource
class_name FormulaData

# =========================================================
# FormulaData.gd
# 单个方剂的数据资源
#
# 作用：
# 表示一个完整方剂
#
# 例如：
# - 麻黄汤
# - 桂枝汤
# - 银翘散
#
# 当前设计目标：
# 1. 能展示方剂信息
# 2. 能支持按疾病关联
# 3. 能支持后续处方判定
# 4. 能支持医书系统查询
# =========================================================


# =========================================================
# 一、基础信息
# =========================================================

# 方剂唯一ID
# 程序内部匹配建议用这个，不建议只靠中文名
@export var formula_id: String = ""

# 方名（显示给玩家）
@export var formula_name: String = ""

# 出处
# 例如：伤寒论、温病条辨
@export var source_book: String = ""

# 对应疾病ID
# 建议与 DiseaseData.disease_id 对应
@export var target_disease_id: String = ""

# 对应疾病名（仅用于显示，可不填）
@export var target_disease_name: String = ""

# 方剂功效
@export_multiline var effect_text: String = ""

# 主治 / 使用说明
@export_multiline var indication_text: String = ""

# 方义说明 / 简介
@export_multiline var description: String = ""


# =========================================================
# 二、君臣佐使分组
# =========================================================

# 君药组
@export var jun_group: Array[FormulaIngredient] = []

# 臣药组
@export var chen_group: Array[FormulaIngredient] = []

# 佐药组
@export var zuo_group: Array[FormulaIngredient] = []

# 使药组
@export var shi_group: Array[FormulaIngredient] = []


# =========================================================
# 三、基础校验
# =========================================================

func is_valid_data() -> bool:
	if formula_id.strip_edges() == "":
		return false

	if formula_name.strip_edges() == "":
		return false

	if get_all_ingredients().is_empty():
		return false

	return true


func validate_data() -> Array[String]:
	var errors: Array[String] = []

	if formula_id.strip_edges() == "":
		errors.append("formula_id 为空")

	if formula_name.strip_edges() == "":
		errors.append("formula_name 为空")

	if get_all_ingredients().is_empty():
		errors.append("方剂没有任何药材")

	var all_ingredients := get_all_ingredients()
	for i in range(all_ingredients.size()):
		var ingredient := all_ingredients[i]

		if ingredient == null:
			errors.append("第 %d 个药材条目为空" % i)
			continue

		if not ingredient.is_valid_data():
			errors.append("药材条目无效：%s" % ingredient.get_display_text())

	if has_duplicate_herb_id():
		errors.append("存在重复 herb_id 的药材条目")

	return errors


# =========================================================
# 四、获取全部药材
# =========================================================

func get_all_ingredients() -> Array[FormulaIngredient]:
	var result: Array[FormulaIngredient] = []

	result.append_array(jun_group)
	result.append_array(chen_group)
	result.append_array(zuo_group)
	result.append_array(shi_group)

	return result


func get_required_ingredients() -> Array[FormulaIngredient]:
	var result: Array[FormulaIngredient] = []

	for ingredient in get_all_ingredients():
		if ingredient != null and ingredient.required:
			result.append(ingredient)

	return result


# =========================================================
# 五、按角色获取药材
# =========================================================

func get_group_by_role(role_name: String) -> Array[FormulaIngredient]:
	match role_name:
		"君":
			return jun_group
		"臣":
			return chen_group
		"佐":
			return zuo_group
		"使":
			return shi_group
		_:
			var empty_group: Array[FormulaIngredient] = []
			return empty_group


func get_role_of_herb_id(herb_id: String) -> String:
	for ingredient in jun_group:
		if ingredient != null and ingredient.get_herb_id() == herb_id:
			return "君"

	for ingredient in chen_group:
		if ingredient != null and ingredient.get_herb_id() == herb_id:
			return "臣"

	for ingredient in zuo_group:
		if ingredient != null and ingredient.get_herb_id() == herb_id:
			return "佐"

	for ingredient in shi_group:
		if ingredient != null and ingredient.get_herb_id() == herb_id:
			return "使"

	return ""


func get_role_of_herb_name(herb_name: String) -> String:
	for ingredient in jun_group:
		if ingredient != null and ingredient.get_herb_name() == herb_name:
			return "君"

	for ingredient in chen_group:
		if ingredient != null and ingredient.get_herb_name() == herb_name:
			return "臣"

	for ingredient in zuo_group:
		if ingredient != null and ingredient.get_herb_name() == herb_name:
			return "佐"

	for ingredient in shi_group:
		if ingredient != null and ingredient.get_herb_name() == herb_name:
			return "使"

	return ""


# =========================================================
# 六、按 herb_id / herb_name 查询
# =========================================================

func has_herb_id(herb_id: String) -> bool:
	for ingredient in get_all_ingredients():
		if ingredient != null and ingredient.get_herb_id() == herb_id:
			return true
	return false


func has_herb_name(herb_name: String) -> bool:
	for ingredient in get_all_ingredients():
		if ingredient != null and ingredient.get_herb_name() == herb_name:
			return true
	return false


func get_ingredient_by_herb_id(herb_id: String) -> FormulaIngredient:
	for ingredient in get_all_ingredients():
		if ingredient != null and ingredient.get_herb_id() == herb_id:
			return ingredient
	return null


func get_ingredient_by_herb_name(herb_name: String) -> FormulaIngredient:
	for ingredient in get_all_ingredients():
		if ingredient != null and ingredient.get_herb_name() == herb_name:
			return ingredient
	return null


# =========================================================
# 七、获取药材ID / 名称列表
# =========================================================

func get_all_herb_ids() -> Array[String]:
	var result: Array[String] = []

	for ingredient in get_all_ingredients():
		if ingredient != null:
			var herb_id := ingredient.get_herb_id()
			if herb_id != "":
				result.append(herb_id)

	return result


func get_required_herb_ids() -> Array[String]:
	var result: Array[String] = []

	for ingredient in get_required_ingredients():
		var herb_id := ingredient.get_herb_id()
		if herb_id != "":
			result.append(herb_id)

	return result


func get_all_herb_names() -> Array[String]:
	var result: Array[String] = []

	for ingredient in get_all_ingredients():
		if ingredient != null:
			var herb_name := ingredient.get_herb_name()
			if herb_name != "":
				result.append(herb_name)

	return result


func get_required_herb_names() -> Array[String]:
	var result: Array[String] = []

	for ingredient in get_required_ingredients():
		var herb_name := ingredient.get_herb_name()
		if herb_name != "":
			result.append(herb_name)

	return result


# =========================================================
# 八、构建映射表
# =========================================================

func get_ingredient_map_by_id() -> Dictionary:
	var result := {}

	for ingredient in get_all_ingredients():
		if ingredient == null:
			continue

		var herb_id := ingredient.get_herb_id()
		if herb_id == "":
			continue

		result[herb_id] = ingredient

	return result


func get_ingredient_map_by_name() -> Dictionary:
	var result := {}

	for ingredient in get_all_ingredients():
		if ingredient == null:
			continue

		var herb_name := ingredient.get_herb_name()
		if herb_name == "":
			continue

		result[herb_name] = ingredient

	return result


func get_required_ingredient_map_by_id() -> Dictionary:
	var result := {}

	for ingredient in get_required_ingredients():
		if ingredient == null:
			continue

		var herb_id := ingredient.get_herb_id()
		if herb_id == "":
			continue

		result[herb_id] = ingredient

	return result


# =========================================================
# 九、读取标准剂量
# =========================================================

func get_standard_amount_by_id(herb_id: String) -> float:
	var ingredient := get_ingredient_by_herb_id(herb_id)
	if ingredient == null:
		return -1.0
	return ingredient.amount


func get_standard_unit_by_id(herb_id: String) -> String:
	var ingredient := get_ingredient_by_herb_id(herb_id)
	if ingredient == null:
		return ""
	return ingredient.unit


# =========================================================
# 十、重复检查
# =========================================================

func has_duplicate_herb_id() -> bool:
	var seen := {}

	for ingredient in get_all_ingredients():
		if ingredient == null:
			continue

		var herb_id := ingredient.get_herb_id()
		if herb_id == "":
			continue

		if seen.has(herb_id):
			return true

		seen[herb_id] = true

	return false


# =========================================================
# 十一、显示文本
# =========================================================

func get_display_text() -> String:
	var lines: Array[String] = []

	lines.append("方名：" + formula_name)

	if source_book.strip_edges() != "":
		lines.append("出处：" + source_book)

	if target_disease_name.strip_edges() != "":
		lines.append("对应疾病：" + target_disease_name)
	elif target_disease_id.strip_edges() != "":
		lines.append("对应疾病ID：" + target_disease_id)

	if effect_text.strip_edges() != "":
		lines.append("功效：" + effect_text)

	if indication_text.strip_edges() != "":
		lines.append("主治：" + indication_text)

	if not jun_group.is_empty():
		lines.append("君药：" + _join_group_text(jun_group))

	if not chen_group.is_empty():
		lines.append("臣药：" + _join_group_text(chen_group))

	if not zuo_group.is_empty():
		lines.append("佐药：" + _join_group_text(zuo_group))

	if not shi_group.is_empty():
		lines.append("使药：" + _join_group_text(shi_group))

	return "\n".join(lines)


func _join_group_text(group: Array[FormulaIngredient]) -> String:
	var parts: Array[String] = []

	for ingredient in group:
		if ingredient != null:
			parts.append(ingredient.get_display_text())

	return "、".join(parts)


# =========================================================
# 十二、调试输出
# =========================================================

func to_dict() -> Dictionary:
	var all_ingredients_data: Array[Dictionary] = []

	for ingredient in get_all_ingredients():
		if ingredient != null:
			all_ingredients_data.append(ingredient.to_dict())

	return {
		"formula_id": formula_id,
		"formula_name": formula_name,
		"source_book": source_book,
		"target_disease_id": target_disease_id,
		"target_disease_name": target_disease_name,
		"effect_text": effect_text,
		"indication_text": indication_text,
		"description": description,
		"ingredients": all_ingredients_data
	}
