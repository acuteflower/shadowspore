class_name FinisherFx
extends Node2D
## Shadowspore 2.0 — Unlit Pixel-Art Choreography FX for V2 Finishers (`V3`, `V4`).
## Strictly adheres to `docs/design_guide.md`: crisp pixel-snapped clusters, `Unlit.material()`,
## pure Shadow Creature & Void palette (`#07040d`..`#ecd2ff`, `#ff4fd8`) + equipped weapon trail colors,
## and zero grey smoke!

const CHITIN_DARK: Color = Color("07040d")
const CHITIN_MID: Color = Color("1a1030")
const RIM_VIOLET: Color = Color("5a36b8")
const VEIN_VIOLET: Color = Color("8a4dff")
const GLOW_VIOLET: Color = Color("b06bff")
const CORE_WHITE: Color = Color("ecd2ff")
const DANGER_PINK: Color = Color("ff4fd8")

var _blade_edge: Color = Color("aac8ff")
var _blade_core: Color = Color("f2f7ff")
var _strike_dir: Vector2 = Vector2.RIGHT

var _plunge_age: float = -1.0
var _press_age: float = -1.0
var _rip_age: float = -1.0
var _rip_dir: Vector2 = Vector2(0.6, -0.8).normalized()

var _chips: Array[Dictionary] = [] ## {pos, vel, z, vz, col, sz, age, life}
var _fissures: Array[Dictionary] = [] ## {ang, len, seed}
var _light: NightLight = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 6
	material = Unlit.material()
	_rng.randomize()
	_light = NightLight.new()
	_light.radius = 44
	_light.squash = 0.62
	_light.glow_color = GLOW_VIOLET
	_light.base_energy = 0.0
	_light.pulse = 0.0
	add_child(_light)


func setup(at_world: Vector2, strike_dir: Vector2, blade_edge: Color, blade_core: Color) -> void:
	global_position = at_world.round()
	_strike_dir = strike_dir.normalized() if strike_dir.length_squared() > 0.001 else Vector2.RIGHT
	_blade_edge = blade_edge
	_blade_core = blade_core


## Beat 1 (`0.24 s`): Vertical downward sword lance pierce + 4-ray entry star + chitin chips!
func trigger_plunge() -> void:
	_plunge_age = 0.0
	if _light != null:
		_light.glow_color = _blade_core.lerp(GLOW_VIOLET, 0.55)
		_light.base_energy = 0.95
		_light.set_night(TimeManager.night_amount())
	for i: int in 14:
		var a: float = _rng.randf_range(0.0, TAU)
		var spd: float = _rng.randf_range(26.0, 78.0)
		var is_glow: bool = i % 3 == 0
		var col: Color = (CORE_WHITE if i % 6 == 0 else GLOW_VIOLET) if is_glow else (CHITIN_MID if i % 2 == 0 else RIM_VIOLET)
		_chips.append({
			"pos": Vector2(0.0, -7.0),
			"vel": Vector2(cos(a), sin(a) * 0.62) * spd,
			"z": _rng.randf_range(2.0, 6.0),
			"vz": _rng.randf_range(38.0, 92.0),
			"col": col,
			"sz": 2 if i % 4 == 0 else 1,
			"age": 0.0,
			"life": _rng.randf_range(0.24, 0.42),
		})
	queue_redraw()


## Beat 2 (`0.52 s`): Brutal second deep press — radial ground fissures & pressurized Void-core eruption!
func trigger_press() -> void:
	_press_age = 0.0
	_fissures.clear()
	for i: int in 7:
		var base_a: float = float(i) * (TAU / 7.0) + _rng.randf_range(-0.22, 0.22)
		_fissures.append({
			"ang": base_a,
			"len": _rng.randf_range(13.0, 23.0),
			"seed": _rng.randf_range(0.0, 10.0),
		})
	if _light != null:
		_light.glow_color = GLOW_VIOLET.lerp(CORE_WHITE, 0.35)
		_light.base_energy = 1.35
		_light.set_night(TimeManager.night_amount())
	# Flat pressurized Void-ichor & glowing spore sparks forced sideways under the pinned carapace!
	for i: int in 18:
		var a: float = _rng.randf_range(0.0, TAU)
		var spd: float = _rng.randf_range(38.0, 96.0)
		var col: Color = CORE_WHITE if i % 5 == 0 else (DANGER_PINK if i % 7 == 0 else (GLOW_VIOLET if i % 2 == 0 else VEIN_VIOLET))
		_chips.append({
			"pos": Vector2(cos(a) * 3.0, -3.0 + sin(a) * 2.0),
			"vel": Vector2(cos(a), sin(a) * 0.58) * spd,
			"z": _rng.randf_range(0.0, 3.0),
			"vz": _rng.randf_range(18.0, 54.0),
			"col": col,
			"sz": 2 if i % 3 == 0 else 1,
			"age": 0.0,
			"life": _rng.randf_range(0.26, 0.46),
		})
	queue_redraw()


## Beat 3 (`0.78 s`): Violent upward wrench/rip-out — sweeping crescent arc & Void crystal shatter!
func trigger_rip(rip_dir: Vector2) -> void:
	_rip_age = 0.0
	_rip_dir = rip_dir.normalized() if rip_dir.length_squared() > 0.001 else Vector2(0.55, -0.83)
	if _light != null:
		_light.glow_color = CORE_WHITE
		_light.base_energy = 1.55
		_light.set_night(TimeManager.night_amount())
	for i: int in 24:
		var spread: float = _rng.randf_range(-0.95, 0.95)
		var launch_2d: Vector2 = _rip_dir.rotated(spread) * _rng.randf_range(44.0, 128.0)
		var col: Color = _blade_core if i % 4 == 0 else (CORE_WHITE if i % 3 == 0 else (GLOW_VIOLET if i % 2 == 0 else CHITIN_DARK))
		_chips.append({
			"pos": Vector2(_rng.randf_range(-3.0, 3.0), -6.0),
			"vel": Vector2(launch_2d.x, launch_2d.y * 0.65),
			"z": _rng.randf_range(3.0, 9.0),
			"vz": _rng.randf_range(58.0, 132.0),
			"col": col,
			"sz": 2 if i % 3 == 0 else 1,
			"age": 0.0,
			"life": _rng.randf_range(0.30, 0.56),
		})
	queue_redraw()


func _process(delta: float) -> void:
	var dirty: bool = false
	if _plunge_age >= 0.0:
		_plunge_age += delta
		dirty = true
		if _plunge_age > 0.26:
			_plunge_age = -1.0
	if _press_age >= 0.0:
		_press_age += delta
		dirty = true
		if _press_age > 0.36:
			_press_age = -1.0
	if _rip_age >= 0.0:
		_rip_age += delta
		dirty = true
		if _rip_age > 0.42:
			_rip_age = -1.0

	for i: int in range(_chips.size() - 1, -1, -1):
		var c: Dictionary = _chips[i]
		var age: float = float(c["age"]) + delta
		var life: float = float(c["life"])
		if age >= life:
			_chips.remove_at(i)
			dirty = true
			continue
		c["age"] = age
		c["pos"] = (c["pos"] as Vector2) + (c["vel"] as Vector2) * delta
		c["vel"] = (c["vel"] as Vector2).move_toward(Vector2.ZERO, 155.0 * delta)
		var vz: float = float(c["vz"]) - 280.0 * delta
		var z: float = maxf(0.0, float(c["z"]) + vz * delta)
		if z <= 0.0 and vz < 0.0:
			vz = -vz * 0.28
		c["vz"] = vz
		c["z"] = z
		dirty = true

	if _light != null and _light.base_energy > 0.001:
		_light.base_energy = move_toward(_light.base_energy, 0.0, 3.2 * delta)
		_light.set_night(TimeManager.night_amount())

	if dirty:
		queue_redraw()
	elif _plunge_age < 0.0 and _press_age < 0.0 and _rip_age < 0.0 and _chips.is_empty() and (_light == null or _light.base_energy <= 0.01):
		queue_free()


func _px(p: Vector2, c: Color, sz: int = 1) -> void:
	draw_rect(Rect2(p.round(), Vector2(float(sz), float(sz))), c)


func _draw() -> void:
	# 1. Ground-hugging glowing Void fissures during Beat 2 (Second Deep Press)!
	if _press_age >= 0.0:
		var pk: float = clampf(_press_age / 0.34, 0.0, 1.0)
		var fade_p: float = 1.0 - smoothstep(0.45, 1.0, pk)
		var reach_k: float = smoothstep(0.0, 0.24, pk)
		for f: Dictionary in _fissures:
			var ang: float = float(f["ang"])
			var flen: float = float(f["len"]) * reach_k
			var fseed: float = float(f["seed"])
			var dir2: Vector2 = Vector2(cos(ang), sin(ang) * 0.62)
			var perp2: Vector2 = Vector2(-dir2.y, dir2.x)
			var steps: int = maxi(3, int(flen / 2.0))
			for s: int in range(1, steps + 1):
				var u: float = float(s) / float(steps)
				var jag: float = sin(u * 9.0 + fseed) * 1.4
				var pt: Vector2 = Vector2(0.0, -2.0) + dir2 * (flen * u) + perp2 * jag
				var col_f: Color = CORE_WHITE if u < 0.32 else (GLOW_VIOLET if u < 0.68 else RIM_VIOLET)
				col_f.a = fade_p * (1.0 - u * 0.35)
				_px(pt, col_f, 2 if u < 0.28 else 1)
		# Vertical energy veins climbing the buried blade at the entry wound!
		var vein_h: float = 18.0 * (1.0 - pk * 0.4)
		for vy: int in range(int(vein_h)):
			var frac_v: float = float(vy) / maxf(vein_h, 1.0)
			var vx: float = roundf(sin(float(vy) * 0.9 + _press_age * 36.0) * 1.5)
			var vc: Color = CORE_WHITE if vy < 4 else GLOW_VIOLET
			vc.a = fade_p * (1.0 - frac_v * 0.75)
			_px(Vector2(vx, -5.0 - float(vy)), vc, 1)

	# 2. Vertical downward lance streak & 4-ray entry flash during Beat 1 (Plunge)!
	if _plunge_age >= 0.0:
		var k1: float = clampf(_plunge_age / 0.24, 0.0, 1.0)
		var a1: float = 1.0 - k1
		var top_y: float = -34.0 + k1 * 10.0
		var bot_y: float = -5.0
		var h_len: int = maxi(2, int(bot_y - top_y))
		for dy_i: int in h_len:
			var y_pos: float = bot_y - float(dy_i)
			var u1: float = float(dy_i) / float(h_len)
			var outer_c: Color = _blade_edge.lerp(VEIN_VIOLET, 0.45)
			outer_c.a = a1 * (1.0 - u1 * 0.65)
			var inner_c: Color = _blade_core
			inner_c.a = a1 * (1.0 - u1 * 0.45)
			if dy_i < int(float(h_len) * 0.65):
				_px(Vector2(-1.0, y_pos), outer_c, 1)
				_px(Vector2(1.0, y_pos), outer_c, 1)
			_px(Vector2(0.0, y_pos), inner_c, 1)
		# Crisp 4-point pixel star at the sternum puncture point `(0, -6)`
		if k1 < 0.55:
			var star_r: int = int(lerpf(8.0, 2.0, k1 / 0.55))
			var sc: Color = CORE_WHITE
			sc.a = 1.0 - k1 / 0.55
			for r_i: int in range(-star_r, star_r + 1):
				_px(Vector2(float(r_i), -6.0), sc, 1)
				if abs(r_i) <= star_r - 2:
					_px(Vector2(0.0, -6.0 + float(r_i)), sc, 1)

	# 3. Violent upward-sweeping rip-out crescent during Beat 3 (Rip-Out)!
	if _rip_age >= 0.0:
		var kr: float = clampf(_rip_age / 0.36, 0.0, 1.0)
		var ar: float = 1.0 - kr
		var base_ang: float = (-_strike_dir).angle() - 0.55
		var arc_span: float = 1.65 * smoothstep(0.0, 0.42, kr)
		var rad_base: float = lerpf(11.0, 23.0, smoothstep(0.0, 0.65, kr))
		var arc_steps: int = 22
		for s_i: int in range(arc_steps + 1):
			var u_r: float = float(s_i) / float(arc_steps)
			var ang_r: float = base_ang + u_r * arc_span
			var r_cur: float = rad_base * (0.72 + 0.36 * sin(u_r * PI))
			var pt_r: Vector2 = Vector2(0.0, -10.0) + Vector2(cos(ang_r) * r_cur, sin(ang_r) * r_cur * 0.76 - u_r * 9.0)
			var col_r: Color = _blade_core if u_r > 0.55 else GLOW_VIOLET.lerp(_blade_edge, 0.5)
			col_r.a = ar * sin(u_r * PI)
			_px(pt_r, col_r, 2 if (u_r > 0.35 and u_r < 0.82 and kr < 0.45) else 1)

	# 4. Crisp pixel chitin fragments & Void crystal sparks
	for c: Dictionary in _chips:
		var age_c: float = float(c["age"])
		var life_c: float = float(c["life"])
		var col_c: Color = c["col"] as Color
		col_c.a = 1.0 - smoothstep(0.55, 1.0, age_c / maxf(life_c, 0.01))
		var scr: Vector2 = (c["pos"] as Vector2) + Vector2(0.0, -float(c["z"]))
		_px(scr, col_c, int(c["sz"]))
