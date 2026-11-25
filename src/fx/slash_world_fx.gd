class_name SlashWorldFx
extends Node2D
## Contextual Sword-Slash & World-Contact Pixel-Art Particle Engine (Shadowspore 2.0).
##
## Replaces generic green grass particles on every swing with physically grounded,
## surface- and object-aware pixel-art VFX that run cleanly on every peer:
##   1. Solid world-object contact along the blade arc (Physics Layer 1):
##        - Stone / Sanctuary Ruin / Bridge Parapet / Cliff / Rock -> hot unlit steel sparks
##          with velocity trails + bouncing mineral stone chips (+ dew splash on filled dew basin)
##        - Wood / Tree Trunk / Fallen Log / Fence / Hut -> species-matched bark & wood splinters
##          (white paper-bark curls for silver_birch, oak bark, wild apple bark, warm timber)
##        - Crystal / Quartz Obelisk -> singing golden-cyan unlit crystal glints
##   2. Ground & water surface swept by the blade's wake (3 arc samples so crossing shorelines,
##      paths, or stone borders reacts accurately to each spot the blade actually cuts):
##        - Water (brook, ocean, tide_shallow, puddle) -> real foaming WaterField wave wake
##          (`add_water_impulse`) + directional spray droplets + night bioluminescent glints
##        - Dry Sand (beach_sand, sand, steppe, quicksand) -> directional golden sand fan
##          (plus sun-bleached dry Strandhafer wisps only where coastal dune_oat tufts exist)
##        - Wet Sand (wet_sand) -> heavier dark damp sand specks + occasional swash foam bead
##        - Actual LivingGrass (gated by true tuft presence!) -> habitat-matched torn grass
##          snippets (meadow, forest fern, brook reed, coastal dune oat, stone-seam moss)
##          + matching floral petals + morning dew / rain droplets
##        - Stone / Ancient Stone / Gravel / Mine Stone / Slope -> mineral grit, pale dust &
##          glancing steel-on-stone sparks (full spark eruption on heavy overhead chop!)
##        - Quartz -> singing golden-lilac unlit quartz sparks + pale crystal dust
##        - Forest Floor / Bed / Field -> fluttering autumn/woodland leaves + humus crumbs
##        - Moss -> soft velvety dark-moss flecks
##        - Damp Earth / Mud -> heavy dark sticky mud splatters
##        - Path -> warm dry road dust + fine grit
##        - Wood -> subtle warm timber dust (+ splinters on heavy chop)
##        - Hexenwald -> sinking witch-green unlit spores + dark ash

const MAX_MOTES: int = 120
const MAX_UNLIT_MOTES: int = 48
const SOLID_MASK: int = 1 ## Physics Layer 1: world solids (ruins, rocks, trees, walls, parapets)

enum MoteKind {
	GRASS_SNIPPET = 0,
	PETAL_OR_LEAF = 1,
	SAND_GRAIN = 2,
	WATER_DROP = 3,
	SPARK_HOT = 4,
	STONE_CHIP = 5,
	WOOD_SPLINTER = 6,
	MUD_SPLAT = 7,
	DUST_WISP = 8,
	GLINT_UNLIT = 9,
}

# ---------------- HANDCRAFTED MATERIAL PALETTES ----------------

const PAL_MEADOW_GRASS: Array[Color] = [
	Color("c4ee96"), Color("87c46f"), Color("234f3b"), Color("4a8858"),
]
const PAL_FOREST_GRASS: Array[Color] = [
	Color("6cb072"), Color("3f7c54"), Color("1e3d30"), Color("2d5d46"),
]
const PAL_REED_GRASS: Array[Color] = [
	Color("96d8ae"), Color("5ea882"), Color("1f4f46"), Color("3e8870"),
]
const PAL_DUNE_OAT: Array[Color] = [
	Color("f2ecc4"), Color("d4cca0"), Color("787e54"), Color("b4ad7c"),
]
const PAL_MOSS: Array[Color] = [
	Color("8cc284"), Color("5a9a62"), Color("224432"), Color("3c6e4a"),
]
const PAL_PETAL_WHITE: Array[Color] = [
	Color("fffcf2"), Color("dfd9cc"), Color("ffe894"),
]
const PAL_PETAL_BLUE: Array[Color] = [
	Color("e0f2ff"), Color("8db8e6"), Color("faf5e8"),
]
const PAL_PETAL_LILAC: Array[Color] = [
	Color("f0e2ff"), Color("a882dc"), Color("faf5e8"),
]
const PAL_PETAL_GOLD: Array[Color] = [
	Color("ffea8a"), Color("e4b848"), Color("fffcf2"),
]
const PAL_PETAL_ROSE: Array[Color] = [
	Color("e8b6cc"), Color("ba7698"), Color("fffcf2"),
]
const PAL_TALL_POLLEN: Array[Color] = [
	Color("f5f0da"), Color("e4dc9e"), Color("ece9d8"),
]
const PAL_BEACH_SAND: Array[Color] = [
	Color("fff6dc"), Color("f2dfb2"), Color("b0894e"), Color("886638"),
]
const PAL_DESERT_SAND: Array[Color] = [
	Color("fff0c4"), Color("dfa85c"), Color("a46e34"), Color("7e5026"),
]
const PAL_WET_SAND: Array[Color] = [
	Color("6b5940"), Color("4c3e2c"), Color("9c8868"), Color("b6a27e"),
]
const PAL_WATER_DAY: Array[Color] = [
	Color("ffffff"), Color("dff8ff"), Color("88d8e6"), Color("c4f2f8"),
]
const PAL_WATER_BIO_NIGHT: Array[Color] = [
	Color("c8fff6"), Color("6cf4e4"), Color("88d8ff"),
]
const PAL_DEW: Array[Color] = [
	Color("d6fff8"), Color("78f4e6"), Color("bfe9ff"),
]
const PAL_STONE_CHIP: Array[Color] = [
	Color("c2c8cc"), Color("8e96a2"), Color("636a78"), Color("a4acb4"),
]
const PAL_STONE_DUST: Array[Color] = [
	Color("cfd6ce"), Color("a8b0b4"), Color("8a929a"),
]
const PAL_PATH_DUST: Array[Color] = [
	Color("d8cab0"), Color("b8a484"), Color("947f62"), Color("e2d6be"),
]
const PAL_FOREST_LEAF: Array[Color] = [
	Color("a67144"), Color("c89358"), Color("765138"), Color("56734a"), Color("8d5e3a"),
]
const PAL_HUMUS: Array[Color] = [
	Color("583d2e"), Color("3e2a20"), Color("72523d"),
]
const PAL_MUD: Array[Color] = [
	Color("5a3d2e"), Color("3d261c"), Color("765440"), Color("2e1d15"),
]
const PAL_WOOD_TIMBER: Array[Color] = [
	Color("b68c5e"), Color("8a6544"), Color("d6b488"), Color("694932"),
]
const PAL_WOOD_BIRCH: Array[Color] = [
	Color("ece8dc"), Color("cbc7bb"), Color("9a948a"), Color("3d383e"),
]
const PAL_WOOD_APPLE: Array[Color] = [
	Color("6e4c3c"), Color("966a50"), Color("bc9272"), Color("4c342a"),
]
const PAL_QUARTZ_UNLIT: Array[Color] = [
	Color("fff4c2"), Color("e8e6fa"), Color("e6c468"), Color("b4ecff"),
]
const PAL_WITCH_SPORE: Array[Color] = [
	Color("a8ff6a"), Color("66c44a"), Color("d8ffbe"),
]


class SlashMote:
	var kind: int = MoteKind.DUST_WISP
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 2.0
	var z_vel: float = 18.0
	var grav: float = 80.0
	var drag: float = 3.0
	var bounce: float = 0.0
	var stick: bool = false
	var age: float = 0.0
	var life: float = 0.45
	var phase: float = 0.0
	var col: Color = Color.WHITE
	var col_end: Color = Color.WHITE
	var size_px: Vector2 = Vector2.ONE
	var flutter: bool = false
	var unlit: bool = false
	var trail: bool = false


class _UnlitCanvas extends Node2D:
	var owner_fx: SlashWorldFx

	func _ready() -> void:
		z_as_relative = false
		z_index = 3
		material = Unlit.material()
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		if owner_fx != null:
			owner_fx._draw_motes(self, true)


static var _instance: SlashWorldFx = null

var _probe_circle: CircleShape2D = null
var _lit_motes: Array[SlashMote] = []
var _unlit_motes: Array[SlashMote] = []
var _unlit_layer: _UnlitCanvas
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sfx_cd_msec: int = 0

## Telemetry for verification tests (`tools/test_slash_world_fx.tscn`)
var last_materials: PackedStringArray = PackedStringArray()
var last_objects: PackedStringArray = PackedStringArray()
var last_mote_kinds: PackedInt32Array = PackedInt32Array()
var last_spawn_count: int = 0


## Returns the single shared world-space `SlashWorldFx` attached to the active scene.
static func of(context: Node) -> SlashWorldFx:
	if context == null or not context.is_inside_tree():
		return null
	var tree: SceneTree = context.get_tree()
	var host_scene: Node = tree.current_scene
	if host_scene == null:
		host_scene = tree.root
	if is_instance_valid(_instance) and _instance.is_inside_tree() and _instance.get_parent() == host_scene:
		return _instance
	var existing: Node = host_scene.get_node_or_null("SlashWorldFx")
	if existing is SlashWorldFx:
		_instance = existing as SlashWorldFx
		return _instance
	var fx: SlashWorldFx = SlashWorldFx.new()
	fx.name = "SlashWorldFx"
	host_scene.add_child(fx)
	_instance = fx
	return fx


func _ready() -> void:
	z_as_relative = false
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_unlit_layer = _UnlitCanvas.new()
	_unlit_layer.name = "SlashWorldUnlit"
	_unlit_layer.owner_fx = self
	add_child(_unlit_layer)
	set_process(false)


func _exit_tree() -> void:
	_probe_circle = null
	if _instance == self:
		_instance = null


func active_mote_count() -> int:
	return _lit_motes.size() + _unlit_motes.size()


func clear_motes() -> void:
	_lit_motes.clear()
	_unlit_motes.clear()
	queue_redraw()
	if _unlit_layer != null:
		_unlit_layer.queue_redraw()
	set_process(false)


# ==============================================================================
# PUBLIC ENTRY POINTS (called locally on every peer from AttackComponent)
# ==============================================================================

## Contextual world reaction for normal combo slashes, thrusts, and diagonal swings.
func on_swing_sweep(
	origin: Vector2,
	aim_dir: Vector2,
	reach: float,
	arc_rad: float,
	sweep_sign: float,
	style: String,
	weapon_tag: String,
	exclude_rids: Array[RID] = []
) -> void:
	if not is_inside_tree():
		return
	var dir: Vector2 = aim_dir.normalized() if aim_dir.length_squared() > 0.001 else Vector2.RIGHT
	var sgn: float = -1.0 if sweep_sign < 0.0 else 1.0
	var tangent: Vector2 = Vector2(-dir.y, dir.x) * sgn
	var is_thrust: bool = style == "thrust"
	var eff_reach: float = clampf(reach, 18.0, 56.0)
	var half_arc: float = clampf(arc_rad * 0.40, 0.25, 1.05)

	last_materials.clear()
	last_objects.clear()
	last_mote_kinds.clear()
	last_spawn_count = 0

	# 1. Sample 3 points along the actual blade path (or 2 forward points for a thrust)
	var sample_pts: Array[Vector2] = []
	var sample_dirs: Array[Vector2] = []
	if is_thrust:
		sample_pts.append(origin + dir * (eff_reach * 0.52))
		sample_dirs.append(dir)
		sample_pts.append(origin + dir * (eff_reach * 0.88))
		sample_dirs.append(dir)
	else:
		var a0: float = -sgn * half_arc
		var a1: float = 0.0
		var a2: float = sgn * half_arc
		for ang: float in [a0, a1, a2]:
			var ray_d: Vector2 = dir.rotated(ang)
			var r_frac: float = 0.72 if is_zero_approx(ang) else 0.64
			sample_pts.append(origin + ray_d * (eff_reach * r_frac))
			# Tangential blade velocity at this arc angle (curves cleanly with the sword!)
			var local_tan: Vector2 = (Vector2(-ray_d.y, ray_d.x) * sgn * 0.78 + ray_d * 0.42).normalized()
			sample_dirs.append(local_tan)

	# 2. Check solid world-object contact (ruins, bridge parapets, rocks, trees, cliffs, logs)
	var hit_solid: Dictionary = _probe_solid_contact(origin, dir, tangent, eff_reach, sample_pts, exclude_rids)
	if not hit_solid.is_empty():
		_emit_solid_contact(hit_solid, false, weapon_tag)

	# 3. Emit ground / water / grass surface wake at each sampled arc point
	var water_impulsed: bool = false
	var count_scale: float = 1.15 if weapon_tag == "sickle" else (0.95 if is_thrust else 1.0)
	for i: int in sample_pts.size():
		var pt: Vector2 = sample_pts[i]
		var flow_dir: Vector2 = sample_dirs[i]
		var did_water: bool = _emit_surface_wake(pt, flow_dir, false, weapon_tag, count_scale, water_impulsed)
		if did_water:
			water_impulsed = true

	if active_mote_count() > 0:
		set_process(true)
		queue_redraw()
		if _unlit_layer != null:
			_unlit_layer.queue_redraw()


## Contextual ground-slam & object-impact burst for heavy overhead chops (`AttackComponent._impact_dust`).
func on_heavy_impact(
	origin: Vector2,
	aim_dir: Vector2,
	reach: float,
	weapon_tag: String,
	exclude_rids: Array[RID] = []
) -> void:
	if not is_inside_tree():
		return
	var dir: Vector2 = aim_dir.normalized() if aim_dir.length_squared() > 0.001 else Vector2.RIGHT
	var impact_at: Vector2 = origin + dir * minf(reach * 0.80, 40.0)
	var tangent: Vector2 = Vector2(-dir.y, dir.x)

	last_materials.clear()
	last_objects.clear()
	last_mote_kinds.clear()
	last_spawn_count = 0

	var probe_pts: Array[Vector2] = [origin + dir * minf(reach * 0.55, 28.0), impact_at]
	var hit_solid: Dictionary = _probe_solid_contact(origin, dir, tangent, reach, probe_pts, exclude_rids)
	if not hit_solid.is_empty():
		_emit_solid_contact(hit_solid, true, weapon_tag)

	_emit_surface_wake(impact_at, dir, true, weapon_tag, 1.0, false)

	if active_mote_count() > 0:
		set_process(true)
		queue_redraw()
		if _unlit_layer != null:
			_unlit_layer.queue_redraw()


# ==============================================================================
# 1. SOLID WORLD OBJECT DETECTION & CONTACT EFFECTS
# ==============================================================================

func _probe_solid_contact(
	origin: Vector2,
	aim_dir: Vector2,
	tangent: Vector2,
	reach: float,
	sample_pts: Array[Vector2],
	exclude_rids: Array[RID]
) -> Dictionary:
	var w2d: World2D = get_world_2d()
	if w2d == null:
		return {}
	var space: PhysicsDirectSpaceState2D = w2d.direct_space_state
	if space == null:
		return {}
	if _probe_circle == null:
		_probe_circle = CircleShape2D.new()
		_probe_circle.radius = 9.5

	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	params.shape = _probe_circle
	params.collision_mask = SOLID_MASK
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = exclude_rids

	var best: Dictionary = {}
	var best_priority: int = -1
	for pt: Vector2 in sample_pts:
		params.transform = Transform2D(0.0, pt)
		var hits: Array[Dictionary] = space.intersect_shape(params, 6)
		for h: Dictionary in hits:
			var col_obj: Object = h.get("collider") as Object
			if col_obj == null:
				continue
			var info: Dictionary = _classify_solid(col_obj)
			if info.is_empty():
				continue
			var prio: int = int(info.get("priority", 1))
			if prio > best_priority:
				best_priority = prio
				var contact_pos: Vector2 = pt
				if col_obj is Node2D:
					var obj_p: Vector2 = (col_obj as Node2D).global_position
					if obj_p.distance_squared_to(pt) < reach * reach * 2.5:
						contact_pos = pt.lerp(obj_p, 0.32)
				best = info
				best["pos"] = contact_pos
				best["out_dir"] = (tangent * 0.72 - aim_dir * 0.45).normalized()
	return best


func _classify_solid(col_obj: Object) -> Dictionary:
	var node: Node = col_obj as Node
	if node == null:
		return {}
	# Ignore invisible / river-depth blockers (swimming bounds are water, not stone!)
	if node.is_in_group("river_depth"):
		return {}
	var parent: Node = node.get_parent()
	var holder: Node = parent if parent != null else node

	# 1. SanctuaryRuin (parapets, runic waymarkers, fallen column drums, ancient dew basins)
	if holder is SanctuaryRuin:
		var ruin: SanctuaryRuin = holder as SanctuaryRuin
		var kind: String = "ruin_basin" if (ruin.ruin_kind == "ancient_dew_basin" and not ruin.is_depleted()) else "stone"
		return {"kind": kind, "priority": 4, "quiet_sfx": false, "species": ""}

	# 2. LivingRock (already emits `clang` + flint sparks via HarvestHurtbox on direct sword hits)
	if holder is LivingRock:
		if (holder as LivingRock).is_depleted():
			return {}
		return {"kind": "living_rock", "priority": 3, "quiet_sfx": true, "species": ""}

	# 3. LivingTree (emits leaf rustle on sword hits -> add authentic species-matched bark splinters!)
	if holder is LivingTree:
		var lt: LivingTree = holder as LivingTree
		if lt.is_depleted():
			return {}
		return {"kind": "living_tree", "priority": 3, "quiet_sfx": true, "species": lt.species_id}

	# 4. WaterBridge stone parapets
	if holder is WaterBridge or (parent != null and parent.get_parent() is WaterBridge):
		return {"kind": "stone", "priority": 4, "quiet_sfx": false, "species": ""}

	# 5. Relief cliffs & walls
	if node.is_in_group("relief_walls") or holder.is_in_group("relief_walls"):
		return {"kind": "stone", "priority": 3, "quiet_sfx": false, "species": ""}

	# 6. Classic WorldLevel props (Rock, FirTree, FallenLog, TownStructure, WaystoneStatue, ArenaPillar)
	if holder is Rock:
		return {"kind": "stone", "priority": 3, "quiet_sfx": false, "species": ""}
	if holder is FirTree:
		return {"kind": "wood", "priority": 3, "quiet_sfx": false, "species": "oak"}
	if holder is FallenLog:
		return {"kind": "wood", "priority": 3, "quiet_sfx": false, "species": "oak"}

	# 7. Fallback by node / parent name (ArenaPillar, Hallgrat walls, Waystone, Hut, Quartz obelisk, Mine walls)
	var tag: String = (node.name + " " + holder.name).to_lower()
	if "quartz" in tag or "crystal" in tag or "obelisk" in tag or "waystone" in tag or "curse" in tag:
		return {"kind": "crystal", "priority": 4, "quiet_sfx": false, "species": ""}
	if "stone" in tag or "rock" in tag or "wall" in tag or "cliff" in tag or "pillar" in tag or "parapet" in tag or "ruin" in tag or "mine" in tag or "hallgrat" in tag or "plaza" in tag:
		return {"kind": "stone", "priority": 3, "quiet_sfx": false, "species": ""}
	if "tree" in tag or "wood" in tag or "log" in tag or "fence" in tag or "hut" in tag or "wagon" in tag or "pier" in tag or "post" in tag or "bench" in tag or "stock" in tag or "workshop" in tag:
		return {"kind": "wood", "priority": 2, "quiet_sfx": false, "species": "oak"}
	return {}


func _emit_solid_contact(hit: Dictionary, heavy: bool, weapon_tag: String) -> void:
	var kind: String = String(hit.get("kind", ""))
	var pos: Vector2 = hit.get("pos", Vector2.ZERO) as Vector2
	var out_dir: Vector2 = hit.get("out_dir", Vector2.UP) as Vector2
	var quiet_sfx: bool = bool(hit.get("quiet_sfx", false))
	var species: String = String(hit.get("species", ""))
	if not last_objects.has(kind):
		last_objects.append(kind)

	match kind:
		"stone", "ruin_basin":
			var n_sparks: int = (11 if heavy else 6) + (2 if weapon_tag == "pickaxe" else 0)
			var n_chips: int = 6 if heavy else 3
			_spawn_sparks(pos, out_dir, n_sparks, 58.0, 128.0 if heavy else 98.0, false)
			_spawn_chips(pos, out_dir, n_chips, PAL_STONE_CHIP, 26.0, 62.0 if heavy else 44.0)
			_spawn_dust(pos, out_dir, 4 if heavy else 2, PAL_STONE_DUST, 14.0, 28.0)
			if kind == "ruin_basin":
				_spawn_water_droplets(pos + Vector2(0.0, -4.0), out_dir, 5 if heavy else 3, PAL_DEW, true)
			if not quiet_sfx:
				_play_contact_sfx("pick_rock", pos, -9.0 if heavy else -13.0, 0.12)

		"living_rock":
			# LivingRock's own HarvestHurtbox emits flint sparks + clang on direct hits;
			# add subtle tangential blade-edge graze sparks + mineral dust!
			_spawn_sparks(pos, out_dir, 5 if heavy else 2, 48.0, 96.0, false)
			_spawn_dust(pos, out_dir, 3 if heavy else 2, PAL_STONE_DUST, 14.0, 26.0)

		"crystal":
			var n_glint: int = 9 if heavy else 6
			_spawn_sparks(pos, out_dir, n_glint, 44.0, 95.0, true)
			_spawn_chips(pos, out_dir, 3 if heavy else 2, PAL_QUARTZ_UNLIT, 22.0, 48.0)
			if not quiet_sfx:
				_play_contact_sfx("prism_ring", pos, -12.0 if heavy else -16.0, 0.08)

		"wood", "living_tree":
			var pal: Array[Color] = PAL_WOOD_BIRCH if species == "silver_birch" else (PAL_WOOD_APPLE if species == "wild_apple" else PAL_WOOD_TIMBER)
			var n_splint: int = (7 if heavy else 3) + (2 if weapon_tag == "axe" else 0)
			_spawn_splinters(pos, out_dir, n_splint, pal, 28.0, 68.0 if heavy else 46.0)
			if not quiet_sfx:
				_play_contact_sfx("axe_chop", pos, -11.0 if heavy else -15.0, 0.10)


# ==============================================================================
# 2. GROUND & WATER SURFACE SWEEP EFFECTS
# ==============================================================================

func _emit_surface_wake(
	pt: Vector2,
	flow_dir: Vector2,
	heavy: bool,
	weapon_tag: String,
	count_scale: float,
	water_impulsed: bool
) -> bool:
	var surf: String = Terrain.surface_at(pt)
	var night: float = TimeManager.night_amount()
	var rain_wet: float = WeatherManager.current.ground_wet if WeatherManager.current != null else 0.0
	var tod: float = TimeManager.time_of_day
	var morning_dew: bool = tod >= 0.22 and tod <= 0.40

	# --- A. WATER SURFACES (Brook, Ocean, Shallow/Deep Water, Tide Shallow, Puddle) ---
	if surf in ["shallow_water", "deep_water", "tide_shallow", "puddle"]:
		_record_material("water")
		var is_puddle: bool = surf == "puddle"
		var n_drops: int = roundi(float(14 if heavy else (4 if is_puddle else 5)) * count_scale)
		_spawn_water_droplets(pt, flow_dir, n_drops, PAL_WATER_DAY, false)
		if night > 0.22:
			_spawn_glints(pt, flow_dir, 6 if heavy else 2, PAL_WATER_BIO_NIGHT, 28.0, 56.0)
		if not water_impulsed or heavy:
			_excite_water_field(pt, flow_dir, 1.30 if heavy else (0.55 if is_puddle else 0.85), 15.0 if heavy else 10.0)
		return true

	# --- B. DRY SAND (Coastal Beach, Quartz Desert Sand, Steppe, Quicksand) ---
	if surf in ["beach_sand", "sand", "steppe", "quicksand"]:
		_record_material(surf)
		var pal_s: Array[Color] = PAL_BEACH_SAND if surf == "beach_sand" else PAL_DESERT_SAND
		var n_sand: int = roundi(float(15 if heavy else 6) * count_scale)
		_spawn_sand_grains(pt, flow_dir, n_sand, pal_s, heavy)
		# On coastal sand dunes (`beach_sand`), if real Strandhafer (`dune_oat`) tufts actually grow right here,
		# mix in 1-2 dry sun-bleached dune straw wisps (NEVER bright green meadow grass!).
		var lg_dune: Dictionary = _query_living_grass(pt)
		if int(lg_dune["style"]) == LivingGrass.STYLE_DUNE:
			_record_material("dune_oat")
			_spawn_grass_snippets(pt, flow_dir, 3 if heavy else 1, PAL_DUNE_OAT, heavy)
		return false

	# --- C. WET SAND (Coastal Swash Zone) ---
	if surf == "wet_sand":
		_record_material("wet_sand")
		_spawn_sand_grains(pt, flow_dir, 7 if heavy else 3, PAL_WET_SAND, heavy, true)
		if heavy or _rng.randf() < 0.55:
			_spawn_water_droplets(pt, flow_dir, 4 if heavy else 1, PAL_WATER_DAY, false)
		return false

	# --- D. STONE / ANCIENT STONE / GRAVEL / MINE STONE / SLOPE ---
	if surf in ["ancient_stone", "stone", "gravel", "mine_stone", "slope"]:
		_record_material(surf)
		var is_hard_stone: bool = surf in ["ancient_stone", "stone", "mine_stone"]
		var n_chips: int = 6 if heavy else (2 if surf == "gravel" or surf == "slope" else 1)
		_spawn_chips(pt, flow_dir, n_chips, PAL_STONE_CHIP, 22.0, 56.0 if heavy else 36.0)
		_spawn_dust(pt, flow_dir, 5 if heavy else 2, PAL_STONE_DUST, 14.0, 30.0)
		# Steel-on-stone sparks: full burst on heavy chop, bright on pickaxe, crisp glancing sparks on hard stone!
		if heavy:
			_spawn_sparks(pt, flow_dir, 9 if is_hard_stone else 5, 52.0, 118.0, false)
			_play_contact_sfx("pick_rock", pt, -8.5, 0.12)
		elif weapon_tag == "pickaxe" or (is_hard_stone and _rng.randf() < 0.55):
			_spawn_sparks(pt, flow_dir, 3 if weapon_tag == "pickaxe" else 1, 46.0, 86.0, false)
		return false

	# --- E. QUARTZ (Singing Quartz Desert Floor) ---
	if surf == "quartz":
		_record_material("quartz")
		_spawn_sparks(pt, flow_dir, 9 if heavy else 3, 44.0, 96.0, true)
		_spawn_dust(pt, flow_dir, 4 if heavy else 2, PAL_STONE_DUST, 16.0, 32.0)
		if heavy:
			_play_contact_sfx("prism_ring", pt, -10.0, 0.08)
		return false

	# --- F. FOREST FLOOR / BED / FIELD (Dry Autumn Leaves + Dark Humus) ---
	if surf in ["forest_floor", "bed", "field"]:
		_record_material(surf)
		if surf == "forest_floor":
			_spawn_flutter_leaves(pt, flow_dir, 6 if heavy else 2, PAL_FOREST_LEAF, heavy)
		_spawn_mud_or_humus(pt, flow_dir, 6 if heavy else 2, PAL_HUMUS, heavy, false)
		var lg_f: Dictionary = _query_living_grass(pt)
		if int(lg_f["style"]) == LivingGrass.STYLE_FOREST and (heavy or _rng.randf() < 0.65):
			_spawn_grass_snippets(pt, flow_dir, 3 if heavy else 1, PAL_FOREST_GRASS, heavy)
		return false

	# --- G. MOSS (Soft Velvety Moss Cushion) ---
	if surf == "moss":
		_record_material("moss")
		_spawn_grass_snippets(pt, flow_dir, 6 if heavy else 2, PAL_MOSS, heavy)
		if morning_dew or rain_wet > 0.25:
			_spawn_water_droplets(pt, flow_dir, 2 if heavy else 1, PAL_DEW, false)
		return false

	# --- H. DAMP EARTH & MUD ---
	if surf in ["damp_earth", "mud"]:
		_record_material(surf)
		_spawn_mud_or_humus(pt, flow_dir, 8 if heavy else 3, PAL_MUD, heavy, true)
		return false

	# --- I. DIRT PATH ---
	if surf == "path":
		_record_material("path")
		_spawn_dust(pt, flow_dir, 7 if heavy else 3, PAL_PATH_DUST, 16.0, 38.0 if heavy else 28.0)
		if heavy or _rng.randf() < 0.45:
			_spawn_chips(pt, flow_dir, 3 if heavy else 1, PAL_STONE_CHIP, 18.0, 36.0)
		return false

	# --- J. WOOD DECK / FLOOR ---
	if surf == "wood":
		_record_material("wood")
		_spawn_dust(pt, flow_dir, 4 if heavy else 2, PAL_WOOD_TIMBER, 12.0, 26.0)
		if heavy or weapon_tag == "axe":
			_spawn_splinters(pt, flow_dir, 4 if heavy else 2, PAL_WOOD_TIMBER, 24.0, 52.0)
		return false

	# --- K. GRASS (Gated by ACTUAL LivingGrass tufts whenever LivingGrass covers this area!) ---
	if surf == "grass":
		var hex_amt: float = BiomeBlend.amount_at(pt)
		if hex_amt > 0.45:
			_record_material("hexenwald")
			_spawn_glints(pt, flow_dir, 4 if heavy else 2, PAL_WITCH_SPORE, 14.0, 28.0)
			_spawn_mud_or_humus(pt, flow_dir, 4 if heavy else 1, PAL_HUMUS, heavy, false)
			return false

		var lg_info: Dictionary = _query_living_grass(pt)
		var covered: bool = bool(lg_info["covered"])
		var g_style: int = int(lg_info["style"])
		var floral: int = int(lg_info["floral"])
		var tall_k: float = float(lg_info.get("tallness", 0.0))

		# If a LivingGrass ecosystem owns this tile and cleared it (around rocks, paths, shoreline),
		# NEVER spawn green grass where there is no grass — emit light earthy ground dust instead!
		if covered and g_style == LivingGrass.STYLE_NONE:
			_record_material("bare_earth")
			_spawn_dust(pt, flow_dir, 4 if heavy else 1, PAL_PATH_DUST, 12.0, 24.0)
			return false

		var pal_g: Array[Color] = _grass_palette_for_style(g_style)
		var mat_name: String = "dune_oat" if g_style == LivingGrass.STYLE_DUNE else (
			"forest_grass" if g_style == LivingGrass.STYLE_FOREST else (
			"bank_reed" if g_style == LivingGrass.STYLE_REED else (
			"moss" if g_style == LivingGrass.STYLE_MOSS else "grass")))
		_record_material(mat_name)

		var tall_bonus: int = 2 if (tall_k >= 0.45 and heavy) else (1 if tall_k >= 0.45 else 0)
		var n_blades: int = roundi(float((7 if heavy else 2) + tall_bonus) * count_scale)
		_spawn_grass_snippets(pt, flow_dir, n_blades, pal_g, heavy)
		if tall_k >= 0.45 and (heavy or _rng.randf() < 0.65):
			_spawn_flutter_leaves(pt, flow_dir, 3 if heavy else 1, PAL_TALL_POLLEN, heavy)
		if floral > 0 and (heavy or _rng.randf() < 0.78):
			var ppal: Array[Color] = PAL_PETAL_WHITE
			match floral:
				2:
					ppal = PAL_PETAL_BLUE
				3:
					ppal = PAL_PETAL_LILAC
				4:
					ppal = PAL_PETAL_GOLD
				5:
					ppal = PAL_PETAL_ROSE
			_spawn_flutter_leaves(pt, flow_dir, 4 if heavy else 2, ppal, heavy)
		if (morning_dew or rain_wet > 0.25) and (heavy or _rng.randf() < 0.48):
			_spawn_water_droplets(pt, flow_dir, 3 if heavy else 1, PAL_DEW, morning_dew and night > 0.15)
		if heavy:
			_spawn_mud_or_humus(pt, flow_dir, 4, PAL_HUMUS, true, false)
		return false

	# Fallback for any unknown future surface: neutral dry dust, never green!
	_record_material(surf)
	_spawn_dust(pt, flow_dir, 4 if heavy else 1, PAL_PATH_DUST, 14.0, 26.0)
	return false


func _query_living_grass(pt: Vector2) -> Dictionary:
	var covered: bool = false
	for node: Node in get_tree().get_nodes_in_group("living_grass"):
		if node is LivingGrass:
			var lg: LivingGrass = node as LivingGrass
			if lg.covers_point(pt, 4.0):
				covered = true
				var st: int = lg.grass_style_at(pt)
				if st != LivingGrass.STYLE_NONE:
					return {"covered": true, "style": st, "floral": lg.floral_kind_at(pt), "tallness": lg.tallness_at(pt)}
	return {"covered": covered, "style": LivingGrass.STYLE_NONE, "floral": 0, "tallness": 0.0}


func _grass_palette_for_style(style_id: int) -> Array[Color]:
	match style_id:
		LivingGrass.STYLE_FOREST:
			return PAL_FOREST_GRASS
		LivingGrass.STYLE_REED:
			return PAL_REED_GRASS
		LivingGrass.STYLE_DUNE:
			return PAL_DUNE_OAT
		LivingGrass.STYLE_MOSS:
			return PAL_MOSS
		_:
			return PAL_MEADOW_GRASS


func _excite_water_field(pt: Vector2, flow_dir: Vector2, strength: float, radius_px: float) -> void:
	for patch: Node in Terrain.patches:
		if is_instance_valid(patch) and patch is WaterField:
			var wf: WaterField = patch as WaterField
			if bool(wf.water_field_at(pt).get("water", false)):
				wf.add_water_impulse(pt, strength, radius_px, flow_dir)
				return


# ==============================================================================
# 3. PARTICLE SPAWNERS (Distinct Physics Per Material!)
# ==============================================================================

func _spawn_grass_snippets(at: Vector2, flow_dir: Vector2, count: int, pal: Array[Color], heavy: bool) -> void:
	for _i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.GRASS_SNIPPET
		var spread: float = _rng.randf_range(-0.75, 0.75) if not heavy else _rng.randf_range(-PI, PI)
		var spd: float = _rng.randf_range(22.0, 58.0 if heavy else 44.0)
		m.pos = at + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-2.5, 2.5))
		m.vel = flow_dir.rotated(spread) * spd
		m.z_h = _rng.randf_range(2.0, 6.0)
		m.z_vel = _rng.randf_range(20.0, 46.0 if heavy else 34.0)
		m.grav = 68.0
		m.drag = 3.2
		m.life = _rng.randf_range(0.45, 0.88)
		m.phase = _rng.randf() * TAU
		m.col = pal[_rng.randi() % pal.size()]
		m.size_px = Vector2(3.0, 1.0) if (heavy and _rng.randf() < 0.30) else (Vector2(2.0, 1.0) if _rng.randf() < 0.70 else Vector2(1.0, 1.0))
		_push_mote(m)


func _spawn_flutter_leaves(at: Vector2, flow_dir: Vector2, count: int, pal: Array[Color], heavy: bool) -> void:
	for _i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.PETAL_OR_LEAF
		var spread: float = _rng.randf_range(-0.9, 0.9) if not heavy else _rng.randf_range(-PI, PI)
		var spd: float = _rng.randf_range(16.0, 44.0 if heavy else 34.0)
		m.pos = at + Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-3.0, 3.0))
		m.vel = flow_dir.rotated(spread) * spd
		m.z_h = _rng.randf_range(2.5, 7.0)
		m.z_vel = _rng.randf_range(16.0, 36.0 if heavy else 26.0)
		m.grav = 28.0
		m.drag = 4.2
		m.flutter = true
		m.life = _rng.randf_range(0.65, 1.20)
		m.phase = _rng.randf() * TAU
		m.col = pal[_rng.randi() % pal.size()]
		m.size_px = Vector2(2.0, 1.0)
		_push_mote(m)


func _spawn_sand_grains(at: Vector2, flow_dir: Vector2, count: int, pal: Array[Color], heavy: bool, wet: bool = false) -> void:
	for i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.SAND_GRAIN
		var spread: float = _rng.randf_range(-0.55, 0.55) if not heavy else _rng.randf_range(-PI, PI)
		var max_spd: float = (52.0 if wet else 68.0) if heavy else (34.0 if wet else 52.0)
		var spd: float = _rng.randf_range(18.0, max_spd)
		m.pos = at + Vector2(_rng.randf_range(-4.5, 4.5), _rng.randf_range(-2.5, 2.5))
		m.vel = flow_dir.rotated(spread) * spd
		m.z_h = _rng.randf_range(0.5, 3.0)
		m.z_vel = _rng.randf_range(14.0, 34.0 if heavy else (22.0 if wet else 26.0))
		m.grav = 115.0 if wet else 64.0
		m.drag = 3.8 if wet else 2.6
		m.stick = wet
		m.bounce = 0.0 if wet else 0.14
		m.life = _rng.randf_range(0.30, 0.56) if wet else _rng.randf_range(0.38, 0.72)
		m.phase = _rng.randf() * TAU
		m.col = pal[_rng.randi() % pal.size()]
		m.size_px = Vector2(2.0, 1.0) if (i < 2 and not wet and _rng.randf() < 0.55) else Vector2.ONE
		_push_mote(m)


func _spawn_water_droplets(at: Vector2, flow_dir: Vector2, count: int, pal: Array[Color], unlit_flag: bool) -> void:
	for i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.WATER_DROP
		var spread: float = _rng.randf_range(-0.72, 0.72)
		var spd: float = _rng.randf_range(22.0, 62.0)
		m.pos = at + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-2.0, 2.0))
		m.vel = flow_dir.rotated(spread) * spd
		m.z_h = _rng.randf_range(1.5, 4.5)
		m.z_vel = _rng.randf_range(34.0, 66.0)
		m.grav = 158.0
		m.drag = 1.6
		m.life = _rng.randf_range(0.28, 0.52)
		m.col = pal[_rng.randi() % pal.size()]
		m.size_px = Vector2(2.0, 1.0) if (i % 3 == 0) else Vector2.ONE
		m.unlit = unlit_flag
		_push_mote(m)


func _spawn_sparks(at: Vector2, out_dir: Vector2, count: int, min_spd: float, max_spd: float, crystal_tint: bool) -> void:
	for i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.SPARK_HOT
		var spread: float = _rng.randf_range(-0.78, 0.78)
		var spd: float = _rng.randf_range(min_spd, max_spd)
		m.pos = at + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.0, 1.0))
		m.vel = out_dir.rotated(spread) * spd
		m.z_h = _rng.randf_range(3.0, 9.0)
		m.z_vel = _rng.randf_range(20.0, 54.0)
		m.grav = 148.0
		m.drag = 2.4
		m.bounce = 0.34
		m.life = _rng.randf_range(0.26, 0.44) if not crystal_tint else _rng.randf_range(0.32, 0.52)
		m.unlit = true
		m.trail = true
		if crystal_tint:
			m.col = Color("fffaf0") if i % 2 == 0 else Color("d0f6ff")
			m.col_end = Color("e6c468") if i % 2 == 0 else Color("b494f6")
		else:
			m.col = Color("fffaf0")
			m.col_end = Color("ff8030") if i % 2 == 0 else Color("ffd458")
		m.size_px = Vector2(2.0, 1.0) if (i == 0) else Vector2.ONE
		_push_mote(m)


func _spawn_chips(at: Vector2, out_dir: Vector2, count: int, pal: Array[Color], min_spd: float, max_spd: float) -> void:
	for i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.STONE_CHIP
		var spread: float = _rng.randf_range(-0.85, 0.85)
		m.pos = at + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-2.0, 2.0))
		m.vel = out_dir.rotated(spread) * _rng.randf_range(min_spd, max_spd)
		m.z_h = _rng.randf_range(2.0, 6.0)
		m.z_vel = _rng.randf_range(26.0, 56.0)
		m.grav = 195.0
		m.drag = 2.0
		m.bounce = 0.30
		m.life = _rng.randf_range(0.34, 0.62)
		m.col = pal[_rng.randi() % pal.size()]
		m.size_px = Vector2(2.0, 1.0) if (i % 2 == 0) else Vector2.ONE
		_push_mote(m)


func _spawn_splinters(at: Vector2, out_dir: Vector2, count: int, pal: Array[Color], min_spd: float, max_spd: float) -> void:
	for i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.WOOD_SPLINTER
		var spread: float = _rng.randf_range(-0.80, 0.80)
		m.pos = at + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 1.0))
		m.vel = out_dir.rotated(spread) * _rng.randf_range(min_spd, max_spd)
		m.z_h = _rng.randf_range(4.0, 10.0)
		m.z_vel = _rng.randf_range(22.0, 48.0)
		m.grav = 135.0
		m.drag = 2.2
		m.bounce = 0.22
		m.life = _rng.randf_range(0.38, 0.68)
		m.col = pal[_rng.randi() % pal.size()]
		m.size_px = Vector2(3.0, 1.0) if (i == 0) else Vector2(2.0, 1.0)
		_push_mote(m)


func _spawn_mud_or_humus(at: Vector2, flow_dir: Vector2, count: int, pal: Array[Color], heavy: bool, sticky_mud: bool) -> void:
	for i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.MUD_SPLAT
		var spread: float = _rng.randf_range(-0.75, 0.75) if not heavy else _rng.randf_range(-PI, PI)
		m.pos = at + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-2.0, 2.0))
		m.vel = flow_dir.rotated(spread) * _rng.randf_range(16.0, 52.0 if heavy else 36.0)
		m.z_h = _rng.randf_range(1.0, 3.5)
		m.z_vel = _rng.randf_range(20.0, 46.0 if heavy else 32.0)
		m.grav = 185.0 if sticky_mud else 145.0
		m.drag = 2.6
		m.stick = true
		m.life = _rng.randf_range(0.36, 0.64)
		m.col = pal[_rng.randi() % pal.size()]
		m.size_px = Vector2(2.0, 1.0) if (sticky_mud and i % 2 == 0) else Vector2.ONE
		_push_mote(m)


func _spawn_dust(at: Vector2, flow_dir: Vector2, count: int, pal: Array[Color], min_spd: float, max_spd: float) -> void:
	for _i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.DUST_WISP
		var spread: float = _rng.randf_range(-0.85, 0.85)
		m.pos = at + Vector2(_rng.randf_range(-4.5, 4.5), _rng.randf_range(-2.5, 2.5))
		m.vel = flow_dir.rotated(spread) * _rng.randf_range(min_spd, max_spd)
		m.z_h = _rng.randf_range(1.0, 4.5)
		m.z_vel = _rng.randf_range(8.0, 18.0)
		m.grav = 20.0
		m.drag = 3.6
		m.life = _rng.randf_range(0.38, 0.68)
		m.col = pal[_rng.randi() % pal.size()]
		m.size_px = Vector2.ONE
		_push_mote(m)


func _spawn_glints(at: Vector2, flow_dir: Vector2, count: int, pal: Array[Color], min_spd: float, max_spd: float) -> void:
	for _i: int in count:
		var m: SlashMote = SlashMote.new()
		m.kind = MoteKind.GLINT_UNLIT
		var spread: float = _rng.randf_range(-0.85, 0.85)
		m.pos = at + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-2.0, 2.0))
		m.vel = flow_dir.rotated(spread) * _rng.randf_range(min_spd, max_spd)
		m.z_h = _rng.randf_range(2.0, 7.0)
		m.z_vel = _rng.randf_range(18.0, 42.0)
		m.grav = 72.0
		m.drag = 2.8
		m.life = _rng.randf_range(0.32, 0.62)
		m.col = pal[_rng.randi() % pal.size()]
		m.col_end = m.col
		m.size_px = Vector2.ONE
		m.unlit = true
		_push_mote(m)


func _push_mote(m: SlashMote) -> void:
	last_spawn_count += 1
	if not last_mote_kinds.has(m.kind):
		last_mote_kinds.append(m.kind)
	if m.unlit:
		if _unlit_motes.size() >= MAX_UNLIT_MOTES:
			_unlit_motes.pop_front()
		_unlit_motes.append(m)
	else:
		if _lit_motes.size() >= MAX_MOTES:
			_lit_motes.pop_front()
		_lit_motes.append(m)


func _record_material(mat: String) -> void:
	if not last_materials.has(mat):
		last_materials.append(mat)


func _play_contact_sfx(id: String, pos: Vector2, db: float, pitch_spread: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now < _sfx_cd_msec:
		return
	_sfx_cd_msec = now + 110
	Sfx.at(self, id, pos, db, pitch_spread)


# ==============================================================================
# 4. SIMULATION & CRISP WHOLE-PIXEL RENDERING
# ==============================================================================

func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	var wind_v: Vector2 = WorldWind.sample(global_position) * 22.0
	_step_list(_lit_motes, dt, wind_v)
	_step_list(_unlit_motes, dt, wind_v)

	queue_redraw()
	if _unlit_layer != null:
		_unlit_layer.queue_redraw()

	if _lit_motes.is_empty() and _unlit_motes.is_empty():
		set_process(false)


func _step_list(list: Array[SlashMote], dt: float, wind_v: Vector2) -> void:
	var i: int = list.size() - 1
	while i >= 0:
		var m: SlashMote = list[i]
		m.age += dt
		if m.age >= m.life:
			list.remove_at(i)
			i -= 1
			continue

		if m.flutter:
			m.vel = m.vel.lerp(wind_v, minf(1.0, dt * m.drag))
		elif m.kind == MoteKind.SAND_GRAIN or m.kind == MoteKind.DUST_WISP or m.kind == MoteKind.GRASS_SNIPPET:
			m.vel = m.vel.lerp(wind_v * 0.75, minf(1.0, dt * m.drag))
		else:
			m.vel = m.vel.move_toward(Vector2.ZERO, m.vel.length() * minf(1.0, dt * m.drag))

		m.pos += m.vel * dt
		m.z_vel -= m.grav * dt
		m.z_h += m.z_vel * dt

		if m.z_h <= 0.0:
			m.z_h = 0.0
			if m.kind == MoteKind.WATER_DROP:
				# Droplets disappear smoothly upon hitting water/ground
				list.remove_at(i)
				i -= 1
				continue
			if m.bounce > 0.0 and m.z_vel < -22.0:
				m.z_vel = -m.z_vel * m.bounce
				m.vel *= 0.62
			else:
				m.z_vel = 0.0
				m.vel = Vector2.ZERO if m.stick else (m.vel * 0.55)
		i -= 1


func _draw() -> void:
	_draw_motes(self, false)


func _draw_motes(canvas: CanvasItem, draw_unlit: bool) -> void:
	var list: Array[SlashMote] = _unlit_motes if draw_unlit else _lit_motes
	for m: SlashMote in list:
		var t: float = clampf(m.age / maxf(m.life, 0.01), 0.0, 1.0)
		var fade_start: float = 0.45 if draw_unlit else 0.55
		var alpha: float = clampf(1.0 - maxf(0.0, (t - fade_start) / (1.0 - fade_start)), 0.0, 1.0)
		if alpha <= 0.02:
			continue

		var drift_x: float = sin(m.age * 8.5 + m.phase) * 1.6 if (m.flutter and m.z_h > 0.25) else 0.0
		var p: Vector2 = Vector2(roundf(m.pos.x + drift_x), roundf(m.pos.y - m.z_h))

		if m.kind == MoteKind.SPARK_HOT:
			var c: Color = m.col.lerp(m.col_end, clampf(t * 1.35, 0.0, 1.0))
			c.a = alpha
			canvas.draw_rect(Rect2(p, m.size_px), c)
			# Crisp 1-px hot directional spark tail opposite velocity while fast!
			if m.trail and m.vel.length_squared() > 400.0:
				var tail_step: Vector2 = -m.vel.normalized().round()
				var tc: Color = m.col_end
				tc.a = alpha * 0.72
				canvas.draw_rect(Rect2(p + tail_step, Vector2.ONE), tc)
		elif m.flutter:
			var c: Color = m.col
			c.a = alpha * 0.94
			var flat: bool = m.z_h <= 0.25 or (int(m.age * 8.0 + m.phase) % 2 == 0)
			canvas.draw_rect(Rect2(p, Vector2(2.0, 1.0) if flat else Vector2(1.0, 2.0)), c)
		elif m.kind == MoteKind.DUST_WISP:
			var c: Color = m.col
			c.a = alpha * 0.72
			canvas.draw_rect(Rect2(p, m.size_px), c)
		else:
			var c: Color = m.col
			c.a = alpha * (0.95 if draw_unlit else 0.92)
			canvas.draw_rect(Rect2(p, m.size_px), c)
