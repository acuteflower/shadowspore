class_name AurelithRig
extends Node2D
## Procedural 3D-projected (`SQUASH = 0.72`), depth-sorted pixel-art rig for
## `Aurelith, Herz des Sonnenquarzes` — a towering ~156 px tall, ~168 px wide
## ancient desert sandstone, gold-ruin & living sun-quartz entity.
## Built purely from organic craggy rock polygons, geological strata/fracture
## details, multi-faceted raw quartz crystals, braided arcane ley-tethers,
## an inverted floating geode tail-spire, and a sandstorm funnel (no cuboids, no robot legs).

signal foot_landed(world_pos: Vector2)

enum Pose {
	DORMANT,
	AWAKEN,
	IDLE,
	MOVE,
	GAUNTLET_SLAM,
	FAULT_SLAM,
	SINKHOLE_CAST,
	BLADE_CLEAVE,
	CHEST_BEAM,
	CLAP_PREP,
	CLAP_CRUSH,
	ZENITH_CHARGE,
	STAGGER,
	DEAD,
}

const SQUASH: float = 0.72

# Harmonized Sonnenquarz-Öde Palettes (aligned with tools/art_desert_ruins.py, zero #000000)
const ST_OUT: Color = Color("241626")
const ST_0: Color = Color("483038")
const ST_1: Color = Color("785042")
const ST_2: Color = Color("aa7a4e")
const ST_3: Color = Color("d8a868")
const ST_4: Color = Color("f2cf8e")

const GD_OUT: Color = Color("34221e")
const GD_0: Color = Color("6f5020")
const GD_1: Color = Color("b48a38")
const GD_2: Color = Color("e6c468")
const GD_3: Color = Color("fff0b0")

const QZ_OUT: Color = Color("282238")
const QZ_DEEP: Color = Color("364262")
const QZ_0: Color = Color("5b698e")
const QZ_1: Color = Color("8191b6")
const QZ_2: Color = Color("a2b3d4")
const QZ_3: Color = Color("d6e2f5")
const QZ_4: Color = Color("ffffff")

const SD_0: Color = Color("472c38")
const SD_1: Color = Color("6e4934")
const SD_2: Color = Color("9c6c44")
const SD_3: Color = Color("c89658")
const SD_4: Color = Color("e6be78")
const SD_5: Color = Color("f7de9e")

# 9-Shard Cathedral Sun-Crown around head apex (reaching ~156..162 px total height)
const CROWN_OFFSETS: Array[float] = [-35.0, -26.0, -17.0, -8.5, 0.0, 8.5, 17.0, 26.0, 35.0]
const CROWN_HEIGHTS: Array[float] = [12.0, 16.0, 21.0, 26.0, 33.0, 26.0, 21.0, 16.0, 12.0]
const CROWN_ARC_Z: Array[float] = [-10.0, -4.0, 2.0, 6.5, 9.0, 6.5, 2.0, -4.0, -10.0]

# 8 Stage-2/3 Crystal Wing-Blades (4 per side fanning out like an astral sun mandala)
const WING_ANGLES: Array[float] = [0.22, 0.58, 0.96, 1.34]
const WING_LENS: Array[float] = [48.0, 66.0, 74.0, 52.0]
const WING_WIDTHS: Array[float] = [4.6, 5.8, 6.2, 4.4]

# 12 Orbiting Satellite Quartz Splinters in Stage 2/3
const SAT_COUNT: int = 12

static var _OVAL_MASKS: Dictionary = {}

## External stage / fight visual controls (0.0..1.0)
var prism_release: float = 0.0 ## Stage 2: ribs split wide, 8 crystal wing blades, violet/gold magic
var storm_ascension: float = 0.0 ## Stage 3: swirling 96 px sandstorm funnel, twin armillary rings, solar plasma
var soul_charge: float = 0.0 ## 0..1 Awakening buildup on DORMANT monument
var twin_blades: bool = false ## ignites colossal crystal greatblades on both gauntlets
var charge_intensity: float = 0.0 ## 0..1 extra core & crown flare while winding up super attacks

var _pose: Pose = Pose.IDLE
var _pose_time: float = 0.0
var _pose_duration: float = 1.0
var _time: float = 0.0
var _heading: float = PI * 0.5
var _forward: Vector2 = Vector2.DOWN
var _right: Vector2 = Vector2.LEFT
var _stride: float = 0.0
var _speed_ratio: float = 0.0
var _last_step_half: int = -1
var _flash: float = 0.0

## Detached fist state (world coordinates converted cleanly to rig-local)
var _detached_fist_active: Array[bool] = [false, false]
var _detached_fist_world: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _detached_fist_lift: Array[float] = [0.0, 0.0]

## Cached anchors in local rig space for external gameplay callers
var _core_local: Vector2 = Vector2(0.0, -78.0)
var _fist_local: Array[Vector2] = [Vector2(-56.0, -48.0), Vector2(56.0, -48.0)]
var _head_local: Vector2 = Vector2(0.0, -118.0)

var _cam_body: Vector3 = Vector3(0.0, 0.72, 0.694)
var _light_body: Vector3 = Vector3(-0.62, -0.45, 0.64)
var _parts: Array[Dictionary] = []

@onready var _body: Node2D = $Body
@onready var _glow: Node2D = $Glow


func _ready() -> void:
	_body.draw.connect(_draw_body)
	_glow.draw.connect(_draw_glow)


func start_pose(pose: Pose, duration: float = 1.0, elapsed: float = 0.0) -> void:
	_pose = pose
	_pose_duration = maxf(duration, 0.05)
	_pose_time = elapsed
	queue_redraw_all()


func hit_flash() -> void:
	_flash = 0.14
	queue_redraw_all()


func set_detached_fist(is_right: bool, active: bool, world_pos: Vector2 = Vector2.ZERO, lift_z: float = 0.0) -> void:
	var idx: int = 1 if is_right else 0
	_detached_fist_active[idx] = active
	_detached_fist_world[idx] = world_pos
	_detached_fist_lift[idx] = lift_z
	queue_redraw_all()


func core_world_pos() -> Vector2:
	return global_position + _core_local


func head_world_pos() -> Vector2:
	return global_position + _head_local


func fist_world_pos(is_right: bool) -> Vector2:
	var idx: int = 1 if is_right else 0
	return global_position + _fist_local[idx]


func queue_redraw_all() -> void:
	if is_instance_valid(_body):
		_body.queue_redraw()
	if is_instance_valid(_glow):
		_glow.queue_redraw()


func update_rig(delta: float, vel: Vector2, heading_rad: float) -> void:
	_time += delta
	_pose_time += delta
	_flash = maxf(0.0, _flash - delta)
	_heading = heading_rad
	_forward = Vector2.from_angle(_heading)
	_right = Vector2(-_forward.y, _forward.x)
	var spd: float = vel.length()
	_speed_ratio = clampf(spd / 85.0, 0.0, 1.3)
	if spd > 6.0 and _pose == Pose.MOVE:
		_stride += delta * (2.8 + spd * 0.04)
		var half: int = int(floorf(_stride / PI))
		if half != _last_step_half:
			_last_step_half = half
			var pulse_ground: Vector2 = _project(0.0, 0.0, 0.0)
			foot_landed.emit(global_position + pulse_ground)
	queue_redraw_all()


func _pose_progress() -> float:
	return clampf(_pose_time / maxf(_pose_duration, 0.05), 0.0, 1.0)


func _project(fwd: float, side: float, height: float) -> Vector2:
	var flat: Vector2 = _forward * fwd + _right * side
	return Vector2(flat.x, flat.y * SQUASH - height)


func _project_v(v: Vector3) -> Vector2:
	return _project(v.x, v.y, v.z)


func _depth(fwd: float, side: float, height: float) -> float:
	var flat: Vector2 = _forward * fwd + _right * side
	return flat.y * SQUASH + height * 0.05


func _depth_v(v: Vector3) -> float:
	return _depth(v.x, v.y, v.z)


func _update_frame_vectors() -> void:
	var cam_xy: Vector2 = Vector2(0.0, 0.72)
	_cam_body = Vector3(_forward.dot(cam_xy), _right.dot(cam_xy), 0.694).normalized()
	var l_xy: Vector2 = Vector2(-0.64, -0.46)
	_light_body = Vector3(_forward.dot(l_xy), _right.dot(l_xy), 0.62).normalized()


func _hashf(n: int, salt: int) -> float:
	var h: int = (n * 374761393 + salt * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


func _magic_palette() -> Dictionary:
	var p1_main: Color = Color("78f4e6")
	var p1_dark: Color = Color("2a8c94")
	var p1_spark: Color = Color("ffe488")
	var p1_eye: Color = Color("78f4e6")
	var p1_core: Color = Color("d0fff8")

	var p2_main: Color = Color("b47aff")
	var p2_dark: Color = Color("6636ad")
	var p2_spark: Color = Color("ff8ae2")
	var p2_eye: Color = Color("ff8ae2")
	var p2_core: Color = Color("fff0b0")

	var p3_main: Color = Color("ffe488")
	var p3_dark: Color = Color("c85e24")
	var p3_spark: Color = Color("ff7847")
	var p3_eye: Color = Color("ff5838")
	var p3_core: Color = Color("ffffff")

	var pr: float = clampf(prism_release, 0.0, 1.0)
	var st: float = clampf(storm_ascension, 0.0, 1.0)
	var main_c: Color = p1_main.lerp(p2_main, pr).lerp(p3_main, st)
	var dark_c: Color = p1_dark.lerp(p2_dark, pr).lerp(p3_dark, st)
	var spark_c: Color = p1_spark.lerp(p2_spark, pr).lerp(p3_spark, st)
	var eye_c: Color = p1_eye.lerp(p2_eye, pr).lerp(p3_eye, st)
	var core_c: Color = p1_core.lerp(p2_core, pr).lerp(p3_core, st)
	var vein_c: Color = Color("78f4e6").lerp(Color("ff8ae2"), pr * 0.7).lerp(Color("ffe488"), st * 0.75)
	return {
		"main": main_c,
		"dark": dark_c,
		"spark": spark_c,
		"eye": eye_c,
		"core": core_c,
		"vein": vein_c,
	}


# ==============================================================================
# PIXEL-ART SPAN RASTERIZERS (CRAGS, GEODE CRYSTALS, STRATA, FRACTURE VEINS)
# ==============================================================================
func _oval(canvas: Node2D, center: Vector2, radius: Vector2, color: Color) -> void:
	var rx: int = maxi(1, roundi(radius.x))
	var ry: int = maxi(1, roundi(radius.y))
	var key: String = "o%d_%d" % [rx, ry]
	var mask: Array = _OVAL_MASKS.get(key, []) as Array
	if mask.is_empty():
		var rows: Array[Vector3i] = []
		for y: int in range(-ry, ry + 1):
			var q: float = float(y) / maxf(float(ry), 0.5)
			if absf(q) > 1.0:
				continue
			var w: int = floori(sqrt(maxf(0.0, 1.0 - q * q)) * float(rx))
			rows.append(Vector3i(-w, y, w * 2 + 1))
		mask = CrusherRig._mask(rows)
		_OVAL_MASKS[key] = mask
	if mask[0] != null:
		canvas.draw_texture(mask[0] as Texture2D, center.round() + Vector2(mask[1] as Vector2i), color)


func _poly_spans(pts: PackedVector2Array) -> Dictionary:
	var n: int = pts.size()
	if n < 3:
		return {}
	var y_min: int = 100000
	var y_max: int = -100000
	for p: Vector2 in pts:
		var py: int = roundi(p.y)
		if py < y_min:
			y_min = py
		if py > y_max:
			y_max = py
	var h: int = y_max - y_min + 1
	if h <= 0 or h > 300:
		return {}
	var lo: PackedInt32Array = PackedInt32Array()
	var hi: PackedInt32Array = PackedInt32Array()
	lo.resize(h)
	hi.resize(h)
	for r: int in h:
		lo[r] = 100000
		hi[r] = -100000
	for r: int in h:
		var sy: float = float(y_min + r) + 0.05
		var xs: Array[float] = []
		for i: int in n:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % n]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				var t: float = (sy - a.y) / (b.y - a.y)
				xs.append(lerpf(a.x, b.x, t))
		if xs.size() >= 2:
			xs.sort()
			lo[r] = roundi(xs[0])
			hi[r] = roundi(xs[xs.size() - 1])
	for p: Vector2 in pts:
		var r: int = clampi(roundi(p.y) - y_min, 0, h - 1)
		var px: int = roundi(p.x)
		if px < lo[r]:
			lo[r] = px
		if px > hi[r]:
			hi[r] = px
	return {"y0": y_min, "lo": lo, "hi": hi}


func _draw_silhouette_outline(canvas: Node2D, faces: Array[PackedVector2Array], out_col: Color) -> void:
	if faces.is_empty():
		return
	var spans_list: Array[Dictionary] = []
	var y_min: int = 100000
	var y_max: int = -100000
	for f: PackedVector2Array in faces:
		var sp: Dictionary = _poly_spans(f)
		if sp.is_empty():
			continue
		spans_list.append(sp)
		var sy0: int = int(sp["y0"])
		var slo: PackedInt32Array = sp["lo"] as PackedInt32Array
		y_min = mini(y_min, sy0)
		y_max = maxi(y_max, sy0 + slo.size() - 1)
	if spans_list.is_empty():
		return
	var h: int = y_max - y_min + 1
	var u_lo: PackedInt32Array = PackedInt32Array()
	var u_hi: PackedInt32Array = PackedInt32Array()
	u_lo.resize(h)
	u_hi.resize(h)
	for r: int in h:
		u_lo[r] = 100000
		u_hi[r] = -100000
	for sp: Dictionary in spans_list:
		var sy0: int = int(sp["y0"])
		var slo: PackedInt32Array = sp["lo"] as PackedInt32Array
		var shi: PackedInt32Array = sp["hi"] as PackedInt32Array
		for i: int in slo.size():
			if slo[i] > shi[i]:
				continue
			var ur: int = sy0 + i - y_min
			u_lo[ur] = mini(u_lo[ur], slo[i])
			u_hi[ur] = maxi(u_hi[ur], shi[i])
	for r: int in range(-1, h + 1):
		var x0: int = 100000
		var x1: int = -100000
		if r >= 0 and r < h and u_lo[r] <= u_hi[r]:
			x0 = mini(x0, u_lo[r] - 1)
			x1 = maxi(x1, u_hi[r] + 1)
		if r - 1 >= 0 and r - 1 < h and u_lo[r - 1] <= u_hi[r - 1]:
			x0 = mini(x0, u_lo[r - 1])
			x1 = maxi(x1, u_hi[r - 1])
		if r + 1 >= 0 and r + 1 < h and u_lo[r + 1] <= u_hi[r + 1]:
			x0 = mini(x0, u_lo[r + 1])
			x1 = maxi(x1, u_hi[r + 1])
		if x0 <= x1:
			canvas.draw_rect(Rect2(float(x0), float(y_min + r), float(x1 - x0 + 1), 1.0), out_col)


func _draw_flat_span_poly(canvas: Node2D, poly: PackedVector2Array, col: Color, top_rim: Color = Color(0, 0, 0, 0), has_rim: bool = false) -> void:
	var sp: Dictionary = _poly_spans(poly)
	if sp.is_empty():
		return
	var y0: int = int(sp["y0"])
	var lo: PackedInt32Array = sp["lo"] as PackedInt32Array
	var hi: PackedInt32Array = sp["hi"] as PackedInt32Array
	for r: int in lo.size():
		if lo[r] > hi[r]:
			continue
		var c: Color = top_rim if (has_rim and r == 0) else col
		canvas.draw_rect(Rect2(float(lo[r]), float(y0 + r), float(hi[r] - lo[r] + 1), 1.0), c)


func _draw_pixel_line(canvas: Node2D, a: Vector2, b: Vector2, col: Color, thickness: float = 1.0) -> void:
	var d: float = a.distance_to(b)
	var steps: int = maxi(1, ceili(d))
	var sz: Vector2 = Vector2(thickness, thickness)
	var off: Vector2 = Vector2.ONE * floorf(thickness * 0.5)
	for i: int in steps + 1:
		var pt: Vector2 = a.lerp(b, float(i) / float(steps)).round() - off
		canvas.draw_rect(Rect2(pt, sz), col)


func _draw_branching_crack(canvas: Node2D, p0: Vector2, p1: Vector2, seed_i: int, dark_c: Color, main_c: Color, spark_c: Color, alpha: float) -> void:
	var mid: Vector2 = p0.lerp(p1, 0.5)
	var perp: Vector2 = (p1 - p0).normalized().orthogonal()
	var k1: Vector2 = p0.lerp(p1, 0.34) + perp * ((_hashf(seed_i, 11) - 0.5) * 6.0)
	var k2: Vector2 = mid + perp * ((_hashf(seed_i, 23) - 0.5) * 7.0)
	var dark_line: Color = Color(dark_c, alpha * 0.9)
	var bright_line: Color = Color(main_c, alpha * 0.95)
	_draw_pixel_line(canvas, p0, k1, dark_line, 2.0)
	_draw_pixel_line(canvas, k1, k2, dark_line, 2.0)
	_draw_pixel_line(canvas, k2, p1, dark_line, 1.0)
	_draw_pixel_line(canvas, p0, k1, bright_line, 1.0)
	_draw_pixel_line(canvas, k1, k2, bright_line, 1.0)
	# Fork twig
	var fork: Vector2 = k1 + perp * ((1.0 if _hashf(seed_i, 37) > 0.5 else -1.0) * (4.0 + _hashf(seed_i, 41) * 4.0)) + (p1 - p0).normalized() * 3.0
	_draw_pixel_line(canvas, k1, fork, bright_line, 1.0)
	canvas.draw_rect(Rect2(k1.round(), Vector2(2, 2)), Color(spark_c, alpha))


## Generates an asymmetrical chipped geological crag polygon (NEVER rectangular, NEVER smooth circle).
func _crag_poly2d(center2: Vector2, rx: float, ry: float, rot: float, seed_i: int, verts: int = 12, taper_bottom: float = 0.0, taper_top: float = 0.0) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var cr: float = cos(rot)
	var sr: float = sin(rot)
	for i: int in verts:
		var ang: float = (float(i) / float(verts)) * TAU + (_hashf(seed_i, i * 17 + 3) - 0.5) * (TAU / float(verts) * 0.38)
		var ca: float = cos(ang)
		var sa: float = sin(ang)
		var rad_j: float = 0.78 + _hashf(seed_i, i * 31 + 7) * 0.42
		# Extra chiseled ledge angles
		if i % 3 == 0:
			rad_j *= 1.12
		elif i % 3 == 1:
			rad_j *= 0.88
		var lx: float = ca * rx * rad_j
		var ly: float = sa * ry * rad_j
		if sa > 0.0 and absf(taper_bottom) > 0.01:
			lx *= lerpf(1.0, 1.0 - taper_bottom, sa)
		if sa < 0.0 and absf(taper_top) > 0.01:
			lx *= lerpf(1.0, 1.0 - taper_top, -sa)
		var wx: float = lx * cr - ly * sr
		var wy: float = lx * sr + ly * cr
		pts.append((center2 + Vector2(wx, wy)).round())
	return pts


## Draws a heavily detailed pixel-art sandstone boulder / crag mass with 1-px ink outline,
## 4-step cel-shaded volume from top-left light, geological strata shelves, dark pits,
## optional gold temple clamps, and branching glowing magic fissures.
func _draw_crag_boulder(canvas: Node2D, center2: Vector2, rx: float, ry: float, rot: float, seed_i: int, flash_mix: float, alpha: float, mpal: Dictionary, opts: Dictionary = {}) -> void:
	if alpha <= 0.03 or rx < 1.5 or ry < 1.5:
		return
	var taper_b: float = float(opts.get("taper_bottom", 0.0))
	var taper_t: float = float(opts.get("taper_top", 0.0))
	var is_gold: bool = bool(opts.get("gold", false))
	var gold_trim: bool = bool(opts.get("gold_trim", false))
	var has_cracks: bool = bool(opts.get("cracks", true))
	var ndl_bias: float = float(opts.get("ndl", 0.15))

	var poly: PackedVector2Array = _crag_poly2d(center2, rx, ry, rot, seed_i, maxi(10, int(rx * 0.7)), taper_b, taper_t)
	var sp: Dictionary = _poly_spans(poly)
	if sp.is_empty():
		return

	var y0: int = int(sp["y0"])
	var lo: PackedInt32Array = sp["lo"] as PackedInt32Array
	var hi: PackedInt32Array = sp["hi"] as PackedInt32Array
	var h: int = lo.size()

	var p_out: Color = (GD_OUT if is_gold else ST_OUT).lerp(Color.WHITE, flash_mix * 0.45)
	var p0: Color = (GD_0 if is_gold else ST_0).lerp(Color.WHITE, flash_mix)
	var p1: Color = (GD_1 if is_gold else ST_1).lerp(Color.WHITE, flash_mix)
	var p2: Color = (GD_2 if is_gold else ST_2).lerp(Color.WHITE, flash_mix)
	var p3: Color = (GD_3 if is_gold else ST_3).lerp(Color.WHITE, flash_mix)
	var p4: Color = (GD_3 if is_gold else ST_4).lerp(Color.WHITE, flash_mix)
	p_out.a *= alpha
	p0.a *= alpha
	p1.a *= alpha
	p2.a *= alpha
	p3.a *= alpha
	p4.a *= alpha

	# 1) 1-px crisp tinted silhouette outline
	_draw_silhouette_outline(canvas, [poly], p_out)

	# 2) Scanline volume shading (top-left sunlight, rocky stepped bands, lower-right shadow)
	for r: int in h:
		var x_l: int = lo[r]
		var x_r: int = hi[r]
		if x_l > x_r:
			continue
		var row_w: int = x_r - x_l + 1
		var yf: float = float(r) / maxf(float(h - 1), 1.0)
		var y_screen: float = float(y0 + r)

		# Deep shadow base across full row
		canvas.draw_rect(Rect2(float(x_l), y_screen, float(row_w), 1.0), p0)

		# Mid rock core shifted top-left
		var mid_end: int = x_r - maxi(1, roundi(float(row_w) * lerpf(0.08, 0.34, yf)))
		if mid_end >= x_l and yf < 0.88:
			var base_c: Color = p2 if (yf < 0.56 and ndl_bias > -0.25) else p1
			canvas.draw_rect(Rect2(float(x_l), y_screen, float(mid_end - x_l + 1), 1.0), base_c)

		# Sunlit upper-left ledge highlight
		if yf < 0.52 and ndl_bias > -0.35:
			var hi_end: int = x_l + maxi(0, roundi(float(row_w) * lerpf(0.74, 0.22, yf / 0.52)) - 1)
			if hi_end >= x_l + 1:
				var hi_c: Color = p4 if (r <= 1 or (yf < 0.16 and _hashf(seed_i, r) > 0.35)) else p3
				canvas.draw_rect(Rect2(float(x_l), y_screen, float(hi_end - x_l + 1), 1.0), hi_c)

		# Deterministic geological sandstone strata shelves & weathered rock chips (non-flickering)
		if row_w >= 8 and r > 1 and r < h - 2:
			var stratum: int = (r + seed_i * 3) % 5
			if stratum == 0:
				var sx0: int = x_l + 2 + int(_hashf(seed_i, r * 19) * float(maxi(1, row_w / 4)))
				var sx1: int = mini(x_r - 2, sx0 + maxi(3, row_w / 3))
				if sx1 > sx0:
					canvas.draw_rect(Rect2(float(sx0), y_screen, float(sx1 - sx0 + 1), 1.0), p0 if yf > 0.45 else p1)
			elif stratum == 2 and yf < 0.65:
				var lx0: int = x_l + 1 + int(_hashf(seed_i, r * 29) * float(maxi(1, row_w / 5)))
				var lx1: int = mini(x_r - 3, lx0 + maxi(2, row_w / 4))
				if lx1 > lx0:
					canvas.draw_rect(Rect2(float(lx0), y_screen, float(lx1 - lx0 + 1), 1.0), p4)

	# 3) Ancient Gold Temple Clamp / Asymmetric Broken Band
	if gold_trim and rx >= 8.0 and ry >= 7.0:
		var band_y: float = center2.y + ry * 0.22
		var b_l: Vector2 = Vector2(center2.x - rx * 0.65, band_y - 2.0).round()
		var b_r: Vector2 = Vector2(center2.x + rx * 0.62, band_y + 1.5).round()
		var g_out: Color = Color(GD_OUT, alpha)
		var g_mid: Color = Color(GD_2.lerp(Color.WHITE, flash_mix), alpha)
		var g_hi: Color = Color(GD_3.lerp(Color.WHITE, flash_mix), alpha)
		_draw_pixel_line(canvas, b_l + Vector2(0, 1), b_r + Vector2(0, 1), g_out, 3.0)
		_draw_pixel_line(canvas, b_l, b_r, g_mid, 2.0)
		_draw_pixel_line(canvas, b_l + Vector2(1, -1), b_l.lerp(b_r, 0.55) + Vector2(0, -1), g_hi, 1.0)
		# Golden rivet / glyph notch
		var gm: Vector2 = b_l.lerp(b_r, 0.48).round()
		canvas.draw_rect(Rect2(gm - Vector2(2, 2), Vector2(5, 5)), Color(GD_1, alpha))
		canvas.draw_rect(Rect2(gm - Vector2(1, 1), Vector2(3, 3)), Color(mpal["spark"] as Color, alpha))

	# 4) Flowing Internal Arcane Fractures inside the Rock
	if has_cracks and rx >= 7.0 and ry >= 7.0:
		var main_c: Color = mpal["main"] as Color
		var dark_c: Color = mpal["dark"] as Color
		var spark_c: Color = mpal["spark"] as Color
		var c_a: Vector2 = center2 + Vector2((_hashf(seed_i, 101) - 0.5) * rx * 0.8, -ry * 0.45)
		var c_b: Vector2 = center2 + Vector2((_hashf(seed_i, 103) - 0.5) * rx * 0.7, ry * 0.45)
		_draw_branching_crack(canvas, c_a, c_b, seed_i + 19, dark_c, main_c, spark_c, alpha * 0.92)


## Draws a rich 3D multi-faceted raw sun-quartz crystal spire (`6-vertex chiseled prism + internal refraction core + specular ridge`).
func _draw_geode_crystal3d(canvas: Node2D, base_3d: Vector3, dir_3d: Vector3, length: float, half_w: float, flash_mix: float, vein_col: Color, alpha: float = 1.0, core_glow: Color = Color(0, 0, 0, 0)) -> void:
	if length <= 2.0 or alpha <= 0.03:
		return
	var base2: Vector2 = _project_v(base_3d)
	var tip2: Vector2 = _project_v(base_3d + dir_3d.normalized() * length)
	var span: Vector2 = tip2 - base2
	var len2: float = span.length()
	if len2 < 2.5:
		len2 = 2.5
		span = Vector2(0.0, -2.5)
	var axis: Vector2 = span / len2
	var perp: Vector2 = Vector2(-axis.y, axis.x)
	var lit_left: bool = perp.x + perp.y <= 0.0
	var p_lt: Vector2 = perp if lit_left else -perp
	var p_rt: Vector2 = -p_lt

	# Chiseled asymmetric quartz hexagon/heptagon with stepped shoulder facets
	var pb_l: Vector2 = (base2 + p_lt * (half_w * 0.82) - axis * 1.2).round()
	var pb_r: Vector2 = (base2 + p_rt * (half_w * 0.92) - axis * 1.2).round()
	var pm_l: Vector2 = (base2 + axis * (len2 * 0.48) + p_lt * (half_w * 1.15)).round()
	var pm_r: Vector2 = (base2 + axis * (len2 * 0.58) + p_rt * (half_w * 1.08)).round()
	var pu_l: Vector2 = (base2 + axis * (len2 * 0.78) + p_lt * (half_w * 0.62)).round()
	var pu_r: Vector2 = (base2 + axis * (len2 * 0.82) + p_rt * (half_w * 0.52)).round()
	var pt: Vector2 = (base2 + axis * len2).round()

	# Inner longitudinal facet ridges
	var ridge_base: Vector2 = (base2 + p_lt * (half_w * 0.16)).round()
	var ridge_mid: Vector2 = (base2 + axis * (len2 * 0.62) + p_lt * (half_w * 0.12)).round()

	var q_out: Color = QZ_OUT.lerp(Color.WHITE, flash_mix * 0.45)
	q_out.a *= alpha
	var sil: PackedVector2Array = PackedVector2Array([pb_l, pb_r, pm_r, pu_r, pt, pu_l, pm_l])
	_draw_silhouette_outline(canvas, [sil], q_out)

	# 3 Facet planes
	var f_lit: PackedVector2Array = PackedVector2Array([pb_l, ridge_base, ridge_mid, pu_l, pm_l])
	var f_mid: PackedVector2Array = PackedVector2Array([ridge_base, pb_r, pm_r, ridge_mid])
	var f_dark: PackedVector2Array = PackedVector2Array([ridge_mid, pm_r, pu_r, pt, pu_l])
	_draw_flat_span_poly(canvas, f_lit, Color(QZ_3.lerp(Color.WHITE, flash_mix), alpha), Color(QZ_4, alpha), true)
	_draw_flat_span_poly(canvas, f_mid, Color(QZ_1.lerp(Color.WHITE, flash_mix), alpha))
	_draw_flat_span_poly(canvas, f_dark, Color(QZ_0.lerp(Color.WHITE, flash_mix), alpha))
	# Deep tip/shadow cap triangle on right side
	var f_tip_lit: PackedVector2Array = PackedVector2Array([pu_l, ridge_mid, pt])
	_draw_flat_span_poly(canvas, f_tip_lit, Color(QZ_2.lerp(Color.WHITE, flash_mix), alpha))

	# Internal glowing refraction veins & base magic root
	_draw_pixel_line(canvas, ridge_base, ridge_mid.lerp(pt, 0.72), Color(QZ_4, alpha * 0.92), 1.0)
	_draw_pixel_line(canvas, pm_l, pt, Color(QZ_4, alpha * 0.75), 1.0)
	_draw_pixel_line(canvas, base2 + axis * 3.0, base2 + axis * (len2 * 0.74), Color(vein_col, alpha * 0.95), 2.0 if half_w >= 4.0 else 1.0)
	if core_glow.a > 0.05:
		canvas.draw_rect(Rect2((base2 + axis * (len2 * 0.2)).round() - Vector2(2, 2), Vector2(4, 4)), Color(core_glow, alpha * 0.9))
		canvas.draw_rect(Rect2(pt, Vector2(2, 2)), Color(QZ_4, alpha))


## Draws 3 intertwined sine-wave arcane plasma ribbons + drifting stone fragments along a tether!
func _draw_braided_tether(canvas: Node2D, a: Vector2, b: Vector2, main_c: Color, dark_c: Color, spark_c: Color, phase_off: float, alpha: float) -> void:
	var diff: Vector2 = b - a
	var d: float = diff.length()
	if d < 3.0:
		return
	var dir: Vector2 = diff / d
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var steps: int = maxi(8, ceili(d * 0.65))
	for strand: int in 3:
		var prev_p: Vector2 = Vector2.ZERO
		var col: Color = dark_c if strand == 0 else (main_c if strand == 1 else spark_c)
		var thick: float = 2.5 if strand == 0 else (2.0 if strand == 1 else 1.0)
		col.a *= alpha * (0.72 if strand == 0 else 0.95)
		var amp_base: float = 3.2 if strand == 0 else (2.4 if strand == 1 else 1.8)
		var s_phase: float = phase_off + float(strand) * 2.1
		for s: int in steps + 1:
			var t: float = float(s) / float(steps)
			var env: float = sin(t * PI)
			var wave: float = sin(t * 10.5 - _time * 8.5 + s_phase) * amp_base * env
			var pt: Vector2 = (a.lerp(b, t) + perp * wave).round()
			if s > 0:
				_draw_pixel_line(canvas, prev_p, pt, col, thick)
			prev_p = pt
	# 3 small levitating rune pebbles flowing from body toward the gauntlet
	for f_i: int in 3:
		var ft: float = fposmod(float(f_i) * 0.34 + _time * 0.45, 1.0)
		var fp: Vector2 = (a.lerp(b, ft) + perp * sin(ft * 9.0 + float(f_i)) * 4.5).round()
		canvas.draw_rect(Rect2(fp - Vector2(2, 2), Vector2(4, 3)), Color(ST_OUT, alpha))
		canvas.draw_rect(Rect2(fp - Vector2(1, 1), Vector2(2, 2)), Color(ST_2 if f_i % 2 == 0 else QZ_2, alpha))
		if f_i == 1:
			canvas.draw_rect(Rect2(fp, Vector2(2, 1)), Color(spark_c, alpha))


# ==============================================================================
# PART QUEUE & POSE KINEMATICS (~156 px HOVERING COLOSSUS)
# ==============================================================================
func _add_part(depth: float, draw_cb: Callable) -> void:
	_parts.append({"d": depth, "fn": draw_cb})


func _compute_rig_pose() -> Dictionary:
	var p: float = _pose_progress()
	var hover_z: float = 6.0 * sin(_time * 2.1)
	var bob: float = sin(_time * 2.4) * 2.2
	var lean: float = 4.0
	var chest_open: float = 4.0 + prism_release * 7.5 + storm_ascension * 4.5
	var head_z: float = 112.0 + hover_z
	var shoulder_z: float = 90.0 + hover_z + bob * 0.4
	var core_z: float = 78.0 + hover_z + bob * 0.5
	var beam_charge: float = clampf(charge_intensity, 0.0, 1.0)
	var blade_l: float = 0.9 if twin_blades else 0.0
	var blade_r: float = 0.9 if twin_blades else 0.0
	var blade_sweep: float = 0.28
	var awaken_t: float = 1.0
	var dead_t: float = 0.0
	var claw_open: float = 0.45

	# Monumental wide poised gauntlets (~168 px wing-to-gauntlet span)
	var hand_l: Vector3 = Vector3(16.0, -56.0, 44.0 + sin(_time * 2.4 + 0.8) * 4.0)
	var hand_r: Vector3 = Vector3(16.0, 56.0, 44.0 + sin(_time * 2.4 - 0.8) * 4.0)
	var arm_l: Vector3 = Vector3(6.0, -59.0, 68.0 + sin(_time * 2.4 + 0.3) * 3.0)
	var arm_r: Vector3 = Vector3(6.0, 59.0, 68.0 + sin(_time * 2.4 - 0.3) * 3.0)

	match _pose:
		Pose.DORMANT:
			awaken_t = 0.0
		Pose.AWAKEN:
			var rise: float = smoothstep(0.08, 0.92, p)
			awaken_t = rise
			core_z = lerpf(24.0, 78.0, rise)
			head_z = core_z + 34.0
			shoulder_z = core_z + 14.0
			chest_open += sin(p * PI) * 8.0
			hand_l = Vector3(14.0, lerpf(-28.0, -58.0, rise), lerpf(10.0, 64.0, rise))
			hand_r = Vector3(14.0, lerpf(28.0, 58.0, rise), lerpf(10.0, 64.0, rise))
			arm_l = Vector3(4.0, -48.0, core_z - 4.0)
			arm_r = Vector3(4.0, 48.0, core_z - 4.0)
			claw_open = 0.85
		Pose.MOVE:
			lean = 9.0 + _speed_ratio * 4.0
			hover_z += absf(sin(_stride)) * 4.0
			hand_l = Vector3(20.0 + sin(_stride) * 7.0, -58.0, 48.0)
			hand_r = Vector3(20.0 - sin(_stride) * 7.0, 58.0, 48.0)
		Pose.GAUNTLET_SLAM:
			if p < 0.45:
				var w: float = smoothstep(0.0, 0.45, p)
				hand_r = Vector3(18.0, 54.0, lerpf(50.0, 108.0, w))
				arm_r = Vector3(8.0, 58.0, lerpf(70.0, 96.0, w))
				lean = lerpf(4.0, -5.0, w)
				claw_open = 0.1
			elif p < 0.65:
				var s: float = smoothstep(0.45, 0.65, p)
				hand_r = Vector3(lerpf(18.0, 38.0, s), lerpf(54.0, 36.0, s), lerpf(108.0, 4.0, s))
				arm_r = Vector3(22.0, 44.0, lerpf(96.0, 34.0, s))
				lean = lerpf(-5.0, 14.0, s)
				claw_open = 0.0
			else:
				var rec: float = smoothstep(0.65, 1.0, p)
				hand_r = Vector3(lerpf(38.0, 16.0, rec), lerpf(36.0, 56.0, rec), lerpf(4.0, 46.0, rec))
				arm_r = Vector3(10.0, 56.0, lerpf(34.0, 68.0, rec))
				lean = lerpf(14.0, 4.0, rec)
		Pose.FAULT_SLAM:
			var raise_t: float = smoothstep(0.0, 0.42, p)
			var drop_t: float = smoothstep(0.42, 0.64, p)
			var up_mix: float = raise_t * (1.0 - drop_t)
			var z_f: float = lerpf(44.0, 104.0, up_mix) - drop_t * 36.0
			hand_l = Vector3(24.0 + drop_t * 10.0, lerpf(-56.0, -34.0, drop_t), maxf(4.0, z_f))
			hand_r = Vector3(24.0 + drop_t * 10.0, lerpf(56.0, 34.0, drop_t), maxf(4.0, z_f))
			claw_open = 0.05
			beam_charge = maxf(beam_charge, up_mix * 0.8)
		Pose.SINKHOLE_CAST:
			var cast_w: float = sin(minf(p * 1.4, 1.0) * PI)
			hand_l = Vector3(24.0, -64.0, 82.0 + cast_w * 20.0)
			hand_r = Vector3(24.0, 64.0, 82.0 + cast_w * 20.0)
			chest_open += 7.0 * cast_w
			beam_charge = maxf(beam_charge, 0.65 * cast_w)
			claw_open = 1.0
		Pose.BLADE_CLEAVE:
			blade_r = 1.0
			if twin_blades or storm_ascension > 0.35:
				blade_l = 1.0
			if p < 0.38:
				var prep: float = smoothstep(0.0, 0.38, p)
				blade_sweep = lerpf(0.28, 1.35, prep)
				hand_r = Vector3(lerpf(16.0, -4.0, prep), lerpf(56.0, 74.0, prep), lerpf(44.0, 80.0, prep))
				hand_l = Vector3(14.0, -64.0, 66.0)
			elif p < 0.72:
				var sw: float = smoothstep(0.38, 0.72, p)
				blade_sweep = lerpf(1.35, -1.2, sw)
				hand_r = Vector3(lerpf(-4.0, 32.0, sw), lerpf(74.0, -18.0, sw), lerpf(80.0, 52.0, sw))
				lean = 12.0 * sin(sw * PI)
			else:
				var rec: float = smoothstep(0.72, 1.0, p)
				blade_sweep = lerpf(-1.2, 0.28, rec)
				hand_r = Vector3(18.0, lerpf(-18.0, 56.0, rec), 48.0)
		Pose.CHEST_BEAM:
			var hold: float = sin(clampf(p * 1.25, 0.0, 1.0) * PI * 0.5)
			chest_open += 11.5 * hold
			beam_charge = maxf(beam_charge, 0.75 + 0.25 * hold)
			lean = -5.0 * hold
			hand_l = Vector3(8.0, -68.0 - 8.0 * hold, 76.0)
			hand_r = Vector3(8.0, 68.0 + 8.0 * hold, 76.0)
			arm_l = Vector3(2.0, -64.0, 84.0)
			arm_r = Vector3(2.0, 64.0, 84.0)
			claw_open = 1.0
		Pose.CLAP_PREP:
			var spread: float = smoothstep(0.0, 1.0, p)
			hand_l = Vector3(24.0, lerpf(-56.0, -78.0, spread), lerpf(48.0, 68.0, spread))
			hand_r = Vector3(24.0, lerpf(56.0, 78.0, spread), lerpf(48.0, 68.0, spread))
			chest_open += 5.0 * spread
			beam_charge = maxf(beam_charge, 0.55 * spread)
			claw_open = 0.85
		Pose.CLAP_CRUSH:
			var slam_m: float = smoothstep(0.0, 0.35, p)
			hand_l = Vector3(lerpf(24.0, 34.0, slam_m), lerpf(-78.0, -13.0, slam_m), 56.0)
			hand_r = Vector3(lerpf(24.0, 34.0, slam_m), lerpf(78.0, 13.0, slam_m), 56.0)
			lean = 12.0 * slam_m
			claw_open = 0.1
		Pose.ZENITH_CHARGE:
			# Regal sun-god ascent: wide open chest & high outstretched colossal gauntlets + angled crystal blades!
			var lift_p: float = clampf(0.45 + p * 0.55, 0.0, 1.0)
			core_z += 12.0 + lift_p * 8.0
			head_z += 14.0 + lift_p * 8.0
			shoulder_z += 12.0 + lift_p * 8.0
			chest_open += 13.0
			beam_charge = 1.0
			blade_l = 1.0
			blade_r = 1.0
			blade_sweep = 1.15
			claw_open = 1.0
			hand_l = Vector3(-4.0, -76.0, 94.0 + sin(_time * 6.0) * 3.0)
			hand_r = Vector3(-4.0, 76.0, 94.0 - sin(_time * 6.0) * 3.0)
			arm_l = Vector3(-2.0, -64.0, 98.0)
			arm_r = Vector3(-2.0, 64.0, 98.0)
		Pose.STAGGER:
			# Collapsed low into sand, huge split ribs wide open revealing blazing exposed core
			core_z = 36.0 + sin(_time * 9.0) * 1.6
			head_z = 56.0
			shoulder_z = 48.0
			lean = 16.0
			chest_open += 14.0
			hand_l = Vector3(24.0, -52.0, 6.0)
			hand_r = Vector3(24.0, 52.0, 6.0)
			arm_l = Vector3(14.0, -48.0, 26.0)
			arm_r = Vector3(14.0, 48.0, 26.0)
			blade_l = 0.0
			blade_r = 0.0
			claw_open = 0.9
		Pose.DEAD:
			dead_t = smoothstep(0.0, 1.0, p)
			core_z = lerpf(62.0, 10.0, dead_t)
			head_z = lerpf(92.0, 16.0, dead_t)
			shoulder_z = lerpf(74.0, 12.0, dead_t)
			chest_open += dead_t * 14.0
			hand_l = Vector3(16.0, -56.0 - dead_t * 12.0, maxf(2.0, 42.0 * (1.0 - dead_t)))
			hand_r = Vector3(16.0, 56.0 + dead_t * 12.0, maxf(2.0, 42.0 * (1.0 - dead_t)))

	return {
		"lean": lean,
		"chest_open": chest_open,
		"core_z": core_z,
		"head_z": head_z,
		"shoulder_z": shoulder_z,
		"arm_l": arm_l,
		"arm_r": arm_r,
		"hand_l": hand_l,
		"hand_r": hand_r,
		"blade_l": blade_l,
		"blade_r": blade_r,
		"blade_sweep": blade_sweep,
		"beam_charge": beam_charge,
		"awaken_t": awaken_t,
		"dead_t": dead_t,
		"claw_open": claw_open,
	}


# ==============================================================================
# MAIN WORLD-LIT PASS (`Body`)
# ==============================================================================
func _draw_body() -> void:
	_update_frame_vectors()
	_parts.clear()

	var mpal: Dictionary = _magic_palette()
	var main_c: Color = mpal["main"] as Color
	var dark_c: Color = mpal["dark"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var eye_c: Color = mpal["eye"] as Color
	var vein_c: Color = mpal["vein"] as Color
	var flash_mix: float = clampf(_flash / 0.14, 0.0, 1.0)

	if _pose == Pose.DORMANT:
		_draw_dormant_monument(mpal, flash_mix)
		return

	var kp: Dictionary = _compute_rig_pose()
	var lean: float = float(kp["lean"])
	var chest_open: float = float(kp["chest_open"])
	var core_z: float = float(kp["core_z"])
	var head_z: float = float(kp["head_z"])
	var sh_z: float = float(kp["shoulder_z"])
	var beam_charge: float = float(kp["beam_charge"])
	var awaken_t: float = float(kp["awaken_t"])
	var dead_t: float = float(kp["dead_t"])
	var claw_open: float = float(kp["claw_open"])
	var alpha: float = clampf((1.0 - dead_t * 0.9) * clampf(awaken_t * 1.25, 0.0, 1.0), 0.0, 1.0)
	if alpha <= 0.02:
		return

	var core_pos3: Vector3 = Vector3(lean, 0.0, core_z)
	var head_pos3: Vector3 = Vector3(lean + 4.5, 0.0, head_z)
	var sh_l3: Vector3 = Vector3(lean - 2.0, -43.0 - chest_open * 0.35, sh_z)
	var sh_r3: Vector3 = Vector3(lean - 2.0, 43.0 + chest_open * 0.35, sh_z)
	var arm_l3: Vector3 = (kp["arm_l"] as Vector3) + Vector3(lean * 0.5, 0.0, 0.0)
	var arm_r3: Vector3 = (kp["arm_r"] as Vector3) + Vector3(lean * 0.5, 0.0, 0.0)
	var hand_l3: Vector3 = (kp["hand_l"] as Vector3) + Vector3(lean * 0.6, 0.0, 0.0)
	var hand_r3: Vector3 = (kp["hand_r"] as Vector3) + Vector3(lean * 0.6, 0.0, 0.0)

	var hand_l_override: Vector2 = Vector2.INF
	var hand_r_override: Vector2 = Vector2.INF
	if _detached_fist_active[0]:
		hand_l_override = (_detached_fist_world[0] - global_position) + Vector2(0.0, -_detached_fist_lift[0])
	if _detached_fist_active[1]:
		hand_r_override = (_detached_fist_world[1] - global_position) + Vector2(0.0, -_detached_fist_lift[1])

	_core_local = _project_v(core_pos3)
	_head_local = _project_v(head_pos3 + Vector3(0.0, 0.0, 12.0))
	_fist_local[0] = hand_l_override if hand_l_override.is_finite() else _project_v(hand_l3)
	_fist_local[1] = hand_r_override if hand_r_override.is_finite() else _project_v(hand_r3)

	# 0) Colossal Ground Cast Shadow + Arcane Sand Whirlpool & Broken Temple Seal
	_draw_ground_seal_and_vortex(mpal, alpha, beam_charge)
	if _pose == Pose.AWAKEN:
		_draw_awakening_debris(main_c, spark_c, _pose_progress())

	# 1) LOWER BODY: Inverted Geode Tail-Spire & Orbiting Monolith Stones (Stage 1/2) -> Massive 96px Sandstorm Funnel (Stage 3)
	if storm_ascension < 0.90:
		var tail_alpha: float = alpha * (1.0 - smoothstep(0.25, 0.90, storm_ascension))
		var tail_z_base: float = maxf(10.0, core_z - 32.0)
		var tail_top3: Vector3 = Vector3(lean * 0.65, 0.0, tail_z_base)
		_add_part(_depth_v(tail_top3), _part_inverted_tail_spire.bind(tail_top3, core_z, tail_alpha, flash_mix, mpal))
		# 5 Orbiting floating monolith shard-plates circling the floating tail-spire
		for o_i: int in 5:
			var o_ang: float = _time * 1.45 + float(o_i) * (TAU / 5.0)
			var o_rad: float = 25.0 + float(o_i % 2) * 5.0
			var o_z: float = tail_z_base + float(o_i % 3) * 7.0 + sin(_time * 2.8 + float(o_i)) * 3.0
			var o_pos3: Vector3 = Vector3(lean * 0.5 + cos(o_ang) * o_rad * 0.72, sin(o_ang) * o_rad, o_z)
			_add_part(_depth_v(o_pos3), _part_orbit_plate.bind(o_pos3, o_i, tail_alpha, flash_mix, mpal))

	if storm_ascension > 0.05:
		_add_cyclone_parts(core_z - 12.0, alpha * smoothstep(0.05, 0.55, storm_ascension), mpal, flash_mix)

	# 2) DORSAL CANYON SPINE + DARK GEODE RIB CAVERN + 7 BACK QUARTZ SPIRES
	var spine3: Vector3 = core_pos3 + Vector3(-11.0, 0.0, 0.0)
	_add_part(_depth_v(spine3), _part_canyon_spine_and_cavern.bind(spine3, core_pos3, chest_open, alpha, flash_mix, mpal))

	# 3) ASTONISHING OPEN ASTRAL SUN-PRISM HEART
	_add_part(_depth_v(core_pos3) + 0.5, _part_prism_heart.bind(core_pos3, mpal, flash_mix, alpha, 1.0 + beam_charge * 0.3))

	# 4) V-TAPERED CRAGGY CHEST RIBS (Split open left/right around the geode cavern)
	var rib_sep: float = 17.5 + chest_open
	for side_i: int in 2:
		var s_sign: float = -1.0 if side_i == 0 else 1.0
		var rib3: Vector3 = core_pos3 + Vector3(5.0, s_sign * rib_sep, 2.0)
		_add_part(_depth_v(rib3) + 1.0, _part_chest_crag.bind(rib3, s_sign, side_i, alpha, flash_mix, mpal))

	# 5) STAGE 2/3 8 MONUMENTAL CRYSTAL WING-BLADES + 12 ORBITING SATELLITE SPLINTERS
	if prism_release > 0.04 or storm_ascension > 0.04:
		var wing_vis: float = smoothstep(0.04, 0.78, maxf(prism_release, storm_ascension))
		for side_i: int in 2:
			var s_sign: float = -1.0 if side_i == 0 else 1.0
			for w_i: int in 4:
				var w_ang: float = WING_ANGLES[w_i]
				var w_len: float = WING_LENS[w_i] * wing_vis * (1.0 + storm_ascension * 0.16)
				var w_w: float = WING_WIDTHS[w_i] * wing_vis
				var w_base: Vector3 = core_pos3 + Vector3(-12.0 - float(w_i) * 1.5, s_sign * (22.0 + float(w_i) * 5.0), 10.0 + float(w_i) * 6.0)
				var w_dir: Vector3 = Vector3(-0.24, s_sign * cos(w_ang * 0.62), sin(w_ang * 0.72) + 0.12).normalized()
				_add_part(_depth_v(w_base) - 2.0, _part_crystal_spire.bind(w_base, w_dir, w_len, w_w, flash_mix, main_c, alpha, spark_c))

		for sat_i: int in SAT_COUNT:
			var s_ang: float = _time * (0.95 if sat_i % 2 == 0 else -0.75) + float(sat_i) * (TAU / float(SAT_COUNT))
			var s_rad: float = 54.0 + float(sat_i % 3) * 11.0
			var s_z: float = core_z - 8.0 + float(sat_i % 5) * 16.0 + sin(_time * 2.2 + float(sat_i)) * 4.0
			var sat3: Vector3 = Vector3(lean + cos(s_ang) * s_rad * 0.65, sin(s_ang) * s_rad, s_z)
			_add_part(_depth_v(sat3), _part_satellite_shard.bind(sat3, sat_i, wing_vis * alpha, flash_mix, main_c))

	# 6) CANYON-MESA SHOULDER CRAGS + 6 ERUPTING QUARTZ PEAKS EACH
	for side_i: int in 2:
		var s_sign: float = -1.0 if side_i == 0 else 1.0
		var sh3: Vector3 = sh_l3 if side_i == 0 else sh_r3
		_add_part(_depth_v(sh3) + 1.2, _part_shoulder_crag.bind(sh3, s_sign, side_i, alpha, flash_mix, mpal))

	# 7) ANCIENT HORNED 3-EYED OBELISK VISAGE + 9-SHARD CATHEDRAL SUN-CROWN
	_add_part(_depth_v(head_pos3) + 1.5, _part_obelisk_head.bind(head_pos3, eye_c, main_c, spark_c, flash_mix, alpha))
	for c_i: int in 9:
		var c_side: float = CROWN_OFFSETS[c_i] * (0.86 + storm_ascension * 0.16)
		var c_z: float = head_z + 24.0 + CROWN_ARC_Z[c_i] + sin(_time * 2.7 + float(c_i) * 0.65) * 1.8
		var c_pos3: Vector3 = Vector3(head_pos3.x - 2.0, c_side, c_z)
		var c_dir: Vector3 = Vector3(-0.08, c_side * 0.019, 1.0).normalized()
		var c_flare: Color = spark_c if (beam_charge > 0.35 or c_i == 4) else vein_c
		var cw: float = 4.2 if c_i == 4 else (3.1 if absi(c_i - 4) <= 1 else 2.3)
		_add_part(_depth_v(c_pos3) + 0.4, _part_crystal_spire.bind(c_pos3, c_dir, CROWN_HEIGHTS[c_i], cw, flash_mix, c_flare, alpha, spark_c if c_i == 4 else Color(0, 0, 0, 0)))

	# 8) BRAIDED LEY-TETHERS + FOREARM BRACER CRAGS + COLOSSAL 4-TALON CLAW-GAUNTLETS + GREATBLADES
	for side_i: int in 2:
		var s_sign: float = -1.0 if side_i == 0 else 1.0
		var sh3: Vector3 = sh_l3 if side_i == 0 else sh_r3
		var arm3: Vector3 = arm_l3 if side_i == 0 else arm_r3
		var hand3: Vector3 = hand_l3 if side_i == 0 else hand_r3
		var p_sh2: Vector2 = _project_v(sh3 + Vector3(0, s_sign * 6.0, 4.0))
		var p_arm2: Vector2 = _project_v(arm3)
		var det_over: Vector2 = hand_l_override if side_i == 0 else hand_r_override
		var has_over: bool = det_over.is_finite()
		var blade_amt: float = float(kp["blade_l"]) if side_i == 0 else float(kp["blade_r"])

		if not has_over:
			_add_part(_depth_v(arm3) - 0.3, _part_braided_arm_tether.bind(p_sh2, p_arm2, _project_v(hand3), main_c, dark_c, spark_c, side_i, alpha))
			_add_part(_depth_v(arm3) + 0.5, _part_forearm_crag.bind(arm3, s_sign, side_i, alpha, flash_mix, mpal))
			_add_part(_depth_v(hand3) + 0.8, _part_colossus_gauntlet.bind(hand3, s_sign, side_i, mpal, flash_mix, alpha, blade_amt, float(kp["blade_sweep"]), claw_open))
		else:
			var det_depth: float = det_over.y + 42.0
			_add_part(det_depth - 0.5, _part_detached_tether.bind(p_sh2, det_over, main_c, dark_c, spark_c, alpha))
			_add_part(det_depth, _part_detached_gauntlet.bind(det_over, s_sign, side_i, mpal, flash_mix, alpha))

	# 9) STAGE 3 GIANT ROTATING 3D CELESTIAL ARMILLARY RINGS (`radius 64 & 76`)
	if storm_ascension > 0.05:
		_add_armillary_ring_parts(core_pos3 + Vector3(-4.0, 0.0, 10.0), 62.0, 0.38, _time * 1.05, alpha * smoothstep(0.05, 0.55, storm_ascension), mpal, flash_mix, false)
		_add_armillary_ring_parts(core_pos3 + Vector3(-4.0, 0.0, 10.0), 74.0, -0.44, -_time * 0.82 + 0.85, alpha * smoothstep(0.15, 0.70, storm_ascension), mpal, flash_mix, true)

	_parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for pt: Dictionary in _parts:
		(pt["fn"] as Callable).call()

	_draw_antigrav_motes(_body, main_c, spark_c, alpha, head_z + 30.0)


# ==============================================================================
# PART CALLBACKS (DETERMINISTIC `.bind(...)` HELPERS)
# ==============================================================================
func _part_prism_heart(core_pos3: Vector3, mpal: Dictionary, flash_mix: float, alpha: float, scale_k: float) -> void:
	_draw_astral_prism_heart(_body, core_pos3, mpal, flash_mix, alpha, scale_k)


func _draw_ground_seal_and_vortex(mpal: Dictionary, alpha: float, beam_charge: float) -> void:
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	# Broad ambient drop shadow under hovering monolith
	_oval(_body, Vector2(0.0, 2.0), Vector2(48.0, 17.0), Color(ST_OUT, 0.34 * alpha))
	_oval(_body, Vector2(0.0, 1.0), Vector2(36.0, 12.0), Color(SD_0, 0.25 * alpha))
	# Concentric carved sand-seal arcs + rotating rune glyphs
	var r_outer: float = 52.0 + beam_charge * 8.0
	var r_inner: float = 34.0
	var rot: float = _time * (0.45 + storm_ascension * 0.8)
	var glyphs: int = 16
	for g_i: int in glyphs:
		var a0: float = rot + float(g_i) / float(glyphs) * TAU
		var a1: float = a0 + 0.22
		var p0: Vector2 = Vector2(cos(a0) * r_outer, sin(a0) * r_outer * SQUASH).round()
		var p1: Vector2 = Vector2(cos(a1) * r_outer, sin(a1) * r_outer * SQUASH).round()
		_draw_pixel_line(_body, p0, p1, Color(main_c if g_i % 2 == 0 else SD_4, alpha * (0.48 + beam_charge * 0.35)), 2.0)
		if g_i % 2 == 0:
			var gi: Vector2 = Vector2(cos(a0) * r_inner, sin(a0) * r_inner * SQUASH).round()
			_body.draw_rect(Rect2(gi - Vector2.ONE, Vector2(3, 2)), Color(spark_c, alpha * 0.7))


func _part_inverted_tail_spire(tail_top3: Vector3, core_z: float, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c_base: Vector2 = _project_v(tail_top3 + Vector3(0.0, 0.0, 12.0))
	var tail_h: float = maxf(18.0, core_z - tail_top3.z)
	# Upper fractured waist monolith tapering strongly downward
	_draw_crag_boulder(_body, c_base + Vector2(0.0, 4.0), 21.0, tail_h * 0.55, 0.0, 107, flash_mix, alpha, mpal, {"taper_bottom": 0.62, "gold_trim": true, "cracks": true, "ndl": 0.2})
	# Deep downward raw sun-quartz crystal anchor tip hover-locked above the sand seal
	_draw_geode_crystal3d(_body, tail_top3 + Vector3(0.0, 0.0, 6.0), Vector3(0.05, 0.0, -1.0), 22.0, 6.5, flash_mix, mpal["main"] as Color, alpha, mpal["spark"] as Color)
	_draw_geode_crystal3d(_body, tail_top3 + Vector3(2.0, -10.0, 10.0), Vector3(0.1, -0.25, -0.95), 15.0, 3.6, flash_mix, mpal["vein"] as Color, alpha)
	_draw_geode_crystal3d(_body, tail_top3 + Vector3(2.0, 10.0, 10.0), Vector3(0.1, 0.25, -0.95), 15.0, 3.6, flash_mix, mpal["vein"] as Color, alpha)


func _part_orbit_plate(pos3: Vector3, idx: int, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(pos3)
	if idx % 2 == 0:
		_draw_crag_boulder(_body, c2, 7.5, 11.5, float(idx) * 0.4, 210 + idx * 17, flash_mix, alpha, mpal, {"taper_bottom": 0.45, "cracks": true})
	else:
		_draw_geode_crystal3d(_body, pos3 - Vector3(0, 0, 5.0), Vector3(0.1, 0.08, 0.98), 16.0, 3.8, flash_mix, mpal["main"] as Color, alpha, mpal["spark"] as Color)


func _part_canyon_spine_and_cavern(spine3: Vector3, core_pos3: Vector3, chest_open: float, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c_sp: Vector2 = _project_v(spine3)
	# Broad ancient jagged dorsal crag supporting ribcage and shoulders
	_draw_crag_boulder(_body, c_sp, 30.0, 31.0, 0.0, 313, flash_mix, alpha, mpal, {"taper_bottom": 0.38, "gold_trim": true, "cracks": true, "ndl": -0.15})

	# 7 soaring dorsal quartz crystals erupting upward behind shoulders/neck
	for d_i: int in 7:
		var off_s: float = float(d_i - 3) * 8.5
		var d_len: float = 36.0 - absf(float(d_i - 3)) * 5.0
		var d_pos3: Vector3 = spine3 + Vector3(-6.0, off_s, 14.0 - absf(float(d_i - 3)) * 1.5)
		var d_dir: Vector3 = Vector3(-0.36, off_s * 0.018, 0.92).normalized()
		_draw_geode_crystal3d(_body, d_pos3, d_dir, d_len, 4.2 if d_i == 3 else 3.0, flash_mix, mpal["vein"] as Color, alpha)

	# Dark inner geode cavity behind the Astral Prism Heart when facing camera
	if _forward.y > -0.65:
		var cav_c: Vector2 = _project_v(core_pos3 + Vector3(1.0, 0.0, 1.0))
		var cav_w: float = 15.0 + chest_open * 0.48
		var cav_poly: PackedVector2Array = _crag_poly2d(cav_c, cav_w, 20.0, 0.0, 419, 10, 0.25)
		_draw_silhouette_outline(_body, [cav_poly], Color(GD_OUT, alpha))
		_draw_flat_span_poly(_body, cav_poly, Color(QZ_OUT, alpha))
		# Inward crystal geode teeth framing the cavern rim
		for t_i: int in 6:
			var ang: float = float(t_i) / 6.0 * TAU + 0.45
			var tb3: Vector3 = core_pos3 + Vector3(1.5, cos(ang) * (cav_w * 0.85), sin(ang) * 14.0)
			var td3: Vector3 = Vector3(0.15, -cos(ang) * 0.85, -sin(ang) * 0.65)
			_draw_geode_crystal3d(_body, tb3, td3, 9.5, 2.2, flash_mix, mpal["main"] as Color, alpha)


func _part_chest_crag(rib3: Vector3, s_sign: float, side_i: int, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(rib3)
	var is_right: bool = side_i == 1
	var ndl_v: float = 0.25 if not is_right else -0.1
	# Sculpted craggy chest armor block + inner golden rib arch + lower quartz fang
	_draw_crag_boulder(_body, c2, 16.5, 22.0, s_sign * 0.16, 521 + side_i * 43, flash_mix, alpha, mpal, {"taper_bottom": 0.48, "gold_trim": true, "cracks": true, "ndl": ndl_v})
	# Heavy golden temple collar arch across upper clavicle
	var cl3: Vector3 = rib3 + Vector3(2.0, -s_sign * 2.5, 15.5)
	_draw_crag_boulder(_body, _project_v(cl3), 13.0, 7.0, s_sign * 0.22, 577 + side_i * 19, flash_mix, alpha, mpal, {"gold": true, "cracks": false, "ndl": ndl_v})
	# Inner geode crystal horns lining the heart slit
	_draw_geode_crystal3d(_body, rib3 + Vector3(3.0, -s_sign * 7.5, 9.0), Vector3(0.25, -s_sign * 0.55, 0.78), 14.0, 3.2, flash_mix, mpal["spark"] as Color, alpha, mpal["main"] as Color)
	_draw_geode_crystal3d(_body, rib3 + Vector3(1.0, -s_sign * 6.0, -9.0), Vector3(0.15, -s_sign * 0.42, -0.88), 12.0, 2.8, flash_mix, mpal["main"] as Color, alpha)


func _part_shoulder_crag(sh3: Vector3, s_sign: float, side_i: int, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(sh3)
	var ndl_v: float = 0.35 if side_i == 0 else -0.05
	# Massive jagged canyon plateau pauldron
	_draw_crag_boulder(_body, c2, 19.5, 16.5, s_sign * 0.18, 631 + side_i * 59, flash_mix, alpha, mpal, {"taper_bottom": 0.32, "gold_trim": true, "cracks": true, "ndl": ndl_v})
	# Golden ruin ridge crest on top of shoulder
	_draw_crag_boulder(_body, _project_v(sh3 + Vector3(0.0, s_sign * 2.0, 11.0)), 14.5, 6.5, s_sign * 0.18, 683 + side_i * 23, flash_mix, alpha, mpal, {"gold": true, "cracks": false, "ndl": ndl_v})
	# 6 Erupting Sun-Quartz Peaks crowning each shoulder!
	for p_i: int in 6:
		var ang_s: float = 0.18 + float(p_i) * 0.16
		var sp_len: float = 34.0 - float(absi(p_i - 2)) * 4.5
		var sp_w: float = 4.2 if p_i == 2 else 3.0
		var b_off: Vector3 = Vector3((float(p_i % 3) - 1.0) * 5.0, s_sign * (float(p_i) * 2.8 - 2.0), 11.0 - float(p_i) * 1.4)
		var d_vec: Vector3 = Vector3((float(p_i % 3) - 1.0) * 0.18, s_sign * sin(ang_s), cos(ang_s)).normalized()
		_draw_geode_crystal3d(_body, sh3 + b_off, d_vec, sp_len, sp_w, flash_mix, mpal["vein"] as Color if p_i % 2 == 0 else mpal["spark"] as Color, alpha, mpal["main"] as Color if p_i == 2 else Color(0, 0, 0, 0))


func _part_obelisk_head(head_pos3: Vector3, eye_c: Color, main_c: Color, spark_c: Color, flash_mix: float, alpha: float) -> void:
	_draw_archon_obelisk_visage(_body, head_pos3, eye_c, main_c, spark_c, flash_mix, alpha)


func _part_crystal_spire(base3: Vector3, dir3: Vector3, length: float, half_w: float, flash_mix: float, vein_col: Color, alpha: float, core_glow: Color) -> void:
	_draw_geode_crystal3d(_body, base3, dir3, length, half_w, flash_mix, vein_col, alpha, core_glow)


func _part_satellite_shard(sat3: Vector3, idx: int, alpha: float, flash_mix: float, vein_col: Color) -> void:
	var tilt: float = _time * 1.4 + float(idx)
	var dir3: Vector3 = Vector3(cos(tilt) * 0.35, sin(tilt) * 0.45, 0.85).normalized()
	_draw_geode_crystal3d(_body, sat3, dir3, 14.0 + float(idx % 3) * 4.0, 2.8, flash_mix, vein_col, alpha)


func _part_braided_arm_tether(p_sh2: Vector2, p_arm2: Vector2, p_hand2: Vector2, main_c: Color, dark_c: Color, spark_c: Color, side_i: int, alpha: float) -> void:
	_draw_braided_tether(_body, p_sh2, p_arm2, main_c, dark_c, spark_c, float(side_i) * 1.2, alpha)
	_draw_braided_tether(_body, p_arm2, p_hand2 + Vector2(0.0, -6.0), main_c, dark_c, spark_c, float(side_i) * 1.2 + 2.0, alpha)


func _part_forearm_crag(arm3: Vector3, s_sign: float, side_i: int, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(arm3)
	_draw_crag_boulder(_body, c2, 13.0, 14.0, s_sign * 0.25, 743 + side_i * 37, flash_mix, alpha, mpal, {"taper_bottom": 0.4, "gold_trim": true, "cracks": true})
	_draw_geode_crystal3d(_body, arm3 + Vector3(-1.0, s_sign * 6.0, 3.0), Vector3(-0.2, s_sign * 0.72, 0.65), 18.0, 3.4, flash_mix, mpal["main"] as Color, alpha)


func _part_colossus_gauntlet(hand3: Vector3, s_sign: float, side_i: int, mpal: Dictionary, flash_mix: float, alpha: float, blade_amt: float, blade_sweep: float, claw_open: float) -> void:
	_draw_colossus_gauntlet(_body, hand3, s_sign, side_i, mpal, flash_mix, alpha, blade_amt, blade_sweep, claw_open)


func _part_detached_tether(p_sh2: Vector2, det_over: Vector2, main_c: Color, dark_c: Color, spark_c: Color, alpha: float) -> void:
	_draw_braided_tether(_body, p_sh2, det_over + Vector2(0.0, -10.0), main_c, dark_c, spark_c, 0.85, alpha)


func _part_detached_gauntlet(det_over: Vector2, s_sign: float, side_i: int, mpal: Dictionary, flash_mix: float, alpha: float) -> void:
	_draw_detached_gauntlet_screen(_body, det_over, s_sign, side_i, mpal, flash_mix, alpha)


# ==============================================================================
# SPECIALTY SCULPTED PIECES (PRISM HEART, HORNED OBELISK VISAGE, CRAG GAUNTLET)
# ==============================================================================
func _draw_astral_prism_heart(canvas: Node2D, core_pos3: Vector3, mpal: Dictionary, flash_mix: float, alpha: float, scale_k: float) -> void:
	var c: Vector2 = _project_v(core_pos3)
	var main_c: Color = mpal["main"] as Color
	var dark_c: Color = mpal["dark"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var core_c: Color = mpal["core"] as Color

	# Outer tilted golden rune ring framing the open Sun-Prism Heart
	var ring_pts: int = 10
	for r_i: int in ring_pts:
		var a0: float = _time * 1.9 + float(r_i) / float(ring_pts) * TAU
		var a1: float = a0 + 0.36
		var p0: Vector2 = c + Vector2(cos(a0) * 14.5 * scale_k, sin(a0) * 17.5 * scale_k)
		var p1: Vector2 = c + Vector2(cos(a1) * 14.5 * scale_k, sin(a1) * 17.5 * scale_k)
		_draw_pixel_line(canvas, p0, p1, Color(GD_2 if r_i % 2 == 0 else spark_c, alpha * 0.92), 2.0)

	# Spinning 8-point prismatic crystal core
	var spin: float = sin(_time * 2.5) * 0.25
	var rh: float = 16.5 * scale_k
	var rw: float = 10.5 * scale_k * (0.78 + 0.22 * absf(cos(_time * 2.6)))
	var top: Vector2 = (c + Vector2(sin(spin) * 2.5, -rh)).round()
	var bot: Vector2 = (c + Vector2(-sin(spin) * 2.5, rh)).round()
	var lft: Vector2 = (c + Vector2(-rw, cos(spin) * 1.5)).round()
	var rgt: Vector2 = (c + Vector2(rw, -cos(spin) * 1.5)).round()

	var sil: PackedVector2Array = PackedVector2Array([top, rgt, bot, lft])
	_draw_silhouette_outline(canvas, [sil], Color(QZ_OUT, alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([top, c, lft]), Color(QZ_4.lerp(Color.WHITE, flash_mix), alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([top, rgt, c]), Color(main_c.lerp(Color.WHITE, flash_mix), alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([c, rgt, bot]), Color(dark_c.lerp(Color.WHITE, flash_mix), alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([lft, c, bot]), Color(spark_c.lerp(Color.WHITE, flash_mix), alpha))

	# Incandescent star center + crackling lightning arcs to the geode rib walls
	canvas.draw_rect(Rect2(c.round() - Vector2(3, 4), Vector2(6, 8)), Color(core_c, alpha))
	canvas.draw_rect(Rect2(c.round() - Vector2(1, 3), Vector2(3, 6)), Color(Color.WHITE, alpha))
	for arc_i: int in 5:
		var a_ang: float = _time * 4.2 + float(arc_i) * (TAU / 5.0)
		var out_p: Vector2 = c + Vector2(cos(a_ang) * (15.0 + 3.0 * sin(_time * 9.0 + float(arc_i))), sin(a_ang) * 18.0)
		var j_mid: Vector2 = c.lerp(out_p, 0.5) + Vector2(sin(_time * 17.0 + float(arc_i)) * 4.0, cos(_time * 13.0) * 3.0)
		_draw_pixel_line(canvas, c, j_mid, Color(spark_c, alpha * 0.9), 1.0)
		_draw_pixel_line(canvas, j_mid, out_p, Color(main_c, alpha * 0.85), 1.0)


func _draw_archon_obelisk_visage(canvas: Node2D, head_pos3: Vector3, eye_c: Color, main_c: Color, spark_c: Color, flash_mix: float, alpha: float) -> void:
	var hc: Vector2 = _project_v(head_pos3)
	var face_vis: float = _forward.y # > 0 facing viewer (Down), < 0 facing away

	# Rear neck quartz crystal spine anchoring the levitating mask
	_draw_crag_boulder(canvas, _project_v(head_pos3 + Vector3(-5.0, 0.0, -3.0)), 11.0, 12.0, 0.0, 811, flash_mix, alpha, {"main": main_c, "dark": ST_0, "spark": spark_c}, {"taper_bottom": 0.45, "cracks": false, "ndl": -0.2})

	# Main Ancient Tapered Split-Obelisk Mask (~26x34 px, zero rectangle!)
	var w_mul: float = 0.72 + 0.28 * absf(face_vis)
	var mask_poly: PackedVector2Array = PackedVector2Array([
		(hc + Vector2(-8.0 * w_mul, -20.0)).round(),
		(hc + Vector2(0.0, -23.0)).round(),
		(hc + Vector2(8.0 * w_mul, -20.0)).round(),
		(hc + Vector2(12.5 * w_mul, -9.0)).round(),
		(hc + Vector2(9.5 * w_mul, 4.0)).round(),
		(hc + Vector2(4.5 * w_mul, 15.0)).round(), # carved bearded chin spire
		(hc + Vector2(0.0, 20.0)).round(),
		(hc + Vector2(-4.5 * w_mul, 15.0)).round(),
		(hc + Vector2(-9.5 * w_mul, 4.0)).round(),
		(hc + Vector2(-12.5 * w_mul, -9.0)).round(),
	])
	_draw_silhouette_outline(canvas, [mask_poly], Color(ST_OUT, alpha))
	_draw_flat_span_poly(canvas, mask_poly, Color(ST_1.lerp(Color.WHITE, flash_mix), alpha))
	# Lit upper-left face facet
	var lit_half: PackedVector2Array = PackedVector2Array([
		mask_poly[0], mask_poly[1], hc + Vector2(0.0, 20.0), mask_poly[7], mask_poly[8], mask_poly[9],
	])
	_draw_flat_span_poly(canvas, lit_half, Color(ST_3.lerp(Color.WHITE, flash_mix), alpha), Color(ST_4, alpha), true)

	# Deep dark center face fissure + golden ancient ruin brow chevron
	_draw_pixel_line(canvas, hc + Vector2(0.0, -20.0), hc + Vector2(0.0, 17.0), Color(ST_OUT, alpha), 2.0)
	_draw_pixel_line(canvas, hc + Vector2(-10.0 * w_mul, -14.0), hc + Vector2(0.0, -8.0), Color(GD_2, alpha), 2.0)
	_draw_pixel_line(canvas, hc + Vector2(0.0, -8.0), hc + Vector2(10.0 * w_mul, -14.0), Color(GD_1, alpha), 2.0)

	# Sweeping twin curved Archon Brow-Horns (left & right curving skyward into quartz tips!)
	for h_sign: float in [-1.0, 1.0]:
		var hb0: Vector3 = head_pos3 + Vector3(1.0, h_sign * 8.0, 12.0)
		var hd0: Vector3 = Vector3(-0.1, h_sign * 0.65, 0.74).normalized()
		_draw_geode_crystal3d(canvas, hb0, hd0, 18.0, 3.0, flash_mix, spark_c if face_vis > -0.3 else main_c, alpha)

	# 3 Blazing Eyes (2 fierce angled slit eyes + 1 vertical Third Sun-Eye on forehead)
	if face_vis > -0.45:
		var ec: Vector2 = _project_v(head_pos3 + Vector3(9.5, 0.0, 3.0)).round()
		var eye_spread: float = 5.5 * (1.0 - absf(_forward.x) * 0.35)
		var le: Vector2 = ec + Vector2(-eye_spread, -3.0)
		var re: Vector2 = ec + Vector2(eye_spread, -3.0)
		# Dark sunken eye sockets
		_draw_pixel_line(canvas, le + Vector2(-3, -1), le + Vector2(2, 1), Color(ST_OUT, alpha), 3.0)
		_draw_pixel_line(canvas, re + Vector2(-2, 1), re + Vector2(3, -1), Color(ST_OUT, alpha), 3.0)
		# Blazing diagonal diamond eye slits
		_draw_pixel_line(canvas, le + Vector2(-3, -1), le + Vector2(2, 1), Color(eye_c, alpha), 1.0)
		_draw_pixel_line(canvas, re + Vector2(-2, 1), re + Vector2(3, -1), Color(eye_c, alpha), 1.0)
		canvas.draw_rect(Rect2(le, Vector2(2, 2)), Color(Color.WHITE, alpha))
		canvas.draw_rect(Rect2(re, Vector2(2, 2)), Color(Color.WHITE, alpha))
		# Vertical Forehead Sun-Eye
		var te: Vector2 = ec + Vector2(0.0, -11.0)
		canvas.draw_rect(Rect2(te - Vector2(2, 4), Vector2(4, 8)), Color(GD_OUT, alpha))
		canvas.draw_rect(Rect2(te - Vector2(1, 3), Vector2(2, 6)), Color(spark_c, alpha))
		canvas.draw_rect(Rect2(te - Vector2(0, 2), Vector2(1, 4)), Color(Color.WHITE, alpha))
		# Subtle flame wisps rising from forehead sun-eye
		var wy: float = fposmod(_time * 16.0, 7.0)
		canvas.draw_rect(Rect2(te + Vector2(-1, -5 - wy), Vector2(2, 2)), Color(main_c, alpha * (1.0 - wy / 7.0)))


func _draw_colossus_gauntlet(canvas: Node2D, hand3: Vector3, s_sign: float, side_i: int, mpal: Dictionary, flash_mix: float, alpha: float, blade_amt: float, blade_sweep: float, claw_open: float) -> void:
	var c: Vector2 = _project_v(hand3)
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var vein_c: Color = mpal["vein"] as Color

	# Outer 4 colossal jagged quartz knuckle/wrist crystals first (depth layered)
	if blade_amt <= 0.05:
		for k_i: int in 3:
			var k_dir: Vector3 = Vector3(0.25 - float(k_i) * 0.15, s_sign * (0.68 - float(k_i) * 0.12), 0.72).normalized()
			var k_base: Vector3 = hand3 + Vector3(2.0 - float(k_i) * 3.0, s_sign * 9.0, 8.0 + float(k_i) * 2.5)
			_draw_geode_crystal3d(canvas, k_base, k_dir, 20.0 - float(k_i) * 3.5, 3.6, flash_mix, vein_c, alpha, main_c if k_i == 0 else Color(0, 0, 0, 0))
	else:
		# Colossal ~86 px prismatic Sun-Quartz Greatsword extending from gauntlet!
		var p_fist: Vector2 = _project_v(hand3 + Vector3(3.0, 0.0, 4.0))
		var b_ang: float = _heading + blade_sweep * (1.0 if s_sign > 0.0 else -1.0)
		var b_dir3: Vector2 = Vector2.from_angle(b_ang)
		var b_dir2: Vector2 = Vector2(b_dir3.x, b_dir3.y * SQUASH).normalized()
		var b_perp: Vector2 = Vector2(-b_dir2.y, b_dir2.x)
		_draw_crystal_blade2d(canvas, p_fist, b_dir2, b_perp, 86.0 * blade_amt, 8.2 * blade_amt, flash_mix, main_c, spark_c, alpha)

	# Heavy craggy wrist & palm boulder mass (~36x32 px)
	_draw_crag_boulder(canvas, c + Vector2(0.0, -4.0), 17.5, 16.0, s_sign * 0.22, 911 + side_i * 61, flash_mix, alpha, mpal, {"taper_bottom": 0.35, "gold_trim": true, "cracks": true, "ndl": 0.22 if side_i == 0 else -0.05})
	# Glowing golden sun-rune core embedded in knuckle center
	canvas.draw_rect(Rect2(c.round() + Vector2(-4, -8), Vector2(8, 6)), Color(GD_OUT, alpha))
	canvas.draw_rect(Rect2(c.round() + Vector2(-3, -7), Vector2(6, 4)), Color(spark_c, alpha))
	canvas.draw_rect(Rect2(c.round() + Vector2(-1, -6), Vector2(2, 2)), Color(Color.WHITE, alpha))

	# 4 Articulated heavy curved sandstone + quartz talons beneath the palm!
	for f_i: int in 4:
		var spread: float = (float(f_i) - 1.5) * lerpf(5.8, 8.2, claw_open)
		var f3: Vector3 = hand3 + Vector3(4.0, spread * 0.85, -7.0)
		var f_dir3: Vector3 = Vector3(0.28, (float(f_i) - 1.5) * 0.28 * claw_open, -0.92).normalized()
		var talon_len: float = 15.0 if (f_i == 1 or f_i == 2) else 12.0
		_draw_geode_crystal3d(canvas, f3, f_dir3, talon_len, 2.8, flash_mix, main_c if f_i % 2 == 0 else QZ_3, alpha)


func _draw_detached_gauntlet_screen(canvas: Node2D, at_pos: Vector2, s_sign: float, side_i: int, mpal: Dictionary, flash_mix: float, alpha: float) -> void:
	var c: Vector2 = at_pos.round()
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var vein_c: Color = mpal["vein"] as Color
	_oval(canvas, c + Vector2(0.0, 18.0), Vector2(18.0, 7.0), Color(ST_OUT, 0.4 * alpha))
	# Back crystal spurs radiating from flying rocket gauntlet
	for s_i: int in 3:
		var ang: float = -PI * 0.5 + s_sign * (0.45 + float(s_i) * 0.35)
		var sp_dir: Vector2 = Vector2.from_angle(ang)
		var sp_tip: Vector2 = (c + sp_dir * (24.0 - float(s_i) * 4.0)).round()
		var sp_p: Vector2 = Vector2(-sp_dir.y, sp_dir.x)
		var sp_poly: PackedVector2Array = PackedVector2Array([
			(c + sp_p * 3.5).round(), (c - sp_p * 3.5).round(), sp_tip,
		])
		_draw_silhouette_outline(canvas, [sp_poly], Color(QZ_OUT, alpha))
		_draw_flat_span_poly(canvas, sp_poly, Color(QZ_2, alpha), Color(QZ_4, alpha), true)
		_draw_pixel_line(canvas, c, sp_tip, Color(vein_c, alpha), 1.0)
	# Huge craggy flying boulder fist
	_draw_crag_boulder(canvas, c, 18.0, 16.0, s_sign * 0.15, 977 + side_i * 31, flash_mix, alpha, mpal, {"taper_bottom": 0.3, "gold_trim": true, "cracks": true})
	canvas.draw_rect(Rect2(c + Vector2(-4, -4), Vector2(8, 6)), Color(GD_OUT, alpha))
	canvas.draw_rect(Rect2(c + Vector2(-3, -3), Vector2(6, 4)), Color(spark_c, alpha))
	canvas.draw_rect(Rect2(c + Vector2(-1, -2), Vector2(2, 2)), Color(Color.WHITE, alpha))
	# 4 heavy impact claws underneath
	for k: int in 4:
		var fx: float = (float(k) - 1.5) * 6.5
		var claw: PackedVector2Array = PackedVector2Array([
			(c + Vector2(fx - 2.5, 11)).round(), (c + Vector2(fx + 2.5, 11)).round(),
			(c + Vector2(fx + 0.5, 22)).round(), (c + Vector2(fx - 1.5, 22)).round(),
		])
		_draw_silhouette_outline(canvas, [claw], Color(QZ_OUT, alpha))
		_draw_flat_span_poly(canvas, claw, Color(QZ_1 if k % 2 == 0 else ST_2, alpha))
		_draw_pixel_line(canvas, c + Vector2(fx, 12), c + Vector2(fx, 20), Color(main_c, alpha), 1.0)


func _draw_crystal_blade2d(canvas: Node2D, base2: Vector2, dir2: Vector2, perp: Vector2, length: float, half_w: float, flash_mix: float, main_c: Color, spark_c: Color, alpha: float) -> void:
	if length < 6.0:
		return
	# Jagged cross-guard horns
	for g_sign: float in [-1.0, 1.0]:
		var g_dir: Vector2 = (dir2 * 0.25 + perp * g_sign * 0.95).normalized()
		var g_tip: Vector2 = (base2 + g_dir * (length * 0.24)).round()
		var g_b0: Vector2 = (base2 - dir2 * 3.0).round()
		var g_b1: Vector2 = (base2 + dir2 * 6.0).round()
		var gp: PackedVector2Array = PackedVector2Array([g_b0, g_b1, g_tip])
		_draw_silhouette_outline(canvas, [gp], Color(QZ_OUT, alpha))
		_draw_flat_span_poly(canvas, gp, Color(GD_2 if g_sign < 0.0 else GD_1, alpha))

	# Main serrated prismatic blade polygons
	var p_b0: Vector2 = (base2 + perp * (half_w * 0.65)).round()
	var p_b1: Vector2 = (base2 - perp * (half_w * 0.65)).round()
	var p_m0: Vector2 = (base2 + dir2 * (length * 0.35) + perp * (half_w * 1.15)).round()
	var p_m1: Vector2 = (base2 + dir2 * (length * 0.42) - perp * (half_w * 1.05)).round()
	var p_u0: Vector2 = (base2 + dir2 * (length * 0.72) + perp * (half_w * 0.85)).round()
	var p_u1: Vector2 = (base2 + dir2 * (length * 0.76) - perp * (half_w * 0.75)).round()
	var p_tip: Vector2 = (base2 + dir2 * length).round()
	var p_spine: Vector2 = (base2 + dir2 * (length * 0.84)).round()

	var sil: PackedVector2Array = PackedVector2Array([p_b0, p_b1, p_m1, p_u1, p_tip, p_u0, p_m0])
	_draw_silhouette_outline(canvas, [sil], Color(QZ_OUT, alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([p_b0, base2, p_spine, p_tip, p_u0, p_m0]), Color(QZ_3.lerp(Color.WHITE, flash_mix), alpha), Color(QZ_4, alpha), true)
	_draw_flat_span_poly(canvas, PackedVector2Array([base2, p_b1, p_m1, p_u1, p_tip, p_spine]), Color(QZ_1.lerp(Color.WHITE, flash_mix), alpha))
	_draw_pixel_line(canvas, base2 + dir2 * 6.0, base2 + dir2 * (length * 0.94), Color(main_c.lerp(Color.WHITE, 0.35), alpha), 2.0)
	_draw_pixel_line(canvas, base2 + dir2 * 10.0, base2 + dir2 * (length * 0.70), Color(spark_c, alpha), 1.0)


# ==============================================================================
# STAGE 3 SANDSTORM FUNNEL & GIANT 3D CELESTIAL ARMILLARY RINGS
# ==============================================================================
func _add_cyclone_parts(top_z: float, alpha: float, mpal: Dictionary, flash_mix: float) -> void:
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var bands: int = 20
	for b_i: int in bands:
		var frac: float = float(b_i) / float(bands - 1)
		var z_h: float = lerpf(3.0, maxf(24.0, top_z + 6.0), frac)
		var rad: float = lerpf(16.0, 48.0, pow(frac, 0.74)) + sin(_time * 4.5 + float(b_i) * 0.85) * 3.0
		var phase: float = _time * (4.8 + (1.0 - frac) * 2.4) + float(b_i) * 1.15
		for arc_i: int in 2:
			var ang0: float = phase + float(arc_i) * PI
			var ang1: float = ang0 + 2.15
			var mid_ang: float = (ang0 + ang1) * 0.5
			var p_mid3: Vector3 = Vector3(cos(mid_ang) * rad * 0.78, sin(mid_ang) * rad, z_h)
			_add_part(_depth_v(p_mid3), _part_cyclone_ribbon.bind(ang0, ang1, rad, z_h, frac, b_i, alpha, main_c, spark_c))

	for k: int in 10:
		var kf: float = float(k) / 10.0
		var b_z: float = lerpf(8.0, maxf(26.0, top_z), kf)
		var b_r: float = lerpf(18.0, 48.0, kf)
		var b_ang: float = _time * 3.1 + float(k) * (TAU / 10.0)
		var b3: Vector3 = Vector3(cos(b_ang) * b_r * 0.8, sin(b_ang) * b_r, b_z)
		_add_part(_depth_v(b3), _part_cyclone_debris.bind(b3, k, b_ang, flash_mix, alpha, mpal))


func _part_cyclone_ribbon(ang0: float, ang1: float, rad: float, z_h: float, frac: float, b_i: int, alpha: float, main_c: Color, spark_c: Color) -> void:
	var segs: int = 7
	for s: int in segs:
		var t0: float = lerpf(ang0, ang1, float(s) / float(segs))
		var t1: float = lerpf(ang0, ang1, float(s + 1) / float(segs))
		var a3: Vector3 = Vector3(cos(t0) * rad * 0.78, sin(t0) * rad, z_h + float(s) * 0.45)
		var b3: Vector3 = Vector3(cos(t1) * rad * 0.78, sin(t1) * rad, z_h + float(s + 1) * 0.45)
		var a2: Vector2 = _project_v(a3)
		var b2: Vector2 = _project_v(b3)
		var thick_h: float = 5.0 if frac > 0.32 else 3.4
		var lit: bool = a2.x < 0.0 or b2.x < 0.0
		var col: Color = (SD_4 if lit else SD_2).lerp(SD_5, frac * 0.38)
		if s == segs - 1 and b_i % 3 == 0:
			col = spark_c
		elif s == 0:
			col = SD_0
		elif b_i % 4 == 1 and s == 3:
			col = main_c
		col.a *= alpha * (0.90 if (b_i % 2 == 0) else 0.74)
		var poly: PackedVector2Array = PackedVector2Array([
			(a2 + Vector2(0.0, -thick_h * 0.5)).round(),
			(b2 + Vector2(0.0, -thick_h * 0.5)).round(),
			(b2 + Vector2(0.0, thick_h * 0.5)).round(),
			(a2 + Vector2(0.0, thick_h * 0.5)).round(),
		])
		_draw_flat_span_poly(_body, poly, col, Color(SD_5, col.a), lit)
		# Dark sand belly line along lower edge for crisp depth separation
		_draw_pixel_line(_body, a2 + Vector2(0.0, thick_h * 0.5), b2 + Vector2(0.0, thick_h * 0.5), Color(SD_1, col.a * 0.8), 1.0)


func _part_cyclone_debris(b3: Vector3, k: int, b_ang: float, flash_mix: float, alpha: float, mpal: Dictionary) -> void:
	if k % 2 == 0:
		_draw_crag_boulder(_body, _project_v(b3), 5.5, 4.5, b_ang, 1020 + k * 13, flash_mix, alpha, mpal, {"cracks": false})
	else:
		_draw_geode_crystal3d(_body, b3, Vector3(0.2, 0.25, 0.94), 12.0, 2.6, flash_mix, mpal["main"] as Color, alpha)


func _add_armillary_ring_parts(center3: Vector3, radius: float, tilt_x: float, spin: float, alpha: float, mpal: Dictionary, flash_mix: float, secondary: bool) -> void:
	if alpha <= 0.04:
		return
	var segs: int = 20
	var spark_c: Color = mpal["spark"] as Color
	var main_c: Color = mpal["main"] as Color
	var ct: float = cos(tilt_x)
	var st: float = sin(tilt_x)
	for i: int in segs:
		var a0: float = float(i) / float(segs) * TAU + spin
		var a1: float = float(i + 1) / float(segs) * TAU + spin
		var am: float = (a0 + a1) * 0.5
		var p0: Vector3 = center3 + Vector3(cos(a0) * radius * 0.72, sin(a0) * radius * ct, sin(a0) * radius * st)
		var p1: Vector3 = center3 + Vector3(cos(a1) * radius * 0.72, sin(a1) * radius * ct, sin(a1) * radius * st)
		var pm: Vector3 = center3 + Vector3(cos(am) * radius * 0.72, sin(am) * radius * ct, sin(am) * radius * st)
		var is_rune_node: bool = (i % 5 == 0)
		_add_part(_depth_v(pm), _part_armillary_seg.bind(p0, p1, pm, center3, is_rune_node, secondary, alpha, flash_mix, main_c, spark_c))


func _part_armillary_seg(p0: Vector3, p1: Vector3, pm: Vector3, center3: Vector3, is_rune_node: bool, secondary: bool, alpha: float, flash_mix: float, main_c: Color, spark_c: Color) -> void:
	var s0: Vector2 = _project_v(p0)
	var s1: Vector2 = _project_v(p1)
	var perp: Vector2 = (s1 - s0).normalized().orthogonal()
	var hw: float = 2.6 if is_rune_node else 1.8
	var poly: PackedVector2Array = PackedVector2Array([
		(s0 - perp * hw).round(), (s1 - perp * hw).round(),
		(s1 + perp * hw).round(), (s0 + perp * hw).round(),
	])
	_draw_silhouette_outline(_body, [poly], Color(GD_OUT if secondary else ST_OUT, alpha))
	var lit_seg: bool = s0.y < center3.z * -0.5 or s0.x < 0.0
	var col_face: Color = (GD_2 if secondary else ST_3) if lit_seg else (GD_1 if secondary else ST_1)
	_draw_flat_span_poly(_body, poly, Color(col_face.lerp(Color.WHITE, flash_mix), alpha), Color(GD_3, alpha), lit_seg)
	if is_rune_node:
		var sm: Vector2 = _project_v(pm).round()
		_body.draw_rect(Rect2(sm - Vector2(2, 2), Vector2(5, 5)), Color(GD_OUT, alpha))
		_body.draw_rect(Rect2(sm - Vector2.ONE, Vector2(3, 3)), Color(spark_c if secondary else main_c, alpha))
		_body.draw_rect(Rect2(sm, Vector2.ONE), Color(Color.WHITE, alpha))


# ==============================================================================
# MONUMENTAL DORMANT SAND-BURIED RUIN MOUND (~92x68 px)
# ==============================================================================
func _draw_dormant_monument(mpal: Dictionary, flash_mix: float) -> void:
	var ch: float = clampf(soul_charge, 0.0, 1.0)
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var pulse: float = 0.55 + 0.45 * sin(_time * (2.5 + ch * 5.0))
	var vib: Vector2 = Vector2(sin(_time * 28.0) * ch * 0.9, 0.0).round() if ch > 0.35 else Vector2.ZERO

	# Broad layered wind-rippled desert sand dune burying a colossus
	_oval(_body, Vector2(0.0, 2.0), Vector2(52.0, 19.0), Color(ST_OUT, 0.36))
	_oval(_body, Vector2(0.0, -3.0), Vector2(48.0, 16.0), SD_1)
	_oval(_body, Vector2(-2.0, -5.0), Vector2(42.0, 13.0), SD_3)
	_oval(_body, Vector2(-5.0, -7.5), Vector2(32.0, 9.5), SD_4)

	if ch > 0.04:
		var line_c: Color = Color(main_c, ch * (0.68 + 0.32 * pulse))
		for k: int in 8:
			var ang: float = float(k) / 8.0 * TAU + 0.25
			var p_in: Vector2 = Vector2(cos(ang) * 12.0, sin(ang) * 5.0 - 5.0)
			var p_out: Vector2 = Vector2(cos(ang) * (28.0 + ch * 18.0), sin(ang) * (10.0 + ch * 7.0) - 2.0)
			_draw_pixel_line(_body, p_in, p_out, line_c, 2.0)

	# Half-sunk colossal shoulders & giant crooked raw quartz clusters jutting out of the sand
	var l_sh3: Vector3 = Vector3(-4.0, -28.0, 4.0) + Vector3(vib.x, 0, 0)
	var r_sh3: Vector3 = Vector3(5.0, 27.0, 2.0) + Vector3(vib.x, 0, 0)
	_draw_crag_boulder(_body, _project_v(l_sh3), 16.0, 13.0, -0.32, 1111, flash_mix, 1.0, mpal, {"gold_trim": true, "cracks": ch > 0.15})
	_draw_crag_boulder(_body, _project_v(r_sh3), 15.0, 12.0, 0.38, 1117, flash_mix, 1.0, mpal, {"gold_trim": true, "cracks": ch > 0.15})
	_draw_geode_crystal3d(_body, l_sh3 + Vector3(-2.0, -4.0, 8.0), Vector3(-0.25, -0.45, 0.85), 24.0, 4.5, flash_mix, Color(main_c, maxf(0.15, ch)), 1.0)
	_draw_geode_crystal3d(_body, l_sh3 + Vector3(3.0, 2.0, 6.0), Vector3(0.1, -0.25, 0.96), 16.0, 3.0, flash_mix, Color(main_c, maxf(0.15, ch)), 1.0)
	_draw_geode_crystal3d(_body, r_sh3 + Vector3(1.0, 4.0, 7.0), Vector3(0.15, 0.48, 0.86), 22.0, 4.2, flash_mix, Color(main_c, maxf(0.15, ch)), 1.0)

	# Giant buried obelisk head + partial floating crown spires at dune crest
	var h3: Vector3 = Vector3(3.0 + vib.x, 0.0, 16.0 + ch * 5.0)
	_draw_archon_obelisk_visage(_body, h3, Color(main_c, ch), main_c, spark_c, flash_mix, 1.0)
	_draw_geode_crystal3d(_body, h3 + Vector3(-4.0, -14.0, 16.0), Vector3(-0.1, -0.25, 0.96), 19.0, 3.2, flash_mix, Color(spark_c, maxf(0.2, ch)), 1.0)
	_draw_geode_crystal3d(_body, h3 + Vector3(-4.0, 0.0, 19.0), Vector3(-0.08, 0.0, 0.99), 26.0, 4.2, flash_mix, Color(spark_c, maxf(0.2, ch)), 1.0)
	_draw_geode_crystal3d(_body, h3 + Vector3(-4.0, 14.0, 16.0), Vector3(-0.1, 0.25, 0.96), 19.0, 3.2, flash_mix, Color(spark_c, maxf(0.2, ch)), 1.0)

	if ch > 0.25:
		var mote_n: int = roundi(ch * 18.0)
		for m_i: int in mote_n:
			var mph: float = fposmod(_time * 0.65 + float(m_i) * 0.17, 1.0)
			var mang: float = float(m_i) * 2.17 + _time * 0.95
			var mx: float = cos(mang) * lerpf(42.0, 10.0, mph)
			var my: float = sin(mang) * 10.0 - 6.0 - mph * (26.0 + ch * 36.0)
			_body.draw_rect(Rect2(Vector2(mx, my).round(), Vector2(2 if m_i % 3 == 0 else 1, 2)), Color(SD_5 if m_i % 2 == 0 else spark_c, sin(mph * PI) * ch))


func _draw_awakening_debris(main_c: Color, spark_c: Color, ap: float) -> void:
	for i: int in 24:
		var ang: float = float(i) / 24.0 * TAU + ap * 4.5
		var r: float = lerpf(54.0, 18.0, ap) + sin(float(i) * 3.1) * 6.0
		var y_rise: float = -ap * lerpf(14.0, 118.0, fposmod(float(i) * 0.37, 1.0))
		var p: Vector2 = Vector2(cos(ang) * r, sin(ang) * r * SQUASH + y_rise).round()
		var col: Color = spark_c if i % 3 == 0 else (SD_4 if i % 2 == 0 else main_c)
		_body.draw_rect(Rect2(p, Vector2(3, 2) if i % 4 == 0 else Vector2(2, 2)), Color(col, sin(ap * PI) * 0.95))


func _draw_antigrav_motes(canvas: Node2D, main_c: Color, spark_c: Color, alpha: float, max_z: float) -> void:
	var count: int = 28
	for i: int in count:
		var phase: float = fposmod(_time * 0.44 + float(i) * (1.0 / float(count)), 1.0)
		var ang: float = float(i) * 2.399 + _time * (0.85 + storm_ascension * 1.15)
		var r: float = lerpf(44.0, 16.0, phase)
		var z_h: float = lerpf(4.0, max_z, phase)
		var pt: Vector2 = Vector2(cos(ang) * r, sin(ang) * r * SQUASH - z_h).round()
		var ma: float = sin(phase * PI) * alpha * 0.88
		var col: Color = SD_5 if (i % 3 == 0) else (spark_c if i % 3 == 1 else main_c)
		canvas.draw_rect(Rect2(pt, Vector2(2, 2) if i % 5 == 0 else Vector2(2, 1)), Color(col, ma))


# ==============================================================================
# UNSHADED ADDITIVE GLOW PASS (`Glow`)
# ==============================================================================
func _draw_glow() -> void:
	var mpal: Dictionary = _magic_palette()
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var eye_c: Color = mpal["eye"] as Color
	var core_c: Color = mpal["core"] as Color

	if _pose == Pose.DORMANT:
		var ch: float = clampf(soul_charge, 0.0, 1.0)
		if ch > 0.05:
			var g_a: float = ch * (0.13 + 0.07 * sin(_time * 3.5))
			_oval(_glow, Vector2(0.0, -14.0), Vector2(28.0 * ch + 6.0, 14.0 * ch + 4.0), Color(main_c, g_a))
			_oval(_glow, Vector2(0.0, -18.0), Vector2(9.0, 7.0), Color(spark_c, g_a * 1.25))
		return

	var kp: Dictionary = _compute_rig_pose()
	var awaken_t: float = float(kp["awaken_t"])
	var dead_t: float = float(kp["dead_t"])
	var alpha: float = clampf((1.0 - dead_t * 0.95) * clampf(awaken_t * 1.3, 0.0, 1.0), 0.0, 1.0)
	if alpha <= 0.04:
		return

	var beam_charge: float = float(kp["beam_charge"])
	var pulse: float = 0.86 + 0.14 * sin(_time * 4.2)
	var boost: float = 1.0 + beam_charge * 0.5 + prism_release * 0.18 + storm_ascension * 0.25

	# Restrained wide daylight ovals (bright at night via additive NightLight, crisp in day)
	_oval(_glow, Vector2.ZERO, Vector2(44.0, 16.0), Color(main_c, 0.09 * alpha * pulse))
	_oval(_glow, _core_local, Vector2(20.0, 22.0), Color(main_c, 0.14 * alpha * boost))
	_oval(_glow, _core_local, Vector2(10.0, 12.0), Color(core_c, 0.22 * alpha * boost))
	_glow.draw_rect(Rect2(_core_local.round() - Vector2(3, 5), Vector2(6, 10)), Color(Color.WHITE, 0.42 * alpha * boost))

	# 9-shard crown crystal tips
	var head_z: float = float(kp["head_z"])
	var lean: float = float(kp["lean"])
	for c_i: int in 9:
		var c_side: float = CROWN_OFFSETS[c_i] * (0.86 + storm_ascension * 0.16)
		var c_z: float = head_z + 24.0 + CROWN_ARC_Z[c_i] + sin(_time * 2.7 + float(c_i) * 0.65) * 1.8
		var tip2: Vector2 = _project(lean - 2.0, c_side, c_z + CROWN_HEIGHTS[c_i] * 0.72).round()
		_glow.draw_rect(Rect2(tip2 - Vector2(2, 2), Vector2(4, 4)), Color(spark_c if c_i == 4 else main_c, 0.24 * alpha * boost))

	# 3 Glowing eyes
	if _forward.y > -0.45:
		var ec: Vector2 = _project(lean + 14.0, 0.0, head_z + 3.0).round()
		_glow.draw_rect(Rect2(ec + Vector2(-7, -4), Vector2(14, 4)), Color(eye_c, 0.22 * alpha))
		_glow.draw_rect(Rect2(ec + Vector2(-2, -14), Vector2(4, 7)), Color(spark_c, 0.28 * alpha))

	# Gauntlet runes & colossal greatblade plasma edges
	for f2: Vector2 in _fist_local:
		_oval(_glow, f2 + Vector2(0.0, -5.0), Vector2(12.0, 10.0), Color(spark_c, 0.13 * alpha * boost))

	for side_i: int in 2:
		var blade_amt: float = float(kp["blade_l"]) if side_i == 0 else float(kp["blade_r"])
		if blade_amt > 0.08:
			var s_sign: float = -1.0 if side_i == 0 else 1.0
			var b_ang: float = _heading + float(kp["blade_sweep"]) * s_sign
			var b_dir3: Vector2 = Vector2.from_angle(b_ang)
			var b_dir2: Vector2 = Vector2(b_dir3.x, b_dir3.y * SQUASH).normalized()
			var p_f: Vector2 = _fist_local[side_i]
			for s: int in range(6, roundi(84.0 * blade_amt), 6):
				var bp: Vector2 = (p_f + b_dir2 * float(s)).round()
				_glow.draw_rect(Rect2(bp - Vector2(2, 2), Vector2(5, 5)), Color(main_c, 0.16 * blade_amt * alpha))
				_glow.draw_rect(Rect2(bp, Vector2(2, 2)), Color(Color.WHITE, 0.36 * blade_amt * alpha))

	if _pose == Pose.AWAKEN:
		var ap: float = _pose_progress()
		_oval(_glow, Vector2(0.0, -54.0 * ap), Vector2(42.0, 28.0), Color(spark_c, sin(ap * PI) * 0.20))
