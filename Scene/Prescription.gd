extends RefCounted
class_name Prescription

# 四个区域
var jun_herbs: Array[Dictionary] = []
var chen_herbs: Array[Dictionary] = []
var zuo_herbs: Array[Dictionary] = []
var shi_herbs: Array[Dictionary] = []

# 兼容旧代码
var herbs: Array[Dictionary]:
	get:
		return get_all_herbs()


func clear() -> void:
	jun_herbs.clear()
	chen_herbs.clear()
	zuo_herbs.clear()
	shi_herbs.clear()


func is_empty() -> bool:
	return (
		jun_herbs.is_empty()
		and chen_herbs.is_empty()
		and zuo_herbs.is_empty()
		and shi_herbs.is_empty()
	)


func add_herb(herb: HerbData, amount: float, unit: String = "qian", role_name: String = "君") -> bool:
	if herb == null:
		return false

	if herb.herb_id.strip_edges() == "":
		return false

	if amount <= 0.0:
		return false

	if not HerbUnit.is_valid_unit(unit):
		return false

	if not _is_valid_role(role_name):
		return false

	# 先删除旧的，避免一味药同时存在多个区
	remove_herb(herb.herb_id)

	var entry: Dictionary = {
		"herb_id": herb.herb_id,
		"herb_name": herb.herb_name,
		"amount": amount,
		"unit": unit,
		"herb_data": herb
	}

	match role_name:
		"君":
			jun_herbs.append(entry)
		"臣":
			chen_herbs.append(entry)
		"佐":
			zuo_herbs.append(entry)
		"使":
			shi_herbs.append(entry)

	return true


func remove_herb(herb_id: String) -> void:
	_remove_from_group(jun_herbs, herb_id)
	_remove_from_group(chen_herbs, herb_id)
	_remove_from_group(zuo_herbs, herb_id)
	_remove_from_group(shi_herbs, herb_id)


func set_herb_amount_and_unit(herb_id: String, amount: float, unit: String) -> bool:
	if herb_id.strip_edges() == "":
		return false

	if amount <= 0.0:
		return false

	if not HerbUnit.is_valid_unit(unit):
		return false

	for group in [jun_herbs, chen_herbs, zuo_herbs, shi_herbs]:
		for i in range(group.size()):
			if group[i].get("herb_id", "") == herb_id:
				group[i]["amount"] = amount
				group[i]["unit"] = unit
				return true

	return false


func get_herb_entry(herb_id: String) -> Dictionary:
	for group in [jun_herbs, chen_herbs, zuo_herbs, shi_herbs]:
		for item in group:
			if item.get("herb_id", "") == herb_id:
				return item
	return {}


func get_herbs_by_role(role_name: String) -> Array[Dictionary]:
	match role_name:
		"君":
			return jun_herbs.duplicate(true)
		"臣":
			return chen_herbs.duplicate(true)
		"佐":
			return zuo_herbs.duplicate(true)
		"使":
			return shi_herbs.duplicate(true)
		_:
			return []


func get_all_herbs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(jun_herbs.duplicate(true))
	result.append_array(chen_herbs.duplicate(true))
	result.append_array(zuo_herbs.duplicate(true))
	result.append_array(shi_herbs.duplicate(true))
	return result


func get_herb_role(herb_id: String) -> String:
	if _has_herb(jun_herbs, herb_id):
		return "君"
	if _has_herb(chen_herbs, herb_id):
		return "臣"
	if _has_herb(zuo_herbs, herb_id):
		return "佐"
	if _has_herb(shi_herbs, herb_id):
		return "使"
	return ""


func to_fen_map() -> Dictionary:
	var result: Dictionary = {}

	for item in get_all_herbs():
		var herb_id: String = str(item.get("herb_id", "")).strip_edges()
		var amount: float = float(item.get("amount", 0.0))
		var unit: String = str(item.get("unit", "")).strip_edges()

		if herb_id == "":
			continue
		if amount <= 0.0:
			continue
		if not HerbUnit.is_valid_unit(unit):
			continue

		result[herb_id] = HerbUnit.to_fen(amount, unit)

	return result


func build_role_maps() -> Dictionary:
	var fen_map: Dictionary = {}
	var name_map: Dictionary = {}
	var role_map: Dictionary = {}

	_append_group_to_maps(jun_herbs, "君", fen_map, name_map, role_map)
	_append_group_to_maps(chen_herbs, "臣", fen_map, name_map, role_map)
	_append_group_to_maps(zuo_herbs, "佐", fen_map, name_map, role_map)
	_append_group_to_maps(shi_herbs, "使", fen_map, name_map, role_map)

	return {
		"fen_map": fen_map,
		"name_map": name_map,
		"role_map": role_map
	}


func get_display_text() -> String:
	var lines: Array[String] = []
	lines.append("君：" + _build_group_text(jun_herbs))
	lines.append("臣：" + _build_group_text(chen_herbs))
	lines.append("佐：" + _build_group_text(zuo_herbs))
	lines.append("使：" + _build_group_text(shi_herbs))
	return "\n".join(lines)


func _append_group_to_maps(
	group: Array[Dictionary],
	role_name: String,
	fen_map: Dictionary,
	name_map: Dictionary,
	role_map: Dictionary
) -> void:
	for item in group:
		var herb_id: String = str(item.get("herb_id", "")).strip_edges()
		var herb_name: String = str(item.get("herb_name", herb_id)).strip_edges()
		var amount: float = float(item.get("amount", 0.0))
		var unit: String = str(item.get("unit", "")).strip_edges()

		if herb_id == "":
			continue
		if amount <= 0.0:
			continue
		if not HerbUnit.is_valid_unit(unit):
			continue

		fen_map[herb_id] = HerbUnit.to_fen(amount, unit)
		name_map[herb_id] = herb_name
		role_map[herb_id] = role_name


func _remove_from_group(group: Array[Dictionary], herb_id: String) -> void:
	for i in range(group.size() - 1, -1, -1):
		if group[i].get("herb_id", "") == herb_id:
			group.remove_at(i)


func _has_herb(group: Array[Dictionary], herb_id: String) -> bool:
	for item in group:
		if item.get("herb_id", "") == herb_id:
			return true
	return false


func _is_valid_role(role_name: String) -> bool:
	return role_name == "君" or role_name == "臣" or role_name == "佐" or role_name == "使"


func _build_group_text(group: Array[Dictionary]) -> String:
	if group.is_empty():
		return "（无）"

	var parts: Array[String] = []
	for item in group:
		parts.append("%s %s" % [
			item.get("herb_name", ""),
			HerbUnit.format_amount(float(item.get("amount", 0.0)), str(item.get("unit", "")))
		])
	return "、".join(parts)
