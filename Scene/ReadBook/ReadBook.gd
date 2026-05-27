extends Window
class_name ReadBook

signal window_closed
signal player_data_changed

# =========================
# 节点引用
# =========================

@onready var info_label: Label = $MarginContainer/VBoxRoot/InfoLabel
@onready var read_button: Button = $MarginContainer/VBoxRoot/ButtonRow/ReadButton

# 左侧：书籍列表
@onready var book_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/BookPanel/BookVBox/BookList

# 中间：条目列表
@onready var entry_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/EntryPanel/EntryVBox/EntryList

# 右侧：正文窗口
@onready var detail_text: RichTextLabel = $MarginContainer/VBoxRoot/ContentRow/DetailPanel/DetailScroll/DetailText

# 右侧：书页背景
@onready var detail_book_page: TextureRect = $MarginContainer/VBoxRoot/ContentRow/DetailPanel/DetailBookPage

# 可选：如果 ReadBook 窗口里还保留了 TopBar，就自动刷新；没有也不报错。
@onready var day_label: Label = get_node_or_null("MarginContainer/VBoxRoot/TopBar/DayLabel") as Label
@onready var thoughts_point_label: Label = _get_thoughts_point_label()


# =========================
# 运行时数据
# =========================

var books: Array[BookData] = []
var book_new_entry_counts: Array[int] = []
var readable_entries: Array[BookEntryData] = []

var selected_book: BookData = null
var selected_entry: BookEntryData = null

# 记录上一次显示的心得数量。
var last_displayed_experience_points: int = -999


func _ready() -> void:
	# 使用 Window 自带右上角 X 关闭按钮。
	if not close_requested.is_connected(_on_window_close_requested):
		close_requested.connect(_on_window_close_requested)

	_update_day_label()
	_update_thoughts_point_ui()

	_connect_ui_signals()

	_refresh_book_list()
	_clear_entry_and_detail()
	read_button.disabled = true
	info_label.text = "请选择今晚要阅读的医书。当前心得：%d" % Unlock.get_experience_points()


func _process(_delta: float) -> void:
	_sync_thoughts_point_if_changed()


# =========================
# 对外打开 / 关闭接口
# =========================

func open_window() -> void:
	show()


func close_window() -> void:
	hide()
	window_closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		close_window()
		get_viewport().set_input_as_handled()


# =========================
# 初始化 / 节点查找
# =========================

func _connect_ui_signals() -> void:
	if not read_button.pressed.is_connected(_on_read_button_pressed):
		read_button.pressed.connect(_on_read_button_pressed)

	if not book_list.item_selected.is_connected(_on_book_selected):
		book_list.item_selected.connect(_on_book_selected)

	if not entry_list.item_selected.is_connected(_on_entry_selected):
		entry_list.item_selected.connect(_on_entry_selected)


# =========================
# 刷新顶部天数显示
# =========================

func _update_day_label() -> void:
	if day_label == null:
		return

	day_label.text = GameTime.get_day_text()


# =========================
# 获取顶部心得 Label
# =========================

func _get_thoughts_point_label() -> Label:
	var label := get_node_or_null("MarginContainer/VBoxRoot/TopBar/ThoughtsPoint") as Label
	if label != null:
		return label

	return find_child("ThoughtsPoint", true, false) as Label


# =========================
# 刷新顶部心得显示
# =========================

func _update_thoughts_point_ui() -> void:
	if thoughts_point_label == null:
		thoughts_point_label = _get_thoughts_point_label()

	var current_points := Unlock.get_experience_points()
	last_displayed_experience_points = current_points

	# ReadBook 作为窗口时可以没有 TopBar；没有就只刷新 InfoLabel，不报错。
	if thoughts_point_label == null:
		return

	thoughts_point_label.visible = true
	thoughts_point_label.show()
	thoughts_point_label.custom_minimum_size = Vector2(120, 24)
	thoughts_point_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	thoughts_point_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thoughts_point_label.text = "心得：%d" % current_points


# =========================
# 心得变化时自动刷新
# =========================

func _sync_thoughts_point_if_changed() -> void:
	var current_points := Unlock.get_experience_points()

	if thoughts_point_label == null or current_points != last_displayed_experience_points:
		_update_thoughts_point_ui()


# =========================
# 刷新书籍列表
# =========================

func _refresh_book_list() -> void:
	var selected_book_id := ""
	if selected_book != null:
		selected_book_id = selected_book.book_id.strip_edges()

	book_list.clear()
	books.clear()
	book_new_entry_counts.clear()

	var selected_index := -1

	for book in BookDB.get_all_books():
		if book == null:
			continue

		if not Unlock.is_book_visible_in_readbook(book):
			continue

		var new_entry_count = Unlock.get_unread_readable_entry_count_by_book(book.book_id)
		var display_name := book.book_name
		if new_entry_count > 0:
			display_name += "  【新 %d】" % new_entry_count

		books.append(book)
		book_new_entry_counts.append(new_entry_count)
		book_list.add_item(display_name)
		var item_index := book_list.item_count - 1

		if new_entry_count > 0:
			book_list.set_item_custom_fg_color(item_index, Color(1.0, 0.82, 0.32, 1.0))
			book_list.set_item_tooltip(item_index, "有 %d 个新解锁条目可以阅读" % new_entry_count)

		if selected_book_id != "" and book.book_id.strip_edges() == selected_book_id:
			selected_index = item_index

	if selected_index >= 0:
		book_list.select(selected_index)


# =========================
# 清空条目与正文
# =========================

func _clear_entry_and_detail() -> void:
	entry_list.clear()
	readable_entries.clear()
	selected_entry = null
	_set_detail_text("")


# =========================
# 设置正文文本
# =========================

func _set_detail_text(value: String) -> void:
	if detail_text == null:
		return

	# 如果 DetailText 挂的是 ClassicalVerticalRichTextLabel.gd，
	# 使用 set_source_text 让它重新生成古籍竖排文本。
	if detail_text.has_method("set_source_text"):
		detail_text.call("set_source_text", value)
	else:
		detail_text.text = value


# =========================
# 刷新当前书的条目列表
# =========================

func _refresh_entry_list_for_selected_book() -> void:
	_update_thoughts_point_ui()
	_clear_entry_and_detail()

	if selected_book == null:
		return

	# -------------------------
	# 1) 药材书：神农百草经
	# -------------------------
	if selected_book.is_herb_book():
		readable_entries = Unlock.get_readable_entries_by_book(selected_book.book_id)

		for entry in readable_entries:
			if entry == null:
				continue

			entry_list.add_item(entry.title)

		var herb_unlock_order := selected_book.get_herb_unlock_order()
		var total := herb_unlock_order.size()
		var days := Unlock.get_book_read_days(selected_book.book_id)
		var unlocked_count = min(days, total)
		var pending_count := Unlock.get_unread_unlocked_disease_or_formula_entry_count()
		var can_continue := Unlock.can_continue_herb_book_reading(selected_book)

		if pending_count > 0:
			info_label.text = "《%s》 进度：%d/%d，已解锁药材：%d\n还有 %d 个已解锁但未阅读的疾病/方剂条目。请先阅读它们，之后才能继续阅读神农百草经的新条目。\n当前心得：%d" % [
				selected_book.book_name, days, total, unlocked_count, pending_count, Unlock.get_experience_points()
			]
		elif days >= total:
			info_label.text = "《%s》已经全部读完。已解锁药材：%d/%d\n当前心得：%d" % [
				selected_book.book_name, unlocked_count, total, Unlock.get_experience_points()
			]
		else:
			var next_herb := String(herb_unlock_order[days]).strip_edges()
			info_label.text = "《%s》 进度：%d/%d，已解锁药材：%d，下一味：%s\n当前心得：%d" % [
				selected_book.book_name, days, total, unlocked_count, next_herb, Unlock.get_experience_points()
			]

		read_button.text = "阅读本书"
		read_button.disabled = not can_continue

		if readable_entries.size() > 0:
			entry_list.select(0)
			selected_entry = readable_entries[0]
			_set_detail_text(_build_entry_text(selected_entry))
		else:
			_set_detail_text("")

		return

	# -------------------------
	# 2) 普通医书：如伤寒论
	# -------------------------
	readable_entries = Unlock.get_readable_entries_by_book(selected_book.book_id)

	for entry in readable_entries:
		if entry == null:
			continue

		var display_name := entry.title

		if Unlock.is_entry_read(entry.entry_id):
			display_name += " [已读]"
		else:
			display_name += " [未读]"

		entry_list.add_item(display_name)

	read_button.text = "阅读条目"
	read_button.disabled = readable_entries.is_empty()

	if readable_entries.is_empty():
		info_label.text = "《%s》当前没有可阅读条目。" % selected_book.book_name
		_set_detail_text("")
		return

	var new_entry_count = Unlock.get_unread_readable_entry_count_by_book(selected_book.book_id)
	if new_entry_count > 0:
		info_label.text = "《%s》共有 %d 个可阅读条目，其中 %d 个新解锁条目尚未阅读。\n当前心得：%d" % [
			selected_book.book_name, readable_entries.size(), new_entry_count, Unlock.get_experience_points()
		]
	else:
		info_label.text = "《%s》共有 %d 个可阅读条目。\n当前心得：%d" % [
			selected_book.book_name, readable_entries.size(), Unlock.get_experience_points()
		]

	entry_list.select(0)
	selected_entry = readable_entries[0]

	if Unlock.is_entry_read(selected_entry.entry_id):
		_set_detail_text(_build_entry_text(selected_entry))
	else:
		_set_detail_text("该条目尚未阅读，阅读后显示正文内容。")


# =========================
# 拼装正文文本
# =========================

func _build_entry_text(entry: BookEntryData) -> String:
	if entry == null:
		return ""

	if entry.detail_text.strip_edges() != "":
		return entry.detail_text

	return "暂无正文"


# =========================
# 选中书籍
# =========================

func _on_book_selected(index: int) -> void:
	if index < 0 or index >= books.size():
		return

	selected_book = books[index]
	selected_entry = null
	_refresh_entry_list_for_selected_book()


# =========================
# 选中条目
# =========================

func _on_entry_selected(index: int) -> void:
	if index < 0 or index >= readable_entries.size():
		return

	selected_entry = readable_entries[index]

	if selected_book != null and selected_book.is_herb_book():
		_set_detail_text(_build_entry_text(selected_entry))
		return

	if Unlock.is_entry_read(selected_entry.entry_id):
		_set_detail_text(_build_entry_text(selected_entry))
	else:
		_set_detail_text("该条目尚未阅读，阅读后显示正文内容。")


# =========================
# 点击阅读
# =========================

func _on_read_button_pressed() -> void:
	if selected_book == null:
		return

	# 药材书：消耗 1 点心得，推进整本书进度。
	if selected_book.is_herb_book():
		var herb_unlock_order := selected_book.get_herb_unlock_order()
		var days := Unlock.get_book_read_days(selected_book.book_id)

		if days >= herb_unlock_order.size():
			info_label.text = "《%s》已经全部读完。\n当前心得：%d" % [
				selected_book.book_name, Unlock.get_experience_points()
			]
			return

		var pending_count := Unlock.get_unread_unlocked_disease_or_formula_entry_count()
		if pending_count > 0:
			_update_thoughts_point_ui()
			info_label.text = "还有 %d 个已解锁但未阅读的疾病/方剂条目。请先阅读它们，之后才能继续阅读神农百草经的新条目。" % pending_count
			read_button.disabled = true
			return

		if not Unlock.consume_experience_point():
			_update_thoughts_point_ui()
			info_label.text = "心得不足。白天开方获得满分甲等评价后，可获得 1 点心得。"
			return

		_update_thoughts_point_ui()
		Unlock.read_book_by_day(selected_book)
		_save_and_notify_player_data_changed()

		_refresh_book_list()
		_refresh_entry_list_for_selected_book()
		_update_thoughts_point_ui()
		info_label.text += "\n消耗心得：-1，当前心得：%d" % Unlock.get_experience_points()

		if readable_entries.size() > 0:
			entry_list.select(0)
			selected_entry = readable_entries[0]
			_set_detail_text(_build_entry_text(selected_entry))
		else:
			_set_detail_text("")

		return

	# 普通书：阅读当前条目。
	if selected_entry == null:
		return

	if Unlock.is_entry_read(selected_entry.entry_id):
		_update_thoughts_point_ui()
		_set_detail_text(_build_entry_text(selected_entry))
		info_label.text = "该条目已读，可直接回看。\n当前心得：%d" % Unlock.get_experience_points()
		return

	if not Unlock.consume_experience_point():
		_update_thoughts_point_ui()
		info_label.text = "心得不足。白天开方获得满分甲等评价后，可获得 1 点心得。"
		return

	_update_thoughts_point_ui()

	var current_entry_id := selected_entry.entry_id
	Unlock.read_entry(selected_entry)
	_save_and_notify_player_data_changed()

	_refresh_book_list()
	_refresh_entry_list_for_selected_book()
	_update_thoughts_point_ui()
	info_label.text += "\n消耗心得：-1，当前心得：%d" % Unlock.get_experience_points()

	for i in range(readable_entries.size()):
		if readable_entries[i].entry_id == current_entry_id:
			selected_entry = readable_entries[i]
			entry_list.select(i)
			_set_detail_text(_build_entry_text(selected_entry))
			break


func _save_and_notify_player_data_changed() -> void:
	if SaveManager != null and SaveManager.has_method("save_game"):
		SaveManager.save_game()

	player_data_changed.emit()


# =========================
# 关闭读书窗口
# =========================

func _on_window_close_requested() -> void:
	close_window()
