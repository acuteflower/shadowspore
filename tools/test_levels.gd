extends Node
## Levels, rewards, collecting and the Fortschritt window with a real player. Never opens the world or reads a save.
## `Godot --headless --path . tools/test_levels.tscn` (optional `-- --capture=/abs/folder` on a rendering driver).
const PLAYER: PackedScene = preload("res://src/entities/player/player.tscn")
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + label)


func key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _capture_dir() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return arg.trim_prefix("--capture=")
	return ""


func _shot(name: String) -> void:
	var dir: String = _capture_dir()
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		for action: StringName in InputMap.get_actions():
			for event: InputEvent in InputMap.action_get_events(action):
				if event is InputEventKey and (event as InputEventKey).keycode == KEY_NONE:
					(event as InputEventKey).keycode = (event as InputEventKey).physical_keycode
	_test_curve()
	_test_rewards()
	await _test_player()
	print("LEVEL TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _test_curve() -> void:
	check(Levels.level_for(0) == 1, "no XP is level 1")
	check(Levels.max_level() == 30, "the cap is level 30")
	var previous: int = 0
	for n: int in range(1, Levels.max_level()):
		var need: int = Levels.xp_to_next(n)
		check(need > previous, "level %d needs more XP than the one before" % n)
		previous = need
		check(Levels.level_for(Levels.xp_at(n + 1)) == n + 1, "the XP threshold of level %d reaches it" % (n + 1))
		check(Levels.level_for(Levels.xp_at(n + 1) - 1) == n, "one XP short of level %d stays below" % (n + 1))
	check(Levels.xp_to_next(1) >= 15 and Levels.xp_to_next(1) <= 40, "the first level comes within a few kills")
	check(Levels.xp_at(Levels.max_level()) < 50000, "the cap is not out of reach")


func _test_rewards() -> void:
	var base: Dictionary = LevelRewards.stats_at(1)
	check(int(base["health"]) == 100 and int(base["stamina"]) == 100, "level 1 keeps 100 health and 100 stamina")
	check(float(base["armor"]) == 0.0 and int(base["talismans"]) == 0, "level 1 has no armor and no talisman slot")
	for n: int in range(2, Levels.max_level() + 1):
		var last: Dictionary = LevelRewards.stats_at(n - 1)
		var now: Dictionary = LevelRewards.stats_at(n)
		check(float(now["health"]) > float(last["health"]), "level %d gives health" % n)
		check(float(now["armor"]) >= float(last["armor"]), "armor never falls")
		if not LevelRewards.is_milestone(n):
			check(float(now["armor"]) == float(last["armor"]) and int(now["talismans"]) == int(last["talismans"]), "level %d (no milestone) gives no armor or slot" % n)
		check(not LevelRewards.lines(n).is_empty(), "level %d has a card" % n)
	check(LevelRewards.is_milestone(5) and LevelRewards.is_milestone(30) and not LevelRewards.is_milestone(6), "milestones every five levels")
	check(float(LevelRewards.stats_at(30)["armor"]) <= 8.0, "armor stays small (gear brings the rest)")
	check(int(LevelRewards.stats_at(30)["talismans"]) >= 1, "milestones open talisman slots")
	check(LevelRewards.next_milestone(1) == 5 and LevelRewards.next_milestone(5) == 10 and LevelRewards.next_milestone(30) == 0, "next milestone lookup")
	check(absf(LevelRewards.damage_factor(0.0) - 1.0) < 0.0001 and LevelRewards.damage_factor(20.0) < 1.0 and LevelRewards.damage_factor(1000.0) > 0.0, "armor reduces damage but never to zero")
	var talisman_level: int = LevelRewards.talisman_level(1)
	check(talisman_level > 1 and LevelRewards.is_milestone(talisman_level), "the first talisman slot opens at a milestone")
	for n: int in range(2, Levels.max_level() + 1):
		check(NightRules.budget(n, 1, 1) >= NightRules.budget(n - 1, 1, 1), "level %d does not make the night easier" % n)


func _test_player() -> void:
	var player: Player = PLAYER.instantiate() as Player
	player.name = "1"
	add_child(player)
	await get_tree().process_frame
	var progress: ProgressComponent = player.progress
	var health: HealthComponent = player.health
	var window: ProgressWindow = player._hud.get_node("ProgressWindow") as ProgressWindow
	check(window != null, "the HUD carries the Fortschritt window")
	check(progress.claimed == 1 and progress.claimable() == 0, "a new character has nothing to collect")
	check(is_equal_approx(health.max_health, 100.0) and is_equal_approx(health.armor, 0.0), "starting values")

	# rising in level changes nothing until the reward is collected
	progress.award(0, Levels.xp_at(6))
	check(progress.level == 6 and progress.claimed == 1 and progress.claimable() == 5, "five levels wait to be collected")
	check(is_equal_approx(health.max_health, 100.0), "unclaimed levels do not raise health")
	check(player.inventory.slot_open("talisman_1") == false, "the talisman slot is sealed before collecting")

	# a partial claim
	progress.request_claim(3)
	check(progress.claimed == 3, "claim up to level 3")
	check(is_equal_approx(health.max_health, float(LevelRewards.stats_at(3)["health"])), "health follows the claimed level")
	check(is_equal_approx(health.current, health.max_health), "the added health arrives at once")
	progress.request_claim(2)
	check(progress.claimed == 3, "claiming backwards does nothing")
	progress.request_claim(99)
	check(progress.claimed == 6, "claim never goes beyond the reached level")
	check(health.armor > 0.0 and is_equal_approx(health.overheal_ratio, float(LevelRewards.stats_at(6)["overheal"])), "the milestone gave armor and overheal")
	check(player.inventory.slot_open("talisman_1"), "the milestone opened the talisman slot")
	check(is_equal_approx(player.stamina.max_stamina, float(LevelRewards.stats_at(6)["stamina"])), "stamina follows the claimed level")

	# armor in a blow
	health.invulnerable_seconds = 0.0
	var before: float = health.current
	health.take_damage(20.0, Vector2.ZERO, 0.0)
	var taken: float = before - health.current
	check(taken < 20.0 and taken > 15.0, "armor softens a blow (took %.1f)" % taken)

	# the window
	var quests: QuestComponent = player.quests
	quests.set_flag("hud_unlocked")
	progress.award(0, Levels.xp_at(9) - progress.xp)
	check(progress.claimable() == 3, "three levels waiting")
	window.open_window()
	await get_tree().process_frame
	check(window.visible and InputManager.progress_open and InputManager.ui_blocking, "the window opens and takes the input")
	check(window._selected == 7, "it selects the first level to collect")
	for i: int in 70:
		await get_tree().process_frame
	check(window._open_t >= 0.99, "the opening animation completes")
	await _shot("open")
	# holding collects
	window._hold_on_node = false
	window._begin_hold(false, false)
	check(window._held, "a hold starts on the bud")
	var guard: int = 0
	while progress.claimed < 9 and guard < 200:
		await get_tree().create_timer(0.02, true).timeout
		guard += 1
	check(progress.claimed == 9, "holding collects everything reached (claimed %d)" % progress.claimed)
	check(not window._held and window._pending == 0, "the hold ends cleanly")
	await get_tree().create_timer(0.6).timeout
	await _shot("claimed")
	# zoom and pan
	var zoom_before: float = window._zoom_target
	window._zoom_by(3.0, window.size * 0.5)
	check(window._zoom_target > zoom_before, "zooming in")
	window._zoom_by(-30.0, window.size * 0.5)
	check(is_equal_approx(window._zoom_target, ProgressWindow.ZOOM_MIN), "zoom is limited")
	window._select_step(5)
	check(window._selected == 12, "arrow keys move along the road")
	for i: int in 30:
		await get_tree().process_frame
	await _shot("far")
	# closing gives everything back
	window._set_open(false)
	for i: int in 40:
		await get_tree().process_frame
	check(not window.visible and not InputManager.progress_open and not InputManager.ui_blocking, "closing restores input")
	window.open_window()
	await get_tree().process_frame
	window._finish_close()
	check(not InputManager.progress_open and not InputManager.ui_blocking, "a forced close restores input")
	player.queue_free()
	await get_tree().process_frame
