extends Node
## Verifies that during an active boss fight all peripheral HUDs (ClockVine, PurseVine, QuestVine,
## HintCard, FishingHud, MultiplayerHud) automatically fade out while BossBar and the Hotbar combat strip stay visible,
## and cleanly restore once the boss dies or releases.
## Optional: `-- --capture=/abs/folder` saves before_boss.png, during_boss.png, after_boss.png.

var _fails: int = 0
var _capture_dir: String = ""


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL [test_boss_hud_hide]: ", msg)


func _ready() -> void:
	_run.call_deferred()


func _step_seconds(secs: float) -> void:
	var steps: int = ceili(secs * 60.0)
	for _i: int in steps:
		await get_tree().process_frame


func _part_alpha(hud: CanvasLayer, part: String) -> float:
	var node: CanvasItem = hud.get_node_or_null(part) as CanvasItem
	if node == null:
		return -1.0
	return node.modulate.a


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")

	GameSettings.set_value("player_name", "ELLIE")
	NetworkManager.host_multiplayer(17968, "B0SS99", 4, "boss_hud_test", "TEST-WELT", "")

	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.loading_in_steps = true
	add_child(world)
	while not world.loading_init_step():
		await get_tree().process_frame

	var deadline: int = Time.get_ticks_msec() + 15000
	var player: Player = null
	while Time.get_ticks_msec() < deadline:
		player = world.get_node_or_null("Players/1") as Player
		if player != null:
			break
		await get_tree().process_frame
	_check(player != null, "player spawned")
	if player == null:
		NetworkManager.leave()
		get_tree().quit(1)
		return

	var guide: Node = player.get_node_or_null("OpeningGuide")
	if guide != null:
		guide.set_process(false)
	var stumbles: Node = player.get_node_or_null("StumbleGuide")
	if stumbles != null:
		stumbles.set_process(false)
	if world.has_method("finish_opening"):
		world.call("finish_opening")
	if player.quests != null:
		player.quests.set_flag("hud_unlocked", true)
	if player.progress != null:
		player.progress.copper = 1245
		player.progress.changed.emit()

	TimeManager.unlock()
	TimeManager.time_of_day = 0.52
	await _step_seconds(1.2)

	var hud: CanvasLayer = player.get("_hud") as CanvasLayer
	_check(hud != null, "player has HUD")
	if hud == null:
		NetworkManager.leave()
		get_tree().quit(1)
		return
	var boss_bar: BossBar = hud.get_node_or_null("BossBar") as BossBar
	_check(boss_bar != null, "HUD has BossBar")

	# 1. Baseline: peripheral HUDs & Hotbar visible
	for part: String in ["ClockVine", "PurseVine", "QuestVine", "MultiplayerHud", "Hotbar", "HealthBar", "StaminaBar"]:
		_check(_part_alpha(hud, part) > 0.95, "before boss: %s visible (%.2f)" % [part, _part_alpha(hud, part)])

	if not _capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/before_boss.png" % _capture_dir)

	# 2. Start boss fight -> BossBar.track()
	var hc := HealthComponent.new()
	hc.max_health = 600.0
	hc.current = 600.0
	add_child(hc)
	get_tree().call_group("boss_bar", "track", "MORNATH", hc)
	await _step_seconds(0.65)
	hc.take_damage(180.0, Vector2.ZERO, 0.0)
	await _step_seconds(0.2)

	_check(boss_bar.visible and boss_bar.is_fighting(), "BossBar active during fight")
	_check(boss_bar.modulate.a > 0.95, "BossBar alpha visible (%.2f)" % boss_bar.modulate.a)
	for keep: String in ["Hotbar", "HealthBar", "StaminaBar", "BlinkIcon"]:
		_check(_part_alpha(hud, keep) > 0.95, "during boss: %s stays visible (%.2f)" % [keep, _part_alpha(hud, keep)])
	for hidden: String in ["ClockVine", "PurseVine", "QuestVine", "HintCard", "FishingHud", "MultiplayerHud"]:
		_check(is_zero_approx(_part_alpha(hud, hidden)), "during boss: %s hidden (%.3f)" % [hidden, _part_alpha(hud, hidden)])

	var mp_hud: MultiplayerHud = hud.get_node_or_null("MultiplayerHud") as MultiplayerHud
	if mp_hud != null:
		_check(not bool(mp_hud.call("_has_point", Vector2(24.0, 320.0))), "hidden MultiplayerHud ignores clicks")

	if not _capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/during_boss.png" % _capture_dir)

	# 3. Boss dies -> peripheral HUDs return cleanly
	hc.current = 0.0
	hc.died.emit()
	await _step_seconds(0.9)
	_check(not boss_bar.is_fighting(), "BossBar no longer fighting after death")
	for rest: String in ["ClockVine", "PurseVine", "QuestVine", "MultiplayerHud", "Hotbar", "HealthBar", "StaminaBar"]:
		_check(_part_alpha(hud, rest) > 0.95, "after death: %s restored (%.2f)" % [rest, _part_alpha(hud, rest)])

	if not _capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/after_boss.png" % _capture_dir)

	# 4. Boss despawns / player leaves arena -> release() also restores HUDs
	var hc2 := HealthComponent.new()
	hc2.max_health = 400.0
	hc2.current = 400.0
	add_child(hc2)
	get_tree().call_group("boss_bar", "track", "MORWENNA", hc2)
	await _step_seconds(0.55)
	_check(is_zero_approx(_part_alpha(hud, "ClockVine")), "second boss hides ClockVine")
	_check(is_zero_approx(_part_alpha(hud, "PurseVine")), "second boss hides PurseVine")
	get_tree().call_group("boss_bar", "release")
	await _step_seconds(0.75)
	_check(_part_alpha(hud, "ClockVine") > 0.95, "release restores ClockVine")
	_check(_part_alpha(hud, "PurseVine") > 0.95, "release restores PurseVine")
	_check(_part_alpha(hud, "QuestVine") > 0.95, "release restores QuestVine")

	NetworkManager.leave()
	print("TEST BOSS HUD HIDE: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
