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


func _localized_text(
	key: String,
	chinese: String,
	english: String,
	japanese: String,
	korean: String
) -> String:
	var translated := tr(key)
	if translated != key and not translated.strip_edges().is_empty():
		return translated

	if LocalizedName.is_english_locale():
		return english
	if LocalizedName.is_japanese_locale():
		return japanese
	if LocalizedName.is_korean_locale():
		return korean
	return chinese


func _ready() -> void:
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
		_set_info_text(_localized_text(
			"UI_STORY_TREATMENT_NO_NPC_ID",
			"剧情没有配置 clinic_npc_id。",
			"The story has no clinic_npc_id configured.",
			"シナリオに clinic_npc_id が設定されていません。",
			"이야기에 clinic_npc_id가 설정되어 있지 않습니다."
		))
		return false

	if treatment_disease == null:
		_set_info_text(_localized_text(
			"UI_STORY_TREATMENT_NO_DISEASE",
			"发起诊疗的剧情没有配置 Disease。",
			"The treatment story has no Disease configured.",
			"診療シナリオに病名が設定されていません。",
			"진료 이야기에 Disease가 설정되어 있지 않습니다."
		))
		return false

	if _npc_manager == null or not is_instance_valid(_npc_manager):
		_set_info_text(_localized_text(
			"UI_STORY_TREATMENT_NPC_MANAGER_UNAVAILABLE",
			"剧情诊疗服务的 NpcManager 不可用。",
			"NpcManager is unavailable for story treatment.",
			"シナリオ診療の NpcManager を使用できません。",
			"이야기 진료용 NpcManager를 사용할 수 없습니다."
		))
		return false

	if not _npc_manager.has_method("replace_with_story_npc"):
		_set_info_text(_localized_text(
			"UI_STORY_TREATMENT_NPC_MANAGER_INTERFACE_MISSING",
			"NpcManager 缺少 story NPC 接口。",
			"NpcManager does not provide the story NPC interface.",
			"NpcManager にシナリオ患者用の機能がありません。",
			"NpcManager에 story NPC 인터페이스가 없습니다."
		))
		return false

	var npc: NpcData = _npc_manager.call(
		"replace_with_story_npc",
		clean_npc_id,
		treatment_disease
	) as NpcData

	if npc == null:
		_set_info_text(_localized_text(
			"UI_STORY_TREATMENT_NPC_LOAD_FAILED_FMT",
			"story NPC 加载失败：%s",
			"Failed to load story NPC: %s",
			"シナリオ患者を読み込めません：%s",
			"story NPC를 불러오지 못했습니다: %s"
		) % clean_npc_id)
		return false

	if npc.npc_type.strip_edges().to_lower() != "story":
		_set_info_text(_localized_text(
			"UI_STORY_TREATMENT_INVALID_NPC_TYPE_FMT",
			"NPC【%s】的 npc_type 不是 story。",
			"NPC 【%s】 does not have npc_type 'story'.",
			"患者【%s】の種別が story ではありません。",
			"NPC【%s】의 npc_type이 story가 아닙니다."
		) % clean_npc_id)
		return false

	_current_npc = npc
	_reset_attempt_state()

	return true


func get_story_treatment_npc_name() -> String:
	if _current_npc == null:
		return ""
	return _current_npc.get_localized_name()


func get_story_treatment_prescription():
	return _current_prescription


func show_story_pulse_hand(
	target_pulse_window: Node,
	hand_side: String
) -> Dictionary:
	if _current_npc == null or _current_npc.disease == null:
		return {
			"ok": false,
			"text": _localized_text(
				"UI_STORY_TREATMENT_NO_ACTIVE_PATIENT",
				"当前没有可诊疗的剧情病人。",
				"There is no story patient available for treatment.",
				"診療できるシナリオ患者がいません。",
				"진료할 이야기 환자가 없습니다."
			)
		}

	if (
		target_pulse_window == null
		or not target_pulse_window.has_method("show_hand_group")
	):
		return {
			"ok": false,
			"text": _localized_text(
				"UI_STORY_TREATMENT_PULSE_WINDOW_UNAVAILABLE",
				"Story 的 PulseWindow 不可用。",
				"The story PulseWindow is unavailable.",
				"脈診画面を使用できません。",
				"맥진 창을 사용할 수 없습니다."
			)
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
		"text": _localized_text(
			"UI_STORY_TREATMENT_PULSE_INVALID_RESULT",
			"Story 的 PulseWindow 返回了无效数据。",
			"The story PulseWindow returned invalid data.",
			"脈診画面から正しい結果を取得できませんでした。",
			"맥진 창에서 유효하지 않은 결과를 반환했습니다."
		)
	}


func submit_story_prescription() -> Dictionary:
	if _current_npc == null:
		return _submit_error(_localized_text(
			"UI_TREATMENT_NO_PATIENT",
			"当前没有病人，无法提交处方",
			"There is no patient. The prescription cannot be submitted.",
			"患者がいないため処方を提出できません。",
			"현재 환자가 없어 처방을 제출할 수 없습니다."
		))

	if _current_npc.disease == null:
		return _submit_error(_localized_text(
			"UI_TREATMENT_NO_DISEASE",
			"当前病人没有绑定疾病，无法提交处方",
			"This patient has no disease assigned. The prescription cannot be submitted.",
			"この患者には病名が設定されていないため、処方を提出できません。",
			"현재 환자에게 연결된 병증이 없어 처방을 제출할 수 없습니다."
		))

	if not _current_prescription.has_disease():
		return _submit_error(_localized_text(
			"UI_TREATMENT_SELECT_DIAGNOSIS",
			"请先选择疾病诊断",
			"Please select a diagnosis first.",
			"先に病名を選択してください。",
			"먼저 병증을 진단해 주세요."
		))

	if _current_prescription == null or _current_prescription.is_empty():
		return _submit_error(_localized_text(
			"UI_TREATMENT_EMPTY_PRESCRIPTION",
			"当前处方为空，请先开方",
			"The prescription is empty. Add herbs first.",
			"処方が空です。先に薬材を選んでください。",
			"처방이 비어 있습니다. 먼저 약재를 선택해 주세요."
		))

	var standard_formula := _get_current_standard_formula()
	if standard_formula == null:
		var disease_name := LocalizedName.disease(
			_current_npc.disease.disease_id,
			_current_npc.disease.disease_name
		)
		return _submit_error(_localized_text(
			"UI_TREATMENT_STANDARD_FORMULA_NOT_FOUND_FMT",
			"未找到疾病【%s】对应的标准方",
			"No standard prescription was found for 【%s】.",
			"【%s】の標準処方が見つかりません。",
			"【%s】에 해당하는 표준 처방을 찾을 수 없습니다."
		) % disease_name)

	var result = _formula_judge.judge_formula(
		_current_prescription,
		standard_formula,
		_current_npc.disease
	)

	if result == null:
		return _submit_error(_localized_text(
			"UI_STORY_TREATMENT_JUDGE_FAILED",
			"处方判定失败。",
			"Prescription evaluation failed.",
			"処方を判定できませんでした。",
			"처방 판정에 실패했습니다."
		))

	var was_already_submitted := _diagnosis_submitted
	_diagnosis_submitted = true
	_last_judge_result = result
	_last_judge_summary_text = result.get_summary_text()

	if (
		not was_already_submitted
		and Records != null
		and Records.has_method("record_treatment")
	):
		var raw_grade = result.get("grade")
		var raw_score = result.get("score")
		if raw_score == null:
			raw_score = -1

		Records.record_treatment(_current_day, {
			"patient_name": _current_npc.npc_name,
			"npc_id": _current_npc.npc_id,
			"npc_type": "story",
			"disease_name": _current_npc.disease.disease_name,
			"disease_id": _current_npc.disease.disease_id,
			"standard_formula_name": standard_formula.formula_name,
			"standard_formula_id": standard_formula.formula_id,
			"diagnosis": _current_prescription.disease_name,
			"diagnosis_id": _current_prescription.disease_id,
			"prescription": _current_prescription.get_display_text(),
			"prescription_items": _current_prescription.get_record_items(),
			"grade": String(raw_grade) if raw_grade != null else "",
			"score": raw_score,
			"success": bool(result.success)
		})

	_current_npc.is_treated = bool(result.success)
	_current_npc.treatment_failed = not bool(result.success)
	_set_info_text(_last_judge_summary_text)

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
		if (
			StoryManager != null
			and StoryManager.has_method("report_story_npc_cured")
		):
			next_story = StoryManager.report_story_npc_cured(
				_current_day,
				clean_trigger_scene,
				clean_treatment_story_id
			)
	else:
		if (
			StoryManager != null
			and StoryManager.has_method("report_story_npc_treatment_failed")
		):
			next_story = StoryManager.report_story_npc_treatment_failed(
				_current_day,
				clean_trigger_scene,
				clean_treatment_story_id
			)

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

	var recommended_formula_id := (
		_current_npc.disease.recommended_formula_id.strip_edges()
	)

	if (
		recommended_formula_id != ""
		and FormulaDB.has_method("get_formula_by_id")
	):
		var recommended_formula = FormulaDB.get_formula_by_id(
			recommended_formula_id
		)
		if recommended_formula is FormulaData:
			return recommended_formula as FormulaData

	var disease_id := _get_current_disease_id()
	if (
		disease_id == ""
		or not FormulaDB.has_method("get_formulas_by_disease")
	):
		return null

	var formula_list = FormulaDB.get_formulas_by_disease(disease_id)
	if typeof(formula_list) != TYPE_ARRAY or formula_list.is_empty():
		return null

	if formula_list[0] is FormulaData:
		return formula_list[0] as FormulaData

	return null


func _build_judgement_result_data(
	judge_result = null,
	summary_text: String = ""
) -> Dictionary:
	var npc_name := ""
	var disease_name := ""
	var standard_formula_name := ""
	var standard_formula_text := ""
	var player_disease_name := ""
	var player_prescription_text := ""
	var grade := ""
	var grade_level := ""
	var total_score := 0

	if _current_npc != null:
		npc_name = _current_npc.get_localized_name()
		if _current_npc.disease != null:
			disease_name = LocalizedName.disease(
				_current_npc.disease.disease_id,
				_current_npc.disease.disease_name
			)

	var standard_formula := _get_current_standard_formula()

	if standard_formula != null:
		standard_formula_name = LocalizedName.formula(
			standard_formula.formula_id,
			standard_formula.formula_name
		)
		standard_formula_text = _build_standard_formula_display_text(
			standard_formula
		)
	else:
		standard_formula_text = _localized_text(
			"UI_RESULT_NO_STANDARD_FORMULA",
			"（未找到标准方）",
			"(No standard prescription)",
			"（標準処方なし）",
			"(표준 처방 없음)"
		)

	if _current_prescription != null:
		player_disease_name = (
			_current_prescription.disease_name.strip_edges()
		)

		if player_disease_name == "":
			player_disease_name = (
				_current_prescription.disease_id.strip_edges()
			)

		if player_disease_name == "":
			player_disease_name = _localized_text(
				"UI_RESULT_NO_DIAGNOSIS",
				"未选择疾病",
				"No diagnosis selected",
				"病名未選択",
				"병증 미선택"
			)
		elif not _current_prescription.disease_id.strip_edges().is_empty():
			player_disease_name = LocalizedName.disease(
				_current_prescription.disease_id,
				player_disease_name
			)

		player_prescription_text = (
			_current_prescription.get_display_text()
		)
	else:
		player_disease_name = _localized_text(
			"UI_RESULT_NO_DIAGNOSIS",
			"未选择疾病",
			"No diagnosis selected",
			"病名未選択",
			"병증 미선택"
		)
		player_prescription_text = _localized_none_text()

	if judge_result != null:
		var raw_grade = judge_result.get("grade")
		if raw_grade != null:
			grade = str(raw_grade)

		var raw_level = judge_result.get("level")
		if raw_level != null:
			grade_level = str(raw_level).strip_edges()

		var raw_score = judge_result.get("score")
		if raw_score != null:
			total_score = int(raw_score)

	return {
		"npc_name": npc_name,
		"disease_name": disease_name,
		"disease_id": (
			_current_npc.disease.disease_id
			if (
				_current_npc != null
				and _current_npc.disease != null
			)
			else ""
		),
		"standard_formula_name": standard_formula_name,
		"standard_formula_id": (
			standard_formula.formula_id
			if standard_formula != null
			else ""
		),
		"standard_formula_text": standard_formula_text,
		"standard_formula_resource": standard_formula,
		"player_disease_name": player_disease_name,
		"player_disease_id": (
			_current_prescription.disease_id
			if _current_prescription != null
			else ""
		),
		"player_prescription_text": player_prescription_text,
		"player_prescription_resource": _current_prescription,
		"grade": grade,
		"grade_level": grade_level,
		"total_score": total_score,
		"summary_text": summary_text,
		"newly_unlocked_entry_titles": [],
		"show_reward_change": false,
		"reputation_change": 0,
		"experience_change": 0,
		"consultation_fee_wen": 0,
		"medicine_income_wen": 0,
		"patient_thank_gift_wen": 0
	}


func _build_standard_formula_display_text(
	formula: FormulaData
) -> String:
	if formula == null:
		return _localized_none_text()

	var lines: Array[String] = []
	lines.append(_build_formula_role_line("君", formula.jun_group))
	lines.append(_build_formula_role_line("臣", formula.chen_group))
	lines.append(_build_formula_role_line("佐", formula.zuo_group))
	lines.append(_build_formula_role_line("使", formula.shi_group))

	return "\n".join(lines)


func _build_formula_group_display_text(group: Array) -> String:
	if group.is_empty():
		return _localized_none_text()

	var parts: Array[String] = []

	for ingredient in group:
		if ingredient == null:
			continue

		if (
			ingredient.has_method("is_valid_data")
			and not ingredient.is_valid_data()
		):
			continue

		var herb_id := ""
		var herb_name := ""
		var amount_text := ""

		if ingredient.has_method("get_herb_id"):
			herb_id = str(ingredient.get_herb_id()).strip_edges()

		if ingredient.has_method("get_herb_name"):
			herb_name = str(ingredient.get_herb_name()).strip_edges()

		if herb_name == "":
			herb_name = herb_id

		if herb_id != "":
			herb_name = LocalizedName.herb(herb_id, herb_name)

		if ingredient.has_method("get_amount_in_fen"):
			amount_text = HerbUnit.format_fen_auto(
				int(ingredient.get_amount_in_fen())
			)

		if herb_name == "":
			continue

		if amount_text == "":
			parts.append(herb_name)
		else:
			parts.append("%s %s" % [herb_name, amount_text])

	if parts.is_empty():
		return _localized_none_text()

	return _list_separator().join(parts)


func _build_formula_role_line(
	role_name: String,
	group: Array
) -> String:
	var locale := TranslationServer.get_locale().to_lower()
	var colon := ": " if locale.begins_with("en") or locale.begins_with("ko") else "："
	return (
		_localized_role_name(role_name)
		+ colon
		+ _build_formula_group_display_text(group)
	)


func _localized_role_name(role_name: String) -> String:
	match role_name:
		"君":
			return _localized_text("UI_PRESCRIPTION_ROLE_JUN", "君", "Chief", "君薬", "군약")
		"臣":
			return _localized_text("UI_PRESCRIPTION_ROLE_CHEN", "臣", "Deputy", "臣薬", "신약")
		"佐":
			return _localized_text("UI_PRESCRIPTION_ROLE_ZUO", "佐", "Assistant", "佐薬", "좌약")
		"使":
			return _localized_text("UI_PRESCRIPTION_ROLE_SHI", "使", "Envoy", "使薬", "사약")
	return role_name


func _localized_none_text() -> String:
	return _localized_text("UI_NONE", "（无）", "(None)", "（なし）", "(없음)")


func _list_separator() -> String:
	var locale := TranslationServer.get_locale().to_lower()
	if locale.begins_with("en") or locale.begins_with("ko"):
		return ", "
	return "、"
