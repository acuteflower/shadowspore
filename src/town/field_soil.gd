class_name FieldSoil
extends RefCounted
## The ground picture of one field (docs/farming.md), painted pixel by pixel from the shape of ALL fields so neighbours melt into one big bed and the outer edge
## breaks up into crumbs and grass instead of a hard rectangle. Everything depends only on the world position of the pixel (never on the field), so two fields that
## both paint the same pixel paint it identically; a pixel inside ANOTHER field's footprint is left to that field (it knows the state of its own cells).
##
## Cell look: rough ground (packed earth, pebbles, grass tufts), a hoed bed (rows of ridges and furrows, every four pixels) and a watered bed (the same, darker and wet,
## a few glints). Palette: the town's violet-plum earth (`tools/art_flora.py` SOIL, `bake_ground.py` PATH), lit from the top left like everything else.

const MARGIN: int = 8 ## picture pixels round the footprint, where the edge may crumble outwards
const CELL: int = 16

const ROUGH: Array[Color] = [Color("3c2e36"), Color("4f3f42"), Color("625048"), Color("77655a")]
const BED: Array[Color] = [Color("2c2030"), Color("45323a"), Color("66494a"), Color("8a6a5c")] ## furrow shadow .. ridge light
const WET: Array[Color] = [Color("1c1626"), Color("2a2030"), Color("3d2f3c"), Color("56444c")]
const GLINT: Color = Color("a8c8de")
const EDGE: Array[Color] = [Color("231a26"), Color("372a30")] ## the outline of the bed: ink and the dark earth
const LIP_LIGHT: Color = Color("9a7a68") ## the lit upper edge of the bed
const CRUMB: Array[Color] = [Color("45323a"), Color("5a4444")]
const GRASS: Array[Color] = [Color("2f624e"), Color("3e7d56"), Color("55985f")]


## `rects`: every field footprint in world pixels; `mine`: this field's footprint; `cells`: cell index -> state (see FarmRules); `day`: for the wet look.
static func render(rects: Array[Rect2], mine: Rect2, cols: int, cells: Dictionary, day: int) -> Image:
	var width: int = roundi(mine.size.x) + MARGIN * 2
	var height: int = roundi(mine.size.y) + MARGIN * 2
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	var near: Array[Rect2] = []
	for rect: Rect2 in rects:
		if rect.grow(float(MARGIN) + 6.0).intersects(mine.grow(float(MARGIN))):
			near.append(rect)
	var origin: Vector2 = mine.position - Vector2(float(MARGIN), float(MARGIN))
	for y: int in height:
		for x: int in width:
			var wx: int = roundi(origin.x) + x
			var wy: int = roundi(origin.y) + y
			var p: Vector2 = Vector2(float(wx) + 0.5, float(wy) + 0.5)
			var d: float = _distance(near, p)
			var inside_mine: bool = mine.has_point(p)
			if not inside_mine and d <= 0.0:
				continue ## another field's ground
			var dd: float = d + _noise(wx, wy) * 2.0
			if dd > 2.6:
				continue
			if dd > 0.9:
				if _hash(wx, wy, 11) < (2.6 - dd) / 1.7 * 0.62:
					var pick: float = _hash(wx, wy, 12)
					if pick < 0.14:
						image.set_pixel(x, y, GRASS[int(_hash(wx, wy, 13) * 3.0) % 3]) ## a tuft clinging to the edge
					else:
						image.set_pixel(x, y, CRUMB[0] if pick < 0.6 else CRUMB[1])
				continue
			if dd > -0.6:
				image.set_pixel(x, y, EDGE[0] if (wx + wy) % 2 == 0 else EDGE[1])
				continue
			var color: Color
			if dd > -2.2:
				color = _lip(near, p, wx, wy)
			else:
				var local: Vector2 = p - mine.position
				var cx: int = clampi(floori(local.x / float(CELL)), 0, cols - 1)
				var cy: int = maxi(floori(local.y / float(CELL)), 0)
				var state: Dictionary = cells.get(cy * cols + cx, {}) as Dictionary
				color = _soil(state, int(local.x) % CELL, int(local.y) % CELL, wx, wy, day)
			image.set_pixel(x, y, color)
	return image


## Signed distance to the union of the footprints (negative inside).
static func _distance(rects: Array[Rect2], p: Vector2) -> float:
	var best: float = INF
	for rect: Rect2 in rects:
		var half: Vector2 = rect.size * 0.5
		var q: Vector2 = (p - (rect.position + half)).abs() - half
		var outside: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
		var inner: float = minf(maxf(q.x, q.y), 0.0)
		best = minf(best, outside + inner)
	return best


## The rim of a bed, lit from the top left: light along the top, dark along the underside, in between on the sides.
static func _lip(rects: Array[Rect2], p: Vector2, wx: int, wy: int) -> Color:
	var above: bool = _distance(rects, p + Vector2(0.0, -2.0)) > 0.0
	var below: bool = _distance(rects, p + Vector2(0.0, 2.0)) > 0.0
	var left: bool = _distance(rects, p + Vector2(-2.0, 0.0)) > 0.0
	var right: bool = _distance(rects, p + Vector2(2.0, 0.0)) > 0.0
	if below:
		return BED[0] if _hash(wx, wy, 21) < 0.7 else EDGE[1]
	if above or left:
		return LIP_LIGHT if _hash(wx, wy, 22) < 0.55 else BED[3]
	if right:
		return BED[1]
	return BED[2]


static func _soil(state: Dictionary, lx: int, ly: int, wx: int, wy: int, day: int) -> Color:
	if not bool(state.get("t", 0)):
		return _rough(wx, wy)
	var row: int = ly % 4 ## 0 ridge top, 1 ridge, 2 slope, 3 furrow
	var tone: int = 3 - row
	var wet: bool = FarmRules.is_wet(state, day)
	var jitter: float = _hash(wx, wy, 31)
	if jitter < 0.1:
		tone = maxi(tone - 1, 0) ## a clod breaks the line
	elif jitter > 0.93:
		tone = mini(tone + 1, 3)
	if _noise(floori(float(wx) / 2.0), floori(float(wy) / 4.0)) > 0.45 and row != 3:
		tone = maxi(tone - 1, 0) ## the ridge is lower in places
	if wet:
		if row == 0 and _hash(wx, wy, 32) < 0.09:
			return GLINT
		return WET[tone]
	if lx == 0 or lx == CELL - 1:
		tone = maxi(tone - 1, 0) if _hash(wx, wy, 33) < 0.35 else tone
	return BED[tone]


## Untouched ground: packed earth with pebbles, a root or two and grass trying to come back.
static func _rough(wx: int, wy: int) -> Color:
	var n: float = _noise(floori(float(wx) / 3.0), floori(float(wy) / 3.0)) * 0.5 + 0.5
	var color: Color = ROUGH[clampi(int(n * 4.0), 0, 3)]
	var r: float = _hash(wx, wy, 41)
	if r < 0.045:
		return ROUGH[3].lightened(0.12) ## a pebble
	if r < 0.08:
		return GRASS[int(_hash(wx, wy, 42) * 3.0) % 3].darkened(0.1)
	if r > 0.965:
		return ROUGH[0]
	return color


# ---------- noise (pure integer hash, the same on every peer) ----------

static func _hash(x: int, y: int, salt: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## Smooth value noise 0..1 -> -1..1 on a grid of 4 px plus a finer one.
static func _noise(x: int, y: int) -> float:
	return _smooth(x, y, 4) * 0.65 + _smooth(x, y, 2) * 0.35


static func _smooth(x: int, y: int, cell: int) -> float:
	var gx: int = floori(float(x) / float(cell))
	var gy: int = floori(float(y) / float(cell))
	var fx: float = float(x - gx * cell) / float(cell)
	var fy: float = float(y - gy * cell) / float(cell)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = _hash(gx, gy, cell)
	var b: float = _hash(gx + 1, gy, cell)
	var c: float = _hash(gx, gy + 1, cell)
	var e: float = _hash(gx + 1, gy + 1, cell)
	return (lerpf(lerpf(a, b, fx), lerpf(c, e, fx), fy) - 0.5) * 2.0
