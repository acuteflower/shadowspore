class_name ListenerRig
extends Node2D
## A hunched listening mass: planted tactile limbs, layered tissue, a throat that
## physically unseams into lobes, and emissive veins flowing toward its pressure core.
## Procedural pixel geometry is projected afresh; no rotated/scaled raster sprites.

signal foot_landed(point: Vector2)
enum Pose { LISTEN, MOVE, NOTICE, CHARGE, RELEASE, BRACE, SCREAM, RECOVER, HURT, DEAD }

class Limb:
	extends RefCounted
	var side: float
	var tactile: bool
	var foot: Vector2
	var from: Vector2
	var to: Vector2
	var pose_from: Vector2
	var stepping: bool = false
	var progress: float = 0.0
	var phase: float = 0.0
	var lift: float = 0.0
	var front: bool = false
	var points: PackedVector2Array = []

const OUTLINE: Color = Color("040208")
const DARK: Color = Color("07040d")
const FLESH: Color = Color("0e0919")
const UPPER: Color = Color("1a1030")
const RIM: Color = Color("5a36b8")
const VEIN: Color = VoidGlow.VEIN
const VEIN_LIGHT: Color = VoidGlow.VEIN_LIGHT
const CORE: Color = Color("ecd2ff")
const EYE: Color = Color("ff4fd8")

var _limbs: Array[Limb] = []
var _pose: Pose = Pose.LISTEN
var _elapsed: float = 0.0
var _duration: float = 1.0
var _time: float = 0.0
var _heading: float = 0.0
var _opening: float = 0.0
var _charge: float = 0.0
var _alpha: float = 1.0
var _flash: float = 0.0
var _agitation: float = 0.0
var _hip: Vector2
var _chest: Vector2
var _head: Vector2
var _sway: Vector2
var _head_width: float = 5.0
var _feet_ready: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _clock: RigClock = RigClock.new()
var _drawn_shadow_alpha: float = -1.0

@onready var _back: Node2D = $Back
@onready var _back_glow: Node2D = $BackGlow
@onready var _body: Node2D = $Body
@onready var _body_glow: Node2D = $BodyGlow
@onready var _front: Node2D = $Front
@onready var _front_glow: Node2D = $FrontGlow


func _ready() -> void:
	_rng.seed = hash(get_parent().name)
	for tactile: bool in [false, true]:
		for side: float in [-1.0, 1.0]:
			var limb: Limb = Limb.new()
			limb.side = side
			limb.tactile = tactile
			limb.phase = _rng.randf() * TAU
			_limbs.append(limb)
	_back.draw.connect(func() -> void: _draw_limbs(_back, false, false))
	_back_glow.draw.connect(func() -> void: _draw_limbs(_back_glow, false, true))
	_body.draw.connect(_draw_body)
	_body_glow.draw.connect(_draw_body_light)
	_front.draw.connect(func() -> void: _draw_limbs(_front, true, false))
	_front_glow.draw.connect(func() -> void: _draw_limbs(_front_glow, true, true))


func start_pose(pose: Pose, duration: float, elapsed: float = 0.0) -> void:
	_pose = pose
	_duration = maxf(0.01, duration)
	_elapsed = elapsed
	for limb: Limb in _limbs:
		limb.pose_from = limb.foot
		limb.stepping = false


func hit_flash() -> void:
	_flash = 1.0
	_agitation = 1.0


func mouth_position() -> Vector2:
	return global_position + _head


func _project(forward: float, side: float, height: float = 0.0) -> Vector2:
	return Vector2(cos(_heading) * forward - sin(_heading) * side, (sin(_heading) * forward + cos(_heading) * side) * 0.72 - height)


func update_rig(delta: float, velocity: Vector2, heading: float) -> void:
	delta = _clock.step(self, delta, velocity.length(), _pose != Pose.LISTEN) ## rebuilt and redrawn ~30 times a second, rarely off screen (RigClock)
	if delta < 0.0:
		return
	_time += delta
	_elapsed += delta
	_heading = heading
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	_agitation = move_toward(_agitation, 0.0, delta * 2.5)
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	_charge = 0.0
	_opening = 0.07 + sin(_time * 1.7) * 0.025
	_alpha = 1.0
	var lean: float = 0.0
	var sag: float = 0.0
	match _pose:
		Pose.LISTEN, Pose.NOTICE:
			lean = sin(_time * 0.9) * 1.4
			if _pose == Pose.NOTICE:
				sag = -2.0 * sin(t * PI)
				_opening = 0.25 * sin(t * PI)
		Pose.CHARGE, Pose.BRACE:
			_charge = smoothstep(0.0, 0.9, t)
			_opening = _charge * (0.65 if _pose == Pose.BRACE else 1.0)
			lean = (-4.5 if _pose == Pose.BRACE else -3.0) * _charge
			sag = (8.0 if _pose == Pose.BRACE else 3.0) * _charge
		Pose.RELEASE, Pose.SCREAM:
			_charge = 1.0 - t * 0.4
			_opening = (1.65 if _pose == Pose.SCREAM else 1.0) - t * 0.4
			lean = sin(t * PI) * (8.0 if _pose == Pose.SCREAM else 6.0)
			sag = -sin(t * PI) * (6.0 if _pose == Pose.SCREAM else 3.0)
		Pose.RECOVER:
			_opening = pow(1.0 - t, 2.0) * 0.7
			sag = sin(t * PI) * 5.0
			lean = -2.0 * (1.0 - t)
		Pose.HURT:
			sag = sin(t * PI) * 3.0
			_opening = 0.3 * (1.0 - t)
		Pose.DEAD:
			_alpha = 1.0 - t * t
			sag = t * 26.0
			_opening = 0.6 * (1.0 - t)
	var breath: float = sin(_time * 2.1)
	_sway = Vector2(sin(_time * 1.3) * 0.75, cos(_time * 1.8) * 0.5)
	_sway += Vector2(sin(_time * 43), cos(_time * 31)) * _agitation * 1.1
	_hip = _project(-3.0, 0.0, maxf(3.0, 12.0 - sag * 0.3)) + _sway
	_chest = _project(1.0 + lean * 0.4, 0.0, maxf(3.0, 23.0 - sag + breath * 0.55)) + _sway
	_head = _project(6.0 + lean, 0.0, maxf(4.0, 33.0 - sag + sin(_time * 2.1 - 0.35) * 0.45)) + _sway
	_head_width = 4.6 + _opening * 6.0
	for limb: Limb in _limbs:
		_update_limb(limb, delta, velocity, t)
		_build_limb(limb)
	for canvas: Node2D in [_back, _back_glow, _body, _body_glow, _front, _front_glow]:
		canvas.queue_redraw()
	if absf(_alpha - _drawn_shadow_alpha) > 0.004:
		_drawn_shadow_alpha = _alpha
		queue_redraw()


func _rest(limb: Limb) -> Vector2:
	return global_position + _project(15.0 if limb.tactile else -6.0, limb.side * (17.0 if limb.tactile else 9.0))


func _update_limb(limb: Limb, delta: float, velocity: Vector2, t: float) -> void:
	var rest: Vector2 = _rest(limb)
	if not _feet_ready or limb.foot == Vector2.ZERO:
		limb.foot = rest
		limb.pose_from = rest
	if limb == _limbs[-1]:
		_feet_ready = true
	limb.lift = 0.0
	if _pose == Pose.DEAD:
		limb.foot = limb.pose_from.lerp(global_position + _project(0, limb.side * 3), smoothstep(0.0, 1.0, t))
	elif _pose in [Pose.CHARGE, Pose.BRACE, Pose.RELEASE, Pose.SCREAM]:
		var spread: Vector2 = global_position + _project(18 if limb.tactile else -9, limb.side * (21 if limb.tactile else 12))
		if _pose == Pose.SCREAM and limb.tactile:
			var splay: Vector2 = global_position + _project(24, limb.side * 27)
			limb.foot = limb.pose_from.lerp(splay, sin(t * PI) * 0.8)
			limb.lift = sin(t * PI) * 3.0
		else:
			limb.foot = limb.pose_from.lerp(spread, smoothstep(0.0, 0.7, t)) if _pose in [Pose.CHARGE, Pose.BRACE] else limb.pose_from
	elif _pose == Pose.RECOVER:
		limb.foot = limb.pose_from.lerp(rest, smoothstep(0.2, 0.95, t))
	else:
		if limb.stepping:
			limb.progress += delta / (0.17 if limb.tactile else 0.22)
			var k: float = minf(1.0, limb.progress)
			var fold: Vector2 = global_position + (limb.from - global_position) * 0.5
			limb.foot = limb.from.lerp(fold, smoothstep(0.0, 0.45, k)).lerp(limb.to, smoothstep(0.35, 1.0, k))
			limb.lift = sin(k * PI) * (4 if limb.tactile else 3)
			if k >= 1.0:
				limb.stepping = false
				foot_landed.emit(limb.foot)
		elif limb.foot.distance_to(rest) > (6.0 if limb.tactile else 5.0) or (velocity.length() < 4.0 and sin(_time * 1.2 + limb.phase) > 0.998):
			var occupied: int = 0
			for other: Limb in _limbs:
				occupied += int(other.stepping)
			if occupied < 2 or limb.foot.distance_to(rest) > 24.0:
				limb.from = limb.foot
				limb.to = rest + velocity * 0.1
				limb.progress = 0.0
				limb.stepping = true
	limb.front = (limb.foot - global_position).y >= -2.0


func _build_limb(limb: Limb) -> void:
	var root: Vector2 = (_chest if limb.tactile else _hip) + _project(0, limb.side * (4.0 if limb.tactile else 3.0))
	var end: Vector2 = limb.foot - global_position - Vector2(0, limb.lift)
	var span: Vector2 = end - root
	var curl: Vector2 = span.orthogonal().normalized() * limb.side * (6.0 + _opening * 3.0)
	var a: Vector2 = root + span * 0.25 + curl - Vector2(0, 5)
	var b: Vector2 = root + span * 0.7 - curl * 0.55
	var count: int = clampi(ceili(span.length() * 0.8), 10, 26)
	limb.points.resize(count)
	var curl_dir: Vector2 = curl.normalized()
	var inv_count: float = 1.0 / float(count - 1)
	for i: int in count:
		var t: float = float(i) * inv_count
		var u: float = 1.0 - t
		var u2: float = u * u
		var t2: float = t * t
		limb.points[i] = root * (u2 * u) + a * (3.0 * u2 * t) + b * (3.0 * u * t2) + end * (t2 * t) + curl_dir * (sin(t * PI) * sin(_time * 1.7 + limb.phase + t * 5.0) * 0.9)


func _tint(color: Color, alpha: float = 1.0) -> Color:
	if _flash <= 0.001:
		return color if (_alpha >= 0.999 and alpha >= 0.999) else Color(color, _alpha * alpha)
	return Color(color.lerp(Color.WHITE, _flash * 0.85), _alpha * alpha)


func _oval(canvas: Node2D, center: Vector2, radius: Vector2, color: Color) -> void:
	for y: int in range(-ceili(radius.y), ceili(radius.y) + 1):
		var q: float = float(y) / maxf(radius.y, 0.01)
		if absf(q) > 1.0:
			continue
		var w: int = floori(sqrt(1.0 - q * q) * radius.x)
		canvas.draw_rect(Rect2((center + Vector2(-w, y)).round(), Vector2(w * 2 + 1, 1)), color)


func _line(canvas: Node2D, from: Vector2, to: Vector2, thickness: float, color: Color) -> void:
	var count: int = maxi(1, ceili(from.distance_to(to)))
	var inv_count: float = 1.0 / float(count)
	var size: Vector2 = Vector2.ONE * thickness
	var half: Vector2 = Vector2.ONE * floorf(thickness * 0.5)
	var prev: Vector2 = Vector2.INF
	for i: int in count + 1:
		var point: Vector2 = from.lerp(to, float(i) * inv_count).round()
		if point == prev:
			continue
		if thickness >= 3.0 and i < count and absf(point.x - prev.x) + absf(point.y - prev.y) <= 1.0:
			continue
		prev = point
		canvas.draw_rect(Rect2(point - half, size), color)


func _halo(canvas: Node2D, point: Vector2, color: Color, strength: float, bloom: float = 0.5) -> void:
	VoidGlow.halo_tex(canvas, VoidGlow.atlas_tex(), point, color, strength * _alpha, bloom)


func _draw_limbs(canvas: Node2D, front: bool, lit: bool) -> void:
	var out_col: Color = _tint(OUTLINE)
	var upper_col: Color = _tint(UPPER)
	var flesh_col: Color = _tint(FLESH)
	var rim_col: Color = _tint(RIM)
	var vg_tex: ImageTexture = VoidGlow.atlas_tex() if lit else null
	for limb: Limb in _limbs:
		var count: int = limb.points.size()
		if limb.front != front or count <= 2:
			continue
		var inv_count: float = 1.0 / float(count - 1)
		if lit:
			var prev_h: Vector2 = Vector2.INF
			for i: int in range(2, count - 2, 2):
				var hr: Vector2 = limb.points[i].round()
				if hr == prev_h:
					continue
				prev_h = hr
				var flow: float = 0.3 + 0.7 * VoidGlow.beat(_time, -float(i) * 0.018, 0.8 + _charge * 1.6)
				VoidGlow.halo_tex(canvas, vg_tex, limb.points[i], VEIN_LIGHT if (i & 2) == 0 else VEIN, (0.55 + _charge * 0.35) * flow * _alpha, 0.4)
			VoidGlow.halo_tex(canvas, vg_tex, limb.points[count >> 1], VEIN, 0.4 * _alpha, 0.5)
			VoidGlow.halo_tex(canvas, vg_tex, limb.points[-1], CORE, (0.7 + _charge * 0.25) * _alpha, 0.8)
			continue
		var draw_p: PackedVector2Array = PackedVector2Array()
		var draw_d: PackedInt32Array = PackedInt32Array()
		var draw_t: PackedFloat32Array = PackedFloat32Array()
		var draw_rim: PackedInt32Array = PackedInt32Array()
		var prev_p: Vector2 = Vector2.INF
		var prev_d: int = -1
		var base_thick: float = 3.2 if limb.tactile else 4.5
		for i: int in count:
			var t: float = float(i) * inv_count
			var diameter: int = maxi(1, roundi(lerpf(base_thick, 1.0, t)))
			var p: Vector2 = limb.points[i].round()
			if p == prev_p and diameter == prev_d:
				continue
			if diameter >= 3 and diameter == prev_d and i < count - 1 and absf(p.x - prev_p.x) + absf(p.y - prev_p.y) <= 1.0:
				continue
			prev_p = p
			prev_d = diameter
			var half_o: float = floorf(diameter * 0.5) + 1.0
			canvas.draw_rect(Rect2(p.x - half_o, p.y - half_o, diameter + 2, diameter + 2), out_col)
			draw_p.append(p)
			draw_d.append(diameter)
			draw_t.append(t)
			draw_rim.append(1 if (i & 1) == 0 and t < 0.8 else 0)
		for j: int in draw_p.size():
			var d: int = draw_d[j]
			var p: Vector2 = draw_p[j]
			var half: float = floorf(d * 0.5)
			canvas.draw_rect(Rect2(p.x - half, p.y - half, d, d), upper_col if draw_t[j] > 0.55 else flesh_col)
			if draw_rim[j] != 0:
				canvas.draw_rect(Rect2(p.x - 1.0, p.y - 1.0, 1.0, 1.0), rim_col)


func _draw_body() -> void:
	if not _feet_ready:
		return
	# Spine and layered thorax: an uneven, connected silhouette rather than a robe.
	_line(_body, _hip, _chest, 10.0 - _charge * 1.3, _tint(OUTLINE))
	_line(_body, _hip + Vector2(-1, 0), _chest, 7.0 - _charge, _tint(FLESH))
	_oval(_body, _hip, Vector2(6, 6), _tint(OUTLINE))
	_oval(_body, _hip - Vector2(1, 1), Vector2(4.5, 4.5), _tint(UPPER))
	var breath: float = sin(_time * 2.1) * 0.3 * (1.0 - _charge)
	_oval(_body, _chest, Vector2(7 + _charge * 2 + breath, 10 - _charge), _tint(OUTLINE))
	_oval(_body, _chest - Vector2(1, 1), Vector2(5.5 + _charge * 2 + breath, 8.5 - _charge), _tint(FLESH))
	_line(_body, _chest + Vector2(1, -2), _head, 5, _tint(OUTLINE))
	_line(_body, _chest, _head, 3, _tint(UPPER))
	for side: float in [-1.0, 1.0]:
		for rib: int in 3:
			var root: Vector2 = _chest + _project(-2 + rib * 1.4, side * (5.8 + _charge * 1.5), 4 - rib * 3)
			_line(_body, root, _chest + _project(3, side * 1.5, 3 - rib * 3), 2, _tint(UPPER))
			_body.draw_rect(Rect2(root.round(), Vector2.ONE), _tint(RIM))
	# Three head lobes peel apart around a deep central slit. The dark inner
	# tissue stays world-lit; only the later glow pass illuminates seams and eyes.
	_oval(_body, _head, Vector2(_head_width, 8.5 + _opening * 2), _tint(OUTLINE))
	for side: float in [-1, 1]:
		var plate: Vector2 = _head + _project(-1, side * (2.3 + _opening * 4.2), 1.4 + _opening * 1.8)
		_oval(_body, plate, Vector2(3.4, 7.8 + _opening * 1.5), _tint(DARK))
		_line(_body, plate - Vector2(1, 5), plate + _project(2, -side * 0.8, -3), 2, _tint(UPPER))
		var tip: Vector2 = _head + _project(-2, side * (8.0 + _opening * 5.0), 9 + _opening * 5)
		_line(_body, plate, tip, 3, _tint(OUTLINE))
		_line(_body, plate + Vector2(-1, 0), tip, 1, _tint(UPPER))
		var feeler_tip: Vector2 = _head + _project(4 + sin(_time * 1.5 + side) * 2, side * (13 + _opening * 3), 2 + cos(_time * 1.2 + side) * 3)
		_line(_body, plate, feeler_tip, 2, _tint(OUTLINE))
		_line(_body, plate, feeler_tip, 1, _tint(UPPER))
	var crown: Vector2 = _head + Vector2(0, -8 - _opening * 5)
	_line(_body, _head + Vector2(0, -3), crown, 4, _tint(OUTLINE))
	_line(_body, _head + Vector2(-1, -4), crown, 2, _tint(UPPER))


func _draw_body_light() -> void:
	if not _feet_ready:
		return
	var vg_tex: ImageTexture = VoidGlow.atlas_tex()
	var px_rect: Rect2 = VoidGlow.pixel_rect()
	var rate: float = 0.8 + _charge * 1.6
	var pulse: float = (VoidGlow.pulse(_time, 0.0, rate, 0.42) + _charge * 0.25) * _alpha
	for side: float in [-1, 1]:
		for i: int in 6:
			var t: float = float(i) / 5.0
			var point: Vector2 = _hip.lerp(_chest, t) + _project(0, side * (1.8 + sin(t * PI) * 2.0), 0)
			VoidGlow.halo_tex(_body_glow, vg_tex, point, VEIN_LIGHT if i % 2 == 0 else VEIN, (VoidGlow.pulse(_time, -t * 0.3, rate, 0.3) * 1.1 + _charge * 0.2) * _alpha, 0.5)
		# Shoulder/rib seams carry the same living violet tissue as the spider.
		for rib: int in 3:
			var outer: Vector2 = _chest + _project(-2 + rib * 1.4, side * (5.8 + _charge * 1.5), 4 - rib * 3)
			var inner: Vector2 = _chest + _project(3, side * 1.5, 3 - rib * 3)
			for j: int in 2:
				VoidGlow.halo_tex(_body_glow, vg_tex, inner.lerp(outer, float(j)), VEIN, pulse * 0.85, 0.5)
		var seam: Vector2 = _head + _project(0, side * (1.5 + _opening * 4), 0)
		for i: int in 6:
			var fi: float = float(i) * 1.8 - 4.5
			VoidGlow.halo_tex(_body_glow, vg_tex, seam + Vector2(sin(fi * 0.8 + side) * 0.7, fi), VEIN_LIGHT, pulse * 0.95, 0.5)
		var eye: Vector2 = _head + _project(3, side * (2.7 + _opening * 4), 3.0)
		VoidGlow.halo_tex(_body_glow, vg_tex, eye, EYE, (0.95 + _charge * 0.3) * _alpha, 1.1)
		VoidGlow.halo_tex(_body_glow, vg_tex, eye + Vector2(0, 1), CORE, (0.6 + _charge * 0.5) * _alpha, 0.0)
	VoidGlow.halo_tex(_body_glow, vg_tex, _chest + _project(-1, 0, 2), VEIN_LIGHT, pulse * 0.9, 0.8)
	VoidGlow.halo_tex(_body_glow, vg_tex, _hip + Vector2(-1, -1), VEIN, pulse * 0.9, 0.8)
	if _opening > 0.15:
		var radius: Vector2 = Vector2(1.0 + _opening * 2.0, 1.0 + _opening * 3.5)
		var rim_col: Color = Color(VEIN, _alpha * _opening * 0.17)
		var mid_col: Color = Color(VEIN, _alpha * _opening * 0.75)
		var outer_r: Vector2 = radius + Vector2(1.0, 1.0)
		for y: int in range(-ceili(outer_r.y), ceili(outer_r.y) + 1):
			var q_o: float = float(y) / maxf(outer_r.y, 0.01)
			if absf(q_o) <= 1.0:
				var w_o: int = floori(sqrt(1.0 - q_o * q_o) * outer_r.x)
				_body_glow.draw_texture_rect_region(vg_tex, Rect2((_head + Vector2(-w_o, y)).round(), Vector2(w_o * 2 + 1, 1)), px_rect, rim_col)
			var q_m: float = float(y) / maxf(radius.y, 0.01)
			if absf(q_m) <= 1.0:
				var w_m: int = floori(sqrt(1.0 - q_m * q_m) * radius.x)
				_body_glow.draw_texture_rect_region(vg_tex, Rect2((_head + Vector2(-w_m, y)).round(), Vector2(w_m * 2 + 1, 1)), px_rect, mid_col)
		_body_glow.draw_texture_rect_region(vg_tex, Rect2(Vector2(roundf(_head.x), roundf(_head.y - radius.y * 0.65)), Vector2(1.0, maxf(1.0, roundf(radius.y * 1.3)))), px_rect, Color(CORE, _alpha * _opening))


func _draw() -> void:
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.5, 0.45))
	draw_circle(Vector2.ZERO, 6, Color(0.025, 0.015, 0.04, _alpha * 0.3))
