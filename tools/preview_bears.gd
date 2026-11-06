extends Node
## Actual world showcase. -- --capture=/absolute/path.png [--rear] [--animate=/absolute/folder]
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass

func _ready() -> void:
	_run.call_deferred()

func _make(pop: BearPopulation, point: Vector2, look: int, id: String) -> WildBear:
	var bear: WildBear = load("res://src/entities/wildlife/wild_bear.tscn").instantiate() as WildBear
	bear.name = id
	bear.position = point
	bear.home = point
	bear.appearance = look
	bear.family_id = "preview_family"
	pop._residents.add_child(bear)
	bear.set_physics_process(false)
	bear.facing = PI * 0.25
	bear._visual_facing = bear.facing
	return bear

func _run() -> void:
	var capture: String = ""
	var animate: String = ""
	var rear: bool = OS.get_cmdline_user_args().has("--rear")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		if arg.begins_with("--animate="):
			animate = arg.trim_prefix("--animate=")
	TimeManager.time_of_day = 0.57
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	player.position = world._spawn_position(0)
	world.get_node("Players").add_child(player)
	player.set_physics_process(false)
	(player.get_node("Camera2D") as Camera2D).enabled = false
	var pop: BearPopulation = world.get_node("Wildlife/Bears") as BearPopulation
	for frame: int in 20:
		await get_tree().physics_frame
	pop.set_process(false)
	TimeManager.time_of_day = 0.55
	var center: Vector2 = player.position
	var best: float = -INF
	# Prefer a broad clear meadow within the loaded world for this family portrait.
	for dx: int in range(-320, 321, 24):
		for dy: int in range(-240, 241, 24):
			var p: Vector2 = player.position + Vector2(dx, dy)
			var safe: bool = true
			for off: Vector2 in [Vector2.ZERO, Vector2(-52, 15), Vector2(40, 25), Vector2(65, -6), Vector2(-90, 45)]:
				if not pop.home_loaded(p + off) or not bool(pop._habitat.call(p + off, "bear")) or not pop._clear(p + off, 18.0):
					safe = false
					break
			if safe and -p.distance_to(player.position + Vector2(-160, -120)) > best:
				center = p
				best = -p.distance_to(player.position + Vector2(-160, -120))
	if best == -INF:
		push_error("No safe bear showcase patch")
		get_tree().quit(1)
		return
	var camera: Camera2D = Camera2D.new()
	camera.position = center + Vector2(-5, -27)
	camera.zoom = Vector2(1.6, 1.6)
	world.add_child(camera)
	player.position = center + Vector2(-90, 45)
	player.remove_from_group("players")
	var mother: WildBear = _make(pop, center + Vector2(-15, 8), 0, "ShowMother")
	var a: WildBear = _make(pop, center + Vector2(40, 25), 2, "ShowCubA")
	var b: WildBear = _make(pop, center + Vector2(65, -6), 2, "ShowCubB")
	mother._issue(WoodlandMammal.Mood.REAR if rear else WoodlandMammal.Mood.FORAGE, 3.0)
	mother.facing = 0.0
	mother._visual_facing = 0.0
	mother._elapsed = 1.7
	a._issue(WoodlandMammal.Mood.PLAY, 4.0)
	a._elapsed = 0.7
	b._issue(WoodlandMammal.Mood.ALERT, 4.0)
	for frame: int in 8:
		await get_tree().process_frame
	if not animate.is_empty():
		DirAccess.make_dir_recursive_absolute(animate)
		for frame: int in 48:
			var t: float = float(frame) / 12.0
			if frame < 16:
				mother._issue(WoodlandMammal.Mood.FORAGE, 2.0)
				mother._elapsed = t
			elif frame < 40:
				mother._issue(WoodlandMammal.Mood.REAR, 2.0)
				mother._elapsed = float(frame - 16) / 12.0
			else:
				mother._issue(WoodlandMammal.Mood.LOWER, 0.65)
				mother._elapsed = float(frame - 40) / 12.0
			a._elapsed = t
			b._elapsed = t
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(animate.path_join("%03d.png" % frame))
	if not capture.is_empty():
		mother._issue(WoodlandMammal.Mood.REAR if rear else WoodlandMammal.Mood.FORAGE, 3.0)
		mother._elapsed = 1.7
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var error: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("Bear world preview: ", error_string(error))
		get_tree().quit(error)
