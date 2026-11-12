class_name MenuEmbers
extends Control
## The living specks of the main menu (`MainMenu`): embers rising from the camp fire, turquoise spores drifting through the light that gather round
## the cursor, and pairs of magenta eyes that open in the void and close again when the light comes near. Screen space, whole art pixels, drawn
## above the dark (`menu_void.gdshader`) so it all glows. `burst(at, n)` throws a ring of embers (the fire's answer to a void surge, the start).

const EMBER_MAX: int = 140
const SPORE_COUNT: int = 34
const EYE_SPOTS: Array[Vector2] = [Vector2(14, 128), Vector2(22, 214), Vector2(10, 300), Vector2(40, 84), Vector2(120, 22), Vector2(560, 18),
		Vector2(626, 96), Vector2(618, 190), Vector2(206, 342), Vector2(360, 350), Vector2(612, 336), Vector2(268, 18)]
const EMBER_HOT: Color = Color("fff0b0")
const EMBER_MID: Color = Color("ffb347")
const EMBER_COOL: Color = Color("c2502a")
const SPORE: Color = Color("78f4e6")
const SPORE_CORE: Color = Color("d0fff8")
const SPORE_DIM: Color = Color("2a8c94")
const EYE: Color = Color("ff4fd8")
const EYE_CORE: Color = Color("ffd0f0")

var fire: Vector2 = Vector2(468.0, 292.0) ## where the embers rise from, screen pixels
var light: Vector2 = Vector2(-999.0, -999.0) ## the cursor's light
var cursor_on: bool = true
var surge: float = 0.0 ## >0: the void lunges, more eyes open, the fire sputters
var intensity: float = 0.0 ## 0..1, the fire's strength (the opening ramps it up)

var _time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _embers: Array[Dictionary] = []
var _spores: Array[Dictionary] = []
var _eyes: Array[Dictionary] = []
var _spawn: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7331
	for i: int in SPORE_COUNT:
		_spores.append({"p": Vector2(_rng.randf_range(160.0, 630.0), _rng.randf_range(150.0, 350.0)), "v": Vector2.ZERO, "phase": _rng.randf() * TAU, "seed": _rng.randf()})
	for spot: Vector2 in EYE_SPOTS:
		_eyes.append({"p": spot, "open": 0.0, "want": false, "next": _rng.randf_range(1.0, 8.0), "blink": 0.0, "wide": _rng.randi_range(3, 5)})


## A ring of embers thrown out from `at`.
func burst(at: Vector2, count: int, speed: float = 70.0) -> void:
	for i: int in count:
		var a: float = _rng.randf() * TAU
		var s: float = _rng.randf_range(0.35, 1.0) * speed
		_add_ember(at + Vector2(cos(a), sin(a)) * 3.0, Vector2(cos(a), sin(a) * 0.7 - 0.35) * s, _rng.randf_range(0.6, 1.4))


func _add_ember(at: Vector2, vel: Vector2, life: float) -> void:
	if _embers.size() >= EMBER_MAX:
		_embers.pop_front()
	_embers.append({"p": at, "v": vel, "age": 0.0, "life": life, "seed": _rng.randf()})


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.1)
	_time += dt
	# embers rise from the fire; a surge chokes them
	_spawn += dt * 16.0 * intensity * (1.0 - 0.7 * clampf(surge, 0.0, 1.0))
	while _spawn >= 1.0:
		_spawn -= 1.0
		_add_ember(fire + Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-6.0, 0.0)), Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-30.0, -14.0)), _rng.randf_range(1.2, 3.2))
	var i: int = 0
	while i < _embers.size():
		var e: Dictionary = _embers[i]
		e.age = float(e.age) + dt
		if float(e.age) >= float(e.life):
			_embers.remove_at(i)
			continue
		var v: Vector2 = e.v
		v.x += sin(_time * 2.3 + float(e.seed) * 20.0) * 18.0 * dt + 4.0 * dt ## sway and a soft breeze
		v.y -= 6.0 * dt ## heat lifts
		v *= 1.0 - 0.9 * dt
		e.v = v
		e.p = (e.p as Vector2) + v * dt
		i += 1
	# spores drift; the cursor gathers them into a slow orbit
	for s: Dictionary in _spores:
		var p: Vector2 = s.p
		var v: Vector2 = s.v
		var ph: float = float(s.phase)
		v += Vector2(sin(_time * 0.7 + ph), cos(_time * 0.5 + ph * 1.3)) * 6.0 * dt
		if cursor_on and light.x > -500.0:
			var to: Vector2 = light - p
			var d: float = to.length()
			if d < 90.0 and d > 0.5:
				var pull: float = (1.0 - d / 90.0)
				v += to / d * pull * 40.0 * dt ## drawn in
				v += Vector2(-to.y, to.x) / d * pull * 34.0 * dt ## and round
		v *= 1.0 - 1.4 * dt
		p += v * dt
		if p.x < 150.0 or p.x > 636.0 or p.y < 140.0 or p.y > 356.0:
			p = Vector2(clampf(p.x, 150.0, 636.0), clampf(p.y, 140.0, 356.0))
			v = -v * 0.5
		s.p = p
		s.v = v
	# eyes open in the dark, close in the light
	for eye: Dictionary in _eyes:
		var spot: Vector2 = eye.p
		var lit: bool = cursor_on and spot.distance_to(light) < 70.0
		eye.next = float(eye.next) - dt * (1.0 + 2.5 * maxf(surge, 0.0))
		if float(eye.next) <= 0.0:
			eye.want = not bool(eye.want)
			eye.next = _rng.randf_range(2.5, 6.0) if bool(eye.want) else _rng.randf_range(3.0, 10.0)
		var want: bool = (bool(eye.want) or surge > 0.55) and not lit and intensity > 0.5
		eye.open = move_toward(float(eye.open), 1.0 if want else 0.0, dt * (2.0 if want else 6.0))
		eye.blink = float(eye.blink) - dt
		if float(eye.blink) < -_rng.randf_range(2.0, 5.0):
			eye.blink = 0.12
	queue_redraw()


func _draw() -> void:
	# spores (behind the embers)
	for s: Dictionary in _spores:
		var p: Vector2 = (s.p as Vector2).round()
		var tw: float = 0.5 + 0.5 * sin(_time * 2.4 + float(s.phase) * 3.0)
		var near: float = 0.0
		if cursor_on and light.x > -500.0:
			near = clampf(1.0 - p.distance_to(light) / 90.0, 0.0, 1.0)
		var a: float = (0.35 + 0.5 * tw + 0.4 * near) * intensity
		draw_rect(Rect2(p, Vector2.ONE), Color(SPORE_CORE if tw > 0.75 or near > 0.5 else SPORE, minf(a, 1.0)))
		if near > 0.3 or tw > 0.85:
			for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_rect(Rect2(p + o, Vector2.ONE), Color(SPORE_DIM, a * 0.6))
	# embers
	for e: Dictionary in _embers:
		var u: float = float(e.age) / float(e.life)
		var c: Color = EMBER_HOT.lerp(EMBER_MID, clampf(u * 2.0, 0.0, 1.0)).lerp(EMBER_COOL, clampf(u * 2.0 - 1.0, 0.0, 1.0))
		var flick: float = 0.7 + 0.3 * sin(_time * 19.0 + float(e.seed) * 40.0)
		c.a = (1.0 - u * u) * flick
		var p: Vector2 = (e.p as Vector2).round()
		draw_rect(Rect2(p, Vector2.ONE), c)
		if u < 0.35 and float(e.seed) > 0.6:
			draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(EMBER_COOL, c.a * 0.5))
	# eyes
	for eye: Dictionary in _eyes:
		var o: float = float(eye.open)
		if o <= 0.02:
			continue
		var spot: Vector2 = eye.p
		var look: Vector2 = Vector2.ZERO
		if cursor_on and light.x > -500.0:
			look = (light - spot).normalized().round()
		var wide: float = float(int(eye.wide))
		var shut: bool = float(eye.blink) > 0.0
		for side: float in [-1.0, 1.0]:
			var at: Vector2 = (spot + Vector2(side * wide * 0.5, 0.0)).round()
			draw_rect(Rect2(at + Vector2(-2, -1), Vector2(4, 3)), Color(EYE, 0.12 * o))
			if shut:
				draw_rect(Rect2(at + Vector2(-1, 0), Vector2(2, 1)), Color(EYE, 0.5 * o))
			else:
				draw_rect(Rect2(at + Vector2(-1, 0), Vector2(2, 1)), Color(EYE, 0.9 * o))
				draw_rect(Rect2(at + Vector2(-1.0 if look.x < 0.0 else 0.0, 0.0), Vector2.ONE), Color(EYE_CORE, o)) ## the pupil looks towards the light
