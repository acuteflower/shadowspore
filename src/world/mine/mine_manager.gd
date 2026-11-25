class_name MineManager
extends Node2D
## The mine: a stack of fixed levels far outside the 1100 x 1100 tile world (see docs/mine.md). Like the interiors every level lives in a slot of its own
## (`origin`), the same on every peer, and what depends on where a player stands is decided by the position (`level_at`): the world is streamed around
## the mine's entrance (`Interiors.outer`), the camera stays on the level, the zone's tint replaces the day's, enemies path on the level's floor.
## The classification is static so any code can ask "is this point in the mine" without a node.

const SLOT: float = PocketSpace.LARGE_SLOT ## 5600.0 (350 tiles): wider than the biggest level (304)
const MARGIN: float = 368.0 ## centers max 304-tile level (4864 px) inside its 5600x5600 PocketSpace slot
const MAX_LEVELS: int = 32 ## uses PocketSpace.Lane.LARGE slots 0..31 (all x, y < -16000)
const X0: float = PocketSpace.LARGE_ORIGIN.x + MARGIN
const Y0: float = PocketSpace.LARGE_ORIGIN.y + MARGIN
const TILE: float = 16.0
const PREFETCH_RANGE: float = 640.0 ## px: how close she must come to the gate or the stairs down for the next layout to be made

var world_seed: int = 0
var entrance: Vector2 = Vector2.ZERO ## where the world outside is while a player is in the mine (the mine's door), world px
var _player: Player
var _view_level: int = -1
var state: Dictionary = {} ## "chest:<level>:<tile>" -> 1 ... what has changed in the levels (opened chests; later mined rocks, cleared rooms): the host decides, everyone keeps the table
var _layouts: Dictionary = {} ## level -> MineLayout (kept: small, and the generator is deterministic anyway)
var _levels: Dictionary = {} ## level -> MineLevel (built while players are in it, freed `unload_seconds` after the last one left)
var _prefetch_clock: float = 0.0 ## counts down to the next `_prefetch_near_player`


func _ready() -> void:
	add_to_group("mines")
	name = "Mines"
	y_sort_enabled = true
	Terrain.patches.append(self)
	add_child(MineAtmosphere.new())
	add_child(MineEncounterDirector.new())
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void:
			if NetworkManager.rpc_ready(self):
				_rpc_snapshot.rpc_id(id, state))
	_register_pockets(&"")


func _exit_tree() -> void:
	Terrain.patches.erase(self)
	for lvl: int in range(1, MAX_LEVELS + 1):
		PocketSpace.unregister_pocket(StringName("mine_%d" % lvl))


func _register_pockets(parent_zone: StringName) -> void:
	for lvl: int in range(1, MAX_LEVELS + 1):
		PocketSpace.register_pocket(StringName("mine_%d" % lvl), PocketSpace.slot_rect(PocketSpace.Lane.LARGE, lvl - 1), parent_zone)


## `Terrain.patches`: the floor of the mine (slate rock, plus shallow cave puddles in wet rooms).
func surface_at(pos: Vector2) -> String:
	var lvl: int = level_at(pos)
	if lvl <= 0:
		return ""
	if _layouts.has(lvl):
		var l: MineLayout = _layouts[lvl] as MineLayout
		var local: Vector2 = pos - origin(lvl)
		var cell: Vector2i = MineLayout.chunk_of(local)
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				var props: Array = l.chunk_props.get(cell + Vector2i(dx, dy), []) as Array
				for entry: Dictionary in props:
					var kind: String = String(entry.get("kind", ""))
					if kind == "puddle_a" or kind == "puddle_b":
						var rx: float = 20.0 if kind == "puddle_a" else 13.0
						var ry: float = 9.0 if kind == "puddle_a" else 6.5
						var ex: float = (local.x - float(entry.get("x", 0.0))) / rx
						var ey: float = (local.y - float(entry.get("y", 0.0))) / ry
						if ex * ex + ey * ey <= 1.0:
							return "puddle"
	return "mine_stone"


func setup(seed_value: int) -> void:
	world_seed = seed_value


# ---------- where is what (static: no node needed) ----------

## The level (1 = the first) a position lies in, -1 for everything else (the open world, the interiors).
static func level_at(pos: Vector2) -> int:
	var hit: Vector2i = PocketSpace.locate(pos)
	if hit.x != PocketSpace.Lane.LARGE:
		return -1
	return hit.y + 1 if hit.y >= 0 and hit.y < MAX_LEVELS else -1


static func in_mine(pos: Vector2) -> bool:
	return level_at(pos) > 0


## Top left of a level's tile (0, 0) in world px.
static func origin(level: int) -> Vector2:
	if level < 1 or level > MAX_LEVELS:
		push_error("MineManager: level %d out of range [1..%d]" % [level, MAX_LEVELS])
		return Vector2.INF
	var slot_pos: Vector2 = PocketSpace.slot_origin(PocketSpace.Lane.LARGE, level - 1)
	return slot_pos + Vector2(MARGIN, MARGIN) if slot_pos.is_finite() else Vector2.INF


static func config() -> Dictionary:
	return DataRegistry.table("mine")


## The zone of a level (data/mine.json "zones"); levels below the last planned one keep the last zone.
static func zone(level: int) -> Dictionary:
	var zones: Array = config().get("zones", []) as Array
	for entry: Dictionary in zones:
		if level >= int(entry.from) and level <= int(entry.to):
			return entry
	return zones[zones.size() - 1] as Dictionary if level > 0 and not zones.is_empty() else {}


## Side length of a level in tiles: 88 on level 1 growing geometrically to 304 on level 20, a multiple of the cell size.
## The mine is always night: the light that depends on the time of day (night lights, glow sheets) asks here how dark it is where it stands.
static func night_at(node: Node2D, amount: float) -> float:
	if node.is_inside_tree():
		var p: Vector2 = node.global_position
		if in_mine(p) or PocketSpace.locate(p).x == PocketSpace.Lane.DUNGEON:
			return 1.0
	return amount


## How much tougher an enemy of this level is than the one in data/enemies.json.
static func health_scale(level: int) -> float:
	return 1.0 + float(config().enemies.health_per_level) * float(level - 1)


static func damage_scale(level: int) -> float:
	return 1.0 + float(config().enemies.damage_per_level) * float(level - 1)


static func edge_tiles(level: int) -> int:
	var world: Dictionary = config().get("world", {}) as Dictionary
	var first: float = float(world.get("edge_first", 88))
	var last: float = float(world.get("edge_last", 304))
	var planned: int = int(world.get("levels_planned", 20))
	var cell: int = int(world.get("cell_tiles", 8))
	var t: float = clampf(float(level - 1) / float(maxi(planned - 1, 1)), 0.0, 1.0)
	return maxi(int(roundf(first * pow(last / first, t) / float(cell))), 1) * cell


static func edge_px(level: int) -> float:
	return edge_tiles(level) * TILE


## Tint of a level (the zone's ambient colour).
static func ambient_of(level: int) -> Color:
	var a: Array = zone(level).get("ambient", [0.4, 0.4, 0.4, 1.0]) as Array
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


# ---------- queries for the rest of the game ----------

## The tint while the local player is in the mine (alpha 0 = she is outside).
func ambient_color() -> Color:
	var player: Player = _local()
	var level: int = level_at(player.global_position) if player != null else -1
	return ambient_of(level) if level > 0 else Color(0, 0, 0, 0)


## Where something in the mine stands as far as the open world is concerned: the mine's door.
func world_position(_pos: Vector2) -> Vector2:
	return entrance


func local_inside() -> bool:
	var player: Player = _local()
	return player != null and in_mine(player.global_position)


## Enemy navigation: is there floor at this point? (Rock and everything outside the level: no.)
func navigation_floor(point: Vector2) -> bool:
	var level: int = level_at(point)
	return level > 0 and layout(level).is_floor_px(point - origin(level))


## The generated shape of a level (made once, the same on every peer).
func layout(level: int) -> MineLayout:
	if not _layouts.has(level):
		_layouts[level] = MineGenerator.new().generate(world_seed, level)
	return _layouts[level] as MineLayout


func level_node(level: int) -> MineLevel:
	return _levels.get(level) as MineLevel


## The built level, made now if it does not exist yet.
func ensure_level(level: int) -> MineLevel:
	if not _levels.has(level):
		var built: MineLevel = MineLevel.new()
		add_child(built)
		built.setup(level, layout(level))
		_levels[level] = built
	return _levels[level] as MineLevel


func set_entrance(pos: Vector2, parent_zone: StringName = &"") -> void:
	entrance = pos
	if parent_zone == &"" and is_inside_tree():
		var world: Node = get_tree().get_first_node_in_group("world")
		if world != null and world.has_method("director"):
			var dir: ZoneDirector = world.call("director") as ZoneDirector
			if dir != null and dir.atlas != null and pos.is_finite():
				parent_zone = dir.atlas.zone_at(dir.continent_id, pos)
	_register_pockets(parent_zone)


## Dev entry (and later the stairs): puts a player in the entry room of a level. The world outside stays where she came from (`entrance`).
func enter(player: Player, level: int) -> void:
	var l: MineLayout = layout(level)
	if not in_mine(player.global_position):
		set_entrance(player.global_position)
	ensure_level(level).build_at(l.entry)
	player.request_teleport(origin(level) + l.tile_center(l.entry))
	apply_view(player)


## Dev exit: back to where she came from.
func leave(player: Player) -> void:
	if entrance != Vector2.ZERO:
		player.request_teleport(entrance)
	apply_view(player)


# ---------- the ways between the levels ----------

## Where she arrives: "entry" (the hall with the stairs up), "exit" (below the stairs down) or "station" (before the lift), in world px.
func arrival(level: int, spot: String) -> Vector2:
	var l: MineLayout = layout(level)
	match spot:
		"exit":
			return origin(level) + l.tile_center(l.exit_stairs + Vector2i(0, 2))
		"station":
			return origin(level) + l.tile_center(l.station_winch + Vector2i(0, 2))
	return origin(level) + l.tile_center(l.entry)


## Local player: to `level` (0 = the gate on the surface) with the iris of the doors; `spot` as in `arrival`.
func travel(player: Player, level: int, spot: String = "entry") -> void:
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if interiors != null:
		await interiors.transit(player, func() -> void: _arrive(player, level, spot))
	else:
		_arrive(player, level, spot)


func _arrive(player: Player, level: int, spot: String) -> void:
	if level <= 0:
		if entrance != Vector2.ZERO:
			player.request_teleport(entrance)
			player.facing = Vector2.DOWN
		apply_view(player)
		return
	var at: Vector2 = arrival(level, spot)
	ensure_level(level).build_at(Vector2i((at - origin(level)) / TILE))
	player.request_teleport(at)
	player.facing = Vector2.DOWN
	apply_view(player)
	if player.quests != null: ## the quests may ask for it later: flags for the mine, each level and each lift
		player.quests.set_flag("mine_entered")
		player.quests.set_flag("mine_level_%d" % level)
	if multiplayer.is_server():
		_host_depth(level)
	else:
		_rpc_depth.rpc_id(1, level)


func deepest() -> int:
	return int(state.get("deepest", 0))


func station_unlocked(level: int) -> bool:
	return state.has("station:%d" % level)


## The levels whose lift is mended, ascending.
func unlocked_stations() -> Array[int]:
	var found: Array[int] = []
	for key: String in state:
		if key.begins_with("station:"):
			found.append(key.get_slice(":", 1).to_int())
	found.sort()
	return found


@rpc("any_peer", "call_remote", "reliable")
func _rpc_depth(level: int) -> void:
	if multiplayer.is_server():
		_host_depth(level)


func _host_depth(level: int) -> void:
	if level > deepest() and level <= MAX_LEVELS:
		set_state("deepest", level)


## Local player mended the lift.
func request_station(level: int) -> void:
	if multiplayer.is_server():
		_host_station(level, multiplayer.get_unique_id())
	else:
		_rpc_station.rpc_id(1, level)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_station(level: int) -> void:
	if multiplayer.is_server():
		_host_station(level, multiplayer.get_remote_sender_id())


func _host_station(level: int, peer: int) -> void:
	if level < 1 or level > MAX_LEVELS or station_unlocked(level):
		return
	var player: Player = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer):
			player = node as Player
	var l: MineLayout = layout(level)
	if player == null or player.health.current <= 0.0 or player.global_position.distance_to(origin(level) + l.tile_center(l.station_winch)) > 96.0:
		return
	set_state("station:%d" % level, 1)


func local_player() -> Player:
	return _local()


func _local() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = null
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node.is_multiplayer_authority():
				_player = node as Player
	return _player


func _process(delta: float) -> void:
	_stream_levels(delta)
	_prefetch_clock -= delta
	if _prefetch_clock <= 0.0:
		_prefetch_clock = 0.5
		_prefetch_near_player()
	var player: Player = _local()
	if player == null:
		return
	var level: int = level_at(player.global_position)
	if level != _view_level:
		var left: bool = _view_level > 0 and level < 1
		_view_level = level
		if level > 0 or left:
			apply_view(player)


## level -> Array[Vector2] (level px): where the players are, per level.
func players_present() -> Dictionary:
	var present: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("players"):
		var pos: Vector2 = (node as Node2D).global_position
		var level: int = level_at(pos)
		if level > 0:
			if not present.has(level):
				present[level] = [] as Array[Vector2]
			(present[level] as Array[Vector2]).append(pos - origin(level))
	return present


## Every peer builds the levels its players are in (the host needs them for the enemies, a client for its own view) and frees the ones nobody is in.
func _stream_levels(delta: float) -> void:
	var present: Dictionary = players_present()
	for level: int in present:
		ensure_level(level).stream(present[level] as Array[Vector2])
	var wait: float = float((config().get("world", {}) as Dictionary).get("unload_seconds", 60))
	for level: int in _levels.keys():
		if not present.has(level):
			var built: MineLevel = _levels[level] as MineLevel
			built.idle += delta
			if built.idle > wait:
				built.queue_free()
				_levels.erase(level)


## A layout is one synchronous generation (deterministic, cached for good), so its cost is only moved earlier: level 1 is made when a player comes near
## the gate, the next level when she comes near the stairs down of the level she is in. Half a second apart, from the local player only.
var _pending_layouts: Dictionary = {} ## level -> {"job": Jobs.Job, "seed": int}


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		for entry_v: Variant in _pending_layouts.values():
			var entry: Dictionary = entry_v as Dictionary
			var job: Jobs.Job = entry.get("job") as Jobs.Job
			if job != null:
				Jobs.cancel(job)
				Jobs.wait(job)
		_pending_layouts.clear()


func _prefetch_layout(level: int) -> void:
	if _layouts.has(level) or level < 1 or level > MAX_LEVELS:
		return
	var req_seed: int = world_seed
	var existing: Dictionary = _pending_layouts.get(level, {}) as Dictionary
	if not existing.is_empty():
		if int(existing.get("seed", -1)) == req_seed:
			return
		var old_job: Jobs.Job = existing.get("job") as Jobs.Job
		if old_job != null:
			Jobs.cancel(old_job)
	var work: Callable = func() -> MineLayout:
		return MineGenerator.new().generate(req_seed, level)
	var on_done: Callable = func(result: Variant) -> void:
		var cur: Dictionary = _pending_layouts.get(level, {}) as Dictionary
		if int(cur.get("seed", -1)) == req_seed:
			_pending_layouts.erase(level)
		if is_instance_valid(self) and world_seed == req_seed and result is MineLayout and not _layouts.has(level):
			_layouts[level] = result
	var on_discard: Callable = func() -> void:
		var cur: Dictionary = _pending_layouts.get(level, {}) as Dictionary
		if int(cur.get("seed", -1)) == req_seed:
			_pending_layouts.erase(level)
	var job: Jobs.Job = Jobs.run(work, on_done, Jobs.Prio.HIGH, on_discard)
	if job == null:
		if not _layouts.has(level):
			layout(level)
	elif job.state != Jobs.State.DELIVERED:
		_pending_layouts[level] = {"job": job, "seed": req_seed}


func _prefetch_near_player() -> void:
	var player: Player = _local()
	if player == null:
		return
	var at: Vector2 = player.global_position
	for gate: Node in get_tree().get_nodes_in_group("mine_gates"):
		if (gate as Node2D).global_position.distance_to(at) < PREFETCH_RANGE:
			_prefetch_layout(1)
			break
	var level: int = level_at(at)
	if level > 0 and level < MAX_LEVELS:
		var l: MineLayout = layout(level)
		var stairs: Vector2 = origin(level) + l.tile_center(l.exit_stairs) ## the stairs down of this level
		if stairs.distance_to(at) < PREFETCH_RANGE:
			_prefetch_layout(level + 1)


## The camera stays on the level while a player is in it; outside it is free again (the interiors do the same for their rooms).
func apply_view(player: Player) -> void:
	var camera: Camera2D = player.get("_camera") as Camera2D
	if camera == null:
		return
	var level: int = level_at(player.global_position)
	if level > 0:
		var o: Vector2 = origin(level)
		var edge: float = edge_px(level)
		camera.limit_left = int(o.x - 64.0)
		camera.limit_top = int(o.y - 64.0)
		camera.limit_right = int(o.x + edge + 64.0)
		camera.limit_bottom = int(o.y + edge + 64.0)
	else:
		camera.limit_left = -10000000
		camera.limit_top = -10000000
		camera.limit_right = 10000000
		camera.limit_bottom = 10000000
	camera.reset_smoothing()


# ---------- what has changed (host decides, everyone keeps the table) ----------

func is_set(key: String) -> bool:
	return state.has(key)


func export_state() -> Dictionary:
	return state.duplicate()


func import_state(data: Dictionary) -> void:
	state.clear()
	for key: Variant in data: ## a save file turns the counts into floats
		state[String(key)] = int(data[key])


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(data: Dictionary) -> void:
	state = data


## Host: sets an entry of the table for everyone (0 removes it).
func set_state(key: String, value: int) -> void:
	if not multiplayer.is_server():
		return
	if NetworkManager.rpc_ready(self):
		_rpc_set.rpc(key, value)
	else:
		_rpc_set(key, value)


@rpc("authority", "call_local", "reliable")
func _rpc_set(key: String, value: int) -> void:
	if value == 0:
		state.erase(key)
	else:
		state[key] = value
	if key.begins_with("chest:"):
		for chest: Node in get_tree().get_nodes_in_group("mine_chests"):
			if (chest as MineChest).key == key:
				(chest as MineChest).opened()


## Local player pressed E at a chest.
func request_chest(key: String) -> void:
	if multiplayer.is_server():
		_host_chest(key, multiplayer.get_unique_id())
	elif NetworkManager.rpc_ready(self):
		_rpc_chest.rpc_id(1, key)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_chest(key: String) -> void:
	if multiplayer.is_server():
		_host_chest(key, multiplayer.get_remote_sender_id())


func _host_chest(key: String, peer: int) -> void:
	if state.has(key):
		return
	var player: Player = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer):
			player = node as Player
	var chest: MineChest = null
	for node: Node in get_tree().get_nodes_in_group("mine_chests"):
		if (node as MineChest).key == key:
			chest = node as MineChest
	if player == null or chest == null or player.health.current <= 0.0 or chest.reach_distance(player.global_position) > Interactable.INTERACT_RANGE + 8.0:
		return
	var level: int = key.get_slice(":", 1).to_int()
	var loot: Dictionary = config().get("chests", {}) as Dictionary
	var span: Array = loot.get("copper", [40, 110]) as Array
	var scale: float = 1.0 + float(loot.get("per_level", 0.15)) * float(level - 1)
	player.progress.award(int(float(randi_range(int(span[0]), int(span[1]))) * scale), int(loot.get("xp", 6)))
	(load("res://src/components/drop_component.gd") as GDScript).call("spawn_drops", get_tree(), loot.get("items", []) as Array, chest.global_position + Vector2(0, 6)) ## by path at run time: a direct reference would make this script load DropComponent (and its scenes) before the rest of the game is ready
	set_state(key, 1)
