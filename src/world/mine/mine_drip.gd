class_name MineDrip
extends Node2D
## Water dripping from the roof into a puddle: a drop falls, rings spread on the water, a quiet plink. Cosmetic, every peer runs its own.

const SOUNDS: Array[AudioStream] = [preload("res://assets/audio/mine/drip_a.wav"), preload("res://assets/audio/mine/drip_b.wav")]
const HEIGHT: float = 38.0

var every: float = 4.0
var _wait: float = 0.0
var _fall: float = -1.0 ## seconds into the fall, -1 = no drop
var _ring: float = -1.0
var _player: AudioStreamPlayer2D


func _ready() -> void:
	z_index = -4
	_wait = randf_range(0.5, every)
	_player = AudioStreamPlayer2D.new()
	_player.volume_db = -20.0
	_player.max_distance = 230.0
	add_child(_player)


func _process(delta: float) -> void:
	if _fall < 0.0 and _ring < 0.0:
		_wait -= delta
		if _wait > 0.0:
			return
		_fall = 0.0
	if _fall >= 0.0:
		_fall += delta
		if _fall >= 0.42:
			_fall = -1.0
			_ring = 0.0
			_wait = every * randf_range(0.8, 1.3)
			_player.stream = SOUNDS[randi() % SOUNDS.size()]
			_player.pitch_scale = randf_range(0.85, 1.2)
			_player.play()
	if _ring >= 0.0:
		_ring += delta
		if _ring > 0.9:
			_ring = -1.0
	queue_redraw()


func _draw() -> void:
	if _fall >= 0.0:
		var t: float = _fall / 0.42
		var y: float = -HEIGHT + HEIGHT * t * t
		draw_rect(Rect2(-0.5, snappedf(y, 1.0), 1.0, 3.0), Color(0.7, 0.85, 1.0, 0.9))
	if _ring >= 0.0:
		var t: float = _ring / 0.9
		for k: int in 2:
			var r: float = (t - k * 0.18) * 9.0
			if r > 0.5:
				_ellipse(r, Color(0.6, 0.78, 1.0, (1.0 - t) * 0.8))


func _ellipse(r: float, color: Color) -> void:
	var previous: Vector2 = Vector2(r, 0.0)
	for i: int in range(1, 13):
		var a: float = float(i) / 12.0 * TAU
		var p: Vector2 = Vector2(cos(a) * r, sin(a) * r * 0.45)
		draw_line(previous.round(), p.round(), color, 1.0)
		previous = p
