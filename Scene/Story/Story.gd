extends Control

signal story_finished
signal story_treatment_requested(npc_id: String)
signal followup_story_requested(story: StoryData, resume_treatment: bool)

const JUDGEMENT_RESULT_SCENE: PackedScene = preload(
	"res://Scene/JudgementResult/JudgementResult.tscn"
)

# =========================================================
# Story.gd
# 独立剧情演出场景脚本。
# 负责读取 StoryData，并逐句播放 StoryLine。
#
# 当前版本规则：
# - 背景图只由 StoryLine.background 控制
# - 当前台词没有设置背景时，继续沿用上一句背景
# - 每段新剧情开始时，先重置为 default_background
# - StoryLine 负责：类型、说话人、文本、背景、立绘
# - dialogue 类型会优先根据 StoryLine.portrait_side 手动指定左、中、右立绘位置
# - portrait_side 为 auto 或空时，才根据 speaker 自动分配左右立绘位置
# - inactive_portrait_mode 为 dim 时，当前说话人在本句结束后继续留在画面
# - inactive_portrait_mode 为 hide 时，从本句推进到下一句时当前说话人退出画面
#
# 本版本修复：
# - 打字机效果不再通过 substr() 逐字修改 RichTextLabel.text
# - 改为先写入完整文本，再用 visible_characters 控制显示数量
# - 避免 DialogueLabel 高度在打字过程中不断变化，导致 SpeakerLabel 被容器重排后轻微下移
# =========================================================

# 当前测试用剧情数据。
# 正式流程里会优先读取 StoryManager.current_story。
@export var story_data: StoryData

# 每段新剧情开始时使用的默认背景。
@export var default_background: Texture2D

# 打字机速度，数值越大显示越快。
@export var type_speed: float = 40.0

# 长按回车跳过整段剧情需要持续按住的秒数。
@export var enter_skip_hold_seconds: float = 1.0

@onready var background_rect: TextureRect = $BackgroundRect
@onready var dark_mask: ColorRect = $DarkMask

# 左、中、右三个立绘槽。
@onready var left_portrait_rect: TextureRect = $CharacterLayer/LeftPortraitRect
@onready var mid_portrait_rect: TextureRect = $CharacterLayer/MidPortraitRect
@onready var right_portrait_rect: TextureRect = $CharacterLayer/RightPortraitRect

@onready var dialogue_block: Control = $DialogueBlock
@onready var speaker_label: Label = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/SpeakerLabel
@onready var dialogue_label: RichTextLabel = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/DialogueLabel
@onready var continue_label: Label = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/ContinueLabel
@onready var treatment_option_container: HBoxContainer = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/TreatmentOptionContainer
@onready var pulse_button: Button = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/TreatmentOptionContainer/PulseButton
@onready var prescription_button: Button = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/TreatmentOptionContainer/PrescriptionButton
@onready var clinical_log_button: Button = $DialogueBlock/DialoguePanel/MarginContainer/VBoxContainer/TreatmentOptionContainer/ClinicalLogButton

@onready var subtitle_block: Control = $SubtitleBlock
@onready var subtitle_label: RichTextLabel = $SubtitleBlock/SubtitlePanel/MarginContainer/VBoxContainer/SubtitleLabel

@onready var pulse_window: Window = $PulseWindow
@onready var prescription_window: Window = $PrescriptionWindow
@onready var clinical_log_window: Window = $ClinicalLogWindow
@onready var judgement_result_host: Control = $JudgementResultHost
@onready var initial_judgement_result: Control = $JudgementResultHost/JudgementResult

var current_lines: Array[StoryLine] = []
var current_line_index: int = -1
var current_full_text: String = ""
var visible_character_count: int = 0
var type_timer: float = 0.0
var is_typing: bool = false
var is_finished: bool = false

var enter_hold_active: bool = false
var enter_hold_time: float = 0.0
var enter_skip_triggered: bool = false

# speaker -> "left" / "mid" / "right"。
# 同一个 speaker 固定站位，避免每句话位置乱跳。
var speaker_side_map: Dictionary = {}

# speaker -> Texture2D。
# 同一个 speaker 后续台词没填 portrait 时，沿用之前的立绘。
var speaker_portrait_map: Dictionary = {}

# 下一个新 speaker 分配到哪一侧。
# auto 仍然只在 left 和 right 之间交替。
var next_speaker_side: String = "left"

# Story 画面中的诊疗状态。业务数据由 Main 注入的隐藏 Clinic 后端持有。
var treatment_backend: Node = null
var treatment_npc_id: String = ""
var treatment_trigger_scene: String = "clinic"
var is_treatment_mode: bool = false
var waiting_for_treatment_backend: bool = false
var resume_treatment_after_story: bool = false
var last_treatment_success: bool = false
var judgement_result_window: Control = null

var pulse_keyboard_override_active: bool = false
var last_pulse_input_signature: String = ""


func _ready() -> void:
	_setup_default_view()
	_connect_treatment_signals()

	# StoryManager 是 Autoload，不是 Engine singleton
	if StoryManager.current_story != null:
		play_story(StoryManager.current_story)
		return

	if story_data != null:
		play_story(story_data)


func _process(delta: float) -> void:
	if is_treatment_mode and pulse_window != null and pulse_window.visible:
		_update_story_pulse_keyboard_display()

	_update_enter_hold_skip(delta)

	# 没有打字时不处理打字机效果。
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

	if waiting_for_treatment_backend:
		return

	if is_treatment_mode:
		_handle_treatment_shortcut(event)
		return

	# 回车：按下时开始计时，短按松开推进，长按跳过整段剧情。
	# 这样可以保留原本“回车推进剧情”的手感，同时增加“长按回车跳过”。
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if _is_enter_key_event(key_event):
			_handle_enter_key_event(key_event)
			get_viewport().set_input_as_handled()
			return

	# 鼠标左键、空格仍然可以直接推进剧情。
	if event is InputEventMouseButton:
		if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
			return
		_advance_or_show_full_text()
		return

	if event.is_action_pressed("ui_accept"):
		_advance_or_show_full_text()


func _is_enter_key_event(key_event: InputEventKey) -> bool:
	return key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER


func _handle_enter_key_event(key_event: InputEventKey) -> void:
	if key_event.echo:
		return

	if key_event.pressed:
		enter_hold_active = true
		enter_hold_time = 0.0
		enter_skip_triggered = false
		return

	# 松开时如果没有触发长按跳过，就按普通回车处理：显示完整当前句 / 推进下一句。
	if enter_hold_active and not enter_skip_triggered:
		_advance_or_show_full_text()

	_reset_enter_hold_state()


func _update_enter_hold_skip(delta: float) -> void:
	if is_finished or is_treatment_mode or waiting_for_treatment_backend:
		_reset_enter_hold_state()
		return

	if not enter_hold_active:
		return

	enter_hold_time += delta

	if enter_hold_time < enter_skip_hold_seconds:
		return

	enter_skip_triggered = true
	enter_hold_active = false
	_skip_current_story()


func _reset_enter_hold_state() -> void:
	enter_hold_active = false
	enter_hold_time = 0.0
	enter_skip_triggered = false


func _advance_or_show_full_text() -> void:
	if is_typing:
		_show_full_text()
	else:
		advance()


func _skip_current_story() -> void:
	if is_finished:
		return

	is_typing = false
	current_line_index = current_lines.size()
	_finish_story()


func play_story(
	data: StoryData,
	preserve_stage: bool = false,
	resume_treatment_when_finished: bool = false
) -> void:
	# 记录当前剧情数据。
	story_data = data

	# 清空旧剧情。
	current_lines.clear()
	if not preserve_stage:
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
	is_treatment_mode = false
	waiting_for_treatment_backend = false
	resume_treatment_after_story = resume_treatment_when_finished
	_reset_enter_hold_state()

	_reset_text_labels()
	treatment_option_container.hide()
	_close_treatment_windows()

	# 每段新剧情开始时重置背景。
	# 后续只由 StoryLine.background 控制切换。
	if not preserve_stage:
		_reset_story_background()

	# 播放第一句。
	advance()


func play_followup_story(data: StoryData, resume_treatment: bool) -> void:
	# 诊疗结果剧情仍在同一个 Story 实例中播放，保留最后的背景和人物站位。
	play_story(data, true, resume_treatment)


# =========================================================
# Story 场景内诊疗
# =========================================================

func _connect_treatment_signals() -> void:
	if not pulse_button.pressed.is_connected(_on_pulse_button_pressed):
		pulse_button.pressed.connect(_on_pulse_button_pressed)

	if not prescription_button.pressed.is_connected(_on_prescription_button_pressed):
		prescription_button.pressed.connect(_on_prescription_button_pressed)

	if not clinical_log_button.pressed.is_connected(_on_clinical_log_button_pressed):
		clinical_log_button.pressed.connect(_on_clinical_log_button_pressed)

	var info_callable := Callable(self, "_on_prescription_info_requested")
	if prescription_window.has_signal("info_requested"):
		if not prescription_window.is_connected("info_requested", info_callable):
			prescription_window.connect("info_requested", info_callable)

	var submit_callable := Callable(self, "_on_prescription_submit_requested")
	if prescription_window.has_signal("submit_requested"):
		if not prescription_window.is_connected("submit_requested", submit_callable):
			prescription_window.connect("submit_requested", submit_callable)


func start_story_npc_treatment(backend: Node, npc_id: String) -> void:
	if backend == null or not is_instance_valid(backend):
		cancel_story_treatment("Story 没有获得可用的 Clinic 诊疗后端。")
		return

	treatment_backend = backend
	treatment_npc_id = npc_id.strip_edges()
	waiting_for_treatment_backend = false

	if story_data != null:
		treatment_trigger_scene = story_data.trigger_scene.strip_edges()
	if treatment_trigger_scene == "":
		treatment_trigger_scene = "clinic"

	_show_treatment_options()


func cancel_story_treatment(message: String) -> void:
	waiting_for_treatment_backend = false
	is_treatment_mode = false
	push_warning(message)
	emit_signal("story_finished")


func _show_treatment_options() -> void:
	if treatment_backend == null or not is_instance_valid(treatment_backend):
		cancel_story_treatment("Clinic 诊疗后端已经失效。")
		return

	is_treatment_mode = true
	is_finished = false
	is_typing = false
	resume_treatment_after_story = false
	_reset_enter_hold_state()
	_close_treatment_windows()

	dialogue_block.show()
	subtitle_block.hide()
	continue_label.hide()

	var npc_name := ""
	if treatment_backend.has_method("get_story_treatment_npc_name"):
		npc_name = str(treatment_backend.call("get_story_treatment_npc_name")).strip_edges()

	speaker_label.text = npc_name if npc_name != "" else "诊疗"
	dialogue_label.text = "请选择诊疗项目。"
	dialogue_label.visible_characters = -1
	treatment_option_container.show()


func _show_treatment_message(message: String) -> void:
	dialogue_block.show()
	subtitle_block.hide()
	speaker_label.text = "诊疗提示"
	dialogue_label.text = message
	dialogue_label.visible_characters = -1
	continue_label.hide()
	treatment_option_container.show()


func _on_pulse_button_pressed() -> void:
	if not is_treatment_mode:
		return

	_show_window_front(pulse_window)
	if pulse_window.has_method("open_window"):
		pulse_window.call("open_window")
	if pulse_window.has_method("show_hint_tab"):
		pulse_window.call("show_hint_tab")
	last_pulse_input_signature = ""


func _on_prescription_button_pressed() -> void:
	if not is_treatment_mode:
		return

	if treatment_backend == null or not is_instance_valid(treatment_backend):
		cancel_story_treatment("Clinic 诊疗后端已经失效。")
		return

	var prescription = null
	if treatment_backend.has_method("get_story_treatment_prescription"):
		prescription = treatment_backend.call("get_story_treatment_prescription")

	if prescription_window.has_method("setup"):
		prescription_window.call("setup", HerbDB, prescription, FormulaDB)

	_show_window_front(prescription_window)


func _on_clinical_log_button_pressed() -> void:
	if not is_treatment_mode:
		return

	_show_window_front(clinical_log_window)
	if clinical_log_window.has_method("open_window"):
		clinical_log_window.call("open_window")
	elif clinical_log_window.has_method("refresh_view"):
		clinical_log_window.call("refresh_view")


func _show_window_front(window_node: Window) -> void:
	if window_node == null:
		return

	window_node.show()
	var parent_node := window_node.get_parent()
	if parent_node != null:
		parent_node.move_child(window_node, parent_node.get_child_count() - 1)
	window_node.grab_focus()


func _close_treatment_windows() -> void:
	for window_node in [pulse_window, prescription_window, clinical_log_window]:
		if window_node == null:
			continue
		if window_node.has_method("close_window"):
			window_node.call("close_window")
		else:
			window_node.hide()

	pulse_keyboard_override_active = false
	last_pulse_input_signature = ""


func _on_prescription_info_requested(text: String) -> void:
	if not is_treatment_mode:
		return
	_show_treatment_message(text)


func _on_prescription_submit_requested() -> void:
	if not is_treatment_mode:
		return

	if treatment_backend == null or not is_instance_valid(treatment_backend):
		cancel_story_treatment("Clinic 诊疗后端已经失效。")
		return

	if not treatment_backend.has_method("submit_story_prescription"):
		cancel_story_treatment("Clinic 缺少 submit_story_prescription()。")
		return

	var raw_submit_result = treatment_backend.call("submit_story_prescription")
	if typeof(raw_submit_result) != TYPE_DICTIONARY:
		_show_treatment_message("Clinic 返回了无效的诊疗结果。")
		return

	var submit_result: Dictionary = raw_submit_result
	if not bool(submit_result.get("ok", false)):
		_show_treatment_message(str(submit_result.get("message", "处方提交失败。")))
		return

	last_treatment_success = bool(submit_result.get("success", false))
	var result_data_value = submit_result.get("result_data", {})
	var result_data: Dictionary = {}
	if typeof(result_data_value) == TYPE_DICTIONARY:
		result_data = result_data_value

	is_treatment_mode = false
	treatment_option_container.hide()
	_close_treatment_windows()
	_show_story_judgement_result(result_data)


func _show_story_judgement_result(result_data: Dictionary) -> void:
	if initial_judgement_result != null and is_instance_valid(initial_judgement_result):
		judgement_result_window = initial_judgement_result
	else:
		judgement_result_window = JUDGEMENT_RESULT_SCENE.instantiate() as Control
		if judgement_result_window != null:
			judgement_result_host.add_child(judgement_result_window)

	if judgement_result_window == null:
		_on_story_judgement_result_closed()
		return

	if not judgement_result_window.tree_exited.is_connected(_on_story_judgement_result_closed):
		judgement_result_window.tree_exited.connect(
			_on_story_judgement_result_closed,
			Object.CONNECT_ONE_SHOT
		)

	if judgement_result_window.has_method("show_result"):
		judgement_result_window.call("show_result", result_data)
	else:
		judgement_result_window.show()


func _on_story_judgement_result_closed() -> void:
	judgement_result_window = null

	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false

	if treatment_backend == null or not is_instance_valid(treatment_backend):
		cancel_story_treatment("判定结束时 Clinic 诊疗后端已经失效。")
		return

	var next_story: StoryData = null
	if treatment_backend.has_method("finish_story_treatment_attempt"):
		var raw_next_story = treatment_backend.call(
			"finish_story_treatment_attempt",
			last_treatment_success,
			treatment_trigger_scene
		)
		if raw_next_story is StoryData:
			next_story = raw_next_story as StoryData

	if next_story != null:
		emit_signal(
			"followup_story_requested",
			next_story,
			not last_treatment_success
		)
		return

	if last_treatment_success:
		is_finished = true
		emit_signal("story_finished")
		return

	# 没有配置失败剧情时，直接回到同一名 story NPC 的诊疗选项。
	_show_treatment_options()


func _handle_treatment_shortcut(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.alt_pressed or key_event.ctrl_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return

	match key_event.keycode:
		KEY_F1:
			_on_pulse_button_pressed()
		KEY_F2:
			_on_prescription_button_pressed()
		KEY_F3:
			_on_clinical_log_button_pressed()
		_:
			return

	get_viewport().set_input_as_handled()


func _get_pressed_action_count(action_names: Array[StringName]) -> int:
	var pressed_count := 0
	for action_name in action_names:
		if Input.is_action_pressed(action_name):
			pressed_count += 1
	return pressed_count


func _update_story_pulse_keyboard_display() -> void:
	var right_actions: Array[StringName] = [
		&"pulse_right_cun",
		&"pulse_right_guan",
		&"pulse_right_chi"
	]
	var left_actions: Array[StringName] = [
		&"pulse_left_cun",
		&"pulse_left_guan",
		&"pulse_left_chi"
	]

	var signature := ""
	for action_name in right_actions + left_actions:
		signature += "1" if Input.is_action_pressed(action_name) else "0"

	if signature == last_pulse_input_signature:
		return
	last_pulse_input_signature = signature

	var right_pressed_count := _get_pressed_action_count(right_actions)
	var left_pressed_count := _get_pressed_action_count(left_actions)
	var total_pressed_count := right_pressed_count + left_pressed_count

	if right_pressed_count == 3 and left_pressed_count == 0:
		pulse_keyboard_override_active = true
		_show_story_pulse_hand("right")
		return

	if left_pressed_count == 3 and right_pressed_count == 0:
		pulse_keyboard_override_active = true
		_show_story_pulse_hand("left")
		return

	if pulse_keyboard_override_active or total_pressed_count != 0:
		pulse_keyboard_override_active = false
		if pulse_window.has_method("show_hint_tab"):
			pulse_window.call("show_hint_tab")


func _show_story_pulse_hand(hand_side: String) -> void:
	if treatment_backend == null or not is_instance_valid(treatment_backend):
		return
	if not treatment_backend.has_method("show_story_pulse_hand"):
		return

	treatment_backend.call("show_story_pulse_hand", pulse_window, hand_side)


func advance() -> void:
	# 推进下一句之前，先处理当前句说话人的退场设置。
	# 例如 LineIndex 2 的陈皮填写 hide，则从第 2 句推进到第 3 句时陈皮退出画面。
	_hide_current_line_speaker_if_needed()

	current_line_index += 1

	# 台词播放完毕。
	if current_line_index >= current_lines.size():
		_finish_story()
		return

	var line_data: StoryLine = current_lines[current_line_index]
	_show_line(line_data)


func _show_line(line_data: StoryLine) -> void:
	# 当前台词设置了背景时进行切换；
	# 没有设置时继续沿用上一句背景。
	_apply_line_background(line_data)

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

	# 关键修复：
	# 不再每帧通过 substr() 改 dialogue_label.text。
	# 先写入完整文本，让 RichTextLabel 一开始就计算完整布局高度。
	# 再用 visible_characters 控制实际显示数量，避免打字过程中触发容器高度变化。
	dialogue_label.text = current_full_text
	dialogue_label.visible_characters = 0

	# 避免隐藏的 subtitle_label 保留上一次的可见字符状态。
	subtitle_label.visible_characters = 0

	# 根据 speaker 显示左、中、右立绘。
	_show_speaker_portrait(line_data)


func _show_subtitle_line(line_data: StoryLine) -> void:
	# 显示背景字幕块。
	subtitle_block.show()
	dialogue_block.hide()

	# 背景字幕通常不显示人物立绘。
	_hide_all_portraits()

	# 同样使用 visible_characters 做字幕打字机效果。
	subtitle_label.text = current_full_text
	subtitle_label.visible_characters = 0

	# 避免隐藏的 dialogue_label 保留上一次的可见字符状态。
	dialogue_label.visible_characters = 0


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

	# 选择当前说话人所在的立绘槽。
	match side:
		"mid":
			active_rect = mid_portrait_rect
		"right":
			active_rect = right_portrait_rect
		_:
			active_rect = left_portrait_rect

	# 当前说话人的立绘正常显示。
	active_rect.texture = portrait
	active_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
	active_rect.show()

	# 其他两个位置已有立绘时保留并压暗。
	var portrait_rects: Array[TextureRect] = [
		left_portrait_rect,
		mid_portrait_rect,
		right_portrait_rect,
	]

	for portrait_rect in portrait_rects:
		if portrait_rect == active_rect:
			continue

		if portrait_rect.texture != null:
			portrait_rect.modulate = Color(0.55, 0.55, 0.55, 0.72)
			portrait_rect.show()
		else:
			portrait_rect.hide()


func _hide_current_line_speaker_if_needed() -> void:
	if current_line_index < 0 or current_line_index >= current_lines.size():
		return

	var line_data: StoryLine = current_lines[current_line_index]
	if line_data == null or line_data.speaker.is_empty():
		return

	if _get_inactive_portrait_mode(line_data) != "hide":
		return

	# 当前说话人没有已经分配的站位时，不处理任何立绘槽。
	if not speaker_side_map.has(line_data.speaker):
		return

	var side := String(speaker_side_map[line_data.speaker])
	var portrait_rect: TextureRect

	match side:
		"mid":
			portrait_rect = mid_portrait_rect
		"right":
			portrait_rect = right_portrait_rect
		_:
			portrait_rect = left_portrait_rect

	# 清空槽位，防止下一句把已经退场的人物重新作为非当前人物显示。
	# speaker_portrait_map 仍保留人物立绘，因此该人物以后再次说话时可以回来。
	portrait_rect.texture = null
	portrait_rect.hide()


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
	if _object_has_property(line_data, "portrait_side"):
		portrait_side = String(line_data.get("portrait_side")).strip_edges().to_lower()

	if portrait_side == "left" or portrait_side == "mid" or portrait_side == "right":
		# 手动指定时，顺便更新 speaker 的固定站位。
		# 这样后续同 speaker 如果写 auto 或空，也会沿用这个手动站位。
		speaker_side_map[line_data.speaker] = portrait_side
		return portrait_side

	return _get_speaker_side(line_data.speaker)


func _get_inactive_portrait_mode(line_data: StoryLine) -> String:
	var inactive_portrait_mode := "dim"

	# 兼容尚未写入 inactive_portrait_mode 字段的旧剧情资源。
	if _object_has_property(line_data, "inactive_portrait_mode"):
		inactive_portrait_mode = String(line_data.get("inactive_portrait_mode")).strip_edges().to_lower()

	if inactive_portrait_mode == "hide":
		return "hide"

	return "dim"


func _object_has_property(target, property_name: String) -> bool:
	if target == null:
		return false

	if not (target is Object):
		return false

	for property_info in target.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true

	return false


func _hide_all_portraits() -> void:
	left_portrait_rect.hide()
	mid_portrait_rect.hide()
	right_portrait_rect.hide()


func _update_visible_text() -> void:
	var safe_count: int = clamp(visible_character_count, 0, current_full_text.length())

	# 根据当前显示块更新可见字符数量。
	# 注意：这里不再修改 text，只修改 visible_characters。
	if subtitle_block.visible:
		subtitle_label.visible_characters = safe_count
	else:
		dialogue_label.visible_characters = safe_count


func _show_full_text() -> void:
	visible_character_count = current_full_text.length()
	_update_visible_text()
	_finish_typing()


func _finish_typing() -> void:
	is_typing = false

	if subtitle_block.visible:
		subtitle_label.visible_characters = current_full_text.length()
	else:
		dialogue_label.visible_characters = current_full_text.length()

	continue_label.show()


func _reset_story_background() -> void:
	# 每段新剧情开始时重置背景。
	background_rect.texture = default_background


func _apply_line_background(line_data: StoryLine) -> void:
	# 只在当前台词明确设置了背景时切换。
	# 留空时保留上一句正在显示的背景。
	if line_data != null and line_data.background != null:
		background_rect.texture = line_data.background


func _setup_default_view() -> void:
	# 默认先隐藏内容块，等播放剧情时再显示。
	dialogue_block.hide()
	subtitle_block.hide()
	treatment_option_container.hide()
	_hide_all_portraits()
	continue_label.hide()
	_close_treatment_windows()

	_reset_text_labels()

	# 遮罩保留显示，用来压暗背景。
	dark_mask.show()


func _reset_text_labels() -> void:
	speaker_label.text = ""

	dialogue_label.text = ""
	dialogue_label.visible_characters = 0

	subtitle_label.text = ""
	subtitle_label.visible_characters = 0


func _finish_story() -> void:
	_reset_enter_hold_state()

	# 治疗失败剧情结束后不离开 Story，直接恢复同一名 NPC 的诊疗选项。
	if resume_treatment_after_story:
		resume_treatment_after_story = false
		_show_treatment_options()
		return

	# 普通剧情配置了 clinic_npc_id 时，台词结束后请求 Main 创建隐藏 Clinic 后端。
	var clinic_npc_id := ""
	if story_data != null:
		clinic_npc_id = story_data.clinic_npc_id.strip_edges()

	if clinic_npc_id != "":
		treatment_npc_id = clinic_npc_id
		waiting_for_treatment_backend = true
		is_typing = false
		continue_label.hide()
		treatment_option_container.hide()
		emit_signal("story_treatment_requested", treatment_npc_id)
		return

	is_finished = true
	emit_signal("story_finished")
