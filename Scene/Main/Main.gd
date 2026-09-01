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
@onready var story_treatment_backend_root: Node = $StoryTreatmentBackendRoot
@onready var story_scene_root: Node = $StorySceneRoot

# 开始菜单根节点
@onready var main_menu_layer: CanvasLayer = $MainMenuLayer

# 三个菜单按钮
@onready var new_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/NewGameButton
@onready var load_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/LoadGameButton
@onready var quit_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/QuitGameButton

# 读取存档弹窗
@onready var save_slot_popup: Panel = $MainMenuLayer/SaveSlotPopup
@onready var save_slot_1_button: Button = $MainMenuLayer/SaveSlotPopup/VBoxContainer/Slot1Button
@onready var save_slot_2_button: Button = $MainMenuLayer/SaveSlotPopup/VBoxContainer/Slot2Button
@onready var save_slot_3_button: Button = $MainMenuLayer/SaveSlotPopup/VBoxContainer/Slot3Button
@onready var save_slot_close_button: Button = $MainMenuLayer/SaveSlotPopup/VBoxContainer/CloseButton


# 预加载场景
const CLINIC_SCENE: PackedScene = preload("res://Scene/clinic/clinic.tscn")
const NIGHT_SCENE: PackedScene = preload("res://Scene/Night/Night.tscn")
const STORY_SCENE: PackedScene = preload("res://Scene/Story/Story.tscn")
const MAP_SCENE_PATH: String = "res://Scene/Map/Map.tscn"


# 当前子场景实例
var current_scene: Node = null
var current_story_scene: Node = null
var story_treatment_backend: Node = null

# 剧情结束后要回到的目标。
# 使用逻辑名，不使用场景路径，避免 Story 直接替换 Main。
var pending_story_return_target: String = ""

# 本次剧情是否暂停了 Clinic 计时
var story_paused_clinic_clock: bool = false

# 存档槽弹窗模式：
# "load" = 读取存档
# "new_game" = 新游戏选择槽位
var save_slot_popup_mode: String = "load"

# 新游戏覆盖已有存档时使用的确认框。
# 这里用代码动态创建 ConfirmationDialog，不需要额外修改 Main.tscn。
var overwrite_confirm_dialog: ConfirmationDialog = null
var pending_overwrite_slot_index: int = -1


func _ready() -> void:
	# 创建覆盖存档确认框
	_setup_overwrite_confirm_dialog()

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

	if not save_slot_1_button.pressed.is_connected(_on_save_slot_1_button_pressed):
		save_slot_1_button.pressed.connect(_on_save_slot_1_button_pressed)

	if not save_slot_2_button.pressed.is_connected(_on_save_slot_2_button_pressed):
		save_slot_2_button.pressed.connect(_on_save_slot_2_button_pressed)

	if not save_slot_3_button.pressed.is_connected(_on_save_slot_3_button_pressed):
		save_slot_3_button.pressed.connect(_on_save_slot_3_button_pressed)

	if not save_slot_close_button.pressed.is_connected(_on_save_slot_close_button_pressed):
		save_slot_close_button.pressed.connect(_on_save_slot_close_button_pressed)


# =========================================================
# 显示开始菜单
# =========================================================
func _show_main_menu() -> void:
	_clear_story_overlay()
	_clear_current_scene()
	main_menu_layer.visible = true
	_close_save_slot_popup()
	_close_overwrite_confirm_dialog()

	# 读取游戏按钮始终可点击，点击后在弹窗中显示三个槽位。
	load_game_button.disabled = false


# =========================================================
# 隐藏开始菜单
# =========================================================
func _hide_main_menu() -> void:
	main_menu_layer.visible = false
	_close_save_slot_popup()
	_close_overwrite_confirm_dialog()


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
	_open_new_game_slot_popup()


# =========================================================
# 读取存档按钮
# 规则：
# 1. 没有存档则不处理
# 2. 有存档则读取
# 3. 根据存档里的 day / night 进入对应场景
# =========================================================
func _on_load_game_button_pressed() -> void:
	_open_load_game_slot_popup()


# =========================================================
# 读取存档弹窗
# =========================================================
func _open_load_game_slot_popup() -> void:
	save_slot_popup_mode = "load"
	_refresh_save_slot_popup()
	save_slot_popup.visible = true


func _open_new_game_slot_popup() -> void:
	save_slot_popup_mode = "new_game"
	_refresh_save_slot_popup()
	save_slot_popup.visible = true


func _close_save_slot_popup() -> void:
	if save_slot_popup != null:
		save_slot_popup.visible = false


func _on_save_slot_close_button_pressed() -> void:
	_close_save_slot_popup()


func _on_save_slot_1_button_pressed() -> void:
	_on_save_slot_button_pressed(1)


func _on_save_slot_2_button_pressed() -> void:
	_on_save_slot_button_pressed(2)


func _on_save_slot_3_button_pressed() -> void:
	_on_save_slot_button_pressed(3)


func _on_save_slot_button_pressed(slot_index: int) -> void:
	if save_slot_popup_mode == "load":
		_load_game_from_slot(slot_index)
		return

	if save_slot_popup_mode == "new_game":
		_start_new_game_in_slot(slot_index)
		return

	print("未知存档槽弹窗模式：", save_slot_popup_mode)


func _refresh_save_slot_popup() -> void:
	var buttons: Array[Button] = [
		save_slot_1_button,
		save_slot_2_button,
		save_slot_3_button
	]

	for i in range(buttons.size()):
		var slot_index: int = i + 1
		var button: Button = buttons[i]
		var meta: Dictionary = SaveManager.get_save_meta(slot_index)

		var exists: bool = bool(meta.get("exists", false))
		var display_name: String = String(meta.get("display_name", "空存档"))
		var save_time: String = String(meta.get("save_time", ""))

		if save_slot_popup_mode == "load":
			if exists:
				button.text = "读取槽位 %d\n%s\n%s" % [
					slot_index,
					display_name,
					save_time
				]
				button.disabled = false
			else:
				button.text = "读取槽位 %d\n空存档" % slot_index
				button.disabled = true

		elif save_slot_popup_mode == "new_game":
			if exists:
				button.text = "新游戏槽位 %d\n覆盖：%s\n%s" % [
					slot_index,
					display_name,
					save_time
				]
			else:
				button.text = "新游戏槽位 %d\n空存档" % slot_index

			# 新游戏模式下，空槽位也必须可以点击，用于创建新存档。
			button.disabled = false


func _load_game_from_slot(slot_index: int) -> void:
	if not SaveManager.has_save(slot_index):
		print("没有存档，无法读取：槽位 %d" % slot_index)
		_refresh_save_slot_popup()
		return

	var load_success: bool = SaveManager.load_game(slot_index)
	if not load_success:
		print("读取存档失败：槽位 %d" % slot_index)
		_refresh_save_slot_popup()
		return

	_hide_main_menu()

	if GameTime.is_day():
		_enter_clinic()
	else:
		_enter_night()




func _start_new_game_in_slot(slot_index: int) -> void:
	if not SaveManager.is_valid_slot(slot_index):
		print("新游戏失败：无效槽位 %d" % slot_index)
		return

	# 如果该槽位已有存档，先弹出确认框，避免误覆盖。
	if SaveManager.has_save(slot_index):
		_open_overwrite_confirm_dialog(slot_index)
		return

	_start_new_game_in_slot_without_confirm(slot_index)


func _start_new_game_in_slot_without_confirm(slot_index: int) -> void:
	if not SaveManager.is_valid_slot(slot_index):
		print("新游戏失败：无效槽位 %d" % slot_index)
		return

	SaveManager.current_slot_index = slot_index

	GameTime.start_new_game()
	Unlock.reset_progress()

	# 新游戏必须清空剧情播放记录。
	# 否则如果从旧流程回到主菜单再点新游戏，
	# StoryManager 内存里可能还残留 played_story_ids。
	StoryManager.load_save_data({})

	# SaveManager 会用临时文件安全替换旧存档。
	# 不要提前删除旧档；新档写入失败时，玩家仍然可以读取原存档。
	var save_success: bool = SaveManager.save_game(slot_index)
	if not save_success:
		push_warning("新游戏存档写入失败，已保留槽位 %d 的原存档。" % slot_index)
		save_slot_popup_mode = "new_game"
		_refresh_save_slot_popup()
		save_slot_popup.visible = true
		return

	_hide_main_menu()
	_enter_clinic()

	print("新游戏开始：槽位 %d" % slot_index)


# =========================================================
# 覆盖已有存档确认框
# =========================================================
func _setup_overwrite_confirm_dialog() -> void:
	if overwrite_confirm_dialog != null:
		return

	overwrite_confirm_dialog = ConfirmationDialog.new()
	overwrite_confirm_dialog.title = "确认覆盖"
	overwrite_confirm_dialog.dialog_text = "该槽位已有存档，是否覆盖？"
	overwrite_confirm_dialog.visible = false

	add_child(overwrite_confirm_dialog)

	if overwrite_confirm_dialog.get_ok_button() != null:
		overwrite_confirm_dialog.get_ok_button().text = "确认覆盖"

	if overwrite_confirm_dialog.get_cancel_button() != null:
		overwrite_confirm_dialog.get_cancel_button().text = "取消"

	if not overwrite_confirm_dialog.confirmed.is_connected(_on_overwrite_confirm_dialog_confirmed):
		overwrite_confirm_dialog.confirmed.connect(_on_overwrite_confirm_dialog_confirmed)

	if overwrite_confirm_dialog.has_signal("canceled"):
		if not overwrite_confirm_dialog.canceled.is_connected(_on_overwrite_confirm_dialog_canceled):
			overwrite_confirm_dialog.canceled.connect(_on_overwrite_confirm_dialog_canceled)

	if overwrite_confirm_dialog.has_signal("close_requested"):
		if not overwrite_confirm_dialog.close_requested.is_connected(_on_overwrite_confirm_dialog_canceled):
			overwrite_confirm_dialog.close_requested.connect(_on_overwrite_confirm_dialog_canceled)


func _open_overwrite_confirm_dialog(slot_index: int) -> void:
	if not SaveManager.is_valid_slot(slot_index):
		print("打开覆盖确认失败：无效槽位 %d" % slot_index)
		return

	_close_save_slot_popup()

	pending_overwrite_slot_index = slot_index

	var meta: Dictionary = SaveManager.get_save_meta(slot_index)
	var display_name: String = String(meta.get("display_name", "该存档"))
	var save_time: String = String(meta.get("save_time", ""))

	if save_time.is_empty():
		overwrite_confirm_dialog.dialog_text = "槽位 %d 已有存档：\n%s\n是否覆盖？" % [
			slot_index,
			display_name
		]
	else:
		overwrite_confirm_dialog.dialog_text = "槽位 %d 已有存档：\n%s\n%s\n是否覆盖？" % [
			slot_index,
			display_name,
			save_time
		]

	overwrite_confirm_dialog.popup_centered()


func _close_overwrite_confirm_dialog() -> void:
	if overwrite_confirm_dialog != null:
		overwrite_confirm_dialog.hide()

	pending_overwrite_slot_index = -1


func _on_overwrite_confirm_dialog_confirmed() -> void:
	var slot_index: int = pending_overwrite_slot_index

	_close_overwrite_confirm_dialog()

	if not SaveManager.is_valid_slot(slot_index):
		print("覆盖失败：无效槽位 %d" % slot_index)
		return

	_start_new_game_in_slot_without_confirm(slot_index)


func _on_overwrite_confirm_dialog_canceled() -> void:
	_close_overwrite_confirm_dialog()

	# 取消覆盖后回到新游戏槽位选择界面。
	save_slot_popup_mode = "new_game"
	_refresh_save_slot_popup()
	save_slot_popup.visible = true

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

	# 连接夜晚剧情请求信号。
	# 注意：必须在 start_night() 之前连接，否则 Night 进入夜晚时自动剧情信号会丢失。
	if current_scene.has_signal("story_requested"):
		if not current_scene.is_connected("story_requested", Callable(self, "_on_story_requested")):
			current_scene.connect("story_requested", Callable(self, "_on_story_requested"))
			print("Main 已连接 Night story_requested 信号")
	else:
		print("current_scene 没有 story_requested 信号")

	# 启动夜晚入口逻辑，包括自动检查 trigger_scene = "night" 的剧情。
	if current_scene.has_method("start_night"):
		current_scene.call("start_night", GameTime.current_day)
	else:
		print("Night 没有 start_night 方法")

	print("已进入 Night 场景，第 %d 天" % GameTime.current_day)


# =========================================================
# 进入 Map（为后续地图场景预留）
# =========================================================
func _enter_map() -> void:
	if not ResourceLoader.exists(MAP_SCENE_PATH):
		push_warning("未找到地图场景：%s，暂时回到 Clinic。" % MAP_SCENE_PATH)
		_enter_clinic()
		return

	var packed_map := load(MAP_SCENE_PATH) as PackedScene
	if packed_map == null:
		push_warning("地图场景加载失败：%s，暂时回到 Clinic。" % MAP_SCENE_PATH)
		_enter_clinic()
		return

	_clear_current_scene()
	current_scene = packed_map.instantiate()
	current_scene_root.add_child(current_scene)

	if current_scene.has_signal("story_requested"):
		var story_callable := Callable(self, "_on_story_requested")
		if not current_scene.is_connected("story_requested", story_callable):
			current_scene.connect("story_requested", story_callable)

	if current_scene.has_method("start_map"):
		current_scene.call("start_map", GameTime.current_day)


# =========================================================
# Clinic 请求播放剧情
# =========================================================
func _on_story_requested(story_path: String, return_target: String = "") -> void:
	# Main 不再根据剧情路径判断是否重复播放。
	# 是否能播放，统一交给 StoryData.story_id + StoryManager 判断。
	# return_target 只保留为旧信号兼容参数；实际返回目标读取 StoryData.return_scene。
	_play_story(story_path, return_target)


func _play_story(story_path: String, _legacy_return_target: String = "") -> void:
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

	# 返回目标由当前正在播放的 StoryData 决定。
	pending_story_return_target = story_data.return_scene
	if pending_story_return_target.is_empty():
		pending_story_return_target = story_data.trigger_scene
	if pending_story_return_target.is_empty():
		pending_story_return_target = "clinic"

	story_paused_clinic_clock = false

	# 进入剧情前暂停 Clinic 计时。
	# 注意：这里是暂停，不是 stop_clinic_clock()，所以不会清空当前时辰和累计秒数。
	if GameTime != null and GameTime.has_method("pause_clinic_clock_for_story"):
		story_paused_clinic_clock = GameTime.pause_clinic_clock_for_story()

	# 只暂存剧情数据，不让 StoryManager 自己切换场景。
	# 此时不记录已播放；只有剧情真正结束后才会写入 played_story_ids。
	var story_set_success: bool = StoryManager.set_story(story_data)

	if not story_set_success:
		push_warning("剧情设置失败：" + story_path)
		pending_story_return_target = ""
		if story_paused_clinic_clock:
			if GameTime != null and GameTime.has_method("resume_clinic_clock_after_story"):
				GameTime.resume_clinic_clock_after_story()
			story_paused_clinic_clock = false
		return

	_save_game_with_warning("进入剧情前")

	# Clinic / Night 即将被隐藏。先取得它当前实际显示的季节背景，
	# 再注入 Story；Texture2D 资源引用不会因为来源场景隐藏而失效。
	var current_background_texture := _get_current_scene_background_texture()

	# 剧情作为覆盖层播放。原 Clinic / Night / Map 实例暂时隐藏，
	# 这样 Story 中打开诊疗窗口时，画面始终停留在 Story 场景。
	_set_scene_visible(current_scene, false)
	_clear_story_overlay()

	current_story_scene = STORY_SCENE.instantiate()
	# 必须在 add_child() 前注入背景：Story._ready() 会在进入场景树时立即播放剧情。
	if current_story_scene.has_method("set_current_scene_background_texture"):
		current_story_scene.call(
			"set_current_scene_background_texture",
			current_background_texture
		)
	elif current_background_texture != null:
		push_warning("Story 缺少 set_current_scene_background_texture()，无法使用当前场景背景。")
	_connect_story_scene_signals(current_story_scene)
	story_scene_root.add_child(current_story_scene)

	print("Main 播放剧情：", story_path)


func _connect_story_scene_signals(story_node: Node) -> void:
	if story_node == null:
		return

	var playback_completed_callable := Callable(self, "_on_story_playback_completed")
	if story_node.has_signal("story_playback_completed"):
		if not story_node.is_connected("story_playback_completed", playback_completed_callable):
			story_node.connect("story_playback_completed", playback_completed_callable)

	var finished_callable := Callable(self, "_on_story_finished")
	if story_node.has_signal("story_finished"):
		if not story_node.is_connected("story_finished", finished_callable):
			story_node.connect("story_finished", finished_callable)

	var treatment_callable := Callable(self, "_on_story_treatment_requested")
	if story_node.has_signal("story_treatment_requested"):
		if not story_node.is_connected("story_treatment_requested", treatment_callable):
			story_node.connect("story_treatment_requested", treatment_callable)

	var followup_callable := Callable(self, "_on_followup_story_requested")
	if story_node.has_signal("followup_story_requested"):
		if not story_node.is_connected("followup_story_requested", followup_callable):
			story_node.connect("followup_story_requested", followup_callable)

	var game_over_callable := Callable(self, "_on_story_game_over_requested")
	if story_node.has_signal("game_over_requested"):
		if not story_node.is_connected("game_over_requested", game_over_callable):
			story_node.connect("game_over_requested", game_over_callable)


func _on_story_playback_completed(completed_story: StoryData) -> void:
	# Story 只会在每段剧情台词真正播放完（或玩家跳过到结尾）时上报一次。
	# 治疗判定阶段不经过这里，因此 story NPC 的奖励与惩罚不会提前结算。
	if completed_story == null:
		return

	if StoryManager == null or not StoryManager.has_method("apply_story_point_changes"):
		push_warning("StoryManager 缺少 apply_story_point_changes()，无法结算剧情名望与心得。")
		return

	var raw_result = StoryManager.apply_story_point_changes(completed_story)
	if typeof(raw_result) != TYPE_DICTIONARY:
		push_warning("StoryManager.apply_story_point_changes() 返回了无效结果。")
		return

	var point_change_result: Dictionary = raw_result
	var reputation_change := int(point_change_result.get("reputation_change", 0))
	var experience_change := int(point_change_result.get("experience_change", 0))
	if reputation_change == 0 and experience_change == 0:
		return

	# Game Over 剧情保持原有规则：只改变当前内存状态，不覆盖最后一个可读取存档点。
	var trigger_type := completed_story.trigger_type.strip_edges().to_lower()
	if trigger_type == StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_OVER:
		return

	_save_game_with_warning("剧情播放完成并结算名望与心得")


func _on_story_treatment_requested(npc_id: String, disease: DiseaseData) -> void:
	_clear_story_treatment_backend()

	story_treatment_backend = CLINIC_SCENE.instantiate()
	story_treatment_backend.set("story_treatment_backend_mode", true)
	story_treatment_backend_root.add_child(story_treatment_backend)

	if not story_treatment_backend.has_method("prepare_story_npc_treatment"):
		_cancel_story_treatment("Clinic 缺少 prepare_story_npc_treatment()。")
		return

	var prepared: bool = bool(story_treatment_backend.call(
		"prepare_story_npc_treatment",
		npc_id,
		disease,
		GameTime.current_day
	))
	if not prepared:
		_cancel_story_treatment("story NPC 诊疗后端准备失败：%s" % npc_id)
		return

	if current_story_scene != null and current_story_scene.has_method("start_story_npc_treatment"):
		current_story_scene.call(
			"start_story_npc_treatment",
			story_treatment_backend,
			npc_id
		)
	else:
		_cancel_story_treatment("Story 缺少 start_story_npc_treatment()。")


func _cancel_story_treatment(message: String) -> void:
	push_warning(message)
	if current_story_scene != null and current_story_scene.has_method("cancel_story_treatment"):
		current_story_scene.call("cancel_story_treatment", message)
	else:
		_on_story_finished()


func _on_followup_story_requested(
	next_story: StoryData,
	resume_treatment: bool
) -> void:
	if next_story == null:
		return

	# 不需要恢复诊疗的后续剧情，结束后按它自己的 return_scene 返回。
	# story_npc_failed_over 会在剧情结束时发送独立的 Game Over 信号。
	if not resume_treatment:
		var next_return_target := next_story.return_scene.strip_edges()
		if next_return_target != "":
			pending_story_return_target = next_return_target

	# 收到后续剧情请求，说明上一段剧情已经完整播放完毕。
	# 先记录上一段，再把 current_story 切换成下一段。
	StoryManager.mark_current_story_played()

	if not StoryManager.set_story(next_story):
		push_warning("后续剧情设置失败：%s" % next_story.story_id)
		if resume_treatment and current_story_scene != null:
			current_story_scene.call("play_followup_story", next_story, true)
		return

	var is_game_over_story := (
		next_story.trigger_type.strip_edges().to_lower()
		== StoryData.TRIGGER_TYPE_STORY_NPC_FAILED_OVER
	)

	# Game Over 不覆盖玩家最后一个可读取的存档点。
	if not is_game_over_story:
		_save_game_with_warning("切换后续剧情")

	if current_story_scene != null and current_story_scene.has_method("play_followup_story"):
		current_story_scene.call(
			"play_followup_story",
			next_story,
			resume_treatment
		)


func _on_story_game_over_requested() -> void:
	# Game Over 剧情已经完整播放，但不保存到磁盘，保留玩家最后一个可读取的存档点。
	StoryManager.mark_current_story_played()
	StoryManager.clear_story()
	pending_story_return_target = ""

	if story_paused_clinic_clock:
		if GameTime != null and GameTime.has_method("cancel_story_pause_state"):
			GameTime.cancel_story_pause_state()
	story_paused_clinic_clock = false

	# 当前项目没有独立 GameOver 场景；结束本局后回到开始菜单。
	# 原存档保留，玩家仍可从最后一个保存点读取。
	_show_main_menu()


func _on_story_finished() -> void:
	# 只有走到正式结束信号，才把当前剧情记为已播放并保存。
	StoryManager.mark_current_story_played()
	StoryManager.clear_story()

	var target := pending_story_return_target
	pending_story_return_target = ""
	_clear_story_overlay()

	if target == "night":
		# 如果剧情是从 Clinic 白天触发，但剧情结束后直接进入 Night，
		# 就不要恢复 Clinic 计时，而是正常结束白天。
		if story_paused_clinic_clock:
			if GameTime != null and GameTime.has_method("cancel_story_pause_state"):
				GameTime.cancel_story_pause_state()

			if GameTime != null and GameTime.is_day():
				GameTime.finish_day()

		story_paused_clinic_clock = false
		_save_game_with_warning("剧情结束并进入夜晚")
		_enter_night()
		return

	story_paused_clinic_clock = false

	if target == "clinic":
		# return_scene 决定剧情结束后的目标场景。
		# 如果当前处于 Night，进入 Clinic 前先正常结束夜晚并推进到下一天；
		# 如果本来就在白天，则保留剧情暂停状态，由新 Clinic 恢复计时。
		if GameTime != null and not GameTime.is_day():
			GameTime.finish_night()
			_save_game_with_warning("剧情结束并进入下一天诊室")
		else:
			_save_game_with_warning("剧情结束并返回诊室")

		_enter_clinic()
		return

	_save_game_with_warning("剧情结束")

	if target == "map":
		_enter_map()
		return

	# 兜底：未知返回目标默认回 Clinic。
	_enter_clinic()


# =========================================================
# Clinic 当天结束
# 白天结束：
# 第 1 天 白天 → 第 1 天 黑夜
# 不增加天数
# =========================================================
func _on_clinic_finished() -> void:
	GameTime.finish_day()
	_save_game_with_warning("白天结束")

	print("Clinic 已结束，切换到 Night 场景")
	_enter_night()


# =========================================================
# Night 结束，进入下一天
# 黑夜结束：
# 第 1 天 黑夜 → 第 2 天 白天
# 天数 +1
# =========================================================
func _on_night_finished() -> void:
	# 玩家点击“休息，进入明天”后，先检查当前天是否存在夜晚结束剧情。
	# 此时还没有调用 finish_night()，所以 trigger_day 对应的是“正在结束的这一天”。
	var night_end_story: StoryData = StoryManager.find_night_end_story(GameTime.current_day)

	if night_end_story != null:
		# night_end 只决定这段剧情在点击“休息”时触发。
		# 剧情结束后前往哪个场景，统一由 StoryData.return_scene 决定。
		_play_story(night_end_story.resource_path)

		# 剧情资源加载或设置失败时不能卡在 Night，直接按原流程进入下一天。
		if current_story_scene == null:
			_finish_night_and_enter_next_day()
		return

	_finish_night_and_enter_next_day()


func _finish_night_and_enter_next_day() -> void:
	GameTime.finish_night()
	_save_game_with_warning("夜晚结束")

	print("夜晚结束，进入第 %d 天" % GameTime.current_day)
	_enter_clinic()


func _save_game_with_warning(context: String) -> bool:
	var save_success: bool = SaveManager.save_game()
	if not save_success:
		push_warning("%s：自动存档失败。" % context)

	return save_success


# =========================================================
# 清理旧子场景
# =========================================================
func _clear_current_scene() -> void:
	if current_scene != null and is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null


func _set_scene_visible(scene_node: Node, should_be_visible: bool) -> void:
	if scene_node == null or not is_instance_valid(scene_node):
		return

	if scene_node is CanvasItem:
		(scene_node as CanvasItem).visible = should_be_visible


func _get_current_scene_background_texture() -> Texture2D:
	# Clinic / Night 通过统一接口返回已经按当前天数切换完成的实际背景。
	# Map 等其他场景以后也可以实现同名方法，无需继续修改 Main。
	if current_scene == null or not is_instance_valid(current_scene):
		return null

	if not current_scene.has_method("get_current_background_texture"):
		return null

	var raw_texture = current_scene.call("get_current_background_texture")
	if raw_texture is Texture2D:
		return raw_texture as Texture2D

	return null


func _clear_story_treatment_backend() -> void:
	if story_treatment_backend != null and is_instance_valid(story_treatment_backend):
		story_treatment_backend.queue_free()
	story_treatment_backend = null


func _clear_story_overlay() -> void:
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false

	if current_story_scene != null and is_instance_valid(current_story_scene):
		current_story_scene.queue_free()
	current_story_scene = null

	_clear_story_treatment_backend()
