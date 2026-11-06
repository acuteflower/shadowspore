class_name WoodlandPopulation
extends Node2D
## Sparse ground residents with stable homes. Tree-sort chain remains continuous through Residents.

const CHUNK_PIXELS: float = 512.0
var _seed: int = 0
var _habitat: Callable
var _active: Dictionary = {}
var _families: Dictionary = {}
var _shelters: Dictionary = {}
var _pending: Array[Vector2i] = []
var _visitors: Array[WoodlandMammal] = []
var _serial: int = 0
var _maintenance: float = 0.0

@onready var _residents: Node2D = $Residents


func _ready() -> void:
	set_process(multiplayer.is_server())


func setup(seed_value: int, habitat: Callable) -> void:
	_seed = seed_value
	_habitat = habitat


func chunk_loaded(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_active[cell] = true
		if not _families.has(cell) and not _pending.has(cell):
			_pending.append(cell)


func chunk_unloaded(cell: Vector2i) -> void:
	_active.erase(cell)
	_pending.erase(cell)


func _process(delta: float) -> void:
	if not _pending.is_empty():
		var cell: Vector2i = _pending.pop_front()
		if _active.has(cell):
			_populate(cell)
	_maintenance -= delta
	if _maintenance <= 0.0:
		_maintenance = 0.5
		_collect()


func _chunk(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK_PIXELS), floori(point.y / CHUNK_PIXELS))


func home_loaded(point: Vector2) -> bool:
	return _active.has(_chunk(point))


func _count(species: String) -> int:
	var count: int = 0
	for node: Node in _residents.get_children():
		var animal: WoodlandMammal = node as WoodlandMammal
		if animal.species == species and not animal.is_queued_for_deletion():
			count += 1
	return count


func _clear(point: Vector2, radius: float) -> bool:
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func can_stand(point: Vector2, animal: WoodlandMammal) -> bool:
	return home_loaded(point) and _habitat.is_valid() and bool(_habitat.call(point, animal.species))


func _spawn_safe(point: Vector2, species: String) -> bool:
	if not _habitat.is_valid() or not bool(_habitat.call(point, species)):
		return false
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	if not _clear(point, float(spec["body_radius"]) + 2.0):
		return false
	for player: Player in Player.all:
		if player.global_position.distance_to(point) < float(spec["alert_range"]):
			return false
	for node: Node in _residents.get_children():
		if (node as Node2D).global_position.distance_to(point) < 18.0:
			return false
	return true


func _cover_score(point: Vector2) -> float:
	var nearest: float = 120.0
	for world: Node in get_tree().get_nodes_in_group("world"):
		var props: Node = world.get_node_or_null("Props")
		if props != null:
			for node: Node in props.get_children():
				var prop: WorldProp = node as WorldProp
				if prop != null and prop.kind in ["tree", "bush", "berry_bush"]:
					nearest = minf(nearest, prop.global_position.distance_to(point))
	return -nearest


func _populate(cell: Vector2i) -> void:
	if _families.has(cell):
		return
	var residents: Array[WoodlandMammal] = []
	_families[cell] = residents
	for species: String in ["deer", "badger", "fox", "hedgehog"]:
		var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(cell.x, cell.y, _seed + hash(species)))
		if _residents.get_child_count() >= int(spec["max_loaded"]) or _count(species) >= int(spec["max_species_loaded"]) or rng.randf() > float(spec["chunk_chance"]):
			continue
		var center: Vector2 = Vector2.ZERO
		var score: float = -INF
		for attempt: int in int(spec["spawn_attempts"]):
			var margin: float = float(spec["spawn_margin"])
			var point: Vector2 = Vector2(cell) * CHUNK_PIXELS + Vector2(rng.randf_range(margin, CHUNK_PIXELS - margin), rng.randf_range(margin, CHUNK_PIXELS - margin))
			if _spawn_safe(point, species):
				var value: float = rng.randf() if species == "deer" else _cover_score(point)
				if value > score:
					score = value
					center = point
		if score == -INF:
			continue
		var count: int = rng.randi_range(int(spec["group_min"]), int(spec["group_max"]))
		var spawned: int = 0
		for i: int in count:
			if _residents.get_child_count() >= int(spec["max_loaded"]) or _count(species) >= int(spec["max_species_loaded"]):
				break
			var point: Vector2 = center + Vector2(25.0 * i, 15.0 * i)
			if not _spawn_safe(point, species):
				continue
			var scene: PackedScene = load(String(spec["scene"])) as PackedScene
			var animal: WoodlandMammal = scene.instantiate() as WoodlandMammal
			_serial += 1
			animal.name = "Resident%d" % _serial
			animal.species = species
			animal.appearance = ([0, 2, 1][i] as int) if species == "deer" else rng.randi_range(0, 2)
			animal.family_id = "%s_%d_%d" % [species, cell.x, cell.y]
			animal.position = point
			animal.home = center
			animal.facing = rng.randf() * TAU
			_residents.add_child(animal)
			residents.append(animal)
			spawned += 1
			if bool(spec["nocturnal"]) and TimeManager.night_amount() < 0.4:
				animal._command.rpc(WoodlandMammal.Mood.HIDDEN if species == "badger" else WoodlandMammal.Mood.SLEEP, animal._range("sleep_seconds"), animal.facing, center if species == "badger" else point, center if species == "badger" else point, 0.0)
		if species == "badger" and spawned > 0:
			# A normal spawned scene, so joining peers see the same fixed den entrance.
			var shelter: WildlifeShelter = load("res://src/entities/wildlife/wildlife_shelter.tscn").instantiate() as WildlifeShelter
			shelter.name = "Den%d" % _serial
			shelter.position = center
			$Shelters.add_child(shelter)
			_shelters[cell] = shelter


## A visitor of the town (TownCritters): one animal of `species` at `point` that goes to `to` and sniffs towards `look`. Null when the caps or the ground forbid it.
func spawn_visitor(species: String, point: Vector2, to: Vector2, look: Vector2) -> WoodlandMammal:
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	if _count(species) >= int(spec["max_species_loaded"]) or _residents.get_child_count() >= int(spec["max_loaded"]) or not _spawn_safe(point, species):
		return null
	var animal: WoodlandMammal = (load(String(spec["scene"])) as PackedScene).instantiate() as WoodlandMammal
	_serial += 1
	animal.name = "Resident%d" % _serial
	animal.species = species
	animal.appearance = randi_range(0, 2)
	animal.family_id = "visit_%d" % _serial
	animal.position = point
	animal.home = point
	animal.facing = (to - point).angle()
	animal.visit = to
	animal.visit_look = look
	_residents.add_child(animal)
	_visitors.append(animal)
	return animal


func visitors() -> Array[WoodlandMammal]:
	for i: int in range(_visitors.size() - 1, -1, -1):
		if not is_instance_valid(_visitors[i]) or _visitors[i].is_queued_for_deletion():
			_visitors.remove_at(i)
	return _visitors


func _collect() -> void:
	for home_cell: Vector2i in _families.keys():
		var residents: Array[WoodlandMammal] = _families[home_cell]
		for i: int in range(residents.size() - 1, -1, -1):
			var animal: WoodlandMammal = residents[i]
			if not is_instance_valid(animal):
				residents.remove_at(i)
				continue
			if not _active.has(home_cell) and not home_loaded(animal.global_position) and not (animal._moving and home_loaded(animal._end)):
				animal.queue_free()
				residents.remove_at(i)
		if residents.is_empty() and not _active.has(home_cell):
			_families.erase(home_cell)
			if _shelters.has(home_cell):
				var shelter: Node = _shelters[home_cell]
				if is_instance_valid(shelter):
					shelter.queue_free()
				_shelters.erase(home_cell)
