class_name WoodlandPopulation
extends Node2D
## Sparse ground residents with stable homes. Tree-sort chain remains continuous through Residents.

const CHUNK_PIXELS: float = 512.0
var enabled_species: Array[String] = ["deer", "fox", "boar", "lynx", "squirrel", "badger", "hex_goat", "hex_toad", "oryx", "fennec", "jerboa", "agama"]
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
				if prop != null and prop.kind in ["tree", "bush", "berry_bush", "hex_shrub", "witch_broom"]:
					nearest = minf(nearest, prop.global_position.distance_to(point))
	return -nearest


func _nearest_conifer_distance(point: Vector2) -> float:
	var nearest: float = INF
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree != null and not tree.is_depleted() and tree.kind != "bone_tree":
			nearest = minf(nearest, tree.global_position.distance_to(point))
	return nearest


func _nearest_log_distance(point: Vector2) -> float:
	var nearest: float = INF
	for log_node: FallenLog in get_tree().get_nodes_in_group("fallen_logs"):
		nearest = minf(nearest, log_node.global_position.distance_to(point))
	return nearest


func _habitat_score(point: Vector2, species: String, rng: RandomNumberGenerator) -> float:
	if species == "deer":
		return rng.randf()
	if species == "squirrel":
		var tree_d: float = _nearest_conifer_distance(point)
		if tree_d > 105.0 and tree_d < INF:
			return -INF
		if tree_d == INF:
			return _cover_score(point)
		return -tree_d + rng.randf() * 8.0
	if species == "lynx":
		var log_d: float = _nearest_log_distance(point)
		var cover: float = _cover_score(point)
		if cover < -95.0 and log_d > 110.0:
			return -INF
		return maxf(cover, -log_d) + rng.randf() * 6.0
	if species == "boar":
		var log_bonus: float = 18.0 if _nearest_log_distance(point) < 65.0 else 0.0
		return _cover_score(point) + log_bonus + rng.randf() * 10.0
	if species == "hex_goat":
		if BiomeBlend.amount_at(point) < 0.30:
			return -INF
		return _cover_score(point) * 0.5 + rng.randf() * 16.0
	if species == "hex_toad":
		if BiomeBlend.amount_at(point) < 0.35:
			return -INF
		var best: float = 130.0
		for spot: Node in get_tree().get_nodes_in_group("toad_spots"):
			if spot is Node2D:
				best = minf(best, (spot as Node2D).global_position.distance_to(point))
		for log_node: FallenLog in get_tree().get_nodes_in_group("fallen_logs"):
			best = minf(best, log_node.global_position.distance_to(point))
		return -best + rng.randf() * 8.0
	if species in ["oryx", "fennec", "jerboa", "agama"]:
		var arid: float = BiomeBlend.arid_at(point)
		if arid < 0.35:
			return -INF
		var oasis: float = BiomeBlend.oasis_at(point)
		var on_quartz: bool = BiomeBlend.is_quartz_surface(point)
		if species == "oryx":
			var shade_bonus: float = 0.0
			for node: Node in get_tree().get_nodes_in_group("bird_perches"):
				var tr: FirTree = node as FirTree
				if tr != null and tr.kind in ["sun_palm", "crown_cactus"] and tr.global_position.distance_to(point) < 110.0:
					shade_bonus = maxf(shade_bonus, 24.0)
			return oasis * 48.0 + shade_bonus + rng.randf() * 14.0
		if species == "fennec":
			var rock_near: float = 120.0
			for world: Node in get_tree().get_nodes_in_group("world"):
				var props: Node = world.get_node_or_null("Props")
				if props != null:
					for node: Node in props.get_children():
						var prop: WorldProp = node as WorldProp
						if prop != null and prop.kind in ["sun_quartz_rock", "desert_scrub", "crown_cactus", "prickly_pear"]:
							rock_near = minf(rock_near, prop.global_position.distance_to(point))
			return -rock_near * 0.65 - oasis * 18.0 + rng.randf() * 12.0
		if species == "jerboa":
			if oasis > 0.45:
				return -INF
			var sand_bonus: float = 28.0 if not on_quartz else -12.0
			return sand_bonus + arid * 20.0 + rng.randf() * 14.0
		if species == "agama":
			if oasis > 0.30:
				return -INF
			var q_score: float = 85.0 if on_quartz else 0.0
			if not on_quartz:
				for off: Vector2 in [Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20)]:
					if BiomeBlend.is_quartz_surface(point + off):
						q_score = maxf(q_score, 42.0)
			if q_score <= 0.0 and arid < 0.62:
				return -INF
			return q_score + rng.randf() * 10.0
	return _cover_score(point)


func _choose_appearance(species: String, index: int, group_count: int, center: Vector2, rng: RandomNumberGenerator, spec: Dictionary) -> int:
	var gloom: float = BiomeBlend.amount_at(center)
	match species:
		"deer":
			var lead_doe: int = 3 if (gloom > 0.12 or rng.randf() < 0.25) else 0
			var family_coats: Array[int] = [lead_doe, 2, 1]
			return family_coats[index % family_coats.size()]
		"fox":
			return rng.rand_weighted(PackedFloat32Array([0.48, 0.20, 0.16, 0.16]))
		"boar":
			if group_count == 1:
				return 1
			if index == 0:
				return 3 if (gloom > 0.12 or rng.randf() < 0.22) else 0
			if index == 1:
				return 2
			if index == 2:
				return 2 if rng.randf() < 0.65 else 1
			return 1 if rng.randf() < 0.55 else 2
		"lynx":
			if gloom >= 0.35:
				return 2
			return rng.rand_weighted(PackedFloat32Array([0.55, 0.25, 0.20]))
		"squirrel":
			return rng.rand_weighted(PackedFloat32Array([0.48, 0.22, 0.14, 0.16]))
		"badger":
			if index > 0:
				return 2
			return 0 if rng.randf() < 0.65 else 1
		"hex_goat":
			if index > 0:
				return 3 if rng.randf() < 0.68 else 2
			return rng.rand_weighted(PackedFloat32Array([0.46, 0.26, 0.28, 0.0]))
		"hex_toad":
			return rng.rand_weighted(PackedFloat32Array([0.46, 0.32, 0.22]))
		"oryx":
			if index == 0:
				return 2 if rng.randf() < 0.22 else 0
			if index == 1 and group_count >= 2 and rng.randf() < 0.72:
				return 3
			return 1 if rng.randf() < 0.74 else 2
		"fennec":
			if index > 0:
				return 3 if rng.randf() < 0.72 else 1
			if BiomeBlend.is_quartz_surface(center) and rng.randf() < 0.55:
				return 2
			return rng.rand_weighted(PackedFloat32Array([0.50, 0.32, 0.18, 0.0]))
		"jerboa":
			if index >= 2 and rng.randf() < 0.75:
				return 3
			if BiomeBlend.is_quartz_surface(center) and rng.randf() < 0.45:
				return 2
			return rng.rand_weighted(PackedFloat32Array([0.52, 0.28, 0.20, 0.0]))
		"agama":
			if BiomeBlend.is_quartz_surface(center) and rng.randf() < 0.46:
				return 2
			if index == 0:
				return 0 if rng.randf() < 0.64 else 1
			return 3 if rng.randf() < 0.36 else 1
	return rng.randi_range(0, int(spec.get("builds", 3)) - 1)


func _populate(cell: Vector2i) -> void:
	if _families.has(cell):
		return
	var residents: Array[WoodlandMammal] = []
	_families[cell] = residents
	for species: String in enabled_species:
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
				var value: float = _habitat_score(point, species, rng)
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
			var spacing: Vector2 = Vector2(16.0 * i, 10.0 * i) if species in ["jerboa", "agama", "fennec"] else (Vector2(19.0 * i, 12.0 * i) if species in ["boar", "squirrel", "hex_toad"] else Vector2(25.0 * i, 15.0 * i))
			var point: Vector2 = center + spacing
			if not _spawn_safe(point, species):
				continue
			var scene: PackedScene = load(String(spec["scene"])) as PackedScene
			var animal: WoodlandMammal = scene.instantiate() as WoodlandMammal
			_serial += 1
			animal.name = "Resident%d" % _serial
			animal.species = species
			animal.appearance = _choose_appearance(species, i, count, center, rng, spec)
			animal.family_id = "%s_%d_%d" % [species, cell.x, cell.y]
			animal.position = point
			animal.home = center
			animal.facing = rng.randf() * TAU
			_residents.add_child(animal)
			residents.append(animal)
			spawned += 1
			if bool(spec["nocturnal"]) and TimeManager.night_amount() < float(spec.get("awake_threshold", 0.4)):
				var hide_in_den: bool = species in ["badger", "jerboa"] or (species == "fennec" and rng.randf() < 0.55)
				animal._command.rpc(WoodlandMammal.Mood.HIDDEN if hide_in_den else WoodlandMammal.Mood.SLEEP, animal._range("sleep_seconds"), animal.facing, center if hide_in_den else point, center if hide_in_den else point, 0.0)
			elif species == "agama" and TimeManager.night_amount() > 0.38:
				animal._command.rpc(WoodlandMammal.Mood.HIDDEN, animal._range("sleep_seconds"), animal.facing, center, center, 0.0)
		if (species in ["badger", "fennec"] or (species == "jerboa" and rng.randf() < 0.55)) and spawned > 0:
			# A normal spawned scene, so joining peers see the same fixed den entrance.
			var shelter: WildlifeShelter = load("res://src/entities/wildlife/wildlife_shelter.tscn").instantiate() as WildlifeShelter
			shelter.name = "Den%d" % _serial
			shelter.shelter_kind = "desert_burrow" if species in ["fennec", "jerboa"] else "badger_den"
			shelter.position = center
			$Shelters.add_child(shelter)
			var cell_shelters: Array = _shelters.get_or_add(cell, []) as Array
			cell_shelters.append(shelter)


## A visitor of the town (TownCritters): one animal of `species` at `point` that goes to `to` and sniffs towards `look`. Null when the caps or the ground forbid it.
func spawn_visitor(species: String, point: Vector2, to: Vector2, look: Vector2) -> WoodlandMammal:
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	if _count(species) >= int(spec["max_species_loaded"]) or _residents.get_child_count() >= int(spec["max_loaded"]) or not _spawn_safe(point, species):
		return null
	var animal: WoodlandMammal = (load(String(spec["scene"])) as PackedScene).instantiate() as WoodlandMammal
	_serial += 1
	animal.name = "Resident%d" % _serial
	animal.species = species
	animal.appearance = randi_range(0, int(spec.get("builds", 3)) - 1)
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
				var entry: Variant = _shelters[home_cell]
				if entry is Array:
					for s: Variant in (entry as Array):
						if is_instance_valid(s):
							(s as Node).queue_free()
				elif is_instance_valid(entry):
					(entry as Node).queue_free()
				_shelters.erase(home_cell)
