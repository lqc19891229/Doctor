extends "res://System/Story/StoryManager.gd"

# =========================================================
# StoryManagerCached.gd
#
# 保留原 StoryManager 的全部剧情规则，只优化资源读取：
# - 原版 registered_story_paths 仍然是剧情路径事实来源。
# - 第一次扫描路径后，把 StoryData 强引用缓存到 Dictionary。
# - find_trigger_story / find_night_end_story / 名望解锁等后续检查
#   都复用缓存，不再每次同步 load() 所有 .tres。
#
# Autoload 名称仍然必须叫 StoryManager。
# =========================================================

var _story_cache_by_path: Dictionary = {}
var _story_path_by_id: Dictionary = {}


func _ready() -> void:
	# 原版 _ready() 唯一工作就是登记剧情路径。
	# 这里显式调用缓存版 refresh，确保 Autoload 初始化时立即完成一次缓存。
	refresh_registered_story_paths()


func refresh_registered_story_paths() -> void:
	# 仍由原 StoryManager 负责扫描 Data/Story，保证剧情登记规则完全不变。
	super.refresh_registered_story_paths()

	# 路径刷新后重新构建缓存。
	_rebuild_story_cache()


func _rebuild_story_cache() -> void:
	_story_cache_by_path.clear()
	_story_path_by_id.clear()

	var started_ms := Time.get_ticks_msec()

	for story_path in registered_story_paths:
		if typeof(story_path) != TYPE_STRING:
			continue

		_load_story_into_cache(String(story_path))

	if OS.is_debug_build():
		print(
			"[StoryCache] 剧情资源缓存完成：",
			_story_cache_by_path.size(),
			" 个，耗时 ",
			Time.get_ticks_msec() - started_ms,
			" ms"
		)


func _load_story_into_cache(story_path: String) -> StoryData:
	var clean_path := story_path.strip_edges()
	if clean_path == "":
		return null

	if _story_cache_by_path.has(clean_path):
		var cached = _story_cache_by_path[clean_path]
		if cached is StoryData:
			return cached as StoryData

	var loaded_story: Resource = load(clean_path)
	if loaded_story == null:
		push_warning("剧情资源加载失败：" + clean_path)
		return null

	if not loaded_story is StoryData:
		push_warning("加载的资源不是 StoryData：" + clean_path)
		return null

	var story := loaded_story as StoryData
	_story_cache_by_path[clean_path] = story

	# 同一 story_id 如果意外重复，保持 registered_story_paths 排序后的第一个，
	# 与原 Night._find_registered_story_path() 的行为一致。
	var story_id := story.story_id.strip_edges()
	if story_id != "" and not _story_path_by_id.has(story_id):
		_story_path_by_id[story_id] = clean_path

	return story


func get_cached_story_by_path(story_path: String) -> StoryData:
	# 新增运行时路径也能按需缓存一次。
	return _load_story_into_cache(story_path)


func get_story_path(target_story: StoryData) -> String:
	if target_story == null:
		return ""

	# 优先按实例查找，完全对应原逻辑。
	for story_path in registered_story_paths:
		var story := _load_story_into_cache(story_path)
		if story == target_story:
			return story_path

	# 实例不同时，用 story_id 兜底。
	var story_id := target_story.story_id.strip_edges()
	if story_id != "" and _story_path_by_id.has(story_id):
		return String(_story_path_by_id[story_id])

	return ""


func get_all_stories() -> Array[StoryData]:
	var result: Array[StoryData] = []

	if registered_story_paths.is_empty():
		refresh_registered_story_paths()

	for story_path in registered_story_paths:
		var story := _load_story_into_cache(story_path)
		if story != null:
			result.append(story)

	return result


func start_story_file(story_path: String, return_scene: String = "") -> bool:
	var clean_path := story_path.strip_edges()
	if clean_path == "":
		push_warning("StoryManager.start_story_file 收到空路径。")
		return false

	var story := _load_story_into_cache(clean_path)
	if story == null:
		return false

	# 仍然调用原 StoryManager.set_story()，不改变剧情流程。
	return set_story(story, return_scene)


func _find_matching_story(
	trigger_scene: String,
	current_day: int,
	trigger_type: String,
	requested_treatment_story_id: String = ""
) -> StoryData:
	if registered_story_paths.is_empty():
		refresh_registered_story_paths()

	# 与原版完全相同的遍历顺序；
	# 唯一区别是这里取缓存，不再同步重复 load()。
	for story_path in registered_story_paths:
		var story := _load_story_into_cache(story_path)
		if story == null:
			continue

		if _is_story_trigger_matched(
			story,
			trigger_scene,
			current_day,
			trigger_type,
			requested_treatment_story_id
		):
			return story

	return null
