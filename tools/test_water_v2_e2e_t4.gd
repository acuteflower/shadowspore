extends RefCounted
## Tier 4 — Real-World End-to-End Application Scenarios (>=5 scenarios).


static func _chk(ctx: RefCounted, cond: bool, area: String, msg: String) -> bool:
	return bool(ctx.call(&"check", cond, area, msg))


static func run(tree: SceneTree, ctx: RefCounted) -> void:
	ctx.call(&"set_tier", "T4")
	await _scenario_1_bridge_puddle_ford(tree, ctx)
	await _scenario_2_coast_swash_ocean_swim(tree, ctx)
	await _scenario_3_stormy_night_puddles_fps(tree, ctx)
	await _scenario_4_multi_actor_jobs_stress(tree, ctx)
	await _scenario_5_world_rivers_coexistence(tree, ctx)


static func _scenario_1_bridge_puddle_ford(tree: SceneTree, ctx: RefCounted) -> void:
	var lab: Node2D = await ctx.call(&"host_and_spawn_lab", tree) as Node2D
	var wf: Node = ctx.call(&"find_water_field") as Node
	var wb: Node = ctx.call(&"find_water_bridge") as Node
	var player: CharacterBody2D = ctx.call(&"get_lab_player", lab) as CharacterBody2D
	var wm: Node = ctx.call(&"get_weather_manager") as Node

	var brook: Dictionary = ctx.call(&"scan_brook_samples", wf, wb) as Dictionary
	var bridge: Dictionary = ctx.call(&"scan_bridge_samples", wf, wb) as Dictionary
	var puddles_sq1: Array[Vector2] = ctx.call(&"scan_puddle_interiors", wf, wb, -568.0, -200.0) as Array[Vector2]

	var ok_walk_bridge: bool = false
	var ok_puddle_boots: bool = false
	var ok_ford_wade: bool = false

	if wf != null and wb != null and player != null:
		var start_pos: Vector2 = Vector2(0.0, 0.0)
		var east_app: Vector2 = bridge.get("east_approach", Vector2(INF, INF)) as Vector2
		var b_center: Vector2 = bridge.get("center", Vector2(INF, INF)) as Vector2
		var ford_pos: Vector2 = brook.get("south_ford_pos", Vector2(INF, INF)) as Vector2
		var max_x: float = float(bridge.get("max_x", -340.0))
		if is_finite(east_app.x) and is_finite(b_center.x) and is_finite(ford_pos.x):
			await ctx.call(&"teleport_and_settle", tree, player, start_pos)
			var start_surf: String = Terrain.surface_at(player.global_position)
			await ctx.call(&"teleport_and_settle", tree, player, east_app)
			await ctx.call(&"walk_player", tree, player, &"move_left", 48)
			await ctx.call(&"step_frames", tree, 4)
			var walked_onto_deck: bool = player.global_position.x <= max_x and bool(wb.call(&"has_water_deck_at", player.global_position))
			var player_surf: String = String(player.get(&"_surface_id"))
			ok_walk_bridge = start_surf == "grass" and walked_onto_deck and player_surf == "ancient_stone" and player.has_meta(&"water_deck") and int(player.get(&"swim")) == SwimRules.NONE

			if not puddles_sq1.is_empty():
				var p_pt: Vector2 = puddles_sq1[0]
				await ctx.call(&"reset_wet_state", tree, wm, player)
				var pre_b: int = int(ctx.call(&"count_active_footprints_near", tree, b_center, 48.0, Color("#1c2b33")))
				await ctx.call(&"teleport_and_settle", tree, player, b_center - Vector2(12.0, 0.0))
				await ctx.call(&"walk_player", tree, player, &"move_right", 24)
				var pre_a: int = int(ctx.call(&"count_active_footprints_near", tree, b_center, 48.0, Color("#1c2b33")))
				var clean_pre: bool = pre_a == pre_b

				await ctx.call(&"teleport_and_settle", tree, player, p_pt - Vector2(12.0, 0.0))
				await ctx.call(&"walk_player", tree, player, &"move_right", 28)
				var before_prints: int = int(ctx.call(&"count_active_footprints_near", tree, b_center, 48.0, Color("#1c2b33")))
				await ctx.call(&"teleport_and_settle", tree, player, b_center - Vector2(12.0, 0.0))
				await ctx.call(&"walk_player", tree, player, &"move_right", 32)
				var after_prints: int = int(ctx.call(&"count_active_footprints_near", tree, b_center, 48.0, Color("#1c2b33")))
				ok_puddle_boots = clean_pre and after_prints > before_prints
				await ctx.call(&"reset_wet_state", tree, wm, player)

			await ctx.call(&"teleport_and_settle", tree, player, ford_pos - Vector2(14.0, 0.0))
			await ctx.call(&"walk_player", tree, player, &"move_right", 24)
			await ctx.call(&"step_frames", tree, 4)
			var p_surf_ford: String = String(player.get(&"_surface_id"))
			var p_surf_dict: Dictionary = player.get(&"_surface") as Dictionary
			var wo: Node = player.get_node_or_null("WaterOverlay")
			var wo_sub: float = float(wo.get(&"submerge")) if wo != null else 0.0
			ok_ford_wade = (
				p_surf_ford == "shallow_water"
				and bool(p_surf_dict.get("water", false))
				and float(p_surf_dict.get("submerge", 0.0)) > 0.0
				and bool(p_surf_dict.get("ripples", false))
				and wo_sub > 0.0
				and int(player.get(&"swim")) == SwimRules.NONE
			)

	_chk(ctx, ok_walk_bridge and ok_puddle_boots and ok_ford_wade, "S1", "Scenario 1: Square 0 -> dry WaterBridge -> bank puddle wet boots -> southern gravel ford wade (bridge=%s boots=%s ford=%s)" % [str(ok_walk_bridge), str(ok_puddle_boots), str(ok_ford_wade)])
	await ctx.call(&"cleanup_node", tree, lab)


static func _scenario_2_coast_swash_ocean_swim(tree: SceneTree, ctx: RefCounted) -> void:
	var lab: Node2D = await ctx.call(&"host_and_spawn_lab", tree) as Node2D
	var wf: Node = ctx.call(&"find_water_field") as Node
	var wb: Node = ctx.call(&"find_water_bridge") as Node
	var player: CharacterBody2D = ctx.call(&"get_lab_player", lab) as CharacterBody2D
	var grass: Node2D = ctx.call(&"get_lab_grass", lab) as Node2D

	var swash: Dictionary = ctx.call(&"scan_swash_samples", wf) as Dictionary
	var ocean: Dictionary = ctx.call(&"scan_ocean_samples", wf) as Dictionary
	var puddles_sq2: Array[Vector2] = ctx.call(&"scan_puddle_interiors", wf, wb, -952.0, -584.0) as Array[Vector2]

	var ok_dunes: bool = false
	var ok_puddle_sq2: bool = false
	var ok_stationary_swash: bool = false
	var ok_ocean_swim: bool = false

	if wf != null and player != null:
		if grass != null:
			ok_dunes = int(ctx.call(&"count_grass_cells_in_rect", grass, Rect2(-710.0, -120.0, 130.0, 240.0))) > 0

		var dry_beach: Vector2 = swash.get("dry_beach_pos", Vector2(INF, INF)) as Vector2
		if not puddles_sq2.is_empty() and is_finite(dry_beach.x):
			await ctx.call(&"teleport_and_settle", tree, player, puddles_sq2[0] - Vector2(10.0, 0.0))
			await ctx.call(&"walk_player", tree, player, &"move_right", 24)
			ok_puddle_sq2 = Terrain.surface_at(puddles_sq2[0]) == "puddle" and bool(wf.call(&"reflects_at", puddles_sq2[0]))

		var dyn_pos: Vector2 = swash.get("dynamic_swash_pos", Vector2(INF, INF)) as Vector2
		if is_finite(dyn_pos.x) and bool(ctx.call(&"rules_has_method", &"shore_state_at")):
			await ctx.call(&"teleport_and_settle", tree, player, dyn_pos)
			var sync_hits: int = 0
			var seen_swash: Dictionary = {}
			var saw_submerge_tide: bool = false
			var wo: Node = player.get_node_or_null("WaterOverlay")
			var fvec: Vector2 = wf.call(&"field_at", dyn_pos) as Vector2
			for step_i: int in 18:
				var t_now: float = float(ctx.call(&"global_shader_float", &"g_water_time"))
				var wdir: Vector2 = ctx.call(&"global_shader_vec2", &"g_wind_dir") as Vector2
				var wgust: float = float(ctx.call(&"global_shader_float", &"g_wind_gust"))
				var storm: float = float(ctx.call(&"global_shader_float", &"g_storm"))
				var expected: String = String(ctx.call(&"call_rules", &"shore_state_at", [fvec.x, dyn_pos.y, t_now, wdir, wgust, storm]))
				var p_surf: String = String(player.get(&"_surface_id"))
				seen_swash[p_surf] = true
				if p_surf == "tide_shallow" and wo != null and float(wo.get(&"submerge")) > 0.0:
					saw_submerge_tide = true
				if p_surf == expected:
					sync_hits += 1
				await ctx.call(&"step_frames", tree, 20)
			ok_stationary_swash = sync_hits >= 12 and seen_swash.size() >= 2 and (saw_submerge_tide or not seen_swash.has("tide_shallow"))

		var deep_west: Vector2 = ocean.get("deep_west_pos", Vector2(INF, INF)) as Vector2
		if is_finite(deep_west.x):
			await ctx.call(&"teleport_and_settle", tree, player, deep_west)
			await ctx.call(&"step_frames", tree, 20)
			var swimmer: Object = player.get(&"swimmer") as Object
			var swim_started: bool = int(player.get(&"swim")) > 0 and swimmer != null and bool(swimmer.get(&"active"))
			var p0: Vector2 = player.global_position
			await ctx.call(&"step_frames", tree, 30)
			var p1: Vector2 = player.global_position
			var c_ocean: Color = (wf.call(&"water_color_at", deep_west) as Dictionary).get("fill", Color.BLACK) as Color
			ok_ocean_swim = swim_started and p0.distance_to(p1) > 0.1 and c_ocean.b > c_ocean.r

	_chk(ctx, ok_dunes and ok_puddle_sq2 and ok_stationary_swash and ok_ocean_swim, "S2", "Scenario 2: Square -2 dunes -> tidepool -> stationary WaterRules swash sync -> Square -3 swim+drift (dunes=%s pud=%s swash=%s swim=%s)" % [str(ok_dunes), str(ok_puddle_sq2), str(ok_stationary_swash), str(ok_ocean_swim)])
	await ctx.call(&"cleanup_node", tree, lab)


static func _scenario_3_stormy_night_puddles_fps(tree: SceneTree, ctx: RefCounted) -> void:
	var lab: Node2D = await ctx.call(&"host_and_spawn_lab", tree) as Node2D
	var wf: Node = ctx.call(&"find_water_field") as Node
	var wb: Node = ctx.call(&"find_water_bridge") as Node
	var player: CharacterBody2D = ctx.call(&"get_lab_player", lab) as CharacterBody2D
	var bridge: Dictionary = ctx.call(&"scan_bridge_samples", wf, wb) as Dictionary
	var ocean: Dictionary = ctx.call(&"scan_ocean_samples", wf) as Dictionary
	var wm: Node = ctx.call(&"get_weather_manager") as Node
	var wr: Node = ctx.call(&"get_water_reflections") as Node

	var ok_storm_night: bool = false
	var ok_fps: bool = false
	var avg_ms: float = 999.0

	if wf != null and wb != null and wm != null and player != null:
		await ctx.call(&"reset_wet_state", tree, wm, player)
		await ctx.call(&"step_seconds", tree, 0.8)
		var dry_puddles: int = (ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array).size()

		wm.call(&"force", "downpour", 60.0)
		wm.set(&"rain", 0.90)
		wm.set(&"_extra_wet", 1.0)
		wm.set(&"puddle", 0.9)
		wm.set(&"ground_wet", 1.0)
		await ctx.call(&"step_seconds", tree, 1.4)
		var rain_puddles: int = (ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array).size()
		var gp_rain: float = float(ctx.call(&"global_shader_float", &"g_puddle"))
		var gr_rain: float = float(ctx.call(&"global_shader_float", &"g_rain"))

		var b_center: Vector2 = bridge.get("center", Vector2(-384.0, 0.0)) as Vector2
		await ctx.call(&"teleport_and_settle", tree, player, b_center)
		wm.call(&"force", "storm", 60.0)
		TimeManager.lock_at(0.00)
		OS.delay_msec(115)
		await ctx.call(&"step_seconds", tree, 1.6)

		var glow_node: CanvasItem = ctx.call(&"find_node_by_name_or_shader", lab, "WaterV2Glow", "water_v2_glow.gdshader") as CanvasItem
		var glow_vis: bool = glow_node != null and glow_node.visible
		var lantern_vis: bool = bool(ctx.call(&"check_bridge_lanterns", wb, true))

		var swell_elevated: bool = false
		var deep_pts: Array[Vector2] = ocean.get("points", []) as Array[Vector2]
		if not deep_pts.is_empty() and bool(ctx.call(&"rules_has_method", &"swell_height")):
			var s_storm: float = absf(float(ctx.call(&"call_rules", &"swell_height", [deep_pts[0], 2.0, Vector2.RIGHT, float(ctx.call(&"global_shader_float", &"g_wind_gust")), float(ctx.call(&"global_shader_float", &"g_storm"))])))
			swell_elevated = s_storm > 0.0

		var refl_ok: bool = wr != null and bool(wr.get(&"enabled"))
		ok_storm_night = rain_puddles > dry_puddles and gp_rain > 0.3 and gr_rain > 0.1 and glow_vis and lantern_vis and swell_elevated and refl_ok and float(ctx.call(&"global_shader_float", &"g_storm")) > 0.2

		# CPU frame-time stress under active movement/swimming/ringbuffer/swimmers
		# (GPU fragment shader & SubViewport budget belongs to non-headless M6 capture).
		var s3_start: Vector2 = ocean.get("shallow_east_pos", Vector2(INF, INF)) as Vector2
		if not is_finite(s3_start.x):
			s3_start = Vector2(-976.0, 0.0)
		await ctx.call(&"teleport_and_settle", tree, player, s3_start)
		await ctx.call(&"step_frames", tree, 4)
		for k: int in 4:
			var sw_pos: Vector2 = player.global_position + Vector2(-48.0 + float(k) * 16.0, 0.0)
			wf.call(&"set_swimmer", 9100 + k, Vector4(sw_pos.x, sw_pos.y, 1.0, 0.5))
		Input.action_press(&"move_left")
		var t0_usec: int = Time.get_ticks_usec()
		for frame_i: int in 60:
			if frame_i % 10 == 0:
				wf.call(&"add_water_impulse", player.global_position, 0.8, 8.0, Vector2.LEFT)
			await tree.physics_frame
		var elapsed_usec: int = Time.get_ticks_usec() - t0_usec
		Input.action_release(&"move_left")
		var wave_active_s3: bool = bool(wf.get(&"_wave_active"))
		var kept_v: Variant = wf.get(&"_kept_tiles")
		var active_v: Variant = wf.get(&"_active_tiles")
		var tile_hits: int = (kept_v as Array).size() if kept_v is Array else 0
		if tile_hits == 0 and active_v is Array:
			tile_hits = (active_v as Array).size()
		var wave_bytes_v: Variant = wf.get(&"_wave_bytes")
		var non_neutral_s3: bool = false
		if wave_bytes_v is PackedByteArray:
			var wb_arr: PackedByteArray = wave_bytes_v as PackedByteArray
			var b_idx: int = 0
			while b_idx + 3 < wb_arr.size():
				if wb_arr[b_idx + 2] != 128 or wb_arr[b_idx + 3] > 0:
					non_neutral_s3 = true
					break
				b_idx += 4
		for k: int in 4:
			wf.call(&"set_swimmer", 9100 + k, Vector4.ZERO)
		avg_ms = float(elapsed_usec) / (60.0 * 1000.0)
		ok_fps = avg_ms <= 16.67 and wave_active_s3 and non_neutral_s3 and tile_hits > 0

	_chk(ctx, ok_storm_night, "S3", "Scenario 3a: Stormy night expands rain puddles, activates water_v2_glow & bridge lantern, raises swell & reflections")
	_chk(ctx, ok_fps, "S3", "Scenario 3b: 60-FPS CPU frame-time budget holds under active stormy-night water traversal (avg=%.2f ms <= 16.67 ms)" % avg_ms)
	await ctx.call(&"cleanup_node", tree, lab)


static func _scenario_4_multi_actor_jobs_stress(tree: SceneTree, ctx: RefCounted) -> void:
	var lab: Node2D = await ctx.call(&"host_and_spawn_lab", tree) as Node2D
	var wf: Node = ctx.call(&"find_water_field") as Node
	var wb: Node = ctx.call(&"find_water_bridge") as Node
	var brook: Dictionary = ctx.call(&"scan_brook_samples", wf, wb) as Dictionary
	var swash: Dictionary = ctx.call(&"scan_swash_samples", wf) as Dictionary
	var ocean: Dictionary = ctx.call(&"scan_ocean_samples", wf) as Dictionary

	var ok_stress: bool = false
	if wf != null:
		var probes: Array[Vector2] = []
		var b_pts: Array[Vector2] = brook.get("points", []) as Array[Vector2]
		var r3_pts: Array[Vector2] = swash.get("regime3_points", []) as Array[Vector2]
		var o_pts: Array[Vector2] = ocean.get("points", []) as Array[Vector2]
		if not b_pts.is_empty():
			probes.append(b_pts[0])
		if not r3_pts.is_empty():
			probes.append(r3_pts[0])
		if not o_pts.is_empty():
			probes.append(o_pts[0])
		probes.append(Vector2(-384.0, 0.0))
		probes.append(Vector2(-768.0, 0.0))
		probes.append(Vector2(-1152.0, 0.0))

		var baseline: Array[Dictionary] = []
		for p: Vector2 in probes:
			baseline.append({
				"field": wf.call(&"field_at", p),
				"info": wf.call(&"water_field_at", p),
				"flow": wf.call(&"water_flow_at", p),
				"color": wf.call(&"water_color_at", p),
				"surf": wf.call(&"surface_at", p),
				"prop": wf.call(&"clear_for_prop", p, 8.0),
			})

		for k: int in 8:
			var sp: Vector2 = probes[k % probes.size()]
			wf.call(&"set_swimmer", 7000 + k, Vector4(sp.x, sp.y, 1.0, 0.5))

		var job_out: Array[Array] = []
		job_out.resize(16)
		var job_ids: Array[Jobs.Job] = []
		for w: int in 16:
			var work: Callable = func() -> Array:
				var rows: Array = []
				for p: Vector2 in probes:
					rows.append({
						"field": wf.call(&"field_at", p),
						"info": wf.call(&"water_field_at", p),
						"flow": wf.call(&"water_flow_at", p),
						"color": wf.call(&"water_color_at", p),
						"surf": wf.call(&"surface_at", p),
						"prop": wf.call(&"clear_for_prop", p, 8.0),
					})
				return rows
			var done: Callable = func(res: Variant) -> void:
				job_out[w] = res as Array
			job_ids.append(Jobs.run(work, done, 0, Callable(), "e2e_t4_stress"))

		for imp: int in 24:
			var ip: Vector2 = probes[imp % probes.size()]
			wf.call(&"add_water_impulse", ip, 0.9, 8.0, Vector2.LEFT)

		Jobs.wait_all(job_ids)
		await ctx.call(&"step_frames", tree, 2)

		var all_match: bool = true
		for w: int in 16:
			var rows: Array = job_out[w]
			if rows.size() != probes.size():
				all_match = false
				break
			for i: int in probes.size():
				var b: Dictionary = baseline[i]
				var r: Dictionary = rows[i] as Dictionary
				if b["field"] != r["field"] or b["surf"] != r["surf"] or b["prop"] != r["prop"] or b["flow"] != r["flow"]:
					all_match = false
					break

		for k: int in 8:
			wf.call(&"set_swimmer", 7000 + k, Vector4.ZERO)
		ok_stress = all_match

	_chk(ctx, ok_stress, "S4", "Scenario 4: 8 swimmers + 24 impulses + 16 concurrent Jobs.run() WaterField workers match baseline cleanly")
	await ctx.call(&"cleanup_node", tree, lab)


static func _scenario_5_world_rivers_coexistence(tree: SceneTree, ctx: RefCounted) -> void:
	NetworkManager.host_singleplayer()
	var world_packed: PackedScene = ctx.call(&"load_scene", String(ctx.get(&"WORLD_LEVEL_PATH"))) as PackedScene
	var wf_scr: GDScript = ctx.call(&"load_script", String(ctx.get(&"WATER_FIELD_PATH"))) as GDScript
	var ok_coexist: bool = false
	var ok_cleanup: bool = false

	if world_packed != null and wf_scr != null:
		var world_inst: Node = world_packed.instantiate()
		if world_inst is Node2D:
			var world: Node2D = world_inst as Node2D
			tree.root.add_child(world)
			await ctx.call(&"step_frames", tree, 4)

			var wf_node: Node2D = wf_scr.new() as Node2D
			tree.root.add_child(wf_node)
			wf_node.call(&"build_grass_lab_west")
			await ctx.call(&"step_frames", tree, 2)
			var wf_registered: bool = Terrain.patches.has(wf_node)
			var wf_isolated: bool = String(wf_node.call(&"surface_at", Vector2(384.0, 22.0))) == ""
			var wf_west_active: bool = String(wf_node.call(&"surface_at", Vector2(-384.0, 0.0))) != ""
			var zone_wf_count: int = 0
			for patch: Node in Terrain.patches:
				if is_instance_valid(patch) and patch.get_script() == wf_scr:
					zone_wf_count += 1
			ok_coexist = zone_wf_count >= 2 and wf_registered and wf_isolated and wf_west_active

			await ctx.call(&"cleanup_node", tree, wf_node)
			await ctx.call(&"cleanup_node", tree, world)

			var leaked_patches: Array[Node] = []
			for patch: Node in Terrain.patches:
				if not is_instance_valid(patch) or patch.get_script() == wf_scr:
					leaked_patches.append(patch)
			ok_cleanup = leaked_patches.is_empty()

	_chk(ctx, ok_coexist, "S5", "Scenario 5a: ZoneWorld + standalone WaterField coexist cleanly in Terrain.patches")
	_chk(ctx, ok_cleanup, "S5", "Scenario 5b: Teardown removes all WaterField patches from Terrain.patches without leaks")
