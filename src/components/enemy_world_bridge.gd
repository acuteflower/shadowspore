class_name EnemyWorldBridge
extends Node2D
## Peer-local V2 physical & ecological environment bridge (`T3`, `T4`, `V6`, `V7`).
## Connects an enemy rig to `LivingGrass`, `WaterField`, `GroundSurfaces`, `LivingTree`, and `TimeManager`
## with zero network traffic and zero per-frame node allocations.

const MAX_FX_MOTES: int = 28
const ICHOR_DARK: Color = Color("1a1030")
const ICHOR_VEIN: Color = Color("8a4dff")
const ICHOR_HOT: Color = Color("ff4fd8")
const LEAF_WARM: Color = Color("7a5338")
const SCREE_CHIP: Color = Color("8d8b9e")
const WATER_DROP: Color = Color("bceef2")


class WorldFxMote:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 2.0
	var z_vel: float = 20.0
	var age: float = 0.0
	var life: float = 0.45
	var col: Color = Color("8a4dff")
	var size_px: Vector2 = Vector2.ONE


var sun_glare: float = 0.0 ## 0 = shaded / night, 1 = exposed to harsh midday sun
var in_canopy_shade: bool = false

var _owner_body: Node2D
var _motes: Array[WorldFxMote] = []
var _wet_claws: int = 0
var _stone_click_cd: float = 0.0
var _shade_timer: float = 0.0
var _glare_spark_cd: float = 0.25
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 1
	_rng.seed = absi(get_instance_id()) + 1337


func configure(owner_body: Node2D, zone_node: Node2D = null) -> void:
	_owner_body = owner_body
	if _owner_body != null:
		_owner_body.set_meta("grass_radius", 13.5)
		_owner_body.set_meta("grass_weight", 0.72)
	if zone_node != null and _owner_body != null:
		sync_zone_z(zone_node, _owner_body.global_position)


func sync_zone_z(zone_node: Node2D, world_pos: Vector2) -> void:
	if zone_node == null:
		return
	if Interiors.slot_at(world_pos) >= 0 or MineManager.in_mine(world_pos):
		zone_node.z_index = -3
		return
	# Above GroundSurfaces (-9..-8), WaterField (-7..-6), and SunShadows (-5), below Y-sorted LivingGrass & actors (0)
	var has_v2_surfaces: bool = false
	for patch: Node in Terrain.patches:
		if patch is GroundSurfaces or patch is WaterField or patch is RockyGround:
			has_v2_surfaces = true
			break
	zone_node.z_index = -4 if has_v2_surfaces else -8


func set_crouched_stealth(crouched: bool, scale_factor: float = 1.0) -> void:
	if _owner_body == null:
		return
	_owner_body.set_meta("grass_radius", (8.0 if crouched else 14.0) * scale_factor)
	_owner_body.set_meta("grass_weight", 0.18 if crouched else 0.78)


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_stone_click_cd = maxf(0.0, _stone_click_cd - dt)
	_shade_timer -= dt
	if _shade_timer <= 0.0 and _owner_body != null:
		_shade_timer = 0.25
		_refresh_microclimate(_owner_body.global_position)

	if sun_glare > 0.35 and _owner_body != null and DisplayServer.get_name() != "headless":
		_glare_spark_cd -= dt
		if _glare_spark_cd <= 0.0:
			_glare_spark_cd = _rng.randf_range(0.22, 0.45)
			# Crisp 1-px dark-violet spore flicker under harsh sun (strictly NO grey smoke per design_guide.md!)
			_push_mote(
				_owner_body.global_position + Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-10.0, -4.0)),
				Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-4.0, 2.0)),
				6.0,
				14.0,
				0.34,
				ICHOR_VEIN if _rng.randf() < 0.5 else Color("5c2fb8"),
				Vector2.ONE,
				false
			)

	if not _motes.is_empty():
		var wind_v: Vector2 = WorldWind.sample(global_position) * 18.0
		for i: int in range(_motes.size() - 1, -1, -1):
			var m: WorldFxMote = _motes[i]
			m.age += dt
			if m.age >= m.life:
				_motes.remove_at(i)
				continue
			m.vel = m.vel.lerp(wind_v, minf(1.0, dt * 2.2))
			m.pos += m.vel * dt
			m.z_vel -= 68.0 * dt
			m.z_h = maxf(0.0, m.z_h + m.z_vel * dt)
			if m.z_h <= 0.0:
				m.vel *= 0.55
				m.z_vel = 0.0
		queue_redraw()


func _refresh_microclimate(world_pos: Vector2) -> void:
	in_canopy_shade = is_position_shaded(world_pos)
	var night: float = TimeManager.night_amount()
	var rain: float = WeatherManager.current.rain if WeatherManager.current != null else 0.0
	if night >= 0.35 or in_canopy_shade or rain >= 0.35 or Interiors.slot_at(world_pos) >= 0 or MineManager.in_mine(world_pos):
		sun_glare = move_toward(sun_glare, 0.0, 0.45)
	else:
		sun_glare = move_toward(sun_glare, clampf(1.0 - night * 2.5, 0.0, 1.0), 0.45)


## Checks whether `world_pos` lies beneath a `LivingTree` crown (`TreeMicroZone` / `crown_radius`).
func is_position_shaded(world_pos: Vector2) -> bool:
	if not is_inside_tree():
		return false
	for patch: Node in Terrain.patches:
		if patch is GroundSurfaces:
			var gs: GroundSurfaces = patch as GroundSurfaces
			for tz: GroundSurfaces.TreeMicroZone in gs._trees:
				if world_pos.distance_to(tz.center) <= tz.crown_r * 0.96:
					return true
	# Fallback check against live LivingTree instances in current scene
	var root: Node = get_tree().current_scene
	if root != null:
		var trees_node: Node = root.find_child("GlimmtalTrees", false, false)
		if trees_node != null:
			for child: Node in trees_node.get_children():
				if child is LivingTree:
					var lt: LivingTree = child as LivingTree
					if lt.stage >= 3 and not lt.is_depleted() and world_pos.distance_to(lt.global_position) <= lt.crown_radius():
						return true
	return false


## Finds the nearest `LivingTree` crown overhead and imparts a physical `1-2 px` leaf-cluster dip (`CANOPY_DROP`).
func impulse_overhead_canopy(world_pos: Vector2) -> void:
	if not is_inside_tree() or get_tree().current_scene == null:
		return
	var best_tree: LivingTree = null
	var best_d: float = 96.0
	var trees_node: Node = get_tree().current_scene.find_child("GlimmtalTrees", false, false)
	if trees_node != null:
		for child: Node in trees_node.get_children():
			if child is LivingTree:
				var lt: LivingTree = child as LivingTree
				var d: float = world_pos.distance_to(lt.global_position)
				if lt.stage >= 3 and d < best_d:
					best_d = d
					best_tree = lt
	if best_tree != null and best_tree.has_method("_impulse_all_clusters"):
		best_tree.call("_impulse_all_clusters", Vector2(0.0, 2.2), 16.0)


## True if `world_pos` is deep unwalkable water (`WaterField.is_deep` or `WorldRivers.depth_amount`).
func is_deep_water(world_pos: Vector2) -> bool:
	for patch: Node in Terrain.patches:
		if patch is WaterField:
			if (patch as WaterField).is_deep(world_pos):
				return true
		elif patch is WorldRivers:
			if (patch as WorldRivers).depth_amount(world_pos) >= 0.62:
				return true
	var surf: String = Terrain.surface_at(world_pos)
	return surf == "deep_water"


## Returns terrain traction/speed multiplier for `ShadowSpider` locomotion (`T1`).
func surface_speed_mult(world_pos: Vector2) -> float:
	var surf: String = Terrain.surface_at(world_pos)
	match surf:
		"ancient_stone", "stone":
			return 1.08
		"path", "quartz":
			return 1.04
		"mud", "quicksand":
			return 0.74
		"puddle", "shallow_water", "tide_shallow":
			return 0.80
		"sand", "beach_sand":
			return 0.90
	return 1.0


## Called on every `SpiderRig.foot_landed(foot_pos)`: drives `WaterField` 30 Hz claw ripples, wet prints, and stone clicks!
func on_claw_landed(foot_pos: Vector2, heavy: bool = false) -> void:
	if not is_inside_tree():
		return
	var hit_water: bool = false
	for patch: Node in Terrain.patches:
		if patch is WaterField:
			var wf: WaterField = patch as WaterField
			var info: Dictionary = wf.water_field_at(foot_pos)
			if bool(info.get("water", false)):
				wf.add_water_impulse(foot_pos, 0.56 if heavy else 0.30, 7.0 if heavy else 4.5, Vector2.ZERO)
				hit_water = true
				break
	var surf: String = Terrain.surface_at(foot_pos)
	if not hit_water and surf in ["puddle", "shallow_water", "tide_shallow"]:
		hit_water = true

	if hit_water:
		_wet_claws = 4
		if DisplayServer.get_name() != "headless" and (heavy or _rng.randf() < 0.45):
			_push_mote(foot_pos, Vector2(_rng.randf_range(-16.0, 16.0), _rng.randf_range(-10.0, 6.0)), 1.5, 24.0, 0.32, WATER_DROP, Vector2.ONE, true)
		return

	if _wet_claws > 0:
		_wet_claws -= 1
		if DisplayServer.get_name() != "headless":
			_push_mote(foot_pos, Vector2.ZERO, 0.5, 4.0, 0.55, Color("3c2d5e"), Vector2(2.0, 1.0), true)

	if surf in ["stone", "ancient_stone", "gravel"] and _stone_click_cd <= 0.0 and _owner_body != null:
		_stone_click_cd = 0.19
		Sfx.at(_owner_body, "spider_step_stone", foot_pos, -15.0 if heavy else -19.0)


## Sweeps `LivingGrass` blades & spawns context-aware severed grass/petal/leaf/scree debris (`T3`, `V7`).
func on_scythe_slash(origin: Vector2, aim_dir: Vector2, reach: float) -> void:
	if not is_inside_tree():
		return
	var dir: Vector2 = aim_dir.normalized() if aim_dir.length_squared() > 0.001 else Vector2.DOWN
	for node: Node in get_tree().get_nodes_in_group("living_grass"):
		if node is LivingGrass:
			var lg: LivingGrass = node as LivingGrass
			lg.stamp_slash(origin, dir, reach, 0.88)
			if lg._has_grass_near(origin + dir * (reach * 0.55)):
				lg._spawn_motes(origin + dir * (reach * 0.55), 5, 44.0, false)

	var impact_pt: Vector2 = origin + dir * (reach * 0.62)
	var surf: String = Terrain.surface_at(impact_pt)
	if DisplayServer.get_name() != "headless":
		if surf in ["forest_floor", "damp_earth", "moss"]:
			for _i: int in 4:
				_push_mote(impact_pt, dir.rotated(_rng.randf_range(-0.7, 0.7)) * _rng.randf_range(18.0, 38.0), 2.0, 22.0, 0.48, LEAF_WARM, Vector2(2.0, 1.0), true)
		elif surf in ["gravel", "stone", "ancient_stone"]:
			for _i: int in 3:
				_push_mote(impact_pt, dir.rotated(_rng.randf_range(-0.6, 0.6)) * _rng.randf_range(24.0, 46.0), 1.5, 26.0, 0.36, SCREE_CHIP, Vector2.ONE, true)
		elif surf in ["puddle", "shallow_water"]:
			on_claw_landed(impact_pt, true)


## Radial shockwave into `LivingGrass` & `WaterField` (`GRAPPLE` impact, `CANOPY_DROP` landing, `EXPOSED` crash, `DEAD`).
func on_ground_burst(center: Vector2, radius: float, strength: float = 0.90) -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group("living_grass"):
		if node is LivingGrass:
			(node as LivingGrass).stamp_burst(center, radius, strength, 6.5)
	for patch: Node in Terrain.patches:
		if patch is WaterField:
			var wf: WaterField = patch as WaterField
			if bool(wf.water_field_at(center).get("water", false)):
				wf.add_water_impulse(center, strength * 0.75, radius * 0.45, Vector2.ZERO)


## Spawns directional Void-ichor & chitin splinters along the incoming hit vector (`V6`).
func on_hit_splatter(body_pos: Vector2, attacker_pos: Vector2, heavy: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var away: Vector2 = (body_pos - attacker_pos).normalized()
	if away.length_squared() < 0.01:
		away = Vector2.UP
	var count: int = 7 if heavy else 4
	for i: int in count:
		var spread: Vector2 = away.rotated(_rng.randf_range(-0.55, 0.55)) * _rng.randf_range(26.0, 62.0 if heavy else 44.0)
		var col: Color = ICHOR_HOT if (heavy and i == 0) else (ICHOR_VEIN if i % 2 == 0 else ICHOR_DARK)
		_push_mote(body_pos + Vector2(0.0, -6.0), spread, 5.0, _rng.randf_range(16.0, 32.0), _rng.randf_range(0.32, 0.54), col, Vector2(2.0 if i == 0 else 1.0, 1.0), true)


func _push_mote(wpos: Vector2, vel: Vector2, zh: float, zvel: float, life: float, col: Color, sz: Vector2, redraw_now: bool) -> void:
	if _motes.size() >= MAX_FX_MOTES:
		_motes.pop_front()
	var m: WorldFxMote = WorldFxMote.new()
	m.pos = wpos
	m.vel = vel
	m.z_h = zh
	m.z_vel = zvel
	m.life = life
	m.col = col
	m.size_px = sz
	_motes.append(m)
	if redraw_now:
		queue_redraw()


func _draw() -> void:
	if _motes.is_empty():
		return
	var inv: Transform2D = get_global_transform().affine_inverse()
	for m: WorldFxMote in _motes:
		var fade: float = clampf(1.0 - maxf(0.0, (m.age / maxf(m.life, 0.01) - 0.55) / 0.45), 0.0, 1.0)
		if fade <= 0.02:
			continue
		var local_p: Vector2 = (inv * (m.pos - Vector2(0.0, m.z_h))).round()
		var c: Color = m.col
		c.a *= fade
		draw_rect(Rect2(local_p, m.size_px), c)
