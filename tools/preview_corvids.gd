extends Node
## Live offline bird workbench in the real meadow. Normal movement controls; no save access.
## Godot --path . tools/preview_corvids.tscn [-- --capture=/absolute/path.png]

class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var capture: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	TimeManager.time_of_day = 0.5
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	var center: Vector2 = world._spawn_position(0) + Vector2(0, -550)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = center + Vector2(0, 110)
	world.get_node("Players").add_child(player)
	if not capture.is_empty():
		(player.get_node("Camera2D") as Camera2D).enabled = false
		var camera: Camera2D = Camera2D.new()
		camera.position = center + Vector2(0, -55)
		world.add_child(camera)
	var population: CorvidPopulation = world.get_node("Wildlife/Corvids") as CorvidPopulation
	var poses: Array[Vector2] = [Vector2(-135, 62), Vector2(-90, 44), Vector2(-55, 74), Vector2(95, 58), Vector2(135, 38)]
	for i: int in poses.size():
		var bird: WildCorvid = load("res://src/entities/wildlife/wild_corvid.tscn").instantiate() as WildCorvid
		bird.name = "PreviewCorvid%d" % i
		bird.species = "crow" if i < 3 else "raven"
		bird.appearance = i % 3
		bird.position = center + poses[i]
		bird.home = bird.position
		bird.flock_id = "preview_crows" if i < 3 else "preview_ravens"
		bird.facing = i * PI / 4.0
		population._birds.add_child(bird)
		bird._set_mood(WildCorvid.State.WATCH if i == 0 else WildCorvid.State.PECK, 4.0)
		if i == 4:
			var perch: Dictionary = population.choose_perch(bird, Vector2.INF)
			if not perch.is_empty():
				bird._finish(perch["position"], perch["height"], perch["path"])
	# One individual demonstrates the arc across the open foreground in the capture.
	var flyer: WildCorvid = load("res://src/entities/wildlife/wild_corvid.tscn").instantiate() as WildCorvid
	flyer.name = "PreviewFlyer"
	flyer.home = center
	flyer.position = center + Vector2(-170, 100)
	population._birds.add_child(flyer)
	flyer._act(WildCorvid.State.FLY, 3.0, 0.0, flyer.position, center + Vector2(145, 90), Vector2(0, -48), 0.0, 0.0, 68.0, "", 1.1 if not capture.is_empty() else 0.0)
	if not capture.is_empty():
		for frame: int in 22:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var error: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("Corvid meadow capture: ", error_string(error))
		get_tree().quit(error)
