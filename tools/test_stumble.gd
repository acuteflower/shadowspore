extends Node
## Walks the wounded Ellie across the three stumble spots (offline, real world level) and checks that she trips once at each and gets up.
var failures: int = 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var spots: Array = DataRegistry.table("ground").get("stumbles", []) as Array
	check(spots.size() == 3 and player.wounded, "three stumble spots, she is wounded")
	var shot_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			shot_dir = arg.trim_prefix("--capture=")
	for i: int in spots.size():
		var tile: Array = (spots[i] as Dictionary).tile as Array
		var at: Vector2 = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
		player.position = at + Vector2(0, -56)
		player._camera.reset_smoothing()
		var tripped: bool = false
		var got_up: bool = false
		var waited: float = 0.0
		var rose: bool = false
		for f: int in 900:
			if not player.stumbling and not tripped:
				player.position += Vector2(0, 1.2) ## walks through the place
				player.velocity = Vector2(0, 40)
			await get_tree().physics_frame
			if player.stumbling:
				tripped = true
				if player._stumble_phase == 1:
					waited += get_physics_process_delta_time()
					if waited > 1.5 and shot_dir != "" and not FileAccess.file_exists(shot_dir + "stumble_%d.png" % i):
						await RenderingServer.frame_post_draw
						get_viewport().get_texture().get_image().save_png(shot_dir + "stumble_%d.png" % i)
					if waited > 2.0 and not rose:
						rose = true
						check(player._stumble_prompt != null, "stumble %d: the prompt hangs over her" % i)
						player._stumble_rise.rpc() ## E
			elif tripped:
				got_up = true
				break
		check(tripped and got_up and rose, "stumble %d: she trips, stays down until E, and gets up" % i)
		check(tripped and got_up, "stumble %d: she trips and gets up" % i)
		check(player.quests.has_flag("stumble_%d" % i), "stumble %d is remembered" % i)
	# once only: walking back over the first spot does nothing
	var tile0: Array = (spots[0] as Dictionary).tile as Array
	player.position = Vector2(float(tile0[0]), float(tile0[1])) * 16.0 + Vector2(8, 8)
	player.velocity = Vector2(0, 40)
	for f: int in 60: await get_tree().physics_frame
	check(not player.stumbling, "no second stumble at the same place")
	print("STUMBLE: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
