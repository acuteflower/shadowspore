class_name WoundBorder
extends ColorRect
## The permanent red border of the wounded state (`Player.wounded`): veins creep in from the screen edges, crawl, and swell with a heartbeat
## (also heard, quietly). It unrolls with a jolt when she becomes wounded and withdraws when she heals. See assets/shaders/wound_border.gdshader.

const HEARTBEAT: AudioStream = preload("res://assets/audio/intro/heartbeat.wav")
const PERIOD: float = 1.15 ## seconds between heartbeats
const GROW_SECONDS: float = 1.4
const WITHDRAW_SECONDS: float = 2.0

var _material: ShaderMaterial
var _grow: float = 0.0
var _on: bool = false
var _time: float = 0.0
var _flash: float = 0.0
var _last_phase: float = 0.0
var _sound: AudioStreamPlayer


func bind(player: Node) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://assets/shaders/wound_border.gdshader")
	material = _material
	_sound = AudioStreamPlayer.new()
	_sound.stream = HEARTBEAT
	_sound.volume_db = -9.0
	add_child(_sound)
	player.wounded_changed.connect(func(_on: bool) -> void: _set_wounded(bool(player.wounded) and not bool(player.bandaged)))
	player.bandaged_changed.connect(func(_on: bool) -> void: _set_wounded(bool(player.wounded) and not bool(player.bandaged)))
	_set_wounded(bool(player.wounded) and not bool(player.bandaged), true)


func _set_wounded(on: bool, silent: bool = false) -> void:
	if on and not _on and not silent:
		_flash = 1.0
	_on = on


func _process(delta: float) -> void:
	_grow = move_toward(_grow, 1.0 if _on else 0.0, delta / (GROW_SECONDS if _on else WITHDRAW_SECONDS))
	_flash = move_toward(_flash, 0.0, delta * 1.6)
	if _grow <= 0.0 and _flash <= 0.0:
		visible = false
		return
	visible = true
	_time += delta
	var phase: float = fposmod(_time, PERIOD)
	var lub: float = exp(-phase * 9.0)
	var dub: float = 0.7 * exp(-(phase - 0.28) * 11.0) if phase > 0.28 else 0.0
	if phase < _last_phase and _on and _grow > 0.4 and not get_tree().paused:
		_sound.play()
	_last_phase = phase
	var eased: float = _grow * _grow * (3.0 - 2.0 * _grow)
	_material.set_shader_parameter("grow", eased)
	_material.set_shader_parameter("beat", maxf(lub, dub) * eased)
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("flash", _flash)
