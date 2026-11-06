extends Node
## Actual map renderer, isolated from the world and all save files.
## Godot --path . tools/preview_map.tscn -- --capture=/absolute/path.png


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	TimeManager.time_of_day = 0.45
	TimeManager.set_process(false)
	var discovery: MapDiscovery = MapDiscovery.new()
	add_child(discovery)
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(MapDiscovery.GRID * MapDiscovery.GRID)
	seen.fill(1)
	discovery.import_data(seen.compress(FileAccess.COMPRESSION_ZSTD))
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var map: MapWindow = MapWindow.new()
	layer.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map._set_open(true)
	map._center = Vector2(550, 550)
	map._scale_target = 0.31
	map._scale = 0.31
	var capture: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture = argument.trim_prefix("--capture=")
		elif argument.begins_with("--zoom="):
			map._scale = clampf(argument.trim_prefix("--zoom=").to_float(), MapWindow.SCALE_MIN, MapWindow.SCALE_MAX)
			map._scale_target = map._scale
		elif argument.begins_with("--at="):
			var coords: PackedStringArray = argument.trim_prefix("--at=").split(",")
			map._center = Vector2(coords[0].to_float(), coords[1].to_float())
		elif argument == "--night":
			TimeManager.time_of_day = 0.98
	if not capture.is_empty():
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		print("Map state: loaded=", map._loaded, " visible=", map.visible, " size=", map.size, " open=", map._open_t)
		var result: Error = get_viewport().get_texture().get_image().save_png(capture)
		print("World map capture: ", error_string(result))
		get_tree().quit(0 if result == OK else 1)
