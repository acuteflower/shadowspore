class_name FisherRig
extends Node2D
## The Lichtfischer's body, drawn as procedural pixel geometry (no rotated raster sprites), docs/enemies/lichtfischer.md.
## Under the water lies a dark, wobbling silhouette; above it hang the stalk and the lantern (a lie: cold teal light in a cage of glassy ribs). For a bite
## the head breaks through the surface: a hinged double jaw with glass needles, a throat that burns violet-magenta, two eyes. All of it is pose-driven so
## every peer draws the same from the replicated state; the host only steers `lure_vec`.
##
## Draw order (children of the rig): Under (silhouette) -> Ring (ripples, reflection) -> Body (head, jaws, spines) -> Front (foam, spray) -> Lure (stalk, cage, bulb)
## -> Glow (additive: eyes, veins, throat, bulb bloom).

signal splashed(world_point: Vector2, power: float)
enum Pose { SURFACE, LURK, NOTICE, STALK, SNAP_WINDUP, SNAP, GAPE, FLASH_WINDUP, FLASH, ORB_CAST, RECOVER, DIVE, HURT, DEAD }

const SQUASH: float = 0.72
const OUTLINE: Color = Color("040208")
const DARK: Color = Color("07040d")
const FLESH: Color = Color("0e0919")
const UPPER: Color = Color("1a1030")
const RIM: Color = Color("5a36b8")
const VEIN: Color = VoidGlow.VEIN
const VEIN_LIGHT: Color = VoidGlow.VEIN_LIGHT
const CORE: Color = Color("ecd2ff")
const EYE: Color = Color("ff4fd8")
const TOOTH: Color = Color("ddd2ff")
const TOOTH_SHADE: Color = Color("8a78c8")
const MOUTH: Color = Color("2a0a33")
const THROAT: Color = Color("c0307f")
const BULB_CORE: Color = Color("eafff8")
const BULB_MID: Color = Color("7ff0d8")
const BULB_EDGE: Color = Color("2fa89a")
const CAGE: Color = Color("cfd8ef")
const CAGE_DARK: Color = Color("4a5a7a")
const DANGER_EDGE: Color = Color("ff4fd8")
const DANGER_CORE: Color = Color("fff0f8")
const WATER_RING: Color = Color("91bbae")
const FOAM: Color = Color("bfe9ff")
const STALK_POINTS: int = 26
const MAX_RINGS: int = 18
const MAX_DROPS: int = 40

var lure_height: float = 24.0 ## px of the lantern above the water when it is at rest (data `lure.height`)
var _pose: Pose = Pose.LURK
var _elapsed: float = 0.0
var _duration: float = 1.0
var _time: float = 0.0
var _heading: float = 0.0
var _alpha: float = 1.0
var _flash: float = 0.0
var _agitation: float = 0.0
var _struck: float = 0.0 ## the lantern was hit: it stutters
var _rise: float = 0.0 ## 0 under water .. 1 head and jaws above it
var _sink: float = 0.0 ## the coil before a lunge
var _gape: float = 0.0 ## 0 closed .. 1 wide open
var _energy: float = 0.8 ## brightness of the lantern
var _scale: float = 1.0
var _open: float = 0.0 ## the ribs of the cage open like a flower
var _danger: float = 0.0 ## 0 friendly teal .. 1 white with a magenta rim: the lie breaks
var _height: float = 24.0
var _retract: float = 0.0 ## the stalk folds into the water
var _ridge: float = 0.0 ## dorsal spines above the surface
var _under: float = 1.0
var _aware: float = 0.0
var _light: float = 1.0 ## 0.4 by day .. 1 at night: the lantern is dimmer under the sun
var _speed: float = 0.0
var _lure_ground: Vector2 = Vector2.ZERO
var _lure_on_water: bool = true
var _bob: Vector2 = Vector2.ZERO
var _head: Vector2 = Vector2.ZERO
var _lure_tip: Vector2 = Vector2.ZERO
var _stalk: PackedVector2Array = PackedVector2Array()
var _rings: Array[Dictionary] = [] ## {p: world, age, life, power}
var _drops: Array[Dictionary] = [] ## {p: world, h, vh, v, age, life}
var _ring_clock: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _under_canvas: Node2D = $Under
@onready var _ring_canvas: Node2D = $Ring
@onready var _body: Node2D = $Body
@onready var _front: Node2D = $Front
@onready var _lure: Node2D = $Lure
@onready var _glow: Node2D = $Glow


func _ready() -> void:
	_rng.seed = hash(get_parent().name)
	_under_canvas.draw.connect(_draw_under)
	_ring_canvas.draw.connect(_draw_rings)
	_body.draw.connect(_draw_body)
	_front.draw.connect(_draw_front)
	_lure.draw.connect(_draw_lure)
	_glow.draw.connect(_draw_glow)
	_pose_values()
	_build_stalk() ## the first draw can come before the first update


func start_pose(pose: Pose, duration: float, elapsed: float = 0.0) -> void:
	_pose = pose
	_duration = maxf(0.01, duration)
	_elapsed = elapsed
	if pose == Pose.SNAP:
		splash(14, 1.3)
		add_ring(_head_ground(), 1.5, 1.0)
	elif pose == Pose.DIVE:
		splash(8, 0.9)
		add_ring(global_position, 1.3, 1.1)
	elif pose == Pose.DEAD:
		splash(10, 1.0)


func hit_flash() -> void:
	_flash = 1.0
	_agitation = 1.0


## The lantern took the blow: the light stutters for a moment.
func lure_struck() -> void:
	_struck = 1.0
	_flash = 1.0
	_agitation = 1.0


## Head centre (rig-local) and the lantern's (rig-local); the creature moves its hurtboxes and its light there.
func head_local() -> Vector2:
	return _head


func lure_local() -> Vector2:
	return _lure_tip


func lure_ground_local() -> Vector2:
	return Vector2(_lure_ground.x, _lure_ground.y * SQUASH) + _bob


func lure_energy() -> float:
	return _energy * _light


func danger() -> float:
	return _danger


func rise() -> float:
	return _rise


func retract() -> float:
	return _retract


func mouth_position() -> Vector2:
	return global_position + _head


func _head_ground() -> Vector2:
	return global_position + _project(8.0 + 16.0 * _rise, 0.0, 0.0)


func _project(forward: float, side: float, height: float = 0.0) -> Vector2:
	return Vector2(cos(_heading) * forward - sin(_heading) * side, (sin(_heading) * forward + cos(_heading) * side) * SQUASH - height)


func splash(count: int, power: float = 1.0) -> void:
	var at: Vector2 = _head_ground()
	for k: int in count:
		if _drops.size() >= MAX_DROPS:
			_drops.remove_at(0)
		var angle: float = _rng.randf() * TAU
		_drops.append({"p": at + Vector2(cos(angle), sin(angle) * 0.5) * _rng.randf_range(1.0, 6.0), "h": _rng.randf_range(1.0, 5.0),
			"vh": _rng.randf_range(40.0, 85.0) * power, "v": Vector2(cos(angle), sin(angle) * 0.5) * _rng.randf_range(8.0, 34.0) * power, "age": 0.0, "life": _rng.randf_range(0.5, 0.9)})
	splashed.emit(at, power)


func add_ring(world_point: Vector2, power: float = 1.0, life: float = 0.9) -> void:
	if _rings.size() >= MAX_RINGS:
		_rings.remove_at(0)
	_rings.append({"p": world_point, "age": 0.0, "life": life, "power": power})


## Called every frame by the creature: `velocity` for the wake, `heading` the facing, `lure_vec` the ground vector from the body to where the lantern wants to hang,
## `light` 0..1 (the night), `aware` 0..1 (how awake the eyes are), `over_water` whether the lantern hangs above the water (it has a reflection then).
func update_rig(delta: float, velocity: Vector2, heading: float, lure_vec: Vector2, light: float, aware: float, over_water: bool) -> void:
	_time += delta
	_elapsed += delta
	_heading = heading
	_light = light
	_aware = move_toward(_aware, aware, delta * 3.0)
	_speed = velocity.length()
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	_agitation = move_toward(_agitation, 0.0, delta * 2.5)
	_struck = move_toward(_struck, 0.0, delta * 1.6)
	_lure_on_water = over_water
	_lure_ground = _lure_ground.lerp(lure_vec, 1.0 - exp(-delta * 6.5))
	_pose_values()
	_bob = Vector2(0.0, sin(_time * 1.4) * 0.6 * (1.0 - _rise))
	_head = _project(8.0 + 16.0 * _rise, 0.0, lerpf(-3.0, 13.0, _rise) - _sink * 3.0) + _bob
	_build_stalk()
	_ring_clock -= delta
	if _speed > 6.0 and _ring_clock <= 0.0 and _under > 0.3:
		_ring_clock = 0.16
		add_ring(global_position + _project(-14.0, 0.0, 0.0), 0.55 + _speed / 70.0, 0.8)
	_tick_particles(delta)
	for canvas: Node2D in [_under_canvas, _ring_canvas, _body, _front, _lure, _glow]:
		canvas.queue_redraw()


func _twitch() -> float:
	var x: float = fposmod(_time * 0.21 + float(hash(get_parent().name) % 97) * 0.013, 1.0)
	return exp(-pow((x - 0.5) * 38.0, 2.0)) + 0.8 * exp(-pow((x - 0.56) * 38.0, 2.0)) ## a double tug now and then: bait that looks alive


func _pose_values() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	_alpha = 1.0
	_rise = 0.0
	_sink = 0.0
	_gape = 0.0
	_scale = 1.0
	_open = 0.0
	_danger = 0.0
	_retract = 0.0
	_ridge = 0.0
	_under = 1.0
	_height = lure_height
	_energy = 0.78 + 0.1 * sin(_time * 1.3) + 0.5 * _twitch() * smoothstep(0.1, 0.5, _aware + 0.3)
	match _pose:
		Pose.SURFACE:
			_retract = 1.0 - smoothstep(0.15, 0.9, t)
			_energy *= smoothstep(0.5, 1.0, t)
			_under = smoothstep(0.0, 0.4, t)
			_ridge = 0.6 * (1.0 - t)
		Pose.NOTICE:
			var pulses: float = 0.0
			for c: float in [0.18, 0.42, 0.66]:
				pulses += exp(-pow((t - c) * 13.0, 2.0))
			_energy = 0.7 + 1.0 * pulses
			_height += 6.0 * pulses
		Pose.STALK:
			_ridge = 1.0
		Pose.SNAP_WINDUP:
			_sink = smoothstep(0.0, 0.8, t)
			_height = lerpf(lure_height, 11.0, smoothstep(0.0, 0.6, t))
			var flicker: float = 0.55 + 0.45 * sin(t * t * 190.0)
			_energy = (0.9 + 0.4 * flicker) * (1.0 - smoothstep(0.72, 0.93, t))
			_danger = smoothstep(0.15, 0.9, t)
		Pose.SNAP:
			_rise = smoothstep(0.0, 0.28, t)
			_gape = (smoothstep(0.0, 0.24, t) if t < 0.5 else lerpf(1.0, 0.08, smoothstep(0.5, 0.64, t)))
			_energy = 0.0
			_danger = 1.0
			_retract = 0.4 * smoothstep(0.0, 0.3, t)
		Pose.GAPE:
			_rise = 1.0 - smoothstep(0.55, 1.0, t)
			_gape = 0.42 + 0.05 * sin(_time * 9.0)
			_energy = smoothstep(0.35, 1.0, t) * 0.5
			_danger = 1.0 - t
			_retract = 0.4 * (1.0 - smoothstep(0.0, 0.6, t))
		Pose.FLASH_WINDUP:
			_energy = lerpf(0.8, 1.7, t) + 0.28 * sin(_time * 48.0 * (0.5 + t))
			_scale = lerpf(1.0, 1.75, smoothstep(0.0, 1.0, t))
			_open = smoothstep(0.1, 0.9, t)
			_height = lerpf(lure_height, 42.0, smoothstep(0.0, 0.8, t))
			_danger = t
		Pose.FLASH:
			_energy = 2.4 * (1.0 - t) + 0.25
			_scale = lerpf(2.0, 1.0, t)
			_open = 1.0 - t
			_height = lerpf(42.0, lure_height, smoothstep(0.3, 1.0, t))
			_danger = 1.0 - t * 0.6
		Pose.ORB_CAST:
			_energy = 1.05 + 0.2 * sin(_time * 7.0)
			_open = 0.85
			_scale = 1.25
			_height = 38.0 + 2.0 * sin(_time * 3.0)
			_danger = 0.35
		Pose.RECOVER:
			_energy = smoothstep(0.3, 1.0, t) * 0.7
			_open = (1.0 - t) * 0.5
		Pose.DIVE:
			_retract = smoothstep(0.0, 0.4, _elapsed)
			_energy *= 1.0 - smoothstep(0.0, 0.3, _elapsed)
			_under = 1.0 - 0.8 * smoothstep(0.2, 0.7, _elapsed)
			_ridge = 0.5
		Pose.HURT:
			_sink = sin(t * PI) * 0.35
			_energy = 0.4 + 0.9 * absf(sin(_time * 55.0)) * _struck
		Pose.DEAD:
			_energy = (0.6 + 0.8 * absf(sin(_time * 40.0))) * (1.0 - smoothstep(0.35, 0.5, t))
			_rise = 0.55 * smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(0.7, 1.0, t))
			_gape = 0.8
			_alpha = 1.0 - smoothstep(0.55, 1.0, t)
			_retract = smoothstep(0.3, 0.7, t)
			_aware = 0.0
	if _pose != Pose.HURT and _struck > 0.0:
		_energy = lerpf(_energy, 0.3 + 1.1 * absf(sin(_time * 55.0)), _struck) ## a struck lantern stutters
	_energy *= _alpha


func _build_stalk() -> void:
	var lg: Vector2 = Vector2(_lure_ground.x, _lure_ground.y * SQUASH) * (1.0 - 0.85 * _retract)
	var h: float = _height * (1.0 - _retract)
	var sway: Vector2 = Vector2(sin(_time * 0.9), cos(_time * 1.2) * 0.6) * 2.2 * (1.0 - _retract) * (1.0 - _open * 0.7)
	var base: Vector2 = _project(10.0, 0.0, 1.0) + _bob
	_lure_tip = base + lg * 0.95 + sway + Vector2(0.0, -h)
	var p1: Vector2 = base + Vector2(lg.x * 0.12, -h * 1.5 - 5.0 * (1.0 - _retract))
	var p2: Vector2 = _lure_tip + Vector2(-lg.x * 0.28, -9.0 * (1.0 - _retract)) + Vector2(0.0, -h * 0.25)
	_stalk.resize(STALK_POINTS)
	for i: int in STALK_POINTS:
		var k: float = float(i) / float(STALK_POINTS - 1)
		var u: float = 1.0 - k
		var point: Vector2 = base * u * u * u + p1 * 3.0 * u * u * k + p2 * 3.0 * u * k * k + _lure_tip * k * k * k
		point += Vector2(sin(_time * 2.3 + float(i) * 0.5), 0.0) * 0.45 * k
		_stalk[i] = point


func _tick_particles(delta: float) -> void:
	for i: int in range(_rings.size() - 1, -1, -1):
		_rings[i]["age"] = float(_rings[i]["age"]) + delta
		if float(_rings[i]["age"]) >= float(_rings[i]["life"]):
			_rings.remove_at(i)
	for i: int in range(_drops.size() - 1, -1, -1):
		var drop: Dictionary = _drops[i]
		drop["age"] = float(drop["age"]) + delta
		drop["vh"] = float(drop["vh"]) - 190.0 * delta
		drop["h"] = float(drop["h"]) + float(drop["vh"]) * delta
		drop["p"] = (drop["p"] as Vector2) + (drop["v"] as Vector2) * delta
		if float(drop["age"]) >= float(drop["life"]) or float(drop["h"]) < -1.0:
			_drops.remove_at(i)


# ----------------------------------------------------------------------------------------------- drawing helpers

func _tint(color: Color, alpha: float = 1.0) -> Color:
	return Color(color.lerp(Color.WHITE, _flash * 0.8), _alpha * alpha)


func _line(canvas: Node2D, from: Vector2, to: Vector2, thickness: float, color: Color) -> void:
	var count: int = maxi(1, ceili(from.distance_to(to) * 1.5))
	var size: Vector2 = Vector2.ONE * thickness
	for i: int in count + 1:
		canvas.draw_rect(Rect2((from.lerp(to, float(i) / count)).round() - Vector2.ONE * floorf(thickness * 0.5), size), color)


func _oval(canvas: Node2D, center: Vector2, radius: Vector2, color: Color) -> void:
	for y: int in range(-ceili(radius.y), ceili(radius.y) + 1):
		var q: float = float(y) / maxf(radius.y, 0.01)
		if absf(q) > 1.0:
			continue
		var w: int = floori(sqrt(1.0 - q * q) * radius.x)
		canvas.draw_rect(Rect2((center + Vector2(-w, y)).round(), Vector2(w * 2 + 1, 1)), color)


## An ellipse lying on the water (`ru` along the facing, `rv` across it), projected into the 3/4 view, filled in rows; `wobble` bends every row sideways like a body seen through water.
func _water_ellipse(canvas: Node2D, center: Vector2, ru: float, rv: float, color: Color, wobble: float = 0.0, phase: float = 0.0) -> void:
	var c: float = cos(_heading)
	var s: float = sin(_heading)
	var a: float = c * c / (ru * ru) + s * s / (rv * rv)
	var span: int = ceili(maxf(ru, rv) * SQUASH)
	for y: int in range(-span, span + 1):
		var gy: float = float(y) / SQUASH
		var b: float = 2.0 * gy * c * s * (1.0 / (ru * ru) - 1.0 / (rv * rv))
		var k: float = gy * gy * (s * s / (ru * ru) + c * c / (rv * rv)) - 1.0
		var disc: float = b * b - 4.0 * a * k
		if disc < 0.0:
			continue
		var root: float = sqrt(disc)
		var shift: int = roundi(sin(float(y) * 0.85 + _time * 2.2 + phase) * wobble)
		var left: int = roundi((-b - root) / (2.0 * a)) + shift
		var right: int = roundi((-b + root) / (2.0 * a)) + shift
		canvas.draw_rect(Rect2((center + Vector2(left, y)).round(), Vector2(right - left + 1, 1)), color)


func _halo(canvas: Node2D, point: Vector2, color: Color, strength: float, bloom: float = 0.5) -> void:
	VoidGlow.halo(canvas, point, color, strength * _alpha, bloom)


# ----------------------------------------------------------------------------------------------- the part under the water

func _draw_under() -> void:
	var a: float = _under * _alpha
	if a <= 0.01:
		return
	var sink_shift: Vector2 = Vector2(0.0, _sink * 1.5)
	_water_ellipse(_under_canvas, _bob + sink_shift, 29.0, 14.5, Color(0.02, 0.012, 0.05, 0.2 * a), 1.0, 0.0)
	_water_ellipse(_under_canvas, _bob + sink_shift, 25.0, 11.5, Color(0.03, 0.02, 0.07, 0.4 * a), 1.0, 0.0)
	_water_ellipse(_under_canvas, _bob + sink_shift + Vector2(0.0, -1.0), 18.0, 7.5, Color(0.11, 0.075, 0.21, 0.3 * a), 1.0, 1.7)
	# the broad tail fan and the two fin blades seen through the water
	for side: float in [-1.0, 1.0]:
		var fin: Vector2 = _project(-6.0, side * 11.0, 0.0) + _bob
		_water_ellipse(_under_canvas, fin, 7.0, 3.0, Color(0.04, 0.025, 0.09, 0.34 * a), 1.0, side)
	_water_ellipse(_under_canvas, _project(-27.0, 0.0, 0.0) + _bob, 6.0, 8.0, Color(0.04, 0.025, 0.09, 0.3 * a), 1.0, 3.0)


func _draw_rings() -> void:
	for ring: Dictionary in _rings:
		var t: float = clampf(float(ring["age"]) / float(ring["life"]), 0.0, 1.0)
		var power: float = float(ring["power"])
		var radius: float = lerpf(3.0, 8.0 + 11.0 * sqrt(power), t)
		var color: Color = Color(WATER_RING, (1.0 - t) * minf(0.7, 0.28 + power * 0.22) * _alpha)
		var center: Vector2 = to_local(ring["p"] as Vector2)
		var steps: int = maxi(18, ceili(radius * 5.0))
		for k: int in steps:
			var angle: float = TAU * float(k) / float(steps)
			if sin(angle * 3.0 + float(power) * 5.0 + t * 2.0) < -0.2:
				continue
			_ring_canvas.draw_rect(Rect2(center + Vector2(roundf(cos(angle) * radius), roundf(sin(angle) * radius * 0.48)), Vector2.ONE), color)
	# a slow, broken ring round the body: the water is disturbed from below even when it lies still
	var steady: float = (0.14 + 0.2 * _rise + 0.12 * _ridge) * _under * _alpha
	var rx: float = 27.0 + sin(_time * 1.1) * 0.8
	var steps: int = 64
	for k: int in steps:
		var angle: float = TAU * float(k) / float(steps)
		if sin(angle * 5.0 + _time * 0.7) < 0.1:
			continue
		var point: Vector2 = _bob + Vector2(roundf(cos(angle) * rx), roundf(sin(angle) * rx * 0.5))
		_ring_canvas.draw_rect(Rect2(point, Vector2.ONE), Color(WATER_RING, steady))
	if _lure_on_water and _energy > 0.05:
		# the reflection of the lantern: a wobbling teal streak below it on the water
		var base: Vector2 = lure_ground_local() + Vector2(0.0, 3.0)
		var warm: Color = BULB_MID.lerp(DANGER_EDGE, _danger * 0.8)
		for i: int in 11:
			var width: int = maxi(1, 4 - i / 3)
			var shift: int = roundi(sin(_time * 3.1 + float(i) * 1.3) * (0.6 + float(i) * 0.18))
			_ring_canvas.draw_rect(Rect2((base + Vector2(shift - width / 2, i)).round(), Vector2(width, 1)), Color(warm, clampf(_energy * _light * 0.34, 0.0, 0.5) * (1.0 - float(i) / 12.0) * _alpha))


# ----------------------------------------------------------------------------------------------- head, jaws, spines

func _jaw_point(joint: Vector3, angle: float, length: float, k: float, hook: float, side: float) -> Vector2:
	var f: float = joint.x + cos(angle) * length * k
	var h: float = joint.z + sin(angle) * length * k + hook * k * k
	return _project(8.0 + 16.0 * _rise + f, side, lerpf(-3.0, 13.0, _rise) - _sink * 3.0 + h) + _bob


func _draw_body() -> void:
	if _under <= 0.05:
		return
	# dorsal spines breaking the surface while it hunts
	if _ridge > 0.05 and _rise < 0.5:
		for i: int in 6:
			var f: float = -18.0 + float(i) * 6.5
			var up: float = (2.0 + 3.0 * sin(float(i) * 1.3 + _time * 2.0) * 0.5 + float(i == 2 or i == 3)) * _ridge
			var root: Vector2 = _project(f, 0.0, 0.0) + _bob
			_line(_body, root, root + Vector2(0.0, -up - 1.0), 3, _tint(OUTLINE, _under))
			_line(_body, root, root + Vector2(0.0, -up), 1, _tint(UPPER, _under))
			_body.draw_rect(Rect2((root + Vector2(0.0, -up)).round(), Vector2.ONE), _tint(RIM, _under))
	if _rise <= 0.04:
		return
	var rise: float = _rise
	# the neck rises out of the water, then the head and jaws
	var neck_base: Vector2 = _project(-2.0, 0.0, -1.0) + _bob
	_line(_body, neck_base, _head + _project(-5.0, 0.0, 0.0), int(7.0 + 6.0 * rise), _tint(OUTLINE))
	_line(_body, neck_base + Vector2(0, -1), _head + _project(-5.0, 0.0, 0.0) + Vector2(0, -1), int(5.0 + 5.0 * rise), _tint(FLESH))
	var theta: float = _gape * 1.2
	var joint: Vector3 = Vector3(-4.0, 0.0, 0.0)
	# the head dome behind the jaws, with a crest
	_oval(_body, _head + _project(-4.0, 0.0, 1.0), Vector2(10.0, 8.5), _tint(OUTLINE))
	_oval(_body, _head + _project(-4.0, 0.0, 2.0), Vector2(8.6, 7.2), _tint(FLESH))
	_oval(_body, _head + _project(-5.0, 0.0, 5.0), Vector2(6.2, 3.8), _tint(UPPER))
	var crest: Vector2 = _head + _project(-6.0, 0.0, 9.0)
	_line(_body, _head + _project(-3.0, 0.0, 5.0), crest, 4, _tint(OUTLINE))
	_line(_body, _head + _project(-3.0, 0.0, 5.0), crest, 2, _tint(UPPER))
	# the far-side jaws first, then the mouth, then the near side
	for pass_index: int in 2:
		var side: float = -2.6 if pass_index == 0 else 2.6
		_draw_jaw_pair(theta, joint, side, pass_index == 1)
	# eyes: sockets on the head (the glow is in the additive pass)
	for side: float in [-1.0, 1.0]:
		var eye: Vector2 = _head + _project(1.0, side * 4.6, 6.0)
		_oval(_body, eye, Vector2(2.0, 1.6), _tint(OUTLINE))


func _draw_jaw_pair(theta: float, joint: Vector3, side: float, near: bool) -> void:
	var up_angle: float = theta * 0.35
	var low_angle: float = -theta * 0.65
	var length: float = 25.0
	if near:
		# the mouth between the jaws: dark plum, a tongue along the lower jaw
		for i: int in 11:
			var k: float = float(i) / 10.0
			var from: Vector2 = _jaw_point(joint, up_angle, length, k, 0.0, 0.0)
			var to: Vector2 = _jaw_point(joint, low_angle, length, k, 3.0, 0.0)
			_line(_body, from, to, 2, _tint(MOUTH.lerp(THROAT, (1.0 - k) * 0.35 * _gape)))
	for jaw: int in 2:
		var upper: bool = jaw == 0
		var angle: float = up_angle if upper else low_angle
		var hook: float = 0.0 if upper else 3.0
		var previous: Vector2 = _jaw_point(joint, angle, length, 0.0, hook, side)
		for i: int in range(1, 11):
			var k: float = float(i) / 10.0
			var point: Vector2 = _jaw_point(joint, angle, length, k, hook, side)
			var thick: float = lerpf(5.0, 2.0, k)
			_line(_body, previous, point, int(thick + 2.0), _tint(OUTLINE))
			_line(_body, previous, point, int(thick), _tint(UPPER if upper else FLESH))
			if i % 3 == 0:
				_body.draw_rect(Rect2(point.round() - Vector2(0, int(thick * 0.5)), Vector2.ONE), _tint(RIM))
			previous = point
		# glass needles: longest in the middle, pointing into the mouth
		for i: int in 9:
			var k: float = 0.12 + float(i) * 0.1
			var base: Vector2 = _jaw_point(joint, angle, length, k, hook, side)
			var inward: float = 1.0 if upper else -1.0
			var tooth_len: float = (3.0 + 3.5 * sin(k * PI)) * (0.55 + 0.45 * smoothstep(0.0, 0.25, _gape + _rise * 0.2))
			var tip: Vector2 = base + Vector2(0.0, tooth_len * inward)
			_line(_body, base, tip, 1, _tint(TOOTH if near else TOOTH_SHADE))
			_body.draw_rect(Rect2(tip.round(), Vector2.ONE), _tint(Color.WHITE if near else TOOTH))


func _draw_front() -> void:
	# foam where the head breaks the surface
	if _rise > 0.04:
		var center: Vector2 = _project(8.0 + 16.0 * _rise, 0.0, 0.0) + _bob
		var rx: float = 11.0 + 8.0 * _rise
		for k: int in 40:
			var angle: float = TAU * float(k) / 40.0
			if sin(angle * 4.0 + _time * 3.0) < -0.1:
				continue
			_front.draw_rect(Rect2(center + Vector2(roundf(cos(angle) * rx), roundf(sin(angle) * rx * 0.5)), Vector2.ONE), Color(FOAM, 0.55 * _rise * _alpha))
	for drop: Dictionary in _drops:
		var at: Vector2 = to_local(drop["p"] as Vector2) - Vector2(0.0, float(drop["h"]))
		var life: float = 1.0 - float(drop["age"]) / float(drop["life"])
		_front.draw_rect(Rect2(at.round(), Vector2.ONE), Color(FOAM, clampf(life * 1.4, 0.0, 1.0)))


# ----------------------------------------------------------------------------------------------- stalk, cage and bulb

func _draw_lure() -> void:
	if _retract > 0.97 or _stalk.is_empty():
		return
	var thin: float = 1.0 - _retract * 0.5
	for pass_index: int in 2:
		for i: int in STALK_POINTS:
			var k: float = float(i) / float(STALK_POINTS - 1)
			var width: int = maxi(1, roundi(lerpf(3.4, 1.0, k) * thin))
			if pass_index == 0:
				_lure.draw_rect(Rect2(_stalk[i].round() - Vector2.ONE * (floorf(width * 0.5) + 1.0), Vector2.ONE * (width + 2)), _tint(OUTLINE))
			else:
				_lure.draw_rect(Rect2(_stalk[i].round() - Vector2.ONE * floorf(width * 0.5), Vector2.ONE * width), _tint(UPPER if k > 0.5 else FLESH))
				if i % 4 == 0:
					_lure.draw_rect(Rect2(_stalk[i].round(), Vector2.ONE), _tint(RIM))
	# the root: a dark knuckle where the rod leaves the head
	_oval(_lure, _stalk[0], Vector2(3.0, 2.0), _tint(OUTLINE))
	_oval(_lure, _stalk[0] + Vector2(0, -1), Vector2(2.0, 1.4), _tint(UPPER))
	var tip: Vector2 = _lure_tip
	var radius: float = 3.4 * _scale
	var spread: float = 1.0 + _open * 4.5
	# the back ribs of the cage, bulb, then the front ribs: glassy, a little too clean for this world
	for front: bool in [false, true]:
		if front:
			_draw_bulb(tip, radius)
		for rib: int in 4:
			var angle: float = float(rib) * TAU / 4.0 + _time * 0.4 + _open * 0.6
			if (sin(angle) >= 0.0) != front:
				continue
			var swing: float = cos(angle) * (radius + 1.0) * spread
			var top: Vector2 = tip + Vector2(0.0, -radius - 2.0)
			var mid: Vector2 = tip + Vector2(swing, 0.0)
			var bottom: Vector2 = tip + Vector2(swing * 0.35, radius + 2.0 + _open * 2.0)
			_line(_lure, top, mid, 1, _tint(OUTLINE))
			_line(_lure, mid, bottom, 1, _tint(OUTLINE))
			_lure.draw_rect(Rect2(top.lerp(mid, 0.55).round(), Vector2.ONE), _tint(CAGE if front else CAGE_DARK))
			_lure.draw_rect(Rect2(mid.lerp(bottom, 0.45).round(), Vector2.ONE), _tint(CAGE if front else CAGE_DARK))
			_lure.draw_rect(Rect2(mid.round(), Vector2.ONE), _tint(Color.WHITE if front else CAGE_DARK))
	# three hair-thin filaments with a spark each: the "flora" that sells the lie
	for i: int in 3:
		var drift: float = (float(i) - 1.0) * 2.6 + sin(_time * 1.7 + float(i) * 2.0) * 1.3
		var tail: Vector2 = tip + Vector2(drift, radius + 3.0 + float(i % 2) * 2.5)
		_line(_lure, tip + Vector2(drift * 0.3, radius + 1.0), tail, 1, _tint(CAGE_DARK, 0.9))


func _bulb_colors() -> Array[Color]:
	var core: Color = BULB_CORE.lerp(DANGER_CORE, _danger)
	var mid: Color = BULB_MID.lerp(DANGER_EDGE, _danger * 0.85)
	var edge: Color = BULB_EDGE.lerp(Color("8a1d6e"), _danger)
	var dim: float = 0.35 + 0.65 * clampf(_energy * _light, 0.0, 1.0) ## an unlit bulb is grey glass
	return [core.lerp(Color("7c8a96"), 1.0 - dim), mid.lerp(Color("4a5560"), 1.0 - dim), edge.lerp(Color("2a3036"), 1.0 - dim)]


func _draw_bulb(tip: Vector2, radius: float) -> void:
	var colors: Array[Color] = _bulb_colors()
	_oval(_lure, tip, Vector2(radius + 1.0, radius + 1.0), _tint(OUTLINE))
	_oval(_lure, tip, Vector2(radius, radius), _tint(colors[2]))
	_oval(_lure, tip + Vector2(-0.5, -0.5), Vector2(radius * 0.72, radius * 0.72), _tint(colors[1]))
	_oval(_lure, tip + Vector2(-1.0, -1.0), Vector2(radius * 0.38, radius * 0.38), _tint(colors[0]))


# ----------------------------------------------------------------------------------------------- everything that shines

func _draw_glow() -> void:
	var live: float = _alpha
	var aware: float = _aware * _under
	var beat_rate: float = 0.8 + (0.6 if _pose in [Pose.SNAP_WINDUP, Pose.FLASH_WINDUP, Pose.ORB_CAST] else 0.0)
	# veins along the back, seen through the water (dim) or above it
	for i: int in 16:
		var k: float = float(i) / 15.0
		var point: Vector2 = _project(lerpf(-24.0, 12.0, k), 0.0, 0.0) + _bob
		var strength: float = (0.16 + 0.34 * aware + 0.3 * _rise + 0.2 * _ridge) * VoidGlow.pulse(_time, -k * 0.35, beat_rate, 0.3) * _under
		_halo(_glow, point, VEIN_LIGHT if i % 4 == 0 else VEIN, strength, 0.4)
	for side: float in [-1.0, 1.0]:
		for i: int in 7:
			var k2: float = float(i) / 6.0
			var fin_point: Vector2 = _project(lerpf(-2.0, -10.0, k2), side * lerpf(3.0, 14.0, k2), 0.0) + _bob
			_halo(_glow, fin_point, VEIN, (0.12 + 0.28 * aware) * VoidGlow.pulse(_time, -k2 * 0.4, beat_rate, 0.3) * _under, 0.4)
	# the stalk is a vein: the heartbeat runs up it into the lantern
	if _retract < 0.9:
		for i: int in range(1, STALK_POINTS - 1):
			var k3: float = float(i) / float(STALK_POINTS - 1)
			var flow: float = 0.25 + 0.75 * VoidGlow.beat(_time, -k3 * 0.32, beat_rate)
			_halo(_glow, _stalk[i], VEIN_LIGHT if i % 5 == 0 else VEIN, 0.5 * flow * (1.0 - _retract) * live, 0.4)
	# the eyes: dim slits at the waterline while it waits, burning when it is awake
	var eye_power: float = clampf(0.25 + aware * 0.9 + _rise * 0.5, 0.0, 1.4) * (1.0 if _pose != Pose.DEAD else 0.0)
	for side2: float in [-1.0, 1.0]:
		var eye: Vector2 = _head + _project(1.0, side2 * 4.6, 6.0)
		if _rise < 0.15:
			eye = _project(14.0, side2 * 4.2, -0.5) + _bob
			if aware > 0.1:
				_halo(_glow, eye, EYE, eye_power * 0.55, 0.9)
		else:
			_halo(_glow, eye, EYE, eye_power, 1.1)
			_halo(_glow, eye + Vector2(0, 1), CORE, 0.6, 0.0)
	# the throat
	if _rise > 0.1 and _gape > 0.1:
		var theta: float = _gape * 1.2
		var joint: Vector3 = Vector3(-4.0, 0.0, 0.0)
		for i: int in 8:
			var k4: float = 0.12 + float(i) * 0.1
			var from: Vector2 = _jaw_point(joint, theta * 0.35, 25.0, k4, 0.0, 0.0)
			var to: Vector2 = _jaw_point(joint, -theta * 0.65, 25.0, k4, 3.0, 0.0)
			_halo(_glow, from.lerp(to, 0.5), EYE.lerp(VEIN_LIGHT, k4), _gape * (1.0 - k4 * 0.6) * _rise * live, 0.55)
	# the lantern
	if _retract < 0.95 and _energy * _light > 0.02:
		var power: float = clampf(_energy * _light, 0.0, 2.6)
		var warm: Color = BULB_MID.lerp(DANGER_EDGE, _danger * 0.85)
		var tip: Vector2 = _lure_tip
		var radius: float = 3.4 * _scale
		_glow.draw_rect(Rect2((tip - Vector2.ONE * (radius * 3.4)).round(), Vector2.ONE * ceilf(radius * 6.8) + Vector2.ONE), Color(warm, 0.045 * power * live))
		_glow.draw_rect(Rect2((tip - Vector2.ONE * (radius * 2.4)).round(), Vector2.ONE * ceilf(radius * 4.8) + Vector2.ONE), Color(warm, 0.08 * power * live))
		_oval(_glow, tip, Vector2(radius * 1.6, radius * 1.6), Color(warm, 0.12 * power * live))
		_halo(_glow, tip, BULB_CORE.lerp(DANGER_CORE, _danger), power, 1.3)
		if _danger > 0.5:
			for k5: int in 10: ## the rim of the lie: magenta teeth round the bulb
				var angle: float = TAU * float(k5) / 10.0 + _time * 2.0
				_glow.draw_rect(Rect2((tip + Vector2(cos(angle), sin(angle)) * (radius + 2.5)).round(), Vector2.ONE), Color(DANGER_EDGE, (_danger - 0.5) * 1.4 * live))
	# the flora lights on the water: fake glow caps that sell the lie, they go out when the bait is thrown away
	if _pose in [Pose.LURK, Pose.NOTICE, Pose.STALK, Pose.SURFACE, Pose.RECOVER]:
		for i: int in 3:
			var angle2: float = _time * 0.18 + float(i) * TAU / 3.0 + float(hash(get_parent().name) % 11)
			var spot: Vector2 = _bob + Vector2(cos(angle2) * (19.0 + 3.0 * float(i)), sin(angle2) * (9.0 + 1.5 * float(i)))
			var blink: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(_time * (1.1 + 0.37 * float(i)) + float(i) * 2.0))
			_halo(_glow, spot, BULB_MID, blink * 0.42 * _light * _under * live, 0.7)
