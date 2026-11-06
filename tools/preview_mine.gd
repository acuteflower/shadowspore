extends Node
## Looks at the mine in the real world level (docs/mine.md). `-- --level=N [--at=tx,ty] [--room=type] --capture=/abs/file.png [--frames=N] [--zoom=Z]` saves a screenshot and quits;
## without --capture you just play there (offline, no save access). --room=<type> puts the camera in the first room of that type.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: int = 1
	var capture: String = ""
	var at: Vector2i = Vector2i(-1, -1)
	var room_type: String = ""
	var frames: int = 40
	var lamp: bool = false
	var rooms_list: PackedStringArray = PackedStringArray()
	var zoom: float = 1.0
	var time_arg: float = -1.0
	var curve: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): level = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--capture="): capture = arg.get_slice("=", 1)
		elif arg.begins_with("--room="): room_type = arg.get_slice("=", 1)
		elif arg.begins_with("--rooms="): rooms_list = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--frames="): frames = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--zoom="): zoom = arg.get_slice("=", 1).to_float()
		elif arg == "--lamp": lamp = true
		elif arg == "--curve": curve = true
		elif arg.begins_with("--time="): time_arg = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--at="): at = Vector2i(arg.get_slice("=", 1).get_slice(",", 0).to_int(), arg.get_slice("=", 1).get_slice(",", 1).to_int())
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var mines: MineManager = world.get_node("Mines") as MineManager
	var player: Player = world._players.get_child(0) as Player
	mines.enter(player, level)
	if time_arg >= 0.0:
		TimeManager.set_time(time_arg)
	var l: MineLayout = mines.layout(level)
	if room_type != "":
		for room: Dictionary in l.rooms:
			if String(room.type) == room_type:
				at = room.center as Vector2i
				break
	if curve: ## the first quarter turn of a rail
		for c: Vector2i in l.chunk_rails:
			for r: Vector3i in l.chunk_rails[c] as Array:
				if r.z >= 2 and at.x < 0:
					at = Vector2i(r.x, r.y)
	if lamp: ## the lamp nearest to the entry
		var best: float = 1e30
		for c: Vector2i in l.chunk_lights:
			for light: Dictionary in l.chunk_lights[c] as Array:
				var p: Vector2 = Vector2(float(light.x), float(light.y))
				var d: float = p.distance_to(l.tile_center(l.entry))
				if d < best and d > 90.0:
					best = d
					at = Vector2i(int(p.x / 16.0), int(p.y / 16.0) + 1)
	if at.x >= 0:
		player.request_teleport(MineManager.origin(level) + l.tile_center(at))
	var camera: Camera2D = player.get("_camera") as Camera2D
	camera.zoom = Vector2.ONE * zoom
	if not rooms_list.is_empty(): ## one shot per room type: <capture>_<type>.png
		for type: String in rooms_list:
			for room: Dictionary in l.rooms:
				if String(room.type) == type:
					player.request_teleport(MineManager.origin(level) + l.tile_center((room.center as Vector2i) + (Vector2i(0, 2) if type == "rest" else Vector2i.ZERO)))
					for i: int in frames:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(capture.replace(".png", "_%s.png" % type))
					print("saved ", type)
					break
		get_tree().quit()
		return
	for i: int in frames:
		await get_tree().process_frame
	if capture != "":
		get_viewport().get_texture().get_image().save_png(capture)
		print("saved ", capture)
		get_tree().quit()
