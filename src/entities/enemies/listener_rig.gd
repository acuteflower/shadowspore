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
	delta = _clock.step(self, delta, velocity.length()) ## rebuilt and redrawn ~30 times a second, rarely off screen (RigClock)
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
	limb.points.resize(40)
	for i: int in 40:
		var t: float = float(i) / 39.0
		var u: float = 1.0 - t
		limb.points[i] = root * u * u * u + a * 3 * u * u * t + b * 3 * u * t * t + end * t * t * t
		limb.points[i] += curl.normalized() * sin(t * PI) * sin(_time * 1.7 + limb.phase + t * 5.0) * 0.9


func _tint(color: Color, alpha: float = 1.0) -> Color:
	return Color(color.lerp(Color.WHITE, _flash * 0.85), _alpha * alpha)


func _oval(canvas: Node2D, center: Vector2, radius: Vector2, color: Color) -> void:
	for y: int in range(-ceili(radius.y), ceili(radius.y) + 1):
		var q: float = float(y) / maxf(radius.y, 0.01)
		if absf(q) > 1.0:
			continue
		var w: int = floori(sqrt(1.0 - q * q) * radius.x)
		canvas.draw_rect(Rect2((center + Vector2(-w, y)).round(), Vector2(w * 2 + 1, 1)), color)


func _line(canvas: Node2D, from: Vector2, to: Vector2, thickness: float, color: Color) -> void:
	var count: int = maxi(1, ceili(from.distance_to(to) * 1.5))
	for i: int in count + 1:
		var point: Vector2 = from.lerp(to, float(i) / count).round()
		canvas.draw_rect(Rect2(point - Vector2.ONE * floorf(thickness * 0.5), Vector2.ONE * thickness), color)


func _halo(canvas: Node2D, point: Vector2, color: Color, strength: float, bloom: float = 0.5) -> void:
	VoidGlow.halo(canvas, point, color, strength * _alpha, bloom)


func _draw_limbs(canvas: Node2D, front: bool, lit: bool) -> void:
	for limb: Limb in _limbs:
		if limb.front != front or limb.points.is_empty():
			continue
		if lit:
			for i: int in range(3, 37):
				var flow: float = 0.3 + 0.7 * VoidGlow.beat(_time, -float(i) * 0.012, 0.8 + _charge * 1.6)
				_halo(canvas, limb.points[i], VEIN_LIGHT if i % 4 == 0 else VEIN, (0.55 + _charge * 0.35) * flow, 0.4)
			_halo(canvas, limb.points[20], VEIN, 0.4)
			_halo(canvas, limb.points[-1], CORE, 0.7 + _charge * 0.25, 0.8)
			continue
		for pass_index: int in 2:
			for i: int in limb.points.size():
				var t: float = float(i) / 39.0
				var diameter: int = maxi(1, roundi(lerpf(3.2 if limb.tactile else 4.5, 1.0, t)))
				if pass_index == 0:
					canvas.draw_rect(Rect2(limb.points[i].round() - Vector2.ONE * (floorf(diameter * 0.5) + 1), Vector2.ONE * (diameter + 2)), _tint(OUTLINE))
				else:
					canvas.draw_rect(Rect2(limb.points[i].round() - Vector2.ONE * floorf(diameter * 0.5), Vector2.ONE * diameter), _tint(UPPER if t > 0.55 else FLESH))
					if i % 3 == 0 and t < 0.8:
						canvas.draw_rect(Rect2(limb.points[i].round() - Vector2(1, 1), Vector2.ONE), _tint(RIM))


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
	var rate: float = 0.8 + _charge * 1.6
	var pulse: float = VoidGlow.pulse(_time, 0.0, rate, 0.42) + _charge * 0.25
	for side: float in [-1, 1]:
		for i: int in 18:
			var t: float = float(i) / 17.0
			var point: Vector2 = _hip.lerp(_chest, t) + _project(0, side * (1.8 + sin(t * PI) * 2.0), 0)
			_halo(_body_glow, point, VEIN_LIGHT if i % 3 == 0 else VEIN, VoidGlow.pulse(_time, -t * 0.3, rate, 0.3) * 1.1 + _charge * 0.2, 0.5)
		# Shoulder/rib seams carry the same living violet tissue as the spider.
		for rib: int in 3:
			var outer: Vector2 = _chest + _project(-2 + rib * 1.4, side * (5.8 + _charge * 1.5), 4 - rib * 3)
			var inner: Vector2 = _chest + _project(3, side * 1.5, 3 - rib * 3)
			for j: int in 5:
				_halo(_body_glow, inner.lerp(outer, float(j) / 4.0), VEIN, pulse * 0.85)
		var seam: Vector2 = _head + _project(0, side * (1.5 + _opening * 4), 0)
		for i: int in 10:
			_halo(_body_glow, seam + Vector2(sin(i * 0.8 + side) * 0.7, i - 5), VEIN_LIGHT, pulse * 0.95)
		var eye: Vector2 = _head + _project(3, side * (2.7 + _opening * 4), 3.0)
		_halo(_body_glow, eye, EYE, 0.95 + _charge * 0.3, 1.1)
		_halo(_body_glow, eye + Vector2(0, 1), CORE, 0.6 + _charge * 0.5, 0.0)
	_halo(_body_glow, _chest + _project(-1, 0, 2), VEIN_LIGHT, pulse * 0.9, 0.8)
	_halo(_body_glow, _hip + Vector2(-1, -1), VEIN, pulse * 0.9, 0.8)
	if _opening > 0.15:
		var radius: Vector2 = Vector2(1.0 + _opening * 2.0, 1.0 + _opening * 3.5)
		_oval(_body_glow, _head, radius + Vector2(1, 1), Color(VEIN, _alpha * _opening * 0.17))
		_oval(_body_glow, _head, radius, Color(VEIN, _alpha * _opening * 0.75))
		_line(_body_glow, _head - Vector2(0, radius.y * 0.65), _head + Vector2(0, radius.y * 0.65), 1, Color(CORE, _alpha * _opening))


func _draw() -> void:
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.5, 0.45))
	draw_circle(Vector2.ZERO, 6, Color(0.025, 0.015, 0.04, _alpha * 0.3))
