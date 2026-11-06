class_name VoidEdge
extends ColorRect
## The world's edge, drawn by assets/shaders/void_edge.gdshader: one quad that always covers the
## view and paints the Void that has eaten the land. The coast comes from the baked distance
## texture (assets/world/land_sdf.png). Purely visual (the collision comes from the chunks).

const SHADER: Shader = preload("res://assets/shaders/void_edge.gdshader")

var _material: ShaderMaterial = ShaderMaterial.new()
var _clock: float = 0.0 ## animation time; runs slow by day and faster at night, so phases never jump


func setup(sdf: Texture2D) -> void:
	_material.shader = SHADER
	_material.set_shader_parameter("sdf", sdf)
	_material.set_shader_parameter("world_tiles", float(RegionMap.WORLD_TILES))
	material = _material
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -8 ## above the ground and the glow layer, below everything that stands on it


func _process(delta: float) -> void:
	var night: float = TimeManager.night_amount()
	_clock = fmod(_clock + delta * lerpf(0.6, 1.25, night), 20000.0)
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var top_left: Vector2 = (inverse * Vector2.ZERO).floor() - Vector2.ONE * 2.0
	var bottom_right: Vector2 = (inverse * get_viewport_rect().size).ceil() + Vector2.ONE * 2.0
	position = top_left
	size = bottom_right - top_left
	_material.set_shader_parameter("origin", top_left)
	_material.set_shader_parameter("view_size", size)
	_material.set_shader_parameter("time", _clock)
	_material.set_shader_parameter("night", night)
