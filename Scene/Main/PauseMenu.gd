extends CanvasLayer

signal toggle_requested
signal resume_requested
signal settings_requested
signal manual_save_requested(slot_index: int)
signal load_game_requested(slot_index: int)
signal main_menu_requested
signal quit_requested

@onready var main_pause_center: CenterContainer = $DarkBackground/CenterContainer
@onready var pause_title_label: Label = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var resume_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeButton
@onready var save_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SaveButton
@onready var load_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/LoadGameButton
@onready var settings_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsButton
@onready var main_menu_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuitButton

@onready var manual_save_center: CenterContainer = $DarkBackground/ManualSaveCenter
@onready var manual_save_title_label: Label = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var manual_save_rule_label: Label = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/RuleLabel
@onready var manual_slot_2_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/ManualSlot2Button
@onready var manual_slot_3_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/ManualSlot3Button
@onready var manual_slot_4_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/ManualSlot4Button
@onready var manual_slot_5_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/ManualSlot5Button
@onready var manual_save_status_label: Label = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var manual_save_back_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/BackButton

@onready var load_save_center: CenterContainer = $DarkBackground/LoadSaveCenter
@onready var load_title_label: Label = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/TitleLabel
@onready var load_rule_label: Label = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/RuleLabel
@onready var load_slot_1_button: Button = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/LoadSlot1Button
@onready var load_slot_2_button: Button = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/LoadSlot2Button
@onready var load_slot_3_button: Button = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/LoadSlot3Button
@onready var load_slot_4_button: Button = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/LoadSlot4Button
@onready var load_slot_5_button: Button = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/LoadSlot5Button
@onready var load_status_label: Label = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var load_back_button: Button = $DarkBackground/LoadSaveCenter/PanelContainer/MarginContainer/VBoxContainer/BackButton

var input_enabled: bool = true
var pending_manual_overwrite_slot: int = -1
var manual_overwrite_dialog: ConfirmationDialog = null
var pending_load_slot: int = -1
var load_confirm_dialog: ConfirmationDialog = null


func _localized_slot_label(slot_index: int) -> String:
	if slot_index == SaveManager.AUTO_SAVE_SLOT:
		return tr("UI_AUTO_SAVE")
	if not SaveManager.is_manual_slot(slot_index):
		return tr("UI_INVALID_SAVE")
	return tr("UI_MANUAL_SLOT_FMT") % (slot_index - 1)


func _localized_save_name(meta: Dictionary) -> String:
	if meta.has("current_day") and meta.has("current_phase"):
		var phase_key := "UI_PHASE_NIGHT" if String(meta["current_phase"]) == GameTime.PHASE_NIGHT else "UI_PHASE_DAY"
		return tr("UI_SAVE_DAY_PHASE") % [int(meta["current_day"]), tr(phase_key)]
	return tr(String(meta.get("display_name", "UI_EMPTY_SAVE")))


func refresh_language() -> void:
	pause_title_label.text = tr("UI_PAUSED")
	resume_button.text = tr("UI_RESUME_GAME")
	save_button.text = tr("UI_SAVE_GAME")
	load_button.text = tr("UI_LOAD_SAVE")
	settings_button.text = tr("UI_SETTINGS_TITLE")
	main_menu_button.text = tr("UI_RETURN_MENU")
	quit_button.text = tr("UI_MENU_QUIT_GAME")
	manual_save_title_label.text = tr("UI_MANUAL_SAVE")
	manual_save_rule_label.text = tr("UI_MANUAL_SAVE_RULE")
	manual_save_back_button.text = tr("UI_BACK")
	load_title_label.text = tr("UI_LOAD_SAVE")
	load_rule_label.text = tr("UI_LOAD_RULE")
	load_back_button.text = tr("UI_BACK")
	if manual_save_center.visible:
		_refresh_manual_save_buttons()
	if load_save_center.visible:
		_refresh_load_game_buttons()
	if load_confirm_dialog != null:
		load_confirm_dialog.title = tr("UI_LOAD_SAVE")
		load_confirm_dialog.get_ok_button().text = tr("UI_CONFIRM_LOAD")
		load_confirm_dialog.get_cancel_button().text = tr("UI_CANCEL")
	if manual_overwrite_dialog != null:
		manual_overwrite_dialog.title = tr("UI_OVERWRITE_MANUAL")
		manual_overwrite_dialog.get_ok_button().text = tr("UI_CONFIRM_OVERWRITE")
		manual_overwrite_dialog.get_cancel_button().text = tr("UI_CANCEL")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh_language()


func _ready() -> void:
	# PauseMenu 必须在 SceneTree.paused = true 时继续处理按钮和 ESC。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	if not resume_button.pressed.is_connected(_on_resume_button_pressed):
		resume_button.pressed.connect(_on_resume_button_pressed)

	if not save_button.pressed.is_connected(_on_save_button_pressed):
		save_button.pressed.connect(_on_save_button_pressed)

	if not load_button.pressed.is_connected(_on_load_button_pressed):
		load_button.pressed.connect(_on_load_button_pressed)

	if not settings_button.pressed.is_connected(_on_settings_button_pressed):
		settings_button.pressed.connect(_on_settings_button_pressed)

	if not main_menu_button.pressed.is_connected(_on_main_menu_button_pressed):
		main_menu_button.pressed.connect(_on_main_menu_button_pressed)

	if not quit_button.pressed.is_connected(_on_quit_button_pressed):
		quit_button.pressed.connect(_on_quit_button_pressed)

	if not manual_slot_2_button.pressed.is_connected(_on_manual_slot_2_pressed):
		manual_slot_2_button.pressed.connect(_on_manual_slot_2_pressed)

	if not manual_slot_3_button.pressed.is_connected(_on_manual_slot_3_pressed):
		manual_slot_3_button.pressed.connect(_on_manual_slot_3_pressed)

	if not manual_slot_4_button.pressed.is_connected(_on_manual_slot_4_pressed):
		manual_slot_4_button.pressed.connect(_on_manual_slot_4_pressed)

	if not manual_slot_5_button.pressed.is_connected(_on_manual_slot_5_pressed):
		manual_slot_5_button.pressed.connect(_on_manual_slot_5_pressed)

	if not manual_save_back_button.pressed.is_connected(_on_manual_save_back_pressed):
		manual_save_back_button.pressed.connect(_on_manual_save_back_pressed)

	if not load_slot_1_button.pressed.is_connected(_on_load_slot_1_pressed):
		load_slot_1_button.pressed.connect(_on_load_slot_1_pressed)
	if not load_slot_2_button.pressed.is_connected(_on_load_slot_2_pressed):
		load_slot_2_button.pressed.connect(_on_load_slot_2_pressed)
	if not load_slot_3_button.pressed.is_connected(_on_load_slot_3_pressed):
		load_slot_3_button.pressed.connect(_on_load_slot_3_pressed)
	if not load_slot_4_button.pressed.is_connected(_on_load_slot_4_pressed):
		load_slot_4_button.pressed.connect(_on_load_slot_4_pressed)
	if not load_slot_5_button.pressed.is_connected(_on_load_slot_5_pressed):
		load_slot_5_button.pressed.connect(_on_load_slot_5_pressed)
	if not load_back_button.pressed.is_connected(_on_load_back_pressed):
		load_back_button.pressed.connect(_on_load_back_pressed)

	_setup_manual_overwrite_dialog()
	_setup_load_confirm_dialog()
	refresh_language()
	_show_main_pause_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event is InputEventKey and (event as InputEventKey).echo:
		return

	if event.is_action_pressed("ui_cancel"):
		if manual_overwrite_dialog != null and manual_overwrite_dialog.visible:
			manual_overwrite_dialog.hide()
			pending_manual_overwrite_slot = -1
			get_viewport().set_input_as_handled()
			return

		if load_confirm_dialog != null and load_confirm_dialog.visible:
			load_confirm_dialog.hide()
			pending_load_slot = -1
			get_viewport().set_input_as_handled()
			return

		if manual_save_center.visible:
			_show_main_pause_panel()
			get_viewport().set_input_as_handled()
			return

		if load_save_center.visible:
			_show_main_pause_panel()
			get_viewport().set_input_as_handled()
			return

		toggle_requested.emit()
		get_viewport().set_input_as_handled()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func show_menu() -> void:
	refresh_language()
	visible = true
	_show_main_pause_panel()


func hide_menu() -> void:
	visible = false
	pending_manual_overwrite_slot = -1
	pending_load_slot = -1
	if manual_overwrite_dialog != null:
		manual_overwrite_dialog.hide()
	if load_confirm_dialog != null:
		load_confirm_dialog.hide()


func _show_main_pause_panel() -> void:
	if main_pause_center != null:
		main_pause_center.visible = true
	if manual_save_center != null:
		manual_save_center.visible = false
	if load_save_center != null:
		load_save_center.visible = false

	if visible and resume_button != null:
		resume_button.grab_focus()


func _open_manual_save_menu() -> void:
	if main_pause_center != null:
		main_pause_center.visible = false
	if load_save_center != null:
		load_save_center.visible = false
	if manual_save_center != null:
		manual_save_center.visible = true

	manual_save_status_label.text = tr("UI_MANUAL_SAVE_DETAIL")
	_refresh_manual_save_buttons()
	manual_slot_2_button.grab_focus()


func _refresh_manual_save_buttons() -> void:
	var buttons: Array[Button] = [
		manual_slot_2_button,
		manual_slot_3_button,
		manual_slot_4_button,
		manual_slot_5_button
	]

	for i in range(buttons.size()):
		var slot_index := i + 2
		var button := buttons[i]
		var meta: Dictionary = SaveManager.get_save_meta(slot_index)

		var slot_label := _localized_slot_label(slot_index)
		var exists := bool(meta.get("exists", false))

		if exists:
			var display_name := _localized_save_name(meta)
			var save_time := String(meta.get("save_time", ""))
			button.text = "%s\n%s\n%s" % [
				slot_label,
				display_name,
				save_time
			]
		else:
			button.text = "%s\n%s" % [slot_label, tr("UI_EMPTY_SAVE")]

		# 手动保存界面中的所有手动槽始终可以点击；已有存档会先询问覆盖。
		button.disabled = false


func _open_load_game_menu() -> void:
	if main_pause_center != null:
		main_pause_center.visible = false
	if manual_save_center != null:
		manual_save_center.visible = false
	if load_save_center != null:
		load_save_center.visible = true

	load_status_label.text = tr("UI_LOAD_WARNING")
	_refresh_load_game_buttons()
	_focus_first_available_load_slot()


func _refresh_load_game_buttons() -> void:
	var buttons: Array[Button] = [
		load_slot_1_button,
		load_slot_2_button,
		load_slot_3_button,
		load_slot_4_button,
		load_slot_5_button
	]

	for i in range(buttons.size()):
		var slot_index := i + 1
		var button := buttons[i]
		var meta: Dictionary = SaveManager.get_save_meta(slot_index)
		var slot_label := _localized_slot_label(slot_index)
		var exists := bool(meta.get("exists", false))

		if exists:
			var display_name := _localized_save_name(meta)
			var save_time := String(meta.get("save_time", ""))
			button.text = "%s\n%s\n%s" % [slot_label, display_name, save_time]
			button.disabled = false
		else:
			button.text = "%s\n%s" % [slot_label, tr("UI_EMPTY_SAVE")]
			button.disabled = true


func _focus_first_available_load_slot() -> void:
	var buttons: Array[Button] = [
		load_slot_1_button,
		load_slot_2_button,
		load_slot_3_button,
		load_slot_4_button,
		load_slot_5_button
	]

	for button in buttons:
		if button != null and not button.disabled:
			button.grab_focus()
			return

	if load_back_button != null:
		load_back_button.grab_focus()


func _request_load_game(slot_index: int) -> void:
	if slot_index < 1 or slot_index > 5:
		return

	if not SaveManager.has_save(slot_index):
		load_status_label.text = tr("UI_NO_LOAD_IN_SLOT")
		_refresh_load_game_buttons()
		_focus_first_available_load_slot()
		return

	pending_load_slot = slot_index
	var meta: Dictionary = SaveManager.get_save_meta(slot_index)
	var slot_label := _localized_slot_label(slot_index)
	var display_name := _localized_save_name(meta)
	var save_time := String(meta.get("save_time", ""))

	var detail := display_name
	if not save_time.is_empty():
		detail += "\n" + save_time

	load_confirm_dialog.dialog_text = (
		tr("UI_LOAD_CONFIRM_DETAIL")
	) % [slot_label, detail]
	load_confirm_dialog.popup_centered()


func _setup_load_confirm_dialog() -> void:
	if load_confirm_dialog != null:
		return

	load_confirm_dialog = ConfirmationDialog.new()
	load_confirm_dialog.title = tr("UI_LOAD_SAVE")
	load_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(load_confirm_dialog)

	if load_confirm_dialog.get_ok_button() != null:
		load_confirm_dialog.get_ok_button().text = tr("UI_CONFIRM_LOAD")
	if load_confirm_dialog.get_cancel_button() != null:
		load_confirm_dialog.get_cancel_button().text = tr("UI_CANCEL")

	load_confirm_dialog.confirmed.connect(_on_load_confirmed)
	if load_confirm_dialog.has_signal("canceled"):
		load_confirm_dialog.canceled.connect(_on_load_canceled)
	if load_confirm_dialog.has_signal("close_requested"):
		load_confirm_dialog.close_requested.connect(_on_load_canceled)


func _on_load_confirmed() -> void:
	var slot_index := pending_load_slot
	pending_load_slot = -1

	if slot_index < 1 or slot_index > 5:
		return

	load_status_label.text = tr("UI_LOADING_SAVE")
	load_game_requested.emit(slot_index)


func _on_load_canceled() -> void:
	var slot_index := pending_load_slot
	pending_load_slot = -1

	var button := _get_load_slot_button(slot_index)
	if button != null:
		button.grab_focus()


func notify_load_game_result(
	slot_index: int,
	success: bool,
	message: String
) -> void:
	if success:
		return

	load_status_label.text = message
	_refresh_load_game_buttons()

	var button := _get_load_slot_button(slot_index)
	if button != null and not button.disabled:
		button.grab_focus()
	else:
		_focus_first_available_load_slot()


func _get_load_slot_button(slot_index: int) -> Button:
	match slot_index:
		1:
			return load_slot_1_button
		2:
			return load_slot_2_button
		3:
			return load_slot_3_button
		4:
			return load_slot_4_button
		5:
			return load_slot_5_button
		_:
			return null


func notify_manual_save_result(
	slot_index: int,
	success: bool,
	message: String
) -> void:
	manual_save_status_label.text = message
	_refresh_manual_save_buttons()

	var button := _get_manual_slot_button(slot_index)
	if button != null:
		button.grab_focus()

	if not success:
		return


func _request_manual_save(slot_index: int) -> void:
	if slot_index < 2 or slot_index > 5:
		return

	# 已有手动档时先确认覆盖，避免误操作。
	if SaveManager.has_save(slot_index):
		pending_manual_overwrite_slot = slot_index
		var meta := SaveManager.get_save_meta(slot_index)
		var display_name := _localized_save_name(meta)
		manual_overwrite_dialog.dialog_text = (
			tr("UI_MANUAL_OVERWRITE_DETAIL")
			% [_localized_slot_label(slot_index), display_name]
		)
		manual_overwrite_dialog.popup_centered()
		return

	_emit_manual_save_request(slot_index)


func _emit_manual_save_request(slot_index: int) -> void:
	manual_save_status_label.text = tr("UI_SAVING_GAME")
	manual_save_requested.emit(slot_index)


func _setup_manual_overwrite_dialog() -> void:
	if manual_overwrite_dialog != null:
		return

	manual_overwrite_dialog = ConfirmationDialog.new()
	manual_overwrite_dialog.title = tr("UI_OVERWRITE_MANUAL")
	manual_overwrite_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(manual_overwrite_dialog)

	if manual_overwrite_dialog.get_ok_button() != null:
		manual_overwrite_dialog.get_ok_button().text = tr("UI_CONFIRM_OVERWRITE")

	if manual_overwrite_dialog.get_cancel_button() != null:
		manual_overwrite_dialog.get_cancel_button().text = tr("UI_CANCEL")

	manual_overwrite_dialog.confirmed.connect(_on_manual_overwrite_confirmed)

	if manual_overwrite_dialog.has_signal("canceled"):
		manual_overwrite_dialog.canceled.connect(_on_manual_overwrite_canceled)

	if manual_overwrite_dialog.has_signal("close_requested"):
		manual_overwrite_dialog.close_requested.connect(_on_manual_overwrite_canceled)


func _on_manual_overwrite_confirmed() -> void:
	var slot_index := pending_manual_overwrite_slot
	pending_manual_overwrite_slot = -1

	if slot_index < 2 or slot_index > 5:
		return

	_emit_manual_save_request(slot_index)


func _on_manual_overwrite_canceled() -> void:
	var slot_index := pending_manual_overwrite_slot
	pending_manual_overwrite_slot = -1

	var button := _get_manual_slot_button(slot_index)
	if button != null:
		button.grab_focus()


func _get_manual_slot_button(slot_index: int) -> Button:
	match slot_index:
		2:
			return manual_slot_2_button
		3:
			return manual_slot_3_button
		4:
			return manual_slot_4_button
		5:
			return manual_slot_5_button
		_:
			return null


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_save_button_pressed() -> void:
	_open_manual_save_menu()


func _on_load_button_pressed() -> void:
	_open_load_game_menu()


func _on_settings_button_pressed() -> void:
	settings_requested.emit()


func _on_load_slot_1_pressed() -> void:
	_request_load_game(1)


func _on_load_slot_2_pressed() -> void:
	_request_load_game(2)


func _on_load_slot_3_pressed() -> void:
	_request_load_game(3)


func _on_load_slot_4_pressed() -> void:
	_request_load_game(4)


func _on_load_slot_5_pressed() -> void:
	_request_load_game(5)


func _on_load_back_pressed() -> void:
	_show_main_pause_panel()


func _on_manual_slot_2_pressed() -> void:
	_request_manual_save(2)


func _on_manual_slot_3_pressed() -> void:
	_request_manual_save(3)


func _on_manual_slot_4_pressed() -> void:
	_request_manual_save(4)


func _on_manual_slot_5_pressed() -> void:
	_request_manual_save(5)


func _on_manual_save_back_pressed() -> void:
	_show_main_pause_panel()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()
