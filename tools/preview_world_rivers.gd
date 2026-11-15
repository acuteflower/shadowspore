extends Node
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var capture: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture = arg.trim_prefix("--capture=")
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	world.set_process(false)
	var data: Dictionary = DataRegistry.table("rivers_baked")
	var incoming: Dictionary = {}
	for edge: Dictionary in data["edges"]:
		var key: String = str(edge["b"])
		incoming[key] = int(incoming.get(key, 0)) + 1
	var at: Vector2
	var nearest: float = INF
	for edge: Dictionary in data["edges"]:
		if int(incoming.get(str(edge["b"]), 0)) < 2: continue
		var p: Vector2 = Vector2(float(edge["b"][0]), float(edge["b"][1]))
		if p.distance_to(world._spawn_position(0)) < nearest:
			nearest = p.distance_to(world._spawn_position(0))
			at = p
	# --spot=N shows the N-th stretch of the drainage instead of the confluence nearest the start.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lake="):
			var lakes: Array = DataRegistry.table("lakes_baked")["lakes"]
			var lake: Dictionary = lakes[int(arg.trim_prefix("--lake=")) % lakes.size()]
			var point: Array = lake["deep"] if Array(Array(OS.get_cmdline_user_args())).any(func(x: String) -> bool: return x.begins_with("--swim=")) else lake.get("shore", lake["deep"])
			at = Vector2(float(point[0]), float(point[1]))
		if arg.begins_with("--spot="):
			var segments: Array = data["segments"]
			at = Vector2(float((segments[int(arg.trim_prefix("--spot=")) * 97 % segments.size()] as Dictionary)["a"][0]), float((segments[int(arg.trim_prefix("--spot=")) * 97 % segments.size()] as Dictionary)["a"][1]))
	var cell: Vector2i = Vector2i((at / 512.0).floor())
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var c: Vector2i = cell + Vector2i(dx, dy)
			if not world._chunks.has(c): world._load_chunk(c)
	var camera: Camera2D = Camera2D.new()
	camera.position = at
	world.add_child(camera)
	# Put a real player at a shallow ford for the optional wading showcase.
	if OS.get_cmdline_user_args().has("--wade"):
		var nearest_ford: Vector2 = at
		var gap: float = INF
		for ford: Array in data["fords"]:
			var point: Vector2 = Vector2(float(ford[0]), float(ford[1]))
			if point.distance_to(at) < gap:
				gap = point.distance_to(at)
				nearest_ford = point
		var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
		player.name = "2"
		player.position = nearest_ford
		world.get_node("Players").add_child(player)
		player.set_physics_process(false)
		(player.get_node("Camera2D") as Camera2D).enabled = false
		player._surface = world._rivers.wade_data(nearest_ford, Terrain.surface_data("shallow_water"))
		player._update_water(0.4)
		player._water._process(0.4)
		player._ripples.add(nearest_ford, 1.2)
		player._ripples._process(0.25)
		camera.position = nearest_ford + Vector2(0, -12)
		camera.zoom = Vector2(1.6, 1.6)
	# --swim=N (1 tread, 2 breast, 3 crawl) with --lake=K puts a real swimmer in the lake; --facing=sector, --night.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--swim="):
			var state: int = int(arg.trim_prefix("--swim="))
			var swimmer: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
			swimmer.name = "2"
			swimmer.position = at
			world.get_node("Players").add_child(swimmer)
			swimmer.set_physics_process(false)
			(swimmer.get_node("Camera2D") as Camera2D).enabled = false
			swimmer.swim = state
			swimmer.swimmer.blend = 1.0
			swimmer.swimmer.active = true
			swimmer.facing = Vector2.RIGHT
			for other: String in OS.get_cmdline_user_args():
				if other.begins_with("--facing="):
					swimmer.facing = Vector2.RIGHT.rotated(float(int(other.trim_prefix("--facing="))) * PI / 4.0)
			swimmer.velocity = swimmer.facing * (0.0 if state == 1 else 40.0)
			for i: int in 48:
				swimmer._animate(0.05)
				swimmer._update_water(0.05)
				if swimmer._ripples != null:
					swimmer._ripples._process(0.05)
				if swimmer._swim_water != null:
					swimmer._swim_water._process(0.05)
			camera.position = at + Vector2(0, -12)
			camera.zoom = Vector2(4.0, 4.0)
	# --mirror (with --lake=K): Ellie stands on the lake's north shore, looking at her mirror image (docs/wasserspiegelung.md).
	if OS.get_cmdline_user_args().has("--mirror"):
		var shore: Vector2 = at
		while world._rivers.field_at(shore).x <= 0.0 and shore.y > at.y - 2000.0:
			shore.y -= 4.0
		shore.y -= 3.0
		var mirror_player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
		mirror_player.name = "2"
		mirror_player.position = shore
		world.get_node("Players").add_child(mirror_player)
		mirror_player.set_physics_process(false)
		(mirror_player.get_node("Camera2D") as Camera2D).enabled = false
		mirror_player.facing = Vector2.DOWN
		for i: int in 12:
			mirror_player._animate(0.05)
		camera.position = shore + Vector2(0, 18)
		camera.zoom = Vector2(2.4, 2.4)
	TimeManager.unlock()
	TimeManager.time_of_day = 0.0 if OS.get_cmdline_user_args().has("--night") else 0.55
	# --time=T (0..1), --day=N (moon phase = N mod 8, 4 full), --sky (with --lake=K: the lake's deep water where the moon's reflection lies), --zoom=Z
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--time="): TimeManager.time_of_day = float(arg.trim_prefix("--time="))
		if arg.begins_with("--day="): TimeManager.day = int(arg.trim_prefix("--day="))
		if arg.begins_with("--zoom="): camera.zoom = Vector2.ONE * float(arg.trim_prefix("--zoom="))
	if OS.get_cmdline_user_args().has("--sky"):
		var run: float = clampf(fposmod(TimeManager.time_of_day - 0.78, 1.0) / 0.462, 0.0, 1.0)
		var view: Vector2 = Vector2(640, 360) / camera.zoom
		var moon_at: Vector2 = view * Vector2(lerpf(0.86, 0.14, run), 0.34 - 0.16 * sin(PI * run))
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--lake="):
				var lakes: Array = DataRegistry.table("lakes_baked")["lakes"]
				var deep: Array = (lakes[int(arg.trim_prefix("--lake=")) % lakes.size()] as Dictionary)["deep"]
				camera.position = Vector2(float(deep[0]), float(deep[1])) - moon_at + view * 0.5 + Vector2(0, -20)
		var view_cell: Vector2i = Vector2i((camera.position / 512.0).floor())
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				if not world._chunks.has(view_cell + Vector2i(dx, dy)): world._load_chunk(view_cell + Vector2i(dx, dy))
	for i: int in 8: await get_tree().process_frame
	for arg: String in OS.get_cmdline_user_args(): ## --weather=ID holds a weather state (clear, rain, storm ...)
		if arg.begins_with("--weather=") and WeatherManager.current != null:
			WeatherManager.current.force(arg.trim_prefix("--weather="))
			for i: int in 150: await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--mirror"):
		for i: int in 8: await get_tree().process_frame ## the mirror chooses what to show a few times a second
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture)
		print("World river capture: ", at)
		if WaterReflections.current != null: print("mirror: ", WaterReflections.current.drawn_items, " copies, ", WaterReflections.current.cost_usec, " usec")
		get_tree().quit()
