class_name TownWear
extends RefCounted
## The ground of a town is trodden (docs/town_ausbau.md A5): where there is traffic (doors, plates, benches, ways) the meadow turns to earth, where nothing happens grass stays.
## Pure functions: the same `structures`, `paths` and day give the same field on every peer, nothing is sent. Cells of 8 px, a value 0..1 each. A piece's `trample`
## {strength, margin, front} in data/town.json says how much it wears the ground round it (`front`: also the free strip before its door); a new piece wears it in over `GROW_DAYS`.

const CELL: float = 8.0
const SIZE: int = 256 ## cells a side of the field's picture: 2048 px round the middle of the town
const GROW_DAYS: float = 6.0
const START: float = 0.25 ## how much a piece wears the ground on its first day
const PATH_STRENGTH: float = 0.85
const PATH_MARGIN: float = 7.0


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))


## Adds a block of wear: `strength` inside `rect`, falling off to nothing over `margin` px outside it. Keeps the larger value of a cell.
static func splat(out: Dictionary, rect: Rect2, strength: float, margin: float) -> void:
	var wide: Rect2 = rect.grow(margin)
	for cy: int in range(floori(wide.position.y / CELL), ceili(wide.end.y / CELL)):
		for cx: int in range(floori(wide.position.x / CELL), ceili(wide.end.x / CELL)):
			var middle: Vector2 = (Vector2(cx, cy) + Vector2(0.5, 0.5)) * CELL
			var nearest: Vector2 = Vector2(clampf(middle.x, rect.position.x, rect.end.x), clampf(middle.y, rect.position.y, rect.end.y))
			var v: float = strength * (1.0 - smoothstep(0.0, maxf(margin, 1.0), middle.distance_to(nearest)))
			if v > 0.01:
				var key: Vector2i = Vector2i(cx, cy)
				out[key] = maxf(float(out.get(key, 0.0)), v)


## Wear of the whole town: Vector2i cell -> 0..1.
static func compute(structures: Dictionary, paths: Array, day: int) -> Dictionary:
	var out: Dictionary = {}
	for id: int in structures:
		var data: Dictionary = structures[id] as Dictionary
		if int(data.g) < TownManager.PROGRESS_FULL:
			continue
		var spec: Dictionary = TownRules.piece(String(data.p))
		var trample: Dictionary = spec.get("trample", {}) as Dictionary
		if trample.is_empty():
			continue
		var age: float = clampf(START + (1.0 - START) * float(day - int(data.get("b", day))) / GROW_DAYS, START, 1.0)
		var strength: float = float(trample.strength) * age
		var margin: float = float(trample.margin)
		var rect: Rect2 = TownRules.foot_rect(String(data.p), float(data.x), float(data.y))
		splat(out, rect, strength, margin)
		if bool(trample.get("front", false)):
			var front: Rect2 = TownRules.front_rect(String(data.p), float(data.x), float(data.y))
			if front.has_area():
				splat(out, front, strength, margin * 0.7)
	for way: Variant in paths:
		var entry: Dictionary = way as Dictionary
		if int(entry.d) != 1:
			continue
		var pts: Array = entry.p as Array
		for k: int in pts.size() - 1:
			var a: Vector2 = Vector2(float((pts[k] as Array)[0]), float((pts[k] as Array)[1]))
			var b: Vector2 = Vector2(float((pts[k + 1] as Array)[0]), float((pts[k + 1] as Array)[1]))
			for step: int in range(int(a.distance_to(b) / 4.0) + 1):
				var at: Vector2 = a.lerp(b, float(step) * 4.0 / maxf(a.distance_to(b), 1.0))
				splat(out, Rect2(at, Vector2.ZERO), PATH_STRENGTH, PATH_MARGIN)
	return out


## The picture the ground shader reads (R8, one pixel a cell) and the rect it covers in world px (x, y, w, h).
static func field_image(cells: Dictionary, origin: Vector2) -> Image:
	var img: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_R8)
	var base: Vector2i = cell_of(origin)
	for key: Vector2i in cells:
		var x: int = key.x - base.x
		var y: int = key.y - base.y
		if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
			img.set_pixel(x, y, Color(float(cells[key]), 0.0, 0.0))
	return img


static func origin_for(center: Vector2) -> Vector2:
	return ((center - Vector2(SIZE, SIZE) * CELL * 0.5) / CELL).floor() * CELL
