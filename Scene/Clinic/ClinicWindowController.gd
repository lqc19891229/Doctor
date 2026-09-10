extends Node
class_name ClinicWindowController

# =========================================================
# ClinicWindowController.gd
# 诊室窗口与快捷键控制器
#
# 负责：
# 1. F1 / F2 / F3 快捷键
# 2. 主界面按钮打开窗口
# 3. 窗口 close_requested 关闭窗口
# 4. 窗口置顶
# 5. 提交处方后关闭诊疗窗口
#
# 不负责：
# 1. 当前 NPC
# 2. 处方判定
# 3. 脉象键盘显示逻辑
# =========================================================

signal pulse_window_opened
signal pulse_window_closed

const SHORTCUT_OPEN_PULSE := KEY_F1
const SHORTCUT_OPEN_PRESCRIPTION := KEY_F2
const SHORTCUT_OPEN_CLINICAL_LOG := KEY_F3

@onready var clinic_root: Node = get_parent()

@onready var pulse_window: Window = clinic_root.find_child("PulseWindow", true, false) as Window
@onready var prescription_window: Window = clinic_root.find_child("PrescriptionWindow", true, false) as Window
@onready var clinical_log_window: Window = clinic_root.find_child("ClinicalLogWindow", true, false) as Window
@onready var info_window: Window = clinic_root.find_child("InfoWindow", true, false) as Window

@onready var open_pulse_window_button: BaseButton = clinic_root.find_child("OpenPulseWindowButton", true, false) as BaseButton
@onready var open_prescription_window_button: BaseButton = clinic_root.find_child("OpenPrescriptionWindowButton", true, false) as BaseButton
@onready var clinical_log_button: BaseButton = clinic_root.find_child("Openclinical_logWindowButton", true, false) as BaseButton

var herb_database = null
var current_prescription = null
var formula_database = null


func _ready() -> void:
	_setup_windows()
	_setup_button_shortcuts()
	_connect_signals()


func configure_prescription_context(
		herb_db,
		prescription,
		formula_db
) -> void:
	herb_database = herb_db
	current_prescription = prescription
	formula_database = formula_db


# =========================================================
# 初始化
# =========================================================

func _setup_windows() -> void:
	if prescription_window != null:
		prescription_window.hide()

	if clinical_log_window != null:
		clinical_log_window.hide()


func _setup_button_shortcuts() -> void:
	_setup_button_shortcut(open_pulse_window_button, SHORTCUT_OPEN_PULSE)
	_setup_button_shortcut(open_prescription_window_button, SHORTCUT_OPEN_PRESCRIPTION)
	_setup_button_shortcut(clinical_log_button, SHORTCUT_OPEN_CLINICAL_LOG)


func _setup_button_shortcut(button: BaseButton, keycode: Key) -> void:
	if button == null:
		return

	var shortcut := Shortcut.new()
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	shortcut.events = [key_event]

	button.shortcut = shortcut
	button.shortcut_in_tooltip = true


func _connect_signals() -> void:
	_safe_connect_pressed(open_pulse_window_button, Callable(self, "open_pulse_window"))
	_safe_connect_pressed(open_prescription_window_button, Callable(self, "open_prescription_window"))
	_safe_connect_pressed(clinical_log_button, Callable(self, "open_clinical_log_window"))

	if pulse_window != null and pulse_window.has_signal("close_requested"):
		if not pulse_window.close_requested.is_connected(Callable(self, "close_pulse_window")):
			pulse_window.close_requested.connect(Callable(self, "close_pulse_window"))

	if prescription_window != null and prescription_window.has_signal("close_requested"):
		if not prescription_window.close_requested.is_connected(Callable(self, "close_prescription_window")):
			prescription_window.close_requested.connect(Callable(self, "close_prescription_window"))

	if clinical_log_window != null and clinical_log_window.has_signal("close_requested"):
		if not clinical_log_window.close_requested.is_connected(Callable(self, "close_clinical_log_window")):
			clinical_log_window.close_requested.connect(Callable(self, "close_clinical_log_window"))

	if info_window != null and info_window.has_signal("close_requested"):
		if not info_window.close_requested.is_connected(Callable(self, "close_info_window")):
			info_window.close_requested.connect(Callable(self, "close_info_window"))


func _safe_connect_pressed(button: BaseButton, callable_fn: Callable) -> void:
	if button != null and not button.pressed.is_connected(callable_fn):
		button.pressed.connect(callable_fn)


# =========================================================
# F1 / F2 / F3 快捷键
# =========================================================

func _unhandled_input(event: InputEvent) -> void:
	if not _is_valid_shortcut_key_event(event):
		return

	match event.keycode:
		SHORTCUT_OPEN_PULSE:
			open_pulse_window()
			get_viewport().set_input_as_handled()

		SHORTCUT_OPEN_PRESCRIPTION:
			open_prescription_window()
			get_viewport().set_input_as_handled()

		SHORTCUT_OPEN_CLINICAL_LOG:
			open_clinical_log_window()
			get_viewport().set_input_as_handled()


func _is_valid_shortcut_key_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey

	if not key_event.pressed:
		return false
	if key_event.echo:
		return false
	if key_event.alt_pressed or key_event.ctrl_pressed or key_event.meta_pressed or key_event.shift_pressed:
		return false

	return (
		key_event.keycode == SHORTCUT_OPEN_PULSE
		or key_event.keycode == SHORTCUT_OPEN_PRESCRIPTION
		or key_event.keycode == SHORTCUT_OPEN_CLINICAL_LOG
	)


# =========================================================
# 通用窗口置顶
# =========================================================

func _show_window_front(window_node: Window) -> void:
	if window_node == null:
		return

	window_node.show()

	var parent_node := window_node.get_parent()
	if parent_node != null:
		parent_node.move_child(window_node, parent_node.get_child_count() - 1)

	window_node.grab_focus()


# =========================================================
# 脉象窗口
# =========================================================

func open_pulse_window() -> void:
	if pulse_window == null:
		return

	if pulse_window.has_method("open_window"):
		pulse_window.call("open_window")
	else:
		pulse_window.show()

	_show_window_front(pulse_window)

	if pulse_window.has_method("show_hint_tab"):
		pulse_window.call("show_hint_tab")

	pulse_window_opened.emit()


func close_pulse_window() -> void:
	if pulse_window == null:
		return

	if pulse_window.has_method("close_window"):
		pulse_window.call("close_window")
	else:
		pulse_window.hide()

	pulse_window_closed.emit()


# =========================================================
# 开方窗口
# =========================================================

func open_prescription_window() -> void:
	if prescription_window == null:
		return

	if prescription_window.has_method("setup"):
		prescription_window.call("setup", herb_database, current_prescription, formula_database)

	_show_window_front(prescription_window)


func close_prescription_window() -> void:
	if prescription_window == null:
		return

	prescription_window.hide()


# =========================================================
# 行医记考窗口
# =========================================================

func open_clinical_log_window() -> void:
	if clinical_log_window == null:
		push_warning("ClinicalLogWindow 没找到，请检查节点名字和挂载位置")
		return

	_show_window_front(clinical_log_window)

	if clinical_log_window.has_method("open_window"):
		clinical_log_window.call("open_window")
		_show_window_front(clinical_log_window)
	elif clinical_log_window.has_method("refresh_view"):
		clinical_log_window.call("refresh_view")


func close_clinical_log_window() -> void:
	if clinical_log_window == null:
		return

	if clinical_log_window.has_method("close_window"):
		clinical_log_window.call("close_window")
	else:
		clinical_log_window.hide()


# =========================================================
# 信息测试窗口
# =========================================================

func open_info_window() -> void:
	if info_window == null:
		return

	info_window.popup_centered()
	info_window.grab_focus()


func close_info_window() -> void:
	if info_window == null:
		return

	info_window.hide()


# =========================================================
# 提交处方后统一关闭诊疗窗口
# =========================================================

func close_treatment_windows_after_submit() -> void:
	close_pulse_window()
	close_prescription_window()
	close_clinical_log_window()
