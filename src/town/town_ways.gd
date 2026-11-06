class_name TownWays
extends RefCounted
## Natural trampled ways ("Trampelpfade", docs/town.md): where a person would really walk, not where a ruler would draw. Pure functions, no world: the town hands in the
## obstacles, a test for "can one stand here" and the ways that already exist.
##
## What makes it read as trodden rather than drawn:
##  - the search is weighted: worn ground is cheap, so a new way is drawn to the old ones and runs alongside them (a person takes the easy ground), but never so cheap that
##    it detours: the weights give a join at about 45 degrees, like two rivers meeting, not a T;
##  - open ground has a slow noise in its cost (hummocks, damp patches) and walls, trunks and stones cost more the closer they are, so the way bends and keeps a person's
##    distance instead of hugging corners;
##  - a way ends where it reaches an older one (a short tail along it), it does not run on to the door of the hut;
##  - the cell path is thinned, rounded (corner cutting) and given a little lateral sway, then checked against the obstacles again, falling back to less rounding.

const CELL: float = 8.0
const MARGIN: float = 3.0 ## obstacles are grown by this for the search
const OPEN: float = 1.4 ## cost of a step on open ground; worn ground costs 1.0
const NOISE_COST: float = 0.5
const CROWD_COST: float = 0.18 ## per solid neighbour cell
const REACH: int = 9 ## how far round the two ends the search may stray (cells); a second, wider try follows when it finds nothing
const MAX_CELLS: int = 80
const STEP: float = 6.0 ## spacing of the stored points
const WOBBLE: float = 4.5 ## sway sideways (noise is about +-0.6 of this)
const CONTACT_MIN: float = 12.0 ## a way must be this long before it may join another


## {"p": PackedVector2Array (points ~6 px apart, first = `from`), "joined": bool (it ends on an older way, not at `to`)}; "p" is empty when no way was found.
## solids: Rect2 the way must keep out of; walkable: Callable(Vector2) -> bool; trails: finished ways (polylines). With `join` false the way runs all the way to `to` (a person
## walking to a place); the trails are still cheap ground, so it follows them where they lead the right way.
static func route(from: Vector2, to: Vector2, solids: Array[Rect2], walkable: Callable, trails: Array[PackedVector2Array], seed_value: int, join: bool = true) -> Dictionary:
	var made: Dictionary = _search(from, to, solids, walkable, trails, seed_value, join, REACH)
	if (made.p as PackedVector2Array).is_empty(): ## walled in within a short way of the two ends (a long building in between): look wider
		made = _search(from, to, solids, walkable, trails, seed_value, join, REACH * 2 + 3)
	return made


static func _search(from: Vector2, to: Vector2, solids: Array[Rect2], walkable: Callable, trails: Array[PackedVector2Array], seed_value: int, join: bool, reach: int) -> Dictionary:
	var fail: Dictionary = {"p": PackedVector2Array(), "joined": false}
	var half: Vector2 = Vector2(CELL, CELL) / 2.0
	var pad: Vector2 = Vector2(reach, reach) * CELL
	var first: Vector2i = Vector2i(((from.min(to) - pad) / CELL).floor())
	var last: Vector2i = Vector2i(((from.max(to) + pad) / CELL).ceil())
	var size: Vector2i = last - first
	if size.x < 3 or size.y < 3 or size.x > MAX_CELLS or size.y > MAX_CELLS:
		return fail
	var grown: Array[Rect2] = []
	var blocks: Array[Rect2] = []
	for r: Rect2 in solids:
		grown.append(r.grow(MARGIN))
		blocks.append(r.grow(1.5))
	var solid: PackedByteArray = PackedByteArray()
	solid.resize(size.x * size.y)
	var worn: PackedByteArray = PackedByteArray()
	worn.resize(size.x * size.y)
	for y: int in size.y:
		for x: int in size.x:
			var c: Vector2 = Vector2(first.x + x, first.y + y) * CELL + half
			var blocked: bool = false
			for r: Rect2 in grown:
				if r.has_point(c):
					blocked = true
					break
			if not blocked and not bool(walkable.call(c)):
				blocked = true
			solid[y * size.x + x] = 1 if blocked else 0
	for line: PackedVector2Array in trails:
		for k: int in line.size() - 1:
			var count: int = maxi(ceili(line[k].distance_to(line[k + 1]) / 3.0), 1)
			for i: int in count + 1:
				var cell: Vector2i = Vector2i((line[k].lerp(line[k + 1], float(i) / float(count)) / CELL).floor()) - first
				if cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y:
					worn[cell.y * size.x + cell.x] = 1
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.03
	var grid: AStarGrid2D = AStarGrid2D.new()
	grid.region = Rect2i(first, size)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = half
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for y: int in size.y:
		for x: int in size.x:
			var id: Vector2i = Vector2i(first.x + x, first.y + y)
			if solid[y * size.x + x] == 1:
				grid.set_point_solid(id, true)
				continue
			if worn[y * size.x + x] == 1:
				continue ## weight 1.0
			var crowd: int = 0
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var nx: int = x + dx
					var ny: int = y + dy
					if (dx != 0 or dy != 0) and nx >= 0 and ny >= 0 and nx < size.x and ny < size.y and solid[ny * size.x + nx] == 1:
						crowd += 1
			var c: Vector2 = Vector2(id) * CELL + half
			grid.set_point_weight_scale(id, OPEN + NOISE_COST * (noise.get_noise_2d(c.x, c.y) * 0.5 + 0.5) + CROWD_COST * float(crowd))
	var a: Vector2i = Vector2i((from / CELL).floor())
	var b: Vector2i = Vector2i((to / CELL).floor())
	if not grid.region.has_point(a) or not grid.region.has_point(b):
		return fail
	grid.set_point_solid(a, false)
	grid.set_point_solid(b, false)
	var ids: Array[Vector2i] = grid.get_id_path(a, b)
	if ids.size() < 2:
		return fail
	var cells: PackedVector2Array = PackedVector2Array()
	cells.append(from)
	for k: int in range(1, ids.size() - 1):
		cells.append(Vector2(ids[k]) * CELL + half)
	cells.append(to)
	var joined: bool = false
	if join and not trails.is_empty():
		var walked: float = 0.0
		for k: int in range(1, ids.size() - 1):
			walked += cells[k].distance_to(cells[k - 1])
			var at: Vector2i = ids[k] - first
			if walked >= CONTACT_MIN and worn[at.y * size.x + at.x] == 1:
				var cut: int = mini(k + 2, cells.size() - 1)
				if cut < cells.size() - 1:
					cells = cells.slice(0, cut + 1)
					var snap: Vector2 = nearest_on(trails, cells[cut])
					if snap.distance_to(cells[cut]) <= 6.0:
						cells[cut] = snap
					joined = true
				break
	var memo: Dictionary = {}
	for level: int in 4:
		var shaped: PackedVector2Array = _shape(cells, level, seed_value)
		if _clear(shaped, blocks, walkable, memo):
			return {"p": shaped, "joined": joined}
	return {"p": resample(cells, STEP), "joined": joined}


## The point of the ways nearest to `point`.
static func nearest_on(trails: Array[PackedVector2Array], point: Vector2) -> Vector2:
	var best: Vector2 = point
	var best_distance: float = INF
	for line: PackedVector2Array in trails:
		for k: int in line.size() - 1:
			var at: Vector2 = Geometry2D.get_closest_point_to_segment(point, line[k], line[k + 1])
			if at.distance_squared_to(point) < best_distance:
				best_distance = at.distance_squared_to(point)
				best = at
	return best


## 0: thinned, rounded twice, resampled, with sway; 1: without sway; 2: rounded once; 3: only thinned.
static func _shape(cells: PackedVector2Array, level: int, seed_value: int) -> PackedVector2Array:
	var pts: PackedVector2Array = _simplify(cells, 3.0 if level < 3 else 1.0)
	if level < 3:
		pts = _round(pts, 2 if level < 2 else 1)
	pts = resample(pts, STEP)
	return _sway(pts, seed_value) if level == 0 else pts


static func _clear(points: PackedVector2Array, blocks: Array[Rect2], walkable: Callable, memo: Dictionary) -> bool:
	for i: int in range(1, points.size() - 1):
		var p: Vector2 = points[i]
		for r: Rect2 in blocks:
			if r.has_point(p):
				return false
		var key: Vector2i = Vector2i((p / 2.0).round())
		if not memo.has(key):
			memo[key] = bool(walkable.call(p))
		if not bool(memo[key]):
			return false
	return true


## Douglas-Peucker: only the points that bend the line by more than `eps` px stay.
static func _simplify(p: PackedVector2Array, eps: float) -> PackedVector2Array:
	if p.size() < 3:
		return p
	var keep: PackedByteArray = PackedByteArray()
	keep.resize(p.size())
	keep[0] = 1
	keep[p.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, p.size() - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var far: int = -1
		var far_distance: float = eps
		for i: int in range(seg.x + 1, seg.y):
			var d: float = p[i].distance_to(Geometry2D.get_closest_point_to_segment(p[i], p[seg.x], p[seg.y]))
			if d > far_distance:
				far = i
				far_distance = d
		if far >= 0:
			keep[far] = 1
			stack.append(Vector2i(seg.x, far))
			stack.append(Vector2i(far, seg.y))
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in p.size():
		if keep[i] == 1:
			out.append(p[i])
	return out


## Corner cutting (Chaikin) with both ends kept.
static func _round(p: PackedVector2Array, rounds: int) -> PackedVector2Array:
	var cur: PackedVector2Array = p
	for _r: int in rounds:
		var out: PackedVector2Array = PackedVector2Array([cur[0]])
		for i: int in cur.size() - 1:
			out.append(cur[i].lerp(cur[i + 1], 0.25))
			out.append(cur[i].lerp(cur[i + 1], 0.75))
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


## A slow lateral sway, nothing at the ends: no way is a ruler line.
static func _sway(p: PackedVector2Array, seed_value: int) -> PackedVector2Array:
	if p.size() < 5:
		return p
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value + 11
	noise.frequency = 0.014
	var total: float = 0.0
	for i: int in range(1, p.size()):
		total += p[i].distance_to(p[i - 1])
	var out: PackedVector2Array = p.duplicate()
	var s: float = 0.0
	for i: int in range(1, p.size() - 1):
		s += p[i].distance_to(p[i - 1])
		var envelope: float = clampf(minf(s, total - s) / 28.0, 0.0, 1.0)
		out[i] = p[i] + (p[i + 1] - p[i - 1]).normalized().orthogonal() * noise.get_noise_1d(s) * WOBBLE * envelope
	return out


## Points `step` px apart along the line (first and last kept).
static func resample(p: PackedVector2Array, step: float) -> PackedVector2Array:
	if p.size() < 2:
		return p
	var out: PackedVector2Array = PackedVector2Array([p[0]])
	var carry: float = 0.0
	for i: int in range(1, p.size()):
		var length: float = p[i - 1].distance_to(p[i])
		if length < 0.001:
			continue
		var at: float = step - carry
		while at <= length:
			out.append(p[i - 1].lerp(p[i], at / length))
			at += step
		carry = length - (at - step)
	if out[out.size() - 1].distance_to(p[p.size() - 1]) > 0.5:
		out.append(p[p.size() - 1])
	return out
