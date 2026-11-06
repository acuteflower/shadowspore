class_name ShockRing
extends Node2D
## A ring of force running out over the ground (flattened for the 3/4 view) with a puff of dust: `ShockRing.burst(parent, pos, radius, strength)`.
## Runs on real time so it also shows in slow motion.

var _age: float = 0.0
var _life: float = 0.45
var _radius: float = 60.0
var _strength: float = 1.0


static func burst(parent: Node, at: Vector2, radius: float = 60.0, strength: float = 1.0) -> void:
	var ring: ShockRing = ShockRing.new()
	ring.position = at
	ring._radius = radius
	ring._strength = strength
	ring._life = 0.3 + 0.2 * strength
	parent.add_child(ring)
	var dust: CPUParticles2D = CPUParticles2D.new()
	dust.position = at
	dust.z_index = 3
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.amount = int(8 + 14 * strength)
	dust.lifetime = 0.7
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 4.0
	dust.direction = Vector2(0, -0.3)
	dust.spread = 180.0
	dust.initial_velocity_min = radius * 0.5
	dust.initial_velocity_max = radius * 1.4
	dust.gravity = Vector2.ZERO
	dust.damping_min = 90.0
	dust.damping_max = 130.0
	dust.scale_amount_min = 1.0
	dust.scale_amount_max = 2.5
	dust.color = Color(0.7, 0.66, 0.85, 0.7)
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	dust.color_ramp = fade
	dust.emitting = true
	parent.add_child(dust)
	dust.get_tree().create_timer(1.2, true, false, true).timeout.connect(dust.queue_free)


func _ready() -> void:
	z_index = 3
	material = Unlit.material()


func _process(delta: float) -> void:
	_age += delta / maxf(Engine.time_scale, 0.02)
	if _age >= _life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k: float = _age / _life
	var r: float = _radius * (1.0 - pow(1.0 - k, 3.0))
	var fade: float = 1.0 - k
	for layer: int in 3:
		var rr: float = r * (1.0 - 0.08 * layer)
		var colour: Color = [Color(0.5, 0.35, 0.95, 0.45), Color(0.8, 0.72, 1.0, 0.8), Color(1, 1, 1, 1)][layer]
		colour.a *= fade * minf(_strength + 0.3, 1.0)
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in 33:
			pts.append(Vector2.from_angle(TAU * i / 32.0) * Vector2(rr, rr * 0.55))
		draw_polyline(pts, colour, maxf(1.0, (3.0 - layer) * fade * _strength))
