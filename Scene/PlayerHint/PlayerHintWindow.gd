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


func _gui_input(event: InputEvent) -> void:
	if not visible or not _can_close_from_input:
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			close_hint()
			return

	if event is InputEventScreenTouch:
		if event.pressed:
			accept_event()
			close_hint()
			return


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not _can_close_from_input:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_hint()
