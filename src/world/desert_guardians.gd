class_name DesertGuardians
extends Node
## Host-authoritative director for `QuartzGolem` ("Quarzwächter") in Sonnenquarz-Öde.
## - Spawns 24/7 (completely independent of time of day — never burns in sunlight).
## - Places home spots EXCLUSIVELY on white ground-quartz outcrops (`BiomeBlend.is_quartz_surface`).
## - Routes player harvesting / mining / plant-picking disturbances to nearby `QuartzGolem`s.

const DESERT_CHUNK_X0: int = 19
const DESERT_CHUNK_X1: int = 34
const DESERT_CHUNK_Y0: int = 1
const DESERT_CHUNK_Y1: int = 11
const MAX_ACTIVE: int = 8
const SPAWN_RANGE: float = 440.0
const DESPAWN_RANGE: float = 640.0
const RESPAWN_COOLDOWN: float = 180.0
const TICK_SECONDS: float = 0.65

var world: WorldLevel
var _homes_by_chunk: Dictionary = {} ## Vector2i(chunk) -> Array[Dictionary] {id, pos, variant, dormant}
var _live: Dictionary = {} ## String(home_id) -> QuartzGolem
var _cooldowns: Dictionary = {} ## String(home_id) -> float seconds left
var _tick_left: float = 0.25


static func of(tree: SceneTree) -> DesertGuardians:
	return tree.get_first_node_in_group("desert_guardians") as DesertGuardians


## Alerts every nearby `QuartzGolem` when `player` mines, harvests, picks, pulls, or hits a prop/plant at `at`.
static func notify_disturbance(tree: SceneTree, at: Vector2, player: Node2D, is_rustle: bool = false) -> void:
	if tree == null or player == null or not is_instance_valid(player):
		return
	if not tree.get_multiplayer().is_server():
		return
	for node: Node in tree.get_nodes_in_group("quartz_golems"):
		if is_instance_valid(node) and node.has_method("provoke"):
			node.call("provoke", player, at, is_rustle, true)


func setup(level: WorldLevel, blocked_cells: Dictionary) -> void:
	world = level
	_homes_by_chunk.clear()
	var seed_base: int = level._map.world_seed
	for cy: int in range(DESERT_CHUNK_Y0, DESERT_CHUNK_Y1 + 1):
		for cx: int in range(DESERT_CHUNK_X0, DESERT_CHUNK_X1 + 1):
			var chunk_cell: Vector2i = Vector2i(cx, cy)
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = hash(Vector4i(cx, cy, seed_base, 14923))
			var spots: Array[Dictionary] = _plan_chunk_homes(chunk_cell, rng, blocked_cells)
			if not spots.is_empty():
				_homes_by_chunk[chunk_cell] = spots


func _ready() -> void:
	add_to_group("desert_guardians")


func planned_home_count() -> int:
	var total: int = 0
	for arr_v: Variant in _homes_by_chunk.values():
		total += (arr_v as Array).size()
	return total


func homes_in_chunk(chunk_cell: Vector2i) -> Array:
	return _homes_by_chunk.get(chunk_cell, []) as Array


func all_homes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for arr_v: Variant in _homes_by_chunk.values():
		for h_v: Variant in arr_v as Array:
			out.append(h_v as Dictionary)
	return out


func _plan_chunk_homes(chunk_cell: Vector2i, rng: RandomNumberGenerator, blocked_cells: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base_tile: Vector2i = chunk_cell * WorldLevel.CHUNK
	var want: int = 2 if rng.randf() < 0.42 else 1
	for attempt: int in 42:
		if out.size() >= want:
			break
		var tx: int = base_tile.x + rng.randi_range(3, WorldLevel.CHUNK - 4)
		var ty: int = base_tile.y + rng.randi_range(3, WorldLevel.CHUNK - 4)
		var cell: Vector2i = Vector2i(tx, ty)
		if blocked_cells.has(cell):
			continue
		var pos: Vector2 = Vector2(float(tx) * 16.0 + 8.0, float(ty) * 16.0 + 8.0)
		if not _is_valid_quartz_home(pos, blocked_cells):
			continue
		var too_close: bool = false
		for prev: Dictionary in out:
			if (prev["pos"] as Vector2).distance_to(pos) < 88.0:
				too_close = true
				break
		if too_close:
			continue
		var region_id: int = world._map.region_at(cell)
		var g_variant: int = 0
		if region_id in [33, 34] and rng.randf() < 0.36:
			g_variant = 2 ## Rare Prisma-Wächter in deep Regions 33/34
		elif rng.randf() < 0.42:
			g_variant = 1 ## Warm Mesa-Terracotta & Amber Sun-Quartz
		out.append({
			"id": "qg_%d_%d" % [tx, ty],
			"pos": pos,
			"variant": g_variant,
			"dormant": rng.randf() < 0.55,
		})
	return out


func _is_valid_quartz_home(pos: Vector2, blocked_cells: Dictionary) -> bool:
	# Strictly on white ground-quartz outcrops (`BiomeBlend.is_quartz_surface`)!
	if not BiomeBlend.is_quartz_surface(pos):
		return false
	# Ensure at least 3 of 4 cardinal offsets are also ground quartz so it sits squarely inside a quartz vein patch
	var q_neighbors: int = 0
	for off: Vector2 in [Vector2(10, 0), Vector2(-10, 0), Vector2(0, 10), Vector2(0, -10)]:
		if BiomeBlend.is_quartz_surface(pos + off):
			q_neighbors += 1
	if q_neighbors < 2:
		return false
	var tx: int = floori(pos.x / 16.0)
	var ty: int = floori(pos.y / 16.0)
	if world.coast_tiles(pos) < 4.0:
		return false
	var base_lvl: int = world._relief.level(tx, ty)
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if blocked_cells.has(Vector2i(tx + dx, ty + dy)):
				return false
			if not world._relief.is_land(tx + dx, ty + dy):
				return false
			if world._relief.kind(tx + dx, ty + dy) != Relief.FLOOR or world._relief.level(tx + dx, ty + dy) != base_lvl:
				return false
	if world._rivers != null and not world._rivers.clear_for_prop(pos, 16.0):
		return false
	return true


func _process(delta: float) -> void:
	if world == null or not multiplayer.is_server():
		return
	for hid: String in _cooldowns.keys():
		var rem: float = float(_cooldowns[hid]) - delta
		if rem <= 0.0:
			_cooldowns.erase(hid)
		else:
			_cooldowns[hid] = rem
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK_SECONDS
	_maintain_guardians()


func _maintain_guardians() -> void:
	# Clean dead/freed entries and despawn far-away peaceful guardians
	for hid: String in _live.keys():
		var golem: Node2D = _live[hid] as Node2D
		if golem == null or not is_instance_valid(golem):
			_live.erase(hid)
			continue
		if golem.has_method("is_provoked") and bool(golem.call("is_provoked")):
			continue
		var nearest_d: float = _nearest_player_dist(golem.global_position)
		if nearest_d > DESPAWN_RANGE:
			_live.erase(hid)
			golem.queue_free()

	if _live.size() >= MAX_ACTIVE or Player.all.is_empty():
		return

	# Spawn guardians in loaded desert chunks near any active surface player (day & night!)
	var checked_chunks: Dictionary = {}
	for player: Player in Player.all:
		if not is_instance_valid(player) or player.health.current <= 0.0:
			continue
		if Interiors.slot_at(player.global_position) >= 0 or MineManager.in_mine(player.global_position):
			continue
		var p_chunk: Vector2i = Vector2i(floori(player.global_position.x / (WorldLevel.CHUNK * 16.0)), floori(player.global_position.y / (WorldLevel.CHUNK * 16.0)))
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var cc: Vector2i = p_chunk + Vector2i(dx, dy)
				if checked_chunks.has(cc) or not _homes_by_chunk.has(cc) or not world._chunks.has(cc):
					continue
				checked_chunks[cc] = true
				for spec_v: Variant in _homes_by_chunk[cc] as Array:
					if _live.size() >= MAX_ACTIVE:
						return
					var spec: Dictionary = spec_v as Dictionary
					var hid: String = String(spec["id"])
					if _live.has(hid) or _cooldowns.has(hid):
						continue
					var hpos: Vector2 = spec["pos"] as Vector2
					var d_player: float = _nearest_player_dist(hpos)
					if d_player > SPAWN_RANGE:
						continue
					_spawn_home_guardian(spec)


func _spawn_home_guardian(spec: Dictionary) -> Node2D:
	var hid: String = String(spec["id"])
	var hpos: Vector2 = spec["pos"] as Vector2
	var golem: Node2D = world.spawn_quartz_golem(
		hpos,
		randf() * TAU,
		int(spec.get("variant", 0)),
		bool(spec.get("dormant", false))
	)
	if golem == null:
		return null
	_live[hid] = golem
	var health: HealthComponent = golem.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		health.died.connect(func() -> void:
			_live.erase(hid)
			_cooldowns[hid] = RESPAWN_COOLDOWN
		)
	return golem


func _nearest_player_dist(at: Vector2) -> float:
	var best: float = INF
	for player: Player in Player.all:
		if is_instance_valid(player) and player.health.current > 0.0:
			if Interiors.slot_at(player.global_position) < 0 and not MineManager.in_mine(player.global_position):
				best = minf(best, player.global_position.distance_to(at))
	return best
