extends Control
class_name Tutorial

signal tutorial_finished


# =========================================================
# 配置
# =========================================================

# 在 Inspector 里直接添加 TutorialSlideData。
@export var slides: Array[TutorialSlideData] = []

# 教程结束后要进入的场景。
# 留空时不会自动切场景，只会发出 tutorial_finished 信号。
@export_file("*.tscn") var exit_scene_path: String = ""

# 是否允许玩家点击“跳过教程”。
@export var allow_skip: bool = true

# 是否允许 Esc 直接结束教程。
@export var escape_to_finish: bool = true


# =========================================================
# 节点引用
# =========================================================

@onready var screenshot: TextureRect = $Screenshot

@onready var mask_layer: Control = $MaskLayer
@onready var mask_top: ColorRect = $MaskLayer/MaskTop
@onready var mask_bottom: ColorRect = $MaskLayer/MaskBottom
@onready var mask_left: ColorRect = $MaskLayer/MaskLeft
@onready var mask_right: ColorRect = $MaskLayer/MaskRight
@onready var highlight_frame: Panel = $HighlightFrame

@onready var guide_panel: PanelContainer = $GuidePanel
@onready var title_label: Label = $GuidePanel/MarginContainer/VBox/TitleLabel
@onready var description_label: Label = $GuidePanel/MarginContainer/VBox/DescriptionLabel
@onready var key_label: Label = $GuidePanel/MarginContainer/VBox/KeyLabel

@onready var prev_button: Button = $GuidePanel/MarginContainer/VBox/NavigationRow/PrevButton
@onready var page_label: Label = $GuidePanel/MarginContainer/VBox/NavigationRow/PageLabel
@onready var next_button: Button = $GuidePanel/MarginContainer/VBox/NavigationRow/NextButton
@onready var skip_button: Button = $GuidePanel/MarginContainer/VBox/NavigationRow/SkipButton


# =========================================================
# 运行时
# =========================================================

var current_slide_index: int = 0


func _ready() -> void:
	if not prev_button.pressed.is_connected(_on_prev_pressed):
		prev_button.pressed.connect(_on_prev_pressed)

	if not next_button.pressed.is_connected(_on_next_pressed):
		next_button.pressed.connect(_on_next_pressed)

	if not skip_button.pressed.is_connected(_on_skip_pressed):
		skip_button.pressed.connect(_on_skip_pressed)

	if not resized.is_connected(_on_tutorial_resized):
		resized.connect(_on_tutorial_resized)

	skip_button.visible = allow_skip

	start_tutorial()


# =========================================================
# 对外接口
# =========================================================

func start_tutorial(start_index: int = 0) -> void:
	if slides.is_empty():
		current_slide_index = 0
		_show_empty_state()
		return

	current_slide_index = clampi(start_index, 0, slides.size() - 1)
	_show_current_slide()


func show_slide(index: int) -> void:
	if slides.is_empty():
		_show_empty_state()
		return

	current_slide_index = clampi(index, 0, slides.size() - 1)
	_show_current_slide()


func next_slide() -> void:
	if slides.is_empty():
		return

	if current_slide_index >= slides.size() - 1:
		finish_tutorial()
		return

	current_slide_index += 1
	_show_current_slide()


func previous_slide() -> void:
	if slides.is_empty():
		return

	if current_slide_index <= 0:
		return

	current_slide_index -= 1
	_show_current_slide()


func finish_tutorial() -> void:
	tutorial_finished.emit()

	if exit_scene_path.strip_edges() != "":
		get_tree().change_scene_to_file(exit_scene_path)
		return

	hide()


# =========================================================
# 显示当前页
# =========================================================

func _show_current_slide() -> void:
	if slides.is_empty():
		_show_empty_state()
		return

	if current_slide_index < 0 or current_slide_index >= slides.size():
		return

	var slide := slides[current_slide_index]

	if slide == null:
		_show_empty_state("当前教程页没有配置 TutorialSlideData。")
		return

	screenshot.texture = slide.screenshot

	title_label.text = slide.title
	description_label.text = slide.description

	var key_text := slide.key_text.strip_edges()
	key_label.visible = key_text != ""
	if key_text != "":
		key_label.text = key_text

	page_label.text = "%d / %d" % [
		current_slide_index + 1,
		slides.size()
	]

	prev_button.disabled = current_slide_index <= 0

	if current_slide_index >= slides.size() - 1:
		next_button.text = "开始游戏"
	else:
		next_button.text = "下一页"

	skip_button.visible = allow_skip

	_apply_highlight(slide)


func _show_empty_state(message: String = "当前 Tutorial 还没有配置教程页面。") -> void:
	screenshot.texture = null

	title_label.text = "新手引导"
	description_label.text = message
	key_label.visible = false

	page_label.text = "0 / 0"

	prev_button.disabled = true
	next_button.disabled = true
	skip_button.visible = allow_skip

	_hide_highlight()


# =========================================================
# 高亮与遮罩
# =========================================================

func _apply_highlight(slide: TutorialSlideData) -> void:
	if slide == null or not slide.show_highlight:
		_hide_highlight()
		return

	var normalized := slide.highlight_rect

	# 防止 Inspector 中误填出屏幕范围。
	var x := clampf(normalized.position.x, 0.0, 1.0)
	var y := clampf(normalized.position.y, 0.0, 1.0)
	var w := clampf(normalized.size.x, 0.0, 1.0 - x)
	var h := clampf(normalized.size.y, 0.0, 1.0 - y)

	if w <= 0.0 or h <= 0.0:
		_hide_highlight()
		return

	var viewport_size := size

	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var rect := Rect2(
		Vector2(
			x * viewport_size.x,
			y * viewport_size.y
		),
		Vector2(
			w * viewport_size.x,
			h * viewport_size.y
		)
	)

	_position_mask(mask_top, Rect2(
		Vector2.ZERO,
		Vector2(viewport_size.x, rect.position.y)
	))

	_position_mask(mask_bottom, Rect2(
		Vector2(0.0, rect.end.y),
		Vector2(
			viewport_size.x,
			maxf(0.0, viewport_size.y - rect.end.y)
		)
	))

	_position_mask(mask_left, Rect2(
		Vector2(0.0, rect.position.y),
		Vector2(rect.position.x, rect.size.y)
	))

	_position_mask(mask_right, Rect2(
		Vector2(rect.end.x, rect.position.y),
		Vector2(
			maxf(0.0, viewport_size.x - rect.end.x),
			rect.size.y
		)
	))

	highlight_frame.position = rect.position
	highlight_frame.size = rect.size

	mask_layer.visible = true
	highlight_frame.visible = true


func _position_mask(control: Control, rect: Rect2) -> void:
	if control == null:
		return

	control.position = rect.position
	control.size = rect.size


func _hide_highlight() -> void:
	mask_layer.visible = false
	highlight_frame.visible = false


func _on_tutorial_resized() -> void:
	if slides.is_empty():
		return

	if current_slide_index < 0 or current_slide_index >= slides.size():
		return

	var slide := slides[current_slide_index]
	if slide != null:
		_apply_highlight(slide)


# =========================================================
# 按钮
# =========================================================

func _on_prev_pressed() -> void:
	previous_slide()


func _on_next_pressed() -> void:
	next_slide()


func _on_skip_pressed() -> void:
	finish_tutorial()


# =========================================================
# 键盘操作
# =========================================================

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey

	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_RIGHT, KEY_SPACE, KEY_ENTER:
			next_slide()
			get_viewport().set_input_as_handled()

		KEY_LEFT:
			previous_slide()
			get_viewport().set_input_as_handled()

		KEY_ESCAPE:
			if escape_to_finish:
				finish_tutorial()
				get_viewport().set_input_as_handled()
