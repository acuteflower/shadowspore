class_name WaterRipples
extends Node2D
## Expanding pixel rings on the water, anchored where they were made (not following the player).

const LIFETIME: float = 0.7
const MAX_RADIUS: float = 9.0
const COLOR: Color = Color("91bbae")

var _positions: PackedVector2Array = []
var _ages: PackedFloat32Array = []
var _strengths: PackedFloat32Array = []


func add(world_pos: Vector2, strength: float = 0.45) -> void:
	if _positions.size() >= int(DataRegistry.table("river_life")["ripple_cap"]):
		_positions.remove_at(0)
		_ages.remove_at(0)
		_strengths.remove_at(0)
	_strengths.append(clampf(strength, 0.25, 1.8))
	_positions.append(world_pos)
	_ages.append(0.0)


func _process(delta: float) -> void:
	if _ages.is_empty():
		return
	for i: int in range(_ages.size() - 1, -1, -1):
		_ages[i] += delta
		if _ages[i] >= LIFETIME:
			_ages.remove_at(i)
			_strengths.remove_at(i)
			_positions.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for i: int in _ages.size():
		var t: float = clampf(_ages[i] / LIFETIME, 0.0, 1.0)
		var strength: float = clampf(_strengths[i], 0.25, 1.8)
		var rx: float = lerpf(2.0, MAX_RADIUS * sqrt(strength), t)
		var color: Color = Color(COLOR, (1.0 - t) * minf(0.68, 0.38 + strength * 0.2))
		var center: Vector2 = to_local(_positions[i]).round()
		var steps: int = maxi(16, ceili(rx * 5.0))
		for k: int in steps:
			var a: float = TAU * float(k) / float(steps)
			# Short uneven arc segments, with gaps that open as the ring travels.
			if sin(a * 3.0 + float(i) * 1.7 + t * 1.3) < -0.15:
				continue
			var point: Vector2 = center + Vector2(roundf(cos(a) * rx), roundf(sin(a) * rx * 0.48))
			draw_rect(Rect2(point, Vector2.ONE), color)

func _wet_at(point: Vector2) -> bool:
	for patch: Node in Terrain.patches:
		if patch is WorldRivers:
			return (patch as WorldRivers).field_at(point).x <= 0.0
	return true
