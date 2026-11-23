class_name LivingRock
extends Interactable
## LivingRock 1.0 — Variable, modular & physical pixel-art mineable rock outcrop (`Glimmtal-Fels`):
## - 5 natural size classes (`s0` Loose Fieldstone -> `s1` Small Boulder -> `s2` Medium Block -> `s3` Stratified Outcrop -> `s4` Massive Tor)
##   across 12 chiseled planar geological archetypes (`s0_a..s4_b`) + horizontal flip (`flip_rock`)
## - Modular ecological "Befall" & random prop overlays (`moss`, `lichen`, `ivy`, `fern`, `fungi` + subtle night spore glow)
##   rolled deterministically or via `Jobs.run()` microclimate ecology (`compute_outcrop_ecology_async`)
## - Progressive physical pickaxe mining (`HarvestHurtbox` + `pickaxe_basic`):
##   intact -> cleavage `cracked_1` -> slab-shed `chipped` + `cracked_2` -> walkable low-profile `rubble` scar!
## - Ballistic 2-tone angular stone splinters, flint impact sparks, mineral dust puffs, moss crumbs & non-pickaxe weapon clang
## - Loose `s0` fieldstones can be picked up directly by hand (`[E] FELDSTEIN AUFHEBEN`) or cracked in 1 pickaxe blow
## - Real-time `SunShadows` / `WaterReflections` registration on standing rock mass + Bayer 4x4 upper-crest occlusion dither!

const ROCK_SHADER: Shader = preload("res://assets/shaders/rock_outcrop.gdshader")
const DROP_SCENE: PackedScene = preload("res://src/entities/drops/item_drop.tscn")
const TRAIT_KEYS: Array[String] = ["moss", "lichen", "ivy", "fern", "fungi"]

class RockMote:
	var kind: int = 0 ## 0=angular stone splinter, 1=flint spark, 2=mineral dust puff, 3=shed moss/leaf crumb
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 0.0
	var z_vel: float = 0.0
	var age: float = 0.0
	var life: float = 0.8
	var col_a: Color = Color("a3acb8")
	var col_b: Color = Color("474b61")


class RockMoteCanvas:
	extends Node2D
	var motes: Array[RockMote] = []

	func _draw() -> void:
		for m: RockMote in motes:
			var rem: float = clampf((m.life - m.age) / maxf(m.life * 0.32, 0.04), 0.0, 1.0)
			if rem <= 0.02:
				continue
			var p: Vector2 = Vector2(roundf(m.pos.x), roundf(m.pos.y - m.z_h))
			if m.kind == 0: ## Angular 2-tone stone splinter tumbling in arc
				var c1: Color = m.col_a
				var c2: Color = m.col_b
				c1.a = rem
				c2.a = rem
				var horiz: bool = (int(m.age * 18.0) % 2) == 0
				if horiz:
					draw_rect(Rect2(p, Vector2(2.0, 1.0)), c1)
					draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2(1.0, 1.0)), c2)
				else:
					draw_rect(Rect2(p, Vector2(1.0, 2.0)), c1)
					draw_rect(Rect2(p + Vector2(1.0, 0.0), Vector2(1.0, 1.0)), c2)
			elif m.kind == 1: ## Crisp metallic flint-spark streak on pickaxe / sword impact!
				var cs: Color = m.col_a if m.age < m.life * 0.45 else m.col_b
				cs.a = rem
				draw_rect(Rect2(p, Vector2(1.0, 1.0)), cs)
				if m.age < m.life * 0.35:
					var tail: Vector2 = (p - m.vel.normalized()).round()
					var ct: Color = m.col_b
					ct.a = rem * 0.70
					draw_rect(Rect2(tail, Vector2(1.0, 1.0)), ct)
			elif m.kind == 2: ## Expanding mineral quarry-dust puff
				var cd: Color = m.col_a
				cd.a = rem * 0.42
				var sz: float = 2.0 if m.age < m.life * 0.5 else 3.0
				draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(sz, 2.0)), cd)
			elif m.kind == 3: ## Dislodged moss / fern crumb
				var cm: Color = m.col_a
				cm.a = rem * 0.90
				draw_rect(Rect2(p, Vector2(2.0, 1.0)), cm)


@export var rock_id: String = "valley_stone"
@export var size_stage: int = 2 ## 0..4 (`s0` loose fieldstone .. `s4` massive tor)
@export var arch_variant: int = -1 ## -1 = deterministic per-seed archetype, or explicit `0..2`
@export var trait_overrides: Dictionary = {} ## Optional explicit trait indices: {"moss": 0, "lichen": 1, "ivy": -1, "fern": 0, "fungi": 0}

var cell: Vector2i = Vector2i.ZERO
var state: Dictionary = {} ## Replicated delta state: {"hp": hits_left, "m": mined_day}

## Geological microclimate & rolled trait identity (computed deterministically or via `Jobs.run()`):
var shade_exposure: float = 0.0 ## 0 = open sunlit bedrock (lichen-rich), 1 = shaded woodland edge (moss/fern/fungi-rich)
var talus_shelter: float = 0.0  ## 0..1 proximity to larger tors
var flip_rock: bool = false
var active_rig_key: String = ""
var rolled_traits: Dictionary = {}

var _rock_seed: int = 0
var _rock_tone: Color = Color.WHITE
var _spec: Dictionary = {}
var _rig_all: Dictionary = {}
var _rig: Dictionary = {}
var _stage_cfg: Dictionary = {}

var _frame_w: float = 68.0
var _frame_h: float = 56.0
var _feet_x: float = 34.0
var _feet_y: float = 46.0
var _height_px: float = 32.0
var _half_w_px: float = 21.0
var _body_half_h_px: float = 8.0

var _base_skirt: Sprite2D = null
var _rubble_sprite: Sprite2D = null
var _rock_pivot: Node2D = null ## Standing mass registered with `WaterReflections` / `SunShadows`
var _body_sprite: Sprite2D = null
var _crack_sprite: Sprite2D = null
var _trait_sprites: Dictionary = {} ## trait_key -> Sprite2D
var _fungi_glow: Sprite2D = null
var _rock_mat: ShaderMaterial = null
var _rubble_mat: ShaderMaterial = null
var _mote_canvas: RockMoteCanvas = null

var _shudder_t: float = 0.0
var _shudder_dir: Vector2 = Vector2.RIGHT
var _shudder_amp: float = 0.0
var _hit_flash: float = 0.0
var _iris_cur: float = 0.0
var _last_night: float = -1.0
var _watching_shadows: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Telemetry counters for automated QA (`test_living_rock` & `grass_lab`):
var total_pickaxe_hits_taken: int = 0
var clang_count: int = 0

@onready var _body_shape: CollisionShape2D = $Body/Shape
@onready var _hurtbox: HarvestHurtbox = $Hurtbox
@onready var _hurt_shape: CollisionShape2D = $Hurtbox/Shape


func setup_rock(pos_px: Vector2, p_stage: int = 2, p_seed: int = 0, p_rock_id: String = "valley_stone") -> void:
	position = pos_px.round()
	rock_id = p_rock_id
	size_stage = clampi(p_stage, 0, 4)
	cell = Vector2i((position / 16.0).floor())
	var eff_seed: int = p_seed if p_seed != 0 else hash([int(position.x), int(position.y), 9311])
	_rock_seed = eff_seed
	_rng.seed = eff_seed
	flip_rock = (_rng.randi() % 2) == 1


func configure_traits(p_arch: int = -1, p_traits: Dictionary = {}, p_flip: int = -1) -> void:
	arch_variant = p_arch
	trait_overrides = p_traits.duplicate(true)
	if p_flip >= 0:
		flip_rock = (p_flip > 0)
	if is_inside_tree():
		_rebuild_rig()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("living_rocks")
	if _rock_seed == 0:
		_rock_seed = hash([int(global_position.x), int(global_position.y), 9311])
	if _rng.seed == 0:
		_rng.seed = _rock_seed
	_hurtbox.harvest_target = self
	if not TimeManager.day_started.is_connected(_on_day_started):
		TimeManager.day_started.connect(_on_day_started)
	_load_rock_data()
	if state.is_empty():
		_init_fresh_state()
	_rebuild_rig()
	tree_exiting.connect(_unwatch_shadows)


func _load_rock_data() -> void:
	_spec = DataRegistry.get_entry("rocks", rock_id)
	var rig_table_name: String = String(_spec.get("rig", "valley_stone_rig"))
	_rig_all = DataRegistry.table(rig_table_name)
	var stages_dict: Dictionary = _spec.get("stages", {}) as Dictionary
	_stage_cfg = stages_dict.get(str(size_stage), {}) as Dictionary


func _init_fresh_state() -> void:
	var max_hp: int = maxi(1, int(_stage_cfg.get("hits", 3)))
	state = {
		"hp": max_hp,
		"m": 0,
	}


func max_hits() -> int:
	return maxi(1, int(_stage_cfg.get("hits", 3)))


func hits_remaining() -> int:
	return maxi(0, int(state.get("hp", max_hits())))


func is_depleted() -> bool:
	return int(state.get("m", 0)) > 0 or hits_remaining() <= 0


func spec() -> Dictionary:
	var out: Dictionary = {
		"harvest": {
			"tool": String((_spec.get("harvest", {}) as Dictionary).get("tool", "pickaxe")),
			"hits": max_hits(),
		},
	}
	if _can_hand_pickup():
		out["pickup"] = _spec.get("pickup_s0", {"prompt": "FELDSTEIN AUFHEBEN"})
	return out


func damage_tier() -> int:
	if is_depleted():
		return 3
	var max_hp: int = max_hits()
	var cur_hp: int = hits_remaining()
	if cur_hp >= max_hp:
		return 0
	if max_hp >= 3 and cur_hp <= max_hp / 2:
		return 2
	return 1


func _pick_archetype_key() -> String:
	var arch_list: Array = _stage_cfg.get("archetypes", ["s2_a"]) as Array
	if arch_list.is_empty():
		return "s2_a"
	var idx: int = arch_variant if arch_variant >= 0 else (absi(_rock_seed * 31 + 7) % arch_list.size())
	return String(arch_list[clampi(idx, 0, arch_list.size() - 1)])


func _roll_ecological_traits(traits_cfg: Dictionary) -> void:
	rolled_traits.clear()
	var det_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	det_rng.seed = _rock_seed ^ 0x5A39C1
	# Subtle mineral warmth/coolness variation per individual stone (`0.94..1.05`)
	var warm: float = det_rng.randf_range(-0.035, 0.035)
	var val: float = det_rng.randf_range(0.95, 1.04)
	_rock_tone = Color(clampf(val + warm, 0.90, 1.07), val, clampf(val - warm * 0.8, 0.90, 1.08), 1.0)

	# Ecological Befall probabilities respond naturally to `shade_exposure` (higher near Square 4 oaks!):
	var probs: Dictionary = {
		"moss": lerpf(0.42, 0.86, shade_exposure),
		"lichen": lerpf(0.76, 0.30, shade_exposure),
		"ivy": lerpf(0.18, 0.52, shade_exposure) if size_stage >= 1 else 0.12,
		"fern": lerpf(0.28, 0.64, shade_exposure),
		"fungi": lerpf(0.14, 0.56, shade_exposure) if size_stage >= 1 else 0.0,
	}

	for key: String in TRAIT_KEYS:
		var cols: Array = traits_cfg.get(key, []) as Array
		if cols.is_empty():
			rolled_traits[key] = -1
			continue
		if trait_overrides.has(key):
			var ov: int = int(trait_overrides[key])
			rolled_traits[key] = clampi(ov, -1, cols.size() - 1)
			continue
		var chance: float = float(probs.get(key, 0.35))
		if det_rng.randf() < chance:
			rolled_traits[key] = det_rng.randi() % cols.size()
		else:
			rolled_traits[key] = -1


func _rebuild_rig() -> void:
	_load_rock_data()
	active_rig_key = _pick_archetype_key()
	_rig = _rig_all.get(active_rig_key, {}) as Dictionary

	_frame_w = float(_rig.get("frame_w", 68.0))
	_frame_h = float(_rig.get("frame_h", 56.0))
	_feet_x = float(_rig.get("feet_x", _frame_w * 0.5))
	_feet_y = float(_rig.get("feet_y", _frame_h - 10.0))
	_height_px = float(_rig.get("height_px", 28.0))
	_half_w_px = float(_rig.get("half_w_px", 18.0))
	_body_half_h_px = float(_rig.get("body_half_h_px", 7.0))

	_roll_ecological_traits(_rig.get("traits", {}) as Dictionary)

	_unwatch_shadows()
	for child: Node in get_children():
		if child.name != "Body" and child.name != "Hurtbox":
			child.queue_free()
	_trait_sprites.clear()
	_fungi_glow = null

	# Configure Layer-1 StaticBody2D footprint & Layer-5 HarvestHurtbox (lifted in 3/4 space so swings connect cleanly!)
	var body_rect: RectangleShape2D = RectangleShape2D.new()
	body_rect.size = Vector2(maxf(_half_w_px * 1.72, 10.0), maxf(_body_half_h_px * 1.75, 7.0))
	_body_shape.shape = body_rect
	_body_shape.position = Vector2(0.0, -_body_half_h_px * 0.85)

	var hurt_rect: RectangleShape2D = RectangleShape2D.new()
	hurt_rect.size = Vector2(maxf(_half_w_px * 1.95, 16.0), maxf(_height_px * 0.78, 16.0))
	_hurt_shape.shape = hurt_rect
	_hurt_shape.position = Vector2(0.0, -maxf(_height_px * 0.42, 10.0))

	var sheet_path: String = String(_rig.get("sheet", ""))
	var glow_path: String = String(_rig.get("glow_sheet", ""))
	var sheet_tex: Texture2D = DataRegistry.tex(sheet_path)
	var glow_tex: Texture2D = DataRegistry.tex(glow_path)

	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = ROCK_SHADER
	_rock_mat.set_shader_parameter("frame_size", Vector2(_frame_w, _frame_h))
	_rock_mat.set_shader_parameter("feet_y_px", _feet_y)
	_rock_mat.set_shader_parameter("highlight", 0.68)
	_rock_mat.set_shader_parameter("sun_side", 0.85)

	_rubble_mat = ShaderMaterial.new()
	_rubble_mat.shader = ROCK_SHADER
	_rubble_mat.set_shader_parameter("frame_size", Vector2(_frame_w, _frame_h))
	_rubble_mat.set_shader_parameter("feet_y_px", _feet_y)
	_rubble_mat.set_shader_parameter("highlight", 0.55)
	_rubble_mat.set_shader_parameter("sun_side", 0.45)

	var sprite_off: Vector2 = Vector2(-_feet_x, -_feet_y)
	var layers: Dictionary = _rig.get("layers", {}) as Dictionary

	if sheet_tex != null:
		# 1. Grounded basal contact shadow + scree skirt (`z_index = -9`)
		var skirt_col: int = int(layers.get("base_skirt", 0))
		if skirt_col >= 0:
			_base_skirt = _make_col_sprite("BaseSkirt", sheet_tex, skirt_col, sprite_off)
			_base_skirt.z_as_relative = false
			_base_skirt.z_index = -9
			_base_skirt.material = _rubble_mat
			add_child(_base_skirt)

		# 2. Walkable low-profile rubble scar (`z_index = -8`, shown when depleted on s1..s4)
		var rub_col: int = int(layers.get("rubble", 5))
		if rub_col >= 0:
			_rubble_sprite = _make_col_sprite("RubbleScar", sheet_tex, rub_col, sprite_off)
			_rubble_sprite.z_as_relative = false
			_rubble_sprite.z_index = -8
			_rubble_sprite.modulate = _rock_tone
			_rubble_sprite.material = _rubble_mat
			add_child(_rubble_sprite)

		# 3. Standing Y-sorted rock pivot (registered with SunShadows / WaterReflections!)
		_rock_pivot = Node2D.new()
		_rock_pivot.name = "RockPivot"
		add_child(_rock_pivot)

		var intact_col: int = int(layers.get("intact", 1))
		_body_sprite = _make_col_sprite("RockBody", sheet_tex, intact_col, sprite_off)
		_body_sprite.modulate = _rock_tone
		_body_sprite.material = _rock_mat
		_rock_pivot.add_child(_body_sprite)

		var crack_col: int = int(layers.get("cracked_1", 3))
		_crack_sprite = _make_col_sprite("CleavageCracks", sheet_tex, crack_col, sprite_off)
		_crack_sprite.material = _rock_mat
		_crack_sprite.visible = false
		_rock_pivot.add_child(_crack_sprite)

		# 4. Modular Ecological "Befall" & Random Prop Overlays
		var traits_cfg: Dictionary = _rig.get("traits", {}) as Dictionary
		for key: String in TRAIT_KEYS:
			var idx: int = int(rolled_traits.get(key, -1))
			var cols: Array = traits_cfg.get(key, []) as Array
			if idx >= 0 and idx < cols.size():
				var t_col: int = int(cols[idx])
				var tsp: Sprite2D = _make_col_sprite("Trait_" + key, sheet_tex, t_col, sprite_off)
				tsp.material = _rock_mat
				_rock_pivot.add_child(tsp)
				_trait_sprites[key] = tsp

				if key == "fungi" and glow_tex != null:
					var g_col: int = int(_rig.get("fungi_glow_col", 0))
					_fungi_glow = _make_col_sprite("FungiGlow", glow_tex, g_col, sprite_off)
					_fungi_glow.material = Unlit.material()
					_fungi_glow.visible = false
					_rock_pivot.add_child(_fungi_glow)

	_mote_canvas = RockMoteCanvas.new()
	_mote_canvas.name = "RockMotes"
	_mote_canvas.z_as_relative = false
	_mote_canvas.z_index = 2
	add_child(_mote_canvas)

	_sync_visual_state()
	_sync_night_glow(true)
	set_process(size_stage >= 3)


func _make_col_sprite(node_name: String, tex: Texture2D, col_idx: int, off: Vector2) -> Sprite2D:
	var sp: Sprite2D = Sprite2D.new()
	sp.name = node_name
	sp.texture = tex
	sp.region_enabled = true
	sp.region_rect = Rect2(float(col_idx) * _frame_w, 0.0, _frame_w, _frame_h)
	sp.centered = false
	sp.offset = off
	sp.flip_h = flip_rock
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sp


func _watch_shadows() -> void:
	if _rock_pivot != null and not _watching_shadows:
		WaterReflections.watch(_rock_pivot, false)
		_watching_shadows = true


func _unwatch_shadows() -> void:
	if _rock_pivot != null and _watching_shadows:
		WaterReflections.unwatch(_rock_pivot)
		_watching_shadows = false


func _sync_visual_state() -> void:
	var depleted: bool = is_depleted()
	var tier: int = damage_tier()
	var leave_rubble: bool = bool(_stage_cfg.get("leave_rubble", size_stage >= 1))
	var layers: Dictionary = _rig.get("layers", {}) as Dictionary

	_body_shape.set_deferred("disabled", depleted or size_stage == 0)
	_hurtbox.set_deferred("monitorable", not depleted)

	if _base_skirt != null:
		_base_skirt.visible = (not depleted) or leave_rubble
	if _rubble_sprite != null:
		_rubble_sprite.visible = depleted and leave_rubble

	if _rock_pivot != null:
		_rock_pivot.visible = not depleted
		if not depleted and size_stage >= 1:
			_watch_shadows()
		else:
			_unwatch_shadows()

	if not depleted and _body_sprite != null:
		var body_col: int = int(layers.get("chipped", 2)) if tier >= 2 else int(layers.get("intact", 1))
		_body_sprite.region_rect = Rect2(float(body_col) * _frame_w, 0.0, _frame_w, _frame_h)
		if _crack_sprite != null:
			_crack_sprite.visible = tier >= 1
			var c_col: int = int(layers.get("cracked_2", 4)) if tier >= 2 else int(layers.get("cracked_1", 3))
			_crack_sprite.region_rect = Rect2(float(c_col) * _frame_w, 0.0, _frame_w, _frame_h)

		# When outer stone slabs cleave away (`tier >= 2`), upper surface lichen/moss/ivy shed naturally!
		for key: String in _trait_sprites.keys():
			var tsp: Sprite2D = _trait_sprites[key] as Sprite2D
			if tsp != null:
				tsp.visible = (tier < 2) or (key == "fungi" or key == "fern")

	_sync_night_glow(true)


func _sync_night_glow(force: bool = false) -> void:
	if _fungi_glow == null:
		return
	var night: float = TimeManager.night_amount()
	if not force and absf(night - _last_night) < 0.01:
		return
	_last_night = night
	var show_g: bool = (not is_depleted()) and night > 0.05
	_fungi_glow.visible = show_g
	if show_g:
		_fungi_glow.modulate.a = lerpf(0.25, 0.88, clampf(night, 0.0, 1.0))


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	_sync_night_glow(false)
	var keep_awake: bool = size_stage >= 3

	if _shudder_t > 0.0:
		_shudder_t = maxf(0.0, _shudder_t - dt)
		var decay: float = _shudder_t / 0.18
		var osc: float = sin((1.0 - decay) * 44.0) * _shudder_amp * decay
		if _rock_pivot != null:
			_rock_pivot.position = (_shudder_dir * osc).round()
		keep_awake = true
	elif _rock_pivot != null and _rock_pivot.position != Vector2.ZERO:
		_rock_pivot.position = Vector2.ZERO

	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - dt * 5.5)
		if _rock_mat != null:
			_rock_mat.set_shader_parameter("hit_flash", _hit_flash)
		keep_awake = true

	# Smooth Bayer 4x4 upper-crest occlusion iris when Ellie stands behind a tall s3/s4 rock formation
	if size_stage >= 3 and not is_depleted() and _rock_mat != null:
		var target_iris: float = 0.0
		var p_pos: Vector2 = Vector2.ZERO
		for p: Player in Player.all:
			if not is_instance_valid(p) or not p.visible:
				continue
			var rel: Vector2 = p.global_position - global_position
			if rel.y < -2.0 and rel.y > -(_height_px + 12.0) and absf(rel.x) < (_half_w_px + 10.0):
				target_iris = 1.0
				p_pos = p.global_position + Vector2(0.0, -18.0)
				break
		if absf(target_iris - _iris_cur) > 0.005 or _iris_cur > 0.005:
			_iris_cur = move_toward(_iris_cur, target_iris, dt * 6.0)
			_rock_mat.set_shader_parameter("iris_player", Vector4(p_pos.x, p_pos.y, 24.0, _iris_cur))

	if _mote_canvas != null and not _mote_canvas.motes.is_empty():
		keep_awake = true
		for i: int in range(_mote_canvas.motes.size() - 1, -1, -1):
			var m: RockMote = _mote_canvas.motes[i]
			m.age += dt
			if m.age >= m.life:
				_mote_canvas.motes.remove_at(i)
				continue
			if m.kind == 0 or m.kind == 3:
				m.pos += m.vel * dt
				m.vel = m.vel.move_toward(Vector2.ZERO, 75.0 * dt)
				m.z_vel -= 280.0 * dt
				m.z_h = maxf(0.0, m.z_h + m.z_vel * dt)
				if m.z_h <= 0.0 and m.z_vel < -25.0:
					m.z_vel = -m.z_vel * 0.28
					m.vel *= 0.55
			elif m.kind == 1:
				m.pos += m.vel * dt
				m.z_vel -= 180.0 * dt
				m.z_h = maxf(0.0, m.z_h + m.z_vel * dt)
			elif m.kind == 2:
				m.pos += m.vel * dt
				m.vel = m.vel.move_toward(Vector2.ZERO, 36.0 * dt)
				m.z_h += 8.0 * dt
		_mote_canvas.queue_redraw()

	if not keep_awake:
		set_process(false)


# ---------------- HAND PICKUP ON LOOSE `s0` FIELDSTONES ----------------

func _can_hand_pickup() -> bool:
	return (not is_depleted()) and bool(_stage_cfg.get("hand_pickup", false))


func prompt() -> String:
	if InputManager.ui_blocking or not _can_hand_pickup():
		return ""
	return String((_spec.get("pickup_s0", {}) as Dictionary).get("prompt", "FELDSTEIN AUFHEBEN"))


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, from.distance_to(global_position + Vector2(0.0, -4.0)) - (_half_w_px + 8.0))


func prompt_position() -> Vector2:
	return Vector2(0.0, -(_height_px + 10.0))


func interact(player: Player) -> void:
	if player == null or not _can_hand_pickup():
		return
	var toward: Vector2 = global_position - player.global_position
	var face_dir: Vector2 = toward.normalized() if toward.length() > 1.0 else player.facing
	player.begin_pick(face_dir, func() -> void:
		if multiplayer.is_server():
			_server_hand_pickup(player)
		else:
			_rpc_request_pickup.rpc_id(1))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pickup() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var who: Player = _find_player(sender)
	if who != null and reach_distance(who.global_position) <= INTERACT_RANGE + 8.0:
		_server_hand_pickup(who)


func _server_hand_pickup(who: Player) -> void:
	if not _can_hand_pickup():
		return
	state["hp"] = 0
	state["m"] = maxi(1, TimeManager.day + 1)
	var out_dir: Vector2 = (who.global_position - global_position).normalized() if who != null else Vector2.DOWN
	_server_roll_drops(_stage_cfg.get("drops", []) as Array, global_position + Vector2(0.0, -6.0), out_dir * 32.0, 10.0)
	_rpc_sync_state.rpc(state, "pickup_s0", out_dir.x)


# ---------------- PICKAXE MINING & HOST-AUTHORITATIVE STATE ----------------

func harvest_hit(source: int) -> void:
	if not multiplayer.is_server() or is_depleted():
		return
	var hitter: Player = _find_player(source)
	var held_tool: String = ""
	if hitter != null and hitter.inventory != null:
		held_tool = String(Items.definition(hitter.inventory.active_stack()).get("tool", ""))
	var from_pos: Vector2 = hitter.global_position if hitter != null else (global_position + Vector2(-16.0, 0.0))
	var hit_from_left: bool = from_pos.x < global_position.x
	var out_x: float = -1.0 if hit_from_left else 1.0 ## Chips & sparks fly toward the struck face / outward!

	var req_tool: String = String((_spec.get("harvest", {}) as Dictionary).get("tool", "pickaxe"))
	if not bool(_stage_cfg.get("mineable", true)) or held_tool != req_tool:
		_rpc_sync_state.rpc(state, "clang", out_x)
		return

	_apply_server_pickaxe_blow(out_x)


## Direct script/test helper for deterministic pickaxe strikes (host-only, mirrors `LivingTree.strike_with_axe`).
func strike_with_pickaxe(from_world_pos: Vector2) -> void:
	if not multiplayer.is_server() or is_depleted():
		return
	var out_x: float = -1.0 if from_world_pos.x < global_position.x else 1.0
	_apply_server_pickaxe_blow(out_x)


func _apply_server_pickaxe_blow(out_x: float) -> void:
	var prev_tier: int = damage_tier()
	var cur_hp: int = hits_remaining() - 1
	state["hp"] = maxi(0, cur_hp)

	if cur_hp > 0:
		if _stage_cfg.has("chip_drop"):
			var cd: Dictionary = _stage_cfg["chip_drop"] as Dictionary
			if _rng.randf() < float(cd.get("chance", 0.45)):
				_server_spawn_drop(
					String(cd["id"]),
					1,
					global_position + Vector2(out_x * _half_w_px * 0.55, -8.0),
					Vector2(out_x * _rng.randf_range(36.0, 58.0), _rng.randf_range(-16.0, 20.0)),
					12.0
				)
		var next_tier: int = damage_tier()
		var fx_kind: String = "slab_cleave" if next_tier > prev_tier and next_tier >= 2 else "pick_hit"
		_rpc_sync_state.rpc(state, fx_kind, out_x)
	else:
		state["m"] = maxi(1, TimeManager.day + 1)
		_server_roll_drops(
			_stage_cfg.get("drops", []) as Array,
			global_position + Vector2(0.0, -8.0),
			Vector2(out_x * 26.0, 12.0),
			14.0
		)
		_rpc_sync_state.rpc(state, "shatter", out_x)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_state(new_state: Dictionary, fx: String, out_x: float) -> void:
	state = new_state.duplicate(true)
	_sync_visual_state()
	match fx:
		"clang":
			clang_count += 1
			_trigger_shudder(Vector2(-out_x, 0.25), 0.9)
			_spawn_flint_sparks(out_x, 4)
			Sfx.at(self, "pick_rock", global_position, -6.0, 0.08)
		"pickup_s0":
			_spawn_dust_puffs(3)
			Sfx.at(self, "pluck", global_position, -3.0)
		"pick_hit":
			total_pickaxe_hits_taken += 1
			_hit_flash = 0.75
			_trigger_shudder(Vector2(-out_x, 0.3), 1.6)
			_spawn_flint_sparks(out_x, 6)
			_spawn_stone_chips(out_x, 7)
			_spawn_dust_puffs(3)
			if int(rolled_traits.get("moss", -1)) >= 0 or int(rolled_traits.get("fern", -1)) >= 0:
				_spawn_moss_crumbs(out_x, 2)
			Sfx.at(self, "pick_rock", global_position, -2.0, 0.06)
		"slab_cleave":
			total_pickaxe_hits_taken += 1
			_hit_flash = 1.0
			_trigger_shudder(Vector2(-out_x, 0.4), 2.2)
			_spawn_flint_sparks(out_x, 8)
			_spawn_stone_chips(out_x, 13)
			_spawn_dust_puffs(6)
			_spawn_moss_crumbs(out_x, 5)
			Sfx.at(self, "pick_rock", global_position, -0.5, 0.08)
		"shatter":
			total_pickaxe_hits_taken += 1
			_spawn_flint_sparks(out_x, 7)
			_spawn_stone_chips(out_x, 18)
			_spawn_dust_puffs(9)
			if int(rolled_traits.get("moss", -1)) >= 0:
				_spawn_moss_crumbs(out_x, 6)
			Sfx.at(self, "rock_break", global_position, -1.0, 0.05)
		"regrow":
			_spawn_dust_puffs(4)
	set_process(true)


func _trigger_shudder(dir: Vector2, amp: float) -> void:
	_shudder_dir = dir.normalized() if dir.length_squared() > 0.001 else Vector2.RIGHT
	_shudder_amp = amp
	_shudder_t = 0.18


func _on_day_started(new_day: int) -> void:
	if not multiplayer.is_server() or not is_depleted():
		return
	var mined_day: int = int(state.get("m", 0))
	if mined_day <= 0:
		return
	var regrow_d: int = int(_stage_cfg.get("regrow_days", 4))
	if regrow_d > 0 and (new_day - (mined_day - 1)) >= regrow_d:
		state["hp"] = max_hits()
		state["m"] = 0
		_rpc_sync_state.rpc(state, "regrow", 0.0)


func advance_weathering_days(days: int) -> void:
	if not multiplayer.is_server() or days <= 0 or not is_depleted():
		return
	var regrow_d: int = int(_stage_cfg.get("regrow_days", 4))
	if days >= regrow_d:
		state["hp"] = max_hits()
		state["m"] = 0
		_rpc_sync_state.rpc(state, "regrow", 0.0)


# ---------------- PARTICLE MOTES & DROP SPAWNING ----------------

func _spawn_stone_chips(out_x: float, count: int) -> void:
	if _mote_canvas == null:
		return
	var hex_list: Array = _spec.get("chip_colors", ["a3acb8", "7f8899", "474b61", "323248"]) as Array
	for _i: int in count:
		if _mote_canvas.motes.size() >= 64:
			break
		var m: RockMote = RockMote.new()
		m.kind = 0
		var spread_x: float = out_x * _rng.randf_range(16.0, 64.0) + _rng.randf_range(-24.0, 24.0)
		m.pos = Vector2(out_x * _half_w_px * _rng.randf_range(0.1, 0.65), _rng.randf_range(-3.0, 3.0))
		m.vel = Vector2(spread_x, _rng.randf_range(-26.0, 28.0))
		m.z_h = clampf(_height_px * _rng.randf_range(0.25, 0.72), 5.0, 34.0)
		m.z_vel = _rng.randf_range(38.0, 96.0)
		m.life = _rng.randf_range(0.50, 0.92)
		m.col_a = Color(String(hex_list[0]))
		m.col_b = Color(String(hex_list[mini(hex_list.size() - 1, 2)]))
		_mote_canvas.motes.append(m)


func _spawn_flint_sparks(out_x: float, count: int) -> void:
	if _mote_canvas == null:
		return
	var sp_hex: Array = _spec.get("spark_colors", ["fff0b0", "e6c468"]) as Array
	for _i: int in count:
		if _mote_canvas.motes.size() >= 64:
			break
		var m: RockMote = RockMote.new()
		m.kind = 1
		m.pos = Vector2(out_x * _half_w_px * 0.45, _rng.randf_range(-2.0, 2.0))
		m.vel = Vector2(out_x * _rng.randf_range(28.0, 74.0), _rng.randf_range(-32.0, 32.0))
		m.z_h = clampf(_height_px * 0.48, 6.0, 26.0)
		m.z_vel = _rng.randf_range(24.0, 68.0)
		m.life = _rng.randf_range(0.14, 0.28)
		m.col_a = Color(String(sp_hex[0]))
		m.col_b = Color(String(sp_hex[mini(sp_hex.size() - 1, 1)]))
		_mote_canvas.motes.append(m)


func _spawn_dust_puffs(count: int) -> void:
	if _mote_canvas == null:
		return
	var dc: Color = Color(String(_spec.get("dust_color", "#9ca3b5")))
	for _i: int in count:
		if _mote_canvas.motes.size() >= 64:
			break
		var m: RockMote = RockMote.new()
		m.kind = 2
		m.pos = Vector2(_rng.randf_range(-_half_w_px * 0.65, _half_w_px * 0.65), _rng.randf_range(-4.0, 4.0))
		m.vel = Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-10.0, 10.0))
		m.z_h = _rng.randf_range(2.0, maxf(6.0, _height_px * 0.45))
		m.life = _rng.randf_range(0.35, 0.65)
		m.col_a = dc
		_mote_canvas.motes.append(m)


func _spawn_moss_crumbs(out_x: float, count: int) -> void:
	if _mote_canvas == null:
		return
	var mc_list: Array = _spec.get("moss_colors", ["346e52", "55985f", "7cb96d"]) as Array
	for _i: int in count:
		if _mote_canvas.motes.size() >= 64:
			break
		var m: RockMote = RockMote.new()
		m.kind = 3
		m.pos = Vector2(_rng.randf_range(-_half_w_px * 0.4, _half_w_px * 0.4), _rng.randf_range(-3.0, 2.0))
		m.vel = Vector2(out_x * _rng.randf_range(12.0, 38.0), _rng.randf_range(-18.0, 18.0))
		m.z_h = clampf(_height_px * 0.55, 6.0, 28.0)
		m.z_vel = _rng.randf_range(24.0, 56.0)
		m.life = _rng.randf_range(0.45, 0.85)
		m.col_a = Color(String(mc_list[_rng.randi() % mc_list.size()]))
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


# ---------------- MULTITHREADED GEOLOGICAL ECOLOGY (`Jobs.run()`) ----------------

## Computes shade/moisture exposure from nearby trees & neighbor tors on a `Jobs` background worker,
## then re-rolls coherent ecological Befall (`moss`, `lichen`, `ivy`, `fern`, `fungi`) on the main thread!
static func compute_outcrop_ecology_async(rocks: Array[LivingRock], tree_positions: Array[Vector2] = []) -> Jobs.Job:
	var rock_pts: PackedVector2Array = PackedVector2Array()
	var rock_stages: PackedInt32Array = PackedInt32Array()
	rock_pts.resize(rocks.size())
	rock_stages.resize(rocks.size())
	for i: int in rocks.size():
		rock_pts[i] = rocks[i].position
		rock_stages[i] = rocks[i].size_stage
	var tree_pts: PackedVector2Array = PackedVector2Array(tree_positions)

	var work: Callable = func() -> Array[Vector2]:
		var out: Array[Vector2] = []
		out.resize(rock_pts.size())
		for i: int in rock_pts.size():
			var p: Vector2 = rock_pts[i]
			var shade: float = 0.0
			for tp: Vector2 in tree_pts:
				var dt_tree: float = p.distance_to(tp)
				if dt_tree < 185.0:
					shade = maxf(shade, (1.0 - dt_tree / 185.0) * 0.92)
			var shelter: float = 0.0
			for j: int in rock_pts.size():
				if i == j or rock_stages[j] < 3:
					continue
				var dr: float = p.distance_to(rock_pts[j])
				if dr < 96.0:
					shelter = maxf(shelter, 1.0 - dr / 96.0)
					if p.y < rock_pts[j].y + 8.0:
						shade = maxf(shade, (1.0 - dr / 96.0) * 0.55)
			out[i] = Vector2(clampf(shade, 0.0, 1.0), clampf(shelter, 0.0, 1.0))
		return out

	var on_done: Callable = func(res: Array[Vector2]) -> void:
		for i: int in mini(rocks.size(), res.size()):
			var rk: LivingRock = rocks[i]
			if is_instance_valid(rk):
				rk.shade_exposure = res[i].x
				rk.talus_shelter = res[i].y
				if rk.is_inside_tree():
					rk._rebuild_rig()

	return Jobs.run(work, on_done)
