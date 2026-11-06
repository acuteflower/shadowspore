class_name MineClutter
extends RefCounted
## What makes a level look lived in and fallen apart (docs/mine.md section 7), spread over the whole floor by rule: the old rail line along the way entry -> lift ->
## exit, heaps of rubble and splintered planks at the foot of the walls, tools and buckets where somebody dropped them, a ladder or a rusty chain on the wall,
## glowing mushrooms in the damp, a lantern still burning on the floor. Nothing here blocks: every piece is flat or small, so the walkways the room phases kept
## clear stay clear. Pure function of the layout with its own random stream; runs after the rooms and the rocks (it keeps clear of what is already there).

const WALL_KINDS: Array = [["rubble_a", 3.0], ["rubble_b", 2.4], ["rubble_c", 1.4], ["planks", 2.4], ["pickaxe", 1.4], ["bucket", 1.2], ["rope", 1.2], ["mushrooms", 2.4], ["bones", 0.3], ["lantern_floor", 0.6]]
const OPEN_KINDS: Array = [["rubble_b", 2.4], ["rubble_a", 1.4], ["planks", 2.0], ["pickaxe", 1.0], ["bucket", 0.8], ["bones", 0.25], ["rope", 0.8]]
const WALL_DECOR: Array = [["ladder", 1.0], ["chain", 1.6]]
const SPACING: int = 2

var _l: MineLayout
var _rng: RandomNumberGenerator
var _taken: Dictionary = {} ## tiles that already have something
var _rocks: Dictionary = {}
var _laid: Dictionary = {} ## (tile, piece) -> true


func dress(layout: MineLayout) -> void:
	_l = layout
	_rng = RandomNumberGenerator.new()
	_rng.seed = MineGenerator._mix(MineGenerator._mix(_l.world_seed, _l.level), 500)
	for c: Vector2i in _l.chunk_props:
		for entry: Dictionary in _l.chunk_props[c] as Array:
			_mark(Vector2i(floori(float(entry.x) / 16.0), floori(float(entry.y) / 16.0)), 1)
	for c: Vector2i in _l.chunk_rocks:
		for rock: Dictionary in _l.chunk_rocks[c] as Array:
			_mark(Vector2i(floori(float(rock.x) / 16.0), floori(float(rock.y) / 16.0)), 1)
	_rails()
	_scatter()


func _mark(t: Vector2i, radius: int) -> void:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			_taken[t + Vector2i(dx, dy)] = true


func _floor(x: int, y: int) -> bool:
	return _l.is_floor(x, y)


func _free(t: Vector2i) -> bool:
	return _floor(t.x, t.y) and _l.solid[t.y * _l.edge + t.x] == 0 and not _taken.has(t)


# ---------- the rail line ----------

## Rails along the corridors of the main way, of every corridor that leaves a junction and of a share of the others. A line is one unbroken track: it follows the
## corridor's own bends (the same L the generator carved: along x at the first hub's row, then along y) and in a room it runs on to the room's middle, as one chain
## of neighbouring tiles with the corridor, so every piece joins the next. A tile can carry several pieces, so tracks cross and branch where they meet.
func _rails() -> void:
	for p: Vector2i in _l.passages:
		if _l.hubs[p.x] < 0 or _l.hubs[p.y] < 0:
			continue
		var junction: bool = false
		for cell: int in [p.x, p.y]:
			var room: int = _l.cell_room[cell]
			junction = junction or (room >= 0 and String(_l.rooms[room].type) == "junction")
		if not _l.critical.has(MineLayout.key(p.x, p.y)) and not junction and _rng.randf() > 0.28:
			continue
		var a: Vector2i = Vector2i(_l.hubs[p.x] >> 16, _l.hubs[p.x] & 0xFFFF)
		var b: Vector2i = Vector2i(_l.hubs[p.y] >> 16, _l.hubs[p.y] & 0xFFFF)
		var way: Array[Vector2i] = _leg(a, b)
		var room_a: int = _l.cell_room[p.x]
		var room_b: int = _l.cell_room[p.y]
		if room_a >= 0 and room_a == room_b:
			continue
		var first: int = 0 ## the first tile of the way outside its room
		var last: int = way.size() - 1
		if room_a >= 0:
			while first < way.size() and (_l.rooms[room_a].rect as Rect2i).has_point(way[first]):
				first += 1
		if room_b >= 0:
			while last >= 0 and (_l.rooms[room_b].rect as Rect2i).has_point(way[last]):
				last -= 1
		if first > last:
			continue
		var chain: Array[Vector2i] = []
		if room_a >= 0: ## from the middle of the room to the last tile inside it (the way's next tile is the first outside)
			var door_a: int = first - 1 if first >= 1 else 0
			chain.append_array(_leg(_l.rooms[room_a].center as Vector2i, way[door_a]))
			first = door_a + 1
		chain.append_array(way.slice(first, last + 1))
		if room_b >= 0:
			var door_b: int = last + 1 if last + 1 < way.size() else way.size() - 1
			var tail: Array[Vector2i] = _leg(_l.rooms[room_b].center as Vector2i, way[door_b])
			tail.reverse()
			if not chain.is_empty() and chain[chain.size() - 1] == tail[0]:
				tail.remove_at(0)
			chain.append_array(tail)
		_track(chain)


## The tiles from a to b: along x at a's row, then along y at b's column.
func _leg(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var step_x: int = 1 if b.x >= a.x else -1
	for x: int in range(a.x, b.x + step_x, step_x):
		path.append(Vector2i(x, a.y))
	var step_y: int = 1 if b.y >= a.y else -1
	for y: int in range(a.y + step_y, b.y + step_y, step_y):
		path.append(Vector2i(b.x, y))
	return path


## Lays rails along a path of neighbouring tiles: straight pieces, a quarter turn at every bend.
func _track(path: Array[Vector2i]) -> void:
	if path.size() < 2:
		return
	for i: int in path.size():
		var dirs: Array[Vector2i] = []
		if i > 0:
			dirs.append(path[i - 1] - path[i])
		if i < path.size() - 1:
			dirs.append(path[i + 1] - path[i])
		var horizontal: bool = false
		var vertical: bool = false
		for d: Vector2i in dirs:
			horizontal = horizontal or d.x != 0
			vertical = vertical or d.y != 0
		var index: int = 0
		if horizontal and vertical: ## a bend: the two sides it joins
			var east: bool = dirs.has(Vector2i(1, 0))
			var south: bool = dirs.has(Vector2i(0, 1))
			index = (5 if south else 4) if east else (2 if south else 3) ## the quarter-turn tiles of the atlas: 2 joins W-S, 3 W-N, 4 E-N, 5 E-S
		elif vertical:
			index = 1
		_rail(path[i], index)


func _rail(t: Vector2i, index: int) -> void:
	if not _floor(t.x, t.y) or _l.solid[t.y * _l.edge + t.x] != 0:
		return
	var key: int = (t.y * _l.edge + t.x) * 8 + index
	if _laid.has(key):
		return
	_laid[key] = true
	_l.add_rail(t, index)
	_taken[t] = true


# ---------- the things lying about ----------

func _pick(table: Array) -> String:
	var total: float = 0.0
	for row: Array in table:
		total += float(row[1])
	var roll: float = _rng.randf() * total
	for row: Array in table:
		roll -= float(row[1])
		if roll <= 0.0:
			return String(row[0])
	return String((table[0] as Array)[0])


func _scatter() -> void:
	var tiles: Array[Vector2i] = []
	for y: int in range(3, _l.edge - 3):
		for x: int in range(3, _l.edge - 3):
			if _floor(x, y) and _l.solid[y * _l.edge + x] == 0:
				tiles.append(Vector2i(x, y))
	for i: int in range(tiles.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Vector2i = tiles[i]
		tiles[i] = tiles[j]
		tiles[j] = tmp
	var zone: Dictionary = MineManager.zone(_l.level)
	var target: int = int(float(_l.floor_tiles) / 1000.0 * float(zone.get("clutter", 30.0)))
	var placed: int = 0
	for t: Vector2i in tiles:
		if placed >= target:
			break
		if not _free(t):
			continue
		var at_wall: bool = not _floor(t.x, t.y - 1)
		var kind: String
		var at: Vector2
		if at_wall and _rng.randf() < 0.22 and _floor(t.x - 1, t.y) and _floor(t.x + 1, t.y): ## on the wall face itself
			kind = _pick(WALL_DECOR)
			at = Vector2(t.x * 16.0 + 8.0 + _rng.randf_range(-3.0, 3.0), t.y * 16.0 + 3.0)
		elif at_wall:
			kind = _pick(WALL_KINDS)
			at = Vector2(t.x * 16.0 + 8.0 + _rng.randf_range(-4.0, 4.0), t.y * 16.0 + 9.0 + _rng.randf_range(0.0, 4.0))
		elif _rng.randf() < 0.6 and _open(t):
			kind = _pick(OPEN_KINDS)
			at = Vector2(t.x * 16.0 + 8.0 + _rng.randf_range(-5.0, 5.0), t.y * 16.0 + 10.0 + _rng.randf_range(-3.0, 4.0))
		else:
			continue
		var extra: Dictionary = {"nosolid": true}
		if kind == "mushrooms" or kind == "lantern_floor":
			extra["spec"] = {"pulse": [1.3, 0.3]} if kind == "mushrooms" else {}
		if kind == "ladder" or kind == "chain":
			extra["spec"] = {"z": -4}
		_l.add_prop(kind, at, extra)
		if kind == "mushrooms":
			_l.add_light(at + Vector2(0.0, -8.0), 40, 0.45, "6ff0e0", 0.1)
		elif kind == "lantern_floor":
			_l.add_light(at + Vector2(0.0, -4.0), 70, 0.75, "ffb561", 0.2)
		_mark(t, SPACING - 1)
		placed += 1


func _open(t: Vector2i) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if not _floor(t.x + dx, t.y + dy):
				return false
	return true
