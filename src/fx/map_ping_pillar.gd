class_name MapPingPillar
extends Node2D
## Transient world beacon spawned by `ZoneCoop` when a player middle-clicks the Atlas
## in the same zone (`docs/v2_zonenwelt_atlas_konzept.md` 6.5): narrow turquoise-gold
## `Unlit` light shaft with isometric ground rings, rising sparks, soft night glow, and
## subtle chime, fading smoothly over 3.5 seconds. Never saved.

const DURATION: float = 3.5
const BEAM_HEIGHT: float = 128.0
const SQUASH: float = 0.52
const COLOR_TEAL: Color = Color("78f4e6")
const COLOR_GOLD: Color = Color("ffe699")
const COLOR_CORE: Color = Color("fffaf0")
const PEER_PALETTE: Array[Color] = [
	Color("b9f3ee"),
	Color("ffd98a"),
	Color("ff7fd8"),
	Color("a6e68f"),
]

var peer_id: int = 1
var color_slot: int = 0
var zone_id: StringName = &""

var _age: float = 0.0
var _accent: Color = COLOR_TEAL
var _light: NightLight = null
var _motes: Array[Vector3] = [] ## (x_offset, phase, speed)


func setup(p_peer_id: int, p_color_slot: int, p_world_pos: Vector2, p_zone_id: StringName) -> void:
	peer_id = p_peer_id
	color_slot = clampi(p_color_slot, 0, PEER_PALETTE.size() - 1)
	position = p_world_pos.round()
	zone_id = p_zone_id
	_accent = PEER_PALETTE[color_slot].lerp(COLOR_TEAL, 0.45)


func _ready() -> void:
	add_to_group("map_ping_pillars")
	material = Unlit.material()
	z_index = 6
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([peer_id, int(position.x), int(position.y), Time.get_ticks_msec()])
	for i: int in 7:
		_motes.append(Vector3(rng.randf_range(-4.0, 4.0), float(i) / 7.0, rng.randf_range(0.32, 0.58)))
	_light = NightLight.new()
	_light.radius = 34
	_light.squash = 0.56
	_light.base_energy = 0.42
	_light.glow_color = COLOR_TEAL.lerp(COLOR_GOLD, 0.35)
	_light.pulse = 0.08
	_light.position = Vector2(0.0, -2.0)
	add_child(_light)
	Sfx.at(self, "ui_confirm", global_position, -5.0, 0.04, 480.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	if _light != null and is_instance_valid(_light):
		var env: float = _envelope()
		_light.base_energy = 0.42 * env
	queue_redraw()


func _envelope() -> float:
	var fade_in: float = clampf(_age / 0.12, 0.0, 1.0)
	var rem: float = clampf(1.0 - _age / DURATION, 0.0, 1.0)
	return fade_in * pow(rem, 1.35)


func _draw() -> void:
	var env: float = _envelope()
	if env <= 0.01:
		return
	var pulse: float = 0.88 + 0.12 * sin(_age * 7.5)

	# 1. Expanding outer turquoise wave ring on the ground
	var wave_u: float = fposmod(_age * 0.72, 1.0)
	var wave_r: float = lerpf(6.0, 24.0, 1.0 - pow(1.0 - wave_u, 2.0))
	var wave_a: float = (1.0 - wave_u) * 0.62 * env
	_draw_pixel_ring(wave_r, Color(COLOR_TEAL, wave_a))

	# 2. Crisp inner golden-teal beacon ring + 4 cardinal diamond ticks
	var inner_r: float = 9.0 + sin(_age * 4.2) * 0.8
	_draw_pixel_ring(inner_r, Color(_accent.lerp(COLOR_GOLD, 0.4), 0.78 * env * pulse))
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var tick: Vector2 = Vector2(roundf(dir.x * (inner_r + 2.0)), roundf(dir.y * (inner_r + 2.0) * SQUASH))
		draw_rect(Rect2(tick, Vector2.ONE), Color(COLOR_GOLD, 0.88 * env))

	# 3. Soft ground glow disc at the foot of the shaft
	draw_rect(Rect2(Vector2(-3.0, -1.0), Vector2(6.0, 2.0)), Color(COLOR_TEAL, 0.40 * env * pulse))
	draw_rect(Rect2(Vector2(-1.0, -1.0), Vector2(2.0, 2.0)), Color(COLOR_CORE, 0.82 * env))

	# 4. Narrow vertical Unlit light shaft (stepped pixel bands dissolving skyward)
	var bands: int = 32
	var step_h: float = BEAM_HEIGHT / float(bands)
	var narrow: float = lerpf(0.55, 1.0, env)
	for b: int in bands:
		var v: float = float(b) / float(bands) ## 0 at ground -> 1 at top
		var falloff: float = pow(1.0 - v, 1.65)
		var y_top: float = -roundf(float(b + 1) * step_h)
		var h_px: float = maxf(1.0, roundf(step_h))
		var outer_w: float = maxf(2.0, roundf(lerpf(6.0, 2.0, v) * narrow))
		var gold_w: float = 2.0 if v < 0.72 else 1.0
		var teal_a: float = 0.34 * falloff * env * pulse
		var gold_a: float = 0.68 * falloff * env * pulse
		if teal_a > 0.015:
			draw_rect(Rect2(Vector2(-floorf(outer_w * 0.5), y_top), Vector2(outer_w, h_px)), Color(COLOR_TEAL, teal_a))
		if gold_a > 0.02:
			draw_rect(Rect2(Vector2(-floorf(gold_w * 0.5), y_top), Vector2(gold_w, h_px)), Color(COLOR_GOLD, gold_a))
		if v < 0.42:
			var core_a: float = 0.78 * (1.0 - v / 0.42) * env
			draw_rect(Rect2(Vector2(-1.0, y_top), Vector2(2.0 if v < 0.22 else 1.0, h_px)), Color(COLOR_CORE, core_a))

	# 5. Rising turquoise & gold sparks drifting up the shaft
	for i: int in _motes.size():
		var m: Vector3 = _motes[i]
		var mu: float = fposmod(m.y + _age * m.z, 1.0)
		var ma: float = sin(mu * PI) * env * 0.90
		if ma <= 0.04:
			continue
		var mx: float = roundf(m.x * (1.0 - mu * 0.45) + sin(_age * 3.6 + float(i) * 1.3) * 1.4)
		var my: float = -roundf(4.0 + mu * (BEAM_HEIGHT * 0.88))
		var mcol: Color = COLOR_GOLD if (i % 2 == 0) else COLOR_TEAL
		draw_rect(Rect2(Vector2(mx, my), Vector2(1.0, 2.0 if mu < 0.5 else 1.0)), Color(mcol, ma))


func _draw_pixel_ring(radius: float, col: Color) -> void:
	if col.a <= 0.01 or radius < 1.0:
		return
	var steps: int = clampi(int(radius * 3.2), 16, 64)
	var last_px: Vector2i = Vector2i(999999, 999999)
	for i: int in steps:
		var ang: float = TAU * float(i) / float(steps)
		var pt: Vector2i = Vector2i(roundi(cos(ang) * radius), roundi(sin(ang) * radius * SQUASH))
		if pt != last_px:
			draw_rect(Rect2(Vector2(pt), Vector2.ONE), col)
			last_px = pt
