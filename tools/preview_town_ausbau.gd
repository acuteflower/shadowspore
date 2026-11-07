extends Node
## Real pictures of the town additions (docs/town_ausbau.md): the checkpoint town in the real world.
##   Godot --rendering-driver opengl3 --path . tools/preview_town_ausbau.tscn -- --capture=/abs/prefix [--time=0.95] [--at=x,y] [--alert] [--cold] [--age=9] [--level=3]
## writes <prefix>.png. `--at` is an offset in px from the middle of the town, `--cold` puts the lamps out, `--age` backdates the hut's renewal in days, `--level` fakes the town level's look.


func _frames(n: int) -> void:
	for i: int in n:
		get_tree().paused = false
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var prefix: String = ""
	var time: float = 0.5
	var offset: Vector2 = Vector2(0, 70)
	var alert: bool = false
	var cold: bool = false
	var age: int = 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): prefix = arg.substr(10)
		elif arg.begins_with("--time="): time = float(arg.substr(7))
		elif arg.begins_with("--at="): offset = Vector2(float(arg.substr(5).split(",")[0]), float(arg.substr(5).split(",")[1]))
		elif arg == "--alert": alert = true
		elif arg == "--cold": cold = true
		elif arg.begins_with("--age="): age = int(arg.substr(6))
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(3)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	await _frames(60)
	world.debug_jump_town()
	await _frames(150)
	if age > 0:
		for id: int in town.structures:
			(town.structures[id] as Dictionary).b = TimeManager.day - age
		town._wear_dirty = true
	if cold:
		for id: int in town.built_ids("lamp_post"):
			town._rpc_lamp.rpc(id, 0, 0, false)
	TimeManager.time_of_day = time
	player.request_teleport(town.center + offset)
	await _frames(200)
	if alert: ## (the night director clears an alarm when a night begins, so it is raised after that)
		town.set_alert(true, 0.6)
		await _frames(400)
	print("PREVIEW alert_on=", town.alert_on, " lit=", town.lit_circles().size())
	for k: int in 3:
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(prefix + (".png" if k == 0 else "_%d.png" % k))
		await _frames(37)
	get_tree().quit()
