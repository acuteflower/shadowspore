class_name WitchBody
extends Node2D
## The picture of Morwenna (docs/enemies/boss_mora.md) and of each of her glitch clones: one frame of the sheets from tools/art_morwenna.py
## (assets/enemies/morwenna/morwenna_<look>.png, 96x96 frames, feet (48, 80), 8 rows E SE S SW W NW N NE, clips in data/morwenna_rig.json), a
## glow sprite with only the burning pixels, a flat ground shadow, and the glitch (assets/shaders/glitch_phantom.gdshader): bands of the picture
## slip sideways, the colours split, a struck phantom crumbles into rows of mist.
## The real witch casts a shadow and her fires burn violet; a phantom has NO shadow, scanlines, and its fires flicker witch green (#a8ff6a).
## Purely a picture: the fight (`MirrorWitchFight`) says every frame what to show (`show_pose`).

const ART: String = "res://assets/enemies/morwenna/"
const SHADER: Shader = preload("res://assets/shaders/glitch_phantom.gdshader")
const FRAME: Vector2 = Vector2(96, 96)
const FEET: Vector2 = Vector2(48, 80)
const GREEN: Color = Color("a8ff6a")
const CLIP_NAMES: PackedStringArray = ["idle", "run", "slash_a", "slash_b", "slash_c", "cast", "leap", "leech", "scream", "down"]

static var _rig: Dictionary = {}
static var _glow_shader: Shader

var phantom: bool = false
var look: int = 0
var height: float = 0.0 ## lifted off the ground (the fall out of the tree, a spring)
var alpha: float = 1.0
var dissolve: float = 0.0 ## 0 whole .. 1 crumbled away
var trail: bool = false ## leaves afterimages while it moves fast
var facing: float = PI / 2.0
var clip: String = "idle"
var _sprite: Sprite2D
var _glow: Sprite2D
var _shadow: Node2D
var _mat: ShaderMaterial = ShaderMaterial.new()
var _glow_mat: ShaderMaterial = ShaderMaterial.new()
var _clock: float = 0.0
var _flash: float = 0.0
var _slice_left: float = 0.0
var _slice_next: float = 1.2
var _slice: Vector4 = Vector4.ZERO
var _split: float = 0.0
var _jitter: float = 0.0
var _night: float = 0.0
var _trail_left: float = 0.0
var _last: Vector2 = Vector2.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func rig() -> Dictionary:
	if _rig.is_empty():
		_rig = JSON.parse_string(FileAccess.get_file_as_string("res://data/morwenna_rig.json")) as Dictionary
	return _rig


static func clip_spec(name: String) -> Dictionary:
	return (rig()["clips"] as Dictionary)[name] as Dictionary


static func clip_length(name: String) -> float:
	var spec: Dictionary = clip_spec(name)
	return float(spec["count"]) / float(spec["fps"])


## Seconds into `name` at which its blow lands (the rig's `strike` frame).
static func strike_time(name: String) -> float:
	var spec: Dictionary = clip_spec(name)
	return float(spec.get("strike", 0)) / float(spec["fps"])


func _ready() -> void:
	_rng.randomize()
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = SHADER.code.replace("shader_type canvas_item;", "shader_type canvas_item;\nrender_mode unshaded;")
	_shadow = Node2D.new()
	_shadow.name = "Shadow"
	_shadow.z_index = -8
	_shadow.draw.connect(_draw_shadow)
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.offset = -FEET
	_mat.shader = SHADER
	_sprite.material = _mat
	add_child(_sprite)
	_glow = Sprite2D.new()
	_glow.centered = false
	_glow.region_enabled = true
	_glow.offset = -FEET
	_glow_mat.shader = _glow_shader
	_glow.material = _glow_mat
	_sprite.add_child(_glow)
	add_to_group("night_lights")
	set_look(look)
	show_pose(clip, 0.0, facing)
	_slice_next = _rng.randf_range(0.4, 2.0)
	_last = global_position


## Called by DayNight through the group `night_lights`.
func set_night(amount: float) -> void:
	_night = amount


func set_look(value: int) -> void:
	look = clampi(value, 0, int(rig().get("looks", 3)) - 1)
	if _sprite == null:
		return
	_sprite.texture = load(ART + "morwenna_%d.png" % look) as Texture2D
	_glow.texture = load(ART + "morwenna_%d_glow.png" % look) as Texture2D
	var sheet: Vector2 = _sprite.texture.get_size()
	for mat: ShaderMaterial in [_mat, _glow_mat]:
		mat.set_shader_parameter("sheet_px", sheet)
		mat.set_shader_parameter("frame_px", FRAME)


static func sector_of(angle: float) -> int:
	return posmod(roundi(angle / (PI / 4.0)), 8)


## Shows the frame of `name` at `t` seconds (loops when `loop`), turned to `angle`.
func show_pose(name: String, t: float, angle: float, loop: bool = true) -> void:
	clip = name
	facing = angle
	if _sprite == null:
		return
	var spec: Dictionary = clip_spec(name)
	var count: int = int(spec["count"])
	var index: int = int(floorf(maxf(t, 0.0) * float(spec["fps"])))
	index = posmod(index, count) if loop else clampi(index, 0, count - 1)
	var origin: Vector2 = Vector2(float(int(spec["start"]) + index), float(sector_of(angle))) * FRAME
	var rect: Rect2 = Rect2(origin, FRAME)
	_sprite.region_rect = rect
	_glow.region_rect = rect
	_mat.set_shader_parameter("frame_origin", origin)
	_glow_mat.set_shader_parameter("frame_origin", origin)


## Struck: a white blink.
func hit_flash() -> void:
	_flash = 1.0


## A band of the picture slips aside now (a spasm, a swap, a blow).
func glitch(strength: float = 1.0, seconds: float = 0.14) -> void:
	var y0: float = _rng.randf_range(14.0, 66.0)
	var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
	_slice = Vector4(y0, _rng.randf_range(4.0, 11.0), side * roundf(_rng.randf_range(3.0, 8.0) * strength), -side * roundf(_rng.randf_range(2.0, 6.0) * strength))
	_slice_left = seconds
	_split = maxf(_split, minf(2.0, strength * 1.5))
	_jitter = maxf(_jitter, strength * 0.9)


func _process(delta: float) -> void:
	_clock += delta
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_split = maxf(_split - delta * 9.0, 0.0)
	_jitter = maxf(_jitter - delta * 6.0, 0.0)
	if _slice_left > 0.0:
		_slice_left -= delta
		if _slice_left <= 0.0:
			_slice = Vector4.ZERO
	_slice_next -= delta
	if _slice_next <= 0.0: ## on its own: the phantoms every 1.5-2.2 s, the witch more rarely and less (more with every phase)
		_slice_next = _rng.randf_range(1.5, 2.2) if phantom else _rng.randf_range(3.6, 6.5) / (1.0 + 0.6 * float(look))
		glitch(1.0 if phantom else 0.55, 0.12)
	_sprite.position = Vector2(0.0, -roundf(height))
	var show: float = alpha * (1.0 - smoothstep(0.75, 1.0, dissolve))
	visible = show > 0.01
	if not visible:
		_last = global_position
		return
	var fire: Color = GREEN if phantom else Color.WHITE
	for mat: ShaderMaterial in [_mat, _glow_mat]:
		mat.set_shader_parameter("slice", _slice)
		mat.set_shader_parameter("split", _split + (0.6 if phantom and fmod(_clock, 1.7) < 0.08 else 0.0))
		mat.set_shader_parameter("jitter", _jitter)
		mat.set_shader_parameter("scan", 1.0 if phantom else 0.0)
		mat.set_shader_parameter("dissolve", dissolve)
		mat.set_shader_parameter("clock", _clock)
	_mat.set_shader_parameter("flash", _flash)
	_mat.set_shader_parameter("tint", Color(1, 1, 1, show * (0.9 if phantom else 1.0)))
	var burn: float = (0.55 + 0.45 * _night) * (0.8 + 0.2 * sin(_clock * (11.0 if phantom else 5.0)))
	if phantom and fmod(_clock * 3.1, 1.0) < 0.07: ## the phantom's eyes twitch
		burn *= 0.25
	_glow_mat.set_shader_parameter("tint", Color(fire.r, fire.g, fire.b, show * burn) if phantom else Color(1, 1, 1, show * burn))
	_glow_mat.set_shader_parameter("flash", 0.0)
	_shadow.queue_redraw()
	if trail:
		_trail_left -= delta
		if _trail_left <= 0.0 and global_position.distance_to(_last) > 1.6:
			_trail_left = 0.045
			_leave_image()
	_last = global_position


## An afterimage: the frame as it is, left where she was, fading in a violet (or green) wash.
func _leave_image() -> void:
	var image: Sprite2D = Sprite2D.new()
	image.texture = _sprite.texture
	image.centered = false
	image.region_enabled = true
	image.region_rect = _sprite.region_rect
	image.offset = -FEET
	image.material = Unlit.material()
	image.modulate = Color(0.45, 1.0, 0.3, 0.42) if phantom else Color(0.78, 0.36, 1.0, 0.46)
	image.global_position = global_position + Vector2(0.0, -roundf(height))
	image.z_index = -1
	get_parent().add_child(image)
	var tween: Tween = image.create_tween()
	tween.tween_property(image, "modulate:a", 0.0, 0.3)
	tween.tween_callback(image.queue_free)


func _draw_shadow() -> void:
	if phantom or dissolve > 0.4: ## a phantom casts none: one of the ways to tell
		return
	var k: float = clampf(height / 150.0, 0.0, 1.0)
	var rx: float = lerpf(13.0, 7.0, k)
	var ry: float = lerpf(5.0, 3.0, k)
	var shade: float = lerpf(0.36, 0.14, k) * alpha
	for y: int in range(-ceili(ry), ceili(ry) + 1):
		var q: float = float(y) / ry
		if absf(q) > 1.0:
			continue
		var w: float = floorf(sqrt(1.0 - q * q) * rx)
		_shadow.draw_rect(Rect2(-w, float(y), w * 2.0 + 1.0, 1.0), Color(0.0, 0.0, 0.0, shade))
