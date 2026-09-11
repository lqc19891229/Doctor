extends Window
class_name PulseWindow

# =========================================================
# PulseWindow.gd
# 三层脉象窗口控制脚本
#
# 第一层：按键提示
# 第二层：右手四个脉象图
# 第三层：左手四个脉象图
#
# 注意：
# 这里不再使用旧版按钮节点。
# 旧版的 RightPulseButtonRow / LeftPulseButtonRow 已经删除。
# =========================================================

# 对外信号保留，避免 Clinic.gd 里如果有连接时报错
signal region_selected(display_region_name: String)


# =========================================================
# 窗口位置锁定
#
# 默认值与 PulseWindow.tscn 当前的位置 Vector2i(0, 36) 一致。
# 如需改变固定位置，可以直接在检查器里修改此参数。
# =========================================================
@export var fixed_window_position: Vector2i = Vector2i(0, 36)


# =========================================================
# 单个显示名 -> 疾病内部区域名 / PulseDrawer 区域 ID
# =========================================================
const REGION_CONFIG := {
	"浮脉": {
		"disease_name": "表",
		"region_id": "exterior"
	},
	"左寸": {
		"disease_name": "心",
		"region_id": "heart"
	},
	"左关": {
		"disease_name": "肝",
		"region_id": "liver"
	},
	"左尺": {
		"disease_name": "肾阴",
		"region_id": "kidney_yin"
	},
	"右寸": {
		"disease_name": "肺",
		"region_id": "lung"
	},
	"右关": {
		"disease_name": "脾",
		"region_id": "spleen"
	},
	"右尺": {
		"disease_name": "肾阳",
		"region_id": "kidney_yang"
	}
}


# =========================================================
# 右手四图显示顺序
# =========================================================
const RIGHT_HAND_REGION_IDS: Array[String] = [
	"exterior",
	"kidney_yang",
	"spleen",
	"lung"
]

const RIGHT_HAND_DISPLAY_NAMES: Array[String] = [
	"浮脉",
	"右尺",
	"右关",
	"右寸"
]

const RIGHT_HAND_DISEASE_NAMES: Array[String] = [
	"表",
	"肾阳",
	"脾",
	"肺"
]


# =========================================================
# 左手四图显示顺序
# =========================================================
const LEFT_HAND_REGION_IDS: Array[String] = [
	"exterior",
	"kidney_yin",
	"liver",
	"heart"
]

const LEFT_HAND_DISPLAY_NAMES: Array[String] = [
	"浮脉",
	"左尺",
	"左关",
	"左寸"
]

const LEFT_HAND_DISEASE_NAMES: Array[String] = [
	"表",
	"肾阴",
	"肝",
	"心"
]


# =========================================================
# 节点引用
# =========================================================
@onready var layer_tabs: TabContainer = $LayerTabs
@onready var right_pulse_drawer: Control = $LayerTabs/右手脉象/RightHandLayout/RightPulseDrawer
@onready var left_pulse_drawer: Control = $LayerTabs/左手脉象/LeftHandLayout/LeftPulseDrawer


# =========================================================
# 生命周期
# =========================================================
func _ready() -> void:
	# 初始化时放到固定位置
	position = fixed_window_position

	# 关闭窗口时只隐藏窗口，不销毁窗口
	if not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)

	# 不论窗口通过按钮、Esc、右上角还是场景切换隐藏，
	# 都确保心跳立即停止。
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)


# =========================================================
# 窗口位置锁定
# =========================================================
func _process(_delta: float) -> void:
	# 窗口显示期间，阻止玩家拖动标题栏改变窗口位置
	if visible and position != fixed_window_position:
		position = fixed_window_position


# =========================================================
# 打开窗口
# =========================================================
func open_window() -> void:
	# 每次打开时恢复固定位置
	position = fixed_window_position

	# 先显示窗口
	show()

	# 等当前这一帧的快捷键/刷新逻辑跑完后，
	# 再切回按键提示页，避免被 show_region() 立刻切到右手页
	call_deferred("_switch_to_hint_tab")

	# 让窗口获得焦点
	grab_focus()


# =========================================================
# 关闭窗口
# =========================================================
func close_window() -> void:
	SfxManager.stop_heartbeat()
	hide()


# =========================================================
# 点击窗口右上角关闭按钮
# =========================================================

# =========================================================
# Esc 快捷键关闭窗口
# =========================================================

# =========================================================
# Clinic 主界面窗口快捷键转发
# =========================================================
const CLINIC_SHORTCUT_OPEN_PULSE := KEY_F1
const CLINIC_SHORTCUT_OPEN_PRESCRIPTION := KEY_F2
const CLINIC_SHORTCUT_OPEN_CLINICAL_LOG := KEY_F3


func _input(event: InputEvent) -> void:
	if _try_handle_escape(event):
		return

	if _try_handle_clinic_window_shortcut(event):
		return


func _try_handle_escape(event: InputEvent) -> bool:
	if not visible:
		return false

	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	if key_event.keycode != KEY_ESCAPE:
		return false

	# 把脉窗口没有搜索栏：Esc 直接关闭当前窗口。
	# 事件在这里被处理后，不会继续传给 Main 的 PauseMenu。
	close_window()
	get_viewport().set_input_as_handled()
	return true


func _try_handle_clinic_window_shortcut(event: InputEvent) -> bool:
	if not visible:
		return false

	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	if key_event.alt_pressed or key_event.ctrl_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return false

	var shortcut_target := _find_window_shortcut_target()
	if shortcut_target == null:
		return false

	var handled := false

	match key_event.keycode:
		CLINIC_SHORTCUT_OPEN_PULSE:
			handled = _open_shortcut_window(shortcut_target, "pulse")

		CLINIC_SHORTCUT_OPEN_PRESCRIPTION:
			handled = _open_shortcut_window(shortcut_target, "prescription")

		CLINIC_SHORTCUT_OPEN_CLINICAL_LOG:
			handled = _open_shortcut_window(shortcut_target, "clinical_log")

		_:
			return false

	if not handled:
		return false

	get_viewport().set_input_as_handled()
	return true


func _open_shortcut_window(shortcut_target: Node, window_type: String) -> bool:
	if shortcut_target == null:
		return false

	match window_type:
		"pulse":
			# Clinic 使用 ClinicWindowController 的公开接口。
			if shortcut_target.has_method("open_pulse_window"):
				shortcut_target.call("open_pulse_window")
				return true

			# Story 治疗模式直接复用 Story.gd 已有按钮回调。
			if shortcut_target.has_method("_on_pulse_button_pressed"):
				shortcut_target.call("_on_pulse_button_pressed")
				return true

		"prescription":
			if shortcut_target.has_method("open_prescription_window"):
				shortcut_target.call("open_prescription_window")
				return true

			if shortcut_target.has_method("_on_prescription_button_pressed"):
				shortcut_target.call("_on_prescription_button_pressed")
				return true

		"clinical_log":
			if shortcut_target.has_method("open_clinical_log_window"):
				shortcut_target.call("open_clinical_log_window")
				return true

			if shortcut_target.has_method("_on_clinical_log_button_pressed"):
				shortcut_target.call("_on_clinical_log_button_pressed")
				return true

	return false


func _find_window_shortcut_target() -> Node:
	var node := get_parent()

	while node != null:
		# Story 优先：
		# Story 与 Clinic 会同时常驻 Main。旧代码一路递归 find_child，
		# 最后会从 Main 找到隐藏 Clinic 的 ClinicWindowController，
		# 导致 Story 窗口把 F1/F2/F3 错发给 Clinic。
		#
		# 只要当前祖先就是 Story 治疗界面，就立刻返回 Story，
		# 不再继续向 Main 搜索。
		if (
			node.has_method("_on_pulse_button_pressed")
			and node.has_method("_on_prescription_button_pressed")
			and node.has_method("_on_clinical_log_button_pressed")
		):
			return node

		# Clinic 只允许查找“当前祖先的直接子节点”控制器，
		# 禁止递归搜索其它常驻场景，避免再次串到错误的 Clinic 实例。
		var controller := node.get_node_or_null("ClinicWindowController")
		if controller != null:
			return controller

		node = node.get_parent()

	return null

func _unhandled_input(event: InputEvent) -> void:
	# 窗口未显示时，不处理 Esc，避免影响其他界面
	if not visible:
		return

	# 只处理键盘事件
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey

	# 只处理按下瞬间，忽略长按重复触发
	if not key_event.pressed or key_event.echo:
		return

	# 只响应 Esc 键
	if key_event.keycode != KEY_ESCAPE:
		return

	# 关闭当前窗口
	close_window()

	# 阻止 Esc 继续向下传递，避免影响其他窗口或主场景
	get_viewport().set_input_as_handled()


func _on_close_requested() -> void:
	SfxManager.stop_heartbeat()
	hide()


func _on_visibility_changed() -> void:
	if not visible:
		SfxManager.stop_heartbeat()


# =========================================================
# 显示单个部位
#
# 说明：
# 现在不再只画一个脉象。
# 按到右手键，就切到右手页，显示右手四图。
# 按到左手键，就切到左手页，显示左手四图。
# =========================================================
func show_region(display_region_name: String, disease) -> Dictionary:
	var result := {
		"ok": false,
		"text": ""
	}

	if disease == null:
		clear_display()
		result.text = "当前没有疾病数据"
		return result

	if not REGION_CONFIG.has(display_region_name):
		clear_display()
		result.text = "未知脉诊区域：" + display_region_name
		return result

	# 每次查看时，同时刷新左右两页的数据
	_refresh_all_drawers(disease)

	# 根据按键对应部位，自动切换到对应页面
	_switch_tab_by_region(display_region_name)

	var disease_region_name := str(REGION_CONFIG[display_region_name]["disease_name"])
	var region_data = disease.get_region_pulse_values(disease_region_name)

	if region_data.is_empty():
		result.text = "当前部位：%s\n对应区域：%s\n未找到区域数据" % [
			display_region_name,
			disease_region_name
		]
		return result

	result.ok = true
	result.text = "当前查看：%s\n对应区域：%s\n气：%s  血：%s  寒热：%s  湿燥：%s" % [
		display_region_name,
		disease_region_name,
		region_data.get("qi", 0.0),
		region_data.get("blood", 0.0),
		region_data.get("cold_hot", 0.0),
		region_data.get("wet_dry", 0.0)
	]

	return result


# =========================================================
# 显示整手
#
# hand_side:
# right = 右手
# left  = 左手
# =========================================================
func show_hand_group(hand_side: String, disease) -> Dictionary:
	var result := {
		"ok": false,
		"text": ""
	}

	if disease == null:
		clear_display()
		result.text = "当前没有疾病数据"
		return result

	# 每次查看时，同时刷新左右两页的数据
	_refresh_all_drawers(disease)

	var display_names: Array[String] = []
	var disease_names: Array[String] = []
	var hand_name := ""

	if hand_side == "right":
		display_names = RIGHT_HAND_DISPLAY_NAMES
		disease_names = RIGHT_HAND_DISEASE_NAMES
		hand_name = "右"

		# 切到右手脉象页
		_switch_to_right_tab()

	elif hand_side == "left":
		display_names = LEFT_HAND_DISPLAY_NAMES
		disease_names = LEFT_HAND_DISEASE_NAMES
		hand_name = "左"

		# 切到左手脉象页
		_switch_to_left_tab()

	else:
		result.text = "未知整手类型：" + hand_side
		return result

	var detail_lines: Array[String] = []

	for i in range(disease_names.size()):
		var disease_region_name := disease_names[i]
		var display_region_name := display_names[i]
		var region_data = disease.get_region_pulse_values(disease_region_name)

		if region_data.is_empty():
			detail_lines.append("%s（%s）：无数据" % [
				display_region_name,
				disease_region_name
			])
		else:
			detail_lines.append(
				"%s（%s） 气：%s  血：%s  寒热：%s  湿燥：%s" % [
					display_region_name,
					disease_region_name,
					region_data.get("qi", 0.0),
					region_data.get("blood", 0.0),
					region_data.get("cold_hot", 0.0),
					region_data.get("wet_dry", 0.0)
				]
			)

	result.ok = true
	result.text = "当前查看：%s手整手脉象\n显示顺序：%s / %s / %s / %s\n\n%s" % [
		hand_name,
		display_names[0],
		display_names[1],
		display_names[2],
		display_names[3],
		"\n".join(detail_lines)
	]

	return result


# =========================================================
# 同时刷新左右两页脉象图
# =========================================================
func _refresh_all_drawers(disease) -> void:
	if disease == null:
		clear_display()
		return

	var all_regions: Dictionary = disease.get_pulse_regions_for_drawer_visual()

	# 右手页：浮脉 / 右尺 / 右关 / 右寸
	if right_pulse_drawer != null:
		if right_pulse_drawer.has_method("set_pulse_regions"):
			right_pulse_drawer.set_pulse_regions(all_regions)

		if right_pulse_drawer.has_method("set_group_regions"):
			right_pulse_drawer.set_group_regions(RIGHT_HAND_REGION_IDS)

	# 左手页：浮脉 / 左尺 / 左关 / 左寸
	if left_pulse_drawer != null:
		if left_pulse_drawer.has_method("set_pulse_regions"):
			left_pulse_drawer.set_pulse_regions(all_regions)

		if left_pulse_drawer.has_method("set_group_regions"):
			left_pulse_drawer.set_group_regions(LEFT_HAND_REGION_IDS)


# =========================================================
# 根据当前部位自动切换标签页
# =========================================================
func _switch_tab_by_region(display_region_name: String) -> void:
	if display_region_name.begins_with("右"):
		_switch_to_right_tab()
	elif display_region_name.begins_with("左"):
		_switch_to_left_tab()
	elif display_region_name == "浮脉":
		# 浮脉左右页都有，这里默认切到右手页
		_switch_to_right_tab()


# =========================================================
# 切到按键提示页
# =========================================================
func _switch_to_hint_tab() -> void:
	if layer_tabs != null:
		layer_tabs.current_tab = 0
		
# =========================================================
# 外部调用：切回按键提示页
# 用途：
# Clinic.gd 检测到玩家松开所有脉诊快捷键后，
# 调用这个函数，让窗口回到第 1 页“按键提示”。
# =========================================================
func show_hint_tab() -> void:
	# 松开脉诊快捷键后，先清空左右脉象图
	# 避免切回按键提示页时闪过上一帧的脉象画面
	clear_display()

	# 立刻切回第 1 页：按键提示
	_switch_to_hint_tab()

# =========================================================
# 切到右手脉象页
# =========================================================
func _switch_to_right_tab() -> void:
	if layer_tabs != null:
		layer_tabs.current_tab = 1


# =========================================================
# 切到左手脉象页
# =========================================================
func _switch_to_left_tab() -> void:
	if layer_tabs != null:
		layer_tabs.current_tab = 2


# =========================================================
# 清空显示
# =========================================================
func clear_display() -> void:
	if right_pulse_drawer != null:
		if right_pulse_drawer.has_method("clear_display"):
			right_pulse_drawer.clear_display()

	if left_pulse_drawer != null:
		if left_pulse_drawer.has_method("clear_display"):
			left_pulse_drawer.clear_display()
