class_name LivingFloraProp
extends Interactable
## LivingFlora 2.0 — Interactive, circadian & physically reactive pixel-art botanical prop:
##   - Supports all 28 Sanctuary, Meadow, Roadside, Crevice & Woodland-Edge species (`data/sanctuary_flora.json`)
##   - Batched whole-pixel `WorldWind` sway + radial 2-sided actor parting via shared `living_flora.gdshader`
##   - Circadian & weather life-cycles:
##       * `day_bloom` (`way_chicory`): opens in morning/noon sun, folds buds closed in late afternoon, rain & night
##       * `night_fold` (`wood_sorrel`): nyctinastic umbrella-folded sleeping leaves at night & in heavy rain
##       * `dew_pearl` (`star_mantle`): forms a gleaming Star-Dew pearl in morning dew (`g_dew`) & rain
##       * `dandelion_puff` (`meadow_clock`): bursts into 12 wind-drifting silver seed parachutes when brushed or picked!
##   - Dual harvest paths (host-authoritative `@rpc`):
##       1) `[E] PFLÜCKEN` -> plucks blossoms/berries/dew into inventory, leaving leafy `picked` plant intact to regrow
##       2) `sickle_basic` (`HarvestHurtbox` Layer 5) -> crisp leaf-arc burst, `ItemDrop` loot & realistic `cut` stubble!

const SMALL_TEX_PATH: String = "res://assets/props/flora_sanctuary_small.png"
const SMALL_GLOW_PATH: String = "res://assets/props/flora_sanctuary_small_glow.png"
const LARGE_TEX_PATH: String = "res://assets/props/flora_sanctuary_large.png"
const LARGE_GLOW_PATH: String = "res://assets/props/flora_sanctuary_large_glow.png"
const DROP_SCENE: PackedScene = preload("res://src/entities/drops/item_drop.tscn")

const SMALL_CELL: Vector2 = Vector2(32.0, 36.0)
const SMALL_OFFSET: Vector2 = Vector2(-16.0, -31.0)
const LARGE_CELL: Vector2 = Vector2(56.0, 52.0)
const LARGE_OFFSET: Vector2 = Vector2(-28.0, -45.0)

@export var species_id: String = "silver_yarrow"
@export var variant: int = 0 ## 0..2 growth/season variant (for large shrubs: 0..1 = bloom, 2 = ripe fruit!)
@export var flip_plant: bool = false

var field: Node2D ## Reference to owning `LivingFloraField` for zero-cost shared materials & pixel motes
var state: Dictionary = {} ## Replicated delta state: {"p": picked_day, "c": cut_day, "hp": hits_left}

var _spec: Dictionary = {}
var _is_large: bool = false
var _row: int = 0
var _radius: float = 8.0
var _height: float = 16.0
var _slow: float = 1.0
var _closed_now: bool = false
var _dew_ready: bool = false
var _active_col: int = -1
var _pose_timer: float = 0.0
var _spring_t: float = -1.0
var _spring_dir: float = 1.0
var _inside_players: Array[Player] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _sprite: Sprite2D
var _glow: Sprite2D
var _walk_area: Area2D
var _hurtbox: HarvestHurtbox


func setup_flora(
	id: String,
	world_pos: Vector2,
	var_idx: int = 0,
	flipped: bool = false,
	owner_field: Node2D = null
) -> void:
	species_id = id
	variant = maxi(0, var_idx)
	flip_plant = flipped
	field = owner_field
	position = world_pos.round()
	_rng.seed = int(absf(position.x * 73.0 + position.y * 197.0)) + var_idx * 31 + 11


func _ready() -> void:
	_spec = DataRegistry.get_entry("sanctuary_flora", species_id)
	if _spec.is_empty():
		_spec = {"name": species_id, "sheet": "small", "row": 0, "sway": 1.0, "radius": 8.0, "height": 14.0, "slow": 1.0}
	_is_large = String(_spec.get("sheet", "small")) == "large"
	_row = int(_spec.get("row", 0))
	_radius = float(_spec.get("radius", 8.0))
	_height = float(_spec.get("height", 14.0))
	_slow = float(_spec.get("slow", 1.0))

	var cell_sz: Vector2 = LARGE_CELL if _is_large else SMALL_CELL
	var foot_off: Vector2 = LARGE_OFFSET if _is_large else SMALL_OFFSET
	var max_var: int = 3 if _is_large else 3
	variant = variant % max_var
	# For `meadow_clock`, variants 1..2 start as silver dandelion puffballs so players see both golden flowers & puffballs!
	if String(_spec.get("behavior", "")) == "dandelion_puff" and variant >= 1:
		variant = 2

	_sprite = Sprite2D.new()
	_sprite.name = "PlantSprite"
	_sprite.texture = load(LARGE_TEX_PATH if _is_large else SMALL_TEX_PATH) as Texture2D
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0.0, float(_row) * cell_sz.y, cell_sz.x, cell_sz.y)
	_sprite.centered = false
	_sprite.offset = foot_off
	_sprite.flip_h = flip_plant
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if field != null and field.has_method("get_shared_material"):
		_sprite.material = field.call("get_shared_material", _is_large, float(_spec.get("sway", 1.0)), false) as ShaderMaterial
	add_child(_sprite)

	if bool(_spec.get("glow", false)):
		_glow = Sprite2D.new()
		_glow.name = "PlantGlow"
		_glow.texture = load(LARGE_GLOW_PATH if _is_large else SMALL_GLOW_PATH) as Texture2D
		_glow.region_enabled = true
		_glow.region_rect = _sprite.region_rect
		_glow.centered = false
		_glow.offset = foot_off
		_glow.flip_h = flip_plant
		_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if field != null and field.has_method("get_shared_material"):
			_glow.material = field.call("get_shared_material", _is_large, float(_spec.get("sway", 1.0)), true) as ShaderMaterial
		else:
			_glow.material = Unlit.material()
		_glow.visible = false
		add_child(_glow)

	# Walk-through sensor (Physics Layer 2 = Player) for rustle, slow, dandelion puff & dew splash!
	_walk_area = Area2D.new()
	_walk_area.name = "FoliageWalkArea"
	_walk_area.collision_layer = 0
	_walk_area.collision_mask = 2
	_walk_area.monitorable = false
	var walk_col: CollisionShape2D = CollisionShape2D.new()
	var walk_circle: CircleShape2D = CircleShape2D.new()
	walk_circle.radius = maxf(6.0, _radius * 0.82)
	walk_col.shape = walk_circle
	walk_col.position = Vector2(0.0, -3.0)
	_walk_area.add_child(walk_col)
	_walk_area.body_entered.connect(_on_walk_entered)
	_walk_area.body_exited.connect(_on_walk_exited)
	add_child(_walk_area)

	# Sickle HarvestHurtbox on Physics Layer 5 (`hurtbox`), lifted -18 px to match chest weapon fan!
	if _spec.has("harvest"):
		_hurtbox = HarvestHurtbox.new()
		_hurtbox.name = "HarvestHurtbox"
		_hurtbox.harvest_target = self
		_hurtbox.collision_layer = 16
		_hurtbox.collision_mask = 8
		var hb_col: CollisionShape2D = CollisionShape2D.new()
		var hb_circle: CircleShape2D = CircleShape2D.new()
		hb_circle.radius = maxf(8.0, _radius * 0.95)
		hb_col.shape = hb_circle
		hb_col.position = Vector2(0.0, -18.0)
		_hurtbox.add_child(hb_col)
		add_child(_hurtbox)

	_refresh_pose(true)


func _exit_tree() -> void:
	for p: Player in _inside_players:
		if is_instance_valid(p):
			p.clear_slow(self)
	_inside_players.clear()


func _process(delta: float) -> void:
	_pose_timer -= delta
	if _pose_timer <= 0.0:
		_pose_timer = 0.35
		_refresh_pose(false)

	if _spring_t >= 0.0:
		_spring_t += delta
		if _spring_t >= 0.55:
			_spring_t = -1.0
			if _sprite != null:
				_sprite.skew = 0.0
			if _glow != null:
				_glow.skew = 0.0
		else:
			var s_val: float = sin(_spring_t * 20.0) * exp(-_spring_t * 5.8) * 0.11 * _spring_dir
			if _sprite != null:
				_sprite.skew = s_val
			if _glow != null:
				_glow.skew = s_val


func spec() -> Dictionary:
	return _spec


func is_cut() -> bool:
	return int(state.get("c", 0)) > 0


func is_picked() -> bool:
	return int(state.get("p", 0)) > 0


func is_depleted() -> bool:
	return is_cut()


func _max_hits() -> int:
	return maxi(1, int((_spec.get("harvest", {}) as Dictionary).get("hits", 1)))


func _hits_left() -> int:
	return int(state.get("hp", _max_hits()))


func _refresh_pose(force: bool) -> void:
	if _sprite == null:
		return
	var cur_day: int = maxi(1, TimeManager.day)
	if is_cut():
		var regrow_c: int = 2
		if cur_day - int(state.get("c", 0)) >= regrow_c:
			state.erase("c")
			state.erase("hp")
	if is_picked():
		var regrow_p: int = int((_spec.get("pickup", {}) as Dictionary).get("regrow_days", 2))
		if cur_day - int(state.get("p", 0)) >= regrow_p:
			state.erase("p")

	var col_idx: int = variant
	var beh: String = String(_spec.get("behavior", ""))
	var tod: float = TimeManager.time_of_day
	var night: float = TimeManager.night_amount()
	var rain: float = WeatherManager.current.rain if WeatherManager.current != null else 0.0
	var wet: float = WeatherManager.current.ground_wet if WeatherManager.current != null else 0.0

	_closed_now = false
	_dew_ready = true

	if is_cut():
		col_idx = 4 if _is_large else 5
	elif is_picked():
		col_idx = 3 if _is_large else 4
	else:
		if beh == "day_bloom":
			# Way Chicory opens in morning/noon sunlight (0.22..0.66) and closes in late evening, night, or rain!
			if night > 0.30 or tod > 0.68 or rain > 0.30:
				col_idx = 3
				_closed_now = true
		elif beh == "night_fold":
			# Wood Sorrel folds its trifoliate heart-leaves asleep at night or in heavy rain!
			if night > 0.40 or rain > 0.45:
				col_idx = 3
				_closed_now = true
		elif beh == "dew_pearl":
			# Star Lady's Mantle holds a shimmering Star-Dew pearl in morning dew, rain, or cool twilight!
			_dew_ready = (tod >= 0.18 and tod <= 0.44) or night > 0.35 or rain > 0.08 or wet > 0.25
			if not _dew_ready:
				col_idx = 3
		elif beh == "gust_silver":
			var gust_now: float = WorldWind.current.gust if WorldWind.current != null else 0.0
			if gust_now > 0.55:
				col_idx = 3

	var cell_sz: Vector2 = LARGE_CELL if _is_large else SMALL_CELL
	if force or col_idx != _active_col:
		_active_col = col_idx
		var rect: Rect2 = Rect2(float(col_idx) * cell_sz.x, float(_row) * cell_sz.y, cell_sz.x, cell_sz.y)
		_sprite.region_rect = rect
		if _glow != null:
			_glow.region_rect = rect
		if _hurtbox != null:
			_hurtbox.set_deferred("monitorable", not is_cut())
		if _prompt_node != null and _prompt_node.visible:
			set_focused(true)

	if _glow != null:
		if is_cut() or is_picked():
			_glow.visible = false
		elif beh == "dew_pearl":
			_glow.visible = _dew_ready
			if _glow.visible:
				_glow.modulate.a = lerpf(0.45, 0.90, night) * (0.78 + 0.22 * sin(Time.get_ticks_msec() * 0.0028 + position.x))
		else:
			_glow.visible = night > 0.05
			if _glow.visible:
				var pulse: float = 0.76 + 0.24 * sin(Time.get_ticks_msec() * 0.0020 + position.x * 0.07 + position.y * 0.05)
				_glow.modulate.a = smoothstep(0.05, 0.82, night) * pulse


func _trigger_spring(dir_x: float) -> void:
	_spring_dir = -1.0 if dir_x < 0.0 else 1.0
	_spring_t = 0.001


func _on_walk_entered(body: Node2D) -> void:
	var p: Player = body as Player
	if p == null or is_cut():
		return
	if not _inside_players.has(p):
		_inside_players.append(p)
	if _slow < 0.99 and p.is_multiplayer_authority():
		p.set_slow(self, _slow)

	var dir_x: float = signf(p.velocity.x) if absf(p.velocity.x) > 4.0 else (-1.0 if p.global_position.x > global_position.x else 1.0)
	_trigger_spring(dir_x)
	if _height >= 16.0:
		Sfx.at(self, "pluck", global_position, -14.0, 0.14)

	var beh: String = String(_spec.get("behavior", ""))
	if beh == "dandelion_puff" and not is_picked() and variant >= 2 and multiplayer.is_server():
		# Brushing past a ripe silver dandelion clock sends 12 seed parachutes drifting on WorldWind!
		state["p"] = maxi(1, TimeManager.day)
		_rpc_sync_flora_state.rpc(state, "puff", dir_x)
	elif beh == "dew_pearl" and _dew_ready and not is_picked() and p.velocity.length() > 65.0:
		if field != null and field.has_method("spawn_dew_splash"):
			field.call("spawn_dew_splash", global_position + Vector2(0.0, -7.0), 6)
	elif bool(_spec.get("petal_drift", false)) and not is_picked() and p.velocity.length() > 45.0:
		if field != null and field.has_method("spawn_petals"):
			var bcols: Array = _spec.get("burst_colors", ["#f4f2fa", "#f7d2e0"]) as Array
			field.call("spawn_petals", global_position + Vector2(0.0, -_height * 0.65), 3, Color(String(bcols[0])))


func _on_walk_exited(body: Node2D) -> void:
	var p: Player = body as Player
	if p != null:
		_inside_players.erase(p)
		p.clear_slow(self)


# ---------------- INTERACTION (`[E] PFLÜCKEN`) & SICKLE HARVEST ----------------

func reach_distance(from: Vector2) -> float:
	return maxf(0.0, global_position.distance_to(from) - _radius)


func prompt_position() -> Vector2:
	return Vector2(0.0, -clampf(_height + 8.0, 18.0, 42.0))


func prompt() -> String:
	if is_cut() or is_picked() or _closed_now or not _spec.has("pickup"):
		return ""
	if String(_spec.get("behavior", "")) == "dew_pearl" and not _dew_ready:
		return ""
	var pk: Dictionary = _spec["pickup"] as Dictionary
	if _is_large and variant == 2 and pk.has("fruit_item"):
		return "HOLUNDERBEEREN PFLÜCKEN"
	if species_id == "wild_rose_briar" and variant < 2:
		return "HECKENROSEN PFLÜCKEN"
	return String(pk.get("prompt", "PFLÜCKEN"))


func interact(player: Player) -> void:
	if prompt().is_empty() or player == null:
		return
	var toward: Vector2 = (global_position - player.global_position).normalized()
	player.begin_pick(toward if toward.length_squared() > 0.01 else Vector2.UP, func() -> void:
		_rpc_request_pick.rpc_id(1, player.get_multiplayer_authority())
	)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_pick(peer_id: int) -> void:
	if not multiplayer.is_server() or is_cut() or is_picked() or _closed_now or not _spec.has("pickup"):
		return
	var pk: Dictionary = _spec["pickup"] as Dictionary
	var item_id: String = String(pk.get("item", ""))
	if _is_large and variant == 2 and pk.has("fruit_item"):
		item_id = String(pk["fruit_item"])
	elif species_id == "wild_rose_briar" and variant < 2:
		item_id = "chicory_petal" if not DataRegistry.table("items").has("wild_rose_petal") else "wild_rose_petal"
	var qty: int = _rng.randi_range(int(pk.get("min", 1)), int(pk.get("max", 1)))
	state["p"] = maxi(1, TimeManager.day)

	for p: Player in Player.all:
		if is_instance_valid(p) and p.get_multiplayer_authority() == peer_id and p.inventory != null and not item_id.is_empty():
			p.inventory.give(item_id, qty)
			break

	var fx_tag: String = "puff" if (String(_spec.get("behavior", "")) == "dandelion_puff" and variant >= 2) else "pick"
	_rpc_sync_flora_state.rpc(state, fx_tag, 1.0)


func harvest_hit(source: int) -> void:
	if not multiplayer.is_server() or is_cut() or not _spec.has("harvest"):
		return
	var hitter: Player = null
	for p: Player in Player.all:
		if is_instance_valid(p) and (source == 0 or p.name.to_int() == source or p.get_multiplayer_authority() == source):
			hitter = p
			break
	var held_tool: String = ""
	if hitter != null and hitter.inventory != null:
		held_tool = String(Items.definition(hitter.inventory.active_stack()).get("tool", ""))
	var out_x: float = -1.0 if (hitter != null and hitter.global_position.x < global_position.x) else 1.0
	var hv: Dictionary = _spec["harvest"] as Dictionary
	if held_tool != String(hv.get("tool", "sickle")):
		_rpc_sync_flora_state.rpc(state, "rustle", out_x)
		return
	_apply_server_sickle_cut(out_x)


func cut_with_sickle(from_pos: Vector2) -> void:
	if not multiplayer.is_server() or is_cut() or not _spec.has("harvest"):
		return
	_apply_server_sickle_cut(-1.0 if from_pos.x < global_position.x else 1.0)


func _apply_server_sickle_cut(out_x: float) -> void:
	var rem: int = _hits_left() - 1
	state["hp"] = maxi(0, rem)
	if rem > 0:
		_rpc_sync_flora_state.rpc(state, "sickle_hit", out_x)
		return
	state["c"] = maxi(1, TimeManager.day)
	for p: Player in _inside_players:
		if is_instance_valid(p):
			p.clear_slow(self)
	_inside_players.clear()

	var drops: Array = ((_spec["harvest"] as Dictionary).get("drops", [])) as Array
	var drops_root: Node = get_tree().get_first_node_in_group("drops")
	for d_entry: Variant in drops:
		var dd: Dictionary = d_entry as Dictionary
		if _rng.randf() <= float(dd.get("chance", 1.0)):
			var item_id: String = String(dd.get("id", ""))
			var cnt: int = _rng.randi_range(int(dd.get("min", 1)), int(dd.get("max", 1)))
			if drops_root != null and DataRegistry.table("items").has(item_id):
				var drop: ItemDrop = DROP_SCENE.instantiate() as ItemDrop
				drop.item_id = item_id
				drop.count = cnt
				drop.position = global_position + Vector2(0.0, -6.0)
				drop.launch = Vector2(out_x * _rng.randf_range(18.0, 38.0), _rng.randf_range(-16.0, 16.0))
				drop.rise = 12.0
				drops_root.add_child(drop, true)
	_rpc_sync_flora_state.rpc(state, "sickle_cut", out_x)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_flora_state(new_state: Dictionary, fx: String, dir_x: float) -> void:
	state = new_state
	_refresh_pose(true)
	_trigger_spring(dir_x)
	var bcols: Array = _spec.get("burst_colors", ["#62a665", "#9ad484"]) as Array
	var primary_c: Color = Color(String(bcols[0]))
	var secondary_c: Color = Color(String(bcols[mini(1, bcols.size() - 1)]))

	match fx:
		"puff":
			if field != null and field.has_method("spawn_dandelion_seeds"):
				field.call("spawn_dandelion_seeds", global_position + Vector2(0.0, -16.0), 12)
			Sfx.at(self, "pluck", global_position, -6.0, 0.12)
		"pick":
			if String(_spec.get("behavior", "")) == "dew_pearl" and field != null and field.has_method("spawn_dew_splash"):
				field.call("spawn_dew_splash", global_position + Vector2(0.0, -8.0), 8)
			elif field != null and field.has_method("spawn_cut_burst"):
				field.call("spawn_cut_burst", global_position + Vector2(0.0, -_height * 0.6), 6, primary_c, secondary_c, dir_x)
			Sfx.at(self, "pluck", global_position, -3.0, 0.08)
		"sickle_hit":
			if field != null and field.has_method("spawn_cut_burst"):
				field.call("spawn_cut_burst", global_position + Vector2(0.0, -_height * 0.5), 5, primary_c, secondary_c, dir_x)
			Sfx.at(self, "sickle_cut", global_position, -3.0, 0.06)
		"sickle_cut":
			if field != null and field.has_method("spawn_cut_burst"):
				field.call("spawn_cut_burst", global_position + Vector2(0.0, -_height * 0.5), 11, primary_c, secondary_c, dir_x)
			Sfx.at(self, "sickle_cut", global_position, -1.0, 0.06)
		"rustle":
			if field != null and field.has_method("spawn_petals") and bool(_spec.get("petal_drift", false)):
				field.call("spawn_petals", global_position + Vector2(0.0, -_height * 0.6), 4, primary_c)
