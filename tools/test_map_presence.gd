extends Node
## Real world actors, discovery and M-map, offline with no save access.
## Godot --headless --path . tools/test_map_presence.tscn
## Native preview: --rendering-method gl_compatibility ... -- --capture=/abs/map.png [--night] [--river]

var _ok: bool = true
var _checks: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_ok = false
		push_error("MAP PRESENCE: " + message)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _marker(map: MapWindow, id: String) -> Dictionary:
	for marker: Dictionary in map._live_markers():
		if String(marker.id) == id:
			return marker
	return {}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	TimeManager.set_process(false)
	TimeManager.time_of_day = 0.5
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(3)
	var player: Player = world._players.get_child(0) as Player
	player.set_physics_process(false)
	var map: MapWindow = player.get_node("Hud/MapWindow") as MapWindow
	map._load_data()
	var discovery: MapDiscovery = map._discovery
	discovery.set_process(false)
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(MapDiscovery.GRID * MapDiscovery.GRID)
	seen.fill(1)
	discovery.import_data(seen.compress(FileAccess.COMPRESSION_ZSTD))
	_check(_marker(map, "valdric").is_empty(), "Valdric's identity and location stay hidden before meeting him")
	player.quests.set_flag("knows_adventurer")
	world.place_knight("door")
	_check(not _marker(map, "valdric").is_empty(), "known Valdric appears")
	var knight: Adventurer = (world.get_node("Quarry_quarry") as Quarry).knight
	knight.global_position += Vector2(32, 16)
	_check((_marker(map, "valdric").tile as Vector2).is_equal_approx(knight.global_position / 16.0), "Valdric follows the reparented moving actor live")
	knight.visible = false
	_check(_marker(map, "valdric").is_empty(), "a hidden cutscene actor leaves no ghost marker")
	knight.visible = true
	var town: TownManager = world.town()
	town._host_found()
	_check(_marker(map, "gustav").is_empty(), "Gustav is absent before arrival")
	town._rpc_resident("gustav", {"trust": 0, "talked": -1}, true)
	var gustav: Settler = town._settlers["gustav"] as Settler
	gustav.set_process(false)
	_check(not _marker(map, "gustav").is_empty(), "arriving resident is visible on the map")
	gustav.global_position += Vector2(80, 32)
	_check((_marker(map, "gustav").tile as Vector2).is_equal_approx(gustav.global_position / 16.0), "Gustav's walking position updates live")
	gustav.visible = false
	var resting: Dictionary = _marker(map, "gustav")
	_check(bool(resting.resting) and (resting.tile as Vector2).is_equal_approx(gustav.home_position() / 16.0), "sleeping Gustav rests at his home marker")
	gustav.visible = true
	seen.fill(0)
	discovery.import_data(seen.compress(FileAccess.COMPRESSION_ZSTD))
	_check(_marker(map, "gustav").is_empty() and _marker(map, "valdric").is_empty(), "NPC markers respect undiscovered terrain")
	_check(not _marker(map, str(player.name)).is_empty(), "the player remains visible over fog")
	seen.fill(1)
	discovery.import_data(seen.compress(FileAccess.COMPRESSION_ZSTD))
	world._spawn_player(20)
	world._spawn_player(30)
	var peer: Player = world._players.get_node("20") as Player
	var peer_two: Player = world._players.get_node("30") as Player
	peer.set_physics_process(false)
	peer_two.set_physics_process(false)
	peer.global_position = town.center + Vector2(110, 100)
	peer_two.global_position = town.center + Vector2(-120, 40)
	var tone: Color = _marker(map, "30").tone
	_check((_marker(map, "20").tile as Vector2).is_equal_approx(peer.global_position / 16.0), "new peer joins the map immediately")
	peer.global_position += Vector2(96, 64)
	_check((_marker(map, "20").tile as Vector2).is_equal_approx(peer.global_position / 16.0), "peer movement is live")
	peer.free()
	_check(_marker(map, "20").is_empty(), "disconnected peer leaves no marker")
	_check((_marker(map, "30").tone as Color) == tone, "remaining peer keeps its colour after disconnect")
	var room: Interior = (world.get_node("Interiors") as Interiors).interior("hut")
	peer_two.global_position = room.room_to_global(Vector2(200, 200))
	var indoor: Dictionary = _marker(map, "30")
	_check(bool(indoor.inside) and (indoor.tile as Vector2).is_equal_approx(Interiors.outer(get_tree(), peer_two.global_position) / 16.0), "indoor peer sits at the real outside entrance")
	knight.global_position = room.room_to_global(Vector2(240, 200))
	_check(bool(_marker(map, "valdric").inside), "Valdric also maps to the entrance indoors")
	map.size = Vector2(640, 360)
	map._marker_spots.clear()
	var first: Vector2 = map._place_marker(Vector2(320, 180))
	var second: Vector2 = map._place_marker(Vector2(320, 180))
	_check(first.distance_to(second) >= 14.0, "overlapping markers fan out without losing their anchor")
	var story: ArenaStory = get_tree().get_first_node_in_group("arena_story") as ArenaStory
	_check(story != null, "the boss arena's story exists")
	if story != null:
		story.set_physics_process(false)
		_check(_marker(map, "mornath").is_empty(), "no Mornath marker while his hologram is away")
		story.hologram.set_active(true)
		story.hologram._appear = 1.0
		var boss_marker: Dictionary = _marker(map, "mornath")
		_check(not boss_marker.is_empty() and String(boss_marker.kind) == "boss", "Mornath's hologram has its own boss marker")
		_check(not boss_marker.is_empty() and (boss_marker.tile as Vector2).is_equal_approx(story.hologram.global_position / 16.0), "the marker stands on the hologram")
		_check(not boss_marker.is_empty() and String(boss_marker.name) == "MORNATH" and not String(boss_marker.extra).is_empty(), "name and extra line come from map_markers.json")
		var card: Rect2 = map._presence_card_rect(boss_marker.merged({"screen": Vector2(320, 180)}))
		_check(card.size.y > 57.0 and map.get_rect().size.x >= 0.0, "his card has the extra line")
		story.hologram._appear = 0.2
		_check(_marker(map, "mornath").is_empty(), "a hologram that is still fading in or out is not marked")
		story.hologram._appear = 1.0
	_check(map._water_image != null and map._water_image.get_width() == RegionMap.WORLD_TILES, "water atlas loaded at tile resolution")
	var wet_tiles: int = 0
	for y: int in map._water_image.get_height():
		for x: int in map._water_image.get_width():
			if map._water_image.get_pixel(x, y).r > 0.1:
				wet_tiles += 1
	_check(wet_tiles > 1000, "real river coverage reaches the map")
	print("MAP PRESENCE: %d checks, %s" % [_checks, "PASS" if _ok else "FAIL"])
	var capture: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture = argument.trim_prefix("--capture=")
	if not capture.is_empty():
		town._banner.visible = false
		player.global_position = town.center + Vector2(20, 120)
		knight.global_position = town.center + Vector2(-30, 45)
		gustav.global_position = town.center + Vector2(65, 90)
		peer_two.global_position = town.center + Vector2(-100, 150)
		TimeManager.time_of_day = 0.98 if OS.get_cmdline_user_args().has("--night") else 0.5
		map._set_open(true)
		map._center = town.center / 16.0 + Vector2(-24, 15)
		map._scale = 4.0
		map._scale_target = 4.0
		if OS.get_cmdline_user_args().has("--river"):
			map._center = Vector2(640, 785)
			map._scale = 2.5
			map._scale_target = 2.5
		if OS.get_cmdline_user_args().has("--overview"):
			map._center = Vector2(550, 550)
			map._scale = 0.31
			map._scale_target = 0.31
		if OS.get_cmdline_user_args().has("--mornath") and story != null:
			map._center = story.hologram.global_position / 16.0 + Vector2(-6, 6)
			map._scale = 4.0
			map._scale_target = 4.0
		var hover: String = "mornath" if OS.get_cmdline_user_args().has("--mornath") else "gustav"
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--hover="):
				hover = argument.trim_prefix("--hover=")
		if hover == "self": hover = str(player.name)
		map._marker_spots.clear()
		for marker: Dictionary in map._live_markers():
			var anchor: Vector2 = map._to_screen(marker.tile as Vector2)
			if not map._on_screen(anchor, -12.0): continue
			var at: Vector2 = map._place_marker(anchor)
			if String(marker.id) == hover: map._cursor = at
		await get_tree().create_timer(1.4).timeout
		await RenderingServer.frame_post_draw
		var result: Error = get_viewport().get_texture().get_image().save_png(capture)
		_check(result == OK, "preview capture saved")
	map._set_open(false)
	world.queue_free()
	await _frames(3)
	get_tree().quit(0 if _ok else 1)
