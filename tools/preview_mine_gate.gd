extends Node
## The mine's gate on the surface and the title of a level. `-- --capture=/abs/file.png [--night] [--banner]` saves a screenshot and quits (the second one is taken
## in level 1 right after the arrival); without --capture you can just walk there (offline, no save access).

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var capture: String = ""
	var night: bool = false
	var banner: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture = arg.get_slice("=", 1)
		elif arg == "--night": night = true
		elif arg == "--banner": banner = true
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var mines: MineManager = world.get_node("Mines") as MineManager
	var player: Player = world._players.get_child(0) as Player
	if night:
		TimeManager.set_time(0.97)
	player.request_teleport(mines.entrance + Vector2(0, 40))
	for i: int in 120:
		await get_tree().process_frame
	if banner:
		mines.travel(player, 1, "entry")
		await get_tree().create_timer(2.6).timeout
	if capture != "":
		get_viewport().get_texture().get_image().save_png(capture)
		print("saved ", capture)
		get_tree().quit()
