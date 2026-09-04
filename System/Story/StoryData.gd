extends Resource
class_name StoryData

# =========================================================
# StoryData
#
# 剧情数据拆成三部分：
# 1. 触发条件 Conditions：所有已填写条件使用 AND 判断。
# 2. 播放后动作 Actions：剧情完整播放后执行。
# 3. 基础设置 Settings：PlayOnce / SortIndex。
#
# TriggerType 已不再参与新剧情的运行逻辑。
# 文件末尾保留旧字段，仅用于尚未重新导出的旧 .tres 兼容。
# =========================================================

const COMPARE_GTE := "gte"
const COMPARE_LTE := "lte"

const TREATMENT_RESULT_CURED := "cured"
const TREATMENT_RESULT_FAILED := "failed"

const BACKGROUND_MODE_DEFAULT := "default"
const BACKGROUND_MODE_CURRENT_SCENE := "current_scene"

# 旧 TriggerType 常量只用于兼容旧 .tres，不参与新结构判断。
const TRIGGER_TYPE_SCENE_ENTER := "scene_enter"
const TRIGGER_TYPE_NIGHT_END := "night_end"
const TRIGGER_TYPE_DAY_REPUTATION_OVER := "day_reputation_over"
const TRIGGER_TYPE_DAY_REPUTATION_BELOW_OVER := "day_reputation_below_over"
const TRIGGER_TYPE_STORY_NPC_CURED := "story_npc_cured"
const TRIGGER_TYPE_STORY_NPC_FAILED_RETRY := "story_npc_failed_retry"
const TRIGGER_TYPE_STORY_NPC_FAILED_BACK := "story_npc_failed_back"
const TRIGGER_TYPE_STORY_NPC_FAILED_OVER := "story_npc_failed_over"


# =========================================================
# 标识
# =========================================================
@export_category("Identity")

# 剧情唯一 ID。
@export var story_id: String = ""

# 策划表中的剧情名称，仅用于识别和调试。
@export var story_name: String = ""


# =========================================================
# 一、触发条件
# 所有非空条件必须同时满足。
# =========================================================
@export_category("Conditions")

# 当前所在场景。留空表示不限制场景。
@export_enum("", "clinic", "night", "map")
var condition_scene: String = ""

# 天数条件：
# - 没有 ConditionStoryID：按游戏绝对天数判断，current_day >= condition_day。
# - 有 ConditionStoryID 且不是治疗结果剧情：按前置剧情完成后的相对天数判断。
# - 治疗结果剧情：按当前游戏绝对天数判断。
# <= 0 表示不限制天数。
@export var condition_day: int = 0

# 金钱条件。Op 留空表示不限制；金额单位统一为“文”。
@export_enum("", "gte", "lte")
var condition_money_op: String = ""
@export var condition_money: int = 0

# 名望条件。Op 留空表示不限制。
@export_enum("", "gte", "lte")
var condition_reputation_op: String = ""
@export var condition_reputation: int = 0

# 必须已经解锁的医书 / 图鉴条目 ID。留空表示不限制。
@export var condition_entry_id: String = ""

# 普通剧情：必须已经完整播放过的前置剧情 ID。
# 治疗结果剧情：表示本次治疗由哪个主剧情发起。
@export var condition_story_id: String = ""

# 本次临时治疗结果条件。只在治疗结束的那次检查中有效，不保存长期状态。
@export_enum("", "cured", "failed")
var condition_treatment_result: String = ""


# =========================================================
# 二、剧情播放后的动作
# =========================================================
@export_category("Actions")

# 剧情结束后返回目标。留空时由当前流程兜底。
@export_enum("", "clinic", "night", "map")
var return_scene: String = ""

# true：剧情完整播放后结束本局并返回主菜单。
@export var end_game: bool = false

# 剧情播放完后生成并进入需要治疗的 story NPC。
# NpcID / Disease / ClinicNpcPortraitPath 都属于同一个“生成治疗 NPC”动作。
@export var clinic_npc_id: String = ""
@export var clinic_disease: DiseaseData
@export var clinic_npc_portrait: Texture2D

# Story NPC 诊疗界面的立绘位置。Excel 暂不配置，默认中间。
@export_enum("left", "mid", "right")
var clinic_npc_portrait_side: String = "mid"

# 数值动作：正数增加，负数扣除，0 不变化。
# money_change 的单位为“文”。
@export var money_change: int = 0
@export var reputation_points_change: int = 0
@export var experience_points_change: int = 0


# =========================================================
# 三、基础设置
# =========================================================
@export_category("Settings")

# true：完整播放过一次后不再自动触发。
@export var play_once: bool = true

# 同一检查时刻有多条剧情同时满足条件时，数值越小优先级越高。
@export var sort_index: int = 0


# =========================================================
# 演出数据
# =========================================================
@export_category("Presentation")

@export_enum("default", "current_scene")
var background_mode: String = BACKGROUND_MODE_DEFAULT

@export var lines: Array[StoryLine] = []


# =========================================================
# 旧资源兼容字段
#
# 新 import_data.py 不再写入这些字段。
# @export_storage 允许旧 .tres 继续被 Godot 读取，但不会显示在 Inspector。
# StoryManager 只会在检测到旧 trigger_type 时读取这些字段进行兼容。
# =========================================================
@export_storage var trigger_story_id: String = ""
@export_storage var trigger_type: String = ""
@export_storage var trigger_scene: String = ""
@export_storage var trigger_day: int = 0
@export_storage var trigger_money: int = 0
@export_storage var required_reputation_points: int = 0
@export_storage var unlock_entry_id: String = ""


func uses_legacy_trigger_schema() -> bool:
	return trigger_type.strip_edges() != ""


func get_condition_scene() -> String:
	var value := condition_scene.strip_edges().to_lower()
	if value == "" and uses_legacy_trigger_schema():
		value = trigger_scene.strip_edges().to_lower()
	return value


func get_condition_day() -> int:
	if condition_day != 0:
		return condition_day
	if uses_legacy_trigger_schema():
		return trigger_day
	return 0


func get_condition_money_op() -> String:
	var value := condition_money_op.strip_edges().to_lower()
	if value != "":
		return value
	if uses_legacy_trigger_schema() and trigger_money != 0:
		return COMPARE_GTE
	return ""


func get_condition_money() -> int:
	if condition_money_op.strip_edges() != "":
		return condition_money
	if uses_legacy_trigger_schema() and trigger_money != 0:
		return trigger_money
	return condition_money


func get_condition_reputation_op() -> String:
	var value := condition_reputation_op.strip_edges().to_lower()
	if value != "":
		return value

	if uses_legacy_trigger_schema() and required_reputation_points > 0:
		if trigger_type.strip_edges().to_lower() == TRIGGER_TYPE_DAY_REPUTATION_BELOW_OVER:
			return COMPARE_LTE
		return COMPARE_GTE

	return ""


func get_condition_reputation() -> int:
	if condition_reputation_op.strip_edges() != "":
		return condition_reputation

	if uses_legacy_trigger_schema() and required_reputation_points > 0:
		# 旧 below 的语义是“当前名望严格小于门槛”。
		# 新结构只有 <=，因此减 1 保持整数名望下的原行为。
		if trigger_type.strip_edges().to_lower() == TRIGGER_TYPE_DAY_REPUTATION_BELOW_OVER:
			return required_reputation_points - 1
		return required_reputation_points

	return condition_reputation


func get_condition_entry_id() -> String:
	var value := condition_entry_id.strip_edges()
	if value == "" and uses_legacy_trigger_schema():
		value = unlock_entry_id.strip_edges()
	return value


func get_condition_story_id() -> String:
	var value := condition_story_id.strip_edges()
	if value == "" and uses_legacy_trigger_schema():
		value = trigger_story_id.strip_edges()
	return value


func get_condition_treatment_result() -> String:
	var value := condition_treatment_result.strip_edges().to_lower()
	if value != "":
		return value

	if not uses_legacy_trigger_schema():
		return ""

	match trigger_type.strip_edges().to_lower():
		TRIGGER_TYPE_STORY_NPC_CURED:
			return TREATMENT_RESULT_CURED
		TRIGGER_TYPE_STORY_NPC_FAILED_RETRY, TRIGGER_TYPE_STORY_NPC_FAILED_BACK, TRIGGER_TYPE_STORY_NPC_FAILED_OVER:
			return TREATMENT_RESULT_FAILED
		_:
			return ""


func should_end_game() -> bool:
	if end_game:
		return true

	if not uses_legacy_trigger_schema():
		return false

	return trigger_type.strip_edges().to_lower() in [
		TRIGGER_TYPE_DAY_REPUTATION_OVER,
		TRIGGER_TYPE_DAY_REPUTATION_BELOW_OVER,
		TRIGGER_TYPE_STORY_NPC_FAILED_OVER,
	]


func is_legacy_failed_retry() -> bool:
	return (
		uses_legacy_trigger_schema()
		and trigger_type.strip_edges().to_lower() == TRIGGER_TYPE_STORY_NPC_FAILED_RETRY
	)
