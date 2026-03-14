## =========================================================
## NpcManager.gd
##
## 功能：
## 负责管理所有 NPC 数据与疾病数据。
##
## 当前版本职责：
## 1. 自动加载 res://Npc/ 中的所有 NpcData
## 2. 自动加载 res://Disease/ 中的所有 DiseaseData
## 3. 获取当前 NPC
## 4. 切换上一个 / 下一个 NPC
## 5. 随机生成 NPC
## 6. 生成 NPC 时直接从 Disease 文件夹随机取病
##
## 数据流：
## NpcManager
##    ├─ NpcData
##    └─ DiseaseData
##            ↓
##        PulseDrawer
## =========================================================

extends Node


## =========================================================
## 一、数据列表
## =========================================================

## 当前正在管理的 NPC 列表
var npc_list: Array[NpcData] = []

## NPC 模板列表（从文件夹加载）
var npc_template_list: Array[NpcData] = []

## 疾病模板列表（从 Disease 文件夹加载）
var disease_list: Array[DiseaseData] = []

## 当前 NPC 索引
var current_index: int = 0


## =========================================================
## 二、随机名字数据
## =========================================================
var family_names: Array[String] = [
	"李", "张", "王", "赵", "陈", "刘", "杨", "黄", "周", "吴"
]

var given_names_male: Array[String] = [
	"明", "强", "安", "林", "山", "峰", "毅", "辰", "远", "博"
]

var given_names_female: Array[String] = [
	"兰", "月", "雪", "梅", "琴", "芳", "云", "荷", "宁", "柔"
]


## =========================================================
## 三、初始化
##
## 功能：
## 场景启动时自动加载 NPC 和 Disease
## =========================================================
func _ready() -> void:
	load_all_npcs()
	load_all_diseases()


## =========================================================
## 四、加载所有 NPC
##
## 功能：
## 扫描 res://Npc/ 下的所有 .tres 文件
## 并读取其中的 NpcData
## =========================================================
func load_all_npcs() -> void:
	npc_list.clear()
	npc_template_list.clear()
	current_index = 0

	var dir := DirAccess.open("res://Npc")

	if dir == null:
		print("Npc 文件夹不存在")
		return

	dir.list_dir_begin()

	var file := dir.get_next()

	while file != "":
		if file.ends_with(".tres"):
			var path := "res://Npc/" + file
			var npc = load(path)

			if npc is NpcData:
				npc_template_list.append(npc)
				npc_list.append(npc)

		file = dir.get_next()

	dir.list_dir_end()

	print("加载 NPC 模板数量：", npc_template_list.size())
	print("当前 NPC 列表数量：", npc_list.size())


## =========================================================
## 五、加载所有 Disease
##
## 功能：
## 扫描 res://Disease/ 下的所有 .tres 文件
## 并读取其中的 DiseaseData
##
## 说明：
## 以后随机 NPC 的疾病就从这里取
## =========================================================
func load_all_diseases() -> void:
	disease_list.clear()

	var dir := DirAccess.open("res://Disease")

	if dir == null:
		print("Disease 文件夹不存在")
		return

	dir.list_dir_begin()

	var file := dir.get_next()

	while file != "":
		if file.ends_with(".tres"):
			var path := "res://Disease/" + file
			var disease = load(path)

			if disease is DiseaseData:
				disease_list.append(disease)

		file = dir.get_next()

	dir.list_dir_end()

	print("加载 Disease 数量：", disease_list.size())


## =========================================================
## 六、获取当前 NPC
##
## 功能：
## 返回当前索引对应的 NPC
## =========================================================
func get_current_npc() -> NpcData:
	if npc_list.is_empty():
		return null

	return npc_list[current_index]


## =========================================================
## 七、切换到下一个 NPC
##
## 功能：
## 索引 +1，超出则回到第一个
## =========================================================
func next_npc() -> NpcData:
	if npc_list.is_empty():
		return null

	current_index += 1

	if current_index >= npc_list.size():
		current_index = 0

	return npc_list[current_index]


## =========================================================
## 八、切换到上一个 NPC
##
## 功能：
## 索引 -1，小于 0 则跳到最后一个
## =========================================================
func prev_npc() -> NpcData:
	if npc_list.is_empty():
		return null

	current_index -= 1

	if current_index < 0:
		current_index = npc_list.size() - 1

	return npc_list[current_index]


## =========================================================
## 九、设置 NPC 列表
##
## 功能：
## 外部直接替换当前 NPC 列表
## =========================================================
func set_npc_list(new_list: Array[NpcData]) -> void:
	npc_list = new_list
	current_index = 0


## =========================================================
## 十、获取 NPC 数量
## =========================================================
func get_npc_count() -> int:
	return npc_list.size()


## =========================================================
## 十一、获取 Disease 数量
## =========================================================
func get_disease_count() -> int:
	return disease_list.size()


## =========================================================
## 十二、随机生成姓名
##
## 功能：
## 根据性别生成一个中文姓名
## =========================================================
func generate_random_name(gender: String) -> String:
	var family_name = family_names.pick_random()

	if gender == "女":
		return family_name + given_names_female.pick_random()

	return family_name + given_names_male.pick_random()


## =========================================================
## 十三、随机获取一个疾病
##
## 功能：
## 从 disease_list 中随机抽取一个 DiseaseData
##
## 返回值：
## - DiseaseData
## - 如果 disease_list 为空，返回 null
## =========================================================
func get_random_disease() -> DiseaseData:
	if disease_list.is_empty():
		return null

	return disease_list.pick_random()


## =========================================================
## 十四、随机生成一个 NPC
##
## 功能：
## 创建新的 NpcData，并随机设置：
## - npc_id
## - 姓名
## - 性别
## - 年龄
## - 疾病
##
## 说明：
## 这里的疾病直接从 Disease 文件夹加载的数据中随机抽取
## =========================================================
func generate_random_npc() -> NpcData:
	var npc := NpcData.new()

	npc.npc_id = "runtime_" + str(Time.get_unix_time_from_system()) + "_" + str(randi())

	var genders := ["男", "女"]
	npc.gender = genders.pick_random()

	npc.npc_name = generate_random_name(npc.gender)
	npc.age = randi_range(16, 70)

	## 直接从 disease_list 随机取病
	npc.disease = get_random_disease()

	npc.is_treated = false

	return npc


## =========================================================
## 十五、生成新病人并加入列表
##
## 功能：
## 生成一个随机 NPC
## 加入 npc_list
## 并自动切换到这个 NPC
## =========================================================
func spawn_random_npc() -> NpcData:
	var npc := generate_random_npc()

	npc_list.append(npc)
	current_index = npc_list.size() - 1

	return npc


## =========================================================
## 十六、移除当前 NPC
##
## 功能：
## 从 npc_list 中删除当前 NPC
## =========================================================
func remove_current_npc() -> void:
	if npc_list.is_empty():
		return

	npc_list.remove_at(current_index)

	if npc_list.is_empty():
		current_index = 0
		return

	if current_index >= npc_list.size():
		current_index = npc_list.size() - 1


## =========================================================
## 十七、重新加载模板
##
## 功能：
## 重新加载 Npc 和 Disease 文件夹中的资源
## =========================================================
func reload_templates() -> void:
	load_all_npcs()
	load_all_diseases()


## =========================================================
## 十八、调试打印当前 NPC
## =========================================================
func debug_current_npc() -> void:
	var npc := get_current_npc()

	if npc == null:
		print("当前没有 NPC")
		return

	print("当前 NPC 索引：", current_index)
	npc.debug_print()


## =========================================================
## 十九、调试打印全部 NPC
## =========================================================
func debug_print_all_npcs() -> void:
	if npc_list.is_empty():
		print("当前 npc_list 为空")
		return

	print("==== 当前 NPC 列表 ====")

	for i in range(npc_list.size()):
		var npc := npc_list[i]

		if npc == null:
			print(i, ": null")
			continue

		var disease_name := "无疾病"

		if npc.disease != null:
			disease_name = npc.disease.disease_name

		print(i, ": ", npc.npc_name, " | ", npc.gender, " | ", npc.age, "岁 | 疾病：", disease_name)


## =========================================================
## 二十、调试打印全部 Disease
##
## 功能：
## 打印当前已加载的所有疾病
## =========================================================
func debug_print_all_diseases() -> void:
	if disease_list.is_empty():
		print("当前 disease_list 为空")
		return

	print("==== 当前 Disease 列表 ====")

	for i in range(disease_list.size()):
		var disease := disease_list[i]

		if disease == null:
			print(i, ": null")
			continue

		print(i, ": ", disease.disease_name)
