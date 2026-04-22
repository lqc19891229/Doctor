extends Resource
class_name HerbData

# ========================
# 基础标识
# ========================

@export var herb_id: String = ""     # 唯一ID（程序用）
@export var herb_name: String = ""   # 药材名称（UI显示）

# ========================
# 药性核心（用于判定/匹配）
# ========================

@export var nature: String = ""      # 性：寒 / 热 / 温 / 凉 / 平
@export var taste: Array[String] = [] # 味：辛 / 甘 / 苦 / 酸 / 咸

# ========================
# 归经（关键匹配字段）
# ========================

@export var meridians: Array[String] = []  # 归经：如 ["肺", "脾"]


# ========================
# 数据校验
# ========================

func is_valid_data() -> bool:
	# herb_id 不能为空
	if herb_id.strip_edges() == "":
		return false

	# herb_name 不能为空
	if herb_name.strip_edges() == "":
		return false

	return true
