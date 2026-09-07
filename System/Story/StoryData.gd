extends Resource
class_name StoryData

# =========================================================
# StoryData
#
# 最终剧情配置结构：
# 1. 触发条件：场景 / 天数 / 金钱 / 名望 / 条目 / 前置剧情 / 治疗结果。
# 2. 播放后动作：播放后目标、生成治疗 NPC、数值奖励。
# 3. 基础设置：PlayOnce / SortIndex。
#
# Excel 策划表使用中文表头；运行时仍使用稳定的英文内部字段。
# night_end 作为“触发场景”的一个特殊值。
# gameover / endgame 作为“播放后”的特殊值。
# =========================================================

const COMPARE_GTE := "gte"
const COMPARE_LTE := "lte"

const TREATMENT_RESULT_CURED := "cured"
const TREATMENT_RESULT_FAILED := "failed"

const TRIGGER_SCENE_NIGHT_END := "night_end"
const AFTER_PLAY_GAMEOVER := "gameover"
const AFTER_PLAY_ENDGAME := "endgame"

const BACKGROUND_MODE_DEFAULT := "default"
const BACKGROUND_MODE_CURRENT_SCENE := "current_scene"

# 旧 TriggerType 常量仅用于读取尚未重新导出的旧 .tres。
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

@export var story_id: String = ""
@export var story_name: String = ""


# =========================================================
# 一、触发条件
# 所有已填写条件使用 AND 判断。
# =========================================================
@export_category("Conditions")

# clinic / night / map 表示进入对应场景时检查。
# night_end 表示玩家在 Night 点击“休息，进入明天”时检查。
# 留空表示不限制触发场景。
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "clinic,night,map,night_end")
var condition_scene: String = ""

# 天数条件：
# - 没有前置剧情：current_day >= condition_day。
# - 有前置剧情且不是治疗结果剧情：前置剧情完成后经过 condition_day 天。
# - 治疗结果剧情：按当前绝对天数判断。
# <= 0 表示不限制天数。
@export var condition_day: int = 0

# Excel 中显示 ≥ / ≤；import_data.py 会转换成 gte / lte。
# Op 留空表示不启用该条件，数值本身可以为 0。
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "gte,lte")
var condition_money_op: String = ""
@export var condition_money: int = 0

@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "gte,lte")
var condition_reputation_op: String = ""
@export var condition_reputation: int = 0

# 必须已解锁的医书 / 图鉴条目。
@export var condition_entry_id: String = ""

# 普通剧情：已完整播放的前置剧情。
# 治疗结果剧情：本次治疗由哪个主剧情发起。
@export var condition_story_id: String = ""

# cured / failed 只在一次治疗结果检查中存在，不保存为长期状态。
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "cured,failed")
var condition_treatment_result: String = ""


# =========================================================
# 二、播放后动作
# =========================================================
@export_category("Actions")

# clinic / night / map：剧情结束后前往对应场景。
# gameover：失败结局，结束本局并直接返回主菜单。
# endgame：最终通关，播放片尾动画后返回主菜单。
# 留空：使用当前流程的默认返回目标。
@export_custom(PROPERTY_HINT_ENUM_SUGGESTION, "clinic,night,map,gameover,endgame")
var after_play: String = ""

# 配置 NpcID 后，剧情完整播放后生成并进入 story NPC 诊疗。
@export var clinic_npc_id: String = ""
@export var clinic_disease: DiseaseData
@export var clinic_npc_portrait: Texture2D

# Excel 暂不单独配置诊疗立绘位置，默认中间。
@export_enum("left", "mid", "right")
var clinic_npc_portrait_side: String = "mid"

# 正数增加，负数扣除，0 不变化。
@export var money_change: int = 0
@export var reputation_points_change: int = 0
@export var experience_points_change: int = 0


# =========================================================
# 三、基础设置
# =========================================================
@export_category("Settings")

@export var play_once: bool = true

# 同一检查时刻有多条剧情同时满足时，数值越小优先级越高。
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
# 新 import_data.py 不再写这些字段。
# 仅用于当前仓库中尚未重新生成的旧 .tres 平滑过渡。
# =========================================================
@export_storage var trigger_story_id: String = ""
@export_storage var trigger_type: String = ""
@export_storage var trigger_scene: String = ""
@export_storage var trigger_day: int = 0
@export_storage var trigger_money: int = 0
@export_storage var required_reputation_points: int = 0
@export_storage var unlock_entry_id: String = ""
@export_storage var return_scene: String = ""
@export_storage var end_game: bool = false


func uses_legacy_trigger_schema() -> bool:
	return trigger_type.strip_edges() != ""


func get_condition_scene() -> String:
	var value := condition_scene.strip_edges().to_lower()
	if value != "":
		return value

	if not uses_legacy_trigger_schema():
		return ""

	if trigger_type.strip_edges().to_lower() == TRIGGER_TYPE_NIGHT_END:
		return TRIGGER_SCENE_NIGHT_END

	return trigger_scene.strip_edges().to_lower()


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
		# 旧 below 是严格 <；整数名望下转换成 <= threshold - 1。
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


func get_after_play() -> String:
	var value := after_play.strip_edges().to_lower()
	if value != "":
		return value

	# 兼容旧资源中单独的 EndGame / ReturnScene。
	if end_game:
		return AFTER_PLAY_GAMEOVER

	if uses_legacy_trigger_schema():
		var legacy_type := trigger_type.strip_edges().to_lower()
		if legacy_type in [
			TRIGGER_TYPE_DAY_REPUTATION_OVER,
			TRIGGER_TYPE_DAY_REPUTATION_BELOW_OVER,
			TRIGGER_TYPE_STORY_NPC_FAILED_OVER,
		]:
			return AFTER_PLAY_GAMEOVER

	var legacy_return_scene := return_scene.strip_edges().to_lower()
	if legacy_return_scene in ["clinic", "night", "map"]:
		return legacy_return_scene

	return ""


func get_return_scene() -> String:
	var value := get_after_play()
	if value in ["clinic", "night", "map"]:
		return value
	return ""


func should_game_over() -> bool:
	return get_after_play() == AFTER_PLAY_GAMEOVER


func should_end_game() -> bool:
	return get_after_play() == AFTER_PLAY_ENDGAME


func is_legacy_failed_retry() -> bool:
	return (
		uses_legacy_trigger_schema()
		and trigger_type.strip_edges().to_lower() == TRIGGER_TYPE_STORY_NPC_FAILED_RETRY
	)
