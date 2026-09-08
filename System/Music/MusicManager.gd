extends Node

var current_music_path:String = ""
var current_place:String = ""
var current_season:String = ""

var bgm_player:AudioStreamPlayer
var fade_time:float = 1.5
var fade_tween:Tween


func _ready():
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM_Player"
	add_child(bgm_player)
	bgm_player.volume_db = -10


# 播放场景音乐
# 目录:
# Assets/Audio/BGM/Clinic/Spring
# Assets/Audio/BGM/Night/Winter

func play_scene_music(place:String):

	current_place = place
	current_season = GameTime.season

	var folder = "res://Assets/Audio/BGM/" + place + "/" + current_season

	var path = find_music(folder)

	if path == "":
		print("MusicManager: 找不到音乐:", folder)
		return

	play_music(path)



func find_music(folder:String)->String:

	var dir = DirAccess.open(folder)

	if dir == null:
		return ""

	for file in dir.get_files():

		if file.ends_with(".ogg") or file.ends_with(".mp3") or file.ends_with(".wav"):
			return folder + "/" + file

	return ""



# StoryData:
# music:"sad"
#
# 对应:
# Assets/Audio/BGM/Story/sad.ogg

func play_story_music(id:String):

	var path = "res://Assets/Audio/BGM/Story/" + id + ".ogg"

	if not FileAccess.file_exists(path):
		print("MusicManager: 剧情音乐不存在:", path)
		return

	play_music(path)



func play_music(path:String):

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



func restore_scene_music():

	if current_place == "":
		return

	play_scene_music(current_place)



func stop_music():

	if fade_tween:
		fade_tween.kill()

	bgm_player.stop()

	current_music_path = ""
