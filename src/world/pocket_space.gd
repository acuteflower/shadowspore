class_name PocketSpace
extends RefCounted
## Where pocket spaces (rooms, mine levels, arenas, dungeons) live in Shadowspore 2.0 (docs/v2_zonenwelt_atlas_konzept.md 4.2).
## Continents use real tile coordinates from (0, 0) into the positive quadrant, so every pocket sits in the negative
## quadrant, below `LIMIT` on both axes, where no continent can ever reach. Two lanes of fixed slots, the same on every
## peer: ROOM (interiors, 1600 px) and LARGE (mine levels up to 304 tiles, arenas, dungeons, 5600 px).
## Slot math is pure and static (safe on workers); the pocket-to-zone registry is main-thread metadata used by
## `Interiors`, `MineManager`, `ZoneDirector`, and coop visibility filtering.

enum Lane { ROOM, LARGE, DUNGEON }

const LIMIT: float = -16000.0 ## a position below this on BOTH axes is pocket space
const ROOM_ORIGIN: Vector2 = Vector2(-80000.0, -80000.0)
const ROOM_SLOT: float = 1600.0
const ROOM_COLUMNS: int = 16
const ROOM_ROWS: int = 4
const LARGE_ORIGIN: Vector2 = Vector2(-80000.0, -56000.0)
const LARGE_SLOT: float = 5600.0
const LARGE_COLUMNS: int = 9
const LARGE_ROWS: int = 4
const DUNGEON_ORIGIN: Vector2 = Vector2(-80000.0, -112000.0)
const DUNGEON_SLOT: float = 8192.0 ## 512x512 tiles per standalone dungeon scene
const DUNGEON_COLUMNS: int = 4
const DUNGEON_ROWS: int = 1

static var _pockets: Dictionary = {} ## StringName -> {"rect": Rect2, "parent_zone": StringName}


static func is_pocket(pos: Vector2) -> bool:
	return pos.x < LIMIT and pos.y < LIMIT


static func capacity(lane: Lane) -> int:
	if lane == Lane.ROOM:
		return ROOM_COLUMNS * ROOM_ROWS
	if lane == Lane.LARGE:
		return LARGE_COLUMNS * LARGE_ROWS
	return DUNGEON_COLUMNS * DUNGEON_ROWS


static func slot_size(lane: Lane) -> float:
	if lane == Lane.ROOM:
		return ROOM_SLOT
	if lane == Lane.LARGE:
		return LARGE_SLOT
	return DUNGEON_SLOT


static func _lane_columns(lane: Lane) -> int:
	if lane == Lane.ROOM:
		return ROOM_COLUMNS
	if lane == Lane.LARGE:
		return LARGE_COLUMNS
	return DUNGEON_COLUMNS


static func _lane_rows(lane: Lane) -> int:
	if lane == Lane.ROOM:
		return ROOM_ROWS
	if lane == Lane.LARGE:
		return LARGE_ROWS
	return DUNGEON_ROWS


static func _lane_origin(lane: Lane) -> Vector2:
	if lane == Lane.ROOM:
		return ROOM_ORIGIN
	if lane == Lane.LARGE:
		return LARGE_ORIGIN
	return DUNGEON_ORIGIN


## Top-left corner of a slot. An index outside the capacity is an error and gives Vector2.INF.
static func slot_origin(lane: Lane, index: int) -> Vector2:
	if index < 0 or index >= capacity(lane):
		push_error("PocketSpace: slot %d out of range for lane %d" % [index, lane])
		return Vector2.INF
	var columns: int = _lane_columns(lane)
	var origin: Vector2 = _lane_origin(lane)
	var size: float = slot_size(lane)
	return origin + Vector2(float(index % columns), float(floori(float(index) / float(columns)))) * size


static func slot_rect(lane: Lane, index: int) -> Rect2:
	var origin: Vector2 = slot_origin(lane, index)
	if not origin.is_finite():
		return Rect2()
	var size: float = slot_size(lane)
	return Rect2(origin, Vector2(size, size))


## (lane, index) of the slot holding `pos`, or (-1, -1) outside every slot.
static func locate(pos: Vector2) -> Vector2i:
	if not is_pocket(pos):
		return Vector2i(-1, -1)
	for lane: Lane in [Lane.ROOM, Lane.LARGE, Lane.DUNGEON]:
		var columns: int = _lane_columns(lane)
		var rows: int = _lane_rows(lane)
		var origin: Vector2 = _lane_origin(lane)
		var local: Vector2 = (pos - origin) / slot_size(lane)
		if local.x < 0.0 or local.y < 0.0 or local.x >= float(columns) or local.y >= float(rows):
			continue
		return Vector2i(lane, int(local.y) * columns + int(local.x))
	return Vector2i(-1, -1)


static func register_pocket(id: StringName, rect: Rect2, parent_zone: StringName = &"") -> void:
	if id == &"":
		return
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= 0.0 or rect.size.y <= 0.0 or not is_pocket(rect.position) or not is_pocket(rect.end - Vector2(0.001, 0.001)):
		push_error("PocketSpace: pocket '%s' rect %s must have positive area strictly inside pocket space (< %s)" % [id, rect, LIMIT])
		return
	_pockets[id] = {"rect": rect, "parent_zone": parent_zone}


static func unregister_pocket(id: StringName) -> void:
	_pockets.erase(id)


static func clear_pockets() -> void:
	_pockets.clear()


static func pocket_id_at(pos: Vector2) -> StringName:
	if not is_pocket(pos):
		return &""
	for id: StringName in _pockets:
		var entry: Dictionary = _pockets[id] as Dictionary
		if (entry.get("rect", Rect2()) as Rect2).has_point(pos):
			return id
	return &""


static func parent_zone_at(pos: Vector2) -> StringName:
	if not is_pocket(pos):
		return &""
	for id: StringName in _pockets:
		var entry: Dictionary = _pockets[id] as Dictionary
		if (entry.get("rect", Rect2()) as Rect2).has_point(pos):
			return entry.get("parent_zone", &"") as StringName
	return &""


static func pockets_of_zone(parent_zone: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if parent_zone == &"":
		return out
	for id: StringName in _pockets:
		var entry: Dictionary = _pockets[id] as Dictionary
		if (entry.get("parent_zone", &"") as StringName) == parent_zone:
			out.append(id)
	return out
