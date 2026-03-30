extends Resource
class_name HerbData

# =========================================================
# HerbData
# 用来描述一味药材的基础数据。
#
# 这版字段与 import_herbs_to_tres.py 完全对应：
# - herb_id
# - herb_name
# - nature
# - taste
# - toxic
# - meridians
# - effect_text
# - indication_text
# - price
# - rarity
# - stack_limit
# - can_prescribe
# =========================================================


# 药材唯一ID
# 例如：
#   ma_huang
#   gui_zhi
@export var herb_id: String = ""


# 药材显示名
# 例如：
#   麻黄
#   桂枝
@export var herb_name: String = ""


# 药性
# 这里先用字符串保存，支持多选值用英文逗号分隔。
# 例如：
#   "温"
#   "寒,凉"
#   "温,热"
#
# 后续如果你想升级成 Array[String] 也可以，
# 但当前版本先保持和导入脚本一致，最稳。
@export var nature: String = ""


# 药味
# 同样先用字符串保存，多选用英文逗号分隔。
# 例如：
#   "辛"
#   "甘,酸"
#   "辛,苦"
@export var taste: String = ""


# 毒性描述
# 当前先留字符串，后面你可以写：
#   "无毒"
#   "小毒"
#   "有毒"
@export var toxic: String = ""


# 归经
# 当前也先用字符串保存，多值用英文逗号分隔。
# 例如：
#   "肺"
#   "肺,表"
#   "心,肺,表"
@export var meridians: String = ""


# 功效描述
# 例如：
#   "发汗解表，宣肺平喘"
@export_multiline var effect_text: String = ""


# 主治描述
# 例如：
#   "外感风寒，恶寒发热，无汗，咳喘"
@export_multiline var indication_text: String = ""


# 价格
# 用于商店、抓药成本等系统
@export var price: int = 0


# 稀有度
# 你可以自行约定：
# 1 = 常见
# 2 = 少见
# 3 = 稀有
# ...
@export var rarity: int = 1


# 单格堆叠上限
# 背包系统、药柜系统可能会用到
@export var stack_limit: int = 99


# 是否允许开方使用
# 某些剧情药、任务药可以设成 false
@export var can_prescribe: bool = true


# =========================================================
# 工具函数
# 下面这些不是必须，但非常实用。
# 以后你在判定、检索、筛选里会方便很多。
# =========================================================

func _split_csv_text(text: String) -> Array[String]:
	"""
	把类似：
		"温,热"
		"肺,表"
	这种英文逗号分隔字符串，转成数组。

	规则：
	1. 按英文逗号拆分
	2. 自动去掉前后空格
	3. 去掉空字符串
	4. 去重
	"""
	var result: Array[String] = []

	if text.is_empty():
		return result

	var parts := text.split(",", false)

	for part in parts:
		var item := part.strip_edges()
		if item.is_empty():
			continue
		if not result.has(item):
			result.append(item)

	return result


func get_nature_list() -> Array[String]:
	"""
	返回药性数组。
	例如：
		"温,热" -> ["温", "热"]
	"""
	return _split_csv_text(nature)


func get_taste_list() -> Array[String]:
	"""
	返回药味数组。
	例如：
		"辛,苦" -> ["辛", "苦"]
	"""
	return _split_csv_text(taste)


func get_meridian_list() -> Array[String]:
	"""
	返回归经数组。
	例如：
		"心,肺,表" -> ["心", "肺", "表"]
	"""
	return _split_csv_text(meridians)


func has_nature(target: String) -> bool:
	"""
	判断这味药是否具有某个药性。
	例如：
		has_nature("温")
	"""
	return get_nature_list().has(target)


func has_taste(target: String) -> bool:
	"""
	判断这味药是否具有某个药味。
	例如：
		has_taste("辛")
	"""
	return get_taste_list().has(target)


func has_meridian(target: String) -> bool:
	"""
	判断这味药是否归某经。
	例如：
		has_meridian("肺")
	"""
	return get_meridian_list().has(target)


func get_display_name() -> String:
	"""
	获取显示名称。
	当前直接返回 herb_name。
	后面如果你想做“炮制品后缀”“品质前缀”，
	可以统一在这里扩展。
	"""
	return herb_name


func get_summary_text() -> String:
	"""
	生成一段简短摘要，方便UI直接显示。
	"""
	var lines: Array[String] = []

	lines.append("药名：" + herb_name)

	if not nature.is_empty():
		lines.append("性：" + nature)

	if not taste.is_empty():
		lines.append("味：" + taste)

	if not meridians.is_empty():
		lines.append("归经：" + meridians)

	if not effect_text.is_empty():
		lines.append("功效：" + effect_text)

	if not indication_text.is_empty():
		lines.append("主治：" + indication_text)

	return "\n".join(lines)
	
# =========================================================
# 基础合法性校验
# 供 HerbDataBase / 导入后检查使用
# =========================================================
func is_valid_data() -> bool:
	# herb_id 不能为空
	if herb_id.strip_edges() == "":
		return false

	# herb_name 不能为空
	if herb_name.strip_edges() == "":
		return false

	# 不允许开方的药，也仍然算“有效数据”
	# 所以这里不检查 can_prescribe
	return true
