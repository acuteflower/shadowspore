class_name SkyCleaverRig
extends Node2D
## Mornath, the Sky Cleaver: once a consecrated sun eagle of the High Spire, now a raptor of void-pitch and basalt blades.
## 100 % procedural pixel geometry like the crusher (no sprites, no rotated rasters): the bird is built in its own frame
## (forward, side, up), tilted by pitch and bank into the body frame, projected 3/4 (`SQUASH`) and depth-sorted part by part.
## Wings are a two-segment arm with 6 primary and 5 secondary basalt blades on stretchy membranes; every blade follows
## its arm through a low-pass filter, so the tips lag and bend like feathers. Tendrils are verlet chains in world space,
## dragged by the real airflow. Black flesh and basalt stay world-lit (`Body`); eyes, veins, runes and the core are the additive `Glow`.

signal wing_beat(strong: bool)
signal bead_dropped(ground_point: Vector2)

enum Pose { PERCHED, TAKEOFF, FLYING, HOVER, LANDING, STAGGER, CRASHED, DEAD, SPENT, DOWNED, JUDGE }

## Everything a pose can ask for; poses fill a target array, the rig blends towards it.
enum Q {
	CX, CY, CZ, PITCH, ROLL,
	NX, NY, NZ, HEAD_Y, HEAD_P, HEAD_R, GAPE,
	WF, LEN,
	RU_Y, RU_E, RF_Y, RF_E, RH_Y, RH_E, R_TW, R_FAN,
	LU_Y, LU_E, LF_Y, LF_E, LH_Y, LH_E, L_TW, L_FAN,
	TAIL_S, TAIL_P,
	GRIP, FOOT_X, FOOT_Z, FOOT_SP, FOOT_A, TOES,
	TREM, VEIN, EYE,
	COUNT,
}

class Span:
	extends RefCounted
	var y0: int = 0
	var lo: PackedInt32Array = PackedInt32Array()
	var hi: PackedInt32Array = PackedInt32Array()

	func has_point(x: int, y: int) -> bool:
		var r: int = y - y0
		if r < 0 or r >= lo.size():
			return false
		return x >= lo[r] and x <= hi[r]

class Part:
	extends RefCounted
	var depth: float = 0.0
	var order: int = 0
	var rank: int = 0
	var draw: Callable = Callable()
	var glow: Callable = Callable()
	var span: Span = null

class Blade:
	extends RefCounted
	var poly: PackedVector2Array = PackedVector2Array()
	var left: PackedVector2Array = PackedVector2Array()
	var right: PackedVector2Array = PackedVector2Array()
	var center: PackedVector2Array = PackedVector2Array()
	var span: Span = null
	var dorsal: float = 1.0
	var depth: float = 0.0
	var tip: Vector2 = Vector2.ZERO
	var vein_start: float = 0.0
	var width: float = 3.0
	var lit_edge: PackedVector2Array = PackedVector2Array()
	var idx: int = -1 ## slot in its wing (0-5 primaries, 6-10 secondaries), -1 = tail
	var light: float = 0.0 ## 0..1: how far this blade has turned into a blade of light (phase 2)
	var hidden: bool = false ## shattered and not yet regrown
	var salt: float = 0.0
	var cracked: bool = false
	var far_edge: PackedVector2Array = PackedVector2Array()

class Wing:
	extends RefCounted
	var side: float = 1.0
	var s: Vector3 = Vector3.ZERO
	var e: Vector3 = Vector3.ZERO
	var w: Vector3 = Vector3.ZERO
	var h: Vector3 = Vector3.ZERO
	var upref: Vector3 = Vector3.UP
	var chord: Vector3 = Vector3.BACK
	var normal: Vector3 = Vector3.UP
	var blades: Array[Blade] = []
	var membrane: PackedVector2Array = PackedVector2Array()
	var membrane_span: Span = null
	var arm_span: Span = null
	var arm_discs: PackedVector3Array = PackedVector3Array()
	var vein_arm: PackedVector2Array = PackedVector2Array()
	var claw: PackedVector2Array = PackedVector2Array()
	var depth: float = 0.0

const OUTLINE: Color = Color("040208")
const DARK: Color = Color("07040d")
const FLESH: Color = Color("0c0814")
const MID: Color = Color("150e24")
const HIGH: Color = Color("221740")
const RIM: Color = Color("5a36b8")
const ROCK0: Color = Color("0d0a17")
const ROCK1: Color = Color("171526")
const ROCK2: Color = Color("262440")
const ROCK3: Color = Color("45436a")
const VEIN: Color = VoidGlow.VEIN
const VEIN_LIGHT: Color = VoidGlow.VEIN_LIGHT
const CORE: Color = Color("ecd2ff")
const CORE_HOT: Color = Color("fff7ff")
const EYE: Color = Color("ff4fd8")
const EYE_HOT: Color = Color("ffd6f6")

const PAL_FLESH: Array[Color] = [OUTLINE, FLESH, MID, HIGH, RIM]
const PAL_DARK: Array[Color] = [OUTLINE, DARK, FLESH, MID, RIM]
const PAL_ROCK: Array[Color] = [OUTLINE, ROCK0, ROCK1, ROCK2, ROCK3]
const PAL_BEAK: Array[Color] = [OUTLINE, ROCK1, ROCK2, ROCK3, Color("7d7bb0")]

const SQUASH: float = 0.72
const OFFSCREEN_HZ: float = 10.0
const LU: float = 11.0
const LF: float = 11.0
const LH: float = 3.5
const SH_X: float = 4.0
const SH_Z: float = 3.0
const P_LEN: Array[float] = [14.0, 16.0, 15.5, 14.0, 12.5, 11.0]
const S_LEN: Array[float] = [13.0, 14.5, 15.5, 15.5, 14.5]
const P_RATE: Array[float] = [12.0, 13.0, 14.5, 16.0, 18.0, 20.0]
const S_RATE: Array[float] = [24.0, 23.0, 22.0, 21.0, 20.0]
const U_S: Array[float] = [0.0, 0.12, 0.3, 0.55, 0.78, 0.92, 1.0]
const HW_S: Array[float] = [0.5, 0.92, 1.0, 0.92, 0.68, 0.34, 0.0]
const TAIL_LEN: Array[float] = [12.0, 14.5, 16.0, 14.5, 12.0]
const TD_N: int = 7
const TD_COUNT: int = 6 ## tendrils of the first phase
const TD_MAX: int = 10 ## phase 2 grows four more out of the back and shoulders
const TD_ANCHOR: Array[Vector3] = [Vector3(6.0, 2.5, -6.5), Vector3(6.0, -2.5, -6.5), Vector3(-3.0, 0.0, -7.5), Vector3(-11.5, 1.2, -2.0), Vector3(3.0, 7.2, 1.5), Vector3(3.0, -7.2, 1.5), Vector3(-4.5, 3.2, 5.0), Vector3(-4.5, -3.2, 5.0), Vector3(1.5, 5.6, 5.2), Vector3(1.5, -5.6, 5.2)]
const TD_LEN: Array[float] = [14.0, 16.0, 20.0, 18.0, 13.0, 15.0, 18.0, 19.0, 15.0, 16.0]
const EYES: int = 8 ## six slits at the sides of the skull, two more on the brow in phase 2
const LIGHT_BLADES: Array[int] = [1, 3] ## primaries that turn into blades of light
const SPL_A: Array[float] = [25.0, 21.0, 28.0, 19.0, 26.0, 23.0]
const SPL_B: Array[float] = [15.0, 18.0, 12.0, 16.0, 17.0, 13.0]
const SPL_TILT: Array[float] = [0.5, -0.4, 0.9, -0.8, 0.2, 1.2]
const SPL_Z: Array[float] = [4.0, -1.0, 8.0, 2.0, 11.0, 6.0]
const SPL_W: Array[float] = [0.7, -0.55, 0.9, -0.8, 0.6, -0.65]
const SPL_LEN: Array[float] = [4.0, 3.0, 5.0, 3.0, 4.0, 5.0]
const HALO_PHI: Array[float] = [0.4, 1.95, 3.5, 5.0]
const HALO_SPAN: Array[float] = [0.5, 0.36, 0.62, 0.3]
const HALO_W: Array[float] = [0.16, -0.11, 0.09, -0.2]
const ZIG: Array[int] = [0, 1, 0, -1, 0, 1, 1, 0, -1, 0, -1, 0, 1]
const TORSO_X: Array[float] = [-12.0, -7.0, -1.0, 5.0, 10.0, 13.0]
const TORSO_R: Array[float] = [2.6, 5.0, 7.4, 7.6, 6.0, 4.0]
const TORSO_Z: Array[float] = [-0.5, 0.0, 0.5, 0.5, 1.5, 3.0]
const BEAD_GRAVITY: float = 520.0
const DEAD_ROLL: float = TAU + 1.45
const FLY_RATE: float = 2.6
const HOVER_RATE: float = 1.5
const FLAP_BEAT: float = 0.12
const PERCH_FOOT: Vector3 = Vector3(3.0, 4.5, 2.0)

var ground_drop: float = 100.0
## What the fight asks of the body on top of the pose (src/entities/enemies/mornath_fight.gd): the wings raised high, the feathers charging, tired and drooping.
var raise_r: float = 0.0 ## 0..1: the bird's right wing raised
var raise_l: float = 0.0 ## the left wing
var charge: float = 0.0 ## 0..1: the feathers charge (veins flare, a light runs out along every blade)
var charge_kind: int = 0 ## 0 rain (white-violet), 1 shot (magenta), 2 chase (dark violet pulse), 3 line (cold white)
var fatigue: float = 0.0 ## 0..1: the wings hang heavy, the head sinks, he heaves
var tick_hz: float = 0.0 ## > 0: the geometry is rebuilt and redrawn at most this often (the game uses 30; 0 = on every call, the tools)
var on_screen: bool = true ## false: it is rebuilt rarely and not drawn at all (nobody can see it)
var stat_update_us: int = 0 ## profiling: microseconds spent in update_rig / draw (summed, reset by the reader)
var stat_draw_us: int = 0
## Phase 2 (the fight sets these): 0 = the look of phase one, 1 = the corrupted look (eight eyes, ten tendrils, blades of light, cracks, broken halo, splinters).
var corruption: float = 0.0
var lift: float = 0.0 ## 0..1: the tendrils pull taut upwards, as if they lifted him

var _pose: Pose = Pose.PERCHED
var _elapsed: float = 0.0
var _duration: float = 1.0
var _time: float = 0.0
var _gt: float = 0.0
var _heading: float = 0.0
var _goal_heading: float = 0.0
var _head_follow: float = 0.0
var _vel: Vector2 = Vector2.ZERO
var _rise: float = 0.0
var _alpha: float = 1.0
var _flash: float = 0.0
var _ready_geo: bool = false
var _tick_acc: float = 0.0
var _drawn_once: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _q: PackedFloat32Array = PackedFloat32Array()
var _tq: PackedFloat32Array = PackedFloat32Array()
var _q_from: PackedFloat32Array = PackedFloat32Array()
var _blend_t: float = 1.0
var _blend_len: float = 0.15

var _flap: float = 0.0
var _flap_rate: float = 0.0
var _pitch_s: float = 0.0
var _roll_s: float = 0.0
var _turn_s: float = 0.0
var _prev_heading: float = 0.0
var _beat_a: bool = false
var _beat_b: bool = false
var _beat_t: bool = false

var _cp: float = 1.0
var _sp: float = 0.0
var _cr: float = 1.0
var _sr: float = 0.0
var _center: Vector3 = Vector3.ZERO
var _view: Vector3 = Vector3(0.0, 0.81, 0.59)
var _head_c: Vector3 = Vector3.ZERO
var _hf: Vector3 = Vector3.RIGHT
var _hs: Vector3 = Vector3.UP
var _hu: Vector3 = Vector3.UP
var _core3: Vector3 = Vector3.ZERO
var _torso_discs: PackedVector3Array = PackedVector3Array()
var _torso_depths: PackedFloat32Array = PackedFloat32Array()
var _wings: Array[Wing] = []
var _bf: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var _tf: PackedVector3Array = PackedVector3Array()
var _bf_ready: bool = false
var _parts: Array[Part] = []
var _sorted: Array[Part] = []
var _order: int = 0

var _td: Array[PackedVector3Array] = []
var _td_prev: Array[PackedVector3Array] = []
var _td_ready: bool = false
var _td_clock: float = 0.0
var _vel3_prev: Vector3 = Vector3.ZERO
var _acc3: Vector3 = Vector3.ZERO
var _td_anchor: Array[Vector3] = []
var _td_floor: float = -1000.0

var _eye_open: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
var _eye_cd: PackedFloat32Array = PackedFloat32Array([1.0, 2.0, 3.0, 2.5, 1.5, 4.0, 2.2, 3.4])
var _eye_blink: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _eye_narrow: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

var _bead_state: int = 0
var _bead_cd: float = 4.0
var _bead_age: float = 0.0
var _bead_pos: Vector2 = Vector2.ZERO
var _bead_vel: float = 0.0
var _bead_r: float = 0.0
var _beak_tip: Vector2 = Vector2.ZERO

var _shards: Array[Dictionary] = []
var _shards_made: bool = false
var _life_wing: Array[float] = [1.0, 1.0]
var _life_core: float = 1.0
var _life_eye: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])

var _corr: float = 0.0 ## the smoothed corruption actually drawn
var _corr_init: bool = false
var _lb: float = 0.0 ## 0..1: how far the light blades have turned from basalt to light
var _pop_age: float = -1.0 ## seconds since the brow eyes popped open (-1 = shut)
var _light_age: float = 99.0 ## seconds since the light blades shattered
var _light_grow: float = 1.0
var _light_flare: float = 0.0
var _crack_flash: float = 0.0
var _judge_k: float = 0.0
var _orn_alive: float = 1.0
var _bits: Array[Dictionary] = []
var _orb: PackedFloat32Array = PackedFloat32Array([0.0, 1.1, 2.3, 3.4, 4.5, 5.6])
var _orb_rate: float = 1.0
var _td_scale: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0])
var _bounds: Rect2 = Rect2()
var _vein_seen: Dictionary = {}

@onready var _body: Node2D = $Body
@onready var _glow: Node2D = $Glow


func _ready() -> void:
	var seed_name: String = String(get_parent().name) if get_parent() != null else "sky"
	_rng.seed = hash(seed_name + "|mornath")
	_q = _default_q()
	_tq = _default_q()
	_q_from = _default_q()
	_bead_cd = _rng.randf_range(2.0, 4.0)
	for i: int in EYES:
		_eye_cd[i] = _rng.randf_range(1.0, 5.0)
	_body.draw.connect(_draw_main)
	_glow.draw.connect(_draw_glow)


# --- API -----------------------------------------------------------------------------------------------------------


func start_pose(pose: Pose, duration: float, elapsed: float = 0.0) -> void:
	var previous: Pose = _pose
	_pose = pose
	_duration = maxf(0.01, duration)
	_elapsed = elapsed
	_q_from = _q.duplicate()
	var late: bool = elapsed > 0.25
	_blend_t = 1.0 if late else 0.0
	match pose:
		Pose.STAGGER:
			_blend_len = 0.07
		Pose.CRASHED:
			_blend_len = 0.08
		Pose.TAKEOFF:
			_blend_len = 0.22
		Pose.LANDING:
			_blend_len = 0.16
		Pose.DEAD:
			_blend_len = 0.25
		Pose.SPENT:
			_blend_len = 0.4
		Pose.DOWNED:
			_blend_len = 0.3
		Pose.JUDGE:
			_blend_len = 0.5
		_:
			_blend_len = 0.25
	var frac: float = clampf(elapsed / _duration, 0.0, 1.0)
	_beat_a = elapsed > 0.05
	_beat_b = frac >= 0.3
	_beat_t = frac >= 0.9
	if pose == Pose.FLYING and previous == Pose.TAKEOFF:
		_flap = 0.2
		_flap_rate = FLY_RATE
	if pose == Pose.DEAD:
		_shards.clear()
		_shards_made = false
	if pose != Pose.PERCHED and _bead_state == 1:
		_bead_state = 0
		_bead_cd = _rng.randf_range(3.0, 6.0)


func update_rig(delta: float, velocity: Vector2, heading: float, rise: float) -> void:
	if tick_hz > 0.0 and delta > 0.0:
		_tick_acc += delta
		var step: float = 1.0 / (tick_hz if on_screen else OFFSCREEN_HZ)
		if _tick_acc < step - 0.0005:
			return
		delta = _tick_acc
		_tick_acc = 0.0
	var t0: int = Time.get_ticks_usec()
	var dt: float = clampf(delta, 0.0, 0.1)
	_time += dt
	_elapsed += dt
	_vel = velocity
	_rise = rise
	_goal_heading = heading
	_flash = move_toward(_flash, 0.0, dt * 5.0)
	_update_corruption(dt)
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	_update_heading(dt)
	_update_motion_state(dt)
	_pose_target(t, dt)
	_blend_t = minf(1.0, _blend_t + dt / _blend_len)
	var k: float = smoothstep(0.0, 1.0, _blend_t)
	for i: int in Q.COUNT:
		_q[i] = lerpf(_q_from[i], _tq[i], k)
	_update_eyes(dt)
	_update_life(t)
	_alpha = 1.0 - pow(smoothstep(0.62, 1.0, t), 1.2) if _pose == Pose.DEAD else 1.0
	_gt += dt * (0.8 + (_q[Q.VEIN] - 1.0) * 0.9 + (0.3 if _pose == Pose.FLYING else 0.0))
	_build(dt, t)
	_step_tendrils(dt)
	_build_tendril_parts()
	_bead_step(dt)
	_shard_step(dt, t)
	_bits_step(dt)
	_finish_parts()
	_ready_geo = true
	if on_screen or not _drawn_once:
		_drawn_once = true
		_body.queue_redraw()
		_glow.queue_redraw()
	stat_update_us += Time.get_ticks_usec() - t0


func hit_flash() -> void:
	_flash = 1.0


## Sets the corruption at once, without the 0.8 s ramp (a checkpoint that starts in phase 2).
func set_corruption_now(value: float) -> void:
	corruption = clampf(value, 0.0, 1.0)
	_corr = corruption
	_corr_init = true
	_pop_age = 2.0 if _corr >= 0.5 else -1.0


## The core crack and all eight eyes flare white for a quarter of a second (the scream).
func crack_flash() -> void:
	_crack_flash = 1.0


## The four light blades shatter into shards and grow back as light over about 1.4 s.
func burst_blades() -> void:
	_light_age = 0.0
	for wing: Wing in _wings:
		for idx: int in LIGHT_BLADES:
			var blade: Blade = wing.blades[idx]
			for n: int in 4:
				var at: int = clampi(2 + n, 1, blade.center.size() - 1)
				var out: Vector2 = (blade.center[at] - blade.center[1]).normalized() if blade.center[at] != blade.center[1] else Vector2.UP
				_bits.append({
					"pos": blade.center[at] + Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6)),
					"vel": out * _rng.randf_range(14.0, 46.0) + Vector2(_rng.randf_range(-16.0, 16.0), _rng.randf_range(-34.0, -6.0)),
					"age": 0.0,
					"life": _rng.randf_range(0.6, 1.0),
					"size": _rng.randi_range(1, 3),
				})
	while _bits.size() > 24:
		_bits.remove_at(0)


## Where the blades of a wing end (rig-local pixels, `si` 0 = the bird's right wing): the six primaries first, then the five secondaries.
## The fight shoots its feathers out of them.
func blade_tips(si: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if si < 0 or si >= _wings.size():
		return out
	for blade: Blade in _wings[si].blades:
		out.append(blade.tip)
	return out


func head_point() -> Vector2:
	return global_position + _p(_head_c)


func core_point() -> Vector2:
	return global_position + _p(_core3)


## Rig-local pixel bounds of the whole drawn silhouette (parts only; bead and shards excluded).
func bounds() -> Rect2:
	return _bounds


# --- math ----------------------------------------------------------------------------------------------------------


func _ang(forward: float, side: float, height: float, heading: float) -> Vector2:
	return Vector2(cos(heading) * forward - sin(heading) * side, (sin(heading) * forward + cos(heading) * side) * SQUASH - height)


func _p(v: Vector3) -> Vector2:
	return _ang(v.x, v.y, v.z, _heading)


func _pw(v: Vector3) -> Vector2:
	return Vector2(v.x, v.y * SQUASH - v.z)


func _depth(v: Vector3) -> float:
	return sin(_heading) * v.x + cos(_heading) * v.y + 0.4 * v.z


func _to_world(v: Vector3) -> Vector3:
	var c: float = cos(_heading)
	var s: float = sin(_heading)
	return Vector3(c * v.x - s * v.y, s * v.x + c * v.y, v.z)


## Bird-local direction into the body frame: roll about the forward axis, then pitch about the side axis.
func _rot(v: Vector3) -> Vector3:
	var y1: float = v.y * _cr + v.z * _sr
	var z1: float = -v.y * _sr + v.z * _cr
	return Vector3(v.x * _cp - z1 * _sp, y1, v.x * _sp + z1 * _cp)


func _bp(v: Vector3) -> Vector3:
	return _center + _rot(v)


func _ik(root: Vector3, target: Vector3, upper: float, lower: float, pole: Vector3) -> PackedVector3Array:
	var span: Vector3 = target - root
	var reach: float = clampf(span.length(), absf(upper - lower) + 0.05, upper + lower - 0.05)
	var dir: Vector3 = span.normalized() if span.length() > 0.001 else Vector3.DOWN
	var along: float = (upper * upper - lower * lower + reach * reach) / (2.0 * reach)
	var bulge: float = sqrt(maxf(upper * upper - along * along, 0.0))
	var bend: Vector3 = pole - dir * pole.dot(dir)
	bend = bend.normalized() if bend.length() > 0.001 else Vector3.UP
	return PackedVector3Array([root + dir * along + bend * bulge, root + dir * reach])


func _tint(color: Color, alpha: float = 1.0) -> Color:
	return Color(color.lerp(Color.WHITE, _flash * 0.8), _alpha * alpha)


func _update_corruption(dt: float) -> void:
	if not _corr_init:
		_corr = corruption
		_corr_init = true
		_pop_age = 2.0 if _corr >= 0.5 else -1.0
	else:
		_corr = move_toward(_corr, corruption, dt * 1.2)
	if _pop_age < 0.0 and _corr >= 0.5:
		_pop_age = 0.0
	elif _corr < 0.45:
		_pop_age = -1.0
	if _pop_age >= 0.0:
		_pop_age = minf(_pop_age + dt, 9.0)
	_lb = smoothstep(0.35, 0.85, _corr)
	_light_age = minf(_light_age + dt, 99.0)
	var regrow: float = clampf((_light_age - 0.3) / 1.4, 0.0, 1.0)
	_light_grow = 1.0 - pow(1.0 - regrow, 3.0)
	_light_flare = (1.0 - regrow) if (_light_age > 0.3 and regrow < 1.0) else 0.0
	_crack_flash = move_toward(_crack_flash, 0.0, dt * 4.0)
	_judge_k = move_toward(_judge_k, 1.0 if _pose == Pose.JUDGE else 0.0, dt * 2.0)
	for i: int in 4:
		_td_scale[TD_COUNT + i] = smoothstep(0.3, 0.9, _corr)


func _noise(n: int, salt: float = 0.0) -> float:
	return fposmod(sin(float(n) * 12.9898 + salt * 78.233) * 43758.5453, 1.0)


# --- pixel spans ---------------------------------------------------------------------------------------------------


func _span_poly(points: PackedVector2Array) -> Span:
	var sp: Span = Span.new()
	if points.size() < 3:
		return sp
	var low: float = INF
	var high: float = -INF
	for point: Vector2 in points:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	var y_lo: int = floori(low)
	var y_hi: int = ceili(high)
	var rows: int = y_hi - y_lo + 1
	sp.y0 = y_lo
	sp.lo.resize(rows)
	sp.hi.resize(rows)
	var n: int = points.size()
	for r: int in rows:
		var scan: float = float(y_lo + r) + 0.5
		var left: float = INF
		var right: float = -INF
		for k: int in n:
			var a: Vector2 = points[k]
			var b: Vector2 = points[(k + 1) % n]
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
				var x: float = a.x + (scan - a.y) / (b.y - a.y) * (b.x - a.x)
				left = minf(left, x)
				right = maxf(right, x)
		if left <= right:
			var from_x: int = roundi(left)
			var width: int = maxi(1, roundi(right) - from_x)
			sp.lo[r] = from_x
			sp.hi[r] = from_x + width - 1
		else:
			sp.lo[r] = 1 << 30
			sp.hi[r] = -(1 << 30)
	return sp


## Union of discs (x, y, radius); `shift` is in units of the disc radius, `scale` shrinks every radius.
func _span_discs(discs: PackedVector3Array, grow: float = 0.0, shift: Vector2 = Vector2.ZERO, scale: float = 1.0) -> Span:
	var sp: Span = Span.new()
	if discs.is_empty():
		return sp
	var low: int = 1 << 30
	var high: int = -(1 << 30)
	for d: Vector3 in discs:
		var r: float = d.z * scale + grow
		var cy: int = roundi(d.y + shift.y * d.z)
		low = mini(low, cy - ceili(r))
		high = maxi(high, cy + ceili(r))
	var rows: int = high - low + 1
	sp.y0 = low
	sp.lo.resize(rows)
	sp.hi.resize(rows)
	for r: int in rows:
		sp.lo[r] = 1 << 30
		sp.hi[r] = -(1 << 30)
	for d: Vector3 in discs:
		var rad: float = d.z * scale + grow
		var cx: int = roundi(d.x + shift.x * d.z)
		var cy2: int = roundi(d.y + shift.y * d.z)
		var rc: int = ceili(rad)
		for dy: int in range(-rc, rc + 1):
			var q: float = rad * rad - float(dy * dy)
			if q < 0.0:
				continue
			var w: int = int(sqrt(q) + 0.35)
			var row: int = cy2 + dy - low
			sp.lo[row] = mini(sp.lo[row], cx - w)
			sp.hi[row] = maxi(sp.hi[row], cx + w)
	return sp


func _paint(canvas: Node2D, sp: Span, color: Color) -> void:
	var rows: int = sp.lo.size()
	var r: int = 0
	while r < rows:
		if sp.hi[r] < sp.lo[r]:
			r += 1
			continue
		var run: int = 1
		while r + run < rows and sp.lo[r + run] == sp.lo[r] and sp.hi[r + run] == sp.hi[r]:
			run += 1
		canvas.draw_rect(Rect2(float(sp.lo[r]), float(sp.y0 + r), float(sp.hi[r] - sp.lo[r] + 1), float(run)), color)
		r += run


## One pixel of ink round the shape (4-connected), drawn under the fill.
func _paint_outline(canvas: Node2D, sp: Span, color: Color) -> void:
	var rows: int = sp.lo.size()
	for r: int in range(-1, rows + 1):
		var lo_v: int = 1 << 30
		var hi_v: int = -(1 << 30)
		if r >= 0 and r < rows and sp.hi[r] >= sp.lo[r]:
			lo_v = sp.lo[r] - 1
			hi_v = sp.hi[r] + 1
		var up: int = r - 1
		if up >= 0 and up < rows and sp.hi[up] >= sp.lo[up]:
			lo_v = mini(lo_v, sp.lo[up])
			hi_v = maxi(hi_v, sp.hi[up])
		var down: int = r + 1
		if down >= 0 and down < rows and sp.hi[down] >= sp.lo[down]:
			lo_v = mini(lo_v, sp.lo[down])
			hi_v = maxi(hi_v, sp.hi[down])
		if hi_v >= lo_v:
			canvas.draw_rect(Rect2(float(lo_v), float(sp.y0 + r), float(hi_v - lo_v + 1), 1.0), color)


## The pixels whose up-left neighbour is outside the shape: the top and left edge catch the light.
func _paint_rim(canvas: Node2D, sp: Span, color: Color) -> void:
	var rows: int = sp.lo.size()
	for r: int in rows:
		if sp.hi[r] < sp.lo[r]:
			continue
		var y: float = float(sp.y0 + r)
		if r == 0 or sp.hi[r - 1] < sp.lo[r - 1]:
			canvas.draw_rect(Rect2(float(sp.lo[r]), y, float(sp.hi[r] - sp.lo[r] + 1), 1.0), color)
			continue
		var left_end: int = mini(sp.hi[r], sp.lo[r - 1])
		if left_end >= sp.lo[r]:
			canvas.draw_rect(Rect2(float(sp.lo[r]), y, float(left_end - sp.lo[r] + 1), 1.0), color)
		var right_start: int = maxi(sp.lo[r], sp.hi[r - 1] + 2)
		if right_start <= sp.hi[r]:
			canvas.draw_rect(Rect2(float(right_start), y, float(sp.hi[r] - right_start + 1), 1.0), color)


## The pixels whose down-right neighbour is outside the shape: a dark under-edge that separates overlapping blades.
func _paint_shade(canvas: Node2D, sp: Span, color: Color) -> void:
	var rows: int = sp.lo.size()
	for r: int in rows:
		if sp.hi[r] < sp.lo[r]:
			continue
		var y: float = float(sp.y0 + r)
		if r == rows - 1 or sp.hi[r + 1] < sp.lo[r + 1]:
			canvas.draw_rect(Rect2(float(sp.lo[r]), y, float(sp.hi[r] - sp.lo[r] + 1), 1.0), color)
			continue
		var right_start: int = maxi(sp.lo[r], sp.hi[r + 1])
		if right_start <= sp.hi[r]:
			canvas.draw_rect(Rect2(float(right_start), y, float(sp.hi[r] - right_start + 1), 1.0), color)


func _expand_bounds(sp: Span) -> void:
	if sp == null or sp.lo.is_empty():
		return
	for r: int in sp.lo.size():
		if sp.hi[r] < sp.lo[r]:
			continue
		var rect: Rect2 = Rect2(float(sp.lo[r]), float(sp.y0 + r), float(sp.hi[r] - sp.lo[r] + 1), 1.0)
		_bounds = rect if _bounds.size == Vector2.ZERO else _bounds.merge(rect)


## A tube of overlapping discs from a 3D polyline (body frame) with radii: returns the discs on screen.
func _discs_along(points: Array[Vector3], radii: Array[float]) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for i: int in points.size() - 1:
		var a: Vector2 = _p(points[i])
		var b: Vector2 = _p(points[i + 1])
		var ra: float = radii[i]
		var rb: float = radii[i + 1]
		var count: int = maxi(1, ceili(a.distance_to(b) / maxf(1.0, minf(ra, rb) * 0.7)))
		for k: int in range(0 if i == 0 else 1, count + 1):
			var u: float = float(k) / float(count)
			var c: Vector2 = a.lerp(b, u)
			out.append(Vector3(c.x, c.y, lerpf(ra, rb, u)))
	return out


func _tube_span(discs: PackedVector3Array) -> Span:
	return _span_discs(discs)


## Outline, base, mid, high and a lit rim: the shared look of every rounded black part.
func _paint_tube(canvas: Node2D, discs: PackedVector3Array, pal: Array[Color], base_span: Span = null) -> Span:
	var base: Span = base_span if base_span != null else _span_discs(discs)
	_paint_outline(canvas, base, _tint(pal[0]))
	_paint(canvas, base, _tint(pal[1]))
	_paint(canvas, _span_discs(discs, 0.0, Vector2(-0.2, -0.26), 0.74), _tint(pal[2]))
	_paint(canvas, _span_discs(discs, 0.0, Vector2(-0.38, -0.5), 0.4), _tint(pal[3]))
	_paint_rim(canvas, base, _tint(pal[4], 0.8))
	return base


func _disc(canvas: Node2D, c: Vector2, r: float, color: Color) -> void:
	var cx: int = roundi(c.x)
	var cy: int = roundi(c.y)
	var rc: int = ceili(r)
	for dy: int in range(-rc, rc + 1):
		var q: float = r * r - float(dy * dy)
		if q < 0.0:
			continue
		var w: int = int(sqrt(q) + 0.35)
		canvas.draw_rect(Rect2(float(cx - w), float(cy + dy), float(w * 2 + 1), 1.0), color)


func _seg(canvas: Node2D, from: Vector2, to: Vector2, width_from: float, width_to: float, color: Color) -> void:
	var count: int = maxi(1, ceili(from.distance_to(to) * 1.5))
	for i: int in count + 1:
		var k: float = float(i) / float(count)
		var width: float = maxf(1.0, roundf(lerpf(width_from, width_to, k)))
		canvas.draw_rect(Rect2(from.lerp(to, k).round() - Vector2.ONE * floorf(width * 0.5), Vector2.ONE * width), color)


func _halo(canvas: Node2D, point: Vector2, color: Color, strength: float, bloom: float = 0.5) -> void:
	VoidGlow.halo(canvas, point, color, strength * _alpha, bloom)


func _beat(phase: float) -> float:
	return VoidGlow.beat(_gt, phase, 1.0)


# --- defaults and poses --------------------------------------------------------------------------------------------


func _default_q() -> PackedFloat32Array:
	var q: PackedFloat32Array = PackedFloat32Array()
	q.resize(Q.COUNT)
	q.fill(0.0)
	q[Q.CZ] = 16.0
	q[Q.PITCH] = 1.08
	q[Q.NX] = 10.5
	q[Q.NZ] = -0.6
	q[Q.HEAD_P] = -0.2
	q[Q.WF] = 1.0
	q[Q.LEN] = 0.95
	for o: int in [Q.RU_Y, Q.LU_Y]:
		q[o] = 0.55
		q[o + 1] = -1.22
		q[o + 2] = -2.25
		q[o + 3] = -0.55
		q[o + 4] = -2.75
		q[o + 5] = -0.8
		q[o + 7] = 0.22
	q[Q.TAIL_S] = 0.2
	q[Q.TAIL_P] = 0.85
	q[Q.GRIP] = 1.0
	q[Q.FOOT_X] = -7.0
	q[Q.FOOT_SP] = 2.6
	q[Q.FOOT_Z] = -5.5
	q[Q.TOES] = 0.8
	q[Q.VEIN] = 1.0
	q[Q.EYE] = 1.0
	return q


func _set_wings(uy: float, ue: float, fy: float, fe: float, hy: float, he: float, tw: float, fan: float) -> void:
	for o: int in [Q.RU_Y, Q.LU_Y]:
		_tq[o] = uy
		_tq[o + 1] = ue
		_tq[o + 2] = fy
		_tq[o + 3] = fe
		_tq[o + 4] = hy
		_tq[o + 5] = he
		_tq[o + 6] = tw
		_tq[o + 7] = fan


func _lerp_wings(uy: float, ue: float, fy: float, fe: float, hy: float, he: float, tw: float, fan: float, k: float) -> void:
	for o: int in [Q.RU_Y, Q.LU_Y]:
		_tq[o] = lerpf(_tq[o], uy, k)
		_tq[o + 1] = lerpf(_tq[o + 1], ue, k)
		_tq[o + 2] = lerpf(_tq[o + 2], fy, k)
		_tq[o + 3] = lerpf(_tq[o + 3], fe, k)
		_tq[o + 4] = lerpf(_tq[o + 4], hy, k)
		_tq[o + 5] = lerpf(_tq[o + 5], he, k)
		_tq[o + 6] = lerpf(_tq[o + 6], tw, k)
		_tq[o + 7] = lerpf(_tq[o + 7], fan, k)


## 1 at the top of the stroke, -1 at the bottom: a quick powerful downstroke (38 % of the cycle), a longer lighter upstroke.
func _stroke(ph: float) -> float:
	var p: float = fposmod(ph, 1.0)
	if p < 0.38:
		return cos(p / 0.38 * PI)
	return -cos((p - 0.38) / 0.62 * PI)


func _flap_wings(ph: float, hover: bool) -> float:
	var ea: float = (_stroke(ph) + 1.0) * 0.5
	var ef: float = (_stroke(ph - 0.05) + 1.0) * 0.5
	var eh: float = (_stroke(ph - 0.11) + 1.0) * 0.5
	if hover:
		_set_wings(lerpf(0.9, 0.05, ea), lerpf(-0.5, 0.8, ea), lerpf(0.75, 0.1, ef), lerpf(-0.6, 0.55, ef), lerpf(0.9, 0.3, eh), lerpf(-0.7, 0.3, eh), 0.0, lerpf(1.0, 0.8, eh))
	else:
		_set_wings(0.03, lerpf(-0.6, 0.95, ea), lerpf(0.04, 0.34, ef), lerpf(-0.75, 0.6, ef), lerpf(0.18, 0.5, eh), lerpf(-0.9, 0.2, eh), 0.0, lerpf(1.0, 0.62, eh))
	return ea * 2.0 - 1.0


func _advance_flap(dt: float, rate: float, beat_now: bool) -> void:
	_flap_rate = lerpf(_flap_rate, rate, 1.0 - exp(-8.0 * dt))
	var previous: float = _flap
	_flap = fposmod(_flap + dt * _flap_rate, 1.0)
	if dt <= 0.0 or not beat_now:
		return
	var crossed: bool = (previous < FLAP_BEAT and _flap >= FLAP_BEAT) or (_flap < previous and (previous < FLAP_BEAT or _flap >= FLAP_BEAT))
	if crossed:
		wing_beat.emit(_pose != Pose.HOVER)


func _update_heading(dt: float) -> void:
	var rate: float = 2.2 if _pose in [Pose.PERCHED, Pose.STAGGER, Pose.SPENT, Pose.JUDGE] else 7.0
	if _pose in [Pose.CRASHED, Pose.DEAD, Pose.DOWNED]:
		rate = 1.5
	if dt <= 0.0:
		if not _ready_geo:
			_heading = _goal_heading
	else:
		_heading += angle_difference(_heading, _goal_heading) * (1.0 - exp(-rate * dt))
	var rel: float = clampf(angle_difference(_heading, _goal_heading), -1.4, 1.4)
	if _pose in [Pose.PERCHED, Pose.STAGGER, Pose.SPENT, Pose.JUDGE]:
		_head_follow = lerpf(_head_follow, rel, 1.0 - exp(-9.0 * dt)) if dt > 0.0 else rel
	else:
		_head_follow = lerpf(_head_follow, 0.0, 1.0 - exp(-6.0 * dt))


func _update_motion_state(dt: float) -> void:
	if dt <= 0.0:
		return
	_pitch_s = lerpf(_pitch_s, clampf(_rise * 0.0042, -0.5, 0.55), 1.0 - exp(-5.0 * dt))
	var turn: float = angle_difference(_prev_heading, _heading) / dt
	_prev_heading = _heading
	_turn_s = lerpf(_turn_s, clampf(turn, -6.0, 6.0), 1.0 - exp(-4.0 * dt))
	_roll_s = lerpf(_roll_s, clampf(_turn_s * 0.2, -0.6, 0.6), 1.0 - exp(-5.0 * dt))


func _pose_target(t: float, dt: float) -> void:
	_tq = _default_q()
	var breath: float = sin(_time * TAU / 2.6)
	match _pose:
		Pose.PERCHED:
			_pose_perched(breath)
		Pose.TAKEOFF:
			_pose_takeoff(t, dt)
		Pose.FLYING:
			_pose_flying(dt)
		Pose.HOVER:
			_pose_hover(dt)
		Pose.LANDING:
			_pose_landing(t)
		Pose.STAGGER:
			_pose_stagger(t, breath)
		Pose.CRASHED:
			_pose_crashed(t)
		Pose.DEAD:
			_pose_dead(t)
		Pose.SPENT:
			_pose_spent(breath)
		Pose.DOWNED:
			_pose_downed(breath)
		Pose.JUDGE:
			_pose_judge(breath)
	_apply_action()
	_tq[Q.HEAD_Y] += _head_follow


func _pose_perched(breath: float) -> void:
	_tq[Q.CZ] = 16.0 + breath * 0.35
	_tq[Q.PITCH] = 1.08 + sin(_time * 0.37) * 0.015 + breath * 0.008
	_tq[Q.HEAD_Y] = 0.5 * sin(_time * 0.45) + 0.22 * sin(_time * 0.97 + 1.3)
	_tq[Q.HEAD_P] = -0.34 + 0.1 * sin(_time * 0.31 + 0.6) + 0.07 * maxf(0.0, sin(_time * 0.9))
	_tq[Q.HEAD_R] = 0.12 * sin(_time * 0.52 + 2.0)
	for o: int in [Q.RU_Y, Q.LU_Y]:
		_tq[o + 1] += breath * 0.03
		_tq[o + 3] += breath * 0.03
	_tq[Q.VEIN] = 1.0 + 0.1 * sin(_time * 0.7)


func _pose_takeoff(t: float, dt: float) -> void:
	var unfold: float = smoothstep(0.05, 0.66, t)
	var up: float = unfold
	var launch: float = smoothstep(0.76, 1.0, t)
	var crouch: float = smoothstep(0.0, 0.7, t) * (1.0 - launch)
	_tq[Q.WF] = 1.0 - unfold
	_tq[Q.LEN] = lerpf(0.95, 1.0, unfold)
	_tq[Q.CZ] = 16.0 - 3.2 * crouch + 8.0 * launch
	_tq[Q.PITCH] = lerpf(1.08, 0.82, up) * (1.0 - launch) + 0.3 * launch
	_tq[Q.HEAD_P] = -0.2 - 0.38 * crouch + 0.3 * launch
	_tq[Q.HEAD_Y] = 0.12 * sin(_time * 4.0) * (1.0 - up)
	_tq[Q.GAPE] = 0.55 * smoothstep(0.25, 0.7, t)
	_tq[Q.NX] = lerpf(10.5, 9.0, launch)
	_tq[Q.NZ] = lerpf(-0.6, 1.4, launch) - 1.2 * crouch
	var phase_k: float = lerpf(0.0, 0.2, launch)
	_set_wings(0.55, -1.22, -2.25, -0.55, -2.75, -0.8, 0.0, 0.22)
	_lerp_wings(0.12, 0.95, 0.35, 0.7, 0.55, 0.35, 0.0, 1.0, up)
	# the same blend from the cloak to the raised wings happens in the bird frame, so the unfold keeps the body frame mix above
	if launch > 0.0:
		var saved: PackedFloat32Array = _tq.duplicate()
		_flap_wings(phase_k, false)
		var flap_vals: PackedFloat32Array = _tq.duplicate()
		_tq = saved
		for o: int in [Q.RU_Y, Q.LU_Y]:
			for n: int in 8:
				_tq[o + n] = lerpf(saved[o + n], flap_vals[o + n], launch)
	_tq[Q.TAIL_S] = lerpf(0.2, 0.85, unfold)
	_tq[Q.TAIL_P] = lerpf(0.55, 0.15, unfold)
	_tq[Q.GRIP] = 1.0 - smoothstep(0.84, 0.96, t)
	_tq[Q.FOOT_X] = lerpf(0.0, -7.0, smoothstep(0.88, 1.0, t))
	_tq[Q.FOOT_Z] = lerpf(-15.0, -5.5, smoothstep(0.88, 1.0, t))
	_tq[Q.FOOT_SP] = 2.8
	_tq[Q.TOES] = lerpf(0.8, 1.0, launch)
	_tq[Q.TREM] = smoothstep(0.15, 0.9, t) * (1.0 - launch)
	_tq[Q.VEIN] = 1.0 + 0.9 * up
	_tq[Q.EYE] = 1.0 + 0.8 * up
	if not _beat_t and t >= 0.9 and dt > 0.0:
		_beat_t = true
		wing_beat.emit(true)


func _pose_flying(dt: float) -> void:
	_advance_flap(dt, FLY_RATE, true)
	var e: float = _flap_wings(_flap, false)
	_tq[Q.WF] = 0.0
	_tq[Q.LEN] = 1.0
	_tq[Q.CZ] = 21.0 + 1.6 * sin(TAU * (_flap - 0.12))
	_tq[Q.PITCH] = _pitch_s
	_tq[Q.ROLL] = _roll_s
	_tq[Q.NX] = 9.0
	_tq[Q.NZ] = 1.6
	_tq[Q.HEAD_P] = _pitch_s * 0.3 - 0.05
	_tq[Q.HEAD_Y] = 0.0
	_tq[Q.TAIL_S] = 0.85
	_tq[Q.TAIL_P] = 0.12 * e - _pitch_s * 0.5
	_tq[Q.GRIP] = 0.0
	_tq[Q.FOOT_X] = -7.0
	_tq[Q.FOOT_Z] = -5.4
	_tq[Q.FOOT_SP] = 2.4
	_tq[Q.TOES] = 1.0
	_tq[Q.VEIN] = 1.15
	_tq[Q.EYE] = 1.0


func _pose_hover(dt: float) -> void:
	_advance_flap(dt, HOVER_RATE, true)
	var e: float = _flap_wings(_flap, true)
	_tq[Q.WF] = 0.0
	_tq[Q.LEN] = 1.0
	_tq[Q.CZ] = 22.0 + 2.0 * sin(TAU * (_flap - 0.1)) + 0.6 * sin(_time * 1.3)
	_tq[Q.PITCH] = 0.95 + 0.05 * e
	_tq[Q.ROLL] = 0.06 * sin(_time * 0.9)
	_tq[Q.NX] = 9.8
	_tq[Q.NZ] = -0.3
	_tq[Q.HEAD_P] = -0.12 + 0.18 * sin(_time * 0.6)
	_tq[Q.HEAD_Y] = 0.55 * sin(_time * 0.55) + 0.2 * sin(_time * 1.4)
	_tq[Q.HEAD_R] = 0.15 * sin(_time * 0.8)
	_tq[Q.TAIL_S] = 0.9
	_tq[Q.TAIL_P] = 0.5 - 0.1 * e
	_tq[Q.GRIP] = 0.0
	_tq[Q.FOOT_X] = 3.0
	_tq[Q.FOOT_Z] = -13.0
	_tq[Q.FOOT_SP] = 3.6
	_tq[Q.TOES] = 0.1
	_tq[Q.VEIN] = 1.1


func _pose_landing(t: float) -> void:
	if not _beat_a:
		_beat_a = true
		wing_beat.emit(false)
	if not _beat_b and t >= 0.3:
		_beat_b = true
		wing_beat.emit(true)
	var flare: float = smoothstep(0.0, 0.3, t)
	var settle: float = smoothstep(0.6, 1.0, t)
	var touch: float = clampf((t - 0.74) / 0.26, 0.0, 1.0)
	_tq[Q.WF] = settle
	_tq[Q.LEN] = lerpf(1.0, 0.95, settle)
	_set_wings(0.55, 0.85, 0.8, 0.7, 0.9, 0.55, 0.0, 1.0)
	_lerp_wings(0.55, -1.22, -2.25, -0.55, -2.75, -0.8, 0.0, 0.22, settle)
	_tq[Q.PITCH] = lerpf(0.25, 1.08, smoothstep(0.0, 0.62, t)) + 0.1 * sin(PI * touch)
	_tq[Q.CZ] = lerpf(24.0, 16.0, smoothstep(0.0, 0.74, t)) - 3.0 * sin(PI * touch * 0.9) * (1.0 - touch * 0.3)
	_tq[Q.NX] = lerpf(9.0, 10.5, flare)
	_tq[Q.NZ] = lerpf(1.5, -0.6, flare)
	_tq[Q.HEAD_P] = lerpf(0.05, -0.2, flare) + 0.1 * sin(PI * touch)
	_tq[Q.TAIL_S] = lerpf(1.0, 0.2, settle)
	_tq[Q.TAIL_P] = lerpf(0.5, 0.55, settle)
	_tq[Q.GRIP] = smoothstep(0.52, 0.78, t)
	_tq[Q.FOOT_X] = 6.0
	_tq[Q.FOOT_Z] = -13.0
	_tq[Q.FOOT_SP] = 3.5
	_tq[Q.TOES] = lerpf(0.1, 0.8, smoothstep(0.7, 1.0, t))
	_tq[Q.VEIN] = 1.0 + 0.5 * (1.0 - settle)
	_tq[Q.GAPE] = 0.3 * sin(PI * flare) * (1.0 - settle)


func _pose_stagger(t: float, breath: float) -> void:
	var k: float = sin(minf(1.0, t * 1.6) * PI) * (1.0 - t * 0.3)
	var shake: float = sin(_time * 62.0) * (1.0 - t)
	_tq[Q.CZ] = 16.0 - 3.0 * k + breath * 0.2
	_tq[Q.PITCH] = 1.08 + 0.42 * k
	_tq[Q.HEAD_P] = -0.2 + 0.7 * k
	_tq[Q.HEAD_Y] = 0.55 * shake
	_tq[Q.HEAD_R] = 0.3 * k * sin(_time * 40.0)
	_tq[Q.GAPE] = 0.9 * k
	_tq[Q.TREM] = 1.0 - t
	_tq[Q.VEIN] = 1.0 + 0.9 * (1.0 - t)
	_tq[Q.EYE] = 1.0 + 1.6 * (1.0 - t * 0.6)
	for o: int in [Q.RU_Y, Q.LU_Y]:
		_tq[o + 3] += shake * 0.07
		_tq[o + 5] += shake * 0.05


func _pose_crashed(t: float) -> void:
	var fall: float = smoothstep(0.0, 0.85, t)
	var bounce: float = sin(PI * clampf((t - 0.85) / 0.15, 0.0, 1.0))
	_tq[Q.ROLL] = DEAD_ROLL * (1.0 - pow(1.0 - fall, 2.0))
	_tq[Q.PITCH] = lerpf(0.6, 0.1, fall) + 0.5 * sin(t * 15.0) * (1.0 - fall)
	_tq[Q.CZ] = lerpf(22.0, 6.2, pow(fall, 1.6)) + 3.4 * bounce
	var slack: float = smoothstep(0.55, 0.95, t)
	_tq[Q.WF] = slack
	_tq[Q.LEN] = 1.0
	var flail: float = (1.0 - slack)
	for o: int in [Q.RU_Y, Q.LU_Y]:
		var ph: float = 0.0 if o == Q.RU_Y else 1.7
		_tq[o] = lerpf(0.3 + 0.3 * sin(t * 23.0 + ph), 0.35, slack)
		_tq[o + 1] = lerpf(0.9 * sin(t * 31.0 + ph), 0.04, slack)
		_tq[o + 2] = lerpf(0.4 + 0.3 * sin(t * 26.0 + ph), 0.7, slack)
		_tq[o + 3] = lerpf(0.8 * sin(t * 28.0 + ph + 0.4), 0.02, slack)
		_tq[o + 4] = lerpf(0.6, 0.9, slack)
		_tq[o + 5] = lerpf(0.6 * sin(t * 25.0 + ph), 0.0, slack)
		_tq[o + 7] = lerpf(1.0, 0.85, slack) * (0.6 + 0.4 * flail)
	_tq[Q.GRIP] = 0.0
	_tq[Q.FOOT_X] = -3.0 + 2.0 * sin(t * 19.0)
	_tq[Q.FOOT_Z] = -7.0
	_tq[Q.FOOT_SP] = 3.2
	_tq[Q.HEAD_P] = lerpf(0.4, -0.3, fall) + 0.2 * sin(t * 17.0) * flail
	_tq[Q.HEAD_Y] = 0.5 * sin(t * 13.0) * flail
	_tq[Q.TAIL_S] = 0.7
	_tq[Q.TAIL_P] = 0.0
	_tq[Q.NX] = 9.0
	_tq[Q.NZ] = 0.5
	_tq[Q.GAPE] = 0.6 * flail
	_tq[Q.VEIN] = 1.2 * (1.0 - 0.4 * slack)
	_tq[Q.TREM] = 0.3 * flail


## Tired on the pillar: crouched low, the wings hang open and heavy, the head sinks, he heaves for breath, the lights are dim.
func _pose_spent(breath: float) -> void:
	_pose_perched(breath)
	_tq[Q.CZ] = 12.6 + breath * 0.9
	_tq[Q.PITCH] = 1.22 + breath * 0.03
	_tq[Q.HEAD_P] = 0.42 + 0.06 * breath
	_tq[Q.HEAD_Y] = 0.28 * sin(_time * 0.4)
	_tq[Q.GAPE] = 0.26 + 0.2 * maxf(breath, 0.0)
	_tq[Q.TREM] = 0.1
	_tq[Q.VEIN] = 0.55 + 0.1 * breath
	_tq[Q.EYE] = 0.5


## Down on the ground after the pillar broke: on his side like the dead, but alive: he heaves, twitches, the veins flicker.
func _pose_downed(breath: float) -> void:
	_tq[Q.ROLL] = DEAD_ROLL
	_tq[Q.PITCH] = 0.1
	_tq[Q.CZ] = 5.6 + 0.45 * breath
	_tq[Q.WF] = 1.0
	_tq[Q.LEN] = 1.0
	var twitch: float = 0.03 * sin(_time * 9.0) * maxf(0.0, sin(_time * 0.7))
	_set_wings(0.35 + twitch, 0.04, 0.7, 0.02 + twitch, 0.9, 0.0, 0.0, 0.85)
	_tq[Q.LU_E] = -0.34
	_tq[Q.LF_E] = -0.2
	_tq[Q.LH_E] = -0.1
	_tq[Q.GRIP] = 0.0
	_tq[Q.FOOT_X] = -3.0
	_tq[Q.FOOT_Z] = -7.0
	_tq[Q.FOOT_SP] = 3.4
	_tq[Q.HEAD_P] = -0.32 + 0.05 * breath
	_tq[Q.HEAD_Y] = 0.3 + 0.15 * sin(_time * 0.5)
	_tq[Q.GAPE] = 0.35 + 0.25 * maxf(breath, 0.0)
	_tq[Q.TAIL_S] = 0.7
	_tq[Q.TAIL_P] = 0.0
	_tq[Q.NX] = 9.0
	_tq[Q.NZ] = 0.2
	_tq[Q.TREM] = 0.12
	_tq[Q.VEIN] = 0.7 + 0.15 * breath
	_tq[Q.EYE] = 0.7


## The judge: upright on the pillar and not tired at all. Chest out, wings flung up and out like the arches of a cathedral (they stay
## raised in the bird's own frame whatever the body does) and fanned wide, shivering a little, head thrown back, the beak open on the scream
## with the throat lit, talons gripping, the tail spread. The fight adds `charge` (kind 3, cold white) on top.
func _pose_judge(breath: float) -> void:
	_tq[Q.CZ] = 18.4 + breath * 0.4
	_tq[Q.PITCH] = 0.55 + breath * 0.012
	_tq[Q.NX] = 11.0
	_tq[Q.NZ] = 0.9
	_tq[Q.HEAD_P] = 0.4 + 0.04 * breath
	_tq[Q.HEAD_Y] = 0.1 * sin(_time * 0.5)
	_tq[Q.HEAD_R] = 0.05 * sin(_time * 0.7)
	_tq[Q.GAPE] = 0.55 + 0.04 * sin(_time * 3.1)
	_tq[Q.WF] = 1.0
	_tq[Q.LEN] = 1.0
	for o: int in [Q.RU_Y, Q.LU_Y]:
		var ph: float = 0.0 if o == Q.RU_Y else 1.9
		var w: float = 0.028 * sin(_time * 9.0 + ph)
		_tq[o] = 0.2
		_tq[o + 1] = 0.42 + w
		_tq[o + 2] = 0.2
		_tq[o + 3] = 0.78 + w
		_tq[o + 4] = 0.3
		_tq[o + 5] = 1.05 + w * 1.4
		_tq[o + 6] = 1.4 * (1.0 if o == Q.RU_Y else -1.0) ## turned face-on, so the blades fan out sideways and up
		_tq[o + 7] = 1.0
	_tq[Q.TAIL_S] = 1.0
	_tq[Q.TAIL_P] = 0.6
	_tq[Q.GRIP] = 1.0
	_tq[Q.TREM] = 0.14
	_tq[Q.VEIN] = 1.9 + 0.1 * breath
	_tq[Q.EYE] = 1.9


## The fight's wishes on top of any pose: raised wings, charging feathers, tiredness.
func _apply_action() -> void:
	var tired: float = maxf(fatigue, 1.0 if _pose == Pose.SPENT else 0.0)
	if tired > 0.001 and _pose != Pose.DOWNED:
		var k: float = smoothstep(0.0, 1.0, tired)
		for o: int in [Q.RU_Y, Q.LU_Y]:
			_tq[o] = lerpf(_tq[o], 0.32, k)
			_tq[o + 1] = lerpf(_tq[o + 1], -0.3, k)
			_tq[o + 2] = lerpf(_tq[o + 2], 0.12, k)
			_tq[o + 3] = lerpf(_tq[o + 3], -0.75, k)
			_tq[o + 4] = lerpf(_tq[o + 4], 0.1, k)
			_tq[o + 5] = lerpf(_tq[o + 5], -1.0, k)
			_tq[o + 6] = lerpf(_tq[o + 6], 0.0, k)
			_tq[o + 7] = lerpf(_tq[o + 7], 0.55, k)
		_tq[Q.WF] = lerpf(_tq[Q.WF], 1.0, k)
		if _pose != Pose.SPENT:
			_tq[Q.HEAD_P] += 0.45 * k
			_tq[Q.CZ] -= 2.0 * k
			_tq[Q.PITCH] += 0.14 * k
			_tq[Q.CZ] += 0.8 * k * sin(_time * 3.4)
		_tq[Q.TREM] = maxf(_tq[Q.TREM], 0.1 * k)
	for si: int in 2:
		var raised: float = raise_r if si == 0 else raise_l
		if raised <= 0.001:
			continue
		var o: int = Q.RU_Y if si == 0 else Q.LU_Y
		var k2: float = smoothstep(0.0, 1.0, raised)
		_tq[o] = lerpf(_tq[o], 0.18, k2)
		_tq[o + 1] = lerpf(_tq[o + 1], 1.32, k2)
		_tq[o + 2] = lerpf(_tq[o + 2], 0.3, k2)
		_tq[o + 3] = lerpf(_tq[o + 3], 1.22, k2)
		_tq[o + 4] = lerpf(_tq[o + 4], 0.45, k2)
		_tq[o + 5] = lerpf(_tq[o + 5], 1.0, k2)
		_tq[o + 6] = lerpf(_tq[o + 6], 0.0, k2)
		_tq[o + 7] = lerpf(_tq[o + 7], 1.0, k2)
	_tq[Q.EYE] += charge * (1.1 if charge_kind == 1 else 0.6)
	_tq[Q.VEIN] += charge * 0.8
	_tq[Q.TREM] = maxf(_tq[Q.TREM], charge * 0.18)


func _pose_dead(t: float) -> void:
	_tq[Q.ROLL] = DEAD_ROLL
	_tq[Q.PITCH] = 0.1
	_tq[Q.CZ] = lerpf(6.2, 5.3, smoothstep(0.1, 0.9, t))
	_tq[Q.WF] = 1.0
	_tq[Q.LEN] = 1.0
	var tw: float = (1.0 - t) * sin(_time * 34.0) * 0.025
	_set_wings(0.35 + tw, 0.04, 0.7, 0.02 + tw, 0.9, 0.0, 0.0, 0.85)
	_tq[Q.LU_E] = -0.34
	_tq[Q.LF_E] = -0.2
	_tq[Q.LH_E] = -0.1
	_tq[Q.GRIP] = 0.0
	_tq[Q.FOOT_X] = -3.0
	_tq[Q.FOOT_Z] = -7.0
	_tq[Q.FOOT_SP] = 3.4
	_tq[Q.HEAD_P] = -0.32
	_tq[Q.HEAD_Y] = 0.3
	_tq[Q.GAPE] = 0.55 * smoothstep(0.0, 0.3, t)
	_tq[Q.TAIL_S] = 0.7
	_tq[Q.TAIL_P] = 0.0
	_tq[Q.NX] = 9.0
	_tq[Q.NZ] = 0.2
	_tq[Q.TREM] = (1.0 - smoothstep(0.0, 0.6, t)) * 0.5
	_tq[Q.VEIN] = 1.0


func _update_eyes(dt: float) -> void:
	var calm: bool = _pose in [Pose.PERCHED, Pose.SPENT, Pose.DOWNED]
	for i: int in EYES:
		if _eye_blink[i] > 0.0:
			_eye_blink[i] = maxf(0.0, _eye_blink[i] - dt)
		_eye_cd[i] -= dt
		if _eye_cd[i] <= 0.0:
			if calm:
				if _rng.randf() < 0.6:
					_eye_blink[i] = _rng.randf_range(0.1, 0.2)
				else:
					_eye_narrow[i] = _rng.randf_range(0.25, 0.6)
			_eye_cd[i] = _rng.randf_range(2.0, 6.5)
		_eye_narrow[i] = maxf(0.0, _eye_narrow[i] - dt)
		var target: float = 0.0 if _eye_blink[i] > 0.0 else (0.45 if _eye_narrow[i] > 0.0 else 1.0)
		_eye_open[i] = lerpf(_eye_open[i], target, 1.0 - exp(-24.0 * dt)) if dt > 0.0 else target


func _stutter(t: float, kill: float, salt: float) -> float:
	if t >= kill:
		return 0.0
	if t < kill - 0.22:
		return 1.0
	var n: int = int(_time * 19.0 + salt * 7.0)
	return 1.0 if _noise(n, salt) > 0.45 else 0.15


func _update_life(t: float) -> void:
	if _pose != Pose.DEAD:
		_life_wing = [1.0, 1.0]
		_life_core = 1.0
		_life_eye = PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
		return
	var kills: Array[float] = [0.12, 0.2, 0.28, 0.36, 0.44, 0.52, 0.58, 0.6]
	for i: int in EYES:
		_life_eye[i] = _stutter(t, kills[i], float(i) + 1.0)
	_life_wing = [_stutter(t, 0.62, 11.0), _stutter(t, 0.72, 12.0)]
	_life_core = _stutter(t, 0.92, 13.0)


# --- geometry ------------------------------------------------------------------------------------------------------


func _new_part(depth: float, draw_call: Callable, glow_call: Callable = Callable(), sp: Span = null) -> Part:
	var part: Part = Part.new()
	part.depth = depth
	part.order = _order
	_order += 1
	part.draw = draw_call
	part.glow = glow_call
	part.span = sp
	_parts.append(part)
	return part


func _surf(x: float, ang: float, off: float = 0.6) -> Vector3:
	var r: float = _torso_r(x) + off
	return Vector3(x, r * sin(ang), _torso_z(x) - r * cos(ang))


func _torso_r(x: float) -> float:
	return _tab(x, TORSO_X, TORSO_R)


func _torso_z(x: float) -> float:
	return _tab(x, TORSO_X, TORSO_Z)


func _tab(x: float, xs: Array[float], ys: Array[float]) -> float:
	if x <= xs[0]:
		return ys[0]
	for i: int in xs.size() - 1:
		if x <= xs[i + 1]:
			var u: float = (x - xs[i]) / (xs[i + 1] - xs[i])
			return lerpf(ys[i], ys[i + 1], smoothstep(0.0, 1.0, u) * 0.6 + 0.4 * u)
	return ys[xs.size() - 1]


func _build(dt: float, t: float) -> void:
	_parts.clear()
	_order = 0
	_wings.clear()
	_cp = cos(_q[Q.PITCH])
	_sp = sin(_q[Q.PITCH])
	_cr = cos(_q[Q.ROLL])
	_sr = sin(_q[Q.ROLL])
	var trem: float = _q[Q.TREM]
	var shake: Vector3 = Vector3(sin(_time * 47.0), sin(_time * 53.0 + 1.0), sin(_time * 61.0 + 2.0)) * trem * 0.45
	_center = Vector3(_q[Q.CX], _q[Q.CY], _q[Q.CZ]) + shake
	_view = Vector3(0.81 * sin(_heading), 0.81 * cos(_heading), 0.59)
	_core3 = _bp(_surf(3.6, 0.0, 0.9))
	_build_torso()
	_build_head()
	_build_tail(dt)
	_build_legs()
	_build_harness()
	_build_wing_pair(dt)
	_orn_alive = 1.0 - smoothstep(0.02, 0.3, t) if _pose == Pose.DEAD else 1.0
	if _corr > 0.03 and _orn_alive > 0.02:
		_build_splinters(dt)
		_build_halo()
	_bf_ready = true
	_td_floor = 0.4 if _pose in [Pose.PERCHED, Pose.DEAD, Pose.CRASHED, Pose.SPENT, Pose.DOWNED, Pose.JUDGE] or (_pose == Pose.LANDING and t > 0.8) else -1000.0


func _build_torso() -> void:
	var pts: Array[Vector3] = []
	var rad: Array[float] = []
	var x: float = -12.5
	while x <= 13.01:
		pts.append(_bp(Vector3(x, 0.0, _torso_z(x))))
		rad.append(_torso_r(x))
		x += 1.9
	_torso_discs = _discs_along(pts, rad)
	_torso_depths = PackedFloat32Array()
	for i: int in pts.size():
		_torso_depths.append(_depth(pts[i]))
	var sp: Span = _span_discs(_torso_discs)
	_new_part(_depth(_center), _draw_torso.bind(sp), Callable(), sp)


func _draw_torso(sp: Span) -> void:
	_paint_tube(_body, _torso_discs, PAL_FLESH, sp)
	# shoulder-blade lamellae over the back and a keel ridge on the breast
	var dorsal: Vector3 = _rot(Vector3(0, 0, 1))
	if dorsal.dot(_view) > -0.1:
		for k: int in 3:
			var xk: float = 3.0 - float(k) * 4.0
			var base: Vector3 = _bp(Vector3(xk, 0.0, _torso_z(xk) + _torso_r(xk) * 0.8))
			var tip: Vector3 = base + _rot(Vector3(-5.5, 0.0, 2.2))
			_blade_quick(base, tip, 2.4, PAL_ROCK, dorsal)


## A small flat blade given by its two ends (spikes, crest, collar): outline, base tone, lit half and a rim.
func _blade_quick(base3: Vector3, tip3: Vector3, width: float, pal: Array[Color], normal: Vector3) -> void:
	var dir: Vector3 = tip3 - base3
	var wd: Vector3 = dir.cross(normal)
	if wd.length() < 0.001:
		wd = Vector3(0, 1, 0)
	wd = wd.normalized()
	var left: PackedVector2Array = PackedVector2Array()
	var right: PackedVector2Array = PackedVector2Array()
	for i: int in U_S.size():
		var pos: Vector3 = base3 + dir * U_S[i]
		var hw: float = width * 0.5 * HW_S[i]
		left.append(_p(pos - wd * hw))
		right.append(_p(pos + wd * hw))
	var poly: PackedVector2Array = left.duplicate()
	for i: int in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	var sp: Span = _span_poly(poly)
	_paint_outline(_body, sp, _tint(pal[0]))
	_paint(_body, sp, _tint(pal[2]))
	_paint(_body, _span_poly(_lit_poly(left, right)), _tint(pal[3]))
	_paint_rim(_body, sp, _tint(pal[4], 0.9))


func _lit_poly(left: PackedVector2Array, right: PackedVector2Array) -> PackedVector2Array:
	var sum_l: float = 0.0
	var sum_r: float = 0.0
	for i: int in left.size():
		sum_l += left[i].x + left[i].y
		sum_r += right[i].x + right[i].y
	var edge: PackedVector2Array = left if sum_l <= sum_r else right
	var other: PackedVector2Array = right if sum_l <= sum_r else left
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in range(0, edge.size() - 1):
		out.append(edge[i])
	for i: int in range(edge.size() - 2, -1, -1):
		out.append(edge[i].lerp(other[i], 0.5))
	return out


func _build_head() -> void:
	var yaw: float = _q[Q.HEAD_Y]
	var pit: float = _q[Q.HEAD_P]
	var roll: float = _q[Q.HEAD_R]
	var fwd: Vector3 = Vector3(cos(yaw) * cos(pit), sin(yaw) * cos(pit), sin(pit))
	var side: Vector3 = Vector3(-sin(yaw), cos(yaw), 0.0)
	var up: Vector3 = Vector3(-cos(yaw) * sin(pit), -sin(yaw) * sin(pit), cos(pit))
	_hf = fwd
	_hs = side * cos(roll) + up * sin(roll)
	_hu = up * cos(roll) - side * sin(roll)
	var base: Vector3 = _bp(Vector3(13.0, 0.0, 3.0))
	_head_c = base + _rot(Vector3(_q[Q.NX], _q[Q.NY], _q[Q.NZ]))
	# neck: a bezier from inside the chest to the back of the skull
	var p0: Vector3 = _bp(Vector3(10.5, 0.0, 2.0))
	var p3: Vector3 = _head_c - _hf * 2.2
	var p1: Vector3 = p0 + _rot(Vector3(4.0, 0.0, 1.8))
	var p2: Vector3 = p3 - _hf * 4.5
	var pts: Array[Vector3] = []
	var rad: Array[float] = []
	for i: int in 6:
		var u: float = float(i) / 5.0
		var w: float = 1.0 - u
		pts.append(p0 * w * w * w + p1 * 3.0 * w * w * u + p2 * 3.0 * w * u * u + p3 * u * u * u)
		rad.append(lerpf(4.6, 3.4, u))
	var neck_discs: PackedVector3Array = _discs_along(pts, rad)
	var nsp: Span = _span_discs(neck_discs)
	_new_part(_depth(pts[3]) + 0.2, _draw_neck.bind(neck_discs, nsp), Callable(), nsp)
	# skull
	var skull: PackedVector3Array = _discs_along([_hp(-1.4, 0.0, 0.0), _hp(1.0, 0.0, -0.2), _hp(2.8, 0.0, -0.8)], [4.3, 4.1, 3.3])
	var ssp: Span = _span_discs(skull)
	var head_depth: float = _depth(_head_c)
	_new_part(head_depth + 0.6, _draw_skull.bind(skull, ssp), _glow_head, ssp)
	# beak: upper hooked, lower hangs by the gape and is joined by tendon threads
	var gape: float = _q[Q.GAPE]
	var upper_pts: Array[Vector3] = [_hp(2.8, 0.0, -0.4), _hp(5.4, 0.0, -0.8), _hp(8.0, 0.0, -1.6), _hp(10.0, 0.0, -2.8), _hp(10.8, 0.0, -4.4)]
	var upper: PackedVector3Array = _discs_along(upper_pts, [2.9, 2.5, 1.9, 1.3, 0.6])
	var usp: Span = _span_discs(upper)
	_beak_tip = _p(upper_pts[4])
	var lower_pts: Array[Vector3] = [_hp(2.6, 0.0, -2.2), _hp(2.6 + 2.4 * cos(gape), 0.0, -2.2 - 2.4 * sin(gape)), _hp(2.6 + 4.8 * cos(gape), 0.0, -2.3 - 4.8 * sin(gape)), _hp(2.6 + 6.4 * cos(gape), 0.0, -2.5 - 6.4 * sin(gape))]
	var lower: PackedVector3Array = _discs_along(lower_pts, [1.8, 1.5, 1.1, 0.6])
	var lsp: Span = _span_discs(lower)
	var beak_depth: float = _depth(_hp(6.0, 0.0, -1.5))
	_new_part(beak_depth + 0.5, _draw_lower.bind(lower, lsp, upper_pts, lower_pts), _glow_mouth, lsp)
	_new_part(beak_depth + 0.65, _draw_upper.bind(upper, usp), Callable(), usp)
	# brow plates over the eyes
	for sd: float in [-1.0, 1.0]:
		var bp: Array[Vector3] = [_hp(2.6, sd * 3.3, 2.7), _hp(0.4, sd * 3.7, 3.0), _hp(-1.8, sd * 3.5, 2.6)]
		var brow: PackedVector3Array = _discs_along(bp, [1.3, 1.5, 1.1])
		var bsp: Span = _span_discs(brow)
		_new_part(_depth(_hp(0.0, sd * 3.5, 2.8)) + 0.7, _draw_rock_tube.bind(brow, bsp), Callable(), bsp)
	# crest of three swept-back blades
	for k: int in 3:
		var sd2: float = (float(k) - 1.0) * 1.9
		var cbase: Vector3 = _hp(-2.2, sd2 * 0.7, 2.6)
		var ctip: Vector3 = _hp(-9.2 + absf(sd2), sd2 * 1.8, 3.6 + (2.2 if k == 1 else 0.6))
		_new_part(_depth((cbase + ctip) * 0.5) + 0.3 - 0.01 * absf(sd2), _draw_crest.bind(cbase, ctip, 3.0))


func _hp(a: float, b: float, c: float) -> Vector3:
	return _head_c + _hf * a + _hs * b + _hu * c


func _draw_neck(discs: PackedVector3Array, sp: Span) -> void:
	_paint_tube(_body, discs, PAL_FLESH, sp)
	# collar lamellae ringing the base of the neck
	var dorsal: Vector3 = _rot(Vector3(0, 0, 1))
	if dorsal.dot(_view) > -0.1:
		for k: int in 5:
			var ang: float = (float(k) - 2.0) * 0.55
			var base: Vector3 = _bp(Vector3(11.0, 0.0, 2.0)) + _rot(Vector3(0.0, sin(ang) * 4.3, cos(ang) * 4.3))
			var tip: Vector3 = base + _rot(Vector3(-1.5, sin(ang) * 3.0, cos(ang) * 3.0 - 1.0))
			_blade_quick(base, tip, 2.4, PAL_ROCK, dorsal)


func _draw_skull(discs: PackedVector3Array, sp: Span) -> void:
	_paint_tube(_body, discs, PAL_FLESH, sp)
	for k: int in EYES:
		if k >= 6 and _pop_age < 0.0:
			continue
		var vis: float = _eye_vis_k(k)
		if vis > 0.3:
			var e: Vector2 = _p(_eye_pos_k(k))
			_body.draw_rect(Rect2((e + Vector2(-2, -1)).round(), Vector2(5, 3)), _tint(OUTLINE, vis))


func _eye_side(k: int) -> float:
	return -1.0 if k < 3 or k == 6 else 1.0


func _eye_pos(side_i: float, row: int) -> Vector3:
	if row == 3:
		return _hp(1.1, side_i * 2.3, 3.7) ## the brow eyes of phase 2
	return _hp(1.9 - 0.5 * float(row == 2), side_i * 3.15, 2.1 - 2.1 * float(row))


func _eye_pos_k(k: int) -> Vector3:
	return _eye_pos(_eye_side(k), 3 if k >= 6 else k % 3)


func _eye_vis_k(k: int) -> float:
	if k >= 6:
		var n: Vector3 = (_hf * 0.5 + _hs * _eye_side(k) * 0.45 + _hu * 0.75).normalized()
		return smoothstep(-0.05, 0.4, n.dot(_view))
	return _eye_vis(_eye_side(k))


func _eye_vis(side_i: float) -> float:
	var n: Vector3 = (_hf * 0.45 + _hs * side_i * 0.9 + _hu * 0.1).normalized()
	return smoothstep(-0.05, 0.4, n.dot(_view))


## The brow eyes pop open: a quick flare that settles.
func _pop_k() -> float:
	if _pop_age < 0.0:
		return 0.0
	return minf(1.0, _pop_age / 0.07) * (1.0 + 1.1 * exp(-_pop_age * 7.0))


func _draw_rock_tube(discs: PackedVector3Array, sp: Span) -> void:
	_paint_tube(_body, discs, PAL_ROCK, sp)


func _draw_upper(discs: PackedVector3Array, sp: Span) -> void:
	_paint_tube(_body, discs, PAL_BEAK, sp)
	var tip: Vector2 = _beak_tip
	_body.draw_rect(Rect2(tip.round() + Vector2(-1, 0), Vector2(1, 1)), _tint(ROCK3))


func _draw_lower(discs: PackedVector3Array, sp: Span, upper_pts: Array[Vector3], lower_pts: Array[Vector3]) -> void:
	var gape: float = _q[Q.GAPE]
	if gape > 0.12:
		# tendon threads between the halves, a little slack
		for k: int in 3:
			var u: float = 0.3 + float(k) * 0.28
			var a: Vector2 = _p(upper_pts[0].lerp(upper_pts[2], u))
			var b: Vector2 = _p(lower_pts[0].lerp(lower_pts[3], u * 0.9))
			var mid: Vector2 = a.lerp(b, 0.5) + Vector2(sin(_time * 7.0 + float(k) * 2.0) * 0.6, 0.4)
			_seg(_body, a, mid, 1.0, 1.0, _tint(OUTLINE))
			_seg(_body, mid, b, 1.0, 1.0, _tint(OUTLINE))
	_paint_tube(_body, discs, PAL_BEAK, sp)


func _draw_crest(base: Vector3, tip: Vector3, width: float) -> void:
	_blade_quick(base, tip, width, PAL_ROCK, _hu)


func _build_tail(dt: float) -> void:
	var count: int = TAIL_LEN.size()
	if _tf.size() != count:
		_tf.resize(count)
		_bf_ready = false
	var spread: float = _q[Q.TAIL_S]
	var tp: float = _q[Q.TAIL_P]
	var nrm: Vector3 = _rot(Vector3(0, 0, 1))
	for k: int in count:
		var yaw: float = (float(k) - 2.0) * 0.3 * spread
		var raw_local: Vector3 = Vector3(-cos(yaw) * cos(tp), sin(yaw) * cos(tp), sin(tp))
		var raw: Vector3 = _rot(raw_local).normalized()
		if not _bf_ready:
			_tf[k] = raw
		else:
			_tf[k] = _tf[k].lerp(raw, 1.0 - exp(-15.0 * dt)).normalized()
		var base: Vector3 = _bp(Vector3(-11.5, (float(k) - 2.0) * 0.9, 0.0))
		var blade: Blade = _make_blade(base, raw, _tf[k], nrm, TAIL_LEN[k], 4.6)
		_new_part(blade.depth - 0.4 - 0.01 * float(absi(k - 2)), _draw_blade.bind(blade, true), Callable(), blade.span)


## One flat blade: flexible (its root follows `raw`, its tip the lagging `filt`), as a polygon with its screen-space edges and span.
func _make_blade(base: Vector3, raw: Vector3, filt: Vector3, nrm: Vector3, length: float, width: float) -> Blade:
	var b: Blade = Blade.new()
	var wd: Vector3 = filt.cross(nrm)
	if wd.length() < 0.001:
		wd = Vector3(0, 1, 0)
	wd = wd.normalized()
	for i: int in U_S.size():
		var u: float = U_S[i]
		var dir: Vector3 = raw.lerp(filt, smoothstep(0.0, 1.0, u))
		dir = dir.normalized() if dir.length() > 0.001 else filt
		var pos: Vector3 = base + dir * (length * u)
		var hw: float = width * 0.5 * HW_S[i]
		b.left.append(_p(pos - wd * hw))
		b.right.append(_p(pos + wd * hw))
		b.center.append(_p(pos))
	b.poly = b.left.duplicate()
	for i: int in range(b.right.size() - 1, -1, -1):
		b.poly.append(b.right[i])
	b.span = _span_poly(b.poly)
	var sum_l: float = 0.0
	var sum_r: float = 0.0
	for i: int in b.left.size():
		sum_l += b.left[i].x + b.left[i].y
		sum_r += b.right[i].x + b.right[i].y
	var edge: PackedVector2Array = b.left if sum_l <= sum_r else b.right
	for i: int in range(1, edge.size() - 1):
		b.lit_edge.append(edge[i])
	var far: PackedVector2Array = b.right if sum_l <= sum_r else b.left
	for i: int in range(1, far.size() - 1):
		b.far_edge.append(far[i])
	b.dorsal = nrm.dot(_view)
	b.tip = b.center[b.center.size() - 1]
	b.depth = _depth(base + filt * length * 0.5)
	b.width = width
	return b


func _draw_blade(blade: Blade, outline: bool = false) -> void:
	if blade.hidden:
		return
	var seen_top: bool = blade.dorsal >= 0.0
	var dk: float = _corr * 0.8 ## phase 2: the basalt turns darker
	var ka: float = lerpf(1.0, 0.3, blade.light) ## a blade of light keeps only a faint dark underlay, the light is drawn in the glow
	var c_base: Color = (ROCK1 if seen_top else ROCK0).lerp(ROCK0.darkened(0.3), dk)
	var c_lit: Color = (ROCK2 if seen_top else ROCK1).lerp(ROCK1.darkened(0.1), dk)
	var c_edge: Color = ROCK3.lerp(ROCK2, dk * 0.8)
	var sp: Span = blade.span
	if outline:
		_paint_outline(_body, sp, _tint(OUTLINE))
	_paint(_body, sp, _tint(c_base, ka))
	var lit: PackedVector2Array = _lit_poly(blade.left, blade.right)
	if lit.size() >= 3:
		_paint(_body, _span_poly(lit), _tint(c_lit, ka))
	_paint_shade(_body, sp, _tint(ROCK0, 0.9 * ka))
	for i: int in blade.lit_edge.size() - 1:
		var far: bool = i >= blade.lit_edge.size() / 2
		_seg(_body, blade.lit_edge[i], blade.lit_edge[i + 1], 1.0, 1.0, _tint(RIM if (far and seen_top) else c_edge, (0.9 if seen_top else 0.5) * ka))


func _draw_wing_outline(wing: Wing) -> void:
	_paint_outline(_body, wing.membrane_span, _tint(OUTLINE))
	for blade: Blade in wing.blades:
		if not blade.hidden:
			_paint_outline(_body, blade.span, _tint(OUTLINE))


func _build_legs() -> void:
	var grip: float = _q[Q.GRIP]
	for si: int in 2:
		var s: float = 1.0 if si == 0 else -1.0
		var hip: Vector3 = _bp(Vector3(-1.5, s * 4.2, -5.8))
		var local_foot: Vector3 = _bp(Vector3(_q[Q.FOOT_X], s * _q[Q.FOOT_SP], _q[Q.FOOT_Z]))
		var world_foot: Vector3 = Vector3(PERCH_FOOT.x, s * PERCH_FOOT.y, PERCH_FOOT.z)
		var ankle: Vector3 = local_foot.lerp(world_foot, grip)
		var solved: PackedVector3Array = _ik(hip, ankle, 8.0, 8.0, Vector3(1.0, s * 0.35, 0.25))
		var knee: Vector3 = solved[0]
		ankle = solved[1]
		var fa: float = _q[Q.FOOT_A]
		var local_dir: Vector3 = _rot(Vector3(cos(fa), 0.0, -sin(fa)))
		var world_dir: Vector3 = Vector3(cos(fa), 0.0, -sin(fa))
		var tdir: Vector3 = local_dir.lerp(world_dir, grip).normalized()
		var thigh: PackedVector3Array = _discs_along([hip, knee], [4.2, 3.0])
		var tsp: Span = _span_discs(thigh)
		var shin: PackedVector3Array = _discs_along([knee, ankle], [2.3, 1.5])
		var ssp: Span = _span_discs(shin)
		var depth: float = (_depth(hip) + _depth(ankle)) * 0.5
		_new_part(depth - 0.1, _draw_leg.bind(thigh, tsp, shin, ssp, ankle, tdir, s, si), Callable(), tsp)


func _draw_leg(thigh: PackedVector3Array, tsp: Span, shin: PackedVector3Array, ssp: Span, ankle: Vector3, tdir: Vector3, s: float, si: int) -> void:
	_paint_tube(_body, shin, PAL_DARK, ssp)
	_paint_tube(_body, thigh, PAL_FLESH, tsp)
	# toes: three forward, curled by TOES, one hind toe, each ending in a basalt claw
	var curl: float = _q[Q.TOES]
	var down: Vector3 = _rot(Vector3(0, 0, -1)).lerp(Vector3(0, 0, -1), _q[Q.GRIP]).normalized()
	var across: Vector3 = tdir.cross(down)
	across = across.normalized() if across.length() > 0.001 else Vector3(0, 1, 0)
	var a: Vector2 = _p(ankle)
	for j: int in range(-1, 2):
		var d1: Vector3 = (tdir + across * float(j) * 0.5).normalized()
		var k1: Vector3 = ankle + d1 * 3.0
		var d2: Vector3 = (d1 * (1.0 - curl * 0.7) + down * (curl * 0.9 + 0.2)).normalized()
		var k2: Vector3 = k1 + d2 * 2.6
		var d3: Vector3 = (d2 + down * 1.2).normalized()
		var k3: Vector3 = k2 + d3 * 2.2
		_seg(_body, a, _p(k1), 2.0, 2.0, _tint(OUTLINE))
		_seg(_body, _p(k1), _p(k2), 2.0, 1.0, _tint(OUTLINE))
		_seg(_body, _p(k2), _p(k3), 1.0, 1.0, _tint(OUTLINE))
		_seg(_body, a, _p(k1), 1.0, 1.0, _tint(ROCK1))
		_seg(_body, _p(k1), _p(k2), 1.0, 1.0, _tint(ROCK2))
		_body.draw_rect(Rect2(_p(k3).round(), Vector2.ONE), _tint(ROCK3))
	var hind: Vector3 = ankle - tdir * 2.8 + down * 0.8
	_seg(_body, a, _p(hind), 2.0, 1.0, _tint(OUTLINE))
	_seg(_body, a, _p(hind), 1.0, 1.0, _tint(ROCK1))
	_body.draw_rect(Rect2((_p(ankle) + Vector2(-1, -1)).round(), Vector2(2, 1)), _tint(ROCK2))


# --- harness -------------------------------------------------------------------------------------------------------


func _build_harness() -> void:
	var depth: float = _depth(_center) + 0.05
	var bands: Array[Array] = []
	# a ring round the body behind the chest, two straps crossing the breast
	var ring: Array[Vector3] = []
	var ring_n: Array[Vector3] = []
	for k: int in 15:
		var ang: float = deg_to_rad(-150.0 + float(k) * 20.0)
		ring.append(_bp(_surf(-2.5, ang, 0.7)))
		ring_n.append(_rot(Vector3(0.0, sin(ang), -cos(ang))))
	bands.append([ring, ring_n])
	var strap_a: Array[Vector3] = []
	var strap_a_n: Array[Vector3] = []
	var strap_b: Array[Vector3] = []
	var strap_b_n: Array[Vector3] = []
	for k: int in 9:
		var u: float = float(k) / 8.0
		var x: float = lerpf(7.5, 1.0, u)
		var ang_a: float = lerpf(deg_to_rad(105.0), deg_to_rad(-70.0), u)
		var ang_b: float = -ang_a
		strap_a.append(_bp(_surf(x, ang_a, 0.7)))
		strap_b.append(_bp(_surf(x, ang_b, 0.7)))
		strap_a_n.append(_rot(Vector3(0.0, sin(ang_a), -cos(ang_a))))
		strap_b_n.append(_rot(Vector3(0.0, sin(ang_b), -cos(ang_b))))
	bands.append([strap_a, strap_a_n])
	bands.append([strap_b, strap_b_n])
	_new_part(depth, _draw_harness.bind(bands), _glow_harness.bind(bands))


func _draw_harness(bands: Array[Array]) -> void:
	for band: Array in bands:
		var pts: Array[Vector3] = band[0]
		var nrm: Array[Vector3] = band[1]
		for k: int in pts.size() - 1:
			if nrm[k].dot(_view) < -0.12 or nrm[k + 1].dot(_view) < -0.12:
				continue
			var a: Vector2 = _p(pts[k])
			var b: Vector2 = _p(pts[k + 1])
			_seg(_body, a, b, 4.0, 4.0, _tint(OUTLINE))
		for k: int in pts.size() - 1:
			if nrm[k].dot(_view) < -0.12 or nrm[k + 1].dot(_view) < -0.12:
				continue
			var a2: Vector2 = _p(pts[k])
			var b2: Vector2 = _p(pts[k + 1])
			_seg(_body, a2, b2, 2.0, 2.0, _tint(ROCK1))
			_seg(_body, a2 + Vector2(-1, -1), b2 + Vector2(-1, -1), 1.0, 1.0, _tint(ROCK3, 0.9))
	# clasp: a quartz crystal where the straps cross, only seen from the front
	var vis: float = _core_vis()
	if vis > 0.15:
		var c: Vector2 = _p(_core3)
		var pts2: PackedVector2Array = PackedVector2Array([c + Vector2(0, -5), c + Vector2(3, -1), c + Vector2(2, 4), c + Vector2(-2, 4), c + Vector2(-3, -1)])
		var sp: Span = _span_poly(pts2)
		_paint_outline(_body, sp, _tint(OUTLINE, vis))
		_paint(_body, sp, _tint(ROCK2, vis))
		_paint(_body, _span_poly(PackedVector2Array([c + Vector2(0, -4), c + Vector2(-1, -1), c + Vector2(-2, -1), c + Vector2(-1, -3)])), _tint(ROCK3, vis))


func _core_vis() -> float:
	var n: Vector3 = _rot(Vector3(0.5, 0.0, -0.85))
	return smoothstep(-0.3, 0.45, n.dot(_view))


func _glow_harness(part: Part, bands: Array[Array]) -> void:
	var life: float = _life_core
	var strength: float = _q[Q.VEIN] * life
	for bi: int in bands.size():
		var pts: Array[Vector3] = bands[bi][0]
		var nrm: Array[Vector3] = bands[bi][1]
		for k: int in pts.size():
			if nrm[k].dot(_view) < 0.0:
				continue
			# a rune tick across the strap every other point, pulsing outward from the core
			var screen: Vector2 = _p(pts[k])
			if _occ(screen.x, screen.y, part.rank):
				continue
			var wave: float = _beat(-(float(k) * 2.2 + float(bi) * 5.0) * 0.012)
			if k % 2 == 0:
				_halo(_glow, screen, VEIN_LIGHT, strength * (0.25 + 0.75 * wave), 0.25)
			elif k + 1 < pts.size():
				_halo(_glow, screen.lerp(_p(pts[k + 1]), 0.5), VEIN, strength * (0.2 + 0.6 * wave), 0.1)
	var vis: float = _core_vis()
	if vis > 0.1:
		var c: Vector2 = _p(_core3)
		if not _occ(c.x, c.y, part.rank):
			var heart: float = _beat(0.0)
			var power: float = life * vis * (0.7 + 0.5 * heart) * _q[Q.VEIN]
			_halo(_glow, c, CORE, power, 1.4)
			_glow.draw_rect(Rect2((c + Vector2(-1, -2)).round(), Vector2(3, 5)), Color(VEIN, _alpha * power * 0.25))
			_glow.draw_rect(Rect2((c + Vector2(0, -1)).round(), Vector2(1, 3)), Color(CORE_HOT, _alpha * clampf(power, 0.0, 1.0)))
			_halo(_glow, c, CORE_HOT, power * 0.5, 0.6)
			if _corr > 0.05:
				_draw_core_crack(c, power)


## Phase 2: the core splits. A short jagged vertical crack of white light through the breastbone that beats with the heart.
func _draw_core_crack(c: Vector2, power: float) -> void:
	var k: float = smoothstep(0.05, 0.9, _corr)
	var half: int = 2 + roundi(4.0 * k)
	var a: float = clampf(power * (0.6 + 0.6 * _beat(0.0)) * k + _crack_flash * 0.9, 0.0, 1.5)
	var base: Vector2 = c.round()
	for i: int in range(-half, half + 1):
		var zi: int = ZIG[(i + 6) % ZIG.size()]
		var fall: float = 1.0 - 0.45 * absf(float(i)) / float(half + 1)
		var pt: Vector2 = base + Vector2(zi, i)
		_glow.draw_rect(Rect2(pt + Vector2(-1, 0), Vector2(3, 1)), Color(VEIN_LIGHT, _alpha * clampf(a * fall * 0.16, 0.0, 1.0)))
		_glow.draw_rect(Rect2(pt, Vector2.ONE), Color(CORE_HOT, _alpha * clampf(a * fall, 0.0, 1.0)))
	if k > 0.5:
		var side: int = -1 if _noise(7, 1.0) < 0.5 else 1
		var fork: Vector2 = base + Vector2(ZIG[(2 + 6) % ZIG.size()], -2)
		_glow.draw_rect(Rect2(fork + Vector2(side, 0), Vector2.ONE), Color(CORE, _alpha * clampf(a * 0.8, 0.0, 1.0)))
		_glow.draw_rect(Rect2(fork + Vector2(side * 2, -1), Vector2.ONE), Color(VEIN_LIGHT, _alpha * clampf(a * 0.6, 0.0, 1.0)))
	_halo(_glow, c, CORE, a * 0.45, 1.1)


# --- wings ---------------------------------------------------------------------------------------------------------


func _wdir(s: float, yaw: float, el: float, wf: float) -> Vector3:
	var d: Vector3 = Vector3(-sin(yaw) * cos(el), s * cos(yaw) * cos(el), sin(el))
	return (_rot(d) * (1.0 - wf) + d * wf).normalized()


func _wnormal(u: Vector3, upref: Vector3, side: float, tw: float) -> Vector3:
	var vertical: float = u.z * u.z
	var ref: Vector3 = upref * (1.0 - vertical) + Vector3(0.0, side, 0.0) * vertical
	var n: Vector3 = ref - u * ref.dot(u)
	if n.length() < 0.05:
		n = Vector3(1, 0, 0) - u * u.x
	n = n.normalized()
	return n * cos(tw) + u.cross(n) * sin(tw)


func _build_wing_pair(dt: float) -> void:
	if _bf[0].size() != 11:
		_bf[0].resize(11)
		_bf[1].resize(11)
		_bf_ready = false
	for si: int in 2:
		_wings.append(_build_wing(si, dt))


func _build_wing(si: int, dt: float) -> Wing:
	var wing: Wing = Wing.new()
	var s: float = 1.0 if si == 0 else -1.0
	wing.side = s
	var o: int = Q.RU_Y if si == 0 else Q.LU_Y
	var raised: float = raise_r if si == 0 else raise_l
	var wf: float = maxf(_q[Q.WF], clampf(raised * 1.6, 0.0, 1.0)) ## a raised wing stands up in the bird's own frame, whatever the body does
	var len_k: float = _q[Q.LEN]
	var trem: float = _q[Q.TREM]
	var jit: float = trem * 0.07
	var ph: float = 0.0 if si == 0 else 1.9
	var uy: float = _q[o] + jit * sin(_time * 57.0 + ph)
	var ue: float = _q[o + 1] + jit * sin(_time * 61.0 + ph + 1.0)
	var fy: float = _q[o + 2]
	var fe: float = _q[o + 3] + jit * sin(_time * 67.0 + ph + 2.0)
	var hy: float = _q[o + 4]
	var he: float = _q[o + 5] + jit * 1.3 * sin(_time * 71.0 + ph + 3.0)
	var fan: float = clampf(_q[o + 7] + trem * 0.06 * sin(_time * 49.0 + ph), 0.0, 1.0)
	var tw: float = _q[o + 6]
	wing.upref = (_rot(Vector3(0, 0, 1)) * (1.0 - wf) + Vector3(0, 0, 1) * wf).normalized()
	var d_u: Vector3 = _wdir(s, uy, ue, wf)
	var d_f: Vector3 = _wdir(s, fy, fe, wf)
	var d_h: Vector3 = _wdir(s, hy, he, wf)
	wing.s = _bp(Vector3(SH_X, s * 5.0, SH_Z))
	wing.e = wing.s + d_u * LU * len_k
	wing.w = wing.e + d_f * LF * len_k
	wing.h = wing.w + d_h * LH * len_k
	var n_u: Vector3 = _wnormal(d_u, wing.upref, s, tw)
	var n_f: Vector3 = _wnormal(d_f, wing.upref, s, tw)
	var n_h: Vector3 = _wnormal(d_h, wing.upref, s, tw)
	var c_f: Vector3 = n_f.cross(d_f) * s
	var c_h: Vector3 = n_h.cross(d_h) * s
	wing.normal = n_f
	wing.chord = c_f
	var raw: Array[Vector3] = []
	var bases: Array[Vector3] = []
	var norms: Array[Vector3] = []
	var lens: Array[float] = []
	var widths: Array[float] = []
	var rates: Array[float] = []
	var starts: Array[float] = []
	for i: int in 6:
		var alpha: float = fan * lerpf(0.08, 1.2, float(i) / 5.0)
		raw.append((d_h * cos(alpha) + c_h * sin(alpha)).normalized())
		bases.append(wing.w + d_h * (LH * len_k * float(i) / 5.0) - c_h * 0.4)
		norms.append(n_h)
		lens.append(P_LEN[i] * len_k)
		widths.append(4.4)
		rates.append(P_RATE[i])
		starts.append(LU + LF + LH * float(i) / 5.0)
	for j: int in 5:
		var alpha2: float = fan * lerpf(1.45, 1.1, float(j) / 4.0)
		raw.append((d_f * cos(alpha2) + c_f * sin(alpha2)).normalized())
		bases.append(wing.e.lerp(wing.w, (float(j) + 0.5) / 5.0) - c_f * 0.5)
		norms.append(n_f)
		lens.append(S_LEN[j] * len_k)
		widths.append(5.2)
		rates.append(S_RATE[j])
		starts.append(LU + LF * (float(j) + 0.5) / 5.0)
	var filt: PackedVector3Array = _bf[si]
	var count: int = raw.size()
	for k: int in count:
		if not _bf_ready:
			filt[k] = raw[k]
		else:
			filt[k] = filt[k].lerp(raw[k], 1.0 - exp(-rates[k] * dt)).normalized()
	_bf[si] = filt
	var tip_mid: Vector3 = Vector3.ZERO
	for k: int in count:
		var is_light: bool = k in LIGHT_BLADES
		var blade_len: float = lens[k]
		var hide: bool = false
		if is_light and _lb > 0.0:
			blade_len *= maxf(lerpf(1.0, _light_grow, _lb), 0.05)
			hide = _lb > 0.5 and _light_grow < 0.04
		var blade: Blade = _make_blade(bases[k], raw[k], filt[k], norms[k], blade_len, widths[k])
		blade.vein_start = starts[k]
		blade.idx = k
		blade.salt = float(si * 11 + k)
		blade.light = _lb if is_light else 0.0
		blade.hidden = hide
		blade.cracked = (not is_light) and _noise(si * 16 + k, 3.1) > 0.6
		wing.blades.append(blade)
		tip_mid += bases[k] + filt[k] * lens[k] * 0.5
	tip_mid /= float(count)
	wing.depth = _depth((wing.s + wing.e + wing.w + tip_mid) * 0.25) + 1.6 * wf
	# membrane: the arm's leading edge, then back along the blade roots at about half their length
	var mem: PackedVector2Array = PackedVector2Array()
	mem.append(_p(wing.s))
	mem.append(_p(wing.e))
	mem.append(_p(wing.w))
	mem.append(_p(wing.h))
	for i: int in 6:
		mem.append(_p(bases[i] + filt[i] * lens[i] * 0.5))
	for j: int in range(4, -1, -1):
		mem.append(_p(bases[6 + j] + filt[6 + j] * lens[6 + j] * 0.5))
	mem.append(_p(wing.s - c_f * 1.5))
	wing.membrane = mem
	wing.membrane_span = _span_poly(mem)
	var arm_pts: Array[Vector3] = [wing.s, wing.e, wing.w, wing.h]
	wing.arm_discs = _discs_along(arm_pts, [2.6, 2.1, 1.5, 1.0])
	wing.arm_span = _span_discs(wing.arm_discs)
	wing.claw = PackedVector2Array([_p(wing.w - c_f * 0.5), _p(wing.w - c_f * 1.6 + n_f * 3.6), _p(wing.w + d_f * 0.8 + n_f * 0.6)])
	wing.vein_arm = PackedVector2Array([_p(wing.s), _p(wing.e), _p(wing.w), _p(wing.h)])
	# parts, in a fixed layering inside the wing so overlapping blades never swap
	var base_depth: float = wing.depth
	_new_part(base_depth - 0.0005, _draw_wing_outline.bind(wing))
	_new_part(base_depth, _draw_membrane.bind(wing), _glow_membrane.bind(wing, si), wing.membrane_span)
	for j: int in range(0, 5):
		var b: Blade = wing.blades[6 + j]
		_new_part(base_depth + 0.001 * float(j + 1), _draw_blade.bind(b), _glow_blade.bind(b, si), b.span)
	for i: int in range(5, -1, -1):
		var b2: Blade = wing.blades[i]
		_new_part(base_depth + 0.01 + 0.001 * float(5 - i), _draw_blade.bind(b2), _glow_blade.bind(b2, si), b2.span)
	_new_part(base_depth + 0.03, _draw_arm.bind(wing), _glow_arm.bind(wing, si), wing.arm_span)
	return wing


func _draw_membrane(wing: Wing) -> void:
	var sp: Span = wing.membrane_span
	_paint(_body, sp, _tint(MID.darkened(0.15)))
	_paint(_body, _span_poly(_inset(wing.membrane, 0.6)), _tint(FLESH))
	_paint_shade(_body, sp, _tint(FLESH, 0.9))
	_paint_rim(_body, sp, _tint(RIM, 0.35))


func _inset(poly: PackedVector2Array, k: float) -> PackedVector2Array:
	var c: Vector2 = Vector2.ZERO
	for point: Vector2 in poly:
		c += point
	c /= float(maxi(1, poly.size()))
	var out: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in poly:
		out.append(c.lerp(point, k))
	return out


func _draw_arm(wing: Wing) -> void:
	_paint_tube(_body, wing.arm_discs, PAL_DARK, wing.arm_span)
	# wrist claw
	var csp: Span = _span_poly(wing.claw)
	_paint_outline(_body, csp, _tint(OUTLINE))
	_paint(_body, csp, _tint(ROCK2))
	_paint_rim(_body, csp, _tint(ROCK3))
	# pauldron: a grown-in bronze plate with a quartz chip
	var sh: Vector2 = _p(wing.s)
	var plate: PackedVector3Array = PackedVector3Array([Vector3(sh.x - 0.5, sh.y - 1.0, 4.0), Vector3(sh.x + 1.0, sh.y + 0.0, 3.4)])
	_paint_tube(_body, plate, PAL_ROCK)
	_body.draw_rect(Rect2((sh + Vector2(-1, -4)).round(), Vector2(2, 3)), _tint(CORE.darkened(0.45)))
	_body.draw_rect(Rect2((sh + Vector2(-1, -4)).round(), Vector2(1, 1)), _tint(CORE_HOT))


func _glow_arm(part: Part, wing: Wing, si: int) -> void:
	var life: float = _life_wing[si] * _q[Q.VEIN]
	var travelled: float = 6.0
	for n: int in wing.vein_arm.size() - 1:
		travelled = _vein_line(PackedVector2Array([wing.vein_arm[n], wing.vein_arm[n + 1]]), part.rank, life * 0.95, travelled, 0.2)
	# the quartz chip on the shoulder
	var sh: Vector2 = _p(wing.s) + Vector2(-0.5, -3.5)
	if not _occ(sh.x, sh.y, part.rank):
		_halo(_glow, sh, CORE, life * (0.5 + 0.4 * _beat(0.05)), 0.7)


func _glow_membrane(part: Part, wing: Wing, si: int) -> void:
	# faint violet vessels in the stretched skin, running from the elbow towards the blade roots
	var life: float = _life_wing[si] * _q[Q.VEIN]
	for j: int in 4:
		var blade: Blade = wing.blades[6 + j]
		var from: Vector2 = _p(wing.e.lerp(wing.w, (float(j) + 0.5) / 5.0))
		var to: Vector2 = blade.center[2]
		_vein_line(PackedVector2Array([from, to]), part.rank, life * 0.5, blade.vein_start, 0.1)


func _glow_blade(part: Part, blade: Blade, si: int) -> void:
	if blade.hidden:
		return
	var life: float = _life_wing[si] * _q[Q.VEIN]
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(1, blade.center.size() - 1):
		pts.append(blade.center[i])
	_vein_line(pts, part.rank, life, blade.vein_start, 0.15)
	# a bright pixel at the blade tip
	var tip: Vector2 = blade.center[blade.center.size() - 2]
	if not _occ(tip.x, tip.y, part.rank):
		_halo(_glow, tip, VEIN_LIGHT, life * (0.35 + 0.6 * _beat(-(blade.vein_start + 14.0) * 0.012)), 0.45)
	if charge > 0.02:
		_charge_blade(part, blade, life, tip)
	if blade.light > 0.02:
		_glow_light_blade(part, blade, si)
	elif blade.cracked and _corr > 0.05:
		_blade_crack(part, blade, _life_wing[si])


## Phase 2: a blade of pure light. The silhouette keeps its place in the sorting (so everything in front of it still hides it),
## the light is a translucent pale fill with a bright edge on the lit side, a violet rim on the other and a burning tip.
func _glow_light_blade(part: Part, blade: Blade, si: int) -> void:
	var a: float = blade.light * _life_wing[si]
	if a < 0.02:
		return
	var rk: int = part.rank
	var pulse: float = 0.85 + 0.15 * _beat(-blade.vein_start * 0.012)
	_paint_visible(_glow, blade.span, Color(CORE, 0.36 * a * pulse * _alpha), rk)
	var lit: PackedVector2Array = _lit_poly(blade.left, blade.right)
	if lit.size() >= 3:
		_paint_visible(_glow, _span_poly(lit), Color(CORE_HOT, 0.2 * a * _alpha), rk)
	_line_visible(_glow, blade.far_edge, Color(VEIN, 0.95 * a * _alpha), rk)
	_line_visible(_glow, blade.lit_edge, Color(CORE_HOT, 0.9 * a * _alpha), rk)
	var shaft: PackedVector2Array = PackedVector2Array()
	for i: int in range(1, blade.center.size() - 1):
		shaft.append(blade.center[i])
	_line_visible(_glow, shaft, Color(CORE_HOT, 0.4 * a * _alpha), rk)
	var tip: Vector2 = blade.center[blade.center.size() - 2]
	if not _occ(tip.x, tip.y, rk):
		_halo(_glow, tip, CORE_HOT, a * (0.75 + 1.5 * _light_flare + 0.2 * _crack_flash), 0.95)


## Two to four thin magenta cracks along a darkened blade: deterministic per blade, flickering slowly.
func _blade_crack(part: Part, blade: Blade, life: float) -> void:
	var n: int = blade.center.size()
	var key: int = int(blade.salt)
	var flick: float = 0.55 + 0.45 * sin(_time * (0.9 + 0.4 * _noise(key, 7.0)) + blade.salt * 2.3)
	var a: float = _corr * life * flick
	if a < 0.05:
		return
	var k0: int = 2 + int(_noise(key, 5.0) * 2.0)
	var count: int = 3
	var across: Vector2 = blade.right[k0] - blade.left[k0]
	across = across.normalized() if across.length() > 0.01 else Vector2.RIGHT
	var line: PackedVector2Array = PackedVector2Array()
	for j: int in count + 1:
		var f: float = float(j) / float(count) * 2.0
		var seg: int = mini(int(f), 1)
		var pos: Vector2 = blade.center[k0 + seg].lerp(blade.center[mini(k0 + seg + 1, n - 2)], f - float(seg))
		line.append(pos + across * float(ZIG[(j + key) % ZIG.size()]) * 0.9)
	_line_visible(_glow, line, Color(EYE, 0.85 * a * _alpha), part.rank)
	var mid: Vector2 = line[count / 2]
	if not _occ(mid.x, mid.y, part.rank):
		_halo(_glow, mid, EYE, a * 0.35, 0.2)

## The feathers charging: a light runs from the root of every blade out to its tip, again and again, and the tip burns. The colour tells the attack.
func _charge_blade(part: Part, blade: Blade, life: float, tip: Vector2) -> void:
	var colors: Array[Color] = [CORE, EYE, Color("6a3fd8"), CORE_HOT]
	var color: Color = colors[clampi(charge_kind, 0, 3)]
	var n: int = blade.center.size()
	var strength: float = charge * life
	if charge_kind == 2:
		strength *= 0.35 + 0.65 * _beat(0.0) ## a dark pulse, like a heart
	var sweep: float = fposmod(_time * (1.1 + 1.6 * charge) - blade.vein_start * 0.012, 1.0)
	var at: float = 1.0 + sweep * float(n - 3)
	var i0: int = clampi(int(at), 1, n - 3)
	var point: Vector2 = blade.center[i0].lerp(blade.center[i0 + 1], at - float(i0))
	if not _occ(point.x, point.y, part.rank):
		_halo(_glow, point, color, strength * 0.9, 0.6)
	if not _occ(tip.x, tip.y, part.rank):
		_halo(_glow, tip, color, strength * (0.55 + 0.45 * sin(_time * 14.0 + blade.vein_start)), 0.85)


## Vein pixels along a screen polyline; the heartbeat runs outward with the travelled distance. Returns the distance reached.
func _vein_line(pts: PackedVector2Array, rank: int, strength: float, start: float, bloom: float) -> float:
	var travelled: float = start
	if strength <= 0.01:
		return travelled
	for i: int in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var steps: int = maxi(1, ceili(a.distance_to(b) / 1.5))
		for k: int in steps:
			var point: Vector2 = a.lerp(b, float(k) / float(steps))
			travelled += 1.5
			if k % 2 == 1:
				continue
			var cell: int = (roundi(point.x) >> 1) * 4096 + (roundi(point.y) >> 1)
			if _vein_seen.has(cell):
				continue
			if _occ(point.x, point.y, rank):
				continue
			_vein_seen[cell] = true
			var wave: float = _beat(-travelled * 0.012)
			_halo(_glow, point, VEIN_LIGHT if k % 4 == 0 else VEIN, strength * 0.7 * (0.2 + 0.8 * wave), bloom)
	return travelled


## Like `_paint`, but only the pixels no later part (in front of this one) covers: the glow canvas lies over the whole body, so a translucent fill must cut its own holes.
func _paint_visible(canvas: Node2D, sp: Span, color: Color, rank: int) -> void:
	var rows: int = sp.lo.size()
	var cuts: Array[Vector2i] = []
	for r: int in rows:
		var lo: int = sp.lo[r]
		var hi: int = sp.hi[r]
		if hi < lo:
			continue
		var y: int = sp.y0 + r
		cuts.clear()
		for k: int in range(rank + 1, _sorted.size()):
			var o: Span = _sorted[k].span
			if o == null:
				continue
			var rr: int = y - o.y0
			if rr < 0 or rr >= o.lo.size() or o.hi[rr] < o.lo[rr] or o.hi[rr] < lo or o.lo[rr] > hi:
				continue
			var cut: Vector2i = Vector2i(o.lo[rr], o.hi[rr])
			var at: int = cuts.size()
			while at > 0 and cuts[at - 1].x > cut.x:
				at -= 1
			cuts.insert(at, cut)
		var x: int = lo
		for cut: Vector2i in cuts:
			if cut.x > x:
				canvas.draw_rect(Rect2(float(x), float(y), float(cut.x - x), 1.0), color)
			x = maxi(x, cut.y + 1)
			if x > hi:
				break
		if x <= hi:
			canvas.draw_rect(Rect2(float(x), float(y), float(hi - x + 1), 1.0), color)


## A one pixel line along a screen polyline, skipping what is hidden by parts in front of `rank`.
func _line_visible(canvas: Node2D, pts: PackedVector2Array, color: Color, rank: int) -> void:
	var last: Vector2i = Vector2i(1 << 20, 1 << 20)
	for i: int in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var steps: int = maxi(1, ceili(a.distance_to(b)))
		for k: int in steps + (1 if i == pts.size() - 2 else 0):
			var pt: Vector2 = a.lerp(b, float(k) / float(steps))
			var cell: Vector2i = Vector2i(roundi(pt.x), roundi(pt.y))
			if cell == last:
				continue
			last = cell
			if _occ(pt.x, pt.y, rank):
				continue
			canvas.draw_rect(Rect2(Vector2(cell), Vector2.ONE), color)


func _occ(x: float, y: float, rank: int) -> bool:
	var ix: int = roundi(x)
	var iy: int = roundi(y)
	for k: int in range(rank + 1, _sorted.size()):
		var sp: Span = _sorted[k].span
		if sp != null and sp.has_point(ix, iy):
			return true
	return false


# --- head glow -----------------------------------------------------------------------------------------------------


func _glow_head(part: Part) -> void:
	var flare: float = _q[Q.EYE]
	for k: int in EYES:
		var vis: float = _eye_vis_k(k) * _eye_open[k] * _life_eye[k]
		if k >= 6:
			vis *= _pop_k()
		if vis < 0.05:
			continue
		var e: Vector2 = _p(_eye_pos_k(k))
		if _occ(e.x, e.y, part.rank):
			continue
		var bright: float = (0.9 + 0.3 * (flare - 1.0) + _crack_flash * 0.9) * vis
		var hot: Color = EYE.lerp(EYE_HOT, clampf((flare - 1.0) * 0.6, 0.0, 0.8)).lerp(CORE_HOT, _crack_flash)
		_halo(_glow, e, hot if _crack_flash > 0.3 else EYE, bright * 0.7, 0.3)
		_glow.draw_rect(Rect2((e + Vector2(-1, 0)).round(), Vector2(3, 1)), Color(hot.lerp(CORE, 0.3), _alpha * minf(1.0, bright)))
		if k % 3 == 1 and k < 6:
			_halo(_glow, e, EYE, bright * 0.8, 1.1)
		elif k >= 6:
			_halo(_glow, e, EYE, bright * 0.55, 0.8)
	# crest tips and the brow plates glow along their seams
	for sd: float in [-1.0, 1.0]:
		var brow: Vector2 = _p(_hp(0.4, sd * 3.7, 3.1))
		if _eye_vis(sd) > 0.3 and not _occ(brow.x, brow.y, part.rank):
			_halo(_glow, brow, VEIN_LIGHT, _eye_vis(sd) * _life_core * (0.35 + 0.5 * _beat(0.1)), 0.3)


func _glow_mouth(part: Part) -> void:
	var gape: float = _q[Q.GAPE]
	if gape < 0.15:
		return
	var mid: Vector2 = _p(_hp(5.0, 0.0, -2.0 - 1.6 * sin(gape)))
	if _occ(mid.x, mid.y, part.rank):
		return
	_halo(_glow, mid, VEIN, minf(1.0, gape) * 0.8 * _life_core * (1.0 + 0.9 * _judge_k), 0.4 + 0.5 * _judge_k)
	if _judge_k > 0.05:
		_halo(_glow, mid, CORE, _judge_k * 0.7 * _life_core, 0.7)


# --- tendrils ------------------------------------------------------------------------------------------------------


func _step_tendrils(dt: float) -> void:
	_td_anchor.clear()
	for i: int in TD_MAX:
		_td_anchor.append(_to_world(_bp(TD_ANCHOR[i])))
	if not _td_ready:
		_td.clear()
		_td_prev.clear()
		for i: int in TD_MAX:
			var pts: PackedVector3Array = PackedVector3Array()
			pts.resize(TD_N)
			var seg: float = TD_LEN[i] * maxf(_td_scale[i], 0.05) / float(TD_N - 1)
			for n: int in TD_N:
				pts[n] = _td_anchor[i] + Vector3(0.0, 0.0, -seg * float(n))
			_td.append(pts)
			_td_prev.append(pts.duplicate())
		_td_ready = true
	var v3: Vector3 = Vector3(_vel.x, _vel.y / SQUASH, _rise)
	if dt > 0.0:
		var a_raw: Vector3 = (v3 - _vel3_prev) / dt
		_acc3 = _acc3.lerp(a_raw.limit_length(1600.0), 1.0 - exp(-14.0 * dt))
		_vel3_prev = v3
	var step: float = 1.0 / 90.0
	_td_clock += dt
	var guard: int = 0
	while _td_clock >= step and guard < 8:
		_td_clock -= step
		guard += 1
		_tendril_substep(step, v3)
	if guard == 8:
		_td_clock = 0.0


func _tendril_substep(h: float, v3: Vector3) -> void:
	var calm: bool = _pose == Pose.PERCHED and lift < 0.05
	var lf: float = lift
	for i: int in TD_MAX:
		var pts: PackedVector3Array = _td[i]
		var prv: PackedVector3Array = _td_prev[i]
		pts[0] = _td_anchor[i]
		prv[0] = _td_anchor[i]
		var sc: float = _td_scale[i]
		if sc < 0.06:
			# a tendril that has not grown yet rests folded at its root, so it grows out cleanly
			for n: int in range(1, TD_N):
				pts[n] = _td_anchor[i]
				prv[n] = _td_anchor[i]
			_td[i] = pts
			_td_prev[i] = prv
			continue
		var seg: float = TD_LEN[i] * sc / float(TD_N - 1)
		for n: int in range(1, TD_N):
			var p: Vector3 = pts[n]
			var vrel: Vector3 = (p - prv[n]) / h
			var vabs: Vector3 = vrel + v3
			var drag: float = 5.5 if not calm else 2.4
			var acc: Vector3 = Vector3(0.0, 0.0, -260.0 + lf * 520.0) - vabs * drag - _acc3 * 0.75
			if calm:
				acc += Vector3(sin(_time * 0.7 + float(i) * 1.9 + float(n) * 0.3) * 22.0, cos(_time * 0.53 + float(i) * 2.7) * 12.0, 0.0)
			var np: Vector3 = p + (p - prv[n]) * 0.992 + acc * h * h
			prv[n] = p
			pts[n] = np
		for it: int in 3:
			pts[0] = _td_anchor[i]
			for n: int in range(0, TD_N - 1):
				var d: Vector3 = pts[n + 1] - pts[n]
				var dist: float = d.length()
				if dist < 0.0001:
					continue
				var diff: float = (dist - seg) / dist
				if n == 0:
					pts[n + 1] -= d * diff
				else:
					pts[n] += d * diff * 0.5
					pts[n + 1] -= d * diff * 0.5
		for n: int in range(2, TD_N):
			var straight: Vector3 = pts[n - 1] + (pts[n - 1] - pts[n - 2])
			pts[n] = pts[n].lerp(straight, 0.035 + lf * 0.25)
		if lf > 0.01:
			# lifted: every link is pulled towards the line straight up from its root, with a faint sway
			for n: int in range(1, TD_N):
				var up_to: Vector3 = _td_anchor[i] + Vector3(sin(_time * 1.7 + float(i) * 1.3 + float(n) * 0.4) * 0.35 * float(n), cos(_time * 1.3 + float(i) * 2.1) * 0.3 * float(n), seg * float(n))
				pts[n] = pts[n].lerp(up_to, lf * 0.12)
		if _td_floor > -500.0:
			for n: int in range(1, TD_N):
				if pts[n].z < _td_floor:
					var fixed: Vector3 = Vector3(pts[n].x, pts[n].y, _td_floor)
					pts[n] = fixed
					prv[n] = prv[n].lerp(fixed, 0.35)
		_td[i] = pts
		_td_prev[i] = prv


func _build_tendril_parts() -> void:
	for i: int in TD_MAX:
		if _td_scale[i] < 0.08:
			continue
		var pts: PackedVector3Array = _td[i]
		var screen: PackedVector2Array = PackedVector2Array()
		for n: int in TD_N:
			screen.append(_pw(pts[n]))
		var mid: Vector3 = pts[TD_N / 2]
		# world frame -> the same depth measure as the body frame (heading already folded in)
		var depth: float = mid.y + 0.4 * mid.z - 0.3
		_new_part(depth, _draw_tendril.bind(screen, i), _glow_tendril.bind(screen, i))


func _draw_tendril(screen: PackedVector2Array, i: int) -> void:
	var thin: float = 1.0 if i < TD_COUNT else 0.85
	var discs: PackedVector3Array = PackedVector3Array()
	for n: int in screen.size() - 1:
		var a: Vector2 = screen[n]
		var b: Vector2 = screen[n + 1]
		var ra: float = lerpf(1.45, 0.55, float(n) / float(screen.size() - 1)) * thin
		var rb: float = lerpf(1.45, 0.55, float(n + 1) / float(screen.size() - 1)) * thin
		var count: int = maxi(1, ceili(a.distance_to(b)))
		for k: int in range(0 if n == 0 else 1, count + 1):
			var u: float = float(k) / float(count)
			var c: Vector2 = a.lerp(b, u)
			discs.append(Vector3(c.x, c.y, lerpf(ra, rb, u)))
	_paint_tube(_body, discs, PAL_DARK)


func _glow_tendril(part: Part, screen: PackedVector2Array, i: int) -> void:
	var life: float = _life_wing[0] * _q[Q.VEIN]
	for n: int in range(1, screen.size(), 2):
		var wave: float = _beat(-float(n) * 0.04 - float(i) * 0.05)
		if not _occ(screen[n].x, screen[n].y, part.rank):
			_halo(_glow, screen[n], VEIN, life * (0.25 + 0.6 * wave) * 0.8, 0.25)
	var tip: Vector2 = screen[screen.size() - 1]
	if not _occ(tip.x, tip.y, part.rank):
		_halo(_glow, tip, CORE.lerp(EYE, 0.45) if i >= TD_COUNT else CORE, life * (0.45 + 0.4 * _beat(-0.3)), 0.6)


# --- bead and shards -----------------------------------------------------------------------------------------------


func _bead_step(dt: float) -> void:
	if dt <= 0.0:
		return
	match _bead_state:
		0:
			if _pose == Pose.PERCHED and _elapsed > 0.4:
				_bead_cd -= dt
				if _bead_cd <= 0.0:
					_bead_state = 1
					_bead_age = 0.0
		1:
			if _pose != Pose.PERCHED:
				_bead_state = 0
				_bead_cd = _rng.randf_range(3.0, 6.0)
			else:
				_bead_age += dt
				var k: float = clampf(_bead_age / 1.5, 0.0, 1.0)
				_bead_r = lerpf(0.6, 2.7, smoothstep(0.0, 1.0, k))
				_bead_pos = _beak_tip + Vector2(0.0, 1.5 + _bead_r + 3.0 * k)
				if _bead_age >= 1.5:
					_bead_state = 2
					_bead_vel = 8.0
		2:
			_bead_vel += BEAD_GRAVITY * dt
			_bead_pos.y += _bead_vel * dt
			if _bead_pos.y >= ground_drop:
				_bead_state = 0
				_bead_cd = _rng.randf_range(3.0, 6.0)
				bead_dropped.emit(global_position + Vector2(_bead_pos.x, ground_drop))


func _draw_bead() -> void:
	if _bead_state == 0:
		return
	var r: float = _bead_r
	var pos: Vector2 = _bead_pos
	if _bead_state == 1:
		# the thread of pitch stretching between the beak and the swelling drop
		_seg(_body, _beak_tip.round() + Vector2(0, 1), pos.round() - Vector2(0, r - 1.0), 2.0, 1.0, _tint(OUTLINE))
		_seg(_body, _beak_tip.round() + Vector2(0, 1), pos.round() - Vector2(0, r - 1.0), 1.0, 1.0, _tint(DARK))
	var stretch: float = 1.0 + clampf(_bead_vel / 600.0, 0.0, 0.5) if _bead_state == 2 else 1.0
	_oval_px(pos, Vector2(r + 1.0, (r + 1.0) * stretch), _tint(RIM, 0.9))
	_oval_px(pos + Vector2(0.0, 0.5), Vector2(r, r * stretch), _tint(DARK))
	_oval_px(pos + Vector2(-0.4, -0.2), Vector2(maxf(0.6, r - 1.0), maxf(0.6, (r - 1.0) * stretch)), _tint(FLESH))
	_body.draw_rect(Rect2((pos + Vector2(-r * 0.45, -r * 0.5 * stretch)).round(), Vector2.ONE), _tint(CORE_HOT, 0.95))
	if r > 2.0:
		_body.draw_rect(Rect2((pos + Vector2(-r * 0.2, -r * 0.2 * stretch)).round(), Vector2.ONE), _tint(VEIN_LIGHT, 0.7))


func _oval_px(center: Vector2, radius: Vector2, color: Color) -> void:
	var cx: int = roundi(center.x)
	var cy: int = roundi(center.y)
	var ry: int = ceili(radius.y)
	for y: int in range(-ry, ry + 1):
		var q: float = float(y) / maxf(radius.y, 0.01)
		if absf(q) > 1.0:
			continue
		var w: int = int(sqrt(1.0 - q * q) * radius.x + 0.3)
		_body.draw_rect(Rect2(float(cx - w), float(cy + y), float(w * 2 + 1), 1.0), color)


func _shard_step(dt: float, t: float) -> void:
	if _pose != Pose.DEAD:
		if not _shards.is_empty():
			_shards.clear()
		return
	if not _shards_made and t >= 0.3 and not _wings.is_empty():
		_shards_made = true
		for n: int in 9:
			var wing: Wing = _wings[n % 2]
			var blade: Blade = wing.blades[_rng.randi() % wing.blades.size()]
			_shards.append({
				"pos": blade.tip + Vector2(0.0, -2.0),
				"vel": Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-10.0, 4.0)),
				"age": 0.0,
				"delay": float(n) * 0.07,
				"size": _rng.randi_range(2, 4),
				"landed": false,
			})
	if dt <= 0.0:
		return
	for shard: Dictionary in _shards:
		shard.age = float(shard.age) + dt
		if float(shard.age) < float(shard.delay) or bool(shard.landed):
			continue
		var vel: Vector2 = shard.vel
		vel.y += 340.0 * dt
		var pos: Vector2 = shard.pos
		pos += vel * dt
		if pos.y >= 0.0:
			pos.y = 0.0
			shard.landed = true
		shard.pos = pos
		shard.vel = vel


func _draw_shards() -> void:
	for shard: Dictionary in _shards:
		if float(shard.age) < float(shard.delay):
			continue
		var pos: Vector2 = shard.pos
		var size: int = int(shard.size)
		var fade: float = 1.0 - smoothstep(0.7, 1.0, clampf((_elapsed / _duration - 0.3) / 0.7, 0.0, 1.0)) * 0.0
		_body.draw_rect(Rect2(pos.round() + Vector2(-1, -1), Vector2(size + 2, 3)), _tint(OUTLINE, fade))
		_body.draw_rect(Rect2(pos.round(), Vector2(size, 1)), _tint(ROCK2, fade))
		_body.draw_rect(Rect2(pos.round() + Vector2(0, -1), Vector2(maxi(1, size - 2), 1)), _tint(ROCK3, fade))


# --- phase 2 ornaments: splinters, the broken halo, shattered blades -----------------------------------------------------


func _splinter_pos(i: int, th: float) -> Vector3:
	var sb: float = SPL_B[i] * sin(th)
	return _center + Vector3(SPL_A[i] * cos(th), sb * cos(SPL_TILT[i]), SPL_Z[i] + sb * sin(SPL_TILT[i]))


## Six small basalt splinters of his old feathers circle the body on slowly tilted ellipses, quicker as he charges; each is sorted on its own depth.
func _build_splinters(dt: float) -> void:
	var speed: float = 1.0 + 2.2 * charge + 1.2 * _judge_k
	_orb_rate = lerpf(_orb_rate, speed, 1.0 - exp(-4.0 * dt)) if dt > 0.0 else speed
	for i: int in 6:
		if dt > 0.0:
			_orb[i] += dt * SPL_W[i] * _orb_rate
		var vis: float = smoothstep(0.28 + 0.07 * float(i), 0.6 + 0.07 * float(i), _corr) * _orn_alive
		if vis < 0.03:
			continue
		var th: float = _orb[i]
		var pos: Vector3 = _splinter_pos(i, th)
		var ahead: Vector3 = _splinter_pos(i, th + (0.12 if SPL_W[i] > 0.0 else -0.12))
		var mid: Vector2 = _p(pos)
		var dir: Vector2 = _p(ahead) - mid
		dir = dir.normalized() if dir.length() > 0.05 else Vector2(1.0, -0.5).normalized()
		var half: float = SPL_LEN[i] * (0.6 + 0.4 * vis) * 0.5
		_new_part(_depth(pos), _draw_splinter.bind(mid - dir * half, mid + dir * half, vis), _glow_splinter.bind(mid + dir * half, vis))


func _draw_splinter(tail: Vector2, head: Vector2, vis: float) -> void:
	_seg(_body, tail, head, 2.0, 3.0, _tint(OUTLINE, vis))
	_seg(_body, tail, head, 1.0, 2.0, _tint(ROCK2, vis))
	_body.draw_rect(Rect2(head.round() + Vector2(-1, -1), Vector2.ONE), _tint(ROCK3, vis))


func _glow_splinter(part: Part, head: Vector2, vis: float) -> void:
	if _occ(head.x, head.y, part.rank):
		return
	_halo(_glow, head, VEIN_LIGHT.lerp(CORE_HOT, _crack_flash), vis * (0.55 + 0.45 * _beat(head.x * 0.01)), 0.3)


func _halo_point(i: int, phi: float, radius: float, bob: float) -> Vector3:
	var back: Vector3 = Vector3(_hf.x, _hf.y, 0.0) * 2.2
	return _head_c - back + Vector3(cos(phi) * radius, sin(phi) * radius, 7.5 + bob + 0.9 * sin(phi * 2.0 + float(i)))


## The old halo, broken: four arcs of bronze basalt floating above and behind the head, drifting apart and bobbing, with a thin violet glow.
func _build_halo() -> void:
	for i: int in 4:
		var fa: float = smoothstep(0.1 + 0.1 * float(i), 0.55 + 0.1 * float(i), _corr) * _orn_alive
		if fa < 0.03:
			continue
		var phi0: float = HALO_PHI[i] + HALO_W[i] * _time
		var radius: float = 9.0 + 2.6 * _corr * (1.0 + 0.3 * float(i % 2))
		var bob: float = 1.3 * sin(_time * 0.9 + float(i) * 1.7) + 1.6 * float(i % 2)
		var half: float = HALO_SPAN[i]
		var count: int = maxi(4, ceili(2.0 * half / 0.14))
		var pts: PackedVector2Array = PackedVector2Array()
		for k: int in count + 1:
			var phi: float = phi0 - half + 2.0 * half * float(k) / float(count)
			pts.append(_p(_halo_point(i, phi, radius, bob)))
		var depth: float = _depth(_halo_point(i, phi0, radius, bob))
		_new_part(depth, _draw_halo_arc.bind(pts, fa, _p(_halo_point(i, 0.0, 0.0, bob))), _glow_halo_arc.bind(pts, fa))


func _draw_halo_arc(pts: PackedVector2Array, fa: float, cen: Vector2) -> void:
	var n: int = pts.size()
	for k: int in n - 1:
		var w: float = 2.0 + sin(PI * (float(k) + 0.5) / float(n - 1))
		_seg(_body, pts[k], pts[k + 1], w, w, _tint(OUTLINE, fa))
	for k: int in n - 1:
		var w2: float = 1.0 + sin(PI * (float(k) + 0.5) / float(n - 1))
		var lit: bool = (pts[k].y + pts[k + 1].y) * 0.5 < cen.y or (pts[k].x + pts[k + 1].x) * 0.5 < cen.x - 4.0
		_seg(_body, pts[k], pts[k + 1], w2, w2, _tint(ROCK2 if lit else ROCK1, fa))
		if lit:
			_seg(_body, pts[k] + Vector2(0, -1), pts[k + 1] + Vector2(0, -1), 1.0, 1.0, _tint(ROCK3, fa * 0.9))


func _glow_halo_arc(part: Part, pts: PackedVector2Array, fa: float) -> void:
	for k: int in range(1, pts.size() - 1, 2):
		if not _occ(pts[k].x, pts[k].y, part.rank):
			_halo(_glow, pts[k], VEIN, fa * 0.4, 0.1)
	for e: Vector2 in [pts[0], pts[pts.size() - 1]]:
		if not _occ(e.x, e.y, part.rank):
			_halo(_glow, e, VEIN_LIGHT, fa * 0.5 * (0.7 + 0.3 * _beat(e.x * 0.02)), 0.35)


func _bits_step(dt: float) -> void:
	if dt <= 0.0 or _bits.is_empty():
		return
	var keep: Array[Dictionary] = []
	for bit: Dictionary in _bits:
		bit.age = float(bit.age) + dt
		if float(bit.age) >= float(bit.life):
			continue
		var vel: Vector2 = bit.vel
		vel.y += 260.0 * dt
		vel *= exp(-0.8 * dt)
		bit.vel = vel
		bit.pos = Vector2(bit.pos) + vel * dt
		keep.append(bit)
	_bits = keep


func _draw_bits() -> void:
	for bit: Dictionary in _bits:
		var fade: float = 1.0 - smoothstep(0.55, 1.0, float(bit.age) / float(bit.life))
		var pos: Vector2 = Vector2(bit.pos).round()
		var size: int = int(bit.size)
		_body.draw_rect(Rect2(pos + Vector2(-1, -1), Vector2(size + 2, size + 1)), _tint(OUTLINE, fade))
		_body.draw_rect(Rect2(pos, Vector2(size, maxi(1, size - 1))), _tint(ROCK2, fade))


func _draw_bits_glow() -> void:
	for bit: Dictionary in _bits:
		var fade: float = 1.0 - float(bit.age) / float(bit.life)
		var pos: Vector2 = Vector2(bit.pos)
		_halo(_glow, pos, VEIN_LIGHT, fade * 0.9, 0.3)
		_glow.draw_rect(Rect2(pos.round(), Vector2.ONE), Color(CORE_HOT, _alpha * clampf(fade * 1.4, 0.0, 1.0)))


# --- sorting and drawing -------------------------------------------------------------------------------------------


func _finish_parts() -> void:
	_parts.sort_custom(func(a: Part, b: Part) -> bool:
		if a.depth != b.depth:
			return a.depth < b.depth
		return a.order < b.order)
	_sorted = _parts.duplicate()
	_bounds = Rect2()
	for i: int in _sorted.size():
		_sorted[i].rank = i
		_expand_bounds(_sorted[i].span)


func _draw_main() -> void:
	if not _ready_geo:
		return
	var t0: int = Time.get_ticks_usec()
	for part: Part in _sorted:
		if part.draw.is_valid():
			part.draw.call()
	_draw_bead()
	_draw_shards()
	_draw_bits()
	stat_draw_us += Time.get_ticks_usec() - t0


func _draw_glow() -> void:
	if not _ready_geo:
		return
	var t0: int = Time.get_ticks_usec()
	_vein_seen.clear()
	for part: Part in _sorted:
		if part.glow.is_valid():
			part.glow.call(part)
	_draw_bits_glow()
	stat_draw_us += Time.get_ticks_usec() - t0
