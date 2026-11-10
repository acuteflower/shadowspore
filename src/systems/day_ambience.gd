class_name DayAmbience
extends Node
## Open-air sound beds that follow the sky: birds, leaves and bees under the sun, crickets and a far hum at night.
## Quiet placeholders (tools/audio_daynight.py). `follow()` is called every frame by `DayNight`.

const DAY: AudioStream = preload("res://assets/audio/ambience/day.wav")
const NIGHT: AudioStream = preload("res://assets/audio/ambience/night.wav")
const LEVEL_DB: float = -17.0

var _day: AudioStreamPlayer
var _night: AudioStreamPlayer
var _wind_day: AudioStreamPlayer ## the Higgsfield beds (assets/audio/sfx), layered under the older ones
var _wind_night: AudioStreamPlayer
var _crickets: AudioStreamPlayer


func _ready() -> void:
	_day = _player(DAY)
	_night = _player(NIGHT)
	_wind_day = _bed("wind_day_loop")
	_wind_night = _bed("wind_night_loop")
	_crickets = _bed("cricket_night")


func _bed(id: String) -> AudioStreamPlayer:
	if not Sfx.has(id):
		return null
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = Sfx.loop(id)
	p.volume_db = -80.0
	add_child(p)
	return p


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
	if _wind_day != null:
		_fade(_wind_day, 0.0 if indoors else sun, delta, -20.0)
	if _wind_night != null:
		_fade(_wind_night, 0.0 if indoors else night, delta, -21.0)
	if _crickets != null:
		_fade(_crickets, 0.0 if indoors else night, delta, -24.0)


func _fade(p: AudioStreamPlayer, amount: float, delta: float, level: float = LEVEL_DB) -> void:
	var want: float = level + linear_to_db(maxf(amount, 0.0001)) if amount > 0.01 else -80.0
	p.volume_db = move_toward(p.volume_db, want, 40.0 * delta)
	if want > -79.0 and not p.playing:
		p.play()
	elif p.playing and p.volume_db <= -79.0:
		p.stop()
