extends Control
class_name PlayerHintWindow

signal confirmed

@onready var message_label: Label = $Panel/VBoxContainer/MessageLabel

var _is_closing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	hide()


func show_hint(message: String, _title_text: String = "提示") -> void:
	_is_closing = false

	if message_label != null:
		message_label.text = message

	show()
	move_to_front()
	grab_focus()


func close_hint() -> void:
	if _is_closing:
		return

	_is_closing = true
	hide()
	confirmed.emit()


func _gui_input(event: InputEvent) -> void:
	if not visible:
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
	if not visible:
		return

	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_hint()
