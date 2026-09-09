extends RichTextLabel
class_name ClassicalVerticalRichTextLabel

# =========================================================
# ClassicalVerticalRichTextLabel.gd
# 古书竖排 RichTextLabel
#
# 作用：
# 1. 把普通横排文本转换成类似古籍的竖排文本
# 2. 支持右起阅读
# 3. 支持横向滚动
# 4. 支持在检查器中调右边距、上边距、字距、列距
# =========================================================


# =========================================================
# 一、排版参数
# =========================================================

# 每两列之间的间隔。
# 默认一个全角空格。
# 想让列距变大，可以改成 "　　"。
# 想让列距变小，可以改成 ""。
@export var column_gap: String = "　"

# 右边距，单位是“全角空格数量”。
# 因为文本是右对齐，所以数值越大，文字整体越往左移动。
@export var right_padding_chars: int = 0

# 上边距，单位是“空行数量”。
# 数值越大，文字整体越往下移动。
@export var top_padding_lines: int = 0

# 字距，单位是“空行数量”。
# 0 = 正常排列。
# 1 = 每个字之间插入一行空白。
# 注意：设置为 1 后，每列实际显示高度会明显变高。
@export var char_spacing_lines: int = 0

# 每列最少字符数，避免窗口尺寸还没稳定时排版太碎。
@export var min_rows_per_column: int = 8

# 每列最大字符数，防止极长文本排成无限高。
@export var max_rows_per_column: int = 2000

# 手动指定每一竖列最多显示多少个字。
# 大于 0 时，超过这个数量就一定换到下一竖列。
# 电脑端建议 20~28。
@export var fixed_rows_per_column: int = 25

# 是否在 ready 时转换场景里已有的 text。
@export var convert_existing_text_on_ready: bool = true

# 是否让竖排文本按古书方式横向展开。
# 需要外层节点是 ScrollContainer，才能左右滚动浏览。
@export var enable_horizontal_browse: bool = true

# 横向展开时，每一列预估占用的宽度倍数。
@export var column_width_multiplier: float = 2.0

# 横向展开时，最小内容宽度，避免短文本太窄。
@export var min_horizontal_content_width: float = 1200.0

# 手动指定每页显示多少竖列。
# 0 = 自动根据 ScrollContainer 可见宽度估算。
# 如果自动分页仍偏宽，可以在检查器里改成 6、7、8。
@export var fixed_columns_per_page: int = 13


# =========================================================
# 二、内部变量
# =========================================================

# 保存原始横排文本。
var _source_text: String = ""

# 保存转换后的竖排文本。
var _display_text: String = ""

# 防止自己设置 text 时触发重复转换。
var _is_applying_text: bool = false

# 避免同一帧重复刷新排版。
var _rebuild_requested: bool = false


# =========================================================
# 三、生命周期
# =========================================================

func _ready() -> void:
	# 不自动滚到底部。
	scroll_following = false

	# 关闭自动换行。
	# 竖排内容需要横向展开，不能被 RichTextLabel 压回当前宽度。
	autowrap_mode = TextServer.AUTOWRAP_OFF

	# 关闭 RichTextLabel 自带竖向滚动。
	# 左右浏览交给外层 ScrollContainer。
	scroll_active = false

	# 古书竖排从右侧开始显示。
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# 尺寸变化时重新排版。
	resized.connect(_request_rebuild)

	# 允许旧代码继续直接设置 text。
	set_process(true)

	# 把节点原本的 text 也转成竖排。
	if convert_existing_text_on_ready and text != "":
		set_source_text(text)


# =========================================================
# 四、外部接口
# =========================================================

# 外部推荐调用这个方法设置文本。
func set_source_text(value: String) -> void:
	_source_text = value
	_request_rebuild()


# 外部分页系统使用：
# 把完整原文按“当前竖排布局”切成多页。
# 每一页已经是 RichTextLabel 可直接显示的竖排矩阵，不会再被二次切字。
func build_source_text_pages(value: String, preferred_columns_per_page: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var clean_text := _normalize_source_text(value)
	var rows_per_column := _estimate_rows_per_column(clean_text.length())
	var columns := _split_text_to_columns(clean_text, rows_per_column)

	if columns.is_empty():
		result.append({
			"text": "",
			"column_count": 1,
		})
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


# 外部分页系统使用：
# 直接显示 build_source_text_pages 生成的某一页。
# 注意这里不能再调用 set_source_text，否则这一页会被再次拆列。
func set_prebuilt_vertical_page(page_data: Dictionary) -> void:
	var page_text := str(page_data.get("text", ""))
	var column_count := int(page_data.get("column_count", 1))

	_source_text = ""
	_display_text = page_text
	_update_horizontal_content_size(column_count)

	_is_applying_text = true
	text = _display_text
	_is_applying_text = false

	_defer_scroll_to_right_edge()
	scroll_to_line(0)


# 外部翻页后调用：把外层 ScrollContainer 移回竖排文本开头。
# 竖排古书从右往左读，所以文本开头在横向滚动条最右侧。
func scroll_to_text_start() -> void:
	call_deferred("_scroll_parent_to_right_edge")
	call_deferred("_scroll_parent_to_right_edge_late")


# 读取原始横排文本，方便调试。
func get_source_text() -> String:
	return _source_text


# =========================================================
# 五、自动监听 text 变化
# =========================================================

func _process(_delta: float) -> void:
	if _is_applying_text:
		return

	# 如果外部直接 label.text = xxx，也自动转换。
	if text != _display_text and text != _source_text:
		_source_text = text
		_request_rebuild()


# =========================================================
# 六、重新排版
# =========================================================

func _request_rebuild() -> void:
	if _rebuild_requested:
		return

	_rebuild_requested = true
	call_deferred("_rebuild_vertical_text")


func _rebuild_vertical_text() -> void:
	_rebuild_requested = false

	var clean_text := _normalize_source_text(_source_text)
	var rows_per_column := _estimate_rows_per_column(clean_text.length())
	var columns := _split_text_to_columns(clean_text, rows_per_column)

	_display_text = _build_vertical_text_from_columns(columns, rows_per_column)

	_update_horizontal_content_size(columns.size())

	_is_applying_text = true
	text = _display_text
	_is_applying_text = false

	_defer_scroll_to_right_edge()

	# 切换条目后，从顶部开始看。
	scroll_to_line(0)


# =========================================================
# 七、横向内容尺寸
# =========================================================

# 根据列数扩大控件宽度。
# 外层如果是 ScrollContainer，就会出现横向滚动区域。
func _update_horizontal_content_size(column_count: int) -> void:
	if not enable_horizontal_browse:
		return

	var font_size := get_theme_font_size("normal_font_size")
	if font_size <= 0:
		font_size = get_theme_default_font_size()
	if font_size <= 0:
		font_size = 16

	var safe_column_count = max(1, column_count)

	# right_padding_chars 也会占宽度，所以这里额外加一点估算宽度。
	var padding_width := float(max(0, right_padding_chars)) * float(font_size)
	var column_width = max(1.0, float(font_size) * column_width_multiplier)
	var content_width = max(
		min_horizontal_content_width,
		float(safe_column_count) * column_width + padding_width
	)

	custom_minimum_size.x = content_width


# 如果外层是 ScrollContainer，文本更新后自动停在最右侧。
# 这样打开详情时，第一列会出现在右边，阅读方向更接近古书。
func _defer_scroll_to_right_edge() -> void:
	call_deferred("_scroll_parent_to_right_edge")


func _scroll_parent_to_right_edge() -> void:
	var parent_node := get_parent()

	if parent_node == null:
		return

	if parent_node is ScrollContainer:
		var scroll_parent := parent_node as ScrollContainer

		# 用一个足够大的值，让 Godot 自动夹到最大滚动位置。
		# 这样比 custom_minimum_size.x 更稳，避免尺寸尚未刷新时停在正文中段。
		scroll_parent.scroll_horizontal = 100000000
		scroll_parent.scroll_vertical = 0


func _scroll_parent_to_right_edge_late() -> void:
	# 等一帧，让 ScrollContainer 和 RichTextLabel 的尺寸先完成更新。
	await get_tree().process_frame
	_scroll_parent_to_right_edge()


# =========================================================
# 八、文本预处理
# =========================================================

func _normalize_source_text(value: String) -> String:
	var result := ""
	var normalized := value.replace("\r\n", "\n").replace("\r", "\n")

	for i in normalized.length():
		var ch := normalized.substr(i, 1)

		# 去掉普通空格和 Tab，避免竖排出现大量松散空白。
		if ch == " " or ch == "\t":
			continue

		# 保留换行。
		# 后续排版会把换行当成“强制换到下一竖列”。
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

	# 优先使用外层 ScrollContainer 的可见高度。
	# 因为 RichTextLabel 自己的 size.y 有时还没刷新，直接用它会算错。
	var visible_height := size.y
	var parent_node := get_parent()
	if parent_node is ScrollContainer:
		visible_height = (parent_node as ScrollContainer).size.y

	# 如果节点还没有完成布局，不强行按 0 高度计算。
	if visible_height <= 0.0:
		if fixed_rows_per_column > 0:
			return clamp(fixed_rows_per_column, min_rows_per_column, max_rows_per_column)
		return min_rows_per_column

	# 可见行数要扣掉上边距。
	# 字距 char_spacing_lines > 0 时，每个字之间还会额外吃掉空行。
	var visible_lines = int(floor(visible_height / row_height)) - max(0, top_padding_lines)
	visible_lines = max(1, visible_lines)

	var spacing = max(0, char_spacing_lines)
	var max_fit_rows = visible_lines
	if spacing > 0:
		# rows 个字实际占用：rows + (rows - 1) * spacing。
		# 反推当前高度最多能放多少个字。
		max_fit_rows = int(floor(float(visible_lines + spacing) / float(spacing + 1)))

	# 手动指定每列字数时，也不能超过真实可见高度。
	if fixed_rows_per_column > 0:
		return clamp(min(fixed_rows_per_column, max_fit_rows), min_rows_per_column, max_rows_per_column)

	return clamp(max_fit_rows, min_rows_per_column, max_rows_per_column)


func _estimate_columns_per_page(preferred_columns_per_page: int = 0) -> int:
	# 函数参数优先级最高，方便不同页面单独控制。
	if preferred_columns_per_page > 0:
		return max(1, preferred_columns_per_page)

	# 检查器里的固定值优先于自动估算。
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

	# 节点还没完成布局时给一个保守值。
	if visible_width <= 0.0:
		return 6

	var column_width = max(1.0, float(font_size) * column_width_multiplier)
	var result := int(floor(visible_width / column_width))

	# 减 1 留出列距和边框余量，避免刚好超出后被裁。
	return max(1, result - 1)


# =========================================================
# 九、切分竖列
# =========================================================

# 把原文切成竖列。
# 规则：
# 1. 每列最多 rows_per_column 个字。
# 2. 遇到原文换行符，立即结束当前列，换到下一竖列。
# 3. 连续换行会生成空列，作为段落间距。
func _split_text_to_columns(value: String, rows_per_column: int) -> Array[String]:
	var columns: Array[String] = []
	var current_column := ""

	for i in value.length():
		var ch := value.substr(i, 1)

		# 原文换行：强制换到下一竖列。
		if ch == "\n":
			columns.append(current_column)
			current_column = ""
			continue

		current_column += ch

		# 当前列达到最大字数：自动换到下一竖列。
		if current_column.length() >= rows_per_column:
			columns.append(current_column)
			current_column = ""

	if current_column != "":
		columns.append(current_column)

	# 避免结尾全是空列。
	while columns.size() > 0 and columns[columns.size() - 1] == "":
		columns.remove_at(columns.size() - 1)

	return columns


func _build_vertical_text(value: String, rows_per_column: int) -> String:
	var columns := _split_text_to_columns(value, rows_per_column)
	return _build_vertical_text_from_columns(columns, rows_per_column)


# =========================================================
# 十、生成竖排文本矩阵
# =========================================================

# 把竖列数组转换成 RichTextLabel 能显示的横向文本矩阵。
# 反向拼接列，让第一列显示在最右边。
func _build_vertical_text_from_columns(columns: Array[String], rows_per_column: int) -> String:
	if columns.is_empty():
		return ""

	var lines: Array[String] = []

	# ---------------------------------------------------------
	# 上边距：
	# 在正文前插入空行，让文字整体往下移动。
	# ---------------------------------------------------------
	for i in range(max(0, top_padding_lines)):
		lines.append("")

	# ---------------------------------------------------------
	# 右边距：
	# 每一行末尾追加全角空格。
	# 因为 RichTextLabel 是右对齐，所以末尾空格会把文字整体往左推。
	# ---------------------------------------------------------
	var right_padding := ""
	for i in range(max(0, right_padding_chars)):
		right_padding += "　"

	# ---------------------------------------------------------
	# 正文：
	# 每一行代表所有竖列在同一高度上的字符。
	# ---------------------------------------------------------
	for row in range(rows_per_column):
		var line_parts: PackedStringArray = PackedStringArray()

		for column_index in range(columns.size() - 1, -1, -1):
			var column_text := columns[column_index]

			if row < column_text.length():
				line_parts.append(column_text.substr(row, 1))
			else:
				line_parts.append("　")

		lines.append(column_gap.join(line_parts) + right_padding)

		# -----------------------------------------------------
		# 字距：
		# 在每一行后插入空行。
		# 这样同一竖列的上下两个字距离会变大。
		# -----------------------------------------------------
		if row < rows_per_column - 1:
			for i in range(max(0, char_spacing_lines)):
				lines.append("")

	return "\n".join(PackedStringArray(lines))


# =========================================================
# 十一、标点竖排转换
# =========================================================

# 把横排标点替换成更适合竖排显示的标点。
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
