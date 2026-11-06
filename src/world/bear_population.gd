class_name BearPopulation
extends WoodlandPopulation
## Sparse families are separate from small woodland residents' eight-animal budget.
func _populate(cell: Vector2i) -> void:
	if _families.has(cell):
		return
	var residents: Array[WoodlandMammal] = []
	_families[cell] = residents
	var spec: Dictionary = DataRegistry.get_entry("wildlife", "bear")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, _seed + 72539))
	if _count("bear") >= int(spec["max_loaded"]) or rng.randf() > float(spec["chunk_chance"]):
		return
	var center: Vector2
	var found: bool = false
	for attempt: int in int(spec["spawn_attempts"]):
		var margin: float = float(spec["spawn_margin"])
		center = Vector2(cell) * CHUNK_PIXELS + Vector2(rng.randf_range(margin, CHUNK_PIXELS - margin), rng.randf_range(margin, CHUNK_PIXELS - margin))
		if _spawn_safe(center, "bear"):
			found = true
			break
	if not found:
		return
	var count: int = rng.randi_range(2, 3) if rng.randf() < float(spec["family_chance"]) else 1
	for i: int in count:
		if _count("bear") >= int(spec["max_loaded"]):
			break
		var point: Vector2 = center
		var safe: bool = i == 0
		if i > 0:
			for attempt: int in 12:
				point = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(25.0, 48.0)
				if _spawn_safe(point, "bear"):
					safe = true
					break
		if not safe:
			continue
		var bear: WildBear = load(String(spec["scene"])).instantiate() as WildBear
		_serial += 1
		bear.name = "Bear%d" % _serial
		bear.appearance = rng.randi_range(0, 1) if i == 0 else 2
		bear.position = point
		bear.home = center
		bear.family_id = "bear_%d_%d" % [cell.x, cell.y]
		bear.facing = rng.randf() * TAU
		_residents.add_child(bear)
		residents.append(bear)

func _collect() -> void:
	# Keep a whole family while any member or its current route is still loaded.
	for cell: Vector2i in _families.keys():
		var family: Array[WoodlandMammal] = _families[cell]
		var keep: bool = _active.has(cell)
		for bear: WoodlandMammal in family:
			if is_instance_valid(bear) and (home_loaded(bear.global_position) or bear._moving and home_loaded(bear._end)):
				keep = true
		if not keep:
			for bear: WoodlandMammal in family:
				if is_instance_valid(bear):
					bear.queue_free()
			_families.erase(cell)
