extends Control

## =========================================================
## PulseDrawer.gd
## 本版功能：
## 1. 保留单脉象显示
## 2. 支持四分屏 GROUP 模式
## 3. 每个脉区独立使用自己的：
##    - qi     -> 振幅
##    - blood  -> 粗细
##    - speed  -> 速度
##    - width  -> 波宽
## 4. 每个脉区独立保存自己的滚动偏移
##    避免四张图共用一套动画参数
## =========================================================

enum DrawMode {
	NONE,
	SINGLE,
	GROUP
}

@export var current_region_name: String = "表"
@export var current_region_id: String = "exterior"

# 旧版兼容参数：
# 仍然保留，方便外部代码或调试使用
# 统一度量后的默认值：
# 1.0 = 健康基准值
@export var qi_value: float = 1.0
@export var blood_value: float = 1.0
@export var cold_hot_value: float = 1.0
@export var wet_dry_value: float = 1.0

@export var pulse_color: Color = Color(0.95, 0.95, 0.95)
@export var animate_wave: bool = true
@export var point_count: int = 360
@export var show_center_line: bool = true

# 健康脉象基准值：
# 外部输入统一用 1.0 表示健康
# 绘图时再乘回原本的实际显示值
const BASE_QI := 100.0
const BASE_BLOOD := 100.0
const BASE_COLD_HOT := 1.3
const BASE_WET_DRY := 10.0

# 缩放参数：
# 用来把四轴数值映射成实际绘制效果
@export var amplitude_scale: float = 0.6
@export var line_width_scale: float = 0.25
@export var speed_scale: float = 1.0
@export var frequency_scale: float = 0.5

# 整套区域数据
# 例如：
# {
#   "exterior": {"qi": 1.2, "blood": 0.9, "speed": 0.7, "width": 1.1},
#   "lung":     {"qi": 0.8, "blood": 0.7, "speed": 1.2, "width": 0.8}
# }
var pulse_regions: Dictionary = {}

# 当前绘制模式
var draw_mode: int = DrawMode.SINGLE

# GROUP 模式下要显示的四个区域 id
var group_region_ids: Array[String] = []

# 每个脉区各自独立的滚动偏移
# key: region_id
# value: float
var region_scroll_map: Dictionary = {}


func _ready() -> void:
	print("PulseDrawer size = ", size)


func _process(delta: float) -> void:
	if not animate_wave:
		return

	if pulse_regions.is_empty():
		return

	# 让每个脉区按自己的 speed / width 独立更新动画
	for region_id in pulse_regions.keys():
		var region_data: Dictionary = pulse_regions[region_id]

		# 速度优先读取 speed，没有就退回 old key cold_hot，再退回默认值
		# 这里读取的是统一值：1.0 = 健康速度
		var cold_hot_logic := float(region_data.get("speed", region_data.get("cold_hot", 1.0)))

		# 波宽优先读取 width，没有就退回 old key wet_dry，再退回默认值
		# 这里读取的是统一值：1.0 = 健康波宽
		var wet_dry_logic := float(region_data.get("width", region_data.get("wet_dry", 1.0)))

		# 转成实际绘图值：
		# speed: 1.0 -> 1.3
		# width: 1.0 -> 10.0
		var cold_hot := cold_hot_logic * BASE_COLD_HOT
		var wet_dry := wet_dry_logic * BASE_WET_DRY

		var speed := cold_hot * speed_scale
		var frequency := 20.0 / (wet_dry * frequency_scale + 0.0001)
		var period_x = max(size.x / max(frequency, 0.0001), 1.0)

		var scroll := float(region_scroll_map.get(region_id, 0.0))
		scroll += delta * speed * period_x
		scroll = fposmod(scroll, period_x)

		region_scroll_map[region_id] = scroll

	queue_redraw()


func _draw() -> void:
	match draw_mode:
		DrawMode.NONE:
			return

		DrawMode.SINGLE:
			_draw_single_region()

		DrawMode.GROUP:
			_draw_group_regions()


# =========================================================
# 单脉象模式：整个 PulseDrawer 只显示一个脉象
# =========================================================
func _draw_single_region() -> void:
	var target_rect := Rect2(Vector2.ZERO, size)

	# 单脉象模式下，显示当前区域
	_draw_region_wave(target_rect, current_region_id)

	# 画四等分辅助线（1/4、1/2、3/4）
	if show_center_line:
		_draw_quarter_guides(target_rect)


# =========================================================
# 组合模式：PulseDrawer 纵向四等分，显示 4 个脉象
# 顺序通常是：
# [表, 寸, 关, 尺]
# =========================================================
func _draw_group_regions() -> void:
	if group_region_ids.size() != 4:
		return

	var block_height := size.y / 4.0

	for i in range(4):
		var target_rect := Rect2(
			Vector2(0.0, block_height * i),
			Vector2(size.x, block_height)
		)

		# 绘制这一块自己的脉象
		_draw_region_wave(target_rect, group_region_ids[i])

		# 画每个区块内部的四等分辅助线（1/4、1/2、3/4）
		if show_center_line:
			_draw_quarter_guides(target_rect)

		# 外框分隔线
		draw_rect(target_rect, Color(1, 1, 1, 0.08), false, 1.0)


# =========================================================
# 在指定矩形内绘制四等分辅助线
# 作用：把当前矩形区域按高度平均分成 4 份
#       因此需要绘制 3 条水平线，位置分别在 1/4、1/2、3/4
# =========================================================
func _draw_quarter_guides(target_rect: Rect2) -> void:
	var guide_color := Color(1, 1, 1, 0.08)
	var h := target_rect.size.y

	var y1 := target_rect.position.y + h * 0.25
	var y2 := target_rect.position.y + h * 0.50
	var y3 := target_rect.position.y + h * 0.75

	draw_line(
		Vector2(target_rect.position.x, y1),
		Vector2(target_rect.position.x + target_rect.size.x, y1),
		guide_color,
		1.0
	)

	draw_line(
		Vector2(target_rect.position.x, y2),
		Vector2(target_rect.position.x + target_rect.size.x, y2),
		guide_color,
		1.0
	)

	draw_line(
		Vector2(target_rect.position.x, y3),
		Vector2(target_rect.position.x + target_rect.size.x, y3),
		guide_color,
		1.0
	)


# =========================================================
# 在指定矩形内绘制某个区域的脉象
# 每个区域都只使用自己的四轴数据
# =========================================================
func _draw_region_wave(target_rect: Rect2, region_id: String) -> void:
	if not pulse_regions.has(region_id):
		return

	var region_data: Dictionary = pulse_regions[region_id]

	# 当前区域自己的四轴
	# 这里读取的是统一值：
	# 1.0 = 健康基准
	# 小于 1.0 = 不足 / 偏弱
	# 大于 1.0 = 亢盛 / 偏强
	var qi_logic := float(region_data.get("qi", 1.0))
	var blood_logic := float(region_data.get("blood", 1.0))
	var cold_hot_logic := float(region_data.get("speed", region_data.get("cold_hot", 1.0)))
	var wet_dry_logic := float(region_data.get("width", region_data.get("wet_dry", 1.0)))

	# 转成实际绘图值：
	# qi:      1.0 -> 100.0
	# blood:   1.0 -> 100.0
	# speed:   1.0 -> 1.3
	# width:   1.0 -> 10.0
	var qi := qi_logic * BASE_QI
	var blood := blood_logic * BASE_BLOOD
	var cold_hot := cold_hot_logic * BASE_COLD_HOT
	var wet_dry := wet_dry_logic * BASE_WET_DRY

	var w := target_rect.size.x
	var h := target_rect.size.y
	var center_y := target_rect.position.y + h * 0.5

	# qi 决定振幅
	var amplitude := qi * amplitude_scale

	# blood 决定线粗
	var line_width = max(blood * line_width_scale, 1.0)

	# wet_dry / width 决定波宽
	var frequency := 20.0 / (wet_dry * frequency_scale + 0.0001)
	var period_x = max(w / max(frequency, 0.0001), 1.0)

	# 当前区域自己的动画偏移
	var scroll := float(region_scroll_map.get(region_id, 0.0))

	var points: PackedVector2Array = []

	for i in range(point_count):
		var t := float(i) / float(max(point_count - 1, 1))
		var x := target_rect.position.x + t * w

		# 当前区域自己的 phase
		var phase = ((x - target_rect.position.x + scroll) / period_x) * TAU
		var wave := sin(phase)

		var y := center_y - wave * amplitude

		# 限制在当前子区域内
		y = clamp(
			y,
			target_rect.position.y + 2.0,
			target_rect.position.y + target_rect.size.y - 2.0
		)

		points.append(Vector2(x, y))

	draw_polyline(points, pulse_color, line_width, true)


# =========================================================
# 旧接口：直接设置当前默认四轴参数
# 注意：这里传入的也是统一值，1.0 = 健康基准
# 主要用于兼容旧逻辑 / 调试
# =========================================================
func set_pulse_values(qi: float, blood: float, cold_hot: float, wet_dry: float) -> void:
	qi_value = qi
	blood_value = blood
	cold_hot_value = cold_hot
	wet_dry_value = wet_dry
	queue_redraw()


# =========================================================
# 设置整套七区数据
# =========================================================
func set_pulse_regions(new_regions: Dictionary) -> void:
	pulse_regions = new_regions
	region_scroll_map.clear()

	# 为每个脉区初始化独立滚动值
	for region_id in pulse_regions.keys():
		region_scroll_map[region_id] = 0.0

	if pulse_regions.is_empty():
		return

	# 如果当前区域不存在，就切到第一个
	if not pulse_regions.has(current_region_id):
		current_region_id = str(pulse_regions.keys()[0])

	# 同步旧版兼容参数
	_apply_current_region_data()
	queue_redraw()


# =========================================================
# 切换到单区域显示
# region_id:
# exterior / heart / liver / spleen / lung / kidney_yin / kidney_yang
# =========================================================
func set_region(region_id: String) -> void:
	if not pulse_regions.has(region_id):
		push_warning("PulseDrawer: 找不到脉区 -> " + region_id)
		return

	draw_mode = DrawMode.SINGLE
	current_region_id = region_id
	group_region_ids.clear()

	# 同步旧版兼容参数
	_apply_current_region_data()
	queue_redraw()


# =========================================================
# 切换到四分屏显示
# 传入 4 个区域 id，例如：
# ["exterior", "lung", "spleen", "kidney_yang"]
# =========================================================
func set_group_regions(region_ids: Array[String]) -> void:
	if region_ids.size() != 4:
		push_warning("PulseDrawer.set_group_regions: 必须传入 4 个区域")
		return

	group_region_ids.clear()

	for region_id in region_ids:
		var region_id_str := str(region_id)
		if not pulse_regions.has(region_id_str):
			push_warning("PulseDrawer.set_group_regions: 找不到脉区 -> " + region_id_str)
			return
		group_region_ids.append(region_id_str)

	draw_mode = DrawMode.GROUP

	# 这里仍然保留 current_region_id，主要是给旧接口兼容
	# 但实际四分屏绘制时，每个区域都会读自己的数据
	current_region_id = group_region_ids[0]
	_apply_current_region_data()
	queue_redraw()


# =========================================================
# 清空显示
# =========================================================
func clear_display() -> void:
	draw_mode = DrawMode.NONE
	group_region_ids.clear()
	queue_redraw()


# =========================================================
# 把当前区域的数据同步到旧版四轴变量
# 仅用于兼容旧逻辑，不再控制 GROUP 模式的实际绘制效果
# =========================================================
func _apply_current_region_data() -> void:
	if not pulse_regions.has(current_region_id):
		return

	var region_data: Dictionary = pulse_regions[current_region_id]

	current_region_name = str(region_data.get("region_name", current_region_name))

	set_pulse_values(
		float(region_data.get("qi", qi_value)),
		float(region_data.get("blood", blood_value)),
		float(region_data.get("speed", region_data.get("cold_hot", cold_hot_value))),
		float(region_data.get("width", region_data.get("wet_dry", wet_dry_value)))
	)


func get_current_region_name() -> String:
	return current_region_name


func get_current_region_id() -> String:
	return current_region_id
