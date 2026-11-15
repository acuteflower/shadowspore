class_name ReliefLayer
extends ColorRect
## Draws the walls, lips, shadows, ramps and stairs of the height levels with
## assets/shaders/relief.gdshader: one quad that always covers the view and reads the baked relief
## texture (see `Relief`). Purely visual, the collision comes from the chunks.

const SHADER: Shader = preload("res://assets/shaders/relief.gdshader")
const TINT_AMOUNT: float = 0.6 ## how much of a biome's colour its ground layer takes on (WorldLevel._make_layer)

static var _glow_shader_cache: Shader

var _material: ShaderMaterial = ShaderMaterial.new()
var _glow: ColorRect ## the veins of crystal and void walls: an additive, unlit copy of the shader that pulses at night
var _glow_material: ShaderMaterial = ShaderMaterial.new()
var _overhang: ColorRect ## foreground copy that occludes actors standing behind/under an elevation
var _overhang_material: ShaderMaterial = ShaderMaterial.new()
var _clock: float = 0.0
var _relief: Relief
var _last_check_tile_rect: Rect2i = Rect2i()
var _has_elevated: bool = false
var _actors: PackedVector4Array = PackedVector4Array()
var _last_night: float = -1.0
var _last_origin: Vector2 = Vector2(INF, INF)
var _last_size: Vector2 = Vector2(-1.0, -1.0)
var _glow_last_origin: Vector2 = Vector2(INF, INF)
var _glow_last_size: Vector2 = Vector2(-1.0, -1.0)


func setup(texture: Texture2D, field: Texture2D, relief: Relief = null) -> void:
	_relief = relief if relief != null else Terrain.relief
	_material.shader = SHADER
	if _glow_shader_cache == null:
		_glow_shader_cache = Shader.new() ## the same source, unshaded and additive (the day tint must not dim a glow)
		_glow_shader_cache.code = SHADER.code.replace("shader_type canvas_item;", "shader_type canvas_item;\nrender_mode unshaded, blend_add;")
	_glow_material.shader = _glow_shader_cache
	_glow_material.set_shader_parameter("glow_pass", true)
	_overhang_material.shader = SHADER
	_overhang_material.set_shader_parameter("overhang_pass", true)
	_actors.resize(8)
	_actors.fill(Vector4.ZERO)
	for m: ShaderMaterial in [_material, _glow_material, _overhang_material]:
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
	_overhang_material.set_shader_parameter("tints", tints)
	material = _material
	_glow = ColorRect.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.material = _glow_material
	add_child(_glow)
	_overhang = ColorRect.new()
	_overhang.name = "ReliefOverhang"
	_overhang.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overhang.material = _overhang_material
	_overhang.top_level = true
	_overhang.z_as_relative = false
	_overhang.z_index = 1
	add_child(_overhang)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -8 ## above the ground and the glow layer, below everything that stands on it


func _process(delta: float) -> void:
	_clock = fmod(_clock + delta, 20000.0)
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var top_left: Vector2 = (inverse * Vector2.ZERO).floor() - Vector2.ONE * 2.0
	var bottom_right: Vector2 = (inverse * get_viewport_rect().size).ceil() + Vector2.ONE * 2.0
	var view_size: Vector2 = bottom_right - top_left
	position = top_left
	if size != view_size:
		size = view_size
	if _last_origin != top_left:
		_last_origin = top_left
		_material.set_shader_parameter("origin", top_left)
	if _last_size != view_size:
		_last_size = view_size
		_material.set_shader_parameter("view_size", view_size)
	_material.set_shader_parameter("time", _clock)
	var night: float = TimeManager.night_amount()
	var night_changed: bool = absf(night - _last_night) > 0.0005
	if night_changed:
		_last_night = night
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
			var styles_mask: int = _relief.check_view_features(current_rect)
			_glow.visible = (styles_mask & 1) != 0
			_has_elevated = (styles_mask & 2) != 0
	if _glow.visible:
		_glow.position = Vector2.ZERO
		if _glow.size != view_size:
			_glow.size = view_size
		if _glow_last_origin != top_left:
			_glow_last_origin = top_left
			_glow_material.set_shader_parameter("origin", top_left)
		if _glow_last_size != view_size:
			_glow_last_size = view_size
			_glow_material.set_shader_parameter("view_size", view_size)
		_glow_material.set_shader_parameter("time", _clock)
		if night_changed:
			_glow_material.set_shader_parameter("night", night)
	if _overhang != null:
		var count: int = 0
		var box_valid: bool = false
		var box: Rect2 = Rect2()
		if _has_elevated and _relief != null:
			for character: Player in Player.all:
				if not is_instance_valid(character):
					continue
				var pos: Vector2 = character.global_position
				var lvl: float = _relief.level_at(pos)
				var base_lvl: int = int(floorf(lvl))
				var ptx: int = floori(pos.x / Relief.TILE)
				var pty: int = floori(pos.y / Relief.TILE)
				var has_higher: bool = false
				for ty: int in range(pty - 3, pty + 2):
					for tx: int in range(ptx - 2, ptx + 3):
						if _relief.level(tx, ty) > base_lvl:
							has_higher = true
							break
					if has_higher:
						break
				if not has_higher:
					continue
				_actors[count] = Vector4(pos.x, pos.y, lvl, 1.0)
				count += 1
				var actor_box: Rect2 = Rect2(pos.x - 16.0, pos.y - 40.0, 32.0, 48.0)
				box = actor_box if not box_valid else box.merge(actor_box)
				box_valid = true
				if count >= 8:
					break
		_overhang.visible = count > 0
		if _overhang.visible:
			var snapped_pos: Vector2 = box.position.floor()
			var snapped_end: Vector2 = box.end.ceil()
			var snapped_size: Vector2 = snapped_end - snapped_pos
			_overhang.position = snapped_pos
			_overhang.size = snapped_size
			_overhang_material.set_shader_parameter("origin", snapped_pos)
			_overhang_material.set_shader_parameter("view_size", snapped_size)
			_overhang_material.set_shader_parameter("time", _clock)
			_overhang_material.set_shader_parameter("night", night)
			_overhang_material.set_shader_parameter("occlude_actors", _actors)
			_overhang_material.set_shader_parameter("occlude_count", count)
