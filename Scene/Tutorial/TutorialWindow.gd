extends Control
class_name TutorialWindow

## A reusable, full-screen tutorial overlay.
##
## Each tutorial page is stored as one TutorialSlideData resource, so its title,
## description and image always stay together.

signal page_changed(page_index: int, page_count: int)
signal finished
signal closed(completed: bool)

enum TutorialSet {
	NIGHT,
	DAY,
}

# 保留原有属性名 slides，避免已经在场景中配置好的夜间教学页丢失。
@export_category("夜间教学")
@export var slides: Array[TutorialSlideData] = []

# 白天教学使用独立数组；之后接入触发机制时调用 open_day_tutorial()。
@export_category("白天教学")
@export var day_slides: Array[TutorialSlideData] = []

@export_category("Behaviour")
@export var pause_game_while_visible: bool = true
@export var close_with_escape: bool = true
@export var wrap_pages: bool = false

@onready var page_image: TextureRect = %PageImage
@onready var window_title: Label = $CenterContainer/WindowPanel/OuterMargin/RootVBox/Header/WindowTitle
@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var keyboard_hint: Label = $CenterContainer/WindowPanel/OuterMargin/RootVBox/Content/TextPanel/TextMargin/TextVBox/KeyboardHint
@onready var page_indicator: Label = %PageIndicator
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton
@onready var close_button: Button = %CloseButton

var current_page: int = 0
var current_tutorial_set: int = TutorialSet.NIGHT
var _tree_was_paused: bool = false
var _active_slides: Array[TutorialSlideData] = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_page()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_active_slides = slides
	_connect_signals()
	_refresh_page()
	hide()


func open_tutorial(start_page: int = 0) -> void:
	# 兼容原有调用：open_tutorial() 始终打开原来的夜间教学。
	current_tutorial_set = TutorialSet.NIGHT
	_active_slides = slides
	_open_active_tutorial(start_page)


func _open_active_tutorial(start_page: int = 0) -> void:
	var page_count := _get_page_count()
	if page_count <= 0:
		push_warning("TutorialWindow 当前选择的教学没有页面。")
		return

	current_page = clampi(start_page, 0, page_count - 1)
	if visible:
		_refresh_page()
		next_button.grab_focus()
		return

	_tree_was_paused = get_tree().paused
	if pause_game_while_visible:
		get_tree().paused = true

	show()
	move_to_front()
	_refresh_page()
	next_button.grab_focus()


## 打开夜间教学。保留 open_tutorial() 作为兼容入口时，默认同样使用夜间教学。
func open_night_tutorial(start_page: int = 0) -> void:
	open_tutorial(start_page)


## 打开白天教学。
func open_day_tutorial(start_page: int = 0) -> void:
	current_tutorial_set = TutorialSet.DAY
	_active_slides = day_slides
	_open_active_tutorial(start_page)


func close_tutorial(completed: bool = false) -> void:
	if not visible:
		return

	hide()
	if pause_game_while_visible:
		get_tree().paused = _tree_was_paused
	closed.emit(completed)


## 兼容原有调用：替换夜间教学页，并将当前教学切回夜间。
func set_slides(new_slides: Array[TutorialSlideData]) -> void:
	slides = new_slides
	current_tutorial_set = TutorialSet.NIGHT
	_active_slides = slides
	current_page = 0
	_refresh_page()


## 替换白天教学页；不会自动打开窗口。
func set_day_slides(new_slides: Array[TutorialSlideData]) -> void:
	day_slides = new_slides
	if current_tutorial_set == TutorialSet.DAY:
		_active_slides = day_slides
		current_page = 0
		_refresh_page()


## Compatibility helper for code that still uses the old array API.
## The optional fourth argument is accepted only so older callers do not break;
## captions are no longer displayed or stored. New code should prefer set_slides().
func set_pages(
	titles: PackedStringArray,
	descriptions: PackedStringArray,
	images: Array[Texture2D],
	_legacy_captions: PackedStringArray = PackedStringArray()
) -> void:
	var new_slides: Array[TutorialSlideData] = []
	var page_count := titles.size()
	page_count = maxi(page_count, descriptions.size())
	page_count = maxi(page_count, images.size())

	for page_index in range(page_count):
		var slide := TutorialSlideData.new()
		slide.title = titles[page_index] if page_index < titles.size() else "UI_TUTORIAL_WINDOW_TITLE"
		slide.description = descriptions[page_index] if page_index < descriptions.size() else ""
		slide.image = images[page_index] if page_index < images.size() else null
		new_slides.append(slide)

	set_slides(new_slides)


func go_to_page(page_index: int) -> void:
	var page_count := _get_page_count()
	if page_count <= 0:
		return

	current_page = clampi(page_index, 0, page_count - 1)
	_refresh_page()


func _connect_signals() -> void:
	if not previous_button.pressed.is_connected(_on_previous_pressed):
		previous_button.pressed.connect(_on_previous_pressed)
	if not next_button.pressed.is_connected(_on_next_pressed):
		next_button.pressed.connect(_on_next_pressed)
	if not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)


func _get_page_count() -> int:
	return _active_slides.size()


func _refresh_page() -> void:
	if not is_node_ready():
		return

	window_title.text = tr("UI_TUTORIAL_WINDOW_TITLE")
	keyboard_hint.text = tr("UI_TUTORIAL_KEYBOARD_HINT")
	previous_button.text = tr("UI_TUTORIAL_PREVIOUS")

	var page_count := _get_page_count()
	var has_pages := page_count > 0

	previous_button.disabled = not has_pages or (current_page == 0 and not wrap_pages)
	next_button.disabled = not has_pages

	if not has_pages:
		page_image.texture = null
		title_label.text = tr("UI_TUTORIAL_NO_PAGES")
		if current_tutorial_set == TutorialSet.DAY:
			description_label.text = tr("UI_TUTORIAL_ADD_DAY_SLIDES")
		else:
			description_label.text = tr("UI_TUTORIAL_ADD_NIGHT_SLIDES")
		page_indicator.text = "0 / 0"
		next_button.text = tr("UI_TUTORIAL_DONE")
		return

	current_page = clampi(current_page, 0, page_count - 1)
	var slide: TutorialSlideData = _active_slides[current_page]

	if slide == null:
		page_image.texture = null
		title_label.text = tr("UI_TUTORIAL_WINDOW_TITLE")
		description_label.text = tr("UI_TUTORIAL_MISSING_SLIDE")
	else:
		page_image.texture = slide.image
		title_label.text = tr(slide.title)
		description_label.text = tr(slide.description)

	page_indicator.text = "%d / %d" % [current_page + 1, page_count]
	next_button.text = tr("UI_TUTORIAL_DONE") if current_page == page_count - 1 else tr("UI_TUTORIAL_NEXT")
	page_changed.emit(current_page, page_count)


func _on_previous_pressed() -> void:
	var page_count := _get_page_count()
	if page_count <= 0:
		return

	if current_page > 0:
		current_page -= 1
	elif wrap_pages:
		current_page = page_count - 1
	_refresh_page()


func _on_next_pressed() -> void:
	var page_count := _get_page_count()
	if page_count <= 0:
		return

	if current_page < page_count - 1:
		current_page += 1
		_refresh_page()
		return

	if wrap_pages:
		current_page = 0
		_refresh_page()
		return

	finished.emit()
	close_tutorial(true)


func _on_close_pressed() -> void:
	close_tutorial(false)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return

	if close_with_escape and event.is_action_pressed("ui_cancel"):
		close_tutorial(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_on_previous_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_on_next_pressed()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if visible and pause_game_while_visible and get_tree() != null:
		get_tree().paused = _tree_was_paused
