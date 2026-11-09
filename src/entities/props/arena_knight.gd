class_name ArenaKnight
extends Interactable
## The dead knight in Valdric's wine-red armour who sits against the east pillar of the boss arena while the quest `mornath` runs (`ArenaStory` shows and hides him,
## per local player: quests are local). E during the step `inspect` starts the search (`MornathInspectScene`). When Mornath has fallen he dissolves: the black in
## him lets go, motes rise, the plate fades. Art `py -3 tools/art_fallen_knight.py --pillar` -> assets/props/arena_knight.png (+ `_glow`, only the emissive pixels).

const ART: Texture2D = preload("res://assets/props/arena_knight.png")
const GLOW: Texture2D = preload("res://assets/props/arena_knight_glow.png")
const BODY: Vector2 = Vector2(2, -2) ## where he sits in the picture (feet at the node)
const CLINK: AudioStream = preload("res://assets/audio/intro/lid_scrape.wav")
const DISSOLVE_SECONDS: float = 4.2

var story: ArenaStory
var inspectable: bool = false
var shown: bool = false

var _sprite: Sprite2D
var _glow: Sprite2D
var _light: NightLight
var _motes: CPUParticles2D
var _body: StaticBody2D
var _time: float = 0.0
var _dissolve: float = -1.0 ## seconds into the dissolve (< 0: not dissolving)
var _flare: float = 0.0 ## 0..1: the veins flare (the cry of the boss, the search)


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = ART
	_sprite.offset = Vector2(0, -15)
	add_child(_sprite)
	_glow = Sprite2D.new()
	_glow.texture = GLOW
	_glow.offset = _sprite.offset
	_glow.material = Unlit.material()
	add_child(_glow)
	_light = NightLight.new()
	_light.position = Vector2(2, -6)
	_light.radius = 58
	_light.base_energy = 0.5
	_light.glow_color = Color("a65cf0")
	add_child(_light)
	_motes = CPUParticles2D.new()
	_motes.position = Vector2(2, -4)
	_motes.amount = 9
	_motes.lifetime = 3.2
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(22, 4)
	_motes.direction = Vector2(0, -1)
	_motes.spread = 20.0
	_motes.initial_velocity_min = 3.0
	_motes.initial_velocity_max = 8.0
	_motes.gravity = Vector2.ZERO
	_motes.color = Color("e45cf0")
	var fade: Gradient = Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.25, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	_motes.color_ramp = fade
	_motes.material = Unlit.material()
	add_child(_motes)
	_body = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(20, 9)
	shape.shape = box
	shape.position = Vector2(3, -2)
	_body.add_child(shape)
	add_child(_body)
	_apply(false)


## Quest on / off for the local player. A dissolve that is running finishes first.
func set_present(on: bool) -> void:
	if _dissolve >= 0.0 or on == shown:
		return
	shown = on
	_apply(on)


func _apply(on: bool) -> void:
	visible = on
	set_process(on)
	_light.visible = on
	_motes.emitting = on
	_body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	_body.collision_layer = 1 if on else 0
	if on:
		_sprite.modulate = Color.WHITE
		_sprite.material = null


func prompt() -> String:
	return "UNTERSUCHEN" if shown and inspectable and _dissolve < 0.0 else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position + BODY) - 12.0


func prompt_position() -> Vector2:
	return Vector2(2, -36)


func interact(player: Player) -> void:
	if story != null:
		story.inspect(player)


## Where she stands to search him.
func stand_point() -> Vector2:
	return global_position + Vector2(-2, 17)


func clink() -> void:
	var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	sound.stream = CLINK
	sound.volume_db = -16
	sound.pitch_scale = 1.45
	sound.max_distance = 320
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
	flare(0.7)


## The black in him stirs (the search, the cry from above).
func flare(amount: float) -> void:
	_flare = maxf(_flare, amount)


## Mornath has fallen: the void lets go of him.
func dissolve() -> void:
	if not shown or _dissolve >= 0.0:
		return
	_dissolve = 0.0
	_motes.amount = 40
	_motes.initial_velocity_max = 26.0
	_motes.lifetime = 2.4
	_body.collision_layer = 0
	flare(1.0)


func _process(delta: float) -> void:
	_time += delta
	_flare = maxf(0.0, _flare - delta * 0.9)
	var night: float = TimeManager.night_amount()
	var breath: float = 0.72 + 0.28 * sin(_time * 1.5) * sin(_time * 0.7 + 1.0)
	var alpha: float = lerpf(0.45, 1.0, night) * breath + _flare * 0.6
	if _dissolve >= 0.0:
		_dissolve += delta
		var t: float = clampf(_dissolve / DISSOLVE_SECONDS, 0.0, 1.0)
		# the glow flares first and dies; the plate fades from the feet up (whole pixel rows)
		alpha *= (1.0 + 1.6 * sin(minf(t * 3.0, 1.0) * PI)) * (1.0 - smoothstep(0.35, 0.9, t))
		_sprite.modulate.a = 1.0 - smoothstep(0.3, 1.0, t)
		_light.base_energy = 0.5 * (1.0 - t)
		if _dissolve >= DISSOLVE_SECONDS:
			_dissolve = -1.0
			shown = false
			_motes.amount = 9
			_motes.initial_velocity_max = 8.0
			_motes.lifetime = 3.2
			_apply(false)
			_light.base_energy = 0.5
			return
	_glow.modulate.a = clampf(alpha, 0.0, 1.6)
