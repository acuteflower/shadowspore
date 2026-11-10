class_name PetGlint
extends Node2D
## What a companion points out (docs/pet_konzept.md 11): a few pixel sparks that circle a spot for a while, gold for the crow's Fundnase, magenta for the
## raven's Warnruf. Cosmetic, drawn unlit, every peer makes its own.

var warning: bool = false
var notes: bool = false ## the whistle: three little notes rise over her head
var life: float = 6.0
var _age: float = 0.0


func _ready() -> void:
	z_index = 40
	material = Unlit.material()


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if notes:
		for i: int in 3:
			var u: float = clampf(_age / life - i * 0.12, 0.0, 1.0)
			if u <= 0.0:
				continue
			var base: Vector2 = Vector2(roundf((i - 1) * 7.0 + sin(u * 9.0 + i) * 2.0), roundf(-34.0 - u * 18.0))
			var a: float = sin(u * PI)
			draw_rect(Rect2(base + Vector2(-1, -1), Vector2(4, 4)), Color("1b1a2e", 0.8 * a))
			draw_rect(Rect2(base, Vector2(2, 2)), Color("f1e6ff", a))
			draw_rect(Rect2(base + Vector2(1, -5), Vector2(1, 5)), Color("f1e6ff", a))
			draw_rect(Rect2(base + Vector2(2, -5), Vector2(2, 1)), Color("f0d070", a))
		return
	var fade: float = clampf(minf(_age * 3.0, (life - _age) * 2.0), 0.0, 1.0)
	var tone: Color = Color("e0409a") if warning else Color("f0d070")
	var count: int = 6 if warning else 4
	for i: int in count:
		var a: float = _age * (2.2 if warning else 1.4) + float(i) / count * TAU
		var r: float = (11.0 + sin(_age * 3.0 + i) * 2.0) if warning else (6.0 + sin(_age * 2.0 + i) * 3.0)
		var p: Vector2 = Vector2(roundf(cos(a) * r), roundf(sin(a) * r * 0.6 - 6.0 - (0.0 if warning else fposmod(_age * 6.0 + i * 3.0, 12.0))))
		draw_rect(Rect2(p - Vector2.ONE, Vector2(3, 3)), Color("1b1a2e", 0.7 * fade))
		draw_rect(Rect2(p, Vector2.ONE), Color(tone, fade))
		if int(_age * 6.0 + i) % 3 == 0:
			draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Color(tone.lightened(0.4), 0.8 * fade))
			draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), Color(tone.lightened(0.4), 0.8 * fade))
