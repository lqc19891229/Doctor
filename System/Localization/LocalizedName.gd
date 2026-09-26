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


static func is_japanese_locale() -> bool:
	return TranslationServer.get_locale().to_lower().begins_with("ja")


static var _japanese_aliases_loaded: bool = false
static var _japanese_aliases: Dictionary = {}


static func normalize_japanese_search_text(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var code := value.unicode_at(index)
		# 片假名统一成平假名；全角英文字母和数字统一成半角。
		if code >= 0x30A1 and code <= 0x30F6:
			code -= 0x60
		elif code >= 0xFF01 and code <= 0xFF5E:
			code -= 0xFEE0
		if code in [0x20, 0x3000, 0x2D, 0x5F, 0x27]:
			continue
		result += String.chr(code)
	return result.to_lower()


static func _load_japanese_aliases() -> void:
	if _japanese_aliases_loaded:
		return
	_japanese_aliases_loaded = true
	var path := "res://Localization/search_ja.txt"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	file.get_csv_line() # header
	while not file.eof_reached():
		var fields := file.get_csv_line()
		if fields.size() < 3 or fields[0].strip_edges().is_empty():
			continue
		_japanese_aliases[fields[0]] = [
			normalize_japanese_search_text(fields[1]),
			normalize_japanese_search_text(fields[2])
		]


static func japanese_search_matches(display_name: String, entity_id: String, query: String) -> bool:
	var needle := normalize_japanese_search_text(query)
	if needle.is_empty():
		return false
	if normalize_japanese_search_text(display_name).contains(needle):
		return true
	_load_japanese_aliases()
	var key := "UI_BOOK_ENTRY_TITLE_" + entity_id.to_upper()
	var aliases: Array = _japanese_aliases.get(key, [])
	for alias in aliases:
		if not str(alias).is_empty() and str(alias).contains(needle):
			return true
	return false


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
