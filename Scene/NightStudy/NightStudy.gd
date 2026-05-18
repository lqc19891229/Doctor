extends Control
class_name NightStudy

signal study_finished

# =========================
# 节点引用
# =========================

# 顶部天数显示
@onready var day_label: Label = $MarginContainer/VBoxRoot/TopBar/DayLabel

# 顶部心得显示
# 说明：
# - ThoughtsPoint 是 NightStudy 场景 TopBar 下的 Label。
# - 先用固定路径查找；如果路径变化，再用 find_child 兜底。
@onready var thoughts_point_label: Label = _get_thoughts_point_label()

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

# 记录上一次显示的心得数量。
# 用途：每帧检测数值变化，避免 Label 没有及时刷新。
var last_displayed_experience_points: int = -999


func _ready() -> void:
	# 进入 NightStudy 后，刷新顶部天数与心得显示
	_update_day_label()
	_update_thoughts_point_ui()

	# 绑定按钮与列表事件
	read_button.pressed.connect(_on_read_button_pressed)
	next_day_button.pressed.connect(_on_next_day_button_pressed)
	book_list.item_selected.connect(_on_book_selected)
	entry_list.item_selected.connect(_on_entry_selected)

	_refresh_book_list()
	_clear_entry_and_detail()
	read_button.disabled = true
	_update_thoughts_point_ui()
	info_label.text = "请选择今晚要阅读的医书。当前心得：%d" % Unlock.get_experience_points()


func _process(_delta: float) -> void:
	# 每帧同步一次心得显示。
	# 这样无论心得是在 Clinic、读档、夜读消耗、或其他地方变化，TopBar 都会自动更新。
	_sync_thoughts_point_if_changed()


# =========================
# 刷新顶部天数显示
# =========================

func _update_day_label() -> void:
	# 如果场景中没有 DayLabel，直接跳过，避免报错
	if day_label == null:
		return

	# 天数统一从 GameTimeManager 读取
	day_label.text = GameTime.get_day_text()


# =========================
# 获取顶部心得 Label
# =========================

func _get_thoughts_point_label() -> Label:
	# 优先使用你当前 NightStudy 场景中的固定路径。
	var label := get_node_or_null("MarginContainer/VBoxRoot/TopBar/ThoughtsPoint") as Label
	if label != null:
		return label

	# 兜底：如果以后节点层级变化，只要名字还叫 ThoughtsPoint，也能找到。
	return find_child("ThoughtsPoint", true, false) as Label


# =========================
# 刷新顶部心得显示
# =========================

func _update_thoughts_point_ui() -> void:
	# 如果 onready 时没找到，运行时再尝试找一次。
	if thoughts_point_label == null:
		thoughts_point_label = _get_thoughts_point_label()

	if thoughts_point_label == null:
		print("NightStudy 没找到心得 Label：MarginContainer/VBoxRoot/TopBar/ThoughtsPoint")
		return

	# 强制显示，避免 Label 被误隐藏。
	thoughts_point_label.visible = true
	thoughts_point_label.show()

	# 给一个最小宽高，避免被 HBoxContainer / TopBar 压到看不见。
	thoughts_point_label.custom_minimum_size = Vector2(120, 24)

	# 右对齐，和 Clinic 顶部显示保持一致。
	thoughts_point_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	thoughts_point_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# UnlockManager 中的 experience_points 就是“心得”。
	var current_points := Unlock.get_experience_points()
	thoughts_point_label.text = "心得：%d" % current_points
	last_displayed_experience_points = current_points


# =========================
# 心得变化时自动刷新
# =========================

func _sync_thoughts_point_if_changed() -> void:
	var current_points := Unlock.get_experience_points()

	# Label 还没绑定，或者心得数量变化时，立即刷新显示。
	if thoughts_point_label == null or current_points != last_displayed_experience_points:
		_update_thoughts_point_ui()


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
	_update_thoughts_point_ui()
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

		info_label.text = "《%s》 进度：%d/%d，已解锁药材：%d，下一味：%s\n当前心得：%d" % [
			selected_book.book_name, days, total, unlocked_count, next_herb, Unlock.get_experience_points()
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

	info_label.text = "《%s》共有 %d 个可阅读条目。\n当前心得：%d" % [
		selected_book.book_name, readable_entries.size(), Unlock.get_experience_points()
	]

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

	# 药材书：消耗 1 点心得，推进整本书进度。
	# 规则：1 点心得解锁 1 味药材。
	if selected_book.is_herb_book():
		var herb_unlock_order := selected_book.get_herb_unlock_order()
		var days := Unlock.get_book_read_days(selected_book.book_id)

		# 已经读完时不消耗心得。
		if days >= herb_unlock_order.size():
			info_label.text = "《%s》已经全部读完。\n当前心得：%d" % [
				selected_book.book_name, Unlock.get_experience_points()
			]
			return

		# 心得不足时不能阅读新内容。
		if not Unlock.consume_experience_point():
			_update_thoughts_point_ui()
			info_label.text = "心得不足。白天开方获得满分甲等评价后，可获得 1 点心得。"
			return

		_update_thoughts_point_ui()

		Unlock.read_book_by_day(selected_book)

		# 消耗心得后立即存档，避免退出或切场景时丢失。
		if SaveManager != null and SaveManager.has_method("save_game"):
			SaveManager.save_game()

		_refresh_entry_list_for_selected_book()
		_update_thoughts_point_ui()
		info_label.text += "\n消耗心得：-1，当前心得：%d" % Unlock.get_experience_points()

		# 刷新后默认显示第一条已解锁药材正文。
		if readable_entries.size() > 0:
			entry_list.select(0)
			selected_entry = readable_entries[0]
			detail_text.text = _build_entry_text(selected_entry)
		else:
			detail_text.text = ""

		return

	# 普通书：阅读当前条目。
	if selected_entry == null:
		return

	# 已读条目只是回看，不消耗心得。
	if Unlock.is_entry_read(selected_entry.entry_id):
		_update_thoughts_point_ui()
		detail_text.text = _build_entry_text(selected_entry)
		info_label.text = "该条目已读，可直接回看。\n当前心得：%d" % Unlock.get_experience_points()
		return

	# 未读条目需要消耗 1 点心得。
	if not Unlock.consume_experience_point():
		_update_thoughts_point_ui()
		info_label.text = "心得不足。白天开方获得满分甲等评价后，可获得 1 点心得。"
		return

	_update_thoughts_point_ui()

	var current_entry_id := selected_entry.entry_id

	Unlock.read_entry(selected_entry)

	# 消耗心得后立即存档，避免退出或切场景时丢失。
	if SaveManager != null and SaveManager.has_method("save_game"):
		SaveManager.save_game()

	# 刷新列表，让当前条目变成 [已读]。
	_refresh_entry_list_for_selected_book()
	_update_thoughts_point_ui()
	info_label.text += "\n消耗心得：-1，当前心得：%d" % Unlock.get_experience_points()

	# 刷新后重新选中刚刚阅读的条目，并显示正文。
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
