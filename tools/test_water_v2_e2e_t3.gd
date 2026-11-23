extends RefCounted
## Tier 3 — Cross-Feature Pairwise Combinations (>=16 pairwise tests).


static func _chk(ctx: RefCounted, cond: bool, area: String, msg: String) -> bool:
	return bool(ctx.call(&"check", cond, area, msg))


static func run(tree: SceneTree, ctx: RefCounted) -> void:
	ctx.call(&"set_tier", "T3")
	var lab: Node2D = await ctx.call(&"host_and_spawn_lab", tree) as Node2D
	var wf: Node = ctx.call(&"find_water_field") as Node
	var wb: Node = ctx.call(&"find_water_bridge") as Node
	var player: CharacterBody2D = ctx.call(&"get_lab_player", lab) as CharacterBody2D

	var brook: Dictionary = ctx.call(&"scan_brook_samples", wf, wb) as Dictionary
	var bridge: Dictionary = ctx.call(&"scan_bridge_samples", wf, wb) as Dictionary
	var swash: Dictionary = ctx.call(&"scan_swash_samples", wf) as Dictionary
	var ocean: Dictionary = ctx.call(&"scan_ocean_samples", wf) as Dictionary
	var puddles_sq1: Array[Vector2] = ctx.call(&"scan_puddle_interiors", wf, wb, -568.0, -200.0) as Array[Vector2]
	var puddles_sq2: Array[Vector2] = ctx.call(&"scan_puddle_interiors", wf, wb, -952.0, -584.0) as Array[Vector2]

	var wm: Node = ctx.call(&"get_weather_manager") as Node
	var wr: Node = ctx.call(&"get_water_reflections") as Node

	# 1. Wind x Swash reach
	var p1: bool = false
	if bool(ctx.call(&"rules_has_method", &"swash_offset_px")):
		var calm_max: float = -INF
		var gale_max: float = -INF
		for i: int in 60:
			var tv: float = float(i) * 0.1
			calm_max = maxf(calm_max, float(ctx.call(&"call_rules", &"swash_offset_px", [0.0, tv, Vector2.RIGHT, 0.1, 0.0])))
			gale_max = maxf(gale_max, float(ctx.call(&"call_rules", &"swash_offset_px", [0.0, tv, Vector2.RIGHT, 0.95, 0.8])))
		p1 = gale_max > calm_max
	_chk(ctx, p1, "T3_WindSwash", "Wind x Swash: gale/storm wind extends swash run-up reach beyond calm")

	# 2. Wind x Ocean swell/whitecaps
	var p2: bool = false
	if bool(ctx.call(&"rules_has_method", &"swell_height")) and wm != null:
		wm.call(&"force", "storm", 60.0)
		await ctx.call(&"step_seconds", tree, 1.8)
		var g_gust: float = float(ctx.call(&"global_shader_float", &"g_wind_gust"))
		var g_storm: float = float(ctx.call(&"global_shader_float", &"g_storm"))
		var s_calm: float = float(ctx.call(&"call_rules", &"swell_height", [Vector2(-1150.0, 0.0), 1.5, Vector2.RIGHT, 0.1, 0.0]))
		var s_storm: float = float(ctx.call(&"call_rules", &"swell_height", [Vector2(-1150.0, 0.0), 1.5, Vector2.RIGHT, g_gust, g_storm]))
		p2 = g_storm > 0.2 and not is_equal_approx(s_calm, s_storm)
		wm.call(&"force", "clear", 60.0)
		await ctx.call(&"step_seconds", tree, 0.8)
	_chk(ctx, p2, "T3_WindOcean", "Wind x Ocean: storm forcing elevates g_storm/g_wind_gust and alters swell_height")

	# 3. Bridge water_deck x river_depth
	var p3: bool = false
	var over_water: Vector2 = bridge.get("deck_over_water_pos", Vector2(INF, INF)) as Vector2
	if player != null and wb != null and wf != null and is_finite(over_water.x):
		var wall: StaticBody2D = StaticBody2D.new()
		wall.add_to_group("river_depth")
		var cs: CollisionShape2D = CollisionShape2D.new()
		var rs: RectangleShape2D = RectangleShape2D.new()
		rs.size = Vector2(20.0, 20.0)
		cs.shape = rs
		wall.add_child(cs)
		wall.position = over_water + Vector2(60.0, 0.0)
		lab.add_child(wall)
		await ctx.call(&"teleport_and_settle", tree, player, over_water)
		await ctx.call(&"step_frames", tree, 6)
		var swimmer: Object = player.get(&"swimmer") as Object
		var exc_n: int = int(swimmer.call(&"exception_count")) if swimmer != null and swimmer.has_method(&"exception_count") else 0
		var patch_order_ok: bool = int(ctx.call(&"patch_index", wb)) > int(ctx.call(&"patch_index", wf))
		p3 = patch_order_ok and player.has_meta(&"water_deck") and int(player.get(&"swim")) == SwimRules.NONE and exc_n > 0
		wall.queue_free()
		await ctx.call(&"step_frames", tree, 2)
	_chk(ctx, p3, "T3_BridgeDepth", "Bridge water_deck x river_depth: patch order and Player._physics_process retain river_depth exceptions")

	# 4. Bridge Piers x Flow/Obstacles
	var p4: bool = false
	var b_center: Vector2 = bridge.get("center", Vector2(INF, INF)) as Vector2
	if wf != null and wb != null and is_finite(b_center.x):
		var min_y: float = float(bridge.get("min_y", b_center.y - 12.0))
		var max_y: float = float(bridge.get("max_y", b_center.y + 12.0))
		var min_x: float = float(bridge.get("min_x", b_center.x - 32.0))
		var max_x: float = float(bridge.get("max_x", b_center.x + 32.0))
		var has_shadow: bool = false
		var has_turb: bool = false
		var sy: float = min_y - 24.0
		while sy <= max_y + 24.0:
			var sx: float = min_x - 8.0
			while sx <= max_x + 8.0:
				var winfo: Dictionary = wf.call(&"water_field_at", Vector2(sx, sy)) as Dictionary
				if float(winfo.get("shadow", 0.0)) > 0.2:
					has_shadow = true
				if float(winfo.get("turbulence", 0.0)) > 0.05:
					has_turb = true
				sx += 4.0
			sy += 4.0
		var f_up: Vector2 = wf.call(&"water_flow_at", Vector2(b_center.x, min_y - 28.0)) as Vector2
		var f_pier: Vector2 = wf.call(&"water_flow_at", b_center) as Vector2
		p4 = f_up.length() > 0.0 and has_shadow and has_turb and f_up.distance_to(f_pier) > 0.2
	_chk(ctx, p4, "T3_BridgeFlow", "Bridge Piers x Flow: shadow/turbulence injected and water_flow_at responds around bridge")

	# 5. Time-of-Day (Noon vs Night) x Glow Visibility (Water + Lantern)
	var p5: bool = false
	var glow_node: CanvasItem = ctx.call(&"find_node_by_name_or_shader", lab, "WaterV2Glow", "water_v2_glow.gdshader") as CanvasItem
	if glow_node != null and wb != null and player != null and is_finite(b_center.x):
		await ctx.call(&"teleport_and_settle", tree, player, b_center)
		await ctx.call(&"lock_time_and_settle_lights", tree, 0.50)
		var day_water_off: bool = not glow_node.visible
		var day_lantern_off: bool = bool(ctx.call(&"check_bridge_lanterns", wb, false))
		await ctx.call(&"lock_time_and_settle_lights", tree, 0.00)
		var night_water_on: bool = glow_node.visible
		var night_lantern_on: bool = bool(ctx.call(&"check_bridge_lanterns", wb, true))
		p5 = day_water_off and day_lantern_off and night_water_on and night_lantern_on
		TimeManager.lock_at(0.50)
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, p5, "T3_TimeGlow", "Time-of-Day x Glow: noon hides water_v2_glow/lantern; night activates both")

	# 6. Time-of-Day (Golden) x Water Color & Reflections
	var p6: bool = false
	var brook_pts: Array[Vector2] = brook.get("points", []) as Array[Vector2]
	if wf != null and not brook_pts.is_empty():
		TimeManager.lock_at(0.50)
		await ctx.call(&"step_frames", tree, 3)
		var noon_d: Dictionary = wf.call(&"water_color_at", brook_pts[0]) as Dictionary
		var c_noon_rim: Color = noon_d.get("rim", Color.BLACK) as Color
		var c_noon_foam: Color = noon_d.get("foam", Color.BLACK) as Color
		TimeManager.lock_at(0.778)
		await ctx.call(&"step_frames", tree, 3)
		var gold_d: Dictionary = wf.call(&"water_color_at", brook_pts[0]) as Dictionary
		var c_gold_rim: Color = gold_d.get("rim", Color.BLACK) as Color
		var c_gold_foam: Color = gold_d.get("foam", Color.BLACK) as Color
		p6 = ((not c_noon_rim.is_equal_approx(c_gold_rim)) or (not c_noon_foam.is_equal_approx(c_gold_foam))) and wr != null and bool(wr.get(&"enabled"))
		TimeManager.lock_at(0.50)
		await ctx.call(&"step_frames", tree, 2)
	_chk(ctx, p6, "T3_GoldenColor", "Golden Hour x Water Color & Reflections: golden tint warms rim/foam while reflections stay active")

	# 7. Time-of-Day (Night) x Puddle Reflection & Glow
	var p7: bool = false
	if wf != null and glow_node != null and not puddles_sq1.is_empty():
		TimeManager.lock_at(0.00)
		await ctx.call(&"step_frames", tree, 2)
		p7 = bool(wf.call(&"reflects_at", puddles_sq1[0])) and glow_node.visible
		TimeManager.lock_at(0.50)
	_chk(ctx, p7, "T3_NightPuddle", "Night x Puddle Reflection & Glow: nocturnal puddles reflect while night glow is active")

	# 8. Rain / g_puddle x Puddle Expansion & g_rain
	var p8: bool = false
	if wf != null and wm != null:
		await ctx.call(&"reset_wet_state", tree, wm, player)
		await ctx.call(&"step_seconds", tree, 0.8)
		var n_dry: int = (ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array).size()
		wm.call(&"force", "downpour", 60.0)
		wm.set(&"rain", 0.90)
		wm.set(&"_extra_wet", 1.0)
		wm.set(&"puddle", 0.9)
		wm.set(&"ground_wet", 1.0)
		await ctx.call(&"step_seconds", tree, 1.5)
		var n_rain: int = (ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array).size()
		p8 = float(ctx.call(&"global_shader_float", &"g_rain")) > 0.1 and float(ctx.call(&"global_shader_float", &"g_puddle")) > 0.3 and n_rain > n_dry
		await ctx.call(&"reset_wet_state", tree, wm, player)
	_chk(ctx, p8, "T3_RainPuddle", "Rain x Puddle Expansion: g_rain & g_puddle rise together and expand puddles")

	# 9. Puddle x Dry Ancient Stone (Wet Boots)
	var p9: bool = false
	if player != null and not puddles_sq1.is_empty() and is_finite(b_center.x):
		await ctx.call(&"reset_wet_state", tree, wm, player)
		var pre_s_before: int = int(ctx.call(&"count_active_footprints_near", tree, b_center, 48.0, Color("#1c2b33")))
		await ctx.call(&"teleport_and_settle", tree, player, b_center - Vector2(12.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 24)
		var pre_s_after: int = int(ctx.call(&"count_active_footprints_near", tree, b_center, 48.0, Color("#1c2b33")))
		var clean_pre: bool = pre_s_after == pre_s_before

		await ctx.call(&"teleport_and_settle", tree, player, puddles_sq1[0] - Vector2(12.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 28)
		var before: int = int(ctx.call(&"count_active_footprints_near", tree, b_center, 48.0, Color("#1c2b33")))
		await ctx.call(&"teleport_and_settle", tree, player, b_center - Vector2(12.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 30)
		var after: int = int(ctx.call(&"count_active_footprints_near", tree, b_center, 48.0, Color("#1c2b33")))
		p9 = clean_pre and after > before
	_chk(ctx, p9, "T3_PuddleStone", "Puddle x Dry Ancient Stone: wet boots stamp #1c2b33 footprints onto bridge stone")

	# 10. Puddle x Dry Beach Sand (Wet Boots)
	var p10: bool = false
	var dry_beach: Vector2 = ctx.call(&"find_dry_land_in_rect", wf, wb, Rect2(-695.0, -40.0, 90.0, 60.0)) as Vector2
	if not is_finite(dry_beach.x):
		dry_beach = swash.get("dry_beach_pos", Vector2(INF, INF)) as Vector2
	if player != null and not puddles_sq2.is_empty() and is_finite(dry_beach.x):
		await ctx.call(&"reset_wet_state", tree, wm, player)
		var pre_b_before: int = int(ctx.call(&"count_active_footprints_near", tree, dry_beach, 48.0, Color("#1c2b33")))
		await ctx.call(&"teleport_and_settle", tree, player, dry_beach - Vector2(12.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 24)
		var pre_b_after: int = int(ctx.call(&"count_active_footprints_near", tree, dry_beach, 48.0, Color("#1c2b33")))
		var clean_pre_s: bool = pre_b_after == pre_b_before

		await ctx.call(&"teleport_and_settle", tree, player, puddles_sq2[0] - Vector2(12.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 28)
		var before_s: int = int(ctx.call(&"count_active_footprints_near", tree, dry_beach, 48.0, Color("#1c2b33")))
		await ctx.call(&"teleport_and_settle", tree, player, dry_beach - Vector2(12.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 30)
		var after_s: int = int(ctx.call(&"count_active_footprints_near", tree, dry_beach, 48.0, Color("#1c2b33")))
		p10 = clean_pre_s and after_s > before_s
		await ctx.call(&"reset_wet_state", tree, wm, player)
	_chk(ctx, p10, "T3_PuddleSand", "Puddle x Dry Beach Sand: wet boots from Square -2 tidepool stamp #1c2b33 prints onto sand")

	# 11. Wading (Ford) x Ringbuffer Impulses x Reflections
	var p11: bool = false
	var ford_pos: Vector2 = brook.get("south_ford_pos", Vector2(INF, INF)) as Vector2
	if wf != null and player != null and is_finite(ford_pos.x):
		await ctx.call(&"teleport_and_settle", tree, player, ford_pos - Vector2(12.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 24)
		await ctx.call(&"step_frames", tree, 4)
		var wave_bytes_v: Variant = wf.get(&"_wave_bytes")
		var non_neutral_wade: bool = false
		if wave_bytes_v is PackedByteArray:
			var wb_arr: PackedByteArray = wave_bytes_v as PackedByteArray
			var b_idx: int = 0
			while b_idx + 3 < wb_arr.size():
				if wb_arr[b_idx + 2] != 128 or wb_arr[b_idx + 3] > 0:
					non_neutral_wade = true
					break
				b_idx += 4
		var refl_active: bool = wr != null and bool(wr.get(&"enabled")) and bool(wr.get(&"_on"))
		p11 = bool(wf.get(&"_wave_active")) and non_neutral_wade and bool(wf.call(&"reflects_at", ford_pos)) and refl_active
	_chk(ctx, p11, "T3_WadeImpulseRefl", "Wading x Ringbuffer Impulses x Reflections: ford wade activates ringbuffer and WaterReflections")

	# 12. Swimming (Ocean) x Ringbuffer Swimmer Slot x Flow Drift
	var p12: bool = false
	var deep_west: Vector2 = ocean.get("deep_west_pos", Vector2(INF, INF)) as Vector2
	if wf != null and player != null and is_finite(deep_west.x):
		await ctx.call(&"teleport_and_settle", tree, player, deep_west)
		await ctx.call(&"step_frames", tree, 20)
		var p_a: Vector2 = player.global_position
		await ctx.call(&"step_frames", tree, 25)
		var p_b: Vector2 = player.global_position
		var swimmer2: Object = player.get(&"swimmer") as Object
		p12 = int(player.get(&"swim")) > 0 and swimmer2 != null and bool(swimmer2.get(&"active")) and p_a.distance_to(p_b) > 0.1
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, p12, "T3_SwimDrift", "Swimming x Swimmer Slot x Flow Drift: Square -3 swimmer drifts passively with current")

	# 13. Biome Adaptive Color x WaterOverlay / SwimWater
	var p13: bool = false
	var surf_pos: Vector2 = swash.get("tide_shallow_pos", swash.get("dynamic_swash_pos", Vector2(INF, INF))) as Vector2
	if wf != null and player != null and is_finite(ford_pos.x) and is_finite(deep_west.x) and is_finite(surf_pos.x):
		var c_ford: Color = (wf.call(&"water_color_at", ford_pos) as Dictionary).get("fill", Color.BLACK) as Color
		var c_sea: Color = (wf.call(&"water_color_at", deep_west) as Dictionary).get("fill", Color.BLACK) as Color
		await ctx.call(&"teleport_and_settle", tree, player, ford_pos)
		await ctx.call(&"step_frames", tree, 16)
		var wo: Node = player.get_node_or_null("WaterOverlay")
		var sw: Node = player.get_node_or_null("SwimWater")
		var wo_sub: float = float(wo.get(&"submerge")) if wo != null else 0.0
		var wo_ford_col: Color = _read_fx_color(wo)
		await ctx.call(&"teleport_and_settle", tree, player, deep_west)
		await ctx.call(&"step_frames", tree, 20)
		var sw_sea_col: Color = _read_fx_color(sw)
		var fallback_col: Color = Color("438780")
		var fx_color_adapted: bool = (
			wo_ford_col.a > 0.0 and sw_sea_col.a > 0.0
			and wo_ford_col.is_equal_approx(c_ford)
			and (not wo_ford_col.is_equal_approx(fallback_col))
			and sw_sea_col.is_equal_approx(c_sea)
			and (not sw_sea_col.is_equal_approx(fallback_col))
			and (not wo_ford_col.is_equal_approx(sw_sea_col))
		)
		p13 = (not c_ford.is_equal_approx(c_sea)) and wo_sub > 0.0 and int(player.get(&"swim")) > 0 and fx_color_adapted
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, p13, "T3_BiomePlayerFX", "Biome Color x WaterOverlay/SwimWater: distinct brook vs ocean color drives player water FX")

	# 14. LivingGrass x Brook & Puddles
	var p14: bool = false
	var grass: Node2D = ctx.call(&"get_lab_grass", lab) as Node2D
	if grass != null and wf != null:
		var brook_checked: int = 0
		var checked_samples: int = 0
		var grass_hits: int = 0
		for bp: Vector2 in brook_pts:
			if bp.y < -120.0 or bp.y > 120.0:
				continue
			var binfo: Dictionary = wf.call(&"water_field_at", bp) as Dictionary
			if float(binfo.get("static_sdf_px", 0.0)) <= -12.0:
				brook_checked += 1
				checked_samples += 1
				if bool(ctx.call(&"has_grass_cell_at", grass, bp)):
					grass_hits += 1
		for pp: Vector2 in puddles_sq1:
			var pinfo: Dictionary = wf.call(&"water_field_at", pp) as Dictionary
			if float(pinfo.get("static_sdf_px", 0.0)) <= -7.0:
				checked_samples += 1
				if bool(ctx.call(&"has_grass_cell_at", grass, pp)):
					grass_hits += 1
		var r3_pts: Array[Vector2] = swash.get("regime3_points", []) as Array[Vector2]
		var r3_checked: int = 0
		for sp: Vector2 in r3_pts:
			if sp.y < -40.0 or sp.y > 90.0:
				continue
			var s_str: String = String(wf.call(&"surface_at", sp))
			if s_str == "wet_sand" or s_str == "tide_shallow":
				r3_checked += 1
				checked_samples += 1
				if bool(ctx.call(&"has_grass_cell_at", grass, sp)):
					grass_hits += 1
				if r3_checked >= 6:
					break
		p14 = brook_checked >= 5 and checked_samples >= 10 and grass_hits == 0
	_chk(ctx, p14, "T3_GrassWaterClear", "LivingGrass x Brook/Puddles/WetSand: >=5 deep brook & >=10 total interior samples have zero grass")

	# 15. LivingGrass x Coastal Dunes & Wet Swash
	var p15: bool = false
	var fresh_swash: Dictionary = ctx.call(&"scan_swash_samples", wf) as Dictionary
	var wet_pos: Vector2 = fresh_swash.get("wet_sand_pos", Vector2(INF, INF)) as Vector2
	if grass != null and is_finite(wet_pos.x):
		var dune_n: int = int(ctx.call(&"count_grass_cells_in_rect", grass, Rect2(-710.0, -120.0, 130.0, 240.0)))
		var wet_clear: bool = not bool(ctx.call(&"has_grass_cell_at", grass, wet_pos))
		p15 = dune_n > 0 and wet_clear
	_chk(ctx, p15, "T3_GrassDunes", "LivingGrass x Coastal Dunes: dune oats grow on Square -2 dunes while wet_sand is clear")

	# 16. LivingGrass x Square 0 Preservation
	var p16: bool = false
	if grass != null:
		var sq0_n: int = int(ctx.call(&"count_grass_cells_in_rect", grass, Rect2(-184.0, -130.0, 368.0, 268.0)))
		p16 = sq0_n >= 400
	_chk(ctx, p16, "T3_GrassSq0", "LivingGrass x Left Expansion: Square 0 retains dense meadow tufts")

	# 17. WorldWind x WeatherManager Convergence
	var p17: bool = false
	var wind_n: Node2D = ctx.call(&"get_lab_wind", lab) as Node2D
	if wm != null and wind_n != null:
		wm.call(&"force", "storm", 60.0)
		await ctx.call(&"step_seconds", tree, 1.8)
		var s_hi: float = float(ctx.call(&"global_shader_float", &"g_storm"))
		var w_storm_hi: float = float(wind_n.get(&"storm"))
		var w_gust_hi: float = float(wind_n.get(&"gust"))
		wm.call(&"force", "clear", 60.0)
		await ctx.call(&"step_seconds", tree, 2.2)
		var s_lo: float = float(ctx.call(&"global_shader_float", &"g_storm"))
		var w_storm_lo: float = float(wind_n.get(&"storm"))
		p17 = s_hi > 0.3 and w_storm_hi > 0.3 and w_gust_hi > 0.2 and s_lo < s_hi and w_storm_lo < w_storm_hi
	_chk(ctx, p17, "T3_WindWeather", "WorldWind x WeatherManager: storm elevates WeatherManager & WorldWind then decays toward clear")

	# 18. WaterRules x WaterAmbience
	var p18: bool = false
	var amb: Node = ctx.call(&"find_water_ambience", lab) as Node
	if amb != null and player != null and is_finite(surf_pos.x) and not brook_pts.is_empty():
		var players: Array[AudioStreamPlayer] = []
		for c: Node in amb.find_children("*", "AudioStreamPlayer", true, false):
			players.append(c as AudioStreamPlayer)
		if not players.is_empty():
			await ctx.call(&"teleport_and_settle", tree, player, brook_pts[0])
			await ctx.call(&"step_frames", tree, 8)
			var any_playing: bool = false
			var brook_total: float = 0.0
			for ap: AudioStreamPlayer in players:
				if ap.playing:
					any_playing = true
				brook_total += db_to_linear(ap.volume_db)
			await ctx.call(&"teleport_and_settle", tree, player, Vector2(850.0, 0.0))
			await ctx.call(&"step_frames", tree, 15)
			var far_total: float = 0.0
			for ap: AudioStreamPlayer in players:
				far_total += db_to_linear(ap.volume_db)
			p18 = any_playing and brook_total > far_total + 0.05
			await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, p18, "T3_RulesAmbience", "WaterRules x WaterAmbience: audio stays active and attenuates by water distance/biome")

	await ctx.call(&"cleanup_node", tree, lab)


static func _read_fx_color(fx_node: Node) -> Color:
	if fx_node == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	for prop_name: StringName in [&"fill_color", &"water_color", &"fill", &"color", &"_fill"]:
		var val: Variant = fx_node.get(prop_name)
		if val is Color:
			return val as Color
	return Color(0.0, 0.0, 0.0, 0.0)
