class_name ManholeCover
extends Node2D
## The old cast-iron manhole cover on the ground where the story starts (art: tools/art_manhole.py): a collar of cut stones round a dark
## shaft, and the lid as a sprite of its own that the intro slides aside (`set_open`: 0 closed over the shaft, 1 pushed off to the north west,
## where it stays). Flat, so you walk over it. The lid's violet crack and bloom, the glimmer in the shaft and the luminous moss glow (dim by day,
## bright at night) and a cold teal light seeps out of the shaft at night. Placed by `WorldLevel._add_ground_decals` from data/ground_baked.json.

const BODY: Texture2D = preload("res://assets/props/manhole.png")
const BODY_GLOW: Texture2D = preload("res://assets/props/manhole_glow.png")
const LID: Texture2D = preload("res://assets/props/manhole_lid.png")
const LID_GLOW: Texture2D = preload("res://assets/props/manhole_lid_glow.png")
const CENTER: Vector2 = Vector2(32, 26) ## the cover's middle in its pictures
const OPEN_OFFSET: Vector2 = Vector2(-13, -9) ## px the lid lies from the shaft when it is pushed aside
const GLOW_BY_DAY: float = 0.22
const DUST_COLOR: Color = Color(0.78, 0.72, 0.84, 0.85)

var _lid: Sprite2D
var _glows: Array[Sprite2D] = []
var _open: float = 1.0
var _jolt: Vector2 = Vector2.ZERO


func _ready() -> void:
	_sprite(BODY, BODY_GLOW, -8)
	_lid = _sprite(LID, LID_GLOW, -7) ## the lid's position is its offset from the shaft
	var light: NightLight = NightLight.new()
	light.position = Vector2(4, 5)
	light.radius = 34
	light.squash = 0.6
	light.base_energy = 0.55
	light.glow_color = Color("5fd9d0")
	add_child(light)
	add_to_group("night_lights") ## DayNight tells every night light how dark it is
	set_night(TimeManager.night_amount())
	_place_lid()


func _sprite(texture: Texture2D, glow_texture: Texture2D, z: int) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = -CENTER
	sprite.z_index = z
	add_child(sprite)
	var glow: Sprite2D = Sprite2D.new()
	glow.texture = glow_texture
	glow.centered = false
	glow.offset = -CENTER
	glow.material = Unlit.material()
	sprite.add_child(glow)
	_glows.append(glow)
	return sprite


func set_night(amount: float) -> void:
	for glow: Sprite2D in _glows:
		glow.modulate.a = lerpf(GLOW_BY_DAY, 1.0, amount)


## 0 = the lid lies over the shaft, 1 = pushed aside.
func set_open(amount: float) -> void:
	_open = amount
	_place_lid()


## A short extra offset of the lid (a knock from below lifts it, the scraping shakes it).
func set_jolt(offset: Vector2) -> void:
	_jolt = offset
	_place_lid()


func _place_lid() -> void:
	if _lid != null:
		_lid.position = (OPEN_OFFSET * _open + _jolt).round()


## A puff of dust (it sifts out of the joint, rises a little and thins out). `at` is relative to the cover's middle.
func dust(at: Vector2, count: int, spread: float = 10.0) -> void:
	var puff: CPUParticles2D = CPUParticles2D.new()
	puff.position = at
	puff.z_index = -6
	puff.one_shot = true
	puff.explosiveness = 0.85
	puff.amount = count
	puff.lifetime = 1.1
	puff.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = spread
	puff.direction = Vector2(0, -1)
	puff.spread = 70.0
	puff.initial_velocity_min = 4.0
	puff.initial_velocity_max = 16.0
	puff.gravity = Vector2(0, -4)
	puff.damping_min = 6.0
	puff.damping_max = 10.0
	puff.scale_amount_min = 1.0
	puff.scale_amount_max = 2.0
	puff.color = DUST_COLOR
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	puff.color_ramp = fade
	puff.emitting = true
	add_child(puff)
	get_tree().create_timer(2.0).timeout.connect(puff.queue_free)
