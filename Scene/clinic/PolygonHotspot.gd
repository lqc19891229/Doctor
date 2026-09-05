extends Area2D


@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var highlight_polygon: Polygon2D = $Polygon2D


func _ready() -> void:
	# 让高亮区域直接使用 CollisionPolygon2D 的轮廓
	highlight_polygon.polygon = collision_polygon.polygon

	# 黄色半透明
	highlight_polygon.color = Color(1.0, 0.78, 0.18, 0.20)

	# 默认隐藏
	highlight_polygon.visible = false

	input_pickable = true

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)


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
		_open_clinical_log_window()


func _open_clinical_log_window() -> void:
	var clinic := _find_clinic_root()

	if clinic == null:
		return

	var controller := clinic.find_child(
		"ClinicWindowController",
		true,
		false
	)

	if controller != null:
		controller.open_clinical_log_window()


func _find_clinic_root() -> Node:
	var node: Node = self

	while node != null:
		if node.name == "Clinic":
			return node

		node = node.get_parent()

	return null
