class_name MovementRules
extends RefCounted
## Pure stateless math and rules for Shadowspore 2.0 player locomotion (`res://data/movement.json`).
## Safe to call on any peer or inside headless tests with zero scene-tree side effects.

enum Quadrant { FORWARD = 0, STRAFE_RIGHT = 1, STRAFE_LEFT = 2, BACKPEDAL = 3 }


static func cfg() -> Dictionary:
	return DataRegistry.table("movement")


static func section(key: String) -> Dictionary:
	return cfg().get(key, {}) as Dictionary


## Non-linear acceleration, carving turn, hard 180-degree sprint-pivot, sprint-surge, and speed-aware brake curve (`T1`, `T3`).
## `input_vec` may carry analog stick magnitude `0..1`. Returns `{velocity: Vector2, pivoted: bool, braking: bool}`.
static func step_velocity(
	current: Vector2,
	input_vec: Vector2,
	target_speed: float,
	delta: float,
	move_age: float,
	surge_left: float,
	sprint_age: float,
	traction: float,
	in_pivot: bool = false
) -> Dictionary:
	var curves: Dictionary = section("curves")
	var turn: Dictionary = section("turn")
	var accel_base: float = float(curves.get("accel", 880.0)) * clampf(traction, 0.45, 1.35)
	var mag: float = clampf(input_vec.length(), 0.0, 1.0)

	if mag <= 0.001 or target_speed <= 0.01:
		var use_glide: bool = sprint_age >= float(curves.get("sprint_brake_after", 0.38)) and current.length() > 72.0
		var brake_rate: float = float(curves.get("sprint_brake_glide", 650.0) if use_glide else curves.get("walk_brake", 1220.0))
		brake_rate *= clampf(traction, 0.5, 1.3)
		var next_stop: Vector2 = current.move_toward(Vector2.ZERO, brake_rate * delta)
		return {
			"velocity": next_stop,
			"pivoted": false,
			"braking": use_glide and next_stop.length() > 14.0,
		}

	var dir: Vector2 = input_vec / mag
	var surge_s: float = maxf(float(curves.get("sprint_surge_seconds", 0.18)), 0.01)
	var surge_k: float = clampf(surge_left / surge_s, 0.0, 1.0)
	var surge_mult: float = lerpf(1.0, float(curves.get("sprint_surge_mult", 1.22)), surge_k * surge_k)
	var analog_scale: float = lerpf(0.55, 1.0, clampf((mag - 0.18) / 0.82, 0.0, 1.0)) if mag < 0.96 else 1.0
	var desired_speed: float = target_speed * analog_scale * surge_mult
	var desired: Vector2 = dir * desired_speed

	var cur_speed: float = current.length()
	var pivoted: bool = false

	# T1: Crisp first-frame micro-impulse so starting from rest never feels sluggish
	var instant_window: float = float(curves.get("instant_window", 0.045))
	var instant_floor: float = desired_speed * float(curves.get("instant_share", 0.45))
	if move_age <= instant_window and cur_speed < instant_floor and not in_pivot:
		current = dir * instant_floor
		cur_speed = instant_floor

	if cur_speed > 8.0:
		var cur_dir: Vector2 = current / cur_speed
		var dot_val: float = clampf(cur_dir.dot(dir), -1.0, 1.0)
		var angle_deg: float = rad_to_deg(acos(dot_val))
		var carve_deg: float = float(turn.get("carve_deg", 68.0))
		var pivot_deg: float = float(turn.get("pivot_deg", 125.0))
		var pivot_min: float = float(turn.get("pivot_min_speed", 86.0))

		if angle_deg >= pivot_deg and cur_speed >= pivot_min and not in_pivot:
			pivoted = true
			var pivot_accel: float = accel_base * float(turn.get("pivot_accel_mult", 2.35))
			return {
				"velocity": current.move_toward(desired, pivot_accel * delta),
				"pivoted": true,
				"braking": false,
			}
		elif in_pivot:
			var pivot_accel2: float = accel_base * float(turn.get("pivot_accel_mult", 2.35))
			return {
				"velocity": current.move_toward(desired, pivot_accel2 * delta),
				"pivoted": false,
				"braking": false,
			}
		elif angle_deg <= carve_deg:
			# T3: Gentle curve carving — rotate velocity vector directly with zero artificial speed loss
			var steer_rate: float = lerpf(18.0, 11.5, clampf(angle_deg / maxf(carve_deg, 1.0), 0.0, 1.0)) * clampf(traction, 0.65, 1.25)
			var turned_dir: Vector2 = cur_dir.slerp(dir, 1.0 - exp(-steer_rate * delta)).normalized()
			var next_spd: float = move_toward(cur_speed, desired_speed, accel_base * delta)
			return {
				"velocity": turned_dir * next_spd,
				"pivoted": false,
				"braking": false,
			}
		elif dot_val < 0.0:
			accel_base *= 1.75

	# Ease-out approach near top speed so acceleration feels lively early and smooth at cruise
	var speed_gap: float = absf(desired_speed - cur_speed) / maxf(desired_speed, 1.0)
	var curve_boost: float = lerpf(0.82, 1.32, clampf(speed_gap, 0.0, 1.0))
	return {
		"velocity": current.move_toward(desired, accel_base * curve_boost * delta),
		"pivoted": pivoted,
		"braking": false,
	}


## Directional slope speed multiplier (`T4`) from `Relief.level_at(now)` vs `Relief.level_at(ahead)`.
static func slope_factor(level_now: float, level_ahead: float, probe_dist: float) -> float:
	if probe_dist <= 0.1:
		return 1.0
	var topo: Dictionary = section("topography")
	# One full relief level over ~16..32 px of a ramp/stair gives delta_h ~ 0.25..0.5 over an 8 px probe
	var dh: float = level_ahead - level_now
	if absf(dh) < 0.015 or absf(dh) > 0.85: ## > 0.85 is a sheer cliff wall, not a walkable slope
		return 1.0
	var normalized_grade: float = clampf(dh / (probe_dist / 20.0), -1.0, 1.0)
	if normalized_grade > 0.0:
		return lerpf(1.0, float(topo.get("uphill_scale", 0.88)), normalized_grade)
	return lerpf(1.0, float(topo.get("downhill_scale", 1.08)), -normalized_grade)


## Road footing bonus & wet/mud traction multiplier (`T4`).
static func surface_traction(surface_id: String, wet: float, rain_puddle: float) -> float:
	var curves: Dictionary = section("curves")
	var wet_scale: float = float(curves.get("wet_brake_scale", 0.72))
	var base: float = 1.0
	match surface_id:
		"mud", "quicksand":
			base = 0.68
		"puddle", "shallow_water", "tide_shallow":
			base = 0.76
		"sand", "beach_sand":
			base = 0.88
		"wet_sand":
			base = 0.94
		"path", "stone", "quartz", "ancient_stone":
			base = 1.08
	var damp: float = clampf(maxf(wet * 0.65, rain_puddle), 0.0, 1.0)
	if surface_id in ["stone", "ancient_stone", "mine_stone", "wood", "slope"]:
		base *= lerpf(1.0, wet_scale, damp)
	return clampf(base, 0.5, 1.2)


## Road speed bonus (`+6 %` on dry stone/path/quartz when not in mud/water, `T4`).
static func road_speed_bonus(surface_id: String) -> float:
	var topo: Dictionary = section("topography")
	var roads: Array = topo.get("road_surfaces", ["path", "stone", "quartz"]) as Array
	return float(topo.get("road_bonus", 1.06)) if (roads.has(surface_id) or surface_id == "ancient_stone") else 1.0


## Out-of-combat `Reisetritt` travel state (`T5`): returns `{active, on_road, stamina_scale, speed_mult}`.
static func reisetritt_state(in_combat: bool, near_threat: bool, surface_id: String, sprint_age: float) -> Dictionary:
	if in_combat or near_threat:
		return {"active": false, "on_road": false, "stamina_scale": 1.0, "speed_mult": 1.0}
	var rt: Dictionary = section("reisetritt")
	var topo: Dictionary = section("topography")
	var roads: Array = topo.get("road_surfaces", ["path", "stone", "quartz"]) as Array
	var on_road: bool = roads.has(surface_id) or surface_id == "ancient_stone"
	var active: bool = sprint_age >= float(rt.get("enter_seconds", 1.1))
	if on_road and active:
		return {
			"active": true,
			"on_road": true,
			"stamina_scale": float(rt.get("road_stamina_scale", 0.0)),
			"speed_mult": float(rt.get("road_speed_bonus", 1.08)),
		}
	return {
		"active": active,
		"on_road": on_road,
		"stamina_scale": float(rt.get("wild_stamina_scale", 0.35)),
		"speed_mult": 1.02 if active else 1.0,
	}


## Relative combat footwork quadrant (`T9`) from `move_dir` and `aim_dir`.
static func combat_quadrant(move_dir: Vector2, aim_dir: Vector2) -> int:
	if move_dir.length_squared() < 0.001 or aim_dir.length_squared() < 0.001:
		return Quadrant.FORWARD
	var cf: Dictionary = section("combat_footwork")
	var fwd_deg: float = float(cf.get("forward_deg", 55.0))
	var strafe_deg: float = float(cf.get("strafe_deg", 125.0))
	var m: Vector2 = move_dir.normalized()
	var a: Vector2 = aim_dir.normalized()
	var deg: float = rad_to_deg(acos(clampf(m.dot(a), -1.0, 1.0)))
	if deg <= fwd_deg:
		return Quadrant.FORWARD
	if deg >= strafe_deg:
		return Quadrant.BACKPEDAL
	# Cross product in screen space (y down): a.cross(m) > 0 means moving clockwise (to her right side)
	return Quadrant.STRAFE_RIGHT if a.cross(m) >= 0.0 else Quadrant.STRAFE_LEFT


static func combat_speed_scale(quadrant: int) -> float:
	var cf: Dictionary = section("combat_footwork")
	match quadrant:
		Quadrant.STRAFE_RIGHT, Quadrant.STRAFE_LEFT:
			return float(cf.get("strafe_speed_scale", 0.94))
		Quadrant.BACKPEDAL:
			return float(cf.get("backpedal_speed_scale", 0.86))
	return 1.0


## Surface acoustic multiplier (`T12`) for enemy & wildlife hearing.
static func surface_noise_scale(surface_id: String) -> float:
	var imp: Dictionary = section("impulse")
	var table: Dictionary = imp.get("surface_noise", {}) as Dictionary
	return float(table.get(surface_id, 1.0))


## Adaptive camera look-ahead & combat/aim framing (`T10`).
static func camera_lead_target(
	velocity: Vector2,
	deadzone_exc: float,
	sprinting: bool,
	reisetritt: bool,
	aim_delta: Vector2,
	aim_framing: bool
) -> Vector2:
	var cam: Dictionary = section("camera")
	var max_lead: float = float(cam.get("max_lead_px", 38.0))
	var lead_sec: float = float(cam.get("sprint_lead_sec", 0.30) if sprinting else cam.get("walk_lead_sec", 0.20))
	if reisetritt:
		lead_sec *= 1.15
	var vel_lead: Vector2 = velocity * lead_sec * clampf(deadzone_exc, 0.0, 1.0)
	if vel_lead.length() > max_lead:
		vel_lead = vel_lead.normalized() * max_lead
	if aim_framing and aim_delta.length_squared() > 4.0:
		var aim_share: float = float(cam.get("aim_share", 0.28))
		var aim_max: float = float(cam.get("aim_max_px", 42.0))
		var aim_vec: Vector2 = aim_delta * aim_share
		if aim_vec.length() > aim_max:
			aim_vec = aim_vec.normalized() * aim_max
		return (vel_lead * 0.45 + aim_vec).limit_length(aim_max + 8.0)
	return vel_lead
