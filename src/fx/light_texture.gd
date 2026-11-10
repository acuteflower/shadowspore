class_name LightTexture
extends RefCounted
## Light cookies for PointLight2D: flat ellipses (a pool of light on the ground in the 3/4 view) with a bright core, a smooth
## fall-off and a slightly irregular edge (a few variants, so no two pools look alike). One texture per size, cached.
##
## Why smooth: the cookies used to be six posterised steps with a 4x4 Bayer dither, drawn at one texel per art pixel. The window is
## a multiple of 640x360 (1280x720 and up), so every texel became a 2x2+ block and the pools read as blocky rings. Now the fall-off
## is continuous (8 bit, with a hair of noise against banding) and `apply` draws the cookie with `SUPERSAMPLE` texels per art pixel,
## so the project's nearest-neighbour filter has nothing left to make blocky.

const SUPERSAMPLE: int = 2 ## texels per art pixel; with the window at 2x (1280x720) this is one texel per screen pixel
const DEFAULT_RADII: PackedInt32Array = [24, 26, 28, 34, 36, 40, 44, 46, 60]

static var _cache: Dictionary = {}


## Gives `light` a cookie that is `width` art pixels wide, at full detail. Use this for every PointLight2D.
static func apply(light: PointLight2D, width: int, squash: float = 0.6, variant: int = 0) -> void:
	light.texture = get_texture(width * SUPERSAMPLE, squash, variant)
	light.texture_scale = 1.0 / float(SUPERSAMPLE)


## Generates the cookies of common light radii up front (one picture costs a few ms of GDScript; the first light of a size used to
## cause that hitch while a chunk streamed in). `radii` are NightLight radii; the three variants and `squash` are the ones
## NightLight picks by default, so later `apply` calls hit the cache. The textures are identical to the lazy ones.
## Prewarms common and extended radii (including 44, 46, 60) so boss, trees and interiors never hitch on spawn.
static func prewarm(radii: PackedInt32Array = DEFAULT_RADII, squash: float = 0.6) -> void:
	for radius: int in radii:
		for variant: int in 3:
			get_texture(radius * 2 * SUPERSAMPLE, squash, variant)
	for extra: int in [44, 46, 60]:
		if not radii.has(extra):
			for variant: int in 3:
				get_texture(extra * 2 * SUPERSAMPLE, squash, variant)
	for variant: int in 3:
		get_texture(60 * 2 * SUPERSAMPLE, 0.8, variant)


## The raw cookie, `width` texels square (square: a non-square cookie got clipped by the renderer). Drawn at texture_scale 1 it is
## smooth but one texel per art pixel; prefer `apply`.
static func get_texture(width: int, squash: float = 0.6, variant: int = 0) -> Texture2D:
	var key: String = "%d_%d_%d" % [width, int(squash * 100.0), variant]
	if _cache.has(key):
		return _cache[key]
	var rx: float = width * 0.5
	var ry: float = maxf(2.0, rx * squash)
	var data: PackedByteArray = PackedByteArray()
	data.resize(width * width * 4)
	var at: int = 0
	for y: int in width:
		var dy: float = (y + 0.5 - rx) / ry
		for x: int in width:
			var dx: float = (x + 0.5 - rx) / rx
			var angle: float = atan2(dy, dx)
			var wobble: float = 1.0 + 0.08 * sin(3.0 * angle + variant * 2.1) + 0.05 * sin(5.0 * angle + variant * 4.7)
			var distance: float = sqrt(dx * dx + dy * dy)
			var v: float = clampf(1.0 - distance / wobble, 0.0, 1.0)
			v = pow(v, 1.8) * (1.0 - smoothstep(0.88, 1.0, distance)) ## bright core, quick fall-off, and never a cut at the texture's border
			var noise: float = float(((x * 73856093) ^ (y * 19349663)) & 255) / 255.0 - 0.5 ## under one 8 bit step: only breaks up banding
			var level: int = clampi(roundi(v * 255.0 + noise * 0.9), 0, 255)
			data[at] = level
			data[at + 1] = level
			data[at + 2] = level
			data[at + 3] = 255
			at += 4
	var image: Image = Image.create_from_data(width, width, false, Image.FORMAT_RGBA8, data)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture
