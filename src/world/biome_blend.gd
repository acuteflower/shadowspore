class_name BiomeBlend
extends RefCounted
## The soft edge of biomes that have their own colours (data/biomes.json `gloom`, `arid`, `fade`): one number per map cell, 0 on the
## shared meadow and in the cells next to it, rising to the biome's strength over `fade` tiles of walking into it. Void cells copy
## their land neighbour, so the biome's own coast never turns back into meadow.
## - `g_gloom` / `amount_at`: Hexenwald (`gloom`)
## - `g_arid`  / `arid_at`:   Sonnenquarz-Öde (`arid`, 96-tile 3-phase desert transition)
## Pure function of the frozen map: every peer builds the same picture; nothing is saved.

const WORLD_PX: float = float(RegionMap.WORLD_TILES) * 16.0
const LAKE_SDF_PATH: String = "res://assets/world/lakes_sdf.png"

static var _cells: PackedFloat32Array = PackedFloat32Array()
static var _arid_cells: PackedFloat32Array = PackedFloat32Array()
static var _side: int = 0
static var _lake_bytes: PackedByteArray = PackedByteArray()
static var _lake_side: int = 0


## The gloom field as numbers 0..1, one per map cell (row-major, `map.grid_size` wide).
static func compute(map: RegionMap) -> PackedFloat32Array:
	return _compute_field(map, "gloom", 48.0)


## The arid desert field as numbers 0..1, one per map cell (row-major, `map.grid_size` wide).
static func compute_arid(map: RegionMap) -> PackedFloat32Array:
	return _compute_field(map, "arid", 96.0)


static func _compute_field(map: RegionMap, key: String, default_fade: float) -> PackedFloat32Array:
	var side: int = map.grid_size
	var biomes: Dictionary = DataRegistry.table("biomes")
	var strength: PackedFloat32Array = PackedFloat32Array()
	var fade: PackedFloat32Array = PackedFloat32Array()
	strength.resize(side * side)
	fade.resize(side * side)
	var land: PackedByteArray = PackedByteArray()
	land.resize(side * side)
	var any: bool = false
	var max_fade: float = default_fade
	for i: int in side * side:
		var id: String = map.biome_at(Vector2i(i % side, i / side) * RegionMap.CELL)
		if id.is_empty():
			continue
		land[i] = 1
		var entry: Dictionary = biomes.get(id, {}) as Dictionary
		strength[i] = float(entry.get(key, 0.0))
		fade[i] = float(entry.get("fade", default_fade))
		if strength[i] > 0.0:
			any = true
			max_fade = maxf(max_fade, fade[i])
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(side * side)
	if not any:
		return out
	var pad: int = ceili(max_fade / float(RegionMap.CELL)) + 6
	var lo: Vector2i = Vector2i(side, side)
	var hi: Vector2i = Vector2i.ZERO
	for i: int in side * side:
		if strength[i] > 0.0:
			lo = Vector2i(mini(lo.x, i % side), mini(lo.y, i / side))
			hi = Vector2i(maxi(hi.x, i % side), maxi(hi.y, i / side))
	lo = (lo - Vector2i.ONE * pad).clamp(Vector2i.ZERO, Vector2i.ONE * (side - 1))
	hi = (hi + Vector2i.ONE * pad).clamp(Vector2i.ZERO, Vector2i.ONE * (side - 1))
	# distance (3-4 chamfer, a third of a cell per step) through land from the nearest land cell without this field
	var far: int = 1 << 20
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(side * side)
	for i: int in side * side:
		dist[i] = 0 if (land[i] == 1 and strength[i] <= 0.0) else far
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			var i: int = y * side + x
			if land[i] == 0 or dist[i] == 0:
				continue
			var best: int = dist[i]
			if x > 0 and land[i - 1] == 1:
				best = mini(best, dist[i - 1] + 3)
			if y > 0:
				if land[i - side] == 1:
					best = mini(best, dist[i - side] + 3)
				if x > 0 and land[i - side - 1] == 1:
					best = mini(best, dist[i - side - 1] + 4)
				if x < side - 1 and land[i - side + 1] == 1:
					best = mini(best, dist[i - side + 1] + 4)
			dist[i] = best
	for y: int in range(hi.y, lo.y - 1, -1):
		for x: int in range(hi.x, lo.x - 1, -1):
			var i: int = y * side + x
			if land[i] == 0 or dist[i] == 0:
				continue
			var best: int = dist[i]
			if x < side - 1 and land[i + 1] == 1:
				best = mini(best, dist[i + 1] + 3)
			if y < side - 1:
				if land[i + side] == 1:
					best = mini(best, dist[i + side] + 3)
				if x < side - 1 and land[i + side + 1] == 1:
					best = mini(best, dist[i + side + 1] + 4)
				if x > 0 and land[i + side - 1] == 1:
					best = mini(best, dist[i + side - 1] + 4)
			dist[i] = best
	for i: int in side * side:
		if land[i] == 1 and strength[i] > 0.0:
			var tiles: float = float(dist[i]) / 3.0 * float(RegionMap.CELL)
			out[i] = strength[i] * smoothstep(0.0, maxf(fade[i], 1.0), minf(tiles, 9999.0))
	var filled: PackedFloat32Array = out.duplicate()
	for _pass: int in 3: ## void cells take what their land neighbours hold
		var next: PackedFloat32Array = filled.duplicate()
		for y: int in range(lo.y, hi.y + 1):
			for x: int in range(lo.x, hi.x + 1):
				var i: int = y * side + x
				if land[i] == 1:
					continue
				var v: float = filled[i]
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var nx: int = x + dx
						var ny: int = y + dy
						if nx >= 0 and ny >= 0 and nx < side and ny < side:
							v = maxf(v, filled[ny * side + nx])
				next[i] = v
		filled = next
	return filled


## Builds the fields for `map`, publishes them to the shaders and keeps the numbers for `amount_at` / `arid_at`.
static func install(map: RegionMap) -> void:
	_cells = compute(map)
	_arid_cells = compute_arid(map)
	_side = map.grid_size
	RenderingServer.global_shader_parameter_set("g_gloom", _make_r8_texture(_cells, _side))
	RenderingServer.global_shader_parameter_set("g_arid", _make_r8_texture(_arid_cells, _side))
	RenderingServer.global_shader_parameter_set("g_gloom_rect", Vector4(0.0, 0.0, WORLD_PX, WORLD_PX))
	var lake_tex: Texture2D = ResourceLoader.load(LAKE_SDF_PATH) as Texture2D
	if lake_tex != null:
		RenderingServer.global_shader_parameter_set("g_lake_sdf", lake_tex)
		var lake_img: Image = lake_tex.get_image()
		if lake_img != null:
			if lake_img.get_format() != Image.FORMAT_L8 and lake_img.get_format() != Image.FORMAT_R8:
				lake_img.convert(Image.FORMAT_R8)
			_lake_bytes = lake_img.get_data()
			_lake_side = lake_img.get_width()


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
static func lake_tiles_at(pos: Vector2) -> float:
	if _lake_side == 0 or _lake_bytes.is_empty():
		return 16.0
	var u: Vector2 = pos / WORLD_PX * float(_lake_side) - Vector2(0.5, 0.5)
	var x0: int = floori(u.x)
	var y0: int = floori(u.y)
	var fx: float = u.x - float(x0)
	var fy: float = u.y - float(y0)
	var raw: float = lerpf(
		lerpf(_lake_byte(x0, y0), _lake_byte(x0 + 1, y0), fx),
		lerpf(_lake_byte(x0, y0 + 1), _lake_byte(x0 + 1, y0 + 1), fx),
		fy
	)
	return (raw - 128.0) / 8.0


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
	if arid < 0.62:
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


static func _sample(arr: PackedFloat32Array, pos: Vector2) -> float:
	if _side == 0 or arr.is_empty():
		return 0.0
	var u: Vector2 = pos / WORLD_PX * float(_side) - Vector2(0.5, 0.5)
	var x0: int = floori(u.x)
	var y0: int = floori(u.y)
	var fx: float = u.x - float(x0)
	var fy: float = u.y - float(y0)
	return lerpf(
		lerpf(_cell_at(arr, x0, y0), _cell_at(arr, x0 + 1, y0), fx),
		lerpf(_cell_at(arr, x0, y0 + 1), _cell_at(arr, x0 + 1, y0 + 1), fx),
		fy
	)


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
