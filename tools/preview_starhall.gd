extends Node2D
## Standalone scenic & parallax preview for Caelia's new open Interstellar Sanctuary
## (docs/caelia_interstellar_konzept.md).
## Renders the live StarHallRoom (8-layer interstellar parallax, ringed shadowed world,
## Milky Way dark dust lanes, dual volumetric nebulae, foreground depth dust, floating Caelia v2,
## floating vertical Return Rift, and floating Ellie in idle / glide poses across shifted viewpoints).
##
## Usage:
##   Godot --rendering-driver opengl3 --path . res://tools/preview_starhall.tscn -- --dir=/abs/output_dir

const ELLIE_FLOAT_TEX: Texture2D = preload("res://assets/characters/player_float.png")

var _out_dir: String = ""
var _room: StarHallRoom
var _cam: Camera2D
var _ellie: Sprite2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--capture="):
			_out_dir = arg.substr(10)
	_build()
	if not _out_dir.is_empty() or DisplayServer.get_name() == "headless":
		_run_capture.call_deferred()


func _build() -> void:
	var mod: CanvasModulate = CanvasModulate.new()
	mod.color = Color("#58567c")
	add_child(mod)

	_room = StarHallRoom.new()
	add_child(_room)

	_ellie = Sprite2D.new()
	_ellie.name = "PreviewEllie"
	_ellie.texture = ELLIE_FLOAT_TEX
	_ellie.hframes = 56
	_ellie.vframes = 8
	_ellie.offset = Vector2(0.0, -20.0)
	_ellie.position = Vector2(1048.0, 1146.0)
	_ellie.frame = 7 * 56 + 10 # NE drift toward Caelia
	var ellie_rim: PointLight2D = PointLight2D.new()
	ellie_rim.position = Vector2(0.0, -18.0)
	ellie_rim.color = Color("b6dcff")
	ellie_rim.energy = 0.34
	LightTexture.apply(ellie_rim, 88, 0.86, 0)
	_ellie.add_child(ellie_rim)
	_room.add_child(_ellie)

	_cam = Camera2D.new()
	_cam.enabled = true
	_cam.position = Vector2(1080.0, 1110.0)
	add_child(_cam)


func _capture_view(shot_name: String, cam_pos: Vector2, ellie_pos: Vector2, ellie_frame: int, sim_t: float) -> void:
	_cam.position = cam_pos
	_ellie.position = ellie_pos
	_ellie.frame = ellie_frame
	_room._time = sim_t
	for _i: int in 6:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless" and not _out_dir.is_empty():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_out_dir)
		var out_file: String = _out_dir.path_join(shot_name + ".png")
		get_viewport().get_texture().get_image().save_png(out_file)
		print("Captured ", out_file)


func _run_capture() -> void:
	await get_tree().process_frame
	# 1. Caelia's clearing with floating Ellie approaching & ringed world in upper-left deep parallax
	await _capture_view("interstellar_center", Vector2(1078.0, 1106.0), Vector2(1038.0, 1148.0), 7 * 56 + 2, 1.4)
	# 2. Arrival Rift view (Ellie arriving 44 px north of the glowing vertical Astrolabe Return Rift)
	await _capture_view("interstellar_arrival", Vector2(1100.0, 1408.0), Vector2(1100.0, 1390.0), 6 * 56 + 34, 2.2)
	# 3. Wide parallax flight east + Boost-Glide pose (shows multi-layer parallax shift vs center!)
	await _capture_view("interstellar_glide_east", Vector2(1620.0, 940.0), Vector2(1590.0, 940.0), 0 * 56 + 18, 3.1)
	# 4. Caelia blessing pose closeup
	if _room.goddess != null:
		_room.goddess.play_bless()
		_room.goddess._clip_t = 0.65
	await _capture_view("interstellar_caelia_bless", Vector2(1100.0, 1104.0), Vector2(1042.0, 1152.0), 7 * 56 + 0, 4.0)
	print("STARHALL PREVIEW OK")
	get_tree().quit(0)
