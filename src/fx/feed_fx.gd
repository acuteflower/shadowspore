class_name FeedFx
extends Node2D
## The morsel in Ellie's outstretched hand while she feeds a wild bird (the crouch is the sheet's, the arm and glove are `AttackComponent`'s). It is a few
## pixels in the colour of the item (averaged from its icon, so a berry is violet and a silverling is steel), with the world's pixel outline and one lit
## corner, and now and then a tiny glint. Unlit, follows the hand every frame.

const INK: Color = Color("1b1a2e")

static var _colors: Dictionary = {}

var _item: String = ""
var _hand: Vector2 = Vector2.ZERO
var _on: bool = false
var _age: float = 0.0


func _ready() -> void:
	z_index = 7
	material = Unlit.material()
	set_process(false)


func show_hand(item: String, hand: Vector2) -> void:
	if not _on:
		_age = 0.0
		set_process(true)
	_on = true
	_item = item
	_hand = hand
	queue_redraw()


func clear() -> void:
	if _on:
		_on = false
		set_process(false)
		queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()


## The average colour of the item's icon (cached).
static func color_of(item: String) -> Color:
	if _colors.has(item):
		return _colors[item] as Color
	var color: Color = Color("c9b8ff")
	var texture: Texture2D = Items.icon({"id": item, "count": 1})
	var image: Image = texture.get_image() if texture != null else null
	if image != null and not image.is_empty():
		var sum: Vector3 = Vector3.ZERO
		var count: int = 0
		for y: int in image.get_height():
			for x: int in image.get_width():
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a > 0.6 and pixel.get_luminance() > 0.12:
					sum += Vector3(pixel.r, pixel.g, pixel.b)
					count += 1
		if count > 0:
			sum /= float(count)
			color = Color(sum.x, sum.y, sum.z)
	_colors[item] = color
	return color


func _draw() -> void:
	if not _on:
		return
	var base: Color = color_of(_item)
	var at: Vector2 = Vector2(roundf(_hand.x), roundf(_hand.y - 1.0))
	draw_rect(Rect2(at + Vector2(-3, -3), Vector2(6, 5)), INK)
	draw_rect(Rect2(at + Vector2(-2, -2), Vector2(4, 3)), base.darkened(0.15))
	draw_rect(Rect2(at + Vector2(-2, -2), Vector2(2, 1)), base.lightened(0.45))
	var glint: float = fmod(_age, 1.3)
	if glint < 0.16:
		draw_rect(Rect2(at + Vector2(2, -5), Vector2(1, 1)), Color("f4f0ff"))
		draw_rect(Rect2(at + Vector2(1, -5), Vector2(3, 1)), Color(1, 1, 1, 0.35))
