class_name RavenOmen
extends Node2D
## The ravens of the Rabenbaum during Morwenna's fight (docs/enemies/boss_mora.md, step 3): a ring of ravens circling above the hollow that gets lower,
## faster and wilder with every phase (`set_mood`). Their one job in the fight is the TELL: when she calls clones, swaps or splits (`shriek`), the
## whole flock gathers screaming right above the REAL witch, the only sign besides her shadow that tells her from her phantoms. `panic` scatters them
## (the scream of the swarm), `dive` sends one raven low along a lane (the lane itself is the fight's warning; the bird only shows it).
## Purely cosmetic, every peer on its own: the moments come from the fight's reliable RPCs, the circling is a smooth function of time.
## Art: the raven builds (3-5) of the shared corvid sheet (assets/wildlife/corvid.png, 48x48 frames, feet (24, 35), flight columns 30-37).

const SHEET: Texture2D = preload("res://assets/wildlife/corvid.png")
const FRAME: Vector2 = Vector2(48, 48)
const FEET: Vector2 = Vector2(24, 35)
const FLY_COL: int = 30
const FLY_FRAMES: int = 8
const CALLS: PackedStringArray = ["res://assets/audio/wildlife/raven_0.wav", "res://assets/audio/wildlife/raven_1.wav", "res://assets/audio/wildlife/crow_0.wav"]

var fight: MirrorWitchFight
var mood: int = 0 ## the phase (0..2); -1 = gone (released, dead)
var _home: Vector2 = Vector2.ZERO
var _clock: float = 0.0
var _birds: Array[Dictionary] = []
var _divers: Array[Dictionary] = []
var _shriek_left: float = 0.0
var _panic_left: float = 0.0
var _call_left: float = 0.0
var _gone: float = 0.0
var _voices: Array[AudioStreamPlayer2D] = []
var _voice_i: int = 0
var _streams: Array[AudioStream] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(p_fight: MirrorWitchFight, tree_pos: Vector2) -> void:
	fight = p_fight
	_home = tree_pos
	top_level = true
	global_position = Vector2.ZERO
	z_index = 7
	_rng.seed = 7741
	for i: int in 16:
		_birds.append({"a": _rng.randf() * TAU, "r": _rng.randf_range(0.85, 1.15), "h": _rng.randf_range(0.9, 1.1), "w": _rng.randf_range(0.85, 1.2),
			"build": 3 + i % 3, "flap": _rng.randf() * 8.0, "pos": tree_pos + Vector2.from_angle(_rng.randf() * TAU) * 120.0, "z": 150.0, "vel": Vector2.ZERO, "show": 0.0})
	if DisplayServer.get_name() != "headless":
		for path: String in CALLS:
			if ResourceLoader.exists(path):
				_streams.append(load(path) as AudioStream)
		for i: int in 3:
			var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
			voice.max_distance = 820.0
			voice.attenuation = 1.3
			add_child(voice)
			_voices.append(voice)


func set_mood(value: int) -> void:
	mood = value


## The flock gathers screaming above the real witch for `seconds`.
func shriek(seconds: float) -> void:
	_shriek_left = maxf(_shriek_left, seconds)
	_call_left = 0.0


## The swarm panics for `seconds`: wide, fast, ragged circles, a storm of calls.
func panic(seconds: float) -> void:
	_panic_left = maxf(_panic_left, seconds)
	_call_left = 0.0


## One raven drops out of the ring and sweeps low from `a` to `b`; it is on the ground line at `warn` seconds from now (when the lane hits).
func dive(a: Vector2, b: Vector2, warn: float) -> void:
	_divers.append({"a": a, "b": b, "t": 0.0, "hit": warn, "build": 3 + _rng.randi() % 3, "flap": _rng.randf() * 8.0})


func _count() -> int:
	if mood < 0:
		return 0
	return [8, 11, 16][clampi(mood, 0, 2)]


func _process(delta: float) -> void:
	_clock += delta
	_shriek_left = maxf(_shriek_left - delta, 0.0)
	_panic_left = maxf(_panic_left - delta, 0.0)
	_gone = move_toward(_gone, 1.0 if mood < 0 else 0.0, delta * 0.35)
	var real: Vector2 = fight.real_position() if is_instance_valid(fight) else _home
	var count: int = _count()
	var spin: float = (0.42 + 0.16 * float(maxi(mood, 0))) * (2.4 if _panic_left > 0.0 else 1.0)
	for i: int in _birds.size():
		var bird: Dictionary = _birds[i]
		var active: bool = i < count or (mood < 0 and float(bird["show"]) > 0.0)
		bird["show"] = move_toward(float(bird["show"]), 1.0 if i < count and mood >= 0 else 0.0, delta * 0.8)
		if not active and float(bird["show"]) <= 0.0:
			continue
		bird["a"] = float(bird["a"]) + delta * spin * float(bird["w"])
		var a: float = float(bird["a"])
		var want: Vector2
		var want_z: float
		if _shriek_left > 0.0 and mood >= 0: ## the tell: a tight screaming knot above the real one
			want = real + Vector2.from_angle(a * 2.2) * Vector2(26.0, 16.0) * float(bird["r"])
			want_z = 74.0 + 10.0 * sin(a * 3.0 + float(i))
		elif _panic_left > 0.0:
			var wobble: float = sin(_clock * 3.1 + float(i) * 1.7)
			want = _home + Vector2(0, 60) + Vector2.from_angle(a + wobble) * Vector2(250.0, 170.0) * float(bird["r"]) * (0.7 + 0.4 * wobble)
			want_z = 40.0 + 70.0 * absf(sin(_clock * 1.7 + float(i)))
		elif mood < 0: ## released (or the fight is over): they drift off and fade
			want = _home + Vector2.from_angle(a) * 420.0
			want_z = 200.0
		else:
			want = _home + Vector2(0, 50) + Vector2.from_angle(a) * Vector2(190.0 - 26.0 * float(mood), 128.0 - 16.0 * float(mood)) * float(bird["r"])
			want_z = (150.0 - 30.0 * float(mood)) * float(bird["h"])
		var pos: Vector2 = bird["pos"] as Vector2
		var next: Vector2 = pos.lerp(want, 1.0 - exp(-(3.2 if _shriek_left > 0.0 else 1.6) * delta))
		bird["vel"] = (next - pos) / maxf(delta, 0.0001)
		bird["pos"] = next
		bird["z"] = lerpf(float(bird["z"]), want_z, 1.0 - exp(-2.0 * delta))
	for d: Dictionary in _divers:
		d["t"] = float(d["t"]) + delta
	_divers = _divers.filter(func(d: Dictionary) -> bool: return float(d["t"]) < float(d["hit"]) + 0.7)
	_call_left -= delta
	if _call_left <= 0.0 and count > 0 and _gone < 0.5:
		var excited: bool = _shriek_left > 0.0 or _panic_left > 0.0
		_call_left = _rng.randf_range(0.12, 0.3) if excited else _rng.randf_range(1.8, 4.5) / (1.0 + float(mood))
		_call(real if _shriek_left > 0.0 else _home + Vector2(0, -60), excited)
	queue_redraw()


func _call(at: Vector2, loud: bool) -> void:
	if _voices.is_empty() or _streams.is_empty():
		return
	var voice: AudioStreamPlayer2D = _voices[_voice_i % _voices.size()]
	_voice_i += 1
	voice.stream = _streams[_rng.randi() % _streams.size()]
	voice.global_position = at + Vector2(_rng.randf_range(-30.0, 30.0), -60.0)
	voice.volume_db = -4.0 if loud else -13.0
	voice.pitch_scale = _rng.randf_range(0.82, 1.08) if loud else _rng.randf_range(0.9, 1.05)
	voice.play()


func _sector(v: Vector2) -> int:
	return posmod(roundi(v.angle() / (PI / 4.0)), 8) if v.length() > 2.0 else 2


func _bird(at: Vector2, height: float, vel: Vector2, build: int, flap: float, alpha: float, fast: float) -> void:
	if alpha <= 0.01:
		return
	var ground: Vector2 = at.round()
	var shadow: float = clampf(1.0 - height / 220.0, 0.25, 0.9)
	draw_rect(Rect2(ground + Vector2(-3, 0), Vector2(7, 2)), Color(0, 0, 0, 0.22 * shadow * alpha))
	var col: int = FLY_COL + int(floorf(_clock * 12.0 * fast + flap)) % FLY_FRAMES
	var row: int = build * 8 + _sector(vel)
	var src: Rect2 = Rect2(Vector2(float(col), float(row)) * FRAME, FRAME)
	draw_texture_rect_region(SHEET, Rect2(ground + Vector2(0, -roundf(height)) - FEET, FRAME), src, Color(1, 1, 1, alpha))


func _draw() -> void:
	for i: int in _birds.size():
		var bird: Dictionary = _birds[i]
		var alpha: float = float(bird["show"]) * (1.0 - _gone)
		_bird(bird["pos"] as Vector2, float(bird["z"]), bird["vel"] as Vector2, int(bird["build"]), float(bird["flap"]), alpha, 1.6 if _panic_left > 0.0 or _shriek_left > 0.0 else 1.0)
	for d: Dictionary in _divers:
		var t: float = float(d["t"])
		var hit: float = float(d["hit"])
		var a: Vector2 = d["a"] as Vector2
		var b: Vector2 = d["b"] as Vector2
		var dir: Vector2 = (b - a).normalized() if b.distance_to(a) > 1.0 else Vector2.RIGHT
		var at: Vector2
		var z: float
		if t < hit: ## dropping in from high above the start of the lane
			var k: float = t / maxf(hit, 0.01)
			at = a - dir * 90.0 * (1.0 - k)
			z = lerpf(170.0, 8.0, k * k)
		else: ## the sweep along the lane and up again
			var k2: float = clampf((t - hit) / 0.6, 0.0, 1.0)
			at = a.lerp(b, k2)
			z = 8.0 + 120.0 * k2 * k2
		_bird(at, z, dir, int(d["build"]), float(d["flap"]), 1.0 - smoothstep(hit + 0.45, hit + 0.7, t), 2.0)
