extends Node
## Live OpenGL3 world showcase for the 6 Sonnenquarz-Öde wildlife species:
## 1) oasis_day: Oryx herd (bull, cow drinking at shore, calf, resting red oryx) + Sonnenfalke perched & soaring
## 2) quartz_midday: Agamas on QUARTZ_W outcrops & hot sand + Gold-Skarabäus rolling sand balls
## 3) dunes_dusk & dunes_night: Fennec family + desert_burrow + hopping & dust-bathing Jerboas
## Run: godot --rendering-driver opengl3 --path . res://tools/preview_desert_wildlife.tscn -- --dir=/abs/folder

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
const MAMMAL_SCENE: PackedScene = preload("res://src/entities/wildlife/woodland_mammal.tscn")
const FALCON_SCENE: PackedScene = preload("res://src/entities/wildlife/wild_meadow_bird.tscn")
const TINY_SCENE: PackedScene = preload("res://src/entities/wildlife/tiny_wildlife.tscn")
const SHELTER_SCENE: PackedScene = preload("res://src/entities/wildlife/wildlife_shelter.tscn")


func _ready() -> void:
	_run.call_deferred()


func _shot(dir: String, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, file_name])


func _spawn_mammal(pop: WoodlandPopulation, species: String, appearance: int, pos: Vector2, mood: int, facing_rad: float, elapsed_t: float = 0.35) -> WoodlandMammal:
	var m: WoodlandMammal = MAMMAL_SCENE.instantiate() as WoodlandMammal
	m.name = "Stage_%s_%d_%d" % [species, appearance, pop._residents.get_child_count()]
	m.species = species
	m.appearance = appearance
	m.position = pos
	m.home = pos
	m.ambient_event = true
	pop._residents.add_child(m)
	m.set_physics_process(false)
	m._command(mood, 8.0, facing_rad, pos, pos, elapsed_t, 1.0 if mood in [WoodlandMammal.Mood.WALK, WoodlandMammal.Mood.FLEE] else 0.0, false, 0.0, 0.0)
	m._process(0.016)
	return m


func _clear_staged(nodes: Array[Node]) -> void:
	for n: Node in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()


func _run() -> void:
	var dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
	GameCursor.visible = false
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	add_child(world)
	var hero: Player = world._players.get_child(0) as Player
	hero.visible = false
	hero.set_physics_process(false)
	hero.get_node("OpeningGuide").set_process(false)
	hero.quests.set_physics_process(false)
	var hud: CanvasLayer = world.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	for child: Node in world.get_children():
		var cl: CanvasLayer = child as CanvasLayer
		if cl != null and cl.name != "MoodGrade":
			cl.visible = false

	var cam: Camera2D = hero.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		for c: Node in hero.get_children():
			if c is Camera2D:
				cam = c as Camera2D
				break

	var woodland_pop: WoodlandPopulation = world.get_node("Wildlife/Woodland") as WoodlandPopulation
	var corvid_pop: CorvidPopulation = world.get_node("Wildlife/Corvids") as CorvidPopulation
	var tiny_pop: TinyPopulation = world.get_node("Wildlife/SmallResidents") as TinyPopulation
	woodland_pop.set_process(false)
	corvid_pop.set_process(false)
	tiny_pop.set_process(false)
	var events: WildlifeEvents = world.get_node_or_null("WildlifeEvents") as WildlifeEvents
	if events != null:
		events.set_process(false)

	TimeManager.unlock()
	TimeManager.locked = true

	# -------------------------------------------------------------------------
	# 1. OASIS DAY: Oryx herd at oasis shore & palm shade + Sonnenfalke
	# -------------------------------------------------------------------------
	TimeManager.time_of_day = 0.40
	var oasis_center: Vector2 = Vector2(708.0, 139.0) * 16.0
	hero.request_teleport(oasis_center)
	for _i: int in 75:
		await get_tree().process_frame

	# Find shoreline spot near a sun_palm at oasis_lagoon
	var shore_spot: Vector2 = oasis_center + Vector2(-180.0, 40.0)
	var water_edge: Vector2 = shore_spot + Vector2(24.0, 8.0)
	var best_palm: FirTree = null
	var palms: Array[FirTree] = []
	_collect_trees(world, "sun_palm", palms)
	for p: FirTree in palms:
		var pp: Vector2 = p.global_position
		for ang_i: int in 16:
			var probe_w: Vector2 = pp + Vector2.from_angle(float(ang_i) * TAU / 16.0) * 56.0
			if world._rivers.lake_at(probe_w):
				var mid_shore: Vector2 = pp.lerp(probe_w, 0.58)
				if not world._rivers.lake_at(mid_shore) and woodland_pop._clear(mid_shore, 10.0):
					best_palm = p
					shore_spot = mid_shore
					water_edge = pp.lerp(probe_w, 0.80)
					break
		if best_palm != null:
			break

	hero.global_position = shore_spot + Vector2(0.0, -14.0)
	if cam != null:
		cam.zoom = Vector2(1.65, 1.65)
	for _i: int in 30:
		await get_tree().process_frame

	var staged: Array[Node] = []
	var bull: WoodlandMammal = _spawn_mammal(woodland_pop, "oryx", 0, shore_spot + Vector2(-34.0, -6.0), WoodlandMammal.Mood.ALERT, PI * 0.18, 0.30)
	var cow_drink: WoodlandMammal = _spawn_mammal(woodland_pop, "oryx", 1, water_edge + Vector2(-8.0, 0.0), WoodlandMammal.Mood.FORAGE, PI * 0.08, 0.55)
	var calf: WoodlandMammal = _spawn_mammal(woodland_pop, "oryx", 3, shore_spot + Vector2(-12.0, 12.0), WoodlandMammal.Mood.WALK, -PI * 0.14, 0.25)
	var red_oryx: WoodlandMammal = _spawn_mammal(woodland_pop, "oryx", 2, (best_palm.global_position + Vector2(18.0, 10.0)) if best_palm != null else (shore_spot + Vector2(-56.0, 16.0)), WoodlandMammal.Mood.SLEEP, PI * 0.32, 0.40)
	staged.append_array([bull, cow_drink, calf, red_oryx])

	var falcon_soar: WildCorvid = FALCON_SCENE.instantiate() as WildCorvid
	falcon_soar.name = "Stage_Falcon_Soar"
	falcon_soar.species = "desert_falcon"
	falcon_soar.appearance = 0
	falcon_soar.home = shore_spot + Vector2(36.0, 26.0)
	falcon_soar.position = shore_spot + Vector2(36.0, 26.0)
	falcon_soar.ambient_event = true
	corvid_pop._birds.add_child(falcon_soar)
	falcon_soar.set_physics_process(false)
	falcon_soar._act(WildCorvid.State.FLY, 4.0, PI * 0.78, shore_spot + Vector2(52.0, 32.0), shore_spot + Vector2(-20.0, 18.0), Vector2(0.0, -18.0), 68.0, 68.0, 72.0, "", 1.2)
	falcon_soar._advance()
	falcon_soar._process(0.016)
	staged.append(falcon_soar)

	if best_palm != null:
		var falcon_perch: WildCorvid = FALCON_SCENE.instantiate() as WildCorvid
		falcon_perch.name = "Stage_Falcon_Perch"
		falcon_perch.species = "desert_falcon"
		falcon_perch.appearance = 1
		falcon_perch.home = best_palm.global_position
		falcon_perch.position = best_palm.global_position + Vector2(8.0, 0.0)
		falcon_perch.ambient_event = true
		corvid_pop._birds.add_child(falcon_perch)
		falcon_perch.set_physics_process(false)
		falcon_perch.facing = PI * 0.28
		falcon_perch._finish(best_palm.global_position + Vector2(8.0, 0.0), 74.0, String(best_palm.get_path()))
		falcon_perch._process(0.016)
		staged.append(falcon_perch)

	for _i: int in 12:
		await get_tree().process_frame
	await _shot(dir, "1_oasis_oryx_falcon")
	_clear_staged(staged)

	# -------------------------------------------------------------------------
	# 2. QUARTZ & HOT SAND MIDDAY: Agamas + Metallic Scarabs rolling balls
	# -------------------------------------------------------------------------
	TimeManager.time_of_day = 0.50
	var quartz_spot: Vector2 = Vector2(822.0, 166.0) * 16.0
	for cy_q: int in range(4, 8):
		for cx_q: int in range(22, 29):
			var probe_q: Vector2 = Vector2(cx_q * 32 + 16, cy_q * 32 + 16) * 16.0
			if BiomeBlend.arid_at(probe_q) > 0.85 and BiomeBlend.is_quartz_surface(probe_q):
				quartz_spot = probe_q
				break
		if BiomeBlend.is_quartz_surface(quartz_spot):
			break

	hero.request_teleport(quartz_spot)
	for _i: int in 75:
		await get_tree().process_frame

	# Find exact quartz patch + nearby golden sand patch inside camera view
	var q_pt: Vector2 = quartz_spot
	var sand_pt: Vector2 = quartz_spot + Vector2(44.0, 22.0)
	for r_i: int in range(1, 14):
		for s_i: int in 16:
			var cand: Vector2 = quartz_spot + Vector2.from_angle(float(s_i) * TAU / 16.0) * float(r_i) * 10.0
			if BiomeBlend.is_quartz_surface(cand) and woodland_pop._clear(cand, 8.0):
				q_pt = cand
			elif Terrain.surface_at(cand) == "sand" and not BiomeBlend.is_quartz_surface(cand) and woodland_pop._clear(cand, 8.0) and cand.distance_to(q_pt) < 88.0 and cand.distance_to(q_pt) > 26.0:
				sand_pt = cand

	hero.global_position = q_pt.lerp(sand_pt, 0.45)
	if cam != null:
		cam.zoom = Vector2(2.35, 2.35)
	for _i: int in 25:
		await get_tree().process_frame

	var ag_male: WoodlandMammal = _spawn_mammal(woodland_pop, "agama", 0, q_pt + Vector2(-12.0, -4.0), WoodlandMammal.Mood.BARK, PI * 0.12, 0.22)
	var ag_quartz: WoodlandMammal = _spawn_mammal(woodland_pop, "agama", 2, q_pt + Vector2(14.0, 2.0), WoodlandMammal.Mood.ALERT, PI - 0.18, 0.40)
	var ag_dance: WoodlandMammal = _spawn_mammal(woodland_pop, "agama", 1, sand_pt + Vector2(-8.0, 6.0), WoodlandMammal.Mood.SPECIAL, PI * 0.35, 0.18)
	var ag_young: WoodlandMammal = _spawn_mammal(woodland_pop, "agama", 3, q_pt + Vector2(2.0, 14.0), WoodlandMammal.Mood.REST, PI * 0.65, 0.30)
	staged.append_array([ag_male, ag_quartz, ag_dance, ag_young])

	for sc_idx: int in 3:
		var sc_pos: Vector2 = sand_pt + Vector2(float(sc_idx * 18 - 14), float((sc_idx % 2) * 14 - 8))
		var sc: TinyWildlife = TINY_SCENE.instantiate() as TinyWildlife
		sc.name = "Stage_Scarab_%d" % sc_idx
		sc.species = "scarab"
		sc.appearance = sc_idx
		sc.home = sc_pos
		sc.position = sc_pos
		sc.ambient_event = true
		tiny_pop._animals.add_child(sc)
		sc.set_physics_process(false)
		var end_p: Vector2 = sc_pos + Vector2(14.0 if sc_idx != 1 else -12.0, 5.0 if sc_idx == 0 else -6.0)
		sc._act(TinyWildlife.State.CRAWL, sc_pos - (end_p - sc_pos) * 0.6, end_p, 2.4, "", Vector2.ZERO, 1.1)
		sc.position = sc_pos
		sc.queue_redraw()
		staged.append(sc)

	for _i: int in 12:
		await get_tree().process_frame
	await _shot(dir, "2_quartz_agama_scarab")
	_clear_staged(staged)

	# -------------------------------------------------------------------------
	# 3. DUNES DUSK & STARRY NIGHT: Fennecs + Desert Burrow + Hopping Jerboas
	# -------------------------------------------------------------------------
	var dune_spot: Vector2 = sand_pt
	for r_d: int in range(2, 18):
		var cand_d: Vector2 = quartz_spot + Vector2(float(r_d) * 16.0, 32.0)
		if Terrain.surface_at(cand_d) == "sand" and not BiomeBlend.is_quartz_surface(cand_d) and woodland_pop._clear(cand_d, 28.0):
			dune_spot = cand_d
			break

	TimeManager.time_of_day = 0.785
	hero.global_position = dune_spot
	if cam != null:
		cam.zoom = Vector2(2.05, 2.05)
	for _i: int in 30:
		await get_tree().process_frame

	var burrow: WildlifeShelter = SHELTER_SCENE.instantiate() as WildlifeShelter
	burrow.name = "Stage_DesertBurrow"
	burrow.shelter_kind = "desert_burrow"
	burrow.position = dune_spot + Vector2(-28.0, -10.0)
	woodland_pop._residents.add_child(burrow)
	staged.append(burrow)

	var fen_listen: WoodlandMammal = _spawn_mammal(woodland_pop, "fennec", 0, dune_spot + Vector2(-14.0, 4.0), WoodlandMammal.Mood.LISTEN, PI * 0.16, 0.45)
	var fen_pounce: WoodlandMammal = _spawn_mammal(woodland_pop, "fennec", 1, dune_spot + Vector2(18.0, -8.0), WoodlandMammal.Mood.SPECIAL, PI * 0.08, 0.42)
	fen_pounce._duration = 0.85
	fen_pounce._elapsed = 0.42
	fen_pounce._process(0.016)
	var fen_kit: WoodlandMammal = _spawn_mammal(woodland_pop, "fennec", 3, dune_spot + Vector2(-36.0, 6.0), WoodlandMammal.Mood.FORAGE, PI * 0.35, 0.35)
	var jerb_hop: WoodlandMammal = _spawn_mammal(woodland_pop, "jerboa", 0, dune_spot + Vector2(46.0, 2.0), WoodlandMammal.Mood.FLEE, -PI * 0.18, 0.22)
	jerb_hop._duration = 0.45
	jerb_hop._elapsed = 0.22
	jerb_hop._process(0.016)
	var jerb_bath: WoodlandMammal = _spawn_mammal(woodland_pop, "jerboa", 1, dune_spot + Vector2(26.0, 22.0), WoodlandMammal.Mood.SPECIAL, PI * 0.75, 0.50)
	var jerb_moon: WoodlandMammal = _spawn_mammal(woodland_pop, "jerboa", 2, dune_spot + Vector2(6.0, 26.0), WoodlandMammal.Mood.GROOM, -PI * 0.65, 0.35)
	staged.append_array([fen_listen, fen_pounce, fen_kit, jerb_hop, jerb_bath, jerb_moon])

	for _i: int in 12:
		await get_tree().process_frame
	await _shot(dir, "3_dunes_dusk_fennec_jerboa")

	TimeManager.time_of_day = 0.02
	for _i: int in 25:
		await get_tree().process_frame
	await _shot(dir, "4_dunes_night_fennec_jerboa")

	_clear_staged(staged)
	print("DESERT WILDLIFE PREVIEW OK")
	get_tree().quit()


func _collect_trees(node: Node, tree_kind: String, out: Array[FirTree]) -> void:
	if node is FirTree and (node as FirTree).kind == tree_kind:
		out.append(node as FirTree)
	for c: Node in node.get_children():
		_collect_trees(c, tree_kind, out)
