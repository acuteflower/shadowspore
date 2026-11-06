class_name SlashArc
extends Node2D
## A sword cut hanging in the air for a moment: a bright crescent (white core, cold violet rim) that thins out, with a few sparks flying off.
## `SlashArc.cut(parent, centre, direction, radius)` adds one (it frees itself). Runs on real time, so it also shows in slow motion.

const LIFE: float = 0.32
var _age: float = 0.0
var _dir: float = 0.0
var _radius: float = 28.0
var _sparks: Array[Dictionary] = []
var _line: bool = false
var _length: float = 90.0


static func cut(parent: Node, centre: Vector2, direction: Vector2, radius: float = 30.0, tilt: float = 0.0) -> SlashArc:
	var arc: SlashArc = SlashArc.new()
	arc.position = centre
	arc._dir = direction.angle() + tilt
	arc._radius = radius
	parent.add_child(arc)
	return arc


## A straight cut line through a point (the frozen moment before the target falls apart).
static func line(parent: Node, centre: Vector2, direction: Vector2, length: float = 90.0) -> SlashArc:
	var arc: SlashArc = SlashArc.new()
	arc.position = centre
	arc._dir = direction.angle()
	arc._line = true
	arc._length = length
	parent.add_child(arc)
	return arc


func _ready() -> void:
	z_index = 6
	material = Unlit.material()
	for i: int in 9:
		_sparks.append({"a": _dir + randf_range(-1.1, 1.1), "v": randf_range(60.0, 150.0), "l": randf_range(0.5, 1.0)})


func _process(delta: float) -> void:
	_age += delta / maxf(Engine.time_scale, 0.02)
	if _age >= (LIFE * 1.2 if _line else LIFE):
		queue_free()
	queue_redraw()


func _draw() -> void:
	if _line:
		var t: float = _age / (LIFE * 1.2)
		var reach: float = 1.0 - pow(1.0 - clampf(t * 4.0, 0.0, 1.0), 3.0)
		var thin: float = (1.0 - t) * (1.0 - t)
		var d: Vector2 = Vector2.from_angle(_dir) * _length * 0.5 * reach
		draw_line(-d, d, Color(0.55, 0.4, 0.95, 0.5 * (1.0 - t)), 7.0 * thin + 1.0)
		draw_line(-d, d, Color(0.85, 0.78, 1.0, 0.85 * (1.0 - t)), 3.5 * thin + 0.5)
		draw_line(-d, d, Color(1, 1, 1, 1.0 - t), 1.5 * thin + 0.5)
		return
	var k: float = _age / LIFE
	var sweep: float = 1.0 - pow(1.0 - clampf(k * 3.0, 0.0, 1.0), 2.0) ## the cut is drawn quickly, then it thins out
	var fade: float = 1.0 - k
	var span: float = 2.1
	for layer: int in 3:
		var thick: float = (7.0 - layer * 2.2) * fade
		var colour: Color = [Color(0.55, 0.4, 0.95, 0.5 * fade), Color(0.8, 0.72, 1.0, 0.8 * fade), Color(1, 1, 1, fade)][layer]
		var pts: PackedVector2Array = PackedVector2Array()
		var steps: int = 14
		for i: int in steps + 1:
			var u: float = float(i) / steps
			var a: float = _dir - span * 0.5 + span * u * sweep
			var width: float = thick * sin(PI * u) ## a crescent: thick in the middle, points at the ends
			pts.append(Vector2.from_angle(a) * (_radius + width * 0.5))
		for i: int in range(steps, -1, -1):
			var u: float = float(i) / steps
			var a: float = _dir - span * 0.5 + span * u * sweep
			var width: float = thick * sin(PI * u)
			pts.append(Vector2.from_angle(a) * (_radius - width * 0.5))
		if pts.size() >= 3:
			draw_colored_polygon(pts, colour)
	for s: Dictionary in _sparks:
		var d: float = float(s.v) * _age
		var from: Vector2 = Vector2.from_angle(float(s.a)) * (_radius * 0.6 + d * 0.5)
		var to: Vector2 = Vector2.from_angle(float(s.a)) * (_radius * 0.6 + d * 0.5 + 6.0 * float(s.l))
		draw_line(from, to, Color(1, 0.95, 1, fade), 1.0)
