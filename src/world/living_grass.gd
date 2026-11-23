class_name LivingGrass
extends Node2D
## LivingGrass v3 — Next-gen interactive pixel-art living meadow system:
## - 5-row subdivided parabolic ArrayMesh -> true organic arching bend & lay-down (zero rigid shear)
## - Y-sorted 6 px horizontal MultiMesh bands so blades wrap genuinely in front of Ellie's lower boots
## - 24 handcrafted botanical tuft/flower/fern/moss sprites x horizontal UV mirror (= 48 silhouettes)
## - Organic domain-warped macro-cluster / Horst distribution (anti-grid!) with woven floral carpets
## - Camera-centered toroidal 128x128 (4x4 px = 512x512 px) persistent deformation ring-buffer (infinite Open World!)
##     R/G: radial outward parting + stride sweep
##     B:   lingering 2-zone crush/flatten trail with alternating L/R boot cadence
##     A:   live damped spring wobble from footsteps, sword swings, and shadow steps
## - Generic actor tracking (players, enemies, wildlife, corvids/raven, NPCs, "grass_deformer") + character contact AO
## - Active unlit night-dew & blossom glow pass (living_grass_glow.png), auto-disabled by day (0 daytime drawcalls)
## - Context-aware pixel blade & matching floral petal kick-up motes + soft positional rustle audio.

const CELL_SIZE: Vector2 = Vector2(16.0, 20.0)
const MESH_ROWS: int = 4 ## 4 vertical segments = 5 vertex rows for true parabolic arching
const BAND_HEIGHT: float = 6.0
const FIELD_RES: int = 128 ## 128 x 4 px = 512 px toroidal sliding window
const CELL_PX: float = 4.0
const FIELD_SIZE: float = float(FIELD_RES) * CELL_PX ## 512.0 px
const RECENTER_STEP_CELLS: int = 4 ## Shift toroidal window once camera moves >= 16 px from center
const UPLOAD_INTERVAL: float = 0.033 ## ~30 Hz GPU upload while actively deforming/recovering

const LIT_SHADER: Shader = preload("res://assets/shaders/living_grass.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/living_grass_glow.gdshader")
const TRAIL_SHADER: Shader = preload("res://assets/shaders/living_grass_trail.gdshader")
const ATLAS_TEX: Texture2D = preload("res://assets/tiles/living_grass.png")
const GLOW_TEX: Texture2D = preload("res://assets/tiles/living_grass_glow.png")

const MAX_MOTES: int = 34
const BLADE_COLORS: Array[Color] = [
	Color("60a360"), Color("87c46f"), Color("336b4e"), Color("b3e08f"),
]
const PETAL_WHITE: Array[Color] = [
	Color("faf5e8"), Color("dfd9cc"), Color("fff0a8"),
]
const PETAL_BLUE: Array[Color] = [
	Color("d0ebff"), Color("8db8e6"), Color("faf5e8"),
]
const PETAL_LILAC: Array[Color] = [
	Color("e4d4fa"), Color("b094dc"), Color("faf5e8"),
]
const PETAL_ALL: Array[Color] = [
	Color("faf5e8"), Color("d0ebff"), Color("e4d4fa"), Color("fff0a8"),
]
const ACTOR_GROUPS: Array[String] = [
	"grass_deformer", "predators", "wildlife", "woodland_mammals", "npcs",
]

## Per-cell deformation record stored by absolute world cell (only kept while non-neutral).
class DeformCell:
	var dir: Vector2 = Vector2.ZERO ## parted / swept direction (-1..+1)
	var crush: float = 0.0 ## 0 = upright, 1 = flattened into trail
	var hold: float = 0.0 ## seconds before elastic recovery begins (keeps footprints crisp)
	var recover_rate: float = 0.16 ## crush units/sec recovered after hold
	var wobble_amp: float = 0.0 ## impact flutter amplitude
	var wobble_t: float = 0.0 ## impact spring clock

## Lightweight pixel mote drawn in `MoteLayer._draw()` (zero node churn).
class GrassMote:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 2.0
	var z_vel: float = 18.0
	var age: float = 0.0
	var life: float = 0.7
	var color: Color = Color("87c46f")
	var size_px: Vector2 = Vector2(2.0, 1.0)
	var flutter: bool = false
	var phase: float = 0.0


class MoteLayer:
	extends Node2D
	var motes: Array[GrassMote] = []

	func _draw() -> void:
		for m: GrassMote in motes:
			var a: float = clampf(1.0 - maxf(0.0, (m.age / maxf(m.life, 0.01) - 0.55) / 0.45), 0.0, 1.0)
			if a <= 0.02:
				continue
			var c: Color = m.color
			c.a = a
			var drift_x: float = sin(m.age * 9.0 + m.phase) * 1.4 if m.flutter else 0.0
			var p: Vector2 = Vector2(roundf(m.pos.x + drift_x), roundf(m.pos.y - m.z_h))
			draw_rect(Rect2(p, m.size_px), c)


static var _shared_mesh: ArrayMesh

var field_origin: Vector2 = Vector2(-256.0, -256.0)
var tuft_count: int = 0
var glow_tuft_count: int = 0
var follow_camera: bool = true ## Slides the 512x512 toroidal deform window with the active camera

var _bounds: Rect2 = Rect2()
var _surfaces: GroundSurfaces = null
var _custom_meadow_rect: Rect2 = Rect2()
var extra_habitat_providers: Array[Node] = []
var _field_cell_origin: Vector2i = Vector2i(-64, -64)
var _field_img: Image
var _field_tex: ImageTexture
var _grass_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _trail_mat: ShaderMaterial
var _trail_rect: ColorRect
var _mote_layer: MoteLayer
var _bands_root: Node2D
var _glow_root: Node2D
var _grass_visible: bool = true

var _active: Dictionary = {} ## Vector2i (world cell) -> DeformCell
var _remove_buf: Array[Vector2i] = []
var _dirty: bool = false
var _upload_timer: float = 0.0
var _floral_cells: Dictionary = {} ## Vector2i (8x8 px cell) -> int (1=white, 2=blue, 3=lilac)
var _grass_cells: Dictionary = {} ## Vector2i (8x8 px cell) -> true (actual tuft presence: gates trails/rustle/motes!)

## Actor tracking (peer-local visual physics: footsteps, L/R stride cadence, shadow steps, sword swings, wildlife, raven)
var _prev_pos: Dictionary = {} ## instance_id -> Vector2
var _stride_dist: Dictionary = {} ## instance_id -> float (accumulated px for L/R boot cadence)
var _stride_foot: Dictionary = {} ## instance_id -> float (+1.0 / -1.0 alternating side)
var _prev_step_t: Dictionary = {} ## instance_id -> float
var _prev_swing: Dictionary = {} ## instance_id -> bool
var _actor_slots: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _prune_timer: float = 0.0
var _mote_wait: float = 0.0
var _rustle_wait: float = 0.0
var _rustle: AudioStreamPlayer2D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func _get_tuft_mesh() -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh
	# Build a canonical 2D 5-row subdivided vertical strip:
	# y goes from +CELL_SIZE.y*0.5 (roots, UV.y = 0.0) to -CELL_SIZE.y*0.5 (tips, UV.y = 1.0).
	var hw: float = CELL_SIZE.x * 0.5
	var hh: float = CELL_SIZE.y * 0.5
	var verts: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for r: int in MESH_ROWS + 1:
		var t: float = float(r) / float(MESH_ROWS)
		var y: float = lerpf(hh, -hh, t)
		verts.append(Vector2(-hw, y))
		uvs.append(Vector2(0.0, t))
		verts.append(Vector2(hw, y))
		uvs.append(Vector2(1.0, t))
	for r: int in MESH_ROWS:
		var i0: int = r * 2
		var i1: int = i0 + 1
		var i2: int = i0 + 2
		var i3: int = i0 + 3
		indices.append(i0)
		indices.append(i1)
		indices.append(i3)
		indices.append(i0)
		indices.append(i3)
		indices.append(i2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_shared_mesh = ArrayMesh.new()
	_shared_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _shared_mesh


func _ready() -> void:
	y_sort_enabled = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("living_grass")
	_rustle = AudioStreamPlayer2D.new()
	_rustle.stream = preload("res://assets/audio/hut/rustle.wav")
	_rustle.max_distance = 140.0
	_rustle.volume_db = -29.0
	add_child(_rustle)


func set_meadow_rect(rect: Rect2) -> void:
	_custom_meadow_rect = rect


func set_water_habitat_provider(provider: Node) -> void:
	extra_habitat_providers.clear()
	if provider != null:
		extra_habitat_providers.append(provider)


func add_habitat_provider(provider: Node) -> void:
	if provider != null and not extra_habitat_providers.has(provider):
		extra_habitat_providers.append(provider)


func _query_habitat(world_pos: Vector2) -> Dictionary:
	var dens: float = 1.0
	var hscale: float = 1.0
	var style: String = "meadow"
	if _surfaces != null:
		var hab: Dictionary = _surfaces.grass_habitat_at(world_pos)
		dens = float(hab.get("density", 1.0))
		hscale = float(hab.get("height_scale", 1.0))
		style = String(hab.get("style", "meadow"))
		if dens <= 0.02:
			return {"density": 0.0, "height_scale": hscale, "style": "none"}

	for patch: Node in Terrain.patches:
		if patch.has_method("has_water_deck_at") and bool(patch.call("has_water_deck_at", world_pos)):
			return {"density": 0.0, "height_scale": 0.6, "style": "none"}

	var providers: Array[Node] = extra_habitat_providers.duplicate()
	for patch: Node in Terrain.patches:
		if patch.has_method("grass_habitat_at") and not providers.has(patch):
			providers.append(patch)

	for prov: Node in providers:
		if not is_instance_valid(prov) or not prov.has_method("grass_habitat_at"):
			continue
		var phab: Dictionary = prov.call("grass_habitat_at", world_pos) as Dictionary
		var pdens: float = float(phab.get("density", 1.0))
		var pstyle: String = String(phab.get("style", "meadow"))
		var phscale: float = float(phab.get("height_scale", 1.0))
		if pdens <= 0.02 or pstyle == "none":
			return {"density": 0.0, "height_scale": phscale, "style": "none"}
		if prov.has_method("surface_at"):
			var psurf: String = String(prov.call("surface_at", world_pos))
			if psurf in ["wet_sand", "tide_shallow", "puddle", "shallow_water", "deep_water"]:
				return {"density": 0.0, "height_scale": 0.6, "style": "none"}
		if pstyle != "meadow":
			dens = minf(dens, pdens)
			hscale = phscale
			style = pstyle

	return {"density": dens, "height_scale": hscale, "style": style}


## Populates an organic, domain-warped living grass ecosystem across `world_rect` (in world px).
## Set `clip_border = true` for clean studio/diorama edges; `false` for seamless tiled open-world chunks.
## Pass `surface_provider` (`GroundSurfaces`) so grass naturally frays along paths, tucks into antique stone
## seams, avoids standing puddles, and shifts into shaded woodland ferns on forest soil!
func setup_rect(world_rect: Rect2, seed_val: int = 2026, clip_border: bool = true, surface_provider: GroundSurfaces = null) -> void:
	_bounds = world_rect
	_surfaces = surface_provider
	var center: Vector2 = world_rect.get_center()
	_field_cell_origin = Vector2i(
		floori(center.x / CELL_PX) - FIELD_RES / 2,
		floori(center.y / CELL_PX) - FIELD_RES / 2
	)
	field_origin = Vector2(_field_cell_origin) * CELL_PX
	_rng.seed = seed_val
	_init_field()
	_build_tufts(world_rect, seed_val, clip_border)


func _init_field() -> void:
	_active.clear()
	_field_img = Image.create(FIELD_RES, FIELD_RES, false, Image.FORMAT_RGBA8)
	_field_img.fill(Color(0.5, 0.5, 0.0, 0.5))
	_field_tex = ImageTexture.create_from_image(_field_img)

	_grass_mat = ShaderMaterial.new()
	_grass_mat.shader = LIT_SHADER
	_grass_mat.set_shader_parameter("field_origin", field_origin)
	_grass_mat.set_shader_parameter("field_size", FIELD_SIZE)
	_grass_mat.set_shader_parameter("deform_tex", _field_tex)
	_grass_mat.set_shader_parameter("actors", _actor_slots)

	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GLOW_SHADER
	_glow_mat.set_shader_parameter("field_origin", field_origin)
	_glow_mat.set_shader_parameter("field_size", FIELD_SIZE)
	_glow_mat.set_shader_parameter("deform_tex", _field_tex)

	_trail_mat = ShaderMaterial.new()
	_trail_mat.shader = TRAIL_SHADER
	_trail_mat.set_shader_parameter("field_origin", field_origin)
	_trail_mat.set_shader_parameter("field_size", FIELD_SIZE)
	_trail_mat.set_shader_parameter("deform_tex", _field_tex)
	_trail_mat.set_shader_parameter("debug_overlay", 0.0)

	if _trail_rect != null:
		_trail_rect.queue_free()
	_trail_rect = ColorRect.new()
	_trail_rect.name = "GrassTrailUnderlay"
	_trail_rect.z_as_relative = false
	_trail_rect.z_index = -10
	_trail_rect.position = _bounds.position
	_trail_rect.size = _bounds.size
	_trail_rect.color = Color.WHITE
	_trail_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trail_rect.material = _trail_mat
	add_child(_trail_rect)

	if _mote_layer != null:
		_mote_layer.queue_free()
	_mote_layer = MoteLayer.new()
	_mote_layer.name = "GrassMotes"
	_mote_layer.z_as_relative = false
	_mote_layer.z_index = 2
	add_child(_mote_layer)


func _build_tufts(world_rect: Rect2, seed_val: int, clip_border: bool = true) -> void:
	if _bands_root != null:
		_bands_root.queue_free()
	_bands_root = Node2D.new()
	_bands_root.name = "Bands"
	_bands_root.y_sort_enabled = true
	add_child(_bands_root)

	if _glow_root != null:
		_glow_root.queue_free()
	_glow_root = Node2D.new()
	_glow_root.name = "NightGlowBands"
	_glow_root.y_sort_enabled = true
	_glow_root.visible = false ## Zero daytime drawcall cost; auto-enabled when TimeManager.night_amount() > 0.02
	add_child(_glow_root)

	var tuft_mesh: ArrayMesh = _get_tuft_mesh()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val + 77

	# Domain-warped organic habitat noise layers -> flowing botanical bands & natural clearings (anti-grid!)
	var warp_noise: FastNoiseLite = FastNoiseLite.new()
	warp_noise.seed = seed_val + 907
	warp_noise.frequency = 0.012
	warp_noise.fractal_octaves = 2

	var density_noise: FastNoiseLite = FastNoiseLite.new()
	density_noise.seed = seed_val + 11
	density_noise.frequency = 0.015
	density_noise.fractal_octaves = 2

	var floral_noise: FastNoiseLite = FastNoiseLite.new()
	floral_noise.seed = seed_val + 313
	floral_noise.frequency = 0.019
	floral_noise.fractal_octaves = 2

	var tall_noise: FastNoiseLite = FastNoiseLite.new()
	tall_noise.seed = seed_val + 577
	tall_noise.frequency = 0.018
	tall_noise.fractal_octaves = 2

	var bands: Dictionary = {} ## int band_idx -> Array[Dictionary]
	var glow_bands: Dictionary = {} ## int band_idx -> Array[Dictionary]
	_floral_cells.clear()
	_grass_cells.clear()
	tuft_count = 0
	glow_tuft_count = 0

	var pad_left: float = 8.0 if clip_border else 2.0
	var pad_right: float = 8.0 if clip_border else 2.0
	var pad_top: float = 12.0 if clip_border else 2.0
	var pad_bottom: float = 2.0
	var spawn_rect: Rect2 = Rect2(
		world_rect.position + Vector2(pad_left, pad_top),
		world_rect.size - Vector2(pad_left + pad_right, pad_top + pad_bottom)
	)
	# Keep Square 0's iconic NW blossom zone scoped to [-192, +192] even when extended leftward across Squares -1/-2/-3
	var meadow_rect: Rect2 = _custom_meadow_rect
	if meadow_rect.size == Vector2.ZERO:
		if world_rect.position.x < -192.0 and world_rect.end.x >= 192.0:
			meadow_rect = Rect2(-192.0, world_rect.position.y, 384.0, world_rect.size.y)
		else:
			meadow_rect = Rect2(world_rect.position, Vector2(minf(world_rect.size.x, 384.0), world_rect.size.y))

	# 2-tier organic Horst / cluster growth:
	# Slightly wider anchor spacing (10.2 x 7.6 px) with heavy organic jitter + dense nestled companion tufts
	# breaks any uniform grid cadence while creating lush interwoven carpets & serene moss breathing clearings.
	var step_x: float = 10.2
	var step_y: float = 7.6
	var y: float = spawn_rect.position.y
	while y <= spawn_rect.end.y:
		var row_shift: float = step_x * 0.5 if int(floorf(y / step_y)) % 2 == 1 else 0.0
		var x: float = spawn_rect.position.x + row_shift
		while x <= spawn_rect.end.x:
			var base_pos: Vector2 = Vector2(
				x + rng.randf_range(-4.5, 4.5),
				y + rng.randf_range(-3.3, 3.3)
			).round()
			if not spawn_rect.has_point(base_pos):
				x += step_x
				continue

			var hab: Dictionary = _query_habitat(base_pos)
			var hab_dens: float = float(hab.get("density", 1.0))
			var hab_hscale: float = float(hab.get("height_scale", 1.0))
			var hab_style: String = String(hab.get("style", "meadow"))
			if hab_dens <= 0.02:
				x += step_x
				continue

			# Domain warp coordinates so habitat pockets curve like wild nature, never straight stripes
			var wp: Vector2 = base_pos + Vector2(
				warp_noise.get_noise_2d(base_pos.x, base_pos.y) * 26.0,
				warp_noise.get_noise_2d(base_pos.x + 173.0, base_pos.y - 91.0) * 26.0
			)
			var d_n: float = density_noise.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			# Natural clearings (calm velvet moss glimpses) vs lush dense meadow clusters
			var keep_prob: float = lerpf(0.32, 0.98, smoothstep(0.26, 0.68, d_n)) * hab_dens
			if hab_style == "stone_seam" or hab_style == "path_edge":
				keep_prob = maxf(keep_prob, hab_dens * 0.78)
			if rng.randf() > keep_prob:
				x += step_x
				continue

			var f_n: float = floral_noise.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			var t_n: float = tall_noise.get_noise_2d(wp.x, wp.y) * 0.5 + 0.5
			var anchor_kind: int = _choose_variant(base_pos, wp, meadow_rect, d_n, f_n, t_n, hab_style, rng)

			# Dense clusters (Horste): rich spots & floral carpets spawn 1-2 tightly interwoven companion tufts!
			var companions: int = 0
			if hab_style == "meadow":
				if d_n > 0.56 and rng.randf() < 0.72:
					companions = 2 if (d_n > 0.72 and rng.randf() < 0.45) else 1
				elif anchor_kind >= 16 and anchor_kind <= 20 and rng.randf() < 0.78:
					companions = 1
			elif (hab_style == "forest" or hab_style == "moss_edge") and d_n > 0.54 and rng.randf() < 0.50:
				companions = 1
			elif (hab_style == "stone_seam" or hab_style == "path_edge") and rng.randf() < 0.45:
				companions = 1
			elif hab_style == "bank_reed" and rng.randf() < 0.55:
				companions = 1
			elif hab_style == "dune_oat" and rng.randf() < 0.45:
				companions = 1

			for c_idx: int in companions + 1:
				var pos: Vector2 = base_pos
				var kind: int = anchor_kind
				var local_hscale: float = hab_hscale
				var local_style: String = hab_style
				if c_idx > 0:
					var ang: float = rng.randf() * TAU
					var dist: float = rng.randf_range(2.8, 5.6)
					pos = (base_pos + Vector2(cos(ang) * dist, sin(ang) * dist * 0.75)).round()
					if not spawn_rect.has_point(pos):
						continue
					var chab: Dictionary = _query_habitat(pos)
					if float(chab.get("density", 1.0)) <= 0.12:
						continue
					local_hscale = float(chab.get("height_scale", hab_hscale))
					local_style = String(chab.get("style", hab_style))
					# Companion in a Horst harmonizes with its anchor
					if local_style == "bank_reed":
						kind = rng.randi_range(8, 13) if rng.randf() < 0.72 else (23 if rng.randf() < 0.25 else rng.randi_range(0, 7))
					elif local_style == "dune_oat":
						kind = 23 if rng.randf() < 0.42 else rng.randi_range(8, 13)
					elif anchor_kind >= 16 and anchor_kind <= 20:
						kind = anchor_kind if rng.randf() < 0.55 else (17 if anchor_kind <= 18 else 19)
					elif anchor_kind >= 8 and anchor_kind <= 13:
						kind = rng.randi_range(0, 7) if rng.randf() < 0.68 else anchor_kind
					elif anchor_kind == 21 or anchor_kind == 22:
						kind = 14 if rng.randf() < 0.55 else 5
					elif local_style == "stone_seam":
						kind = 14 if rng.randf() < 0.45 else (15 if rng.randf() < 0.5 else 7)
					else:
						kind = rng.randi_range(0, 7)

				# Near northern border of bounded patch, keep shorter silhouettes so tips never poke outside the frame
				if clip_border and pos.y < world_rect.position.y + 19.0:
					if (kind >= 8 and kind <= 13) or kind >= 21:
						kind = rng.randi_range(0, 7)

				var flipped: bool = rng.randf() < 0.5
				var band_idx: int = floori(pos.y / BAND_HEIGHT)
				var tint_v: float = rng.randf_range(0.91, 1.07)
				var warm_bias: float = rng.randf_range(-0.03, 0.035)
				var tint_c: Color = Color(clampf(tint_v + warm_bias, 0.85, 1.10), tint_v, clampf(tint_v - warm_bias * 0.6, 0.85, 1.10), 1.0)
				if local_style == "forest" or local_style == "moss_edge":
					# Deep cool shaded woodland tint so forest ferns & sedges blend harmonically into dark humus!
					tint_c = Color(tint_c.r * 0.84, tint_c.g * 0.91, tint_c.b * 0.96, 1.0)
				elif local_style == "bank_reed":
					# Lush moist riparian reed & sedge green
					tint_c = Color(tint_c.r * 0.86, tint_c.g * 0.98, tint_c.b * 0.94, 1.0)
				elif local_style == "dune_oat":
					# Sun-bleached coastal Strandhafer / marram grass (alpha=0.50 encodes dune_k=1.0 for shader!)
					tint_c = Color(tint_c.r * 1.02, tint_c.g * 0.99, tint_c.b * 0.94, 0.50)
				elif local_style == "coastal_edge":
					# Transitional sea-sage coastal turf between dune ridge and inland meadow (dune_k=0.64)
					tint_c = Color(tint_c.r * 0.98, tint_c.g * 0.99, tint_c.b * 0.96, 0.68)
				var edge_flex: float = 0.72 if (clip_border and (pos.x < spawn_rect.position.x + 5.0 or pos.x > spawn_rect.end.x - 5.0)) else 1.0
				var entry: Dictionary = {
					"pos": pos,
					"kind": kind + (24 if flipped else 0),
					"phase": rng.randf(),
					"flex": rng.randf_range(0.70, 1.38) * edge_flex,
					"hscale": clampf(rng.randf_range(0.84, 1.14) * local_hscale, 0.55, 1.16),
					"tint": tint_c,
				}
				var arr: Array = bands.get_or_add(band_idx, []) as Array
				arr.append(entry)
				tuft_count += 1

				var gc: Vector2i = Vector2i((pos / 8.0).floor())
				_grass_cells[gc] = true

				# Record floral micro-habitat cells so walking/sprinting kicks up matching petals!
				if kind >= 16 and kind <= 20:
					_floral_cells[gc] = 1 if kind <= 17 else (2 if kind == 19 else 3)

				# Selective unlit night-glow pass: all blossoms + seed plumes + sparse poetic dew-tipped blades
				var has_glow: bool = (kind >= 16 and kind <= 20) or kind == 23 or (kind in [0, 2, 4, 6, 8, 9, 10, 12, 13] and rng.randf() < 0.34)
				if has_glow:
					var garr: Array = glow_bands.get_or_add(band_idx, []) as Array
					garr.append(entry)
					glow_tuft_count += 1
			x += step_x
		y += step_y

	_populate_bands(_bands_root, bands, tuft_mesh, ATLAS_TEX, _grass_mat)
	_populate_bands(_glow_root, glow_bands, tuft_mesh, GLOW_TEX, _glow_mat)


func _populate_bands(parent: Node2D, bands: Dictionary, mesh: ArrayMesh, tex: Texture2D, mat: ShaderMaterial) -> void:
	var keys: Array = bands.keys()
	keys.sort()
	for bkey_v: Variant in keys:
		var bkey: int = int(bkey_v)
		var items: Array = bands[bkey] as Array
		if items.is_empty():
			continue
		var band_node: Node2D = Node2D.new()
		band_node.position = Vector2(0.0, (float(bkey) + 1.0) * BAND_HEIGHT)
		parent.add_child(band_node)

		var mm_node: MultiMeshInstance2D = MultiMeshInstance2D.new()
		mm_node.texture = tex
		mm_node.material = mat
		mm_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mm_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = items.size()

		for i: int in items.size():
			var it: Dictionary = items[i] as Dictionary
			var p: Vector2 = it["pos"] as Vector2
			var local_pos: Vector2 = Vector2(p.x, p.y - band_node.position.y - 8.5)
			mm.set_instance_transform_2d(i, Transform2D(0.0, local_pos))
			mm.set_instance_color(i, it["tint"] as Color)
			mm.set_instance_custom_data(i, Color(
				float(int(it["kind"])) / 48.0,
				float(it["phase"]),
				float(it["flex"]),
				float(it["hscale"]),
			))
		mm_node.multimesh = mm
		band_node.add_child(mm_node)


func _choose_variant(pos: Vector2, warped_pos: Vector2, meadow_rect: Rect2, d_n: float, f_n: float, t_n: float, hab_style: String, rng: RandomNumberGenerator) -> int:
	# Habitat-specific botanical palettes:
	if hab_style == "stone_seam":
		var rs: float = rng.randf()
		if rs < 0.36:
			return 14 ## plush low moss pillow hugging stone edge
		if rs < 0.68:
			return 15 ## delicate low woodland clover
		if rs < 0.88:
			return 7 ## compact 5px velvet turf blades
		return 3 ## compact 6px emerald crown tuft

	if hab_style == "path_edge":
		var rp: float = rng.randf()
		if rp < 0.22:
			return 15 if rng.randf() < 0.6 else 14
		if rp < 0.34 and f_n > 0.58:
			return 17 if rng.randf() < 0.6 else 19
		if rp < 0.44 and t_n > 0.55:
			return 23 ## occasional nodding roadside seed plume
		return rng.randi_range(0, 7)

	if hab_style == "forest" or hab_style == "moss_edge":
		var rf: float = rng.randf()
		if rf < 0.34:
			return 21 if rng.randf() < 0.58 else 22 ## shaded woodland ferns!
		if rf < 0.58:
			return 14 if rng.randf() < 0.55 else 15 ## lush moss pillows & clover
		if rf < 0.80:
			return 12 if rng.randf() < 0.52 else 5 ## deep cool emerald forest sedges
		return 3 if rng.randf() < 0.5 else 7

	if hab_style == "bank_reed":
		var rr: float = rng.randf()
		if rr < 0.62:
			return rng.randi_range(8, 13) ## tall sweeping riparian reeds & sedges
		if rr < 0.78:
			return 23 ## tall reed seed plume
		if rr < 0.90:
			return 5 if rng.randf() < 0.5 else 3
		return 14 ## mossy bank cushion

	if hab_style == "dune_oat" or hab_style == "coastal_edge":
		var rd: float = rng.randf()
		if hab_style == "dune_oat" and rd < 0.28:
			return 23 ## coastal marram / Strandhafer seed plume
		if rd < 0.82:
			return rng.randi_range(8, 13) ## tall wind-swept coastal dune grass wisps
		return [0, 2, 4, 6][rng.randi_range(0, 3)]

	# Meadow Square (Square 1) & open grass margins around paths in Square 2:
	var in_meadow: bool = meadow_rect.grow(16.0).has_point(pos)
	var nx: float = (warped_pos.x - meadow_rect.position.x) / maxf(meadow_rect.size.x, 1.0)
	var ny: float = (warped_pos.y - meadow_rect.position.y) / maxf(meadow_rect.size.y, 1.0)

	# North-West sunlit floral ribbon on Square 1 (+ subtle smaller wildflower pockets in Square 2 grass!)
	var nw_floral: float = clampf((1.0 - nx * 1.38) * (1.0 - ny * 1.28), 0.0, 1.0) if in_meadow else 0.0
	if nw_floral > 0.14 or f_n > 0.69:
		var flower_chance: float = clampf(nw_floral * 0.68 + maxf(0.0, f_n - 0.66) * 0.95, 0.0, 0.78)
		if rng.randf() < flower_chance:
			if nw_floral > 0.36 and rng.randf() < 0.64:
				return 16 if rng.randf() < 0.55 else 17
			if rng.randf() < 0.56:
				return 19
			return 18 if rng.randf() < 0.55 else 20

	# South-East shaded woodland nook on Square 1
	var se_shade: float = clampf((nx - 0.50) * 2.1 * (ny - 0.44) * 2.1, 0.0, 1.0) if in_meadow else 0.0
	if se_shade > 0.15:
		var r_se: float = rng.randf()
		if r_se < 0.26 * se_shade:
			return 21 if rng.randf() < 0.55 else 22
		if r_se < 0.46 * se_shade:
			return 14 if rng.randf() < 0.5 else 5
		if r_se < 0.70 * se_shade:
			return 12

	# Serene mossy pillows & fine woodland clover mats framing natural clearings
	var r: float = rng.randf()
	if d_n < 0.42 and r < 0.32:
		return 14 if rng.randf() < 0.52 else (15 if rng.randf() < 0.65 else 7)
	# Sweeping tall meadow sedges & nodding golden seed plumes in lush pockets
	if t_n > 0.52 and r < 0.42:
		if rng.randf() < 0.15:
			return 23 ## golden seed plume
		return rng.randi_range(8, 13)
	# Core multi-blade lush grass tufts (0..7)
	return rng.randi_range(0, 7)


func set_debug_overlay(enabled: bool) -> void:
	if _trail_mat != null:
		_trail_mat.set_shader_parameter("debug_overlay", 0.85 if enabled else 0.0)


func set_grass_visible(on: bool) -> void:
	_grass_visible = on
	if _bands_root != null:
		_bands_root.visible = on
	if _glow_root != null:
		_glow_root.visible = on and TimeManager.night_amount() > 0.02
	if _trail_rect != null:
		_trail_rect.visible = on


## Queries current crush intensity (0..1) at a world position (useful for verification & telemetry).
func crush_at(world_pos: Vector2) -> float:
	var wc: Vector2i = _world_to_cell(world_pos)
	if not _active.has(wc):
		return 0.0
	return (_active[wc] as DeformCell).crush


func _world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i((world_pos / CELL_PX).floor())


func _cell_to_world(wc: Vector2i) -> Vector2:
	return Vector2(wc) * CELL_PX + Vector2(CELL_PX * 0.5, CELL_PX * 0.5)


func _cell_in_window(wc: Vector2i) -> bool:
	return (
		wc.x >= _field_cell_origin.x
		and wc.x < _field_cell_origin.x + FIELD_RES
		and wc.y >= _field_cell_origin.y
		and wc.y < _field_cell_origin.y + FIELD_RES
	)


func _cell_to_tex(wc: Vector2i) -> Vector2i:
	return Vector2i(posmod(wc.x, FIELD_RES), posmod(wc.y, FIELD_RES))


## Slides the 512x512 px toroidal deformation window to stay centered on `target_world_pos`.
## Existing trails stay 100% world-locked in memory; only newly wrapped strips are cleared to neutral!
func recenter_field(target_world_pos: Vector2) -> bool:
	if _field_img == null:
		return false
	var desired_origin: Vector2i = Vector2i(
		floori(target_world_pos.x / CELL_PX) - FIELD_RES / 2,
		floori(target_world_pos.y / CELL_PX) - FIELD_RES / 2
	)
	var delta_c: Vector2i = desired_origin - _field_cell_origin
	if absi(delta_c.x) < RECENTER_STEP_CELLS and absi(delta_c.y) < RECENTER_STEP_CELLS:
		return false

	var old_origin: Vector2i = _field_cell_origin
	_field_cell_origin = desired_origin
	field_origin = Vector2(_field_cell_origin) * CELL_PX
	var neutral: Color = Color(0.5, 0.5, 0.0, 0.5)

	if absi(delta_c.x) >= FIELD_RES or absi(delta_c.y) >= FIELD_RES:
		# Large teleport: reset whole ring-buffer cleanly
		_field_img.fill(neutral)
		_active.clear()
	else:
		# Clear ONLY newly entered wrapped columns/rows (O(perimeter), never copies existing trails!)
		if delta_c.x > 0:
			for wx: int in range(old_origin.x + FIELD_RES, _field_cell_origin.x + FIELD_RES):
				var tx: int = posmod(wx, FIELD_RES)
				for ty: int in FIELD_RES:
					_field_img.set_pixel(tx, ty, neutral)
		elif delta_c.x < 0:
			for wx: int in range(_field_cell_origin.x, old_origin.x):
				var tx: int = posmod(wx, FIELD_RES)
				for ty: int in FIELD_RES:
					_field_img.set_pixel(tx, ty, neutral)
		if delta_c.y > 0:
			for wy: int in range(old_origin.y + FIELD_RES, _field_cell_origin.y + FIELD_RES):
				var ty: int = posmod(wy, FIELD_RES)
				for tx: int in FIELD_RES:
					_field_img.set_pixel(tx, ty, neutral)
		elif delta_c.y < 0:
			for wy: int in range(_field_cell_origin.y, old_origin.y):
				var ty: int = posmod(wy, FIELD_RES)
				for tx: int in FIELD_RES:
					_field_img.set_pixel(tx, ty, neutral)

		# Prune active cell records that scrolled out of the active window
		_remove_buf.clear()
		for wc_v: Variant in _active:
			var wc: Vector2i = wc_v as Vector2i
			if not _cell_in_window(wc):
				_remove_buf.append(wc)
		for rem: Vector2i in _remove_buf:
			_active.erase(rem)

	if _grass_mat != null:
		_grass_mat.set_shader_parameter("field_origin", field_origin)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("field_origin", field_origin)
	if _trail_mat != null:
		_trail_mat.set_shader_parameter("field_origin", field_origin)
	_dirty = true
	return true


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05) ## Guard trails & spring physics against frame-hitch spikes
	_mote_wait = maxf(0.0, _mote_wait - dt)
	_rustle_wait = maxf(0.0, _rustle_wait - dt)
	_prune_timer += dt
	if _prune_timer >= 1.0:
		_prune_timer = 0.0
		_prune_stale_actors()
	if _glow_root != null:
		_glow_root.visible = _grass_visible and TimeManager.night_amount() > 0.02
	if follow_camera:
		var cam: Camera2D = get_viewport().get_camera_2d()
		if cam != null:
			recenter_field(cam.get_screen_center_position())
	_track_actors(dt)
	_advance_field(dt)
	_advance_motes(dt)


func _prune_stale_actors() -> void:
	if _prev_pos.is_empty():
		return
	var dead: Array[int] = []
	for id_v: Variant in _prev_pos:
		var id: int = int(id_v)
		var obj: Object = instance_from_id(id)
		if obj == null or not (obj is Node2D) or not (obj as Node2D).is_inside_tree():
			dead.append(id)
	for id: int in dead:
		_prev_pos.erase(id)
		_stride_dist.erase(id)
		_stride_foot.erase(id)
		_prev_step_t.erase(id)
		_prev_swing.erase(id)


func _track_actors(delta: float) -> void:
	var safe_dt: float = maxf(delta, 0.008)
	var slot_idx: int = 0

	# 1. Players (full movement fidelity: L/R boot cadence, shadow step burst, sword slash gust, contact shadow)
	for player: Player in Player.all:
		if not is_instance_valid(player) or not player.is_inside_tree():
			continue
		var id: int = player.get_instance_id()
		var pos: Vector2 = player.global_position
		var prev: Vector2 = _prev_pos.get(id, pos) as Vector2
		_prev_pos[id] = pos

		if slot_idx < 4 and _bounds.grow(48.0).has_point(pos):
			_actor_slots[slot_idx] = Vector4(pos.x, pos.y + 1.0, 12.5, 0.85)
			slot_idx += 1

		# Shadow Step burst (departure & arrival radial ring)
		var step_t: float = player._step_t
		var prev_step: float = float(_prev_step_t.get(id, -1.0))
		_prev_step_t[id] = step_t
		if step_t >= 0.0 and prev_step < 0.0:
			stamp_burst(player._step_from, 26.0, 1.0, 7.8)
			_spawn_motes(player._step_from, 7, 48.0, true)
		elif prev_step >= 0.0 and prev_step < Player.STEP_GONE and step_t >= Player.STEP_GONE:
			stamp_burst(pos, 28.0, 1.0, 8.2)
			_spawn_motes(pos, 8, 56.0, true)

		# Sword Slash directional gust
		var swinging: bool = player.attack != null and player.attack.is_swinging()
		var was_swinging: bool = bool(_prev_swing.get(id, false))
		_prev_swing[id] = swinging
		if swinging and not was_swinging:
			var aim: Vector2 = player.attack.aim_dir
			if aim.length_squared() > 0.01:
				stamp_slash(pos, aim.normalized(), 34.0, 0.72)
				_spawn_motes(pos + aim.normalized() * 18.0, 5, 42.0, false)

		if not _bounds.grow(24.0).has_point(pos):
			continue

		if player.air_height > 2.5:
			continue

		var dist: float = prev.distance_to(pos)
		if dist > 96.0:
			continue

		if dist < 0.35:
			_stamp_standing(pos, 8.5, 0.50)
		else:
			var speed: float = dist / safe_dt
			var sneaking: bool = player.stealth != null and player.stealth.sneaking
			var sprinting: bool = player.sprinting or speed > 96.0
			var crush_amt: float = 0.44 if sneaking else (0.98 if sprinting else 0.74)
			var hold_sec: float = 1.05 if sneaking else (2.5 if sprinting else 1.65)
			var recover_sec: float = 4.4 if sneaking else (8.0 if sprinting else 6.0)
			var radius: float = 10.5 if sneaking else (14.5 if sprinting else 12.2)
			var wobble: float = 0.35 if sneaking else (1.0 if sprinting else 0.65)

			# Subtle alternating left/right boot offset for natural tactile footstep cadence!
			var stride_len: float = 9.0 if sneaking else (13.5 if sprinting else 11.0)
			var acc: float = float(_stride_dist.get(id, 0.0)) + dist
			var side: float = float(_stride_foot.get(id, 1.0))
			if acc >= stride_len:
				acc -= stride_len
				side = -side
				_stride_foot[id] = side
			_stride_dist[id] = acc
			var move_dir: Vector2 = (pos - prev) / dist
			var foot_off: Vector2 = Vector2(-move_dir.y, move_dir.x) * (side * 2.1)

			var touched: bool = stamp_segment(prev + foot_off, pos + foot_off, radius, crush_amt, hold_sec, recover_sec, wobble)
			if touched and _has_grass_near(pos):
				_play_rustle(pos, sneaking, sprinting)
				if _mote_wait <= 0.0 and (sprinting or speed > 62.0):
					_mote_wait = 0.13 if sprinting else 0.24
					_spawn_motes(pos, 3 if sprinting else 2, 34.0 if sprinting else 20.0, false)

	# 2. Generic world entities (enemies, wildlife, woodland mammals, NPCs, custom "grass_deformer")
	for grp: String in ACTOR_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(grp):
			var body: Node2D = node as Node2D
			if body == null or body is Player or not body.is_inside_tree():
				continue
			slot_idx = _track_generic_actor(body, safe_dt, slot_idx, 10.5, 0.65)

	# 3. Corvids / Ellie's Raven (soft small impression only when hopping/resting on the grass)
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		var body: Node2D = node as Node2D
		if body == null or not body.is_inside_tree():
			continue
		var h_val: Variant = node.get("_height")
		if h_val != null and float(h_val) > 3.0:
			continue
		slot_idx = _track_generic_actor(body, safe_dt, slot_idx, 6.5, 0.45)

	# Zero unused contact shadow slots and upload to lit grass shader
	while slot_idx < 4:
		_actor_slots[slot_idx] = Vector4.ZERO
		slot_idx += 1
	if _grass_mat != null:
		_grass_mat.set_shader_parameter("actors", _actor_slots)


func _track_generic_actor(body: Node2D, safe_dt: float, slot_idx: int, default_radius: float, default_weight: float) -> int:
	var pos: Vector2 = body.global_position
	if not _bounds.grow(28.0).has_point(pos):
		return slot_idx
	var radius: float = float(body.get_meta("grass_radius", default_radius))
	var weight: float = float(body.get_meta("grass_weight", default_weight))
	if slot_idx < 4:
		_actor_slots[slot_idx] = Vector4(pos.x, pos.y + 1.0, radius, weight * 0.78)
		slot_idx += 1
	var id: int = body.get_instance_id()
	var prev: Vector2 = _prev_pos.get(id, pos) as Vector2
	_prev_pos[id] = pos
	var dist: float = prev.distance_to(pos)
	if dist > 96.0:
		return slot_idx
	if dist < 0.35:
		_stamp_standing(pos, radius * 0.72, 0.38 * weight)
	else:
		var speed: float = dist / safe_dt
		var boost: float = clampf(speed / 90.0, 0.45, 1.25)
		stamp_segment(prev, pos, radius, clampf(0.62 * weight * boost, 0.25, 0.92), 1.1, 4.8, 0.55 * weight)
	return slot_idx


## Creates a gentle, persistent flattened meadow nest (e.g., Ellie resting/lying with her raven on join!).
func stamp_rest_nest(center_pos: Vector2, radius: float = 15.0, strength: float = 0.85, hold_sec: float = 3.5) -> void:
	var c0: Vector2i = _world_to_cell(center_pos)
	var r_cells: int = ceili(radius / CELL_PX)
	var r2: float = radius * radius
	for dy: int in range(-r_cells, r_cells + 1):
		for dx: int in range(-r_cells, r_cells + 1):
			var wc: Vector2i = c0 + Vector2i(dx, dy)
			if not _cell_in_window(wc):
				continue
			var offset: Vector2 = _cell_to_world(wc) - center_pos
			var d2: float = offset.length_squared()
			if d2 > r2:
				continue
			var dist: float = sqrt(d2)
			var falloff: float = pow(1.0 - dist / radius, 0.75)
			var outward: Vector2 = offset / maxf(dist, 0.5)
			var cell: DeformCell = _get_or_create_cell(wc)
			cell.dir = cell.dir.lerp(outward * clampf(0.45 + 0.55 * falloff, 0.0, 1.0), 0.55)
			cell.crush = maxf(cell.crush, clampf(strength * (0.35 + 0.65 * falloff), 0.0, 1.0))
			cell.hold = maxf(cell.hold, hold_sec * falloff)
			cell.recover_rate = minf(cell.recover_rate, 0.12)
			_dirty = true


## Public Movement 2.0 impulse receiver (`T12`, `V12`): radial landing shock-rings, sprint-pivot sweeps, and surge kicks.
func apply_locomotion_impulse(world_pos: Vector2, dir: Vector2, radius: float, crush_amt: float, wobble_amt: float, kind: String) -> void:
	if not _bounds.grow(36.0).has_point(world_pos):
		return
	if kind == "pivot" and dir.length_squared() > 0.01:
		stamp_slash(world_pos, -dir.normalized(), radius * 1.25, crush_amt)
		stamp_burst(world_pos, radius * 0.85, crush_amt, wobble_amt)
		_spawn_motes(world_pos, 5, 42.0, true)
	elif kind == "land":
		stamp_burst(world_pos, radius, crush_amt, wobble_amt)
		_spawn_motes(world_pos, 7, 48.0, true)
	elif kind == "surge":
		stamp_burst(world_pos, radius * 0.8, crush_amt * 0.85, wobble_amt)
		_spawn_motes(world_pos, 3, 32.0, false)


func _stamp_standing(pos: Vector2, radius: float, max_crush: float) -> void:
	var c0: Vector2i = _world_to_cell(pos)
	var r_cells: int = ceili(radius / CELL_PX)
	var r2: float = radius * radius
	for dy: int in range(-r_cells, r_cells + 1):
		for dx: int in range(-r_cells, r_cells + 1):
			var wc: Vector2i = c0 + Vector2i(dx, dy)
			if not _cell_in_window(wc) or not _has_grass_at_cell(wc):
				continue
			var delta_p: Vector2 = _cell_to_world(wc) - pos
			var d2: float = delta_p.length_squared()
			if d2 > r2:
				continue
			var falloff: float = 1.0 - sqrt(d2) / radius
			var target_crush: float = max_crush * falloff
			var cell: DeformCell = _get_or_create_cell(wc)
			if target_crush > cell.crush:
				cell.crush = target_crush
				var outward: Vector2 = delta_p.normalized() if d2 > 0.25 else Vector2(1.0, 0.0)
				cell.dir = cell.dir.lerp(outward * (0.45 + 0.55 * falloff), 0.35)
				cell.hold = maxf(cell.hold, 0.6)
				cell.recover_rate = minf(cell.recover_rate, 0.22)
				_dirty = true


## Sweeps a capsule from `from` to `to`, radially parting blades left & right around the stride
## while crushing them flat into a lingering 2-zone trail.
func stamp_segment(from: Vector2, to: Vector2, radius: float, crush_amt: float, hold_sec: float, recover_sec: float, wobble_amt: float) -> bool:
	var travel: Vector2 = to - from
	var length: float = travel.length()
	var move_dir: Vector2 = travel / maxf(length, 0.001)
	var steps: int = maxi(1, ceili(length / CELL_PX))
	var r_cells: int = ceili(radius / CELL_PX)
	var r2: float = radius * radius
	var touched: bool = false
	var rec_rate: float = 1.0 / maxf(recover_sec, 0.5)

	for s: int in steps + 1:
		var at: Vector2 = from.lerp(to, float(s) / float(steps))
		var center: Vector2i = _world_to_cell(at)
		for dy: int in range(-r_cells, r_cells + 1):
			for dx: int in range(-r_cells, r_cells + 1):
				var wc: Vector2i = center + Vector2i(dx, dy)
				if not _cell_in_window(wc):
					continue
				if not _has_grass_at_cell(wc):
					continue
				var offset: Vector2 = _cell_to_world(wc) - at
				var d2: float = offset.length_squared()
				if d2 > r2:
					continue
				var dist: float = sqrt(d2)
				var falloff: float = pow(1.0 - dist / radius, 0.85)
				var outward: Vector2 = offset / maxf(dist, 0.5)
				# Radial parting splits outer rim blades left & right while inner stride lays them along travel
				var push: Vector2 = (outward * 0.74 + move_dir * 0.42).normalized() * clampf(0.45 + 0.65 * falloff, 0.0, 1.0)
				var cell: DeformCell = _get_or_create_cell(wc)
				cell.dir = cell.dir.lerp(push, clampf(0.55 + 0.35 * falloff, 0.0, 1.0))
				cell.crush = maxf(cell.crush, clampf(crush_amt * (0.32 + 0.78 * falloff), 0.0, 1.0))
				cell.hold = maxf(cell.hold, hold_sec * (0.55 + 0.45 * falloff))
				cell.recover_rate = minf(cell.recover_rate, rec_rate)
				if wobble_amt * falloff > cell.wobble_amp * 0.7:
					cell.wobble_amp = maxf(cell.wobble_amp, wobble_amt * falloff)
					cell.wobble_t = 0.0
				_dirty = true
				touched = true
	return touched


## Radial burst (Shadow Step departure/arrival or heavy stomp): flattens a crisp ring outward.
func stamp_burst(center_pos: Vector2, radius: float, strength: float, recover_sec: float = 8.0) -> void:
	var c0: Vector2i = _world_to_cell(center_pos)
	var r_cells: int = ceili(radius / CELL_PX)
	var r2: float = radius * radius
	var rec_rate: float = 1.0 / maxf(recover_sec, 0.5)
	for dy: int in range(-r_cells, r_cells + 1):
		for dx: int in range(-r_cells, r_cells + 1):
			var wc: Vector2i = c0 + Vector2i(dx, dy)
			if not _cell_in_window(wc):
				continue
			var offset: Vector2 = _cell_to_world(wc) - center_pos
			var d2: float = offset.length_squared()
			if d2 > r2:
				continue
			var dist: float = sqrt(d2)
			var falloff: float = 1.0 - dist / radius
			var outward: Vector2 = offset / maxf(dist, 0.5)
			var cell: DeformCell = _get_or_create_cell(wc)
			cell.dir = outward * clampf(0.55 + 0.65 * falloff, 0.0, 1.0)
			cell.crush = maxf(cell.crush, clampf(strength * (0.45 + 0.65 * falloff), 0.0, 1.0))
			cell.hold = maxf(cell.hold, 2.2 * falloff + 0.6)
			cell.recover_rate = minf(cell.recover_rate, rec_rate)
			cell.wobble_amp = maxf(cell.wobble_amp, strength * falloff)
			cell.wobble_t = 0.0
			_dirty = true


## Directional gust from a sword swing sweeping across grass in front of Ellie.
func stamp_slash(origin: Vector2, aim_dir: Vector2, reach: float, strength: float = 0.7) -> void:
	var sweep_center: Vector2 = origin + aim_dir * (reach * 0.55)
	var radius: float = reach * 0.68
	var c0: Vector2i = _world_to_cell(sweep_center)
	var r_cells: int = ceili(radius / CELL_PX)
	var r2: float = radius * radius
	var perp: Vector2 = Vector2(-aim_dir.y, aim_dir.x)
	for dy: int in range(-r_cells, r_cells + 1):
		for dx: int in range(-r_cells, r_cells + 1):
			var wc: Vector2i = c0 + Vector2i(dx, dy)
			if not _cell_in_window(wc):
				continue
			var offset: Vector2 = _cell_to_world(wc) - sweep_center
			var d2: float = offset.length_squared()
			if d2 > r2:
				continue
			var falloff: float = 1.0 - sqrt(d2) / radius
			var cell: DeformCell = _get_or_create_cell(wc)
			cell.dir = (aim_dir * 0.65 + perp * 0.55).normalized() * clampf(0.5 + 0.5 * falloff, 0.0, 1.0)
			cell.crush = maxf(cell.crush, 0.42 * strength * falloff)
			cell.hold = maxf(cell.hold, 0.55 * falloff)
			cell.recover_rate = maxf(cell.recover_rate, 0.25)
			cell.wobble_amp = maxf(cell.wobble_amp, strength * falloff)
			cell.wobble_t = 0.0
			_dirty = true


func _get_or_create_cell(wc: Vector2i) -> DeformCell:
	if _active.has(wc):
		return _active[wc] as DeformCell
	var cell: DeformCell = DeformCell.new()
	_active[wc] = cell
	return cell


## Advances elastic grass recovery & impact spring wobble (zero per-frame array churn) and updates the toroidal GPU texture.
func _advance_field(delta: float) -> void:
	if _active.is_empty() and not _dirty:
		return
	_upload_timer += delta
	var do_upload: bool = _dirty or _upload_timer >= UPLOAD_INTERVAL

	_remove_buf.clear()
	for wc_key: Variant in _active:
		var wc: Vector2i = wc_key as Vector2i
		var cell: DeformCell = _active[wc] as DeformCell
		if cell.hold > 0.0:
			cell.hold = maxf(0.0, cell.hold - delta)
		else:
			cell.crush = maxf(0.0, cell.crush - cell.recover_rate * delta)
			var dir_decay: float = exp(-delta * maxf(cell.recover_rate * 1.4, 0.35))
			cell.dir *= dir_decay

		var wobble_val: float = 0.0
		if cell.wobble_amp > 0.005:
			cell.wobble_t += delta
			var env: float = exp(-cell.wobble_t * 5.8)
			if env < 0.02:
				cell.wobble_amp = 0.0
			else:
				wobble_val = cell.wobble_amp * env * cos(cell.wobble_t * 17.0)

		var tex_c: Vector2i = _cell_to_tex(wc)
		if cell.crush <= 0.004 and cell.dir.length_squared() <= 0.0004 and cell.wobble_amp <= 0.005:
			_field_img.set_pixelv(tex_c, Color(0.5, 0.5, 0.0, 0.5))
			_remove_buf.append(wc)
			do_upload = true
		elif do_upload:
			var r_v: float = clampf(0.5 + cell.dir.x * 0.5, 0.0, 1.0)
			var g_v: float = clampf(0.5 + cell.dir.y * 0.5, 0.0, 1.0)
			var b_v: float = clampf(cell.crush, 0.0, 1.0)
			var a_v: float = clampf(0.5 + wobble_val * 0.5, 0.0, 1.0)
			_field_img.set_pixelv(tex_c, Color(r_v, g_v, b_v, a_v))

	for rem: Vector2i in _remove_buf:
		_active.erase(rem)

	if do_upload:
		_field_tex.update(_field_img)
		_upload_timer = 0.0
		_dirty = false


## Checks whether an 8x8 px neighborhood around a world position actually contains living grass tufts.
func _has_grass_near(pos: Vector2) -> bool:
	if _grass_cells.is_empty():
		return true
	var c0: Vector2i = Vector2i((pos / 8.0).floor())
	if _grass_cells.has(c0):
		return true
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if _grass_cells.has(c0 + Vector2i(dx, dy)):
				return true
	return false


func _has_grass_at_cell(wc: Vector2i) -> bool:
	if (_surfaces == null and extra_habitat_providers.is_empty()) or _grass_cells.is_empty():
		return true
	var gc: Vector2i = Vector2i(floori(float(wc.x) * 0.5), floori(float(wc.y) * 0.5))
	if _grass_cells.has(gc):
		return true
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if _grass_cells.has(gc + Vector2i(dx, dy)):
				return true
	return false


## Looks up whether a world position sits on a white/blue/lilac floral cushion (for context-aware petal kick-up).
func _floral_kind_at(pos: Vector2) -> int:
	var c0: Vector2i = Vector2i((pos / 8.0).floor())
	if _floral_cells.has(c0):
		return int(_floral_cells[c0])
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var nc: Vector2i = c0 + Vector2i(dx, dy)
			if _floral_cells.has(nc):
				return int(_floral_cells[nc])
	return 0


func _spawn_motes(at: Vector2, count: int, burst_speed: float, force_petals: bool) -> void:
	if _mote_layer == null:
		return
	var f_kind: int = _floral_kind_at(at)
	for _i: int in count:
		if _mote_layer.motes.size() >= MAX_MOTES:
			_mote_layer.motes.pop_front()
		var m: GrassMote = GrassMote.new()
		var ang: float = _rng.randf() * TAU
		var spd: float = _rng.randf_range(0.35, 1.0) * burst_speed
		m.pos = at + Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-3.0, 3.0))
		m.vel = Vector2.from_angle(ang) * spd
		m.z_h = _rng.randf_range(1.5, 4.5)
		m.z_vel = _rng.randf_range(16.0, 34.0)
		m.life = _rng.randf_range(0.50, 1.05)
		m.phase = _rng.randf() * TAU

		var is_petal: bool = (f_kind > 0 and _rng.randf() < 0.72) or (force_petals and _rng.randf() < 0.38)
		if is_petal:
			var pal: Array[Color] = PETAL_WHITE if f_kind == 1 else (PETAL_BLUE if f_kind == 2 else (PETAL_LILAC if f_kind == 3 else PETAL_ALL))
			m.color = pal[_rng.randi() % pal.size()]
			m.size_px = Vector2(2.0, 1.0) if _rng.randf() < 0.45 else Vector2(1.0, 1.0)
			m.flutter = true
			m.z_vel *= 0.85
			m.life *= 1.35
		else:
			m.color = BLADE_COLORS[_rng.randi() % BLADE_COLORS.size()]
			m.size_px = Vector2(2.0, 1.0) if _rng.randf() < 0.65 else Vector2(1.0, 1.0)
			m.flutter = false
		_mote_layer.motes.append(m)


func _advance_motes(delta: float) -> void:
	if _mote_layer == null or _mote_layer.motes.is_empty():
		return
	var wind_v: Vector2 = WorldWind.sample(global_position) * 26.0
	for i: int in range(_mote_layer.motes.size() - 1, -1, -1):
		var m: GrassMote = _mote_layer.motes[i]
		m.age += delta
		if m.age >= m.life:
			_mote_layer.motes.remove_at(i)
			continue
		m.vel = m.vel.lerp(wind_v, minf(1.0, delta * (4.2 if m.flutter else 3.4)))
		m.pos += m.vel * delta
		var grav: float = 36.0 if m.flutter else 68.0
		m.z_vel -= grav * delta
		m.z_h = maxf(0.0, m.z_h + m.z_vel * delta)
		if m.z_h <= 0.0:
			m.vel *= 0.65
			m.z_vel = 0.0
	_mote_layer.queue_redraw()


func _play_rustle(pos: Vector2, sneaking: bool, sprinting: bool) -> void:
	if _rustle == null or _rustle_wait > 0.0 or InputManager.ui_blocking:
		return
	_rustle_wait = 0.48 if sneaking else (0.20 if sprinting else 0.34)
	_rustle.position = pos
	_rustle.volume_db = -35.0 if sneaking else (-24.0 if sprinting else -29.0)
	_rustle.pitch_scale = _rng.randf_range(0.86, 1.18)
	if not _rustle.playing:
		_rustle.play()
