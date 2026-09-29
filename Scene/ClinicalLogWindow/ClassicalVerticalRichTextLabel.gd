extends RichTextLabel
class_name ClassicalVerticalRichTextLabel

# 古籍竖排 RichTextLabel
# 中文继续使用原来的纯文本矩阵。
# 日文 / 韩文使用 BBCode table 固定“字格”，避免比例字宽导致竖列左右漂移。

@export var column_gap: String = "　"
@export var right_padding_chars: int = 0
@export var top_padding_lines: int = 0
@export var char_spacing_lines: int = 0
@export var min_rows_per_column: int = 8
@export var max_rows_per_column: int = 2000
@export var fixed_rows_per_column: int = 25
@export var convert_existing_text_on_ready: bool = true
@export var enable_horizontal_browse: bool = true
@export var column_width_multiplier: float = 2.0
@export var min_horizontal_content_width: float = 1200.0
@export var fixed_columns_per_page: int = 13

var _source_text: String = ""
var _horizontal_source: bool = false
var _display_text: String = ""
var _is_applying_text: bool = false
var _rebuild_requested: bool = false


func _ready() -> void:
	scroll_following = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	scroll_active = false
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	resized.connect(_request_rebuild)
	set_process(true)

	if convert_existing_text_on_ready and text != "":
		set_source_text(text)


func set_source_text(value: String) -> void:
	_horizontal_source = false
	_source_text = value
	_request_rebuild()


func set_horizontal_source_text(value: String) -> void:
	_horizontal_source = true
	_source_text = value
	_request_rebuild()


func build_source_text_pages(value: String, preferred_columns_per_page: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var clean_text := _normalize_source_text(value)
	var rows_per_column := _estimate_rows_per_column(clean_text.length())
	var columns := _split_text_to_columns(clean_text, rows_per_column)

	if columns.is_empty():
		result.append({"text": "", "column_count": 1})
		return result

	var columns_per_page := _estimate_columns_per_page(preferred_columns_per_page)

	for start_index in range(0, columns.size(), columns_per_page):
		var page_columns: Array[String] = []
		var end_index = min(start_index + columns_per_page, columns.size())

		for column_index in range(start_index, end_index):
			page_columns.append(columns[column_index])

		result.append({
			"text": _build_vertical_text_from_columns(page_columns, rows_per_column),
			"column_count": page_columns.size(),
		})

	return result


func set_prebuilt_vertical_page(page_data: Dictionary) -> void:
	var page_text := str(page_data.get("text", ""))
	var column_count := int(page_data.get("column_count", 1))

	_horizontal_source = false
	fit_content = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bbcode_enabled = _uses_fixed_cell_grid()

	_source_text = ""
	_display_text = page_text
	_update_horizontal_content_size(column_count)

	_is_applying_text = true
	text = _display_text
	_is_applying_text = false

	_defer_scroll_to_right_edge()
	scroll_to_line(0)


func scroll_to_text_start() -> void:
	call_deferred("_scroll_parent_to_right_edge")
	call_deferred("_scroll_parent_to_right_edge_late")


func get_source_text() -> String:
	return _source_text


func _process(_delta: float) -> void:
	if _is_applying_text:
		return

	if text != _display_text and text != _source_text:
		_source_text = text
		_request_rebuild()


func _request_rebuild() -> void:
	if _rebuild_requested:
		return
	_rebuild_requested = true
	call_deferred("_rebuild_vertical_text")


func _rebuild_vertical_text() -> void:
	_rebuild_requested = false

	if _horizontal_source:
		bbcode_enabled = false
		_display_text = _source_text.replace("\r\n", "\n").replace("\r", "\n")
		custom_minimum_size.x = 0.0
		fit_content = true
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

		_is_applying_text = true
		text = _display_text
		_is_applying_text = false

		call_deferred("_scroll_parent_to_left_edge")
		return

	fit_content = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bbcode_enabled = _uses_fixed_cell_grid()

	var clean_text := _normalize_source_text(_source_text)
	var rows_per_column := _estimate_rows_per_column(clean_text.length())
	var columns := _split_text_to_columns(clean_text, rows_per_column)

	_display_text = _build_vertical_text_from_columns(columns, rows_per_column)
	_update_horizontal_content_size(columns.size())

	_is_applying_text = true
	text = _display_text
	_is_applying_text = false

	_defer_scroll_to_right_edge()
	scroll_to_line(0)


func _uses_fixed_cell_grid() -> bool:
	var locale := TranslationServer.get_locale().to_lower().replace("-", "_")
	# 韩文字形宽度差异最明显；日文假名/汉字混排也统一走固定字格。
	return locale.begins_with("ko") or locale.begins_with("ja")


func _scroll_parent_to_left_edge() -> void:
	var parent_node := get_parent()
	if parent_node is ScrollContainer:
		var scroll_parent := parent_node as ScrollContainer
		scroll_parent.scroll_horizontal = 0
		scroll_parent.scroll_vertical = 0


func _update_horizontal_content_size(column_count: int) -> void:
	if not enable_horizontal_browse:
		return

	var font_size := get_theme_font_size("normal_font_size")
	if font_size <= 0:
		font_size = get_theme_default_font_size()
	if font_size <= 0:
		font_size = 16

	var safe_column_count = max(1, column_count)
	var padding_width := float(max(0, right_padding_chars)) * float(font_size)
	var column_width = max(1.0, float(font_size) * column_width_multiplier)
	var content_width = max(
		min_horizontal_content_width,
		float(safe_column_count) * column_width + padding_width
	)

	custom_minimum_size.x = content_width


func _defer_scroll_to_right_edge() -> void:
	call_deferred("_scroll_parent_to_right_edge")


func _scroll_parent_to_right_edge() -> void:
	var parent_node := get_parent()
	if parent_node is ScrollContainer:
		var scroll_parent := parent_node as ScrollContainer
		scroll_parent.scroll_horizontal = 100000000
		scroll_parent.scroll_vertical = 0


func _scroll_parent_to_right_edge_late() -> void:
	await get_tree().process_frame
	_scroll_parent_to_right_edge()


func _normalize_source_text(value: String) -> String:
	var result := ""
	var normalized := value.replace("\r\n", "\n").replace("\r", "\n")

	for i in normalized.length():
		var ch := normalized.substr(i, 1)

		if ch == " " or ch == "\t":
			continue

		if ch == "\n":
			result += "\n"
			continue

		result += _to_vertical_char(ch)

	return result


func _estimate_rows_per_column(_char_count: int) -> int:
	var font_size := get_theme_font_size("normal_font_size")
	if font_size <= 0:
		font_size = get_theme_default_font_size()
	if font_size <= 0:
		font_size = 16

	var line_spacing := get_theme_constant("line_separation")
	var row_height = max(1.0, float(font_size + line_spacing))

	var visible_height := size.y
	var parent_node := get_parent()
	if parent_node is ScrollContainer:
		visible_height = (parent_node as ScrollContainer).size.y

	if visible_height <= 0.0:
		if fixed_rows_per_column > 0:
			return clamp(fixed_rows_per_column, min_rows_per_column, max_rows_per_column)
		return min_rows_per_column

	var visible_lines = int(floor(visible_height / row_height)) - max(0, top_padding_lines)
	visible_lines = max(1, visible_lines)

	var spacing = max(0, char_spacing_lines)
	var max_fit_rows = visible_lines

	if spacing > 0:
		max_fit_rows = int(floor(float(visible_lines + spacing) / float(spacing + 1)))

	if fixed_rows_per_column > 0:
		return clamp(
			min(fixed_rows_per_column, max_fit_rows),
			min_rows_per_column,
			max_rows_per_column
		)

	return clamp(max_fit_rows, min_rows_per_column, max_rows_per_column)


func _estimate_columns_per_page(preferred_columns_per_page: int = 0) -> int:
	if preferred_columns_per_page > 0:
		return max(1, preferred_columns_per_page)

	if fixed_columns_per_page > 0:
		return max(1, fixed_columns_per_page)

	var font_size := get_theme_font_size("normal_font_size")
	if font_size <= 0:
		font_size = get_theme_default_font_size()
	if font_size <= 0:
		font_size = 16

	var visible_width := size.x
	var parent_node := get_parent()
	if parent_node is ScrollContainer:
		visible_width = (parent_node as ScrollContainer).size.x

	if visible_width <= 0.0:
		return 6

	var column_width = max(1.0, float(font_size) * column_width_multiplier)
	var result := int(floor(visible_width / column_width))
	return max(1, result - 1)


func _split_text_to_columns(value: String, rows_per_column: int) -> Array[String]:
	var columns: Array[String] = []
	var current_column := ""

	for i in value.length():
		var ch := value.substr(i, 1)

		if ch == "\n":
			columns.append(current_column)
			current_column = ""
			continue

		current_column += ch

		if current_column.length() >= rows_per_column:
			columns.append(current_column)
			current_column = ""

	if current_column != "":
		columns.append(current_column)

	while columns.size() > 0 and columns[columns.size() - 1] == "":
		columns.remove_at(columns.size() - 1)

	return columns


func _build_vertical_text_from_columns(columns: Array[String], rows_per_column: int) -> String:
	if columns.is_empty():
		return ""

	if _uses_fixed_cell_grid():
		return _build_fixed_cell_vertical_table(columns, rows_per_column)

	return _build_plain_vertical_matrix(columns, rows_per_column)


func _build_plain_vertical_matrix(columns: Array[String], rows_per_column: int) -> String:
	var lines: Array[String] = []

	for _i in range(max(0, top_padding_lines)):
		lines.append("")

	var right_padding := ""
	for _i in range(max(0, right_padding_chars)):
		right_padding += "　"

	for row in range(rows_per_column):
		var line_parts := PackedStringArray()

		for column_index in range(columns.size() - 1, -1, -1):
			var column_text := columns[column_index]

			if row < column_text.length():
				line_parts.append(column_text.substr(row, 1))
			else:
				line_parts.append("　")

		lines.append(column_gap.join(line_parts) + right_padding)

		if row < rows_per_column - 1:
			for _i in range(max(0, char_spacing_lines)):
				lines.append("")

	return "\n".join(PackedStringArray(lines))


func _build_fixed_cell_vertical_table(columns: Array[String], rows_per_column: int) -> String:
	# 日文 / 韩文使用固定列数的 table。
	# 关键点：
	# 1. 不再把“列间距”做成额外 table 列，否则短文本会被拉得非常散。
	# 2. 即使当前页只有少量正文列，也仍然按 fixed_columns_per_page 建表，
	#    让短页和长页拥有相同的列宽，不会出现韩文第二页突然被撑宽。
	# 3. 空列补在左边，正文仍从右往左阅读。
	var visual_columns: int = columns.size()
	var target_columns: int = maxi(visual_columns, fixed_columns_per_page)
	target_columns = maxi(1, target_columns)

	var out := PackedStringArray()
	out.append("[right][table=%d]" % target_columns)

	for _pad_row in range(maxi(0, top_padding_lines)):
		for _cell in range(target_columns):
			out.append("[cell][center]　[/center][/cell]")

	for row in range(rows_per_column):
		var blank_left_columns: int = maxi(0, target_columns - visual_columns)

		# 左侧先补空列，保证实际正文始终贴在右侧。
		for _blank in range(blank_left_columns):
			out.append("[cell][center]　[/center][/cell]")

		# 正文列反向写入，让第一列位于最右侧。
		for column_index in range(columns.size() - 1, -1, -1):
			var column_text: String = columns[column_index]
			var ch: String = "　"
			if row < column_text.length():
				ch = column_text.substr(row, 1)

			out.append("[cell][center]%s[/center][/cell]" % ch)

		if row < rows_per_column - 1:
			for _spacing_row in range(maxi(0, char_spacing_lines)):
				for _cell in range(target_columns):
					out.append("[cell][center]　[/center][/cell]")

	out.append("[/table][/right]")
	return "".join(out)


func _to_vertical_char(ch: String) -> String:
	match ch:
		"(":
			return "︵"
		")":
			return "︶"
		"（":
			return "︵"
		"）":
			return "︶"
		"[":
			return "﹇"
		"]":
			return "﹈"
		"【":
			return "︻"
		"】":
			return "︼"
		"《":
			return "︽"
		"》":
			return "︾"
		"，":
			return "︐"
		"、":
			return "︑"
		"。":
			return "︒"
		"；":
			return "︔"
		"：":
			return "︓"
		"︰":
			return "︓"
		"？":
			return "︖"
		"！":
			return "︕"
		"﹗":
			return "︕"
		"“":
			return "﹁"
		"”":
			return "﹂"
		"「":
			return "﹁"
		"」":
			return "﹂"
		"『":
			return "﹃"
		"』":
			return "﹄"
		"‧":
			return "・"
		"•":
			return "・"
		"·":
			return "・"
		"+":
			return "＋"
		"*":
			return ""
		_:
			return ch
