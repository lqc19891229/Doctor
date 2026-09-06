extends Area2D


enum HotspotAction {
	READ_BOOK,
	NEXT_DAY
}


@export var action: HotspotAction = HotspotAction.READ_BOOK

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var highlight_polygon: Polygon2D = $Polygon2D

# Hotspot 的父节点就是 Night 的 BackgroundImage(TextureRect)。
var background_image: TextureRect = null


func _ready() -> void:
	# 高亮直接复用碰撞轮廓。
	# NextDayHotspot 的碰撞节点本身带 position / scale，
	# 所以 transform 也一起复制，保证高亮与碰撞完全重合。
	highlight_polygon.polygon = collision_polygon.polygon
	highlight_polygon.transform = collision_polygon.transform
	highlight_polygon.color = Color(1.0, 0.78, 0.18, 0.20)
	highlight_polygon.z_index = 10
	highlight_polygon.visible = false

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

	# BackgroundImage 当前使用 TextureRect.STRETCH_KEEP_ASPECT_COVERED。
	# 这种模式不是把图片分别拉伸到控件宽高，而是：
	# 1. 按同一个比例等比放大，直到完全覆盖控件。
	# 2. 超出控件的部分从两边居中裁掉。
	#
	# Hotspot 的坐标是在原始背景图片坐标中绘制的，
	# 因此必须使用完全相同的 scale + offset 才不会在改变宽高比后偏移。
	var cover_scale: float = maxf(
		control_size.x / texture_size.x,
		control_size.y / texture_size.y
	)

	var displayed_size: Vector2 = texture_size * cover_scale
	var crop_offset: Vector2 = (control_size - displayed_size) * 0.5

	position = crop_offset
	scale = Vector2(cover_scale, cover_scale)


func _on_mouse_entered() -> void:
	highlight_polygon.visible = true


func _on_mouse_exited() -> void:
	highlight_polygon.visible = false


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
			# 复用原来的按钮逻辑，保留未读条目检查。
			if night.has_method("_on_next_day_button_pressed"):
				night.call("_on_next_day_button_pressed")


func _find_night_root() -> Node:
	var node: Node = self

	while node != null:
		if node.name == "Night":
			return node
		node = node.get_parent()

	return null
