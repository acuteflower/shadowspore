class_name SwimWater
extends Node2D
## docs/schwimmen_konzept.md 6.1: the water around a swimmer, drawn in whole pixels like WaterOverlay/WaterRipples. Sits below her feet so it is
## drawn after the sprite (the waterline in front of the body); `Back` is a child behind her (the ring of water and her shadow on it).
## Splashes, bubbles and the crown at the way in/out are world-anchored pixel particles (every peer makes its own).

const FILL: Color = Color("438780")
const RIM: Color = Color("91bbae")
const FOAM: Color = Color("bfe9ff")
const SHADOW: Color = Color("2a2748")
const MOON: Color = Color("c7e0ff") ## cold glints on rings and waterline at night
const SORT_SHIFT: float = 6.0
const MAX_DROPS: int = 48

var energy: float = 0.0 ## 0 treading .. 1 crawl, eased
var moving: bool = false
var heading: Vector2 = Vector2.RIGHT ## ground direction of travel
var intensity: float = 0.0 ## 0..1 fade in/out with the swim blend

var _drops: Array[Dictionary] = [] ## {p: Vector2 world foot pos, h: height px, v: Vector2, vh: float, age: float, life: float, foam: bool}
var _bubbles: Array[Dictionary] = []
var _back: Node2D


func _ready() -> void:
	position = Vector2(0.0, SORT_SHIFT)
	_back = Node2D.new()
	_back.name = "Back"
	_back.z_index = -1
	_back.draw.connect(_draw_back)
	add_child(_back)
	_back.position = Vector2(0.0, -SORT_SHIFT)


func _process(delta: float) -> void:
	if intensity <= 0.0 and _drops.is_empty() and _bubbles.is_empty():
		return
	for i: int in range(_drops.size() - 1, -1, -1):
		var d: Dictionary = _drops[i]
		d["age"] = float(d["age"]) + delta
		d["vh"] = float(d["vh"]) - 150.0 * delta
		d["h"] = float(d["h"]) + float(d["vh"]) * delta
		d["p"] = (d["p"] as Vector2) + (d["v"] as Vector2) * delta
		if float(d["age"]) >= float(d["life"]) or float(d["h"]) < -1.0:
			_drops.remove_at(i)
	for i: int in range(_bubbles.size() - 1, -1, -1):
		var b: Dictionary = _bubbles[i]
		b["age"] = float(b["age"]) + delta
		b["h"] = float(b["h"]) + 14.0 * delta
		if float(b["age"]) >= 0.8:
			_bubbles.remove_at(i)
	queue_redraw()
	_back.queue_redraw()


## Drops thrown up at a world foot position (an arm entering the water, a kick, the crown at the way in).
func splash(world_pos: Vector2, count: int, power: float = 1.0, foam: bool = false, height: float = 0.5) -> void:
	for k: int in count:
		if _drops.size() >= MAX_DROPS:
			_drops.remove_at(0)
		var a: float = randf() * TAU
		var speed: float = randf_range(8.0, 22.0) * power
		_drops.append({"p": world_pos + Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0)), "h": height, "v": Vector2(cos(a), sin(a) * 0.5) * speed,
			"vh": randf_range(36.0, 72.0) * power, "age": 0.0, "life": randf_range(0.35, 0.6), "foam": foam or randf() < 0.3})


func bubble(world_pos: Vector2) -> void:
	if _bubbles.size() < 8:
		_bubbles.append({"p": world_pos, "h": 0.0, "age": 0.0})


func _draw() -> void:
	draw_set_transform(Vector2(0.0, -SORT_SHIFT))
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var night: float = TimeManager.night_amount()
	if intensity > 0.02:
		# The waterline in front of the body: a ragged strip of light pixels dancing in 1-3 px waves; it breaks up when she swims hard.
		var half: int = 11 if energy > 0.6 else 9
		for x: int in range(-half, half + 1):
			var wave: float = sin(float(x) * 0.7 + t * (3.0 + 4.0 * energy)) + 0.6 * sin(float(x) * 1.6 - t * 2.3)
			var y: int = int(roundf(wave * (0.6 + 1.0 * energy)))
			var edge: float = 1.0 - absf(float(x)) / float(half + 1)
			var lit: bool = posmod(x + int(t * 5.0), 5) < 2
			var tint: Color = FOAM if (lit and energy > 0.5) else RIM
			if night > 0.3 and posmod(x * 3 + int(t * 6.0), 7) == 0:
				tint = MOON ## a moon glint on the ripple
			draw_rect(Rect2(x, y, 1, 1), Color(tint, (0.7 + 0.3 * edge) * intensity))
			draw_rect(Rect2(x, y + 1, 1, 1), Color(FILL, (0.7 * edge + 0.15) * intensity))
		# The bow wave: two short V lines ahead of her, longer and brighter the faster she swims.
		if moving:
			var fwd: Vector2 = Vector2(heading.x, heading.y * 0.5).normalized()
			var side: Vector2 = Vector2(-fwd.y, fwd.x)
			var length: int = 3 + int(5.0 * energy)
			for k: int in length:
				var base: Vector2 = fwd * (6.0 + float(k) * 0.6) + Vector2(0.0, -1.0)
				for sgn: int in [-1, 1]:
					var p: Vector2 = (base - fwd * float(k) * 1.1 + side * float(k) * 0.9 * float(sgn)).round()
					draw_rect(Rect2(p, Vector2.ONE), Color(FOAM if energy > 0.6 and k < 2 else RIM, (0.7 - 0.07 * float(k)) * intensity))
	for d: Dictionary in _drops:
		var local: Vector2 = to_local((d["p"] as Vector2)) + Vector2(0.0, -SORT_SHIFT - float(d["h"]))
		var fade: float = 1.0 - float(d["age"]) / float(d["life"])
		draw_rect(Rect2(local.round(), Vector2.ONE), Color(FOAM if bool(d["foam"]) else RIM, 0.9 * fade))
	for b: Dictionary in _bubbles:
		var local: Vector2 = to_local((b["p"] as Vector2)) + Vector2(sin(float(b["age"]) * 9.0), -SORT_SHIFT - float(b["h"]))
		draw_rect(Rect2(local.round(), Vector2.ONE), Color(FOAM, 0.7 * (1.0 - float(b["age"]) / 0.8)))


## Behind the swimmer: a flat ring of water (1 : 0.45) with the violet shadow of the body on it.
func _draw_back() -> void:
	if intensity <= 0.02:
		return
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var rx: float = 11.0 + 2.0 * energy
	var ry: float = rx * 0.45
	_back.draw_set_transform(Vector2(0.0, 5.0))
	for i: int in 40:
		var a: float = TAU * float(i) / 40.0
		var wob: float = 1.0 + 0.06 * sin(a * 3.0 + t * 2.0)
		var p: Vector2 = Vector2(roundf(cos(a) * rx * wob), roundf(sin(a) * ry * wob))
		_back.draw_rect(Rect2(p, Vector2.ONE), Color(FILL, 0.85 * intensity))
		if posmod(i + int(t * 4.0), 2) == 0:
			_back.draw_rect(Rect2(p + Vector2(0.0, -1.0), Vector2.ONE), Color(MOON if (TimeManager.night_amount() > 0.3 and i % 5 == 0) else RIM, 0.75 * intensity))
	for y: int in range(-2, 3):
		var w: int = int(rx * 0.8 * (1.0 - absf(float(y)) / 3.0))
		_back.draw_rect(Rect2(-w, y, w * 2, 1), Color(SHADOW, 0.3 * intensity))
