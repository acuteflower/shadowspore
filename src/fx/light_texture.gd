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
const MAX_TEX_WIDTH: int = 128 ## soft falloff cookies upscale seamlessly with linear filtering above 128px
const BUCKET_STEP: int = 16
const COMMON_BUCKETS: PackedInt32Array = [32, 48, 64, 80, 96, 112, 128]
const COMMON_SQUASHES: PackedFloat32Array = [0.55, 0.60, 0.65, 0.70, 0.75, 0.80]

static var _cache: Dictionary = {}
static var _alpha_templates: Dictionary = {} ## width -> zeroed RGB / 255 A template byte array


## Gives `light` a cookie that is `width` art pixels wide, at full detail. Use this for every PointLight2D.
static func apply(light: PointLight2D, width: int, squash: float = 0.6, variant: int = 0) -> void:
	var q_squash: float = snappedf(clampf(squash, 0.25, 2.0), 0.05)
	var tex_w: int = clampi(int(roundf(float(width * SUPERSAMPLE) / float(BUCKET_STEP))) * BUCKET_STEP, 32, MAX_TEX_WIDTH)
	light.texture = get_texture(tex_w, q_squash, variant)
	light.texture_scale = float(width) / float(tex_w)
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## Generates the cookies of common light radii up front (one picture costs a few ms of GDScript; the first light of a size used to
## cause that hitch while a chunk streamed in). `radii` are NightLight radii; the three variants and `squash` are the ones
## NightLight picks by default, so later `apply` calls hit the cache. The textures are identical to the lazy ones.
## Prewarms bucketed cookie sizes and common squashes (including ancient_fir, trees and interiors) so streaming never hitches.
static func prewarm(radii: PackedInt32Array = DEFAULT_RADII, squash: float = 0.6) -> void:
	for w: int in COMMON_BUCKETS:
		for s: float in COMMON_SQUASHES:
			for variant: int in 3:
				get_texture(w, s, variant)
	for radius: int in radii:
		var q_squash: float = snappedf(clampf(squash, 0.25, 2.0), 0.05)
		var tex_w: int = clampi(int(roundf(float(radius * 2 * SUPERSAMPLE) / float(BUCKET_STEP))) * BUCKET_STEP, 32, MAX_TEX_WIDTH)
		for variant: int in 3:
			get_texture(tex_w, q_squash, variant)


## The raw cookie, `width` texels square (square: a non-square cookie got clipped by the renderer). Drawn at texture_scale 1 it is
## smooth but one texel per art pixel; prefer `apply`.
static func get_texture(width: int, squash: float = 0.6, variant: int = 0) -> Texture2D:
	var key: String = "%d_%d_%d" % [width, int(roundf(squash * 100.0)), variant]
	if _cache.has(key):
		return _cache[key]
	var rx: float = width * 0.5
	var ry: float = maxf(2.0, rx * squash)
	var data: PackedByteArray = _blank_cookie(width)
	var p3: float = float(variant) * 2.1
	var p5: float = float(variant) * 4.7
	var cp3: float = cos(p3)
	var sp3: float = sin(p3)
	var cp5: float = cos(p5)
	var sp5: float = sin(p5)
	var y_min: int = maxi(0, int(floorf(rx - ry)) - 1)
	var y_max: int = mini(width, int(ceilf(rx + ry)) + 1)
	var row_stride: int = width * 4
	for y: int in range(y_min, y_max):
		var dy: float = (y + 0.5 - rx) / ry
		var dy2: float = dy * dy
		if dy2 >= 1.0:
			continue
		var max_dx: float = sqrt(1.0 - dy2) * rx
		var x_min: int = maxi(0, int(floorf(rx - max_dx)) - 1)
		var x_max: int = mini(width, int(ceilf(rx + max_dx)) + 1)
		var at: int = y * row_stride + x_min * 4
		for x: int in range(x_min, x_max):
			var dx: float = (x + 0.5 - rx) / rx
			var dist2: float = dx * dx + dy2
			if dist2 >= 1.0:
				at += 4
				continue
			var level: int = 255
			if dist2 > 0.000001:
				var distance: float = sqrt(dist2)
				var inv_d: float = 1.0 / distance
				var c: float = dx * inv_d
				var s: float = dy * inv_d
				var c2: float = c * c
				var s2: float = s * s
				var sin3: float = 3.0 * s - 4.0 * s * s2
				var cos3: float = 4.0 * c * c2 - 3.0 * c
				var sin5: float = s * (16.0 * s2 * s2 - 20.0 * s2 + 5.0)
				var cos5: float = c * (16.0 * c2 * c2 - 20.0 * c2 + 5.0)
				var w3: float = sin3 * cp3 + cos3 * sp3
				var w5: float = sin5 * cp5 + cos5 * sp5
				var wobble: float = 1.0 + 0.08 * w3 + 0.05 * w5
				var v: float = clampf(1.0 - distance / wobble, 0.0, 1.0)
				v = pow(v, 1.8) * (1.0 - smoothstep(0.88, 1.0, distance)) ## bright core, quick fall-off, and never a cut at the texture's border
				var noise: float = float(((x * 73856093) ^ (y * 19349663)) & 255) / 255.0 - 0.5 ## under one 8 bit step: only breaks up banding
				level = clampi(roundi(v * 255.0 + noise * 0.9), 0, 255)
			data[at] = level
			data[at + 1] = level
			data[at + 2] = level
			at += 4
	var image: Image = Image.create_from_data(width, width, false, Image.FORMAT_RGBA8, data)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


static func _blank_cookie(width: int) -> PackedByteArray:
	if _alpha_templates.has(width):
		return (_alpha_templates[width] as PackedByteArray).duplicate()
	var tmpl: PackedByteArray = PackedByteArray()
	var px_count: int = width * width
	tmpl.resize(px_count * 4)
	tmpl.fill(0)
	var at: int = 3
	for _i: int in px_count:
		tmpl[at] = 255
		at += 4
	_alpha_templates[width] = tmpl
	return tmpl.duplicate()
