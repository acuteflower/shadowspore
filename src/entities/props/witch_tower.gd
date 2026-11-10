class_name WitchTower
extends Node2D
## The witch's tower of the Hexenwald (art and layout: tools/art_witch_tower.py -> assets/props/witch_tower/). Puts the baked pieces together and brings them to life:
## glow that beats, a figure passing the big window at night, the dormer eye looking about, the bubbling cauldron, swaying crown / charms / lanterns, green smoke,
## steam, candle flames and wisps circling the keep. Origin = the foot of the gate. Placed by WorldLevel from data/ground.json "towers" (site and the way to its gate: tools/bake_hexenwald_path.py; preview: tools/preview_witch_tower.tscn).
const DIR: String = "res://assets/props/witch_tower/"
const SWAY: Shader = preload("res://assets/shaders/sway_rows.gdshader")
const GREEN: Color = Color("a8ff6a")
const HOT: Color = Color("eaffc4")
const EYE_LOOK: Array[int] = [0, 0, 0, 1, 2, 2, 3, 0, 0, 4, 5, 5, 6, 0, 7, 0] ## frames of the eye strip, half a second each

const INTERIOR: String = "witch_stairs" ## the shaft with the spiral stair; the witch's room above it is reached from there (data/interiors.json, tools/art_witch_tower_inside.py)

var doorway: Doorway ## the gate (E): into the shaft
var exit_position: Vector2 ## where she stands when she comes out again
var _info: Dictionary = {}
var _origin: Vector2 = Vector2.ZERO ## the frame's top left, from the feet
var _glows: Array[CanvasItem] = []
var _swaying: Array[ShaderMaterial] = []
var _window: Sprite2D
var _eye: Sprite2D
var _cauldron: Sprite2D
var _fx: Node2D
var _time: float = 0.0
var _night: float = 0.0
var _walk: float = -1.0 ## >= 0: the figure is crossing the window
var _next_walk: float = 5.0
static var _unlit_sway: Shader


func _ready() -> void:
	_info = JSON.parse_string(FileAccess.get_file_as_string(DIR + "witch_tower.json")) as Dictionary
	var frame: Array = _info.frame
	_origin = Vector2(-float(frame[0]) / 2.0, -float(_info.ground))
	y_sort_enabled = false
	var pad: Sprite2D = _sprite("tower_pad", Vector2(-95.0, -float((_info.pad as Dictionary).feet)), self)
	pad.z_index = -9
	var body: Sprite2D = _sprite("tower", _origin, self)
	_glows.append(_sprite("tower_glow", Vector2.ZERO, body, true))
	_window = _strip("tower_window", _info.window_anim, body)
	_eye = _strip("tower_eye", _info.eye_anim, body)
	_cauldron = _strip("tower_cauldron", _info.cauldron_anim, body)
	var parts: Dictionary = _info.parts
	for id: String in parts:
		var part: Dictionary = parts[id]
		var crown: bool = id == "tower_crown"
		var sprite: Sprite2D = _sprite(id, _point(part.at), self)
		sprite.material = _sway_material(SWAY, crown)
		if bool(part.glow):
			var glow: Sprite2D = _sprite(id + "_glow", Vector2.ZERO, sprite)
			glow.material = _sway_material(_unlit(), crown)
			_glows.append(glow)
	_fx = Node2D.new()
	_fx.material = Unlit.material()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_smoke(_point(_info.smoke), Vector2(6.0, -16.0), 22, 5.5, Color(0.55, 1.0, 0.5, 0.34))
	_smoke(_point(_info.cauldron) + Vector2(0, -2), Vector2(2.0, -11.0), 8, 2.2, Color(0.8, 1.0, 0.7, 0.4))
	_light(_point(_info.window), 70, 0.9)
	_light(_point(_info.cauldron), 34, 0.7)
	_light(Vector2(0, -6), 54, 0.75)
	_light(_point(_info.turret_window), 36, 0.5)
	var body_shape: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = 17.0
	capsule.height = 78.0
	shape.shape = capsule
	shape.rotation = PI / 2.0
	shape.position = Vector2(0, -24)
	body_shape.add_child(shape)
	add_child(body_shape)
	doorway = Doorway.new()
	doorway.name = "Gate"
	doorway.interior_id = INTERIOR
	doorway.reach_radius = 10.0
	doorway.prompt_height = 44.0
	doorway.position = Vector2(0, 1)
	add_child(doorway)
	exit_position = global_position + Vector2(0, 20)
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if interiors != null:
		for room: String in [INTERIOR, "witch_room"]: ## both lie behind this gate as far as the open world is concerned
			interiors.register_entrance(room, self)
	add_to_group("night_lights")
	set_night(TimeManager.night_amount())


func set_night(amount: float) -> void:
	_night = amount


func _point(at: Variant) -> Vector2:
	return _origin + Vector2(float((at as Array)[0]), float((at as Array)[1]))


func _sprite(file: String, at: Vector2, parent: Node, unlit: bool = false) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(DIR + file + ".png") as Texture2D
	sprite.centered = false
	sprite.position = at
	if unlit:
		sprite.material = Unlit.material()
	parent.add_child(sprite)
	return sprite


func _strip(file: String, data: Dictionary, parent: Node) -> Sprite2D:
	var sprite: Sprite2D = _sprite(file, Vector2(float((data.at as Array)[0]), float((data.at as Array)[1])), parent, true)
	sprite.hframes = int(data.frames)
	return sprite


static func _unlit() -> Shader:
	if _unlit_sway == null:
		_unlit_sway = Shader.new()
		_unlit_sway.code = SWAY.code.replace("shader_type canvas_item;", "shader_type canvas_item;\nrender_mode unshaded;")
	return _unlit_sway


func _sway_material(shader: Shader, crown: bool) -> ShaderMaterial:
	var made: ShaderMaterial = ShaderMaterial.new()
	made.shader = shader
	made.set_shader_parameter("pivot_row", 74.0 if crown else 0.0) # the crown is rooted at its foot, the rest hangs from its top
	made.set_shader_parameter("dir", -1.0 if crown else 1.0)
	made.set_shader_parameter("amount", 2.0 if crown else 3.0)
	made.set_shader_parameter("flutter", 0.5)
	made.set_shader_parameter("cell_w", 14.0 if crown else 6.0)
	_swaying.append(made)
	return made


func _smoke(at: Vector2, drift: Vector2, amount: int, life: float, tint: Color) -> void:
	var smoke: CPUParticles2D = CPUParticles2D.new()
	smoke.position = at
	smoke.amount = amount
	smoke.lifetime = life
	smoke.direction = drift.normalized()
	smoke.spread = 14.0
	smoke.gravity = Vector2.ZERO
	smoke.initial_velocity_min = drift.length() * 0.7
	smoke.initial_velocity_max = drift.length() * 1.2
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 4.0
	smoke.color = tint
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	smoke.color_ramp = fade
	smoke.material = Unlit.material()
	add_child(smoke)


func _light(at: Vector2, radius: int, energy: float) -> void:
	var light: NightLight = NightLight.new()
	light.position = at
	light.radius = radius
	light.base_energy = energy
	light.glow_color = GREEN
	add_child(light)


func _process(delta: float) -> void:
	_time += delta
	var beat: float = 0.5 + 0.5 * sin(_time * 1.7)
	var strength: float = lerpf(0.4, 1.0, _night) * (0.86 + 0.14 * beat)
	for glow: CanvasItem in _glows:
		glow.modulate.a = strength
	var wind: float = WorldWind.sample(global_position).x
	for made: ShaderMaterial in _swaying:
		made.set_shader_parameter("wind", wind)
		made.set_shader_parameter("time", _time)
	_cauldron.frame = int(_time * 6.0) % _cauldron.hframes
	_eye.frame = EYE_LOOK[int(_time * 2.0) % EYE_LOOK.size()]
	# somebody is home: now and then she passes the window (more often at night)
	if _walk < 0.0:
		_next_walk -= delta * lerpf(0.4, 1.0, _night)
		if _next_walk <= 0.0:
			_walk = 0.0
	else:
		_walk += delta * 3.2
		if _walk >= float(_window.hframes - 1):
			_walk = -1.0
			_next_walk = randf_range(7.0, 15.0)
	_window.frame = 0 if _walk < 0.0 else 1 + int(_walk)
	_window.flip_h = false
	_fx.queue_redraw()


func walk_now() -> void: ## for the preview
	_walk = 0.0


func _draw_fx() -> void:
	# candle flames: a flickering pixel or two over every wick
	var candles: Array = _info.candles
	for i: int in candles.size():
		var at: Vector2 = _point(candles[i])
		var flick: int = int(_time * 9.0 + float(i) * 2.3) % 4
		_fx.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(2, 2)), Color(GREEN, 0.25))
		_fx.draw_rect(Rect2(at + Vector2(0 if flick < 3 else -1, -1 if flick != 1 else -2), Vector2(1, 2 if flick != 2 else 1)), HOT)
	# three wisps circle the keep, slowly climbing and sinking; dim while they are behind it
	for i: int in 3:
		var turn: float = _time * (0.5 + 0.11 * float(i)) + float(i) * 2.1
		var height: float = -60.0 - 62.0 * float(i) + sin(_time * 0.4 + float(i)) * 18.0
		var at: Vector2 = Vector2(cos(turn) * 44.0, height + sin(turn) * 9.0).round()
		var front: float = 1.0 if sin(turn) > -0.15 else 0.0
		if front < 0.5 and absf(at.x) < 26.0:
			continue
		var twinkle: float = 0.7 + 0.3 * sin(_time * 7.0 + float(i) * 1.9)
		_fx.draw_rect(Rect2(at + Vector2(-2, -2), Vector2(5, 5)), Color(GREEN, 0.10 * twinkle))
		_fx.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(3, 3)), Color(GREEN, 0.32 * twinkle))
		_fx.draw_rect(Rect2(at, Vector2(1, 1)), HOT)
		for k: int in range(1, 5): # a tail
			var back: float = turn - float(k) * 0.09
			_fx.draw_rect(Rect2(Vector2(cos(back) * 44.0, height + sin(back) * 9.0).round(), Vector2(1, 1)), Color(GREEN, 0.5 - 0.1 * float(k)))
