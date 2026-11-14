extends Node
## Live OpenGL3 visual verification captures for Sonnenquarz-Öde Stufe 3 & Stufe 4b:
## 1) Midday `sun_heat` (`ERHITZT`), golden stamina vine shimmer & Ellie's `'sweat'` brow-wipe gesture + `QuartzArch` shade
## 2) Sand-drifted `desert_caravan_ruins` road + `ruin_sandstone` + `LightConduit` pulse + `ResonanceObelisk` Prism Ring
## 3) `prism_vein` on white ground quartz during dry `Arkanes Quarzgewitter` + violet-amber arcane lightning bolt
## 4) Nighttime `PrismSeal` (`prism_ruinenfeld`) trial illuminated with conduits, obelisks & risen chest
## Run: godot --rendering-driver opengl3 --path . res://tools/preview_desert_features.tscn -- --dir=/abs/folder

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")


func _ready() -> void:
	_run.call_deferred()


func _shot(dir: String, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, file_name])


func _run() -> void:
	var dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.trim_prefix("--dir=")
	GameCursor.visible = false
	NetworkManager.host_singleplayer()
	var world: WorldLevel = WORLD.instantiate() as WorldLevel
	world.opening_over = true
	add_child(world)
	await get_tree().process_frame
	var hero: Player = world._players.get_child(0) as Player
	hero.intro = null
	hero.story_lock = false
	hero.wounded = false
	hero.health.floor_value = 0.0
	hero.health.current = hero.health.max_health
	var wound_border: CanvasItem = world.find_child("WoundBorder", true, false) as CanvasItem
	if wound_border != null:
		wound_border.visible = false
	var guide: Node = hero.get_node_or_null("OpeningGuide")
	if guide != null:
		guide.set_process(false)
		if guide is CanvasItem:
			(guide as CanvasItem).visible = false
	hero.quests.set_physics_process(false)

	var cam: Camera2D = hero.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		for c: Node in hero.get_children():
			if c is Camera2D:
				cam = c as Camera2D
				break

	TimeManager.unlock()
	TimeManager.locked = true

	# --- Shot 1: Midday Sun-Heat (`ERHITZT`), golden stamina vine shimmer & Ellie `'sweat'` brow-wipe on Sand-Drifted Caravan Road ---
	var caravan_spot: Vector2 = Vector2(888.0, 146.0) * 16.0 + Vector2(8.0, 8.0)
	for path_v: Variant in DataRegistry.table("ground").get("paths", []) as Array:
		var p_spec: Dictionary = path_v as Dictionary
		if String(p_spec.get("id", "")) == "desert_caravan_ruins":
			var pts: Array = p_spec.get("points", []) as Array
			if pts.size() >= 6:
				var mid_pt: Array = pts[pts.size() / 2] as Array
				caravan_spot = Vector2(world._start) * 16.0 + Vector2(8.0, 8.0) + Vector2(float(mid_pt[0]), float(mid_pt[1]))
			break

	TimeManager.time_of_day = 0.50
	hero.request_teleport(caravan_spot)
	for _i: int in 95:
		await get_tree().process_frame

	hero.set_physics_process(false)
	hero.velocity = Vector2.ZERO
	hero.facing = Vector2(0.35, 0.94).normalized()
	hero._sector = 2
	hero.heat_amount = 0.95
	hero.effects.apply("sun_heat")
	hero.stamina.current = hero.stamina.max_stamina * 0.72 ## ensure stamina vine stays visible on HUD
	hero._start_standby(Player.HEAT_STANDBY_CLIP)
	hero._standby_time = 10.0 / 12.0 ## peak brow-wipe frame
	hero._animate(0.0)
	if cam != null:
		cam.zoom = Vector2(1.6, 1.6)
	for _i: int in 12:
		await get_tree().process_frame
	await _shot(dir, "1_heat_sweat_and_shade")

	# --- Shot 2: Real Bundled Ruin Courtyard Ensemble (`shrine_ensemble` / `sanctum_seal`) with Arch Shade, Corner Masonry, Conduit Pulse & Prism Ring ---
	var ruin_chunk: Vector2i = Vector2i.ZERO
	var ruin_spot: Vector2 = caravan_spot
	if world.desert_ruins != null:
		for c_key: Variant in world.desert_ruins.sites():
			var s_spec: Dictionary = world.desert_ruins.sites()[c_key] as Dictionary
			var sk: String = String(s_spec.get("kind", ""))
			var st: Vector2i = s_spec.tile as Vector2i
			if sk == "shrine_ensemble" and st.x >= 835:
				ruin_chunk = c_key as Vector2i
				ruin_spot = s_spec.pos as Vector2
				break
		if ruin_chunk == Vector2i.ZERO:
			for c_key2: Variant in world.desert_ruins.sites():
				var s_spec2: Dictionary = world.desert_ruins.sites()[c_key2] as Dictionary
				if String(s_spec2.get("kind", "")) in ["shrine_ensemble", "sanctum_seal"]:
					ruin_chunk = c_key2 as Vector2i
					ruin_spot = s_spec2.pos as Vector2
					break

	hero.set_physics_process(true)
	hero.request_teleport(ruin_spot + Vector2(0.0, 2.0))
	if cam != null:
		cam.zoom = Vector2(1.25, 1.25)
	for _i: int in 95:
		await get_tree().process_frame

	if world.desert_ruins != null and world.desert_ruins._live_chunks.has(ruin_chunk):
		for rn_v: Variant in world.desert_ruins._live_chunks[ruin_chunk] as Array:
			if rn_v is DesertRuins.LightConduit:
				var lc: DesertRuins.LightConduit = rn_v as DesertRuins.LightConduit
				lc.trigger_pulse()
				lc._pulse_t = 0.55
				lc._refresh_glows()
				lc._spark_overlay.queue_redraw()
			elif rn_v is DesertRuins.ResonanceObelisk:
				var rob: DesertRuins.ResonanceObelisk = rn_v as DesertRuins.ResonanceObelisk
				rob.emit_prism_ring()
				rob._ring_t = 0.44
				rob._ring_draw.queue_redraw()
	for _i: int in 4:
		await get_tree().process_frame
	await _shot(dir, "2_caravan_conduit_and_prism_ring")

	# --- Shot 3: Prism Vein on White Ground Quartz + Dry Arkanes Quarzgewitter & Arcane Bolt ---
	var prism_spot: Vector2 = Vector2(860.0, 150.0) * 16.0 + Vector2(8.0, 8.0)
	for cy: int in range(3, 8):
		var found_pv: bool = false
		for cx: int in range(25, 32):
			var rect: Rect2i = Rect2i(Vector2i(cx, cy) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			for entry: Dictionary in world._generator.props_for_chunk(rect):
				if String(entry.kind) == "prism_vein":
					prism_spot = entry.pos as Vector2
					found_pv = true
					break
			if found_pv:
				break
		if found_pv:
			break

	hero.set_physics_process(true)
	hero.cool_down(45.0)
	hero.request_teleport(prism_spot + Vector2(-28.0, 18.0))
	TimeManager.time_of_day = 0.54
	if cam != null:
		cam.zoom = Vector2(1.5, 1.5)
	for _i: int in 85:
		await get_tree().process_frame
	if WeatherManager.current != null:
		WeatherManager.current.focus = prism_spot
		WeatherManager.current.force("storm", 0.0)
		for _w: int in 20:
			WeatherManager.current.follow(false, 2.0)
			await get_tree().process_frame
		WeatherManager.current._strike({"x": 0.58, "y": 0.42, "far": 0.08, "seed": 11, "bolt": true, "double": true}, 0.0)
	await _shot(dir, "3_prism_vein_arcane_storm")
	if WeatherManager.current != null:
		WeatherManager.current.release()

	# --- Shot 4: Nighttime PrismSeal Sanctuary (`prism_ruinenfeld`) with Arch, Conduits, Obelisks, Corner Piers & Risen Chest ---
	var seal_spot: Vector2 = Vector2(993.0, 180.0) * 16.0 + Vector2(8.0, 8.0)
	var puzzles_node: Puzzles = world.get_node_or_null("Puzzles") as Puzzles
	if puzzles_node != null and puzzles_node.trial("prism_ruinenfeld") != null:
		seal_spot = puzzles_node.trial("prism_ruinenfeld").global_position
	TimeManager.time_of_day = 0.0
	hero.request_teleport(seal_spot + Vector2(0.0, 18.0))
	if cam != null:
		cam.zoom = Vector2(1.22, 1.22)
	for _i: int in 90:
		await get_tree().process_frame
	if puzzles_node != null:
		var pt: PrismSeal = puzzles_node.trial("prism_ruinenfeld") as PrismSeal
		if pt != null:
			pt.activate_pillar(0)
			pt.activate_pillar(1)
			pt.activate_pillar(2)
	for _i: int in 25:
		await get_tree().process_frame
	await _shot(dir, "4_prism_seal_night")

	print("DESERT FEATURES PREVIEW OK")
	get_tree().quit()
