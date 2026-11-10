class_name BiomeBlend
extends RefCounted
## The soft edge of biomes that have their own colours (data/biomes.json `gloom`, `fade`): one number per map cell, 0 on the
## shared meadow and in the cells next to it, rising to the biome's `gloom` over `fade` tiles of walking into it. Void cells copy
## their land neighbour, so the biome's own coast never turns back into meadow. The ground shader (`g_gloom`, `g_gloom_rect`)
## mixes its palettes with it; later stages (fog, light, plant colours, sound) read the same field with `amount_at`.
## Pure function of the frozen map: every peer builds the same picture; nothing is saved.

const WORLD_PX: float = float(RegionMap.WORLD_TILES) * 16.0

static var _cells: PackedFloat32Array = PackedFloat32Array()
static var _side: int = 0


## The field as numbers 0..1, one per map cell (row-major, `map.grid_size` wide).
static func compute(map: RegionMap) -> PackedFloat32Array:
	var side: int = map.grid_size
	var biomes: Dictionary = DataRegistry.table("biomes")
	var strength: PackedFloat32Array = PackedFloat32Array()
	var fade: PackedFloat32Array = PackedFloat32Array()
	strength.resize(side * side)
	fade.resize(side * side)
	var land: PackedByteArray = PackedByteArray()
	land.resize(side * side)
	var any: bool = false
	for i: int in side * side:
		var id: String = map.biome_at(Vector2i(i % side, i / side) * RegionMap.CELL)
		if id.is_empty():
			continue
		land[i] = 1
		var entry: Dictionary = biomes.get(id, {}) as Dictionary
		strength[i] = float(entry.get("gloom", 0.0))
		fade[i] = float(entry.get("fade", 48.0))
		any = any or strength[i] > 0.0
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(side * side)
	if not any:
		return out
	var lo: Vector2i = Vector2i(side, side) ## the box round the gloomy cells (plus the fade): only it is worked on, the rest of the world stays 0
	var hi: Vector2i = Vector2i.ZERO
	for i: int in side * side:
		if strength[i] > 0.0:
			lo = Vector2i(mini(lo.x, i % side), mini(lo.y, i / side))
			hi = Vector2i(maxi(hi.x, i % side), maxi(hi.y, i / side))
	lo = (lo - Vector2i.ONE * 16).clamp(Vector2i.ZERO, Vector2i.ONE * (side - 1))
	hi = (hi + Vector2i.ONE * 16).clamp(Vector2i.ZERO, Vector2i.ONE * (side - 1))
	# distance (3-4 chamfer, a third of a cell per step) through land from the nearest land cell without gloom
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
			var tiles: float = float(dist[i]) / 3.0 * float(RegionMap.CELL) ## no land without gloom at all (dist = far) counts as deep inside
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


## Builds the field for `map`, publishes it to the shaders and keeps the numbers for `amount_at`.
static func install(map: RegionMap) -> void:
	_cells = compute(map)
	_side = map.grid_size
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(_cells.size())
	for i: int in _cells.size():
		bytes[i] = clampi(roundi(_cells[i] * 255.0), 0, 255)
	var image: Image = Image.create_from_data(_side, _side, false, Image.FORMAT_R8, bytes)
	RenderingServer.global_shader_parameter_set("g_gloom", ImageTexture.create_from_image(image))
	RenderingServer.global_shader_parameter_set("g_gloom_rect", Vector4(0.0, 0.0, WORLD_PX, WORLD_PX))


## Gloom at a world position (px): 0 = shared meadow, 1 = the biome's own colours; bilinear like the shader reads it.
static func amount_at(pos: Vector2) -> float:
	if _side == 0:
		return 0.0
	var u: Vector2 = pos / WORLD_PX * float(_side) - Vector2(0.5, 0.5)
	var x0: int = floori(u.x)
	var y0: int = floori(u.y)
	var fx: float = u.x - float(x0)
	var fy: float = u.y - float(y0)
	return lerpf(lerpf(_at(x0, y0), _at(x0 + 1, y0), fx), lerpf(_at(x0, y0 + 1), _at(x0 + 1, y0 + 1), fx), fy)


static func _at(x: int, y: int) -> float:
	return _cells[clampi(y, 0, _side - 1) * _side + clampi(x, 0, _side - 1)]
