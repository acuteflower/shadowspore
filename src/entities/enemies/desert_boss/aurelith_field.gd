class_name AurelithField
extends Node2D
## Active ground-magic, monolith cover, telegraph, beam/tether, and reflected `Resonanz-Kern` engine
## for `Aurelith, Herz des Sonnenquarzes` (docs/enemies/boss_aurelith.md, Pakete 3–6).
##
## Visual Architecture (v2 Textured Pixel-Art Overhaul):
## - World-lit base canvases (`_floor_canvas`, `_sky_body`) paired 1:1 with unlit/additive glow canvases
##   (`_floor_glow_canvas`, `_warn_canvas`, `_sky_fx`), matching `AurelithRig` & `art_desert_ruins.py`.
## - 4 distinct asymmetric Voronoi-sandstone, gold-relief & sun-quartz monolith pillars (`monolith_pillars.png`)
##   with erupting-from-sand animations and molten-cracked superheat states (row 1).
## - 4 organic vitrified fulgurite & snow-quartz crusts (`sintered_plates.png`), 4-frame terraced desert
##   sinkhole maelstroms (`quicksand_vortex.png`), colossal 4-claw buried anvil gauntlet (`buried_gauntlet.png`),
##   carved rune chain-links & arcing geode pods (`chain_links.png`), pharaonic relief crushing walls (`temple_walls.png`),
##   3D gold-astrolabe `Resonanz-Kerne` (`resonance_core.png`), billowing sand-wave barrels (`tsunami_rollers.png`),
##   crystal crescent cleave arcs, erupting fault seams, solar astrolabe mandalas (`slash_and_seams.png`),
##   and spinning faceted crystal/gold shrapnel (`prism_spike_and_shards.png`).

signal core_struck_boss(damage: float, source_peer: int)

const SQUASH: float = 0.72
const WARN_DARK: Color = Color("c21f3b")
const WARN_MID: Color = Color("ff4a63")
const WARN_HOT: Color = Color("ffd0d6")
const GOLD_WARN: Color = Color("ffd86b")
const TURQ_SAFE: Color = Color("78f4e6")
const VIOLET_ARC: Color = Color("c58cff")

const TEX_PILLARS: Texture2D = preload("res://assets/enemies/aurelith_fx/monolith_pillars.png")
const TEX_PILLARS_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/monolith_pillars_glow.png")
const TEX_PLATES: Texture2D = preload("res://assets/enemies/aurelith_fx/sintered_plates.png")
const TEX_PLATES_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/sintered_plates_glow.png")
const TEX_VORTEX: Texture2D = preload("res://assets/enemies/aurelith_fx/quicksand_vortex.png")
const TEX_VORTEX_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/quicksand_vortex_glow.png")
const TEX_GAUNTLET: Texture2D = preload("res://assets/enemies/aurelith_fx/buried_gauntlet.png")
const TEX_GAUNTLET_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/buried_gauntlet_glow.png")
const TEX_LINKS: Texture2D = preload("res://assets/enemies/aurelith_fx/chain_links.png")
const TEX_LINKS_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/chain_links_glow.png")
const TEX_WALLS: Texture2D = preload("res://assets/enemies/aurelith_fx/temple_walls.png")
const TEX_WALLS_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/temple_walls_glow.png")
const TEX_CORE: Texture2D = preload("res://assets/enemies/aurelith_fx/resonance_core.png")
const TEX_CORE_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/resonance_core_glow.png")
const TEX_ROLLERS: Texture2D = preload("res://assets/enemies/aurelith_fx/tsunami_rollers.png")
const TEX_ROLLERS_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/tsunami_rollers_glow.png")
const TEX_SLASH: Texture2D = preload("res://assets/enemies/aurelith_fx/slash_and_seams.png")
const TEX_SLASH_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/slash_and_seams_glow.png")
const TEX_SHARDS: Texture2D = preload("res://assets/enemies/aurelith_fx/prism_spike_and_shards.png")
const TEX_SHARDS_GLOW: Texture2D = preload("res://assets/enemies/aurelith_fx/prism_spike_and_shards_glow.png")

var boss: Aurelith
var center: Vector2 = Vector2.ZERO
var arena_radii: Vector2 = Vector2(290.0, 210.0)

var _clock: float = 0.0
var _floor_canvas: Node2D
var _floor_glow_canvas: Node2D
var _warn_canvas: Node2D
var _pillar_root: Node2D
var _core_root: Node2D
var _sky_body: Node2D
var _sky_fx: Node2D

var _quartz_plates: Array[Dictionary] = [] ## {pos, radius, born, until, variant, flip_x}
var _quicksands: Array[Dictionary] = [] ## {pos, radius, pull, born, until, seed}
var _telegraphs: Array[Dictionary] = [] ## {kind, start, until, ...}
var _pillars: Dictionary = {} ## pillar_id -> PillarNode
var _cores: Dictionary = {} ## core_id -> ResonanceCoreNode
var _temple_walls: Array[Dictionary] = [] ## {pos, axis, len, gap, start, crush_at, until, crushed_fx}
var _gauntlet_anchor: Dictionary = {} ## {active, from, pos, until, yanking, yank_start, yank_dur}
var _solar_beam: Dictionary = {} ## {active, origin, angle, length, splits: Array[Dictionary]}
var _tether_links: Array[Dictionary] = [] ## {a, b, col}
var _tsunami_vis: Dictionary = {} ## {active, dir, progress}
var _sky_bolts: Array[Dictionary] = [] ## {at, age, dur, col, seed}
var _bursts: Array[Dictionary] = [] ## {pos, vel, life, max_life, col, sz}
var _shrapnel: Array[Dictionary] = [] ## {pos, vel, z, vz, rot, spin, life, max_life, kind, scale}
var _slash_arcs: Array[Dictionary] = [] ## {pos, ang, scale, age, dur, flip_y}
var _crystal_seams: Array[Dictionary] = [] ## {from, to, born, until}
var _geode_pods: Array[Dictionary] = [] ## {from, to, age, dur, seed}
var _zenith_seal: Dictionary = {} ## {active, pos, charge}
var _mirage_cd: float = 0.0
var _yank_dust_cd: float = 0.0
var _active_wave_dir: Vector2 = Vector2.ZERO
var _floor_was_active: bool = false
var _warn_was_active: bool = false
var _sky_body_was_active: bool = false
var _sky_fx_was_active: bool = false


func setup(p_boss: Aurelith, p_center: Vector2, p_radii: Vector2) -> void:
	boss = p_boss
	center = p_center
	arena_radii = p_radii
	name = "AurelithField"
	global_position = center
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("resonance_obelisks")

	_floor_canvas = Node2D.new()
	_floor_canvas.name = "FloorMagic"
	_floor_canvas.z_index = -7
	_floor_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor_canvas.draw.connect(_draw_floor)
	add_child(_floor_canvas)

	_floor_glow_canvas = Node2D.new()
	_floor_glow_canvas.name = "FloorMagicGlow"
	_floor_glow_canvas.z_index = -7
	_floor_glow_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var floor_add: CanvasItemMaterial = CanvasItemMaterial.new()
	floor_add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	floor_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_floor_glow_canvas.material = floor_add
	_floor_glow_canvas.draw.connect(_draw_floor_glow)
	add_child(_floor_glow_canvas)

	_warn_canvas = Node2D.new()
	_warn_canvas.name = "Telegraphs"
	_warn_canvas.z_index = -6
	_warn_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_warn_canvas.material = Unlit.material()
	_warn_canvas.draw.connect(_draw_warnings)
	add_child(_warn_canvas)

	_pillar_root = Node2D.new()
	_pillar_root.name = "Pillars"
	_pillar_root.y_sort_enabled = true
	_pillar_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_pillar_root)

	_core_root = Node2D.new()
	_core_root.name = "ResonanceCores"
	_core_root.y_sort_enabled = true
	_core_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_core_root)

	_sky_body = Node2D.new()
	_sky_body.name = "SkyBody"
	_sky_body.z_index = 4
	_sky_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sky_body.draw.connect(_draw_sky_body)
	add_child(_sky_body)

	_sky_fx = Node2D.new()
	_sky_fx.name = "SkyFx"
	_sky_fx.z_index = 5
	_sky_fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sky_fx.material = Unlit.material()
	_sky_fx.draw.connect(_draw_sky_fx)
	add_child(_sky_fx)

	Terrain.patches.append(self)


func _exit_tree() -> void:
	Terrain.patches.erase(self)


func now() -> float:
	return _clock


func clear_all() -> void:
	_quartz_plates.clear()
	_quicksands.clear()
	_telegraphs.clear()
	_temple_walls.clear()
	_gauntlet_anchor.clear()
	_solar_beam.clear()
	_tether_links.clear()
	_tsunami_vis.clear()
	_sky_bolts.clear()
	_bursts.clear()
	_shrapnel.clear()
	_slash_arcs.clear()
	_crystal_seams.clear()
	_geode_pods.clear()
	_zenith_seal.clear()
	_active_wave_dir = Vector2.ZERO
	for pid: int in _pillars.keys():
		var pn: Node2D = _pillars[pid] as Node2D
		if is_instance_valid(pn):
			pn.queue_free()
	_pillars.clear()
	for cid: int in _cores.keys():
		var cn: Node2D = _cores[cid] as Node2D
		if is_instance_valid(cn):
			cn.queue_free()
	_cores.clear()
	if _floor_canvas != null:
		_floor_canvas.queue_redraw()
	if _floor_glow_canvas != null:
		_floor_glow_canvas.queue_redraw()
	if _warn_canvas != null:
		_warn_canvas.queue_redraw()
	if _sky_body != null:
		_sky_body.queue_redraw()
	if _sky_fx != null:
		_sky_fx.queue_redraw()


# --- Terrain & Spell-Recharge Integration --------------------------------------------------------------------------


func surface_at(world_pos: Vector2) -> String:
	for qp: Dictionary in _quartz_plates:
		if _clock < float(qp["until"]):
			var r: float = float(qp["radius"])
			var rel: Vector2 = world_pos - (qp["pos"] as Vector2)
			if Vector2(rel.x / r, rel.y / (r * SQUASH)).length_squared() <= 1.0:
				return "quartz"
	for qs: Dictionary in _quicksands:
		if _clock < float(qs["until"]):
			var rq: float = float(qs["radius"])
			var relq: Vector2 = world_pos - (qs["pos"] as Vector2)
			if Vector2(relq.x / rq, relq.y / (rq * SQUASH)).length_squared() <= 1.0:
				return "quicksand"
	return ""


func recharge_bonus_at(world_pos: Vector2) -> float:
	for pid: int in _pillars:
		var pn: Node2D = _pillars[pid] as Node2D
		if is_instance_valid(pn) and pn.global_position.distance_to(world_pos) <= 92.0:
			return 0.28
	for qp: Dictionary in _quartz_plates:
		if _clock < float(qp["until"]) and (qp["pos"] as Vector2).distance_to(world_pos) <= float(qp["radius"]) + 12.0:
			return 0.18
	return 0.0


# --- Ground Transformations & Pillars ------------------------------------------------------------------------------


func add_quartz_plate(world_pos: Vector2, radius: float, duration: float = 9.0) -> void:
	var clamped: Vector2 = clamp_in_arena(world_pos, 0.88)
	# Sintered quartz solidifies overlapping quicksand!
	_quicksands = _quicksands.filter(func(q: Dictionary) -> bool:
		return (q["pos"] as Vector2).distance_to(clamped) > (radius + float(q["radius"])) * 0.55
	)
	for qp: Dictionary in _quartz_plates:
		if (qp["pos"] as Vector2).distance_to(clamped) <= 42.0:
			qp["until"] = maxf(float(qp["until"]), _clock + duration)
			qp["radius"] = maxf(float(qp["radius"]), radius)
			return
	if _quartz_plates.size() >= 7:
		_quartz_plates.pop_front()
	var h: int = abs(hash(Vector2i(clamped.round())) + _quartz_plates.size() * 13)
	_quartz_plates.append({
		"pos": clamped,
		"radius": radius,
		"born": _clock,
		"until": _clock + duration,
		"variant": h % 4,
		"flip_x": ((h >> 3) & 1) == 1,
	})


func add_quicksand(world_pos: Vector2, radius: float, duration: float = 7.5, pull_speed: float = 48.0) -> void:
	var clamped: Vector2 = clamp_in_arena(world_pos, 0.82)
	for qs: Dictionary in _quicksands:
		if (qs["pos"] as Vector2).distance_to(clamped) <= 48.0:
			qs["until"] = maxf(float(qs["until"]), _clock + duration)
			qs["radius"] = maxf(float(qs["radius"]), radius)
			return
	if _quicksands.size() >= 2:
		_quicksands.pop_front()
	_quicksands.append({
		"pos": clamped,
		"radius": radius,
		"pull": pull_speed,
		"born": _clock,
		"until": _clock + duration,
		"seed": _quicksands.size() * 17 + int(roundi(clamped.x)),
	})


func spawn_pillar(pillar_id: int, world_pos: Vector2, duration: float = 18.0) -> void:
	var clamped: Vector2 = clamp_in_arena(world_pos, 0.84).round()
	if _pillars.has(pillar_id):
		var old_p: Node2D = _pillars[pillar_id] as Node2D
		if is_instance_valid(old_p):
			old_p.queue_free()
		_pillars.erase(pillar_id)
	var near_ids: Array[int] = []
	for near_pid: int in _pillars:
		var near_pn: PillarNode = _pillars[near_pid] as PillarNode
		if is_instance_valid(near_pn) and near_pn.global_position.distance_to(clamped) < 52.0:
			near_ids.append(near_pid)
	for near_pid2: int in near_ids:
		shatter_pillar(near_pid2, false)
	# Cap at 3 standing pillars so the arena stays clear, readable & fair
	while _pillars.size() >= 3:
		var oldest_id: int = int(_pillars.keys()[0])
		shatter_pillar(oldest_id, false)
	var node: PillarNode = PillarNode.new()
	node.pillar_id = pillar_id
	node.field = self
	node.position = clamped - center
	node.born = _clock
	node.until = _clock + duration
	node.setup_visuals(posmod(pillar_id - 1, 4))
	_pillar_root.add_child(node)
	_pillars[pillar_id] = node
	add_quartz_plate(clamped, 28.0, duration)
	spawn_burst(clamped, 7, TURQ_SAFE)
	spawn_shrapnel(clamped, 4, 0.72)


func shatter_pillar(pillar_id: int, with_shrapnel: bool = true) -> Vector2:
	if not _pillars.has(pillar_id):
		return Vector2.INF
	var node: PillarNode = _pillars[pillar_id] as PillarNode
	_pillars.erase(pillar_id)
	if not is_instance_valid(node):
		return Vector2.INF
	var wp: Vector2 = node.global_position
	node.queue_free()
	if with_shrapnel:
		spawn_burst(wp, 16, GOLD_WARN)
		spawn_shrapnel(wp, 11, 1.05)
		ShockRing.burst(self, wp - center, 44.0, 0.6)
	return wp


func pillar_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pid: int in _pillars:
		var pn: PillarNode = _pillars[pid] as PillarNode
		if is_instance_valid(pn):
			out.append(pn.global_position)
	return out


func find_pillars_near(world_pos: Vector2, radius: float) -> Array[int]:
	var ids: Array[int] = []
	for pid: int in _pillars:
		var pn: PillarNode = _pillars[pid] as PillarNode
		if is_instance_valid(pn) and pn.global_position.distance_to(world_pos) <= radius:
			ids.append(pid)
	return ids


## Ray-circle check against standing pillars for `SOLAR_BEAM` cover: returns `{dist, pillar_id}` (`pillar_id = -1` if unblocked).
func clip_beam_against_pillars(origin: Vector2, dir: Vector2, max_len: float, delta: float) -> Dictionary:
	var best_d: float = max_len
	var hit_id: int = -1
	for pid: int in _pillars:
		var pn: PillarNode = _pillars[pid] as PillarNode
		if not is_instance_valid(pn):
			continue
		var rel: Vector2 = pn.global_position - origin
		var proj: float = rel.dot(dir)
		if proj < 12.0 or proj > best_d:
			continue
		var perp: float = absf(rel.x * (-dir.y) + rel.y * dir.x)
		if perp <= 16.0:
			best_d = proj
			hit_id = pid
	if hit_id >= 0 and delta > 0.0:
		var hit_node: PillarNode = _pillars[hit_id] as PillarNode
		if is_instance_valid(hit_node):
			hit_node.beam_heat += delta
	return {"dist": best_d, "pillar_id": hit_id}


## True when `world_pos` sits inside the wind-shadow wedge behind any standing pillar relative to `wave_dir`.
func is_sheltered_behind_pillar(world_pos: Vector2, wave_dir: Vector2) -> bool:
	var wn: Vector2 = wave_dir.normalized()
	for pid: int in _pillars:
		var pn: PillarNode = _pillars[pid] as PillarNode
		if not is_instance_valid(pn):
			continue
		var rel: Vector2 = world_pos - pn.global_position
		var downstream: float = rel.dot(wn)
		if downstream >= 4.0 and downstream <= 86.0:
			var lateral: float = absf(rel.x * (-wn.y) + rel.y * wn.x)
			if lateral <= 18.0 + downstream * 0.28:
				return true
	return false


## True when a standing pillar blocks direct line of sight from `origin` to `world_pos` (survives partial `ZENIT-NOVA`).
func has_pillar_cover_from(origin: Vector2, world_pos: Vector2) -> bool:
	var to_p: Vector2 = world_pos - origin
	var dist: float = to_p.length()
	if dist < 24.0:
		return false
	var dir: Vector2 = to_p / dist
	for pid: int in _pillars:
		var pn: PillarNode = _pillars[pid] as PillarNode
		if not is_instance_valid(pn):
			continue
		var rel: Vector2 = pn.global_position - origin
		var proj: float = rel.dot(dir)
		if proj > 14.0 and proj < dist - 4.0:
			var perp: float = absf(rel.x * (-dir.y) + rel.y * dir.x)
			if perp <= 22.0:
				return true
	return false


# --- Reflected `Resonanz-Kerne` (100 % Weapon & Spell Parity) ------------------------------------------------------


func spawn_resonance_core(core_id: int, world_pos: Vector2, lifetime: float = 5.8) -> void:
	var clamped: Vector2 = clamp_in_arena(world_pos, 0.88).round()
	if _cores.has(core_id):
		var prev: Node2D = _cores[core_id] as Node2D
		if is_instance_valid(prev):
			prev.queue_free()
		_cores.erase(core_id)
	var unlaunched: Array[int] = active_core_ids()
	while unlaunched.size() >= 4:
		var old_cid: int = int(unlaunched.pop_front())
		if _cores.has(old_cid):
			var old_cn: Node2D = _cores[old_cid] as Node2D
			_cores.erase(old_cid)
			if is_instance_valid(old_cn):
				old_cn.queue_free()
	var node: ResonanceCoreNode = ResonanceCoreNode.new()
	node.core_id = core_id
	node.field = self
	node.position = clamped - center
	node.max_life = lifetime
	_core_root.add_child(node)
	_cores[core_id] = node
	spawn_burst(clamped, 6, TURQ_SAFE)
	spawn_shrapnel(clamped, 3, 0.65)


func launch_core_at_boss(core_id: int, source_peer: int) -> void:
	if not _cores.has(core_id):
		return
	var node: ResonanceCoreNode = _cores[core_id] as ResonanceCoreNode
	if not is_instance_valid(node) or node.launched:
		return
	node.launched = true
	node.source_peer = source_peer
	node.life = 0.0
	node.max_life = 2.5
	node.disable_hurtbox()
	spawn_burst(node.global_position, 10, GOLD_WARN)
	ShockRing.burst(self, node.position + Vector2(0.0, -14.0), 30.0, 0.7)


func active_core_ids() -> Array[int]:
	var out: Array[int] = []
	for cid: int in _cores:
		var cn: ResonanceCoreNode = _cores[cid] as ResonanceCoreNode
		if is_instance_valid(cn) and not cn.launched:
			out.append(cid)
	return out


func core_world_pos(core_id: int) -> Vector2:
	if _cores.has(core_id):
		var cn: ResonanceCoreNode = _cores[core_id] as ResonanceCoreNode
		if is_instance_valid(cn):
			return cn.global_position
	return Vector2.INF


func _on_core_hurtbox_struck(core_id: int, source_peer: int) -> void:
	if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if is_instance_valid(boss) and boss.fight != null:
			boss.fight.host_reflect_core(core_id, source_peer)


# --- Telegraphs & Visual Effects -----------------------------------------------------------------------------------


func warn_circle(world_pos: Vector2, radius: float, duration: float, inner_radius: float = 0.0, tint: Color = WARN_MID) -> void:
	_telegraphs.append({
		"kind": "circle",
		"pos": world_pos - center,
		"r": radius,
		"inner_r": inner_radius,
		"start": _clock,
		"until": _clock + maxf(duration, 0.08),
		"tint": tint,
	})


func warn_box(from_world: Vector2, to_world: Vector2, half_width: float, duration: float, tint: Color = WARN_MID) -> void:
	_telegraphs.append({
		"kind": "box",
		"from": from_world - center,
		"to": to_world - center,
		"hw": half_width,
		"start": _clock,
		"until": _clock + maxf(duration, 0.08),
		"tint": tint,
	})


func warn_cone(origin_world: Vector2, angle: float, half_arc: float, radius: float, duration: float, tint: Color = WARN_MID) -> void:
	_telegraphs.append({
		"kind": "cone",
		"origin": origin_world - center,
		"ang": angle,
		"arc": half_arc,
		"r": radius,
		"start": _clock,
		"until": _clock + maxf(duration, 0.08),
		"tint": tint,
	})


func warn_armillary(duration: float, base_seed: float) -> void:
	_telegraphs.append({
		"kind": "armillary",
		"seed": base_seed,
		"start": _clock,
		"until": _clock + maxf(duration, 0.1),
	})


func set_gauntlet_anchor(active: bool, from_world: Vector2 = Vector2.ZERO, at_world: Vector2 = Vector2.ZERO, hold_dur: float = 2.2) -> void:
	if not active:
		_gauntlet_anchor.clear()
		return
	_gauntlet_anchor = {
		"active": true,
		"from": from_world - center,
		"pos": at_world - center,
		"until": _clock + hold_dur,
		"yanking": false,
		"yank_start": 0.0,
		"yank_dur": 0.32,
	}


func trigger_gauntlet_yank(to_world: Vector2, dur: float = 0.32) -> void:
	if _gauntlet_anchor.is_empty():
		return
	_gauntlet_anchor["yanking"] = true
	_gauntlet_anchor["yank_to"] = to_world - center
	_gauntlet_anchor["yank_start"] = _clock
	_gauntlet_anchor["yank_dur"] = maxf(dur, 0.08)
	_gauntlet_anchor["until"] = _clock + dur + 0.05


func add_temple_press_visual(center_world: Vector2, axis_dir: Vector2, wall_len: float, start_half_gap: float, prep_dur: float) -> void:
	_temple_walls.append({
		"pos": center_world - center,
		"axis": axis_dir.normalized(),
		"len": wall_len,
		"gap": start_half_gap,
		"start": _clock,
		"crush_at": _clock + prep_dur,
		"until": _clock + prep_dur + 0.44,
		"crushed_fx": false,
	})
	var ax: Vector2 = axis_dir.normalized()
	spawn_burst(center_world - ax * start_half_gap, 10, AurelithRig.SD_4)
	spawn_burst(center_world + ax * start_half_gap, 10, AurelithRig.SD_4)


func set_solar_beam(active: bool, origin_world: Vector2 = Vector2.ZERO, angle: float = 0.0, length: float = 300.0, splits: Array[Dictionary] = []) -> void:
	if not active:
		_solar_beam.clear()
		return
	_solar_beam = {
		"active": true,
		"origin": origin_world - center,
		"angle": angle,
		"length": length,
		"splits": splits,
	}


func set_tether_links(links: Array[Dictionary]) -> void:
	_tether_links = links


func set_tsunami_wave(active: bool, wave_dir: Vector2 = Vector2.ZERO, progress: float = 0.0) -> void:
	if not active:
		_tsunami_vis.clear()
		_active_wave_dir = wave_dir.normalized() if wave_dir != Vector2.ZERO else Vector2.ZERO
		return
	_active_wave_dir = wave_dir.normalized()
	_tsunami_vis = {
		"active": true,
		"dir": _active_wave_dir,
		"progress": progress,
	}


func set_zenith_seal(active: bool, world_pos: Vector2 = Vector2.ZERO, charge_q: float = 0.0) -> void:
	if not active:
		_zenith_seal.clear()
		return
	_zenith_seal = {
		"active": true,
		"pos": world_pos - center,
		"charge": clampf(charge_q, 0.0, 1.0),
	}


func spawn_slash_arc(origin_world: Vector2, angle: float, scale_mul: float = 1.0, dur: float = 0.36, flip_y: bool = false) -> void:
	if _slash_arcs.size() >= 8:
		_slash_arcs.pop_front()
	_slash_arcs.append({
		"pos": origin_world - center,
		"ang": angle,
		"scale": scale_mul,
		"age": 0.0,
		"dur": maxf(dur, 0.1),
		"flip_y": flip_y,
	})


func add_crystal_seam(from_world: Vector2, to_world: Vector2, dur: float = 0.78) -> void:
	if _crystal_seams.size() >= 10:
		_crystal_seams.pop_front()
	_crystal_seams.append({
		"from": from_world - center,
		"to": to_world - center,
		"born": _clock,
		"until": _clock + maxf(dur, 0.12),
	})


func spawn_geode_pod(from_world: Vector2, to_world: Vector2, dur: float = 0.76) -> void:
	_geode_pods.append({
		"from": from_world - center,
		"to": to_world - center,
		"age": 0.0,
		"dur": maxf(dur, 0.15),
		"seed": randf_range(0.0, TAU),
	})


func step_mirage_trail(world_pos: Vector2, delta: float) -> void:
	_mirage_cd -= delta
	if _mirage_cd <= 0.0:
		_mirage_cd = 0.075
		var ang: float = _clock * 9.0
		spawn_slash_arc(world_pos + Vector2(0.0, -26.0), ang, 0.74, 0.28, int(floorf(_clock * 20.0)) % 2 == 0)
		spawn_burst(world_pos, 5, GOLD_WARN)


func spawn_sky_bolt(world_pos: Vector2, col: Color = GOLD_WARN, dur: float = 0.38) -> void:
	_sky_bolts.append({
		"at": world_pos - center,
		"age": 0.0,
		"dur": dur,
		"col": col,
		"seed": randf_range(0.0, 100.0),
	})
	spawn_burst(world_pos, 12, col)
	spawn_shrapnel(world_pos, 5, 0.85)


func spawn_shrapnel(world_pos: Vector2, count: int = 8, speed_mul: float = 1.0) -> void:
	var rel: Vector2 = world_pos - center
	for i: int in count:
		var ang: float = TAU * float(i) / float(maxi(count, 1)) + randf_range(-0.26, 0.26)
		var spd: float = randf_range(34.0, 108.0) * speed_mul
		if _shrapnel.size() >= 36:
			_shrapnel.pop_front()
		_shrapnel.append({
			"pos": rel + Vector2(randf_range(-5.0, 5.0), randf_range(-3.0, 3.0)),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd * SQUASH),
			"z": randf_range(4.0, 14.0),
			"vz": randf_range(75.0, 145.0) * speed_mul,
			"rot": randf_range(0.0, TAU),
			"spin": randf_range(-11.0, 11.0),
			"life": 0.0,
			"max_life": randf_range(0.46, 0.76),
			"kind": (i + randi()) % 4,
			"scale": randf_range(0.68, 0.98),
		})


func spawn_burst(world_pos: Vector2, count: int, col: Color) -> void:
	var rel: Vector2 = world_pos - center
	for i: int in count:
		var ang: float = TAU * float(i) / float(maxi(count, 1)) + randf_range(-0.25, 0.25)
		var spd: float = randf_range(26.0, 96.0)
		if _bursts.size() >= 48:
			_bursts.pop_front()
		_bursts.append({
			"pos": rel + Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0)),
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd * SQUASH - randf_range(18.0, 52.0)),
			"life": randf_range(0.32, 0.68),
			"max_life": 0.68,
			"col": Color("ffffff") if i % 4 == 0 else col,
			"sz": 3.0 if i % 3 == 0 else 2.0,
		})


func clamp_in_arena(world_pos: Vector2, margin_ratio: float = 0.86) -> Vector2:
	var lim: Vector2 = arena_radii * margin_ratio
	var rel: Vector2 = (world_pos - center) / lim
	if rel.length_squared() > 1.0:
		return center + rel.normalized() * lim
	return world_pos


# --- Frame Tick & Physics ------------------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_clock += delta

	# Local-authority quicksand pull on players standing inside an active maelstrom
	if not _quicksands.is_empty():
		for player: Player in Player.all:
			if player == null or not is_instance_valid(player) or player.health.current <= 0.0:
				continue
			if not player.is_multiplayer_authority():
				continue
			if player.talismans != null and player.talismans.perks.has("prism_break"):
				continue
			if Terrain.surface_at(player.global_position) == "quartz":
				continue
			for qs: Dictionary in _quicksands:
				if _clock >= float(qs["until"]):
					continue
				var qpos: Vector2 = qs["pos"] as Vector2
				var rq: float = float(qs["radius"])
				var diff: Vector2 = qpos - player.global_position
				var ell_d: float = Vector2(diff.x / rq, diff.y / (rq * SQUASH)).length()
				if ell_d > 0.08 and ell_d <= 1.0:
					var pull_v: Vector2 = diff.normalized() * float(qs["pull"]) * (1.15 - 0.45 * ell_d)
					player.move_and_collide(pull_v * delta)

	# Advance launched `Resonanz-Kerne` homing straight into Aurelith!
	var finished_cores: Array[int] = []
	for cid: int in _cores:
		var cn: ResonanceCoreNode = _cores[cid] as ResonanceCoreNode
		if not is_instance_valid(cn):
			finished_cores.append(cid)
			continue
		cn.life += delta
		if cn.launched:
			if not is_instance_valid(boss):
				finished_cores.append(cid)
				continue
			var goal: Vector2 = (boss.global_position + Vector2(0.0, -36.0)) - center
			cn.set_travel_dir((goal - cn.position).normalized())
			cn.position = cn.position.move_toward(goal, 390.0 * delta)
			if cn.position.distance_to(goal) <= 18.0:
				spawn_burst(boss.global_position + Vector2(0.0, -34.0), 16, TURQ_SAFE)
				spawn_shrapnel(boss.global_position + Vector2(0.0, -20.0), 8, 0.95)
				ShockRing.burst(self, goal, 52.0, 0.65)
				if multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
					core_struck_boss.emit(110.0, cn.source_peer)
				finished_cores.append(cid)
		elif cn.life >= cn.max_life:
			finished_cores.append(cid)
	for cid_done: int in finished_cores:
		if _cores.has(cid_done):
			var dead_c: Node2D = _cores[cid_done] as Node2D
			_cores.erase(cid_done)
			if is_instance_valid(dead_c):
				dead_c.queue_free()

	# Expire melted or timed-out pillars
	var expired_pillars: Array[int] = []
	for pid: int in _pillars:
		var pn: PillarNode = _pillars[pid] as PillarNode
		if not is_instance_valid(pn) or _clock >= pn.until or pn.beam_heat >= 1.15:
			expired_pillars.append(pid)
	for pid_exp: int in expired_pillars:
		shatter_pillar(pid_exp, true)


func _process(delta: float) -> void:
	if not _quartz_plates.is_empty():
		_quartz_plates = _quartz_plates.filter(func(q: Dictionary) -> bool: return _clock < float(q["until"]))
	if not _quicksands.is_empty():
		_quicksands = _quicksands.filter(func(q: Dictionary) -> bool: return _clock < float(q["until"]))
	if not _telegraphs.is_empty():
		_telegraphs = _telegraphs.filter(func(w: Dictionary) -> bool: return _clock < float(w["until"]))
	if not _crystal_seams.is_empty():
		_crystal_seams = _crystal_seams.filter(func(cs: Dictionary) -> bool: return _clock < float(cs["until"]))
	if not _temple_walls.is_empty():
		for tw: Dictionary in _temple_walls:
			if not bool(tw.get("crushed_fx", false)) and _clock >= float(tw["crush_at"]):
				tw["crushed_fx"] = true
				spawn_shrapnel(center + (tw["pos"] as Vector2), 10, 1.0)
		_temple_walls = _temple_walls.filter(func(tw2: Dictionary) -> bool: return _clock < float(tw2["until"]))
	if not _gauntlet_anchor.is_empty():
		if bool(_gauntlet_anchor.get("yanking", false)):
			_yank_dust_cd -= delta
			if _yank_dust_cd <= 0.0:
				_yank_dust_cd = 0.045
				var yq_d: float = clampf((_clock - float(_gauntlet_anchor["yank_start"])) / float(_gauntlet_anchor["yank_dur"]), 0.0, 1.0)
				var g_cur: Vector2 = (_gauntlet_anchor["pos"] as Vector2).lerp(_gauntlet_anchor["yank_to"] as Vector2, yq_d)
				spawn_burst(center + g_cur, 4, AurelithRig.SD_4)
		if _clock >= float(_gauntlet_anchor.get("until", 0.0)):
			_gauntlet_anchor.clear()

	for b: Dictionary in _sky_bolts:
		b["age"] = float(b["age"]) + delta
	if not _sky_bolts.is_empty():
		_sky_bolts = _sky_bolts.filter(func(b: Dictionary) -> bool: return float(b["age"]) < float(b["dur"]))

	for sa: Dictionary in _slash_arcs:
		sa["age"] = float(sa["age"]) + delta
	if not _slash_arcs.is_empty():
		_slash_arcs = _slash_arcs.filter(func(sa: Dictionary) -> bool: return float(sa["age"]) < float(sa["dur"]))

	for gp: Dictionary in _geode_pods:
		gp["age"] = float(gp["age"]) + delta
	if not _geode_pods.is_empty():
		_geode_pods = _geode_pods.filter(func(gp: Dictionary) -> bool: return float(gp["age"]) < float(gp["dur"]))

	for sh: Dictionary in _shrapnel:
		sh["life"] = float(sh["life"]) + delta
		sh["pos"] = (sh["pos"] as Vector2) + (sh["vel"] as Vector2) * delta
		var vz_now: float = float(sh["vz"]) - 360.0 * delta
		var z_now: float = float(sh["z"]) + vz_now * delta
		if z_now < 0.0:
			z_now = 0.0
			vz_now = absf(vz_now) * 0.42
			sh["vel"] = (sh["vel"] as Vector2) * 0.68
		sh["z"] = z_now
		sh["vz"] = vz_now
		sh["rot"] = float(sh["rot"]) + float(sh["spin"]) * delta
	if not _shrapnel.is_empty():
		_shrapnel = _shrapnel.filter(func(sh2: Dictionary) -> bool: return float(sh2["life"]) < float(sh2["max_life"]))

	for m: Dictionary in _bursts:
		m["life"] = float(m["life"]) - delta
		var vel: Vector2 = m["vel"] as Vector2
		vel.y += 140.0 * delta
		m["vel"] = vel
		m["pos"] = (m["pos"] as Vector2) + vel * delta
	if not _bursts.is_empty():
		_bursts = _bursts.filter(func(m: Dictionary) -> bool: return float(m["life"]) > 0.0)

	var floor_active: bool = not _quicksands.is_empty() or not _quartz_plates.is_empty()
	if floor_active or _floor_was_active:
		_floor_canvas.queue_redraw()
		_floor_glow_canvas.queue_redraw()
	_floor_was_active = floor_active

	var warn_active: bool = not _telegraphs.is_empty() or _active_wave_dir != Vector2.ZERO or bool(_zenith_seal.get("active", false))
	if warn_active or _warn_was_active:
		_warn_canvas.queue_redraw()
	_warn_was_active = warn_active

	var sky_body_active: bool = (
		not _crystal_seams.is_empty()
		or not _tether_links.is_empty()
		or bool(_gauntlet_anchor.get("active", false))
		or not _temple_walls.is_empty()
		or not _geode_pods.is_empty()
		or bool(_tsunami_vis.get("active", false))
		or not _slash_arcs.is_empty()
		or not _shrapnel.is_empty()
	)
	if sky_body_active or _sky_body_was_active:
		_sky_body.queue_redraw()
	_sky_body_was_active = sky_body_active

	var sky_fx_active: bool = sky_body_active or bool(_solar_beam.get("active", false)) or not _sky_bolts.is_empty() or not _bursts.is_empty()
	if sky_fx_active or _sky_fx_was_active:
		_sky_fx.queue_redraw()
	_sky_fx_was_active = sky_fx_active


# --- Drawing: Textured Ground Magic (`_floor_canvas` + `_floor_glow_canvas`) ---------------------------------------


func _draw_floor() -> void:
	# 1) Swirling 4-Frame Terraced Quicksand Maelstroms (`quicksand_vortex.png`)
	for qs: Dictionary in _quicksands:
		var rem: float = clampf((float(qs["until"]) - _clock) / 0.6, 0.0, 1.0)
		var grow: float = clampf((_clock - float(qs["born"])) / 0.32, 0.0, 1.0)
		var a: float = rem * grow
		if a <= 0.02:
			continue
		var pos: Vector2 = (qs["pos"] as Vector2) - center
		var r: float = float(qs["radius"]) * grow
		var seed_i: int = int(qs["seed"])
		var frame: int = posmod(int(floorf(_clock * 8.0)) + seed_i, 4)
		var draw_w: float = roundf(r * 2.22)
		var draw_h: float = roundf(draw_w * (92.0 / 128.0))
		var dst: Rect2 = Rect2((pos - Vector2(draw_w, draw_h) * 0.5).round(), Vector2(draw_w, draw_h))
		var src: Rect2 = Rect2(float(frame) * 128.0, 0.0, 128.0, 92.0)
		_floor_canvas.draw_texture_rect_region(TEX_VORTEX, dst, src, Color(1.0, 1.0, 1.0, a))

		# Orbiting desert pebbles & sandstone crumbs spiraling into the funnel throat
		for k: int in 9:
			var u_orb: float = fmod(_clock * 0.65 + float(k) / 9.0 + float(seed_i % 7) * 0.11, 1.0)
			var rr: float = r * lerpf(0.88, 0.14, u_orb)
			var ang: float = -_clock * (2.2 + 1.8 * u_orb) + float(k) * (TAU / 9.0)
			var pt: Vector2 = (pos + Vector2(cos(ang) * rr, sin(ang) * rr * SQUASH)).round()
			var p_col: Color = AurelithRig.GD_2 if k % 4 == 0 else (AurelithRig.ST_2 if k % 2 == 0 else AurelithRig.SD_4)
			_floor_canvas.draw_rect(Rect2(pt, Vector2(2.0, 2.0)), Color(p_col, a * sin(u_orb * PI)))

	# 2) Organic Vitrified Sintered-Quartz & Fulgurite Crusts (`sintered_plates.png`, 4 variants)
	for qp: Dictionary in _quartz_plates:
		var rem_q: float = clampf((float(qp["until"]) - _clock) / 0.8, 0.0, 1.0)
		var grow_q: float = clampf((_clock - float(qp["born"])) / 0.22, 0.0, 1.0)
		var aq: float = rem_q * grow_q
		if aq <= 0.02:
			continue
		var qpos: Vector2 = ((qp["pos"] as Vector2) - center).round()
		var rq: float = float(qp["radius"]) * grow_q
		var variant: int = int(qp.get("variant", 0))
		var flip_x: bool = bool(qp.get("flip_x", false))
		var draw_w: float = roundf(rq * 2.34)
		var draw_h: float = roundf(draw_w * (58.0 / 80.0))
		var src_q: Rect2 = Rect2(float(variant) * 80.0, 0.0, 80.0, 58.0)
		_floor_canvas.draw_set_transform(qpos, 0.0, Vector2(-1.0 if flip_x else 1.0, 1.0))
		_floor_canvas.draw_texture_rect_region(TEX_PLATES, Rect2(-Vector2(draw_w, draw_h) * 0.5, Vector2(draw_w, draw_h)), src_q, Color(1.0, 1.0, 1.0, aq))
	_floor_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_floor_glow() -> void:
	for qs: Dictionary in _quicksands:
		var rem: float = clampf((float(qs["until"]) - _clock) / 0.6, 0.0, 1.0)
		var grow: float = clampf((_clock - float(qs["born"])) / 0.32, 0.0, 1.0)
		var a: float = rem * grow * (0.76 + 0.24 * sin(_clock * 6.5))
		if a <= 0.02:
			continue
		var pos: Vector2 = (qs["pos"] as Vector2) - center
		var r: float = float(qs["radius"]) * grow
		var frame: int = posmod(int(floorf(_clock * 8.0)) + int(qs["seed"]), 4)
		var draw_w: float = roundf(r * 2.22)
		var draw_h: float = roundf(draw_w * (92.0 / 128.0))
		var dst: Rect2 = Rect2((pos - Vector2(draw_w, draw_h) * 0.5).round(), Vector2(draw_w, draw_h))
		_floor_glow_canvas.draw_texture_rect_region(TEX_VORTEX_GLOW, dst, Rect2(float(frame) * 128.0, 0.0, 128.0, 92.0), Color(1.0, 1.0, 1.0, a))

	for qp: Dictionary in _quartz_plates:
		var rem_q: float = clampf((float(qp["until"]) - _clock) / 0.8, 0.0, 1.0)
		var grow_q: float = clampf((_clock - float(qp["born"])) / 0.22, 0.0, 1.0)
		var aq: float = rem_q * grow_q * (0.72 + 0.28 * sin(_clock * 5.2 + float(qp.get("variant", 0))))
		if aq <= 0.02:
			continue
		var qpos: Vector2 = ((qp["pos"] as Vector2) - center).round()
		var rq: float = float(qp["radius"]) * grow_q
		var variant: int = int(qp.get("variant", 0))
		var flip_x: bool = bool(qp.get("flip_x", false))
		var draw_w: float = roundf(rq * 2.34)
		var draw_h: float = roundf(draw_w * (58.0 / 80.0))
		_floor_glow_canvas.draw_set_transform(qpos, 0.0, Vector2(-1.0 if flip_x else 1.0, 1.0))
		_floor_glow_canvas.draw_texture_rect_region(TEX_PLATES_GLOW, Rect2(-Vector2(draw_w, draw_h) * 0.5, Vector2(draw_w, draw_h)), Rect2(float(variant) * 80.0, 0.0, 80.0, 58.0), Color(1.0, 1.0, 1.0, aq))
	_floor_glow_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Drawing: Sun-Architect Astrolabe Telegraphs (`_warn_canvas`) --------------------------------------------------


func _draw_warnings() -> void:
	# Grand Zenith / Armillary Solar Astrolabe floor mandala beneath Aurelith
	if not _zenith_seal.is_empty() and bool(_zenith_seal.get("active", false)):
		var zpos: Vector2 = _zenith_seal["pos"] as Vector2
		var zq: float = float(_zenith_seal.get("charge", 0.5))
		var sc_z: float = 1.15 + 0.55 * zq
		_warn_canvas.draw_set_transform(zpos.round(), _clock * 1.1, Vector2(sc_z, sc_z * SQUASH))
		_warn_canvas.draw_texture_rect_region(TEX_SLASH_GLOW, Rect2(Vector2(-56.0, -42.0), Vector2(112.0, 84.0)), Rect2(336.0, 0.0, 112.0, 84.0), Color(1.0, 1.0, 1.0, 0.72 + 0.25 * zq))
		_warn_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Highlight turquoise wind-shadow shelters behind standing pillars during Dune Tsunami!
	if _active_wave_dir != Vector2.ZERO:
		var wn: Vector2 = _active_wave_dir
		var wp_perp: Vector2 = Vector2(-wn.y, wn.x)
		for pid: int in _pillars:
			var pn: PillarNode = _pillars[pid] as PillarNode
			if not is_instance_valid(pn):
				continue
			var origin: Vector2 = pn.position
			var wedge: PackedVector2Array = PackedVector2Array([
				origin + wp_perp * 16.0,
				origin - wp_perp * 16.0,
				origin + wn * 84.0 - wp_perp * 40.0,
				origin + wn * 84.0 + wp_perp * 40.0,
				origin + wp_perp * 16.0,
			])
			var pulse_w: float = 0.20 + 0.08 * sin(_clock * 9.0)
			_warn_canvas.draw_colored_polygon(wedge.slice(0, 4), Color(TURQ_SAFE, pulse_w))
			_warn_canvas.draw_polyline(wedge, Color(TURQ_SAFE, 0.84), 1.5)
			# Animated downstream safe-shelter sun-chevrons inside the leeward corridor
			for ch_i: int in 3:
				var u_ch: float = fmod(float(ch_i) / 3.0 + _clock * 0.85, 1.0)
				var d_ch: float = lerpf(16.0, 74.0, u_ch)
				var w_ch: float = lerpf(9.0, 22.0, u_ch)
				var apex: Vector2 = origin + wn * (d_ch + 8.0)
				var chev: PackedVector2Array = PackedVector2Array([
					(origin + wn * d_ch - wp_perp * w_ch).round(),
					apex.round(),
					(origin + wn * d_ch + wp_perp * w_ch).round(),
				])
				_warn_canvas.draw_polyline(chev, Color(Color.WHITE if ch_i == 0 else TURQ_SAFE, sin(u_ch * PI) * 0.78), 1.5)

	for w: Dictionary in _telegraphs:
		var dur: float = maxf(float(w["until"]) - float(w["start"]), 0.05)
		var p: float = clampf((_clock - float(w["start"])) / dur, 0.0, 1.0)
		var flash: bool = p > 0.82 and int(floorf(_clock * 24.0)) % 2 == 0
		var tint: Color = w.get("tint", WARN_MID) as Color
		var edge_col: Color = WARN_HOT if flash else tint
		var fill_a: float = 0.13 + 0.24 * p
		match String(w["kind"]):
			"circle":
				var cpos: Vector2 = w["pos"] as Vector2
				var r: float = float(w["r"])
				var inner_r: float = float(w.get("inner_r", 0.0))
				if inner_r <= 0.5:
					_draw_ellipse_poly(_warn_canvas, cpos, r, r * SQUASH, Color(WARN_DARK, fill_a * 0.72), 32)
					_draw_ellipse_poly(_warn_canvas, cpos, r * p, r * p * SQUASH, Color(edge_col, fill_a), 28)
					_draw_ellipse_ring(_warn_canvas, cpos, r, r * SQUASH, Color(edge_col, 0.92), 36)
					if r >= 22.0:
						_draw_ellipse_ring(_warn_canvas, cpos, r - 3.5, (r - 3.5) * SQUASH, Color(GOLD_WARN, 0.62), 32)
						# 8 Sun-Architect astrolabe degree notches + inner rotating sun-diamond seal
						var ticks_n: int = 12 if r > 120.0 else 8
						for ti: int in ticks_n:
							var ta: float = TAU * float(ti) / float(ticks_n) + _clock * 0.35
							var t0: Vector2 = (cpos + Vector2(cos(ta) * (r - 5.5), sin(ta) * (r - 5.5) * SQUASH)).round()
							var t1: Vector2 = (cpos + Vector2(cos(ta) * (r + 1.5), sin(ta) * (r + 1.5) * SQUASH)).round()
							_warn_canvas.draw_line(t0, t1, Color(GOLD_WARN if ti % 2 == 0 else edge_col, 0.85), 1.5)
						var star_r: float = maxf(6.0, r * p)
						var star_pts: PackedVector2Array = PackedVector2Array()
						for si: int in 9:
							var sa: float = -_clock * 1.1 + TAU * float(si) / 8.0
							var mk: float = 1.0 if si % 2 == 0 else 0.76
							star_pts.append((cpos + Vector2(cos(sa) * star_r * mk, sin(sa) * star_r * SQUASH * mk)).round())
						_warn_canvas.draw_polyline(star_pts, Color(GOLD_WARN, 0.65), 1.2)
				else:
					_draw_ring_band(_warn_canvas, cpos, inner_r, r, Color(edge_col, fill_a + 0.12), Color(edge_col, 0.92))
					for ti2: int in 12:
						var ta2: float = TAU * float(ti2) / 12.0 - _clock * 0.4
						var p_in: Vector2 = (cpos + Vector2(cos(ta2) * inner_r, sin(ta2) * inner_r * SQUASH)).round()
						var p_out: Vector2 = (cpos + Vector2(cos(ta2) * r, sin(ta2) * r * SQUASH)).round()
						_warn_canvas.draw_line(p_in, p_in.lerp(p_out, 0.22), Color(GOLD_WARN, 0.75), 1.5)
						_warn_canvas.draw_line(p_out.lerp(p_in, 0.22), p_out, Color(GOLD_WARN, 0.75), 1.5)
			"box":
				var a_pt: Vector2 = w["from"] as Vector2
				var b_pt: Vector2 = w["to"] as Vector2
				var hw: float = float(w["hw"])
				var ab_len: float = a_pt.distance_to(b_pt)
				if ab_len <= 1.0:
					continue
				var dir: Vector2 = (b_pt - a_pt) / ab_len
				var nrm: Vector2 = Vector2(-dir.y, dir.x)
				var quad: PackedVector2Array = PackedVector2Array([
					a_pt + nrm * hw, b_pt + nrm * hw, b_pt - nrm * hw, a_pt - nrm * hw, a_pt + nrm * hw
				])
				_warn_canvas.draw_colored_polygon(quad.slice(0, 4), Color(WARN_DARK, fill_a * 0.78))
				var sweep_hw: float = hw * p
				var sweep_q: PackedVector2Array = PackedVector2Array([
					a_pt + nrm * sweep_hw, b_pt + nrm * sweep_hw, b_pt - nrm * sweep_hw, a_pt - nrm * sweep_hw
				])
				_warn_canvas.draw_colored_polygon(sweep_q, Color(edge_col, fill_a))
				_warn_canvas.draw_polyline(quad, Color(edge_col, 0.92), 1.5)
				# Engraved inner golden cartouche rails + directional sun-chevrons
				var in_hw: float = maxf(2.0, hw - 3.0)
				_warn_canvas.draw_line((a_pt + nrm * in_hw).round(), (b_pt + nrm * in_hw).round(), Color(GOLD_WARN, 0.58), 1.0)
				_warn_canvas.draw_line((a_pt - nrm * in_hw).round(), (b_pt - nrm * in_hw).round(), Color(GOLD_WARN, 0.58), 1.0)
				var chev_cnt: int = clampi(int(ab_len / 38.0), 1, 6)
				for ci: int in chev_cnt:
					var cu: float = (float(ci) + 0.5) / float(chev_cnt)
					var cp: Vector2 = a_pt.lerp(b_pt, cu)
					var cw: float = minf(hw * 0.52, 12.0)
					var c_poly: PackedVector2Array = PackedVector2Array([
						(cp - dir * 5.0 + nrm * cw).round(),
						(cp + dir * 6.0).round(),
						(cp - dir * 5.0 - nrm * cw).round(),
					])
					_warn_canvas.draw_polyline(c_poly, Color(GOLD_WARN, 0.65), 1.2)
			"cone":
				var orig: Vector2 = w["origin"] as Vector2
				var ang0: float = float(w["ang"])
				var arc: float = float(w["arc"])
				var rc: float = float(w["r"])
				var pts: PackedVector2Array = PackedVector2Array([orig])
				var pts_fill: PackedVector2Array = PackedVector2Array([orig])
				var pts_inner_arc: PackedVector2Array = PackedVector2Array()
				var steps_c: int = 24
				for i: int in range(steps_c + 1):
					var a_i: float = ang0 - arc + (2.0 * arc) * float(i) / float(steps_c)
					var dir_i: Vector2 = Vector2(cos(a_i), sin(a_i) * SQUASH)
					pts.append((orig + dir_i * rc).round())
					pts_fill.append((orig + dir_i * (rc * p)).round())
					pts_inner_arc.append((orig + dir_i * maxf(8.0, rc - 4.5)).round())
				pts.append(orig)
				_warn_canvas.draw_colored_polygon(pts.slice(0, pts.size() - 1), Color(WARN_DARK, fill_a * 0.72))
				_warn_canvas.draw_colored_polygon(pts_fill, Color(edge_col, fill_a))
				_warn_canvas.draw_polyline(pts, Color(edge_col, 0.92), 1.5)
				_warn_canvas.draw_polyline(pts_inner_arc, Color(GOLD_WARN, 0.68), 1.0)
				# Radial sun-architect rib lines across the cleave fan
				for rib_k: int in [-1, 0, 1]:
					var ra: float = ang0 + float(rib_k) * arc * 0.52
					var rd: Vector2 = Vector2(cos(ra), sin(ra) * SQUASH)
					_warn_canvas.draw_line((orig + rd * 12.0).round(), (orig + rd * (rc - 5.0)).round(), Color(GOLD_WARN, 0.45), 1.0)
			"armillary":
				var base_s: float = float(w["seed"])
				var elapsed: float = _clock - float(w["start"])
				for ring_idx: int in 4:
					var rad: float = 68.0 + float(ring_idx) * 56.0
					var dir_s: float = 1.0 if ring_idx % 2 == 0 else -1.0
					var spin_a: float = base_s_angle(base_s, ring_idx, elapsed, dir_s)
					_draw_gapped_armillary_ring(_warn_canvas, rad, spin_a, 0.46)


# --- Drawing: World-Lit Physical Spawns & Attacks (`_sky_body`) ----------------------------------------------------


func _draw_sky_body() -> void:
	# 1) Erupting Sun-Quartz Crystal Fault Seams (`slash_and_seams.png` Col 2)
	for cs: Dictionary in _crystal_seams:
		var a_s: Vector2 = cs["from"] as Vector2
		var b_s: Vector2 = cs["to"] as Vector2
		var grow_s: float = clampf((_clock - float(cs["born"])) / 0.14, 0.0, 1.0)
		var rem_s: float = clampf((float(cs["until"]) - _clock) / 0.18, 0.0, 1.0)
		var alpha_s: float = grow_s * rem_s
		if alpha_s <= 0.02:
			continue
		_stamp_seam_segments(_sky_body, TEX_SLASH, a_s, b_s, grow_s, Color(1.0, 1.0, 1.0, alpha_s))

	# 2) Carved Stone-and-Gold Chain Links along Tether Chains (`chain_links.png` Col 0 & 1)
	for tl: Dictionary in _tether_links:
		var a_rel: Vector2 = (tl["a"] as Vector2) - center
		var b_rel: Vector2 = (tl["b"] as Vector2) - center
		_draw_textured_chain_links(_sky_body, TEX_LINKS, a_rel, b_rel, 3.0, false, 0.72)

	# 3) Colossal Buried Anvil Gauntlet & Rune-Stone Chain (`buried_gauntlet.png` + `chain_links.png`)
	if not _gauntlet_anchor.is_empty() and bool(_gauntlet_anchor.get("active", false)):
		var g_info: Dictionary = _gauntlet_draw_state()
		var gpos: Vector2 = g_info["gpos"] as Vector2
		var wrist: Vector2 = g_info["wrist"] as Vector2
		var boss_rel: Vector2 = g_info["boss_rel"] as Vector2
		var yanking: bool = bool(g_info["yanking"])
		var col_g: int = int(g_info["col"])
		var flip_g: float = float(g_info["flip_x"])
		_draw_textured_chain_links(_sky_body, TEX_LINKS, boss_rel, wrist, 2.0 if yanking else 9.0, true, 0.84)
		_sky_body.draw_set_transform(gpos.round(), 0.0, Vector2(flip_g, 1.0))
		_sky_body.draw_texture_rect_region(TEX_GAUNTLET, Rect2(Vector2(-40.0, -54.0), Vector2(80.0, 72.0)), Rect2(float(col_g) * 80.0, 0.0, 80.0, 72.0))
		_sky_body.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4) Rising Pharaonic Sandstone Relief Crushing-Walls (`temple_walls.png` Col 0 & 1)
	for tw: Dictionary in _temple_walls:
		_draw_temple_press_pair(_sky_body, TEX_WALLS, tw, 1.0)

	# 5) Arcing Thrown Sandstone-Gold Geode Pods (`chain_links.png` Col 2 & 3)
	for gp: Dictionary in _geode_pods:
		var u_g: float = clampf(float(gp["age"]) / float(gp["dur"]), 0.0, 1.0)
		var ground_p: Vector2 = (gp["from"] as Vector2).lerp(gp["to"] as Vector2, u_g)
		var arc_z: float = sin(u_g * PI) * 68.0
		var shadow_s: float = lerpf(0.55, 1.05, 1.0 - sin(u_g * PI) * 0.5)
		_draw_ellipse_poly(_sky_body, ground_p, 11.0 * shadow_s, 6.5 * shadow_s, Color(0.08, 0.04, 0.12, 0.34), 12)
		var pod_col: int = 3 if u_g >= 0.72 else 2
		var rot_g: float = float(gp["seed"]) + u_g * 9.5
		_sky_body.draw_set_transform((ground_p + Vector2(0.0, -arc_z)).round(), rot_g, Vector2(1.12, 1.12))
		_sky_body.draw_texture_rect_region(TEX_LINKS, Rect2(Vector2(-14.0, -14.0), Vector2(28.0, 28.0)), Rect2(float(pod_col) * 28.0, 0.0, 28.0, 28.0))
		_sky_body.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 6) Rolling Textured Desert Tsunami Wave Barrels (`tsunami_rollers.png` Col 0..3)
	if not _tsunami_vis.is_empty() and bool(_tsunami_vis.get("active", false)):
		_draw_tsunami_barrels(_sky_body, TEX_ROLLERS, false)

	# 7) Sweeping Crystal Crescent Cleave Arcs (`slash_and_seams.png` Col 0 -> Col 1)
	for sa: Dictionary in _slash_arcs:
		var q_sa: float = clampf(float(sa["age"]) / float(sa["dur"]), 0.0, 1.0)
		var col_sa: int = 0 if q_sa < 0.46 else 1
		var alpha_sa: float = clampf((1.0 - q_sa) * 1.35, 0.0, 1.0)
		var sc_sa: float = float(sa["scale"]) * lerpf(0.90, 1.08, q_sa)
		var sy_sa: float = (-sc_sa if bool(sa["flip_y"]) else sc_sa) * 0.88
		_sky_body.draw_set_transform((sa["pos"] as Vector2).round(), float(sa["ang"]), Vector2(sc_sa, sy_sa))
		_sky_body.draw_texture_rect_region(TEX_SLASH, Rect2(Vector2(-44.0, -42.0), Vector2(112.0, 84.0)), Rect2(float(col_sa) * 112.0, 0.0, 112.0, 84.0), Color(1.0, 1.0, 1.0, alpha_sa))
		_sky_body.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 8) Spinning Faceted Crystal & Gold-Sandstone Shrapnel Chunks (`prism_spike_and_shards.png` Row 1)
	for sh: Dictionary in _shrapnel:
		var q_sh: float = clampf(float(sh["life"]) / float(sh["max_life"]), 0.0, 1.0)
		var alpha_sh: float = clampf((1.0 - q_sh) * 1.4, 0.0, 1.0)
		var g_pt: Vector2 = sh["pos"] as Vector2
		var z_h: float = float(sh["z"])
		if z_h > 1.0:
			_sky_body.draw_rect(Rect2((g_pt + Vector2(-2.0, 0.0)).round(), Vector2(4.0, 2.0)), Color(0.08, 0.04, 0.12, 0.28 * alpha_sh))
		var sc_sh: float = float(sh["scale"]) * lerpf(1.0, 0.78, q_sh)
		var kind_sh: int = int(sh["kind"])
		_sky_body.draw_set_transform((g_pt + Vector2(0.0, -z_h)).round(), float(sh["rot"]), Vector2(sc_sh, sc_sh))
		_sky_body.draw_texture_rect_region(TEX_SHARDS, Rect2(Vector2(-28.0, -32.0), Vector2(56.0, 64.0)), Rect2(float(kind_sh) * 56.0, 64.0, 56.0, 64.0), Color(1.0, 1.0, 1.0, alpha_sh))
	_sky_body.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Drawing: Unlit Luminous Glows, Beams & Lightning (`_sky_fx`) --------------------------------------------------


func _draw_sky_fx() -> void:
	# 1) Glow pass for Erupting Sun-Quartz Crystal Fault Seams
	for cs: Dictionary in _crystal_seams:
		var a_s: Vector2 = cs["from"] as Vector2
		var b_s: Vector2 = cs["to"] as Vector2
		var grow_s: float = clampf((_clock - float(cs["born"])) / 0.14, 0.0, 1.0)
		var rem_s: float = clampf((float(cs["until"]) - _clock) / 0.18, 0.0, 1.0)
		var pulse_s: float = 0.78 + 0.22 * sin(_clock * 26.0)
		var alpha_s: float = grow_s * rem_s * pulse_s
		if alpha_s <= 0.02:
			continue
		_stamp_seam_segments(_sky_fx, TEX_SLASH_GLOW, a_s, b_s, grow_s, Color(1.0, 1.0, 1.0, alpha_s))

	# 2) Braided Plasma Tether Filaments + Stone Link Glows
	for tl: Dictionary in _tether_links:
		var a_rel: Vector2 = (tl["a"] as Vector2) - center
		var b_rel: Vector2 = (tl["b"] as Vector2) - center
		var lcol: Color = tl.get("col", TURQ_SAFE) as Color
		var segs: int = 14
		var poly_a: PackedVector2Array = PackedVector2Array()
		var poly_b: PackedVector2Array = PackedVector2Array()
		var nrm: Vector2 = Vector2(-(b_rel.y - a_rel.y), b_rel.x - a_rel.x).normalized()
		for i: int in range(segs + 1):
			var u: float = float(i) / float(segs)
			var env: float = sin(u * PI)
			var jag1: float = sin(u * PI * 5.0 + _clock * 20.0) * 3.5 * env
			var jag2: float = cos(u * PI * 4.0 - _clock * 16.0) * 2.5 * env
			poly_a.append((a_rel.lerp(b_rel, u) + nrm * jag1).round())
			poly_b.append((a_rel.lerp(b_rel, u) - nrm * jag2).round())
		_sky_fx.draw_polyline(poly_a, Color(lcol, 0.58), 3.5)
		_sky_fx.draw_polyline(poly_b, Color(GOLD_WARN, 0.52), 2.0)
		_sky_fx.draw_polyline(poly_a, Color("ffffff", 0.90), 1.2)
		_draw_textured_chain_links(_sky_fx, TEX_LINKS_GLOW, a_rel, b_rel, 3.0, false, 0.72)

	# 3) Glow pass for Anchored Anvil Gauntlet & Rune-Stone Chain
	if not _gauntlet_anchor.is_empty() and bool(_gauntlet_anchor.get("active", false)):
		var g_info: Dictionary = _gauntlet_draw_state()
		var gpos: Vector2 = g_info["gpos"] as Vector2
		var wrist: Vector2 = g_info["wrist"] as Vector2
		var boss_rel: Vector2 = g_info["boss_rel"] as Vector2
		var yanking: bool = bool(g_info["yanking"])
		var col_g: int = int(g_info["col"])
		var flip_g: float = float(g_info["flip_x"])
		var sag_amt: float = 2.0 if yanking else 9.0
		var c_pts: PackedVector2Array = PackedVector2Array()
		for ci: int in 11:
			var cu: float = float(ci) / 10.0
			var sag: float = sin(cu * PI) * sag_amt
			c_pts.append((boss_rel.lerp(wrist, cu) + Vector2(0.0, sag)).round())
		_sky_fx.draw_polyline(c_pts, Color(TURQ_SAFE, 0.65), 3.0)
		_sky_fx.draw_polyline(c_pts, Color(GOLD_WARN, 0.90), 1.2)
		_draw_textured_chain_links(_sky_fx, TEX_LINKS_GLOW, boss_rel, wrist, sag_amt, true, 0.84)
		_sky_fx.draw_set_transform(gpos.round(), 0.0, Vector2(flip_g, 1.0))
		_sky_fx.draw_texture_rect_region(TEX_GAUNTLET_GLOW, Rect2(Vector2(-40.0, -54.0), Vector2(80.0, 72.0)), Rect2(float(col_g) * 80.0, 0.0, 80.0, 72.0))
		_sky_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 4) Glow pass for Pharaonic Sandstone Relief Crushing-Walls
	for tw: Dictionary in _temple_walls:
		_draw_temple_press_pair(_sky_fx, TEX_WALLS_GLOW, tw, 0.92)

	# 5) Glow pass + Ember Trail for Arcing Geode Pods
	for gp: Dictionary in _geode_pods:
		var u_g: float = clampf(float(gp["age"]) / float(gp["dur"]), 0.0, 1.0)
		var ground_p: Vector2 = (gp["from"] as Vector2).lerp(gp["to"] as Vector2, u_g)
		var arc_z: float = sin(u_g * PI) * 68.0
		var pod_col: int = 3 if u_g >= 0.72 else 2
		var rot_g: float = float(gp["seed"]) + u_g * 9.5
		for tr_i: int in 4:
			var u_prev: float = maxf(0.0, u_g - float(tr_i + 1) * 0.045)
			var tp: Vector2 = (gp["from"] as Vector2).lerp(gp["to"] as Vector2, u_prev) + Vector2(0.0, -sin(u_prev * PI) * 68.0)
			_sky_fx.draw_rect(Rect2(tp.round(), Vector2(2.0, 2.0)), Color(TURQ_SAFE if tr_i % 2 == 0 else GOLD_WARN, (1.0 - float(tr_i) * 0.22) * 0.8))
		_sky_fx.draw_set_transform((ground_p + Vector2(0.0, -arc_z)).round(), rot_g, Vector2(1.12, 1.12))
		_sky_fx.draw_texture_rect_region(TEX_LINKS_GLOW, Rect2(Vector2(-14.0, -14.0), Vector2(28.0, 28.0)), Rect2(float(pod_col) * 28.0, 0.0, 28.0, 28.0))
		_sky_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 6) Searing Solar Chest Beam + Spinning Astrolabe Muzzle Lens + 3-Way Prism Split Rays (`SOLAR_BEAM`)
	if not _solar_beam.is_empty() and bool(_solar_beam.get("active", false)):
		var b_orig: Vector2 = _solar_beam["origin"] as Vector2
		var b_ang: float = float(_solar_beam["angle"])
		var b_len: float = float(_solar_beam["length"])
		var b_end: Vector2 = b_orig + Vector2.from_angle(b_ang) * b_len

		# Rotating Solar Astrolabe Muzzle Mandala (`slash_and_seams` Col 3) at Aurelith's core!
		_sky_fx.draw_set_transform(b_orig.round(), _clock * 2.8, Vector2(0.64, 0.64))
		_sky_fx.draw_texture_rect_region(TEX_SLASH, Rect2(Vector2(-56.0, -42.0), Vector2(112.0, 84.0)), Rect2(336.0, 0.0, 112.0, 84.0), Color(1.0, 1.0, 1.0, 0.92))
		_sky_fx.draw_texture_rect_region(TEX_SLASH_GLOW, Rect2(Vector2(-56.0, -42.0), Vector2(112.0, 84.0)), Rect2(336.0, 0.0, 112.0, 84.0))
		_sky_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		_draw_prism_laser(_sky_fx, b_orig, b_end, 14.0, VIOLET_ARC, GOLD_WARN, _clock)
		for sp: Dictionary in _solar_beam.get("splits", []) as Array:
			var s_orig: Vector2 = (sp["from"] as Vector2) - center
			var s_end: Vector2 = (sp["to"] as Vector2) - center
			var s_col: Color = sp.get("col", TURQ_SAFE) as Color
			_draw_prism_laser(_sky_fx, s_orig, s_end, 8.0, s_col, Color.WHITE, _clock * 1.3)
			# Refracting prism star-flare on the splitting QuartzGolem!
			_sky_fx.draw_set_transform(s_orig.round(), -_clock * 3.4, Vector2(0.42, 0.42))
			_sky_fx.draw_texture_rect_region(TEX_SLASH_GLOW, Rect2(Vector2(-56.0, -42.0), Vector2(112.0, 84.0)), Rect2(336.0, 0.0, 112.0, 84.0))
			_sky_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 7) Glow pass for Rolling Desert Tsunami Wave Barrels
	if not _tsunami_vis.is_empty() and bool(_tsunami_vis.get("active", false)):
		_draw_tsunami_barrels(_sky_fx, TEX_ROLLERS_GLOW, true)

	# 8) Glow pass for Sweeping Crystal Crescent Cleave Arcs
	for sa: Dictionary in _slash_arcs:
		var q_sa: float = clampf(float(sa["age"]) / float(sa["dur"]), 0.0, 1.0)
		var col_sa: int = 0 if q_sa < 0.46 else 1
		var alpha_sa: float = clampf((1.0 - q_sa) * 1.25, 0.0, 1.0)
		var sc_sa: float = float(sa["scale"]) * lerpf(0.90, 1.08, q_sa)
		var sy_sa: float = (-sc_sa if bool(sa["flip_y"]) else sc_sa) * 0.88
		_sky_fx.draw_set_transform((sa["pos"] as Vector2).round(), float(sa["ang"]), Vector2(sc_sa, sy_sa))
		_sky_fx.draw_texture_rect_region(TEX_SLASH_GLOW, Rect2(Vector2(-44.0, -42.0), Vector2(112.0, 84.0)), Rect2(float(col_sa) * 112.0, 0.0, 112.0, 84.0), Color(1.0, 1.0, 1.0, alpha_sa))
		_sky_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 9) Forked Dry Arcane Sky-Lightning Bolts + Ground Star-Flash
	for sb: Dictionary in _sky_bolts:
		var bq: float = 1.0 - clampf(float(sb["age"]) / maxf(float(sb["dur"]), 0.05), 0.0, 1.0)
		var bat: Vector2 = sb["at"] as Vector2
		var bcol: Color = sb["col"] as Color
		var bseed: float = float(sb.get("seed", 0.0))
		var bolt_pts: PackedVector2Array = PackedVector2Array()
		for bi: int in 11:
			var bu: float = float(bi) / 10.0
			var bx: float = bat.x + (sin(float(bi) * 3.9 + bseed + _clock * 28.0) * 13.0 * (1.0 - bu * 0.75) if bi < 10 else 0.0)
			var by: float = lerpf(bat.y - 210.0, bat.y, bu)
			bolt_pts.append(Vector2(bx, by).round())
		_sky_fx.draw_polyline(bolt_pts, Color(VIOLET_ARC, bq * 0.45), 8.0)
		_sky_fx.draw_polyline(bolt_pts, Color(bcol, bq * 0.85), 4.0)
		_sky_fx.draw_polyline(bolt_pts, Color("ffffff", bq), 1.8)
		# Two forked secondary lightning branches
		for br_i: int in [3, 6]:
			var root_p: Vector2 = bolt_pts[br_i]
			var sgn_b: float = 1.0 if br_i == 3 else -1.0
			var branch: PackedVector2Array = PackedVector2Array([
				root_p,
				(root_p + Vector2(sgn_b * 14.0, 18.0)).round(),
				(root_p + Vector2(sgn_b * 26.0, 38.0)).round(),
			])
			_sky_fx.draw_polyline(branch, Color(bcol, bq * 0.72), 2.2)
			_sky_fx.draw_polyline(branch, Color.WHITE, 1.0)
		_draw_ellipse_poly(_sky_fx, bat, 18.0 * bq, 11.0 * bq, Color(bcol, 0.55 * bq), 14)
		_draw_ellipse_poly(_sky_fx, bat, 8.0 * bq, 5.0 * bq, Color(Color.WHITE, 0.9 * bq), 10)

	# 10) Glow pass for Spinning Shrapnel Chunks + Crisp Impact Sparks
	for sh: Dictionary in _shrapnel:
		var q_sh: float = clampf(float(sh["life"]) / float(sh["max_life"]), 0.0, 1.0)
		var alpha_sh: float = clampf(1.0 - q_sh, 0.0, 1.0)
		var g_pt: Vector2 = sh["pos"] as Vector2
		var sc_sh: float = float(sh["scale"]) * lerpf(1.0, 0.78, q_sh)
		var kind_sh: int = int(sh["kind"])
		_sky_fx.draw_set_transform((g_pt + Vector2(0.0, -float(sh["z"]))).round(), float(sh["rot"]), Vector2(sc_sh, sc_sh))
		_sky_fx.draw_texture_rect_region(TEX_SHARDS_GLOW, Rect2(Vector2(-28.0, -32.0), Vector2(56.0, 64.0)), Rect2(float(kind_sh) * 56.0, 64.0, 56.0, 64.0), Color(1.0, 1.0, 1.0, alpha_sh))
	_sky_fx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for m: Dictionary in _bursts:
		var ma: float = clampf(float(m["life"]) / maxf(float(m["max_life"]), 0.05), 0.0, 1.0)
		var mp: Vector2 = (m["pos"] as Vector2).round()
		var msz: float = float(m["sz"])
		_sky_fx.draw_rect(Rect2(mp, Vector2.ONE * msz), Color(m["col"] as Color, ma))


# --- Textured Rendering Helpers ------------------------------------------------------------------------------------


func _gauntlet_draw_state() -> Dictionary:
	var gpos: Vector2 = _gauntlet_anchor["pos"] as Vector2
	var yanking: bool = bool(_gauntlet_anchor.get("yanking", false))
	if yanking:
		var yq: float = clampf((_clock - float(_gauntlet_anchor["yank_start"])) / float(_gauntlet_anchor["yank_dur"]), 0.0, 1.0)
		gpos = gpos.lerp(_gauntlet_anchor["yank_to"] as Vector2, yq)
	var boss_rel: Vector2 = (boss.global_position + Vector2(22.0, -54.0) - center) if is_instance_valid(boss) else Vector2.ZERO
	var col_g: int = 1 if yanking else 0
	var flip_x: float = 1.0
	var wrist_off: Vector2 = Vector2(0.5, -41.0)
	if yanking:
		if boss_rel.x > gpos.x + 6.0:
			flip_x = -1.0
			wrist_off = Vector2(13.0, -42.0)
		else:
			wrist_off = Vector2(-13.0, -42.0)
	return {
		"gpos": gpos,
		"wrist": gpos + wrist_off,
		"boss_rel": boss_rel,
		"yanking": yanking,
		"col": col_g,
		"flip_x": flip_x,
	}


func _draw_textured_chain_links(canvas: CanvasItem, tex: Texture2D, a: Vector2, b: Vector2, sag_px: float, skip_ends: bool, link_scale: float) -> void:
	var dist: float = a.distance_to(b)
	if dist < 18.0:
		return
	var count: int = clampi(int(dist / 16.0), 2, 16)
	var start_i: int = 1 if skip_ends else 1
	var end_i: int = count - 1
	for i: int in range(start_i, end_i + 1):
		var u: float = float(i) / float(count)
		var u_prev: float = maxf(0.0, u - 0.05)
		var u_next: float = minf(1.0, u + 0.05)
		var p_cur: Vector2 = a.lerp(b, u) + Vector2(0.0, sin(u * PI) * sag_px)
		var p_prev: Vector2 = a.lerp(b, u_prev) + Vector2(0.0, sin(u_prev * PI) * sag_px)
		var p_next: Vector2 = a.lerp(b, u_next) + Vector2(0.0, sin(u_next * PI) * sag_px)
		var ang: float = (p_next - p_prev).angle()
		var col_l: int = i % 2
		canvas.draw_set_transform(p_cur.round(), ang, Vector2(link_scale, link_scale))
		canvas.draw_texture_rect_region(tex, Rect2(Vector2(-14.0, -14.0), Vector2(28.0, 28.0)), Rect2(float(col_l) * 28.0, 0.0, 28.0, 28.0))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _stamp_seam_segments(canvas: CanvasItem, tex: Texture2D, a: Vector2, b: Vector2, grow_h: float, mod_col: Color) -> void:
	var ab: Vector2 = b - a
	var dist: float = ab.length()
	if dist < 8.0:
		return
	var dir: Vector2 = ab / dist
	var dir_pos: Vector2 = dir if dir.x >= 0.0 else -dir
	var seg_len: float = 68.0
	var count: int = maxi(1, int(ceilf(dist / seg_len)))
	var seg_span: float = dist / float(count)
	var segs: Array[Vector2] = []
	for i: int in count:
		var u: float = (float(i) + 0.5) / float(count)
		segs.append(a.lerp(b, u))
	segs.sort_custom(func(pa: Vector2, pb: Vector2) -> bool: return pa.y < pb.y)
	for si: int in segs.size():
		var mid: Vector2 = segs[si]
		# Preserve upright 3/4 crystal teeth (`y_vec = (0, grow_h)`) while shearing fissure base along `dir_pos`!
		var x_vec: Vector2 = dir_pos * clampf(seg_span / 82.0, 0.45, 1.15)
		if absf(x_vec.x) < 0.38:
			var sgn_x: float = -1.0 if (si % 2 == 1) else 1.0
			x_vec = Vector2(0.44 * sgn_x, dir_pos.y * clampf(seg_span / 82.0, 0.45, 1.0))
		var y_vec: Vector2 = Vector2(0.0, grow_h)
		canvas.draw_set_transform_matrix(Transform2D(x_vec, y_vec, mid.round()))
		canvas.draw_texture_rect_region(tex, Rect2(Vector2(-56.0, -48.0), Vector2(112.0, 84.0)), Rect2(224.0, 0.0, 112.0, 84.0), mod_col)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_temple_press_pair(canvas: CanvasItem, tex: Texture2D, tw: Dictionary, base_alpha: float) -> void:
	var pos_w: Vector2 = tw["pos"] as Vector2
	var axis: Vector2 = tw["axis"] as Vector2
	var tang: Vector2 = Vector2(-axis.y, axis.x)
	var wall_len: float = float(tw["len"])
	var gap0: float = float(tw["gap"])
	var start_t: float = float(tw["start"])
	var crush_at: float = float(tw["crush_at"])
	var cur_gap: float = gap0
	var alpha_w: float = base_alpha
	var rise_h: float = clampf((_clock - start_t) / 0.22, 0.18, 1.0)
	if _clock < crush_at:
		var prep_q: float = clampf((_clock - start_t) / maxf(crush_at - start_t, 0.05), 0.0, 1.0)
		cur_gap = lerpf(gap0 + 12.0, gap0 * 0.88, smoothstep(0.0, 0.4, prep_q))
		if prep_q > 0.78:
			cur_gap = lerpf(gap0 * 0.88, 6.0, (prep_q - 0.78) / 0.22)
	else:
		cur_gap = 4.0
		var fade_q: float = clampf((_clock - crush_at) / 0.44, 0.0, 1.0)
		alpha_w = base_alpha * (1.0 - fade_q)
		rise_h = lerpf(1.0, 0.35, fade_q)
	if alpha_w <= 0.02:
		return

	var wall_entries: Array[Dictionary] = [
		{"wc": pos_w - axis * cur_gap, "col": 0},
		{"wc": pos_w + axis * cur_gap, "col": 1},
	]
	wall_entries.sort_custom(func(a_e: Dictionary, b_e: Dictionary) -> bool:
		return (a_e["wc"] as Vector2).y < (b_e["wc"] as Vector2).y
	)
	var tang_pos: Vector2 = tang if tang.x >= 0.0 else -tang
	for entry: Dictionary in wall_entries:
		var wc: Vector2 = entry["wc"] as Vector2
		var col_w: int = int(entry["col"])
		var src_w: Rect2 = Rect2(float(col_w) * 120.0, 0.0, 120.0, 68.0)
		if tang_pos.x >= 0.46:
			var x_vec: Vector2 = tang_pos * (wall_len / 106.0)
			var y_vec: Vector2 = Vector2(0.0, rise_h)
			canvas.draw_set_transform_matrix(Transform2D(x_vec, y_vec, wc.round()))
			canvas.draw_texture_rect_region(tex, Rect2(Vector2(-60.0, -56.0), Vector2(120.0, 68.0)), src_w, Color(1.0, 1.0, 1.0, alpha_w))
		else:
			# Stepped 3-bastion colonnade when walls run North-South so stone facade stays thick & upright!
			var bastions: Array[Vector2] = [
				wc - tang * (wall_len * 0.34),
				wc,
				wc + tang * (wall_len * 0.34),
			]
			bastions.sort_custom(func(pa: Vector2, pb: Vector2) -> bool: return pa.y < pb.y)
			for bp: Vector2 in bastions:
				canvas.draw_set_transform(bp.round(), 0.0, Vector2(0.56, rise_h))
				canvas.draw_texture_rect_region(tex, Rect2(Vector2(-60.0, -56.0), Vector2(120.0, 68.0)), src_w, Color(1.0, 1.0, 1.0, alpha_w))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tsunami_barrels(canvas: CanvasItem, tex: Texture2D, is_glow: bool) -> void:
	var wd: Vector2 = _tsunami_vis["dir"] as Vector2
	var perp_w: Vector2 = Vector2(-wd.y, wd.x)
	var prog: float = float(_tsunami_vis["progress"])
	var span_r: float = maxf(arena_radii.x, arena_radii.y)
	var crest_c: Vector2 = wd * (prog * span_r)
	var seg_count: int = 16
	var items: Array[Dictionary] = []
	var phase_step: int = int(floorf(_clock * 5.0))
	for rank: int in 2:
		# Rank 0 = trailing churning sand-swell bank (-24 px); Rank 1 = breaking front crest (+5 px)
		var count_r: int = seg_count - (2 if rank == 0 else 0)
		for si: int in range(count_r + 1):
			var u: float = lerpf(-1.0, 1.0, (float(si) + (0.5 if rank == 0 else 0.0)) / float(maxi(count_r, 1)))
			var depth_off: float = (-24.0 + sin(float(si) * 2.1 + _clock * 9.0) * 5.0) if rank == 0 else (5.0 + sin(float(si) * 1.7 + _clock * 13.0) * 5.5)
			var sample_p: Vector2 = crest_c + wd * depth_off + perp_w * (u * span_r)
			var ell_q: float = Vector2(sample_p.x / arena_radii.x, sample_p.y / arena_radii.y).length()
			if ell_q > 1.02:
				continue
			var edge_fade: float = clampf((1.02 - ell_q) * 3.6, 0.0, 1.0)
			var bob_y: float = sin(float(si) * 1.3 + float(rank) * 2.0 + _clock * 11.0) * 3.0
			var pt: Vector2 = sample_p + Vector2(0.0, bob_y)
			# Rank 0 uses pure sand/masonry billows (0 or 2); Rank 1 mixes sand billows with sparse crystal crags (1 or 3)!
			var col_pick: int = (0 if (si + phase_step) % 2 == 0 else 2)
			if rank == 1 and posmod(si * 5 + phase_step, 5) in [1, 3]:
				col_pick = 1 if (si % 2 == 0) else 3
			var lean: float = clampf(wd.x * 0.16, -0.18, 0.18) + sin(float(si) * 2.3) * 0.06
			items.append({
				"pt": pt,
				"fade": edge_fade,
				"col": col_pick,
				"flip": ((si + rank) % 2 == 1),
				"rank": rank,
				"lean": lean,
				"scale": (0.94 if rank == 0 else 0.84) + 0.30 * edge_fade,
			})
	items.sort_custom(func(ia: Dictionary, ib: Dictionary) -> bool:
		var ya: float = (ia["pt"] as Vector2).y + float(ia["rank"]) * 1.5
		var yb: float = (ib["pt"] as Vector2).y + float(ib["rank"]) * 1.5
		return ya < yb
	)
	for it: Dictionary in items:
		var p_it: Vector2 = (it["pt"] as Vector2).round()
		var fade_it: float = float(it["fade"])
		var sc_it: float = float(it["scale"])
		var sx_it: float = -sc_it if bool(it["flip"]) else sc_it
		var col_it: int = int(it["col"])
		var rank_it: int = int(it["rank"])
		var alpha_it: float = clampf(fade_it * (0.85 if is_glow else (0.90 if rank_it == 0 else 1.0)), 0.0, 1.0)
		var mod_it: Color = Color(1.0, 1.0, 1.0, alpha_it) if (is_glow or rank_it == 1) else Color(0.90, 0.82, 0.74, alpha_it)
		canvas.draw_set_transform(p_it, float(it["lean"]), Vector2(sx_it, sc_it))
		canvas.draw_texture_rect_region(tex, Rect2(Vector2(-36.0, -48.0), Vector2(72.0, 60.0)), Rect2(float(col_it) * 72.0, 0.0, 72.0, 60.0), mod_it)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Wind-whipped desert spindrift & flying quartz grains surging ahead of the wave crest!
	if not is_glow:
		for sp_i: int in 22:
			var u_sp: float = lerpf(-0.92, 0.92, fmod(float(sp_i) * 0.173 + _clock * 0.12, 1.0))
			var adv: float = fmod(_clock * 96.0 + float(sp_i) * 19.0, 38.0)
			var sp_pt: Vector2 = crest_c + wd * (14.0 + adv) + perp_w * (u_sp * span_r) + Vector2(0.0, -6.0 - float(sp_i % 4) * 5.0)
			var eq: float = Vector2(sp_pt.x / arena_radii.x, sp_pt.y / arena_radii.y).length()
			if eq <= 0.98:
				var sa_f: float = (1.0 - adv / 38.0) * 0.75
				var scol: Color = TURQ_SAFE if sp_i % 6 == 0 else AurelithRig.SD_5
				canvas.draw_line(sp_pt.round(), (sp_pt + wd * 7.0).round(), Color(scol, sa_f), 1.5)


static func _draw_prism_laser(canvas: CanvasItem, a: Vector2, b: Vector2, width: float, outer: Color, mid: Color, t_anim: float) -> void:
	var ab: Vector2 = b - a
	var dist: float = ab.length()
	if dist <= 2.0:
		return
	var dir: Vector2 = ab / dist
	var nrm: Vector2 = Vector2(-dir.y, dir.x)
	canvas.draw_line(a, b, Color(outer, 0.38), width * 1.75)
	canvas.draw_line(a, b, Color(mid, 0.84), width * 0.90)
	# Braided crystalline plasma helix along the beam
	var steps: int = clampi(int(dist / 14.0), 4, 24)
	var h1: PackedVector2Array = PackedVector2Array()
	var h2: PackedVector2Array = PackedVector2Array()
	for i: int in range(steps + 1):
		var u: float = float(i) / float(steps)
		var wave: float = sin(u * dist * 0.08 - t_anim * 24.0) * (width * 0.48)
		var base_p: Vector2 = a.lerp(b, u)
		h1.append((base_p + nrm * wave).round())
		h2.append((base_p - nrm * wave).round())
	canvas.draw_polyline(h1, Color(TURQ_SAFE, 0.72), 1.6)
	canvas.draw_polyline(h2, Color(GOLD_WARN, 0.72), 1.6)
	canvas.draw_line(a, b, Color.WHITE, maxf(width * 0.36, 2.2))
	# Faceted star-burst flare at beam impact tip!
	canvas.draw_circle(b, width * 0.85, Color(outer, 0.48))
	canvas.draw_circle(b, width * 0.55, Color(mid, 0.85))
	canvas.draw_circle(b, width * 0.30, Color.WHITE)
	for sp_i: int in 4:
		var sa: float = t_anim * 5.0 + float(sp_i) * PI * 0.5
		var d_sp: Vector2 = Vector2.from_angle(sa) * (width * 1.15)
		canvas.draw_line((b - d_sp).round(), (b + d_sp).round(), Color.WHITE, 1.4)


static func _draw_ellipse_poly(canvas: CanvasItem, pos: Vector2, rx: float, ry: float, col: Color, steps: int) -> void:
	if rx <= 1.0 or ry <= 1.0:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in steps:
		var a: float = TAU * float(i) / float(steps)
		pts.append((pos + Vector2(cos(a) * rx, sin(a) * ry)).round())
	canvas.draw_colored_polygon(pts, col)


static func _draw_ellipse_ring(canvas: CanvasItem, pos: Vector2, rx: float, ry: float, col: Color, steps: int) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(steps + 1):
		var a: float = TAU * float(i) / float(steps)
		pts.append((pos + Vector2(cos(a) * rx, sin(a) * ry)).round())
	canvas.draw_polyline(pts, col, 1.5)


static func _draw_ring_band(canvas: CanvasItem, pos: Vector2, r_in: float, r_out: float, fill_col: Color, rim_col: Color) -> void:
	var steps: int = 36
	for i: int in steps:
		var a0: float = TAU * float(i) / float(steps)
		var a1: float = TAU * float(i + 1) / float(steps)
		var d0: Vector2 = Vector2(cos(a0), sin(a0) * SQUASH)
		var d1: Vector2 = Vector2(cos(a1), sin(a1) * SQUASH)
		var quad: PackedVector2Array = PackedVector2Array([
			pos + d0 * r_in, pos + d0 * r_out, pos + d1 * r_out, pos + d1 * r_in
		])
		canvas.draw_colored_polygon(quad, fill_col)
	_draw_ellipse_ring(canvas, pos, r_in, r_in * SQUASH, rim_col, steps)
	_draw_ellipse_ring(canvas, pos, r_out, r_out * SQUASH, rim_col, steps)


static func _draw_gapped_armillary_ring(canvas: CanvasItem, rad: float, spin_a: float, half_gap: float) -> void:
	# Two 180-deg-opposed safe gaps of width `2 * half_gap` rad, framed like engraved golden astrolabe bands!
	for arc_i: int in 2:
		var start_a: float = spin_a + float(arc_i) * PI + half_gap
		var end_a: float = spin_a + float(arc_i + 1) * PI - half_gap
		var pts_mid: PackedVector2Array = PackedVector2Array()
		var pts_in: PackedVector2Array = PackedVector2Array()
		var pts_out: PackedVector2Array = PackedVector2Array()
		var r_in: float = rad - 7.5
		var r_out: float = rad + 7.5
		for s: int in 21:
			var a: float = lerpf(start_a, end_a, float(s) / 20.0)
			var dir_a: Vector2 = Vector2(cos(a), sin(a) * SQUASH)
			pts_mid.append((dir_a * rad).round())
			pts_in.append((dir_a * r_in).round())
			pts_out.append((dir_a * r_out).round())
		canvas.draw_polyline(pts_mid, Color(WARN_MID, 0.36), 13.0)
		canvas.draw_polyline(pts_in, Color(GOLD_WARN, 0.88), 1.8)
		canvas.draw_polyline(pts_out, Color(GOLD_WARN, 0.88), 1.8)
		canvas.draw_polyline(pts_mid, Color(Color.WHITE, 0.55), 1.4)
		# Engraved astrolabe degree notches along the ring + turquoise safe-gate endcaps!
		for t_i: int in 9:
			var ta: float = lerpf(start_a, end_a, float(t_i) / 8.0)
			var td: Vector2 = Vector2(cos(ta), sin(ta) * SQUASH)
			canvas.draw_line((td * r_in).round(), (td * r_out).round(), Color(GOLD_WARN, 0.72), 1.5)
		for gate_a: float in [start_a, end_a]:
			var gd: Vector2 = Vector2(cos(gate_a), sin(gate_a) * SQUASH)
			canvas.draw_line((gd * (r_in - 2.0)).round(), (gd * (r_out + 2.0)).round(), Color(TURQ_SAFE, 0.95), 2.5)


static func is_in_armillary_danger(world_pos: Vector2, basin_center: Vector2, base_seed: float, elapsed: float) -> bool:
	var rel: Vector2 = world_pos - basin_center
	var ell_v: Vector2 = Vector2(rel.x, rel.y / SQUASH)
	var dist: float = ell_v.length()
	var ang: float = atan2(ell_v.y, ell_v.x)
	for ring_idx: int in 4:
		var rad: float = 68.0 + float(ring_idx) * 56.0
		if absf(dist - rad) <= 10.5:
			var dir_s: float = 1.0 if ring_idx % 2 == 0 else -1.0
			var spin_a: float = base_s_angle(base_seed, ring_idx, elapsed, dir_s)
			var da0: float = absf(wrapf(ang - spin_a, -PI, PI))
			var da1: float = absf(wrapf(ang - (spin_a + PI), -PI, PI))
			if da0 > 0.46 and da1 > 0.46:
				return true
	return false


static func base_s_angle(base_seed: float, ring_idx: int, elapsed: float, dir_s: float) -> float:
	return base_seed + float(ring_idx) * 1.15 + elapsed * (0.85 - 0.10 * float(ring_idx)) * dir_s


# --- Inner Entities: Varied Monolith Pillar & Astrolabe Resonance Core ---------------------------------------------


class PillarNode:
	extends StaticBody2D
	var pillar_id: int = 0
	var field: AurelithField
	var born: float = 0.0
	var until: float = 0.0
	var beam_heat: float = 0.0
	var _age: float = 0.0
	var _holder: Node2D
	var _molten_spr: Sprite2D
	var _molten_glow: Sprite2D

	func _ready() -> void:
		collision_layer = 1
		collision_mask = 0
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_to_group("day_canopies")
		var shape_node: CollisionShape2D = CollisionShape2D.new()
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 13.0
		shape_node.shape = circle
		shape_node.position = Vector2(0.0, -4.0)
		add_child(shape_node)

	func setup_visuals(variant: int) -> void:
		var v: int = clampi(variant, 0, 3)
		var shadow: Node2D = Node2D.new()
		shadow.z_index = -1
		shadow.draw.connect(func() -> void:
			AurelithField._draw_ellipse_poly(shadow, Vector2(6.0, 2.0), 23.0, 14.0, Color(0.05, 0.03, 0.09, 0.34), 16)
		)
		add_child(shadow)

		_holder = Node2D.new()
		_holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_holder)

		var add_mat: CanvasItemMaterial = CanvasItemMaterial.new()
		add_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

		# Row 0: Intact / Sun-Charged monolith variant
		var spr: Sprite2D = Sprite2D.new()
		spr.texture = AurelithField.TEX_PILLARS
		spr.region_enabled = true
		spr.region_rect = Rect2(float(v) * 64.0, 0.0, 64.0, 84.0)
		spr.centered = false
		spr.offset = Vector2(-32.0, -72.0)
		_holder.add_child(spr)

		var glow: Sprite2D = Sprite2D.new()
		glow.texture = AurelithField.TEX_PILLARS_GLOW
		glow.region_enabled = true
		glow.region_rect = spr.region_rect
		glow.centered = false
		glow.offset = spr.offset
		glow.material = add_mat
		spr.add_child(glow)

		# Row 1: Superheated / Molten-Cracked state crossfaded on top as `beam_heat` rises or expiration nears!
		_molten_spr = Sprite2D.new()
		_molten_spr.texture = AurelithField.TEX_PILLARS
		_molten_spr.region_enabled = true
		_molten_spr.region_rect = Rect2(float(v) * 64.0, 84.0, 64.0, 84.0)
		_molten_spr.centered = false
		_molten_spr.offset = spr.offset
		_molten_spr.modulate.a = 0.0
		_holder.add_child(_molten_spr)

		_molten_glow = Sprite2D.new()
		_molten_glow.texture = AurelithField.TEX_PILLARS_GLOW
		_molten_glow.region_enabled = true
		_molten_glow.region_rect = _molten_spr.region_rect
		_molten_glow.centered = false
		_molten_glow.offset = spr.offset
		_molten_glow.material = add_mat
		_molten_glow.modulate.a = 0.0
		_holder.add_child(_molten_glow)

	func _process(delta: float) -> void:
		_age += delta
		if _holder == null:
			return
		var rise_q: float = clampf(_age / 0.22, 0.0, 1.0)
		var ease_r: float = 1.0 - pow(1.0 - rise_q, 3.0)
		var tremor: float = 0.0
		if rise_q < 1.0 or beam_heat > 0.45:
			tremor = 1.0 if int(floorf(_age * 34.0)) % 2 == 0 else -1.0
		_holder.position = Vector2(tremor, 0.0)
		_holder.scale = Vector2(lerpf(0.86, 1.0, ease_r), lerpf(0.24, 1.0, ease_r))

		var expire_heat: float = 0.0
		if field != null:
			expire_heat = clampf(1.0 - (until - field.now()) / 1.4, 0.0, 1.0)
		var molten_q: float = maxf(clampf(beam_heat / 0.58, 0.0, 1.0), expire_heat)
		_molten_spr.modulate.a = molten_q
		_molten_glow.modulate.a = molten_q * (0.78 + 0.22 * sin(_age * 20.0))

	func day_canopy() -> Vector4:
		return Vector4(global_position.x + 8.0, global_position.y + 3.0, 32.0, 22.0)


class ResonanceCoreNode:
	extends Node2D
	var core_id: int = 0
	var field: AurelithField
	var life: float = 0.0
	var max_life: float = 5.8
	var launched: bool = false
	var source_peer: int = 1
	var _travel_dir: Vector2 = Vector2.UP
	var _hurtbox: ResonanceCoreHurtbox
	var _ring_layer: Node2D
	var _spr: Sprite2D
	var _glow: Sprite2D

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		_ring_layer = Node2D.new()
		_ring_layer.z_index = -1
		_ring_layer.material = Unlit.material()
		_ring_layer.draw.connect(_draw_ring_and_tail)
		add_child(_ring_layer)

		_spr = Sprite2D.new()
		_spr.texture = AurelithField.TEX_CORE
		_spr.hframes = 4
		_spr.vframes = 2
		_spr.position = Vector2(0.0, -14.0)
		add_child(_spr)

		_glow = Sprite2D.new()
		_glow.texture = AurelithField.TEX_CORE_GLOW
		_glow.hframes = 4
		_glow.vframes = 2
		var add_mat: CanvasItemMaterial = CanvasItemMaterial.new()
		add_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = add_mat
		_spr.add_child(_glow)

		_hurtbox = ResonanceCoreHurtbox.new()
		_hurtbox.core_node = self
		_hurtbox.collision_layer = 1 << 4 ## Layer 5: hit equally by ALL player weapons & ALL wand spells!
		_hurtbox.collision_mask = 0
		var cs: CollisionShape2D = CollisionShape2D.new()
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = 16.0
		cs.shape = circle
		cs.position = Vector2(0.0, -12.0)
		_hurtbox.add_child(cs)
		add_child(_hurtbox)

	func set_travel_dir(d: Vector2) -> void:
		if d.length_squared() > 0.01:
			_travel_dir = d

	func disable_hurtbox() -> void:
		if _hurtbox != null:
			_hurtbox.set_deferred("collision_layer", 0)

	func _process(_delta: float) -> void:
		var bob: float = -14.0 if launched else (roundf(sin(life * 5.8) * 3.0) - 15.0)
		_spr.position = Vector2(0.0, bob)
		var f_idx: int = (4 + posmod(int(floorf(life * 16.0)), 4)) if launched else posmod(int(floorf(life * 8.5)), 4)
		_spr.frame = f_idx
		_glow.frame = f_idx
		_glow.modulate.a = 0.95 if launched else (0.74 + 0.26 * sin(life * 12.0))
		_ring_layer.queue_redraw()

	func _draw_ring_and_tail() -> void:
		if not launched:
			var pulse: float = 0.70 + 0.30 * sin(life * 11.0)
			AurelithField._draw_ellipse_poly(_ring_layer, Vector2(0.0, 1.0), 11.0, 6.5, Color(0.06, 0.03, 0.11, 0.34), 14)
			AurelithField._draw_ellipse_ring(_ring_layer, Vector2.ZERO, 16.0, 11.5, Color("78f4e6", 0.72 * pulse), 24)
			AurelithField._draw_ellipse_ring(_ring_layer, Vector2.ZERO, 12.5, 9.0, Color("ffd86b", 0.55 * pulse), 20)
			for i: int in 4:
				var a: float = life * 1.8 + float(i) * PI * 0.5
				var p: Vector2 = Vector2(cos(a) * 16.0, sin(a) * 11.5).round()
				_ring_layer.draw_rect(Rect2(p - Vector2.ONE, Vector2(2.0, 2.0)), Color("ffd86b", 0.90))
		else:
			# Blazing solar-comet tail trailing behind the reflected core!
			var back: Vector2 = -_travel_dir
			var perp: Vector2 = Vector2(-back.y, back.x)
			for k: int in 5:
				var u: float = float(k + 1) / 5.0
				var tp: Vector2 = Vector2(0.0, -14.0) + back * (u * 26.0) + perp * sin(life * 28.0 + float(k)) * 2.5
				var sz: float = 4.0 - u * 2.2
				_ring_layer.draw_rect(Rect2(tp.round(), Vector2(sz, sz)), Color("ffd86b" if k % 2 == 0 else "78f4e6", (1.0 - u) * 0.88))


class ResonanceCoreHurtbox:
	extends HurtboxComponent
	var core_node: ResonanceCoreNode

	func take_hit(_damage: float, _from: Vector2, _knockback: float, source: int = 0) -> void:
		if core_node != null and not core_node.launched and core_node.field != null:
			core_node.field._on_core_hurtbox_struck(core_node.core_id, source if source > 0 else 1)
