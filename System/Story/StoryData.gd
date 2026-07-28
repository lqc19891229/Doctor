extends Resource
class_name StoryData

# 剧情唯一 ID，用来记录是否已经播放过
@export var story_id: String = ""

# 剧情触发场景，例如 clinic / night / map
@export_enum("clinic", "night", "map")
var trigger_scene: String = "clinic"

# 触发条件：第几天触发，0 表示不限制天数
@export var trigger_day: int = 0

# 触发条件：需要达到的最低名望，0 表示不限制名望
@export var required_reputation_points: int = 0

# 剧情解锁时，是否顺便解锁某个医书条目，不需要解锁医书条目就留空。
@export var unlock_entry_id: String = ""

# 是否只播放一次
@export var play_once: bool = true

# 剧情结束后返回目标
@export_enum("clinic", "night", "map")
var return_scene: String = "clinic"

# 剧情结束后如果回到 clinic，并且需要指定当前接诊病人，填写 story NPC 的 npc_id。
# 对应 NPC 资源需要放在 res://Data/Npc 下，且 NpcData.npc_type = "story"。
@export var clinic_npc_id: String = ""

# 台词列表
@export var lines: Array[StoryLine] = []
