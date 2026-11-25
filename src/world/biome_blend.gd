class_name BiomeBlend
extends RefCounted
## The soft edge of biomes that have their own colours (data/biomes.json `gloom`, `arid`, `fade`): one number per map cell, 0 on the
## shared meadow and in the cells next to it, rising to the biome's strength over `fade` tiles of walking into it. Void cells copy
## their land neighbour, so the biome's own coast never turns back into meadow.
## - `g_gloom` / `amount_at`: Hexenwald (`gloom`)
## - `g_arid`  / `arid_at`:   Sonnenquarz-Öde (`arid`, 96-tile 3-phase desert transition)
## Pure function of the frozen map: every peer builds the same picture; nothing is saved.

const WORLD_PX: float = 1024.0 * 16.0

static var _cells: PackedFloat32Array = PackedFloat32Array()
static var _arid_cells: PackedFloat32Array = PackedFloat32Array()
static var _side: int = 0
static var _lake_bytes: PackedByteArray = PackedByteArray()
static var _lake_side: int = 0
static var _installed_key: String = ""
static var _gloom_tex: ImageTexture
static var _arid_tex: ImageTexture


static func has_cache(expected_key: String) -> bool:
	return _installed_key == expected_key and not _cells.is_empty() and _side > 0


static func clear_cache() -> void:
	_cells = PackedFloat32Array()
	_arid_cells = PackedFloat32Array()
	_side = 0
	_lake_bytes = PackedByteArray()
	_lake_side = 0
	_installed_key = ""
	_gloom_tex = null
	_arid_tex = null
	RenderingServer.global_shader_parameter_set("g_gloom", null)
	RenderingServer.global_shader_parameter_set("g_arid", null)
	RenderingServer.global_shader_parameter_set("g_lake_sdf", null)


## Publishes a precomputed bundle on the main thread.
static func apply_bundle(bundle: Dictionary, lake_tex: Texture2D) -> void:
	_cells = bundle.get("cells", PackedFloat32Array()) as PackedFloat32Array
	_arid_cells = bundle.get("arid_cells", PackedFloat32Array()) as PackedFloat32Array
	_side = int(bundle.get("side", 0))
	_lake_bytes = bundle.get("lake_bytes", PackedByteArray()) as PackedByteArray
	_lake_side = int(bundle.get("lake_side", 0))
	_installed_key = String(bundle.get("key", ""))
	_gloom_tex = _make_r8_texture(_cells, _side)
	_arid_tex = _make_r8_texture(_arid_cells, _side)
	_publish_shaders(lake_tex)
	Jobs.register_cleanup(BiomeBlend.clear_cache)


static func _publish_shaders(lake_tex: Texture2D) -> void:
	RenderingServer.global_shader_parameter_set("g_gloom", _gloom_tex)
	RenderingServer.global_shader_parameter_set("g_arid", _arid_tex)
	RenderingServer.global_shader_parameter_set("g_gloom_rect", Vector4(0.0, 0.0, WORLD_PX, WORLD_PX))
	if lake_tex != null:
		RenderingServer.global_shader_parameter_set("g_lake_sdf", lake_tex)


static func _make_r8_texture(values: PackedFloat32Array, side: int) -> ImageTexture:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(values.size())
	for i: int in values.size():
		bytes[i] = clampi(roundi(values[i] * 255.0), 0, 255)
	var image: Image = Image.create_from_data(side, side, false, Image.FORMAT_R8, bytes)
	return ImageTexture.create_from_image(image)


## Gloom at a world position (px): 0 = shared meadow, 1 = Hexenwald; bilinear like the shader reads it.
static func amount_at(pos: Vector2) -> float:
	return _sample(_cells, pos)


## Aridity at a world position (px): 0 = shared meadow, 1 = deep Sonnenquarz-Öde; bilinear like `g_arid`.
static func arid_at(pos: Vector2) -> float:
	return _sample(_arid_cells, pos)


## Signed distance in tiles from lake water (`< 0` in water, `0` at bank, `+d` up to ~15.875 on dry land), synced with `g_lake_sdf`.
static func sample_lake_tiles(lake_bytes: PackedByteArray, lake_side: int, pos: Vector2) -> float:
	if lake_side == 0 or lake_bytes.is_empty():
		return 16.0
	var u: Vector2 = pos / WORLD_PX * float(lake_side) - Vector2(0.5, 0.5)
	var x0: int = floori(u.x)
	var y0: int = floori(u.y)
	var fx: float = u.x - float(x0)
	var fy: float = u.y - float(y0)
	var raw: float = lerpf(
		lerpf(float(lake_bytes[clampi(y0, 0, lake_side - 1) * lake_side + clampi(x0, 0, lake_side - 1)]), float(lake_bytes[clampi(y0, 0, lake_side - 1) * lake_side + clampi(x0 + 1, 0, lake_side - 1)]), fx),
		lerpf(float(lake_bytes[clampi(y0 + 1, 0, lake_side - 1) * lake_side + clampi(x0, 0, lake_side - 1)]), float(lake_bytes[clampi(y0 + 1, 0, lake_side - 1) * lake_side + clampi(x0 + 1, 0, lake_side - 1)]), fx),
		fy
	)
	return (raw - 128.0) / 8.0


static func lake_tiles_at(pos: Vector2) -> float:
	return sample_lake_tiles(_lake_bytes, _lake_side, pos)


static func _lake_byte(x: int, y: int) -> float:
	return float(_lake_bytes[clampi(y, 0, _lake_side - 1) * _lake_side + clampi(x, 0, _lake_side - 1)])


## Cozy desert oasis hollow weight `0..1` around desert spring basins (synced bit-for-bit with `ground_tone.gdshader`).
static func oasis_at(pos: Vector2) -> float:
	var arid: float = arid_at(pos)
	if arid < 0.30:
		return 0.0
	var d_tiles: float = lake_tiles_at(pos)
	if d_tiles >= 10.5:
		return 0.0
	var px: Vector2 = pos.floor()
	var wob: float = (_vnoise(px / 26.0 + Vector2(19.0, 47.0)) - 0.5) * 2.8 + (_vnoise(px / 11.0 + Vector2(73.0, 13.0)) - 0.5) * 1.1
	return (1.0 - smoothstep(0.8, 7.2, d_tiles + wob)) * smoothstep(0.30, 0.50, arid)


## True where the ground shader's glowing white quartz outcrops stand open at `pos` (px), synced bit-for-bit with `ground_tone.gdshader`.
static func is_quartz_surface(pos: Vector2) -> bool:
	var arid: float = arid_at(pos)
	if arid < 0.62 or oasis_at(pos) >= 0.25:
		return false
	var px: Vector2 = pos.floor()
	var w_big: Vector2 = Vector2(
		_vnoise(px / 120.0 + Vector2(13.0, 71.0)) - 0.5,
		_vnoise(px / 120.0 + Vector2(89.0, 29.0)) - 0.5
	) * 80.0
	var pocket: float = _vnoise((px + w_big) / 280.0 + Vector2(17.0, 63.0))
	if pocket < 0.56:
		return false
	var pocket_t: float = smoothstep(0.56, 0.80, pocket) * smoothstep(0.62, 0.78, arid)
	var w_med: Vector2 = Vector2(
		_vnoise(px / 24.0 + Vector2(41.0, 9.0)) - 0.5,
		_vnoise(px / 24.0 + Vector2(7.0, 53.0)) - 0.5
	) * 20.0
	var p2: Vector2 = px + w_med
	var q: Vector2 = Vector2(p2.x * 1.18 + p2.y * 0.36, p2.y * 1.24 - p2.x * 0.28)
	var cl: float = (
		_vnoise(Vector2(q.x / 29.0, q.y / 19.0) + Vector2(103.0, 19.0)) * 0.52
		+ _vnoise(Vector2(q.x / 11.0, q.y / 8.5) + Vector2(5.0, 83.0)) * 0.33
		+ _vnoise(q / 5.0 + Vector2(29.0, 61.0)) * 0.15
	)
	return cl * (0.64 + 0.52 * pocket_t) > 0.72


## Depth (0..1, or 0 outside a puddle) of a standing rain puddle at `pos` (px), synced bit-for-bit with `ground_tone.gdshader`.
static func puddle_at(pos: Vector2, puddle_amount: float) -> float:
	if puddle_amount <= 0.02:
		return 0.0
	var arid: float = arid_at(pos)
	var pud_here: float = puddle_amount * (1.0 - smoothstep(0.18, 0.48, arid))
	if pud_here <= 0.02:
		return 0.0
	var px: Vector2 = pos.floor()
	var hollow: float = _vnoise(px / 150.0 + Vector2(51.0, 9.0))
	if hollow < 0.2:
		return 0.0
	var warp: float = _vnoise(px / 8.0 + Vector2(7.0, 61.0)) - 0.5
	var p_fbm: Vector2 = px / 27.0 + Vector2(133.0, 41.0) + Vector2(warp * 0.55, warp * 0.55)
	var fbm_val: float = (
		_vnoise(p_fbm) * 0.58
		+ _vnoise(p_fbm * 2.07 + Vector2(7.3, 7.3)) * 0.28
		+ _vnoise(p_fbm * 4.1 - Vector2(3.1, 3.1)) * 0.14
	)
	var pn: float = fbm_val + 0.55 * (hollow - 0.5)
	var pthr: float = 0.815 - 0.12 * pud_here
	var edge: float = _uhash(int(px.x) + 311, int(px.y) + 5)
	if pn <= pthr + 0.018 * edge:
		return 0.0
	return clampf((pn - pthr) / 0.08, 0.08, 1.0)


static func sample_field(arr: PackedFloat32Array, side: int, pos: Vector2) -> float:
	if side == 0 or arr.is_empty():
		return 0.0
	var u: Vector2 = pos / WORLD_PX * float(side) - Vector2(0.5, 0.5)
	var x0: int = floori(u.x)
	var y0: int = floori(u.y)
	var fx: float = u.x - float(x0)
	var fy: float = u.y - float(y0)
	return lerpf(
		lerpf(arr[clampi(y0, 0, side - 1) * side + clampi(x0, 0, side - 1)], arr[clampi(y0, 0, side - 1) * side + clampi(x0 + 1, 0, side - 1)], fx),
		lerpf(arr[clampi(y0 + 1, 0, side - 1) * side + clampi(x0, 0, side - 1)], arr[clampi(y0 + 1, 0, side - 1) * side + clampi(x0 + 1, 0, side - 1)], fx),
		fy
	)


static func _sample(arr: PackedFloat32Array, pos: Vector2) -> float:
	return sample_field(arr, _side, pos)


static func _cell_at(arr: PackedFloat32Array, x: int, y: int) -> float:
	return arr[clampi(y, 0, _side - 1) * _side + clampi(x, 0, _side - 1)]


static func _uhash(ix: int, iy: int) -> float:
	var qx: int = (ix + 65536) & 0xFFFFFFFF
	var qy: int = (iy + 65536) & 0xFFFFFFFF
	var h: int = ((qx * 1597334677) & 0xFFFFFFFF) ^ ((qy * 3812015801) & 0xFFFFFFFF)
	h = ((h ^ (h >> 16)) * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 3266489917) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h >> 8) / 16777216.0


static func _vnoise(p: Vector2) -> float:
	var ix: int = floori(p.x)
	var iy: int = floori(p.y)
	var fx: float = p.x - float(ix)
	var fy: float = p.y - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _uhash(ix, iy)
	var b: float = _uhash(ix + 1, iy)
	var c: float = _uhash(ix, iy + 1)
	var d: float = _uhash(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
