class_name AurelithArena
extends Node
## Das Singende Becken (`Tile 626, 69`, Region 33 — docs/enemies/boss_aurelith.md, Paket 2):
## Open-world desert boss basin for `Aurelith, Herz des Sonnenquarzes`, present from Day 1 with zero quest lock.
##
## Lifecycle (host-authoritative, replicated to all peers):
## - `DORMANT`: Half-buried monument (`AurelithRig` in `Pose.DORMANT`) rests in the center of 6 radial white
##   ground-quartz veins surrounded by 6 `QuartzGolem` sentinels (all 3 variants, `pickaxe_override = 1.0`).
##   Each slain sentinel streams its stored solar-ley charge into the monument (`soul_charge = 1/6 .. 6/6`),
##   igniting its radial vein, raising resonant hum, levitating sand/pebbles, and escalating remaining sentinels.
## - `SILENCE`: When the 6th sentinel falls, `0.85 s` of eerie dead silence hushes even the desert wind while
##   six soul orbs hover and contract along the veins.
## - `BOSS`: All 6 veins surge into the core; `Aurelith` tears out of the sand (`Pose.AWAKEN` -> `Pose.FAULT_SLAM`)
##   and slams both colossal fists into the floor, driving up a 36-tooth sintered-quartz & whirling sandstorm
##   perimeter barrier (`290 x 210 px` 3/4 ellipse + `WallClimb` lock).
## - `FREE`: Defeated (`released = true`, saved in `SaveGame`); the barrier subsides back into open sand.
## - Wipe / Empty Reset: If no living player stays within `leash` (`640 px`) for `reset_seconds` (`8.0 s`),
##   the barrier crumbles, any active boss/sentinels clear, `soul_charge` resets to `0`, and the 6 sentinels return.

enum Stage {
	DORMANT,
	SILENCE,
	BOSS,
	FREE,
}

const BOSS_SCENE_PATH: String = "res://src/entities/enemies/desert_boss/aurelith.tscn"
const RIG_SCENE: PackedScene = preload("res://src/entities/enemies/desert_boss/aurelith_rig.tscn")
const HARP_WAV: String = "res://assets/audio/observatory/wind_harp.wav"
const SURGE_WAV: String = "res://assets/audio/observatory/storm_surge.wav"
const CHIME_WAV: String = "res://assets/audio/observatory/ocular_chime.wav"
const SLAM_WAV: String = "res://assets/audio/golem/shock_erupt.wav"

const TICK: float = 0.20
const DESPAWN_IDLE_RANGE: float = 740.0
const DECAL_HALF_W: int = 184
const DECAL_HALF_H: int = 130

static var _CACHED_DECAL_BASE: ImageTexture = null
static var _CACHED_SEAL_GLOW: ImageTexture = null
static var _CACHED_VEIN_GLOWS: Array[ImageTexture] = []
static var _TOOTH_TEX_CACHE: Array[Dictionary] = []

var world: WorldLevel
var boss: Aurelith
var stage: Stage = Stage.DORMANT
var released: bool = false
var sealed: bool = false
var killed_count: int = 0

var _spec: Dictionary = {}
var _center: Vector2 = Vector2.ZERO
var _center_tile: Vector2i = Vector2i(626, 69)
var _arena_radii: Vector2 = Vector2(290.0, 210.0)
var _vein_pads: Array[Vector2] = []
var _guardian_specs: Array[Dictionary] = []
var _reserved: Dictionary = {}

var _guardians: Array[Node2D] = []
var _slot_dead: Array[bool] = []
var _guardians_spawned: bool = false
var _clock: float = 0.0
var _away: float = 0.0
var _silence_left: float = -1.0
var _rematch_in: float = -1.0

var _display_charge: float = 0.0
var _wall_grow: float = 0.0
var _time: float = 0.0
var _silence_fx_t: float = 0.0
var _weather_ducked_db: float = 0.0

var _surface_patch: BasinSurfacePatch
var _decal_root: Node2D
var _decal_body: Node2D
var _decal_glow: Node2D
var _monument_root: Node2D
var _monument_rig: AurelithRig
var _monument_body: StaticBody2D
var _monument_light: NightLight
var _hologram: AurelithHologram
var _hum_player: AudioStreamPlayer2D
var _sfx_player: AudioStreamPlayer2D
var _wall_root: Node2D
var _wall_bodies: Array[StaticBody2D] = []
var _wall_teeth: Array[Dictionary] = [] ## {root, base, glow, angle, base_pos}
var _storm_berm_fx: Node2D
var _storm_fx: Node2D
var _soul_fx: Node2D

var _soul_streams: Array[Dictionary] = [] ## {from, age, dur, slot}
var _float_pebbles: Array[Dictionary] = [] ## {pos, z, vz, col, sz, life, max_life}
var _storm_ribbons: Array[Dictionary] = [] ## {ang, speed, rad_k, z, span, kind}
var _storm_streaks: Array[Dictionary] = [] ## {ang, speed, rad_k, z, len, kind}


func setup(p_world: WorldLevel) -> Dictionary:
	world = p_world
	name = "AurelithArena"
	add_to_group("aurelith_arena")
	add_to_group("climb_block")
	_spec = DataRegistry.table("aurelith_arena")
	var tile_arr: Array = _spec.get("tile", [626, 69]) as Array
	_center_tile = Vector2i(int(tile_arr[0]), int(tile_arr[1]))
	_center = Vector2(float(_center_tile.x) * 16.0 + 8.0, float(_center_tile.y) * 16.0 + 8.0)
	_arena_radii = Vector2(
		float(_spec.get("arena_rx", 290.0)),
		float(_spec.get("arena_ry", 210.0))
	)
	_guardian_specs.clear()
	_vein_pads.clear()
	_slot_dead.clear()
	_guardians.clear()
	for g_v: Variant in _spec.get("guardians", []) as Array:
		var gd: Dictionary = g_v as Dictionary
		var off: Array = gd.get("offset", [0, 80]) as Array
		var rel: Vector2 = Vector2(float(off[0]), float(off[1]))
		_guardian_specs.append({
			"offset": rel,
			"variant": int(gd.get("variant", 0)),
			"dormant": bool(gd.get("dormant", false)),
		})
		_vein_pads.append(_center + rel)
		_slot_dead.append(false)
		_guardians.append(null)

	_compute_reserved_cells()
	_ensure_baked_art()
	_register_surface_patch()
	_build_decal()
	_build_monument()
	_build_perimeter_wall()
	_build_fx_layers()
	_init_storm_streaks()
	return _reserved


func _ready() -> void:
	if multiplayer != null and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_ask_host.call_deferred()


func reserved_cells() -> Dictionary:
	return _reserved


func basin_position() -> Vector2:
	return _center


func arena_radii() -> Vector2:
	return _arena_radii


func hologram() -> AurelithHologram:
	return _hologram


func boss_present() -> bool:
	if not is_inside_tree():
		return false
	for node: Node in get_tree().get_nodes_in_group("bosses"):
		if node is Aurelith and not node.is_queued_for_deletion():
			return true
	return false


func active_guardian_count() -> int:
	var c: int = 0
	for g: Node2D in _guardians:
		if g != null and is_instance_valid(g) and not g.is_queued_for_deletion():
			var hc: HealthComponent = g.get_node_or_null("HealthComponent") as HealthComponent
			if hc != null and hc.current > 0.0:
				c += 1
	return c


func soul_charge_ratio() -> float:
	return clampf(float(killed_count) / float(maxi(_guardian_specs.size(), 1)), 0.0, 1.0)


func set_preview_hidden(hidden: bool) -> void:
	set_process(not hidden)
	set_physics_process(not hidden)
	if _decal_root != null:
		_decal_root.visible = not hidden
	if _monument_root != null:
		_monument_root.visible = not hidden
	if _monument_body != null:
		_monument_body.set_deferred("collision_layer", 0 if hidden else 1)
	if _wall_root != null:
		_wall_root.visible = not hidden
	if _storm_berm_fx != null:
		_storm_berm_fx.visible = not hidden
	if _storm_fx != null:
		_storm_fx.visible = not hidden
	if _soul_fx != null:
		_soul_fx.visible = not hidden
	if _hologram != null and hidden:
		_hologram.set_active(false)
	if hidden:
		_clear_guardians()


## Asked by `WallClimb` before a climb: while the basin perimeter is sealed, nobody climbs in or out.
func blocks_climb(from: Vector2, to: Vector2) -> bool:
	if not sealed:
		return false
	var pad_radii: Vector2 = _arena_radii + Vector2(54.0, 44.0)
	var d_from: Vector2 = (from - _center) / pad_radii
	var d_to: Vector2 = (to - _center) / pad_radii
	return d_from.length_squared() <= 1.0 or d_to.length_squared() <= 1.0


func _compute_reserved_cells() -> void:
	var clear_r: int = int(_spec.get("clear_radius", 20))
	var blocked: Dictionary = {}
	var stones: Dictionary = {}
	for dy: int in range(-clear_r, clear_r + 1):
		for dx: int in range(-clear_r, clear_r + 1):
			# Elliptical basin reservation so generated cacti/boulders/wild golem homes never intrude
			var nx: float = float(dx) / float(clear_r)
			var ny: float = float(dy) / (float(clear_r) * 0.78)
			if nx * nx + ny * ny <= 1.05:
				var cell: Vector2i = _center_tile + Vector2i(dx, dy)
				blocked[cell] = true
				if dx * dx + dy * dy <= 11 * 11:
					stones[cell] = true
	_reserved = {"blocked": blocked, "stones": stones}


func _register_surface_patch() -> void:
	_surface_patch = BasinSurfacePatch.new()
	_surface_patch.name = "AurelithSurfacePatch"
	_surface_patch.center = _center
	_surface_patch.vein_pads = _vein_pads.duplicate()
	add_child(_surface_patch)
	Terrain.patches.append(_surface_patch)
	_surface_patch.tree_exiting.connect(func() -> void: Terrain.patches.erase(_surface_patch))


# --- Pixel-Art Bakers (cached once across runs) --------------------------------------------------------------------


static func _bhash(x: int, y: int, salt: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + salt * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 <= 0.001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _ensure_baked_art() -> void:
	if _CACHED_DECAL_BASE == null:
		_bake_basin_decal()
	if _TOOTH_TEX_CACHE.is_empty():
		_bake_perimeter_teeth()


static func _shard_metric(p: Vector2, origin: Vector2, ang: float, length_px: float, base_hw: float) -> float:
	var rel: Vector2 = Vector2(p.x - origin.x, (p.y - origin.y) / 0.74)
	var ca: float = cos(ang)
	var sa: float = sin(ang)
	var u_par: float = rel.x * ca + rel.y * sa
	var u_perp: float = absf(-rel.x * sa + rel.y * ca)
	if u_par < -base_hw * 0.65 or u_par > length_px + 2.0:
		return 99.0
	var t: float = clampf(u_par / maxf(length_px, 1.0), 0.0, 1.0)
	var allow_hw: float = lerpf(base_hw, base_hw * 0.78, t / 0.62) if t < 0.62 else lerpf(base_hw * 0.78, 0.55, (t - 0.62) / 0.38)
	if u_par < 0.0:
		allow_hw = base_hw * clampf(1.0 + u_par / maxf(base_hw * 0.7, 1.0), 0.0, 1.0)
	return maxf(u_perp - allow_hw, u_par - length_px)


func _bake_basin_decal() -> void:
	var w: int = DECAL_HALF_W * 2
	var h: int = DECAL_HALF_H * 2
	var base_bytes: PackedByteArray = PackedByteArray()
	base_bytes.resize(w * h * 4)
	var seal_bytes: PackedByteArray = PackedByteArray()
	seal_bytes.resize(w * h * 4)
	var n_veins: int = _guardian_specs.size()
	var vein_arrays: Array[PackedByteArray] = []
	for i: int in n_veins:
		var vb: PackedByteArray = PackedByteArray()
		vb.resize(w * h * 4)
		vein_arrays.append(vb)

	var c_qz_out: Color = AurelithRig.QZ_OUT
	var c_qz0: Color = AurelithRig.QZ_0
	var c_qz1: Color = AurelithRig.QZ_1
	var c_qz2: Color = AurelithRig.QZ_2
	var c_qz3: Color = AurelithRig.QZ_3
	var c_qz4: Color = AurelithRig.QZ_4
	var c_st_out: Color = AurelithRig.ST_OUT
	var c_st0: Color = AurelithRig.ST_0
	var c_st1: Color = AurelithRig.ST_1
	var c_st2: Color = AurelithRig.ST_2
	var c_st3: Color = AurelithRig.ST_3
	var c_sd3: Color = AurelithRig.SD_3
	var c_gd0: Color = AurelithRig.GD_0
	var c_gd1: Color = AurelithRig.GD_1
	var c_gd2: Color = AurelithRig.GD_2
	var c_gd3: Color = AurelithRig.GD_3
	var c_turq_deep: Color = Color("3cc0c6")
	var c_turq: Color = Color("78f4e6")
	var c_gold: Color = Color("ffd86b")

	# Precompute 3-segment zig-zag crystal spines + side spurs + 7-shard druse rosettes for the 6 veins
	var vein_p0: Array[Vector2] = []
	var vein_p1: Array[Vector2] = []
	var vein_p2: Array[Vector2] = []
	var vein_end: Array[Vector2] = []
	var spur_a0: Array[Vector2] = []
	var spur_a1: Array[Vector2] = []
	var spur_b0: Array[Vector2] = []
	var spur_b1: Array[Vector2] = []
	var vein_angles: Array[float] = []
	for i: int in n_veins:
		var end_p: Vector2 = (_guardian_specs[i]["offset"] as Vector2)
		var dir: Vector2 = end_p.normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var sgn: float = 1.0 if (i % 2 == 0) else -1.0
		var p0: Vector2 = Vector2(dir.x * 26.0, dir.y * 20.0)
		var p1: Vector2 = end_p * 0.37 + perp * (10.5 * sgn)
		var p2: Vector2 = end_p * 0.71 - perp * (7.5 * sgn)
		vein_p0.append(p0)
		vein_p1.append(p1)
		vein_p2.append(p2)
		vein_end.append(end_p)
		vein_angles.append(atan2(end_p.y / 0.72, end_p.x))
		var sa_dir: Vector2 = (dir + perp * (0.68 * sgn)).normalized()
		var sb_dir: Vector2 = (dir - perp * (0.62 * sgn)).normalized()
		spur_a0.append(p1)
		spur_a1.append(p1 + Vector2(sa_dir.x * 16.0, sa_dir.y * 12.0))
		spur_b0.append(p2)
		spur_b1.append(p2 + Vector2(sb_dir.x * 14.0, sb_dir.y * 10.5))

	var q_owner: PackedByteArray = PackedByteArray()
	q_owner.resize(w * h)
	var q_facet: PackedByteArray = PackedByteArray()
	q_facet.resize(w * h)
	var q_spine: PackedFloat32Array = PackedFloat32Array()
	q_spine.resize(w * h)

	# Pass 1: Recessed pharaonic sun-compass altar (`ell_r <= 1.05`) + quartz outcrop mask
	for py: int in h:
		var dy: float = float(py - DECAL_HALF_H)
		for px: int in w:
			var dx: float = float(px - DECAL_HALF_W)
			var p: Vector2 = Vector2(dx, dy)
			var p_i: int = py * w + px
			var idx: int = p_i * 4
			var ell_v: Vector2 = Vector2(dx / 60.0, dy / 43.0)
			var ell_r: float = ell_v.length()
			var ang: float = atan2(ell_v.y, ell_v.x)
			var n1: float = _bhash(px / 3, py / 3, 17)
			var n2: float = _bhash(px, py, 53)
			var outer_lim: float = 1.02 + 0.035 * sin(ang * 12.0) + (_bhash(px / 2, py / 2, 23) - 0.5) * 0.045

			# 1) Full sunken Voronoi sandstone & inlaid gold sun-compass mosaic (revealed when Aurelith rises!)
			if ell_r <= outer_lim:
				var nw_inner: bool = (dx + dy * 1.25) < 0.0 ## sunken step: NW wall is shadowed, SE wall catches sun!
				var col: Color = c_st1
				if ell_r >= 0.91:
					if ell_r >= outer_lim - 0.03:
						col = c_st_out if nw_inner else c_sd3
					else:
						col = (c_st0 if n1 < 0.65 else c_st1) if nw_inner else (c_st3 if n1 < 0.6 else c_st2)
				elif ell_r >= 0.77:
					var border_ring: bool = ell_r > 0.89 or ell_r < 0.79
					var tooth_i: int = int(floorf((ang + PI) / TAU * 24.0))
					if border_ring:
						col = c_st_out
					elif tooth_i % 2 == 0:
						col = (c_gd3 if n2 < 0.35 else c_gd2) if not nw_inner else (c_gd2 if n2 < 0.55 else c_gd1)
						seal_bytes[idx] = int(roundi(c_gold.r * 255.0))
						seal_bytes[idx + 1] = int(roundi(c_gold.g * 255.0))
						seal_bytes[idx + 2] = int(roundi(c_gold.b * 255.0))
						seal_bytes[idx + 3] = 155
					else:
						col = c_st0 if nw_inner else c_st1
				elif ell_r >= 0.30:
					# Keystone sandstone slabs + 6 inlaid golden-turquoise ley channels
					var sec_f: float = (ang + PI) / TAU * 12.0
					var sec_edge: float = minf( sec_f - floorf(sec_f), 1.0 - (sec_f - floorf(sec_f)) )
					var ring_seam: bool = absf(ell_r - 0.54) < 0.020
					var channel_hit: bool = false
					var channel_core: bool = false
					for vi_c: int in n_veins:
						var da: float = absf(wrapf(ang - vein_angles[vi_c], -PI, PI))
						var arc_px: float = da * ell_r * 52.0
						if arc_px <= 2.4:
							channel_hit = true
							channel_core = arc_px <= 1.15
							break
					if channel_core:
						col = c_qz3.lerp(c_turq, 0.55)
						seal_bytes[idx] = int(roundi(c_turq.r * 255.0))
						seal_bytes[idx + 1] = int(roundi(c_turq.g * 255.0))
						seal_bytes[idx + 2] = int(roundi(c_turq.b * 255.0))
						seal_bytes[idx + 3] = 175
					elif channel_hit:
						col = c_gd1 if nw_inner else c_gd2
					elif ring_seam or sec_edge < 0.045:
						col = c_st_out
					else:
						var slab_h: float = _bhash(int(floorf(sec_f)), 0 if ell_r < 0.54 else 1, 89)
						col = c_st0 if slab_h < 0.28 else (c_st1 if slab_h < 0.72 else c_st2)
				else:
					# Central sunken sun-quartz prism socket (`ell_r < 0.30`)
					if ell_r >= 0.22:
						col = c_st_out if ell_r >= 0.275 else (c_gd2 if nw_inner else c_gd1)
					else:
						var hex_i: int = int(floorf((ang + PI) / TAU * 6.0)) % 6
						col = [c_qz4, c_qz3, c_qz1, c_qz0, c_qz2, c_qz3][hex_i]
						if ell_r < 0.08 or absf(sin(ang * 3.0)) < 0.16:
							col = c_qz4
							seal_bytes[idx] = int(roundi(c_gold.r * 255.0))
							seal_bytes[idx + 1] = int(roundi(c_gold.g * 255.0))
							seal_bytes[idx + 2] = int(roundi(c_gold.b * 255.0))
							seal_bytes[idx + 3] = 195

				base_bytes[idx] = int(roundi(col.r * 255.0))
				base_bytes[idx + 1] = int(roundi(col.g * 255.0))
				base_bytes[idx + 2] = int(roundi(col.b * 255.0))
				base_bytes[idx + 3] = 232

			# 2) Angular fractured quartz vein mask + 7-shard crystal rosette pads
			if ell_r < 0.44:
				continue
			var best_v: int = -1
			var best_m: float = 99.0
			var best_spine_d: float = 99.0
			var best_fac: int = 0
			var facet_cell_a: int = int(floorf(float(px * 2 + py) / 9.0))
			var facet_cell_b: int = int(floorf(float(py * 2 - px) / 9.0))
			var cell_ang_step: float = (_bhash(facet_cell_a, facet_cell_b, 131) - 0.5) * 3.4

			for vi: int in n_veins:
				var end_p: Vector2 = vein_end[vi]
				# Quick AABB reject per vein
				var min_vx: float = minf(0.0, end_p.x) - 34.0
				var max_vx: float = maxf(0.0, end_p.x) + 34.0
				var min_vy: float = minf(0.0, end_p.y) - 28.0
				var max_vy: float = maxf(0.0, end_p.y) + 28.0
				if p.x < min_vx or p.x > max_vx or p.y < min_vy or p.y > max_vy:
					continue

				var d0: float = _seg_dist(p, vein_p0[vi], vein_p1[vi])
				var d1: float = _seg_dist(p, vein_p1[vi], vein_p2[vi])
				var d2: float = _seg_dist(p, vein_p2[vi], end_p)
				var d_main: float = minf(d0, minf(d1, d2))
				var d_spurs: float = minf(_seg_dist(p, spur_a0[vi], spur_a1[vi]), _seg_dist(p, spur_b0[vi], spur_b1[vi]))
				var m_vein: float = minf(d_main - 4.8 + cell_ang_step, d_spurs - 2.5 + cell_ang_step * 0.55)

				# 7-shard angular crystal rosette under each sentinel
				var m_pad: float = 99.0
				var pad_Shard_id: int = 0
				if p.distance_squared_to(end_p) <= 32.0 * 32.0:
					for sk: int in 7:
						var s_ang: float = float(sk) * (TAU / 7.0) + float(vi) * 0.51 + (0.14 if sk % 2 == 0 else -0.11)
						var s_len: float = [24.0, 18.0, 22.0, 16.5, 23.0, 17.5, 20.5][sk]
						var s_hw: float = [6.4, 5.2, 6.0, 4.8, 6.2, 5.0, 5.6][sk]
						var sm: float = _shard_metric(p, end_p, s_ang, s_len, s_hw)
						if sm < m_pad:
							m_pad = sm
							pad_Shard_id = sk

				var m_tot: float = minf(m_vein, m_pad)
				if m_tot < best_m:
					best_m = m_tot
					best_v = vi
					best_spine_d = d_main
					if m_pad < m_vein:
						best_fac = pad_Shard_id
					else:
						best_fac = int(_bhash(facet_cell_a, facet_cell_b, 211 + vi) * 6.99)

			if best_v >= 0 and best_m <= 0.0:
				q_owner[p_i] = best_v + 1
				q_facet[p_i] = best_fac
				q_spine[p_i] = best_spine_d

	# Pass 2: Shade angular quartz facets with crisp 1-px mineral contours & SE elevation drop-ledge
	for py: int in range(2, h - 2):
		var dy: float = float(py - DECAL_HALF_H)
		for px: int in range(2, w - 2):
			var p_i: int = py * w + px
			var owner_id: int = q_owner[p_i]
			if owner_id == 0:
				continue
			var vi: int = owner_id - 1
			var idx: int = p_i * 4
			var dx: float = float(px - DECAL_HALF_W)
			var p: Vector2 = Vector2(dx, dy)

			var empty_n: bool = q_owner[p_i - w] == 0
			var empty_w: bool = q_owner[p_i - 1] == 0
			var empty_s: bool = q_owner[p_i + w] == 0
			var empty_e: bool = q_owner[p_i + 1] == 0
			var empty_s2: bool = q_owner[p_i + w * 2] == 0 or q_owner[p_i + w + 1] == 0
			var empty_nw2: bool = q_owner[p_i - w - 1] == 0

			var fac: int = q_facet[p_i]
			var diff_fac: bool = (
				q_facet[p_i - 1] != fac or q_facet[p_i - w] != fac
			) and not (empty_n or empty_w or empty_s or empty_e)

			var qcol: Color = c_qz2
			if empty_s or empty_e:
				# Crisp dark mineral drop-ledge on SE side so the crystal cluster visibly rises out of the sand
				qcol = c_qz_out
			elif empty_n or empty_w:
				# Cool slate-blue NW outer contour matching desert ground-quartz style
				qcol = c_qz0 if (px + py) % 3 == 0 else c_qz1
			elif empty_s2:
				# Vertical shadowed crystal thickness wall above the SE ledge
				qcol = c_qz0 if fac % 2 == 0 else c_qz1
			elif empty_nw2:
				# Crisp sunlit NW bevel!
				qcol = c_qz4
			elif diff_fac:
				# Internal crystal cleavage ridge between shards/plates
				qcol = c_qz4 if (fac % 2 == 0) else c_qz1
			else:
				qcol = [c_qz4, c_qz3, c_qz2, c_qz3, c_qz4, c_qz1, c_qz3][fac % 7]

			base_bytes[idx] = int(roundi(qcol.r * 255.0))
			base_bytes[idx + 1] = int(roundi(qcol.g * 255.0))
			base_bytes[idx + 2] = int(roundi(qcol.b * 255.0))
			base_bytes[idx + 3] = 250

			# Focused inner solar-ley fissure & hexagonal pad rune (never washes out the pad facets!)
			var end_p: Vector2 = vein_end[vi]
			var pad_ell_r: float = Vector2((p.x - end_p.x) / 11.5, (p.y - end_p.y) / 8.5).length()
			var spine_d: float = q_spine[p_i]
			var on_pad_rune: bool = absf(pad_ell_r - 0.88) <= 0.14 or pad_ell_r <= 0.24
			var on_vein_seam: bool = spine_d <= 1.75 and pad_ell_r > 0.92
			if (on_vein_seam or on_pad_rune) and not (empty_s or empty_e or empty_n or empty_w):
				var seam_t: float = clampf(1.0 - spine_d / 1.85, 0.0, 1.0) if on_vein_seam else 0.78
				var gcol: Color = c_turq_deep.lerp(c_turq, seam_t).lerp(c_gold, seam_t * 0.55)
				qcol = qcol.lerp(gcol, 0.42)
				base_bytes[idx] = int(roundi(qcol.r * 255.0))
				base_bytes[idx + 1] = int(roundi(qcol.g * 255.0))
				base_bytes[idx + 2] = int(roundi(qcol.b * 255.0))
				var va: PackedByteArray = vein_arrays[vi]
				va[idx] = int(roundi(gcol.r * 255.0))
				va[idx + 1] = int(roundi(gcol.g * 255.0))
				va[idx + 2] = int(roundi(gcol.b * 255.0))
				va[idx + 3] = int(roundi(lerpf(135.0, 195.0, seam_t)))

	_CACHED_DECAL_BASE = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, base_bytes))
	_CACHED_SEAL_GLOW = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, seal_bytes))
	_CACHED_VEIN_GLOWS.clear()
	for vi: int in n_veins:
		_CACHED_VEIN_GLOWS.append(ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, vein_arrays[vi])))


func _bake_perimeter_teeth() -> void:
	_TOOTH_TEX_CACHE.clear()
	var tw: int = 52
	var th: int = 56
	var ground_y: float = 47.0
	for kind: int in 8:
		var base_b: PackedByteArray = PackedByteArray()
		base_b.resize(tw * th * 4)
		var glow_b: PackedByteArray = PackedByteArray()
		glow_b.resize(tw * th * 4)
		# part_mask: 0=empty, 1=sand/masonry berm, 2=left crystal shard, 3=right crystal shard, 4=main central fang
		var part_mask: PackedByteArray = PackedByteArray()
		part_mask.resize(tw * th)

		var main_lean: float = [-3.4, 3.0, -1.5, 3.8, 0.4, -2.6, 2.2, -0.8][kind]
		var main_h: float = [42.0, 38.0, 44.0, 36.0, 41.0, 43.0, 39.0, 37.0][kind]
		var main_hw: float = [9.8, 8.8, 10.4, 8.6, 9.4, 10.0, 9.0, 9.6][kind]
		var left_h: float = [25.0, 29.0, 22.0, 27.0, 26.0, 20.0, 28.0, 24.0][kind]
		var right_h: float = [27.0, 21.0, 28.0, 23.0, 24.0, 29.0, 22.0, 26.0][kind]
		var left_lean: float = [-6.2, -4.8, -7.0, -5.2, -5.8, -4.4, -6.5, -5.0][kind]
		var right_lean: float = [5.8, 6.6, 4.6, 6.2, 5.4, 7.0, 4.8, 6.0][kind]
		var cleaved_tip: bool = kind in [1, 4, 6]

		# Precompute organic undulating bottom foot curve per X column (zero flat horizontal sticker line!)
		var foot_cols: PackedFloat32Array = PackedFloat32Array()
		foot_cols.resize(tw)
		for x: int in tw:
			var dx0: float = (float(x) - 26.0) / 22.5
			var arch: float = clampf(1.0 - dx0 * dx0, 0.0, 1.0)
			var step_jag: float = (_bhash(x / 3, kind, 71) - 0.5) * 3.4
			foot_cols[x] = ground_y + arch * 5.2 + step_jag

		for y: int in range(1, th - 1):
			for x: int in range(2, tw - 2):
				var yf_col: float = foot_cols[x] - float(y)
				if yf_col < 0.0:
					continue
				var yf: float = ground_y - float(y)
				var pi: int = y * tw + x

				# 1) Cracked Voronoi sandstone & drifted sand berm collar (`yf <= 14`)
				var berm_h: float = 13.5 + (_bhash(x / 4, kind, 19) - 0.5) * 4.0
				if yf <= berm_h:
					var bt: float = clampf(maxf(yf, 0.0) / berm_h, 0.0, 1.0)
					var berm_hw: float = lerpf(21.5, 13.0, bt * bt)
					if absf(float(x) - 26.0) <= berm_hw:
						part_mask[pi] = 1

				# 2) Left angled crystal fang
				if yf >= -1.0 and yf <= left_h:
					var lt: float = clampf(maxf(yf, 0.0) / left_h, 0.0, 1.0)
					var lcx: float = 16.5 + left_lean * lt
					var lhw: float = lerpf(6.4, 4.8, lt / 0.62) if lt < 0.62 else lerpf(4.8, 0.7, (lt - 0.62) / 0.38)
					if absf(float(x) - lcx) <= lhw:
						part_mask[pi] = 2

				# 3) Right angled crystal fang
				if yf >= -1.0 and yf <= right_h:
					var rt: float = clampf(maxf(yf, 0.0) / right_h, 0.0, 1.0)
					var rcx: float = 35.5 + right_lean * rt
					var rhw: float = lerpf(6.4, 4.8, rt / 0.62) if rt < 0.62 else lerpf(4.8, 0.7, (rt - 0.62) / 0.38)
					if absf(float(x) - rcx) <= rhw:
						part_mask[pi] = 3

				# 4) Central colossal sun-quartz obelisk fang (overlaps in front)
				if yf >= -2.0 and yf <= main_h:
					var mt: float = clampf(maxf(yf, 0.0) / main_h, 0.0, 1.0)
					var mcx: float = 26.0 + main_lean * mt
					var mhw: float = lerpf(main_hw, main_hw * 0.74, mt / 0.64) if mt < 0.64 else lerpf(main_hw * 0.74, 2.2 if cleaved_tip else 0.75, (mt - 0.64) / 0.36)
					if absf(float(x) - mcx) <= mhw:
						# Re-bury very bottom 5 px under masonry/sand collar scallops so the fang erupts OUT of the rock!
						var socket_h: float = 5.5 + sin(float(x) * 0.55 + float(kind)) * 2.4
						if yf > socket_h or part_mask[pi] == 0:
							part_mask[pi] = 4

		for y: int in range(1, th - 1):
			for x: int in range(1, tw - 1):
				var pi: int = y * tw + x
				var part: int = part_mask[pi]
				if part == 0:
					continue
				var idx: int = pi * 4
				var yf: float = ground_y - float(y)
				var yf_col: float = foot_cols[x] - float(y)
				var empty_l: bool = part_mask[pi - 1] == 0
				var empty_r: bool = part_mask[pi + 1] == 0
				var empty_u: bool = part_mask[pi - tw] == 0
				var empty_d: bool = part_mask[pi + tw] == 0
				var outer_edge: bool = empty_l or empty_r or empty_u or empty_d
				# Soften bottom sand-berm transition into the desert floor (no dark black line along the sand foot!)
				var sand_foot_edge: bool = empty_d and yf_col <= 2.2

				var col: Color = AurelithRig.QZ_2
				if sand_foot_edge:
					var sd_pick: float = _bhash(x, y, 97 + kind)
					col = AurelithRig.SD_3 if x < 26 else (AurelithRig.SD_2 if sd_pick < 0.6 else AurelithRig.SD_1)
					base_b[idx] = int(roundi(col.r * 255.0))
					base_b[idx + 1] = int(roundi(col.g * 255.0))
					base_b[idx + 2] = int(roundi(col.b * 255.0))
					base_b[idx + 3] = 215
					continue

				if outer_edge:
					if part == 1:
						col = AurelithRig.ST_1 if (empty_u and x < 26) else AurelithRig.ST_OUT
					else:
						col = AurelithRig.QZ_1 if (empty_l or empty_u) else AurelithRig.QZ_OUT
				elif part == 1:
					# Voronoi sandstone temple masonry & drifted golden sand collar
					var blk_n: float = _bhash(x / 4, y / 3, 31 + kind)
					var seam: bool = (x + kind) % 7 == 0 or (y + kind) % 5 == 0
					if yf_col < 3.4:
						col = AurelithRig.SD_4 if x < 22 else (AurelithRig.SD_3 if x < 31 else AurelithRig.SD_1)
					elif seam:
						col = AurelithRig.ST_OUT
					elif y % 4 == 1 and kind % 2 == 0 and absf(float(x) - 26.0) < 13.0:
						col = AurelithRig.GD_2 if x < 26 else AurelithRig.GD_0
					else:
						col = AurelithRig.ST_3 if (x < 23 or blk_n > 0.66) else (AurelithRig.ST_2 if x < 31 else AurelithRig.ST_0)
				else:
					# Shading for left (2), right (3), or central (4) faceted sun-quartz fangs
					var fang_h: float = main_h if part == 4 else (left_h if part == 2 else right_h)
					var fang_cx0: float = 26.0 if part == 4 else (16.5 if part == 2 else 35.5)
					var fang_lean: float = main_lean if part == 4 else (left_lean if part == 2 else right_lean)
					var ft: float = clampf(maxf(yf, 0.0) / fang_h, 0.0, 1.0)
					var fcx: float = fang_cx0 + fang_lean * ft
					var side: float = float(x) - fcx
					# Internal overlap crease where central fang sits in front of side fangs
					var part_seam: bool = (
						part == 4 and (
							(part_mask[pi - 1] in [2, 3]) or (part_mask[pi + 1] in [2, 3]) or (part_mask[pi + tw] == 1)
						)
					)
					if part_seam:
						col = AurelithRig.QZ_0 if side < 0.0 else AurelithRig.QZ_OUT
					else:
						# 3-plane hexagonal crystal shading (bright NW plane, translucent mid plane, deep cool-indigo SE plane)
						var ridge_d: float = absf(side + 1.6)
						if ridge_d < 0.85 and ft > 0.18 and ft < 0.88:
							col = AurelithRig.QZ_4
						elif side < -1.8:
							col = AurelithRig.QZ_4 if (ft > 0.42 or part == 4) else AurelithRig.QZ_3
						elif side < 1.5:
							if (x + y * 2 + kind) % 11 == 0 and ft > 0.45:
								col = AurelithRig.SPEC_TURQ if kind % 2 == 0 else AurelithRig.SPEC_AMBR
							else:
								col = AurelithRig.QZ_3 if part == 4 else AurelithRig.QZ_2
						elif side < 4.5:
							col = AurelithRig.QZ_1 if part == 4 else AurelithRig.QZ_0
						else:
							col = AurelithRig.QZ_0

						# Glowing solar-ley fracture zigzagging up from the masonry socket into the crystal core!
						var crack_x: float = sin(float(y) * 0.38 + float(kind * 2 + part)) * 2.1
						if absf(side - crack_x) < 0.78 and ft > 0.08 and ft < 0.76:
							var gcol: Color = Color("78f4e6") if (y + kind) % 2 == 0 else Color("ffd86b")
							col = col.lerp(gcol, 0.68)
							glow_b[idx] = int(roundi(gcol.r * 255.0))
							glow_b[idx + 1] = int(roundi(gcol.g * 255.0))
							glow_b[idx + 2] = int(roundi(gcol.b * 255.0))
							glow_b[idx + 3] = 210

				base_b[idx] = int(roundi(col.r * 255.0))
				base_b[idx + 1] = int(roundi(col.g * 255.0))
				base_b[idx + 2] = int(roundi(col.b * 255.0))
				base_b[idx + 3] = 255

		_TOOTH_TEX_CACHE.append({
			"base": ImageTexture.create_from_image(Image.create_from_data(tw, th, false, Image.FORMAT_RGBA8, base_b)),
			"glow": ImageTexture.create_from_image(Image.create_from_data(tw, th, false, Image.FORMAT_RGBA8, glow_b)),
		})


# --- Scene Construction (every peer) -------------------------------------------------------------------------------


func _additive_material() -> CanvasItemMaterial:
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


func _build_decal() -> void:
	_decal_root = Node2D.new()
	_decal_root.name = "AurelithBasinDecal"
	_decal_root.position = _center
	world.add_child.call_deferred(_decal_root)

	_decal_body = Node2D.new()
	_decal_body.name = "Body"
	_decal_body.z_index = -9
	_decal_body.draw.connect(_draw_decal_body)
	_decal_root.add_child(_decal_body)

	_decal_glow = Node2D.new()
	_decal_glow.name = "Glow"
	_decal_glow.z_index = -8
	_decal_glow.material = _additive_material()
	_decal_glow.draw.connect(_draw_decal_glow)
	_decal_root.add_child(_decal_glow)


func _build_monument() -> void:
	_monument_root = MonumentCanopyNode.new()
	_monument_root.name = "AurelithDormantMonument"
	_monument_root.position = _center
	var ysort_parent: Node2D = world.get_node_or_null("Props") as Node2D
	if ysort_parent == null:
		ysort_parent = world
	ysort_parent.add_child.call_deferred(_monument_root)

	_monument_rig = RIG_SCENE.instantiate() as AurelithRig
	_monument_rig.name = "Rig"
	_monument_rig.start_pose(AurelithRig.Pose.DORMANT, 1.0)
	_monument_root.add_child(_monument_rig)

	_monument_body = StaticBody2D.new()
	_monument_body.name = "Footprint"
	_monument_body.collision_layer = 1
	_monument_body.collision_mask = 0
	var shape_node: CollisionShape2D = CollisionShape2D.new()
	var cap: CapsuleShape2D = CapsuleShape2D.new()
	cap.radius = 15.0
	cap.height = 54.0
	shape_node.shape = cap
	shape_node.rotation = PI * 0.5
	shape_node.position = Vector2(0.0, -8.0)
	_monument_body.add_child(shape_node)
	_monument_root.add_child(_monument_body)

	_monument_light = NightLight.new()
	_monument_light.position = Vector2(0.0, -18.0)
	_monument_light.radius = 86
	_monument_light.squash = 0.72
	_monument_light.glow_color = Color("78f4e6")
	_monument_light.base_energy = 0.15
	_monument_root.add_child(_monument_light)

	_hum_player = AudioStreamPlayer2D.new()
	_hum_player.name = "ResonanceHum"
	_hum_player.max_distance = 620.0
	_hum_player.attenuation = 1.6
	if ResourceLoader.exists(HARP_WAV):
		var wav: AudioStreamWAV = (load(HARP_WAV) as AudioStreamWAV).duplicate() as AudioStreamWAV
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1)
			_hum_player.stream = wav
	_hum_player.volume_db = -80.0
	_monument_root.add_child(_hum_player)

	_sfx_player = AudioStreamPlayer2D.new()
	_sfx_player.name = "BasinSfx"
	_sfx_player.max_distance = 760.0
	_sfx_player.attenuation = 1.4
	_monument_root.add_child(_sfx_player)

	_hologram = AurelithHologram.new()
	_hologram.name = "AurelithHologram"
	_hologram.arena = self
	_hologram.position = _center
	ysort_parent.add_child.call_deferred(_hologram)


func _build_perimeter_wall() -> void:
	_wall_root = Node2D.new()
	_wall_root.name = "AurelithPerimeterWall"
	_wall_root.y_sort_enabled = true
	world.add_child.call_deferred(_wall_root)

	var count: int = maxi(int(_spec.get("wall_teeth", 44)), 16)
	var step_ang: float = TAU / float(count)
	for i: int in count:
		var ang: float = float(i) * step_ang + 0.045 * sin(float(i * 3))
		var rad_j: float = 1.0 + 0.018 * sin(float(i * 5 + 1))
		var pt: Vector2 = _center + Vector2(cos(ang) * _arena_radii.x * rad_j, sin(ang) * _arena_radii.y * rad_j)
		var tangent: Vector2 = Vector2(-sin(ang) * _arena_radii.x, cos(ang) * _arena_radii.y).normalized()
		var seg_len: float = _center.distance_to(pt) * step_ang * 1.24

		var body: StaticBody2D = StaticBody2D.new()
		body.collision_layer = 0
		body.collision_mask = 0
		body.position = pt
		var col: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(maxf(seg_len, 42.0), 20.0)
		col.shape = rect
		col.rotation = tangent.angle()
		col.position = Vector2(0.0, -4.0)
		body.add_child(col)
		_wall_root.add_child(body)
		_wall_bodies.append(body)

		var tooth_holder: Node2D = Node2D.new()
		tooth_holder.position = pt.round()
		tooth_holder.visible = false
		var entry: Dictionary = _TOOTH_TEX_CACHE[(i * 3 + i / 5) % _TOOTH_TEX_CACHE.size()]
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = entry["base"] as Texture2D
		spr.centered = false
		spr.offset = Vector2(-26.0, -48.0)
		# Keep NW light consistent (`flip_h = false`) so every tooth's left/NW facets stay sunlit!
		tooth_holder.add_child(spr)

		var glow_spr: Sprite2D = Sprite2D.new()
		glow_spr.texture = entry["glow"] as Texture2D
		glow_spr.centered = false
		glow_spr.offset = spr.offset
		glow_spr.material = _additive_material()
		glow_spr.modulate.a = 0.72
		spr.add_child(glow_spr)

		_wall_root.add_child(tooth_holder)
		_wall_teeth.append({
			"root": tooth_holder,
			"base": spr,
			"glow": glow_spr,
			"angle": ang,
			"pos": pt,
		})


func _build_fx_layers() -> void:
	_storm_berm_fx = Node2D.new()
	_storm_berm_fx.name = "AurelithStormBerm"
	_storm_berm_fx.position = _center
	_storm_berm_fx.z_index = -7
	_storm_berm_fx.visible = false
	_storm_berm_fx.draw.connect(_draw_storm_berm)
	world.add_child.call_deferred(_storm_berm_fx)

	_storm_fx = Node2D.new()
	_storm_fx.name = "AurelithStormVeil"
	_storm_fx.position = _center
	_storm_fx.z_index = 2
	_storm_fx.material = Unlit.material()
	_storm_fx.draw.connect(_draw_storm_veil)
	world.add_child.call_deferred(_storm_fx)

	_soul_fx = Node2D.new()
	_soul_fx.name = "AurelithSoulFx"
	_soul_fx.position = _center
	_soul_fx.z_index = 4
	_soul_fx.material = _additive_material()
	_soul_fx.draw.connect(_draw_soul_fx)
	world.add_child.call_deferred(_soul_fx)


func _init_storm_streaks() -> void:
	_storm_ribbons.clear()
	for r: int in 28:
		_storm_ribbons.append({
			"ang": float(r) / 28.0 * TAU,
			"speed": 1.45 + float(r % 5) * 0.28,
			"rad_k": 0.96 + float((r * 3) % 5) * 0.020,
			"z": 5.0 + float((r * 9) % 30),
			"span": 0.14 + float(r % 4) * 0.035,
			"kind": r % 4,
		})
	_storm_streaks.clear()
	for i: int in 96:
		_storm_streaks.append({
			"ang": float(i) / 96.0 * TAU,
			"speed": 1.65 + float(i % 6) * 0.26,
			"rad_k": 0.94 + float((i * 7) % 6) * 0.022,
			"z": 3.0 + float((i * 11) % 34),
			"len": 0.06 + float(i % 4) * 0.022,
			"kind": i % 4,
		})


# --- Frame Update & Visuals (every peer) ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	_time += delta
	var target_charge: float = 1.0 if stage in [Stage.SILENCE, Stage.BOSS] else soul_charge_ratio()
	_display_charge = move_toward(_display_charge, target_charge, delta * 1.8)
	if stage == Stage.SILENCE:
		_silence_fx_t += delta
	else:
		_silence_fx_t = 0.0

	_update_monument_and_audio(delta)
	_update_wall_animation(delta)
	_update_particles(delta)

	if _decal_glow != null and (_display_charge > 0.01 or stage in [Stage.SILENCE, Stage.BOSS]):
		_decal_glow.queue_redraw()
	if _storm_berm_fx != null and (_wall_grow > 0.01 or _storm_berm_fx.visible):
		_storm_berm_fx.visible = _wall_grow > 0.01
		if _storm_berm_fx.visible:
			_storm_berm_fx.queue_redraw()
	if _storm_fx != null and (_wall_grow > 0.01 or _storm_fx.visible):
		_storm_fx.visible = _wall_grow > 0.01
		if _storm_fx.visible:
			_storm_fx.queue_redraw()
	if _soul_fx != null:
		_soul_fx.queue_redraw()


func _update_monument_and_audio(delta: float) -> void:
	var show_monument: bool = not released and stage in [Stage.DORMANT, Stage.SILENCE] and not boss_present()
	if _monument_root != null:
		if _monument_root.visible != show_monument:
			_monument_root.visible = show_monument
			_monument_body.set_deferred("collision_layer", 1 if show_monument else 0)
		if show_monument and _monument_rig != null:
			_monument_rig.soul_charge = _display_charge
			_monument_rig.update_rig(delta, Vector2.ZERO, PI * 0.5)
		if _monument_light != null:
			_monument_light.base_energy = (0.14 + 0.56 * _display_charge) if show_monument else 0.0

	if _hologram != null:
		var show_holo: bool = released and stage == Stage.FREE and not boss_present() and _rematch_in < 0.0
		_hologram.set_active(show_holo)

	# Resonant glass-harp hum while 1..5 guardians have fed the core; dead silence on the 6th!
	if _hum_player != null and DisplayServer.get_name() != "headless":
		var want_hum_db: float = -80.0
		if show_monument and stage == Stage.DORMANT and _display_charge > 0.06:
			want_hum_db = lerpf(-22.0, -7.5, _display_charge)
			_hum_player.pitch_scale = lerpf(0.68, 1.04, _display_charge)
		var rate: float = 180.0 if stage == Stage.SILENCE else 28.0
		_hum_player.volume_db = move_toward(_hum_player.volume_db, want_hum_db, rate * delta)
		if want_hum_db > -78.0 and not _hum_player.playing:
			_hum_player.play()
		elif _hum_player.playing and _hum_player.volume_db <= -79.0:
			_hum_player.stop()

	# Eerie 0.85s desert wind hush (`Weather` bus) when a local player witnesses the 6th sentinel fall
	_update_weather_silence(delta)


func _update_weather_silence(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var local_near: bool = false
	if stage == Stage.SILENCE:
		for player: Player in Player.all:
			if player.is_multiplayer_authority() and player.global_position.distance_to(_center) < 720.0:
				local_near = true
				break
	var want_duck: float = -34.0 if local_near else 0.0
	if is_equal_approx(_weather_ducked_db, want_duck):
		return
	var prev_duck: float = _weather_ducked_db
	_weather_ducked_db = move_toward(_weather_ducked_db, want_duck, (190.0 if local_near else 85.0) * delta)
	var bus_idx: int = AudioServer.get_bus_index(&"Weather")
	if bus_idx >= 0:
		var cur_db: float = AudioServer.get_bus_volume_db(bus_idx)
		AudioServer.set_bus_volume_db(bus_idx, cur_db + (_weather_ducked_db - prev_duck))


func _restore_weather_bus_immediately() -> void:
	if not is_zero_approx(_weather_ducked_db) and DisplayServer.get_name() != "headless":
		var bus_idx: int = AudioServer.get_bus_index(&"Weather")
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, AudioServer.get_bus_volume_db(bus_idx) - _weather_ducked_db)
	_weather_ducked_db = 0.0


func _update_wall_animation(delta: float) -> void:
	var want: float = 1.0 if sealed else 0.0
	if not is_equal_approx(_wall_grow, want):
		_wall_grow = move_toward(_wall_grow, want, delta * (2.2 if sealed else 0.9))
		for i: int in _wall_teeth.size():
			var td: Dictionary = _wall_teeth[i]
			var holder: Node2D = td["root"] as Node2D
			var glow_spr: Sprite2D = td["glow"] as Sprite2D
			var ripple: float = float(i % 9) * 0.065
			var k: float = clampf(_wall_grow * 1.55 - ripple, 0.0, 1.0) if sealed else _wall_grow
			holder.visible = k > 0.02
			holder.scale = Vector2(1.0, k)
			holder.modulate.a = 1.0 if sealed else k
			glow_spr.modulate.a = (0.58 + 0.24 * sin(_time * 3.4 + float(i) * 0.5)) * k
	elif sealed:
		for i: int in _wall_teeth.size():
			var glow_spr2: Sprite2D = (_wall_teeth[i]["glow"]) as Sprite2D
			glow_spr2.modulate.a = 0.58 + 0.22 * sin(_time * 3.4 + float(i) * 0.5)


func _update_particles(delta: float) -> void:
	for s: Dictionary in _soul_streams:
		s["age"] = float(s["age"]) + delta
	if not _soul_streams.is_empty():
		_soul_streams = _soul_streams.filter(func(s: Dictionary) -> bool: return float(s["age"]) < float(s["dur"]))

	# Antigravity floating sand & quartz pebbles once >= 2 guardians have fallen (`soul_charge >= 0.33`)
	if stage == Stage.DORMANT and not released and _display_charge >= 0.30 and _float_pebbles.size() < 26:
		if randf() < delta * (8.0 + 18.0 * _display_charge):
			var ang: float = randf() * TAU
			var rad: float = randf_range(16.0, 68.0)
			_float_pebbles.append({
				"pos": Vector2(cos(ang) * rad, sin(ang) * rad * 0.72),
				"z": 0.0,
				"vz": randf_range(12.0, 28.0) * (0.6 + _display_charge),
				"col": Color("78f4e6") if randi() % 3 == 0 else (Color("ffe488") if randi() % 3 == 1 else AurelithRig.SD_4),
				"sz": 2.0 if randi() % 3 == 0 else 1.0,
				"life": 0.0,
				"max_life": randf_range(1.1, 1.9),
			})
	for p: Dictionary in _float_pebbles:
		p["life"] = float(p["life"]) + delta
		if stage != Stage.SILENCE: ## during the 0.85s dead silence, levitating grains freeze weightlessly in mid-air!
			p["z"] = float(p["z"]) + float(p["vz"]) * delta
	if not _float_pebbles.is_empty():
		_float_pebbles = _float_pebbles.filter(func(p: Dictionary) -> bool: return float(p["life"]) < float(p["max_life"]))

	if _wall_grow > 0.01:
		for rb: Dictionary in _storm_ribbons:
			rb["ang"] = fmod(float(rb["ang"]) + float(rb["speed"]) * delta, TAU)
		for st: Dictionary in _storm_streaks:
			st["ang"] = fmod(float(st["ang"]) + float(st["speed"]) * delta, TAU)


func _draw_decal_body() -> void:
	if _CACHED_DECAL_BASE != null:
		_decal_body.draw_texture(_CACHED_DECAL_BASE, Vector2(-DECAL_HALF_W, -DECAL_HALF_H))


func _draw_decal_glow() -> void:
	var pulse: float = 0.78 + 0.22 * sin(_time * 3.8)
	var seal_a: float = clampf(_display_charge * 0.85, 0.0, 0.9) * pulse
	if _CACHED_SEAL_GLOW != null and seal_a > 0.02:
		_decal_glow.draw_texture(_CACHED_SEAL_GLOW, Vector2(-DECAL_HALF_W, -DECAL_HALF_H), Color(1.0, 1.0, 1.0, seal_a))
	var n_v: int = mini(_CACHED_VEIN_GLOWS.size(), _slot_dead.size())
	for vi: int in n_v:
		var lit: bool = _slot_dead[vi] or stage in [Stage.SILENCE, Stage.BOSS]
		if not lit:
			continue
		var va: float = (0.95 if stage == Stage.SILENCE else 0.72) * (0.82 + 0.18 * sin(_time * 4.5 + float(vi)))
		_decal_glow.draw_texture(_CACHED_VEIN_GLOWS[vi], Vector2(-DECAL_HALF_W, -DECAL_HALF_H), Color(1.0, 1.0, 1.0, va))


func _draw_storm_berm() -> void:
	if _wall_grow <= 0.02:
		return
	var a_wall: float = clampf(_wall_grow, 0.0, 1.0)
	var segs: int = 88
	var pts_outer: PackedVector2Array = PackedVector2Array()
	var pts_mid: PackedVector2Array = PackedVector2Array()
	var pts_inner: PackedVector2Array = PackedVector2Array()
	for i: int in range(segs + 1):
		var ang: float = float(i) / float(segs) * TAU
		var wave: float = sin(ang * 14.0 + _time * 2.8) * 3.5 + cos(ang * 9.0 - _time * 1.9) * 2.5
		var base_p: Vector2 = Vector2(cos(ang) * _arena_radii.x, sin(ang) * _arena_radii.y)
		var rad_dir: Vector2 = base_p.normalized()
		pts_outer.append((base_p + rad_dir * (10.0 + wave)).round())
		pts_mid.append((base_p + rad_dir * (1.0 + wave * 0.45)).round())
		pts_inner.append((base_p - rad_dir * (8.0 - wave * 0.5)).round())

	_storm_berm_fx.draw_polyline(pts_outer, Color(AurelithRig.SD_2, 0.52 * a_wall), 9.0)
	_storm_berm_fx.draw_polyline(pts_inner, Color(AurelithRig.SD_3, 0.48 * a_wall), 8.0)
	_storm_berm_fx.draw_polyline(pts_mid, Color(AurelithRig.ST_OUT, 0.72 * a_wall), 4.0)
	# Glowing solar-ley ground fracture pulsing right between the erupted crags
	for k: int in 22:
		var i0: int = (k * 4 + int(floorf(_time * 8.0))) % segs
		var arc_pts: PackedVector2Array = PackedVector2Array()
		for s: int in 3:
			var ii: int = (i0 + s) % (segs + 1)
			arc_pts.append(pts_mid[ii])
		var lcol: Color = Color("78f4e6" if k % 2 == 0 else "ffd86b", (0.58 + 0.24 * sin(_time * 4.2 + float(k))) * a_wall)
		_storm_berm_fx.draw_polyline(arc_pts, lcol, 2.0)


func _draw_storm_veil() -> void:
	if _wall_grow <= 0.02:
		return
	var a_wall: float = clampf(_wall_grow, 0.0, 1.0)
	# 1) Sweeping tangential sandstorm & solar-ley wind ribbons connecting the 44 crags
	for rb: Dictionary in _storm_ribbons:
		var ang0: float = float(rb["ang"])
		var span: float = float(rb["span"])
		var rk: float = float(rb["rad_k"])
		var z_base: float = float(rb["z"]) * a_wall
		var rkind: int = int(rb["kind"])
		var rcol: Color = AurelithRig.SD_4
		var ralpha: float = 0.54 * a_wall
		if rkind == 0:
			rcol = Color("78f4e6")
			ralpha = 0.56 * a_wall
		elif rkind == 1:
			rcol = Color("ffd86b")
			ralpha = 0.52 * a_wall
		elif rkind == 2:
			rcol = AurelithRig.SD_5
			ralpha = 0.48 * a_wall
		var rib_pts: PackedVector2Array = PackedVector2Array()
		for s: int in 7:
			var u: float = float(s) / 6.0
			var a_s: float = ang0 - u * span
			var z_wave: float = z_base + sin(u * PI + _time * 5.0 + ang0) * 4.5
			rib_pts.append(Vector2(cos(a_s) * _arena_radii.x * rk, sin(a_s) * _arena_radii.y * rk - z_wave).round())
		_storm_fx.draw_polyline(rib_pts, Color(rcol, ralpha), 2.0 if rkind >= 2 else 1.5)

	# 2) Crisp pixel sand-grains & glinting sun-quartz splinters whipping inside the cyclone wall
	for st: Dictionary in _storm_streaks:
		var ang0: float = float(st["ang"])
		var span: float = float(st["len"])
		var rk: float = float(st["rad_k"])
		var z_lift: float = float(st["z"]) * a_wall
		var kind: int = int(st["kind"])
		var col: Color = AurelithRig.SD_4
		var alpha: float = 0.62 * a_wall
		if kind == 0:
			col = Color("78f4e6")
			alpha = 0.78 * a_wall
		elif kind == 1:
			col = Color("ffd86b")
			alpha = 0.72 * a_wall
		elif kind == 2:
			col = Color("ffffff")
			alpha = 0.68 * a_wall
		for seg: int in 3:
			var a_s: float = ang0 - float(seg) * (span * 0.42)
			var pt: Vector2 = Vector2(cos(a_s) * _arena_radii.x * rk, sin(a_s) * _arena_radii.y * rk - z_lift).round()
			var seg_a: float = alpha * (1.0 - float(seg) * 0.28)
			var sz: Vector2 = Vector2(3.0 if seg == 0 else 2.0, 2.0 if seg == 0 else 1.0)
			_storm_fx.draw_rect(Rect2(pt, sz), Color(col, seg_a))


func _draw_soul_fx() -> void:
	# 1) Weightless floating sand & quartz flecks around the waking mound
	for p: Dictionary in _float_pebbles:
		var life_t: float = float(p["life"]) / maxf(float(p["max_life"]), 0.05)
		var pa: float = sin(clampf(life_t, 0.0, 1.0) * PI) * 0.88
		var pt: Vector2 = ((p["pos"] as Vector2) + Vector2(0.0, -float(p["z"]))).round()
		var sz: float = float(p["sz"])
		_soul_fx.draw_rect(Rect2(pt, Vector2.ONE * sz), Color(p["col"] as Color, pa))

	# 2) Spiraling soul-drain ribbons from each fallen guardian into the sunken core
	for s: Dictionary in _soul_streams:
		var q: float = clampf(float(s["age"]) / maxf(float(s["dur"]), 0.05), 0.0, 1.0)
		var from_rel: Vector2 = (s["from"] as Vector2) - _center
		var to_rel: Vector2 = Vector2(0.0, -20.0)
		var perp: Vector2 = Vector2(-from_rel.y, from_rel.x).normalized()
		var head_t: float = smoothstep(0.0, 0.85, q)
		var tail_t: float = smoothstep(0.18, 1.0, q)
		for step_i: int in 20:
			var u: float = lerpf(tail_t, head_t, float(step_i) / 19.0)
			var arc_h: float = sin(u * PI) * 26.0
			var swirl: float = sin(u * 10.0 - _time * 14.0 + float(s["slot"])) * (1.0 - u) * 14.0
			var cur: Vector2 = (from_rel.lerp(to_rel, u) + perp * swirl + Vector2(0.0, -arc_h)).round()
			var sa: float = sin(clampf(float(step_i) / 19.0, 0.0, 1.0) * PI) * (1.0 - q * 0.35)
			_soul_fx.draw_rect(Rect2(cur - Vector2.ONE, Vector2(3.0, 3.0)), Color("78f4e6", sa * 0.55))
			_soul_fx.draw_rect(Rect2(cur, Vector2(2.0, 2.0)), Color("ffe488" if step_i > 14 else "ffffff", sa * 0.92))

	# 3) During the 0.85s dead silence: 6 suspended soul stars contracting inward along the 6 veins
	if stage == Stage.SILENCE:
		var silence_dur: float = maxf(float(_spec.get("silence_seconds", 0.85)), 0.1)
		var sq: float = clampf(_silence_fx_t / silence_dur, 0.0, 1.0)
		var pull: float = pow(sq, 2.4)
		for vi: int in _vein_pads.size():
			var pad_rel: Vector2 = _vein_pads[vi] - _center
			var orb_p: Vector2 = pad_rel.lerp(Vector2(0.0, -18.0), pull).round()
			_soul_fx.draw_rect(Rect2(orb_p - Vector2(3.0, 1.0), Vector2(7.0, 3.0)), Color("78f4e6", 0.72))
			_soul_fx.draw_rect(Rect2(orb_p - Vector2(1.0, 3.0), Vector2(3.0, 7.0)), Color("ffe488", 0.78))
			_soul_fx.draw_rect(Rect2(orb_p - Vector2.ONE, Vector2(3.0, 3.0)), Color("ffffff", 0.96))


# --- Host Watch & Ritual State Machine -----------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if multiplayer == null or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	if _rematch_in >= 0.0:
		_rematch_in -= delta
		if _rematch_in < 0.0:
			summon_boss(false)
	if stage == Stage.SILENCE and _silence_left >= 0.0:
		_silence_left -= delta
		if _silence_left <= 0.0:
			_silence_left = -1.0
			_rpc_awaken_burst.rpc()
			summon_boss(false)
			return

	_clock += delta
	if _clock < TICK:
		return
	var step: float = _clock
	_clock = 0.0

	match stage:
		Stage.DORMANT:
			if released:
				stage = Stage.FREE
				return
			var near_spawn: bool = _someone_near(float(_spec.get("spawn_range", 520.0)))
			if near_spawn and not _guardians_spawned:
				_spawn_basin_guardians()
			elif _guardians_spawned:
				if killed_count > 0 or _any_guardian_provoked():
					_watch_empty(step)
				elif not _someone_near(DESPAWN_IDLE_RANGE):
					_clear_guardians()
		Stage.SILENCE:
			_watch_empty(step)
		Stage.BOSS:
			if not boss_present() and not released:
				_reset()


func _someone_near(radius: float) -> bool:
	for player: Player in Player.all:
		if player == null or not is_instance_valid(player) or player.health.current <= 0.0:
			continue
		if Interiors.slot_at(player.global_position) >= 0 or MineManager.in_mine(player.global_position):
			continue
		if player.global_position.distance_to(_center) <= radius:
			return true
	return false


func _nearest_player_in_basin() -> Player:
	var best: Player = null
	var best_d: float = float(_spec.get("leash", 640.0))
	for player: Player in Player.all:
		if player == null or not is_instance_valid(player) or player.health.current <= 0.0:
			continue
		if Interiors.slot_at(player.global_position) >= 0 or MineManager.in_mine(player.global_position):
			continue
		var d: float = player.global_position.distance_to(_center)
		if d < best_d:
			best = player
			best_d = d
	return best


func _any_guardian_provoked() -> bool:
	for g: Node2D in _guardians:
		if g != null and is_instance_valid(g) and g.has_method("is_provoked") and bool(g.call("is_provoked")):
			return true
	return false


func _watch_empty(step: float) -> void:
	if _someone_near(float(_spec.get("leash", 640.0))):
		_away = 0.0
		return
	_away += step
	if _away >= float(_spec.get("reset_seconds", 8.0)):
		_reset()


func _spawn_basin_guardians() -> void:
	if not multiplayer.is_server():
		return
	_guardians_spawned = true
	for slot: int in _guardian_specs.size():
		if _slot_dead[slot]:
			continue
		if _guardians[slot] != null and is_instance_valid(_guardians[slot]):
			continue
		var gd: Dictionary = _guardian_specs[slot]
		var pad_pos: Vector2 = _vein_pads[slot]
		var face_ang: float = (pad_pos - _center).angle()
		var golem: Node2D = world.spawn_quartz_golem(
			pad_pos,
			face_ang,
			int(gd["variant"]),
			bool(gd["dormant"]),
			1.0,
			1.0,
			false
		)
		if golem == null:
			continue
		golem.set("pickaxe_override", 1.0) ## Pure weapon & spell focus inside Aurelith's basin!
		_guardians[slot] = golem
		var hc: HealthComponent = golem.get_node_or_null("HealthComponent") as HealthComponent
		if hc != null:
			hc.died.connect(_on_basin_guardian_died.bind(slot, golem), CONNECT_ONE_SHOT)


func _on_basin_guardian_died(slot: int, golem: Node2D) -> void:
	if not multiplayer.is_server() or stage != Stage.DORMANT or released:
		return
	if slot < 0 or slot >= _slot_dead.size() or _slot_dead[slot]:
		return
	_slot_dead[slot] = true
	_guardians[slot] = null
	var death_pos: Vector2 = golem.global_position if is_instance_valid(golem) else _vein_pads[slot]
	killed_count += 1
	_away = 0.0
	_rpc_guardian_soul.rpc(slot, death_pos, killed_count)

	# Guardians 3..5: remaining sentinels escalate in arcane resonance & converge on the intruder!
	if killed_count >= 2 and killed_count < _guardian_specs.size():
		var target: Player = _nearest_player_in_basin()
		var intensity: float = clampf(float(killed_count - 1) / float(maxi(_guardian_specs.size() - 2, 1)), 0.25, 1.0)
		for g: Node2D in _guardians:
			if g != null and is_instance_valid(g) and g.has_method("boost_basin_aggression"):
				g.call("boost_basin_aggression", intensity, target)

	# 6th guardian falls -> 0.85s dead silence before Aurelith self-assembles!
	if killed_count >= _guardian_specs.size():
		_silence_left = float(_spec.get("silence_seconds", 0.85))
		_rpc_stage.rpc(Stage.SILENCE, false, killed_count, _slot_dead_mask())


func _slot_dead_mask() -> int:
	var mask: int = 0
	for i: int in _slot_dead.size():
		if _slot_dead[i]:
			mask |= (1 << i)
	return mask


func _apply_slot_mask(mask: int) -> void:
	for i: int in _slot_dead.size():
		_slot_dead[i] = ((mask >> i) & 1) != 0


func _clear_guardians() -> void:
	for i: int in _guardians.size():
		var g: Node2D = _guardians[i]
		if g != null and is_instance_valid(g):
			g.queue_free()
		_guardians[i] = null
	_guardians_spawned = false


## Host: spawns `Aurelith` (`res://src/entities/enemies/desert_boss/aurelith.tscn`) at the center of the Singing Basin.
func summon_boss(skip_awaken_anim: bool = false) -> void:
	if not multiplayer.is_server() or boss_present():
		return
	var players: int = 0
	var leash_px: float = float(_spec.get("leash", 640.0))
	for player: Player in Player.all:
		if player != null and is_instance_valid(player) and player.health.current > 0.0 and player.global_position.distance_to(_center) <= leash_px:
			players += 1
	var packed: PackedScene = load(BOSS_SCENE_PATH) as PackedScene
	var node: Aurelith = packed.instantiate() as Aurelith
	world._enemy_count += 1
	node.name = "Aurelith%d" % world._enemy_count
	node.enemy_id = String(_spec.get("species", "boss_aurelith"))
	node.health_scale = 1.0 + 0.5 * float(maxi(players - 1, 0))
	node.skip_awaken = skip_awaken_anim
	node.position = _center
	var target: Player = _nearest_player_in_basin()
	node.heading = (target.global_position - _center).angle() if target != null else PI * 0.5
	world._enemies.add_child(node, true)
	boss = node
	node.reset_requested.connect(_reset)
	_rpc_stage.rpc(Stage.BOSS, skip_awaken_anim, _guardian_specs.size(), (1 << _guardian_specs.size()) - 1)


## Called on every peer when `Aurelith` slams both colossal fists into the sand during `Pose.FAULT_SLAM`.
func on_boss_fist_slam() -> void:
	_set_sealed(true)
	if multiplayer.is_server():
		_nudge_rim_players_inside()


func _nudge_rim_players_inside() -> void:
	var leash_px: float = float(_spec.get("leash", 640.0))
	for player: Player in Player.all:
		if player == null or not is_instance_valid(player) or player.health.current <= 0.0:
			continue
		if player.global_position.distance_to(_center) > leash_px:
			continue
		var rel: Vector2 = (player.global_position - _center) / _arena_radii
		var d: float = rel.length()
		if d > 0.89:
			var safe_pos: Vector2 = _center + rel.normalized() * (_arena_radii * 0.84)
			player.request_teleport(safe_pos)


func _set_sealed(on: bool) -> void:
	if sealed == on:
		return
	sealed = on
	for body: StaticBody2D in _wall_bodies:
		body.set_deferred("collision_layer", 1 if on else 0)
	if on:
		_play_basin_sfx(SURGE_WAV, -4.0, 0.92)


func _reset() -> void:
	_clear_guardians()
	for i: int in _slot_dead.size():
		_slot_dead[i] = false
	killed_count = 0
	_silence_left = -1.0
	_away = 0.0
	if is_instance_valid(boss):
		boss.queue_free()
	boss = null
	var next_stage: Stage = Stage.FREE if released else Stage.DORMANT
	_rpc_stage.rpc(next_stage, false, 0, 0)
	if not released and _someone_near(float(_spec.get("spawn_range", 520.0))):
		_spawn_basin_guardians()


func on_released() -> void:
	released = true
	stage = Stage.FREE
	_set_sealed(false)
	_restore_weather_bus_immediately()


# --- RPCs, Late-Join Sync, SaveGame & Dev Menu ---------------------------------------------------------------------


@rpc("authority", "call_local", "reliable")
func _rpc_guardian_soul(slot: int, death_pos: Vector2, new_count: int) -> void:
	if slot >= 0 and slot < _slot_dead.size():
		_slot_dead[slot] = true
	killed_count = new_count
	_soul_streams.append({
		"from": death_pos,
		"age": 0.0,
		"dur": 0.78,
		"slot": slot,
	})
	_play_basin_sfx(CHIME_WAV, -6.0, 0.76 + 0.08 * float(new_count))
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			var d: float = player.global_position.distance_to(_center)
			if d < 420.0:
				player.add_shake(0.55 * (1.0 - smoothstep(40.0, 420.0, d)))


@rpc("authority", "call_local", "reliable")
func _rpc_awaken_burst() -> void:
	for vi: int in _vein_pads.size():
		_soul_streams.append({
			"from": _vein_pads[vi],
			"age": 0.0,
			"dur": 0.62,
			"slot": vi,
		})
	_play_basin_sfx(SLAM_WAV, -2.0, 0.74)
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			var d: float = player.global_position.distance_to(_center)
			if d < 520.0:
				player.add_shake(1.65 * (1.0 - smoothstep(40.0, 520.0, d)))


@rpc("authority", "call_local", "reliable")
func _rpc_stage(next: int, seal: bool, p_killed: int, slot_mask: int) -> void:
	stage = next as Stage
	killed_count = p_killed
	_apply_slot_mask(slot_mask)
	_set_sealed(seal)
	if stage != Stage.SILENCE:
		_restore_weather_bus_immediately()
	if _decal_glow != null:
		_decal_glow.queue_redraw()


func _ask_host() -> void:
	_ask_state.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ask_state() -> void:
	if multiplayer.is_server():
		_rpc_state.rpc_id(
			multiplayer.get_remote_sender_id(),
			int(stage),
			sealed,
			released,
			killed_count,
			_slot_dead_mask()
		)


@rpc("authority", "call_remote", "reliable")
func _rpc_state(p_stage: int, p_sealed: bool, p_released: bool, p_killed: int, p_mask: int) -> void:
	released = p_released
	stage = p_stage as Stage
	killed_count = p_killed
	_apply_slot_mask(p_mask)
	_display_charge = soul_charge_ratio()
	_set_sealed(p_sealed)
	if p_sealed:
		_wall_grow = 0.98


func request_rematch() -> void:
	if multiplayer.is_server():
		_host_rematch()
	else:
		_rpc_ask_rematch.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ask_rematch() -> void:
	if multiplayer.is_server():
		_host_rematch()


func _host_rematch() -> void:
	if not released or stage != Stage.FREE or boss_present() or _rematch_in >= 0.0:
		return
	_rematch_in = 0.85
	_rpc_hologram_touched.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_hologram_touched() -> void:
	if _hologram != null:
		_hologram.touched()


func debug_fight() -> void:
	if not multiplayer.is_server():
		_rpc_debug_fight.rpc_id(1)
		return
	_clear_guardians()
	for i: int in _slot_dead.size():
		_slot_dead[i] = true
	killed_count = _guardian_specs.size()
	_silence_left = -1.0
	summon_boss(false)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_debug_fight() -> void:
	if multiplayer.is_server():
		debug_fight()


func debug_phase(target_phase: int) -> void:
	if not multiplayer.is_server():
		_rpc_debug_phase.rpc_id(1, target_phase)
		return
	if not boss_present():
		_clear_guardians()
		for i: int in _slot_dead.size():
			_slot_dead[i] = true
		killed_count = _guardian_specs.size()
		_silence_left = -1.0
		summon_boss(true)
	for node: Node in get_tree().get_nodes_in_group("bosses"):
		if node is Aurelith and not node.is_queued_for_deletion():
			(node as Aurelith).debug_force_phase(target_phase, true)
			break


@rpc("any_peer", "call_remote", "reliable")
func _rpc_debug_phase(target_phase: int) -> void:
	if multiplayer.is_server():
		debug_phase(target_phase)


func export_state() -> Dictionary:
	return {"released": released}


func import_state(data: Dictionary) -> void:
	if bool(data.get("released", false)):
		released = true
		stage = Stage.FREE
		_set_sealed(false)
		_clear_guardians()


func _play_basin_sfx(path: String, db: float, pitch: float) -> void:
	if DisplayServer.get_name() == "headless" or _sfx_player == null or not ResourceLoader.exists(path):
		return
	_sfx_player.stream = load(path) as AudioStream
	_sfx_player.volume_db = db
	_sfx_player.pitch_scale = pitch
	_sfx_player.play()


func _exit_tree() -> void:
	_restore_weather_bus_immediately()
	if is_instance_valid(_decal_root):
		_decal_root.queue_free()
	if is_instance_valid(_monument_root):
		_monument_root.queue_free()
	if is_instance_valid(_wall_root):
		_wall_root.queue_free()
	if is_instance_valid(_storm_berm_fx):
		_storm_berm_fx.queue_free()
	if is_instance_valid(_storm_fx):
		_storm_fx.queue_free()
	if is_instance_valid(_soul_fx):
		_soul_fx.queue_free()
	if is_instance_valid(_hologram):
		_hologram.queue_free()


# --- Helper Inner Nodes --------------------------------------------------------------------------------------------


class BasinSurfacePatch:
	extends Node
	var center: Vector2 = Vector2.ZERO
	var vein_pads: Array[Vector2] = []

	func surface_at(world_pos: Vector2) -> String:
		var rel: Vector2 = world_pos - center
		if rel.length_squared() > 180.0 * 180.0:
			return ""
		var seal_d: float = Vector2(rel.x / 54.0, rel.y / 38.0).length()
		if seal_d <= 1.02:
			return "quartz"
		for vi: int in vein_pads.size():
			var end_p: Vector2 = vein_pads[vi] - center
			var perp: Vector2 = Vector2(-end_p.y, end_p.x).normalized()
			var mid_p: Vector2 = end_p * 0.52 + perp * (11.0 if (vi % 2 == 0) else -11.0)
			if AurelithArena._seg_dist(rel, Vector2.ZERO, mid_p) <= 9.0 or AurelithArena._seg_dist(rel, mid_p, end_p) <= 9.0:
				return "quartz"
			if Vector2((rel.x - end_p.x) / 22.0, (rel.y - end_p.y) / 16.0).length() <= 1.0:
				return "quartz"
		return ""


class MonumentCanopyNode:
	extends Node2D

	func _ready() -> void:
		add_to_group("day_canopies")

	func day_canopy() -> Vector4:
		if not visible:
			return Vector4.ZERO
		return Vector4(global_position.x + 8.0, global_position.y + 4.0, 50.0, 34.0)
