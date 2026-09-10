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
	# CollisionPolygon2D 是唯一轮廓数据源。
	# 高亮区始终从碰撞区同步 polygon 与 transform，避免两者发生偏移。
	_sync_highlight_polygon()
	highlight_polygon.color = Color(1.0, 0.78, 0.18, 0.20)
	highlight_polygon.visible = false

	input_pickable = true

	hotspot_container = get_parent() as Control
	if hotspot_container != null:
		if not hotspot_container.resized.is_connected(_sync_to_table_size):
			hotspot_container.resized.connect(_sync_to_table_size)
		_sync_to_table_size()

	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	if not input_event.is_connected(_on_input_event):
		input_event.connect(_on_input_event)

	set_process(true)


func _process(_delta: float) -> void:
	# 调试运行时如果直接调整 CollisionPolygon2D，
	# 正在显示的高亮也会立即跟随，不再保留 _ready() 时的旧轮廓。
	if highlight_polygon.visible:
		_sync_highlight_polygon()


func _sync_highlight_polygon() -> void:
	if collision_polygon == null or highlight_polygon == null:
		return

	highlight_polygon.polygon = collision_polygon.polygon
	highlight_polygon.transform = collision_polygon.transform


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

	# 尺寸变化后再次同步，确保高亮与碰撞区保持完全一致。
	_sync_highlight_polygon()


func _on_mouse_entered() -> void:
	# 每次准备显示前都重新读取 CollisionPolygon2D，
	# 防止运行时调整碰撞区后高亮仍使用旧数据。
	_sync_highlight_polygon()
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
