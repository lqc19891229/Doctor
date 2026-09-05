extends Window
class_name ReadBook

signal window_closed
signal player_data_changed

# =========================
# 节点引用
# =========================

@onready var info_label: Label = $MarginContainer/VBoxRoot/InfoLabel
# 左侧：书籍列表
@onready var book_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/BookPanel/BookVBox/BookList

# 中间：条目列表
@onready var entry_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/EntryPanel/EntryVBox/EntryList

# 右侧：正文窗口
@onready var detail_text: RichTextLabel = $MarginContainer/VBoxRoot/ContentRow/DetailPanel/DetailScroll/DetailText

# 右侧：书页背景
@onready var detail_book_page: TextureRect = $MarginContainer/VBoxRoot/ContentRow/DetailPanel/DetailBookPage

# 可选：如果 ReadBook 窗口里还保留了 TopBar，就自动刷新天数；没有也不报错。
@onready var day_label: Label = get_node_or_null("MarginContainer/VBoxRoot/TopBar/DayLabel") as Label


# =========================
# 运行时数据
# =========================

var books: Array[BookData] = []
var book_new_entry_counts: Array[int] = []
var readable_entries: Array[BookEntryData] = []

var selected_book: BookData = null
var selected_entry: BookEntryData = null

# UnlockManager 的医书状态版本。版本未变化时，不重建 22 本书的列表。
var last_readbook_state_version: int = -1
var book_list_dirty: bool = true


func _ready() -> void:
	# 使用 Window 自带右上角 X 关闭按钮。
	if not close_requested.is_connected(_on_window_close_requested):
		close_requested.connect(_on_window_close_requested)

	_connect_ui_signals()
	_update_day_label()

	# ReadBook 默认是隐藏子窗口；不要在 Night 创建时提前构建整套书籍列表。
	# 第一次真正打开窗口时再按状态版本懒加载。
	book_list_dirty = true
	_clear_entry_and_detail()

	info_label.text = "请选择要查看的医书。"


# =========================
# 对外打开 / 关闭接口
# =========================

func open_window() -> void:
	# 天数文本很轻，打开时直接同步；书籍列表只有状态版本变化才重建。
	_update_day_label()
	_refresh_book_list_if_dirty()
	_clear_entry_and_detail()
	show()
	_focus_book_list_on_open()


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
# ReadBook dirty / version
# =========================

func mark_data_dirty() -> void:
	book_list_dirty = true


func _get_readbook_state_version() -> int:
	if Unlock != null and Unlock.has_method("get_readbook_state_version"):
		return int(Unlock.get_readbook_state_version())

	# 兼容旧 UnlockManager：没有版本接口时每次打开都刷新一次。
	return -1


func _refresh_book_list_if_dirty(force_refresh: bool = false) -> void:
	var current_version := _get_readbook_state_version()

	if current_version < 0:
		_refresh_book_list()
		return

	if not force_refresh and not book_list_dirty and current_version == last_readbook_state_version:
		return

	_refresh_book_list()
	last_readbook_state_version = current_version
	book_list_dirty = false

	if OS.is_debug_build():
		print("[ReadBook] 书籍列表已刷新：状态版本=", current_version, "，可见书籍=", books.size())


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
			display_name += "  【新%d】" % new_entry_count

		books.append(book)
		book_new_entry_counts.append(new_entry_count)
		book_list.add_item(display_name)
		var item_index := book_list.item_count - 1

		if new_entry_count > 0:
			book_list.set_item_custom_fg_color(item_index, Color(1.0, 0.82, 0.32, 1.0))
			book_list.set_item_tooltip(item_index, "有 %d 个新解锁条目可以查看" % new_entry_count)

		if selected_book_id != "" and book.book_id.strip_edges() == selected_book_id:
			selected_index = item_index

	if selected_index >= 0:
		book_list.select(selected_index)
	elif selected_book_id != "":
		# 读入其它存档后，上一份存档选中的书可能已不可见。
		selected_book = null
		selected_entry = null


# =========================
# 清空条目与正文
# =========================

func _clear_entry_and_detail() -> void:
	entry_list.clear()
	readable_entries.clear()
	selected_entry = null
	_set_detail_text("")


# =========================
# 打开窗口时默认停在书籍栏
# =========================

func _focus_book_list_on_open() -> void:
	if book_list == null:
		return

	# 先把键盘 / 手柄焦点放回左侧书籍列表，避免默认落到条目栏。
	book_list.grab_focus()

	# 如果当前没有选中书籍，则默认选中第一本书，只刷新条目列表，不阅读条目。
	if selected_book == null and books.size() > 0:
		book_list.select(0)
		selected_book = books[0]
		_refresh_entry_list_for_selected_book()
		book_list.grab_focus()
		return

	# 如果之前已经选过一本书，恢复书籍栏选中状态，并重新刷新条目列表。
	# 注意：open_window() 里已经调用过 _clear_entry_and_detail()，
	# 所以这里必须重新刷新条目，否则再次打开窗口时条目栏会是空的。
	_reselect_current_book_in_list()
	_refresh_entry_list_for_selected_book()
	book_list.grab_focus()


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
	_clear_entry_and_detail()

	if selected_book == null:
		return

	readable_entries = Unlock.get_readable_entries_by_book(selected_book.book_id)
	_sort_unread_entries_to_top()

	for entry in readable_entries:
		_add_entry_list_item(entry)

	if readable_entries.is_empty():
		info_label.text = "《%s》当前没有已解锁条目。" % selected_book.book_name
		_set_detail_text("")
		return

	var new_entry_count = Unlock.get_unread_readable_entry_count_by_book(selected_book.book_id)
	if new_entry_count > 0:
		info_label.text = "《%s》共有 %d 个已解锁条目，其中 %d 个尚未查看。" % [
			selected_book.book_name,
			readable_entries.size(),
			new_entry_count
		]
	else:
		info_label.text = "《%s》共有 %d 个已解锁条目。" % [
			selected_book.book_name,
			readable_entries.size()
		]

	# 只显示条目列表，不自动选中 / 阅读第一个条目。
	# 玩家需要手动点击条目后，才会触发 _show_entry_by_index() 并标记已读。
	entry_list.deselect_all()
	selected_entry = null
	_set_detail_text("")


# =========================
# 拼装正文文本
# =========================

func _get_entry_list_display_name(entry: BookEntryData) -> String:
	if entry == null:
		return ""

	var display_name := entry.title
	if not Unlock.is_entry_read(entry.entry_id) and Unlock.can_read_entry(entry.entry_id):
		display_name += "  【新】"

	return display_name


func _is_unread_readable_entry(entry: BookEntryData) -> bool:
	if entry == null:
		return false

	var entry_id := entry.entry_id.strip_edges()
	if entry_id == "":
		return false

	return Unlock.can_read_entry(entry_id) and not Unlock.is_entry_read(entry_id)


func _sort_unread_entries_to_top() -> void:
	var unread_entries: Array[BookEntryData] = []
	var read_or_normal_entries: Array[BookEntryData] = []

	for entry in readable_entries:
		if _is_unread_readable_entry(entry):
			unread_entries.append(entry)
		else:
			read_or_normal_entries.append(entry)

	readable_entries.clear()
	readable_entries.append_array(unread_entries)
	readable_entries.append_array(read_or_normal_entries)


func _add_entry_list_item(entry: BookEntryData) -> void:
	if entry == null:
		return

	entry_list.add_item(_get_entry_list_display_name(entry))
	var item_index := entry_list.item_count - 1

	if _is_unread_readable_entry(entry):
		entry_list.set_item_custom_fg_color(item_index, Color(1.0, 0.82, 0.32, 1.0))
		entry_list.set_item_tooltip(item_index, "新解锁条目，尚未查看")


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
	_show_entry_by_index(index)


# =========================
# 直接查看条目
# =========================

func _show_entry_by_index(index: int) -> void:
	if index < 0 or index >= readable_entries.size():
		return

	selected_entry = readable_entries[index]
	if selected_entry == null:
		return

	var current_entry_id := selected_entry.entry_id.strip_edges()
	if current_entry_id == "":
		return

	# 只允许查看已经满足对应解锁条件，或已经读过的条目。
	if not Unlock.is_entry_unlocked(current_entry_id) and not Unlock.is_entry_read(current_entry_id):
		info_label.text = "该条目尚未解锁，请先满足对应的解锁条件。"
		_set_detail_text("")
		return

	var was_unread := not Unlock.is_entry_read(current_entry_id)

	# 第一次查看条目时标记为已读。
	# 药材会在此时同步解锁；方剂和疾病通常已由依赖关系提前解锁。
	if was_unread:
		Unlock.read_entry(selected_entry)
		_notify_player_data_changed()

	_set_detail_text(_build_entry_text(selected_entry))

	if was_unread:
		# read_entry() 可能进一步解锁药材 -> 方剂 -> 疾病，因此版本会变化。
		# 这里只在这次真实状态变化后重建一次书籍栏。
		mark_data_dirty()
		_refresh_book_list_if_dirty()
		_reselect_current_book_in_list()
		_refresh_entry_list_titles_keep_selection(current_entry_id)
		info_label.text = "已查看条目。"


func _reselect_current_book_in_list() -> void:
	if selected_book == null:
		return

	var current_book_id := selected_book.book_id.strip_edges()
	if current_book_id == "":
		return

	for i in range(books.size()):
		if books[i] != null and books[i].book_id.strip_edges() == current_book_id:
			book_list.select(i)
			return


func _refresh_entry_list_titles_keep_selection(entry_id: String) -> void:
	_sort_unread_entries_to_top()
	entry_list.clear()

	var selected_index := -1
	for i in range(readable_entries.size()):
		var entry := readable_entries[i]
		_add_entry_list_item(entry)

		if entry != null and entry.entry_id.strip_edges() == entry_id:
			selected_index = i
			selected_entry = entry

	if selected_index >= 0:
		entry_list.select(selected_index)


func _notify_player_data_changed() -> void:
	# 阅读状态与解锁变化先保留在内存，等 Night 正式结束时统一写盘。
	player_data_changed.emit()


# =========================
# 关闭读书窗口
# =========================

func _on_window_close_requested() -> void:
	close_window()
