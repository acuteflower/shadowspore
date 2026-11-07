extends Node
## Waystone statues (docs/waystones.md): the statue stands where the data says, E starts the awakening, the host marks it awake, the map's fog lifts round it,
## the camera scene holds and releases the player, the save state round-trips. Takes about 20 s (real time). `-- --capture=/abs/dir` saves a picture per moment (needs a window).
var _ok: bool = true
var _dir: String = ""


func _check(name: String, value: bool) -> void:
	if not value:
		_ok = false
		print("FAILED: ", name)


func _shot(name: String) -> void:
	if _dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


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
	var statue: WaystoneStatue = world.get_node("Waystone_hang_wachterin") as WaystoneStatue
	var manager: Waystones = Waystones.of(get_tree())
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	_check("statue exists", statue != null and manager != null)
	_check("statue is on the plateau tile", statue.position.is_equal_approx(Vector2(840, 649) * 16.0 + Vector2(8, 8)))
	_check("dormant prompt", statue.prompt() == "AKTIVIEREN" and not statue.awake)
	_check("registered", manager.entries().size() == 8 and not bool(manager.entries()[0].awake))
	player.global_position = statue.global_position + Vector2(0, 40)
	var far: Vector2 = Vector2(840 + 50, 649)
	_check("far tile unseen before", not discovery.is_seen(far))
	player.health.heal_full()
	await _shot("0_dormant")
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	await get_tree().create_timer(0.9).timeout ## the first time she is this close: a small dialogue, once
	_check("discovery dialogue opens", box.is_active() and player.quests.has_flag("waystone_seen"))
	box._end()
	await get_tree().process_frame
	statue.interact(player) ## E: she lays her palms on the stone, the statue wakes where they touch
	await get_tree().create_timer(0.1).timeout
	_check("touch animation runs", player.is_busy() and player.touch_hold and statue.prompt() == "")
	_check("not awake before the palms touch", not manager.is_awake(statue.id))
	await get_tree().create_timer(0.6).timeout
	_check("host marks it awake when the palms lie on it", manager.is_awake(statue.id))
	_check("palms stay on the stone", player.touch_hold)
	_check("player held by the scene", player.story_lock)
	await _shot("1_flicker")
	await get_tree().create_timer(2.6).timeout
	await _shot("2_wave_a")
	await get_tree().create_timer(1.2).timeout
	await _shot("3_wave_b")
	await get_tree().create_timer(1.3).timeout
	await _shot("4_bloom")
	_check("palms let go at the bloom", not player.touch_hold)
	await get_tree().create_timer(1.2).timeout
	_check("statue settled awake", statue.awake)
	await _shot("5_awake")
	await get_tree().create_timer(2.4).timeout
	await _shot("6_map")
	_check("fog lifted round the statue", discovery.is_seen(far))
	await get_tree().create_timer(6.0).timeout
	_check("player free again", not player.story_lock)
	await _shot("7_after")
	var saved: Dictionary = manager.export_state()
	_check("export lists the statue", (saved.awake as Array).has(statue.id))
	manager._awake.clear()
	statue.awake = false
	manager.import_state(saved)
	_check("import restores it", manager.is_awake(statue.id) and statue.awake)
	await _travel_test(world, player, manager, statue)
	print("WAYSTONES: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


## Travel: the second statue stands at (598, 523); E at an awake statue walks her up, the map opens in travel mode, holding chooses a destination.
func _travel_test(world: WorldLevel, player: Player, manager: Waystones, first: WaystoneStatue) -> void:
	var second: WaystoneStatue = world.get_node("Waystone_ebene_wachterin") as WaystoneStatue
	_check("second statue stands at 598, 523", second != null and second.position.is_equal_approx(Vector2(598, 523) * 16.0 + Vector2(8, 8)))
	_check("dormant second statue offers activating", second.prompt() == "AKTIVIEREN")
	manager.import_state({"awake": [first.id, second.id]})
	_check("awake statues offer travelling", first.prompt() == "REISEN" and second.prompt() == "REISEN")
	# the hold on the map (pure rules, identity projection)
	var ways: MapWaystones = MapWaystones.new()
	ways.travel_from = first.id
	var to_tile: Callable = func(tile: Vector2) -> Vector2: return tile
	var target_tile: Vector2 = Vector2(598, 523)
	var picked: String = ""
	for i: int in 5:
		picked = ways.update(0.1, get_tree(), target_tile, to_tile, true, false, 0)
	_check("hold is under way and not finished", picked == "" and ways.hold > 0.3 and ways.target == second.id)
	ways.update(0.1, get_tree(), Vector2(0, 0), to_tile, true, false, 0) ## the mouse leaves: the hold decays
	for i: int in 6:
		ways.update(0.1, get_tree(), target_tile, to_tile, true, false, 0)
	for i: int in 14:
		picked = ways.update(0.1, get_tree(), target_tile, to_tile, true, false, 0)
		if picked != "":
			break
	_check("holding long enough picks the statue", picked == second.id)
	# E at the first statue: she walks up, touches it, the map opens in travel mode; closing it again cancels
	player.global_position = first.global_position + Vector2(40, 60)
	first.interact(player)
	await get_tree().create_timer(0.3).timeout
	_check("travel scene holds her", player.story_lock and player.get_node_or_null("WaystoneTravel") != null)
	var map: MapWindow = get_tree().get_first_node_in_group("map_window") as MapWindow
	var waited: float = 0.0
	while not map.visible and waited < 8.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	await get_tree().create_timer(1.6).timeout
	_check("map opened in travel mode", map.visible and map._ways.travel_from == first.id and map._ways.destinations() == [second.id])
	_check("she stands at the statue with palms on it", player.touch_hold and player.global_position.distance_to(first.global_position + Vector2(0, 15)) < 6.0)
	map._cursor = map._to_screen(Vector2(598, 523))
	map._ws_mouse = true
	await get_tree().create_timer(0.7).timeout
	_check("the marker reacts to the mouse", map._ways.hover == second.id and map._ways.hold > 0.2)
	await _shot("8_travel_map")
	map._ws_mouse = false
	map._set_open(false) ## Esc: no travel
	await get_tree().create_timer(0.3).timeout
	_check("cancelling frees her", not player.story_lock and not player.touch_hold)
	await get_tree().create_timer(1.0).timeout
	first.interact(player)
	waited = 0.0
	while not map.visible and waited < 8.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	await get_tree().create_timer(1.0).timeout
	map._ways.travel_from = ""
	map._set_open(false)
	map.travel_chosen.emit(first.id, second.id) ## the hold finished
	await get_tree().create_timer(0.9).timeout
	await _shot("9_travel_flood")
	await get_tree().create_timer(3.8).timeout
	_check("she arrived in front of the second statue", player.global_position.distance_to(second.global_position + Vector2(0, 28)) < 12.0)
	_check("and is free", not player.story_lock)
	await _shot("10_arrived")
