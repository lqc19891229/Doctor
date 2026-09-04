extends Node

# =========================================================
# StoryManager.gd
#
# 新剧情规则：
# - 不再用 TriggerType 决定剧情种类。
# - 所有剧情统一由 StoryData Conditions 判断。
# - 条件全部为 AND；空条件表示不限制。
# - 治疗成功 / 失败通过一次性的 context 传入，不保存为长期状态。
# - 同时满足多条剧情时按 SortIndex（小 -> 大）排序，再按 StoryID 排序。
# - 剧情完整播放后由 apply_story_value_changes() 结算金钱 / 名望 / 心得。
# - 返回场景、结束游戏、生成治疗 NPC 仍由 Story.gd / Main.gd 执行动作。
# =========================================================

var current_story: StoryData = null
var return_scene_override: String = ""

# 旧逻辑兼容变量。
var has_played_clinic_intro: bool = false

# 已完整播放剧情。
var played_story_ids: Dictionary = {}

# 剧情第一次完整播放结束时的游戏天数。
var played_story_days: Dictionary = {}

const STORY_DIR: String = "res://Data/Story"
var registered_story_paths: Array[String] = []


func _ready() -> void:
	refresh_registered_story_paths()


func refresh_registered_story_paths() -> void:
	registered_story_paths.clear()
	_scan_story_dir(STORY_DIR)
	registered_story_paths.sort()

	print("已登记剧情数量：", registered_story_paths.size())
	for story_path in registered_story_paths:
		print("登记剧情：", story_path)


func _scan_story_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("剧情目录不存在：" + dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while not file_name.is_empty():
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue

		var full_path := dir_path.path_join(file_name)

		if dir.current_is_dir():
			_scan_story_dir(full_path)
		elif file_name.ends_with(".tres"):
			register_story_path(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


# Cached 版本会覆盖这个入口，统一复用下面所有条件判断。
func _load_story_resource(story_path: String) -> StoryData:
	var loaded_story: Resource = load(story_path)
	if loaded_story == null:
		push_warning("剧情资源加载失败：" + story_path)
		return null

	if not loaded_story is StoryData:
		push_warning("加载的资源不是 StoryData：" + story_path)
		return null

	return loaded_story as StoryData


func get_all_stories() -> Array[StoryData]:
	var result: Array[StoryData] = []

	if registered_story_paths.is_empty():
		refresh_registered_story_paths()

	for story_path in registered_story_paths:
		var story := _load_story_resource(story_path)
		if story != null:
			result.append(story)

	return result


func set_story(story: StoryData, return_scene: String = "") -> bool:
	if story == null:
		push_warning("StoryManager.set_story 收到空 StoryData。")
		return false

	current_story = story
	return_scene_override = return_scene
	return true


func start_story_file(story_path: String, return_scene: String = "") -> bool:
	var clean_path := story_path.strip_edges()
	if clean_path == "":
		push_warning("StoryManager.start_story_file 收到空路径。")
		return false

	var story := _load_story_resource(clean_path)
	if story == null:
		return false

	return set_story(story, return_scene)


# =========================================================
# 统一剧情检查入口
# =========================================================

# 场景进入时调用。
func find_trigger_story(trigger_scene: String, current_day: int) -> StoryData:
	return _find_matching_story({
		"scene": trigger_scene.strip_edges().to_lower(),
		"day": current_day,
		"treatment_result": "",
		"treatment_story_id": "",
		"check_point": "scene_enter",
	})


# 保留旧调用接口。
# 新结构里不再存在 night_end 触发类型；新剧情统一在进入 ConditionScene 时检查。
# 这里仅用于尚未重新导出的旧 night_end .tres，避免过渡期间旧剧情失效。
func find_night_end_story(current_day: int) -> StoryData:
	return _find_matching_story({
		"scene": "night",
		"day": current_day,
		"treatment_result": "",
		"treatment_story_id": "",
		"check_point": "night_end",
		"legacy_only": true,
	})


func find_story_npc_cured_story(
	trigger_scene: String,
	current_day: int,
	treatment_story_id: String
) -> StoryData:
	var clean_treatment_story_id := treatment_story_id.strip_edges()
	if clean_treatment_story_id == "":
		push_warning("治疗成功事件缺少来源剧情 ID。")
		return null

	return _find_matching_story({
		"scene": trigger_scene.strip_edges().to_lower(),
		"day": current_day,
		"treatment_result": StoryData.TREATMENT_RESULT_CURED,
		"treatment_story_id": clean_treatment_story_id,
		"check_point": "treatment",
	})


func find_story_npc_treatment_failed_story(
	trigger_scene: String,
	current_day: int,
	treatment_story_id: String
) -> StoryData:
	var clean_treatment_story_id := treatment_story_id.strip_edges()
	if clean_treatment_story_id == "":
		push_warning("治疗失败事件缺少来源剧情 ID。")
		return null

	return _find_matching_story({
		"scene": trigger_scene.strip_edges().to_lower(),
		"day": current_day,
		"treatment_result": StoryData.TREATMENT_RESULT_FAILED,
		"treatment_story_id": clean_treatment_story_id,
		"check_point": "treatment",
	})


func report_story_npc_cured(
	current_day: int,
	trigger_scene: String = "clinic",
	treatment_story_id: String = ""
) -> StoryData:
	return find_story_npc_cured_story(
		trigger_scene,
		current_day,
		treatment_story_id
	)


func report_story_npc_treatment_failed(
	current_day: int,
	trigger_scene: String = "clinic",
	treatment_story_id: String = ""
) -> StoryData:
	return find_story_npc_treatment_failed_story(
		trigger_scene,
		current_day,
		treatment_story_id
	)


func _find_matching_story(context: Dictionary) -> StoryData:
	if registered_story_paths.is_empty():
		refresh_registered_story_paths()

	var candidates: Array[StoryData] = []

	for story_path in registered_story_paths:
		var story := _load_story_resource(story_path)
		if story == null:
			continue

		if _is_story_condition_matched(story, context):
			candidates.append(story)

	if candidates.is_empty():
		return null

	candidates.sort_custom(Callable(self, "_story_sort_before"))
	return candidates[0]


func _story_sort_before(a: StoryData, b: StoryData) -> bool:
	if a.sort_index != b.sort_index:
		return a.sort_index < b.sort_index

	# 同优先级时，让结束本局的剧情先于普通剧情，兼容原有终局优先规则。
	if a.should_end_game() != b.should_end_game():
		return a.should_end_game()

	return a.story_id.strip_edges() < b.story_id.strip_edges()


func _is_story_condition_matched(story: StoryData, context: Dictionary) -> bool:
	if story == null:
		return false

	var story_id := story.story_id.strip_edges()
	if story_id == "":
		push_warning("自动触发剧情缺少 story_id。")
		return false

	if story.play_once and played_story_ids.has(story_id):
		return false

	# 只对旧 .tres 使用 TriggerType 做兼容筛选。
	# 新 import_data.py 不再写 trigger_type，因此新剧情完全不会依赖它。
	if bool(context.get("legacy_only", false)) and not story.uses_legacy_trigger_schema():
		return false

	if story.uses_legacy_trigger_schema():
		if not _legacy_check_point_matches(story, context):
			return false

	var current_scene := String(context.get("scene", "")).strip_edges().to_lower()
	var current_day := int(context.get("day", 0))
	var event_treatment_result := String(context.get("treatment_result", "")).strip_edges().to_lower()
	var event_treatment_story_id := String(context.get("treatment_story_id", "")).strip_edges()

	# 场景条件。
	var required_scene := story.get_condition_scene()
	if required_scene != "" and required_scene != current_scene:
		return false

	# 治疗结果条件。
	var required_treatment_result := story.get_condition_treatment_result()
	if required_treatment_result != event_treatment_result:
		# 两边都为空才算匹配；有任意一边不同都不能触发。
		return false

	# 前置剧情 / 治疗来源剧情。
	var required_story_id := story.get_condition_story_id()
	var prerequisite_played_day := 0
	if required_story_id == story_id:
		push_warning("剧情不能把自己设置为 ConditionStoryID：" + story_id)
		return false

	if required_story_id != "":
		if required_treatment_result != "":
			# 治疗结果剧情中，ConditionStoryID 表示发起本次治疗的主剧情。
			if event_treatment_story_id == "" or event_treatment_story_id != required_story_id:
				return false
		else:
			# 普通剧情中，ConditionStoryID 表示必须已经完整播放的前置剧情。
			if not has_played_story(required_story_id):
				return false
			prerequisite_played_day = int(played_story_days.get(required_story_id, 0))

	# 天数条件。
	var required_day := story.get_condition_day()
	if required_day > 0:
		var target_day := required_day

		# 普通前置剧情继续保留“完成前置剧情后 N 天”的原有能力。
		# 治疗结果是一次性即时上下文，因此其 Day 仍按绝对天数判断。
		if required_story_id != "" and required_treatment_result == "":
			target_day = prerequisite_played_day + required_day

		if current_day < target_day:
			return false

	# 金钱条件。
	var money_op := story.get_condition_money_op()
	if money_op != "":
		var current_money_result := _get_current_money_wen()
		if not bool(current_money_result.get("ok", false)):
			return false

		if not _compare_numeric(
			int(current_money_result.get("value", 0)),
			story.get_condition_money(),
			money_op,
			"ConditionMoney",
			story_id
		):
			return false

	# 名望条件。
	var reputation_op := story.get_condition_reputation_op()
	if reputation_op != "":
		var current_reputation_result := _get_current_reputation()
		if not bool(current_reputation_result.get("ok", false)):
			return false

		if not _compare_numeric(
			int(current_reputation_result.get("value", 0)),
			story.get_condition_reputation(),
			reputation_op,
			"ConditionReputation",
			story_id
		):
			return false

	# 条目条件。
	var required_entry_id := story.get_condition_entry_id()
	if required_entry_id != "":
		if Unlock == null or not Unlock.has_method("is_entry_unlocked"):
			return false

		if not Unlock.is_entry_unlocked(required_entry_id):
			return false

	return true


func _legacy_check_point_matches(story: StoryData, context: Dictionary) -> bool:
	var legacy_type := story.trigger_type.strip_edges().to_lower()
	var check_point := String(context.get("check_point", "scene_enter")).strip_edges().to_lower()
	var treatment_result := String(context.get("treatment_result", "")).strip_edges().to_lower()

	match legacy_type:
		StoryData.TRIGGER_TYPE_NIGHT_END:
			return check_point == "night_end"
		StoryData.TRIGGER_TYPE_STORY_NPC_CURED:
			return check_point == "treatment" and treatment_result == StoryData.TREATMENT_RESULT_CURED
		StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_RETRY, StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_BACK, StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_OVER:
			return check_point == "treatment" and treatment_result == StoryData.TREATMENT_RESULT_FAILED
		_:
			# scene_enter 与旧 day_reputation_* 都是在进入场景时检查。
			return check_point == "scene_enter"


func _compare_numeric(
	current_value: int,
	target_value: int,
	op: String,
	field_name: String,
	story_id: String
) -> bool:
	match op.strip_edges().to_lower():
		StoryData.COMPARE_GTE:
			return current_value >= target_value
		StoryData.COMPARE_LTE:
			return current_value <= target_value
		_:
			push_warning("Story %s 的 %s 比较方式非法：%s" % [story_id, field_name, op])
			return false


func _get_current_money_wen() -> Dictionary:
	if Unlock == null:
		return {"ok": false, "value": 0}

	if Unlock.has_method("get_money_wen"):
		return {"ok": true, "value": int(Unlock.get_money_wen())}

	if _object_has_property(Unlock, "money_wen"):
		return {"ok": true, "value": int(Unlock.get("money_wen"))}

	push_warning("StoryManager：Unlock 缺少金钱读取接口 get_money_wen / money_wen。")
	return {"ok": false, "value": 0}


func _get_current_reputation() -> Dictionary:
	if Unlock == null:
		return {"ok": false, "value": 0}

	if Unlock.has_method("get_reputation_points"):
		return {"ok": true, "value": int(Unlock.get_reputation_points())}

	if _object_has_property(Unlock, "reputation_points"):
		return {"ok": true, "value": int(Unlock.get("reputation_points"))}

	push_warning("StoryManager：Unlock 缺少名望读取接口 get_reputation_points / reputation_points。")
	return {"ok": false, "value": 0}


func try_set_trigger_story(trigger_scene: String, current_day: int) -> bool:
	var story := find_trigger_story(trigger_scene, current_day)
	if story == null:
		return false

	return set_story(story, get_return_scene(story))


func get_return_scene(data: StoryData = null) -> String:
	if not return_scene_override.is_empty():
		return return_scene_override

	if data != null and not data.return_scene.is_empty():
		return data.return_scene

	return ""


# =========================================================
# 剧情播放后的数值动作
# =========================================================

func apply_story_value_changes(story: StoryData) -> Dictionary:
	var result := {
		"money_change": 0,
		"reputation_change": 0,
		"experience_change": 0,
		"newly_unlocked_stories": [],
		"newly_unlocked_entry_titles": [],
	}

	if story == null:
		return result

	var money_change := int(story.money_change)
	var reputation_change := int(story.reputation_points_change)
	var experience_change := int(story.experience_points_change)

	result["money_change"] = money_change
	result["reputation_change"] = reputation_change
	result["experience_change"] = experience_change

	if Unlock == null:
		if money_change != 0 or reputation_change != 0 or experience_change != 0:
			push_warning("StoryManager：Unlock 不存在，无法结算剧情数值动作。")
		return result

	if money_change != 0:
		_apply_money_change(money_change)

	if reputation_change != 0:
		if Unlock.has_method("add_reputation_points"):
			result["newly_unlocked_stories"] = Unlock.add_reputation_points(reputation_change)
		else:
			push_warning("StoryManager：Unlock 缺少 add_reputation_points()。")

	if experience_change != 0:
		if Unlock.has_method("change_experience_points"):
			result["newly_unlocked_entry_titles"] = Unlock.change_experience_points(experience_change)
		else:
			push_warning("StoryManager：Unlock 缺少 change_experience_points()。")

	return result


# 兼容旧 Main.gd / 其他调用方。
func apply_story_point_changes(story: StoryData) -> Dictionary:
	return apply_story_value_changes(story)


func _apply_money_change(amount: int) -> void:
	if amount == 0 or Unlock == null:
		return

	# 如果以后 UnlockManager 增加统一接口，这里会自动优先使用。
	if Unlock.has_method("change_money_wen"):
		Unlock.call("change_money_wen", amount)
		return

	if _object_has_property(Unlock, "money_wen"):
		var current_money := int(Unlock.get("money_wen"))
		Unlock.set("money_wen", current_money + amount)
		return

	push_warning("StoryManager：Unlock 缺少 change_money_wen() 或 money_wen，无法结算剧情金钱。")


func _object_has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false

	for property_info in target.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true

	return false


# =========================================================
# 剧情播放状态
# =========================================================

func clear_story() -> void:
	current_story = null
	return_scene_override = ""


func register_story_path(story_path: String) -> void:
	var clean_path := story_path.strip_edges()
	if clean_path == "" or registered_story_paths.has(clean_path):
		return

	registered_story_paths.append(clean_path)


func has_played_story(story_id: String) -> bool:
	var clean_story_id := story_id.strip_edges()
	if clean_story_id == "":
		return false
	return played_story_ids.has(clean_story_id)


func mark_story_played_by_id(story_id: String) -> void:
	var clean_story_id := story_id.strip_edges()
	if clean_story_id == "":
		return

	played_story_ids[clean_story_id] = true
	if not played_story_days.has(clean_story_id):
		played_story_days[clean_story_id] = int(GameTime.current_day)


func mark_current_story_played() -> void:
	_mark_story_played(current_story)


func _mark_story_played(story: StoryData) -> void:
	if story == null:
		return

	var story_id := story.story_id.strip_edges()
	if story_id == "":
		return

	played_story_ids[story_id] = true
	if not played_story_days.has(story_id):
		played_story_days[story_id] = int(GameTime.current_day)


# =========================================================
# 存档
# =========================================================

func get_save_data() -> Dictionary:
	return {
		"played_story_ids": played_story_ids.duplicate(true),
		"played_story_days": played_story_days.duplicate(true),
		"has_played_clinic_intro": has_played_clinic_intro,
	}


func load_save_data(data: Dictionary) -> void:
	played_story_ids.clear()
	played_story_days.clear()
	current_story = null
	return_scene_override = ""

	if data.has("played_story_ids") and typeof(data["played_story_ids"]) == TYPE_DICTIONARY:
		played_story_ids = data["played_story_ids"].duplicate(true)

	if data.has("played_story_days") and typeof(data["played_story_days"]) == TYPE_DICTIONARY:
		played_story_days = data["played_story_days"].duplicate(true)

	if data.has("has_played_clinic_intro"):
		has_played_clinic_intro = bool(data["has_played_clinic_intro"])
	else:
		has_played_clinic_intro = false
