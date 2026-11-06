extends Node
## Offline real-world view of the crusher fighting Ellie. -- --capture=/absolute/path.png --moment=windup|slam|rush|sweep|stun [--night]
## (walk: it chases from far away and leaves its footprints) Saves one frame at that moment (zoom 1.6, camera on the fight). No saves, no game socket.
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")

class PreviewWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var capture: String = ""
	var moment: String = "windup"
	var night: bool = OS.get_cmdline_user_args().has("--night")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--moment="):
			moment = arg.trim_prefix("--moment=")
	TimeManager.time_of_day = 0.92 if night else 0.5
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.set_script(PreviewWorld)
	add_child(world)
	var center: Vector2 = world._spawn_position(0)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	var gap: float = {"windup": 34.0, "slam": 34.0, "rush": 90.0, "sweep": 22.0, "stun": 90.0, "walk": 200.0}.get(moment, 34.0)
	player.position = center + Vector2(gap if moment != "sweep" else -gap, 90 if moment == "walk" else 0)
	world.get_node("Players").add_child(player)
	player.set_physics_process(false)
	(player.get_node("Camera2D") as Camera2D).enabled = false
	var camera: Camera2D = Camera2D.new()
	camera.position = center + (Vector2(10, -20) if moment != "walk" else Vector2(70, 80))
	camera.zoom = Vector2(1.8, 1.8)
	world.add_child(camera)
	for frame: int in 3:
		await get_tree().physics_frame
	var start: Vector2 = center + (Vector2(-60, 90) if moment == "walk" else Vector2.ZERO)
	var actor: VoidCrusher = world._spawn_crusher(start)
	if actor == null:
		push_error("No safe crusher preview spawn")
		get_tree().quit(1)
		return
	actor.heading = 0.0
	actor._known = player.position
	actor._target = player
	actor._memory = 8.0
	actor._slam_cd = 0.0
	actor._rush_cd = 0.0
	actor._sweep_cd = 0.0
	actor.get_node("HealthBar").hide()
	match moment:
		"windup", "slam":
			actor._set_state(VoidCrusher.State.SLAM_WINDUP)
		"rush", "stun":
			actor._set_state(VoidCrusher.State.RUSH_WINDUP)
		"sweep":
			actor._set_state(VoidCrusher.State.SWEEP_WINDUP)
		"walk":
			actor._rush_cd = 99.0
			actor._set_state(VoidCrusher.State.CHASE)
	var want: Dictionary = {"windup": [VoidCrusher.State.SLAM_WINDUP, 0.78], "slam": [VoidCrusher.State.SLAM_RECOVER, 0.22], "rush": [VoidCrusher.State.RUSH, 0.16], "sweep": [VoidCrusher.State.SWEEP, 0.09], "stun": [VoidCrusher.State.STUN, 0.4], "walk": [VoidCrusher.State.CHASE, 3.6]}
	for frame: int in 900:
		await get_tree().physics_frame
		if capture.is_empty():
			continue
		var target: Array = want[moment] as Array
		if actor.state == target[0] and actor._state_time >= float(target[1]):
			await RenderingServer.frame_post_draw
			var result: Error = get_viewport().get_texture().get_image().save_png(capture)
			print("Crusher world capture (", moment, "): ", error_string(result))
			get_tree().quit(result)
			return
	if not capture.is_empty():
		push_error("Crusher preview did not reach the moment " + moment)
		get_tree().quit(1)
