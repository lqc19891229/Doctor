extends Area2D


enum HotspotAction {
	READ_BOOK,
	NEXT_DAY
}


# Hotspot 是在 Night 场景的 1920×1080 基准画面中，
# 对着 BackgroundImage 已经显示出来的内容绘制的。
# 因此改变宽高比时，必须从“基准画面的 TextureRect 裁切结果”
# 映射到“当前画面的 TextureRect 裁切结果”，不能把 Polygon 顶点
# 直接当成背景 PNG 的原始像素坐标。
const REFERENCE_BACKGROUND_SIZE := Vector2(1920.0, 1080.0)


@export var action: HotspotAction = HotspotAction.READ_BOOK

# 调试用：找不到某个 Hotspot 时可在 Inspector 中临时勾选，
# 运行后该区域会一直显示。正式游戏保持 false。
@export var debug_always_show: bool = false

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var highlight_polygon: Polygon2D = $Polygon2D

var background_image: TextureRect = null
var last_texture: Texture2D = null
var last_background_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	# 与 Clinic 一样，高亮直接复用碰撞轮廓。
	# 如果某个 CollisionPolygon2D 自带 position / scale，
	# transform 也一起复制，保证高亮与点击区域完全重合。
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

	# Night 会在不同天数切换四季背景。TextureRect 换 texture 时尺寸未必改变，
	# 因此 resized 信号不一定触发。这里仅在 texture 或控件尺寸真的变化时重算。
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

	# ---------------------------------------------------------
	# 1. 先还原 1920×1080 基准画面中 BackgroundImage 的实际绘制方式。
	# ---------------------------------------------------------
	# stretch_mode = STRETCH_KEEP_ASPECT_COVERED：
	# 等比放大到完全覆盖 Control，并把多出来的部分居中裁切。
	var reference_texture_scale: float = maxf(
		REFERENCE_BACKGROUND_SIZE.x / texture_size.x,
		REFERENCE_BACKGROUND_SIZE.y / texture_size.y
	)

	var reference_displayed_size: Vector2 = (
		texture_size * reference_texture_scale
	)
	var reference_crop_offset: Vector2 = (
		REFERENCE_BACKGROUND_SIZE - reference_displayed_size
	) * 0.5

	# ---------------------------------------------------------
	# 2. 计算当前宽高比下 BackgroundImage 的实际绘制方式。
	# ---------------------------------------------------------
	var current_texture_scale: float = maxf(
		control_size.x / texture_size.x,
		control_size.y / texture_size.y
	)

	var current_displayed_size: Vector2 = texture_size * current_texture_scale
	var current_crop_offset: Vector2 = (
		control_size - current_displayed_size
	) * 0.5

	# ---------------------------------------------------------
	# 3. 把“基准画面坐标”转换到“当前画面坐标”。
	# ---------------------------------------------------------
	# 基准画面中的点 P 对应背景纹理中的点：
	# Q = (P - reference_crop_offset) / reference_texture_scale
	#
	# 当前画面中的位置：
	# P' = current_crop_offset + Q * current_texture_scale
	#
	# 合并后得到统一的 scale + offset。
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
			# 复用原来的按钮逻辑，保留“有未读条目不能休息”的检查。
			if night.has_method("_on_next_day_button_pressed"):
				night.call("_on_next_day_button_pressed")


func _find_night_root() -> Node:
	var node: Node = self

	while node != null:
		if node.name == "Night":
			return node
		node = node.get_parent()

	return null
