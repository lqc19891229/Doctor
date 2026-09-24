extends Control

signal result_closed

@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var result_text: RichTextLabel = $Panel/VBoxContainer/RichTextLabel
@onready var rating_image: TextureRect = $Panel/VBoxContainer/RatingImage
@onready var rating_text: Label = $Panel/VBoxContainer/RatingText

var current_result_data: Dictionary = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not current_result_data.is_empty():
		_render_result(current_result_data)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	if result_text != null:
		result_text.bbcode_enabled = true

func show_result(data: Dictionary) -> void:
	current_result_data = data.duplicate(true)
	visible = true
	get_tree().paused = true
	_render_result(current_result_data)


func _render_result(data: Dictionary) -> void:

	var disease_name: String = str(data.get("disease_name", ""))
	var standard_formula_name: String = str(data.get("standard_formula_name", ""))
	var standard_formula_text: String = str(data.get("standard_formula_text", ""))
	var player_disease_name: String = str(data.get("player_disease_name", ""))
	var player_prescription_text: String = str(data.get("player_prescription_text", ""))
	var newly_unlocked_entry_titles: Array[String] = _get_string_array(data.get("newly_unlocked_entry_titles", []))
	var show_reward_change: bool = bool(data.get("show_reward_change", false))
	var reputation_change: int = int(data.get("reputation_change", 0))
	var consultation_fee_wen: int = int(data.get("consultation_fee_wen", 0))
	var medicine_income_wen: int = int(data.get("medicine_income_wen", 0))
	var patient_thank_gift_wen: int = int(data.get("patient_thank_gift_wen", 0))
	var grade := str(data.get("grade", "")).strip_edges()

	result_text.clear()
	result_text.append_text(tr("UI_RESULT_DISEASE_FMT") % disease_name)
	result_text.append_text(tr("UI_RESULT_FORMULA_FMT") % standard_formula_name)
	result_text.append_text(tr("UI_RESULT_FORMULA_DETAIL_FMT") % standard_formula_text)
	result_text.append_text(tr("UI_RESULT_DIAGNOSIS_FMT") % player_disease_name)
	result_text.append_text(tr("UI_RESULT_PRESCRIPTION_FMT") % player_prescription_text)

	# 首次提交时始终分项显示诊费和药材收入。
	# 治疗失败时诊费为 0，药材收入为负的实际成本。
	if show_reward_change:
		var reward_parts: Array[String] = [
			tr("UI_RESULT_REPUTATION_CHANGE_FMT") % _format_change(reputation_change),
			tr("UI_RESULT_CONSULTATION_CHANGE_FMT") % _format_money_change(consultation_fee_wen),
			tr("UI_RESULT_MEDICINE_CHANGE_FMT") % _format_money_change(medicine_income_wen)
		]
		if patient_thank_gift_wen > 0:
			reward_parts.append(
				tr("UI_RESULT_GIFT_CHANGE_FMT") % _format_money_change(patient_thank_gift_wen)
			)
		result_text.append_text(tr("UI_RESULT_REWARDS_FMT") % tr("UI_RESULT_REWARD_SEPARATOR").join(reward_parts))

	if not newly_unlocked_entry_titles.is_empty():
		result_text.append_text(tr("UI_RESULT_UNLOCKED_FMT") % tr("UI_RESULT_UNLOCK_SEPARATOR").join(newly_unlocked_entry_titles))

	var rating_key := ""
	match grade:
		"妙手回春":
			rating_image.texture = preload("res://Assets/Rating/rating_miaoshouhuichun.png")
			rating_key = "UI_RESULT_GRADE_PERFECT"
		"治疗成功":
			rating_image.texture = preload("res://Assets/Rating/rating_success.png")
			rating_key = "UI_RESULT_GRADE_SUCCESS"
		"治疗失败":
			rating_image.texture = preload("res://Assets/Rating/rating_failed.png")
			rating_key = "UI_RESULT_GRADE_FAILED"
		_:
			rating_image.texture = null

	var use_english_text := TranslationServer.get_locale().begins_with("en") and not rating_key.is_empty()
	rating_image.visible = rating_image.texture != null and not use_english_text
	rating_text.visible = use_english_text
	rating_text.text = tr(rating_key) if use_english_text else ""


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
	if TranslationServer.get_locale().begins_with("en"):
		var amount := absi(value)
		var liang: int = amount / 1000
		var wen: int = amount % 1000
		var parts: Array[String] = []
		if liang > 0:
			parts.append(tr("UI_MONEY_LIANG_FMT") % liang)
		if wen > 0:
			parts.append(tr("UI_MONEY_WEN_FMT") % wen)
		if parts.is_empty():
			parts.append(tr("UI_MONEY_WEN_FMT") % 0)
		if value == 0:
			return parts[0]
		return ("+" if value > 0 else "-") + " ".join(parts)

	if Unlock != null and Unlock.has_method("format_money_change"):
		return String(Unlock.format_money_change(value))

	# 兜底：正常项目中 Unlock 应始终存在。
	if value >= 0:
		return "+%d文" % value
	return "%d文" % value


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
