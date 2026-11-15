extends Node
## Automated end-to-end verification for the Star Hall, Goddess Caelia ("Die Wächterin"),
## first-death cosmic rescue, statue <-> Star Hall travel, Lichtschritt purification,
## music hook, portrait slicing, and SaveGame state round-trip.
## `-- --capture=/abs/dir` saves screenshots when run with a renderer (--rendering-driver opengl3).

var _ok: bool = true
var _dir: String = ""


func _check(label: String, cond: bool) -> void:
	if not cond:
		_ok = false
		print("FAILED: ", label)
	else:
		print("PASS: ", label)


func _shot(label: String) -> void:
	if _dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, label])


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_dir = arg.trim_prefix("--capture=")
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var player: Player = world._players.get_child(0) as Player
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	var waystones: Waystones = Waystones.of(get_tree())
	var goddess: GoddessSystem = GoddessSystem.of(get_tree())
	var hall: Interior = interiors.interior("starhall") if interiors != null else null
	var room: StarHallRoom = hall.get_node_or_null("StarHallRoom") as StarHallRoom if hall != null else null
	var music: MusicDirector = get_tree().get_first_node_in_group("music_director") as MusicDirector

	_check("goddess system registered", goddess != null)
	_check("starhall interior exists", hall != null and room != null and room.goddess != null and room.return_seal != null)
	_check("starhall stone surface", interiors.surface_at(interiors.starhall_position()) == "stone")
	_check("starhall music stream loaded", music != null and ResourceLoader.exists("res://assets/audio/music/starhall.mp3"))

	# 1. Portrait slicing check for DialogueBox
	var dlg: DialogueBox = DialogueBox.find(player)
	_check("dialogue box exists", dlg != null)
	if dlg != null:
		var p_tex: Texture2D = dlg._portrait_for("DIE WÄCHTERIN")
		_check("goddess portrait slices cleanly", p_tex != null and Vector2i(p_tex.get_size()) == DialogueArt.LOGICAL_SIZE)

	# 2. First-death rescue + pre-intro statue travel checks
	world.opening_over = false
	_check("rescue blocked before opening_over", not goddess.can_rescue(player))
	world.finish_opening()
	_check("rescue eligible after opening even with 0 awake statues", goddess.can_rescue(player))
	waystones.import_state({"awake": ["hang_wachterin"]})
	await get_tree().process_frame
	_check("statue travel eligible before first death with 1 awake statue", goddess.can_travel_to_starhall(player))
	var pre_mw: MapWaystones = MapWaystones.new()
	pre_mw.travel_from = "hang_wachterin"
	pre_mw.update(0.016, get_tree(), Vector2(320.0, 58.0), func(t: Vector2) -> Vector2: return t, false, false, 0)
	_check("map waystones includes starhall before first death", pre_mw.destinations().has(GoddessSystem.STARHALL_ID))
	var statue: WaystoneStatue = waystones.statue_node("hang_wachterin")
	_check("hang_wachterin statue node exists", statue != null)
	if statue != null:
		player.global_position = statue.global_position + Vector2(0.0, 20.0)
		statue.interact(player)
		var travel_map: MapWindow = get_tree().get_first_node_in_group("map_window") as MapWindow
		var open_w: float = 0.0
		while travel_map != null and not travel_map.visible and open_w < 5.0:
			await get_tree().process_frame
			open_w += get_process_delta_time()
		_check("statue interact opens map in travel mode", travel_map != null and travel_map.visible)
		if travel_map != null and travel_map.visible:
			travel_map.set("_cursor", MapWaystones.STARHALL_SCREEN)
			travel_map.set("_ws_mouse", true)
		var tr_w: float = 0.0
		while tr_w < 6.0 and (player.get_node_or_null("WaystoneTravel") != null or interiors.is_busy()):
			await get_tree().process_frame
			tr_w += get_process_delta_time()
		if travel_map != null:
			travel_map.set("_ws_mouse", false)
	_check("arrived in starhall via statue before first death", interiors.in_starhall(player.global_position) and not player.story_lock)
	await goddess.return_from_starhall(player)
	_check("returned from starhall to world", not interiors.in_starhall(player.global_position))
	goddess.debug_reset(player)
	await get_tree().process_frame
	_check("rescue eligible after opening + 1 awake statue", goddess.can_rescue(player))

	# 3. Trigger lethal blow -> rescued to Star Hall (even if talisman ward is hooked)
	var ward_tripped: Array[bool] = [false]
	player.health.ward = func(_left: float) -> float:
		ward_tripped[0] = true
		return 10.0
	player.global_position = Vector2(840.0 * 16.0, 660.0 * 16.0)
	player.health.take_damage(99999.0, Vector2.ZERO, 0.0, 0)
	player.health.ward = Callable()
	_check("story_ward runs before talisman ward on first death", not ward_tripped[0])
	_check("lethal hit prevented by goddess ward", player.health.current > 0.0 and player.health.current == player.health.max_health)
	_check("goddess marked introduced immediately", goddess.is_introduced_player(player))
	_check("second lethal rescue blocked", not goddess.can_rescue(player))

	if player.quests != null:
		player.quests.set_flag("hud_unlocked")

	# Wait for rescue flash & teleport into Star Hall and transition settle
	var wait_t: float = 0.0
	while wait_t < 4.5 and (not interiors.in_starhall(player.global_position) or goddess.is_busy()):
		await get_tree().process_frame
		wait_t += get_process_delta_time()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("player teleported to starhall", interiors.in_starhall(player.global_position))
	_check("music switches to starhall indoors", music != null and music.in_starhall)
	_check("rescue wake dialogue started", dlg != null and dlg.is_active())
	await get_tree().create_timer(0.65, true).timeout
	await _shot("0_starhall_arrival")
	if dlg != null and dlg.is_active():
		dlg._end()
	await get_tree().process_frame
	await get_tree().process_frame

	# 4. Walk to Throne & talk to Caelia -> grants LICHTSCHRITT
	var cam: Camera2D = player.get_node("Camera2D") as Camera2D
	player.global_position = hall.room_to_global(Vector2(280.0, 210.0))
	player.facing = Vector2.UP
	player.reset_physics_interpolation()
	cam.reset_smoothing()
	cam.force_update_scroll()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_check("goddess interact prompt ready", room.goddess.prompt() == "SPRECHEN")
	_shot_deferred_noop()
	await _shot("1_goddess_throne")

	room.goddess.interact(player)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("goddess intro dialogue opens", dlg != null and dlg.is_active())
	await get_tree().create_timer(0.75, true).timeout
	await _shot("2_goddess_dialogue")
	if dlg != null and dlg.is_active():
		dlg._end()
	wait_t = 0.0
	while wait_t < 3.5 and (goddess.is_busy() or not player.light_step):
		await get_tree().process_frame
		wait_t += get_process_delta_time()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("lichtschritt unlocked on player", player.light_step)
	_check("lichtschritt extended range", player.effective_step_range() > player.step_range)
	_check("lichtschritt reduced stamina cost", player.step_cost() < (player.step_stamina + float(player.progress.level)))
	var blink_script: Script = load("res://src/ui/blink_icon.gd") as Script
	var skill_script: Script = load("res://src/ui/skill_tree_window.gd") as Script
	var blink_icon: Control = null
	var skill_win: Control = null
	for n: Node in world.find_children("*", "", true, false):
		if n.get_script() == blink_script:
			blink_icon = n as Control
		elif n.get_script() == skill_script:
			skill_win = n as Control
	if blink_icon != null:
		blink_icon.queue_redraw()
		_check("hud blink icon bound to light_step player", blink_icon.get("_blink") != null and player.light_step)
	await _shot("3_goddess_blessing")

	# 4b. Return dialogue with Caelia once known -> full illuminated Goddess portrait
	if player.quests != null:
		player.quests.set_flag("knows_goddess")
	room.goddess.interact(player)
	await get_tree().create_timer(0.75, true).timeout
	await _shot("2b_goddess_portrait_revealed")
	if dlg != null and dlg.is_active():
		dlg._end()
	await get_tree().process_frame
	await get_tree().process_frame

	# 5. Execute Lichtschritt & check FX + combat shockwave
	player.global_position = hall.room_to_global(Vector2(280.0, 480.0))
	player.stamina.current = player.stamina.max_stamina
	cam.reset_smoothing()
	cam.force_update_scroll()
	var dummy_hurt: _TestDummyHurtbox = _TestDummyHurtbox.new()
	dummy_hurt.global_position = player.global_position + Vector2(68.0, -12.0)
	world.add_child(dummy_hurt)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var started_step: bool = player._try_shadow_step(Vector2.RIGHT)
	_check("lichtschritt triggers cleanly", started_step)
	await get_tree().process_frame
	var found_light_fx: bool = false
	for child: Node in get_tree().current_scene.get_children():
		if child is LightStepFx:
			found_light_fx = true
	_check("LightStepFx spawned instead of ShadowStepFx", found_light_fx)
	await _shot("4_lichtschritt_fx")
	await get_tree().create_timer(0.25).timeout
	_check("lichtschritt arrival damages nearby enemy hurtbox", dummy_hurt.hits >= 1)
	dummy_hurt.queue_free()

	# 5b. SkillTreeWindow displays LICHTSCHRITT
	if skill_win != null:
		skill_win.call("_set_open", true)
		for _i: int in 25:
			await get_tree().process_frame
		await _shot("5_skill_tree_lichtschritt")
		skill_win.call("_finish_close")
		await get_tree().process_frame

	# 6. Map travel destination includes STERNENSAAL even with 1 awake statue + live screenshot
	var mw: MapWaystones = MapWaystones.new()
	mw.travel_from = "hang_wachterin"
	mw.update(0.016, get_tree(), Vector2(320.0, 58.0), func(t: Vector2) -> Vector2: return t, false, false, 0)
	_check("map waystones includes starhall with 1 statue", mw.destinations().has(GoddessSystem.STARHALL_ID))
	var map_win: Node = get_tree().get_first_node_in_group("map_window")
	if map_win != null and map_win.call("open_travel", "hang_wachterin"):
		for _i: int in 25:
			await get_tree().process_frame
		await _shot("6_map_starhall")
		map_win.visible = false
		map_win.set("_opening", false)
		map_win.set("_open_t", 0.0)
		InputManager.map_open = false
		InputManager.ui_blocking = false
		get_tree().paused = false
		await get_tree().process_frame

	# 7. Return seal view + brings player back outside
	player.global_position = room.return_seal.global_position + Vector2(0.0, 12.0)
	cam.reset_smoothing()
	cam.force_update_scroll()
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("7_return_seal")
	room.return_seal.interact(player)
	wait_t = 0.0
	while wait_t < 2.5 and interiors.in_starhall(player.global_position):
		await get_tree().process_frame
		wait_t += get_process_delta_time()
	_check("return seal returns player outside", not interiors.in_starhall(player.global_position))

	# 8. SaveGame round-trip check
	var exported: Dictionary = goddess.export_state()
	goddess.debug_reset(player)
	_check("reset clears state", not goddess.is_introduced_player(player) and not player.light_step)
	goddess.import_state(exported)
	_check("import restores introduced and light_step", goddess.is_introduced_player(player) and player.light_step)

	print("STARHALL: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


func _shot_deferred_noop() -> void:
	pass


class _TestDummyHurtbox:
	extends HurtboxComponent
	var hits: int = 0

	func _ready() -> void:
		collision_layer = 1 << 4
		collision_mask = 0
		var col: CollisionShape2D = CollisionShape2D.new()
		var circ: CircleShape2D = CircleShape2D.new()
		circ.radius = 12.0
		col.shape = circ
		add_child(col)

	func take_hit(damage: float, from: Vector2, knockback: float, source: int = 0) -> void:
		hits += 1
		super.take_hit(damage, from, knockback, source)
