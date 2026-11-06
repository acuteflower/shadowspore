extends Node
## Step 2 of the mine (docs/mine.md): the generator on many seeds. Connectivity (also for a body two tiles wide), key places, widths, determinism, time.
## `-- --quick` runs a handful of seeds.

const PLAN: Dictionary = {1: 80, 5: 40, 10: 16, 20: 6} ## level -> seeds

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("MINE GENERATOR FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var quick: bool = OS.get_cmdline_user_args().has("--quick")
	for level: int in PLAN:
		var seeds: int = 3 if quick else int(PLAN[level])
		var slowest: float = 0.0
		var total_ms: float = 0.0
		var rooms: int = 0
		var path: int = 0
		var floor_share: float = 0.0
		for s: int in seeds:
			var layout: MineLayout = MineGenerator.new().generate(1000 + s * 7919, level)
			slowest = maxf(slowest, layout.build_ms)
			total_ms += layout.build_ms
			rooms += layout.rooms.size()
			path += layout.path_cells
			floor_share += float(layout.floor_tiles) / float(layout.edge * layout.edge)
			_verify(layout, "level %d seed %d" % [level, 1000 + s * 7919])
			if s < 2:
				var again: MineLayout = MineGenerator.new().generate(1000 + s * 7919, level)
				_check(again.tiles == layout.tiles and again.entry == layout.entry and again.exit == layout.exit and again.station == layout.station, "deterministic level %d seed %d" % [level, s])
				_check(again.rooms.size() == layout.rooms.size() and again.passages == layout.passages, "deterministic rooms level %d" % level)
			await get_tree().process_frame
		var limit: float = 150.0 if level == 1 else 800.0
		print("level %2d: %3d seeds, avg %.0f ms, slowest %.0f ms, rooms %.0f, way %.0f cells, floor %.0f %%" % [level, seeds, total_ms / seeds, slowest, float(rooms) / seeds, float(path) / seeds, 100.0 * floor_share / seeds])
		_check(slowest < limit * 3.0, "level %d too slow: %.0f ms" % [level, slowest]) ## 3x slack: the test machine may be busy; the printed numbers are the real figures
	# the shape follows the level number
	var small: MineLayout = MineGenerator.new().generate(5, 1)
	var big: MineLayout = MineGenerator.new().generate(5, 20)
	_check(small.edge == 88 and big.edge == 304, "edges 88 / 304")
	_check(big.rooms.size() > small.rooms.size() * 4, "bigger levels have many more rooms")
	_check(big.path_cells > small.path_cells, "the deepest way is longer")
	print("MINE GENERATOR: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


func _verify(l: MineLayout, tag: String) -> void:
	var e: int = l.edge
	_check(l.tiles.size() == e * e, tag + ": tile count")
	for i: int in e: ## solid rim
		for k: int in MineGenerator.BORDER:
			if l.tiles[k * e + i] != MineLayout.WALL or l.tiles[(e - 1 - k) * e + i] != MineLayout.WALL or l.tiles[i * e + k] != MineLayout.WALL or l.tiles[i * e + e - 1 - k] != MineLayout.WALL:
				_check(false, tag + ": rim is solid")
				return
	_check(l.is_floor(l.entry.x, l.entry.y) and l.is_floor(l.exit.x, l.exit.y) and l.is_floor(l.station.x, l.station.y), tag + ": key places are floor")
	var kinds: Dictionary = {}
	for c: Vector2i in l.chunk_props:
		for entry: Dictionary in l.chunk_props[c] as Array:
			kinds[String(entry.kind)] = int(kinds.get(String(entry.kind), 0)) + 1
	_check(kinds.has("stairs_up") and kinds.has("stairs_down") and kinds.has("winch") and kinds.has("fire_pit"), tag + ": entry, exit and rest are dressed")
	_check(l.entry_stairs != Vector2i.ZERO and l.exit_stairs != Vector2i.ZERO and l.station_winch != Vector2i.ZERO, tag + ": key places are recorded")
	_check(l.entry_room != l.exit_room and l.entry_room != l.station_room and l.exit_room != l.station_room, tag + ": key rooms differ")
	# everything is one piece
	var reached: int = _flood(l, l.entry, 1)
	_check(reached == l.floor_tiles, tag + ": floor is connected (%d of %d)" % [reached, l.floor_tiles])
	# a body two tiles wide gets everywhere that matters
	var cleared: PackedByteArray = _flood_wide(l, l.entry, true)
	_check(_near(cleared, e, l.exit_stairs + Vector2i(0, 2), 3), tag + ": the stairs down are reachable for a wide body")
	_check(_near(cleared, e, l.station_winch + Vector2i(0, 2), 3), tag + ": the lift is reachable for a wide body")
	_check(_near(cleared, e, l.rest_fire, 3), tag + ": the fire is reachable for a wide body")
	_check(_near(cleared, e, l.entry_stairs + Vector2i(0, 1), 3), tag + ": the stairs up are reachable for a wide body")
	var lost: int = 0
	for room: Dictionary in l.rooms:
		var c: Vector2i = room.center as Vector2i
		var rr: Rect2i = room.rect as Rect2i
		if not _near(cleared, e, rr.position + rr.size / 2, maxi(rr.size.x, rr.size.y) / 2):
			lost += 1
			print("  unreachable: ", room.type, " cells ", room.cells, " rect ", room.rect, " shape ", room.shape, " degree ", room.degree)
		_check(String(room.type) != "", tag + ": room %d has a type" % int(room.id))
		_check(l.is_floor(c.x, c.y), tag + ": room %d centre is floor" % int(room.id))
	_check(lost == 0, tag + ": %d rooms unreachable for a wide body" % lost)
	# the main way
	var distances: Array[int] = []
	for room: Dictionary in l.rooms:
		var cell: Rect2i = room.cells as Rect2i
		var d: int = l.distance[cell.position.y * l.cells + cell.position.x]
		distances.append(d)
		_check(d >= 0, tag + ": room %d is connected in the graph" % int(room.id))
	var farthest: int = distances.max()
	var exit_cells: Rect2i = l.rooms[l.exit_room].cells as Rect2i
	var exit_d: int = l.distance[exit_cells.position.y * l.cells + exit_cells.position.x]
	_check(float(exit_d) >= 0.3 * float(farthest), tag + ": exit is far on the way (%d of %d)" % [exit_d, farthest])
	var crow: float = Vector2(l.entry).distance_to(Vector2(l.exit))
	_check(crow >= 0.3 * float(e), tag + ": exit is far as the crow flies (%.0f of %d)" % [crow, e])
	var st_cells: Rect2i = l.rooms[l.station_room].cells as Rect2i
	var st_d: int = l.distance[st_cells.position.y * l.cells + st_cells.position.x]
	_check(st_d > 0 and float(st_d) / float(maxi(exit_d, 1)) > 0.15 and float(st_d) / float(maxi(exit_d, 1)) < 0.9, tag + ": station is about halfway (%d of %d)" % [st_d, exit_d])
	for k: int in l.critical:
		_check(int(l.widths.get(k, 3)) >= 3, tag + ": critical passages are at least 3 wide")
	_check(l.critical.size() >= l.path_cells, tag + ": critical path marked")
	# decoration: every prop stands on floor, lamps hang below a wall; the deepest zone has no lamps
	var lamps: int = 0
	for c: Vector2i in l.chunk_props:
		for entry: Dictionary in l.chunk_props[c] as Array:
			var tx: int = floori(float(entry.x) / 16.0)
			var ty: int = floori(float(entry.y) / 16.0)
			_check(l.is_floor(tx, ty), tag + ": prop %s stands on floor" % entry.kind)
			if String(entry.kind).begins_with("lamp"):
				lamps += 1
				_check(not l.is_floor(tx, ty - 1), tag + ": lamp hangs on a wall")
	if l.level >= 16:
		_check(lamps == 0, tag + ": no lamps in the deepest zone")
	if l.level == 1:
		_check(lamps >= 8 and not l.chunk_lights.is_empty(), tag + ": level 1 has lamp chains (%d)" % lamps)


func _flood(l: MineLayout, from: Vector2i, _step: int) -> int:
	var e: int = l.edge
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(e * e)
	var queue: PackedInt32Array = PackedInt32Array([from.y * e + from.x])
	seen[queue[0]] = 1
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		for d: int in [-1, 1, -e, e]:
			var nb: int = at + d
			if nb >= 0 and nb < e * e and seen[nb] == 0 and l.tiles[nb] == MineLayout.FLOOR:
				seen[nb] = 1
				queue.append(nb)
	return queue.size()


## Tiles a 2 x 2 body can stand on (its top left tile), reachable from `from`; marks them 1.
func _flood_wide(l: MineLayout, from: Vector2i, props_block: bool = false) -> PackedByteArray:
	var e: int = l.edge
	var ok: PackedByteArray = PackedByteArray()
	ok.resize(e * e)
	for y: int in range(0, e - 1):
		for x: int in range(0, e - 1):
			if l.tiles[y * e + x] == 1 and l.tiles[y * e + x + 1] == 1 and l.tiles[(y + 1) * e + x] == 1 and l.tiles[(y + 1) * e + x + 1] == 1:
				if not props_block or (l.solid[y * e + x] + l.solid[y * e + x + 1] + l.solid[(y + 1) * e + x] + l.solid[(y + 1) * e + x + 1]) == 0:
					ok[y * e + x] = 1
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(e * e)
	var start: int = from.y * e + from.x
	var queue: PackedInt32Array = PackedInt32Array([start])
	seen[start] = 1
	var head: int = 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		for d: int in [-1, 1, -e, e]:
			var nb: int = at + d
			if nb >= 0 and nb < e * e and seen[nb] == 0 and ok[nb] == 1:
				seen[nb] = 1
				queue.append(nb)
	return seen


## Is a tile marked in `cleared` within `reach` of `at`?
func _near(cleared: PackedByteArray, e: int, at: Vector2i, reach: int) -> bool:
	for y: int in range(maxi(at.y - reach, 0), mini(at.y + reach + 1, e)):
		for x: int in range(maxi(at.x - reach, 0), mini(at.x + reach + 1, e)):
			if cleared[y * e + x] == 1:
				return true
	return false
