class_name LightStepFx
extends Node2D
## Purified divine Light Step visual effect (Player.play_shadow_step when Player.light_step is active).
## Replaces Void tears with radiant gold-and-turquoise starlight beams, drifting star sparks along the dash vector,
## an arrival shock ring (46 px), and a brief unshaded NightLight flash that illuminates pitch-black night fights.
## Also provides helper beams for the Goddess's first-death Rescue Pillar and her Throne Blessing.

const GOLD_BRIGHT: Color = Color("fff0b0")
const GOLD: Color = Color("e6c468")
const TEAL_CORE: Color = Color("d0fff8")
const TEAL_BRIGHT: Color = Color("78f4e6")
const TEAL_DEEP: Color = Color("2a8c94")
const LIFE: float = 0.85

var from: Vector2
var to: Vector2
var dir: Vector2 = Vector2.RIGHT
var gone_at: float = 0.2
var back_at: float = 0.27

var _t: float = 0.0
var _motes: Array[Dictionary] = []
var _light: PointLight2D


func setup(from_feet: Vector2, to_feet: Vector2, step_dir: Vector2, gone: float, back: float) -> void:
	from = from_feet
	to = to_feet
	dir = step_dir.normalized() if step_dir != Vector2.ZERO else Vector2.RIGHT
	gone_at = gone
	back_at = back
	material = Unlit.material()
	z_index = 4

	var seed_val: int = int(absf(from.x * 17.0 + from.y * 11.0)) % 9973
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val
	var side: Vector2 = dir.orthogonal()
	var span: float = from.distance_to(to)

	# Trail star sparks along the light beam between from and to
	for i: int in 36:
		var u: float = rng.randf()
		var base_p: Vector2 = from.lerp(to, u) + side * rng.randf_range(-9.0, 9.0) + Vector2(0.0, -rng.randf_range(4.0, 38.0))
		_motes.append({
			"p": base_p,
			"v": dir * rng.randf_range(28.0, 82.0) + Vector2(rng.randf_range(-10.0, 10.0), -rng.randf_range(10.0, 34.0)),
			"t0": rng.randf_range(0.0, gone_at + 0.08),
			"life": rng.randf_range(0.22, 0.48),
			"gold": rng.randf() < 0.45,
			"cross": rng.randf() < 0.28,
		})

	# Radial arrival star burst motes
	for j: int in 24:
		var ang: float = (TAU * float(j) / 24.0) + rng.randf_range(-0.12, 0.12)
		var spd: float = rng.randf_range(36.0, 94.0)
		_motes.append({
			"p": to + Vector2(0.0, -14.0),
			"v": Vector2.from_angle(ang) * spd + Vector2(0.0, -8.0),
			"t0": back_at - 0.02,
			"life": rng.randf_range(0.20, 0.42),
			"gold": (j % 2) == 0,
			"cross": (j % 4) == 0,
		})

	if span > 1.0:
		_motes.append({
			"p": from + Vector2(0.0, -16.0),
			"v": dir * minf(span * 2.5, 220.0),
			"t0": 0.0,
			"life": 0.25,
			"gold": true,
			"cross": true,
		})

	_light = _make_light(self, to + Vector2(0.0, -16.0), TEAL_BRIGHT.lerp(GOLD_BRIGHT, 0.35), 140, 0.72, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	if _light != null:
		if _t < back_at:
			_light.position = from.lerp(to, clampf(_t / maxf(gone_at, 0.05), 0.0, 1.0)) + Vector2(0.0, -16.0)
			_light.energy = 0.85
		else:
			_light.position = to + Vector2(0.0, -16.0)
			_light.energy = maxf(0.0, 1.15 * (1.0 - (_t - back_at) / 0.48))
	queue_redraw()


func _draw() -> void:
	# 1. Departure starlight pillar & glow
	if _t < gone_at + 0.22:
		var dep_k: float = clampf(1.0 - _t / (gone_at + 0.22), 0.0, 1.0)
		_draw_pillar(from, dep_k * 0.85, 26.0, 88.0)

	# 2. Radiant ground ribbon along the step path
	if _t >= 0.03 and _t < back_at + 0.24:
		var line_k: float = sin(clampf((_t - 0.03) / (back_at + 0.21), 0.0, 1.0) * PI)
		draw_line(from + Vector2(0.0, -14.0), to + Vector2(0.0, -14.0), Color(TEAL_BRIGHT, line_k * 0.48), 5.0)
		draw_line(from + Vector2(0.0, -14.0), to + Vector2(0.0, -14.0), Color(GOLD_BRIGHT, line_k * 0.85), 2.0)

	# 3. Arrival burst pillar + light shockwave ring
	if _t >= back_at - 0.04:
		var arr_t: float = (_t - (back_at - 0.04)) / 0.46
		var arr_k: float = clampf(1.0 - arr_t, 0.0, 1.0)
		if arr_k > 0.0:
			_draw_pillar(to, arr_k, 34.0, 108.0)
			var ring_r: float = lerpf(8.0, 46.0, clampf(arr_t * 1.15, 0.0, 1.0))
			var ring_a: float = arr_k * 0.9
			draw_arc(to + Vector2(0.0, -6.0), ring_r, 0.0, TAU, 32, Color(TEAL_BRIGHT, ring_a * 0.7), 2.0)
			draw_arc(to + Vector2(0.0, -6.0), ring_r * 0.72, 0.0, TAU, 24, Color(GOLD_BRIGHT, ring_a), 1.0)

	# 4. Crisp pixel star motes
	for m: Dictionary in _motes:
		var age: float = _t - float(m["t0"])
		var life: float = float(m["life"])
		if age < 0.0 or age >= life:
			continue
		var k: float = 1.0 - age / life
		var p: Vector2 = ((m["p"] as Vector2) + (m["v"] as Vector2) * age).round()
		var col: Color = Color(GOLD_BRIGHT if bool(m["gold"]) else TEAL_BRIGHT, clampf(k * 1.2, 0.0, 1.0))
		draw_rect(Rect2(p, Vector2.ONE), col)
		if bool(m["cross"]) and k > 0.3:
			var arm: Color = Color(GOLD if bool(m["gold"]) else TEAL_DEEP, k * 0.8)
			draw_rect(Rect2(p + Vector2(-1.0, 0.0), Vector2.ONE), arm)
			draw_rect(Rect2(p + Vector2(1.0, 0.0), Vector2.ONE), arm)
			draw_rect(Rect2(p + Vector2(0.0, -1.0), Vector2.ONE), arm)
			draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), arm)


func _draw_pillar(feet: Vector2, strength: float, max_w: float, height: float) -> void:
	if strength <= 0.01:
		return
	var outer_w: float = max_w * (0.45 + 0.55 * strength)
	var inner_w: float = outer_w * 0.42
	draw_rect(Rect2(Vector2(feet.x - outer_w * 0.5, feet.y - height).round(), Vector2(outer_w, height).round()), Color(TEAL_BRIGHT, strength * 0.24))
	draw_rect(Rect2(Vector2(feet.x - inner_w * 0.5, feet.y - height).round(), Vector2(inner_w, height).round()), Color(TEAL_CORE, strength * 0.52))
	draw_rect(Rect2(Vector2(feet.x - 1.5, feet.y - height).round(), Vector2(3.0, height).round()), Color(GOLD_BRIGHT, strength * 0.88))


## Dramatic radiant blessing burst around `player` when Caelia grants LICHTSCHRITT.
static func spawn_blessing(target: Node2D) -> void:
	if target == null or target.get_tree() == null:
		return
	var host: Node = target.get_tree().current_scene
	if host == null:
		return
	var fx: LightStepFx = LightStepFx.new()
	fx.setup(target.global_position, target.global_position, Vector2.UP, 0.25, 0.28)
	host.add_child(fx)


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
		draw_rect(Rect2(Vector2(-w_outer * 0.5, -h).round(), Vector2(w_outer, h).round()), Color(TEAL_BRIGHT, k * 0.28))
		draw_rect(Rect2(Vector2(-w_mid * 0.5, -h).round(), Vector2(w_mid, h).round()), Color(TEAL_CORE, k * 0.55))
		draw_rect(Rect2(Vector2(-3.0, -h).round(), Vector2(6.0, h).round()), Color(GOLD_BRIGHT, k * 0.92))
		for i: int in 14:
			var rise: float = fposmod(_t * 140.0 + float(i) * 31.0, 260.0)
			var sx: float = sin(float(i) * 2.1 + _t * 4.0) * (w_outer * 0.36)
			draw_rect(Rect2(Vector2(sx, -rise).round(), Vector2(2.0, 2.0)), Color(GOLD_BRIGHT if i % 2 == 0 else TEAL_CORE, k))
