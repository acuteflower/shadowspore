class_name ShadowStepFx
extends Node2D
## The void around Ellie's shadow step (Player.play_shadow_step), on every peer, unlit: pixel shards torn off her leading edge and sucked
## into a tear in the air (`void_rift.gdshader`, the void spider's language: a ragged wound of ink with pulsing veins, glitching rows, warped
## ground at its lips, its own random shape and lean every step) that crumbles shut with a broken ring, a breath of violet where she was;
## at the arrival a second tear rips open, the shards stream out into her and it crumbles away. Her body itself dissolves in `hit_flash.gdshader` (`step_*`).
## Everything follows the step's clock, so every peer draws the same; the node frees itself.

const BLACK: Color = Color("06030c")
const RIM: Color = Color("7d57e0") ## VoidGlow.VEIN: the spider's veins
const RIM_LIGHT: Color = Color("a98af0") ## VoidGlow.VEIN_LIGHT
const SPARK: Color = Color("ff3ddb")
const RIFT_SHADER: Shader = preload("res://assets/shaders/void_rift.gdshader")
const RIFT_SIZE: Vector2i = Vector2i(44, 76)
const LIFE: float = 0.95

var from: Vector2 ## her feet where she vanishes
var to: Vector2 ## her feet where she comes back
var dir: Vector2 = Vector2.RIGHT
var gone_at: float = 0.2 ## when she is fully dissolved
var back_at: float = 0.27 ## when she starts to condense again
var _t: float = 0.0
var _shards: Array[Dictionary] = []
var _seed: int = 0
var _rifts: Array[Dictionary] = [] ## {mat, opens, closes}: the two tears


func setup(from_feet: Vector2, to_feet: Vector2, step_dir: Vector2, gone: float, back: float) -> void:
	from = from_feet
	to = to_feet
	dir = step_dir.normalized() if step_dir != Vector2.ZERO else Vector2.RIGHT
	gone_at = gone
	back_at = back
	_seed = int(absf(from.x * 13.0 + from.y * 7.0)) % 9973
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed
	var side: Vector2 = dir.orthogonal()
	for i: int in 46: ## torn off her body as the front runs from her leading edge to her back
		var k: float = rng.randf()
		var lateral: float = rng.randf_range(-1.0, 1.0)
		var height: float = rng.randf_range(4.0, 46.0)
		var start: Vector2 = from + dir * lerpf(7.0, -7.0, k) + side * lateral * 5.0 + Vector2(0.0, -height)
		_shards.append({"out": true, "t0": lerpf(0.0, gone_at, k), "p": start, "v": dir * rng.randf_range(110.0, 220.0) + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-30.0, 6.0)),
			"size": 2 if rng.randf() < 0.3 else 1, "spark": rng.randf() < 0.08, "life": rng.randf_range(0.14, 0.26)})
	for i: int in 40: ## streaming out of the arrival rift into her, from the core outwards
		var height: float = rng.randf_range(4.0, 46.0)
		var target: Vector2 = to + side * rng.randf_range(-5.0, 5.0) + Vector2(0.0, -height)
		_shards.append({"out": false, "t0": back_at - rng.randf_range(0.0, 0.03), "p": target, "from": _rift(to, -1.0) + Vector2(rng.randf_range(-2.0, 2.0), -rng.randf_range(4.0, 38.0)),
			"size": 2 if rng.randf() < 0.3 else 1, "spark": rng.randf() < 0.08, "life": rng.randf_range(0.07, 0.12)})
	material = Unlit.material()
	z_index = 2
	_add_rift(_rift(from, 1.0), 0.0, gone_at + 0.05, rng)
	_add_rift(_rift(to, -1.0), back_at - 0.05, back_at + 0.1, rng)
	queue_redraw()


## One tear: a quad running `void_rift.gdshader`, its middle at her chest height, its own seed and lean.
func _add_rift(base: Vector2, opens: float, closes: float, rng: RandomNumberGenerator) -> void:
	var image: Image = Image.create(RIFT_SIZE.x, RIFT_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var quad: Sprite2D = Sprite2D.new()
	quad.texture = ImageTexture.create_from_image(image)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = RIFT_SHADER
	mat.set_shader_parameter("seed", rng.randf() * 1000.0)
	mat.set_shader_parameter("lean", rng.randf_range(-0.18, 0.18))
	mat.set_shader_parameter("open_amt", 0.0)
	quad.material = mat
	quad.position = (base + Vector2(0.0, -25.0)).round()
	add_child(quad)
	_rifts.append({"mat": mat, "opens": opens, "closes": closes})


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	for rift: Dictionary in _rifts:
		var mat: ShaderMaterial = rift["mat"] as ShaderMaterial
		var opens: float = float(rift["opens"])
		var open_k: float = clampf((_t - opens) / 0.07, 0.0, 1.0)
		mat.set_shader_parameter("age", maxf(_t - opens, 0.0))
		mat.set_shader_parameter("open_amt", 1.0 - pow(1.0 - open_k, 2.0) if _t >= opens else 0.0)
		mat.set_shader_parameter("close_amt", clampf((_t - float(rift["closes"])) / 0.13, 0.0, 1.0))
	queue_redraw()


## Where the rift stands: just ahead of her (`sign` 1, leaving) or just behind her (-1, arriving), in the direction of the step.
func _rift(feet: Vector2, sign: float) -> Vector2:
	return feet + dir * 11.0 * sign


func _draw() -> void:
	var tick: int = int(_t * 30.0) ## the glitch changes thirty times a second, the same on every peer
	_draw_pool(from, clampf((_t - 0.02) / 0.08, 0.0, 1.0) * (1.0 - clampf((_t - 0.45) / 0.45, 0.0, 1.0)))
	_draw_pool(to, clampf((_t - back_at) / 0.08, 0.0, 1.0) * (1.0 - clampf((_t - back_at - 0.2) / 0.4, 0.0, 1.0)))
	_draw_ring(from + dir * 8.0, gone_at + 0.06)
	_draw_ring(to - dir * 8.0, back_at + 0.1)
	for shard: Dictionary in _shards:
		_draw_shard(shard, tick)
	_draw_afterglow(tick)


## A dark, breathing pool on the ground with a few short violet tendrils (the void touching the ground for a moment).
func _draw_pool(feet: Vector2, k: float) -> void:
	if k <= 0.01:
		return
	for y: int in range(-3, 4):
		var half: int = int(round(9.0 * k * sqrt(maxf(0.0, 1.0 - float(y * y) / 12.0))))
		for x: int in range(-half, half + 1):
			if (x + y + _seed) % 3 == 0 and absf(float(x)) > half * 0.6:
				continue ## dithered rim
			draw_rect(Rect2(feet + Vector2(x, y), Vector2.ONE), Color(BLACK, 0.55 * k))
	for i: int in 4:
		var a: float = float(i) * TAU / 4.0 + float(_seed) * 0.3
		var length: float = (5.0 + 3.0 * sin(_t * 9.0 + i)) * k
		var end: Vector2 = feet + Vector2(cos(a) * (9.0 + length), sin(a) * (3.0 + length * 0.35))
		draw_line(feet + Vector2(cos(a) * 8.0, sin(a) * 2.6), end.round(), Color(RIM, 0.5 * k), 1.0)


## The tear crumbling shut pushes a ring of void over the ground: ragged, its radius wanders, it breaks apart in random gaps as it spreads.
func _draw_ring(center: Vector2, at: float) -> void:
	var k: float = (_t - at) / 0.24
	if k < 0.0 or k > 1.0:
		return
	var rx: float = lerpf(4.0, 20.0, 1.0 - pow(1.0 - k, 2.0))
	var steps: int = 44
	for i: int in steps:
		var a: float = float(i) * TAU / float(steps)
		var noise: float = fposmod(sin(float(i) * 12.9898 + float(_seed) * 0.731) * 43758.5453, 1.0)
		if noise < 0.25 + 0.55 * k:
			continue ## it falls apart as it spreads
		var r: float = rx * (1.0 + 0.16 * sin(a * 3.0 + float(_seed)) + 0.08 * sin(a * 7.0 + float(_seed) * 0.3))
		var point: Vector2 = (center + Vector2(cos(a) * r, sin(a) * r * 0.36)).round()
		var lit: bool = noise > 0.93
		draw_rect(Rect2(point, Vector2.ONE), Color(RIM_LIGHT if lit else RIM, (0.85 if lit else 0.55) * (1.0 - k)))
		if noise > 0.6 and noise < 0.75:
			draw_rect(Rect2(point + Vector2(0.0, 1.0), Vector2.ONE), Color(BLACK, 0.6 * (1.0 - k)))


## A torn-off pixel: leaving, it flies on along the step and is sucked into the rift; arriving, it streams from the rift into her body.
func _draw_shard(shard: Dictionary, tick: int) -> void:
	var t0: float = float(shard["t0"])
	var life: float = float(shard["life"])
	var age: float = _t - t0
	if age < 0.0 or age > life:
		return
	var k: float = age / life
	var point: Vector2
	if bool(shard["out"]):
		var p: Vector2 = shard["p"] as Vector2
		var flown: Vector2 = p + (shard["v"] as Vector2) * age
		var rift: Vector2 = _rift(from, 1.0) + Vector2(0.0, p.y - from.y) * 0.6
		point = flown.lerp(rift, k * k)
	else:
		point = (shard["from"] as Vector2).lerp(shard["p"] as Vector2, 1.0 - pow(1.0 - k, 2.0))
	point = point.round()
	if (tick + int(point.y)) % 7 == 0:
		point.x += 1.0 if (tick % 2) == 0 else -1.0 ## glitch jitter
	var size: float = float(shard["size"])
	var fade: float = 1.0 - k if bool(shard["out"]) else minf(1.0, k * 3.0) * (1.0 - k * 0.6)
	if bool(shard["spark"]):
		draw_rect(Rect2(point, Vector2.ONE), Color(SPARK, fade))
		VoidGlow.halo(self, point, SPARK, 0.35 * fade, 0.3)
		return
	# a fleck of black void flesh with a cold edge on one side and a short smear behind it (the way it flies)
	var smear: Vector2 = (-(shard["v"] as Vector2).normalized() if bool(shard["out"]) else ((shard["p"] as Vector2) - (shard["from"] as Vector2)).normalized() * -1.0).round()
	draw_rect(Rect2(point + smear, Vector2.ONE), Color(RIM, 0.45 * fade))
	draw_rect(Rect2(point, Vector2(size, size)), Color(BLACK, fade))
	if size > 1.0 or (tick + int(point.x)) % 3 == 0:
		draw_rect(Rect2(point + Vector2(0.0, -1.0), Vector2(size, 1.0)), Color(RIM_LIGHT if size > 1.0 else RIM, 0.6 * fade))


## Where she was: a few faint violet motes hang in the air and drift up a little after the rift has closed.
func _draw_afterglow(tick: int) -> void:
	var k: float = clampf((_t - gone_at) / 0.6, 0.0, 1.0)
	if k <= 0.0 or k >= 1.0:
		return
	for i: int in 9:
		var h: float = float((i * 37 + _seed) % 44) + 4.0
		var x: float = float((i * 53 + _seed) % 11) - 5.0
		var p: Vector2 = (from + Vector2(x, -h - k * 8.0)).round()
		if (tick + i) % 4 == 0:
			continue
		draw_rect(Rect2(p, Vector2.ONE), Color(RIM if i % 4 != 0 else RIM_LIGHT, 0.55 * (1.0 - k)))
