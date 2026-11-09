class_name GroundDecal
extends Sprite2D
## A hand-authored patch of ground (old flagstones, the footpath) lying on the meadow, baked by tools/bake_ground.py from
## data/ground.json: a picture and a mask picture of the same size (R: 60 stone, 80 path). It paints its own surface, so
## footsteps and speed follow what you see (`Terrain.patches`). Added by `WorldLevel._add_ground_decals`.

const SURFACES: Dictionary = {60: "stone", 80: "path"} ## mask value -> surface (data/terrain.json)

var _mask: Image
var _glow: Sprite2D
var _time: float = 0.0
var _mask_bytes: PackedByteArray = PackedByteArray()
var _mask_width: int = 0
var _mask_height: int = 0
var decal_id: String = "" ## the baked picture's name without the extension (arena floors: "<arena>_arena")
var _fury: float = 0.0 ## 0..1: the inlaid light has turned into pink-violet fire (Mornath's last phase)
var _fury_goal: float = 0.0
var _fury_speed: float = 1.0
var _fury_material: ShaderMaterial
var _flames: PixelFlames
var _base_material: ShaderMaterial ## the lit picture with its turquoise recoloured
var _teal_glow: Sprite2D ## the same picture again, only its turquoise, burning (additive, unshaded)
var _teal_material: ShaderMaterial


func setup(texture_path: String, mask_path: String, top_left: Vector2, glow_path: String = "") -> void:
	texture = load(texture_path) as Texture2D
	decal_id = texture_path.get_file().get_basename()
	_mask = (load(mask_path) as Texture2D).get_image()
	_mask.convert(Image.FORMAT_R8)
	_mask_bytes = _mask.get_data()
	_mask_width = _mask.get_width()
	_mask_height = _mask.get_height()
	set_process(false)
	centered = false
	position = top_left
	z_index = -9
	Terrain.patches.append(self)
	if glow_path != "" and ResourceLoader.exists(glow_path):
		_glow = Sprite2D.new() ## the inlaid light of the floor (arenas): unlit, dim by day, alive at night
		_glow.texture = load(glow_path) as Texture2D
		_glow.centered = false
		_glow.material = Unlit.material()
		add_child(_glow)
		add_to_group("ground_glow")
		set_process(true)
	tree_exiting.connect(func() -> void: Terrain.patches.erase(self))


## The surface under a world position: "" off the decal or where it has nothing.
func surface_at(world_pos: Vector2) -> String:
	var local: Vector2 = world_pos - position
	var x: int = int(floorf(local.x))
	var y: int = int(floorf(local.y))
	if x < 0 or y < 0 or x >= _mask_width or y >= _mask_height:
		return ""
	var val: int = _mask_bytes[y * _mask_width + x]
	return String(SURFACES.get(val, ""))


func _process(delta: float) -> void:
	if _glow == null:
		return
	_time += delta
	_glow.modulate.a = lerpf(0.35, 1.0, TimeManager.night_amount()) * (0.8 + 0.2 * sin(_time * 0.9))
	if _fury != _fury_goal:
		_fury = move_toward(_fury, _fury_goal, delta * _fury_speed)
		if _fury <= 0.0 and _fury_goal <= 0.0:
			_glow.material = Unlit.material() ## the fire is out: the turquoise light again
			material = null
			if _teal_glow != null:
				_teal_glow.visible = false
			if _flames != null:
				_flames.amount = 0.0
	if _fury > 0.0 and _fury_material != null:
		_fury_material.set_shader_parameter("fury", _fury)
		_fury_material.set_shader_parameter("time", _time)
		_base_material.set_shader_parameter("fury", _fury)
		_teal_material.set_shader_parameter("fury", _fury)
		_teal_material.set_shader_parameter("time", _time)
		_glow.modulate.a = maxf(_glow.modulate.a, 0.85 * _fury) ## burning, the light does not sleep by day
		if _flames != null:
			_flames.amount = _fury


## The inlaid light turns into pink-violet fire over `seconds` (0 = at once) and parts of it burn with flames. `extinguish` puts it out again.
func ignite(seconds: float) -> void:
	if _glow == null:
		return
	if _fury_material == null:
		_fury_material = ShaderMaterial.new()
		_fury_material.shader = load("res://assets/shaders/fury_glow.gdshader") as Shader
	_glow.material = _fury_material
	if _base_material == null:
		_base_material = ShaderMaterial.new()
		_base_material.shader = load("res://assets/shaders/fury_ground.gdshader") as Shader
		_teal_material = ShaderMaterial.new()
		_teal_material.shader = load("res://assets/shaders/fury_teal_glow.gdshader") as Shader
		_teal_glow = Sprite2D.new()
		_teal_glow.name = "TealFire"
		_teal_glow.texture = texture
		_teal_glow.centered = false
		_teal_glow.material = _teal_material
		add_child(_teal_glow)
	material = _base_material
	_teal_glow.visible = true
	if _flames == null:
		_flames = PixelFlames.new()
		_flames.name = "Flames"
		_flames.z_index = 1
		add_child(_flames)
		_flames.build(_flame_spots(), 7.0, 18.0, hash(decal_id))
	_fury_goal = 1.0
	_fury_speed = 1.0 / maxf(seconds, 0.001)
	if seconds <= 0.0:
		_fury = 1.0


func extinguish(seconds: float) -> void:
	_fury_goal = 0.0
	_fury_speed = 1.0 / maxf(seconds, 0.001)
	if seconds <= 0.0:
		_fury = 0.0


func fury() -> float:
	return _fury


## Where flames can stand: pixels of the inlaid light, picked by a hash so they are spread over all of it (about sixty).
func _flame_spots() -> PackedVector2Array:
	var spots: PackedVector2Array = PackedVector2Array()
	var image: Image = _glow.texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	for y: int in range(2, image.get_height(), 3):
		for x: int in range(2, image.get_width(), 3):
			var c: Color = image.get_pixel(x, y)
			if c.a > 0.5 and (c.r + c.g + c.b) / 3.0 > 0.35 and float(hash(Vector2i(x, y)) % 1000) / 1000.0 < 0.2:
				spots.append(Vector2(x, y))
	return spots
