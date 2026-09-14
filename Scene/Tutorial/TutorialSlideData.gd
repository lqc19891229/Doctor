extends Resource
class_name TutorialSlideData

## Data for one page in TutorialWindow.
## Keeping all fields in one Resource prevents title/image/description arrays from
## becoming misaligned as the tutorial grows.

@export var title: String = "游戏说明"
@export_multiline var description: String = ""
@export var caption: String = ""
@export var image: Texture2D
