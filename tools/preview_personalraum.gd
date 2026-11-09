extends Node
## Ellie's room, offline, no save access (the room is not wired into the story yet): the opening plays first (RoomIntro), then the room is yours.
## Godot --path . tools/preview_personalraum.tscn [-- --night] [-- --free]     --free skips the opening and puts you into the room at once
## Captures (needs a window): -- --shots=0.8,2.6,4.0 --dir=/abs/folder   saves one picture when the opening's clock reaches each time (seconds).
## WASD walk, Shift sprint; walk up to the crow in the window and away again. Esc: pause menu.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	TimeManager.set_process(false)
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	TimeManager.time_of_day = 0.0 if "--night" in args else 0.5
	var player: Player = world._players.get_child(0) as Player
	var room: Interior = (world.get_node("Interiors") as Interiors).interior("personalraum")
	var shots: Array[float] = []
	var dir: String = ""
	for arg: String in args:
		if arg.begins_with("--shots="):
			for part: String in arg.substr(8).split(","):
				shots.append(float(part))
		elif arg.begins_with("--dir="):
			dir = arg.substr(6)
	if "--free" in args:
		var start: Array = room.spec.start as Array
		player.global_position = room.room_to_global(Vector2(float(start[0]), float(start[1])))
		player.request_heal()
		return
	var intro: RoomIntro = RoomIntro.new()
	add_child(intro)
	intro.start(player, room)
	var taken: int = 0
	while is_instance_valid(intro) and taken < shots.size():
		await get_tree().process_frame
		if intro.elapsed() >= shots[taken]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir.path_join("shot_%02d_%.1f.png" % [taken, shots[taken]]))
			taken += 1
	if not shots.is_empty():
		for i: int in 120:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("shot_end.png"))
		get_tree().quit()
