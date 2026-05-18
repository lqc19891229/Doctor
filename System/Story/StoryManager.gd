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
# =========================================================


# 当前准备播放的剧情。
# Story.tscn 进入后会优先读取这里的数据。
var current_story: StoryData = null


# 剧情结束后的返回场景标记。
# 正式流程里主要作为记录使用，真正返回由 Main.gd 控制。
var return_scene_override: String = ""


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


# 所有可被自动触发检查的剧情资源路径。
# 之后你新增剧情，只要把 tres 路径加到这里即可。
#
# 注意：
# 这里先放你现有教学剧情路径。
# 如果你的实际路径不同，改成你项目里的真实路径。
var registered_story_paths: Array[String] = [
	"res://Data/Story/teaching_test.tres"
]


func set_story(story: StoryData, return_scene: String = "") -> bool:
	# 保存剧情数据。
	if story == null:
		push_warning("StoryManager.set_story 收到空 StoryData。")
		return false

	current_story = story
	return_scene_override = return_scene

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
	current_story = null
	return_scene_override = ""


func register_story_path(story_path: String) -> void:
	# 运行时登记剧情路径。
	# 如果以后你想从别的地方动态添加剧情，可以用这个函数。
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

	# 读取 StoryData 中配置的 story_id。
	# 需要你在 StoryData.gd 中添加：
	# @export var story_id: String = ""
	var story_id: String = story.get("story_id")

	# 读取 StoryData 中配置的触发场景。
	# 需要你在 StoryData.gd 中添加：
	# @export var trigger_scene: String = ""
	var story_trigger_scene: String = story.get("trigger_scene")

	# 读取 StoryData 中配置的触发天数。
	# 需要你在 StoryData.gd 中添加：
	# @export var trigger_day: int = 0
	var story_trigger_day: int = story.get("trigger_day")

	# 读取 StoryData 中配置的是否只播放一次。
	# 需要你在 StoryData.gd 中添加：
	# @export var play_once: bool = true
	var play_once: bool = true

	var raw_play_once = story.get("play_once")
	if raw_play_once != null:
		play_once = raw_play_once

	# 如果没有配置 story_id，用资源路径不好记录。
	# 所以这里要求自动触发剧情必须有 story_id。
	if story_id.is_empty():
		push_warning("自动触发剧情缺少 story_id。")
		return false

	# 如果是只播放一次，并且已经播放过，则不再触发。
	if play_once and played_story_ids.has(story_id):
		return false

	# 如果配置了触发场景，则必须和当前场景一致。
	if not story_trigger_scene.is_empty() and story_trigger_scene != trigger_scene:
		return false

	# 如果配置了触发天数，则必须和当前天数一致。
	# trigger_day <= 0 表示不限制天数。
	if story_trigger_day > 0 and story_trigger_day != current_day:
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
