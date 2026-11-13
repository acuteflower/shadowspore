class_name RegionMap
extends RefCounted
## The world's region layout. A hex grid of seeds (jittered, unevenly sized) is cut into regions
## along noise-warped Voronoi borders, so shapes are organic while the hex order stays
## underneath. The land itself is a noise blob (no fixed outline), regions are grouped into a few
## big super regions. Fully determined by `world_seed`, so every peer builds the same map.
## Ids are indices into `regions` / `supers`; -1 is outside the world.

const WORLD_TILES: int = 1100 ## the world fits inside this square
const CELL: int = 4 ## tiles per lookup cell
const SPACING: float = 150.0 ## tiles between neighbouring hex seeds
const JITTER: float = 0.3 ## seed shift, in spacings
const MIN_AREA: int = 6000 ## tiles^2; smaller regions (coast slivers) are dropped
const SUPER_COUNT: int = 5
const COAST_WOBBLE: float = 0.1 ## noise added to the land field (about a tile of coast wobble)

var world_seed: int
var world_biome: String = "" ## optional shared biome; named areas remain independent
var own_biomes: Array[String] = [] ## biomes that keep their own areas although `world_biome` is shared (data/world_map.json `own_biomes`: the Hexenwald)
var editor_compatible_maps: Array[Dictionary] = []
## {id, center: Vector2 (tiles), scale, neighbors: Array[int], depth, area, super}
var regions: Array[Dictionary] = []
## {id, regions: Array[int], neighbors: Array[int], depth, area, center: Vector2 (tiles),
## name: String (area name), biome: String (id in data/biomes.json, "" until assigned)}
var supers: Array[Dictionary] = []
var start_region: int = -1
## Where the players spawn (tile). The story start region stays the base for depth and difficulty; the spawn is hand-picked near the middle of the map.
var start: Vector2i = Vector2i(-1, -1)
var grid_size: int = WORLD_TILES / CELL
var _grid: PackedInt32Array = PackedInt32Array()
var _land: PackedByteArray = PackedByteArray()


## With `baked` (the frozen world, `RegionMap.new(0, DataRegistry.table("world_map"))`, see `to_data`) the map is loaded as is;
## without it the map is generated from the seed (dev tool: tools/bake_world_map.gd freezes one).
func _init(seed_value: int, baked: Dictionary = {}) -> void:
	world_seed = seed_value
	if not baked.is_empty():
		_from_data(baked)
		return
	_make_land()
	_place_seeds()
	_rasterize()
	_find_start_and_depth()
	_group_supers()


## Everything needed to rebuild this exact map; the grid is run-length coded [id, count, ...].
func to_data() -> Dictionary:
	var out_regions: Array[Dictionary] = []
	for reg: Dictionary in regions:
		var c: Vector2 = reg.center as Vector2
		out_regions.append({"id": reg.id, "center": [c.x, c.y], "scale": reg.scale, "neighbors": reg.neighbors, "depth": reg.depth, "area": reg.area, "super": reg.super})
	var out_supers: Array[Dictionary] = []
	for sup: Dictionary in supers:
		var c: Vector2 = sup.center as Vector2
		var entry: Dictionary = {"id": sup.id, "regions": sup.regions, "neighbors": sup.neighbors, "depth": sup.depth, "area": sup.area, "center": [c.x, c.y], "biome": sup.biome}
		if sup.has("name"):
			entry["name"] = sup.name
		out_supers.append(entry)
	var runs: Array[int] = []
	var cur: int = _grid[0]
	var count: int = 0
	for id: int in _grid:
		if id == cur:
			count += 1
		else:
			runs.append_array([cur, count])
			cur = id
			count = 1
	runs.append_array([cur, count])
	var result: Dictionary = {"seed": world_seed, "cell": CELL, "world_tiles": WORLD_TILES, "start_region": start_region, "start": [start.x, start.y], "regions": out_regions, "supers": out_supers, "grid": runs}
	if not world_biome.is_empty():
		result["biome"] = world_biome
	if not own_biomes.is_empty():
		result["own_biomes"] = own_biomes.duplicate()
	if not editor_compatible_maps.is_empty():
		result["editor_compatible_maps"] = editor_compatible_maps.duplicate(true)
	return result


func _from_data(d: Dictionary) -> void:
	assert(int(d.cell) == CELL and int(d.world_tiles) == WORLD_TILES, "world_map.json was baked with other grid constants")
	world_seed = int(d.seed)
	world_biome = String(d.get("biome", ""))
	own_biomes.assign(d.get("own_biomes", []))
	editor_compatible_maps.assign(d.get("editor_compatible_maps", []))
	start_region = int(d.start_region)
	if d.has("start"):
		start = Vector2i(int((d.start as Array)[0]), int((d.start as Array)[1]))
	for r: Dictionary in d.regions:
		var c: Array = r.center
		regions.append({"id": int(r.id), "center": Vector2(c[0], c[1]), "scale": float(r.scale), "neighbors": _ints(r.neighbors), "depth": int(r.depth), "area": int(r.area), "super": int(r.super)})
	for sup: Dictionary in d.supers:
		var c: Array = sup.center
		var entry: Dictionary = {"id": int(sup.id), "regions": _ints(sup.regions), "neighbors": _ints(sup.neighbors), "depth": int(sup.depth), "area": int(sup.area), "center": Vector2(c[0], c[1]), "biome": str(sup.get("biome", ""))}
		if sup.has("name"):
			entry["name"] = String(sup.name)
		supers.append(entry)
	var runs: Array = d.grid
	_grid.resize(grid_size * grid_size)
	var at: int = 0
	for i: int in range(0, runs.size(), 2):
		for _k: int in int(runs[i + 1]):
			_grid[at] = int(runs[i])
			at += 1


## JSON hands back floats; ids must be ints.
func _ints(a: Array) -> Array:
	var out: Array = []
	for v: Variant in a:
		out.append(int(v))
	return out


func region_at(tile: Vector2i) -> int:
	if tile.x < 0 or tile.y < 0:
		return -1
	var c: Vector2i = tile / CELL
	if c.x < 0 or c.y < 0 or c.x >= grid_size or c.y >= grid_size:
		return -1
	return _grid[c.y * grid_size + c.x]


## How much land there is at a point (tile units): 0..1, bilinear between the land flags of the
## 4-tile cells, so thresholding it at 0.5 gives a smooth coast instead of 4-tile steps.
func land_amount(tile: Vector2) -> float:
	var u: Vector2 = tile / CELL - Vector2(0.5, 0.5)
	var x0: int = floori(u.x)
	var y0: int = floori(u.y)
	var fx: float = u.x - x0
	var fy: float = u.y - y0
	return lerpf(lerpf(_land_cell(x0, y0), _land_cell(x0 + 1, y0), fx), lerpf(_land_cell(x0, y0 + 1), _land_cell(x0 + 1, y0 + 1), fx), fy)


## Land flag per tile of the whole world (row-major, WORLD_TILES wide, 1 = land): the smooth land
## field plus a little wobble, thresholded at 0.5, then a 3x3 majority pass (rounds corners and
## drops one-tile spikes and notches). Slow (seconds): only for tools/bake_land_sdf.gd, the game
## reads the baked result.
func tile_land_mask() -> PackedByteArray:
	var coast: FastNoiseLite = _noise(23, 1.0 / 9.0)
	var side: int = WORLD_TILES
	var raw: PackedByteArray = PackedByteArray()
	raw.resize((side + 2) * (side + 2))
	for y: int in side + 2:
		for x: int in side + 2:
			var t: Vector2i = Vector2i(x - 1, y - 1)
			var v: float = land_amount(Vector2(t) + Vector2(0.5, 0.5)) + coast.get_noise_2d(t.x, t.y) * COAST_WOBBLE
			raw[y * (side + 2) + x] = 1 if v > 0.5 else 0
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(side * side)
	for y: int in side:
		for x: int in side:
			var n: int = 0
			for dy: int in 3:
				for dx: int in 3:
					n += raw[(y + dy) * (side + 2) + x + dx]
			mask[y * side + x] = 1 if n >= 5 else 0
	return mask


func _land_cell(cx: int, cy: int) -> float:
	if cx < 0 or cy < 0 or cx >= grid_size or cy >= grid_size:
		return 0.0
	return 1.0 if _grid[cy * grid_size + cx] >= 0 else 0.0


## A tile inside the region, as close to its centre as the region's land allows (the centre
## itself can lie in the sea for a bent region).
func anchor(region: int) -> Vector2i:
	var target: Vector2 = (regions[region] as Dictionary).center as Vector2
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for i: int in _grid.size():
		if _grid[i] == region:
			var tile: Vector2 = (Vector2(i % grid_size, i / grid_size) + Vector2(0.5, 0.5)) * CELL
			if tile.distance_squared_to(target) < best_d:
				best_d = tile.distance_squared_to(target)
				best = Vector2i(tile)
	return best


## Biome id (data/biomes.json) of the super region the tile lies in; "" outside the world.
func biome_at(tile: Vector2i) -> String:
	var id: int = super_at(tile)
	if id < 0:
		return ""
	var own: String = (supers[id] as Dictionary).biome as String
	return own if world_biome.is_empty() or own_biomes.has(own) else world_biome


## One byte per map cell: 0 normal meadow, 1 Hexenwald (`witch_forest`), 2 other bare biomes (`quartz_desert`); PropGenerator reads it.
func bare_cells() -> PackedByteArray:
	var biomes: Dictionary = DataRegistry.table("biomes")
	var out: PackedByteArray = PackedByteArray()
	out.resize(grid_size * grid_size)
	for i: int in out.size():
		var id: int = _grid[i]
		if id >= 0:
			var b: String = biome_at(Vector2i(i % grid_size, i / grid_size) * CELL)
			if bool((biomes.get(b, {}) as Dictionary).get("bare", false)):
				out[i] = 1 if b == "witch_forest" else 2
	return out


## The shared biome also applies to older baked materials and saved editor patches.
static func active_biome(id: String) -> String:
	var table: Dictionary = DataRegistry.table("world_map")
	var active: String = String(table.get("biome", ""))
	return id if active.is_empty() or (table.get("own_biomes", []) as Array).has(id) else active


func area_name(id: int) -> String:
	var area: Dictionary = supers[id]
	return String(area.get("name", DataRegistry.get_entry("biomes", String(area.biome)).get("name", "UNBEKANNT")))


func super_at(tile: Vector2i) -> int:
	var id: int = region_at(tile)
	return -1 if id < 0 else (regions[id] as Dictionary).super as int


func _noise(seed_offset: int, freq: float, octaves: int = 1) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = world_seed + seed_offset
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


## Land = big noise lobes, pulled down towards the edges of the square (no circle), then only the
## biggest connected piece is kept.
func _make_land() -> void:
	var lobes: FastNoiseLite = _noise(5, 1.0 / 340.0, 3)
	var ragged: FastNoiseLite = _noise(6, 1.0 / 40.0)
	var half: float = WORLD_TILES * 0.5
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(grid_size * grid_size)
	for cy: int in grid_size:
		for cx: int in grid_size:
			var p: Vector2 = (Vector2(cx, cy) + Vector2(0.5, 0.5)) * CELL
			var d: float = maxf(absf(p.x - half), absf(p.y - half)) / half
			var v: float = lobes.get_noise_2d(p.x, p.y) * 0.9 + ragged.get_noise_2d(p.x, p.y) * 0.1 + 0.55 - d * d * 1.0
			mask[cy * grid_size + cx] = 1 if v > 0.0 else 0
	# keep the largest connected piece
	var label: PackedInt32Array = PackedInt32Array()
	label.resize(mask.size())
	var best_label: int = 0
	var best_size: int = 0
	var next_label: int = 1
	for start: int in mask.size():
		if mask[start] == 0 or label[start] != 0:
			continue
		var stack: PackedInt32Array = [start]
		label[start] = next_label
		var size: int = 0
		while not stack.is_empty():
			var i: int = stack[-1]
			stack.resize(stack.size() - 1)
			size += 1
			var x: int = i % grid_size
			var y: int = i / grid_size
			for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + off.x
				var ny: int = y + off.y
				if nx < 0 or ny < 0 or nx >= grid_size or ny >= grid_size:
					continue
				var j: int = ny * grid_size + nx
				if mask[j] == 1 and label[j] == 0:
					label[j] = next_label
					stack.append(j)
		if size > best_size:
			best_size = size
			best_label = next_label
		next_label += 1
	_land.resize(mask.size())
	for i: int in mask.size():
		_land[i] = 1 if label[i] == best_label else 0


func _place_seeds() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed
	var mid: Vector2 = Vector2.ONE * WORLD_TILES * 0.5
	var rows: int = int(WORLD_TILES / (SPACING * 0.866)) + 3
	for r: int in range(-rows, rows + 1):
		for q: int in range(-rows, rows + 1):
			var p: Vector2 = mid + Vector2(SPACING * (q + r * 0.5), SPACING * 0.866 * r)
			p += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * SPACING * JITTER
			var scale: float = rng.randf_range(0.8, 1.25)
			if absf(p.x - mid.x) > WORLD_TILES * 0.5 or absf(p.y - mid.y) > WORLD_TILES * 0.5:
				continue
			regions.append({"id": regions.size(), "center": p, "scale": scale, "neighbors": [], "depth": -1, "area": 0, "super": -1})


func _rasterize() -> void:
	_assign()
	var kept: Array[Dictionary] = []
	for reg: Dictionary in regions:
		if (reg.area as int) >= MIN_AREA:
			reg.id = kept.size()
			kept.append(reg)
	if kept.size() < regions.size():
		regions = kept
		_assign()
	for cy: int in grid_size - 1:
		for cx: int in grid_size - 1:
			var a: int = _grid[cy * grid_size + cx]
			for b: int in [_grid[cy * grid_size + cx + 1], _grid[(cy + 1) * grid_size + cx]]:
				if a >= 0 and b >= 0 and a != b:
					_link(a, b)


## Fills `_grid` with the nearest region per land cell, smooths it, and counts each region's area.
func _assign() -> void:
	var wx: FastNoiseLite = _noise(1, 1.0 / 90.0)
	var wy: FastNoiseLite = _noise(2, 1.0 / 90.0)
	var fx: FastNoiseLite = _noise(3, 1.0 / 28.0)
	var fy: FastNoiseLite = _noise(4, 1.0 / 28.0)
	_grid.resize(grid_size * grid_size)
	for cy: int in grid_size:
		for cx: int in grid_size:
			if _land[cy * grid_size + cx] == 0:
				_grid[cy * grid_size + cx] = -1
				continue
			var p: Vector2 = (Vector2(cx, cy) + Vector2(0.5, 0.5)) * CELL
			# bend the sample point: wide swings make big bays, fine ones ragged edges
			var q: Vector2 = p + Vector2(wx.get_noise_2d(p.x, p.y), wy.get_noise_2d(p.x, p.y)) * 38.0
			q += Vector2(fx.get_noise_2d(p.x, p.y), fy.get_noise_2d(p.x, p.y)) * 7.0
			var best: int = -1
			var best_d: float = INF
			for reg: Dictionary in regions:
				var d: float = q.distance_to(reg.center as Vector2) / (reg.scale as float)
				if d < best_d:
					best_d = d
					best = reg.id as int
			_grid[cy * grid_size + cx] = best
	_smooth()
	for reg: Dictionary in regions:
		reg.area = 0
	for id: int in _grid:
		if id >= 0:
			(regions[id] as Dictionary).area = ((regions[id] as Dictionary).area as int) + CELL * CELL


## One majority pass (3x3): removes single-cell exclaves and pinholes the border warp leaves.
func _smooth() -> void:
	var out: PackedInt32Array = _grid.duplicate()
	for cy: int in range(1, grid_size - 1):
		for cx: int in range(1, grid_size - 1):
			var counts: Dictionary = {}
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var id: int = _grid[(cy + dy) * grid_size + cx + dx]
					counts[id] = (counts.get(id, 0) as int) + 1
			for id: int in counts:
				if (counts[id] as int) >= 5:
					out[cy * grid_size + cx] = id
	_grid = out


func _link(a: int, b: int) -> void:
	var na: Array = (regions[a] as Dictionary).neighbors
	if not na.has(b):
		na.append(b)
		((regions[b] as Dictionary).neighbors as Array).append(a)


## Start at the southern edge (southernmost region with enough land); depth = steps from there,
## the base for difficulty and for which regions open up with the story.
func _find_start_and_depth() -> void:
	var best_y: float = -INF
	for reg: Dictionary in regions:
		if (reg.area as int) > 4000 and (reg.center as Vector2).y > best_y:
			best_y = (reg.center as Vector2).y
			start_region = reg.id as int
	var queue: Array[int] = [start_region]
	(regions[start_region] as Dictionary).depth = 0
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for n: int in (regions[cur] as Dictionary).neighbors:
			if (regions[n] as Dictionary).depth == -1:
				(regions[n] as Dictionary).depth = ((regions[cur] as Dictionary).depth as int) + 1
				queue.append(n)


## Super regions: the start region's group plus SUPER_COUNT-1 anchors as far from each other as
## possible; then the smallest group repeatedly takes the closest free neighbour, which keeps
## groups connected and about equally big.
func _group_supers() -> void:
	var anchors: Array[int] = [start_region]
	while anchors.size() < mini(SUPER_COUNT, regions.size()):
		var far: int = -1
		var far_d: float = -1.0
		for reg: Dictionary in regions:
			var nearest: float = INF
			for a: int in anchors:
				nearest = minf(nearest, (reg.center as Vector2).distance_to((regions[a] as Dictionary).center as Vector2))
			if nearest > far_d:
				far_d = nearest
				far = reg.id as int
		anchors.append(far)
	for a: int in anchors:
		supers.append({"id": supers.size(), "regions": [a], "neighbors": [], "depth": -1, "area": (regions[a] as Dictionary).area, "center": Vector2.ZERO, "biome": ""})
		(regions[a] as Dictionary).super = supers.size() - 1
	var open: int = regions.size() - anchors.size()
	while open > 0:
		var order: Array[Dictionary] = supers.duplicate()
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.area as int) < (b.area as int))
		var took: bool = false
		for s: Dictionary in order:
			var anchor: Vector2 = (regions[(s.regions as Array)[0] as int] as Dictionary).center as Vector2
			var pick: int = -1
			var pick_d: float = INF
			for r: int in s.regions:
				for n: int in (regions[r] as Dictionary).neighbors:
					var d: float = ((regions[n] as Dictionary).center as Vector2).distance_to(anchor)
					if (regions[n] as Dictionary).super == -1 and d < pick_d:
						pick_d = d
						pick = n
			if pick >= 0:
				(regions[pick] as Dictionary).super = s.id
				(s.regions as Array).append(pick)
				s.area = (s.area as int) + ((regions[pick] as Dictionary).area as int)
				open -= 1
				took = true
				break
		if not took:
			break # leftovers not connected to any group: cannot happen on one landmass
	for s: Dictionary in supers:
		var sum: Vector2 = Vector2.ZERO
		for r: int in s.regions:
			sum += ((regions[r] as Dictionary).center as Vector2) * ((regions[r] as Dictionary).area as float)
			for n: int in (regions[r] as Dictionary).neighbors:
				var other: int = (regions[n] as Dictionary).super as int
				if other != s.id and other >= 0 and not (s.neighbors as Array).has(other):
					(s.neighbors as Array).append(other)
		s.center = sum / maxf(s.area as float, 1.0)
	var queue: Array[int] = [0]
	(supers[0] as Dictionary).depth = 0
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for n: int in (supers[cur] as Dictionary).neighbors:
			if (supers[n] as Dictionary).depth == -1:
				(supers[n] as Dictionary).depth = ((supers[cur] as Dictionary).depth as int) + 1
				queue.append(n)
