class_name WeatherField
extends RefCounted
## The cloud field (docs/wetter_konzept.md section 5): ONE tileable noise texture, made once from the world seed, read by the GPU shaders
## (`g_cloud_tex`, see daylight.gdshaderinc) AND by the CPU (`density`/`thick`/`rain_at`), so the two can never drift apart. Channel R is the big
## masses (one tile = TILE_A px), G the fine detail (TILE_B px), B an independent field for local variation. Every channel is rank-normalised, so its
## values are spread evenly over 0..1 and a coverage of 0.4 really covers 40 % of the sky (`threshold`).
## The GLSL twin of `density` / `thick` is in assets/shaders/daylight.gdshaderinc: change both together.

const SIZE: int = 128
const TILE_A: float = 2048.0
const TILE_B: float = 512.0
const DETAIL_OFFSET: Vector2 = Vector2(0.37, 0.61)
const WIDTH: float = 0.17 ## density range over which a cloud edge fades in

var image: Image
var texture: ImageTexture
var ready_now: bool = false
var quantiles: PackedFloat32Array = PackedFloat32Array() ## 257 sorted samples of the density: the inverse of the coverage
## What the weather is doing right now (set by WeatherManager each frame, read by the GLSL globals and the CPU twin).
var drift: Vector2 = Vector2.ZERO
var thresh: float = 2.0 ## density above which there is cloud (2 = none)
var bonus: float = 0.0 ## an overcast sky is thick even at its thin places
var rain_regime: float = 0.0


## Starts the build on a worker; `on_ready` runs on the main thread when the texture exists.
func build(world_seed: int, on_ready: Callable) -> void:
	var jobs: Node = Engine.get_main_loop().root.get_node_or_null("Jobs")
	if jobs == null:
		_finish(_generate(world_seed), on_ready)
		return
	jobs.call("run", Callable(self, "_generate").bind(world_seed), Callable(self, "_finish").bind(on_ready), 2)


## Worker: three rank-normalised noise channels as raw RGB8 bytes.
func _generate(world_seed: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(SIZE * SIZE * 3)
	var channels: Array[PackedFloat32Array] = [
		_fbm([6, 12, 24, 48], [1.0, 0.55, 0.30, 0.16], world_seed * 31 + 11),
		_fbm([4, 8, 16, 32], [1.0, 0.55, 0.30, 0.16], world_seed * 31 + 12),
		_fbm([5, 10, 20], [1.0, 0.5, 0.25], world_seed * 31 + 13),
	]
	for c: int in 3:
		var values: PackedFloat32Array = channels[c]
		var sorted: PackedFloat32Array = values.duplicate()
		sorted.sort()
		for i: int in SIZE * SIZE:
			var rank: int = sorted.bsearch(values[i])
			out[i * 3 + c] = clampi(roundi(255.0 * float(rank) / float(SIZE * SIZE - 1)), 0, 255)
	return out


func _fbm(sizes: Array, amps: Array, seed_value: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var field: PackedFloat32Array = PackedFloat32Array()
	field.resize(SIZE * SIZE)
	for o: int in sizes.size():
		var cells: int = int(sizes[o])
		var lattice: PackedFloat32Array = PackedFloat32Array()
		lattice.resize(cells * cells)
		for i: int in cells * cells:
			lattice[i] = rng.randf()
		var amp: float = float(amps[o])
		for y: int in SIZE:
			var fy: float = float(y) * float(cells) / float(SIZE)
			var y0: int = int(fy)
			var ty: float = fy - float(y0)
			ty = ty * ty * (3.0 - 2.0 * ty)
			var row0: int = (y0 % cells) * cells
			var row1: int = ((y0 + 1) % cells) * cells
			for x: int in SIZE:
				var fx: float = float(x) * float(cells) / float(SIZE)
				var x0: int = int(fx)
				var tx: float = fx - float(x0)
				tx = tx * tx * (3.0 - 2.0 * tx)
				var x1: int = (x0 + 1) % cells
				x0 = x0 % cells
				var a: float = lerpf(lattice[row0 + x0], lattice[row0 + x1], tx)
				var b: float = lerpf(lattice[row1 + x0], lattice[row1 + x1], tx)
				field[y * SIZE + x] += amp * lerpf(a, b, ty)
	return field


func _finish(bytes: PackedByteArray, on_ready: Callable) -> void:
	image = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, bytes)
	texture = ImageTexture.create_from_image(image)
	_build_quantiles()
	ready_now = true
	if on_ready.is_valid():
		on_ready.call()


func _build_quantiles() -> void:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var n: int = 72
	for y: int in n:
		for x: int in n:
			samples.append(density(Vector2(float(x), float(y)) * (TILE_A / float(n)) + Vector2(11.0, 7.0), Vector2.ZERO))
	samples.sort()
	quantiles.resize(257)
	for i: int in 257:
		quantiles[i] = samples[mini(samples.size() - 1, int(float(i) / 256.0 * float(samples.size() - 1)))]


## Bilinear, wrapping, texel-centre exact like the GPU's `filter_linear, repeat_enable`. Returns the channel `c` (0 R, 1 G, 2 B) in 0..1.
func sample(uv: Vector2, c: int) -> float:
	if image == null:
		return 0.0
	var fx: float = uv.x * float(SIZE) - 0.5
	var fy: float = uv.y * float(SIZE) - 0.5
	var x0: int = floori(fx)
	var y0: int = floori(fy)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var xa: int = posmod(x0, SIZE)
	var xb: int = posmod(x0 + 1, SIZE)
	var ya: int = posmod(y0, SIZE)
	var yb: int = posmod(y0 + 1, SIZE)
	var a: float = lerpf(_px(xa, ya, c), _px(xb, ya, c), tx)
	var b: float = lerpf(_px(xa, yb, c), _px(xb, yb, c), tx)
	return lerpf(a, b, ty)


func _px(x: int, y: int, c: int) -> float:
	var color: Color = image.get_pixel(x, y)
	return color.r if c == 0 else (color.g if c == 1 else color.b)


## The cloud density at a world position (0..1), `drift` already taken off.
func density(p: Vector2, with_drift: Vector2 = Vector2(INF, INF)) -> float:
	var q: Vector2 = p - (drift if with_drift.x == INF else with_drift)
	return sample(q / TILE_A, 0) * 0.76 + sample(q / TILE_B + DETAIL_OFFSET, 1) * 0.24


## Density above which the sky is clouded for a coverage 0..1 (the inverse of the density's distribution).
func threshold(cover: float) -> float:
	if quantiles.is_empty() or cover <= 0.001:
		return 2.0 ## no cloud at all
	var f: float = clampf(1.0 - cover, 0.0, 1.0) * 256.0
	var i: int = mini(255, int(f))
	return lerpf(quantiles[i], quantiles[i + 1], f - float(i))


## How thick the cloud is over a world position: 0 open sky .. 1 solid.
func thick(p: Vector2) -> float:
	return clampf((density(p) - thresh) / WIDTH + bonus, 0.0, 1.0)


## The rain falling on the ground at a world position, 0..1: only under cloud, heaviest in its cores (a rain cell passes over you).
## Never rains in the arid Sonnenquarz-Öde (`BiomeBlend.arid_at`).
func rain_at(p: Vector2) -> float:
	if rain_regime <= 0.001:
		return 0.0
	var dry: float = 1.0 - smoothstep(0.18, 0.45, BiomeBlend.arid_at(p))
	if dry <= 0.001:
		return 0.0
	var th: float = thick(p)
	var core: float = smoothstep(0.1, 0.75, th)
	return clampf(rain_regime * dry * (0.45 + 0.75 * core) * smoothstep(0.02, 0.25, th), 0.0, 1.0)


## The light that is left under the cloud above a world position (the shadow): 1 in the sun, `shadow` under the thickest cloud.
func light_at(p: Vector2, shadow: float) -> float:
	return lerpf(1.0, shadow, smoothstep(0.04, 0.5, thick(p)))
