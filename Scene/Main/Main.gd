extends Node
class_name Main

# =========================================================
# Main
# 负责：
# 1. 显示开始菜单
# 2. 新游戏
# 3. 读取存档
# 4. 退出游戏
# 5. 在 Clinic 和 Night 之间切换
# 6. 白天/黑夜结束时自动存档
# =========================================================


# 子场景挂载点
@onready var current_scene_root: Node = $CurrentSceneRoot

# 开始菜单根节点
@onready var main_menu_layer: CanvasLayer = $MainMenuLayer

# 三个菜单按钮
@onready var new_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/NewGameButton
@onready var load_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/LoadGameButton
@onready var quit_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/QuitGameButton


# 预加载场景
const CLINIC_SCENE: PackedScene = preload("res://Scene/Clinic/Clinic.tscn")
const NIGHT_SCENE: PackedScene = preload("res://Scene/Night/Night.tscn")
const STORY_SCENE: PackedScene = preload("res://Scene/Story/Story.tscn")


# 当前子场景实例
var current_scene: Node = null

# 剧情结束后要回到的目标。
# 使用逻辑名，不使用场景路径，避免 Story 直接替换 Main。
var pending_story_return_target: String = ""

# 本次剧情是否暂停了 Clinic 计时
var story_paused_clinic_clock: bool = false


func _ready() -> void:
	# 连接开始菜单按钮
	_connect_menu_buttons()

	# 进入游戏时先显示菜单，不直接进入诊室
	_show_main_menu()

	print("Main 初始化完成，等待玩家选择")


# =========================================================
# 连接菜单按钮
# =========================================================
func _connect_menu_buttons() -> void:
	if not new_game_button.pressed.is_connected(_on_new_game_button_pressed):
		new_game_button.pressed.connect(_on_new_game_button_pressed)

	if not load_game_button.pressed.is_connected(_on_load_game_button_pressed):
		load_game_button.pressed.connect(_on_load_game_button_pressed)

	if not quit_game_button.pressed.is_connected(_on_quit_game_button_pressed):
		quit_game_button.pressed.connect(_on_quit_game_button_pressed)


# =========================================================
# 显示开始菜单
# =========================================================
func _show_main_menu() -> void:
	_clear_current_scene()
	main_menu_layer.visible = true

	# 没有存档时，读取按钮禁用
	load_game_button.disabled = not SaveManager.has_save()


# =========================================================
# 隐藏开始菜单
# =========================================================
func _hide_main_menu() -> void:
	main_menu_layer.visible = false


# =========================================================
# 新游戏按钮
# 规则：
# 1. 删除旧存档
# 2. 重置时间
# 3. 重置解锁进度
# 4. 创建新存档
# 5. 进入第 1 天白天诊室
# =========================================================
func _on_new_game_button_pressed() -> void:
	SaveManager.delete_save()

	GameTime.start_new_game()
	Unlock.reset_progress()

	# 新游戏必须清空剧情播放记录。
	# 否则如果从旧流程回到主菜单再点新游戏，
	# StoryManager 内存里可能还残留 played_story_ids。
	StoryManager.load_save_data({})

	SaveManager.save_game()

	_hide_main_menu()
	_enter_clinic()


# =========================================================
# 读取存档按钮
# 规则：
# 1. 没有存档则不处理
# 2. 有存档则读取
# 3. 根据存档里的 day / night 进入对应场景
# =========================================================
func _on_load_game_button_pressed() -> void:
	if not SaveManager.has_save():
		print("没有存档，无法读取")
		return

	var load_success: bool = SaveManager.load_game()
	if not load_success:
		print("读取存档失败")
		return

	_hide_main_menu()

	if GameTime.is_day():
		_enter_clinic()
	else:
		_enter_night()


# =========================================================
# 退出游戏按钮
# =========================================================
func _on_quit_game_button_pressed() -> void:
	get_tree().quit()


# =========================================================
# 进入 Clinic
# =========================================================
func _enter_clinic() -> void:
	_clear_current_scene()

	# 实例化诊室场景
	current_scene = CLINIC_SCENE.instantiate()
	current_scene_root.add_child(current_scene)

	# 连接 clinic_finished 信号
	if current_scene.has_signal("clinic_finished"):
		if not current_scene.is_connected("clinic_finished", Callable(self, "_on_clinic_finished")):
			current_scene.connect("clinic_finished", Callable(self, "_on_clinic_finished"))
			print("Main 已连接 clinic_finished 信号")
	else:
		print("current_scene 没有 clinic_finished 信号")

	# 连接剧情请求信号。
	# 注意：必须在 start_new_day() 之前连接，否则 Clinic 进入当天自动剧情时信号会丢失。
	if current_scene.has_signal("story_requested"):
		if not current_scene.is_connected("story_requested", Callable(self, "_on_story_requested")):
			current_scene.connect("story_requested", Callable(self, "_on_story_requested"))
			print("Main 已连接 story_requested 信号")
	else:
		print("current_scene 没有 story_requested 信号")

	# 刷新左上角天数显示
	if current_scene.has_method("set_day"):
		current_scene.call("set_day", GameTime.current_day)
		print("已刷新诊室天数：", GameTime.current_day)
	else:
		print("Clinic 没有 set_day 方法")

	# 开始新的一天逻辑
	if current_scene.has_method("start_new_day"):
		current_scene.call("start_new_day", GameTime.current_day)

	print("已进入 Clinic 场景，第 %d 天" % GameTime.current_day)


# =========================================================
# 进入 Night
# =========================================================
func _enter_night() -> void:
	_clear_current_scene()

	# 实例化夜晚主场景
	current_scene = NIGHT_SCENE.instantiate()
	current_scene_root.add_child(current_scene)

	# 连接 night_finished 信号
	if current_scene.has_signal("night_finished"):
		if not current_scene.is_connected("night_finished", Callable(self, "_on_night_finished")):
			current_scene.connect("night_finished", Callable(self, "_on_night_finished"))
			print("Main 已连接 night_finished 信号")
	else:
		print("current_scene 没有 night_finished 信号")

	print("已进入 Night 场景，第 %d 天" % GameTime.current_day)


# =========================================================
# Clinic 请求播放剧情
# =========================================================
func _on_story_requested(story_path: String, return_target: String) -> void:
	# Main 不再根据剧情路径判断是否重复播放。
	# 是否能播放，统一交给 StoryData.story_id + StoryManager 判断。
	_play_story(story_path, return_target)


func _play_story(story_path: String, return_target: String) -> void:
	if story_path.is_empty():
		push_warning("剧情路径为空")
		return

	var loaded_story := load(story_path)
	if loaded_story == null:
		push_warning("剧情文件加载失败：" + story_path)
		return

	if not loaded_story is StoryData:
		push_warning("文件不是 StoryData：" + story_path)
		return

	var story_data: StoryData = loaded_story as StoryData

	# 读取剧情 ID。
	# 以后无论剧情文件路径怎么改，只要 story_id 不变，
	# 重复播放判断都不会失效。
	var story_id: String = story_data.story_id

	# 读取是否只播放一次。
	var play_once: bool = story_data.play_once

	# 一次性剧情如果已经播放过，就不再进入 Story 场景。
	if play_once and StoryManager.has_played_story(story_id):
		print("剧情已播放，跳过：", story_id)
		return

	pending_story_return_target = return_target
	story_paused_clinic_clock = false

	# 进入剧情前暂停 Clinic 计时。
	# 注意：这里是暂停，不是 stop_clinic_clock()，所以不会清空当前时辰和累计秒数。
	if GameTime != null and GameTime.has_method("pause_clinic_clock_for_story"):
		story_paused_clinic_clock = GameTime.pause_clinic_clock_for_story()

	# 只暂存剧情数据，不让 StoryManager 自己切换场景。
	# set_story() 内部会把 story_id 记录到 played_story_ids。
	var story_set_success: bool = StoryManager.set_story(story_data)

	if not story_set_success:
		push_warning("剧情设置失败：" + story_path)
		pending_story_return_target = ""
		if story_paused_clinic_clock:
			if GameTime != null and GameTime.has_method("resume_clinic_clock_after_story"):
				GameTime.resume_clinic_clock_after_story()
			story_paused_clinic_clock = false
		return

	SaveManager.save_game()

	_clear_current_scene()

	current_scene = STORY_SCENE.instantiate()
	current_scene_root.add_child(current_scene)

	if current_scene.has_signal("story_finished"):
		if not current_scene.is_connected("story_finished", Callable(self, "_on_story_finished")):
			current_scene.connect("story_finished", Callable(self, "_on_story_finished"))
	else:
		print("current_scene 没有 story_finished 信号")

	print("Main 播放剧情：", story_path)


func _on_story_finished() -> void:
	StoryManager.clear_story()

	var target := pending_story_return_target
	pending_story_return_target = ""

	if target == "night":
		# 如果剧情是从 Clinic 白天触发，但剧情结束后直接进入 Night，
		# 就不要恢复 Clinic 计时，而是正常结束白天。
		if story_paused_clinic_clock:
			if GameTime != null and GameTime.has_method("cancel_story_pause_state"):
				GameTime.cancel_story_pause_state()

			if GameTime != null and GameTime.is_day():
				GameTime.finish_day()
				SaveManager.save_game()

		story_paused_clinic_clock = false
		_enter_night()
		return

	if target == "clinic":
		# 回 Clinic 时不在 Main 里直接 resume。
		# 因为 _enter_clinic() 会实例化 Clinic，
		# Clinic._ready() 会调用 GameTime.start_clinic_time()，
		# 而 start_clinic_time() 已经会识别剧情暂停状态并恢复计时。
		story_paused_clinic_clock = false
		_enter_clinic()
		return

	# 兜底：未知 return_target 默认回 Clinic。
	story_paused_clinic_clock = false
	_enter_clinic()


# =========================================================
# Clinic 当天结束
# 白天结束：
# 第 1 天 白天 → 第 1 天 黑夜
# 不增加天数
# =========================================================
func _on_clinic_finished() -> void:
	GameTime.finish_day()
	SaveManager.save_game()

	print("Clinic 已结束，切换到 Night 场景")
	_enter_night()


# =========================================================
# Night 结束，进入下一天
# 黑夜结束：
# 第 1 天 黑夜 → 第 2 天 白天
# 天数 +1
# =========================================================
func _on_night_finished() -> void:
	GameTime.finish_night()
	SaveManager.save_game()

	print("夜晚结束，进入第 %d 天" % GameTime.current_day)
	_enter_clinic()


# =========================================================
# 清理旧子场景
# =========================================================
func _clear_current_scene() -> void:
	if current_scene != null and is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
