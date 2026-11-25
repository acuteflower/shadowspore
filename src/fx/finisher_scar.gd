class_name FinisherScar
extends Node2D
## Finisher V2 Kern-Bruch (docs/finisher_v2_konzept.md): the burnt scar where a core was torn out. A jagged star of cracks in the ground that
## glows violet-white first (unlit) and cools within a few seconds, then a dark violet scorch that fades out over `LIFE` seconds.
## Pure decoration, local on every peer, drawn under all bodies (absolute z -4, above the ground shadows).

const LIFE: float = 25.0
const GLOW_FOR: float = 5.0
const SCORCH: Color = Color("140b24")
const CRACK_DARK: Color = Color("2a1748")
const CRACK_HOT: Color = Color("b06bff")
const CRACK_CORE: Color = Color("ecd2ff")

var _age: float = 0.0
var _rays: Array[Dictionary] = [] ## {ang, len, seed}
var _blots: PackedVector2Array = PackedVector2Array()
var _redraw_left: float = 0.0


func setup(at_world: Vector2, strike_dir: Vector2) -> void:
	global_position = at_world.round()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var count: int = 7
	for i: int in count:
		var a: float = float(i) * TAU / float(count) + rng.randf_range(-0.25, 0.25)
		var bias: float = 1.0 + 0.45 * maxf(0.0, Vector2.from_angle(a).dot(-strike_dir)) ## the rip tore towards her: longer cracks on that side
		_rays.append({"ang": a, "len": rng.randf_range(9.0, 17.0) * bias, "seed": rng.randf_range(0.0, 10.0)})
	for i: int in 22:
		var r: float = sqrt(rng.randf()) * 7.0
		var a2: float = rng.randf() * TAU
		_blots.append(Vector2(cos(a2) * r, sin(a2) * r * 0.6).round())


func _ready() -> void:
	z_as_relative = false
	z_index = -4
	material = Unlit.material()


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = 0.05 if _age < GLOW_FOR else 0.5
		queue_redraw()


func _px(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.round(), Vector2.ONE), c)


func _draw() -> void:
	var fade: float = 1.0 - smoothstep(LIFE * 0.55, LIFE, _age)
	var heat: float = 1.0 - smoothstep(0.0, GLOW_FOR, _age)
	var night: float = TimeManager.night_amount()
	for b: Vector2 in _blots:
		_px(b, Color(SCORCH, 0.55 * fade))
	for ray: Dictionary in _rays:
		var ang: float = float(ray["ang"])
		var rlen: float = float(ray["len"])
		var sd: float = float(ray["seed"])
		var dir: Vector2 = Vector2(cos(ang), sin(ang) * 0.6)
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var steps: int = maxi(3, int(rlen / 1.5))
		for s: int in range(1, steps + 1):
			var u: float = float(s) / float(steps)
			var p: Vector2 = dir * (rlen * u) + perp * (sin(u * 8.0 + sd) * 1.3)
			var dark: Color = Color(CRACK_DARK, (0.8 - u * 0.4) * fade)
			_px(p, dark)
			if heat > 0.01 and u < 0.85:
				var hot: Color = CRACK_CORE if u < 0.3 else CRACK_HOT
				hot.a = heat * (1.0 - u) * lerpf(0.55, 1.0, night)
				_px(p, hot)
	if heat > 0.01:
		var core: Color = Color(CRACK_CORE, heat * 0.9)
		for o: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_px(o, core)
