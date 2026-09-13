extends Resource
class_name TutorialSlideData

# 当前页使用的游戏截图。
@export var screenshot: Texture2D

# 教程标题。
@export var title: String = ""

# 教程说明文字。
@export_multiline var description: String = ""

# 需要强调的按键，例如：
# F1
# Q / A / Z
# 鼠标左键
@export var key_text: String = ""

# 是否显示遮罩高亮。
@export var show_highlight: bool = true

# 高亮区域，使用 0~1 的相对坐标。
#
# 示例：
# Rect2(0.70, 0.05, 0.20, 0.10)
#
# 表示：
# X = 屏幕宽度的 70%
# Y = 屏幕高度的 5%
# 宽 = 屏幕宽度的 20%
# 高 = 屏幕高度的 10%
@export var highlight_rect: Rect2 = Rect2(0.25, 0.25, 0.5, 0.5)
