class_name LivingTree
extends Interactable
## LivingTree 2.0 — Next-gen botanical, physical & ecological pixel-art tree organism:
## - Hierarchical Split-Canopy & Scaffold Rig (`RootSkirt` z -9, `TrunkBase` + progressive `KerfNotch`,
##   `TrunkUpper` + `HarvestAmber`, 1..6 independent `CanopyClusters` + `*Glow`, optional `ForegroundOverhang`)
## - 3-frequency GPU wind (`canopy_cluster.gdshader` at true world branch anchors -> traveling gust waves,
##   cellular breathing & 12 Hz integer-pixel leaf-fan rustle at 0.00 ms idle GDScript CPU cost!)
## - Damped harmonic oscillator per cluster for physical impulses (axe chops, perched birds, sword slashes, walk-through saplings)
## - 7 true 1:1 pixel-density ontogenetic life stages (`s0` Acorn -> `s1` Whip -> `s2` Sapling -> `s3` Pole -> `s4` Mature
##   -> `s5` Ancient Matriarch -> `s6_log` Nurse Log) + true `coppice` (`Stockausschlag`) sprouting out of felled stumps!
## - Stand ecology via `Jobs.run()`: real **Crown Shyness** (`shy_left` / `shy_right` sky channels) & Forest vs. Solitary form
## - Multi-stage forestry felling physics: directional kerf wedge, 0.42s hinge-wood fiber creak, nonlinear rotational drag
##   equation (canopy billows upward!), restitution ground bounce, `LivingGrass` trunk-crush & rolled loot along fallen shaft
## - Multi-lobe `DaylightField` *Komorebi* light islands + cluster-synced `SunShadows` & `WaterReflections`
## - Selective per-cluster canopy peeling + Bayer 4x4 pixel-dither iris (trunk base stays 100% solid!)
## - Hydrological canopy interception, wet bark `stemflow` & 60s post-rain `CanopyDripLine` droplets
## - Ecological sockets (`RoofPerch` weight-dip, `Dendrotelm` woodland bees, `TreeRootSeat` mossy rest hollow)
## - Subtle nocturnal "Ellie = Shadowspore" mycorrhizal root bio-resonance & Waystone consecration healing!

const CANOPY_SHADER: Shader = preload("res://assets/shaders/canopy_cluster.gdshader")
const CANOPY_GLOW_SHADER: Shader = preload("res://assets/shaders/canopy_cluster_glow.gdshader")
const TRUNK_SHADER: Shader = preload("res://assets/shaders/tree_trunk.gdshader")
const DROP_SCENE: PackedScene = preload("res://src/entities/drops/item_drop.tscn")

const PEEL_ALPHA: float = 0.68
const FALL_MAX_ANGLE: float = 1.46
const HINGE_CREAK_SEC: float = 0.40
const SETTLE_HOLD_SEC: float = 1.45
const POST_RAIN_DRIP_SEC: float = 55.0

class ClusterNode:
	var sprite: Sprite2D = null
	var glow: Sprite2D = null
	var blossom_sprite: Sprite2D = null
	var blossom_glow: Sprite2D = null
	var fruit_sprite: Sprite2D = null
	var mat: ShaderMaterial = null
	var glow_mat: ShaderMaterial = null
	var role: String = ""
	var side: float = 0.0
	var anchor_px: Vector2 = Vector2.ZERO
	var base_pos: Vector2 = Vector2.ZERO
	var stiffness: float = 1.0
	var disp: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var peel_cur: float = 1.0
	var peel_target: float = 1.0
	var iris_cur: float = 0.0
	var lobe: Vector4 = Vector4.ZERO


class TreeMote:
	var kind: int = 0 ## 0=tumbling leaf, 1=wood/bark chip, 2=rain drip, 3=ground ripple, 4=bee, 5=spore spark, 6=blossom petal
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 0.0
	var z_vel: float = 0.0
	var age: float = 0.0
	var life: float = 1.8
	var phase: float = 0.0
	var col_a: Color = Color("55985f")
	var col_b: Color = Color("a8dc8c")


class MoteCanvas:
	extends Node2D
	var motes: Array[TreeMote] = []

	func _draw() -> void:
		for m: TreeMote in motes:
			var rem: float = clampf((m.life - m.age) / maxf(m.life * 0.28, 0.05), 0.0, 1.0)
			var fade_in: float = clampf(m.age * 7.0, 0.0, 1.0)
			var a: float = rem * fade_in
			if a <= 0.02:
				continue
			var p: Vector2 = Vector2(roundf(m.pos.x), roundf(m.pos.y - m.z_h))
			if m.kind == 0: ## Tumbling 2x3 lobed oak leaf (flips flat <-> edge in air!)
				var spin: float = sin(m.age * 6.8 + m.phase)
				var c1: Color = m.col_a
				var c2: Color = m.col_b
				c1.a = a
				c2.a = a * 0.85
				if absf(spin) > 0.42:
					draw_rect(Rect2(p, Vector2(2.0, 1.0)), c1)
					draw_rect(Rect2(p + Vector2(1.0, -1.0 if spin > 0.0 else 1.0), Vector2.ONE), c2)
				else:
					draw_rect(Rect2(p, Vector2(1.0, 2.0)), c2)
			elif m.kind == 1: ## Flying two-tone oak sapwood/bark splinter
				var c_chip: Color = m.col_a if int(m.age * 16.0) % 2 == 0 else m.col_b
				c_chip.a = a
				draw_rect(Rect2(p, Vector2(2.0, 1.0)), c_chip)
			elif m.kind == 2: ## Post-rain canopy drip droplet
				var c_drop: Color = Color(0.76, 0.92, 1.0, a * 0.85)
				draw_rect(Rect2(p, Vector2(1.0, 2.0)), c_drop)
			elif m.kind == 3: ## Concentric 1px drip splash ring on ground/puddle
				var r_px: float = roundf(lerpf(1.0, 4.0, clampf(m.age / maxf(m.life, 0.05), 0.0, 1.0)))
				var c_ring: Color = Color(0.78, 0.94, 1.0, a * 0.50)
				draw_rect(Rect2(p + Vector2(-r_px, 0.0), Vector2(1.0, 1.0)), c_ring)
				draw_rect(Rect2(p + Vector2(r_px, 0.0), Vector2(1.0, 1.0)), c_ring)
				draw_rect(Rect2(p + Vector2(0.0, -roundf(r_px * 0.6)), Vector2(1.0, 1.0)), c_ring)
				draw_rect(Rect2(p + Vector2(0.0, roundf(r_px * 0.6)), Vector2(1.0, 1.0)), c_ring)
			elif m.kind == 4: ## Tiny 4px golden woodland bee hovering near hollow
				var c_body: Color = Color("d89e3c")
				var c_stripe: Color = Color("281b26")
				var c_wing: Color = Color(0.92, 0.97, 1.0, 0.78 * a)
				c_body.a = a
				c_stripe.a = a
				draw_rect(Rect2(p, Vector2(2.0, 1.0)), c_body)
				draw_rect(Rect2(p + Vector2(1.0, 0.0), Vector2(1.0, 1.0)), c_stripe)
				if int(m.age * 28.0) % 2 == 0:
					draw_rect(Rect2(p + Vector2(0.0, -1.0), Vector2(2.0, 1.0)), c_wing)
			elif m.kind == 5: ## Subtle silver-teal Shadowspore mycorrhizal spark
				var c_sp: Color = m.col_a
				c_sp.a = a * 0.82
				draw_rect(Rect2(p, Vector2.ONE), c_sp)
			elif m.kind == 6: ## Drifting pink-white apple blossom petal (*Blütenschnee*)
				var p_flutter: float = sin(m.age * 5.2 + m.phase)
				var cp1: Color = m.col_a
				var cp2: Color = m.col_b
				cp1.a = a * 0.95
				cp2.a = a * 0.88
				draw_rect(Rect2(p, Vector2(2.0, 1.0) if absf(p_flutter) > 0.38 else Vector2(1.0, 2.0)), cp1)
				if p_flutter > 0.15:
					draw_rect(Rect2(p + Vector2(1.0, 1.0), Vector2.ONE), cp2)


@export var species_id: String = "valley_oak"
@export var stage: int = 4 ## 0..6
@export var arch_variant: int = -1 ## -1 = deterministic per-seed archetype, 0="s4", 1="s4_b", 2="s4_c"
@export var phenology_mode: int = -1 ## -1 = species default, 0 = summer foliage, 1 = full spring blossom, 2 = ripe fruit load
@export var trait_overrides: Dictionary = {} ## Optional explicit trait indices: {"moss": 0, "ivy": -1, "hollow": 1, "fungi": 0, "sprig": 1, "amber": 1}
@export var autumn_shift: float = 0.0 ## 0..1 altitude/microclimate bronze-gold phenology
@export var corruption: float = 0.0 ## 0..1 void ash crust near unsealed rifts
@export var allow_veteran_chop: bool = false ## Stage 5 matriarch protected unless enabled / master axe

var cell: Vector2i = Vector2i.ZERO
var level: Variant = null
var state: Dictionary = {} ## Replicated delta state: {"s": stage, "hp": hits_left, "n": notch_dir, "f": felled_day, "c": coppice, "p": picked_day}

## Stand ecology & individual trait identity (computed deterministically or via `Jobs.run()`):
var shy_left_px: float = 0.0
var shy_right_px: float = 0.0
var stand_shade: float = 0.0 ## 0 = open solitary pasture form, 1 = tall forest-stand form
var flip_tree: bool = false
var active_rig_key: String = ""
var rolled_traits: Dictionary = {}

var _tree_seed: int = 0
var _crown_tint: Color = Color.WHITE
var _species: Dictionary = {}
var _rig_all: Dictionary = {}
var _rig: Dictionary = {}
var _stage_cfg: Dictionary = {}

var _frame_w: float = 196.0
var _frame_h: float = 200.0
var _feet_x: float = 98.0
var _feet_y: float = 180.0
var _cut_y: float = 167.0
var _height_px: float = 164.0
var _clear_px: float = 52.0
var _trunk_half_px: float = 11.0
var _crown_half_px: float = 78.0
var _wind_exposure: float = 1.0

var _root_skirt: Sprite2D = null
var _trunk_base: Sprite2D = null
var _upper_pivot: Node2D = null ## Hinged at `(0, -(feet_y - cut_y))` so standing -> toppling is 100% seamless!
var _trunk_upper: Sprite2D = null
var _trunk_glow: Sprite2D = null
var _trait_sprites: Array[Sprite2D] = []
var _trait_glows: Array[Sprite2D] = []
var _harvest_overlay: Sprite2D = null
var _harvest_glow: Sprite2D = null
var _kerf_overlay: Sprite2D = null
var _overhang_sprite: Sprite2D = null
var _base_trunk_mat: ShaderMaterial = null
var _upper_trunk_mat: ShaderMaterial = null
var _mote_canvas: MoteCanvas = null
var _night_light: NightLight = null
var _root_seat: TreeRootSeat = null
var _notifier: VisibleOnScreenNotifier2D = null

var _clusters: Array[ClusterNode] = []
var _perches: Array[RoofPerch] = []
var _perch_cluster_idx: PackedInt32Array = PackedInt32Array()
var _perch_occupied: PackedByteArray = PackedByteArray()

@onready var _body_shape: CollisionShape2D = $Body/Shape
@onready var _hurtbox: HarvestHurtbox = $Hurtbox
@onready var _hurt_shape: CollisionShape2D = $Hurtbox/Shape

## Live physical & ecological simulation clocks:
var _on_screen: bool = true
var _falling: bool = false
var _fall_phase: int = 0 ## 0=creak, 1=accelerate, 2=bounce/settle, 3=fade
var _fall_dir: float = 1.0
var _fall_t: float = 0.0
var _fall_angle: float = 0.0
var _fall_vel: float = 0.0
var _trunk_sway_angle: float = 0.0
var _trunk_sway_vel: float = 0.0

var _canopy_wetness: float = 0.0 ## 0..1 hydrological interception reservoir
var _wetness_sent: float = 0.0 ## last wetness pushed to the materials
var _post_rain_timer: float = 0.0
var _drip_wait: float = 0.4
var _leaf_drift_wait: float = 2.2
var _bee_wait: float = 0.6
var _cover_wait: float = 0.0
var _perch_wait: float = 0.25
var _actor_flex_prev: Dictionary = {} ## instance_id -> Vector2 (walk-through whip bend & sword gusts)
var _actor_swing_prev: Dictionary = {} ## instance_id -> bool

## "Ellie = Shadowspore" nocturnal bio-resonance & Waystone consecration healing:
var _resonance: float = 0.0
var _still_night_sec: float = 0.0
var _resonance_spark_wait: float = 0.0
var _heal_flash: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Telemetry counters (read by `GrassLab` / `test_living_tree` QA):
var last_felled_grass_crush: float = 0.0
var total_axe_hits_taken: int = 0
var resonance_triggered: bool = false


func setup_tree(pos_px: Vector2, p_stage: int = 4, p_seed: int = 0, p_species: String = "valley_oak") -> void:
	position = pos_px.round()
	species_id = p_species
	stage = clampi(p_stage, 0, 6)
	cell = Vector2i((position / 16.0).floor())
	var eff_seed: int = p_seed if p_seed != 0 else hash([int(position.x), int(position.y), 7717])
	_tree_seed = eff_seed
	_rng.seed = eff_seed
	flip_tree = (_rng.randi() % 2) == 1


func configure_traits(p_arch: int = -1, p_traits: Dictionary = {}, p_flip: int = -1, p_phenology: int = -2) -> void:
	arch_variant = p_arch
	trait_overrides = p_traits.duplicate(true)
	if p_flip >= 0:
		flip_tree = (p_flip > 0)
	if p_phenology >= -1:
		phenology_mode = p_phenology
	if is_inside_tree():
		_rebuild_rig()


func _effective_phenology() -> int:
	if state.has("ph"):
		return int(state["ph"])
	if phenology_mode >= 0:
		return phenology_mode
	return int(_species.get("default_phenology", 0))


func set_phenology_mode(p_mode: int) -> void:
	phenology_mode = clampi(p_mode, 0, 2)
	state["ph"] = phenology_mode
	_sync_phenology_visuals()
	_apply_crown_shyness_offsets()
	set_night(TimeManager.night_amount())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("living_trees")
	add_to_group("day_canopies")
	add_to_group("night_lights")
	if _tree_seed == 0:
		_tree_seed = hash([int(global_position.x), int(global_position.y), 7717])
	if _rng.seed == 0:
		_rng.seed = _tree_seed
	if is_instance_valid(WorldWind.current):
		_wind_exposure = WorldWind.current.exposure(global_position)
	_hurtbox.harvest_target = self
	if not TimeManager.day_started.is_connected(_on_day_started):
		TimeManager.day_started.connect(_on_day_started)
	_load_species_data()
	if state.is_empty():
		_init_fresh_state()
	_rebuild_rig()
	set_night(TimeManager.night_amount())


func _load_species_data() -> void:
	_species = DataRegistry.get_entry("trees", species_id)
	var rig_name: String = String(_species.get("rig", "valley_oak_rig"))
	_rig_all = DataRegistry.table(rig_name)


func _init_fresh_state() -> void:
	var st_cfg: Dictionary = (_species.get("stages", {}) as Dictionary).get(str(stage), {}) as Dictionary
	var max_hp: int = int(st_cfg.get("hits", 4))
	state = {
		"s": stage,
		"hp": max_hp,
		"n": 0,
		"f": 0,
		"c": 0,
		"p": 0,
		"d": TimeManager.day,
	}


## Thread-safe batch computation of **Crown Shyness** (`shy_left_px`, `shy_right_px`) and **Stand Shade** via `Jobs.run()`.
## Pure value arrays inside the worker -> 100% compliant with `GEMINI.md` multithreading rules!
static func compute_stand_ecology_async(trees: Array[LivingTree], on_complete: Callable = Callable()) -> Jobs.Job:
	var positions: PackedVector2Array = PackedVector2Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	for t: LivingTree in trees:
		if is_instance_valid(t):
			positions.append(t.global_position if t.is_inside_tree() else t.position)
			radii.append(t.crown_radius())
		else:
			positions.append(Vector2.INF)
			radii.append(0.0)
	var count: int = positions.size()
	var work: Callable = func() -> PackedVector3Array:
		var out: PackedVector3Array = PackedVector3Array()
		out.resize(count)
		for i: int in count:
			var pi: Vector2 = positions[i]
			var ri: float = radii[i]
			if not pi.is_finite() or ri <= 8.0:
				out[i] = Vector3.ZERO
				continue
			var shy_l: float = 0.0
			var shy_r: float = 0.0
			var shade_acc: float = 0.0
			for j: int in count:
				if i == j:
					continue
				var pj: Vector2 = positions[j]
				var rj: float = radii[j]
				if not pj.is_finite() or rj <= 8.0:
					continue
				var delta_v: Vector2 = pj - pi
				var dist: float = Vector2(delta_v.x, delta_v.y * 1.32).length()
				var touch_dist: float = ri + rj + 14.0
				if dist < touch_dist and dist > 1.0:
					var overlap: float = clampf((touch_dist - dist) / 28.0, 0.0, 1.0)
					var push_px: float = maxf(1.0, roundf(overlap * 6.0))
					if delta_v.x < -2.0:
						shy_l = maxf(shy_l, push_px)
					elif delta_v.x > 2.0:
						shy_r = maxf(shy_r, push_px)
					shade_acc += overlap * 0.55
			out[i] = Vector3(shy_l, shy_r, clampf(shade_acc, 0.0, 1.0))
		return out
	var done: Callable = func(res_v: Variant) -> void:
		if res_v is PackedVector3Array:
			var res: PackedVector3Array = res_v
			for i: int in mini(trees.size(), res.size()):
				var t: LivingTree = trees[i]
				if is_instance_valid(t):
					var v: Vector3 = res[i]
					t.apply_stand_ecology(v.x, v.y, v.z)
		if on_complete.is_valid():
			on_complete.call()
	return Jobs.run(work, done, Jobs.Prio.HIGH)


func apply_stand_ecology(left_shy_px: float, right_shy_px: float, p_stand_shade: float) -> void:
	shy_left_px = clampf(left_shy_px, 0.0, 8.0)
	shy_right_px = clampf(right_shy_px, 0.0, 8.0)
	stand_shade = clampf(p_stand_shade, 0.0, 1.0)
	_apply_crown_shyness_offsets()


func crown_radius() -> float:
	return _crown_half_px


func trunk_radius() -> float:
	return _trunk_half_px


func is_depleted() -> bool:
	return int(state.get("f", 0)) > 0


func is_done() -> bool:
	return not is_depleted() and not _falling and stage >= 3


func is_falling() -> bool:
	return _falling


func spec() -> Dictionary:
	if _stage_cfg.is_empty():
		return _species
	var choppable: bool = bool(_stage_cfg.get("choppable", false)) or (allow_veteran_chop and bool(_stage_cfg.get("veteran_landmark", false)))
	var tool_name: String = "axe" if choppable else ("sickle" if bool(_stage_cfg.get("sickle_cut", false)) else "")
	var out: Dictionary = {
		"harvest": {"tool": tool_name, "hits": int(_stage_cfg.get("hits", 4))},
	}
	if _has_ripe_pickup():
		out["pickup"] = _species.get("pickup", {})
	return out


func _rig_key_for_state() -> String:
	if is_depleted():
		if int(state.get("c", 0)) >= 1 and _rig_all.has("coppice"):
			return "coppice"
		return str(_stage_cfg.get("id", "s4"))
	stage = clampi(int(state.get("s", stage)), 0, 6)
	var stages_dict: Dictionary = _species.get("stages", {}) as Dictionary
	_stage_cfg = stages_dict.get(str(stage), stages_dict.get("4", {})) as Dictionary
	return String(_stage_cfg.get("id", "s4"))


func _clear_rig_nodes() -> void:
	for p: RoofPerch in _perches:
		if is_instance_valid(p):
			p.queue_free()
	_perches.clear()
	_perch_cluster_idx.clear()
	_perch_occupied.clear()
	_clusters.clear()
	_trait_sprites.clear()
	_trait_glows.clear()
	for child: Node in [_root_skirt, _trunk_base, _upper_pivot, _overhang_sprite, _mote_canvas, _night_light, _root_seat, _notifier]:
		if child != null and is_instance_valid(child):
			child.queue_free()
	_root_skirt = null
	_trunk_base = null
	_upper_pivot = null
	_trunk_upper = null
	_trunk_glow = null
	_harvest_overlay = null
	_harvest_glow = null
	_kerf_overlay = null
	_overhang_sprite = null
	_base_trunk_mat = null
	_upper_trunk_mat = null
	_mote_canvas = null
	_night_light = null
	_root_seat = null
	_notifier = null


func _trait_cols(traits_def: Dictionary, key: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if not traits_def.has(key):
		return out
	var raw: Variant = traits_def[key]
	if raw is Array:
		var arr: Array = raw as Array
		for v: Variant in arr:
			out.append(int(v))
	elif raw is int or raw is float:
		out.append(int(raw))
	return out


func _select_rig_key(coppice_active: bool, rig_rng: RandomNumberGenerator) -> String:
	if coppice_active:
		return "coppice"
	var base_key: String = String(_stage_cfg.get("id", "s4"))
	if stage == 4 and not is_depleted():
		var candidates: Array[String] = []
		for cand: String in ["s4", "s4_b", "s4_c"]:
			if _rig_all.has(cand):
				candidates.append(cand)
		if not candidates.is_empty():
			var idx: int = clampi(arch_variant, 0, candidates.size() - 1) if arch_variant >= 0 else (rig_rng.randi() % candidates.size())
			return candidates[idx]
	return base_key


func _roll_traits_for_rig(traits_def: Dictionary, rig_rng: RandomNumberGenerator) -> Dictionary:
	var out: Dictionary = {}
	var probs: Dictionary = {
		"moss": 0.86 if stage >= 5 else (0.58 if stage == 4 else (0.42 if stage == 3 else 0.0)),
		"ivy": 0.56 if stage >= 5 else (0.34 if stage == 4 else (0.20 if stage == 3 else 0.0)),
		"hollow": 0.88 if stage >= 5 else (0.40 if stage == 4 else (0.16 if stage == 3 else 0.0)),
		"fungi": 0.58 if stage >= 5 else (0.36 if stage == 4 else (0.14 if stage == 3 else 0.0)),
		"sprig": 0.54 if stage >= 5 else (0.48 if stage == 4 else (0.52 if stage == 3 else 0.0)),
	}
	for t_key: String in ["moss", "ivy", "hollow", "fungi", "sprig"]:
		var cols: PackedInt32Array = _trait_cols(traits_def, t_key)
		if cols.is_empty():
			out[t_key] = -1
			continue
		if trait_overrides.has(t_key):
			var ov: int = int(trait_overrides[t_key])
			out[t_key] = clampi(ov, 0, cols.size() - 1) if (ov >= 0 and cols[clampi(ov, 0, cols.size() - 1)] >= 0) else -1
			continue
		var pr: float = float(probs.get(t_key, 0.0))
		if pr > 0.0 and rig_rng.randf() < pr:
			var pick: int = rig_rng.randi() % cols.size()
			out[t_key] = pick if cols[pick] >= 0 else -1
		else:
			out[t_key] = -1

	# Keep Stage 3/4 trunks natural & un-cluttered (at most 2 upper props unless explicitly overridden!)
	if stage <= 4:
		var active_upper: Array[String] = []
		for uk: String in ["ivy", "hollow", "fungi", "sprig"]:
			if int(out.get(uk, -1)) >= 0 and not trait_overrides.has(uk):
				active_upper.append(uk)
		while active_upper.size() > 2:
			var drop_i: int = rig_rng.randi() % active_upper.size()
			out[active_upper[drop_i]] = -1
			active_upper.remove_at(drop_i)

	if trait_overrides.has("amber"):
		out["amber"] = 1 if int(trait_overrides["amber"]) > 0 else 0
	elif bool(_stage_cfg.get("has_pickup", false)):
		out["amber"] = 1 if (stage >= 5 or _tree_seed == 404 or rig_rng.randf() < 0.68) else 0
	else:
		out["amber"] = 0
	return out


func _rebuild_rig() -> void:
	_clear_rig_nodes()
	stage = clampi(int(state.get("s", stage)), 0, 6)
	var stages_dict: Dictionary = _species.get("stages", {}) as Dictionary
	_stage_cfg = stages_dict.get(str(stage), stages_dict.get("4", {})) as Dictionary
	var felled: bool = is_depleted()
	var coppice_active: bool = felled and int(state.get("c", 0)) >= 1 and _rig_all.has("coppice")

	var rig_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rig_rng.seed = hash([_tree_seed, stage, 9137])
	var rkey: String = _select_rig_key(coppice_active, rig_rng)
	active_rig_key = rkey
	_rig = _rig_all.get(rkey, {}) as Dictionary
	if _rig.is_empty():
		_rig = _rig_all.get(String(_stage_cfg.get("id", "s4")), {}) as Dictionary
	if _rig.is_empty():
		# Graceful fallback if art assets are still generating
		_setup_colliders(felled)
		return

	var traits_def: Dictionary = _rig.get("traits", {}) as Dictionary
	rolled_traits = _roll_traits_for_rig(traits_def, rig_rng)
	_crown_tint = Color(
		rig_rng.randf_range(0.96, 1.04),
		rig_rng.randf_range(0.96, 1.04),
		rig_rng.randf_range(0.96, 1.04),
		1.0
	)

	_frame_w = float(_rig.get("frame_w", 196))
	_frame_h = float(_rig.get("frame_h", 200))
	_feet_x = float(_rig.get("feet_x", _frame_w * 0.5))
	_feet_y = float(_rig.get("feet_y", _frame_h - 20.0))
	_cut_y = float(_rig.get("cut_y", _feet_y - 13.0))
	_height_px = float(_rig.get("height_px", 164.0))
	_clear_px = float(_rig.get("clear_px", 52.0))
	_trunk_half_px = float(_rig.get("trunk_half_px", 10.0))
	_crown_half_px = float(_rig.get("crown_half_px", 72.0))

	var sheet_tex: Texture2D = DataRegistry.tex(String(_rig.get("sheet", "")))
	var glow_path: String = String(_rig.get("glow_sheet", ""))
	var glow_tex: Texture2D = DataRegistry.tex(glow_path) if not glow_path.is_empty() else null
	if sheet_tex == null:
		_setup_colliders(felled)
		return

	var num_cols: int = maxi(1, int(_rig.get("num_cols", 1)))
	var glow_cols: int = maxi(1, int(_rig.get("glow_cols", 1)))
	var layers: Dictionary = _rig.get("layers", {}) as Dictionary
	var glow_layers: Dictionary = _rig.get("glow_layers", {}) as Dictionary
	var base_offset: Vector2 = Vector2(-_feet_x, -_feet_y)

	_base_trunk_mat = ShaderMaterial.new()
	_base_trunk_mat.shader = TRUNK_SHADER
	_base_trunk_mat.set_shader_parameter("frame_size", Vector2(_frame_w, _frame_h))
	_base_trunk_mat.set_shader_parameter("corruption", corruption)

	_upper_trunk_mat = ShaderMaterial.new()
	_upper_trunk_mat.shader = TRUNK_SHADER
	_upper_trunk_mat.set_shader_parameter("frame_size", Vector2(_frame_w, _frame_h))
	_upper_trunk_mat.set_shader_parameter("corruption", corruption)

	# 1. RootSkirt (z -9: sits seamlessly under LivingGrass tips, blends buttress roots & moss into soil)
	var skirt_col: int = int(layers.get("root_skirt", -1))
	if skirt_col >= 0 and skirt_col < num_cols:
		_root_skirt = _make_layer_sprite("RootSkirt", sheet_tex, num_cols, skirt_col, base_offset)
		_root_skirt.z_as_relative = false
		_root_skirt.z_index = -9
		_root_skirt.material = _base_trunk_mat
		add_child(_root_skirt)

	# 2. TrunkBase (remains standing as natural mossy heartwood-ringed stump when felled; never dithered!)
	var tbase_col: int = int(layers.get("trunk_base", -1))
	if tbase_col >= 0 and tbase_col < num_cols:
		_trunk_base = _make_layer_sprite("TrunkBase", sheet_tex, num_cols, tbase_col, base_offset)
		_trunk_base.material = _base_trunk_mat
		add_child(_trunk_base)

	# 3. Hinged Upper Tree (`_upper_pivot` sits right at the felling hinge `(0, -(feet_y - cut_y))`!)
	var hinge_h: float = maxf(0.0, _feet_y - _cut_y)
	_upper_pivot = Node2D.new()
	_upper_pivot.name = "UpperPivot"
	_upper_pivot.position = Vector2(0.0, -hinge_h)
	add_child(_upper_pivot)
	var upper_offset: Vector2 = Vector2(-_feet_x, -_feet_y + hinge_h)

	if not felled or coppice_active:
		var tupper_col: int = int(layers.get("trunk_upper", -1))
		if tupper_col >= 0 and tupper_col < num_cols:
			_trunk_upper = _make_layer_sprite("TrunkUpper", sheet_tex, num_cols, tupper_col, upper_offset)
			_trunk_upper.material = _upper_trunk_mat
			_upper_pivot.add_child(_trunk_upper)

		if glow_tex != null and int(glow_layers.get("trunk_glow", -1)) >= 0:
			var tg_col: int = int(glow_layers.get("trunk_glow", 0))
			if tg_col < glow_cols:
				_trunk_glow = _make_layer_sprite("TrunkGlow", glow_tex, glow_cols, tg_col, upper_offset)
				_trunk_glow.material = Unlit.material()
				_trunk_glow.visible = TimeManager.night_amount() > 0.02
				_upper_pivot.add_child(_trunk_glow)

		# 3b. Modular Per-Tree Trait Overlays (`moss`, `ivy`, `hollow`, `fungi`, `sprig`)
		for t_key: String in ["moss", "ivy", "hollow", "fungi", "sprig"]:
			var t_idx: int = int(rolled_traits.get(t_key, -1))
			if t_idx < 0:
				continue
			var t_cols: PackedInt32Array = _trait_cols(traits_def, t_key)
			if t_idx >= t_cols.size():
				continue
			var sheet_col: int = t_cols[t_idx]
			if sheet_col < 0 or sheet_col >= num_cols:
				continue
			var tsp: Sprite2D = _make_layer_sprite("Trait_%s" % t_key, sheet_tex, num_cols, sheet_col, upper_offset)
			tsp.material = _upper_trunk_mat
			_upper_pivot.add_child(tsp)
			_trait_sprites.append(tsp)
			var g_cols: PackedInt32Array = _trait_cols(traits_def, "%s_glow" % t_key)
			if glow_tex != null and t_idx < g_cols.size():
				var g_col: int = g_cols[t_idx]
				if g_col >= 0 and g_col < glow_cols:
					var tglow: Sprite2D = _make_layer_sprite("TraitGlow_%s" % t_key, glow_tex, glow_cols, g_col, upper_offset)
					tglow.material = Unlit.material()
					tglow.visible = TimeManager.night_amount() > 0.02
					tsp.add_child(tglow)
					_trait_glows.append(tglow)

		# Regenerative Alchemy Bark Harvest overlay (`oak_amber`)
		var harv_col: int = int(layers.get("harvest_amber", -1))
		if harv_col >= 0 and harv_col < num_cols and int(rolled_traits.get("amber", 1)) > 0:
			_harvest_overlay = _make_layer_sprite("HarvestAmber", sheet_tex, num_cols, harv_col, upper_offset)
			_harvest_overlay.material = _upper_trunk_mat
			_harvest_overlay.visible = _has_ripe_pickup()
			_upper_pivot.add_child(_harvest_overlay)
			if glow_tex != null and int(glow_layers.get("harvest_glow", -1)) >= 0:
				var hg_col: int = int(glow_layers.get("harvest_glow", 1))
				if hg_col < glow_cols:
					_harvest_glow = _make_layer_sprite("HarvestGlow", glow_tex, glow_cols, hg_col, upper_offset)
					_harvest_glow.material = Unlit.material()
					_harvest_glow.visible = _harvest_overlay.visible and TimeManager.night_amount() > 0.02
					_harvest_overlay.add_child(_harvest_glow)

		# Progressive Axe Kerf Wedge Overlay
		var kerf1_col: int = int(layers.get("kerf_1", -1))
		if kerf1_col >= 0 and kerf1_col < num_cols:
			_kerf_overlay = _make_layer_sprite("KerfNotch", sheet_tex, num_cols, kerf1_col, upper_offset)
			_kerf_overlay.material = _upper_trunk_mat
			_kerf_overlay.visible = false
			_upper_pivot.add_child(_kerf_overlay)
			_sync_kerf_visual(layers, num_cols)

		# 4. Split Canopy Clusters (1..6 independent GPU-wind + spring-physics bough clouds + optional Blossom/Fruit phenology!)
		var raw_clusters: Array = _rig.get("clusters", []) as Array
		var glow_c_start: int = int(glow_layers.get("cluster_glow_start", -1))
		var pheno_def: Dictionary = _rig.get("phenology", {}) as Dictionary
		var blossom_cols: PackedInt32Array = _trait_cols(pheno_def, "blossom_cols")
		var fruit_cols: PackedInt32Array = _trait_cols(pheno_def, "fruit_cols")
		var blossom_glow_start: int = int(pheno_def.get("blossom_glow_start", -1))
		for c_idx: int in raw_clusters.size():
			var c_info: Dictionary = raw_clusters[c_idx] as Dictionary
			var c_col: int = int(c_info.get("col", -1))
			if c_col < 0 or c_col >= num_cols:
				continue
			var cn: ClusterNode = ClusterNode.new()
			cn.role = String(c_info.get("role", "cluster"))
			var raw_side: float = float(c_info.get("side", 0.0))
			cn.side = -raw_side if flip_tree else raw_side
			var anc_arr: Array = c_info.get("anchor", [_feet_x, _feet_y - _clear_px]) as Array
			var ax: float = float(anc_arr[0])
			var ay: float = float(anc_arr[1])
			cn.anchor_px = Vector2((_frame_w - ax) if flip_tree else ax, ay)
			cn.stiffness = float(c_info.get("stiffness", 1.0))
			var flutter_amt: float = float(c_info.get("flutter", 0.42))
			var phase_val: float = float(c_info.get("phase", float(c_idx) * 1.17)) + fposmod(global_position.x * 0.031 + global_position.y * 0.017, TAU)
			var world_anc: Vector2 = global_position + Vector2(cn.anchor_px.x - _feet_x, cn.anchor_px.y - _feet_y)

			cn.mat = ShaderMaterial.new()
			cn.mat.shader = CANOPY_SHADER
			cn.mat.set_shader_parameter("frame_size", Vector2(_frame_w, _frame_h))
			cn.mat.set_shader_parameter("anchor_px", Vector2(ax, ay))
			cn.mat.set_shader_parameter("world_anchor", world_anc)
			cn.mat.set_shader_parameter("stiffness", cn.stiffness)
			cn.mat.set_shader_parameter("flutter", flutter_amt)
			cn.mat.set_shader_parameter("phase_seed", phase_val)
			cn.mat.set_shader_parameter("wind_exposure", _wind_exposure * float(_species.get("sway_gain", 1.0)))
			cn.mat.set_shader_parameter("autumn_shift", autumn_shift)
			cn.mat.set_shader_parameter("autumn_hue", float(_species.get("autumn_hue", 0.0)))
			cn.mat.set_shader_parameter("corruption", corruption)
			cn.mat.set_shader_parameter("upper_occlude", 0.48 if c_idx == 0 else (0.24 if c_idx <= 2 else 0.0))

			cn.sprite = _make_layer_sprite("CanopyCluster_%d" % c_idx, sheet_tex, num_cols, c_col, upper_offset)
			cn.sprite.material = cn.mat
			cn.sprite.modulate = _crown_tint
			_upper_pivot.add_child(cn.sprite)

			if c_idx < blossom_cols.size() and blossom_cols[c_idx] >= 0 and blossom_cols[c_idx] < num_cols:
				cn.blossom_sprite = _make_layer_sprite("Blossom_%d" % c_idx, sheet_tex, num_cols, blossom_cols[c_idx], upper_offset)
				cn.blossom_sprite.material = cn.mat
				cn.sprite.add_child(cn.blossom_sprite)
				if glow_tex != null and blossom_glow_start >= 0 and (blossom_glow_start + c_idx) < glow_cols:
					var bg_mat: ShaderMaterial = ShaderMaterial.new()
					bg_mat.shader = CANOPY_GLOW_SHADER
					bg_mat.set_shader_parameter("frame_size", Vector2(_frame_w, _frame_h))
					bg_mat.set_shader_parameter("anchor_px", Vector2(ax, ay))
					bg_mat.set_shader_parameter("world_anchor", world_anc)
					bg_mat.set_shader_parameter("stiffness", cn.stiffness)
					bg_mat.set_shader_parameter("flutter", flutter_amt)
					bg_mat.set_shader_parameter("phase_seed", phase_val)
					bg_mat.set_shader_parameter("wind_exposure", _wind_exposure * float(_species.get("sway_gain", 1.0)))
					cn.blossom_glow = _make_layer_sprite("BlossomGlow_%d" % c_idx, glow_tex, glow_cols, blossom_glow_start + c_idx, upper_offset)
					cn.blossom_glow.material = bg_mat
					cn.blossom_glow.visible = false
					cn.blossom_sprite.add_child(cn.blossom_glow)

			if c_idx < fruit_cols.size() and fruit_cols[c_idx] >= 0 and fruit_cols[c_idx] < num_cols:
				cn.fruit_sprite = _make_layer_sprite("Fruit_%d" % c_idx, sheet_tex, num_cols, fruit_cols[c_idx], upper_offset)
				cn.fruit_sprite.material = cn.mat
				cn.sprite.add_child(cn.fruit_sprite)

			if glow_tex != null and glow_c_start >= 0 and (glow_c_start + c_idx) < glow_cols:
				cn.glow_mat = ShaderMaterial.new()
				cn.glow_mat.shader = CANOPY_GLOW_SHADER
				cn.glow_mat.set_shader_parameter("frame_size", Vector2(_frame_w, _frame_h))
				cn.glow_mat.set_shader_parameter("anchor_px", Vector2(ax, ay))
				cn.glow_mat.set_shader_parameter("world_anchor", world_anc)
				cn.glow_mat.set_shader_parameter("stiffness", cn.stiffness)
				cn.glow_mat.set_shader_parameter("flutter", flutter_amt)
				cn.glow_mat.set_shader_parameter("phase_seed", phase_val)
				cn.glow_mat.set_shader_parameter("wind_exposure", _wind_exposure * float(_species.get("sway_gain", 1.0)))

				cn.glow = _make_layer_sprite("ClusterGlow_%d" % c_idx, glow_tex, glow_cols, glow_c_start + c_idx, upper_offset)
				cn.glow.material = cn.glow_mat
				cn.glow.visible = TimeManager.night_amount() > 0.02
				cn.sprite.add_child(cn.glow)

			var lobe_arr: Array = c_info.get("lobe", [0.0, 0.0, _crown_half_px * 0.7, _crown_half_px * 0.45]) as Array
			var lx: float = -float(lobe_arr[0]) if flip_tree else float(lobe_arr[0])
			cn.lobe = Vector4(lx, float(lobe_arr[1]), float(lobe_arr[2]), float(lobe_arr[3]))
			_clusters.append(cn)

		# 5. Optional High Foreground Canopy Frame (`overhang` on Stage 5 Ancient Matriarchs)
		var over_col: int = int(layers.get("overhang", -1))
		if over_col >= 0 and over_col < num_cols:
			_overhang_sprite = _make_layer_sprite("CanopyOverhang", sheet_tex, num_cols, over_col, base_offset)
			_overhang_sprite.z_as_relative = false
			_overhang_sprite.z_index = 18
			_overhang_sprite.modulate = Color(0.86, 0.92, 0.96, 0.88)
			if not _clusters.is_empty():
				_overhang_sprite.material = _clusters[_clusters.size() - 1].mat
			add_child(_overhang_sprite)

		# 6. Ecological Sockets: Bird Perches (`RoofPerch`), Mossy Root Seat (`TreeRootSeat`), NightLight & Fireflies
		var perch_list: Array = _rig.get("perches", []) as Array
		for p_raw: Variant in perch_list:
			var pa: Array = p_raw as Array
			if pa.size() < 3:
				continue
			var pdx: float = -float(pa[0]) if flip_tree else float(pa[0])
			var ph: float = float(pa[1])
			var pc_idx: int = clampi(int(pa[2]), 0, maxi(0, _clusters.size() - 1))
			var perch: RoofPerch = RoofPerch.new()
			perch.host = self
			perch.position = Vector2(pdx, 1.0)
			perch.perch_height = ph
			add_child(perch)
			_perches.append(perch)
			_perch_cluster_idx.append(pc_idx)
			_perch_occupied.append(0)

		if bool(_stage_cfg.get("has_rest_seat", false)) and _rig.has("rest_seat"):
			var rs_arr: Array = _rig.get("rest_seat", [28.0, 4.0]) as Array
			if rs_arr.size() >= 2:
				var rdx: float = -float(rs_arr[0]) if flip_tree else float(rs_arr[0])
				_root_seat = TreeRootSeat.new()
				_root_seat.name = "RootRestSeat"
				_root_seat.host_tree = self
				_root_seat.custom_label = String(_species.get("seat_prompt", ""))
				_root_seat.position = Vector2(rdx, float(rs_arr[1]))
				add_child(_root_seat)

		if stage >= 3:
			if bool(_species.get("fireflies", true)):
				add_to_group("flora_glow")
			_night_light = NightLight.new()
			_night_light.radius = int(clampf(_trunk_half_px * 2.6, 24.0, 42.0))
			_night_light.squash = 0.56
			_night_light.base_energy = float(_species.get("light_energy", 0.09)) * (1.15 if stage >= 5 else 1.0)
			_night_light.glow_color = Color(String(_species.get("light_color", "#5ce8dc")))
			_night_light.pulse = 0.14
			_night_light.position = Vector2(0.0, -4.0)
			add_child(_night_light)

	_mote_canvas = MoteCanvas.new()
	_mote_canvas.name = "TreeMotes"
	_mote_canvas.z_as_relative = false
	_mote_canvas.z_index = 4
	add_child(_mote_canvas)

	_notifier = VisibleOnScreenNotifier2D.new()
	var nw: float = (_crown_half_px + 32.0) * 2.0
	var nh: float = _height_px + 48.0
	_notifier.rect = Rect2(-nw * 0.5, -_height_px - 24.0, nw, nh)
	_notifier.screen_entered.connect(func() -> void:
		_on_screen = true
		set_process(true))
	_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(_notifier)

	_sync_phenology_visuals()
	_apply_crown_shyness_offsets()
	_setup_colliders(felled)
	set_night(TimeManager.night_amount())


func _sync_phenology_visuals() -> void:
	var eff_ph: int = _effective_phenology()
	var ripe_fruit: bool = (eff_ph == 2) and _has_ripe_pickup()
	if eff_ph == 1 and not is_depleted() and stage >= 2:
		add_to_group("blossom_trees")
	elif is_in_group("blossom_trees"):
		remove_from_group("blossom_trees")
	for cn: ClusterNode in _clusters:
		if cn.blossom_sprite != null:
			cn.blossom_sprite.visible = (eff_ph == 1)
		if cn.fruit_sprite != null:
			cn.fruit_sprite.visible = ripe_fruit


func _make_layer_sprite(s_name: String, tex: Texture2D, h_cols: int, frame_col: int, off: Vector2) -> Sprite2D:
	var sp: Sprite2D = Sprite2D.new()
	sp.name = s_name
	sp.texture = tex
	sp.hframes = h_cols
	sp.vframes = 1
	sp.frame = frame_col
	sp.centered = false
	sp.flip_h = flip_tree
	sp.offset = off
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sp


func _apply_crown_shyness_offsets() -> void:
	var stand_lift: float = roundf(stand_shade * 4.0) if stage >= 3 else 0.0
	var has_fruit_load: bool = (_effective_phenology() == 2) and _has_ripe_pickup() and stage >= 3 and (_rig.get("phenology", {}) as Dictionary).has("fruit_cols")
	for cn: ClusterNode in _clusters:
		var x_push: float = 0.0
		if cn.side < -0.15 and shy_left_px > 0.0:
			x_push = shy_left_px * absf(cn.side) ## Retract left cluster inward away from left neighbor!
		elif cn.side > 0.15 and shy_right_px > 0.0:
			x_push = -shy_right_px * absf(cn.side) ## Retract right cluster inward away from right neighbor!
		var fruit_droop: float = 2.0 if (has_fruit_load and absf(cn.side) > 0.25) else 0.0
		cn.base_pos = Vector2(roundf(x_push), -stand_lift + fruit_droop)
		if cn.sprite != null:
			cn.sprite.position = cn.base_pos + cn.disp.round()


func _setup_colliders(felled: bool) -> void:
	var flex_only: bool = bool(_stage_cfg.get("walk_through_flex", false))
	var nurse_log: bool = bool(_stage_cfg.get("nurse_log", false))
	if felled or flex_only:
		_body_shape.set_deferred("disabled", true)
	else:
		_body_shape.set_deferred("disabled", false)
		var rshape: RectangleShape2D = RectangleShape2D.new()
		if nurse_log:
			rshape.size = Vector2(92.0, 12.0)
			_body_shape.position = Vector2(0.0, -5.0)
		else:
			rshape.size = Vector2(_trunk_half_px * 2.0 + 2.0, 7.0)
			_body_shape.position = Vector2(0.0, -3.5)
		_body_shape.shape = rshape

	var can_hit: bool = not felled and (bool(_stage_cfg.get("choppable", false)) or bool(_stage_cfg.get("sickle_cut", false)) or (allow_veteran_chop and bool(_stage_cfg.get("veteran_landmark", false))))
	_hurtbox.set_deferred("monitorable", can_hit)
	var cshape: CircleShape2D = CircleShape2D.new()
	cshape.radius = maxf(10.0, _trunk_half_px + 6.0)
	_hurt_shape.shape = cshape
	_hurt_shape.position = Vector2(0.0, -8.0)


func _sync_kerf_visual(layers: Dictionary, num_cols: int) -> void:
	if _kerf_overlay == null:
		return
	var max_hp: int = maxi(1, int(_stage_cfg.get("hits", 4)))
	var cur_hp: int = int(state.get("hp", max_hp))
	var dmg_ratio: float = 1.0 - float(cur_hp) / float(max_hp)
	if dmg_ratio <= 0.05:
		_kerf_overlay.visible = false
		return
	var k1: int = int(layers.get("kerf_1", -1))
	var k2: int = int(layers.get("kerf_2", k1))
	_kerf_overlay.frame = k2 if (dmg_ratio >= 0.48 and k2 >= 0 and k2 < num_cols) else k1
	var notch_side: int = int(state.get("n", 1))
	# Base kerf art is drawn on the right side of the unflipped trunk; tuck 4 px inward so the wedge bites cleanly into the bark!
	_kerf_overlay.flip_h = (notch_side < 0)
	_kerf_overlay.position = Vector2(-float(notch_side) * 4.0, 0.0)
	_kerf_overlay.visible = true


## DayNight callback (`night_lights` group): hides all glow layers by day (`0` daytime drawcalls!).
func set_night(amount: float) -> void:
	var show_glow: bool = amount > 0.02 and not is_depleted() and not _falling
	var base_a: float = clampf(amount * 0.92 + _resonance * 0.45, 0.0, 1.0)
	if _trunk_glow != null:
		_trunk_glow.visible = show_glow
		_trunk_glow.modulate.a = base_a
	for tg: Sprite2D in _trait_glows:
		if is_instance_valid(tg):
			tg.visible = show_glow
			tg.modulate.a = clampf(amount * 0.90 + _resonance * 0.25, 0.0, 1.0)
	if _harvest_glow != null:
		_harvest_glow.visible = show_glow and _has_ripe_pickup()
		_harvest_glow.modulate.a = clampf(amount * 0.95, 0.0, 1.0)
	for cn: ClusterNode in _clusters:
		if cn.glow != null:
			cn.glow.visible = show_glow
			cn.glow.modulate.a = clampf(amount * 0.85, 0.0, 1.0)
		if cn.blossom_glow != null:
			cn.blossom_glow.visible = show_glow and (_effective_phenology() == 1)
			cn.blossom_glow.modulate.a = clampf(amount * 0.80, 0.0, 1.0)


func set_autumn_shift(val: float) -> void:
	autumn_shift = clampf(val, 0.0, 1.0)
	for cn: ClusterNode in _clusters:
		if cn.mat != null:
			cn.mat.set_shader_parameter("autumn_shift", autumn_shift)


func set_corruption(val: float) -> void:
	corruption = clampf(val, 0.0, 1.0)
	for tm: ShaderMaterial in [_base_trunk_mat, _upper_trunk_mat]:
		if tm != null:
			tm.set_shader_parameter("corruption", corruption)
	for cn: ClusterNode in _clusters:
		if cn.mat != null:
			cn.mat.set_shader_parameter("corruption", corruption)


## Triggered when a nearby WaystoneStatue or Town Light-Post consecrates the land!
func consecrate_heal() -> void:
	set_corruption(0.0)
	_heal_flash = 1.0
	_impulse_all_clusters(Vector2(0.0, -2.2), 16.0)
	_spawn_leaf_burst(10)
	set_process(true)


## Multi-lobe canopy projection for `DaylightField` -> creates genuine breathing *Komorebi* light gaps between boughs!
func day_canopy_lobes() -> PackedVector4Array:
	var out: PackedVector4Array = PackedVector4Array()
	if is_depleted() or _falling or stage < 2:
		return out
	var sun_shift: Vector2 = Vector2(_height_px * 0.20, _height_px * 0.09)
	for cn: ClusterNode in _clusters:
		var c: Vector2 = global_position + sun_shift + Vector2(cn.lobe.x + cn.base_pos.x, cn.lobe.y)
		out.append(Vector4(c.x, c.y, maxf(8.0, cn.lobe.z), maxf(6.0, cn.lobe.w)))
	return out


func day_canopy() -> Vector4:
	if is_depleted() or _falling or stage < 2:
		return Vector4.ZERO
	var center: Vector2 = global_position + Vector2(_height_px * 0.20, _height_px * 0.09)
	return Vector4(center.x, center.y, maxf(8.0, _crown_half_px * 1.02), maxf(6.0, _crown_half_px * 0.60))


# ---------------- INTERACTABLE (REGENERATIVE ALCHEMY BARK HARVEST) ----------------

func _active_pickup_cfg() -> Dictionary:
	if _effective_phenology() == 1 and _species.has("blossom_pickup"):
		return _species.get("blossom_pickup", {}) as Dictionary
	return _species.get("pickup", {}) as Dictionary


func _has_ripe_pickup() -> bool:
	if is_depleted() or _falling or not bool(_stage_cfg.get("has_pickup", false)):
		return false
	var has_pheno_rig: bool = (_rig.get("phenology", {}) as Dictionary).has("fruit_cols")
	if has_pheno_rig:
		if _effective_phenology() <= 0:
			return false
	elif int(rolled_traits.get("amber", 1)) <= 0:
		return false
	var picked_day: int = int(state.get("p", 0))
	if picked_day <= 0:
		return true
	var regrow_d: int = int(_active_pickup_cfg().get("regrow_days", 3))
	return (TimeManager.day - (picked_day - 1)) >= regrow_d


func prompt() -> String:
	if InputManager.ui_blocking or not _has_ripe_pickup():
		return ""
	return String(_active_pickup_cfg().get("prompt", "WUNDHARZ ERNTEN"))


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, from.distance_to(global_position + Vector2(0.0, -5.0)) - (_trunk_half_px + 8.0))


func prompt_position() -> Vector2:
	return Vector2(0.0, -minf(_clear_px + 8.0, 56.0))


func interact(player: Player) -> void:
	if player == null or not _has_ripe_pickup():
		return
	var toward: Vector2 = global_position - player.global_position
	var face_dir: Vector2 = toward.normalized() if toward.length() > 1.0 else player.facing
	player.begin_pick(face_dir, func() -> void:
		if multiplayer.is_server():
			_server_pick_bark(player)
		else:
			_rpc_request_pick.rpc_id(1))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pick() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var who: Player = _find_player(sender)
	if who != null and reach_distance(who.global_position) <= INTERACT_RANGE + 8.0:
		_server_pick_bark(who)


func _server_pick_bark(who: Player = null) -> void:
	if not _has_ripe_pickup():
		return
	state["p"] = TimeManager.day + 1
	var p_cfg: Dictionary = _active_pickup_cfg()
	var drop_list: Array = p_cfg.get("drops", []) as Array
	var is_shake: bool = bool(p_cfg.get("shake_harvest", false))
	if is_shake and not _clusters.is_empty():
		# Tree-Shake Harvest: apples/blossoms tumble down from real outer bough cluster positions!
		for entry_v: Variant in drop_list:
			var entry: Dictionary = entry_v as Dictionary
			if _rng.randf() > float(entry.get("chance", 1.0)):
				continue
			var n: int = _rng.randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))
			for k: int in n:
				var cn: ClusterNode = _clusters[(k + 1) % _clusters.size()]
				var bx: float = clampf(cn.lobe.x + _rng.randf_range(-14.0, 14.0), -_crown_half_px * 0.85, _crown_half_px * 0.85)
				var by: float = _rng.randf_range(4.0, 16.0)
				var drop_pos: Vector2 = global_position + Vector2(bx, by)
				var launch_v: Vector2 = Vector2(signf(bx) * _rng.randf_range(12.0, 32.0), _rng.randf_range(6.0, 22.0))
				_server_spawn_drop(String(entry["id"]), 1, drop_pos, launch_v, _clear_px + 6.0)
		# Sacred Mistletoe (`ivy == 0` on `wild_apple`) yields a rare bonus mistletoe sprig when shaken!
		if species_id == "wild_apple" and int(rolled_traits.get("ivy", -1)) == 0 and _rng.randf() < 0.65:
			_server_spawn_drop("wild_mistletoe", 1, global_position + Vector2(0.0, 8.0), Vector2(_rng.randf_range(-18.0, 18.0), 18.0), _clear_px + 12.0)
	else:
		var out_dir: Vector2 = (who.global_position - global_position).normalized() if who != null else Vector2.DOWN
		_server_roll_drops(drop_list, global_position + Vector2(0.0, -14.0), out_dir * 42.0, 14.0)
	_broadcast_tree_state(state, "shake_pick" if is_shake else "pick", 0.0)


# ---------------- AXE CHOPPING & HOST-AUTHORITATIVE STATE ----------------

func harvest_hit(source: int) -> void:
	if not multiplayer.is_server() or is_depleted() or _falling:
		return
	var hitter: Player = _find_player(source)
	var held_tool: String = ""
	if hitter != null and hitter.inventory != null:
		held_tool = String(Items.definition(hitter.inventory.active_stack()).get("tool", ""))

	var hit_from_left: bool = hitter != null and hitter.global_position.x < global_position.x
	var push_dir: float = 1.0 if hit_from_left else -1.0 ## Tree leans & falls AWAY from the chopper!
	var notch_side: int = -1 if hit_from_left else 1     ## Kerf wedge opens ON the side struck by the axe!

	if bool(_stage_cfg.get("sickle_cut", false)) and held_tool == "sickle":
		state["f"] = TimeManager.day + 1
		state["c"] = 0
		_server_roll_drops(_stage_cfg.get("drops", []) as Array, global_position + Vector2(0.0, -8.0), Vector2(push_dir * 38.0, 6.0), 8.0)
		_broadcast_tree_state(state, "cut_whip", push_dir)
		return

	var choppable: bool = bool(_stage_cfg.get("choppable", false)) or (allow_veteran_chop and bool(_stage_cfg.get("veteran_landmark", false)))
	if not choppable or held_tool != "axe":
		_broadcast_tree_state(state, "rustle", push_dir)
		return

	var cur_hp: int = int(state.get("hp", int(_stage_cfg.get("hits", 4)))) - 1
	state["hp"] = maxi(0, cur_hp)
	state["n"] = notch_side

	if cur_hp > 0:
		if _stage_cfg.has("chip_drop"):
			var cd: Dictionary = _stage_cfg["chip_drop"] as Dictionary
			if _rng.randf() < float(cd.get("chance", 0.3)):
				_server_spawn_drop(String(cd["id"]), 1, global_position + Vector2(float(notch_side) * 8.0, -12.0), Vector2(float(notch_side) * 48.0, _rng.randf_range(-14.0, 18.0)), 12.0)
		_broadcast_tree_state(state, "axe_hit", push_dir)
	else:
		state["f"] = TimeManager.day + 1
		state["c"] = 0
		_broadcast_tree_state(state, "fell", push_dir)


## Direct test/script helper to apply a simulated axe strike from `from_world_pos` (host-only).
func strike_with_axe(from_world_pos: Vector2) -> void:
	if not multiplayer.is_server() or is_depleted() or _falling:
		return
	var hit_from_left: bool = from_world_pos.x < global_position.x
	var push_dir: float = 1.0 if hit_from_left else -1.0
	var notch_side: int = -1 if hit_from_left else 1
	var cur_hp: int = int(state.get("hp", int(_stage_cfg.get("hits", 4)))) - 1
	state["hp"] = maxi(0, cur_hp)
	state["n"] = notch_side
	if cur_hp > 0:
		_broadcast_tree_state(state, "axe_hit", push_dir)
	else:
		state["f"] = TimeManager.day + 1
		state["c"] = 0
		_broadcast_tree_state(state, "fell", push_dir)


## Sends `_rpc_sync_state` safely: when inside a `ZoneStage`, targets only clients that currently hold that zone
## (`ZoneDirector.peers_holding_zone`), avoiding "Node not found" RPC errors on distant clients.
func _broadcast_tree_state(new_state: Dictionary, fx: String, dir: float) -> void:
	var tree_parent: Node = get_parent()
	var stage_node: ZoneStage = (tree_parent.get_parent() as ZoneStage) if tree_parent != null else null
	if stage_node != null:
		_rpc_sync_state(new_state, fx, dir)
		if NetworkManager.rpc_ready(self) and stage_node.zone != null:
			var director: ZoneDirector = stage_node.get_parent() as ZoneDirector
			if director != null:
				for peer: int in director.peers_holding_zone(stage_node.zone.id):
					_rpc_sync_state.rpc_id(peer, new_state, fx, dir)
		return
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_sync_state.rpc(new_state, fx, dir)
	else:
		_rpc_sync_state(new_state, fx, dir)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_state(new_state: Dictionary, fx: String, dir: float) -> void:
	state = new_state.duplicate(true)
	match fx:
		"rustle":
			_impulse_all_clusters(Vector2(dir * 1.4, 0.5), 14.0)
			if _effective_phenology() == 1:
				_spawn_petal_burst(6)
			else:
				_spawn_leaf_burst(3)
			set_process(true)
		"pick":
			if _harvest_overlay != null:
				_harvest_overlay.visible = false
			if _harvest_glow != null:
				_harvest_glow.visible = false
			_sync_phenology_visuals()
			_apply_crown_shyness_offsets()
			_impulse_all_clusters(Vector2(0.0, 1.1), 10.0)
			Sfx.at(self, "pluck", global_position, -3.0)
			set_process(true)
		"shake_pick":
			_sync_phenology_visuals()
			_apply_crown_shyness_offsets()
			_trunk_sway_vel += 0.18
			_impulse_all_clusters(Vector2(0.0, -2.4), 22.0)
			if _effective_phenology() == 1:
				_spawn_petal_burst(18)
			else:
				_spawn_leaf_burst(8)
				for gnode: Node in get_tree().get_nodes_in_group("living_grass"):
					var lg: LivingGrass = gnode as LivingGrass
					if lg != null:
						lg.stamp_burst(global_position + Vector2(0.0, 10.0), _crown_half_px * 0.45, 0.55, 6.0)
			_scatter_perched_birds()
			Sfx.at(self, "pluck", global_position, -1.5)
			set_process(true)
		"axe_hit":
			total_axe_hits_taken += 1
			var layers: Dictionary = _rig.get("layers", {}) as Dictionary
			var num_cols: int = maxi(1, int(_rig.get("num_cols", 1)))
			_sync_kerf_visual(layers, num_cols)
			_trunk_sway_vel += dir * 0.24
			_impulse_all_clusters(Vector2(dir * 2.8, 1.2), 24.0)
			_spawn_wood_chips(-dir, 8)
			_spawn_leaf_burst(7)
			_scatter_perched_birds()
			Sfx.at(self, "axe_chop", global_position, -1.5, 0.06)
			set_process(true)
		"cut_whip":
			_spawn_leaf_burst(8)
			Sfx.at(self, "pluck", global_position, -2.0)
			_rebuild_rig()
		"fell":
			total_axe_hits_taken += 1
			_begin_felling(dir if absf(dir) > 0.1 else 1.0)
		"grow":
			_rebuild_rig()
			_impulse_all_clusters(Vector2(0.0, -1.8), 12.0)
			_spawn_leaf_burst(5)
			set_process(true)
		_:
			_rebuild_rig()


# ---------------- ONTOGENETIC GROWTH & COPPICE REGROWTH ----------------

func _on_day_started(day: int) -> void:
	# Re-show regrown bark resin or ripened orchard fruit if ready!
	if not is_depleted():
		var ripe: bool = _has_ripe_pickup()
		if _harvest_overlay != null:
			_harvest_overlay.visible = ripe
			if _harvest_glow != null:
				_harvest_glow.visible = ripe and TimeManager.night_amount() > 0.02
		_sync_phenology_visuals()
		_apply_crown_shyness_offsets()
		_sync_phenology_visuals()
		_apply_crown_shyness_offsets()

	if not multiplayer.is_server():
		return
	advance_growth_days(day - int(state.get("d", day)))


## Advances biological growth / coppice sprouting by `days_delta` (callable in `TreeLab` time-lapse!).
func advance_growth_days(days_delta: int = 1) -> void:
	if not multiplayer.is_server() or _falling or days_delta <= 0:
		return
	if is_depleted():
		# Felled oak stump -> vigorous Coppice (`Stockausschlag`) -> Sapling -> Pole -> Mature!
		var cur_c: int = int(state.get("c", 0))
		if cur_c == 0:
			state["c"] = 1
			state["d"] = TimeManager.day
			_broadcast_tree_state(state, "grow", 0.0)
		else:
			state["f"] = 0
			state["c"] = 0
			state["s"] = 1
			var s1_cfg: Dictionary = (_species.get("stages", {}) as Dictionary).get("1", {}) as Dictionary
			state["hp"] = int(s1_cfg.get("hits", 1))
			state["n"] = 0
			state["d"] = TimeManager.day
			_broadcast_tree_state(state, "grow", 0.0)
		return

	var grow_req: int = int(_stage_cfg.get("grow_days", 0))
	var next_st: int = int(_stage_cfg.get("next_stage", stage))
	if grow_req > 0 and next_st != stage:
		var elapsed_d: int = maxi(days_delta, TimeManager.day - int(state.get("d", TimeManager.day)))
		if elapsed_d >= grow_req or days_delta >= 1:
			state["s"] = next_st
			var nxt_cfg: Dictionary = (_species.get("stages", {}) as Dictionary).get(str(next_st), {}) as Dictionary
			state["hp"] = int(nxt_cfg.get("hits", 4))
			state["n"] = 0
			state["d"] = TimeManager.day
			_broadcast_tree_state(state, "grow", 0.0)


# ---------------- NONLINEAR FORESTRY FELLING PHYSICS ----------------

func _begin_felling(dir: float) -> void:
	if _falling:
		return
	_falling = true
	_fall_dir = signf(dir) if absf(dir) > 0.01 else 1.0
	_fall_phase = 0
	_fall_t = 0.0
	_fall_angle = 0.0
	_fall_vel = 0.0

	_body_shape.set_deferred("disabled", true)
	_hurtbox.set_deferred("monitorable", false)
	if _night_light != null:
		_night_light.visible = false
	if _overhang_sprite != null:
		_overhang_sprite.visible = false
	_scatter_perched_birds()
	_spawn_wood_chips(-_fall_dir, 14)
	_spawn_leaf_burst(16)
	Sfx.at(self, "tree_fall", global_position, 0.0, 0.03, 480.0)
	set_process(true)


func _step_felling(dt: float) -> void:
	if _upper_pivot == null:
		_finish_felling()
		return
	_fall_t += dt
	if _fall_phase == 0:
		# Phase 0 (0..0.40s): Hinge-wood fibers groan & tear; trunk trembles and leans slowly past balance
		var u: float = clampf(_fall_t / HINGE_CREAK_SEC, 0.0, 1.0)
		var tremor: float = sin(_fall_t * 52.0) * (1.0 - u) * 0.016
		_fall_angle = _fall_dir * (0.045 * u * u) + tremor
		_upper_pivot.rotation = _fall_angle
		if _fall_t >= HINGE_CREAK_SEC:
			_fall_phase = 1
			_fall_t = 0.0
			_fall_angle = _fall_dir * 0.045
			_fall_vel = _fall_dir * 0.22
			if _kerf_overlay != null:
				_kerf_overlay.visible = false
	elif _fall_phase == 1:
		# Phase 1: Nonlinear rotational differential equation with canopy aerodynamic drag!
		# alpha = (g_eff * sin(|theta|) - k_drag * omega^2) / L_eff
		var abs_a: float = maxf(absf(_fall_angle), 0.04)
		var l_eff: float = clampf(_height_px / 95.0, 0.75, 2.1)
		var drag_k: float = 0.14 + float(_clusters.size()) * 0.03
		var accel: float = (5.8 * sin(abs_a) - drag_k * _fall_vel * _fall_vel) / l_eff
		_fall_vel += _fall_dir * maxf(accel, 0.25) * dt
		_fall_angle += _fall_vel * dt
		_upper_pivot.rotation = _fall_angle

		# Aerodynamic canopy drag: leaf clusters billow upward/backward against rushing air!
		var drag_lift: float = clampf(absf(_fall_vel) * 1.6, 0.0, 5.0)
		for i: int in _clusters.size():
			var cn: ClusterNode = _clusters[i]
			if cn.sprite != null:
				cn.sprite.position = cn.base_pos + Vector2(-_fall_dir * drag_lift * (0.5 + 0.12 * float(i)), -drag_lift * 0.4).round()

		if absf(_fall_angle) >= FALL_MAX_ANGLE:
			_fall_angle = _fall_dir * FALL_MAX_ANGLE
			_upper_pivot.rotation = _fall_angle
			_on_felling_ground_impact()
			_fall_phase = 2
			_fall_t = 0.0
	elif _fall_phase == 2:
		# Phase 2: Heavy elastic ground restitution bounce + settle on crushed LivingGrass!
		var bounce: float = exp(-5.2 * _fall_t) * absf(sin(_fall_t * 11.5)) * 0.11
		_upper_pivot.rotation = _fall_dir * (FALL_MAX_ANGLE - bounce)
		for cn: ClusterNode in _clusters:
			if cn.sprite != null:
				cn.sprite.position = cn.sprite.position.lerp(cn.base_pos, clampf(dt * 8.0, 0.0, 1.0)).round()
		if _fall_t >= SETTLE_HOLD_SEC:
			_fall_phase = 3
			_fall_t = 0.0
	elif _fall_phase == 3:
		# Phase 3: Smoothly dissolve fallen upper crown while mossy heartwood stump stays untouched!
		var alpha: float = clampf(1.0 - _fall_t / 0.55, 0.0, 1.0)
		_upper_pivot.modulate.a = alpha
		if _fall_t >= 0.55:
			_finish_felling()


func _on_felling_ground_impact() -> void:
	var stump_world: Vector2 = global_position + Vector2(_fall_dir * 8.0, -2.0)
	var tip_world: Vector2 = global_position + Vector2(_fall_dir * _height_px * 0.92, 4.0)
	var crown_mid: Vector2 = global_position + Vector2(_fall_dir * _height_px * 0.68, 2.0)

	# Crush LivingGrass along the entire fallen oak shaft & broad canopy!
	last_felled_grass_crush = 0.0
	for gnode: Node in get_tree().get_nodes_in_group("living_grass"):
		var lg: LivingGrass = gnode as LivingGrass
		if lg != null:
			lg.stamp_segment(stump_world, tip_world, maxf(14.0, _trunk_half_px * 1.6), 1.0, 6.0, 14.0, 1.0)
			lg.stamp_burst(crown_mid, maxf(24.0, _crown_half_px * 0.52), 0.96, 9.5)
			last_felled_grass_crush = maxf(last_felled_grass_crush, lg.crush_at(crown_mid))

	# Camera impact shake scaled by tree height
	for player: Player in Player.all:
		if is_instance_valid(player) and player.global_position.distance_to(global_position) < 380.0:
			player.add_shake(clampf(_height_px / 34.0, 1.8, 5.2))

	# Dust, splinter & leaf impact cloud along the fallen crown
	_spawn_leaf_burst(24, Vector2(_fall_dir * _height_px * 0.62, -6.0))
	_spawn_wood_chips(_fall_dir, 10)

	# Host rolls logs, bark & acorns right along the fallen trunk axis!
	if multiplayer.is_server():
		var drops_cfg: Array = _stage_cfg.get("drops", []) as Array
		for d_raw: Variant in drops_cfg:
			var d: Dictionary = d_raw as Dictionary
			if _rng.randf() > float(d.get("chance", 1.0)):
				continue
			var cnt: int = _rng.randi_range(int(d.get("min", 1)), int(d.get("max", 1)))
			for k: int in cnt:
				var along: float = _rng.randf_range(0.22, 0.85)
				var spawn_at: Vector2 = global_position + Vector2(_fall_dir * _height_px * along, _rng.randf_range(-4.0, 6.0))
				var launch_v: Vector2 = Vector2(_fall_dir * _rng.randf_range(16.0, 44.0), _rng.randf_range(-28.0, 28.0))
				_server_spawn_drop(String(d["id"]), 1, spawn_at, launch_v, 10.0)


func _finish_felling() -> void:
	_falling = false
	_rebuild_rig()


# ---------------- LIVE FRAME SIMULATION (ZERO-COST IDLE WHEN STILL!) ----------------

func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	if _falling:
		_step_felling(dt)
		_step_motes(dt)
		return

	var has_active_springs: bool = _step_springs(dt)
	_step_hydrology_and_air(dt)
	_step_motes(dt)

	if _heal_flash > 0.0:
		_heal_flash = maxf(0.0, _heal_flash - dt * 1.4)
		for tm: ShaderMaterial in [_base_trunk_mat, _upper_trunk_mat]:
			if tm != null:
				tm.set_shader_parameter("heal_flash", _heal_flash)
		for cn: ClusterNode in _clusters:
			if cn.mat != null:
				cn.mat.set_shader_parameter("heal_flash", _heal_flash)

	var near_player: bool = _step_player_interactions(dt)
	_step_perch_contacts(dt)

	# Offscreen & completely calm -> sleep at 0.00 ms CPU (GPU handles 100% of wind!)
	if not _on_screen and not has_active_springs and _mote_canvas != null and _mote_canvas.motes.is_empty() and not near_player and _heal_flash <= 0.0:
		set_process(false)


func _step_springs(dt: float) -> bool:
	var moving: bool = false
	if absf(_trunk_sway_angle) > 0.0005 or absf(_trunk_sway_vel) > 0.0005:
		var k_t: float = 85.0 if stage >= 2 else 36.0
		var c_t: float = 9.5 if stage >= 2 else 5.2
		var acc_t: float = -k_t * _trunk_sway_angle - c_t * _trunk_sway_vel
		_trunk_sway_vel += acc_t * dt
		_trunk_sway_angle += _trunk_sway_vel * dt
		if _upper_pivot != null:
			_upper_pivot.rotation = clampf(_trunk_sway_angle, -0.22, 0.22)
		moving = true
	elif _upper_pivot != null and _upper_pivot.rotation != 0.0:
		_trunk_sway_angle = 0.0
		_trunk_sway_vel = 0.0
		_upper_pivot.rotation = 0.0

	for cn: ClusterNode in _clusters:
		if cn.disp.length_squared() > 0.01 or cn.vel.length_squared() > 0.02:
			var k_c: float = 54.0 * cn.stiffness
			var c_c: float = 7.4 * sqrt(maxf(cn.stiffness, 0.4))
			var acc: Vector2 = -k_c * cn.disp - c_c * cn.vel
			cn.vel += acc * dt
			cn.disp += cn.vel * dt
			if cn.sprite != null:
				cn.sprite.position = cn.base_pos + cn.disp.round()
			moving = true
		elif cn.sprite != null and cn.sprite.position != cn.base_pos:
			cn.disp = Vector2.ZERO
			cn.vel = Vector2.ZERO
			cn.sprite.position = cn.base_pos

		if absf(cn.peel_cur - cn.peel_target) > 0.008:
			cn.peel_cur = move_toward(cn.peel_cur, cn.peel_target, dt * 4.2)
			if cn.sprite != null:
				cn.sprite.modulate = Color(_crown_tint.r, _crown_tint.g, _crown_tint.b, cn.peel_cur)
			moving = true
	return moving


func _step_hydrology_and_air(dt: float) -> void:
	if is_depleted() or stage < 2 or not _on_screen:
		return
	var rain_now: float = WorldWind.current.rain if is_instance_valid(WorldWind.current) else 0.0
	if rain_now > 0.05:
		_canopy_wetness = move_toward(_canopy_wetness, 1.0, dt * 0.08 * (0.5 + rain_now))
		_post_rain_timer = POST_RAIN_DRIP_SEC
	else:
		_canopy_wetness = move_toward(_canopy_wetness, 0.0, dt * 0.022)
		_post_rain_timer = maxf(0.0, _post_rain_timer - dt)

	if absf(_canopy_wetness - _wetness_sent) > 0.002 or (_canopy_wetness == 0.0 and _wetness_sent != 0.0):
		_wetness_sent = _canopy_wetness ## a dry tree no longer pushes every cluster's material every frame (forests)
		for tm: ShaderMaterial in [_base_trunk_mat, _upper_trunk_mat]:
			if tm != null:
				tm.set_shader_parameter("stemflow", _canopy_wetness)
		for cn: ClusterNode in _clusters:
			if cn.mat != null:
				cn.mat.set_shader_parameter("rain_droop", _canopy_wetness)
			if cn.glow_mat != null:
				cn.glow_mat.set_shader_parameter("rain_droop", _canopy_wetness)

	# Canopy Drip-Line water droplets during & for 55s after rain!
	if (_canopy_wetness > 0.22 or _post_rain_timer > 0.0) and _mote_canvas != null and _mote_canvas.motes.size() < 28:
		_drip_wait -= dt
		if _drip_wait <= 0.0:
			_drip_wait = _rng.randf_range(0.22, 0.68) / maxf(_canopy_wetness, 0.35)
			var ang: float = _rng.randf() * TAU
			var drip_r: float = _crown_half_px * _rng.randf_range(0.75, 1.02)
			var ground_off: Vector2 = Vector2(cos(ang) * drip_r, sin(ang) * drip_r * 0.62)
			var m: TreeMote = TreeMote.new()
			m.kind = 2
			m.pos = ground_off
			m.z_h = _clear_px + _rng.randf_range(4.0, 22.0)
			m.z_vel = -92.0
			m.life = 1.2
			_mote_canvas.motes.append(m)

	# Ambient windborne tumbling leaf OR *Blütenschnee* apple-blossom petal along true WorldWind vector!
	var eff_ph: int = _effective_phenology()
	_leaf_drift_wait -= dt
	if _leaf_drift_wait <= 0.0:
		var gust: float = WorldWind.current.gust if is_instance_valid(WorldWind.current) else 0.25
		var rate_boost: float = 1.45 if eff_ph == 1 else 1.0
		_leaf_drift_wait = _rng.randf_range(1.4, 3.8) / (clampf(0.5 + gust * 0.6, 0.5, 2.6) * rate_boost)
		if rain_now < 0.45 and _mote_canvas != null and _mote_canvas.motes.size() < 28:
			if eff_ph == 1:
				_spawn_petal_burst(1 if gust < 0.55 else 2)
			else:
				_spawn_single_wind_leaf(Vector2.ZERO)

	# Daytime woodland & orchard honeybees (around tree hollows OR full-blossom crowns!)
	var has_hollow_trait: bool = int(rolled_traits.get("hollow", -1)) >= 0 or (stage == 5 and bool(_stage_cfg.get("has_hollow", false)) and not (_rig.get("traits", {}) as Dictionary).has("hollow"))
	var has_blossom_bees: bool = (eff_ph == 1 and stage >= 3)
	if (stage >= 4 and has_hollow_trait or has_blossom_bees) and TimeManager.night_amount() < 0.25 and rain_now < 0.15:
		_bee_wait -= dt
		if _bee_wait <= 0.0:
			_bee_wait = _rng.randf_range(0.85, 1.9) if has_blossom_bees else _rng.randf_range(1.1, 2.4)
			if _mote_canvas != null and _mote_canvas.motes.size() < 28:
				var bee: TreeMote = TreeMote.new()
				bee.kind = 4
				if has_blossom_bees:
					bee.pos = Vector2(_rng.randf_range(-_crown_half_px * 0.65, _crown_half_px * 0.65), _rng.randf_range(-6.0, 6.0))
					bee.z_h = _clear_px + _rng.randf_range(4.0, maxf(12.0, (_height_px - _clear_px) * 0.65))
				else:
					var h_arr: Array = _rig.get("hollow", []) as Array
					var h_dx: float = float(h_arr[0]) if h_arr.size() >= 2 else -3.0
					var h_dy: float = float(h_arr[1]) if h_arr.size() >= 2 else -48.0
					var hx: float = -h_dx if flip_tree else h_dx
					bee.pos = Vector2(hx + _rng.randf_range(-5.0, 5.0), 0.0)
					bee.z_h = absf(h_dy) + _rng.randf_range(-4.0, 5.0)
				bee.life = _rng.randf_range(2.0, 3.4)
				bee.phase = _rng.randf() * TAU
				_mote_canvas.motes.append(bee)


func _step_player_interactions(dt: float) -> bool:
	var any_near: bool = false
	var flex_whip: bool = bool(_stage_cfg.get("walk_through_flex", false))
	var night_amt: float = TimeManager.night_amount()
	var quiet_ellie_near: bool = false

	for p: Player in Player.all:
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		var pid: int = p.get_instance_id()
		var ppos: Vector2 = p.global_position
		var prev_p: Vector2 = _actor_flex_prev.get(pid, ppos) as Vector2
		_actor_flex_prev[pid] = ppos
		var d: float = ppos.distance_to(global_position)
		if d < 240.0:
			any_near = true

		# 1. Stage 0/1 Acorn Sprout & Whip: bends elastically out of Ellie's way as she walks through!
		if flex_whip and not is_depleted() and d < 18.0:
			var step_d: float = prev_p.distance_to(ppos)
			if step_d > 0.35:
				var push_x: float = signf(global_position.x - ppos.x)
				if absf(push_x) < 0.1:
					push_x = 1.0 if ppos.x >= prev_p.x else -1.0
				_trunk_sway_vel += push_x * clampf(step_d * 0.055, 0.05, 0.32)
				_impulse_all_clusters(Vector2(push_x * 2.0, 0.6), 12.0)

		# 2. Sword slash aerodynamic gust ruffling low boughs
		var swinging: bool = p.attack != null and p.attack.is_swinging()
		var was_sw: bool = bool(_actor_swing_prev.get(pid, false))
		_actor_swing_prev[pid] = swinging
		if swinging and not was_sw and d < _crown_half_px + 22.0 and stage >= 1 and not is_depleted():
			var aim_x: float = signf(p.attack.aim_dir.x) if absf(p.attack.aim_dir.x) > 0.1 else 1.0
			_impulse_all_clusters(Vector2(aim_x * 1.4, -0.5), 11.0)
			_spawn_leaf_burst(3)

		# 3. "Ellie = Shadowspore" subtle nocturnal mycorrhizal root bio-resonance!
		if stage >= 4 and not is_depleted() and night_amt > 0.35 and d < _trunk_half_px + 34.0 and prev_p.distance_to(ppos) < 0.25 and not swinging:
			quiet_ellie_near = true

	if quiet_ellie_near:
		_still_night_sec += dt
		if _still_night_sec >= 1.6:
			_resonance = move_toward(_resonance, 1.0, dt * 0.55)
			resonance_triggered = true
			_resonance_spark_wait -= dt
			if _resonance_spark_wait <= 0.0 and _mote_canvas != null and _mote_canvas.motes.size() < 28:
				_resonance_spark_wait = 0.65
				var sp: TreeMote = TreeMote.new()
				sp.kind = 5
				sp.pos = Vector2(_rng.randf_range(-_trunk_half_px * 1.5, _trunk_half_px * 1.5), _rng.randf_range(-4.0, 5.0))
				sp.z_h = 2.0
				sp.z_vel = _rng.randf_range(7.0, 13.0)
				sp.vel = Vector2(_rng.randf_range(-3.0, 3.0), 0.0)
				sp.life = 1.9
				sp.col_a = Color("78f4e6") if _rng.randf() < 0.65 else Color("cbaaff")
				_mote_canvas.motes.append(sp)
	else:
		_still_night_sec = maxf(0.0, _still_night_sec - dt * 2.0)
		_resonance = move_toward(_resonance, 0.0, dt * 0.65)

	if night_amt > 0.02 and _trunk_glow != null:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0032)
		_trunk_glow.modulate.a = clampf(night_amt * 0.88 + _resonance * (0.25 + 0.30 * pulse), 0.0, 1.0)

	# 4. Selective Per-Cluster Canopy Peeling + Bayer 4x4 Pixel-Dither Iris (12 Hz check)
	_cover_wait -= dt
	if _cover_wait <= 0.0 and stage >= 2 and not is_depleted():
		_cover_wait = 0.08
		_update_selective_cluster_peeling()

	return any_near


func _update_selective_cluster_peeling() -> void:
	var crown_cy: float = -(_clear_px + (_height_px - _clear_px) * 0.46)
	var crown_rx: float = maxf(18.0, _crown_half_px * 0.94)
	var crown_ry: float = maxf(18.0, (_height_px - _clear_px) * 0.58 + 14.0)
	var trunk_iris: Vector4 = Vector4.ZERO

	for cn: ClusterNode in _clusters:
		cn.peel_target = 1.0
		var best_iris: Vector4 = Vector4.ZERO
		for p: Player in Player.all:
			if not is_instance_valid(p) or p.health.current <= 0.0:
				continue
			var rel: Vector2 = p.global_position - global_position
			# Only peel/iris when the player's body (center at rel + (0, -14)) is genuinely covered by the foliage crown!
			if rel.y >= -6.0 or rel.y < -(_height_px + 8.0):
				continue
			var body_rel: Vector2 = Vector2(rel.x, rel.y - 14.0)
			var norm_d: float = Vector2(body_rel.x / crown_rx, (body_rel.y - crown_cy) / crown_ry).length()
			if norm_d > 1.0:
				continue
			var iris_vec: Vector4 = Vector4(p.global_position.x, p.global_position.y - 16.0, 30.0, 1.0)
			if trunk_iris.w <= 0.0:
				trunk_iris = iris_vec
			var cl_center_x: float = (cn.anchor_px.x - _feet_x) + cn.side * (_crown_half_px * 0.35)
			var cl_span_x: float = maxf(30.0, _crown_half_px * 0.62)
			if absf(rel.x - cl_center_x) <= cl_span_x:
				cn.peel_target = PEEL_ALPHA
				best_iris = iris_vec
				break
		if cn.mat != null:
			cn.mat.set_shader_parameter("iris_player", best_iris)

	# Synchronize Bayer 4x4 iris onto UpperTrunk + Trait overlays so internal boughs NEVER stick out over dithered leaves!
	if _upper_trunk_mat != null:
		_upper_trunk_mat.set_shader_parameter("iris_player", trunk_iris)


func _step_perch_contacts(dt: float) -> void:
	if _perches.is_empty() or not _on_screen:
		return
	_perch_wait -= dt
	if _perch_wait > 0.0:
		return
	_perch_wait = 0.22
	var corvids: Array[Node] = get_tree().get_nodes_in_group("corvids")
	for i: int in _perches.size():
		var perch: RoofPerch = _perches[i]
		if not is_instance_valid(perch):
			continue
		var p_world: Vector2 = perch.global_position
		var p_h: float = perch.perch_height
		var has_bird: bool = false
		for cnode: Node in corvids:
			var bird: Node2D = cnode as Node2D
			if bird == null:
				continue
			if bird.global_position.distance_squared_to(p_world) <= 64.0:
				var bh: float = float(cnode.get("_height")) if cnode.get("_height") != null else 0.0
				if absf(bh - p_h) <= 8.0:
					has_bird = true
					break
		var was_occ: bool = _perch_occupied[i] == 1
		if has_bird != was_occ:
			_perch_occupied[i] = 1 if has_bird else 0
			var c_idx: int = _perch_cluster_idx[i]
			# Touchdown dips the bough downward (+1.8 px); takeoff springs it upward (-1.3 px)!
			impulse_cluster(c_idx, Vector2(0.0, 1.8 if has_bird else -1.3), 18.0 if has_bird else 14.0)
			_spawn_leaf_burst(2, Vector2(perch.position.x, -p_h))


func impulse_cluster(cluster_idx: int, offset_px: Vector2, vel_kick: float = 14.0) -> void:
	if cluster_idx < 0 or cluster_idx >= _clusters.size():
		return
	var cn: ClusterNode = _clusters[cluster_idx]
	cn.disp += offset_px * 0.45
	cn.vel += offset_px.normalized() * vel_kick
	set_process(true)


func _impulse_all_clusters(offset_px: Vector2, vel_kick: float) -> void:
	for i: int in _clusters.size():
		var phase_lag: float = 1.0 - float(i) * 0.08
		impulse_cluster(i, offset_px * phase_lag, vel_kick * phase_lag)


func _scatter_perched_birds() -> void:
	for cnode: Node in get_tree().get_nodes_in_group("corvids"):
		var bird: Node2D = cnode as Node2D
		if bird != null and bird.global_position.distance_to(global_position) < _crown_half_px + 28.0:
			if bird.has_method("_take_wing"):
				bird.call("_take_wing", true, false, false, false)


# ---------------- MOTES & DROPS ----------------

func _step_motes(dt: float) -> void:
	if _mote_canvas == null or _mote_canvas.motes.is_empty():
		return
	var wind_v: Vector2 = WorldWind.sample(global_position) if is_instance_valid(WorldWind.current) else Vector2(0.25, 0.0)
	for i: int in range(_mote_canvas.motes.size() - 1, -1, -1):
		var m: TreeMote = _mote_canvas.motes[i]
		m.age += dt
		if m.age >= m.life:
			_mote_canvas.motes.remove_at(i)
			continue
		if m.kind == 0: ## Tumbling oak leaf riding WorldWind in figure-8 pendulum
			if m.z_h > 0.5:
				var sway_x: float = sin(m.age * 4.4 + m.phase) * 14.0
				m.pos += (wind_v * 26.0 + Vector2(sway_x, 2.5) + m.vel) * dt
				m.vel = m.vel.move_toward(Vector2.ZERO, 28.0 * dt)
				m.z_h = maxf(0.0, m.z_h - 15.5 * dt)
		elif m.kind == 1: ## Wood/bark chip ballistic arc
			m.pos += m.vel * dt
			m.vel = m.vel.move_toward(Vector2.ZERO, 60.0 * dt)
			m.z_vel -= 260.0 * dt
			m.z_h = maxf(0.0, m.z_h + m.z_vel * dt)
		elif m.kind == 2: ## Post-rain canopy droplet -> spawns ground/puddle ripple on impact!
			m.z_vel -= 220.0 * dt
			m.z_h += m.z_vel * dt
			if m.z_h <= 0.0:
				var rip: TreeMote = TreeMote.new()
				rip.kind = 3
				rip.pos = m.pos
				rip.life = 0.42
				_mote_canvas.motes[i] = rip
		elif m.kind == 4: ## Woodland bee figure-8 around tree hollow
			m.pos.x += sin(m.age * 5.6 + m.phase) * 11.0 * dt
			m.z_h += cos(m.age * 4.2 + m.phase) * 7.0 * dt
		elif m.kind == 5: ## Rising mycorrhizal spark
			m.pos.x += sin(m.age * 3.1 + m.phase) * 6.0 * dt
			m.z_h += m.z_vel * dt
		elif m.kind == 6: ## Dreamy pink-white *Blütenschnee* petal gliding slowly on WorldWind!
			if m.z_h > 0.4:
				var p_glide: Vector2 = Vector2(sin(m.age * 3.3 + m.phase) * 18.0, cos(m.age * 2.1 + m.phase) * 4.5)
				m.pos += (wind_v * 30.0 + p_glide + m.vel) * dt
				m.vel = m.vel.move_toward(Vector2.ZERO, 24.0 * dt)
				m.z_h = maxf(0.0, m.z_h - 8.2 * dt)
	_mote_canvas.queue_redraw()


func _blossom_palette() -> Array[Color]:
	var out: Array[Color] = []
	var raw_arr: Array = _species.get("blossom_colors", []) as Array
	for hex_v: Variant in raw_arr:
		out.append(Color(String(hex_v)))
	if not out.is_empty():
		return out
	return [Color("fff4f8"), Color("ffd6e6"), Color("e88aa8")]


func _spawn_petal_burst(count: int, center_off: Vector2 = Vector2.ZERO) -> void:
	if _mote_canvas == null or _crown_half_px < 10.0:
		return
	var bpal: Array[Color] = _blossom_palette()
	for _i: int in count:
		if _mote_canvas.motes.size() >= 52:
			break
		var m: TreeMote = TreeMote.new()
		m.kind = 6
		m.pos = center_off + Vector2(_rng.randf_range(-_crown_half_px * 0.68, _crown_half_px * 0.68), _rng.randf_range(-10.0, 10.0))
		m.vel = Vector2(_rng.randf_range(-16.0, 16.0), _rng.randf_range(-6.0, 8.0))
		m.z_h = maxf(10.0, _clear_px + _rng.randf_range(2.0, maxf(12.0, (_height_px - _clear_px) * 0.72)))
		m.life = _rng.randf_range(3.8, 6.2)
		m.phase = _rng.randf() * TAU
		m.col_a = bpal[0]
		m.col_b = bpal[bpal.size() - 1]
		_mote_canvas.motes.append(m)
	set_process(true)


func _leaf_palette() -> Array[Color]:
	var out: Array[Color] = []
	var key: String = "autumn_colors" if autumn_shift > 0.45 else "rain_colors"
	var raw_arr: Array = _species.get(key, []) as Array
	for hex_v: Variant in raw_arr:
		out.append(Color(String(hex_v)))
	if not out.is_empty():
		return out
	if autumn_shift > 0.45:
		return [Color("d89e3c"), Color("b86432"), Color("e6c468")]
	return [Color("3e7d56"), Color("55985f"), Color("7cb96d"), Color("a8dc8c")]


func _spawn_single_wind_leaf(origin_bias: Vector2) -> void:
	if _mote_canvas == null or _crown_half_px < 12.0:
		return
	var pal: Array[Color] = _leaf_palette()
	var m: TreeMote = TreeMote.new()
	m.kind = 0
	m.pos = origin_bias + Vector2(_rng.randf_range(-_crown_half_px * 0.65, _crown_half_px * 0.65), _rng.randf_range(-8.0, 8.0))
	m.z_h = _clear_px + _rng.randf_range(8.0, maxf(14.0, (_height_px - _clear_px) * 0.72))
	m.life = _rng.randf_range(3.2, 5.2)
	m.phase = _rng.randf() * TAU
	m.col_a = pal[_rng.randi() % pal.size()]
	m.col_b = pal[mini(pal.size() - 1, (_rng.randi() % pal.size()) + 1)]
	_mote_canvas.motes.append(m)


func _spawn_leaf_burst(count: int, center_off: Vector2 = Vector2.ZERO) -> void:
	if _mote_canvas == null:
		return
	var pal: Array[Color] = _leaf_palette()
	for _i: int in count:
		if _mote_canvas.motes.size() >= 48:
			break
		var m: TreeMote = TreeMote.new()
		m.kind = 0
		m.pos = center_off + Vector2(_rng.randf_range(-_crown_half_px * 0.58, _crown_half_px * 0.58), _rng.randf_range(-10.0, 10.0))
		m.vel = Vector2(_rng.randf_range(-22.0, 22.0), _rng.randf_range(-8.0, 8.0))
		m.z_h = maxf(10.0, _clear_px + _rng.randf_range(0.0, maxf(10.0, (_height_px - _clear_px) * 0.65)))
		m.life = _rng.randf_range(2.2, 3.8)
		m.phase = _rng.randf() * TAU
		m.col_a = pal[_rng.randi() % pal.size()]
		m.col_b = pal[mini(pal.size() - 1, (_rng.randi() % pal.size()) + 1)]
		_mote_canvas.motes.append(m)
	set_process(true)


func _spawn_wood_chips(out_dir_x: float, count: int) -> void:
	if _mote_canvas == null:
		return
	var wood_arr: Array = _species.get("wood_colors", []) as Array
	var bark_arr: Array = _species.get("bark_colors", []) as Array
	var col_wood: Color = Color(String(wood_arr[0])) if not wood_arr.is_empty() else Color("e6c494")
	var col_bark: Color = Color(String(bark_arr[0])) if not bark_arr.is_empty() else Color("6f5869")
	for _i: int in count:
		var m: TreeMote = TreeMote.new()
		m.kind = 1
		m.pos = Vector2(out_dir_x * _trunk_half_px * 0.6, _rng.randf_range(-2.0, 3.0))
		m.vel = Vector2(out_dir_x * _rng.randf_range(24.0, 68.0), _rng.randf_range(-24.0, 24.0))
		m.z_h = 13.0
		m.z_vel = _rng.randf_range(46.0, 96.0)
		m.life = _rng.randf_range(0.55, 0.95)
		m.col_a = col_wood
		m.col_b = col_bark
		_mote_canvas.motes.append(m)


func _server_roll_drops(drop_list: Array, base_pos: Vector2, base_launch: Vector2, rise_px: float) -> void:
	for entry_v: Variant in drop_list:
		var entry: Dictionary = entry_v as Dictionary
		if _rng.randf() > float(entry.get("chance", 1.0)):
			continue
		var n: int = _rng.randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))
		for _k: int in n:
			var jitter: Vector2 = Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-14.0, 14.0))
			_server_spawn_drop(String(entry["id"]), 1, base_pos, base_launch + jitter, rise_px)


func _server_spawn_drop(item_id: String, count: int, world_at: Vector2, launch_vel: Vector2, rise_px: float) -> void:
	if not multiplayer.is_server() or item_id.is_empty():
		return
	var drops_root: Node = get_tree().get_first_node_in_group("drops")
	if drops_root == null:
		return
	var drop: ItemDrop = DROP_SCENE.instantiate() as ItemDrop
	drop.item_id = item_id
	drop.count = count
	drop.position = world_at
	drop.launch = launch_vel
	drop.rise = rise_px
	drops_root.add_child(drop, true)


func _find_player(peer_id: int) -> Player:
	for p: Player in Player.all:
		if is_instance_valid(p) and (peer_id == 0 or p.name.to_int() == peer_id or p.get_multiplayer_authority() == peer_id):
			return p
	return Player.all[0] if not Player.all.is_empty() else null
