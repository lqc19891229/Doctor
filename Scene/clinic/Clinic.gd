extends Control

# =========================================================
# Clinic.gd
# 诊室主控制脚本（接入 Main 流程版）
#
# 主要职责：
# 1. 管理当前病人数据刷新
# 2. 管理脉象键盘把脉逻辑
# 3. 持有当前处方数据，并接收 PrescriptionWindow 的信号
# 4. 提交处方并与标准方比较
# 5. 向 Main 发出“当天接诊结束”信号
# 6. 接入 GameTimeManager 的 Clinic 自动计时显示
# 7. 请求剧情播放
# =========================================================


# =========================================================
# 对外信号
# =========================================================

# 通知 Main：Clinic 当天流程结束
signal clinic_finished

# 通知 Main：Clinic 请求播放剧情
# Clinic 不直接切换 Story 场景，避免破坏 Main 管理的主流程。
signal story_requested(story_path: String, return_target: String)


# =========================================================
# 常量定义
# =========================================================

# 默认查看的脉象区域
const DEFAULT_DISPLAY_REGION := "浮脉"

# 判定结果弹窗场景路径
const JUDGEMENT_RESULT_SCENE_PATH := "res://Scene/JudgementResult/JudgementResult.tscn"

# 通用顶部栏控制器脚本
const TopBarControllerScript := preload("res://System/Unlock/TopBarController.gd")

# 诊室四季背景
const CLINIC_SPRING_BACKGROUND: Texture2D = preload("res://Assets/Background/clinic/spring.png")
const CLINIC_SUMMER_BACKGROUND: Texture2D = preload("res://Assets/Background/clinic/summer.png")
const CLINIC_AUTUMN_BACKGROUND: Texture2D = preload("res://Assets/Background/clinic/autumn.png")
const CLINIC_WINTER_BACKGROUND: Texture2D = preload("res://Assets/Background/clinic/winter.png")


# NPC 台词自动隐藏时间，单位：秒
const NPC_DIALOGUE_AUTO_HIDE_SECONDS := 10.0

# random NPC 立绘入场动画
const RANDOM_NPC_PORTRAIT_ENTRANCE_DURATION := 1.0
const RANDOM_NPC_PORTRAIT_ENTRANCE_START_SCALE := Vector2(0.92, 0.92)


# =========================================================
# 场景节点引用
# =========================================================

# ---------- 顶部时间显示 ----------
# 说明：
# 1. DayLabel 显示“第几天”
# 2. TimeLabel 显示“当前时辰”
@onready var day_label: Label = find_child("DayLabel", true, false) as Label
@onready var time_label: Label = find_child("TimeLabel", true, false) as Label

# ---------- 诊室季节背景 ----------
# 复用 Clinic 场景中现有的 Background 节点，无需新增节点。
@onready var clinic_background: TextureRect = $Background/BackgroundImage

# ---------- 心得显示 ----------
#  这个 Label 只负责显示 UnlockManager 中保存的心得数量。
@onready var thoughts_point_label: Label = find_child("ThoughtsPoint", true, false) as Label
@onready var reputation_point_label: Label = find_child("ReputationPoint", true, false) as Label

# ---------- 当前 NPC 立绘 ----------
# 说明：
# 1. 节点建议放在 Clinic/Background/Portrait。
# 2. 使用 find_child，方便你在场景里调整层级，只要节点名仍叫 Portrait 即可。
@onready var portrait_rect: TextureRect = find_child("Portrait", true, false) as TextureRect

# ---------- 当前 NPC 姓名 ----------
# 说明：
# 1. 节点建议放在 Portrait 附近，节点名保持 NpcNameLabel 即可。
# 2. 只显示 current_npc.npc_name。
@onready var npc_name_label: Label = find_child("NpcNameLabel", true, false) as Label

# ---------- 当前 NPC 台词 ----------
# 说明：
# 1. 节点建议放在 Portrait 附近，节点名保持 NpcDialogueLabel 即可。
# 2. 支持 Label 或 RichTextLabel；这里按 Control 接收，避免节点类型调整时报错。
# 3. 台词在刷新病人时随机生成一次，不在 _process() 中重复刷新。
@onready var npc_dialogue_label: Control = find_child("NpcDialogueLabel", true, false) as Control

# ---------- 脉象窗口 ----------
@onready var pulse_window: PulseWindow = find_child("PulseWindow", true, false) as PulseWindow

# ---------- 信息测试窗口 ----------
# 说明：
# 1. info_window 仍按 Window 接收，避免 InfoWindow.gd 未注册 class_name 时报错
# 2. info_label 使用 find_child 获取，兼容以下两种结构：
#    - InfoWindow/Panel/InfoLabel
#    - InfoWindow/Panel/VBoxContainer/InfoLabel
@onready var info_window: Window = find_child("InfoWindow", true, false) as Window
@onready var info_label: Label = find_child("InfoLabel", true, false) as Label

# ---------- 数据库 / 管理器 ----------
@onready var herb_database = HerbDB
@onready var formula_database = FormulaDB
@onready var npc_manager = find_child("NpcManager", true, false)

# ---------- 开方窗口 ----------
@onready var prescription_window: PrescriptionWindow = find_child("PrescriptionWindow", true, false) as PrescriptionWindow

# ---------- 行医记考 ----------
# 说明：
# 1. 这里使用 find_child，避免场景还没接好时报错。
# 2. 窗口打开/关闭和按钮快捷键统一交给 ClinicWindowController.gd。
@onready var clinical_log_window: ClinicalLogWindow = find_child("ClinicalLogWindow", true, false) as ClinicalLogWindow

# ---------- 窗口与快捷键控制器 ----------
@onready var window_controller: ClinicWindowController = find_child("ClinicWindowController", true, false) as ClinicWindowController

# ---------- 通用顶部栏控制器 ----------
var topbar_controller = null

# ---------- 结束当天 ----------
# 结束当天按钮已经转移到 InfoWindow，这里不再直接引用旧按钮


# =========================================================
# 运行时状态
# =========================================================

# 当前显示的脉诊区域（UI显示名）
var current_display_region_name: String = DEFAULT_DISPLAY_REGION

# 当前接诊病人
var current_npc: NpcData = null

# 当前诊疗流程是否已提交
var diagnosis_submitted: bool = false

# 当前玩家处方（数据仍由 Clinic 持有）
var current_prescription := Prescription.new()

# 方剂判定器
var formula_judge := FormulaJudge.new()

# 键盘把脉是否处于覆盖显示状态
var pulse_keyboard_override_active: bool = false

# 上一帧按键签名，用于避免每帧重复刷新
var last_pulse_input_signature: String = ""

# 当前天数（由 Main 注入）
var current_day: int = 1

# 防止 Clinic 结束信号重复发出
var clinic_finished_emitted: bool = false

# 最近一次处方判定结果
# 说明：
# 1. submit_prescription() 负责生成判定结果。
# 2. _on_prescription_submit_requested() 负责把结果交给 JudgementResult 场景显示。
var last_formula_judge_result = null
var last_formula_judge_summary_text: String = ""

# 最近一次提交处方后，本次心得更新新解锁的行医记考条目标题
# 说明：
# 1. 只记录本次提交产生的新解锁条目。
# 2. JudgementResult 会读取这个列表，并在 RichTextLabel 中给出解锁提示。
var last_newly_unlocked_entry_titles: Array[String] = []

# 最近一次提交处方后，实际发生的 random NPC 固定奖励变化。
# story NPC 的奖励由 StoryData 在剧情播放完成时结算，不写入这里。
var last_reputation_change: int = 0
var last_experience_change: int = 0

# 当前打开的判定结果窗口
var judgement_result_window: Control = null

# NPC 台词当前是否正在显示
var npc_dialogue_visible: bool = false

# NPC 台词显示令牌
# 说明：
# 1. 每次显示或隐藏台词都会递增。
# 2. 用来防止旧的 10 秒计时器误隐藏新的 NPC 台词。
var npc_dialogue_display_token: int = 0

# 提交处方后，是否正在等待当前 NPC 的治疗结果台词播放完毕。
# 说明：
# 1. true 时，玩家点击隐藏台词或 10 秒结束后才弹出 JudgementResult。
# 2. 确保 random NPC 的治疗成功 / 失败反馈先于判定结果显示。
var waiting_judgement_after_treatment_dialogue: bool = false

# Main 为 Story 场景创建的隐藏业务后端会在 add_child() 前把此项设为 true。
# 后端模式只保留 NpcManager、处方与判定逻辑，不启动诊室计时和诊室 UI 信号。
var story_treatment_backend_mode: bool = false

# Story 中的开方窗口无法显示 Clinic 的 InfoWindow，因此缓存最近一次提示供 Story 读取。
var last_info_text: String = ""

# 当前 random NPC 立绘入场动画；切换病人时先停止旧动画，避免 Tween 相互叠加。
var portrait_entrance_tween: Tween = null


# =========================================================
# 生命周期
# =========================================================

func _ready() -> void:
	_validate_scene_node_bindings()

	if story_treatment_backend_mode:
		current_npc = null
		visible = false
		return

	_setup_topbar_controller()
	_setup_time_system()

	if window_controller != null:
		window_controller.configure_prescription_context(
			herb_database,
			current_prescription,
			formula_database
		)

	_connect_signals()

	# 病人不再在 _ready() 中自动生成。
	# Main 会在连接好 story_requested 信号后调用 start_new_day()，
	# 再由 start_new_day() 按“入口剧情 → random NPC”的顺序决定。
	# story NPC 的诊疗由 Story 场景请求隐藏 Clinic 后端处理。
	current_npc = null
	_update_npc_portrait()
	_update_npc_name()
	_set_npc_dialogue_label_text("")
	_refresh_topbar(true)

	# 调试输出：仅在 Debug 构建中打印数据库加载情况，避免正式版刷屏。
	if OS.is_debug_build():
		print("药材数量：", herb_database.get_all_herbs().size())
		if formula_database != null and formula_database.has_method("debug_print_all_formulas"):
			formula_database.debug_print_all_formulas()

	# 注意：不要在 _ready() 里自动触发剧情。
	# Main 还没有连接 story_requested 信号时，_ready() 发出的信号会丢失。
	# 自动剧情统一放到 start_new_day()，由 Main 连接好信号后调用。


func _process(_delta: float) -> void:
	if story_treatment_backend_mode:
		return

	# Clinic 不在这里处理时间计时
	# 时间推进统一交给 GameTimeManager.gd

	# 每帧检查一次心得数量。
	# 说明：
	# - 只有数量变化时才会真正改 Label 文本。
	# - 这样即使心得来自读档、调试窗口或其它脚本，也能同步到 TopBar。
	_refresh_topbar_points(false)

	# 只有脉象窗口打开时才处理键盘把脉逻辑
	if pulse_window != null and pulse_window.visible:
		_update_pulse_keyboard_display()


func _validate_scene_node_bindings() -> void:
	# 现在 Clinic 的 UI 结构为：
	# Clinic
	# ├─ Background
	# ├─ VBoxContainer
	# │  ├─ TopBar
	# │  ├─ Panel        # 占位用
	# │  └─ ButtonRow
	# ├─ PrescriptionWindow
	# ├─ PulseWindow
	# ├─ ClinicalLogWindow
	# ├─ InfoWindow
	# └─ NpcManager
	#
	# 这里不要再写死 DiagnosisPanel/DiagnosisLayout 路径。
	# find_child 会按节点名查找，适合当前这种 UI 结构仍在调整的阶段。
	if not OS.is_debug_build():
		return

	var required_nodes := {
		"Background": clinic_background,
		"DayLabel": day_label,
		"TimeLabel": time_label,
		"ThoughtsPoint": thoughts_point_label,
		"ReputationPoint": reputation_point_label,
		"Portrait": portrait_rect,
		"NpcNameLabel": npc_name_label,
		"NpcDialogueLabel": npc_dialogue_label,
		"PulseWindow": pulse_window,
		"PrescriptionWindow": prescription_window,
		"ClinicalLogWindow": clinical_log_window,
		"InfoWindow": info_window,
		"NpcManager": npc_manager,
		"ClinicWindowController": window_controller
	}

	for node_name in required_nodes.keys():
		if required_nodes[node_name] == null:
			push_warning("Clinic.gd 未找到节点：%s，请检查 Clinic.tscn 中的节点名称。" % node_name)


# =========================================================
# 初始化：通用 TopBar 控制器
# =========================================================

func _setup_topbar_controller() -> void:
	if topbar_controller != null and is_instance_valid(topbar_controller):
		return

	topbar_controller = TopBarControllerScript.new()
	topbar_controller.name = "TopBarController"
	add_child(topbar_controller)
	topbar_controller.setup(
		day_label,
		time_label,
		thoughts_point_label,
		reputation_point_label
	)
	topbar_controller.set_fallback_day(current_day)


# =========================================================
# 初始化：Clinic 时间系统
# =========================================================

func _setup_time_system() -> void:
	# 每次进入 Clinic，都重置为辰时，并由 GameTimeManager 开始自动计时
	if GameTime.has_method("start_clinic_time"):
		GameTime.start_clinic_time()

	# 监听 GameTimeManager 发出的 Clinic 时间结束信号
	# 例如：辰、巳、午、未、申结束后自动进入夜读
	if GameTime.has_signal("clinic_time_finished"):
		if not GameTime.clinic_time_finished.is_connected(_on_clinic_time_finished):
			GameTime.clinic_time_finished.connect(_on_clinic_time_finished)

	_update_time_ui()


# =========================================================
# 刷新 TopBar 显示
# =========================================================

func _refresh_topbar(force_refresh: bool = false) -> void:
	if topbar_controller != null:
		topbar_controller.refresh_all(force_refresh)


func _refresh_topbar_points(force_refresh: bool = false) -> void:
	if topbar_controller != null:
		topbar_controller.refresh_points(force_refresh)


func _update_time_ui() -> void:
	if topbar_controller != null:
		topbar_controller.set_fallback_day(current_day)
		topbar_controller.refresh_time()


func _update_thoughts_point_ui(force_refresh: bool = false) -> void:
	if topbar_controller != null:
		topbar_controller.refresh_thoughts_point(force_refresh)


func _update_reputation_point_ui(force_refresh: bool = false) -> void:
	if topbar_controller != null:
		topbar_controller.refresh_reputation_point(force_refresh)


# =========================================================
# GameTimeManager：时间变化回调（兼容旧连接；新逻辑由 TopBarController 负责监听）
# =========================================================

func _on_game_time_changed() -> void:
	_update_time_ui()


# =========================================================
# 根据当前节气刷新诊室背景
# =========================================================

func _update_clinic_background() -> void:
	if clinic_background == null:
		push_warning("Clinic.gd 未找到 TextureRect 类型的 Background 节点，无法切换季节背景。")
		return

	# current_day 每一天对应一个节气；每 24 天循环到下一年的立春。
	var solar_term_index: int = (maxi(current_day, 1) - 1) % 24

	if solar_term_index < 6:
		# 立春、雨水、惊蛰、春分、清明、谷雨
		clinic_background.texture = CLINIC_SPRING_BACKGROUND
	elif solar_term_index < 12:
		# 立夏、小满、芒种、夏至、小暑、大暑
		clinic_background.texture = CLINIC_SUMMER_BACKGROUND
	elif solar_term_index < 18:
		# 立秋、处暑、白露、秋分、寒露、霜降
		clinic_background.texture = CLINIC_AUTUMN_BACKGROUND
	else:
		# 立冬、小雪、大雪、冬至、小寒、大寒
		clinic_background.texture = CLINIC_WINTER_BACKGROUND


# =========================================================
# GameTimeManager：Clinic 时间结束回调
# =========================================================

func _on_clinic_time_finished() -> void:
	finish_clinic_for_today()


# =========================================================
# 初始化：信号连接
# =========================================================

func _connect_signals() -> void:
	# ---------- 窗口控制器信号 ----------
	if window_controller != null:
		if not window_controller.pulse_window_opened.is_connected(_on_window_controller_pulse_window_opened):
			window_controller.pulse_window_opened.connect(_on_window_controller_pulse_window_opened)

		if not window_controller.pulse_window_closed.is_connected(_on_window_controller_pulse_window_closed):
			window_controller.pulse_window_closed.connect(_on_window_controller_pulse_window_closed)

	# ---------- 脉象窗口业务信号 ----------
	if pulse_window != null:
		if not pulse_window.region_selected.is_connected(_on_pulse_panel_region_selected):
			pulse_window.region_selected.connect(_on_pulse_panel_region_selected)

	# ---------- 开方窗口业务信号 ----------
	if prescription_window != null:
		if not prescription_window.info_requested.is_connected(_on_prescription_info_requested):
			prescription_window.info_requested.connect(_on_prescription_info_requested)

		if not prescription_window.submit_requested.is_connected(_on_prescription_submit_requested):
			prescription_window.submit_requested.connect(_on_prescription_submit_requested)

	# ---------- 信息测试窗口业务信号 ----------
	if info_window != null:
		# 以下信号由 InfoWindow.gd 中的按钮发出
		_safe_connect_custom_signal(info_window, "prev_npc_requested", _on_prev_button_pressed)
		_safe_connect_custom_signal(info_window, "next_npc_requested", _on_next_button_pressed)
		_safe_connect_custom_signal(info_window, "spawn_npc_requested", _on_spawn_npc_button_pressed)
		_safe_connect_custom_signal(info_window, "end_today_requested", _on_end_today_pressed)
		_safe_connect_custom_signal(info_window, "unlock_all_entries_requested", _on_unlock_all_entries_requested)


func _safe_connect_custom_signal(target: Object, signal_name: StringName, callable_fn: Callable) -> void:
	# 兼容自定义 InfoWindow.gd：
	# 如果 InfoWindow 没有声明该信号，就直接跳过，避免报错。
	if target == null:
		return

	if not target.has_signal(signal_name):
		if OS.is_debug_build():
			print("InfoWindow 缺少信号：", signal_name)
		return

	if not target.is_connected(signal_name, callable_fn):
		target.connect(signal_name, callable_fn)


# =========================================================
# 通用工具函数
# =========================================================

func _ensure_current_npc_valid(show_message: bool = false) -> bool:
	if current_npc == null:
		current_npc = npc_manager.get_current_npc()

	if current_npc == null:
		if show_message:
			_set_info_text("当前没有病人")
		return false

	if current_npc.disease == null:
		if show_message:
			_set_info_text("病人：%s\n未绑定疾病数据" % current_npc.npc_name)
		return false

	return true

func _set_info_text(text: String) -> void:
	last_info_text = text

	# 统一写入信息窗口文本。
	# 说明：
	# 1. 其它函数不再直接访问 info_label.text，减少空节点报错风险。
	# 2. 如果 InfoLabel 暂未接入场景，则在 Debug 构建中打印，方便排查。
	if info_label != null:
		info_label.text = text
	elif OS.is_debug_build():
		print(text)


func _get_pressed_action_count(action_names: Array[StringName]) -> int:
	# 统计一组输入动作中，当前被按下的动作数量。
	# 用于键盘把脉时判断左右手三键是否同时按下。
	var pressed_count := 0
	for action_name in action_names:
		if Input.is_action_pressed(action_name):
			pressed_count += 1
	return pressed_count


func _show_pulse_result(result: Dictionary) -> void:
	# 统一处理 PulseWindow 返回的脉象显示结果。
	# 说明：
	# 1. show_region() 与 show_hand_group() 原本有重复的信息拼接。
	# 2. 这里集中生成提示文本，后续新增病人字段时只需要改一处。
	if not _ensure_current_npc_valid(true):
		return

	var result_text: String = result.get("text", "")
	if not result.get("ok", false):
		_set_info_text("病人：%s\n疾病：%s\n%s" % [
			current_npc.npc_name,
			current_npc.disease.disease_name,
			result_text
		])
		return

	_set_info_text("病人：%s\n性别：%s  年龄：%d\n疾病：%s\n%s" % [
		current_npc.npc_name,
		current_npc.gender,
		current_npc.age,
		current_npc.disease.disease_name,
		result_text
	])


# =========================================================
# 刷新当前 NPC 立绘
# =========================================================

func _update_npc_portrait() -> void:
	# 只负责把 current_npc 当前诊疗状态对应的立绘显示到 Portrait 节点。
	# 立绘选择逻辑放在 NpcData.get_current_portrait() 中。
	if portrait_rect == null:
		return

	if current_npc == null:
		portrait_rect.texture = null
		portrait_rect.visible = false
		return

	var display_portrait: Texture2D = current_npc.get_current_portrait()
	if display_portrait == null:
		portrait_rect.texture = null
		portrait_rect.visible = false
		return

	portrait_rect.texture = display_portrait
	portrait_rect.visible = true


func _play_random_npc_portrait_entrance() -> void:
	if portrait_rect == null:
		return

	# 快速切换病人时先停止上一段动画，避免它继续影响新立绘。
	if portrait_entrance_tween != null and portrait_entrance_tween.is_valid():
		portrait_entrance_tween.kill()
	portrait_entrance_tween = null
	portrait_rect.scale = Vector2.ONE
	portrait_rect.modulate.a = 1.0

	# 剧情 NPC 不使用 Clinic 中 random NPC 的入场表现。
	if current_npc == null or current_npc.npc_type.strip_edges().to_lower() == "story":
		return

	if portrait_rect.texture == null or not portrait_rect.visible:
		return

	portrait_rect.pivot_offset = portrait_rect.size * 0.5
	portrait_rect.scale = RANDOM_NPC_PORTRAIT_ENTRANCE_START_SCALE
	portrait_rect.modulate.a = 0.0

	portrait_entrance_tween = create_tween()
	portrait_entrance_tween.set_parallel(true)
	portrait_entrance_tween.set_trans(Tween.TRANS_QUAD)
	portrait_entrance_tween.set_ease(Tween.EASE_OUT)
	portrait_entrance_tween.tween_property(
		portrait_rect,
		"scale",
		Vector2.ONE,
		RANDOM_NPC_PORTRAIT_ENTRANCE_DURATION
	)
	portrait_entrance_tween.tween_property(
		portrait_rect,
		"modulate:a",
		1.0,
		RANDOM_NPC_PORTRAIT_ENTRANCE_DURATION
	)


# =========================================================
# 刷新当前 NPC 姓名
# =========================================================

func _update_npc_name() -> void:
	# 只负责把 current_npc.npc_name 显示到 NpcNameLabel。
	# 如果当前没有病人，或病人姓名为空，则隐藏姓名 Label。
	if npc_name_label == null:
		return

	if current_npc == null:
		npc_name_label.text = ""
		npc_name_label.visible = false
		return

	var display_name := current_npc.npc_name.strip_edges()
	npc_name_label.text = display_name
	npc_name_label.visible = display_name != ""


# =========================================================
# 刷新当前 NPC 台词
# =========================================================

func _set_npc_dialogue_label_text(text: String) -> void:
	# NpcDialogueLabel 可以是 Label，也可以是 RichTextLabel。
	# 两者都支持 text 属性，但这里分开处理，后续改 BBCode 时更方便。
	if npc_dialogue_label == null:
		return

	if npc_dialogue_label is RichTextLabel:
		var rich_label := npc_dialogue_label as RichTextLabel
		rich_label.text = text
	elif npc_dialogue_label is Label:
		var label := npc_dialogue_label as Label
		label.text = text
	else:
		# 兜底：如果以后换成其它带 text 属性的控件，也尽量写入。
		npc_dialogue_label.set("text", text)

	_show_npc_dialogue_temporarily(text)


func _show_npc_dialogue_temporarily(text: String) -> void:
	if npc_dialogue_label == null:
		return

	var display_text := text.strip_edges()

	npc_dialogue_display_token += 1
	var current_token := npc_dialogue_display_token

	if display_text == "":
		npc_dialogue_visible = false
		npc_dialogue_label.visible = false
		return

	npc_dialogue_visible = true
	npc_dialogue_label.visible = true

	await get_tree().create_timer(NPC_DIALOGUE_AUTO_HIDE_SECONDS).timeout

	if current_token != npc_dialogue_display_token:
		return

	_hide_npc_dialogue()


func _hide_npc_dialogue() -> void:
	if npc_dialogue_label == null:
		return

	if not npc_dialogue_visible:
		return

	npc_dialogue_display_token += 1
	npc_dialogue_visible = false
	npc_dialogue_label.visible = false

	# 提交处方后的治疗结果台词结束后，再显示 JudgementResult。
	# 玩家点击隐藏和 10 秒自动隐藏都会走到这里。
	if waiting_judgement_after_treatment_dialogue:
		waiting_judgement_after_treatment_dialogue = false
		_show_judgement_result_window(
			last_formula_judge_result,
			last_formula_judge_summary_text
		)

# =========================================================
# 刷新当前病人显示
# =========================================================

func refresh_clinic_view() -> void:
	current_npc = npc_manager.get_current_npc()

	current_prescription.clear()
	current_prescription.clear_disease()
	diagnosis_submitted = false

	if window_controller != null:
		window_controller.configure_prescription_context(
			herb_database,
			current_prescription,
			formula_database
		)

	last_formula_judge_result = null
	last_formula_judge_summary_text = ""
	last_newly_unlocked_entry_titles.clear()
	last_reputation_change = 0
	last_experience_change = 0
	waiting_judgement_after_treatment_dialogue = false

	current_display_region_name = DEFAULT_DISPLAY_REGION

	_reset_pulse_keyboard_state()

	if not _ensure_current_npc_valid(true):
		_update_npc_portrait()
		_update_npc_name()

		# ✔ 关键修改：台词完全来自NpcData
		if current_npc != null:
			_set_npc_dialogue_label_text(current_npc.get_dialogue())
		else:
			_set_npc_dialogue_label_text("")

		return

	_update_npc_portrait()
	_update_npc_name()
	_play_random_npc_portrait_entrance.call_deferred()

	# ✔ 关键修改：唯一台词入口
	_set_npc_dialogue_label_text(current_npc.get_dialogue())

	show_region(current_display_region_name)

	if prescription_window != null:
		prescription_window.setup(herb_database, current_prescription, formula_database)

	if clinical_log_window != null and clinical_log_window.has_method("refresh_view"):
		clinical_log_window.refresh_view()

	_update_thoughts_point_ui(true)
	_update_reputation_point_ui(true)


# =========================================================
# 刷新当前NPC（切换/按钮）
# =========================================================

func refresh_current_patient() -> void:
	current_npc = npc_manager.get_current_npc()

	if not _ensure_current_npc_valid(true):
		_update_npc_portrait()
		_update_npc_name()

		# ✔ 迁移后统一入口
		if current_npc != null:
			_set_npc_dialogue_label_text(current_npc.get_dialogue())
		else:
			_set_npc_dialogue_label_text("")

		return

	_update_npc_portrait()
	_update_npc_name()
	_play_random_npc_portrait_entrance.call_deferred()

	# ✔ 关键修改点
	_set_npc_dialogue_label_text(current_npc.get_dialogue())

	show_region(current_display_region_name)


# =========================================================
# 显示单个脉象区域
# =========================================================

func show_region(display_region_name: String) -> void:
	# 显示指定名称的单个脉象区域，并同步刷新信息提示。
	if not _ensure_current_npc_valid(true):
		return

	current_display_region_name = display_region_name

	if pulse_window == null:
		_set_info_text("脉象窗口不存在")
		return

	_show_pulse_result(pulse_window.show_region(display_region_name, current_npc.disease))


# =========================================================
# 显示整只手的四宫格脉象
# =========================================================

func show_hand_group(hand_side: String) -> void:
	# 显示整只手的脉象区域，并同步刷新信息提示。
	# hand_side 建议传入 "left" 或 "right"。
	if not _ensure_current_npc_valid(true):
		return

	if pulse_window == null:
		_set_info_text("脉象窗口不存在")
		return

	_show_pulse_result(pulse_window.show_hand_group(hand_side, current_npc.disease))


# =========================================================
# 键盘把脉
# =========================================================

func _update_pulse_keyboard_display() -> void:
	# 根据键盘输入刷新把脉窗口显示。
	# 规则：
	# 1. 右手 Q/A/Z 三键全按，且左手未按时，显示右手四宫格。
	# 2. 左手 W/S/X 三键全按，且右手未按时，显示左手四宫格。
	# 3. 其它状态显示提示页，避免松键时闪过单个脉象。
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
		show_hand_group("right")
		return

	if left_pressed_count == 3 and right_pressed_count == 0:
		pulse_keyboard_override_active = true
		show_hand_group("left")
		return

	if pulse_keyboard_override_active or total_pressed_count != 0:
		pulse_keyboard_override_active = false
		if pulse_window != null and pulse_window.has_method("show_hint_tab"):
			pulse_window.show_hint_tab()


func _reset_pulse_keyboard_state() -> void:
	pulse_keyboard_override_active = false
	last_pulse_input_signature = ""


# =========================================================
# 清空脉象显示
# =========================================================

func _clear_pulse() -> void:
	if pulse_window != null:
		pulse_window.clear_display()


# =========================================================
# 获取当前病人的 disease_id
# =========================================================

func _get_current_disease_id() -> String:
	if current_npc == null or current_npc.disease == null:
		return ""
	return current_npc.disease.disease_id.strip_edges()


# =========================================================
# 获取当前病人对应标准方
# =========================================================

func _get_current_standard_formula() -> FormulaData:
	if current_npc == null or current_npc.disease == null:
		return null

	var recommended_formula_id := current_npc.disease.recommended_formula_id.strip_edges()
	if recommended_formula_id != "":
		var recommended_formula = formula_database.get_formula_by_id(recommended_formula_id)
		if recommended_formula != null:
			return recommended_formula

	var disease_id := _get_current_disease_id()
	if disease_id == "":
		return null

	var formula_list = formula_database.get_formulas_by_disease(disease_id)
	if formula_list.is_empty():
		return null

	return formula_list[0]

func _get_reputation_reward_by_judge_result(result) -> int:
	if result == null:
		return 0

	var grade := ""
	var raw_grade = result.get("grade")
	if raw_grade != null:
		grade = str(raw_grade).strip_edges()

	match grade:
		"妙手回春":
			return 10
		"治疗成功":
			return 0
		"治疗失败":
			return -10
		_:
			return 0


# =========================================================
# 提交处方并判定
# =========================================================

func submit_prescription() -> bool:
	if current_npc == null:
		_set_info_text("当前没有病人，无法提交处方")
		return false

	if current_npc.disease == null:
		_set_info_text("当前病人没有绑定疾病，无法提交处方")
		return false

	if current_prescription.is_empty():
		_set_info_text("当前处方为空，请先开方")
		return false

	var standard_formula := _get_current_standard_formula()
	if standard_formula == null:
		_set_info_text("未找到疾病【%s】对应的标准方" % current_npc.disease.disease_name)
		return false

	var was_already_submitted := diagnosis_submitted
	var result := formula_judge.judge_formula(current_prescription, standard_formula, current_npc.disease)
	diagnosis_submitted = true

	var summary_text := result.get_summary_text()
	last_formula_judge_result = result
	last_formula_judge_summary_text = summary_text
	last_newly_unlocked_entry_titles.clear()
	last_reputation_change = 0
	last_experience_change = 0

	# random NPC 继续沿用治疗判定时的固定奖励与惩罚。
	# story NPC 的名望和心得不在这里结算，改由后续 StoryData 配置，
	# 并在对应剧情完整播放结束时统一结算。
	var uses_fixed_treatment_rewards := (
		current_npc.npc_type.strip_edges().to_lower() != "story"
	)

	# random NPC 提交判定后根据评级改变名望。
	# 妙手回春：名望 +10；治疗成功：名望不变；治疗失败：名望 -10。
	# was_already_submitted 用于防止同一名病人重复提交刷名望。
	#
	# 说明：
	# - Unlock.add_reputation_points() 会根据当前名望静默检查并解锁剧情。
	# - Clinic 不展示剧情解锁提示，剧情播放仍交给 StoryManager 在触发时机处理。
	var reputation_reward := 0
	if uses_fixed_treatment_rewards:
		reputation_reward = _get_reputation_reward_by_judge_result(result)

	if reputation_reward != 0 and not was_already_submitted:
		if Unlock != null and Unlock.has_method("add_reputation_points"):
			Unlock.add_reputation_points(reputation_reward)
			last_reputation_change = reputation_reward
			_update_reputation_point_ui(true)

			if reputation_reward > 0:
				summary_text += "\n获得名望：+%d" % reputation_reward
			else:
				summary_text += "\n损失名望：%d" % reputation_reward

			if Unlock.has_method("get_reputation_points"):
				summary_text += "\n当前名望：%d" % Unlock.get_reputation_points()

			if SaveManager != null and SaveManager.has_method("save_game"):
				SaveManager.save_game()
	elif reputation_reward != 0 and was_already_submitted:
		summary_text += "\n本病人已提交过处方，不重复改变名望。"
		if Unlock != null and Unlock.has_method("get_reputation_points"):
			summary_text += "\n当前名望：%d" % Unlock.get_reputation_points()

	var result_grade := ""
	if result != null:
		var raw_result_grade = result.get("grade")
		if raw_result_grade != null:
			result_grade = str(raw_result_grade).strip_edges()

	if uses_fixed_treatment_rewards and result_grade == "治疗成功" and not was_already_submitted:
		summary_text += "\n治疗成功：名望、心得不变"
	elif uses_fixed_treatment_rewards and result_grade == "治疗成功" and was_already_submitted:
		summary_text += "\n本病人已提交过处方，名望、心得不变。"

	# random NPC 达成妙手回春时获得 1 点心得，并立刻按累计心得自动解锁条目。
	# was_already_submitted 用于防止同一名病人重复提交刷心得。
	var is_miaoshouhuichun := false
	if result != null and result.has_method("is_miaoshouhuichun"):
		is_miaoshouhuichun = result.is_miaoshouhuichun()
	else:
		is_miaoshouhuichun = result.grade == "妙手回春" and result.score == 100

	if uses_fixed_treatment_rewards and is_miaoshouhuichun and not was_already_submitted:
		var newly_unlocked_titles: Array[String] = []
		if Unlock != null and Unlock.has_method("add_experience_point"):
			newly_unlocked_titles = Unlock.add_experience_point(1)
			last_experience_change = 1

		_update_thoughts_point_ui(true)
		summary_text += "\n获得心得：+1"
		summary_text += "\n当前累计心得：%d" % Unlock.get_experience_points()

		if not newly_unlocked_titles.is_empty():
			last_newly_unlocked_entry_titles.assign(newly_unlocked_titles)
			summary_text += "\n新解锁条目：%s" % "、".join(newly_unlocked_titles)

		if clinical_log_window != null and clinical_log_window.has_method("refresh_view"):
			clinical_log_window.refresh_view()

		# 获得心得和自动解锁后立即存档，避免切场景或退出时丢失。
		if SaveManager != null and SaveManager.has_method("save_game"):
			SaveManager.save_game()
	elif uses_fixed_treatment_rewards and is_miaoshouhuichun and was_already_submitted:
		_update_thoughts_point_ui(true)
		summary_text += "\n本病人已提交过处方，不重复获得心得。"
		summary_text += "\n当前累计心得：%d" % Unlock.get_experience_points()

	# 只有判定成功才视为治愈，切换到治疗后立绘和治疗后台词。
	# 治疗失败则保持治疗前立绘，但显示治疗失败台词。
	current_npc.is_treated = result.success
	current_npc.treatment_failed = not result.success
	_update_npc_portrait()
	_set_npc_dialogue_label_text(current_npc.get_dialogue())

	last_formula_judge_summary_text = summary_text

	_set_info_text(summary_text)
	if OS.is_debug_build():
		result.debug_print()
	return true

# =========================================================
# 判定结果窗口
# =========================================================

func _show_judgement_result_window(judge_result = null, summary_text: String = "") -> void:
	# 当前 NPC 的治疗成功 / 失败台词播放完毕后，弹出 JudgementResult。
	# 玩家点击任意位置关闭该场景后，再刷新到下一名病人。
	if judgement_result_window != null and is_instance_valid(judgement_result_window):
		judgement_result_window.queue_free()
		judgement_result_window = null

	if not ResourceLoader.exists(JUDGEMENT_RESULT_SCENE_PATH):
		_set_info_text("未找到判定结果场景：%s\n%s" % [
			JUDGEMENT_RESULT_SCENE_PATH,
			summary_text
		])
		_go_to_next_patient_after_judgement()
		return

	var packed_scene := load(JUDGEMENT_RESULT_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_set_info_text("判定结果场景加载失败：%s\n%s" % [
			JUDGEMENT_RESULT_SCENE_PATH,
			summary_text
		])
		_go_to_next_patient_after_judgement()
		return

	judgement_result_window = packed_scene.instantiate() as Control
	if judgement_result_window == null:
		_set_info_text("判定结果场景根节点必须继承 Control。\n%s" % summary_text)
		_go_to_next_patient_after_judgement()
		return

	add_child(judgement_result_window)

	if not judgement_result_window.tree_exited.is_connected(_on_judgement_result_window_closed):
		judgement_result_window.tree_exited.connect(
			_on_judgement_result_window_closed,
			Object.CONNECT_ONE_SHOT
		)

	var result_data := _build_judgement_result_data(judge_result, summary_text)

	if judgement_result_window.has_method("show_result"):
		judgement_result_window.call("show_result", result_data)
	else:
		# 兜底：如果 JudgementResult.gd 还没有 show_result()，至少把场景显示出来。
		judgement_result_window.visible = true


func _build_judgement_result_data(judge_result = null, summary_text: String = "") -> Dictionary:
	# JudgementResult 只负责显示，这里把当前病人、标准方和玩家输入整理成文本。
	var npc_name := ""
	var disease_name := ""
	var standard_formula_name := ""
	var standard_formula_text := ""
	var player_disease_name := ""
	var player_prescription_text := ""
	var grade := ""
	var total_score := 0

	if current_npc != null:
		npc_name = current_npc.npc_name
		if current_npc.disease != null:
			disease_name = current_npc.disease.disease_name

	var standard_formula := _get_current_standard_formula()
	if standard_formula != null:
		standard_formula_name = standard_formula.formula_name
		standard_formula_text = _build_standard_formula_display_text(standard_formula)
	else:
		standard_formula_text = "（未找到标准方）"

	if current_prescription != null:
		player_disease_name = current_prescription.disease_name.strip_edges()
		if player_disease_name == "":
			player_disease_name = current_prescription.disease_id.strip_edges()
		if player_disease_name == "":
			player_disease_name = "未选择疾病"
		player_prescription_text = current_prescription.get_display_text()
	else:
		player_disease_name = "未选择疾病"
		player_prescription_text = "（无）"

	if judge_result != null:
		var raw_grade = judge_result.get("grade")
		if raw_grade != null:
			grade = str(raw_grade)

		var raw_score = judge_result.get("score")
		if raw_score != null:
			total_score = int(raw_score)

	return {
		"npc_name": npc_name,
		"disease_name": disease_name,
		"standard_formula_name": standard_formula_name,
		"standard_formula_text": standard_formula_text,
		"player_disease_name": player_disease_name,
		"player_prescription_text": player_prescription_text,
		"grade": grade,
		"total_score": total_score,
		"summary_text": summary_text,
		"newly_unlocked_entry_titles": last_newly_unlocked_entry_titles.duplicate(),
		"show_reward_change": (
			current_npc != null
			and current_npc.npc_type.strip_edges().to_lower() != "story"
		),
		"reputation_change": last_reputation_change,
		"experience_change": last_experience_change
	}


func _build_standard_formula_display_text(formula: FormulaData) -> String:
	if formula == null:
		return "（无）"

	var lines: Array[String] = []
	lines.append("君：" + _build_formula_group_display_text(formula.jun_group))
	lines.append("臣：" + _build_formula_group_display_text(formula.chen_group))
	lines.append("佐：" + _build_formula_group_display_text(formula.zuo_group))
	lines.append("使：" + _build_formula_group_display_text(formula.shi_group))
	return "\n".join(lines)


func _build_formula_group_display_text(group: Array) -> String:
	if group.is_empty():
		return "（无）"

	var parts: Array[String] = []
	for ingredient in group:
		if ingredient == null:
			continue
		if ingredient.has_method("is_valid_data") and not ingredient.is_valid_data():
			continue

		var herb_name := ""
		var amount_text := ""

		if ingredient.has_method("get_herb_name"):
			herb_name = str(ingredient.get_herb_name()).strip_edges()
		if herb_name == "" and ingredient.has_method("get_herb_id"):
			herb_name = str(ingredient.get_herb_id()).strip_edges()

		if ingredient.has_method("get_amount_in_fen"):
			amount_text = HerbUnit.format_fen_auto(int(ingredient.get_amount_in_fen()))

		if herb_name == "":
			continue
		if amount_text == "":
			parts.append(herb_name)
		else:
			parts.append("%s %s" % [herb_name, amount_text])

	if parts.is_empty():
		return "（无）"
	return "、".join(parts)


func _on_judgement_result_window_closed() -> void:
	judgement_result_window = null

	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false

	if not is_inside_tree():
		return

	# 治疗结果台词已经在 JudgementResult 之前播放完毕。
	# 关闭判定结果后，直接进入下一位病人。
	_go_to_next_patient_after_judgement()


func _show_current_patient_result_before_judgement() -> void:
	if current_npc == null:
		_show_judgement_result_window(
			last_formula_judge_result,
			last_formula_judge_summary_text
		)
		return

	waiting_judgement_after_treatment_dialogue = true

	# submit_prescription() 已经写入 is_treated / treatment_failed。
	# 因此这里会显示对应的治疗后立绘，以及成功或失败台词。
	_update_npc_portrait()
	_update_npc_name()

	var treatment_dialogue := current_npc.get_dialogue()
	_set_npc_dialogue_label_text(treatment_dialogue)

	# 没有可显示台词或场景未绑定台词节点时，不阻塞判定结果。
	if treatment_dialogue.strip_edges() == "" or npc_dialogue_label == null:
		waiting_judgement_after_treatment_dialogue = false
		_show_judgement_result_window(
			last_formula_judge_result,
			last_formula_judge_summary_text
		)


func _go_to_next_patient_after_judgement() -> void:
	# 普通 Clinic 只处理日常 random NPC。
	# story NPC 的治疗判定与结果剧情全部由 Story 场景中的隐藏 Clinic 后端处理。
	_replace_with_random_patient()


func _replace_with_random_patient() -> void:
	if npc_manager == null:
		push_warning("Clinic 找不到 NpcManager，无法刷新 random NPC。")
		return

	if npc_manager.has_method("replace_with_random_npc"):
		npc_manager.replace_with_random_npc()
	elif npc_manager.has_method("spawn_random_npc"):
		npc_manager.spawn_random_npc()
	else:
		push_warning("NpcManager 缺少 random NPC 生成接口。")
		return

	refresh_clinic_view()


# =========================================================
# 结束当天接诊
# 作用：
# 1. 停止 Clinic 自动计时
# 2. 告诉 Main：Clinic 已完成当前阶段
# 3. 后面 Main 收到后可切到 Bookshelf / 夜晚流程
# =========================================================

func finish_clinic_for_today() -> void:
	# 防止时间结束和按钮点击同时触发，导致重复切场景
	if clinic_finished_emitted:
		return

	clinic_finished_emitted = true

	# Clinic 结束时停止 GameTimeManager 里的 Clinic 计时器
	if GameTime.has_method("stop_clinic_clock"):
		GameTime.stop_clinic_clock()

	print("Clinic 发出 clinic_finished")
	emit_signal("clinic_finished")

# =========================================================
# 病人切换按钮
# =========================================================

func _on_prev_button_pressed() -> void:
	npc_manager.prev_npc()
	refresh_clinic_view()


func _on_next_button_pressed() -> void:
	npc_manager.next_npc()
	refresh_clinic_view()


func _on_spawn_npc_button_pressed() -> void:
	if npc_manager.has_method("replace_with_random_npc"):
		npc_manager.replace_with_random_npc()
	else:
		npc_manager.spawn_random_npc()
	refresh_clinic_view()


func _on_submit_button_pressed() -> void:
	# 兼容旧提交按钮。当前主要由 PrescriptionWindow 的 submit_requested 信号触发。
	submit_prescription()


# =========================================================
# 脉象窗口
# =========================================================


func _on_pulse_panel_region_selected(display_region_name: String) -> void:
	pulse_keyboard_override_active = false
	show_region(display_region_name)


func _on_window_controller_pulse_window_opened() -> void:
	last_pulse_input_signature = ""


func _on_window_controller_pulse_window_closed() -> void:
	_reset_pulse_keyboard_state()


func _on_prescription_info_requested(text: String) -> void:
	_set_info_text(text)


# =========================================================
# 接收 PrescriptionWindow 发回的提交请求
# =========================================================

func _on_prescription_submit_requested() -> void:
	# 接收开方窗口的提交请求。
	# 只有处方成功判定后，才关闭治疗窗口。
	# random NPC 会先播放治疗成功 / 失败台词，再弹出 JudgementResult。
	if not submit_prescription():
		return

	if window_controller != null:
		window_controller.close_treatment_windows_after_submit()

	_show_current_patient_result_before_judgement()


func _on_end_today_pressed() -> void:
	# InfoWindow 中“结束当天”按钮的回调。
	finish_clinic_for_today()


# =========================================================
# 设置当前天数（由 Main 调用）
# =========================================================

func set_day(day: int) -> void:
	current_day = day
	_update_clinic_background()

	# DayLabel / TimeLabel 统一从 GameTimeManager 刷新
	_update_time_ui()
	_update_thoughts_point_ui(true)
	_update_reputation_point_ui(true)


# =========================================================
# 快捷键输入
# Ctrl + T 打开信息测试窗口
# =========================================================

func _input(event: InputEvent) -> void:
	if story_treatment_backend_mode:
		return

	# 判定结果窗口显示期间，不处理底层 Clinic 的台词点击。
	# 避免点击 JudgementResult 时误触底层台词隐藏逻辑。
	if judgement_result_window != null and is_instance_valid(judgement_result_window):
		return

	# NPC 台词显示期间，点击任意区域隐藏台词。
	# 这次点击会被标记为已处理，避免误触下面的按钮。
	if npc_dialogue_visible:
		if event is InputEventMouseButton:
			var mouse_event := event as InputEventMouseButton
			if mouse_event.pressed:
				_hide_npc_dialogue()
				get_viewport().set_input_as_handled()
				return

		if event is InputEventScreenTouch:
			var touch_event := event as InputEventScreenTouch
			if touch_event.pressed:
				_hide_npc_dialogue()
				get_viewport().set_input_as_handled()
				return

	if event is InputEventKey:
		# 只在按下瞬间触发，避免长按重复弹出
		if event.pressed and not event.echo:
			# 判断是否按下 Ctrl + T
			if event.ctrl_pressed and event.keycode == KEY_T:
				if window_controller != null:
					window_controller.open_info_window()
				get_viewport().set_input_as_handled()
				return

# =========================================================
# 测试功能：一键解锁所有条目
# =========================================================
func _on_unlock_all_entries_requested() -> void:
	var result: Dictionary = Unlock.unlock_all_entries_for_test()

	_set_info_text("测试功能：已解锁全部条目\n条目：%d\n药材：%d\n方剂：%d\n疾病：%d\n医理：%d" % [
		result.get("entry_count", 0),
		result.get("herb_count", 0),
		result.get("formula_count", 0),
		result.get("disease_count", 0),
		result.get("theory_count", 0)
	])

	if clinical_log_window != null and clinical_log_window.has_method("refresh_view"):
		clinical_log_window.refresh_view()


# =========================================================
# Story 场景诊疗后端接口
# 说明：
# 1. 这些接口只提供数据和判定，不负责 Story 的画面。
# 2. story NPC 仍由 NpcManager 加载，处方仍由 Clinic 持有并提交。
# 3. Story.tscn 中实例化的四个窗口只负责表现。
# =========================================================

func prepare_story_npc_treatment(
	npc_id: String,
	treatment_disease: DiseaseData,
	day: int
) -> bool:
	current_day = day
	last_info_text = ""

	var clean_npc_id := npc_id.strip_edges()
	if clean_npc_id == "":
		_set_info_text("剧情没有配置 clinic_npc_id。")
		return false

	if treatment_disease == null:
		_set_info_text("发起诊疗的剧情没有配置 Disease。")
		return false

	if npc_manager == null or not npc_manager.has_method("replace_with_story_npc"):
		_set_info_text("Clinic 找不到可用的 NpcManager story NPC 接口。")
		return false

	var npc: NpcData = npc_manager.replace_with_story_npc(
		clean_npc_id,
		treatment_disease
	)
	if npc == null:
		_set_info_text("story NPC 加载失败：%s" % clean_npc_id)
		return false

	if npc.npc_type.strip_edges().to_lower() != "story":
		_set_info_text("NPC【%s】的 npc_type 不是 story。" % clean_npc_id)
		return false

	current_npc = npc
	current_prescription.clear()
	current_prescription.clear_disease()
	diagnosis_submitted = false
	last_formula_judge_result = null
	last_formula_judge_summary_text = ""
	last_newly_unlocked_entry_titles.clear()
	last_reputation_change = 0
	last_experience_change = 0
	waiting_judgement_after_treatment_dialogue = false
	_reset_pulse_keyboard_state()
	return true


func get_story_treatment_npc_name() -> String:
	if current_npc == null:
		return ""
	return current_npc.npc_name


func get_story_treatment_prescription():
	return current_prescription


func show_story_pulse_region(target_pulse_window: Node, display_region_name: String) -> Dictionary:
	if current_npc == null or current_npc.disease == null:
		return {
			"ok": false,
			"text": "当前没有可诊疗的剧情病人。"
		}

	if target_pulse_window == null or not target_pulse_window.has_method("show_region"):
		return {
			"ok": false,
			"text": "Story 的 PulseWindow 不可用。"
		}

	var raw_result = target_pulse_window.call(
		"show_region",
		display_region_name,
		current_npc.disease
	)
	if typeof(raw_result) == TYPE_DICTIONARY:
		return raw_result

	return {
		"ok": false,
		"text": "Story 的 PulseWindow 返回了无效数据。"
	}


func show_story_pulse_hand(target_pulse_window: Node, hand_side: String) -> Dictionary:
	if current_npc == null or current_npc.disease == null:
		return {
			"ok": false,
			"text": "当前没有可诊疗的剧情病人。"
		}

	if target_pulse_window == null or not target_pulse_window.has_method("show_hand_group"):
		return {
			"ok": false,
			"text": "Story 的 PulseWindow 不可用。"
		}

	var raw_result = target_pulse_window.call(
		"show_hand_group",
		hand_side,
		current_npc.disease
	)
	if typeof(raw_result) == TYPE_DICTIONARY:
		return raw_result

	return {
		"ok": false,
		"text": "Story 的 PulseWindow 返回了无效数据。"
	}


func submit_story_prescription() -> Dictionary:
	# 使用与普通 Clinic 相同的处方判定逻辑，但不打开 Clinic 自己的结果窗口。
	# submit_prescription() 会识别 story NPC，因此不会在治疗判定时结算固定奖励或惩罚。
	if not submit_prescription():
		return {
			"ok": false,
			"message": last_info_text
		}

	return {
		"ok": true,
		"success": current_npc != null and current_npc.is_treated,
		"result_data": _build_judgement_result_data(
			last_formula_judge_result,
			last_formula_judge_summary_text
		)
	}


func finish_story_treatment_attempt(
	success: bool,
	trigger_scene: String,
	treatment_story_id: String = ""
) -> StoryData:
	if current_npc == null:
		return null

	var clean_trigger_scene := trigger_scene.strip_edges()
	if clean_trigger_scene == "":
		clean_trigger_scene = "clinic"
	var clean_treatment_story_id := treatment_story_id.strip_edges()

	var next_story: StoryData = null

	if success:
		if StoryManager != null and StoryManager.has_method("report_story_npc_cured"):
			next_story = StoryManager.report_story_npc_cured(
				current_day,
				clean_trigger_scene,
				clean_treatment_story_id
			)
	else:
		if StoryManager != null and StoryManager.has_method("report_story_npc_treatment_failed"):
			next_story = StoryManager.report_story_npc_treatment_failed(
				current_day,
				clean_trigger_scene,
				clean_treatment_story_id
			)

		# 失败后继续治疗同一名 story NPC。
		# diagnosis_submitted 保持 true，只清空下一次诊疗需要重开的处方。
		current_npc.is_treated = false
		current_npc.treatment_failed = false
		current_prescription.clear()
		current_prescription.clear_disease()
		last_formula_judge_result = null
		last_formula_judge_summary_text = ""
		last_newly_unlocked_entry_titles.clear()
		last_reputation_change = 0
		last_experience_change = 0

	if SaveManager != null and SaveManager.has_method("save_game"):
		SaveManager.save_game()

	return next_story


# =========================================================
# 剧情系统入口
# 说明：
# 1. Clinic 只负责在合适时机请求剧情。
# 2. 剧情是否满足触发条件，统一交给 StoryManager 判断。
# 3. Clinic 仍然通过 story_requested 通知 Main 切换到 Story.tscn。
# 4. 为了兼容你现在的 Main.gd，这里仍然传 story_path，不传空路径。
# =========================================================

func start_story_from_clinic(story_path: String, return_target: String = "clinic") -> void:
	# story_path 示例：res://Data/Story/teaching_test.tres
	# Clinic 不直接切换 Story 场景，只向 Main 发出请求。
	# return_target 使用逻辑名，例如："clinic" / "night"。
	if story_path.is_empty():
		push_warning("Clinic.start_story_from_clinic 收到空剧情路径。")
		return

	emit_signal("story_requested", story_path, return_target)

func start_new_day(day: int) -> void:
	# 记录当前天数。
	current_day = day

	# 按当天对应的节气切换诊室四季背景。
	_update_clinic_background()

	# 每天开始时，允许 Clinic 结束信号重新发出。
	# 否则第一天结束后，第二天可能无法再次进入夜晚流程。
	clinic_finished_emitted = false

	# 刷新时间、心得和名望显示。
	_update_time_ui()
	_update_thoughts_point_ui(true)
	_update_reputation_point_ui(true)

	# 自动剧情触发入口.
	# 具体触发条件不再写死在 Clinic.gd，改由 StoryData + StoryManager 决定。
	if _try_start_auto_story("clinic", current_day):
		return

	# 没有剧情指定的 story NPC，也没有入口剧情时，
	# 才生成当天的日常 random NPC。
	_replace_with_random_patient()


func _try_start_auto_story(trigger_scene: String, day: int) -> bool:
	# StoryManager 没有接好时，直接跳过，避免阻塞诊室流程。
	if StoryManager == null:
		push_warning("Clinic 无法访问 StoryManager。")
		return false

	# 需要使用之前修改过的 StoryManager.gd。
	# 其中必须包含 find_trigger_story(trigger_scene, current_day)。
	if not StoryManager.has_method("find_trigger_story"):
		push_warning("StoryManager 缺少 find_trigger_story()，无法自动检查剧情触发条件。")
		return false

	# 让 StoryManager 统一检查是否有满足条件的剧情。
	var story: StoryData = StoryManager.find_trigger_story(trigger_scene, day)
	if story == null:
		return false

	return _request_story_data(story)


func _request_story_data(story: StoryData) -> bool:
	if story == null:
		return false

	# 找到这个 StoryData 对应的资源路径。
	# 这样可以继续兼容 Main.gd 当前的 story_requested(story_path, return_target) 逻辑。
	var story_path := _find_registered_story_path(story)
	if story_path.is_empty():
		push_warning("找到可触发剧情，但没有找到对应资源路径。请检查 StoryManager.registered_story_paths。")
		return false

	# 优先使用 StoryData 自己配置的 return_scene。
	# 如果没有配置，就默认返回 clinic。
	var return_target := "clinic"
	if story.return_scene != "":
		return_target = story.return_scene

	# 仍然只发信号给 Main，不在 Clinic 里直接切换场景。
	start_story_from_clinic(story_path, return_target)
	return true


func _find_registered_story_path(target_story: StoryData) -> String:
	# 从 StoryManager.registered_story_paths 中反查剧情资源路径。
	# 这样自动触发仍然由 StoryManager 管理剧情列表。
	if target_story == null:
		return ""

	# 如果 StoryManager 还没有 registered_story_paths，说明使用的不是新版 StoryManager。
	var story_paths = StoryManager.get("registered_story_paths")
	if typeof(story_paths) != TYPE_ARRAY:
		push_warning("StoryManager 缺少 registered_story_paths。")
		return ""

	for story_path in story_paths:
		if typeof(story_path) != TYPE_STRING:
			continue

		var loaded_story: Resource = load(story_path)
		if loaded_story == null:
			continue

		if not loaded_story is StoryData:
			continue

		var story := loaded_story as StoryData

		# Godot 资源通常会被缓存，同一路径加载到的是同一个资源实例。
		# 这里先用实例比较，最直接。
		if story == target_story:
			return story_path

		# 如果实例比较失败，就用 story_id 再兜底比较。
		var target_story_id: String = target_story.get("story_id")
		var current_story_id: String = story.get("story_id")
		if not target_story_id.is_empty() and target_story_id == current_story_id:
			return story_path

	return ""
