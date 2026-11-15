class_name AurelithRig
extends Node2D
## Procedural 3D-projected (`SQUASH = 0.72`), depth-sorted, per-pixel textured rig for
## `Aurelith, Herz des Sonnenquarzes` — a towering ~156 px tall, ~168 px wide
## ancient desert sandstone, gold-ruin & living sun-quartz entity.
##
## v3 Surface & Crystal Architecture:
## - Cached `ImageTexture` pixel-art bakers (`_TEX_CACHE`) with 2D Voronoi rock-block grain,
##   4x4 Bayer dithering, diagonal sedimentary strata, sintered white quartz crusts, and
##   6 distinct carved ancient reliefs (zero identical buttons or flat scanline blobs).
## - 5 distinct quartz crystal morphologies (`CATHEDRAL_HEX`, `CLEAVED_TABLE`, `TWIN_CLUSTER`,
##   `BATTLE_NOTCHED`, `DRUSE_CROWN`) with snowy Voronoi roots, horizontal growth striations,
##   and diagonal turquoise/violet/amber spectral dispersion bands.
## - Pixel-matched `Glow` pass stamping exact rock fissures, carved runes, and crystal inclusions.

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

enum CrystalKind {
	CATHEDRAL_HEX = 0,
	CLEAVED_TABLE = 1,
	TWIN_CLUSTER = 2,
	BATTLE_NOTCHED = 3,
	DRUSE_CROWN = 4,
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
const QZ_CAV0: Color = Color("1d1530")
const QZ_CAV1: Color = Color("2b2044")
const QZ_DEEP: Color = Color("364262")
const QZ_0: Color = Color("5b698e")
const QZ_1: Color = Color("8191b6")
const QZ_2: Color = Color("a2b3d4")
const QZ_3: Color = Color("d6e2f5")
const QZ_4: Color = Color("ffffff")

# Prismatic spectral dispersion tints (subtle sun-refracted bands across crystal facets)
const SPEC_TURQ: Color = Color("6cf0e4")
const SPEC_VIOL: Color = Color("b58cff")
const SPEC_AMBR: Color = Color("ffe08a")

const SD_0: Color = Color("472c38")
const SD_1: Color = Color("6e4934")
const SD_2: Color = Color("9c6c44")
const SD_3: Color = Color("c89658")
const SD_4: Color = Color("e6be78")
const SD_5: Color = Color("f7de9e")

# 4x4 Bayer ordered dithering matrix (0..15)
const BAYER4: Array[int] = [
	0, 8, 2, 10,
	12, 4, 14, 6,
	3, 11, 1, 9,
	15, 7, 13, 5,
]

# Asymmetric 9-Shard Cathedral Sun-Crown around head apex (~156..162 px total height)
const CROWN_OFFSETS: Array[float] = [-35.5, -26.0, -17.5, -8.8, 0.0, 9.2, 18.0, 26.5, 35.0]
const CROWN_HEIGHTS: Array[float] = [12.5, 15.5, 22.5, 27.0, 34.5, 24.5, 21.0, 17.0, 11.5]
const CROWN_WIDTHS: Array[float] = [2.8, 3.2, 3.6, 3.8, 4.8, 3.9, 3.3, 3.4, 2.7]
const CROWN_ARC_Z: Array[float] = [-10.0, -4.5, 2.0, 6.5, 9.5, 6.0, 1.5, -4.0, -10.5]
const CROWN_KINDS: Array[int] = [
	CrystalKind.CLEAVED_TABLE,
	CrystalKind.BATTLE_NOTCHED,
	CrystalKind.TWIN_CLUSTER,
	CrystalKind.BATTLE_NOTCHED,
	CrystalKind.CATHEDRAL_HEX,
	CrystalKind.CLEAVED_TABLE,
	CrystalKind.CATHEDRAL_HEX,
	CrystalKind.DRUSE_CROWN,
	CrystalKind.CLEAVED_TABLE,
]

# 8 Stage-2/3 Crystal Wing-Blades (4 per side, varied morphologies & widths)
const WING_ANGLES: Array[float] = [0.18, 0.52, 0.88, 1.24]
const WING_LENS: Array[float] = [48.0, 66.0, 74.0, 52.0]
const WING_WIDTHS: Array[float] = [5.0, 6.2, 6.6, 4.8]
const WING_KINDS_L: Array[int] = [
	CrystalKind.CLEAVED_TABLE,
	CrystalKind.CATHEDRAL_HEX,
	CrystalKind.TWIN_CLUSTER,
	CrystalKind.BATTLE_NOTCHED,
]
const WING_KINDS_R: Array[int] = [
	CrystalKind.DRUSE_CROWN,
	CrystalKind.BATTLE_NOTCHED,
	CrystalKind.CATHEDRAL_HEX,
	CrystalKind.CLEAVED_TABLE,
]

const SAT_COUNT: int = 12

static var _OVAL_MASKS: Dictionary = {}
static var _TEX_CACHE: Dictionary = {}
static var _CACHE_WARMED: bool = false

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
var _redraw_accum: float = 0.0
var _force_redraw: bool = true
var _last_kp: Dictionary = {}

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
var _glow_stamps: Array[Dictionary] = []

@onready var _body: Node2D = $Body
@onready var _glow: Node2D = $Glow


func _ready() -> void:
	warm_cache()
	_body.draw.connect(_draw_body)
	_glow.draw.connect(_draw_glow)


static func warm_cache() -> void:
	if _CACHE_WARMED:
		return
	_CACHE_WARMED = true
	for sec: int in [-2, -1, 0, 1]:
		_get_head_entry(sec)
	_get_cleaved_head_half_entry(0)
	_get_cleaved_head_half_entry(1)
	_get_dormant_dune_entry()
	_get_geode_cavern_entry()
	_get_greatblade_canon(0)
	_get_greatblade_canon(1)
	for kind_i: int in 5:
		for var_i: int in 4:
			for bucket: int in [18, 32, 64]:
				_get_crystal_canon(kind_i, bucket, var_i, false)
	_get_crystal_canon(CrystalKind.CATHEDRAL_HEX, 32, 0, true)
	_get_crystal_canon(CrystalKind.CATHEDRAL_HEX, 32, 1, true)
	for side_i: int in 2:
		for w_i: int in [1, 2]:
			var wk: int = WING_KINDS_L[w_i] if side_i == 0 else WING_KINDS_R[w_i]
			_get_crystal_canon(wk, 32, side_i * 7 + w_i, true)
			_get_crystal_canon(wk, 64, side_i * 7 + w_i, true)
	# Pre-warm all body Voronoi crag boulders so zero CPU baking ever happens during combat
	_get_crag_entry(21.0, 24.0, 107, 0.62, 0.0, false, 5, true, 0.2)
	_get_crag_entry(8.5, 11.5, 211, 0.45, 0.0, false, 1, true, 0.15)
	_get_crag_entry(7.5, 8.5, 239, 0.0, 0.0, true, -1, false, 0.15)
	_get_crag_entry(8.0, 10.5, 263, 0.4, 0.0, false, 4, true, 0.15)
	_get_crag_entry(30.0, 31.0, 313, 0.38, 0.0, false, 4, true, -0.15)
	_get_crag_entry(11.0, 12.0, 811, 0.45, 0.0, false, -1, false, -0.2)
	for idx_s: int in [3, 7, 11]:
		_get_crag_entry(5.5, 7.0, 770 + idx_s * 13, 0.0, 0.0, false, 1, true, 0.15)
	for side_i: int in 2:
		var ndl_rib: float = 0.25 if side_i == 0 else -0.1
		_get_crag_entry(17.0, 22.5, 521 + side_i * 43, 0.48, 0.0, false, 0 if side_i == 0 else 1, true, ndl_rib)
		_get_crag_entry(13.5, 7.0, 577 + side_i * 19, 0.0, 0.0, true, -1, false, ndl_rib)
		var ndl_sh: float = 0.35 if side_i == 0 else -0.05
		_get_crag_entry(20.0, 17.0, 631 + side_i * 59, 0.32, 0.0, false, 3 if side_i == 0 else 2, true, ndl_sh)
		_get_crag_entry(14.5, 6.5, 683 + side_i * 23, 0.0, 0.0, true, -1, false, ndl_sh)
		_get_crag_entry(13.5, 14.5, 743 + side_i * 37, 0.4, 0.0, false, 1 if side_i == 0 else 4, true, 0.15)
		_get_crag_entry(18.0, 16.5, 911 + side_i * 61, 0.34, 0.0, false, 5 if side_i == 0 else 0, true, 0.22 if side_i == 0 else -0.05)
		_get_crag_entry(11.5, 5.0, 947 + side_i * 29, 0.0, 0.0, true, -1, false, 0.15)
		for f_i: int in 4:
			_get_crag_entry(4.2, 4.5, 1201 + side_i * 19 + f_i * 7, 0.0, 0.0, f_i == 1, -1, false, 0.15)
		_get_crag_entry(18.5, 16.5, 977 + side_i * 31, 0.3, 0.0, false, 2 if side_i == 0 else 4, true, 0.15)
		_get_crag_entry(11.0, 4.8, 991 + side_i * 17, 0.0, 0.0, true, -1, false, 0.15)
		_get_crag_entry(6.0, 5.0, 1020 + side_i * 13, 0.0, 0.0, false, 1, true, 0.15)
		_get_crag_entry(6.5, 4.5, 1060 + side_i * 17, 0.0, 0.0, true, -1, false, 0.15)
	for k_i: int in 4:
		_get_crag_entry(4.0, 4.2, 1300 + k_i * 11, 0.0, 0.0, false, -1, false, 0.15)
	for ch_b: bool in [false, true]:
		_get_crag_entry(16.5, 13.5, 1111, 0.0, 0.0, false, 3, ch_b, 0.15)
		_get_crag_entry(15.5, 12.5, 1117, 0.0, 0.0, false, 2, ch_b, 0.15)


func start_pose(pose: Pose, duration: float = 1.0, elapsed: float = 0.0) -> void:
	_pose = pose
	_pose_duration = maxf(duration, 0.05)
	_pose_time = elapsed
	_force_redraw = true
	queue_redraw_all()


func hit_flash() -> void:
	_flash = 0.14
	_force_redraw = true
	queue_redraw_all()


func set_detached_fist(is_right: bool, active: bool, world_pos: Vector2 = Vector2.ZERO, lift_z: float = 0.0) -> void:
	var idx: int = 1 if is_right else 0
	_detached_fist_active[idx] = active
	_detached_fist_world[idx] = world_pos
	_detached_fist_lift[idx] = lift_z
	_force_redraw = true
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
	var head_delta: float = absf(angle_difference(_heading, heading_rad))
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
	_redraw_accum += delta
	if _force_redraw or _redraw_accum >= 0.016 or head_delta >= 0.025 or _pose == Pose.DEAD:
		_redraw_accum = 0.0
		_force_redraw = false
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


static func _hashf(n: int, salt: int) -> float:
	var h: int = (n * 374761393 + salt * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _bayer(px: int, py: int) -> float:
	var idx: int = (py & 3) * 4 + (px & 3)
	return (float(BAYER4[idx]) / 15.0) - 0.5


static func _put_rgba(buf: PackedByteArray, idx4: int, col: Color) -> void:
	buf[idx4] = clampi(roundi(col.r * 255.0), 0, 255)
	buf[idx4 + 1] = clampi(roundi(col.g * 255.0), 0, 255)
	buf[idx4 + 2] = clampi(roundi(col.b * 255.0), 0, 255)
	buf[idx4 + 3] = clampi(roundi(col.a * 255.0), 0, 255)


static func _make_tex(w: int, h: int, buf: PackedByteArray) -> ImageTexture:
	var img: Image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, buf)
	return ImageTexture.create_from_image(img)


static func _stone_ramp(val: float, is_gold: bool) -> Color:
	if is_gold:
		if val < 0.24:
			return GD_0
		elif val < 0.52:
			return GD_1
		elif val < 0.80:
			return GD_2
		return GD_3
	if val < 0.19:
		return ST_0
	elif val < 0.41:
		return ST_1
	elif val < 0.65:
		return ST_2
	elif val < 0.86:
		return ST_3
	return ST_4


static func _quartz_ramp(val: float) -> Color:
	if val < 0.16:
		return QZ_DEEP
	elif val < 0.34:
		return QZ_0
	elif val < 0.56:
		return QZ_1
	elif val < 0.76:
		return QZ_2
	elif val < 0.91:
		return QZ_3
	return QZ_4


static func _sand_ramp(val: float) -> Color:
	if val < 0.16:
		return SD_0
	elif val < 0.34:
		return SD_1
	elif val < 0.54:
		return SD_2
	elif val < 0.74:
		return SD_3
	elif val < 0.90:
		return SD_4
	return SD_5


static func _point_in_poly(pt: Vector2, poly: PackedVector2Array) -> bool:
	var inside: bool = false
	var n: int = poly.size()
	var j: int = n - 1
	for i: int in n:
		var pi: Vector2 = poly[i]
		var pj: Vector2 = poly[j]
		if ((pi.y > pt.y) != (pj.y > pt.y)) and (pt.x < (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y + 0.00001) + pi.x):
			inside = not inside
		j = i
	return inside


static func _seg_dist(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.0001:
		return pt.distance_to(a)
	var t: float = clampf((pt - a).dot(ab) / l2, 0.0, 1.0)
	return pt.distance_to(a + ab * t)


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
# CACHED PER-PIXEL TEXTURE BAKERS (VORONOI MASONRY, 5 CRYSTAL CUTS, VISAGE)
# ==============================================================================

## Stamps a cached multi-layer pixel-art texture entry onto `canvas` + optional glow queue (supports GPU Transform2D).
func _stamp_entry(canvas: Node2D, entry: Dictionary, center2: Vector2, alpha: float, flash_mix: float, vein_col: Color, spark_col: Color, glow_weight: float = 0.16, rot_rad: float = 0.0, scale_v: Vector2 = Vector2.ONE) -> void:
	if entry.is_empty() or alpha <= 0.03:
		return
	var use_xf: bool = absf(rot_rad) > 0.002 or not scale_v.is_equal_approx(Vector2.ONE)
	var xform: Transform2D = Transform2D.IDENTITY
	var draw_pos: Vector2 = center2.round() + (entry["off"] as Vector2)
	if use_xf:
		xform = Transform2D(rot_rad, scale_v, 0.0, center2.round())
		draw_pos = entry["off"] as Vector2
		canvas.draw_set_transform_matrix(xform)

	var base_tex: Texture2D = entry["base"] as Texture2D
	canvas.draw_texture(base_tex, draw_pos, Color(1.0, 1.0, 1.0, alpha))

	var vein_tex: Texture2D = entry.get("vein", null) as Texture2D
	if vein_tex != null and vein_col.a > 0.03:
		var vc: Color = Color(vein_col.r, vein_col.g, vein_col.b, vein_col.a * alpha)
		canvas.draw_texture(vein_tex, draw_pos, vc)
		if glow_weight > 0.01 and canvas == _body:
			var g_col: Color = Color(vein_col.r, vein_col.g, vein_col.b, vein_col.a * alpha * glow_weight)
			if use_xf:
				_glow_stamps.append({"tex": vein_tex, "pos": draw_pos, "col": g_col, "has_xf": true, "xform": xform})
			else:
				_glow_stamps.append({"tex": vein_tex, "pos": draw_pos, "col": g_col, "has_xf": false})

	var spark_tex: Texture2D = entry.get("spark", null) as Texture2D
	if spark_tex != null and spark_col.a > 0.03:
		var sc: Color = Color(spark_col.r, spark_col.g, spark_col.b, spark_col.a * alpha)
		canvas.draw_texture(spark_tex, draw_pos, sc)
		if glow_weight > 0.01 and canvas == _body:
			var gs_col: Color = Color(spark_col.r, spark_col.g, spark_col.b, spark_col.a * alpha * glow_weight * 1.25)
			if use_xf:
				_glow_stamps.append({"tex": spark_tex, "pos": draw_pos, "col": gs_col, "has_xf": true, "xform": xform})
			else:
				_glow_stamps.append({"tex": spark_tex, "pos": draw_pos, "col": gs_col, "has_xf": false})

	if flash_mix > 0.02:
		var flash_tex: Texture2D = entry.get("flash", null) as Texture2D
		if flash_tex != null:
			canvas.draw_texture(flash_tex, draw_pos, Color(1.0, 1.0, 1.0, flash_mix * alpha * 0.85))

	if use_xf:
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Finalizes 1-px crisp tinted pixel-art outlines and builds ImageTextures for `base`, `vein`, `spark`, `flash`.
static func _finalize_layers(w: int, h: int, mask: PackedByteArray, out_kind: PackedByteArray, base_buf: PackedByteArray, vein_buf: PackedByteArray, spark_buf: PackedByteArray, has_vein: bool, has_spark: bool, off: Vector2) -> Dictionary:
	var flash_buf: PackedByteArray = PackedByteArray()
	flash_buf.resize(w * h * 4)
	for py: int in h:
		for px: int in w:
			var i: int = py * w + px
			var i4: int = i * 4
			if mask[i] != 0:
				flash_buf[i4] = 255
				flash_buf[i4 + 1] = 255
				flash_buf[i4 + 2] = 255
				flash_buf[i4 + 3] = 255
				continue
			var near_k: int = 0
			if px > 0 and mask[i - 1] != 0:
				near_k = maxi(near_k, out_kind[i - 1])
			if px + 1 < w and mask[i + 1] != 0:
				near_k = maxi(near_k, out_kind[i + 1])
			if py > 0 and mask[i - w] != 0:
				near_k = maxi(near_k, out_kind[i - w])
			if py + 1 < h and mask[i + w] != 0:
				near_k = maxi(near_k, out_kind[i + w])
			if near_k > 0:
				var oc: Color = ST_OUT
				if near_k == 2:
					oc = GD_OUT
				elif near_k == 3:
					oc = QZ_OUT
				_put_rgba(base_buf, i4, oc)
				flash_buf[i4] = 255
				flash_buf[i4 + 1] = 255
				flash_buf[i4 + 2] = 255
				flash_buf[i4 + 3] = 160

	return {
		"base": _make_tex(w, h, base_buf),
		"vein": _make_tex(w, h, vein_buf) if has_vein else null,
		"spark": _make_tex(w, h, spark_buf) if has_spark else null,
		"flash": _make_tex(w, h, flash_buf),
		"off": off,
	}


## Bakes a richly textured ancient sandstone / gold-ruin boulder with:
## - Chiseled angular rock silhouette + eroded V-notches
## - 2D Voronoi stone-block masonry & dark fracture joints + 1-px sunlit bevel lips
## - 4x4 Bayer dithering + diagonal sedimentary strata
## - Sintered white sun-quartz mineral crust patches
## - 6 distinct asymmetric ancient reliefs (`relief_id`: 0..5, or -1 for none)
static func _get_crag_entry(rx: float, ry: float, seed_i: int, taper_b: float, taper_t: float, is_gold: bool, relief_id: int, has_cracks: bool, ndl_bias: float) -> Dictionary:
	var rx_i: int = maxi(3, roundi(rx))
	var ry_i: int = maxi(3, roundi(ry))
	var ndl_q: int = clampi(roundi((ndl_bias + 0.5) * 4.0), 0, 4)
	var tb_q: int = roundi(taper_b * 10.0)
	var tt_q: int = roundi(taper_t * 10.0)
	var key: String = "cr_%d_%d_%d_%d_%d_%d_%d_%d_%d" % [
		rx_i, ry_i, seed_i, tb_q, tt_q, 1 if is_gold else 0, relief_id, 1 if has_cracks else 0, ndl_q
	]
	if _TEX_CACHE.has(key):
		return _TEX_CACHE[key] as Dictionary

	# Build chiseled multi-faceted crag polygon in canonical unrotated rock space (GPU Transform2D handles rotation/scale!)
	var verts: int = clampi(maxi(11, (rx_i + ry_i) / 2), 11, 20)
	var poly: PackedVector2Array = PackedVector2Array()
	var notch_a: int = posmod(seed_i * 3 + 2, verts)
	var notch_b: int = posmod(notch_a + verts / 2 + 1, verts)
	for i: int in verts:
		var ang: float = (float(i) / float(verts)) * TAU + (_hashf(seed_i, i * 17 + 3) - 0.5) * (TAU / float(verts) * 0.34)
		var ca: float = cos(ang)
		var sa: float = sin(ang)
		var rad_j: float = 0.82 + _hashf(seed_i, i * 31 + 7) * 0.34
		if i == notch_a or i == notch_b:
			rad_j *= 0.68 # Sharp eroded V-notch bitten into rock silhouette!
		elif i % 3 == 0:
			rad_j *= 1.10
		elif i % 3 == 1:
			rad_j *= 0.90
		var lx: float = ca * float(rx_i) * rad_j
		var ly: float = sa * float(ry_i) * rad_j
		if sa > 0.0 and absf(taper_b) > 0.01:
			lx *= lerpf(1.0, 1.0 - taper_b, sa)
		if sa < 0.0 and absf(taper_t) > 0.01:
			lx *= lerpf(1.0, 1.0 - taper_t, -sa)
		poly.append(Vector2(lx, ly))

	var pad: int = 4
	var half_w: int = maxi(rx_i, ry_i) + pad + 3
	var w: int = half_w * 2 + 1
	var h: int = half_w * 2 + 1
	var cx: int = half_w
	var cy: int = half_w

	# Deterministic Voronoi stone-slab feature seeds in unrotated local rock space
	var cell_step: float = 7.6 if (rx_i + ry_i) >= 24 else 5.8
	var gx_n: int = maxi(2, ceili(float(rx_i * 2 + 8) / cell_step))
	var gy_n: int = maxi(2, ceili(float(ry_i * 2 + 8) / cell_step))
	var v_pts: PackedVector2Array = PackedVector2Array()
	var v_bias: PackedFloat32Array = PackedFloat32Array()
	var v_quartz: PackedByteArray = PackedByteArray()
	for gy: int in range(-gy_n, gy_n + 1):
		for gx: int in range(-gx_n, gx_n + 1):
			var cid: int = (gy + 32) * 67 + (gx + 32)
			var jx: float = (float(gx) + (_hashf(seed_i, cid * 11 + 1) - 0.5) * 0.78) * cell_step
			var jy: float = (float(gy) + (_hashf(seed_i, cid * 19 + 5) - 0.5) * 0.78) * cell_step
			v_pts.append(Vector2(jx, jy))
			v_bias.append((_hashf(seed_i, cid * 29 + 9) - 0.5) * (0.16 if is_gold else 0.25))
			# Upper/outer Voronoi blocks on non-gold sandstone can be encrusted with white sun-quartz!
			var q_roll: float = _hashf(seed_i, cid * 43 + 17)
			var allow_q: bool = (not is_gold) and (rx_i >= 11) and (jy < float(ry_i) * 0.14 or absf(jx) > float(rx_i) * 0.46)
			v_quartz.append(1 if (allow_q and q_roll > 0.80) else 0)
	var v_count: int = v_pts.size()

	# Crack spine line in local rock space so Voronoi joints near this path glow with arcane energy
	var crack_a: Vector2 = Vector2((_hashf(seed_i, 211) - 0.5) * float(rx_i) * 1.1, -float(ry_i) * 0.65)
	var crack_b: Vector2 = Vector2((_hashf(seed_i, 223) - 0.5) * float(rx_i) * 1.1, float(ry_i) * 0.65)
	var strata_ang: float = (_hashf(seed_i, 307) - 0.5) * 0.55
	var st_ca: float = cos(strata_ang)
	var st_sa: float = sin(strata_ang)

	var mask: PackedByteArray = PackedByteArray()
	var out_kind: PackedByteArray = PackedByteArray()
	var base_buf: PackedByteArray = PackedByteArray()
	var vein_buf: PackedByteArray = PackedByteArray()
	var spark_buf: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	out_kind.resize(w * h)
	base_buf.resize(w * h * 4)
	vein_buf.resize(w * h * 4)
	spark_buf.resize(w * h * 4)

	var has_vein: bool = false
	var has_spark: bool = false

	for py: int in h:
		var wy: float = float(py - cy)
		for px: int in w:
			var wx: float = float(px - cx)
			if not _point_in_poly(Vector2(wx, wy), poly):
				continue
			var idx: int = py * w + px
			var idx4: int = idx * 4
			mask[idx] = 1
			out_kind[idx] = 2 if is_gold else 1

			var lx: float = wx
			var ly: float = wy
			var nx: float = wx / maxf(float(rx_i), 1.0)
			var ny: float = wy / maxf(float(ry_i), 1.0)

			# Directional top-left sunlight + spherical rock volume
			var dome_z: float = sqrt(maxf(0.08, 1.0 - clampf(nx * nx * 0.75 + ny * ny * 0.75, 0.0, 0.92)))
			var shade: float = 0.44 + (-nx * 0.36 - ny * 0.38 + dome_z * 0.22) + (float(ndl_q) - 2.0) * 0.08

			# Nearest 2 Voronoi stone slab centers
			var d1: float = 99999.0
			var d2: float = 99999.0
			var c1: int = 0
			var pt_l: Vector2 = Vector2(lx, ly)
			for vi: int in v_count:
				var d: float = pt_l.distance_to(v_pts[vi])
				if d < d1:
					d2 = d1
					d1 = d
					c1 = vi
				elif d < d2:
					d2 = d
			var edge: float = d2 - d1
			var cell_vec: Vector2 = pt_l - v_pts[c1]
			var is_q_patch: bool = (v_quartz[c1] == 1)

			# Apply per-slab normal tilt + sedimentary bedding strata + Bayer dithering
			shade += v_bias[c1]
			var strata_coord: float = lx * st_sa + ly * st_ca
			var strata_wave: float = sin(strata_coord * 1.15 + float(seed_i)) * 0.07
			shade += strata_wave

			# Masonry/fracture joint between Voronoi rock blocks
			var on_joint: bool = edge < (0.68 if is_gold else 0.84)
			if on_joint:
				shade -= (0.24 if is_gold else 0.34)
			elif edge < 1.62 and (cell_vec.x + cell_vec.y) < 0.0:
				shade += 0.14 # Crisp 1-px sunlit bevel lip below/right of rock joint!

			var dither: float = _bayer(px, py) * (0.055 if is_gold else 0.082)
			var final_v: float = clampf(shade + dither, 0.0, 1.0)

			var col: Color
			if is_q_patch:
				out_kind[idx] = 3
				col = _quartz_ramp(clampf(final_v + 0.14, 0.0, 1.0))
				if on_joint:
					col = QZ_0
			else:
				col = _stone_ramp(final_v, is_gold)

			# --- 6 DISTINCT ASYMMETRIC ANCIENT RELIEFS & CARVINGS ---
			if not is_gold and rx_i >= 9 and ry_i >= 8 and relief_id >= 0:
				var r_kind: int = relief_id % 6
				if r_kind == 0:
					# 0: Broken diagonal tarnished-gold temple strap + rivets + glowing slit
					var band_d: float = lx * 0.42 + ly * 0.91 - float(ry_i) * 0.14
					if absf(band_d) <= 2.1 and lx > -float(rx_i) * 0.75 and lx < float(rx_i) * 0.48:
						out_kind[idx] = 2
						if absf(band_d) > 1.45:
							col = GD_OUT
						else:
							col = _stone_ramp(clampf(final_v + 0.10, 0.0, 1.0), true)
							if absf(fmod(lx + 20.0, 5.0) - 2.5) < 0.7 and absf(band_d) < 0.8:
								col = GD_3
						if absf(lx + 1.5) < 1.3 and absf(band_d) < 1.1:
							_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 0.95))
							has_spark = true
				elif r_kind == 1:
					# 1: Sunken carved pharaonic sun-cartouche with glowing hieroglyph strokes
					var cx_r: float = absf(lx - 1.0)
					var cy_r: float = absf(ly + 1.0)
					if cx_r <= 5.2 and cy_r <= 4.2 and (cx_r + cy_r) <= 8.0:
						if cx_r > 4.1 or cy_r > 3.1:
							col = ST_0 if (lx + ly < 0.0) else ST_4
						else:
							col = ST_OUT
							var glyph_bar: bool = (absf(ly + 2.2) < 0.65 and cx_r < 3.0) or (absf(lx - 1.0) < 0.65 and ly > -1.5 and ly < 2.2)
							if glyph_bar:
								_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.95))
								has_vein = true
								if absf(lx - 1.0) < 0.7 and absf(ly + 0.2) < 0.7:
									_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 1.0))
									has_spark = true
				elif r_kind == 2:
					# 2: Cracked mini-geode druse pocket with 3 glinting crystal teeth
					var gd_p: Vector2 = Vector2(lx + float(rx_i) * 0.15, ly + float(ry_i) * 0.08)
					var gd_r: float = gd_p.length() + sin(atan2(gd_p.y, gd_p.x) * 3.0 + float(seed_i)) * 0.8
					if gd_r < 4.8:
						if gd_r > 3.7:
							col = QZ_OUT
						else:
							col = QZ_CAV0 if ((px + py) % 2 == 0) else QZ_DEEP
							if (int(roundf(gd_p.x)) % 2 == 0 and absf(gd_p.y + 1.2) < 1.1) or (absf(gd_p.x - 1.2) < 0.8 and absf(gd_p.y - 1.0) < 0.9):
								col = QZ_4
								_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 0.85))
								has_spark = true
				elif r_kind == 3:
					# 3: Stepped golden temple corner-bracket bolted onto upper-outer edge
					var bx: float = -lx if (seed_i % 2 == 0) else lx
					if bx > float(rx_i) * 0.12 and ly < float(ry_i) * 0.18:
						if (bx > float(rx_i) * 0.42) or (ly < -float(ry_i) * 0.28):
							out_kind[idx] = 2
							col = _stone_ramp(clampf(final_v + 0.12, 0.0, 1.0), true)
							if absf(bx - float(rx_i) * 0.42) < 0.85 or absf(ly + float(ry_i) * 0.28) < 0.85:
								col = GD_0
				elif r_kind == 4:
					# 4: Thick sintered white sun-quartz mineral seam cutting diagonally across rock
					var seam_d: float = absf(lx * 0.76 - ly * 0.65 + 1.5 + sin(ly * 0.5) * 1.4)
					if seam_d < 2.3:
						out_kind[idx] = 3
						col = QZ_4 if seam_d < 0.85 else (QZ_2 if seam_d < 1.6 else QZ_0)
						if seam_d > 1.55 and ((px + py) % 2 == 0):
							_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.9))
							has_vein = true
				elif r_kind == 5:
					# 5: Inlaid curved golden astrolabe arc + degree ticks + star pip
					var arc_c: Vector2 = Vector2(lx - float(rx_i) * 0.25, ly + float(ry_i) * 0.22)
					var arc_r: float = arc_c.length()
					if absf(arc_r - float(mini(rx_i, ry_i)) * 0.58) < 1.15:
						out_kind[idx] = 2
						col = GD_3 if (px + py) % 3 == 0 else GD_2
					elif absf(arc_r - 2.0) < 1.2:
						col = GD_OUT
						if arc_r < 1.1:
							_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 1.0))
							has_spark = true

			# Organic Voronoi-following glowing arcane fractures
			if has_cracks and rx_i >= 7 and ry_i >= 7:
				var c_dist: float = _seg_dist(pt_l, crack_a, crack_b)
				if (on_joint and c_dist < 4.6) or c_dist < 0.72:
					col = ST_OUT
					var intensity: float = 0.95 if c_dist < 2.2 else 0.72
					_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, intensity))
					has_vein = true
					if d1 > 2.2 and edge < 0.45 and c_dist < 2.4 and ((px + py + seed_i) % 5 == 0):
						_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 1.0))
						has_spark = true

			_put_rgba(base_buf, idx4, col)

	var res: Dictionary = _finalize_layers(w, h, mask, out_kind, base_buf, vein_buf, spark_buf, has_vein, has_spark, Vector2(-float(cx), -float(cy)))
	_TEX_CACHE[key] = res
	return res


## Bakes 1 of 5 distinct Sun-Quartz crystal morphologies at quantized length & screen angle:
## - `0 CATHEDRAL_HEX`: Stepped asymmetric 6-sided prism + horizontal striations + inclusion pocket
## - `1 CLEAVED_TABLE`: Diagonally sheared ancient flat hexagonal cleavage table top
## - `2 TWIN_CLUSTER`: Main prism + angled secondary daughter shard from shared snowy druse root
## - `3 BATTLE_NOTCHED`: Slightly curved crystal with 2 sharp V-chips & dark slate mineral root
## - `4 DRUSE_CROWN`: Stout chiseled crystal splitting into uneven double-tipped crest + gold flecks
static func _get_crystal_canon(kind: int, len_bucket: int, variant: int, gold_collar: bool = false) -> Dictionary:
	var buck_i: int = 18 if len_bucket <= 20 else (32 if len_bucket <= 44 else 64)
	var var_i: int = posmod(variant, 4)
	var kind_i: int = posmod(kind, 5)
	var key: String = "xtc_%d_%d_%d_%d" % [kind_i, buck_i, var_i, 1 if gold_collar else 0]
	if _TEX_CACHE.has(key):
		return _TEX_CACHE[key] as Dictionary

	var hw: float = 3.2 if buck_i == 18 else (4.0 if buck_i == 32 else 6.0)
	var flen: float = float(buck_i)
	var axis: Vector2 = Vector2.RIGHT
	var p_lt: Vector2 = Vector2.UP

	# Build bounding box covering base `(-4)` to `tip (flen + 4)` and side sprouts in canonical `angle = 0.0`
	var reach_side: float = hw * (2.75 if kind_i == CrystalKind.TWIN_CLUSTER else 1.75) + 5.0
	var min_x: int = -6
	var max_x: int = ceili(flen + 4.0) + 2
	var min_y: int = floori(-reach_side) - 2
	var max_y: int = ceili(reach_side) + 2
	var w: int = maxi(8, max_x - min_x + 1)
	var h: int = maxi(8, max_y - min_y + 1)
	var ox: int = -min_x
	var oy: int = -min_y

	# Primary crystal silhouette in `(u_along, v_across)` crystal-local space (`v > 0` = lit side)
	var main_poly: PackedVector2Array = PackedVector2Array()
	var twin_poly: PackedVector2Array = PackedVector2Array()
	var table_poly: PackedVector2Array = PackedVector2Array()
	var ridge_shift: float = (0.14 if (var_i % 2 == 0) else -0.08) * hw

	if kind_i == CrystalKind.CATHEDRAL_HEX:
		main_poly = PackedVector2Array([
			Vector2(-1.5, -hw * 0.86),
			Vector2(flen * 0.18, -hw * 1.08),
			Vector2(flen * 0.66, -hw * 0.96),
			Vector2(flen * 0.84, -hw * 0.46),
			Vector2(flen, hw * 0.08),
			Vector2(flen * 0.78, hw * 0.72),
			Vector2(flen * 0.42, hw * 1.12),
			Vector2(-1.5, hw * 0.84),
		])
	elif kind_i == CrystalKind.CLEAVED_TABLE:
		# Bold diagonally sheared ancient flat hexagonal top-face (unmistakably truncated!)
		var cl_lo: float = flen * (0.58 if var_i < 2 else 0.64)
		var cl_hi: float = flen * 0.92
		var dir_cl: float = 1.0 if (var_i % 2 == 0) else -1.0
		var u_lt: float = cl_hi if dir_cl > 0.0 else cl_lo
		var u_rt: float = cl_lo if dir_cl > 0.0 else cl_hi
		main_poly = PackedVector2Array([
			Vector2(-1.5, -hw * 0.94),
			Vector2(flen * 0.28, -hw * 1.14),
			Vector2(u_rt * 0.86, -hw * 1.02),
			Vector2(u_rt, -hw * 0.68),
			Vector2((u_lt + u_rt) * 0.5 + 1.6, 0.0),
			Vector2(u_lt, hw * 0.72),
			Vector2(u_lt * 0.84, hw * 1.08),
			Vector2(flen * 0.22, hw * 1.12),
			Vector2(-1.5, hw * 0.88),
		])
		table_poly = PackedVector2Array([
			Vector2(u_rt - 3.0, -hw * 0.64),
			Vector2(u_rt, -hw * 0.68),
			Vector2((u_lt + u_rt) * 0.5 + 1.6, 0.0),
			Vector2(u_lt, hw * 0.72),
			Vector2(u_lt - 3.2, hw * 0.52),
			Vector2((u_lt + u_rt) * 0.5 - 2.6, -0.05),
		])
	elif kind_i == CrystalKind.TWIN_CLUSTER:
		main_poly = PackedVector2Array([
			Vector2(-1.5, -hw * 0.82),
			Vector2(flen * 0.55, -hw * 0.98),
			Vector2(flen * 0.82, -hw * 0.45),
			Vector2(flen, 0.05 * hw),
			Vector2(flen * 0.76, hw * 0.68),
			Vector2(flen * 0.38, hw * 0.98),
			Vector2(-1.5, hw * 0.88),
		])
		var s_side: float = 1.0 if (var_i % 2 == 0) else -1.0
		twin_poly = PackedVector2Array([
			Vector2(flen * 0.05, s_side * hw * 0.30),
			Vector2(flen * 0.26, s_side * hw * 1.75),
			Vector2(flen * 0.58, s_side * hw * 2.50),
			Vector2(flen * 0.52, s_side * hw * 1.45),
			Vector2(flen * 0.34, s_side * hw * 0.40),
		])
	elif kind_i == CrystalKind.BATTLE_NOTCHED:
		# Swept curved crystal horn with 2 deep battle-chips bitten out of its edges!
		var bend: float = hw * (0.65 if var_i < 2 else -0.58)
		main_poly = PackedVector2Array([
			Vector2(-1.5, -hw * 0.88),
			Vector2(flen * 0.24, -hw * 1.08),
			Vector2(flen * 0.35, -hw * 0.34), # Deep V-chip #1!
			Vector2(flen * 0.46, -hw * 1.00 + bend * 0.25),
			Vector2(flen * 0.76, -hw * 0.58 + bend * 0.62),
			Vector2(flen, bend),
			Vector2(flen * 0.72, hw * 0.76 + bend * 0.65),
			Vector2(flen * 0.60, hw * 0.22 + bend * 0.42), # Deep V-chip #2!
			Vector2(flen * 0.50, hw * 1.08 + bend * 0.30),
			Vector2(flen * 0.18, hw * 1.02),
			Vector2(-1.5, hw * 0.82),
		])
	else:
		# DRUSE_CROWN: Broad chunky multi-stepped crystal splitting into two distinct uneven peaks!
		main_poly = PackedVector2Array([
			Vector2(-1.5, -hw * 1.08),
			Vector2(flen * 0.36, -hw * 1.34),
			Vector2(flen * 0.68, -hw * 1.18),
			Vector2(flen * 0.76, -hw * 0.62), # Secondary shorter peak!
			Vector2(flen * 0.52, -hw * 0.08), # Deep saddle cleft between twin peaks!
			Vector2(flen, hw * 0.42), # Tall primary peak!
			Vector2(flen * 0.74, hw * 1.24),
			Vector2(flen * 0.28, hw * 1.30),
			Vector2(-1.5, hw * 1.04),
		])

	var hue_phase: float = float(var_i) * 1.57 + float(kind_i) * 0.95
	var mask: PackedByteArray = PackedByteArray()
	var out_kind: PackedByteArray = PackedByteArray()
	var base_buf: PackedByteArray = PackedByteArray()
	var vein_buf: PackedByteArray = PackedByteArray()
	var spark_buf: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	out_kind.resize(w * h)
	base_buf.resize(w * h * 4)
	vein_buf.resize(w * h * 4)
	spark_buf.resize(w * h * 4)
	var has_vein: bool = false
	var has_spark: bool = false

	for py: int in h:
		var sy: float = float(py - oy)
		for px: int in w:
			var sx: float = float(px - ox)
			var pt_s: Vector2 = Vector2(sx, sy)
			var u: float = pt_s.dot(axis)
			var v_lt: float = pt_s.dot(p_lt)
			var uv: Vector2 = Vector2(u, v_lt)

			var in_main: bool = _point_in_poly(uv, main_poly)
			var in_twin: bool = (not twin_poly.is_empty()) and _point_in_poly(uv, twin_poly)
			if not in_main and not in_twin:
				continue

			var idx: int = py * w + px
			var idx4: int = idx * 4
			mask[idx] = 1
			out_kind[idx] = 3

			var t_len: float = clampf(u / maxf(flen, 1.0), 0.0, 1.0)
			var dither: float = _bayer(px, py) * 0.075

			# Optional ornate golden temple collar clamp around base of giant wing crystals
			if gold_collar and u >= 1.5 and u <= 6.5 and in_main:
				out_kind[idx] = 2
				var g_val: float = 0.56 + (v_lt / maxf(hw, 1.0)) * 0.28 + dither
				var g_col: Color = _stone_ramp(clampf(g_val, 0.0, 1.0), true)
				if absf(u - 1.8) < 0.7 or absf(u - 6.2) < 0.7:
					g_col = GD_0
				_put_rgba(base_buf, idx4, g_col)
				continue

			var q_val: float = 0.52
			if in_twin and not in_main:
				# Daughter crystal facet lighting
				var twin_mid: float = (hw * 1.25) if (var_i % 2 == 0) else (-hw * 1.25)
				q_val = 0.72 if (v_lt > twin_mid) else 0.36
			else:
				# 3-plane hexagonal crystal facet shading (`v_lt > ridge` = bright lit plane, middle = prism plane, `< -0.35*hw` = deep cool shadow plane)
				var r_line: float = ridge_shift + (hw * 0.18 if kind_i == CrystalKind.BATTLE_NOTCHED and t_len > 0.5 else 0.0)
				if v_lt > r_line + hw * 0.12:
					q_val = 0.84 + (1.0 - t_len) * 0.06
				elif v_lt > -hw * 0.36:
					q_val = 0.58 + t_len * 0.08
				else:
					q_val = 0.24 + t_len * 0.06

				# Cleaved hexagonal top-table catches crisp overhead desert sunlight!
				if not table_poly.is_empty() and _point_in_poly(uv, table_poly):
					q_val = 0.90

			# Basal root crusts: snowy white Voronoi druse (`kind 0,1,2`) vs smoky slate (`kind 3`) vs gold-flecked (`kind 4`)
			var root_noise: float = sin(u * 1.3 + v_lt * 1.7 + float(var_i) * 2.1) * 0.5 + 0.5
			if t_len < 0.22 + root_noise * 0.08:
				if kind_i == CrystalKind.BATTLE_NOTCHED:
					q_val = minf(q_val, 0.20 + t_len * 1.1) # Dark smoky slate root!
				elif kind_i == CrystalKind.DRUSE_CROWN and root_noise > 0.68 and t_len < 0.14:
					out_kind[idx] = 2
					_put_rgba(base_buf, idx4, GD_2 if v_lt > 0.0 else GD_1)
					continue
				else:
					q_val = maxf(q_val, 0.82 if root_noise > 0.38 else 0.66) # Snowy white quartz root!

			# Horizontal crystal growth striations & bright longitudinal facet ridge glints
			if flen >= 16.0 and int(floorf(u)) % 6 == 0 and v_lt > -hw * 0.1:
				q_val += 0.14
			if absf(v_lt - ridge_shift) < 0.68 and t_len > 0.12 and t_len < 0.90:
				q_val = 0.98

			var base_c: Color = _quartz_ramp(clampf(q_val + dither, 0.0, 1.0))

			# 4 Distinct Mineral Quartz Tint Families (`var_i` 0..3) so neighboring crystals differ in mineral hue!
			if q_val < 0.94:
				if var_i == 1:
					# Warm Sun-Citrine golden-ivory quartz
					base_c = base_c.lerp(Color("ffe294"), 0.28 * (1.0 - t_len * 0.45))
				elif var_i == 2:
					# Smoky Amethyst-Rooted phantom quartz
					base_c = base_c.lerp(Color("7c62b8"), clampf((0.68 - t_len) * 0.52, 0.08, 0.38))
				elif var_i == 3:
					# Singing Oasis Aqua-Refracted quartz
					base_c = base_c.lerp(Color("7af2e6"), 0.25)

			# Subtle diagonal prismatic spectral dispersion bands (matching art_desert_ruins.py!)
			if t_len > 0.20 and t_len < 0.88 and q_val > 0.35 and q_val < 0.93:
				var disp: float = sin(u * 0.38 + v_lt * 0.62 + hue_phase)
				if disp > 0.42:
					base_c = base_c.lerp(SPEC_TURQ, 0.22)
				elif disp < -0.45:
					base_c = base_c.lerp(SPEC_VIOL, 0.22)
				elif absf(disp) < 0.16 and ((px + py) % 2 == 0):
					base_c = base_c.lerp(SPEC_AMBR, 0.18)

			_put_rgba(base_buf, idx4, base_c)

			# Distinct per-morphology internal magic inclusions (NOT a uniform center line!)
			if kind_i == CrystalKind.CATHEDRAL_HEX:
				# Branching basal filament + glowing diamond inclusion pocket at 46% height
				var pocket_d: float = absf(u - flen * 0.46) * 0.55 + absf(v_lt - ridge_shift * 0.5)
				if pocket_d < 1.8:
					_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 0.95))
					has_spark = true
				elif t_len < 0.52 and absf(v_lt - sin(u * 0.45) * 1.1) < 0.72:
					_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.88))
					has_vein = true
			elif kind_i == CrystalKind.CLEAVED_TABLE:
				# Sub-table glowing cleavage rim + basal spark
				if t_len > 0.64 and t_len < 0.76 and absf(v_lt) < hw * 0.55 and ((px + py) % 2 == 0):
					_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.90))
					has_vein = true
				elif t_len > 0.14 and t_len < 0.26 and absf(v_lt) < 1.1:
					_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 0.90))
					has_spark = true
			elif kind_i == CrystalKind.TWIN_CLUSTER:
				# Shared glowing nexus at fork between mother & daughter crystal!
				var fork_p: Vector2 = Vector2(flen * 0.22, (hw * 0.55) if (var_i % 2 == 0) else (-hw * 0.55))
				var fd: float = uv.distance_to(fork_p)
				if fd < 2.2:
					_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 0.95))
					has_spark = true
				elif fd < 4.5 and absf(v_lt - fork_p.y * 0.5) < 0.85:
					_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.85))
					has_vein = true
			elif kind_i == CrystalKind.BATTLE_NOTCHED:
				# Arcane energy leaking right out of the chipped V-notch scar!
				var scar_d: float = uv.distance_to(Vector2(flen * 0.36, -hw * 0.42))
				if scar_d < 2.4:
					_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.95))
					has_vein = true
					if scar_d < 1.3:
						_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 1.0))
						has_spark = true
			else:
				# DRUSE_CROWN: Twin glowing core seeds under the double peaks
				var s1: float = uv.distance_to(Vector2(flen * 0.56, hw * 0.22))
				var s2: float = uv.distance_to(Vector2(flen * 0.50, -hw * 0.38))
				if s1 < 1.6 or s2 < 1.4:
					_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.92))
					has_vein = true
					if s1 < 0.95:
						_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 0.95))
						has_spark = true

	var res: Dictionary = _finalize_layers(w, h, mask, out_kind, base_buf, vein_buf, spark_buf, has_vein, has_spark, Vector2(-float(ox), -float(oy)))
	_TEX_CACHE[key] = res
	return res


## Bakes the bespoke Ancient Split-Obelisk Pharaonic Head (`front/side` vs `back` cranium relief):
## - Voronoi weathered sandstone plates, quartz temple crust, jagged central canyon fissure
## - Stepped tarnished-gold nemes brow-crest & segmented pharaonic beard-spire
## - Back view: 3 golden spine-clamps & sunken glowing Solar Disk relief (never a blank kite!)
static func _get_head_entry(face_sector: int) -> Dictionary:
	# face_sector: -2 (rear), -1 (left profile), 0 (front), +1 (right profile)
	var key: String = "hd_v3_%d" % face_sector
	if _TEX_CACHE.has(key):
		return _TEX_CACHE[key] as Dictionary

	var w: int = 39
	var h: int = 51
	var cx: int = 19
	var cy: int = 25
	var is_rear: bool = (face_sector == -2)
	var w_mul: float = 0.80 if absi(face_sector) == 1 else 1.0
	var side_shift: float = float(face_sector) * 2.2 if absi(face_sector) == 1 else 0.0

	var poly: PackedVector2Array = PackedVector2Array([
		Vector2(-9.0 * w_mul, -21.0),
		Vector2(-2.0 * w_mul, -23.5),
		Vector2(2.0 * w_mul, -23.0),
		Vector2(9.0 * w_mul, -20.5),
		Vector2(13.5 * w_mul, -9.5),
		Vector2(12.0 * w_mul, -2.0),
		Vector2(10.0 * w_mul, 5.0),
		Vector2(5.2 * w_mul, 15.5),
		Vector2(1.5 * w_mul, 21.5),
		Vector2(-1.5 * w_mul, 21.5),
		Vector2(-5.2 * w_mul, 15.5),
		Vector2(-10.0 * w_mul, 5.0),
		Vector2(-12.5 * w_mul, -3.5),
		Vector2(-13.5 * w_mul, -9.5),
	])

	# Monumental chiseled Voronoi stone slabs across the ancient obelisk mask (clean ~8.5 px clusters)
	var v_pts: PackedVector2Array = PackedVector2Array()
	var v_bias: PackedFloat32Array = PackedFloat32Array()
	for gy: int in range(-4, 5):
		for gx: int in range(-2, 3):
			var cid: int = (gy + 10) * 31 + (gx + 10)
			v_pts.append(Vector2(float(gx) * 8.4 + (_hashf(881, cid) - 0.5) * 4.5, float(gy) * 8.2 + (_hashf(887, cid + 7) - 0.5) * 4.5))
			v_bias.append((_hashf(883, cid * 13) - 0.5) * 0.16)

	var mask: PackedByteArray = PackedByteArray()
	var out_kind: PackedByteArray = PackedByteArray()
	var base_buf: PackedByteArray = PackedByteArray()
	var vein_buf: PackedByteArray = PackedByteArray()
	var spark_buf: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	out_kind.resize(w * h)
	base_buf.resize(w * h * 4)
	vein_buf.resize(w * h * 4)
	spark_buf.resize(w * h * 4)
	var has_vein: bool = false
	var has_spark: bool = false

	for py: int in h:
		var ly: float = float(py - cy)
		for px: int in w:
			var lx: float = float(px - cx)
			if not _point_in_poly(Vector2(lx, ly), poly):
				continue
			# Battle chip bitten out of right cheek edge!
			if not is_rear and ly > -6.0 and ly < -2.0 and lx > 9.5 * w_mul:
				continue

			var idx: int = py * w + px
			var idx4: int = idx * 4
			mask[idx] = 1
			out_kind[idx] = 1

			var pt: Vector2 = Vector2(lx, ly)
			var d1: float = 9999.0
			var d2: float = 9999.0
			var c1: int = 0
			for vi: int in v_pts.size():
				var d: float = pt.distance_to(v_pts[vi])
				if d < d1:
					d2 = d1
					d1 = d
					c1 = vi
				elif d < d2:
					d2 = d
			var edge: float = d2 - d1
			var shade: float = 0.56 - (lx / 14.0) * 0.34 - (ly / 24.0) * 0.20 + v_bias[c1]
			if edge < 0.68:
				shade -= 0.22
			var dither: float = _bayer(px, py) * 0.072
			var col: Color = _stone_ramp(clampf(shade + dither, 0.0, 1.0), false)

			# Upper-left temple sintered sun-quartz crust patch!
			if lx < -4.5 * w_mul and ly < -11.0:
				out_kind[idx] = 3
				col = _quartz_ramp(clampf(shade + 0.26 + dither, 0.0, 1.0))

			var fx: float = lx - side_shift
			if is_rear:
				# Sculpted Rear Cranium: 3 heavy golden spine-clamps + sunken glowing Solar Disk!
				if (absf(ly + 14.0) < 1.6 or absf(ly + 5.0) < 1.6 or absf(ly - 5.0) < 1.6) and absf(lx) < 8.5:
					out_kind[idx] = 2
					col = _stone_ramp(clampf(shade + 0.12 + dither, 0.0, 1.0), true)
				var disk_r: float = Vector2(lx, ly + 4.5).length()
				if absf(disk_r - 5.2) < 1.1:
					col = ST_OUT
					_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.85))
					has_vein = true
				elif disk_r < 2.2:
					col = GD_OUT
					_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 0.9))
					has_spark = true
			else:
				# Bold Tarnished-Gold Pharaonic Brow-Nemes Crest + Segmented Beard Spire!
				var chevron_y: float = -13.8 + absf(fx) * 0.42
				if absf(ly - chevron_y) < 2.2:
					out_kind[idx] = 2
					col = GD_0 if (ly - chevron_y) > 1.2 else (GD_3 if fx < 0.0 else GD_2)
				elif ly >= 11.5 and absf(fx) < 4.5:
					out_kind[idx] = 2
					var seg_band: int = int(floorf((ly - 11.5) / 2.5))
					col = GD_0 if (seg_band % 2 == 1) else _stone_ramp(clampf(shade + 0.16, 0.0, 1.0), true)
				elif absf(ly - 3.2) < 1.0 and absf(fx) > 4.6 and absf(fx) < 9.5 * w_mul:
					out_kind[idx] = 2
					col = GD_2 if fx < 0.0 else GD_1

				# Jagged eroded central canyon split down the obelisk visage (clean 1-2 px fissure)
				var canyon_x: float = 0.55 if int(floorf((ly + 24.0) / 5.0)) % 2 == 0 else -0.45
				if absf(fx - canyon_x) < 0.85 and ly > -19.5 and ly < 17.5:
					col = ST_OUT
					if absf(fx - canyon_x) < 0.55 and ((py % 3) != 0):
						_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.72))
						has_vein = true

				# Gold-bezeled Forehead Sun-Cartouche Socket (around 3rd eye at fx=0, ly=-11.5)
				var third_dx: float = absf(fx)
				var third_dy: float = absf(ly + 11.5)
				if third_dx <= 2.7 and third_dy <= 4.8 and (third_dx + third_dy * 0.6) <= 4.7:
					out_kind[idx] = 2
					if third_dx > 1.4 or third_dy > 3.4:
						col = GD_3 if (fx + ly < -11.0) else GD_0
					else:
						col = GD_OUT
						_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 1.0))
						has_spark = true

				# Heavy overhanging brow shadow + deep chiseled dark eye-troughs so 3 eyes pierce cleanly!
				var eye_spread: float = 5.4 * w_mul
				for e_sign: float in [-1.0, 1.0]:
					var ex: float = fx - e_sign * eye_spread
					var ey: float = ly + 3.2 - e_sign * ex * 0.25
					if absf(ex) <= 3.8 and ey >= -2.4 and ey <= 2.1:
						col = ST_OUT if absf(ey) <= 1.6 else ST_0

			_put_rgba(base_buf, idx4, col)

	var res: Dictionary = _finalize_layers(w, h, mask, out_kind, base_buf, vein_buf, spark_buf, has_vein, has_spark, Vector2(-float(cx), -float(cy)))
	_TEX_CACHE[key] = res
	return res


## Bakes the Left (`0`) or Right (`1`) shattered half of Aurelith's Split-Obelisk Visage for the 4-beat Death Supernova!
static func _get_cleaved_head_half_entry(side_i: int) -> Dictionary:
	var key: String = "hd_cleaved_%d" % side_i
	if _TEX_CACHE.has(key):
		return _TEX_CACHE[key] as Dictionary

	var w: int = 39
	var h: int = 51
	var cx: int = 19
	var cy: int = 25
	var poly: PackedVector2Array = PackedVector2Array([
		Vector2(-9.0, -21.0),
		Vector2(-2.0, -23.5),
		Vector2(2.0, -23.0),
		Vector2(9.0, -20.5),
		Vector2(13.5, -9.5),
		Vector2(12.0, -2.0),
		Vector2(10.0, 5.0),
		Vector2(5.2, 15.5),
		Vector2(1.5, 21.5),
		Vector2(-1.5, 21.5),
		Vector2(-5.2, 15.5),
		Vector2(-10.0, 5.0),
		Vector2(-12.5, -3.5),
		Vector2(-13.5, -9.5),
	])
	var v_pts: PackedVector2Array = PackedVector2Array()
	var v_bias: PackedFloat32Array = PackedFloat32Array()
	for gy: int in range(-4, 5):
		for gx: int in range(-2, 3):
			var cid: int = (gy + 10) * 31 + (gx + 10)
			v_pts.append(Vector2(float(gx) * 8.4 + (_hashf(881, cid) - 0.5) * 4.5, float(gy) * 8.2 + (_hashf(887, cid + 7) - 0.5) * 4.5))
			v_bias.append((_hashf(883, cid * 13) - 0.5) * 0.16)

	var mask: PackedByteArray = PackedByteArray()
	var out_kind: PackedByteArray = PackedByteArray()
	var base_buf: PackedByteArray = PackedByteArray()
	var vein_buf: PackedByteArray = PackedByteArray()
	var spark_buf: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	out_kind.resize(w * h)
	base_buf.resize(w * h * 4)
	vein_buf.resize(w * h * 4)
	spark_buf.resize(w * h * 4)
	var has_vein: bool = false
	var has_spark: bool = false

	for py: int in h:
		var ly: float = float(py - cy)
		var canyon_x: float = (0.75 if int(floorf((ly + 24.0) / 4.0)) % 2 == 0 else -0.65) + sin(ly * 0.35) * 0.8
		for px: int in w:
			var lx: float = float(px - cx)
			if side_i == 0 and lx > canyon_x - 0.35:
				continue
			if side_i == 1 and lx < canyon_x + 0.35:
				continue
			if not _point_in_poly(Vector2(lx, ly), poly):
				continue
			if ly > -6.0 and ly < -2.0 and lx > 9.5:
				continue
			var idx: int = py * w + px
			var idx4: int = idx * 4
			mask[idx] = 1
			out_kind[idx] = 1

			var pt: Vector2 = Vector2(lx, ly)
			var d1: float = 9999.0
			var d2: float = 9999.0
			var c1: int = 0
			for vi: int in v_pts.size():
				var d: float = pt.distance_to(v_pts[vi])
				if d < d1:
					d2 = d1
					d1 = d
					c1 = vi
				elif d < d2:
					d2 = d
			var shade: float = 0.56 - (lx / 14.0) * 0.34 - (ly / 24.0) * 0.20 + v_bias[c1]
			if (d2 - d1) < 0.68:
				shade -= 0.22
			var dither: float = _bayer(px, py) * 0.072
			var col: Color = _stone_ramp(clampf(shade + dither, 0.0, 1.0), false)
			if lx < -4.5 and ly < -11.0:
				out_kind[idx] = 3
				col = _quartz_ramp(clampf(shade + 0.26 + dither, 0.0, 1.0))

			var chevron_y: float = -13.8 + absf(lx) * 0.42
			if absf(ly - chevron_y) < 2.2:
				out_kind[idx] = 2
				col = GD_0 if (ly - chevron_y) > 1.2 else (GD_3 if lx < 0.0 else GD_2)
			elif ly >= 11.5 and absf(lx) < 4.5:
				out_kind[idx] = 2
				var seg_band: int = int(floorf((ly - 11.5) / 2.5))
				col = GD_0 if (seg_band % 2 == 1) else _stone_ramp(clampf(shade + 0.16, 0.0, 1.0), true)

			var e_sign: float = -1.0 if side_i == 0 else 1.0
			var ex: float = lx - e_sign * 5.4
			var ey: float = ly + 3.2 - e_sign * ex * 0.25
			if absf(ex) <= 3.8 and ey >= -2.4 and ey <= 2.1:
				col = ST_OUT if absf(ey) <= 1.6 else ST_0

			# Incandescent freshly-cleaved inner sun-quartz fracture face!
			var cleave_d: float = absf(lx - canyon_x)
			if cleave_d < 2.1:
				out_kind[idx] = 3
				col = QZ_4 if cleave_d < 1.1 else QZ_2
				_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.95))
				has_vein = true
				if cleave_d < 1.15 and ((py + side_i) % 3 == 0):
					_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 1.0))
					has_spark = true

			_put_rgba(base_buf, idx4, col)

	var pivot_x: float = 13.0 if side_i == 0 else 25.0
	var res: Dictionary = _finalize_layers(w, h, mask, out_kind, base_buf, vein_buf, spark_buf, has_vein, has_spark, Vector2(-pivot_x, -float(cy)))
	_TEX_CACHE[key] = res
	return res


## Bakes a serrated, multi-faceted ~86 px Ancient Sun-Quartz Relic Greatsword in canonical `angle = 0.0`:
## - Stepped golden pharaonic crossguard & pommel collar
## - Voronoi fracture veins, 2 battle-chipped spine notches, spectral dispersion, and fuller runes
static func _get_greatblade_canon(side_i: int) -> Dictionary:
	var key: String = "gbc_%d" % side_i
	if _TEX_CACHE.has(key):
		return _TEX_CACHE[key] as Dictionary

	var flen: float = 86.0
	var hw: float = 8.5
	var axis: Vector2 = Vector2.RIGHT
	var p_lt: Vector2 = Vector2.UP

	var reach_side: float = hw * 2.5 + 6.0
	var min_x: int = -8
	var max_x: int = ceili(flen + 4.0) + 2
	var min_y: int = floori(-reach_side) - 2
	var max_y: int = ceili(reach_side) + 2
	var w: int = maxi(12, max_x - min_x + 1)
	var h: int = maxi(12, max_y - min_y + 1)
	var ox: int = -min_x
	var oy: int = -min_y

	# Serrated relic blade polygon with stepped fuller ricasso & battle-notched edges
	var blade_poly: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -hw * 0.72),
		Vector2(flen * 0.16, -hw * 1.18),
		Vector2(flen * 0.34, -hw * 1.10),
		Vector2(flen * 0.40, -hw * 0.62), # Serration notch 1
		Vector2(flen * 0.48, -hw * 1.06),
		Vector2(flen * 0.78, -hw * 0.80),
		Vector2(flen, 0.0),
		Vector2(flen * 0.76, hw * 0.84),
		Vector2(flen * 0.60, hw * 0.48), # Serration notch 2
		Vector2(flen * 0.52, hw * 1.08),
		Vector2(flen * 0.22, hw * 1.16),
		Vector2(0.0, hw * 0.72),
	])
	var guard_poly: PackedVector2Array = PackedVector2Array([
		Vector2(-3.5, -hw * 0.85),
		Vector2(5.5, -hw * 2.15),
		Vector2(11.5, -hw * 1.45),
		Vector2(8.5, 0.0),
		Vector2(11.5, hw * 1.45),
		Vector2(5.5, hw * 2.15),
		Vector2(-3.5, hw * 0.85),
	])

	var mask: PackedByteArray = PackedByteArray()
	var out_kind: PackedByteArray = PackedByteArray()
	var base_buf: PackedByteArray = PackedByteArray()
	var vein_buf: PackedByteArray = PackedByteArray()
	var spark_buf: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	out_kind.resize(w * h)
	base_buf.resize(w * h * 4)
	vein_buf.resize(w * h * 4)
	spark_buf.resize(w * h * 4)
	var has_vein: bool = false
	var has_spark: bool = false

	for py: int in h:
		var sy: float = float(py - oy)
		for px: int in w:
			var sx: float = float(px - ox)
			var pt_s: Vector2 = Vector2(sx, sy)
			var u: float = pt_s.dot(axis)
			var v_lt: float = pt_s.dot(p_lt)
			var uv: Vector2 = Vector2(u, v_lt)

			var in_guard: bool = _point_in_poly(uv, guard_poly)
			var in_blade: bool = _point_in_poly(uv, blade_poly)
			if not in_guard and not in_blade:
				continue

			var idx: int = py * w + px
			var idx4: int = idx * 4
			mask[idx] = 1
			var dither: float = _bayer(px, py) * 0.14

			if in_guard and u < 9.5:
				out_kind[idx] = 2
				var gv: float = 0.55 + (v_lt / maxf(hw * 2.0, 1.0)) * 0.34 + dither
				var gcol: Color = _stone_ramp(clampf(gv, 0.0, 1.0), true)
				if absf(u - 3.5) < 2.2 and absf(v_lt) < 2.2:
					gcol = GD_OUT
					if absf(u - 3.5) < 1.2 and absf(v_lt) < 1.2:
						_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 1.0))
						has_spark = true
				_put_rgba(base_buf, idx4, gcol)
				continue

			out_kind[idx] = 3
			var t_len: float = clampf(u / maxf(flen, 1.0), 0.0, 1.0)
			var abs_v: float = absf(v_lt)

			# Recessed central fuller channel + bevelled lit/shadow razor edges
			var qv: float = 0.56
			if abs_v < hw * 0.24 and t_len < 0.76:
				qv = 0.28 # Dark engraved fuller groove!
			elif v_lt >= 0.0:
				qv = 0.86 if abs_v > hw * 0.52 else 0.72
			else:
				qv = 0.48 if abs_v > hw * 0.58 else 0.36

			# Diagonal fracture glints & spectral dispersion along the giant quartz blade
			if int(floorf(u + v_lt * 0.6)) % 9 == 0 and abs_v > hw * 0.24:
				qv += 0.14
			var bcol: Color = _quartz_ramp(clampf(qv + dither, 0.0, 1.0))
			var disp: float = sin(u * 0.28 + v_lt * 0.55 + float(side_i) * 1.7)
			if disp > 0.38 and qv > 0.42:
				bcol = bcol.lerp(SPEC_TURQ, 0.24)
			elif disp < -0.38 and qv > 0.42:
				bcol = bcol.lerp(SPEC_VIOL, 0.22)

			# 5 Engraved Glowing Ancient Sun-Runes spaced up the fuller channel!
			if abs_v < 1.45 and t_len > 0.14 and t_len < 0.78:
				var rune_slot: float = fmod(u, 11.0)
				if rune_slot > 2.5 and rune_slot < 8.0:
					bcol = QZ_OUT
					_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.95))
					has_vein = true
					if absf(rune_slot - 5.2) < 0.9 and abs_v < 0.8:
						_put_rgba(spark_buf, idx4, Color(1.0, 1.0, 1.0, 1.0))
						has_spark = true
			elif abs_v > hw * 0.72 and ((px + py) % 3 == 0) and t_len > 0.25:
				_put_rgba(vein_buf, idx4, Color(1.0, 1.0, 1.0, 0.55))
				has_vein = true

			_put_rgba(base_buf, idx4, bcol)

	var res: Dictionary = _finalize_layers(w, h, mask, out_kind, base_buf, vein_buf, spark_buf, has_vein, has_spark, Vector2(-float(ox), -float(oy)))
	_TEX_CACHE[key] = res
	return res


## Bakes the banded Agate & Amethyst-Slate Open Geode Chest Cavern behind the Sun-Prism Heart (`cw_i = 22`).
static func _get_geode_cavern_entry() -> Dictionary:
	var cw_i: int = 22
	var key: String = "cav_22"
	if _TEX_CACHE.has(key):
		return _TEX_CACHE[key] as Dictionary

	var rx: float = float(cw_i)
	var ry: float = 21.0
	var poly: PackedVector2Array = PackedVector2Array()
	for i: int in 12:
		var ang: float = float(i) / 12.0 * TAU
		var rj: float = 0.88 + _hashf(419, i * 19) * 0.22
		poly.append(Vector2(cos(ang) * rx * rj, sin(ang) * ry * rj))

	var w: int = cw_i * 2 + 11
	var h: int = 51
	var cx: int = w / 2
	var cy: int = 25
	var mask: PackedByteArray = PackedByteArray()
	var out_kind: PackedByteArray = PackedByteArray()
	var base_buf: PackedByteArray = PackedByteArray()
	var vein_buf: PackedByteArray = PackedByteArray()
	var spark_buf: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	out_kind.resize(w * h)
	base_buf.resize(w * h * 4)
	vein_buf.resize(w * h * 4)
	spark_buf.resize(w * h * 4)

	for py: int in h:
		var ly: float = float(py - cy)
		for px: int in w:
			var lx: float = float(px - cx)
			if not _point_in_poly(Vector2(lx, ly), poly):
				continue
			var idx: int = py * w + px
			var idx4: int = idx * 4
			mask[idx] = 1
			out_kind[idx] = 2
			var rad_f: float = sqrt((lx / rx) * (lx / rx) + (ly / ry) * (ly / ry)) + sin(atan2(ly, lx) * 5.0) * 0.05
			var col: Color = QZ_CAV0
			if rad_f > 0.84:
				col = ST_0 if (lx + ly < 0.0) else ST_OUT # Deep dark stone cavern bevel!
			elif rad_f > 0.66:
				col = QZ_DEEP if ((px + py) % 3 == 0) else QZ_CAV1 # Deep amethyst-slate geode wall!
			else:
				col = QZ_CAV0
				if ((px * 7 + py * 13) % 29) == 0:
					col = QZ_1 # Subtle internal mineral glints!
			_put_rgba(base_buf, idx4, col)

	var res: Dictionary = _finalize_layers(w, h, mask, out_kind, base_buf, vein_buf, spark_buf, false, false, Vector2(-float(cx), -float(cy)))
	_TEX_CACHE[key] = res
	return res


## Bakes the wind-rippled, Bayer-dithered Desert Sand Dune burying Dormant Aurelith.
static func _get_dormant_dune_entry() -> Dictionary:
	var key: String = "dormant_dune_v3"
	if _TEX_CACHE.has(key):
		return _TEX_CACHE[key] as Dictionary

	var w: int = 109
	var h: int = 43
	var cx: int = 54
	var cy: int = 24
	var mask: PackedByteArray = PackedByteArray()
	var out_kind: PackedByteArray = PackedByteArray()
	var base_buf: PackedByteArray = PackedByteArray()
	var vein_buf: PackedByteArray = PackedByteArray()
	var spark_buf: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	out_kind.resize(w * h)
	base_buf.resize(w * h * 4)
	vein_buf.resize(w * h * 4)
	spark_buf.resize(w * h * 4)

	for py: int in h:
		var ly: float = float(py - cy)
		for px: int in w:
			var lx: float = float(px - cx)
			var nx: float = lx / 50.0
			var ny: float = (ly + 3.0) / 16.5
			var r2: float = nx * nx + ny * ny + sin(lx * 0.16) * 0.06
			if r2 > 1.0:
				continue
			var idx: int = py * w + px
			var idx4: int = idx * 4
			mask[idx] = 1
			out_kind[idx] = 0 # Soft sand transition onto desert floor (no hard ink ring!)

			# Wind-blown desert dune ripples + top-left sunlight + Bayer dithering + small pebbles
			var ripple: float = sin(ly * 0.95 + sin(lx * 0.09) * 2.2) * 0.14
			var shade: float = 0.62 - nx * 0.24 - ny * 0.34 + ripple + _bayer(px, py) * 0.15
			var col: Color = _sand_ramp(clampf(shade, 0.08, 1.0))
			if r2 > 0.86 and ((px + py) % 2 == 0):
				col.a = 0.55
			# Embedded small sandstone & white quartz rubble pebbles on dune slope
			var peb: int = (px * 37 + py * 91) & 127
			if peb == 3 and r2 < 0.78:
				col = QZ_3
			elif peb == 11 and r2 < 0.80:
				col = ST_1
			_put_rgba(base_buf, idx4, col)

	var res: Dictionary = {
		"base": _make_tex(w, h, base_buf),
		"vein": null,
		"spark": null,
		"flash": null,
		"off": Vector2(-float(cx), -float(cy)),
	}
	_TEX_CACHE[key] = res
	return res


# ==============================================================================
# PIXEL-ART PRIMITIVES & HIGH-LEVEL PART WRAPPERS
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
			var mw: int = floori(sqrt(maxf(0.0, 1.0 - q * q)) * float(rx))
			rows.append(Vector3i(-mw, y, mw * 2 + 1))
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


## Draws a Voronoi-masonry, Bayer-dithered, quartz-encrusted sandstone/gold boulder mass.
func _draw_crag_boulder(canvas: Node2D, center2: Vector2, rx: float, ry: float, rot: float, seed_i: int, flash_mix: float, alpha: float, mpal: Dictionary, opts: Dictionary = {}) -> void:
	if alpha <= 0.03 or rx < 1.5 or ry < 1.5:
		return
	var taper_b: float = float(opts.get("taper_bottom", 0.0))
	var taper_t: float = float(opts.get("taper_top", 0.0))
	var is_gold: bool = bool(opts.get("gold", false))
	var has_cracks: bool = bool(opts.get("cracks", true))
	var ndl_bias: float = float(opts.get("ndl", 0.15))
	var default_relief: int = (seed_i % 6) if bool(opts.get("gold_trim", false)) else -1
	var relief_id: int = int(opts.get("relief", default_relief))
	var scale_v: Vector2 = opts.get("scale_v", Vector2.ONE) as Vector2

	var entry: Dictionary = _get_crag_entry(rx, ry, seed_i, taper_b, taper_t, is_gold, relief_id, has_cracks, ndl_bias)
	var main_c: Color = mpal.get("main", Color("78f4e6")) as Color
	var spark_c: Color = mpal.get("spark", Color("ffe488")) as Color
	_stamp_entry(canvas, entry, center2, alpha, flash_mix, main_c, spark_c, 0.16, rot, scale_v)


## Stamps a canonical Sun-Quartz crystal via GPU `Transform2D` while preserving crisp top-left facet lighting across 360°.
func _draw_crystal_2d(canvas: Node2D, base2: Vector2, ang2: float, len2: float, half_w: float, flash_mix: float, vein_col: Color, alpha: float, sp_col: Color, kind: int, variant: int, gold_collar: bool = false, glow_w: float = 0.15) -> void:
	if len2 <= 2.0 or alpha <= 0.03:
		return
	var bucket: int = 18 if len2 < 21.0 else (32 if len2 < 44.0 else 64)
	if gold_collar:
		bucket = 32 if len2 < 44.0 else 64
	var canon_hw: float = 3.2 if bucket == 18 else (4.0 if bucket == 32 else 6.0)
	var flip_y: float = -1.0 if (cos(ang2) - sin(ang2)) < 0.0 else 1.0
	var sx: float = clampf(len2 / float(bucket), 0.18, 1.48)
	var sy: float = clampf(half_w / canon_hw, 0.52, 1.58) * flip_y
	var entry: Dictionary = _get_crystal_canon(kind, bucket, variant, gold_collar)
	_stamp_entry(canvas, entry, base2, alpha, flash_mix, vein_col, sp_col, glow_w, ang2, Vector2(sx, sy))


## Draws a 3D-projected Sun-Quartz crystal using one of 5 distinct hand-crafted pixel morphologies.
func _draw_geode_crystal3d(canvas: Node2D, base_3d: Vector3, dir_3d: Vector3, length: float, half_w: float, flash_mix: float, vein_col: Color, alpha: float = 1.0, core_glow: Color = Color(0, 0, 0, 0), kind: int = 0, variant: int = 0, gold_collar: bool = false) -> void:
	if length <= 2.0 or alpha <= 0.03:
		return
	var dir_n: Vector3 = dir_3d.normalized()
	var base2: Vector2 = _project_v(base_3d)
	var tip2: Vector2 = _project_v(base_3d + dir_n * length)
	var span: Vector2 = tip2 - base2
	var len2: float = span.length()
	if len2 < 3.0:
		len2 = 3.0
		span = Vector2(0.0, -3.0)
	# Prevent extreme vertical stretch when away-facing crystals align with both -Y and +Z
	len2 = minf(len2, length * 1.02)
	var ang2: float = span.angle()
	var sp_col: Color = core_glow if core_glow.a > 0.04 else vein_col
	_draw_crystal_2d(canvas, base2, ang2, len2, half_w, flash_mix, vein_col, alpha, sp_col, kind, variant, gold_collar, 0.15)


## Draws 3 intertwined sine-wave arcane plasma ribbons + drifting carved pebbles along a tether (fast C++ polylines)!
func _draw_braided_tether(canvas: Node2D, a: Vector2, b: Vector2, main_c: Color, dark_c: Color, spark_c: Color, phase_off: float, alpha: float) -> void:
	var diff: Vector2 = b - a
	var d: float = diff.length()
	if d < 3.0 or alpha <= 0.03:
		return
	var dir: Vector2 = diff / d
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var steps: int = clampi(ceili(d * 0.25), 5, 14)
	for strand: int in 3:
		var col: Color = dark_c if strand == 0 else (main_c if strand == 1 else spark_c)
		var thick: float = 2.5 if strand == 0 else (2.0 if strand == 1 else 1.0)
		col.a *= alpha * (0.72 if strand == 0 else 0.95)
		var amp_base: float = 3.2 if strand == 0 else (2.4 if strand == 1 else 1.8)
		var s_phase: float = phase_off + float(strand) * 2.1
		var pts: PackedVector2Array = PackedVector2Array()
		pts.resize(steps + 1)
		for s: int in steps + 1:
			var t: float = float(s) / float(steps)
			var env: float = sin(t * PI)
			var wave: float = sin(t * 10.5 - _time * 8.5 + s_phase) * amp_base * env
			pts[s] = (a.lerp(b, t) + perp * wave).round()
		canvas.draw_polyline(pts, col, thick, false)
	# 3 small levitating rune/quartz pebbles flowing along the tether
	for f_i: int in 3:
		var ft: float = fposmod(float(f_i) * 0.34 + _time * 0.45, 1.0)
		var fp: Vector2 = (a.lerp(b, ft) + perp * sin(ft * 9.0 + float(f_i)) * 4.5).round()
		canvas.draw_rect(Rect2(fp - Vector2(2, 2), Vector2(5, 4)), Color(ST_OUT if f_i != 2 else QZ_OUT, alpha))
		canvas.draw_rect(Rect2(fp - Vector2(1, 1), Vector2(3, 2)), Color(GD_2 if f_i == 0 else (ST_2 if f_i == 1 else QZ_3), alpha))
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

	var hand_l: Vector3 = Vector3(16.0, -56.0, 44.0 + sin(_time * 2.4 + 0.8) * 4.0)
	var hand_r: Vector3 = Vector3(16.0, 56.0, 44.0 + sin(_time * 2.4 - 0.8) * 4.0)
	var arm_l: Vector3 = Vector3(6.0, -59.0, 68.0 + sin(_time * 2.4 + 0.3) * 3.0)
	var arm_r: Vector3 = Vector3(6.0, 59.0, 68.0 + sin(_time * 2.4 - 0.3) * 3.0)

	match _pose:
		Pose.DORMANT:
			awaken_t = 0.0
		Pose.AWAKEN:
			var rise: float = smoothstep(0.04, 0.92, p)
			awaken_t = lerpf(0.24, 1.0, rise)
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
			# 4-Beat Pinnacle Death Choreography (`3.80 s`):
			# 1 (`0.00..0.25`): Resonance Overload & Skyward Surge + Piercing God-Rays
			# 2 (`0.25..0.57`): Sequential Ley-Tether Severance & Gauntlet/Shoulder Ruin Crashes
			# 3 (`0.57..0.76`): Core Implosion -> Sun-Prism Supernova & Split-Obelisk Visage Cleave!
			# 4 (`0.76..1.00`): Harmonic Golden Sand & Singing-Quartz Starlight Dissolution
			dead_t = smoothstep(0.76, 1.0, p)
			var vib_d: float = sin(_time * 48.0) * 3.4 * smoothstep(0.0, 0.22, p) * (1.0 - smoothstep(0.55, 0.62, p))
			lean = lerpf(4.0, -7.0, smoothstep(0.0, 0.25, p)) + vib_d
			chest_open += smoothstep(0.0, 0.28, p) * 16.5
			beam_charge = 1.0 if p < 0.60 else maxf(0.0, 1.0 - (p - 0.60) * 3.5)
			blade_l = 0.0
			blade_r = 0.0
			claw_open = 1.0 if p < 0.35 else 0.25

			if p < 0.57:
				core_z = lerpf(74.0, 96.0, smoothstep(0.0, 0.25, p)) + cos(_time * 37.0) * 1.8
				head_z = core_z + 36.0
			else:
				var c_fall: float = pow(smoothstep(0.57, 0.70, p), 1.65)
				var h_fall: float = pow(smoothstep(0.57, 0.72, p), 1.55)
				core_z = lerpf(96.0, 9.0, c_fall)
				head_z = lerpf(132.0, 11.0, h_fall)

			if p < 0.45:
				shoulder_z = core_z + 14.0
			else:
				var sh_fall: float = pow(smoothstep(0.45, 0.54, p), 1.75)
				shoulder_z = lerpf(110.0, 11.0, sh_fall)

			# Right gauntlet severs at `p = 0.25` and crashes onto desert floor by `p = 0.32`
			var lift_arms: float = smoothstep(0.0, 0.22, p)
			if p < 0.25:
				hand_r = Vector3(6.0, 72.0, lerpf(50.0, 94.0, lift_arms))
				arm_r = Vector3(2.0, 64.0, lerpf(70.0, 98.0, lift_arms))
			else:
				var fall_r: float = pow(smoothstep(0.25, 0.32, p), 1.8)
				hand_r = Vector3(lerpf(6.0, 28.0, fall_r), lerpf(72.0, 78.0, fall_r), lerpf(94.0, 5.0, fall_r))
				arm_r = Vector3(lerpf(2.0, 14.0, fall_r), lerpf(64.0, 58.0, fall_r), lerpf(98.0, 9.0, fall_r))

			# Left gauntlet severs at `p = 0.35` and crashes onto desert floor by `p = 0.42`
			if p < 0.35:
				hand_l = Vector3(6.0, -72.0, lerpf(50.0, 94.0, lift_arms))
				arm_l = Vector3(2.0, -64.0, lerpf(70.0, 98.0, lift_arms))
			else:
				var fall_l: float = pow(smoothstep(0.35, 0.42, p), 1.8)
				hand_l = Vector3(lerpf(6.0, 26.0, fall_l), lerpf(-72.0, -80.0, fall_l), lerpf(94.0, 5.0, fall_l))
				arm_l = Vector3(lerpf(2.0, 12.0, fall_l), lerpf(-64.0, -60.0, fall_l), lerpf(98.0, 9.0, fall_l))

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
		"dead_p": p if _pose == Pose.DEAD else 0.0,
		"claw_open": claw_open,
	}


# ==============================================================================
# MAIN WORLD-LIT PASS (`Body`)
# ==============================================================================
func _draw_body() -> void:
	_update_frame_vectors()
	_parts.clear()
	_glow_stamps.clear()

	var mpal: Dictionary = _magic_palette()
	var main_c: Color = mpal["main"] as Color
	var dark_c: Color = mpal["dark"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var eye_c: Color = mpal["eye"] as Color
	var vein_c: Color = mpal["vein"] as Color
	var flash_mix: float = clampf(_flash / 0.14, 0.0, 1.0)

	if _pose == Pose.DORMANT:
		_last_kp.clear()
		_draw_dormant_monument(mpal, flash_mix)
		return

	var kp: Dictionary = _compute_rig_pose()
	_last_kp = kp
	var is_dying: bool = (_pose == Pose.DEAD)
	var dead_p: float = float(kp["dead_p"])
	if is_dying and dead_p >= 0.53 and dead_p <= 0.68:
		var nova_flash: float = smoothstep(0.53, 0.575, dead_p) * (1.0 - smoothstep(0.585, 0.68, dead_p))
		flash_mix = maxf(flash_mix, nova_flash * 0.92)

	var lean: float = float(kp["lean"])
	var chest_open: float = float(kp["chest_open"])
	var core_z: float = float(kp["core_z"])
	var head_z: float = float(kp["head_z"])
	var sh_z: float = float(kp["shoulder_z"])
	var beam_charge: float = float(kp["beam_charge"])
	var awaken_t: float = float(kp["awaken_t"])
	var dead_t: float = float(kp["dead_t"])
	var claw_open: float = float(kp["claw_open"])
	var alpha: float = clampf((1.0 - dead_t * 0.98) * clampf(awaken_t * 1.25, 0.0, 1.0), 0.0, 1.0)

	if alpha <= 0.02:
		if is_dying and dead_p < 1.0:
			_draw_death_dissolution_motes(_body, main_c, spark_c, clampf((dead_p - 0.68) / 0.32, 0.0, 1.0))
		return

	var sh_extra_spread: float = smoothstep(0.45, 0.56, dead_p) * 20.0 if is_dying else 0.0
	var core_pos3: Vector3 = Vector3(lean, 0.0, core_z)
	var head_pos3: Vector3 = Vector3(lean + 4.5, 0.0, head_z)
	var sh_l3: Vector3 = Vector3(lean - 2.0, -43.0 - chest_open * 0.35 - sh_extra_spread, sh_z)
	var sh_r3: Vector3 = Vector3(lean - 2.0, 43.0 + chest_open * 0.35 + sh_extra_spread, sh_z)
	var arm_l3: Vector3 = (kp["arm_l"] as Vector3) + Vector3(lean * 0.5, 0.0, 0.0)
	var arm_r3: Vector3 = (kp["arm_r"] as Vector3) + Vector3(lean * 0.5, 0.0, 0.0)
	var hand_l3: Vector3 = (kp["hand_l"] as Vector3) + Vector3(lean * 0.6, 0.0, 0.0)
	var hand_r3: Vector3 = (kp["hand_r"] as Vector3) + Vector3(lean * 0.6, 0.0, 0.0)

	var hand_l_override: Vector2 = Vector2.INF
	var hand_r_override: Vector2 = Vector2.INF
	if _detached_fist_active[0] and not is_dying:
		hand_l_override = (_detached_fist_world[0] - global_position) + Vector2(0.0, -_detached_fist_lift[0])
	if _detached_fist_active[1] and not is_dying:
		hand_r_override = (_detached_fist_world[1] - global_position) + Vector2(0.0, -_detached_fist_lift[1])

	_core_local = _project_v(core_pos3)
	_head_local = _project_v(head_pos3 + Vector3(0.0, 0.0, 12.0))
	_fist_local[0] = hand_l_override if hand_l_override.is_finite() else _project_v(hand_l3)
	_fist_local[1] = hand_r_override if hand_r_override.is_finite() else _project_v(hand_r3)

	# 0) Colossal Ground Cast Shadow + Arcane Sand Whirlpool & Broken Temple Seal
	var seal_alpha: float = alpha * (1.0 - smoothstep(0.56, 0.72, dead_p)) if is_dying else alpha
	if seal_alpha > 0.03:
		_draw_ground_seal_and_vortex(mpal, seal_alpha, beam_charge)
	if _pose == Pose.AWAKEN:
		_draw_awakening_debris(main_c, spark_c, _pose_progress())

	var storm_live: float = storm_ascension * (1.0 - smoothstep(0.16, 0.56, dead_p)) if is_dying else storm_ascension

	# 1) LOWER BODY: Inverted Geode Tail-Spire & Varied Orbiting Relics (Stage 1/2) -> Massive 96px Sandstorm Funnel (Stage 3)
	if storm_live < 0.90:
		var tail_alpha: float = alpha * (1.0 - smoothstep(0.25, 0.90, storm_live))
		var tail_z_base: float = maxf(6.0 if is_dying else 10.0, core_z - 32.0)
		var tail_top3: Vector3 = Vector3(lean * 0.65, 0.0, tail_z_base)
		_add_part(_depth_v(tail_top3), _part_inverted_tail_spire.bind(tail_top3, core_z, tail_alpha, flash_mix, mpal))
		if not is_dying or dead_p < 0.57:
			for o_i: int in 5:
				var o_ang: float = _time * 1.45 + float(o_i) * (TAU / 5.0)
				var o_rad: float = 25.0 + float(o_i % 2) * 5.0 + (dead_p * 26.0 if is_dying else 0.0)
				var o_z: float = tail_z_base + float(o_i % 3) * 7.0 + sin(_time * 2.8 + float(o_i)) * 3.0
				var o_pos3: Vector3 = Vector3(lean * 0.5 + cos(o_ang) * o_rad * 0.72, sin(o_ang) * o_rad, o_z)
				_add_part(_depth_v(o_pos3), _part_orbit_plate.bind(o_pos3, o_i, tail_alpha, flash_mix, mpal))

	if storm_live > 0.05:
		_add_cyclone_parts(core_z - 12.0, alpha * smoothstep(0.05, 0.55, storm_live), mpal, flash_mix)

	# 2) DORSAL CANYON SPINE + BANDED GEODE RIB CAVERN + 7 VARIED BACK QUARTZ SPIRES
	var spine3: Vector3 = core_pos3 + Vector3(-11.0, 0.0, 0.0)
	_add_part(_depth_v(spine3), _part_canyon_spine_and_cavern.bind(spine3, core_pos3, chest_open, alpha, flash_mix, mpal))

	# 3) ROSE-CUT OCTAGONAL ASTRAL SUN-PRISM HEART (swells -> implodes -> detonates at `dead_p = 0.57`!)
	if not is_dying or dead_p < 0.57:
		var h_scale: float = 1.0 + beam_charge * 0.3
		if is_dying:
			if dead_p < 0.51:
				h_scale = lerpf(1.18, 1.72, smoothstep(0.0, 0.51, dead_p))
			else:
				h_scale = lerpf(1.72, 0.40, smoothstep(0.51, 0.57, dead_p))
		_add_part(_depth_v(core_pos3) + 0.5, _part_prism_heart.bind(core_pos3, mpal, flash_mix, alpha, h_scale))

	# 4) ASYMMETRIC V-TAPERED CRAGGY CHEST RIBS
	var rib_sep: float = 17.5 + chest_open + (smoothstep(0.57, 0.74, dead_p) * 18.0 if is_dying else 0.0)
	for side_i: int in 2:
		var s_sign: float = -1.0 if side_i == 0 else 1.0
		var rib3: Vector3 = core_pos3 + Vector3(5.0, s_sign * rib_sep, 2.0)
		_add_part(_depth_v(rib3) + 1.0, _part_chest_crag.bind(rib3, s_sign, side_i, alpha, flash_mix, mpal))

	# 5) STAGE 2/3 8 MONUMENTAL VARIED CRYSTAL WING-BLADES + 12 ORBITING SATELLITE SPLINTERS
	if prism_release > 0.04 or storm_ascension > 0.04:
		var wing_vis: float = smoothstep(0.04, 0.78, maxf(prism_release, storm_ascension))
		var wing_scatter: float = smoothstep(0.45, 0.62, dead_p) if is_dying else 0.0
		var wing_alpha: float = alpha * (1.0 - smoothstep(0.56, 0.78, dead_p)) if is_dying else alpha
		if wing_alpha > 0.03:
			for side_i: int in 2:
				var s_sign: float = -1.0 if side_i == 0 else 1.0
				var away_side: float = clampf(-(_right * s_sign).y, 0.0, 1.0)
				for w_i: int in 4:
					var w_ang: float = WING_ANGLES[w_i] + wing_scatter * 0.55
					var w_len: float = WING_LENS[w_i] * wing_vis * (1.0 + storm_ascension * 0.15) * lerpf(1.0, 0.80, away_side)
					var w_w: float = WING_WIDTHS[w_i] * wing_vis
					var w_base: Vector3 = core_pos3 + Vector3(-13.0 - float(w_i) * 1.8, s_sign * (22.0 + float(w_i) * 5.0 + wing_scatter * 36.0), maxf(4.0, 8.0 + float(w_i) * 5.5 - wing_scatter * 48.0))
					var z_lift: float = (sin(w_ang * 0.70) + 0.08) * lerpf(1.0, 0.58, away_side) - wing_scatter * 0.75
					var w_dir: Vector3 = Vector3(-0.36, s_sign * cos(w_ang * 0.58) * 0.92, z_lift).normalized()
					var w_kind: int = WING_KINDS_L[w_i] if side_i == 0 else WING_KINDS_R[w_i]
					var has_collar: bool = (w_i == 1 or w_i == 2)
					_add_part(_depth_v(w_base) - 2.0, _part_crystal_spire.bind(w_base, w_dir, w_len, w_w, flash_mix, main_c, wing_alpha, spark_c, w_kind, side_i * 7 + w_i, has_collar))

		if not is_dying or dead_p < 0.57:
			for sat_i: int in SAT_COUNT:
				var s_ang: float = _time * (0.95 if sat_i % 2 == 0 else -0.75) + float(sat_i) * (TAU / float(SAT_COUNT))
				var s_rad: float = 54.0 + float(sat_i % 3) * 11.0
				var s_z: float = core_z - 8.0 + float(sat_i % 5) * 16.0 + sin(_time * 2.2 + float(sat_i)) * 4.0
				var sat3: Vector3 = Vector3(lean + cos(s_ang) * s_rad * 0.65, sin(s_ang) * s_rad, s_z)
				_add_part(_depth_v(sat3), _part_satellite_shard.bind(sat3, sat_i, wing_vis * alpha, flash_mix, main_c))

	# 6) ASYMMETRIC CANYON-MESA SHOULDER CRAGS + DISTINCT QUARTZ CLUSTERS
	for side_i: int in 2:
		var s_sign: float = -1.0 if side_i == 0 else 1.0
		var sh3: Vector3 = sh_l3 if side_i == 0 else sh_r3
		_add_part(_depth_v(sh3) + 1.2, _part_shoulder_crag.bind(sh3, s_sign, side_i, alpha, flash_mix, mpal))

	# 7) ANCIENT HORNED 3-EYED OBELISK VISAGE + ASYMMETRIC 9-SHARD CATHEDRAL SUN-CROWN
	if is_dying and dead_p >= 0.57:
		var split_q: float = smoothstep(0.57, 0.75, dead_p)
		var fall_q: float = pow(smoothstep(0.57, 0.72, dead_p), 1.5)
		_add_part(_depth_v(head_pos3) + 1.5, _part_cleaved_obelisk_death.bind(head_pos3, split_q, fall_q, main_c, spark_c, flash_mix, alpha))
		var crown_alpha: float = alpha * (1.0 - smoothstep(0.66, 0.86, dead_p))
		if crown_alpha > 0.04:
			for c_i: int in 9:
				var c_side_d: float = CROWN_OFFSETS[c_i] * (1.0 + split_q * 1.65) + (-14.0 if c_i < 4 else 14.0) * split_q
				var c_z_d: float = maxf(4.0, lerpf(136.0 + CROWN_ARC_Z[c_i], 6.0, fall_q))
				var c_pos3_d: Vector3 = Vector3(head_pos3.x + float(c_i % 3 - 1) * 8.0 * split_q, c_side_d, c_z_d)
				var c_dir_d: Vector3 = Vector3(0.18 * split_q, signf(c_side_d) * (0.25 + 0.65 * split_q), 1.0 - 0.75 * split_q).normalized()
				_add_part(_depth_v(c_pos3_d) + 0.4, _part_crystal_spire.bind(c_pos3_d, c_dir_d, CROWN_HEIGHTS[c_i], CROWN_WIDTHS[c_i], flash_mix, spark_c, crown_alpha, Color(0, 0, 0, 0), CROWN_KINDS[c_i], c_i + 1, c_i == 4))
	else:
		_add_part(_depth_v(head_pos3) + 1.5, _part_obelisk_head.bind(head_pos3, eye_c, main_c, spark_c, flash_mix, alpha))
		for c_i: int in 9:
			var c_side: float = CROWN_OFFSETS[c_i] * (0.86 + storm_ascension * 0.16)
			var c_z: float = head_z + 24.0 + CROWN_ARC_Z[c_i] + sin(_time * 2.7 + float(c_i) * 0.65) * 1.8
			var c_pos3: Vector3 = Vector3(head_pos3.x - 2.0, c_side, c_z)
			var tilt_j: float = (_hashf(991, c_i * 17) - 0.5) * 0.08
			var c_dir: Vector3 = Vector3(-0.08, c_side * 0.020 + tilt_j, 1.0).normalized()
			var c_flare: Color = spark_c if (beam_charge > 0.35 or c_i == 4) else vein_c
			var c_kind: int = CROWN_KINDS[c_i]
			_add_part(_depth_v(c_pos3) + 0.4, _part_crystal_spire.bind(c_pos3, c_dir, CROWN_HEIGHTS[c_i], CROWN_WIDTHS[c_i], flash_mix, c_flare, alpha, spark_c if c_i == 4 else Color(0, 0, 0, 0), c_kind, c_i + 1, c_i == 4))

	# 8) BRAIDED LEY-TETHERS + FOREARM BRACER CRAGS + COLOSSAL ARTICULATED CLAW-GAUNTLETS + RELIC GREATBLADES
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

		var tether_alpha: float = alpha
		if is_dying:
			var snap_at: float = 0.35 if side_i == 0 else 0.25
			tether_alpha = alpha * (1.0 - smoothstep(snap_at - 0.02, snap_at + 0.03, dead_p))

		if not has_over:
			if tether_alpha > 0.04:
				_add_part(_depth_v(arm3) - 0.3, _part_braided_arm_tether.bind(p_sh2, p_arm2, _project_v(hand3), main_c, dark_c, spark_c, side_i, tether_alpha))
			_add_part(_depth_v(arm3) + 0.5, _part_forearm_crag.bind(arm3, s_sign, side_i, alpha, flash_mix, mpal))
			_add_part(_depth_v(hand3) + 0.8, _part_colossus_gauntlet.bind(hand3, s_sign, side_i, mpal, flash_mix, alpha, blade_amt, float(kp["blade_sweep"]), claw_open))
		else:
			var det_depth: float = det_over.y + 42.0
			_add_part(det_depth - 0.5, _part_detached_tether.bind(p_sh2, det_over, main_c, dark_c, spark_c, alpha))
			_add_part(det_depth, _part_detached_gauntlet.bind(det_over, s_sign, side_i, mpal, flash_mix, alpha))

	# 9) STAGE 3 GIANT ROTATING 3D CELESTIAL ARMILLARY RINGS (`radius 62 & 74`)
	if storm_live > 0.05:
		_add_armillary_ring_parts(core_pos3 + Vector3(-4.0, 0.0, 10.0), 62.0, 0.38, _time * 1.05, alpha * smoothstep(0.05, 0.55, storm_live), mpal, flash_mix, false)
		_add_armillary_ring_parts(core_pos3 + Vector3(-4.0, 0.0, 10.0), 74.0, -0.44, -_time * 0.82 + 0.85, alpha * smoothstep(0.15, 0.70, storm_live), mpal, flash_mix, true)

	_parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for pt: Dictionary in _parts:
		(pt["fn"] as Callable).call()

	if is_dying:
		var ray_int: float = smoothstep(0.04, 0.24, dead_p) * (1.0 - smoothstep(0.55, 0.60, dead_p))
		if ray_int > 0.03:
			_draw_death_god_rays(_body, _core_local, ray_int, main_c, spark_c, false)
		if dead_p >= 0.56 and dead_p <= 0.82:
			_draw_death_supernova(_body, Vector2(0.0, -96.0), clampf((dead_p - 0.56) / 0.26, 0.0, 1.0), main_c, spark_c, false)
		if dead_p >= 0.62:
			_draw_death_dissolution_motes(_body, main_c, spark_c, clampf((dead_p - 0.62) / 0.38, 0.0, 1.0))
	else:
		_draw_antigrav_motes(_body, main_c, spark_c, alpha, head_z + 30.0)


# ==============================================================================
# PART CALLBACKS (DETERMINISTIC `.bind(...)` HELPERS)
# ==============================================================================
func _part_prism_heart(core_pos3: Vector3, mpal: Dictionary, flash_mix: float, alpha: float, scale_k: float) -> void:
	_draw_astral_prism_heart(_body, core_pos3, mpal, flash_mix, alpha, scale_k)


func _draw_ground_seal_and_vortex(mpal: Dictionary, alpha: float, beam_charge: float) -> void:
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	_oval(_body, Vector2(0.0, 2.0), Vector2(48.0, 17.0), Color(ST_OUT, 0.34 * alpha))
	_oval(_body, Vector2(0.0, 1.0), Vector2(36.0, 12.0), Color(SD_0, 0.25 * alpha))
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
			_body.draw_rect(Rect2(gi - Vector2.ONE, Vector2(3, 2)), Color(spark_c, alpha * 0.72))


func _part_inverted_tail_spire(tail_top3: Vector3, core_z: float, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c_base: Vector2 = _project_v(tail_top3 + Vector3(0.0, 0.0, 12.0))
	var tail_h: float = maxf(18.0, core_z - tail_top3.z)
	var sy_tail: float = clampf((tail_h * 0.55) / 24.0, 0.55, 1.45)
	# Voronoi-textured fractured waist monolith with astrolabe relief (`5`), GPU-scaled vertically so hover never misses cache!
	_draw_crag_boulder(_body, c_base + Vector2(0.0, 4.0), 21.0, 24.0, 0.0, 107, flash_mix, alpha, mpal, {"taper_bottom": 0.62, "relief": 5, "cracks": true, "ndl": 0.2, "scale_v": Vector2(1.0, sy_tail)})
	# Varied downward sun-quartz anchor cluster (central heavy druse tooth + cleaved left + notched right)
	_draw_geode_crystal3d(_body, tail_top3 + Vector3(0.0, 0.0, 6.0), Vector3(0.05, 0.0, -1.0), 23.0, 6.8, flash_mix, mpal["main"] as Color, alpha, mpal["spark"] as Color, CrystalKind.DRUSE_CROWN, 1)
	_draw_geode_crystal3d(_body, tail_top3 + Vector3(2.0, -10.5, 10.0), Vector3(0.1, -0.28, -0.95), 16.0, 3.8, flash_mix, mpal["vein"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, 2)
	_draw_geode_crystal3d(_body, tail_top3 + Vector3(2.0, 10.5, 9.5), Vector3(0.1, 0.26, -0.95), 14.5, 3.5, flash_mix, mpal["vein"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.BATTLE_NOTCHED, 3)


func _part_orbit_plate(pos3: Vector3, idx: int, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(pos3)
	if idx == 0:
		_draw_crag_boulder(_body, c2, 8.5, 11.5, 0.25, 211, flash_mix, alpha, mpal, {"taper_bottom": 0.45, "relief": 1, "cracks": true})
	elif idx == 1:
		_draw_geode_crystal3d(_body, pos3 - Vector3(0, 0, 5.0), Vector3(0.1, -0.14, 0.98), 17.0, 4.0, flash_mix, mpal["main"] as Color, alpha, mpal["spark"] as Color, CrystalKind.TWIN_CLUSTER, 1)
	elif idx == 2:
		# Broken tarnished-gold temple pillar drum!
		_draw_crag_boulder(_body, c2, 7.5, 8.5, -0.35, 239, flash_mix, alpha, mpal, {"gold": true, "cracks": false})
	elif idx == 3:
		_draw_geode_crystal3d(_body, pos3 - Vector3(0, 0, 4.0), Vector3(-0.1, 0.18, 0.98), 15.0, 3.8, flash_mix, mpal["vein"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, 3)
	else:
		_draw_crag_boulder(_body, c2, 8.0, 10.5, 0.50, 263, flash_mix, alpha, mpal, {"taper_bottom": 0.4, "relief": 4, "cracks": true})


func _part_canyon_spine_and_cavern(spine3: Vector3, core_pos3: Vector3, chest_open: float, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c_sp: Vector2 = _project_v(spine3)
	_draw_crag_boulder(_body, c_sp, 30.0, 31.0, 0.0, 313, flash_mix, alpha, mpal, {"taper_bottom": 0.38, "relief": 4, "cracks": true, "ndl": -0.15})

	# 7 varied dorsal quartz crystals erupting upward behind shoulders/neck
	var dorsal_kinds: Array[int] = [
		CrystalKind.CLEAVED_TABLE, CrystalKind.BATTLE_NOTCHED, CrystalKind.TWIN_CLUSTER,
		CrystalKind.CATHEDRAL_HEX, CrystalKind.DRUSE_CROWN, CrystalKind.CLEAVED_TABLE, CrystalKind.BATTLE_NOTCHED,
	]
	for d_i: int in 7:
		var off_s: float = float(d_i - 3) * 8.8
		var d_len: float = 36.0 - absf(float(d_i - 3)) * 4.8 + float(d_i % 2) * 2.5
		var d_pos3: Vector3 = spine3 + Vector3(-6.0, off_s, 14.0 - absf(float(d_i - 3)) * 1.5)
		var d_dir: Vector3 = Vector3(-0.36, off_s * 0.019, 0.92).normalized()
		_draw_geode_crystal3d(_body, d_pos3, d_dir, d_len, 4.4 if d_i == 3 else 3.2, flash_mix, mpal["vein"] as Color, alpha, Color(0, 0, 0, 0), dorsal_kinds[d_i], d_i)

	# Banded Agate & Amethyst-Slate Open Geode Cavern behind the Astral Prism Heart
	if _forward.y > -0.65:
		var cav_c: Vector2 = _project_v(core_pos3 + Vector3(1.0, 0.0, 1.0))
		var cav_w: float = 15.5 + chest_open * 0.48
		var cav_entry: Dictionary = _get_geode_cavern_entry()
		_stamp_entry(_body, cav_entry, cav_c, alpha, flash_mix, Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0, 0.0, Vector2(clampf(cav_w / 22.0, 0.65, 1.45), 1.0))
		for t_i: int in 7:
			var ang: float = float(t_i) / 7.0 * TAU + 0.35
			var tb3: Vector3 = core_pos3 + Vector3(1.5, cos(ang) * (cav_w * 0.86), sin(ang) * 14.5)
			var td3: Vector3 = Vector3(0.15, -cos(ang) * 0.85, -sin(ang) * 0.65)
			_draw_geode_crystal3d(_body, tb3, td3, 8.5 + float(t_i % 3) * 2.0, 2.5, flash_mix, mpal["main"] as Color, alpha, Color(0, 0, 0, 0), t_i % 5, t_i)


func _part_chest_crag(rib3: Vector3, s_sign: float, side_i: int, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(rib3)
	var is_right: bool = side_i == 1
	var ndl_v: float = 0.25 if not is_right else -0.1
	# Left chest gets broken diagonal gold strap (`0`); Right chest gets sunken sun-cartouche (`1`)!
	var rib_relief: int = 0 if side_i == 0 else 1
	_draw_crag_boulder(_body, c2, 17.0, 22.5, s_sign * 0.16, 521 + side_i * 43, flash_mix, alpha, mpal, {"taper_bottom": 0.48, "relief": rib_relief, "cracks": true, "ndl": ndl_v})
	# Heavy tarnished-gold temple collar arch across upper clavicle
	var cl3: Vector3 = rib3 + Vector3(2.0, -s_sign * 2.5, 15.5)
	_draw_crag_boulder(_body, _project_v(cl3), 13.5, 7.0, s_sign * 0.22, 577 + side_i * 19, flash_mix, alpha, mpal, {"gold": true, "cracks": false, "ndl": ndl_v})
	# Varied geode crystal teeth lining the open chest split
	var k_up: int = CrystalKind.BATTLE_NOTCHED if side_i == 0 else CrystalKind.TWIN_CLUSTER
	var k_lo: int = CrystalKind.CLEAVED_TABLE if side_i == 0 else CrystalKind.DRUSE_CROWN
	_draw_geode_crystal3d(_body, rib3 + Vector3(3.0, -s_sign * 7.5, 9.0), Vector3(0.25, -s_sign * 0.55, 0.78), 14.5, 3.4, flash_mix, mpal["spark"] as Color, alpha, mpal["main"] as Color, k_up, side_i + 1)
	_draw_geode_crystal3d(_body, rib3 + Vector3(1.0, -s_sign * 6.0, -9.0), Vector3(0.15, -s_sign * 0.42, -0.88), 12.5, 3.0, flash_mix, mpal["main"] as Color, alpha, Color(0, 0, 0, 0), k_lo, side_i + 3)


func _part_shoulder_crag(sh3: Vector3, s_sign: float, side_i: int, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(sh3)
	var ndl_v: float = 0.35 if side_i == 0 else -0.05
	# Left shoulder: stepped gold temple corner-clasp (`3`); Right shoulder: cracked mini-geode pocket (`2`)!
	var sh_relief: int = 3 if side_i == 0 else 2
	_draw_crag_boulder(_body, c2, 20.0, 17.0, s_sign * 0.18, 631 + side_i * 59, flash_mix, alpha, mpal, {"taper_bottom": 0.32, "relief": sh_relief, "cracks": true, "ndl": ndl_v})
	_draw_crag_boulder(_body, _project_v(sh3 + Vector3(0.0, s_sign * 2.0, 11.0)), 14.5, 6.5, s_sign * 0.18, 683 + side_i * 23, flash_mix, alpha, mpal, {"gold": true, "cracks": false, "ndl": ndl_v})

	# Curated asymmetrical geological sun-quartz clusters (Left != Right, zero feather-row look!)
	if side_i == 0:
		_draw_geode_crystal3d(_body, sh3 + Vector3(-3.0, -2.0, 11.0), Vector3(-0.14, -0.24, 0.96), 25.0, 3.6, flash_mix, mpal["vein"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, 0)
		_draw_geode_crystal3d(_body, sh3 + Vector3(1.0, -6.5, 10.5), Vector3(0.06, -0.44, 0.89), 35.0, 4.8, flash_mix, mpal["spark"] as Color, alpha, mpal["main"] as Color, CrystalKind.TWIN_CLUSTER, 1)
		_draw_geode_crystal3d(_body, sh3 + Vector3(-2.0, -11.0, 8.5), Vector3(-0.18, -0.62, 0.76), 28.0, 3.8, flash_mix, mpal["vein"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.BATTLE_NOTCHED, 2)
		_draw_geode_crystal3d(_body, sh3 + Vector3(4.0, -13.5, 6.5), Vector3(0.22, -0.74, 0.63), 19.0, 3.9, flash_mix, mpal["spark"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.DRUSE_CROWN, 3)
		_draw_geode_crystal3d(_body, sh3 + Vector3(0.0, -16.0, 4.0), Vector3(0.0, -0.86, 0.50), 16.0, 3.0, flash_mix, mpal["vein"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, 1)
	else:
		_draw_geode_crystal3d(_body, sh3 + Vector3(2.0, 2.5, 11.0), Vector3(0.10, 0.22, 0.97), 28.0, 4.0, flash_mix, mpal["spark"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.DRUSE_CROWN, 2)
		_draw_geode_crystal3d(_body, sh3 + Vector3(-1.5, 6.5, 10.5), Vector3(-0.08, 0.42, 0.90), 34.0, 4.6, flash_mix, mpal["vein"] as Color, alpha, mpal["main"] as Color, CrystalKind.CATHEDRAL_HEX, 3)
		_draw_geode_crystal3d(_body, sh3 + Vector3(3.0, 10.5, 8.5), Vector3(0.16, 0.58, 0.80), 22.0, 3.8, flash_mix, mpal["spark"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, 0)
		_draw_geode_crystal3d(_body, sh3 + Vector3(-2.5, 13.5, 6.5), Vector3(-0.15, 0.72, 0.67), 27.0, 3.7, flash_mix, mpal["vein"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.TWIN_CLUSTER, 2)
		_draw_geode_crystal3d(_body, sh3 + Vector3(1.5, 16.0, 4.0), Vector3(0.12, 0.85, 0.51), 15.5, 3.0, flash_mix, mpal["spark"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.BATTLE_NOTCHED, 1)


func _part_obelisk_head(head_pos3: Vector3, eye_c: Color, main_c: Color, spark_c: Color, flash_mix: float, alpha: float) -> void:
	_draw_archon_obelisk_visage(_body, head_pos3, eye_c, main_c, spark_c, flash_mix, alpha)


func _part_crystal_spire(base3: Vector3, dir3: Vector3, length: float, half_w: float, flash_mix: float, vein_col: Color, alpha: float, core_glow: Color, kind: int = 0, variant: int = 0, gold_collar: bool = false) -> void:
	_draw_geode_crystal3d(_body, base3, dir3, length, half_w, flash_mix, vein_col, alpha, core_glow, kind, variant, gold_collar)


func _part_satellite_shard(sat3: Vector3, idx: int, alpha: float, flash_mix: float, vein_col: Color) -> void:
	if idx % 4 == 3:
		_draw_crag_boulder(_body, _project_v(sat3), 5.5, 7.0, float(idx) * 0.5, 770 + idx * 13, flash_mix, alpha, {"main": vein_col, "spark": vein_col}, {"relief": 1, "cracks": true})
		return
	var tilt: float = _time * 1.4 + float(idx)
	var dir3: Vector3 = Vector3(cos(tilt) * 0.35, sin(tilt) * 0.45, 0.85).normalized()
	_draw_geode_crystal3d(_body, sat3, dir3, 14.0 + float(idx % 3) * 4.5, 3.0, flash_mix, vein_col, alpha, Color(0, 0, 0, 0), idx % 5, idx)


func _part_braided_arm_tether(p_sh2: Vector2, p_arm2: Vector2, p_hand2: Vector2, main_c: Color, dark_c: Color, spark_c: Color, side_i: int, alpha: float) -> void:
	_draw_braided_tether(_body, p_sh2, p_arm2, main_c, dark_c, spark_c, float(side_i) * 1.2, alpha)
	_draw_braided_tether(_body, p_arm2, p_hand2 + Vector2(0.0, -6.0), main_c, dark_c, spark_c, float(side_i) * 1.2 + 2.0, alpha)


func _part_forearm_crag(arm3: Vector3, s_sign: float, side_i: int, alpha: float, flash_mix: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(arm3)
	var fa_relief: int = 1 if side_i == 0 else 4
	_draw_crag_boulder(_body, c2, 13.5, 14.5, s_sign * 0.25, 743 + side_i * 37, flash_mix, alpha, mpal, {"taper_bottom": 0.4, "relief": fa_relief, "cracks": true})
	var spur_kind: int = CrystalKind.TWIN_CLUSTER if side_i == 0 else CrystalKind.CLEAVED_TABLE
	_draw_geode_crystal3d(_body, arm3 + Vector3(-1.0, s_sign * 6.0, 3.0), Vector3(-0.2, s_sign * 0.72, 0.65), 19.0, 3.6, flash_mix, mpal["main"] as Color, alpha, Color(0, 0, 0, 0), spur_kind, side_i)


func _part_colossus_gauntlet(hand3: Vector3, s_sign: float, side_i: int, mpal: Dictionary, flash_mix: float, alpha: float, blade_amt: float, blade_sweep: float, claw_open: float) -> void:
	_draw_colossus_gauntlet(_body, hand3, s_sign, side_i, mpal, flash_mix, alpha, blade_amt, blade_sweep, claw_open)


func _part_detached_tether(p_sh2: Vector2, det_over: Vector2, main_c: Color, dark_c: Color, spark_c: Color, alpha: float) -> void:
	_draw_braided_tether(_body, p_sh2, det_over + Vector2(0.0, -10.0), main_c, dark_c, spark_c, 0.85, alpha)


func _part_detached_gauntlet(det_over: Vector2, s_sign: float, side_i: int, mpal: Dictionary, flash_mix: float, alpha: float) -> void:
	_draw_detached_gauntlet_screen(_body, det_over, s_sign, side_i, mpal, flash_mix, alpha)


# ==============================================================================
# SPECIALTY SCULPTED PIECES (ROSE-CUT PRISM HEART, VISAGE, CLAW GAUNTLETS)
# ==============================================================================
func _draw_astral_prism_heart(canvas: Node2D, core_pos3: Vector3, mpal: Dictionary, flash_mix: float, alpha: float, scale_k: float) -> void:
	var c: Vector2 = _project_v(core_pos3)
	var main_c: Color = mpal["main"] as Color
	var dark_c: Color = mpal["dark"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var core_c: Color = mpal["core"] as Color

	# Engraved golden astrolabe ring + 4 cardinal notched gold clasps framing the Heart
	var ring_pts: int = 12
	for r_i: int in ring_pts:
		var a0: float = _time * 1.85 + float(r_i) / float(ring_pts) * TAU
		var a1: float = a0 + 0.34
		var p0: Vector2 = (c + Vector2(cos(a0) * 15.0 * scale_k, sin(a0) * 18.0 * scale_k)).round()
		var p1: Vector2 = (c + Vector2(cos(a1) * 15.0 * scale_k, sin(a1) * 18.0 * scale_k)).round()
		_draw_pixel_line(canvas, p0, p1, Color(GD_OUT, alpha * 0.9), 3.0)
		_draw_pixel_line(canvas, p0, p1, Color(GD_2 if r_i % 2 == 0 else spark_c, alpha * 0.95), 1.0)
		if r_i % 3 == 0:
			canvas.draw_rect(Rect2(p0 - Vector2.ONE, Vector2(3, 3)), Color(GD_3, alpha))

	# Multi-faceted 8-point Rose-Cut Sun-Prism Star
	var spin: float = sin(_time * 2.5) * 0.24
	var rh: float = 17.0 * scale_k
	var rw: float = 11.5 * scale_k * (0.80 + 0.20 * absf(cos(_time * 2.6)))
	var top: Vector2 = (c + Vector2(sin(spin) * 2.5, -rh)).round()
	var bot: Vector2 = (c + Vector2(-sin(spin) * 2.5, rh)).round()
	var lft: Vector2 = (c + Vector2(-rw, cos(spin) * 1.5)).round()
	var rgt: Vector2 = (c + Vector2(rw, -cos(spin) * 1.5)).round()
	var d_ul: Vector2 = (c + Vector2(-rw * 0.62, -rh * 0.56)).round()
	var d_ur: Vector2 = (c + Vector2(rw * 0.62, -rh * 0.56)).round()
	var d_dr: Vector2 = (c + Vector2(rw * 0.62, rh * 0.56)).round()
	var d_dl: Vector2 = (c + Vector2(-rw * 0.62, rh * 0.56)).round()

	var sil: PackedVector2Array = PackedVector2Array([top, d_ur, rgt, d_dr, bot, d_dl, lft, d_ul])
	_draw_silhouette_outline(canvas, [sil], Color(QZ_OUT, alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([top, c, lft, d_ul]), Color(QZ_4.lerp(Color.WHITE, flash_mix), alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([top, d_ur, rgt, c]), Color(main_c.lerp(Color.WHITE, flash_mix), alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([c, rgt, d_dr, bot]), Color(dark_c.lerp(Color.WHITE, flash_mix), alpha))
	_draw_flat_span_poly(canvas, PackedVector2Array([lft, c, bot, d_dl]), Color(spark_c.lerp(Color.WHITE, flash_mix), alpha))

	# Internal rose-cut crown table & incandescent star nucleus
	var inner_table: PackedVector2Array = PackedVector2Array([
		(c + Vector2(0, -6.5 * scale_k)).round(),
		(c + Vector2(4.5 * scale_k, 0)).round(),
		(c + Vector2(0, 6.5 * scale_k)).round(),
		(c + Vector2(-4.5 * scale_k, 0)).round(),
	])
	_draw_flat_span_poly(canvas, inner_table, Color(core_c, alpha))
	_draw_pixel_line(canvas, top, bot, Color(QZ_4, alpha * 0.8), 1.0)
	_draw_pixel_line(canvas, lft, rgt, Color(QZ_4, alpha * 0.8), 1.0)
	canvas.draw_rect(Rect2(c.round() - Vector2(2, 3), Vector2(4, 6)), Color(Color.WHITE, alpha))

	for arc_i: int in 5:
		var a_ang: float = _time * 4.2 + float(arc_i) * (TAU / 5.0)
		var out_p: Vector2 = c + Vector2(cos(a_ang) * (15.0 + 3.0 * sin(_time * 9.0 + float(arc_i))), sin(a_ang) * 18.0)
		var j_mid: Vector2 = c.lerp(out_p, 0.5) + Vector2(sin(_time * 17.0 + float(arc_i)) * 4.0, cos(_time * 13.0) * 3.0)
		_draw_pixel_line(canvas, c, j_mid, Color(spark_c, alpha * 0.9), 1.0)
		_draw_pixel_line(canvas, j_mid, out_p, Color(main_c, alpha * 0.85), 1.0)


func _draw_archon_obelisk_visage(canvas: Node2D, head_pos3: Vector3, eye_c: Color, main_c: Color, spark_c: Color, flash_mix: float, alpha: float) -> void:
	var hc: Vector2 = _project_v(head_pos3)
	var face_vis: float = _forward.y # > 0 facing viewer (Down), < 0 facing away

	# Rear neck sandstone + quartz spine anchoring the levitating obelisk mask
	_draw_crag_boulder(canvas, _project_v(head_pos3 + Vector3(-5.0, 0.0, -3.0)), 11.0, 12.0, 0.0, 811, flash_mix, alpha, {"main": main_c, "spark": spark_c}, {"taper_bottom": 0.45, "cracks": false, "ndl": -0.2})

	# Select baked obelisk visage orientation (`-2` rear cranium, `-1` left profile, `0` front, `+1` right profile)
	var sector: int = 0
	if face_vis < -0.32:
		sector = -2
	elif _forward.x < -0.58:
		sector = -1
	elif _forward.x > 0.58:
		sector = 1
	var head_entry: Dictionary = _get_head_entry(sector)
	_stamp_entry(canvas, head_entry, hc, alpha, flash_mix, main_c, spark_c, 0.18)

	# Asymmetric Archon Brow-Horns: Left = tall curved Battle-Notched horn; Right = shattered Cleaved horn!
	var hb_l: Vector3 = head_pos3 + Vector3(1.0, -8.5, 12.0)
	var hd_l: Vector3 = Vector3(-0.1, -0.64, 0.76).normalized()
	_draw_geode_crystal3d(canvas, hb_l, hd_l, 20.0, 3.3, flash_mix, spark_c if face_vis > -0.3 else main_c, alpha, Color(0, 0, 0, 0), CrystalKind.BATTLE_NOTCHED, 1)

	var hb_r: Vector3 = head_pos3 + Vector3(1.0, 8.5, 11.5)
	var hd_r: Vector3 = Vector3(-0.1, 0.66, 0.74).normalized()
	_draw_geode_crystal3d(canvas, hb_r, hd_r, 15.5, 3.5, flash_mix, spark_c if face_vis > -0.3 else main_c, alpha, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, 2)

	# Live blazing 3 eyes inside the chiseled sockets when facing viewer
	if sector != -2 and eye_c.a > 0.04:
		var side_shift: float = float(sector) * 2.2 if absi(sector) == 1 else 0.0
		var w_mul: float = 0.80 if absi(sector) == 1 else 1.0
		var eye_spread: float = 5.4 * w_mul
		var ec: Vector2 = hc.round() + Vector2(side_shift, 0.0)
		var le: Vector2 = (ec + Vector2(-eye_spread, -3.2)).round()
		var re: Vector2 = (ec + Vector2(eye_spread, -3.2)).round()
		_draw_pixel_line(canvas, le + Vector2(-3, -1), le + Vector2(2, 0), Color(eye_c, alpha), 2.0)
		_draw_pixel_line(canvas, re + Vector2(-2, 0), re + Vector2(3, -1), Color(eye_c, alpha), 2.0)
		canvas.draw_rect(Rect2(le - Vector2(1, 0), Vector2(3, 2)), Color(Color.WHITE, eye_c.a * alpha))
		canvas.draw_rect(Rect2(re - Vector2(2, 0), Vector2(3, 2)), Color(Color.WHITE, eye_c.a * alpha))
		# Vertical Forehead Sun-Eye flame wisp
		var te: Vector2 = (ec + Vector2(0.0, -11.5)).round()
		canvas.draw_rect(Rect2(te - Vector2(0, 2), Vector2(1, 4)), Color(Color.WHITE, eye_c.a * alpha))
		var wy: float = fposmod(_time * 16.0, 7.0)
		canvas.draw_rect(Rect2(te + Vector2(-1, -5 - wy), Vector2(2, 2)), Color(main_c, eye_c.a * alpha * (1.0 - wy / 7.0)))


func _draw_colossus_gauntlet(canvas: Node2D, hand3: Vector3, s_sign: float, side_i: int, mpal: Dictionary, flash_mix: float, alpha: float, blade_amt: float, blade_sweep: float, claw_open: float) -> void:
	var c: Vector2 = _project_v(hand3)
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var vein_c: Color = mpal["vein"] as Color

	# Outer 3 varied jagged quartz wrist/knuckle spurs OR Colossal ~86 px Textured Relic Greatblade!
	if blade_amt <= 0.05:
		var spur_kinds: Array[int] = [CrystalKind.BATTLE_NOTCHED, CrystalKind.CLEAVED_TABLE, CrystalKind.DRUSE_CROWN]
		for k_i: int in 3:
			var k_dir: Vector3 = Vector3(0.25 - float(k_i) * 0.15, s_sign * (0.68 - float(k_i) * 0.12), 0.72).normalized()
			var k_base: Vector3 = hand3 + Vector3(2.0 - float(k_i) * 3.0, s_sign * 9.5, 8.0 + float(k_i) * 2.5)
			_draw_geode_crystal3d(canvas, k_base, k_dir, 21.0 - float(k_i) * 3.5, 3.8, flash_mix, vein_c, alpha, main_c if k_i == 0 else Color(0, 0, 0, 0), spur_kinds[(k_i + side_i) % 3], k_i + side_i * 2)
	else:
		var p_fist: Vector2 = _project_v(hand3 + Vector3(3.0, 0.0, 4.0))
		var b_ang: float = _heading + blade_sweep * (1.0 if s_sign > 0.0 else -1.0)
		var b_dir3: Vector2 = Vector2.from_angle(b_ang)
		var b_dir2: Vector2 = Vector2(b_dir3.x, b_dir3.y * SQUASH).normalized()
		var b_ang2: float = b_dir2.angle()
		var b_flip_y: float = -1.0 if (cos(b_ang2) - sin(b_ang2)) < 0.0 else 1.0
		var gb_entry: Dictionary = _get_greatblade_canon(side_i)
		_stamp_entry(canvas, gb_entry, p_fist, alpha, flash_mix, main_c, spark_c, 0.22, b_ang2, Vector2(blade_amt, blade_amt * b_flip_y))

	# Asymmetric Heavy Textured Boulder Gauntlet (Left = Astrolabe Sun-Wheel `5`; Right = Broken Gold Strap + Quartz Seam `0` + `4`)!
	var g_relief: int = 5 if side_i == 0 else 0
	_draw_crag_boulder(canvas, c + Vector2(0.0, -4.0), 18.0, 16.5, s_sign * 0.22, 911 + side_i * 61, flash_mix, alpha, mpal, {"taper_bottom": 0.34, "relief": g_relief, "cracks": true, "ndl": 0.22 if side_i == 0 else -0.05})
	# Stepped golden knuckle ridge plate across upper fist (asymmetric left vs right!)
	_draw_crag_boulder(canvas, c + Vector2(-s_sign * 2.5, -12.0), 11.5, 5.0, -s_sign * 0.14, 947 + side_i * 29, flash_mix, alpha, mpal, {"gold": true, "cracks": false})

	# 4 Articulated 2-Segment Claws: Stone+Gold Proximal Knuckle Phalanx -> Varied Curved Quartz Talons!
	var claw_kinds: Array[int] = [
		CrystalKind.CLEAVED_TABLE, CrystalKind.BATTLE_NOTCHED, CrystalKind.CATHEDRAL_HEX, CrystalKind.BATTLE_NOTCHED,
	]
	for f_i: int in 4:
		var rel: float = float(f_i) - 1.5
		var spread: float = rel * lerpf(6.0, 8.6, claw_open)
		var knuckle3: Vector3 = hand3 + Vector3(4.0, spread * 0.86, -5.5)
		var kn2: Vector2 = _project_v(knuckle3)
		# Textured proximal stone/gold knuckle phalanx!
		_draw_crag_boulder(canvas, kn2, 4.2, 4.5, rel * 0.18, 1201 + side_i * 19 + f_i * 7, flash_mix, alpha, mpal, {"gold": f_i == 1, "cracks": false})
		# Distal curved/chipped sun-quartz talon angling slightly inward like predatory stone claws!
		var curve_in: float = -rel * 0.14 + rel * 0.30 * claw_open
		var f_dir3: Vector3 = Vector3(0.28, curve_in, -0.92).normalized()
		var talon_len: float = 15.5 if (f_i == 1 or f_i == 2) else 12.0
		var talon3: Vector3 = knuckle3 + Vector3(0.5, 0.0, -2.5)
		_draw_geode_crystal3d(canvas, talon3, f_dir3, talon_len, 3.0, flash_mix, main_c if f_i % 2 == 0 else QZ_3, alpha, Color(0, 0, 0, 0), claw_kinds[(f_i + side_i) % 4], f_i + side_i)


func _draw_detached_gauntlet_screen(canvas: Node2D, at_pos: Vector2, s_sign: float, side_i: int, mpal: Dictionary, flash_mix: float, alpha: float) -> void:
	var c: Vector2 = at_pos.round()
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var vein_c: Color = mpal["vein"] as Color
	_oval(canvas, c + Vector2(0.0, 19.0), Vector2(19.0, 7.0), Color(ST_OUT, 0.4 * alpha))
	# 3 varied crystal rocket-spurs radiating from flying gauntlet
	for s_i: int in 3:
		var ang: float = -PI * 0.5 + s_sign * (0.42 + float(s_i) * 0.36)
		_draw_crystal_2d(canvas, c, ang, 22.0 - float(s_i) * 3.5, 3.6, flash_mix, vein_c, alpha, spark_c, (s_i + side_i) % 5, s_i, false, 0.16)
	# Textured flying boulder fist + golden knuckle ridge
	_draw_crag_boulder(canvas, c, 18.5, 16.5, s_sign * 0.15, 977 + side_i * 31, flash_mix, alpha, mpal, {"taper_bottom": 0.3, "relief": 2 if side_i == 0 else 4, "cracks": true})
	_draw_crag_boulder(canvas, c + Vector2(0.0, -10.0), 11.0, 4.8, 0.0, 991 + side_i * 17, flash_mix, alpha, mpal, {"gold": true, "cracks": false})
	# 4 articulated stone-knuckle + quartz-talon claws underneath
	for k: int in 4:
		var fx: float = (float(k) - 1.5) * 6.8
		var kn_p: Vector2 = c + Vector2(fx, 10.5)
		_draw_crag_boulder(canvas, kn_p, 4.0, 4.2, 0.0, 1300 + k * 11, flash_mix, alpha, mpal, {"cracks": false})
		var c_ang: float = PI * 0.5 - (float(k) - 1.5) * 0.12
		_draw_crystal_2d(canvas, kn_p + Vector2(0.0, 2.0), c_ang, 13.5 if (k == 1 or k == 2) else 11.0, 2.8, flash_mix, main_c, alpha, spark_c, (k + 1) % 5, k, false, 0.12)


# ==============================================================================
# STAGE 3 BAYER-TEXTURED SANDSTORM FUNNEL & ENGRAVED CELESTIAL ARMILLARY RINGS
# ==============================================================================
func _add_cyclone_parts(top_z: float, alpha: float, mpal: Dictionary, flash_mix: float) -> void:
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var bands: int = 12
	for b_i: int in bands:
		var frac: float = float(b_i) / float(bands - 1)
		var z_h: float = lerpf(3.0, maxf(24.0, top_z + 6.0), frac)
		var rad: float = lerpf(16.0, 48.0, pow(frac, 0.74)) + sin(_time * 4.5 + float(b_i) * 0.85) * 3.0
		var phase: float = _time * (4.8 + (1.0 - frac) * 2.4) + float(b_i) * 1.15
		for arc_i: int in 2:
			var ang0: float = phase + float(arc_i) * PI
			var ang1: float = ang0 + 2.25
			var mid_ang: float = (ang0 + ang1) * 0.5
			var p_mid3: Vector3 = Vector3(cos(mid_ang) * rad * 0.78, sin(mid_ang) * rad, z_h)
			_add_part(_depth_v(p_mid3), _part_cyclone_ribbon.bind(ang0, ang1, rad, z_h, frac, b_i, alpha, main_c, spark_c))

	for k: int in 8:
		var kf: float = float(k) / 8.0
		var b_z: float = lerpf(8.0, maxf(26.0, top_z), kf)
		var b_r: float = lerpf(18.0, 48.0, kf)
		var b_ang: float = _time * 3.1 + float(k) * (TAU / 8.0)
		var b3: Vector3 = Vector3(cos(b_ang) * b_r * 0.8, sin(b_ang) * b_r, b_z)
		_add_part(_depth_v(b3), _part_cyclone_debris.bind(b3, k, b_ang, flash_mix, alpha, mpal))


func _part_cyclone_ribbon(ang0: float, ang1: float, rad: float, z_h: float, frac: float, b_i: int, alpha: float, main_c: Color, spark_c: Color) -> void:
	var segs: int = 5
	for s: int in segs:
		var t0: float = lerpf(ang0, ang1, float(s) / float(segs))
		var t1: float = lerpf(ang0, ang1, float(s + 1) / float(segs))
		var a3: Vector3 = Vector3(cos(t0) * rad * 0.78, sin(t0) * rad, z_h + float(s) * 0.6)
		var b3: Vector3 = Vector3(cos(t1) * rad * 0.78, sin(t1) * rad, z_h + float(s + 1) * 0.6)
		var a2: Vector2 = _project_v(a3)
		var b2: Vector2 = _project_v(b3)
		var thick_h: float = 6.2 if frac > 0.32 else 4.4
		var lit: bool = a2.x < 0.0 or b2.x < 0.0
		var col_top: Color = SD_5 if lit else SD_3
		var col_mid: Color = (SD_4 if lit else SD_2).lerp(SD_5, frac * 0.35)
		if s == segs - 1 and b_i % 3 == 0:
			col_mid = spark_c
		elif s == 0:
			col_mid = SD_0
		elif b_i % 4 == 1 and s == 2:
			col_mid = main_c
		var ca: float = alpha * (0.92 if (b_i % 2 == 0) else 0.76)
		col_mid.a *= ca
		col_top.a *= ca
		var p_tl: Vector2 = (a2 + Vector2(0.0, -thick_h * 0.5)).round()
		var p_tr: Vector2 = (b2 + Vector2(0.0, -thick_h * 0.5)).round()
		var p_br: Vector2 = (b2 + Vector2(0.0, thick_h * 0.5)).round()
		var p_bl: Vector2 = (a2 + Vector2(0.0, thick_h * 0.5)).round()
		_body.draw_colored_polygon(PackedVector2Array([p_tl, p_tr, p_br, p_bl]), col_mid)
		if lit:
			_body.draw_line(p_tl, p_tr, col_top, 1.0)
		_body.draw_line(p_bl, p_br, Color(SD_0, ca * 0.85), 1.0)
		if (b_i + s) % 2 == 0:
			var mid_pt: Vector2 = a2.lerp(b2, 0.5).round()
			_body.draw_rect(Rect2(mid_pt + Vector2(-1, -1), Vector2(2, 1)), Color(QZ_3 if (b_i + s) % 4 == 0 else SD_5, ca))


func _part_cyclone_debris(b3: Vector3, k: int, b_ang: float, flash_mix: float, alpha: float, mpal: Dictionary) -> void:
	var c2: Vector2 = _project_v(b3)
	var kind_mod: int = k % 4
	var sub_seed: int = k % 2
	if kind_mod == 0:
		_draw_crag_boulder(_body, c2, 6.0, 5.0, b_ang, 1020 + sub_seed * 13, flash_mix, alpha, mpal, {"relief": 1, "cracks": true})
	elif kind_mod == 1:
		_draw_geode_crystal3d(_body, b3, Vector3(0.2, 0.25, 0.94), 13.0, 3.0, flash_mix, mpal["main"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.TWIN_CLUSTER, k)
	elif kind_mod == 2:
		# Broken golden temple pillar / astrolabe shard swirling in the storm!
		_draw_crag_boulder(_body, c2, 6.5, 4.5, b_ang, 1060 + sub_seed * 17, flash_mix, alpha, mpal, {"gold": true, "cracks": false})
	else:
		_draw_geode_crystal3d(_body, b3, Vector3(-0.25, 0.18, 0.95), 12.0, 3.2, flash_mix, mpal["spark"] as Color, alpha, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, k)


func _add_armillary_ring_parts(center3: Vector3, radius: float, tilt_x: float, spin: float, alpha: float, mpal: Dictionary, flash_mix: float, secondary: bool) -> void:
	if alpha <= 0.04:
		return
	var segs: int = 16
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
		var is_rune_node: bool = (i % 4 == 0)
		_add_part(_depth_v(pm), _part_armillary_seg.bind(p0, p1, pm, center3, i, is_rune_node, secondary, alpha, flash_mix, main_c, spark_c))


func _part_armillary_seg(p0: Vector3, p1: Vector3, pm: Vector3, center3: Vector3, seg_i: int, is_rune_node: bool, secondary: bool, alpha: float, flash_mix: float, main_c: Color, spark_c: Color) -> void:
	var s0: Vector2 = _project_v(p0)
	var s1: Vector2 = _project_v(p1)
	var span_s: Vector2 = s1 - s0
	if span_s.length_squared() < 0.25:
		return
	var perp: Vector2 = span_s.normalized().orthogonal()
	var hw: float = 2.8 if is_rune_node else 2.0
	var out_col: Color = Color(GD_OUT if secondary else ST_OUT, alpha)
	var poly_out: PackedVector2Array = PackedVector2Array([
		(s0 - perp * (hw + 1.0)).round(), (s1 - perp * (hw + 1.0)).round(),
		(s1 + perp * (hw + 1.0)).round(), (s0 + perp * (hw + 1.0)).round(),
	])
	var poly: PackedVector2Array = PackedVector2Array([
		(s0 - perp * hw).round(), (s1 - perp * hw).round(),
		(s1 + perp * hw).round(), (s0 + perp * hw).round(),
	])
	_body.draw_colored_polygon(poly_out, out_col)
	var lit_seg: bool = s0.y < center3.z * -0.5 or s0.x < 0.0
	var col_face: Color = (GD_2 if secondary else ST_3) if lit_seg else (GD_1 if secondary else ST_1)
	_body.draw_colored_polygon(poly, Color(col_face.lerp(Color.WHITE, flash_mix), alpha))
	if lit_seg:
		_body.draw_line(poly[0], poly[1], Color(GD_3, alpha), 1.0)
	var sm: Vector2 = _project_v(pm).round()
	if seg_i % 2 == 1:
		_body.draw_line((sm - perp * 1.5).round(), (sm + perp * 1.5).round(), Color(GD_0 if secondary else ST_0, alpha * 0.9), 1.0)
	if is_rune_node:
		_body.draw_rect(Rect2(sm - Vector2(3, 3), Vector2(6, 6)), Color(GD_OUT, alpha))
		_body.draw_rect(Rect2(sm - Vector2(2, 2), Vector2(4, 4)), Color(GD_2, alpha))
		_body.draw_rect(Rect2(sm - Vector2.ONE, Vector2(2, 2)), Color(spark_c if secondary else main_c, alpha))
		_body.draw_rect(Rect2(sm, Vector2.ONE), Color(Color.WHITE, alpha))


# ==============================================================================
# MONUMENTAL WIND-RIPPLED DORMANT SAND-BURIED RUIN MOUND (~108x72 px)
# ==============================================================================
func _draw_dormant_monument(mpal: Dictionary, flash_mix: float) -> void:
	var ch: float = clampf(soul_charge, 0.0, 1.0)
	var main_c: Color = mpal["main"] as Color
	var spark_c: Color = mpal["spark"] as Color
	var pulse: float = 0.55 + 0.45 * sin(_time * (2.5 + ch * 5.0))
	var vib: Vector2 = Vector2(sin(_time * 28.0) * ch * 0.9, 0.0).round() if ch > 0.35 else Vector2.ZERO

	# Per-pixel wind-rippled Bayer-dithered sand dune blending organically into desert sand
	_oval(_body, Vector2(0.0, 3.0), Vector2(54.0, 19.0), Color(ST_OUT, 0.28))
	var dune_entry: Dictionary = _get_dormant_dune_entry()
	_stamp_entry(_body, dune_entry, Vector2(0.0, -3.0), 1.0, 0.0, Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0)

	if ch > 0.04:
		var line_c: Color = Color(main_c, ch * (0.68 + 0.32 * pulse))
		for k: int in 8:
			var ang: float = float(k) / 8.0 * TAU + 0.25
			var p_in: Vector2 = Vector2(cos(ang) * 12.0, sin(ang) * 5.0 - 5.0)
			var p_mid: Vector2 = Vector2(cos(ang + 0.14) * (20.0 + ch * 8.0), sin(ang + 0.14) * (7.5 + ch * 3.0) - 3.5)
			var p_out: Vector2 = Vector2(cos(ang) * (28.0 + ch * 18.0), sin(ang) * (10.0 + ch * 7.0) - 2.0)
			_draw_pixel_line(_body, p_in, p_mid, line_c, 2.0)
			_draw_pixel_line(_body, p_mid, p_out, line_c, 1.0)

	# Half-sunk asymmetric weathered shoulders & varied raw quartz clusters jutting out of the sand
	var l_sh3: Vector3 = Vector3(-4.0, -29.0, 4.0) + Vector3(vib.x, 0, 0)
	var r_sh3: Vector3 = Vector3(5.0, 28.0, 2.0) + Vector3(vib.x, 0, 0)
	_draw_crag_boulder(_body, _project_v(l_sh3), 16.5, 13.5, -0.32, 1111, flash_mix, 1.0, mpal, {"relief": 3, "cracks": ch > 0.12})
	_draw_crag_boulder(_body, _project_v(r_sh3), 15.5, 12.5, 0.38, 1117, flash_mix, 1.0, mpal, {"relief": 2, "cracks": ch > 0.12})
	_draw_geode_crystal3d(_body, l_sh3 + Vector3(-2.0, -4.0, 8.0), Vector3(-0.25, -0.45, 0.85), 25.0, 4.6, flash_mix, Color(main_c, maxf(0.15, ch)), 1.0, Color(0, 0, 0, 0), CrystalKind.TWIN_CLUSTER, 1)
	_draw_geode_crystal3d(_body, l_sh3 + Vector3(3.0, 2.0, 6.0), Vector3(0.1, -0.25, 0.96), 16.5, 3.2, flash_mix, Color(main_c, maxf(0.15, ch)), 1.0, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, 0)
	_draw_geode_crystal3d(_body, r_sh3 + Vector3(1.0, 4.0, 7.0), Vector3(0.15, 0.48, 0.86), 23.0, 4.4, flash_mix, Color(main_c, maxf(0.15, ch)), 1.0, Color(0, 0, 0, 0), CrystalKind.DRUSE_CROWN, 2)

	# Giant buried textured obelisk head + asymmetric ancient crown shards at dune crest
	var h3: Vector3 = Vector3(3.0 + vib.x, 0.0, 16.0 + ch * 5.0)
	_draw_archon_obelisk_visage(_body, h3, Color(main_c, ch), main_c, spark_c, flash_mix, 1.0)
	_draw_geode_crystal3d(_body, h3 + Vector3(-4.0, -14.0, 16.0), Vector3(-0.1, -0.25, 0.96), 19.0, 3.4, flash_mix, Color(spark_c, maxf(0.2, ch)), 1.0, Color(0, 0, 0, 0), CrystalKind.BATTLE_NOTCHED, 2)
	_draw_geode_crystal3d(_body, h3 + Vector3(-4.0, 0.0, 19.0), Vector3(-0.08, 0.0, 0.99), 27.0, 4.5, flash_mix, Color(spark_c, maxf(0.2, ch)), 1.0, Color(0, 0, 0, 0), CrystalKind.CATHEDRAL_HEX, 0, true)
	_draw_geode_crystal3d(_body, h3 + Vector3(-4.0, 14.0, 16.0), Vector3(-0.1, 0.25, 0.96), 18.0, 3.5, flash_mix, Color(spark_c, maxf(0.2, ch)), 1.0, Color(0, 0, 0, 0), CrystalKind.CLEAVED_TABLE, 1)

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
# 4-BEAT EPIC DEATH CHOREOGRAPHY DRAW HELPERS (CLEAVED OBELISK, GOD-RAYS, SUPERNOVA)
# ==============================================================================
func _part_cleaved_obelisk_death(head_pos3: Vector3, split_q: float, fall_q: float, main_c: Color, spark_c: Color, flash_mix: float, alpha: float) -> void:
	var hc: Vector2 = _project_v(head_pos3)
	var sep_x: float = 6.0 + split_q * 28.0
	var drop_y: float = fall_q * 6.0
	var l_pos: Vector2 = hc + Vector2(-sep_x, drop_y)
	var r_pos: Vector2 = hc + Vector2(sep_x, drop_y + 2.0 * split_q)
	var l_rot: float = -0.62 * split_q
	var r_rot: float = 0.68 * split_q

	# Ground shadows beneath the crashing cleaved obelisk halves once near desert sand
	if fall_q > 0.55:
		var sh_a: float = smoothstep(0.55, 0.95, fall_q) * 0.36 * alpha
		_oval(_body, l_pos + Vector2(0.0, 14.0), Vector2(14.0, 5.0), Color(ST_OUT, sh_a))
		_oval(_body, r_pos + Vector2(0.0, 14.0), Vector2(14.0, 5.0), Color(ST_OUT, sh_a))

	# Left & Right Horned Obelisk Halves with glowing cleaved sun-quartz interior!
	var l_entry: Dictionary = _get_cleaved_head_half_entry(0)
	var r_entry: Dictionary = _get_cleaved_head_half_entry(1)
	_stamp_entry(_body, l_entry, l_pos, alpha, flash_mix, spark_c, Color.WHITE, 0.28, l_rot, Vector2.ONE)
	_stamp_entry(_body, r_entry, r_pos, alpha, flash_mix, spark_c, Color.WHITE, 0.28, r_rot, Vector2.ONE)

	# Brow-horns tumbling attached to each cleaved half
	_draw_crystal_2d(_body, l_pos + Vector2(-6.0, -10.0).rotated(l_rot), -2.25 + l_rot, 20.0, 3.3, flash_mix, spark_c, alpha, main_c, CrystalKind.BATTLE_NOTCHED, 1)
	_draw_crystal_2d(_body, r_pos + Vector2(6.0, -10.0).rotated(r_rot), -0.88 + r_rot, 15.5, 3.5, flash_mix, spark_c, alpha, main_c, CrystalKind.CLEAVED_TABLE, 2)


func _draw_death_god_rays(canvas: Node2D, origin: Vector2, intensity: float, main_c: Color, spark_c: Color, is_glow: bool) -> void:
	var rays: int = 10
	var base_rot: float = _time * 1.15
	var alpha_k: float = intensity * (0.44 if is_glow else 0.78)
	for i: int in rays:
		var ang: float = base_rot + float(i) / float(rays) * TAU + sin(float(i) * 2.1 + _time * 3.0) * 0.08
		var r_len: float = (62.0 + float(i % 3) * 24.0) * (0.55 + 0.55 * intensity)
		var dir: Vector2 = Vector2.from_angle(ang)
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var w0: float = maxf(1.5, 2.0 + intensity * 2.2)
		var w1: float = maxf(2.0, (7.5 + float(i % 2) * 3.5) * intensity)
		var p_a: Vector2 = origin + dir * 6.0 - perp * w0
		var p_b: Vector2 = origin + dir * 6.0 + perp * w0
		var p_c: Vector2 = origin + dir * r_len + perp * w1
		var p_d: Vector2 = origin + dir * r_len - perp * w1
		var col: Color = Color("ffe898") if (i % 2 == 0) else main_c.lerp(spark_c, 0.5)
		col.a = alpha_k * (0.85 if (i % 2 == 0) else 0.62)
		canvas.draw_colored_polygon(PackedVector2Array([p_a, p_b, p_c, p_d]), col)
		if not is_glow and i % 2 == 0:
			canvas.draw_line((origin + dir * 5.0).round(), (origin + dir * (r_len * 0.82)).round(), Color(Color.WHITE, alpha_k * 0.92), 1.5)


func _draw_death_supernova(canvas: Node2D, origin: Vector2, nova_q: float, main_c: Color, spark_c: Color, is_glow: bool) -> void:
	var fade: float = pow(1.0 - nova_q, 1.35)
	if fade <= 0.02:
		return
	var expand: float = 1.0 - pow(1.0 - nova_q, 2.4)
	var rad_ring: float = lerpf(18.0, 146.0, expand)
	var ring_col: Color = Color("ffe898").lerp(main_c, nova_q * 0.55)
	ring_col.a = fade * (0.48 if is_glow else 0.88)

	# Expanding elliptical 3/4 solar shock-halo + crisp inner white core flash
	var ring_pts: PackedVector2Array = PackedVector2Array()
	var segs: int = 28
	ring_pts.resize(segs + 1)
	for s: int in segs + 1:
		var a: float = float(s) / float(segs) * TAU
		ring_pts[s] = (origin + Vector2(cos(a) * rad_ring, sin(a) * rad_ring * 0.78)).round()
	canvas.draw_polyline(ring_pts, ring_col, 4.0 if is_glow else 2.5, false)

	if nova_q < 0.55:
		var core_fade: float = 1.0 - (nova_q / 0.55)
		var core_r: float = lerpf(38.0, 8.0, nova_q / 0.55)
		_oval(canvas, origin, Vector2(core_r * 1.25, core_r), Color(spark_c, core_fade * (0.55 if is_glow else 0.75)))
		_oval(canvas, origin, Vector2(core_r * 0.65, core_r * 0.55), Color(Color.WHITE, core_fade * (0.75 if is_glow else 0.95)))

	# 12 Razor-sharp diamond supernova spikes piercing across the screen!
	for k: int in 12:
		var s_ang: float = float(k) / 12.0 * TAU + 0.18
		var dir: Vector2 = Vector2.from_angle(s_ang)
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var spike_len: float = (128.0 if (k % 3 == 0) else 78.0) * lerpf(0.35, 1.15, expand)
		var inner_d: float = nova_q * 36.0
		if spike_len <= inner_d + 6.0:
			continue
		var mid_d: float = lerpf(inner_d, spike_len, 0.28)
		var hw: float = (4.8 if (k % 3 == 0) else 2.8) * fade
		var sp_c: Color = Color.WHITE if (k % 3 == 0) else (Color("ffe488") if (k % 2 == 0) else main_c)
		sp_c.a = fade * (0.52 if is_glow else 0.94)
		if hw < 1.1:
			canvas.draw_line(origin + dir * inner_d, origin + dir * spike_len, sp_c, 1.5)
		else:
			var sp_poly: PackedVector2Array = PackedVector2Array([
				origin + dir * inner_d,
				origin + dir * mid_d + perp * hw,
				origin + dir * spike_len,
				origin + dir * mid_d - perp * hw,
			])
			canvas.draw_colored_polygon(sp_poly, sp_c)


func _draw_death_dissolution_motes(canvas: Node2D, main_c: Color, spark_c: Color, diss_q: float) -> void:
	var count: int = 44
	for i: int in count:
		var seed_f: float = float(i) * 1.618034
		var local_q: float = clampf((diss_q - fposmod(seed_f * 0.29, 0.34)) / 0.66, 0.0, 1.0)
		if local_q <= 0.01 or local_q >= 0.99:
			continue
		var swirl_a: float = float(i) * 2.399 + local_q * 3.8
		var rad: float = lerpf(78.0 * (0.25 + 0.75 * fposmod(seed_f, 1.0)), 10.0, local_q)
		var rise_y: float = -local_q * lerpf(56.0, 168.0, fposmod(seed_f * 1.7, 1.0))
		var pt: Vector2 = Vector2(cos(swirl_a) * rad, sin(swirl_a) * rad * SQUASH - 8.0 + rise_y).round()
		var ma: float = sin(local_q * PI) * 0.95
		var col: Color = Color("ffe898") if (i % 3 == 0) else (Color("78f4e6") if (i % 3 == 1) else spark_c.lerp(main_c, 0.5))
		var sz: Vector2 = Vector2(3, 3) if (i % 6 == 0) else (Vector2(2, 2) if (i % 2 == 0) else Vector2(2, 1))
		canvas.draw_rect(Rect2(pt, sz), Color(col, ma))
		if i % 6 == 0:
			canvas.draw_rect(Rect2(pt + Vector2.ONE, Vector2.ONE), Color(Color.WHITE, ma))


# ==============================================================================
# UNSHADED ADDITIVE GLOW PASS (`Glow` — PIXEL-MATCHED VEIN & RUNE STAMPS)
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
			var g_a: float = ch * (0.12 + 0.06 * sin(_time * 3.5))
			_oval(_glow, Vector2(0.0, -14.0), Vector2(28.0 * ch + 6.0, 14.0 * ch + 4.0), Color(main_c, g_a))
			_oval(_glow, Vector2(0.0, -18.0), Vector2(9.0, 7.0), Color(spark_c, g_a * 1.25))
			var had_xf_d: bool = false
			for gs: Dictionary in _glow_stamps:
				if bool(gs.get("has_xf", false)):
					_glow.draw_set_transform_matrix(gs["xform"] as Transform2D)
					had_xf_d = true
				elif had_xf_d:
					_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					had_xf_d = false
				_glow.draw_texture(gs["tex"] as Texture2D, gs["pos"] as Vector2, gs["col"] as Color)
			if had_xf_d:
				_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	var kp: Dictionary = _last_kp if not _last_kp.is_empty() else _compute_rig_pose()
	var is_dying: bool = (_pose == Pose.DEAD)
	var dead_p: float = float(kp.get("dead_p", 0.0))
	var awaken_t: float = float(kp["awaken_t"])
	var dead_t: float = float(kp["dead_t"])
	var alpha: float = clampf((1.0 - dead_t * 0.98) * clampf(awaken_t * 1.3, 0.0, 1.0), 0.0, 1.0)

	# 1) Pixel-for-pixel glowing rock fissures, carved cartouches, fuller runes & crystal inclusions!
	if alpha > 0.03:
		var had_xf: bool = false
		for gs: Dictionary in _glow_stamps:
			if bool(gs.get("has_xf", false)):
				_glow.draw_set_transform_matrix(gs["xform"] as Transform2D)
				had_xf = true
			elif had_xf:
				_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				had_xf = false
			_glow.draw_texture(gs["tex"] as Texture2D, gs["pos"] as Vector2, gs["col"] as Color)
		if had_xf:
			_glow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if is_dying:
		var ray_int: float = smoothstep(0.04, 0.24, dead_p) * (1.0 - smoothstep(0.55, 0.60, dead_p))
		if ray_int > 0.03:
			_draw_death_god_rays(_glow, _core_local, ray_int, main_c, spark_c, true)
			_oval(_glow, _core_local, Vector2(30.0 * ray_int + 12.0, 32.0 * ray_int + 12.0), Color(spark_c, 0.26 * ray_int))
		if dead_p >= 0.56 and dead_p <= 0.84:
			_draw_death_supernova(_glow, Vector2(0.0, -96.0), clampf((dead_p - 0.56) / 0.28, 0.0, 1.0), main_c, spark_c, true)
		if dead_p >= 0.62:
			_draw_death_dissolution_motes(_glow, main_c, spark_c, clampf((dead_p - 0.62) / 0.38, 0.0, 1.0))
		return

	if alpha <= 0.04:
		return

	var beam_charge: float = float(kp["beam_charge"])
	var pulse: float = 0.86 + 0.14 * sin(_time * 4.2)
	var boost: float = 1.0 + beam_charge * 0.45 + prism_release * 0.15 + storm_ascension * 0.22

	# 2) Restrained heart/seal aura (crisp in bright desert noon, radiant in night darkness)
	_oval(_glow, Vector2.ZERO, Vector2(44.0, 16.0), Color(main_c, 0.08 * alpha * pulse))
	_oval(_glow, _core_local, Vector2(18.0, 20.0), Color(main_c, 0.12 * alpha * boost))
	_oval(_glow, _core_local, Vector2(9.0, 11.0), Color(core_c, 0.20 * alpha * boost))
	_glow.draw_rect(Rect2(_core_local.round() - Vector2(2, 4), Vector2(5, 8)), Color(Color.WHITE, 0.38 * alpha * boost))

	# 3) 3 Blazing Eyes crisp unlit pinpoints
	if _forward.y > -0.32:
		var lean: float = float(kp["lean"])
		var head_z: float = float(kp["head_z"])
		var hc: Vector2 = _project(lean + 4.5, 0.0, head_z).round()
		_glow.draw_rect(Rect2(hc + Vector2(-7, -4), Vector2(4, 2)), Color(eye_c, 0.28 * alpha))
		_glow.draw_rect(Rect2(hc + Vector2(4, -4), Vector2(4, 2)), Color(eye_c, 0.28 * alpha))
		_glow.draw_rect(Rect2(hc + Vector2(-1, -14), Vector2(2, 5)), Color(spark_c, 0.34 * alpha))

	if _pose == Pose.AWAKEN:
		var ap: float = _pose_progress()
		_oval(_glow, Vector2(0.0, -54.0 * ap), Vector2(42.0, 28.0), Color(spark_c, sin(ap * PI) * 0.18))
