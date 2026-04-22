extends Resource
class_name BookEntryData

# =========================================================
# BookEntryData.gd
# 医书条目公共基类
#
# 只保留最基础、所有条目一定共有的字段
# 这样 Inspector 不会把无关字段全显示出来
# =========================================================

# 条目唯一ID
@export var entry_id: String = ""

# 所属书籍ID
@export var book_id: String = ""

# 条目标题
@export var title: String = ""

# 正文
@export_multiline var detail_text: String = ""


# 返回条目类型
func get_entry_type() -> String:
	return ""


# 基础校验
func is_valid_data() -> bool:
	if entry_id.strip_edges() == "":
		return false

	if book_id.strip_edges() == "":
		return false

	if title.strip_edges() == "":
		return false

	if get_entry_type().strip_edges() == "":
		return false

	return true
