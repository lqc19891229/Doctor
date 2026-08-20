extends Control

signal result_closed

@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var result_text: RichTextLabel = $Panel/VBoxContainer/RichTextLabel
@onready var rating_image: TextureRect = $Panel/VBoxContainer/RatingImage  # 新增节点

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
	var experience_change: int = int(data.get("experience_change", 0))

	# 清空之前内容
	result_text.clear()

	# 上半部分：标准方信息
	result_text.append_text("病人疾病：%s\n" % disease_name)
	result_text.append_text("标准方：%s\n" % standard_formula_name)
	result_text.append_text("方剂配伍：\n%s\n\n" % standard_formula_text)

	# 下半部分：玩家输入
	result_text.append_text("断病：%s\n" % player_disease_name)
	result_text.append_text("开方：\n%s\n" % player_prescription_text)

	if show_reward_change:
		result_text.append_text("\n[b]本次治疗奖励：[/b]\n")
		result_text.append_text("名望变化：%s\n" % _format_change(reputation_change))
		result_text.append_text("心得变化：%s\n" % _format_change(experience_change))

	if not newly_unlocked_entry_titles.is_empty():
		result_text.append_text("\n[b]心得新悟：[/b]解锁新条目：%s\n" % "、".join(newly_unlocked_entry_titles))

	# -------------------------------
	# 显示评级图片
	# 新评级规则：
	# 100 分：妙手回春
	# 60~99 分：治疗成功
	# 0~59 分：治疗失败
	var grade := str(data.get("grade", "")).strip_edges()
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
	if value > 0:
		return "+%d" % value
	return str(value)


func _placeholder(text: String) -> String:
	if text.strip_edges() == "":
		return "（无）"
	return text


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton and event.pressed:
		close_result()


func close_result() -> void:
	# 防止同一帧重复点击造成重复发送关闭事件。
	if not visible:
		return

	visible = false
	get_tree().paused = false

	# 业务流程使用显式信号推进，不再依赖 tree_exited / queue_free 时机。
	result_closed.emit()

	queue_free()
