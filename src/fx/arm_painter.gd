class_name ArmPainter
extends RefCounted
## Paints her right arm the way tools/art_hero3d.py paints her left one (docs/griff_system.md): the same parts (plum coat sleeve,
## black leather bracer with the glowing violet band below the elbow, leather glove), 4x4 subpixel coverage (`opaque >= 6` of 16),
## the same light from the upper left in four flat bands, crease ink where a part or hair lock lies in front of another, and a
## per-pixel 3D depth test against the sprite sheet's `*_blood.png` depth/material channels so hair, head and torso occlude the arm cleanly.

const S: float = GripRig.SCALE
const COAT: int = 0
const LEATHER: int = 1
const VIOLET: int = 2
const SKIN: int = 3
const SOLID_MIN: int = 6 ## art_hero3d to_pixels: >= 6 of 16 (4x4) subpixels makes a solid pixel
const RAMPS: Array = [
	[Color("1a0d24"), Color("3a2144"), Color("593766"), Color("7e548c")], ## art_hero3d COAT: puffed wine-plum short sleeve
	[Color("0e0716"), Color("1e112c"), Color("36224c"), Color("5e427e")], ## LEATHER: wrist bracer
	[Color("34185e"), Color("6636ad"), Color("9468ee"), Color("cbaaff")], ## VIOLET: bracelet accent
	[Color("dc9496"), Color("f2b8b2"), Color("fde0d2"), Color("fff3e8")], ## SKIN: bare porcelain forearm & hand
]
const BANDS: Array[float] = [0.06, 0.34, 0.7] ## shade_band thresholds for cloth and leather
const SKIN_BANDS: Array[float] = [-0.28, 0.06, 0.52] ## shade_band thresholds for skin
const INK_DEPTH: float = 2.4 ## a pixel this much behind a neighbour gets its darkest shade (to_pixels)
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SUB_OFF: Array[float] = [-0.375, -0.125, 0.125, 0.375] ## 4x4 subpixel centres relative to pixel centre

static var _depth_cache: Dictionary = {} ## Texture2D -> {bytes: PackedByteArray, w: int, h: int, valid: bool}


## Extracts and caches raw RGBA8 bytes of a depth-encoded `*_blood.png` texture (`valid` = marker (255, 137, 42, 1) at (0, 0)).
static func depth_source(blood_tex: Texture2D) -> Dictionary:
	if blood_tex == null:
		return {}
	if _depth_cache.has(blood_tex):
		return _depth_cache[blood_tex] as Dictionary
	var img: Image = blood_tex.get_image()
	if img == null or img.is_empty():
		_depth_cache[blood_tex] = {}
		return {}
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = img.get_data()
	var valid: bool = bytes.size() >= 4 and bytes[1] == 137 and bytes[2] == 42 and bytes[3] == 1
	var entry: Dictionary = {"bytes": bytes, "w": img.get_width(), "h": img.get_height(), "valid": valid} if valid else {}
	_depth_cache[blood_tex] = entry
	return entry


## Draws the arm on `canvas` whose origin sits at `origin` (feet-relative screen px). Returns where the violet band is on the canvas
## (a worn bracelet is drawn there) and the direction of the forearm on the screen, as [band, forearm].
static func paint(canvas: CanvasItem, origin: Vector2, shoulder: Vector3, elbow: Vector3, wrist: Vector3, fist: Vector3, alpha: float, depth_ctx: Dictionary = {}) -> Array[Vector2]:
	var image: Dictionary = raster(shoulder, elbow, wrist, fist, depth_ctx)
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
static func raster(shoulder: Vector3, elbow: Vector3, wrist: Vector3, fist: Vector3, depth_ctx: Dictionary = {}) -> Dictionary:
	var has_depth: bool = bool(depth_ctx.get("valid", false))
	var arm_style: String = String(depth_ctx.get("arm_style", "default"))
	var arm_tint: Color = depth_ctx.get("arm_tint", Color.WHITE) as Color
	var bare_arm: bool = arm_style == "bare"
	var parts: Array = []
	var puff_end: Vector3 = shoulder.lerp(elbow, 0.44)
	var fore_mid: Vector3 = elbow.lerp(wrist, 0.52)
	if bare_arm:
		if not has_depth:
			parts.append([shoulder, shoulder, 1.32 * S, 1.32 * S, SKIN, -1.0, -1.0])
		parts.append([shoulder, elbow, 1.15 * S, 1.00 * S, SKIN, -1.0, -1.0])
		parts.append([elbow, wrist, 1.00 * S, 0.88 * S, SKIN, -1.0, -1.0])
		parts.append([fist, fist, 0.98 * S, 0.98 * S, SKIN, -1.0, -1.0])
	else:
		if not has_depth:
			parts.append([shoulder, shoulder, 1.65 * S, 1.65 * S, COAT, -1.0, -1.0])
		parts.append([shoulder, puff_end, 1.58 * S, 1.28 * S, COAT, -1.0, -1.0])
		parts.append([puff_end, elbow, 1.06 * S, 1.00 * S, SKIN, -1.0, -1.0])
		parts.append([elbow, fore_mid, 1.02 * S, 0.95 * S, SKIN, -1.0, -1.0])
		parts.append([fore_mid, wrist, 1.12 * S, 0.96 * S, LEATHER, -1.0, -1.0])
		parts.append([fist, fist, 0.98 * S, 0.98 * S, SKIN, -1.0, -1.0])
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for part: Array in parts:
		for p: Vector3 in [part[0] as Vector3, part[1] as Vector3]:
			var s: Vector2 = GripRig.screen(p)
			var r: float = maxf(float(part[2]), float(part[3])) + 2.0
			lo = Vector2(minf(lo.x, s.x - r), minf(lo.y, s.y - r))
			hi = Vector2(maxf(hi.x, s.x + r), maxf(hi.y, s.y + r))
	var x0: int = floori(lo.x)
	var y0: int = floori(lo.y)
	var w: int = clampi(ceili(hi.x) - x0 + 1, 1, 64)
	var h: int = clampi(ceili(hi.y) - y0 + 1, 1, 64)
	var n_px: int = w * h
	var code: PackedInt32Array = PackedInt32Array()
	code.resize(n_px)
	code.fill(-1)
	var cov: PackedInt32Array = PackedInt32Array() ## 16-bit 4x4 subpixel coverage mask per pixel
	cov.resize(n_px)
	var zbuf: PackedFloat32Array = PackedFloat32Array()
	zbuf.resize(n_px)
	zbuf.fill(-1e9)
	var light: Vector3 = GripRig.light()
	for part: Array in parts:
		_raster(part, x0, y0, w, h, code, cov, zbuf, light)
	# Apply 4x4 solidity rule (`opaque >= 6` of 16) and per-pixel sprite depth occlusion
	var bytes: PackedByteArray = depth_ctx.get("bytes", PackedByteArray()) as PackedByteArray if has_depth else PackedByteArray()
	var atlas_w: int = int(depth_ctx.get("w", 0))
	var cell_x: int = int(depth_ctx.get("cell_x", 0))
	var cell_y: int = int(depth_ctx.get("cell_y", 0))
	var cell_w: int = int(depth_ctx.get("cell_w", 0))
	var cell_h: int = int(depth_ctx.get("cell_h", 0))
	var foot_x: int = int(depth_ctx.get("foot_x", 24))
	var foot_y: int = int(depth_ctx.get("foot_y", 51))
	var skew: float = float(depth_ctx.get("skew", 0.0))
	var dy_px: int = roundi(float(depth_ctx.get("dy", 0.0)))
	for y: int in h:
		var sy_local: int = (y0 + y) - dy_px
		var skew_dx: int = roundi(-skew * float(sy_local))
		var cy: int = sy_local + foot_y
		for x: int in w:
			var i: int = y * w + x
			if code[i] < 0:
				continue
			var bits: int = cov[i]
			bits = bits - ((bits >> 1) & 0x5555)
			bits = (bits & 0x3333) + ((bits >> 2) & 0x3333)
			var pop: int = (((bits + (bits >> 4)) & 0x0F0F) * 0x0101) >> 8
			if pop < SOLID_MIN:
				code[i] = -1
				continue
			if not has_depth or cy < 0 or cy >= cell_h:
				continue
			var cx: int = (x0 + x) - skew_dx + foot_x
			if cx < 0 or cx >= cell_w:
				continue
			var bidx: int = ((cell_y + cy) * atlas_w + (cell_x + cx)) * 4
			var a8: int = bytes[bidx + 3]
			if a8 >= 254:
				var body_z: float = float(bytes[bidx + 1]) * 0.25 - 20.0
				var body_mat: int = bytes[bidx + 2] - 1 ## 0 = HAIR, 1 = SKIN
				if zbuf[i] <= body_z + (0.45 if body_mat <= 1 else 0.15):
					code[i] = -1
			elif a8 == 1 and bytes[bidx + 2] >= 64:
				var out_mat: int = bytes[bidx + 2] - 64
				var out_z: float = float(bytes[bidx + 1]) * 0.25 - 20.0
				if out_mat <= 1 and zbuf[i] <= out_z + 0.45: ## keep hair & face 1px outlines crisp over the arm
					code[i] = -1
	# Crease ink: a visible arm pixel clearly behind an adjacent arm part OR behind an adjacent hair/body pixel gets band 0
	var inked: PackedInt32Array = code.duplicate()
	for y: int in h:
		var sy_local: int = (y0 + y) - dy_px
		var skew_dx: int = roundi(-skew * float(sy_local))
		var cy: int = sy_local + foot_y
		for x: int in w:
			var i: int = y * w + x
			if code[i] < 0:
				continue
			var darkened: bool = false
			for o: Vector2i in NEIGHBOURS:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and code[ny * w + nx] >= 0 and zbuf[ny * w + nx] > zbuf[i] + INK_DEPTH:
					darkened = true
					break
			if not darkened and has_depth:
				var cx: int = (x0 + x) - skew_dx + foot_x
				for o: Vector2i in NEIGHBOURS:
					var ncx: int = cx + o.x
					var ncy: int = cy + o.y
					if ncx >= 0 and ncx < cell_w and ncy >= 0 and ncy < cell_h:
						var nbidx: int = ((cell_y + ncy) * atlas_w + (cell_x + ncx)) * 4
						if bytes[nbidx + 3] >= 254 and (float(bytes[nbidx + 1]) * 0.25 - 20.0) > zbuf[i] + INK_DEPTH:
							darkened = true
							break
			if darkened:
				inked[i] = (code[i] / 4) * 4
	# Outline: empty pixels touching a visible arm pixel get its ink, unless sprite hair/body sits at or in front of the arm there
	var colors: Array[Color] = []
	colors.resize(n_px)
	var filled: PackedByteArray = PackedByteArray()
	filled.resize(n_px)
	for y: int in h:
		var sy_local: int = (y0 + y) - dy_px
		var skew_dx: int = roundi(-skew * float(sy_local))
		var cy: int = sy_local + foot_y
		for x: int in w:
			var i: int = y * w + x
			if inked[i] >= 0:
				var mat: int = inked[i] / 4
				var band: int = inked[i] % 4
				if mat == VIOLET:
					band = maxi(band, 2)
				var col: Color = (RAMPS[mat] as Array)[band] as Color
				if mat == COAT or mat == LEATHER:
					col = _dye_cloth(col, arm_tint)
				colors[i] = col
				filled[i] = 1
				continue
			var best_nb: int = -1
			var best_z: float = -1e9
			for o: Vector2i in NEIGHBOURS:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and code[ny * w + nx] >= 0 and zbuf[ny * w + nx] > best_z:
					best_z = zbuf[ny * w + nx]
					best_nb = code[ny * w + nx]
			if best_nb < 0:
				continue
			if has_depth and cy >= 0 and cy < cell_h:
				var cx: int = (x0 + x) - skew_dx + foot_x
				if cx >= 0 and cx < cell_w:
					var bidx: int = ((cell_y + cy) * atlas_w + (cell_x + cx)) * 4
					var a8: int = bytes[bidx + 3]
					if a8 >= 254:
						var body_z: float = float(bytes[bidx + 1]) * 0.25 - 20.0
						if best_z <= body_z + INK_DEPTH: ## seamless shoulder join & never paint ink onto hair in front
							continue
					elif a8 == 1 and bytes[bidx + 2] >= 64:
						var out_mat: int = bytes[bidx + 2] - 64
						var out_z: float = float(bytes[bidx + 1]) * 0.25 - 20.0
						if out_mat <= 1 and best_z <= out_z + 0.45:
							continue
			colors[i] = _ink(best_nb / 4)
			filled[i] = 1
	return {"x0": x0, "y0": y0, "w": w, "h": h, "colors": colors, "filled": filled, "codes": inked}


static func _raster(part: Array, x0: int, y0: int, w: int, h: int, code: PackedInt32Array, cov: PackedInt32Array, zbuf: PackedFloat32Array, light: Vector3) -> void:
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
	var inv_len2: float = 1.0 / len2 if len2 > 0.0001 else 0.0
	var axis_len: float = a3.distance_to(b3)
	var r_max: float = maxf(ra, rb) + (0.12 if ring0 >= 0.0 else 0.0)
	var bx0: int = clampi(floori(minf(a.x, b.x) - r_max - 0.6) - x0, 0, w)
	var bx1: int = clampi(ceili(maxf(a.x, b.x) + r_max + 0.6) - x0 + 1, 0, w)
	var by0: int = clampi(floori(minf(a.y, b.y) - r_max - 0.6) - y0, 0, h)
	var by1: int = clampi(ceili(maxf(a.y, b.y) + r_max + 0.6) - y0 + 1, 0, h)
	for y: int in range(by0, by1):
		var py: float = float(y0 + y) + 0.5
		for x: int in range(bx0, bx1):
			var px: float = float(x0 + x) + 0.5
			var p: Vector2 = Vector2(px, py)
			var t: float = clampf((p - a).dot(ab) * inv_len2, 0.0, 1.0)
			var along: float = t * axis_len
			var ring: bool = ring0 >= 0.0 and along >= ring0 and along <= ring1
			var r: float = lerpf(ra, rb, t) + (0.10 if ring else 0.0)
			var off: Vector2 = p - (a + ab * t)
			var d2_c: float = off.length_squared()
			var r_out: float = r + 0.54
			if d2_c > r_out * r_out:
				continue
			var mask: int = 0xFFFF
			var r_in: float = maxf(r - 0.54, 0.0)
			if d2_c > r_in * r_in:
				mask = 0
				var bit: int = 1
				var r2: float = r * r
				for sy: float in SUB_OFF:
					var qy: float = py + sy
					for sx: float in SUB_OFF:
						var qx: float = px + sx
						var qt: float = clampf(((qx - a.x) * ab.x + (qy - a.y) * ab.y) * inv_len2, 0.0, 1.0)
						var dx: float = qx - (a.x + ab.x * qt)
						var dy: float = qy - (a.y + ab.y * qt)
						if dx * dx + dy * dy <= r2:
							mask |= bit
						bit <<= 1
				if mask == 0:
					continue
			var i: int = y * w + x
			cov[i] |= mask
			var clamped_d2: float = minf(d2_c, r * r * 0.96)
			var dz: float = sqrt(maxf(r * r - clamped_d2, 0.0))
			var z: float = GripRig.depth(a3.lerp(b3, t)) + dz
			if z <= zbuf[i]:
				continue
			zbuf[i] = z
			var n: Vector3 = (Vector3(1.0, 0.0, 0.0) * off.x + GripRig.SCREEN_DOWN * off.y + GripRig.VIEW * dz) / maxf(r, 0.01)
			var lam: float = 0.78 * n.dot(light) + 0.22 * (0.5 + 0.5 * n.z) - 0.06
			var band: int = 0
			var th_arr: Array[float] = SKIN_BANDS if mat == SKIN else BANDS
			for th: float in th_arr:
				if lam >= th:
					band += 1
			code[i] = (VIOLET if ring else mat) * 4 + band


## Matches `cosmetic_dye` in `hit_flash.gdshader` for cloth/leather ramps (`tint == white` is lossless).
static func _dye_cloth(col: Color, tint: Color) -> Color:
	if absf(tint.r - 1.0) + absf(tint.g - 1.0) + absf(tint.b - 1.0) < 0.005:
		return col
	var lum: float = col.r * 0.3 + col.g * 0.59 + col.b * 0.11
	if lum < 0.055:
		return col
	var t: float = clampf((lum - 0.055) / 0.55, 0.0, 1.0)
	var dark: Color = Color(tint.r * 0.22, tint.g * 0.22, tint.b * 0.22, col.a)
	var light_c: Color = tint.lerp(Color(0.96, 0.92, 0.98, 1.0), 0.42)
	light_c.a = col.a
	return dark.lerp(light_c, t)


## art_hero3d ink_color: unified crisp dark plum-obsidian silhouette outline (#100716).
static func _ink(_mat: int) -> Color:
	return Color("100716")
