extends Panel

signal region_selected(region_name: String)

# 右手按钮
@onready var right_cun_button = $PulsePanelLayout/RightPulseButtonRow/RightCunButton
@onready var right_guan_button = $PulsePanelLayout/RightPulseButtonRow/RightGuanButton
@onready var right_chi_button = $PulsePanelLayout/RightPulseButtonRow/RightChiButton

# 左手按钮
@onready var left_cun_button = $PulsePanelLayout/LeftPulseButtonRow/LeftCunButton
@onready var left_guan_button = $PulsePanelLayout/LeftPulseButtonRow/LeftGuanButton
@onready var left_chi_button = $PulsePanelLayout/LeftPulseButtonRow/LeftChiButton


func _ready() -> void:
	# 右手
	if right_cun_button != null:
		right_cun_button.pressed.connect(_on_right_cun_button_pressed)

	if right_guan_button != null:
		right_guan_button.pressed.connect(_on_right_guan_button_pressed)

	if right_chi_button != null:
		right_chi_button.pressed.connect(_on_right_chi_button_pressed)

	# 左手
	if left_cun_button != null:
		left_cun_button.pressed.connect(_on_left_cun_button_pressed)

	if left_guan_button != null:
		left_guan_button.pressed.connect(_on_left_guan_button_pressed)

	if left_chi_button != null:
		left_chi_button.pressed.connect(_on_left_chi_button_pressed)


func _on_right_cun_button_pressed() -> void:
	emit_signal("region_selected", "右寸")


func _on_right_guan_button_pressed() -> void:
	emit_signal("region_selected", "右关")


func _on_right_chi_button_pressed() -> void:
	emit_signal("region_selected", "右尺")


func _on_left_cun_button_pressed() -> void:
	emit_signal("region_selected", "左寸")


func _on_left_guan_button_pressed() -> void:
	emit_signal("region_selected", "左关")


func _on_left_chi_button_pressed() -> void:
	emit_signal("region_selected", "左尺")
