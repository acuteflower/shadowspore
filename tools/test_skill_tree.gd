extends Node
## Isolated real-player/UI regression. Never opens the world or reads the user's save.
const PLAYER: PackedScene = preload("res://src/entities/player/player.tscn")
const SAVE: String = "user://shadowspore-skill-tree-test.json" ## user:// so it also works on Windows (no /tmp)
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dir: String = "/tmp"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			dir = arg.trim_prefix("--capture=")
	get_viewport().get_texture().get_image().save_png(dir + "/shadowspore-skills-" + label + ".png")


func key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func check_void_pixels(window: SkillTreeWindow) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for layer: Control in [window._web, window._orbs, window._chrome]:
		layer.hide()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var scale: Vector2 = Vector2(image.get_size()) / window.size
	var lights: PackedVector4Array = window._material.get_shader_parameter("lights")
	var count: int = int(window._material.get_shader_parameter("light_count"))
	var known_dots: int = 0
	var hidden_dots: int = 0
	for y: int in range(35, int(window.size.y) - 35, 2):
		for x: int in range(35, int(window.size.x) - 35, 2):
			var world: Vector2 = window._center + (Vector2(x, y) - window.size * 0.5) / window._zoom
			var edge: float = INF
			for i: int in count:
				edge = minf(edge, world.distance_to(Vector2(lights[i].x, lights[i].y)) - lights[i].z)
			var pixel: Color = image.get_pixel(roundi(x * scale.x), roundi(y * scale.y))
			if pixel.r > 0.6 and pixel.b > 0.9:
				if edge < -45.0: known_dots += 1
				if edge > 35.0: hidden_dots += 1
	check(known_dots == 0, "no fixed star dots in the explored clearings")
	print("VEIL PIXELS: explored=%d, hidden=%d" % [known_dots, hidden_dots])
	for layer: Control in [window._web, window._orbs, window._chrome]:
		layer.show()


func record_animation(window: SkillTreeWindow, skills: SkillTreeComponent, folder: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(folder)
	skills.import_data({})
	window._reveal.clear()
	window._center = SkillTreeWindow.HOME
	window._flying = false
	window._velocity = Vector2.ZERO
	window._zoom = window._fit_zoom()
	window._zoom_target = window._zoom
	window._time = 0.0
	window._select("movement_echo_a")
	for frame: int in 60:
		if frame == 18: key(KEY_ENTER, true)
		if frame == 29: key(KEY_ENTER, false)
		await get_tree().create_timer(1.0 / 12.0, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder.path_join("%03d.png" % frame))
	key(KEY_ENTER, false)
	check(skills.is_explored("movement_echo_a"), "recorded real hold and reveal completes")


## Holds on the flower of a skill; the next ready upgrade `id` of it is what gets learned.
func hold_learn(window: SkillTreeWindow, skills: SkillTreeComponent, root: String, id: String) -> void:
	window._select(root)
	window._cancel_hold()
	key(KEY_ENTER, true)
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		window._process(SkillTreeWindow.LEARN_SECONDS + 0.05)
	else:
		await get_tree().create_timer(SkillTreeWindow.LEARN_SECONDS + 0.1, true).timeout
	key(KEY_ENTER, false)
	for _wait: int in 60:
		await get_tree().process_frame
		if skills.is_learned(id):
			break


func check_upgrades(player: Player, window: SkillTreeWindow, skills: SkillTreeComponent) -> void:
	var def: Dictionary = {"weapon_class": "sword_1h"} ## an item definition, as AttackComponent reads it
	var discovered: Array = skills.export_data().discovered
	check(skills.is_visible("combo_four") and skills.is_visible("combo_five") and not skills.is_awake("combo_four"), "upgrades are always visible but not learned")
	check(skills.points_total() == 4 and skills.points_free() == 4, "level 5 gives four skill points")
	check(skills.upgrade_state("combo_four") == &"ready" and skills.upgrade_state("combo_five") == &"blocked", "level 5: the first upgrade is ready, the second waits for it")
	check(player.attack._combo_size(def) == 3, "without upgrades the combo has three strikes")
	skills.request_learn("combo_five")
	skills.request_learn("sword_combo")
	skills.request_learn("movement_echo_a")
	check(not skills.is_learned("combo_five") and (skills.export_data().learned as Array).is_empty(), "invalid learn requests do nothing")
	window._select("sword_combo")
	check(window._holdable("sword_combo") and window._next_ready("sword_combo") == "combo_four", "the skill's flower can be held on while an upgrade is ready")
	check(not window._shown("combo_four") and not window._shown("combo_five") and window._shown("sword_combo"), "upgrades are no orbs of their own")
	window._flying = false ## the earlier reveal flew the view away from HOME
	window._velocity = Vector2.ZERO
	window._center = SkillTreeWindow.HOME
	window._zoom = window._fit_zoom()
	window._zoom_target = window._zoom
	check(window._pick(window._screen("sword_combo")) == "sword_combo", "the flower is picked")
	window._process(0.1)
	await capture("upgrade-ready")
	# released early: nothing is bought
	key(KEY_ENTER, true)
	await get_tree().process_frame
	window._process(0.3)
	key(KEY_ENTER, false)
	await get_tree().process_frame
	check(not skills.is_learned("combo_four"), "releasing early does not learn")
	await hold_learn(window, skills, "sword_combo", "combo_four")
	check(skills.is_learned("combo_four") and skills.is_awake("combo_four"), "a completed hold learns the upgrade")
	check(skills.points_free() == 3 and skills.learned_count("sword_combo") == 1, "learning costs exactly one point")
	check(player.attack._combo_size(def) == 4, "the combo has a fourth strike")
	check(window._reveal.has("sword_combo"), "host-confirmed learning plays the animation on the flower")
	check(skills.upgrade_state("combo_five") == &"locked", "level 5: the fifth strike is locked by level")
	skills.request_learn("combo_five")
	check(not skills.is_learned("combo_five"), "an upgrade below its level cannot be learned")
	await get_tree().create_timer(0.5, true).timeout
	await capture("upgrade-learned")
	player.progress.xp = Levels.xp_at(15)
	check(skills.points_total() == 14 and skills.upgrade_state("combo_five") == &"ready" and skills.has_ready_upgrade("sword_combo"), "level 15: the fifth strike is ready")
	await hold_learn(window, skills, "sword_combo", "combo_five")
	check(skills.is_learned("combo_five") and skills.points_free() == 11, "the fifth strike costs two points")
	check(player.attack._combo_size(def) == 5 and skills.learned_count("sword_combo") == 2, "the combo has five strikes")
	check(not skills.has_ready_upgrade("sword_combo"), "nothing left to buy")
	await capture("upgrade-all")
	var saved: Dictionary = skills.export_data()
	skills.import_data({})
	check(not skills.is_learned("combo_four") and player.attack._combo_size(def) == 3, "old saves start without upgrades")
	skills.import_data(saved)
	check(skills.is_learned("combo_four") and skills.is_learned("combo_five") and player.attack._combo_size(def) == 5, "learned upgrades survive a save round trip")
	skills.import_data({"learned": ["combo_five"]})
	check(not skills.is_learned("combo_five"), "an upgrade whose parent is missing is rejected")
	skills.import_data({"learned": ["combo_five", "combo_four", "combo_four", "unknown", "sprint"]})
	check(skills.is_learned("combo_five") and skills.is_learned("combo_four") and (skills.export_data().learned as Array).size() == 2, "unordered saves restore the chain, duplicates and unknown IDs are dropped")
	player.progress.xp = Levels.xp_at(5)
	skills.import_data(saved)
	check(skills.is_learned("combo_four") and not skills.is_learned("combo_five"), "a save with an upgrade above the level is trimmed")
	skills.import_data({"learned": "invalid"})
	check((skills.export_data().learned as Array).is_empty(), "a malformed learned list is ignored")
	skills.import_data({"discovered": discovered, "learned": ["combo_four"]}) ## what the real save below must bring back


func check_sprint(player: Player) -> void:
	await get_tree().physics_frame
	var start: Vector2 = player.position
	var duration: float = 30.0 / Engine.physics_ticks_per_second
	Input.action_press("move_right")
	Input.action_press("sprint")
	for frame: int in 30:
		await get_tree().physics_frame
	check(player.sprinting and player.position.x > start.x and player.velocity.x > player.max_speed, "sprint input moves Ellie at sprint speed")
	check(is_equal_approx(player.stamina.max_stamina - player.stamina.current, player.sprint_cost_per_sec * duration), "sprinting spends the normal stamina cost")
	player.stamina.refill()
	player.effects.apply("glutatem", 30.0, 5.0)
	for frame: int in 30:
		await get_tree().physics_frame
	check(player.sprinting and is_equal_approx(player.stamina.max_stamina - player.stamina.current, player.sprint_cost_per_sec * duration * 0.85), "Glutatem V reduces sprint cost")
	player.effects.clear("glutatem")
	player.stamina.spend(player.stamina.current)
	start = player.position
	for frame: int in 30:
		await get_tree().physics_frame
	check(not player.sprinting and player.position.x > start.x and is_equal_approx(player.velocity.x, player.max_speed), "empty stamina falls back to walking")
	Input.action_release("move_right")
	Input.action_release("sprint")
	player.request_teleport(Vector2.ZERO)
	player.stamina.refill()


func _run() -> void:
	# The headless server cannot translate physical keyboard layouts for existing HUD labels.
	if DisplayServer.get_name() == "headless":
		for action: StringName in InputMap.get_actions():
			for event: InputEvent in InputMap.action_get_events(action):
				if event is InputEventKey and (event as InputEventKey).keycode == KEY_NONE:
					(event as InputEventKey).keycode = (event as InputEventKey).physical_keycode
	var player: Player = PLAYER.instantiate() as Player
	player.name = "1"
	add_child(player)
	await get_tree().process_frame
	await check_sprint(player)
	var skills: SkillTreeComponent = player.get_node("SkillTreeComponent") as SkillTreeComponent
	var window: SkillTreeWindow = player._hud.get_node("SkillTreeWindow") as SkillTreeWindow
	var nodes: Dictionary = skills.definitions()
	check(nodes.size() == 13, "four roots, one unlock, two upgrades and six placeholders")
	var roots: int = 0
	var visible_count: int = 0
	for id: String in nodes:
		if skills.is_awake(id): roots += 1
		if skills.is_visible(id): visible_count += 1
		check(skills.is_awake(id) or skills.is_upgrade(id) or skills.is_unlock(id) or bool((nodes[id] as Dictionary).get("placeholder", false)), "every non-root has a defined node type")
	check(roots == 4 and visible_count == 11, "the unlock is visible alongside the starters, upgrades and direct neighbours")
	check(skills.is_root("sneak") and skills.upgrades_of("sneak").is_empty() and skills.upgrades_of("sprint").is_empty(), "sprint and sneak have no upgrades")
	check(not skills.can_explore("movement_echo_b"), "hidden descendants cannot be explored")
	check(skills.points_free() == 0 and skills.upgrade_state("combo_four") == &"locked", "level 1: no points, the first upgrade is locked")
	skills.request_learn(WallClimb.SKILL)
	check(window._shown(WallClimb.SKILL) and not skills.is_awake(WallClimb.SKILL) and not skills.can_explore(WallClimb.SKILL), "climbing is a visible purchase and needs a point")
	skills.request_explore("movement_echo_b")
	skills.request_explore("unknown")
	skills.request_explore("sword_combo")
	check((skills.export_data().discovered as Array).is_empty(), "invalid or real-skill requests do nothing")
	player.progress.xp = Levels.xp_at(5)
	var xp: int = player.progress.xp
	var copper: int = player.progress.copper
	var blink_range: float = player.blink.blink_range
	var cooldown: float = player.blink.cooldown
	var sprint_speed: float = player.sprint_speed
	var burst_speed: float = player.burst_speed
	var combo: Dictionary = DataRegistry.get_entry("weapon_classes", "sword_1h").duplicate(true)
	key(KEY_F, true)
	await get_tree().process_frame
	key(KEY_F, false)
	await get_tree().create_timer(1.0, true).timeout
	check(window._opening and window.visible and get_tree().paused, "F opens the real menu and pauses solo")
	check(InputManager.skills_open and InputManager.ui_blocking, "skill menu owns input")
	await check_void_pixels(window)
	check(window._stage.position == Vector2.ZERO and window._stage.size == window.size, "the skill canvas covers the entire page")
	# Cursor anchoring stays correct throughout a smooth zoom, not just at its final scale.
	var cursor: Vector2 = Vector2(420, 110)
	var under_cursor: Vector2 = window._center + (cursor - window.size * 0.5) / window._zoom
	window._zoom_by(1.0, cursor)
	for frame: int in 24:
		window._navigate_view(1.0 / 60.0)
	check((window._center + (cursor - window.size * 0.5) / window._zoom).distance_to(under_cursor) < 0.001, "smooth zoom preserves the graph point under the cursor")
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(400, 15)
	mouse.pressed = true
	window._input(mouse)
	check(window._dragging, "the former header area is draggable")
	var before_drag: Vector2 = window._center
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(18, 9)
	motion.position = mouse.position + motion.relative
	window._input(motion)
	check(window._center.distance_to(before_drag - motion.relative / window._zoom) < 0.001, "dragging moves the graph by the correct zoom-adjusted distance")
	mouse.pressed = false
	window._input(mouse)
	var released_at: Vector2 = window._center
	window._navigate_view(0.08)
	check(window._center.distance_to(released_at) > 0.1, "drag release glides like the world map")
	mouse.position = Vector2(335, window.size.y - 30)
	mouse.pressed = true
	window._input(mouse)
	check(window._dragging, "the former footer area is draggable")
	mouse.pressed = false
	window._input(mouse)
	window._set_zoom_from(90.0)
	check(is_equal_approx(window._zoom_target, SkillTreeWindow.ZOOM_MAX), "top of the zoom vine reaches maximum zoom")
	window._set_zoom_from(window.size.y - 34.0)
	check(is_equal_approx(window._zoom_target, SkillTreeWindow.ZOOM_MIN), "bottom of the zoom vine reaches minimum zoom")
	window._select("sword_combo")
	window._center = SkillTreeWindow.HOME
	window._velocity = Vector2.ZERO
	window._flying = false
	window._anchor = window.size * 0.5
	window._zoom = window._fit_zoom()
	window._zoom_target = window._zoom
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	key(KEY_SPACE, true)
	check(InputManager.move_vector() == Vector2.ZERO and not InputManager.sprint_pressed() and not InputManager.blink_pressed(), "move, sprint and blink cannot leak into the world")
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	key(KEY_SPACE, false)
	await capture("roots")
	window._select("sprint")
	await capture("sprint")
	window._select("shadow_blink")
	await capture("blink")
	if DisplayServer.get_name() != "headless":
		window._center = window._pos("shadow_blink")
		window._zoom = 1.65
		window._zoom_target = 1.65
		await capture("zoomed")
		window._center = SkillTreeWindow.HOME
		window._zoom = window._fit_zoom()
		window._zoom_target = window._zoom
	var inventory: Control = player._hud.get_node("InventoryWindow") as Control
	key(KEY_I, true)
	await get_tree().process_frame
	key(KEY_I, false)
	check(not inventory.visible, "inventory cannot overlap the skill menu")
	window._select("movement_echo_a")
	await capture("placeholder")
	key(KEY_ENTER, true)
	await get_tree().process_frame
	window._process(0.25)
	await capture("holding")
	key(KEY_ENTER, false)
	await get_tree().process_frame
	check(not skills.is_explored("movement_echo_a"), "releasing early does not explore")
	key(KEY_ENTER, true)
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		window._process(0.71)
	else:
		await get_tree().create_timer(0.73, true).timeout
	key(KEY_ENTER, false)
	for _wait: int in 60: ## the host answer may need a few frames under load
		await get_tree().process_frame
		if skills.is_explored("movement_echo_a"):
			break
	check(skills.is_explored("movement_echo_a") and skills.is_visible("movement_echo_b"), "completed hold reveals the next neighbour")
	check(not skills.is_awake("movement_echo_a"), "exploration never makes a placeholder into a skill")
	check(window._reveal.has("movement_echo_a"), "host-confirmed discovery starts reveal animation")
	await get_tree().create_timer(0.35, true).timeout
	await capture("reveal")
	await get_tree().create_timer(0.9, true).timeout
	await capture("explored")
	check(player.progress.xp == xp and player.progress.copper == copper and player.blink.blink_range == blink_range and player.blink.cooldown == cooldown and player.sprint_speed == sprint_speed and player.burst_speed == burst_speed and DataRegistry.get_entry("weapon_classes", "sword_1h") == combo, "exploration changes no XP, money or ability stats")
	var before: Dictionary = skills.export_data()
	skills.request_explore("movement_echo_a")
	check(skills.export_data() == before, "duplicate exploration is idempotent")
	await check_upgrades(player, window, skills)
	var free: int = skills.points_free()
	window._select(WallClimb.SKILL)
	await capture("climb-ready")
	await hold_learn(window, skills, WallClimb.SKILL, WallClimb.SKILL)
	check(skills.is_awake(WallClimb.SKILL) and skills.points_free() == free - 1, "holding on Klettern buys it for exactly one point")
	await capture("climb-learned")
	check(SaveGame.save(get_tree(), SAVE), "isolated save writes discovery")
	skills.import_data({})
	check(not skills.is_explored("movement_echo_a"), "old saves start with roots only")
	check(SaveGame.load_into(get_tree(), SAVE) and skills.is_explored("movement_echo_a"), "save round trip restores discovery")
	check(skills.is_learned("combo_four") and not skills.is_learned("combo_five") and player.attack._combo_size({"weapon_class": "sword_1h"}) == 4, "SaveGame restores learned upgrades")
	check(skills.is_learned(WallClimb.SKILL) and skills.points_free() == free - 1, "SaveGame restores climbing and its point cost")
	skills.import_data({"discovered": ["movement_echo_b", "unknown", "sword_combo", "movement_echo_a", "movement_echo_a"]})
	check((skills.export_data().discovered as Array).size() == 2 and skills.is_explored("movement_echo_b"), "unordered saves restore connected nodes and discard duplicates and unknown IDs")
	skills.import_data({"discovered": ["movement_echo_b"]})
	check(not skills.is_explored("movement_echo_b"), "disconnected save data is rejected")
	skills.import_data({"discovered": "invalid"})
	check((skills.export_data().discovered as Array).is_empty(), "malformed discovery list is ignored")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--record="):
			await record_animation(window, skills, argument.trim_prefix("--record="))
	if DisplayServer.get_name() != "headless":
		skills.import_data({"discovered": nodes.keys()})
		window._reveal.clear()
		window._flying = false
		window._center = Vector2(-14, -25)
		window._zoom = 0.9
		window._zoom_target = 0.9
		window._select("sword_combo")
		await capture("complete")
	key(KEY_ESCAPE, true)
	await get_tree().process_frame
	key(KEY_ESCAPE, false)
	await get_tree().create_timer(0.4, true).timeout
	check(not get_tree().paused and not InputManager.skills_open and not InputManager.ui_blocking, "Escape finishes the closing animation and releases pause/input")
	check(not (player._hud.get_node("PauseMenu") as PauseMenu)._opening, "Escape closes only the skills menu")
	var pause: PauseMenu = player._hud.get_node("PauseMenu") as PauseMenu
	pause._set_open(true)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.9, true).timeout
		await capture("pause-menu")
	pause._run_action("skills")
	check(window._opening and not pause._opening, "pause-menu skill button opens the same view")
	window._finish_close()
	InputManager.ui_blocking = true
	window._set_open(true)
	check(not window._opening, "another modal blocks opening")
	InputManager.ui_blocking = false
	player.story_lock = true
	window._set_open(true)
	check(not window._opening, "story scenes block opening")
	player.story_lock = false
	window._set_open(true)
	player._hud.begin_intro()
	check(not get_tree().paused and not InputManager.skills_open and not InputManager.ui_blocking, "story HUD suspension first releases the skill modal")
	player._hud.end_intro()
	window._set_open(true)
	window.queue_free()
	await get_tree().process_frame
	check(not get_tree().paused and not InputManager.ui_blocking and not InputManager.skills_open, "unexpected window removal restores input and pause")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("SKILL TREE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
