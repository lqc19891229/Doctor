extends Area2D


enum HotspotAction {
	READ_BOOK,
	NEXT_DAY
}


# 这些 Polygon 顶点是在 1920×1080 基准画面中，
# 对着 BackgroundImage 实际显示出来的内容校准的。
const REFERENCE_BACKGROUND_SIZE := Vector2(1920.0, 1080.0)


@export var action: HotspotAction = HotspotAction.READ_BOOK

# 调试时可勾选，让高亮始终显示。
@export var debug_always_show: bool = false

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var highlight_polygon: Polygon2D = $Polygon2D

var background_image: TextureRect = null
var last_texture: Texture2D = null
var last_background_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	# 高亮与碰撞区始终共用同一套 Polygon。
	highlight_polygon.polygon = collision_polygon.polygon
	highlight_polygon.transform = collision_polygon.transform
	highlight_polygon.color = Color(1.0, 0.78, 0.18, 0.20)
	highlight_polygon.z_index = 10
	highlight_polygon.visible = debug_always_show

	input_pickable = true

	background_image = get_parent() as TextureRect
	if background_image != null:
		if not background_image.resized.is_connected(_sync_to_background_image):
			background_image.resized.connect(_sync_to_background_image)
		_sync_to_background_image()

	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)

	set_process(true)


func _process(_delta: float) -> void:
	if background_image == null:
		return

	if (
		background_image.texture != last_texture
		or not background_image.size.is_equal_approx(last_background_size)
	):
		_sync_to_background_image()


func _sync_to_background_image() -> void:
	if background_image == null:
		return

	var control_size: Vector2 = background_image.size
	if control_size.x <= 0.0 or control_size.y <= 0.0:
		return

	var texture: Texture2D = background_image.texture
	if texture == null:
		return

	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	last_texture = texture
	last_background_size = control_size

	# BackgroundImage 使用 STRETCH_KEEP_ASPECT_COVERED。
	# Polygon 是在 1920×1080 基准画面中校准的，因此这里计算：
	# “基准画面里图片的 cover 结果” -> “当前画面里图片的 cover 结果”
	# 的相对变换。这样改变宽高比时 Hotspot 会跟着背景物体移动。

	var reference_texture_scale: float = maxf(
		REFERENCE_BACKGROUND_SIZE.x / texture_size.x,
		REFERENCE_BACKGROUND_SIZE.y / texture_size.y
	)

	var reference_displayed_size: Vector2 = texture_size * reference_texture_scale
	var reference_crop_offset: Vector2 = (
		REFERENCE_BACKGROUND_SIZE - reference_displayed_size
	) * 0.5

	var current_texture_scale: float = maxf(
		control_size.x / texture_size.x,
		control_size.y / texture_size.y
	)

	var current_displayed_size: Vector2 = texture_size * current_texture_scale
	var current_crop_offset: Vector2 = (
		control_size - current_displayed_size
	) * 0.5

	var mapping_scale: float = current_texture_scale / reference_texture_scale
	var mapping_offset: Vector2 = (
		current_crop_offset
		- reference_crop_offset * mapping_scale
	)

	position = mapping_offset
	scale = Vector2(mapping_scale, mapping_scale)


func _on_mouse_entered() -> void:
	highlight_polygon.visible = true


func _on_mouse_exited() -> void:
	highlight_polygon.visible = debug_always_show


func _on_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_activate()


func _activate() -> void:
	var night := _find_night_root()
	if night == null:
		return

	match action:
		HotspotAction.READ_BOOK:
			if night.has_method("open_read_book_window"):
				night.call("open_read_book_window")

		HotspotAction.NEXT_DAY:
			if night.has_method("_on_next_day_button_pressed"):
				night.call("_on_next_day_button_pressed")


func _find_night_root() -> Node:
	var node: Node = self

	while node != null:
		if node.name == "Night":
			return node
		node = node.get_parent()

	return null
