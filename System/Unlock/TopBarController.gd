extends Node
class_name TopBarController

# =========================================================
# TopBarController
# 通用顶部栏显示控制器
#
# 负责：
# 1. 日期显示
# 2. 当前时辰 / 固定时间文本显示
# 3. 名望显示
# 4. 根据名望显示对应称号
# 5. 银钱显示（两 + 文）
#
# 使用方式：
# var topbar := TopBarController.new()
# add_child(topbar)
# topbar.setup(day_label, time_label, reputation_point_label)
# topbar.refresh_all(true)
#
# 如夜晚场景需要固定显示“夜晚”：
# topbar.set_time_text_override("夜晚")
# =========================================================

const DEFAULT_LABEL_SIZE := Vector2(120, 24)

var day_label: Label = null
var time_label: Label = null
var reputation_point_label: Label = null
var money_point_label: Label = null

# Clinic 场景可选的图标式银钱显示。
# 保留 MoneyPoint Label 作为兼容入口，因此无需修改 Clinic.gd。
var money_container: HBoxContainer = null
var money_debt_label: Label = null
var money_liang_label: Label = null
var money_wen_label: Label = null

var fallback_day: int = 1
var time_text_override: String = ""

var last_displayed_reputation_point: int = -999999
var last_displayed_money_wen: int = -999999999


func setup(
	_day_label: Label,
	_time_label: Label,
	_reputation_point_label: Label,
	_time_text_override: String = "",
	_money_point_label: Label = null
) -> void:
	day_label = _day_label
	time_label = _time_label
	reputation_point_label = _reputation_point_label
	money_point_label = _money_point_label
	time_text_override = _time_text_override

	_setup_money_display()
	_bind_game_time_signal()
	_bind_unlock_signals()
	refresh_all(true)


func set_fallback_day(day: int) -> void:
	fallback_day = max(day, 1)
	refresh_time()


func set_time_text_override(value: String) -> void:
	time_text_override = value
	refresh_time()


func clear_time_text_override() -> void:
	time_text_override = ""
	refresh_time()


func refresh_all(force_refresh: bool = false) -> void:
	refresh_time()
	refresh_points(force_refresh)


func refresh_points(force_refresh: bool = false) -> void:
	refresh_reputation_point(force_refresh)
	refresh_money_point(force_refresh)


func refresh_time() -> void:
	if day_label != null:
		if GameTime != null and GameTime.has_method("get_day_text"):
			day_label.text = GameTime.get_day_text()
		else:
			day_label.text = "第 %d 天" % fallback_day

	if time_label != null:
		if not time_text_override.is_empty():
			time_label.text = time_text_override
		elif GameTime != null and GameTime.has_method("get_shichen_text"):
			time_label.text = GameTime.get_shichen_text()
		else:
			time_label.text = "辰时"



func refresh_reputation_point(force_refresh: bool = false) -> void:
	if reputation_point_label == null:
		return

	var current_points := 0
	if Unlock != null and Unlock.has_method("get_reputation_points"):
		current_points = Unlock.get_reputation_points()

	if not force_refresh and current_points == last_displayed_reputation_point:
		return

	last_displayed_reputation_point = current_points
	_prepare_point_label(reputation_point_label)
	reputation_point_label.text = get_reputation_display_text(current_points)


func refresh_money_point(force_refresh: bool = false) -> void:
	if money_point_label == null and money_container == null:
		return

	var current_money_wen := 0
	if Unlock != null and Unlock.has_method("get_money_wen"):
		current_money_wen = Unlock.get_money_wen()

	if not force_refresh and current_money_wen == last_displayed_money_wen:
		return

	last_displayed_money_wen = current_money_wen

	var absolute_amount: int = absi(current_money_wen)
	var liang: int = absolute_amount / 1000
	var wen: int = absolute_amount % 1000

	# 优先使用 Clinic 场景中的银元宝 / 铜钱图标布局。
	if money_container != null and money_liang_label != null and money_wen_label != null:
		money_container.visible = true
		if money_point_label != null:
			money_point_label.visible = false

		if money_debt_label != null:
			money_debt_label.visible = current_money_wen < 0
			money_debt_label.text = "欠"

		money_liang_label.text = "%d两" % liang
		money_wen_label.text = "%d文" % wen
		return

	# 其他尚未改造的场景继续使用原来的纯文字显示。
	if money_point_label == null:
		return

	_prepare_point_label(money_point_label)
	if Unlock != null and Unlock.has_method("format_money"):
		money_point_label.text = "银钱：%s" % Unlock.format_money(current_money_wen)
	elif current_money_wen < 0:
		money_point_label.text = "银钱：欠 %d两 %d文" % [liang, wen]
	else:
		money_point_label.text = "银钱：%d两 %d文" % [liang, wen]

func _setup_money_display() -> void:
	money_container = null
	money_debt_label = null
	money_liang_label = null
	money_wen_label = null

	if money_point_label == null:
		return

	var parent_node := money_point_label.get_parent()
	if parent_node == null:
		return

	money_container = parent_node.get_node_or_null("MoneyContainer") as HBoxContainer
	if money_container == null:
		return

	money_debt_label = money_container.get_node_or_null("DebtLabel") as Label
	money_liang_label = money_container.get_node_or_null("LiangLabel") as Label
	money_wen_label = money_container.get_node_or_null("WenLabel") as Label

	# 只要场景提供了完整的 MoneyContainer，就隐藏旧文字 Label。
	if money_liang_label != null and money_wen_label != null:
		money_point_label.visible = false
		money_container.visible = true
	else:
		money_container = null


func get_reputation_title(reputation: int) -> String:
	if reputation <= 100:
		return "初窥门径"
	elif reputation <= 300:
		return "略有小成"
	elif reputation <= 600:
		return "融会贯通"
	elif reputation <= 2000:
		return "炉火纯青"
	else:
		return "出神入化"


func get_reputation_display_text(reputation: int) -> String:
	var title := get_reputation_title(reputation)
	var target := get_reputation_target(reputation)

	# 最高等级已经没有下一阶段目标。
	if target <= 0:
		return "名望：%d　%s" % [reputation, title]

	return "名望：%d/%d　%s" % [reputation, target, title]


func get_reputation_target(reputation: int) -> int:
	if reputation <= 100:
		return 100
	elif reputation <= 300:
		return 300
	elif reputation <= 600:
		return 600
	elif reputation <= 2000:
		return 2000
	else:
		return -1


func _prepare_point_label(label: Label) -> void:
	if label == null:
		return

	label.visible = true
	label.custom_minimum_size = DEFAULT_LABEL_SIZE
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _bind_unlock_signals() -> void:
	if Unlock == null:
		return


	if Unlock.has_signal("reputation_points_changed"):
		var reputation_callback := Callable(self, "_on_reputation_points_changed")
		if not Unlock.is_connected("reputation_points_changed", reputation_callback):
			Unlock.connect("reputation_points_changed", reputation_callback)

	if Unlock.has_signal("money_wen_changed"):
		var money_callback := Callable(self, "_on_money_wen_changed")
		if not Unlock.is_connected("money_wen_changed", money_callback):
			Unlock.connect("money_wen_changed", money_callback)




func _on_reputation_points_changed(_value: int) -> void:
	refresh_reputation_point(false)


func _on_money_wen_changed(_value: int) -> void:
	refresh_money_point(false)


func _bind_game_time_signal() -> void:
	if GameTime == null:
		return

	if not GameTime.has_signal("time_changed"):
		return

	var callback := Callable(self, "refresh_time")
	if not GameTime.time_changed.is_connected(callback):
		GameTime.time_changed.connect(callback)
