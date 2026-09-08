extends Node

var current_music_path:String = ""
var current_place:String = ""
var current_season:String = ""

var bgm_player:AudioStreamPlayer
var fade_time:float = 1.5
var fade_tween:Tween

var scene_music = {
	"clinic": {
		"spring":"res://Assets/Audio/BGM/Clinic/spring.ogg",
		"summer":"res://Assets/Audio/BGM/Clinic/summer.ogg",
		"autumn":"res://Assets/Audio/BGM/Clinic/autumn.ogg",
		"winter":"res://Assets/Audio/BGM/Clinic/winter.ogg"
	},
	"night": {
		"spring":"res://Assets/Audio/BGM/Night/spring.ogg",
		"summer":"res://Assets/Audio/BGM/Night/summer.ogg",
		"autumn":"res://Assets/Audio/BGM/Night/autumn.ogg",
		"winter":"res://Assets/Audio/BGM/Night/winter.ogg"
	}
}

var story_music = {
	"ending":"res://Assets/Audio/BGM/Special/ending.ogg",
	"battle":"res://Assets/Audio/BGM/Special/battle.ogg",
	"sad":"res://Assets/Audio/BGM/Special/sad.ogg"
}

func _ready():
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM_Player"
	add_child(bgm_player)
	bgm_player.volume_db = -10

func play_scene_music(place:String):
	if not scene_music.has(place):
		print("MusicManager: 找不到场景音乐:", place)
		return
	var season = GameTime.season
	if not scene_music[place].has(season):
		print("MusicManager: 找不到季节音乐:", season)
		return
	current_place = place
	current_season = season
	play_music(scene_music[place][season])

func play_story_music(id:String):
	if not story_music.has(id):
		print("MusicManager: 找不到剧情音乐:", id)
		return
	play_music(story_music[id])

func play_music(path:String):
	if current_music_path == path:
		return
	var music = load(path)
	if music == null:
		print("MusicManager: 音乐文件不存在:", path)
		return
	current_music_path = path
	if fade_tween:
		fade_tween.kill()
	if bgm_player.playing:
		fade_tween = create_tween()
		fade_tween.tween_property(bgm_player,"volume_db",-40,fade_time)
		await fade_tween.finished
	bgm_player.stream = music
	bgm_player.play()
	bgm_player.volume_db = -40
	fade_tween = create_tween()
	fade_tween.tween_property(bgm_player,"volume_db",-10,fade_time)

func restore_scene_music():
	if current_place == "":
		return
	play_scene_music(current_place)

func stop_music():
	if fade_tween:
		fade_tween.kill()
	if bgm_player:
		bgm_player.stop()
	current_music_path = ""
