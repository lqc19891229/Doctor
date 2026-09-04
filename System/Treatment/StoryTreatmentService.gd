## =========================================================
## StoryTreatmentService.gd
##
## 剧情 NPC 的轻量诊疗后端。
##
## 只保留 Story 场景真正需要的业务：
## - story NPC 运行时实例
## - Prescription
## - FormulaJudge
## - 把脉数据转发
## - 成功 / 失败后的后续剧情查询
##
## 不实例化 Clinic.tscn，不包含诊室 UI、计时、TopBar、WindowController 等。
## =========================================================

extends Node

const NPC_MANAGER_SCRIPT = preload("res://System/Npc/NpcManager.gd")

var _npc_manager: Node = null
var _current_npc: NpcData = null
var _current_prescription := Prescription.new()
var _formula_judge := FormulaJudge.new()
var _current_day: int = 1
var _diagnosis_submitted: bool = false
var _last_judge_result = null
var _last_judge_summary_text: String = ""
var _last_info_text: String = ""


func _ready() -> void:
	# 只创建一个纯数据 NpcManager。
	# 第 3 步已经让 NpcManager 的模板目录使用 static 共享缓存，
	# 因此这里不会再次扫描 / load 全部 NPC 资源。
	_npc_manager = NPC_MANAGER_SCRIPT.new()
	add_child(_npc_manager)


func prepare_story_npc_treatment(
	npc_id: String,
	treatment_disease: DiseaseData,
	day: int
) -> bool:
	_current_day = maxi(day, 1)
	_last_info_text = ""

	var clean_npc_id := npc_id.strip_edges()
	if clean_npc_id == "":
		_set_info_text("剧情没有配置 clinic_npc_id。")
		return false

	if treatment_disease == null:
		_set_info_text("发起诊疗的剧情没有配置 Disease。")
		return false

	if _npc_manager == null or not is_instance_valid(_npc_manager):
		_set_info_text("剧情诊疗服务的 NpcManager 不可用。")
		return false

	if not _npc_manager.has_method("replace_with_story_npc"):
		_set_info_text("NpcManager 缺少 story NPC 接口。")
		return false

	var npc: NpcData = _npc_manager.call(
		"replace_with_story_npc",
		clean_npc_id,
		treatment_disease
	) as NpcData
	if npc == null:
		_set_info_text("story NPC 加载失败：%s" % clean_npc_id)
		return false

	if npc.npc_type.strip_edges().to_lower() != "story":
		_set_info_text("NPC【%s】的 npc_type 不是 story。" % clean_npc_id)
		return false

	_current_npc = npc
	_reset_attempt_state()

	if OS.is_debug_build():
		print(
			"[StoryTreatmentService] 已准备剧情诊疗：",
			_current_npc.npc_name,
			" / ",
			_current_npc.npc_id,
			" / ",
			_current_npc.disease.disease_name
		)

	return true


func get_story_treatment_npc_name() -> String:
	if _current_npc == null:
		return ""
	return _current_npc.npc_name


func get_story_treatment_prescription():
	return _current_prescription


func show_story_pulse_hand(target_pulse_window: Node, hand_side: String) -> Dictionary:
	if _current_npc == null or _current_npc.disease == null:
		return {
			"ok": false,
			"text": "当前没有可诊疗的剧情病人。"
		}

	if target_pulse_window == null or not target_pulse_window.has_method("show_hand_group"):
		return {
			"ok": false,
			"text": "Story 的 PulseWindow 不可用。"
		}

	var raw_result = target_pulse_window.call(
		"show_hand_group",
		hand_side,
		_current_npc.disease
	)
	if typeof(raw_result) == TYPE_DICTIONARY:
		return raw_result

	return {
		"ok": false,
		"text": "Story 的 PulseWindow 返回了无效数据。"
	}


func submit_story_prescription() -> Dictionary:
	if _current_npc == null:
		return _submit_error("当前没有病人，无法提交处方")

	if _current_npc.disease == null:
		return _submit_error("当前病人没有绑定疾病，无法提交处方")

	if _current_prescription == null or _current_prescription.is_empty():
		return _submit_error("当前处方为空，请先开方")

	var standard_formula := _get_current_standard_formula()
	if standard_formula == null:
		return _submit_error(
			"未找到疾病【%s】对应的标准方" % _current_npc.disease.disease_name
		)

	var result = _formula_judge.judge_formula(
		_current_prescription,
		standard_formula,
		_current_npc.disease
	)
	if result == null:
		return _submit_error("处方判定失败。")

	_diagnosis_submitted = true
	_last_judge_result = result
	_last_judge_summary_text = result.get_summary_text()

	# story NPC 的名望 / 心得 / 银钱仍由后续 StoryData 在剧情播放完成后结算；
	# 此处只更新当前治疗状态。
	_current_npc.is_treated = bool(result.success)
	_current_npc.treatment_failed = not bool(result.success)
	_set_info_text(_last_judge_summary_text)

	if OS.is_debug_build() and result.has_method("debug_print"):
		result.debug_print()

	return {
		"ok": true,
		"success": _current_npc.is_treated,
		"result_data": _build_judgement_result_data(
			_last_judge_result,
			_last_judge_summary_text
		)
	}


func finish_story_treatment_attempt(
	success: bool,
	trigger_scene: String,
	treatment_story_id: String = ""
) -> StoryData:
	if _current_npc == null:
		return null

	var clean_trigger_scene := trigger_scene.strip_edges()
	if clean_trigger_scene == "":
		clean_trigger_scene = "clinic"
	var clean_treatment_story_id := treatment_story_id.strip_edges()

	var next_story: StoryData = null
	if success:
		if StoryManager != null and StoryManager.has_method("report_story_npc_cured"):
			next_story = StoryManager.report_story_npc_cured(
				_current_day,
				clean_trigger_scene,
				clean_treatment_story_id
			)
	else:
		if StoryManager != null and StoryManager.has_method("report_story_npc_treatment_failed"):
			next_story = StoryManager.report_story_npc_treatment_failed(
				_current_day,
				clean_trigger_scene,
				clean_treatment_story_id
			)

		# 治疗失败后允许同一 story NPC 再次开方。
		_current_npc.is_treated = false
		_current_npc.treatment_failed = false
		_reset_attempt_state()

	return next_story


func get_last_info_text() -> String:
	return _last_info_text


func _submit_error(message: String) -> Dictionary:
	_set_info_text(message)
	return {
		"ok": false,
		"message": message
	}


func _set_info_text(message: String) -> void:
	_last_info_text = message


func _reset_attempt_state() -> void:
	_current_prescription.clear()
	_current_prescription.clear_disease()
	_diagnosis_submitted = false
	_last_judge_result = null
	_last_judge_summary_text = ""


func _get_current_disease_id() -> String:
	if _current_npc == null or _current_npc.disease == null:
		return ""
	return _current_npc.disease.disease_id.strip_edges()


func _get_current_standard_formula() -> FormulaData:
	if _current_npc == null or _current_npc.disease == null:
		return null

	if FormulaDB == null:
		return null

	var recommended_formula_id := _current_npc.disease.recommended_formula_id.strip_edges()
	if recommended_formula_id != "" and FormulaDB.has_method("get_formula_by_id"):
		var recommended_formula = FormulaDB.get_formula_by_id(recommended_formula_id)
		if recommended_formula is FormulaData:
			return recommended_formula as FormulaData

	var disease_id := _get_current_disease_id()
	if disease_id == "" or not FormulaDB.has_method("get_formulas_by_disease"):
		return null

	var formula_list = FormulaDB.get_formulas_by_disease(disease_id)
	if typeof(formula_list) != TYPE_ARRAY or formula_list.is_empty():
		return null

	if formula_list[0] is FormulaData:
		return formula_list[0] as FormulaData
	return null


func _build_judgement_result_data(judge_result = null, summary_text: String = "") -> Dictionary:
	var npc_name := ""
	var disease_name := ""
	var standard_formula_name := ""
	var standard_formula_text := ""
	var player_disease_name := ""
	var player_prescription_text := ""
	var grade := ""
	var total_score := 0

	if _current_npc != null:
		npc_name = _current_npc.npc_name
		if _current_npc.disease != null:
			disease_name = _current_npc.disease.disease_name

	var standard_formula := _get_current_standard_formula()
	if standard_formula != null:
		standard_formula_name = standard_formula.formula_name
		standard_formula_text = _build_standard_formula_display_text(standard_formula)
	else:
		standard_formula_text = "（未找到标准方）"

	if _current_prescription != null:
		player_disease_name = _current_prescription.disease_name.strip_edges()
		if player_disease_name == "":
			player_disease_name = _current_prescription.disease_id.strip_edges()
		if player_disease_name == "":
			player_disease_name = "未选择疾病"
		player_prescription_text = _current_prescription.get_display_text()
	else:
		player_disease_name = "未选择疾病"
		player_prescription_text = "（无）"

	if judge_result != null:
		var raw_grade = judge_result.get("grade")
		if raw_grade != null:
			grade = str(raw_grade)

		var raw_score = judge_result.get("score")
		if raw_score != null:
			total_score = int(raw_score)

	return {
		"npc_name": npc_name,
		"disease_name": disease_name,
		"standard_formula_name": standard_formula_name,
		"standard_formula_text": standard_formula_text,
		"player_disease_name": player_disease_name,
		"player_prescription_text": player_prescription_text,
		"grade": grade,
		"total_score": total_score,
		"summary_text": summary_text,
		"newly_unlocked_entry_titles": [],
		"show_reward_change": false,
		"reputation_change": 0,
		"experience_change": 0,
		"treatment_income_wen": 0
	}


func _build_standard_formula_display_text(formula: FormulaData) -> String:
	if formula == null:
		return "（无）"

	var lines: Array[String] = []
	lines.append("君：" + _build_formula_group_display_text(formula.jun_group))
	lines.append("臣：" + _build_formula_group_display_text(formula.chen_group))
	lines.append("佐：" + _build_formula_group_display_text(formula.zuo_group))
	lines.append("使：" + _build_formula_group_display_text(formula.shi_group))
	return "\n".join(lines)


func _build_formula_group_display_text(group: Array) -> String:
	if group.is_empty():
		return "（无）"

	var parts: Array[String] = []
	for ingredient in group:
		if ingredient == null:
			continue
		if ingredient.has_method("is_valid_data") and not ingredient.is_valid_data():
			continue

		var herb_name := ""
		var amount_text := ""

		if ingredient.has_method("get_herb_name"):
			herb_name = str(ingredient.get_herb_name()).strip_edges()
		if herb_name == "" and ingredient.has_method("get_herb_id"):
			herb_name = str(ingredient.get_herb_id()).strip_edges()

		if ingredient.has_method("get_amount_in_fen"):
			amount_text = HerbUnit.format_fen_auto(int(ingredient.get_amount_in_fen()))

		if herb_name == "":
			continue
		if amount_text == "":
			parts.append(herb_name)
		else:
			parts.append("%s %s" % [herb_name, amount_text])

	if parts.is_empty():
		return "（无）"
	return "、".join(parts)
