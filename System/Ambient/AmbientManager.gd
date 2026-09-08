extends Node

# 环境音管理器
# 负责 Clinic / Night 四季环境音播放、循环、淡入淡出

var ambient_player: AudioStreamPlayer

var current_ambient_path: String = ""
var current_place: String = ""
var current_season: String = ""

var fade_time: float = 2.0
var fade_tween: Tween


func _ready() -> void:
	ambient_player = AudioStreamPlayer.new()
	ambient_player.name = "Ambient_Player"

	if AudioServer.get_bus_index("Ambient") >= 0:
		ambient_player.bus = "Ambient"

	add_child(ambient_player)

	ambient_player.volume_db = -50

	if not ambient_player.finished.is_connected(_on_ambient_finished):
		ambient_player.finished.connect(_on_ambient_finished)



func play_scene_ambient(place: String) -> void:

	current_place = place
	current_season = GameTime.get_season()

	var folder = (
		"res://Assets/Ambient/"
		+ place
		+ "/"
		+ current_season
	)

	var path = find_ambient(folder)

	if path == "":
		print("AmbientManager: 找不到环境音:", folder)
		return

	if path == current_ambient_path:
		return

	play_ambient(path)



func find_ambient(folder: String) -> String:

	var dir = DirAccess.open(folder)

	if dir == null:
		return ""

	var sounds = []

	for file in dir.get_files():

		if (
			file.to_lower().ends_with(".mp3")
			or file.to_lower().ends_with(".ogg")
			or file.to_lower().ends_with(".wav")
		):
			sounds.append(folder + "/" + file)

	if sounds.is_empty():
		return ""

	return sounds.pick_random()



func play_ambient(path: String) -> void:

	var sound = load(path)

	if sound == null:
		return

	current_ambient_path = path

	if fade_tween:
		fade_tween.kill()

	if ambient_player.playing:

		fade_tween = create_tween()

		fade_tween.tween_property(
			ambient_player,
			"volume_db",
			0,
			fade_time
		)

		await fade_tween.finished


	ambient_player.stream = sound
	ambient_player.play()
	ambient_player.volume_db = -50


	fade_tween = create_tween()

	fade_tween.tween_property(
		ambient_player,
		"volume_db",
		-8,
		fade_time
	)



func _on_ambient_finished() -> void:

	if current_place == "":
		return

	var folder = (
		"res://Assets/Ambient/"
		+ current_place
		+ "/"
		+ current_season
	)

	var next_path = find_ambient(folder)

	if next_path == "":
		return

	play_ambient(next_path)



func stop_ambient() -> void:

	if fade_tween:
		fade_tween.kill()

	ambient_player.stop()

	current_ambient_path = ""
	current_place = ""
	current_season = ""
