class_name MineLayout
extends RefCounted
## The result of `MineGenerator`: everything about the shape of one mine level, as plain data (no nodes). The same on every peer for the same
## world seed and level. Later phases (props, rocks, encounters) read this and add their own lists.
##
## Space: the level is `cells` x `cells` cells of `cell_size` (8) tiles; a tile is 16 px. Tile (0, 0) is the level's origin (`MineManager.origin`).

const WALL: int = 0
const FLOOR: int = 1
const CELL: int = 8

var level: int = 1
var world_seed: int = 0
var zone_id: String = ""
var edge: int = 88 ## tiles per side
var cells: int = 11 ## cells per side
var tiles: PackedByteArray = PackedByteArray() ## edge * edge, WALL or FLOOR
var cell_used: PackedByteArray = PackedByteArray() ## 1 = the cell is part of the maze (a room cell or a corridor cell)
var cell_room: PackedInt32Array = PackedInt32Array() ## room index per cell, -1 = corridor or unused
var rooms: Array[Dictionary] = [] ## {id, cells: Rect2i, rect: Rect2i (tiles), center: Vector2i (tile), shape, type, degree, area}
var passages: Array[Vector2i] = [] ## pairs of neighbouring cell indices (a < b) joined by a corridor or door
var critical: Dictionary = {} ## passage key -> true: the passages on the way entry -> station -> exit, never blocked
var widths: Dictionary = {} ## passage key -> corridor width in tiles
var entry_room: int = -1
var exit_room: int = -1
var station_room: int = -1
var entry: Vector2i = Vector2i.ZERO ## tile in the middle of the entry room (where the stairs from above arrive)
var exit: Vector2i = Vector2i.ZERO
var station: Vector2i = Vector2i.ZERO
var entry_stairs: Vector2i = Vector2i.ZERO ## tile in front of the stairs up (the entry hall)
var exit_stairs: Vector2i = Vector2i.ZERO ## tile of the stairs down (the exit hall)
var station_winch: Vector2i = Vector2i.ZERO ## tile in front of the lift (the rest room)
var rest_fire: Vector2i = Vector2i.ZERO
var path_cells: int = 0 ## length of the way entry -> exit in cells
var distance: PackedInt32Array = PackedInt32Array() ## cells from the entry, per cell (-1 = unreachable)
var floor_tiles: int = 0
var chunk_props: Dictionary = {} ## chunk cell (Vector2i) -> Array[Dictionary] {kind, x, y (feet, level px), ...}: what stands in the level
var chunk_lights: Dictionary = {} ## chunk cell -> Array[Dictionary] {x, y, radius, energy, color, flicker}
var chunk_cables: Dictionary = {} ## chunk cell -> Array[Dictionary] {a, b} (hanging ropes between lamps, drawn by the chunk)
var chunk_rails: Dictionary = {} ## chunk cell -> Array[Vector3i] (tile x, tile y, rail tile index): rails lying on the floor
var hubs: PackedInt32Array = PackedInt32Array() ## per cell: the corridor hub tile (x * 65536 + y), -1 unused
var solid: PackedByteArray = PackedByteArray() ## 1 = a tile a solid prop stands on (edge * edge): only for tests and for placing things clear of them
var chunk_rocks: Dictionary = {} ## chunk cell -> Array[Dictionary] {kind, x, y (feet, level px), variant}: rocks to mine
var collapses: Array[Dictionary] = [] ## {key (passage), x, y}: piles of rocks across passages off the main way
var encounters: Array[Dictionary] = [] ## {id, template, room, cost, members: [{enemy, x, y (feet, level px), heading}]}: sleeping groups of enemies (MineEncounters)
var budget: float = 0.0 ## encounter points of the level, `encounters` spend nearly all of them
var prop_count: int = 0
var build_ms: float = 0.0


func is_floor(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < edge and y < edge and tiles[y * edge + x] == FLOOR


func is_floor_px(local: Vector2) -> bool:
	return is_floor(floori(local.x / 16.0), floori(local.y / 16.0))


func cell_index(cx: int, cy: int) -> int:
	return cy * cells + cx


func cell_of_tile(x: int, y: int) -> int:
	return clampi(y / CELL, 0, cells - 1) * cells + clampi(x / CELL, 0, cells - 1)


## The room a tile lies in (cell based, so the walls around the room count too), -1 in corridors.
func room_at(x: int, y: int) -> int:
	return cell_room[cell_of_tile(x, y)]


static func key(a: int, b: int) -> int:
	return a * 100000 + b if a < b else b * 100000 + a


func is_critical(a: int, b: int) -> bool:
	return critical.has(key(a, b))


func tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * 16.0 + 8.0, tile.y * 16.0 + 8.0)


static func chunk_of(px: Vector2) -> Vector2i:
	return Vector2i(floori(px.x / 512.0), floori(px.y / 512.0))


func add_prop(kind: String, at: Vector2, extra: Dictionary = {}) -> void:
	var entry: Dictionary = {"kind": kind, "x": at.x, "y": at.y}
	entry.merge(extra)
	var c: Vector2i = chunk_of(at)
	if not chunk_props.has(c):
		chunk_props[c] = [] as Array[Dictionary]
	(chunk_props[c] as Array[Dictionary]).append(entry)
	prop_count += 1


func add_light(at: Vector2, radius: int, energy: float, color: String, flicker: float) -> void:
	var c: Vector2i = chunk_of(at)
	if not chunk_lights.has(c):
		chunk_lights[c] = [] as Array[Dictionary]
	(chunk_lights[c] as Array[Dictionary]).append({"x": at.x, "y": at.y, "radius": radius, "energy": energy, "color": color, "flicker": flicker})


func add_cable(a: Vector2, b: Vector2) -> void:
	var c: Vector2i = chunk_of(a)
	if not chunk_cables.has(c):
		chunk_cables[c] = [] as Array[Dictionary]
	(chunk_cables[c] as Array[Dictionary]).append({"a": a, "b": b})


func add_rail(tile: Vector2i, index: int) -> void:
	var c: Vector2i = Vector2i(tile.x / 32, tile.y / 32)
	if not chunk_rails.has(c):
		chunk_rails[c] = [] as Array[Vector3i]
	(chunk_rails[c] as Array[Vector3i]).append(Vector3i(tile.x, tile.y, index))


func remove_rail(tile: Vector2i) -> void:
	var c: Vector2i = Vector2i(tile.x / 32, tile.y / 32)
	var rails: Array = chunk_rails.get(c, []) as Array
	for i: int in range(rails.size() - 1, -1, -1):
		var r: Vector3i = rails[i] as Vector3i
		if r.x == tile.x and r.y == tile.y:
			rails.remove_at(i)


func add_rock(kind: String, at: Vector2, variant: int) -> void:
	var c: Vector2i = chunk_of(at)
	if not chunk_rocks.has(c):
		chunk_rocks[c] = [] as Array[Dictionary]
	(chunk_rocks[c] as Array[Dictionary]).append({"kind": kind, "x": at.x, "y": at.y, "variant": variant})
