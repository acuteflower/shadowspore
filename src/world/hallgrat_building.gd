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
var _lamp: bool = false ## a street lantern: it burns only once Pim has lit it (`HallgratPeople.lamp_lit`)
const ACTIVE_DIST_SQ: float = 680.0 * 680.0
var _far_wait: float = 0.0
var _at: Vector2 = Vector2.ZERO
var _light: NightLight


func setup(type: String, at: Vector2, mirrored: bool) -> void:
	type_id = type
	flip = mirrored
	position = at
	_at = at
	_lamp = type == "deko_laterne"
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
		var path: String = DIR + String(info.get("dir", "")) + type_id + ("_glow.png" if glow else ".png")
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
		_light = light
	_time = fposmod(position.x * 0.01, 7.0)
	_far_wait = fposmod(absf(_at.x * 0.017 + _at.y * 0.031), 0.35)
	if not bool(info.get("solid", true)): ## a flower bed, a heap of rubble: walked over
		return
	var body: StaticBody2D = StaticBody2D.new()
	if info.has("chain"): ## a wall: a row of turned boxes along its line (a thin band polygon of a curved wall failed to decompose)
		var chain: Array = info.chain as Array
		var thick: float = float(info.get("thick", 7.0)) ## the town wall is thicker than a garden wall
		for t: Variant in info.get("towers", []) as Array: ## the town wall's round towers: a circle each
			var tower: Array = t as Array
			var round_shape: CollisionShape2D = CollisionShape2D.new()
			var circle: CircleShape2D = CircleShape2D.new()
			circle.radius = float(tower[2])
			round_shape.shape = circle
			round_shape.position = Vector2(float(tower[0]) * (-1.0 if flip else 1.0), float(tower[1]))
			body.add_child(round_shape)
		for k: int in chain.size() - 1:
			var a: Vector2 = Vector2(float((chain[k] as Array)[0]), float((chain[k] as Array)[1]))
			var b: Vector2 = Vector2(float((chain[k + 1] as Array)[0]), float((chain[k + 1] as Array)[1]))
			if flip:
				a.x = -a.x
				b.x = -b.x
			var piece: CollisionShape2D = CollisionShape2D.new()
			var wall_box: RectangleShape2D = RectangleShape2D.new()
			wall_box.size = Vector2(a.distance_to(b) + 3.0, thick)
			piece.shape = wall_box
			piece.position = (a + b) / 2.0 + Vector2(0, -1)
			piece.rotation = (b - a).angle()
			body.add_child(piece)
		add_child(body)
		return
	if info.has("poly"):  # a house turned halfway to a diagonal way: its footprint is a turned rectangle, shrunk a little towards its middle
		var pts: PackedVector2Array = PackedVector2Array()
		var mid: Vector2 = Vector2.ZERO
		for q: Variant in info.poly as Array:
			var corner: Vector2 = Vector2(float((q as Array)[0]) * (-1.0 if flip else 1.0), float((q as Array)[1]))
			pts.append(corner)
			mid += corner
		mid /= float(maxi(1, pts.size()))
		for k: int in pts.size(): ## shrunk a little towards its middle
			pts[k] = pts[k] + (mid - pts[k]).normalized() * minf(4.0, (mid - pts[k]).length() * 0.3)
		var polygon: CollisionPolygon2D = CollisionPolygon2D.new()
		polygon.polygon = pts
		body.add_child(polygon)
		add_child(body)
		_time = fposmod(position.x * 0.01, 7.0)
		_far_wait = fposmod(absf(_at.x * 0.017 + _at.y * 0.031), 0.35)
		return
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(maxf(8.0, _foot.x - 6.0), maxf(6.0, _foot.y - 4.0))
	shape.shape = box
	shape.position = Vector2(0, -box.size.y / 2.0 - 1.0)
	body.add_child(shape)
	add_child(body)
	_time = fposmod(position.x * 0.01, 7.0)
	_far_wait = fposmod(absf(_at.x * 0.017 + _at.y * 0.031), 0.35)


func _process(delta: float) -> void:
	if _glow == null and _sprite == null:
		set_process(false)
		return
	if _far_wait > 0.0:
		_far_wait -= delta
		if _far_wait > 0.0:
			return
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d() if vp != null else null
	if cam != null:
		var near: bool = global_position.distance_squared_to(cam.get_screen_center_position()) <= ACTIVE_DIST_SQ
		if not near:
			for player: Player in Player.all:
				if is_instance_valid(player) and player.is_multiplayer_authority() and global_position.distance_squared_to(player.global_position) <= ACTIVE_DIST_SQ:
					near = true
					break
		if not near:
			if _glow != null and _glow.modulate.a != 0.0:
				_glow.modulate.a = 0.0
			if _sprite != null and _sprite.modulate.a != 1.0:
				_sprite.modulate.a = 1.0
				if _glow != null:
					_glow.self_modulate.a = 1.0
			_far_wait = 0.35
			return
	_time += delta
	if _glow != null:
		var night: float = TimeManager.night_amount()
		var lit: bool = not _lamp or HallgratPeople.lamp_lit(_at, TimeManager.time_of_day)
		var glow_a: float = 0.0 if (night <= 0.005 or not lit) else night * (0.9 + 0.1 * sin(_time * 1.7))
		if _glow.modulate.a != glow_a:
			_glow.modulate.a = glow_a
		if _light != null and _light.visible != lit:
			_light.visible = lit
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
	if _sprite.modulate.a != target:
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

## Mirror image in water and puddles (WaterReflections).
func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		WaterReflections.watch(self, false)
	elif what == NOTIFICATION_EXIT_TREE:
		WaterReflections.unwatch(self)
