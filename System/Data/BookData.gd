extends Resource
class_name BookData

# =========================================================
# BookData.gd
# 书本定义资源
#
# 作用：
# 1. 定义一本书的基础信息
# 2. 给UI书单使用
# 3. 给系统分类使用
#
# 注意：
# - 不再在这里直接配置 unlock_herb_ids / unlock_disease_ids
# - 药材书按顺序解锁药材
# - 病证书通过 DiseaseBookEntryData 管理条目
# =========================================================


# =========================================================
# 一、书本类型
# =========================================================

# herb      = 药材书
# disease   = 病证书
# encyclopedia = 百科书
@export_enum("herb", "disease", "encyclopedia")
var book_type: String = "disease"


# =========================================================
# 二、基础信息
# =========================================================

# 书籍唯一ID
# 例如：
# shennongbencaojing
# shanghanlun
# wenbingtiaobian
# xingyijikao
@export var book_id: String = ""

# 书名
@export var book_name: String = ""

# 简介
@export_multiline var description: String = ""

# 作者 / 来源（可选）
@export var author_name: String = ""

# 排序用
# UI里按这个顺序显示
@export var sort_index: int = 0


# =========================================================
# 三、药材书专用
# =========================================================

# 如果是药材书，可填写药材条目顺序表
# 每次夜晚阅读时，从前往后逐步解锁
@export var herb_unlock_order: Array[String] = []


# =========================================================
# 四、显示控制
# =========================================================

# 初始是否可见
# 用于控制玩家一开始是否能在书架看到这本书
@export var visible_by_default: bool = true

# 是否只能阅读一次（一般整本书本身不用这个限制）
@export var read_once: bool = false


# =========================================================
# 五、基础校验
# =========================================================

func is_valid_data() -> bool:
	if book_id.strip_edges() == "":
		return false

	if book_name.strip_edges() == "":
		return false

	if book_type.strip_edges() == "":
		return false

	return true


func validate_data() -> Array[String]:
	var errors: Array[String] = []

	if book_id.strip_edges() == "":
		errors.append("book_id 为空")

	if book_name.strip_edges() == "":
		errors.append("book_name 为空")

	if book_type.strip_edges() == "":
		errors.append("book_type 为空")

	for i in range(herb_unlock_order.size()):
		if herb_unlock_order[i].strip_edges() == "":
			errors.append("herb_unlock_order 第 %d 项为空字符串" % i)

	return errors
