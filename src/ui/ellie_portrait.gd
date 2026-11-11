class_name ElliePortrait
extends Control
## Ellie's dialogue portrait: a still picture (healthy or wounded) from assets/ui/ellie_dialogue_v4.png (tools/art_portrait_talk.py, 103 x 153 px per cell,
## row 0 healthy, row 2 wounded). Speaking and blinking are switched off for now; the sheet still holds the mouth shapes and closed eyes for later.
const SHEET: Texture2D = preload("res://assets/ui/ellie_dialogue_v4.png")
const CELL: Vector2 = Vector2(103, 153)
var _healthy: AtlasTexture = AtlasTexture.new()
var _wounded: AtlasTexture = AtlasTexture.new()
var reflective: bool = false
var hurt: bool = false
var speaking: bool = false
var talk_char: String = ""
var opacity: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_healthy.atlas = SHEET
	_healthy.region = Rect2(Vector2.ZERO, CELL)
	_wounded.atlas = SHEET
	_wounded.region = Rect2(Vector2(0, CELL.y * 2.0), CELL)


func advance(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(_wounded if hurt else _healthy, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, opacity))
