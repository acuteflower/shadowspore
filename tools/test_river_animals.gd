extends Node
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
var checks: int = 0
var failures: int = 0
func _ready() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _run() -> void:
	var rivers: WorldRivers = WorldRivers.new()
	add_child(rivers)
	var pop: RiverFauna = rivers.fauna
	pop.set_process(false)
	var data: Dictionary = DataRegistry.table("rivers_baked")
	var seen: Dictionary = {}
	for key: String in data["chunks"]:
		var cell: Vector2i = Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
		pop.chunk_loaded(cell)
		var details: RiverDetails = RiverDetails.new()
		add_child(details)
		details.setup(rivers, cell)
		pop._populate(cell)
		for animal: RiverAnimal in pop.animals.get_children():
			animal.set_physics_process(false)
			seen[animal.kind] = true
			check(animal.position.distance_to(animal.home) < 20, "Animal spawned outside home")
			if animal.kind in ["shoal", "brook", "strider", "duck"]: check(rivers.field_at(animal.position).x < 0, "Water animal spawned on land")
			if animal.kind == "heron": check(rivers.field_at(animal.position).x > -7.0 and rivers.field_at(animal.position).y < 0.5, "Heron spawned in deep water")
			var original: Vector2 = animal.position
			for i: int in 12:
				animal._choose()
				if animal._moving:
					if animal.mode in [RiverAnimal.Mode.FLY, RiverAnimal.Mode.PLUNGE]: check(pop.valid_flight(animal, animal._end), "Flight leaves the chunk")
					else: check(pop.valid_route(animal, animal._end, animal._curve), "Invalid chosen route")
					animal._elapsed = animal._duration * 0.5
					animal._physics_process(0.0)
					if animal.kind in ["shoal", "brook", "strider"]: check(rivers.field_at(animal.position).x < 0, "Animal crossed dry land")
					animal._elapsed = animal._duration
					animal._physics_process(0.0)
			check(not pop.valid_route(animal, animal.home + Vector2(1000, 0), Vector2.ZERO), "Route escaped home bounds")
			if animal.kind == "brook":
				animal._fear_left = 0
				animal._act(RiverAnimal.Mode.TRAVEL, animal.position, animal.position, Vector2.ZERO, 0.1, 0, 0, 0)
				animal._choose()
				check(absf(angle_difference(animal.facing, (-pop.flow_at(animal.position)).angle())) < 0.01, "Bachfish does not hold upstream")
			if animal.kind == "dragonfly":
				TimeManager.time_of_day = 0.97
				animal.position = animal.home
				animal._choose()
				check(animal.mode == RiverAnimal.Mode.PERCH, "Dragonfly failed night rest")
				TimeManager.time_of_day = 0.5
			animal.position = original
		for kind: String in ["shoal", "brook", "frog", "strider", "dragonfly", "heron", "kingfisher", "duck"]:
			check(pop.count(kind) <= int(DataRegistry.get_entry("river_animals", kind)["cap"]), "Population exceeded species cap")
		details.queue_free()
		pop.chunk_unloaded(cell)
		await get_tree().process_frame
		check(pop.animals.get_child_count() == 0, "Unloaded river animals leaked")
	check(seen.size() == 8, "Not all eight species populate")
	for sheet: String in ["heron", "frog", "kingfisher", "duck"]:
		var spec: Dictionary = DataRegistry.get_entry("river_animals", sheet)
		var texture: Texture2D = load(String(spec.sheet)) as Texture2D
		check(texture.get_size() == Vector2(int(spec.cols) * (64 if sheet == "heron" else (40 if sheet == "duck" else 32)), int(spec.builds) * 8 * (64 if sheet == "heron" else (40 if sheet == "duck" else 32))), "%s sheet contract broken" % sheet)
	var tex: Texture2D = load("res://assets/water/river_animals.png") as Texture2D
	check(tex.get_size() == Vector2(192, 960), "Animal atlas contract broken")
	print("River animals: %d checks, %d failures, species %s" % [checks, failures, seen.keys()])
	get_tree().quit(0 if failures == 0 else 1)
