class_name ReliefLayer
extends ColorRect
## Draws the walls, lips, shadows, ramps and stairs of the height levels with
## assets/shaders/relief.gdshader: one quad that always covers the view and reads the baked relief
## texture (see `Relief`). Purely visual, the collision comes from the chunks.

const SHADER: Shader = preload("res://assets/shaders/relief.gdshader")
const TINT_AMOUNT: float = 0.6 ## how much of a biome's colour its ground layer takes on (WorldLevel._make_layer)

var _material: ShaderMaterial = ShaderMaterial.new()
var _glow: ColorRect ## the veins of crystal and void walls: an additive, unlit copy of the shader that pulses at night
var _glow_material: ShaderMaterial = ShaderMaterial.new()
var _clock: float = 0.0
var _relief: Relief
var _last_check_tile_rect: Rect2i = Rect2i()


func setup(texture: Texture2D, field: Texture2D, relief: Relief = null) -> void:
	_relief = relief if relief != null else Terrain.relief
	_material.shader = SHADER
	var glow_shader: Shader = Shader.new() ## the same source, unshaded and additive (the day tint must not dim a glow)
	glow_shader.code = SHADER.code.replace("shader_type canvas_item;", "shader_type canvas_item;\nrender_mode unshaded, blend_add;")
	_glow_material.shader = glow_shader
	_glow_material.set_shader_parameter("glow_pass", true)
	for m: ShaderMaterial in [_material, _glow_material]:
		m.set_shader_parameter("relief", texture)
		m.set_shader_parameter("field", field)
		m.set_shader_parameter("wobble", Relief.WOBBLE)
		m.set_shader_parameter("world_tiles", float(RegionMap.WORLD_TILES))
	var tints: PackedVector3Array = PackedVector3Array()
	var biomes: Dictionary = DataRegistry.table("biomes")
	for id: String in biomes: ## the baker numbered the biomes in this order
		var active: String = RegionMap.active_biome(id)
		var tint: Color = Color.WHITE if active == "meadow" else Color.WHITE.lerp(Color((biomes[active] as Dictionary).color as String), TINT_AMOUNT)
		tints.append(Vector3(tint.r, tint.g, tint.b))
	_material.set_shader_parameter("tints", tints)
	_glow_material.set_shader_parameter("tints", tints)
	material = _material
	_glow = ColorRect.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.material = _glow_material
	add_child(_glow)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -8 ## above the ground and the glow layer, below everything that stands on it


func _process(delta: float) -> void:
	_clock = fmod(_clock + delta, 20000.0)
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var top_left: Vector2 = (inverse * Vector2.ZERO).floor() - Vector2.ONE * 2.0
	var bottom_right: Vector2 = (inverse * get_viewport_rect().size).ceil() + Vector2.ONE * 2.0
	position = top_left
	size = bottom_right - top_left
	var night: float = TimeManager.night_amount()
	_material.set_shader_parameter("origin", top_left)
	_material.set_shader_parameter("view_size", size)
	_material.set_shader_parameter("time", _clock)
	_material.set_shader_parameter("night", night)
	if _relief == null:
		_relief = Terrain.relief
	if _relief != null:
		var x0: int = floori(top_left.x / Relief.TILE) - 2
		var y0: int = floori(top_left.y / Relief.TILE) - 3
		var x1: int = ceili(bottom_right.x / Relief.TILE) + 2
		var y1: int = ceili(bottom_right.y / Relief.TILE) + 2
		var current_rect: Rect2i = Rect2i(x0, y0, x1 - x0, y1 - y0)
		if current_rect != _last_check_tile_rect:
			_last_check_tile_rect = current_rect
			_glow.visible = _relief.has_glow_style(current_rect)
	if _glow.visible:
		_glow.position = Vector2.ZERO
		_glow.size = size
		_glow_material.set_shader_parameter("origin", top_left)
		_glow_material.set_shader_parameter("view_size", size)
		_glow_material.set_shader_parameter("time", _clock)
		_glow_material.set_shader_parameter("night", night)
