class_name MineDecorator
extends RefCounted
## Dresses a generated level with what is the same everywhere (docs/mine.md sections 6 and 7): timber supports across the straight corridors and the chains of
## lamps along the north walls (their density and the share of dead lamps come from the zone). Pure function of the layout, own random streams; the results
## go into the layout's per-chunk lists (props, lights, cables) which the chunks build when they load. Rooms are dressed by `MineRooms` (step 6).

const LAMP_FEET: int = 36 ## the row of the lamp sprite that stands on the foot of the wall: the lantern hangs on the wall face
const LAMP_LIGHT: Dictionary = {"radius": 78, "energy": 0.95, "color": "ffb561", "flicker": 0.16}

var _l: MineLayout
var _zone: Dictionary
var _lamps: Array[Vector2i] = [] ## tiles of the lamps (lit or dead), for the spacing
var _grid: Dictionary = {}


func dress(layout: MineLayout) -> void:
	_l = layout
	_zone = MineManager.zone(layout.level)
	_supports()
	_lamp_chains()
	MineRooms.new().dress(_l)
	MineRocks.new().dress(_l)
	MineClutter.new().dress(_l)
	MineEncounters.new().dress(_l)


func _rng(phase: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = MineGenerator._mix(MineGenerator._mix(_l.world_seed, _l.level), 100 + phase)
	return rng


func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(array.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = array[i]
		array[i] = array[j]
		array[j] = tmp


func _wall(x: int, y: int) -> bool:
	return not _l.is_floor(x, y)


func _corridor(x: int, y: int) -> bool:
	return _l.is_floor(x, y) and _l.cell_room[_l.cell_of_tile(x, y)] < 0


## Is a lamp or support already within `spacing` tiles?
func _crowded(tile: Vector2i, spacing: float) -> bool:
	var reach: int = int(ceilf(spacing / 8.0))
	var c: Vector2i = Vector2i(tile.x / 8, tile.y / 8)
	for dy: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			for other: Vector2i in _grid.get(c + Vector2i(dx, dy), []) as Array:
				if Vector2(other).distance_to(Vector2(tile)) < spacing:
					return true
	return false


func _claim(tile: Vector2i) -> void:
	var c: Vector2i = Vector2i(tile.x / 8, tile.y / 8)
	if not _grid.has(c):
		_grid[c] = [] as Array[Vector2i]
	(_grid[c] as Array[Vector2i]).append(tile)
	_lamps.append(tile)


func _light(at: Vector2) -> void:
	_l.add_light(at, int(LAMP_LIGHT.radius), float(LAMP_LIGHT.energy), String(LAMP_LIGHT.color), float(LAMP_LIGHT.flicker))


## A frame across a straight three tile wide corridor running north-south: floor in the three columns, rock beside them, for three rows.
func _supports() -> void:
	var chance: float = float(_zone.get("support_chance", 0.0))
	if chance <= 0.0:
		return
	var rng: RandomNumberGenerator = _rng(1)
	var spots: Array[Vector2i] = []
	for y: int in range(3, _l.edge - 3):
		for x: int in range(3, _l.edge - 3):
			if not _corridor(x, y):
				continue
			var straight: bool = true
			for dy: int in range(-1, 2):
				if not (_l.is_floor(x - 1, y + dy) and _l.is_floor(x, y + dy) and _l.is_floor(x + 1, y + dy) and _wall(x - 2, y + dy) and _wall(x + 2, y + dy)):
					straight = false
					break
			if straight:
				spots.append(Vector2i(x, y))
	_shuffle(spots, rng)
	var with_lamp: float = 0.35 if float(_zone.get("lamp_spacing", 0)) > 0.0 else 0.0
	for tile: Vector2i in spots:
		if rng.randf() > chance or _crowded(tile, 11.0):
			continue
		_claim(tile)
		var lit: bool = rng.randf() < with_lamp and rng.randf() >= float(_zone.get("lamp_gap", 0.0))
		_l.add_prop("support_lamp" if lit else "support_frame", Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 + 8.0))
		if lit:
			_light(Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 - 24.0))


## Lamps hang on the faces of the north walls along the corridors, joined by a rope; in the deeper zones some are dead and then there are none.
func _lamp_chains() -> void:
	var spacing: float = float(_zone.get("lamp_spacing", 0))
	if spacing <= 0.0:
		return
	var gap: float = float(_zone.get("lamp_gap", 0.0))
	var rng: RandomNumberGenerator = _rng(2)
	var spots: Array[Vector2i] = []
	for y: int in range(3, _l.edge - 3):
		for x: int in range(3, _l.edge - 3):
			if _corridor(x, y) and _wall(x, y - 1) and _wall(x - 1, y - 1) and _wall(x + 1, y - 1):
				spots.append(Vector2i(x, y))
	_shuffle(spots, rng)
	var placed: Array[Vector2i] = []
	for tile: Vector2i in spots:
		if _crowded(tile, spacing):
			continue
		_claim(tile)
		placed.append(tile)
		var dead: bool = rng.randf() < gap
		var foot: Vector2 = Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 + 1.0)
		_l.add_prop("lamp_dead" if dead else "lamp", foot)
		if not dead:
			_light(foot + Vector2(5.0, 2.0))
	placed.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for i: int in range(placed.size() - 1): ## a rope between neighbours on the same wall
		var a: Vector2i = placed[i]
		var b: Vector2i = placed[i + 1]
		if a.y != b.y or float(b.x - a.x) > spacing * 2.2:
			continue
		var joined: bool = true
		for x: int in range(a.x, b.x + 1):
			if not (_corridor(x, a.y) and _wall(x, a.y - 1)):
				joined = false
				break
		if joined:
			_l.add_cable(Vector2(a.x * 16.0 + 13.0, a.y * 16.0 - 7.0), Vector2(b.x * 16.0 + 13.0, b.y * 16.0 - 7.0))
