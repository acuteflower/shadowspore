extends Node2D
## Standalone character, 8-direction floating rig, scale vs floating Ellie & dialogue portrait preview
## for redesigned Caelia v2 (docs/caelia_interstellar_konzept.md).
##
## Usage:
##   Godot --rendering-driver opengl3 --path . res://tools/preview_goddess.tscn -- --dir=/abs/output_dir

const GODDESS_TEX: Texture2D = preload("res://assets/characters/goddess.png")
const GODDESS_GLOW_TEX: Texture2D = preload("res://assets/characters/goddess_glow.png")
const PORTRAIT_TEX: Texture2D = preload("res://assets/ui/portrait_goddess.png")
const ELLIE_FLOAT_TEX: Texture2D = preload("res://assets/characters/player_float.png")
const RIG_PATH: String = "res://data/goddess_rig.json"

var _out_dir: String = ""
var _time: float = 0.0
var _fw: int = 128
var _fh: int = 144
var _anchor_x: float = 64.0
var _anchor_y: float = 78.0
var _clips: Dictionary = {}
var _live_actors: Array[Dictionary] = []
var _blink_rect: TextureRect = null
var _open_atlas: AtlasTexture = null
var _blink_atlas: AtlasTexture = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_parse_cli_args()
	var ok: bool = _load_and_verify_assets()
	_build_preview_scene()
	if not ok:
		push_error("Goddess v2 asset contract verification failed.")
		if not _out_dir.is_empty() or DisplayServer.get_name() == "headless":
			get_tree().quit(1)
		return
	if not _out_dir.is_empty() or DisplayServer.get_name() == "headless":
		_run_capture.call_deferred()


func _parse_cli_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--capture="):
			_out_dir = arg.substr(10)
	if _out_dir.is_empty():
		for arg2: String in OS.get_cmdline_args():
			if arg2.begins_with("--dir="):
				_out_dir = arg2.substr(6)
			elif arg2.begins_with("--capture="):
				_out_dir = arg2.substr(10)


func _load_and_verify_assets() -> bool:
	var ok: bool = true
	if not FileAccess.file_exists(RIG_PATH):
		push_error("Missing rig JSON: " + RIG_PATH)
		return false

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_PATH))
	if not (parsed is Dictionary):
		push_error("Invalid JSON in " + RIG_PATH)
		return false

	var rig: Dictionary = parsed as Dictionary
	var fs: Array = rig.get("frame_size", [128, 144]) as Array
	_fw = int(fs[0])
	_fh = int(fs[1])
	var ft: Array = rig.get("feet", [64, 78]) as Array
	_anchor_x = float(ft[0])
	_anchor_y = float(ft[1])
	_clips = rig.get("clips", {}) as Dictionary

	var cols: int = int(rig.get("columns", 28))
	var rows: int = int(rig.get("rows", 8))
	var expected_size: Vector2i = Vector2i(cols * _fw, rows * _fh)
	if Vector2i(GODDESS_TEX.get_size()) != expected_size:
		push_error("Unexpected goddess.png size: %s vs %s" % [str(GODDESS_TEX.get_size()), str(expected_size)])
		ok = false
	if Vector2i(GODDESS_GLOW_TEX.get_size()) != expected_size:
		push_error("Unexpected goddess_glow.png size: %s vs %s" % [str(GODDESS_GLOW_TEX.get_size()), str(expected_size)])
		ok = false

	var req_clips: Dictionary = {"float_idle": 8, "float_talk": 8, "float_bless": 12}
	for cname_v: Variant in req_clips.keys():
		var cname: String = String(cname_v)
		if not _clips.has(cname):
			push_error("Missing clip: " + cname)
			ok = false
		elif int((_clips[cname] as Dictionary).get("count", 0)) != int(req_clips[cname]):
			push_error("Clip %s count mismatch" % cname)
			ok = false

	if Vector2i(PORTRAIT_TEX.get_size()) != Vector2i(206, 153):
		push_error("Unexpected portrait_goddess.png size: " + str(PORTRAIT_TEX.get_size()))
		ok = false

	_open_atlas = AtlasTexture.new()
	_open_atlas.atlas = PORTRAIT_TEX
	_open_atlas.region = Rect2(0.0, 0.0, 103.0, 153.0)
	_blink_atlas = AtlasTexture.new()
	_blink_atlas.atlas = PORTRAIT_TEX
	_blink_atlas.region = Rect2(103.0, 0.0, 103.0, 153.0)
	if not DialogueArt.valid_portrait(_open_atlas) or not DialogueArt.valid_portrait(_blink_atlas):
		push_error("Portrait cells do not satisfy DialogueArt.LOGICAL_SIZE")
		ok = false
	return ok


func _build_preview_scene() -> void:
	var mod: CanvasModulate = CanvasModulate.new()
	mod.color = Color(0.84, 0.86, 0.98, 1.0)
	add_child(mod)

	var bg: ColorRect = ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(640.0, 360.0)
	bg.color = Color("#060412")
	bg.z_index = -20
	add_child(bg)

	for s_i: int in 64:
		var seed_v: float = float(s_i) * 1.6180339
		var star: ColorRect = ColorRect.new()
		star.position = Vector2(roundf(fmod(seed_v * 137.5, 636.0) + 2.0), roundf(fmod(seed_v * 211.3, 352.0) + 4.0))
		star.size = Vector2(1.0, 1.0)
		star.color = Color("#7ef4f0") if (s_i % 4 == 0) else (Color("#fff0b0") if (s_i % 5 == 0) else Color("#c8d6f8"))
		star.material = Unlit.material()
		star.z_index = -18
		add_child(star)

	_add_unlit_label("CAELIA V2 — FLOATING INTERSTELLAR GODDESS (8-DIR) & PORTRAIT", Vector2(12.0, 6.0), 11, Color("#fff3d1"))

	# Top row: S idle, SE talk, S bless
	_add_goddess_actor("float_idle", 2, Vector2(74.0, 114.0))
	_add_unlit_label("float_idle (S)", Vector2(40.0, 174.0), 9, Color("#b8f5f2"))

	_add_goddess_actor("float_talk", 1, Vector2(186.0, 114.0))
	_add_unlit_label("float_talk (SE)", Vector2(152.0, 174.0), 9, Color("#dfdcf2"))

	_add_goddess_actor("float_bless", 2, Vector2(302.0, 114.0))
	_add_unlit_label("float_bless (12f)", Vector2(264.0, 174.0), 9, Color("#ffe8a6"))

	# Bottom row: Back nebula hair (N), Side (W), Floating Ellie vs Floating Caelia scale check
	_add_goddess_actor("float_idle", 6, Vector2(74.0, 266.0))
	_add_unlit_label("Nebula Hair (N)", Vector2(38.0, 336.0), 9, Color("#b8f5f2"))

	_add_goddess_actor("float_idle", 4, Vector2(174.0, 266.0))
	_add_unlit_label("Profile (W)", Vector2(146.0, 336.0), 9, Color("#dfdcf2"))

	_add_goddess_actor("float_idle", 2, Vector2(316.0, 266.0))
	var ellie_sp: Sprite2D = Sprite2D.new()
	ellie_sp.texture = ELLIE_FLOAT_TEX
	ellie_sp.centered = false
	ellie_sp.offset = Vector2(-32.0, -34.0)
	ellie_sp.region_enabled = true
	ellie_sp.region_rect = Rect2(0.0, 128.0, 64.0, 64.0) # S float_idle
	ellie_sp.position = Vector2(246.0, 276.0)
	add_child(ellie_sp)
	_add_unlit_label("Ellie Zero-G vs Caelia", Vector2(228.0, 336.0), 9, Color("#b8f5f2"))

	# Right showcase: Redesigned Dialogue Portrait (open + blink)
	var card_bg: ColorRect = ColorRect.new()
	card_bg.position = Vector2(382.0, 28.0)
	card_bg.size = Vector2(246.0, 320.0)
	card_bg.color = Color("#120e24")
	card_bg.material = Unlit.material()
	add_child(card_bg)

	_add_unlit_label("portrait_goddess.png (206x153)", Vector2(394.0, 34.0), 10, Color("#fff3d1"))

	var open_rect: TextureRect = TextureRect.new()
	open_rect.texture = _open_atlas
	open_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	open_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	open_rect.material = Unlit.material()
	open_rect.position = Vector2(394.0, 56.0)
	open_rect.size = Vector2(103.0, 153.0)
	add_child(open_rect)

	var closed_rect: TextureRect = TextureRect.new()
	closed_rect.texture = _blink_atlas
	closed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	closed_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	closed_rect.material = Unlit.material()
	closed_rect.position = Vector2(512.0, 56.0)
	closed_rect.size = Vector2(103.0, 153.0)
	add_child(closed_rect)

	var dlg_bar: ColorRect = ColorRect.new()
	dlg_bar.position = Vector2(392.0, 236.0)
	dlg_bar.size = Vector2(226.0, 100.0)
	dlg_bar.color = Color("#0c091a")
	dlg_bar.material = Unlit.material()
	add_child(dlg_bar)

	_blink_rect = TextureRect.new()
	_blink_rect.texture = _open_atlas
	_blink_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blink_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_blink_rect.material = Unlit.material()
	_blink_rect.position = Vector2(396.0, 230.0)
	_blink_rect.size = Vector2(72.0, 107.0)
	add_child(_blink_rect)

	_add_unlit_label("CAELIA", Vector2(478.0, 246.0), 11, Color("#ffe8a6"))
	_add_unlit_label("„Lass die Schwere los.\nZwischen den Sternen\nträgt dich das Licht.“", Vector2(478.0, 266.0), 9, Color("#e8e5f8"))


func _add_unlit_label(txt: String, pos: Vector2, fsize: int, col: Color) -> Label:
	var lbl: Label = Label.new()
	lbl.text = txt
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", col)
	lbl.material = Unlit.material()
	lbl.z_index = 20
	add_child(lbl)
	return lbl


func _add_goddess_actor(clip_name: String, row_idx: int, anchor_pos: Vector2) -> void:
	var clip_d: Dictionary = _clips.get(clip_name, {"start": 0, "count": 8, "fps": 6}) as Dictionary
	var start_col: int = int(clip_d.get("start", 0))
	var count_fr: int = maxi(1, int(clip_d.get("count", 8)))
	var fps_val: float = float(clip_d.get("fps", 6.0))
	var off: Vector2 = Vector2(-_anchor_x, -_anchor_y)
	var init_rect: Rect2 = Rect2(float(start_col * _fw), float(row_idx * _fh), float(_fw), float(_fh))

	var sp: Sprite2D = Sprite2D.new()
	sp.texture = GODDESS_TEX
	sp.centered = false
	sp.offset = off
	sp.position = anchor_pos
	sp.region_enabled = true
	sp.region_rect = init_rect
	add_child(sp)

	var gl: Sprite2D = Sprite2D.new()
	gl.texture = GODDESS_GLOW_TEX
	gl.centered = false
	gl.offset = off
	gl.material = Unlit.material()
	gl.region_enabled = true
	gl.region_rect = init_rect
	sp.add_child(gl)

	_live_actors.append({"sprite": sp, "glow": gl, "start": start_col, "count": count_fr, "fps": fps_val, "row": row_idx})


func _process(delta: float) -> void:
	_advance_visuals(_time + delta)


func _advance_visuals(new_time: float) -> void:
	_time = new_time
	for actor: Dictionary in _live_actors:
		var sp: Sprite2D = actor["sprite"] as Sprite2D
		var gl: Sprite2D = actor["glow"] as Sprite2D
		var col: int = int(actor["start"]) + posmod(int(floor(_time * float(actor["fps"]))), int(actor["count"]))
		var rect: Rect2 = Rect2(float(col * _fw), float(int(actor["row"]) * _fh), float(_fw), float(_fh))
		sp.region_rect = rect
		gl.region_rect = rect

	if _blink_rect != null and _open_atlas != null and _blink_atlas != null:
		_blink_rect.texture = _blink_atlas if (fmod(_time, 3.6) > 3.35) else _open_atlas


func _run_capture() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless" and not _out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_out_dir)
		_advance_visuals(0.75)
		for _i: int in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var live_path: String = _out_dir.path_join("goddess_live_preview.png")
		get_viewport().get_texture().get_image().save_png(live_path)
		print("Captured ", live_path)
	print("GODDESS PREVIEW OK")
	get_tree().quit(0)
