extends Control
class_name TutorialSlideshow

signal tutorial_finished

# 用于确认下载到的是“全屏截图聚光灯”版本，而不是旧版卡片轮播。
const BUILD_ID := "spotlight_v2_2026_09_11"

@export_category("每页内容")
@export var screenshots: Array[Texture2D] = []
@export var titles: PackedStringArray = []
@export var descriptions: PackedStringArray = []

# 每一项都是相对于整个画面的归一化坐标：
# Rect2(x, y, width, height)，四个值均为 0.0 到 1.0。
@export var focus_rects: Array[Rect2] = []

# right / left / top / bottom / auto
@export var callout_sides: PackedStringArray = []

@export_category("聚光灯外观")
@export var close_on_finish: bool = true
@export var overlay_color: Color = Color(0.0, 0.0, 0.0, 0.72)
@export var highlight_color: Color = Color(0.96, 0.73, 0.22, 1.0)
@export_range(0.0, 32.0, 1.0) var focus_padding: float = 8.0
@export_range(0.0, 80.0, 1.0) var callout_gap: float = 28.0

@onready var screenshot: TextureRect = $Screenshot
@onready var placeholder: Control = $Placeholder
@onready var shade_top: ColorRect = $ShadeLayer/ShadeTop
@onready var shade_bottom: ColorRect = $ShadeLayer/ShadeBottom
@onready var shade_left: ColorRect = $ShadeLayer/ShadeLeft
@onready var shade_right: ColorRect = $ShadeLayer/ShadeRight
@onready var highlight_border: Panel = $HighlightBorder
@onready var callout_panel: Panel = $CalloutPanel
@onready var callout_title: Label = $CalloutPanel/TitleLabel
@onready var callout_description: RichTextLabel = $CalloutPanel/DescriptionLabel
@onready var callout_arrow: Label = $CalloutArrow
@onready var page_label: Label = $BottomBar/PageLabel
@onready var previous_button: Button = $BottomBar/PreviousButton
@onready var next_button: Button = $BottomBar/NextButton
@onready var skip_button: Button = $SkipButton

var current_page: int = 0
var _finishing: bool = false


func _ready() -> void:
	if not previous_button.pressed.is_connected(_on_previous_pressed):
		previous_button.pressed.connect(_on_previous_pressed)
	if not next_button.pressed.is_connected(_on_next_pressed):
		next_button.pressed.connect(_on_next_pressed)
	if not skip_button.pressed.is_connected(_on_skip_pressed):
		skip_button.pressed.connect(_on_skip_pressed)
	if not resized.is_connected(_on_viewport_resized):
		resized.connect(_on_viewport_resized)

	_apply_colors()
	_show_page()
	next_button.grab_focus()


func open(reset_to_first_page: bool = true) -> void:
	_finishing = false
	if reset_to_first_page:
		current_page = 0
	visible = true
	_show_page()
	next_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _finishing:
		return

	if event.is_action_pressed("ui_left"):
		_on_previous_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		_on_next_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_skip_pressed()
		get_viewport().set_input_as_handled()


func _get_page_count() -> int:
	return maxi(
		maxi(screenshots.size(), titles.size()),
		maxi(descriptions.size(), maxi(focus_rects.size(), 1))
	)


func _show_page() -> void:
	var page_count := _get_page_count()
	current_page = clampi(current_page, 0, page_count - 1)

	var page_texture: Texture2D = null
	if current_page < screenshots.size():
		page_texture = screenshots[current_page]

	screenshot.texture = page_texture
	screenshot.visible = page_texture != null
	placeholder.visible = page_texture == null

	callout_title.text = (
		titles[current_page]
		if current_page < titles.size()
		else "玩法说明"
	)
	callout_description.text = (
		descriptions[current_page]
		if current_page < descriptions.size()
		else "请在 TutorialSlideshow 节点中配置这一页的说明文字。"
	)

	page_label.text = "%d / %d" % [current_page + 1, page_count]
	previous_button.disabled = current_page == 0
	next_button.text = "开始游戏" if current_page == page_count - 1 else "下一页"

	call_deferred("_update_spotlight")


func _get_normalized_focus_rect() -> Rect2:
	if current_page < focus_rects.size():
		var configured := focus_rects[current_page]
		return Rect2(
			clampf(configured.position.x, 0.0, 1.0),
			clampf(configured.position.y, 0.0, 1.0),
			clampf(configured.size.x, 0.02, 1.0),
			clampf(configured.size.y, 0.02, 1.0)
		)

	return Rect2(0.35, 0.35, 0.30, 0.20)


func _get_focus_rect_pixels() -> Rect2:
	var normalized := _get_normalized_focus_rect()
	var viewport_size := size

	var focus := Rect2(
		Vector2(
			normalized.position.x * viewport_size.x,
			normalized.position.y * viewport_size.y
		),
		Vector2(
			normalized.size.x * viewport_size.x,
			normalized.size.y * viewport_size.y
		)
	)

	focus.position -= Vector2.ONE * focus_padding
	focus.size += Vector2.ONE * focus_padding * 2.0
	focus.position.x = clampf(focus.position.x, 0.0, viewport_size.x)
	focus.position.y = clampf(focus.position.y, 0.0, viewport_size.y)
	focus.size.x = minf(focus.size.x, viewport_size.x - focus.position.x)
	focus.size.y = minf(focus.size.y, viewport_size.y - focus.position.y)
	return focus


func _update_spotlight() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return

	var focus := _get_focus_rect_pixels()
	var focus_end := focus.position + focus.size

	_set_control_rect(
		shade_top,
		Rect2(Vector2.ZERO, Vector2(size.x, focus.position.y))
	)
	_set_control_rect(
		shade_bottom,
		Rect2(
			Vector2(0.0, focus_end.y),
			Vector2(size.x, maxf(size.y - focus_end.y, 0.0))
		)
	)
	_set_control_rect(
		shade_left,
		Rect2(
			Vector2(0.0, focus.position.y),
			Vector2(focus.position.x, focus.size.y)
		)
	)
	_set_control_rect(
		shade_right,
		Rect2(
			Vector2(focus_end.x, focus.position.y),
			Vector2(maxf(size.x - focus_end.x, 0.0), focus.size.y)
		)
	)

	_set_control_rect(highlight_border, focus)
	_place_callout(focus)


func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = Vector2(maxf(rect.size.x, 0.0), maxf(rect.size.y, 0.0))


func _place_callout(focus: Rect2) -> void:
	var panel_size := callout_panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		panel_size = callout_panel.custom_minimum_size

	var side := "auto"
	if current_page < callout_sides.size():
		side = callout_sides[current_page].strip_edges().to_lower()

	if side not in ["left", "right", "top", "bottom"]:
		var right_space := size.x - (focus.position.x + focus.size.x)
		var left_space := focus.position.x
		side = "right" if right_space >= left_space else "left"

	var panel_position := Vector2.ZERO
	match side:
		"left":
			panel_position = Vector2(
				focus.position.x - panel_size.x - callout_gap,
				focus.position.y + (focus.size.y - panel_size.y) * 0.5
			)
		"top":
			panel_position = Vector2(
				focus.position.x + (focus.size.x - panel_size.x) * 0.5,
				focus.position.y - panel_size.y - callout_gap
			)
		"bottom":
			panel_position = Vector2(
				focus.position.x + (focus.size.x - panel_size.x) * 0.5,
				focus.position.y + focus.size.y + callout_gap
			)
		_:
			panel_position = Vector2(
				focus.position.x + focus.size.x + callout_gap,
				focus.position.y + (focus.size.y - panel_size.y) * 0.5
			)

	var safe_margin := 24.0
	panel_position.x = clampf(
		panel_position.x,
		safe_margin,
		maxf(size.x - panel_size.x - safe_margin, safe_margin)
	)
	panel_position.y = clampf(
		panel_position.y,
		safe_margin,
		maxf(size.y - panel_size.y - safe_margin, safe_margin)
	)
	callout_panel.position = panel_position
	_place_arrow(side, focus, panel_position, panel_size)


func _place_arrow(
	side: String,
	focus: Rect2,
	panel_position: Vector2,
	panel_size: Vector2
) -> void:
	var arrow_size := callout_arrow.size
	match side:
		"left":
			callout_arrow.text = "▶"
			callout_arrow.position = Vector2(
				panel_position.x + panel_size.x + 4.0,
				focus.position.y + focus.size.y * 0.5 - arrow_size.y * 0.5
			)
		"top":
			callout_arrow.text = "▼"
			callout_arrow.position = Vector2(
				focus.position.x + focus.size.x * 0.5 - arrow_size.x * 0.5,
				panel_position.y + panel_size.y + 2.0
			)
		"bottom":
			callout_arrow.text = "▲"
			callout_arrow.position = Vector2(
				focus.position.x + focus.size.x * 0.5 - arrow_size.x * 0.5,
				panel_position.y - arrow_size.y - 2.0
			)
		_:
			callout_arrow.text = "◀"
			callout_arrow.position = Vector2(
				panel_position.x - arrow_size.x - 4.0,
				focus.position.y + focus.size.y * 0.5 - arrow_size.y * 0.5
			)


func _apply_colors() -> void:
	for shade in [shade_top, shade_bottom, shade_left, shade_right]:
		shade.color = overlay_color

	var highlight_style := highlight_border.get_theme_stylebox("panel")
	if highlight_style is StyleBoxFlat:
		var editable_style := highlight_style.duplicate() as StyleBoxFlat
		editable_style.border_color = highlight_color
		highlight_border.add_theme_stylebox_override("panel", editable_style)

	callout_arrow.add_theme_color_override("font_color", highlight_color)


func _on_viewport_resized() -> void:
	call_deferred("_update_spotlight")


func _on_previous_pressed() -> void:
	if _finishing or current_page <= 0:
		return
	current_page -= 1
	_show_page()


func _on_next_pressed() -> void:
	if _finishing:
		return

	if current_page >= _get_page_count() - 1:
		_finish_tutorial()
		return

	current_page += 1
	_show_page()


func _on_skip_pressed() -> void:
	if _finishing:
		return
	_finish_tutorial()


func _finish_tutorial() -> void:
	if _finishing:
		return

	_finishing = true
	visible = false
	tutorial_finished.emit()

	if close_on_finish:
		queue_free()
