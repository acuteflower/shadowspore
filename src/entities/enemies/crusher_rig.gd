class_name CrusherRig
extends Node2D
## The Void Crusher's body, drawn afresh every frame from procedural pixel geometry like the spider and the listener (no rotated or scaled rasters):
## a hunched torso on two planted legs, a basalt club arm on the right that doubles as a third foot (knuckle walking), three thorned tendons on the left,
## a tiled horn collar that shields head and chest from the front, and a cleft between the shoulder humps (the back) where the void core shows.
## Everything is solved in a body frame (forward, side, height), projected 3/4 (`SQUASH`) and depth-sorted part by part, so the arm swings behind and in front of the torso.
## Black tissue and basalt stay world-lit (`Body`); eyes, veins and the core are a separate additive pass (`Glow`) that follows occlusion (the core only shows from behind).

signal foot_landed(point: Vector2, heavy: bool)

enum Pose { IDLE, NOTICE, MOVE, SLAM_WINDUP, SLAM, SLAM_RECOVER, RUSH_WINDUP, RUSH, RUSH_RECOVER, SWEEP_WINDUP, SWEEP, SWEEP_RECOVER, STUN, HURT, DEAD }

class Planted:
	extends RefCounted
	var foot: Vector2 = Vector2.ZERO
	var from: Vector2 = Vector2.ZERO
	var to: Vector2 = Vector2.ZERO
	var pose_from: Vector2 = Vector2.ZERO
	var stepping: bool = false
	var progress: float = 0.0
	var lift: float = 0.0

const OUTLINE: Color = Color("040208")
const DARK: Color = Color("07040d")
const FLESH: Color = Color("0c0814")
const MID: Color = Color("150e24")
const HIGH: Color = Color("1f1638")
const RIM: Color = Color("4a3a8c")
const ROCK0: Color = Color("0d0a17")
const ROCK1: Color = Color("171526")
const ROCK2: Color = Color("262440")
const ROCK3: Color = Color("45436a")
const VEIN: Color = VoidGlow.VEIN
const VEIN_LIGHT: Color = VoidGlow.VEIN_LIGHT
const CORE: Color = Color("ecd2ff")
const EYE: Color = Color("ff4fd8")

const SQUASH: float = 0.72
const ARM_UPPER: float = 24.0
const ARM_LOWER: float = 24.0
const LEG_UPPER: float = 13.5
const LEG_LOWER: float = 13.5
const STRANDS: int = 3
const STRAND_POINTS: int = 28
const REST_FIST: Vector3 = Vector3(15.0, 23.0, 0.0)
const OVERHEAD: Vector3 = Vector3(-4.0, 7.0, 72.0)
const IMPACT: Vector3 = Vector3(35.0, 9.0, 0.0)
const BREAK_AT: float = 0.28 ## the club arm snaps off this far into the death

var slam_hit_frac: float = 0.67 ## how far into the strike the fist lands (the host's hit_time / strike)

var _legs: Array[Planted] = [Planted.new(), Planted.new()]
var _knuckle: Planted = Planted.new()
var _pose: Pose = Pose.IDLE
var _elapsed: float = 0.0
var _duration: float = 1.0
var _time: float = 0.0
var _heading: float = 0.0
var _aim: float = 0.0
var _spin: float = 1.0
var _alpha: float = 1.0
var _flash: float = 0.0
var _agitation: float = 0.0
var _charge: float = 0.0
var _exposed: float = 0.0
var _lean: float = 0.0
var _sag: float = 0.0
var _head_dip: float = 0.0
var _stance: float = 1.0
var _leg_f: Array[float] = [-2.0, 2.0]
var _step_time: float = 0.3
var _sway: Vector3 = Vector3.ZERO
var _fist_free: bool = false
var _fist_goal: Vector3 = REST_FIST
var _fist_rate: float = 20.0
var _fist_snap: bool = false
var _fist_pos: Vector3 = REST_FIST
var _fist: Vector3 = REST_FIST ## after the reach clamp
var _elbow: Vector3 = Vector3.ZERO
var _hip: Vector3 = Vector3.ZERO
var _chest: Vector3 = Vector3.ZERO
var _head: Vector3 = Vector3.ZERO
var _sh_l: Vector3 = Vector3.ZERO
var _sh_r: Vector3 = Vector3.ZERO
var _hips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _knees: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _feet3: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _tips: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _strands: Array[PackedVector2Array] = []
var _strand_depth: PackedFloat32Array = [0.0, 0.0, 0.0]
var _arm_broken: bool = false
var _debris: Array[Dictionary] = []
var _impact_time: float = -10.0
var _ready_geo: bool = false
var _parts: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _body: Node2D = $Body
@onready var _glow: Node2D = $Glow


func _ready() -> void:
	_rng.seed = hash(get_parent().name)
	for i: int in STRANDS:
		_strands.append(PackedVector2Array())
	_body.draw.connect(_draw_main)
	_glow.draw.connect(_draw_glow)


func start_pose(pose: Pose, duration: float, elapsed: float = 0.0) -> void:
	_pose = pose
	_duration = maxf(0.01, duration)
	_elapsed = elapsed
	for limb: Planted in _legs + [_knuckle]:
		limb.pose_from = limb.foot
		limb.stepping = false
	if pose == Pose.SLAM_RECOVER:
		_impact_time = _time - elapsed
	if pose == Pose.SWEEP_WINDUP:
		_spin = 1.0 if angle_difference(_heading, _aim) >= 0.0 else -1.0
	if pose == Pose.DEAD:
		_debris.clear()
	else:
		_arm_broken = false


func hit_flash() -> void:
	_flash = 1.0
	_agitation = 1.0


## Where the head is in the world (the voice and the sparks of a hit on the shield come from here).
func head_point() -> Vector2:
	return global_position + _p(_head)


func core_point() -> Vector2:
	return global_position + _p(Vector3(-10.0 + _lean * 0.5, 0.0, 35.0 - _sag))


func _ang(forward: float, side: float, height: float, heading: float) -> Vector2:
	return Vector2(cos(heading) * forward - sin(heading) * side, (sin(heading) * forward + cos(heading) * side) * SQUASH - height)


func _project(forward: float, side: float, height: float = 0.0) -> Vector2:
	return _ang(forward, side, height, _heading)


func _p(v: Vector3) -> Vector2:
	return _ang(v.x, v.y, v.z, _heading)


## Depth along the view axis: larger = nearer to the camera = drawn later.
func _depth(v: Vector3) -> float:
	return sin(_heading) * v.x + cos(_heading) * v.y


## A ground offset on the screen back into the body frame.
func _frame(delta: Vector2) -> Vector3:
	var u: float = delta.x
	var w: float = delta.y / SQUASH
	return Vector3(cos(_heading) * u + sin(_heading) * w, -sin(_heading) * u + cos(_heading) * w, 0.0)


func _polar(angle: float, radius: float, height: float) -> Vector3:
	var rel: float = angle - _heading
	return Vector3(cos(rel) * radius, sin(rel) * radius, height)


## Two-bone solve in 3D: returns [elbow, reached end]. `pole` says which way the joint bends.
func _ik(root: Vector3, target: Vector3, upper: float, lower: float, pole: Vector3) -> PackedVector3Array:
	var span: Vector3 = target - root
	var reach: float = clampf(span.length(), absf(upper - lower) + 0.05, upper + lower - 0.05)
	var dir: Vector3 = span.normalized() if span.length() > 0.001 else Vector3.DOWN
	var along: float = (upper * upper - lower * lower + reach * reach) / (2.0 * reach)
	var bulge: float = sqrt(maxf(upper * upper - along * along, 0.0))
	var bend: Vector3 = pole - dir * pole.dot(dir)
	bend = bend.normalized() if bend.length() > 0.001 else Vector3.UP
	return PackedVector3Array([root + dir * along + bend * bulge, root + dir * reach])


func update_rig(delta: float, velocity: Vector2, heading: float, aim: float) -> void:
	_time += delta
	_elapsed += delta
	_heading = heading
	_aim = aim
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	_agitation = move_toward(_agitation, 0.0, delta * 2.5)
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	_pose_step(t)
	var breath: float = sin(_time * TAU / 1.9) * 0.7
	_sway += Vector3(sin(_time * 43.0), cos(_time * 31.0), 0.0) * _agitation * 1.2
	_hip = Vector3(-5.0 + _lean * 0.25, 0.0, maxf(9.0, 17.0 - _sag * 0.55)) + _sway * 0.5
	_chest = Vector3(1.0 + _lean * 0.6, 0.0, maxf(13.0, 31.0 - _sag + breath)) + _sway
	_head = Vector3(8.0 + _lean * 0.9, 0.0, maxf(19.0, 44.0 - _sag - _head_dip + breath * 0.6)) + _sway
	_sh_r = Vector3(_lean * 0.7, 15.0, maxf(13.0, 38.0 - _sag)) + _sway
	_sh_l = Vector3(_lean * 0.7, -15.0, maxf(13.0, 38.0 - _sag)) + _sway
	var moving: int = 0
	for i: int in 2:
		_update_planted(_legs[i], _leg_rest(i), delta, velocity, _step_time, 7.0, 4.0, false, moving)
		moving += int(_legs[i].stepping)
		if _pose == Pose.DEAD:
			var kneel: float = smoothstep(0.0, 0.3, t)
			_legs[i].foot = _legs[i].pose_from.lerp(global_position + _project(-6.0, (-1.0 if i == 0 else 1.0) * 9.0, 0.0), kneel)
			_legs[i].lift = 0.0
	if not _fist_free:
		_update_planted(_knuckle, global_position + _project(REST_FIST.x, REST_FIST.y, 0.0), delta, velocity, _step_time * 1.05, 9.0, 6.0, true, moving)
	else:
		_knuckle.foot = global_position + _p(Vector3(_fist.x, _fist.y, 0.0))
		_knuckle.stepping = false
	_ready_geo = true
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		_hips[i] = Vector3(-4.0 + _lean * 0.1, side * 7.0, _hip.z) + _sway * 0.3
		_feet3[i] = _frame(_legs[i].foot - global_position) + Vector3(0.0, 0.0, _legs[i].lift)
		_knees[i] = _ik(_hips[i], _feet3[i], LEG_UPPER, LEG_LOWER, Vector3(1.0, side * 0.25, 0.7))[0]
	var goal: Vector3 = _fist_goal
	if not _fist_free:
		goal = _frame(_knuckle.foot - global_position) + Vector3(0.0, 0.0, _knuckle.lift)
	_fist_pos = goal if _fist_snap else _fist_pos.lerp(goal, 1.0 - exp(-_fist_rate * delta))
	var solved: PackedVector3Array = _ik(_sh_r, _fist_pos, ARM_UPPER, ARM_LOWER, Vector3(-0.35, 1.0, 0.9))
	_elbow = solved[0]
	_fist = solved[1]
	_update_strands(delta, t)
	if _pose == Pose.DEAD and not _arm_broken and t >= BREAK_AT:
		_break_arm()
	_alpha = 1.0 - pow(smoothstep(0.72, 1.0, t), 1.5) if _pose == Pose.DEAD else 1.0
	_body.queue_redraw()
	_glow.queue_redraw()
	queue_redraw()


func _set_fist(goal: Vector3, rate: float = 14.0, snap: bool = false) -> void:
	_fist_free = true
	_fist_goal = goal
	_fist_rate = rate
	_fist_snap = snap


func _pose_step(t: float) -> void:
	_charge = 0.0
	_exposed = 0.0
	_lean = 0.0
	_sag = 0.0
	_head_dip = 0.0
	_stance = 1.0
	_leg_f = [-2.0, 2.0]
	_step_time = 0.3
	_sway = Vector3.ZERO
	_fist_free = false
	_fist_snap = false
	_fist_rate = 24.0
	match _pose:
		Pose.IDLE:
			_lean = sin(_time * 0.8) * 0.8
			_sag = 2.0
			_exposed = 0.12
		Pose.NOTICE:
			var k: float = sin(t * PI)
			_sag = 3.0 + 3.0 * k
			_head_dip = 5.0 * k
			_charge = 0.35 * k
			_set_fist(REST_FIST.lerp(Vector3(8.0, 20.0, 26.0), k), 12.0)
		Pose.MOVE:
			_lean = 2.5
			_sag = 2.0 + absf(sin(_time * 3.1)) * 1.8
			_sway = Vector3(0.0, sin(_time * 3.1) * 1.4, 0.0)
			_exposed = 0.12
		Pose.SLAM_WINDUP:
			var raise: float = smoothstep(0.0, 0.62, t)
			var tremble: float = 0.25 + 1.5 * smoothstep(0.55, 1.0, t)
			_lean = -6.0 * raise
			_sag = 2.0 + 3.0 * raise
			_head_dip = 2.0 * raise
			_charge = smoothstep(0.1, 0.9, t)
			_stance = 1.0 + 0.4 * raise
			_sway = Vector3(sin(_time * 41.0), cos(_time * 37.0), 0.0) * 0.35 * tremble * raise
			_set_fist(REST_FIST.lerp(OVERHEAD, raise) + Vector3(sin(_time * 47.0), cos(_time * 39.0), sin(_time * 53.0)) * tremble * raise, 0.0, true)
		Pose.SLAM:
			var e: float = pow(clampf(t / slam_hit_frac, 0.0, 1.0), 2.2)
			_lean = -6.0 + 17.0 * e
			_sag = 5.0 + 7.0 * e
			_charge = 1.0
			_stance = 1.4
			_set_fist(OVERHEAD.lerp(IMPACT, e) + Vector3(0.0, 0.0, 8.0 * sin(e * PI)), 0.0, true)
		Pose.SLAM_RECOVER:
			var wrench: float = smoothstep(0.7, 1.0, t)
			_lean = lerpf(11.0, 5.0, wrench)
			_sag = lerpf(12.0, 7.0, wrench)
			_head_dip = 3.0 + 4.0 * sin(t * 9.0) * (1.0 - wrench)
			_stance = 1.4
			_charge = 0.5 * (1.0 - t)
			_exposed = 0.55
			_sway = Vector3(sin(_time * 29.0), cos(_time * 23.0), 0.0) * 0.5 * wrench
			_set_fist(IMPACT + Vector3(sin(_time * 55.0) * wrench * 1.2, 0.0, -1.0 + 15.0 * wrench), 0.0, true)
		Pose.RUSH_WINDUP:
			var k: float = smoothstep(0.0, 0.9, t)
			_lean = 8.0 * k
			_sag = 9.0 * k
			_head_dip = 6.0 * k
			_charge = k
			_stance = 1.2
			_leg_f = [-8.0, 8.0]
			_sway = Vector3(sin(_time * 61.0), cos(_time * 53.0), 0.0) * 0.7 * k
			_set_fist(REST_FIST.lerp(Vector3(20.0, 22.0, 3.0), k), 10.0)
		Pose.RUSH:
			_lean = 13.0
			_sag = 12.0
			_head_dip = 7.0
			_charge = 1.0
			_step_time = 0.13
			_leg_f = [-4.0, 4.0]
			_sway = Vector3(0.0, sin(_time * 24.0) * 1.2, 0.0)
		Pose.RUSH_RECOVER:
			_lean = lerpf(13.0, 0.0, smoothstep(0.0, 0.8, t))
			_sag = lerpf(12.0, 3.0, t)
			_head_dip = lerpf(7.0, 0.0, t)
			_charge = 1.0 - t
			_exposed = 0.35 * (1.0 - t)
			_stance = 1.25
			_sway = Vector3(sin(_time * 21.0), 0.0, 0.0) * (1.0 - t)
		Pose.SWEEP_WINDUP:
			var k: float = smoothstep(0.0, 1.0, t)
			_lean = -3.0 * k
			_sag = 3.0 + 2.0 * k
			_charge = k
			_stance = 1.2
			_set_fist(_polar(_aim - _spin * 1.9, 36.0, 20.0), 11.0)
		Pose.SWEEP:
			_lean = 4.0 * t
			_sag = 4.0
			_charge = 1.0
			_stance = 1.2
			_set_fist(_polar(_aim - _spin * (1.9 - 2.0 * t), 36.0, lerpf(20.0, 8.0, t)), 0.0, true)
		Pose.SWEEP_RECOVER:
			_lean = lerpf(4.0, 0.0, t)
			_sag = lerpf(4.0, 2.0, t)
			_charge = 0.5 * (1.0 - t)
			_exposed = 0.3 * (1.0 - t)
			_stance = 1.2
			if t < 0.45:
				_set_fist(_polar(_aim + _spin * 0.1, 34.0, 6.0), 18.0)
		Pose.STUN:
			_lean = 8.0
			_sag = 12.0
			_head_dip = 10.0
			_stance = 1.3
			_exposed = 1.0
			_sway = Vector3(sin(_time * 3.2) * 1.4, sin(_time * 2.3) * 2.0, 0.0)
			_agitation = maxf(_agitation, 0.25)
			_set_fist(Vector3(17.0, 15.0, 0.0), 6.0)
		Pose.HURT:
			var k: float = sin(t * PI)
			_lean = -9.0 * k
			_sag = -3.0 * k
			_head_dip = -4.0 * k
			_exposed = 1.0
			_set_fist(REST_FIST + Vector3(0.0, 0.0, 14.0 * k), 16.0)
		Pose.DEAD:
			var kneel: float = smoothstep(0.0, 0.3, t)
			var collapse: float = smoothstep(0.45, 1.0, t)
			_sag = 14.0 * kneel + 14.0 * collapse
			_lean = 4.0 * kneel + 5.0 * collapse
			_head_dip = 6.0 * kneel + 6.0 * collapse
			_exposed = 1.0 - t
			_stance = 1.1
			_sway = Vector3(sin(_time * 38.0), cos(_time * 31.0), 0.0) * (1.0 - t) * 0.8


func _leg_rest(i: int) -> Vector2:
	var side: float = -1.0 if i == 0 else 1.0
	return global_position + _project(_leg_f[i], side * 9.0 * _stance, 0.0)


func _update_planted(p: Planted, rest: Vector2, delta: float, velocity: Vector2, step_time: float, trigger: float, step_lift: float, heavy: bool, busy: int) -> void:
	if not _ready_geo or p.foot == Vector2.ZERO:
		p.foot = rest
		p.pose_from = rest
	p.lift = 0.0
	if p.stepping:
		p.progress += delta / step_time
		var k: float = minf(1.0, p.progress)
		p.foot = p.from.lerp(p.to, smoothstep(0.0, 1.0, k))
		p.lift = sin(k * PI) * step_lift
		if k >= 1.0:
			p.stepping = false
			foot_landed.emit(p.foot, heavy)
	elif p.foot.distance_to(rest) > trigger and (busy < 1 or p.foot.distance_to(rest) > trigger * 3.0):
		p.from = p.foot
		p.to = rest + velocity * 0.12
		p.progress = 0.0
		p.stepping = true


## Three tendons from the left shoulder; each tip probes the ground (or grips, trails, lashes, goes limp) depending on the pose.
func _update_strands(delta: float, t: float) -> void:
	for i: int in STRANDS:
		var k: float = float(i)
		var target: Vector3 = Vector3(14.0 + k * 5.0, -(17.0 + k * 6.0), 1.0)
		target += Vector3(sin(_time * 1.3 + k * 2.1) * 4.0, cos(_time * 1.7 + k * 1.3) * 3.0, maxf(0.0, sin(_time * 2.2 + k) * 4.0))
		var rate: float = 9.0
		match _pose:
			Pose.MOVE, Pose.RUSH_RECOVER:
				target += Vector3(6.0 + sin(_time * 6.0 + k) * 2.0, 0.0, 0.0)
			Pose.NOTICE:
				target = Vector3(16.0 + k * 4.0, -(12.0 + k * 7.0), 12.0 + sin(t * PI) * 6.0 + sin(_time * 9.0 + k) * 2.0)
			Pose.SLAM_WINDUP, Pose.RUSH_WINDUP:
				target = Vector3(10.0 + k * 5.0, -(18.0 + k * 4.0), 0.0) + Vector3(sin(_time * 52.0 + k), cos(_time * 47.0 + k), 0.0) * 0.5 * _charge
			Pose.SLAM, Pose.SLAM_RECOVER:
				target = Vector3(24.0 + k * 3.0, -(10.0 + k * 5.0), 0.0)
			Pose.RUSH:
				target = Vector3(-16.0 - k * 6.0, -(10.0 + k * 6.0), 18.0 + k * 3.0 + sin(_time * 30.0 + k) * 2.0)
				rate = 6.0
			Pose.SWEEP_WINDUP, Pose.SWEEP:
				target = _polar(_aim + (k - 1.0) * 0.35 - (1.0 - t) * _spin * 0.6, 30.0 + k * 7.0, 8.0)
				rate = 16.0
			Pose.SWEEP_RECOVER:
				rate = 6.0
			Pose.STUN, Pose.DEAD:
				target = Vector3(2.0 + k * 4.0, -(18.0 + k * 5.0), 0.0)
				rate = 5.0
			Pose.HURT:
				target = Vector3(4.0, -(10.0 + k * 5.0), 22.0)
				rate = 20.0
		if _tips[i] == Vector3.ZERO:
			_tips[i] = target
		_tips[i] = _tips[i].lerp(target, 1.0 - exp(-rate * delta))
		var root: Vector3 = _sh_l + Vector3(0.0, -k * 1.5, 1.0 - k)
		var tip: Vector3 = _tips[i]
		var slack: float = 1.0 - clampf(_charge * 0.7, 0.0, 0.8)
		if _pose in [Pose.DEAD, Pose.STUN]:
			slack = 1.0
		var c1: Vector3 = root.lerp(tip, 0.33) + Vector3(0.0, -4.0, 9.0 * slack)
		var c2: Vector3 = root.lerp(tip, 0.7) + Vector3(0.0, 0.0, 5.0 * slack)
		var pts: PackedVector2Array = PackedVector2Array()
		pts.resize(STRAND_POINTS)
		for n: int in STRAND_POINTS:
			var u: float = float(n) / float(STRAND_POINTS - 1)
			var w: float = 1.0 - u
			var point: Vector3 = root * w * w * w + c1 * 3.0 * w * w * u + c2 * 3.0 * w * u * u + tip * u * u * u
			point += Vector3(0.0, sin(_time * 1.7 + k + u * 5.0) * sin(u * PI) * 0.9, 0.0)
			pts[n] = _p(point)
		_strands[i] = pts
		_strand_depth[i] = _depth(root.lerp(tip, 0.55))


func _break_arm() -> void:
	_arm_broken = true
	_debris.clear()
	var joints: Array[Vector3] = [_sh_r + Vector3(0, 2, 2), _elbow, _elbow.lerp(_fist, 0.5), _fist, _fist + Vector3(3, 2, 2), _sh_r.lerp(_elbow, 0.5)]
	for n: int in joints.size():
		var j: Vector3 = joints[n]
		var out: Vector2 = Vector2.from_angle(_rng.randf() * TAU)
		_debris.append({
			"ground": _ang(j.x, j.y, 0.0, _heading),
			"height": j.z,
			"velocity": out * _rng.randf_range(40.0, 110.0) * Vector2(1.0, SQUASH),
			"rise": _rng.randf_range(30.0, 90.0),
			"radius": 5.5 - float(n % 3) * 1.1 + (2.5 if n == 3 else 0.0),
			"seed": _rng.randi() % 997,
		})


# --- pixel helpers -------------------------------------------------------------------------------------------------


func _tint(color: Color, alpha: float = 1.0) -> Color:
	return Color(color.lerp(Color.WHITE, _flash * 0.85), _alpha * alpha)


## Fills a convex-ish polygon in whole pixel rows, so the silhouette stays hard-edged and the draw never fails on degenerate input.
func _fill(canvas: Node2D, points: PackedVector2Array, color: Color) -> void:
	var low: float = INF
	var high: float = -INF
	for point: Vector2 in points:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	for y: int in range(floori(low), ceili(high) + 1):
		var scan: float = float(y) + 0.5
		var left: float = INF
		var right: float = -INF
		for k: int in points.size():
			var a: Vector2 = points[k]
			var b: Vector2 = points[(k + 1) % points.size()]
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
				var x: float = a.x + (scan - a.y) / (b.y - a.y) * (b.x - a.x)
				left = minf(left, x)
				right = maxf(right, x)
		if left <= right:
			var from_x: float = roundf(left)
			canvas.draw_rect(Rect2(from_x, float(y), maxf(1.0, roundf(right) - from_x), 1.0), color)


func _blob(canvas: Node2D, center: Vector2, rx: float, ry: float, seed_value: int, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in 9:
		var angle: float = TAU * float(k) / 9.0 + 0.4
		var jitter: float = 0.86 + 0.2 * fposmod(sin(float(seed_value * 17 + k) * 12.9898) * 43758.5453, 1.0)
		points.append(center + Vector2(cos(angle) * rx * jitter, sin(angle) * ry * jitter))
	_fill(canvas, points, color)


func _oval(canvas: Node2D, center: Vector2, radius: Vector2, color: Color) -> void:
	for y: int in range(-ceili(radius.y), ceili(radius.y) + 1):
		var q: float = float(y) / maxf(radius.y, 0.01)
		if absf(q) > 1.0:
			continue
		var w: int = floori(sqrt(1.0 - q * q) * radius.x)
		canvas.draw_rect(Rect2((center + Vector2(-w, y)).round(), Vector2(w * 2 + 1, 1)), color)


func _seg(canvas: Node2D, from: Vector2, to: Vector2, width_from: float, width_to: float, color: Color) -> void:
	var count: int = maxi(1, ceili(from.distance_to(to) * 1.5))
	for i: int in count + 1:
		var k: float = float(i) / float(count)
		var width: float = maxf(1.0, roundf(lerpf(width_from, width_to, k)))
		canvas.draw_rect(Rect2(from.lerp(to, k).round() - Vector2.ONE * floorf(width * 0.5), Vector2.ONE * width), color)


func _halo(canvas: Node2D, point: Vector2, color: Color, strength: float, bloom: float = 0.5) -> void:
	VoidGlow.halo(canvas, point, color, strength * _alpha, bloom)


## A basalt boulder like the world's rocks: dark body, mid face, lit cap, a chip of highlight and a cold rim.
func _rock(canvas: Node2D, center: Vector2, r: float, seed_value: int) -> void:
	_blob(canvas, center, r + 1.2, (r + 1.2) * 0.9, seed_value, _tint(OUTLINE))
	_blob(canvas, center, r, r * 0.9, seed_value, _tint(ROCK0))
	_blob(canvas, center + Vector2(-r * 0.12, -r * 0.16), r * 0.82, r * 0.72, seed_value + 1, _tint(ROCK1))
	_blob(canvas, center + Vector2(-r * 0.3, -r * 0.38), r * 0.52, r * 0.4, seed_value + 2, _tint(ROCK2))
	canvas.draw_rect(Rect2((center + Vector2(-r * 0.5, -r * 0.62)).round(), Vector2(2, 1)), _tint(ROCK3))
	canvas.draw_rect(Rect2((center + Vector2(-r * 0.7, -r * 0.3)).round(), Vector2(1, 2)), _tint(RIM))


## A horn plate: outline, body, lit cap and a rim line.
func _plate(canvas: Node2D, center: Vector2, rx: float, ry: float, seed_value: int, lit: Color = HIGH) -> void:
	_blob(canvas, center, rx + 1.2, ry + 1.2, seed_value, _tint(OUTLINE))
	_blob(canvas, center, rx, ry, seed_value, _tint(MID))
	_blob(canvas, center + Vector2(-rx * 0.2, -ry * 0.28), rx * 0.66, ry * 0.5, seed_value + 3, _tint(lit))
	canvas.draw_rect(Rect2((center + Vector2(-rx * 0.55, -ry * 0.62)).round(), Vector2(maxf(2.0, rx * 0.6), 1)), _tint(RIM))


func _spike(canvas: Node2D, base: Vector2, tip: Vector2, width: float, color: Color) -> void:
	var across: Vector2 = (tip - base).orthogonal().normalized() * width * 0.5
	_fill(canvas, PackedVector2Array([base - across * 1.4, base + across * 1.4, tip + (tip - base).normalized() * 1.2]), _tint(OUTLINE))
	_fill(canvas, PackedVector2Array([base - across, base + across, tip]), _tint(color))


# --- the body, depth sorted ----------------------------------------------------------------------------------------


func _add(depth: float, draw_part: Callable) -> void:
	_parts.append({"d": depth, "f": draw_part})


func _draw_main() -> void:
	if not _ready_geo:
		return
	_parts.clear()
	_collect()
	_parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.d) < float(b.d))
	for part: Dictionary in _parts:
		(part.f as Callable).call()


func _collect() -> void:
	for i: int in 2:
		_add((_depth(_hips[i]) + _depth(_feet3[i])) * 0.5 - 0.1, _draw_leg.bind(i))
	_add(0.0, _draw_torso)
	_add(_depth(Vector3(-10.0, 0.0, 0.0)) - 0.3, _draw_back)
	_add(_depth(_sh_l) + 0.2, _draw_left_shoulder)
	_add(_depth(_head) + 0.6, _draw_head)
	for n: int in 5:
		var phi: float = (float(n) - 2.0) * 0.62
		var pos: Vector3 = Vector3(_chest.x + 11.0 * cos(phi), 13.0 * sin(phi), _chest.z + 4.0 - absf(phi) * 2.5)
		_add(_depth(pos) + 0.8, _draw_collar.bind(pos, 5.4, 6.8, n))
	for n: int in 3:
		var phi: float = (float(n) - 1.0) * 0.8
		var pos: Vector3 = Vector3(_chest.x + 13.0 * cos(phi), 16.0 * sin(phi), _chest.z - 5.0)
		_add(_depth(pos) + 0.7, _draw_collar.bind(pos, 7.0, 7.0, n + 7))
	for i: int in STRANDS:
		_add(_strand_depth[i], _draw_strand.bind(i))
	if not _arm_broken:
		_collect_arm()
	else:
		_add(_depth(_sh_r) + 0.1, _draw_stump)
		for chunk: Dictionary in _debris:
			var spot: Vector2 = _debris_spot(chunk)
			_add(_depth(_frame(Vector2(chunk.ground))) + 0.2 + spot.y * 0.0, _draw_chunk.bind(chunk))


func _collect_arm() -> void:
	# Overlapping boulders so the club reads as one crude limb: a thick upper arm, a heavier forearm and a huge fist with three knuckle stones.
	for n: int in 5:
		var k: float = float(n) / 4.0
		_add_arm_rock(_sh_r.lerp(_elbow, k), lerpf(8.0, 7.2, k) + float(n % 2) * 0.8, n)
	for n: int in 6:
		var k: float = float(n + 1) / 6.0
		_add_arm_rock(_elbow.lerp(_fist, k), lerpf(8.2, 9.6, k) - float(n % 2) * 0.7, 10 + n)
	_add(_depth(_elbow) + 0.5, _draw_elbow_spike)
	for n: int in 3:
		var knuckle: Vector3 = _fist + Vector3(6.5, (float(n) - 1.0) * 5.5, 1.0 - absf(float(n) - 1.0) * 1.5)
		_add_arm_rock(knuckle, 5.0, 20 + n, 0.55)
	_add_arm_rock(_fist + Vector3(0, 0, 1), 11.0, 30, 0.45)


func _add_arm_rock(pos: Vector3, radius: float, seed_value: int, bias: float = 0.3) -> void:
	_add(_depth(pos) + bias, _draw_arm_rock.bind(pos, radius, seed_value))


func _draw_arm_rock(pos: Vector3, radius: float, seed_value: int) -> void:
	_rock(_body, _p(pos).round(), radius, seed_value)


func _draw_elbow_spike() -> void:
	var elbow: Vector2 = _p(_elbow)
	var out: Vector2 = _p(_elbow + Vector3(-3.0, 8.0, 7.0)) - elbow
	_spike(_body, elbow + out * 0.35, elbow + out * 1.25, 6.0, ROCK2)
	var back: Vector2 = _p(_elbow + Vector3(-9.0, 2.0, 3.0)) - elbow
	_spike(_body, elbow + back * 0.3, elbow + back * 1.1, 5.0, ROCK1)


func _draw_stump() -> void:
	var shoulder: Vector2 = _p(_sh_r)
	_blob(_body, shoulder, 8.5, 7.5, 71, _tint(OUTLINE))
	_blob(_body, shoulder, 7.0, 6.0, 72, _tint(ROCK0))
	_blob(_body, shoulder + Vector2(0, 2), 4.5, 3.5, 73, _tint(DARK))
	for n: int in 4:
		_spike(_body, shoulder + Vector2(n * 3 - 4, 2), shoulder + Vector2(n * 3 - 5, -4 - (n % 2) * 3), 3.0, ROCK2)


func _debris_spot(chunk: Dictionary) -> Vector2:
	var tau: float = maxf(0.0, _elapsed - BREAK_AT * _duration)
	var run: float = (1.0 - exp(-3.0 * tau)) / 3.0
	var height: float = maxf(0.0, float(chunk.height) + float(chunk.rise) * tau - 110.0 * tau * tau)
	return Vector2(chunk.ground) + Vector2(chunk.velocity) * run + Vector2(0.0, -height)


func _draw_chunk(chunk: Dictionary) -> void:
	_rock(_body, _debris_spot(chunk).round(), float(chunk.radius), int(chunk.seed))


func _draw_leg(i: int) -> void:
	var hip: Vector2 = _p(_hips[i])
	var knee: Vector2 = _p(_knees[i])
	var foot: Vector2 = _p(_feet3[i])
	_seg(_body, hip, knee, 10.0, 9.0, _tint(OUTLINE))
	_seg(_body, knee, foot, 9.0, 7.0, _tint(OUTLINE))
	_seg(_body, hip, knee, 8.0, 7.0, _tint(FLESH))
	_seg(_body, knee, foot, 7.0, 5.0, _tint(FLESH))
	_seg(_body, hip + Vector2(-2, -1), knee + Vector2(-2, -1), 2.0, 2.0, _tint(HIGH))
	_seg(_body, hip + Vector2(-3, -1), knee + Vector2(-3, 0), 1.0, 1.0, _tint(RIM, 0.8))
	_blob(_body, knee + Vector2(0, -1), 4.6, 4.2, 40 + i, _tint(OUTLINE))
	_blob(_body, knee + Vector2(-0.5, -1.5), 3.6, 3.2, 44 + i, _tint(HIGH))
	var ground: Vector2 = _p(Vector3(_feet3[i].x, _feet3[i].y, 0.0))
	_oval(_body, ground + Vector2(1, 0), Vector2(7.5, 4.0), _tint(OUTLINE))
	_oval(_body, ground + Vector2(1, -0.5), Vector2(6.5, 3.2), _tint(DARK))
	_oval(_body, ground + Vector2(-0.5, -1.5), Vector2(4.0, 1.6), _tint(MID))


func _draw_torso() -> void:
	var hip: Vector2 = _p(_hip)
	var chest: Vector2 = _p(_chest)
	var swell: float = _charge * 1.5
	_oval(_body, hip, Vector2(10, 8), _tint(OUTLINE))
	_oval(_body, hip + Vector2(0, -0.5), Vector2(9, 7), _tint(FLESH))
	_oval(_body, hip + Vector2(-2, -2), Vector2(5.5, 3.5), _tint(MID))
	_seg(_body, hip, chest, 17.0, 20.0, _tint(OUTLINE))
	_seg(_body, hip, chest, 15.0, 18.0, _tint(FLESH))
	_oval(_body, chest, Vector2(17.0 + swell, 14.0 + swell * 0.5), _tint(OUTLINE))
	_oval(_body, chest + Vector2(0, -0.5), Vector2(16.0 + swell, 13.0 + swell * 0.5), _tint(FLESH))
	_oval(_body, chest + Vector2(-3, -4), Vector2(11, 7), _tint(MID))
	_oval(_body, chest + Vector2(-5, -6), Vector2(6, 3), _tint(HIGH))
	_oval(_body, chest + Vector2(-7, -11), Vector2(7, 1), _tint(RIM))
	_oval(_body, hip + Vector2(-3, -6), Vector2(4, 1), _tint(RIM))
	for n: int in 2:
		var fold: Vector2 = chest + Vector2(-9 + n * 9, 5 + n)
		_seg(_body, fold, fold + Vector2(6, 2), 1.0, 1.0, _tint(DARK))
		_body.draw_rect(Rect2(fold.round(), Vector2.ONE), _tint(RIM))


func _draw_back() -> void:
	var c: Vector2 = _p(Vector3(-10.0 + _lean * 0.5, 0.0, 36.0 - _sag)).round()
	_oval(_body, c, Vector2(16, 12), _tint(OUTLINE))
	_oval(_body, c + Vector2(0, -0.5), Vector2(15, 11), _tint(MID))
	var open: float = 3.0 + _exposed * 4.0
	_body.draw_rect(Rect2((c + Vector2(-open * 0.5 - 1.0, -9)).round(), Vector2(open + 2.0, 19)), _tint(OUTLINE))
	_body.draw_rect(Rect2((c + Vector2(-open * 0.5, -8)).round(), Vector2(open, 17)), _tint(DARK))
	for side: float in [-1.0, 1.0]:
		var hump: Vector2 = c + Vector2(side * 9.5, -2)
		_plate(_body, hump, 7.5, 9.5, 61 + int(side), HIGH)
		_spike(_body, hump + Vector2(side * 1, -6), hump + Vector2(side * 3, -14), 5.0, MID)
		_body.draw_rect(Rect2((c + Vector2(side * (open * 0.5 + 0.5) - 0.5, -8)).round(), Vector2(1, 17)), _tint(RIM, 0.8))


func _draw_left_shoulder() -> void:
	var s: Vector2 = _p(_sh_l)
	_plate(_body, s + Vector2(0, -2), 8.5, 7.5, 81, HIGH)
	_spike(_body, s + Vector2(-2, -7), s + Vector2(-4, -17), 6.0, MID)
	_spike(_body, s + Vector2(3, -6), s + Vector2(6, -13), 5.0, MID)


func _draw_collar(pos: Vector3, rx: float, ry: float, seed_value: int) -> void:
	var c: Vector2 = _p(pos)
	_plate(_body, c, rx, ry, 90 + seed_value, HIGH if seed_value < 7 else MID)
	_body.draw_rect(Rect2((c + Vector2(-rx * 0.4, ry * 0.55)).round(), Vector2(maxf(2.0, rx * 0.8), 1)), _tint(DARK))


func _eye_visibility(index: int) -> float:
	var side: float = (float(index) - 1.0) * 4.4
	var depth: float = sin(_heading) * 5.5 + cos(_heading) * side
	return smoothstep(-1.5, 1.2, depth)


func _eye_point(index: int) -> Vector2:
	return _p(Vector3(_head.x + 5.5, (float(index) - 1.0) * 4.4, _head.z + 2.5))


func _draw_head() -> void:
	var h: Vector2 = _p(_head)
	_oval(_body, h, Vector2(8.5, 7.5), _tint(OUTLINE))
	_oval(_body, h + Vector2(0, -0.5), Vector2(7.5, 6.5), _tint(DARK))
	var front: Vector2 = _p(_head + Vector3(4.0, 0.0, 0.0)) - h
	_plate(_body, h + front * 0.9 + Vector2(0, -1), 5.5, 5.2, 99, MID)
	for n: int in 3:
		var visibility: float = _eye_visibility(n)
		if visibility > 0.3:
			var e: Vector2 = _eye_point(n)
			_body.draw_rect(Rect2((e + Vector2(-2, -1)).round(), Vector2(5, 3)), _tint(OUTLINE, visibility))
	for side: float in [-1.0, 1.0]:
		var base: Vector2 = _p(_head + Vector3(-2.0, side * 5.0, 4.0))
		var horn: Vector2 = _p(_head + Vector3(-9.0, side * 8.0, 8.0 + _charge * 3.0))
		_spike(_body, base, horn, 4.0, MID)


func _draw_strand(i: int) -> void:
	var pts: PackedVector2Array = _strands[i]
	if pts.is_empty():
		return
	for pass_index: int in 2:
		for n: int in pts.size():
			var u: float = float(n) / float(pts.size() - 1)
			var width: int = maxi(1, roundi(lerpf(4.2, 1.0, u)))
			if pass_index == 0:
				_body.draw_rect(Rect2(pts[n].round() - Vector2.ONE * (floorf(width * 0.5) + 1.0), Vector2.ONE * (width + 2)), _tint(OUTLINE))
			else:
				_body.draw_rect(Rect2(pts[n].round() - Vector2.ONE * floorf(width * 0.5), Vector2.ONE * width), _tint(MID if u > 0.5 else FLESH))
				if n % 3 == 0 and u < 0.85:
					_body.draw_rect(Rect2(pts[n].round() - Vector2(1, 1), Vector2.ONE), _tint(RIM))
	var tip: Vector2 = pts[pts.size() - 1]
	var dir: Vector2 = (tip - pts[pts.size() - 4]).normalized()
	for spread: float in [-0.7, 0.0, 0.7]:
		var claw: Vector2 = tip + dir.rotated(spread) * 4.5
		_seg(_body, tip, claw, 2.0, 1.0, _tint(OUTLINE))
		_body.draw_rect(Rect2(claw.round(), Vector2.ONE), _tint(MID))


# --- the light -----------------------------------------------------------------------------------------------------


func _back_visibility() -> float:
	return 1.0 - smoothstep(-0.7, 0.9, sin(_heading))


func _hidden(point: Vector2, depth: float) -> bool:
	return depth < -3.0 and point.distance_to(_p(_chest)) < 13.0


func _rate() -> float:
	return 0.8 + _charge * 1.6 + _exposed * 0.5


## One vein along body-frame points. The heartbeat runs outward from the core along it; on the torso a point is dark where the body covers it.
func _vein(path: Array[Vector3], strength: float, start: float = 0.0, on_torso: bool = true) -> float:
	var travelled: float = start
	for n: int in path.size() - 1:
		var from: Vector3 = path[n]
		var to: Vector3 = path[n + 1]
		var steps: int = maxi(2, ceili(_p(from).distance_to(_p(to)) / 1.5))
		for k: int in steps:
			var point: Vector3 = from.lerp(to, float(k) / float(steps))
			travelled += 1.5
			var visible: float = smoothstep(-6.0, 2.0, _depth(point)) if on_torso else 1.0
			if visible > 0.02:
				var wave: float = VoidGlow.beat(_time, -travelled * 0.012, _rate())
				_halo(_glow, _p(point), VEIN_LIGHT if k % 3 == 0 else VEIN, visible * strength * 0.7 * (0.2 + 0.8 * wave), 0.15)
	return travelled


func _draw_glow() -> void:
	if not _ready_geo:
		return
	var heart: float = VoidGlow.beat(_time, 0.0, _rate())
	var strength: float = 0.55 + 0.5 * heart + _exposed * 0.3 + _charge * 0.25
	var back: float = _back_visibility()
	var core3: Vector3 = Vector3(-10.0 + _lean * 0.5, 0.0, 35.0 - _sag)
	var core: Vector2 = _p(core3)
	# The whole chest swells with violet light on the beat and while it charges.
	_oval(_glow, _p(_chest), Vector2(19, 16), Color(VEIN, _alpha * (0.008 + 0.014 * heart + 0.035 * _charge)))
	if back > 0.04:
		var length: float = 5.0 + _exposed * 4.0
		_glow.draw_rect(Rect2((core + Vector2(-4, -length - 2)).round(), Vector2(9, length * 2.0 + 5.0)), Color(VEIN, _alpha * back * 0.1 * strength))
		_glow.draw_rect(Rect2((core + Vector2(-1, -length)).round(), Vector2(3, length * 2.0 + 1.0)), Color(VEIN, _alpha * back * 0.75 * strength))
		_glow.draw_rect(Rect2((core + Vector2(0, -length * 0.8)).round(), Vector2(1, length * 1.6)), Color(CORE, _alpha * back * clampf(strength, 0.0, 1.0)))
		_halo(_glow, core, CORE, back * strength * 1.2, 1.6)
	# Veins spread from the core over the humps, down the spine and round the ribs; the pulse follows them outward.
	var z: float = 35.0 - _sag
	for side: float in [-1.0, 1.0]:
		_vein([core3, Vector3(-10.0, side * 8.0, z + 6.0), Vector3(-7.0, side * 14.0, z + 11.0), Vector3(-4.0, side * 17.0, z + 8.0)], 0.9)
		_vein([core3, Vector3(-9.0, side * 5.0, z - 8.0), Vector3(-5.0, side * 11.0, z - 14.0)], 0.7)
		_vein([Vector3(-4.0, side * 6.0, _hip.z + 2.0), Vector3(-1.0, side * 12.0, _hip.z + 9.0), Vector3(1.0 + _lean * 0.6, side * 15.0, _chest.z), Vector3(3.0 + _lean * 0.6, side * 11.0, _chest.z + 8.0)], 0.85, 14.0)
	_vein([core3, Vector3(-11.0, 0.0, z + 9.0), Vector3(-8.0, 0.0, z + 16.0)], 0.8)
	_vein([core3, Vector3(-9.0, 0.0, z - 10.0), Vector3(-6.0, 0.0, _hip.z + 1.0)], 0.8)
	for i: int in 2:
		_vein([_hips[i], _knees[i], _feet3[i] + Vector3(0, 0, 1)], 0.6, 20.0)
	# The club: core -> shoulder -> elbow -> fist, and cracks that open along each boulder.
	if not _arm_broken:
		var travelled: float = _vein([core3, Vector3(-8.0, 9.0, z + 6.0), _sh_r + Vector3(0, 0, 4)], 1.0)
		var arm: Array[Vector3] = [_sh_r + Vector3(0, 0, 4), _elbow + Vector3(0, 0, 3), _fist + Vector3(0, 0, 3)]
		for n: int in 2:
			var from: Vector3 = arm[n]
			var to: Vector3 = arm[n + 1]
			var steps: int = maxi(2, ceili(_p(from).distance_to(_p(to)) / 1.5))
			for k: int in steps:
				var point: Vector3 = from.lerp(to, float(k) / float(steps))
				travelled += 1.5
				var screen: Vector2 = _p(point)
				if not _hidden(screen, _depth(point)):
					var wave: float = VoidGlow.beat(_time, -travelled * 0.012, _rate())
					if k % 2 == 0:
						_halo(_glow, screen, VEIN_LIGHT if k % 4 == 0 else VEIN, (0.3 + 0.7 * wave) * (0.9 + _charge * 0.3), 0.2)
					if k % 5 == 2:
						for branch: float in [-1.0, 1.0]:
							_halo(_glow, screen + Vector2(branch * 3.0, branch * 2.0 - 1.0), VEIN, (0.25 + 0.6 * wave) * 0.7, 0.0)
		var fist: Vector2 = _p(_fist)
		var punch: float = 0.5 + 0.5 * heart + _charge * 0.4
		for n: int in 3:
			_halo(_glow, fist + Vector2(-5 + n * 5, -4 + (n % 2) * 5), VEIN_LIGHT, punch, 0.8)
		_halo(_glow, fist + Vector2(1, -2), CORE, punch * 1.1, 1.2)
		_halo(_glow, _p(_elbow) + Vector2(1, -2), VEIN_LIGHT, punch * 0.9, 0.8)
		for spike: Vector2 in [Vector2(2, -8), Vector2(-7, -4)]:
			_halo(_glow, _p(_elbow) + spike, CORE, 0.5 + 0.4 * heart, 0.6)
	# Seams under the collar plates, shoulder and back spikes, horn tips: the armour glows through its joints.
	for n: int in 5:
		var phi: float = (float(n) - 2.0) * 0.62
		var pos: Vector3 = Vector3(_chest.x + 11.0 * cos(phi), 13.0 * sin(phi), _chest.z + 4.0 - absf(phi) * 2.5)
		var seen: float = smoothstep(-2.0, 4.0, _depth(pos))
		for k: int in 5:
			_halo(_glow, _p(pos) + Vector2(-2 + k, 5 + (1 if k % 2 == 0 else 0)), VEIN_LIGHT, seen * VoidGlow.pulse(_time, -float(n) * 0.04, _rate(), 0.3), 0.3)
	var tips: Array[Vector3] = [_sh_l + Vector3(0, -2, 10), _sh_l + Vector3(0, 4, 6), Vector3(-10.0 + _lean * 0.5, -13.0, z + 17.0), Vector3(-10.0 + _lean * 0.5, 13.0, z + 17.0)]
	for tip: Vector3 in tips:
		_halo(_glow, _p(tip), VEIN_LIGHT, smoothstep(-6.0, 2.0, _depth(tip)) * (0.55 + 0.45 * heart), 0.7)
	for side: float in [-1.0, 1.0]:
		var horn: Vector3 = _head + Vector3(-9.0, side * 8.0, 8.0 + _charge * 3.0)
		_halo(_glow, _p(horn), VEIN_LIGHT, smoothstep(-6.0, 2.0, _depth(horn)) * (0.6 + 0.4 * heart), 0.7)
	# Eyes: three magenta slits with a wide bloom, flaring when it charges.
	for n: int in 3:
		var visibility: float = _eye_visibility(n)
		if visibility > 0.05:
			var eye: Vector2 = _eye_point(n)
			var bright: float = (0.95 + _charge * 0.4) * visibility
			_halo(_glow, eye, EYE, bright, 1.6)
			_glow.draw_rect(Rect2((eye + Vector2(-1, 0)).round(), Vector2(3, 1)), Color(EYE.lerp(CORE, 0.35), _alpha * minf(1.0, bright)))
			_glow.draw_rect(Rect2((eye + Vector2(-3, -1)).round(), Vector2(7, 3)), Color(EYE, _alpha * bright * 0.14))
			if _charge > 0.2:
				_glow.draw_rect(Rect2(eye.round(), Vector2.ONE), Color(CORE, _alpha * _charge * visibility))
	for i: int in STRANDS:
		var pts: PackedVector2Array = _strands[i]
		if pts.is_empty():
			continue
		for n: int in range(2, pts.size() - 1, 2):
			var wave: float = VoidGlow.beat(_time, -float(n) * 0.014 - float(i) * 0.05, _rate())
			_halo(_glow, pts[n], VEIN_LIGHT if n % 4 == 0 else VEIN, 0.35 + 0.65 * wave + _charge * 0.2, 0.4)
		_halo(_glow, pts[pts.size() - 1], CORE, 0.8 + _charge * 0.4, 1.0)
	_draw_cracks()


## After the slam: jagged violet cracks run out of the fist across the ground and fade.
func _draw_cracks() -> void:
	var age: float = _time - _impact_time
	if _pose not in [Pose.SLAM_RECOVER, Pose.RUSH_RECOVER] or age < 0.0 or age > 1.0 or _pose != Pose.SLAM_RECOVER:
		return
	var origin: Vector2 = _ang(IMPACT.x, IMPACT.y, 0.0, _heading)
	var fade: float = 1.0 - age
	for i: int in 5:
		var angle: float = _heading + (float(i) - 2.0) * 0.48
		var length: float = (18.0 + float(i % 3) * 8.0) * minf(1.0, age / 0.12)
		var previous: Vector2 = origin
		for step: int in range(1, int(length / 3.0) + 1):
			var distance: float = float(step) * 3.0
			var wobble: float = sin(float(step) * 2.3 + float(i) * 1.7) * 1.4
			var dir: Vector2 = Vector2.from_angle(angle)
			var point: Vector2 = origin + Vector2(dir.x, dir.y * SQUASH) * distance + Vector2(-dir.y, dir.x * SQUASH) * wobble
			_seg(_glow, previous, point, 3.0, 2.0, Color(VEIN, _alpha * fade * 0.18))
			_seg(_glow, previous, point, 1.0, 1.0, Color(VEIN_LIGHT, _alpha * fade * 0.7))
			previous = point
		_halo(_glow, previous, CORE, fade * 0.8)
	_halo(_glow, origin, CORE, minf(1.0, fade * 1.4))


func _draw() -> void:
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.5, 0.45))
	draw_circle(Vector2.ZERO, 13, Color(0.025, 0.015, 0.04, _alpha * 0.32))
