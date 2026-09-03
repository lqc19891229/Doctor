extends Control

signal result_closed

@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var result_text: RichTextLabel = $Panel/VBoxContainer/RichTextLabel
@onready var rating_image: TextureRect = $Panel/VBoxContainer/RatingImage

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	if result_text != null:
		result_text.bbcode_enabled = true

func show_result(data: Dictionary) -> void:
	visible = true
	get_tree().paused = true

	var disease_name: String = str(data.get("disease_name", ""))
	var standard_formula_name: String = str(data.get("standard_formula_name", ""))
	var standard_formula_text: String = str(data.get("standard_formula_text", ""))
	var player_disease_name: String = str(data.get("player_disease_name", ""))
	var player_prescription_text: String = str(data.get("player_prescription_text", ""))
	var newly_unlocked_entry_titles: Array[String] = _get_string_array(data.get("newly_unlocked_entry_titles", []))
	var show_reward_change: bool = bool(data.get("show_reward_change", false))
	var reputation_change: int = int(data.get("reputation_change", 0))
	var treatment_income_wen: int = int(data.get("treatment_income_wen", 0))
	var grade := str(data.get("grade", "")).strip_edges()
	var treatment_failed := grade == "治疗失败"

	result_text.clear()
	result_text.append_text("病人疾病：%s\n" % disease_name)
	result_text.append_text("标准方：%s\n" % standard_formula_name)
	result_text.append_text("方剂配伍：\n%s\n\n" % standard_formula_text)
	result_text.append_text("断病：%s\n" % player_disease_name)
	result_text.append_text("开方：\n%s\n" % player_prescription_text)

	# 治疗失败时整个“本次治疗奖励”区域不显示。
	# 治疗成功 / 妙手回春时，在名望下方显示本次治疗收入。
	if show_reward_change and not treatment_failed:
		result_text.append_text("\n本次治疗奖励：\n")
		result_text.append_text("名望%s\n" % _format_change(reputation_change))
		result_text.append_text("治疗收入%s\n" % _format_money_change(treatment_income_wen))

	if not newly_unlocked_entry_titles.is_empty():
		result_text.append_text("\n解锁新条目：%s\n" % "、".join(newly_unlocked_entry_titles))

	match grade:
		"妙手回春":
			rating_image.texture = preload("res://Assets/Rating/rating_miaoshouhuichun.png")
		"治疗成功":
			rating_image.texture = preload("res://Assets/Rating/rating_success.png")
		"治疗失败":
			rating_image.texture = preload("res://Assets/Rating/rating_failed.png")
		_:
			rating_image.texture = null

	rating_image.visible = rating_image.texture != null


func _get_string_array(value) -> Array[String]:
	var result: Array[String] = []

	if value is Array:
		for item in value:
			var text := str(item).strip_edges()
			if text != "":
				result.append(text)

	return result


func _format_change(value: int) -> String:
	# 奖励区使用“名望+数值”的形式。
	if value >= 0:
		return "+%d" % value
	return str(value)


func _format_money_change(value: int) -> String:
	# 与银钱系统当前“两 / 文”显示格式保持一致。
	if Unlock != null and Unlock.has_method("format_money_change"):
		return String(Unlock.format_money_change(value))

	# 兜底：正常项目中 Unlock 应始终存在。
	if value >= 0:
		return "+%d文" % value
	return "%d文" % value


func _placeholder(text: String) -> String:
	if text.strip_edges() == "":
		return "（无）"
	return text


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton and event.pressed:
		# 关闭结果窗的点击不允许继续穿透到本帧新创建的 Night UI。
		get_viewport().set_input_as_handled()
		close_result()
		return

	if event is InputEventScreenTouch and event.pressed:
		get_viewport().set_input_as_handled()
		close_result()


func close_result() -> void:
	if not visible:
		return

	visible = false
	get_tree().paused = false
	result_closed.emit()
	queue_free()
