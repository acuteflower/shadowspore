extends RefCounted
## Shared opaque-box helpers, compile-safe dynamic probes, and spatial scanners for Water System v2 E2E tests.

const WATER_RULES_PATH: String = "res://src/water/water_rules.gd"
const WATER_FIELD_PATH: String = "res://src/water/water_field.gd"
const WATER_BRIDGE_PATH: String = "res://src/water/water_bridge.gd"
const WATER_AMBIENCE_PATH: String = "res://src/water/water_ambience.gd"
const GRASS_LAB_PATH: String = "res://tools/grass_lab.tscn"
const WORLD_LEVEL_PATH: String = "res://src/world/v2/zone_world.tscn"

const R1_PROTECTED_FILES: Array[String] = [
	"res://src/world/ground_surfaces.gd",
	"res://assets/shaders/ground_surfaces.gdshader",
	"res://tools/art_ancient_stones.py",
	"res://tools/art_forest_details.py",
]

const R1_PROTECTED_ART_SCRIPTS: Array[String] = [
	"res://tools/art_ancient_stones.py",
	"res://tools/art_forest_details.py",
]

const WATER_V2_FORBIDDEN_SYMBOLS: Array[String] = [
	"WaterSystem v2", "WaterField", "water_v2", "WaterBridge", "water_bridge",
	"WaterRules", "WaterAmbience", "water_geo_map", "water_flow_map",
	"tide_shallow", "coastal_props", "puddle_v2",
]

const ORIGINAL_TERRAIN_SURFACES: Array[String] = [
	"grass", "path", "gravel", "ancient_stone", "forest_floor", "moss",
	"damp_earth", "mud", "shallow_water", "deep_water", "slope", "stone",
	"wood", "bed", "mine_stone", "field", "steppe", "sand", "quartz",
	"quicksand", "puddle",
]

var checks: int = 0
var failures: int = 0
var current_tier: String = "T1"
var tier_checks: Dictionary = {"T1": 0, "T2": 0, "T3": 0, "T4": 0}
var tier_failures: Dictionary = {"T1": 0, "T2": 0, "T3": 0, "T4": 0}
var _rules_inst: RefCounted = null


func set_tier(tier_id: String) -> void:
	current_tier = tier_id
	if not tier_checks.has(tier_id):
		tier_checks[tier_id] = 0
		tier_failures[tier_id] = 0


func check(cond: bool, area: String, msg: String) -> bool:
	checks += 1
	tier_checks[current_tier] = int(tier_checks.get(current_tier, 0)) + 1
	if cond:
		print("[PASS] [%s][%s] %s" % [current_tier, area, msg])
	else:
		failures += 1
		tier_failures[current_tier] = int(tier_failures.get(current_tier, 0)) + 1
		print("[FAIL] [%s][%s] %s" % [current_tier, area, msg])
		push_error("[%s][%s] %s" % [current_tier, area, msg])
	return cond


func load_script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


func load_scene(path: String) -> PackedScene:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


func rules_script() -> GDScript:
	return load_script(WATER_RULES_PATH)


func call_rules(method: StringName, args: Array) -> Variant:
	var scr: GDScript = rules_script()
	if scr == null:
		return null
	if _rules_inst == null or _rules_inst.get_script() != scr:
		_rules_inst = scr.new() as RefCounted
	if _rules_inst != null and _rules_inst.has_method(method):
		return _rules_inst.callv(method, args)
	if scr.has_method(method):
		return scr.callv(method, args)
	return null


func rules_has_method(method: StringName) -> bool:
	var scr: GDScript = rules_script()
	if scr == null:
		return false
	if _rules_inst == null or _rules_inst.get_script() != scr:
		_rules_inst = scr.new() as RefCounted
	if _rules_inst != null and _rules_inst.has_method(method):
		return true
	return scr.has_method(method)


func find_water_field() -> Node:
	for patch: Node in Terrain.patches:
		if is_instance_valid(patch) and patch.has_method(&"water_field_at"):
			return patch
	return null


func find_water_bridge() -> Node:
	for patch: Node in Terrain.patches:
		if is_instance_valid(patch) and patch.has_method(&"has_water_deck_at") and not patch.has_method(&"water_field_at"):
			return patch
	return null


func find_water_ambience(root: Node) -> Node:
	var scr: GDScript = load_script(WATER_AMBIENCE_PATH)
	if scr == null or root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back() as Node
		if is_instance_valid(cur) and cur.get_script() == scr:
			return cur
		for child: Node in cur.get_children():
			stack.append(child)
	return null


func find_node_by_name_or_shader(root: Node, target_name: String, shader_suffix: String) -> CanvasItem:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back() as Node
		if is_instance_valid(cur) and cur is CanvasItem:
			var ci: CanvasItem = cur as CanvasItem
			if ci.name == target_name:
				return ci
			if shader_suffix != "" and ci.material is ShaderMaterial:
				var sm: ShaderMaterial = ci.material as ShaderMaterial
				if sm.shader != null and sm.shader.resource_path.ends_with(shader_suffix):
					return ci
		for child: Node in cur.get_children():
			stack.append(child)
	return null


func patch_index(patch: Node) -> int:
	if patch == null:
		return -1
	return Terrain.patches.find(patch)


func host_and_spawn_lab(tree: SceneTree) -> Node2D:
	NetworkManager.host_singleplayer()
	var packed: PackedScene = load_scene(GRASS_LAB_PATH)
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if not (inst is Node2D):
		if inst != null:
			inst.queue_free()
		return null
	var lab: Node2D = inst as Node2D
	lab.set(&"_demo_active", false)
	tree.root.add_child(lab)
	await step_frames(tree, 4)
	return lab


func get_lab_player(lab: Node2D) -> CharacterBody2D:
	if lab == null:
		return null
	var players_node: Node = lab.get_node_or_null("Players")
	if players_node == null or players_node.get_child_count() == 0:
		return null
	return players_node.get_child(0) as CharacterBody2D


func get_lab_wind(lab: Node2D) -> Node2D:
	if lab == null:
		return null
	var w: Node2D = lab.get_node_or_null("WorldWind") as Node2D
	if w != null:
		return w
	var wind_scr: GDScript = load_script("res://src/world/world_wind.gd")
	if wind_scr != null:
		return wind_scr.get(&"current") as Node2D
	return null


func get_lab_grass(lab: Node2D) -> Node2D:
	if lab == null:
		return null
	return lab.get_node_or_null("LivingGrass") as Node2D


func get_weather_manager() -> Node:
	var wm_scr: GDScript = load_script("res://src/world/weather_manager.gd")
	if wm_scr == null:
		return null
	return wm_scr.get(&"current") as Node


func get_water_reflections() -> Node:
	var wr_scr: GDScript = load_script("res://src/water/water_reflections.gd")
	if wr_scr == null:
		return null
	return wr_scr.get(&"current") as Node


func lock_time_and_settle_lights(tree: SceneTree, time_of_day: float) -> void:
	TimeManager.lock_at(time_of_day)
	OS.delay_msec(115)
	await step_seconds(tree, 0.35)


func step_frames(tree: SceneTree, physics_frames: int) -> void:
	for i: int in physics_frames:
		await tree.physics_frame
	await tree.process_frame


func step_seconds(tree: SceneTree, seconds: float) -> void:
	var frames: int = maxi(1, int(ceilf(seconds * 60.0)))
	for i: int in frames:
		await tree.physics_frame
	await tree.process_frame


func teleport_and_settle(tree: SceneTree, player: CharacterBody2D, pos: Vector2) -> void:
	if player == null:
		return
	if player.has_method(&"request_teleport"):
		player.call(&"request_teleport", pos)
	else:
		player.global_position = pos
	await step_frames(tree, 4)


func walk_player(tree: SceneTree, player: CharacterBody2D, action: StringName, frames: int, sprint: bool = false) -> void:
	if player == null:
		return
	if sprint:
		Input.action_press(&"sprint")
	Input.action_press(action)
	for i: int in frames:
		await tree.physics_frame
	Input.action_release(action)
	if sprint:
		Input.action_release(&"sprint")
	await tree.physics_frame


func release_all_inputs() -> void:
	var actions: Array[StringName] = [
		&"move_left", &"move_right", &"move_up", &"move_down",
		&"sprint", &"sneak", &"shadow_step", &"action_primary", &"action_secondary",
	]
	for act: StringName in actions:
		if Input.is_action_pressed(act):
			Input.action_release(act)


func stop_audio_under(node: Node) -> void:
	if node == null:
		return
	for p2: Node in node.find_children("*", "AudioStreamPlayer2D", true, false):
		var player2d: AudioStreamPlayer2D = p2 as AudioStreamPlayer2D
		player2d.stop()
		player2d.stream = null
	for p1: Node in node.find_children("*", "AudioStreamPlayer", true, false):
		var player1d: AudioStreamPlayer = p1 as AudioStreamPlayer
		player1d.stop()
		player1d.stream = null


func cleanup_node(tree: SceneTree, node: Node) -> void:
	release_all_inputs()
	TimeManager.unlock()
	var wm: Node = get_weather_manager()
	if wm != null and is_instance_valid(wm) and wm.has_method(&"release"):
		wm.call(&"release")
	if node != null and is_instance_valid(node):
		stop_audio_under(node)
		node.queue_free()
	await tree.process_frame
	await tree.process_frame


func global_shader_float(param_name: StringName) -> float:
	var v: Variant = RenderingServer.global_shader_parameter_get(param_name)
	if v != null:
		return float(v)
	# Headless Dummy RenderingServer returns null for global shader parameters;
	# fall back to the authoritative GDScript simulation state.
	var key: String = String(param_name)
	var wm: Node = get_weather_manager()
	if wm != null and is_instance_valid(wm):
		var g_dict: Variant = wm.get(&"_g")
		if g_dict is Dictionary and (g_dict as Dictionary).has(key):
			return float((g_dict as Dictionary)[key])
		match param_name:
			&"g_rain":
				return float(wm.get(&"rain"))
			&"g_storm":
				return float(wm.get(&"storm"))
			&"g_puddle":
				return float(wm.get(&"puddle"))
			&"g_wet":
				return float(wm.get(&"ground_wet"))
	var wind_scr: GDScript = load_script("res://src/world/world_wind.gd")
	var wind: Node2D = wind_scr.get(&"current") as Node2D if wind_scr != null else null
	if wind != null and is_instance_valid(wind):
		match param_name:
			&"g_wind_gust":
				return float(wind.get(&"gust"))
			&"g_wind_clock":
				return float(wind.get(&"clock"))
	if param_name == &"g_water_time":
		var wf: Node = find_water_field()
		if wf != null and is_instance_valid(wf):
			var ft: float = float(wf.get(&"_frame_water_time"))
			return ft if ft > 0.0 else float(wf.get(&"_clock"))
		for patch: Node in Terrain.patches:
			if is_instance_valid(patch) and patch.get(&"_clock") != null:
				return float(patch.get(&"_clock"))
	return 0.0


func global_shader_vec2(param_name: StringName) -> Vector2:
	var v: Variant = RenderingServer.global_shader_parameter_get(param_name)
	if v is Vector2:
		return v as Vector2
	if param_name == &"g_wind_dir":
		var wind_scr: GDScript = load_script("res://src/world/world_wind.gd")
		var wind: Node2D = wind_scr.get(&"current") as Node2D if wind_scr != null else null
		if wind != null and is_instance_valid(wind):
			var d: Variant = wind.get(&"direction")
			if d is Vector2:
				return d as Vector2
	return Vector2.ZERO


func verify_r1_protected_files() -> bool:
	var ok: bool = true
	for r_path: String in R1_PROTECTED_FILES:
		if not FileAccess.file_exists(r_path):
			ok = false
			print("[INFO] R1 missing protected file: %s" % r_path)
			continue
		var txt: String = FileAccess.get_file_as_string(r_path)
		if txt.is_empty():
			ok = false
			print("[INFO] R1 empty protected file: %s" % r_path)
			continue
		for sym: String in WATER_V2_FORBIDDEN_SYMBOLS:
			if txt.contains(sym):
				ok = false
				print("[INFO] R1 forbidden Water v2 symbol '%s' found in %s" % [sym, r_path])
		if R1_PROTECTED_ART_SCRIPTS.has(r_path):
			if not (txt.contains("def ") and txt.contains("import ")):
				ok = false
				print("[INFO] R1 invalid Python module markers in %s" % r_path)
	return ok


func count_grass_cells_in_rect(grass: Node2D, rect: Rect2) -> int:
	if grass == null:
		return 0
	var cells_v: Variant = grass.get(&"_grass_cells")
	if not (cells_v is Dictionary):
		return 0
	var cells: Dictionary = cells_v as Dictionary
	var count: int = 0
	for gc_v: Variant in cells.keys():
		var gc: Vector2i = gc_v as Vector2i
		var cell_center: Vector2 = Vector2(gc) * 8.0 + Vector2(4.0, 4.0)
		if rect.has_point(cell_center):
			count += 1
	return count


func has_grass_cell_at(grass: Node2D, world_pos: Vector2) -> bool:
	if grass == null:
		return false
	var cells_v: Variant = grass.get(&"_grass_cells")
	if not (cells_v is Dictionary):
		return false
	var gc: Vector2i = Vector2i((world_pos / 8.0).floor())
	return (cells_v as Dictionary).has(gc)


func check_bridge_lanterns(wb: Node, expect_lit: bool) -> bool:
	if wb == null:
		return false
	var pl_count: int = 0
	var glow_sprite_count: int = 0
	for child: Node in wb.find_children("*", "CanvasItem", true, false):
		var ci: CanvasItem = child as CanvasItem
		if ci is PointLight2D:
			pl_count += 1
			var pl: PointLight2D = ci as PointLight2D
			var is_budgeted: Variant = pl.get(&"budgeted")
			var is_lit_pl: bool = false
			if is_budgeted is bool and not (is_budgeted as bool):
				var ov: Variant = pl.get(&"_overflow")
				is_lit_pl = (ov is CanvasItem) and (ov as CanvasItem).visible
			else:
				is_lit_pl = pl.enabled and pl.energy > 0.0
			if expect_lit and not is_lit_pl:
				return false
			if (not expect_lit) and is_lit_pl:
				return false
		elif ci.name.to_lower().contains("glow"):
			glow_sprite_count += 1
			if expect_lit and not ci.visible:
				return false
			if (not expect_lit) and ci.visible:
				return false
	return (pl_count + glow_sprite_count) > 0


func reset_wet_state(tree: SceneTree, wm: Node, player: CharacterBody2D) -> void:
	if wm != null and is_instance_valid(wm):
		wm.call(&"force", "clear", 60.0)
		wm.set(&"rain", 0.0)
		wm.set(&"ground_wet", 0.0)
		wm.set(&"_extra_wet", 0.0)
		wm.set(&"puddle", 0.0)
	if player != null and is_instance_valid(player):
		player.set(&"_wet", 0.0)
		var foot_comp: Node = player.get_node_or_null("FootstepComponent")
		if foot_comp != null:
			foot_comp.set(&"_puddle_wet", 0.0)
	await step_frames(tree, 4)


func scan_brook_samples(wf: Node, wb: Node = null) -> Dictionary:
	var out: Dictionary = {
		"points": [] as Array[Vector2],
		"north_deep_pos": Vector2(INF, INF),
		"south_ford_pos": Vector2(INF, INF),
		"deep_any_pos": Vector2(INF, INF),
		"min_y": INF,
		"max_y": -INF,
		"max_depth": 0.0,
		"min_ford_depth": 1.0,
		"has_water": false,
	}
	if wf == null:
		return out
	var pts: Array[Vector2] = out["points"] as Array[Vector2]
	var best_ford_score: float = -INF
	var y: float = -132.0
	while y <= 132.0:
		var x: float = -568.0
		while x <= -200.0:
			var pos: Vector2 = Vector2(x, y)
			var on_deck: bool = wb != null and bool(wb.call(&"has_water_deck_at", pos))
			var info: Dictionary = wf.call(&"water_field_at", pos) as Dictionary
			var regime: int = int(info.get("regime", 0))
			var is_water: bool = bool(info.get("water", false))
			var depth: float = float(info.get("depth", 0.0))
			var static_sdf: float = float(info.get("static_sdf_px", 0.0))
			var surf: String = String(wf.call(&"surface_at", pos))
			if regime == 1 and is_water:
				out["has_water"] = true
				pts.append(pos)
				out["min_y"] = minf(float(out["min_y"]), y)
				out["max_y"] = maxf(float(out["max_y"]), y)
				if depth > float(out["max_depth"]):
					out["max_depth"] = depth
					if y < 0.0 and not on_deck:
						out["north_deep_pos"] = pos
				if bool(wf.call(&"is_deep", pos)) and not on_deck and not is_finite((out["deep_any_pos"] as Vector2).x):
					out["deep_any_pos"] = pos
				if y < 0.0 and depth >= 0.6 and not on_deck and not is_finite((out["north_deep_pos"] as Vector2).x):
					out["north_deep_pos"] = pos
				if not on_deck and surf == "shallow_water" and depth < 0.22:
					var ford_score: float = -static_sdf + (100.0 if (y >= 56.0 and y <= 116.0) else (20.0 if y > 20.0 else 0.0))
					if ford_score > best_ford_score:
						best_ford_score = ford_score
						out["min_ford_depth"] = depth
						out["south_ford_pos"] = pos
			x += 4.0
		y += 4.0
	return out


func scan_bridge_samples(wf: Node, wb: Node) -> Dictionary:
	var out: Dictionary = {
		"deck_points": [] as Array[Vector2],
		"center": Vector2(INF, INF),
		"deck_over_water_pos": Vector2(INF, INF),
		"min_x": INF,
		"max_x": -INF,
		"min_y": INF,
		"max_y": -INF,
		"east_approach": Vector2(INF, INF),
		"west_approach": Vector2(INF, INF),
	}
	if wb == null:
		return out
	var pts: Array[Vector2] = out["deck_points"] as Array[Vector2]
	var sum: Vector2 = Vector2.ZERO
	var y: float = -136.0
	while y <= 136.0:
		var x: float = -568.0
		while x <= -200.0:
			var pos: Vector2 = Vector2(x, y)
			if bool(wb.call(&"has_water_deck_at", pos)):
				pts.append(pos)
				sum += pos
				out["min_x"] = minf(float(out["min_x"]), x)
				out["max_x"] = maxf(float(out["max_x"]), x)
				out["min_y"] = minf(float(out["min_y"]), y)
				out["max_y"] = maxf(float(out["max_y"]), y)
				if wf != null:
					var info: Dictionary = wf.call(&"water_field_at", pos) as Dictionary
					if bool(info.get("water", false)) and float(info.get("depth", 0.0)) > 0.2:
						if not is_finite((out["deck_over_water_pos"] as Vector2).x) or float(info.get("depth", 0.0)) > 0.4:
							out["deck_over_water_pos"] = pos
			x += 4.0
		y += 4.0
	if not pts.is_empty():
		var c: Vector2 = sum / float(pts.size())
		out["center"] = c
		out["east_approach"] = Vector2(float(out["max_x"]) + 10.0, c.y)
		out["west_approach"] = Vector2(float(out["min_x"]) - 10.0, c.y)
	return out


func scan_swash_samples(wf: Node) -> Dictionary:
	var out: Dictionary = {
		"regime3_points": [] as Array[Vector2],
		"dry_beach_pos": Vector2(INF, INF),
		"wet_sand_pos": Vector2(INF, INF),
		"tide_shallow_pos": Vector2(INF, INF),
		"dynamic_swash_pos": Vector2(INF, INF),
		"surfaces_seen": {} as Dictionary,
	}
	if wf == null:
		return out
	var pts: Array[Vector2] = out["regime3_points"] as Array[Vector2]
	var seen: Dictionary = out["surfaces_seen"] as Dictionary
	var dry_band: Vector2 = Vector2(INF, INF)
	var wet_band: Vector2 = Vector2(INF, INF)
	var tide_band: Vector2 = Vector2(INF, INF)
	var best_dyn: Vector2 = Vector2(INF, INF)
	var best_dyn_score: int = 0
	var base_t: float = global_shader_float(&"g_water_time")
	var wdir: Vector2 = global_shader_vec2(&"g_wind_dir")
	var wgust: float = global_shader_float(&"g_wind_gust")
	var storm: float = global_shader_float(&"g_storm")
	var has_rules: bool = rules_has_method(&"shore_state_at")

	var y: float = -128.0
	while y <= 128.0:
		var in_y_band: bool = y >= -40.0 and y <= 90.0
		var x: float = -952.0
		while x <= -584.0:
			var pos: Vector2 = Vector2(x, y)
			var info: Dictionary = wf.call(&"water_field_at", pos) as Dictionary
			var regime: int = int(info.get("regime", 0))
			var bed_id: int = int(info.get("bed_id", 0))
			var static_sdf: float = float(info.get("static_sdf_px", 999.0))
			var surf: String = String(wf.call(&"surface_at", pos))
			if surf != "":
				seen[surf] = true
			if regime == 3:
				pts.append(pos)
			if surf == "beach_sand":
				if in_y_band and not is_finite(dry_band.x):
					dry_band = pos
				elif not is_finite((out["dry_beach_pos"] as Vector2).x):
					out["dry_beach_pos"] = pos
			elif surf == "wet_sand":
				if in_y_band and not is_finite(wet_band.x):
					wet_band = pos
				elif not is_finite((out["wet_sand_pos"] as Vector2).x):
					out["wet_sand_pos"] = pos
			elif surf == "tide_shallow":
				if in_y_band and not is_finite(tide_band.x):
					tide_band = pos
				elif not is_finite((out["tide_shallow_pos"] as Vector2).x):
					out["tide_shallow_pos"] = pos

			if regime == 3 and bed_id == 2 and in_y_band and static_sdf >= -2.0 and static_sdf <= 12.0 and bool(wf.call(&"has_dynamic_water", pos)):
				if has_rules:
					var cycle_states: Dictionary = {}
					for step_i: int in 16:
						var probe_t: float = base_t + float(step_i) * 0.34
						var st: String = String(call_rules(&"shore_state_at", [static_sdf, pos.y, probe_t, wdir, wgust, storm]))
						cycle_states[st] = true
					var distinct_n: int = cycle_states.size()
					var mid_bonus: int = 1 if (static_sdf >= 2.0 and static_sdf <= 10.0) else 0
					var score: int = distinct_n * 10 + mid_bonus
					if distinct_n >= 2 and score > best_dyn_score:
						best_dyn_score = score
						best_dyn = pos
				elif not is_finite(best_dyn.x):
					best_dyn = pos
			x += 4.0
		y += 4.0

	if is_finite(dry_band.x):
		out["dry_beach_pos"] = dry_band
	if is_finite(wet_band.x):
		out["wet_sand_pos"] = wet_band
	if is_finite(tide_band.x):
		out["tide_shallow_pos"] = tide_band
	if is_finite(best_dyn.x):
		out["dynamic_swash_pos"] = best_dyn
	return out


func scan_ocean_samples(wf: Node) -> Dictionary:
	var out: Dictionary = {
		"points": [] as Array[Vector2],
		"shallow_east_pos": Vector2(INF, INF),
		"deep_west_pos": Vector2(INF, INF),
		"min_depth": 1.0,
		"max_depth": 0.0,
	}
	if wf == null:
		return out
	var pts: Array[Vector2] = out["points"] as Array[Vector2]
	var y: float = -120.0
	while y <= 120.0:
		var x: float = -1336.0
		while x <= -968.0:
			var pos: Vector2 = Vector2(x, y)
			var info: Dictionary = wf.call(&"water_field_at", pos) as Dictionary
			if int(info.get("regime", 0)) == 4 and bool(info.get("water", false)):
				pts.append(pos)
				var d: float = float(info.get("depth", 0.0))
				if d < float(out["min_depth"]):
					out["min_depth"] = d
					out["shallow_east_pos"] = pos
				if d > float(out["max_depth"]):
					out["max_depth"] = d
					out["deep_west_pos"] = pos
			x += 8.0
		y += 8.0
	return out


func scan_puddles(wf: Node, wb: Node, x_min: float, x_max: float) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if wf == null:
		return found
	var y: float = -132.0
	while y <= 132.0:
		var x: float = x_min
		while x <= x_max:
			var pos: Vector2 = Vector2(x, y)
			var on_deck: bool = wb != null and bool(wb.call(&"has_water_deck_at", pos))
			if not on_deck:
				var surf: String = String(wf.call(&"surface_at", pos))
				if surf == "puddle":
					found.append(pos)
			x += 4.0
		y += 4.0
	return found


func scan_puddle_interiors(wf: Node, wb: Node, x_min: float, x_max: float) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	if wf == null:
		return centers
	var raw: Array[Vector2] = scan_puddles(wf, wb, x_min, x_max)
	if raw.is_empty():
		return centers
	var clusters: Array[Array] = []
	for pt: Vector2 in raw:
		var placed: bool = false
		for cl: Array in clusters:
			var anchor: Vector2 = cl[0] as Vector2
			if anchor.distance_to(pt) <= 28.0:
				cl.append(pt)
				placed = true
				break
		if not placed:
			clusters.append([pt])
	for cl: Array in clusters:
		var sum: Vector2 = Vector2.ZERO
		for p_v: Variant in cl:
			sum += (p_v as Vector2)
		var centroid: Vector2 = sum / float(cl.size())
		var best_pt: Vector2 = cl[0] as Vector2
		var best_score: float = INF
		for p_v: Variant in cl:
			var p: Vector2 = p_v as Vector2
			var info: Dictionary = wf.call(&"water_field_at", p) as Dictionary
			var sdf: float = float(info.get("static_sdf_px", 0.0))
			var score: float = p.distance_to(centroid) + (0.0 if sdf <= -4.0 else 40.0)
			if score < best_score:
				best_score = score
				best_pt = p
		centers.append(best_pt)
	return centers


func find_dry_land_in_rect(wf: Node, wb: Node, rect: Rect2) -> Vector2:
	if wf == null:
		return Vector2(INF, INF)
	var y: float = rect.position.y
	while y <= rect.end.y:
		var x: float = rect.position.x
		while x <= rect.end.x:
			var pos: Vector2 = Vector2(x, y)
			var on_deck: bool = wb != null and bool(wb.call(&"has_water_deck_at", pos))
			if not on_deck:
				var info: Dictionary = wf.call(&"water_field_at", pos) as Dictionary
				var surf: String = String(wf.call(&"surface_at", pos))
				if bool(info.get("in_bounds", false)) and not bool(info.get("water", false)) and not bool(info.get("wet_sand", false)) and surf != "puddle" and not bool(wf.call(&"reflects_at", pos)):
					return pos
			x += 8.0
		y += 8.0
	return Vector2(INF, INF)


func count_active_footprints_near(tree: SceneTree, center: Vector2, radius: float, expected_color: Color = Color(0, 0, 0, 0)) -> int:
	if tree == null or tree.current_scene == null:
		return 0
	var canvas: Node = tree.current_scene.get_node_or_null("FootprintCanvas")
	if canvas == null:
		return 0
	var pool: Variant = canvas.get(&"_pool")
	if not (pool is Array):
		return 0
	var count: int = 0
	var canvas_2d: Node2D = canvas as Node2D
	for item_v: Variant in (pool as Array):
		var item: Object = item_v as Object
		if item == null:
			continue
		if not bool(item.get(&"active")):
			continue
		var local_pos: Vector2 = item.get(&"pos") as Vector2
		var world_pos: Vector2 = canvas_2d.to_global(local_pos) if canvas_2d != null else local_pos
		if world_pos.distance_to(center) <= radius:
			if expected_color.a > 0.0:
				var col: Color = item.get(&"color") as Color
				if col.is_equal_approx(expected_color):
					count += 1
			else:
				count += 1
	return count
