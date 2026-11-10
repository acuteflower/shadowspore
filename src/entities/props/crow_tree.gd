class_name CrowTree
extends Node2D
## Der Rabenbaum: the unique landmark in the middle of the Schieferkessel (docs/enemies/boss_mora.md). Art: `py -3 tools/art_crow_tree.py`
## (assets/props/crow_tree/: pad, trunk, crown, moss, charms, glow, veins; 320x360, feet (160, 340); crow_tree.json holds 16 perches and the hollow).
## Its ecology uses the shared replicated corvid population and its caps.
## What Morwenna did to it is driven from here, the same on every peer:
##   `veins`  the ritual's cracks of light pulse violet with a heartbeat; `set_hour(1)` (the witch hour, phase 3) makes them blaze witch green and the
##            whole tree glow sickly; `set_liberated(true)` lets them go out for good, the leaves warm, a warm light settles under the crown and the
##            ravens come home to all sixteen boughs.
const ART: String = "res://assets/props/crow_tree/"
const ORIGIN: Vector2 = Vector2(-160, -340)
const HEXG: Color = Color("a8ff6a")
const WARM: Color = Color(1.2, 1.14, 0.9)

var liberated: bool = false
var hour: float = 0.0 ## 0..1: the witch hour (set by the fight)
var drain: float = 0.0 ## 0..1: she is drinking from it right now: the veins race
var _layers: Array[Sprite2D] = []
var _leafy: Array[Sprite2D] = []
var _materials: Array[ShaderMaterial] = []
var _glow: Sprite2D
var _veins: Sprite2D
var _light: NightLight
var _time: float = 0.0
var _visit: float = 0.0
var _hour_now: float = 0.0
var _free: float = 0.0
var _night: float = 0.0
var _hollow: Vector2 = Vector2(0, -40)
var _birds: Array[WildCorvid] = []


func _ready() -> void:
	add_to_group("crow_tree")
	add_to_group("night_lights")
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART + "crow_tree.json")) as Dictionary
	for id: String in info.layers:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = id.capitalize()
		sprite.texture = load(ART + id + ".png") as Texture2D
		sprite.centered = false
		sprite.position = ORIGIN
		add_child(sprite)
		if id == "pad":
			sprite.z_index = -9
		elif id == "glow":
			_glow = sprite
			sprite.material = Unlit.material()
		elif id == "veins":
			_veins = sprite
			sprite.material = Unlit.material()
		else:
			_layers.append(sprite)
			if id in ["crown", "moss", "charms"]:
				var mat: ShaderMaterial = ShaderMaterial.new()
				mat.shader = preload("res://assets/shaders/sway_rows.gdshader")
				mat.set_shader_parameter("pivot_row", 340.0)
				mat.set_shader_parameter("dir", -1.0)
				mat.set_shader_parameter("amount", 0.07 if id == "crown" else 0.12)
				mat.set_shader_parameter("flutter", 0.05 if id == "crown" else 0.08)
				mat.set_shader_parameter("speed", 0.65)
				sprite.material = mat
				_materials.append(mat)
				if id != "charms":
					_leafy.append(sprite)
	var at: Array = info.get("hollow", [160, 300]) as Array
	_hollow = Vector2(float(at[0]), float(at[1])) + ORIGIN
	for raw: Array in info.perches:
		var perch: RoofPerch = RoofPerch.new()
		perch.host = self
		perch.position = Vector2(float(raw[0]) - 160.0, 1)
		perch.perch_height = 341.0 - float(raw[1])
		add_child(perch)
	_light = NightLight.new()
	_light.position = Vector2(0, -34)
	_light.radius = 70
	_light.base_energy = 0.55
	_light.glow_color = Color("9a3af0")
	add_child(_light)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = 12.0
	capsule.height = 56.0
	shape.shape = capsule
	shape.rotation = PI / 2.0
	shape.position = Vector2(0, -12)
	body.add_child(shape)
	add_child(body)


## Called by DayNight through the group `night_lights`.
func set_night(amount: float) -> void:
	_night = amount


## The dark mouth in the trunk (world): where her heart beats, where the light goes out when she is freed.
func hollow_point() -> Vector2:
	return global_position + _hollow


## Where she kneels to drink from the tree (the ground in front of the hollow).
func tap_point() -> Vector2:
	return global_position + Vector2(2, 20)


## Where she hides before the fight: up in the crown, above the fork.
func crown_height() -> float:
	return 168.0


func set_hour(value: float) -> void:
	hour = clampf(value, 0.0, 1.0)


func set_liberated(value: bool, instant: bool = false) -> void:
	if liberated == value:
		return
	liberated = value
	if instant:
		_free = 1.0 if value else 0.0
	if multiplayer.is_server():
		for bird: WildCorvid in _birds:
			if is_instance_valid(bird):
				bird._take_wing(false, false, false, true)


func _process(delta: float) -> void:
	_time += delta
	_hour_now = move_toward(_hour_now, 0.0 if liberated else hour, delta * 0.7)
	_free = move_toward(_free, 1.0 if liberated else 0.0, delta * 0.22)
	for mat: ShaderMaterial in _materials:
		mat.set_shader_parameter("time", _time)
		mat.set_shader_parameter("wind", sin(_time * 0.3) * 0.18 + sin(_time * (2.3 + 5.0 * _hour_now)) * 0.1 * _hour_now) ## restless in the witch hour
	## the ritual: a double heartbeat runs through the veins, faster while she drinks; green and blazing in the witch hour; out when freed
	var beat: float = VoidGlow.beat(_time, 0.0, 0.8 + 0.5 * _hour_now + 0.9 * drain)
	var vein_color: Color = Color(1, 1, 1).lerp(Color(HEXG.r * 1.25, HEXG.g * 1.25, HEXG.b * 1.25), _hour_now)
	var vein_alpha: float = (0.42 + 0.3 * _night + 0.3 * beat + 0.4 * _hour_now + 0.3 * drain) * (1.0 - _free)
	_veins.modulate = Color(vein_color.r, vein_color.g, vein_color.b, clampf(vein_alpha, 0.0, 1.0))
	_veins.self_modulate = Color(1, 1, 1) if _hour_now < 0.5 else Color(0.72, 1.0, 0.5) ## the violet cracks turn too
	_glow.modulate.a = lerpf(0.3 + 0.5 * _night + sin(_time * 1.5) * 0.08, 0.16, _free)
	var leaf: Color = Color(1, 1, 1).lerp(Color(0.74, 1.0, 0.78), _hour_now * 0.6).lerp(WARM, _free)
	_light.glow_color = Color("9a3af0").lerp(HEXG, _hour_now).lerp(Color("ffd9a0"), _free)
	_light.base_energy = lerpf(0.55 + 0.5 * _hour_now, 0.7, _free)
	var hidden: bool = false
	var near: bool = false
	for hero: Player in Player.all:
		var d: Vector2 = hero.global_position - global_position
		near = near or d.length() < 650.0
		if hero.is_multiplayer_authority() and d.y < -14.0 and d.y > -300.0 and absf(d.x) < 120.0:
			hidden = true
	for sprite: Sprite2D in _layers:
		var a: float = move_toward(sprite.modulate.a, 0.3 if hidden else 1.0, delta * 2.0)
		var tone: Color = leaf if sprite in _leafy else Color(1, 1, 1)
		sprite.modulate = Color(tone.r, tone.g, tone.b, a)
	if not multiplayer.is_server():
		return
	_visit -= delta
	if _visit > 0.0:
		return
	_visit = 3.0
	for i: int in range(_birds.size() - 1, -1, -1):
		if not is_instance_valid(_birds[i]):
			_birds.remove_at(i)
	if not near:
		for bird: WildCorvid in _birds:
			bird.queue_free()
		_birds.clear()
		return
	if _birds.size() >= (16 if liberated else 9):
		return
	var population: CorvidPopulation = get_tree().get_first_node_in_group("corvid_population") as CorvidPopulation
	if population == null:
		return
	for attempt: int in 12:
		var point: Vector2 = global_position + Vector2.from_angle(randf() * TAU) * randf_range(180.0, 290.0)
		var bird: WildCorvid = population.spawn_visitor("crow", point, "crow_tree")
		if bird != null:
			_birds.append(bird)
			bird._take_wing(false, false, false, true)
			break
