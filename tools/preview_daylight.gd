extends Node
## Day/night mood captures of the real world. `-- --dir=/abs/folder [--times=0.0,0.27,0.5,0.757] [--at=x,y tile] [--zoom=1]`
## --phase=12 locks the day clock and daylight field phase for look comparisons.
## Saves one png per time of day (0..1, 0.5 = noon). Offline, no save access.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void: pass
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var dir: String = ""
	var times: PackedStringArray = "0.0,0.27,0.5,0.757".split(",")
	var tile: Vector2 = Vector2.ZERO
	var zoom: float = 1.0
	var phase: float = -1.0
	var day: int = 0
	var with_town: bool = false
	var with_player: bool = false
	var with_watchers: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=")
		if arg.begins_with("--times="): times = arg.trim_prefix("--times=").split(",")
		if arg.begins_with("--at="):
			var parts: PackedStringArray = arg.trim_prefix("--at=").split(",")
			tile = Vector2(float(parts[0]), float(parts[1]))
		if arg.begins_with("--phase="): phase = float(arg.trim_prefix("--phase="))
		if arg.begins_with("--zoom="): zoom = float(arg.trim_prefix("--zoom="))
		if arg == "--player": with_player = true ## the real heroine (her camera, her aura of moonlight); the world keeps running
		if arg == "--watchers": with_watchers = true ## open the bush eyes at once (NightWatchers.fill_now)
		if arg == "--town": with_town = true ## a founded town with its house at the start: shows how the light pushes fog back
		if arg.begins_with("--day="): day = int(arg.trim_prefix("--day=")) ## the moon has phases: day % 8 (0 new, 4 full)
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	if not with_player:
		world.set_script(EmptyWorld)
	add_child(world)
	if not with_player:
		world.set_process(false)
	var at: Vector2 = world._spawn_position(0) if tile == Vector2.ZERO else tile * 16.0
	var cell: Vector2i = Vector2i((at / 512.0).floor())
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var c: Vector2i = cell + Vector2i(dx, dy)
			if not world._chunks.has(c): world._load_chunk(c)
	if with_player:
		var hero: Player = world._players.get_child(0) as Player
		hero.request_teleport(at)
		if phase >= 0.0: ## isolated look QA, never saves or changes ordinary play
			hero.get_node("OpeningGuide").set_process(false)
			hero.quests.set_physics_process(false)
			hero.health.current = hero.health.max_health
			hero.health.floor_value = hero.health.max_health
			hero.sync_wound_visuals()
	else:
		var camera: Camera2D = Camera2D.new()
		camera.position = at
		camera.zoom = Vector2(zoom, zoom)
		world.add_child(camera)
	if with_town:
		var hut: Hut = world.hut_node()
		world.town().import_state({"version": 1, "founded": true, "name": 0, "center": [hut.position.x, hut.position.y], "day": 1, "next_id": 1,
			"structures": {"0": {"p": "house", "x": hut.position.x, "y": hut.position.y, "f": 0, "g": 1000}}, "stock": {}, "cleared": [], "residents": {}})
	TimeManager.unlock()
	if phase >= 0.0: TimeManager.locked = true
	TimeManager.day = day
	for t: String in times:
		TimeManager.time_of_day = float(t)
		for i: int in (150 if with_player else 40):
			if phase >= 0.0 and is_instance_valid(DaylightField.current): DaylightField.current.clock = phase
			await get_tree().process_frame
		if with_watchers:
			for _k: int in 20: await get_tree().process_frame
			for node: Node in get_tree().get_nodes_in_group("night_watchers"): node.call("fill_now")
			for _k: int in 100: await get_tree().process_frame
		if is_instance_valid(DaylightField.current): print("canopy rebuild us: ", DaylightField.current.rebuild_usec)
		if dir.is_empty(): continue
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/t%s.png" % [dir, t])
	print("daylight capture done at ", at)
	get_tree().quit()
