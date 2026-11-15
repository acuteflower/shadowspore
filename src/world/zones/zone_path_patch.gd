class_name ZonePathPatch
extends Node2D
## Procedural earthy footpath segment rendered cleanly above ground tiles and registered with Terrain.patches.

var _world_points: PackedVector2Array = PackedVector2Array()
var _half_width: float = 22.0
var _surface: String = "path"
var _registered: bool = false


func setup(points_px: PackedVector2Array, width_px: float, surface_name: String = "path") -> void:
	_world_points = points_px
	_half_width = maxf(width_px * 0.5, 8.0)
	_surface = surface_name


func _ready() -> void:
	z_index = -9
	if not Terrain.patches.has(self):
		Terrain.patches.append(self)
		_registered = true
	queue_redraw()


func _exit_tree() -> void:
	if _registered:
		Terrain.patches.erase(self)
		_registered = false


func surface_at(pos: Vector2) -> String:
	if _world_points.size() < 2:
		return ""
	for i: int in range(_world_points.size() - 1):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(pos, _world_points[i], _world_points[i + 1])
		if pos.distance_to(closest) <= _half_width * 0.85:
			return _surface
	return ""


func _draw() -> void:
	if _world_points.size() < 2:
		return
	var rim_col: Color = Color(0.24, 0.21, 0.16, 0.36)
	var earth_col: Color = Color(0.41, 0.34, 0.26, 0.62)
	var center_col: Color = Color(0.49, 0.42, 0.33, 0.50)
	for i: int in range(_world_points.size() - 1):
		var a: Vector2 = _world_points[i] - global_position
		var b: Vector2 = _world_points[i + 1] - global_position
		draw_line(a, b, rim_col, _half_width * 2.1, true)
		draw_circle(a, _half_width * 1.05, rim_col)
		draw_circle(b, _half_width * 1.05, rim_col)
	for i: int in range(_world_points.size() - 1):
		var a: Vector2 = _world_points[i] - global_position
		var b: Vector2 = _world_points[i + 1] - global_position
		draw_line(a, b, earth_col, _half_width * 1.65, true)
		draw_circle(a, _half_width * 0.82, earth_col)
		draw_circle(b, _half_width * 0.82, earth_col)
	for i: int in range(_world_points.size() - 1):
		var a: Vector2 = _world_points[i] - global_position
		var b: Vector2 = _world_points[i + 1] - global_position
		draw_line(a, b, center_col, _half_width * 0.95, true)
		draw_circle(a, _half_width * 0.47, center_col)
		draw_circle(b, _half_width * 0.47, center_col)
