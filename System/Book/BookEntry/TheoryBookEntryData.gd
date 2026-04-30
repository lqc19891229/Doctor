extends BookEntryData
class_name TheoryBookEntryData

# =========================================================
# TheoryBookEntryData.gd
# 理论书条目
#
# 用途：
# 1. 用于《黄帝内经》
# 2. 解释阴阳、五行、脏腑、气血、寒热、湿燥、脉象规则
# 3. 阅读后只标记为已读，不解锁疾病实体
# =========================================================

# 前置条目
# 例如：先读“阴阳”，再读“五行”
@export var prerequisite_entry_ids: Array[String] = []


func get_entry_type() -> String:
	return "theory"


func is_valid_data() -> bool:
	if not super.is_valid_data():
		return false

	return true
