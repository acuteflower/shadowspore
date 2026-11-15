class_name WoodlandPopulation
extends Node2D
## Sparse ground residents with stable homes. Tree-sort chain remains continuous through Residents.

const CHUNK_PIXELS: float = 512.0
const FEATURE_PAD: float = 140.0
const SHELTER_SCENE: PackedScene = preload("res://src/entities/wildlife/wildlife_shelter.tscn")
const MAMMAL_SCENE: PackedScene = preload("res://src/entities/wildlife/woodland_mammal.tscn")
static var _scene_cache: Dictionary = {}
var enabled_species: Array[String] = ["deer", "fox", "boar", "lynx", "squirrel", "badger", "hex_goat", "hex_toad", "oryx", "fennec", "jerboa", "agama"]
var _seed: int = 0
var _habitat: Callable
var _active: Dictionary = {}
var _families: Dictionary = {}
var _shelters: Dictionary = {}
var _pending: Array[Vector2i] = []
var _pending_tasks: Array[Dictionary] = [] ## sliced per species group so runtime streaming stays sub-ms
var _visitors: Array[WoodlandMammal] = []
var _serial: int = 0
var _maintenance: float = 0.0
var _clear_shape: CircleShape2D
var _clear_query: PhysicsShapeQueryParameters2D

@onready var _residents: Node2D = $Residents


static func _scene(path: String) -> PackedScene:
	var cached: Variant = _scene_cache.get(path)
	if cached is PackedScene:
		return cached as PackedScene
	var packed: PackedScene = load(path) as PackedScene
	if packed != null:
		_scene_cache[path] = packed
	return packed


func _ready() -> void:
	_scene_cache["res://src/entities/wildlife/woodland_mammal.tscn"] = MAMMAL_SCENE
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
	for i: int in range(_pending_tasks.size() - 1, -1, -1):
		if (_pending_tasks[i]["cell"] as Vector2i) == cell:
			_pending_tasks.remove_at(i)


func _process(delta: float) -> void:
	if _pending_tasks.is_empty() and not _pending.is_empty():
		var next_cell: Vector2i = _pending.pop_front()
		if _active.has(next_cell) and not _families.has(next_cell):
			var residents: Array[WoodlandMammal] = []
			_families[next_cell] = residents
			_pending_tasks.append({"cell": next_cell, "idx": 0, "residents": residents, "features": {}})
	if not _pending_tasks.is_empty():
		var task: Dictionary = _pending_tasks[0]
		var task_cell: Vector2i = task["cell"] as Vector2i
		if not _active.has(task_cell):
			_pending_tasks.remove_at(0)
		else:
			var budget_end: int = Time.get_ticks_usec() + 1400
			if not bool(task.get("ready", false)):
				task["features"] = _collect_cell_features(task_cell)
				task["ready"] = true
			var idx: int = int(task["idx"])
			while idx < enabled_species.size() and Time.get_ticks_usec() < budget_end:
				_populate_species(task_cell, enabled_species[idx], task["residents"] as Array[WoodlandMammal], task["features"] as Dictionary)
				idx += 1
			task["idx"] = idx
			if idx >= enabled_species.size():
				_pending_tasks.remove_at(0)
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
	if _clear_shape == null:
		_clear_shape = CircleShape2D.new()
		_clear_query = PhysicsShapeQueryParameters2D.new()
		_clear_query.shape = _clear_shape
		_clear_query.collision_mask = 1
	_clear_shape.radius = radius
	_clear_query.transform = Transform2D(0.0, point)
	return get_world_2d().direct_space_state.intersect_shape(_clear_query, 1).is_empty()


func can_stand(point: Vector2, animal: WoodlandMammal) -> bool:
	return home_loaded(point) and _habitat.is_valid() and bool(_habitat.call(point, animal.species))


func _spawn_safe(point: Vector2, species: String, spec: Dictionary = {}) -> bool:
	if not _habitat.is_valid() or not bool(_habitat.call(point, species)):
		return false
	var entry: Dictionary = spec if not spec.is_empty() else DataRegistry.get_entry("wildlife", species)
	if not _clear(point, float(entry["body_radius"]) + 2.0):
		return false
	var alert_r2: float = float(entry["alert_range"])
	alert_r2 *= alert_r2
	for player: Player in Player.all:
		if player.global_position.distance_squared_to(point) < alert_r2:
			return false
	for node: Node in _residents.get_children():
		if (node as Node2D).global_position.distance_squared_to(point) < 324.0:
			return false
	return true


func _collect_cell_features(cell: Vector2i) -> Dictionary:
	var rect: Rect2 = Rect2(Vector2(cell) * CHUNK_PIXELS - Vector2(FEATURE_PAD, FEATURE_PAD), Vector2.ONE * (CHUNK_PIXELS + FEATURE_PAD * 2.0))
	var cover_pts: PackedVector2Array = PackedVector2Array()
	var rock_pts: PackedVector2Array = PackedVector2Array()
	var conifer_pts: PackedVector2Array = PackedVector2Array()
	var shade_pts: PackedVector2Array = PackedVector2Array()
	var log_pts: PackedVector2Array = PackedVector2Array()
	var toad_pts: PackedVector2Array = PackedVector2Array()
	var world_node: Node = get_tree().get_first_node_in_group("world")
	var used_chunks: bool = false
	if world_node != null:
		var chunks_var: Variant = world_node.get("_chunks")
		if chunks_var is Dictionary and not (chunks_var as Dictionary).is_empty():
			used_chunks = true
			var chunks_dict: Dictionary = chunks_var as Dictionary
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var chunk_obj: Variant = chunks_dict.get(cell + Vector2i(dx, dy))
					if chunk_obj == null:
						continue
					for thing: WorldProp in (chunk_obj as WorldLevel.Chunk).things:
						if thing == null or not is_instance_valid(thing):
							continue
						var p: Vector2 = thing.global_position
						if not rect.has_point(p):
							continue
						var k: String = thing.kind
						if k == "tree" or k == "bush" or k == "berry_bush" or k == "hex_shrub" or k == "witch_broom":
							cover_pts.append(p)
						elif k == "sun_quartz_rock" or k == "desert_scrub" or k == "crown_cactus" or k == "prickly_pear":
							rock_pts.append(p)
	if not used_chunks:
		for world: Node in get_tree().get_nodes_in_group("world"):
			var props: Node = world.get_node_or_null("Props")
			if props != null:
				for node: Node in props.get_children():
					var n2: Node2D = node as Node2D
					if n2 == null or not rect.has_point(n2.global_position):
						continue
					var prop: WorldProp = node as WorldProp
					if prop != null:
						var k: String = prop.kind
						if k == "tree" or k == "bush" or k == "berry_bush" or k == "hex_shrub" or k == "witch_broom":
							cover_pts.append(prop.global_position)
						elif k == "sun_quartz_rock" or k == "desert_scrub" or k == "crown_cactus" or k == "prickly_pear":
							rock_pts.append(prop.global_position)
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree == null or not rect.has_point(tree.global_position):
			continue
		if not tree.is_depleted() and tree.kind != "bone_tree":
			conifer_pts.append(tree.global_position)
		if tree.kind == "sun_palm" or tree.kind == "crown_cactus":
			shade_pts.append(tree.global_position)
	for log_node: FallenLog in get_tree().get_nodes_in_group("fallen_logs"):
		if rect.has_point(log_node.global_position):
			log_pts.append(log_node.global_position)
	for spot: Node in get_tree().get_nodes_in_group("toad_spots"):
		if spot is Node2D and rect.has_point((spot as Node2D).global_position):
			toad_pts.append((spot as Node2D).global_position)
	return {"cover": cover_pts, "rock": rock_pts, "conifer": conifer_pts, "shade": shade_pts, "log": log_pts, "toad": toad_pts}


static func _min_dist_pts(point: Vector2, pts: PackedVector2Array, max_dist: float) -> float:
	var best_sq: float = max_dist * max_dist
	var found: bool = false
	for p: Vector2 in pts:
		var d2: float = p.distance_squared_to(point)
		if d2 < best_sq:
			best_sq = d2
			found = true
	return sqrt(best_sq) if found else max_dist


func _cover_score(point: Vector2, features: Dictionary = {}) -> float:
	if not features.is_empty():
		return -_min_dist_pts(point, features["cover"] as PackedVector2Array, 120.0)
	var nearest: float = 120.0
	for world: Node in get_tree().get_nodes_in_group("world"):
		var props: Node = world.get_node_or_null("Props")
		if props != null:
			for node: Node in props.get_children():
				var n2: Node2D = node as Node2D
				if n2 == null or n2.global_position.distance_squared_to(point) >= nearest * nearest:
					continue
				var prop: WorldProp = node as WorldProp
				if prop != null and prop.kind in ["tree", "bush", "berry_bush", "hex_shrub", "witch_broom"]:
					nearest = prop.global_position.distance_to(point)
	return -nearest


func _nearest_conifer_distance(point: Vector2, features: Dictionary = {}) -> float:
	if not features.is_empty():
		var pts: PackedVector2Array = features["conifer"] as PackedVector2Array
		if pts.is_empty():
			return INF
		var best_sq: float = INF
		for p: Vector2 in pts:
			best_sq = minf(best_sq, p.distance_squared_to(point))
		return sqrt(best_sq) if is_finite(best_sq) else INF
	var nearest: float = INF
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: FirTree = node as FirTree
		if tree != null and not tree.is_depleted() and tree.kind != "bone_tree":
			nearest = minf(nearest, tree.global_position.distance_to(point))
	return nearest


func _nearest_log_distance(point: Vector2, features: Dictionary = {}) -> float:
	if not features.is_empty():
		var pts: PackedVector2Array = features["log"] as PackedVector2Array
		if pts.is_empty():
			return INF
		var best_sq: float = INF
		for p: Vector2 in pts:
			best_sq = minf(best_sq, p.distance_squared_to(point))
		return sqrt(best_sq) if is_finite(best_sq) else INF
	var nearest: float = INF
	for log_node: FallenLog in get_tree().get_nodes_in_group("fallen_logs"):
		nearest = minf(nearest, log_node.global_position.distance_to(point))
	return nearest


func _habitat_score(point: Vector2, species: String, rng: RandomNumberGenerator, features: Dictionary = {}) -> float:
	if species == "deer":
		return rng.randf()
	if species == "squirrel":
		var tree_d: float = _nearest_conifer_distance(point, features)
		if tree_d > 105.0 and tree_d < INF:
			return -INF
		if tree_d == INF:
			return _cover_score(point, features)
		return -tree_d + rng.randf() * 8.0
	if species == "lynx":
		var log_d: float = _nearest_log_distance(point, features)
		var cover: float = _cover_score(point, features)
		if cover < -95.0 and log_d > 110.0:
			return -INF
		return maxf(cover, -log_d) + rng.randf() * 6.0
	if species == "boar":
		var log_bonus: float = 18.0 if _nearest_log_distance(point, features) < 65.0 else 0.0
		return _cover_score(point, features) + log_bonus + rng.randf() * 10.0
	if species == "hex_goat":
		if BiomeBlend.amount_at(point) < 0.30:
			return -INF
		return _cover_score(point, features) * 0.5 + rng.randf() * 16.0
	if species == "hex_toad":
		if BiomeBlend.amount_at(point) < 0.35:
			return -INF
		var best: float = 130.0
		if not features.is_empty():
			best = minf(best, _min_dist_pts(point, features["toad"] as PackedVector2Array, 130.0))
			best = minf(best, _min_dist_pts(point, features["log"] as PackedVector2Array, 130.0))
		else:
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
			if not features.is_empty():
				for p: Vector2 in (features["shade"] as PackedVector2Array):
					if p.distance_squared_to(point) < 12100.0:
						shade_bonus = 24.0
						break
			else:
				for node: Node in get_tree().get_nodes_in_group("bird_perches"):
					var tr: FirTree = node as FirTree
					if tr != null and tr.kind in ["sun_palm", "crown_cactus"] and tr.global_position.distance_to(point) < 110.0:
						shade_bonus = maxf(shade_bonus, 24.0)
			return oasis * 48.0 + shade_bonus + rng.randf() * 14.0
		if species == "fennec":
			var rock_near: float = 120.0
			if not features.is_empty():
				rock_near = _min_dist_pts(point, features["rock"] as PackedVector2Array, 120.0)
			else:
				for world: Node in get_tree().get_nodes_in_group("world"):
					var props: Node = world.get_node_or_null("Props")
					if props != null:
						for node: Node in props.get_children():
							var n2: Node2D = node as Node2D
							if n2 == null or n2.global_position.distance_squared_to(point) >= rock_near * rock_near:
								continue
							var prop: WorldProp = node as WorldProp
							if prop != null and prop.kind in ["sun_quartz_rock", "desert_scrub", "crown_cactus", "prickly_pear"]:
								rock_near = prop.global_position.distance_to(point)
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
	return _cover_score(point, features)


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
	var features: Dictionary = _collect_cell_features(cell)
	for species: String in enabled_species:
		_populate_species(cell, species, residents, features)


func _populate_species(cell: Vector2i, species: String, residents: Array[WoodlandMammal], features: Dictionary) -> void:
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, _seed + hash(species)))
	var max_loaded: int = Quality.scaled(int(spec["max_loaded"]), "wildlife", 1)
	var max_sp: int = int(spec["max_species_loaded"])
	var total_now: int = _residents.get_child_count()
	var sp_now: int = _count(species)
	if total_now >= max_loaded or sp_now >= max_sp or rng.randf() > float(spec["chunk_chance"]):
		return
	var center: Vector2 = Vector2.ZERO
	var score: float = -INF
	var margin: float = float(spec["spawn_margin"])
	for attempt: int in int(spec["spawn_attempts"]):
		var point: Vector2 = Vector2(cell) * CHUNK_PIXELS + Vector2(rng.randf_range(margin, CHUNK_PIXELS - margin), rng.randf_range(margin, CHUNK_PIXELS - margin))
		if _spawn_safe(point, species, spec):
			var value: float = _habitat_score(point, species, rng, features)
			if value > score:
				score = value
				center = point
	if score == -INF:
		return
	var count: int = rng.randi_range(int(spec["group_min"]), int(spec["group_max"]))
	var spawned: int = 0
	var scene: PackedScene = _scene(String(spec["scene"]))
	var nocturnal: bool = bool(spec["nocturnal"])
	var night_now: float = TimeManager.night_amount()
	for i: int in count:
		if total_now >= max_loaded or sp_now >= max_sp:
			break
		var spacing: Vector2 = Vector2(16.0 * i, 10.0 * i) if species in ["jerboa", "agama", "fennec"] else (Vector2(19.0 * i, 12.0 * i) if species in ["boar", "squirrel", "hex_toad"] else Vector2(25.0 * i, 15.0 * i))
		var point: Vector2 = center + spacing
		if not _spawn_safe(point, species, spec):
			continue
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
		total_now += 1
		sp_now += 1
		if nocturnal and night_now < float(spec.get("awake_threshold", 0.4)):
			var hide_in_den: bool = species in ["badger", "jerboa"] or (species == "fennec" and rng.randf() < 0.55)
			animal._command.rpc(WoodlandMammal.Mood.HIDDEN if hide_in_den else WoodlandMammal.Mood.SLEEP, animal._range("sleep_seconds"), animal.facing, center if hide_in_den else point, center if hide_in_den else point, 0.0)
		elif species == "agama" and night_now > 0.38:
			animal._command.rpc(WoodlandMammal.Mood.HIDDEN, animal._range("sleep_seconds"), animal.facing, center, center, 0.0)
	if (species in ["badger", "fennec"] or (species == "jerboa" and rng.randf() < 0.55)) and spawned > 0:
		# A normal spawned scene, so joining peers see the same fixed den entrance.
		var shelter: WildlifeShelter = SHELTER_SCENE.instantiate() as WildlifeShelter
		shelter.name = "Den%d" % _serial
		shelter.shelter_kind = "desert_burrow" if species in ["fennec", "jerboa"] else "badger_den"
		shelter.position = center
		$Shelters.add_child(shelter)
		var cell_shelters: Array = _shelters.get_or_add(cell, []) as Array
		cell_shelters.append(shelter)


## A visitor of the town (TownCritters): one animal of `species` at `point` that goes to `to` and sniffs towards `look`. Null when the caps or the ground forbid it.
func spawn_visitor(species: String, point: Vector2, to: Vector2, look: Vector2) -> WoodlandMammal:
	var spec: Dictionary = DataRegistry.get_entry("wildlife", species)
	if _count(species) >= int(spec["max_species_loaded"]) or _residents.get_child_count() >= Quality.scaled(int(spec["max_loaded"]), "wildlife", 1) or not _spawn_safe(point, species):
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
