extends Node
## Captures Ellie pulling a root out of the ground in the real world: `-- --dir=/abs/folder [--kind=ember_carrot|night_beet] [--at=x,y tile]`.
## One png every 0.1 s of the one-second action. Offline, no save access; needs a window (use --rendering-driver opengl3).
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var dir: String = ""
	var kind: String = "ember_carrot"
	var tile: Vector2 = Vector2(520, 600)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=")
		if arg.begins_with("--kind="): kind = arg.trim_prefix("--kind=")
		if arg.begins_with("--at="):
			var parts: PackedStringArray = arg.trim_prefix("--at=").split(",")
			tile = Vector2(float(parts[0]), float(parts[1]))
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	add_child(world)
	var at: Vector2 = tile * 16.0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var c: Vector2i = Vector2i((at / 512.0).floor()) + Vector2i(dx, dy)
			if not world._chunks.has(c): world._load_chunk(c)
	var player: Player = world._players.get_child(0) as Player
	player.request_teleport(at)
	TimeManager.unlock()
	TimeManager.time_of_day = 0.5
	for i: int in 120: await get_tree().process_frame
	var cell: Vector2i = Vector2i(((player.global_position + Vector2(22, 0)) / 16.0).floor())
	var thing: WorldProp = world._spawn_thing(cell, kind, 1)
	thing.global_position = player.global_position + Vector2(22, 0)
	for i: int in 10: await get_tree().process_frame
	thing.interact(player)
	for step: int in 12:
		await get_tree().create_timer(0.1).timeout
		await RenderingServer.frame_post_draw
		if not dir.is_empty():
			get_viewport().get_texture().get_image().save_png("%s/pull_%02d.png" % [dir, step])
	print("pull capture done, state ", thing.state)
	get_tree().quit()
