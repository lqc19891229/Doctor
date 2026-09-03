extends Control
class_name PlayerHintWindow

signal confirmed

@onready var message_label: Label = $Panel/VBoxContainer/MessageLabel

var _is_closing := false
var _can_close_from_input := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	z_index = 1000
	hide()


func show_hint(message: String, _title_text: String = "提示") -> void:
	_is_closing = false
	_can_close_from_input = false

	if message_label != null:
		message_label.text = message

	show()
	move_to_front()
	grab_focus()

	# 防止“关闭上一个窗口”的同一次点击穿透到刚显示的提示窗口。
	# 下一帧才允许鼠标 / 键盘关闭。
	call_deferred("_enable_close_input")


func _enable_close_input() -> void:
	if visible:
		_can_close_from_input = true


func close_hint() -> void:
	if _is_closing:
		return

	_is_closing = true
	_can_close_from_input = false
	hide()
	confirmed.emit()


func _input(event: InputEvent) -> void:
	# 使用全局输入而不是根 Control 的 _gui_input()。
	# 这样即使点击落在 PanelContainer / Label 等子 Control 上，
	# PlayerHintWindow 仍然能够收到关闭点击。
	if not visible or not _can_close_from_input:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if (
			mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_LEFT
		):
			get_viewport().set_input_as_handled()
			close_hint()
			return

	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			get_viewport().set_input_as_handled()
			close_hint()
			return


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not _can_close_from_input:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_hint()
