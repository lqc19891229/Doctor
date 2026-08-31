extends Resource
class_name StoryData

const TRIGGER_TYPE_SCENE_ENTER := "scene_enter"
const TRIGGER_TYPE_NIGHT_END := "night_end"
const TRIGGER_TYPE_STORY_NPC_CURED := "story_npc_cured"
const TRIGGER_TYPE_STORY_NPC_FAILED_RETRY := "story_npc_failed_retry"
const TRIGGER_TYPE_STORY_NPC_FAILED_BACK := "story_npc_failed_back"
const TRIGGER_TYPE_STORY_NPC_FAILED_OVER := "story_npc_failed_over"

const BACKGROUND_MODE_DEFAULT := "default"
const BACKGROUND_MODE_CURRENT_SCENE := "current_scene"

# 剧情唯一 ID，用来记录是否已经播放过
@export var story_id: String = ""

# 关联剧情 ID。
# - scene_enter：作为普通前置剧情；必须先完整播放该剧情，当前剧情才允许触发。
# - story_npc_cured / story_npc_failed_*：绑定发起本次治疗的主剧情。
# 治疗结果剧情必须填写该字段。
@export var trigger_story_id: String = ""

# 剧情触发类型：
# - scene_enter：进入指定场景时检查，兼容现有按场景 / 天数 / 名望触发的剧情。
# - night_end：Night 场景点击“休息，进入明天”时检查；剧情完整结束后再推进到下一天。
# - story_npc_cured：指定的 story NPC 被治愈后检查。
# - story_npc_failed_retry：指定的 story NPC 治疗失败，剧情结束后重新回到该 NPC 的诊疗界面。
# - story_npc_failed_back：指定的 story NPC 治疗失败，剧情结束后返回 return_scene。
# - story_npc_failed_over：指定的 story NPC 治疗失败，剧情结束后 Game Over。
@export_enum("scene_enter", "night_end", "story_npc_cured", "story_npc_failed_retry", "story_npc_failed_back", "story_npc_failed_over")
var trigger_type: String = TRIGGER_TYPE_SCENE_ENTER

# 剧情触发场景，例如 clinic / night / map
@export_enum("clinic", "night", "map")
var trigger_scene: String = "clinic"

# 剧情触发天数：
# - trigger_story_id 为空：表示游戏第几天开始允许触发。
# - scene_enter / night_end 且 trigger_story_id 非空：表示前置剧情完整播放结束后第几天允许触发。
# - 治疗结果剧情：必须填写 0，治疗结束后立即按 trigger_story_id 匹配。
#   TriggerScene 必须与发起诊疗的主剧情一致；night_end 主剧情对应 night。
# - 0 表示不增加额外天数。
@export var trigger_day: int = 0

# 触发条件：需要达到的最低名望，0 表示不限制名望
@export var required_reputation_points: int = 0

# 剧情解锁时，是否顺便解锁某个医书条目，不需要解锁医书条目就留空。
@export var unlock_entry_id: String = ""

# 是否只播放一次
@export var play_once: bool = true

# 每段新剧情开始时使用的背景模式：
# - default：显示 Story 场景中配置的 default_background。
# - current_scene：隐藏 Story 自己的背景，显示下层当前保留的 Clinic / Night / Map 场景。
# StoryLine.background 仍可在任意一句中指定图片，并从该句开始覆盖当前场景。
@export_enum("default", "current_scene")
var background_mode: String = BACKGROUND_MODE_DEFAULT

# 剧情结束后返回目标
@export_enum("clinic", "night", "map")
var return_scene: String = "clinic"

# 本段剧情完整播放结束后结算的名望变化。
# 正数表示奖励，负数表示惩罚，0 表示不变化。
@export var reputation_points_change: int = 0

# 本段剧情完整播放结束后结算的心得变化。
# 正数表示奖励，负数表示惩罚，0 表示不变化。
@export var experience_points_change: int = 0

# 本段剧情台词播放完后，如果需要直接在 Story 场景中诊疗 story NPC，
# 填写该 NPC 的 npc_id。表现层留在 Story，诊疗数据仍由 NpcManager → Clinic 处理。
# 对应 NPC 资源需要放在 res://Data/Npc 下，且 NpcData.npc_type = "story"。
@export var clinic_npc_id: String = ""

# 本段剧情发起诊疗时使用的疾病。
# 疾病属于“本次剧情诊疗”，不再固定绑定在 StoryNPC 的 NpcData 资源上。
# 同一个 StoryNPC 因此可以在不同的发起诊疗剧情中配置不同疾病。
@export var clinic_disease: DiseaseData

# Story NPC 诊疗界面使用的立绘。
# 该字段与普通剧情台词的 portrait 相互独立，方便在诊疗选项界面手动指定人物立绘。
# 留空时不主动修改当前画面的立绘状态。
@export var clinic_npc_portrait: Texture2D

# Story NPC 诊疗界面的立绘位置。
@export_enum("left", "mid", "right")
var clinic_npc_portrait_side: String = "mid"

# 台词列表
@export var lines: Array[StoryLine] = []
