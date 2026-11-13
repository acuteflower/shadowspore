extends Node
## Every trial placed in the real world (data/puzzles.json `placed`, spread by tools/place_trials.py) in the streamed world: its key points lie on
## dry land of one level, the places one has to reach (a crow's mound, the raven's stations, the wisp's end) are free of solid things, and the
## Hexenwald holds only crow trials and one root weave. With `-- --dir=/abs` a picture of every trial is saved (windowed run).
## Run: Godot --headless --path . tools/test_trials_world.tscn   (prints TRIALS WORLD OK)

var _ok: bool = true
var _dir: String = ""


func check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TRIALS WORLD FAILED: ", what)


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.get_slice("=", 1)
	_run.call_deferred()


func _wait(sec: float) -> void:
	var t: float = 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()


func _tile(t: Variant) -> Vector2:
	var a: Array = t as Array
	return Vector2(float(a[0]), float(a[1])) * 16.0 + Vector2(8, 8)


func _run() -> void:
	if _dir != "":
		NetworkManager.host_singleplayer()
	var world: WorldLevel = (load("res://src/world/world_level.tscn") as PackedScene).instantiate() as WorldLevel
	add_child(world)
	await _wait(0.5)
	TimeManager.set_time(0.45)
	var player: Player = world._players.get_child(0) as Player
	player.intro = null
	player.story_lock = false
	player.health.floor_value = 1.0
	var table: Dictionary = DataRegistry.table("puzzles")
	var hexen: Array = []
	for entry: Dictionary in table.get("placed", []) as Array:
		var id: String = String(entry["id"])
		var kind: String = String(entry["kind"])
		var home: Vector2 = _tile(entry["tile"])
		if String(entry.get("area", "")) == "Hexenwald":
			hexen.append(kind)
		player.global_position = home + Vector2(0, 60)
		player.velocity = Vector2.ZERO
		await _wait(2.5)
		var level: int = world.town_level_at(home)
		var reach: Array = []
		for key: String in ["mound"]:
			if entry.has(key):
				reach.append(_tile(entry[key]))
		for p: Variant in entry.get("stations", []) as Array:
			reach.append(_tile(p))
		var route: Array = entry.get("route", []) as Array
		for k: int in range(1, route.size()): ## route[0] is the wisp's own bowl
			reach.append(_tile(route[k]))
		for p: Vector2 in [home] + reach:
			check(world.water_depth(p) < 0.0, "%s: %s is dry" % [id, p / 16.0])
			check(world.town_level_at(p) == level, "%s: %s lies on the trial's level" % [id, p / 16.0])
		for p: Vector2 in reach:
			if p.distance_to(player.global_position) < 700.0:
				var said: String = world.town_probe(Rect2(p - Vector2(6, 6), Vector2(12, 12)))
				check(said == "" or said == "ZU NAH AM WASSER", "%s: %s can be reached (%s)" % [id, p / 16.0, said])
		if kind == "root_weave" or kind == "star_mirror":
			var said2: String = world.town_probe(Rect2(home + Vector2(-60, 40), Vector2(16, 16)))
			check(said2 != "KEIN LAND" and said2 != "ZU UNEBEN", "%s: the ground round it is flat land (%s)" % [id, said2])
		if _dir != "":
			player.global_position = home + Vector2(0, 70)
			await _wait(1.5)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(_dir.path_join(id + ".png"))
		print("checked ", id)
	for k: Variant in hexen:
		check(String(k) in ["crow_hoard", "raven_trade", "root_weave"], "the Hexenwald holds only crow trials and a weave (found %s)" % k)
	check(hexen.count("root_weave") == 1, "exactly one root weave in the Hexenwald")
	print("TRIALS WORLD OK" if _ok else "TRIALS WORLD FAILED")
	get_tree().quit(0 if _ok else 1)
