extends Node2D
## Standalone character, rig, throne-fit & dialogue portrait preview for the Star Hall Goddess.
## Verifies:
##   - assets/characters/goddess.png + assets/characters/goddess_glow.png (Unlit)
##   - data/goddess_rig.json (sit_idle 6f, sit_talk 6f, sit_bless 8f, stand_idle 6f; S/SE/SW)
##   - Seated alignment on assets/interior/starhall/throne.png + 1.6x scale vs Ellie (player.png)
##   - assets/ui/portrait_goddess.png (206x153 = two 103x153 cells: open + blink)
##
## Usage:
##   Godot --rendering-driver opengl3 --path . res://tools/preview_goddess.tscn -- --dir=/abs/output_dir

const GODDESS_TEX: Texture2D = preload("res://assets/characters/goddess.png")
const GODDESS_GLOW_TEX: Texture2D = preload("res://assets/characters/goddess_glow.png")
const PORTRAIT_TEX: Texture2D = preload("res://assets/ui/portrait_goddess.png")
const RIG_PATH: String = "res://data/goddess_rig.json"
const PLAYER_PATH: String = "res://assets/characters/player.png"
const THRONE_PATH: String = "res://assets/interior/starhall/throne.png"
const THRONE_GLOW_PATH: String = "res://assets/interior/starhall/throne_glow.png"

var _out_dir: String = ""
var _time: float = 0.0
var _fw: int = 96
var _fh: int = 112
var _foot_x: float = 48.0
var _ground_row: float = 94.0
var _clips: Dictionary = {}
var _live_actors: Array[Dictionary] = []
var _throne_sprites: Array[Sprite2D] = []
var _blink_rect: TextureRect = null
var _open_atlas: AtlasTexture = null
var _blink_atlas: AtlasTexture = null


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_parse_cli_args()
	var ok: bool = _load_and_verify_assets()
	_build_preview_scene()
	if not ok:
		push_error("Goddess asset contract verification failed.")
		if not _out_dir.is_empty() or DisplayServer.get_name() == "headless":
			get_tree().quit(1)
		return
	if not _out_dir.is_empty() or DisplayServer.get_name() == "headless":
		_run_capture.call_deferred()


func _parse_cli_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in all_args:
		if arg.begins_with("--dir="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--capture="):
			_out_dir = arg.substr(10)
	if _out_dir.is_empty():
		var sys_args: PackedStringArray = OS.get_cmdline_args()
		for arg2: String in sys_args:
			if arg2.begins_with("--dir="):
				_out_dir = arg2.substr(6)
			elif arg2.begins_with("--capture="):
				_out_dir = arg2.substr(10)


func _load_and_verify_assets() -> bool:
	var ok: bool = true
	if not FileAccess.file_exists(RIG_PATH):
		push_error("Missing rig JSON: " + RIG_PATH)
		return false

	var raw_json: String = FileAccess.get_file_as_string(RIG_PATH)
	var parsed: Variant = JSON.parse_string(raw_json)
	if not (parsed is Dictionary):
		push_error("Invalid JSON in " + RIG_PATH)
		return false

	var rig: Dictionary = parsed as Dictionary
	if rig.has("frame_size") and rig["frame_size"] is Array:
		var fs: Array = rig["frame_size"] as Array
		if fs.size() >= 2:
			_fw = int(fs[0])
			_fh = int(fs[1])
	if rig.has("feet") and rig["feet"] is Array:
		var ft: Array = rig["feet"] as Array
		if ft.size() >= 2:
			_foot_x = float(ft[0])
			_ground_row = float(ft[1])
	if rig.has("clips") and rig["clips"] is Dictionary:
		_clips = rig["clips"] as Dictionary

	var cols: int = int(rig.get("columns", 26))
	var rows: int = int(rig.get("rows", 3))
	var expected_size: Vector2i = Vector2i(cols * _fw, rows * _fh)
	if Vector2i(GODDESS_TEX.get_size()) != expected_size:
		push_error("Unexpected goddess.png size: %s vs %s" % [str(GODDESS_TEX.get_size()), str(expected_size)])
		ok = false
	if Vector2i(GODDESS_GLOW_TEX.get_size()) != expected_size:
		push_error("Unexpected goddess_glow.png size: %s vs %s" % [str(GODDESS_GLOW_TEX.get_size()), str(expected_size)])
		ok = false

	var req_clips: Dictionary = {
		"sit_idle": 6,
		"sit_talk": 6,
		"sit_bless": 8,
		"stand_idle": 6,
	}
	for clip_name_var: Variant in req_clips.keys():
		var clip_name: String = String(clip_name_var)
		if not _clips.has(clip_name):
			push_error("Missing clip in goddess_rig.json: " + clip_name)
			ok = false
		else:
			var cdict: Dictionary = _clips[clip_name] as Dictionary
			var cnt: int = int(cdict.get("count", 0))
			var want_cnt: int = int(req_clips[clip_name])
			if cnt != want_cnt:
				push_error("Clip %s count=%d (expected %d)" % [clip_name, cnt, want_cnt])
				ok = false

	var p_size: Vector2i = Vector2i(PORTRAIT_TEX.get_size())
	if p_size != Vector2i(206, 153):
		push_error("Unexpected portrait_goddess.png size: %s (expected 206x153)" % str(p_size))
		ok = false

	_open_atlas = AtlasTexture.new()
	_open_atlas.atlas = PORTRAIT_TEX
	_open_atlas.region = Rect2(0.0, 0.0, 103.0, 153.0)

	_blink_atlas = AtlasTexture.new()
	_blink_atlas.atlas = PORTRAIT_TEX
	_blink_atlas.region = Rect2(103.0, 0.0, 103.0, 153.0)

	if not DialogueArt.valid_portrait(_open_atlas) or not DialogueArt.valid_portrait(_blink_atlas):
		push_error("Portrait cells do not satisfy DialogueArt.LOGICAL_SIZE (103x153)")
		ok = false

	return ok


func _build_preview_scene() -> void:
	# Ambient starlight modulation so Unlit glow overlay stands out just like in the Star Hall
	var mod: CanvasModulate = CanvasModulate.new()
	mod.color = Color(0.86, 0.88, 0.98, 1.0)
	add_child(mod)

	# Deep cosmic starfield backdrop (640x360)
	var bg: ColorRect = ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size = Vector2(640.0, 360.0)
	bg.color = Color("#0e0b1c")
	bg.z_index = -20
	add_child(bg)

	for s_i: int in 48:
		var seed_v: float = float(s_i) * 1.6180339
		var sx: float = roundf(fmod(seed_v * 137.5, 636.0) + 2.0)
		var sy: float = roundf(fmod(seed_v * 211.3, 352.0) + 4.0)
		var star: ColorRect = ColorRect.new()
		star.position = Vector2(sx, sy)
		star.size = Vector2(2.0, 2.0) if (s_i % 7 == 0) else Vector2(1.0, 1.0)
		star.color = Color("#7ef4f0") if (s_i % 3 == 0) else Color("#fff5d8")
		star.material = Unlit.material()
		star.z_index = -18
		add_child(star)

	# Title banner
	_add_unlit_label("STAR HALL GODDESS — SPRITES, GLOW, THRONE FIT & PORTRAIT", Vector2(14.0, 8.0), 12, Color("#fff3d1"))

	# Left showcase: Throne + Seated Bless / Seated Idle / Seated Talk / Standing + Ellie Scale
	var throne_pos: Vector2 = Vector2(96.0, 184.0)
	if ResourceLoader.exists(THRONE_PATH):
		var t_tex: Texture2D = ResourceLoader.load(THRONE_PATH) as Texture2D
		if t_tex != null:
			var t_sp: Sprite2D = Sprite2D.new()
			t_sp.texture = t_tex
			t_sp.centered = false
			t_sp.offset = Vector2(-80.0, -148.0)
			t_sp.hframes = 8
			t_sp.position = throne_pos
			add_child(t_sp)
			_throne_sprites.append(t_sp)

			if ResourceLoader.exists(THRONE_GLOW_PATH):
				var tg_tex: Texture2D = ResourceLoader.load(THRONE_GLOW_PATH) as Texture2D
				if tg_tex != null:
					var tg_sp: Sprite2D = Sprite2D.new()
					tg_sp.texture = tg_tex
					tg_sp.centered = false
					tg_sp.offset = Vector2(-80.0, -148.0)
					tg_sp.hframes = 8
					tg_sp.material = Unlit.material()
					t_sp.add_child(tg_sp)
					_throne_sprites.append(tg_sp)

	_add_goddess_actor("sit_idle", 0, Vector2(96.0, 185.0))
	_add_unlit_label("sit_idle (Throne)", Vector2(52.0, 198.0), 10, Color("#b8f5f2"))

	# Clip strip along bottom-left & center: sit_talk (S), sit_bless (S), sit_idle (SE), stand_idle (S) + Ellie
	_add_stage_plinth(Vector2(214.0, 185.0), 62.0)
	_add_goddess_actor("sit_talk", 0, Vector2(214.0, 185.0))
	_add_unlit_label("sit_talk (S)", Vector2(186.0, 198.0), 10, Color("#dfdcf2"))

	_add_stage_plinth(Vector2(292.0, 185.0), 62.0)
	_add_goddess_actor("sit_bless", 0, Vector2(292.0, 185.0))
	_add_unlit_label("sit_bless (8f)", Vector2(258.0, 198.0), 10, Color("#ffe8a6"))

	_add_stage_plinth(Vector2(106.0, 326.0), 64.0)
	_add_goddess_actor("sit_idle", 1, Vector2(106.0, 326.0))
	_add_unlit_label("sit_idle (SE)", Vector2(74.0, 338.0), 10, Color("#dfdcf2"))

	_add_stage_plinth(Vector2(194.0, 326.0), 64.0)
	_add_goddess_actor("sit_bless", 2, Vector2(194.0, 326.0))
	_add_unlit_label("sit_bless (SW)", Vector2(158.0, 338.0), 10, Color("#dfdcf2"))

	_add_stage_plinth(Vector2(304.0, 326.0), 96.0)
	_add_goddess_actor("stand_idle", 0, Vector2(322.0, 326.0))
	if ResourceLoader.exists(PLAYER_PATH):
		var p_tex: Texture2D = ResourceLoader.load(PLAYER_PATH) as Texture2D
		if p_tex != null:
			var ellie_sp: Sprite2D = Sprite2D.new()
			ellie_sp.texture = p_tex
			ellie_sp.centered = false
			ellie_sp.offset = Vector2(-32.0, -56.0)
			ellie_sp.region_enabled = true
			ellie_sp.region_rect = Rect2(0.0, 0.0, 64.0, 64.0)
			ellie_sp.position = Vector2(276.0, 326.0)
			add_child(ellie_sp)
	_add_unlit_label("Ellie vs stand_idle (66px)", Vector2(246.0, 338.0), 10, Color("#b8f5f2"))

	# Right showcase: Dialogue Portrait (Open 1x, Blink 1x, and Live Animated 1.5x card)
	var card_bg: ColorRect = ColorRect.new()
	card_bg.position = Vector2(382.0, 30.0)
	card_bg.size = Vector2(246.0, 318.0)
	card_bg.color = Color("#17132a")
	card_bg.material = Unlit.material()
	add_child(card_bg)

	_add_unlit_label("portrait_goddess.png (206x153)", Vector2(392.0, 36.0), 10, Color("#fff3d1"))

	var open_rect: TextureRect = TextureRect.new()
	open_rect.texture = _open_atlas
	open_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	open_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	open_rect.material = Unlit.material()
	open_rect.position = Vector2(394.0, 56.0)
	open_rect.size = Vector2(103.0, 153.0)
	add_child(open_rect)
	_add_unlit_label("open (103x153)", Vector2(404.0, 212.0), 9, Color("#b8f5f2"))

	var closed_rect: TextureRect = TextureRect.new()
	closed_rect.texture = _blink_atlas
	closed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	closed_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	closed_rect.material = Unlit.material()
	closed_rect.position = Vector2(512.0, 56.0)
	closed_rect.size = Vector2(103.0, 153.0)
	add_child(closed_rect)
	_add_unlit_label("blink (103x153)", Vector2(522.0, 212.0), 9, Color("#dfdcf2"))

	# Live blinking dialogue-box preview strip at bottom right
	var dlg_bar: ColorRect = ColorRect.new()
	dlg_bar.position = Vector2(392.0, 236.0)
	dlg_bar.size = Vector2(226.0, 102.0)
	dlg_bar.color = Color("#110d20")
	dlg_bar.material = Unlit.material()
	add_child(dlg_bar)

	_blink_rect = TextureRect.new()
	_blink_rect.texture = _open_atlas
	_blink_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blink_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_blink_rect.material = Unlit.material()
	_blink_rect.position = Vector2(396.0, 232.0)
	_blink_rect.size = Vector2(72.0, 107.0)
	add_child(_blink_rect)

	_add_unlit_label("DIE GÖTTIN", Vector2(478.0, 246.0), 11, Color("#ffe8a6"))
	_add_unlit_label("„Tritt näher, Sternenkind.\nDein Licht ruht noch in dir.“", Vector2(478.0, 268.0), 9, Color("#e8e5f8"))


func _add_stage_plinth(center: Vector2, width: float) -> void:
	var plinth: ColorRect = ColorRect.new()
	plinth.position = Vector2(roundf(center.x - width * 0.5), roundf(center.y - 3.0))
	plinth.size = Vector2(roundf(width), 6.0)
	plinth.color = Color("#2a2448")
	plinth.z_index = -4
	add_child(plinth)

	var rim: ColorRect = ColorRect.new()
	rim.position = Vector2(roundf(center.x - width * 0.5 + 2.0), roundf(center.y - 3.0))
	rim.size = Vector2(roundf(width - 4.0), 1.0)
	rim.color = Color("#8f86ba")
	rim.z_index = -3
	add_child(rim)


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
	var clip_d: Dictionary = _clips.get(clip_name, {"start": 0, "count": 6, "fps": 6}) as Dictionary
	var start_col: int = int(clip_d.get("start", 0))
	var count_fr: int = maxi(1, int(clip_d.get("count", 6)))
	var fps_val: float = float(clip_d.get("fps", 6.0))
	var off: Vector2 = Vector2(-_foot_x, -_ground_row)
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

	_live_actors.append({
		"sprite": sp,
		"glow": gl,
		"start": start_col,
		"count": count_fr,
		"fps": fps_val,
		"row": row_idx,
	})


func _process(delta: float) -> void:
	_advance_visuals(_time + delta)


func _advance_visuals(new_time: float) -> void:
	_time = new_time
	for actor: Dictionary in _live_actors:
		var sp: Sprite2D = actor["sprite"] as Sprite2D
		var gl: Sprite2D = actor["glow"] as Sprite2D
		var st: int = int(actor["start"])
		var cnt: int = int(actor["count"])
		var fps_v: float = float(actor["fps"])
		var r_idx: int = int(actor["row"])
		var col: int = st + posmod(int(floor(_time * fps_v)), cnt)
		var rect: Rect2 = Rect2(float(col * _fw), float(r_idx * _fh), float(_fw), float(_fh))
		sp.region_rect = rect
		gl.region_rect = rect

	var t_fr: int = posmod(int(floor(_time * 6.5)), 8)
	for tsp: Sprite2D in _throne_sprites:
		tsp.frame = t_fr

	if _blink_rect != null and _open_atlas != null and _blink_atlas != null:
		var cycle: float = fmod(_time, 3.6)
		_blink_rect.texture = _blink_atlas if (cycle > 3.35) else _open_atlas


func _export_contact_images(out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 1. Deterministic sprite + glow contact sheet (works in both headless & opengl3)
	var base_img: Image = GODDESS_TEX.get_image()
	var glow_img: Image = GODDESS_GLOW_TEX.get_image()
	base_img.convert(Image.FORMAT_RGBA8)
	glow_img.convert(Image.FORMAT_RGBA8)

	var contact: Image = Image.create(base_img.get_width(), base_img.get_height(), false, Image.FORMAT_RGBA8)
	contact.fill(Color("#120e24"))
	contact.blend_rect(base_img, Rect2i(Vector2i.ZERO, base_img.get_size()), Vector2i.ZERO)
	contact.blend_rect(glow_img, Rect2i(Vector2i.ZERO, glow_img.get_size()), Vector2i.ZERO)
	var contact_path: String = out_dir.path_join("goddess_contact.png")
	contact.save_png(contact_path)
	print("Saved ", contact_path)

	# 2. Deterministic 2x zoomed portrait inspection sheet
	var p_img: Image = PORTRAIT_TEX.get_image()
	p_img.convert(Image.FORMAT_RGBA8)
	var p_card: Image = Image.create(230, 169, false, Image.FORMAT_RGBA8)
	p_card.fill(Color("#161229"))
	p_card.blend_rect(p_img, Rect2i(0, 0, 103, 153), Vector2i(8, 8))
	p_card.blend_rect(p_img, Rect2i(103, 0, 103, 153), Vector2i(119, 8))
	p_card.resize(460, 338, Image.INTERPOLATE_NEAREST)
	var p_out: String = out_dir.path_join("goddess_portrait_preview.png")
	p_card.save_png(p_out)
	print("Saved ", p_out)


func _run_capture() -> void:
	await get_tree().process_frame
	if not _out_dir.is_empty():
		_export_contact_images(_out_dir)

	if DisplayServer.get_name() != "headless" and not _out_dir.is_empty():
		_advance_visuals(0.55)
		for _i: int in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var vp_img: Image = get_viewport().get_texture().get_image()
		var live_path: String = _out_dir.path_join("goddess_live_preview.png")
		vp_img.save_png(live_path)
		print("Captured ", live_path)

	print("GODDESS PREVIEW OK")
	get_tree().quit(0)
