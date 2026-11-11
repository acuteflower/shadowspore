class_name SpellZone
extends Node2D
## A spell standing on the ground (docs/magie_konzept.md): the base of BanishLight and RootGround. Every peer builds its own copy from the same
## parameters (SpellComponent._rpc_zone) and draws it; only the host's copy deals damage and heals. Its look is seeded from where it stands and
## who cast it, so every peer sees the same roots and runes. It frees itself when its time and its ending have run out.

const SQUASH: float = 0.6 ## ground circles are flat in the 3/4 view (the same squash as NightLight)
const HURTBOX_MASK: int = 16 ## physics layer 5: enemies (and training dummies)
const ADD_SHADER: String = "shader_type canvas_item;\nrender_mode unshaded, blend_add;\n"

var params: Dictionary = {} ## SpellRules.params of the cast (set before it enters the tree)
var caster: int = 0 ## peer id of who cast it (the credit for kills)
var extra: Array = [] ## what the host decided for this cast (SpellComponent._rpc_zone): Glutschwarm's targets, the veiled, the price
var radius: float = 32.0
var seconds: float = 5.0
var _age: float = 0.0
var _tick_clock: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _motes: Array[Dictionary] = [] ## {p (zone px), v, life, max, color, size, drag, rise}
var _air: Node2D ## the motes, above everybody, additive

static var _add_material: CanvasItemMaterial
static var _sounds: Dictionary = {}


## A magic sound (assets/audio/magic, tools/audio_magic.py) at a point in the world; a missing file is skipped.
static func sound(parent: Node, id: String, at: Vector2, db: float = 0.0) -> void:
	if not _sounds.has(id):
		var path: String = "res://assets/audio/magic/%s.wav" % id
		_sounds[id] = load(path) if ResourceLoader.exists(path) else null
	var s: AudioStream = _sounds[id] as AudioStream
	if s == null or parent == null or not parent.is_inside_tree():
		return
	var scene: Node = parent.get_tree().current_scene if parent.get_tree().current_scene != null else parent
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = s
	player.volume_db = db
	player.pitch_scale = randf_range(0.96, 1.04)
	player.max_distance = 340.0
	scene.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


static func add_material() -> CanvasItemMaterial:
	if _add_material == null:
		_add_material = CanvasItemMaterial.new()
		_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_add_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _add_material


func _ready() -> void:
	position = position.round()
	radius = float(params.get("radius", 32.0))
	seconds = float(params.get("seconds", 5.0))
	y_sort_enabled = true
	_rng.seed = hash(Vector3i(roundi(position.x), roundi(position.y), caster))
	_air = Node2D.new()
	_air.name = "Air"
	_air.z_index = 3
	_air.material = add_material()
	_air.draw.connect(_draw_air)
	add_child(_air)
	_build()


func _process(delta: float) -> void:
	_age += delta
	_tick_motes(delta)
	if multiplayer.is_server() and _age <= seconds:
		_tick_clock += delta
		var tick: float = float(params.get("tick", 1.0))
		while _tick_clock >= tick:
			_tick_clock -= tick
			_host_tick(tick)
	_update(delta)
	_air.queue_redraw()
	if _age >= seconds + _ending():
		queue_free()


# ---------------------------------------------------------------- for the kinds

func _build() -> void:
	pass


func _update(_delta: float) -> void:
	pass


func _host_tick(_tick: float) -> void:
	pass


## Seconds the ending takes after `seconds` have run out.
func _ending() -> float:
	return 0.8


# ---------------------------------------------------------------- shared helpers

## 0..1 how far the spell has ended (0 while it lives).
func ending_amount() -> float:
	return clampf((_age - seconds) / _ending(), 0.0, 1.0)


func inside(world_pos: Vector2) -> bool:
	var rel: Vector2 = world_pos - global_position
	return Vector2(rel.x, rel.y / SQUASH).length() <= radius


## Host: every hurtbox of an enemy whose feet stand in the circle (no plants: their harvest boxes share the layer).
func enemies_inside() -> Array[HurtboxComponent]:
	var found: Array[HurtboxComponent] = []
	for box: HurtboxComponent in HitScan.circle(self, global_position, radius + 10.0, HURTBOX_MASK):
		if box is HarvestHurtbox or box.health == null or box.health.current <= 0.0:
			continue
		if inside(feet_of(box)):
			found.append(box)
	return found


## Where the creature of a hurtbox stands (its body's feet, else the box itself).
static func feet_of(box: HurtboxComponent) -> Vector2:
	var body: Node2D = box.get_parent() as Node2D
	return body.global_position if body != null else box.global_position


func players_inside() -> Array[Player]:
	var found: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Player = node as Player
		if player != null and player.health.current > 0.0 and inside(player.global_position):
			found.append(player)
	return found


func caster_node() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(caster):
			return node as Player
	return null


## A child that draws one quad through `shader` (the zone's frame: the quad's own position is passed to the shader as `offset` when it has one).
func shader_quad(node_name: String, shader_path: String, rect: Rect2, z: int, at: Vector2 = Vector2.ZERO) -> Node2D:
	var node: Node2D = Node2D.new()
	node.name = node_name
	node.position = at
	node.z_index = z
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load(shader_path) as Shader
	node.material = mat
	var local_rect: Rect2 = Rect2(rect.position - at, rect.size)
	node.draw.connect(func() -> void: node.draw_rect(local_rect, Color.WHITE))
	add_child(node)
	return node


static func set_shader(node: Node2D, key: String, value: Variant) -> void:
	(node.material as ShaderMaterial).set_shader_parameter(key, value)


## A mote in the air: `p` in the zone's frame, `v` px/s, rises against `rise` px/s² and slows by `drag`.
func mote(p: Vector2, v: Vector2, life: float, color: Color, size: int = 1, rise: float = 0.0, drag: float = 1.5) -> void:
	if _motes.size() >= 160:
		return
	_motes.append({"p": p, "v": v, "life": life, "max": life, "color": color, "size": size, "rise": rise, "drag": drag})


func _tick_motes(delta: float) -> void:
	for i: int in range(_motes.size() - 1, -1, -1):
		var m: Dictionary = _motes[i]
		m["life"] = float(m["life"]) - delta
		if float(m["life"]) <= 0.0:
			_motes.remove_at(i)
			continue
		var v: Vector2 = m["v"] as Vector2
		v.y -= float(m["rise"]) * delta
		v *= exp(-float(m["drag"]) * delta)
		m["v"] = v
		m["p"] = (m["p"] as Vector2) + v * delta


func _draw_air() -> void:
	for m: Dictionary in _motes:
		var k: float = float(m["life"]) / float(m["max"])
		var colour: Color = m["color"] as Color
		var size: int = int(m["size"])
		var at: Vector2 = (m["p"] as Vector2).round()
		var tint: Color = Color(colour, colour.a * minf(k * 2.0, 1.0))
		if size >= 2 and k > 0.35: ## a bigger mote: a little cross with a bright heart
			_air.draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 1)), Color(tint, tint.a * 0.55))
			_air.draw_rect(Rect2(at + Vector2(0, -1), Vector2(1, 3)), Color(tint, tint.a * 0.55))
		_air.draw_rect(Rect2(at, Vector2.ONE), tint)


## A random point inside the circle (zone frame).
func random_inside(rng: RandomNumberGenerator, fill: float = 1.0) -> Vector2:
	var a: float = rng.randf() * TAU
	var r: float = sqrt(rng.randf()) * radius * fill
	return Vector2(cos(a) * r, sin(a) * r * SQUASH)
