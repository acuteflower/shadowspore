class_name MineAtmosphere
extends Node2D
## What the local player hears and sees of the mine itself (docs/mine.md section 7): the zone's ambience (fades with the door), dust motes drifting through
## the air, and now and then a far rumble that shakes a little rock loose (a quiet camera shake, a puff of dust from above, no gameplay). Cosmetic:
## every peer runs its own.

const SOUNDS: String = "res://assets/audio/mine/"
const RUMBLE_EVERY: Vector2 = Vector2(50.0, 110.0)

var _dust: CPUParticles2D
var _falling: CPUParticles2D
var _ambient: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _creak: AudioStreamPlayer
var _zone: String = ""
var _next_rumble: float = 40.0
var _next_creak: float = 14.0
var _mines: MineManager
var _banner: MineBanner
var _bats: MineBats
var _shown_level: int = -1


func _ready() -> void:
	_mines = get_parent() as MineManager
	z_index = 4
	_banner = MineBanner.new()
	add_child(_banner)
	_bats = MineBats.new()
	add_child(_bats)
	_dust = _particles(46, 9.0, Vector2(330, 190), Color(0.78, 0.72, 0.9, 0.34))
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 5.0
	_dust.direction = Vector2(0.4, 0.3)
	_dust.spread = 180.0
	_falling = _particles(60, 2.2, Vector2(300, 6), Color(0.6, 0.55, 0.7, 0.8))
	_falling.one_shot = true
	_falling.explosiveness = 0.6
	_falling.gravity = Vector2(0, 90)
	_falling.initial_velocity_min = 4.0
	_falling.initial_velocity_max = 20.0
	_falling.direction = Vector2(0, 1)
	_falling.spread = 25.0
	_falling.emitting = false
	_ambient = _player(-80.0)
	_ambient.finished.connect(func() -> void: _ambient.play())
	_rumble = _player(-8.0)
	_rumble.stream = load(SOUNDS + "rumble.wav") as AudioStream
	_creak = _player(-17.0)


func _player(volume: float) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.volume_db = volume
	add_child(player)
	return player


func _particles(amount: int, life: float, extents: Vector2, color: Color) -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.0
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, Color(color, 0.0))
	ramp.add_point(0.2, color)
	ramp.add_point(0.8, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.material = Unlit.material()
	p.emitting = false
	add_child(p)
	return p


func _process(delta: float) -> void:
	var player: Player = _mines.local_player()
	var level: int = MineManager.level_at(player.global_position) if player != null else -1
	var inside: bool = level > 0
	if inside:
		global_position = player.global_position + Vector2(0, -20)
		var zone: String = String(MineManager.zone(level).get("id", ""))
		if zone != _zone:
			_zone = zone
			_ambient.stream = load(SOUNDS + "ambience_%s.wav" % zone) as AudioStream
			_ambient.play()
	if level != _shown_level:
		_shown_level = level
		if inside:
			_banner.show_level(level)
	_dust.emitting = inside
	_bats.active = inside and level <= 10
	_ambient.volume_db = move_toward(_ambient.volume_db, -7.0 if inside else -80.0, 60.0 * delta)
	if not inside and _ambient.playing and _ambient.volume_db <= -79.0:
		_ambient.stop()
		_zone = ""
	if not inside:
		return
	_next_rumble -= delta
	_next_creak -= delta
	if _next_rumble <= 0.0:
		_next_rumble = randf_range(RUMBLE_EVERY.x, RUMBLE_EVERY.y)
		_rumble.pitch_scale = randf_range(0.85, 1.1)
		_rumble.play()
		_falling.restart()
		_falling.emitting = true
		player.add_shake(1.6)
	if _next_creak <= 0.0:
		_next_creak = randf_range(9.0, 24.0)
		_creak.stream = load(SOUNDS + ("creak_a.wav" if randf() < 0.5 else "creak_b.wav")) as AudioStream
		_creak.pitch_scale = randf_range(0.8, 1.2)
		_creak.play()
