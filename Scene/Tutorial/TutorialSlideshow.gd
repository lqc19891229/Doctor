extends Control
class_name TutorialSlideshow

signal tutorial_finished

@export var screenshots: Array[Texture2D] = []
@export var titles: PackedStringArray = []
@export var descriptions: PackedStringArray = []
@export var close_on_finish: bool = true

@onready var screenshot: TextureRect = $SlideFrame/Screenshot
@onready var placeholder: Control = $SlideFrame/Placeholder
@onready var title_label: Label = $CaptionPanel/TitleLabel
@onready var description_label: RichTextLabel = $CaptionPanel/DescriptionLabel
@onready var page_label: Label = $PageLabel
@onready var previous_button: Button = $PreviousButton
@onready var next_button: Button = $NextButton
@onready var skip_button: Button = $SkipButton

var current_page: int = 0
var _finishing: bool = false


func _ready() -> void:
	if not previous_button.pressed.is_connected(_on_previous_pressed):
		previous_button.pressed.connect(_on_previous_pressed)
	if not next_button.pressed.is_connected(_on_next_pressed):
		next_button.pressed.connect(_on_next_pressed)
	if not skip_button.pressed.is_connected(_on_skip_pressed):
		skip_button.pressed.connect(_on_skip_pressed)

	_show_page()
	next_button.grab_focus()


func open(reset_to_first_page: bool = true) -> void:
	_finishing = false
	if reset_to_first_page:
		current_page = 0
	visible = true
	_show_page()
	next_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _finishing:
		return

	if event.is_action_pressed("ui_left"):
		_on_previous_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		_on_next_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_skip_pressed()
		get_viewport().set_input_as_handled()


func _get_page_count() -> int:
	return maxi(maxi(screenshots.size(), titles.size()), maxi(descriptions.size(), 1))


func _show_page() -> void:
	var page_count := _get_page_count()
	current_page = clampi(current_page, 0, page_count - 1)

	var page_texture: Texture2D = null
	if current_page < screenshots.size():
		page_texture = screenshots[current_page]

	screenshot.texture = page_texture
	screenshot.visible = page_texture != null
	placeholder.visible = page_texture == null

	title_label.text = (
		titles[current_page]
		if current_page < titles.size()
		else "玩法说明"
	)
	description_label.text = (
		descriptions[current_page]
		if current_page < descriptions.size()
		else "请在 TutorialSlideshow 节点的 Screenshots 属性中添加这一页的游戏截图。"
	)

	page_label.text = "%d / %d" % [current_page + 1, page_count]
	previous_button.disabled = current_page == 0
	next_button.text = "开始游戏" if current_page == page_count - 1 else "下一页"


func _on_previous_pressed() -> void:
	if _finishing or current_page <= 0:
		return

	current_page -= 1
	_show_page()


func _on_next_pressed() -> void:
	if _finishing:
		return

	if current_page >= _get_page_count() - 1:
		_finish_tutorial()
		return

	current_page += 1
	_show_page()


func _on_skip_pressed() -> void:
	if _finishing:
		return
	_finish_tutorial()


func _finish_tutorial() -> void:
	if _finishing:
		return

	_finishing = true
	tutorial_finished.emit()

	if close_on_finish:
		queue_free()
	else:
		visible = false
