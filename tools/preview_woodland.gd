extends Node
## Offline real-world wildlife workbench, no save or game-port access.
## Godot --path . tools/preview_woodland.tscn [-- --capture=/absolute/path.png]

class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _make(population: WoodlandPopulation, species: String, appearance: int, at: Vector2) -> WoodlandMammal:
	# The world/relief can change while this workbench remains in use. Place the
	# showcase on current safe ground rather than assuming its old coordinates.
	var radius: float = float(DataRegistry.get_entry("wildlife", species)["body_radius"]) + 3.0
	var found: bool = false
	for ring: int in 12:
		for sector: int in 12:
			var candidate: Vector2 = at + Vector2.from_angle(float(sector) * TAU / 12.0) * float(ring) * 12.0
			if population.home_loaded(candidate) and bool(population._habitat.call(candidate, species)) and population._clear(candidate, radius):
				at = candidate
				found = true
				break
		if found:
			break
	for node: Node in population._residents.get_children():
		var resident: WoodlandMammal = node as WoodlandMammal
		if resident.species == species and resident.appearance == appearance:
			resident.position = at
			resident.home = at
			return resident
	var animal: WoodlandMammal = load("res://src/entities/wildlife/woodland_mammal.tscn").instantiate() as WoodlandMammal
	animal.name = "Preview_%s_%d" % [species, appearance]
	animal.species = species
	animal.appearance = appearance
	animal.position = at
	animal.home = at
	population._residents.add_child(animal)
	return animal


func _run() -> void:
	var capture: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	TimeManager.time_of_day = 0.5 if OS.get_cmdline_user_args().has("--day") else 0.797
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	var center: Vector2 = world._spawn_position(0) + Vector2(-80, -620)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = center + Vector2(-270, 150)
	world.get_node("Players").add_child(player)
	if not capture.is_empty():
		(player.get_node("Camera2D") as Camera2D).enabled = false
		var camera: Camera2D = Camera2D.new()
		camera.position = center + Vector2(0, 25)
		world.add_child(camera)
	for frame: int in 15:
		await get_tree().physics_frame
	var population: WoodlandPopulation = world.get_node("Wildlife/Woodland") as WoodlandPopulation
	var doe: WoodlandMammal = _make(population, "deer", 0, center + Vector2(-155, 70))
	doe.family_id = "preview_family"
	doe.facing = PI * 0.75
	doe._issue(WoodlandMammal.Mood.FORAGE, 4.0)
	var fawn: WoodlandMammal = _make(population, "deer", 2, center + Vector2(-120, 102))
	fawn.family_id = "preview_family"
	fawn.home = doe.home
	fawn.facing = PI * 0.25
	fawn._issue(WoodlandMammal.Mood.FORAGE, 4.0)
	var buck: WoodlandMammal = _make(population, "deer", 1, center + Vector2(-195, 105))
	buck.family_id = "preview_family"
	buck.home = doe.home
	buck.facing = PI * 0.75
	buck._issue(WoodlandMammal.Mood.ALERT, 4.0)
	var badger: WoodlandMammal = _make(population, "badger", 0, center + Vector2(180, 120))
	badger.facing = PI
	badger._issue(WoodlandMammal.Mood.SPECIAL, 3.5)
	var den: WildlifeShelter = load("res://src/entities/wildlife/wildlife_shelter.tscn").instantiate() as WildlifeShelter
	den.name = "PreviewDen"
	den.position = badger.home + Vector2(16, -12)
	population.get_node("Shelters").add_child(den)
	var fox: WoodlandMammal = _make(population, "fox", 0, center + Vector2(100, 92))
	fox.facing = PI * 1.25
	fox._issue(WoodlandMammal.Mood.LISTEN, 4.0)
	var hedgehog: WoodlandMammal = _make(population, "hedgehog", 0, center + Vector2(15, 123))
	hedgehog.facing = PI * 0.75
	hedgehog._issue(WoodlandMammal.Mood.FORAGE, 4.0)
	var points: Array[Vector2] = []
	for cell: Vector2i in world._chunks:
		for flower: Vector2 in world._flower_targets(cell):
			if flower.distance_to(center + Vector2(5, 65)) < 75.0:
				points.append(flower)
	var insects: ButterflyPopulation = world.get_node("Wildlife/MeadowInsects") as ButterflyPopulation
	for i: int in mini(3, points.size()):
		var insect: MeadowButterfly = load("res://src/entities/wildlife/meadow_butterfly.tscn").instantiate() as MeadowButterfly
		insect.name = "PreviewFlutter%d" % i
		insect.appearance = i
		insect.position = points[i]
		insect.home = points[i]
		insect.flowers = points
		insects._butterflies.add_child(insect)
	if not capture.is_empty():
		for frame: int in 18:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var error: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("Woodland capture: ", error_string(error))
		get_tree().quit(error)
