## =========================================================
## 脚本功能：
## 管理 NPC 数据的加载、切换与随机生成。
## 负责从资源目录读取 NPC 模板，从 DiseaseDB 读取疾病数据，
## 并根据模板和疾病数据生成运行时 NPC。
## =========================================================

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


# ============================================================
# 生命周期初始化
# ============================================================

# 函数功能：
# 节点进入场景树后执行初始化。
# 初始化随机数种子，并加载 NPC 模板和疾病数据。
func _ready() -> void:
	randomize()
	load_all_npcs()
	load_all_diseases_from_database()


# ============================================================
# 数据加载
# ============================================================

# 函数功能：
# 从 res://Data/Npc 目录中加载所有 NPC 模板资源。
# 加载成功后同时写入 NPC 模板列表和当前 NPC 列表。
func load_all_npcs() -> void:
	npc_list.clear()
	npc_template_list.clear()
	current_index = 0

	var dir := DirAccess.open("res://Data/Npc")

	if dir == null:
		print("Npc/data 文件夹不存在")
		return

	dir.list_dir_begin()
	var file := dir.get_next()

	while file != "":
		if file.ends_with(".tres") or file.ends_with(".res"):
			var path := "res://Data/Npc/" + file
			var npc = load(path)

			if npc is NpcData:
				npc_template_list.append(npc)
				npc_list.append(npc)

		file = dir.get_next()

	dir.list_dir_end()

	print("加载 NPC 模板数量：", npc_template_list.size())
	print("当前 NPC 列表数量：", npc_list.size())


# 函数功能：
# 从 DiseaseDB 中读取所有疾病数据。
# 随机生成 NPC 时会从该列表中随机分配疾病。
func load_all_diseases_from_database() -> void:
	disease_list.clear()

	if DiseaseDB == null:
		print("DiseaseDB 不存在")
		return

	disease_list = DiseaseDB.get_all_diseases()

	print("从 DiseaseDB 加载 Disease 数量：", disease_list.size())


# ============================================================
# 当前 NPC 获取与切换
# ============================================================

# 函数功能：
# 获取当前索引对应的 NPC。
# 如果列表为空则返回 null；如果索引越界则重置到第一个 NPC。
func get_current_npc() -> NpcData:
	if npc_list.is_empty():
		return null

	if current_index < 0 or current_index >= npc_list.size():
		current_index = 0

	return npc_list[current_index]


# 函数功能：
# 将当前 NPC 切换到上一个。
# 如果已经位于第一个 NPC，则循环切换到最后一个 NPC。
func prev_npc() -> void:
	if npc_list.is_empty():
		return

	current_index -= 1

	if current_index < 0:
		current_index = npc_list.size() - 1


# 函数功能：
# 将当前 NPC 切换到下一个。
# 如果已经位于最后一个 NPC，则循环切换到第一个 NPC。
func next_npc() -> void:
	if npc_list.is_empty():
		return

	current_index += 1

	if current_index >= npc_list.size():
		current_index = 0


# ============================================================
# 随机基础信息生成
# ============================================================

# 函数功能：
# 从姓氏库和名字库中随机组合一个 NPC 姓名。
func random_name() -> String:
	var surname = SURNAMES[randi() % SURNAMES.size()]
	var given = GIVEN_NAMES[randi() % GIVEN_NAMES.size()]
	return surname + given


# 函数功能：
# 随机生成 NPC 性别。
func random_gender() -> String:
	return "男" if randi() % 2 == 0 else "女"


# 函数功能：
# 随机生成 NPC 年龄。
# 当前年龄范围为 16 到 70 岁。
func random_age() -> int:
	return randi_range(16, 70)


# ============================================================
# 随机 NPC 创建与加入列表
# ============================================================

# 函数功能：
# 根据随机 NPC 模板和随机疾病生成一个新的运行时 NPC。
# 生成失败时返回 null。
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


# 函数功能：
# 生成一个随机 NPC，并加入当前 NPC 列表。
# 生成成功后会自动切换到新生成的 NPC。
func spawn_random_npc() -> NpcData:
	var npc := generate_random_npc()

	if npc == null:
		return null

	npc_list.append(npc)
	current_index = npc_list.size() - 1

	print("生成新 NPC：", npc.npc_name)
	print("当前 NPC 列表数量：", npc_list.size())

	return npc
