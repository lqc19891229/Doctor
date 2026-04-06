extends Window
class_name PulseWindowUI

# =========================================================
# PulseWindowUI.gd
# 脉象窗口主控制脚本
#
# 主要职责：
# 1. 管理脉象窗口内部按钮点击
# 2. 管理单区域显示
# 3. 管理整手显示
# 4. 管理 PulseDrawer 的绘制调用
# 5. 对外只暴露少量接口给 Clinic.gd
# =========================================================

## 对外信号：当用户点击按钮切换区域时，通知 Clinic
signal region_selected(display_region_name: String)

# =========================================================
# 常量定义
# =========================================================

## 脉象显示名称 -> 疾病内部区域名称 / Drawer区域ID
const REGION_CONFIG := {
	"浮脉": {"disease_name": "表",   "region_id": "exterior"},
	"左寸": {"disease_name": "心",   "region_id": "heart"},
	"左关": {"disease_name": "肝",   "region_id": "liver"},
	"左尺": {"disease_name": "肾阴", "region_id": "kidney_yin"},
	"右寸": {"disease_name": "肺",   "region_id": "lung"},
	"右关": {"disease_name": "脾",   "region_id": "spleen"},
	"右尺": {"disease_name": "肾阳", "region_id": "kidney_yang"},
}

## 整手显示配置
const HAND_GROUP_CONFIG := {
	"right": {
		region_ids = ["exterior", "kidney_yang", "spleen", "lung"],
		display_names = ["浮脉", "右尺", "右关", "右寸"],
		disease_names = ["表", "肾阳", "脾", "肺"]
	},
	"left": {
	region_ids = ["exterior", "kidney_yin", "liver", "heart"],
	display_names = ["浮脉", "左尺", "左关", "左寸"],
	disease_names = ["表", "肾阴", "肝", "心"]
	}
}

# =========================================================
# 节点引用
# =========================================================

@onready var pulse_panel = $PulsePanel
@onready var pulse_drawer = $PulsePanel/PulsePanelLayout/PulseDrawer
@onready var right_button_row = $PulsePanel/PulsePanelLayout/RightPulseButtonRow
@onready var left_button_row = $PulsePanel/PulsePanelLayout/LeftPulseButtonRow

# =========================================================
# 生命周期
# =========================================================

func _ready() -> void:
	## 连接窗口关闭事件
	if not close_requested.is_connected(_on_close_requested):
		close_requested.connect(_on_close_requested)

	## 连接左右两边按钮
	_connect_region_buttons(right_button_row)
	_connect_region_buttons(left_button_row)

# =========================================================
# 对外接口：窗口开关
# =========================================================

func open_window() -> void:
	show()
	grab_focus()


func close_window() -> void:
	hide()


func _on_close_requested() -> void:
	hide()

# =========================================================
# 对外接口：显示单区域
# =========================================================

func show_region(display_region_name: String, disease) -> Dictionary:
	## 返回结果字典，供 Clinic 更新 info_label
	## 这样 Clinic 不需要再碰 PulseDrawer
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

	var disease_region_name := str(REGION_CONFIG[display_region_name]["disease_name"])
	var region_id := str(REGION_CONFIG[display_region_name]["region_id"])

	var region_data = disease.get_region_pulse_values(disease_region_name)
	if region_data.is_empty():
		clear_display()
		result.text = "当前部位：%s\n对应区域：%s\n未找到区域数据" % [
			display_region_name,
			disease_region_name
		]
		return result

	## 先把全部区域数据交给 Drawer
	if pulse_drawer != null and pulse_drawer.has_method("set_pulse_regions"):
		pulse_drawer.set_pulse_regions(disease.get_pulse_regions_for_drawer_visual())

	## 再切换到当前目标区域
	if pulse_drawer != null and pulse_drawer.has_method("set_region"):
		pulse_drawer.set_region(region_id)

	## 如果 Panel 未来需要同步当前区域，可在这里扩展
	if pulse_panel != null and pulse_panel.has_method("select_region"):
		pulse_panel.select_region(display_region_name)

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
# 对外接口：显示整手
# =========================================================

func show_hand_group(hand_side: String, disease) -> Dictionary:
	## 返回结果字典，供 Clinic 更新 info_label
	var result := {
		"ok": false,
		"text": ""
	}

	if disease == null:
		clear_display()
		result.text = "当前没有疾病数据"
		return result

	if not HAND_GROUP_CONFIG.has(hand_side):
		clear_display()
		result.text = "未知整手类型：" + hand_side
		return result

	var config = HAND_GROUP_CONFIG[hand_side]

	## 先把全部区域数据交给 Drawer
	if pulse_drawer != null and pulse_drawer.has_method("set_pulse_regions"):
		pulse_drawer.set_pulse_regions(disease.get_pulse_regions_for_drawer_visual())

	## 组装要显示的区域 ID 列表
	var region_ids: Array[String] = []
	for id in config["region_ids"]:
		region_ids.append(str(id))

	## 切到整手显示模式
	if pulse_drawer != null and pulse_drawer.has_method("set_group_regions"):
		pulse_drawer.set_group_regions(region_ids)

	var display_names: Array = config["display_names"]
	var disease_names: Array = config["disease_names"]

	var detail_lines: Array[String] = []

	for i in range(disease_names.size()):
		var disease_region_name := str(disease_names[i])
		var display_region_name := str(display_names[i])
		var region_data = disease.get_region_pulse_values(disease_region_name)

		if region_data.is_empty():
			detail_lines.append("%s（%s）：无数据" % [display_region_name, disease_region_name])
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
		"右" if hand_side == "right" else "左",
		display_names[0], display_names[1], display_names[2], display_names[3],
		"\n".join(detail_lines)
	]
	return result

# =========================================================
# 对外接口：清空显示
# =========================================================

func clear_display() -> void:
	if pulse_drawer == null:
		return

	if pulse_drawer.has_method("clear_display"):
		pulse_drawer.clear_display()

	if pulse_drawer.has_method("set_pulse_values"):
		pulse_drawer.set_pulse_values(0.0, 0.0, 1.0, 10.0)

# =========================================================
# 内部：按钮连接
# =========================================================

func _connect_region_buttons(container: Node) -> void:
	if container == null:
		return

	for child in container.get_children():
		if child is Button:
			child.pressed.connect(_on_region_button_pressed.bind(child))

# =========================================================
# 内部：按钮点击处理
# 把节点名映射成显示名，再通知 Clinic
# =========================================================

func _on_region_button_pressed(button: Button) -> void:
	var display_region_name := ""

	match button.name:
		"RightCunButton":
			display_region_name = "右寸"
		"RightGuanButton":
			display_region_name = "右关"
		"RightChiButton":
			display_region_name = "右尺"
		"LeftCunButton":
			display_region_name = "左寸"
		"LeftGuanButton":
			display_region_name = "左关"
		"LeftChiButton":
			display_region_name = "左尺"

	if display_region_name != "":
		region_selected.emit(display_region_name)
