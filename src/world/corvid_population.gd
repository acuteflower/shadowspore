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
	var gloom: float = BiomeBlend.amount_at(Vector2(cell) * CHUNK_PIXELS + Vector2.ONE * CHUNK_PIXELS * 0.5) ## 0 on all old land: there the draws and numbers stay exactly as they were
	for species: String in ["crow", "raven"]:
		var spec: Dictionary = local_spec(species, gloom)
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
			if i > 0 and spec.has("spacing"): ## a big flock of the Hexenwald: a tight crowd, bird beside bird (a sunflower spiral, jittered)
				point += Vector2.from_angle(i * 2.39996 + rng.randf_range(-0.3, 0.3)) * float(spec["spacing"]) * sqrt(float(i))
			elif i > 0:
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
			bird.witch = gloom >= 0.5
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
	_populate_owl(cell, gloom, flock)
	_populate_desert_falcon(cell, flock)


func _populate_owl(cell: Vector2i, gloom: float, flock: Array[WildCorvid]) -> void:
	var owl_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	owl_rng.seed = hash(Vector3i(cell.x, cell.y, _seed + 9187))
	var spec: Dictionary = local_spec("owl", gloom)
	var mid_px: Vector2 = Vector2(cell) * CHUNK_PIXELS + Vector2.ONE * CHUNK_PIXELS * 0.5
	var w_deep_owl: float = MeadowHabitats.deep_forest_at(mid_px)
	var owl_chance: float = float(spec["chunk_chance"]) * (1.0 + 1.85 * w_deep_owl)
	var owl_cap: int = int(spec.get("max_species_loaded", 2)) + (2 if w_deep_owl >= 0.40 else 0)
	if owl_rng.randf() > owl_chance or _wild_count() >= int(spec["max_loaded"]) or _species_count("owl") >= owl_cap:
		return
	var margin: float = float(spec["spawn_margin"])
	var center: Vector2 = Vector2.ZERO
	var found: bool = false
	for attempt: int in int(spec["spawn_attempts"]):
		var candidate: Vector2 = Vector2(cell) * CHUNK_PIXELS + Vector2(owl_rng.randf_range(margin, CHUNK_PIXELS - margin), owl_rng.randf_range(margin, CHUNK_PIXELS - margin))
		if _floor(candidate, "owl") and _clear(candidate, 6.0) and _player_clear(candidate, float(spec["alert_range"])):
			center = candidate
			found = true
			break
	if not found:
		return
	var owl_scene: PackedScene = load(String(spec["scene"])) as PackedScene
	var owl: WildCorvid = owl_scene.instantiate() as WildCorvid
	_serial += 1
	owl.name = "Corvid%d" % _serial
	owl.species = "owl"
	if gloom >= 0.45:
		owl.appearance = 2 if owl_rng.randf() < 0.72 else 1
	else:
		owl.appearance = 0 if owl_rng.randf() < 0.65 else 1
	owl.flock_id = "owl_%d_%d" % [cell.x, cell.y]
	owl.home = center
	owl.witch = gloom >= 0.45
	owl.position = center
	owl.facing = owl_rng.randf() * TAU
	_birds.add_child(owl)
	var perch: Dictionary = choose_perch(owl, Vector2.INF)
	if perch.is_empty():
		owl.queue_free()
		return
	owl._finish.rpc(perch["position"], perch["height"], perch["path"])
	flock.append(owl)
	if gloom < 0.35:
		_populate_songbirds(cell, flock)


func _populate_desert_falcon(cell: Vector2i, flock: Array[WildCorvid]) -> void:
	var mid: Vector2 = Vector2(cell) * CHUNK_PIXELS + Vector2.ONE * CHUNK_PIXELS * 0.5
	if BiomeBlend.arid_at(mid) < 0.35:
		return
	var frng: RandomNumberGenerator = RandomNumberGenerator.new()
	frng.seed = hash(Vector3i(cell.x, cell.y, _seed + 19427))
	var spec: Dictionary = DataRegistry.get_entry("wildlife", "desert_falcon")
	if frng.randf() > float(spec["chunk_chance"]) or _wild_count() >= int(spec["max_loaded"]) or _species_count("desert_falcon") >= int(spec.get("max_species_loaded", 3)):
		return
	var margin: float = float(spec["spawn_margin"])
	var center: Vector2 = Vector2.ZERO
	var found: bool = false
	for attempt: int in int(spec["spawn_attempts"]):
		var candidate: Vector2 = Vector2(cell) * CHUNK_PIXELS + Vector2(frng.randf_range(margin, CHUNK_PIXELS - margin), frng.randf_range(margin, CHUNK_PIXELS - margin))
		if _floor(candidate, "desert_falcon") and _clear(candidate, 5.0) and _player_clear(candidate, float(spec["alert_range"])):
			center = candidate
			found = true
			break
	if not found:
		return
	var falcon_scene: PackedScene = load(String(spec["scene"])) as PackedScene
	var falcon: WildCorvid = falcon_scene.instantiate() as WildCorvid
	_serial += 1
	falcon.name = "Corvid%d" % _serial
	falcon.species = "desert_falcon"
	if BiomeBlend.is_quartz_surface(center) and frng.randf() < 0.52:
		falcon.appearance = 2
	else:
		falcon.appearance = frng.rand_weighted(PackedFloat32Array([0.48, 0.34, 0.18]))
	falcon.flock_id = "desert_falcon_%d_%d" % [cell.x, cell.y]
	falcon.home = center
	falcon.position = center
	falcon.facing = frng.randf() * TAU
	_birds.add_child(falcon)
	var perch: Dictionary = choose_desert_perch(falcon, Vector2.INF)
	if not perch.is_empty():
		falcon._finish.rpc(perch["position"], perch["height"], perch["path"])
	elif not TimeManager.is_night():
		var soar_h: float = frng.randf_range(78.0, 96.0)
		var dir: Vector2 = Vector2.from_angle(falcon.facing)
		var goal: Vector2 = center + dir * 72.0
		falcon._act.rpc(WildCorvid.State.FLY, 2.6, dir.angle(), center, goal, dir.orthogonal() * 44.0, soar_h, soar_h, soar_h + 4.0, "", 0.0)
	flock.append(falcon)


func _populate_songbirds(cell: Vector2i, flock: Array[WildCorvid]) -> void:
	var seeds: Dictionary = {"woodpecker": 11423, "jay": 13691, "robin": 15803}
	for species: String in ["woodpecker", "jay", "robin"]:
		var srng: RandomNumberGenerator = RandomNumberGenerator.new()
		srng.seed = hash(Vector3i(cell.x, cell.y, _seed + int(seeds[species])))
		var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
		if srng.randf() > float(spec["chunk_chance"]) or _wild_count() >= int(spec["max_loaded"]) or _species_count(species) >= int(spec.get("max_species_loaded", 3)):
			continue
		var margin: float = float(spec["spawn_margin"])
		var center: Vector2 = Vector2.ZERO
		var found: bool = false
		for attempt: int in int(spec["spawn_attempts"]):
			var candidate: Vector2 = Vector2(cell) * CHUNK_PIXELS + Vector2(srng.randf_range(margin, CHUNK_PIXELS - margin), srng.randf_range(margin, CHUNK_PIXELS - margin))
			if not _floor(candidate, species) or not _clear(candidate, 5.0) or not _player_clear(candidate, float(spec["alert_range"])):
				continue
			if species in ["woodpecker", "jay"] and not _near_tree(candidate, 165.0):
				continue
			center = candidate
			found = true
			break
		if not found:
			continue
		var count: int = srng.randi_range(int(spec["group_min"]), int(spec["group_max"]))
		var flock_key: String = "%s_%d_%d" % [species, cell.x, cell.y]
		var scene: PackedScene = load(String(spec["scene"])) as PackedScene
		for i: int in count:
			if _wild_count() >= int(spec["max_loaded"]) or _species_count(species) >= int(spec.get("max_species_loaded", 3)):
				break
			var point: Vector2 = center if i == 0 else (center + Vector2.from_angle(srng.randf() * TAU) * srng.randf_range(16.0, float(spec["group_radius"])))
			if i > 0 and (not _floor(point, species) or not _clear(point, 5.0) or not _player_clear(point, float(spec["alert_range"]))):
				continue
			var bird: WildCorvid = scene.instantiate() as WildCorvid
			_serial += 1
			bird.name = "Corvid%d" % _serial
			bird.species = species
			bird.appearance = srng.randi_range(0, int(spec.get("builds", 3)) - 1)
			bird.flock_id = flock_key
			bird.home = center
			bird.position = point
			bird.facing = srng.randf() * TAU
			_birds.add_child(bird)
			if bool(spec.get("requires_perch", false)):
				var perch: Dictionary = choose_perch(bird, Vector2.INF)
				if perch.is_empty():
					bird.queue_free()
					continue
				bird._finish.rpc(perch["position"], perch["height"], perch["path"])
			flock.append(bird)


func _near_tree(point: Vector2, radius: float) -> bool:
	var r2: float = radius * radius
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree != null and not tree.is_depleted() and not tree.kind in ["bone_tree", "crown_cactus", "sun_palm"] and BiomeBlend.arid_at(tree.global_position) < 0.22 and tree.global_position.distance_squared_to(point) <= r2:
			return true
	return false


## The species' numbers for a chunk with `gloom` (BiomeBlend): a `witch_forest` block in data/wildlife.json raises the chunk chance
## with the gloom and, deep inside (gloom >= 0.5), replaces group size, spawn attempts and the shared cap: the Hexenwald is the corvids' own wood.
static func local_spec(species: String, gloom: float) -> Dictionary:
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	var witch: Dictionary = spec.get("witch_forest", {})
	if witch.is_empty() or gloom <= 0.0:
		return spec
	var local: Dictionary = spec.duplicate()
	local["chunk_chance"] = lerpf(float(spec["chunk_chance"]), float(witch.get("chunk_chance", spec["chunk_chance"])), clampf(gloom, 0.0, 1.0))
	if gloom >= 0.5:
		for key: String in witch:
			if key != "chunk_chance":
				local[key] = witch[key]
	return local


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
		if other != null and other != bird and other.state != WildCorvid.State.FLY and other._height < 1.0 and other.global_position.distance_to(point) < float(bird._spec["personal_space"]):
			return false
	return true


## A companion may land close to its person (the ambient rule keeps birds away from players).
func can_land_companion(point: Vector2, bird: WildCorvid) -> bool:
	return _floor(point, bird.species) and _clear(point, 5.0) and _active.has(_chunk(point))


func choose_perch(bird: WildCorvid, danger: Vector2) -> Dictionary:
	if bird.species == "woodpecker":
		return choose_trunk_perch(bird, danger)
	if bird.species == "desert_falcon":
		return choose_desert_perch(bird, danger)
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
		if tree == null or tree.is_depleted() or tree._falling or tree.kind in ["bone_tree", "crown_cactus", "sun_palm"] or BiomeBlend.arid_at(tree.global_position) >= 0.22:
			continue
		var distance: float = tree.global_position.distance_to(bird.global_position)
		if distance > 340.0 or (danger.is_finite() and tree.global_position.distance_to(danger) < float(bird._spec["safe_landing_range"])):
			continue
		for slot: int in _slot_count(tree):
			var key: String = "%s:%d" % [tree.get_path(), slot]
			var owner: Variant = _claims.get(key)
			if is_instance_valid(owner) and owner != bird:
				continue
			var seat: Dictionary = _slot(tree, slot)
			var value: float = distance + (seat.position as Vector2).distance_to(bird.home) * 0.15
			if value < score:
				score = value
				best = {"position": seat.position, "height": seat.height, "path": String(tree.get_path()), "claim": key}
	if not best.is_empty():
		_claims[String(best["claim"])] = bird
	return best


## Woodpeckers cling directly to visible tree trunks (below the dense fir crown) or forage along fallen trunks.
func choose_trunk_perch(bird: WildCorvid, danger: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var score: float = INF
	if not danger.is_finite() and not bird._rest_time():
		for log_node: FallenLog in get_tree().get_nodes_in_group("fallen_logs"):
			var d_log: float = bird.global_position.distance_to(log_node.perch_point)
			var log_key: String = "%s:log" % log_node.get_path()
			var log_owner: Variant = _claims.get(log_key)
			if d_log < 190.0 and d_log > 16.0 and (not is_instance_valid(log_owner) or log_owner == bird):
				var v_log: float = d_log + 24.0
				if v_log < score:
					score = v_log
					best = {"position": log_node.perch_point, "height": log_node.perch_height, "path": String(log_node.get_path()), "claim": log_key}
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree == null or tree.is_depleted() or tree._falling or tree.kind == "bone_tree" or tree.kind == "crown_cactus" or tree.kind == "sun_palm":
			continue
		var d: float = tree.global_position.distance_to(bird.global_position)
		if d > 310.0 or (not bird._perch_path.is_empty() and String(tree.get_path()) == bird._perch_path) or (danger.is_finite() and tree.global_position.distance_to(danger) < float(bird._spec["safe_landing_range"])):
			continue
		var trunk_key: String = "%s:trunk" % tree.get_path()
		var owner: Variant = _claims.get(trunk_key)
		if is_instance_valid(owner) and owner != bird:
			continue
		var side: float = -3.5 if bird.global_position.x <= tree.global_position.x else 3.5
		var base_h: float = 20.0 if bird._rest_time() else (9.0 if tree.variant == 0 else 11.0)
		var seat_pos: Vector2 = tree.global_position + Vector2(side, 2.0)
		var val: float = d + seat_pos.distance_to(bird.home) * 0.18
		if val < score:
			score = val
			best = {"position": seat_pos, "height": base_h, "path": String(tree.get_path()), "claim": trunk_key}
	if not best.is_empty():
		_claims[String(best["claim"])] = bird
	return best


## Desert falcons perch on tall crown cacti, oasis date-palm crowns, and sun-quartz monoliths.
func choose_desert_perch(bird: WildCorvid, danger: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var score: float = INF
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree == null or tree.is_depleted() or tree._falling or not (tree.kind in ["crown_cactus", "sun_palm"]):
			continue
		var d: float = tree.global_position.distance_to(bird.global_position)
		if d > 360.0 or (danger.is_finite() and tree.global_position.distance_to(danger) < float(bird._spec["safe_landing_range"])):
			continue
		for slot: int in _slot_count(tree):
			var key: String = "%s:%d" % [tree.get_path(), slot]
			var owner: Variant = _claims.get(key)
			if is_instance_valid(owner) and owner != bird:
				continue
			var seat: Dictionary = _slot(tree, slot)
			if tree.kind == "crown_cactus":
				seat = {"position": tree.global_position + Vector2((slot * 2 - 1) * (7.0 if tree.variant >= 2 else 0.0), 1.0), "height": float(tree.spec()["height"][tree.variant]) * 0.88}
			elif tree.kind == "sun_palm":
				seat = {"position": tree.global_position + Vector2(0.0, 1.0), "height": float(tree.spec()["height"][tree.variant]) * 0.78}
			var val: float = d + (seat.position as Vector2).distance_to(bird.home) * 0.15
			if val < score:
				score = val
				best = {"position": seat.position, "height": seat.height, "path": String(tree.get_path()), "claim": key}
	for world: Node in get_tree().get_nodes_in_group("world"):
		var props: Node = world.get_node_or_null("Props")
		if props != null:
			for node: Node in props.get_children():
				var prop: WorldProp = node as WorldProp
				if prop == null or prop.kind != "sun_quartz_rock" or prop.is_depleted() or prop.variant < 1:
					continue
				var dr: float = prop.global_position.distance_to(bird.global_position)
				if dr > 300.0 or (danger.is_finite() and prop.global_position.distance_to(danger) < float(bird._spec["safe_landing_range"])):
					continue
				var rkey: String = "%s:monolith" % prop.get_path()
				var rowner: Variant = _claims.get(rkey)
				if is_instance_valid(rowner) and rowner != bird:
					continue
				var rval: float = dr + 18.0 + prop.global_position.distance_to(bird.home) * 0.15
				if rval < score:
					score = rval
					best = {"position": prop.global_position + Vector2(0.0, 1.0), "height": 18.0 if prop.variant >= 2 else 14.0, "path": String(prop.get_path()), "claim": rkey}
	for node: Node in get_tree().get_nodes_in_group("town_perches"):
		var perch: RoofPerch = node as RoofPerch
		if perch == null or perch.is_depleted() or BiomeBlend.arid_at(perch.global_position) < 0.4:
			continue
		var reach: float = perch.global_position.distance_to(bird.global_position)
		if reach > 360.0 or (danger.is_finite() and perch.global_position.distance_to(danger) < float(bird._spec["safe_landing_range"])):
			continue
		var roof_key: String = "%s:roof" % perch.get_path()
		var roof_owner: Variant = _claims.get(roof_key)
		if is_instance_valid(roof_owner) and roof_owner != bird:
			continue
		var roof_val: float = reach + 10.0 + perch.global_position.distance_to(bird.home) * 0.15
		if roof_val < score:
			score = roof_val
			best = {"position": perch.global_position, "height": perch.perch_height, "path": String(perch.get_path()), "claim": roof_key}
	if not best.is_empty():
		_claims[String(best["claim"])] = bird
	return best


## Branches a tree offers: one on a small tree, three on the others; the bare boughs of a Bleichbaum hold a row of them (2-5), so a whole
## flock of the Hexenwald can sit on one dead tree.
func _slot_count(tree: FirTree) -> int:
	if tree.kind == "bone_tree":
		return 2 + tree.variant
	if tree.kind == "crown_cactus":
		return 1 if tree.variant == 0 else 2
	return 1 if tree.variant == 0 else 3


## Where branch `slot` of `tree` is: the point under it on the ground and its height (one and three slots: as they always were).
func _slot(tree: FirTree, slot: int) -> Dictionary:
	var slots: int = _slot_count(tree)
	var height: float = float(tree.spec()["height"][tree.variant])
	var half: float = float(tree.spec()["crown_half_width"][tree.variant])
	var side: float = (float(slot) / float(slots - 1) * 2.0 - 1.0) if slots > 1 else 0.0
	var rise: float = (0.62 + 0.09 * slot) if slots <= 3 else (0.6 + 0.07 * float((slot * 3) % slots)) ## a row of dead boughs: heights in a zigzag
	return {"position": tree.global_position + Vector2(side * half * (0.45 if slots <= 3 else 0.6), 2.0 + slot * 0.5), "height": height * rise}


## Host: a free branch on a tree within `radius` of `point` (an observing crow of the Hexenwald, see WildCorvid._observe), claimed; {} if none.
func perch_near(bird: WildCorvid, point: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var score: float = INF
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree == null or tree.is_depleted() or tree._falling or tree.global_position.distance_to(point) > radius:
			continue
		for slot: int in _slot_count(tree):
			var key: String = "%s:%d" % [tree.get_path(), slot]
			var owner: Variant = _claims.get(key)
			if is_instance_valid(owner) and owner != bird:
				continue
			var seat: Dictionary = _slot(tree, slot)
			var value: float = (seat.position as Vector2).distance_to(point)
			if value < score:
				score = value
				best = {"position": seat.position, "height": seat.height, "path": String(tree.get_path()), "claim": key}
	if not best.is_empty():
		release_perch(bird)
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
			var watchman: WildCorvid = null
			for candidate: Variant in candidates:
				var perched: WildCorvid = candidate as WildCorvid
				if perched != null and (not perched._perch_path.is_empty() or perched._height > 8.0):
					watchman = perched
					break
			if watchman == null:
				watchman = candidates[turn % candidates.size()] as WildCorvid
			watchman._set_mood(WildCorvid.State.WATCH, watchman._range("watch_seconds"))
			_watch_turns[id] = turn + 1
		if flock.is_empty() and not _active.has(home_cell):
			_flocks.erase(home_cell)
