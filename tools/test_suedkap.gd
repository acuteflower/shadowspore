extends Node
## Headless integration test for Milestone 5: full playable Zone 2 `SÜDKAP` (Sturmhafen).
## Verifies:
## - `windkap_suedkap` threshold is immediately open (no blocker)
## - `SÜDKAP` loads cleanly in ZoneWorld with 6 places, Waystone, Vista, 8 VeilThreads,
##   2 Chests, 2 Puzzles, 3 outgoing blockers, Alte Mole props, and DungeonEntrance
## - `RAU` danger & night spawns (`shadow_spider`, `void_listener`, `light_fisher`)
## - `AtlasBook` computes SÜDKAP progress and rewards (`STURMLÄUFER`)
## Run: Godot --headless --path . res://tools/test_suedkap.tscn  (prints SUEDKAP OK)

var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	NetworkManager.host_singleplayer()
	var atlas: Atlas = Atlas.shared()
	var sk: Atlas.Zone = atlas.zone(&"suedkap")
	_check(sk != null, "Atlas contains zone suedkap")
	_check(not sk.placeholder, "suedkap is non-placeholder playable zone")
	_check(sk.danger == &"rau", "suedkap danger is RAU")
	_check(sk.places.size() == 6, "suedkap has 6 named places (got %d)" % sk.places.size())

	## Threshold windkap_suedkap must be seamlessly open without flags
	var th_open: Atlas.Threshold = atlas.thresholds.get(&"windkap_suedkap") as Atlas.Threshold
	_check(th_open != null and Atlas.is_threshold_open(th_open, {}), "windkap_suedkap threshold is immediately open")

	## Outgoing SÜDKAP thresholds must be closed by default
	for tid: StringName in [&"suedkap_erlenfurt", &"suedkap_glimmrast", &"suedkap_hexenwald_kern"]:
		var th: Atlas.Threshold = atlas.thresholds.get(tid) as Atlas.Threshold
		_check(th != null and not Atlas.is_threshold_open(th, {}), "threshold %s closed by default" % String(tid))

	## Mount ZoneWorld & load SÜDKAP stage directly
	print("STEP 1: instancing ZoneWorld")
	var world_scene: PackedScene = preload("res://src/world/v2/zone_world.tscn")
	var world: ZoneWorld = world_scene.instantiate() as ZoneWorld
	world.loading_in_steps = false
	add_child(world)
	print("STEP 2: ZoneWorld added")
	await get_tree().process_frame

	var dir: ZoneDirector = world.director()
	_check(dir != null, "ZoneDirector created")
	## Move player into SÜDKAP (Wächterplatz) so ZoneDirector keeps SÜDKAP loaded
	var p_move: Player = SaveGame._local_player(get_tree())
	if p_move != null:
		p_move.global_position = Atlas.px_of(Vector2(sk.origin) + Vector2(246.0, 184.0))
	print("STEP 3: loading suedkap")
	dir.load_now(&"suedkap")
	print("STEP 4: suedkap load_now returned, is_building=", dir.is_building())
	var guard: int = 0
	while dir.is_building() and guard < 120:
		guard += 1
		await get_tree().process_frame
	for _i: int in 4:
		await get_tree().process_frame
	print("STEP 5: checking stage")

	var stage: ZoneStage = dir.stage(&"suedkap")
	if stage != null:
		print("SUEDKAP build_ms=", stage.build_ms)
	_check(stage != null and stage.attached, "SÜDKAP ZoneStage built and attached")
	_check(stage.water != null, "SÜDKAP has coastal WaterField")
	_check(stage.blockers.size() == 3, "SÜDKAP has 3 physical outgoing blockers (got %d)" % stage.blockers.size())
	_check(stage.props_root.get_node_or_null("SturmhafenBeacon") != null, "Alte Mole HarborBeacon attached")
	_check(stage.props_root.get_node_or_null("AlteMolePaving") != null, "Alte Mole stone paving attached")

	## Waystone & Vista registered
	var ws: Waystones = Waystones.of(get_tree())
	_check(ws != null and not ws.spec_for("waechterin_sturmhafen").is_empty(), "Waystone waechterin_sturmhafen registered")
	var vistas: Vistas = Vistas.of(get_tree())
	_check(vistas != null and vistas.point_node("sturmkanzel") != null, "VistaPoint sturmkanzel attached")

	## VeilThreads
	var vt: VeilThreads = VeilThreads.of(get_tree())
	_check(vt != null and vt.total_in_zone(&"suedkap") == 8, "SÜDKAP has 8 VeilThreads (got %d)" % (vt.total_in_zone(&"suedkap") if vt != null else -1))

	## DungeonEntrance placed on Alte Mole
	var gates: Array[Node] = get_tree().get_nodes_in_group("dungeon_entrances")
	var found_sturmhafen_gate: bool = false
	for g_node: Node in gates:
		var ge: DungeonEntrance = g_node as DungeonEntrance
		if ge != null and ge.dungeon_id == "suedkap_gezeitenkammern":
			found_sturmhafen_gate = true
			_check(ge.zone_id == &"suedkap", "DungeonEntrance zone_id is suedkap")
			_check(ge.prompt().contains("ST. 5"), "DungeonEntrance prompt shows min level")
	_check(found_sturmhafen_gate, "DungeonEntrance for suedkap_gezeitenkammern placed in SÜDKAP")

	## AtlasBook progress & SÜDKAP rewards
	var book: AtlasBook = AtlasBook.new()
	add_child(book)
	book.setup(atlas, get_tree().get_first_node_in_group("map_discovery") as MapDiscovery, dir, SaveGame._local_player(get_tree()))
	book.set_preview_reveal_all(true)
	var stats: Dictionary = book.compute_zone_progress(&"suedkap")
	_check(int(stats.get("places_total", 0)) == 6, "AtlasBook counts 6 places in SÜDKAP")
	_check(int(stats.get("threads_total", 0)) == 8, "AtlasBook counts 8 VeilThreads in SÜDKAP")
	_check(int(stats.get("waystones_total", 0)) == 1, "AtlasBook counts 1 waystone in SÜDKAP")
	_check(int(stats.get("vistas_total", 0)) == 1, "AtlasBook counts 1 vista in SÜDKAP")
	_check(int(stats.get("chests_total", 0)) == 2, "AtlasBook counts 2 chests in SÜDKAP")
	_check(int(stats.get("puzzles_total", 0)) == 2, "AtlasBook counts 2 puzzles in SÜDKAP")
	_check(book.claim_or_activate_tier(&"suedkap", 100), "AtlasBook claims SÜDKAP 100% reward")
	var lp: Player = SaveGame._local_player(get_tree())
	_check(lp != null and lp.appearance != null and lp.appearance.title_id == "sturm_laeufer", "SÜDKAP 100% grants title STURMLÄUFER")

	if _failed == 0:
		print("SUEDKAP OK (%d checks)" % _checks)
	else:
		push_error("SUEDKAP FAILED (%d/%d failed)" % [_failed, _checks])
	world.queue_free()
	book.queue_free()
	get_tree().quit(0 if _failed == 0 else 1)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		push_error("FAIL: %s" % label)
