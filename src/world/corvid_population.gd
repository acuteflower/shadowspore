class_name CorvidPopulation
extends Node2D
## Separate bird budget, same shared Y-sort as other wildlife. Ground flocks belong to streamed
## homes, but flying birds survive a border crossing. Perches are real loaded, uncut tree branches.

const BIRD: PackedScene = preload("res://src/entities/wildlife/wild_corvid.tscn")
const CHUNK_PIXELS: float = 512.0
var _seed: int = 0
var _habitat: Callable
var _active: Dictionary = {}
var _flocks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _claims: Dictionary = {}
var _sounds: Dictionary = {}
var _watch_turns: Dictionary = {}
var _visitors: Array[WildCorvid] = []
var _serial: int = 0
var _maintenance: float = 0.0

@onready var _birds: Node2D = $Birds


func _ready() -> void:
	add_to_group("corvid_population")
	set_process(multiplayer.is_server())


func setup(seed_value: int, habitat: Callable) -> void:
	_seed = seed_value
	_habitat = habitat


func chunk_loaded(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_active[cell] = true
		if not _flocks.has(cell) and not _pending.has(cell):
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
		_maintenance = 1.0
		_maintain()


func _populate(cell: Vector2i) -> void:
	if _flocks.has(cell):
		return
	var flock: Array[WildCorvid] = []
	_flocks[cell] = flock
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, _seed + 6299))
	for species: String in ["crow", "raven", "owl", "hoopoe"]:
		var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
		if rng.randf() > float(spec["chunk_chance"]) or _wild_count() >= int(spec["max_loaded"]) or _species_count(species) >= int(spec.get("max_species_loaded", spec["max_loaded"])):
			continue
		var center: Vector2 = Vector2.ZERO
		var found: bool = false
		for attempt: int in int(spec["spawn_attempts"]):
			var margin: float = float(spec["spawn_margin"])
			center = Vector2(cell) * CHUNK_PIXELS + Vector2(rng.randf_range(margin, CHUNK_PIXELS - margin), rng.randf_range(margin, CHUNK_PIXELS - margin))
			if _floor(center, species) and _clear(center, 6.0):
				found = true
				break
		if not found:
			continue
		var id: String = "%s_%d_%d" % [species, cell.x, cell.y]
		var count: int = rng.randi_range(int(spec["group_min"]), int(spec["group_max"]))
		for i: int in count:
			if _wild_count() >= int(spec["max_loaded"]) or _species_count(species) >= int(spec.get("max_species_loaded", spec["max_loaded"])):
				break
			var point: Vector2 = center
			if i > 0:
				point += Vector2.from_angle(i * TAU / count) * rng.randf_range(25.0, float(spec["group_radius"]))
			if not _floor(point, species) or not _clear(point, 6.0) or not _player_clear(point, float(spec["alert_range"])):
				continue
			var registry: PetRegistry = PetRegistry.of(get_tree())
			var key: String = "%s#%d" % [id, i] ## the same bird every session: the flocks are seeded from the chunk (PetRegistry)
			if registry != null and registry.has_record(key):
				rng.randi_range(0, 2) ## the same draws as the flock bird made, so the rest of the flock stays as it was
				rng.randf()
				continue ## it has a name and a territory now: the registry puts it where it belongs, not the flock
			var scene: PackedScene = load(String(spec["scene"])) as PackedScene
			var bird: WildCorvid = scene.instantiate() as WildCorvid
			_serial += 1
			bird.name = "Corvid%d" % _serial
			bird.species = species
			bird.appearance = rng.randi_range(0, 2)
			bird.flock_id = id
			bird.pet_key = key
			bird.home = center
			bird.position = point
			bird.facing = rng.randf() * TAU
			_birds.add_child(bird)
			if bool(spec.get("requires_perch", false)):
				var perch: Dictionary = choose_perch(bird, Vector2.INF)
				if perch.is_empty():
					bird.queue_free()
					continue
				bird._finish.rpc(perch["position"], perch["height"], perch["path"])
			flock.append(bird)


## A visitor of the town (TownCritters): one bird of `species` at `point`, grounded, wanting a roof (`visit_roof`). Null when the caps, the ground or the people forbid it.
func spawn_visitor(species: String, point: Vector2, flock: String) -> WildCorvid:
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	if _wild_count() >= int(spec["max_loaded"]) or _species_count(species) >= int(spec.get("max_species_loaded", spec["max_loaded"])):
		return null
	if not _floor(point, species) or not _clear(point, 6.0) or not _player_clear(point, float(spec["alert_range"])):
		return null
	var bird: WildCorvid = (load(String(spec["scene"])) as PackedScene).instantiate() as WildCorvid
	_serial += 1
	bird.name = "Corvid%d" % _serial
	bird.species = species
	bird.appearance = randi_range(0, 2)
	bird.flock_id = flock
	bird.home = point
	bird.position = point
	bird.facing = randf() * TAU
	bird.visit_roof = true
	_birds.add_child(bird)
	_visitors.append(bird)
	return bird


## Birds that count against the ambient budget: the registered ones (named, with a territory) have a budget of their own.
func _wild_count() -> int:
	var registry: PetRegistry = PetRegistry.of(get_tree())
	var count: int = 0
	for node: Node in _birds.get_children():
		var bird: WildCorvid = node as WildCorvid
		if not bird.is_queued_for_deletion() and (registry == null or not registry.has_record(bird.pet_key)):
			count += 1
	return count


## True when the chunk round `point` is loaded here (the host's streaming).
func is_active_at(point: Vector2) -> bool:
	return _active.has(_chunk(point))


## Host: puts the registered bird `key` at `point` (or a free spot close by). Null when the place is not fit right now (water, a tree, a player near).
func spawn_pet(key: String, record: Dictionary, point: Vector2, player_clear: float) -> WildCorvid:
	var species: String = String(record["sp"])
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	var at: Vector2 = point
	var found: bool = false
	for attempt: int in 6:
		at = point + (Vector2.from_angle(attempt * 1.7) * float(attempt) * 9.0)
		if _floor(at, species) and _clear(at, 6.0) and _player_clear(at, player_clear):
			found = true
			break
	if not found:
		return null
	var bird: WildCorvid = (load(String(spec["scene"])) as PackedScene).instantiate() as WildCorvid
	_serial += 1
	bird.name = "Corvid%d" % _serial
	bird.species = species
	bird.appearance = int(record["ap"])
	bird.flock_id = "pet:%s" % key
	bird.pet_key = key
	bird.home = point
	bird.territory = point
	bird.position = at
	bird.facing = randf() * TAU
	_birds.add_child(bird)
	return bird


## Host: a registered bird whose place is out of view goes away (the registry puts it back when the place is loaded again).
func remove_pet(bird: WildCorvid) -> void:
	release_perch(bird)
	bird.queue_free()


func visitors() -> Array[WildCorvid]:
	for i: int in range(_visitors.size() - 1, -1, -1):
		if not is_instance_valid(_visitors[i]) or _visitors[i].is_queued_for_deletion():
			_visitors.remove_at(i)
	return _visitors


func _species_count(species: String) -> int:
	var count: int = 0
	for node: Node in _birds.get_children():
		var bird: WildCorvid = node as WildCorvid
		if not bird.is_queued_for_deletion() and bird.species == species:
			count += 1
	return count


func _floor(point: Vector2, species: String) -> bool:
	return _habitat.is_valid() and bool(_habitat.call(point, species))


func _clear(point: Vector2, radius: float) -> bool:
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _player_clear(point: Vector2, radius: float) -> bool:
	for player: Player in Player.all:
		if player.health.current > 0.0 and player.global_position.distance_to(point) < radius:
			return false
	return true


func can_land(point: Vector2, bird: WildCorvid) -> bool:
	if not _floor(point, bird.species) or not _clear(point, 5.0) or not _player_clear(point, float(bird._spec["safe_landing_range"])):
		return false
	var cell: Vector2i = _chunk(point)
	if not _active.has(cell):
		return false
	for node: Node in _birds.get_children():
		var other: WildCorvid = node as WildCorvid
		if other != bird and other.state != WildCorvid.State.FLY and other._height < 1.0 and other.global_position.distance_to(point) < float(bird._spec["personal_space"]):
			return false
	return true


## A companion may land close to its person (the ambient rule keeps birds away from players).
func can_land_companion(point: Vector2, bird: WildCorvid) -> bool:
	return _floor(point, bird.species) and _clear(point, 5.0) and _active.has(_chunk(point))


func choose_perch(bird: WildCorvid, danger: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var score: float = INF
	if not danger.is_finite() and not bird._rest_time():
		for log_node: FallenLog in get_tree().get_nodes_in_group("fallen_logs"):
			var distance: float = bird.global_position.distance_to(log_node.perch_point)
			var key: String = "%s:log" % log_node.get_path()
			var owner: Variant = _claims.get(key)
			if distance < 220.0 and (not is_instance_valid(owner) or owner == bird):
				var value: float = distance+12.0
				if value < score:
					score = value
					best = {"position":log_node.perch_point,"height":log_node.perch_height,"path":String(log_node.get_path()),"claim":key}
	for node: Node in get_tree().get_nodes_in_group("town_perches"): ## roofs, lamp arms, benches and fences of the town
		var perch: RoofPerch = node as RoofPerch
		if perch == null or perch.is_depleted():
			continue
		var reach: float = perch.global_position.distance_to(bird.global_position)
		if reach > 340.0 or (danger.is_finite() and perch.global_position.distance_to(danger) < float(bird._spec["safe_landing_range"])):
			continue
		var roof_key: String = "%s:roof" % perch.get_path()
		var roof_owner: Variant = _claims.get(roof_key)
		if is_instance_valid(roof_owner) and roof_owner != bird:
			continue
		var roof_value: float = reach + 20.0 - (400.0 if bird.visit_roof else 0.0)
		if roof_value < score:
			score = roof_value
			best = {"position": perch.global_position, "height": perch.perch_height, "path": String(perch.get_path()), "claim": roof_key}
	if bird.visit_roof and not best.is_empty():
		_claims[String(best["claim"])] = bird
		return best
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree == null or tree.is_depleted() or tree._falling:
			continue
		var distance: float = tree.global_position.distance_to(bird.global_position)
		if distance > 340.0 or (danger.is_finite() and tree.global_position.distance_to(danger) < float(bird._spec["safe_landing_range"])):
			continue
		var height: float = float(tree.spec()["height"][tree.variant])
		var half: float = float(tree.spec()["crown_half_width"][tree.variant])
		var slots: int = 1 if tree.variant == 0 else 3
		for slot: int in slots:
			var key: String = "%s:%d" % [tree.get_path(), slot]
			var owner: Variant = _claims.get(key)
			if is_instance_valid(owner) and owner != bird:
				continue
			var side: float = float(slot - 1) if slots == 3 else 0.0
			var point: Vector2 = tree.global_position + Vector2(side * half * 0.45, 2.0 + slot * 0.5)
			var value: float = distance + point.distance_to(bird.home) * 0.15
			if value < score:
				score = value
				best = {"position": point, "height": height * (0.62 + 0.09 * slot), "path": String(tree.get_path()), "claim": key}
	if not best.is_empty():
		_claims[String(best["claim"])] = bird
	return best


func release_perch(bird: WildCorvid) -> void:
	for key: String in _claims.keys():
		if not is_instance_valid(_claims[key]) or _claims[key] == bird:
			_claims.erase(key)


func _route_distance(point: Vector2, start: Vector2, end: Vector2, bend: Vector2) -> float:
	var nearest: float = INF
	for i: int in range(1, 20):
		var p: float = i / 20.0
		var at: Vector2 = start.lerp(end, p) + bend * (4.0 * p * (1.0 - p))
		nearest = minf(nearest, point.distance_to(at))
	return nearest


func route_bend(start: Vector2, end: Vector2, preferred: Vector2) -> Vector2:
	var side: Vector2 = (end - start).orthogonal().normalized()
	var best: Vector2 = preferred
	var cost: float = INF
	for bend: Vector2 in [preferred, side * 45.0, side * -45.0, side * 90.0, side * -90.0, Vector2.ZERO]:
		var score: float = bend.distance_to(preferred) * 0.1
		for node: Node in get_tree().get_nodes_in_group("bird_perches"):
			var tree: FirTree = node as FirTree
			if tree == null or tree.is_depleted():
				continue
			var radius: float = float(tree.spec()["crown_half_width"][tree.variant]) + 12.0
			if tree.global_position.distance_to(start) < radius or tree.global_position.distance_to(end) < radius:
				continue ## departing/approaching a branch, not crossing the entire tree
			if _route_distance(tree.global_position, start, end, bend) < radius:
				score += float(tree.spec()["height"][tree.variant]) * 4.0
		if score < cost:
			cost = score
			best = bend
	return best


func flight_clearance(start: Vector2, end: Vector2, bend: Vector2 = Vector2.ZERO) -> float:
	var height: float = 0.0
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree != null and not tree.is_depleted():
			var radius: float = float(tree.spec()["crown_half_width"][tree.variant]) + 12.0
			if tree.global_position.distance_to(start) < radius or tree.global_position.distance_to(end) < radius:
				continue
			if _route_distance(tree.global_position, start, end, bend) < radius:
				height = maxf(height, float(tree.spec()["height"][tree.variant]) + 28.0)
	return height


func authorize_call(flock: String) -> bool:
	var now: int = Time.get_ticks_msec()
	if now < int(_sounds.get(flock, 0)):
		return false
	_sounds[flock] = now + 1100
	return true


func _chunk(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK_PIXELS), floori(point.y / CHUNK_PIXELS))


func _maintain() -> void:
	for home_cell: Vector2i in _flocks.keys():
		var flock: Array[WildCorvid] = _flocks[home_cell]
		var watchers: Dictionary = {}
		for i: int in range(flock.size() - 1, -1, -1):
			var bird: WildCorvid = flock[i]
			if not is_instance_valid(bird):
				flock.remove_at(i)
				continue
			if not _active.has(home_cell) and not _active.has(_chunk(bird.global_position)) and not (bird._moving and _active.has(_chunk(bird._end))):
				release_perch(bird)
				bird.queue_free()
				flock.remove_at(i)
				continue
			if bird.state in [WildCorvid.State.WATCH, WildCorvid.State.ROOST]:
				watchers[bird.flock_id] = true
		var eligible: Dictionary = {}
		for bird: WildCorvid in flock:
			if bool(bird._spec.get("flock_watch", true)) and not watchers.has(bird.flock_id) and bird.state in [WildCorvid.State.IDLE, WildCorvid.State.PECK] and not bird._danger:
				(eligible.get_or_add(bird.flock_id, []) as Array).append(bird)
		for id: String in eligible:
			var candidates: Array = eligible[id]
			var turn: int = int(_watch_turns.get(id, 0))
			var watchman: WildCorvid = candidates[turn % candidates.size()] as WildCorvid
			watchman._set_mood(WildCorvid.State.WATCH, watchman._range("watch_seconds"))
			_watch_turns[id] = turn + 1
		if flock.is_empty() and not _active.has(home_cell):
			_flocks.erase(home_cell)
