extends Control

## =========================================================
## PulseDrawer.gd
##
## 特点：
## 1. 不做归一化
## 2. 不限制数据范围
## 3. 四轴值直接参与计算
##
## 四轴含义：
## 气轴      -> 波峰高度
## 血轴      -> 线条粗细
## 寒热轴    -> 脉搏速度
## 湿燥轴    -> 波形宽窄
##
## 设计思想：
## 数值完全由外部数据决定，脚本只负责绘图。
## =========================================================


## =========================================================
## 一、健康脉象数值
## =========================================================

@export var qi_value: float = 100.0
@export var blood_value: float = 100.0
@export var cold_hot_value: float = 1.3
@export var wet_dry_value: float = 10.0


## =========================================================
## 二、显示参数
## =========================================================

@export var pulse_color: Color = Color(0.95,0.95,0.95)
@export var animate_wave: bool = true
@export var point_count: int = 360
@export var show_center_line: bool = true


## =========================================================
## 三、倍率参数
##
## 这些只是线性倍率，不是限制。
## =========================================================

@export var amplitude_scale: float = 2.5
@export var line_width_scale: float = 0.5
@export var speed_scale: float = 1.0
@export var frequency_scale: float = 1.0


## =========================================================
## 四、运行变量
## =========================================================

var scroll_x: float = 0.0


## =========================================================
## 函数：_process
##
## 功能：
## 控制波形滚动速度
## =========================================================
func _process(delta: float) -> void:

	if not animate_wave:
		return

	## 寒热轴 -> 速度
	var speed := cold_hot_value * speed_scale

	## 湿燥轴 -> 波宽
	## 数值越大，波越宽
	var frequency := 20.0 / (wet_dry_value * frequency_scale + 0.0001)

	var period_x := size.x / frequency

	scroll_x += delta * speed * period_x

	scroll_x = fposmod(scroll_x, period_x)

	queue_redraw()


## =========================================================
## 函数：_draw
##
## 功能：
## 绘制脉象曲线
## =========================================================
func _draw() -> void:

	var w := size.x
	var h := size.y

	var center_y := h * 0.5

	## 气轴 -> 振幅
	var amplitude := qi_value * amplitude_scale

	## 血轴 -> 线宽
	var line_width := blood_value * line_width_scale

	## 湿燥轴 -> 波宽
	var frequency := 20.0 / (wet_dry_value * frequency_scale + 0.0001)

	var period_x := w / frequency

	var points: PackedVector2Array = []

	for i in point_count:

		var t := float(i) / float(point_count - 1)

		var x := t * w

		var phase := ((x + scroll_x) / period_x) * TAU

		var wave := sin(phase)

		var y := center_y - wave * amplitude

		points.append(Vector2(x,y))


	draw_polyline(points, pulse_color, line_width, true)


	if show_center_line:
		draw_line(
			Vector2(0,center_y),
			Vector2(w,center_y),
			Color(1,1,1,0.08),
			1.0
		)


## =========================================================
## 设置四轴
## =========================================================
func set_pulse_values(qi:float,blood:float,cold_hot:float,wet_dry:float):

	qi_value = qi
	blood_value = blood
	cold_hot_value = cold_hot
	wet_dry_value = wet_dry

	queue_redraw()


## =========================================================
## 从疾病数据读取
## =========================================================
func apply_disease_pulse(disease_data:DiseaseData):

	set_pulse_values(
		disease_data.pulse_qi,
		disease_data.pulse_blood,
		disease_data.pulse_cold_hot,
		disease_data.pulse_wet_dry
	)
