class_name LightTexture
extends RefCounted
## Light cookies for PointLight2D with a stepped, dithered falloff, so light pools match the pixel
## look. They are flat ellipses (a pool of light on the ground in the 3/4 view), have a bright core
## and a slightly irregular edge (a few variants, so no two pools look alike). One texture per
## size, cached; draw it at scale 1 so the dither stays on the pixel grid.

const STEPS: int = 6
const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _cache: Dictionary = {}


static func get_texture(width: int, squash: float = 0.6, variant: int = 0) -> Texture2D:
	var key: String = "%d_%d_%d" % [width, int(squash * 100.0), variant]
	if _cache.has(key):
		return _cache[key]
	var image: Image = Image.create(width, width, false, Image.FORMAT_RGBA8) ## square: a non-square cookie got clipped by the renderer
	var rx: float = width * 0.5
	var ry: float = maxf(2.0, rx * squash)
	for y: int in width:
		for x: int in width:
			var dx: float = (x + 0.5 - rx) / rx
			var dy: float = (y + 0.5 - rx) / ry
			var angle: float = atan2(dy, dx)
			var wobble: float = 1.0 + 0.08 * sin(3.0 * angle + variant * 2.1) + 0.05 * sin(5.0 * angle + variant * 4.7)
			var v: float = clampf(1.0 - sqrt(dx * dx + dy * dy) / wobble, 0.0, 1.0)
			v = pow(v, 1.8) ## bright core, quick falloff
			var dither: float = (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0 - 0.5
			var level: float = clampf(floorf(v * STEPS + 0.5 + dither * 0.55) / STEPS, 0.0, 1.0)
			image.set_pixel(x, y, Color(level, level, level, 1.0))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
