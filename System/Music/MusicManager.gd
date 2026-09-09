extends Node

var current_music_path: String = ""
var current_place: String = ""
var current_season: String = ""

# 当前音乐类型：scene = 场景BGM，story = 剧情BGM
var current_music_mode: String = ""

# 当前场景BGM目录。场景音乐播放完后，会从这里随机选择下一首。
var current_scene_folder: String = ""

var bgm_player: AudioStreamPlayer
var fade_time: float = 1.5
var fade_tween: Tween


func _ready():
	# 全局音乐始终运行。
	# JudgementResult 暂停 SceneTree 时，BGM 仍继续播放。
	process_mode = Node.PROCESS_MODE_ALWAYS

	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM_Player"
	bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS

	# 使用 Godot Audio Bus 管理BGM音量。
	# 如果项目中尚未创建 BGM Bus，则自动使用 Master。
	if AudioServer.get_bus_index("BGM") >= 0:
		bgm_player.bus = "BGM"

	add_child(bgm_player)
	bgm_player.volume_db = -10

	# 场景BGM自然播放结束后，自动随机播放下一首。
	if not bgm_player.finished.is_connected(_on_bgm_finished):
		bgm_player.finished.connect(_on_bgm_finished)


# 场景音乐
# Clinic:
# Assets/Music/BGM/Clinic/Spring
# Assets/Music/BGM/Clinic/Summer
# Assets/Music/BGM/Clinic/Autumn
# Assets/Music/BGM/Clinic/Winter
#
# Night:
# Assets/Music/BGM/Night

func play_scene_music(place: String):

	current_place = place

	if place == "Clinic":
		current_season = GameTime.get_season()
		var folder = "res://Assets/Music/BGM/Clinic/" + current_season
		var path = find_music(folder)

		if path == "":
			print("MusicManager: 找不到Clinic音乐:", folder)
			return

		current_scene_folder = folder
		current_music_mode = "scene"
		play_music(path)


	elif place == "Night":

		var folder = "res://Assets/Music/BGM/Night"
		var path = find_music(folder)

		if path == "":
			print("MusicManager: 找不到Night音乐:", folder)
			return

		current_scene_folder = folder
		current_music_mode = "scene"
		play_music(path)


	else:

		var folder = "res://Assets/Music/BGM/" + place
		var path = find_music(folder)

		if path == "":
			print("MusicManager: 找不到场景音乐:", folder)
			return

		current_scene_folder = folder
		current_music_mode = "scene"
		play_music(path)



# 从目录随机选择音乐。
# 有多首时可排除上一首，避免连续重复。

func find_music(folder: String, exclude_path: String = "") -> String:

	var dir = DirAccess.open(folder)

	if dir == null:
		return ""

	var musics = []

	for file in dir.get_files():

		if (
			file.to_lower().ends_with(".mp3")
			or file.to_lower().ends_with(".ogg")
			or file.to_lower().ends_with(".wav")
		):

			musics.append(folder + "/" + file)


	if musics.is_empty():
		return ""

	# 有多首时，不连续重复上一首。
	if exclude_path != "" and musics.size() > 1:
		musics.erase(exclude_path)

	return musics.pick_random()



# 场景BGM自然播放结束后随机播放下一首。
# 如果目录里只有一首，就重新播放这一首，实现连续循环。

func _on_bgm_finished() -> void:

	if current_music_mode != "scene":
		return

	if current_scene_folder == "":
		return

	var next_path = find_music(current_scene_folder, current_music_path)

	if next_path == "":
		print("MusicManager: 找不到下一首场景音乐:", current_scene_folder)
		return

	play_music(next_path, true)



# 剧情音乐
# StoryData:
# music:"sad"
#
# Assets/Music/BGM/Story/sad.ogg

func play_story_music(id: String):

	if id == "":
		return

	var extensions = [".ogg", ".mp3", ".wav"]

	for ext in extensions:
		var path = "res://Assets/Music/BGM/Story/" + id + ext

		if FileAccess.file_exists(path):
			current_music_mode = "story"
			play_music(path)
			return

	print("MusicManager: 剧情音乐不存在:", id)



func play_music(path: String, force_restart: bool = false):

	# 普通切换时，相同音乐不重复启动。
	# 场景目录只有一首时，force_restart=true 允许自然结束后重新播放。
	if current_music_path == path and not force_restart:
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



# 剧情结束后重新根据当前场景状态播放场景音乐。
# 不保存剧情开始前的BGM。
# 例如：
# Clinic/Spring/a.mp3
# -> Story/sad.mp3
# -> 剧情结束重新选择 Clinic/Spring 音乐。

func resume_scene_music():

	if current_place == "":
		return

	play_scene_music(current_place)



func stop_music():

	if fade_tween:
		fade_tween.kill()

	bgm_player.stop()

	current_music_path = ""
	current_music_mode = ""
	current_scene_folder = ""
