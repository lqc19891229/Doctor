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
# - “播放后”统一使用 after_play：clinic / night / map / endgame。
# - 生成治疗 NPC 仍由 Story.gd / Main.gd 执行。
# - 性能：剧情资源启动时缓存一次；运行时按场景/治疗结果索引查询。
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

# =========================================================
# 运行时剧情缓存 / 索引
#
# 原则：
# 1. 文件系统扫描与 Resource load 只在缓存构建时发生。
# 2. 运行时剧情检查只访问内存中的 StoryData。
# 3. 按“ConditionScene + TreatmentResult”缩小候选集合。
# 4. 每个候选集合在缓存构建时预排序，运行时不再 sort_custom()。
# =========================================================
var _story_cache_by_path: Dictionary = {}
var _story_path_by_id: Dictionary = {}
var _story_path_by_instance_id: Dictionary = {}
var _story_by_id: Dictionary = {}
var _story_candidates_by_scene_result: Dictionary = {}
var _global_story_candidates_by_result: Dictionary = {}
var _story_cache_ready: bool = false


func _ready() -> void:
	refresh_registered_story_paths()


func refresh_registered_story_paths() -> void:
	var started_ms := Time.get_ticks_msec()

	_story_cache_ready = false
	registered_story_paths.clear()
	_scan_story_dir(STORY_DIR)
	registered_story_paths.sort()
	_rebuild_story_cache_and_indexes()

	if OS.is_debug_build():
		print(
			"[StoryManager] 剧情缓存完成：",
			_story_cache_by_path.size(),
			" 个，索引桶 ",
			_story_candidates_by_scene_result.size() + _global_story_candidates_by_result.size(),
			" 个，耗时 ",
			Time.get_ticks_msec() - started_ms,
			" ms"
		)


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


func _rebuild_story_cache_and_indexes() -> void:
	_story_cache_by_path.clear()
	_story_path_by_id.clear()
	_story_path_by_instance_id.clear()
	_story_by_id.clear()
	_story_candidates_by_scene_result.clear()
	_global_story_candidates_by_result.clear()

	# 第一遍：只做一次 Resource load，并建立 Path / ID 映射。
	for story_path in registered_story_paths:
		var story := _load_story_from_disk(story_path)
		if story == null:
			continue

		_story_cache_by_path[story_path] = story
		_story_path_by_instance_id[story.get_instance_id()] = story_path

		var story_id := story.story_id.strip_edges()
		if story_id == "":
			continue

		if _story_path_by_id.has(story_id):
			push_warning(
				"发现重复 StoryID：%s。路径 %s 将继续保留排序靠前的原记录。"
				% [story_id, story_path]
			)
			continue

		_story_path_by_id[story_id] = story_path
		_story_by_id[story_id] = story

	# 第二遍：按固定条件建立候选索引。
	for story_path in registered_story_paths:
		var story = _story_cache_by_path.get(story_path)
		if story is StoryData:
			_index_story_candidate(story as StoryData)

	_sort_story_candidate_indexes()
	_story_cache_ready = true


func _load_story_from_disk(story_path: String) -> StoryData:
	var clean_path := story_path.strip_edges()
	if clean_path == "":
		return null

	var loaded_story: Resource = load(clean_path)
	if loaded_story == null:
		push_warning("剧情资源加载失败：" + clean_path)
		return null

	if not loaded_story is StoryData:
		push_warning("加载的资源不是 StoryData：" + clean_path)
		return null

	return loaded_story as StoryData


func _load_story_resource(story_path: String) -> StoryData:
	var clean_path := story_path.strip_edges()
	if clean_path == "":
		return null

	if _story_cache_by_path.has(clean_path):
		var cached = _story_cache_by_path[clean_path]
		if cached is StoryData:
			return cached as StoryData

	# 兼容运行时手动传入、但没有登记到 Data/Story 的剧情路径。
	# 这种路径只按需 load 一次并缓存，不自动加入触发索引。
	var story := _load_story_from_disk(clean_path)
	if story == null:
		return null

	_story_cache_by_path[clean_path] = story
	_story_path_by_instance_id[story.get_instance_id()] = clean_path

	var story_id := story.story_id.strip_edges()
	if story_id != "" and not _story_path_by_id.has(story_id):
		_story_path_by_id[story_id] = clean_path
		_story_by_id[story_id] = story

	return story


func _ensure_story_cache() -> void:
	if _story_cache_ready:
		return

	if registered_story_paths.is_empty():
		refresh_registered_story_paths()
		return

	_rebuild_story_cache_and_indexes()


func _make_story_candidate_key(scene: String, treatment_result: String) -> String:
	return scene.strip_edges().to_lower() + "|" + treatment_result.strip_edges().to_lower()


func _index_story_candidate(story: StoryData) -> void:
	if story == null:
		return

	var required_scene := story.get_condition_scene()
	var required_treatment_result := story.get_condition_treatment_result()

	if required_scene == "":
		var global_bucket: Array = _global_story_candidates_by_result.get(
			required_treatment_result,
			[]
		)
		global_bucket.append(story)
		_global_story_candidates_by_result[required_treatment_result] = global_bucket
		return

	var key := _make_story_candidate_key(required_scene, required_treatment_result)
	var scene_bucket: Array = _story_candidates_by_scene_result.get(key, [])
	scene_bucket.append(story)
	_story_candidates_by_scene_result[key] = scene_bucket


func _sort_story_candidate_indexes() -> void:
	for key in _story_candidates_by_scene_result.keys():
		var bucket: Array = _story_candidates_by_scene_result[key]
		bucket.sort_custom(Callable(self, "_story_sort_before"))
		_story_candidates_by_scene_result[key] = bucket

	for key in _global_story_candidates_by_result.keys():
		var bucket: Array = _global_story_candidates_by_result[key]
		bucket.sort_custom(Callable(self, "_story_sort_before"))
		_global_story_candidates_by_result[key] = bucket


func get_story_by_id(story_id: String) -> StoryData:
	_ensure_story_cache()

	var clean_story_id := story_id.strip_edges()
	if clean_story_id == "":
		return null

	var story = _story_by_id.get(clean_story_id)
	if story is StoryData:
		return story as StoryData

	return null


func get_story_path(target_story: StoryData) -> String:
	if target_story == null:
		return ""

	_ensure_story_cache()

	var instance_id := target_story.get_instance_id()
	if _story_path_by_instance_id.has(instance_id):
		return String(_story_path_by_instance_id[instance_id])

	var story_id := target_story.story_id.strip_edges()
	if story_id != "" and _story_path_by_id.has(story_id):
		return String(_story_path_by_id[story_id])

	return ""


func get_cached_story_by_path(story_path: String) -> StoryData:
	_ensure_story_cache()
	return _load_story_resource(story_path)


func get_all_stories() -> Array[StoryData]:
	_ensure_story_cache()

	var result: Array[StoryData] = []
	for story_path in registered_story_paths:
		var story = _story_cache_by_path.get(story_path)
		if story is StoryData:
			result.append(story as StoryData)

	return result


func get_story_cache_stats() -> Dictionary:
	_ensure_story_cache()
	return {
		"story_count": _story_cache_by_path.size(),
		"scene_result_bucket_count": _story_candidates_by_scene_result.size(),
		"global_result_bucket_count": _global_story_candidates_by_result.size(),
	}


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


# Night 点击“休息，进入明天”时调用。
# night_end 现在是“触发场景”的一个特殊值，而不是 TriggerType。
func find_night_end_story(current_day: int) -> StoryData:
	return _find_matching_story({
		"scene": StoryData.TRIGGER_SCENE_NIGHT_END,
		"day": current_day,
		"treatment_result": "",
		"treatment_story_id": "",
		"check_point": "night_end",
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
	_ensure_story_cache()

	var current_scene := String(context.get("scene", "")).strip_edges().to_lower()
	var treatment_result := String(
		context.get("treatment_result", "")
	).strip_edges().to_lower()

	# 只取与当前场景 / 治疗结果有关的剧情。
	# ConditionScene 为空的剧情属于全局候选，因此单独维护一个已排序桶。
	var scene_key := _make_story_candidate_key(current_scene, treatment_result)
	var scene_candidates: Array = _story_candidates_by_scene_result.get(scene_key, [])
	var global_candidates: Array = _global_story_candidates_by_result.get(
		treatment_result,
		[]
	)

	# 两个桶都已经预排序。这里做一次无分配的有序归并扫描，
	# 找到第一个真正满足动态条件的剧情就直接返回。
	var scene_index := 0
	var global_index := 0

	while scene_index < scene_candidates.size() or global_index < global_candidates.size():
		var story: StoryData = null

		if scene_index >= scene_candidates.size():
			story = global_candidates[global_index] as StoryData
			global_index += 1
		elif global_index >= global_candidates.size():
			story = scene_candidates[scene_index] as StoryData
			scene_index += 1
		else:
			var scene_story := scene_candidates[scene_index] as StoryData
			var global_story := global_candidates[global_index] as StoryData

			if _story_sort_before(scene_story, global_story):
				story = scene_story
				scene_index += 1
			else:
				story = global_story
				global_index += 1

		if story != null and _is_story_condition_matched(story, context):
			return story

	return null


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

	# 旧 .tres 仍可通过兼容字段读取；新资源不会写 trigger_type。
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

	if data != null:
		return data.get_return_scene()

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

	# 正常启动扫描期间缓存还未 ready，不需要每添加一个路径就重建。
	# 如果运行时有外部代码动态登记剧情，则让下一次查询统一重建一次索引。
	if _story_cache_ready:
		registered_story_paths.sort()
		_story_cache_ready = false


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
