extends Resource
class_name FormulaIngredient

# =========================================================
# FormulaIngredient.gd
# 标准方中的单味药条目
#
# 作用：
# - 记录某一味药
# - 记录数量 amount
# - 记录单位 unit（fen/qian/liang/jin）
# - 提供转换成“总分”的接口
# =========================================================

@export var herb: HerbData

# 录入数量
# 例如：
# amount = 3, unit = "qian"  -> 3钱
# amount = 1.5, unit = "liang" -> 1.5两
@export_range(0.0, 999.0, 0.1)
var amount: float = 0.0

# 内部统一用单位代码，不直接存中文
@export_enum("fen", "qian", "liang", "jin")
var unit: String = "qian"

@export var required: bool = true

# =========================================================
# 一、数据合法性
# =========================================================
func is_valid_data() -> bool:
	if herb == null:
		return false

	if herb.herb_id.strip_edges() == "":
		return false

	if amount <= 0.0:
		return false

	if not HerbUnit.is_valid_unit(unit):
		return false

	return true


# =========================================================
# 二、返回 herb_id
# =========================================================
func get_herb_id() -> String:
	if herb == null:
		return ""
	return herb.herb_id.strip_edges()


# =========================================================
# 三、返回 herb_name
# =========================================================
func get_herb_name() -> String:
	if herb == null:
		return ""
	return herb.herb_name.strip_edges()


# =========================================================
# 四、换算成总分
# =========================================================
func get_amount_in_fen() -> int:
	return HerbUnit.to_fen(amount, unit)


# =========================================================
# 五、显示文本
# =========================================================
func get_amount_text() -> String:
	return HerbUnit.format_amount(amount, unit)


func get_display_text() -> String:
	if herb == null:
		return "空药材"

	var herb_name := get_herb_name()
	if herb_name == "":
		herb_name = get_herb_id()

	return "%s %s" % [herb_name, get_amount_text()]
