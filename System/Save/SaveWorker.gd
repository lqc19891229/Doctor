extends RefCounted

# =========================================================
# SaveWorker
# 只在后台线程中处理“纯数据 -> JSON -> 磁盘”。
# 不读取/修改任何 Node、SceneTree、Resource 或 Autoload 状态。
# =========================================================

func write_request(request: Dictionary) -> Dictionary:
	var slot_index := int(request.get("slot_index", -1))
	var save_path := String(request.get("save_path", ""))
	var temp_path := String(request.get("temp_path", ""))
	var backup_path := String(request.get("backup_path", ""))
	var save_absolute := String(request.get("save_absolute", ""))
	var temp_absolute := String(request.get("temp_absolute", ""))
	var backup_absolute := String(request.get("backup_absolute", ""))
	var save_data = request.get("save_data", {})

	if save_path.is_empty() or temp_path.is_empty() or backup_path.is_empty():
		return _failure(request, "存档路径为空。")

	if typeof(save_data) != TYPE_DICTIONARY:
		return _failure(request, "存档快照不是 Dictionary。")

	# 先处理上一次进程可能留下的 .tmp / .bak。
	var recovery := _recover_interrupted_save(
		save_path,
		temp_path,
		backup_path,
		save_absolute,
		temp_absolute,
		backup_absolute
	)
	if not bool(recovery.get("ok", false)):
		return _failure(request, String(recovery.get("error", "无法恢复中断的存档事务。")))

	# 正式构建中不再输出缩进 JSON，减少序列化量和磁盘写入量。
	var json_text := JSON.stringify(save_data)
	if json_text.is_empty():
		return _failure(request, "JSON 序列化结果为空。")

	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _failure(request, "无法打开临时存档文件：%s" % temp_path)

	file.store_string(json_text)
	file.flush()
	var write_error := file.get_error()
	file.close()

	if write_error != OK:
		_remove_file_if_exists(temp_path, temp_absolute)
		return _failure(
			request,
			"临时存档写入错误：%s，错误码：%d" % [temp_path, write_error]
		)

	var commit := _commit_temp_save(
		save_path,
		temp_path,
		backup_path,
		save_absolute,
		temp_absolute,
		backup_absolute
	)
	if not bool(commit.get("ok", false)):
		return _failure(request, String(commit.get("error", "无法提交临时存档。")))

	return {
		"ok": true,
		"slot_index": slot_index,
		"day": int(request.get("day", 1)),
		"phase": String(request.get("phase", "")),
		"context": String(request.get("context", ""))
	}


func _failure(request: Dictionary, message: String) -> Dictionary:
	return {
		"ok": false,
		"slot_index": int(request.get("slot_index", -1)),
		"day": int(request.get("day", 1)),
		"phase": String(request.get("phase", "")),
		"context": String(request.get("context", "")),
		"error": message
	}


func _commit_temp_save(
	save_path: String,
	temp_path: String,
	backup_path: String,
	save_absolute: String,
	temp_absolute: String,
	backup_absolute: String
) -> Dictionary:
	var had_previous_save := FileAccess.file_exists(save_path)

	# 正常情况下 recovery 已清理备份。这里再兜底清理一次。
	if FileAccess.file_exists(backup_path):
		if not _remove_file_if_exists(backup_path, backup_absolute):
			_remove_file_if_exists(temp_path, temp_absolute)
			return {
				"ok": false,
				"error": "无法清理旧备份：%s" % backup_path
			}

	# 旧正式存档先改名为备份，保持事务可恢复。
	if had_previous_save:
		var backup_error := DirAccess.rename_absolute(save_absolute, backup_absolute)
		if backup_error != OK:
			_remove_file_if_exists(temp_path, temp_absolute)
			return {
				"ok": false,
				"error": "无法备份旧存档：%s，错误码：%d" % [save_path, backup_error]
			}

	var replace_error := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if replace_error != OK:
		var restore_error := OK
		if had_previous_save and FileAccess.file_exists(backup_path):
			restore_error = DirAccess.rename_absolute(backup_absolute, save_absolute)

		_remove_file_if_exists(temp_path, temp_absolute)

		if restore_error != OK:
			return {
				"ok": false,
				"error": "存档替换失败且旧档恢复失败；旧备份：%s，替换错误：%d，恢复错误：%d" % [
					backup_path,
					replace_error,
					restore_error
				]
			}

		return {
			"ok": false,
			"error": "无法替换正式存档：%s，错误码：%d" % [save_path, replace_error]
		}

	# 新档已就位；备份清理失败不影响本次存档有效性。
	if had_previous_save:
		_remove_file_if_exists(backup_path, backup_absolute)

	return {"ok": true}


func _recover_interrupted_save(
	save_path: String,
	temp_path: String,
	backup_path: String,
	save_absolute: String,
	temp_absolute: String,
	backup_absolute: String
) -> Dictionary:
	# 正式存档存在时，以正式存档为准，清理事务残留。
	if FileAccess.file_exists(save_path):
		if not _remove_file_if_exists(temp_path, temp_absolute):
			return {"ok": false, "error": "无法清理临时存档：%s" % temp_path}
		if not _remove_file_if_exists(backup_path, backup_absolute):
			return {"ok": false, "error": "无法清理备份存档：%s" % backup_path}
		return {"ok": true}

	# 正式档不存在但 .bak 存在：优先恢复旧档。
	if FileAccess.file_exists(backup_path):
		var restore_error := DirAccess.rename_absolute(backup_absolute, save_absolute)
		if restore_error != OK:
			return {
				"ok": false,
				"error": "无法恢复旧存档：%s，错误码：%d" % [backup_path, restore_error]
			}
		_remove_file_if_exists(temp_path, temp_absolute)
		return {"ok": true}

	# 第一次保存若只留下 .tmp，验证完整 JSON 后再提升为正式档。
	if FileAccess.file_exists(temp_path):
		if _is_valid_save_file(temp_path):
			var promote_error := DirAccess.rename_absolute(temp_absolute, save_absolute)
			if promote_error == OK:
				return {"ok": true}
			return {
				"ok": false,
				"error": "无法接管临时存档：%s，错误码：%d" % [temp_path, promote_error]
			}

		if not _remove_file_if_exists(temp_path, temp_absolute):
			return {"ok": false, "error": "无法删除损坏的临时存档：%s" % temp_path}

	return {"ok": true}


func _is_valid_save_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		return false

	return typeof(json.data) == TYPE_DICTIONARY


func _remove_file_if_exists(path: String, absolute_path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true

	return DirAccess.remove_absolute(absolute_path) == OK
