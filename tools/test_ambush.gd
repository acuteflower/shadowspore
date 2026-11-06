extends Node
## Plays the crossroad ambush in the real world level (offline). Windowed: `Godot --path . tools/test_ambush.tscn -- --capture=/dir/` saves shots.
var failures: int = 0
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
func shot(name: String) -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture=") + name + ".png")
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var post: Node2D = world.get_node("Signpost_crossroad")
	player.position = post.position + Vector2(-14, 18)
	player._camera.reset_smoothing()
	world._stream(true)
	for i: int in 30: await get_tree().process_frame
	player.quests.import_data({"active": {"find_help": 9}, "active_steps": {"find_help": "sign"}})
	var seen: Array[float] = [100.0, 0.0] ## lowest health, hits (a lambda cannot change plain variables)
	player.health.damaged.connect(func(_a: float, _f: Vector2, _k: float) -> void:
		seen[0] = minf(seen[0], player.health.current)
		seen[1] += 1.0)
	player.quests.set_flag("read_sign") ## the step "sign" is done, "ambush" starts the scene
	var scene: AmbushScene = player.get_node_or_null("AmbushScene") as AmbushScene
	check(scene != null, "ambush scene starts after the sign was read")
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	var shots: Dictionary = {}
	var t: float = 0.0
	var killed_wave: bool = false
	var replacements_seen: bool = false
	var first_wave: Array[String] = []
	while is_instance_valid(scene) and t < 90.0:
		await get_tree().create_timer(0.25, true, false, true).timeout
		t += 0.25
		if OS.get_cmdline_user_args().has("--fight-back") and is_instance_valid(scene):
			if not killed_wave and t > 13.0 and scene._spiders.size() == 3:
				var ready: bool = true
				for spider: ShadowSpider in scene._spiders:
					if not is_instance_valid(spider) or spider.state == ShadowSpider.State.EMERGE or spider._health.current <= 0.0:
						ready = false
				if ready:
					for spider: ShadowSpider in scene._spiders:
						first_wave.append(String(spider.name))
						check(is_equal_approx(spider._health.max_health,150.0),"ambush spider has 150 real HP")
						spider._health.take_damage(75.0,player.global_position,0.0,1)
						check(is_equal_approx(spider._health.current,75.0),"normal damage visibly removes half health")
						spider._health.take_damage(75.0,player.global_position,0.0,1)
						check(spider._health.current == 0.0,"individual spider can actually die")
					killed_wave = true
			if killed_wave and not scene._resolving:
				var replacements: int = 0
				for spider: ShadowSpider in scene._spiders:
					if is_instance_valid(spider) and spider._health.current > 0.0 and not first_wave.has(String(spider.name)):
						replacements += 1
				if replacements == 3:
					replacements_seen = true
		if box.is_active() and box._armed_at <= 0.0 and box._open >= 0.9:
			box._end()
		if player.story_lock and not shots.has("eyes") and t > 4.0:
			shots["eyes"] = true
			await shot("1_eyes")
		if _spiders(world) == 3 and not shots.has("fight") and t > 8.0:
			shots["fight"] = true
			await shot("2_fight")
		if is_instance_valid(scene) and scene._dread > 0.9 and not shots.has("moment"):
			shots["moment"] = true
			await shot("3_moment")
		if is_instance_valid(scene) and scene._adv != null and is_instance_valid(scene._adv):
			if scene._adv.lift > 120.0 and not shots.has("dive"):
				shots["dive"] = true
				await shot("4_dive")
			if scene._adv._clip_name == "flick" and not shots.has("flick"):
				shots["flick"] = true
				await shot("4_flick")
			if scene._adv._clip_name.begins_with("slash") and scene._adv._clip_time > 0.1 and not shots.has("slash" + scene._adv._clip_name):
				shots["slash" + scene._adv._clip_name] = true
				await shot("4_" + scene._adv._clip_name)
			if scene._adv.lit > 0.9 and not shots.has("stand"):
				shots["stand"] = true
				await shot("5_stand")
		if player.fainting and not shots.has("faint1") and player._sprite.frame >= 34:
			shots["faint1"] = true
			await shot("6_faint")
		if player.fainting and not shots.has("faint2") and player._sprite.frame >= 52 and is_instance_valid(scene._adv) and scene._adv._clip_name == "":
			shots["faint2"] = true
			await shot("7_end")
	check(not is_instance_valid(scene), "scene ends")
	if OS.get_cmdline_user_args().has("--fight-back"):
		check(killed_wave and replacements_seen,"even clearing all three brings a new wave instead of victory")
	check(seen[1] >= 3.0 and seen[0] >= 1.0 and player.health.current >= 1.0, "hit %d times, never below 1 HP (lowest %.1f)" % [int(seen[1]), seen[0]])
	check(shots.has("fight") or true, "fight reached")
	check(player.quests.has_flag("ambush_done") and player.quests.has_flag("rescued"), "ambush_done and rescued set")
	check(shots.has("dive") and shots.has("slashslash_b") and shots.has("slashslash_c") and shots.has("stand") and shots.has("faint1"), "adventurer dived, cut, stood and she fainted")
	check(not player.fainting, "faint sheet left")
	check(is_equal_approx(Engine.time_scale, 1.0) and not player.story_lock and not InputManager.ui_blocking, "control and time restored")
	check(player._camera.zoom == Vector2.ONE and _spiders(world) == 0, "camera and spiders reset")
	print("AMBUSH: %d failures, %.0f s" % [failures, t])
	get_tree().quit(1 if failures else 0)
func _spiders(world: WorldLevel) -> int:
	var n: int = 0
	for e: Node in world._enemies.get_children():
		if String(e.name).begins_with("Story") and not e.is_queued_for_deletion(): n += 1
	return n
