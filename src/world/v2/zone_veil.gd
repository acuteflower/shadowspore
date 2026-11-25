class_name ZoneVeil
extends Polygon2D
## A veil of dark mist over a seamless threshold's mouth while its gate is closed (docs/v2_zonenwelt_atlas_konzept.md
## 13.3): the far side is still being built (or the story keeps it shut), so what lies beyond is hidden instead of
## showing the empty dark. A band along the threshold line, reaching `DEPTH` tiles towards the neighbour; the vertex
## colours carry u (red: along the line) and v (green: away from it) to the shader. Fades in and out on its own (`shut`).

const SHADER: Shader = preload("res://assets/shaders/zone_veil.gdshader")
const DEPTH: float = 5.0 ## tiles towards the neighbour
const BACK: float = 0.6 ## tiles onto the own side
const FADE: float = 1.0 ## seconds for a full fade

var shut: bool = true
var amount: float = 1.0


static func build(zone: Atlas.Zone, line: PackedVector2Array) -> ZoneVeil:
	var veil: ZoneVeil = ZoneVeil.new()
	veil.z_as_relative = false
	veil.z_index = 2
	var pts: PackedVector2Array = Atlas.smooth_open(line, 0.75) if line.size() > 2 else line
	if pts.size() < 2:
		return veil
	var mid: Vector2 = Atlas.point_along(pts, 0.5)
	var along: Vector2 = (pts[pts.size() - 1] - pts[0]).normalized()
	var away: Vector2 = along.orthogonal()
	if zone.contains(mid + away * 1.2):
		away = -away
	var poly: PackedVector2Array = PackedVector2Array()
	var uv: PackedColorArray = PackedColorArray()
	var total: float = Atlas.polyline_length(pts)
	var run: float = 0.0
	var near: PackedVector2Array = PackedVector2Array()
	var far: PackedVector2Array = PackedVector2Array()
	var near_uv: PackedColorArray = PackedColorArray()
	var far_uv: PackedColorArray = PackedColorArray()
	for i: int in pts.size():
		if i > 0:
			run += pts[i].distance_to(pts[i - 1])
		var u: float = run / maxf(total, 0.001)
		near.append(Atlas.px_of(pts[i] - away * BACK))
		far.append(Atlas.px_of(pts[i] + away * DEPTH))
		near_uv.append(Color(u, 0.0, 0.0, 1.0))
		far_uv.append(Color(u, 1.0, 0.0, 1.0))
	poly.append_array(near)
	uv.append_array(near_uv)
	far.reverse()
	far_uv.reverse()
	poly.append_array(far)
	uv.append_array(far_uv)
	veil.polygon = poly
	veil.vertex_colors = uv
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("back", BACK / (BACK + DEPTH))
	veil.material = mat
	return veil


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	var goal: float = 1.0 if shut else 0.0
	if is_equal_approx(amount, goal):
		set_process(false)
		visible = amount > 0.0
		return
	amount = move_toward(amount, goal, delta / FADE)
	_apply()


func set_shut(closed: bool, instant: bool = false) -> void:
	shut = closed
	if instant:
		amount = 1.0 if closed else 0.0
	visible = true
	_apply()
	set_process(true)


func _apply() -> void:
	var mat: ShaderMaterial = material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("amount", amount)
	visible = amount > 0.0
