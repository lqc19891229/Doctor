extends Node

var current_music_path: String = ""
var current_place: String = ""
var current_season: String = ""
var saved_scene_music_path: String = ""

var bgm_player: AudioStreamPlayer
var fade_time: float = 1.5
var fade_tween: Tween


func _ready():
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM_Player"

	# 使用 Godot Audio Bus 管理BGM音量。
	# 如果项目中尚未创建 BGM Bus，则自动使用 Master。
	if AudioServer.get_bus_index("BGM") >= 0:
		bgm_player.bus = "BGM"

	add_child(bgm_player)
	bgm_player.volume_db = -10


# 场景音乐
# Clinic:
# Assets/Audio/BGM/Clinic/Spring
# Assets/Audio/BGM/Clinic/Summer
# Assets/Audio/BGM/Clinic/Autumn
# Assets/Audio/BGM/Clinic/Winter
#
# Night:
# Assets/Audio/BGM/Night

func play_scene_music(place: String):

	current_place = place

	if place == "Clinic":
		current_season = GameTime.season
		var folder = "res://Assets/Audio/BGM/Clinic/" + current_season
		var path = find_music(folder)

		if path == "":
			print("MusicManager: 找不到Clinic音乐:", folder)
			return

		play_music(path)


	elif place == "Night":

		var folder = "res://Assets/Audio/BGM/Night"
		var path = find_music(folder)

		if path == "":
			print("MusicManager: 找不到Night音乐:", folder)
			return

		play_music(path)


	else:

		var folder = "res://Assets/Audio/BGM/" + place
		var path = find_music(folder)

		if path == "":
			print("MusicManager: 找不到场景音乐:", folder)
			return

		play_music(path)



# 从目录随机选择音乐

func find_music(folder: String) -> String:

	var dir = DirAccess.open(folder)

	if dir == null:
		return ""

	var musics = []

	for file in dir.get_files():

		if file.to_lower().ends_with(".mp3"):

			musics.append(folder + "/" + file)


	if musics.is_empty():
		return ""

	return musics.pick_random()



# 剧情音乐
# StoryData:
# music:"sad"
#
# Assets/Audio/BGM/Story/sad.ogg

func play_story_music(id: String):

	if id == "":
		return

	var extensions = [".ogg", ".mp3", ".wav"]

	for ext in extensions:
		var path = "res://Assets/Audio/BGM/Story/" + id + ext

		if FileAccess.file_exists(path):
			play_music(path)
			return

	print("MusicManager: 剧情音乐不存在:", id)



func play_music(path: String):

	if current_music_path == path:
		return

	var music = load(path)

	if music == null:
		return

	current_music_path = path

	if fade_tween:
		fade_tween.kill()


	if bgm_player.playing:

		fade_tween = create_tween()

		fade_tween.tween_property(
			bgm_player,
			"volume_db",
			-40,
			fade_time
		)

		await fade_tween.finished


	bgm_player.stream = music
	bgm_player.play()
	bgm_player.volume_db = -40


	fade_tween = create_tween()

	fade_tween.tween_property(
		bgm_player,
		"volume_db",
		-10,
		fade_time
	)



# 剧情结束恢复场景音乐

func save_scene_music():

	saved_scene_music_path = current_music_path


func restore_scene_music():

	if saved_scene_music_path != "":
		play_music(saved_scene_music_path)
		return

	if current_place == "":
		return

	play_scene_music(current_place)



func stop_music():

	if fade_tween:
		fade_tween.kill()

	bgm_player.stop()

	current_music_path = ""
