class_name AmbushEyes
extends Node2D
## Pairs of magenta eyes opening in the dark, drawn unlit in the world (the spiders of the crossroad ambush come out of them). `open(i, pos)`
## fades a pair in at a world position, `close(i)` lets it go.

var _pairs: Dictionary = {} ## slot -> {pos, t, closing}
var _time: float = 0.0


func _ready() -> void:
	z_index = 5
	material = Unlit.material()


func open(slot: int, pos: Vector2) -> void:
	_pairs[slot] = {"pos": pos, "t": 0.0, "closing": false}


func close(slot: int) -> void:
	if _pairs.has(slot):
		(_pairs[slot] as Dictionary).closing = true


func _process(delta: float) -> void:
	_time += delta
	for slot: int in _pairs.keys():
		var pair: Dictionary = _pairs[slot]
		pair.t = float(pair.t) + delta * (-4.0 if bool(pair.closing) else 0.9)
		if float(pair.t) < 0.0:
			_pairs.erase(slot)
	queue_redraw()


func _draw() -> void:
	for slot: int in _pairs:
		var pair: Dictionary = _pairs[slot]
		var a: float = clampf(float(pair.t), 0.0, 1.0)
		var at: Vector2 = to_local(pair.pos as Vector2) + Vector2(0, -11)
		var blink: bool = fmod(_time * 0.8 + slot * 1.7, 3.6) > 3.4
		var pulse: float = 0.75 + 0.25 * sin(_time * 3.1 + slot)
		for side: float in [-1.0, 1.0]:
			var e: Vector2 = at + Vector2(side * 3.5, 0)
			draw_circle(e, 6.0, Color(0.7, 0.2, 0.9, 0.10 * a * pulse))
			draw_circle(e, 3.5, Color(0.8, 0.25, 0.95, 0.16 * a * pulse))
			var h: float = 1.0 if blink else 2.0
			draw_rect(Rect2(e + Vector2(-1.5, -h * 0.5), Vector2(3, h)), Color(0.9, 0.36, 0.94, a))
			if not blink:
				draw_rect(Rect2(e + Vector2(-0.5, -1), Vector2(1, 1)), Color(1.0, 0.85, 1.0, a))
