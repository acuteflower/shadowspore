class_name EatEffect
extends Node2D
## What surrounds the one-second eating animation (the sheet and the right arm do the body): the
## berry in her hand, flicked into the air and caught in her mouth, juice sparks at the bite and
## a ring of healing light with rising sparkles. Everything follows the animation time, so every
## peer sees the same. Unlit: it glows at night.

const LAUNCH: float = 0.20 ## the berry leaves the hand
const BITE: float = 0.48 ## it reaches the mouth
const BERRY: Array[Color] = [Color("2a1568"), Color("4a2aa0"), Color("6a3ee0"), Color("8a5cf0"), Color("d9c8ff")]
const HEAL: Color = Color("9af0a8")
const WHITE: Color = Color("f4f0ff")
const JUICE: Array[Color] = [Color("8a5cf0"), Color("d9c8ff"), Color("6a3ee0"), Color("78f4e6")]

var _t: float = -1.0
var _hand: Vector2 = Vector2.ZERO
var _mouth: Vector2 = Vector2.ZERO
var _launch_from: Vector2 = Vector2.ZERO


func _ready() -> void:
	z_index = 6
	material = Unlit.material()


## Called every frame of the animation with its time, the hand and the mouth (px from the feet).
func show_state(time: float, hand: Vector2, mouth: Vector2) -> void:
	if time < LAUNCH:
		_launch_from = hand
	_t = time
	_hand = hand
	_mouth = mouth
	queue_redraw()


func clear() -> void:
	if _t >= 0.0:
		_t = -1.0
		queue_redraw()


func _draw() -> void:
	if _t < 0.0:
		return
	if _t < LAUNCH:
		_berry(_hand + Vector2(0, -1), 1.0)
	elif _t < BITE:
		var u: float = (_t - LAUNCH) / (BITE - LAUNCH)
		for k: int in 3: ## a short glinting trail
			var uu: float = maxf(u - k * 0.07, 0.0)
			var at: Vector2 = _launch_from.lerp(_mouth, uu) + Vector2(0, -sin(uu * PI) * 18.0)
			if k == 0:
				_berry(at, 1.0)
			else:
				_dot(at + Vector2(1, 1), Color(BERRY[4], 0.55 - k * 0.2))
	var since: float = _t - BITE
	if since < 0.0:
		return
	if since < 0.14: ## a flash of light at the mouth
		var size: int = 1 + int((1.0 - since / 0.14) * 3.0)
		for d: int in range(-size, size + 1):
			_dot(_mouth + Vector2(d, 0), Color(WHITE, 1.0 - since / 0.14))
			_dot(_mouth + Vector2(0, d), Color(WHITE, 1.0 - since / 0.14))
	for i: int in 9: ## juice and sparks fly from the mouth
		var angle: float = i * TAU / 9.0 + 0.4
		var life: float = 0.45
		if since < life:
			var v: Vector2 = Vector2.from_angle(angle) * (20.0 + (i % 3) * 7.0)
			_dot(_mouth + v * since + Vector2(0, 80.0 * since * since), Color(JUICE[i % JUICE.size()], 1.0 - since / life))
	for ring: int in 3: ## rings of healing light rise from her feet to her head
		var age: float = since - ring * 0.12
		if age < 0.0 or age > 0.7:
			continue
		var rise: float = age / 0.7
		var radius: float = 11.0 + 8.0 * sin(rise * PI)
		var center_y: float = -3.0 - 36.0 * rise
		var color: Color = HEAL if ring != 1 else WHITE
		for k: int in 30:
			var a: float = k * TAU / 30.0
			var at: Vector2 = Vector2(cos(a) * radius, center_y + sin(a) * radius * 0.4).round()
			draw_rect(Rect2(at, Vector2(2, 1)), Color(color, minf((1.0 - rise) * 1.3, 1.0)))
	for i: int in 12: ## sparkles drift up around her
		var start: float = (i % 4) * 0.06
		var age: float = since - start
		if age < 0.0 or age > 0.85:
			continue
		var a: float = i * 2.399
		var x: float = cos(a) * (7.0 + (i % 3) * 3.0)
		var y: float = -6.0 - age * (34.0 + (i % 5) * 5.0)
		_dot(Vector2(x, y), Color(HEAL if i % 3 != 0 else WHITE, 1.0 - age / 0.85))


func _dot(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at.round(), Vector2.ONE), color)


## A 3x3 berry with cut corners (the same as on the bush): shade, base, light, glint.
func _berry(at: Vector2, alpha: float) -> void:
	var c: Vector2 = at.round()
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			if (dx == 1 and dy == -1) or (dx == -1 and dy == 1):
				continue
			var lit: int = -dx - dy
			var color: Color = BERRY[2] if lit > 0 else (BERRY[0] if lit < 0 else BERRY[1])
			draw_rect(Rect2(c + Vector2(dx, dy), Vector2.ONE), Color(color, alpha))
	draw_rect(Rect2(c + Vector2(-1, -1), Vector2.ONE), BERRY[4])
