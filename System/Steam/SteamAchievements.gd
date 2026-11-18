extends Node
## Steamworks achievements and stats bridge for GodotSteam GDExtension (Godot 4.6).
## The game continues to run normally when GodotSteam or the Steam client is unavailable.

const APP_ID := 5608660
const ACHIEVEMENT_FIRST_PATIENT := "FIRST_PATIENT_CURED"
const ACHIEVEMENT_100_PATIENTS := "TREAT_100_PATIENTS"
const ACHIEVEMENT_ALL_BOOK_ENTRIES := "READ_ALL_BOOK_ENTRIES"
const STAT_TOTAL_PATIENTS_CURED := "TOTAL_PATIENTS_CURED"
const PATIENT_ACHIEVEMENT_TARGET := 100
const RETRY_SECONDS := 5.0

var _steam: Object = null
var _initialized := false
var _pending_achievements: Dictionary = {}
var _pending_patient_increments := 0
var _pending_patient_count_floor := 0
var _has_pending_patient_stat := false
var _needs_store := false
var _retry_in_seconds := 0.0


func _init() -> void:
	# GodotSteam reads the App ID from these variables during steamInitEx().
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))


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

	var init_result = _steam.call("steamInitEx")
	if typeof(init_result) != TYPE_DICTIONARY:
		push_warning("Steam initialization returned an unexpected response.")
		return

	_initialized = int(init_result.get("status", -1)) == 0
	if not _initialized:
		push_warning("Steam initialization failed: %s" % str(init_result.get("verbal", "unknown")))
		return

	print("Steam initialized for App ID %d." % APP_ID
	)

	# A Steam account may already have enough progress to satisfy a stat-based achievement.
	if _steam.has_method("getStatInt"):
		var current_count := int(_steam.call("getStatInt", STAT_TOTAL_PATIENTS_CURED))
		if current_count >= PATIENT_ACHIEVEMENT_TARGET:
			_pending_achievements[ACHIEVEMENT_100_PATIENTS] = true

	_flush_pending()


func _process(delta: float) -> void:
	if not _initialized:
		return

	if _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")

	if (
		_pending_achievements.is_empty()
		and not _has_pending_patient_stat
		and not _needs_store
	):
		return

	_retry_in_seconds -= delta
	if _retry_in_seconds <= 0.0:
		_retry_in_seconds = RETRY_SECONDS
		_flush_pending()


# -------------------------------------------------------------------
# Public achievement API
# -------------------------------------------------------------------

func unlock_first_patient_cured() -> void:
	unlock(ACHIEVEMENT_FIRST_PATIENT)


func unlock_read_all_book_entries() -> void:
	unlock(ACHIEVEMENT_ALL_BOOK_ENTRIES)


func unlock(achievement_api_name: String) -> void:
	var api_name := achievement_api_name.strip_edges()
	if api_name.is_empty():
		return

	_pending_achievements[api_name] = true
	_flush_pending()


# -------------------------------------------------------------------
# Patient statistics
# -------------------------------------------------------------------

# Called once for each newly recorded successful treatment.
# local_success_count is used as a lower bound to recover progress from older saves.
func record_successful_patient(local_success_count: int) -> void:
	_pending_patient_increments += 1
	_pending_patient_count_floor = maxi(_pending_patient_count_floor, maxi(local_success_count, 0))
	_has_pending_patient_stat = true
	_flush_pending()


# Called when a save is loaded. It never decreases the Steam account's lifetime statistic.
func sync_successful_patient_count(local_success_count: int) -> void:
	_pending_patient_count_floor = maxi(_pending_patient_count_floor, maxi(local_success_count, 0))
	_has_pending_patient_stat = true
	_flush_pending()


func get_successful_patient_count() -> int:
	if not _initialized or not _steam.has_method("getStatInt"):
		return 0
	return int(_steam.call("getStatInt", STAT_TOTAL_PATIENTS_CURED))


# -------------------------------------------------------------------
# Steam submission
# -------------------------------------------------------------------

func _flush_pending() -> void:
	if not _initialized:
		return

	var should_store := false

	if _has_pending_patient_stat:
		if not _steam.has_method("getStatInt") or not _steam.has_method("setStatInt"):
			push_warning("GodotSteam stat methods are unavailable; patient progress remains pending.")
		else:
			var current_count := int(_steam.call("getStatInt", STAT_TOTAL_PATIENTS_CURED))
			var desired_count := maxi(
				current_count + _pending_patient_increments,
				_pending_patient_count_floor
			)

			if desired_count > current_count:
				var stat_set := bool(_steam.call(
					"setStatInt",
					STAT_TOTAL_PATIENTS_CURED,
					desired_count
				))
				if stat_set:
					should_store = true
					print("Steam stat updated: %s = %d" % [
						STAT_TOTAL_PATIENTS_CURED,
						desired_count
					])
				else:
					push_warning("Steam rejected stat update: " + STAT_TOTAL_PATIENTS_CURED)
			else:
				# The Steam account already has at least this much progress.
				_pending_patient_increments = 0
				_pending_patient_count_floor = 0
				_has_pending_patient_stat = false

			if desired_count >= PATIENT_ACHIEVEMENT_TARGET:
				_pending_achievements[ACHIEVEMENT_100_PATIENTS] = true

			if desired_count > current_count and bool(_steam.call(
				"getStatInt",
				STAT_TOTAL_PATIENTS_CURED
			)) >= desired_count:
				_pending_patient_increments = 0
				_pending_patient_count_floor = 0
				_has_pending_patient_stat = false

	for raw_api_name in _pending_achievements.keys():
		var api_name := String(raw_api_name)
		if not _steam.has_method("getAchievement") or not _steam.has_method("setAchievement"):
			continue

		var state = _steam.call("getAchievement", api_name)
		if typeof(state) != TYPE_DICTIONARY or not bool(state.get("ret", false)):
			# The achievement may not have been published yet; keep it pending and retry.
			continue

		if bool(state.get("achieved", false)):
			_pending_achievements.erase(api_name)
			continue

		if bool(_steam.call("setAchievement", api_name)):
			_pending_achievements.erase(api_name)
			should_store = true
			print("Steam achievement queued: ", api_name)

	if should_store:
		_needs_store = true

	if _needs_store and _steam.has_method("storeStats"):
		if bool(_steam.call("storeStats")):
			_needs_store = false
			print("Steam stats and achievements submitted.")
		else:
			push_warning("Steam storeStats() failed; will retry.")
