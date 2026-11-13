class_name TinyPopulation
extends Node2D
## Sparse host-owned, chunk-bound bees and snails. No combat, emission or harvest.
var _seed: int
var _flowers: Callable
var _habitat: Callable
var _active: Dictionary = {}
var _pending: Array[Vector2i] = []
var _settled: Dictionary = {}
var _serial: int = 0
var _night: bool = false
@onready var _animals: Node2D = $Animals


func setup(seed_value: int, habitat: Callable, flowers: Callable) -> void:
	_seed = seed_value
	_habitat = habitat
	_flowers = flowers
	_night = TimeManager.is_night()
	set_process(multiplayer.is_server())


func chunk_loaded(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_active[cell] = true
		if not _settled.has(cell) and not _pending.has(cell):
			_pending.append(cell)


func chunk_unloaded(cell: Vector2i) -> void:
	_active.erase(cell)
	_pending.erase(cell)
	_settled.erase(cell)
	for node: Node in _animals.get_children():
		var animal: TinyWildlife = node as TinyWildlife
		if _cell(animal.home) == cell:
			animal.queue_free()


## The chunk lies in the Hexenwald (its middle deep in BiomeBlend's field).
func _witch(cell: Vector2i) -> bool:
	return BiomeBlend.amount_at(Vector2(cell) * 512.0 + Vector2(256, 256)) >= 0.5


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 512), floori(point.y / 512))


func can_crawl(from: Vector2, to: Vector2, species: String = "snail") -> bool:
	if not _habitat.is_valid():
		return false
	for point: Vector2 in [from, from.lerp(to, 0.5), to]:
		if not _active.has(_cell(point)) or not bool(_habitat.call(point, species)):
			return false
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = 1.0
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0, from)
	query.collision_mask = 1
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	query.motion = to - from
	return get_world_2d().direct_space_state.cast_motion(query)[0] >= 0.999


func _process(_delta: float) -> void:
	if _night != TimeManager.is_night():
		_night = TimeManager.is_night()
		for cell: Vector2i in _active:
			if not _pending.has(cell):
				_pending.append(cell)
		if not _night:
			for node: Node in _animals.get_children():
				if (node as TinyWildlife).species == "moth" and not _witch(_cell((node as TinyWildlife).home)):
					node.queue_free()
			for cell: Vector2i in _settled:
				if not _witch(cell): ## the Hexenwald's moths stay: it is always dusk there
					(_settled[cell] as Dictionary).erase("moth")
	if not _pending.is_empty():
		var cell: Vector2i = _pending.pop_front()
		if _active.has(cell):
			_populate(cell)


func _populate(cell: Vector2i) -> void:
	if not _settled.has(cell):
		_settled[cell] = {}
	var origin: Vector2 = Vector2(cell) * 512.0
	if BiomeBlend.arid_at(origin + Vector2(256.0, 256.0)) >= 0.22 and BiomeBlend.arid_at(origin) >= 0.22 and BiomeBlend.arid_at(origin + Vector2(512.0, 512.0)) >= 0.22:
		return
	var settled: Dictionary = _settled[cell]
	var witch: bool = _witch(cell)
	for species: String in ["snail", "bee", "ladybug", "moth", "toad", "bat"]:
		if settled.has(species) or (species == "moth" and not TimeManager.is_night() and not witch) or (species in ["toad", "bat"] and not witch):
			continue
		settled[species] = true
		var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
		if witch and spec.has("witch_forest"):
			spec = spec.duplicate()
			spec.merge(spec["witch_forest"] as Dictionary, true)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(cell.x, cell.y, _seed + hash(species)))
		if rng.randf() > float(spec["chunk_chance"]):
			continue
		var patch: Array[Vector2] = []
		if species in ["bee", "ladybug", "moth"]:
			if not _flowers.is_valid():
				continue
			for point: Vector2 in _flowers.call(cell):
				patch.append(point)
			if species == "moth":
				var lights: Array[Vector2] = []
				var candles: Array[Vector2] = [] ## in the Hexenwald they keep to the grave candles' flames
				for node: Node in get_tree().get_nodes_in_group("flora_glow"):
					if node is Node2D and _cell((node as Node2D).global_position) == cell and BiomeBlend.arid_at((node as Node2D).global_position) < 0.22:
						lights.append((node as Node2D).global_position)
						if node is WorldProp and (node as WorldProp).kind == "grave_candle":
							candles.append((node as Node2D).global_position + Vector2(0, -8))
				if candles.size() >= 3:
					patch = candles
				elif lights.size() >= 3:
					patch = lights
			if patch.size() < 3:
				continue
		if species == "toad": ## its home is a toadstool
			for node: Node in get_tree().get_nodes_in_group("toad_spots"):
				if node is Node2D and _cell((node as Node2D).global_position) == cell:
					patch.append((node as Node2D).global_position)
			if patch.is_empty():
				continue
		elif species == "bat": ## its home is a stand of the wood's trees, which it hangs under
			for node: Node in get_tree().get_nodes_in_group("bird_perches"):
				var trunk: FirTree = node as FirTree
				if trunk != null and _cell(trunk.global_position) == cell and (trunk.kind == "hag_tree" or trunk.kind == "bone_tree") and trunk.variant >= 1:
					patch.append(trunk.global_position)
			if patch.size() < 2:
				continue
		var count: int = rng.randi_range(int(spec["group_min"]), int(spec["group_max"]))
		for i: int in count:
			var current: int = 0
			for node: Node in _animals.get_children():
				if (node as TinyWildlife).species == species and not node.is_queued_for_deletion():
					current += 1
			if current >= int(spec["max_loaded"]):
				break
			var at: Vector2 = Vector2(cell) * 512 + Vector2(rng.randf_range(55, 457), rng.randf_range(55, 457))
			var tree: FirTree
			if species in ["bee", "ladybug", "moth"]:
				at = patch[rng.randi_range(0, patch.size() - 1)]
			elif species == "toad":
				at = (patch[rng.randi_range(0, patch.size() - 1)] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(7.0, 13.0)).round()
				if not can_crawl(at, at, species):
					continue
			elif species == "bat":
				at = patch[rng.randi_range(0, patch.size() - 1)] + Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-20.0, 20.0))
			elif species == "snail" and rng.randf() < float(spec["tree_chance"]):
				for node: Node in get_tree().get_nodes_in_group("bird_perches"):
					var candidate: FirTree = node as FirTree
					if candidate != null and _cell(candidate.global_position) == cell and not candidate.kind in ["crown_cactus", "sun_palm"] and BiomeBlend.arid_at(candidate.global_position) < 0.22 and int(candidate.state.get("f", 0)) == 0 and float((candidate.spec()["clear"] as Array)[candidate.variant]) >= 24.0:
						tree = candidate
						at = tree.global_position
						break
			if species in ["snail", "ladybug"] and tree == null:
				var valid: bool = can_crawl(at, at, species)
				for attempt: int in 8:
					if valid or species == "ladybug":
						break
					at = Vector2(cell) * 512 + Vector2(rng.randf_range(55, 457), rng.randf_range(55, 457))
					valid = can_crawl(at, at, species)
				if not valid:
					continue
			var animal: TinyWildlife = load("res://src/entities/wildlife/tiny_wildlife.tscn").instantiate() as TinyWildlife
			_serial += 1
			animal.name = "Tiny_%s_%d" % [species, _serial]
			animal.species = species
			animal.appearance = rng.randi_range(0, 2)
			animal.home = at
			animal.position = at
			if tree != null:
				animal.tree_path = String(tree.get_path())
				var half: float = float((tree.spec()["trunk_half_width"] as Array)[tree.variant])
				animal.tree_offset = Vector2((half - 1) * (-1 if i % 2 == 0 else 1), -rng.randf_range(9, 22))
			animal.flowers = patch
			_animals.add_child(animal)
