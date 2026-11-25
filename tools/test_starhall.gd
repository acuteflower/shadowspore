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
	var world: ZoneWorld = load("res://src/world/v2/zone_world.tscn").instantiate() as ZoneWorld
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
	_check("starhall cosmos zero-G surface", interiors.surface_at(interiors.starhall_position()) == "cosmos")
	_check("starhall music stream loaded", music != null and ResourceLoader.exists("res://assets/audio/music/starhall.mp3"))

	# 1. Portrait slicing check for DialogueBox
	var dlg: DialogueBox = DialogueBox.find(player)
	_check("dialogue box exists", dlg != null)
	if dlg != null:
		var p_tex: Texture2D = dlg._portrait_for("DIE WÄCHTERIN")
		_check("goddess portrait slices cleanly", p_tex != null and Vector2i(p_tex.get_size()) == DialogueArt.LOGICAL_SIZE)

	# 2. First-death rescue + pre-intro statue travel checks
	world.add_to_group("story_world")
	world.opening_over = false
	_check("rescue blocked before opening_over", not goddess.can_rescue(player))
	world.opening_over = true
	world.remove_from_group("story_world")
	_check("rescue eligible after opening even with 0 awake statues", goddess.can_rescue(player))
	waystones.import_state({"awake": ["bucht_waechterin"]})
	await get_tree().process_frame
	_check("statue travel eligible before first death with 1 awake statue", goddess.can_travel_to_starhall(player))
	var statue: WaystoneStatue = waystones.statue_node("bucht_waechterin")
	_check("bucht_waechterin statue node exists", statue != null)
	await goddess.travel_to_starhall(player, "bucht_waechterin")
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

	# 4. Float to Caelia in center of open interstellar space & talk -> grants LICHTSCHRITT
	var cam: Camera2D = player.get_node("Camera2D") as Camera2D
	player.global_position = hall.room_to_global(ZeroGRules.room_center() + Vector2(0.0, 52.0))
	player.facing = Vector2.UP
	player.reset_physics_interpolation()
	cam.reset_smoothing()
	cam.force_update_scroll()
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_check("player floats in zero-G inside interstellar sanctuary", player.in_zero_g() and player._sheet == Player.FLOAT_SHEET_ID)
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

	# 4b. Return dialogue with Caelia once known -> full illuminated Goddess portrait -> Caelia's Sternenaltar
	if player.quests != null:
		player.quests.set_flag("knows_goddess")
	_check("caelia_stars quest started after blessing", player.quests != null and player.quests.is_active("caelia_stars"))
	player.inventory.add_item("star_shard", 42)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("caelia_stars advances once player owns star_shard", player.quests != null and player.quests.has_flag("caelia_has_shard") and player.quests.active_step_id("caelia_stars") == "bring_star_shards")
	room.goddess.interact(player)
	await get_tree().create_timer(0.75, true).timeout
	await _shot("2b_goddess_portrait_revealed")
	if dlg != null and dlg.is_active():
		dlg._end()
	wait_t = 0.0
	var altar: Node = null
	while wait_t < 2.0 and altar == null:
		await get_tree().process_frame
		wait_t += get_process_delta_time()
		altar = get_tree().get_first_node_in_group("goddess_window")
	_check("sternenaltar opens after return dialogue", altar != null)
	if altar != null:
		for _i: int in 45:
			await get_tree().process_frame
		await _shot("8_caelia_altar_gifts")
		var hp_before: float = player.health.max_health
		var stam_before: float = player.stamina.max_stamina
		var blade_offer_cost: int = 0
		for off: Dictionary in GoddessSystem.OFFERS:
			if String(off.get("id", "")) == "blade_starlight":
				blade_offer_cost = int(off.get("cost", 0))
		_check("blade_starlight costs 30 star shards", blade_offer_cost == 30)
		goddess.request_exchange("stardust_elixir")
		goddess.request_exchange("morningstar_pendant")
		goddess.request_exchange("blade_starlight")
		goddess.request_donate(7)
		await get_tree().process_frame
		await get_tree().process_frame
		_check("exchanged starlight items in inventory", player.inventory.has_item("stardust_elixir") and player.inventory.has_item("morningstar_pendant") and player.inventory.has_item("blade_starlight"))
		_check("shards collected counter tracks trades + donations", goddess.shards_collected(player) == 42)
		_check("caelia_stars quest completed after first offering", player.quests != null and player.quests.is_finished("caelia_stars"))
		altar.call("_set_tab", 1)
		for _i: int in 15:
			await get_tree().process_frame
		await _shot("9_caelia_altar_collection")
		goddess.request_claim_milestone("m1")
		goddess.request_claim_milestone("m2")
		goddess.request_claim_milestone("m3")
		goddess.request_claim_milestone("m4")
		await get_tree().process_frame
		await get_tree().process_frame
		_check("milestones increase health & stamina", player.health.max_health >= hp_before + 25.0 and player.stamina.max_stamina >= stam_before + 30.0)
		_check("milestone m2 grants starfall night bonus", GoddessSystem.any_starfall_bonus(get_tree()) >= 1)
		_check("milestone m3 strengthens lichtschritt", GoddessSystem.star_step_rank(player) >= 1)
		_check("milestone m4 grants caelia_sigil", player.inventory.has_item("caelia_sigil"))
		altar.call("_close")
		wait_t = 0.0
		while wait_t < 1.5 and is_instance_valid(altar):
			await get_tree().process_frame
			wait_t += get_process_delta_time()
		player.story_lock = false
		player.view_shift = Vector2.ZERO
		cam.zoom = Vector2.ONE
		cam.reset_smoothing()
		cam.force_update_scroll()
		await get_tree().process_frame

	# 5. Execute Lichtschritt & check FX + combat shockwave
	player.global_position = hall.room_to_global(ZeroGRules.room_center() + Vector2(-40.0, 120.0))
	player.stamina.current = player.stamina.max_stamina
	await get_tree().process_frame
	cam.reset_smoothing()
	cam.force_update_scroll()
	var dummy_hurt: _TestDummyHurtbox = _TestDummyHurtbox.new()
	dummy_hurt.global_position = player.global_position + Vector2(104.0, -12.0)
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
	await get_tree().create_timer(0.14).timeout
	await _shot("4_lichtschritt_fx")
	await get_tree().create_timer(0.18).timeout
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

	# 5c. Equip blade_starlight & morningstar_pendant -> test starlight gear + swing trail + starlight perk
	player.global_position = hall.room_to_global(ZeroGRules.room_center() + Vector2(-36.0, 62.0))
	player.velocity = Vector2.ZERO
	player.facing = Vector2.DOWN
	var blade_slot: int = _find_slot(player.inventory, "blade_starlight")
	if blade_slot >= 0:
		player.inventory.request("equip", [blade_slot, "main_hand"])
	if player.progress != null and player.progress.claimed < 5:
		player.progress.claimed = 5
	var neck_slot: int = _find_slot(player.inventory, "morningstar_pendant")
	if neck_slot >= 0:
		player.inventory.request("equip", [neck_slot, "talisman_1"])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("blade_starlight equipped in main_hand", String((player.inventory.equipment.get("main_hand", {}) as Dictionary).get("id", "")) == "blade_starlight")
	_check("morningstar_pendant worn as talisman", player.talismans != null and player.talismans.perks.has("starlight"))
	cam.zoom = Vector2(1.5, 1.5)
	cam.reset_smoothing()
	cam.force_update_scroll()
	player.attack.attack(Vector2(0.8, 0.45).normalized())
	await get_tree().create_timer(0.11).timeout
	await _shot("10_ellie_starlight_gear")
	cam.zoom = Vector2.ONE
	await get_tree().create_timer(0.35).timeout
	for _w: int in 40:
		if player.attack.can_attack():
			break
		await get_tree().process_frame
	await get_tree().create_timer(0.65).timeout
	player.velocity = Vector2.ZERO
	var star_dummy: _TestDummyHurtbox = _TestDummyHurtbox.new()
	star_dummy.global_position = player.global_position + Vector2(20.0, -24.0)
	world.add_child(star_dummy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.talismans.note_blink()
	_check("morningstar_pendant arms starlight_left on blink", player.talismans.starlight_left > 0.0)
	player.attack.attack(Vector2.RIGHT)
	await get_tree().create_timer(0.35).timeout
	_check("starlight perk deals main + wave hit on first attack after blink", star_dummy.hits >= 2 and player.talismans.starlight_left <= 0.0)
	star_dummy.queue_free()

	# 5d. blade_starlight unique right-click: Sternenstich (Astral Crescent + 3 stars) & Himmelsfall (5 stars + heal)
	for _w2: int in 40:
		if player.attack.can_attack():
			break
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	player.global_position = hall.room_to_global(ZeroGRules.room_center() + Vector2(-72.0, 62.0))
	player.velocity = Vector2.ZERO
	player.stamina.current = player.stamina.max_stamina
	cam.zoom = Vector2(1.25, 1.25)
	cam.reset_smoothing()
	cam.force_update_scroll()
	var alt_dummy: _TestDummyHurtbox = _TestDummyHurtbox.new()
	alt_dummy.global_position = player.global_position + Vector2(68.0, -24.0)
	world.add_child(alt_dummy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("blade_starlight exposes custom alt attack", player.attack.can_alt())
	player.attack.alt_press(Vector2.RIGHT)
	await get_tree().create_timer(0.24).timeout
	var found_starfall_fx: bool = false
	for child: Node in get_tree().current_scene.get_children():
		if child is StarfallFx:
			found_starfall_fx = true
	_check("sternenstich spawns StarfallFx", found_starfall_fx)
	await _shot("11_starlight_sternenstich")
	await get_tree().create_timer(0.28).timeout
	var hits_after_stage1: int = alt_dummy.hits
	_check("sternenstich hits distant enemy with astral crescent + stars", hits_after_stage1 >= 2)
	# Reset combo cleanly, then run uninterrupted Stage 1 -> Stage 2 (Himmelsfall) chain + capture
	await get_tree().create_timer(0.85).timeout
	for _w3: int in 40:
		if player.attack.can_alt():
			break
		await get_tree().process_frame
	player.global_position = hall.room_to_global(ZeroGRules.room_center() + Vector2(-72.0, 62.0))
	player.velocity = Vector2.ZERO
	player.stamina.current = player.stamina.max_stamina
	player.attack.alt_press(Vector2.RIGHT)
	await get_tree().create_timer(0.48).timeout
	for _w4: int in 20:
		if player.attack.can_alt():
			break
		await get_tree().process_frame
	player.global_position = hall.room_to_global(ZeroGRules.room_center() + Vector2(-72.0, 62.0))
	player.velocity = Vector2.ZERO
	var hits_before_stage2: int = alt_dummy.hits
	player.stamina.current = player.stamina.max_stamina
	player.health.current = player.health.max_health - 20.0
	var hp_wounded: float = player.health.current
	player.attack.alt_press(Vector2.RIGHT)
	await get_tree().create_timer(0.24).timeout
	await _shot("12_starlight_himmelsfall")
	await get_tree().create_timer(0.50).timeout
	_check("himmelsfall hits with falling star lances & heals player", alt_dummy.hits > hits_before_stage2 and player.health.current > hp_wounded)
	cam.zoom = Vector2.ONE
	alt_dummy.queue_free()

	# 6. Map travel opens AtlasView in travel mode with 1 awake statue
	var map_win: Node = get_tree().get_first_node_in_group("map_window")
	_check("map travel opens with 1 awake statue", map_win != null and bool(map_win.call("open_travel", "bucht_waechterin")))
	if map_win != null and map_win.visible:
		for _i: int in 10:
			await get_tree().process_frame
		await _shot("6_map_starhall")
		map_win.call("_set_open", false)
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
	_check("reset clears state", not goddess.is_introduced_player(player) and not player.light_step and goddess.shards_collected(player) == 0)
	goddess.import_state(exported)
	_check("import restores introduced, light_step, shards and milestones", goddess.is_introduced_player(player) and player.light_step and goddess.shards_collected(player) == 42 and goddess.has_milestone(player, "m4"))

	print("STARHALL: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


func _find_slot(inv: InventoryComponent, item_id: String) -> int:
	if inv == null:
		return -1
	for i: int in inv.slots.size():
		var st: Dictionary = inv.slots[i]
		if not st.is_empty() and String(st.get("id", "")) == item_id:
			return i
	return -1


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
