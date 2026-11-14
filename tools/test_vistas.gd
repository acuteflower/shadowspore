extends Node
## Automated Stage 1 verification (`docs/wiesenbiom_ausbau_konzept.md` — Panorama-Aussichtspunkte):
## 1. All 14 `VistaPoint`s spawn on flat walkable Level-3 meadow ground with valid unblocked `seat_position()` and `approach_position()`.
## 2. Interacting (`VistaPoint.interact(player)`) sits Ellie via `RestComponent`, activates `MusicDirector.vista_mode`, fades the HUD (`hud.vista_hide`),
##    expands `WorldLevel` chunk streaming in the look direction (`_vista_focus_radius == 2`), and tweens `Camera2D.zoom` -> `0.56` + `player.view_shift`.
## 3. Sitting past `reveal_delay` marks the vista discovered in `Vistas`, reveals the wide valley disc in `MapDiscovery`, grants `12` XP, and appears on `MapVistas`.
## 4. Standing up restores `Camera2D.zoom`, `player.view_shift`, `hud.vista_hide`, `MusicDirector.vista_mode`, and clears `vista_focus`.
## 5. `SaveGame` round-trip (`export_state` / `import_state`) preserves discovered vistas.
## Optional `-- --capture=/abs/dir` saves real-world screenshots when run with `--rendering-driver opengl3`.

var _checks: int = 0
var _failures: int = 0
var _capture_dir: String = ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("VISTA TEST FAILED: " + label)
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
	TimeManager.set_time(0.36) ## crisp golden morning light

	var player: Player = world._players.get_child(0) as Player
	var manager: Vistas = Vistas.of(get_tree())
	var discovery: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	var music: MusicDirector = get_tree().get_first_node_in_group("music_director") as MusicDirector
	var hud: CanvasLayer = player.get_node("Hud") as CanvasLayer

	_check(manager != null, "Vistas manager exists in group 'vistas'")
	var entries: Array[Dictionary] = manager.entries()
	_check(entries.size() == 14, "All 14 meadow cliff vistas loaded from data/vistas.json (got %d)" % entries.size())

	var block_img: Image = Relief.BLOCK.get_image()
	block_img.convert(Image.FORMAT_L8)
	var region_map: RegionMap = RegionMap.new(0, DataRegistry.table("world_map"))

	for spec: Dictionary in entries:
		var vid: String = String(spec.id)
		var pt: VistaPoint = manager.point_node(vid)
		_check(pt != null, "VistaPoint node spawned for " + vid)
		if pt == null:
			continue
		var seat_tile: Vector2i = Vector2i(floori(pt.seat_position().x / 16.0), floori(pt.seat_position().y / 16.0))
		var app_tile: Vector2i = Vector2i(floori(pt.approach_position().x / 16.0), floori(pt.approach_position().y / 16.0))
		_check(region_map.biome_at(seat_tile) == "meadow", "%s stands in meadow biome" % vid)
		_check(block_img.get_pixelv(seat_tile).r8 < 128, "%s seat tile (%s) is walkable/unblocked" % [vid, str(seat_tile)])
		_check(block_img.get_pixelv(app_tile).r8 < 128, "%s approach tile (%s) is walkable/unblocked" % [vid, str(app_tile)])
		_check(not manager.is_discovered(vid), "%s starts undiscovered" % vid)

	## Test full sit -> zoom -> chunk stream -> discovery -> XP -> stand-up flow on `ruinen_seewarte` (overlooking the central lakes!)
	var target: VistaPoint = manager.point_node("ruinen_seewarte")
	_check(target != null, "ruinen_seewarte vista exists")
	player.health.heal_full()
	if player.intro != null:
		player.intro.queue_free()
		player.intro = null
	player.story_lock = false
	player.global_position = target.approach_position()
	(player.get_node("Camera2D") as Camera2D).reset_smoothing()

	## Let chunks stream around approach position
	for _i: int in 18:
		world._stream(false)
		await get_tree().process_frame

	_check(target.prompt() == "AUSSICHT GENIESSEN", "Prompt reads AUSSICHT GENIESSEN before sitting (got '%s')" % target.prompt())
	var xp_before: int = player.progress.xp
	var valley_probe_tile: Vector2 = Vector2(target.global_position / 16.0) + target.sit_direction() * 34.0
	_check(not discovery.is_seen(valley_probe_tile), "Distant valley tile starts hidden under fog")

	await _shot("01_before_sit")

	target.interact(player)
	var rest: RestComponent = player.get_node("RestComponent") as RestComponent
	var waited: float = 0.0
	while rest.state != RestComponent.State.IDLE and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1

	_check(rest.state == RestComponent.State.IDLE, "Player entered RestComponent.State.IDLE on VistaPoint")
	_check(bool(hud.get("vista_hide")), "HUD entered vista_hide fade mode while seated")
	_check(music != null and music.vista_mode, "MusicDirector entered vista_mode while seated")
	_check(world._vista_focus_radius == 2, "WorldLevel activated _vista_focus_radius == 2")

	## Pump streaming while zoomed out so valley chunks finish building
	await get_tree().create_timer(2.3).timeout
	for _i: int in 24:
		world._stream(false)
		await get_tree().process_frame

	var cam: Camera2D = player.view_camera()
	_check(absf(cam.zoom.x - 0.56) < 0.03, "Camera2D zoomed smoothly out to ~0.56 (got %.3f)" % cam.zoom.x)
	_check(player.view_shift.length() > 80.0, "Player view_shift panned toward the cliff valley (len=%.1f)" % player.view_shift.length())
	_check(world._chunks.has(world._vista_focus_cell), "Valley focus chunk streamed into memory")
	_check(manager.is_discovered("ruinen_seewarte"), "Vista marked discovered after sitting quietly")
	_check(discovery.is_seen(valley_probe_tile), "Wide valley disc revealed in MapDiscovery")
	_check(player.progress.xp == xp_before + 12, "First-time vista discovery granted +12 XP (%d -> %d)" % [xp_before, player.progress.xp])

	await _shot("02_seated_panorama_day")

	## Sunset / night glow shot if capturing
	if _capture_dir != "":
		TimeManager.set_time(0.84)
		await get_tree().create_timer(0.35).timeout
		await _shot("03_seated_panorama_dusk")
		TimeManager.set_time(0.36)

	## Verify MapVistas picks up the discovered vista and builds hover state cleanly
	var map_vistas: MapVistas = MapVistas.new()
	var identity_proj: Callable = func(tile: Vector2) -> Vector2: return tile
	var vista_tile: Vector2 = Vector2(494.0, 504.0)
	map_vistas.update(get_tree(), vista_tile, identity_proj)
	_check(map_vistas.hover == "ruinen_seewarte", "MapVistas registers discovered vista and hover hit-test")

	## Stand up and verify full cleanup
	rest.request_stand()
	var stand_wait: float = 0.0
	while rest.state != RestComponent.State.FREE and stand_wait < 2.0:
		await get_tree().create_timer(0.1).timeout
		stand_wait += 0.1
	await get_tree().create_timer(1.0).timeout

	_check(rest.state == RestComponent.State.FREE, "Player stood back up cleanly")
	_check(not bool(hud.get("vista_hide")), "HUD restored after standing up")
	_check(music != null and not music.vista_mode, "MusicDirector exited vista_mode")
	_check(world._vista_focus_radius == 0, "WorldLevel cleared _vista_focus_radius")
	_check(absf(cam.zoom.x - 1.0) < 0.03, "Camera2D zoom restored to 1.0 (got %.3f)" % cam.zoom.x)
	_check(player.view_shift.length() < 2.0, "Player view_shift restored to zero")

	## Save/load state round-trip
	var exported: Array = manager.export_state()
	_check(exported.has("ruinen_seewarte"), "Vistas.export_state includes discovered vista")
	manager.import_state([])
	_check(not manager.is_discovered("ruinen_seewarte") and not target.discovered_flag, "Clearing import resets vista state")
	manager.import_state(exported)
	_check(manager.is_discovered("ruinen_seewarte") and target.discovered_flag, "Vistas.import_state restores discovered vista & glow")

	## Re-sitting does NOT grant duplicate XP
	var xp_after: int = player.progress.xp
	target.rest_tick(player, 5.0)
	_check(player.progress.xp == xp_after, "Re-visiting an already discovered vista does not grant duplicate XP")

	print("VISTAS TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
