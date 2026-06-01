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
# - dialogue 类型会优先根据 StoryLine.portrait_side 手动指定左右立绘位置
# - portrait_side 为 auto 或空时，才根据 speaker 自动分配左右立绘位置
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

# 左右两个立绘槽。
@onready var left_portrait_rect: TextureRect = $CharacterLayer/LeftPortraitRect
@onready var right_portrait_rect: TextureRect = $CharacterLayer/RightPortraitRect

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

# speaker -> "left" / "right"。
# 同一个 speaker 固定站位，避免每句话左右乱跳。
var speaker_side_map: Dictionary = {}

# speaker -> Texture2D。
# 同一个 speaker 后续台词没填 portrait 时，沿用之前的立绘。
var speaker_portrait_map: Dictionary = {}

# 下一个新 speaker 分配到哪一侧。
var next_speaker_side: String = "left"


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
	speaker_side_map.clear()
	speaker_portrait_map.clear()
	next_speaker_side = "left"

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

	# 根据 speaker 显示左右立绘。
	_show_speaker_portrait(line_data)


func _show_subtitle_line(line_data: StoryLine) -> void:
	# 显示背景字幕块。
	subtitle_block.show()
	dialogue_block.hide()

	# 背景字幕通常不显示人物立绘。
	_hide_all_portraits()

	# 清空文本，等待打字机逐字显示。
	subtitle_label.text = ""


func _show_speaker_portrait(line_data: StoryLine) -> void:
	if line_data.speaker.is_empty():
		_hide_all_portraits()
		return

	# 如果当前台词带了新立绘，则记录到该 speaker 名下。
	if line_data.portrait != null:
		speaker_portrait_map[line_data.speaker] = line_data.portrait

	# 如果当前台词没带立绘，则尝试沿用这个 speaker 之前出现过的立绘。
	var portrait: Texture2D = speaker_portrait_map.get(line_data.speaker, null)

	if portrait == null:
		_hide_all_portraits()
		return

	var side := _get_line_portrait_side(line_data)

	var active_rect: TextureRect
	var inactive_rect: TextureRect

	if side == "left":
		active_rect = left_portrait_rect
		inactive_rect = right_portrait_rect
	else:
		active_rect = right_portrait_rect
		inactive_rect = left_portrait_rect

	active_rect.texture = portrait
	active_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
	active_rect.show()

	# 另一侧如果已有角色立绘，保留但压暗。
	# 这样可以形成“当前说话人亮，另一人暗”的对话效果。
	if inactive_rect.texture != null:
		inactive_rect.modulate = Color(0.55, 0.55, 0.55, 0.72)
		inactive_rect.show()
	else:
		inactive_rect.hide()


func _get_speaker_side(speaker: String) -> String:
	if speaker_side_map.has(speaker):
		return speaker_side_map[speaker]

	var side := next_speaker_side
	speaker_side_map[speaker] = side

	if next_speaker_side == "left":
		next_speaker_side = "right"
	else:
		next_speaker_side = "left"

	return side


func _get_line_portrait_side(line_data: StoryLine) -> String:
	var portrait_side := "auto"

	# 兼容旧资源：如果 StoryLine.gd 还没加 portrait_side，避免直接报错。
	if "portrait_side" in line_data:
		portrait_side = String(line_data.portrait_side).strip_edges().to_lower()

	if portrait_side == "left" or portrait_side == "right":
		# 手动指定时，顺便更新 speaker 的固定站位。
		# 这样后续同 speaker 如果写 auto 或空，也会沿用这个手动站位。
		speaker_side_map[line_data.speaker] = portrait_side
		return portrait_side

	return _get_speaker_side(line_data.speaker)


func _hide_all_portraits() -> void:
	left_portrait_rect.hide()
	right_portrait_rect.hide()


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
	_hide_all_portraits()
	continue_label.hide()

	# 遮罩保留显示，用来压暗背景。
	dark_mask.show()


func _finish_story() -> void:
	is_finished = true

	# Story 不再自己 change_scene
	# 只通知 Main：剧情结束了
	emit_signal("story_finished")
