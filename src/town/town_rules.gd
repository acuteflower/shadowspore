class_name TownRules
extends RefCounted
## The pure rules of the town (docs/town.md): catalogue lookups, footprints, the lit territory, levels, costs. No nodes, so the host, the preview of
## the builder and the tests all ask the same functions.

const TILE: float = 16.0


static func config() -> Dictionary:
	return DataRegistry.table("town")


static func piece(id: String) -> Dictionary:
	return (config().get("pieces", {}) as Dictionary).get(id, {}) as Dictionary


## The pieces a player can choose in the build menu, in the catalogue's order (the house is not one of them).
static func buildable() -> Array[String]:
	var out: Array[String] = []
	var pieces: Dictionary = config().get("pieces", {}) as Dictionary
	for id: String in pieces:
		if not bool((pieces[id] as Dictionary).get("builtin", false)):
			out.append(id)
	return out


static func in_category(category: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in buildable():
		if String(piece(id).get("category", "")) == category:
			out.append(id)
	return out


static func categories() -> Array:
	return config().get("categories", []) as Array


## The ground a piece stands on: its feet at (x, y), `foot` [w, h] wide and deep, the bottom edge at y.
static func foot_rect(id: String, x: float, y: float) -> Rect2:
	var foot: Array = piece(id).get("foot", [16, 16]) as Array
	var w: float = float(foot[0])
	var h: float = float(foot[1])
	return Rect2(x - w / 2.0, y - h, w, h)


## The ground in front of a door that has to stay free: where people stand, work and walk in (`front` [w, d] in the data: as wide as the door side, d deep from the
## feet line towards the viewer). No area for a piece without a door.
static func front_rect(id: String, x: float, y: float) -> Rect2:
	var front: Array = piece(id).get("front", []) as Array
	if front.size() < 2:
		return Rect2(x, y, 0.0, 0.0)
	return Rect2(x - float(front[0]) / 2.0, y, float(front[0]), float(front[1]))


static func snap_of(id: String) -> float:
	return float(piece(id).get("snap", 8))


## The footprint's top left corner sits on the grid (so a 16 px plate fills exactly one ground tile); returns the feet position.
static func snapped_position(id: String, pos: Vector2) -> Vector2:
	var grid: float = snap_of(id)
	var rect: Rect2 = foot_rect(id, pos.x, pos.y)
	var corner: Vector2 = Vector2(roundf(rect.position.x / grid) * grid, roundf(rect.position.y / grid) * grid)
	return corner + Vector2(rect.size.x / 2.0, rect.size.y)


## Do two footprints overlap? (Touching edges do not.)
static func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and b.position.x < a.end.x and a.position.y < b.end.y and b.position.y < a.end.y


## Circles of light {x, y, reach} -> is `pos` inside one of them?
static func covers(circles: Array[Vector3], pos: Vector2) -> bool:
	for c: Vector3 in circles:
		if pos.distance_squared_to(Vector2(c.x, c.y)) <= c.z * c.z:
			return true
	return false


## How deep `pos` lies in the light: the largest `reach - distance` over the circles (positive = inside, negative = that far outside the nearest one; -9999 without circles).
static func light_depth(circles: Array[Vector3], pos: Vector2) -> float:
	var best: float = -9999.0
	for c: Vector3 in circles:
		best = maxf(best, c.z - pos.distance_to(Vector2(c.x, c.y)))
	return best


## The way out of the light at `pos`: a unit vector away from the circle that holds it deepest (zero without circles).
static func light_outward(circles: Array[Vector3], pos: Vector2) -> Vector2:
	var best: float = -INF
	var away: Vector2 = Vector2.ZERO
	for c: Vector3 in circles:
		var depth: float = c.z - pos.distance_to(Vector2(c.x, c.y))
		if depth > best:
			best = depth
			away = pos - Vector2(c.x, c.y)
	return away.normalized() if away != Vector2.ZERO else Vector2.RIGHT


## Which share of the line a..b lies in light (sampled), 0..1: a way with little light on it is a gap in the net.
static func lit_fraction(circles: Array[Vector3], a: Vector2, b: Vector2, steps: int = 12) -> float:
	var lit: int = 0
	for i: int in steps + 1:
		if light_depth(circles, a.lerp(b, float(i) / float(steps))) > 0.0:
			lit += 1
	return float(lit) / float(steps + 1)


## The level index (0 = first) a town of this worth has reached.
static func level_for(worth: float) -> int:
	var levels: Array = config().get("levels", []) as Array
	var index: int = 0
	for i: int in levels.size():
		if worth >= float((levels[i] as Dictionary).worth):
			index = i
	return index


static func level_name(index: int) -> String:
	var levels: Array = config().get("levels", []) as Array
	return String((levels[clampi(index, 0, levels.size() - 1)] as Dictionary).name) if not levels.is_empty() else ""


## Worth needed for the next level (-1 at the top).
static func next_worth(index: int) -> float:
	var levels: Array = config().get("levels", []) as Array
	return float((levels[index + 1] as Dictionary).worth) if index + 1 < levels.size() else -1.0


## What demolishing gives back: all of it for a site, `refund_done` of it for a finished piece (rounded up).
static func refund(cost: Dictionary, finished: bool) -> Dictionary:
	var out: Dictionary = {}
	var share: float = float((config().get("limits", {}) as Dictionary).get("refund_done", 0.6)) if finished else 1.0
	for item: String in cost:
		out[item] = ceili(float(cost[item]) * share)
	return out


## "WOOD 3  GLOW CAP 2" for a cost dictionary, with the item names of data/items.json.
static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: String in cost:
		parts.append("%d %s" % [int(cost[item]), String(DataRegistry.get_entry("items", item).get("name", item)).to_upper()])
	return "  ".join(parts)


static func town_names() -> Array:
	return (config().get("name", {}) as Dictionary).get("choices", []) as Array
