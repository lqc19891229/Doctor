extends Node
## Steam achievements bridge for GodotSteam GDExtension (Godot 4).
## Steam is accessed dynamically, so the game can still run without the extension.
## Steamworks App ID: 5608660

const APP_ID := 5608660
const FIRST_PATIENT_CURED := "FIRST_PATIENT_CURED"
const RETRY_SECONDS := 5.0

var _steam: Object = null
var _initialized := false
var _pending: Dictionary = {}
var _retry_in_seconds := 0.0


func _ready() -> void:
	# Keep Steam callbacks running even while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not Engine.has_singleton("Steam"):
		print("Steam achievements disabled: GodotSteam extension not installed.")
		return

	_steam = Engine.get_singleton("Steam")
	if not _steam.has_method("steamInitEx"):
		push_warning("Steam achievements disabled: steamInitEx() unavailable.")
		return

	var init_result = _steam.call("steamInitEx", APP_ID)
	if typeof(init_result) != TYPE_DICTIONARY:
		push_warning("Steam initialization returned an unexpected response.")
		return

	_initialized = int(init_result.get("status", -1)) == 0
	if not _initialized:
		push_warning("Steam initialization failed: %s" % str(init_result.get("verbal", "unknown")))


func _process(delta: float) -> void:
	if not _initialized:
		return

	if _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")

	if _pending.is_empty():
		return

	_retry_in_seconds -= delta
	if _retry_in_seconds <= 0.0:
		_retry_in_seconds = RETRY_SECONDS
		_flush_pending()


func unlock_first_patient_cured() -> void:
	unlock(FIRST_PATIENT_CURED)


func unlock(achievement_api_name: String) -> void:
	if achievement_api_name.is_empty():
		return

	_pending[achievement_api_name] = true
	_flush_pending()


func _flush_pending() -> void:
	if not _initialized:
		return

	for raw_api_name in _pending.keys():
		var api_name := String(raw_api_name)
		if not _steam.has_method("getAchievement"):
			continue

		var state = _steam.call("getAchievement", api_name)
		if typeof(state) != TYPE_DICTIONARY or not bool(state.get("ret", false)):
			# Steamworks may not have published the API name yet.
			continue

		if bool(state.get("achieved", false)):
			_pending.erase(api_name)
			continue

		if not bool(_steam.call("setAchievement", api_name)):
			continue

		# setAchievement alone only updates Steam's local cache.
		if bool(_steam.call("storeStats")):
			_pending.erase(api_name)
			print("Steam achievement submitted: ", api_name)
