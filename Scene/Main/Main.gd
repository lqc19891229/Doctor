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

# 游戏内暂停菜单 / 设置菜单
@onready var pause_menu_layer: CanvasLayer = $PauseMenuLayer
@onready var settings_layer: CanvasLayer = $SettingsLayer

# 开始菜单按钮
@onready var new_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/NewGameButton
@onready var load_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/LoadGameButton
@onready var settings_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/SettingsButton
@onready var quit_game_button: Button = $MainMenuLayer/MenuPanel/VBoxContainer/QuitGameButton

# 读取存档弹窗
@onready var save_slot_popup: Panel = $MainMenuLayer/SaveSlotPopup
@onready var save_slot_1_button: Button = $MainMenuLayer/SaveSlotPopup/VBoxContainer/Slot1Button
@onready var save_slot_2_button: Button = $MainMenuLayer/SaveSlotPopup/VBoxContainer/Slot2Button
@onready var save_slot_3_button: Button = $MainMenuLayer/SaveSlotPopup/VBoxContainer/Slot3Button
@onready var save_slot_close_button: Button = $MainMenuLayer/SaveSlotPopup/VBoxContainer/CloseButton


# 预加载场景
const CLINIC_SCENE: PackedScene = preload("res://Scene/Clinic/Clinic.tscn")
const NIGHT_SCENE: PackedScene = preload("res://Scene/Night/Night.tscn")
const STORY_SCENE: PackedScene = preload("res://Scene/Story/Story.tscn")
const ENDING_CREDITS_SCENE: PackedScene = preload(
	"res://Scene/Ending/Ending_credits.tscn"
)
const STORY_TREATMENT_SERVICE_SCRIPT = preload("res://System/Treatment/StoryTreatmentService.gd")
const MAP_SCENE_PATH: String = "res://Scene/Map/Map.tscn"


# 当前子场景实例
var current_scene: Node = null
var current_story_scene: Node = null
var story_treatment_backend: Node = null

# Clinic / Night 改为常驻实例：每种场景整局最多实例化一次。
# 切换昼夜时只隐藏并禁用处理，不再 queue_free + instantiate。
var clinic_scene_instance: Node = null
var night_scene_instance: Node = null

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

# Pause Menu 中“返回主菜单 / 退出游戏”的确认框。
# 使用代码动态创建，避免再增加单独场景。
var return_to_menu_confirm_dialog: ConfirmationDialog = null
var quit_game_confirm_dialog: ConfirmationDialog = null


func _ready() -> void:
	# 创建确认框
	_setup_overwrite_confirm_dialog()
	_setup_pause_confirm_dialogs()

	# 连接开始菜单，以及 Pause / Settings 的信号。
	_connect_menu_buttons()
	_connect_overlay_menu_signals()

	# 初始状态不显示游戏内覆盖菜单。
	_hide_pause_menu_visual_only()
	_close_settings_menu(false)
	_set_pause_menu_input_enabled(true)

	# 进入游戏时先显示菜单，不直接进入诊室。
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

	if not settings_button.pressed.is_connected(_on_settings_button_pressed):
		settings_button.pressed.connect(_on_settings_button_pressed)

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
# 连接 Pause / Settings 信号
# =========================================================
func _connect_overlay_menu_signals() -> void:
	if pause_menu_layer != null:
		var pause_signal_map: Dictionary = {
			"toggle_requested": Callable(self, "_on_pause_toggle_requested"),
			"resume_requested": Callable(self, "_on_pause_resume_requested"),
			"settings_requested": Callable(self, "_on_pause_settings_requested"),
			"main_menu_requested": Callable(self, "_on_pause_main_menu_requested"),
			"quit_requested": Callable(self, "_on_pause_quit_requested")
		}

		for signal_name_value in pause_signal_map.keys():
			var signal_name := String(signal_name_value)
			var signal_callable: Callable = pause_signal_map[signal_name_value]
			if pause_menu_layer.has_signal(signal_name):
				if not pause_menu_layer.is_connected(signal_name, signal_callable):
					pause_menu_layer.connect(signal_name, signal_callable)

	if settings_layer != null and settings_layer.has_signal("closed"):
		var settings_closed_callable := Callable(self, "_on_settings_closed")
		if not settings_layer.is_connected("closed", settings_closed_callable):
			settings_layer.connect("closed", settings_closed_callable)


# =========================================================
# 显示开始菜单
# =========================================================
func _show_main_menu() -> void:
	# 标题菜单永远处于非暂停状态。
	var tree := get_tree()
	if tree != null:
		tree.paused = false

	# 回到主菜单时统一停止游戏场景的全局 BGM 与环境音，
	# 避免 Clinic / Night 音频继续在标题界面播放。
	if is_instance_valid(MusicManager):
		MusicManager.stop_music()

	if is_instance_valid(AmbientManager):
		AmbientManager.stop_ambient()

	_hide_pause_menu_visual_only()
	_close_settings_menu(false)
	_set_pause_menu_input_enabled(true)

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
# 1. 选择存档槽；若确认覆盖已有槽位，则先删除旧存档
# 2. 重置时间
# 3. 重置解锁进度
# 4. 不立即写盘，等待第一次昼夜阶段结束
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
# 设置按钮
# =========================================================
func _on_settings_button_pressed() -> void:
	_open_settings_menu()


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

			# 新游戏模式下，空槽位也必须可以点击，用于开始新游戏。
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

	# 新游戏本身不写盘。若玩家确认覆盖已有槽位，先清除旧档，
	# 后续只会在“白天结束进入 Night”或“Night 结束进入下一天”时生成新存档。
	if SaveManager.has_save(slot_index):
		var delete_success: bool = SaveManager.delete_save(slot_index)
		if not delete_success:
			push_warning("新游戏失败：无法清除槽位 %d 的旧存档。" % slot_index)
			save_slot_popup_mode = "new_game"
			_refresh_save_slot_popup()
			save_slot_popup.visible = true
			return

	SaveManager.current_slot_index = slot_index

	GameTime.start_new_game()
	Unlock.reset_progress()

	# 新游戏必须清空剧情播放记录。
	# 否则如果从旧流程回到主菜单再点新游戏，
	# StoryManager 内存里可能还残留 played_story_ids。
	StoryManager.load_save_data({})

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
	_quit_game_safely()


# =========================================================
# Pause Menu / Settings
# =========================================================
func _on_pause_toggle_requested() -> void:
	# Settings 自己处理 ESC；打开时 PauseMenu 不应再切换。
	if settings_layer != null and settings_layer.visible:
		return

	# 标题菜单阶段不打开 Pause Menu。
	# 如果当前正在选择存档，ESC 只负责关闭存档选择层。
	if main_menu_layer.visible:
		if save_slot_popup != null and save_slot_popup.visible:
			_close_save_slot_popup()
		return

	if pause_menu_layer.visible:
		_close_pause_menu()
	else:
		_open_pause_menu()


func _open_pause_menu() -> void:
	if main_menu_layer.visible:
		return

	if pause_menu_layer != null and pause_menu_layer.has_method("show_menu"):
		pause_menu_layer.call("show_menu")
	else:
		pause_menu_layer.visible = true

	var tree := get_tree()
	if tree != null:
		tree.paused = true


func _close_pause_menu() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false

	_hide_pause_menu_visual_only()
	_set_pause_menu_input_enabled(true)


func _hide_pause_menu_visual_only() -> void:
	if pause_menu_layer == null:
		return

	if pause_menu_layer.has_method("hide_menu"):
		pause_menu_layer.call("hide_menu")
	else:
		pause_menu_layer.visible = false


func _set_pause_menu_input_enabled(enabled: bool) -> void:
	if pause_menu_layer != null and pause_menu_layer.has_method("set_input_enabled"):
		pause_menu_layer.call("set_input_enabled", enabled)


func _on_pause_resume_requested() -> void:
	_close_pause_menu()


func _on_pause_settings_requested() -> void:
	_open_settings_menu()


func _open_settings_menu() -> void:
	if settings_layer == null:
		return

	# SettingsLayer 自己在暂停状态下也能运行。
	# 暂时禁用 PauseMenu 的 ESC 监听，避免两个覆盖层同时响应。
	_set_pause_menu_input_enabled(false)

	if settings_layer.has_method("open_panel"):
		settings_layer.call("open_panel")
	else:
		settings_layer.visible = true


func _close_settings_menu(emit_closed_signal: bool = true) -> void:
	if settings_layer == null:
		return

	if settings_layer.has_method("close_panel"):
		settings_layer.call("close_panel", emit_closed_signal)
	else:
		settings_layer.visible = false
		if emit_closed_signal and settings_layer.has_signal("closed"):
			settings_layer.emit_signal("closed")


func _on_settings_closed() -> void:
	_set_pause_menu_input_enabled(true)


func _on_pause_main_menu_requested() -> void:
	if return_to_menu_confirm_dialog == null:
		_return_to_main_menu_from_game()
		return

	_set_pause_menu_input_enabled(false)
	return_to_menu_confirm_dialog.popup_centered()


func _on_pause_quit_requested() -> void:
	if quit_game_confirm_dialog == null:
		_quit_game_safely()
		return

	_set_pause_menu_input_enabled(false)
	quit_game_confirm_dialog.popup_centered()


func _setup_pause_confirm_dialogs() -> void:
	if return_to_menu_confirm_dialog == null:
		return_to_menu_confirm_dialog = ConfirmationDialog.new()
		return_to_menu_confirm_dialog.title = "返回主菜单"
		return_to_menu_confirm_dialog.dialog_text = (
			"当前阶段尚未完成。\n"
			+ "返回主菜单后，将从最近一次自动存档继续。\n\n"
			+ "是否返回主菜单？"
		)
		return_to_menu_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(return_to_menu_confirm_dialog)

		if return_to_menu_confirm_dialog.get_ok_button() != null:
			return_to_menu_confirm_dialog.get_ok_button().text = "返回主菜单"
		if return_to_menu_confirm_dialog.get_cancel_button() != null:
			return_to_menu_confirm_dialog.get_cancel_button().text = "取消"

		var return_confirm_callable := Callable(self, "_on_return_to_menu_confirmed")
		if not return_to_menu_confirm_dialog.confirmed.is_connected(return_confirm_callable):
			return_to_menu_confirm_dialog.confirmed.connect(return_confirm_callable)

		var return_cancel_callable := Callable(self, "_on_pause_confirm_canceled")
		if return_to_menu_confirm_dialog.has_signal("canceled"):
			if not return_to_menu_confirm_dialog.canceled.is_connected(return_cancel_callable):
				return_to_menu_confirm_dialog.canceled.connect(return_cancel_callable)
		if return_to_menu_confirm_dialog.has_signal("close_requested"):
			if not return_to_menu_confirm_dialog.close_requested.is_connected(return_cancel_callable):
				return_to_menu_confirm_dialog.close_requested.connect(return_cancel_callable)

	if quit_game_confirm_dialog == null:
		quit_game_confirm_dialog = ConfirmationDialog.new()
		quit_game_confirm_dialog.title = "退出游戏"
		quit_game_confirm_dialog.dialog_text = (
			"当前阶段尚未完成。\n"
			+ "退出游戏后，本阶段未保存的进度将丢失。\n\n"
			+ "是否退出游戏？"
		)
		quit_game_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(quit_game_confirm_dialog)

		if quit_game_confirm_dialog.get_ok_button() != null:
			quit_game_confirm_dialog.get_ok_button().text = "退出游戏"
		if quit_game_confirm_dialog.get_cancel_button() != null:
			quit_game_confirm_dialog.get_cancel_button().text = "取消"

		var quit_confirm_callable := Callable(self, "_on_quit_game_confirmed")
		if not quit_game_confirm_dialog.confirmed.is_connected(quit_confirm_callable):
			quit_game_confirm_dialog.confirmed.connect(quit_confirm_callable)

		var quit_cancel_callable := Callable(self, "_on_pause_confirm_canceled")
		if quit_game_confirm_dialog.has_signal("canceled"):
			if not quit_game_confirm_dialog.canceled.is_connected(quit_cancel_callable):
				quit_game_confirm_dialog.canceled.connect(quit_cancel_callable)
		if quit_game_confirm_dialog.has_signal("close_requested"):
			if not quit_game_confirm_dialog.close_requested.is_connected(quit_cancel_callable):
				quit_game_confirm_dialog.close_requested.connect(quit_cancel_callable)


func _on_return_to_menu_confirmed() -> void:
	_return_to_main_menu_from_game()


func _on_quit_game_confirmed() -> void:
	_quit_game_safely()


func _on_pause_confirm_canceled() -> void:
	_set_pause_menu_input_enabled(true)


func _return_to_main_menu_from_game() -> void:
	# 先解除 SceneTree pause，保证标题菜单和后续输入恢复正常。
	var tree := get_tree()
	if tree != null:
		tree.paused = false

	_close_settings_menu(false)
	_hide_pause_menu_visual_only()
	_set_pause_menu_input_enabled(true)

	# 放弃当前阶段的内存进度。存档文件保持最近一次阶段自动存档。
	# GameTime 是 Autoload，必须主动停止 Clinic 时钟，否则即使场景隐藏也会继续计时。
	if GameTime != null:
		if GameTime.has_method("stop_clinic_clock"):
			GameTime.stop_clinic_clock()
		elif GameTime.has_method("cancel_story_pause_state"):
			GameTime.cancel_story_pause_state()

	story_paused_clinic_clock = false
	pending_story_return_target = ""

	if StoryManager != null and StoryManager.has_method("clear_story"):
		StoryManager.clear_story()

	_show_main_menu()


func _quit_game_safely() -> void:
	# SaveManager 自己的 _exit_tree() 也会 flush；
	# 这里主动收尾一次，确保退出路径语义明确。
	if SaveManager != null and SaveManager.has_method("flush_async_saves"):
		SaveManager.flush_async_saves()

	get_tree().quit()


# =========================================================
# 进入 Clinic
# =========================================================
func _enter_clinic() -> void:
	_clear_current_scene()

	var was_cached := clinic_scene_instance != null and is_instance_valid(clinic_scene_instance)
	current_scene = _get_or_create_clinic_scene()
	if current_scene == null:
		push_error("Clinic 场景实例创建失败。")
		return

	_set_scene_active(current_scene, true)

	# 连接 clinic_finished 信号。常驻场景只会实际连接一次。
	if current_scene.has_signal("clinic_finished"):
		if not current_scene.is_connected("clinic_finished", Callable(self, "_on_clinic_finished")):
			current_scene.connect("clinic_finished", Callable(self, "_on_clinic_finished"))
			print("Main 已连接 clinic_finished 信号")
	else:
		print("current_scene 没有 clinic_finished 信号")

	# 必须在 start_new_day() 之前连接，避免入口自动剧情请求丢失。
	if current_scene.has_signal("story_requested"):
		if not current_scene.is_connected("story_requested", Callable(self, "_on_story_requested")):
			current_scene.connect("story_requested", Callable(self, "_on_story_requested"))
			print("Main 已连接 story_requested 信号")
	else:
		print("current_scene 没有 story_requested 信号")

	if current_scene.has_method("set_day"):
		current_scene.call("set_day", GameTime.current_day)
		print("已刷新诊室天数：", GameTime.current_day)
	else:
		print("Clinic 没有 set_day 方法")

	# 先播放 Clinic 场景音乐，再执行 start_new_day()。
	# start_new_day() 可能同步触发入口剧情；这样剧情 BGM 可以正确覆盖场景 BGM。
	if is_instance_valid(MusicManager):
		MusicManager.play_scene_music("Clinic")

	# 播放 Clinic 场景环境音
	if is_instance_valid(AmbientManager):
		AmbientManager.play_scene_ambient("Clinic")

	# 每次重新进入 Clinic 都走每日入口；Clinic.start_new_day() 负责清理上一天
	# 的临时 UI / 病人状态并重新启动白天计时。
	if current_scene.has_method("start_new_day"):
		current_scene.call("start_new_day", GameTime.current_day)

	if OS.is_debug_build() and was_cached:
		print("[Main] 复用 Clinic 常驻实例")

	print("已进入 Clinic 场景，第 %d 天" % GameTime.current_day)


# =========================================================
# 进入 Night
# =========================================================
func _enter_night(show_finance_report: bool = true) -> void:
	_clear_current_scene()

	var was_cached := night_scene_instance != null and is_instance_valid(night_scene_instance)
	current_scene = _get_or_create_night_scene()
	if current_scene == null:
		push_error("Night 场景实例创建失败。")
		return

	_set_scene_active(current_scene, true)

	# 连接 night_finished 信号。常驻场景只会实际连接一次。
	if current_scene.has_signal("night_finished"):
		if not current_scene.is_connected("night_finished", Callable(self, "_on_night_finished")):
			current_scene.connect("night_finished", Callable(self, "_on_night_finished"))
			print("Main 已连接 night_finished 信号")
	else:
		print("current_scene 没有 night_finished 信号")

	# 必须在 start_night() 之前连接，避免入口自动剧情请求丢失。
	if current_scene.has_signal("story_requested"):
		if not current_scene.is_connected("story_requested", Callable(self, "_on_story_requested")):
			current_scene.connect("story_requested", Callable(self, "_on_story_requested"))
			print("Main 已连接 Night story_requested 信号")
	else:
		print("current_scene 没有 story_requested 信号")

	# 先播放 Night 场景音乐，再执行 start_night()。
	# start_night() 可能同步触发入口剧情；这样剧情 BGM 可以正确覆盖场景 BGM。
	if is_instance_valid(MusicManager):
		MusicManager.play_scene_music("Night")

	# 播放 Night 场景环境音
	if is_instance_valid(AmbientManager):
		AmbientManager.play_scene_ambient("Night")

	if current_scene.has_method("start_night"):
		current_scene.call("start_night", GameTime.current_day, show_finance_report)
	else:
		print("Night 没有 start_night 方法")

	if OS.is_debug_build() and was_cached:
		print("[Main] 复用 Night 常驻实例")

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
	# return_target 只保留为旧信号兼容参数；实际行为读取 StoryData.after_play。
	_play_story(story_path, return_target)


func _play_story(story_path: String, _legacy_return_target: String = "") -> void:
	if story_path.is_empty():
		push_warning("剧情路径为空")
		return

	# StoryManager 已在启动时缓存所有剧情资源；优先直接取缓存，
	# 避免 Main 在真正播放时再进行一次同步 load()。
	var loaded_story = null
	if StoryManager != null and StoryManager.has_method("get_cached_story_by_path"):
		loaded_story = StoryManager.get_cached_story_by_path(story_path)
	else:
		loaded_story = load(story_path)

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

	# “播放后”决定剧情结束目标。gameover / endgame 都不需要返回游戏场景。
	pending_story_return_target = story_data.get_return_scene()
	var is_terminal_story := (
		story_data.should_game_over()
		or story_data.should_end_game()
	)
	if pending_story_return_target.is_empty() and not is_terminal_story:
		var trigger_scene := story_data.get_condition_scene()
		# night_end 是触发时机，默认返回仍然是 Night。
		if trigger_scene == StoryData.TRIGGER_SCENE_NIGHT_END:
			pending_story_return_target = "night"
		elif trigger_scene in ["clinic", "night", "map"]:
			pending_story_return_target = trigger_scene

	if pending_story_return_target.is_empty() and not is_terminal_story:
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

	# 剧情进入只更新内存状态，不在这里写盘。

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

	var endgame_callable := Callable(self, "_on_story_endgame_requested")
	if story_node.has_signal("endgame_requested"):
		if not story_node.is_connected("endgame_requested", endgame_callable):
			story_node.connect("endgame_requested", endgame_callable)


func _on_story_playback_completed(completed_story: StoryData) -> void:
	# 每段剧情台词真正播放完（或跳过到结尾）后，统一执行数值动作。
	# 治疗判定阶段不经过这里，因此金钱 / 名望 / 心得不会提前结算。
	if completed_story == null:
		return

	if StoryManager == null or not StoryManager.has_method("apply_story_value_changes"):
		push_warning("StoryManager 缺少 apply_story_value_changes()，无法结算剧情数值动作。")
		return

	var raw_result = StoryManager.apply_story_value_changes(completed_story)
	if typeof(raw_result) != TYPE_DICTIONARY:
		push_warning("StoryManager.apply_story_value_changes() 返回了无效结果。")
		return

	var value_change_result: Dictionary = raw_result
	var money_change := int(value_change_result.get("money_change", 0))
	var reputation_change := int(value_change_result.get("reputation_change", 0))
	var experience_change := int(value_change_result.get("experience_change", 0))
	if money_change == 0 and reputation_change == 0 and experience_change == 0:
		return

	# 数值变化只保留在内存，等待下一次昼夜阶段结束统一写盘。


func _on_story_treatment_requested(npc_id: String, disease: DiseaseData) -> void:
	# story NPC 诊疗过程只修改内存，不在诊疗中途写盘。

	_clear_story_treatment_backend()

	# 剧情诊疗不再实例化完整的 Clinic.tscn。
	# 只创建轻量 StoryTreatmentService，避免重复构建整套诊室 UI / Window / 控制器。
	story_treatment_backend = STORY_TREATMENT_SERVICE_SCRIPT.new()
	story_treatment_backend_root.add_child(story_treatment_backend)

	if not story_treatment_backend.has_method("prepare_story_npc_treatment"):
		_cancel_story_treatment("StoryTreatmentService 缺少 prepare_story_npc_treatment()。")
		return

	var prepared: bool = bool(story_treatment_backend.call(
		"prepare_story_npc_treatment",
		npc_id,
		disease,
		GameTime.current_day
	))
	if not prepared:
		_cancel_story_treatment("StoryTreatmentService 准备失败：%s" % npc_id)
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

	# 不需要恢复诊疗的后续剧情，结束后按它自己的“播放后”配置返回。
	# gameover / endgame 会在剧情结束时发送各自的终止信号。
	if not resume_treatment:
		var next_return_target := next_story.get_return_scene()
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

	# 连续剧情切换只更新内存，不在 followup 切换时写盘。

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

	# gameover 不播放片尾，直接回到开始菜单。
	# 原存档保留，玩家仍可从最后一个保存点读取。
	_show_main_menu()


func _on_story_endgame_requested() -> void:
	# 最终通关剧情已经完整播放；与 gameover 一样不覆盖玩家最后一个存档点。
	StoryManager.mark_current_story_played()
	StoryManager.clear_story()
	pending_story_return_target = ""

	if story_paused_clinic_clock:
		if GameTime != null and GameTime.has_method("cancel_story_pause_state"):
			GameTime.cancel_story_pause_state()
	story_paused_clinic_clock = false

	var tree := get_tree()
	if tree == null:
		return

	tree.paused = false

	# endgame 专用于最终通关：剧情淡出后进入工作人员片尾。
	var error := tree.change_scene_to_packed(ENDING_CREDITS_SCENE)
	if error != OK:
		push_error("进入片尾场景失败，错误代码：%s" % error)
		_show_main_menu()


func _is_game_over_story(story: StoryData) -> bool:
	if story == null:
		return false

	# “播放后 = gameover”表示失败结局。
	return story.should_game_over()


func _on_story_finished() -> void:
	# 只有走到正式结束信号，才把当前剧情记为已播放。
	# 剧情状态继续保留在内存，只有昼夜阶段真正结束时才写盘。
	StoryManager.mark_current_story_played()
	StoryManager.clear_story()

	var target := pending_story_return_target
	pending_story_return_target = ""
	_clear_story_overlay()

	if target == "night":
		# 剧情结束返回 Night：如果本次确实结束白天，
		# 必须先完成当天财务结算，再切换到 Night。
		# 白天接诊时已经实时入账的诊费与药材利润保持不变。
		var did_finish_day: bool = false
		if story_paused_clinic_clock:
			if GameTime != null and GameTime.has_method("cancel_story_pause_state"):
				GameTime.cancel_story_pause_state()

			if GameTime != null and GameTime.is_day():
				_settle_current_day_finances_if_needed()
				GameTime.finish_day()
				did_finish_day = true

		story_paused_clinic_clock = false

		# 只有本次确实完成“白天 → Night”阶段切换才写盘。
		if did_finish_day:
			_save_game_with_warning("白天结束（剧情返回 Night）")

		_enter_night(false)
		return

	story_paused_clinic_clock = false

	if target == "clinic":
		# “播放后”决定剧情结束后的目标场景。
		# 如果当前处于 Night，进入 Clinic 前先正常结束夜晚并推进到下一天；
		# 如果本来就在白天，则只返回 Clinic，不写盘。
		if GameTime != null and not GameTime.is_day():
			GameTime.finish_night()
			_save_game_with_warning("夜晚结束（剧情返回下一天诊室）")

		_enter_clinic()
		return

	if target == "map":
		_enter_map()
		return

	# 兜底：未知返回目标默认回 Clinic。
	_enter_clinic()


# =========================================================
# 当天银钱结算
# =========================================================
func _settle_current_day_finances_if_needed() -> void:
	# 收入在白天接诊时已经实时记入 Unlock；
	# 进入 Night 前统一扣除工钱 / 食费并生成当天结算报告。
	if Unlock != null and Unlock.has_method("settle_day_finances"):
		Unlock.settle_day_finances(GameTime.current_day)



# =========================================================
# Clinic 当天结束
# 白天结束：
# 第 1 天 白天 → 第 1 天 黑夜
# 不增加天数
# =========================================================
func _on_clinic_finished() -> void:
	# 正常白天结束：先结算，再进入 Night；Night 默认显示结算窗口。
	_settle_current_day_finances_if_needed()
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
	# night_end 现在是“触发场景”的一个特殊值。
	# 只在玩家点击“休息，进入明天”这一刻检查，不会和普通 night 入口混在一起。
	var pending_story: StoryData = StoryManager.find_night_end_story(GameTime.current_day)

	if pending_story != null:
		_play_story(pending_story.resource_path)

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
	# 阶段自动存档优先提交到后台线程。
	# 旧 SaveManager 仍可通过同步 save_game() 兜底，便于脚本逐步替换。
	var save_success := false
	if SaveManager != null and SaveManager.has_method("save_game_async"):
		save_success = bool(SaveManager.call("save_game_async", -1, context))
	else:
		save_success = SaveManager.save_game()

	if not save_success:
		push_warning("%s：自动存档任务提交失败。" % context)

	return save_success


# =========================================================
# Clinic / Night 常驻场景管理
# =========================================================
func _get_or_create_clinic_scene() -> Node:
	if clinic_scene_instance != null and is_instance_valid(clinic_scene_instance):
		return clinic_scene_instance

	clinic_scene_instance = CLINIC_SCENE.instantiate()
	current_scene_root.add_child(clinic_scene_instance)
	_set_scene_active(clinic_scene_instance, false)

	if OS.is_debug_build():
		print("[Main] Clinic 常驻实例创建完成")

	return clinic_scene_instance


func _get_or_create_night_scene() -> Node:
	if night_scene_instance != null and is_instance_valid(night_scene_instance):
		return night_scene_instance

	night_scene_instance = NIGHT_SCENE.instantiate()
	current_scene_root.add_child(night_scene_instance)
	_set_scene_active(night_scene_instance, false)

	if OS.is_debug_build():
		print("[Main] Night 常驻实例创建完成")

	return night_scene_instance


# 旧名字保留，避免其它 Main 内部调用需要大范围改写。
# Clinic / Night 不再销毁；Map 等临时场景仍按旧行为释放。
func _clear_current_scene() -> void:
	if current_scene == null or not is_instance_valid(current_scene):
		current_scene = null
		return

	if current_scene == clinic_scene_instance or current_scene == night_scene_instance:
		_set_scene_active(current_scene, false)
	else:
		current_scene.queue_free()

	current_scene = null


func _set_scene_active(scene_node: Node, should_be_active: bool) -> void:
	if scene_node == null or not is_instance_valid(scene_node):
		return

	# Window 节点可能作为原生子窗口独立显示，单纯隐藏父 Control 不一定足够。
	# 场景脚本有清理钩子时，先让它关闭自己的临时窗口。
	if not should_be_active and scene_node.has_method("prepare_for_scene_hide"):
		scene_node.call("prepare_for_scene_hide")

	if scene_node is CanvasItem:
		(scene_node as CanvasItem).visible = should_be_active

	# PROCESS_MODE_DISABLED 会连同使用 INHERIT 的子节点一起停止 _process/_input。
	# 重新进入时恢复 INHERIT。
	scene_node.process_mode = (
		Node.PROCESS_MODE_INHERIT
		if should_be_active
		else Node.PROCESS_MODE_DISABLED
	)


func _set_scene_visible(scene_node: Node, should_be_visible: bool) -> void:
	# Story 覆盖播放期间不仅隐藏底层场景，同时停止它的处理。
	_set_scene_active(scene_node, should_be_visible)


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
