class_name WeatherAudio
extends Node
## The weather you hear (docs/wetter_konzept.md section 7.4; placeholders from tools/audio_weather.py). Three rain beds (light / mid / heavy) are crossfaded by the
## rain that falls on the ground under the camera, a roof bed takes over indoors, two wind beds follow the wind, and thunder plays when the sound reaches us
## (WeatherManager.thunder_rolled, delayed by the distance of the flash). Everything runs through the bus "Weather" whose low-pass filter muffles it indoors
## (about 700 Hz) and under a dense crown (about 3 kHz). `follow` is called every frame by `DayNight`.

const BUS: StringName = &"Weather"
const DIR: String = "res://assets/audio/weather/"

var _beds: Dictionary = {}
var _thunder: Array[AudioStream] = []
var _filter: AudioEffectLowPassFilter
var _cut: float = 20500.0
var _manager: WeatherManager
var _cfg: Dictionary = {}
var levels: Dictionary = {} ## what is playing right now, 0..1 per bed (readable for tests)


func _ready() -> void:
	name = "WeatherAudio"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_cfg = (WeatherRules.cfg().get("audio", {}) as Dictionary)
	_ensure_bus()
	for id: String in ["rain_light", "rain_mid", "rain_heavy", "rain_roof", "wind_light", "wind_strong"]:
		_beds[id] = _make_bed(id)
	for id: String in ["thunder_close", "thunder_mid", "thunder_far"]:
		_thunder.append(load(DIR + id + ".wav") as AudioStream)


func bind(manager: WeatherManager) -> void:
	_manager = manager
	manager.thunder_rolled.connect(_on_thunder)


func _ensure_bus() -> void:
	var idx: int = AudioServer.get_bus_index(BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
		AudioServer.set_bus_send(idx, &"Master")
	_filter = null
	for e: int in AudioServer.get_bus_effect_count(idx):
		var fx: AudioEffect = AudioServer.get_bus_effect(idx, e)
		if fx is AudioEffectLowPassFilter:
			_filter = fx as AudioEffectLowPassFilter
	if _filter == null:
		_filter = AudioEffectLowPassFilter.new()
		_filter.cutoff_hz = 20500.0
		AudioServer.add_bus_effect(idx, _filter)


func _make_bed(id: String) -> AudioStreamPlayer:
	var stream: AudioStreamWAV = (load(DIR + id + ".wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / (2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1)
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = BUS
	p.volume_db = -80.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	var w: WeatherManager = _manager if _manager != null else WeatherManager.current
	if w == null:
		return
	var rain: float = clampf(w.local_rain, 0.0, 1.0)
	var canopy: float = w.canopy_at(w.focus)
	var indoors: bool = w.indoors
	var outdoor_rain: float = 0.0 if indoors else rain
	var light: float = (1.0 - smoothstep(0.12, 0.5, outdoor_rain)) * smoothstep(0.02, 0.12, outdoor_rain)
	var mid: float = smoothstep(0.12, 0.5, outdoor_rain) * (1.0 - smoothstep(0.55, 0.9, outdoor_rain))
	var heavy: float = smoothstep(0.55, 0.9, outdoor_rain)
	var shelter: float = 1.0 - 0.35 * canopy ## under the crowns it is quieter and duller
	var roof: float = clampf(w.rain * 1.2, 0.0, 1.0) * smoothstep(0.03, 0.12, w.rain) if indoors else 0.0
	var wind_amount: float = clampf(w.wind * (0.35 if indoors else 1.0), 0.0, 1.0)
	levels = {
		"rain_light": light * shelter, "rain_mid": mid * shelter, "rain_heavy": heavy * shelter, "rain_roof": roof,
		"wind_light": smoothstep(0.1, 0.5, wind_amount) * (1.0 - smoothstep(0.7, 1.0, wind_amount) * 0.6),
		"wind_strong": smoothstep(0.55, 1.0, wind_amount),
	}
	var db: Dictionary = {"rain_light": float(_cfg.get("rain_db", -14.0)), "rain_mid": float(_cfg.get("rain_db", -14.0)), "rain_heavy": float(_cfg.get("rain_db", -14.0)) + 1.0,
		"rain_roof": float(_cfg.get("roof_db", -12.0)), "wind_light": float(_cfg.get("wind_db", -16.0)), "wind_strong": float(_cfg.get("wind_db", -16.0)) + 2.0}
	for id: String in _beds:
		var p: AudioStreamPlayer = _beds[id] as AudioStreamPlayer
		var a: float = float(levels[id])
		var want: float = float(db[id]) + linear_to_db(maxf(a, 0.0001)) if a > 0.01 else -80.0
		p.volume_db = move_toward(p.volume_db, want, 30.0 * delta)
		if want > -79.0 and not p.playing:
			p.play()
		elif p.playing and p.volume_db <= -79.0:
			p.stop()
	var cut_target: float = 700.0 if indoors else lerpf(20500.0, 3000.0, canopy)
	_cut = lerpf(_cut, cut_target, 1.0 - exp(-delta / 0.25))
	if _filter != null:
		_filter.cutoff_hz = clampf(_cut, 300.0, 20500.0)


func _on_thunder(far: float) -> void:
	if _thunder.is_empty():
		return
	var which: int = 2 if far > 0.66 else (1 if far > 0.33 else 0)
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = _thunder[which]
	p.bus = BUS
	p.volume_db = float(_cfg.get("thunder_db", -6.0)) - far * 9.0
	p.pitch_scale = randf_range(0.92, 1.06)
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()
