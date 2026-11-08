class_name VoidFeather
extends RefCounted
## The feathers of Mornath (docs/boss_sky_cleaver.md): big razor feathers of black void flesh, a shaft of basalt that glows like a vein, torn barbs, a cold violet
## rim on the side that faces the light. Rasterised pixel by pixel at any direction (never rotated afterwards), so every angle is as crisp as the next.
## `art(length, width, angle, variant)` gives {"body": lit texture, "glow": additive texture, "tip": pixel of the tip, "base": pixel of the quill, "size": Vector2};
## the angle is the direction base -> tip on the screen, snapped to 15 degrees. Textures are cached.

const OUTLINE: Color = Color("040208")
const DARK: Color = Color("07040d")
const FLESH: Color = Color("0c0814")
const MID: Color = Color("150e24")
const HIGH: Color = Color("221740")
const RIM: Color = Color("5a36b8")
const ROCK2: Color = Color("262440")
const ROCK3: Color = Color("45436a")
const VEIN: Color = Color("7d57e0")
const VEIN_LIGHT: Color = Color("a98af0")
const CORE: Color = Color("ecd2ff")
const STEPS: int = 24
const LIGHT: Vector2 = Vector2(-0.55, -0.83) ## the light comes from the top left

## The sizes the fight uses (length, width): kept here so the cache can be filled before they are needed (`warm_list`).
const FALL: Vector2i = Vector2i(20, 7) ## rain
const THROWN: Vector2i = Vector2i(22, 7) ## leaving a wing towards a barrier
const SHOT: Vector2i = Vector2i(26, 9)
const SHOT_STUCK: Vector2i = Vector2i(40, 12)
const SALVO: Vector2i = Vector2i(16, 6)
const SALVO_STUCK: Vector2i = Vector2i(24, 8)
const LINE: Vector2i = Vector2i(22, 7)
const LINE_STUCK: Vector2i = Vector2i(30, 10)
const BARRIER_LENGTHS: Array[int] = [34, 37, 40]
const BARRIER_WIDTH: int = 11
const LEANS: Array[float] = [-0.26, 0.0, 0.26]

static var _cache: Dictionary = {}
static var _warm: Array[Array] = []
static var _warm_at: int = 0


## Everything the fight will ask for, so that no feather has to be drawn for the first time in the middle of an attack.
static func warm_list() -> Array[Array]:
	if not _warm.is_empty():
		return _warm
	for lean: float in LEANS:
		for v: int in 4:
			_warm.append([FALL.x, FALL.y, PI / 2.0 + lean, v])
		for length: int in BARRIER_LENGTHS:
			for v: int in 4:
				_warm.append([length, BARRIER_WIDTH, PI / 2.0 + lean, v])
		for stuck: Vector2i in [SHOT_STUCK, SALVO_STUCK, LINE_STUCK]:
			for v: int in 4:
				_warm.append([stuck.x, stuck.y, PI / 2.0 + lean, v])
	for k: int in STEPS:
		for size: Vector2i in [THROWN, SHOT, SALVO, LINE]:
			for v: int in 4: ## the fight rolls 0..3 for every one of them: a missing picture is drawn in the middle of the attack (0.5-1.6 ms each, a chase salvo needs ~30)
				_warm.append([size.x, size.y, float(k) / float(STEPS) * TAU, v])
	return _warm


## Draws some of the feathers of `warm_list` that are not cached yet, for at most `budget_usec`. True when all are done.
static func warm_step(budget_usec: int) -> bool:
	var list: Array[Array] = warm_list()
	var start: int = Time.get_ticks_usec()
	while _warm_at < list.size() and Time.get_ticks_usec() - start < budget_usec:
		var e: Array = list[_warm_at]
		art(int(e[0]), int(e[1]), float(e[2]), int(e[3]))
		_warm_at += 1
	return _warm_at >= list.size()


static func quantise(angle: float) -> int:
	return posmod(roundi(angle / TAU * float(STEPS)), STEPS)


## Cached art for a feather `length` px long and `width` px wide whose tip points at `angle` (screen angle, 0 = right, PI/2 = down).
static func art(length: int, width: int, angle: float, variant: int = 0) -> Dictionary:
	var step: int = quantise(angle)
	var key: String = "%d|%d|%d|%d" % [length, width, step, variant]
	if not _cache.has(key):
		_cache[key] = _render(length, width, float(step) / float(STEPS) * TAU, variant)
	return _cache[key] as Dictionary


static func _hash(a: int, b: int) -> float:
	var h: int = (a * 374761393 + b * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## Half width of the vane at `u` (0 = quill, 1 = tip), in px.
static func _half(u: float, half: float) -> float:
	if u < 0.1:
		return 0.55
	if u < 0.42:
		return lerpf(0.55, half, smoothstep(0.1, 0.42, u))
	var t: float = (u - 0.42) / 0.58
	return half * pow(maxf(1.0 - t * t, 0.0), 0.55)


static func _render(length: int, width: int, theta: float, variant: int) -> Dictionary:
	var axis: Vector2 = Vector2.from_angle(theta)
	var across: Vector2 = axis.orthogonal()
	var half: float = float(width) * 0.5
	var bend_k: float = (_hash(variant, 7) - 0.5) * 0.16
	var pad: int = 4
	var lo: Vector2 = Vector2(1e9, 1e9)
	var hi: Vector2 = Vector2(-1e9, -1e9)
	for corner: Vector2 in [Vector2.ZERO, axis * float(length), across * (half + 2.0), -across * (half + 2.0), axis * float(length) * 0.55 + across * (half + 2.0), axis * float(length) * 0.55 - across * (half + 2.0)]:
		lo = Vector2(minf(lo.x, corner.x), minf(lo.y, corner.y))
		hi = Vector2(maxf(hi.x, corner.x), maxf(hi.y, corner.y))
	var w: int = int(ceil(hi.x - lo.x)) + pad * 2
	var h: int = int(ceil(hi.y - lo.y)) + pad * 2
	var origin: Vector2 = Vector2(float(pad), float(pad)) - lo
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(w * h)
	var shade: PackedByteArray = PackedByteArray()
	shade.resize(w * h)
	var glow: PackedByteArray = PackedByteArray()
	glow.resize(w * h)
	var split_at: float = 0.5 + _hash(variant, 3) * 0.14 ## where the vane has a split
	var split_side: int = 1 if _hash(variant, 5) > 0.5 else 0
	for py: int in h:
		for px: int in w:
			var p: Vector2 = Vector2(float(px) + 0.5, float(py) + 0.5) - origin
			var u: float = p.dot(axis) / float(length)
			if u < 0.0 or u > 1.0:
				continue
			var v: float = p.dot(across) - bend_k * float(length) * u * u
			var hw: float = _half(u, half)
			var av: float = absf(v)
			if av > hw:
				continue
			var side: int = 1 if v > 0.0 else 0
			var e: float = av / maxf(hw, 0.001)
			var phase: float = u * float(length) - av ## the barbs leave the shaft at 45 degrees: clean diagonals in the pixel grid
			var barb: int = int(floor(phase / 3.0))
			var stripe: float = fposmod(phase, 3.0) / 3.0
			if u > 0.13 and av > 0.7:
				# a comb edge: the barbs end one by one, some are torn short
				var cut: float = _hash(barb + side * 57, variant + 11)
				if e > 0.74 and stripe > 0.62 and cut > 0.35:
					continue
				if e > 1.0 - cut * cut * 0.42:
					continue
				if side == split_side and absf(u - split_at) < 0.012 + 0.012 * e and e > 0.28:
					continue ## the split in the vane
			var i: int = py * w + px
			mask[i] = 1
			# 1 shaft, 2 body, 3 lit rim, 4 dark rim, 5 gap between barbs, 6 lit barb near the shaft, 7 mid barb
			var kind: int = 2
			if av < 0.6 and u > 0.02:
				kind = 1
			else:
				var lit: float = (across * (1.0 if v > 0.0 else -1.0)).dot(LIGHT)
				if e > 0.8:
					kind = 3 if lit > 0.05 else 4
				elif stripe < 0.34:
					kind = 5
				elif e < 0.5 and lit > -0.2:
					kind = 6
				elif e < 0.7:
					kind = 7
			shade[i] = kind
			if kind == 1:
				glow[i] = 150
			elif kind != 4 and e > 0.18 and e < 0.8 and stripe < 0.34 and barb % 2 == 0:
				glow[i] = 70 ## every other gap between the barbs holds a thread of light
			elif e > 0.8 and stripe > 0.5 and barb % 3 == 0:
				glow[i] = 95 ## the barb tips along the edge catch the light
	var body: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var glow_image: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for py: int in h:
		for px: int in w:
			var i: int = py * w + px
			if mask[i] == 1:
				var color: Color = FLESH
				match shade[i]:
					1:
						color = Color("7a66c8") if (px + py) % 2 == 0 else Color("5a4aa0")
					3:
						color = Color("8a68f0")
					4:
						color = Color("1a1236")
					5:
						color = Color("0a0614")
					6:
						color = Color("4a3a9a")
					7:
						color = Color("33266b")
					_:
						color = Color("22184a")
				body.set_pixel(px, py, color)
				if glow[i] > 0:
					glow_image.set_pixel(px, py, Color(VEIN_LIGHT if glow[i] > 160 else VEIN, float(glow[i]) / 255.0))
			else:
				var near: bool = false
				var near_shaft: bool = false
				for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var qx: int = px + off.x
					var qy: int = py + off.y
					if qx >= 0 and qy >= 0 and qx < w and qy < h and mask[qy * w + qx] == 1:
						near = true
						if glow[qy * w + qx] >= 200:
							near_shaft = true
				if near:
					body.set_pixel(px, py, OUTLINE)
					glow_image.set_pixel(px, py, Color(VEIN, 0.3 if near_shaft else 0.2)) ## a thin halo round the feather
	var tip: Vector2 = origin + axis * float(length)
	var tip_px: Vector2i = Vector2i(int(floor(tip.x)), int(floor(tip.y)))
	for off: Vector2i in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		var tx: int = tip_px.x + off.x
		var ty: int = tip_px.y + off.y
		if tx >= 0 and ty >= 0 and tx < w and ty < h and mask[ty * w + tx] == 1:
			glow_image.set_pixel(tx, ty, Color(CORE, 0.95))
	var result: Dictionary = {}
	result["body"] = ImageTexture.create_from_image(body)
	result["glow"] = ImageTexture.create_from_image(glow_image)
	result["tip"] = tip
	result["base"] = origin
	result["size"] = Vector2(w, h)
	return result


## The centre of the feather in image pixels (for projectiles that are drawn by their middle).
static func middle(a: Dictionary) -> Vector2:
	return ((a["tip"] as Vector2) + (a["base"] as Vector2)) * 0.5
