extends RefCounted
class_name LocalizedName

# =========================================================
# 统一实体显示名称 / 搜索辅助
#
# 规则：
# - 程序逻辑始终使用 herb_id / formula_id / disease_id。
# - 显示名称统一读取 UI_BOOK_ENTRY_TITLE_<ID>。
# - 找不到翻译时使用传入的中文 fallback。
# - 简体中文搜索：中文名 + 拼音全拼 + 拼音首字母。
# - 繁体中文搜索：繁体名 + 注音 + 拼音 + 拼音首字母。
# - 英文环境搜索：英文名 + 英文单词首字母。
# - 日文环境搜索：日文名称 + 假名 + Romaji + Romaji 首字母。
# - 韩文环境搜索：韩文名称 + 초성 + Romaja + Romaja 首字母。
# - 详情排版：英文、韩文横排；中文、日文使用古籍竖排。
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

	if translated.strip_edges() == "" or translated == translation_key:
		if fallback.strip_edges() != "":
			return fallback
		return clean_id

	return translated


static func _normalized_locale() -> String:
	return TranslationServer.get_locale().to_lower().replace("-", "_")


static func is_english_locale() -> bool:
	return _normalized_locale().begins_with("en")


static func is_japanese_locale() -> bool:
	return _normalized_locale().begins_with("ja")


static func is_korean_locale() -> bool:
	return _normalized_locale().begins_with("ko")


static func is_chinese_locale() -> bool:
	return _normalized_locale().begins_with("zh")


static func is_traditional_chinese_locale() -> bool:
	var locale := _normalized_locale()
	return (
		locale.begins_with("zh_tw")
		or locale.begins_with("zh_hant")
	)


static func is_horizontal_detail_locale() -> bool:
	# 英文、韩文正文使用横排；简/繁中、日文保持古籍竖排。
	return is_english_locale() or is_korean_locale()


# =========================================================
# 繁体中文搜索
# =========================================================

static var _traditional_chinese_aliases_loaded: bool = false
static var _traditional_chinese_aliases: Dictionary = {}


static func normalize_traditional_chinese_search_text(value: String) -> String:
	var result := value.strip_edges().to_lower()

	# 全角 ASCII 统一为半角，方便直接输入全角英数字时也能搜索。
	var normalized := ""
	for index in range(result.length()):
		var code := result.unicode_at(index)
		if code >= 0xFF01 and code <= 0xFF5E:
			code -= 0xFEE0
		normalized += String.chr(code)
	result = normalized

	# 搜索忽略常见分隔符、空白以及注音声调符号。
	for separator in [
		" ", "\t", "\r", "\n", "_", "-", "'", "|",
		",", "，", ".", "。", "、", "・", "･", "·",
		"(", ")", "（", "）", "[", "]", "【", "】",
		"/", "／", ":", "：", ";", "；",
		"ˉ", "ˊ", "ˇ", "ˋ", "˙"
	]:
		result = result.replace(separator, "")

	# 拼音声调统一成无声调形式；ü 系列统一成 v。
	var replacements := {
		"ā": "a", "á": "a", "ǎ": "a", "à": "a",
		"ē": "e", "é": "e", "ě": "e", "è": "e",
		"ī": "i", "í": "i", "ǐ": "i", "ì": "i",
		"ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
		"ū": "u", "ú": "u", "ǔ": "u", "ù": "u",
		"ü": "v", "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v",
	}
	for source in replacements:
		result = result.replace(str(source), str(replacements[source]))

	return result


static func _load_traditional_chinese_aliases() -> void:
	if _traditional_chinese_aliases_loaded:
		return

	_traditional_chinese_aliases_loaded = true

	var path := "res://Localization/search_zh_TW.txt"
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

		var raw_pinyin := str(fields[2])

		_traditional_chinese_aliases[fields[0]] = {
			"zhuyin": normalize_traditional_chinese_search_text(fields[1]),
			"pinyin": normalize_traditional_chinese_search_text(raw_pinyin),
			"pinyin_initials": romanization_initials(raw_pinyin),
		}


static func traditional_chinese_search_matches(
	display_name: String,
	entity_id: String,
	query: String
) -> bool:
	var needle := normalize_traditional_chinese_search_text(query)

	if needle.is_empty():
		return false

	if normalize_traditional_chinese_search_text(display_name).contains(needle):
		return true

	_load_traditional_chinese_aliases()

	var key := "UI_BOOK_ENTRY_TITLE_" + entity_id.to_upper()
	var aliases: Dictionary = _traditional_chinese_aliases.get(key, {})

	if aliases.is_empty():
		return false

	var zhuyin := str(aliases.get("zhuyin", ""))
	if not zhuyin.is_empty() and zhuyin.contains(needle):
		return true

	var pinyin := str(aliases.get("pinyin", ""))
	if not pinyin.is_empty() and pinyin.contains(needle):
		return true

	var pinyin_initials := str(aliases.get("pinyin_initials", ""))
	if (
		not pinyin_initials.is_empty()
		and pinyin_initials.begins_with(needle)
	):
		return true

	return false


# =========================================================
# 日语搜索
# =========================================================

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

		# 普通搜索忽略常见分隔符。
		if code in [0x20, 0x3000, 0x2D, 0x5F, 0x27, 0x7C]:
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

		var raw_romaji := str(fields[2])

		_japanese_aliases[fields[0]] = {
			"kana": normalize_japanese_search_text(fields[1]),
			"romaji": normalize_japanese_search_text(raw_romaji),
			"romaji_initials": romanization_initials(raw_romaji),
		}


static func japanese_search_matches(
	display_name: String,
	entity_id: String,
	query: String
) -> bool:
	var needle := normalize_japanese_search_text(query)

	if needle.is_empty():
		return false

	if normalize_japanese_search_text(display_name).contains(needle):
		return true

	_load_japanese_aliases()

	var key := "UI_BOOK_ENTRY_TITLE_" + entity_id.to_upper()
	var aliases: Dictionary = _japanese_aliases.get(key, {})

	if aliases.is_empty():
		return false

	var kana := str(aliases.get("kana", ""))
	if not kana.is_empty() and kana.contains(needle):
		return true

	var romaji := str(aliases.get("romaji", ""))
	if not romaji.is_empty() and romaji.contains(needle):
		return true

	var romaji_initials := str(aliases.get("romaji_initials", ""))
	if (
		not romaji_initials.is_empty()
		and romaji_initials.begins_with(needle)
	):
		return true

	return false


# =========================================================
# 韩语搜索
# =========================================================

static var _korean_aliases_loaded: bool = false
static var _korean_aliases: Dictionary = {}


static func _load_korean_aliases() -> void:
	if _korean_aliases_loaded:
		return

	_korean_aliases_loaded = true

	var path := "res://Localization/search_ko.txt"
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

		var raw_romaja := str(fields[2])

		_korean_aliases[fields[0]] = {
			"hangul": str(fields[1]),
			"romaja": normalize_search_text(raw_romaja),
			"romaja_initials": romanization_initials(raw_romaja),
		}


static func _korean_initials(value: String) -> String:
	const CHOSEONG = [
		"ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ",
		"ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ",
		"ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
	]

	var result := ""

	for index in range(value.length()):
		var code := value.unicode_at(index)

		if code >= 0xAC00 and code <= 0xD7A3:
			result += CHOSEONG[int((code - 0xAC00) / 588)]

	return result


static func korean_search_matches(
	display_name: String,
	entity_id: String,
	query: String
) -> bool:
	var needle := normalize_search_text(query)

	if needle.is_empty():
		return false

	_load_korean_aliases()

	var key := "UI_BOOK_ENTRY_TITLE_" + entity_id.to_upper()
	var aliases: Dictionary = _korean_aliases.get(key, {})

	var names: Array = [display_name]
	var hangul := str(aliases.get("hangul", ""))

	if not hangul.is_empty():
		names.append(hangul)

	for name in names:
		var normalized_name := normalize_search_text(str(name))

		if normalized_name.contains(needle):
			return true

		var initials := _korean_initials(str(name))

		if (
			not initials.is_empty()
			and initials.begins_with(needle)
		):
			return true

	var romaja := str(aliases.get("romaja", ""))
	if (
		not romaja.is_empty()
		and normalize_search_text(romaja).contains(needle)
	):
		return true

	var romaja_initials := str(aliases.get("romaja_initials", ""))
	if (
		not romaja_initials.is_empty()
		and romaja_initials.begins_with(needle)
	):
		return true

	return false


# =========================================================
# 通用搜索辅助
# =========================================================

static func normalize_search_text(value: String) -> String:
	return value.strip_edges().to_lower() \
		.replace("_", "") \
		.replace("-", "") \
		.replace(" ", "") \
		.replace("'", "") \
		.replace("|", "")


static func romanization_initials(value: String) -> String:
	# Romaji / Romaja / Pinyin 单字首字母。
	#
	# | 表示一个汉字 / 日文汉字 / 韩文音节对应的 Romanization 边界。
	# 同时兼容旧的空格、连字符、下划线格式。
	var clean_text := value.strip_edges().to_lower() \
		.replace("|", " ") \
		.replace("-", " ") \
		.replace("_", " ") \
		.replace("'", "")

	var words := clean_text.split(" ", false)
	var initials := ""

	for word in words:
		var clean_word := String(word).strip_edges()

		if clean_word.length() > 0:
			initials += clean_word.substr(0, 1)

	return initials


static func id_initials(value: String) -> String:
	var parts := value.to_lower().split("_", false)
	var initials := ""

	for part in parts:
		if part.length() > 0:
			initials += part.substr(0, 1)

	return initials


static func english_initials(value: String) -> String:
	# 连字符视为单词分隔符；英文所有格中的撇号直接去掉。
	# 例：
	# White Atractylodes Rhizome -> war
	# Wind-Cold Exterior Deficiency Pattern -> wcedp
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
