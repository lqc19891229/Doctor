extends Node

# =========================================================
# StoryManager.gd
# 剧情系统管理器。
# 作为 Autoload 使用。
#
# 正式流程规则：
# - StoryManager 只保存剧情数据，不直接切换场景。
# - 场景切换统一交给 Main.gd 管理。
# - 这样不会破坏 Main → Clinic → NightStudy 的主流程。
#
# 新增规则：
# - 剧情触发条件写在 StoryData 里。
# - StoryManager 负责统一检查触发条件。
# - Clinic / NightStudy 等场景只上报当前状态。
#
# 当前版本：
# - 启动时自动扫描 res://Data/Story/ 下所有 .tres 剧情资源。
# - 不再需要手动把每个剧情路径写进 registered_story_paths。
# =========================================================


# 当前准备播放的剧情。
# Story.tscn 进入后会优先读取这里的数据。
var current_story: StoryData = null


# 剧情结束后的返回场景标记。
# 正式流程里主要作为记录使用，真正返回由 Main.gd 控制。
var return_scene_override: String = ""

# 当前剧情台词结束后，需要交给隐藏 Clinic 后端接诊的 story NPC。
# 这里不会在 clear_story() 中清空，而是等 Main 创建诊疗后端时消费。
var pending_clinic_npc_id: String = ""


# 是否已经播放过 Clinic 第一次进入剧情。
# 注意：
# 这是旧逻辑兼容变量。
# 后续建议逐渐改成 played_story_ids 通用记录。
var has_played_clinic_intro: bool = false


# 已播放过的剧情 ID。
# key = story_id
# value = true
#
# 例：
# played_story_ids["clinic_day_1_intro"] = true
var played_story_ids: Dictionary = {}

# 剧情第一次完整播放结束时的游戏天数。
# key = story_id
# value = 完成剧情时的 current_day
var played_story_days: Dictionary = {}

# story NPC 的累计治愈次数。
# key = npc_id
# value = 已成功治疗次数
# 每次成功治疗都会加 1，并按 StoryData.trigger_cure_count 匹配后续剧情。
var cured_story_npc_counts: Dictionary = {}


# 剧情资源根目录。
# 会自动扫描这个目录下所有 .tres 文件，包括子目录。
const STORY_DIR: String = "res://Data/Story"


# 所有可被自动触发检查的剧情资源路径。
# 启动时会由 refresh_registered_story_paths() 自动填充。
var registered_story_paths: Array[String] = []


func _ready() -> void:
	# Autoload 初始化时自动登记所有剧情资源。
	refresh_registered_story_paths()


func refresh_registered_story_paths() -> void:
	# 重新扫描剧情目录。
	# 如果运行时生成了新的 .tres，也可以手动调用这个函数刷新列表。
	registered_story_paths.clear()

	_scan_story_dir(STORY_DIR)

	# 排序保证触发顺序稳定。
	# 同一天、同场景有多个剧情满足条件时，会优先检查路径排序靠前的剧情。
	registered_story_paths.sort()

	print("已登记剧情数量：", registered_story_paths.size())
	for story_path in registered_story_paths:
		print("登记剧情：", story_path)


func get_all_stories() -> Array[StoryData]:
	# 给 UnlockManager 使用。
	# UnlockManager 不再维护写死的 STORY_UNLOCKS 字典，
	# 而是通过这里读取所有剧情 .tres，检查每个 StoryData 自己配置的名望解锁条件。
	var result: Array[StoryData] = []

	# 如果列表为空，尝试重新扫描一次，避免 Autoload 初始化顺序导致未登记。
	if registered_story_paths.is_empty():
		refresh_registered_story_paths()

	for story_path in registered_story_paths:
		var loaded_story: Resource = load(story_path)

		if loaded_story == null:
			push_warning("剧情资源加载失败：" + story_path)
			continue

		if not loaded_story is StoryData:
			push_warning("加载的资源不是 StoryData：" + story_path)
			continue

		result.append(loaded_story as StoryData)

	return result


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
		else:
			if file_name.ends_with(".tres"):
				register_story_path(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


func set_story(story: StoryData, return_scene: String = "") -> bool:
	# 保存剧情数据。
	if story == null:
		push_warning("StoryManager.set_story 收到空 StoryData。")
		return false

	current_story = story
	return_scene_override = return_scene

	# 如果剧情配置了 clinic_npc_id，则台词结束后在 Story 场景进入该 NPC 的诊疗阶段。
	pending_clinic_npc_id = ""
	var raw_clinic_npc_id = story.get("clinic_npc_id")
	if raw_clinic_npc_id != null:
		pending_clinic_npc_id = String(raw_clinic_npc_id).strip_edges()

	return true


func start_story_file(story_path: String, return_scene: String = "") -> bool:
	# 检查剧情路径是否为空。
	if story_path.is_empty():
		push_warning("StoryManager.start_story_file 收到空路径。")
		return false

	# 加载剧情资源。
	var loaded_story: Resource = load(story_path)

	# 检查资源是否存在。
	if loaded_story == null:
		push_warning("剧情资源加载失败：" + story_path)
		return false

	# 检查资源类型是否正确。
	if not loaded_story is StoryData:
		push_warning("加载的资源不是 StoryData：" + story_path)
		return false

	# 只保存剧情，不切换场景。
	# Main.gd 会在保存成功后进入 Story.tscn。
	return set_story(loaded_story as StoryData, return_scene)


func find_trigger_story(trigger_scene: String, current_day: int) -> StoryData:
	# 兼容原有调用：进入场景时只检查 scene_enter 类型剧情。
	# story_npc_cured 类型剧情不会在每天进入 Clinic / Night 时提前播放。
	return _find_matching_story(
		trigger_scene,
		current_day,
		StoryData.TRIGGER_TYPE_SCENE_ENTER,
		""
	)


func find_story_npc_cured_story(
	npc_id: String,
	trigger_scene: String,
	current_day: int,
	cure_count: int = 0
) -> StoryData:
	# 指定 story NPC 被治愈后，按本次累计治愈次数寻找对应后续剧情。
	var clean_npc_id := npc_id.strip_edges()
	if clean_npc_id == "":
		return null

	# 兼容外部直接调用：未传次数时使用当前已记录的累计次数。
	var event_cure_count := cure_count
	if event_cure_count <= 0:
		event_cure_count = get_story_npc_cure_count(clean_npc_id)
	if event_cure_count <= 0:
		return null

	return _find_matching_story(
		trigger_scene,
		current_day,
		StoryData.TRIGGER_TYPE_STORY_NPC_CURED,
		clean_npc_id,
		event_cure_count
	)


func find_story_npc_treatment_failed_story(
	npc_id: String,
	trigger_scene: String,
	current_day: int
) -> StoryData:
	# 指定 story NPC 治疗失败后，寻找与该 NPC 匹配的失败剧情。
	# 同一个 NPC、场景与条件只应配置一种失败类型。
	# 失败事件本身不写入一次性状态；是否能够再次播放由 StoryData.play_once 控制。
	var clean_npc_id := npc_id.strip_edges()
	if clean_npc_id == "":
		return null

	var failed_retry_story := _find_matching_story(
		trigger_scene,
		current_day,
		StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_RETRY,
		clean_npc_id
	)
	if failed_retry_story != null:
		return failed_retry_story

	var failed_back_story := _find_matching_story(
		trigger_scene,
		current_day,
		StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_BACK,
		clean_npc_id
	)
	if failed_back_story != null:
		return failed_back_story

	return _find_matching_story(
		trigger_scene,
		current_day,
		StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_OVER,
		clean_npc_id
	)


func report_story_npc_cured(
	npc_id: String,
	current_day: int,
	trigger_scene: String = "clinic"
) -> StoryData:
	# Clinic 在 story NPC 治疗成功、治疗结果台词播放完毕后调用。
	# 同一个 npc_id 可以多次成功治疗；每次调用都视为一次新的成功治疗事件。
	var clean_npc_id := npc_id.strip_edges()
	if clean_npc_id == "":
		return null

	var cure_count := get_story_npc_cure_count(clean_npc_id) + 1
	cured_story_npc_counts[clean_npc_id] = cure_count

	return find_story_npc_cured_story(
		clean_npc_id,
		trigger_scene,
		current_day,
		cure_count
	)


func report_story_npc_treatment_failed(
	npc_id: String,
	current_day: int,
	trigger_scene: String = "clinic"
) -> StoryData:
	# 治疗失败后不记录“已失败”状态。
	# 失败剧情结束后的行为由 story_npc_failed_retry /
	# story_npc_failed_back / story_npc_failed_over 决定。
	# 若失败剧情需要再次触发，请在 Story 表中把 PlayOnce 设为 false。
	var clean_npc_id := npc_id.strip_edges()
	if clean_npc_id == "":
		return null

	return find_story_npc_treatment_failed_story(
		clean_npc_id,
		trigger_scene,
		current_day
	)


func has_cured_story_npc(npc_id: String) -> bool:
	return get_story_npc_cure_count(npc_id) > 0


func get_story_npc_cure_count(npc_id: String) -> int:
	# 返回指定 story NPC 的累计成功治疗次数。
	var clean_npc_id := npc_id.strip_edges()
	if clean_npc_id == "":
		return 0

	return maxi(0, int(cured_story_npc_counts.get(clean_npc_id, 0)))


func _find_matching_story(
	trigger_scene: String,
	current_day: int,
	trigger_type: String,
	trigger_npc_id: String,
	trigger_cure_count: int = 0
) -> StoryData:
	# 如果列表为空，尝试重新扫描一次，避免初始化顺序导致未登记。
	if registered_story_paths.is_empty():
		refresh_registered_story_paths()

	# 在所有登记过的剧情里，寻找第一个满足触发条件的剧情。
	for story_path in registered_story_paths:
		var loaded_story: Resource = load(story_path)

		# 跳过加载失败的剧情资源。
		if loaded_story == null:
			push_warning("剧情资源加载失败：" + story_path)
			continue

		# 跳过类型错误的资源。
		if not loaded_story is StoryData:
			push_warning("加载的资源不是 StoryData：" + story_path)
			continue

		var story: StoryData = loaded_story as StoryData

		# 检查这个剧情是否满足触发条件。
		if _is_story_trigger_matched(
			story,
			trigger_scene,
			current_day,
			trigger_type,
			trigger_npc_id,
			trigger_cure_count
		):
			return story

	return null


func try_set_trigger_story(trigger_scene: String, current_day: int) -> bool:
	# 查找当前场景、当前天数是否有可触发剧情。
	var story: StoryData = find_trigger_story(trigger_scene, current_day)

	# 没有找到可触发剧情。
	if story == null:
		return false

	# 优先读取 StoryData 自己配置的 return_scene。
	var return_scene: String = get_return_scene(story)

	# 设置当前剧情。
	return set_story(story, return_scene)


func get_return_scene(data: StoryData = null) -> String:
	# 优先使用外部传入的返回场景。
	if not return_scene_override.is_empty():
		return return_scene_override

	# 如果外部没传，就使用 StoryData 自己设置的返回场景。
	if data != null and not data.return_scene.is_empty():
		return data.return_scene

	return ""


# 结算一段已经完整播放结束的剧情所配置的名望与心得变化。
#
# 说明：
# - 这里只负责结算传入的 StoryData，不负责判断治疗成功或失败。
# - 调用方必须在剧情真正播放完成时调用，不能在剧情刚开始或治疗结果刚产生时调用。
# - StoryData 中的正数表示奖励，负数表示惩罚，0 表示不变化。
# - 本函数不主动存档；调用方可在剧情完成流程结束后统一保存。
#
# 返回值：
# - reputation_change：本次配置的名望变化量。
# - experience_change：本次配置的心得变化量。
# - newly_unlocked_stories：名望增加后新解锁的剧情数据。
# - newly_unlocked_entry_titles：心得增加后新解锁的医书条目标题。
func apply_story_point_changes(story: StoryData) -> Dictionary:
	var result := {
		"reputation_change": 0,
		"experience_change": 0,
		"newly_unlocked_stories": [],
		"newly_unlocked_entry_titles": []
	}

	if story == null:
		return result

	var reputation_change := int(story.reputation_points_change)
	var experience_change := int(story.experience_points_change)
	result["reputation_change"] = reputation_change
	result["experience_change"] = experience_change

	if Unlock == null:
		push_warning("StoryManager：Unlock 不存在，无法结算剧情配置的名望与心得变化。")
		return result

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


func clear_story() -> void:
	# 清空当前剧情缓存。
	# 不要清空 has_played_clinic_intro，否则回到 Clinic 后会重复播放教学剧情。
	# 不要清空 played_story_ids，否则所有一次性剧情都会再次触发。
	# 不要在这里清空 pending_clinic_npc_id，它需要等 Clinic 重新进入后消费。
	current_story = null
	return_scene_override = ""


func consume_pending_clinic_npc_id() -> String:
	# Main 创建 Story 诊疗后端后调用。读取后立刻清空，避免最终回 Clinic 时再次套用。
	var result := pending_clinic_npc_id.strip_edges()
	pending_clinic_npc_id = ""
	return result


func register_story_path(story_path: String) -> void:
	# 运行时登记剧情路径。
	# 自动扫描和外部动态添加剧情都会用这个函数。
	if story_path.is_empty():
		return

	if registered_story_paths.has(story_path):
		return

	registered_story_paths.append(story_path)


func has_played_story(story_id: String) -> bool:
	# 外部可用这个函数检查某个剧情是否已经播放过。
	var clean_story_id := story_id.strip_edges()
	if clean_story_id == "":
		return false

	return played_story_ids.has(clean_story_id)


func mark_story_played_by_id(story_id: String) -> void:
	# 外部可手动标记某个剧情已经播放。
	var clean_story_id := story_id.strip_edges()
	if clean_story_id == "":
		return

	played_story_ids[clean_story_id] = true

	# 只记录第一次完整播放结束时的天数，避免重复调用改变相对计时起点。
	if not played_story_days.has(clean_story_id):
		played_story_days[clean_story_id] = int(GameTime.current_day)


func mark_current_story_played() -> void:
	# 只有剧情确实结束，或已经完成并准备切换到后续剧情时，才由 Main 调用。
	# set_story() 只负责暂存数据，避免玩家在剧情中途退出后被误判为已经播放。
	_mark_story_played(current_story)


func _is_story_trigger_matched(
	story: StoryData,
	trigger_scene: String,
	current_day: int,
	requested_trigger_type: String,
	requested_trigger_npc_id: String,
	requested_trigger_cure_count: int
) -> bool:
	# 检查 StoryData 是否为空。
	if story == null:
		return false

	# 自动触发剧情必须有 story_id，否则无法记录已播放 / 已解锁状态。
	var story_id := story.story_id.strip_edges()
	if story_id == "":
		push_warning("自动触发剧情缺少 story_id。")
		return false

	# 如果是只播放一次，并且已经播放过，则不再触发。
	if story.play_once and played_story_ids.has(story_id):
		return false

	# 如果配置了前置剧情，则必须先完整播放对应剧情。
	# trigger_story_id 为空时，不限制前置剧情。
	var trigger_story_id := story.trigger_story_id.strip_edges()
	var trigger_story_played_day := 0
	if trigger_story_id != "":
		# 防止剧情错误地把自己设置为前置剧情。
		if trigger_story_id == story_id:
			push_warning("剧情不能把自己设置为前置剧情：" + story_id)
			return false

		if not has_played_story(trigger_story_id):
			return false

		# 旧存档可能没有 played_story_days。
		# 这时按第 0 天处理，避免旧存档中的后续剧情永久无法触发。
		trigger_story_played_day = int(played_story_days.get(trigger_story_id, 0))

	# 触发类型必须匹配。
	# 旧剧情资源没有显式填写 trigger_type 时，会使用 StoryData 的 scene_enter 默认值。
	var story_trigger_type := story.trigger_type.strip_edges().to_lower()
	if story_trigger_type == "":
		story_trigger_type = StoryData.TRIGGER_TYPE_SCENE_ENTER

	var clean_requested_trigger_type := requested_trigger_type.strip_edges().to_lower()
	if clean_requested_trigger_type == "":
		clean_requested_trigger_type = StoryData.TRIGGER_TYPE_SCENE_ENTER

	if story_trigger_type != clean_requested_trigger_type:
		return false

	# story NPC 诊疗结果类型必须填写 trigger_npc_id，并与本次 NPC 完全匹配。
	if (
		story_trigger_type == StoryData.TRIGGER_TYPE_STORY_NPC_CURED
		or story_trigger_type == StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_RETRY
		or story_trigger_type == StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_BACK
		or story_trigger_type == StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_OVER
	):
		var required_npc_id := story.trigger_npc_id.strip_edges()
		var event_npc_id := requested_trigger_npc_id.strip_edges()

		if required_npc_id == "":
			push_warning("%s 剧情缺少 trigger_npc_id：%s" % [
				story_trigger_type,
				story_id
			])
			return false

		if required_npc_id != event_npc_id:
			return false

		# 治愈剧情还必须与本次累计治愈次数完全匹配。
		# 旧 .tres 没有显式配置时，StoryData 默认值为 1。
		if story_trigger_type == StoryData.TRIGGER_TYPE_STORY_NPC_CURED:
			var required_cure_count := maxi(1, story.trigger_cure_count)
			if requested_trigger_cure_count != required_cure_count:
				return false

	# 如果配置了触发场景，则必须和当前场景一致。
	# trigger_scene 仍然保留，因为它控制剧情在哪个场景播放。
	var story_trigger_scene := story.trigger_scene.strip_edges()
	if story_trigger_scene != "" and story_trigger_scene != trigger_scene:
		return false

	# trigger_day 规则：
	# - 没有 trigger_story_id：按游戏绝对天数判断。
	# - 有 trigger_story_id：按前置剧情完成日后的相对天数判断。
	# - trigger_day <= 0：不增加额外天数。
	if story.trigger_day > 0:
		var required_trigger_day := story.trigger_day

		if trigger_story_id != "":
			required_trigger_day = trigger_story_played_day + story.trigger_day

		if current_day < required_trigger_day:
			return false

	# 名望剧情规则：
	# - required_reputation_points <= 0：不需要名望解锁，按场景和播放状态正常触发。
	# - required_reputation_points > 0：必须先由 UnlockManager 解锁，StoryManager 才允许播放。
	# 这样“解锁”和“播放”分开：UnlockManager 管名望解锁，StoryManager 管播放。
	if story.required_reputation_points > 0:
		if Unlock == null:
			return false

		if not Unlock.has_method("is_story_unlocked"):
			return false

		if not Unlock.is_story_unlocked(story_id):
			return false

	# unlock_entry_id 现在作为剧情触发前置条件使用。
	# - unlock_entry_id 为空：不限制医书条目。
	# - unlock_entry_id 非空：必须先解锁对应医书条目，剧情才允许触发。
	# 注意：这里不负责解锁条目，只负责检查条目是否已经解锁。
	var required_entry_id := story.unlock_entry_id.strip_edges()
	if required_entry_id != "":
		if Unlock == null:
			return false

		if not Unlock.has_method("is_entry_unlocked"):
			return false

		if not Unlock.is_entry_unlocked(required_entry_id):
			return false

	return true

func _mark_story_played(story: StoryData) -> void:
	# 空剧情不处理。
	if story == null:
		return

	# 读取剧情 ID。
	var story_id := story.story_id.strip_edges()

	# 没有 ID 的剧情不记录。
	if story_id == "":
		return

	# 记录剧情已经完整播放。
	# play_once = false 的剧情也需要记录，才能作为其他剧情的前置条件；
	# 是否阻止重复播放仍由 _is_story_trigger_matched() 中的 play_once 判断控制。
	played_story_ids[story_id] = true

	# 只记录第一次完整播放结束时的天数，避免重复剧情改变相对计时起点。
	if not played_story_days.has(story_id):
		played_story_days[story_id] = int(GameTime.current_day)


# =========================================================
# 保存剧情播放状态
# =========================================================
func get_save_data() -> Dictionary:
	# 返回当前剧情进度。
	# duplicate(true) 表示深拷贝，避免外部误改 StoryManager 内部数据。
	return {
		"played_story_ids": played_story_ids.duplicate(true),
		"played_story_days": played_story_days.duplicate(true),
		"has_played_clinic_intro": has_played_clinic_intro,
		"cured_story_npc_counts": cured_story_npc_counts.duplicate(true),
		# 保留旧字段，方便旧版本代码读取新存档；新版本读档优先使用上面的次数字段。
		"cured_story_npc_ids": _build_legacy_cured_story_npc_ids(),
		"pending_clinic_npc_id": pending_clinic_npc_id
	}


func _build_legacy_cured_story_npc_ids() -> Dictionary:
	# 旧存档格式只记录是否治愈过，这里根据次数生成兼容数据。
	var result: Dictionary = {}
	for raw_npc_id in cured_story_npc_counts.keys():
		var clean_npc_id := String(raw_npc_id).strip_edges()
		if clean_npc_id != "" and int(cured_story_npc_counts[raw_npc_id]) > 0:
			result[clean_npc_id] = true
	return result


# =========================================================
# 读取剧情播放状态
# =========================================================
func load_save_data(data: Dictionary) -> void:
	# 先清空，避免读档时残留上一次运行的数据。
	played_story_ids.clear()
	played_story_days.clear()
	cured_story_npc_counts.clear()
	pending_clinic_npc_id = ""
	current_story = null
	return_scene_override = ""

	# 恢复已播放剧情 ID。
	if data.has("played_story_ids") and typeof(data["played_story_ids"]) == TYPE_DICTIONARY:
		played_story_ids = data["played_story_ids"].duplicate(true)

	# 恢复剧情第一次完整播放结束时的游戏天数。
	# 旧存档没有该字段时保持为空，触发检查会按第 0 天兼容处理。
	if data.has("played_story_days") and typeof(data["played_story_days"]) == TYPE_DICTIONARY:
		played_story_days = data["played_story_days"].duplicate(true)

	# 优先恢复新版累计治愈次数。
	if data.has("cured_story_npc_counts") and typeof(data["cured_story_npc_counts"]) == TYPE_DICTIONARY:
		var saved_counts: Dictionary = data["cured_story_npc_counts"]
		for raw_npc_id in saved_counts.keys():
			var clean_npc_id := String(raw_npc_id).strip_edges()
			var saved_count := maxi(0, int(saved_counts[raw_npc_id]))
			if clean_npc_id != "" and saved_count > 0:
				cured_story_npc_counts[clean_npc_id] = saved_count
	# 兼容旧存档：旧格式中的 true 表示已经成功治疗过 1 次。
	elif data.has("cured_story_npc_ids") and typeof(data["cured_story_npc_ids"]) == TYPE_DICTIONARY:
		var legacy_cured_ids: Dictionary = data["cured_story_npc_ids"]
		for raw_npc_id in legacy_cured_ids.keys():
			var clean_npc_id := String(raw_npc_id).strip_edges()
			if clean_npc_id != "" and bool(legacy_cured_ids[raw_npc_id]):
				cured_story_npc_counts[clean_npc_id] = 1

	# 恢复剧情结束后等待 Clinic 消费的 story NPC。
	# 这样在剧情期间退出并读档时，不会丢失剧情指定的病人。
	if data.has("pending_clinic_npc_id"):
		pending_clinic_npc_id = String(data["pending_clinic_npc_id"]).strip_edges()

	# 恢复旧逻辑兼容变量。
	if data.has("has_played_clinic_intro"):
		has_played_clinic_intro = bool(data["has_played_clinic_intro"])
	else:
		has_played_clinic_intro = false
