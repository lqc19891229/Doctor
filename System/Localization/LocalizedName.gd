extends RefCounted
class_name LocalizedName

# =========================================================
# 统一实体显示名称 / 搜索辅助
#
# 规则：
# - 程序逻辑始终使用 herb_id / formula_id / disease_id。
# - 显示名称统一读取 UI_BOOK_ENTRY_TITLE_<ID>。
# - 找不到翻译时使用传入的中文 fallback。
# - 中文环境搜索：中文名 + 拼音全拼 + 拼音首字母。
# - 英文环境搜索：英文名 + 英文单词首字母。
# =========================================================


static func herb(herb_id: String, fallback: String = "") -> String:
	return _entity_title(herb_id, fallback)


static func formula(formula_id: String, fallback: String = "") -> String:
	return _entity_title(formula_id, fallback)


static func disease(disease_id: String, fallback: String = "") -> String:
	return _entity_title(disease_id, fallback)


static func _entity_title(entity_id: String, fallback: String = "") -> String:
	var clean_id := entity_id.strip_edges()
	if clean_id == "":
		return fallback

	var translation_key := "UI_BOOK_ENTRY_TITLE_" + clean_id.to_upper()
	var translated := TranslationServer.translate(translation_key)

	# 找不到翻译时 TranslationServer 通常返回 key 本身。
	if translated.strip_edges() == "" or translated == translation_key:
		if fallback.strip_edges() != "":
			return fallback
		return clean_id

	return translated


static func is_english_locale() -> bool:
	return TranslationServer.get_locale().to_lower().begins_with("en")


static func normalize_search_text(value: String) -> String:
	return value.strip_edges().to_lower() \
		.replace("_", "") \
		.replace("-", "") \
		.replace(" ", "") \
		.replace("'", "")


static func id_initials(value: String) -> String:
	var parts := value.to_lower().split("_", false)
	var initials := ""

	for part in parts:
		if part.length() > 0:
			initials += part.substr(0, 1)

	return initials


static func english_initials(value: String) -> String:
	# 连字符视为单词分隔符；英文所有格中的撇号直接去掉。
	# 例：White Atractylodes Rhizome -> war
	#     Wind-Cold Exterior Deficiency Pattern -> wcedp
	var clean_text := value.strip_edges() \
		.replace("-", " ") \
		.replace("'", "")

	var words := clean_text.split(" ", false)
	var initials := ""

	for word in words:
		var clean_word := String(word).strip_edges()
		if clean_word.length() > 0:
			initials += clean_word.substr(0, 1).to_lower()

	return initials
