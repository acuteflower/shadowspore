class_name ArenaPillar
extends Node2D
## A monumental stone pillar of the first boss arena (art: tools/art_arena_pillars.py, 3 variants of 64x128, feet at (32, 118)); placed from
## data/ground.json "arenas[].pillars" by `WorldLevel._add_arenas`. Solid at its foot, a vein in it glows (unlit sheet: dim by day, bright
## at night, breathing) with a faint violet pool of light, and it fades to a ghost while it really hides someone standing behind it
## (like the crowns of the trees), so the fight stays readable.
##
## The boss fight can arm a pillar (`set_armed`): then weapons wear it down (the host decides, `_rpc_hit` tells everybody), cracks of light spread over it, and when it
## is gone it collapses (`_rpc_break`): it shudders, the top bursts into chunks cut out of its own picture that tumble and settle as rubble, a jagged stump stays,
## `shattered` fires on every peer at the burst. `restore()` builds it again (the fight was reset).

signal shattered ## the top bursts (on every peer): whoever sat on it falls now
signal worn(left: float, maximum: float) ## a hit landed

const ART: Texture2D = preload("res://assets/props/arena_pillars.png")
const GLOW: Texture2D = preload("res://assets/props/arena_pillars_glow.png")
const FRAME: Vector2i = Vector2i(64, 128)
const FEET: int = 118 ## the row of the picture the base stands on
const BASE: Vector2 = Vector2(22.0, 8.0) ## the solid footprint
const FADE_ALPHA: float = 0.38
const HIDE_HALF_WIDTH: float = 22.0 ## someone this close to the pillar's axis (px) and behind it counts as hidden
const HIDE_HEIGHT: float = 96.0
const CUT_ROW: int = 86 ## above this row of the picture the pillar bursts, below it a stump stays
const COLLAPSE_TIME: float = 0.6 ## shuddering before the burst
const CHUNKS: int = 9
const GRAVITY: float = 420.0

const PERCH_HEIGHTS: Array[float] = [103.0, 92.0, 94.0] ## per variant: how high the top of the capital is above the foot (where a boss perches)

var variant: int = 0
var arena: String = "" ## id of the arena it belongs to (data/ground.json "arenas")
var index: int = 0 ## its number in that arena's "pillars" list
var broken: bool = false ## the top is gone (the stump and the rubble stay)
var integrity: float = 0.0
var max_integrity: float = 1.0
var _sprite: Sprite2D
var _glow: Sprite2D
var _time: float = 0.0
var _covering: bool = false
var _check: float = 0.0
var _fade: Tween
var _armed: bool = false
var _hurtbox: PillarHurtbox
var _fx: Node2D ## cracks and flying chips (lit)
var _fx_glow: Node2D ## the same, glowing
var _cracks: Array[PackedVector2Array] = []
var _chips: Array[Dictionary] = []
var _shake: float = 0.0
var _collapse: float = -1.0
var _fall_dir: Vector2 = Vector2.DOWN
var _chunks: Array[Dictionary] = []
var _rubble: Node2D
var _light: NightLight
var _fury: float = 0.0 ## 0..1: the vein of light has turned into pink-violet fire (Mornath's last phase), see `ignite`
var _fury_goal: float = 0.0
var _fury_speed: float = 1.0
var _fury_material: ShaderMaterial
var _flames: PixelFlames
var _base_material: ShaderMaterial ## the lit picture with its turquoise recoloured
var _teal_glow: Sprite2D ## the picture again, only its turquoise, burning (additive, unshaded)
var _teal_material: ShaderMaterial
var _marker: PillarMarker ## "smash me": ring, chevrons and a leaf of text while the pillar is armed


## Height of the perch above the foot, in px.
func perch_height() -> float:
	return PERCH_HEIGHTS[clampi(variant, 0, PERCH_HEIGHTS.size() - 1)]


func _ready() -> void:
	add_to_group("arena_pillars")
	_sprite = _make(ART, false)
	_glow = _make(GLOW, true)
	_fx = Node2D.new()
	_fx.z_index = 1
	add_child(_fx)
	_fx.draw.connect(_draw_fx)
	_fx_glow = Node2D.new()
	_fx_glow.z_index = 1
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_fx_glow.material = add
	add_child(_fx_glow)
	_fx_glow.draw.connect(_draw_fx_glow)
	_rubble = Node2D.new()
	add_child(_rubble)
	_light = NightLight.new()
	_light.position = Vector2(0, -44)
	_light.radius = 40
	_light.squash = 0.7
	_light.base_energy = 0.45
	_light.glow_color = Color("9468ee")
	add_child(_light)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = BASE
	shape.shape = box
	shape.position = Vector2(0, -BASE.y / 2.0)
	body.add_child(shape)
	add_child(body)
	_hurtbox = PillarHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 0
	_hurtbox.collision_mask = 0
	var hit_shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 15.0
	hit_shape.shape = circle
	hit_shape.position = Vector2(0, -12)
	_hurtbox.add_child(hit_shape)
	add_child(_hurtbox)
	_marker = PillarMarker.new()
	_marker.name = "Marker"
	add_child(_marker)
	_marker.setup(self)
	_time = fmod(position.x * 0.37 + position.y * 0.11, 6.0)
	_make_cracks()


func _make(tex: Texture2D, unlit: bool) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = tex
	sprite.hframes = maxi(tex.get_width() / FRAME.x, 1)
	sprite.frame = clampi(variant, 0, sprite.hframes - 1)
	sprite.offset = Vector2(0, -(FEET - FRAME.y / 2.0))
	if unlit:
		sprite.material = Unlit.material()
	add_child(sprite)
	return sprite


func _process(delta: float) -> void:
	_time += delta
	_shake = maxf(_shake - delta * 3.0, 0.0)
	if _collapse >= 0.0:
		_step_collapse(delta)
	var jolt: Vector2 = Vector2.ZERO
	if _shake > 0.0 or (_collapse >= 0.0 and _collapse < COLLAPSE_TIME):
		var k: float = maxf(_shake, smoothstep(0.0, COLLAPSE_TIME, _collapse) * 1.4 if _collapse >= 0.0 else 0.0)
		jolt = Vector2(roundf(sin(_time * 80.0) * k), 0.0)
	_sprite.position = jolt
	_glow.position = jolt
	_glow.modulate.a = lerpf(0.4, 1.0, TimeManager.night_amount()) * (0.82 + 0.18 * sin(_time * 1.1)) * _sprite.modulate.a
	if _armed and not broken:
		_glow.modulate.a = minf(1.0, _glow.modulate.a * (1.2 + 0.3 * sin(_time * 7.0))) ## an armed pillar glows uneasily
	_run_chips(delta)
	_run_chunks(delta)
	if _armed or not _chips.is_empty() or _collapse >= 0.0 or _shake > 0.0:
		_fx.queue_redraw()
		_fx_glow.queue_redraw()
	_step_fury(delta)
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.1
	var covering: bool = false
	for player: Player in Player.all:
		var rel: Vector2 = player.global_position - global_position
		if rel.y < -2.0 and rel.y > -HIDE_HEIGHT * 0.55 and absf(rel.x) < HIDE_HALF_WIDTH: ## her feet lie behind the pillar, so it is drawn over her
			covering = true
			break
	if covering == _covering:
		return
	_covering = covering
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_sprite, "modulate:a", FADE_ALPHA if _covering else 1.0, 0.18)


# --- the fire of the last phase ------------------------------------------------------------------------------------


## The vein of light turns into pink-violet fire over `seconds` (0 = at once), flames stand on it and the pool of light round the pillar turns pink.
func ignite(seconds: float) -> void:
	if broken:
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
		_teal_material.set_shader_parameter("strength", 0.9)
		_teal_glow = Sprite2D.new()
		_teal_glow.name = "TealFire"
		_teal_glow.texture = ART
		_teal_glow.hframes = _sprite.hframes
		_teal_glow.frame = _sprite.frame
		_teal_glow.offset = _sprite.offset
		_teal_glow.material = _teal_material
		add_child(_teal_glow)
	_sprite.material = _base_material
	if _flames == null:
		_flames = PixelFlames.new()
		_flames.name = "Flames"
		_flames.z_index = 2
		add_child(_flames)
		_flames.build(_flame_spots(), 5.0, 11.0, index + 7)
	_fury_goal = 1.0
	_fury_speed = 1.0 / maxf(seconds, 0.001)
	if seconds <= 0.0:
		_fury = 1.0
	_apply_fury()


func extinguish(seconds: float) -> void:
	_fury_goal = 0.0
	_fury_speed = 1.0 / maxf(seconds, 0.001)
	if seconds <= 0.0:
		_fury = 0.0
		_apply_fury()


func fury() -> float:
	return _fury


## Pixels of the glowing vein (in the pillar's own frame) where flames can stand.
func _flame_spots() -> PackedVector2Array:
	var spots: PackedVector2Array = PackedVector2Array()
	var image: Image = GLOW.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var x0: int = variant * FRAME.x
	for y: int in range(8, CUT_ROW + 6, 4):
		for x: int in range(0, FRAME.x, 2):
			var c: Color = image.get_pixel(x0 + x, y)
			if c.a > 0.5 and (c.r + c.g + c.b) / 3.0 > 0.35 and float(hash(Vector2i(x, y)) % 1000) / 1000.0 < 0.3:
				spots.append(Vector2(x - FRAME.x / 2, y - FEET))
	return spots


func _step_fury(delta: float) -> void:
	if _fury == _fury_goal and _fury <= 0.0:
		return
	if broken and _fury_goal > 0.0:
		_fury_goal = 0.0
		_fury_speed = 2.0
	if _fury != _fury_goal:
		_fury = move_toward(_fury, _fury_goal, delta * _fury_speed)
	_apply_fury()
	if _fury <= 0.0 and _fury_goal <= 0.0:
		_glow.material = Unlit.material() ## the fire is out
		_sprite.material = null
		if _teal_glow != null:
			_teal_glow.visible = false
		_light.glow_color = Color("9468ee")
		_light.base_energy = 0.45 if not broken else 0.15


func _apply_fury() -> void:
	if _fury_material != null:
		_fury_material.set_shader_parameter("fury", _fury)
		_fury_material.set_shader_parameter("time", _time)
		_base_material.set_shader_parameter("fury", _fury)
		_teal_material.set_shader_parameter("fury", _fury)
		_teal_material.set_shader_parameter("time", _time)
		_teal_glow.visible = _fury > 0.0 and not broken
		_teal_glow.position = _sprite.position
		_teal_glow.modulate.a = _sprite.modulate.a
	if _fury > 0.0:
		_glow.modulate.a = maxf(_glow.modulate.a, 0.9 * _fury)
		_light.glow_color = Color("9468ee").lerp(Color("ff5ad8"), _fury)
		_light.base_energy = lerpf(0.45, 0.85, _fury) if not broken else 0.15
	if _flames != null:
		_flames.amount = _fury


# --- being worn down -----------------------------------------------------------------------------------------------


## The fight arms the pillar (on every peer): weapons find it now and wear it down by `hp` in all.
func set_armed(on: bool, hp: float = 60.0) -> void:
	if broken:
		return
	_armed = on
	_hurtbox.set_deferred("collision_layer", 1 << 4 if on else 0)
	if on:
		_marker.urgency = 0.0
		max_integrity = hp
		integrity = hp
	else:
		integrity = max_integrity
	_fx.queue_redraw()


func is_armed() -> bool:
	return _armed and not broken


## The judgement's clock for the marker (0 calm .. 1 out of time): the leaf over the pillar turns magenta and stutters.
func set_marker_urgency(value: float) -> void:
	_marker.urgency = clampf(value, 0.0, 1.0)


## Host (the weapon hit scan): a blow wears the pillar down.
func take_hit(damage: float, from: Vector2) -> void:
	if not multiplayer.is_server() or not _armed or broken or _collapse >= 0.0:
		return
	var left: float = maxf(integrity - maxf(damage, 1.0), 0.0)
	_rpc_hit.rpc(left, (global_position - from).normalized())
	if left <= 0.0:
		_rpc_break.rpc((global_position - from).normalized())


@rpc("authority", "call_local", "reliable")
func _rpc_hit(left: float, away: Vector2) -> void:
	integrity = left
	_shake = 1.0
	for i: int in 6:
		_chips.append({"pos": Vector2(randf_range(-9.0, 9.0), randf_range(-60.0, -14.0)), "vel": Vector2(away.x * randf_range(10.0, 45.0) + randf_range(-20.0, 20.0), randf_range(-60.0, -20.0)), "age": 0.0, "life": randf_range(0.35, 0.7), "z": 0.0})
	worn.emit(integrity, max_integrity)


@rpc("authority", "call_local", "reliable")
func _rpc_break(fall_dir: Vector2) -> void:
	if broken or _collapse >= 0.0:
		return
	_fall_dir = fall_dir if fall_dir != Vector2.ZERO else Vector2.DOWN
	_collapse = 0.0
	integrity = 0.0


func _step_collapse(delta: float) -> void:
	var before: float = _collapse
	_collapse += delta
	if before < COLLAPSE_TIME and _collapse >= COLLAPSE_TIME:
		_shatter()
	if before >= 0.0 and before < COLLAPSE_TIME and fmod(_collapse, 0.09) < delta:
		_chips.append({"pos": Vector2(randf_range(-10.0, 10.0), randf_range(-90.0, -20.0)), "vel": Vector2(randf_range(-30.0, 30.0), randf_range(-50.0, -10.0)), "age": 0.0, "life": randf_range(0.3, 0.6), "z": 0.0})


# --- cracks and chips ----------------------------------------------------------------------------------------------


func _make_cracks() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [arena, index])
	_cracks.clear()
	for c: int in 4:
		var points: PackedVector2Array = PackedVector2Array()
		var p: Vector2 = Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-92.0, -50.0) if c < 2 else rng.randf_range(-50.0, -16.0))
		points.append(p)
		for i: int in 18:
			p += Vector2(rng.randf_range(-3.0, 3.0), 2.0 + rng.randf() * 3.0 if c % 2 == 0 else -(2.0 + rng.randf() * 3.0))
			p.x = clampf(p.x, -12.0, 12.0)
			points.append(p)
		_cracks.append(points)


func _wear() -> float:
	if not _armed and _collapse < 0.0:
		return 0.0
	if _collapse >= 0.0:
		return 1.0
	return clampf(1.0 - integrity / maxf(max_integrity, 1.0), 0.0, 1.0)


func _draw_fx() -> void:
	if broken:
		return
	var wear: float = _wear()
	if wear > 0.0 or _armed:
		for c: int in _cracks.size():
			var points: PackedVector2Array = _cracks[c]
			var shown: int = clampi(int(float(points.size()) * clampf(wear * 1.25 - float(c) * 0.12 + (0.12 if _armed else 0.0), 0.0, 1.0)), 0, points.size() - 1)
			for i: int in shown:
				_fx.draw_line(points[i].round(), points[i + 1].round(), Color("040208"), 1.0)
	for chip: Dictionary in _chips:
		var k: float = float(chip["age"]) / float(chip["life"])
		_fx.draw_rect(Rect2((chip["pos"] as Vector2).round(), Vector2.ONE * (2 if k < 0.5 else 1)), Color("45436a", 1.0 - k))


func _draw_fx_glow() -> void:
	if broken:
		return
	var wear: float = _wear()
	if wear <= 0.0 and not _armed:
		return
	var flicker: float = 0.65 + 0.35 * sin(_time * 11.0)
	for c: int in _cracks.size():
		var points: PackedVector2Array = _cracks[c]
		var shown: int = clampi(int(float(points.size()) * clampf(wear * 1.25 - float(c) * 0.12 + (0.12 if _armed else 0.0), 0.0, 1.0)), 0, points.size() - 1)
		for i: int in shown:
			var p: Vector2 = points[i].round()
			_fx_glow.draw_rect(Rect2(p + Vector2(1, 0), Vector2.ONE), Color("a98af0", (0.4 + 0.5 * wear) * flicker))
			if i % 3 == 0:
				_fx_glow.draw_rect(Rect2(p + Vector2(-1, -1), Vector2(3, 3)), Color("7d57e0", 0.18 * (0.4 + wear)))
	if _collapse >= 0.0:
		var k: float = clampf(_collapse / COLLAPSE_TIME, 0.0, 1.0)
		for i: int in 14: ## the veins flare white as it gives
			var y: float = -18.0 - float(i) * 6.0
			_fx_glow.draw_rect(Rect2(Vector2(-1 + (i % 3 - 1), y).round(), Vector2(1, 3)), Color("ecd2ff", k * 0.9))


func _run_chips(delta: float) -> void:
	for chip: Dictionary in _chips:
		chip["age"] = float(chip["age"]) + delta
		var vel: Vector2 = chip["vel"] as Vector2
		vel.y += 300.0 * delta
		chip["vel"] = vel
		chip["pos"] = (chip["pos"] as Vector2) + vel * delta
	_chips = _chips.filter(func(c: Dictionary) -> bool: return float(c["age"]) < float(c["life"]))


# --- the burst -----------------------------------------------------------------------------------------------------


static func _hash(a: int, b: int) -> float:
	var h: int = (a * 374761393 + b * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## The top bursts into chunks cut out of the pillar's own picture (a jagged Voronoi of its pixels), a stump stays.
func _shatter(silent: bool = false) -> void:
	broken = true
	_armed = false
	_hurtbox.set_deferred("collision_layer", 0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|shatter" % [arena, index])
	var art: Image = ART.get_image()
	art.convert(Image.FORMAT_RGBA8)
	var glow: Image = GLOW.get_image()
	glow.convert(Image.FORMAT_RGBA8)
	var fx0: int = variant * FRAME.x
	var seeds: Array[Vector2] = []
	for i: int in CHUNKS:
		seeds.append(Vector2(rng.randf_range(6.0, 58.0), rng.randf_range(4.0, float(CUT_ROW) - 4.0)))
	var owner_of: PackedInt32Array = PackedInt32Array()
	owner_of.resize(FRAME.x * CUT_ROW)
	var lo: Array[Vector2i] = []
	var hi: Array[Vector2i] = []
	for i: int in CHUNKS:
		lo.append(Vector2i(999, 999))
		hi.append(Vector2i(-1, -1))
	for y: int in CUT_ROW:
		for x: int in FRAME.x:
			var best: int = -1
			if art.get_pixel(fx0 + x, y).a > 0.0:
				var best_d: float = 1e9
				for i: int in CHUNKS:
					var d: float = (Vector2(x, y) - seeds[i]).length_squared() + _hash(x, y) * 60.0
					if d < best_d:
						best_d = d
						best = i
				lo[best] = Vector2i(mini(lo[best].x, x), mini(lo[best].y, y))
				hi[best] = Vector2i(maxi(hi[best].x, x), maxi(hi[best].y, y))
			owner_of[y * FRAME.x + x] = best
	_chunks.clear()
	for i: int in CHUNKS:
		if hi[i].x < 0:
			continue
		var size: Vector2i = hi[i] - lo[i] + Vector2i.ONE
		var body_image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var glow_image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		for y: int in size.y:
			for x: int in size.x:
				var sx: int = lo[i].x + x
				var sy: int = lo[i].y + y
				if owner_of[sy * FRAME.x + sx] == i:
					body_image.set_pixel(x, y, art.get_pixel(fx0 + sx, sy))
					glow_image.set_pixel(x, y, glow.get_pixel(fx0 + sx, sy))
		var node: Node2D = Node2D.new()
		var body_sprite: Sprite2D = Sprite2D.new()
		body_sprite.texture = ImageTexture.create_from_image(body_image)
		node.add_child(body_sprite)
		var glow_sprite: Sprite2D = Sprite2D.new()
		glow_sprite.texture = ImageTexture.create_from_image(glow_image)
		glow_sprite.material = Unlit.material()
		node.add_child(glow_sprite)
		var centre: Vector2 = Vector2(lo[i]) + Vector2(size) * 0.5 - Vector2(FRAME.x * 0.5, FEET)
		node.position = centre
		_rubble.add_child(node)
		var out: float = clampf(centre.x / 20.0, -1.0, 1.0)
		var dir: Vector2 = (_fall_dir * 0.7 + Vector2(out, rng.randf_range(-0.4, 0.4))).normalized()
		var chunk: Dictionary = {
			"node": node, "ground": Vector2(centre.x, -rng.randf_range(0.0, 3.0)), "z": -centre.y, "vx": dir.x * rng.randf_range(24.0, 70.0), "vy": dir.y * rng.randf_range(10.0, 40.0),
			"vz": rng.randf_range(10.0, 80.0), "spin": rng.randf_range(-3.5, 3.5), "bounces": 0, "rest": false,
		}
		if silent: ## a joining peer: the rubble lies already, spread round the foot
			var spot: Vector2 = Vector2(dir.x * rng.randf_range(10.0, 36.0), dir.y * rng.randf_range(2.0, 12.0))
			node.position = spot.round()
			node.rotation = float(rng.randi() % 4) * PI / 2.0
			node.z_index = -1
			chunk["rest"] = true
		_chunks.append(chunk)
	# the stump: the lower rows of the picture with a ragged top edge
	var stump_top: int = CUT_ROW - 4
	var stump: Image = Image.create(FRAME.x, FRAME.y - stump_top, false, Image.FORMAT_RGBA8)
	var stump_glow: Image = Image.create(FRAME.x, FRAME.y - stump_top, false, Image.FORMAT_RGBA8)
	for y: int in range(stump_top, FRAME.y):
		for x: int in FRAME.x:
			var jag: int = 4 + int(_hash(x / 3, index) * 7.0) + int(sin(float(x) * 0.31 + float(index)) * 2.0)
			if y - stump_top < jag:
				continue
			stump.set_pixel(x, y - stump_top, art.get_pixel(fx0 + x, y))
			stump_glow.set_pixel(x, y - stump_top, glow.get_pixel(fx0 + x, y))
	for sprite: Sprite2D in [_sprite, _glow]:
		sprite.hframes = 1
		sprite.frame = 0
		sprite.centered = false
		sprite.offset = Vector2.ZERO
		sprite.position = Vector2.ZERO
	_sprite.texture = ImageTexture.create_from_image(stump)
	_glow.texture = ImageTexture.create_from_image(stump_glow)
	_stump_offset = Vector2(-FRAME.x * 0.5, -float(FEET - stump_top))
	_sprite.offset = _stump_offset
	_glow.offset = _stump_offset
	_light.base_energy = 0.15
	if silent:
		return
	ShockRing.burst(get_parent(), global_position, 54.0, 1.0)
	for i: int in 5:
		_chips.append({"pos": Vector2(randf_range(-12.0, 12.0), randf_range(-60.0, -20.0)), "vel": Vector2(randf_range(-60.0, 60.0), randf_range(-90.0, -30.0)), "age": 0.0, "life": randf_range(0.4, 0.8), "z": 0.0})
	shattered.emit()


var _stump_offset: Vector2 = Vector2.ZERO


func _run_chunks(delta: float) -> void:
	for chunk: Dictionary in _chunks:
		if bool(chunk["rest"]):
			continue
		var node: Node2D = chunk["node"] as Node2D
		var ground: Vector2 = chunk["ground"] as Vector2
		ground += Vector2(float(chunk["vx"]), float(chunk["vy"])) * delta
		var z: float = float(chunk["z"])
		var vz: float = float(chunk["vz"]) - GRAVITY * delta
		z += vz * delta
		if z <= 0.0:
			z = 0.0
			if int(chunk["bounces"]) < 2 and absf(vz) > 40.0:
				vz = -vz * 0.32
				chunk["vx"] = float(chunk["vx"]) * 0.55
				chunk["vy"] = float(chunk["vy"]) * 0.55
				chunk["bounces"] = int(chunk["bounces"]) + 1
				if int(chunk["bounces"]) == 1 and randf() < 0.6:
					ShockRing.burst(get_parent(), global_position + ground, 12.0, 0.25)
			else:
				chunk["rest"] = true
				vz = 0.0
		chunk["ground"] = ground
		chunk["z"] = z
		chunk["vz"] = vz
		node.position = Vector2(ground.x, ground.y - z).round()
		node.rotation += float(chunk["spin"]) * delta * (0.4 if bool(chunk["rest"]) else 1.0)
		if bool(chunk["rest"]):
			node.rotation = roundf(node.rotation / (PI / 2.0)) * (PI / 2.0) + float(int(ground.x) % 3 - 1) * 0.1
			node.z_index = -1


## A joining peer: the pillar is gone already, no show (rubble lies round the stump).
func break_silently() -> void:
	if broken:
		return
	_collapse = COLLAPSE_TIME
	_shatter(true)


## Whole again (the fight was reset): the picture, the footprint, nothing worn.
func restore() -> void:
	for child: Node in _rubble.get_children():
		child.queue_free()
	_chunks.clear()
	broken = false
	_armed = false
	_collapse = -1.0
	integrity = max_integrity
	_hurtbox.set_deferred("collision_layer", 0)
	for sprite: Sprite2D in [_sprite, _glow]:
		sprite.texture = ART if sprite == _sprite else GLOW
		sprite.hframes = maxi(sprite.texture.get_width() / FRAME.x, 1)
		sprite.frame = clampi(variant, 0, sprite.hframes - 1)
		sprite.centered = true
		sprite.offset = Vector2(0, -(FEET - FRAME.y / 2.0))
		sprite.position = Vector2.ZERO
	_light.base_energy = 0.45
	_light.glow_color = Color("9468ee")
	_fury = 0.0
	_fury_goal = 0.0
	_glow.material = Unlit.material()
	_sprite.material = null
	if _teal_glow != null:
		_teal_glow.visible = false
	if _flames != null:
		_flames.amount = 0.0
	_chips.clear()
