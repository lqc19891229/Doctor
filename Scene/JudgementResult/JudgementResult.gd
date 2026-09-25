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
	var disease_id: String = str(data.get("disease_id", "")).strip_edges()
	var standard_formula_name: String = str(data.get("standard_formula_name", ""))
	var standard_formula_id: String = str(data.get("standard_formula_id", "")).strip_edges()
	var standard_formula_text: String = str(data.get("standard_formula_text", ""))
	var player_disease_name: String = str(data.get("player_disease_name", ""))
	var player_disease_id: String = str(data.get("player_disease_id", "")).strip_edges()
	var player_prescription_text: String = str(data.get("player_prescription_text", ""))
	var newly_unlocked_entry_titles: Array[String] = _get_string_array(data.get("newly_unlocked_entry_titles", []))
	var show_reward_change: bool = bool(data.get("show_reward_change", false))
	var reputation_change: int = int(data.get("reputation_change", 0))
	var consultation_fee_wen: int = int(data.get("consultation_fee_wen", 0))
	var medicine_income_wen: int = int(data.get("medicine_income_wen", 0))
	var patient_thank_gift_wen: int = int(data.get("patient_thank_gift_wen", 0))
	var grade := str(data.get("grade", "")).strip_edges()
	var grade_level := str(data.get("grade_level", "")).strip_edges().to_lower()
	var is_english := TranslationServer.get_locale().to_lower().begins_with("en")

	# 结果数据仍保留原始中文名称 / ID；英文环境只在显示层本地化。
	# 这样切换语言时可立即重新渲染，不影响处方判定和存档数据。
	if is_english:
		if disease_id != "":
			disease_name = LocalizedName.disease(disease_id, disease_name)

		if standard_formula_id != "":
			standard_formula_name = LocalizedName.formula(standard_formula_id, standard_formula_name)

		var standard_formula = data.get("standard_formula_resource", null)
		if standard_formula is FormulaData:
			standard_formula_text = _format_formula_for_english(standard_formula)
		elif standard_formula_text == "（未找到标准方）":
			standard_formula_text = tr("UI_RESULT_FORMULA_NOT_FOUND")

		var prescription = data.get("player_prescription_resource", null)
		if prescription is Prescription:
			player_prescription_text = _format_prescription_for_english(prescription)
		elif player_prescription_text == "（无）":
			player_prescription_text = tr("UI_RESULT_NONE")

		if player_disease_id != "":
			player_disease_name = LocalizedName.disease(player_disease_id, player_disease_name)
		elif player_disease_name == "未选择疾病":
			player_disease_name = tr("UI_RESULT_NO_DIAGNOSIS")

	# 结果排版统一为：
	# 病人疾病：xxx，标准方：xxx
	# 方剂配伍：
	# 君 / 臣 / 佐 / 使
	#
	# 断病：xxx
	# 开方：
	# 君 / 臣 / 佐 / 使
	#
	# 本次治疗奖励：
	var sections: Array[String] = []

	var disease_line := (tr("UI_RESULT_DISEASE_FMT") % disease_name).strip_edges()
	var formula_line := (tr("UI_RESULT_FORMULA_FMT") % standard_formula_name).strip_edges()
	var inline_separator := tr("UI_RESULT_REWARD_SEPARATOR")
	if is_english:
		inline_separator += " "

	var standard_block := disease_line + inline_separator + formula_line
	standard_block += "\n" + (tr("UI_RESULT_FORMULA_DETAIL_FMT") % standard_formula_text).strip_edges()
	sections.append(standard_block)

	var prescription_block := (tr("UI_RESULT_DIAGNOSIS_FMT") % player_disease_name).strip_edges()
	prescription_block += "\n" + (tr("UI_RESULT_PRESCRIPTION_FMT") % player_prescription_text).strip_edges()
	sections.append(prescription_block)

	# 首次提交时分项显示诊费和药材收入。
	# 每一项独占一行，保持结果区结构清晰。
	if show_reward_change:
		var reward_lines: Array[String] = [
			tr("UI_RESULT_REPUTATION_CHANGE_FMT") % _format_change(reputation_change),
			tr("UI_RESULT_CONSULTATION_CHANGE_FMT") % _format_money_change(consultation_fee_wen),
			tr("UI_RESULT_MEDICINE_CHANGE_FMT") % _format_money_change(medicine_income_wen)
		]
		if patient_thank_gift_wen > 0:
			reward_lines.append(
				tr("UI_RESULT_GIFT_CHANGE_FMT") % _format_money_change(patient_thank_gift_wen)
			)

		var reward_title := (tr("UI_RESULT_REWARDS_FMT") % "").strip_edges()
		sections.append(reward_title + "\n" + "\n".join(reward_lines))

	if not newly_unlocked_entry_titles.is_empty():
		if is_english:
			for index in range(newly_unlocked_entry_titles.size()):
				newly_unlocked_entry_titles[index] = _localized_unlock_title(newly_unlocked_entry_titles[index])
		sections.append(
			(tr("UI_RESULT_UNLOCKED_FMT") % tr("UI_RESULT_UNLOCK_SEPARATOR").join(newly_unlocked_entry_titles)).strip_edges()
		)

	result_text.clear()
	result_text.append_text("\n\n".join(sections))

	# 显示判定优先使用 FormulaJudge 的稳定内部 level。
	# 旧数据没有 level 时继续兼容中文 grade。
	var rating_key := ""
	match grade_level:
		"perfect":
			rating_image.texture = preload("res://Assets/Rating/rating_miaoshouhuichun.png")
			rating_key = "UI_RESULT_GRADE_PERFECT"
		"pass":
			rating_image.texture = preload("res://Assets/Rating/rating_success.png")
			rating_key = "UI_RESULT_GRADE_SUCCESS"
		"fail":
			rating_image.texture = preload("res://Assets/Rating/rating_failed.png")
			rating_key = "UI_RESULT_GRADE_FAILED"
		_:
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

	var use_english_text := is_english and not rating_key.is_empty()
	rating_image.visible = rating_image.texture != null and not use_english_text
	rating_text.visible = use_english_text
	rating_text.text = tr(rating_key) if use_english_text else ""


func _format_formula_for_english(formula: FormulaData) -> String:
	var groups := [
		["UI_PRESCRIPTION_ROLE_JUN", formula.jun_group],
		["UI_PRESCRIPTION_ROLE_CHEN", formula.chen_group],
		["UI_PRESCRIPTION_ROLE_ZUO", formula.zuo_group],
		["UI_PRESCRIPTION_ROLE_SHI", formula.shi_group]
	]
	var lines: Array[String] = []
	for role_data in groups:
		var parts: Array[String] = []
		for ingredient in role_data[1]:
			if ingredient == null:
				continue
			if ingredient.has_method("is_valid_data") and not ingredient.is_valid_data():
				continue
			var herb_id := ""
			var herb_name := ""
			if ingredient.has_method("get_herb_id"):
				herb_id = str(ingredient.get_herb_id()).strip_edges()
			if ingredient.has_method("get_herb_name"):
				herb_name = str(ingredient.get_herb_name()).strip_edges()
			if herb_name == "":
				herb_name = herb_id
			if herb_id != "":
				herb_name = LocalizedName.herb(herb_id, herb_name)
			if herb_name == "":
				continue
			var amount := ""
			if ingredient.has_method("get_amount_in_fen"):
				amount = _format_dose_for_english(int(ingredient.get_amount_in_fen()))
			if amount == "":
				parts.append(herb_name)
			else:
				parts.append("%s %s" % [herb_name, amount])
		var content := tr("UI_RESULT_NONE") if parts.is_empty() else tr("UI_RESULT_UNLOCK_SEPARATOR").join(parts)
		lines.append(tr("UI_RESULT_ROLE_LINE_FMT") % [tr(role_data[0]), content])
	return "\n".join(lines)


func _format_prescription_for_english(prescription: Prescription) -> String:
	var roles := [
		["君", "UI_PRESCRIPTION_ROLE_JUN"],
		["臣", "UI_PRESCRIPTION_ROLE_CHEN"],
		["佐", "UI_PRESCRIPTION_ROLE_ZUO"],
		["使", "UI_PRESCRIPTION_ROLE_SHI"]
	]
	var lines: Array[String] = []
	for role_data in roles:
		var parts: Array[String] = []
		for item in prescription.get_herbs_by_role(role_data[0]):
			var herb_id := str(item.get("herb_id", "")).strip_edges()
			var herb_name := str(item.get("herb_name", "")).strip_edges()
			if herb_name == "":
				herb_name = herb_id
			if herb_id != "":
				herb_name = LocalizedName.herb(herb_id, herb_name)
			if herb_name == "":
				continue
			var amount := float(item.get("amount", 0.0))
			var unit := str(item.get("unit", ""))
			parts.append("%s %s" % [herb_name, _format_dose_for_english(HerbUnit.to_fen(amount, unit))])
		var content := tr("UI_RESULT_NONE") if parts.is_empty() else tr("UI_RESULT_UNLOCK_SEPARATOR").join(parts)
		lines.append(tr("UI_RESULT_ROLE_LINE_FMT") % [tr(role_data[1]), content])
	return "\n".join(lines)


func _format_dose_for_english(total_fen: int) -> String:
	if total_fen <= 0:
		return tr("UI_PRESCRIPTION_ZERO_FEN")

	var remaining := total_fen
	var parts: Array[String] = []
	for unit_data in [
		[HerbUnit.FEN_PER_JIN, "UI_PRESCRIPTION_UNIT_JIN"],
		[HerbUnit.FEN_PER_LIANG, "UI_PRESCRIPTION_UNIT_LIANG"],
		[HerbUnit.FEN_PER_QIAN, "UI_PRESCRIPTION_UNIT_QIAN"],
		[HerbUnit.FEN_PER_FEN, "UI_PRESCRIPTION_UNIT_FEN"]
	]:
		var unit_size: int = unit_data[0]
		var count: int = remaining / unit_size
		if count > 0:
			parts.append("%d %s" % [count, tr(unit_data[1])])
			remaining %= unit_size
	return " ".join(parts)


func _localized_unlock_title(value: String) -> String:
	if value == "预制方剂":
		return tr("UI_RESULT_PRESET_UNLOCK")
	if value.begins_with("预制方剂："):
		return tr("UI_RESULT_PRESET_UNLOCK_FMT") % value.trim_prefix("预制方剂：")
	return value


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
