extends Control

@warning_ignore("unused_signal")
signal story_finished
signal story_playback_completed(completed_story: StoryData)
signal story_treatment_requested(npc_id: String, disease: DiseaseData)
signal followup_story_requested(story: StoryData, resume_treatment: bool)
@warning_ignore("unused_signal")
signal game_over_requested
@warning_ignore("unused_signal")
signal endgame_requested

const JUDGEMENT_RESULT_SCENE: PackedScene = preload(
	"res://Scene/JudgementResult/JudgementResult.tscn"
)
const PORTRAIT_NORMAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const PORTRAIT_DIM_COLOR := Color(0.55, 0.55, 0.55, 0.72)

# =========================================================
# Story.gd
# 独立剧情演出场景脚本。
# 负责读取 StoryData，并逐句播放 StoryLine。
#
# 当前版本规则：
# - 每段新剧情开始时，由 StoryData.background_mode 决定显示 default_background，
#   或显示 Main 在隐藏 Clinic / Night / Map 前传入的当前场景背景贴图
# - StoryLine.background 可在任意一句中指定图片并覆盖当前场景
# - 当前台词没有设置背景时，继续沿用上一句的背景状态
# - StoryLine 负责：类型、说话人、文本、背景、立绘、BGM
# - dialogue 类型会优先根据 StoryLine.portrait_side 手动指定左、中、右立绘位置
# - portrait_side 为 auto 或空时，才根据 speaker 自动分配左右立绘位置
# - inactive_portrait_mode 为 dim 时，当前说话人在本句结束后继续留在画面并压暗
# - inactive_portrait_mode 为 hide 时，从本句推进到下一句时当前说话人退出画面
# - inactive_portrait_mode 为 normal 时，当前说话人在本句结束后继续保持正常亮度
#
# 本版本修复：
# - 打字机效果不再通过 substr() 逐字修改 RichTextLabel.text
# - 改为先写入完整文本，再用 visible_characters 控制显示数量
# - 避免 DialogueLabel 高度在打字过程中不断变化，导致 SpeakerLabel 被容器重排后轻微下移
# - 进入 story NPC 治疗成功/失败结果剧情前，只清除诊疗阶段遗留的物理立绘槽
#   不清除 speaker_side_map / speaker_portrait_map，保留正常 StoryLine 人物映射逻辑
# =========================================================

# 当前测试用剧情数据。
# 正式流程里会优先读取 StoryManager.current_story。
@export var story_data: StoryData

# 每段新剧情开始时使用的默认背景。
@export var default_background: Texture2D

# 打字机速度，数值越大显示越快。
@export var type_speed: float = 40.0

# 背景单次渐出或渐入的持续时间。
# 完整换图过程为：旧背景渐出 -> 切换贴图 -> 新背景渐入，
# 因此总时长约为该数值的两倍。
@export_range(0.05, 2.0, 0.05) var background_fade_duration: float = 0.45

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
var story_completion_reported: bool = false

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
# 发起本次治疗的主剧情 ID。
# 播放成功/失败结果剧情时 story_data 会改变，因此必须单独保存并在失败重试后继续沿用。
var treatment_source_story_id: String = ""
var treatment_trigger_scene: String = "clinic"
var is_treatment_mode: bool = false
var waiting_for_treatment_backend: bool = false
var resume_treatment_after_story: bool = false
var last_treatment_success: bool = false
var judgement_result_window: Control = null

var pulse_keyboard_override_active: bool = false
var last_pulse_input_signature: String = ""

# 当前正在执行的背景渐变。
# 保存引用后，可以在玩家快速推进、连续切换背景时终止旧动画，避免多个 Tween 互相覆盖。
var background_fade_tween: Tween = null

# 当前是否正在等待一句台词所配置的新背景完成渐出与渐入。
# 过渡期间暂停剧情推进，避免对话框和立绘抢在新背景之前刷新。
var is_background_transitioning: bool = false

# DarkMask 在 Story.tscn 中原本用于压暗背景。
# 运行时记录它的初始透明度，背景渐入完成后恢复到该值。
var dark_mask_normal_alpha: float = 0.18

# Main 会在把 Story 加入场景树之前注入来源场景当前实际显示的背景。
# 因此 Clinic / Night 即使随后被隐藏，Story 仍能显示正确的季节贴图。
var current_scene_background_texture: Texture2D = null


func set_current_scene_background_texture(texture: Texture2D) -> void:
	# 这里只保存资源引用，不访问 @onready 节点；允许 Main 在 add_child() 前调用。
	current_scene_background_texture = texture


func _ready() -> void:
	dark_mask_normal_alpha = dark_mask.color.a

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


func _input(event: InputEvent) -> void:
	# Story NPC 诊疗阶段：
	# 当独立 Window 关闭后，键盘焦点可能回到 Story 主 Viewport。
	# 只要把脉 / 开方 / 行医记考还有任意窗口可见，
	# Esc 就必须继续优先关闭最上层窗口，不能提前落到 PauseMenu。
	if _try_handle_treatment_window_escape(event):
		return

	# 剧情鼠标点击需要在 UI Control 消费事件前处理。
	# 键盘和诊疗快捷键仍由 _unhandled_input() 负责。
	if is_finished:
		return

	if is_background_transitioning:
		# 背景过渡期间吞掉鼠标事件，防止连续点击推进下一句，
		# 也避免事件继续传递给 Story 下方暂时隐藏的场景。
		get_viewport().set_input_as_handled()
		return

	if waiting_for_treatment_backend:
		return

	# 诊疗模式下不能用全局鼠标推进剧情，避免点击把脉、开方等按钮时误触。
	if is_treatment_mode:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if (
			mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_LEFT
		):
			_advance_or_show_full_text()
			get_viewport().set_input_as_handled()


# =========================================================
# Story NPC 诊疗窗口 Esc 统一兜底
# =========================================================

func _try_handle_treatment_window_escape(event: InputEvent) -> bool:
	# 只在 Story NPC 诊疗模式下介入。
	# 普通剧情阶段的 Esc 行为完全保持原样。
	if not is_treatment_mode:
		return false

	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey

	if not key_event.pressed or key_event.echo:
		return false

	if key_event.keycode != KEY_ESCAPE:
		return false

	if (
		key_event.alt_pressed
		or key_event.ctrl_pressed
		or key_event.meta_pressed
		or key_event.shift_pressed
	):
		return false

	var top_window := _get_topmost_visible_treatment_window()

	# 三个诊疗窗口都已经关闭：
	# 不吃掉 Esc，让 Main / PauseMenu 正常接管。
	if top_window == null:
		return false

	# 还有诊疗窗口可见：
	# 关闭当前最上层窗口，并终止本次 Esc 的继续传播。
	if top_window.has_method("close_window"):
		top_window.call("close_window")
	else:
		top_window.hide()

	get_viewport().set_input_as_handled()
	return true


func _get_topmost_visible_treatment_window() -> Window:
	var top_window: Window = null
	var top_index: int = -1

	var treatment_windows: Array[Window] = []

	if pulse_window != null:
		treatment_windows.append(pulse_window)

	if prescription_window != null:
		treatment_windows.append(prescription_window)

	if clinical_log_window != null:
		treatment_windows.append(clinical_log_window)

	for window_node in treatment_windows:
		if not window_node.visible:
			continue

		# _show_window_front() 每次都会把新打开/重新打开的窗口
		# 移到父节点最后，因此 get_index() 最大的可见窗口
		# 就是当前最上层的诊疗窗口。
		var child_index := window_node.get_index()

		if top_window == null or child_index > top_index:
			top_window = window_node
			top_index = child_index

	return top_window


func _unhandled_input(event: InputEvent) -> void:
	if is_finished:
		return

	if is_background_transitioning:
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
	if (
		is_finished
		or is_background_transitioning
		or is_treatment_mode
		or waiting_for_treatment_backend
	):
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
	if is_background_transitioning:
		return

	if is_typing:
		_show_full_text()
	else:
		advance()


func _skip_current_story() -> void:
	if is_finished or is_background_transitioning:
		return

	is_typing = false
	continue_label.hide()

	# 如果这段剧情结束后会继续进入 / 返回 story NPC 诊疗界面，
	# 跳过时也必须先同步到剧情最后一个有效背景。
	# 否则直接调用 _finish_story() 会让诊疗界面停留在玩家长按回车时的背景。
	if _story_continues_to_treatment():
		var final_background := _get_final_story_background()
		if final_background != null and background_rect.texture != final_background:
			is_background_transitioning = true
			dialogue_block.hide()
			subtitle_block.hide()
			treatment_option_container.hide()
			_clear_physical_portrait_slots()

			await _change_background_with_fade(final_background)

			# Story 如果在等待背景切换时已经被移出场景树，就不再继续结束流程。
			if not is_inside_tree():
				return

			is_background_transitioning = false

	current_line_index = current_lines.size()
	_finish_story()


func _story_continues_to_treatment() -> bool:
	# 失败重试结果剧情播放结束后，会恢复刚才的诊疗界面。
	if resume_treatment_after_story:
		return true

	# 普通剧情配置了 clinic_npc_id 时，播放结束后会进入新的 story NPC 诊疗。
	if story_data == null:
		return false

	return not story_data.clinic_npc_id.strip_edges().is_empty()


func _get_final_story_background() -> Texture2D:
	# 背景字段允许留空，留空表示沿用上一张图。
	# 因此不能只读取最后一句，而要取得整段剧情最后一个非空背景。
	var final_background: Texture2D = background_rect.texture

	for line_data in current_lines:
		if line_data != null and line_data.background != null:
			final_background = line_data.background

	return final_background


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
	is_background_transitioning = false
	story_completion_reported = false
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
	# 治疗成功 / 失败结果剧情仍在同一个 Story 实例中播放。
	#
	# 这里仅清除诊疗阶段遗留在 Left / Mid / Right 上的实际 TextureRect 内容，
	# 不清除 speaker_side_map / speaker_portrait_map / next_speaker_side。
	# 因此：
	# - 不会把 clinic_npc_portrait 遗留到 004_01 等结果剧情里；
	# - StoryLine 原本的 speaker 站位映射、portrait 复用规则仍然有效；
	# - preserve_stage 仍为 true，所以背景继续保留上一阶段状态。
	_clear_physical_portrait_slots()
	play_story(data, true, resume_treatment)


func _clear_physical_portrait_slots() -> void:
	var portrait_rects: Array[TextureRect] = [
		left_portrait_rect,
		mid_portrait_rect,
		right_portrait_rect,
	]

	for portrait_rect in portrait_rects:
		portrait_rect.texture = null
		portrait_rect.modulate = PORTRAIT_NORMAL_COLOR
		portrait_rect.hide()


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
	treatment_source_story_id = ""
	waiting_for_treatment_backend = false

	if story_data != null:
		treatment_source_story_id = story_data.story_id.strip_edges()
		treatment_trigger_scene = story_data.get_condition_scene()

		# 如果“治疗失败剧情”通过 NpcID / Disease 动作重新生成同一名患者，
		# 后续治疗结果仍然要继续绑定最初发起治疗的主剧情。
		# 新结构不再用 failed_retry TriggerType，而是用“失败条件 + 生成 NPC 动作”表达重试。
		var treatment_result_condition := story_data.get_condition_treatment_result()
		var source_story_condition := story_data.get_condition_story_id()
		if treatment_result_condition != "" and source_story_condition != "":
			treatment_source_story_id = source_story_condition

	if treatment_trigger_scene == "":
		treatment_trigger_scene = "clinic"

	_show_treatment_options()


func cancel_story_treatment(message: String) -> void:
	waiting_for_treatment_backend = false
	is_treatment_mode = false
	push_warning(message)
	_finish_story_with_fade(&"story_finished")


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

	# 诊疗选项界面的立绘由当前 StoryData 单独配置。
	# 每次进入或恢复诊疗选项时都重新应用，因此长按回车跳过失败剧情后也能正确恢复。
	_apply_treatment_portrait_from_story_data()

	speaker_label.text = npc_name if npc_name != "" else "诊疗"
	dialogue_label.text = "请选择诊疗项目。"
	dialogue_label.visible_characters = -1
	treatment_option_container.show()


func _apply_treatment_portrait_from_story_data() -> void:
	if story_data == null:
		return

	var portrait: Texture2D = story_data.clinic_npc_portrait
	if portrait == null:
		# 没有手动配置时保持原有行为，不强制清除剧情立绘。
		return

	var portrait_side := story_data.clinic_npc_portrait_side.strip_edges().to_lower()
	if portrait_side not in ["left", "mid", "right"]:
		portrait_side = "right"

	# 进入诊疗选项界面后，清除上一段剧情遗留的槽位内容，
	# 只显示当前 StoryData 手动配置的诊疗立绘。
	var portrait_rects: Array[TextureRect] = [
		left_portrait_rect,
		mid_portrait_rect,
		right_portrait_rect,
	]
	for portrait_rect in portrait_rects:
		portrait_rect.texture = null
		portrait_rect.hide()

	var target_rect: TextureRect = right_portrait_rect
	match portrait_side:
		"left":
			target_rect = left_portrait_rect
		"mid":
			target_rect = mid_portrait_rect
		_:
			target_rect = right_portrait_rect

	target_rect.texture = portrait
	target_rect.modulate = PORTRAIT_NORMAL_COLOR
	target_rect.show()


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

	# 每次重新打开窗口都从静音状态开始，避免继承上一次把脉声音。
	SfxManager.stop_heartbeat()

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
	SfxManager.stop_heartbeat()

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

	var close_callable := Callable(self, "_on_story_judgement_result_closed")

	# JudgementResult 主动发送 result_closed，避免把剧情推进绑定到节点销毁时机。
	# 保留 tree_exited 兜底，兼容临时使用旧版 JudgementResult.gd 的情况。
	if judgement_result_window.has_signal("result_closed"):
		if not judgement_result_window.is_connected("result_closed", close_callable):
			judgement_result_window.connect(
				"result_closed",
				close_callable,
				Object.CONNECT_ONE_SHOT
			)
	else:
		if not judgement_result_window.tree_exited.is_connected(close_callable):
			judgement_result_window.tree_exited.connect(
				close_callable,
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
			treatment_trigger_scene,
			treatment_source_story_id
		)
		if raw_next_story is StoryData:
			next_story = raw_next_story as StoryData

	if next_story != null:
		# 新结构中“失败后重试”由结果剧情自己的 NpcID / Disease / 立绘动作表达，
		# 不再通过 TriggerType 决定行为。
		# 这里只保留旧 .tres 的 failed_retry 兼容。
		var resume_treatment := next_story.is_legacy_failed_retry()
		emit_signal(
			"followup_story_requested",
			next_story,
			resume_treatment
		)
		return

	if last_treatment_success:
		_finish_story_with_fade(&"story_finished")
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
		SfxManager.start_heartbeat()
		_show_story_pulse_hand("right")
		return

	if left_pressed_count == 3 and right_pressed_count == 0:
		pulse_keyboard_override_active = true
		SfxManager.start_heartbeat()
		_show_story_pulse_hand("left")
		return

	# 只要不再满足完整的单手三键组合，就立即停止心跳。
	SfxManager.stop_heartbeat()

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
	if is_background_transitioning:
		return

	# 推进下一句之前，先应用当前句说话人的结束状态。
	# 例如填写 hide / dim / normal，分别表示退场 / 压暗保留 / 正常亮度保留。
	_apply_current_line_speaker_portrait_state()

	current_line_index += 1

	# 台词播放完毕。
	if current_line_index >= current_lines.size():
		_finish_story()
		return

	var line_data: StoryLine = current_lines[current_line_index]
	_show_line(line_data)


func _show_line(line_data: StoryLine) -> void:
	continue_label.hide()

	# StoryLine.Music 控制剧情BGM切换
	if line_data != null and line_data.music != "":
		MusicManager.play_story_music(line_data.music)

	# 只有当前句明确指定了不同背景时才等待过渡。
	# 普通台词和重复使用同一背景的台词仍然立即显示。
	var changed_background := (
		line_data != null
		and line_data.background != null
		and background_rect.texture != line_data.background
	)

	if changed_background:
		is_background_transitioning = true
		is_typing = false
		_reset_enter_hold_state()

		# 换背景时先隐藏旧台词，并彻底清空左、中、右三个物理立绘槽。
		# 保留人物站位和 speaker_portrait_map，背景切换完成后可从当前句
		# 重新建立新背景中的人物画面，不会把上一背景的旧立绘带回来。
		dialogue_block.hide()
		subtitle_block.hide()
		_clear_physical_portrait_slots()

		await _apply_line_background(line_data)

		# Story 如果在等待期间已被外部移出场景树，不再继续刷新 UI。
		if not is_inside_tree():
			return

		is_background_transitioning = false

	current_full_text = line_data.text
	visible_character_count = 0
	type_timer = 0.0
	is_typing = true

	if line_data.line_type == "subtitle":
		_show_subtitle_line(line_data)
	else:
		# 背景切换完成后，正常显示当前句台词和当前说话人的立绘。
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

	# 到这里时背景切换（如有）已经完成，因此正常显示当前说话人立绘。
	_show_speaker_portrait(line_data)


@warning_ignore("unused_parameter")
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
	active_rect.modulate = PORTRAIT_NORMAL_COLOR
	active_rect.show()

	# 其他位置沿用各自上一句结束时设置的状态。
	# 不能在这里统一压暗，否则 normal 会在下一句开始时被覆盖。
	var portrait_rects: Array[TextureRect] = [
		left_portrait_rect,
		mid_portrait_rect,
		right_portrait_rect,
	]

	for portrait_rect in portrait_rects:
		if portrait_rect == active_rect:
			continue

		if portrait_rect.texture != null:
			portrait_rect.show()
		else:
			portrait_rect.hide()


func _apply_current_line_speaker_portrait_state() -> void:
	if current_line_index < 0 or current_line_index >= current_lines.size():
		return

	var line_data: StoryLine = current_lines[current_line_index]
	if line_data == null or line_data.speaker.is_empty():
		return

	# 当前说话人没有已经分配的站位时，不处理任何立绘槽。
	if not speaker_side_map.has(line_data.speaker):
		return

	var side := String(speaker_side_map[line_data.speaker])
	var portrait_rect: TextureRect = left_portrait_rect

	match side:
		"mid":
			portrait_rect = mid_portrait_rect
		"right":
			portrait_rect = right_portrait_rect
		_:
			portrait_rect = left_portrait_rect

	var mode := _get_inactive_portrait_mode(line_data)

	match mode:
		"hide":
			# 清空槽位，防止下一句把已经退场的人物重新显示。
			# speaker_portrait_map 仍保留人物立绘，因此该人物以后再次说话时可以回来。
			portrait_rect.texture = null
			portrait_rect.hide()
		"normal":
			if portrait_rect.texture != null:
				portrait_rect.modulate = PORTRAIT_NORMAL_COLOR
				portrait_rect.show()
		_:
			# 空值和未知旧值都按 dim 处理，保持向后兼容。
			if portrait_rect.texture != null:
				portrait_rect.modulate = PORTRAIT_DIM_COLOR
				portrait_rect.show()


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

	if inactive_portrait_mode in ["hide", "dim", "normal"]:
		return inactive_portrait_mode

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
	# default：保持原有行为，显示 Story 场景配置的默认背景。
	# current_scene：显示 Main 在隐藏来源场景前传入的当前季节背景。
	var target_texture: Texture2D = default_background
	var background_mode := StoryData.BACKGROUND_MODE_DEFAULT
	if story_data != null:
		background_mode = story_data.background_mode.strip_edges().to_lower()

	if background_mode == StoryData.BACKGROUND_MODE_CURRENT_SCENE:
		if current_scene_background_texture != null:
			target_texture = current_scene_background_texture
		else:
			# 独立运行 Story 或来源场景未实现背景接口时，至少保留原有默认背景兜底。
			push_warning("Story 使用 current_scene，但没有收到当前场景背景贴图。")

	# 如果第一句已经明确配置背景，直接以它作为开场背景。
	# 这样不会先渐入默认背景，然后又立刻切换到第一句背景。
	if not current_lines.is_empty():
		var first_line: StoryLine = current_lines[0]
		if first_line != null and first_line.background != null:
			target_texture = first_line.background

	_show_background_from_black(target_texture)


func _apply_line_background(line_data: StoryLine) -> void:
	# 只在当前台词明确设置了背景时切换。
	# 留空时保留上一句正在显示的背景，或继续显示传入的当前场景背景贴图。
	if line_data != null and line_data.background != null:
		await _change_background_with_fade(line_data.background)


func _stop_background_fade() -> void:
	# 快速推进剧情时，先终止上一段尚未完成的渐变，
	# 再从 DarkMask 当前的透明度开始新的渐变。
	if background_fade_tween != null and background_fade_tween.is_valid():
		background_fade_tween.kill()

	background_fade_tween = null


func _set_background_texture(texture: Texture2D) -> void:
	background_rect.texture = texture
	background_rect.show()


func _show_background_from_black(texture: Texture2D) -> void:
	# 新剧情开始时先显示纯黑遮罩，再逐渐恢复为场景原本的压暗程度。
	_stop_background_fade()
	_set_background_texture(texture)

	var mask_color := dark_mask.color
	mask_color.a = 1.0
	dark_mask.color = mask_color

	background_fade_tween = create_tween()
	background_fade_tween.set_trans(Tween.TRANS_SINE)
	background_fade_tween.set_ease(Tween.EASE_IN_OUT)
	background_fade_tween.tween_property(
		dark_mask,
		"color:a",
		dark_mask_normal_alpha,
		background_fade_duration
	)


func _change_background_with_fade(new_texture: Texture2D) -> void:
	if new_texture == null:
		return

	# 相同背景不重复播放渐变。
	# 第一行背景已在 _reset_story_background() 中预先应用，因此也会走到这里直接返回。
	if background_rect.texture == new_texture:
		background_rect.show()
		return

	_stop_background_fade()

	var fade_tween := create_tween()
	background_fade_tween = fade_tween
	fade_tween.set_trans(Tween.TRANS_SINE)
	fade_tween.set_ease(Tween.EASE_IN_OUT)

	# 旧背景渐出到黑色。
	fade_tween.tween_property(
		dark_mask,
		"color:a",
		1.0,
		background_fade_duration
	)

	# 完全变黑后替换背景贴图。
	fade_tween.tween_callback(
		_set_background_texture.bind(new_texture)
	)

	# 新背景从黑色渐入，并恢复原本的 0.18 压暗透明度。
	fade_tween.tween_property(
		dark_mask,
		"color:a",
		dark_mask_normal_alpha,
		background_fade_duration
	)

	await fade_tween.finished

	if background_fade_tween == fade_tween:
		background_fade_tween = null


func _fade_story_background_out() -> void:
	# 剧情结束时终止尚未完成的开场渐入或中途换图动画，
	# 再从 DarkMask 当前透明度渐变到纯黑。
	_stop_background_fade()

	var fade_tween := create_tween()
	background_fade_tween = fade_tween
	fade_tween.set_trans(Tween.TRANS_SINE)
	fade_tween.set_ease(Tween.EASE_IN_OUT)
	fade_tween.tween_property(
		dark_mask,
		"color:a",
		1.0,
		background_fade_duration
	)

	await fade_tween.finished

	if background_fade_tween == fade_tween:
		background_fade_tween = null


func _finish_story_with_fade(completion_signal: StringName) -> void:
	# 普通剧情结束后重新由当前场景决定 BGM。
	# Game Over / Endgame 会离开当前游戏场景，不应恢复旧场景 BGM。
	if (
		completion_signal != &"game_over_requested"
		and completion_signal != &"endgame_requested"
	):
		MusicManager.resume_scene_music()

	# is_finished 会立即阻止玩家在淡出期间继续点击或按键，
	# completion_signal 则必须等背景完全淡出后才发送给 Main。
	if is_finished:
		return

	is_finished = true
	is_typing = false
	_reset_enter_hold_state()
	continue_label.hide()

	await _fade_story_background_out()

	# 淡出期间如果 Story 已经被外部移出场景树，就不再发送结束信号。
	if not is_inside_tree():
		return

	emit_signal(completion_signal)


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


func _report_story_playback_completed() -> void:
	# 每次 play_story() 只上报一次，避免连按、跳过或后续分支造成重复结算。
	if story_completion_reported:
		return

	story_completion_reported = true
	emit_signal("story_playback_completed", story_data)


func _finish_story() -> void:
	_reset_enter_hold_state()
	_report_story_playback_completed()

	# “播放后 = gameover”表示失败结局，直接结束本局。
	if story_data != null and story_data.should_game_over():
		_finish_story_with_fade(&"game_over_requested")
		return

	# “播放后 = endgame”只用于最终通关，剧情淡出后进入片尾动画。
	if story_data != null and story_data.should_end_game():
		_finish_story_with_fade(&"endgame_requested")
		return

	# 只用于旧 failed_retry .tres 的兼容。
	if resume_treatment_after_story:
		resume_treatment_after_story = false
		_show_treatment_options()
		return

	# 配置 NpcID 后，剧情完整播放结束再生成并进入 story NPC 诊疗。
	var clinic_npc_id := ""
	var clinic_disease: DiseaseData = null

	if story_data != null:
		clinic_npc_id = story_data.clinic_npc_id.strip_edges()
		clinic_disease = story_data.clinic_disease

	if clinic_npc_id != "":
		treatment_npc_id = clinic_npc_id
		waiting_for_treatment_backend = true
		is_typing = false
		continue_label.hide()
		treatment_option_container.hide()
		emit_signal(
			"story_treatment_requested",
			treatment_npc_id,
			clinic_disease
		)
		return

	_finish_story_with_fade(&"story_finished")
