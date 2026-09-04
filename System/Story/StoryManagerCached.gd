extends "res://System/Story/StoryManager.gd"

# =========================================================
# StoryManagerCached.gd
#
# 只负责缓存 StoryData 资源。
# 所有“条件 / 动作 / SortIndex”规则统一继承 StoryManager.gd，
# 避免缓存版再维护第二套触发逻辑。
# =========================================================

var _story_cache_by_path: Dictionary = {}
var _story_path_by_id: Dictionary = {}


func _ready() -> void:
	refresh_registered_story_paths()


func refresh_registered_story_paths() -> void:
	super.refresh_registered_story_paths()
	_rebuild_story_cache()


func _rebuild_story_cache() -> void:
	_story_cache_by_path.clear()
	_story_path_by_id.clear()

	var started_ms := Time.get_ticks_msec()
	for story_path in registered_story_paths:
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

	var story_id := story.story_id.strip_edges()
	if story_id != "" and not _story_path_by_id.has(story_id):
		_story_path_by_id[story_id] = clean_path

	return story


# StoryManager 的所有遍历都会经过这个入口，因此自动获得缓存。
func _load_story_resource(story_path: String) -> StoryData:
	return _load_story_into_cache(story_path)


func get_cached_story_by_path(story_path: String) -> StoryData:
	return _load_story_into_cache(story_path)


func get_story_path(target_story: StoryData) -> String:
	if target_story == null:
		return ""

	for story_path in registered_story_paths:
		var story := _load_story_into_cache(story_path)
		if story == target_story:
			return String(story_path)

	var story_id := target_story.story_id.strip_edges()
	if story_id != "" and _story_path_by_id.has(story_id):
		return String(_story_path_by_id[story_id])

	return ""
