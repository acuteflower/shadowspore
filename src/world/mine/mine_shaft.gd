class_name MineShaft
extends Node2D
## An air shaft: a column of cool daylight falls through the roof onto a pool of light on the floor, dust turning in it. Unshaded and additive, so it stays
## bright whatever the zone's tint. Cosmetic, every peer runs its own.

const BEAM_H: float = 170.0
var _t: float = 0.0
var _dust: CPUParticles2D


func _ready() -> void:
	z_index = 3
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add
	_dust = CPUParticles2D.new()
	_dust.amount = 18
	_dust.lifetime = 6.0
	_dust.preprocess = 6.0
	_dust.local_coords = true
	_dust.position = Vector2(0, -60)
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(12, 60)
	_dust.gravity = Vector2.ZERO
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 4.0
	_dust.direction = Vector2(0.2, 1.0)
	_dust.spread = 90.0
	_dust.scale_amount_min = 1.0
	_dust.scale_amount_max = 1.0
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(0.8, 0.9, 1.0, 0.0))
	ramp.add_point(0.3, Color(0.8, 0.9, 1.0, 0.7))
	ramp.set_color(1, Color(0.8, 0.9, 1.0, 0.0))
	_dust.color_ramp = ramp
	add_child(_dust)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var breath: float = 0.85 + 0.15 * sin(_t * 0.9)
	var top: Vector2 = Vector2(0, -BEAM_H)
	var points: PackedVector2Array = PackedVector2Array([top + Vector2(-14, 0), top + Vector2(14, 0), Vector2(22, -4), Vector2(-22, -4)])
	var colors: PackedColorArray = PackedColorArray([Color(0.6, 0.78, 1.0, 0.0), Color(0.6, 0.78, 1.0, 0.0), Color(0.6, 0.78, 1.0, 0.2 * breath), Color(0.6, 0.78, 1.0, 0.2 * breath)])
	draw_polygon(points, colors)
	for ring: int in 4: ## the pool of light on the floor: stepped rings, pixel art
		var r: float = 44.0 - ring * 9.0
		var a: float = (0.05 + 0.045 * ring) * breath
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in 22:
			var ang: float = float(i) / 22.0 * TAU
			pts.append(Vector2(cos(ang) * r, sin(ang) * r * 0.5 - 2.0).round())
		draw_colored_polygon(pts, Color(0.62, 0.8, 1.0, a))
