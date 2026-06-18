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

# 剧情结束后回到 Clinic 时，需要指定接诊的 story NPC。
# 这里不会在 clear_story() 中清空，而是等 Clinic 消费，避免 Story 场景结束后数据丢失。
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

	# 如果剧情配置了 clinic_npc_id，则剧情结束回到 Clinic 后指定该 story NPC 为当前病人。
	pending_clinic_npc_id = ""
	var raw_clinic_npc_id = story.get("clinic_npc_id")
	if raw_clinic_npc_id != null:
		pending_clinic_npc_id = String(raw_clinic_npc_id).strip_edges()

	# 设置剧情时，顺便记录已播放。
	# 这样可以防止同一个剧情重复触发。
	_mark_story_played(story)

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
		if _is_story_trigger_matched(story, trigger_scene, current_day):
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


func clear_story() -> void:
	# 清空当前剧情缓存。
	# 不要清空 has_played_clinic_intro，否则回到 Clinic 后会重复播放教学剧情。
	# 不要清空 played_story_ids，否则所有一次性剧情都会再次触发。
	# 不要在这里清空 pending_clinic_npc_id，它需要等 Clinic 重新进入后消费。
	current_story = null
	return_scene_override = ""


func consume_pending_clinic_npc_id() -> String:
	# Clinic 回场景后调用。读取后立刻清空，避免重复套用同一个剧情 NPC。
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
	if story_id.is_empty():
		return false

	return played_story_ids.has(story_id)


func mark_story_played_by_id(story_id: String) -> void:
	# 外部可手动标记某个剧情已经播放。
	if story_id.is_empty():
		return

	played_story_ids[story_id] = true


func _is_story_trigger_matched(story: StoryData, trigger_scene: String, current_day: int) -> bool:
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

	# 如果配置了触发场景，则必须和当前场景一致。
	# trigger_scene 仍然保留，因为它控制剧情在哪个场景播放。
	var story_trigger_scene := story.trigger_scene.strip_edges()
	if story_trigger_scene != "" and story_trigger_scene != trigger_scene:
		return false

	# 暂时保留 trigger_day：
	# - trigger_day <= 0 表示不限制天数
	# - trigger_day > 0 表示必须当前天数达到后才允许触发
	# 这样可以兼容你现有按天触发的旧剧情，同时叠加名望解锁条件。
	if story.trigger_day > 0 and current_day < story.trigger_day:
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
	var story_id: String = story.get("story_id")

	# 没有 ID 的剧情不记录。
	if story_id.is_empty():
		return

	# 读取是否只播放一次。
	var play_once: bool = true

	var raw_play_once = story.get("play_once")
	if raw_play_once != null:
		play_once = raw_play_once

	# 只有一次性剧情才记录。
	if play_once:
		played_story_ids[story_id] = true


# =========================================================
# 保存剧情播放状态
# =========================================================
func get_save_data() -> Dictionary:
	# 返回当前已经播放过的剧情记录。
	# duplicate(true) 表示深拷贝，避免外部误改 StoryManager 内部数据。
	return {
		"played_story_ids": played_story_ids.duplicate(true),
		"has_played_clinic_intro": has_played_clinic_intro
	}


# =========================================================
# 读取剧情播放状态
# =========================================================
func load_save_data(data: Dictionary) -> void:
	# 先清空，避免读档时残留上一次运行的数据。
	played_story_ids.clear()

	# 恢复已播放剧情 ID。
	if data.has("played_story_ids") and typeof(data["played_story_ids"]) == TYPE_DICTIONARY:
		played_story_ids = data["played_story_ids"].duplicate(true)

	# 恢复旧逻辑兼容变量。
	if data.has("has_played_clinic_intro"):
		has_played_clinic_intro = bool(data["has_played_clinic_intro"])
	else:
		has_played_clinic_intro = false
