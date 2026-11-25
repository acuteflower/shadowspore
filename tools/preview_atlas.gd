extends Node
## Standalone AtlasView + Living Map preview & capture tool.
## Usage:
##   godot --path . res://tools/preview_atlas.tscn -- --dir=/abs [--out=/abs/file.png] --level=ort|zone|continent|world|all [--time=0.45] [--weather=fair] [--open] [--zone=windkap] [--unlocked] [--all-discovered|--full-continent] [--hover]

const AtlasViewScript: GDScript = preload("res://src/ui/atlas_view.gd")

var _atlas: Atlas
var _discovery: MapDiscovery
var _markers: MapMarkers
var _view: Control
var _weather_field: WeatherField


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir: String = ""
	var out_file: String = ""
	var level_arg: String = ""
	var time_val: float = 0.45
	var weather_id: String = "fair"
	var zone_arg: String = "windkap"
	var capture_open: bool = false
	var unlocked: bool = false
	var all_discovered: bool = false
	var show_hover: bool = false
	var custom_zoom: float = -1.0
	var custom_center: Vector2 = Vector2.INF

	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			out_dir = arg.trim_prefix("--dir=")
		elif arg.begins_with("--out="):
			out_file = arg.trim_prefix("--out=")
		elif arg.begins_with("--capture="):
			out_file = arg.trim_prefix("--capture=")
		elif arg.begins_with("--level="):
			level_arg = arg.trim_prefix("--level=").to_lower()
		elif arg.begins_with("--time="):
			time_val = clampf(arg.trim_prefix("--time=").to_float(), 0.0, 0.999)
		elif arg.begins_with("--weather="):
			weather_id = arg.trim_prefix("--weather=").to_lower()
		elif arg.begins_with("--zone="):
			zone_arg = arg.trim_prefix("--zone=").to_lower()
		elif arg.begins_with("--zoom="):
			custom_zoom = arg.trim_prefix("--zoom=").to_float()
		elif arg.begins_with("--center="):
			var cparts: PackedStringArray = arg.trim_prefix("--center=").split(",")
			if cparts.size() >= 2:
				custom_center = Vector2(cparts[0].to_float(), cparts[1].to_float())
		elif arg == "--open":
			capture_open = true
		elif arg == "--unlocked":
			unlocked = true
		elif arg == "--all-discovered" or arg == "--full-continent":
			all_discovered = true
			unlocked = true
		elif arg == "--hover":
			show_hover = true

	if level_arg.is_empty():
		if not out_file.is_empty():
			level_arg = "continent" if all_discovered else "zone"
		else:
			level_arg = "all" if not out_dir.is_empty() else "zone"
	if level_arg in ["continent", "world", "all"]:
		unlocked = true

	TimeManager.lock_at(time_val)
	TimeManager.set_process(false)

	_atlas = Atlas.shared()
	var continent_id: StringName = &"main"
	if not _atlas.continents.has(continent_id) and not _atlas.continents.is_empty():
		continent_id = _atlas.continents.keys()[0] as StringName

	var zones_list: Array[Atlas.Zone] = _atlas.zones_of(continent_id)
	var target_zone: Atlas.Zone = _atlas.zone(StringName(zone_arg))
	if target_zone == null and not zones_list.is_empty():
		target_zone = zones_list[0]
	var zone_id: StringName = target_zone.id if target_zone != null else &""
	var player_tile: Vector2 = _resolve_preview_player_tile(target_zone)

	# In-memory MapDiscovery (never touches save files)
	_discovery = MapDiscovery.new()
	add_child(_discovery)
	if _discovery.has_method(&"setup_atlas"):
		_discovery.call(&"setup_atlas", _atlas, continent_id)

	if all_discovered:
		for z_all: Atlas.Zone in zones_list:
			if _discovery.has_method(&"mark_zone_entered"):
				_discovery.call(&"mark_zone_entered", z_all.id)
			if _discovery.has_method(&"reveal_zone_disc"):
				var diag: float = Vector2(z_all.size).length()
				_discovery.call(&"reveal_zone_disc", z_all.id, Vector2(z_all.size) * 0.5, diag)
	elif target_zone != null:
		if _discovery.has_method(&"mark_zone_entered"):
			_discovery.call(&"mark_zone_entered", target_zone.id)
		var rev_radius: float = maxf(88.0, float(maxi(target_zone.size.x, target_zone.size.y)) * 0.42)
		if _discovery.has_method(&"reveal_zone_disc"):
			var local_c: Vector2 = player_tile - Vector2(target_zone.origin)
			_discovery.call(&"reveal_zone_disc", target_zone.id, local_c, rev_radius)
			var center_local: Vector2 = target_zone.center() - Vector2(target_zone.origin)
			_discovery.call(&"reveal_zone_disc", target_zone.id, center_local, rev_radius * 0.78)
			if not _discovery.is_seen(player_tile) and _discovery.has_method(&"import_zone_fog"):
				var fw: int = maxi(1, ceili(float(target_zone.size.x) * 0.5))
				var fh: int = maxi(1, ceili(float(target_zone.size.y) * 0.5))
				var raw_fog: PackedByteArray = PackedByteArray()
				raw_fog.resize(fw * fh)
				for cy: int in fh:
					for cx: int in fw:
						var cell_p: Vector2 = (Vector2(float(cx), float(cy)) + Vector2(0.5, 0.5)) * 2.0
						if cell_p.distance_to(local_c) <= rev_radius or cell_p.distance_to(center_local) <= rev_radius * 0.78:
							raw_fog[cy * fw + cx] = 1
				_discovery.call(&"import_zone_fog", target_zone.id, {"w": fw, "h": fh, "zstd": raw_fog.compress(FileAccess.COMPRESSION_ZSTD)})
		else:
			_discovery.reveal_disc(player_tile, 9.5)
		# Mark neighboring connected zones as sighted (`gesichtet`) for realistic early-game continent state
		if _discovery.has_method(&"mark_zone_sighted"):
			for th: Atlas.Threshold in _atlas.thresholds_of(target_zone.id):
				var nb_id: StringName = th.other(target_zone.id)
				if nb_id != &"" and nb_id != target_zone.id:
					_discovery.call(&"mark_zone_sighted", nb_id)

	# MapMarkers with authentic landmarks from the target zone
	if ResourceLoader.exists("res://src/ui/map_markers.gd"):
		_markers = MapMarkers.new()
		_register_sample_markers(target_zone, player_tile)

	# Local WeatherField for cloud/rain/storm rendering without WorldLevel
	_weather_field = WeatherField.new()
	_weather_field.build(1337, Callable())
	while not _weather_field.ready_now:
		await get_tree().process_frame

	var w_state: WeatherRules.State = WeatherRules.named(weather_id)
	var w_dict: Dictionary = {
		"id": weather_id,
		"name": WeatherRules.display_name(weather_id),
		"cloud": w_state.cloud,
		"rain": w_state.rain,
		"wind": w_state.wind,
		"storm": w_state.storm,
		"fog": w_state.fog,
		"dir": w_state.dir,
	}
	_push_weather_globals(w_state)

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_view = AtlasViewScript.new() as Control
	layer.add_child(_view)
	_view.call(&"setup", _atlas, _discovery, _markers, null)
	_view.call(&"set_continent_unlocked", unlocked, false)
	_view.call(&"set_veil_progress", 0.65)
	_view.call(&"set_preview_overrides", time_val, w_dict)
	if all_discovered and _view.has_method(&"set_preview_reveal_all"):
		_view.call(&"set_preview_reveal_all", true)

	var live_proxy: Texture2D = _make_live_proxy_texture()

	if out_dir.is_empty() and out_file.is_empty():
		_view.call(&"begin_open", live_proxy if capture_open else null, player_tile, zone_id, not capture_open)
		if level_arg != "all":
			_view.call(&"jump_to_level", StringName(level_arg), Vector2.ZERO, 0.0)
		if custom_zoom > 0.0:
			_view.call(&"set_zoom", custom_zoom, Vector2.ZERO)
		return

	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
	if not out_file.is_empty():
		DirAccess.make_dir_recursive_absolute(out_file.get_base_dir())
	var failed: bool = false

	if capture_open and not out_dir.is_empty():
		_view.call(&"begin_open", live_proxy, player_tile, zone_id, false)
		var step_times: Array[float] = [0.08, 0.18, 0.45, 0.78]
		var prev_t: float = 0.0
		for idx: int in step_times.size():
			var dt: float = step_times[idx] - prev_t
			prev_t = step_times[idx]
			_advance_sim(dt)
			await _wait_render_frames(2)
			var ok: bool = await _save_capture(out_dir.path_join("atlas_open_%02d.png" % (idx + 1)))
			failed = failed or not ok

	_view.call(&"begin_open", null, player_tile, zone_id, true)
	# Keep cursor parked cleanly in ocean corner unless --hover is requested
	var park_mm: InputEventMouseMotion = InputEventMouseMotion.new()
	park_mm.position = Vector2(8.0, 8.0)
	_view.call(&"_gui_input", park_mm)

	var levels_to_capture: Array[StringName] = []
	if level_arg == "all":
		levels_to_capture = [&"ort", &"zone", &"continent", &"world"]
	else:
		levels_to_capture = [StringName(level_arg)]

	for lvl: StringName in levels_to_capture:
		_view.call(&"jump_to_level", lvl, Vector2.ZERO, 0.0)
		if lvl == &"zone" and target_zone != null:
			_view.call(&"set_center_tile", target_zone.center())
		elif lvl == &"ort" and target_zone != null:
			_view.call(&"set_center_tile", player_tile)
		if custom_center.is_finite() and levels_to_capture.size() == 1:
			_view.call(&"set_center_tile", custom_center)
		if custom_zoom > 0.0 and levels_to_capture.size() == 1:
			_view.call(&"set_zoom", custom_zoom, Vector2.ZERO)
		_advance_sim(0.25)
		if show_hover and lvl == &"continent" and target_zone != null:
			var z_screen: Vector2 = _view.get_viewport_rect().size * 0.5
			var mm: InputEventMouseMotion = InputEventMouseMotion.new()
			mm.position = z_screen
			_view.call(&"_gui_input", mm)
			_advance_sim(0.25)
		await _wait_render_frames(3)
		var target_path: String = out_file if (not out_file.is_empty() and levels_to_capture.size() == 1) else out_dir.path_join("atlas_%s.png" % String(lvl))
		var ok: bool = await _save_capture(target_path)
		failed = failed or not ok

	if level_arg == "all" and unlocked and not out_dir.is_empty():
		# Capture cloud flythrough mid-transition (~0.090 px/tile)
		_view.call(&"set_zoom", 0.090, Vector2.ZERO)
		_advance_sim(0.15)
		await _wait_render_frames(3)
		var ok_fly: bool = await _save_capture(out_dir.path_join("atlas_flythrough.png"))
		failed = failed or not ok_fly

	print("Atlas preview capture: ", "OK" if not failed else "FAILED")
	get_tree().quit(1 if failed else 0)


func _resolve_preview_player_tile(z: Atlas.Zone) -> Vector2:
	if z == null:
		return Vector2(1200.0, 900.0)
	var camp_raw: Variant = z.raw.get("camp", {})
	if camp_raw is Dictionary:
		var cf: Variant = (camp_raw as Dictionary).get("campfire_tile", (camp_raw as Dictionary).get("tile"))
		if cf is Array and (cf as Array).size() >= 2:
			var pt: Vector2 = Vector2(float((cf as Array)[0]), float((cf as Array)[1]))
			if not z.bbox.grow(4.0).has_point(pt):
				pt += Vector2(z.origin)
			if z.contains(pt):
				return pt
			# Nudge slightly inland (-Y) if camp tile sits right on the surf line
			for dy: float in [-6.0, -12.0, -20.0, -28.0, 6.0]:
				var nudged: Vector2 = pt + Vector2(0.0, dy)
				if z.contains(nudged) and Atlas.edge_distance(nudged, z.footprint) > 4.0:
					return nudged
	for lm: Atlas.Landmark in z.landmarks:
		if lm.kind == &"campfire" or lm.kind == &"camp":
			return lm.pos
	return z.center()


func _advance_sim(seconds: float) -> void:
	var steps: int = maxi(ceili(seconds / 0.05), 1)
	var dt: float = seconds / float(steps)
	for i: int in steps:
		_view._process(dt)


func _wait_render_frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save_capture(abs_path: String) -> bool:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("PreviewAtlas: empty viewport image for " + abs_path)
		return false
	var err: Error = img.save_png(abs_path)
	print("Saved ", abs_path, " -> ", error_string(err))
	return err == OK


func _push_weather_globals(w: WeatherRules.State) -> void:
	if _weather_field == null or _weather_field.texture == null:
		return
	var thresh: float = _weather_field.threshold(w.cloud)
	var bonus: float = maxf(w.cloud - 0.75, 0.0) * 1.4
	RenderingServer.global_shader_parameter_set("g_cloud_tex", _weather_field.texture)
	RenderingServer.global_shader_parameter_set("g_cloud_thresh", thresh)
	RenderingServer.global_shader_parameter_set("g_cloud_bonus", bonus)
	RenderingServer.global_shader_parameter_set("g_cloud_shadow", 0.74)
	RenderingServer.global_shader_parameter_set("g_rain", w.rain)
	RenderingServer.global_shader_parameter_set("g_storm", w.storm)


func _make_live_proxy_texture() -> ImageTexture:
	# 640x360 crisp 16 px/tile live-world proxy for Match-Cut preview
	var img: Image = Image.create(640, 360, false, Image.FORMAT_RGBA8)
	var grass_a: Color = Color("3e7d56")
	var grass_b: Color = Color("2f624e")
	var path_c: Color = Color("9c8668")
	for y: int in 360:
		for x: int in 640:
			var tile_x: int = x / 16
			var tile_y: int = y / 16
			var col: Color = grass_a if (tile_x + tile_y) % 2 == 0 else grass_b
			if absi(y - 180 + int(sin(float(x) * 0.025) * 28.0)) < 18:
				col = path_c
			if Vector2(x - 320, y - 180).length() < 12.0:
				col = Color("e9e3f7")
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _register_sample_markers(z: Atlas.Zone, player_tile: Vector2) -> void:
	if _markers == null or not _markers.has_method(&"register_provider") or z == null:
		return
	var z_id: StringName = z.id
	var items: Array[Dictionary] = [
		{
			"id": &"preview_camp",
			"kind": &"campfire",
			"category": &"nature",
			"pos": player_tile,
			"zone": z_id,
			"levels": 3,
			"priority": 95,
			"label": "RASTPLATZ · TAG 1",
			"anim": &"pulse",
			"color": Color("f7d98b"),
			"data": {},
		}
	]
	var added_landmarks: int = 0
	for lm: Atlas.Landmark in z.landmarks:
		if lm.kind == &"veil_thread":
			continue
		var cat: StringName = &"nature"
		var col: Color = Color("e6d4a8")
		var prio: int = 65
		var lvls: int = 3
		if lm.kind == &"waystone":
			cat = &"waystones"
			col = Color("7fe3da")
			prio = 85
			lvls = 7
		elif lm.kind == &"ruin" or lm.kind == &"map_table" or String(lm.id).contains("tafel") or String(lm.id).contains("ruin"):
			cat = &"quests"
			col = Color("ffd98a")
			prio = 90
			lvls = 7
		elif lm.kind == &"vista" or lm.kind == &"lighthouse":
			cat = &"nature"
			col = Color("cbaaff")
			prio = 75
			lvls = 3
		elif lm.kind == &"campfire" or lm.kind == &"camp":
			cat = &"nature"
			col = Color("f7d98b")
			prio = 80
			lvls = 7
		var lm_lbl: String = lm.name if not lm.name.is_empty() else String(lm.id).replace("_", " ").to_upper()
		items.append({
			"id": lm.id,
			"kind": lm.kind,
			"category": cat,
			"pos": lm.pos,
			"zone": z_id,
			"levels": lvls,
			"priority": prio,
			"label": lm_lbl,
			"anim": &"pulse" if cat == &"quests" else &"",
			"color": col,
			"data": {},
		})
		added_landmarks += 1

	if added_landmarks == 0:
		var c: Vector2 = z.center()
		items.append({
			"id": &"preview_quest",
			"kind": &"quest",
			"category": &"quests",
			"pos": c + Vector2(-22.0, -14.0),
			"zone": z_id,
			"levels": 7,
			"priority": 90,
			"label": "STEINSETZER-TAFEL",
			"anim": &"pulse",
			"color": Color("ffd98a"),
			"data": {},
		})
		items.append({
			"id": &"preview_waystone",
			"kind": &"waystone",
			"category": &"waystones",
			"pos": c + Vector2(18.0, -12.0),
			"zone": z_id,
			"levels": 7,
			"priority": 85,
			"label": "WEGSTEIN",
			"anim": &"glow",
			"color": Color("7fe3da"),
			"data": {},
		})

	var prov: Callable = func(_ctx: Dictionary) -> Array[Dictionary]:
		return items
	_markers.call(&"register_provider", &"preview_samples", prov)
