class_name HallgratWays
extends RefCounted
## Hallgrat's walking net for its people (docs/hallgrat_bewohner_konzept.md 9). A pure grid of 8 px cells over the town's bounds,
## built from immutable data only (the relief's collision and floor kinds, the footprints of every house, deco thing and wall piece of
## data/hallgrat.json and data/hallgrat_art.json, the paved tiles of data/ground_baked.json), so every peer and every worker thread gets the
## same answer. Paved ground and door paths are cheap, grass dearer, the edge of a wall dearer still, so people keep to the streets and the
## middle of them. Height levels are crossed only where the relief's collision is open (ramps, stairs, rock steps). `route(a, b)` is an
## A* over the grid, pulled straight where the line is clear and resampled; routes are cached (guarded by a mutex: a `Jobs` worker may warm
## them). Safe to build on a worker: it reads `Relief` and `DataRegistry` tables only.

const CELL: float = 8.0
const MARGIN: float = 4.0 ## px every solid shape is grown by (half a body)
const PAVED: float = 1.0
const GRASS: float = 1.7
const EDGE: float = 0.6 ## extra cost per solid neighbour cell: keep to the middle of a street
const STEP: float = 4.0 ## spacing of a route's points
const MAX_EXPAND: int = 60000
const TRUNKS: Array[String] = ["tree", "birch", "blossom", "orchard_apple", "orchard_pear", "willow"]

var origin: Vector2 = Vector2.ZERO ## px of cell (0, 0)
var cols: int = 0
var rows: int = 0
var cost: PackedFloat32Array = PackedFloat32Array() ## 0 = blocked
var _cache: Dictionary = {} ## "x,y>x,y" -> PackedVector2Array
var _lock: Mutex = Mutex.new()


static func build(relief: Relief, data: Dictionary, art: Dictionary, baked: Dictionary) -> HallgratWays:
	var w: HallgratWays = HallgratWays.new()
	var b: Array = data.get("bounds", [0, 0, 1, 1]) as Array
	w.origin = Vector2(float(b[0]), float(b[1])) * 16.0
	w.cols = int((float(b[2]) - float(b[0])) * 16.0 / CELL)
	w.rows = int((float(b[3]) - float(b[1])) * 16.0 / CELL)
	w.cost.resize(w.cols * w.rows)
	var paved: Dictionary = {}
	for run: Array in baked.get("hallgrat_clear", []) as Array:
		for tx: int in range(int(run[1]), int(run[2]) + 1):
			paved[Vector2i(tx, int(run[0]))] = true
	for y: int in w.rows:
		for x: int in w.cols:
			var p: Vector2 = w.origin + Vector2(x + 0.5, y + 0.5) * CELL
			var tile: Vector2i = Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
			var open: bool = relief == null or relief.walkable(tile.x, tile.y)
			if open and relief != null:
				for oy: float in [-2.0, 2.0]:
					for ox: float in [-2.0, 2.0]:
						if relief.blocked_at(p + Vector2(ox, oy)):
							open = false
			w.cost[y * w.cols + x] = (PAVED if paved.has(tile) else GRASS) if open else 0.0
	for dp: Dictionary in data.get("door_paths", []) as Array: ## the lanes from the doors are streets too
		var pts: Array = dp.get("px", []) as Array
		for k: int in pts.size() - 1:
			var a: Vector2 = Vector2(float((pts[k] as Array)[0]), float((pts[k] as Array)[1]))
			var c: Vector2 = Vector2(float((pts[k + 1] as Array)[0]), float((pts[k + 1] as Array)[1]))
			var n: int = maxi(1, int(a.distance_to(c) / 4.0))
			for i: int in n + 1:
				var cell: Vector2i = w.cell_of(a.lerp(c, float(i) / n))
				if w.inside(cell) and w.cost[cell.y * w.cols + cell.x] > 0.0:
					w.cost[cell.y * w.cols + cell.x] = PAVED
	var types: Dictionary = art.get("types", {}) as Dictionary
	for spec: Dictionary in (data.get("placed", []) as Array) + (data.get("deco", []) as Array):
		var feet: Array = spec.px as Array
		w._block_piece(types.get(String(spec.type), {}) as Dictionary, Vector2(float(feet[0]), float(feet[1])), bool(spec.get("flip", false)))
	for spec: Dictionary in art.get("wall_pieces", []) as Array:
		var at: Array = spec.px as Array
		w._block_piece(types.get(String(spec.type), {}) as Dictionary, Vector2(float(at[0]), float(at[1])), false)
	for spec: Dictionary in data.get("greenery", []) as Array: ## the town's trees have solid trunks (bushes and flowers are walked through)
		if not TRUNKS.has(String(spec.kind)):
			continue
		var tile: Array = spec.tile as Array
		var cell: Vector2i = Vector2i(int(tile[0]), int(tile[1]))
		var h: int = absi(hash(Vector2i(cell.x, cell.y * 7 + 3)))
		var foot: Vector2 = Vector2(cell) * 16.0 + Vector2(8 + h % 9 - 4, 13 + (h / 9) % 5 - 2)
		var r: float = 5.0 + MARGIN
		var c0: Vector2i = w.cell_of(foot - Vector2(r, r))
		var c1: Vector2i = w.cell_of(foot + Vector2(r, r))
		for y: int in range(maxi(0, c0.y), mini(w.rows - 1, c1.y) + 1):
			for x: int in range(maxi(0, c0.x), mini(w.cols - 1, c1.x) + 1):
				if w.center_of(Vector2i(x, y)).distance_to(foot) <= r:
					w.cost[y * w.cols + x] = 0.0
	var with_edge: PackedFloat32Array = w.cost.duplicate()
	for y: int in w.rows:
		for x: int in w.cols:
			var here: float = w.cost[y * w.cols + x]
			if here <= 0.0:
				continue
			var solid: int = 0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if not w.inside(q) or w.cost[q.y * w.cols + q.x] <= 0.0:
					solid += 1
			with_edge[y * w.cols + x] = here + EDGE * solid
	w.cost = with_edge
	return w


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / CELL), floori((p.y - origin.y) / CELL))


func center_of(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func open_at(p: Vector2) -> bool:
	var c: Vector2i = cell_of(p)
	return inside(c) and cost[c.y * cols + c.x] > 0.0


## The free cell centre nearest to `p` (a breadth-first ring search; deterministic). INF when nothing is free within `reach` cells.
func snap(p: Vector2, reach: int = 12) -> Vector2:
	var c: Vector2i = cell_of(p)
	if inside(c) and cost[c.y * cols + c.x] > 0.0:
		return center_of(c)
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	for r: int in range(1, reach + 1):
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q: Vector2i = c + Vector2i(dx, dy)
				if inside(q) and cost[q.y * cols + q.x] > 0.0:
					var d: float = center_of(q).distance_squared_to(p)
					if d < best_d:
						best_d = d
						best = center_of(q)
		if best.is_finite():
			return best
	return best


## Marks the cells a solid piece covers (the same shapes `HallgratBuilding` gives its StaticBody), grown by MARGIN.
func _block_piece(info: Dictionary, at: Vector2, flip: bool) -> void:
	if info.is_empty() or not bool(info.get("solid", true)):
		return
	var sx: float = -1.0 if flip else 1.0
	var shapes: Array[PackedVector2Array] = []
	var circles: Array[Vector3] = []
	if info.has("chain"):
		var chain: Array = info.chain as Array
		var half: float = float(info.get("thick", 7.0)) / 2.0
		for t: Variant in info.get("towers", []) as Array:
			var tw: Array = t as Array
			circles.append(Vector3(float(tw[0]) * sx + at.x, float(tw[1]) + at.y, float(tw[2])))
		for k: int in chain.size() - 1:
			var a: Vector2 = Vector2(float((chain[k] as Array)[0]) * sx, float((chain[k] as Array)[1])) + at + Vector2(0, -1)
			var b: Vector2 = Vector2(float((chain[k + 1] as Array)[0]) * sx, float((chain[k + 1] as Array)[1])) + at + Vector2(0, -1)
			var along: Vector2 = (b - a).normalized()
			var side: Vector2 = along.orthogonal() * half
			a -= along * 1.5
			b += along * 1.5
			shapes.append(PackedVector2Array([a + side, b + side, b - side, a - side]))
	elif info.has("poly"):
		var pts: PackedVector2Array = PackedVector2Array()
		for q: Variant in info.poly as Array:
			pts.append(Vector2(float((q as Array)[0]) * sx, float((q as Array)[1])) + at)
		shapes.append(pts)
	else:
		var foot: Array = info.get("foot", [12, 6]) as Array
		var size: Vector2 = Vector2(maxf(8.0, float(foot[0]) - 6.0), maxf(6.0, float(foot[1]) - 4.0))
		var c: Vector2 = at + Vector2(0, -size.y / 2.0 - 1.0)
		shapes.append(PackedVector2Array([c - size / 2.0, c + Vector2(size.x, -size.y) / 2.0, c + size / 2.0, c + Vector2(-size.x, size.y) / 2.0]))
	for poly: PackedVector2Array in shapes:
		var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(poly, MARGIN)
		for g: PackedVector2Array in grown:
			_fill_poly(g)
	for circ: Vector3 in circles:
		var r: float = circ.z + MARGIN
		var c0: Vector2i = cell_of(Vector2(circ.x - r, circ.y - r))
		var c1: Vector2i = cell_of(Vector2(circ.x + r, circ.y + r))
		for y: int in range(maxi(0, c0.y), mini(rows - 1, c1.y) + 1):
			for x: int in range(maxi(0, c0.x), mini(cols - 1, c1.x) + 1):
				if center_of(Vector2i(x, y)).distance_to(Vector2(circ.x, circ.y)) <= r:
					cost[y * cols + x] = 0.0


func _fill_poly(poly: PackedVector2Array) -> void:
	if poly.size() < 3:
		return
	var box: Rect2 = Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly:
		box = box.expand(p)
	var c0: Vector2i = cell_of(box.position)
	var c1: Vector2i = cell_of(box.end)
	for y: int in range(maxi(0, c0.y), mini(rows - 1, c1.y) + 1):
		for x: int in range(maxi(0, c0.x), mini(cols - 1, c1.x) + 1):
			if Geometry2D.is_point_in_polygon(center_of(Vector2i(x, y)), poly):
				cost[y * cols + x] = 0.0


## The way from `from` to `to` (px, both snapped to free cells), a polyline of points STEP apart. Empty when there is none.
func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a: Vector2 = snap(from)
	var b: Vector2 = snap(to)
	if not a.is_finite() or not b.is_finite():
		return PackedVector2Array()
	var key: String = "%d,%d>%d,%d" % [int(a.x), int(a.y), int(b.x), int(b.y)]
	_lock.lock()
	var known: Variant = _cache.get(key)
	_lock.unlock()
	if known != null:
		return known as PackedVector2Array
	var out: PackedVector2Array = _search(cell_of(a), cell_of(b))
	_lock.lock()
	_cache[key] = out
	_lock.unlock()
	return out


func cached_routes() -> int:
	_lock.lock()
	var n: int = _cache.size()
	_lock.unlock()
	return n


const NEIGH: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]


func _search(start: Vector2i, goal: Vector2i) -> PackedVector2Array:
	if start == goal:
		return PackedVector2Array([center_of(start)])
	var n: int = cols * rows
	var g: PackedFloat32Array = PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var came: PackedInt32Array = PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed: PackedByteArray = PackedByteArray()
	closed.resize(n)
	var heap_f: PackedFloat32Array = PackedFloat32Array()
	var heap_i: PackedInt32Array = PackedInt32Array()
	var s: int = start.y * cols + start.x
	var gi: int = goal.y * cols + goal.x
	g[s] = 0.0
	_push(heap_f, heap_i, _h(start, goal), s)
	var expanded: int = 0
	while heap_i.size() > 0:
		var cur: int = _pop(heap_f, heap_i)
		if closed[cur] != 0:
			continue
		closed[cur] = 1
		if cur == gi:
			break
		expanded += 1
		if expanded > MAX_EXPAND:
			return PackedVector2Array()
		var cx: int = cur % cols
		var cy: int = cur / cols
		for d: Vector2i in NEIGH:
			var nx: int = cx + d.x
			var ny: int = cy + d.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var ni: int = ny * cols + nx
			var c: float = cost[ni]
			if c <= 0.0 or closed[ni] != 0:
				continue
			var step: float = c
			if d.x != 0 and d.y != 0: ## diagonal: no cutting a corner
				if cost[cy * cols + nx] <= 0.0 or cost[ny * cols + cx] <= 0.0:
					continue
				step *= 1.41421
			var ng: float = g[cur] + step
			if ng < g[ni]:
				g[ni] = ng
				came[ni] = cur
				_push(heap_f, heap_i, ng + _h(Vector2i(nx, ny), goal), ni)
	if came[gi] < 0:
		return PackedVector2Array()
	var cells: PackedVector2Array = PackedVector2Array()
	var at: int = gi
	while at >= 0:
		cells.append(center_of(Vector2i(at % cols, at / cols)))
		at = came[at]
	cells.reverse()
	return _resample(_pull(cells))


func _h(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	return PAVED * (maxi(dx, dy) + 0.41421 * mini(dx, dy))


static func _push(hf: PackedFloat32Array, hi: PackedInt32Array, f: float, i: int) -> void:
	hf.append(f)
	hi.append(i)
	var k: int = hf.size() - 1
	while k > 0:
		var p: int = (k - 1) / 2
		if hf[p] <= hf[k]:
			break
		var tf: float = hf[p]
		hf[p] = hf[k]
		hf[k] = tf
		var ti: int = hi[p]
		hi[p] = hi[k]
		hi[k] = ti
		k = p


static func _pop(hf: PackedFloat32Array, hi: PackedInt32Array) -> int:
	var top: int = hi[0]
	var last: int = hf.size() - 1
	hf[0] = hf[last]
	hi[0] = hi[last]
	hf.resize(last)
	hi.resize(last)
	var k: int = 0
	while true:
		var l: int = k * 2 + 1
		if l >= last:
			break
		var m: int = l
		if l + 1 < last and hf[l + 1] < hf[l]:
			m = l + 1
		if hf[k] <= hf[m]:
			break
		var tf: float = hf[m]
		hf[m] = hf[k]
		hf[k] = tf
		var ti: int = hi[m]
		hi[m] = hi[k]
		hi[k] = ti
		k = m
	return top


## True when the straight line a -> b stays on free cells whose cost is no dearer than the dearer end (so a shortcut never leaves the street
## for the grass) and keeps the corners clear.
func clear_line(a: Vector2, b: Vector2) -> bool:
	var limit: float = maxf(_cost_at(a), _cost_at(b)) + 0.01
	var n: int = maxi(1, int(a.distance_to(b) / 1.0))
	for i: int in n + 1:
		var p: Vector2 = a.lerp(b, float(i) / n)
		var c: float = _cost_at(p)
		if c <= 0.0 or c > limit:
			return false
	return true


func _cost_at(p: Vector2) -> float:
	var c: Vector2i = cell_of(p)
	return cost[c.y * cols + c.x] if inside(c) else 0.0


## String pulling: from each kept point jump to the farthest later cell the line reaches.
func _pull(cells: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array([cells[0]])
	var i: int = 0
	while i < cells.size() - 1:
		var j: int = mini(cells.size() - 1, i + 24)
		while j > i + 1 and not clear_line(cells[i], cells[j]):
			j -= 1
		out.append(cells[j])
		i = j
	return out


static func _resample(p: PackedVector2Array) -> PackedVector2Array:
	if p.size() < 2:
		return p
	var out: PackedVector2Array = PackedVector2Array([p[0]])
	var carry: float = 0.0
	for k: int in p.size() - 1:
		var a: Vector2 = p[k]
		var b: Vector2 = p[k + 1]
		var seg: float = a.distance_to(b)
		var d: float = STEP - carry
		while d <= seg:
			out.append(a.lerp(b, d / seg))
			d += STEP
		carry = seg - (d - STEP)
	if out[out.size() - 1] != p[p.size() - 1]:
		out.append(p[p.size() - 1])
	return out


static func length_of(p: PackedVector2Array) -> float:
	var total: float = 0.0
	for k: int in p.size() - 1:
		total += p[k].distance_to(p[k + 1])
	return total


## The point `d` px along a polyline (clamped).
static func point_along(p: PackedVector2Array, d: float) -> Vector2:
	if p.is_empty():
		return Vector2.INF
	var left: float = d
	for k: int in p.size() - 1:
		var seg: float = p[k].distance_to(p[k + 1])
		if left <= seg:
			return p[k].lerp(p[k + 1], left / seg) if seg > 0.0 else p[k]
		left -= seg
	return p[p.size() - 1]
