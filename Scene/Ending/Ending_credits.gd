extends Control

## Godot 4.x
## 不使用 AnimationPlayer。
## 整张古书长卷从左向右匀速移动。
##
## 使用方法：
## 1. 把 Ending_credits.tscn 和 Ending_credits.gd 放到同一目录。
## 2. 直接运行该场景。
## 3. 在 Inspector 中可设置 cover_texture、scroll_speed、return_scene。
## 4. 修改下面的 CREDITS 数据即可替换工作人员名单。

@export_category("滚动")
@export var scroll_speed: float = 90.0
@export var start_delay: float = 0.8
@export var end_delay: float = 1.2

@export_category("封面")
@export var cover_texture: Texture2D

@export_category("结束")
## 例如：res://scenes/title.tscn
## 留空则播放结束后停在黑屏，不切换场景。
@export_file("*.tscn") var return_scene: String = ""

@export_category("排版")
@export var page_width: float = 920.0
@export var horizontal_margin: float = 160.0
@export var column_gap: float = 94.0
@export var title_font_size: int = 42
@export var name_font_size: int = 32

const PAPER_COLOR := Color("#D2BF91")
const PAPER_DARK := Color("#B29D70")
const INK_COLOR := Color("#2E261E")
const MUTED_INK := Color("#574B3D")
const SEAL_COLOR := Color("#7C2B22")

# 每个 Dictionary 会生成一“页”。
# columns 内每个元素是一列，列内文字自动竖排。
# 古籍阅读习惯通常从右向左，因此本脚本也按右侧第一列开始排。
const CREDITS := [
	{
		"title": "制 作 人 员",
		"columns": [
			["制作", "李"],
			["策划", "李"],
			["程序", "李"],
			["美术", "李"]
		]
	},
	{
		"title": "协 力",
		"columns": [
			["音乐", "某 某"],
			["音效", "某 某"],
			["测试", "某 某"],
			["特别感谢", "某 某"]
		]
	},
	{
		"title": "终",
		"columns": [
			["感 谢 游 玩"]
		]
	}
]

@onready var viewport_mask: Control = $ViewportMask
@onready var scroll_content: Control = $ViewportMask/ScrollContent

var _content_width: float = 0.0
var _running := false
var _elapsed := 0.0
var _finished := false


func _ready() -> void:
	resized.connect(_on_resized)
	_build_scroll()
	_reset_position()


func _process(delta: float) -> void:
	if _finished:
		return

	_elapsed += delta

	if not _running:
		if _elapsed >= start_delay:
			_running = true
		return

	scroll_content.position.x += scroll_speed * delta

	# 整张长卷完全离开屏幕右侧后结束。
	if scroll_content.position.x >= size.x:
		_finished = true
		await get_tree().create_timer(end_delay).timeout
		_finish_credits()


func _on_resized() -> void:
	if not is_node_ready():
		return

	_build_scroll()
	_reset_position()


func _reset_position() -> void:
	# 从左侧完全藏住整张长卷，再向右进入。
	scroll_content.position = Vector2(-_content_width, 0.0)
	_elapsed = 0.0
	_running = false
	_finished = false


func _build_scroll() -> void:
	# 立即清理旧页面，保证本函数保持同步；_ready() 后可以立刻用新的 _content_width 复位。
	for child in scroll_content.get_children():
		child.free()

	var pages := 1 + CREDITS.size()
	_content_width = horizontal_margin * 2.0 + page_width * pages

	scroll_content.size = Vector2(_content_width, size.y)

	_create_paper_background()

	# 长卷从左侧向右滚动时，本地 x 越大的页面越先进入屏幕。
	# 因此把封面放在最右侧，再把工作人员页按阅读顺序反向铺到左侧，
	# 实际播放顺序就是：封面 -> 制作人员 -> 协力 -> 感谢游玩。
	var x := horizontal_margin
	for page_index in range(CREDITS.size() - 1, -1, -1):
		_create_credit_page(x, CREDITS[page_index])
		x += page_width

	_create_cover_page(x)


func _create_paper_background() -> void:
	var paper := ColorRect.new()
	paper.name = "Paper"
	paper.position = Vector2.ZERO
	paper.size = Vector2(_content_width, size.y)
	paper.color = PAPER_COLOR
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_content.add_child(paper)

	# 上下两条深色古籍边缘。
	var top_line := ColorRect.new()
	top_line.position = Vector2(0, 38)
	top_line.size = Vector2(_content_width, 4)
	top_line.color = PAPER_DARK
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(top_line)

	var bottom_line := ColorRect.new()
	bottom_line.position = Vector2(0, size.y - 42)
	bottom_line.size = Vector2(_content_width, 4)
	bottom_line.color = PAPER_DARK
	bottom_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(bottom_line)

# 简单纸张旧化纹理：用半透明细线模拟，不需要外部贴图。
	for i in range(18):
		var stain := ColorRect.new()

		var y: float = 70.0 + float(i) * maxf(
			20.0,
			(size.y - 140.0) / 18.0
		)

		stain.position = Vector2(0, y)
		stain.size = Vector2(_content_width, 1)
		stain.color = Color(0.32, 0.25, 0.16, 0.055)
		stain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(stain)


func _create_cover_page(page_x: float) -> void:
	var page := Control.new()
	page.name = "CoverPage"
	page.position = Vector2(page_x, 0)
	page.size = Vector2(page_width, size.y)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_content.add_child(page)

	if cover_texture:
		var cover := TextureRect.new()
		cover.texture = cover_texture
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cover.position = Vector2(page_width * 0.18, size.y * 0.13)
		cover.size = Vector2(page_width * 0.64, size.y * 0.74)
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(cover)
	else:
		# 没有指定封面贴图时，生成一个简化的《本草纲目》古书封面占位。
		var frame := ColorRect.new()
		frame.position = Vector2(page_width * 0.25, size.y * 0.14)
		frame.size = Vector2(page_width * 0.50, size.y * 0.72)
		frame.color = Color("#B7A070")
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(frame)

		var inner := ColorRect.new()
		inner.position = Vector2(14, 14)
		inner.size = frame.size - Vector2(28, 28)
		inner.color = Color("#CBB886")
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(inner)

		var title := Label.new()
		title.text = _vertical_text("本草纲目")
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 54)
		title.add_theme_color_override("font_color", INK_COLOR)
		title.position = Vector2(inner.size.x * 0.35, inner.size.y * 0.16)
		title.size = Vector2(inner.size.x * 0.30, inner.size.y * 0.68)
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(title)

		_add_seal(inner, Vector2(inner.size.x * 0.66, inner.size.y * 0.69), "古\n籍")


func _create_credit_page(page_x: float, page_data: Dictionary) -> void:
	var page := Control.new()
	page.position = Vector2(page_x, 0)
	page.size = Vector2(page_width, size.y)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll_content.add_child(page)

	# 分隔竖线。
	var separator := ColorRect.new()
	separator.position = Vector2(page_width - 8, size.y * 0.13)
	separator.size = Vector2(2, size.y * 0.74)
	separator.color = Color(INK_COLOR, 0.22)
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(separator)

	var title_label := Label.new()
	title_label.text = _vertical_text(str(page_data.get("title", "")))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title_label.add_theme_font_size_override("font_size", title_font_size)
	title_label.add_theme_color_override("font_color", MUTED_INK)
	title_label.position = Vector2(page_width - 170, size.y * 0.18)
	title_label.size = Vector2(80, size.y * 0.62)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(title_label)

	var columns: Array = page_data.get("columns", [])
	var start_x := page_width - 280.0

	for index in range(columns.size()):
		var column_data: Array = columns[index]

		var column := VBoxContainer.new()
		column.position = Vector2(start_x - index * column_gap, size.y * 0.22)
		column.size = Vector2(72, size.y * 0.58)
		column.alignment = BoxContainer.ALIGNMENT_BEGIN
		column.add_theme_constant_override("separation", 28)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(column)

		for item in column_data:
			var label := Label.new()
			label.text = _vertical_text(str(item))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", name_font_size)
			label.add_theme_color_override("font_color", INK_COLOR)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(label)

	# 每页放一个小红印。
	_add_seal(page, Vector2(100, size.y * 0.70), "製\n作")


func _add_seal(parent: Control, pos: Vector2, text: String) -> void:
	var seal := ColorRect.new()
	seal.position = pos
	seal.size = Vector2(64, 64)
	seal.color = Color(SEAL_COLOR, 0.88)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(seal)

	var seal_text := Label.new()
	seal_text.text = text
	seal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal_text.add_theme_font_size_override("font_size", 18)
	seal_text.add_theme_color_override("font_color", Color("#E8D9B8"))
	seal_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	seal_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(seal_text)


func _vertical_text(source: String) -> String:
	# 空格只用于视觉分词，竖排时忽略。
	var result := ""
	var clean := source.replace(" ", "")

	for i in clean.length():
		result += clean.substr(i, 1)
		if i < clean.length() - 1:
			result += "\n"

	return result


func _finish_credits() -> void:
	if return_scene.is_empty():
		scroll_content.hide()
		return

	get_tree().change_scene_to_file(return_scene)
