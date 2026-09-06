extends Area2D

enum HotspotAction {
	READ_BOOK,
	NEXT_DAY
}

@export var action: HotspotAction = HotspotAction.READ_BOOK
@export var debug_always_show: bool = false

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var highlight_polygon: Polygon2D = $Polygon2D


func _ready() -> void:
	# 关键：这个 Area2D 不再做任何运行时位置/缩放修正。
	# 你在编辑器里画的 CollisionPolygon2D 就是最终坐标。
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE

	# CollisionPolygon2D 是唯一轮廓来源。
	highlight_polygon.polygon = collision_polygon.polygon
	highlight_polygon.transform = collision_polygon.transform
	highlight_polygon.color = Color(1.0, 0.78, 0.18, 0.20)
	highlight_polygon.z_index = 10
	highlight_polygon.visible = debug_always_show

	input_pickable = true

	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)

	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)

	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)


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
