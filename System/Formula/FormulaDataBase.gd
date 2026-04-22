extends Node
class_name FormulaDataBase

# =========================================================
# FormulaDataBase.gd
# 方剂数据库
#
# 功能：
# - 自动扫描 res://Formula/data/
# - 自动加载所有 FormulaData 类型的 .tres
# - 提供按 id / disease_id 查询接口
# =========================================================

const FORMULA_DATA_DIR := "res://Data/Formula/"

var formulas: Array[FormulaData] = []


func _ready() -> void:
	load_all_formulas()
	print("FormulaDataBase 已加载方剂数量：", formulas.size())


# =========================================================
# 一、加载所有方剂
# =========================================================
func load_all_formulas() -> void:
	formulas.clear()
	_scan_formula_dir(FORMULA_DATA_DIR)


# 递归扫描目录
func _scan_formula_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("FormulaDataBase: 无法打开目录 -> " + dir_path)
		return

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break

		# 跳过隐藏文件
		if file_name.begins_with("."):
			continue

		var full_path := dir_path.path_join(file_name)

		if dir.current_is_dir():
			# 递归扫描子目录
			_scan_formula_dir(full_path)
		else:
			# 只处理 .tres
			if file_name.ends_with(".tres"):
				_try_load_formula(full_path)

	dir.list_dir_end()


# 尝试加载单个方剂资源
func _try_load_formula(path: String) -> void:
	var res := load(path)
	if res == null:
		push_warning("FormulaDataBase: 加载失败 -> " + path)
		return

	if res is FormulaData:
		var formula: FormulaData = res

		# 过滤掉没有 formula_id 的脏数据（可选，但建议保留）
		if formula.formula_id.strip_edges() == "":
			push_warning("FormulaDataBase: formula_id 为空，已跳过 -> " + path)
			return

		formulas.append(formula)
		print("已加载方剂：", formula.formula_name, " | id=", formula.formula_id)
	else:
		# 如果这个 .tres 不是 FormulaData，就跳过
		print("跳过非 FormulaData 资源：", path)


# =========================================================
# 二、查询接口
# =========================================================

func get_all_formulas() -> Array[FormulaData]:
	return formulas


func get_formula_by_id(formula_id: String) -> FormulaData:
	formula_id = formula_id.strip_edges()
	if formula_id == "":
		return null

	for formula in formulas:
		if formula == null:
			continue

		if formula.formula_id == formula_id:
			return formula

	return null


func get_formulas_by_disease(disease_id: String) -> Array[FormulaData]:
	var result: Array[FormulaData] = []

	disease_id = disease_id.strip_edges()
	if disease_id == "":
		return result

	for formula in formulas:
		if formula == null:
			continue

		if formula.target_disease_id == disease_id:
			result.append(formula)

	return result


# =========================================================
# 三、调试接口
# =========================================================

func debug_print_all_formulas() -> void:
	print("===== FormulaDataBase =====")
	print("总方剂数：", formulas.size())

	for formula in formulas:
		if formula == null:
			continue

		print(
			"方名：", formula.formula_name,
			" | formula_id=", formula.formula_id,
			" | target_disease_id=", formula.target_disease_id
		)

	print("===========================")
