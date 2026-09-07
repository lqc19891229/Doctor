extends Area2D

enum HotspotAction {
	READ_BOOK,
	NEXT_DAY
}

# 与 clinic/TableImage 完全相同的参考尺寸。
const REFERENCE_TABLE_SIZE := Vector2(1920.0, 841.0)

@export var action: HotspotAction = HotspotAction.READ_BOOK
@export var debug_always_show: bool = false

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var highlight_polygon: Polygon2D = $Polygon2D

var hotspot_container: Control = null


func _ready() -> void:
	# CollisionPolygon2D 是唯一轮廓来源。
	highlight_polygon.polygon = collision_polygon.polygon
	highlight_polygon.transform = collision_polygon.transform
	highlight_polygon.color = Color(1.0, 0.78, 0.18, 0.20)
	highlight_polygon.z_index = 10
	highlight_polygon.visible = debug_always_show

	input_pickable = true

	# 当前直接父节点是 DeskHotspots(Control)，不是 TextureRect。
	# 与 clinic 一样，按这个容器的实际尺寸同步热点缩放。
	hotspot_container = get_parent() as Control
	if hotspot_container != null:
		if not hotspot_container.resized.is_connected(_sync_to_table_size):
			hotspot_container.resized.connect(_sync_to_table_size)
		call_deferred("_sync_to_table_size")

	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)


func _sync_to_table_size() -> void:
	if hotspot_container == null:
		return

	var current_size := hotspot_container.size
	if current_size.x <= 0.0 or current_size.y <= 0.0:
		return

	# Hotspot 坐标统一以 TableImage 的 1920×841 为参考。
	position = Vector2.ZERO
	scale = Vector2(
		current_size.x / REFERENCE_TABLE_SIZE.x,
		current_size.y / REFERENCE_TABLE_SIZE.y
	)


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
