extends Node
## Automated verification of the Lost-Ark-style zoned semi-open world (Milestone 1).
## Headless: godot --headless --path . res://tools/test_zones.tscn

const ZONE_WORLD_SCENE: PackedScene = preload("res://src/world/zones/zone_world.tscn")
const PLAYER_SCENE: PackedScene = preload("res://src/entities/player/player.tscn")

var _failures: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _frames(n: int) -> void:
	for _i: int in range(n):
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_catalog_and_continent()
	await _test_zone_world_runtime()
	print("ZONE WORLD TESTS ", "OK" if _failures == 0 else ("FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _test_catalog_and_continent() -> void:
	ZoneCatalog.clear_cache()
	var main: Dictionary = ZoneCatalog.main_continent()
	_check(String(main.get("id", "")) == "main", "main continent present")
	_check(bool(main.get("outer_water", false)), "main continent surrounded by water")

	var biomes: Array = main.get("biomes", []) as Array
	_check("meadow" in biomes and "witch_forest" in biomes, "main continent contains meadow & witch_forest")
	_check(not ("desert" in biomes) and not ("quartz_desert" in biomes), "no desert biome on main continent")

	var bounds: Array = main.get("start_area_bounds", []) as Array
	_check(bounds.size() == 4, "start_area_bounds has 4 coordinates")
	if bounds.size() == 4:
		var w_ratio: float = float(bounds[2]) - float(bounds[0])
		var h_ratio: float = float(bounds[3]) - float(bounds[1])
		_check(w_ratio >= 0.11 and w_ratio <= 0.15, "start area ~13%% width (got %.3f)" % w_ratio)
		_check(h_ratio >= 0.15 and h_ratio <= 0.19, "start area ~17%% height (got %.3f)" % h_ratio)
		_check(float(bounds[0]) < 0.08 and float(bounds[3]) > 0.90, "start area placed in bottom-left")

	var witch_poly: Array = main.get("witch_forest_poly", []) as Array
	_check(witch_poly.size() >= 5, "witch_forest polygon defined")
	if not witch_poly.is_empty():
		var cx: float = 0.0
		var cy: float = 0.0
		for pt_v: Variant in witch_poly:
			var pt: Array = pt_v as Array
			cx += float(pt[0])
			cy += float(pt[1])
		cx /= float(witch_poly.size())
		cy /= float(witch_poly.size())
		_check(cx > 0.70 and cy < 0.35, "witch_forest placed in top-right (%.2f, %.2f)" % [cx, cy])

	var void_edges: Array = main.get("void_edges", []) as Array
	var harbors: Array = main.get("harbors", []) as Array
	_check(void_edges.size() >= 2 and harbors.size() >= 2, "void edges and harbors configured")

	var playable: Array[String] = ZoneCatalog.playable_zone_ids("main")
	_check(playable.size() == 2 and ("start_path" in playable) and ("home_valley" in playable), "only start_path & home_valley unlocked in Milestone 1")

	var summaries: Array[Dictionary] = ZoneCatalog.zone_summaries("main")
	_check(summaries.size() >= 11, "11 province summaries on main continent")
	for z: Dictionary in summaries:
		_check(String(z.get("biome", "")) != "desert", "no desert zone on main continent (%s)" % String(z.get("id", "")))

	var desert_cont: Dictionary = ZoneCatalog.continent("quartz_desert")
	_check(not desert_cont.is_empty() and not bool(desert_cont.get("unlocked", true)), "overseas quartz_desert defined as locked future continent")

	_check(ZoneCatalog.slot_origin_px("start_path") == Vector2.ZERO, "start_path occupies slot 0 at (0,0)")
	_check(ZoneCatalog.slot_origin_px("home_valley") == Vector2(8192.0, 0.0), "home_valley occupies slot 1 at (8192,0)")
	_check(ZoneCatalog.zone_id_at(Vector2(200.0, 200.0)) == "start_path", "zone_id_at resolves start_path")
	_check(ZoneCatalog.zone_id_at(Vector2(8500.0, 200.0)) == "home_valley", "zone_id_at resolves home_valley")

	## Seamless 100% organic continent partition check (no unassigned gaps)
	var layout: Dictionary = ZoneCatalog.continent_layout("main")
	var land_cells: int = int(layout.get("land_cells", 0))
	var areas: Dictionary = layout.get("zone_areas", {}) as Dictionary
	var sum_zone_cells: int = 0
	for z: Dictionary in summaries:
		var zid: String = String(z.get("id", ""))
		var area_z: int = int(areas.get(zid, 0))
		_check(area_z >= 40, "organic province %s covers landmass (cells=%d)" % [zid, area_z])
		sum_zone_cells += area_z
	_check(land_cells > 5000 and sum_zone_cells == land_cells, "100%% of organic continent landmass partitioned across zones (%d/%d)" % [sum_zone_cells, land_cells])

	## Non-blocky organic zone corner rounding check
	var hv_shape: Dictionary = ZoneBuilder.compute_zone_shape(ZoneCatalog.zone_spec("home_valley"))
	var hv_w: int = int(hv_shape["w"])
	var hv_walk: PackedByteArray = hv_shape["walkable"] as PackedByteArray
	_check(hv_walk[10 * hv_w + 10] == 0, "home_valley outer corner carved organically by woodland border")


func _test_zone_world_runtime() -> void:
	var world: ZoneWorld = ZONE_WORLD_SCENE.instantiate() as ZoneWorld
	add_child(world)
	await _frames(4)

	_check(world.is_in_group("story_world") and world.is_in_group("zone_world"), "ZoneWorld registers in story_world & zone_world groups")
	_check(world.active_zones().has("start_path"), "start_path built on startup")
	_check(not world.active_zones().has("home_valley"), "home_valley stays unloaded until entered")
	_check(not world.raids_allowed(), "raids disabled while nobody is in home_valley")

	var sp_zone: ZoneInstance = world.active_zones().get("start_path") as ZoneInstance
	_check(sp_zone != null and sp_zone.cover_node != null and sp_zone.fallen_knight != null, "start_path spawns manhole & FallenKnight")
	_check(sp_zone != null and sp_zone.decals.size() >= 2, "start_path places baked decals")
	_check(sp_zone != null and sp_zone.enemies.size() >= 2, "start_path spawns guard spiders")

	var has_signpost: bool = false
	if sp_zone != null:
		for n: Node in sp_zone.poi_nodes:
			if n is Signpost:
				has_signpost = true
				break
	_check(has_signpost, "start_path spawns Signpost")

	var q_start: Vector2i = world.resolve_quest_tile(Vector2i(463, 616))
	var q_home: Vector2i = world.resolve_quest_tile(Vector2i(786, 676))
	_check(ZoneCatalog.zone_id_at(Vector2(q_start) * 16.0) == "start_path", "resolve_quest_tile maps opening quest tile into start_path")
	_check(ZoneCatalog.zone_id_at(Vector2(q_home) * 16.0) == "home_valley", "resolve_quest_tile maps town/hut quest tile into home_valley")

	var p1: Player = world._players.get_child(0) as Player
	_check(p1 != null, "local player 1 spawned")
	if p1 == null:
		return

	## Locked south gate must reject portal travel
	var locked_portal: ZonePortal = sp_zone.portals.get("to_south_blocked") as ZonePortal
	_check(locked_portal != null and locked_portal.locked, "start_path south gate exists and is locked")
	if locked_portal != null:
		p1.request_teleport(locked_portal.global_position)
		await _frames(2)
		world.request_portal_travel("start_path", "to_south_blocked", p1)
		await _frames(2)
		_check(world.player_zone(p1.name.to_int()) == "start_path", "locked gate blocks zone transition")

	## Walk/request portal to home_valley
	var to_home: ZonePortal = sp_zone.portals.get("to_home_valley") as ZonePortal
	_check(to_home != null and not to_home.locked and to_home.trigger_mode == "walk", "start_path -> home_valley portal is open walk trigger")
	if to_home != null:
		world._portal_cooldown_until.clear()
		p1.request_teleport(to_home.global_position)
		await _frames(2)
		world.request_portal_travel("start_path", "to_home_valley", p1)
		await _frames(3)
		_check(world.player_zone(p1.name.to_int()) == "home_valley", "portal transition moves P1 to home_valley")
		_check(world.active_zones().has("home_valley"), "home_valley dynamically loaded on arrival")
		_check(not world.active_zones().has("start_path"), "empty start_path unloads dynamically after P1 leaves")
		_check(world.discovered_zones().has("home_valley"), "home_valley marked discovered")
		_check(world.raids_allowed(), "raids enabled while P1 occupies home_valley")

	var hv_zone: ZoneInstance = world.active_zones().get("home_valley") as ZoneInstance
	_check(hv_zone != null and hv_zone.hut_node != null, "home_valley spawns Valdric's hut")
	_check(hv_zone != null and hv_zone.waystone_ids.has("home_valley_stone"), "home_valley registers waystone")

	## Water & TownManager probe checks in home_valley
	var pond_global_tile: Vector2i = hv_zone.slot_origin_tile + Vector2i(130, 108)
	var pond_pos: Vector2 = Vector2(pond_global_tile) * 16.0 + Vector2(8.0, 8.0)
	_check(world.water_depth(pond_pos) > 0.0, "southeastern pond reports positive water depth")
	_check(world.town_probe(Rect2(pond_pos - Vector2(8, 8), Vector2(16, 16))) != "", "town_probe blocks building inside water pond")

	world.opening_over = true
	p1.quests.set_flag("rebuild_done")
	var hut: Hut = world.hut_node()
	var build_pos: Vector2 = hut.position + Vector2(-96.0, 48.0)
	var found_clear: bool = false
	for dx: int in [-96, -80, -64, 64, 80, 96]:
		for dy: int in [-48, 48, 64]:
			var test_pt: Vector2 = hut.position + Vector2(float(dx), float(dy))
			if world.town_probe(Rect2(test_pt - Vector2(12, 12), Vector2(24, 24))) == "":
				build_pos = test_pt
				found_clear = true
				break
		if found_clear:
			break
	_check(found_clear, "town_probe finds buildable flat meadow land around Valdric's hut (near %s)" % str(build_pos))

	## Return portal home_valley -> start_path
	var to_start: ZonePortal = hv_zone.portals.get("to_start_path") as ZonePortal
	_check(to_start != null and not to_start.locked, "home_valley -> start_path return portal open")
	if to_start != null:
		world._portal_cooldown_until.clear()
		p1.request_teleport(to_start.global_position)
		await _frames(2)
		world.request_portal_travel("home_valley", "to_start_path", p1)
		await _frames(3)
		_check(world.player_zone(p1.name.to_int()) == "start_path", "return portal moves P1 back to start_path")
		_check(world.active_zones().has("start_path") and not world.active_zones().has("home_valley"), "home_valley unloads when P1 returns to start_path")
		_check(not world.raids_allowed(), "raids disabled again when home_valley is empty")

	## Co-op Option B: P1 in start_path + P2 in home_valley simultaneously
	var p2: Player = PLAYER_SCENE.instantiate() as Player
	p2.name = "2"
	world._players.add_child(p2)
	await _frames(2)
	world.travel_to_zone(2, "home_valley", "respawn", true)
	await _frames(3)
	_check(world.active_zones().has("start_path") and world.active_zones().has("home_valley"), "Option B co-op keeps P1 start_path and P2 home_valley active simultaneously")
	_check(world.raids_allowed(), "raids allowed when co-op peer P2 is in home_valley even if P1 is in start_path")

	## P1 joins P2 in home_valley -> start_path unloads cleanly
	world.travel_to_zone(p1.name.to_int(), "home_valley", "respawn", true)
	await _frames(3)
	world.unload_unused_zones()
	if world.active_zones().has("start_path"):
		print("DEBUG active_zones=", world.active_zones().keys(), " player_zones=", world.players_in_zones(), " p1=", p1.global_position, " p2=", p2.global_position)
	_check(not world.active_zones().has("start_path") and world.active_zones().has("home_valley"), "start_path unloads when both P1 and P2 occupy home_valley")

	## Clean up P2 and verify save state export/import roundtrip + SaveGame path isolation
	p2.queue_free()
	world._player_zones.erase(2)
	await _frames(2)
	world.travel_to_zone(p1.name.to_int(), "start_path", "default", true)
	await _frames(2)
	var exported_z: Dictionary = world.export_zone_state()
	world.import_zone_state(exported_z)
	_check(world.discovered_zones().has("home_valley"), "zone state export/import preserves discovered zones")
	_check(SaveGame.is_zones_world(get_tree()), "SaveGame detects ZoneWorld active in tree")
	_check(SaveGame.path_for(get_tree()) == SaveGame.ZONES_PATH, "SaveGame routes ZoneWorld to separate user://save_zones.json")
	_check(SaveGame.path_for(get_tree()) != SaveGame.PATH, "ZoneWorld save path stays isolated from open-world save.json")

	## Verify MapWindow detects ZoneWorld and switches Tier 1 <-> Tier 2 cleanly
	var ui_layer: CanvasLayer = CanvasLayer.new()
	add_child(ui_layer)
	var map_win: MapWindow = MapWindow.new()
	ui_layer.add_child(map_win)
	map_win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_win._set_open(true)
	await _frames(2)
	map_win.set_zone_map_mode("continent")
	await _frames(1)
	_check(map_win._zone_view != null and map_win._zone_view.mode == "continent", "MapWindow switches to Tier 2 Continent mode")
	map_win.set_zone_map_mode("zone", "home_valley")
	await _frames(1)
	_check(map_win._zone_view != null and map_win._zone_view.mode == "zone" and map_win._zone_view.inspected_zone_id == "home_valley", "MapWindow switches to Tier 1 inspected Zone mode")
	ui_layer.queue_free()

	## Verify respawn rule after opening_over = true
	world.opening_over = true
	world._player_zones[p1.name.to_int()] = "start_path"
	var respawn_pos: Vector2 = world.respawn_point_for(p1.name.to_int())
	_check(ZoneCatalog.zone_id_at(respawn_pos) == "home_valley", "respawn_point_for resolves into home_valley after opening_over")
	p1.health.current = 0.0
	p1._respawn_after_delay()
	await _frames(30)
	p1.request_respawn()
	await _frames(60)
	_check(world.player_zone(p1.name.to_int()) == "home_valley", "death after opening_over respawns player into home_valley (zone=%s, pos=%s)" % [world.player_zone(p1.name.to_int()), str(p1.global_position)])
	_check(ZoneCatalog.zone_id_at(p1.global_position) == "home_valley", "player physically relocated to home_valley on respawn")
