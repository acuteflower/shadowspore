class_name TownPathArt
extends RefCounted
## Renders a dynamic settlement footpath ("Trampelweg") matching Shadowspore's cluster-shaded world paths (tools/bake_ground.py):
## clean cel-shaded earth cushions (orphan-cleaned, no Bayer checkerboard noise), scalloped grass-blade fringes, sunken 3/4 NW/SE
## bank shading, worn door aprons, and small shaded twilight-slate pebbles. Deterministic across peers via `seed_value`.

const RAMP: Array[Color] = [
	Color("463852"),
	Color("5e4f62"),
	Color("7b6b6e"),
	Color("988978"),
	Color("b4a58b"),
	Color("cdc0a2"),
	Color("e3d7ba"),
]
const GRASS: Array[Color] = [
	Color("22483c"),
	Color("2f624e"),
	Color("3e7d56"),
	Color("55985f"),
	Color("7cb96d"),
	Color("a8dc8c"),
]
const PEBBLE: Array[Color] = [
	Color("2e2a52"),
	Color("47436f"),
	Color("665f94"),
	Color("8a83b8"),
]
const PAD: int = 13
const BASE: float = 4.8 ## half width in the open
const APRON: float = 4.6 ## extra worn width in front of a doorway
const APRON_LENGTH: float = 20.0
const SUNK: Vector2 = Vector2(-1.0, -1.0)


## {texture: ImageTexture, origin: Vector2 (world px of the texture's top left)}; empty for fewer than two points.
static func make(points: PackedVector2Array, seed_value: int, end_door: bool = false) -> Dictionary:
	var made: Dictionary = image(points, seed_value, end_door)
	if made.is_empty():
		return {}
	return {"texture": ImageTexture.create_from_image(made.image as Image), "origin": made.origin}


## Pure Image builder (safe without renderer): {image: Image, origin: Vector2}.
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
	var w: int = size.x
	var h: int = size.y
	var total_px: int = w * h

	var cushion_noise: FastNoiseLite = FastNoiseLite.new()
	cushion_noise.seed = seed_value
	cushion_noise.frequency = 0.095
	var edge_noise: FastNoiseLite = FastNoiseLite.new()
	edge_noise.seed = seed_value + 3
	edge_noise.frequency = 0.14
	var wide_noise: FastNoiseLite = FastNoiseLite.new()
	wide_noise.seed = seed_value + 5
	wide_noise.frequency = 0.022

	var norm_t: PackedFloat32Array = PackedFloat32Array()
	norm_t.resize(total_px)
	norm_t.fill(9.0)
	var side: PackedFloat32Array = PackedFloat32Array()
	side.resize(total_px)
	var door_pin: PackedByteArray = PackedByteArray()
	door_pin.resize(total_px)

	var shade_dir: Vector2 = SUNK.normalized()
	var s: float = 0.0
	for seg: int in points.size() - 1:
		var a: Vector2 = points[seg] - origin
		var b: Vector2 = points[seg + 1] - origin
		var seg_len: float = a.distance_to(b)
		var steps: int = maxi(ceili(seg_len), 1)
		for i: int in steps + 1:
			var u: float = float(i) / float(steps)
			var c: Vector2 = a.lerp(b, u)
			var here: float = s + seg_len * u
			var reach: float = BASE + 1.4 * wide_noise.get_noise_1d(here) + 0.6 * cushion_noise.get_noise_1d(here * 0.7)
			reach += maxf(wide_noise.get_noise_1d(here * 0.35 + 300.0) - 0.35, 0.0) * 5.2
			var door_w: float = clampf(1.0 - here / APRON_LENGTH, 0.0, 1.0)
			reach += APRON * door_w * door_w
			var end_w: float = 0.0
			if end_door:
				end_w = clampf(1.0 - (length - here) / APRON_LENGTH, 0.0, 1.0)
				reach += APRON * end_w * end_w
			reach = maxf(reach, 2.6)
			var span: int = ceili(reach * 1.35) + 2
			for dy: int in range(-span, span + 1):
				var py: int = int(c.y) + dy
				if py < 0 or py >= h:
					continue
				for dx: int in range(-span, span + 1):
					var px: int = int(c.x) + dx
					if px < 0 or px >= w:
						continue
					var offset: Vector2 = Vector2(float(px) + 0.5 - c.x, float(py) + 0.5 - c.y)
					var d: float = offset.length()
					var t_here: float = d / reach
					var idx: int = py * w + px
					if t_here < norm_t[idx]:
						norm_t[idx] = t_here
						side[idx] = (offset / maxf(d, 0.001)).dot(shade_dir)
					if (door_w > 0.75 or end_w > 0.75) and d < 2.2:
						door_pin[idx] = 1
		s += seg_len

	var keep: PackedByteArray = PackedByteArray()
	keep.resize(total_px)
	var tones: PackedByteArray = PackedByteArray()
	tones.resize(total_px)

	for y: int in h:
		var wy: float = origin.y + float(y)
		for x: int in w:
			var idx: int = y * w + x
			var t_raw: float = norm_t[idx]
			if t_raw > 1.35:
				continue
			var wx: float = origin.x + float(x)
			var wob: float = edge_noise.get_noise_2d(wx, wy) * 0.22 + cushion_noise.get_noise_2d(wx * 2.1, wy * 2.1) * 0.08
			var te: float = t_raw + wob
			if door_pin[idx] == 0 and te >= 1.0:
				continue
			keep[idx] = 1
			var cush: float = cushion_noise.get_noise_2d(wx, wy) * 1.55 + edge_noise.get_noise_2d(wx * 1.8, wy * 1.8) * 0.45
			var center_wear: float = 0.85 * maxf(0.0, 1.0 - (t_raw / 0.62) * (t_raw / 0.62))
			var bank: float = 0.0
			if te > 0.72:
				if side[idx] > 0.16:
					bank = -0.85
				elif side[idx] < -0.16:
					bank = 0.55
			var raw_tone: float = 3.35 + cush + center_wear - 0.75 * maxf(0.0, te - 0.58) / 0.42 + bank
			tones[idx] = clampi(roundi(raw_tone), 0, RAMP.size() - 1)

	# Orphan-pixel cleanup pass so earth tones form crisp Shadowspore cushions
	var cleaned: PackedByteArray = tones.duplicate()
	for y: int in range(1, h - 1):
		for x: int in range(1, w - 1):
			var idx: int = y * w + x
			if keep[idx] == 0:
				continue
			var v: int = tones[idx]
			var u_idx: int = (y - 1) * w + x
			var d_idx: int = (y + 1) * w + x
			var l_idx: int = y * w + (x - 1)
			var r_idx: int = y * w + (x + 1)
			var matches: int = 0
			var sum_nb: int = 0
			var cnt_nb: int = 0
			for n_idx: int in [u_idx, d_idx, l_idx, r_idx]:
				if keep[n_idx] == 1:
					cnt_nb += 1
					sum_nb += tones[n_idx]
					if tones[n_idx] == v:
						matches += 1
			if cnt_nb >= 3 and matches == 0:
				cleaned[idx] = clampi(roundi(float(sum_nb) / float(cnt_nb)), 0, RAMP.size() - 1)

	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		for x: int in w:
			var idx: int = y * w + x
			if keep[idx] == 0:
				continue
			img.set_pixel(x, y, RAMP[cleaned[idx]])

	# Shaded 2px slate pebbles & melted grass-blade tufts along the rim
	for y: int in range(2, h - 2):
		var wy_i: int = int(origin.y) + y
		for x: int in range(2, w - 2):
			var idx: int = y * w + x
			if keep[idx] == 0:
				continue
			var wx_i: int = int(origin.x) + x
			var hval: int = abs(hash(Vector2i(wx_i, wy_i) + Vector2i(seed_value * 13, 7)))
			var is_rim: bool = keep[(y - 1) * w + x] == 0 or keep[(y + 1) * w + x] == 0 or keep[y * w + x - 1] == 0 or keep[y * w + x + 1] == 0
			if is_rim and door_pin[idx] == 0:
				if (hval % 10) < 4:
					if side[idx] > 0.08:
						img.set_pixel(x, y, GRASS[3])
						if keep[(y + 1) * w + x] == 1:
							var under: Color = img.get_pixel(x, y + 1)
							img.set_pixel(x, y + 1, Color(under.r * 0.80, under.g * 0.78, minf(1.0, under.b * 0.88 + 0.02), 1.0))
					else:
						var bh: int = 2 + (hval % 2)
						for j: int in bh:
							if y - j >= 0:
								img.set_pixel(x, y - j, GRASS[mini(2 + j * 2, GRASS.size() - 1)])
			elif norm_t[idx] < 0.72 and (hval % 89) == 0:
				img.set_pixel(x, y, PEBBLE[3])
				if keep[y * w + x + 1] == 1:
					img.set_pixel(x + 1, y, PEBBLE[1])
				if keep[(y + 1) * w + x + 1] == 1:
					img.set_pixel(x + 1, y + 1, PEBBLE[0])
	return {"image": img, "origin": origin}
