class_name TownPathArt
extends RefCounted
## The picture of a trampled way (a "Trampelweg"), in the colours of the story's footpath (tools/bake_ground.py). Worn, not drawn: the width swells and thins along the way
## (slow noise, now and then a wide place where people stepped aside), a door gets a worn apron in front of it, the edge is not a line but ground thinning out (the
## grass comes back pixel by pixel, in dither and in noise), tufts of grass grow through the middle, the north-west rim lies in shade and the south-east rim catches
## light, so the way lies a little sunk. Made once per way from its polyline, on every peer the same (everything is noise and hash seeded by `seed_value`).

const SHADE: Color = Color("75666a")
const MID: Color = Color("958776")
const LIGHT: Color = Color("b3a58a")
const HIGH: Color = Color("e4d8ba")
const BANK: Color = Color("55465a")
const BAYER: Array[float] = [0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0]
const PAD: int = 13
const BASE: float = 4.7 ## half width in the open
const APRON: float = 4.6 ## how much wider the ground is worn in front of a door
const APRON_LENGTH: float = 20.0
const SUNK: Vector2 = Vector2(-1.0, -1.0) ## the shaded rim lies on this side


## {texture: ImageTexture, origin: Vector2 (world px of the texture's top left)}; empty for a way of fewer than two points.
static func make(points: PackedVector2Array, seed_value: int, end_door: bool = false) -> Dictionary:
	var made: Dictionary = image(points, seed_value, end_door)
	if made.is_empty():
		return {}
	return {"texture": ImageTexture.create_from_image(made.image as Image), "origin": made.origin}


## The same as an Image (no renderer needed): {image: Image, origin: Vector2}.
static func image(points: PackedVector2Array, seed_value: int, end_door: bool = false) -> Dictionary:
	if points.size() < 2:
		return {}
	var low: Vector2 = points[0]
	var high: Vector2 = points[0]
	var length: float = 0.0
	for i: int in points.size():
		low = low.min(points[i])
		high = high.max(points[i])
		if i > 0:
			length += points[i - 1].distance_to(points[i])
	var origin: Vector2 = (low - Vector2(PAD, PAD)).floor()
	var size: Vector2i = Vector2i((high - low).ceil()) + Vector2i(PAD * 2 + 1, PAD * 2 + 1)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.06
	var wide: FastNoiseLite = FastNoiseLite.new()
	wide.seed = seed_value + 5
	wide.frequency = 0.02
	var tuft: FastNoiseLite = FastNoiseLite.new()
	tuft.seed = seed_value + 9
	tuft.frequency = 0.3
	var cover: PackedFloat32Array = PackedFloat32Array()
	cover.resize(size.x * size.y)
	var side: PackedFloat32Array = PackedFloat32Array()
	side.resize(size.x * size.y)
	var shade_dir: Vector2 = SUNK.normalized()
	var s: float = 0.0
	for seg: int in points.size() - 1:
		var a: Vector2 = points[seg] - origin
		var b: Vector2 = points[seg + 1] - origin
		var steps: int = maxi(ceili(a.distance_to(b)), 1)
		for i: int in steps + 1:
			var c: Vector2 = a.lerp(b, float(i) / float(steps))
			var here: float = s + a.distance_to(b) * float(i) / float(steps)
			var reach: float = BASE + 1.5 * wide.get_noise_1d(here) + 0.7 * noise.get_noise_1d(here * 0.8)
			reach += maxf(wide.get_noise_1d(here * 0.35 + 300.0) - 0.35, 0.0) * 6.0 ## a wide place where people stepped aside
			var door: float = clampf(1.0 - here / APRON_LENGTH, 0.0, 1.0)
			reach += APRON * door * door
			if end_door:
				var near_end: float = clampf(1.0 - (length - here) / APRON_LENGTH, 0.0, 1.0)
				reach += APRON * near_end * near_end
			reach = maxf(reach, 2.4)
			var span: int = ceili(reach) + 3
			for dy: int in range(-span, span + 1):
				for dx: int in range(-span, span + 1):
					var px: int = int(c.x) + dx
					var py: int = int(c.y) + dy
					if px < 0 or py < 0 or px >= size.x or py >= size.y:
						continue
					var offset: Vector2 = Vector2(float(px) + 0.5 - c.x, float(py) + 0.5 - c.y)
					var value: float = clampf((reach + 1.5 - offset.length()) / 3.5, 0.0, 1.0) ## solid in the middle, 3.5 px of thinning ground at the edge
					if value > cover[py * size.x + px]:
						cover[py * size.x + px] = value
						side[py * size.x + px] = offset.dot(shade_dir)
		s += a.distance_to(b)
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: int in size.y:
		for x: int in size.x:
			var v: float = cover[y * size.x + x]
			if v <= 0.0:
				continue
			var wx: int = int(origin.x) + x
			var wy: int = int(origin.y) + y
			var dither: float = BAYER[(wy & 3) * 4 + (wx & 3)] / 16.0
			var rough: float = float(hash(Vector2i(wx, wy) + Vector2i(seed_value, 3)) & 255) / 255.0
			var patch: float = noise.get_noise_2d(float(wx) * 0.8, float(wy) * 0.8)
			var wear: float = v * (0.92 + 0.18 * patch)
			if wear < 0.07 + 0.62 * (0.4 * dither + 0.6 * rough):
				continue ## the grass is back here
			if wear > 0.5 and tuft.get_noise_2d(float(wx), float(wy)) > 0.62:
				continue ## a tuft growing through the middle
			var n: float = noise.get_noise_2d(float(wx) * 1.7, float(wy) * 1.7)
			var color: Color = MID
			if wear < 0.38: ## the rim
				if side[y * size.x + x] > 0.0:
					color = BANK if rough < 0.5 else SHADE
				else:
					color = LIGHT if rough < 0.85 else HIGH
			elif wear < 0.7:
				color = LIGHT if n > -0.1 else (SHADE if n < -0.42 else MID)
			else:
				if n > 0.0:
					color = LIGHT
				elif n < -0.34:
					color = SHADE
				elif absf(n) < 0.04:
					color = SHADE ## the faint wear line of feet
				if hash(Vector2i(wx, wy) + Vector2i(seed_value, 0)) % 97 == 0:
					color = HIGH ## a pebble
			img.set_pixel(x, y, color)
	return {"image": img, "origin": origin}
