class_name MineRooms
extends RefCounted
## Dresses the rooms of a level by their type (docs/mine.md section 5): the entry hall with the stairs up, the exit hall with the stairs down, the rest room
## with the lift and a fire, junctions with rails and a cart, stores, bunk rooms, spider nests, wet caves, air shafts, treasure rooms. Pure function of the
## layout with a random stream per room, so one room never shifts another. Everything goes into the layout's lists (props, rails, lights).
## Footprints: a prop takes a rectangle of tiles that must be free floor; a walkway from every door of the room to its middle is kept clear first.

const FOOT: Dictionary = { ## kind -> [tiles wide, tiles deep] (the row of the position and the rows above... no: deep rows towards the north)
	"crates": [4, 1], "barrel": [1, 1], "sacks": [3, 1], "bunk": [5, 1], "table": [5, 1], "stool": [1, 1], "chest": [3, 1], "cart": [5, 1], "cart_loaded": [5, 1],
	"nest": [5, 2], "stalagmites": [3, 1], "waysign": [1, 1], "shelf": [5, 1], "pots": [3, 1], "post": [1, 1], "bones": [3, 1], "notes": [1, 1], "stairs_up": [5, 1],
	"stairs_down": [5, 3], "winch": [7, 2], "anvil": [2, 1], "forge": [5, 2], "quench": [3, 1], "crystal_a": [3, 1], "crystal_b": [3, 1], "crystal_big": [3, 1], "void_pod": [1, 1],
	"void_crack": [3, 1], "void_eyes": [2, 1],
}
const DOWN: Array[String] = ["winch"] ## footprints that run from the wall tile towards the south (they stand against the back wall) instead of towards the north
const FLAT: Array[String] = ["bones", "notes", "web", "puddle_a", "puddle_b", "void_crack", "void_eyes"] ## lie on the floor: no footprint blocking, drawn below everything

var _l: MineLayout
var _zone: Dictionary
var _taken: Dictionary = {} ## Vector2i -> true
var _rng: RandomNumberGenerator
var _room: Dictionary
var _doors: Dictionary = {} ## room id -> Array[Vector2i] (cell inside, cell outside)
var _key_tiles: Dictionary = {} ## tiles of the key props (stairs, lift, fire): their solids stay when a room is cleared
const BLOCKING: Array[String] = ["crates", "barrel", "sacks", "bunk", "table", "stool", "cart", "cart_loaded", "nest", "stalagmites", "waysign", "shelf", "pots", "post", "anvil", "forge", "quench", "crystal_a", "crystal_b", "crystal_big", "void_pod"]


func dress(layout: MineLayout) -> void:
	_l = layout
	_zone = MineManager.zone(layout.level)
	if _l.solid.size() != _l.edge * _l.edge:
		_l.solid.resize(_l.edge * _l.edge)
	_index_doors()
	for room: Dictionary in _l.rooms:
		_room = room
		_rng = RandomNumberGenerator.new()
		_rng.seed = MineGenerator._mix(MineGenerator._mix(_l.world_seed, _l.level), 1000 + int(room.id))
		_walkways(3 if String(room.type) in ["entry", "exit", "rest"] else 5)
		match String(room.type):
			"entry": _entry()
			"exit": _exit()
			"rest": _rest()
			"junction": _junction()
			"storage": _storage()
			"bunks": _bunks()
			"spider_nest": _nest()
			"forge": _forge()
			"crystal": _crystal()
			"voidroom": _voidroom()
			"wet": _wet()
			"airshaft": _airshaft()
			"treasure": _treasure()
			_: _empty()
	_repair()


# ---------- helpers ----------

func _solid(t: Vector2i, key: bool = false) -> void:
	if t.x >= 0 and t.y >= 0 and t.x < _l.edge and t.y < _l.edge:
		_l.solid[t.y * _l.edge + t.x] = 1
		if key:
			_key_tiles[t] = true


func _floor(t: Vector2i) -> bool:
	return _l.is_floor(t.x, t.y)


func _free(t: Vector2i) -> bool:
	return _floor(t) and not _taken.has(t)


func _center() -> Vector2i:
	return _room.center as Vector2i


func _rect() -> Rect2i:
	return _room.rect as Rect2i


func _cell_hub(cell: int) -> Vector2i:
	return Vector2i(_l.hubs[cell] >> 16, _l.hubs[cell] & 0xFFFF) if _l.hubs[cell] >= 0 else Vector2i(-1, -1)


func _reserve(a: Vector2i, b: Vector2i, w: int) -> void:
	var lo: int = -(w / 2)
	var hi: int = w / 2
	for pass_index: int in 2: ## an L: along x, then along y
		var from: Vector2i = a if pass_index == 0 else Vector2i(b.x, a.y)
		var to: Vector2i = Vector2i(b.x, a.y) if pass_index == 0 else b
		for y: int in range(mini(from.y, to.y) + lo, maxi(from.y, to.y) + hi + 1):
			for x: int in range(mini(from.x, to.x) + lo, maxi(from.x, to.x) + hi + 1):
				_taken[Vector2i(x, y)] = true


## Keeps the way from every door of the room to its middle clear.
func _walkways(width: int = 5) -> void:
	var id: int = int(_room.id)
	var middle: Vector2i = _center()
	for pair: Vector2i in _doors.get(id, []) as Array: ## x: the cell inside the room, y: the cell outside
		var inside: int = pair.x
		var outside: int = pair.y
		var door: Vector2i = _cell_hub(inside)
		if door.x < 0:
			continue
		_reserve(middle, door, width)
		var far: Vector2i = _cell_hub(outside)
		if far.x >= 0: ## the same L as the generator carved: from the hub of the lower cell index to the higher one
			_reserve(door if inside < outside else far, far if inside < outside else door, width)


## Every passage that leaves a room, listed per room (once for the whole level).
func _index_doors() -> void:
	_doors.clear()
	for p: Vector2i in _l.passages:
		for pair: Array in [[p.x, p.y], [p.y, p.x]]:
			var inside: int = _l.cell_room[int(pair[0])]
			if inside >= 0 and _l.cell_room[int(pair[1])] != inside:
				if not _doors.has(inside):
					_doors[inside] = [] as Array[Vector2i]
				(_doors[inside] as Array[Vector2i]).append(Vector2i(int(pair[0]), int(pair[1])))


## Tiles in the room that have rock to their north (where things hang or lean against the wall), left to right.
func _back_wall() -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var rect: Rect2i = _rect()
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if _floor(Vector2i(x, y)) and not _floor(Vector2i(x, y - 1)) and _l.cell_room[_l.cell_of_tile(x, y)] == int(_room.id):
				found.append(Vector2i(x, y))
	return found


func _shuffled(list: Array[Vector2i]) -> Array[Vector2i]:
	var copy: Array[Vector2i] = list.duplicate()
	for i: int in range(copy.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Vector2i = copy[i]
		copy[i] = copy[j]
		copy[j] = tmp
	return copy


func _footprint(kind: String, at: Vector2i) -> Array[Vector2i]:
	var f: Array = FOOT.get(kind, [1, 1]) as Array
	var tiles: Array[Vector2i] = []
	for dy: int in int(f[1]):
		for dx: int in int(f[0]):
			tiles.append(Vector2i(at.x - (int(f[0]) - 1) / 2 + dx, at.y + dy if kind in DOWN else at.y - dy))
	return tiles


## Puts a prop with its feet on the tile `at` (x centred, y the front row) if its footprint is free floor; flat things need only floor.
func _place(kind: String, at: Vector2i, shift: Vector2 = Vector2.ZERO, extra: Dictionary = {}) -> bool:
	var tiles: Array[Vector2i] = _footprint(kind, at)
	for t: Vector2i in tiles:
		if (kind in FLAT and not _floor(t)) or (kind not in FLAT and not _free(t)):
			return false
	if kind not in FLAT:
		for t: Vector2i in tiles:
			_taken[t] = true
			_solid(t)
	_l.add_prop(kind, Vector2(at.x * 16.0 + 8.0 + shift.x, at.y * 16.0 + 13.0 + shift.y), extra)
	return true


## Tries wall spots in random order until `kind` fits; returns whether it was placed.
func _against_wall(kind: String, tries: int = 40) -> bool:
	var spots: Array[Vector2i] = _shuffled(_back_wall())
	for i: int in mini(tries, spots.size()):
		if _place(kind, spots[i], Vector2(0.0, -6.0)):
			return true
	return false


func _anywhere(kind: String, margin: int = 1, tries: int = 40) -> bool:
	var rect: Rect2i = _rect()
	for i: int in tries:
		var t: Vector2i = Vector2i(_rng.randi_range(rect.position.x + margin, rect.end.x - 1 - margin), _rng.randi_range(rect.position.y + margin, rect.end.y - 1 - margin))
		if _place(kind, t):
			return true
	return false


func _lamps(count: int) -> void:
	if float(_zone.get("lamp_spacing", 0)) <= 0.0:
		return
	var spots: Array[Vector2i] = _shuffled(_back_wall())
	var placed: Array[Vector2i] = []
	for t: Vector2i in spots:
		if placed.size() >= count:
			break
		var far: bool = true
		for other: Vector2i in placed:
			if Vector2(other).distance_to(Vector2(t)) < 5.0:
				far = false
		if far and _floor(t + Vector2i(1, 0)) and not _floor(t + Vector2i(1, -1)) and not _floor(t + Vector2i(-1, -1)):
			var dead: bool = _rng.randf() < float(_zone.get("lamp_gap", 0.0))
			var foot: Vector2 = Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 1.0)
			_l.add_prop("lamp_dead" if dead else "lamp", foot)
			if not dead:
				_l.add_light(foot + Vector2(5.0, 2.0), int(MineDecorator.LAMP_LIGHT.radius), float(MineDecorator.LAMP_LIGHT.energy), String(MineDecorator.LAMP_LIGHT.color), float(MineDecorator.LAMP_LIGHT.flicker))
			placed.append(t)


func _extra(n: int, kinds: Array[String]) -> void:
	for i: int in n:
		_anywhere(kinds[_rng.randi() % kinds.size()])


func _rails(length_each_side: int) -> void:
	var m: Vector2i = _center()
	var rect: Rect2i = _rect()
	var horizontal: bool = rect.size.x >= rect.size.y
	var step: Vector2i = Vector2i(1, 0) if horizontal else Vector2i(0, 1)
	for dir: int in [-1, 1]:
		for i: int in range(length_each_side + 1):
			var t: Vector2i = m + step * dir * i
			if not _floor(t):
				break
			_l.add_rail(t, 0 if horizontal else 1)
			if dir == 1 or i > 0:
				pass
	_l.add_rail(m, 0 if horizontal else 1)


# ---------- the key places ----------

func _entry() -> void:
	var middle: Vector2i = _center()
	var top: Vector2i = _spot("stairs_up", true)
	_taken[middle] = true
	for t: Vector2i in _footprint("stairs_up", top):
		_taken[t] = true
		_solid(t, true)
	_l.add_prop("stairs_up", Vector2(top.x * 16.0 + 8.0, top.y * 16.0 + 8.0), {"id": "stairs_up"})
	_l.entry_stairs = Vector2i(top.x, top.y + 1)
	_lamps(4)
	_extra(2, ["crates", "barrel"] as Array[String])
	_place("waysign", middle + Vector2i(4, 2))
	_taken.erase(middle)


## Where a prop of this size fits clear of the walkways with its whole footprint inside the room: against the back wall if `need_wall`, preferably near the
## middle of the room; the nearest back wall tile if nothing fits.
func _spot(kind: String, need_wall: bool) -> Vector2i:
	var rect: Rect2i = _rect()
	var middle: Vector2i = _center()
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: float = 1e9
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var t: Vector2i = Vector2i(x, y)
			if not _floor(t) or (need_wall and _floor(t + Vector2i(0, -1))):
				continue
			if not _footprint(kind, t).all(func(q: Vector2i) -> bool: return _free(q) and rect.has_point(q)):
				continue
			var score: float = float(absi(x - middle.x)) + (0.0 if need_wall else float(absi(y - middle.y)))
			if score < best_score:
				best_score = score
				best = t
	if best.x >= 0:
		return best
	var wall: Array[Vector2i] = _back_wall()
	return wall[0] if not wall.is_empty() else middle


func _exit() -> void:
	var middle: Vector2i = _center()
	for t: Vector2i in _footprint("stairs_down", middle + Vector2i(0, 1)):
		_taken[t] = true
		if t.y < middle.y + 1: ## the front row stays open: that is where one stands
			_solid(t, true)
	_l.add_prop("stairs_down", Vector2(middle.x * 16.0 + 8.0, middle.y * 16.0 + 14.0), {"id": "stairs_down"})
	_l.exit_stairs = middle
	_lamps(4)
	_extra(2, ["barrel", "crates", "sacks"] as Array[String])
	_anywhere("bones")


func _rest() -> void:
	var middle: Vector2i = _center()
	var best: Vector2i = _spot("winch", false)
	for t: Vector2i in _footprint("winch", best):
		_taken[t] = true
		_solid(t, true)
	_l.add_prop("winch", Vector2(best.x * 16.0 + 8.0, (best.y + 1) * 16.0 + 12.0), {"id": "winch"})
	_l.station_winch = best + Vector2i(0, 1)
	var pit: Vector2i = middle + Vector2i(0, 2)
	for t: Vector2i in [pit, pit + Vector2i(-1, 0), pit + Vector2i(1, 0), pit + Vector2i(0, -1)]:
		_taken[t] = true
		_solid(t, true)
	var fire: Vector2 = Vector2(pit.x * 16.0 + 8.0, pit.y * 16.0 + 12.0)
	_l.add_prop("fire_pit", fire)
	_l.add_light(fire + Vector2(0, -8), 118, 1.3, "ff9448", 0.35)
	_place("seat_log", pit + Vector2i(-3, 1))
	_place("seat_stump", pit + Vector2i(3, 0))
	_l.rest_fire = pit
	_lamps(4)
	_extra(3, ["crates", "barrel", "sacks", "pots"] as Array[String])
	_place("notes", pit + Vector2i(0, 3))


# ---------- the other rooms ----------

func _junction() -> void: ## its rails are laid by MineClutter: from every door to the middle
	var cart_at: Vector2i = _center() + Vector2i(4, 0) if _rect().size.x >= _rect().size.y else _center() + Vector2i(0, 4)
	var cart: String = "cart_loaded" if _rng.randf() < 0.5 else "cart"
	var rr: Rect2i = _rect()
	if maxi(rr.size.x, rr.size.y) >= 11 and mini(rr.size.x, rr.size.y) >= 6 and _footprint(cart, cart_at).all(func(t: Vector2i) -> bool: return _floor(t) and rr.has_point(t)):
		for t: Vector2i in _footprint(cart, cart_at):
			_taken[t] = true
			_solid(t)
		_l.add_prop(cart, Vector2(cart_at.x * 16.0 + 8.0, cart_at.y * 16.0 + 12.0))
	_anywhere("waysign")
	_lamps(2)
	_extra(1, ["post", "barrel"] as Array[String])


func _storage() -> void:
	_lamps(2)
	for i: int in _rng.randi_range(2, 3):
		_against_wall(["crates", "sacks", "shelf", "pots"][_rng.randi() % 4])
	_extra(_rng.randi_range(2, 4), ["barrel", "crates", "sacks"] as Array[String])
	if _rng.randf() < 0.4:
		_anywhere("cart_loaded")


func _bunks() -> void:
	_lamps(2)
	var wall: Array[Vector2i] = _shuffled(_back_wall())
	var bunks: int = 0
	for t: Vector2i in wall:
		if bunks >= _rng.randi_range(2, 3):
			break
		if _place("bunk", t, Vector2(0, -6)):
			bunks += 1
	var table_at: Vector2i = _center() + Vector2i(0, 1)
	if _place("table", table_at):
		_place("stool", table_at + Vector2i(-2, 1))
		_place("stool", table_at + Vector2i(2, 1))
		_l.add_prop("notes", Vector2(table_at.x * 16.0 + 8.0, table_at.y * 16.0 - 14.0), {"id": "notes"})
	_extra(1, ["pots", "barrel"] as Array[String])


func _nest() -> void:
	_place("nest", _center() + Vector2i(1, 1))
	var rect: Rect2i = _rect()
	for corner: Vector2i in [Vector2i(rect.position.x, rect.position.y), Vector2i(rect.end.x - 1, rect.position.y)]:
		if _floor(corner):
			_l.add_prop("web", Vector2(corner.x * 16.0 + 8.0, corner.y * 16.0 + 2.0), {"spec": {"z": -5, "flip": corner.x > rect.position.x}})
	for i: int in 2:
		_anywhere("bones")
	_l.add_light(Vector2((_center().x + 1) * 16.0 + 8.0, (_center().y + 1) * 16.0), 70, 0.7, "b040d8", 0.25) ## the eggs glow faintly


func _wet() -> void:
	var rect: Rect2i = _rect()
	for i: int in _rng.randi_range(3, 6):
		var kind: String = "puddle_a" if _rng.randf() < 0.55 else "puddle_b"
		var t: Vector2i = Vector2i(_rng.randi_range(rect.position.x + 1, rect.end.x - 2), _rng.randi_range(rect.position.y + 1, rect.end.y - 2))
		var tiles: Array[Vector2i] = [t, t + Vector2i(1, 0), t + Vector2i(-1, 0)]
		if tiles.all(func(q: Vector2i) -> bool: return _floor(q) and not _taken.has(q)):
			_l.add_prop(kind, Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 8.0), {"spec": {"z": -5}})
			if kind == "puddle_a":
				_l.add_prop("drip", Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 8.0), {"every": _rng.randf_range(2.5, 6.0)})
	for i: int in _rng.randi_range(2, 3):
		_anywhere("stalagmites")
	_anywhere("bones", 1, 12)
	_extra(1, ["post"] as Array[String])


func _airshaft() -> void:
	var middle: Vector2i = _center()
	_l.add_prop("shaft", Vector2(middle.x * 16.0 + 8.0, middle.y * 16.0 + 8.0))
	_l.add_light(Vector2(middle.x * 16.0 + 8.0, middle.y * 16.0 + 8.0), 120, 1.1, "9ec4ff", 0.06)
	_extra(2, ["stalagmites", "post", "barrel"] as Array[String])


func _treasure() -> void:
	var wall: Array[Vector2i] = _back_wall()
	if not wall.is_empty():
		var best: Vector2i = wall[wall.size() / 2]
		if _place("chest", best, Vector2(0, -4), {"id": "chest"}):
			_l.add_light(Vector2(best.x * 16.0 + 8.0, best.y * 16.0), 58, 0.7, "ffd070", 0.1)
	_anywhere("bones")
	_extra(2, ["sacks", "barrel", "crates"] as Array[String])
	_lamps(1)


func _forge() -> void:
	## The hearth against the back wall (its coals and flames glow and spark, a warm light), the anvil in front of it, the quenching trough, a tool shelf.
	var hearth: Vector2i = Vector2i(-1, -1)
	for b: Vector2i in _shuffled(_back_wall()):
		if _place("forge", b + Vector2i(0, 1), Vector2(0.0, -4.0), {"spec": {"sound": "fire.wav", "sparks": true}}):
			hearth = b + Vector2i(0, 1)
			break
	if hearth.x >= 0:
		_l.add_light(Vector2(hearth.x * 16.0 + 8.0, hearth.y * 16.0 - 2.0), 110, 1.15, "ff8a3a", 0.3)
		_place("anvil", hearth + Vector2i(0, 4), Vector2(0.0, -2.0))
	else:
		_anywhere("anvil")
	_anywhere("quench")
	_against_wall("shelf")
	_extra(2, ["crates", "barrel", "sacks"] as Array[String])
	_anywhere("bones", 1, 12)
	_lamps(1)


func _crystal() -> void:
	## A natural cave: the heart is a pillar of crystal, clusters grow from the floor and pulse in their own time; no lamp is needed.
	_place("crystal_big", _center() + Vector2i(0, 1), Vector2.ZERO, {"spec": {"pulse": [1.1, 0.35]}})
	_l.add_light(Vector2(_center().x * 16.0 + 8.0, _center().y * 16.0 - 24.0), 120, 0.9, "6ff0e0", 0.08)
	for i: int in _rng.randi_range(3, 6):
		var violet: bool = _rng.randf() < 0.4
		var kind: String = "crystal_b" if violet else "crystal_a"
		var t: Vector2i = Vector2i(_rng.randi_range(_rect().position.x + 1, _rect().end.x - 2), _rng.randi_range(_rect().position.y + 1, _rect().end.y - 2))
		if _place(kind, t, Vector2.ZERO, {"spec": {"pulse": [_rng.randf_range(1.2, 2.4), 0.5]}}):
			_l.add_light(Vector2(t.x * 16.0 + 8.0, t.y * 16.0 - 8.0), 62, 0.7, "b48cff" if violet else "6ff0e0", 0.1)
	for i: int in _rng.randi_range(1, 2):
		_anywhere("stalagmites")
	_anywhere("puddle_b", 1, 12)


func _voidroom() -> void:
	## The void has eaten into the rock: cracks with a light in them, pods that breathe, pairs of eyes in the dark of the wall.
	for i: int in _rng.randi_range(3, 5):
		var t: Vector2i = Vector2i(_rng.randi_range(_rect().position.x + 1, _rect().end.x - 2), _rng.randi_range(_rect().position.y + 1, _rect().end.y - 2))
		if _place("void_crack", t, Vector2.ZERO, {"spec": {"z": -5, "flip": _rng.randf() < 0.5, "pulse": [_rng.randf_range(0.9, 1.7), 0.55]}}):
			_l.add_light(Vector2(t.x * 16.0 + 8.0, t.y * 16.0 + 6.0), 54, 0.55, "c070ff", 0.12)
	for i: int in _rng.randi_range(2, 3):
		var t: Vector2i = Vector2i(_rng.randi_range(_rect().position.x + 1, _rect().end.x - 2), _rng.randi_range(_rect().position.y + 1, _rect().end.y - 2))
		if _place("void_pod", t, Vector2.ZERO, {"spec": {"pulse": [1.4, 0.4]}}):
			_l.add_light(Vector2(t.x * 16.0 + 8.0, t.y * 16.0 - 6.0), 48, 0.6, "ff5adc", 0.15)
	var wall: Array[Vector2i] = _shuffled(_back_wall())
	for k: int in mini(2, wall.size()):
		if _floor(wall[k]):
			_l.add_prop("void_eyes", Vector2(wall[k].x * 16.0 + 8.0, wall[k].y * 16.0 + 2.0), {"spec": {"z": -5, "pulse": [0.8, 0.7]}})
	_l.add_light(Vector2(_center().x * 16.0 + 8.0, _center().y * 16.0), 110, 0.75, "9a5aff", 0.1)
	_anywhere("bones", 1, 12)


func _empty() -> void:
	if _rng.randf() < 0.5:
		_extra(1, ["post", "barrel", "crates"] as Array[String])
	_lamps(1)


# ---------- nothing may be walled in ----------

## Tiles a body two tiles wide can reach from the entry with the solid props in the way (the top left tile of the body).
func _reach() -> PackedByteArray:
	var e: int = _l.edge
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(e * e)
	var start: int = _l.entry.y * e + _l.entry.x
	var queue: PackedInt32Array = PackedInt32Array([start])
	seen[start] = 1
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		for d: int in [-1, 1, -e, e]:
			var nb: int = at + d
			if nb < 0 or nb + e + 1 >= e * e or seen[nb] == 1:
				continue
			if _l.tiles[nb] == 1 and _l.tiles[nb + 1] == 1 and _l.tiles[nb + e] == 1 and _l.tiles[nb + e + 1] == 1 and _l.solid[nb] + _l.solid[nb + 1] + _l.solid[nb + e] + _l.solid[nb + e + 1] == 0:
				seen[nb] = 1
				queue.append(nb)
	return seen


func _reached_near(seen: PackedByteArray, at: Vector2i, reach: int) -> bool:
	var e: int = _l.edge
	for y: int in range(maxi(at.y - reach, 0), mini(at.y + reach + 1, e)):
		for x: int in range(maxi(at.x - reach, 0), mini(at.x + reach + 1, e)):
			if seen[y * e + x] == 1:
				return true
	return false


## Something blocks the way into a room or to the stairs: find where the cut-off part meets the reachable part (a search through the floor as if there were no
## props) and clear the blocking props around that spot. The stairs, lift and fire stay: they sit in halls with room round them.
func _repair() -> void:
	for attempt: int in 9:
		var seen: PackedByteArray = _reach()
		var targets: Array[Vector2i] = _unreached(seen)
		if targets.is_empty():
			return
		if attempt == 8: ## the last resort: the props round what is still cut off lose their collision, so nothing can ever be walled in
			for target: Vector2i in targets:
				_soften(target)
			return
		var cleared: Array[Vector2i] = []
		for target: Vector2i in targets:
			if cleared.size() >= 4:
				break
			var cut: Vector2i = _find_cut(target, seen)
			if cut.x >= 0 and not cleared.any(func(c: Vector2i) -> bool: return absi(c.x - cut.x) <= 3 and absi(c.y - cut.y) <= 3):
				_clear_around(cut, 7)
				cleared.append(cut)


## Spots the body cannot reach: the middle of every room and the places in front of the stairs and the lift.
func _unreached(seen: PackedByteArray) -> Array[Vector2i]:
	var targets: Array[Vector2i] = []
	for room: Dictionary in _l.rooms:
		var rect: Rect2i = room.rect as Rect2i
		var middle: Vector2i = rect.position + rect.size / 2
		if not _reached_near(seen, middle, maxi(rect.size.x, rect.size.y) / 2):
			targets.append(middle)
	for spot: Vector2i in [_l.exit_stairs + Vector2i(0, 2), _l.station_winch + Vector2i(0, 2), _l.entry_stairs + Vector2i(0, 1)]:
		if not _reached_near(seen, spot, 3):
			targets.append(spot)
	return targets


## Takes the collision from every prop within 16 tiles of `at` (the sprites stay) and frees their tiles.
func _soften(at: Vector2i) -> void:
	for y: int in range(maxi(at.y - 16, 0), mini(at.y + 17, _l.edge)):
		for x: int in range(maxi(at.x - 16, 0), mini(at.x + 17, _l.edge)):
			_l.solid[y * _l.edge + x] = 0
	for c: Vector2i in _l.chunk_props:
		for entry: Dictionary in _l.chunk_props[c] as Array:
			if absi(int(float(entry.x) / 16.0) - at.x) <= 16 and absi(int(float(entry.y) / 16.0) - at.y) <= 16:
				entry["nosolid"] = true


## Breadth first from `from` over the floor a body fits on (ignoring props) until a tile that is reachable with the props: where the way is cut.
func _find_cut(from: Vector2i, seen: PackedByteArray) -> Vector2i:
	var e: int = _l.edge
	var start: Vector2i = from
	for i: int in 12: ## the target tile itself may be a wall corner: step to the nearest tile a body fits on
		if _fits(start):
			break
		start.x += 1 if i % 2 == 0 else -2
	if not _fits(start):
		return Vector2i(-1, -1)
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(e * e)
	var queue: PackedInt32Array = PackedInt32Array([start.y * e + start.x])
	visited[queue[0]] = 1
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		if seen[at] == 1:
			return Vector2i(at % e, at / e)
		var px: int = at % e
		var py: int = at / e
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = px + d.x
			var ny: int = py + d.y
			if nx >= 0 and ny >= 0 and nx + 1 < e and ny + 1 < e and visited[ny * e + nx] == 0:
				var n: int = ny * e + nx
				if _l.tiles[n] == 1 and _l.tiles[n + 1] == 1 and _l.tiles[n + e] == 1 and _l.tiles[n + e + 1] == 1:
					visited[n] = 1
					queue.append(n)
	return Vector2i(-1, -1)


func _fits(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x + 1 < _l.edge and p.y + 1 < _l.edge and _floor(p) and _floor(p + Vector2i(1, 0)) and _floor(p + Vector2i(0, 1)) and _floor(p + Vector2i(1, 1))


## Removes the blocking props (not the key ones) within `radius` tiles of `at`.
func _clear_around(at: Vector2i, radius: int) -> void:
	for y: int in range(maxi(at.y - radius, 0), mini(at.y + radius + 1, _l.edge)):
		for x: int in range(maxi(at.x - radius, 0), mini(at.x + radius + 1, _l.edge)):
			if not _key_tiles.has(Vector2i(x, y)):
				_l.solid[y * _l.edge + x] = 0
	for c: Vector2i in _l.chunk_props:
		var kept: Array[Dictionary] = []
		for entry: Dictionary in _l.chunk_props[c] as Array:
			var tile: Vector2i = Vector2i(floori(float(entry.x) / 16.0), floori(float(entry.y) / 16.0))
			if absi(tile.x - at.x) <= radius and absi(tile.y - at.y) <= radius and String(entry.kind) in BLOCKING:
				_l.prop_count -= 1
			else:
				kept.append(entry)
		_l.chunk_props[c] = kept
