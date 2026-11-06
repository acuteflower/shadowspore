class_name DayAmbience
extends Node
## Open-air sound beds that follow the sky: birds, leaves and bees under the sun, crickets and a far hum at night.
## Quiet placeholders (tools/audio_daynight.py). `follow()` is called every frame by `DayNight`.

const DAY: AudioStream = preload("res://assets/audio/ambience/day.wav")
const NIGHT: AudioStream = preload("res://assets/audio/ambience/night.wav")
const LEVEL_DB: float = -17.0

var _day: AudioStreamPlayer
var _night: AudioStreamPlayer


func _ready() -> void:
	_day = _player(DAY)
	_night = _player(NIGHT)


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	p.finished.connect(func() -> void: p.play()) ## the beds loop
	add_child(p)
	return p


func follow(sun: float, night: float, indoors: bool, delta: float) -> void:
	_fade(_day, 0.0 if indoors else sun, delta)
	_fade(_night, 0.0 if indoors else night, delta)


func _fade(p: AudioStreamPlayer, amount: float, delta: float) -> void:
	var want: float = LEVEL_DB + linear_to_db(maxf(amount, 0.0001)) if amount > 0.01 else -80.0
	p.volume_db = move_toward(p.volume_db, want, 40.0 * delta)
	if want > -79.0 and not p.playing:
		p.play()
	elif p.playing and p.volume_db <= -79.0:
		p.stop()
