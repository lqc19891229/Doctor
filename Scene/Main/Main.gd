extends Node
class_name Main

# =========================================================
# Main
# 负责：
# 1. 初始化开局数据
# 2. 在 Clinic 和 NightStudy 之间切换
# 3. 监听子场景发回来的流程信号
# =========================================================

# 子场景挂载点
@onready var current_scene_root: Node = $CurrentSceneRoot

# 预加载场景
const CLINIC_SCENE: PackedScene = preload("res://Scene/Clinic/Clinic.tscn")
const NIGHT_STUDY_SCENE: PackedScene = preload("res://Scene/NightStudy/NightStudy.tscn")

# 当前子场景实例
var current_scene: Node = null

# 当前天数
var current_day: int = 1


func _ready() -> void:
	_init_game_data()
	_enter_clinic()


# 初始化开局数据
func _init_game_data() -> void:
	print("Main 初始化完成，当前第 %d 天" % current_day)

# 进入 Clinic
func _enter_clinic() -> void:
	_clear_current_scene()

	# 实例化诊室场景
	current_scene = CLINIC_SCENE.instantiate()
	current_scene_root.add_child(current_scene)

	# 连接 clinic_finished 信号
	# 当诊室一天结束时，切换到 NightStudy
	if current_scene.has_signal("clinic_finished"):
		if not current_scene.is_connected("clinic_finished", Callable(self, "_on_clinic_finished")):
			current_scene.connect("clinic_finished", Callable(self, "_on_clinic_finished"))
			print("Main 已连接 clinic_finished 信号")
	else:
		print("current_scene 没有 clinic_finished 信号")

	# 先刷新左上角天数显示
	if current_scene.has_method("set_day"):
		current_scene.call("set_day", current_day)
		print("已刷新诊室天数：", current_day)
	else:
		print("Clinic 没有 set_day 方法")

	# 再开始新的一天逻辑
	if current_scene.has_method("start_new_day"):
		current_scene.call("start_new_day", current_day)

	print("已进入 Clinic 场景，第 %d 天" % current_day)

# 进入 NightStudy
func _enter_night_study() -> void:
	_clear_current_scene()

	# 实例化夜晚读书场景
	current_scene = NIGHT_STUDY_SCENE.instantiate()
	current_scene_root.add_child(current_scene)

	# 连接 study_finished 信号
	# 当夜晚阅读结束时，进入下一天的 Clinic
	if current_scene.has_signal("study_finished"):
		if not current_scene.is_connected("study_finished", Callable(self, "_on_study_finished")):
			current_scene.connect("study_finished", Callable(self, "_on_study_finished"))
			print("Main 已连接 study_finished 信号")
	else:
		print("current_scene 没有 study_finished 信号")

	print("已进入 NightStudy 场景")


# Clinic 当天结束
func _on_clinic_finished() -> void:
	print("Clinic 已结束，切换到夜晚阅读场景")
	_enter_night_study()


# NightStudy 结束，进入下一天
func _on_study_finished() -> void:
	current_day += 1
	print("夜晚阅读结束，进入第 %d 天" % current_day)
	_enter_clinic()


# 清理旧子场景
func _clear_current_scene() -> void:
	if current_scene != null and is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
