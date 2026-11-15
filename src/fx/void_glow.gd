class_name VoidGlow
extends RefCounted
## The shared violet light of every shadow creature (spider, listener, crusher): one heartbeat that pulses its veins, and one soft pixel bloom for veins, cores and eyes.
## Callers draw on an additive, unshaded canvas; `strength` is already multiplied by the creature's own fade.

const INTENSITY: float = 0.78 ## one knob for the light of every shadow creature
const VEIN: Color = Color("7d57e0") ## slightly cooler and less saturated than the first violet
const VEIN_LIGHT: Color = Color("a98af0")
const BLOOM_OUTER: float = 0.035
const BLOOM_MID: float = 0.09
const BLOOM_VEIN: float = 0.1 ## the thin halo of a vein pixel: veins are drawn pixel after pixel, so more would stack into a solid tube
const BLOOM_SPOT: float = 0.22
const _SRC_VEIN: Rect2 = Rect2(0.0, 0.0, 3.0, 3.0)
const _SRC_SPOT: Rect2 = Rect2(4.0, 0.0, 7.0, 7.0)
const _SRC_PIXEL: Rect2 = Rect2(14.0, 1.0, 1.0, 1.0)

static var _atlas: ImageTexture


static func _atlas_tex() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var img: Image = Image.create(16, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	# Tile 0 (0..2, 0..2): 3x3 vein halo (outer BLOOM_VEIN, center 1.0)
	for dy: int in 3:
		for dx: int in 3:
			var a: float = 1.0 if (dx == 1 and dy == 1) else BLOOM_VEIN
			img.set_pixel(dx, dy, Color(1.0, 1.0, 1.0, a))
	# Tile 1 (4..10, 0..6): 7x7 layered additive spot bloom weights
	for dy: int in 7:
		for dx: int in 7:
			var ring: int = maxi(absi(dx - 3), absi(dy - 3))
			var a: float = BLOOM_OUTER
			if ring <= 2:
				a += BLOOM_MID
			if ring <= 1:
				a += BLOOM_SPOT
			img.set_pixel(4 + dx, dy, Color(1.0, 1.0, 1.0, a))
	# Pixel block (13..15, 0..2): padded 3x3 white center at (14, 1) so rects stay in the VoidGlow batch without UV edge bleed
	img.fill_rect(Rect2i(13, 0, 3, 3), Color.WHITE)
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


## Draws a crisp 1x1 unshaded glowing pixel using the shared VoidGlow atlas (keeps CanvasItem batch intact).
static func pixel(canvas: CanvasItem, at: Vector2, color: Color) -> void:
	canvas.draw_texture_rect_region(_atlas_tex(), Rect2(at, Vector2.ONE), _SRC_PIXEL, color)


## Draws an unshaded rectangle using the shared VoidGlow atlas (keeps CanvasItem batch intact).
static func rect(canvas: CanvasItem, region: Rect2, color: Color) -> void:
	canvas.draw_texture_rect_region(_atlas_tex(), region, _SRC_PIXEL, color)


## A double heartbeat (lub-dub) in 0..1; `phase` offsets it, a vein passes `-distance * 0.012` so the pulse runs along it.
static func beat(time: float, phase: float = 0.0, rate: float = 0.8) -> float:
	var x: float = fposmod(time * rate + phase, 1.0)
	return clampf(exp(-pow((x - 0.08) * 13.0, 2.0)) + 0.65 * exp(-pow((x - 0.3) * 13.0, 2.0)), 0.0, 1.0)


## The resting glow with the heartbeat on top: never fully dark, bright on the beat.
static func pulse(time: float, phase: float = 0.0, rate: float = 0.8, floor_value: float = 0.38) -> float:
	return floor_value + (1.0 - floor_value) * beat(time, phase, rate)


## A one pixel light. `bloom` up to 0.5 is a vein pixel (a faint 3x3 so a line stays a thin line); above it is an eye or a core: a stronger 3x3 plus 5x5 and 7x7 steps that scale with `bloom`.
static func halo(canvas: CanvasItem, point: Vector2, color: Color, strength: float, bloom: float = 0.5) -> void:
	if strength <= 0.01:
		return
	var tex: ImageTexture = _atlas_tex()
	var ax: float = roundf(point.x)
	var ay: float = roundf(point.y)
	var s: float = clampf(strength * INTENSITY, 0.0, 1.5)
	if bloom > 0.5:
		canvas.draw_texture_rect_region(tex, Rect2(ax - 3.0, ay - 3.0, 7.0, 7.0), _SRC_SPOT, Color(color, s))
		var cs: float = minf(1.0, s)
		canvas.draw_texture_rect_region(tex, Rect2(ax, ay, 1.0, 1.0), _SRC_PIXEL, Color(color.lerp(Color.WHITE, 0.25 * cs), cs))
	else:
		canvas.draw_texture_rect_region(tex, Rect2(ax - 1.0, ay - 1.0, 3.0, 3.0), _SRC_VEIN, Color(color, s))
