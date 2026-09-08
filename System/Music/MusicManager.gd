extends Node


# ==================================================
# MusicManager
# 全局音乐管理系统
#
# 功能：
# 1. clinic / night 四季BGM
# 2. 剧情指定音乐切换
# 3. 剧情结束恢复原BGM
# 4. 全局调用
#
# Autoload:
# MusicManager
# ==================================================



# 当前播放音乐路径
var current_music_path:String = ""


# 当前场景信息
var current_place:String = ""


# 当前季节
var current_season:String = ""



# 音乐播放器

var bgm_player:AudioStreamPlayer



# ==================================================
# 场景BGM配置
# ==================================================

var scene_music = {

	"clinic":
	{
		"spring":
		"res://Assets/Audio/BGM/Clinic/spring.ogg",

		"summer":
		"res://Assets/Audio/BGM/Clinic/summer.ogg",

		"autumn":
		"res://Assets/Audio/BGM/Clinic/autumn.ogg",

		"winter":
		"res://Assets/Audio/BGM/Clinic/winter.ogg"
	},


	"night":
	{
		"spring":
		"res://Assets/Audio/BGM/Night/spring.ogg",

		"summer":
		"res://Assets/Audio/BGM/Night/summer.ogg",

		"autumn":
		"res://Assets/Audio/BGM/Night/autumn.ogg",

		"winter":
		"res://Assets/Audio/BGM/Night/winter.ogg"
	}

}



# ==================================================
# 剧情特殊音乐
# ==================================================

var story_music = {


	"ending":
	"res://Assets/Audio/BGM/Special/ending.ogg",


	"battle":
	"res://Assets/Audio/BGM/Special/battle.ogg",


	"sad":
	"res://Assets/Audio/BGM/Special/sad.ogg"

}



# ==================================================
# 初始化
# ==================================================

func _ready():

	bgm_player = AudioStreamPlayer.new()

	bgm_player.name = "BGM_Player"

	add_child(bgm_player)


	# 默认音量
	bgm_player.volume_db = -10



# ==================================================
# 播放场景音乐
#
# 示例：
# MusicManager.play_scene_music("clinic")
#
# 自动读取：
# GameTime.season
# ==================================================

func play_scene_music(place:String):


	if not scene_music.has(place):

		print("MusicManager: 找不到场景音乐:",place)
		return



	var season = GameTime.season



	if not scene_music[place].has(season):

		print("MusicManager: 找不到季节音乐:",season)
		return



	current_place = place

	current_season = season



	var music_path = scene_music[place][season]


	play_music(music_path)



# ==================================================
# 剧情音乐
#
# 示例：
# MusicManager.play_story_music("sad")
# ==================================================

func play_story_music(id:String):


	if not story_music.has(id):

		print("MusicManager: 找不到剧情音乐:",id)
		return



	play_music(
		story_music[id]
	)



# ==================================================
# 核心播放
# ==================================================

func play_music(path:String):


	if current_music_path == path:

		return



	var music = load(path)


	if music == null:

		print("MusicManager: 音乐文件不存在:",path)
		return



	current_music_path = path


	bgm_player.stream = music


	bgm_player.play()



# ==================================================
# 恢复场景音乐
#
# 剧情结束调用
# ==================================================

func restore_scene_music():


	if current_place == "":

		return



	play_scene_music(
		current_place
	)



# ==================================================
# 停止音乐
# ==================================================

func stop_music():


	if bgm_player:

		bgm_player.stop()


	current_music_path = ""
