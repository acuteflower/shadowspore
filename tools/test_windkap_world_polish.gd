extends Node2D
## End-to-end verification & GPU visual capture suite for the Windkap World Polish:
##   1. Continuous River <-> Sea Estuary & River <-> Lake (`Erlenweiher`) junctions
##   2. Clean Blotch-Free Pixel-Art Beach Sand with REAL WorldWind Movement (sand drift, Treibsand veils, airborne sand wisps)
##   3. ONLY Existing Project Objects (coastal_props.png, rock_ground_details.png, LivingRock, LivingGrass — ZERO custom extras or ShoreCrabs!)
##   4. Real 3D Sand Footprints (`z_index == -6`) + Live Swash Wash-Away
##   5. Fast Seamless Streaming & Entry from Windkap into Südkap (`windkap_suedkap` threshold open, zero dark void!)
##
## Run headless checks:
##   Godot --headless --path . --fixed-fps 60 res://tools/test_windkap_world_polish.tscn
## Run GPU visual capture:
##   Godot --path . --fixed-fps 60 res://tools/test_windkap_world_polish.tscn -- --capture-dir="C:/path/to/dir"

const WORLD_SCENE: PackedScene = preload("res://src/world/v2/zone_world.tscn")

var _checks: int = 0
var _fails: int = 0
var _capture_dir: String = ""


func _ready() -> void:
	_capture_dir = _parse_arg("--capture-dir=")
	get_tree().create_timer(115.0).timeout.connect(func() -> void:
		push_error("TIMEOUT in test_windkap_world_polish")
		get_tree().quit(1)
	)
	_run.call_deferred()


static func _parse_arg(prefix: String) -> String:
	var all_args: PackedStringArray = OS.get_cmdline_user_args()
	all_args.append_array(OS.get_cmdline_args())
	for arg: String in all_args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).strip_edges()
	return ""


func _chk(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + msg)
		print("[FAIL] ", msg)
	else:
		print("[PASS] ", msg)


func _step_frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _run() -> void:
	NetworkManager.host_singleplayer()
	await _step_frames(2)

	var world: ZoneWorld = WORLD_SCENE.instantiate() as ZoneWorld
	world.loading_in_steps = false
	add_child(world)
	await _step_frames(12)

	var atlas: Atlas = Atlas.shared()
	var z: Atlas.Zone = atlas.zone(&"windkap")
	var dir: ZoneDirector = world._director
	var stage: ZoneStage = dir.stage(&"windkap") if dir != null else null
	var player: Player = SaveGame._local_player(get_tree())

	_chk(z != null and stage != null and stage.attached, "Windkap ZoneStage built and attached cleanly")
	_chk(player != null, "Local player spawned in ZoneWorld")
	if z == null or stage == null or player == null:
		get_tree().quit(1)
		return

	var origin: Vector2 = Vector2(z.origin)
	var water: WaterField = stage.water
	var rocky: RockyGround = stage.rocky
	_chk(water != null, "Windkap WaterField exists")
	_chk(rocky != null, "Windkap RockyGround exists")

	# --- 1. Water Junction Checks (River <-> Sea Estuary + River <-> Lake Erlenweiher) ---
	if water != null:
		var mouth_pts: Array[Vector2] = [
			Atlas.px_of(origin + Vector2(153.6, 178.5)),
			Atlas.px_of(origin + Vector2(148.5, 183.5)),
			Atlas.px_of(origin + Vector2(145.7, 186.3)),
			Atlas.px_of(origin + Vector2(144.2, 190.5)),
			Atlas.px_of(origin + Vector2(143.5, 195.0)),
		]
		var all_water: bool = true
		var max_sdf_jump: float = 0.0
		var prev_sdf: float = water.field_at(mouth_pts[0]).x
		var has_outflow: bool = false
		for mp: Vector2 in mouth_pts:
			var wf: Dictionary = water.water_field_at(mp)
			if not bool(wf.get("water", false)):
				all_water = false
			var cur_sdf: float = float(wf.get("static_sdf_px", 0.0))
			max_sdf_jump = maxf(max_sdf_jump, absf(cur_sdf - prev_sdf))
			prev_sdf = cur_sdf
			var fl: Vector2 = water.water_flow_at(mp)
			if fl.length() > 1.0:
				has_outflow = true
		_chk(all_water, "Erlenbach -> Silberbucht estuary centerline stays continuous water throughout mouth")
		_chk(max_sdf_jump < 48.0, "Estuary SDF transitions smoothly without discontinuity jump (max_jump=%.1f)" % max_sdf_jump)
		_chk(has_outflow, "Erlenbach estuary maintains active seaward outflow current")

		var lake_center: Vector2 = Atlas.px_of(origin + Vector2(175.8, 148.4))
		var wf_lake: Dictionary = water.water_field_at(lake_center)
		_chk(bool(wf_lake.get("water", false)) and int(wf_lake.get("regime", 0)) == WaterRules.REGIME_LAKE, "Erlenweiher woodland pond active as REGIME_LAKE (reg=%d)" % int(wf_lake.get("regime", 0)))

		var beach_pt: Vector2 = Atlas.px_of(origin + Vector2(112.0, 202.0))
		var s_beach: String = Terrain.surface_at(beach_pt)
		_chk(s_beach in ["beach_sand", "wet_sand", "tide_shallow"], "Silberbucht beach reports coastal sand/swash surface (got '%s')" % s_beach)

		# Verify permanent sand water-puddle blotches were removed from Windkap
		var old_puddle_pt: Vector2 = Atlas.px_of(origin + Vector2(105.2, 203.2))
		var wf_old_pud: Dictionary = water.water_field_at(old_puddle_pt)
		_chk(int(wf_old_pud.get("regime", 0)) != WaterRules.REGIME_PUDDLE, "No permanent puddle blotches on Windkap beach sand")

	# --- 2. Live WorldWind Beach & Sand Movement Check ---
	var dry_beach_pos: Vector2 = Atlas.px_of(origin + Vector2(112.0, 202.0))
	player.global_position = dry_beach_pos
	var ww: WorldWind = WorldWind.current
	if ww != null:
		ww.set_weather(0.55, 0.24, 0.10, 0.0)
	var drift_before: Vector2 = water._sand_drift if water != null else Vector2.ZERO
	var creep_before: float = water._dune_creep if water != null else 0.0
	var saw_coastal_sand_wisp: bool = false
	for _w: int in 45:
		await get_tree().process_frame
		if ww != null and not saw_coastal_sand_wisp:
			for p_v: Variant in ww._air:
				if p_v is Dictionary and int((p_v as Dictionary).get("kind", -1)) == 10:
					saw_coastal_sand_wisp = true
					break
	var drift_delta: float = (water._sand_drift - drift_before).length() if water != null else 0.0
	var creep_delta: float = (water._dune_creep - creep_before) if water != null else 0.0
	_chk(drift_delta > 4.0 and creep_delta > 0.10, "Coastal sand shader actively drifts & creeps with live WorldWind (drift=%.1f px, creep=%.2f)" % [drift_delta, creep_delta])
	_chk(saw_coastal_sand_wisp, "WorldWind spawns live airborne coastal beach Treibsand wisps (kind=10) over dry sand")

	# --- 3. Sand Footprint Visibility & Real Wash-Away Check ---
	var foot_comp: FootstepComponent = player.get_node_or_null("FootstepComponent") as FootstepComponent
	_chk(foot_comp != null, "Player has FootstepComponent")
	if foot_comp != null:
		var dry_surf: Dictionary = Terrain.surface_data("beach_sand")
		foot_comp.step(dry_surf, Vector2(65.0, 8.0), false, 0.0, 1)
		var canvas: FootstepComponent.FootprintCanvas = FootstepComponent._get_canvas(get_tree())
		_chk(canvas != null and canvas.z_index == -6, "FootprintCanvas renders at z_index == -6 above WaterField sand (-7)")
		var active_prints: int = 0
		var dry_styled: int = 0
		if canvas != null:
			for it: FootstepComponent.FootprintItem in canvas._pool:
				if it.active:
					active_prints += 1
					if it.style == FootstepComponent.STYLE_DRY_SAND:
						dry_styled += 1
		_chk(active_prints >= 1 and dry_styled >= 1, "Dry sand footprint created with 3D dry_sand style (active=%d, dry=%d)" % [active_prints, dry_styled])

		var surf_water_pos: Vector2 = Atlas.px_of(origin + Vector2(114.0, 207.0))
		if canvas != null:
			canvas.add_footprint(canvas.to_local(surf_water_pos), surf_water_pos, 0.0, Color("#3d332d"), 0.85, 7.0, FootstepComponent.STYLE_WET_SAND, true)
			await _step_frames(12)
			var washed_triggered: bool = false
			for it: FootstepComponent.FootprintItem in canvas._pool:
				if it.washable and (it.washing or (not it.active and it.world_pos == surf_water_pos)):
					washed_triggered = true
					break
			_chk(washed_triggered, "Surf water actively triggers swash wash-away on washable coastal sand footprints")

	# --- 4. Existing-Assets-Only Check (ZERO windkap_extras & ZERO ShoreCrabs!) ---
	_chk(not ResourceLoader.exists("res://assets/tiles/windkap_extras.png"), "Removed custom windkap_extras.png asset cleanly")
	_chk(stage.get_node_or_null("ShoreCrabs") == null, "Removed custom ShoreCrabs node cleanly")
	var flat_coastal: Node = stage.get_node_or_null("CoastalPropsFlat")
	_chk(flat_coastal != null and flat_coastal.get_child_count() >= 14, "Existing coastal_props.png flat details populated (count=%d)" % (flat_coastal.get_child_count() if flat_coastal != null else 0))
	if rocky != null:
		_chk(rocky.detail_count >= 80, "Existing RockyGround rock_ground_details.png populated (detail_count=%d)" % rocky.detail_count)
	var living_rocks: int = 0
	for ch: Node in stage.props_root.get_children():
		if ch is LivingRock:
			living_rocks += 1
	_chk(living_rocks >= 30, "Existing LivingRock boulders & fieldstones populated (count=%d)" % living_rocks)

	# --- 5. Seamless Windkap -> Südkap Streaming & Open Threshold Check ---
	var approach_suedkap_px: Vector2 = Atlas.px_of(Vector2(704.0, 1338.6)) ## 19 tiles west of naht_windkap_suedkap on dirt road
	player.global_position = approach_suedkap_px
	var t_stream0: int = Time.get_ticks_msec()
	var deadline_ms: int = t_stream0 + 25000
	while not dir.is_loaded(&"suedkap") and Time.get_ticks_msec() < deadline_ms:
		await get_tree().process_frame
	var stream_sec: float = float(Time.get_ticks_msec() - t_stream0) / 1000.0
	await _step_frames(18)
	var suedkap_loaded: bool = dir.is_loaded(&"suedkap")
	var gate_open_wk: bool = not stage.gate_closed(&"windkap_suedkap")
	var veil_wk: ZoneVeil = stage.veil(&"windkap_suedkap")
	var veil_open: bool = veil_wk == null or not veil_wk.shut
	var sk_stage: ZoneStage = dir.stage(&"suedkap")
	var gate_open_sk: bool = sk_stage != null and not sk_stage.gate_closed(&"windkap_suedkap")
	_chk(suedkap_loaded, "Südkap streams & attaches automatically when approaching naht_windkap_suedkap (%.2fs)" % stream_sec)
	_chk(gate_open_wk and gate_open_sk and veil_open, "Threshold windkap_suedkap gate & ZoneVeil are OPEN on both sides (wk=%s, sk=%s, veil=%s)" % [str(gate_open_wk), str(gate_open_sk), str(veil_open)])

	# Cross the seam physically into Südkap and confirm ZoneDirector tracks player in Südkap!
	player.global_position = Atlas.px_of(Vector2(732.0, 1340.5))
	await _step_frames(68) ## allow Windkap's ZoneVeil (1.0s fade) to fully dissolve before visual inspection
	var pzone: StringName = dir.player_zone.get(1, &"") as StringName
	_chk(pzone == &"suedkap", "Crossing east seam transitions player smoothly into Südkap (player_zone=%s)" % String(pzone))
	_chk(veil_wk == null or not veil_wk.visible, "Threshold windkap_suedkap ZoneVeil fully dissolved after opening")

	# --- 6. Optional Real GPU Visual Screenshots ---
	if not _capture_dir.is_empty():
		await _capture_visual_shots(world, z, stage, player, foot_comp)

	print("TEST_WINDKAP_WORLD_POLISH COMPLETE: %d/%d passed (%d failed)" % [_checks - _fails, _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _capture_visual_shots(world: ZoneWorld, z: Atlas.Zone, stage: ZoneStage, player: Player, foot_comp: FootstepComponent) -> void:
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	var origin: Vector2 = Vector2(z.origin)
	var cam: Camera2D = player.get("_camera") as Camera2D
	if player._hud != null:
		player._hud.visible = false
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	for grp: String in ["speech_box", "dialogue_box"]:
		for ui_n: Node in get_tree().get_nodes_in_group(grp):
			if ui_n is CanvasItem:
				(ui_n as CanvasItem).visible = false
			if ui_n.has_method("close"):
				ui_n.call("close")

	# Stamp clean dry & wet beach footprints on Silberbucht
	if foot_comp != null:
		var canvas: FootstepComponent.FootprintCanvas = FootstepComponent._get_canvas(get_tree())
		if canvas != null:
			var trail_start: Vector2 = Atlas.px_of(origin + Vector2(107.0, 199.5))
			var trail_end: Vector2 = Atlas.px_of(origin + Vector2(115.5, 198.2))
			var dir_v: Vector2 = (trail_end - trail_start).normalized()
			var perp: Vector2 = Vector2(-dir_v.y, dir_v.x)
			var rot: float = roundf(dir_v.angle() / (PI / 4.0)) * (PI / 4.0)
			for i: int in 14:
				var fp: Vector2 = trail_start.lerp(trail_end, float(i) / 13.0) + perp * (2.6 if i % 2 == 0 else -2.6)
				canvas.add_footprint(canvas.to_local(fp.round()), fp.round(), rot, Color("#7d6347"), 0.85, 90.0, FootstepComponent.STYLE_DRY_SAND, false)
			var wet_start: Vector2 = Atlas.px_of(origin + Vector2(110.0, 202.4))
			var wet_end: Vector2 = Atlas.px_of(origin + Vector2(115.0, 201.4))
			for j: int in 8:
				var wfp: Vector2 = wet_start.lerp(wet_end, float(j) / 7.0) + perp * (2.6 if j % 2 == 0 else -2.6)
				canvas.add_footprint(canvas.to_local(wfp.round()), wfp.round(), rot, Color("#3d332d"), 0.88, 90.0, FootstepComponent.STYLE_WET_SAND, false)

	# Keep active coastal breeze for crisp visible sand wisps!
	if WorldWind.current != null:
		WorldWind.current.set_weather(0.55, 0.24, 0.08, 0.0)

	var shots: Array[Dictionary] = [
		{"file": "01_suedkap_crossing_day.png", "world": Vector2(723.0, 1338.6), "zoom": 0.85, "time": 0.44, "off": Vector2(0.0, 0.0), "wait": 24},
		{"file": "02_beach_wind_day_a.png", "local": Vector2(112.5, 198.5), "zoom": 1.0, "time": 0.44, "off": Vector2(0.0, 6.0), "wait": 24},
		{"file": "03_beach_wind_day_b.png", "local": Vector2(112.5, 198.5), "zoom": 1.0, "time": 0.44, "off": Vector2(0.0, 6.0), "wait": 36},
		{"file": "04_beach_wind_night.png", "local": Vector2(112.5, 198.5), "zoom": 0.95, "time": 0.96, "off": Vector2(0.0, 6.0), "wait": 18},
		{"file": "05_estuary_day.png", "local": Vector2(146.5, 185.5), "zoom": 0.88, "time": 0.44, "off": Vector2(0.0, 16.0), "wait": 16},
		{"file": "06_rocky_nw_day.png", "local": Vector2(72.0, 68.0), "zoom": 0.85, "time": 0.44, "off": Vector2(0.0, 0.0), "wait": 14},
		{"file": "07_rocky_windkap_day.png", "local": Vector2(48.5, 159.0), "zoom": 0.85, "time": 0.44, "off": Vector2(-18.0, 6.0), "wait": 14},
	]

	for shot: Dictionary in shots:
		TimeManager.lock_at(float(shot["time"]))
		var pos: Vector2 = Atlas.px_of(shot["world"] as Vector2) if shot.has("world") else Atlas.px_of(origin + (shot["local"] as Vector2))
		player.global_position = pos
		if cam != null:
			var zf: float = float(shot["zoom"])
			cam.zoom = Vector2(zf, zf)
			cam.offset = shot["off"] as Vector2
			cam.reset_smoothing()
		for _f: int in int(shot.get("wait", 14)):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var out_path: String = _capture_dir.path_join(String(shot["file"]))
		img.save_png(out_path)
		print("CAPTURED ", out_path)
	if stage != null and world != null:
		pass
