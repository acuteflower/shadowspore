extends Node
## Automated Stage 3 & Stage 4 verification (`docs/wiesenbiom_ausbau_konzept.md`):
##  - Stage 3 (`red_order`): `OrderMonument` (`watchtower`, `patrol_camp`, `boundary_stone`), `found_order_trace` quest flag,
##    `order_signet` talisman in Nordgrat watchtower chest, and Valdric `order_trace` town dialogue reaction.
##  - Stage 4 (`water_works`):
##      1. `OldWatermill` unjamming (`begin_pull` / `request_unjam_mill`), spinning 6-frame wheel, water splash & rising `LootChest`.
##      2. `BrokenStoneBridge` dry `"stone"` deck override over deep river water, central `42 px` water gap, and crisp Shadow-Step (`Alt`) leap!
##      3. `FisherPier` dry `"wood"` deck override over lake water, `SeatSpot` sitting (`AM FISCHERSTEG RASTEN`), and `ReedRowboat` search drops.
##  - `MeadowPois` export/import roundtrip.
## Optional `-- --capture=/abs/dir` saves real-world screenshots when run with `--rendering-driver opengl3`.

var _checks: int = 0
var _failures: int = 0
var _capture_dir: String = ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("MEADOW POIS TEST FAILED: " + label)
		print("FAILED: ", label)


func _shot(shot_name: String) -> void:
	if _capture_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(shot_name + ".png"))


func _hide_ui_overlays(pois: MeadowPois) -> void:
	if pois != null and pois._banner != null:
		pois._banner.visible = false
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.skip_all()
		box.visible = false


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

	var player: Player = world._players.get_child(0) as Player
	if player.intro != null:
		player.intro.queue_free()
		player.intro = null
	player.story_lock = false
	player.health.heal_full()
	player.stamina.refill()

	var pois: MeadowPois = MeadowPois.of(get_tree())
	_check(pois != null, "MeadowPois node exists in group 'meadow_pois'")
	_check(pois.order_tiles().size() == 13, "All 13 Red Order POIs registered (got %d)" % pois.order_tiles().size())
	_check(pois.mill_tiles().size() == 3, "All 3 OldWatermills registered (got %d)" % pois.mill_tiles().size())
	_check(pois.bridge_tiles().size() == 4, "All 4 BrokenStoneBridges registered (got %d)" % pois.bridge_tiles().size())
	_check(pois.pier_tiles().size() == 6, "All 6 FisherPiers registered (got %d)" % pois.pier_tiles().size())

	# ------------------------------------------------------------------
	# 1. Stage 3: OrderWatchtower + OrderPatrolCamp + Valdric reaction
	# ------------------------------------------------------------------
	var tower_tile: Vector2i = Vector2i(368, 188) ## order_tower_nordgrat
	player.request_teleport(Vector2(tower_tile) * 16.0 + Vector2(8.0, 26.0))
	await _stream_around(world, tower_tile)

	var watchtower: OrderMonument = pois._find_live_order("order_tower_nordgrat")
	_check(watchtower != null, "OrderWatchtower 'order_tower_nordgrat' streamed into chunk")
	var chests: LootChests = LootChests.of(get_tree())
	_check(chests != null and chests.chest("order_tower_nordgrat_chest") != null, "Watchtower rare LootChest placed beside ruin")
	_check(chests._extra.has("order_tower_nordgrat_chest"), "Nordgrat watchtower chest carries guaranteed 'order_signet' talisman")

	if watchtower != null:
		await _shot("01_order_watchtower_day")
		_check(not player.quests.has_flag("found_order_trace"), "Player starts without 'found_order_trace' quest flag")
		var xp_before: int = player.progress.xp
		watchtower.interact(player)
		await get_tree().process_frame
		_check(player.quests.has_flag("found_order_trace"), "Reading OrderWatchtower sets 'found_order_trace' quest flag")
		_check(pois.is_order_discovered("order_tower_nordgrat"), "OrderWatchtower marked discovered in MeadowPois")
		_check(player.progress.xp == xp_before + 12, "First-time Red Order discovery awards +12 XP")

	# Patrol camp visual & banner check
	var camp_tile: Vector2i = Vector2i(538, 654) ## order_camp_lichtung
	player.request_teleport(Vector2(camp_tile) * 16.0 + Vector2(8.0, 26.0))
	await _stream_around(world, camp_tile)
	var camp: OrderMonument = pois._find_live_order("order_camp_lichtung")
	_check(camp != null and camp._banner != null, "OrderPatrolCamp streamed with swaying crimson banner")
	_hide_ui_overlays(pois)
	TimeManager.set_time(0.02)
	for _i3: int in 6:
		await get_tree().process_frame
	await _shot("02_order_patrol_camp_night")
	TimeManager.set_time(0.38)

	# Verify Valdric settler chat includes order_trace pool when flag is set
	world.debug_jump_town()
	world._town_node._check_arrivals(1.0)
	for _i4: int in 6:
		await get_tree().process_frame
	var valdric_node: Settler = world._town_node.settler_node("valdric")
	_check(valdric_node != null, "Valdric settler found after founding town")
	if valdric_node != null:
		var order_lines: Array = (valdric_node.spec.chat as Dictionary).get("order_trace", []) as Array
		var matched_order_line: bool = false
		for _roll: int in 40:
			var picked_line: String = valdric_node._chat_line(player)
			if order_lines.has(picked_line):
				matched_order_line = true
				break
		_check(matched_order_line, "Valdric chat selects Red Order reflection line once 'found_order_trace' is set")

	# ------------------------------------------------------------------
	# 2. Stage 4.1: OldWatermill unjamming + wheel rotation + chest spawn
	# ------------------------------------------------------------------
	var mill_tile: Vector2i = Vector2i(789, 725) ## mill_auental
	player.request_teleport(Vector2(mill_tile) * 16.0 + Vector2(36.0, 8.0))
	await _stream_around(world, mill_tile)

	var mill: OldWatermill = pois._find_live_mill("mill_auental")
	_check(mill != null, "OldWatermill 'mill_auental' streamed on river bank")
	if mill != null:
		_check(not mill.unjammed, "OldWatermill starts jammed by driftwood")
		_check(mill.prompt() == "VERKEILTES TREIBHOLZ LÖSEN", "Jammed watermill shows German unjam prompt")
		_hide_ui_overlays(pois)
		await _shot("03_old_watermill_jammed")
		pois.request_unjam_mill("mill_auental")
		for _i6: int in 18:
			await get_tree().process_frame
		_check(mill.unjammed, "OldWatermill transitions to unjammed state")
		_check(mill._wheel != null and mill._wheel_phase > 0.0, "Watermill paddle wheel rotates continuously after unjamming")
		_check(chests.chest("mill_auental_chest") != null, "Unjamming watermill spawns mill cache chest beside arched door")
		_hide_ui_overlays(pois)
		await _shot("04_old_watermill_spinning")

	# ------------------------------------------------------------------
	# 3. Stage 4.2: BrokenStoneBridge dry deck override + Shadow-Step leap
	# ------------------------------------------------------------------
	var bridge_tile: Vector2i = Vector2i(725, 697) ## bridge_auental (ew)
	player.request_teleport(Vector2(bridge_tile) * 16.0 + Vector2(-56.0, 8.0))
	await _stream_around(world, bridge_tile)

	var live_bridge: BrokenStoneBridge = null
	for br: BrokenStoneBridge in pois._live_bridges:
		if br.bridge_id == "bridge_auental":
			live_bridge = br
			break
	_check(live_bridge != null, "BrokenStoneBridge 'bridge_auental' streamed across river")
	if live_bridge != null:
		var west_brink: Vector2 = Vector2(live_bridge.deck_rects[0].end.x - 4.0, live_bridge.deck_rects[0].get_center().y)
		var gap_mid: Vector2 = (live_bridge.neg_pos + live_bridge.pos_pos) * 0.5
		var east_brink: Vector2 = Vector2(live_bridge.deck_rects[1].position.x + 6.0, live_bridge.deck_rects[1].get_center().y)
		_check(Terrain.surface_at(west_brink) == "stone", "West bridge abutment reports dry 'stone' surface over river")
		_check(pois.has_water_deck_at(west_brink), "West bridge abutment registers water_deck override")
		_check(not pois.has_water_deck_at(gap_mid), "Collapsed central bridge gap is NOT covered by stone deck")

		player.request_teleport(west_brink)
		for _i8: int in 6:
			await get_tree().physics_frame
		_check(player.swim == 0 and not bool(player._surface.get("water", false)), "Player stands completely dry (swim==0, water==false) on stone bridge abutment over river")
		_hide_ui_overlays(pois)
		await _shot("05_broken_stone_bridge_day")

		# Leap across the 42 px broken river chasm using Shadow-Step!
		player.stamina.refill()
		var stepped: bool = player._try_shadow_step(Vector2.RIGHT)
		_check(stepped, "Shadow-Step triggers cleanly from dry stone bridge brink across river chasm")
		for _i9: int in 24:
			await get_tree().physics_frame
		_check(player.global_position.x >= east_brink.x - 2.0, "Shadow-Step carries Ellie across the broken river gap onto the East abutment (x=%.1f vs %.1f)" % [player.global_position.x, east_brink.x])
		_check(player.swim == 0 and pois.has_water_deck_at(player.global_position), "Ellie lands dry on the East stone bridge deck without falling into swim mode")

	# ------------------------------------------------------------------
	# 4. Stage 4.3: FisherPier dry wood deck + sitting + ReedRowboat search
	# ------------------------------------------------------------------
	var pier_tile: Vector2i = Vector2i(347, 467) ## pier_glassee (dir 2 = South)
	player.request_teleport(Vector2(pier_tile) * 16.0 + Vector2(8.0, 8.0))
	await _stream_around(world, pier_tile)

	var pier: FisherPier = pois._find_live_pier("pier_glassee")
	_check(pier != null, "FisherPier 'pier_glassee' streamed on lake shore")
	if pier != null:
		var tip_pt: Vector2 = pier.seat_position()
		_check(Terrain.surface_at(tip_pt) == "wood", "FisherPier head over lake water reports dry 'wood' surface")
		player.request_teleport(pier.approach_position())
		for _i11: int in 6:
			await get_tree().physics_frame
		_check(player.swim == 0 and not bool(player._surface.get("water", false)), "Player walks dry onto wooden lakeside pier without swimming")

		# Sit at the pier head
		pier.interact(player)
		var rest_comp: RestComponent = player.get_node("RestComponent") as RestComponent
		var wait_sit: float = 0.0
		while rest_comp.state != RestComponent.State.IDLE and wait_sit < 3.0:
			await get_tree().create_timer(0.1).timeout
			wait_sit += 0.1
		_check(rest_comp.state == RestComponent.State.IDLE, "Player sits peacefully at the lakeside FisherPier head")
		_hide_ui_overlays(pois)
		await _shot("06_fisher_pier_and_rowboat")
		rest_comp.request_stand()
		var wait_up: float = 0.0
		while rest_comp.state != RestComponent.State.FREE and wait_up < 2.5:
			await get_tree().create_timer(0.1).timeout
			wait_up += 0.1
		_check(rest_comp.state == RestComponent.State.FREE, "Player stands back up cleanly from FisherPier")

		# Search the ReedRowboat
		var drops_node: Node = get_tree().get_first_node_in_group("drops")
		var drops_before: int = drops_node.get_child_count() if drops_node != null else 0
		player.request_teleport(pier.boat_world_pos + Vector2(0.0, -14.0))
		await get_tree().physics_frame
		pois.request_search_rowboat("pier_glassee")
		for _i14: int in 6:
			await get_tree().process_frame
		_check(pois.is_boat_searched("pier_glassee") and pier.boat_searched, "ReedRowboat marked searched after interaction")
		var drops_after: int = drops_node.get_child_count() if drops_node != null else 0
		_check(drops_after >= drops_before + 2, "Searching ReedRowboat pops salvage ItemDrops into the world (before=%d, after=%d)" % [drops_before, drops_after])

	# ------------------------------------------------------------------
	# 5. Save/Load export_state & import_state roundtrip
	# ------------------------------------------------------------------
	var exported: Dictionary = pois.export_state()
	pois.import_state({})
	_check(not pois.has_progress(), "Clearing MeadowPois resets state cleanly")
	pois.import_state(exported)
	_check(pois.is_order_discovered("order_tower_nordgrat") and pois.is_mill_unjammed("mill_auental") and pois.is_boat_searched("pier_glassee"), "MeadowPois export_state/import_state roundtrips order, mill & rowboat progress")

	print("MEADOW POIS TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
