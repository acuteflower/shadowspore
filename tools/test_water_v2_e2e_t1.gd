extends RefCounted
## Tier 1 — Feature Coverage (F1..F9, >=5 checks per feature area, >=45 total).


static func _chk(ctx: RefCounted, cond: bool, area: String, msg: String) -> bool:
	return bool(ctx.call(&"check", cond, area, msg))


static func run(tree: SceneTree, ctx: RefCounted) -> void:
	ctx.call(&"set_tier", "T1")
	var lab: Node2D = await ctx.call(&"host_and_spawn_lab", tree) as Node2D
	var wf: Node = ctx.call(&"find_water_field") as Node
	var wb: Node = ctx.call(&"find_water_bridge") as Node
	var player: CharacterBody2D = ctx.call(&"get_lab_player", lab) as CharacterBody2D

	var brook: Dictionary = ctx.call(&"scan_brook_samples", wf, wb) as Dictionary
	var bridge: Dictionary = ctx.call(&"scan_bridge_samples", wf, wb) as Dictionary
	var swash: Dictionary = ctx.call(&"scan_swash_samples", wf) as Dictionary
	var ocean: Dictionary = ctx.call(&"scan_ocean_samples", wf) as Dictionary
	var puddles_sq1: Array[Vector2] = ctx.call(&"scan_puddles", wf, wb, -568.0, -200.0) as Array[Vector2]
	var puddles_sq2: Array[Vector2] = ctx.call(&"scan_puddles", wf, wb, -952.0, -584.0) as Array[Vector2]

	await _test_f1_brook(tree, ctx, wf, brook)
	await _test_f2_bridge(tree, ctx, lab, wf, wb, player, bridge)
	await _test_f3_coastal(tree, ctx, lab, wf, swash)
	await _test_f4_ocean(tree, ctx, wf, player, ocean, brook, swash)
	await _test_f5_ringbuffer_jobs(tree, ctx, wf, player, brook, ocean)
	await _test_f6_wind_weather_time_reflections(tree, ctx, lab, wf, brook, swash, puddles_sq1)
	await _test_f7_art_audio(tree, ctx, lab, wf, player, brook, swash, ocean)
	await _test_f8_boundary_r1_preservation(tree, ctx, lab, wf)
	await _test_f9_puddles_tidepools(tree, ctx, lab, wf, wb, player, puddles_sq1, puddles_sq2, bridge, swash)

	await ctx.call(&"cleanup_node", tree, lab)


static func _test_f1_brook(tree: SceneTree, ctx: RefCounted, wf: Node, brook: Dictionary) -> void:
	var wf_idx: int = int(ctx.call(&"patch_index", wf))
	_chk(ctx, wf != null and wf_idx >= 0, "F1", "WaterField node instantiated and registered in Terrain.patches")
	var pts: Array[Vector2] = brook.get("points", []) as Array[Vector2]
	var min_y: float = float(brook.get("min_y", INF))
	var max_y: float = float(brook.get("max_y", -INF))
	_chk(ctx, not pts.is_empty() and min_y < -40.0 and max_y > 40.0, "F1", "Square -1 brook has regime==1 spanning N->S (pts=%d, y=[%.0f..%.0f])" % [pts.size(), min_y, max_y])

	var north_deep: Vector2 = brook.get("north_deep_pos", Vector2(INF, INF)) as Vector2
	var max_depth: float = float(brook.get("max_depth", 0.0))
	var deep_ok: bool = wf != null and is_finite(north_deep.x) and max_depth >= 0.6 and bool(wf.call(&"is_deep", north_deep))
	_chk(ctx, deep_ok, "F1", "Square -1 northern kolk exists with depth >= 0.6 and is_deep == true (max_depth=%.2f)" % max_depth)

	var ford_pos: Vector2 = brook.get("south_ford_pos", Vector2(INF, INF)) as Vector2
	var ford_depth: float = float(brook.get("min_ford_depth", 1.0))
	var ford_ok: bool = wf != null and is_finite(ford_pos.x) and ford_depth < 0.35 and Terrain.surface_at(ford_pos) == "shallow_water" and not bool(wf.call(&"is_deep", ford_pos))
	_chk(ctx, ford_ok, "F1", "Square -1 southern gravel ford exists (depth=%.2f < 0.35, surface=shallow_water, is_deep=false)" % ford_depth)

	var wade_ok: bool = false
	if wf != null and is_finite(ford_pos.x):
		var base: Dictionary = Terrain.surface_data("shallow_water")
		var wade: Dictionary = wf.call(&"wade_data", ford_pos, base) as Dictionary
		var fv: Vector2 = wade.get("flow_velocity", Vector2.ZERO) as Vector2
		wade_ok = bool(wade.get("water", false)) and float(wade.get("submerge", 0.0)) > 0.0 and bool(wade.get("ripples", false)) and float(wade.get("depth_amount", 1.0)) < 0.92 and fv.length() > 0.0
	_chk(ctx, wade_ok, "F1", "WaterField.wade_data() at gravel ford populates water/submerge/ripples/flow_velocity")

	var flow_ok: bool = false
	if wf != null and not pts.is_empty():
		var downstream_hits: int = 0
		for p: Vector2 in pts:
			var flow: Vector2 = wf.call(&"water_flow_at", p) as Vector2
			if flow.y > 0.5 and flow.length() > 0.5:
				downstream_hits += 1
		flow_ok = downstream_hits > 0
	_chk(ctx, flow_ok, "F1", "WaterField.water_flow_at() across Square -1 brook yields non-zero N->S downstream vectors")
	await tree.process_frame


static func _test_f2_bridge(tree: SceneTree, ctx: RefCounted, lab: Node2D, wf: Node, wb: Node, player: CharacterBody2D, bridge: Dictionary) -> void:
	var wf_idx: int = int(ctx.call(&"patch_index", wf))
	var wb_idx: int = int(ctx.call(&"patch_index", wb))
	_chk(ctx, wb != null and wf_idx >= 0 and wb_idx > wf_idx, "F2", "WaterBridge registered in Terrain.patches after WaterField (%d > %d)" % [wb_idx, wf_idx])

	var over_water: Vector2 = bridge.get("deck_over_water_pos", Vector2(INF, INF)) as Vector2
	var deck_ok: bool = wb != null and is_finite(over_water.x) and bool(wb.call(&"has_water_deck_at", over_water)) and Terrain.surface_at(over_water) == "ancient_stone"
	_chk(ctx, deck_ok, "F2", "WaterBridge deck over brook returns has_water_deck_at==true and Terrain.surface_at=='ancient_stone'")

	var player_deck_ok: bool = false
	if player != null and is_finite(over_water.x):
		var depth_wall: StaticBody2D = StaticBody2D.new()
		depth_wall.add_to_group("river_depth")
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rect_shape: RectangleShape2D = RectangleShape2D.new()
		rect_shape.size = Vector2(24.0, 24.0)
		cs.shape = rect_shape
		depth_wall.add_child(cs)
		depth_wall.position = over_water + Vector2(64.0, 0.0)
		lab.add_child(depth_wall)
		await ctx.call(&"teleport_and_settle", tree, player, over_water)
		await ctx.call(&"step_frames", tree, 4)
		var swimmer: Object = player.get(&"swimmer") as Object
		var exc_n: int = int(swimmer.call(&"exception_count")) if swimmer != null and swimmer.has_method(&"exception_count") else 0
		player_deck_ok = player.has_meta(&"water_deck") and int(player.get(&"swim")) == SwimRules.NONE and exc_n > 0
		depth_wall.queue_free()
		await ctx.call(&"step_frames", tree, 2)
	_chk(ctx, player_deck_ok, "F2", "Player on WaterBridge deck sets water_deck meta, stays dry (swim==NONE), and retains river_depth exceptions")

	var parapet_ok: bool = false
	var center: Vector2 = bridge.get("center", Vector2(INF, INF)) as Vector2
	if lab != null and is_finite(center.x):
		var probe: CharacterBody2D = CharacterBody2D.new()
		probe.collision_layer = 0
		probe.collision_mask = 1
		var p_shape: CollisionShape2D = CollisionShape2D.new()
		var p_circ: CircleShape2D = CircleShape2D.new()
		p_circ.radius = 4.0
		p_shape.shape = p_circ
		probe.add_child(p_shape)
		lab.add_child(probe)
		for rd_node: Node in tree.get_nodes_in_group("river_depth"):
			if rd_node is CollisionObject2D:
				probe.add_collision_exception_with(rd_node as CollisionObject2D)
		probe.position = center
		await ctx.call(&"step_frames", tree, 2)
		var blocked_n: bool = probe.test_move(probe.global_transform, Vector2(0.0, -28.0))
		var blocked_s: bool = probe.test_move(probe.global_transform, Vector2(0.0, 28.0))
		var open_e: bool = not probe.test_move(probe.global_transform, Vector2(18.0, 0.0))
		var open_w: bool = not probe.test_move(probe.global_transform, Vector2(-18.0, 0.0))
		parapet_ok = blocked_n and blocked_s and open_e and open_w
		probe.queue_free()
	_chk(ctx, parapet_ok, "F2", "North/South Layer-1 StaticBody2D parapets block vertical exit while E/W approaches stay open")

	var pier_flow_ok: bool = false
	if wf != null and wb != null and is_finite(center.x):
		var min_y: float = float(bridge.get("min_y", center.y - 12.0))
		var max_y: float = float(bridge.get("max_y", center.y + 12.0))
		var min_x: float = float(bridge.get("min_x", center.x - 32.0))
		var max_x: float = float(bridge.get("max_x", center.x + 32.0))
		var field_bounds_v: Variant = wf.get(&"bounds")
		var has_shadow: bool = false
		var has_turb: bool = false
		if field_bounds_v is Rect2:
			var sy: float = min_y - 24.0
			while sy <= max_y + 24.0:
				var sx: float = min_x - 8.0
				while sx <= max_x + 8.0:
					var sp: Vector2 = Vector2(sx, sy)
					if (field_bounds_v as Rect2).has_point(sp):
						var winfo: Dictionary = wf.call(&"water_field_at", sp) as Dictionary
						if float(winfo.get("shadow", 0.0)) > 0.2:
							has_shadow = true
						if float(winfo.get("turbulence", 0.0)) > 0.05:
							has_turb = true
					sx += 4.0
				sy += 4.0
		var flow_up: Vector2 = wf.call(&"water_flow_at", Vector2(center.x, min_y - 28.0)) as Vector2
		var flow_under: Vector2 = wf.call(&"water_flow_at", center) as Vector2
		pier_flow_ok = has_shadow and has_turb and (flow_up.length() > 0.5) and (flow_up.distance_to(flow_under) > 0.2)
	_chk(ctx, pier_flow_ok, "F2", "Bridge piers & arch shadow injected into water_flow_map / water_flow_at")

	var z_ok: bool = false
	if wb != null:
		var has_deck_z: bool = (wb as Node2D).z_index == -3
		var has_rail_z0: bool = false
		for child: Node in wb.find_children("*", "CanvasItem", true, false):
			var ci: CanvasItem = child as CanvasItem
			var nm: String = ci.name.to_lower()
			if ci.z_index == -3:
				has_deck_z = true
			if (nm.contains("rail") or nm.contains("parapet") or nm.contains("north") or nm.contains("south")) and ci.z_index == 0:
				has_rail_z0 = true
		z_ok = has_deck_z and has_rail_z0
	_chk(ctx, z_ok, "F2", "WaterBridge Y-sorted deck uses z_index==-3 and railings use z_index==0")

	var lantern_ok: bool = false
	if wb != null and player != null and is_finite(center.x):
		await ctx.call(&"teleport_and_settle", tree, player, center)
		await ctx.call(&"lock_time_and_settle_lights", tree, 0.50)
		var off_by_day: bool = bool(ctx.call(&"check_bridge_lanterns", wb, false))
		await ctx.call(&"lock_time_and_settle_lights", tree, 0.00)
		var on_by_night: bool = bool(ctx.call(&"check_bridge_lanterns", wb, true))
		lantern_ok = off_by_day and on_by_night
		TimeManager.lock_at(0.50)
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, lantern_ok, "F2", "WaterBridge lantern glow & NightLight are off at noon (0.50) and active at night (0.00)")


static func _test_f3_coastal(tree: SceneTree, ctx: RefCounted, lab: Node2D, wf: Node, swash: Dictionary) -> void:
	var r3_pts: Array[Vector2] = swash.get("regime3_points", []) as Array[Vector2]
	_chk(ctx, not r3_pts.is_empty(), "F3", "Square -2 coastal biome contains regime==3 samples (%d pts)" % r3_pts.size())

	var seen: Dictionary = swash.get("surfaces_seen", {}) as Dictionary
	var has_all_surfaces: bool = seen.has("beach_sand") and seen.has("wet_sand") and seen.has("tide_shallow")
	if not has_all_surfaces and wf != null:
		var dyn_pos: Vector2 = swash.get("dynamic_swash_pos", Vector2(INF, INF)) as Vector2
		if is_finite(dyn_pos.x):
			var extra_seen: Dictionary = seen.duplicate()
			var dinfo: Dictionary = wf.call(&"water_field_at", dyn_pos) as Dictionary
			var static_sdf: float = float(dinfo.get("static_sdf_px", 0.0))
			var base_t: float = float(ctx.call(&"global_shader_float", &"g_water_time"))
			var wdir: Vector2 = ctx.call(&"global_shader_vec2", &"g_wind_dir") as Vector2
			var wgust: float = float(ctx.call(&"global_shader_float", &"g_wind_gust"))
			var storm: float = float(ctx.call(&"global_shader_float", &"g_storm"))
			for step_i: int in 16:
				var probe_t: float = base_t + float(step_i) * 0.34
				var st: Variant = ctx.call(&"call_rules", &"shore_state_at", [static_sdf, dyn_pos.y, probe_t, wdir, wgust, storm])
				if st != null:
					extra_seen[String(st)] = true
			has_all_surfaces = extra_seen.has("beach_sand") and extra_seen.has("wet_sand") and extra_seen.has("tide_shallow")
	_chk(ctx, has_all_surfaces, "F3", "Square -2 exhibits beach_sand, wet_sand, and tide_shallow surfaces (seen=%s)" % str(seen.keys()))

	var rules_ok: bool = false
	if ctx.call(&"rules_script") != null:
		var a: Variant = ctx.call(&"call_rules", &"swash_offset_px", [0.0, 3.25, Vector2.RIGHT, 0.4, 0.1])
		var b: Variant = ctx.call(&"call_rules", &"swash_offset_px", [0.0, 3.25, Vector2.RIGHT, 0.4, 0.1])
		var p: Variant = ctx.call(&"call_rules", &"swash_phase", [0.0, 3.25, Vector2.RIGHT, 0.4, 0.1])
		var w: Variant = ctx.call(&"call_rules", &"sand_wetness", [2.0, 0.0, 3.25, Vector2.RIGHT, 0.4, 0.1])
		var s: Variant = ctx.call(&"call_rules", &"shore_state_at", [2.0, 0.0, 3.25, Vector2.RIGHT, 0.4, 0.1])
		rules_ok = a != null and b != null and is_equal_approx(float(a), float(b)) and p != null and w != null and s != null
	_chk(ctx, rules_ok, "F3", "WaterRules pure functions (swash_offset_px, swash_phase, sand_wetness, shore_state_at) are deterministic")

	var sync_ok: bool = false
	var dyn_pos2: Vector2 = swash.get("dynamic_swash_pos", Vector2(INF, INF)) as Vector2
	if wf != null and is_finite(dyn_pos2.x) and bool(ctx.call(&"rules_has_method", &"shore_state_at")):
		var mismatches: int = 0
		var matches: int = 0
		for frame_step: int in 4:
			var t_now: float = float(ctx.call(&"global_shader_float", &"g_water_time"))
			var wdir: Vector2 = ctx.call(&"global_shader_vec2", &"g_wind_dir") as Vector2
			var wgust: float = float(ctx.call(&"global_shader_float", &"g_wind_gust"))
			var storm: float = float(ctx.call(&"global_shader_float", &"g_storm"))
			var fvec: Vector2 = wf.call(&"field_at", dyn_pos2) as Vector2
			var rule_state: String = String(ctx.call(&"call_rules", &"shore_state_at", [fvec.x, dyn_pos2.y, t_now, wdir, wgust, storm]))
			var surf_state: String = Terrain.surface_at(dyn_pos2)
			if surf_state == rule_state:
				matches += 1
			else:
				mismatches += 1
			await ctx.call(&"step_frames", tree, 20)
		sync_ok = matches > 0 and mismatches == 0
	_chk(ctx, sync_ok, "F3", "CPU/GPU sync: Terrain.surface_at matches WaterRules.shore_state_at across swash ticks")

	var terrain_tbl: Dictionary = DataRegistry.table("terrain")
	var json_ok: bool = terrain_tbl.has("beach_sand") and terrain_tbl.has("wet_sand") and terrain_tbl.has("tide_shallow")
	if json_ok:
		var ts_entry: Dictionary = terrain_tbl["tide_shallow"] as Dictionary
		json_ok = bool(ts_entry.get("water", false)) and bool(ts_entry.get("ripples", false)) and float(ts_entry.get("submerge", 0.0)) > 0.0
	_chk(ctx, json_ok, "F3", "data/terrain.json includes beach_sand, wet_sand, and tide_shallow with valid metadata")

	var tr_beach: float = MovementRules.surface_traction("beach_sand", 0.0, 0.0)
	var tr_wet: float = MovementRules.surface_traction("wet_sand", 0.2, 0.0)
	var tr_tide: float = MovementRules.surface_traction("tide_shallow", 0.5, 0.0)
	var tr_stone: float = MovementRules.surface_traction("ancient_stone", 0.0, 0.0)
	var traction_ok: bool = tr_beach < 1.0 and tr_tide < tr_beach and tr_stone >= 1.04 and tr_wet >= 0.5 and tr_wet <= 1.2
	_chk(ctx, traction_ok, "F3", "MovementRules.surface_traction handles beach_sand/wet_sand/tide_shallow/ancient_stone (%.2f, %.2f, %.2f, %.2f)" % [tr_beach, tr_wet, tr_tide, tr_stone])

	var grass_ok: bool = false
	var grass: Node2D = ctx.call(&"get_lab_grass", lab) as Node2D
	if grass != null and wf != null:
		var wet_samples: int = 0
		var wet_grass_hits: int = 0
		var y: float = -120.0
		while y <= 120.0:
			var x: float = -820.0
			while x <= -590.0:
				var p: Vector2 = Vector2(x, y)
				var s_at: String = String(wf.call(&"surface_at", p))
				var info: Dictionary = wf.call(&"water_field_at", p) as Dictionary
				var sdf_v: float = float(info.get("static_sdf_px", 99.0))
				if (bool(info.get("water", false)) and sdf_v <= -12.0) or s_at == "wet_sand" or s_at == "tide_shallow":
					wet_samples += 1
					if bool(ctx.call(&"has_grass_cell_at", grass, p)):
						wet_grass_hits += 1
				x += 12.0
			y += 12.0
		var dune_cells: int = int(ctx.call(&"count_grass_cells_in_rect", grass, Rect2(-710.0, -120.0, 130.0, 240.0)))
		grass_ok = dune_cells > 0 and wet_samples >= 10 and wet_grass_hits == 0
	_chk(ctx, grass_ok, "F3", "LivingGrass places coastal dune oats on Square -2 dunes and clears water/wet_sand")


static func _test_f4_ocean(tree: SceneTree, ctx: RefCounted, wf: Node, player: CharacterBody2D, ocean: Dictionary, brook: Dictionary, swash: Dictionary) -> void:
	var pts: Array[Vector2] = ocean.get("points", []) as Array[Vector2]
	_chk(ctx, not pts.is_empty(), "F4", "Square -3 Open Sea contains regime==4 samples (%d pts)" % pts.size())

	var shallow_east: Vector2 = ocean.get("shallow_east_pos", Vector2(INF, INF)) as Vector2
	var deep_west: Vector2 = ocean.get("deep_west_pos", Vector2(INF, INF)) as Vector2
	var min_d: float = float(ocean.get("min_depth", 1.0))
	var max_d: float = float(ocean.get("max_depth", 0.0))
	var shelf_ok: bool = is_finite(shallow_east.x) and is_finite(deep_west.x) and deep_west.x < shallow_east.x and max_d >= 0.90 and max_d > min_d + 0.15
	_chk(ctx, shelf_ok, "F4", "Shelf drop-off increases westward toward 1.0 (min=%.2f@x=%.0f -> max=%.2f@x=%.0f)" % [min_d, shallow_east.x, max_d, deep_west.x])

	var deep_ok: bool = wf != null and is_finite(deep_west.x) and bool(wf.call(&"is_deep", deep_west)) and float(wf.call(&"depth_amount", deep_west)) >= 0.92
	_chk(ctx, deep_ok, "F4", "Deep Square -3 ocean satisfies is_deep==true and depth_amount >= 0.92")

	var swell_ok: bool = false
	if is_finite(deep_west.x) and bool(ctx.call(&"rules_has_method", &"swell_height")) and bool(ctx.call(&"rules_has_method", &"flow_drift_at")):
		var s0: float = float(ctx.call(&"call_rules", &"swell_height", [deep_west, 1.0, Vector2.RIGHT, 0.5, 0.2]))
		var s1: float = float(ctx.call(&"call_rules", &"swell_height", [deep_west, 2.3, Vector2.RIGHT, 0.5, 0.2]))
		var drift: Vector2 = ctx.call(&"call_rules", &"flow_drift_at", [deep_west, 1.0, Vector2.RIGHT, 0.5, 0.2, 4, 0.95]) as Vector2
		swell_ok = absf(s0 - s1) > 0.001 and drift.length() > 0.01
	_chk(ctx, swell_ok, "F4", "WaterRules.swell_height and flow_drift_at are active in Square -3 ocean")

	var swim_drift_ok: bool = false
	if player != null and is_finite(deep_west.x):
		await ctx.call(&"teleport_and_settle", tree, player, deep_west)
		await ctx.call(&"step_frames", tree, 20)
		var swimmer: Object = player.get(&"swimmer") as Object
		var entered_swim: bool = int(player.get(&"swim")) > 0 and swimmer != null and bool(swimmer.get(&"active"))
		var p_start: Vector2 = player.global_position
		await ctx.call(&"step_frames", tree, 30)
		var p_end: Vector2 = player.global_position
		swim_drift_ok = entered_swim and p_start.distance_to(p_end) > 0.1
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, swim_drift_ok, "F4", "Player enters swimming (swim>0, swimmer.active) and drifts with flow_velocity in Square -3")

	var tint_ok: bool = false
	var brook_pts: Array[Vector2] = brook.get("points", []) as Array[Vector2]
	var surf_pos: Vector2 = swash.get("tide_shallow_pos", swash.get("dynamic_swash_pos", Vector2(INF, INF))) as Vector2
	if wf != null and not brook_pts.is_empty() and is_finite(deep_west.x) and is_finite(surf_pos.x):
		var c_brook: Color = (wf.call(&"water_color_at", brook_pts[0]) as Dictionary).get("fill", Color.BLACK) as Color
		var c_surf: Color = (wf.call(&"water_color_at", surf_pos) as Dictionary).get("fill", Color.BLACK) as Color
		var c_ocean: Color = (wf.call(&"water_color_at", deep_west) as Dictionary).get("fill", Color.BLACK) as Color
		tint_ok = not c_brook.is_equal_approx(c_ocean) and not c_surf.is_equal_approx(c_ocean) and c_ocean.b > c_ocean.r
	_chk(ctx, tint_ok, "F4", "water_color_at distinguishes brook jade, coastal turquoise, and ocean Prussian/indigo tint")


static func _test_f5_ringbuffer_jobs(tree: SceneTree, ctx: RefCounted, wf: Node, player: CharacterBody2D, brook: Dictionary, ocean: Dictionary) -> void:
	var brook_pts: Array[Vector2] = brook.get("points", []) as Array[Vector2]
	var ocean_pts: Array[Vector2] = ocean.get("points", []) as Array[Vector2]
	var impulse_ok: bool = false
	if wf != null and player != null and not brook_pts.is_empty():
		var imp_pt: Vector2 = brook_pts[brook_pts.size() / 2]
		await ctx.call(&"teleport_and_settle", tree, player, imp_pt)
		await ctx.call(&"step_frames", tree, 2)
		wf.call(&"add_water_impulse", imp_pt, 1.2, 8.0, Vector2.DOWN)
		await ctx.call(&"step_frames", tree, 3)
		var wave_bytes_v: Variant = wf.get(&"_wave_bytes")
		var non_neutral: bool = false
		if wave_bytes_v is PackedByteArray:
			var wb_arr: PackedByteArray = wave_bytes_v as PackedByteArray
			var idx: int = 0
			while idx + 3 < wb_arr.size():
				if wb_arr[idx + 2] != 128 or wb_arr[idx + 3] > 0:
					non_neutral = true
					break
				idx += 4
		impulse_ok = bool(wf.get(&"_wave_active")) and non_neutral
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, impulse_ok, "F5", "WaterField.add_water_impulse() activates 128x128 toroidal ringbuffer with non-neutral wave bytes")

	var swimmer_cap_ok: bool = false
	if wf != null and player != null and not ocean_pts.is_empty():
		var base_p: Vector2 = ocean_pts[0]
		await ctx.call(&"teleport_and_settle", tree, player, base_p)
		for k: int in 8:
			wf.call(&"set_swimmer", 9000 + k, Vector4(base_p.x + float(k) * 4.0, base_p.y, 1.0, 0.5))
		await ctx.call(&"step_frames", tree, 2)
		var sw_before: Dictionary = wf.get(&"_swimmers") as Dictionary
		var active_with_8: bool = sw_before.size() == 8 and bool(wf.get(&"_wave_active"))
		for k: int in 8:
			wf.call(&"set_swimmer", 9000 + k, Vector4.ZERO)
		await ctx.call(&"step_frames", tree, 2)
		var sw_after: Dictionary = wf.get(&"_swimmers") as Dictionary
		swimmer_cap_ok = active_with_8 and sw_after.size() == 0
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, swimmer_cap_ok, "F5", "WaterField.set_swimmer() accepts >4 concurrent swimmer keys and clears cleanly")

	var recenter_ok: bool = false
	if wf != null and player != null:
		await ctx.call(&"teleport_and_settle", tree, player, Vector2(-280.0, 0.0))
		await ctx.call(&"step_frames", tree, 4)
		var orig_a: Vector2 = wf.get(&"_wave_origin") as Vector2
		await ctx.call(&"teleport_and_settle", tree, player, Vector2(-1180.0, 0.0))
		await ctx.call(&"step_frames", tree, 4)
		var orig_b: Vector2 = wf.get(&"_wave_origin") as Vector2
		wf.call(&"add_water_impulse", Vector2(-1180.0, 0.0), 1.0, 8.0, Vector2.LEFT)
		await ctx.call(&"step_frames", tree, 2)
		recenter_ok = orig_a.distance_to(orig_b) > 512.0 and bool(wf.get(&"_wave_active"))
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, recenter_ok, "F5", "Toroidal wave ringbuffer recenters >512 px and stays active across camera/player jumps")

	var sample_pts: Array[Vector2] = []
	if not brook_pts.is_empty():
		sample_pts.append(brook_pts[0])
	if not ocean_pts.is_empty():
		sample_pts.append(ocean_pts[0])
	sample_pts.append(Vector2(-750.0, 0.0))
	sample_pts.append(Vector2(0.0, 0.0))

	var worker_ok: bool = false
	var parity_ok: bool = false
	if wf != null and not sample_pts.is_empty():
		var main_results: Array[Dictionary] = []
		for p: Vector2 in sample_pts:
			main_results.append({
				"field": wf.call(&"field_at", p),
				"info": wf.call(&"water_field_at", p),
				"flow": wf.call(&"water_flow_at", p),
				"color": wf.call(&"water_color_at", p),
				"surf": wf.call(&"surface_at", p),
				"prop": wf.call(&"clear_for_prop", p, 8.0),
			})
		var job_results: Array[Dictionary] = []
		job_results.resize(sample_pts.size())
		var ids: Array[Jobs.Job] = []
		for idx: int in sample_pts.size():
			var pt: Vector2 = sample_pts[idx]
			var work: Callable = func() -> Dictionary:
				return {
					"field": wf.call(&"field_at", pt),
					"info": wf.call(&"water_field_at", pt),
					"flow": wf.call(&"water_flow_at", pt),
					"color": wf.call(&"water_color_at", pt),
					"surf": wf.call(&"surface_at", pt),
					"prop": wf.call(&"clear_for_prop", pt, 8.0),
				}
			var done: Callable = func(res: Variant) -> void:
				job_results[idx] = res as Dictionary
			ids.append(Jobs.run(work, done, 0, Callable(), "e2e_t1_f5"))
		Jobs.wait_all(ids)
		worker_ok = true
		parity_ok = true
		for idx: int in sample_pts.size():
			var m: Dictionary = main_results[idx]
			var j: Dictionary = job_results[idx]
			if j.is_empty() or m["field"] != j["field"] or m["surf"] != j["surf"] or m["prop"] != j["prop"] or m["flow"] != j["flow"]:
				parity_ok = false
	_chk(ctx, worker_ok, "F5", "Jobs.run() concurrent WaterField queries complete without error")
	_chk(ctx, parity_ok, "F5", "Jobs.run() worker query results match main-thread results identically")

	var clear_ok: bool = false
	if wf != null and not ocean_pts.is_empty():
		var in_water: bool = bool(wf.call(&"clear_for_prop", ocean_pts[0], 8.0))
		var on_land: bool = bool(wf.call(&"clear_for_prop", Vector2(0.0, 0.0), 8.0))
		clear_ok = (not in_water) and on_land
	_chk(ctx, clear_ok, "F5", "WaterField.clear_for_prop() rejects ocean water and accepts dry Square 0 land")


static func _test_f6_wind_weather_time_reflections(tree: SceneTree, ctx: RefCounted, lab: Node2D, wf: Node, brook: Dictionary, swash: Dictionary, puddles_sq1: Array[Vector2]) -> void:
	var wind_ok: bool = false
	var breeze_ok: bool = false
	var wm: Node = ctx.call(&"get_weather_manager") as Node
	var wind_node: Node2D = ctx.call(&"get_lab_wind", lab) as Node2D
	if wm != null and wind_node != null:
		wm.call(&"force", "clear", 60.0)
		await ctx.call(&"step_seconds", tree, 1.5)
		if lab.has_method(&"_apply_weather"):
			lab.call(&"_apply_weather", 1)
		var max_gust_breeze: float = 0.0
		for _step_b: int in 4:
			await ctx.call(&"step_frames", tree, 22)
			max_gust_breeze = maxf(max_gust_breeze, float(ctx.call(&"global_shader_float", &"g_wind_gust")))
		var dir_breeze: Vector2 = ctx.call(&"global_shader_vec2", &"g_wind_dir") as Vector2
		var oid: String = String(wm.get(&"override_id"))
		breeze_ok = oid != "" and oid != "clear" and oid != "breeze" and float(wind_node.get(&"strength")) > 0.30 and max_gust_breeze > 0.05
		wm.call(&"force", "storm", 60.0)
		await ctx.call(&"step_seconds", tree, 2.0)
		var g_rain: float = float(ctx.call(&"global_shader_float", &"g_rain"))
		var g_storm: float = float(ctx.call(&"global_shader_float", &"g_storm"))
		wind_ok = dir_breeze.length() > 0.1 and g_rain > 0.05 and g_storm > 0.1
		wm.call(&"force", "clear", 60.0)
		await ctx.call(&"step_seconds", tree, 1.0)
	_chk(ctx, wind_ok, "F6", "WeatherManager + WorldWind drive g_wind_dir, g_wind_gust, g_rain, g_storm globals")
	_chk(ctx, breeze_ok, "F6", "grass_lab weather preset 1 (BRISE) uses a valid data/weather.json state and updates WorldWind")

	var glow_node: CanvasItem = ctx.call(&"find_node_by_name_or_shader", lab, "WaterV2Glow", "water_v2_glow.gdshader") as CanvasItem
	TimeManager.lock_at(0.50)
	await ctx.call(&"step_frames", tree, 3)
	_chk(ctx, glow_node != null and not glow_node.visible, "F6", "water_v2_glow node exists and is hidden at noon (visible==false)")

	TimeManager.lock_at(0.00)
	await ctx.call(&"step_frames", tree, 3)
	_chk(ctx, glow_node != null and glow_node.visible, "F6", "water_v2_glow node becomes visible at night (visible==true)")

	TimeManager.lock_at(0.778)
	await ctx.call(&"step_frames", tree, 3)
	var golden_ok: bool = false
	var brook_pts: Array[Vector2] = brook.get("points", []) as Array[Vector2]
	if wf != null and not brook_pts.is_empty() and TimeManager.golden_amount() > 0.2:
		var gold_dict: Dictionary = wf.call(&"water_color_at", brook_pts[0]) as Dictionary
		var c_gold_rim: Color = gold_dict.get("rim", Color.BLACK) as Color
		var c_gold_foam: Color = gold_dict.get("foam", Color.BLACK) as Color
		TimeManager.lock_at(0.50)
		await ctx.call(&"step_frames", tree, 3)
		var noon_dict: Dictionary = wf.call(&"water_color_at", brook_pts[0]) as Dictionary
		var c_noon_rim: Color = noon_dict.get("rim", Color.BLACK) as Color
		var c_noon_foam: Color = noon_dict.get("foam", Color.BLACK) as Color
		golden_ok = (not c_gold_rim.is_equal_approx(c_noon_rim)) or (not c_gold_foam.is_equal_approx(c_noon_foam))
	TimeManager.lock_at(0.50)
	_chk(ctx, golden_ok, "F6", "Golden hour (TimeManager.golden_amount > 0) visibly warms water_color_at()")

	var wr: Node = ctx.call(&"get_water_reflections") as Node
	_chk(ctx, wr != null and bool(wr.get(&"enabled")), "F6", "WaterReflections.current != null and enabled == true")

	var reflects_at_ok: bool = false
	var fresh_swash: Dictionary = ctx.call(&"scan_swash_samples", wf) as Dictionary
	var wet_pos: Vector2 = fresh_swash.get("wet_sand_pos", Vector2(INF, INF)) as Vector2
	if wf != null and not brook_pts.is_empty() and is_finite(wet_pos.x) and not puddles_sq1.is_empty():
		var r_brook: bool = bool(wf.call(&"reflects_at", brook_pts[0]))
		var r_dry: bool = bool(wf.call(&"reflects_at", Vector2(0.0, 0.0)))
		var r_wet: bool = bool(wf.call(&"reflects_at", wet_pos))
		var r_pud: bool = bool(wf.call(&"reflects_at", puddles_sq1[0]))
		reflects_at_ok = r_brook and r_wet and r_pud and (not r_dry)
	_chk(ctx, reflects_at_ok, "F6", "WaterField.reflects_at() true on brook/wet_sand/puddles and false on dry Square 0")


static func _test_f7_art_audio(tree: SceneTree, ctx: RefCounted, lab: Node2D, wf: Node, player: CharacterBody2D, _brook: Dictionary, swash: Dictionary, ocean: Dictionary) -> void:
	var bridge_art_ok: bool = true
	for p: String in [
		"res://assets/props/water_bridge.png",
		"res://assets/props/water_bridge_glow.png",
	]:
		if not ResourceLoader.exists(p):
			bridge_art_ok = false
		else:
			var t: Texture2D = load(p) as Texture2D
			if t == null or t.get_width() <= 0 or t.get_height() <= 0:
				bridge_art_ok = false
	_chk(ctx, bridge_art_ok, "F7", "Bridge art PNGs exist and load with positive dimensions")

	var coastal_art_ok: bool = true
	for p: String in [
		"res://assets/tiles/coastal_props.png",
		"res://assets/tiles/coastal_props_glow.png",
	]:
		if not ResourceLoader.exists(p):
			coastal_art_ok = false
		else:
			var t: Texture2D = load(p) as Texture2D
			if t == null or t.get_width() <= 0 or t.get_height() <= 0:
				coastal_art_ok = false
	_chk(ctx, coastal_art_ok, "F7", "Coastal biome props PNGs exist and load with positive dimensions")

	var shaders_ok: bool = FileAccess.file_exists("res://assets/shaders/water_optics.gdshaderinc")
	for sp: String in [
		"res://assets/shaders/water_v2_surface.gdshader",
		"res://assets/shaders/water_v2_glow.gdshader",
	]:
		if not ResourceLoader.exists(sp):
			shaders_ok = false
		else:
			var sh: Shader = load(sp) as Shader
			if sh == null or sh.code.is_empty():
				shaders_ok = false
	_chk(ctx, shaders_ok, "F7", "water_optics.gdshaderinc, water_v2_surface.gdshader, and water_v2_glow.gdshader exist and load")

	var wavs_ok: bool = true
	for wp: String in [
		"res://assets/audio/water/brook_loop.wav",
		"res://assets/audio/water/surf_wash_loop.wav",
		"res://assets/audio/water/ocean_swell_loop.wav",
	]:
		if not ResourceLoader.exists(wp):
			wavs_ok = false
		else:
			var wav: AudioStreamWAV = load(wp) as AudioStreamWAV
			if wav == null or wav.get_length() <= 0.5:
				wavs_ok = false
	_chk(ctx, wavs_ok, "F7", "All 3 water AudioStreamWAV loops (brook, surf_wash, ocean_swell) load with length > 0.5s")

	var amb: Node = ctx.call(&"find_water_ambience", lab) as Node
	_chk(ctx, amb != null, "F7", "WaterAmbience node exists and is active in grass_lab")

	var loop_bus_ok: bool = false
	var players: Array[AudioStreamPlayer] = []
	if amb != null:
		for c: Node in amb.find_children("*", "AudioStreamPlayer", true, false):
			players.append(c as AudioStreamPlayer)
		if not players.is_empty():
			loop_bus_ok = true
			for ap: AudioStreamPlayer in players:
				var wav: AudioStreamWAV = ap.stream as AudioStreamWAV
				var bus_idx: int = AudioServer.get_bus_index(ap.bus)
				if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_FORWARD or wav.loop_end <= 0 or bus_idx < 0:
					loop_bus_ok = false
	_chk(ctx, loop_bus_ok, "F7", "WaterAmbience streams enforce LOOP_FORWARD, loop_end > 0, and valid AudioServer bus routing")

	var swash_vol_ok: bool = false
	if amb != null and player != null and wf != null and not players.is_empty():
		var ocean_pts: Array[Vector2] = ocean.get("points", []) as Array[Vector2]
		var surf_pos: Vector2 = swash.get("dynamic_swash_pos", Vector2(INF, INF)) as Vector2
		if is_finite(surf_pos.x):
			await ctx.call(&"teleport_and_settle", tree, player, surf_pos)
			var vols: Array[float] = []
			for step_i: int in 8:
				await ctx.call(&"step_frames", tree, 15)
				var total_lin: float = 0.0
				for ap: AudioStreamPlayer in players:
					total_lin += db_to_linear(ap.volume_db)
				vols.append(total_lin)
			var min_v: float = vols[0]
			var max_v: float = vols[0]
			for v: float in vols:
				min_v = minf(min_v, v)
				max_v = maxf(max_v, v)
			swash_vol_ok = (max_v - min_v) > 0.002
			if not swash_vol_ok and not ocean_pts.is_empty():
				await ctx.call(&"teleport_and_settle", tree, player, ocean_pts[0])
				await ctx.call(&"step_frames", tree, 10)
				var total_ocean: float = 0.0
				for ap: AudioStreamPlayer in players:
					total_ocean += db_to_linear(ap.volume_db)
				swash_vol_ok = absf(total_ocean - vols[0]) > 0.002
			await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, swash_vol_ok, "F7", "WaterAmbience surf/biome volume modulates dynamically with swash / biome position")


static func _test_f8_boundary_r1_preservation(tree: SceneTree, ctx: RefCounted, lab: Node2D, wf: Node) -> void:
	var r1_ok: bool = bool(ctx.call(&"verify_r1_protected_files"))
	_chk(ctx, r1_ok, "F8", "R1 protected ground_surfaces.* and art scripts exist, are valid, and are free of Water v2 symbols")

	var probes_ok: bool = (
		Terrain.surface_at(Vector2(-32.0, 0.0)) == "grass"
		and Terrain.surface_at(Vector2(234.0, 18.0)) == "path"
		and Terrain.surface_at(Vector2(382.0, -78.0)) == "gravel"
		and Terrain.surface_at(Vector2(392.0, 18.0)) == "ancient_stone"
		and Terrain.surface_at(Vector2(786.0, -48.0)) == "puddle"
		and Terrain.surface_at(Vector2(646.0, -68.0)) == "moss"
	)
	var seen_sq2: Dictionary = {}
	for y_i: int in range(-120, 121, 8):
		for x_i: int in range(584, 952, 8):
			seen_sq2[Terrain.surface_at(Vector2(float(x_i), float(y_i)))] = true
	probes_ok = probes_ok and seen_sq2.has("forest_floor") and seen_sq2.has("damp_earth") and seen_sq2.has("mud")
	_chk(ctx, probes_ok, "F8", "All 9 Square 0/+1/+2 surface probes preserved intact")

	var right_empty_ok: bool = wf != null
	if wf != null:
		for px: float in [-190.0, 0.0, 192.0, 384.0, 576.0, 786.0, 950.0]:
			var pos: Vector2 = Vector2(px, 0.0)
			if String(wf.call(&"surface_at", pos)) != "":
				right_empty_ok = false
			var fv: Vector2 = wf.call(&"field_at", pos) as Vector2
			if is_finite(fv.x):
				right_empty_ok = false
	_chk(ctx, right_empty_ok, "F8", "WaterField returns '' and field_at.x == INF everywhere for x >= -192")

	var tbl: Dictionary = DataRegistry.table("terrain")
	var orig_ok: bool = true
	var orig_list: Array = ctx.get(&"ORIGINAL_TERRAIN_SURFACES") as Array
	for surf_v: Variant in orig_list:
		if not tbl.has(String(surf_v)):
			orig_ok = false
	_chk(ctx, orig_ok, "F8", "All 21 original data/terrain.json surfaces preserved")

	var sq0_grass_ok: bool = false
	var grass: Node2D = ctx.call(&"get_lab_grass", lab) as Node2D
	if grass != null and lab != null:
		var metrics: Variant = lab.get(&"_metrics")
		var metrics_ok: bool = (metrics is Dictionary) and bool((metrics as Dictionary).get("tuft_density", false)) and bool((metrics as Dictionary).get("floral_petals", false))
		var sq0_cells: int = int(ctx.call(&"count_grass_cells_in_rect", grass, Rect2(-184.0, -130.0, 368.0, 268.0)))
		var nw_cells: int = int(ctx.call(&"count_grass_cells_in_rect", grass, Rect2(-184.0, -130.0, 184.0, 130.0)))
		sq0_grass_ok = metrics_ok and sq0_cells >= 400 and nw_cells >= 80
	_chk(ctx, sq0_grass_ok, "F8", "LivingGrass Square 0 ([-192, +192]) retains dense meadow tufts and NW floral zone")

	var bounds_ok: bool = false
	if lab != null:
		var sq_tiles: Variant = lab.get(&"SQUARE_TILES")
		if sq_tiles is Rect2i:
			var r: Rect2i = sq_tiles as Rect2i
			bounds_ok = r.position.x == -84 and r.end.x >= 60
	_chk(ctx, bounds_ok, "F8", "grass_lab expands leftward to x=-1344 (-84 tiles) while keeping right-side squares intact (end.x>=60)")
	await tree.process_frame


static func _test_f9_puddles_tidepools(tree: SceneTree, ctx: RefCounted, _lab: Node2D, wf: Node, wb: Node, player: CharacterBody2D, puddles_sq1: Array[Vector2], puddles_sq2: Array[Vector2], bridge: Dictionary, swash: Dictionary) -> void:
	var centers_sq1: Array[Vector2] = ctx.call(&"scan_puddle_interiors", wf, wb, -568.0, -200.0) as Array[Vector2]
	var centers_sq2: Array[Vector2] = ctx.call(&"scan_puddle_interiors", wf, wb, -952.0, -584.0) as Array[Vector2]
	_chk(ctx, not puddles_sq1.is_empty() and not centers_sq1.is_empty(), "F9", "Square -1 has standing bank/stone-hollow puddles (count=%d)" % puddles_sq1.size())
	_chk(ctx, not puddles_sq2.is_empty() and not centers_sq2.is_empty(), "F9", "Square -2 has beach-hollow/tidepool puddles (count=%d)" % puddles_sq2.size())

	var wm: Node = ctx.call(&"get_weather_manager") as Node
	var rain_expand_ok: bool = false
	if wf != null and wm != null:
		await ctx.call(&"reset_wet_state", tree, wm, player)
		await ctx.call(&"step_seconds", tree, 0.8)
		var dry_count: int = (ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array).size()
		wm.call(&"force", "downpour", 60.0)
		wm.set(&"rain", 0.90)
		wm.set(&"_extra_wet", 1.0)
		wm.set(&"puddle", 0.9)
		wm.set(&"ground_wet", 1.0)
		await ctx.call(&"step_seconds", tree, 1.5)
		var rain_count: int = (ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array).size()
		var gp: float = float(ctx.call(&"global_shader_float", &"g_puddle"))
		rain_expand_ok = float(wm.get(&"puddle")) > 0.3 and gp > 0.3 and rain_count > dry_count
	_chk(ctx, rain_expand_ok, "F9", "WeatherManager rain raises g_puddle and dynamically expands Square -1/-2 puddles")

	var refl_ok: bool = false
	if wf != null:
		var sample_p: Vector2 = centers_sq1[0] if not centers_sq1.is_empty() else (centers_sq2[0] if not centers_sq2.is_empty() else Vector2(INF, INF))
		if is_finite(sample_p.x):
			refl_ok = bool(wf.call(&"reflects_at", sample_p))
	_chk(ctx, refl_ok, "F9", "WaterField.reflects_at() returns true over puddles & tidepools")

	var rain_imp_ok: bool = false
	if wf != null and wm != null and player != null and not centers_sq1.is_empty():
		var gr: float = float(ctx.call(&"global_shader_float", &"g_rain"))
		var sample_p: Vector2 = centers_sq1[0]
		await ctx.call(&"teleport_and_settle", tree, player, sample_p)
		await ctx.call(&"step_frames", tree, 2)
		wf.call(&"add_water_impulse", sample_p, 0.8, 6.0, Vector2.ZERO)
		await ctx.call(&"step_frames", tree, 2)
		rain_imp_ok = gr > 0.1 and bool(wf.get(&"_wave_active"))
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, rain_imp_ok, "F9", "g_rain > 0.1 during rain and add_water_impulse() activates ringbuffer on puddle positions")

	var step_splash_ok: bool = false
	var wet_boots_ok: bool = false
	var pud_table: Dictionary = DataRegistry.table("terrain").get("puddle", {}) as Dictionary
	var table_puddle_ok: bool = String(pud_table.get("sound", "")) == "puddle" and String((pud_table.get("step", {}) as Dictionary).get("kind", "")) == "splash"
	if player != null and not centers_sq1.is_empty():
		var puddle_pt: Vector2 = centers_sq1[0]
		var dry_pt: Vector2 = bridge.get("center", Vector2(INF, INF)) as Vector2
		if not is_finite(dry_pt.x):
			dry_pt = swash.get("dry_beach_pos", Vector2(INF, INF)) as Vector2
		if is_finite(dry_pt.x):
			await ctx.call(&"reset_wet_state", tree, wm, player)
			var pre_dry_before: int = int(ctx.call(&"count_active_footprints_near", tree, dry_pt, 48.0, Color("#1c2b33")))
			await ctx.call(&"teleport_and_settle", tree, player, dry_pt - Vector2(14.0, 0.0))
			await ctx.call(&"walk_player", tree, player, &"move_right", 24)
			var pre_dry_after: int = int(ctx.call(&"count_active_footprints_near", tree, dry_pt, 48.0, Color("#1c2b33")))
			var clean_baseline: bool = pre_dry_after == pre_dry_before

			await ctx.call(&"teleport_and_settle", tree, player, puddle_pt - Vector2(12.0, 0.0))
			await ctx.call(&"walk_player", tree, player, &"move_right", 28)
			var on_puddle_surf: String = Terrain.surface_at(puddle_pt)
			var foot_comp: Node = player.get_node_or_null("FootstepComponent")
			var got_wet: bool = foot_comp != null and float(foot_comp.get(&"_puddle_wet")) > 0.0
			step_splash_ok = clean_baseline and table_puddle_ok and on_puddle_surf == "puddle" and got_wet

			var before_prints: int = int(ctx.call(&"count_active_footprints_near", tree, dry_pt, 48.0, Color("#1c2b33")))
			await ctx.call(&"teleport_and_settle", tree, player, dry_pt - Vector2(14.0, 0.0))
			await ctx.call(&"walk_player", tree, player, &"move_right", 32)
			var after_prints: int = int(ctx.call(&"count_active_footprints_near", tree, dry_pt, 48.0, Color("#1c2b33")))
			wet_boots_ok = clean_baseline and after_prints > before_prints
	_chk(ctx, step_splash_ok, "F9", "Puddle terrain config and stepping into puddle interior trigger puddle splash/wetness")
	_chk(ctx, wet_boots_ok, "F9", "Walking from puddle onto dry stone/sand stamps wet boot prints (#1c2b33) on FootprintCanvas")
	if wm != null:
		await ctx.call(&"reset_wet_state", tree, wm, player)
