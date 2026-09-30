extends RichTextLabel
class_name ClassicalVerticalRichTextLabel

# 古籍竖排 RichTextLabel
# 中文、日文保持竖排；韩文按英文一样使用横排。

const DEFAULT_FONT_PATH := "res://Assets/Fonts/SourceHanSerifSC-Regular.otf"
const KOREAN_FONT_PATH := "res://Assets/Fonts/SourceHanSerifKR-Regular.otf"

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
var _default_font: Font
var _korean_font: Font
var _locale_driven_source: bool = false


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return

	# 游戏运行时切换语言后，重新选择字体。
	_apply_locale_font()

	# 直接通过 set_source_text() 设置的文本可以在这里立即重排。
	# 预构建分页文本由上层窗口刷新页面，避免把已构建页面清空。
	if not _source_text.is_empty():
		if _locale_driven_source:
			_horizontal_source = _is_korean_locale()
		_request_rebuild()


func _ready() -> void:
	_cache_fonts()
	_apply_locale_font()

	scroll_following = false
	autowrap_mode = TextServer.AUTOWRAP_OFF
	scroll_active = false
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	resized.connect(_request_rebuild)
	set_process(true)

	if convert_existing_text_on_ready and text != "":
		set_source_text(text)


func _cache_fonts() -> void:
	# 保存场景中原本的字体，确保非韩文环境继续使用原字体。
	_default_font = get_theme_font("normal_font")
	if _default_font == null:
		_default_font = load(DEFAULT_FONT_PATH) as Font

	# 使用 load 而不是 preload：即使用户尚未复制韩文字体，游戏也不会因为资源不存在而无法启动。
	_korean_font = load(KOREAN_FONT_PATH) as Font
	if _korean_font == null:
		push_warning(
			"韩文字体不存在：%s；韩文环境将暂时使用原字体。" % KOREAN_FONT_PATH
		)


func _is_korean_locale() -> bool:
	var locale := TranslationServer.get_locale().to_lower().replace("-", "_")
	return locale.begins_with("ko")


func _apply_locale_font() -> void:
	if _default_font == null:
		_default_font = get_theme_font("normal_font")

	var target_font: Font = _default_font
	if _is_korean_locale() and _korean_font != null:
		target_font = _korean_font

	if target_font != null:
		add_theme_font_override("normal_font", target_font)


func set_source_text(value: String) -> void:
	# 普通文本入口由当前语言决定方向：韩文横排，中文/日文竖排。
	_locale_driven_source = true
	_horizontal_source = _is_korean_locale()
	_source_text = value
	_request_rebuild()


func set_horizontal_source_text(value: String) -> void:
	_locale_driven_source = false
	_horizontal_source = true
	_source_text = value
	_request_rebuild()


func build_source_text_pages(value: String, preferred_columns_per_page: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	# 韩文和英文一样使用横排文本，不再按竖排列切分页。
	if _is_korean_locale():
		result.append({
			"text": _normalize_horizontal_source_text(value),
			"column_count": 1,
			"horizontal": true,
		})
		return result

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
	var is_horizontal_page := bool(page_data.get("horizontal", _is_korean_locale()))

	_locale_driven_source = true
	_horizontal_source = is_horizontal_page
	bbcode_enabled = false

	_source_text = ""
	_display_text = page_text

	if _horizontal_source:
		fit_content = true
		autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		custom_minimum_size.x = 0.0
	else:
		fit_content = false
		autowrap_mode = TextServer.AUTOWRAP_OFF
		horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_update_horizontal_content_size(column_count)

	_is_applying_text = true
	text = _display_text
	_is_applying_text = false

	if _horizontal_source:
		call_deferred("_scroll_parent_to_left_edge")
	else:
		_defer_scroll_to_right_edge()
	scroll_to_line(0)


func scroll_to_text_start() -> void:
	if _horizontal_source:
		call_deferred("_scroll_parent_to_left_edge")
		return

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
	bbcode_enabled = false

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


func _normalize_horizontal_source_text(value: String) -> String:
	return value.replace("\r\n", "\n").replace("\r", "\n")


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
