class_name MineRocks
extends RefCounted
## Rocks to mine (docs/mine.md section 8): single rocks against the walls (never in the way: the body must still get everywhere with them in place), and
## collapses, piles of rocks across a corridor that is not on the way entry -> lift -> exit: a shortcut or a side room behind them, to be mined open.
## Pure function of the layout, own random stream; results go into the layout's per-chunk rock lists, `MineLevel` spawns them as `MineRock`s.

const SMALL: Array[int] = [0, 1, 3, 5] ## rock variants (data/plants.json "rock") that fit into a corridor
const ANY: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
const MIN_SPACING: float = 4.0

var _l: MineLayout
var _zone: Dictionary
var _rng: RandomNumberGenerator
var _near: Dictionary = {} ## tiles within two tiles of a prop or rock
var _grid: Dictionary = {}


func dress(layout: MineLayout) -> void:
	_l = layout
	_zone = MineManager.zone(layout.level)
	_rng = RandomNumberGenerator.new()
	_rng.seed = MineGenerator._mix(MineGenerator._mix(_l.world_seed, _l.level), 300)
	for c: Vector2i in _l.chunk_props:
		for entry: Dictionary in _l.chunk_props[c] as Array:
			_mark(Vector2i(floori(float(entry.x) / 16.0), floori(float(entry.y) / 16.0)), 2)
	_collapses()
	_scatter()


func _mark(tile: Vector2i, radius: int) -> void:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			_near[tile + Vector2i(dx, dy)] = true


func _floor(x: int, y: int) -> bool:
	return _l.is_floor(x, y)


## A rock only stands where a 2 x 2 body still passes at both sides of it: floor in a 5 x 3 block (the rock's row and the two below), so never in a corridor mouth.
func _open(x: int, y: int) -> bool:
	for dy: int in 3:
		for dx: int in range(-2, 3):
			if not _floor(x + dx, y + dy):
				return false
	return true


func _weighted(options: Array[int]) -> int:
	var weights: Array = DataRegistry.get_entry("plants", "rock").get("weights", [3, 3, 2, 1, 2, 2, 2, 1]) as Array
	var total: float = 0.0
	for v: int in options:
		total += float(weights[v])
	var roll: float = _rng.randf() * total
	for v: int in options:
		roll -= float(weights[v])
		if roll <= 0.0:
			return v
	return options[options.size() - 1]


func _scatter() -> void:
	var density: float = float(_zone.get("rock_density", 14.0))
	var target: int = int(float(_l.floor_tiles) / 1000.0 * density)
	var spots: Array[Vector2i] = []
	for y: int in range(3, _l.edge - 3):
		for x: int in range(3, _l.edge - 3):
			if _floor(x, y) and not _floor(x, y - 1) and _floor(x, y + 1) and _floor(x, y + 2) and _floor(x, y + 3) and _open(x, y) and _l.solid[y * _l.edge + x] == 0 and not _near.has(Vector2i(x, y)):
				spots.append(Vector2i(x, y))
	for i: int in range(spots.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Vector2i = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	var placed: int = 0
	for t: Vector2i in spots:
		if placed >= target:
			break
		if _near.has(t) or _crowded(t):
			continue
		var in_room: bool = _l.cell_room[_l.cell_of_tile(t.x, t.y)] >= 0
		var roomy: bool = in_room and _floor(t.x - 2, t.y) and _floor(t.x + 2, t.y) and _floor(t.x, t.y + 3)
		var variant: int = _weighted(ANY if roomy else SMALL)
		_l.add_rock("mine_rock", Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 11.0), variant)
		_l.solid[t.y * _l.edge + t.x] = 1
		_claim(t)
		_mark(t, 1)
		placed += 1


func _crowded(t: Vector2i) -> bool:
	var c: Vector2i = Vector2i(t.x / 8, t.y / 8)
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			for other: Vector2i in _grid.get(c + Vector2i(dx, dy), []) as Array:
				if Vector2(other).distance_to(Vector2(t)) < MIN_SPACING:
					return true
	return false


func _claim(t: Vector2i) -> void:
	var c: Vector2i = Vector2i(t.x / 8, t.y / 8)
	if not _grid.has(c):
		_grid[c] = [] as Array[Vector2i]
	(_grid[c] as Array[Vector2i]).append(t)


## A pile of rocks across a straight stretch of a passage that is not on the main way.
func _collapses() -> void:
	var chance: float = float(_zone.get("collapse_chance", 0.0))
	var limit: int = maxi(1, _l.edge / 24)
	var made: int = 0
	for p: Vector2i in _l.passages:
		if made >= limit:
			return
		if _l.is_critical(p.x, p.y) or _rng.randf() > chance or _l.hubs[p.x] < 0 or _l.hubs[p.y] < 0:
			continue
		var a: Vector2i = Vector2i(_l.hubs[p.x] >> 16, _l.hubs[p.x] & 0xFFFF)
		var b: Vector2i = Vector2i(_l.hubs[p.y] >> 16, _l.hubs[p.y] & 0xFFFF)
		var w: int = int(_l.widths.get(MineLayout.key(p.x, p.y), 3))
		var lo: int = -((w - 1) / 2)
		var hi: int = w / 2
		var at: Vector2i = Vector2i(-1, -1)
		var horizontal: bool = true
		if absi(b.x - a.x) >= 6: ## the first leg of the corridor runs along x at the row of the first hub
			at = Vector2i((a.x + b.x) / 2, a.y)
		elif absi(b.y - a.y) >= 6: ## else the second leg runs along y at the column of the second hub
			at = Vector2i(b.x, (a.y + b.y) / 2)
			horizontal = false
		if at.x < 0 or not _straight(at, horizontal, lo, hi) or _near.has(at):
			continue
		var cross: Vector2 = Vector2(at.x * 16.0 + 8.0, at.y * 16.0 + 8.0)
		for k: int in range(lo, hi + 1): ## one rock per tile across the corridor (the world keys props by tile), staggered along it so no gap is left
			var stagger: float = (4.0 if (k - lo) % 2 == 0 else -4.0) + _rng.randf_range(-1.5, 1.5)
			var pos: Vector2 = Vector2(at.x * 16.0 + 8.0 + stagger, (at.y + k) * 16.0 + 11.0) if horizontal else Vector2((at.x + k) * 16.0 + 8.0, at.y * 16.0 + 8.0 + stagger)
			_l.add_rock("mine_collapse", pos, SMALL[_rng.randi() % SMALL.size()])
		_l.collapses.append({"key": MineLayout.key(p.x, p.y), "x": cross.x, "y": cross.y})
		_mark(at, 3)
		made += 1


## Is the corridor across `at` exactly as wide as it should be, rock on both sides, and not inside a room?
func _straight(at: Vector2i, horizontal: bool, lo: int, hi: int) -> bool:
	if _l.cell_room[_l.cell_of_tile(at.x, at.y)] >= 0:
		return false
	for k: int in range(lo - 1, hi + 2):
		var t: Vector2i = at + (Vector2i(0, k) if horizontal else Vector2i(k, 0))
		var inside: bool = k >= lo and k <= hi
		if _floor(t.x, t.y) != inside:
			return false
		var behind: Vector2i = t + (Vector2i(1, 0) if horizontal else Vector2i(0, 1))
		if inside and not _floor(behind.x, behind.y):
			return false
	return true
