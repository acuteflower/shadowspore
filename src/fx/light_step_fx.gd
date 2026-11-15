class_name LightStepFx
extends Node2D
## Purified Light Step (`Player.play_shadow_step` when `Player.light_step` is active), built in the exact scale, pacing, and
## silhouette language of `ShadowStepFx`, translated into celestial starlight: starlight flecks torn off Ellie's leading edge
## into a glowing star-tear (`void_rift.gdshader` with `light_mode = true`) that crumbles shut with a broken turquoise-gold ring
## and a breath of starlight; at the arrival a second tear opens, shards stream back into her, and it crumbles away.
## Her body itself dissolves and condenses via `hit_flash.gdshader` (`step_light = true`).

const DEEP: Color = Color("164b56")
const RIM: Color = Color("3cc0c6")
const RIM_LIGHT: Color = Color("78f4e6")
const TEAL_CORE: Color = Color("d0fff8")
const GOLD: Color = Color("e6c468")
const GOLD_BRIGHT: Color = Color("fff0b0")
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
var _rifts: Array[Dictionary] = [] ## {mat, opens, closes}: the two starlight tears
var _light: PointLight2D


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
	for i: int in 46: ## torn off her body as the front sweeps from leading edge to back
		var k: float = rng.randf()
		var lateral: float = rng.randf_range(-1.0, 1.0)
		var height: float = rng.randf_range(4.0, 46.0)
		var start: Vector2 = from + dir * lerpf(7.0, -7.0, k) + side * lateral * 5.0 + Vector2(0.0, -height)
		_shards.append({
			"out": true,
			"t0": lerpf(0.0, gone_at, k),
			"p": start,
			"v": dir * rng.randf_range(110.0, 220.0) + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-30.0, 6.0)),
			"size": 2 if rng.randf() < 0.3 else 1,
			"spark": rng.randf() < 0.12,
			"gold": rng.randf() < 0.42,
			"life": rng.randf_range(0.14, 0.26),
		})
	for i: int in 40: ## streaming out of the arrival tear into her body
		var height: float = rng.randf_range(4.0, 46.0)
		var target: Vector2 = to + side * rng.randf_range(-5.0, 5.0) + Vector2(0.0, -height)
		_shards.append({
			"out": false,
			"t0": back_at - rng.randf_range(0.0, 0.03),
			"p": target,
			"from": _rift(to, -1.0) + Vector2(rng.randf_range(-2.0, 2.0), -rng.randf_range(4.0, 38.0)),
			"size": 2 if rng.randf() < 0.3 else 1,
			"spark": rng.randf() < 0.12,
			"gold": rng.randf() < 0.42,
			"life": rng.randf_range(0.07, 0.12),
		})
	material = Unlit.material()
	z_index = 2
	_add_rift(_rift(from, 1.0), 0.0, gone_at + 0.05, rng)
	_add_rift(_rift(to, -1.0), back_at - 0.05, back_at + 0.1, rng)
	_light = _make_light(self, from + Vector2(0.0, -16.0), RIM_LIGHT.lerp(GOLD_BRIGHT, 0.35), 96, 0.72, 0.52)
	queue_redraw()


## One tear: a quad running `void_rift.gdshader` in celestial light mode, centered at her chest height.
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
	mat.set_shader_parameter("light_mode", true)
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
	if _light != null:
		if _t < back_at:
			_light.position = from.lerp(to, clampf(_t / maxf(gone_at, 0.05), 0.0, 1.0)) + Vector2(0.0, -16.0)
			_light.energy = 0.55
		else:
			_light.position = to + Vector2(0.0, -16.0)
			_light.energy = maxf(0.0, 0.65 * (1.0 - (_t - back_at) / 0.42))
	queue_redraw()


## Where the tear stands: just ahead of her (`sign` 1, leaving) or just behind her (-1, arriving), in the direction of the step.
func _rift(feet: Vector2, sign_val: float) -> Vector2:
	return feet + dir * 11.0 * sign_val


func _draw() -> void:
	var tick: int = int(_t * 30.0) ## the glitch changes thirty times a second, matching every peer
	_draw_pool(from, clampf((_t - 0.02) / 0.08, 0.0, 1.0) * (1.0 - clampf((_t - 0.45) / 0.45, 0.0, 1.0)))
	_draw_pool(to, clampf((_t - back_at) / 0.08, 0.0, 1.0) * (1.0 - clampf((_t - back_at - 0.2) / 0.4, 0.0, 1.0)))
	_draw_ring(from + dir * 8.0, gone_at + 0.06)
	_draw_ring(to - dir * 8.0, back_at + 0.1)
	for shard: Dictionary in _shards:
		_draw_shard(shard, tick)
	_draw_afterglow(tick)


## A luminous starlight pool on the ground with four short golden-teal rays.
func _draw_pool(feet: Vector2, k: float) -> void:
	if k <= 0.01:
		return
	for y: int in range(-3, 4):
		var half: int = int(round(9.0 * k * sqrt(maxf(0.0, 1.0 - float(y * y) / 12.0))))
		for x: int in range(-half, half + 1):
			if (x + y + _seed) % 3 == 0 and absf(float(x)) > half * 0.6:
				continue ## dithered rim
			var r2: float = (float(x) * float(x)) / maxf(float(half * half), 1.0) + float(y * y) / 6.0
			var col: Color = GOLD_BRIGHT if (r2 < 0.22 and (x + y + _seed) % 2 == 0) else (RIM_LIGHT if r2 < 0.45 else (RIM if r2 < 0.78 else DEEP))
			var a: float = (0.50 if r2 < 0.45 else 0.40) * k
			draw_rect(Rect2(feet + Vector2(x, y), Vector2.ONE), Color(col, a))
	for i: int in 4:
		var a: float = float(i) * TAU / 4.0 + float(_seed) * 0.3
		var length: float = (5.0 + 3.0 * sin(_t * 9.0 + i)) * k
		var end: Vector2 = feet + Vector2(cos(a) * (9.0 + length), sin(a) * (3.0 + length * 0.35))
		draw_line(feet + Vector2(cos(a) * 8.0, sin(a) * 2.6), end.round(), Color(GOLD if i % 2 == 0 else RIM_LIGHT, 0.55 * k), 1.0)


## The tear crumbling shut pushes a broken ring of turquoise & gold starlight across the ground (same footprint as ShadowStepFx).
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
			continue
		var r: float = rx * (1.0 + 0.16 * sin(a * 3.0 + float(_seed)) + 0.08 * sin(a * 7.0 + float(_seed) * 0.3))
		var point: Vector2 = (center + Vector2(cos(a) * r, sin(a) * r * 0.36)).round()
		var lit: bool = noise > 0.88
		draw_rect(Rect2(point, Vector2.ONE), Color(GOLD_BRIGHT if lit else RIM_LIGHT, (0.85 if lit else 0.55) * (1.0 - k)))
		if noise > 0.6 and noise < 0.75:
			draw_rect(Rect2(point + Vector2(0.0, 1.0), Vector2.ONE), Color(DEEP, 0.55 * (1.0 - k)))


## A torn-off starlight pixel: leaving, it flies along the step into the tear; arriving, it streams out into her body.
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
		point.x += 1.0 if (tick % 2) == 0 else -1.0 ## glitch jitter matching ShadowStepFx
	var size: float = float(shard["size"])
	var fade: float = 1.0 - k if bool(shard["out"]) else minf(1.0, k * 3.0) * (1.0 - k * 0.6)
	var is_gold: bool = bool(shard["gold"])
	if bool(shard["spark"]):
		var spark_col: Color = GOLD_BRIGHT if is_gold else TEAL_CORE
		draw_rect(Rect2(point, Vector2.ONE), Color(spark_col, fade))
		VoidGlow.halo(self, point, GOLD if is_gold else RIM_LIGHT, 0.35 * fade, 0.3)
		return
	var smear: Vector2 = (-(shard["v"] as Vector2).normalized() if bool(shard["out"]) else ((shard["p"] as Vector2) - (shard["from"] as Vector2)).normalized() * -1.0).round()
	draw_rect(Rect2(point + smear, Vector2.ONE), Color(GOLD if is_gold else RIM, 0.45 * fade))
	draw_rect(Rect2(point, Vector2(size, size)), Color(TEAL_CORE if not is_gold else GOLD_BRIGHT, fade))
	if size > 1.0 or (tick + int(point.x)) % 3 == 0:
		draw_rect(Rect2(point + Vector2(0.0, -1.0), Vector2(size, 1.0)), Color(GOLD_BRIGHT if is_gold else RIM_LIGHT, 0.65 * fade))


## Where she was: faint starlight motes drift up after the departure tear closes.
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
		draw_rect(Rect2(p, Vector2.ONE), Color(GOLD_BRIGHT if i % 3 == 0 else RIM_LIGHT, 0.58 * (1.0 - k)))


## Compact radiant blessing burst around `player` when Caelia grants LICHTSCHRITT.
static func spawn_blessing(target: Node2D) -> void:
	if target == null or target.get_tree() == null:
		return
	var host: Node = target.get_tree().current_scene
	if host == null:
		return
	var burst: _BlessingBurst = _BlessingBurst.new()
	burst.position = target.global_position
	host.add_child(burst)


## Tall celestial rescue beam spawned in screen/world space before Ellie is lifted into the Star Hall.
static func spawn_rescue_pillar(parent: Node, at: Vector2) -> Node2D:
	var pillar: _RescueBeam = _RescueBeam.new()
	pillar.position = at
	parent.add_child(pillar)
	return pillar


static func _make_light(parent: Node, pos: Vector2, col: Color, width: int, squash: float, energy: float) -> PointLight2D:
	var light: PointLight2D = PointLight2D.new()
	light.position = pos
	light.color = col
	light.energy = energy
	LightTexture.apply(light, width, squash, int(absf(pos.x + pos.y)) % 3)
	parent.add_child(light)
	return light


class _BlessingBurst:
	extends Node2D
	const LIFE_TIME: float = 0.72
	var _t: float = 0.0
	var _light: PointLight2D

	func _ready() -> void:
		material = Unlit.material()
		z_index = 4
		_light = LightStepFx._make_light(self, Vector2(0.0, -18.0), Color("fff0b0"), 110, 0.75, 0.85)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE_TIME:
			queue_free()
			return
		if _light != null:
			_light.energy = 0.9 * sin(clampf(_t / LIFE_TIME, 0.0, 1.0) * PI)
		queue_redraw()

	func _draw() -> void:
		var k: float = clampf(_t / LIFE_TIME, 0.0, 1.0)
		var alpha: float = sin(k * PI)
		var rx: float = lerpf(6.0, 22.0, 1.0 - pow(1.0 - k, 2.0))
		for i: int in 24:
			var a: float = float(i) * TAU / 24.0 + k * 1.4
			var p: Vector2 = Vector2(cos(a) * rx, sin(a) * rx * 0.38).round()
			draw_rect(Rect2(p, Vector2.ONE), Color(GOLD_BRIGHT if i % 2 == 0 else RIM_LIGHT, alpha * 0.85))
		for m: int in 14:
			var ang: float = float(m) * TAU / 14.0
			var rise: float = lerpf(4.0, 42.0, k) + float((m * 11) % 8)
			var sway: float = cos(ang + k * 2.0) * lerpf(6.0, 13.0, sin(k * PI))
			var mp: Vector2 = Vector2(sway, -rise).round()
			draw_rect(Rect2(mp, Vector2.ONE), Color(GOLD_BRIGHT if m % 3 == 0 else TEAL_CORE, alpha))


class _RescueBeam:
	extends Node2D
	var _t: float = 0.0
	var _light: PointLight2D

	func _ready() -> void:
		material = Unlit.material()
		z_index = 20
		_light = LightStepFx._make_light(self, Vector2(0.0, -24.0), Color("fff0b0"), 210, 0.78, 1.35)

	func _process(delta: float) -> void:
		_t += delta
		if _t >= 1.65:
			queue_free()
			return
		if _light != null:
			_light.energy = 1.45 * sin(clampf(_t / 1.65, 0.0, 1.0) * PI)
		queue_redraw()

	func _draw() -> void:
		var k: float = sin(clampf(_t / 1.65, 0.0, 1.0) * PI)
		var h: float = 420.0
		var w_outer: float = 44.0 * (0.4 + 0.6 * k)
		var w_mid: float = 20.0 * (0.4 + 0.6 * k)
		draw_rect(Rect2(Vector2(-w_outer * 0.5, -h).round(), Vector2(w_outer, h).round()), Color(RIM_LIGHT, k * 0.28))
		draw_rect(Rect2(Vector2(-w_mid * 0.5, -h).round(), Vector2(w_mid, h).round()), Color(TEAL_CORE, k * 0.55))
		draw_rect(Rect2(Vector2(-3.0, -h).round(), Vector2(6.0, h).round()), Color(GOLD_BRIGHT, k * 0.92))
		for i: int in 14:
			var rise: float = fposmod(_t * 140.0 + float(i) * 31.0, 260.0)
			var sx: float = sin(float(i) * 2.1 + _t * 4.0) * (w_outer * 0.36)
			draw_rect(Rect2(Vector2(sx, -rise).round(), Vector2(2.0, 2.0)), Color(GOLD_BRIGHT if i % 2 == 0 else TEAL_CORE, k))
