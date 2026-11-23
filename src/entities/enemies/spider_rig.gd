class_name SpiderRig
extends Node2D
## Shadowspore 2.0 — True 8-legged + Pedipalp/Chelicera Void-Mycelium Arachnid Rig (`T1`, `V1`..`V6`).
## - 8 world-anchored arachnid limbs (Pairs I..IV) in alternating 2x4 tetrapod gait with metachronal wave
##   + 2 feeling Pedipalps + 2 articulated Chelicerae fangs.
## - 3D-raymarched 2-segment body sheet (`40x36`, 8 true facings x 6 rows: 4-phase Opisthosoma breathing,
##   pre-strike engorged swell, and battle-cracked `< 50%` HP / `EXPOSED` carapace).
## - 8-point tarsus ground contact AO + belly shadow + live `SunShadows.cast` sheared silhouette projection.
## - Zero-allocation draw buffers, `RigClock` frame throttling, 3 brood phenotypes, directional hit-recoil & Death Curl.

signal foot_landed(world_pos: Vector2)

enum Pose {
	LOCOMOTION,
	WINDUP,
	STRIKE,
	RECOVER,
	DEAD,
	THROW,
	PULL,
	OBSERVE,
	COIL,
	CLIMB_REACH,
	CLIMB,
	HESITATE,
	BACKSTEP,
	VENOM_WINDUP,
	VENOM_LUNGE,
	EXPOSED,
	CROUCH,
	CANOPY_HANG,
	CANOPY_DROP,
	RECOIL,
	IMPALED
}

const BODY_COLS: int = 8
const BODY_ROWS: int = 6

class Leg:
	extends RefCounted
	var angle: float = 0.0
	var radius: float = 18.0
	var root: Vector2 = Vector2.ZERO
	var thickness: float = 4.0
	var arch_boost: float = 1.0
	var grabber: bool = false
	var side: float = 1.0
	var phase: float = 0.0
	var metachronal: float = 0.0 ## Rear-to-front swing delay fraction within a tetrapod half-cycle
	var foot: Vector2 = Vector2.ZERO
	var height: float = 0.0
	var stepping: bool = false
	var step_t: float = 0.0
	var step_from: Vector2 = Vector2.ZERO
	var step_to: Vector2 = Vector2.ZERO
	var pose_from: Vector2 = Vector2.ZERO
	var pose_height: float = 0.0
	var mass: float = 1.0
	var dead_from: Vector2 = Vector2.ZERO
	var front: bool = false
	var straighten: float = 0.0
	var points: PackedVector2Array = PackedVector2Array()
	var step_time: float = 0.11
	var lift: float = 6.5
	var trigger: float = 6.5
	var cooldown: float = 0.0
	var idle_timer: float = 1.0
	var twitch: float = 0.0
	var group: int = 0
	var swung: bool = false

## True 8-Legged Arachnid Layout (Pairs I..IV, alternating R/L):
## Groups `[0, 1, 1, 0, 0, 1, 1, 0]` = classic spider tetrapod (`R1, L2, R3, L4` vs `L1, R2, L3, R4`).
const LEG_DEFS: Array[Dictionary] = [
	{"angle": 30.0, "radius": 19.5, "root": Vector2(5.2, 2.6), "thick": 4.5, "arch": 1.12, "grabber": true, "side": 1.0, "meta": 0.24},
	{"angle": -34.0, "radius": 19.0, "root": Vector2(5.2, -2.6), "thick": 4.5, "arch": 1.12, "grabber": true, "side": -1.0, "meta": 0.24},
	{"angle": 68.0, "radius": 21.5, "root": Vector2(2.2, 3.6), "thick": 4.1, "arch": 1.05, "grabber": false, "side": 1.0, "meta": 0.16},
	{"angle": -73.0, "radius": 21.0, "root": Vector2(2.2, -3.6), "thick": 4.1, "arch": 1.05, "grabber": false, "side": -1.0, "meta": 0.16},
	{"angle": 108.0, "radius": 21.5, "root": Vector2(-0.8, 3.8), "thick": 3.9, "arch": 1.00, "grabber": false, "side": 1.0, "meta": 0.08},
	{"angle": -112.0, "radius": 21.0, "root": Vector2(-0.8, -3.8), "thick": 3.9, "arch": 1.00, "grabber": false, "side": -1.0, "meta": 0.08},
	{"angle": 148.0, "radius": 20.5, "root": Vector2(-3.8, 3.0), "thick": 3.8, "arch": 1.08, "grabber": false, "side": 1.0, "meta": 0.00},
	{"angle": -144.0, "radius": 20.0, "root": Vector2(-3.8, -3.0), "thick": 3.8, "arch": 1.08, "grabber": false, "side": -1.0, "meta": 0.00},
]
const GAIT_GROUPS: Array[int] = [0, 1, 1, 0, 0, 1, 1, 0]

## Calibrated to tools/art_shadow_spider.py (`pro_u = 3.7`, `ab_u = -4.6`):
const EYE_SPOTS: Array[Vector3] = [
	Vector3(7.35, -1.65, 0.95),
	Vector3(7.35, 1.65, 0.95),
	Vector3(5.85, -2.95, 0.55),
	Vector3(5.85, 2.95, 0.55),
]
const CORE_SPOTS: Array[Vector3] = [
	Vector3(-4.35, 0.0, 1.45),
	Vector3(-6.40, 1.15, 0.80),
	Vector3(-6.40, -1.15, 0.80),
	Vector3(3.20, 0.0, 0.72),
]

const BODY_HEIGHT: float = 9.5
const SQUASH: float = 0.78
const STEP_TIME: Vector2 = Vector2(0.07, 0.16)
const STEP_LIFT: Vector2 = Vector2(4.5, 9.5)
const STEP_TRIGGER: Vector2 = Vector2(5.0, 9.0)
const MAX_STRETCH: float = 27.0
const MAX_STEPPING: int = 2
const GAIT_MIN_SPEED: float = 6.0
const WOBBLE: float = 1.15
const GRAB_SPREAD: float = 8.0

const OUTLINE: Color = Color("040208")
const SHADE: Array[Color] = [Color("07040d"), Color("0e0919"), Color("1a1030"), Color("221740")]
const RIM: Color = Color("5a36b8")
const WET_RIM: Color = Color("7c62d6")
const VEIN: Color = VoidGlow.VEIN
const GLOW: Color = Color("b06bff")
const VEIN_LIGHT: Color = VoidGlow.VEIN_LIGHT
const EYE: Color = Color("ff4fd8")
const EYE_HESITATE: Color = Color("cbaaff") ## Spore-kinship lavender matching Ellie's hair!
const WARNING: Color = Color("ff4fd8")
const SHADOW_INK: Color = Color("080512")
const THORNS: Array[float] = [0.34, 0.56, 0.76]

var strike_arc: float = deg_to_rad(100.0)
var strike_hit_fraction: float = 0.58
var attack_side: float = 1.0
var strike_reach: float = 26.0
var damage_flash: float = 0.0
var agitation: float = 0.0
var emergence: float = 1.0
var emergence_seed: float = 0.0
var health_ratio: float = 1.0 ## < 0.5 reveals battle-cracked Opisthosoma row + subtle limp!
var air_height: float = 0.0 ## > 0 during CANOPY_HANG / CANOPY_DROP
var ceiling_height: float = 62.0 ## Silk drop line height above ground
var brood_variant: int = 0 ## 0 = Common, 1 = Scout (0.88x, long legs), 2 = Thorn Elder (1.14x, permanent barbs)
var finisher_stage: int = 0 ## 0 = gather, 1 = Plunge pinned, 2 = Second Deep Press cracked, 3 = Rip-Out yank

var _body_scale_mult: float = 1.0
var _leg_scale_mult: float = 1.0
var _permanent_thorns: bool = false

var _legs: Array[Leg] = []
var _aim: Vector2 = Vector2.DOWN
var _heading: float = PI / 2.0
var _ground_heading: float = PI / 2.0
var _pose: Pose = Pose.LOCOMOTION
var _pose_elapsed: float = 0.0
var _pose_duration: float = 1.0
var _time: float = 0.0
var _gait_phase: float = 0.0
var _alpha: float = 1.0
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE
var _warning: float = 0.0
var _hesitate_blend: float = 0.0
var _fang_open: float = 0.0
var _feet_ready: bool = false
var _anchor: Vector2 = Vector2.ZERO
var _hit_jolt: Vector2 = Vector2.ZERO
var _noise: FastNoiseLite = FastNoiseLite.new()
var _twitch_timer: float = 1.0
var _yaw: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _emission: Sprite2D
var _shadow_layer: Node2D
var _body_offset: Vector2 = Vector2(0, -BODY_HEIGHT)
var _climb_start: Vector2
var _climb_end: Vector2
var _climb_grip: Vector2
var _clock: RigClock = RigClock.new()
var _swing_group: int = 0
var _swing_t: float = 0.0
var _was_moving: bool = false
var _half_cycle: float = 0.28
var _was_on_screen: bool = true
var _sent_flash: float = -1.0
var _sent_flash_color: Color = Color(-1.0, -1.0, -1.0, -1.0)
var _sent_pulse: float = -1.0
var _sent_warning: float = -1.0

var _draw_cx: PackedFloat32Array = PackedFloat32Array()
var _draw_cy: PackedFloat32Array = PackedFloat32Array()
var _draw_d: PackedInt32Array = PackedInt32Array()
var _draw_fade: PackedFloat32Array = PackedFloat32Array()
var _draw_t: PackedFloat32Array = PackedFloat32Array()
var _draw_rim_x: PackedFloat32Array = PackedFloat32Array()
var _draw_rim_y: PackedFloat32Array = PackedFloat32Array()
var _draw_rim_fade: PackedFloat32Array = PackedFloat32Array()

@onready var _back: Node2D = $Back
@onready var _body: Sprite2D = $Body
@onready var _front: Node2D = $Front
@onready var _glow: Node2D = $Glow


func _ready() -> void:
	_body.hframes = BODY_COLS
	_body.vframes = BODY_ROWS
	_emission = ShadowEmission.attach(_body)

	_shadow_layer = Node2D.new()
	_shadow_layer.name = "GroundShadow"
	_shadow_layer.z_as_relative = false
	_shadow_layer.z_index = -5
	add_child(_shadow_layer)
	move_child(_shadow_layer, 0)
	_shadow_layer.draw.connect(_draw_ground_shadow)

	for def_index: int in LEG_DEFS.size():
		var def: Dictionary = LEG_DEFS[def_index]
		var leg: Leg = Leg.new()
		leg.group = GAIT_GROUPS[def_index]
		leg.angle = deg_to_rad(float(def["angle"]))
		leg.radius = float(def["radius"])
		leg.root = def["root"] as Vector2
		leg.thickness = float(def["thick"])
		leg.arch_boost = float(def["arch"])
		leg.grabber = bool(def["grabber"])
		leg.side = float(def["side"])
		leg.metachronal = float(def["meta"])
		leg.phase = randf() * TAU
		leg.idle_timer = randf_range(0.3, 2.5)
		_randomize_step(leg)
		_legs.append(leg)

	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = randi()
	_noise.frequency = 1.0
	_back.draw.connect(func() -> void: _draw_layer(_back, false))
	_front.draw.connect(func() -> void: _draw_layer(_front, true))
	_glow.draw.connect(_draw_glow)
	apply_brood_variant(brood_variant)


func apply_brood_variant(variant_idx: int) -> void:
	brood_variant = clampi(variant_idx, 0, 2)
	match brood_variant:
		1: ## Späh-Brut: smaller agile body, longer skittering reach
			_body_scale_mult = 0.88
			_leg_scale_mult = 1.08
			_permanent_thorns = false
		2: ## Alte Dornenspinne: larger scarred carapace, permanent chitin barbs
			_body_scale_mult = 1.14
			_leg_scale_mult = 1.06
			_permanent_thorns = true
		_:
			_body_scale_mult = 1.0
			_leg_scale_mult = 1.0
			_permanent_thorns = false


func set_aim(dir: Vector2) -> void:
	if dir != Vector2.ZERO:
		_aim = dir.normalized()


func set_anchor(point: Vector2) -> void:
	_anchor = point


func set_climb(from: Vector2, to: Vector2, upward: bool) -> void:
	_climb_start = from
	_climb_end = to
	var direction: Vector2 = (to - from).normalized()
	_climb_grip = to - direction * 10.0 if upward else from + direction * 8.0


func start_pose(pose: Pose, duration: float, elapsed: float = 0.0) -> void:
	_pose = pose
	_pose_elapsed = elapsed
	_pose_duration = maxf(duration, 0.01)
	for leg: Leg in _legs:
		leg.pose_from = leg.foot
		leg.pose_height = leg.height
		leg.dead_from = leg.foot
		leg.stepping = false


func hit_flash(impulse_dir: Vector2 = Vector2.ZERO, heavy: bool = false) -> void:
	damage_flash = 1.0
	agitation = 1.0
	if impulse_dir.length_squared() > 0.01:
		var strength: float = 4.6 if heavy else 2.6
		_hit_jolt = impulse_dir.normalized() * strength
		# Legs on the struck side briefly lose purchase and re-anchor!
		for leg: Leg in _legs:
			var leg_dir: Vector2 = leg.foot - global_position
			if leg_dir.dot(-impulse_dir) > 0.15:
				leg.twitch = 1.0


func update_rig(delta: float, velocity: Vector2, heading: float) -> void:
	_pose_elapsed += delta
	delta = _clock.step(self, delta, velocity.length(), _pose != Pose.LOCOMOTION)
	if delta < 0.0:
		return
	_time += delta
	_heading = heading
	_yaw = _noise.get_noise_2d(_time * 0.6, 3.0) * (0.04 if _pose == Pose.CROUCH else 0.11)
	_sway = Vector2(_noise.get_noise_2d(_time * 0.8, 7.0) * 1.0, _noise.get_noise_2d(_time * 1.1, 11.0) * 0.6)
	if _pose == Pose.CROUCH:
		_sway *= 0.2
	_hit_jolt = _hit_jolt.move_toward(Vector2.ZERO, 22.0 * delta)
	_ground_heading = Vector2(cos(heading + _yaw), sin(heading + _yaw) / SQUASH).angle()
	var t: float = clampf(_pose_elapsed / _pose_duration, 0.0, 1.0)
	damage_flash = move_toward(damage_flash, 0.0, 6.0 * delta)
	agitation = move_toward(agitation, 0.0, 2.5 * delta)
	_hesitate_blend = move_toward(_hesitate_blend, 1.0 if _pose == Pose.HESITATE else 0.0, 5.5 * delta)

	var want_fangs: float = 1.0 if _pose in [Pose.WINDUP, Pose.STRIKE, Pose.VENOM_WINDUP, Pose.VENOM_LUNGE, Pose.THROW, Pose.IMPALED] else (0.45 if _pose == Pose.EXPOSED else 0.0)
	_fang_open = move_toward(_fang_open, want_fangs, 8.0 * delta)

	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(1.1, 2.2) if health_ratio < 0.5 else randf_range(2.4, 4.5)
		var leg_idx: int = 7 if health_ratio < 0.5 else (randi() % _legs.size())
		_legs[leg_idx].twitch = 1.0
		agitation = maxf(agitation, 0.15)

	var origin: Vector2 = global_position
	if not _feet_ready:
		for leg: Leg in _legs:
			leg.foot = _rest_foot(leg, origin)
			leg.pose_from = leg.foot
		_feet_ready = true

	_gait_phase += velocity.length() * 0.16 * delta
	var run_speed: float = velocity.length()
	if run_speed >= GAIT_MIN_SPEED and _pose == Pose.LOCOMOTION:
		_half_cycle = lerpf(0.24, 0.10, clampf(run_speed / 110.0, 0.0, 1.0))
		_swing_t += delta
		if _swing_t >= _half_cycle:
			_swing_t = 0.0
			_swing_group = 1 - _swing_group
			for leg: Leg in _legs:
				leg.swung = false
	else:
		_swing_t = 0.0
		if _was_moving and _pose == Pose.LOCOMOTION:
			for leg: Leg in _legs:
				leg.twitch = maxf(leg.twitch, randf_range(0.35, 0.85))
			agitation = maxf(agitation, 0.18)
	_was_moving = run_speed >= GAIT_MIN_SPEED

	var on_screen: bool = true if RigClock.OFFSCREEN_HZ <= 0.0 else RigClock.on_screen(self)
	_was_on_screen = on_screen
	if on_screen:
		_update_body(t, velocity)

	for leg: Leg in _legs:
		if emergence < 1.0:
			var order: float = 0.24 if leg.grabber else (0.37 if absf(leg.angle) < 1.8 else 0.50)
			var odd: float = sin(leg.angle * 17.0 + emergence_seed)
			order += odd * 0.06
			var reach: float = smoothstep(order, order + 0.30, emergence)
			reach = clampf(reach + sin(reach * TAU * 1.5 + odd) * sin(reach * PI) * 0.10, 0.0, 1.0)
			var pull: Vector2 = -_aim * (1.0 - emergence) * 9.0
			leg.foot = origin + pull + (_rest_foot(leg, origin) - origin) * reach
			leg.height = sin(reach * PI) * 9.0
			leg.mass = lerpf(0.15, 1.0, reach)
			leg.stepping = false
		else:
			_update_leg(leg, delta, origin, velocity, t)
		if on_screen:
			_build_curve(leg, origin)
			leg.front = leg.foot.y >= origin.y - 2.5 or leg.height > 6.5

	if on_screen:
		_shadow_layer.queue_redraw()
		_back.queue_redraw()
		_front.queue_redraw()
		_glow.queue_redraw()


func _select_body_row() -> int:
	if _pose == Pose.IMPALED:
		return 5 if finisher_stage >= 2 else (4 if finisher_stage == 1 else 5)
	if _pose == Pose.EXPOSED or health_ratio < 0.50:
		return 5 ## Cracked carapace exposing glowing spore-fissures!
	if _pose in [Pose.COIL, Pose.THROW, Pose.VENOM_WINDUP, Pose.VENOM_LUNGE, Pose.WINDUP]:
		return 4 ## Engorged pre-strike Opisthosoma swell!
	var breathe_rate: float = 0.9 if _pose == Pose.CROUCH else 2.2
	return posmod(int(_time * breathe_rate), 4)


func _update_body(t: float, velocity: Vector2) -> void:
	var offset: Vector2 = Vector2(0, -BODY_HEIGHT * _body_scale_mult - air_height) + _hit_jolt
	var scale_goal: Vector2 = Vector2.ONE * _body_scale_mult
	var rot_goal: float = 0.0
	var speed: float = clampf(velocity.length() / 100.0, 0.0, 1.0)
	offset += -velocity * 0.018 + _sway
	offset.y += sin(_time * 2.1) * 0.35
	scale_goal *= Vector2(1.0 + speed * 0.08, 1.0 - speed * 0.10)

	if speed > 0.05 and _pose == Pose.LOCOMOTION:
		var gp: float = clampf(_swing_t / maxf(_half_cycle, 0.01), 0.0, 1.0)
		var lateral: float = sin((float(_swing_group) + gp) * PI)
		var side: Vector2 = Vector2.from_angle(_heading).orthogonal()
		offset += side * lateral * 1.15 * speed
		offset.y += (0.5 + 0.5 * cos(gp * TAU)) * 0.85 * speed + speed * 1.2
		if health_ratio < 0.5:
			offset.y += maxf(0.0, sin(_gait_phase * 2.2)) * 1.2 ## Subtle battle-wounded limp!

	var telegraph: float = 0.0
	_warning = 0.0
	match _pose:
		Pose.CROUCH:
			offset.y += 3.8
			scale_goal *= Vector2(1.06, 0.84)
		Pose.CANOPY_HANG:
			offset.y += sin(_time * 1.8) * 1.2
			scale_goal *= Vector2(0.94, 1.06)
		Pose.CANOPY_DROP:
			scale_goal *= Vector2(0.90, 1.14)
			_warning = 0.55
		Pose.HESITATE:
			# Curious head-tilt recognizing Ellie's spore-mycelium kinship (`T2`, `V4`)!
			var tilt_wave: float = sin(minf(t * 1.3, 1.0) * PI)
			offset.y -= tilt_wave * 1.4
			rot_goal = 0.11 * attack_side * smoothstep(0.0, 0.45, t)
			if t > 0.68: ## Valdrics Sun-Quartz sears its senses at the end of hesitate!
				_warning = smoothstep(0.68, 1.0, t) * 0.85
				offset += -_aim * smoothstep(0.68, 1.0, t) * 2.2
		Pose.OBSERVE:
			offset.y -= sin(t * PI) * 1.6
			scale_goal *= Vector2(0.95, 1.07)
		Pose.WINDUP:
			var e: float = smoothstep(0.0, 0.8, t)
			offset += -_aim * 3.2 * e + Vector2(0, -2.2 * e)
			scale_goal *= Vector2(1.0 + 0.14 * e, 1.0 - 0.10 * e)
			_warning = e
			telegraph = 0.08 * e
		Pose.VENOM_WINDUP:
			var ev: float = smoothstep(0.0, 0.85, t)
			offset += -_aim * 4.2 * ev + Vector2(0, 2.2 * ev)
			scale_goal *= Vector2(1.12 * (1.0 + 0.06 * ev), 0.88)
			_warning = ev
			telegraph = 0.10 * ev
		Pose.VENOM_LUNGE:
			offset += _aim * 5.0 * sin(t * PI) + Vector2(0, -1.5 * sin(t * PI))
			scale_goal *= Vector2(0.88, 1.16)
			_warning = 1.0
			telegraph = 0.14 * sin(t * PI)
		Pose.COIL:
			var ec: float = smoothstep(0.0, 0.85, t)
			offset += -_aim * 3.0 * ec + Vector2(0, 3.4 * ec)
			scale_goal *= Vector2(1.0 + 0.22 * ec, 1.0 - 0.26 * ec)
			_warning = ec
			telegraph = 0.08 * ec
		Pose.STRIKE:
			offset += _aim * 3.2 * sin(t * PI)
			scale_goal *= Vector2(0.93, 1.11)
			_warning = 1.0
			telegraph = 0.12 * sin(t * PI)
		Pose.THROW:
			offset += _aim * 4.0 * t + Vector2(0, 2.0)
			scale_goal *= Vector2(0.88, 1.15)
			_warning = 1.0
		Pose.PULL:
			offset += -_aim * 3.0
			scale_goal *= Vector2(0.94, 1.08)
			_warning = 0.65
		Pose.BACKSTEP:
			offset += -_aim * sin(t * PI) * 2.5 - Vector2(0, sin(t * PI) * 3.2)
			scale_goal *= Vector2(0.92, 1.08)
		Pose.RECOIL:
			offset += -_aim * (1.0 - t) * 3.0 + Vector2(0, -sin(t * PI) * 1.8)
			_warning = 0.35 * (1.0 - t)
		Pose.EXPOSED:
			# Knocked flat onto sternum, pulsing Opisthosoma helplessly exposed (`T5`, `V6`)!
			offset.y += 4.2 * smoothstep(0.0, 0.22, t) * (1.0 - smoothstep(0.82, 1.0, t))
			offset.x += sin(_time * 28.0) * 0.6 * (1.0 - t * 0.5)
			scale_goal *= Vector2(1.14, 0.84)
			rot_goal = sin(_time * 16.0) * 0.05
			_warning = 0.45 + 0.35 * sin(_time * 18.0)
		Pose.CLIMB_REACH:
			var reach_c: float = smoothstep(0.0, 0.9, t)
			offset += -_aim * 2.0 * reach_c + Vector2(0, 2.0 * reach_c)
			scale_goal *= Vector2(1.12, 0.86)
			_warning = reach_c * 0.35
		Pose.CLIMB:
			offset += -_aim * (1.0 + sin(t * PI) * 3.0)
			scale_goal *= Vector2(0.90, 1.14)
			_warning = 0.3 + sin(t * PI) * 0.15
		Pose.RECOVER:
			offset.y += 2.0 * (1.0 - t)
			scale_goal *= Vector2(1.0 + 0.14 * (1.0 - t), 1.0 - 0.16 * (1.0 - t))
		Pose.IMPALED:
			# V2 Finisher (`spider_impale_down`): 3-beat visceral reaction synchronized with Ellie's sword!
			if finisher_stage <= 0:
				offset.y += 1.4
				scale_goal *= Vector2(1.04, 0.94)
				_warning = 0.45
			elif finisher_stage == 1:
				# Beat 1 (Plunge): Slammed flat onto earth, violent pain spasm!
				offset.y += 4.2
				offset.x += sin(_time * 46.0) * 0.7
				scale_goal *= Vector2(1.13, 0.84)
				_warning = 0.88
				telegraph = 0.12
			elif finisher_stage == 2:
				# Beat 2 (Second Deep Press!): Crushed 1.5 px deeper, cracked carapace blazing `#ecd2ff`!
				offset.y += 5.6
				offset.x += sin(_time * 68.0) * 1.15
				scale_goal *= Vector2(1.20, 0.76)
				rot_goal = sin(_time * 52.0) * 0.06
				_warning = 1.0
				telegraph = 0.16
			else:
				# Beat 3 (Rip-Out!): Yanked upward by the wrenching blade right as core detonates!
				offset.y -= 2.8
				scale_goal *= Vector2(0.92, 1.14)
				_warning = 1.0
		Pose.DEAD:
			# Authentic Arachnid Death Curl: sternum settles onto earth rather than cartoon pancake!
			offset.y += 4.8 * smoothstep(0.0, 0.65, t)
			scale_goal *= Vector2(0.96 - t * 0.08, 0.92 - t * 0.22)
			_alpha = 1.0 - smoothstep(0.35, 1.0, t)

	if _pose != Pose.DEAD:
		_alpha = 1.0
	if emergence < 1.0:
		var form: float = smoothstep(0.22, 0.93, emergence)
		var heave: float = sin(smoothstep(0.50, 1.0, emergence) * PI)
		var struggle: float = sin(emergence * 23.0 + emergence_seed) * sin(form * PI)
		offset += Vector2(struggle * 1.8, absf(struggle) * 1.3)
		offset = Vector2(0, 2).lerp(offset, form) - _aim * (1.0 - form) * 9.0
		offset.y -= heave * 4.0
		scale_goal *= Vector2(lerpf(0.30, 1.0, form) + sin(form * PI) * 0.20, lerpf(0.12, 1.0, form))
		_alpha = smoothstep(0.17, 0.35, emergence)

	offset += Vector2(sin(_time * 43.0), cos(_time * 31.0)) * agitation * 0.75
	_body_offset = offset
	_body.position = offset.round()
	_body.scale = scale_goal
	_body.rotation = rot_goal

	var sector_col: int = posmod(roundi((_heading + _yaw) / (PI / 4.0)), BODY_COLS)
	var anim_row: int = _select_body_row()
	_body.frame = anim_row * BODY_COLS + sector_col

	_flash = maxf(damage_flash, telegraph)
	_flash_color = Color.WHITE if damage_flash >= telegraph else WARNING
	var material: ShaderMaterial = _body.material as ShaderMaterial
	if material != null:
		if absf(_flash - _sent_flash) > 0.004 or (_flash == 0.0 and _sent_flash != 0.0):
			_sent_flash = _flash
			material.set_shader_parameter("flash", _flash)
		if _flash_color != _sent_flash_color:
			_sent_flash_color = _flash_color
			material.set_shader_parameter("flash_color", _flash_color)
	_body.modulate.a = _alpha
	_emission.frame = _body.frame
	var glow_material: ShaderMaterial = _emission.material as ShaderMaterial
	if glow_material != null:
		var next_pulse: float = VoidGlow.pulse(_time, 0.0, 0.9 + _warning * 1.6, 0.25)
		if absf(next_pulse - _sent_pulse) > 0.008:
			_sent_pulse = next_pulse
			glow_material.set_shader_parameter("pulse", next_pulse)
		if absf(_warning - _sent_warning) > 0.008 or (_warning == 0.0 and _sent_warning != 0.0):
			_sent_warning = _warning
			glow_material.set_shader_parameter("warning", _warning)


func _squash(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * SQUASH)


func _rest_foot(leg: Leg, origin: Vector2) -> Vector2:
	var r_eff: float = leg.radius * _leg_scale_mult
	if _pose == Pose.CROUCH:
		r_eff *= 0.56
	return origin + _squash(Vector2.from_angle(_ground_heading + leg.angle) * r_eff)


func _stepping_count() -> int:
	var count: int = 0
	for other: Leg in _legs:
		if other.stepping:
			count += 1
	return count


func _start_step(leg: Leg, target: Vector2) -> void:
	leg.stepping = true
	leg.step_t = 0.0
	leg.step_from = leg.foot
	leg.step_to = target


func _randomize_step(leg: Leg) -> void:
	leg.step_time = randf_range(STEP_TIME.x, STEP_TIME.y)
	leg.lift = randf_range(STEP_LIFT.x, STEP_LIFT.y)
	leg.trigger = randf_range(STEP_TRIGGER.x, STEP_TRIGGER.y)
	leg.cooldown = randf_range(0.0, 0.07)


func _update_leg(leg: Leg, delta: float, origin: Vector2, velocity: Vector2, t: float) -> void:
	var rest: Vector2 = _rest_foot(leg, origin)
	var across: Vector2 = _aim.orthogonal() * leg.side
	var active: bool = leg.grabber and leg.side == attack_side
	leg.straighten = 0.0
	leg.mass = 1.0
	leg.twitch = move_toward(leg.twitch, 0.0, 3.0 * delta)

	if _pose == Pose.DEAD:
		# Authentic Arachnid Death Curl: all 8 legs curl inward beneath the sternum (`V6`)!
		var curl_target: Vector2 = origin + _squash(Vector2.from_angle(_ground_heading + leg.angle * 0.72) * (5.2 * _body_scale_mult))
		var curl_t: float = smoothstep(0.0, 0.72, t)
		leg.foot = leg.dead_from.lerp(curl_target, curl_t)
		leg.height = sin(curl_t * PI) * 5.5 + curl_t * 2.2
		leg.mass = 1.0 - t * 0.45
		return

	if _pose in [Pose.CANOPY_HANG, Pose.CANOPY_DROP]:
		var tuck: float = 0.46 if _pose == Pose.CANOPY_HANG else lerpf(0.55, 1.0, smoothstep(0.35, 1.0, t))
		leg.foot = origin + (_rest_foot(leg, origin) - origin) * tuck
		leg.height = air_height * (0.85 if _pose == Pose.CANOPY_HANG else (1.0 - smoothstep(0.5, 1.0, t)))
		leg.stepping = false
		return

	if _pose == Pose.EXPOSED:
		# Legs buckle wide & quiver helplessly during the 1.1s stagger window (`T5`)!
		var splay: Vector2 = origin + (_rest_foot(leg, origin) * 0.0) + (_rest_foot(leg, origin) - origin) * 1.24 + across * (2.5 * sin(_time * 22.0 + leg.phase))
		var recover_k: float = smoothstep(0.80, 1.0, t)
		leg.foot = leg.pose_from.lerp(splay, smoothstep(0.0, 0.20, t)).lerp(rest, recover_k)
		leg.height = 0.0
		leg.straighten = 0.45 * (1.0 - recover_k)
		leg.stepping = false
		return

	if _pose == Pose.IMPALED:
		leg.stepping = false
		if finisher_stage <= 0:
			var brace: Vector2 = origin + (rest - origin) * 0.92
			leg.foot = leg.pose_from.lerp(brace, minf(t * 5.0, 1.0))
			leg.height = 3.2 if leg.grabber else 0.0
		elif finisher_stage == 1:
			# Beat 1 (Plunge): All 8 legs shoot skyward in a dramatic shock spasm!
			var shock_in: Vector2 = origin + (rest - origin) * 0.80 + across * (2.2 * sin(_time * 38.0 + leg.phase))
			leg.foot = leg.foot.lerp(shock_in, minf(delta * 22.0, 1.0))
			leg.height = lerpf(leg.height, 9.6 + sin(_time * 34.0 + leg.phase) * 1.6, minf(delta * 24.0, 1.0))
			leg.straighten = 0.32
		elif finisher_stage == 2:
			# Beat 2 (Second Deep Press): Legs slam back into earth & claw frantically under the crushing blade!
			var claw_pos: Vector2 = origin + (rest - origin) * 1.18 + Vector2(sin(_time * 58.0 + leg.phase * 2.3), cos(_time * 51.0 + leg.phase)) * 2.4
			leg.foot = leg.foot.lerp(claw_pos, minf(delta * 20.0, 1.0))
			leg.height = absf(sin(_time * 42.0 + leg.phase)) * 2.2
			leg.straighten = 0.50
			leg.twitch = 1.0
		else:
			# Beat 3 (Rip-Out): Legs yank inward off the ground into Death Curl!
			var yank_in: Vector2 = origin + (rest - origin) * 0.52
			leg.foot = leg.foot.lerp(yank_in, minf(delta * 24.0, 1.0))
			leg.height = 7.5
		return

	if _pose == Pose.HESITATE:
		if leg.grabber:
			# Both front tactile legs lift gently toward Ellie, sensing spore kinship (`T2`)!
			var feel: float = sin(minf(t * 1.2, 1.0) * PI)
			leg.foot = leg.pose_from.lerp(origin + _aim * (21.0 * _leg_scale_mult) + across * 6.5, smoothstep(0.0, 0.55, t))
			leg.height = 4.5 * feel
			leg.mass = 0.85
		else:
			leg.foot = leg.pose_from
			leg.height = 0.0
		leg.stepping = false
		return

	if _pose == Pose.CLIMB_REACH:
		var ec: float = smoothstep(0.0, 0.85, t)
		leg.foot = leg.pose_from.lerp(_climb_grip + across * GRAB_SPREAD, ec) if leg.grabber else leg.pose_from
		leg.height = leg.pose_height * (1.0 - ec)
		leg.straighten = ec * 0.8 if leg.grabber else 0.0
		leg.mass = 1.0 + ec * (0.3 if leg.grabber else 0.15)
		leg.stepping = false
		return

	if _pose == Pose.CLIMB:
		if leg.grabber:
			leg.foot = (_climb_grip + across * GRAB_SPREAD).lerp(rest, smoothstep(0.73, 1.0, t))
			leg.height = 0.0
			leg.straighten = 0.9 * (1.0 - smoothstep(0.7, 1.0, t))
			leg.mass = 0.85
		else:
			var cycle: float = t * 3.0 + (0.5 if leg.side > 0.0 else 0.0) + (0.22 if leg.root.x < 0.0 else 0.0)
			var contact: float = clampf(floorf(cycle) / 3.0 - 0.18, 0.0, 1.0)
			var next_contact: float = minf(1.0, contact + 1.0 / 3.0)
			var k_c: float = fposmod(cycle, 1.0)
			var wall_foot: Vector2 = _climb_start.lerp(_climb_end, lerpf(contact, next_contact, smoothstep(0.65, 1.0, k_c))) + across * leg.radius * 0.65 - _aim * 6.0
			leg.foot = leg.pose_from.lerp(wall_foot, smoothstep(0.0, 0.2, t)).lerp(rest, smoothstep(0.84, 1.0, t))
			leg.height = sin(smoothstep(0.65, 1.0, k_c) * PI) * 2.0
			leg.mass = 1.15 - sin(k_c * PI) * 0.3
		leg.stepping = false
		return

	if _pose in [Pose.WINDUP, Pose.COIL, Pose.STRIKE, Pose.THROW, Pose.PULL, Pose.RECOVER, Pose.VENOM_WINDUP, Pose.VENOM_LUNGE]:
		if leg.grabber:
			match _pose:
				Pose.WINDUP:
					var ew: float = smoothstep(0.0, 0.9, t)
					var folded: Vector2 = origin - _aim * 5.0 + across * (7.0 if active else 12.0)
					leg.foot = leg.pose_from.lerp(folded, ew) if active else leg.pose_from
					leg.height = lerpf(leg.pose_height, 13.5 if active else 0.0, ew)
					leg.mass = 1.0 + ew * (0.65 if active else 0.1)
				Pose.VENOM_WINDUP:
					var evw: float = smoothstep(0.0, 0.9, t)
					leg.foot = leg.pose_from.lerp(origin - _aim * 4.0 + across * 9.5, evw)
					leg.height = lerpf(leg.pose_height, 9.5, evw)
					leg.mass = 1.35
				Pose.VENOM_LUNGE:
					var evl: float = sin(t * PI)
					leg.foot = origin + _aim * (20.0 + 8.0 * evl) + across * (5.0 - 2.5 * evl)
					leg.height = 4.0 * evl
					leg.straighten = 0.65 * evl
					leg.mass = 1.3
				Pose.COIL:
					var ecoil: float = smoothstep(0.0, 0.9, t)
					leg.foot = leg.pose_from.lerp(origin - _aim * 6.0 + across * 5.0, ecoil)
					leg.height = lerpf(leg.pose_height, 2.0, ecoil)
					leg.mass = 1.0 + ecoil * 0.4
				Pose.STRIKE:
					if active:
						# Exact sector match (`< 0.05 px` agreement verified by test_void_predator.gd)!
						var grow_end: float = strike_hit_fraction * 0.35
						var growth: float = smoothstep(0.0, grow_end, t)
						var sweep: float = smoothstep(grow_end, strike_hit_fraction, t)
						var direction: Vector2 = _aim.rotated(lerpf(attack_side * strike_arc * 0.5, -attack_side * strike_arc * 0.5, sweep))
						leg.foot = leg.pose_from.lerp(origin + Vector2(0, 2) + direction * strike_reach, growth)
						leg.height = leg.pose_height * (1.0 - growth)
						leg.mass = lerpf(1.65, 0.95, growth)
						leg.straighten = growth * 0.45
					else:
						leg.foot = leg.pose_from
						leg.height = 0.0
				Pose.THROW:
					var et: float = pow(t, 2.0)
					leg.foot = leg.pose_from.lerp(_anchor + across * GRAB_SPREAD, et)
					leg.height = leg.pose_height * (1.0 - et)
					leg.straighten = et
					leg.mass = lerpf(1.4, 0.65, et)
				Pose.PULL:
					leg.foot = _anchor + across * GRAB_SPREAD
					leg.height = 0.0
					leg.straighten = 1.0
					leg.mass = 0.75
				Pose.RECOVER:
					var er: float = smoothstep(0.0, 0.85, t)
					var fold_r: Vector2 = origin + across * 6.0
					leg.foot = leg.pose_from.lerp(fold_r, smoothstep(0.0, 0.48, t)).lerp(rest, smoothstep(0.48, 1.0, t))
					leg.height = lerpf(leg.pose_height, 0.0, er) + sin(t * PI) * 3.0
					leg.mass = 0.7 + er * 0.3
			leg.stepping = false
			return
		elif _pose not in [Pose.PULL, Pose.RECOVER, Pose.VENOM_LUNGE]:
			leg.foot = leg.pose_from
			leg.height = lerpf(leg.pose_height, 0.0, minf(t * 6.0, 1.0))
			leg.mass = 1.2
			return

	if _pose == Pose.OBSERVE and active:
		leg.foot = leg.pose_from.lerp(origin + _aim * 25.0 + across * 4.0, smoothstep(0.0, 1.0, t))
		leg.height = 3.0
		leg.mass = 0.65
		return

	leg.cooldown -= delta
	leg.idle_timer -= delta
	if leg.stepping:
		leg.step_t += delta / leg.step_time
		var k: float = minf(leg.step_t, 1.0)
		var fold: Vector2 = origin + (leg.step_from - origin) * 0.46
		leg.foot = leg.step_from.lerp(fold, smoothstep(0.0, 0.42, k)).lerp(leg.step_to, smoothstep(0.36, 1.0, k))
		leg.height = sin(PI * k) * leg.lift * 0.68
		leg.mass = 1.0 - sin(k * PI) * 0.42
		if leg.step_t >= 1.0:
			leg.stepping = false
			leg.height = 0.0
			_randomize_step(leg)
			foot_landed.emit(leg.foot)
		return

	leg.height = move_toward(leg.height, 0.0, 35.0 * delta)
	var stretch: float = leg.foot.distance_to(rest)
	var speed: float = velocity.length()
	if speed >= GAIT_MIN_SPEED:
		var max_air: int = 4 if speed > 92.0 else 3
		var air_ok: bool = _stepping_count() < max_air
		if stretch > MAX_STRETCH * _leg_scale_mult and air_ok:
			_start_step(leg, rest + velocity * 0.09)
		elif leg.group == _swing_group and not leg.swung and not leg.stepping and air_ok and _swing_t >= _half_cycle * leg.metachronal:
			leg.swung = true
			var speed_k: float = clampf(speed / 110.0, 0.0, 1.0)
			leg.step_time = clampf(_half_cycle * 0.62, 0.055, 0.16) * randf_range(0.94, 1.06)
			leg.lift = lerpf(8.5, 5.2, speed_k) * randf_range(0.88, 1.12)
			_start_step(leg, rest + velocity * (leg.step_time * 1.65 + 0.025))
		return

	if _pose == Pose.CROUCH:
		if stretch > 7.5:
			_start_step(leg, rest)
		return

	var free: bool = _stepping_count() < MAX_STEPPING
	if stretch > MAX_STRETCH * _leg_scale_mult or (leg.cooldown <= 0.0 and free and stretch > leg.trigger):
		_start_step(leg, rest + velocity * 0.09)
	elif leg.idle_timer <= 0.0 and free:
		if leg.grabber:
			leg.idle_timer = randf_range(0.65, 1.6)
			leg.lift = randf_range(4.0, 6.5)
			leg.step_time = randf_range(0.07, 0.12)
			_start_step(leg, rest + Vector2.from_angle(_ground_heading) * randf_range(2.0, 5.0) + Vector2(randf_range(-2.2, 2.2), randf_range(-1.5, 1.5)))
		else:
			leg.idle_timer = randf_range(2.0, 4.6)
			leg.lift = 3.0
			_start_step(leg, rest + Vector2(randf_range(-2.5, 2.5), randf_range(-1.8, 1.8)))


## Sculpted 3/4 High-Patella Arachnid Curve (`T1`, `V2`):
## Rises steep out of the sternum coxa into an unmistakable high patella arch above dorsal height,
## then plunges vertically into a razor-sharp tarsus tip anchored in world space.
func _build_curve(leg: Leg, origin: Vector2) -> void:
	var fwd: Vector2 = Vector2.from_angle(_ground_heading)
	var right: Vector2 = fwd.orthogonal()
	var root: Vector2 = origin + _body_offset + _squash(fwd * leg.root.x + right * leg.root.y) * _body.scale
	var foot: Vector2 = leg.foot + Vector2(0, -leg.height)
	var span: Vector2 = foot - root
	var span_len: float = span.length()
	var along: Vector2 = span / span_len if span_len > 0.5 else Vector2.DOWN
	var perp: Vector2 = along.orthogonal() * leg.side

	var slack: float = clampf(leg.radius * _leg_scale_mult * 0.62 - span_len * 0.10, 2.0, 14.0) * (1.0 - leg.straighten * 0.94)
	var arch_lift: float = slack * 1.12 * leg.arch_boost
	if _pose == Pose.CROUCH:
		arch_lift *= 0.68
	var control_a: Vector2 = root + span * 0.32 + perp * (slack * 0.78) + Vector2(0, -arch_lift)
	var control_b: Vector2 = root + span * 0.76 - perp * (slack * 0.35) + Vector2(0, -arch_lift * 0.58)

	var count: int = clampi(ceili(span_len * 0.88), 9, 36)
	leg.points.resize(count)
	var inv_count: float = 1.0 / float(count - 1)
	var leg_noise: float = _noise.get_noise_2d(_time * 0.8, leg.phase * 7.0)
	var wobble_scale: float = WOBBLE * (1.0 + agitation + leg.twitch) * (1.0 - leg.straighten * 0.88)
	for i: int in count:
		var u_t: float = float(i) * inv_count
		var u: float = 1.0 - u_t
		var u2: float = u * u
		var t2: float = u_t * u_t
		var point: Vector2 = u2 * u * root + 3.0 * u2 * u_t * control_a + 3.0 * u * t2 * control_b + t2 * u_t * foot
		var wave: float = leg_noise * 0.5 + sin(u_t * 7.0 - _time * 2.4 + leg.phase) * 0.5
		var envelope: float = sin(u_t * PI)
		leg.points[i] = point + perp * (wave * wobble_scale * envelope)
	# Guarantee exact endpoint contact (`0.0 px` drift)!
	leg.points[count - 1] = foot


func _tint(color: Color) -> Color:
	if _flash <= 0.001:
		return color if _alpha >= 0.999 else Color(color, color.a * _alpha)
	return Color(color.lerp(_flash_color, _flash), color.a * _alpha)


## 8-Point Tarsus Contact AO + Belly Shadow Ellipse + Dynamic `SunShadows.cast` Sheared Silhouette (`V3`)!
func _draw_ground_shadow() -> void:
	if _alpha <= 0.02 or emergence <= 0.15:
		return
	var inv: Transform2D = _shadow_layer.get_global_transform().affine_inverse()
	var air_k: float = clampf(1.0 - air_height / 72.0, 0.18, 1.0)
	var base_a: float = 0.30 * _alpha * emergence * air_k

	# 1. Dynamic Sun/Moon Cast Shadow Silhouette (matches SunShadows.current.cast & strength!)
	if SunShadows.current != null and SunShadows.current.enabled and SunShadows.current.strength > 0.04 and air_height < 24.0:
		var cast_vec: Vector2 = SunShadows.current.cast
		var sun_a: float = clampf(SunShadows.current.strength * 0.42 * _alpha * emergence, 0.0, 0.40)
		if sun_a > 0.02:
			var body_h: float = (BODY_HEIGHT + 3.0) * _body_scale_mult + air_height
			var body_cast_c: Vector2 = (inv * (global_position + cast_vec * body_h)).round()
			var rx_s: float = roundf(9.5 * _body_scale_mult)
			var ry_s: float = roundf(5.5 * _body_scale_mult)
			_shadow_layer.draw_rect(Rect2(body_cast_c - Vector2(rx_s, ry_s * 0.5), Vector2(rx_s * 2.0, ry_s)), Color(SHADOW_INK, sun_a))
			_shadow_layer.draw_rect(Rect2(body_cast_c - Vector2(rx_s * 0.7, ry_s * 0.8), Vector2(rx_s * 1.4, ry_s * 1.6)), Color(SHADOW_INK, sun_a * 0.88))
			for leg: Leg in _legs:
				var pts: PackedVector2Array = leg.points
				var n_p: int = pts.size()
				if n_p < 4:
					continue
				for idx_s: int in range(0, n_p, 2):
					var world_pt: Vector2 = pts[idx_s]
					var arch_h: float = sin(float(idx_s) / float(n_p - 1) * PI) * 9.0 + leg.height
					var sh_pt: Vector2 = (inv * (leg.foot.lerp(global_position, 1.0 - float(idx_s) / float(n_p - 1)) + cast_vec * arch_h)).round()
					_shadow_layer.draw_rect(Rect2(sh_pt, Vector2(2.0, 2.0 if idx_s < n_p / 2 else 1.0)), Color(SHADOW_INK, sun_a * 0.82))

	# 2. Cool-violet Belly Contact Shadow Ellipse directly beneath sternum/abdomen
	var belly_c: Vector2 = (inv * (global_position + Vector2(0.0, 1.0))).round()
	var brx: float = roundf(8.5 * _body_scale_mult * lerpf(0.55, 1.0, air_k))
	var bry: float = roundf(4.0 * _body_scale_mult * lerpf(0.55, 1.0, air_k))
	_shadow_layer.draw_rect(Rect2(belly_c - Vector2(brx, bry * 0.5), Vector2(brx * 2.0, bry)), Color(SHADOW_INK, base_a * 0.82))
	_shadow_layer.draw_rect(Rect2(belly_c - Vector2(brx * 0.65, bry), Vector2(brx * 1.3, bry * 2.0)), Color(SHADOW_INK, base_a * 0.62))

	# 3. Crisp 8-Point Tarsus Contact AO Dots where each claw pierces moss/grass/stone!
	if air_height < 6.0:
		for leg: Leg in _legs:
			var lift_fade: float = clampf(1.0 - leg.height / 5.5, 0.0, 1.0)
			if lift_fade <= 0.04:
				continue
			var fp: Vector2 = (inv * leg.foot).round()
			_shadow_layer.draw_rect(Rect2(fp + Vector2(-1.0, 0.0), Vector2(2.0, 1.0)), Color(OUTLINE, 0.48 * _alpha * lift_fade))

	# 4. Canopy Silk Anchor Thread (`CANOPY_HANG` / `CANOPY_DROP`)
	if _pose in [Pose.CANOPY_HANG, Pose.CANOPY_DROP] and air_height > 2.0:
		var top_world: Vector2 = global_position + Vector2(0.0, -ceiling_height - 18.0)
		var bot_world: Vector2 = _body.global_position + Vector2(0.0, -4.0)
		var p_top: Vector2 = (inv * top_world).round()
		var p_bot: Vector2 = (inv * bot_world).round()
		var span_y: int = maxi(2, int(absf(p_bot.y - p_top.y)))
		for sy: int in range(0, span_y, 2):
			var py_t: float = lerpf(p_top.y, p_bot.y, float(sy) / float(span_y))
			_shadow_layer.draw_rect(Rect2(Vector2(p_bot.x, roundf(py_t)), Vector2.ONE), Color(RIM if sy % 6 == 0 else SHADE[2], 0.72 * _alpha))


func _draw_mouthparts(canvas: Node2D, inverse: Transform2D, front_layer: bool) -> void:
	var fwd: Vector2 = Vector2.from_angle(_ground_heading)
	var is_southish: bool = fwd.y >= -0.18
	if is_southish != front_layer:
		return
	var right: Vector2 = fwd.orthogonal()
	var head_base: Vector2 = global_position + _body_offset + _squash(fwd * (7.2 * _body_scale_mult))

	# 1. Two nimble Pedipalps (tactile feelers ahead of head)
	var palp_lift: float = 2.8 if _pose == Pose.HESITATE else 0.0
	for sgn: float in [-1.0, 1.0]:
		var tap: float = sin(_time * 7.5 + sgn * 1.4) * (1.1 if _pose == Pose.HESITATE else 0.55)
		var p0: Vector2 = inverse * (head_base + _squash(right * (sgn * 2.1 * _body_scale_mult)))
		var p1: Vector2 = inverse * (head_base + _squash(fwd * (3.8 * _body_scale_mult) + right * (sgn * (3.2 + tap))) + Vector2(0.0, -1.8 - palp_lift))
		var p2: Vector2 = inverse * (head_base + _squash(fwd * (6.2 * _body_scale_mult) + right * (sgn * (2.4 + tap * 0.6))) + Vector2(0.0, 0.5 - palp_lift * 0.6))
		for seg_pt: Vector2 in [p0, p0.lerp(p1, 0.5), p1, p1.lerp(p2, 0.5), p2]:
			var rp: Vector2 = seg_pt.round()
			canvas.draw_rect(Rect2(rp - Vector2.ONE, Vector2(3.0, 3.0)), Color(OUTLINE, _alpha))
		for seg_pt2: Vector2 in [p0, p0.lerp(p1, 0.5), p1, p1.lerp(p2, 0.5), p2]:
			var rp2: Vector2 = seg_pt2.round()
			canvas.draw_rect(Rect2(rp2, Vector2.ONE), _tint(SHADE[2]))

	# 2. Two articulated Chelicerae Fangs (spread & gleam hot magenta on Windup / Strike / Venom Lunge!)
	if _fang_open > 0.08:
		var spread: float = lerpf(1.2, 3.4, _fang_open) * _body_scale_mult
		var reach_f: float = lerpf(2.2, 5.4, _fang_open) * _body_scale_mult
		for sgn_f: float in [-1.0, 1.0]:
			var f_root: Vector2 = inverse * (head_base + _squash(right * (sgn_f * 1.3 * _body_scale_mult)))
			var f_mid: Vector2 = inverse * (head_base + _squash(fwd * (reach_f * 0.55) + right * (sgn_f * spread)) + Vector2(0.0, -0.8))
			var f_tip: Vector2 = inverse * (head_base + _squash(fwd * reach_f + right * (sgn_f * spread * 0.45)) + Vector2(0.0, 0.8))
			for fp: Vector2 in [f_root, f_mid, f_tip]:
				var rfp: Vector2 = fp.round()
				canvas.draw_rect(Rect2(rfp - Vector2.ONE, Vector2(3.0, 3.0)), Color(OUTLINE, _alpha))
			canvas.draw_rect(Rect2(f_root.round(), Vector2.ONE), _tint(SHADE[1]))
			canvas.draw_rect(Rect2(f_mid.round(), Vector2.ONE), _tint(RIM))
			canvas.draw_rect(Rect2(f_tip.round(), Vector2.ONE), Color(EYE, _alpha))


func _draw_layer(canvas: Node2D, front: bool) -> void:
	var inverse: Transform2D = canvas.get_global_transform().affine_inverse()
	var n_pts: int = 0
	var n_rim: int = 0
	var out_opaque: Color = Color(OUTLINE, _alpha)

	var sun_dir: Vector2 = Vector2(-0.62, -0.78)
	if SunShadows.current != null and SunShadows.current.cast.length_squared() > 0.01:
		sun_dir = -SunShadows.current.cast.normalized()

	for leg: Leg in _legs:
		if leg.front != front or leg.points.size() <= 1:
			continue
		var count: int = leg.points.size()
		var inv_count: float = 1.0 / float(count - 1)
		var base_thick: float = leg.thickness * leg.mass * (1.0 - leg.straighten * 0.28)
		var prev_cx: float = INF
		var prev_cy: float = INF
		var prev_d: int = -1
		for i: int in count:
			var u_t: float = float(i) * inv_count
			# 3-zone arachnid profile: robust Femur (0..0.34), sculpted Patella-Tibia (0.34..0.72), razor 1px Tarsus (0.72..1.0)!
			var diameter: int = 1
			if u_t < 0.78:
				var patella_swell: float = 0.55 * exp(-pow((u_t - 0.36) / 0.14, 2.0))
				diameter = maxi(1, roundi(lerpf(base_thick, 1.0, smoothstep(0.22, 0.88, u_t)) + patella_swell))
			var p: Vector2 = inverse * leg.points[i]
			var half_d: float = floorf(float(diameter) * 0.5)
			var cx: float = roundf(p.x) - half_d
			var cy: float = roundf(p.y) - half_d
			if cx == prev_cx and cy == prev_cy and diameter == prev_d:
				continue
			if diameter >= 3 and diameter == prev_d and i > 1 and i < count - 1 and absf(cx - prev_cx) + absf(cy - prev_cy) <= 1.0:
				continue
			prev_cx = cx
			prev_cy = cy
			prev_d = diameter
			# Crisp opaque 1px claw tip (`fade = 1.0`), zero muddy blur!
			canvas.draw_rect(Rect2(cx - 1.0, cy - 1.0, diameter + 2, diameter + 2), out_opaque)

			if n_pts >= _draw_cx.size():
				var cap: int = n_pts + 96
				_draw_cx.resize(cap)
				_draw_cy.resize(cap)
				_draw_d.resize(cap)
				_draw_fade.resize(cap)
				_draw_t.resize(cap)
			_draw_cx[n_pts] = cx
			_draw_cy[n_pts] = cy
			_draw_d[n_pts] = diameter
			_draw_fade[n_pts] = 1.0
			_draw_t[n_pts] = u_t

			# Directional Patella/Femur Rim-Light along the sun/moon edge!
			if diameter >= 2 and u_t > 0.08 and u_t < 0.74:
				if n_rim >= _draw_rim_x.size():
					var rcap: int = n_rim + 64
					_draw_rim_x.resize(rcap)
					_draw_rim_y.resize(rcap)
					_draw_rim_fade.resize(rcap)
				var rx_off: float = (diameter - 1) if sun_dir.x > 0.25 else 0.0
				_draw_rim_x[n_rim] = cx + rx_off
				_draw_rim_y[n_rim] = cy
				_draw_rim_fade[n_rim] = 1.0 if (u_t > 0.26 and u_t < 0.48) else 0.65
				n_rim += 1
			n_pts += 1

	var shade0: Color = _tint(SHADE[0])
	var shade1: Color = _tint(SHADE[1])
	var shade2: Color = _tint(SHADE[2])
	var shade3: Color = _tint(SHADE[3])
	var wet_amt: float = WeatherManager.current.ground_wet if WeatherManager.current != null else 0.0
	var rim_base: Color = RIM.lerp(WET_RIM, clampf(wet_amt * 0.75, 0.0, 0.75))
	var rim_tint: Color = _tint(rim_base)

	for j: int in n_pts:
		var jt: float = _draw_t[j]
		var col: Color = shade0 if jt < 0.26 else (shade3 if (jt >= 0.30 and jt <= 0.44) else (shade1 if jt < 0.68 else shade2))
		var d: int = _draw_d[j]
		canvas.draw_rect(Rect2(_draw_cx[j], _draw_cy[j], d, d), col)

	for r: int in n_rim:
		var rcol: Color = rim_tint
		rcol.a *= _draw_rim_fade[r]
		canvas.draw_rect(Rect2(_draw_rim_x[r], _draw_rim_y[r], 1.0, 1.0), rcol)

	# Chitin Barbs / Mycelium Thorns (active during combat strikes OR permanently on Thorn Elder brood!)
	var show_thorns: bool = _permanent_thorns or (_pose in [Pose.WINDUP, Pose.STRIKE, Pose.THROW, Pose.PULL, Pose.VENOM_WINDUP, Pose.VENOM_LUNGE])
	if show_thorns:
		for leg: Leg in _legs:
			if leg.front != front or (not _permanent_thorns and not leg.grabber) or leg.points.size() <= 3:
				continue
			var lcount: int = leg.points.size()
			for fraction: float in THORNS:
				var idx_t: int = clampi(roundi(fraction * float(lcount - 1)), 1, lcount - 2)
				var tangent: Vector2 = leg.points[idx_t + 1] - leg.points[idx_t - 1]
				var out: Vector2 = Vector2(-tangent.y, tangent.x).normalized()
				if out.dot(leg.points[idx_t] - global_position) < 0.0:
					out = -out
				var base_p: Vector2 = inverse * (leg.points[idx_t] + out * (leg.thickness * 0.5 * (1.0 - fraction * 0.5)))
				canvas.draw_rect(Rect2(roundf(base_p.x), roundf(base_p.y), 1, 1), out_opaque)
				var tip_p: Vector2 = inverse * (leg.points[idx_t] + out * (leg.thickness * 0.5 * (1.0 - fraction * 0.5) + 2.0))
				canvas.draw_rect(Rect2(roundf(tip_p.x), roundf(tip_p.y), 1, 1), Color(RIM, _alpha))

	_draw_mouthparts(canvas, inverse, front)


func _draw_glow() -> void:
	var layer: Node2D = _glow
	var vg_tex: ImageTexture = VoidGlow.atlas_tex()
	var px_rect: Rect2 = VoidGlow.pixel_rect()
	var inverse: Transform2D = layer.get_global_transform().affine_inverse()
	var sector_col: int = _body.frame % BODY_COLS
	var angle: float = float(sector_col) * PI / 4.0
	var fwd: Vector2 = Vector2(cos(angle), sin(angle) / SQUASH).normalized()
	var right: Vector2 = fwd.orthogonal()
	var center: Vector2 = _body.global_position

	var night_k: float = TimeManager.night_amount()
	var halo_env: float = lerpf(0.28, 0.88, night_k)
	var crouch_dim: float = 0.45 if _pose == Pose.CROUCH else 1.0
	var eye_col: Color = EYE.lerp(EYE_HESITATE, _hesitate_blend)
	var eye_strength: float = (0.45 + 0.42 * night_k + 0.36 * _warning) * _alpha * crouch_dim

	# Hide anterior eye halos when head faces away from camera (North view = sector 6)
	if sector_col != 6:
		for eye_i: int in EYE_SPOTS.size():
			# In Death Curl, ocelli flicker out one by one!
			if _pose == Pose.DEAD and (_pose_elapsed / _pose_duration) > (0.22 + float(eye_i) * 0.16):
				continue
			var spot: Vector3 = EYE_SPOTS[eye_i]
			var es: float = eye_strength * clampf(spot.z, 0.35, 0.85)
			VoidGlow.halo_tex(layer, vg_tex, inverse * (center + _squash(fwd * spot.x + right * spot.y) * _body.scale), eye_col, es * halo_env, 0.42)

	var rate: float = (1.45 if health_ratio < 0.5 else 0.9) + _warning * 1.65
	var pulse: float = (0.22 + 0.65 * VoidGlow.beat(_time, 0.0, rate) + 0.30 * _warning) * _alpha * crouch_dim * halo_env
	if _pose == Pose.EXPOSED:
		pulse = (0.62 + 0.30 * sin(_time * 22.0)) * _alpha

	for spot_c: Vector3 in CORE_SPOTS:
		var cs: float = pulse * clampf(spot_c.z * 0.50, 0.22, 0.70)
		VoidGlow.halo_tex(layer, vg_tex, inverse * (center + _squash(fwd * spot_c.x + right * spot_c.y) * _body.scale), VEIN, cs, 0.62 if cs > 0.45 * _alpha else 0.36)

	var striking_pose: bool = _pose in [Pose.WINDUP, Pose.COIL, Pose.STRIKE, Pose.THROW, Pose.PULL, Pose.VENOM_WINDUP, Pose.VENOM_LUNGE]
	var surge_travel: float = clampf(_pose_elapsed / maxf(_pose_duration * 0.85, 0.05), 0.0, 1.0) if striking_pose else -1.0
	var vein_env: float = lerpf(0.42, 0.92, maxf(night_k, _warning))

	for leg: Leg in _legs:
		var pts: PackedVector2Array = leg.points
		var lcount: int = pts.size()
		if lcount < 3:
			continue
		var inv_lcount: float = 1.0 / float(lcount - 1)
		var previous: Vector2 = Vector2.INF
		var is_active_strike_limb: bool = leg.grabber and striking_pose
		for i: int in range(2, lcount - 2):
			var u_t: float = float(i) * inv_lcount
			if u_t < 0.14 or u_t > 0.80:
				continue
			if not is_active_strike_limb and (i & 1) == 1:
				continue
			var point: Vector2 = (inverse * pts[i]).round()
			if point == previous:
				continue
			previous = point
			var wave: float = VoidGlow.beat(_time, -u_t * 0.32 + leg.phase * 0.02, rate)
			var travel_boost: float = 0.0
			if is_active_strike_limb and surge_travel >= 0.0:
				travel_boost = maxf(0.0, 1.0 - absf(u_t - surge_travel) * 3.8) * 0.60
			var v_alpha: float = _alpha * crouch_dim * vein_env * clampf(0.32 + wave * 0.48 + _warning * 0.22 + travel_boost, 0.0, 1.0)
			var v_col: Color = Color.WHITE.lerp(VEIN_LIGHT, 0.5) if travel_boost > 0.35 else VEIN_LIGHT
			layer.draw_texture_rect_region(vg_tex, Rect2(point, Vector2.ONE), px_rect, Color(v_col, v_alpha))
			if (i & 3) == 0 and (night_k > 0.15 or is_active_strike_limb):
				VoidGlow.halo_tex(layer, vg_tex, point, VEIN, _alpha * crouch_dim * halo_env * (wave * 0.35 + travel_boost * 0.4), 0.38)

		VoidGlow.halo_tex(layer, vg_tex, inverse * pts[lcount >> 1], VEIN, 0.26 * _alpha * crouch_dim * halo_env, 0.40)
		if is_active_strike_limb or night_k > 0.15:
			VoidGlow.halo_tex(layer, vg_tex, inverse * pts[lcount - 1], WARNING if is_active_strike_limb else GLOW, (0.85 if is_active_strike_limb else 0.36 * halo_env) * _alpha, 0.62)
