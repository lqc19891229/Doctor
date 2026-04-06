extends Control
class_name NightStudy

# =========================================================
# NightStudy.gd
# 夜晚读书场景
#
# 作用：
# 1. 点击“阅读”时调用 Unlock.read_disease_entry(...)
# 2. 把本次新增解锁结果显示到界面上
# 3. 点击“进入明天”时通知 Main 切回 Clinic
#
# 新版说明：
# - 夜晚阅读对象不再是 BookData
# - 而是 DiseaseBookEntryData（病证书条目）
# - 真正解锁病证的单位是“条目”
# =========================================================

# 通知 Main：夜晚阶段结束，进入下一天
signal study_finished

# UI 节点
@onready var info_label: Label = $VBoxContainer/InfoLabel
@onready var read_button: Button = $VBoxContainer/ButtonRow/ReadButton
@onready var next_day_button: Button = $VBoxContainer/ButtonRow/NextDayButton

# 当前病证条目数据
var current_entry: DiseaseBookEntryData = null

# 是否已经执行过本次阅读
var has_read_this_night: bool = false


func _ready() -> void:
	_safe_connect_pressed(read_button, _on_read_button_pressed)
	_safe_connect_pressed(next_day_button, _on_next_day_button_pressed)

	_load_entry()
	_refresh_info_text()


# 安全连接按钮，避免重复 connect 报错
func _safe_connect_pressed(button: BaseButton, callable_fn: Callable) -> void:
	if button != null and not button.pressed.is_connected(callable_fn):
		button.pressed.connect(callable_fn)


# 加载当前夜晚要阅读的病证条目
func _load_entry() -> void:
	current_entry = null

	var readable_entry_ids := Unlock.get_all_readable_disease_entry_ids()
	if readable_entry_ids.is_empty():
		return

	var first_entry_id := readable_entry_ids[0]
	current_entry = DiseaseBookDB.get_entry_by_id(first_entry_id)


# 刷新初始文本
func _refresh_info_text() -> void:
	if current_entry == null:
		info_label.text = "夜晚读书\n当前没有可阅读的病证条目"
		return

	var title := current_entry.get_display_name()
	var book_id := current_entry.book_id
	var summary := current_entry.summary_text.strip_edges()

	var lines: Array[String] = []
	lines.append("夜晚读书")
	lines.append("当前条目：%s" % title)
	lines.append("所属书籍：%s" % book_id)

	if summary != "":
		lines.append("摘要：%s" % summary)

	lines.append("点击“阅读”可尝试解锁病证内容")
	info_label.text = "\n".join(lines)


# 点击阅读
func _on_read_button_pressed() -> void:
	if current_entry == null:
		info_label.text = "当前没有可阅读的病证条目"
		return

	# 防止同一晚重复点阅读，导致提示混乱
	if has_read_this_night:
		info_label.text += "\n\n今晚已经阅读过这个条目了"
		return

	has_read_this_night = true

	# 阅读前先记录旧状态，方便比较哪些内容是新解锁的
	var old_formulas := Unlock.unlocked_formula_ids.keys()
	var old_diseases := Unlock.unlocked_disease_ids.keys()
	var old_read_entries := Unlock.read_book_entry_ids.keys()

	# 先判断当前条目是否可阅读
	if not Unlock.is_disease_entry_readable(current_entry.entry_id) and not Unlock.is_entry_read(current_entry.entry_id):
		var fail_lines: Array[String] = []
		fail_lines.append("阅读失败：当前条目暂不可读")

		var required_herbs := current_entry.get_required_herb_ids_unique()
		if not required_herbs.is_empty():
			fail_lines.append("需要药材：%s" % "、".join(required_herbs))

		var pre_entries := current_entry.get_prerequisite_entry_ids_unique()
		if not pre_entries.is_empty():
			fail_lines.append("需要先读前置条目：%s" % "、".join(pre_entries))

		fail_lines.append("")
		fail_lines.append("点击“进入明天”返回诊室")

		info_label.text = "\n".join(fail_lines)
		return

	# 调用新版解锁系统：阅读病证条目
	Unlock.read_disease_entry(current_entry)

	var new_formulas: Array[String] = []
	var new_diseases: Array[String] = []
	var new_read_entries: Array[String] = []

	# 对比方剂解锁变化
	for formula_id in Unlock.unlocked_formula_ids.keys():
		if not old_formulas.has(formula_id):
			new_formulas.append(formula_id)

	# 对比病证解锁变化
	for disease_id in Unlock.unlocked_disease_ids.keys():
		if not old_diseases.has(disease_id):
			new_diseases.append(disease_id)

	# 对比条目阅读变化
	for entry_id in Unlock.read_book_entry_ids.keys():
		if not old_read_entries.has(entry_id):
			new_read_entries.append(entry_id)

	var lines: Array[String] = []
	lines.append("已阅读条目：%s" % current_entry.get_display_name())

	if new_read_entries.is_empty() and new_formulas.is_empty() and new_diseases.is_empty():
		lines.append("没有新增解锁内容")
	else:
		if not new_read_entries.is_empty():
			lines.append("新完成条目：%s" % "、".join(new_read_entries))
		if not new_formulas.is_empty():
			lines.append("新解锁方剂：%s" % "、".join(new_formulas))
		if not new_diseases.is_empty():
			lines.append("新解锁病证：%s" % "、".join(new_diseases))

	var detail_text := current_entry.detail_text.strip_edges()
	if detail_text != "":
		lines.append("")
		lines.append("条目正文：")
		lines.append(detail_text)

	lines.append("")
	lines.append("点击“进入明天”返回诊室")

	info_label.text = "\n".join(lines)


# 点击进入明天
func _on_next_day_button_pressed() -> void:
	emit_signal("study_finished")
