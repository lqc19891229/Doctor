extends Window
class_name ReadBook

signal window_closed
signal player_data_changed

const FIXED_WINDOW_POSITION := Vector2i(50, 66)

# =========================
# 节点引用
# =========================

@onready var info_label: Label = $MarginContainer/VBoxRoot/BottomRow/InfoLabel
@onready var pulse_practice_button: Button = $MarginContainer/VBoxRoot/BottomRow/PulsePracticeButton
@onready var pulse_practice_window: PulseWindow = $PulsePracticeWindow
# 左侧：书籍列表
@onready var book_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/BookPanel/BookVBox/BookList

# 中间：条目搜索 / 列表
@onready var search_edit: LineEdit = $MarginContainer/VBoxRoot/SearchEdit
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

# 所有当前可在 ReadBook 中显示的医书。
# 全局搜索时 books 会变成筛选后的书籍列表，因此另外保留完整集合。
var all_visible_books: Array[BookData] = []

# 当前左侧 BookList 实际显示的医书。
var books: Array[BookData] = []
var book_new_entry_counts: Array[int] = []

# 当前选中医书的全部可阅读条目。
var readable_entries: Array[BookEntryData] = []

# 当前全局搜索匹配到的条目总数。
var global_search_match_count: int = 0

# 当前 EntryList 实际显示的条目。
# 搜索后 ItemList 的索引不再等同于 readable_entries 的索引，
# 因此必须单独保存显示结果，避免点击搜索结果时打开错误条目。
var displayed_entries: Array[BookEntryData] = []

var selected_book: BookData = null
var selected_entry: BookEntryData = null

# UnlockManager 的医书状态版本。版本未变化时，不重建 22 本书的列表。
var last_readbook_state_version: int = -1
var book_list_dirty: bool = true
var _info_message_key: String = ""
var _info_message_args: Array = []


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return

	title = tr("UI_READ_BOOK_WINDOW_TITLE")
	_update_pulse_practice_button()

	# 只重绘列表文字，保留当前书籍、条目和正文的选中状态。
	if visible:
		var book_id := selected_book.book_id if selected_book != null else ""
		var entry_id := selected_entry.entry_id if selected_entry != null else ""
		_rebuild_book_list_for_search(book_id)
		if selected_book != null:
			_refresh_entry_list_view(entry_id)
			if selected_entry != null:
				_set_detail_text(_build_entry_text(selected_entry))

	if selected_book != null and _info_message_key in [
		"UI_READ_BOOK_SEARCH_SUMMARY_FMT",
		"UI_READ_BOOK_EMPTY_BOOK_FMT",
		"UI_READ_BOOK_UNREAD_COUNT_FMT",
		"UI_READ_BOOK_ENTRY_COUNT_FMT"
	]:
		_update_entry_info_label()
	elif _info_message_key != "":
		_set_info_message(_info_message_key, _info_message_args)
	if pulse_practice_window != null and pulse_practice_window.visible:
		call_deferred("_update_pulse_practice_title")


func _set_info_message(key: String, args: Array = []) -> void:
	_info_message_key = key
	_info_message_args = args
	info_label.text = tr(key) % args if not args.is_empty() else tr(key)


func _localized_book_name(book: BookData) -> String:
	if book == null:
		return ""
	var key := "UI_BOOK_NAME_" + book.book_id.to_upper()
	var translated := tr(key)
	return book.book_name if translated == key else translated


func _ready() -> void:
	title = tr("UI_READ_BOOK_WINDOW_TITLE")
	# ReadBook 始终固定在屏幕坐标 (50, 66)。
	position = FIXED_WINDOW_POSITION

	# 使用 Window 自带右上角 X 关闭按钮。
	if not close_requested.is_connected(_on_window_close_requested):
		close_requested.connect(_on_window_close_requested)

	_connect_ui_signals()
	_update_day_label()

	# ReadBook 默认是隐藏子窗口；不要在 Night 创建时提前构建整套书籍列表。
	# 第一次真正打开窗口时再按状态版本懒加载。
	book_list_dirty = true
	_clear_entry_and_detail()

	_set_info_message("UI_READ_BOOK_CHOOSE_BOOK")


# =========================
# 对外打开 / 关闭接口
# =========================

func open_window() -> void:
	# 每次打开都恢复固定位置，避免上次窗口状态影响坐标。
	position = FIXED_WINDOW_POSITION

	# 每次重新打开读书窗口时清空上一次全局搜索。
	# 阻止 text_changed 在窗口尚未完成刷新时提前触发筛选。
	if search_edit != null:
		search_edit.set_block_signals(true)
		search_edit.clear()
		search_edit.set_block_signals(false)

	_update_day_label()
	_refresh_book_list_if_dirty()

	# 即使解锁状态版本没有变化，也要根据已经清空的搜索词
	# 重新构建左侧列表，避免保留上次关闭窗口前的搜索结果。
	var preferred_book_id := ""
	if selected_book != null:
		preferred_book_id = selected_book.book_id.strip_edges()
	_rebuild_book_list_for_search(preferred_book_id)

	_clear_entry_and_detail()
	show()
	_focus_book_list_on_open()


func _process(_delta: float) -> void:
	# Window 没有 position_changed 信号，因此每帧检查位置。
	# 只有窗口可见且坐标被改变时才写回，避免无意义赋值。
	if visible and position != FIXED_WINDOW_POSITION:
		position = FIXED_WINDOW_POSITION


func close_window() -> void:
	if pulse_practice_window != null and pulse_practice_window.visible:
		pulse_practice_window.close_window()

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

	if search_edit != null and not search_edit.text_changed.is_connected(_on_search_text_changed):
		search_edit.text_changed.connect(_on_search_text_changed)

	if pulse_practice_button != null and not pulse_practice_button.pressed.is_connected(_on_pulse_practice_button_pressed):
		pulse_practice_button.pressed.connect(_on_pulse_practice_button_pressed)


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


# =========================
# 刷新书籍列表
# =========================

func _refresh_book_list() -> void:
	var selected_book_id := ""
	if selected_book != null:
		selected_book_id = selected_book.book_id.strip_edges()

	all_visible_books.clear()

	for book in BookDB.get_all_books():
		if book == null:
			continue

		if not Unlock.is_book_visible_in_readbook(book):
			continue

		all_visible_books.append(book)

	var preferred_index := _rebuild_book_list_for_search(selected_book_id)

	# 如果读入其它存档后，上一份存档选中的书已经完全不可见，
	# 清掉旧选择。仅仅因为搜索过滤而暂时不显示，不在这里清空。
	if selected_book_id != "":
		var still_visible := false
		for book in all_visible_books:
			if book != null and book.book_id.strip_edges() == selected_book_id:
				still_visible = true
				break

		if not still_visible:
			selected_book = null
			selected_entry = null
		elif preferred_index >= 0:
			book_list.select(preferred_index)


func _count_matching_entries_in_book(book: BookData) -> int:
	if book == null:
		return 0

	var query := _get_search_query()
	if query == "":
		return 0

	var match_count := 0
	var entries: Array[BookEntryData] = Unlock.get_readable_entries_by_book(book.book_id)

	for entry in entries:
		if _entry_matches_search(entry):
			match_count += 1

	return match_count


func _rebuild_book_list_for_search(preferred_book_id: String = "") -> int:
	book_list.clear()
	books.clear()
	book_new_entry_counts.clear()
	global_search_match_count = 0

	var query := _get_search_query()
	var preferred_index := -1

	for book in all_visible_books:
		if book == null:
			continue

		var match_count := 0
		if query != "":
			match_count = _count_matching_entries_in_book(book)
			if match_count <= 0:
				continue
			global_search_match_count += match_count

		var new_entry_count = Unlock.get_unread_readable_entry_count_by_book(book.book_id)
		var display_name := _localized_book_name(book)

		if query != "":
			display_name += tr("UI_READ_BOOK_MATCH_BADGE_FMT") % match_count

		if new_entry_count > 0:
			display_name += tr("UI_READ_BOOK_NEW_COUNT_BADGE_FMT") % new_entry_count

		books.append(book)
		book_new_entry_counts.append(new_entry_count)
		book_list.add_item(display_name)

		var item_index := book_list.item_count - 1

		if new_entry_count > 0:
			book_list.set_item_custom_fg_color(
				item_index,
				Color(1.0, 0.82, 0.32, 1.0)
			)

		if query != "":
			book_list.set_item_tooltip(
				item_index,
				tr("UI_READ_BOOK_MATCH_TOOLTIP_FMT") % match_count
			)
		elif new_entry_count > 0:
			book_list.set_item_tooltip(
				item_index,
				tr("UI_READ_BOOK_NEW_TOOLTIP_FMT") % new_entry_count
			)
		else:
			book_list.set_item_tooltip(item_index, display_name)

		if preferred_book_id != "" and book.book_id.strip_edges() == preferred_book_id:
			preferred_index = item_index

	if preferred_index >= 0:
		book_list.select(preferred_index)

	return preferred_index


# =========================
# 清空条目与正文
# =========================

func _clear_entry_and_detail() -> void:
	entry_list.clear()
	readable_entries.clear()
	displayed_entries.clear()
	selected_entry = null
	_set_detail_text("")
	_update_pulse_practice_button()


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

	var use_english_page := false
	if value != "" and selected_entry != null and TranslationServer.get_locale().begins_with("en"):
		var body_key := "UI_BOOK_ENTRY_BODY_" + selected_entry.entry_id.to_upper()
		use_english_page = tr(body_key) != body_key

	# 如果 DetailText 挂的是 ClassicalVerticalRichTextLabel.gd，
	# 使用 set_source_text 让它重新生成古籍竖排文本。
	if use_english_page and detail_text.has_method("set_horizontal_source_text"):
		detail_text.call("set_horizontal_source_text", value)
	elif detail_text.has_method("set_source_text"):
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
	_sort_entries_by_index()

	_refresh_entry_list_view()
	_update_entry_info_label()

	# 只显示条目列表，不自动选中 / 阅读第一个条目。
	# 玩家需要手动点击条目后，才会触发 _show_entry_by_index() 并标记已读。
	entry_list.deselect_all()
	selected_entry = null
	_set_detail_text("")


# =========================
# 全局条目搜索
# =========================

func _get_search_query() -> String:
	if search_edit == null:
		return ""

	return search_edit.text.strip_edges()


func _entry_matches_search(entry: BookEntryData) -> bool:
	if entry == null:
		return false

	var query := _get_search_query()
	if query == "":
		return true

	# findn() 为大小写不敏感搜索；中文标题可直接匹配。
	return entry.title.findn(query) >= 0 or _localized_entry_title(entry).findn(query) >= 0


func _refresh_entry_list_view(select_entry_id: String = "") -> void:
	entry_list.clear()
	displayed_entries.clear()

	var selected_index := -1

	for entry in readable_entries:
		if not _entry_matches_search(entry):
			continue

		displayed_entries.append(entry)
		_add_entry_list_item(entry)

		if (
			select_entry_id != ""
			and entry != null
			and entry.entry_id.strip_edges() == select_entry_id
		):
			selected_index = displayed_entries.size() - 1
			selected_entry = entry

	if selected_index >= 0:
		entry_list.select(selected_index)

	_update_pulse_practice_button()


func _update_entry_info_label() -> void:
	if selected_book == null:
		return

	var raw_query := _get_search_query()

	if raw_query != "":
		_set_info_message("UI_READ_BOOK_SEARCH_SUMMARY_FMT", [
			raw_query,
			global_search_match_count,
			_localized_book_name(selected_book),
			displayed_entries.size()
		])
		return

	if readable_entries.is_empty():
		_set_info_message("UI_READ_BOOK_EMPTY_BOOK_FMT", [_localized_book_name(selected_book)])
		return

	var new_entry_count = Unlock.get_unread_readable_entry_count_by_book(selected_book.book_id)
	if new_entry_count > 0:
		_set_info_message("UI_READ_BOOK_UNREAD_COUNT_FMT", [
			_localized_book_name(selected_book),
			readable_entries.size(),
			new_entry_count
		])
	else:
		_set_info_message("UI_READ_BOOK_ENTRY_COUNT_FMT", [
			_localized_book_name(selected_book),
			readable_entries.size()
		])


func _on_search_text_changed(_new_text: String) -> void:
	var preferred_book_id := ""
	if selected_book != null:
		preferred_book_id = selected_book.book_id.strip_edges()

	selected_entry = null
	_set_detail_text("")

	var preferred_index := _rebuild_book_list_for_search(preferred_book_id)

	if books.is_empty():
		selected_book = null
		_clear_entry_and_detail()

		var query := _get_search_query()
		if query == "":
			_set_info_message("UI_READ_BOOK_NO_BOOKS")
		else:
			_set_info_message("UI_READ_BOOK_NO_RESULTS_FMT", [query])
		return

	# 当前书仍有匹配结果时继续停留；
	# 否则自动切换到第一本包含匹配条目的医书。
	var target_index := preferred_index
	if target_index < 0:
		target_index = 0
		book_list.select(target_index)

	selected_book = books[target_index]
	_refresh_entry_list_for_selected_book()

# =========================
# 拼装正文文本
# =========================

func _get_entry_list_display_name(entry: BookEntryData) -> String:
	if entry == null:
		return ""

	var display_name := _localized_entry_title(entry)
	if not Unlock.is_entry_read(entry.entry_id) and Unlock.can_read_entry(entry.entry_id):
		display_name += tr("UI_READ_BOOK_NEW_BADGE")

	return display_name


func _localized_entry_title(entry: BookEntryData) -> String:
	if entry == null:
		return ""
	var key := "UI_BOOK_ENTRY_TITLE_" + entry.entry_id.to_upper()
	var translated := tr(key)
	return entry.title if translated == key else translated


func _is_unread_readable_entry(entry: BookEntryData) -> bool:
	if entry == null:
		return false

	var entry_id := entry.entry_id.strip_edges()
	if entry_id == "":
		return false

	return Unlock.can_read_entry(entry_id) and not Unlock.is_entry_read(entry_id)


func _sort_entries_by_index() -> void:
	readable_entries.sort_custom(
		func(a: BookEntryData, b: BookEntryData) -> bool:
			# 新解锁且尚未阅读的条目始终排在最上方，
			# 方便玩家第一时间看到本轮新增内容。
			var a_is_new := _is_unread_readable_entry(a)
			var b_is_new := _is_unread_readable_entry(b)

			if a_is_new != b_is_new:
				return a_is_new

			# 同为新条目，或同为已读条目时，再按 sort_index 排序。
			# 因此一个新条目被阅读后，会自动回到它自己的 sort_index 位置。
			if a.sort_index != b.sort_index:
				return a.sort_index < b.sort_index

			# sort_index 相同时使用 entry_id 保证显示顺序稳定。
			return a.entry_id.naturalnocasecmp_to(b.entry_id) < 0
	)


func _add_entry_list_item(entry: BookEntryData) -> void:
	if entry == null:
		return

	entry_list.add_item(_get_entry_list_display_name(entry))
	var item_index := entry_list.item_count - 1

	if _is_unread_readable_entry(entry):
		entry_list.set_item_custom_fg_color(item_index, Color(1.0, 0.82, 0.32, 1.0))
		entry_list.set_item_tooltip(item_index, tr("UI_READ_BOOK_NEW_ENTRY_TOOLTIP"))


func _build_entry_text(entry: BookEntryData) -> String:
	if entry == null:
		return ""

	if entry.detail_text.strip_edges() != "":
		var key := "UI_BOOK_ENTRY_BODY_" + entry.entry_id.to_upper()
		var translated := tr(key)
		return entry.detail_text if translated == key else translated

	return tr("UI_READ_BOOK_NO_CONTENT")


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
	if index < 0 or index >= displayed_entries.size():
		return

	selected_entry = displayed_entries[index]
	if selected_entry == null:
		return

	var current_entry_id := selected_entry.entry_id.strip_edges()
	if current_entry_id == "":
		return

	# 只允许查看已经满足对应解锁条件，或已经读过的条目。
	if not Unlock.is_entry_unlocked(current_entry_id) and not Unlock.is_entry_read(current_entry_id):
		_set_info_message("UI_READ_BOOK_ENTRY_LOCKED")
		_set_detail_text("")
		return

	var was_unread := not Unlock.is_entry_read(current_entry_id)

	# 第一次查看条目时标记为已读。
	# 药材会在此时同步解锁；方剂和疾病通常已由依赖关系提前解锁。
	if was_unread:
		Unlock.read_entry(selected_entry)
		_notify_player_data_changed()

	_set_detail_text(_build_entry_text(selected_entry))
	_update_pulse_practice_button()

	if was_unread:
		# read_entry() 可能进一步解锁药材 -> 方剂 -> 疾病，因此版本会变化。
		# 这里只在这次真实状态变化后重建一次书籍栏。
		mark_data_dirty()
		_refresh_book_list_if_dirty()
		_reselect_current_book_in_list()
		_refresh_entry_list_titles_keep_selection(current_entry_id)
		_set_info_message("UI_READ_BOOK_ENTRY_READ")


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
	# 阅读条目后可能触发级联解锁。
	# 重新取得当前书的可读条目，确保刚解锁的新条目可以立刻出现在列表顶部。
	if selected_book != null:
		readable_entries = Unlock.get_readable_entries_by_book(selected_book.book_id)

	_sort_entries_by_index()
	_refresh_entry_list_view(entry_id)

# =========================
# 夜晚脉象练习
# =========================

func _get_selected_disease_data() -> DiseaseData:
	if selected_entry == null:
		return null

	if not (selected_entry is DiseaseBookEntryData):
		return null

	var disease_entry := selected_entry as DiseaseBookEntryData
	if disease_entry == null:
		return null

	var disease_id := disease_entry.disease_id.strip_edges()
	if disease_id == "":
		return null

	return DiseaseDB.get_disease_by_id(disease_id)


func _update_pulse_practice_button() -> void:
	if pulse_practice_button == null:
		return

	var disease := _get_selected_disease_data()

	if disease == null:
		pulse_practice_button.disabled = true
		pulse_practice_button.text = tr("UI_READ_BOOK_VIEW_PULSE")
		pulse_practice_button.tooltip_text = tr("UI_READ_BOOK_PULSE_SELECT_HINT")
		return

	pulse_practice_button.disabled = false
	pulse_practice_button.text = tr("UI_READ_BOOK_VIEW_PULSE")
	pulse_practice_button.tooltip_text = tr("UI_READ_BOOK_PULSE_TOOLTIP_FMT") % disease.disease_name


func _on_pulse_practice_button_pressed() -> void:
	var disease := _get_selected_disease_data()
	if disease == null:
		_set_info_message("UI_READ_BOOK_SELECT_DISEASE_FIRST")
		_update_pulse_practice_button()
		return

	if pulse_practice_window == null:
		_set_info_message("UI_READ_BOOK_PULSE_MISSING")
		return

	# 使用 ReadBook 自己的 PulseWindow 实例，不影响白天诊所的把脉窗口。
	_update_pulse_practice_title()
	pulse_practice_window.open_window()

	# PulseWindow.open_window() 会 deferred 回到“按键提示”页。
	# 所以这里也 deferred，在它之后切换为练习模式并显示右手脉象。
	call_deferred("_show_pulse_practice_disease", disease)


func _update_pulse_practice_title() -> void:
	if pulse_practice_window == null:
		return
	var disease := _get_selected_disease_data()
	if disease != null:
		pulse_practice_window.title = tr("UI_READ_BOOK_PULSE_TITLE_FMT") % disease.disease_name


func _show_pulse_practice_disease(disease: DiseaseData) -> void:
	if pulse_practice_window == null or disease == null:
		return

	var tabs := pulse_practice_window.get_node_or_null("LayerTabs") as TabContainer
	if tabs != null:
		# ReadBook 练习不需要 Clinic 的按键提示页。
		# 把左右手标签显示出来，让玩家可以直接点击切换复习。
		tabs.set_tab_hidden(0, true)
		tabs.set_tab_hidden(1, false)
		tabs.set_tab_hidden(2, false)

	# show_hand_group 会一次刷新左右两手的数据；
	# 默认先显示右手，玩家随后可点击“左手脉象”标签切换。
	pulse_practice_window.show_hand_group("right", disease)


func _notify_player_data_changed() -> void:
	# 阅读状态与解锁变化先保留在内存，等 Night 正式结束时统一写盘。
	player_data_changed.emit()


# =========================
# 关闭读书窗口
# =========================

func _on_window_close_requested() -> void:
	close_window()
