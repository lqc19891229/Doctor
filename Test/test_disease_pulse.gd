extends Node

## 脉象绘制节点
@onready var pulse_drawer = $PulseDrawer

## 显示 NPC 和疾病信息的文本
@onready var disease_label: Label = $DiseaseName

## NPC 管理器
@onready var npc_manager = $NpcManager


## =========================================================
## 函数：_ready()
##
## 功能：
## 场景启动时，先显示当前 NPC 对应的疾病和脉象。
## =========================================================
func _ready() -> void:
	show_current_npc()


## =========================================================
## 函数：show_current_npc()
##
## 功能：
## 读取当前 NPC 数据，并更新：
## 1. NPC / 疾病文字
## 2. 脉象图
##
## 意义：
## 这是当前测试场景的核心刷新函数。
## 不管是点击上一个、下一个，还是生成新病人，
## 最后都调用这里。
## =========================================================
func show_current_npc() -> void:
	var npc: NpcData = npc_manager.get_current_npc()

	if npc == null:
		disease_label.text = "没有 NPC 数据"
		pulse_drawer.reset_pulse()
		return

	if npc.disease == null:
		disease_label.text = "NPC：%s\n没有绑定疾病" % npc.npc_name
		pulse_drawer.reset_pulse()
		return

	## 更新脉象
	pulse_drawer.apply_disease_pulse(npc.disease)

	## 更新文字
	disease_label.text = "NPC：%s\n性别：%s  年龄：%d\n疾病：%s\n气：%s  血：%s  寒热：%s  湿燥：%s" % [
		npc.npc_name,
		npc.gender,
		npc.age,
		npc.disease.disease_name,
		npc.disease.pulse_qi,
		npc.disease.pulse_blood,
		npc.disease.pulse_cold_hot,
		npc.disease.pulse_wet_dry
	]

	## 调试输出
	print("当前 NPC：", npc.npc_name)
	npc.debug_print()


## =========================================================
## 函数：_on_next_button_pressed()
##
## 功能：
## 切换到下一个 NPC，然后刷新显示。
## =========================================================
func _on_next_button_pressed() -> void:
	npc_manager.next_npc()
	show_current_npc()


## =========================================================
## 函数：_on_prev_button_pressed()
##
## 功能：
## 切换到上一个 NPC，然后刷新显示。
## =========================================================
func _on_prev_button_pressed() -> void:
	npc_manager.prev_npc()
	show_current_npc()


## =========================================================
## 函数：_on_spawn_npc_button_pressed()
##
## 功能：
## 随机生成一个新病人，并自动切换到这个新病人。
##
## 流程：
## 1. 调用 NpcManager 生成随机 NPC
## 2. 新 NPC 会加入 npc_list
## 3. current_index 会自动切到这个新 NPC
## 4. 刷新界面与脉象
## =========================================================
func _on_spawn_npc_button_pressed() -> void:
	var new_npc: NpcData = npc_manager.spawn_random_npc()

	if new_npc == null:
		print("生成新病人失败")
		return

	print("生成了新病人：", new_npc.npc_name)

	show_current_npc()
