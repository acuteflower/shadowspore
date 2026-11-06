extends Node
## Offline actual forest combat view. -- --capture=/absolute/path.png [--close]
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var capture: String = ""
	var close: bool = OS.get_cmdline_user_args().has("--close")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	TimeManager.time_of_day = 0.78
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	var center: Vector2 = world._spawn_position(0)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	player.position = center + Vector2(0 if close else 70, 0)
	world.get_node("Players").add_child(player)
	player.set_physics_process(false)
	(player.get_node("Camera2D") as Camera2D).enabled = false
	var camera: Camera2D = Camera2D.new()
	camera.position = center + Vector2(0, -20)
	camera.zoom = Vector2(1.6, 1.6)
	world.add_child(camera)
	for frame: int in 3:
		await get_tree().physics_frame
	var actor: VoidListener = world._spawn_listener(center + Vector2(-36 if close else -80, 0))
	if actor == null:
		push_error("No safe listener preview spawn")
		get_tree().quit(1)
		return
	actor.heading = 0.0
	actor._known = player.position
	actor._target = player
	actor._memory = 8.0
	actor._wave_cd = 0.0
	actor._set_state(VoidListener.State.HUNT)
	for frame: int in 600:
		await get_tree().physics_frame
		if capture.is_empty():
			continue
		var moment: bool = close and actor.state == VoidListener.State.SCREAM and actor._state_time >= 0.15
		if not close:
			for node: Node in world.get_node("EnemyProjectiles").get_children():
				var wave: ResonanceWave = node as ResonanceWave
				moment = moment or (wave != null and wave.travelled >= 54.0 and not wave.stopped)
		if moment:
			await RenderingServer.frame_post_draw
			var result: Error = get_viewport().get_texture().get_image().save_png(capture)
			print("Listener forest capture: ", error_string(result))
			get_tree().quit(result)
			return
	if not capture.is_empty():
		push_error("Listener preview did not reach attack moment")
		get_tree().quit(1)
