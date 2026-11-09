class_name PlantSowing
extends Node
## Seed flight (docs/plant_life.md): every sunrise the host lets some of the loaded plants that carry a `sow` block in data/plants.json
## (wisp seed, spark poppy, moonbells ...) scatter a seed. It flies a short arc and a young plant of the same kind stands where it
## lands: the meadow changes slowly. A sown plant grows for a few days, lives `sow.lifespan` days and then withers, so nothing piles up.
## Also here: the Fangblume (`snapper`) that creeps up to the dark edge of the town's light (`_edge_round`), where it stays until the
## light grows over it.
##
## State is `sown`: cell -> {"k" kind, "v" variant, "d" day sown, "e" 1 = edge snapper (no lifespan)}. The host decides and tells every
## peer with `_rpc_sow` / `_rpc_wither`; a joining peer gets `_rpc_snapshot`; the save keeps it (`export` / `import_saved`).
## Sown plants are ordinary `WorldProp`s of their chunk (they go with it), so picking, harvesting and regrowing work as for generated ones.
const MAX_PER_CHUNK: int = 10
const MAX_TOTAL: int = 260
const FLIGHT_TIME: float = 1.2
const GROW_DAYS: float = 4.0 ## a sown plant is 60 % size at first and full size after this many days
const EDGE_MAX: int = 10 ## edge snappers the town may have at most
const EDGE_BAND: Vector2 = Vector2(10.0, 44.0) ## px outside the light's rim where they take root

var sown: Dictionary = {}
var level: WorldLevel
var _pending: Dictionary = {} ## cells whose seed is still in the air


func setup(world: WorldLevel) -> void:
	level = world
	name = "PlantSowing"


func _ready() -> void:
	TimeManager.day_started.connect(_on_day) ## every peer: the young plants grow; the host also sows
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _rpc_snapshot.rpc_id(id, sown))


# ------------------------------------------------------------------ the day
func _on_day(day: int) -> void:
	if multiplayer.is_server():
		_wither_round(day)
		_sow_round(day)
		_edge_round(day)
	_refresh_sizes()


func _sow_round(day: int) -> void:
	var wet: bool = Moisture.is_wet_day(day)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([level._map.world_seed, day, 5501])
	var parents: Array[WorldProp] = []
	for cell: Vector2i in level._things:
		var thing: WorldProp = level._things[cell] as WorldProp
		if is_instance_valid(thing) and thing.spec().has("sow"):
			parents.append(thing)
	for thing: WorldProp in parents:
		if sown.size() >= MAX_TOTAL:
			return
		if thing.state.has("p") or thing.is_depleted():
			continue ## a picked plant has no seed left
		var spec: Dictionary = thing.spec().get("sow", {}) as Dictionary
		var chance: float = float(spec.get("chance", 0.2)) * (1.5 if wet else 1.0)
		var damp: float = level._generator.damp_at(thing.position / 16.0)
		chance *= lerpf(0.4, 1.0, smoothstep(0.1, 0.45, damp)) ## dry ground lets few seeds take
		if rng.randf() >= chance:
			continue
		var reach: float = float(spec.get("range", 4))
		var target: Vector2i = Vector2i((thing.position / 16.0 + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, reach)).floor())
		if cell_ok(target):
			_rpc_sow.rpc(target, thing.kind, thing.variant, day, thing.global_position + Vector2(0, -float((thing.spec().height as Array)[thing.variant]) * 0.8), false)


## Edge snappers: a few Fangblumen take root just outside the town's light, a bit more of them as the town grows.
func _edge_round(day: int) -> void:
	var town: TownManager = level._town_node
	if town == null or not town.founded:
		return
	var edge_count: int = 0
	for entry: Variant in sown.values():
		if int((entry as Dictionary).get("e", 0)) == 1:
			edge_count += 1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([level._map.world_seed, day, 8803])
	var circles: Array[Vector3] = town.lit_circles()
	if circles.is_empty() or edge_count >= EDGE_MAX:
		return
	for _i: int in 3:
		var circle: Vector3 = circles[rng.randi() % circles.size()]
		var at: Vector2 = Vector2(circle.x, circle.y) + Vector2.from_angle(rng.randf() * TAU) * (circle.z + rng.randf_range(EDGE_BAND.x, EDGE_BAND.y))
		var cell: Vector2i = Vector2i((at / 16.0).floor())
		var depth: float = town.light_depth(PropGenerator.position_of(cell))
		if depth > -EDGE_BAND.x * 0.5 or depth < -EDGE_BAND.y - 16.0:
			continue
		if cell_ok(cell):
			_rpc_sow.rpc(cell, "snapper", rng.randi() % 3, day, Vector2.ZERO, true)
			return


func _wither_round(day: int) -> void:
	for cell: Vector2i in sown.keys():
		var entry: Dictionary = sown[cell] as Dictionary
		var gone: bool = false
		if int(entry.get("e", 0)) == 1:
			var town: TownManager = level._town_node
			gone = town != null and town.founded and town.light_depth(PropGenerator.position_of(cell)) > 6.0 ## the light has grown over it
		else:
			var lifespan: int = int((DataRegistry.get_entry("plants", String(entry.k)).get("sow", {}) as Dictionary).get("lifespan", 8))
			gone = day - int(entry.d) >= lifespan
		if gone:
			_rpc_wither.rpc(cell)


## Can a seed take root on this tile: a loaded chunk, free ground, nothing within a tile, no more than `MAX_PER_CHUNK` sown in the chunk.
func cell_ok(cell: Vector2i) -> bool:
	var chunk_cell: Vector2i = Vector2i(floori(cell.x / float(WorldLevel.CHUNK)), floori(cell.y / float(WorldLevel.CHUNK)))
	if not level._chunks.has(chunk_cell) or sown.has(cell) or _pending.has(cell) or level._generator.blocked_cells.has(cell):
		return false
	var pos: Vector2 = PropGenerator.position_of(cell)
	var in_chunk: int = 0
	for other: Vector2i in sown:
		if Vector2i(floori(other.x / float(WorldLevel.CHUNK)), floori(other.y / float(WorldLevel.CHUNK))) == chunk_cell:
			in_chunk += 1
	if in_chunk >= MAX_PER_CHUNK:
		return false
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var near: Vector2i = cell + Vector2i(dx, dy)
			var thing: WorldProp = level._things.get(near) as WorldProp
			var gap: float = 26.0 if (thing != null and (thing.kind in PropGenerator.TREE_KINDS or thing.kind == "rock" or thing.kind == "iron_rock")) else 14.0
			if (thing != null or sown.has(near)) and pos.distance_to(PropGenerator.position_of(near)) < gap:
				return false
	return level.town_probe(Rect2(pos - Vector2(6, 6), Vector2(12, 12))) == ""


# ------------------------------------------------------------------ everyone
@rpc("authority", "call_local", "reliable")
func _rpc_sow(cell: Vector2i, kind: String, variant: int, day: int, from: Vector2, edge: bool) -> void:
	sown[cell] = {"k": kind, "v": variant, "d": day, "e": 1 if edge else 0}
	_pending[cell] = true
	var to: Vector2 = PropGenerator.position_of(cell)
	if from != Vector2.ZERO and is_inside_tree():
		var flight: Flight = Flight.new()
		flight.setup(from, to, _seed_colors(kind))
		level._props.add_child(flight)
	await get_tree().create_timer(FLIGHT_TIME if from != Vector2.ZERO else 0.05).timeout
	_pending.erase(cell)
	if sown.has(cell):
		_spawn(cell, true)


@rpc("authority", "call_local", "reliable")
func _rpc_wither(cell: Vector2i) -> void:
	sown.erase(cell)
	var thing: WorldProp = level._things.get(cell) as WorldProp
	if not is_instance_valid(thing):
		return
	var chunk: WorldLevel.Chunk = level._chunks.get(Vector2i(floori(cell.x / float(WorldLevel.CHUNK)), floori(cell.y / float(WorldLevel.CHUNK)))) as WorldLevel.Chunk
	if chunk != null:
		chunk.things.erase(thing)
	level._things.erase(cell)
	var tween: Tween = thing.create_tween()
	tween.tween_property(thing, "modulate:a", 0.0, 0.9)
	tween.tween_callback(func() -> void:
		if is_instance_valid(thing):
			thing.get_parent().remove_child(thing)
			thing.queue_free())


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(data: Dictionary) -> void:
	sown = data.duplicate(true)
	for cell: Vector2i in sown:
		_spawn(cell, false)


## A chunk just went live: the sown plants of its area stand there.
func populate(chunk_cell: Vector2i, chunk: WorldLevel.Chunk) -> void:
	for cell: Vector2i in sown:
		if Vector2i(floori(cell.x / float(WorldLevel.CHUNK)), floori(cell.y / float(WorldLevel.CHUNK))) == chunk_cell:
			_spawn(cell, false, chunk)


func _spawn(cell: Vector2i, fresh: bool, chunk: WorldLevel.Chunk = null) -> void:
	if level._things.has(cell) or _pending.has(cell) and not fresh:
		return
	var entry: Dictionary = sown.get(cell, {}) as Dictionary
	if entry.is_empty() or not DataRegistry.table("plants").has(String(entry.k)):
		return
	if chunk == null:
		chunk = level._chunks.get(Vector2i(floori(cell.x / float(WorldLevel.CHUNK)), floori(cell.y / float(WorldLevel.CHUNK)))) as WorldLevel.Chunk
	if chunk == null:
		return
	var thing: WorldProp = level._create_thing(cell, String(entry.k), int(entry.v))
	thing.scale = Vector2.ONE * _size(entry)
	level._props.add_child(thing)
	level._things[cell] = thing
	chunk.things.append(thing)
	if fresh:
		thing.modulate.a = 0.0
		thing.create_tween().tween_property(thing, "modulate:a", 1.0, 0.6)


func _size(entry: Dictionary) -> float:
	return clampf(0.6 + 0.4 * float(TimeManager.day - int(entry.d)) / GROW_DAYS, 0.6, 1.0)


func _refresh_sizes() -> void:
	for cell: Vector2i in sown:
		var thing: WorldProp = level._things.get(cell) as WorldProp
		if is_instance_valid(thing):
			thing.scale = Vector2.ONE * _size(sown[cell] as Dictionary)


func _seed_colors(kind: String) -> Array[Color]:
	var spec: Dictionary = DataRegistry.get_entry("plants", kind)
	var out: Array[Color] = []
	for hex: Variant in (spec.get("puff", spec.get("leaf_colors", ["#f6f4ff"])) as Array):
		out.append(Color(String(hex)))
	return out


# ------------------------------------------------------------------ the save
func export() -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in sown:
		out["s:%d,%d" % [cell.x, cell.y]] = sown[cell]
	return out


func import_saved(saved: Dictionary) -> void:
	sown.clear()
	for key: String in saved:
		if not key.begins_with("s:"):
			continue
		var parts: PackedStringArray = key.trim_prefix("s:").split(",")
		var entry: Dictionary = saved[key] as Dictionary
		sown[Vector2i(int(parts[0]), int(parts[1]))] = {"k": String(entry.k), "v": int(entry.v), "d": int(entry.d), "e": int(entry.get("e", 0))}
	for cell: Vector2i in sown:
		_spawn(cell, false)


## A handful of seeds that arc from the parent plant to the new spot (unlit, a few pixels).
class Flight extends Node2D:
	var _from: Vector2
	var _to: Vector2
	var _colors: Array[Color]
	var _age: float = 0.0

	func setup(from: Vector2, to: Vector2, colors: Array[Color]) -> void:
		_from = from
		_to = to
		_colors = colors if not colors.is_empty() else [Color("f6f4ff")]
		z_index = 60
		material = Unlit.material()

	func _process(delta: float) -> void:
		_age += delta
		queue_redraw()
		if _age >= PlantSowing.FLIGHT_TIME:
			queue_free()

	func _draw() -> void:
		var t: float = clampf(_age / PlantSowing.FLIGHT_TIME, 0.0, 1.0)
		for i: int in 3:
			var lag: float = clampf(t - 0.06 * float(i), 0.0, 1.0)
			var at: Vector2 = _from.lerp(_to, lag) + Vector2(sin(lag * 9.0 + float(i)) * 3.0, -sin(lag * PI) * (22.0 + 6.0 * float(i)))
			var color: Color = _colors[i % _colors.size()]
			color.a = 1.0 - 0.6 * t
			draw_rect(Rect2(at.round(), Vector2.ONE * (2.0 if i == 0 else 1.0)), color)
