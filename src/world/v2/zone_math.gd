class_name ZoneMath
extends RefCounted
## Small pure geometry helpers of the 2.0 zone world (worker-safe, no state).


## Distance (tiles) from a point to a closed polygon's outline, measured from inside too (`Atlas.edge_distance` is 0
## inside).
static func rim_distance(point: Vector2, poly: PackedVector2Array) -> float:
	var best: float = INF
	var n: int = poly.size()
	for i: int in n:
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, poly[i], poly[(i + 1) % n])))
	return best


## Distance from a point to an open polyline.
static func polyline_distance(point: Vector2, line: PackedVector2Array) -> float:
	if line.size() == 1:
		return point.distance_to(line[0])
	var best: float = INF
	for i: int in range(line.size() - 1):
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, line[i], line[i + 1])))
	return best


## A copy of `poly` moved by `shift` and scaled (tiles -> px and the like).
static func mapped(poly: PackedVector2Array, scale: float, shift: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(poly.size())
	for i: int in poly.size():
		out[i] = poly[i] * scale + shift
	return out
