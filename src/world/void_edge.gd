class_name VoidEdge
extends ColorRect
## The world's edge, drawn by assets/shaders/void_edge.gdshader: one quad that always covers the
## view and paints the Void that has eaten the land. The coast comes from the baked distance
## texture (assets/world/land_sdf.png). Purely visual (the collision comes from the chunks).

const SHADER: Shader = preload("res://assets/shaders/void_edge.gdshader")
const TILE: float = 16.0
const RIM_MAX: float = 10.0

var _material: ShaderMaterial = ShaderMaterial.new()
var _clock: float = 0.0 ## animation time; runs slow by day and faster at night, so phases never jump
var _sdf_data: PackedByteArray = PackedByteArray()
var _sdf_w: int = 0
var _sdf_h: int = 0


func setup(sdf: Texture2D) -> void:
	_material.shader = SHADER
	_material.set_shader_parameter("sdf", sdf)
	_material.set_shader_parameter("world_tiles", float(RegionMap.WORLD_TILES))
	material = _material
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -8 ## above the ground and the glow layer, below everything that stands on it
	if sdf != null:
		var img: Image = sdf.get_image()
		if img != null:
			img.convert(Image.FORMAT_L8)
			_sdf_data = img.get_data()
			_sdf_w = img.get_width()
			_sdf_h = img.get_height()


func _sample_sdf_cpu(world_px: Vector2) -> float:
	if _sdf_data.is_empty():
		return 0.0
	var world_size: float = TILE * float(RegionMap.WORLD_TILES)
	var u: float = world_px.x / world_size
	var v: float = world_px.y / world_size
	if u < 0.0 or v < 0.0 or u >= 1.0 or v >= 1.0:
		return -16.0
	var x: int = clampi(int(u * float(_sdf_w)), 0, _sdf_w - 1)
	var y: int = clampi(int(v * float(_sdf_h)), 0, _sdf_h - 1)
	var raw: int = _sdf_data[y * _sdf_w + x]
	return (float(raw) - 128.0) / 8.0


func _is_void_near(top_left: Vector2, bottom_right: Vector2) -> bool:
	if _sdf_data.is_empty():
		return true
	const STEP: float = 128.0 # px (8 tiles)
	var y: float = top_left.y
	while y <= bottom_right.y:
		var x: float = top_left.x
		while x <= bottom_right.x:
			if _sample_sdf_cpu(Vector2(x, y)) < RIM_MAX + 1.0:
				return true
			x += STEP
		if _sample_sdf_cpu(Vector2(bottom_right.x, y)) < RIM_MAX + 1.0:
			return true
		y += STEP
	var x_bottom: float = top_left.x
	while x_bottom <= bottom_right.x:
		if _sample_sdf_cpu(Vector2(x_bottom, bottom_right.y)) < RIM_MAX + 1.0:
			return true
		x_bottom += STEP
	return false


func _process(delta: float) -> void:
	var night: float = TimeManager.night_amount()
	_clock = fmod(_clock + delta * lerpf(0.6, 1.25, night), 20000.0)
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var top_left: Vector2 = (inverse * Vector2.ZERO).floor() - Vector2.ONE * 2.0
	var bottom_right: Vector2 = (inverse * get_viewport_rect().size).ceil() + Vector2.ONE * 2.0

	if not _is_void_near(top_left, bottom_right):
		visible = false
		return

	visible = true
	position = top_left
	size = bottom_right - top_left
	_material.set_shader_parameter("origin", top_left)
	_material.set_shader_parameter("view_size", size)
	_material.set_shader_parameter("time", _clock)
	_material.set_shader_parameter("night", night)
