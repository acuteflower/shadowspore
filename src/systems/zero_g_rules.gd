class_name ZeroGRules
extends RefCounted
## Pure data-driven rules for weightless free-floating movement in Caelia's interstellar sanctuary
## (docs/caelia_interstellar_konzept.md, data/zero_g.json).
## Kept tree-free so headless unit tests can verify inertia, counter-thrust, boost-glide,
## hover-brake, and soft veil-horizon return curvature directly.

enum State {
	NONE = 0,
	IDLE = 1,
	DRIFT = 2,
	GLIDE = 3,
	BRAKE = 4,
	ARRIVE = 5,
}

const DEFAULT_CENTER: Vector2 = Vector2(1100.0, 1100.0)
const DEFAULT_ARRIVAL: Vector2 = Vector2(1100.0, 1390.0)

static var _cache: Dictionary = {}


static func config() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if DataRegistry != null:
		var loaded: Dictionary = DataRegistry.table("zero_g")
		if not loaded.is_empty():
			_cache = loaded
			return _cache
	return {}


static func clear_cache() -> void:
	_cache.clear()


static func section(key: String) -> Dictionary:
	var cfg: Dictionary = config()
	var sec: Variant = cfg.get(key, {})
	return sec as Dictionary if sec is Dictionary else {}


static func room_center() -> Vector2:
	var raw: Variant = config().get("center", [DEFAULT_CENTER.x, DEFAULT_CENTER.y])
	if raw is Array and (raw as Array).size() >= 2:
		var a: Array = raw as Array
		return Vector2(float(a[0]), float(a[1]))
	return DEFAULT_CENTER


static func arrival_point() -> Vector2:
	var raw: Variant = config().get("arrival", [DEFAULT_ARRIVAL.x, DEFAULT_ARRIVAL.y])
	if raw is Array and (raw as Array).size() >= 2:
		var a: Array = raw as Array
		return Vector2(float(a[0]), float(a[1]))
	return DEFAULT_ARRIVAL


## Horizon ratio in [0..1]: 0 inside soft_radius, smoothly rising to 1 at hard_radius.
static func horizon_ratio(rel_pos: Vector2) -> float:
	var hcfg: Dictionary = section("horizon")
	var r_soft: float = float(hcfg.get("soft_radius", 760.0))
	var r_hard: float = maxf(r_soft + 1.0, float(hcfg.get("hard_radius", 1040.0)))
	var dist: float = rel_pos.length()
	return clampf((dist - r_soft) / (r_hard - r_soft), 0.0, 1.0)


## One physics step of Fluid Zero-G motion.
## `rel_pos` is player position relative to the interstellar center `(1100, 1100)`.
static func step_motion(
	vel: Vector2,
	input_dir: Vector2,
	want_glide: bool,
	want_brake: bool,
	rel_pos: Vector2,
	delta: float,
	boost_ready: bool
) -> Dictionary:
	var m: Dictionary = section("motion")
	var hcfg: Dictionary = section("horizon")

	var cruise_speed: float = float(m.get("cruise_speed", 82.0))
	var glide_speed: float = float(m.get("glide_speed", 158.0))
	var precision_speed: float = float(m.get("precision_speed", 34.0))
	var accel: float = float(m.get("accel", 195.0))
	var glide_accel: float = float(m.get("glide_accel", 290.0))
	var counter_mult: float = float(m.get("counter_thrust_mult", 2.15))
	var drag: float = float(m.get("drag", 1.12))
	var brake_drag: float = float(m.get("brake_drag", 4.9))
	var settle_speed: float = float(m.get("settle_speed", 7.5))
	var settle_drag: float = float(m.get("settle_drag", 3.4))
	var boost_impulse: float = float(m.get("boost_impulse", 36.0))
	var brake_dot: float = float(m.get("brake_dot_threshold", -0.38))
	var brake_min_spd: float = float(m.get("brake_min_speed", 38.0))
	var glide_enter: float = float(m.get("glide_enter_speed", 106.0))
	var drift_enter: float = float(m.get("drift_enter_speed", 14.0))

	var dir: Vector2 = input_dir.normalized() if input_dir.length_squared() > 0.001 else Vector2.ZERO
	var has_input: bool = dir != Vector2.ZERO
	var cur_vel: Vector2 = vel
	var speed: float = cur_vel.length()
	var boost_fired: bool = false

	# Counter-thrust detection: pushing strongly opposite to current drift triggers braking lean-back + extra authority
	var opposing: bool = false
	if has_input and speed >= brake_min_spd:
		var align: float = cur_vel.normalized().dot(dir)
		if align <= brake_dot:
			opposing = true

	var active_glide: bool = want_glide and has_input and not want_brake
	if active_glide and boost_ready and not opposing:
		cur_vel += dir * boost_impulse
		boost_fired = true
		speed = cur_vel.length()

	if has_input:
		var target_spd: float = precision_speed if want_brake else (glide_speed if active_glide else cruise_speed)
		var target_vel: Vector2 = dir * target_spd
		var rate: float = glide_accel if active_glide else accel
		if opposing:
			rate *= counter_mult
		elif want_brake:
			rate *= 1.55
		# Smooth vector curving instead of snappy ground clamping
		var diff: Vector2 = target_vel - cur_vel
		var diff_len: float = diff.length()
		var max_dv: float = rate * delta
		if diff_len <= max_dv:
			cur_vel = target_vel
		else:
			cur_vel += (diff / diff_len) * max_dv
		# Gently trim excess speed above target (e.g. exiting glide into cruise) without jarring snap
		var next_spd: float = cur_vel.length()
		if next_spd > target_spd + 2.0 and not boost_fired:
			var trim_k: float = exp(-(brake_drag if want_brake else drag * 1.45) * delta)
			cur_vel = cur_vel.normalized() * maxf(target_spd, next_spd * trim_k)
	else:
		# Weightless coasting with low exponential drag, or deliberate Hover-Brake, plus calm settle under threshold
		var eff_drag: float = brake_drag if want_brake else (settle_drag if speed < settle_speed else drag)
		cur_vel *= exp(-eff_drag * delta)
		if cur_vel.length() < 1.2:
			cur_vel = Vector2.ZERO

	# Soft Veil Horizon: elastic inward return current beyond soft_radius (no invisible box walls!)
	var r_soft: float = float(hcfg.get("soft_radius", 760.0))
	var r_hard: float = maxf(r_soft + 1.0, float(hcfg.get("hard_radius", 1040.0)))
	var ret_accel: float = float(hcfg.get("return_accel", 340.0))
	var tang_damp: float = float(hcfg.get("tangential_damp", 0.45))

	var dist: float = rel_pos.length()
	var h_ratio: float = clampf((dist - r_soft) / (r_hard - r_soft), 0.0, 1.0)
	if dist > r_soft and dist > 0.001:
		var radial: Vector2 = rel_pos / dist
		# Quadratic elastic pull inward
		cur_vel -= radial * (ret_accel * h_ratio * h_ratio * delta)
		var out_comp: float = cur_vel.dot(radial)
		if out_comp > 0.0:
			# Softly bleed outward momentum while preserving graceful curving glide along the tangent
			var bleed: float = exp(-(1.8 + 7.5 * h_ratio * h_ratio) * delta)
			cur_vel -= radial * (out_comp * (1.0 - bleed))
		if h_ratio > 0.85:
			var tang: Vector2 = cur_vel - radial * cur_vel.dot(radial)
			cur_vel -= tang * (1.0 - exp(-tang_damp * h_ratio * delta))

	var final_spd: float = cur_vel.length()
	var braking_vis: bool = opposing or (want_brake and final_spd >= 22.0 and (not has_input or final_spd > precision_speed + 12.0))

	var state: int = State.IDLE
	if braking_vis:
		state = State.BRAKE
	elif active_glide or (final_spd >= glide_enter and not want_brake):
		state = State.GLIDE
	elif has_input or final_spd >= drift_enter:
		state = State.DRIFT

	return {
		"velocity": cur_vel,
		"state": state,
		"boost_fired": boost_fired,
		"horizon": h_ratio,
		"braking": braking_vis,
	}


## Gentle pixel-friendly Lissajous floating breath offset while hovering in zero gravity.
static func idle_bob_offset(t: float, speed: float) -> Vector2:
	var b: Dictionary = section("idle_bob")
	var amp_y: float = float(b.get("amp_y", 2.6))
	var amp_x: float = float(b.get("amp_x", 1.1))
	var freq_y: float = float(b.get("freq_y", 1.25))
	var freq_x: float = float(b.get("freq_x", 0.62))
	var calm: float = clampf(1.0 - speed / 150.0, 0.28, 1.0)
	return Vector2(
		sin(t * freq_x) * amp_x * calm,
		sin(t * freq_y) * amp_y * calm
	)
