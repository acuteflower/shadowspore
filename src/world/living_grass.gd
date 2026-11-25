class_name LivingGrass
extends Node2D
## LivingGrass v4 — Multi-species, dual-tier interactive pixel-art living grass ecosystem:
## - Dual-tier Y-sorted MultiMesh architecture (fine 4 px Y-sort bands so tall & short blades wrap genuinely around legs):
##     1. Standard Tier (20x24 px, 5-row parabolic mesh): 40 handcrafted botanical variants x mirror (= 80 silhouettes)
##        fescue, wind-combed turf, sedges, ribwort plantain, moss pillows, clover, 8 wildflower species,
##        woodland ferns/fiddleheads/bilberry/fallen-leaf sedges/pin-mushrooms, stone-crevice thyme,
##        seed plumes, brook rushes, red sorrel, coastal Strandhafer, upland sheep's fescue.
##     2. Tall Grass Tier (24x36 px, 7-row parabolic mesh, 21-33 px knee-to-hip height vs 42 px Ellie!):
##        24 handcrafted tall-species variants x mirror (= 48 silhouettes -> 128 total silhouettes!)
##        waist-high wild meadow horsts, wind waves, dense thickets, wild oats, silver feather-grass,
##        meadowsweet, oxeye daisies, wild sage spires, knapweed, goldenrod, cow-parsley, red sorrel,
##        dew-pearl moon-grass, brook reeds, cattails (Rohrkolben), plumed common reed, yellow flag iris,
##        woodland eagle-ferns, horsetail/sedge, tall coastal Strandhafer & steppe feather-grass.
## - Domain-warped ecological micro-habitats: serene moss clearings, classic meadow, sweeping wildflower drifts,
##   and waist-high Hohes-Gras belts with safe northern overhang checks (never pokes over stone slabs or paths!).
## - Live zero-lag actor parting curtain + camera-centered toroidal 128x128 (512x512 px) persistent trail ring-buffer.
## - Active unlit night-dew, silver-plume & blossom glow pass (zero daytime drawcalls).
## - Context-aware blade, pollen/seed-fluff & 5-color wildflower petal motes + depth-sensitive positional rustle audio.

const STD_CELL_SIZE: Vector2 = Vector2(20.0, 24.0)
const STD_MESH_ROWS: int = 4 ## 4 vertical segments = 5 vertex rows
const STD_FOOT_OFFSET: float = 10.0 ## Foot y=22 inside 24 px cell -> +10 px from center
const STD_COLS: int = 8
const STD_ROWS: int = 5
const STD_COUNT: int = STD_COLS * STD_ROWS ## 40

const TALL_CELL_SIZE: Vector2 = Vector2(24.0, 36.0)
const TALL_MESH_ROWS: int = 6 ## 6 vertical segments = 7 vertex rows for silky tall-grass arching
const TALL_FOOT_OFFSET: float = 16.0 ## Foot y=34 inside 36 px cell -> +16 px from center
const TALL_COLS: int = 8
const TALL_ROWS: int = 3
const TALL_COUNT: int = TALL_COLS * TALL_ROWS ## 24

const BAND_HEIGHT: float = 4.0 ## Crisp 4 px Y-sort bands so knee/hip-high blades wrap seamlessly around Ellie
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
const TALL_ATLAS_TEX: Texture2D = preload("res://assets/tiles/living_grass_tall.png")
const TALL_GLOW_TEX: Texture2D = preload("res://assets/tiles/living_grass_tall_glow.png")

const MAX_MOTES: int = 44
const STYLE_NONE: int = 0
const STYLE_MEADOW: int = 1
const STYLE_FOREST: int = 2
const STYLE_REED: int = 3
const STYLE_DUNE: int = 4
const STYLE_MOSS: int = 5

const BLADE_COLORS: Array[Color] = [
	Color("5ea05e"), Color("84c06c"), Color("30664b"), Color("b2de8d"), Color("9b9d63"),
]
const FOREST_BLADE_COLORS: Array[Color] = [
	Color("2d6152"), Color("427e5e"), Color("63a36e"), Color("204442"),
]
const REED_BLADE_COLORS: Array[Color] = [
	Color("2f7162"), Color("449173"), Color("68b288"), Color("21514d"),
]
const DUNE_BLADE_COLORS: Array[Color] = [
	Color("c0ba86"), Color("e4dcab"), Color("98996c"), Color("727b58"),
]
const MOSS_BLADE_COLORS: Array[Color] = [
	Color("438356"), Color("63a36e"), Color("2d6152"), Color("8ac385"),
]
const HOE_TILL_SFX: AudioStream = preload("res://assets/audio/farming/hoe_till.wav")
const SOIL_CRUMB_COLORS: Array[Color] = [
	Color("583d2e"), Color("3e2a20"), Color("72523d"), Color("4a3326"),
]
const POLLEN_COLORS: Array[Color] = [
	Color("f5f0da"), Color("e4dc9e"), Color("ece9d8"), Color("ffea8a"),
]
const PETAL_WHITE: Array[Color] = [
	Color("faf6ea"), Color("ddd8cc"), Color("ffea8a"),
]
const PETAL_BLUE: Array[Color] = [
	Color("d0ebff"), Color("8ab5e4"), Color("faf6ea"),
]
const PETAL_LILAC: Array[Color] = [
	Color("dcd0fa"), Color("9d88d6"), Color("faf6ea"),
]
const PETAL_GOLD: Array[Color] = [
	Color("ffea8a"), Color("e4b848"), Color("faf6ea"),
]
const PETAL_ROSE: Array[Color] = [
	Color("e8b6cc"), Color("ba7698"), Color("faf6ea"),
]
const PETAL_ALL: Array[Color] = [
	Color("faf6ea"), Color("d0ebff"), Color("dcd0fa"), Color("ffea8a"), Color("e8b6cc"),
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

## Per-instance handle for removable tall-grass tufts (O(1) hide on hoe clear, zero MultiMesh rebuild).
class TallTuftRef:
	var id: int = -1
	var pos: Vector2 = Vector2.ZERO
	var style_id: int = STYLE_MEADOW
	var floral_code: int = 0
	var mm_lit: MultiMesh = null
	var idx_lit: int = -1
	var orig_transform_lit: Transform2D = Transform2D.IDENTITY
	var orig_custom_lit: Color = Color.BLACK
	var mm_glow: MultiMesh = null
	var idx_glow: int = -1
	var orig_transform_glow: Transform2D = Transform2D.IDENTITY
	var orig_custom_glow: Color = Color.BLACK
	var removed: bool = false


## Lightweight pixel mote drawn in `MoteLayer._draw()` (zero node churn).
class GrassMote:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var z_h: float = 2.0
	var z_vel: float = 18.0
	var age: float = 0.0
	var life: float = 0.7
	var color: Color = Color("84c06c")
	var size_px: Vector2 = Vector2(2.0, 1.0)
	var flutter: bool = false
	var phase: float = 0.0


## RefCounted wrapper around a packed float buffer per Y-sort band (mutated in-place, zero CoW copies, zero per-tuft Dicts!).
## Stride = 11 floats: [px, py, kind_f, phase, flex, hscale, r, g, b, a, tall_id_f]
const BAND_STRIDE: int = 11


class BandBuf:
	var data: PackedFloat32Array = PackedFloat32Array()
	var size: int = 0

	func push(px: float, py: float, kind_f: float, phase: float, flex: float, hscale: float, tint_c: Color, tall_id_f: float) -> void:
		var need: int = size + BAND_STRIDE
		if need > data.size():
			data.resize(maxi(need, maxi(BAND_STRIDE * 32, data.size() * 2)))
		var o: int = size
		data[o] = px
		data[o + 1] = py
		data[o + 2] = kind_f
		data[o + 3] = phase
		data[o + 4] = flex
		data[o + 5] = hscale
		data[o + 6] = tint_c.r
		data[o + 7] = tint_c.g
		data[o + 8] = tint_c.b
		data[o + 9] = tint_c.a
		data[o + 10] = tall_id_f
		size = need


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
			var drift_x: float = sin(m.age * 8.5 + m.phase) * 1.5 if m.flutter else 0.0
			var p: Vector2 = Vector2(roundf(m.pos.x + drift_x), roundf(m.pos.y - m.z_h))
			draw_rect(Rect2(p, m.size_px), c)


static var _shared_std_mesh: ArrayMesh
static var _shared_tall_mesh: ArrayMesh

var field_origin: Vector2 = Vector2(-256.0, -256.0)
var tuft_count: int = 0 ## Total tufts (standard + tall)
var std_tuft_count: int = 0
var tall_tuft_count: int = 0
var glow_tuft_count: int = 0
var follow_camera: bool = true ## Slides the 512x512 toroidal deform window with the active camera

var _bounds: Rect2 = Rect2()
var _surfaces: GroundSurfaces = null
var _custom_meadow_rect: Rect2 = Rect2()
var extra_habitat_providers: Array[Node] = []
var _cached_providers: Array[Node] = []
var _cached_deck_patches: Array[Node] = []
var _zone_mask_provider: ZoneStage = null
var _providers_cached: bool = false
var _cell_origin: Vector2i = Vector2i.ZERO
var _cell_w: int = 0
var _cell_h: int = 0
var _cell_style: PackedByteArray = PackedByteArray() ## 8x8px flat grid: 0=none, 1..5=STYLE_*
var _cell_tall: PackedByteArray = PackedByteArray() ## 8x8px flat grid: 0..255 mapped to 0.0..1.0
var _cell_floral: PackedByteArray = PackedByteArray() ## 8x8px flat grid: 0..5 floral code
var _cell_grid_ready: bool = false
var _use_cell_dicts: bool = true ## Kept true for small lab patches (grass_lab/e2e); disabled on L/XL zones to avoid 400k dict hashes!
var _field_cell_origin: Vector2i = Vector2i(-64, -64)
var _field_img: Image
var _field_tex: ImageTexture
var _grass_mat: ShaderMaterial
var _tall_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _tall_glow_mat: ShaderMaterial
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
var _floral_cells: Dictionary = {} ## Vector2i (8x8 px cell) -> int (1=white, 2=blue, 3=lilac, 4=gold, 5=rose)
var _grass_cells: Dictionary = {} ## Vector2i (8x8 px cell) -> true (actual tuft presence: gates trails/rustle/motes!)
var _grass_style: Dictionary = {} ## Vector2i (8x8 px cell) -> int (STYLE_MEADOW..STYLE_MOSS)
var _tall_cells: Dictionary = {} ## Vector2i (8x8 px cell) -> float (0..1 local tall-grass density/height)
var _tall_tufts: Array[TallTuftRef] = [] ## Deterministic tall-tuft registry for host-authoritative hoe clearing
var _tall_grid: Dictionary = {} ## Vector2i (16x16 px cell) -> Array[int] indices into `_tall_tufts`
var _removed_tall: Dictionary = {} ## int tall_id -> true (persisted / synced cleared tall tufts)

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
var _hoe_sfx: AudioStreamPlayer2D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func _build_strip_mesh(cell_size: Vector2, rows: int) -> ArrayMesh:
	var hw: float = cell_size.x * 0.5
	var hh: float = cell_size.y * 0.5
	var verts: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for r: int in rows + 1:
		var t: float = float(r) / float(rows)
		var y: float = lerpf(hh, -hh, t)
		verts.append(Vector2(-hw, y))
		uvs.append(Vector2(0.0, t))
		verts.append(Vector2(hw, y))
		uvs.append(Vector2(1.0, t))
	for r: int in rows:
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
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _get_std_mesh() -> ArrayMesh:
	if _shared_std_mesh == null:
		_shared_std_mesh = _build_strip_mesh(STD_CELL_SIZE, STD_MESH_ROWS)
	return _shared_std_mesh


static func _get_tall_mesh() -> ArrayMesh:
	if _shared_tall_mesh == null:
		_shared_tall_mesh = _build_strip_mesh(TALL_CELL_SIZE, TALL_MESH_ROWS)
	return _shared_tall_mesh


func _ready() -> void:
	y_sort_enabled = true
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("living_grass")
	_rustle = AudioStreamPlayer2D.new()
	_rustle.stream = preload("res://assets/audio/hut/rustle.wav")
	_rustle.max_distance = 148.0
	_rustle.volume_db = -28.0
	add_child(_rustle)
	_hoe_sfx = AudioStreamPlayer2D.new()
	_hoe_sfx.stream = HOE_TILL_SFX
	_hoe_sfx.max_distance = 220.0
	_hoe_sfx.volume_db = -7.0
	add_child(_hoe_sfx)


func set_meadow_rect(rect: Rect2) -> void:
	_custom_meadow_rect = rect


func set_water_habitat_provider(provider: Node) -> void:
	extra_habitat_providers.clear()
	if provider != null:
		extra_habitat_providers.append(provider)


func add_habitat_provider(provider: Node) -> void:
	if provider != null and not extra_habitat_providers.has(provider):
		extra_habitat_providers.append(provider)


const HAB_STYLE_NAMES: PackedStringArray = [
	"none", "meadow", "stone_seam", "path_edge", "forest", "moss_edge", "bank_reed", "dune_oat", "coastal_edge",
]


static func _hab_style_code(name: String) -> int:
	match name:
		"meadow":
			return 1
		"stone_seam":
			return 2
		"path_edge":
			return 3
		"forest":
			return 4
		"moss_edge":
			return 5
		"bank_reed":
			return 6
		"dune_oat":
			return 7
		"coastal_edge":
			return 8
		_:
			return 0


## Zero-allocation habitat query returning `Vector3(density, height_scale, style_code)`.
func _query_habitat_vec(world_pos: Vector2) -> Vector3:
	if _zone_mask_provider != null and not _zone_mask_provider.is_dry_tile_px(world_pos):
		return Vector3(0.0, 1.0, 0.0)
	var dens: float = 1.0
	var hscale: float = 1.0
	var style_i: int = 1
	if _surfaces != null:
		var sv: Vector3 = _surfaces.grass_habitat_vec(world_pos)
		dens = sv.x
		hscale = sv.y
		style_i = int(sv.z)
		if dens <= 0.02 or style_i == 0:
			return Vector3(0.0, hscale, 0.0)

	if _providers_cached:
		if not _cached_deck_patches.is_empty():
			for patch: Node in _cached_deck_patches:
				if bool(patch.call("has_water_deck_at", world_pos)):
					return Vector3(0.0, 0.6, 0.0)
		for prov: Node in _cached_providers:
			var pv: Vector3
			if prov is WaterField:
				pv = (prov as WaterField).grass_habitat_vec(world_pos)
			elif prov is RockyGround:
				pv = (prov as RockyGround).grass_habitat_vec(world_pos)
			elif prov is GroundSurfaces:
				pv = (prov as GroundSurfaces).grass_habitat_vec(world_pos)
			elif prov is ZoneStage:
				if (prov as ZoneStage).is_dry_tile_px(world_pos):
					continue
				return Vector3(0.0, 1.0, 0.0)
			else:
				var phab: Dictionary = prov.call("grass_habitat_at", world_pos) as Dictionary
				var psc: int = _hab_style_code(String(phab.get("style", "meadow")))
				pv = Vector3(float(phab.get("density", 1.0)), float(phab.get("height_scale", 1.0)), float(psc))
				if pv.x > 0.02 and psc != 0 and prov.has_method("surface_at"):
					var psurf: String = String(prov.call("surface_at", world_pos))
					if psurf in ["wet_sand", "tide_shallow", "puddle", "shallow_water", "deep_water"]:
						return Vector3(0.0, 0.6, 0.0)
			var pstyle_i: int = int(pv.z)
			if pv.x <= 0.02 or pstyle_i == 0:
				return Vector3(0.0, pv.y, 0.0)
			if pstyle_i != 1:
				dens = minf(dens, pv.x)
				hscale = pv.y
				style_i = pstyle_i
		return Vector3(dens, hscale, float(style_i))

	var fallback: Dictionary = _query_habitat(world_pos)
	return Vector3(float(fallback.get("density", 1.0)), float(fallback.get("height_scale", 1.0)), float(_hab_style_code(String(fallback.get("style", "meadow")))))


func _query_habitat(world_pos: Vector2) -> Dictionary:
	if _zone_mask_provider != null and not _zone_mask_provider.is_dry_tile_px(world_pos):
		return {"density": 0.0, "height_scale": 1.0, "style": "none"}
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

	var deck_patches: Array[Node] = _cached_deck_patches if _providers_cached else Terrain.patches
	for patch: Node in deck_patches:
		if (_providers_cached or patch.has_method("has_water_deck_at")) and bool(patch.call("has_water_deck_at", world_pos)):
			return {"density": 0.0, "height_scale": 0.6, "style": "none"}

	var providers: Array[Node] = _cached_providers
	if not _providers_cached:
		providers = extra_habitat_providers.duplicate()
		for patch: Node in Terrain.patches:
			if patch.has_method("grass_habitat_at") and not providers.has(patch):
				providers.append(patch)

	for prov: Node in providers:
		if not _providers_cached and (not is_instance_valid(prov) or not prov.has_method("grass_habitat_at")):
			continue
		var phab: Dictionary
		if prov is ZoneStage:
			phab = (prov as ZoneStage).grass_habitat_at(world_pos)
		elif prov is WaterField:
			phab = (prov as WaterField).grass_habitat_at(world_pos)
		elif prov is RockyGround:
			phab = (prov as RockyGround).grass_habitat_at(world_pos)
		else:
			phab = prov.call("grass_habitat_at", world_pos) as Dictionary
		var pdens: float = float(phab.get("density", 1.0))
		var pstyle: String = String(phab.get("style", "meadow"))
		var phscale: float = float(phab.get("height_scale", 1.0))
		if pdens <= 0.02 or pstyle == "none":
			return {"density": 0.0, "height_scale": phscale, "style": "none"}
		# RockyGround/ZoneStage never produce water surfaces, and WaterField.grass_habitat_at already clears all wet/water regimes!
		if not (prov is RockyGround) and not (prov is ZoneStage) and not (prov is WaterField) and prov.has_method("surface_at"):
			var psurf: String = String(prov.call("surface_at", world_pos))
			if psurf in ["wet_sand", "tide_shallow", "puddle", "shallow_water", "deep_water"]:
				return {"density": 0.0, "height_scale": 0.6, "style": "none"}
		if pstyle != "meadow":
			dens = minf(dens, pdens)
			hscale = phscale
			style = pstyle

	return {"density": dens, "height_scale": hscale, "style": style}


## Asymmetric north-tip clearance check so 24..33 px tall blades never poke over antique stone slabs,
## cobble avenues, boulders, puddles, or bridges rooted just north of the tuft!
func _tall_tip_clear(pos: Vector2, local_style: String) -> bool:
	var probe_mid: Vector2 = pos + Vector2(0.0, -16.0)
	var probe_top: Vector2 = pos + Vector2(0.0, -28.0)
	var deck_patches: Array[Node] = _cached_deck_patches if _providers_cached else Terrain.patches
	if not deck_patches.is_empty():
		for patch: Node in deck_patches:
			if _providers_cached or patch.has_method("has_water_deck_at"):
				if bool(patch.call("has_water_deck_at", probe_mid)) or bool(patch.call("has_water_deck_at", probe_top)):
					return false
	if local_style == "bank_reed":
		# Reeds & cattails naturally lean out over brook water, only block stone slabs & bridge parapets!
		if _surfaces != null:
			var s1: int = int(_surfaces.grass_habitat_vec(probe_mid).z)
			if s1 == 2 or s1 == 0:
				return false
			var s2: int = int(_surfaces.grass_habitat_vec(probe_top).z)
			if s2 == 2 or s2 == 0:
				return false
		return true
	var nhab: Vector3 = _query_habitat_vec(probe_mid)
	var nstyle_i: int = int(nhab.z)
	if local_style == "dune_oat":
		return nstyle_i != 0 and nhab.x > 0.05
	if nhab.x <= 0.15 or nstyle_i == 0 or nstyle_i == 2 or nstyle_i == 3:
		return false
	var thab: Vector3 = _query_habitat_vec(probe_top)
	var tstyle_i: int = int(thab.z)
	if tstyle_i == 2 or (tstyle_i == 0 and thab.x <= 0.02):
		return false
	return true


## Populates an organic, domain-warped multi-species dual-tier living grass ecosystem across `world_rect`.
## Set `clip_border = true` for clean studio/diorama edges; `false` for seamless tiled open-world chunks.
## Worker-thread safe when called from `ZoneStage.build()` off the scene tree.
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
	# Cache relevant habitat & water-deck providers ONCE for this rect (avoids 800k+ Array.duplicate & cross-zone queries!)
	var query_rect: Rect2 = world_rect.grow(48.0)
	_cached_providers.clear()
	_cached_deck_patches.clear()
	_zone_mask_provider = null
	for prov: Node in extra_habitat_providers:
		if not is_instance_valid(prov):
			continue
		if prov is ZoneStage and _zone_mask_provider == null:
			_zone_mask_provider = prov as ZoneStage
		elif prov.has_method("grass_habitat_at"):
			_cached_providers.append(prov)
	for patch: Node in Terrain.patches:
		if not is_instance_valid(patch):
			continue
		if patch.has_method("has_water_deck_at"):
			if not (patch is WaterField):
				var deck_overlap: bool = true
				if patch is WaterBridge:
					deck_overlap = (patch as WaterBridge).deck_world_bounds().intersects(query_rect)
				if deck_overlap:
					_cached_deck_patches.append(patch)
		if patch.has_method("grass_habitat_at") and not _cached_providers.has(patch) and patch != _zone_mask_provider:
			var overlap: bool = true
			if patch is WaterField:
				overlap = (patch as WaterField).bounds.intersects(query_rect)
			elif patch is RockyGround:
				overlap = (patch as RockyGround).bounds.intersects(query_rect)
			elif patch is GroundSurfaces:
				overlap = (patch as GroundSurfaces).bounds.intersects(query_rect)
			if overlap:
				_cached_providers.append(patch)
	if _surfaces != null:
		_surfaces.prepare_fast_queries()
	for prov: Node in _cached_providers:
		if prov is RockyGround:
			(prov as RockyGround).prepare_fast_queries()
		elif prov is GroundSurfaces:
			(prov as GroundSurfaces).prepare_fast_queries()
	_providers_cached = true
	_build_tufts(world_rect, seed_val, clip_border)
	_providers_cached = false
	_zone_mask_provider = null
	_cached_providers.clear()
	_cached_deck_patches.clear()


func _make_tier_material(shader: Shader, cols: int, rows: int, foot_y_local: float, tier_scale: float, with_actors: bool) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("field_origin", field_origin)
	mat.set_shader_parameter("field_size", FIELD_SIZE)
	mat.set_shader_parameter("deform_tex", _field_tex)
	mat.set_shader_parameter("atlas_cols", float(cols))
	mat.set_shader_parameter("atlas_rows", float(rows))
	mat.set_shader_parameter("foot_y_local", foot_y_local)
	mat.set_shader_parameter("tier_scale", tier_scale)
	if with_actors:
		mat.set_shader_parameter("actors", _actor_slots)
	return mat


func _init_field() -> void:
	_active.clear()
	_field_img = Image.create(FIELD_RES, FIELD_RES, false, Image.FORMAT_RGBA8)
	_field_img.fill(Color(0.5, 0.5, 0.0, 0.5))
	_field_tex = ImageTexture.create_from_image(_field_img)

	_grass_mat = _make_tier_material(LIT_SHADER, STD_COLS, STD_ROWS, STD_FOOT_OFFSET, 1.0, true)
	_tall_mat = _make_tier_material(LIT_SHADER, TALL_COLS, TALL_ROWS, TALL_FOOT_OFFSET, 1.55, true)
	_glow_mat = _make_tier_material(GLOW_SHADER, STD_COLS, STD_ROWS, STD_FOOT_OFFSET, 1.0, true)
	_tall_glow_mat = _make_tier_material(GLOW_SHADER, TALL_COLS, TALL_ROWS, TALL_FOOT_OFFSET, 1.55, true)

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

	var std_mesh: ArrayMesh = _get_std_mesh()
	var tall_mesh: ArrayMesh = _get_tall_mesh()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val + 77

	# Domain-warped organic ecological noise layers -> pre-baked 256x256 seamless C++ byte tables (1024x1024 px period,
	# ~10 ms total vs ~4500 ms of 2M GDScript FastNoiseLite.get_noise_2d() calls!).
	var warp_b: PackedByteArray = _bake_noise_bytes(seed_val + 907, 0.011)
	var dens_b: PackedByteArray = _bake_noise_bytes(seed_val + 11, 0.015)
	var tall_b: PackedByteArray = _bake_noise_bytes(seed_val + 577, 0.013)
	var flor_b: PackedByteArray = _bake_noise_bytes(seed_val + 313, 0.018)
	var spec_b: PackedByteArray = _bake_noise_bytes(seed_val + 743, 0.024)
	var soil_b: PackedByteArray = _bake_noise_bytes(seed_val + 1231, 0.010)
	var inv255: float = 1.0 / 255.0

	_floral_cells.clear()
	_grass_cells.clear()
	_grass_style.clear()
	_tall_cells.clear()
	_tall_tufts.clear()
	_tall_grid.clear()
	_removed_tall.clear()
	_cell_origin = Vector2i(floori(world_rect.position.x / 8.0) - 1, floori(world_rect.position.y / 8.0) - 1)
	_cell_w = maxi(1, ceili(world_rect.end.x / 8.0) - _cell_origin.x + 2)
	_cell_h = maxi(1, ceili(world_rect.end.y / 8.0) - _cell_origin.y + 2)
	var cell_total: int = _cell_w * _cell_h
	_cell_style.resize(cell_total)
	_cell_style.fill(0)
	_cell_tall.resize(cell_total)
	_cell_tall.fill(0)
	_cell_floral.resize(cell_total)
	_cell_floral.fill(0)
	_cell_grid_ready = true
	var rect_area: float = world_rect.size.x * world_rect.size.y
	_use_cell_dicts = rect_area <= 4000000.0
	tuft_count = 0
	std_tuft_count = 0
	tall_tuft_count = 0
	glow_tuft_count = 0

	var pad_left: float = 10.0 if clip_border else 2.0
	var pad_right: float = 10.0 if clip_border else 2.0
	var pad_top: float = 14.0 if clip_border else 2.0
	var pad_bottom: float = 2.0
	var spawn_rect: Rect2 = Rect2(
		world_rect.position + Vector2(pad_left, pad_top),
		world_rect.size - Vector2(pad_left + pad_right, pad_top + pad_bottom)
	)
	var min_band: int = floori(spawn_rect.position.y / BAND_HEIGHT) - 2
	var band_span: int = maxi(1, ceili(spawn_rect.end.y / BAND_HEIGHT) - min_band + 3)
	var std_bands: Array[BandBuf] = []
	var tall_bands: Array[BandBuf] = []
	var std_glow_bands: Array[BandBuf] = []
	var tall_glow_bands: Array[BandBuf] = []
	std_bands.resize(band_span)
	tall_bands.resize(band_span)
	std_glow_bands.resize(band_span)
	tall_glow_bands.resize(band_span)

	var meadow_rect: Rect2 = _custom_meadow_rect
	if meadow_rect.size == Vector2.ZERO:
		if world_rect.position.x < -192.0 and world_rect.end.x >= 192.0:
			meadow_rect = Rect2(-192.0, world_rect.position.y, 384.0, world_rect.size.y)
		else:
			meadow_rect = Rect2(world_rect.position, Vector2(minf(world_rect.size.x, 384.0), world_rect.size.y))

	# 2-tier organic Horst / cluster growth with multi-story layering (ground-cover + mid + waist-high tall belts!)
	# XL zones (>42M px², e.g. Suedkap) use slightly wider spacing (still >2x overlap on 20x24 px tufts) for fast streaming!
	var prof_on: bool = OS.get_environment("ZONE_PROFILE") == "1"
	var t_loop0: int = Time.get_ticks_usec() if prof_on else 0
	var is_xl: bool = rect_area > 42000000.0
	var step_x: float = 12.6 if is_xl else 10.4
	var step_y: float = 9.4 if is_xl else 7.8
	var y: float = spawn_rect.position.y
	while y <= spawn_rect.end.y:
		var row_shift: float = step_x * 0.5 if int(floorf(y / step_y)) % 2 == 1 else 0.0
		var x: float = spawn_rect.position.x + row_shift
		while x <= spawn_rect.end.x:
			var base_pos: Vector2 = Vector2(
				x + rng.randf_range(-4.6, 4.6),
				y + rng.randf_range(-3.4, 3.4)
			).round()
			if not spawn_rect.has_point(base_pos):
				x += step_x
				continue
			if _zone_mask_provider != null and not _zone_mask_provider.is_dry_tile_px(base_pos):
				x += step_x
				continue

			var hab_v: Vector3 = _query_habitat_vec(base_pos)
			var hab_dens: float = hab_v.x
			var hab_hscale: float = hab_v.y
			var hab_style_i: int = int(hab_v.z)
			if hab_dens <= 0.02 or hab_style_i == 0:
				x += step_x
				continue
			var hab_style: String = HAB_STYLE_NAMES[hab_style_i]

			# Domain warp coordinates so habitat pockets & tall-grass belts sweep organically like wild nature
			var b_wx: int = floori(base_pos.x * 0.25)
			var b_wy: int = floori(base_pos.y * 0.25)
			var wp: Vector2 = base_pos + Vector2(
				(float(warp_b[(b_wy & 255) * 256 + (b_wx & 255)]) * (2.0 / 255.0) - 1.0) * 28.0,
				(float(warp_b[((b_wy - 23) & 255) * 256 + ((b_wx + 43) & 255)]) * (2.0 / 255.0) - 1.0) * 28.0
			)
			var ni: int = (floori(wp.y * 0.25) & 255) * 256 + (floori(wp.x * 0.25) & 255)
			var d_n: float = float(dens_b[ni]) * inv255
			var keep_prob: float = lerpf(0.32, 0.98, smoothstep(0.25, 0.66, d_n)) * hab_dens
			if hab_style_i == 2 or hab_style_i == 3:
				keep_prob = maxf(keep_prob, hab_dens * 0.78)
			if rng.randf() > keep_prob:
				x += step_x
				continue

			var f_n: float = float(flor_b[ni]) * inv255
			var t_n: float = float(tall_b[ni]) * inv255
			var sp_n: float = float(spec_b[ni]) * inv255
			var soil_n: float = float(soil_b[ni]) * inv255

			# Compute tall-grass belt intensity (0..1) — natural waist-high wild meadow swathes, riparian reeds,
			# forest eagle-ferns, and coastal tall Strandhafer crests! Roll probability BEFORE `_tall_tip_clear`!
			var tall_prob: float = _tall_probability(base_pos, wp, meadow_rect, d_n, t_n, hab_style, hab_hscale)
			var anchor_tall: bool = (
				tall_prob > 0.02
				and hab_hscale >= 0.80
				and hab_style_i != 2
				and hab_style_i != 3
				and (not clip_border or base_pos.y >= world_rect.position.y + 32.0)
				and rng.randf() < tall_prob
				and _tall_tip_clear(base_pos, hab_style)
			)
			var anchor_kind: int = (
				_choose_tall_variant(base_pos, wp, meadow_rect, f_n, sp_n, soil_n, hab_style, rng)
				if anchor_tall
				else _choose_standard_variant(base_pos, wp, meadow_rect, d_n, f_n, t_n, sp_n, soil_n, hab_style, rng)
			)

			# Dense Horsts: tall-grass thickets, rich meadow pockets & floral drifts nestle 1-2 companions!
			var companions: int = 0
			if anchor_tall:
				companions = 2 if (d_n > 0.52 and rng.randf() < 0.62) else 1
			elif hab_style_i == 1:
				if d_n > 0.55 and rng.randf() < 0.72:
					companions = 2 if (d_n > 0.72 and rng.randf() < 0.45) else 1
				elif anchor_kind >= 16 and anchor_kind <= 23 and rng.randf() < 0.78:
					companions = 1
			elif (hab_style_i == 4 or hab_style_i == 5) and d_n > 0.52 and rng.randf() < 0.52:
				companions = 1
			elif (hab_style_i == 2 or hab_style_i == 3) and rng.randf() < 0.46:
				companions = 1
			elif hab_style_i == 6 and rng.randf() < 0.58:
				companions = 1
			elif hab_style_i == 7 and rng.randf() < 0.48:
				companions = 1

			for c_idx: int in companions + 1:
				var pos: Vector2 = base_pos
				var is_tall: bool = anchor_tall
				var kind: int = anchor_kind
				var local_hscale: float = hab_hscale
				var local_style_i: int = hab_style_i
				var local_style: String = hab_style
				if c_idx > 0:
					var ang: float = rng.randf() * TAU
					var dist: float = rng.randf_range(3.0, 6.2 if anchor_tall else 5.6)
					pos = (base_pos + Vector2(cos(ang) * dist, sin(ang) * dist * 0.76)).round()
					if not spawn_rect.has_point(pos):
						continue
					if _zone_mask_provider != null and not _zone_mask_provider.is_dry_tile_px(pos):
						continue
					var chab_v: Vector3 = _query_habitat_vec(pos)
					if chab_v.x <= 0.12 or int(chab_v.z) == 0:
						continue
					local_hscale = chab_v.y
					local_style_i = int(chab_v.z)
					local_style = HAB_STYLE_NAMES[local_style_i]
					if anchor_tall:
						# Multi-story Horst: pair tall grass with 1 fellow tall stalk or lush mid-grass under-skirt!
						var comp_can_tall: bool = (
							c_idx == 1
							and local_hscale >= 0.80
							and local_style_i != 2
							and local_style_i != 3
							and (not clip_border or pos.y >= world_rect.position.y + 32.0)
							and rng.randf() < (0.58 if local_style_i == 1 else 0.44)
							and _tall_tip_clear(pos, local_style)
						)
						if comp_can_tall:
							is_tall = true
							kind = _choose_tall_variant(pos, wp, meadow_rect, f_n, sp_n, soil_n, local_style, rng)
						else:
							is_tall = false
							kind = _choose_understory_companion(local_style, anchor_kind, sp_n, rng)
					else:
						is_tall = false
						kind = _choose_standard_companion(local_style, anchor_kind, sp_n, rng)

				# Near northern border of bounded patch, keep shorter silhouettes so tips never clip out of frame
				if clip_border and not is_tall and pos.y < world_rect.position.y + 21.0:
					if (kind >= 8 and kind <= 13) or kind >= 24:
						kind = rng.randi_range(0, 7)

				var flipped: bool = rng.randf() < 0.5
				var band_idx: int = floori(pos.y / BAND_HEIGHT)
				var tint_c: Color = _compute_tuft_tint(local_style, soil_n, is_tall, rng)
				var edge_flex: float = 0.72 if (clip_border and (pos.x < spawn_rect.position.x + 6.0 or pos.x > spawn_rect.end.x - 6.0)) else 1.0
				var total_v: int = TALL_COUNT if is_tall else STD_COUNT
				var h_min: float = 0.86 if is_tall else 0.84
				var h_max: float = 1.12 if is_tall else 1.14
				var flex_lo: float = 0.78 if is_tall else 0.68
				var flex_hi: float = 1.32 if is_tall else 1.38
				var kind_enc: float = float(kind + (total_v if flipped else 0))
				var phase_v: float = rng.randf()
				var flex_v: float = rng.randf_range(flex_lo, flex_hi) * edge_flex
				var hscale_v: float = clampf(rng.randf_range(h_min, h_max) * local_hscale, 0.55, 1.18)

				var gc_x: int = floori(pos.x * 0.125)
				var gc_y: int = floori(pos.y * 0.125)
				var st_id: int = STYLE_MEADOW
				if local_style_i == 7 or local_style_i == 8:
					st_id = STYLE_DUNE
				elif local_style_i == 6:
					st_id = STYLE_REED
				elif local_style_i == 4 or local_style_i == 5:
					st_id = STYLE_FOREST
				elif local_style_i == 2:
					st_id = STYLE_MOSS

				# Record rich 5-color floral micro-habitat cells so movement kicks up matching petals!
				var f_code: int = _floral_code_for(kind, is_tall)
				var lx: int = gc_x - _cell_origin.x
				var ly: int = gc_y - _cell_origin.y
				if lx >= 0 and lx < _cell_w and ly >= 0 and ly < _cell_h:
					var cidx: int = ly * _cell_w + lx
					_cell_style[cidx] = st_id
					if f_code > 0:
						_cell_floral[cidx] = f_code
				if _use_cell_dicts:
					var gc: Vector2i = Vector2i(gc_x, gc_y)
					_grass_cells[gc] = true
					_grass_style[gc] = st_id
					if f_code > 0:
						_floral_cells[gc] = f_code

				var bi: int = clampi(band_idx - min_band, 0, band_span - 1)
				var tall_id_f: float = -1.0
				if is_tall:
					var tall_id: int = _tall_tufts.size()
					tall_id_f = float(tall_id)
					var tref: TallTuftRef = TallTuftRef.new()
					tref.id = tall_id
					tref.pos = pos
					tref.style_id = st_id
					tref.floral_code = f_code
					_tall_tufts.append(tref)
					var gcell16: Vector2i = Vector2i(floori(pos.x * 0.0625), floori(pos.y * 0.0625))
					var gbucket: Array = _tall_grid.get_or_add(gcell16, []) as Array
					gbucket.append(tall_id)
					var tbuf: BandBuf = tall_bands[bi]
					if tbuf == null:
						tbuf = BandBuf.new()
						tall_bands[bi] = tbuf
					tbuf.push(pos.x, pos.y, kind_enc, phase_v, flex_v, hscale_v, tint_c, tall_id_f)
					tall_tuft_count += 1
					if lx >= 0 and lx < _cell_w and ly >= 0 and ly < _cell_h:
						var cidx_t: int = ly * _cell_w + lx
						var cur_b: int = _cell_tall[cidx_t]
						_cell_tall[cidx_t] = mini(255, maxi(cur_b, 173) + (46 if cur_b > 0 else 0))
						for ndy: int in range(-1, 2):
							var ny: int = ly + ndy
							if ny < 0 or ny >= _cell_h:
								continue
							var nrow: int = ny * _cell_w
							for ndx: int in range(-1, 2):
								if ndx == 0 and ndy == 0:
									continue
								var nx: int = lx + ndx
								if nx >= 0 and nx < _cell_w and _cell_tall[nrow + nx] < 89:
									_cell_tall[nrow + nx] = maxi(_cell_tall[nrow + nx], 82)
					if _use_cell_dicts:
						var gc_d: Vector2i = Vector2i(gc_x, gc_y)
						var cur_t: float = float(_tall_cells.get(gc_d, 0.0))
						_tall_cells[gc_d] = minf(1.0, maxf(cur_t, 0.68) + (0.18 if cur_t > 0.0 else 0.0))
						for ndy: int in range(-1, 2):
							for ndx: int in range(-1, 2):
								if ndx == 0 and ndy == 0:
									continue
								var ngc: Vector2i = gc_d + Vector2i(ndx, ndy)
								if float(_tall_cells.get(ngc, 0.0)) < 0.35:
									_tall_cells[ngc] = maxf(float(_tall_cells.get(ngc, 0.0)), 0.32)
				else:
					var sbuf: BandBuf = std_bands[bi]
					if sbuf == null:
						sbuf = BandBuf.new()
						std_bands[bi] = sbuf
					sbuf.push(pos.x, pos.y, kind_enc, phase_v, flex_v, hscale_v, tint_c, -1.0)
					std_tuft_count += 1
				tuft_count += 1

				# Selective unlit night-glow pass: blossoms, plumes, pin-shrooms, moon-grass & sparse dew blades
				if _has_night_glow(kind, is_tall, rng):
					if is_tall:
						var tgbuf: BandBuf = tall_glow_bands[bi]
						if tgbuf == null:
							tgbuf = BandBuf.new()
							tall_glow_bands[bi] = tgbuf
						tgbuf.push(pos.x, pos.y, kind_enc, phase_v, flex_v, hscale_v, tint_c, tall_id_f)
					else:
						var sgbuf: BandBuf = std_glow_bands[bi]
						if sgbuf == null:
							sgbuf = BandBuf.new()
							std_glow_bands[bi] = sgbuf
						sgbuf.push(pos.x, pos.y, kind_enc, phase_v, flex_v, hscale_v, tint_c, -1.0)
					glow_tuft_count += 1
			x += step_x
		y += step_y

	var t_bands0: int = Time.get_ticks_usec() if prof_on else 0
	_populate_dual_bands(_bands_root, std_bands, tall_bands, min_band, std_mesh, tall_mesh, ATLAS_TEX, TALL_ATLAS_TEX, _grass_mat, _tall_mat, false)
	_populate_dual_bands(_glow_root, std_glow_bands, tall_glow_bands, min_band, std_mesh, tall_mesh, GLOW_TEX, TALL_GLOW_TEX, _glow_mat, _tall_glow_mat, true)
	if prof_on:
		var t_end: int = Time.get_ticks_usec()
		print("GRASS_PROFILE tufts=%d (std=%d tall=%d glow=%d) loop=%.1f ms bands=%.1f ms" % [
			tuft_count, std_tuft_count, tall_tuft_count, glow_tuft_count,
			float(t_bands0 - t_loop0) * 0.001, float(t_end - t_bands0) * 0.001,
		])


static func _bake_noise_bytes(seed_i: int, freq: float) -> PackedByteArray:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = seed_i
	n.frequency = freq * 4.0
	n.fractal_octaves = 2
	var img: Image = n.get_seamless_image(256, 256, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


const TALL_FLORAL_LUT: PackedByteArray = [
	0, 0, 0, 0, 0, 0, 0, 0,
	1, 1, 3, 5, 4, 1, 0, 0,
	0, 0, 0, 4, 0, 0, 0, 0,
]
const STD_FLORAL_LUT: PackedByteArray = [
	0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0,
	1, 1, 4, 2, 5, 3, 1, 4,
	0, 0, 0, 0, 0, 5, 0, 0,
	0, 0, 0, 0, 3, 0, 0, 0,
]
const TALL_GLOW_LUT: PackedFloat32Array = [
	0.36, 0.36, 0.36, 0.36, 0.65, 0.65, 1.0, 0.36,
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.36, 1.0,
	0.36, 0.65, 0.65, 1.0, 0.36, 0.36, 0.65, 0.65,
]
const STD_GLOW_LUT: PackedFloat32Array = [
	0.30, 0.0, 0.30, 0.0, 0.30, 0.30, 0.30, 0.0,
	0.30, 0.30, 0.30, 0.0, 0.30, 0.30, 0.0, 0.0,
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
	0.0, 0.0, 0.72, 0.0, 0.0, 0.0, 0.72, 0.0,
	0.72, 0.72, 0.72, 0.30, 0.72, 0.0, 0.0, 0.0,
]


func _tall_probability(pos: Vector2, warped_pos: Vector2, meadow_rect: Rect2, d_n: float, t_n: float, hab_style: String, hab_hscale: float) -> float:
	if hab_style == "bank_reed":
		return 0.46 if d_n > 0.30 else 0.28
	if hab_style == "dune_oat":
		return 0.34 if t_n > 0.46 else 0.14
	if hab_style == "coastal_edge":
		return 0.16 if t_n > 0.56 else 0.0
	if hab_style == "forest" or hab_style == "moss_edge":
		# Tall woodland eagle-ferns & horsetails in rich damp pockets & canopy drip lines
		if hab_hscale >= 1.04:
			return 0.32 if t_n > 0.44 else 0.14
		return 0.22 if (d_n > 0.52 and t_n > 0.52) else 0.05

	# Open Meadow: sweeping organic waist-high Hohes-Gras belts + lush wild meadow pockets!
	var in_meadow: bool = meadow_rect.grow(16.0).has_point(pos)
	var nx: float = (warped_pos.x - meadow_rect.position.x) / maxf(meadow_rect.size.x, 1.0)
	var ny: float = (warped_pos.y - meadow_rect.position.y) / maxf(meadow_rect.size.y, 1.0)

	# On Square 1 / Studio Meadow: crisp ecological contrast so serene short clover/flower clearings
	# frame unmistakably dense, sweeping waist-high Hohes-Gras (tall grass) belts!
	var belt_bias: float = 0.0
	if in_meadow:
		var sw_tall: float = clampf((ny - 0.46) * 2.4 * (1.0 - absf(nx - 0.44) * 1.50), 0.0, 1.0)
		var ne_tall: float = clampf((nx - 0.54) * 2.4 * (1.0 - ny * 1.45), 0.0, 1.0)
		var nw_floral_clear: float = clampf((1.0 - nx * 1.55) * (1.0 - ny * 1.50), 0.0, 1.0)
		var center_calm: float = clampf(1.0 - Vector2((nx - 0.34) * 3.4, (ny - 0.42) * 3.8).length(), 0.0, 1.0)
		belt_bias = maxf(sw_tall * 0.56, ne_tall * 0.48) - nw_floral_clear * 0.36 - center_calm * 0.38

	var raw_belt: float = smoothstep(0.53, 0.76, t_n) * 0.62 + belt_bias
	if hab_hscale >= 1.05:
		raw_belt += 0.16 ## Canopy drip line nourishes tall meadow plumes & ferns
	if d_n < 0.44:
		raw_belt *= 0.12 ## Preserve calm short moss/clover clearings for visual rhythm!
	return clampf(raw_belt, 0.0, 0.78)


func _compute_tuft_tint(local_style: String, soil_n: float, is_tall: bool, rng: RandomNumberGenerator) -> Color:
	var tint_v: float = rng.randf_range(0.92, 1.07)
	# Subtle world-space botanical micro-climate shift (cool moist emerald hollows vs warm sunlit crests!)
	var soil_shift: float = (soil_n - 0.5) * 0.09
	var warm_bias: float = rng.randf_range(-0.025, 0.03) + soil_shift
	var r_c: float = clampf(tint_v + warm_bias, 0.84, 1.12)
	var g_c: float = clampf(tint_v + soil_shift * 0.25, 0.86, 1.10)
	var b_c: float = clampf(tint_v - warm_bias * 0.65, 0.84, 1.10)
	if is_tall:
		# Slightly richer saturation & grounding on tall wild horsts
		r_c *= 0.99
		g_c *= 1.01
	var tint_c: Color = Color(r_c, g_c, b_c, 1.0)
	if local_style == "forest" or local_style == "moss_edge":
		tint_c = Color(tint_c.r * 0.85, tint_c.g * 0.92, tint_c.b * 0.96, 1.0)
	elif local_style == "bank_reed":
		tint_c = Color(tint_c.r * 0.88, tint_c.g * 0.99, tint_c.b * 0.96, 1.0)
	elif local_style == "dune_oat":
		tint_c = Color(tint_c.r * 1.02, tint_c.g * 0.99, tint_c.b * 0.95, 0.50)
	elif local_style == "coastal_edge":
		tint_c = Color(tint_c.r * 0.98, tint_c.g * 0.99, tint_c.b * 0.96, 0.68)
	return tint_c


func _floral_code_for(kind: int, is_tall: bool) -> int:
	if is_tall:
		return TALL_FLORAL_LUT[kind] if (kind >= 0 and kind < TALL_COUNT) else 0
	return STD_FLORAL_LUT[kind] if (kind >= 0 and kind < STD_COUNT) else 0


func _has_night_glow(kind: int, is_tall: bool, rng: RandomNumberGenerator) -> bool:
	var p: float = 0.0
	if is_tall:
		p = TALL_GLOW_LUT[kind] if (kind >= 0 and kind < TALL_COUNT) else 0.0
	else:
		p = STD_GLOW_LUT[kind] if (kind >= 0 and kind < STD_COUNT) else 0.0
	if p >= 1.0:
		return true
	if p <= 0.0:
		return false
	return rng.randf() < p


func _populate_dual_bands(
	parent: Node2D,
	std_bands: Array[BandBuf],
	tall_bands: Array[BandBuf],
	min_band: int,
	std_mesh: ArrayMesh,
	tall_mesh: ArrayMesh,
	std_tex: Texture2D,
	tall_tex: Texture2D,
	std_mat: ShaderMaterial,
	tall_mat: ShaderMaterial,
	is_glow: bool = false
) -> void:
	for bi: int in std_bands.size():
		var std_buf: BandBuf = std_bands[bi]
		var tall_buf: BandBuf = tall_bands[bi]
		var std_cnt: int = (std_buf.size / BAND_STRIDE) if std_buf != null else 0
		var tall_cnt: int = (tall_buf.size / BAND_STRIDE) if tall_buf != null else 0
		if std_cnt <= 0 and tall_cnt <= 0:
			continue
		var bkey: int = min_band + bi
		var band_node: Node2D = Node2D.new()
		band_node.position = Vector2(0.0, (float(bkey) + 0.5) * BAND_HEIGHT)
		parent.add_child(band_node)

		if std_cnt > 0:
			_add_band_mm(band_node, std_buf.data, std_cnt, std_mesh, std_tex, std_mat, STD_FOOT_OFFSET, float(STD_COUNT * 2), false, is_glow)
		if tall_cnt > 0:
			_add_band_mm(band_node, tall_buf.data, tall_cnt, tall_mesh, tall_tex, tall_mat, TALL_FOOT_OFFSET, float(TALL_COUNT * 2), true, is_glow)


func _add_band_mm(
	band_node: Node2D,
	data: PackedFloat32Array,
	count: int,
	mesh: ArrayMesh,
	tex: Texture2D,
	mat: ShaderMaterial,
	foot_offset: float,
	kind_div: float,
	is_tall_tier: bool = false,
	is_glow: bool = false
) -> void:
	if count <= 0:
		return
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
	mm.instance_count = count

	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(count * 16)
	var inv_kind_div: float = 1.0 / kind_div
	var y_off: float = band_node.position.y + foot_offset
	var tall_total: int = _tall_tufts.size()
	for i: int in count:
		var off: int = i * BAND_STRIDE
		var lx: float = data[off]
		var ly: float = data[off + 1] - y_off
		var kr: float = data[off + 2] * inv_kind_div
		var ph: float = data[off + 3]
		var fl: float = data[off + 4]
		var hs: float = data[off + 5]
		var b: int = i * 16
		buf[b] = 1.0
		buf[b + 3] = lx
		buf[b + 5] = 1.0
		buf[b + 7] = ly
		buf[b + 8] = data[off + 6]
		buf[b + 9] = data[off + 7]
		buf[b + 10] = data[off + 8]
		buf[b + 11] = data[off + 9]
		buf[b + 12] = kr
		buf[b + 13] = ph
		buf[b + 14] = fl
		buf[b + 15] = hs
		if is_tall_tier:
			var tid: int = int(data[off + 10])
			if tid >= 0 and tid < tall_total:
				var tref: TallTuftRef = _tall_tufts[tid]
				var xf: Transform2D = Transform2D(0.0, Vector2(lx, ly))
				var cdata: Color = Color(kr, ph, fl, hs)
				if is_glow:
					tref.mm_glow = mm
					tref.idx_glow = i
					tref.orig_transform_glow = xf
					tref.orig_custom_glow = cdata
				else:
					tref.mm_lit = mm
					tref.idx_lit = i
					tref.orig_transform_lit = xf
					tref.orig_custom_lit = cdata
	mm.buffer = buf
	mm_node.multimesh = mm
	band_node.add_child(mm_node)


func _choose_tall_variant(
	pos: Vector2,
	warped_pos: Vector2,
	meadow_rect: Rect2,
	f_n: float,
	sp_n: float,
	soil_n: float,
	hab_style: String,
	rng: RandomNumberGenerator
) -> int:
	if hab_style == "bank_reed":
		var rr: float = rng.randf()
		if rr < 0.34:
			return 16 ## tall arching brook reed clump
		if rr < 0.62:
			return 17 ## iconic velvet-brown cattails (Rohrkolben!)
		if rr < 0.84:
			return 18 ## plumed common reed (Schilfrohr)
		return 19 ## golden yellow flag iris & bank sedge

	if hab_style == "dune_oat":
		return 22 if rng.randf() < 0.86 else 23 ## tall coastal Strandhafer + rare feather-grass

	if hab_style == "coastal_edge":
		return 22 if rng.randf() < 0.50 else (23 if rng.randf() < 0.50 else rng.randi_range(0, 2))

	if hab_style == "forest" or hab_style == "moss_edge":
		var rf: float = rng.randf()
		if rf < 0.56:
			return 20 ## tall tiered woodland eagle-fern
		if rf < 0.88:
			return 21 ## woodland shade sedge & horsetail
		return 15 ## rare dew-pearl moon-grass in deep damp shade

	# Open Meadow Tall Grass Belts: rich botanical mix of lush tall grass, seed plumes & flowering stalks!
	var in_meadow: bool = meadow_rect.grow(16.0).has_point(pos)
	var nx: float = (warped_pos.x - meadow_rect.position.x) / maxf(meadow_rect.size.x, 1.0)
	var ny: float = (warped_pos.y - meadow_rect.position.y) / maxf(meadow_rect.size.y, 1.0)
	var se_shade: float = clampf((nx - 0.55) * 2.2 * (ny - 0.48) * 2.2, 0.0, 1.0) if in_meadow else 0.0
	if se_shade > 0.25 and rng.randf() < 0.52 * se_shade:
		return 20 if rng.randf() < 0.55 else (15 if rng.randf() < 0.55 else 21)

	# Flowering wild-meadow tall accents clustered organically by `f_n` & `sp_n`
	var bloom_roll: float = rng.randf()
	if f_n > 0.54 and bloom_roll < clampf(0.18 + (f_n - 0.54) * 0.95, 0.0, 0.48):
		if sp_n < 0.22:
			return 9 if rng.randf() < 0.58 else 13 ## oxeye daisies & cow-parsley umbels
		if sp_n < 0.42:
			return 8 if rng.randf() < 0.55 else 13 ## meadowsweet & cow-parsley
		if sp_n < 0.62:
			return 10 if rng.randf() < 0.60 else 11 ## wild sage spires & clover-rose knapweed
		if sp_n < 0.82:
			return 12 if rng.randf() < 0.55 else 14 ## goldenrod & russet red-sorrel
		return 15 if rng.randf() < 0.40 else 9

	# Dry sun-warmed meadow ridges favor golden wild oats, silver feather-grass & brome
	var r: float = rng.randf()
	if soil_n > 0.60 and r < 0.44:
		var warm_pool: Array[int] = [4, 5, 6, 7, 14, 23]
		return warm_pool[rng.randi() % warm_pool.size()]

	# Core waist-high wild meadow grass horsts (0..3) + swaying panicles (4..7)
	if r < 0.64:
		return rng.randi_range(0, 3)
	if r < 0.94:
		return rng.randi_range(4, 7)
	return 15 ## occasional dew-pearl moon-grass


func _choose_standard_variant(
	pos: Vector2,
	warped_pos: Vector2,
	meadow_rect: Rect2,
	d_n: float,
	f_n: float,
	t_n: float,
	sp_n: float,
	soil_n: float,
	hab_style: String,
	rng: RandomNumberGenerator
) -> int:
	# Habitat-specific botanical palettes:
	if hab_style == "stone_seam":
		var rs: float = rng.randf()
		if rs < 0.30:
			return 29 ## stone-crevice wild thyme hugging stone bevels
		if rs < 0.58:
			return 14 ## plush velvety moss pillow
		if rs < 0.80:
			return 15 ## delicate low woodland clover
		if rs < 0.92:
			return 39 if soil_n > 0.52 else 7 ## wiry sheep's fescue or soft baby shoots
		return 3 ## compact velvety turf

	if hab_style == "path_edge":
		var rp: float = rng.randf()
		if rp < 0.22:
			return 15 if rng.randf() < 0.50 else (29 if rng.randf() < 0.55 else 14)
		if rp < 0.34:
			return 11 if rng.randf() < 0.55 else 39 ## roadside plantain & dry sheep's fescue!
		if rp < 0.46 and f_n > 0.54:
			var edge_flowers: Array[int] = [17, 18, 19, 20, 23]
			return edge_flowers[rng.randi() % edge_flowers.size()]
		if rp < 0.56 and t_n > 0.52:
			return 34 if rng.randf() < 0.50 else (37 if rng.randf() < 0.50 else 32)
		return rng.randi_range(0, 7)

	if hab_style == "forest" or hab_style == "moss_edge":
		var rf: float = rng.randf()
		if rf < 0.28:
			return 24 if rng.randf() < 0.52 else (25 if rng.randf() < 0.65 else 26) ## lady-fern, bracken & fiddleheads!
		if rf < 0.48:
			return 28 if (hab_style == "forest" and rng.randf() < 0.52) else (27 if rng.randf() < 0.52 else 31) ## fallen-leaf sedge, bilberry, hart's-tongue
		if rf < 0.72:
			return 30 if rng.randf() < 0.28 else (14 if rng.randf() < 0.58 else 15) ## pin-shroom moss, velvet moss, clover
		if rf < 0.88:
			return 12 if rng.randf() < 0.60 else 5
		return 3 if rng.randf() < 0.55 else 7

	if hab_style == "bank_reed":
		var rr: float = rng.randf()
		if rr < 0.42:
			return 35 ## lush riparian brook sedge
		if rr < 0.64:
			return 36 ## brook-edge rush & lilac water-mint
		if rr < 0.80:
			return 31 if rng.randf() < 0.55 else 12 ## hart's-tongue & cool moisture sedge
		if rr < 0.92:
			return 8 if rng.randf() < 0.55 else 32
		return 14

	if hab_style == "dune_oat" or hab_style == "coastal_edge":
		var rd: float = rng.randf()
		if hab_style == "dune_oat":
			if rd < 0.68:
				return 38 ## native coastal Strandhafer!
			if rd < 0.86:
				return 32 if rng.randf() < 0.55 else 39
			return [8, 9, 10][rng.randi() % 3]
		if rd < 0.42:
			return 38
		if rd < 0.66:
			return 39 if rng.randf() < 0.55 else 13
		return [0, 1, 2, 8, 9][rng.randi() % 5]

	# Meadow Square (Square 1) & open grass margins:
	var in_meadow: bool = meadow_rect.grow(16.0).has_point(pos)
	var nx: float = (warped_pos.x - meadow_rect.position.x) / maxf(meadow_rect.size.x, 1.0)
	var ny: float = (warped_pos.y - meadow_rect.position.y) / maxf(meadow_rect.size.y, 1.0)

	# Sunlit wildflower drifts (NW Square 1 + organic species-clustered pockets across all meadows!)
	var nw_floral: float = clampf((1.0 - nx * 1.38) * (1.0 - ny * 1.28), 0.0, 1.0) if in_meadow else 0.0
	if nw_floral > 0.14 or f_n > 0.65:
		var flower_chance: float = clampf(nw_floral * 0.70 + maxf(0.0, f_n - 0.62) * 0.98, 0.0, 0.80)
		if rng.randf() < flower_chance:
			# Group wildflower species organically by `sp_n` so drifts look genuinely botanical!
			if nw_floral > 0.38 and sp_n < 0.42:
				return 16 if rng.randf() < 0.52 else (17 if rng.randf() < 0.62 else 22) ## chamomile, daisies & yarrow
			if sp_n < 0.24:
				return 16 if rng.randf() < 0.55 else 17 ## white chamomile & daisies
			if sp_n < 0.44:
				return 18 if rng.randf() < 0.62 else 23 ## sunlit buttercups & dandelions!
			if sp_n < 0.64:
				return 19 if rng.randf() < 0.65 else 21 ## forget-me-nots & nodding harebells
			if sp_n < 0.82:
				return 20 if rng.randf() < 0.60 else 21 ## dusty-rose clover & harebells
			return 22 if rng.randf() < 0.52 else 23 ## white yarrow & dandelion puffballs

	# South-East shaded woodland nook on Square 1
	var se_shade: float = clampf((nx - 0.50) * 2.1 * (ny - 0.44) * 2.1, 0.0, 1.0) if in_meadow else 0.0
	if se_shade > 0.15:
		var r_se: float = rng.randf()
		if r_se < 0.30 * se_shade:
			return 24 if rng.randf() < 0.45 else (25 if rng.randf() < 0.55 else 26)
		if r_se < 0.50 * se_shade:
			return 30 if rng.randf() < 0.32 else (27 if rng.randf() < 0.50 else 14)
		if r_se < 0.74 * se_shade:
			return 12 if rng.randf() < 0.65 else 31

	# Serene mossy pillows, clover mats & baby shoots framing natural clearings
	var r: float = rng.randf()
	if d_n < 0.42 and r < 0.38:
		if rng.randf() < 0.38:
			return 14
		if rng.randf() < 0.58:
			return 15
		return 7 if rng.randf() < 0.55 else 3

	# Sweeping mid-height sedges, broadleaf plantain & delicate meadow seed plumes
	if t_n > 0.48 and r < 0.46:
		var p_roll: float = rng.randf()
		if p_roll < 0.12:
			return 32 ## nodding wild oats
		if p_roll < 0.21:
			return 33 ## foxtail / timothy spikes
		if p_roll < 0.29:
			return 34 ## quaking grass
		if p_roll < 0.36:
			return 37 ## rustic red sorrel
		if p_roll < 0.46:
			return 11 ## broadleaf ribwort plantain
		if soil_n > 0.58 and p_roll < 0.60:
			return 13 if rng.randf() < 0.65 else 39 ## warm olive meadow grass
		return rng.randi_range(8, 13)

	# Core multi-blade lush grass tufts (0..7)
	return rng.randi_range(0, 7)


func _choose_understory_companion(local_style: String, anchor_tall_kind: int, sp_n: float, rng: RandomNumberGenerator) -> int:
	if local_style == "bank_reed":
		return 35 if rng.randf() < 0.55 else (36 if rng.randf() < 0.55 else 31)
	if local_style == "dune_oat" or local_style == "coastal_edge":
		return 38 if rng.randf() < 0.72 else 39
	if local_style == "forest" or local_style == "moss_edge":
		return 24 if rng.randf() < 0.34 else (25 if rng.randf() < 0.45 else (14 if rng.randf() < 0.55 else 12))
	# Harmonize tall meadow companion understory with its tall horst
	if anchor_tall_kind in [8, 9, 13]:
		return 16 if rng.randf() < 0.38 else (17 if rng.randf() < 0.45 else rng.randi_range(0, 7))
	if anchor_tall_kind in [10, 11]:
		return 20 if (sp_n > 0.5 and rng.randf() < 0.42) else (21 if rng.randf() < 0.38 else rng.randi_range(0, 7))
	if anchor_tall_kind == 12:
		return 18 if rng.randf() < 0.42 else rng.randi_range(0, 7)
	if anchor_tall_kind in [4, 5, 6, 7, 14]:
		return 13 if rng.randf() < 0.35 else (32 if rng.randf() < 0.25 else rng.randi_range(0, 7))
	return rng.randi_range(0, 11)


func _choose_standard_companion(local_style: String, anchor_kind: int, sp_n: float, rng: RandomNumberGenerator) -> int:
	if local_style == "bank_reed":
		return 35 if rng.randf() < 0.58 else (36 if rng.randf() < 0.45 else rng.randi_range(0, 7))
	if local_style == "dune_oat":
		return 38 if rng.randf() < 0.65 else (32 if rng.randf() < 0.45 else 39)
	if anchor_kind >= 16 and anchor_kind <= 23:
		if rng.randf() < 0.52:
			return anchor_kind
		if anchor_kind in [16, 17, 22]:
			return 17 if rng.randf() < 0.6 else 16
		if anchor_kind in [18, 23]:
			return 18 if rng.randf() < 0.65 else 23
		if anchor_kind in [19, 21]:
			return 19 if rng.randf() < 0.6 else 21
		return 20 if sp_n > 0.45 else 15
	if anchor_kind >= 24 and anchor_kind <= 31:
		return 14 if rng.randf() < 0.42 else (15 if rng.randf() < 0.45 else (28 if local_style == "forest" else 5))
	if local_style == "stone_seam":
		return 29 if rng.randf() < 0.38 else (14 if rng.randf() < 0.52 else (15 if rng.randf() < 0.6 else 7))
	if anchor_kind >= 8 and anchor_kind <= 13:
		return rng.randi_range(0, 7) if rng.randf() < 0.66 else anchor_kind
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


## Returns local tall-grass density/height factor (0.0 = short/none, up to 1.0 = dense waist-high tall grass).
func tallness_at(world_pos: Vector2) -> float:
	if _bounds.size != Vector2.ZERO and not _bounds.grow(12.0).has_point(world_pos):
		return 0.0
	if _cell_grid_ready:
		if tall_tuft_count <= 0:
			return 0.0
		var lx: int = floori(world_pos.x * 0.125) - _cell_origin.x
		var ly: int = floori(world_pos.y * 0.125) - _cell_origin.y
		var best: float = 0.0
		if lx >= 0 and lx < _cell_w and ly >= 0 and ly < _cell_h:
			best = float(_cell_tall[ly * _cell_w + lx]) * (1.0 / 255.0)
			if best >= 0.85:
				return best
		for dy: int in range(-1, 2):
			var ny: int = ly + dy
			if ny < 0 or ny >= _cell_h:
				continue
			var nrow: int = ny * _cell_w
			for dx: int in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx: int = lx + dx
				if nx >= 0 and nx < _cell_w:
					var v: float = float(_cell_tall[nrow + nx]) * (1.0 / 255.0)
					if v > best:
						best = v * 0.85
		return clampf(best, 0.0, 1.0)
	if _tall_cells.is_empty():
		return 0.0
	var c0: Vector2i = Vector2i((world_pos / 8.0).floor())
	var best_d: float = float(_tall_cells.get(c0, 0.0))
	if best_d >= 0.85:
		return best_d
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var v: float = float(_tall_cells.get(c0 + Vector2i(dx, dy), 0.0))
			if v > best_d:
				best_d = v * 0.85
	return clampf(best_d, 0.0, 1.0)


## Convenience query: true when `world_pos` sits inside genuine knee/waist-high tall grass.
func is_tall_grass_at(world_pos: Vector2) -> bool:
	return tallness_at(world_pos) >= 0.45


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
		_field_img.fill(neutral)
		_active.clear()
	else:
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

		_remove_buf.clear()
		for wc_v: Variant in _active:
			var wc: Vector2i = wc_v as Vector2i
			if not _cell_in_window(wc):
				_remove_buf.append(wc)
		for rem: Vector2i in _remove_buf:
			_active.erase(rem)

	for mat: ShaderMaterial in [_grass_mat, _tall_mat, _glow_mat, _tall_glow_mat, _trail_mat]:
		if mat != null:
			mat.set_shader_parameter("field_origin", field_origin)
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

	# 1. Players (full movement fidelity: L/R boot cadence, tall-grass curtain, shadow step burst, sword slash gust)
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

		# Shadow Step burst (departure & arrival radial ring — strictly gated to actual grass!)
		var step_t: float = player._step_t
		var prev_step: float = float(_prev_step_t.get(id, -1.0))
		_prev_step_t[id] = step_t
		if step_t >= 0.0 and prev_step < 0.0:
			if covers_point(player._step_from, 28.0):
				stamp_burst(player._step_from, 26.0, 1.0, 7.8)
				if _has_grass_near(player._step_from):
					_spawn_motes(player._step_from, 8, 48.0, true)
		elif prev_step >= 0.0 and prev_step < Player.STEP_GONE and step_t >= Player.STEP_GONE:
			if covers_point(pos, 28.0):
				stamp_burst(pos, 28.0, 1.0, 8.2)
				if _has_grass_near(pos):
					_spawn_motes(pos, 9, 56.0, true)

		# Sword Slash directional gust (blade bending only; contextual particles are owned by `SlashWorldFx`)
		var swinging: bool = player.attack != null and player.attack.is_swinging()
		var was_swinging: bool = bool(_prev_swing.get(id, false))
		_prev_swing[id] = swinging
		if swinging and not was_swinging and covers_point(pos, 38.0):
			var aim: Vector2 = player.attack.aim_dir
			if aim.length_squared() > 0.01:
				var slash_tall: float = tallness_at(pos + aim.normalized() * 18.0)
				stamp_slash(pos, aim.normalized(), 34.0 + 6.0 * slash_tall, 0.72 + 0.22 * slash_tall)

		if not _bounds.grow(24.0).has_point(pos):
			continue

		if player.air_height > 2.5:
			continue

		var dist: float = prev.distance_to(pos)
		if dist > 96.0:
			continue

		var tall_k: float = tallness_at(pos)
		if dist < 0.35:
			_stamp_standing(pos, 8.5 + 3.0 * tall_k, 0.50 + 0.14 * tall_k)
		else:
			var speed: float = dist / safe_dt
			var sneaking: bool = player.stealth != null and player.stealth.sneaking
			var sprinting: bool = player.sprinting or speed > 96.0
			var crush_amt: float = (0.44 if sneaking else (0.98 if sprinting else 0.74)) * (1.0 + 0.12 * tall_k)
			var hold_sec: float = (1.05 if sneaking else (2.5 if sprinting else 1.65)) * (1.0 + 0.32 * tall_k)
			var recover_sec: float = (4.4 if sneaking else (8.0 if sprinting else 6.0)) * (1.0 + 0.38 * tall_k)
			var radius: float = (10.5 if sneaking else (14.5 if sprinting else 12.2)) * (1.0 + 0.22 * tall_k)
			var wobble: float = (0.35 if sneaking else (1.0 if sprinting else 0.65)) * (1.0 + 0.28 * tall_k)

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

			var touched: bool = stamp_segment(prev + foot_off, pos + foot_off, radius, clampf(crush_amt, 0.0, 1.0), hold_sec, recover_sec, wobble)
			if touched and _has_grass_near(pos):
				_play_rustle(pos, sneaking, sprinting, tall_k)
				if _mote_wait <= 0.0 and (sprinting or speed > 58.0 or (tall_k >= 0.45 and speed > 36.0)):
					_mote_wait = 0.11 if sprinting else (0.19 if tall_k >= 0.45 else 0.25)
					var m_cnt: int = (4 if tall_k >= 0.45 else 3) if sprinting else (3 if tall_k >= 0.45 else 2)
					_spawn_motes(pos, m_cnt, 36.0 if sprinting else 22.0, false)

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

	# Zero unused contact shadow & parting slots and upload to BOTH lit & night-glow materials (keeps glow synced!)
	while slot_idx < 4:
		_actor_slots[slot_idx] = Vector4.ZERO
		slot_idx += 1
	for mat: ShaderMaterial in [_grass_mat, _tall_mat, _glow_mat, _tall_glow_mat]:
		if mat != null:
			mat.set_shader_parameter("actors", _actor_slots)


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
	var tall_k: float = tallness_at(pos)
	if dist < 0.35:
		_stamp_standing(pos, radius * (0.72 + 0.20 * tall_k), 0.38 * weight)
	else:
		var speed: float = dist / safe_dt
		var boost: float = clampf(speed / 90.0, 0.45, 1.25)
		stamp_segment(prev, pos, radius * (1.0 + 0.18 * tall_k), clampf(0.62 * weight * boost, 0.25, 0.92), 1.1 + 0.4 * tall_k, 4.8 + 1.8 * tall_k, 0.55 * weight)
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
	if not covers_point(world_pos, 36.0):
		return
	var on_grass: bool = _has_grass_near(world_pos)
	if kind == "pivot" and dir.length_squared() > 0.01:
		stamp_slash(world_pos, -dir.normalized(), radius * 1.25, crush_amt)
		stamp_burst(world_pos, radius * 0.85, crush_amt, wobble_amt)
		if on_grass:
			_spawn_motes(world_pos, 6, 42.0, true)
	elif kind == "land":
		stamp_burst(world_pos, radius, crush_amt, wobble_amt)
		if on_grass:
			_spawn_motes(world_pos, 8, 48.0, true)
	elif kind == "surge":
		stamp_burst(world_pos, radius * 0.8, crush_amt * 0.85, wobble_amt)
		if on_grass:
			_spawn_motes(world_pos, 4, 32.0, false)


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


## Checks whether this LivingGrass patch's world rectangle covers `pos`.
func covers_point(pos: Vector2, margin: float = 0.0) -> bool:
	return _bounds.size != Vector2.ZERO and _bounds.grow(margin).has_point(pos)


## Public check: true only when `pos` lies inside this patch AND real grass tufts exist within 12 px.
func has_grass_near(pos: Vector2) -> bool:
	return _has_grass_near(pos)


## Returns the botanical habitat style (`STYLE_NONE` if no tufts exist near `pos`).
func grass_style_at(pos: Vector2) -> int:
	if _bounds.size != Vector2.ZERO and not _bounds.grow(12.0).has_point(pos):
		return STYLE_NONE
	if _cell_grid_ready:
		if tuft_count <= 0:
			return STYLE_MEADOW if _bounds.size == Vector2.ZERO else STYLE_NONE
		var lx: int = floori(pos.x * 0.125) - _cell_origin.x
		var ly: int = floori(pos.y * 0.125) - _cell_origin.y
		if lx >= 0 and lx < _cell_w and ly >= 0 and ly < _cell_h:
			var s0: int = _cell_style[ly * _cell_w + lx]
			if s0 != STYLE_NONE:
				return s0
		for dy: int in range(-1, 2):
			var ny: int = ly + dy
			if ny < 0 or ny >= _cell_h:
				continue
			var nrow: int = ny * _cell_w
			for dx: int in range(-1, 2):
				var nx: int = lx + dx
				if nx >= 0 and nx < _cell_w:
					var sn: int = _cell_style[nrow + nx]
					if sn != STYLE_NONE:
						return sn
		return STYLE_NONE
	if _grass_cells.is_empty():
		return STYLE_MEADOW if _bounds.size == Vector2.ZERO else STYLE_NONE
	var c0: Vector2i = Vector2i((pos / 8.0).floor())
	if _grass_style.has(c0):
		return int(_grass_style[c0])
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var nc: Vector2i = c0 + Vector2i(dx, dy)
			if _grass_style.has(nc):
				return int(_grass_style[nc])
	return STYLE_NONE


## Public floral micro-habitat query (0=none, 1=white, 2=blue, 3=lilac, 4=gold, 5=rose).
func floral_kind_at(pos: Vector2) -> int:
	if _bounds.size != Vector2.ZERO and not _bounds.grow(12.0).has_point(pos):
		return 0
	return _floral_kind_at(pos)


func _has_grass_near(pos: Vector2) -> bool:
	if _bounds.size != Vector2.ZERO and not _bounds.grow(12.0).has_point(pos):
		return false
	if _cell_grid_ready:
		if tuft_count <= 0:
			return _bounds.size == Vector2.ZERO
		return grass_style_at(pos) != STYLE_NONE
	if _grass_cells.is_empty():
		return _bounds.size == Vector2.ZERO
	var c0: Vector2i = Vector2i((pos / 8.0).floor())
	if _grass_cells.has(c0):
		return true
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if _grass_cells.has(c0 + Vector2i(dx, dy)):
				return true
	return false


func _has_grass_at_cell(wc: Vector2i) -> bool:
	if (_surfaces == null and extra_habitat_providers.is_empty()):
		return true
	if _cell_grid_ready:
		if tuft_count <= 0:
			return true
		var lx: int = floori(float(wc.x) * 0.5) - _cell_origin.x
		var ly: int = floori(float(wc.y) * 0.5) - _cell_origin.y
		if lx >= 0 and lx < _cell_w and ly >= 0 and ly < _cell_h and _cell_style[ly * _cell_w + lx] != STYLE_NONE:
			return true
		for dy: int in range(-1, 2):
			var ny: int = ly + dy
			if ny < 0 or ny >= _cell_h:
				continue
			var nrow: int = ny * _cell_w
			for dx: int in range(-1, 2):
				var nx: int = lx + dx
				if nx >= 0 and nx < _cell_w and _cell_style[nrow + nx] != STYLE_NONE:
					return true
		return false
	if _grass_cells.is_empty():
		return true
	var gc: Vector2i = Vector2i(floori(float(wc.x) * 0.5), floori(float(wc.y) * 0.5))
	if _grass_cells.has(gc):
		return true
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if _grass_cells.has(gc + Vector2i(dx, dy)):
				return true
	return false


func _floral_kind_at(pos: Vector2) -> int:
	if _cell_grid_ready:
		var lx: int = floori(pos.x * 0.125) - _cell_origin.x
		var ly: int = floori(pos.y * 0.125) - _cell_origin.y
		if lx >= 0 and lx < _cell_w and ly >= 0 and ly < _cell_h:
			var f0: int = _cell_floral[ly * _cell_w + lx]
			if f0 != 0:
				return f0
		for dy: int in range(-1, 2):
			var ny: int = ly + dy
			if ny < 0 or ny >= _cell_h:
				continue
			var nrow: int = ny * _cell_w
			for dx: int in range(-1, 2):
				var nx: int = lx + dx
				if nx >= 0 and nx < _cell_w:
					var fn: int = _cell_floral[nrow + nx]
					if fn != 0:
						return fn
		return 0
	var c0: Vector2i = Vector2i((pos / 8.0).floor())
	if _floral_cells.has(c0):
		return int(_floral_cells[c0])
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var nc: Vector2i = c0 + Vector2i(dx, dy)
			if _floral_cells.has(nc):
				return int(_floral_cells[nc])
	return 0


func _blade_palette_for(style_id: int) -> Array[Color]:
	match style_id:
		STYLE_FOREST:
			return FOREST_BLADE_COLORS
		STYLE_REED:
			return REED_BLADE_COLORS
		STYLE_DUNE:
			return DUNE_BLADE_COLORS
		STYLE_MOSS:
			return MOSS_BLADE_COLORS
		_:
			return BLADE_COLORS


func _petal_palette_for(f_kind: int) -> Array[Color]:
	match f_kind:
		1:
			return PETAL_WHITE
		2:
			return PETAL_BLUE
		3:
			return PETAL_LILAC
		4:
			return PETAL_GOLD
		5:
			return PETAL_ROSE
		_:
			return PETAL_ALL


func _spawn_motes(at: Vector2, count: int, burst_speed: float, force_petals: bool) -> void:
	if _mote_layer == null or not _has_grass_near(at):
		return
	var g_style: int = grass_style_at(at)
	var b_pal: Array[Color] = _blade_palette_for(g_style)
	var f_kind: int = _floral_kind_at(at)
	var tall_k: float = tallness_at(at)
	for _i: int in count:
		if _mote_layer.motes.size() >= MAX_MOTES:
			_mote_layer.motes.pop_front()
		var m: GrassMote = GrassMote.new()
		var ang: float = _rng.randf() * TAU
		var spd: float = _rng.randf_range(0.35, 1.0) * burst_speed
		m.pos = at + Vector2(_rng.randf_range(-5.5, 5.5), _rng.randf_range(-3.0, 3.0))
		m.vel = Vector2.from_angle(ang) * spd
		m.z_h = _rng.randf_range(2.0, 5.0 + 7.0 * tall_k)
		m.z_vel = _rng.randf_range(16.0, 34.0 + 8.0 * tall_k)
		m.life = _rng.randf_range(0.50, 1.10)
		m.phase = _rng.randf() * TAU

		var is_petal: bool = (f_kind > 0 and _rng.randf() < 0.72) or (force_petals and g_style == STYLE_MEADOW and _rng.randf() < 0.34)
		var is_pollen: bool = (not is_petal) and tall_k >= 0.40 and _rng.randf() < 0.42
		if is_petal:
			var pal: Array[Color] = _petal_palette_for(f_kind)
			m.color = pal[_rng.randi() % pal.size()]
			m.size_px = Vector2(2.0, 1.0) if _rng.randf() < 0.48 else Vector2(1.0, 1.0)
			m.flutter = true
			m.z_vel *= 0.85
			m.life *= 1.38
		elif is_pollen:
			# Floating golden pollen / silver seed-fluff shaken loose from tall grass plumes!
			m.color = POLLEN_COLORS[_rng.randi() % POLLEN_COLORS.size()]
			m.size_px = Vector2(1.0, 1.0)
			m.flutter = true
			m.z_vel *= 0.70
			m.life *= 1.55
		else:
			m.color = b_pal[_rng.randi() % b_pal.size()]
			m.size_px = Vector2(3.0, 1.0) if (tall_k >= 0.50 and _rng.randf() < 0.32) else (Vector2(2.0, 1.0) if _rng.randf() < 0.68 else Vector2(1.0, 1.0))
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
		m.vel = m.vel.lerp(wind_v, minf(1.0, delta * (4.4 if m.flutter else 3.4)))
		m.pos += m.vel * delta
		var grav: float = 30.0 if m.flutter else 68.0
		m.z_vel -= grav * delta
		m.z_h = maxf(0.0, m.z_h + m.z_vel * delta)
		if m.z_h <= 0.0:
			m.vel *= 0.65
			m.z_vel = 0.0
	_mote_layer.queue_redraw()


func _play_rustle(pos: Vector2, sneaking: bool, sprinting: bool, tall_k: float = 0.0) -> void:
	if _rustle == null or _rustle_wait > 0.0 or InputManager.ui_blocking:
		return
	var base_wait: float = 0.48 if sneaking else (0.19 if sprinting else 0.33)
	_rustle_wait = base_wait * lerpf(1.0, 0.78, tall_k)
	_rustle.position = pos
	var base_db: float = -35.0 if sneaking else (-24.0 if sprinting else -29.0)
	_rustle.volume_db = base_db + 2.8 * tall_k
	var pitch_shift: float = -0.12 * tall_k ## Deeper, fuller brushy rustle in waist-high tall grass!
	_rustle.pitch_scale = clampf(_rng.randf_range(0.86, 1.18) + pitch_shift, 0.68, 1.24)
	if not _rustle.playing:
		_rustle.play()


# ==============================================================================
# HOE CLEARING FOR TALL GRASS (Host-authoritative, replicated via @rpc)
# ==============================================================================

## Exact spatial query for cursor hover & tool prompts: true when any living tall-grass horst lies within `radius` px.
func has_tall_tuft_near(world_pos: Vector2, radius: float = 16.0) -> bool:
	if _tall_tufts.is_empty() or not covers_point(world_pos, radius):
		return false
	var r2: float = radius * radius
	var c0: Vector2i = Vector2i((world_pos / 16.0).floor())
	var span: int = maxi(1, ceili(radius / 16.0))
	for dy: int in range(-span, span + 1):
		for dx: int in range(-span, span + 1):
			var bucket: Variant = _tall_grid.get(c0 + Vector2i(dx, dy))
			if not (bucket is Array):
				continue
			for tid_v: Variant in bucket as Array:
				var tref: TallTuftRef = _tall_tufts[int(tid_v)]
				if tref.removed:
					continue
				# Check near base & mid-stem (in 3/4 view players hover over the tall blades slightly above the foot!)
				var foot_d2: float = tref.pos.distance_squared_to(world_pos)
				var mid_d2: float = (tref.pos + Vector2(0.0, -10.0)).distance_squared_to(world_pos)
				if foot_d2 <= r2 or mid_d2 <= r2:
					return true
	return false


## Host-only: clears every living tall-grass tuft inside a hoe swing's strike zone and replicates to all peers.
## Underlying low meadow turf, clover, and moss remain untouched so clearing looks organic rather than bare!
func host_hoe_tall_grass(origin: Vector2, aim_dir: Vector2, reach: float = 22.0, arc_rad: float = 1.75) -> int:
	if is_inside_tree() and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return 0
	if _tall_tufts.is_empty() or not covers_point(origin, reach + 24.0):
		return 0
	var dir: Vector2 = aim_dir.normalized() if aim_dir.length_squared() > 0.001 else Vector2.RIGHT
	var impact_pos: Vector2 = origin + dir * (reach * 0.72)
	var impact_r2: float = 17.5 * 17.5
	var max_reach: float = reach + 10.0
	var max_reach2: float = max_reach * max_reach
	var half_cos: float = cos(clampf(arc_rad * 0.56, 0.35, 1.35))

	var hit_ids: PackedInt32Array = PackedInt32Array()
	var c0: Vector2i = Vector2i((impact_pos / 16.0).floor())
	var span: int = ceili((max_reach + 18.0) / 16.0)
	for dy: int in range(-span, span + 1):
		for dx: int in range(-span, span + 1):
			var bucket: Variant = _tall_grid.get(c0 + Vector2i(dx, dy))
			if not (bucket is Array):
				continue
			for tid_v: Variant in bucket as Array:
				var tid: int = int(tid_v)
				var tref: TallTuftRef = _tall_tufts[tid]
				if tref.removed:
					continue
				if tref.pos.distance_squared_to(impact_pos) <= impact_r2:
					hit_ids.append(tid)
					continue
				var rel: Vector2 = tref.pos - origin
				var d2: float = rel.length_squared()
				if d2 <= max_reach2:
					if d2 <= 11.0 * 11.0 or rel.normalized().dot(dir) >= half_cos:
						hit_ids.append(tid)

	if hit_ids.is_empty():
		return 0
	if is_inside_tree() and multiplayer.has_multiplayer_peer():
		_rpc_remove_tall.rpc(hit_ids, impact_pos, dir)
	else:
		_apply_remove_tall(hit_ids, impact_pos, dir, true)
	return hit_ids.size()


@rpc("authority", "call_local", "reliable")
func _rpc_remove_tall(ids: PackedInt32Array, impact_pos: Vector2, dir: Vector2) -> void:
	_apply_remove_tall(ids, impact_pos, dir, true)


## Exports deterministic indices of hoe-cleared tall grass (for zone persistence & joiner snapshots).
func export_removed_tall() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if _removed_tall.is_empty():
		return out
	var keys: Array = _removed_tall.keys()
	keys.sort()
	for k: Variant in keys:
		out.append(int(k))
	return out


## Silently applies previously removed tall-grass indices (zone load, reload, or late-join sync).
func apply_removed_tall(ids: PackedInt32Array) -> void:
	if ids.is_empty():
		return
	_apply_remove_tall(ids, Vector2.ZERO, Vector2.RIGHT, false)


func _apply_remove_tall(ids: PackedInt32Array, impact_pos: Vector2, dir: Vector2, with_fx: bool) -> int:
	var removed_now: int = 0
	var dirty_cells: Dictionary = {} ## Vector2i (8x8 px cell) -> true
	for tid: int in ids:
		if tid < 0 or tid >= _tall_tufts.size():
			continue
		var tref: TallTuftRef = _tall_tufts[tid]
		if tref.removed:
			continue
		tref.removed = true
		_removed_tall[tid] = true
		removed_now += 1
		tall_tuft_count = maxi(0, tall_tuft_count - 1)
		tuft_count = maxi(0, tuft_count - 1)
		if tref.mm_lit != null and tref.idx_lit >= 0:
			tref.mm_lit.set_instance_transform_2d(tref.idx_lit, Transform2D(Vector2.ZERO, Vector2.ZERO, tref.orig_transform_lit.origin))
			tref.mm_lit.set_instance_custom_data(tref.idx_lit, Color(tref.orig_custom_lit.r, tref.orig_custom_lit.g, tref.orig_custom_lit.b, 0.0))
		if tref.mm_glow != null and tref.idx_glow >= 0:
			tref.mm_glow.set_instance_transform_2d(tref.idx_glow, Transform2D(Vector2.ZERO, Vector2.ZERO, tref.orig_transform_glow.origin))
			tref.mm_glow.set_instance_custom_data(tref.idx_glow, Color(tref.orig_custom_glow.r, tref.orig_custom_glow.g, tref.orig_custom_glow.b, 0.0))
			glow_tuft_count = maxi(0, glow_tuft_count - 1)
		var gc: Vector2i = Vector2i((tref.pos / 8.0).floor())
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				dirty_cells[gc + Vector2i(dx, dy)] = true
		if with_fx:
			_spawn_hoe_uproot_motes(tref.pos, dir, tref.style_id, tref.floral_code)

	if removed_now == 0:
		return 0
	_refresh_tall_cells(dirty_cells)
	if with_fx:
		stamp_burst(impact_pos, 17.5, 0.72, 4.5)
		_play_hoe_cut(impact_pos)
	return removed_now


func _refresh_tall_cells(cells: Dictionary) -> void:
	for gc_v: Variant in cells:
		var gc: Vector2i = gc_v as Vector2i
		var center: Vector2 = (Vector2(gc) + Vector2(0.5, 0.5)) * 8.0
		var g16: Vector2i = Vector2i((center / 16.0).floor())
		var best: float = 0.0
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var bucket: Variant = _tall_grid.get(g16 + Vector2i(dx, dy))
				if not (bucket is Array):
					continue
				for tid_v: Variant in bucket as Array:
					var tref: TallTuftRef = _tall_tufts[int(tid_v)]
					if tref.removed:
						continue
					var tgc: Vector2i = Vector2i((tref.pos / 8.0).floor())
					var d_cheb: int = maxi(absi(tgc.x - gc.x), absi(tgc.y - gc.y))
					if d_cheb == 0:
						best = minf(1.0, maxf(best, 0.68) + (0.18 if best >= 0.68 else 0.0))
					elif d_cheb == 1 and best < 0.35:
						best = maxf(best, 0.32)
		if _cell_grid_ready:
			var lx: int = gc.x - _cell_origin.x
			var ly: int = gc.y - _cell_origin.y
			if lx >= 0 and lx < _cell_w and ly >= 0 and ly < _cell_h:
				_cell_tall[ly * _cell_w + lx] = clampi(roundi(best * 255.0), 0, 255)
		if _use_cell_dicts:
			if best > 0.01:
				_tall_cells[gc] = best
			else:
				_tall_cells.erase(gc)


func _spawn_hoe_uproot_motes(at: Vector2, swing_dir: Vector2, style_id: int, floral_code: int) -> void:
	if _mote_layer == null:
		return
	var b_pal: Array[Color] = _blade_palette_for(style_id)
	var base_dir: Vector2 = swing_dir.normalized() if swing_dir.length_squared() > 0.001 else Vector2.RIGHT
	# 1. Severed tall-grass blades flying out along the hoe arc
	for _i: int in 4:
		if _mote_layer.motes.size() >= MAX_MOTES:
			_mote_layer.motes.pop_front()
		var m: GrassMote = GrassMote.new()
		var spread: float = _rng.randf_range(-1.15, 1.15)
		var spd: float = _rng.randf_range(26.0, 58.0)
		m.pos = at + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-2.5, 2.5))
		m.vel = base_dir.rotated(spread) * spd
		m.z_h = _rng.randf_range(3.0, 11.0)
		m.z_vel = _rng.randf_range(26.0, 52.0)
		m.life = _rng.randf_range(0.55, 1.05)
		m.phase = _rng.randf() * TAU
		m.color = b_pal[_rng.randi() % b_pal.size()]
		m.size_px = Vector2(3.0, 1.0) if _rng.randf() < 0.55 else Vector2(2.0, 1.0)
		m.flutter = false
		_mote_layer.motes.append(m)
	# 2. Earthy uprooted soil crumbs at the roots
	for _j: int in 2:
		if _mote_layer.motes.size() >= MAX_MOTES:
			_mote_layer.motes.pop_front()
		var s: GrassMote = GrassMote.new()
		var ang: float = _rng.randf() * TAU
		s.pos = at + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-1.5, 1.5))
		s.vel = Vector2.from_angle(ang) * _rng.randf_range(14.0, 32.0)
		s.z_h = _rng.randf_range(1.0, 4.0)
		s.z_vel = _rng.randf_range(20.0, 38.0)
		s.life = _rng.randf_range(0.38, 0.68)
		s.phase = _rng.randf() * TAU
		s.color = SOIL_CRUMB_COLORS[_rng.randi() % SOIL_CRUMB_COLORS.size()]
		s.size_px = Vector2(2.0, 1.0) if _rng.randf() < 0.4 else Vector2(1.0, 1.0)
		s.flutter = false
		_mote_layer.motes.append(s)
	# 3. Matching blossom petal or drifting seed-pollen fluff
	if _mote_layer.motes.size() >= MAX_MOTES:
		_mote_layer.motes.pop_front()
	var p: GrassMote = GrassMote.new()
	p.pos = at + Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-3.0, 2.0))
	p.vel = base_dir.rotated(_rng.randf_range(-1.3, 1.3)) * _rng.randf_range(14.0, 34.0)
	p.z_h = _rng.randf_range(6.0, 14.0)
	p.z_vel = _rng.randf_range(16.0, 30.0)
	p.life = _rng.randf_range(0.85, 1.45)
	p.phase = _rng.randf() * TAU
	if floral_code > 0:
		var ppal: Array[Color] = _petal_palette_for(floral_code)
		p.color = ppal[_rng.randi() % ppal.size()]
		p.size_px = Vector2(2.0, 1.0)
	else:
		p.color = POLLEN_COLORS[_rng.randi() % POLLEN_COLORS.size()]
		p.size_px = Vector2(1.0, 1.0)
	p.flutter = true
	_mote_layer.motes.append(p)


func _play_hoe_cut(pos: Vector2) -> void:
	if InputManager.ui_blocking:
		return
	if _hoe_sfx != null:
		_hoe_sfx.position = pos
		_hoe_sfx.pitch_scale = _rng.randf_range(0.92, 1.10)
		_hoe_sfx.play()
	if _rustle != null:
		_rustle.position = pos
		_rustle.volume_db = -21.0
		_rustle.pitch_scale = _rng.randf_range(0.76, 0.96)
		_rustle.play()
