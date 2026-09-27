extends CanvasLayer

signal closed

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION_AUDIO: String = "audio"
const SECTION_DISPLAY: String = "display"
const SECTION_LANGUAGE: String = "language"

const LOCALE_ZH_CN: String = "zh_CN"
const LOCALE_EN: String = "en"
const LOCALE_JA: String = "ja"

const DISPLAY_MODE_FULLSCREEN: String = "fullscreen"
const DISPLAY_MODE_WINDOW_1920X1080: String = "window_1920x1080"
const DISPLAY_MODE_WINDOW_1600X900: String = "window_1600x900"
const DISPLAY_MODE_WINDOW_1280X720: String = "window_1280x720"
const DISPLAY_MODE_ORDER: Array[String] = [
	DISPLAY_MODE_FULLSCREEN,
	DISPLAY_MODE_WINDOW_1920X1080,
	DISPLAY_MODE_WINDOW_1600X900,
	DISPLAY_MODE_WINDOW_1280X720,
]
const DISPLAY_MODE_SIZES: Dictionary = {
	DISPLAY_MODE_WINDOW_1920X1080: Vector2i(1920, 1080),
	DISPLAY_MODE_WINDOW_1600X900: Vector2i(1600, 900),
	DISPLAY_MODE_WINDOW_1280X720: Vector2i(1280, 720),
}

const MASTER_BUS: String = "Master"
const MUSIC_BUS: String = "BGM"
const SFX_BUS: String = "SFX"
const AMBIENT_BUS: String = "Ambient"

@onready var master_volume_slider: HSlider = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MasterVolumeSlider
@onready var music_volume_slider: HSlider = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MusicVolumeSlider
@onready var sfx_volume_slider: HSlider = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SfxVolumeSlider
@onready var ambient_volume_slider: HSlider = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AmbientVolumeSlider
@onready var language_option_button: OptionButton = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/LanguageOptionButton
@onready var display_mode_option_button: OptionButton = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/DisplayModeOptionButton
@onready var music_label: Label = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/MusicLabel
@onready var sfx_label: Label = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/SfxLabel
@onready var ambient_label: Label = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/AmbientLabel
@onready var back_button: Button = $DarkBackground/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/BackButton

var config: ConfigFile = ConfigFile.new()
var loading_settings: bool = false


func _ready() -> void:
	# Settings 既可以从标题菜单打开，也可以从已暂停的游戏中打开。
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_setup_language_options()
	_setup_display_mode_options()
	_load_settings()
	_refresh_optional_audio_bus_state()
	_connect_signals()


func _setup_language_options() -> void:
	language_option_button.clear()
	language_option_button.add_item("简体中文")
	language_option_button.add_item("English")
	language_option_button.add_item("日本語")


func _setup_display_mode_options(selected_mode: String = "") -> void:
	display_mode_option_button.clear()

	for mode in DISPLAY_MODE_ORDER:
		var label := ""
		if mode == DISPLAY_MODE_FULLSCREEN:
			label = tr("UI_FULLSCREEN")
		else:
			var size: Vector2i = DISPLAY_MODE_SIZES[mode]
			label = tr("UI_DISPLAY_MODE_WINDOW_FMT") % [size.x, size.y]
		display_mode_option_button.add_item(label)
		display_mode_option_button.set_item_metadata(display_mode_option_button.item_count - 1, mode)

	var mode_to_select := selected_mode
	if not _is_valid_display_mode(mode_to_select):
		mode_to_select = DISPLAY_MODE_WINDOW_1920X1080
	for index in range(display_mode_option_button.item_count):
		if str(display_mode_option_button.get_item_metadata(index)) == mode_to_select:
			display_mode_option_button.select(index)
			return
	display_mode_option_button.select(0)


func _connect_signals() -> void:
	if not master_volume_slider.value_changed.is_connected(_on_master_volume_changed):
		master_volume_slider.value_changed.connect(_on_master_volume_changed)

	if not music_volume_slider.value_changed.is_connected(_on_music_volume_changed):
		music_volume_slider.value_changed.connect(_on_music_volume_changed)

	if not sfx_volume_slider.value_changed.is_connected(_on_sfx_volume_changed):
		sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)

	if not ambient_volume_slider.value_changed.is_connected(_on_ambient_volume_changed):
		ambient_volume_slider.value_changed.connect(_on_ambient_volume_changed)

	if not language_option_button.item_selected.is_connected(_on_language_selected):
		language_option_button.item_selected.connect(_on_language_selected)

	if not display_mode_option_button.item_selected.is_connected(_on_display_mode_selected):
		display_mode_option_button.item_selected.connect(_on_display_mode_selected)

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
	var saved_locale := str(config.get_value(SECTION_LANGUAGE, "locale", LOCALE_ZH_CN))
	if saved_locale != LOCALE_ZH_CN and saved_locale != LOCALE_EN and saved_locale != LOCALE_JA:
		saved_locale = LOCALE_ZH_CN
	var saved_display_mode := _get_saved_display_mode()

	master_volume_slider.value = clampf(master_value, 0.0, 100.0)
	music_volume_slider.value = clampf(music_value, 0.0, 100.0)
	sfx_volume_slider.value = clampf(sfx_value, 0.0, 100.0)
	ambient_volume_slider.value = clampf(float(config.get_value(SECTION_AUDIO, "ambient_volume", 80.0)), 0.0, 100.0)
	match saved_locale:
		LOCALE_EN:
			language_option_button.select(1)
		LOCALE_JA:
			language_option_button.select(2)
		_:
			language_option_button.select(0)
	TranslationServer.set_locale(saved_locale)
	_setup_display_mode_options(saved_display_mode)
	_apply_bus_volume(MASTER_BUS, master_volume_slider.value)
	_apply_bus_volume(MUSIC_BUS, music_volume_slider.value)
	_apply_bus_volume(SFX_BUS, sfx_volume_slider.value)
	_apply_bus_volume(AMBIENT_BUS, ambient_volume_slider.value)
	_apply_display_mode(saved_display_mode)

	loading_settings = false


func _save_settings() -> void:
	config.set_value(SECTION_AUDIO, "master_volume", master_volume_slider.value)
	config.set_value(SECTION_AUDIO, "music_volume", music_volume_slider.value)
	config.set_value(SECTION_AUDIO, "sfx_volume", sfx_volume_slider.value)
	config.set_value(SECTION_AUDIO, "ambient_volume", ambient_volume_slider.value)
	config.set_value(SECTION_LANGUAGE, "locale", _selected_locale())
	var selected_display_mode := _selected_display_mode()
	config.set_value(SECTION_DISPLAY, "display_mode", selected_display_mode)
	# Keep the old key in sync so older builds can still read this setting.
	config.set_value(SECTION_DISPLAY, "fullscreen", selected_display_mode == DISPLAY_MODE_FULLSCREEN)

	var save_error := config.save(CONFIG_PATH)
	if save_error != OK:
		push_warning("设置保存失败：%s" % CONFIG_PATH)


func _selected_locale() -> String:
	match language_option_button.selected:
		1:
			return LOCALE_EN
		2:
			return LOCALE_JA
	return LOCALE_ZH_CN


func _selected_display_mode() -> String:
	var selected_index := display_mode_option_button.selected
	if selected_index < 0 or selected_index >= display_mode_option_button.item_count:
		return DISPLAY_MODE_WINDOW_1920X1080

	var selected_mode := str(display_mode_option_button.get_item_metadata(selected_index))
	return selected_mode if _is_valid_display_mode(selected_mode) else DISPLAY_MODE_WINDOW_1920X1080


func _get_saved_display_mode() -> String:
	var saved_mode := str(config.get_value(SECTION_DISPLAY, "display_mode", "")).strip_edges()
	if _is_valid_display_mode(saved_mode):
		return saved_mode

	# Migrate settings.cfg files created before the display-mode dropdown existed.
	var legacy_fullscreen := bool(config.get_value(
		SECTION_DISPLAY,
		"fullscreen",
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	))
	return DISPLAY_MODE_FULLSCREEN if legacy_fullscreen else DISPLAY_MODE_WINDOW_1920X1080


func _is_valid_display_mode(mode: String) -> bool:
	return mode == DISPLAY_MODE_FULLSCREEN or DISPLAY_MODE_SIZES.has(mode)


func _refresh_optional_audio_bus_state() -> void:
	var music_available := AudioServer.get_bus_index(MUSIC_BUS) >= 0
	var sfx_available := AudioServer.get_bus_index(SFX_BUS) >= 0
	var ambient_available := AudioServer.get_bus_index(AMBIENT_BUS) >= 0

	music_volume_slider.editable = music_available
	sfx_volume_slider.editable = sfx_available
	ambient_volume_slider.editable = ambient_available

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


func _apply_display_mode(mode: String) -> void:
	if mode == DISPLAY_MODE_FULLSCREEN:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return

	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var target_size = DISPLAY_MODE_SIZES.get(mode, Vector2i(1920, 1080))
	DisplayServer.window_set_size(target_size)


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


func _on_ambient_volume_changed(value: float) -> void:
	if loading_settings:
		return
	_apply_bus_volume(AMBIENT_BUS, value)


func _on_language_selected(_index: int) -> void:
	if loading_settings:
		return
	var selected_display_mode := _selected_display_mode()
	TranslationServer.set_locale(_selected_locale())
	_setup_display_mode_options(selected_display_mode)
	_save_settings()


func _on_display_mode_selected(index: int) -> void:
	if loading_settings:
		return
	var selected_mode := str(display_mode_option_button.get_item_metadata(index))
	_apply_display_mode(selected_mode)


func _on_back_button_pressed() -> void:
	close_panel()
