extends Node2D
## Standalone scenic & shader preview for the Star Hall ("Der Sternensaal", docs/sternensaal_konzept.md).
## Builds the complete 560x820 floating moon-marble temple island in deep cosmos with:
##   - starhall_cosmos.gdshader (4 parallax star layers, Bayer nebulae, island aura, outer Void rifts)
##   - floor_base.png + floor_glow.png (Unlit)
##   - Two recessed starhall_mirror.gdshader reflection basins
##   - Animated Throne, 6 Crystal Pylons + 2 Arrival Pylons, 3 Relic Plinths, Balustrades, Return Seal
##   - 6 floating outer cosmos_island_0..2 fragments + drifting pixel-snapped star_mote sparks
##   - Automatic seated Goddess integration when assets/characters/goddess.png is present
##
## Usage:
##   Godot --rendering-driver opengl3 --path . tools/preview_starhall.tscn -- --dir=/abs/output_dir

const DIR: String = "res://assets/interior/starhall/"
const COSMOS_SHADER: Shader = preload("res://assets/shaders/starhall_cosmos.gdshader")
const MIRROR_SHADER: Shader = preload("res://assets/shaders/starhall_mirror.gdshader")

const FLOOR_BASE_TEX: Texture2D = preload("res://assets/interior/starhall/floor_base.png")
const FLOOR_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/floor_glow.png")
const THRONE_TEX: Texture2D = preload("res://assets/interior/starhall/throne.png")
const THRONE_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/throne_glow.png")
const PYLON_TEX: Texture2D = preload("res://assets/interior/starhall/pylon.png")
const PYLON_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/pylon_glow.png")
const BALUSTRADE_TEX: Texture2D = preload("res://assets/interior/starhall/balustrade.png")
const BALUSTRADE_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/balustrade_glow.png")
const RETURN_SEAL_TEX: Texture2D = preload("res://assets/interior/starhall/return_seal.png")
const RETURN_SEAL_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/return_seal_glow.png")
const RELIC_PLINTH_TEX: Texture2D = preload("res://assets/interior/starhall/relic_plinth.png")
const RELIC_PLINTH_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/relic_plinth_glow.png")
const ISLAND0_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_0.png")
const ISLAND0_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_0_glow.png")
const ISLAND1_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_1.png")
const ISLAND1_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_1_glow.png")
const ISLAND2_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_2.png")
const ISLAND2_GLOW_TEX: Texture2D = preload("res://assets/interior/starhall/cosmos_island_2_glow.png")
const STAR_MOTE_TEX: Texture2D = preload("res://assets/interior/starhall/star_mote.png")

const HALL_SIZE: Vector2 = Vector2(560.0, 820.0)
const COSMOS_POS: Vector2 = Vector2(-620.0, -230.0)
const COSMOS_SIZE: Vector2 = Vector2(1800.0, 1280.0)

var _out_dir: String = ""
var _time: float = 0.0
var _cam: Camera2D
var _cosmos_mat: ShaderMaterial
var _mirror_mats: Array[ShaderMaterial] = []
var _anims: Array[Dictionary] = []
var _islands: Array[Dictionary] = []
var _motes: Array[Dictionary] = []
var _goddess_sprite: Sprite2D = null
var _goddess_glow: Sprite2D = null
var _goddess_frames: int = 6
var _goddess_row: int = 0
var _goddess_col0: int = 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_out_dir = arg.substr(6)
		elif arg.begins_with("--capture="):
			_out_dir = arg.substr(10)

	_build_hall()
	if not _out_dir.is_empty() or DisplayServer.get_name() == "headless":
		_run_capture.call_deferred()


func _build_hall() -> void:
	# Constant clear silver-blue starlight ambient (no day/night darkening in the Star Hall)
	var modulate_node: CanvasModulate = CanvasModulate.new()
	modulate_node.color = Color(0.84, 0.86, 0.97, 1.0)
	add_child(modulate_node)

	# 1. Deep Cosmos Shader Backdrop
	var cosmos_rect: ColorRect = ColorRect.new()
	cosmos_rect.name = "StarHallCosmos"
	cosmos_rect.position = COSMOS_POS
	cosmos_rect.size = COSMOS_SIZE
	cosmos_rect.z_index = -30
	_cosmos_mat = ShaderMaterial.new()
	_cosmos_mat.shader = COSMOS_SHADER
	_cosmos_mat.set_shader_parameter("rect_size", COSMOS_SIZE)
	_cosmos_mat.set_shader_parameter("hall_origin", -COSMOS_POS)
	_cosmos_mat.set_shader_parameter("hall_size", HALL_SIZE)
	_cosmos_mat.set_shader_parameter("cam_offset", Vector2.ZERO)
	_cosmos_mat.set_shader_parameter("time", 0.0)
	cosmos_rect.material = _cosmos_mat
	add_child(cosmos_rect)

	# 2. Outer Floating Marble & Crystal Islands in Parallax Space
	var island_texs: Array[Texture2D] = [ISLAND0_TEX, ISLAND1_TEX, ISLAND2_TEX]
	var island_glows: Array[Texture2D] = [ISLAND0_GLOW_TEX, ISLAND1_GLOW_TEX, ISLAND2_GLOW_TEX]
	var island_specs: Array[Dictionary] = [
		{"v": 0, "pos": Vector2(44.0, 128.0), "amp": 4.0, "spd": 0.9, "ph": 0.2},
		{"v": 1, "pos": Vector2(512.0, 146.0), "amp": 3.0, "spd": 1.1, "ph": 1.7},
		{"v": 1, "pos": Vector2(58.0, 470.0), "amp": 4.0, "spd": 0.8, "ph": 2.9},
		{"v": 0, "pos": Vector2(506.0, 488.0), "amp": 3.5, "spd": 0.95, "ph": 4.1},
		{"v": 2, "pos": Vector2(88.0, 720.0), "amp": 3.0, "spd": 1.25, "ph": 0.9},
		{"v": 2, "pos": Vector2(476.0, 732.0), "amp": 3.0, "spd": 1.15, "ph": 3.5},
	]
	for spec: Dictionary in island_specs:
		var v_idx: int = int(spec["v"])
		var base_pos: Vector2 = spec["pos"] as Vector2
		var holder: Node2D = Node2D.new()
		holder.position = base_pos
		holder.z_index = -20
		add_child(holder)

		var ib: Sprite2D = Sprite2D.new()
		ib.texture = island_texs[v_idx]
		holder.add_child(ib)

		var ig: Sprite2D = Sprite2D.new()
		ig.texture = island_glows[v_idx]
		ig.material = Unlit.material()
		holder.add_child(ig)

		_islands.append({
			"node": holder,
			"base": base_pos,
			"amp": float(spec["amp"]),
			"spd": float(spec["spd"]),
			"ph": float(spec["ph"]),
		})

	# 3. Floating Moon-Marble Platform Base & Unlit Leyline Glow
	var floor_base: Sprite2D = Sprite2D.new()
	floor_base.name = "FloorBase"
	floor_base.texture = FLOOR_BASE_TEX
	floor_base.centered = false
	floor_base.position = Vector2.ZERO
	floor_base.z_index = -10
	add_child(floor_base)

	var floor_glow: Sprite2D = Sprite2D.new()
	floor_glow.name = "FloorGlow"
	floor_glow.texture = FLOOR_GLOW_TEX
	floor_glow.centered = false
	floor_glow.position = Vector2.ZERO
	floor_glow.z_index = -8
	floor_glow.material = Unlit.material()
	add_child(floor_glow)

	# 4. Two Recessed Reflection Basins on the Star Bridge (exact inner water rects)
	var basin_positions: Array[Vector2] = [Vector2(170.0, 399.0), Vector2(346.0, 399.0)]
	var basin_sz: Vector2 = Vector2(44.0, 162.0)
	for b_idx: int in basin_positions.size():
		var m_rect: ColorRect = ColorRect.new()
		m_rect.name = "MirrorBasin_%d" % b_idx
		m_rect.position = basin_positions[b_idx]
		m_rect.size = basin_sz
		m_rect.z_index = -9
		var m_mat: ShaderMaterial = ShaderMaterial.new()
		m_mat.shader = MIRROR_SHADER
		m_mat.set_shader_parameter("basin_size", basin_sz)
		m_mat.set_shader_parameter("cam_offset", Vector2.ZERO)
		m_mat.set_shader_parameter("time", 0.0)
		m_mat.set_shader_parameter("mirror_seed", float(b_idx) * 17.0)
		m_rect.material = m_mat
		add_child(m_rect)
		_mirror_mats.append(m_mat)

	# 5. Y-Sorted Sanctuary Props, Throne, Goddess, Pylons & Balustrades
	var props_root: Node2D = Node2D.new()
	props_root.name = "SortedHallProps"
	props_root.y_sort_enabled = true
	add_child(props_root)

	# Monumental Divine Throne at (280, 162), foot anchor (80, 148)
	_add_anim_prop(
		props_root,
		"DivineThrone",
		THRONE_TEX,
		THRONE_GLOW_TEX,
		Vector2(280.0, 162.0),
		Vector2(-80.0, -148.0),
		8,
		6.5,
		0.0
	)
	_add_star_light(Vector2(280.0, 140.0), Color(0.58, 0.96, 0.98), 180, 0.72, 0.72)
	_add_star_light(Vector2(280.0, 182.0), Color(1.00, 0.90, 0.66), 140, 0.65, 0.42)

	# Optional Seated Goddess on the Throne if @goddess-art's asset exists
	_try_add_goddess(props_root)

	# 3 Relic Plinths on the Northern Throne Dais
	var relic_spots: Array[Vector2] = [
		Vector2(174.0, 180.0),
		Vector2(386.0, 180.0),
		Vector2(204.0, 224.0),
	]
	for r_idx: int in relic_spots.size():
		_add_anim_prop(
			props_root,
			"RelicPlinth_%d" % r_idx,
			RELIC_PLINTH_TEX,
			RELIC_PLINTH_GLOW_TEX,
			relic_spots[r_idx],
			Vector2(-18.0, -44.0),
			8,
			6.0,
			float(r_idx) * 0.35
		)

	# 6 Crystal Candelabra Pylons (3 pairs along the Star Bridge)
	var pylon_spots: Array[Vector2] = [
		Vector2(204.0, 344.0),
		Vector2(356.0, 344.0),
		Vector2(228.0, 480.0),
		Vector2(332.0, 480.0),
		Vector2(204.0, 612.0),
		Vector2(356.0, 612.0),
	]
	for p_idx: int in pylon_spots.size():
		var p_pos: Vector2 = pylon_spots[p_idx]
		_add_anim_prop(
			props_root,
			"CrystalPylon_%d" % p_idx,
			PYLON_TEX,
			PYLON_GLOW_TEX,
			p_pos,
			Vector2(-24.0, -84.0),
			8,
			6.5,
			float(p_idx) * 0.22
		)
		_add_star_light(p_pos + Vector2(0.0, -28.0), Color(0.45, 0.95, 0.94), 96, 0.7, 0.45)

	# Openwork Moon-Marble Balustrades along Balcony North & South Rims
	var bal_spots: Array[Vector2] = [
		Vector2(174.0, 381.0),
		Vector2(386.0, 381.0),
		Vector2(174.0, 581.0),
		Vector2(386.0, 581.0),
	]
	for b_i: int in bal_spots.size():
		_add_static_prop(
			props_root,
			"Balustrade_%d" % b_i,
			BALUSTRADE_TEX,
			BALUSTRADE_GLOW_TEX,
			bal_spots[b_i],
			Vector2(-24.0, -32.0)
		)

	# Floating Return Seal above the Southern Arrival Circle at (280, 715)
	_add_anim_prop(
		props_root,
		"ReturnSeal",
		RETURN_SEAL_TEX,
		RETURN_SEAL_GLOW_TEX,
		Vector2(280.0, 715.0),
		Vector2(-32.0, -26.0),
		8,
		7.0,
		0.0
	)
	_add_star_light(Vector2(280.0, 712.0), Color(0.48, 0.96, 0.94), 132, 0.65, 0.62)

	# 6. Drifting Pixel-Snapped Star Motes across the Sanctuary
	var motes_root: Node2D = Node2D.new()
	motes_root.name = "StarMotes"
	motes_root.z_index = 15
	add_child(motes_root)
	for m_i: int in 26:
		var seed_f: float = float(m_i) * 1.6180339
		var mx: float = 155.0 + fmod(seed_f * 97.3, 250.0)
		var my: float = 85.0 + fmod(seed_f * 173.7, 665.0)
		var ms: Sprite2D = Sprite2D.new()
		ms.texture = STAR_MOTE_TEX
		ms.hframes = 4
		ms.frame = m_i % 4
		ms.material = Unlit.material()
		ms.position = Vector2(roundf(mx), roundf(my))
		motes_root.add_child(ms)
		_motes.append({
			"sprite": ms,
			"bx": mx,
			"by": my,
			"ph": seed_f * 3.1,
			"spd": 3.5 + fmod(seed_f * 5.0, 3.0),
		})

	# 7. Camera
	_cam = Camera2D.new()
	_cam.enabled = true
	_cam.position = Vector2(280.0, 430.0)
	_cam.zoom = Vector2(0.4, 0.4)
	add_child(_cam)


func _try_add_goddess(parent: Node2D) -> void:
	var g_path: String = "res://assets/characters/goddess.png"
	if not ResourceLoader.exists(g_path):
		return
	var g_tex: Texture2D = ResourceLoader.load(g_path) as Texture2D
	if g_tex == null:
		return

	var fw: int = 96
	var fh: int = 112
	var foot_x: float = 48.0
	var ground_row: float = 94.0

	var rig_path: String = "res://data/goddess_rig.json"
	if FileAccess.file_exists(rig_path):
		var raw: String = FileAccess.get_file_as_string(rig_path)
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			var rig: Dictionary = parsed as Dictionary
			if rig.has("frame") and rig["frame"] is Array:
				var fr_arr: Array = rig["frame"] as Array
				if fr_arr.size() >= 2:
					fw = int(fr_arr[0])
					fh = int(fr_arr[1])
			elif rig.has("frame_size") and rig["frame_size"] is Array:
				var fs: Array = rig["frame_size"] as Array
				if fs.size() >= 2:
					fw = int(fs[0])
					fh = int(fs[1])
			if rig.has("feet") and rig["feet"] is Array:
				var ft_arr: Array = rig["feet"] as Array
				if ft_arr.size() >= 2:
					foot_x = float(ft_arr[0])
					ground_row = float(ft_arr[1])
			elif rig.has("ground_row"):
				foot_x = float(fw) * 0.5
				ground_row = float(rig["ground_row"])
			if rig.has("default_row"):
				_goddess_row = int(rig["default_row"])
			if rig.has("clips") and rig["clips"] is Dictionary:
				var clips: Dictionary = rig["clips"] as Dictionary
				if clips.has("sit_idle") and clips["sit_idle"] is Dictionary:
					var sit_d: Dictionary = clips["sit_idle"] as Dictionary
					_goddess_row = int(sit_d.get("row", _goddess_row))
					_goddess_col0 = int(sit_d.get("start", sit_d.get("col", 0)))
					_goddess_frames = maxi(1, int(sit_d.get("count", sit_d.get("frames", 6))))

	var seat_pos: Vector2 = Vector2(280.0, 163.0)
	var off: Vector2 = Vector2(-foot_x, -ground_row)

	_goddess_sprite = Sprite2D.new()
	_goddess_sprite.name = "Goddess"
	_goddess_sprite.texture = g_tex
	_goddess_sprite.centered = false
	_goddess_sprite.offset = off
	_goddess_sprite.position = seat_pos
	_goddess_sprite.region_enabled = true
	_goddess_sprite.region_rect = Rect2(float(_goddess_col0 * fw), float(_goddess_row * fh), float(fw), float(fh))
	parent.add_child(_goddess_sprite)

	var gg_path: String = "res://assets/characters/goddess_glow.png"
	if ResourceLoader.exists(gg_path):
		var gg_tex: Texture2D = ResourceLoader.load(gg_path) as Texture2D
		if gg_tex != null:
			_goddess_glow = Sprite2D.new()
			_goddess_glow.name = "GoddessGlow"
			_goddess_glow.texture = gg_tex
			_goddess_glow.centered = false
			_goddess_glow.offset = off
			_goddess_glow.position = Vector2.ZERO
			_goddess_glow.material = Unlit.material()
			_goddess_glow.region_enabled = true
			_goddess_glow.region_rect = _goddess_sprite.region_rect
			_goddess_sprite.add_child(_goddess_glow)


func _add_static_prop(
	parent: Node2D,
	prop_name: String,
	base_tex: Texture2D,
	glow_tex: Texture2D,
	pos: Vector2,
	off: Vector2
) -> Sprite2D:
	var sp: Sprite2D = Sprite2D.new()
	sp.name = prop_name
	sp.texture = base_tex
	sp.centered = false
	sp.offset = off
	sp.position = pos
	parent.add_child(sp)

	if glow_tex != null:
		var gl: Sprite2D = Sprite2D.new()
		gl.name = prop_name + "Glow"
		gl.texture = glow_tex
		gl.centered = false
		gl.offset = off
		gl.material = Unlit.material()
		sp.add_child(gl)
	return sp


func _add_anim_prop(
	parent: Node2D,
	prop_name: String,
	base_tex: Texture2D,
	glow_tex: Texture2D,
	pos: Vector2,
	off: Vector2,
	frames: int,
	fps: float,
	phase: float
) -> Sprite2D:
	var sp: Sprite2D = Sprite2D.new()
	sp.name = prop_name
	sp.texture = base_tex
	sp.centered = false
	sp.offset = off
	sp.hframes = frames
	sp.position = pos
	parent.add_child(sp)

	var gl: Sprite2D = null
	if glow_tex != null:
		gl = Sprite2D.new()
		gl.name = prop_name + "Glow"
		gl.texture = glow_tex
		gl.centered = false
		gl.offset = off
		gl.hframes = frames
		gl.material = Unlit.material()
		sp.add_child(gl)

	_anims.append({
		"sprite": sp,
		"glow": gl,
		"frames": frames,
		"fps": fps,
		"phase": phase,
	})
	return sp


func _add_star_light(pos: Vector2, col: Color, width: int, squash: float, energy: float) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.position = pos
	light.color = col
	light.energy = energy
	LightTexture.apply(light, width, squash, int(absf(pos.x + pos.y)) % 3)
	add_child(light)
	return light


func _process(delta: float) -> void:
	_advance_visuals(_time + delta)


func _advance_visuals(new_time: float) -> void:
	_time = new_time
	var cam_shift: Vector2 = (_cam.position - Vector2(280.0, 430.0)) if _cam != null else Vector2.ZERO

	if _cosmos_mat != null:
		_cosmos_mat.set_shader_parameter("time", _time)
		_cosmos_mat.set_shader_parameter("cam_offset", cam_shift)

	for m_mat: ShaderMaterial in _mirror_mats:
		m_mat.set_shader_parameter("time", _time)
		m_mat.set_shader_parameter("cam_offset", cam_shift)

	for entry: Dictionary in _anims:
		var sp: Sprite2D = entry["sprite"] as Sprite2D
		var gl: Sprite2D = entry["glow"] as Sprite2D
		var n_fr: int = int(entry["frames"])
		var fps: float = float(entry["fps"])
		var ph: float = float(entry["phase"])
		var fr: int = posmod(int(floor((_time + ph) * fps)), n_fr)
		sp.frame = fr
		if gl != null:
			gl.frame = fr

	for isl: Dictionary in _islands:
		var node: Node2D = isl["node"] as Node2D
		var b_pos: Vector2 = isl["base"] as Vector2
		var amp: float = float(isl["amp"])
		var spd: float = float(isl["spd"])
		var ph_i: float = float(isl["ph"])
		node.position = Vector2(b_pos.x, b_pos.y + roundf(sin(_time * spd + ph_i) * amp))

	for mote: Dictionary in _motes:
		var ms: Sprite2D = mote["sprite"] as Sprite2D
		var bx: float = float(mote["bx"])
		var by: float = float(mote["by"])
		var ph_m: float = float(mote["ph"])
		var spd_m: float = float(mote["spd"])
		var dy: float = fmod(_time * spd_m + ph_m * 10.0, 36.0)
		var dx: float = sin(_time * 1.1 + ph_m) * 4.0
		ms.position = Vector2(roundf(bx + dx), roundf(by - dy))
		ms.frame = posmod(int(floor(_time * 4.5 + ph_m * 2.0)), 4)

	if _goddess_sprite != null and _goddess_sprite.texture != null:
		var g_rect: Rect2 = _goddess_sprite.region_rect
		var g_cols_max: int = maxi(1, int(_goddess_sprite.texture.get_width() / maxf(1.0, g_rect.size.x)))
		var n_gf: int = mini(_goddess_frames, g_cols_max - _goddess_col0)
		if n_gf > 0:
			var g_fr: int = _goddess_col0 + posmod(int(floor(_time * 6.0)), n_gf)
			var next_rect: Rect2 = Rect2(float(g_fr) * g_rect.size.x, float(_goddess_row) * g_rect.size.y, g_rect.size.x, g_rect.size.y)
			_goddess_sprite.region_rect = next_rect
			if _goddess_glow != null:
				_goddess_glow.region_rect = next_rect


func _capture_view(shot_name: String, cam_pos: Vector2, cam_zoom: Vector2, sim_time: float) -> void:
	_cam.position = cam_pos
	_cam.zoom = cam_zoom
	_advance_visuals(sim_time)
	for _i: int in 4:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless" and not _out_dir.is_empty():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_out_dir)
		var out_file: String = _out_dir.path_join(shot_name + ".png")
		get_viewport().get_texture().get_image().save_png(out_file)
		print("Captured ", out_file)


func _run_capture() -> void:
	await get_tree().process_frame
	await _capture_view("starhall_overview", Vector2(280.0, 430.0), Vector2(0.4, 0.4), 1.2)
	await _capture_view("starhall_throne", Vector2(280.0, 146.0), Vector2(1.0, 1.0), 1.8)
	await _capture_view("starhall_bridge", Vector2(280.0, 480.0), Vector2(1.0, 1.0), 2.4)
	await _capture_view("starhall_arrival", Vector2(280.0, 685.0), Vector2(1.0, 1.0), 3.0)
	print("STARHALL PREVIEW OK")
	get_tree().quit(0)
