extends Control


const MAIN_SCENE_PATH: String = "res://Scene/Main/Main.tscn"

## 声明画面的总停留时间，包含淡入和淡出。
@export_range(0.5, 10.0, 0.1) var display_duration: float = 2.0
@export_range(0.0, 1.0, 0.05) var fade_duration: float = 0.25

@onready var statement_container: VBoxContainer = %StatementContainer


func _ready() -> void:
	statement_container.modulate.a = 0.0

	var actual_fade_duration: float = minf(
		fade_duration,
		display_duration * 0.5
	)
	var hold_duration: float = maxf(
		display_duration - actual_fade_duration * 2.0,
		0.0
	)

	var tween := create_tween()
	tween.tween_property(
		statement_container,
		"modulate:a",
		1.0,
		actual_fade_duration
	)
	tween.tween_interval(hold_duration)
	tween.tween_property(
		statement_container,
		"modulate:a",
		0.0,
		actual_fade_duration
	)

	await tween.finished

	var error := get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	if error != OK:
		push_error(
			"无法从免责声明进入主场景，错误代码：%s" % error
		)

