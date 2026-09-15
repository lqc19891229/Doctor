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
# 4. 提供仅用于开发测试的日期、剧情、名望、心得、银钱和夜读快捷功能
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

# 测试数据发生变化。宿主场景可按需监听并刷新自己的 UI。
signal test_data_changed


# =========================================================
# 节点引用
# =========================================================

@onready var info_label: Label = $Panel/VBoxContainer/InfoLabel
@onready var prev_button: Button = $Panel/VBoxContainer/ButtonRow/PrevButton
@onready var next_button: Button = $Panel/VBoxContainer/ButtonRow/NextButton
@onready var spawn_npc_button: Button = $Panel/VBoxContainer/ButtonRow/SpawnNpcButton
@onready var end_today_button: Button = $Panel/VBoxContainer/ButtonRow/EndTodayButton
@onready var unlock_all_entries_button: Button = $Panel/VBoxContainer/ButtonRow/UnlockAllEntriesButton

# 场景中固定存在的扩展测试控件，可直接在 InfoWindow.tscn 中调整。
@onready var extended_test_panel: VBoxContainer = $Panel/VBoxContainer/ExtendedTestPanel
@onready var day_spin_box: SpinBox = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/DaySpinBox
@onready var set_day_button: Button = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/SetDayButton
@onready var story_check_list: VBoxContainer = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/StoryScrollContainer/StoryCheckList
@onready var mark_selected_stories_played_button: Button = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/StoryActionColumn/MarkSelectedStoriesPlayedButton
@onready var select_all_unplayed_stories_button: Button = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/StoryActionColumn/SelectAllUnplayedStoriesButton
@onready var clear_story_selection_button: Button = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/StoryActionColumn/ClearStorySelectionButton
@onready var reputation_spin_box: SpinBox = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/ReputationSpinBox
@onready var set_reputation_button: Button = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/SetReputationButton
@onready var experience_spin_box: SpinBox = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/ExperienceSpinBox
@onready var set_experience_button: Button = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/SetExperienceButton
@onready var money_spin_box: SpinBox = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/MoneySpinBox
@onready var set_money_button: Button = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/SetMoneyButton
@onready var read_all_unlocked_button: Button = $Panel/VBoxContainer/ExtendedTestPanel/ExtendedTestGrid/ReadAllUnlockedButton
@onready var test_status_label: Label = $Panel/VBoxContainer/ExtendedTestPanel/TestStatusLabel


# =========================================================
# 生命周期
# =========================================================

func _ready() -> void:
	_connect_signals()
	_refresh_test_controls()


# Esc 关闭信息窗口。
# 使用 ui_cancel 兼容 Godot 默认 Esc 映射；只有窗口可见时才处理。
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		close_window()
		get_viewport().set_input_as_handled()


# =========================================================
# 初始化信号
# =========================================================

func _connect_signals() -> void:
	# Window 右上角 X 只会发出 close_requested，必须主动隐藏窗口。
	if not close_requested.is_connected(_on_window_close_requested):
		close_requested.connect(_on_window_close_requested)

	# Clinic 目前直接调用 popup_centered()，每次弹出前刷新测试数据。
	if not about_to_popup.is_connected(_on_window_about_to_popup):
		about_to_popup.connect(_on_window_about_to_popup)

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

	# 连接场景中固定存在的扩展测试按钮。
	if set_day_button != null and not set_day_button.pressed.is_connected(_on_set_day_button_pressed):
		set_day_button.pressed.connect(_on_set_day_button_pressed)

	if mark_selected_stories_played_button != null and not mark_selected_stories_played_button.pressed.is_connected(_on_mark_selected_stories_played_button_pressed):
		mark_selected_stories_played_button.pressed.connect(_on_mark_selected_stories_played_button_pressed)

	if select_all_unplayed_stories_button != null and not select_all_unplayed_stories_button.pressed.is_connected(_on_select_all_unplayed_stories_button_pressed):
		select_all_unplayed_stories_button.pressed.connect(_on_select_all_unplayed_stories_button_pressed)

	if clear_story_selection_button != null and not clear_story_selection_button.pressed.is_connected(_on_clear_story_selection_button_pressed):
		clear_story_selection_button.pressed.connect(_on_clear_story_selection_button_pressed)

	if set_reputation_button != null and not set_reputation_button.pressed.is_connected(_on_set_reputation_button_pressed):
		set_reputation_button.pressed.connect(_on_set_reputation_button_pressed)

	if set_experience_button != null and not set_experience_button.pressed.is_connected(_on_set_experience_button_pressed):
		set_experience_button.pressed.connect(_on_set_experience_button_pressed)

	if set_money_button != null and not set_money_button.pressed.is_connected(_on_set_money_button_pressed):
		set_money_button.pressed.connect(_on_set_money_button_pressed)

	if read_all_unlocked_button != null and not read_all_unlocked_button.pressed.is_connected(_on_read_all_unlocked_button_pressed):
		read_all_unlocked_button.pressed.connect(_on_read_all_unlocked_button_pressed)


# =========================================================
# 扩展测试界面刷新
# =========================================================

func _refresh_test_controls() -> void:
	if extended_test_panel == null:
		return

	if day_spin_box != null and GameTime != null and _object_has_property(GameTime, &"current_day"):
		day_spin_box.value = maxi(int(GameTime.get(&"current_day")), 1)

	if reputation_spin_box != null:
		reputation_spin_box.value = _get_current_reputation()

	if experience_spin_box != null:
		experience_spin_box.value = _get_current_experience()

	if money_spin_box != null:
		money_spin_box.value = _get_current_money_wen()

	_reload_story_checklist()
	_refresh_test_status()


func _reload_story_checklist() -> void:
	if story_check_list == null:
		return

	var previously_selected_ids := _get_selected_story_ids_for_test()

	# 立即从容器移除旧节点，避免 queue_free() 延迟导致刷新时暂时出现重复项。
	for child in story_check_list.get_children():
		story_check_list.remove_child(child)
		child.queue_free()

	if StoryManager == null or not StoryManager.has_method("get_all_stories"):
		_add_story_checklist_message("StoryManager 接口不可用")
		_set_story_selection_buttons_enabled(false)
		return

	var all_stories = StoryManager.call("get_all_stories")
	if typeof(all_stories) != TYPE_ARRAY:
		_add_story_checklist_message("未读取到剧情数据")
		_set_story_selection_buttons_enabled(false)
		return

	var story_count := 0
	var unplayed_count := 0
	for story in all_stories:
		if story == null:
			continue

		var story_id := str(_get_object_property(story, &"story_id", "")).strip_edges()
		if story_id == "":
			continue

		var has_played := _is_story_played_for_test(story_id)
		var trigger_scene := str(
			_get_object_property(story, &"trigger_scene", "")
		).strip_edges()

		var story_check_box := CheckBox.new()
		story_check_box.name = "Story_%d" % story_count
		story_check_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		story_check_box.set_meta(&"story_id", story_id)

		var state_text := "已播放" if has_played else "未播放"
		story_check_box.text = "%s｜%s" % [state_text, story_id]
		if trigger_scene != "":
			story_check_box.text += "（%s）" % trigger_scene

		# 已播放剧情仍显示，便于确认当前状态，但不允许再次选择。
		story_check_box.disabled = has_played
		if not has_played:
			unplayed_count += 1
			story_check_box.button_pressed = previously_selected_ids.has(story_id)

		story_check_list.add_child(story_check_box)
		story_count += 1

	if story_count <= 0:
		_add_story_checklist_message("没有可用剧情")
		_set_story_selection_buttons_enabled(false)
		return

	_set_story_selection_buttons_enabled(unplayed_count > 0)


func _add_story_checklist_message(message: String) -> void:
	if story_check_list == null:
		return

	var message_label := Label.new()
	message_label.text = message
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_check_list.add_child(message_label)


func _set_story_selection_buttons_enabled(enabled: bool) -> void:
	if mark_selected_stories_played_button != null:
		mark_selected_stories_played_button.disabled = not enabled
	if select_all_unplayed_stories_button != null:
		select_all_unplayed_stories_button.disabled = not enabled
	if clear_story_selection_button != null:
		clear_story_selection_button.disabled = not enabled


func _get_selected_story_ids_for_test() -> Array[String]:
	var selected_story_ids: Array[String] = []
	if story_check_list == null:
		return selected_story_ids

	for child in story_check_list.get_children():
		if not (child is CheckBox):
			continue

		var story_check_box := child as CheckBox
		if story_check_box.disabled or not story_check_box.button_pressed:
			continue

		var story_id := str(story_check_box.get_meta(&"story_id", "")).strip_edges()
		if story_id != "":
			selected_story_ids.append(story_id)

	return selected_story_ids

func _refresh_test_status() -> void:
	if test_status_label == null:
		return

	var day := 0
	if GameTime != null and _object_has_property(GameTime, &"current_day"):
		day = int(GameTime.get(&"current_day"))

	var unread_count := -1
	if Unlock != null and Unlock.has_method("get_unread_readable_entry_count"):
		unread_count = int(Unlock.call("get_unread_readable_entry_count"))

	if unread_count >= 0:
		test_status_label.text = "当前：第 %d 日｜名望 %d｜心得 %d｜银钱 %s｜可读未读条目 %d" % [
			day,
			_get_current_reputation(),
			_get_current_experience(),
			_format_money(_get_current_money_wen()),
			unread_count
		]
	else:
		test_status_label.text = "当前：第 %d 日｜名望 %d｜心得 %d｜银钱 %s" % [
			day,
			_get_current_reputation(),
			_get_current_experience(),
			_format_money(_get_current_money_wen())
		]


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


# =========================================================
# 扩展测试功能：修改日期
# =========================================================

func _on_set_day_button_pressed() -> void:
	if day_spin_box == null:
		_show_test_result("修改日期失败：日期输入框不存在。")
		return

	if GameTime == null or not _object_has_property(GameTime, &"current_day"):
		_show_test_result("修改日期失败：GameTime.current_day 不可用。")
		return

	var target_day := maxi(int(day_spin_box.value), 1)
	GameTime.set(&"current_day", target_day)

	if GameTime.has_signal("time_changed"):
		GameTime.emit_signal("time_changed")

	_notify_host_data_changed()
	_refresh_test_controls()

	var day_text := ""
	if GameTime.has_method("get_day_text"):
		day_text = str(GameTime.call("get_day_text"))

	if day_text == "":
		_show_test_result("测试日期已修改为第 %d 日。" % target_day)
	else:
		_show_test_result("测试日期已修改为第 %d 日：%s。" % [target_day, day_text])


# =========================================================
# 扩展测试功能：批量标记用户明确勾选的剧情
# =========================================================

func _on_mark_selected_stories_played_button_pressed() -> void:
	if StoryManager == null:
		_show_test_result("标记剧情失败：StoryManager 不可用。")
		return

	var selected_story_ids := _get_selected_story_ids_for_test()
	if selected_story_ids.is_empty():
		_show_test_result("标记剧情失败：请先勾选需要解锁的剧情。")
		return

	var marked_count := 0
	var failed_story_ids: Array[String] = []

	for story_id in selected_story_ids:
		if _is_story_played_for_test(story_id):
			continue

		if _mark_story_played_for_test(story_id):
			marked_count += 1
		else:
			failed_story_ids.append(story_id)

	_notify_host_data_changed()
	_reload_story_checklist()
	_refresh_test_status()

	if not failed_story_ids.is_empty():
		_show_test_result(
			"已标记 %d 条剧情；以下剧情标记失败：%s。" % [
				marked_count,
				", ".join(PackedStringArray(failed_story_ids))
			]
		)
	elif marked_count <= 0:
		_show_test_result("选中的剧情已经全部处于已播放状态。")
	else:
		_show_test_result("已按选择标记 %d 条剧情为播放完成。" % marked_count)


func _on_select_all_unplayed_stories_button_pressed() -> void:
	if story_check_list == null:
		return

	var selected_count := 0
	for child in story_check_list.get_children():
		if not (child is CheckBox):
			continue

		var story_check_box := child as CheckBox
		if story_check_box.disabled:
			continue

		story_check_box.button_pressed = true
		selected_count += 1

	_show_test_result("已选择全部 %d 条未播放剧情；点击“标记选中”后才会真正修改状态。" % selected_count)


func _on_clear_story_selection_button_pressed() -> void:
	if story_check_list == null:
		return

	for child in story_check_list.get_children():
		if child is CheckBox:
			(child as CheckBox).button_pressed = false

	_show_test_result("已清空剧情选择，剧情播放状态未改变。")


func _is_story_played_for_test(story_id: String) -> bool:
	var clean_story_id := story_id.strip_edges()
	if clean_story_id == "" or StoryManager == null:
		return false

	if StoryManager.has_method("has_played_story"):
		return bool(StoryManager.call("has_played_story", clean_story_id))

	if _object_has_property(StoryManager, &"played_story_ids"):
		var played_value = StoryManager.get(&"played_story_ids")
		if typeof(played_value) == TYPE_DICTIONARY:
			var played_ids: Dictionary = played_value
			return played_ids.has(clean_story_id)

	return false


func _mark_story_played_for_test(story_id: String) -> bool:
	var clean_story_id := story_id.strip_edges()
	if clean_story_id == "" or StoryManager == null:
		return false

	if StoryManager.has_method("mark_story_played_by_id"):
		StoryManager.call("mark_story_played_by_id", clean_story_id)
		return true

	if _object_has_property(StoryManager, &"played_story_ids"):
		var played_value = StoryManager.get(&"played_story_ids")
		if typeof(played_value) == TYPE_DICTIONARY:
			var played_ids: Dictionary = played_value
			played_ids[clean_story_id] = true
			StoryManager.set(&"played_story_ids", played_ids)
			return true

	return false


# =========================================================
# 扩展测试功能：修改名望核心数值
# =========================================================

func _on_set_reputation_button_pressed() -> void:
	if reputation_spin_box == null:
		_show_test_result("修改名望失败：名望输入框不存在。")
		return

	if Unlock == null:
		_show_test_result("修改名望失败：Unlock 不可用。")
		return

	var target_reputation := maxi(int(reputation_spin_box.value), 0)
	var current_reputation := _get_current_reputation()
	var changed := false

	if Unlock.has_method("add_reputation_points"):
		Unlock.call("add_reputation_points", target_reputation - current_reputation)
		changed = true
	elif _object_has_property(Unlock, &"reputation_points"):
		Unlock.set(&"reputation_points", target_reputation)
		if Unlock.has_method("refresh_story_unlocks_by_reputation"):
			Unlock.call("refresh_story_unlocks_by_reputation")
		changed = true

	if not changed:
		_show_test_result("修改名望失败：Unlock 缺少名望修改接口。")
		return

	_notify_host_data_changed()
	_refresh_test_controls()
	_show_test_result("名望核心数值已修改为 %d。" % _get_current_reputation())


# =========================================================
# 扩展测试功能：修改心得核心数值
# =========================================================

func _on_set_experience_button_pressed() -> void:
	if experience_spin_box == null:
		_show_test_result("修改心得失败：心得输入框不存在。")
		return

	if Unlock == null:
		_show_test_result("修改心得失败：Unlock 不可用。")
		return

	var target_experience := maxi(int(experience_spin_box.value), 0)
	var current_experience := _get_current_experience()
	var delta := target_experience - current_experience
	var changed := false

	# 增加心得时优先走现有接口，让依赖心得的医书条目同步解锁。
	if delta > 0 and Unlock.has_method("add_experience_point"):
		Unlock.call("add_experience_point", delta)
		changed = true
	elif delta == 0:
		changed = true
	elif _object_has_property(Unlock, &"experience_points"):
		# 现有 add_experience_point() 不接受负数；降低心得时直接设置目标值。
		Unlock.set(&"experience_points", target_experience)
		changed = true

	if not changed:
		_show_test_result("修改心得失败：Unlock 缺少心得修改接口。")
		return

	if Unlock.has_method("refresh_auto_unlocks_by_experience"):
		Unlock.call("refresh_auto_unlocks_by_experience")
	if Unlock.has_method("refresh_unlocks_by_dependencies"):
		Unlock.call("refresh_unlocks_by_dependencies")

	_notify_host_data_changed()
	_refresh_test_controls()
	_show_test_result("心得核心数值已修改为 %d。" % _get_current_experience())


# =========================================================
# 扩展测试功能：修改银钱
# 单位统一使用“文”；允许负数，负数表示欠款。
# =========================================================

func _on_set_money_button_pressed() -> void:
	if money_spin_box == null:
		_show_test_result("修改银钱失败：银钱输入框不存在。")
		return

	if Unlock == null:
		_show_test_result("修改银钱失败：Unlock 不可用。")
		return

	var target_money_wen := int(money_spin_box.value)
	var current_money_wen := _get_current_money_wen()
	var changed := false

	# 优先走正式接口，确保 money_wen_changed 正常发出，
	# Clinic / Night 顶部栏会沿用现有监听逻辑立即刷新。
	if Unlock.has_method("change_money_wen"):
		Unlock.call("change_money_wen", target_money_wen - current_money_wen)
		changed = true
	elif _object_has_property(Unlock, &"money_wen"):
		# 兼容没有 change_money_wen() 的旧版本。
		Unlock.set(&"money_wen", target_money_wen)
		if Unlock.has_signal("money_wen_changed"):
			Unlock.emit_signal("money_wen_changed", target_money_wen)
		changed = true

	if not changed:
		_show_test_result("修改银钱失败：Unlock 缺少银钱修改接口。")
		return

	_notify_host_data_changed()
	_refresh_test_controls()
	_show_test_result(
		"银钱已修改为 %s（%d 文）。" % [
			_format_money(_get_current_money_wen()),
			_get_current_money_wen()
		]
	)


# =========================================================
# 扩展测试功能：一键阅读全部已解锁条目
# =========================================================

func _on_read_all_unlocked_button_pressed() -> void:
	if Unlock == null:
		_show_test_result("一键阅读失败：Unlock 不可用。")
		return

	if BookEntryDB == null or not BookEntryDB.has_method("get_all_entries"):
		_show_test_result("一键阅读失败：BookEntryDB.get_all_entries() 不可用。")
		return

	if not Unlock.has_method("read_entry") and not Unlock.has_method("mark_entry_as_read"):
		_show_test_result("一键阅读失败：Unlock 缺少阅读接口。")
		return

	if Unlock.has_method("refresh_auto_unlocks_by_experience"):
		Unlock.call("refresh_auto_unlocks_by_experience")
	if Unlock.has_method("refresh_unlocks_by_dependencies"):
		Unlock.call("refresh_unlocks_by_dependencies")

	var all_entries = BookEntryDB.call("get_all_entries")
	if typeof(all_entries) != TYPE_ARRAY:
		_show_test_result("一键阅读失败：没有读取到医书条目列表。")
		return

	var read_count := 0
	var pass_limit := maxi(all_entries.size(), 1) + 1

	# 阅读药材、方剂或疾病条目可能继续解锁其他条目，因此循环到状态稳定。
	for _pass_index in range(pass_limit):
		var current_pass_count := 0

		for entry in all_entries:
			if entry == null:
				continue

			var entry_id := str(
				_get_object_property(entry, &"entry_id", "")
			).strip_edges()
			if entry_id == "":
				continue

			if not _is_entry_unlocked(entry_id):
				continue
			if _is_entry_read(entry_id):
				continue

			if Unlock.has_method("can_read_entry"):
				if not bool(Unlock.call("can_read_entry", entry_id)):
					continue

			if Unlock.has_method("read_entry"):
				Unlock.call("read_entry", entry)
			else:
				Unlock.call("mark_entry_as_read", entry_id)

			if _is_entry_read(entry_id):
				current_pass_count += 1
				read_count += 1

		if Unlock.has_method("refresh_unlocks_by_dependencies"):
			Unlock.call("refresh_unlocks_by_dependencies")

		if current_pass_count == 0:
			break

	_notify_host_data_changed()
	_refresh_test_controls()

	if read_count <= 0:
		_show_test_result("没有可一键阅读的已解锁未读条目。")
	else:
		_show_test_result("已一键阅读 %d 个已解锁条目。" % read_count)


# =========================================================
# 公共窗口方法、存档与刷新
# =========================================================

func open_window() -> void:
	_refresh_test_controls()
	popup_centered()


func _on_window_close_requested() -> void:
	hide()


func _on_window_about_to_popup() -> void:
	_refresh_test_controls()


func close_window() -> void:
	hide()


# Debug 修改只作用于当前内存状态；下一次昼夜阶段结束时统一写盘。

func _notify_host_data_changed() -> void:
	test_data_changed.emit()

	var host := get_parent()
	if host == null:
		return

	# Night 和 Clinic 都已有这个刷新方法；调用后日期、名望等会立即更新。
	if host.has_method("_refresh_topbar"):
		host.call("_refresh_topbar", true)

	# 若宿主场景带有读书窗口，同时刷新其列表和数值显示。
	var read_book_window := host.find_child("ReadBook", true, false)
	if read_book_window == null:
		return

	if read_book_window.has_method("_update_day_label"):
		read_book_window.call("_update_day_label")
	if read_book_window.has_method("_update_thoughts_point_ui"):
		read_book_window.call("_update_thoughts_point_ui")
	if read_book_window.has_method("_refresh_book_list"):
		read_book_window.call("_refresh_book_list")


func _show_test_result(message: String) -> void:
	if test_status_label != null:
		test_status_label.text = message

	# Night 中 InfoLabel 是主要反馈区；Clinic 中也保留同样的即时反馈。
	set_info_text(message)


# =========================================================
# 数据兼容辅助函数
# =========================================================

func _get_current_reputation() -> int:
	if Unlock == null:
		return 0

	if Unlock.has_method("get_reputation_points"):
		return int(Unlock.call("get_reputation_points"))

	if _object_has_property(Unlock, &"reputation_points"):
		return int(Unlock.get(&"reputation_points"))

	return 0


func _get_current_experience() -> int:
	if Unlock == null:
		return 0

	if Unlock.has_method("get_experience_points"):
		return int(Unlock.call("get_experience_points"))

	if _object_has_property(Unlock, &"experience_points"):
		return int(Unlock.get(&"experience_points"))

	return 0


func _get_current_money_wen() -> int:
	if Unlock == null:
		return 0

	if Unlock.has_method("get_money_wen"):
		return int(Unlock.call("get_money_wen"))

	if _object_has_property(Unlock, &"money_wen"):
		return int(Unlock.get(&"money_wen"))

	return 0


func _format_money(amount_wen: int) -> String:
	if Unlock != null and Unlock.has_method("format_money"):
		return str(Unlock.call("format_money", amount_wen))

	var absolute_amount := absi(amount_wen)
	var liang := absolute_amount / 1000
	var wen := absolute_amount % 1000
	var text := "%d两 %d文" % [liang, wen]

	if amount_wen < 0:
		return "欠 " + text

	return text


func _is_entry_unlocked(entry_id: String) -> bool:
	if Unlock == null:
		return false

	if Unlock.has_method("is_entry_unlocked"):
		return bool(Unlock.call("is_entry_unlocked", entry_id))

	if _object_has_property(Unlock, &"unlocked_entry_ids"):
		var unlocked_value = Unlock.get(&"unlocked_entry_ids")
		if typeof(unlocked_value) == TYPE_DICTIONARY:
			var unlocked_ids: Dictionary = unlocked_value
			return unlocked_ids.has(entry_id)

	return false


func _is_entry_read(entry_id: String) -> bool:
	if Unlock == null:
		return false

	if Unlock.has_method("is_entry_read"):
		return bool(Unlock.call("is_entry_read", entry_id))

	if _object_has_property(Unlock, &"read_entry_ids"):
		var read_value = Unlock.get(&"read_entry_ids")
		if typeof(read_value) == TYPE_DICTIONARY:
			var read_ids: Dictionary = read_value
			return read_ids.has(entry_id)

	return false


func _object_has_property(target: Object, property_name: StringName) -> bool:
	if target == null:
		return false

	for property_info in target.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true

	return false


func _get_object_property(
	target: Object,
	property_name: StringName,
	fallback_value: Variant
) -> Variant:
	if not _object_has_property(target, property_name):
		return fallback_value

	var value = target.get(property_name)
	return fallback_value if value == null else value
