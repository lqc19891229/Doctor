extends Window
class_name InfoWindow

# =========================================================
# InfoWindow.gd
# 信息窗口脚本
#
# 作用：
# 1. 承载病人切换相关按钮
# 2. 不直接操作 NpcManager
# 3. 通过信号把“按钮请求”发送给 Clinic
# =========================================================


# =========================================================
# 对外信号
# =========================================================

# 请求切换到上一个病人
signal prev_npc_requested

# 请求切换到下一个病人
signal next_npc_requested

# 请求生成一个随机病人
signal spawn_npc_requested

# 请求结束当天
signal end_today_requested

# 请求一键解锁所有医书条目（仅测试用）
signal unlock_all_entries_requested


# =========================================================
# 节点引用
# =========================================================

@onready var info_label: Label = $Panel/VBoxContainer/InfoLabel
@onready var prev_button: Button = $Panel/VBoxContainer/ButtonRow/PrevButton
@onready var next_button: Button = $Panel/VBoxContainer/ButtonRow/NextButton
@onready var spawn_npc_button: Button = $Panel/VBoxContainer/ButtonRow/SpawnNpcButton
@onready var end_today_button: Button = $Panel/VBoxContainer/ButtonRow/EndTodayButton
@onready var unlock_all_entries_button: Button = $Panel/VBoxContainer/ButtonRow/UnlockAllEntriesButton


# =========================================================
# 生命周期
# =========================================================

func _ready() -> void:
	_connect_signals()


# =========================================================
# 初始化信号
# =========================================================

func _connect_signals() -> void:
	# 连接“上一个”按钮
	if prev_button != null and not prev_button.pressed.is_connected(_on_prev_button_pressed):
		prev_button.pressed.connect(_on_prev_button_pressed)

	# 连接“下一个”按钮
	if next_button != null and not next_button.pressed.is_connected(_on_next_button_pressed):
		next_button.pressed.connect(_on_next_button_pressed)

	# 连接“生成NPC”按钮
	if spawn_npc_button != null and not spawn_npc_button.pressed.is_connected(_on_spawn_npc_button_pressed):
		spawn_npc_button.pressed.connect(_on_spawn_npc_button_pressed)

	# 连接“结束当天”按钮
	if end_today_button != null and not end_today_button.pressed.is_connected(_on_end_today_button_pressed):
		end_today_button.pressed.connect(_on_end_today_button_pressed)

	# 连接“一键解锁所有条目”按钮
	if unlock_all_entries_button != null and not unlock_all_entries_button.pressed.is_connected(_on_unlock_all_entries_button_pressed):
		unlock_all_entries_button.pressed.connect(_on_unlock_all_entries_button_pressed)


# =========================================================
# 对外方法：设置显示文字
# Clinic 调用这个方法更新 InfoLabel
# =========================================================

func set_info_text(text: String) -> void:
	if info_label == null:
		return

	info_label.text = text


# =========================================================
# 按钮回调
# 这里只发信号，不直接写业务逻辑
# =========================================================

func _on_prev_button_pressed() -> void:
	prev_npc_requested.emit()


func _on_next_button_pressed() -> void:
	next_npc_requested.emit()


func _on_spawn_npc_button_pressed() -> void:
	spawn_npc_requested.emit()


func _on_end_today_button_pressed() -> void:
	end_today_requested.emit()


# =========================================================
# 测试按钮：一键解锁所有医书条目
# =========================================================

func _on_unlock_all_entries_button_pressed() -> void:
	unlock_all_entries_requested.emit()
