## =========================================================
## NpcManager.gd
##
## 脚本功能：
## 管理 NPC 数据的加载与切换。
##
## 当前 NPC 规则：
## - Data/Npc 下的 .tres / .res 全部视为预制 NPC 数据。
## - npc_type = "random"：平日诊室刷新时，从 random NPC 池中随机抽取。
## - npc_type = "story"：剧情触发时，按 npc_id 精确选择对应 story NPC。
## - 抽取出来的 NPC 会 duplicate(true)，避免修改 .tres 原始资源。
## =========================================================

extends Node

# 平日常规病人池。
var random_npc_pool: Array[NpcData] = []

# 剧情病人表。
# key = npc_id
# value = NpcData
var story_npc_by_id: Dictionary = {}

# 当前可切换的 NPC 列表（运行时病人实例）。
var npc_list: Array[NpcData] = []

# 当前查看索引。
var current_index: int = 0

# NPC 资源根目录。支持子文件夹递归扫描。
const NPC_DIR := "res://Data/Npc"


# ============================================================
# 生命周期初始化
# ============================================================

func _ready() -> void:
	randomize()
	load_all_npcs()


# ============================================================
# 数据加载
# ============================================================

# 函数功能：
# 从 res://Data/Npc 目录递归加载所有 NPC 资源。
# 资源按 NpcData.npc_type 分为 random 与 story 两类。
func load_all_npcs() -> void:
	npc_list.clear()
	random_npc_pool.clear()
	story_npc_by_id.clear()
	current_index = 0

	_scan_npc_dir(NPC_DIR)

	print("加载 random NPC 数量：", random_npc_pool.size())
	print("加载 story NPC 数量：", story_npc_by_id.size())
	print("当前运行时 NPC 列表数量：", npc_list.size())


func _scan_npc_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("NPC 文件夹不存在：%s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue

		var full_path := dir_path.path_join(file_name)

		if dir.current_is_dir():
			_scan_npc_dir(full_path)
		else:
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				_load_npc_resource(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


func _load_npc_resource(path: String) -> void:
	var loaded_resource := load(path)
	if loaded_resource == null:
		push_warning("NPC 资源加载失败：%s" % path)
		return

	if not loaded_resource is NpcData:
		push_warning("加载的资源不是 NpcData：%s" % path)
		return

	var npc := loaded_resource as NpcData
	var npc_type := npc.npc_type.strip_edges().to_lower()

	# 兼容旧数据：没有写 npc_type 的 NPC 默认视为 random。
	if npc_type == "" or npc_type == "random":
		random_npc_pool.append(npc)
		return

	if npc_type == "story":
		var npc_id := npc.npc_id.strip_edges()
		if npc_id == "":
			push_warning("story NPC 缺少 npc_id：%s" % path)
			return

		if story_npc_by_id.has(npc_id):
			push_warning("重复的 story NPC npc_id：%s，后加载的资源会覆盖前一个。" % npc_id)

		story_npc_by_id[npc_id] = npc
		return

	push_warning("未知 npc_type：%s，路径：%s" % [npc_type, path])


# ============================================================
# 当前 NPC 获取与切换
# ============================================================

func get_current_npc() -> NpcData:
	if npc_list.is_empty():
		return null

	if current_index < 0 or current_index >= npc_list.size():
		current_index = 0

	return npc_list[current_index]


func prev_npc() -> void:
	if npc_list.is_empty():
		return

	current_index -= 1
	if current_index < 0:
		current_index = npc_list.size() - 1


func next_npc() -> void:
	if npc_list.is_empty():
		return

	current_index += 1
	if current_index >= npc_list.size():
		current_index = 0


# ============================================================
# NPC 实例化
# ============================================================

func _make_runtime_npc(source_npc: NpcData, forced_type: String = "") -> NpcData:
	if source_npc == null:
		return null

	var npc := source_npc.duplicate(true) as NpcData
	if npc == null:
		return null

	if forced_type != "":
		npc.npc_type = forced_type.strip_edges().to_lower()
	else:
		npc.npc_type = npc.npc_type.strip_edges().to_lower()

	# random NPC 每次进入 Clinic 时，随机绑定一个“已经解锁”的疾病。
	# 注意：这里会覆盖 random NPC .tres 里原本可能填写的 disease。
	if npc.npc_type == "random":
		_assign_random_unlocked_disease(npc)

	# 疾病绑定完成后，再初始化本次诊疗状态和本次固定台词。
	if npc.has_method("setup_clinic_visit"):
		npc.setup_clinic_visit()
	else:
		npc.is_treated = false

	return npc


func _assign_random_unlocked_disease(npc: NpcData) -> void:
	if npc == null:
		return

	var unlocked_diseases := _get_unlocked_disease_pool()
	if unlocked_diseases.is_empty():
		push_warning("NpcManager: 当前没有已解锁疾病，无法给 random NPC 分配疾病。")
		npc.disease = null
		return

	npc.disease = unlocked_diseases[randi() % unlocked_diseases.size()]


func _get_unlocked_disease_pool() -> Array[DiseaseData]:
	var result: Array[DiseaseData] = []

	if Unlock == null:
		push_warning("NpcManager: Unlock 不存在，无法读取已解锁疾病。")
		return result

	if DiseaseDB == null:
		push_warning("NpcManager: DiseaseDB 不存在，无法读取疾病数据。")
		return result

	if not Unlock.has_method("get_unlocked_disease_id_list"):
		push_warning("NpcManager: Unlock 缺少 get_unlocked_disease_id_list()。")
		return result

	if not DiseaseDB.has_method("get_disease"):
		push_warning("NpcManager: DiseaseDB 缺少 get_disease()。")
		return result

	var unlocked_ids: Array[String] = Unlock.get_unlocked_disease_id_list()

	for disease_id in unlocked_ids:
		var clean_id := disease_id.strip_edges()
		if clean_id == "":
			continue

		var disease := DiseaseDB.get_disease(clean_id)
		if disease == null:
			push_warning("NpcManager: 已解锁疾病 ID 找不到对应 DiseaseData：%s" % clean_id)
			continue

		result.append(disease)

	return result


# ============================================================
# random NPC：平日刷新用
# ============================================================

func get_random_npc_template() -> NpcData:
	if random_npc_pool.is_empty():
		return null

	return random_npc_pool[randi() % random_npc_pool.size()]


func generate_random_npc() -> NpcData:
	var source_npc := get_random_npc_template()
	if source_npc == null:
		push_warning("没有 random NPC，无法抽取平日病人。请在 Data/Npc 下创建 npc_type = random 的 NpcData。")
		return null

	return _make_runtime_npc(source_npc, "random")


func spawn_random_npc() -> NpcData:
	var npc := generate_random_npc()
	if npc == null:
		return null

	npc_list.append(npc)
	current_index = npc_list.size() - 1

	print("抽取 random NPC：", npc.npc_name, " / ", npc.npc_id)
	if npc.disease != null:
		print("random NPC 疾病：", npc.disease.disease_name)
	print("当前运行时 NPC 列表数量：", npc_list.size())

	return npc


func replace_with_random_npc() -> NpcData:
	npc_list.clear()
	current_index = 0
	return spawn_random_npc()


# ============================================================
# story NPC：剧情指定用
# ============================================================

func has_story_npc(npc_id: String) -> bool:
	var clean_id := npc_id.strip_edges()
	if clean_id == "":
		return false

	return story_npc_by_id.has(clean_id)


func get_story_npc_template(npc_id: String) -> NpcData:
	var clean_id := npc_id.strip_edges()
	if clean_id == "":
		return null

	if not story_npc_by_id.has(clean_id):
		return null

	return story_npc_by_id[clean_id] as NpcData


func generate_story_npc(npc_id: String) -> NpcData:
	var source_npc := get_story_npc_template(npc_id)
	if source_npc == null:
		push_warning("找不到 story NPC：%s。请检查 Data/Npc 下是否存在 npc_type = story 且 npc_id 匹配的资源。" % npc_id)
		return null

	return _make_runtime_npc(source_npc, "story")


func spawn_story_npc(npc_id: String) -> NpcData:
	var npc := generate_story_npc(npc_id)
	if npc == null:
		return null

	npc_list.append(npc)
	current_index = npc_list.size() - 1

	print("抽取 story NPC：", npc.npc_name, " / ", npc.npc_id)
	if npc.disease != null:
		print("story NPC 疾病：", npc.disease.disease_name)
	print("当前运行时 NPC 列表数量：", npc_list.size())

	return npc


func replace_with_story_npc(npc_id: String) -> NpcData:
	npc_list.clear()
	current_index = 0
	return spawn_story_npc(npc_id)
