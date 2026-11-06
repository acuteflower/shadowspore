extends Node
## Real-world offline workbench, standard movement controls, no save access.
## Godot --path . tools/preview_meadow_birds.tscn [-- --night --capture=/absolute/path.png]

class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _make(population: CorvidPopulation, species: String, point: Vector2) -> WildMeadowBird:
	for node: Node in population._birds.get_children():
		if node is WildMeadowBird and (node as WildMeadowBird).species == species:
			return node as WildMeadowBird
	var bird: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
	bird.name = "Preview_" + species
	bird.species = species
	bird.appearance = 0
	bird.position = point
	bird.home = point
	bird.flock_id = "preview_" + species
	population._birds.add_child(bird)
	return bird


func _run() -> void:
	var capture: String = ""
	var night: bool = OS.get_cmdline_user_args().has("--night")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	TimeManager.time_of_day = 0.97 if night else 0.5
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	var center: Vector2 = world._spawn_position(0) + Vector2(0, -550)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = center + Vector2(-185, 88)
	world.get_node("Players").add_child(player)
	if not capture.is_empty():
		(player.get_node("Camera2D") as Camera2D).enabled = false
		var camera: Camera2D = Camera2D.new()
		camera.position = center + Vector2(-20, -40)
		world.add_child(camera)
	var population: CorvidPopulation = world.get_node("Wildlife/Corvids") as CorvidPopulation
	var owl: WildMeadowBird = _make(population, "owl", center + Vector2(90, 0))
	var branch: Dictionary = population.choose_perch(owl, Vector2.INF)
	if not branch.is_empty():
		owl._finish(branch["position"], branch["height"], branch["path"])
		owl.facing = PI * 0.5
	if night:
		var start: Vector2 = owl.global_position
		owl._act(WildCorvid.State.FLY, 4.0, PI, start, center + Vector2(-40, 85), Vector2(-26, 26), owl._height, 0.0, maxf(owl._height + 16.0, 80.0), "", 2.1)
	var hoopoe: WildMeadowBird = _make(population, "hoopoe", center + Vector2(65, 60))
	hoopoe.position = center + Vector2(65, 60)
	hoopoe.home = hoopoe.position
	hoopoe.facing = PI * 0.75
	if night:
		var perch: Dictionary = population.choose_perch(hoopoe, Vector2.INF)
		if not perch.is_empty():
			hoopoe._finish(perch["position"], perch["height"], perch["path"])
	else:
		hoopoe._set_mood(WildCorvid.State.WATCH, 1.8)
	if not capture.is_empty():
		for frame: int in 20:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var error: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("Meadow bird capture: ", error_string(error))
		get_tree().quit(error)
