extends CanvasLayer

signal closed

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION_AUDIO: String = "audio"
const SECTION_DISPLAY: String = "display"

const MASTER_BUS: String = "Master"
const MUSIC_BUS: String = "BGM"
const SFX_BUS: String = "SFX"

@onready var master_volume_slider: HSlider = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MasterVolumeSlider
@onready var music_volume_slider: HSlider = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MusicVolumeSlider
@onready var sfx_volume_slider: HSlider = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SfxVolumeSlider
@onready var fullscreen_check_box: CheckBox = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/FullscreenCheckBox
@onready var music_label: Label = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MusicLabel
@onready var sfx_label: Label = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SfxLabel
@onready var back_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton

var config: ConfigFile = ConfigFile.new()
var loading_settings: bool = false


func _ready() -> void:
	# Settings 既可以从标题菜单打开，也可以从已暂停的游戏中打开。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_load_settings()
	_refresh_optional_audio_bus_state()
	_connect_signals()


func _connect_signals() -> void:
	if not master_volume_slider.value_changed.is_connected(_on_master_volume_changed):
		master_volume_slider.value_changed.connect(_on_master_volume_changed)

	if not music_volume_slider.value_changed.is_connected(_on_music_volume_changed):
		music_volume_slider.value_changed.connect(_on_music_volume_changed)

	if not sfx_volume_slider.value_changed.is_connected(_on_sfx_volume_changed):
		sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)

	if not fullscreen_check_box.toggled.is_connected(_on_fullscreen_toggled):
		fullscreen_check_box.toggled.connect(_on_fullscreen_toggled)

	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and (event as InputEventKey).echo:
		return

	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()


func open_panel() -> void:
	_refresh_optional_audio_bus_state()
	visible = true
	back_button.grab_focus()


func close_panel(emit_closed_signal: bool = true) -> void:
	if not visible:
		return

	_save_settings()
	visible = false

	if emit_closed_signal:
		closed.emit()


func _load_settings() -> void:
	loading_settings = true

	var load_error := config.load(CONFIG_PATH)
	if load_error != OK:
		config = ConfigFile.new()

	var master_value := float(config.get_value(SECTION_AUDIO, "master_volume", 100.0))
	var music_value := float(config.get_value(SECTION_AUDIO, "music_volume", 80.0))
	var sfx_value := float(config.get_value(SECTION_AUDIO, "sfx_volume", 80.0))
	var fullscreen_value := bool(config.get_value(
		SECTION_DISPLAY,
		"fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	))

	master_volume_slider.value = clampf(master_value, 0.0, 100.0)
	music_volume_slider.value = clampf(music_value, 0.0, 100.0)
	sfx_volume_slider.value = clampf(sfx_value, 0.0, 100.0)
	fullscreen_check_box.button_pressed = fullscreen_value

	_apply_bus_volume(MASTER_BUS, master_volume_slider.value)
	_apply_bus_volume(MUSIC_BUS, music_volume_slider.value)
	_apply_bus_volume(SFX_BUS, sfx_volume_slider.value)
	_apply_fullscreen(fullscreen_value)

	loading_settings = false


func _save_settings() -> void:
	config.set_value(SECTION_AUDIO, "master_volume", master_volume_slider.value)
	config.set_value(SECTION_AUDIO, "music_volume", music_volume_slider.value)
	config.set_value(SECTION_AUDIO, "sfx_volume", sfx_volume_slider.value)
	config.set_value(SECTION_DISPLAY, "fullscreen", fullscreen_check_box.button_pressed)

	var save_error := config.save(CONFIG_PATH)
	if save_error != OK:
		push_warning("设置保存失败：%s" % CONFIG_PATH)


func _refresh_optional_audio_bus_state() -> void:
	var music_available := AudioServer.get_bus_index(MUSIC_BUS) >= 0
	var sfx_available := AudioServer.get_bus_index(SFX_BUS) >= 0

	music_volume_slider.editable = music_available
	sfx_volume_slider.editable = sfx_available

	music_label.tooltip_text = (
		"当前项目尚未创建 BGM 音频总线。创建后该滑块会自动生效。"
		if not music_available
		else ""
	)
	music_volume_slider.tooltip_text = music_label.tooltip_text

	sfx_label.tooltip_text = (
		"当前项目尚未创建 SFX 音频总线。创建后该滑块会自动生效。"
		if not sfx_available
		else ""
	)
	sfx_volume_slider.tooltip_text = sfx_label.tooltip_text


func _apply_bus_volume(bus_name: String, percent: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return

	var linear_value := clampf(percent / 100.0, 0.0, 1.0)
	var db_value := -80.0 if linear_value <= 0.0001 else linear_to_db(linear_value)
	AudioServer.set_bus_volume_db(bus_index, db_value)


func _apply_fullscreen(enabled: bool) -> void:
	var target_mode := (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if enabled
		else DisplayServer.WINDOW_MODE_WINDOWED
	)

	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)


func _on_master_volume_changed(value: float) -> void:
	if loading_settings:
		return
	_apply_bus_volume(MASTER_BUS, value)


func _on_music_volume_changed(value: float) -> void:
	if loading_settings:
		return
	_apply_bus_volume(MUSIC_BUS, value)


func _on_sfx_volume_changed(value: float) -> void:
	if loading_settings:
		return
	_apply_bus_volume(SFX_BUS, value)


func _on_fullscreen_toggled(enabled: bool) -> void:
	if loading_settings:
		return
	_apply_fullscreen(enabled)


func _on_back_button_pressed() -> void:
	close_panel()
