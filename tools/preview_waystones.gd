extends Node
## Looks at every waystone site of the world: puts a player beside each statue (dormant, or `-- --awake` awakened), waits for the world to stream in and saves a picture.
## `Godot --rendering-driver opengl3 --path . tools/preview_waystones.tscn -- --capture=/abs/dir [--awake]`; prints per statue the relief level, the flat surroundings and the ground.
var _dir: String = ""
var _awake: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_dir = arg.trim_prefix("--capture=")
		elif arg == "--awake":
			_awake = true
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.health.heal_full()
	player.quests.set_flag("waystone_seen")
	var manager: Waystones = Waystones.of(get_tree())
	if _awake:
		manager.import_state({"awake": manager.specs().keys()})
	for id: String in manager.specs():
		var statue: WaystoneStatue = manager.statue_node(id)
		player.request_teleport(statue.global_position + Vector2(0, 70))
		await get_tree().create_timer(3.0).timeout
		var relief: Relief = world._relief
		print("%s tile %s level %.2f flat %s" % [id, str((manager.specs()[id] as Dictionary).tile), relief.level_at(statue.global_position), str(relief.flat_around(statue.global_position, 40.0))])
		if _dir != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, id])
	get_tree().quit(0)
