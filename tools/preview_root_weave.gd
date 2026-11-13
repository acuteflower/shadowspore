extends Node
## Look study of the root weave in the trials' test world: captures the sleeping heart, the risen weave after a few touches (with the pulse
## running), the grown legendary weave and a solved one.
## Run: Godot --rendering-driver opengl3 --path . tools/preview_root_weave.tscn -- --dir=/abs/folder [--night]

var _dir: String = ""


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


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	if _dir != "":
		get_viewport().get_texture().get_image().save_png(_dir.path_join(name + ".png"))
		print("captured ", name)


func _run() -> void:
	NetworkManager.host_singleplayer()
	var world: Node2D = (load("res://src/world/trial_level.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	await _wait(0.3)
	if OS.get_cmdline_user_args().has("--night"):
		TimeManager.set_time(0.95)
	else:
		TimeManager.set_time(0.45)
	var puzzles: Puzzles = Puzzles.of(get_tree())
	var player: Player = (world.get("_players") as Node).get_child(0) as Player
	player.intro = null
	var hud: Node = player.get_node_or_null("Hud")
	var leg: RootWeave = puzzles.trial("weave_altes_geflecht") as RootWeave
	var rare: RootWeave = puzzles.trial("weave_geflecht") as RootWeave
	var com: RootWeave = puzzles.trial("weave_keimling") as RootWeave
	player.global_position = rare.global_position + Vector2(-30, 52)
	await _wait(1.0)
	await _shot("weave_1_sleeping")
	rare._ask("start", -1)
	await _wait(0.9)
	await _shot("weave_2_rising")
	await _wait(2.0)
	await _shot("weave_3_risen")
	rare._ask("press", rare.rules.bit_of("A"))
	await _wait(0.12)
	await _shot("weave_4_pulse")
	await _wait(1.5)
	rare._ask("press", rare.rules.bit_of("F"))
	await _wait(3.0)
	player.global_position = rare.global_position + Vector2(60, 40)
	await _wait(0.5)
	await _shot("weave_5_grown")
	player.global_position = leg.global_position + Vector2(0, 40)
	leg._ask("start", -1)
	await _wait(3.0)
	for cid: String in ["B", "E", "A", "D", "F", "G"]:
		leg._ask("press", leg.rules.bit_of(cid))
		await _wait(2.2)
	await _shot("weave_6_legendary")
	player.global_position = com.global_position + Vector2(20, -60)
	com._ask("start", -1)
	await _wait(2.5)
	for cid: Variant in com.rules.solution():
		com._ask("press", com.rules.bit_of(String(cid)))
		await _wait(1.6)
	await _wait(1.0)
	await _shot("weave_7_solved")
	await _wait(3.0)
	await _shot("weave_8_chest")
	get_tree().quit()
