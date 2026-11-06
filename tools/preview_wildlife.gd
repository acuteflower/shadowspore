extends Node
## Live meadow workbench with normal WASD controls, no ENet socket or save access.
## Godot --path . tools/preview_wildlife.tscn [-- --capture=/absolute/path.png]

class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var capture: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	TimeManager.time_of_day = 0.5
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	var center: Vector2 = world._spawn_position(0) + Vector2(0, -148)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = center + Vector2(0, 50)
	world.get_node("Players").add_child(player)
	var positions: Array[Vector2] = [Vector2(-138, -18), Vector2(-72, -60), Vector2(-30, 0), Vector2(40, -38), Vector2(70, 12), Vector2(-185, -52)]
	for i: int in 6:
		var rabbit: WildRabbit = load("res://src/entities/wildlife/wild_rabbit.tscn").instantiate() as WildRabbit
		rabbit.name = "PreviewRabbit%d" % i
		rabbit.appearance = i
		rabbit.position = center + positions[i]
		rabbit.home = rabbit.position
		rabbit.facing = [0.0, PI * 0.25, PI * 0.75, PI, PI * 0.5, -PI * 0.25][i]
		world.get_node("Wildlife/Animals").add_child(rabbit)
		rabbit._set_state(WildRabbit.State.GRAZE if i % 2 == 0 else WildRabbit.State.REST, 3.0 + i * 0.3)
	if not capture.is_empty():
		for frame: int in 12:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var error: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("Rabbit meadow capture: ", error_string(error))
		get_tree().quit(error)
