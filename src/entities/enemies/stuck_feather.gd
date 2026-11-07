class_name StuckFeather
extends Node2D
## One of the small void feathers Mornath throws in front of the arena's ways down (docs/boss_sky_cleaver.md): it sticks in the ground, solid, and together with its
## neighbours blocks the way. Cosmetic and solid on every peer; the boss frees them (`dissolve()`) when it dies or resets. The node stands on the tip of the feather,
## so it sorts with the people walking by.
## Cheap: no light of its own, only every third feather infects the ground and every second one raises dust when it lands, the shaft's flash is drawn only while
## it runs (a feather that does nothing costs one `modulate` a frame).

const GLINT_MIN: float = 1.4
const GLINT_MAX: float = 4.2
const PATCH_EVERY: float = 20.0

var length: int = 40
var width: int = 11
var variant: int = 0
var lean: float = 0.0
var solid: Vector2 = Vector2(14.0, 8.0) ## the footprint that blocks the way
var infect: bool = false ## darkens the ground round it
var burst: bool = false ## raises dust when it lands
var _swing: Node2D ## pivot at the tip, the feather shudders about it
var _body: Sprite2D
var _glow: Sprite2D
var _fx: Node2D
var _age: float = 0.0
var _since_land: float = 99.0
var _glint: float = -1.0
var _next_glint: float = 1.0
var _dissolve: float = -1.0
var _patch_in: float = 0.0
var _tip: Vector2 = Vector2.ZERO
var _collider: StaticBody2D
var _drawn: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Plants a feather with its tip at `at` (world); `landing` plays the impact (false = it was there already: a joining peer). `index` decides what it does besides standing.
static func plant(parent: Node, at: Vector2, p_length: int, p_width: int, p_variant: int, p_lean: float, p_solid: Vector2, landing: bool, index: int = 0) -> StuckFeather:
	var feather: StuckFeather = StuckFeather.new()
	feather.length = p_length
	feather.width = p_width
	feather.variant = p_variant
	feather.lean = p_lean
	feather.solid = p_solid
	feather.infect = index % 3 == 0
	feather.burst = index % 2 == 0
	feather.position = at
	parent.add_child(feather)
	if landing:
		feather.land()
	return feather


func _ready() -> void:
	_rng.seed = hash(position) + variant
	_next_glint = _rng.randf_range(0.5, GLINT_MAX)
	var art: Dictionary = VoidFeather.art(length, width, PI / 2.0 + lean, variant)
	_tip = art["tip"] as Vector2
	_swing = Node2D.new()
	add_child(_swing)
	_body = Sprite2D.new()
	_body.texture = art["body"] as Texture2D
	_body.centered = false
	_body.position = -_tip
	_swing.add_child(_body)
	_glow = Sprite2D.new()
	_glow.texture = art["glow"] as Texture2D
	_glow.centered = false
	_glow.position = -_tip
	var add: CanvasItemMaterial = CanvasItemMaterial.new()
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_swing.add_child(_glow)
	_fx = Node2D.new()
	_fx.material = add
	add_child(_fx)
	_fx.draw.connect(_draw_fx)
	_collider = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = solid
	shape.shape = box
	shape.position = Vector2(0.0, -solid.y * 0.5)
	_collider.add_child(shape)
	add_child(_collider)
	_patch_in = 0.2 if infect else 1e9


## The impact: the feather shudders about its tip, dust flies (on every second one), the shaft flashes.
func land() -> void:
	_since_land = 0.0
	_glint = 0.0
	if burst:
		ShockRing.burst(get_parent(), global_position, 22.0, 0.45)


func _process(delta: float) -> void:
	_age += delta
	_since_land += delta
	_patch_in -= delta
	if _patch_in <= 0.0 and _dissolve < 0.0:
		_patch_in = PATCH_EVERY
		ShadowPatch.spawn(get_tree().current_scene, global_position + Vector2(0, -1), Vector2i(30, 20), PATCH_EVERY + 4.0, 6.0, 5)
	_next_glint -= delta
	if _next_glint <= 0.0 and _dissolve < 0.0:
		_next_glint = _rng.randf_range(GLINT_MIN, GLINT_MAX)
		_glint = 0.0
	if _glint >= 0.0:
		_glint += delta
		if _glint > 0.3:
			_glint = -1.0
	# the shudder after the impact: a damped swing about the tip
	_swing.rotation = 0.16 * sin(_since_land * 38.0) * exp(-_since_land * 6.0) if _since_land < 1.0 else 0.0
	var alpha: float = 1.0
	if _dissolve >= 0.0:
		_dissolve += delta
		var k: float = _dissolve / 0.9
		var blink: bool = fmod(_dissolve * 24.0, 2.0) < 1.0 and k > 0.3
		alpha = 0.0 if blink else 1.0 - k
		if k >= 1.0:
			queue_free()
			return
	modulate.a = alpha
	_glow.modulate.a = (0.62 + 0.28 * sin(_age * 2.1 + position.x)) if _since_land > 0.4 else 1.0
	var flashing: bool = _glint >= 0.0 or _since_land < 0.3
	if flashing or _drawn:
		_fx.queue_redraw()
	_drawn = flashing


## The flash along the shaft ("blitzen"): a white-violet line from the tip to the quill, flickering, and a ring in the ground.
func _draw_fx() -> void:
	var k: float = _glint
	var strength: float = 0.0
	if k >= 0.0:
		strength = (1.0 if fmod(k * 26.0, 2.0) < 1.4 else 0.35) * (1.0 - k / 0.3)
	if _since_land < 0.3:
		strength = maxf(strength, 1.0 - _since_land / 0.3)
	if strength <= 0.0:
		return
	var top: float = float(length) * cos(lean) * 0.95
	var from: Vector2 = Vector2.ZERO
	for i: int in range(1, 7):
		var along: float = float(i) / 6.0
		var jitter: float = 0.0 if i % 2 == 0 else (1.0 if int(_age * 30.0) % 2 == 0 else -1.0)
		var to: Vector2 = Vector2(-sin(lean) * top * along + jitter, -top * along).round()
		_fx.draw_line(from, to, Color(Color("ecd2ff"), strength * (0.9 - 0.5 * along)), 1.0)
		from = to
	var ring: float = 5.0 + 8.0 * clampf(k / 0.3, 0.0, 1.0) if k >= 0.0 else 5.0
	for i: int in 10:
		var p: Vector2 = Vector2.from_angle(TAU * float(i) / 10.0) * Vector2(ring, ring * 0.55)
		_fx.draw_rect(Rect2(p.round(), Vector2.ONE), Color(Color("a98af0"), strength * 0.7))


## It crumbles away (the boss died, or the fight was reset); it stops blocking at once.
func dissolve() -> void:
	if _dissolve >= 0.0:
		return
	_dissolve = 0.0
	if _collider != null:
		_collider.queue_free()
		_collider = null
