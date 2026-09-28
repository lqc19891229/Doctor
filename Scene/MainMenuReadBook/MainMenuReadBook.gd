extends Window
class_name MainMenuReadBook

## 主菜单“阅读典籍”专用窗口。
##
## 这个窗口不复用 Night 场景中的 ReadBook 节点，也不读取当前局 Unlock
## 状态；它只读取 GlobalReadBookArchive 中跨存档累计的典籍进度。

const GLOBAL_ARCHIVE_SCRIPT = preload(
	"res://System/Book/Book/GlobalReadBookArchive.gd"
)
const FIXED_WINDOW_POSITION := Vector2i(50, 66)

@onready var info_label: Label = $MarginContainer/VBoxRoot/BottomRow/InfoLabel
@onready var book_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/BookPanel/BookVBox/BookList
@onready var search_edit: LineEdit = $MarginContainer/VBoxRoot/SearchEdit
@onready var entry_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/EntryPanel/EntryVBox/EntryList
@onready var detail_text: RichTextLabel = $MarginContainer/VBoxRoot/ContentRow/DetailPanel/DetailScroll/DetailText

var global_archive = null

var all_visible_books: Array[BookData] = []
var books: Array[BookData] = []
var readable_entries: Array[BookEntryData] = []
var displayed_entries: Array[BookEntryData] = []

var selected_book: BookData = null
var selected_entry: BookEntryData = null
var global_search_match_count: int = 0
var _info_message_key: String = ""
var _info_message_args: Array = []


func _ready() -> void:
	global_archive = GLOBAL_ARCHIVE_SCRIPT.new()
	title = tr("UI_READ_BOOK_WINDOW_TITLE")
	position = FIXED_WINDOW_POSITION
	hide()

	if not close_requested.is_connected(_on_window_close_requested):
		close_requested.connect(_on_window_close_requested)
	if not book_list.item_selected.is_connected(_on_book_selected):
		book_list.item_selected.connect(_on_book_selected)
	if not entry_list.item_selected.is_connected(_on_entry_selected):
		entry_list.item_selected.connect(_on_entry_selected)
	if not search_edit.text_changed.is_connected(_on_search_text_changed):
		search_edit.text_changed.connect(_on_search_text_changed)

	global_archive.reload()
	_clear_entry_and_detail()
	_set_info_message("UI_READ_BOOK_CHOOSE_BOOK")


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return

	title = tr("UI_READ_BOOK_WINDOW_TITLE")
	var book_id := selected_book.book_id if selected_book != null else ""
	var entry_id := selected_entry.entry_id if selected_entry != null else ""
	_refresh_book_list()
	_rebuild_book_list_for_search(book_id)
	if selected_book != null:
		_refresh_entry_list_for_selected_book()
		if entry_id != "":
			_refresh_entry_list_view(entry_id)
			if selected_entry != null:
				_set_detail_text(_build_entry_text(selected_entry))
	if _info_message_key != "":
		if _info_message_key in [
			"UI_READ_BOOK_SEARCH_SUMMARY_FMT",
			"UI_READ_BOOK_EMPTY_BOOK_FMT",
			"UI_READ_BOOK_UNREAD_COUNT_FMT",
			"UI_READ_BOOK_ENTRY_COUNT_FMT",
		]:
			_update_entry_info_label()
		else:
			_set_info_message(_info_message_key, _info_message_args)


func open_global_archive() -> void:
	if global_archive == null:
		global_archive = GLOBAL_ARCHIVE_SCRIPT.new()
	global_archive.reload()

	if search_edit != null:
		search_edit.set_block_signals(true)
		search_edit.clear()
		search_edit.set_block_signals(false)

	selected_book = null
	selected_entry = null
	_refresh_book_list()
	_rebuild_book_list_for_search()
	_clear_entry_and_detail()
	show()
	grab_focus()
	_focus_book_list_on_open()


func open_window() -> void:
	open_global_archive()


func close_window() -> void:
	hide()
	var parent_window := get_parent().get_window() if get_parent() != null else null
	if parent_window != null and parent_window != self:
		parent_window.grab_focus()


func _on_window_close_requested() -> void:
	close_window()


func _process(_delta: float) -> void:
	if visible and position != FIXED_WINDOW_POSITION:
		position = FIXED_WINDOW_POSITION


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_window()
		get_viewport().set_input_as_handled()


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


func _localized_entry_title(entry: BookEntryData) -> String:
	if entry == null:
		return ""
	var key := "UI_BOOK_ENTRY_TITLE_" + entry.entry_id.to_upper()
	var translated := tr(key)
	return entry.title if translated == key else translated


func _get_search_query() -> String:
	return search_edit.text.strip_edges() if search_edit != null else ""


func _refresh_book_list() -> void:
	var selected_book_id := selected_book.book_id.strip_edges() if selected_book != null else ""
	all_visible_books.clear()

	if global_archive == null:
		return

	for book in BookDB.get_all_books():
		if book == null:
			continue
		if global_archive.is_book_visible_in_readbook(book):
			all_visible_books.append(book)

	var preferred_index := _rebuild_book_list_for_search(selected_book_id)
	if selected_book_id == "":
		return

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
	if book == null or global_archive == null:
		return 0

	var query := _get_search_query()
	if query == "":
		return 0

	var match_count := 0
	for entry in global_archive.get_readable_entries_by_book(book.book_id):
		if entry != null and _entry_matches_search(entry):
			match_count += 1
	return match_count


func _rebuild_book_list_for_search(preferred_book_id: String = "") -> int:
	book_list.clear()
	books.clear()
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

		var new_entry_count = global_archive.get_unread_readable_entry_count_by_book(book.book_id)
		var display_name := _localized_book_name(book)
		if query != "":
			display_name += "  " + tr("UI_READ_BOOK_MATCH_BADGE_FMT") % match_count
		if new_entry_count > 0:
			display_name += "  " + tr("UI_READ_BOOK_NEW_COUNT_BADGE_FMT") % new_entry_count

		books.append(book)
		book_list.add_item(display_name)
		var item_index := book_list.item_count - 1
		if new_entry_count > 0:
			book_list.set_item_custom_fg_color(item_index, Color(1.0, 0.82, 0.32, 1.0))
		if query != "":
			book_list.set_item_tooltip(
				item_index,
				tr("UI_READ_BOOK_MATCH_TOOLTIP_FMT") % match_count
			)
		else:
			book_list.set_item_tooltip(item_index, display_name)

		if preferred_book_id != "" and book.book_id.strip_edges() == preferred_book_id:
			preferred_index = item_index

	if preferred_index >= 0:
		book_list.select(preferred_index)
	return preferred_index


func _entry_matches_search(entry: BookEntryData) -> bool:
	if entry == null:
		return false

	var query := _get_search_query()
	if query == "":
		return true

	var localized_title := _localized_entry_title(entry)
	var entity_id := _get_search_entity_id(entry)

	# 日文：日文名称 + 假名 + Romaji + Romaji 首字母。
	if LocalizedName.is_japanese_locale():
		return LocalizedName.japanese_search_matches(
			localized_title,
			entity_id,
			query
		)

	# 韩文：韩文名称 + 초성 + Romaja + Romaja 首字母。
	if LocalizedName.is_korean_locale():
		return LocalizedName.korean_search_matches(
			localized_title,
			entity_id,
			query
		)

	var clean_query := LocalizedName.normalize_search_text(query)
	if clean_query == "":
		return false

	# 英文：英文名称 + 英文单词首字母。
	if LocalizedName.is_english_locale():
		var english_name := LocalizedName.normalize_search_text(localized_title)
		var english_initials := LocalizedName.english_initials(localized_title)

		return (
			english_name.contains(clean_query)
			or english_initials.begins_with(clean_query)
		)

	# 中文：中文标题 + entry_id / data_id 全拼 + 拼音首字母。
	var title_text := LocalizedName.normalize_search_text(entry.title)

	var entry_id_raw := str(entry.entry_id).to_lower()
	var entry_id_text := LocalizedName.normalize_search_text(entry_id_raw)
	var entry_id_initials := LocalizedName.id_initials(entry_id_raw)

	var data_id_raw := entity_id.to_lower()
	var data_id_text := LocalizedName.normalize_search_text(data_id_raw)
	var data_id_initials := LocalizedName.id_initials(data_id_raw)

	return (
		title_text.contains(clean_query)
		or entry_id_text.contains(clean_query)
		or entry_id_initials.contains(clean_query)
		or data_id_text.contains(clean_query)
		or data_id_initials.contains(clean_query)
	)


func _get_search_entity_id(entry: BookEntryData) -> String:
	if entry == null:
		return ""

	if entry is HerbBookEntryData:
		return str((entry as HerbBookEntryData).herb_id)

	if entry is FormulaBookEntryData:
		return str((entry as FormulaBookEntryData).formula_id)

	if entry is DiseaseBookEntryData:
		return str((entry as DiseaseBookEntryData).disease_id)

	return str(entry.entry_id)
func _refresh_entry_list_for_selected_book() -> void:
	_clear_entry_and_detail()
	if selected_book == null or global_archive == null:
		return

	readable_entries = global_archive.get_readable_entries_by_book(selected_book.book_id)
	_sort_entries_by_index()
	_refresh_entry_list_view()
	_update_entry_info_label()
	entry_list.deselect_all()
	selected_entry = null
	_set_detail_text("")


func _sort_entries_by_index() -> void:
	readable_entries.sort_custom(func(a: BookEntryData, b: BookEntryData) -> bool:
		var a_is_new := _is_unread_readable_entry(a)
		var b_is_new := _is_unread_readable_entry(b)
		if a_is_new != b_is_new:
			return a_is_new
		if a.sort_index != b.sort_index:
			return a.sort_index < b.sort_index
		return a.entry_id.naturalnocasecmp_to(b.entry_id) < 0
	)


func _is_unread_readable_entry(entry: BookEntryData) -> bool:
	if entry == null or global_archive == null:
		return false
	var entry_id := entry.entry_id.strip_edges()
	return (
		entry_id != ""
		and global_archive.can_read_entry(entry_id)
		and not global_archive.is_entry_read(entry_id)
	)


func _get_entry_list_display_name(entry: BookEntryData) -> String:
	var display_name := _localized_entry_title(entry)
	if _is_unread_readable_entry(entry):
		display_name += "  " + tr("UI_READ_BOOK_NEW_BADGE")
	return display_name


func _refresh_entry_list_view(select_entry_id: String = "") -> void:
	entry_list.clear()
	displayed_entries.clear()
	var selected_index := -1

	for entry in readable_entries:
		if not _entry_matches_search(entry):
			continue
		displayed_entries.append(entry)
		_add_entry_list_item(entry)
		if select_entry_id != "" and entry.entry_id.strip_edges() == select_entry_id:
			selected_index = displayed_entries.size() - 1
			selected_entry = entry

	if selected_index >= 0:
		entry_list.select(selected_index)


func _add_entry_list_item(entry: BookEntryData) -> void:
	if entry == null:
		return
	entry_list.add_item(_get_entry_list_display_name(entry))
	var item_index := entry_list.item_count - 1
	if _is_unread_readable_entry(entry):
		entry_list.set_item_custom_fg_color(item_index, Color(1.0, 0.82, 0.32, 1.0))
		entry_list.set_item_tooltip(item_index, tr("UI_READ_BOOK_NEW_ENTRY_TOOLTIP"))


func _update_entry_info_label() -> void:
	if selected_book == null:
		return

	var query := _get_search_query()
	if query != "":
		_set_info_message("UI_READ_BOOK_SEARCH_SUMMARY_FMT", [
			query,
			global_search_match_count,
			_localized_book_name(selected_book),
			displayed_entries.size(),
		])
		return

	if readable_entries.is_empty():
		_set_info_message("UI_READ_BOOK_EMPTY_BOOK_FMT", [_localized_book_name(selected_book)])
		return

	var new_entry_count := 0
	for entry in readable_entries:
		if _is_unread_readable_entry(entry):
			new_entry_count += 1
	if new_entry_count > 0:
		_set_info_message("UI_READ_BOOK_UNREAD_COUNT_FMT", [
			_localized_book_name(selected_book),
			readable_entries.size(),
			new_entry_count,
		])
	else:
		_set_info_message("UI_READ_BOOK_ENTRY_COUNT_FMT", [
			_localized_book_name(selected_book),
			readable_entries.size(),
		])


func _on_search_text_changed(_new_text: String) -> void:
	var preferred_book_id := selected_book.book_id.strip_edges() if selected_book != null else ""
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

	var target_index := preferred_index if preferred_index >= 0 else 0
	book_list.select(target_index)
	selected_book = books[target_index]
	_refresh_entry_list_for_selected_book()


func _clear_entry_and_detail() -> void:
	entry_list.clear()
	readable_entries.clear()
	displayed_entries.clear()
	selected_entry = null
	_set_detail_text("")


func _focus_book_list_on_open() -> void:
	if book_list == null:
		return

	book_list.grab_focus()
	if books.is_empty():
		_set_info_message("UI_READ_BOOK_NO_BOOKS")
		return

	if selected_book == null:
		book_list.select(0)
		selected_book = books[0]
	else:
		_reselect_current_book_in_list()
	_refresh_entry_list_for_selected_book()
	book_list.grab_focus()


func _reselect_current_book_in_list() -> void:
	if selected_book == null:
		return
	var current_book_id := selected_book.book_id.strip_edges()
	for i in range(books.size()):
		if books[i] != null and books[i].book_id.strip_edges() == current_book_id:
			book_list.select(i)
			return


func _on_book_selected(index: int) -> void:
	if index < 0 or index >= books.size():
		return
	selected_book = books[index]
	selected_entry = null
	_refresh_entry_list_for_selected_book()


func _on_entry_selected(index: int) -> void:
	_show_entry_by_index(index)


func _show_entry_by_index(index: int) -> void:
	if index < 0 or index >= displayed_entries.size() or global_archive == null:
		return

	selected_entry = displayed_entries[index]
	if selected_entry == null:
		return

	var entry_id := selected_entry.entry_id.strip_edges()
	if entry_id == "":
		return
	if not global_archive.is_entry_unlocked(entry_id) and not global_archive.is_entry_read(entry_id):
		_set_info_message("UI_READ_BOOK_ENTRY_LOCKED")
		_set_detail_text("")
		return

	var was_unread = not global_archive.is_entry_read(entry_id)
	if was_unread:
		global_archive.mark_entry_as_read(entry_id)

	_set_detail_text(_build_entry_text(selected_entry))
	if not was_unread:
		return

	_refresh_book_list()
	_rebuild_book_list_for_search(selected_book.book_id if selected_book != null else "")
	_refresh_entry_list_titles_keep_selection(entry_id)
	_set_info_message("UI_READ_BOOK_ENTRY_READ")


func _refresh_entry_list_titles_keep_selection(entry_id: String) -> void:
	if selected_book == null or global_archive == null:
		return
	readable_entries = global_archive.get_readable_entries_by_book(selected_book.book_id)
	_sort_entries_by_index()
	_refresh_entry_list_view(entry_id)
	_update_entry_info_label()


func _build_entry_text(entry: BookEntryData) -> String:
	if entry == null:
		return ""
	if entry.detail_text.strip_edges() != "":
		var key := "UI_BOOK_ENTRY_BODY_" + entry.entry_id.to_upper()
		var translated := tr(key)
		return entry.detail_text if translated == key else translated
	return tr("UI_READ_BOOK_NO_CONTENT")


func _set_detail_text(value: String) -> void:
	if detail_text == null:
		return

	var use_horizontal_page := (
		value != ""
		and selected_entry != null
		and LocalizedName.is_horizontal_detail_locale()
		and tr("UI_BOOK_ENTRY_BODY_" + selected_entry.entry_id.to_upper()) !=
			"UI_BOOK_ENTRY_BODY_" + selected_entry.entry_id.to_upper()
	)

	if use_horizontal_page and detail_text.has_method("set_horizontal_source_text"):
		detail_text.call("set_horizontal_source_text", value)
	elif detail_text.has_method("set_source_text"):
		detail_text.call("set_source_text", value)
	else:
		detail_text.text = value
