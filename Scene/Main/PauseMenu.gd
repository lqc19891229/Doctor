extends CanvasLayer

signal toggle_requested
signal resume_requested
signal settings_requested
signal manual_save_requested(slot_index: int)
signal main_menu_requested
signal quit_requested

@onready var main_pause_center: CenterContainer = $DarkBackground/CenterContainer
@onready var resume_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeButton
@onready var save_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SaveButton
@onready var settings_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsButton
@onready var main_menu_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuitButton

@onready var manual_save_center: CenterContainer = $DarkBackground/ManualSaveCenter
@onready var manual_slot_2_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/ManualSlot2Button
@onready var manual_slot_3_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/ManualSlot3Button
@onready var manual_slot_4_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/ManualSlot4Button
@onready var manual_slot_5_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/ManualSlot5Button
@onready var manual_save_status_label: Label = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var manual_save_back_button: Button = $DarkBackground/ManualSaveCenter/PanelContainer/MarginContainer/VBoxContainer/BackButton

var input_enabled: bool = true
var pending_manual_overwrite_slot: int = -1
var manual_overwrite_dialog: ConfirmationDialog = null


func _ready() -> void:
	# PauseMenu 必须在 SceneTree.paused = true 时继续处理按钮和 ESC。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	if not resume_button.pressed.is_connected(_on_resume_button_pressed):
		resume_button.pressed.connect(_on_resume_button_pressed)

	if not save_button.pressed.is_connected(_on_save_button_pressed):
		save_button.pressed.connect(_on_save_button_pressed)

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

	_setup_manual_overwrite_dialog()
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

		if manual_save_center.visible:
			_show_main_pause_panel()
			get_viewport().set_input_as_handled()
			return

		toggle_requested.emit()
		get_viewport().set_input_as_handled()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func show_menu() -> void:
	visible = true
	_show_main_pause_panel()


func hide_menu() -> void:
	visible = false
	pending_manual_overwrite_slot = -1
	if manual_overwrite_dialog != null:
		manual_overwrite_dialog.hide()


func _show_main_pause_panel() -> void:
	if main_pause_center != null:
		main_pause_center.visible = true
	if manual_save_center != null:
		manual_save_center.visible = false

	if visible and resume_button != null:
		resume_button.grab_focus()


func _open_manual_save_menu() -> void:
	if main_pause_center != null:
		main_pause_center.visible = false
	if manual_save_center != null:
		manual_save_center.visible = true

	manual_save_status_label.text = (
		"白天保存：记录本日开始状态；夜晚保存：记录当前夜晚状态。"
	)
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

		var slot_label := String(
			meta.get("slot_label", SaveManager.get_slot_display_label(slot_index))
		)
		var exists := bool(meta.get("exists", false))

		if exists:
			var display_name := String(meta.get("display_name", ""))
			var save_time := String(meta.get("save_time", ""))
			button.text = "%s\n%s\n%s" % [
				slot_label,
				display_name,
				save_time
			]
		else:
			button.text = "%s\n空存档" % slot_label

		# 手动保存界面中的所有手动槽始终可以点击；已有存档会先询问覆盖。
		button.disabled = false


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
		var display_name := String(meta.get("display_name", "已有存档"))
		manual_overwrite_dialog.dialog_text = (
			"%s已有记录：\n%s\n\n是否覆盖？"
			% [SaveManager.get_slot_display_label(slot_index), display_name]
		)
		manual_overwrite_dialog.popup_centered()
		return

	_emit_manual_save_request(slot_index)


func _emit_manual_save_request(slot_index: int) -> void:
	manual_save_status_label.text = "正在保存……"
	manual_save_requested.emit(slot_index)


func _setup_manual_overwrite_dialog() -> void:
	if manual_overwrite_dialog != null:
		return

	manual_overwrite_dialog = ConfirmationDialog.new()
	manual_overwrite_dialog.title = "覆盖手动存档"
	manual_overwrite_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(manual_overwrite_dialog)

	if manual_overwrite_dialog.get_ok_button() != null:
		manual_overwrite_dialog.get_ok_button().text = "确认覆盖"

	if manual_overwrite_dialog.get_cancel_button() != null:
		manual_overwrite_dialog.get_cancel_button().text = "取消"

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


func _on_settings_button_pressed() -> void:
	settings_requested.emit()


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
