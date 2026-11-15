extends Node
## Visual capture suite for ZoneWorld & two-tier MapWindow.
## godot --path . res://tools/preview_zones.tscn -- --dir=/abs/output/dir

const ZONE_WORLD_SCENE: PackedScene = preload("res://src/world/zones/zone_world.tscn")


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i: int in range(n):
		await get_tree().process_frame


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err: Error = get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE %s -> %s" % [path, error_string(err)])


func _run() -> void:
	var out_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			out_dir = arg.trim_prefix("--dir=")
	if out_dir.is_empty():
		print("Usage: -- --dir=/abs/output/dir")
		get_tree().quit(1)
		return

	var world: ZoneWorld = ZONE_WORLD_SCENE.instantiate() as ZoneWorld
	add_child(world)
	await _frames(4)

	TimeManager.lock_at(0.42) ## Crisp bright daylight for inspection
	var dn: Node = world.get_node_or_null("DayNight")
	if dn != null and dn.has_method("set_night"):
		dn.call("set_night", 0.0)

	var p1: Player = world._players.get_child(0) as Player
	var cam: Camera2D = p1.get("_camera") as Camera2D
	if cam != null:
		cam.zoom = Vector2(0.75, 0.75)

	## 1) start_path near FallenKnight + Signpost + footpaths
	var sp_zone: ZoneInstance = world.active_zones().get("start_path") as ZoneInstance
	if sp_zone != null:
		var knight_pos: Vector2 = sp_zone.fallen_knight.global_position if sp_zone.fallen_knight != null else sp_zone.spawn_position("default")
		p1.request_teleport(knight_pos + Vector2(-40.0, 20.0))
		world.apply_camera_bounds(p1)
	await _frames(6)
	await _capture(out_dir.path_join("zone_start_path.png"))

	## 2) home_valley around Valdric's hut, waystone & pond
	p1.wounded = false
	p1.health.current = p1.health.max_health
	p1.sync_wound_visuals()
	if cam != null:
		cam.zoom = Vector2(0.55, 0.55)
	world.travel_to_zone(p1.name.to_int(), "home_valley", "respawn", true)
	await _frames(6)
	var hv_zone: ZoneInstance = world.active_zones().get("home_valley") as ZoneInstance
	if hv_zone != null and hv_zone.hut_node != null:
		p1.request_teleport(hv_zone.hut_node.global_position + Vector2(140.0, 150.0))
		world.apply_camera_bounds(p1)
	await _frames(6)
	await _capture(out_dir.path_join("zone_home_valley.png"))

	## 3) MapWindow Tier 1 (Zone Detail) + 4) MapWindow Tier 2 (Main Continent)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var map_win: MapWindow = MapWindow.new()
	layer.add_child(map_win)
	map_win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_win._set_open(true)
	await get_tree().create_timer(0.6).timeout
	map_win.set_zone_map_mode("zone", "home_valley")
	await _frames(6)
	await _capture(out_dir.path_join("zone_map_tier1.png"))

	map_win.set_zone_map_mode("continent")
	await _frames(6)
	await _capture(out_dir.path_join("zone_map_tier2.png"))

	get_tree().quit(0)
