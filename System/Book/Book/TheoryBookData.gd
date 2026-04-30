extends BookData
class_name TheoryBookData

# =========================================================
# TheoryBookData.gd
# 理论书数据
#
# 用途：
# 1. 存放《黄帝内经》这种基础理论书
# 2. 不直接解锁疾病、方剂、药材
# 3. 只负责让玩家理解游戏底层规则
# =========================================================

# 理论书可阅读条目
@export var unlock_entry_ids: Array[String] = []


func validate_data() -> Array[String]:
	var errors := super.validate_data()

	# 理论书必须使用 theory 类型
	if book_type != "theory":
		errors.append("TheoryBookData 的 book_type 必须为 theory")

	# 检查条目 ID 是否为空
	for i in range(unlock_entry_ids.size()):
		if unlock_entry_ids[i].strip_edges() == "":
			errors.append("unlock_entry_ids 第 %d 项为空字符串" % i)

	return errors


func get_unlock_entry_ids() -> Array[String]:
	return unlock_entry_ids.duplicate()
