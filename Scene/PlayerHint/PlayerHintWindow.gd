extends Window
class_name PlayerHintWindow

signal confirmed

@onready var message_label: Label = $Panel/VBoxContainer/MessageLabel
@onready var ok_button: Button = $Panel/VBoxContainer/OkButton


func _ready() -> void:
	close_requested.connect(_on_close_requested)

	if ok_button != null and not ok_button.pressed.is_connected(_on_ok_button_pressed):
		ok_button.pressed.connect(_on_ok_button_pressed)

	hide()


func show_hint(message: String, title_text: String = "提示") -> void:
	title = title_text

	if message_label != null:
		message_label.text = message

	popup_centered()


func _on_ok_button_pressed() -> void:
	hide()
	confirmed.emit()


func _on_close_requested() -> void:
	hide()
	confirmed.emit()
