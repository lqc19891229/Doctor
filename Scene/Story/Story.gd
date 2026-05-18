extends Control

signal story_finished

# =========================================================
# Story.gd
# 独立剧情演出场景脚本。
# 负责读取 StoryData，并逐句播放 StoryLine。
#
# 当前版本规则：
# - 背景图由 StoryData.background 统一控制
# - StoryLine 只负责：类型、说话人、文本、立绘
# =========================================================

# 当前测试用剧情数据。
# 正式流程里会优先读取 StoryManager.current_story。
@export var story_data: StoryData

# StoryData.background 没设置时使用的备用背景。
@export var default_background: Texture2D

# 打字机速度，数值越大显示越快。
@export var type_speed: float = 40.0

@onready var background_rect: TextureRect = $BackgroundRect
@onready var dark_mask: ColorRect = $DarkMask
@onready var portrait_rect: TextureRect = $CharacterLayer/PortraitRect

@onready var dialogue_block: Control = $DialogueBlock
@onready var speaker_label: Label = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/SpeakerLabel
@onready var dialogue_label: RichTextLabel = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/DialogueLabel
@onready var continue_label: Label = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/ContinueLabel

@onready var subtitle_block: Control = $SubtitleBlock
@onready var subtitle_label: RichTextLabel = $SubtitleBlock/SubtitlePanel/MarginContainer/VBoxContainer/SubtitleLabel

var current_lines: Array[StoryLine] = []
var current_line_index: int = -1
var current_full_text: String = ""
var visible_character_count: int = 0
var type_timer: float = 0.0
var is_typing: bool = false
var is_finished: bool = false


func _ready() -> void:
	_setup_default_view()

	# StoryManager 是 Autoload，不是 Engine singleton
	if StoryManager.current_story != null:
		play_story(StoryManager.current_story)
		return

	if story_data != null:
		play_story(story_data)


func _process(delta: float) -> void:
	# 没有打字时不处理。
	if not is_typing:
		return

	# 按速度累积显示字符。
	type_timer += delta * type_speed

	var target_count := int(type_timer)
	if target_count > visible_character_count:
		visible_character_count = target_count
		_update_visible_text()

	# 当前句子已经显示完成。
	if visible_character_count >= current_full_text.length():
		_finish_typing()


func _unhandled_input(event: InputEvent) -> void:
	if is_finished:
		return

	# 鼠标左键、空格、回车都可以推进剧情。
	if event.is_action_pressed("ui_accept") or event is InputEventMouseButton:
		if event is InputEventMouseButton:
			if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
				return

		if is_typing:
			_show_full_text()
		else:
			advance()


func play_story(data: StoryData) -> void:
	# 记录当前剧情数据。
	story_data = data

	# 清空旧剧情。
	current_lines.clear()

	if story_data != null:
		current_lines = story_data.lines.duplicate()

	current_line_index = -1
	current_full_text = ""
	visible_character_count = 0
	type_timer = 0.0
	is_typing = false
	is_finished = false

	# 整段剧情固定背景，只在开始播放时设置一次。
	_apply_story_background()

	# 播放第一句。
	advance()


func advance() -> void:
	current_line_index += 1

	# 台词播放完毕。
	if current_line_index >= current_lines.size():
		_finish_story()
		return

	var line_data: StoryLine = current_lines[current_line_index]
	_show_line(line_data)


func _show_line(line_data: StoryLine) -> void:
	current_full_text = line_data.text
	visible_character_count = 0
	type_timer = 0.0
	is_typing = true

	continue_label.hide()

	if line_data.line_type == "subtitle":
		_show_subtitle_line(line_data)
	else:
		_show_dialogue_line(line_data)


func _show_dialogue_line(line_data: StoryLine) -> void:
	# 显示人物对话块。
	dialogue_block.show()
	subtitle_block.hide()

	# 设置说话人。
	speaker_label.text = line_data.speaker

	# 清空文本，等待打字机逐字显示。
	dialogue_label.text = ""

	# 设置人物立绘。
	if line_data.portrait != null:
		portrait_rect.texture = line_data.portrait
		portrait_rect.show()
	else:
		portrait_rect.hide()


func _show_subtitle_line(line_data: StoryLine) -> void:
	# 显示背景字幕块。
	subtitle_block.show()
	dialogue_block.hide()

	# 背景字幕通常不显示人物立绘。
	portrait_rect.hide()

	# 清空文本，等待打字机逐字显示。
	subtitle_label.text = ""


func _update_visible_text() -> void:
	var visible_text := current_full_text.substr(0, visible_character_count)

	# 根据当前显示块更新文字。
	if subtitle_block.visible:
		subtitle_label.text = visible_text
	else:
		dialogue_label.text = visible_text


func _show_full_text() -> void:
	visible_character_count = current_full_text.length()
	_update_visible_text()
	_finish_typing()


func _finish_typing() -> void:
	is_typing = false
	continue_label.show()


func _apply_story_background() -> void:
	# 背景现在由 StoryData 统一控制。
	if story_data != null and story_data.background != null:
		background_rect.texture = story_data.background
	else:
		background_rect.texture = default_background


func _setup_default_view() -> void:
	# 默认先隐藏内容块，等播放剧情时再显示。
	dialogue_block.hide()
	subtitle_block.hide()
	portrait_rect.hide()
	continue_label.hide()

	# 遮罩保留显示，用来压暗背景。
	dark_mask.show()


func _finish_story() -> void:
	is_finished = true

	# Story 不再自己 change_scene
	# 只通知 Main：剧情结束了
	emit_signal("story_finished")
