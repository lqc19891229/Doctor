extends Control

@onready var title_label: Label = $Panel/VBoxContainer/Label
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

	# 清空之前内容
	result_text.clear()

	# 上半部分：标准方信息
	result_text.append_text("病人疾病：%s\n" % disease_name)
	result_text.append_text("标准方：%s\n" % standard_formula_name)
	result_text.append_text("方剂配伍：\n%s\n\n" % standard_formula_text)

	# 下半部分：玩家输入
	result_text.append_text("断病：%s\n" % player_disease_name)
	result_text.append_text("开方：\n%s\n" % player_prescription_text)

	# -------------------------------
	# 显示评级图片
	match str(data.get("grade", "")):
		"妙手回春":
			rating_image.texture = preload("res://Assets/Rating/rating_miaoshouhuichun.png")
		"甲等":
			rating_image.texture = preload("res://Assets/Rating/rating_a.png")
		"乙等":
			rating_image.texture = preload("res://Assets/Rating/rating_b.png")
		"丙等":
			rating_image.texture = preload("res://Assets/Rating/rating_c.png")
		"丁等":
			rating_image.texture = preload("res://Assets/Rating/rating_d.png")
		_:
			rating_image.texture = null

	rating_image.visible = rating_image.texture != null


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
	visible = false
	get_tree().paused = false
	queue_free()
