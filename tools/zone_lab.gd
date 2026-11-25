extends "res://src/world/test_level.gd"
## Zone lab (docs/v2_zonenwelt_atlas_konzept.md 13, step 3): the first real piece of the 2.0 zone world. Two placeholder
## zones of `data/world/` (LABORWIESE, LABORWALD) streamed by `ZoneDirector` at their real continent coordinates, with
## v2 nature (GroundSurfaces, LivingGrass, LivingTree), joined by one seamless threshold (the trail under the crowns).
## Sandbox: `SaveGame` never touches it (group `sandbox`); F8 writes the zone state to `user://zone_lab.json`,
## `-- --continue` starts from it. F7 = next day (to watch the catch-up).
##
##   Godot --path . tools/zone_lab.tscn [-- --continue] [--at=x,y (tiles)] [--capture=/abs.png [--hold=seconds]]

const START_TILE: Vector2 = Vector2(1060.0, 968.0)
const SAVE_PATH: String = "user://zone_lab.json"
const BACKDROP: Color = Color(0.043, 0.063, 0.055)


class LabMapStub:
	extends RefCounted
	var world_seed: int = 42


var _map: LabMapStub = LabMapStub.new() ## WorldWind reads `_map.world_seed`
var director: ZoneDirector
var _wind: WorldWind
var _label: Label
var _start: Vector2 = START_TILE
var _continue: bool = false
var _capture: String = "" ## `--capture=/abs.png`: wait until every zone near the start is in, save a picture, quit
var _capture_wait: int = 0
var _capture_frames: int = 0 ## frames since start: a neighbour within reach is queued in the first ones
var _capture_after: float = 0.0 ## `--hold=seconds`: capture this long after the lab started (the arrival inscriptions run in real time), 0 = 90 frames after streaming settled
var _started_ms: int = 0


func _ready() -> void:
	add_to_group("sandbox")
	_parse_args()
	_started_ms = Time.get_ticks_msec()
	RenderingServer.set_default_clear_color(BACKDROP)
	director = ZoneDirector.new()
	director.setup(Atlas.shared(), &"lab", _ground.tile_set, _ground.material, _players)
	add_child(director)
	if _continue and FileAccess.file_exists(SAVE_PATH):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if raw is Dictionary:
			director.import_state(raw as Dictionary)
	var first: StringName = director.atlas.zone_at_tile(&"lab", _start)
	director.load_now(first if first != &"" else &"labor_wiese")
	super._ready()
	_wind = WorldWind.new()
	_wind.name = "WorldWind"
	_wind.setup(self)
	add_child(_wind)
	_build_status()


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--continue":
			_continue = true
		elif arg.begins_with("--capture="):
			_capture = arg.substr(10)
		elif arg.begins_with("--hold="):
			_capture_after = arg.substr(7).to_float()
		elif arg.begins_with("--at="):
			var parts: PackedStringArray = arg.substr(5).split(",")
			if parts.size() == 2:
				_start = Vector2(parts[0].to_float(), parts[1].to_float())


func _fill_ground() -> void:
	pass ## the zones paint their own ground


func _land_biome(_tile: Vector2i) -> String:
	return "meadow"


func navigation_floor(pos: Vector2) -> bool:
	return director != null and director.atlas.zone_at(&"lab", pos) != &""


func _spawn_position(index: int) -> Vector2:
	return Atlas.px_of(_start) + Vector2(16.0 * float(index), 0.0)


func _clamp_spawn(pos: Vector2) -> Vector2:
	return pos


func spawn_point() -> Vector2:
	return _spawn_position(0)


func _process(delta: float) -> void:
	super._process(delta)
	_update_status()
	if not _capture.is_empty():
		_step_capture()


func _step_capture() -> void:
	_capture_frames += 1
	if director.is_building() or director.stages.is_empty() or _capture_frames < 150:
		_capture_wait = 0
		return
	_capture_wait += 1
	var due: bool = _capture_wait == 90 if _capture_after <= 0.0 else (_capture_wait >= 2 and float(Time.get_ticks_msec() - _started_ms) / 1000.0 >= _capture_after)
	if due:
		var path: String = _capture
		_capture = "" ## once only
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(path)
		print("ZONE LAB CAPTURE ", path, " ", director.build_log)
		get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F7:
			if multiplayer.is_server():
				TimeManager.day += 1
				TimeManager.day_started.emit(TimeManager.day)
		KEY_F8:
			if multiplayer.is_server():
				var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
				if file != null:
					file.store_string(JSON.stringify(director.export_state()))


# --- status card ------------------------------------------------------------------------------------------------------

func _build_status() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "ZoneLabStatus"
	layer.layer = 90
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(6.0, 80.0) ## below the clock vine and the place line of ZoneArrival
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color("e8e2c8"))
	_label.add_theme_color_override("font_outline_color", Color("1b1a2e"))
	_label.add_theme_constant_override("outline_size", 3)
	layer.add_child(_label)


func _update_status() -> void:
	if _label == null or director == null:
		return
	var me: int = multiplayer.get_unique_id()
	var here: StringName = director.player_zone.get(me, &"") as StringName
	var zone: Atlas.Zone = director.atlas.zone(here)
	var lines: PackedStringArray = []
	lines.append("ZONENLABOR  %s%s" % [zone.name if zone != null else "-", ("  (" + String(zone.danger).to_upper() + ")") if zone != null else ""])
	var player: Node2D = _players.get_node_or_null(str(me)) as Node2D
	if player != null:
		var tile: Vector2 = Atlas.tile_of(player.global_position).floor()
		lines.append("TILE %d, %d   TAG %d" % [int(tile.x), int(tile.y), TimeManager.day])
	var loaded: PackedStringArray = []
	for id: StringName in director.stages:
		loaded.append(String(id))
	lines.append("GELADEN: %s%s" % [", ".join(loaded), "   (BAUT...)" if director.is_building() else ""])
	lines.append("SCHWELLE KRONENGANG: %s" % ("OFFEN" if director.threshold_open(&"labor_kronengang") else "ZU"))
	lines.append("F7 NÄCHSTER TAG   F8 SPEICHERN")
	_label.text = "\n".join(lines)
