class_name MapHallgrat
extends RefCounted
## Hallgrat on the map (M), drawn for `MapWindow` under the markers (docs/stadt_westen_konzept.md): the stone town as a plan of itself, its paved
## squares, its ways, its houses and the town wall in the map's own pixel hand (see `draw`). Only what the player has seen shows (`MapDiscovery`); the name and the
## hover card come from the town's own map marker (`Hallgrat.map_marker`, style `hallgrat`). Everything is read once from data/hallgrat.json and
## data/hallgrat_art.json; nothing here is state.

const DOT: Color = Color("d6cdea") ## streets and paving: the map's pale ink
const ROOF_TONE: Color = Color("8a6fb0") ## slate roofs
const WALL_TONE: Color = Color("6d6a9a")
const HOUSE: Array = ["..R..", ".RRR.", "RRRRR", ".XwX.", ".XXX."]
const HALL: Array = ["...R...", ".RRRRR.", "RRRRRRR", ".XwXwX.", ".XXXXX."]

var _loaded: bool = false
var _ways: Array[PackedVector2Array] = [] ## tiles
var _squares: Array[Rect2] = [] ## tiles
var _houses: Array[PackedVector2Array] = [] ## tiles, footprints
var _walls: Array[PackedVector2Array] = [] ## tiles: the town wall
var _mids: Array[Vector2] = [] ## tiles: the middle of every house
var _sizes: Array[float] = [] ## tiles: how wide every house is
var _bounds: Rect2 = Rect2()


func _load() -> void:
	_loaded = true
	var data: Dictionary = DataRegistry.table("hallgrat")
	if data.is_empty():
		return
	var b: Array = data.get("bounds", []) as Array
	if b.size() == 4:
		_bounds = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	for way: Dictionary in data.get("ways", []) as Array:
		var line: PackedVector2Array = PackedVector2Array()
		for p: Array in way.get("line", []) as Array:
			line.append(Vector2(float(p[0]) + 0.5, float(p[1]) + 0.5))
		if line.size() >= 2:
			_ways.append(_round(_round(line))) ## the plan's lines go in tile steps: rounded like the paved streets
	for place: Dictionary in data.get("places", []) as Array:
		var r: Array = place.get("rect", []) as Array
		if r.size() == 4 and String(place.get("kind", "")) == "square":
			_squares.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	for run: Dictionary in data.get("wall_runs", []) as Array: ## the town wall (style `stadt`; the low garden walls are too small for the map)
		if String(run.get("style", "")) != "stadt":
			continue
		var line: PackedVector2Array = PackedVector2Array()
		var pts: Array = run.get("pts", []) as Array
		for k: int in range(0, pts.size(), 4):
			line.append(Vector2(float((pts[k] as Array)[0]), float((pts[k] as Array)[1])) / 16.0)
		line.append(Vector2(float((pts[pts.size() - 1] as Array)[0]), float((pts[pts.size() - 1] as Array)[1])) / 16.0)
		if line.size() >= 2:
			_walls.append(line)
	var types: Dictionary = DataRegistry.table("hallgrat_art").get("types", {}) as Dictionary
	for spec: Dictionary in data.get("placed", []) as Array:
		var info: Dictionary = types.get(String(spec.type), {}) as Dictionary
		var feet: Array = spec.px as Array
		var at: Vector2 = Vector2(float(feet[0]), float(feet[1]))
		var flip: float = -1.0 if bool(spec.get("flip", false)) else 1.0
		var poly: PackedVector2Array = PackedVector2Array()
		if info.has("poly"):
			for q: Array in info.poly as Array:
				poly.append((at + Vector2(float(q[0]) * flip, float(q[1]))) / 16.0)
		elif info.has("foot"):
			var foot: Array = info.foot as Array
			var w: float = float(foot[0]) / 2.0
			var d: float = float(foot[1])
			for q: Vector2 in [Vector2(-w, -d), Vector2(w, -d), Vector2(w, 0), Vector2(-w, 0)]:
				poly.append((at + q) / 16.0)
		if poly.size() >= 3:
			_houses.append(poly)
			var mid: Vector2 = Vector2.ZERO
			var lo: Vector2 = poly[0]
			var hi: Vector2 = poly[0]
			for q: Vector2 in poly:
				mid += q
				lo = lo.min(q)
				hi = hi.max(q)
			_mids.append(mid / poly.size())
			_sizes.append(hi.x - lo.x)


## `to_screen` maps a tile to the screen, `scale` = screen px per tile, `seen(tile)` = the fog is lifted there. Drawn in the map's own hand:
## streets as dotted ink paths, squares as a sprinkle of paving dots, every house a little pixel house with an ink rim (the home town's
## look), the town wall a battlement line. Below zoom 0.9 only the town's marker stands there.
func draw(canvas: CanvasItem, scale: float, fade: float, size: Vector2, to_screen: Callable, seen: Callable) -> void:
	if not _loaded:
		_load()
	if _bounds.size == Vector2.ZERO or scale < 0.9:
		return
	var a: Vector2 = to_screen.call(_bounds.position) as Vector2
	var b: Vector2 = to_screen.call(_bounds.end) as Vector2
	if b.x < 0.0 or b.y < 0.0 or a.x > size.x or a.y > size.y:
		return
	var f: float = fade * clampf((scale - 0.9) / 0.3, 0.0, 1.0)
	for r: Rect2 in _squares: # paving: a loose sprinkle of light dots
		if not bool(seen.call(r.get_center())):
			continue
		var p0: Vector2 = (to_screen.call(r.position) as Vector2).round()
		var p1: Vector2 = (to_screen.call(r.end) as Vector2).round()
		var y: float = p0.y
		while y < p1.y:
			var x: float = p0.x + (2.0 if int(y) % 6 == 0 else 0.0)
			while x < p1.x:
				canvas.draw_rect(Rect2(Vector2(x, y), Vector2.ONE), Color(DOT, 0.5 * f))
				x += 4.0
			y += 3.0
	for line: PackedVector2Array in _ways: # streets: dotted paths, an ink dot under every light one
		var pts: PackedVector2Array = _screen_line(line, to_screen, seen)
		var carry: float = 0.0
		for i: int in pts.size() - 1:
			var ab: Vector2 = pts[i + 1] - pts[i]
			var length: float = ab.length()
			var t: float = carry
			while t < length:
				var p: Vector2 = (pts[i] + ab * (t / length)).round()
				canvas.draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(VineStyle.OUTLINE, 0.7 * f))
				canvas.draw_rect(Rect2(p, Vector2.ONE), Color(DOT, f))
				t += 2.0
			carry = t - length
	for line: PackedVector2Array in _walls:
		var pts: PackedVector2Array = _screen_line(line, to_screen, seen)
		if pts.size() < 2:
			continue
		var count: int = 0
		for i: int in pts.size() - 1:
			var n: int = int(pts[i].distance_to(pts[i + 1]))
			for k: int in n:
				var p: Vector2 = pts[i].lerp(pts[i + 1], float(k) / maxf(n, 1.0)).round()
				canvas.draw_rect(Rect2(p - Vector2(1, 0), Vector2(3, 1)), Color(VineStyle.OUTLINE, 0.9 * f))
				canvas.draw_rect(Rect2(p, Vector2.ONE), Color(VineStyle.PETAL if count % 3 == 0 else WALL_TONE, f))
				count += 1
	var used: Array[Vector2] = []
	for i: int in _houses.size():
		var mid: Vector2 = _mids[i]
		if not bool(seen.call(mid)):
			continue
		var at: Vector2 = (to_screen.call(mid) as Vector2).round()
		if at.x < -8.0 or at.y < -8.0 or at.x > size.x + 8.0 or at.y > size.y + 8.0:
			continue
		var big: bool = _sizes[i] > 9.0
		var room: float = 8.0 if big else 6.0
		var clear: bool = true
		for u: Vector2 in used:
			if absf(u.x - at.x) < room and absf(u.y - at.y) < 5.0:
				clear = false
				break
		if not clear:
			continue
		used.append(at)
		_house(canvas, at, HALL if big else HOUSE, f)


## A little house in pixels: the outline first, then roof and wall.
func _house(canvas: CanvasItem, at: Vector2, rows: Array, fade: float) -> void:
	var w: int = String(rows[0]).length()
	var origin: Vector2 = at - Vector2(w / 2, rows.size() - 1)
	for pass_index: int in 2:
		for y: int in rows.size():
			var row: String = rows[y]
			for x: int in w:
				var ch: String = row[x]
				if ch == ".":
					continue
				if pass_index == 0:
					for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
						canvas.draw_rect(Rect2(origin + Vector2(x, y) + o, Vector2.ONE), Color(VineStyle.OUTLINE, 0.9 * fade))
				else:
					var color: Color = ROOF_TONE if ch == "R" else (Color(VineStyle.WARM_GLOW) if ch == "w" else VineStyle.PETAL)
					canvas.draw_rect(Rect2(origin + Vector2(x, y), Vector2.ONE), Color(color, fade))


## The screen points of the seen part of a line (a line is cut where it runs into unseen land).
func _screen_line(line: PackedVector2Array, to_screen: Callable, seen: Callable) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for q: Vector2 in line:
		if not bool(seen.call(q)):
			if out.size() >= 2:
				return out
			out.clear()
			continue
		out.append((to_screen.call(q) as Vector2).round())
	return out


## One Chaikin pass: every corner cut, the ends kept.
static func _round(line: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array([line[0]])
	for i: int in line.size() - 1:
		out.append(line[i].lerp(line[i + 1], 0.25))
		out.append(line[i].lerp(line[i + 1], 0.75))
	out.append(line[line.size() - 1])
	return out
