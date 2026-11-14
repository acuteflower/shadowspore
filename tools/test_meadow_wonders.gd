extends Node
## Automated Stage 5 verification (`docs/wiesenbiom_ausbau_konzept.md` — Die 3 Einmaligen Weltwunder):
##  1. `BellPond` (*Der Glockenteich*, shore `[795, 525]` -> spire `[801, 525]`):
##     - Daytime kingfisher perch, submerged stones before midnight (`stones_risen == false`, no dry deck).
##     - Clear midnight (`0.0` / `24:00`): underwater bell tolls, 6 stepping stones rise (`stones_risen == true`),
##       dry `"stone"` causeway (`has_water_deck_at`, `player.swim == 0`), safety hold while crossing,
##       awakening belfry altar -> permanent causeway + legendary `LootChest` carrying `bell_chime_talisman`!
##  2. `SleepingGuardians` (*Der Kreis der Schlafenden Wächter*, `[256, 205]`):
##     - 7 monolith guardians (`6` sleeping, `7th` broken Col `2`) + 7 offering bowls + fallen headstone.
##     - Tests Path B partial/wrong-order reset (`lit_step` `0 -> 2 -> wrong bowl -> 0`).
##     - Tests Path A full awakening: picking up fallen headstone (`player.carry_stone == 1`), carrying to broken
##       guardian socket, restoring 7th monolith to Col `0`, awakening blessing echo (`+1.5 HP/s` & `+4 Stamina/s`),
##       and spawning rising legendary `LootChest`!
##  3. `FlowerAmphitheater` (*Das Blumen-Amphitheater*, `[421, 667]`):
##     - Concentric moonflower rings + circular mossy stone podium + 42 night wisps dancing on awakening + `rare` `LootChest`.
##  4. `MeadowWonders` `export_state()` / `import_state()` roundtrip (plus verifying Path B full `0..6` brazier sequence after reset!).
## Optional `-- --capture=/abs/dir` saves real-world screenshots when run with `--rendering-driver opengl3`.

var _checks: int = 0
var _failures: int = 0
var _capture_dir: String = ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("MEADOW WONDERS TEST FAILED: " + label)
		print("FAILED: ", label)


func _shot(shot_name: String) -> void:
	if _capture_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(shot_name + ".png"))


func _hide_overlays(wonders: MeadowWonders) -> void:
	if wonders != null and wonders._banner != null:
		wonders._banner.visible = false


func _stream_around(world: WorldLevel, tile: Vector2i) -> void:
	var c: Vector2i = tile / WorldLevel.CHUNK
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			world._load_chunk(c + Vector2i(dx, dy))
	await get_tree().physics_frame
	await get_tree().physics_frame


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	world.finish_opening()
	TimeManager.set_time(0.38)
	WeatherManager.force_weather("clear")

	var player: Player = world._players.get_child(0) as Player
	if player.intro != null:
		player.intro.queue_free()
		player.intro = null
	player.story_lock = false
	player.health.heal_full()
	player.stamina.refill()

	var wonders: MeadowWonders = MeadowWonders.of(get_tree())
	var chests: LootChests = LootChests.of(get_tree())
	_check(wonders != null, "MeadowWonders node exists in group 'meadow_wonders'")

	# ------------------------------------------------------------------
	# 1. DER GLOCKENTEICH (BellPond)
	# ------------------------------------------------------------------
	var bell_shore: Vector2i = wonders.bell_shore_tile()
	player.request_teleport(Vector2(bell_shore) * 16.0 + Vector2(-8.0, 8.0))
	await _stream_around(world, bell_shore)

	var pond: BellPond = wonders._bell_node
	_check(pond != null, "BellPond streamed at forest lake shore " + str(bell_shore))
	if pond != null:
		var mid_causeway: Vector2 = (pond.shore_pos + pond.spire_pos) * 0.5
		_check(not pond.stones_risen, "Stepping stones stay submerged during daytime")
		_check(not wonders.has_water_deck_at(mid_causeway), "Submerged causeway does NOT grant dry deck during daytime")
		await _shot("01_bell_pond_day_kingfishers")

		# Switch to clear midnight (00:15 -> tod = 0.01)
		TimeManager.set_time(0.01)
		for _i: int in 6:
			await get_tree().process_frame
		_check(pond.stones_risen, "Clear midnight tolls underwater bell and raises the 6 stepping stones")
		_check(Terrain.surface_at(mid_causeway) == "stone" and wonders.has_water_deck_at(mid_causeway), "Risen stepping stones form dry 'stone' causeway over lake")

		# Walk onto the risen stepping stones and verify Ellie stays dry
		player.request_teleport(mid_causeway)
		for _i2: int in 6:
			await get_tree().physics_frame
		_check(player.swim == 0 and not bool(player._surface.get("water", false)), "Player stands completely dry on risen BellPond stepping stones")
		await _shot("02_bell_pond_midnight_risen")

		# Safety check: if clock leaves midnight while player is still on the causeway, stones stay risen!
		TimeManager.set_time(0.20)
		await get_tree().process_frame
		_check(pond.stones_risen, "Safety hold keeps stepping stones risen while player is crossing the lake")
		TimeManager.set_time(0.01)
		await get_tree().process_frame

		# Reach spire belfry & awaken permanently
		player.request_teleport(pond.spire_pos + Vector2(-10.0, 4.0))
		await get_tree().physics_frame
		var xp_before_bell: int = player.progress.xp
		pond._altar.interact(player)
		for _i3: int in 6:
			await get_tree().process_frame
		_check(wonders.is_bell_awakened() and pond.awakened, "BellPond permanently awakened after ringing belfry altar")
		_check(player.progress.xp == xp_before_bell + 28, "Awakening BellPond awards +28 XP")
		_check(chests.chest("wonder_bell_pond_chest") != null, "Legendary chest rises on BellPond spire platform")
		_check(chests._extra.has("wonder_bell_pond_chest"), "BellPond chest contains guaranteed 'bell_chime_talisman'")
		_hide_overlays(wonders)
		await _shot("03_bell_pond_awakened_chest")

	# ------------------------------------------------------------------
	# 2. DER KREIS DER SCHLAFENDEN WÄCHTER (SleepingGuardians)
	# ------------------------------------------------------------------
	TimeManager.set_time(0.36)
	var guard_tile: Vector2i = wonders.guardians_tile()
	player.request_teleport(Vector2(guard_tile) * 16.0 + Vector2(8.0, 38.0))
	await _stream_around(world, guard_tile)

	var ring: SleepingGuardians = wonders._guardians_node
	_check(ring != null, "SleepingGuardians streamed on Glasklippen plateau " + str(guard_tile))
	if ring != null:
		_check(ring._statues.size() == 7, "All 7 giant guardian monoliths spawned")
		_check(ring._statues[SleepingGuardians.BROKEN_INDEX].frame == 2, "7th guardian starts broken & headless (Col 2)")
		_hide_overlays(wonders)
		await _shot("04_sleeping_guardians_asleep")

		# Test Path B partial sequence + wrong-order reset
		player.request_teleport(ring.global_position + ring.brazier_local_pos(0) + Vector2(0.0, 12.0))
		await get_tree().physics_frame
		wonders.request_light_guardian_brazier(0)
		await get_tree().process_frame
		player.request_teleport(ring.global_position + ring.brazier_local_pos(1) + Vector2(0.0, 12.0))
		await get_tree().physics_frame
		wonders.request_light_guardian_brazier(1)
		await get_tree().process_frame
		_check(ring.lit_step == 2 and ring._braziers[0].lit and ring._braziers[1].lit, "Lighting braziers 0 & 1 advances sequence to step 2")

		# Wrong bowl (index 4 instead of 2) resets unawakened bowls
		player.request_teleport(ring.global_position + ring.brazier_local_pos(4) + Vector2(0.0, 12.0))
		await get_tree().physics_frame
		wonders.request_light_guardian_brazier(4)
		await get_tree().process_frame
		_check(ring.lit_step == 0 and not ring._braziers[0].lit, "Lighting out-of-order brazier resets unawakened bowls to 0")

		# Test Path A: Pick up FallenHeadstone -> carry -> restore 7th guardian!
		var hs_world: Vector2 = ring.global_position + ring.headstone_start
		player.request_teleport(hs_world + Vector2(0.0, 14.0))
		await get_tree().physics_frame
		_check(ring._headstone.prompt() == "KOPFSTEIN AUFHEBEN", "FallenHeadstone exposes 'KOPFSTEIN AUFHEBEN' prompt")
		ring._headstone.interact(player)
		for _i4: int in 4:
			await get_tree().process_frame
		_check(ring.carrier_peer == player.name.to_int() and player.carry_stone == 1, "Interacting with FallenHeadstone puts Ellie into two-handed stone carry state")

		var socket_world: Vector2 = ring._broken_plinth.global_position
		player.request_teleport(socket_world + Vector2(0.0, 14.0))
		await get_tree().physics_frame
		_check(ring._broken_plinth.prompt() == "WÄCHTERHAUPT EINSETZEN", "Broken 7th guardian plinth exposes 'WÄCHTERHAUPT EINSETZEN' while carrying headstone")
		ring._broken_plinth.interact(player)
		for _i5: int in 14:
			await get_tree().process_frame
		_check(wonders.is_guardians_awakened() and ring.awakened and ring.head_restored, "Restoring headstone awakens the Circle of Sleeping Guardians")
		_check(ring._statues[SleepingGuardians.BROKEN_INDEX].frame == 0, "7th guardian statue visually restored to whole monolith (Col 0)")
		_check(chests.chest("wonder_sleeping_guardians_chest") != null, "Legendary chest rises at center of awakened Guardian Circle")

		# Verify Blessing Echo regeneration (+1.5 HP/s & +4 Stamina/s inside ring)
		player.request_teleport(ring.global_position + Vector2(0.0, 18.0))
		player.health.set_health(player.health.max_health - 15.0)
		player.stamina._set_current(40.0)
		var hp_low: float = player.health.current
		var stam_low: float = player.stamina.current
		await get_tree().create_timer(1.15).timeout
		_check(player.health.current > hp_low and player.stamina.current > stam_low, "Awakened Guardian Circle regenerates HP (%.1f->%.1f) & Stamina (%.1f->%.1f)" % [hp_low, player.health.current, stam_low, player.stamina.current])
		_hide_overlays(wonders)
		TimeManager.set_time(0.96)
		for _i6: int in 4:
			await get_tree().process_frame
		await _shot("05_sleeping_guardians_awakened_night")

	# ------------------------------------------------------------------
	# 3. DAS BLUMEN-AMPHITHEATER (FlowerAmphitheater)
	# ------------------------------------------------------------------
	TimeManager.set_time(0.98)
	var amp_tile: Vector2i = wonders.amphitheater_tile()
	player.request_teleport(Vector2(amp_tile) * 16.0 + Vector2(8.0, 64.0))
	await _stream_around(world, amp_tile)

	var amp: FlowerAmphitheater = wonders._amphitheater_node
	_check(amp != null, "FlowerAmphitheater streamed in Die Lichtung hollow " + str(amp_tile))
	if amp != null:
		_check(amp._flower_glows.size() >= 35, "Concentric moonflower rings surround the silent stone podium (flowers=%d)" % amp._flower_glows.size())
		_check(amp.prompt() == "AUF DER STILLEN BÜHNE LAUSCHEN", "Unawakened amphitheater shows stage prompt")

		# Step onto the silent stone stage at night -> automatic wisp dance awakening!
		player.request_teleport(amp.global_position + Vector2(0.0, 6.0))
		for _i7: int in 8:
			await get_tree().process_frame
		_check(wonders.is_amphitheater_awakened() and amp.awakened, "Stepping onto the silent stone stage at night awakens FlowerAmphitheater")
		_check(amp.wisp_intensity() >= 0.99 and amp._wisps.size() == 42, "42 harmonic wisps dance at full intensity around the moonflower stage")
		_check(chests.chest("wonder_flower_amphitheater_chest") != null, "Rare LootChest rises at the southern entrance of FlowerAmphitheater")
		_hide_overlays(wonders)
		await _shot("06_flower_amphitheater_wisps_night")

	# ------------------------------------------------------------------
	# 4. Save/Load Roundtrip + Path B Full 7-Brazier Verification
	# ------------------------------------------------------------------
	var saved_wonders: Dictionary = wonders.export_state()
	wonders.import_state({})
	_check(not wonders.has_progress(), "Empty import resets MeadowWonders state")

	# Verify Path B (all 7 braziers 0..6 in order) also awakens SleepingGuardians cleanly!
	if ring != null:
		for b_idx: int in SleepingGuardians.GUARDIAN_COUNT:
			player.request_teleport(ring.global_position + ring.brazier_local_pos(b_idx) + Vector2(0.0, 10.0))
			await get_tree().physics_frame
			wonders.request_light_guardian_brazier(b_idx)
			await get_tree().process_frame
		_check(wonders.is_guardians_awakened() and not ring.head_restored, "Path B (lighting all 7 braziers in ascending order) awakens SleepingGuardians independently")

	wonders.import_state(saved_wonders)
	_check(wonders.is_bell_awakened() and wonders.is_guardians_awakened() and wonders._guardians_head_restored and wonders.is_amphitheater_awakened(), "MeadowWonders export_state/import_state roundtrips all 3 World Wonders")

	print("MEADOW WONDERS TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
