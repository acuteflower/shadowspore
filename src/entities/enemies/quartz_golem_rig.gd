class_name QuartzGolemRig
extends Node2D
## Procedural 3D-projected (`SQUASH = 0.72`), depth-sorted pixel-art rig for `QuartzGolem` ("Quarzwächter").
## Magically suspended desert sandstone blocks & faceted sun-quartz crystals bound by crackling arcane tethers,
## orbiting crystal satellites, engraved sandstone runes, and a hovering ground rune-ring.

signal foot_landed(world_pos: Vector2)

enum Pose {
	DORMANT,
	PEACEFUL,
	AWAKEN,
	MOVE,
	BLADE_WINDUP,
	BLADE_SLASH,
	SHARD_WINDUP,
	SHARD_RELEASE,
	SHOCK_WINDUP,
	SHOCK_SLAM,
	RECOVER,
	HURT,
	DEAD,
}

const SQUASH: float = 0.72
static var _MASKS: Dictionary = {}

var variant: int = 0 ## 0 = Sun-Quartz & Ochre, 1 = Mesa-Terracotta & Amber, 2 = Prisma & Ruin-Stone
var provoked: bool = false
var weather_charge: float = 0.0 ## 0..1 resonance lift & halo during Resonanzwind / Quarzgewitter

var _pose: Pose = Pose.DORMANT
var _pose_time: float = 0.0
var _pose_duration: float = 1.0
var _time: float = 0.0
var _heading: float = PI * 0.5
var _forward: Vector2 = Vector2.DOWN
var _right: Vector2 = Vector2.LEFT
var _stride: float = 0.0
var _speed_ratio: float = 0.0
var _last_step_half: int = -1
var _flash: float = 0.0
var _shoulder_world: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]

@onready var _body: Node2D = $Body
@onready var _glow: Node2D = $Glow


func _ready() -> void:
	_body.draw.connect(_draw_body)
	_glow.draw.connect(_draw_glow)


func start_pose(pose: Pose, duration: float = 1.0, elapsed: float = 0.0) -> void:
	_pose = pose
	_pose_duration = maxf(duration, 0.05)
	_pose_time = elapsed
	queue_redraw_all()


func hit_flash() -> void:
	_flash = 0.14
	queue_redraw_all()


func queue_redraw_all() -> void:
	if is_instance_valid(_body):
		_body.queue_redraw()
	if is_instance_valid(_glow):
		_glow.queue_redraw()


func shard_launch_point(index: int) -> Vector2:
	var idx: int = clampi(index, 0, 2)
	return global_position + _shoulder_world[idx]


func update_rig(delta: float, vel: Vector2, heading_rad: float, is_provoked: bool, resonance_amt: float = 0.0) -> void:
	_time += delta
	_pose_time += delta
	_flash = maxf(0.0, _flash - delta)
	_heading = heading_rad
	provoked = is_provoked
	weather_charge = clampf(resonance_amt, 0.0, 1.0)
	_forward = Vector2.from_angle(_heading)
	_right = Vector2(-_forward.y, _forward.x)
	var spd: float = vel.length()
	_speed_ratio = clampf(spd / 58.0, 0.0, 1.2)
	if spd > 4.0 and _pose in [Pose.PEACEFUL, Pose.MOVE]:
		_stride += delta * (3.2 + spd * 0.09)
		var half: int = int(floorf(_stride / PI))
		if half != _last_step_half:
			_last_step_half = half
			var side_sign: float = 1.0 if (half % 2 == 0) else -1.0
			var foot_ground: Vector2 = _project(0.0, side_sign * 5.8, 0.0)
			foot_landed.emit(global_position + foot_ground)
	queue_redraw_all()


func _project(fwd: float, side: float, height: float) -> Vector2:
	var flat: Vector2 = _forward * fwd + _right * side
	return Vector2(flat.x, flat.y * SQUASH - height)


func _depth(fwd: float, side: float, height: float) -> float:
	var flat: Vector2 = _forward * fwd + _right * side
	return flat.y * SQUASH + height * 0.06


func _palette() -> Dictionary:
	match variant:
		1:
			return {
				"stone_out": Color("2a1719"),
				"stone_0": Color("4d2926"),
				"stone_1": Color("8c4f38"),
				"stone_2": Color("c97d50"),
				"stone_3": Color("efb47a"),
				"quartz_out": Color("34324c"),
				"quartz_0": Color("8392b4"),
				"quartz_1": Color("c2d2e8"),
				"quartz_2": Color("eef4fc"),
				"quartz_3": Color("fff7d6"),
				"tether_dark": Color("2a8c94"),
				"tether": Color("78f4e6"),
				"spark": Color("ffe488"),
				"calm_eye": Color("78f4e6"),
				"angry_eye": Color("ff7847"),
				"angry_spark": Color("ffe488"),
			}
		2:
			return {
				"stone_out": Color("261e30"),
				"stone_0": Color("524658"),
				"stone_1": Color("8e8094"),
				"stone_2": Color("c5b8c6"),
				"stone_3": Color("ebe2e8"),
				"quartz_out": Color("34294c"),
				"quartz_0": Color("8b72ba"),
				"quartz_1": Color("caa8f5"),
				"quartz_2": Color("e4f6ff"),
				"quartz_3": Color("ffffff"),
				"tether_dark": Color("6636ad"),
				"tether": Color("ff8ae2"),
				"spark": Color("78f4e6"),
				"calm_eye": Color("78f4e6"),
				"angry_eye": Color("ff4fd8"),
				"angry_spark": Color("ffe488"),
			}
		_:
			return {
				"stone_out": Color("2b191d"),
				"stone_0": Color("58362e"),
				"stone_1": Color("9e6844"),
				"stone_2": Color("d8a35c"),
				"stone_3": Color("f2cf88"),
				"quartz_out": Color("34324c"),
				"quartz_0": Color("7d96ba"),
				"quartz_1": Color("b8cbe4"),
				"quartz_2": Color("dceaf8"),
				"quartz_3": Color("ffffff"),
				"tether_dark": Color("2a8c94"),
				"tether": Color("78f4e6"),
				"spark": Color("ffe488"),
				"calm_eye": Color("78f4e6"),
				"angry_eye": Color("ff6e4a"),
				"angry_spark": Color("ffe488"),
			}


func _pose_progress() -> float:
	return clampf(_pose_time / maxf(_pose_duration, 0.05), 0.0, 1.0)


func _oval(canvas: Node2D, center: Vector2, radius: Vector2, color: Color) -> void:
	var rx: int = maxi(1, roundi(radius.x))
	var ry: int = maxi(1, roundi(radius.y))
	var key: String = "o%d_%d" % [rx, ry]
	var mask: Array = _MASKS.get(key, [])
	if mask.is_empty():
		var rows: Array[Vector3i] = []
		for y: int in range(-ry, ry + 1):
			var q: float = float(y) / maxf(float(ry), 0.5)
			if absf(q) > 1.0:
				continue
			var w: int = floori(sqrt(maxf(0.0, 1.0 - q * q)) * float(rx))
			rows.append(Vector3i(-w, y, w * 2 + 1))
		mask = CrusherRig._mask(rows)
		_MASKS[key] = mask
	if mask[0] != null:
		canvas.draw_texture(mask[0] as Texture2D, center.round() + Vector2(mask[1] as Vector2i), color)


## Draws a chunky 3/4 pixel-art layered desert sandstone block with optional glowing arcane rune inlay.
func _draw_stone_block(canvas: Node2D, center: Vector2, half_size: Vector2, pal: Dictionary, flash_mix: float, rune_col: Color = Color(0, 0, 0, 0), rune_style: int = 0) -> void:
	var c: Vector2 = center.round()
	var hw: int = maxi(2, roundi(half_size.x))
	var hh: int = maxi(2, roundi(half_size.y))
	var out_c: Color = (pal["stone_out"] as Color).lerp(Color.WHITE, flash_mix * 0.5)
	var s0: Color = (pal["stone_0"] as Color).lerp(Color.WHITE, flash_mix)
	var s1: Color = (pal["stone_1"] as Color).lerp(Color.WHITE, flash_mix)
	var s2: Color = (pal["stone_2"] as Color).lerp(Color.WHITE, flash_mix)
	var s3: Color = (pal["stone_3"] as Color).lerp(Color.WHITE, flash_mix)
	for dy: int in range(-hh - 1, hh + 2):
		var row_trim: int = 1 if abs(dy) >= hh else 0
		var x0: int = -hw + row_trim
		var x1: int = hw - row_trim
		canvas.draw_rect(Rect2(Vector2(c.x + float(x0 - 1), c.y + float(dy)), Vector2(float(x1 - x0 + 3), 1.0)), out_c)
	for dy: int in range(-hh, hh + 1):
		var row_trim: int = 1 if abs(dy) == hh else 0
		var x0: int = -hw + row_trim
		var x1: int = hw - row_trim
		for dx: int in range(x0, x1 + 1):
			var col: Color = s1
			if dy <= -hh + 1 and dx <= 1:
				col = s3
			elif dy < 0 or (dy == 0 and dx < 0):
				col = s2
			elif dy >= hh - 1 or dx >= hw - 1:
				col = s0
			if dy == 1 and (dx + dy) % 3 != 0 and col == s1:
				col = s0
			canvas.draw_rect(Rect2(Vector2(c.x + float(dx), c.y + float(dy)), Vector2.ONE), col)
	if rune_col.a > 0.05:
		if rune_style == 1:
			# Glowing chest/collar sigil (diamond + side ticks)
			canvas.draw_rect(Rect2(c + Vector2(-3.0, 0.0), Vector2(7.0, 1.0)), Color(rune_col, rune_col.a * 0.75))
			canvas.draw_rect(Rect2(c + Vector2(-1.0, -1.0), Vector2(3.0, 3.0)), rune_col)
			canvas.draw_rect(Rect2(c, Vector2.ONE), Color("ffffff", rune_col.a))
		else:
			canvas.draw_rect(Rect2(c + Vector2(-1.0, 0.0), Vector2(3.0, 1.0)), rune_col)
			canvas.draw_rect(Rect2(c, Vector2.ONE), Color("ffe488", rune_col.a))


## Draws a crisp faceted sun-quartz crystal spire oriented along `dir_2d` (with optional glowing arcane vein).
func _draw_quartz_crystal(canvas: Node2D, base_pt: Vector2, dir_2d: Vector2, length: float, half_w: float, pal: Dictionary, flash_mix: float, arcane_vein: Color = Color(0, 0, 0, 0)) -> void:
	var axis: Vector2 = dir_2d.normalized()
	if axis == Vector2.ZERO:
		axis = Vector2.UP
	var perp: Vector2 = Vector2(-axis.y, axis.x)
	var steps: int = maxi(3, roundi(length))
	var out_c: Color = (pal["quartz_out"] as Color).lerp(Color.WHITE, flash_mix * 0.45)
	var q0: Color = (pal["quartz_0"] as Color).lerp(Color.WHITE, flash_mix)
	var q1: Color = (pal["quartz_1"] as Color).lerp(Color.WHITE, flash_mix)
	var q2: Color = (pal["quartz_2"] as Color).lerp(Color.WHITE, flash_mix)
	var q3: Color = (pal["quartz_3"] as Color).lerp(Color.WHITE, flash_mix)
	for s: int in range(-1, steps + 2):
		var frac: float = clampf(float(s) / float(steps), 0.0, 1.0)
		var w_here: int = maxi(0, roundi(half_w * (1.0 - pow(frac, 1.45))))
		if s < 0 or s > steps:
			w_here = 0
		for w: int in range(-w_here - 1, w_here + 2):
			var pt: Vector2 = (base_pt + axis * float(s) + perp * float(w)).round()
			canvas.draw_rect(Rect2(pt, Vector2.ONE), out_c)
	for s: int in range(0, steps + 1):
		var frac: float = float(s) / float(steps)
		var w_here: int = maxi(0, roundi(half_w * (1.0 - pow(frac, 1.45))))
		for w: int in range(-w_here, w_here + 1):
			var pt: Vector2 = (base_pt + axis * float(s) + perp * float(w)).round()
			var world_offset: Vector2 = perp * float(w) + axis * float(s) * 0.25
			var col: Color = q1
			if w == 0 and arcane_vein.a > 0.05 and frac > 0.14 and frac < 0.82 and (s % 2 == 0):
				col = arcane_vein.lerp(q3, 0.35)
			elif w == 0 and frac > 0.24:
				col = q3
			elif world_offset.x + world_offset.y * 0.65 <= -0.35:
				col = q2 if frac < 0.72 else q3
			elif world_offset.x + world_offset.y * 0.65 >= 0.75:
				col = q0
			canvas.draw_rect(Rect2(pt, Vector2.ONE), col)


## Crackling arcane tether with dark contrast backing, luminous thread, and a travelling energy spark!
func _draw_arcane_tether(canvas: Node2D, from: Vector2, to: Vector2, base_col: Color, spark_col: Color, phase_offset: float) -> void:
	var dist: float = from.distance_to(to)
	if dist < 2.0:
		return
	var ortho: Vector2 = (to - from).normalized().orthogonal()
	var count: int = maxi(2, ceili(dist * 1.3))
	var spark_pos: float = fposmod(_time * 2.4 + phase_offset, 1.0)
	for i: int in range(count + 1):
		var k: float = float(i) / float(count)
		var arc_wobble: float = sin(k * PI) * sin(_time * 9.0 + phase_offset * TAU + k * 4.0) * 1.1
		var p: Vector2 = (from.lerp(to, k) + ortho * arc_wobble).round()
		canvas.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color("261a30", base_col.a * 0.65))
		var is_spark: bool = absf(k - spark_pos) < 0.16
		canvas.draw_rect(Rect2(p, Vector2.ONE), spark_col if is_spark else base_col)


func _compute_parts() -> Dictionary:
	var p: float = _pose_progress()
	var hover_bob: float = sin(_time * 3.1) * 1.6 + weather_charge * 2.4
	var collapsed: float = 0.0
	var slam_drop: float = 0.0
	var fist_lift: float = 0.0
	var blade_grow: float = 0.0
	var blade_sweep: float = 0.0
	var shard_orbit: float = 0.0
	var hurt_jolt: float = 0.0

	match _pose:
		Pose.DORMANT:
			collapsed = 1.0
			hover_bob = 0.0
		Pose.AWAKEN:
			collapsed = 1.0 - smoothstep(0.0, 0.85, p)
			hover_bob = sin(p * PI) * 3.8
		Pose.PEACEFUL:
			hover_bob = sin(_time * 2.5) * 1.4 + weather_charge * 1.8
		Pose.MOVE:
			hover_bob = absf(sin(_stride)) * 1.7 + weather_charge * 2.2
		Pose.BLADE_WINDUP:
			blade_grow = smoothstep(0.05, 0.92, p)
			blade_sweep = -0.85 * smoothstep(0.0, 1.0, p)
			hover_bob += 1.6 * p
		Pose.BLADE_SLASH:
			blade_grow = 1.0 - smoothstep(0.88, 1.0, p)
			blade_sweep = lerpf(-0.85, 0.95, smoothstep(0.0, 0.78, p))
		Pose.SHARD_WINDUP:
			shard_orbit = smoothstep(0.04, 0.90, p)
			hover_bob += 4.2 * smoothstep(0.0, 1.0, p)
		Pose.SHARD_RELEASE:
			shard_orbit = 1.0 - smoothstep(0.0, 0.45, p)
			hover_bob += 4.0 * (1.0 - p * 0.6)
		Pose.SHOCK_WINDUP:
			fist_lift = smoothstep(0.0, 0.92, p)
			hover_bob += 3.0 * fist_lift
		Pose.SHOCK_SLAM:
			var impact: float = smoothstep(0.0, 0.28, p)
			slam_drop = sin(impact * PI * 0.5) * (1.0 - smoothstep(0.55, 1.0, p) * 0.5)
		Pose.RECOVER:
			hover_bob = -1.5 * (1.0 - p)
		Pose.HURT:
			hurt_jolt = (1.0 - p) * 3.0
		Pose.DEAD:
			collapsed = smoothstep(0.0, 0.68, p)
			hover_bob = 0.0

	var walk_swing: float = sin(_stride) * _speed_ratio * (1.0 - collapsed)
	var base_lift: float = (1.0 - collapsed) * (14.5 + hover_bob - slam_drop * 5.0) + collapsed * 3.0

	# Clear magical levitation gaps between every block!
	var foot_l: Vector3 = Vector3(walk_swing * 3.6, -6.2 - collapsed * 2.5, maxf(2.0, absf(walk_swing) * 2.2) * (1.0 - collapsed) + 1.5)
	var foot_r: Vector3 = Vector3(-walk_swing * 3.6, 6.2 + collapsed * 2.5, maxf(2.0, absf(-walk_swing) * 2.2) * (1.0 - collapsed) + 1.5)
	var pelvis: Vector3 = Vector3(-hurt_jolt * 0.5, 0.0, lerpf(8.5, 2.5, collapsed) + hover_bob * 0.5)
	var core: Vector3 = Vector3(-hurt_jolt, 0.0, base_lift + lerpf(4.8, 0.5, collapsed))
	var head: Vector3 = Vector3(1.5 - hurt_jolt, 0.0, lerpf(base_lift + 14.0, 4.2, collapsed))

	var sh_spread: float = 11.5 + shard_orbit * 2.5 + collapsed * 2.0
	var sh_h: float = lerpf(base_lift + 6.8 + fist_lift * 6.5 - slam_drop * 6.0, 3.0, collapsed)
	var arm_l: Vector3 = Vector3(2.5 - walk_swing * 2.2 + slam_drop * 3.5, -sh_spread, sh_h - slam_drop * 5.5)
	var arm_r: Vector3 = Vector3(2.5 + walk_swing * 2.2 + slam_drop * 3.5, sh_spread, sh_h - slam_drop * 5.5)

	if blade_grow > 0.01:
		var b_ang: float = blade_sweep
		arm_r = Vector3(cos(b_ang) * 8.5 + 4.5, sin(b_ang) * 9.8 + 2.5, base_lift + 5.5)
		arm_l = Vector3(-3.0, -11.2, base_lift + 5.8)

	return {
		"collapsed": collapsed,
		"foot_l": foot_l,
		"foot_r": foot_r,
		"pelvis": pelvis,
		"core": core,
		"head": head,
		"arm_l": arm_l,
		"arm_r": arm_r,
		"blade_grow": blade_grow,
		"blade_sweep": blade_sweep,
		"shard_orbit": shard_orbit,
		"slam_drop": slam_drop,
		"fist_lift": fist_lift,
	}


func _draw_body() -> void:
	var pal: Dictionary = _palette()
	var flash_mix: float = clampf(_flash / 0.14, 0.0, 1.0)
	var parts: Dictionary = _compute_parts()
	var collapsed: float = float(parts["collapsed"])
	var tether_c: Color = (pal["angry_eye"] as Color if provoked else pal["tether"] as Color)
	var spark_c: Color = (pal["angry_spark"] as Color if provoked else pal["spark"] as Color)
	var eye_c: Color = (pal["angry_eye"] as Color if provoked else pal["calm_eye"] as Color)
	if _pose == Pose.DEAD:
		eye_c = Color(eye_c, 1.0 - collapsed)

	# Ground shadow ellipse anchored at feet (0, 0)
	var shadow_rx: float = lerpf(10.0, 12.5, collapsed)
	var shadow_ry: float = lerpf(3.6, 4.5, collapsed)
	_oval(_body, Vector2.ZERO, Vector2(shadow_rx, shadow_ry), Color("2b191d", 0.36))

	# Hovering Ground Arcane Rune Ring directly beneath the floating golem!
	if collapsed < 0.78 and _pose != Pose.DEAD:
		var ring_alpha: float = (1.0 - collapsed) * (0.78 if provoked else 0.58)
		var ring_r: float = 11.5 + sin(_time * 3.6) * 0.8 + (1.5 if provoked else 0.0)
		var spin_spd: float = 1.9 if provoked else 0.75
		for k: int in 16:
			var ang: float = float(k) / 16.0 * TAU + _time * spin_spd
			var rp: Vector2 = Vector2(cos(ang) * ring_r, sin(ang) * ring_r * SQUASH - 1.0).round()
			var is_cardinal: bool = (k % 4 == 0)
			_body.draw_rect(Rect2(rp + Vector2(0.0, 1.0), Vector2(2.0 if is_cardinal else 1.0, 1.0)), Color("2b191d", ring_alpha * 0.7))
			_body.draw_rect(Rect2(rp, Vector2(2.0 if is_cardinal else 1.0, 1.0)), Color(spark_c if is_cardinal else tether_c, ring_alpha))

	var foot_l3: Vector3 = parts["foot_l"] as Vector3
	var foot_r3: Vector3 = parts["foot_r"] as Vector3
	var pelvis3: Vector3 = parts["pelvis"] as Vector3
	var core3: Vector3 = parts["core"] as Vector3
	var head3: Vector3 = parts["head"] as Vector3
	var arm_l3: Vector3 = parts["arm_l"] as Vector3
	var arm_r3: Vector3 = parts["arm_r"] as Vector3

	var p_core: Vector2 = _project(core3.x, core3.y, core3.z)
	var p_pelvis: Vector2 = _project(pelvis3.x, pelvis3.y, pelvis3.z)
	var p_head: Vector2 = _project(head3.x, head3.y, head3.z)
	var p_arm_l: Vector2 = _project(arm_l3.x, arm_l3.y, arm_l3.z)
	var p_arm_r: Vector2 = _project(arm_r3.x, arm_r3.y, arm_r3.z)
	var p_foot_l: Vector2 = _project(foot_l3.x, foot_l3.y, foot_l3.z)
	var p_foot_r: Vector2 = _project(foot_r3.x, foot_r3.y, foot_r3.z)

	# Crackling, spark-beaded arcane energy tethers visibly suspending every stone piece!
	if collapsed < 0.85:
		var ta: float = (1.0 - collapsed) * 0.95
		var tc: Color = Color(tether_c, ta)
		var sc: Color = Color(spark_c, ta)
		_draw_arcane_tether(_body, p_pelvis, p_core, tc, sc, 0.00)
		_draw_arcane_tether(_body, p_core, p_head, tc, sc, 0.25)
		_draw_arcane_tether(_body, p_core, p_arm_l, tc, sc, 0.50)
		_draw_arcane_tether(_body, p_core, p_arm_r, tc, sc, 0.75)
		_draw_arcane_tether(_body, p_foot_l, p_pelvis, Color(tether_c, ta * 0.80), sc, 0.15)
		_draw_arcane_tether(_body, p_foot_r, p_pelvis, Color(tether_c, ta * 0.80), sc, 0.65)

	# Depth-sorted draw list of 3D parts + 2 orbiting crystal satellites!
	var items: Array[Dictionary] = [
		{"kind": "foot", "v": foot_l3, "d": _depth(foot_l3.x, foot_l3.y, foot_l3.z)},
		{"kind": "foot", "v": foot_r3, "d": _depth(foot_r3.x, foot_r3.y, foot_r3.z)},
		{"kind": "pelvis", "v": pelvis3, "d": _depth(pelvis3.x, pelvis3.y, pelvis3.z)},
		{"kind": "core", "v": core3, "d": _depth(core3.x, core3.y, core3.z)},
		{"kind": "head", "v": head3, "d": _depth(head3.x, head3.y, head3.z)},
		{"kind": "arm_l", "v": arm_l3, "d": _depth(arm_l3.x, arm_l3.y, arm_l3.z)},
		{"kind": "arm_r", "v": arm_r3, "d": _depth(arm_r3.x, arm_r3.y, arm_r3.z)},
	]
	if collapsed < 0.65 and _pose != Pose.DEAD:
		for sat_i: int in 2:
			var sat_ang: float = _time * (2.6 if provoked else 1.5) + float(sat_i) * PI
			var sat3: Vector3 = Vector3(cos(sat_ang) * 11.5, sin(sat_ang) * 14.5, core3.z + 2.0 + sin(_time * 4.0 + float(sat_i)) * 2.0)
			items.append({"kind": "sat", "v": sat3, "d": _depth(sat3.x, sat3.y, sat3.z)})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))

	for entry: Dictionary in items:
		var v: Vector3 = entry["v"] as Vector3
		var screen: Vector2 = _project(v.x, v.y, v.z)
		match String(entry["kind"]):
			"foot":
				_draw_stone_block(_body, screen, Vector2(3.0, 2.0), pal, flash_mix)
			"pelvis":
				_draw_stone_block(_body, screen, Vector2(4.2, 2.4), pal, flash_mix, Color(tether_c, 0.85 * (1.0 - collapsed)))
			"sat":
				# Orbiting arcane quartz shard satellite
				_draw_quartz_crystal(_body, screen + Vector2(0.0, 2.0), Vector2(0.0, -1.0), 5.0, 1.5, pal, flash_mix, Color(tether_c, 0.9))
			"core":
				# Split sandstone shoulder-collar + gleaming exposed Sun-Quartz Arcane Heart!
				_draw_stone_block(_body, screen + Vector2(0.0, 2.0), Vector2(6.2, 3.5), pal, flash_mix, Color(tether_c, 0.95 * (1.0 - collapsed)), 1)
				_draw_quartz_crystal(_body, screen + Vector2(-3.0, 1.0), Vector2(-0.46, -0.89), 9.5, 2.5, pal, flash_mix, Color(tether_c, 0.85))
				_draw_quartz_crystal(_body, screen + Vector2(3.0, 1.0), Vector2(0.48, -0.88), 9.0, 2.4, pal, flash_mix, Color(tether_c, 0.85))
				_draw_quartz_crystal(_body, screen + Vector2(0.0, 0.0), Vector2(0.04, -1.0), 12.5, 3.2, pal, flash_mix, Color(spark_c, 0.95))
			"head":
				_draw_stone_block(_body, screen, Vector2(4.6, 3.0), pal, flash_mix)
				_draw_quartz_crystal(_body, screen + Vector2(0.0, -2.0), Vector2(0.0, -1.0), 8.0, 2.3, pal, flash_mix, Color(tether_c, 0.85))
				if _forward.y > -0.55 and collapsed < 0.65:
					var face_shift: Vector2 = Vector2(clampf(_forward.x * 2.5, -2.0, 2.0), 0.0).round()
					_body.draw_rect(Rect2((screen + face_shift + Vector2(-3.0, 0.0)).round(), Vector2(2.0, 1.0)), eye_c)
					_body.draw_rect(Rect2((screen + face_shift + Vector2(1.0, 0.0)).round(), Vector2(2.0, 1.0)), eye_c)
					_body.draw_rect(Rect2((screen + face_shift + Vector2(-2.0, 0.0)).round(), Vector2.ONE), Color("ffffff", 0.9))
					_body.draw_rect(Rect2((screen + face_shift + Vector2(1.0, 0.0)).round(), Vector2.ONE), Color("ffffff", 0.9))
			"arm_l":
				var fist_scale: float = 1.0 + float(parts["fist_lift"]) * 0.28
				_draw_stone_block(_body, screen, Vector2(3.6 * fist_scale, 3.0 * fist_scale), pal, flash_mix, Color(eye_c, 0.9 * (1.0 - collapsed)))
				_draw_quartz_crystal(_body, screen + Vector2(-1.0, -1.0), Vector2(-0.5, -0.86), 6.5, 2.0, pal, flash_mix, Color(tether_c, 0.8))
			"arm_r":
				var fist_scale_r: float = 1.0 + float(parts["fist_lift"]) * 0.28
				_draw_stone_block(_body, screen, Vector2(3.6 * fist_scale_r, 3.0 * fist_scale_r), pal, flash_mix, Color(eye_c, 0.9 * (1.0 - collapsed)))
				if float(parts["blade_grow"]) <= 0.02:
					_draw_quartz_crystal(_body, screen + Vector2(1.0, -1.0), Vector2(0.5, -0.86), 6.5, 2.0, pal, flash_mix, Color(tether_c, 0.8))

	# Foreground Crystal Arm-Sword (`CRYSTAL_BLADE`) — long rune-veined Sun-Quartz Greatblade!
	var blade_grow_fg: float = float(parts["blade_grow"])
	if blade_grow_fg > 0.02:
		var sweep_ang_fg: float = _heading + float(parts["blade_sweep"]) * 0.95
		var b_dir3_fg: Vector2 = Vector2.from_angle(sweep_ang_fg)
		var b_dir2_fg: Vector2 = Vector2(b_dir3_fg.x, b_dir3_fg.y * SQUASH).normalized()
		var b_perp_fg: Vector2 = Vector2(-b_dir2_fg.y, b_dir2_fg.x)
		var blade_len_fg: float = 40.0 * blade_grow_fg
		_draw_quartz_crystal(_body, p_arm_r + b_dir2_fg * 3.0, (b_dir2_fg * 0.35 + b_perp_fg).normalized(), 9.0 * blade_grow_fg, 2.2, pal, flash_mix, Color("78f4e6", 0.95))
		_draw_quartz_crystal(_body, p_arm_r + b_dir2_fg * 3.0, (b_dir2_fg * 0.35 - b_perp_fg).normalized(), 9.0 * blade_grow_fg, 2.2, pal, flash_mix, Color("78f4e6", 0.95))
		_draw_quartz_crystal(_body, p_arm_r + b_dir2_fg * 2.0, b_dir2_fg, blade_len_fg, 3.8, pal, flash_mix, Color("78f4e6", 1.0))

	# 3 hovering shoulder Sun-Quartz spikes + Arcane Casting Halo during SHARD_WINDUP / SHARD_RELEASE!
	var shard_orbit: float = float(parts["shard_orbit"])
	if shard_orbit > 0.02:
		var aim2: Vector2 = Vector2(_forward.x, _forward.y * SQUASH).normalized()
		if aim2 == Vector2.ZERO:
			aim2 = Vector2.DOWN
		# Arcane rune halo behind shoulders
		for h_i: int in 14:
			var hang: float = float(h_i) / 14.0 * TAU - _time * 3.2
			var hp: Vector2 = (p_core + Vector2(cos(hang) * 15.0 * shard_orbit, sin(hang) * 10.0 * shard_orbit - 10.0)).round()
			_body.draw_rect(Rect2(hp, Vector2.ONE), Color("ffe488" if h_i % 2 == 0 else "78f4e6", 0.85 * shard_orbit))
		for idx: int in 3:
			var side_slot: float = float(idx - 1) * 12.0
			var arc_h: float = core3.z + 13.0 + (4.0 if idx == 1 else 0.0) + sin(_time * 8.0 + float(idx)) * 1.4
			var s_pos: Vector2 = _project(2.5, side_slot, arc_h)
			_shoulder_world[idx] = s_pos
			_draw_quartz_crystal(_body, s_pos - aim2 * 3.5, aim2, 12.0 * shard_orbit, 2.5 * shard_orbit, pal, flash_mix, Color("78f4e6", 0.95))
	else:
		for idx: int in 3:
			_shoulder_world[idx] = p_core + Vector2(float(idx - 1) * 8.0, -9.0)


func _draw_glow() -> void:
	var pal: Dictionary = _palette()
	var parts: Dictionary = _compute_parts()
	var collapsed: float = float(parts["collapsed"])
	var core3: Vector3 = parts["core"] as Vector3
	var pelvis3: Vector3 = parts["pelvis"] as Vector3
	var head3: Vector3 = parts["head"] as Vector3
	var arm_l3: Vector3 = parts["arm_l"] as Vector3
	var arm_r3: Vector3 = parts["arm_r"] as Vector3
	var p_core: Vector2 = _project(core3.x, core3.y, core3.z).round()
	var p_pelvis: Vector2 = _project(pelvis3.x, pelvis3.y, pelvis3.z).round()
	var p_head: Vector2 = _project(head3.x, head3.y, head3.z).round()
	var p_arm_l: Vector2 = _project(arm_l3.x, arm_l3.y, arm_l3.z).round()
	var p_arm_r: Vector2 = _project(arm_r3.x, arm_r3.y, arm_r3.z).round()

	var aura_c: Color = (pal["angry_eye"] as Color if provoked else pal["tether"] as Color)
	var spark_c: Color = (pal["angry_spark"] as Color if provoked else pal["spark"] as Color)
	if _pose == Pose.DEAD:
		return

	if collapsed > 0.75:
		var glint: float = 0.12 + 0.10 * maxf(0.0, sin(_time * 2.2))
		_glow.draw_rect(Rect2(p_core - Vector2(3, 3), Vector2(6, 6)), Color(pal["calm_eye"] as Color, glint))
		return

	# Ground rune-ring glow + subtle Arcane Heart bloom (kept tight so sunlit pixel facets stay crisp!)
	var pulse: float = (0.16 + 0.05 * sin(_time * 5.2) + weather_charge * 0.12) * (1.0 - collapsed)
	_glow.draw_rect(Rect2(Vector2(-10.0, -3.0), Vector2(20.0, 5.0)), Color(aura_c, pulse * 0.22))
	_glow.draw_rect(Rect2(p_core - Vector2(6, 6), Vector2(12, 12)), Color(aura_c, pulse * 0.22))
	_glow.draw_rect(Rect2(p_core - Vector2(3, 4), Vector2(6, 7)), Color(spark_c, pulse * 0.34))

	# Luminous tether sparks along core -> head / arms / pelvis + satellite orbit trails
	for limb_pt: Vector2 in [p_head, p_arm_l, p_arm_r, p_pelvis]:
		var mid_p: Vector2 = p_core.lerp(limb_pt, 0.5).round()
		_glow.draw_rect(Rect2(mid_p - Vector2.ONE, Vector2(2, 2)), Color(aura_c, pulse * 0.38))
		var spark_t: float = fposmod(_time * (2.6 if provoked else 1.4), 1.0)
		var spark_p: Vector2 = p_core.lerp(limb_pt, spark_t).round()
		_glow.draw_rect(Rect2(spark_p, Vector2(2, 2)), Color(spark_c, 0.45 * (1.0 - collapsed)))

	if collapsed < 0.65:
		for sat_i: int in 2:
			var sat_ang_g: float = _time * (2.6 if provoked else 1.5) + float(sat_i) * PI
			for trail_j: int in 4:
				var a_back: float = sat_ang_g - float(trail_j) * 0.24
				var s3: Vector3 = Vector3(cos(a_back) * 11.5, sin(a_back) * 14.5, core3.z + 2.0 + sin(_time * 4.0 + float(sat_i)) * 2.0)
				var sp_sat: Vector2 = _project(s3.x, s3.y, s3.z).round()
				var ta_sat: float = (1.0 - float(trail_j) * 0.23) * 0.34
				_glow.draw_rect(Rect2(sp_sat, Vector2(2, 2)), Color(spark_c if trail_j == 0 else aura_c, ta_sat))

	if _forward.y > -0.55:
		var face_shift: Vector2 = Vector2(clampf(_forward.x * 2.5, -2.0, 2.0), 0.0).round()
		_glow.draw_rect(Rect2(p_head + face_shift + Vector2(-3.0, -1.0), Vector2(6.0, 2.0)), Color(aura_c, 0.26))

	# Awakening spiral arcane vortex
	if _pose == Pose.AWAKEN:
		var ap: float = _pose_progress()
		var ring_r: float = lerpf(6.0, 22.0, ap)
		var ring_a: float = (1.0 - ap) * 0.65
		for i: int in 20:
			var ang: float = float(i) / 20.0 * TAU + ap * 3.6
			var rp: Vector2 = (Vector2(cos(ang) * ring_r, sin(ang) * ring_r * SQUASH - ap * 13.0)).round()
			_glow.draw_rect(Rect2(rp - Vector2.ONE, Vector2(3, 3)), Color("ffe488" if i % 2 == 0 else "78f4e6", ring_a * 0.5))
			_glow.draw_rect(Rect2(rp, Vector2(2, 2)), Color(Color.WHITE, ring_a * 0.85))

	# Ambient rising magical sparks around the hovering construct
	for m_i: int in 5:
		var m_phase: float = fposmod(_time * 0.85 + float(m_i) * 0.21, 1.0)
		var m_ang: float = float(m_i) * 2.399 + _time * 1.2
		var m_x: float = cos(m_ang) * lerpf(11.0, 4.0, m_phase)
		var m_y: float = -4.0 - m_phase * 28.0
		var m_a: float = sin(m_phase * PI) * 0.55 * (1.0 - collapsed)
		_glow.draw_rect(Rect2(Vector2(m_x, m_y).round(), Vector2.ONE), Color("78f4e6" if m_i % 2 == 0 else "ffe488", m_a))

	# Crystal Arm-Sword luminous aura & crescent slash wave
	var blade_grow: float = float(parts["blade_grow"])
	if blade_grow > 0.02:
		var sweep_ang: float = _heading + float(parts["blade_sweep"]) * 0.95
		var b_dir3: Vector2 = Vector2.from_angle(sweep_ang)
		var b_dir2: Vector2 = Vector2(b_dir3.x, b_dir3.y * SQUASH).normalized()
		var blade_len: float = 40.0 * blade_grow
		for s: int in range(2, roundi(blade_len), 3):
			var bp: Vector2 = (p_arm_r + b_dir2 * float(s)).round()
			_glow.draw_rect(Rect2(bp - Vector2(2, 2), Vector2(5, 5)), Color("78f4e6", 0.22 * blade_grow))
			_glow.draw_rect(Rect2(bp - Vector2.ONE, Vector2(3, 3)), Color("ffe488", 0.20 * blade_grow))
		if _pose == Pose.BLADE_SLASH:
			var sp: float = _pose_progress()
			for k: int in 16:
				var frac_k: float = float(k) / 15.0
				var trail_ang: float = sweep_ang - frac_k * 1.45
				var td: Vector2 = Vector2(cos(trail_ang), sin(trail_ang) * SQUASH)
				var tp_outer: Vector2 = (p_core + Vector2(0.0, 4.0) + td * 39.0).round()
				var tp_inner: Vector2 = (p_core + Vector2(0.0, 4.0) + td * 30.0).round()
				var ta_k: float = (1.0 - frac_k) * (1.0 - sp * 0.65)
				_glow.draw_rect(Rect2(tp_outer - Vector2.ONE, Vector2(3, 3)), Color("78f4e6", ta_k * 0.55))
				_glow.draw_rect(Rect2(tp_outer, Vector2(2, 2)), Color("ffffff", ta_k * 0.80))
				_glow.draw_rect(Rect2(tp_inner, Vector2(2, 2)), Color("ffe488", ta_k * 0.45))

	# Hovering shoulder shards casting halo glow
	var shard_orbit: float = float(parts["shard_orbit"])
	if shard_orbit > 0.02:
		_glow.draw_rect(Rect2(p_core + Vector2(-14.0, -18.0), Vector2(28.0, 16.0)), Color("78f4e6", 0.16 * shard_orbit))
		for idx: int in 3:
			var sp2: Vector2 = _shoulder_world[idx].round()
			_glow.draw_rect(Rect2(sp2 - Vector2(4, 4), Vector2(8, 8)), Color("78f4e6", 0.34 * shard_orbit))
			_glow.draw_rect(Rect2(sp2 - Vector2(2, 2), Vector2(4, 4)), Color("ffe488", 0.42 * shard_orbit))

	# Sandstone Shock glowing rune-fists
	if float(parts["fist_lift"]) > 0.05 or float(parts["slam_drop"]) > 0.05:
		var fa: float = maxf(float(parts["fist_lift"]), float(parts["slam_drop"])) * 0.52
		_glow.draw_rect(Rect2(p_arm_l - Vector2(4, 4), Vector2(8, 8)), Color("ff7847", fa))
		_glow.draw_rect(Rect2(p_arm_r - Vector2(4, 4), Vector2(8, 8)), Color("ff7847", fa))
		_glow.draw_rect(Rect2(p_arm_l - Vector2(2, 2), Vector2(4, 4)), Color("ffe488", fa))
		_glow.draw_rect(Rect2(p_arm_r - Vector2(2, 2), Vector2(4, 4)), Color("ffe488", fa))
