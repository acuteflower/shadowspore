class_name ShockRing
extends Node2D
## A ring of force running out over the ground (flattened for the 3/4 view) with a puff of dust: `ShockRing.burst(parent, pos, radius, strength)`.
## Runs on real time so it also shows in slow motion.
## Optimized: Caches Gradient and unit circle coordinates, and pools ShockRing and CPUParticles2D nodes.

const LAYER_COLORS: Array[Color] = [
	Color(0.5, 0.35, 0.95, 0.45),
	Color(0.8, 0.72, 1.0, 0.8),
	Color(1.0, 1.0, 1.0, 1.0),
]

static var _fade_gradient: Gradient = null
static var _unit_circle: PackedVector2Array = PackedVector2Array()
static var _ring_pool: Array[ShockRing] = []
static var _dust_pool: Array[CPUParticles2D] = []

var _age: float = 0.0
var _life: float = 0.45
var _radius: float = 60.0
var _strength: float = 1.0


static func _get_gradient() -> Gradient:
	if _fade_gradient == null:
		_fade_gradient = Gradient.new()
		_fade_gradient.set_color(0, Color(1, 1, 1, 0.9))
		_fade_gradient.set_color(1, Color(1, 1, 1, 0.0))
	return _fade_gradient


static func _ensure_unit_circle() -> void:
	if not _unit_circle.is_empty():
		return
	_unit_circle.resize(33)
	for i: int in 33:
		var a: float = TAU * float(i) / 32.0
		_unit_circle[i] = Vector2(cos(a), sin(a) * 0.55)


static func burst(parent: Node, at: Vector2, radius: float = 60.0, strength: float = 1.0) -> void:
	# 1. ShockRing instance from pool or newly created
	var ring: ShockRing = null
	while not _ring_pool.is_empty():
		var candidate: ShockRing = _ring_pool.pop_back()
		if is_instance_valid(candidate):
			ring = candidate
			break
	if ring == null:
		ring = ShockRing.new()
		ring.z_index = 3
		ring.material = Unlit.material()

	ring._age = 0.0
	ring._radius = radius
	ring._strength = strength
	ring._life = 0.3 + 0.2 * strength
	ring.position = at
	ring.visible = true
	ring.set_process(true)
	if ring.get_parent() != parent:
		if ring.get_parent() != null:
			ring.get_parent().remove_child(ring)
		parent.add_child(ring)

	# 2. Dust CPUParticles2D from pool or newly created
	var dust: CPUParticles2D = null
	while not _dust_pool.is_empty():
		var candidate: CPUParticles2D = _dust_pool.pop_back()
		if is_instance_valid(candidate):
			dust = candidate
			break
	if dust == null:
		dust = CPUParticles2D.new()
		dust.z_index = 3
		dust.one_shot = true
		dust.explosiveness = 0.95
		dust.lifetime = 0.7
		dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		dust.emission_sphere_radius = 4.0
		dust.direction = Vector2(0, -0.3)
		dust.spread = 180.0
		dust.gravity = Vector2.ZERO
		dust.damping_min = 90.0
		dust.damping_max = 130.0
		dust.scale_amount_min = 1.0
		dust.scale_amount_max = 2.5
		dust.color = Color(0.7, 0.66, 0.85, 0.7)
		dust.color_ramp = _get_gradient()
		dust.finished.connect(_recycle_dust.bind(dust))

	dust.position = at
	dust.amount = int(8 + 14 * strength)
	dust.initial_velocity_min = radius * 0.5
	dust.initial_velocity_max = radius * 1.4
	dust.visible = true
	if dust.get_parent() != parent:
		if dust.get_parent() != null:
			dust.get_parent().remove_child(dust)
		parent.add_child(dust)
	dust.restart()


static func _recycle_ring(ring: ShockRing) -> void:
	ring.set_process(false)
	ring.visible = false
	if ring.get_parent() != null:
		ring.get_parent().remove_child(ring)
	if _ring_pool.size() < 32:
		_ring_pool.append(ring)
	else:
		ring.queue_free()


static func _recycle_dust(dust: CPUParticles2D) -> void:
	if not is_instance_valid(dust):
		return
	dust.emitting = false
	dust.visible = false
	if dust.get_parent() != null:
		dust.get_parent().remove_child(dust)
	if _dust_pool.size() < 32:
		_dust_pool.append(dust)
	else:
		dust.queue_free()


func _ready() -> void:
	z_index = 3
	material = Unlit.material()


func _process(delta: float) -> void:
	_age += delta / maxf(Engine.time_scale, 0.02)
	if _age >= _life:
		_recycle_ring(self)
		return
	queue_redraw()


func _draw() -> void:
	_ensure_unit_circle()
	var k: float = _age / _life
	var r: float = _radius * (1.0 - pow(1.0 - k, 3.0))
	var fade: float = 1.0 - k
	var strength_factor: float = minf(_strength + 0.3, 1.0)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(33)
	for layer: int in 3:
		var rr: float = r * (1.0 - 0.08 * float(layer))
		var colour: Color = LAYER_COLORS[layer]
		colour.a = fade * strength_factor * (0.45 if layer == 0 else (0.8 if layer == 1 else 1.0))
		for i: int in 33:
			pts[i] = _unit_circle[i] * rr
		draw_polyline(pts, colour, maxf(1.0, (3.0 - float(layer)) * fade * _strength))
