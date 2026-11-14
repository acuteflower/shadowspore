class_name HallgratBuilding
extends Node2D
## One building or market stall of Hallgrat (docs/stadt_westen_konzept.md stage 3b; pictures by tools/art_hallgrat_houses.py, the numbers in
## data/hallgrat_art.json). The node stands on the middle of the building's front edge, so it sorts with the world by its feet. Its windows'
## glass is a second, unlit picture that only shines at night (a warm NightLight at the first window); a StaticBody covers the footprint; a
## player walking behind it sees the building fade, the way tree crowns do. Built by `Hallgrat`, the same on every peer.
const DIR: String = "res://assets/town/hallgrat/"
const FADE_ALPHA: float = 0.42

var type_id: String = ""
var flip: bool = false
var _sprite: Sprite2D
var _glow: Sprite2D
var _rect: Rect2 ## the picture, local px (for the fade)
var _foot: Vector2
var _check: float = 0.0
var _time: float = 0.0


func setup(type: String, at: Vector2, mirrored: bool) -> void:
	type_id = type
	flip = mirrored
	position = at
	name = "Building_" + type


func _ready() -> void:
	var info: Dictionary = (DataRegistry.table("hallgrat_art").get("types", {}) as Dictionary).get(type_id, {}) as Dictionary
	if info.is_empty():
		push_warning("Hallgrat: no picture for " + type_id)
		return
	var size: Vector2 = Vector2(float((info.size as Array)[0]), float((info.size as Array)[1]))
	var feet: Vector2 = Vector2(float((info.feet as Array)[0]), float((info.feet as Array)[1]))
	if flip:
		feet.x = size.x - feet.x
	_foot = Vector2(float((info.foot as Array)[0]), float((info.foot as Array)[1]))
	_rect = Rect2(-feet, size)
	for glow: bool in [false, true]:
		var path: String = DIR + type_id + ("_glow.png" if glow else ".png")
		if not ResourceLoader.exists(path):
			continue
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(path) as Texture2D
		sprite.centered = false
		sprite.flip_h = flip
		sprite.offset = -feet
		if glow:
			sprite.material = Unlit.material()
			_glow = sprite
		else:
			_sprite = sprite
		add_child(sprite)
	var lights: Array = info.get("lights", []) as Array
	if not lights.is_empty():
		var first: Array = lights[0] as Array
		var light: NightLight = NightLight.new()
		var lx: float = float(first[0])
		light.position = Vector2((size.x - lx) if flip else lx, float(first[1])) - feet + Vector2(0, 10)
		light.radius = 40
		light.base_energy = 0.45
		light.glow_color = Color("ffb35a")
		add_child(light)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(maxf(8.0, _foot.x - 6.0), maxf(6.0, _foot.y - 4.0))
	shape.shape = box
	shape.position = Vector2(0, -box.size.y / 2.0 - 1.0)
	body.add_child(shape)
	add_child(body)
	_time = fposmod(position.x * 0.01, 7.0)


func _process(delta: float) -> void:
	_time += delta
	if _glow != null:
		var night: float = TimeManager.night_amount()
		_glow.modulate.a = lerpf(0.0, 1.0, night) * (0.9 + 0.1 * sin(_time * 1.7))
	_check -= delta
	if _check > 0.0 or _sprite == null:
		return
	_check = 0.15
	var hidden: bool = false
	for player: Player in Player.all:
		if not is_instance_valid(player) or not player.is_multiplayer_authority():
			continue
		var local: Vector2 = player.global_position - global_position
		if local.y < -_foot.y and _rect.grow(-4.0).has_point(local + Vector2(0, -20)):
			hidden = true
	var target: float = FADE_ALPHA if hidden else 1.0
	_sprite.modulate.a = move_toward(_sprite.modulate.a, target, 0.25)
	if _glow != null:
		_glow.self_modulate.a = _sprite.modulate.a


## The tiles the building stands on (and one round it), kept free of generated plants and stones.
func footprint_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var info: Dictionary = (DataRegistry.table("hallgrat_art").get("types", {}) as Dictionary).get(type_id, {}) as Dictionary
	if info.is_empty():
		return out
	var foot: Vector2 = Vector2(float((info.foot as Array)[0]), float((info.foot as Array)[1]))
	var x0: int = floori((position.x - foot.x / 2.0) / 16.0) - 1
	var x1: int = floori((position.x + foot.x / 2.0) / 16.0) + 1
	var y0: int = floori((position.y - foot.y) / 16.0) - 1
	var y1: int = floori(position.y / 16.0) + 1
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			out.append(Vector2i(x, y))
	return out
