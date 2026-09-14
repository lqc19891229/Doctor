extends Control
class_name TutorialWindow

## A reusable, full-screen tutorial overlay.
##
## The scene ships with four project-specific pages, but every page array is
## exported so the same window can be reused by Clinic, Night or a future scene.

signal page_changed(page_index: int, page_count: int)
signal finished
signal closed(completed: bool)

@export_category("Tutorial pages")
@export var page_titles: PackedStringArray = [
	"坐堂问诊",
	"诊脉辨证",
	"开具处方",
	"夜读医书",
]
@export var page_descriptions: PackedStringArray = [
	"白天在诊室接待病人。先了解病情，再依次进行诊脉、记录与开方。",
	"点击诊脉入口查看六部脉象。结合病人的叙述与脉象，判断可能的证候。",
	"在处方窗口选择药材与用量。提交前可以返回检查，确认后系统会评估疗效。",
	"结束白天后进入夜晚。阅读已解锁医书，可以补全病证、方剂与药材知识。",
]
@export var page_captions: PackedStringArray = [
	"诊室总览",
	"诊桌与诊脉入口",
	"开方与确认",
	"夜晚与医书",
]
@export var page_images: Array[Texture2D] = [
	preload("res://Assets/Background/clinic/spring.png"),
	preload("res://Assets/Background/clinic/clinic_table.png"),
	preload("res://Assets/UI/bookpage.png"),
	preload("res://Assets/Background/clinic/night_table.png"),
]

@export_category("Behaviour")
@export var pause_game_while_visible: bool = true
@export var close_with_escape: bool = true
@export var wrap_pages: bool = false

@onready var page_image: TextureRect = %PageImage
@onready var image_caption: Label = %ImageCaption
@onready var step_label: Label = %StepLabel
@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var page_indicator: Label = %PageIndicator
@onready var previous_button: Button = %PreviousButton
@onready var next_button: Button = %NextButton
@onready var close_button: Button = %CloseButton

var current_page: int = 0
var _tree_was_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_connect_signals()
	_refresh_page()
	hide()


func open_tutorial(start_page: int = 0) -> void:
	var page_count := _get_page_count()
	if page_count <= 0:
		push_warning("TutorialWindow has no tutorial pages.")
		return

	current_page = clampi(start_page, 0, page_count - 1)
	_tree_was_paused = get_tree().paused
	if pause_game_while_visible:
		get_tree().paused = true

	show()
	move_to_front()
	_refresh_page()
	next_button.grab_focus()


func close_tutorial(completed: bool = false) -> void:
	if not visible:
		return

	hide()
	if pause_game_while_visible:
		get_tree().paused = _tree_was_paused
	closed.emit(completed)


func set_pages(
	titles: PackedStringArray,
	descriptions: PackedStringArray,
	images: Array[Texture2D],
	captions: PackedStringArray = PackedStringArray()
) -> void:
	page_titles = titles
	page_descriptions = descriptions
	page_images = images
	page_captions = captions
	current_page = 0
	_refresh_page()


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
	var page_count := page_titles.size()
	page_count = maxi(page_count, page_descriptions.size())
	page_count = maxi(page_count, page_captions.size())
	page_count = maxi(page_count, page_images.size())
	return page_count


func _refresh_page() -> void:
	if not is_node_ready():
		return

	var page_count := _get_page_count()
	var has_pages := page_count > 0

	previous_button.disabled = not has_pages or (current_page == 0 and not wrap_pages)
	next_button.disabled = not has_pages

	if not has_pages:
		page_image.texture = null
		image_caption.text = ""
		step_label.text = ""
		title_label.text = "暂无说明"
		description_label.text = "请在 Inspector 中配置 Tutorial pages。"
		page_indicator.text = "0 / 0"
		next_button.text = "完成"
		return

	current_page = clampi(current_page, 0, page_count - 1)
	page_image.texture = page_images[current_page] if current_page < page_images.size() else null
	image_caption.text = page_captions[current_page] if current_page < page_captions.size() else ""
	step_label.text = "第 %d 步" % (current_page + 1)
	title_label.text = page_titles[current_page] if current_page < page_titles.size() else "游戏说明"
	description_label.text = (
		page_descriptions[current_page]
		if current_page < page_descriptions.size()
		else ""
	)
	page_indicator.text = "%d / %d" % [current_page + 1, page_count]
	next_button.text = "完成" if current_page == page_count - 1 else "下一步"
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


func _unhandled_input(event: InputEvent) -> void:
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
