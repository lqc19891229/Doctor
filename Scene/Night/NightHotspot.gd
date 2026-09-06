extends Area2D


enum HotspotAction {
	READ_BOOK,
	NEXT_DAY
}


# Night 背景与当前 Hotspot 顶点按 1920×1080 的局部坐标绘制。
const REFERENCE_BACKGROUND_SIZE := Vector2(1920.0, 1080.0)


@export var action: HotspotAction = HotspotAction.READ_BOOK

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var highlight_polygon: Polygon2D = $Polygon2D

var hotspot_container: Control = null


func _ready() -> void:
	# 和 Clinic 的 PolygonHotspot 一样：高亮直接复用碰撞轮廓。
	# Night 的 NextDayHotspot 的 CollisionPolygon2D 还带有 position/scale，
	# 因此这里同时复制 transform，确保高亮与碰撞区完全重合。
	highlight_polygon.polygon = collision_polygon.polygon
	highlight_polygon.transform = collision_polygon.transform
	highlight_polygon.color = Color(1.0, 0.78, 0.18, 0.20)
	highlight_polygon.z_index = 10
	highlight_polygon.visible = false

	input_pickable = true

	hotspot_container = get_parent() as Control
	if hotspot_container != null:
		if not hotspot_container.resized.is_connected(_sync_to_background_size):
			hotspot_container.resized.connect(_sync_to_background_size)
		_sync_to_background_size()

	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)


func _sync_to_background_size() -> void:
	if hotspot_container == null:
		return

	if hotspot_container.size.x <= 0.0 or hotspot_container.size.y <= 0.0:
		return

	# 与 Clinic 的 Hotspot 一样，窗口尺寸变化时同步缩放碰撞区和高亮区。
	scale = Vector2(
		hotspot_container.size.x / REFERENCE_BACKGROUND_SIZE.x,
		hotspot_container.size.y / REFERENCE_BACKGROUND_SIZE.y
	)


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
			# 复用原本按钮的逻辑，仍然保留“有未读条目时不能进入下一天”的检查。
			if night.has_method("_on_next_day_button_pressed"):
				night.call("_on_next_day_button_pressed")


func _find_night_root() -> Node:
	var node: Node = self

	while node != null:
		if node.name == "Night":
			return node
		node = node.get_parent()

	return null
