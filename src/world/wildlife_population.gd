class_name WildlifePopulation
extends Node2D
## Host-only population of streamed meadow chunks. Animals live outside chunk nodes so fleeing
## across a chunk border never deletes them. This root and Animals both enable Y-sort so
## animals share the world's feet-based ordering with props and players. A departed home stays reserved until its herd leaves.

const RABBIT: PackedScene = preload("res://src/entities/wildlife/wild_rabbit.tscn")
const CHUNK_PIXELS: float = 512.0

var _seed: int = 0
var _valid_spawn: Callable
var _active: Dictionary = {}
var _populations: Dictionary = {}
var _pending: Array[Vector2i] = []
var _maintenance: float = 0.0
var _serial: int = 0
var _spec: Dictionary

@onready var _animals: Node2D = $Animals


func _ready() -> void:
	_spec = DataRegistry.get_entry("wildlife", "rabbit")
	set_process(multiplayer.is_server())


func setup(world_seed: int, valid_spawn: Callable, bird_habitat: Callable = Callable(), fauna_habitat: Callable = Callable(), flower_source: Callable = Callable()) -> void:
	_seed = world_seed
	_valid_spawn = valid_spawn
	$Corvids.setup(world_seed, bird_habitat)
	$Woodland.setup(world_seed, fauna_habitat)
	$Bears.setup(world_seed, fauna_habitat)
	$MeadowInsects.setup(world_seed, flower_source)
	$SmallResidents.setup(world_seed, fauna_habitat, flower_source)


func chunk_loaded(cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	$Corvids.chunk_loaded(cell)
	$Woodland.chunk_loaded(cell)
	_active[cell] = true
	if not _populations.has(cell) and not _pending.has(cell):
		_pending.append(cell)


func chunk_unloaded(cell: Vector2i) -> void:
	if multiplayer.is_server():
		$Corvids.chunk_unloaded(cell)
		$Woodland.chunk_unloaded(cell)
		$Bears.chunk_unloaded(cell)
		$MeadowInsects.chunk_unloaded(cell)
		$SmallResidents.chunk_unloaded(cell)
		_active.erase(cell)
		_pending.erase(cell)


func _process(delta: float) -> void:
	if not _pending.is_empty():
		# Chunk colliders/props have entered the physics world by the time this runs.
		var cell: Vector2i = _pending.pop_front()
		if _active.has(cell):
			_populate(cell)
	_maintenance -= delta
	if _maintenance <= 0.0:
		_maintenance = 0.5
		_collect_departed()


func _populate(cell: Vector2i) -> void:
	if _populations.has(cell) or _animals.get_child_count() >= int(_spec["max_loaded"]):
		return
	var rabbits: Array[WildRabbit] = []
	_populations[cell] = rabbits
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, _seed + 1973))
	if rng.randf() > float(_spec["chunk_chance"]):
		return
	var margin: float = float(_spec["spawn_margin"])
	var origin: Vector2 = Vector2(cell) * CHUNK_PIXELS
	var center: Vector2 = Vector2.ZERO
	var found: bool = false
	for attempt: int in int(_spec["spawn_attempts"]):
		center = origin + Vector2(rng.randf_range(margin, CHUNK_PIXELS - margin), rng.randf_range(margin, CHUNK_PIXELS - margin))
		if _can_spawn(center):
			found = true
			break
	if not found:
		return
	var count: int = rng.randi_range(int(_spec["group_min"]), int(_spec["group_max"]))
	for i: int in count:
		if _animals.get_child_count() >= int(_spec["max_loaded"]):
			break
		var position: Vector2 = center
		if i > 0:
			position += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(22.0, float(_spec["group_radius"]))
		if not _can_spawn(position):
			continue
		var rabbit: WildRabbit = RABBIT.instantiate() as WildRabbit
		_serial += 1
		rabbit.name = "Rabbit%d" % _serial
		rabbit.position = position
		rabbit.home = center
		var weights: PackedFloat32Array = PackedFloat32Array(_spec["variant_weights"])
		rabbit.appearance = rng.rand_weighted(weights)
		rabbit.temperament = rng.randf_range(0.9, 1.12)
		rabbit.facing = rng.randf() * TAU
		_animals.add_child(rabbit)
		rabbits.append(rabbit)


func _can_spawn(at: Vector2) -> bool:
	if not _valid_spawn.is_valid() or not bool(_valid_spawn.call(at)):
		return false
	# Do not materialize wildlife beside a player or inside a solid prop.
	for player: Player in Player.all:
		if player.global_position.distance_to(at) < float(_spec["alert_range"]):
			return false
	for animal: Node in _animals.get_children():
		if (animal as Node2D).global_position.distance_to(at) < 18.0:
			return false
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 7.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, at)
	query.collision_mask = 1
	return _animals.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _collect_departed() -> void:
	for home_chunk: Vector2i in _populations.keys():
		var herd: Array[WildRabbit] = _populations[home_chunk]
		for i: int in range(herd.size() - 1, -1, -1):
			var rabbit: WildRabbit = herd[i]
			if not is_instance_valid(rabbit):
				herd.remove_at(i)
				continue
			var cell: Vector2i = Vector2i(floori(rabbit.global_position.x / CHUNK_PIXELS), floori(rabbit.global_position.y / CHUNK_PIXELS))
			if not _active.has(home_chunk) and not _active.has(cell):
				rabbit.queue_free()
				herd.remove_at(i)
		if herd.is_empty() and not _active.has(home_chunk):
			_populations.erase(home_chunk)
