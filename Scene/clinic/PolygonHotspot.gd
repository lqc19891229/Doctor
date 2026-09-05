extends Area2D


enum HotspotAction {
	PULSE,
	PRESCRIPTION,
	CLINICAL_LOG
}


# Polygon 顶点绘制时的 TableImage 基准尺寸。
# 当前这些顶点按 1920×841 的 TableImage 局部坐标保存。
const REFERENCE_TABLE_SIZE := Vector2(1920.0, 841.0)


@export var action: HotspotAction = HotspotAction.PULSE

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var highlight_polygon: Polygon2D = $Polygon2D

var hotspot_container: Control = null


func _ready() -> void:
	# 高亮直接复用碰撞轮廓，只需要在编辑器里维护一套点。
	highlight_polygon.polygon = collision_polygon.polygon
	highlight_polygon.color = Color(1.0, 0.78, 0.18, 0.20)
	highlight_polygon.visible = false

	input_pickable = true

	hotspot_container = get_parent() as Control
	if hotspot_container != null:
		if not hotspot_container.resized.is_connected(_sync_to_table_size):
			hotspot_container.resized.connect(_sync_to_table_size)
		_sync_to_table_size()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)


func _sync_to_table_size() -> void:
	if hotspot_container == null:
		return

	if hotspot_container.size.x <= 0.0 or hotspot_container.size.y <= 0.0:
		return

	# TableImage 改变尺寸时，碰撞区与高亮区一起按桌面缩放。
	scale = Vector2(
		hotspot_container.size.x / REFERENCE_TABLE_SIZE.x,
		hotspot_container.size.y / REFERENCE_TABLE_SIZE.y
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
	var clinic := _find_clinic_root()
	if clinic == null:
		return

	var controller := clinic.find_child(
		"ClinicWindowController",
		true,
		false
	)

	if controller == null:
		return

	match action:
		HotspotAction.PULSE:
			controller.open_pulse_window()

		HotspotAction.PRESCRIPTION:
			controller.open_prescription_window()

		HotspotAction.CLINICAL_LOG:
			controller.open_clinical_log_window()


func _find_clinic_root() -> Node:
	var node: Node = self

	while node != null:
		if node.name == "Clinic":
			return node

		node = node.get_parent()

	return null
