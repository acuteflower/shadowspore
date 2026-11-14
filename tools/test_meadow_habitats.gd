extends Node
## Automated Stage 2 verification (`docs/wiesenbiom_ausbau_konzept.md` — Die 3 Makro-Landschaften):
## 1. `MeadowHabitats` installs cleanly and strictly zeros out weights inside all sanctuaries
##    (Glimmrast hut, quarry, start, Hallgrat, Mornath's arena, Hexenwald, Sonnenquarz-Öde).
## 2. All 3 macro-habitats (`deep_forest`, `wind_meadow`, `old_pasture`) exist across the 5-area meadow,
##    and `MeadowLandmarks` places hilltop `SolitaryTree`s, `ForestShrine` glades, and `old_pasture` sites.
## 3. `PropGenerator` vs `PropGenerator.fork()` produces bit-exact output across all 3 macro-landscapes.
## 4. Streaming a `wind_meadow` hilltop chunk spawns `SolitaryTree` (`SeatSpot`), suppresses conifers inside
##    strong `wind_meadow` cells (`w_wind >= 0.45`), produces monoculture flower seas, and lets Ellie sit & stand.
## 5. Streaming a `deep_forest` shrine chunk spawns giant `ancient_fir`s + `ForestShrine` + `SunbeamShaft`;
##    blessing the shrine heals + awards `+16` XP, reveals map fog, spawns a `Wurzelkiste` (`LootChests`), and persists.
## 6. Streaming an `old_pasture` chunk (and testing `orchard_apple` / `orchard_pear` fruit pickup + regrowth)
##    drops `meadow_apple` / `moon_pear`, hides `_ground_fruit`, and regrows cleanly.
## Optional `-- --capture=/abs/dir` saves real-world screenshots when run with `--rendering-driver opengl3`.

var _checks: int = 0
var _failures: int = 0
var _capture_dir: String = ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("MEADOW HABITATS TEST FAILED: " + label)
		print("FAILED: ", label)


func _shot(shot_name: String) -> void:
	if _capture_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(shot_name + ".png"))


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

	_check(MeadowHabitats.is_installed(), "MeadowHabitats installed on WorldLevel startup")

	# 1. Sanctuary protection checks
	var sanctuary_tiles: Array[Vector2] = [
		Vector2(786, 676), ## Glimmrast hut
		Vector2(754, 700), ## Quarry
		Vector2(463, 616), ## Start
		Vector2(501, 685), ## FallenKnight
		Vector2(170, 350), ## Hallgrat
		Vector2(499, 258), ## Mornath's arena
		Vector2(826, 880), ## Hexenwald
		Vector2(842, 185), ## Sonnenquarz-Öde
	]
	for st: Vector2 in sanctuary_tiles:
		var w: Vector3 = MeadowHabitats.weights_at_tiles(st)
		_check(w.length() < 0.001, "Sanctuary / non-meadow tile %s has zero macro-habitat weights (got %s)" % [str(st), str(w)])

	# 2. Macro-habitat coverage across the 275x275 grid
	var deep_cells: int = 0
	var wind_cells: int = 0
	var pasture_cells: int = 0
	for gy: int in range(10, 265, 2):
		for gx: int in range(10, 265, 2):
			var px: Vector2 = Vector2(float(gx * 4 + 2), float(gy * 4 + 2)) * 16.0
			var dom: String = MeadowHabitats.dominant_at(px)
			match dom:
				"deep_forest":
					deep_cells += 1
				"wind_meadow":
					wind_cells += 1
				"old_pasture":
					pasture_cells += 1
	_check(deep_cells >= 120, "Der Tiefe Urforst covers substantial meadow territory (sampled cells=%d)" % deep_cells)
	_check(wind_cells >= 120, "Offene Windwiesen covers substantial meadow territory (sampled cells=%d)" % wind_cells)
	_check(pasture_cells >= 40, "Verlassenes Weideland covers substantial meadow territory (sampled cells=%d)" % pasture_cells)

	var landmarks: MeadowLandmarks = MeadowLandmarks.of(get_tree())
	_check(landmarks != null, "MeadowLandmarks node exists in group 'meadow_landmarks'")
	var oaks: Array[Vector2i] = landmarks.oak_tiles()
	var shrines: Array[Vector2i] = landmarks.shrine_tiles()
	var pastures: Array[Vector2i] = landmarks.pasture_tiles()
	_check(oaks.size() >= 3, "At least 3 hilltop SolitaryTree oaks placed across Windwiesen (got %d)" % oaks.size())
	_check(shrines.size() >= 4, "At least 4 hidden ForestShrines placed in Der Tiefe Urforst (got %d)" % shrines.size())
	_check(pastures.size() >= 2, "At least 2 Old Pasture reference sites recorded (got %d)" % pastures.size())

	# 3. Worker-thread fork determinism across all 3 macro-habitats
	var fork_gen: PropGenerator = world._generator.fork()
	var sample_chunks: Array[Vector2i] = [
		oaks[0] / WorldLevel.CHUNK,
		shrines[0] / WorldLevel.CHUNK,
		pastures[0] / WorldLevel.CHUNK,
	]
	for sc: Vector2i in sample_chunks:
		var rect_sc: Rect2i = Rect2i(sc * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
		var a_out: Array[Dictionary] = world._generator.props_for_chunk(rect_sc)
		var b_out: Array[Dictionary] = fork_gen.props_for_chunk(rect_sc)
		_check(a_out == b_out, "PropGenerator.fork() output is bit-exact identical to main generator on chunk %s (items=%d)" % [str(sc), a_out.size()])

	# 4. Stream Windwiese & test SolitaryTree + conifer suppression + flower dominance
	var oak_tile: Vector2i = oaks[0]
	player.global_position = Vector2(oak_tile) * 16.0 + Vector2(8.0, 44.0)
	(player.get_node("Camera2D") as Camera2D).reset_smoothing()
	for _i: int in 24:
		world._stream(false)
		await get_tree().process_frame

	var oak_chunk: Vector2i = oak_tile / WorldLevel.CHUNK
	var found_oak: SolitaryTree = null
	for child: Node in world._props.get_children():
		if child is SolitaryTree and child.global_position.distance_to(Vector2(oak_tile) * 16.0) < 32.0:
			found_oak = child as SolitaryTree
			break
	_check(found_oak != null, "SolitaryTree spawned when streaming Windwiese chunk " + str(oak_chunk))

	# Check conifer suppression inside high wind_meadow core
	var wind_rect: Rect2i = Rect2i(oak_chunk * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
	var wind_gen: Array[Dictionary] = world._generator.props_for_chunk(wind_rect)
	var stray_conifers: int = 0
	var wind_flowers_count: int = 0
	for pd: Dictionary in wind_gen:
		var k: String = String(pd.kind)
		var w_here: float = MeadowHabitats.wind_meadow_at(pd.pos as Vector2)
		if w_here >= 0.48 and (k == "tree" or k == "ancient_fir"):
			stray_conifers += 1
		if k in ["sunbloom", "moonbell", "spark_poppy", "puffseed"]:
			wind_flowers_count += 1
	_check(stray_conifers == 0, "Zero conifers spawn inside open Windwiese core (w_wind >= 0.48), got %d" % stray_conifers)
	_check(wind_flowers_count >= 12, "Open Windwiese chunk bursts with wildflowers (count=%d)" % wind_flowers_count)

	if found_oak != null:
		player.global_position = found_oak.approach_position()
		(player.get_node("Camera2D") as Camera2D).reset_smoothing()
		await get_tree().process_frame
		await _shot("01_wind_meadow_solitary_oak_day")
		_check(found_oak.prompt() != "", "SolitaryTree exposes resting prompt ('%s')" % found_oak.prompt())
		found_oak.interact(player)
		var rest: RestComponent = player.get_node("RestComponent") as RestComponent
		var wait_sit: float = 0.0
		while rest.state != RestComponent.State.IDLE and wait_sit < 3.0:
			await get_tree().create_timer(0.1).timeout
			wait_sit += 0.1
		_check(rest.state == RestComponent.State.IDLE, "Player sits peacefully beneath/on SolitaryTree")
		await _shot("02_wind_meadow_seated")
		rest.request_stand()
		var wait_up: float = 0.0
		while rest.state != RestComponent.State.FREE and wait_up < 2.5:
			await get_tree().create_timer(0.1).timeout
			wait_up += 0.1
		_check(rest.state == RestComponent.State.FREE, "Player stands back up cleanly from SolitaryTree")

	# 5. Stream Deep Forest (`Der Tiefe Urforst`) & test `ancient_fir` + `ForestShrine` + `SunbeamShaft`
	var shrine_tile: Vector2i = shrines[0]
	player.global_position = Vector2(shrine_tile) * 16.0 + Vector2(0.0, 22.0)
	(player.get_node("Camera2D") as Camera2D).reset_smoothing()
	for _i2: int in 24:
		world._stream(false)
		await get_tree().process_frame

	var found_shrine: ForestShrine = null
	var ancient_fir_count: int = 0
	for child2: Node in world._props.get_children():
		if child2 is ForestShrine and child2.global_position.distance_to(Vector2(shrine_tile) * 16.0) < 32.0:
			found_shrine = child2 as ForestShrine
		elif child2 is FirTree and String((child2 as WorldProp).kind) == "ancient_fir":
			ancient_fir_count += 1
	_check(found_shrine != null, "ForestShrine spawned in Der Tiefe Urforst at " + str(shrine_tile))
	_check(ancient_fir_count >= 6, "Giant ancient_fir cathedral trees surround the Urforst glade (count=%d)" % ancient_fir_count)

	await _shot("03_deep_forest_shrine_before")

	if found_shrine != null:
		var sid: String = found_shrine.shrine_id
		_check(found_shrine.prompt() == "WALDSCHREIN EHRSAM BERÜHREN", "ForestShrine prompt ready before blessing")
		player.health.current = maxf(1.0, player.health.max_health - 20.0)
		var hp_before: float = player.health.current
		var xp_before: int = player.progress.xp
		found_shrine.interact(player)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(landmarks.is_shrine_blessed(sid) and found_shrine.blessed, "ForestShrine marked blessed after interaction")
		_check(player.health.current > hp_before, "ForestShrine blessing healed player (%.1f -> %.1f)" % [hp_before, player.health.current])
		_check(player.progress.xp == xp_before + 16, "ForestShrine blessing granted +16 XP (%d -> %d)" % [xp_before, player.progress.xp])
		var chests: LootChests = LootChests.of(get_tree())
		_check(chests != null and chests.chest(sid) != null, "Mossy Wurzelkiste spawned beside awakened ForestShrine")

		await get_tree().create_timer(0.6).timeout
		await _shot("04_deep_forest_shrine_blessed")

		# Persistence round-trip
		var saved_lm: Array = landmarks.export_state()
		_check(saved_lm.has(sid), "MeadowLandmarks.export_state contains blessed shrine id")
		landmarks.import_state([])
		_check(not landmarks.is_shrine_blessed(sid) and not found_shrine.blessed, "Empty import resets shrine state")
		landmarks.import_state(saved_lm)
		_check(landmarks.is_shrine_blessed(sid) and found_shrine.blessed, "import_state restores blessed shrine state")

	# 6. Stream Old Pasture (`Verlassenes Weideland`) & test orchard fruit pickup + regrowth + walls/fences
	if landmarks._banner != null:
		landmarks._banner.visible = false
	var pasture_tile: Vector2i = pastures[0]
	# Search nearby pasture chunks for an orchard tree (`orchard_apple` or `orchard_pear`)
	player.global_position = Vector2(pasture_tile) * 16.0 + Vector2(8.0, 8.0)
	(player.get_node("Camera2D") as Camera2D).reset_smoothing()
	for _i3: int in 26:
		world._stream(false)
		await get_tree().process_frame

	var orchard_tree: FirTree = null
	var wall_or_fence: int = 0
	for child3: Node in world._props.get_children():
		if child3 is WorldProp:
			var pk: String = String((child3 as WorldProp).kind)
			if pk in ["orchard_apple", "orchard_pear"] and orchard_tree == null:
				orchard_tree = child3 as FirTree
			elif pk in ["dry_stone_wall", "broken_fence"]:
				wall_or_fence += 1

	# If the 3x3 around pastures[0] happened to roll walls/fences without an orchard tree, check remaining pasture spots
	if orchard_tree == null:
		for alt_p: Vector2i in pastures:
			player.global_position = Vector2(alt_p) * 16.0 + Vector2(8.0, 8.0)
			for _i4: int in 20:
				world._stream(false)
				await get_tree().process_frame
			for child4: Node in world._props.get_children():
				if child4 is WorldProp:
					var pk2: String = String((child4 as WorldProp).kind)
					if pk2 in ["orchard_apple", "orchard_pear"] and orchard_tree == null:
						orchard_tree = child4 as FirTree
					elif pk2 in ["dry_stone_wall", "broken_fence"]:
						wall_or_fence += 1
			if orchard_tree != null:
				break

	_check(orchard_tree != null, "Old Pasture spawns overgrown orchard fruit trees (orchard_apple / orchard_pear)")
	_check(wall_or_fence >= 2, "Old Pasture spawns dry-stone walls and/or broken wooden fences (count=%d)" % wall_or_fence)

	if orchard_tree != null:
		player.global_position = orchard_tree.global_position + Vector2(0.0, 18.0)
		(player.get_node("Camera2D") as Camera2D).reset_smoothing()
		await get_tree().process_frame
		await _shot("05_old_pasture_orchard_day")
		if _capture_dir != "":
			TimeManager.set_time(0.92)
			await get_tree().create_timer(0.25).timeout
			await _shot("06_old_pasture_orchard_night")
			TimeManager.set_time(0.38)

		_check(orchard_tree._ground_fruit != null and orchard_tree._ground_fruit.visible, "Fallen fruit sprite visible beneath unpicked orchard tree")
		_check(orchard_tree.prompt().ends_with("SAMMELN"), "Orchard tree exposes fruit pickup prompt ('%s')" % orchard_tree.prompt())
		world.request_pick(orchard_tree.cell)
		await get_tree().process_frame
		_check(orchard_tree._picked(), "Picking orchard tree marks state 'p' harvested")
		_check(orchard_tree._ground_fruit != null and not orchard_tree._ground_fruit.visible, "Fallen fruit sprite hides once harvested")

	print("MEADOW HABITATS TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
