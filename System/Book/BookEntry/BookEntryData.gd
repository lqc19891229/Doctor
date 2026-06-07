extends Resource
class_name BookEntryData

# =========================================================
# BookEntryData.gd
# 医书条目公共基类
# =========================================================

# 条目唯一ID
@export var entry_id: String = ""

# 所属书籍ID
@export var book_id: String = ""

# 条目标题
@export var title: String = ""

# 正文
@export_multiline var detail_text: String = ""

# =========================================================
# 新增：自动解锁所需累计心得点数
# -1：不参与心得自动解锁
#  0：游戏开始即可自动解锁
#  1：累计获得 1 点心得后自动解锁
#  2：累计获得 2 点心得后自动解锁
@export var unlock_required_experience_points: int = -1

# =========================================================
# 返回条目类型
func get_entry_type() -> String:
	return ""

# =========================================================
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
