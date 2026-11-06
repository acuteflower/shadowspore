class_name MapDiscovery
extends Node
## Which parts of the world have been seen (the fog of the map, M). One byte per 4x4-tile cell of
## the RegionMap grid. The host reveals a ragged disc around every player a few times a second and
## tells everyone (`_rpc_reveal`); a joining peer gets the whole table (`_rpc_snapshot`). The
## discovery is shared by all players. `MapWindow` draws it; the save file keeps it (`export_data`).

signal revealed(cells: PackedInt32Array) ## cell indices that just became known
signal replaced ## the whole table changed (snapshot, loaded save)

const GRID: int = RegionMap.WORLD_TILES / RegionMap.CELL
const CELL_PX: float = RegionMap.CELL * 16.0
const RADIUS: float = 7.5 ## cells around a player that count as seen (30 tiles, a bit more than the screen)
const RAGGED: float = 1.6 ## cells the edge of that disc wanders
const TICK: float = 0.4

var _seen: PackedByteArray = PackedByteArray()
var _count: int = 0
var _timer: float = 0.0


func _ready() -> void:
	add_to_group("map_discovery")
	_seen.resize(GRID * GRID)
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(id: int) -> void: _rpc_snapshot.rpc_id(id, export_data()))


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	var fresh: PackedInt32Array = PackedInt32Array()
	for player: Player in Player.all:
		_scan(Interiors.outer(get_tree(), player.global_position) / CELL_PX, fresh)
	if not fresh.is_empty():
		_rpc_reveal.rpc(fresh)


func _scan(at: Vector2, fresh: PackedInt32Array) -> void:
	var reach: int = ceili(RADIUS + RAGGED)
	for y: int in range(maxi(floori(at.y) - reach, 0), mini(floori(at.y) + reach + 1, GRID)):
		for x: int in range(maxi(floori(at.x) - reach, 0), mini(floori(at.x) + reach + 1, GRID)):
			var index: int = y * GRID + x
			if _seen[index] != 0:
				continue
			var wander: float = (fposmod(sin(float(index) * 12.9898) * 43758.5453, 1.0) - 0.5) * RAGGED
			if Vector2(x + 0.5, y + 0.5).distance_to(at) <= RADIUS + wander:
				fresh.append(index)


@rpc("authority", "call_local", "reliable")
func _rpc_reveal(cells: PackedInt32Array) -> void:
	var added: PackedInt32Array = PackedInt32Array()
	for index: int in cells:
		if index >= 0 and index < _seen.size() and _seen[index] == 0:
			_seen[index] = 1
			_count += 1
			added.append(index)
	if not added.is_empty():
		revealed.emit(added)


@rpc("authority", "reliable")
func _rpc_snapshot(data: PackedByteArray) -> void:
	import_data(data)


func seen_count() -> int:
	return _count


func is_seen_cell(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < GRID and y < GRID and _seen[y * GRID + x] != 0


## `tile` in tile units (not pixels).
func is_seen(tile: Vector2) -> bool:
	return is_seen_cell(floori(tile.x / RegionMap.CELL), floori(tile.y / RegionMap.CELL))


func bytes() -> PackedByteArray:
	return _seen


## The table, compressed (network snapshot and save file).
func export_data() -> PackedByteArray:
	return _seen.compress(FileAccess.COMPRESSION_ZSTD)


func import_data(data: PackedByteArray) -> void:
	var raw: PackedByteArray = data.decompress(GRID * GRID, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != GRID * GRID:
		return
	_seen = raw
	_count = 0
	for value: int in _seen:
		_count += value
	replaced.emit()


## Loading a save: the host's table replaces everything, peers get it too.
func import_saved(data: PackedByteArray) -> void:
	import_data(data)
	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_rpc_snapshot.rpc(export_data())
