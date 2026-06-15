## =========================================================
## NpcManager.gd
##
## 脚本功能：
## 管理 NPC 数据的加载、切换与随机生成。
##
## 当前随机 NPC 规则：
## - Data/Npc 下的 .tres 只作为随机 NPC 模板读取，不再直接塞进当前病人列表。
## - 平时接诊用 spawn_random_npc() 生成运行时随机 NPC。
## - 随机 NPC 会随机姓名、性别、年龄、疾病，并按性别年龄随机抽取立绘。
## - 每个随机 NPC 会生成唯一 npc_id，避免多个病人共用模板 ID。
## =========================================================

extends Node

# NPC 模板列表（固定资源，只作为随机生成参考，不直接当成当前病人）
var npc_template_list: Array[NpcData] = []

# 当前可切换的 NPC 列表（运行时病人）
var npc_list: Array[NpcData] = []

# 疾病列表
var disease_list: Array[DiseaseData] = []

# 当前查看索引
var current_index: int = 0

# 已生成的随机 NPC 数量，用于生成唯一运行时 ID。
var random_npc_spawn_count: int = 0

# 随机 NPC 立绘根目录。
# 请在此目录下建立：
# - male_young
# - male_adult
# - male_old
# - female_young
# - female_adult
# - female_old
const RANDOM_PORTRAIT_ROOT := "res://Assets/Portrait/RandomNPC"


# 随机姓名库
const SURNAMES := [
	"李", "王", "张", "刘", "陈", "杨", "赵", "黄", "周", "吴",
	"徐", "孙", "胡", "朱", "高", "林", "何", "郭", "马", "罗"
]

const MALE_GIVEN_NAMES := [
	"一川", "子安", "明远", "承泽", "景行", "修远", "子墨", "思源",
	"景辰", "星河", "知远", "承恩", "怀瑾", "云舟", "清和", "远山"
]

const FEMALE_GIVEN_NAMES := [
	"安然", "若琳", "清雅", "诗雨", "梦瑶", "婉晴", "子涵", "若曦",
	"映雪", "青黛", "云舒", "知夏", "听雨", "月白", "兰因", "书瑶"
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

	# 诊室初始没有病人时，自动生成一位常规随机病人。
	if npc_list.is_empty():
		spawn_random_npc()


# ============================================================
# 数据加载
# ============================================================

# 函数功能：
# 从 res://Data/Npc 目录中加载所有 NPC 模板资源。
# 注意：
# - 这里加载到 npc_template_list。
# - 不再直接写入 npc_list。
# - npc_list 只保存运行时真正出现的病人。
func load_all_npcs() -> void:
	npc_list.clear()
	npc_template_list.clear()
	current_index = 0
	random_npc_spawn_count = 0

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

		file = dir.get_next()

	dir.list_dir_end()

	print("加载 NPC 随机模板数量：", npc_template_list.size())
	print("当前运行时 NPC 列表数量：", npc_list.size())


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
# 如果列表为空，会尝试自动生成一个随机 NPC。
func get_current_npc() -> NpcData:
	if npc_list.is_empty():
		spawn_random_npc()

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
		spawn_random_npc()
		return

	current_index -= 1

	if current_index < 0:
		current_index = npc_list.size() - 1


# 函数功能：
# 将当前 NPC 切换到下一个。
# 如果已经位于最后一个 NPC，则循环切换到第一个 NPC。
func next_npc() -> void:
	if npc_list.is_empty():
		spawn_random_npc()
		return

	current_index += 1

	if current_index >= npc_list.size():
		current_index = 0


# ============================================================
# 随机基础信息生成
# ============================================================

# 函数功能：
# 从姓氏库和名字库中随机组合一个 NPC 姓名。
func random_name(gender: String = "") -> String:
	var surname = SURNAMES[randi() % SURNAMES.size()]
	var given_names := MALE_GIVEN_NAMES

	if gender == "女":
		given_names = FEMALE_GIVEN_NAMES
	elif gender != "男" and randi() % 2 == 1:
		given_names = FEMALE_GIVEN_NAMES

	var given = given_names[randi() % given_names.size()]
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
# 随机立绘
# ============================================================

# 函数功能：
# 按年龄划分立绘年龄段。
# 16 - 29：young
# 30 - 54：adult
# 55+：old
func _get_age_group(age: int) -> String:
	if age < 30:
		return "young"

	if age < 55:
		return "adult"

	return "old"


# 函数功能：
# 把中文性别转换成随机立绘文件夹使用的英文前缀。
func _get_gender_folder(gender: String) -> String:
	if gender == "女":
		return "female"

	return "male"


# 函数功能：
# 根据性别和年龄得到随机立绘目录。
func _get_portrait_folder(gender: String, age: int) -> String:
	return "%s/%s_%s" % [
		RANDOM_PORTRAIT_ROOT,
		_get_gender_folder(gender),
		_get_age_group(age)
	]


# 函数功能：
# 读取目录下可作为 Texture2D 加载的图片文件。
func _get_texture_files_in_folder(folder_path: String) -> Array[String]:
	var result: Array[String] = []

	var dir := DirAccess.open(folder_path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir():
			var lower_name := file_name.to_lower()
			var is_texture_file := false
			is_texture_file = is_texture_file or lower_name.ends_with(".png")
			is_texture_file = is_texture_file or lower_name.ends_with(".jpg")
			is_texture_file = is_texture_file or lower_name.ends_with(".jpeg")
			is_texture_file = is_texture_file or lower_name.ends_with(".webp")

			if is_texture_file:
				result.append(folder_path + "/" + file_name)

		file_name = dir.get_next()

	dir.list_dir_end()
	return result


# 函数功能：
# 根据随机 NPC 的性别、年龄，从对应目录随机抽取一张立绘。
# 如果目录不存在、目录为空或图片加载失败，则回退到模板自带 portrait。
func _get_random_portrait(gender: String, age: int, fallback_portrait: Texture2D = null) -> Texture2D:
	var folder_path := _get_portrait_folder(gender, age)
	var files := _get_texture_files_in_folder(folder_path)

	if files.is_empty():
		push_warning("随机 NPC 立绘目录为空或不存在：%s，将使用模板立绘。" % folder_path)
		return fallback_portrait

	var file_path: String = files[randi() % files.size()]
	var texture = load(file_path)

	if texture is Texture2D:
		return texture

	push_warning("随机 NPC 立绘加载失败：%s，将使用模板立绘。" % file_path)
	return fallback_portrait


# ============================================================
# 随机 NPC 创建与加入列表
# ============================================================

func _get_random_template() -> NpcData:
	if npc_template_list.is_empty():
		return null

	return npc_template_list[randi() % npc_template_list.size()]


func _get_random_disease() -> DiseaseData:
	if disease_list.is_empty():
		return null

	return disease_list[randi() % disease_list.size()]


func _make_random_npc_id(template: NpcData) -> String:
	random_npc_spawn_count += 1

	var template_id := "template"
	if template != null:
		template_id = template.npc_id.strip_edges()
		if template_id == "":
			template_id = "template"

	return "random_%s_%04d" % [template_id, random_npc_spawn_count]


# 函数功能：
# 根据随机 NPC 模板和随机疾病生成一个新的运行时 NPC。
# 生成失败时返回 null。
func generate_random_npc() -> NpcData:
	if npc_template_list.is_empty():
		print("没有 NPC 模板，无法生成随机 NPC")
		return null

	if disease_list.is_empty():
		print("没有 Disease 数据，无法生成随机 NPC")
		return null

	var template := _get_random_template()
	var disease := _get_random_disease()

	if template == null or disease == null:
		return null

	var npc := NpcData.new()

	# 生成唯一运行时 ID，并记录来源模板。
	npc.npc_id = _make_random_npc_id(template)
	npc.npc_type = "random"
	npc.source_template_id = template.npc_id.strip_edges()

	# 生成时随机人物信息。
	var generated_gender := random_gender()
	var generated_age := random_age()
	npc.gender = generated_gender
	npc.npc_name = random_name(generated_gender)
	npc.age = generated_age

	# 根据性别和年龄随机抽取立绘。
	# 如果对应目录没有图片，则自动回退到模板自带立绘。
	npc.portrait = _get_random_portrait(generated_gender, generated_age, template.portrait)

	# 运行时状态。
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

	print("生成随机 NPC：", npc.npc_name, " / ", npc.npc_id)
	if npc.disease != null:
		print("随机 NPC 疾病：", npc.disease.disease_name)
	print("当前运行时 NPC 列表数量：", npc_list.size())

	return npc


# 函数功能：
# 清空当前运行时病人，并生成一个新的随机病人。
# 如果你希望“换下一位普通病人”时不保留旧随机病人，可以调用这个函数。
func replace_with_random_npc() -> NpcData:
	npc_list.clear()
	current_index = 0
	return spawn_random_npc()
