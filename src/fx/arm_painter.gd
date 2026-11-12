class_name ArmPainter
extends RefCounted
## Paints her right arm the way tools/art_hero3d.py paints her left one (docs/griff_system.md): the same parts (leather shoulder cap,
## plum coat sleeve, black leather bracer with the glowing violet band below the elbow, leather glove), the same radii, the same light
## from the upper left in four flat bands, the same ink where a part lies in front of another and the same dark outline round it all.
## Every part is a tapered capsule in GripRig space; one sample per pixel centre, a tiny depth buffer, then runs of equal pixels are drawn
## as rectangles. The canvas should carry the player's sprite shader (AttackComponent.mirror_material), so pallor, wetness, the hit flash
## and the daylight grade fall on the arm exactly as on the sheet.

const S: float = GripRig.SCALE
const COAT: int = 0
const LEATHER: int = 1
const VIOLET: int = 2
const RAMPS: Array = [
	[Color("171020"), Color("30203c"), Color("503359"), Color("795884")], ## art_hero3d COAT: the muted plum sleeve
	[Color("09060f"), Color("150f22"), Color("2c2347"), Color("6a5aa6")], ## LEATHER: shoulder cap, bracer, glove
	[Color("34185e"), Color("6636ad"), Color("9468ee"), Color("cbaaff")], ## VIOLET: the band below the elbow (emissive: never darker than band 2)
]
const BANDS: Array[float] = [0.06, 0.34, 0.7] ## shade_band thresholds for cloth and leather
const INK_DEPTH: float = 2.4 ## a pixel this much behind a neighbour gets its darkest shade (to_pixels)
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static var _inks: Array[Color] = []


## Draws the arm on `canvas` whose origin sits at `origin` (feet-relative screen px). Returns where the violet band is on the canvas
## (a worn bracelet is drawn there) and the direction of the forearm on the screen, as [band, forearm].
static func paint(canvas: CanvasItem, origin: Vector2, shoulder: Vector3, elbow: Vector3, wrist: Vector3, fist: Vector3, alpha: float) -> Array[Vector2]:
	var image: Dictionary = raster(shoulder, elbow, wrist, fist)
	var x0: int = image["x0"]
	var y0: int = image["y0"]
	var w: int = image["w"]
	var h: int = image["h"]
	var colors: Array[Color] = image["colors"]
	var filled: PackedByteArray = image["filled"]
	for y: int in h:
		var run_start: int = -1
		var run_color: Color = Color.TRANSPARENT
		for x: int in w + 1:
			var i: int = y * w + x
			var here: bool = x < w and filled[i] == 1
			if run_start >= 0 and (not here or colors[i] != run_color):
				var c: Color = run_color
				c.a *= alpha
				canvas.draw_rect(Rect2(Vector2(x0 + run_start, y0 + y) - origin, Vector2(x - run_start, 1)), c)
				run_start = -1
			if here and run_start < 0:
				run_start = x
				run_color = colors[i]
	var d2: Vector3 = (wrist - elbow).normalized() if wrist.distance_to(elbow) > 0.01 else Vector3.DOWN
	return [GripRig.screen(elbow + d2 * 1.6 * S) - origin, GripRig.screen(wrist) - GripRig.screen(elbow)]


## The arm as pixels (feet-relative screen grid): {x0, y0, w, h, colors (Array[Color]), filled (1 = a pixel), codes (material * 4 + band, -1 none)}.
static func raster(shoulder: Vector3, elbow: Vector3, wrist: Vector3, fist: Vector3) -> Dictionary:
	var d2: Vector3 = (wrist - elbow).normalized() if wrist.distance_to(elbow) > 0.01 else Vector3.DOWN
	## [a, b, radius a, radius b, material, ring start, ring end] (ring = distance from a along the axis that is the violet band)
	var parts: Array = [
		[shoulder, shoulder, 1.75 * S, 1.75 * S, LEATHER, -1.0, -1.0],
		[shoulder, elbow, 1.35 * S, 1.1 * S, COAT, -1.0, -1.0],
		[elbow + d2 * 0.4 * S, wrist, 1.2 * S, 0.95 * S, LEATHER, 1.1 * S, 2.1 * S],
		[fist, fist, 1.08 * S, 1.08 * S, LEATHER, -1.0, -1.0],
	]
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for part: Array in parts:
		for p: Vector3 in [part[0] as Vector3, part[1] as Vector3]:
			var s: Vector2 = GripRig.screen(p)
			var r: float = maxf(float(part[2]), float(part[3])) + 1.5
			lo = Vector2(minf(lo.x, s.x - r), minf(lo.y, s.y - r))
			hi = Vector2(maxf(hi.x, s.x + r), maxf(hi.y, s.y + r))
	var x0: int = floori(lo.x)
	var y0: int = floori(lo.y)
	var w: int = clampi(ceili(hi.x) - x0 + 1, 1, 64)
	var h: int = clampi(ceili(hi.y) - y0 + 1, 1, 64)
	var code: PackedInt32Array = PackedInt32Array()
	code.resize(w * h)
	code.fill(-1)
	var zbuf: PackedFloat32Array = PackedFloat32Array()
	zbuf.resize(w * h)
	zbuf.fill(-1e9)
	var light: Vector3 = GripRig.light()
	for part: Array in parts:
		_raster(part, x0, y0, w, h, code, zbuf, light)
	# ink: a pixel clearly behind a neighbour takes its darkest shade, so the forearm stands off the sleeve it crosses
	var inked: PackedInt32Array = code.duplicate()
	for y: int in h:
		for x: int in w:
			var i: int = y * w + x
			if code[i] < 0:
				continue
			for o: Vector2i in NEIGHBOURS:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and code[ny * w + nx] >= 0 and zbuf[ny * w + nx] > zbuf[i] + INK_DEPTH:
					inked[i] = (code[i] / 4) * 4
					break
	# outline: empty pixels touching the arm get the ink of the part they touch
	var colors: Array[Color] = []
	colors.resize(w * h)
	var filled: PackedByteArray = PackedByteArray()
	filled.resize(w * h)
	for y: int in h:
		for x: int in w:
			var i: int = y * w + x
			if inked[i] >= 0:
				var mat: int = inked[i] / 4
				var band: int = inked[i] % 4
				if mat == VIOLET:
					band = maxi(band, 2)
				colors[i] = (RAMPS[mat] as Array)[band] as Color
				filled[i] = 1
				continue
			for o: Vector2i in NEIGHBOURS:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and code[ny * w + nx] >= 0:
					colors[i] = _ink(code[ny * w + nx] / 4)
					filled[i] = 1
					break
	return {"x0": x0, "y0": y0, "w": w, "h": h, "colors": colors, "filled": filled, "codes": inked}


static func _raster(part: Array, x0: int, y0: int, w: int, h: int, code: PackedInt32Array, zbuf: PackedFloat32Array, light: Vector3) -> void:
	var a3: Vector3 = part[0]
	var b3: Vector3 = part[1]
	var ra: float = part[2]
	var rb: float = part[3]
	var mat: int = part[4]
	var ring0: float = part[5]
	var ring1: float = part[6]
	var a: Vector2 = GripRig.screen(a3)
	var b: Vector2 = GripRig.screen(b3)
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	var axis_len: float = a3.distance_to(b3)
	var r_max: float = maxf(ra, rb) + (0.25 if ring0 >= 0.0 else 0.0)
	var bx0: int = clampi(floori(minf(a.x, b.x) - r_max) - x0, 0, w)
	var bx1: int = clampi(ceili(maxf(a.x, b.x) + r_max) - x0 + 1, 0, w)
	var by0: int = clampi(floori(minf(a.y, b.y) - r_max) - y0, 0, h)
	var by1: int = clampi(ceili(maxf(a.y, b.y) + r_max) - y0 + 1, 0, h)
	for y: int in range(by0, by1):
		for x: int in range(bx0, bx1):
			var p: Vector2 = Vector2(x0 + x + 0.5, y0 + y + 0.5)
			var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0001 else 0.0
			var along: float = t * axis_len
			var ring: bool = ring0 >= 0.0 and along >= ring0 and along <= ring1
			var r: float = lerpf(ra, rb, t) + (0.18 if ring else 0.0)
			var off: Vector2 = p - (a + ab * t)
			var d2: float = off.length_squared()
			if d2 > r * r:
				continue
			var dz: float = sqrt(r * r - d2)
			var z: float = GripRig.depth(a3.lerp(b3, t)) + dz
			var i: int = y * w + x
			if z <= zbuf[i]:
				continue
			zbuf[i] = z
			var n: Vector3 = (Vector3(1.0, 0.0, 0.0) * off.x + GripRig.SCREEN_DOWN * off.y + GripRig.VIEW * dz) / r
			var lam: float = 0.78 * n.dot(light) + 0.22 * (0.5 + 0.5 * n.z) - 0.06
			var band: int = 0
			for th: float in BANDS:
				if lam >= th:
					band += 1
			code[i] = (VIOLET if ring else mat) * 4 + band


## art_hero3d ink_color: the darkest shade of a material, darker still.
static func _ink(mat: int) -> Color:
	if _inks.is_empty():
		for ramp: Array in RAMPS:
			var c: Color = ramp[0] as Color
			_inks.append(Color(c.r * 0.55, c.g * 0.55 * 0.95, c.b * 0.55))
	return _inks[mat]
