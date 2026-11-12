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
	check(pop.enabled_kinds == ["heron", "otter", "duck"], "Live river fauna must spawn heron, otter, and duck by default")
	var data: Dictionary = DataRegistry.table("rivers_baked")
	for key: String in data["chunks"]:
		var cell: Vector2i = Vector2i(int(key.get_slice(",", 0)), int(key.get_slice(",", 1)))
		pop.chunk_loaded(cell)
		pop._populate(cell)
		for animal: RiverAnimal in pop.animals.get_children():
			check(animal.kind in ["heron", "otter", "duck"], "Unexpected river species spawned in live river fauna")
		pop.chunk_unloaded(cell)
	await get_tree().process_frame
	pop.enabled_kinds = ["shoal", "brook", "frog", "strider", "dragonfly", "heron", "otter", "kingfisher", "duck"]
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
		for kind: String in ["shoal", "brook", "frog", "strider", "dragonfly", "heron", "otter", "kingfisher", "duck"]:
			check(pop.count(kind) <= int(DataRegistry.get_entry("river_animals", kind)["cap"]), "Population exceeded species cap")
		details.queue_free()
		pop.chunk_unloaded(cell)
		await get_tree().process_frame
		check(pop.animals.get_child_count() == 0, "Unloaded river animals leaked")
	check(seen.size() == 9, "Not all nine species populate")
	for sheet: String in ["heron", "otter", "frog", "kingfisher", "duck"]:
		var spec: Dictionary = DataRegistry.get_entry("river_animals", sheet)
		var texture: Texture2D = load(String(spec.sheet)) as Texture2D
		var cell_px: int = 64 if sheet in ["heron", "otter", "duck"] else 32
		check(texture.get_size() == Vector2(int(spec.cols) * cell_px, int(spec.builds) * 8 * cell_px), "%s sheet contract broken" % sheet)
	var tex: Texture2D = load("res://assets/water/river_animals.png") as Texture2D
	check(tex.get_size() == Vector2(192, 960), "Animal atlas contract broken")
	# Benchmark heron checks: 58 cols, 3 builds, alert lookout, one-leg rest, autonomous shallow-water strike, glide
	var heron: RiverAnimal = load("res://src/water/river_animal.tscn").instantiate() as RiverAnimal
	heron.name = "BenchmarkHeron"
	heron.kind = "heron"
	heron.school = "heron_bench"
	heron.home = Vector2(256, 256)
	heron.position = heron.home
	pop.animals.add_child(heron)
	heron.set_physics_process(false)
	check(heron._sprite.hframes == 58 and heron._sprite.vframes == 24, "Heron 58x24 benchmark frame grid not configured")
	check(heron._sprite.material != null, "Heron lacks daylight world shader material")
	heron._act(RiverAnimal.Mode.REST, heron.position, heron.position, Vector2.ZERO, 2.0, 0.0, 0.4, 5)
	check(heron._column() in range(4, 8), "Heron one-leg tucked rest column mismatch")
	heron._act(RiverAnimal.Mode.REST, heron.position, heron.position, Vector2.ZERO, 2.0, 0.0, 0.4, 4)
	check(heron._column() in range(34, 38), "Heron stretched-neck alert column mismatch")
	heron._act(RiverAnimal.Mode.STRIKE, heron.position, heron.position, Vector2.ZERO, 2.1, 0.0, 1.6, 1)
	check(heron._column() in range(26, 30), "Heron catch fish-in-bill column mismatch")
	heron._act(RiverAnimal.Mode.FLY, heron.position, heron.position + Vector2(120, 0), Vector2.ZERO, 3.0, 0.0, 1.5, 0)
	check(heron._column() in range(46, 50), "Heron mid-flight river glide column mismatch")
	heron.queue_free()
	var otter: RiverAnimal = load("res://src/water/river_animal.tscn").instantiate() as RiverAnimal
	otter.name = "BenchmarkOtter"
	otter.kind = "otter"
	otter.school = "otter_bench"
	otter.home = Vector2(256, 256)
	otter.position = otter.home
	pop.animals.add_child(otter)
	otter.set_physics_process(false)
	check(otter._sprite.hframes == 58 and otter._sprite.vframes == 24, "Otter 58x24 benchmark frame grid not configured")
	otter._act(RiverAnimal.Mode.REST, otter.position, otter.position, Vector2.ZERO, 2.0, 0.0, 0.4, 4)
	check(otter._column() in range(8, 12), "Otter upright periscope column mismatch")
	otter._act(RiverAnimal.Mode.PLUNGE, otter.position, otter.position, Vector2.ZERO, 0.6, 0.0, 0.25, 1)
	check(otter._column() in range(28, 34), "Otter porpoise plunge column mismatch")
	otter._act(RiverAnimal.Mode.STRIKE, otter.position, otter.position, Vector2.ZERO, 3.0, 0.0, 2.0, 1)
	check(otter._column() in range(44, 52), "Otter back-floating fish feast column mismatch")
	otter.queue_free()
	var drake: RiverAnimal = load("res://src/water/river_animal.tscn").instantiate() as RiverAnimal
	drake.name = "BenchmarkDrake"
	drake.kind = "duck"
	drake.school = "duck_pair"
	drake.member = 0
	drake.home = Vector2(256, 256)
	drake.position = drake.home
	pop.animals.add_child(drake)
	drake.set_physics_process(false)
	var duckling: RiverAnimal = load("res://src/water/river_animal.tscn").instantiate() as RiverAnimal
	duckling.name = "BenchmarkDuckling"
	duckling.kind = "duck"
	duckling.school = "duckfamily_bench"
	duckling.member = 1
	duckling.home = Vector2(256, 256)
	duckling.position = duckling.home
	pop.animals.add_child(duckling)
	duckling.set_physics_process(false)
	check(drake._sprite.hframes == 58 and drake._sprite.vframes == 24, "Duck 58x24 benchmark frame grid not configured")
	check(drake._build() == 0 and duckling._build() == 2, "Mallard drake / duckling build mapping mismatch")
	drake._act(RiverAnimal.Mode.DABBLE, drake.position, drake.position, Vector2.ZERO, 2.4, 0.0, 1.2, 0)
	check(drake._column() in range(10, 16), "Duck up-ending dabble column mismatch")
	drake.position = Vector2(0, 0) ## dry bank (field.x > 0)
	drake._act(RiverAnimal.Mode.TRAVEL, drake.position, drake.position + Vector2(12, 0), Vector2.ZERO, 1.0, 0.0, 0.4, 0)
	check(drake._column() in range(38, 46), "Duck grassy shore waddle column mismatch")
	drake._act(RiverAnimal.Mode.REST, drake.position, drake.position, Vector2.ZERO, 3.0, 0.0, 0.8, 5)
	check(drake._column() in range(52, 58), "Duck shore tucked-bill sleep column mismatch")
	drake.queue_free()
	duckling.queue_free()
	print("River animals: %d checks, %d failures, species %s" % [checks, failures, seen.keys()])
	get_tree().quit(0 if failures == 0 else 1)
