extends CanvasLayer

signal toggle_requested
signal resume_requested
signal settings_requested
signal main_menu_requested
signal quit_requested

@onready var resume_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/ResumeButton
@onready var settings_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SettingsButton
@onready var main_menu_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/QuitButton

var input_enabled: bool = true


func _ready() -> void:
	# PauseMenu 必须在 SceneTree.paused = true 时继续处理按钮和 ESC。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	if not resume_button.pressed.is_connected(_on_resume_button_pressed):
		resume_button.pressed.connect(_on_resume_button_pressed)

	if not settings_button.pressed.is_connected(_on_settings_button_pressed):
		settings_button.pressed.connect(_on_settings_button_pressed)

	if not main_menu_button.pressed.is_connected(_on_main_menu_button_pressed):
		main_menu_button.pressed.connect(_on_main_menu_button_pressed)

	if not quit_button.pressed.is_connected(_on_quit_button_pressed):
		quit_button.pressed.connect(_on_quit_button_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event is InputEventKey and (event as InputEventKey).echo:
		return

	if event.is_action_pressed("ui_cancel"):
		toggle_requested.emit()
		get_viewport().set_input_as_handled()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled


func show_menu() -> void:
	visible = true
	resume_button.grab_focus()


func hide_menu() -> void:
	visible = false


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_settings_button_pressed() -> void:
	settings_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()
