extends RefCounted
## Tier 2 — Boundary & Corner Cases (F1..F9, >=5 checks per feature area, >=45 total).


static func _chk(ctx: RefCounted, cond: bool, area: String, msg: String) -> bool:
	return bool(ctx.call(&"check", cond, area, msg))


static func run(tree: SceneTree, ctx: RefCounted) -> void:
	ctx.call(&"set_tier", "T2")
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

	await _t2_f1(tree, ctx, wf, player, brook)
	await _t2_f2(tree, ctx, lab, wf, wb, player, bridge)
	await _t2_f3(tree, ctx, wf, player, swash)
	await _t2_f4(tree, ctx, wf, player, ocean)
	await _t2_f5(tree, ctx, wf, player)
	await _t2_f6(tree, ctx, lab, wf)
	await _t2_f7(tree, ctx, wf)
	await _t2_f8(tree, ctx, lab, wf)
	await _t2_f9(tree, ctx, lab, wf, wb, player, puddles_sq1, puddles_sq2, bridge, swash)

	await ctx.call(&"cleanup_node", tree, lab)


static func _t2_f1(tree: SceneTree, ctx: RefCounted, wf: Node, player: CharacterBody2D, brook: Dictionary) -> void:
	var border_ok: bool = wf != null
	if wf != null:
		var info_w: Dictionary = wf.call(&"water_field_at", Vector2(-576.0, 0.0)) as Dictionary
		var fv_w: Vector2 = wf.call(&"field_at", Vector2(-576.0, 0.0)) as Vector2
		var info_e_in: Dictionary = wf.call(&"water_field_at", Vector2(-192.5, 0.0)) as Dictionary
		var fv_e_in: Vector2 = wf.call(&"field_at", Vector2(-192.5, 0.0)) as Vector2
		var info_e_out: Dictionary = wf.call(&"water_field_at", Vector2(-192.0, 0.0)) as Dictionary
		var fv_e_out: Vector2 = wf.call(&"field_at", Vector2(-192.0, 0.0)) as Vector2
		border_ok = (
			bool(info_w.get("in_bounds", false)) and is_finite(fv_w.x) and is_finite(fv_w.y)
			and bool(info_e_in.get("in_bounds", false)) and is_finite(fv_e_in.x) and is_finite(fv_e_in.y)
			and (not bool(info_e_out.get("in_bounds", true))) and (not is_finite(fv_e_out.x))
		)
	_chk(ctx, border_ok, "F1", "Exact Square -1 half-open borders (x=-576,-192.5 inside; x=-192 outside) evaluate cleanly")

	var tb_ok: bool = wf != null
	if wf != null:
		var info_top: Dictionary = wf.call(&"water_field_at", Vector2(-384.0, -144.0)) as Dictionary
		var info_bot_in: Dictionary = wf.call(&"water_field_at", Vector2(-384.0, 143.5)) as Dictionary
		var info_bot_out: Dictionary = wf.call(&"water_field_at", Vector2(-384.0, 144.0)) as Dictionary
		tb_ok = (
			bool(info_top.get("in_bounds", false)) and float(info_top.get("depth", -1.0)) >= 0.0
			and bool(info_bot_in.get("in_bounds", false)) and float(info_bot_in.get("depth", -1.0)) >= 0.0
			and (not bool(info_bot_out.get("in_bounds", true)))
		)
	_chk(ctx, tb_ok, "F1", "Exact y=-144/+143.5 inside and y=+144 half-open outside along Square -1 return valid depth")

	var depth_thresh_ok: bool = false
	var ford_pos: Vector2 = brook.get("south_ford_pos", Vector2(INF, INF)) as Vector2
	var deep_pos: Vector2 = brook.get("north_deep_pos", Vector2(INF, INF)) as Vector2
	if wf != null and is_finite(ford_pos.x) and is_finite(deep_pos.x):
		depth_thresh_ok = float(wf.call(&"depth_amount", ford_pos)) < 0.35 and (not bool(wf.call(&"is_deep", ford_pos))) and float(wf.call(&"depth_amount", deep_pos)) >= 0.60 and bool(wf.call(&"is_deep", deep_pos))
	_chk(ctx, depth_thresh_ok, "F1", "Depth threshold separation: ford (<0.35, not deep) vs kolk (>=0.60, deep)")

	var no_swim_ford_ok: bool = false
	if wf != null and player != null and is_finite(ford_pos.x):
		await ctx.call(&"teleport_and_settle", tree, player, ford_pos)
		await ctx.call(&"step_frames", tree, 12)
		var swimmer: Object = player.get(&"swimmer") as Object
		no_swim_ford_ok = int(player.get(&"swim")) == SwimRules.NONE and (swimmer == null or not bool(swimmer.get(&"active")))
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, no_swim_ford_ok, "F1", "Gravel ford depth (<0.92 enter threshold) keeps player wading on foot (swim==NONE)")

	var dry_bank_ok: bool = false
	if wf != null:
		var dry_probe: Vector2 = ctx.call(&"find_dry_land_in_rect", wf, null, Rect2(-568.0, -132.0, 368.0, 264.0)) as Vector2
		if is_finite(dry_probe.x):
			var info: Dictionary = wf.call(&"water_field_at", dry_probe) as Dictionary
			var wade: Dictionary = wf.call(&"wade_data", dry_probe, Terrain.surface_data("grass")) as Dictionary
			dry_bank_ok = (not bool(info.get("water", true))) and (not bool(wade.get("water", false))) and float(wade.get("submerge", 0.0)) == 0.0
	_chk(ctx, dry_bank_ok, "F1", "Dry Square -1 bank outside brook SDF returns water==false and submerge==0.0")


static func _t2_f2(tree: SceneTree, ctx: RefCounted, _lab: Node2D, wf: Node, wb: Node, player: CharacterBody2D, bridge: Dictionary) -> void:
	var min_x: float = float(bridge.get("min_x", INF))
	var max_x: float = float(bridge.get("max_x", -INF))
	var center: Vector2 = bridge.get("center", Vector2(INF, INF)) as Vector2
	var ew_edges_ok: bool = false
	if wb != null and is_finite(center.x) and is_finite(min_x) and is_finite(max_x):
		var inside_w: bool = bool(wb.call(&"has_water_deck_at", Vector2(min_x + 2.0, center.y)))
		var outside_w: bool = bool(wb.call(&"has_water_deck_at", Vector2(min_x - 6.0, center.y)))
		var inside_e: bool = bool(wb.call(&"has_water_deck_at", Vector2(max_x - 2.0, center.y)))
		var outside_e: bool = bool(wb.call(&"has_water_deck_at", Vector2(max_x + 6.0, center.y)))
		ew_edges_ok = inside_w and (not outside_w) and inside_e and (not outside_e)
	_chk(ctx, ew_edges_ok, "F2", "WaterBridge has_water_deck_at() flips cleanly at west/east deck entry & exit edges")

	var min_y: float = float(bridge.get("min_y", INF))
	var max_y: float = float(bridge.get("max_y", -INF))
	var ns_edges_ok: bool = false
	if wb != null and is_finite(center.x) and is_finite(min_y) and is_finite(max_y):
		var out_n: bool = bool(wb.call(&"has_water_deck_at", Vector2(center.x, min_y - 6.0)))
		var out_s: bool = bool(wb.call(&"has_water_deck_at", Vector2(center.x, max_y + 6.0)))
		ns_edges_ok = (not out_n) and (not out_s)
	_chk(ctx, ns_edges_ok, "F2", "WaterBridge has_water_deck_at() returns false outside north/south railing edges")

	var over_water: Vector2 = bridge.get("deck_over_water_pos", Vector2(INF, INF)) as Vector2
	var override_ok: bool = false
	if wf != null and wb != null and is_finite(over_water.x):
		var wf_surf: String = String(wf.call(&"surface_at", over_water))
		var t_surf: String = Terrain.surface_at(over_water)
		override_ok = (wf_surf == "shallow_water" or wf_surf == "deep_water") and t_surf == "ancient_stone"
	_chk(ctx, override_ok, "F2", "Terrain.surface_at overrides WaterField water with 'ancient_stone' over bridge span")

	var standalone_ok: bool = false
	var wb_scr: GDScript = ctx.call(&"load_script", String(ctx.get(&"WATER_BRIDGE_PATH"))) as GDScript
	if wb_scr != null:
		var solo: Node2D = wb_scr.new() as Node2D
		if solo != null:
			var r_off: bool = bool(solo.call(&"has_water_deck_at", Vector2(9999.0, 9999.0)))
			var s_off: String = String(solo.call(&"surface_at", Vector2(9999.0, 9999.0)))
			standalone_ok = (not r_off) and s_off == ""
			solo.free()
	_chk(ctx, standalone_ok, "F2", "WaterBridge standalone instance without WaterField handles out-of-bounds safely")

	var lantern_thresh_ok: bool = false
	if wb != null and player != null and is_finite(center.x):
		await ctx.call(&"teleport_and_settle", tree, player, center)
		await ctx.call(&"lock_time_and_settle_lights", tree, 0.75)
		var off_at_75: bool = bool(ctx.call(&"check_bridge_lanterns", wb, false))
		await ctx.call(&"lock_time_and_settle_lights", tree, 0.88)
		var on_at_88: bool = bool(ctx.call(&"check_bridge_lanterns", wb, true))
		lantern_thresh_ok = off_at_75 and on_at_88
		TimeManager.lock_at(0.50)
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, lantern_thresh_ok, "F2", "WaterBridge lantern glow & NightLight respect night threshold (off at 0.75, on at 0.88)")

	var exit_meta_ok: bool = false
	var east_app: Vector2 = bridge.get("east_approach", Vector2(INF, INF)) as Vector2
	if player != null and is_finite(over_water.x) and is_finite(east_app.x):
		await ctx.call(&"teleport_and_settle", tree, player, over_water)
		var had_meta: bool = player.has_meta(&"water_deck")
		await ctx.call(&"teleport_and_settle", tree, player, east_app)
		exit_meta_ok = had_meta and (not player.has_meta(&"water_deck"))
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, exit_meta_ok, "F2", "Leaving WaterBridge east approach clears water_deck meta cleanly")


static func _t2_f3(tree: SceneTree, ctx: RefCounted, wf: Node, player: CharacterBody2D, swash: Dictionary) -> void:
	var border_ok: bool = wf != null
	if wf != null:
		for x: float in [-960.0, -576.0]:
			var info: Dictionary = wf.call(&"water_field_at", Vector2(x, 0.0)) as Dictionary
			var fv: Vector2 = wf.call(&"field_at", Vector2(x, 0.0)) as Vector2
			if not bool(info.get("in_bounds", false)) or int(info.get("regime", -1)) < 0 or not is_finite(fv.x):
				border_ok = false
	_chk(ctx, border_ok, "F3", "Exact Square -2 borders (x=-960, x=-576) are in_bounds with finite values")

	var hyst_ok: bool = false
	if bool(ctx.call(&"rules_has_method", &"sand_wetness")) and bool(ctx.call(&"rules_has_method", &"swash_offset_px")):
		var max_off: float = -INF
		var peak_t: float = 0.0
		for i: int in 120:
			var t_p: float = float(i) * 0.1
			var off: float = float(ctx.call(&"call_rules", &"swash_offset_px", [0.0, t_p, Vector2.RIGHT, 0.25, 0.0]))
			if off > max_off:
				max_off = off
				peak_t = t_p
		var wet_at_peak: float = float(ctx.call(&"call_rules", &"sand_wetness", [max_off - 0.5, 0.0, peak_t, Vector2.RIGHT, 0.25, 0.0]))
		var wet_after_1s: float = float(ctx.call(&"call_rules", &"sand_wetness", [max_off + 24.0, 0.0, peak_t + 1.0, Vector2.RIGHT, 0.25, 0.0]))
		var wet_after_5s: float = float(ctx.call(&"call_rules", &"sand_wetness", [max_off + 24.0, 0.0, peak_t + 5.0, Vector2.RIGHT, 0.25, 0.0]))
		hyst_ok = wet_at_peak >= 0.90 and wet_after_5s <= wet_after_1s and wet_after_5s <= 0.25
	_chk(ctx, hyst_ok, "F3", "WaterRules.sand_wetness peaks at ~1.0 when wetted and decays <=0.25 after ~4-5s")

	var stationary_ok: bool = false
	var dyn_pos: Vector2 = swash.get("dynamic_swash_pos", Vector2(INF, INF)) as Vector2
	if wf != null and player != null and is_finite(dyn_pos.x):
		await ctx.call(&"teleport_and_settle", tree, player, dyn_pos)
		var saw_states: Dictionary = {}
		var dyn_flag: bool = false
		for step_i: int in 18:
			var s_now: String = Terrain.surface_at(player.global_position)
			saw_states[s_now] = true
			if bool(wf.call(&"has_dynamic_water", player.global_position)):
				dyn_flag = true
			await ctx.call(&"step_frames", tree, 20)
		stationary_ok = dyn_flag and saw_states.size() >= 2 and (saw_states.has("tide_shallow") or saw_states.has("wet_sand"))
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, stationary_ok, "F3", "Stationary player in swash zone has has_dynamic_water==true and tracks >=2 swash states")

	var wind_ext_ok: bool = false
	if bool(ctx.call(&"rules_has_method", &"swash_offset_px")):
		var c_min: float = INF
		var c_max: float = -INF
		var s_min: float = INF
		var s_max: float = -INF
		for i: int in 80:
			var t_v: float = float(i) * 0.1
			var co: float = float(ctx.call(&"call_rules", &"swash_offset_px", [0.0, t_v, Vector2.RIGHT, 0.0, 0.0]))
			var so: float = float(ctx.call(&"call_rules", &"swash_offset_px", [0.0, t_v, Vector2.RIGHT, 1.0, 1.0]))
			c_min = minf(c_min, co)
			c_max = maxf(c_max, co)
			s_min = minf(s_min, so)
			s_max = maxf(s_max, so)
		wind_ext_ok = (s_max - s_min) > (c_max - c_min)
	_chk(ctx, wind_ext_ok, "F3", "Storm wind swash reach amplitude strictly exceeds calm wind in WaterRules")

	var tr_wet_hi: float = MovementRules.surface_traction("wet_sand", 1.0, 1.0)
	var tr_dry_lo: float = MovementRules.surface_traction("beach_sand", 0.0, 0.0)
	_chk(ctx, tr_wet_hi >= 0.5 and tr_wet_hi <= 1.2 and tr_dry_lo >= 0.5 and tr_dry_lo <= 1.2, "F3", "MovementRules.surface_traction stays clamped within [0.5, 1.2] for coastal extremes")

	var tbl: Dictionary = DataRegistry.table("terrain")
	var sprint_ok: bool = tbl.has("tide_shallow") and tbl.has("deep_water") and bool((tbl["tide_shallow"] as Dictionary).get("allow_sprint", false)) and (not bool((tbl["deep_water"] as Dictionary).get("allow_sprint", true)))
	_chk(ctx, sprint_ok, "F3", "data/terrain.json keeps tide_shallow sprintable while deep_water disables sprint")


static func _t2_f4(tree: SceneTree, ctx: RefCounted, wf: Node, player: CharacterBody2D, ocean: Dictionary) -> void:
	var border_ok: bool = wf != null
	if wf != null:
		var info_w: Dictionary = wf.call(&"water_field_at", Vector2(-1344.0, 0.0)) as Dictionary
		var fv_w: Vector2 = wf.call(&"field_at", Vector2(-1344.0, 0.0)) as Vector2
		var info_e: Dictionary = wf.call(&"water_field_at", Vector2(-960.0, 0.0)) as Dictionary
		var fv_e: Vector2 = wf.call(&"field_at", Vector2(-960.0, 0.0)) as Vector2
		var info_out: Dictionary = wf.call(&"water_field_at", Vector2(-1345.0, 0.0)) as Dictionary
		border_ok = (
			bool(info_w.get("in_bounds", false)) and is_finite(fv_w.x)
			and bool(info_e.get("in_bounds", false)) and is_finite(fv_e.x)
			and (not bool(info_out.get("in_bounds", true)))
		)
	_chk(ctx, border_ok, "F4", "Exact Square -3 borders (x=-1344, x=-960 inside; x=-1345 outside) return valid bounds")

	var hyst_swim_ok: bool = (
		SwimRules.wants_swim(false, 0.92)
		and (not SwimRules.wants_swim(false, 0.85))
		and SwimRules.wants_swim(true, 0.85)
		and (not SwimRules.wants_swim(true, 0.79))
	)
	_chk(ctx, hyst_swim_ok, "F4", "SwimRules depth hysteresis holds at 0.92 enter / 0.80 exit boundaries")

	var swell_ext_ok: bool = false
	if bool(ctx.call(&"rules_has_method", &"swell_height")):
		var c_peak: float = 0.0
		var s_peak: float = 0.0
		for i: int in 60:
			var t_v: float = float(i) * 0.1
			c_peak = maxf(c_peak, absf(float(ctx.call(&"call_rules", &"swell_height", [Vector2(-1150.0, 0.0), t_v, Vector2.RIGHT, 0.0, 0.0]))))
			s_peak = maxf(s_peak, absf(float(ctx.call(&"call_rules", &"swell_height", [Vector2(-1150.0, 0.0), t_v, Vector2.RIGHT, 1.0, 1.0]))))
		swell_ext_ok = s_peak > c_peak
	_chk(ctx, swell_ext_ok, "F4", "Storm wind increases WaterRules.swell_height peak amplitude vs calm")

	var deep_west: Vector2 = ocean.get("deep_west_pos", Vector2(INF, INF)) as Vector2
	var flow_bound_ok: bool = false
	if wf != null and is_finite(deep_west.x):
		var fv: Vector2 = wf.call(&"water_flow_at", deep_west) as Vector2
		flow_bound_ok = is_finite(fv.x) and is_finite(fv.y) and fv.length() < 500.0
	_chk(ctx, flow_bound_ok, "F4", "Open sea water_flow_at() velocity is finite and bounded")

	var exit_swim_ok: bool = false
	if player != null and is_finite(deep_west.x):
		await ctx.call(&"teleport_and_settle", tree, player, deep_west)
		await ctx.call(&"step_frames", tree, 18)
		var was_swimming: bool = int(player.get(&"swim")) > 0
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
		await ctx.call(&"step_frames", tree, 8)
		var swimmer: Object = player.get(&"swimmer") as Object
		exit_swim_ok = was_swimming and int(player.get(&"swim")) == SwimRules.NONE and (swimmer == null or not bool(swimmer.get(&"active")))
	_chk(ctx, exit_swim_ok, "F4", "Returning from deep Square -3 ocean to dry Square 0 cleanly exits swim state")


static func _t2_f5(tree: SceneTree, ctx: RefCounted, wf: Node, player: CharacterBody2D) -> void:
	var oob_ok: bool = false
	if wf != null:
		var fv: Vector2 = wf.call(&"field_at", Vector2(10000.0, 10000.0)) as Vector2
		var info: Dictionary = wf.call(&"water_field_at", Vector2(10000.0, 10000.0)) as Dictionary
		oob_ok = (not is_finite(fv.x)) and (not bool(info.get("in_bounds", true)))
	_chk(ctx, oob_ok, "F5", "Out-of-bounds (10000,10000) returns INF SDF and in_bounds==false")

	var nonfinite_ok: bool = false
	if wf != null:
		var fv_inf: Vector2 = wf.call(&"field_at", Vector2(INF, 0.0)) as Vector2
		var info_nan: Dictionary = wf.call(&"water_field_at", Vector2(-INF, NAN)) as Dictionary
		nonfinite_ok = (not is_finite(fv_inf.x)) and (not bool(info_nan.get("in_bounds", true)))
	_chk(ctx, nonfinite_ok, "F5", "Non-finite queries (INF, NAN) fail gracefully without crash")

	var radius_ok: bool = false
	if wf != null:
		var r0: bool = bool(wf.call(&"clear_for_prop", Vector2(-384.0, 0.0), 0.0))
		var r_neg: bool = bool(wf.call(&"clear_for_prop", Vector2(-384.0, 0.0), -5.0))
		var r_dry: bool = bool(wf.call(&"clear_for_prop", Vector2(0.0, 0.0), 0.0))
		radius_ok = (not r0) and (not r_neg) and r_dry
	_chk(ctx, radius_ok, "F5", "clear_for_prop() returns false in brook for <=0 radii and true on dry land")

	var recenter_edge_ok: bool = false
	if wf != null and player != null:
		await ctx.call(&"teleport_and_settle", tree, player, Vector2(-250.0, 0.0))
		await ctx.call(&"step_frames", tree, 3)
		var orig_1: Vector2 = wf.get(&"_wave_origin") as Vector2
		await ctx.call(&"teleport_and_settle", tree, player, Vector2(-1150.0, 0.0))
		await ctx.call(&"step_frames", tree, 3)
		var orig_2: Vector2 = wf.get(&"_wave_origin") as Vector2
		wf.call(&"add_water_impulse", Vector2(-1150.0, 0.0), 0.9, 8.0, Vector2.RIGHT)
		await ctx.call(&"step_frames", tree, 2)
		var active_far: bool = bool(wf.get(&"_wave_active"))
		await ctx.call(&"teleport_and_settle", tree, player, Vector2(-250.0, 0.0))
		await ctx.call(&"step_frames", tree, 3)
		var orig_3: Vector2 = wf.get(&"_wave_origin") as Vector2
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
		recenter_edge_ok = orig_1.distance_to(orig_2) > 512.0 and orig_3.distance_to(orig_1) < 32.0 and active_far
	_chk(ctx, recenter_edge_ok, "F5", "Rapid back-and-forth >512 px camera jumps recenter wave ringbuffer cleanly")

	var burst_ok: bool = false
	if wf != null and player != null:
		await ctx.call(&"teleport_and_settle", tree, player, Vector2(-380.0, 0.0))
		await ctx.call(&"step_frames", tree, 2)
		for i: int in 32:
			wf.call(&"add_water_impulse", Vector2(-380.0, -40.0 + float(i % 8) * 10.0), 1.0, 8.0, Vector2.DOWN)
		for k: int in 10:
			wf.call(&"set_swimmer", 8100 + k, Vector4(-1100.0 + float(k) * 6.0, 0.0, 1.0, 0.5))
		await ctx.call(&"step_frames", tree, 3)
		var sw_burst: Dictionary = wf.get(&"_swimmers") as Dictionary
		burst_ok = bool(wf.get(&"_wave_active")) and sw_burst.size() == 10
	_chk(ctx, burst_ok, "F5", "Burst of 32 impulses + 10 concurrent swimmers activates ringbuffer without overflow")

	var clear_swimmer_ok: bool = false
	if wf != null:
		for k: int in 10:
			wf.call(&"set_swimmer", 8100 + k, Vector4.ZERO)
		await ctx.call(&"step_frames", tree, 2)
		var sw_cleared: Dictionary = wf.get(&"_swimmers") as Dictionary
		clear_swimmer_ok = sw_cleared.is_empty()
		if player != null:
			await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, clear_swimmer_ok, "F5", "Clearing swimmer slots via Vector4.ZERO cleans up all ringbuffer swimmers")


static func _t2_f6(tree: SceneTree, ctx: RefCounted, lab: Node2D, wf: Node) -> void:
	var glow_node: CanvasItem = ctx.call(&"find_node_by_name_or_shader", lab, "WaterV2Glow", "water_v2_glow.gdshader") as CanvasItem
	TimeManager.lock_at(0.50)
	await ctx.call(&"step_frames", tree, 2)
	var day_off: bool = glow_node != null and not glow_node.visible
	TimeManager.lock_at(0.78)
	await ctx.call(&"step_frames", tree, 2)
	var gold_off: bool = glow_node != null and not glow_node.visible
	TimeManager.lock_at(0.88)
	await ctx.call(&"step_frames", tree, 2)
	var night_on: bool = glow_node != null and glow_node.visible
	TimeManager.lock_at(0.50)
	_chk(ctx, day_off and gold_off and night_on, "F6", "water_v2_glow visibility transitions cleanly at night threshold (0.50/0.78 off, 0.88 on)")

	var wm: Node = ctx.call(&"get_weather_manager") as Node
	var weather_clamp_ok: bool = false
	if wm != null:
		wm.call(&"force", "storm", 60.0)
		await ctx.call(&"step_seconds", tree, 2.0)
		var gr: float = float(ctx.call(&"global_shader_float", &"g_rain"))
		var gs: float = float(ctx.call(&"global_shader_float", &"g_storm"))
		var gg: float = float(ctx.call(&"global_shader_float", &"g_wind_gust"))
		weather_clamp_ok = gr > 0.1 and gs > 0.1 and gg > 0.1 and gr <= 1.05 and gs <= 1.05 and is_finite(gg) and gg < 30.0
		wm.call(&"force", "clear", 60.0)
		await ctx.call(&"step_seconds", tree, 0.8)
	_chk(ctx, weather_clamp_ok, "F6", "Extreme storm shader globals stay finite and clamped")

	var refl_cadence_ok: bool = false
	var wr: Node = ctx.call(&"get_water_reflections") as Node
	if wr != null:
		await ctx.call(&"step_seconds", tree, 0.3)
		refl_cadence_ok = bool(wr.get(&"enabled"))
	_chk(ctx, refl_cadence_ok, "F6", "WaterReflections survives >=0.2s rebuild cadence with enabled==true")

	var oob_refl_ok: bool = wf != null and (not bool(wf.call(&"reflects_at", Vector2(10000.0, 10000.0))))
	_chk(ctx, oob_refl_ok, "F6", "WaterField.reflects_at() returns false for out-of-bounds coordinates")

	var colors_valid_ok: bool = wf != null
	if wf != null:
		for t_v: float in [0.00, 0.27, 0.50, 0.74]:
			TimeManager.lock_at(t_v)
			var c_dict: Dictionary = wf.call(&"water_color_at", Vector2(-1150.0, 0.0)) as Dictionary
			var fill_c: Color = c_dict.get("fill", Color(0, 0, 0, 0)) as Color
			if is_nan(fill_c.r) or is_nan(fill_c.g) or is_nan(fill_c.b) or fill_c.a <= 0.0:
				colors_valid_ok = false
		TimeManager.lock_at(0.50)
	_chk(ctx, colors_valid_ok, "F6", "water_color_at() returns valid finite colors across night/morning/noon/golden times")


static func _t2_f7(tree: SceneTree, ctx: RefCounted, _wf: Node) -> void:
	var solo_amb_ok: bool = false
	var amb_scr: GDScript = ctx.call(&"load_script", String(ctx.get(&"WATER_AMBIENCE_PATH"))) as GDScript
	if amb_scr != null:
		var solo: Node2D = amb_scr.new() as Node2D
		if solo != null:
			solo.process_mode = Node.PROCESS_MODE_ALWAYS
			solo._process(0.016)
			solo_amb_ok = true
			ctx.call(&"stop_audio_under", solo)
			solo.free()
	_chk(ctx, solo_amb_ok, "F7", "WaterAmbience handles standalone _process without WaterField gracefully")

	var no_black_ok: bool = false
	var bridge_tex: Texture2D = load("res://assets/props/water_bridge.png") as Texture2D if ResourceLoader.exists("res://assets/props/water_bridge.png") else null
	if bridge_tex != null:
		var img: Image = bridge_tex.get_image()
		if img != null and img.get_width() > 0 and img.get_height() > 0:
			var has_pure_black: bool = false
			for py: int in img.get_height():
				for px: int in img.get_width():
					var c: Color = img.get_pixel(px, py)
					if c.a > 0.1 and c.r == 0.0 and c.g == 0.0 and c.b == 0.0:
						has_pure_black = true
						break
				if has_pure_black:
					break
			no_black_ok = not has_pure_black
	_chk(ctx, no_black_ok, "F7", "water_bridge.png complies with zero pure-#000000 outline rule")

	var wav_fmt_ok: bool = true
	for wp: String in [
		"res://assets/audio/water/brook_loop.wav",
		"res://assets/audio/water/surf_wash_loop.wav",
		"res://assets/audio/water/ocean_swell_loop.wav",
	]:
		var wav: AudioStreamWAV = load(wp) as AudioStreamWAV if ResourceLoader.exists(wp) else null
		if wav == null or wav.stereo or wav.mix_rate != 22050 or wav.get_length() <= 0.5 or wav.data.is_empty():
			wav_fmt_ok = false
	_chk(ctx, wav_fmt_ok, "F7", "Water loop WAVs load as 22050 Hz mono AudioStreamWAV with valid PCM/QOA data")

	var vol_bound_ok: bool = false
	if amb_scr != null:
		var inst: Node2D = amb_scr.new() as Node2D
		if inst != null:
			tree.root.add_child(inst)
			await ctx.call(&"step_frames", tree, 2)
			vol_bound_ok = true
			for c: Node in inst.find_children("*", "AudioStreamPlayer", true, false):
				var ap: AudioStreamPlayer = c as AudioStreamPlayer
				if is_nan(ap.volume_db) or ap.volume_db > 6.0 or ap.volume_db < -85.0:
					vol_bound_ok = false
			ctx.call(&"stop_audio_under", inst)
			inst.queue_free()
			await tree.process_frame
	_chk(ctx, vol_bound_ok, "F7", "WaterAmbience audio players maintain finite bounded volume_db")

	var large_t_ok: bool = false
	if bool(ctx.call(&"rules_has_method", &"swash_offset_px")) and bool(ctx.call(&"rules_has_method", &"swell_height")):
		var s_zero: float = float(ctx.call(&"call_rules", &"swash_offset_px", [0.0, 0.0, Vector2.RIGHT, 0.2, 0.0]))
		var s_big: float = float(ctx.call(&"call_rules", &"swash_offset_px", [0.0, 100000.0, Vector2.RIGHT, 0.2, 0.0]))
		var w_big: float = float(ctx.call(&"call_rules", &"swell_height", [Vector2(-1150.0, 0.0), 100000.0, Vector2.RIGHT, 0.2, 0.0]))
		large_t_ok = is_finite(s_zero) and is_finite(s_big) and is_finite(w_big)
	_chk(ctx, large_t_ok, "F7", "WaterRules remains finite at t=0.0 and t=100000.0 without precision collapse")


static func _t2_f8(tree: SceneTree, ctx: RefCounted, lab: Node2D, wf: Node) -> void:
	var seam_ok: bool = wf != null and Terrain.surface_at(Vector2(-188.0, 0.0)) == "grass" and String(wf.call(&"surface_at", Vector2(-190.0, 0.0))) == ""
	_chk(ctx, seam_ok, "F8", "Square -1 / Square 0 boundary (x=-192) does not clobber Square 0 grass")

	var right_borders_ok: bool = wf != null
	if wf != null:
		for px: float in [192.0, 576.0, 959.0]:
			if String(wf.call(&"surface_at", Vector2(px, 0.0))) != "":
				right_borders_ok = false
	_chk(ctx, right_borders_ok, "F8", "Right-side borders (x=+192, +576, +959) are untouched by WaterField")

	var grass: Node2D = ctx.call(&"get_lab_grass", lab) as Node2D
	var grass_sq0_ok: bool = false
	if grass != null and lab != null:
		var metrics: Variant = lab.get(&"_metrics")
		grass_sq0_ok = (metrics is Dictionary) and bool((metrics as Dictionary).get("tuft_density", false)) and int(grass.get(&"tuft_count")) >= 1600
	_chk(ctx, grass_sq0_ok, "F8", "LivingGrass preserves >=1600 tufts across expanded studio with Square 0 intact")

	var tbl: Dictionary = DataRegistry.table("terrain")
	var orig_speeds_ok: bool = (
		tbl.has("ancient_stone")
		and is_equal_approx(float((tbl["ancient_stone"] as Dictionary).get("speed", 0.0)), 1.05)
		and tbl.has("puddle")
		and is_equal_approx(float((tbl["puddle"] as Dictionary).get("speed", 0.0)), 0.96)
	)
	_chk(ctx, orig_speeds_ok, "F8", "Original terrain.json speeds for ancient_stone (1.05) and puddle (0.96) remain exact")

	var tmp_lab: Node2D = await ctx.call(&"host_and_spawn_lab", tree) as Node2D
	await ctx.call(&"cleanup_node", tree, tmp_lab)
	var lab_wm: Node = lab.find_child("WeatherManager", true, false)
	if lab_wm != null:
		(load("res://src/world/weather_manager.gd") as GDScript).set(&"current", lab_wm)
	var lab_wr: Node = lab.find_child("WaterReflections", true, false)
	if lab_wr != null:
		(load("res://src/water/water_reflections.gd") as GDScript).set(&"current", lab_wr)
	var leaked: bool = false
	for p: Node in Terrain.patches:
		if not is_instance_valid(p):
			leaked = true
		elif p.get_parent() == null:
			leaked = true
	_chk(ctx, not leaked, "F8", "Disposing a grass_lab instance leaves zero invalid/dangling Terrain.patches entries")


static func _t2_f9(tree: SceneTree, ctx: RefCounted, _lab: Node2D, wf: Node, wb: Node, player: CharacterBody2D, _puddles_sq1: Array[Vector2], _puddles_sq2: Array[Vector2], bridge: Dictionary, swash: Dictionary) -> void:
	var centers_sq1: Array[Vector2] = ctx.call(&"scan_puddle_interiors", wf, wb, -568.0, -200.0) as Array[Vector2]
	var centers_sq2: Array[Vector2] = ctx.call(&"scan_puddle_interiors", wf, wb, -952.0, -584.0) as Array[Vector2]
	var wm: Node = ctx.call(&"get_weather_manager") as Node
	var growth_ok: bool = false
	if wf != null and wm != null:
		await ctx.call(&"reset_wet_state", tree, wm, player)
		await ctx.call(&"step_seconds", tree, 0.8)
		var dry_n: int = (ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array).size()
		wm.call(&"force", "downpour", 60.0)
		wm.set(&"rain", 0.90)
		wm.set(&"_extra_wet", 1.0)
		wm.set(&"puddle", 0.9)
		wm.set(&"ground_wet", 1.0)
		await ctx.call(&"step_seconds", tree, 1.5)
		var wet_n: int = (ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array).size()
		var gp_wet: float = float(ctx.call(&"global_shader_float", &"g_puddle"))
		growth_ok = wet_n > dry_n and gp_wet > 0.3
		await ctx.call(&"reset_wet_state", tree, wm, player)
	_chk(ctx, growth_ok, "F9", "Puddle cell count expands strictly from dry (g_puddle=0) to heavy rain (g_puddle>0.3)")

	var stationary_puddle_ok: bool = false
	if wf != null and player != null and wm != null and not centers_sq1.is_empty():
		var edge_pt: Vector2 = Vector2(INF, INF)
		wm.call(&"force", "downpour", 60.0)
		wm.set(&"rain", 0.90)
		wm.set(&"_extra_wet", 1.0)
		wm.set(&"puddle", 0.9)
		wm.set(&"ground_wet", 1.0)
		await ctx.call(&"step_seconds", tree, 1.2)
		var wet_pts: Array = ctx.call(&"scan_puddles", wf, wb, -952.0, -200.0) as Array
		for pt_v: Variant in wet_pts:
			var pt: Vector2 = pt_v as Vector2
			if bool(wf.call(&"has_dynamic_water", pt)):
				edge_pt = pt
				break
		if is_finite(edge_pt.x):
			await ctx.call(&"teleport_and_settle", tree, player, edge_pt)
			stationary_puddle_ok = Terrain.surface_at(player.global_position) == "puddle"
			await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
		await ctx.call(&"reset_wet_state", tree, wm, player)
	_chk(ctx, stationary_puddle_ok, "F9", "Stationary player on rain-reactive puddle detects puddle state via has_dynamic_water")

	var no_swim_puddle_ok: bool = false
	var sample_p: Vector2 = centers_sq1[0] if not centers_sq1.is_empty() else (centers_sq2[0] if not centers_sq2.is_empty() else Vector2(INF, INF))
	if wf != null and player != null and is_finite(sample_p.x):
		await ctx.call(&"teleport_and_settle", tree, player, sample_p)
		await ctx.call(&"step_frames", tree, 10)
		no_swim_puddle_ok = (not bool(wf.call(&"is_deep", sample_p))) and float(wf.call(&"depth_amount", sample_p)) < 0.35 and int(player.get(&"swim")) == SwimRules.NONE
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
	_chk(ctx, no_swim_puddle_ok, "F9", "Puddles stay shallow (<0.35, is_deep==false) and never trigger deep swimming")

	var refl_edge_ok: bool = false
	var dry_sq1: Vector2 = ctx.call(&"find_dry_land_in_rect", wf, wb, Rect2(-568.0, -132.0, 368.0, 264.0)) as Vector2
	if wf != null and is_finite(sample_p.x) and is_finite(dry_sq1.x):
		var on_p: bool = bool(wf.call(&"reflects_at", sample_p))
		var off_p: bool = bool(wf.call(&"reflects_at", dry_sq1))
		refl_edge_ok = on_p and (not off_p)
	_chk(ctx, refl_edge_ok, "F9", "Puddle reflects_at() is true inside puddle and false on dry bank")

	var decay_ok: bool = false
	var dry_pt: Vector2 = bridge.get("center", Vector2(INF, INF)) as Vector2
	if not is_finite(dry_pt.x):
		dry_pt = swash.get("dry_beach_pos", Vector2(INF, INF)) as Vector2
	if player != null and is_finite(sample_p.x) and is_finite(dry_pt.x):
		await ctx.call(&"reset_wet_state", tree, wm, player)
		var foot_comp: Node = player.get_node_or_null("FootstepComponent")
		var pre_clean_before: int = int(ctx.call(&"count_active_footprints_near", tree, dry_pt, 48.0, Color("#1c2b33")))
		await ctx.call(&"teleport_and_settle", tree, player, dry_pt - Vector2(16.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 24)
		var pre_clean_after: int = int(ctx.call(&"count_active_footprints_near", tree, dry_pt, 48.0, Color("#1c2b33")))
		var clean_dry: bool = pre_clean_after == pre_clean_before

		await ctx.call(&"teleport_and_settle", tree, player, sample_p - Vector2(12.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 28)
		var pw_wet: float = float(foot_comp.get(&"_puddle_wet")) if foot_comp != null else 0.0

		var before_prints: int = int(ctx.call(&"count_active_footprints_near", tree, dry_pt, 48.0, Color("#1c2b33")))
		await ctx.call(&"teleport_and_settle", tree, player, dry_pt - Vector2(18.0, 0.0))
		await ctx.call(&"walk_player", tree, player, &"move_right", 24)
		var mid_prints: int = int(ctx.call(&"count_active_footprints_near", tree, dry_pt, 48.0, Color("#1c2b33")))
		await ctx.call(&"walk_player", tree, player, &"move_right", 45)
		var pw_dry: float = float(foot_comp.get(&"_puddle_wet")) if foot_comp != null else 0.0
		decay_ok = clean_dry and pw_wet >= 0.40 and mid_prints > before_prints and pw_dry < pw_wet
		await ctx.call(&"teleport_and_settle", tree, player, Vector2.ZERO)
		await ctx.call(&"reset_wet_state", tree, wm, player)
	_chk(ctx, decay_ok, "F9", "Wet puddle-boot damping wets (>=0.40), stamps #1c2b33 prints, and decays over dry steps")

	var sq2_right_puddle_ok: bool = wf != null and String(wf.call(&"surface_at", Vector2(786.0, -48.0))) == "" and Terrain.surface_at(Vector2(786.0, -48.0)) == "puddle"
	_chk(ctx, sq2_right_puddle_ok, "F9", "Square +2 right-side puddle at (786,-48) belongs to GroundSurfaces, not WaterField")
