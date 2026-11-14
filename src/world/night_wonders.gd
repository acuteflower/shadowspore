class_name NightWonders
extends Node2D
## Host-authoritative director for Meadow night wonders (`docs/wiesenbiom_ausbau_konzept.md` Stufe 6):
##  1. Starfall (`StarCrater`): on clear nights after opening, a bright shooting star streaks across the sky in the
##     compass direction of its impact crater; harvesting yields warm `star_shard` ore, or unharvested craters
##     cool cleanly to dark dawn stone at sunrise (`TimeManager.day_started`).
##  2. `SpiritStag` (*Der Weiße Kronenhirsch*): peaceful ghost-white stag on quiet meadow clearings at night
##     (strictly ZERO hurtbox). Approaching upright startles it into silver mist; approaching while sneaking uncovers
##     `antler_talisman` (plus `star_shard` / `moon_pear`) out of the moss.

const STREAK_WAV: String = "res://assets/audio/meadow_wonders/starfall_streak.wav"
const IMPACT_WAV: String = "res://assets/audio/meadow_wonders/starfall_impact.wav"
const DROP_SCENE: String = "res://src/entities/drops/item_drop.tscn"

var world: WorldLevel
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _next_crater_id: int = 0
var _craters: Dictionary = {} ## int(crater_id) -> StarCrater
var _crater_data: Dictionary = {} ## int(crater_id) -> {id: int, pos: Vector2, state: int}

var _next_stag_id: int = 0
var _stags: Dictionary = {} ## int(stag_id) -> SpiritStag
var _blessed_stags: Dictionary = {} ## int(stag_id) -> true

var _streaks: Array[Dictionary] = [] ## [{id, from_world, target_pos, t, duration}]
var _sky_layer: CanvasLayer
var _sky_canvas: Node2D
var _banner: TownBanner

var _last_starfall_day: int = -1
var _last_stag_day: int = -1
var _dir_clock: float = 4.0
var _drop_serial: int = 0


static func of(tree: SceneTree) -> NightWonders:
	return tree.get_first_node_in_group("night_wonders") as NightWonders


func setup(level: WorldLevel) -> void:
	world = level
	_rng.seed = level._map.world_seed ^ 0x6a91b3 if level != null and level._map != null else 71331


func _ready() -> void:
	add_to_group("night_wonders")
	_build_sky_overlay()
	TimeManager.day_started.connect(_on_day_started)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)


func _build_sky_overlay() -> void:
	_sky_layer = CanvasLayer.new()
	_sky_layer.name = "StarfallSkyLayer"
	_sky_layer.layer = 8
	_sky_layer.follow_viewport_enabled = false
	add_child(_sky_layer)

	_sky_canvas = Node2D.new()
	_sky_canvas.material = Unlit.material()
	_sky_canvas.draw.connect(_draw_sky_streaks)
	_sky_layer.add_child(_sky_canvas)


func active_streak_count() -> int:
	return _streaks.size()


func live_crater_count() -> int:
	return _craters.size()


func crater_node(crater_id: int) -> StarCrater:
	var c: StarCrater = _craters.get(crater_id) as StarCrater
	return c if is_instance_valid(c) else null


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var list: Array = []
	for cid: int in _crater_data:
		list.append(_crater_data[cid])
	if not list.is_empty():
		_rpc_crater_snapshot.rpc_id(peer_id, list)


func _on_day_started(_day: int) -> void:
	if multiplayer.is_server():
		cool_all_craters()


func cool_all_craters() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		_rpc_dawn_cool()
	else:
		_rpc_dawn_cool.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_dawn_cool() -> void:
	for cid: int in _crater_data:
		var rec: Dictionary = _crater_data[cid] as Dictionary
		if int(rec.get("state", 0)) == 0:
			rec["state"] = 2
	for cid_n: int in _craters:
		var node: StarCrater = _craters.get(cid_n) as StarCrater
		if is_instance_valid(node):
			node.cool_at_dawn()


func _process(delta: float) -> void:
	if not _streaks.is_empty():
		var remaining: Array[Dictionary] = []
		for s: Dictionary in _streaks:
			s["t"] = float(s.t) + delta
			if float(s.t) >= float(s.duration):
				_complete_streak(s)
			else:
				remaining.append(s)
		_streaks = remaining
		if _sky_canvas != null:
			_sky_canvas.queue_redraw()
	elif _sky_canvas != null:
		_sky_canvas.queue_redraw()

	if not multiplayer.is_server():
		return
	_dir_clock -= delta
	if _dir_clock <= 0.0:
		_dir_clock = 5.0
		_host_natural_tick()


func _host_natural_tick() -> void:
	if world == null or not world.opening_over or TimeManager.day < 1 or not TimeManager.is_night():
		return
	var rain_amt: float = WeatherManager.current.rain if WeatherManager.current != null else 0.0
	var tod: float = TimeManager.time_of_day

	if _last_starfall_day != TimeManager.day and (tod >= 0.88 or tod <= 0.12) and rain_amt <= 0.2:
		_last_starfall_day = TimeManager.day
		if _rng.randf() < 0.32:
			trigger_starfall()

	if _last_stag_day != TimeManager.day and rain_amt <= 0.25 and _stags.is_empty():
		_last_stag_day = TimeManager.day
		if _rng.randf() < 0.28:
			spawn_spirit_stag()


# ---------------------------------------------------------------- 1. Starfall & StarCrater

func trigger_starfall(forced_target: Vector2 = Vector2.INF) -> Vector2:
	if not multiplayer.is_server():
		return Vector2.INF
	var target: Vector2 = forced_target if forced_target.is_finite() else _find_meadow_night_spot(42.0, 80.0, false)
	if not target.is_finite():
		return Vector2.INF
	_next_crater_id += 1
	var cid: int = _next_crater_id
	var from_world: Vector2 = target + Vector2(-220.0, -340.0)
	_crater_data[cid] = {"id": cid, "pos": target, "state": 0}
	if multiplayer.get_peers().is_empty():
		_rpc_starfall(cid, from_world, target)
	else:
		_rpc_starfall.rpc(cid, from_world, target)
	return target


@rpc("authority", "call_local", "reliable")
func _rpc_starfall(cid: int, from_world: Vector2, target_pos: Vector2) -> void:
	if not _crater_data.has(cid):
		_crater_data[cid] = {"id": cid, "pos": target_pos, "state": 0}
	_streaks.append({
		"id": cid,
		"from_world": from_world,
		"target_pos": target_pos,
		"t": 0.0,
		"duration": 1.05,
	})
	if ResourceLoader.exists(STREAK_WAV):
		var snd: AudioStreamPlayer = AudioStreamPlayer.new()
		snd.stream = load(STREAK_WAV) as AudioStream
		snd.bus = "SFX"
		snd.volume_db = -3.0
		snd.finished.connect(snd.queue_free)
		add_child(snd)
		snd.play()
	if _sky_canvas != null:
		_sky_canvas.queue_redraw()


func _complete_streak(s: Dictionary) -> void:
	var cid: int = int(s.id)
	var target_pos: Vector2 = s.target_pos as Vector2
	var state_val: int = int((_crater_data.get(cid, {}) as Dictionary).get("state", 0))
	_spawn_crater_node(cid, target_pos, state_val)

	if ResourceLoader.exists(IMPACT_WAV):
		var snd: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		snd.stream = load(IMPACT_WAV) as AudioStream
		snd.bus = "SFX"
		snd.volume_db = -1.5
		snd.max_distance = 1400.0
		snd.position = target_pos
		snd.finished.connect(snd.queue_free)
		add_child(snd)
		snd.play()

	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority() and p.global_position.distance_to(target_pos) <= 900.0:
			p._shake = maxf(p._shake, 0.9)


func _spawn_crater_node(cid: int, pos_px: Vector2, state_val: int) -> StarCrater:
	var existing: StarCrater = crater_node(cid)
	if existing != null:
		existing.set_state_mode(state_val)
		return existing
	var node: StarCrater = StarCrater.new()
	node.name = "StarCrater_%d" % cid
	node.setup(self, cid, pos_px, state_val)
	var parent_node: Node2D = world._props if world != null and world._props != null else self
	parent_node.add_child(node)
	_craters[cid] = node
	return node


@rpc("authority", "reliable")
func _rpc_crater_snapshot(list: Array) -> void:
	for rec_v: Variant in list:
		var rec: Dictionary = rec_v as Dictionary
		var cid: int = int(rec.id)
		var pos: Vector2 = rec.pos as Vector2
		var st: int = int(rec.state)
		_crater_data[cid] = rec
		_spawn_crater_node(cid, pos, st)


func request_harvest_crater(cid: int) -> void:
	if multiplayer.is_server():
		_host_harvest_crater(cid, multiplayer.get_unique_id())
	else:
		_rpc_req_harvest.rpc_id(1, cid)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_req_harvest(cid: int) -> void:
	if multiplayer.is_server():
		_host_harvest_crater(cid, multiplayer.get_remote_sender_id())


func _host_harvest_crater(cid: int, peer_id: int) -> void:
	if not multiplayer.is_server() or not _crater_data.has(cid):
		return
	var rec: Dictionary = _crater_data[cid] as Dictionary
	if int(rec.state) != 0:
		return
	var pos: Vector2 = rec.pos as Vector2
	var who: Player = _player_by_peer(peer_id)
	if who == null or who.health == null or who.health.current <= 0.0:
		return
	if who.global_position.distance_to(pos) > 64.0:
		return
	rec["state"] = 1
	_award_xp_and_reveal(pos, 18, 10.0)
	for i: int in 3:
		var ang: float = (float(i) / 3.0) * TAU + _rng.randf_range(-0.25, 0.25)
		_spawn_drop(pos + Vector2(0.0, -4.0), "star_shard", 1, ang, 38.0, 75.0)
	if multiplayer.get_peers().is_empty():
		_rpc_crater_state(cid, 1)
	else:
		_rpc_crater_state.rpc(cid, 1)


@rpc("authority", "call_local", "reliable")
func _rpc_crater_state(cid: int, state_val: int) -> void:
	if _crater_data.has(cid):
		(_crater_data[cid] as Dictionary)["state"] = state_val
	var node: StarCrater = crater_node(cid)
	if node != null:
		node.set_state_mode(state_val)


func _draw_sky_streaks() -> void:
	if _streaks.is_empty():
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var xf: Transform2D = vp.get_canvas_transform()
	var vp_rect: Rect2 = vp.get_visible_rect()
	var vp_size: Vector2 = vp_rect.size if vp_rect.size.x > 10.0 else Vector2(640.0, 360.0)
	var safe_rect: Rect2 = Rect2(Vector2(18.0, 18.0), vp_size - Vector2(36.0, 36.0))

	for s: Dictionary in _streaks:
		var k: float = clampf(float(s.t) / maxf(float(s.duration), 0.01), 0.0, 1.0)
		var ease_k: float = k * (0.65 + 0.35 * k)
		var from_w: Vector2 = s.from_world as Vector2
		var targ_w: Vector2 = s.target_pos as Vector2
		var head_scr: Vector2 = xf * from_w.lerp(targ_w, ease_k)
		var tail_scr: Vector2 = xf * from_w.lerp(targ_w, maxf(0.0, ease_k - 0.26))
		_sky_canvas.draw_line(tail_scr, head_scr, Color(0.72, 0.45, 1.0, 0.42), 5.0)
		_sky_canvas.draw_line(tail_scr, head_scr, Color(1.0, 0.78, 0.38, 0.85), 2.4)
		_sky_canvas.draw_line(tail_scr.lerp(head_scr, 0.35), head_scr, Color(1.0, 0.98, 0.90, 1.0), 1.2)
		_sky_canvas.draw_circle(head_scr, 3.2, Color(1.0, 0.96, 0.86, 1.0))

		# Spark trail particles along the streak
		var seg_dir: Vector2 = tail_scr - head_scr
		for sp: int in 7:
			var frac: float = float(sp + 1) / 8.0
			var jitter: Vector2 = Vector2(sin(k * 28.0 + float(sp) * 2.1), cos(k * 22.0 + float(sp) * 1.7)) * (1.8 + frac * 3.0)
			var pt: Vector2 = (head_scr + seg_dir * frac + jitter).round()
			_sky_canvas.draw_rect(Rect2(pt, Vector2(1.0, 1.0)), Color(1.0, 0.88, 0.56, 1.0 - frac * 0.75))

		# Edge-of-screen compass glint pointing in the exact direction of impact when off-screen
		var targ_scr: Vector2 = xf * targ_w
		if not safe_rect.has_point(targ_scr):
			var center: Vector2 = vp_size * 0.5
			var dir: Vector2 = (targ_scr - center).normalized()
			var edge_pt: Vector2 = center + dir * minf(vp_size.x, vp_size.y) * 0.42
			edge_pt = edge_pt.clamp(safe_rect.position, safe_rect.end)
			var pulse_a: float = 0.65 + 0.35 * sin(k * 16.0)
			_sky_canvas.draw_circle(edge_pt, 3.5, Color(1.0, 0.84, 0.42, pulse_a))


# ---------------------------------------------------------------- 2. SpiritStag (Der Weiße Kronenhirsch)

func spawn_spirit_stag(forced_pos: Vector2 = Vector2.INF) -> SpiritStag:
	if not multiplayer.is_server():
		return null
	var pos: Vector2 = forced_pos if forced_pos.is_finite() else _find_meadow_night_spot(36.0, 66.0, true)
	if not pos.is_finite():
		return null
	_next_stag_id += 1
	var sid: int = _next_stag_id
	if multiplayer.get_peers().is_empty():
		_rpc_spawn_stag(sid, pos)
	else:
		_rpc_spawn_stag.rpc(sid, pos)
	return _stags.get(sid) as SpiritStag


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_stag(sid: int, pos_px: Vector2) -> void:
	var existing: SpiritStag = _stags.get(sid) as SpiritStag
	if existing != null and is_instance_valid(existing):
		return
	var stag: SpiritStag = SpiritStag.new()
	stag.name = "SpiritStag_%d" % sid
	stag.setup(self, sid, pos_px)
	var parent_node: Node2D = world._props if world != null and world._props != null else self
	parent_node.add_child(stag)
	stag.tree_exiting.connect(func() -> void: _stags.erase(sid))
	_stags[sid] = stag


func host_set_stag_state(sid: int, new_state: int, west: bool, peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		_rpc_stag_state(sid, new_state, west, peer_id)
	else:
		_rpc_stag_state.rpc(sid, new_state, west, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_stag_state(sid: int, new_state: int, west: bool, peer_id: int) -> void:
	var stag: SpiritStag = _stags.get(sid) as SpiritStag
	if stag != null and is_instance_valid(stag):
		stag.apply_state(new_state, west, peer_id)


func host_complete_stag_blessing(sid: int, peer_id: int) -> void:
	if not multiplayer.is_server() or _blessed_stags.has(sid):
		return
	var stag: SpiritStag = _stags.get(sid) as SpiritStag
	if stag == null or not is_instance_valid(stag):
		return
	_blessed_stags[sid] = true
	var pos: Vector2 = stag.global_position
	var who: Player = _player_by_peer(peer_id)
	var already_owns: bool = false
	if who != null and who.inventory != null:
		already_owns = who.inventory.count_item("antler_talisman") > 0 or TalismanRules.worn_ids(who.inventory.equipment).has("antler_talisman")

	if not already_owns and DataRegistry.table("items").has("antler_talisman"):
		_spawn_drop(pos + Vector2(-4.0, 2.0), "antler_talisman", 1, PI * 0.42, 34.0, 95.0)
		_spawn_drop(pos + Vector2(6.0, 2.0), "star_shard", 1, PI * 0.62, 36.0, 72.0)
	else:
		_spawn_drop(pos + Vector2(-6.0, 2.0), "star_shard", 2, PI * 0.40, 34.0, 76.0)
		_spawn_drop(pos + Vector2(6.0, 2.0), "moon_pear", 1, PI * 0.65, 32.0, 68.0)

	_award_xp_and_reveal(pos, 24, 12.0)
	host_set_stag_state(sid, SpiritStag.State.BLESS_VANISH, stag.face_west, peer_id)
	if multiplayer.get_peers().is_empty():
		_rpc_stag_banner(peer_id)
	else:
		_rpc_stag_banner.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_stag_banner(peer_id: int) -> void:
	if multiplayer.get_unique_id() != peer_id:
		return
	if _banner == null:
		_banner = TownBanner.new()
		add_child(_banner)
	_banner.show_banner({
		"header": "NACHTWUNDER",
		"title": "DER WEISSE KRONENHIRSCH",
		"sub": "EIN VERBORGENES RELIKT AUS DEM MOOS",
		"color": Color("2b4c59"),
		"emblem": -1,
	})


# ---------------------------------------------------------------- Helpers

func _find_meadow_night_spot(min_tiles: float, max_tiles: float, avoid_enemies: bool) -> Vector2:
	if world == null:
		return Vector2.INF
	var living: Array[Player] = []
	for p: Player in Player.all:
		if is_instance_valid(p) and p.health != null and p.health.current > 0.0:
			living.append(p)
	if living.is_empty():
		return Vector2.INF

	var anchor_p: Player = living[_rng.randi() % living.size()]
	var anchor_tile: Vector2 = anchor_p.global_position / 16.0
	var town_center: Vector2 = world._town_node.center if world._town_node != null else Vector2(-99999.0, -99999.0)
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies") if avoid_enemies else []

	for _attempt: int in 80:
		var ang: float = _rng.randf() * TAU
		var dist_t: float = _rng.randf_range(min_tiles, max_tiles)
		var tile: Vector2i = Vector2i((anchor_tile + Vector2.from_angle(ang) * dist_t).round())
		if tile.x < 80 or tile.y < 80 or tile.x >= RegionMap.WORLD_TILES - 80 or tile.y >= RegionMap.WORLD_TILES - 80:
			continue
		if world._biome_at(tile) != "meadow":
			continue
		var px: Vector2 = Vector2(tile) * 16.0 + Vector2(8.0, 8.0)
		if px.distance_to(town_center) < 48.0 * 16.0:
			continue
		if world._rivers != null and (not world._rivers.clear_for_prop(px, 24.0) or world._rivers.depth_amount(px) >= 0.0):
			continue
		if world._relief != null and not world._relief.flat_around(px, 20.0):
			continue
		if world._generator != null and world._generator.blocked_cells.has(tile):
			continue
		var safe_from_enemies: bool = true
		if avoid_enemies:
			for e_node: Node in enemies:
				if is_instance_valid(e_node) and e_node is Node2D and (e_node as Node2D).global_position.distance_to(px) < 220.0:
					safe_from_enemies = false
					break
		if safe_from_enemies:
			return px
	return Vector2.INF


func _award_xp_and_reveal(origin: Vector2, xp_amt: int, reveal_cells: float) -> void:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.health != null and p.health.current > 0.0 and p.global_position.distance_to(origin) <= 260.0 and p.progress != null:
			p.progress.award(0, xp_amt)
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		discovery.reveal_disc(origin / 16.0, reveal_cells)


func _spawn_drop(origin: Vector2, item_id: String, cnt: int, angle: float, speed: float, pop_v: float) -> void:
	var container: Node = get_tree().get_first_node_in_group("drops")
	if container == null:
		return
	var drop: ItemDrop = (load(DROP_SCENE) as PackedScene).instantiate() as ItemDrop
	_drop_serial += 1
	drop.name = "WonderDrop_%d" % _drop_serial
	drop.item_id = item_id
	drop.count = cnt
	drop.position = origin
	drop.launch = Vector2.from_angle(angle) * speed
	drop.rise = 10.0
	drop.pop = pop_v
	drop.life = 300.0
	container.add_child(drop)


func _player_by_peer(peer_id: int) -> Player:
	for p: Player in Player.all:
		if p.name.to_int() == peer_id:
			return p
	return null
