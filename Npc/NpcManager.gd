extends Node

# NPC 模板列表（固定资源）
var npc_template_list: Array[NpcData] = []

# 当前可切换的 NPC 列表（运行时）
var npc_list: Array[NpcData] = []

# 疾病列表
var disease_list: Array[DiseaseData] = []

# 当前查看索引
var current_index: int = 0


# 随机姓名库
const SURNAMES := [
	"李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴",
	"徐", "孙", "胡", "朱", "高", "林", "何", "郭", "马", "罗"
]

const GIVEN_NAMES := [
	"一川", "子安", "明远", "承泽", "景行", "修远", "子墨", "安然",
	"若琳", "清雅", "诗雨", "梦瑶", "婉晴", "子涵", "思源", "景辰",
	"若曦", "星河", "知远", "承恩"
]


func _ready() -> void:
	randomize()
	load_all_npcs()
	load_all_diseases()


# 加载所有 NPC 模板
func load_all_npcs() -> void:
	npc_list.clear()
	npc_template_list.clear()
	current_index = 0

	var dir := DirAccess.open("res://Npc/data")

	if dir == null:
		print("Npc/data 文件夹不存在")
		return

	dir.list_dir_begin()
	var file := dir.get_next()

	while file != "":
		if file.ends_with(".tres") or file.ends_with(".res"):
			var path := "res://Npc/data/" + file
			var npc = load(path)

			if npc is NpcData:
				npc_template_list.append(npc)
				npc_list.append(npc)

		file = dir.get_next()

	dir.list_dir_end()

	print("加载 NPC 模板数量：", npc_template_list.size())
	print("当前 NPC 列表数量：", npc_list.size())


# 加载所有 Disease
func load_all_diseases() -> void:
	disease_list.clear()

	var dir := DirAccess.open("res://Disease/data")

	if dir == null:
		print("Disease/data 文件夹不存在")
		return

	dir.list_dir_begin()
	var file := dir.get_next()

	while file != "":
		if file.ends_with(".tres") or file.ends_with(".res"):
			var path := "res://Disease/data/" + file
			var disease = load(path)

			if disease is DiseaseData:
				disease_list.append(disease)

		file = dir.get_next()

	dir.list_dir_end()

	print("加载 Disease 数量：", disease_list.size())


# 获取当前 NPC
func get_current_npc() -> NpcData:
	if npc_list.is_empty():
		return null

	if current_index < 0 or current_index >= npc_list.size():
		current_index = 0

	return npc_list[current_index]


# 上一个 NPC
func prev_npc() -> void:
	if npc_list.is_empty():
		return

	current_index -= 1

	if current_index < 0:
		current_index = npc_list.size() - 1


# 下一个 NPC
func next_npc() -> void:
	if npc_list.is_empty():
		return

	current_index += 1

	if current_index >= npc_list.size():
		current_index = 0


# 随机姓名
func random_name() -> String:
	var surname = SURNAMES[randi() % SURNAMES.size()]
	var given = GIVEN_NAMES[randi() % GIVEN_NAMES.size()]
	return surname + given


# 随机性别
func random_gender() -> String:
	return "男" if randi() % 2 == 0 else "女"


# 随机年龄
func random_age() -> int:
	return randi_range(16, 70)


# 生成一个随机 NPC
func generate_random_npc() -> NpcData:
	if npc_template_list.is_empty():
		print("没有 NPC 模板，无法生成")
		return null

	if disease_list.is_empty():
		print("没有 Disease 数据，无法生成")
		return null

	var template: NpcData = npc_template_list[randi() % npc_template_list.size()]
	var disease: DiseaseData = disease_list[randi() % disease_list.size()]

	var npc := NpcData.new()

	# 保留模板中的基础 ID 作为来源参考
	npc.npc_id = template.npc_id

	# 生成时随机人物信息
	npc.npc_name = random_name()
	npc.gender = random_gender()
	npc.age = random_age()

	# 运行时状态
	npc.disease = disease
	npc.is_treated = false

	return npc


# 生成并加入当前列表
func spawn_random_npc() -> NpcData:
	var npc := generate_random_npc()

	if npc == null:
		return null

	npc_list.append(npc)
	current_index = npc_list.size() - 1

	print("生成新 NPC：", npc.npc_name)
	print("当前 NPC 列表数量：", npc_list.size())

	return npc
