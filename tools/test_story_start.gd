extends Node
var failures: int = 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	check(player.wounded and is_equal_approx(player.health.current, player.health.max_health * 0.1), "fresh spawn uses actual wounded state")
	check(player._wound > 0.9, "blood/pallor visible immediately")
	var hud: Node = player._hud
	for name_string: String in ["Hotbar", "ClockVine", "PurseVine", "BlinkIcon", "HealthBar", "StaminaBar"]:
		check(not (hud.get_node(name_string) as CanvasItem).visible, name_string + " hidden at start")
	check(not (hud.get_node("HealthBar") as CanvasItem).visible and not (hud.get_node("StaminaBar") as CanvasItem).visible, "health and stamina hidden with hotbar")
	world.begin_story()
	player.quests.set_flag("hud_unlocked")
	check((hud.get_node("Hotbar") as CanvasItem).visible, "future unlock hook updates HUD")
	check((hud.get_node("HealthBar") as CanvasItem).visible and (hud.get_node("StaminaBar") as CanvasItem).visible, "unlock shows bars with hotbar")
	(hud.get_node("Hotbar") as CanvasItem).hide()
	await get_tree().process_frame
	check(not (hud.get_node("HealthBar") as CanvasItem).visible and not (hud.get_node("StaminaBar") as CanvasItem).visible, "manual hotbar hiding also hides bars")
	(hud.get_node("Hotbar") as CanvasItem).show()
	await get_tree().process_frame
	check((hud.get_node("HealthBar") as CanvasItem).visible and (hud.get_node("StaminaBar") as CanvasItem).visible, "manual hotbar reveal restores bars")
	var saved: Dictionary = player.quests.export_data()
	player.quests.import_data({})
	check(not (hud.get_node("Hotbar") as CanvasItem).visible, "early quest reload retains hidden HUD")
	player.quests.import_data(saved)
	check((hud.get_node("Hotbar") as CanvasItem).visible, "unlock survives quest save/load")
	player.quests.import_data({})
	player.health.current = player.health.max_health
	player.sync_wound_visuals()
	check(not player.wounded and player._wound == 0, "healthy save state restores healthy visuals")
	player.health.current = player.health.max_health * 0.1
	player.sync_wound_visuals()
	var dialogue: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	dialogue.start("spiders_intro")
	dialogue._end()
	check(not (hud.get_node("Hotbar") as CanvasItem).visible, "closing dialogue does not reveal locked HUD")
	world.start_intro()
	check((hud as CanvasLayer).visible, "HUD layer stays visible for cinematic wound border")
	check((player._sprite.material as ShaderMaterial).get_shader_parameter("blood_map") == Player.EMERGE_BLOOD, "intro uses its own aligned blood sheet")
	check(Player.EMERGE_BLOOD.get_size() == IntroScene.SHEET.get_size(), "intro blood layout matches animation")
	var captured_intro: bool = false
	var deadline: int = Time.get_ticks_msec() + 20000
	while player.intro != null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if player.intro != null and player.intro._time > 3.9 and not captured_intro:
			captured_intro = true
			var border: WoundBorder = hud.get_node("WoundBorder") as WoundBorder
			check(border.is_visible_in_tree() and border._grow > 0.9, "red wound border is already visible while crawling")
			check(not (hud.get_node("HealthBar") as CanvasItem).visible and not (hud.get_node("StaminaBar") as CanvasItem).visible, "no bars during crawl")
			for arg: String in OS.get_cmdline_user_args():
				if arg.begins_with("--capture="):
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture=").get_basename() + "-crawl.png")
	check(player.intro == null and player.wounded, "full intro ends with injured player")
	check((hud as CanvasLayer).visible and not (hud.get_node("ClockVine") as CanvasItem).visible, "intro reveal preserves reduced HUD")
	var centre: Vector2 = Vector2(world._start) * 16 + Vector2(8,8)
	var gate: Vector2 = centre + Vector2(100,784)
	for guard: Dictionary in DataRegistry.table("ground").get("guards", []):
		var at: Vector2 = centre + Vector2(float(guard.at[0]), float(guard.at[1]))
		check(world._relief.flat_around(at, 13), "guard on flat traversable terrain")
		check(at.distance_to(gate) > 96 and at.distance_to(gate) < 106, "guard lane preserves sneaking clearance")
	var approach: Dictionary = (DataRegistry.get_entry("quests", "find_help").steps as Array)[1]
	var trigger: Vector2 = Vector2(float(approach.tile[0]), float(approach.tile[1])) * 16 + Vector2(8,8)
	for guard: Dictionary in DataRegistry.table("ground").get("guards", []):
		var at: Vector2 = centre + Vector2(float(guard.at[0]), float(guard.at[1]))
		check(at.distance_to(trigger) > 125, "dialogue starts before guard detection")
	check(TimeManager.locked and is_zero_approx(TimeManager.time_of_day) and TimeManager.day == 0, "opening: day 1, 00:00, clock locked")
	var t0: float = TimeManager.time_of_day
	await get_tree().create_timer(0.3).timeout
	check(is_equal_approx(TimeManager.time_of_day, t0), "locked clock does not advance")
	player.health.current = 0.0
	player._respawn_after_delay()
	await get_tree().create_timer(0.4).timeout
	check(player.health.current <= 0.0, "a fallen player waits for the death screen's choice")
	player.request_respawn()
	await get_tree().create_timer(0.8).timeout
	check(player.wounded and is_equal_approx(player.health.current, player.health.max_health * 0.1), "death in the opening respawns wounded")
	world.finish_opening()
	check(not TimeManager.locked, "finishing the opening releases the clock")
	# Render near the new guard lane, without progressing quests or writing saves.
	player.quests.set_physics_process(false)
	player.position = gate - Vector2(115,95)
	player._camera.reset_smoothing()
	world._stream(true)
	for frame: int in 90: await get_tree().process_frame
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	print("STORY START: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
