extends Resource
class_name DiseaseBookEntryData

# =========================================================
# DiseaseBookEntryData.gd
# 病证书条目数据（精简版）
#
# 设计目标：
# 1. 书籍系统不重复保存 DiseaseData 里的核心疾病信息
# 2. 条目只保存“书籍阅读相关”的内容
# 3. 病名、脉象、推荐方等核心内容，运行时从 DiseaseDB 读取
# 4. 本脚本兼容 DiseaseData 中使用 recommended_formula_id 的写法
# =========================================================


# =========================================================
# 一、基础信息
# =========================================================

# 条目唯一ID
# 建议格式：
# shanghanlun_fenghan_biaoshi
@export var entry_id: String = ""

# 所属书籍ID
# 例如：
# shanghanlun
# wenbingtiaobian
# jinguiyaolue
# taipinghuiminhejijufang
# qianjinfang
@export var book_id: String = ""

# 对应的疾病ID
# 必须和 DiseaseData.disease_id 对应
@export var disease_id: String = ""


# =========================================================
# 二、阅读条件
# =========================================================

# 阅读该病证条目所需的药材ID
# 一般填写该病证推荐方中涉及的药材
# 当这些药材都已解锁后，该条目进入“可阅读”状态
@export var required_herb_ids: Array[String] = []

# 前置条目ID
# 用于控制某本书中的阅读顺序
# 例如：后续条目要求先读前一个条目
@export var prerequisite_entry_ids: Array[String] = []


# =========================================================
# 三、书籍专属文本
# =========================================================

# 条目摘要
# 用于病证列表简述、行医记考摘要等
@export_multiline var summary_text: String = ""

# 条目正文
# 用于夜晚读书界面的正文展示
@export_multiline var detail_text: String = ""

# 开发备注
@export_multiline var note: String = ""


# =========================================================
# 四、基础校验
# =========================================================

# 判断当前条目数据是否基本有效
func is_valid_data() -> bool:
	if entry_id.strip_edges() == "":
		return false

	if book_id.strip_edges() == "":
		return false

	if disease_id.strip_edges() == "":
		return false

	return true


# 返回错误列表，方便批量检查资源配置
func validate_data() -> Array[String]:
	var errors: Array[String] = []

	if entry_id.strip_edges() == "":
		errors.append("entry_id 为空")

	if book_id.strip_edges() == "":
		errors.append("book_id 为空")

	if disease_id.strip_edges() == "":
		errors.append("disease_id 为空")

	for i in range(required_herb_ids.size()):
		if required_herb_ids[i].strip_edges() == "":
			errors.append("required_herb_ids 第 %d 项为空字符串" % i)

	for i in range(prerequisite_entry_ids.size()):
		if prerequisite_entry_ids[i].strip_edges() == "":
			errors.append("prerequisite_entry_ids 第 %d 项为空字符串" % i)

	return errors


# =========================================================
# 五、获取数据库
# =========================================================

# 获取 DiseaseDB 全局单例
# 你的自动加载名字是 DiseaseDB，因此这里直接从 /root 取
func _get_disease_db() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("DiseaseDB")


# =========================================================
# 六、读取 DiseaseData
# =========================================================

# 获取当前条目对应的 DiseaseData
# 前提：DiseaseDB 中存在 get_disease_by_id(disease_id) 方法
func get_disease_data():
	var db := _get_disease_db()
	if db == null:
		return null

	if not db.has_method("get_disease_by_id"):
		return null

	return db.get_disease_by_id(disease_id)


# =========================================================
# 七、对外辅助接口
# =========================================================

# 获取显示名称
# 优先从 DiseaseData 中读取 disease_name
# 如果读取失败，则退回 disease_id
func get_display_name() -> String:
	var disease_data = get_disease_data()
	if disease_data == null:
		return disease_id

	var value := String(disease_data.disease_name).strip_edges()
	if value != "":
		return value

	return disease_id


# 获取推荐方ID
# 注意：这里兼容你当前 DiseaseData 使用的字段名：
# recommended_formula_id
func get_standard_formula_id() -> String:
	var disease_data = get_disease_data()
	if disease_data == null:
		return ""

	return String(disease_data.recommended_formula_id).strip_edges()


# 是否存在推荐方
func has_standard_formula() -> bool:
	return get_standard_formula_id() != ""


# 获取脉象文本
# 你当前的 DiseaseData.gd 里没有 pulse_text 字段
# 所以这里统一返回空字符串，避免运行时报错
# 后续如果你真的加了 pulse_text 字段，再恢复读取逻辑即可
func get_pulse_text() -> String:
	return ""


# 获取去重后的 required_herb_ids
func get_required_herb_ids_unique() -> Array[String]:
	var result: Array[String] = []
	var cache: Dictionary = {}

	for herb_id in required_herb_ids:
		var clean_id := herb_id.strip_edges()
		if clean_id == "":
			continue

		if cache.has(clean_id):
			continue

		cache[clean_id] = true
		result.append(clean_id)

	return result


# 获取去重后的 prerequisite_entry_ids
func get_prerequisite_entry_ids_unique() -> Array[String]:
	var result: Array[String] = []
	var cache: Dictionary = {}

	for pre_id in prerequisite_entry_ids:
		var clean_id := pre_id.strip_edges()
		if clean_id == "":
			continue

		if cache.has(clean_id):
			continue

		cache[clean_id] = true
		result.append(clean_id)

	return result
