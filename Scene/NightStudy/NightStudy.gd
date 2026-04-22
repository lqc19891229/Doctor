extends Control
class_name NightStudy

signal study_finished

# =========================
# 节点引用
# =========================

@onready var info_label: Label = $MarginContainer/VBoxRoot/InfoLabel
@onready var read_button: Button = $MarginContainer/VBoxRoot/ButtonRow/ReadButton
@onready var next_day_button: Button = $MarginContainer/VBoxRoot/ButtonRow/NextDayButton

# 左侧：书籍列表
@onready var book_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/BookPanel/BookVBox/BookList

# 中间：条目列表
@onready var entry_list: ItemList = $MarginContainer/VBoxRoot/ContentRow/EntryPanel/EntryVBox/EntryList

# 右侧：正文窗口
@onready var detail_text: RichTextLabel = $MarginContainer/VBoxRoot/ContentRow/DetailPanel/DetailVBox/DetailText


# =========================
# 运行时数据
# =========================

var books: Array[BookData] = []
var readable_entries: Array[BookEntryData] = []

var selected_book: BookData = null
var selected_entry: BookEntryData = null


func _ready() -> void:
	# 绑定按钮与列表事件
	read_button.pressed.connect(_on_read_button_pressed)
	next_day_button.pressed.connect(_on_next_day_button_pressed)
	book_list.item_selected.connect(_on_book_selected)
	entry_list.item_selected.connect(_on_entry_selected)

	_refresh_book_list()
	_clear_entry_and_detail()
	read_button.disabled = true
	info_label.text = "请选择今晚要阅读的医书。"


# =========================
# 刷新书籍列表
# =========================

func _refresh_book_list() -> void:
	book_list.clear()
	books = BookDB.get_all_books()

	for book in books:
		if book == null:
			continue
		book_list.add_item(book.book_name)


# =========================
# 清空条目与正文
# =========================

func _clear_entry_and_detail() -> void:
	entry_list.clear()
	readable_entries.clear()
	selected_entry = null
	detail_text.text = ""


# =========================
# 刷新当前书的条目列表
# =========================

func _refresh_entry_list_for_selected_book() -> void:
	_clear_entry_and_detail()

	if selected_book == null:
		return

	# -------------------------
	# 1) 药材书：神农百草经
	# 规则：
	# - 已解锁药材条目显示在列表中
	# - 选中后直接显示正文
	# - 点击“阅读本书”推进下一天，解锁下一味药材
	# -------------------------
	if selected_book.is_herb_book():
		var herb_entries := BookEntryDB.get_entries_by_book(selected_book.book_id)

		for entry in herb_entries:
			if entry == null:
				continue

			# 药材条目只要已解锁即可显示
			if Unlock.is_entry_visible(entry.entry_id):
				readable_entries.append(entry)
				entry_list.add_item(entry.title)

		var herb_unlock_order := selected_book.get_herb_unlock_order()
		var total := herb_unlock_order.size()
		var days := Unlock.get_book_read_days(selected_book.book_id)
		var unlocked_count = min(days, total)

		var next_herb := "无"
		if days < total:
			next_herb = herb_unlock_order[days]

		info_label.text = "《%s》 进度：%d/%d，已解锁药材：%d，下一味：%s" % [
			selected_book.book_name, days, total, unlocked_count, next_herb
		]

		read_button.text = "阅读本书"
		read_button.disabled = false

		# 默认选中第一条已解锁药材，并直接显示正文
		if readable_entries.size() > 0:
			entry_list.select(0)
			selected_entry = readable_entries[0]
			detail_text.text = _build_entry_text(selected_entry)
		else:
			detail_text.text = ""

		return

	# -------------------------
	# 2) 普通医书：如伤寒论
	# 规则：
	# - 可显示条目出现在列表中（未读可阅读 / 已读可回看）
	# - 未读条目不显示正文
	# - 阅读后显示正文，并标记[已读]
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
		detail_text.text = ""
		return

	info_label.text = "《%s》共有 %d 个可阅读条目。" % [selected_book.book_name, readable_entries.size()]

	# 默认选中第一条
	entry_list.select(0)
	selected_entry = readable_entries[0]

	# 普通书未读前不显示正文
	if Unlock.is_entry_read(selected_entry.entry_id):
		detail_text.text = _build_entry_text(selected_entry)
	else:
		detail_text.text = "该条目尚未阅读，阅读后显示正文内容。"


# =========================
# 拼装正文文本
# 现在只显示 DetailText，不再显示
# 标题 / 类型 / 条目ID / 所属书籍 / 药材ID 等调试信息
# =========================

func _build_entry_text(entry: BookEntryData) -> String:
	# 判空保护
	if entry == null:
		return ""

	# 只返回正文内容
	if entry.detail_text.strip_edges() != "":
		return entry.detail_text

	# 没有正文时给占位提示
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

	# 药材书：条目出现在列表中就直接显示正文
	if selected_book != null and selected_book.is_herb_book():
		detail_text.text = _build_entry_text(selected_entry)
		return

	# 普通书：未读前不显示正文，已读后显示正文
	if Unlock.is_entry_read(selected_entry.entry_id):
		detail_text.text = _build_entry_text(selected_entry)
	else:
		detail_text.text = "该条目尚未阅读，阅读后显示正文内容。"


# =========================
# 点击阅读
# =========================

func _on_read_button_pressed() -> void:
	if selected_book == null:
		return

	# 药材书：推进整本书进度
	if selected_book.is_herb_book():
		Unlock.read_book_by_day(selected_book)
		_refresh_entry_list_for_selected_book()

		# 刷新后默认显示第一条已解锁药材正文
		if readable_entries.size() > 0:
			entry_list.select(0)
			selected_entry = readable_entries[0]
			detail_text.text = _build_entry_text(selected_entry)
		else:
			detail_text.text = ""

		return

	# 普通书：阅读当前条目
	if selected_entry == null:
		return

	var current_entry_id := selected_entry.entry_id

	Unlock.read_entry(selected_entry)

	# 刷新列表，让当前条目变成 [已读]
	_refresh_entry_list_for_selected_book()

	# 刷新后重新选中刚刚阅读的条目，并显示正文
	for i in range(readable_entries.size()):
		if readable_entries[i].entry_id == current_entry_id:
			selected_entry = readable_entries[i]
			entry_list.select(i)
			detail_text.text = _build_entry_text(selected_entry)
			break


# =========================
# 进入下一天
# =========================

func _on_next_day_button_pressed() -> void:
	study_finished.emit()
