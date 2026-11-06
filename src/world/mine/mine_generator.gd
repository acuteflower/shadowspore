class_name MineGenerator
extends RefCounted
## Builds the shape of a mine level (docs/mine.md section 4). A pure function of (world seed, level): no nodes, no globals except the data table,
## so every peer gets the same level and tests can run headless. Each phase draws from a random stream of its own (`_stream`), so changing one phase
## never shifts another.
##
## Phases: rooms on a cell grid -> a maze over the cells (rooms are single nodes) with some cells left as solid rock -> braiding (loops) -> entry, exit
## and station -> the critical path -> carving the tiles (rooms, corridors, hubs) -> erosion -> room types.

const CELL: int = 8
const BORDER: int = 2 ## solid tiles round the level
const TYPE_MIN_CELLS: Dictionary = {"spider_nest": 2, "forge": 2, "crystal": 2, "voidroom": 2}
const TYPE_MAX_CELLS: Dictionary = {"storage": 4, "bunks": 4, "airshaft": 4}

var _l: MineLayout
var _zone: Dictionary
var _n: int = 0 ## cells per side
var _edge: int = 0
var _room_of: PackedInt32Array = PackedInt32Array()
var _adj: Array[PackedInt32Array] = []
var _linked: Dictionary = {}
var _hub: PackedInt32Array = PackedInt32Array() ## per cell: hub tile x * 65536 + y, or -1
var _noise: FastNoiseLite


@warning_ignore("integer_division")
func generate(world_seed: int, level: int) -> MineLayout:
	var started: int = Time.get_ticks_usec()
	_l = MineLayout.new()
	_l.world_seed = world_seed
	_l.level = level
	_zone = MineManager.zone(level)
	_l.zone_id = String(_zone.get("id", ""))
	_edge = MineManager.edge_tiles(level)
	_n = _edge / CELL
	_l.edge = _edge
	_l.cells = _n
	_linked.clear()
	_l.passages.clear()
	_noise = FastNoiseLite.new()
	_noise.seed = int(_mix(_mix(world_seed, level), 77) & 0x7FFFFFFF)
	_noise.frequency = 0.13
	_rooms()
	_maze()
	_braid()
	_adjacency()
	_keys()
	_carve()
	_erode()
	_types()
	MineDecorator.new().dress(_l)
	_l.build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	return _l


# ---------- random ----------

static func _mix(a: int, b: int) -> int:
	var x: int = a * 6364136223846793 + b * 1442695040888963 + 0x1E3779B97F4A7C15
	x = (x ^ (x >> 29)) * 0x3F58476D1CE4E5B9
	return x ^ (x >> 32)


func _stream(phase: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _mix(_mix(_l.world_seed, _l.level), phase)
	return rng


## A stable random number 0..1 per tile, phase and salt (no state).
static func _hash2(x: int, y: int, salt: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + salt * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(array.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = array[i]
		array[i] = array[j]
		array[j] = tmp


# ---------- phase 1: rooms ----------

func _rooms() -> void:
	var rng: RandomNumberGenerator = _stream(1)
	_room_of.resize(_n * _n)
	_room_of.fill(-1)
	var side: int = rng.randi() % 4 ## the entry hall (2 x 2 cells) lies at the edge of the level
	var along: int = rng.randi_range(1, _n - 3)
	var at: Vector2i
	match side:
		0: at = Vector2i(along, 0)
		1: at = Vector2i(_n - 2, along)
		2: at = Vector2i(along, _n - 2)
		_: at = Vector2i(0, along)
	_add_room(Rect2i(at.x, at.y, 2, 2))
	var covered: int = 4
	var target: int = int(roundf(float(_zone.get("room_density", 0.3)) * float(_n * _n)))
	var sizes: Array = _zone.get("room_cells", [1, 2]) as Array
	var low: int = int(sizes[0])
	var high: int = int(sizes[1])
	var tries: int = 0
	var halls: int = 0 ## a few halls (2 x 2 cells) first: the exit and the rest room need the space for their stairs and lift
	while halls < 3 + _n / 40 and tries < 400:
		tries += 1
		var hall: Rect2i = Rect2i(rng.randi_range(0, _n - 2), rng.randi_range(0, _n - 2), 2, 2)
		if _ring_free(hall):
			_add_room(hall)
			covered += 4
			halls += 1
	tries = 0
	while covered < target and tries < target * 40:
		tries += 1
		var w: int = low if rng.randf() < 0.3 else rng.randi_range(low, high)
		var h: int = low if rng.randf() < 0.3 else rng.randi_range(low, high)
		var rect: Rect2i = Rect2i(rng.randi_range(0, _n - w), rng.randi_range(0, _n - h), w, h)
		if _ring_free(rect):
			_add_room(rect)
			covered += w * h


func _ring_free(rect: Rect2i) -> bool:
	for y: int in range(maxi(rect.position.y - 1, 0), mini(rect.end.y + 1, _n)):
		for x: int in range(maxi(rect.position.x - 1, 0), mini(rect.end.x + 1, _n)):
			if _room_of[y * _n + x] >= 0:
				return false
	return true


func _add_room(cells: Rect2i) -> void:
	var id: int = _l.rooms.size()
	for y: int in range(cells.position.y, cells.end.y):
		for x: int in range(cells.position.x, cells.end.x):
			_room_of[y * _n + x] = id
	var rect: Rect2i = Rect2i(cells.position * CELL + Vector2i.ONE, cells.size * CELL - Vector2i(2, 2))
	rect = rect.intersection(Rect2i(BORDER, BORDER, _edge - 2 * BORDER, _edge - 2 * BORDER))
	_l.rooms.append({"id": id, "cells": cells, "rect": rect, "center": rect.position + rect.size / 2, "shape": String(_zone.get("room_shape", "rect")), "type": "", "degree": 0, "area": cells.size.x * cells.size.y})


# ---------- phase 2: the maze ----------

func _find(parent: PackedInt32Array, x: int) -> int:
	var root: int = x
	while parent[root] != root:
		root = parent[root]
	while parent[x] != root:
		var next: int = parent[x]
		parent[x] = root
		x = next
	return root


func _link(a: int, b: int) -> void:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	_l.passages.append(Vector2i(lo, hi))
	_linked[MineLayout.key(lo, hi)] = true


func _maze() -> void:
	var rng: RandomNumberGenerator = _stream(2)
	var total: int = _n * _n
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(total)
	for i: int in total:
		parent[i] = i
	for room: Dictionary in _l.rooms: ## every room is one node: its cells are joined from the start
		var cells: Rect2i = room.cells as Rect2i
		var first: int = cells.position.y * _n + cells.position.x
		for y: int in range(cells.position.y, cells.end.y):
			for x: int in range(cells.position.x, cells.end.x):
				parent[_find(parent, y * _n + x)] = _find(parent, first)
	var solid: float = float(_zone.get("solid", 0.12))
	var excluded: PackedByteArray = PackedByteArray()
	excluded.resize(total)
	for i: int in total:
		excluded[i] = 1 if _room_of[i] < 0 and rng.randf() < solid else 0
	var plain: Array = []
	var bridged: Array = []
	for y: int in _n:
		for x: int in _n:
			var a: int = y * _n + x
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				if x + step.x >= _n or y + step.y >= _n:
					continue
				var b: int = (y + step.y) * _n + x + step.x
				if _room_of[a] >= 0 and _room_of[a] == _room_of[b]:
					continue
				(bridged if excluded[a] == 1 or excluded[b] == 1 else plain).append(Vector2i(a, b))
	_shuffle(plain, rng)
	_shuffle(bridged, rng)
	for pair: Vector2i in plain + bridged: ## ordinary cells first; solid rock is only crossed where it must be
		var ra: int = _find(parent, pair.x)
		var rb: int = _find(parent, pair.y)
		if ra != rb:
			parent[ra] = rb
			_link(pair.x, pair.y)
	var changed: bool = true ## solid cells that only ended up as dead ends are rock again
	while changed:
		changed = false
		var degree: PackedInt32Array = PackedInt32Array()
		degree.resize(total)
		for p: Vector2i in _l.passages:
			degree[p.x] += 1
			degree[p.y] += 1
		for i: int in total:
			if excluded[i] == 1 and degree[i] == 1:
				for k: int in range(_l.passages.size()):
					var p: Vector2i = _l.passages[k]
					if p.x == i or p.y == i:
						_linked.erase(MineLayout.key(p.x, p.y))
						_l.passages.remove_at(k)
						break
				excluded[i] = 2 ## stays rock
				changed = true


# ---------- phase 3: loops ----------

func _braid() -> void:
	var rng: RandomNumberGenerator = _stream(3)
	var total: int = _n * _n
	var degree: PackedInt32Array = PackedInt32Array()
	degree.resize(total)
	for p: Vector2i in _l.passages:
		degree[p.x] += 1
		degree[p.y] += 1
	var braid: float = float(_zone.get("braid", 0.2))
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i: int in total:
		if _room_of[i] >= 0 or degree[i] != 1 or rng.randf() >= braid: ## a dead end is joined to a neighbour (some are kept: that is where the chests are)
			continue
		var options: Array[int] = []
		for d: Vector2i in dirs:
			var x: int = i % _n + d.x
			var y: int = i / _n + d.y
			if x < 0 or y < 0 or x >= _n or y >= _n:
				continue
			var j: int = y * _n + x
			if (degree[j] > 0 or _room_of[j] >= 0) and not _linked.has(MineLayout.key(i, j)) and (_room_of[j] < 0 or _room_of[j] != _room_of[i]):
				options.append(j)
		if not options.is_empty():
			var j: int = options[rng.randi() % options.size()]
			_link(i, j)
			degree[i] += 1
			degree[j] += 1
	for y: int in _n: ## a few more loops anywhere
		for x: int in _n:
			var a: int = y * _n + x
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				if x + step.x >= _n or y + step.y >= _n:
					continue
				var b: int = (y + step.y) * _n + x + step.x
				var used_a: bool = degree[a] > 0 or _room_of[a] >= 0
				var used_b: bool = degree[b] > 0 or _room_of[b] >= 0
				if used_a and used_b and not _linked.has(MineLayout.key(a, b)) and (_room_of[a] < 0 or _room_of[a] != _room_of[b]):
					if rng.randf() < braid * 0.12:
						_link(a, b)
	_l.cell_used.resize(total)
	_l.cell_room = _room_of.duplicate()
	degree.fill(0)
	for p: Vector2i in _l.passages:
		degree[p.x] += 1
		degree[p.y] += 1
	for i: int in total:
		_l.cell_used[i] = 1 if degree[i] > 0 or _room_of[i] >= 0 else 0


func _adjacency() -> void:
	var total: int = _n * _n
	_adj.clear()
	_adj.resize(total)
	for i: int in total:
		_adj[i] = PackedInt32Array()
	for p: Vector2i in _l.passages:
		_adj[p.x].append(p.y)
		_adj[p.y].append(p.x)
	for room: Dictionary in _l.rooms: ## inside a room all neighbouring cells are open to each other
		var cells: Rect2i = room.cells as Rect2i
		for y: int in range(cells.position.y, cells.end.y):
			for x: int in range(cells.position.x, cells.end.x):
				if x + 1 < cells.end.x:
					_adj[y * _n + x].append(y * _n + x + 1)
					_adj[y * _n + x + 1].append(y * _n + x)
				if y + 1 < cells.end.y:
					_adj[y * _n + x].append((y + 1) * _n + x)
					_adj[(y + 1) * _n + x].append(y * _n + x)


## Breadth first from a cell: fills `dist` (-1 unreachable) and `prev`.
func _bfs(from: int, dist: PackedInt32Array, prev: PackedInt32Array) -> void:
	dist.resize(_n * _n)
	prev.resize(_n * _n)
	dist.fill(-1)
	prev.fill(-1)
	dist[from] = 0
	var queue: PackedInt32Array = PackedInt32Array([from])
	var head: int = 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		for nb: int in _adj[c]:
			if dist[nb] < 0:
				dist[nb] = dist[c] + 1
				prev[nb] = c
				queue.append(nb)


# ---------- phase 4: entry, exit, station ----------

## A hall: two cells or more in both directions (room for stairs or a lift).
func _hall(room: Dictionary) -> bool:
	var size: Vector2i = (room.cells as Rect2i).size
	return size.x >= 2 and size.y >= 2


func _room_cell(room: int) -> int:
	var cells: Rect2i = _l.rooms[room].cells as Rect2i
	return cells.position.y * _n + cells.position.x


func _keys() -> void:
	var rng: RandomNumberGenerator = _stream(4)
	var dist: PackedInt32Array = PackedInt32Array()
	var prev: PackedInt32Array = PackedInt32Array()
	_l.entry_room = 0
	_bfs(_room_cell(0), dist, prev)
	_l.distance = dist
	var best: float = -1.0
	var longest: int = 0
	for room: Dictionary in _l.rooms:
		if int(room.id) != 0:
			longest = maxi(longest, dist[_room_cell(int(room.id))])
	var entry_center: Vector2 = Vector2((_l.rooms[0].center as Vector2i))
	for share: float in [0.8, 0.6, 0.4, 0.0]: ## the exit: among the rooms far away on the way the one farthest as the crow flies (a hall of two cells or more preferred); the way's share is relaxed until it is also far in space
		best = -1.0
		for room: Dictionary in _l.rooms:
			if int(room.id) == 0 or not _hall(room) or dist[_room_cell(int(room.id))] < int(share * float(longest)):
				continue
			var crow: float = entry_center.distance_to(Vector2(room.center as Vector2i))
			var score: float = crow + rng.randf() * 0.01
			if score > best:
				best = score
				_l.exit_room = int(room.id)
		if best >= 0.35 * float(_edge):
			break
	var exit_dist: float = float(dist[_room_cell(_l.exit_room)])
	_l.path_cells = int(exit_dist)
	var on_path: Dictionary = {}
	var c: int = _room_cell(_l.exit_room)
	while c >= 0:
		on_path[c] = true
		c = prev[c]
	best = -1000.0
	for room: Dictionary in _l.rooms: ## the station: halfway, in a room of its own beside the main way
		var id: int = int(room.id)
		if id == 0 or id == _l.exit_room or dist[_room_cell(id)] < 0:
			continue
		var rep: int = _room_cell(id)
		var score: float = -absf(float(dist[rep]) / maxf(exit_dist, 1.0) - 0.5) - (0.0 if not on_path.has(rep) else 0.15) - (0.0 if _hall(room) else 0.4) + rng.randf() * 0.001
		if score > best:
			best = score
			_l.station_room = id
	_l.entry = (_l.rooms[0].center as Vector2i)
	_l.exit = (_l.rooms[_l.exit_room].center as Vector2i)
	if _l.station_room >= 0:
		_l.station = (_l.rooms[_l.station_room].center as Vector2i)
	_mark_critical(prev, _room_cell(_l.exit_room))
	if _l.station_room >= 0:
		_mark_critical(prev, _room_cell(_l.station_room))
		var dist2: PackedInt32Array = PackedInt32Array()
		var prev2: PackedInt32Array = PackedInt32Array()
		_bfs(_room_cell(_l.station_room), dist2, prev2)
		_mark_critical(prev2, _room_cell(_l.exit_room))


func _mark_critical(prev: PackedInt32Array, from: int) -> void:
	var c: int = from
	while c >= 0 and prev[c] >= 0:
		_l.critical[MineLayout.key(c, prev[c])] = true
		c = prev[c]


# ---------- phase 5: carving ----------

func _fill(x0: int, y0: int, x1: int, y1: int) -> void:
	for y: int in range(maxi(y0, BORDER), mini(y1, _edge - BORDER - 1) + 1):
		var row: int = y * _edge
		for x: int in range(maxi(x0, BORDER), mini(x1, _edge - BORDER - 1) + 1):
			_l.tiles[row + x] = MineLayout.FLOOR


## A straight stretch `w` tiles wide through (x, y), horizontal or vertical.
func _stretch(a: Vector2i, b: Vector2i, w: int) -> void:
	var lo: int = -((w - 1) / 2)
	var hi: int = w / 2
	_fill(mini(a.x, b.x) + lo, mini(a.y, b.y) + lo, maxi(a.x, b.x) + hi, maxi(a.y, b.y) + hi)


func _carve_between(a: Vector2i, b: Vector2i, w: int) -> void:
	_stretch(a, Vector2i(b.x, a.y), w)
	_stretch(Vector2i(b.x, a.y), b, w)


func _cell_center(cell: int) -> Vector2i:
	return Vector2i((cell % _n) * CELL + CELL / 2, (cell / _n) * CELL + CELL / 2)


func _carve() -> void:
	var rng: RandomNumberGenerator = _stream(5)
	_l.tiles.resize(_edge * _edge)
	_l.tiles.fill(MineLayout.WALL)
	for room: Dictionary in _l.rooms:
		_carve_room(room, rng)
	var total: int = _n * _n
	_hub.resize(total)
	_hub.fill(-1)
	var reach: PackedInt32Array = PackedInt32Array() ## widest passage per cell
	reach.resize(total)
	var wide: Array = _zone.get("corridor_width", [3, 3]) as Array
	for p: Vector2i in _l.passages:
		var w: int = rng.randi_range(int(wide[0]), int(wide[1]))
		if _l.is_critical(p.x, p.y):
			w = maxi(w, 3)
		_l.widths[MineLayout.key(p.x, p.y)] = w
		reach[p.x] = maxi(reach[p.x], w)
		reach[p.y] = maxi(reach[p.y], w)
	for i: int in total:
		if _l.cell_used[i] == 0:
			continue
		var center: Vector2i = _cell_center(i)
		if _room_of[i] < 0:
			center += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
			center = Vector2i(clampi(center.x, BORDER + 1, _edge - BORDER - 3), clampi(center.y, BORDER + 1, _edge - BORDER - 3)) ## a corridor along the rim must keep its width
		_hub[i] = center.x * 65536 + center.y
	var degree: PackedInt32Array = PackedInt32Array()
	degree.resize(total)
	for p: Vector2i in _l.passages:
		degree[p.x] += 1
		degree[p.y] += 1
	for p: Vector2i in _l.passages:
		var a: Vector2i = Vector2i(_hub[p.x] >> 16, _hub[p.x] & 0xFFFF)
		var b: Vector2i = Vector2i(_hub[p.y] >> 16, _hub[p.y] & 0xFFFF)
		var w: int = int(_l.widths[MineLayout.key(p.x, p.y)])
		_carve_between(a, b, w)
		for end: int in [p.x, p.y]: ## a blob room is reached by a spoke from its middle
			if _room_of[end] >= 0 and String(_l.rooms[_room_of[end]].shape) == "blob":
				var hub: Vector2i = Vector2i(_hub[end] >> 16, _hub[end] & 0xFFFF)
				_carve_between(_l.rooms[_room_of[end]].center as Vector2i, hub, 3)
	_l.hubs = _hub.duplicate()
	for i: int in total: ## corridor joints are a little wider than the corridors, dead ends end in a small chamber
		if _hub[i] < 0 or _room_of[i] >= 0:
			continue
		var hub: Vector2i = Vector2i(_hub[i] >> 16, _hub[i] & 0xFFFF)
		var size: int = maxi(reach[i], 4 if degree[i] == 1 else 3)
		_stretch(hub, hub, size)


func _carve_room(room: Dictionary, rng: RandomNumberGenerator) -> void:
	var rect: Rect2i = room.rect as Rect2i
	if String(room.shape) == "rect":
		_fill(rect.position.x, rect.position.y, rect.end.x - 1, rect.end.y - 1)
		return
	var cx: float = float(rect.position.x) + float(rect.size.x) * 0.5
	var cy: float = float(rect.position.y) + float(rect.size.y) * 0.5
	var rx: float = float(rect.size.x) * 0.5
	var ry: float = float(rect.size.y) * 0.5
	var shift: float = rng.randf() * 100.0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var dx: float = (float(x) + 0.5 - cx) / rx
			var dy: float = (float(y) + 0.5 - cy) / ry
			if sqrt(dx * dx + dy * dy) + 0.32 * _noise.get_noise_2d(float(x) + shift, float(y)) < 0.98:
				_l.tiles[y * _edge + x] = MineLayout.FLOOR


# ---------- phase 6: erosion ----------

func _erode() -> void:
	var erosion: float = float(_zone.get("erosion", 0.1))
	var rounds: int = 1 if erosion < 0.2 else 2
	var salt: int = int(_mix(_l.world_seed, _l.level) & 0xFFFF)
	for pass_index: int in rounds: ## walls next to floor sometimes give way: alcoves and bumps, never a narrower passage
		var give: PackedInt32Array = PackedInt32Array()
		var p: float = erosion * (1.0 if pass_index == 0 else 0.6)
		for y: int in range(BORDER, _edge - BORDER):
			var row: int = y * _edge
			for x: int in range(BORDER, _edge - BORDER):
				if _l.tiles[row + x] == MineLayout.WALL:
					if _l.tiles[row + x - 1] == MineLayout.FLOOR or _l.tiles[row + x + 1] == MineLayout.FLOOR or _l.tiles[row + x - _edge] == MineLayout.FLOOR or _l.tiles[row + x + _edge] == MineLayout.FLOOR:
						if _hash2(x, y, salt + pass_index) < p:
							give.append(row + x)
		for index: int in give:
			_l.tiles[index] = MineLayout.FLOOR
	for y: int in range(BORDER, _edge - BORDER): ## one tile spikes of rock are smoothed away
		var row: int = y * _edge
		for x: int in range(BORDER, _edge - BORDER):
			if _l.tiles[row + x] == MineLayout.WALL:
				var open: int = int(_l.tiles[row + x - 1]) + int(_l.tiles[row + x + 1]) + int(_l.tiles[row + x - _edge]) + int(_l.tiles[row + x + _edge])
				if open >= 3:
					_l.tiles[row + x] = MineLayout.FLOOR
	_prune_islands()


## Floor that cannot be reached from the entry (specks cut off by a room's noise) becomes rock.
func _prune_islands() -> void:
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(_edge * _edge)
	var queue: PackedInt32Array = PackedInt32Array([_l.entry.y * _edge + _l.entry.x])
	seen[queue[0]] = 1
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		for step: int in [-1, 1, -_edge, _edge]:
			var nb: int = at + step
			if nb >= 0 and nb < _edge * _edge and seen[nb] == 0 and _l.tiles[nb] == MineLayout.FLOOR:
				seen[nb] = 1
				queue.append(nb)
	for i: int in _edge * _edge:
		if _l.tiles[i] == MineLayout.FLOOR and seen[i] == 0:
			_l.tiles[i] = MineLayout.WALL
	_l.floor_tiles = queue.size()


# ---------- phase 7: room types ----------

func _types() -> void:
	var rng: RandomNumberGenerator = _stream(7)
	var degree: PackedInt32Array = PackedInt32Array()
	degree.resize(_n * _n)
	for p: Vector2i in _l.passages:
		degree[p.x] += 1
		degree[p.y] += 1
	for room: Dictionary in _l.rooms:
		var cells: Rect2i = room.cells as Rect2i
		var d: int = 0
		for y: int in range(cells.position.y, cells.end.y):
			for x: int in range(cells.position.x, cells.end.x):
				d += degree[y * _n + x]
		room.degree = d
	_l.rooms[_l.entry_room].type = "entry"
	_l.rooms[_l.exit_room].type = "exit"
	if _l.station_room >= 0:
		_l.rooms[_l.station_room].type = "rest"
	var weights: Dictionary = _zone.get("room_weights", {}) as Dictionary
	var count: int = _l.rooms.size()
	var caps: Dictionary = {"treasure": maxi(1, count / 10), "airshaft": maxi(1, count / 8), "forge": maxi(1, count / 6)}
	var used: Dictionary = {}
	var order: Array = []
	for room: Dictionary in _l.rooms:
		if String(room.type) == "":
			order.append(room)
	_shuffle(order, rng)
	for room: Dictionary in order:
		var options: Array[String] = []
		var total: float = 0.0
		for type: String in weights:
			var area: int = int(room.area)
			if area < int(TYPE_MIN_CELLS.get(type, 1)) or area > int(TYPE_MAX_CELLS.get(type, 99)):
				continue
			if type == "junction" and int(room.degree) < 3:
				continue
			if type == "treasure" and int(room.degree) != 1:
				continue
			if caps.has(type) and int(used.get(type, 0)) >= int(caps[type]):
				continue
			options.append(type)
			total += float(weights[type])
		if options.is_empty():
			room.type = "empty"
			continue
		var roll: float = rng.randf() * total
		var chosen: String = options[options.size() - 1]
		for type: String in options:
			roll -= float(weights[type])
			if roll <= 0.0:
				chosen = type
				break
		room.type = chosen
		used[chosen] = int(used.get(chosen, 0)) + 1
