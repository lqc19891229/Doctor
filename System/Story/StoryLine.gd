extends Resource
class_name StoryLine

# =========================================================
# StoryLine
# 一句剧情内容的数据。
# 背景不放在这里，整段剧情背景由 StoryData.background 控制。
# =========================================================

# 当前这一句的表现类型。
# dialogue = 人物对话
# subtitle = 背景字幕 / 旁白
@export_enum("dialogue", "subtitle") var line_type: String = "dialogue"

# 说话人名称。
# subtitle 类型可以留空。
@export var speaker: String = ""

# 当前台词 / 字幕内容。
@export_multiline var text: String = ""

# 当前人物立绘。
# subtitle 类型可以留空。
@export var portrait: Texture2D

# 立绘显示位置
@export_enum("auto", "left", "right") var portrait_side: String = "auto"
