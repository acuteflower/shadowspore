class_name GroundSurfaces
extends Node2D
## Next-gen continuous ground material, antique stone slab & woodland floor detail layer.
## - Paints pixel-frayed dirt paths, gravel tracks, rich woodland humus, plush moss carpets,
##   damp earth, mud margins & standing mirror woodland puddles onto a lightweight 2x2 px surface map.
## - Places handcrafted antique stone slabs, stepping stones, moon-ring rondell & woodland details
##   (fallen leaf litter, creeping roots, mossy rocks, twigs & glowing forest mushrooms).
## - Registers with `Terrain.patches` so `FootstepComponent` & `Player` automatically react with exact
##   footstep audio, dust/mud/splash puffs, footprints, soaked boots & surface speed multipliers.
## - Exposes `grass_habitat_at(world_pos)` so `LivingGrass` organically frays along paths, tucks moss
##   & clover into antique stone seams, avoids standing puddles, and shifts to shaded ferns in forests.

const TREE_BUCKET_PX: float = 128.0 ## bigger than any crown's drip line
const FOREST_NOISE_PX: float = 2.0 ## world px per texel of the forest noise (= one surface cell)
const FOREST_NOISE_SIZE: int = 256 ## the forest noise repeats every 512 px
const SURFACE_SHADER: Shader = preload("res://assets/shaders/ground_surfaces.gdshader")
const PROP_LIT_SHADER: Shader = preload("res://assets/shaders/ground_prop_lit.gdshader")
const SLAB_TEX: Texture2D = preload("res://assets/tiles/ancient_stones.png")
const SLAB_GLOW_TEX: Texture2D = preload("res://assets/tiles/ancient_stones_glow.png")
const COURTYARD_TEX: Texture2D = preload("res://assets/tiles/ancient_courtyard.png")
const COURTYARD_GLOW_TEX: Texture2D = preload("res://assets/tiles/ancient_courtyard_glow.png")
const FOREST_TEX: Texture2D = preload("res://assets/tiles/forest_floor_details.png")
const FOREST_GLOW_TEX: Texture2D = preload("res://assets/tiles/forest_floor_details_glow.png")

const SLAB_CELL: Vector2 = Vector2(32.0, 24.0)
const FOREST_CELL: Vector2 = Vector2(24.0, 20.0)

class StoneFootprint:
	var center: Vector2 = Vector2.ZERO
	var radii: Vector2 = Vector2(12.0, 7.5)
	var is_courtyard: bool = false


class TreeMicroZone:
	var center: Vector2 = Vector2.ZERO
	var trunk_r: float = 12.0
	var crown_r: float = 64.0

var bounds: Rect2 = Rect2()
var cell_px: float = 2.0
var slab_count: int = 0
var detail_count: int = 0

var _map_w: int = 0
var _map_h: int = 0
var _surface_img: Image
var _detail_img: Image
var _surface_tex: ImageTexture
var _detail_tex: ImageTexture
var _surface_mat: ShaderMaterial
var _prop_mat: ShaderMaterial
var _surface_rect: ColorRect
var _props_root: Node2D
var _glow_root: Node2D
var _stones: Array[StoneFootprint] = []
var _trees: Array[TreeMicroZone] = []
var _forest_mask: Image ## `set_forest_mask`: drawn by the shader, asked by `_forest_cell`
var _forest_origin: Vector2 = Vector2.ZERO
var _forest_texel: float = 16.0
var _forest_noise: Image
var _forest_mask_tex: ImageTexture
var _forest_noise_tex: ImageTexture
var _tree_buckets: Dictionary = {} ## Vector2i -> PackedInt32Array of `_trees` indices (grass queries look at 3x3)
var _surf_bytes: PackedByteArray = PackedByteArray()
var _det_bytes: PackedByteArray = PackedByteArray()
var _fmask_bytes: PackedByteArray = PackedByteArray()
var _fmask_w: int = 0
var _fmask_h: int = 0
var _fmask_stride: int = 1
var _fnoise_bytes: PackedByteArray = PackedByteArray()
var _tree_near: PackedByteArray = PackedByteArray()
var _tb_ox: int = 0
var _tb_oy: int = 0
var _tb_w: int = 0
var _tb_h: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not Terrain.patches.has(self):
		Terrain.patches.append(self)
	tree_exiting.connect(func() -> void: Terrain.patches.erase(self))


func setup(world_rect: Rect2, texel_px: float = 2.0) -> void:
	bounds = world_rect
	cell_px = maxf(1.0, texel_px)
	_map_w = maxi(8, ceili(world_rect.size.x / cell_px))
	_map_h = maxi(8, ceili(world_rect.size.y / cell_px))
	_surface_img = Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	_surface_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_detail_img = Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	_detail_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_stones.clear()
	_trees.clear()
	_tree_buckets.clear()
	slab_count = 0
	detail_count = 0

	_prop_mat = ShaderMaterial.new()
	_prop_mat.shader = PROP_LIT_SHADER

	if _props_root != null:
		_props_root.queue_free()
	_props_root = Node2D.new()
	_props_root.name = "GroundProps"
	_props_root.z_as_relative = false
	_props_root.z_index = -9
	add_child(_props_root)

	if _glow_root != null:
		_glow_root.queue_free()
	_glow_root = Node2D.new()
	_glow_root.name = "GroundPropGlow"
	_glow_root.z_as_relative = false
	_glow_root.z_index = -8
	_glow_root.visible = false
	add_child(_glow_root)


func _world_to_px(world_pos: Vector2) -> Vector2i:
	var rel: Vector2 = (world_pos - bounds.position) / cell_px
	return Vector2i(floori(rel.x), floori(rel.y))


func _px_to_world(ix: int, iy: int) -> Vector2:
	return bounds.position + Vector2((float(ix) + 0.5) * cell_px, (float(iy) + 0.5) * cell_px)


## Smooth Catmull-Rom spline subdivision so ways & cobble lanes curve organically without straight-segment kinks.
static func _subdivide_catmull(pts: Array[Vector2], subdiv: int = 5) -> Array[Vector2]:
	if pts.size() <= 2 or subdiv <= 1:
		return pts
	var out: Array[Vector2] = []
	var n: int = pts.size()
	for i: int in n - 1:
		var p0: Vector2 = pts[maxi(0, i - 1)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(n - 1, i + 2)]
		var steps: int = subdiv if i < n - 2 else subdiv + 1
		for s: int in steps:
			var t: float = float(s) / float(subdiv)
			var t2: float = t * t
			var t3: float = t2 * t
			var q: Vector2 = 0.5 * (
				(2.0 * p1)
				+ (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
			)
			out.append(q)
	return out


## Paints an organic, spline-smoothed cobble / river-pebble lane (surface G). Dirt ways use `paint_way`.
func paint_cobble_lane(raw_points: Array[Vector2], half_width: float, seed_val: int = 17, taper_end: bool = false, taper_start: bool = false) -> void:
	if raw_points.size() < 2 or _surface_img == null:
		return
	var points: Array[Vector2] = _subdivide_catmull(raw_points, 5)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.030
	noise.fractal_octaves = 2

	var total_len: float = 0.0
	var seg_lens: Array[float] = []
	for s: int in points.size() - 1:
		var sl: float = points[s].distance_to(points[s + 1])
		seg_lens.append(sl)
		total_len += sl

	var pad: float = half_width + 18.0
	var bb: Rect2 = Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		bb = bb.expand(p)
	bb = bb.grow(pad)

	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)

	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var min_d: float = 1e9
			var best_along: float = 0.0
			var accum: float = 0.0
			for seg: int in points.size() - 1:
				var a: Vector2 = points[seg]
				var b: Vector2 = points[seg + 1]
				var ab: Vector2 = b - a
				var l2: float = ab.length_squared()
				var t_seg: float = clampf((wp - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0001 else 0.0
				var d: float = wp.distance_to(a + ab * t_seg)
				if d < min_d:
					min_d = d
					best_along = accum + seg_lens[seg] * t_seg
				accum += seg_lens[seg]

			var u_along: float = best_along / maxf(total_len, 1.0)
			var taper: float = 1.0
			if taper_start and total_len > 20.0:
				taper *= smoothstep(0.0, 0.25, u_along) * 0.65 + 0.35
			if taper_end and total_len > 20.0:
				taper *= smoothstep(1.0, 0.62, u_along) * 0.65 + 0.35
			var wob: float = noise.get_noise_2d(wp.x, wp.y) * (half_width * 0.32)
			var eff_w: float = (half_width + wob) * taper
			if min_d > eff_w + 10.0:
				continue
			var w_scale: float = (0.48 + 0.52 * taper) if (taper_start or taper_end) else 1.0
			var w_val: float = (1.0 - smoothstep(eff_w * 0.48, eff_w + 7.5, min_d)) * w_scale
			if w_val <= 0.01:
				continue
			var sc: Color = _surface_img.get_pixel(ix, iy)
			sc.g = maxf(sc.g, w_val)
			_surface_img.set_pixel(ix, iy, sc)


## Trodden ways, three kinds (`paint_way`). All are worn INTO the ground: surface R = wear
## (low = flattened grass, mid = soil breaking through, high = bare packed soil), detail A = wheel rut.
##   trail: narrow footpath that wanders and comes and goes in the grass
##   path:  wide trodden way, bare core, grassy worn shoulders
##   cart:  two wheel ruts at `gauge` from the centre with a short-grass median
const WAY_KINDS: Dictionary = {
	"trail": {"half": 4.5, "wobble": 1.4, "meander": 3.2, "shoulder": 3.5, "peak": 0.88, "gaps": 0.42},
	"path": {"half": 9.0, "wobble": 2.2, "meander": 3.0, "shoulder": 8.5, "peak": 0.94, "gaps": 0.06},
	"cart": {"half": 11.5, "wobble": 1.2, "meander": 2.0, "shoulder": 4.5, "peak": 0.52, "gaps": 0.0, "gauge": 6.8, "rut": 2.8},
}


## Paints a spline-smoothed trodden way of `kind` ("trail" / "path" / "cart") along `raw_points`.
## Set `fade_start` / `fade_end` = false when the way meets a stone courtyard threshold flush!
func paint_way(
	raw_points: Array[Vector2],
	kind: String,
	seed_val: int = 17,
	damp: float = 0.0,
	taper_end: bool = false,
	fade_start: bool = true,
	fade_end: bool = true
) -> void:
	if raw_points.size() < 2 or _surface_img == null:
		return
	var points: Array[Vector2] = _subdivide_catmull(raw_points, 5)
	var spec: Dictionary = WAY_KINDS.get(kind, WAY_KINDS["path"]) as Dictionary
	var half: float = float(spec["half"])
	var wobble: float = float(spec["wobble"])
	var meander: float = float(spec["meander"])
	var shoulder: float = float(spec["shoulder"])
	var peak: float = float(spec["peak"])
	var gaps: float = float(spec["gaps"])
	var gauge: float = float(spec.get("gauge", 0.0))
	var rut_half: float = float(spec.get("rut", 0.0))

	var width_noise: FastNoiseLite = FastNoiseLite.new()
	width_noise.seed = seed_val
	width_noise.frequency = 0.05
	var along_noise: FastNoiseLite = FastNoiseLite.new()
	along_noise.seed = seed_val + 7
	along_noise.frequency = 0.018

	var total_len: float = 0.0
	var seg_lens: Array[float] = []
	for s: int in points.size() - 1:
		var sl: float = points[s].distance_to(points[s + 1])
		seg_lens.append(sl)
		total_len += sl

	var bb: Rect2 = Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		bb = bb.expand(p)
	bb = bb.grow(half + wobble + meander + shoulder + 4.0)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)

	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var min_d: float = 1e9
			var side: float = 1.0
			var along: float = 0.0
			var accum: float = 0.0
			for seg: int in points.size() - 1:
				var a: Vector2 = points[seg]
				var ab: Vector2 = points[seg + 1] - a
				var l2: float = ab.length_squared()
				var t_seg: float = clampf((wp - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0001 else 0.0
				var d: float = wp.distance_to(a + ab * t_seg)
				if d < min_d:
					min_d = d
					side = 1.0 if ab.cross(wp - a) >= 0.0 else -1.0
					along = accum + seg_lens[seg] * t_seg
				accum += seg_lens[seg]

			# Lateral offset from the drawn line: the way wanders a little like a real trodden one.
			var ax: float = absf(min_d * side - along_noise.get_noise_1d(along) * meander)
			var half_w: float = half + width_noise.get_noise_2d(wp.x, wp.y) * wobble
			# Optional soft grass fade at open ends; stays flush full-width when meeting a stone threshold (`fade_start/end = false`).
			var f_start: float = smoothstep(0.0, 22.0, along) if fade_start else 1.0
			var f_end: float = smoothstep(0.0, 22.0, total_len - along) if fade_end else 1.0
			var fade: float = f_start * f_end
			half_w *= lerpf(0.3, 1.0, fade)
			if taper_end and total_len > 20.0:
				fade *= 1.0 - smoothstep(0.6, 1.0, along / total_len)
				half_w *= lerpf(0.45, 1.0, fade)
			if ax > half_w + shoulder:
				continue
			var edge: float = 1.0 - smoothstep(half_w - shoulder * 0.5, half_w + shoulder, ax)
			# Where few walk the grass closes over the way for a stretch.
			var gap: float = gaps * smoothstep(0.05, 0.45, along_noise.get_noise_1d(along * 1.9 + 300.0))
			# Patches where the grass holds on even in the middle of the way.
			var hold: float = smoothstep(0.15, 0.6, width_noise.get_noise_2d(wp.x * 1.7 + 91.0, wp.y * 1.7 - 37.0))
			var wear: float = edge * peak * (1.0 - gap * 0.6) * (1.0 - hold * 0.28) * fade
			var rut: float = 0.0
			if gauge > 0.0:
				rut = (1.0 - smoothstep(rut_half * 0.5, rut_half + 1.4, absf(ax - gauge))) * fade
				var median: float = 0.30 * (1.0 - smoothstep(gauge - rut_half - 1.0, gauge - rut_half + 0.5, ax))
				wear = maxf(edge * maxf(wear, median), rut * 0.96)
			if wear <= 0.01 and rut <= 0.01:
				continue
			var sc: Color = _surface_img.get_pixel(ix, iy)
			sc.r = maxf(sc.r, wear)
			if damp > 0.0:
				sc.a = maxf(sc.a, (wear * 0.45 + rut * 0.55) * damp)
			_surface_img.set_pixel(ix, iy, sc)
			if rut > 0.01:
				var dc: Color = _detail_img.get_pixel(ix, iy)
				dc.a = maxf(dc.a, rut)
				_detail_img.set_pixel(ix, iy, dc)


## Paints a rich woodland floor biome zone with frayed organic borders, plush moss banks & canopy shade.
func paint_forest_zone(rect: Rect2, blend_margin: float = 34.0, seed_val: int = 101) -> void:
	if _surface_img == null:
		return
	var edge_n: FastNoiseLite = FastNoiseLite.new()
	edge_n.seed = seed_val
	edge_n.frequency = 0.018
	edge_n.fractal_octaves = 2

	var moss_n: FastNoiseLite = FastNoiseLite.new()
	moss_n.seed = seed_val + 53
	moss_n.frequency = 0.022
	moss_n.fractal_octaves = 2

	var shade_n: FastNoiseLite = FastNoiseLite.new()
	shade_n.seed = seed_val + 127
	shade_n.frequency = 0.014
	shade_n.fractal_octaves = 2

	var bb: Rect2 = rect.grow(blend_margin + 12.0)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)

	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			# Signed distance inside BOTH left and right borders -> organic woodland transitions into both Square 2 & Square 4!
			var wob_l: float = edge_n.get_noise_2d(wp.x, wp.y) * 28.0
			var wob_r: float = edge_n.get_noise_2d(wp.x + 313.0, wp.y - 97.0) * 32.0
			var inside_l: float = wp.x - (rect.position.x + wob_l)
			var inside_r: float = (rect.end.x + wob_r) - wp.x
			var fw: float = minf(
				smoothstep(-blend_margin * 0.45, blend_margin * 0.85, inside_l),
				smoothstep(-blend_margin * 0.45, blend_margin * 0.85, inside_r)
			)
			if fw <= 0.01:
				continue
			var sc: Color = _surface_img.get_pixel(ix, iy)
			var dc: Color = _detail_img.get_pixel(ix, iy)
			sc.b = maxf(sc.b, fw)
			# Organic velvet moss carpets weaving over the dark forest humus
			var mn: float = moss_n.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			if mn > 0.50:
				var mw: float = smoothstep(0.50, 0.72, mn) * fw * 0.92
				dc.r = maxf(dc.r, mw)
			# Deep woodland canopy dappled shade pools
			var sh: float = clampf((shade_n.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5) * 0.85 + 0.15, 0.0, 1.0)
			dc.b = maxf(dc.b, sh * fw * 0.78)
			_surface_img.set_pixel(ix, iy, sc)
			_detail_img.set_pixel(ix, iy, dc)


## Forest floor from a coverage mask (2.0 zones: the planned stands and belts, any outline). `mask` is an L8 image
## whose texel (i, j) covers `texel_px` world px from `origin_px`, its value meant at the texel's centre (blur it first
## for a soft edge). Nothing is painted per cell: the surface shader reads the mask and a tileable noise texture
## (edge wobble, moss, canopy shade) and lays the humus itself, and `surface_at` / `grass_habitat_at` ask the very same
## data (`_forest_cell`), so a zone of any size costs only its mask. Same channels as `paint_forest_zone` (b = humus,
## detail r = moss, detail b = shade); combined with painted forest by max.
func set_forest_mask(mask: Image, origin_px: Vector2, texel_px: float, seed_val: int = 101) -> void:
	_forest_mask = mask
	_forest_origin = origin_px
	_forest_texel = maxf(1.0, texel_px)
	_forest_noise = _make_forest_noise(seed_val)


## Three tileable noises in one RGB8 image (edge wobble, moss, canopy shade), one texel per `FOREST_NOISE_PX`.
static func _make_forest_noise(seed_val: int) -> Image:
	var size: int = FOREST_NOISE_SIZE
	var freqs: Array[float] = [0.03, 0.022, 0.014]
	var layers: Array[Image] = []
	for k: int in 3:
		var n: FastNoiseLite = FastNoiseLite.new()
		n.seed = seed_val + [0, 53, 127][k]
		n.frequency = freqs[k] * FOREST_NOISE_PX
		n.fractal_octaves = 2
		var img: Image = n.get_seamless_image(size, size, false, false, 0.1, true)
		img.convert(Image.FORMAT_L8)
		layers.append(img)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(size * size * 3)
	var a: PackedByteArray = layers[0].get_data()
	var b: PackedByteArray = layers[1].get_data()
	var c: PackedByteArray = layers[2].get_data()
	for i: int in size * size:
		bytes[i * 3] = a[i]
		bytes[i * 3 + 1] = b[i]
		bytes[i * 3 + 2] = c[i]
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)


## Forest at a world point: x = humus (0..1), y = moss, z = canopy shade; what the shader draws there.
func _forest_cell(world_pos: Vector2) -> Vector3:
	if _forest_mask == null:
		return Vector3.ZERO
	var f: Vector2 = (world_pos - _forest_origin) / _forest_texel - Vector2(0.5, 0.5)
	var x0: int = floori(f.x)
	var y0: int = floori(f.y)
	var fx: float = f.x - float(x0)
	var fy: float = f.y - float(y0)
	var mw: int = _forest_mask.get_width() - 1
	var mh: int = _forest_mask.get_height() - 1
	var v00: float = _forest_mask.get_pixel(clampi(x0, 0, mw), clampi(y0, 0, mh)).r
	var v10: float = _forest_mask.get_pixel(clampi(x0 + 1, 0, mw), clampi(y0, 0, mh)).r
	var v01: float = _forest_mask.get_pixel(clampi(x0, 0, mw), clampi(y0 + 1, 0, mh)).r
	var v11: float = _forest_mask.get_pixel(clampi(x0 + 1, 0, mw), clampi(y0 + 1, 0, mh)).r
	var m: float = lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy)
	if m < 0.04:
		return Vector3.ZERO
	var q: Vector2i = Vector2i(floori(world_pos.x / FOREST_NOISE_PX), floori(world_pos.y / FOREST_NOISE_PX))
	var n: Color = _forest_noise.get_pixel(posmod(q.x, FOREST_NOISE_SIZE), posmod(q.y, FOREST_NOISE_SIZE))
	var fw: float = smoothstep(0.3, 0.72, m + (n.r * 2.0 - 1.0) * 0.24)
	if fw <= 0.01:
		return Vector3.ZERO
	var moss: float = smoothstep(0.50, 0.72, n.g) * fw * 0.92
	var shade: float = clampf(n.b * 0.85 + 0.15, 0.0, 1.0) * fw * 0.78
	return Vector3(fw, moss, shade)


## A tree's micro-zone for the grass (root collar, drip line) without painting its ground (many trees in a wood).
func add_tree_zone(center: Vector2, trunk_r: float, crown_r: float) -> void:
	var tz: TreeMicroZone = TreeMicroZone.new()
	tz.center = center
	tz.trunk_r = maxf(trunk_r, 4.0)
	tz.crown_r = maxf(crown_r, 12.0)
	_add_tree_zone(tz)


func _add_tree_zone(tz: TreeMicroZone) -> void:
	_trees.append(tz)
	var cell: Vector2i = Vector2i(floori(tz.center.x / TREE_BUCKET_PX), floori(tz.center.y / TREE_BUCKET_PX))
	var list: PackedInt32Array = _tree_buckets.get(cell, PackedInt32Array()) as PackedInt32Array
	list.append(_trees.size() - 1)
	_tree_buckets[cell] = list


## Smoothly widens a road fork or courtyard junction so paths flare naturally where travellers turn.
func paint_junction_fillet(center: Vector2, radii: Vector2, channel: String = "path", strength: float = 0.90) -> void:
	if _surface_img == null:
		return
	var bb: Rect2 = Rect2(center - radii * 1.3, radii * 2.6)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var d: float = ((wp - center) / radii).length()
			if d >= 1.0:
				continue
			var w: float = (1.0 - smoothstep(0.38, 1.0, d)) * strength
			var sc: Color = _surface_img.get_pixel(ix, iy)
			if channel == "gravel":
				sc.g = maxf(sc.g, w)
			else:
				sc.r = maxf(sc.r, w)
			_surface_img.set_pixel(ix, iy, sc)


## Paints a soft plush moss pocket (great beside antique ruins, shaded paths or wet forest banks).
func paint_moss_patch(center: Vector2, radii: Vector2, strength: float = 0.88, seed_val: int = 33) -> void:
	if _detail_img == null:
		return
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.045
	var bb: Rect2 = Rect2(center - radii * 1.4, radii * 2.8)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var rel: Vector2 = (wp - center) / radii
			var d: float = rel.length() + noise.get_noise_2d(wp.x, wp.y) * 0.34
			if d >= 1.15:
				continue
			var mw: float = (1.0 - smoothstep(0.32, 1.12, d)) * strength
			var dc: Color = _detail_img.get_pixel(ix, iy)
			dc.r = maxf(dc.r, mw)
			_detail_img.set_pixel(ix, iy, dc)


## Paints a natural moisture depression: damp earth collar -> dark mud -> standing mirror woodland puddle (`peak > 0.82`).
func paint_moisture_hollow(center: Vector2, radii: Vector2, peak: float = 0.94, seed_val: int = 89) -> void:
	if _surface_img == null:
		return
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.036
	noise.fractal_octaves = 2
	var bb: Rect2 = Rect2(center - radii * 1.5, radii * 3.0)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var rel: Vector2 = (wp - center) / radii
			var d: float = rel.length() + noise.get_noise_2d(wp.x, wp.y) * 0.32
			if d >= 1.25:
				continue
			var hw: float = clampf((1.0 - smoothstep(0.18, 1.22, d)) * peak, 0.0, 1.0)
			var sc: Color = _surface_img.get_pixel(ix, iy)
			sc.a = maxf(sc.a, hw)
			_surface_img.set_pixel(ix, iy, sc)


## Places a handcrafted antique stone slab (variant 0..15) with soil-bed AO, surface footprint & optional night rune glow.
func add_ancient_slab(world_pos: Vector2, variant: int, flip_h: bool = false, tint: Color = Color.WHITE) -> void:
	var v: int = clampi(variant, 0, 15)
	var pos: Vector2 = world_pos.round()
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = SLAB_TEX
	sp.region_enabled = true
	sp.region_rect = Rect2(float(v) * SLAB_CELL.x, 0.0, SLAB_CELL.x, SLAB_CELL.y)
	sp.position = pos
	sp.flip_h = flip_h
	sp.modulate = tint
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.material = _prop_mat
	_props_root.add_child(sp)
	slab_count += 1

	# Carved antique relic slabs (9, 13) carry subtle unlit night rune glow!
	if v == 9 or v == 13:
		var gl: Sprite2D = Sprite2D.new()
		gl.texture = SLAB_GLOW_TEX
		gl.region_enabled = true
		gl.region_rect = sp.region_rect
		gl.position = pos
		gl.flip_h = flip_h
		gl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		gl.material = Unlit.material()
		_glow_root.add_child(gl)

	var fp: StoneFootprint = StoneFootprint.new()
	fp.center = pos + Vector2(0.0, 0.5)
	if v >= 10 and v <= 13:
		fp.radii = Vector2(11.5, 6.5)
	elif v >= 14:
		fp.radii = Vector2(10.5, 6.5)
	elif v == 8:
		fp.radii = Vector2(13.5, 5.5)
	else:
		fp.radii = Vector2(13.0, 7.8)
	_stones.append(fp)
	_stamp_stone_ao(fp.center, fp.radii + Vector2(2.5, 2.5))


## Places the cohesive 112x80 Ancient Sanctuary Waystone Courtyard (interlocking flagstones + carved crescent medallion).
func add_ancient_courtyard(world_pos: Vector2) -> void:
	var pos: Vector2 = world_pos.round()
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = COURTYARD_TEX
	sp.position = pos
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.material = _prop_mat
	_props_root.add_child(sp)
	slab_count += 12

	var gl: Sprite2D = Sprite2D.new()
	gl.texture = COURTYARD_GLOW_TEX
	gl.position = pos
	gl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gl.material = Unlit.material()
	_glow_root.add_child(gl)

	var fp: StoneFootprint = StoneFootprint.new()
	fp.center = pos + Vector2(0.0, 1.0)
	fp.radii = Vector2(52.0, 36.5)
	fp.is_courtyard = true
	_stones.append(fp)
	_stamp_stone_ao(fp.center, Vector2(53.5, 38.0))


## Invisible stone footprint (no decal): stone footsteps and no grass through a built base, e.g. the Sternenauge plinth.
func add_stone_footprint(world_pos: Vector2, radii: Vector2) -> void:
	var fp: StoneFootprint = StoneFootprint.new()
	fp.center = world_pos.round()
	fp.radii = radii
	fp.is_courtyard = true
	_stones.append(fp)


func add_hero_rondell(world_pos: Vector2) -> void:
	add_ancient_courtyard(world_pos)


## Places a handcrafted woodland floor detail (0..2 leaves, 3..5 roots, 6..8 mossy rocks, 9..10 twigs, 11..13 mushrooms, 14..15 moss).
func add_forest_detail(world_pos: Vector2, variant: int, flip_h: bool = false, tint: Color = Color.WHITE) -> void:
	var v: int = clampi(variant, 0, 15)
	var pos: Vector2 = world_pos.round()
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = FOREST_TEX
	sp.region_enabled = true
	sp.region_rect = Rect2(float(v) * FOREST_CELL.x, 0.0, FOREST_CELL.x, FOREST_CELL.y)
	sp.position = pos
	sp.flip_h = flip_h
	sp.modulate = tint
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.material = _prop_mat
	_props_root.add_child(sp)
	detail_count += 1

	# Twilight violet & pale-teal forest mushrooms shimmer softly at night!
	if v == 12 or v == 13:
		var gl: Sprite2D = Sprite2D.new()
		gl.texture = FOREST_GLOW_TEX
		gl.region_enabled = true
		gl.region_rect = sp.region_rect
		gl.position = pos
		gl.flip_h = flip_h
		gl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		gl.material = Unlit.material()
		_glow_root.add_child(gl)


func _stamp_stone_ao(center: Vector2, radii: Vector2) -> void:
	if _detail_img == null:
		return
	var bb: Rect2 = Rect2(center - radii, radii * 2.0)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var d: float = ((wp - center) / radii).length()
			if d >= 1.0:
				continue
			var ao: float = 1.0 - smoothstep(0.60, 1.0, d)
			var dc: Color = _detail_img.get_pixel(ix, iy)
			dc.g = maxf(dc.g, ao)
			_detail_img.set_pixel(ix, iy, dc)


## Finalizes & uploads the continuous ground textures to the GPU.
func commit() -> void:
	_surface_tex = ImageTexture.create_from_image(_surface_img)
	_detail_tex = ImageTexture.create_from_image(_detail_img)

	_surface_mat = ShaderMaterial.new()
	_surface_mat.shader = SURFACE_SHADER
	_surface_mat.set_shader_parameter("map_origin", bounds.position)
	_surface_mat.set_shader_parameter("map_size", bounds.size)
	_surface_mat.set_shader_parameter("surface_map", _surface_tex)
	_surface_mat.set_shader_parameter("detail_map", _detail_tex)
	if _forest_mask != null:
		_forest_mask_tex = ImageTexture.create_from_image(_forest_mask)
		_forest_noise_tex = ImageTexture.create_from_image(_forest_noise)
		_surface_mat.set_shader_parameter("forest_on", true)
		_surface_mat.set_shader_parameter("forest_mask", _forest_mask_tex)
		_surface_mat.set_shader_parameter("forest_noise", _forest_noise_tex)
		_surface_mat.set_shader_parameter("forest_rect", Vector4(_forest_origin.x, _forest_origin.y, float(_forest_mask.get_width()) * _forest_texel, float(_forest_mask.get_height()) * _forest_texel))
		_surface_mat.set_shader_parameter("forest_noise_px", FOREST_NOISE_PX * float(FOREST_NOISE_SIZE))

	if _surface_rect != null:
		_surface_rect.queue_free()
	_surface_rect = ColorRect.new()
	_surface_rect.name = "GroundSurfaceLayer"
	_surface_rect.z_as_relative = false
	_surface_rect.z_index = -10
	_surface_rect.position = bounds.position
	_surface_rect.size = bounds.size
	_surface_rect.color = Color.WHITE
	_surface_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface_rect.material = _surface_mat
	add_child(_surface_rect)


func _process(_delta: float) -> void:
	if _glow_root == null:
		return
	var night: float = TimeManager.night_amount()
	var on: bool = night > 0.04
	_glow_root.visible = on
	if on:
		var pulse: float = 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.0018)
		_glow_root.modulate.a = smoothstep(0.04, 0.85, night) * pulse


## Returns the exact underfoot surface ID (data/terrain.json) for `Terrain.patches`.
func surface_at(world_pos: Vector2) -> String:
	if _surface_img == null or not bounds.has_point(world_pos):
		return ""
	var p: Vector2i = _world_to_px(world_pos)
	var ix: int = clampi(p.x, 0, _map_w - 1)
	var iy: int = clampi(p.y, 0, _map_h - 1)
	var sc: Color = _surface_img.get_pixel(ix, iy)
	var dc: Color = _detail_img.get_pixel(ix, iy)
	var fc: Vector3 = _forest_cell(world_pos)
	sc.b = maxf(sc.b, fc.x)
	dc.r = maxf(dc.r, fc.y)
	dc.b = maxf(dc.b, fc.z)

	# Standing woodland puddle wins over submerged earth; antique stone slabs sit above earth/paths!
	if sc.a >= 0.77:
		return "puddle"
	if _stone_overlap(world_pos) > 0.65:
		return "ancient_stone"
	if sc.a >= 0.54:
		return "mud"
	if sc.a >= 0.28:
		return "damp_earth"
	if sc.g >= 0.42:
		return "gravel"
	if sc.r >= 0.55 or dc.a >= 0.55:
		return "path"
	if dc.r >= 0.45:
		return "moss"
	if sc.b >= 0.40:
		return "forest_floor"
	return ""


## Answers how dense & what kind of `LivingGrass` should grow at `world_pos`:
## keeps slab faces, path cores & standing puddles crisp while growing organically along borders & seams!
func grass_habitat_at(world_pos: Vector2) -> Dictionary:
	if _surface_img == null or not bounds.has_point(world_pos):
		return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}
	var p: Vector2i = _world_to_px(world_pos)
	var ix: int = clampi(p.x, 0, _map_w - 1)
	var iy: int = clampi(p.y, 0, _map_h - 1)
	var sc: Color = _surface_img.get_pixel(ix, iy)
	var dc: Color = _detail_img.get_pixel(ix, iy)
	var fc: Vector3 = _forest_cell(world_pos)
	sc.b = maxf(sc.b, fc.x)
	dc.r = maxf(dc.r, fc.y)
	dc.b = maxf(dc.b, fc.z)

	# 1. Standing puddle or deep mud -> zero upright grass inside water/mud
	if sc.a >= 0.58:
		return {"density": 0.0, "height_scale": 0.6, "style": "none"}

	# 2. Asymmetric 3/4 stone clearance:
	# Grass blades extend ~12 px UPWARD from their foot! So we must clear grass feet across the stone face
	# PLUS +12 px SOUTH of every stone so blades rooted south of a slab NEVER cover the slab's face!
	var stone_clear: int = _stone_grass_zone(world_pos)
	if stone_clear == 2:
		return {"density": 0.0, "height_scale": 0.55, "style": "none"}
	if stone_clear == 1:
		# Outer framing collar around stone: ONLY low moss, clover & short 5px blades that kiss the bevel!
		return {"density": 0.72, "height_scale": 0.58, "style": "stone_seam"}

	# 3. Cobble lane: core stays clear, shoulders fray into low grass.
	if sc.g >= 0.46:
		return {"density": 0.0, "height_scale": 0.62, "style": "none"}
	if sc.g >= 0.16:
		var edge_t: float = 1.0 - smoothstep(0.16, 0.46, sc.g)
		return {"density": clampf(edge_t * 0.90, 0.0, 1.0), "height_scale": lerpf(0.60, 0.88, edge_t), "style": "path_edge"}
	# 3b. Trodden ways: the more worn, the sparser and shorter the grass; ruts and bare cores stay clear.
	if dc.a >= 0.5 or sc.r >= 0.62:
		return {"density": 0.0, "height_scale": 0.55, "style": "none"}
	if sc.r >= 0.12:
		var wear_t: float = smoothstep(0.12, 0.62, sc.r)
		return {"density": 1.0 - wear_t * 0.85, "height_scale": lerpf(0.95, 0.5, wear_t), "style": "path_edge"}

	# 4. Botanical tree root-collar & canopy drip-line microclimate (`LivingTree 2.0` coupling!):
	# - Tight buttress collar (`r < trunk_r * 1.12`): clear tall blades so buttress roots & moss cushions stay crisp
	# - Inner shaded root humus (`r < crown_r * 0.56`): softer woodland clover, moss & low sedges
	# - Outer Canopy Drip Line (`r = crown_r * 0.78 .. 1.16`): rainwater runoff nourishes lush tall ferns, clover & sedges!
	if not _trees.is_empty():
		var tree_hab: Dictionary = _tree_habitat(world_pos, sc.b)
		if not tree_hab.is_empty():
			return tree_hab

	# 5. Woodland floor (Square 3) -> lush ferns, moss cushions & dark sedges clustered naturally on moss banks!
	if sc.b >= 0.38:
		var wet_cut: float = 1.0 - smoothstep(0.28, 0.56, sc.a)
		if dc.r >= 0.36:
			return {"density": clampf((0.46 + dc.r * 0.36) * wet_cut, 0.0, 0.80), "height_scale": 0.90, "style": "moss_edge"}
		return {"density": clampf(0.18 * wet_cut, 0.0, 0.30), "height_scale": 0.82, "style": "forest"}

	# 6. Damp border near forest puddles on meadow
	if sc.a >= 0.24:
		return {"density": 0.35, "height_scale": 0.80, "style": "moss_edge"}

	return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}


## Snapshots immutable byte arrays & builds a 1-byte/bucket tree-presence grid so `LivingGrass` queries
## run without `Image.get_pixel()`, `Dictionary` allocations, or 3x3 bucket hash lookups on open meadow!
func prepare_fast_queries() -> void:
	if _surface_img != null:
		_surf_bytes = _surface_img.get_data()
	if _detail_img != null:
		_det_bytes = _detail_img.get_data()
	if _forest_mask != null:
		_fmask_bytes = _forest_mask.get_data()
		_fmask_w = _forest_mask.get_width()
		_fmask_h = _forest_mask.get_height()
		_fmask_stride = maxi(1, _fmask_bytes.size() / maxi(1, _fmask_w * _fmask_h))
	else:
		_fmask_bytes = PackedByteArray()
		_fmask_w = 0
		_fmask_h = 0
	if _forest_noise != null:
		_fnoise_bytes = _forest_noise.get_data()
	else:
		_fnoise_bytes = PackedByteArray()

	if _tree_buckets.is_empty():
		_tree_near = PackedByteArray()
		_tb_w = 0
		_tb_h = 0
		return
	var inv_tb: float = 1.0 / TREE_BUCKET_PX
	_tb_ox = floori(bounds.position.x * inv_tb) - 2
	_tb_oy = floori(bounds.position.y * inv_tb) - 2
	_tb_w = maxi(1, ceili(bounds.end.x * inv_tb) - _tb_ox + 3)
	_tb_h = maxi(1, ceili(bounds.end.y * inv_tb) - _tb_oy + 3)
	_tree_near.resize(_tb_w * _tb_h)
	_tree_near.fill(0)
	for cell_v: Variant in _tree_buckets:
		var c: Vector2i = cell_v as Vector2i
		var cx: int = c.x - _tb_ox
		var cy: int = c.y - _tb_oy
		for dy: int in range(-1, 2):
			var ny: int = cy + dy
			if ny < 0 or ny >= _tb_h:
				continue
			var nrow: int = ny * _tb_w
			for dx: int in range(-1, 2):
				var nx: int = cx + dx
				if nx >= 0 and nx < _tb_w:
					_tree_near[nrow + nx] = 1


func _forest_cell_fast(world_pos: Vector2) -> Vector3:
	if _fmask_bytes.is_empty():
		return _forest_cell(world_pos)
	var inv_ft: float = 1.0 / _forest_texel
	var fx_f: float = (world_pos.x - _forest_origin.x) * inv_ft - 0.5
	var fy_f: float = (world_pos.y - _forest_origin.y) * inv_ft - 0.5
	var x0: int = floori(fx_f)
	var y0: int = floori(fy_f)
	var mw: int = _fmask_w - 1
	var mh: int = _fmask_h - 1
	var cx0: int = clampi(x0, 0, mw)
	var cx1: int = clampi(x0 + 1, 0, mw)
	var cy0: int = clampi(y0, 0, mh)
	var cy1: int = clampi(y0 + 1, 0, mh)
	var s: int = _fmask_stride
	var b00: int = _fmask_bytes[(cy0 * _fmask_w + cx0) * s]
	var b10: int = _fmask_bytes[(cy0 * _fmask_w + cx1) * s]
	var b01: int = _fmask_bytes[(cy1 * _fmask_w + cx0) * s]
	var b11: int = _fmask_bytes[(cy1 * _fmask_w + cx1) * s]
	if b00 == 0 and b10 == 0 and b01 == 0 and b11 == 0:
		return Vector3.ZERO
	var fx: float = fx_f - float(x0)
	var fy: float = fy_f - float(y0)
	var inv255: float = 1.0 / 255.0
	var m: float = lerpf(lerpf(float(b00), float(b10), fx), lerpf(float(b01), float(b11), fx), fy) * inv255
	if m < 0.04:
		return Vector3.ZERO
	var qx: int = posmod(floori(world_pos.x * (1.0 / FOREST_NOISE_PX)), FOREST_NOISE_SIZE)
	var qy: int = posmod(floori(world_pos.y * (1.0 / FOREST_NOISE_PX)), FOREST_NOISE_SIZE)
	var ni: int = (qy * FOREST_NOISE_SIZE + qx) * 3
	var nr: float = float(_fnoise_bytes[ni]) * inv255
	var fw: float = smoothstep(0.3, 0.72, m + (nr * 2.0 - 1.0) * 0.24)
	if fw <= 0.01:
		return Vector3.ZERO
	var ng: float = float(_fnoise_bytes[ni + 1]) * inv255
	var nb: float = float(_fnoise_bytes[ni + 2]) * inv255
	return Vector3(fw, smoothstep(0.50, 0.72, ng) * fw * 0.92, clampf(nb * 0.85 + 0.15, 0.0, 1.0) * fw * 0.78)


## Returns `Vector3(density, height_scale, style_code)` or `Vector3(-1.0, 0.0, 0.0)` when no tree is near.
func _tree_habitat_vec(world_pos: Vector2, humus: float) -> Vector3:
	var inv_tb: float = 1.0 / TREE_BUCKET_PX
	var tx: int = floori(world_pos.x * inv_tb)
	var ty: int = floori(world_pos.y * inv_tb)
	if not _tree_near.is_empty():
		var gx: int = tx - _tb_ox
		var gy: int = ty - _tb_oy
		if gx < 0 or gx >= _tb_w or gy < 0 or gy >= _tb_h or _tree_near[gy * _tb_w + gx] == 0:
			return Vector3(-1.0, 0.0, 0.0)
	var cell: Vector2i = Vector2i(tx, ty)
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			var bucket: Variant = _tree_buckets.get(cell + Vector2i(ox, oy))
			if bucket == null:
				continue
			for index: int in (bucket as PackedInt32Array):
				var tz: TreeMicroZone = _trees[index]
				var dx: float = world_pos.x - tz.center.x
				var dy: float = (world_pos.y - tz.center.y) * 1.38
				var max_r: float = maxf(tz.crown_r * 1.16, tz.trunk_r * 1.65)
				if absf(dx) > max_r or absf(dy) > max_r:
					continue
				var dist_t: float = sqrt(dx * dx + dy * dy)
				if dist_t > max_r:
					continue
				if dist_t <= tz.trunk_r * 0.68:
					return Vector3(0.0, 0.55, 0.0)
				if dist_t <= tz.trunk_r * 1.65:
					return Vector3(0.84, 0.66, 2.0)
				if tz.crown_r >= 24.0:
					var cr_ratio: float = dist_t / tz.crown_r
					if cr_ratio >= 0.78 and cr_ratio <= 1.16:
						return Vector3(1.0, 1.12, 1.0 if humus < 0.25 else 5.0)
					if cr_ratio < 0.56 and humus < 0.38:
						return Vector3(0.72, 0.88, 5.0)
	return Vector3(-1.0, 0.0, 0.0)


## Zero-allocation habitat query for `LivingGrass._build_tufts()` (`Vector3(density, height_scale, style_code)`).
## Style codes: 0=none, 1=meadow, 2=stone_seam, 3=path_edge, 4=forest, 5=moss_edge.
func grass_habitat_vec(world_pos: Vector2) -> Vector3:
	if _surface_img == null or not bounds.has_point(world_pos):
		return Vector3(1.0, 1.0, 1.0)
	var inv_c: float = 1.0 / cell_px
	var ix: int = clampi(floori((world_pos.x - bounds.position.x) * inv_c), 0, _map_w - 1)
	var iy: int = clampi(floori((world_pos.y - bounds.position.y) * inv_c), 0, _map_h - 1)
	var sc_r: float
	var sc_g: float
	var sc_b: float
	var sc_a: float
	var dc_r: float
	var dc_a: float
	if not _surf_bytes.is_empty() and not _det_bytes.is_empty():
		var bi: int = (iy * _map_w + ix) * 4
		var inv255: float = 1.0 / 255.0
		sc_r = float(_surf_bytes[bi]) * inv255
		sc_g = float(_surf_bytes[bi + 1]) * inv255
		sc_b = float(_surf_bytes[bi + 2]) * inv255
		sc_a = float(_surf_bytes[bi + 3]) * inv255
		dc_r = float(_det_bytes[bi]) * inv255
		dc_a = float(_det_bytes[bi + 3]) * inv255
	else:
		var sc: Color = _surface_img.get_pixel(ix, iy)
		var dc: Color = _detail_img.get_pixel(ix, iy)
		sc_r = sc.r
		sc_g = sc.g
		sc_b = sc.b
		sc_a = sc.a
		dc_r = dc.r
		dc_a = dc.a
	if _forest_mask != null:
		var fc: Vector3 = _forest_cell_fast(world_pos)
		if fc.x > sc_b:
			sc_b = fc.x
		if fc.y > dc_r:
			dc_r = fc.y

	if sc_a >= 0.58:
		return Vector3(0.0, 0.6, 0.0)
	if not _stones.is_empty():
		var stone_clear: int = _stone_grass_zone(world_pos)
		if stone_clear == 2:
			return Vector3(0.0, 0.55, 0.0)
		if stone_clear == 1:
			return Vector3(0.72, 0.58, 2.0)
	if sc_g >= 0.46:
		return Vector3(0.0, 0.62, 0.0)
	if sc_g >= 0.16:
		var edge_t: float = 1.0 - smoothstep(0.16, 0.46, sc_g)
		return Vector3(clampf(edge_t * 0.90, 0.0, 1.0), lerpf(0.60, 0.88, edge_t), 3.0)
	if dc_a >= 0.5 or sc_r >= 0.62:
		return Vector3(0.0, 0.55, 0.0)
	if sc_r >= 0.12:
		var wear_t: float = smoothstep(0.12, 0.62, sc_r)
		return Vector3(1.0 - wear_t * 0.85, lerpf(0.95, 0.5, wear_t), 3.0)
	if not _trees.is_empty():
		var tv: Vector3 = _tree_habitat_vec(world_pos, sc_b)
		if tv.x >= 0.0:
			return tv
	if sc_b >= 0.38:
		var wet_cut: float = 1.0 - smoothstep(0.28, 0.56, sc_a)
		if dc_r >= 0.36:
			return Vector3(clampf((0.46 + dc_r * 0.36) * wet_cut, 0.0, 0.80), 0.90, 5.0)
		return Vector3(clampf(0.18 * wet_cut, 0.0, 0.30), 0.82, 4.0)
	if sc_a >= 0.24:
		return Vector3(0.35, 0.80, 5.0)
	return Vector3(1.0, 1.0, 1.0)


## Grass at a tree's root collar or drip line (`grass_habitat_at` step 4), {} when no tree is near. Walks the 3x3
## buckets round the point in a fixed order (the same on every peer), no list is built per query.
func _tree_habitat(world_pos: Vector2, humus: float) -> Dictionary:
	var cell: Vector2i = Vector2i(floori(world_pos.x / TREE_BUCKET_PX), floori(world_pos.y / TREE_BUCKET_PX))
	for oy: int in range(-1, 2):
		for ox: int in range(-1, 2):
			var bucket: Variant = _tree_buckets.get(cell + Vector2i(ox, oy))
			if bucket == null:
				continue
			for index: int in (bucket as PackedInt32Array):
				var tz: TreeMicroZone = _trees[index]
				var rel_t: Vector2 = (world_pos - tz.center) * Vector2(1.0, 1.38)
				var dist_t: float = rel_t.length()
				if dist_t > tz.crown_r * 1.16 and dist_t > tz.trunk_r * 1.65:
					continue
				if dist_t <= tz.trunk_r * 0.68:
					return {"density": 0.0, "height_scale": 0.55, "style": "none"}
				if dist_t <= tz.trunk_r * 1.65:
					return {"density": 0.84, "height_scale": 0.66, "style": "stone_seam"}
				if tz.crown_r >= 24.0:
					var cr_ratio: float = dist_t / tz.crown_r
					if cr_ratio >= 0.78 and cr_ratio <= 1.16:
						return {"density": 1.0, "height_scale": 1.12, "style": "meadow" if humus < 0.25 else "moss_edge"}
					if cr_ratio < 0.56 and humus < 0.38:
						return {"density": 0.72, "height_scale": 0.88, "style": "moss_edge"}
	return {}


## Paints a botanical root-humus collar, north-bias cushion moss & moist canopy drip-line ring for `LivingTree 2.0`.
func paint_tree_root_zone(center: Vector2, trunk_r: float, crown_r: float, seed_val: int = 401) -> void:
	if _surface_img == null or _detail_img == null:
		return
	var tz: TreeMicroZone = TreeMicroZone.new()
	tz.center = center
	tz.trunk_r = maxf(trunk_r, 4.0)
	tz.crown_r = maxf(crown_r, 12.0)
	_add_tree_zone(tz)

	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.042
	var outer_r: float = maxf(trunk_r * 2.6, crown_r * 1.18)
	var bb: Rect2 = Rect2(center - Vector2(outer_r, outer_r * 0.85), Vector2(outer_r * 2.0, outer_r * 1.7))
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var rel: Vector2 = (wp - center) * Vector2(1.0, 1.38)
			var d: float = rel.length()
			var wob: float = noise.get_noise_2d(wp.x, wp.y) * 5.5
			var sc: Color = _surface_img.get_pixel(ix, iy)
			var dc: Color = _detail_img.get_pixel(ix, iy)
			var changed: bool = false
			# Plush emerald root-collar moss cushions & soft contact AO (NEVER cuts dark brown dirt holes into green meadow!)
			var root_reach: float = trunk_r * 2.15 + wob
			if d < root_reach and sc.r < 0.38 and sc.g < 0.38 and sc.a < 0.60:
				var rw: float = 1.0 - smoothstep(trunk_r * 0.55, root_reach, d)
				if sc.b >= 0.32:
					sc.b = maxf(sc.b, rw * 0.72)
				dc.g = maxf(dc.g, rw * 0.38) ## subtle cool root-collar ambient occlusion
				var north_bias: float = clampf(0.75 - (wp.y - center.y) * 0.018, 0.38, 1.0)
				dc.r = maxf(dc.r, rw * 0.90 * north_bias)
				changed = true
			# Canopy drip-line subtle shade & moisture ring (`r ~ 0.82..1.10 crown_r`)
			if crown_r >= 32.0 and d < crown_r * 1.12 + wob:
				var shade_w: float = (1.0 - smoothstep(crown_r * 0.45, crown_r * 1.08, d)) * 0.42
				dc.b = maxf(dc.b, shade_w)
				var drip_band: float = 1.0 - absf((d - crown_r * 0.94) / maxf(crown_r * 0.20, 6.0))
				if drip_band > 0.0 and sc.a < 0.22 and sc.r < 0.35 and sc.g < 0.35:
					sc.a = maxf(sc.a, clampf(drip_band * 0.20, 0.0, 0.20))
				changed = true
			if changed:
				_surface_img.set_pixel(ix, iy, sc)
				_detail_img.set_pixel(ix, iy, dc)


## Exact underfoot check for `Terrain.surface_at()` (stone face only, no south grass-height padding).
func _stone_overlap(world_pos: Vector2) -> float:
	var best: float = 0.0
	for fp: StoneFootprint in _stones:
		var rel: Vector2 = (world_pos - fp.center) / fp.radii
		var d: float = rel.length()
		if d < 0.96:
			best = maxf(best, 1.0)
	return best


## Returns 2 inside the stone's 3/4 visual occlusion guard (stone + 12px south!), 1 in the framing moss collar, 0 clear.
func _stone_grass_zone(world_pos: Vector2) -> int:
	var zone: int = 0
	for fp: StoneFootprint in _stones:
		var dx: float = absf(world_pos.x - fp.center.x)
		var dy: float = world_pos.y - fp.center.y
		# Asymmetric 3/4 guard: horizontal +6.5 px (prevents 16px-wide stone_seam moss sprites from overlapping slab edges!),
		# north +3.0 px, south +13.0 px (prevents any tall blade below the stone from reaching up across the stone face!).
		var rx_inner: float = fp.radii.x + 6.5
		var ry_n: float = fp.radii.y + 3.0
		var ry_s: float = fp.radii.y + 13.0
		var ny: float = dy / (ry_s if dy >= 0.0 else ry_n)
		var nx: float = dx / rx_inner
		var d_in: float = sqrt(nx * nx + ny * ny)
		if d_in <= 1.0:
			return 2
		var nx_out: float = dx / (rx_inner + 5.5)
		var ny_out: float = dy / ((ry_s + 4.5) if dy >= 0.0 else (ry_n + 4.5))
		if sqrt(nx_out * nx_out + ny_out * ny_out) <= 1.0:
			zone = maxi(zone, 1)
	return zone


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 <= 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
