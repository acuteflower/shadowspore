class_name SpiderRig
extends Node2D
## A void mass borrowing a six-limbed shape. Feet anchor in world space; soft limbs retract,
## reform and take tension rather than hinging at fixed knees.
## It knows nothing about AI: the spider says where it moves, which way it faces and which pose to play.
## Children: Back (legs behind the body), Body (sprite sheet, 8 facings), Front (legs in front),
## Glow (additive halos on eyes, cores, knees and claws).

signal foot_landed(world_pos: Vector2) ## a leg finished a step

enum Pose { LOCOMOTION, WINDUP, STRIKE, RECOVER, DEAD, THROW, PULL, OBSERVE, COIL, CLIMB_REACH, CLIMB }

class Leg:
	extends RefCounted
	var angle: float = 0.0 ## rest direction, radians from the heading (+ = right side)
	var radius: float = 16.0 ## rest distance of the foot from the body
	var root: Vector2 = Vector2.ZERO ## mount on the body: (forward, sideways)
	var thickness: float = 3.0
	var grabber: bool = false ## front legs: the ones that strike
	var side: float = 1.0
	var phase: float = 0.0
	var foot: Vector2 = Vector2.ZERO ## ground position (world)
	var height: float = 0.0 ## how far the foot is lifted
	var stepping: bool = false
	var step_t: float = 0.0
	var step_from: Vector2 = Vector2.ZERO
	var step_to: Vector2 = Vector2.ZERO
	var pose_from: Vector2 = Vector2.ZERO
	var pose_height: float = 0.0
	var mass: float = 1.0
	var dead_from: Vector2 = Vector2.ZERO
	var front: bool = false ## drawn over the body
	var straighten: float = 0.0 ## 0 = normal arched leg, 1 = stretched out long and taut (the grapple)
	var points: PackedVector2Array = [] ## curve samples (world)
	var step_time: float = 0.11 ## each step gets its own random time, lift and trigger distance
	var lift: float = 6.0
	var trigger: float = 6.5
	var cooldown: float = 0.0
	var idle_timer: float = 1.0 ## next restless shift while standing
	var twitch: float = 0.0 ## 1 right after a spasm, fades
	var group: int = 0 ## tetrapod group: legs of one group swing together while the other carries the body
	var swung: bool = false ## already stepped in this swing turn

## Slightly uneven on purpose: this is a creature, not a machine.
const LEG_DEFS: Array = [
	{"angle": 32.0, "radius": 18.0, "root": Vector2(4.5, 2.5), "thick": 4.6, "grabber": true, "side": 1.0},
	{"angle": -38.0, "radius": 17.0, "root": Vector2(4.5, -2.5), "thick": 4.6, "grabber": true, "side": -1.0},
	{"angle": 84.0, "radius": 21.0, "root": Vector2(0.0, 4.0), "thick": 4.2, "grabber": false, "side": 1.0},
	{"angle": -90.0, "radius": 20.0, "root": Vector2(0.0, -4.0), "thick": 4.2, "grabber": false, "side": -1.0},
	{"angle": 148.0, "radius": 19.0, "root": Vector2(-5.0, 3.0), "thick": 3.8, "grabber": false, "side": 1.0},
	{"angle": -140.0, "radius": 20.0, "root": Vector2(-5.0, -3.0), "thick": 3.8, "grabber": false, "side": -1.0},
]
## Glow spots on the body sprite (forward, sideways, radius); matches tools/gen_art.py.
const EYE_SPOTS: Array = [Vector3(5.8, -1.7, 0.9), Vector3(6.1, 1.2, 0.65), Vector3(4.3, -3.1, 0.5), Vector3(4.5, 2.5, 0.5), Vector3(6.9, -0.1, 0.4)]
const CORE_SPOTS: Array = [Vector3(-1.5, 0.3, 1.4), Vector3(-4.6, 2.0, 0.9), Vector3(2.7, -1.6, 0.8)]
const BODY_HEIGHT: float = 9.0
const SQUASH: float = 0.78 ## 3/4 view: ground distances are shortened vertically (matches the body art)
const STEP_TIME: Vector2 = Vector2(0.07, 0.17) ## random range per step
const STEP_LIFT: Vector2 = Vector2(4.0, 9.5)
const STEP_TRIGGER: Vector2 = Vector2(5.0, 9.5) ## a foot steps once it is this far from where it should be
const MAX_STRETCH: float = 26.0
const MAX_STEPPING: int = 2 ## legs in the air at once while standing
const GAIT_MIN_SPEED: float = 6.0 ## above this the legs run the alternating tetrapod gait
const GAIT_GROUPS: Array[int] = [0, 1, 1, 0, 0, 1] ## per LEG_DEFS entry: front-right, mid-left, rear-right swing together
const WOBBLE: float = 1.4
const GRAB_SPREAD: float = 8.0 ## px: how far apart the front claws dig in during the grapple
const OUTLINE: Color = Color("040208")
const SHADE: Array[Color] = [Color("07040d"), Color("0e0919"), Color("1a1030")] ## root, middle, tip
const RIM: Color = Color("6a3fd0")
const VEIN: Color = VoidGlow.VEIN
const GLOW: Color = Color("b06bff")
const VEIN_LIGHT: Color = VoidGlow.VEIN_LIGHT
const EYE: Color = Color("ff4fd8")
const WARNING: Color = Color("ff4fd8")
const THORNS: Array[float] = [0.36, 0.58, 0.77] ## where along a leg the thorns sit

var strike_arc: float = deg_to_rad(100.0)
var strike_hit_fraction: float = 0.58
var attack_side: float = 1.0
var strike_reach: float = 26.0 ## how far the front legs reach when they strike
var damage_flash: float = 0.0 ## set to 1 on a hit; fades by itself
var agitation: float = 0.0 ## set to 1 on a hit: legs and body shudder, fades
var emergence: float = 1.0 ## 0..1: fluid mass -> reaching claws -> raised, planted creature
var emergence_seed: float = 0.0

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
var _warning: float = 0.0 ## 0..1, how strongly eyes and claws glow the attack warning
var _feet_ready: bool = false
var _anchor: Vector2 = Vector2.ZERO ## world ground point the front legs grab
var _noise: FastNoiseLite = FastNoiseLite.new()
var _twitch_timer: float = 1.0
var _yaw: float = 0.0 ## the body drifts a little off its heading
var _sway: Vector2 = Vector2.ZERO
var _emission: Sprite2D
var _body_offset: Vector2 = Vector2(0, -BODY_HEIGHT)
var _climb_start: Vector2
var _climb_end: Vector2
var _climb_grip: Vector2
var _clock: RigClock = RigClock.new()
var _swing_group: int = 0 ## which tetrapod group may step now
var _swing_t: float = 0.0
var _was_moving: bool = false
var _half_cycle: float = 0.3 ## seconds one group swings; shorter the faster it runs

@onready var _back: Node2D = $Back
@onready var _body: Sprite2D = $Body
@onready var _front: Node2D = $Front
@onready var _glow: Node2D = $Glow


func _ready() -> void:
	_emission = ShadowEmission.attach(_body)
	for def_index: int in LEG_DEFS.size():
		var def: Dictionary = LEG_DEFS[def_index]
		var leg: Leg = Leg.new()
		leg.group = GAIT_GROUPS[def_index]
		leg.angle = deg_to_rad(float(def["angle"]))
		leg.radius = float(def["radius"])
		leg.root = def["root"]
		leg.thickness = float(def["thick"])
		leg.grabber = bool(def["grabber"])
		leg.side = float(def["side"])
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


func set_aim(dir: Vector2) -> void:
	if dir != Vector2.ZERO:
		_aim = dir.normalized()


func set_anchor(point: Vector2) -> void:
	_anchor = point


func set_climb(from: Vector2, to: Vector2, upward: bool) -> void:
	_climb_start = from
	_climb_end = to
	var direction: Vector2 = (to - from).normalized()
	# On ascent the forelimbs hook over the upper lip; on descent they retain
	# their grip at the old lip and let the body down under tension.
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


func hit_flash() -> void:
	damage_flash = 1.0
	agitation = 1.0


## Call every frame on every peer.
func update_rig(delta: float, velocity: Vector2, heading: float) -> void:
	delta = _clock.step(self, delta, velocity.length()) ## rebuilt and redrawn ~30 times a second, rarely off screen (RigClock)
	if delta < 0.0:
		return
	_time += delta
	_heading = heading
	_yaw = _noise.get_noise_2d(_time * 0.6, 3.0) * 0.12
	_sway = Vector2(_noise.get_noise_2d(_time * 0.8, 7.0) * 1.1, _noise.get_noise_2d(_time * 1.1, 11.0) * 0.65)
	_ground_heading = Vector2(cos(heading + _yaw), sin(heading + _yaw) / SQUASH).angle()
	_pose_elapsed += delta
	var t: float = clampf(_pose_elapsed / _pose_duration, 0.0, 1.0)
	damage_flash = move_toward(damage_flash, 0.0, 6.0 * delta)
	agitation = move_toward(agitation, 0.0, 2.5 * delta)
	_twitch_timer -= delta
	if _twitch_timer <= 0.0: ## a random leg spasms
		_twitch_timer = randf_range(2.4, 4.5)
		_legs[randi() % _legs.size()].twitch = 1.0
		agitation = maxf(agitation, 0.12)

	var origin: Vector2 = global_position
	if not _feet_ready:
		for leg: Leg in _legs:
			leg.foot = _rest_foot(leg, origin)
			leg.pose_from = leg.foot
		_feet_ready = true
	_gait_phase += velocity.length() * 0.16 * delta
	var run_speed: float = velocity.length()
	if run_speed >= GAIT_MIN_SPEED and _pose == Pose.LOCOMOTION:
		_half_cycle = lerpf(0.24, 0.1, clampf(run_speed / 110.0, 0.0, 1.0)) ## a slow stalk is deliberate, a surge is a skitter
		_swing_t += delta
		if _swing_t >= _half_cycle:
			_swing_t = 0.0
			_swing_group = 1 - _swing_group
			for leg: Leg in _legs:
				leg.swung = false
	else:
		_swing_t = 0.0
		if _was_moving and _pose == Pose.LOCOMOTION: ## a sudden freeze: the legs quiver as the mass settles
			for leg: Leg in _legs:
				leg.twitch = maxf(leg.twitch, randf_range(0.4, 0.9))
			agitation = maxf(agitation, 0.2)
	_was_moving = run_speed >= GAIT_MIN_SPEED
	_update_body(t, velocity)
	for leg: Leg in _legs:
		if emergence < 1.0:
			# Front claws find purchase first, followed by the middle and rear limbs.
			var order: float = 0.27 if leg.grabber else (0.39 if absf(leg.angle) < 2.0 else 0.51)
			var odd: float = sin(leg.angle * 17.0 + emergence_seed)
			order += odd * 0.07
			var reach: float = smoothstep(order, order + 0.30, emergence)
			# Sticky strands catch, recoil and pull free at different times on each limb.
			reach = clampf(reach + sin(reach*TAU*1.5+odd)*sin(reach*PI)*0.10,0.0,1.0)
			var pull: Vector2 = -_aim * (1.0-emergence) * 9.0
			leg.foot = origin + pull + (_rest_foot(leg,origin)-origin) * reach
			leg.height = sin(reach*PI) * 9.0
			leg.mass = lerpf(0.15,1.0,reach)
			leg.stepping = false
		else:
			_update_leg(leg, delta, origin, velocity, t)
		_build_curve(leg, origin)
		leg.front = leg.foot.y >= origin.y - 3.0 or leg.height > 6.0

	_back.queue_redraw()
	_front.queue_redraw()
	_glow.queue_redraw()


func _update_body(t: float, velocity: Vector2) -> void:
	var offset: Vector2 = Vector2(0, -BODY_HEIGHT)
	var scale_goal: Vector2 = Vector2.ONE
	var speed: float = clampf(velocity.length() / 100.0, 0.0, 1.0)
	offset += -velocity * 0.018 + _sway
	offset.y += sin(_time * 2.0) * 0.35
	scale_goal = Vector2(1.0 + speed * 0.09, 1.0 - speed * 0.12)
	if speed > 0.05 and _pose == Pose.LOCOMOTION:
		# The mass rides the gait: it sinks each time the groups swap, flows sideways over the group that carries it
		# and hangs low while skittering, so it glides more than it walks.
		var gp: float = clampf(_swing_t / maxf(_half_cycle, 0.01), 0.0, 1.0)
		var lateral: float = sin((float(_swing_group) + gp) * PI)
		var side: Vector2 = Vector2.from_angle(_heading).orthogonal()
		offset += side * lateral * 1.2 * speed
		offset.y += (0.5 + 0.5 * cos(gp * TAU)) * 0.9 * speed + speed * 1.4
		scale_goal.y -= (0.5 + 0.5 * cos(gp * TAU)) * 0.04 * speed
	var telegraph: float = 0.0
	_warning = 0.0
	match _pose:
		Pose.OBSERVE:
			offset.y -= sin(t * PI) * 1.5
			scale_goal = Vector2(0.95, 1.07)
		Pose.WINDUP:
			var e: float = smoothstep(0.0, 0.8, t)
			offset += -_aim * 3.0 * e + Vector2(0, -2.0 * e)
			scale_goal = Vector2(1.0 + 0.16 * e, 1.0 - 0.12 * e)
			_warning = e
			telegraph = 0.08 * e
		Pose.COIL:
			var e: float = smoothstep(0.0, 0.85, t)
			offset += -_aim * 3.0 * e + Vector2(0, 3.5 * e)
			scale_goal = Vector2(1.0 + 0.25 * e, 1.0 - 0.32 * e)
			_warning = e
			telegraph = 0.08 * e
		Pose.STRIKE:
			offset += _aim * 3.0 * sin(t * PI)
			scale_goal = Vector2(0.92, 1.12)
			_warning = 1.0
			telegraph = 0.12 * sin(t * PI)
		Pose.THROW:
			offset += _aim * 4.0 * t + Vector2(0, 2.0)
			scale_goal = Vector2(0.88, 1.16)
			_warning = 1.0
		Pose.PULL:
			offset += -_aim * 3.0
			scale_goal = Vector2(0.94, 1.08)
			_warning = 0.65
		Pose.CLIMB_REACH:
			var reach: float = smoothstep(0.0, 0.9, t)
			offset += -_aim * 2.0 * reach + Vector2(0, 2.0 * reach)
			scale_goal = Vector2(1.12, 0.86)
			_warning = reach * 0.35
		Pose.CLIMB:
			offset += -_aim * (1.0 + sin(t * PI) * 3.0)
			scale_goal = Vector2(0.9, 1.14)
			_warning = 0.3 + sin(t * PI) * 0.15
		Pose.RECOVER:
			offset.y += 2.0 * (1.0 - t)
			scale_goal = Vector2(1.0 + 0.15 * (1.0 - t), 1.0 - 0.18 * (1.0 - t))
		Pose.DEAD:
			offset.y += 7.0 * smoothstep(0.0, 1.0, t)
			scale_goal = Vector2(1.0 + t * 0.35, 1.0 - t * 0.75)
			_alpha = 1.0 - t * t
	if _pose != Pose.DEAD:
		_alpha = 1.0
	if emergence < 1.0:
		var form: float = smoothstep(0.22,0.93,emergence)
		var heave: float = sin(smoothstep(0.50,1.0,emergence)*PI)
		var struggle: float = sin(emergence*23.0+emergence_seed)*sin(form*PI)
		offset += Vector2(struggle*1.8,absf(struggle)*1.3)
		offset = Vector2(0,2).lerp(offset,form) - _aim*(1.0-form)*9.0
		offset.y -= heave * 4.0
		scale_goal *= Vector2(lerpf(0.30,1.0,form) + sin(form*PI)*0.20, lerpf(0.12,1.0,form))
		_alpha = smoothstep(0.17,0.35,emergence)
	offset += Vector2(sin(_time * 43.0), cos(_time * 31.0)) * agitation * 0.8
	_body_offset = offset
	_body.position = offset.round()
	_body.scale = scale_goal
	_body.frame = posmod(roundi((_heading + _yaw) / (PI / 4.0)), 8)
	_flash = maxf(damage_flash, telegraph)
	_flash_color = Color.WHITE if damage_flash >= telegraph else WARNING
	var material: ShaderMaterial = _body.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("flash", _flash)
		material.set_shader_parameter("flash_color", _flash_color)
	_body.modulate.a = _alpha
	_emission.frame = _body.frame
	var glow_material: ShaderMaterial = _emission.material as ShaderMaterial
	glow_material.set_shader_parameter("pulse", VoidGlow.pulse(_time, 0.0, 0.9 + _warning * 1.6, 0.25))
	glow_material.set_shader_parameter("warning", _warning)


func _squash(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * SQUASH)


func _rest_foot(leg: Leg, origin: Vector2) -> Vector2:
	return origin + _squash(Vector2.from_angle(_ground_heading + leg.angle) * leg.radius)


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
		leg.foot = leg.dead_from.lerp(origin + across * 3.0, smoothstep(0.0, 1.0, t))
		leg.height = sin(t * PI) * 4.0
		leg.mass = 1.0 - t * 0.75
		return
	if _pose == Pose.CLIMB_REACH:
		var e: float = smoothstep(0.0, 0.85, t)
		leg.foot = leg.pose_from.lerp(_climb_grip + across * GRAB_SPREAD, e) if leg.grabber else leg.pose_from
		leg.height = leg.pose_height * (1.0 - e)
		leg.straighten = e * 0.8 if leg.grabber else 0.0
		leg.mass = 1.0 + e * (0.3 if leg.grabber else 0.15)
		leg.stepping = false
		return
	if _pose == Pose.CLIMB:
		if leg.grabber:
			leg.foot = (_climb_grip + across * GRAB_SPREAD).lerp(rest, smoothstep(0.73, 1.0, t))
			leg.height = 0.0
			leg.straighten = 0.9 * (1.0 - smoothstep(0.7, 1.0, t))
			leg.mass = 0.85
		else:
			# Alternating short wall contacts; each one plants while the body pulls
			# past it, then folds and reforms farther up/down the same face.
			var cycle: float = t * 3.0 + (0.5 if leg.side > 0.0 else 0.0) + (0.22 if leg.root.x < 0.0 else 0.0)
			var contact: float = clampf(floorf(cycle) / 3.0 - 0.18, 0.0, 1.0)
			var next_contact: float = minf(1.0, contact + 1.0 / 3.0)
			var k: float = fposmod(cycle, 1.0)
			var wall_foot: Vector2 = _climb_start.lerp(_climb_end, lerpf(contact, next_contact, smoothstep(0.65, 1.0, k))) + across * leg.radius * 0.65 - _aim * 6.0
			leg.foot = leg.pose_from.lerp(wall_foot, smoothstep(0.0, 0.2, t)).lerp(rest, smoothstep(0.84, 1.0, t))
			leg.height = sin(smoothstep(0.65, 1.0, k) * PI) * 2.0
			leg.mass = 1.15 - sin(k * PI) * 0.3
		leg.stepping = false
		return
	if _pose in [Pose.WINDUP, Pose.COIL, Pose.STRIKE, Pose.THROW, Pose.PULL, Pose.RECOVER]:
		if leg.grabber:
			match _pose:
				Pose.WINDUP:
					var e: float = smoothstep(0.0, 0.9, t)
					var folded: Vector2 = origin - _aim * 5.0 + across * (7.0 if active else 12.0)
					leg.foot = leg.pose_from.lerp(folded, e) if active else leg.pose_from
					leg.height = lerpf(leg.pose_height, 13.0 if active else 0.0, e)
					leg.mass = 1.0 + e * (0.65 if active else 0.1)
				Pose.COIL:
					var e: float = smoothstep(0.0, 0.9, t)
					leg.foot = leg.pose_from.lerp(origin - _aim * 6.0 + across * 5.0, e)
					leg.height = lerpf(leg.pose_height, 2.0, e)
					leg.mass = 1.0 + e * 0.4
				Pose.STRIKE:
					if active:
						# Grow to the far edge, then sweep through the exact ground-space fan.
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
					var e: float = pow(t, 2.0)
					leg.foot = leg.pose_from.lerp(_anchor + across * GRAB_SPREAD, e)
					leg.height = leg.pose_height * (1.0 - e)
					leg.straighten = e
					leg.mass = lerpf(1.4, 0.65, e)
				Pose.PULL:
					leg.foot = _anchor + across * GRAB_SPREAD
					leg.height = 0.0
					leg.straighten = 1.0
					leg.mass = 0.75
				Pose.RECOVER:
					var e: float = smoothstep(0.0, 0.85, t)
					var fold: Vector2 = origin + across * 6.0
					leg.foot = leg.pose_from.lerp(fold, smoothstep(0.0, 0.48, t)).lerp(rest, smoothstep(0.48, 1.0, t))
					leg.height = lerpf(leg.pose_height, 0.0, e) + sin(t * PI) * 3.0
					leg.mass = 0.7 + e * 0.3
			leg.stepping = false
			return
		elif _pose != Pose.PULL and _pose != Pose.RECOVER:
			# Supporting feet stay planted; the body can stretch between these anchors.
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
		var fold: Vector2 = origin + (leg.step_from - origin) * 0.42
		leg.foot = leg.step_from.lerp(fold, smoothstep(0.0, 0.42, k)).lerp(leg.step_to, smoothstep(0.38, 1.0, k))
		leg.height = sin(PI * k) * leg.lift * 0.65
		leg.mass = 1.0 - sin(k * PI) * 0.5
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
		# Alternating tetrapod, like a real arachnid: one group of three swings while the other three carry the body,
		# then they swap. The foot lands ahead of where the body will be, so it never drags.
		if stretch > MAX_STRETCH:
			_start_step(leg, rest + velocity * 0.09)
		elif leg.group == _swing_group and not leg.swung and not leg.stepping:
			leg.swung = true
			var speed_k: float = clampf(speed / 110.0, 0.0, 1.0)
			leg.step_time = clampf(_half_cycle * 0.7, 0.06, 0.2) * randf_range(0.92, 1.08)
			leg.lift = lerpf(8.5, 5.5, speed_k) * randf_range(0.85, 1.15) ## a slow stalk lifts high and places each foot, a skitter stays low
			_start_step(leg, rest + velocity * (leg.step_time * 1.6 + 0.02))
		return
	var free: bool = _stepping_count() < MAX_STEPPING
	if stretch > MAX_STRETCH or (leg.cooldown <= 0.0 and free and stretch > leg.trigger):
		_start_step(leg, rest + velocity * 0.09)
	elif leg.idle_timer <= 0.0 and free:
		if leg.grabber: ## the forelimbs keep feeling ahead of it, tip-tapping the ground
			leg.idle_timer = randf_range(0.55, 1.5)
			leg.lift = randf_range(4.0, 6.5)
			leg.step_time = randf_range(0.07, 0.12)
			_start_step(leg, rest + Vector2.from_angle(_ground_heading) * randf_range(2.0, 5.0) + Vector2(randf_range(-2.5, 2.5), randf_range(-1.5, 1.5)))
		else:
			leg.idle_timer = randf_range(1.8, 4.2)
			leg.lift = 3.0
			_start_step(leg, rest + Vector2(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0)))


## Soft cubic limbs, with distributed curvature and fixed endpoints (no knee flips or foot jitter).
func _build_curve(leg: Leg, origin: Vector2) -> void:
	var fwd: Vector2 = Vector2.from_angle(_ground_heading)
	var right: Vector2 = fwd.orthogonal()
	var root: Vector2 = origin + _body_offset + _squash(fwd * leg.root.x + right * leg.root.y) * _body.scale
	var foot: Vector2 = leg.foot + Vector2(0, -leg.height)
	var span: Vector2 = foot - root
	var along: Vector2 = span.normalized() if span.length() > 0.5 else Vector2.DOWN
	var perp: Vector2 = along.orthogonal() * leg.side
	var slack: float = clampf(leg.radius * 0.65 - span.length() * 0.12, 2.0, 13.0) * (1.0 - leg.straighten * 0.95)
	var control_a: Vector2 = root + span * 0.3 + perp * slack + Vector2(0, -slack * 0.65)
	var control_b: Vector2 = root + span * 0.72 - perp * slack * 0.6 + Vector2(0, -slack * 0.4)
	var count: int = clampi(ceili(span.length() * 1.5), 18, 180)
	leg.points.resize(count)
	for i: int in count:
		var t: float = float(i) / (count - 1)
		var u: float = 1.0 - t
		var point: Vector2 = u * u * u * root + 3.0 * u * u * t * control_a + 3.0 * u * t * t * control_b + t * t * t * foot
		var wave: float = _noise.get_noise_2d(_time * 0.8 - t * 2.0, leg.phase * 7.0 + t * 3.0)
		var envelope: float = sin(t * PI)
		leg.points[i] = point + perp * wave * WOBBLE * envelope * (1.0 + agitation + leg.twitch) * (1.0 - leg.straighten * 0.85)


func _tint(color: Color) -> Color:
	return Color(color.lerp(_flash_color, _flash), color.a * _alpha)


func _shade(t: float) -> Color:
	return SHADE[0] if t < 0.3 else (SHADE[1] if t < 0.65 else SHADE[2])


## A tangible dark filament at the tip, rather than smoke.
func _wisp(t: float) -> float:
	return clampf((1.0 - t) * 5.0, 0.55, 1.0)


func _draw_layer(canvas: Node2D, front: bool) -> void:
	var inverse: Transform2D = canvas.get_global_transform().affine_inverse()
	var here: Array[Leg] = []
	for leg: Leg in _legs:
		if leg.front == front and leg.points.size() > 1:
			here.append(leg)
	for pass_index: int in 3: ## outline, fill, rim light
		for leg: Leg in here:
			var count: int = leg.points.size()
			for i: int in count:
				var t: float = float(i) / (count - 1)
				var diameter: int = roundi(lerpf(leg.thickness * leg.mass * (1.0 - leg.straighten * 0.3), 1.0, smoothstep(0.3, 1.0, t))) ## thick thigh, thin shin
				var p: Vector2 = inverse * leg.points[i]
				var corner: Vector2 = Vector2(roundf(p.x) - floorf(diameter * 0.5), roundf(p.y) - floorf(diameter * 0.5))
				var fade: float = _wisp(t)
				match pass_index:
					0:
						canvas.draw_rect(Rect2(corner - Vector2.ONE, Vector2(diameter + 2, diameter + 2)), Color(OUTLINE, _alpha * fade))
					1:
						canvas.draw_rect(Rect2(corner, Vector2(diameter, diameter)), _tint(Color(_shade(t), fade)))
					2:
						if diameter >= 2 and t > 0.05 and t < 0.9:
							canvas.draw_rect(Rect2(corner, Vector2.ONE), _tint(Color(RIM, fade)))
	for leg: Leg in here:
		if not (leg.grabber and _pose in [Pose.WINDUP, Pose.STRIKE, Pose.THROW, Pose.PULL]):
			continue
		var count: int = leg.points.size()
		for fraction: float in THORNS: ## material gathers into transient barbs on an attacking limb
			var i: int = clampi(roundi(fraction * (count - 1)), 1, count - 2)
			var tangent: Vector2 = leg.points[i + 1] - leg.points[i - 1]
			var out: Vector2 = Vector2(-tangent.y, tangent.x).normalized()
			if out.dot(leg.points[i] - global_position) < 0.0:
				out = -out
			var base: Vector2 = inverse * (leg.points[i] + out * (leg.thickness * 0.5 * (1.0 - fraction * 0.5)))
			canvas.draw_rect(Rect2(roundf(base.x), roundf(base.y), 1, 1), Color(OUTLINE, _alpha))
			var tip: Vector2 = inverse * (leg.points[i] + out * (leg.thickness * 0.5 * (1.0 - fraction * 0.5) + 2.0))
			canvas.draw_rect(Rect2(roundf(tip.x), roundf(tip.y), 1, 1), Color(RIM, _alpha))


func _halo(canvas: Node2D, point: Vector2, strength: float, color: Color) -> void:
	VoidGlow.halo(canvas, point, color, strength * _alpha, 1.0 if strength > 0.6 else 0.5)


## Small additive halos plus a flowing one-pixel vein down each limb; body emission is masked.
func _draw_glow() -> void:
	var layer: Node2D = _glow
	var inverse: Transform2D = layer.get_global_transform().affine_inverse()
	var angle: float = _body.frame * PI / 4.0
	var fwd: Vector2 = Vector2(cos(angle), sin(angle) / SQUASH).normalized()
	var right: Vector2 = fwd.orthogonal()
	var center: Vector2 = _body.global_position
	var eye_strength: float = 0.85 + 0.35 * _warning
	for spot: Vector3 in EYE_SPOTS:
		_halo(layer, inverse * (center + _squash(fwd * spot.x + right * spot.y) * _body.scale), eye_strength * clampf(spot.z + 0.3, 0.4, 1.0), EYE)
	var rate: float = 0.9 + _warning * 1.6
	var pulse: float = 0.3 + 0.9 * VoidGlow.beat(_time, 0.0, rate) + 0.2 * _warning
	for spot: Vector3 in CORE_SPOTS:
		_halo(layer, inverse * (center + _squash(fwd * spot.x + right * spot.y) * _body.scale), pulse * clampf(spot.z * 0.6, 0.35, 0.8), VEIN)
	for leg: Leg in _legs:
		if leg.points.size() < 3:
			continue
		var previous: Vector2 = Vector2.INF
		for i: int in range(2, leg.points.size() - 2):
			var t: float = float(i) / (leg.points.size() - 1)
			if t < 0.12 or t > 0.88:
				continue
			var point: Vector2 = (inverse * leg.points[i]).round()
			if point == previous:
				continue
			previous = point
			var wave: float = VoidGlow.beat(_time, -t * 0.3 + leg.phase * 0.02, rate)
			layer.draw_rect(Rect2(point, Vector2.ONE), Color(VEIN_LIGHT, _alpha * (0.45 + wave * 0.55 + _warning * 0.15)))
			if i % 3 == 0:
				VoidGlow.halo(layer, point, VEIN, _alpha * wave * 0.5, 0.45)
		_halo(layer, inverse * leg.points[leg.points.size() >> 1], 0.45, VEIN)
		var striking: bool = leg.grabber and (_pose in [Pose.WINDUP, Pose.COIL, Pose.STRIKE, Pose.THROW, Pose.PULL])
		_halo(layer, inverse * leg.points[leg.points.size() - 1], 1.0 if striking else 0.6, WARNING if striking else GLOW)
