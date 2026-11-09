class_name SkillIcons
extends RefCounted
## Bakes the 13x13 skill icons of SkillIconArt (tools/art_skill_icons.py) into textures: the map's ramp slots are filled from the
## branch colour, a 1 px ink outline is added. Cached per icon and colour; the textures stay referenced here, or they turn white.
const INK: Color = Color("08050f")
const GOLD: Color = Color("e6c468")
const GOLD_LIGHT: Color = Color("fff0b0")
const WHITE: Color = Color("f4eeff")
const NEIGHBORS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const SIZE: int = 15 ## 13 + the outline all round

static var _cache: Dictionary = {}


static func has_icon(icon: String) -> bool:
	return SkillIconArt.ICONS.has(icon)


## The icon in the colours of `tone` (the branch). `locked` greys it down for something not yet earned.
static func texture(icon: String, tone: Color, locked: bool = false) -> Texture2D:
	var key: String = "%s|%s|%d" % [icon, tone.to_html(false), 1 if locked else 0]
	if _cache.has(key):
		return _cache[key] as Texture2D
	if not SkillIconArt.ICONS.has(icon):
		return null
	var palette: Dictionary = {
		"=": tone.darkened(0.8), "-": tone.darkened(0.52), "o": tone.darkened(0.12), "+": tone.lightened(0.38), "#": tone.lightened(0.78),
		"g": GOLD, "G": GOLD_LIGHT, "w": WHITE,
	}
	if locked:
		for slot: String in palette:
			var c: Color = palette[slot] as Color
			var grey: float = c.get_luminance() * 0.7
			palette[slot] = c.lerp(Color(grey, grey, grey), 0.72).darkened(0.18)
	var rows: Array = SkillIconArt.ICONS[icon] as Array
	var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var solid: PackedByteArray = PackedByteArray()
	solid.resize(SIZE * SIZE)
	for y: int in rows.size():
		var text: String = rows[y]
		for x: int in text.length():
			var cell: String = text[x]
			if palette.has(cell):
				image.set_pixel(x + 1, y + 1, palette[cell] as Color)
				solid[(y + 1) * SIZE + x + 1] = 1
	for y: int in SIZE:
		for x: int in SIZE:
			if solid[y * SIZE + x] == 1:
				continue
			for d: Vector2i in NEIGHBORS:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < SIZE and ny < SIZE and solid[ny * SIZE + nx] == 1:
					image.set_pixel(x, y, INK)
					break
	var baked: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = baked
	return baked


## Draws the icon centred on `at`, whole pixels, `scale_value` 1 or 2.
static func draw(canvas: CanvasItem, icon: String, at: Vector2, tone: Color, alpha: float = 1.0, scale_value: int = 1, locked: bool = false) -> void:
	var tex: Texture2D = texture(icon, tone, locked)
	if tex == null:
		return
	var side: float = float(SIZE * scale_value)
	canvas.draw_texture_rect(tex, Rect2((at - Vector2(side, side) * 0.5).round(), Vector2(side, side)), false, Color(1, 1, 1, alpha))
