class_name RockyGround
extends Node2D
## RockyGround v1 — Variable, multi-stratum geological ground & highland outcrop surface layer:
## - Paints organic stony mineral loam (`slope`), Voronoi angular fractured scree/talus (`gravel`),
##   stepped stratified bedrock shelves (`stone`), crustose rock-lichen colonies, and crevice cushion-moss (`moss`)
##   onto lightweight 2x2 px control maps rendered at 1px pixel-art precision (`rocky_ground.gdshader`).
## - Automatically registers in `Terrain.patches` so `FootstepComponent`, `Player`, and `LivingGrass`
##   react with exact footstep audio, gravel/stone dust puffs, bedrock/scree grass clearing, and
##   crevice `stone_seam` tufts without modifying `GroundSurfaces`.

const ROCKY_SHADER: Shader = preload("res://assets/shaders/rocky_ground.gdshader")
const PROP_LIT_SHADER: Shader = preload("res://assets/shaders/ground_prop_lit.gdshader")
const DETAIL_TEX_PATH: String = "res://assets/tiles/rock_ground_details.png"
const DETAIL_GLOW_PATH: String = "res://assets/tiles/rock_ground_details_glow.png"
const DETAIL_CELL: Vector2 = Vector2(24.0, 20.0)

class RockFootprint:
	var center: Vector2 = Vector2.ZERO
	var radii: Vector2 = Vector2(18.0, 9.0)


var bounds: Rect2 = Rect2()
var cell_px: float = 2.0
var detail_count: int = 0

var _map_w: int = 0
var _map_h: int = 0
var _strata_img: Image ## R: stony_loam, G: angular_scree, B: bedrock_shelf, A: dampness
var _detail_img: Image ## R: cushion_moss, G: crustose_lichen, B: boulder_ao, A: quarry_trail
var _strata_tex: ImageTexture
var _detail_tex: ImageTexture
var _strata_mat: ShaderMaterial
var _prop_mat: ShaderMaterial
var _surface_rect: ColorRect
var _props_root: Node2D
var _glow_root: Node2D
var _rock_footprints: Array[RockFootprint] = []


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
	_strata_img = Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	_strata_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_detail_img = Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	_detail_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_rock_footprints.clear()
	detail_count = 0

	_prop_mat = ShaderMaterial.new()
	_prop_mat.shader = PROP_LIT_SHADER

	if _props_root != null:
		_props_root.queue_free()
	_props_root = Node2D.new()
	_props_root.name = "RockGroundDetails"
	_props_root.z_as_relative = false
	_props_root.z_index = -9
	add_child(_props_root)

	if _glow_root != null:
		_glow_root.queue_free()
	_glow_root = Node2D.new()
	_glow_root.name = "RockGroundGlow"
	_glow_root.z_as_relative = false
	_glow_root.z_index = -8
	_glow_root.visible = false
	add_child(_glow_root)


func _world_to_px(world_pos: Vector2) -> Vector2i:
	var rel: Vector2 = (world_pos - bounds.position) / cell_px
	return Vector2i(floori(rel.x), floori(rel.y))


func _px_to_world(ix: int, iy: int) -> Vector2:
	return bounds.position + Vector2((float(ix) + 0.5) * cell_px, (float(iy) + 0.5) * cell_px)


## Paints a broad highland rocky slope zone transitioning organically from meadow/glade on the west (`blend_west_px`)
## into weathered stony loam, scree pockets, bedrock shelves, lichens & crevice moss!
func paint_rocky_highland_zone(rect: Rect2, blend_west_px: float = 48.0, seed_val: int = 701) -> void:
	if _strata_img == null or _detail_img == null:
		return
	var edge_n: FastNoiseLite = FastNoiseLite.new()
	edge_n.seed = seed_val
	edge_n.frequency = 0.017
	edge_n.fractal_octaves = 2

	var loam_n: FastNoiseLite = FastNoiseLite.new()
	loam_n.seed = seed_val + 31
	loam_n.frequency = 0.021
	loam_n.fractal_octaves = 2

	var scree_n: FastNoiseLite = FastNoiseLite.new()
	scree_n.seed = seed_val + 73
	scree_n.frequency = 0.026
	scree_n.fractal_octaves = 2

	var moss_n: FastNoiseLite = FastNoiseLite.new()
	moss_n.seed = seed_val + 119
	moss_n.frequency = 0.029
	moss_n.fractal_octaves = 2

	var bb: Rect2 = rect.grow(blend_west_px + 12.0)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)

	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var wob_w: float = edge_n.get_noise_2d(wp.x, wp.y) * 34.0
			var inside_w: float = wp.x - (rect.position.x + wob_w)
			var zone_w: float = smoothstep(-blend_west_px * 0.55, blend_west_px * 0.95, inside_w)
			if zone_w <= 0.01:
				continue

			var st: Color = _strata_img.get_pixel(ix, iy)
			var dt: Color = _detail_img.get_pixel(ix, iy)

			# Variable stony mineral loam islands (leaves natural hardy grass pockets in between!)
			var ln: float = loam_n.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			var east_grad: float = clampf((wp.x - rect.position.x) / maxf(rect.size.x, 1.0), 0.0, 1.0)
			var loam_v: float = smoothstep(0.32 - east_grad * 0.14, 0.70, ln) * zone_w * 0.88
			st.r = maxf(st.r, loam_v)

			# Natural scree ribbons drifting across stony ground
			var sn: float = scree_n.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			if sn > 0.46:
				st.g = maxf(st.g, smoothstep(0.46, 0.78, sn) * zone_w * 0.78)

			# Scattered highland moss cushions in cooler shaded pockets
			var mn: float = moss_n.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			if mn > 0.62:
				dt.r = maxf(dt.r, smoothstep(0.62, 0.82, mn) * zone_w * 0.74)

			_strata_img.set_pixel(ix, iy, st)
			_detail_img.set_pixel(ix, iy, dt)


## Paints an exposed stratified bedrock shelf / highland stone terrace (`stone` underfoot) with crustose lichens & edge scree.
func paint_bedrock_shelf(center: Vector2, radii: Vector2, strength: float = 0.94, seed_val: int = 811) -> void:
	if _strata_img == null or _detail_img == null:
		return
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.032
	noise.fractal_octaves = 2

	var lich_n: FastNoiseLite = FastNoiseLite.new()
	lich_n.seed = seed_val + 47
	lich_n.frequency = 0.048

	var bb: Rect2 = Rect2(center - radii * 1.55, radii * 3.1)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)

	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var rel: Vector2 = (wp - center) / radii
			# Slightly angular superellipse so bedrock ledges follow geological cleavage rather than circles
			var d_ang: float = pow(pow(absf(rel.x), 2.3) + pow(absf(rel.y), 2.3), 1.0 / 2.3)
			var d: float = d_ang + noise.get_noise_2d(wp.x, wp.y) * 0.30
			if d >= 1.42:
				continue

			var st: Color = _strata_img.get_pixel(ix, iy)
			var dt: Color = _detail_img.get_pixel(ix, iy)

			if d < 1.08:
				var bw: float = (1.0 - smoothstep(0.42, 1.06, d)) * strength
				st.b = maxf(st.b, bw)
				# Sunlit crustose map-lichen patches on exposed bedrock
				var lv: float = lich_n.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
				if lv > 0.48:
					dt.g = maxf(dt.g, smoothstep(0.48, 0.78, lv) * bw * 0.88)
			# Surrounding weathered scree & stony loam apron where bedrock erodes into the slope!
			var apron: float = (1.0 - smoothstep(0.72, 1.40, d)) * 0.82
			st.g = maxf(st.g, apron)
			st.r = maxf(st.r, apron * 0.76)

			_strata_img.set_pixel(ix, iy, st)
			_detail_img.set_pixel(ix, iy, dt)


## Paints an angular talus / scree fan (`gravel` underfoot) — e.g. downslope of boulder clusters or trails.
func paint_scree_fan(center: Vector2, radii: Vector2, strength: float = 0.88, seed_val: int = 853) -> void:
	if _strata_img == null or _detail_img == null:
		return
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.038
	var bb: Rect2 = Rect2(center - radii * 1.4, radii * 2.8)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var d: float = ((wp - center) / radii).length() + noise.get_noise_2d(wp.x, wp.y) * 0.34
			if d >= 1.20:
				continue
			var sw: float = (1.0 - smoothstep(0.28, 1.18, d)) * strength
			var st: Color = _strata_img.get_pixel(ix, iy)
			st.g = maxf(st.g, sw)
			st.r = maxf(st.r, sw * 0.65)
			_strata_img.set_pixel(ix, iy, st)


## Paints a meandering worn stony quarry trail (`slope` / `gravel` underfoot) connecting Square 4's glade into Square 5.
func paint_quarry_trail(points: Array[Vector2], half_width: float = 9.0, seed_val: int = 887) -> void:
	if points.size() < 2 or _strata_img == null or _detail_img == null:
		return
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.042
	var total_len: float = 0.0
	var seg_lens: Array[float] = []
	for s: int in points.size() - 1:
		var sl: float = points[s].distance_to(points[s + 1])
		seg_lens.append(sl)
		total_len += sl

	var bb: Rect2 = Rect2(points[0], Vector2.ZERO)
	for p: Vector2 in points:
		bb = bb.expand(p)
	bb = bb.grow(half_width + 16.0)
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
				var ab: Vector2 = points[seg + 1] - a
				var l2: float = ab.length_squared()
				var t_seg: float = clampf((wp - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.0001 else 0.0
				var d: float = wp.distance_to(a + ab * t_seg)
				if d < min_d:
					min_d = d
					best_along = accum + seg_lens[seg] * t_seg
				accum += seg_lens[seg]
			var fade: float = smoothstep(0.0, 26.0, best_along) * smoothstep(0.0, 26.0, total_len - best_along)
			var eff_w: float = (half_width + noise.get_noise_2d(wp.x, wp.y) * 3.2) * lerpf(0.45, 1.0, fade)
			if min_d > eff_w + 8.0:
				continue
			var tw: float = (1.0 - smoothstep(eff_w * 0.42, eff_w + 7.5, min_d)) * fade
			var st: Color = _strata_img.get_pixel(ix, iy)
			var dt: Color = _detail_img.get_pixel(ix, iy)
			st.r = maxf(st.r, tw * 0.90)
			st.g = maxf(st.g, tw * 0.48)
			dt.a = maxf(dt.a, tw * 0.85)
			_strata_img.set_pixel(ix, iy, st)
			_detail_img.set_pixel(ix, iy, dt)


## Paints a plush highland crevice moss pocket.
func paint_moss_pocket(center: Vector2, radii: Vector2, strength: float = 0.88, seed_val: int = 911) -> void:
	if _detail_img == null:
		return
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.048
	var bb: Rect2 = Rect2(center - radii * 1.4, radii * 2.8)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var d: float = ((wp - center) / radii).length() + noise.get_noise_2d(wp.x, wp.y) * 0.34
			if d >= 1.15:
				continue
			var mw: float = (1.0 - smoothstep(0.30, 1.12, d)) * strength
			var dt: Color = _detail_img.get_pixel(ix, iy)
			dt.r = maxf(dt.r, mw)
			_detail_img.set_pixel(ix, iy, dt)


## Stamps a natural geological boulder collar around a `LivingRock` outcrop:
## contact AO, frost-shattered scree halo, north-bias cushion moss, and asymmetric 3/4 `LivingGrass` clearance!
func register_rock_outcrop(center: Vector2, half_w_px: float, body_half_h_px: float, seed_val: int = 929) -> void:
	if _strata_img == null or _detail_img == null:
		return
	var fp: RockFootprint = RockFootprint.new()
	fp.center = center
	fp.radii = Vector2(maxf(half_w_px, 6.0), maxf(body_half_h_px + 2.0, 4.5))
	_rock_footprints.append(fp)

	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.052
	var outer: Vector2 = fp.radii * 2.35 + Vector2(8.0, 6.0)
	var bb: Rect2 = Rect2(center - outer, outer * 2.0)
	var x0: int = clampi(floori((bb.position.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var x1: int = clampi(ceili((bb.end.x - bounds.position.x) / cell_px), 0, _map_w - 1)
	var y0: int = clampi(floori((bb.position.y - bounds.position.y) / cell_px), 0, _map_h - 1)
	var y1: int = clampi(ceili((bb.end.y - bounds.position.y) / cell_px), 0, _map_h - 1)

	for iy: int in range(y0, y1 + 1):
		for ix: int in range(x0, x1 + 1):
			var wp: Vector2 = _px_to_world(ix, iy)
			var rel: Vector2 = (wp - center) / fp.radii
			var d: float = rel.length() + noise.get_noise_2d(wp.x, wp.y) * 0.24
			if d >= 2.25:
				continue
			var st: Color = _strata_img.get_pixel(ix, iy)
			var dt: Color = _detail_img.get_pixel(ix, iy)
			if d < 1.38:
				dt.b = maxf(dt.b, (1.0 - smoothstep(0.55, 1.38, d)) * 0.85)
			if half_w_px >= 12.0:
				var scree_w: float = (1.0 - smoothstep(0.75, 2.15, d)) * clampf(half_w_px / 28.0, 0.45, 0.90)
				st.g = maxf(st.g, scree_w)
				st.r = maxf(st.r, scree_w * 0.68)
				# North-side cool damp moss collar tucked behind boulders!
				if wp.y < center.y + 2.0 and d > 0.78 and d < 1.65:
					var nb: float = clampf((center.y + 2.0 - wp.y) / maxf(fp.radii.y * 1.4, 6.0), 0.0, 1.0)
					dt.r = maxf(dt.r, (1.0 - smoothstep(0.85, 1.62, d)) * nb * 0.72)
			_strata_img.set_pixel(ix, iy, st)
			_detail_img.set_pixel(ix, iy, dt)


## Places a handcrafted rocky-ground detail sprite (0..2 splinters, 3..5 flat plates, 6..8 mossy gravel,
## 9..10 lichen/sedge, 11..12 rock-ferns, 13..14 Sempervivum rosettes, 15 crevice quartz-dew).
func add_rock_detail(world_pos: Vector2, variant: int, flip_h: bool = false, tint: Color = Color.WHITE) -> void:
	var base_tex: Texture2D = DataRegistry.tex(DETAIL_TEX_PATH)
	if base_tex == null or _props_root == null:
		return
	var v: int = clampi(variant, 0, 15)
	var pos: Vector2 = world_pos.round()
	var sp: Sprite2D = Sprite2D.new()
	sp.texture = base_tex
	sp.region_enabled = true
	sp.region_rect = Rect2(float(v) * DETAIL_CELL.x, 0.0, DETAIL_CELL.x, DETAIL_CELL.y)
	sp.position = pos
	sp.flip_h = flip_h
	sp.modulate = tint
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.material = _prop_mat
	_props_root.add_child(sp)
	detail_count += 1

	var glow_tex: Texture2D = DataRegistry.tex(DETAIL_GLOW_PATH)
	if glow_tex != null and (v == 12 or v == 15):
		var gl: Sprite2D = Sprite2D.new()
		gl.texture = glow_tex
		gl.region_enabled = true
		gl.region_rect = sp.region_rect
		gl.position = pos
		gl.flip_h = flip_h
		gl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		gl.material = Unlit.material()
		_glow_root.add_child(gl)


func commit() -> void:
	if _strata_img == null or _detail_img == null:
		return
	_strata_tex = ImageTexture.create_from_image(_strata_img)
	_detail_tex = ImageTexture.create_from_image(_detail_img)

	_strata_mat = ShaderMaterial.new()
	_strata_mat.shader = ROCKY_SHADER
	_strata_mat.set_shader_parameter("map_origin", bounds.position)
	_strata_mat.set_shader_parameter("map_size", bounds.size)
	_strata_mat.set_shader_parameter("strata_map", _strata_tex)
	_strata_mat.set_shader_parameter("detail_map", _detail_tex)

	if _surface_rect != null:
		_surface_rect.queue_free()
	_surface_rect = ColorRect.new()
	_surface_rect.name = "RockyGroundLayer"
	_surface_rect.z_as_relative = false
	_surface_rect.z_index = -10
	_surface_rect.position = bounds.position
	_surface_rect.size = bounds.size
	_surface_rect.color = Color.WHITE
	_surface_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface_rect.material = _strata_mat
	add_child(_surface_rect)


func _process(_delta: float) -> void:
	if _glow_root == null:
		return
	var night: float = TimeManager.night_amount()
	var on: bool = night > 0.04
	_glow_root.visible = on
	if on:
		var pulse: float = 0.74 + 0.26 * sin(Time.get_ticks_msec() * 0.0017)
		_glow_root.modulate.a = smoothstep(0.04, 0.85, night) * pulse


## Returns underfoot surface ID (`data/terrain.json`) for `Terrain.patches`:
## `"stone"` on exposed bedrock shelves, `"gravel"` on angular scree/talus, `"moss"` on moss cushions, `"slope"` on stony loam.
func surface_at(world_pos: Vector2) -> String:
	if _strata_img == null or not bounds.has_point(world_pos):
		return ""
	var p: Vector2i = _world_to_px(world_pos)
	var ix: int = clampi(p.x, 0, _map_w - 1)
	var iy: int = clampi(p.y, 0, _map_h - 1)
	var st: Color = _strata_img.get_pixel(ix, iy)
	var dt: Color = _detail_img.get_pixel(ix, iy)

	if dt.r >= 0.50:
		return "moss"
	if st.b >= 0.48:
		return "stone"
	if st.g >= 0.42:
		return "gravel"
	if st.r >= 0.46 or dt.a >= 0.48:
		return "slope"
	return ""


## Couples `RockyGround` with `LivingGrass`:
## - Clears upright blades on exposed bedrock, packed scree, worn quarry tracks, and +13px south of every `LivingRock` face!
## - Tucks short hardy `stone_seam` sedges/clover into bedrock margins, boulder collars, and loose scree aprons!
func grass_habitat_at(world_pos: Vector2) -> Dictionary:
	if _strata_img == null or not bounds.has_point(world_pos):
		return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}

	var r_zone: int = _boulder_grass_zone(world_pos)
	if r_zone == 2:
		return {"density": 0.0, "height_scale": 0.55, "style": "none"}
	if r_zone == 1:
		return {"density": 0.68, "height_scale": 0.58, "style": "stone_seam"}

	var p: Vector2i = _world_to_px(world_pos)
	var ix: int = clampi(p.x, 0, _map_w - 1)
	var iy: int = clampi(p.y, 0, _map_h - 1)
	var st: Color = _strata_img.get_pixel(ix, iy)
	var dt: Color = _detail_img.get_pixel(ix, iy)

	# Exposed bedrock shelf core stays clean stone; fracture margins get short crevice tufts!
	if st.b >= 0.52 and dt.r < 0.45:
		return {"density": 0.0, "height_scale": 0.55, "style": "none"}
	if st.b >= 0.24:
		return {"density": 0.52, "height_scale": 0.56, "style": "stone_seam"}

	# Packed angular scree core stays clear; outer loose scree apron grows sparse hardy tufts
	if st.g >= 0.52 and dt.r < 0.45:
		return {"density": 0.0, "height_scale": 0.55, "style": "none"}
	if dt.a >= 0.52 or st.r >= 0.66:
		return {"density": 0.0, "height_scale": 0.55, "style": "none"}

	if st.g >= 0.20 or st.r >= 0.22:
		var rockiness: float = clampf(maxf((st.g - 0.20) / 0.34, (st.r - 0.22) / 0.46), 0.0, 1.0)
		return {
			"density": lerpf(0.86, 0.22, rockiness),
			"height_scale": lerpf(0.90, 0.58, rockiness),
			"style": "stone_seam" if rockiness > 0.48 else "path_edge",
		}

	if dt.r >= 0.36:
		return {"density": 0.76, "height_scale": 0.78, "style": "moss_edge"}

	return {"density": 1.0, "height_scale": 1.0, "style": "meadow"}


func _boulder_grass_zone(world_pos: Vector2) -> int:
	var zone: int = 0
	for fp: RockFootprint in _rock_footprints:
		var dx: float = absf(world_pos.x - fp.center.x)
		var dy: float = world_pos.y - fp.center.y
		var rx_in: float = fp.radii.x + 2.0
		var ry_n: float = fp.radii.y + 1.0
		var ry_s: float = fp.radii.y + 13.0
		var ny: float = dy / (ry_s if dy >= 0.0 else ry_n)
		var nx: float = dx / rx_in
		if (nx * nx + ny * ny) <= 1.0:
			return 2
		var nx_out: float = dx / (rx_in + 6.0)
		var ny_out: float = dy / ((ry_s + 5.0) if dy >= 0.0 else (ry_n + 5.0))
		if (nx_out * nx_out + ny_out * ny_out) <= 1.0:
			zone = maxi(zone, 1)
	return zone
