class_name CrowTree
extends Node2D
## Unique landmark; ecology uses the shared replicated corvid population and its caps.
const ART: String = "res://assets/props/crow_tree/"
var liberated: bool = false
var _layers: Array[Sprite2D] = []
var _materials: Array[ShaderMaterial] = []
var _glow: Sprite2D
var _time: float = 0.0
var _visit: float = 0.0
var _birds: Array[WildCorvid] = []

func _ready() -> void:
	add_to_group("crow_tree")
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART + "crow_tree.json")) as Dictionary
	for id: String in info.layers:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(ART + id + ".png") as Texture2D
		sprite.centered = false
		sprite.position = Vector2(-160, -340)
		add_child(sprite)
		if id == "pad":
			sprite.z_index = -9
		elif id == "glow":
			_glow = sprite
			sprite.material = Unlit.material()
		else:
			_layers.append(sprite)
			if id in ["crown", "moss", "charms"]:
				var mat: ShaderMaterial = ShaderMaterial.new()
				mat.shader = preload("res://assets/shaders/sway_rows.gdshader")
				mat.set_shader_parameter("pivot_row", 340.0)
				mat.set_shader_parameter("dir", -1.0)
				mat.set_shader_parameter("amount", 0.12)
				mat.set_shader_parameter("flutter", 0.06)
				mat.set_shader_parameter("speed", 0.65)
				sprite.material = mat
				_materials.append(mat)
	for raw: Array in info.perches:
		var perch: RoofPerch = RoofPerch.new()
		perch.host = self
		perch.position = Vector2(float(raw[0]) - 160.0, 1)
		perch.perch_height = 341.0 - float(raw[1])
		add_child(perch)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var capsule: CapsuleShape2D = CapsuleShape2D.new()
	capsule.radius = 14.0
	capsule.height = 62.0
	shape.shape = capsule
	shape.rotation = PI / 2.0
	shape.position = Vector2(0, -16)
	body.add_child(shape)
	add_child(body)

func set_liberated(value: bool) -> void:
	if liberated == value:
		return
	liberated = value
	if multiplayer.is_server():
		for bird: WildCorvid in _birds:
			if is_instance_valid(bird):
				bird._take_wing(false, false, false, true)

func _process(delta: float) -> void:
	_time += delta
	for mat: ShaderMaterial in _materials:
		mat.set_shader_parameter("time", _time)
		mat.set_shader_parameter("wind", sin(_time * 0.3) * 0.18)
	_glow.modulate.a = (0.12 if liberated else 0.65) + sin(_time * 1.5) * 0.08
	var hidden: bool = false
	var near: bool = false
	for hero: Player in Player.all:
		var d: Vector2 = hero.global_position - global_position
		near = near or d.length() < 650.0
		if hero.is_multiplayer_authority() and d.y < -20.0 and d.y > -320.0 and absf(d.x) < 135.0:
			hidden = true
	for sprite: Sprite2D in _layers:
		sprite.modulate.a = move_toward(sprite.modulate.a, 0.35 if hidden else 1.0, delta * 2.0)
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
	if _birds.size() >= 9:
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
