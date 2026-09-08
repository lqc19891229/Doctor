extends Resource
class_name StoryLine

# =========================================================
# StoryLine
# 一句剧情内容的数据。
# 背景和BGM均可由剧情行控制。
# StoryData只负责剧情整体配置，不保存单句演出音乐。
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

# 当前这句指定的背景。
# 留空时继续使用上一句背景；
# 如果是第一句留空，则使用 StoryData.background。
@export var background: Texture2D

# 当前人物立绘。
# subtitle 类型可以留空。
@export var portrait: Texture2D

# 立绘显示位置。
@export_enum("auto", "left", "mid", "right") var portrait_side: String = "auto"

# 当前说话人在本句结束后的立绘处理方式。
# dim = 推进到下一句后继续留在画面并压暗。
# hide = 从本句推进到下一句时退出画面；人物以后再次说话时仍可重新显示。
# normal = 推进到下一句后继续留在画面，并保持正常显示亮度。
@export_enum("dim", "hide", "normal") var inactive_portrait_mode: String = "dim"

# 当前这句剧情指定的BGM。
#
# 留空：
# 不改变当前音乐。
#
# 示例：
# music = "sad"
#
# 对应：
# Assets/Audio/BGM/Story/sad.mp3 / sad.ogg
#
# BGM配置只存在StoryLine，不写入StoryData。

@export var music: String = ""
