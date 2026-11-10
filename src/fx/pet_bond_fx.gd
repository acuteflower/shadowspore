class_name PetBondFx
extends Node2D
## What happens at a bird that took food from a hand: a few feather motes (the bird's own dark plumage, a violet sheen and a golden spark) lift off and
## drift up, and when the bond reaches a new stage a ring of warm light spreads on the ground. World-anchored, unlit, over in about 1.4 seconds,
## then it frees itself. Cosmetic: every peer spawns its own.

const LIFE: float = 1.4
const FEATHER: Array[Color] = [Color("2a2144"), Color("4a3a78"), Color("8a7ac8")]
const GOLD: Color = Color("ffd98a")
const TEAL: Color = Color("78f4e6")

var _age: float = 0.0
var _up: bool = false
var _motes: Array[Dictionary] = []


static func spawn(parent: Node, at: Vector2, stage_up: bool) -> void:
	var fx: PetBondFx = PetBondFx.new()
	fx._up = stage_up
	fx.global_position = at
	parent.add_child(fx)
	fx.global_position = at


func _ready() -> void:
	z_index = 30
	material = Unlit.material()
	for i: int in (12 if _up else 7):
		_motes.append({"a": randf() * TAU, "r": randf_range(1.0, 7.0), "v": randf_range(14.0, 30.0), "s": randf_range(-6.0, 6.0), "c": randi() % 3, "g": randf() < 0.3})


func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= LIFE:
		queue_free()


func _draw() -> void:
	var k: float = _age / LIFE
	if _up and k < 0.8:
		var radius: float = 5.0 + k / 0.8 * 24.0
		var steps: int = 28
		for i: int in steps:
			if (i + int(_age * 10.0)) % 2 == 0:
				var angle: float = float(i) / steps * TAU
				var point: Vector2 = Vector2(cos(angle), sin(angle) * 0.45) * radius + Vector2(0, -1)
				draw_rect(Rect2(point.round(), Vector2(1, 1)), Color(GOLD, (1.0 - k / 0.8) * 0.9))
	for mote: Dictionary in _motes:
		var rise: float = float(mote["v"]) * _age
		var at: Vector2 = Vector2(cos(float(mote["a"])) * float(mote["r"]) + sin(_age * 3.0 + float(mote["a"])) * 2.0 + float(mote["s"]) * _age, -8.0 - rise)
		var alpha: float = clampf(1.0 - k * k, 0.0, 1.0)
		var color: Color = GOLD if bool(mote["g"]) else FEATHER[int(mote["c"])]
		if bool(mote["g"]):
			draw_rect(Rect2(at.round(), Vector2(1, 1)), Color(color, alpha))
			draw_rect(Rect2(at.round() + Vector2(-1, 0), Vector2(3, 1)), Color(color, alpha * 0.35))
		else:
			draw_rect(Rect2(at.round(), Vector2(2, 1)), Color(color, alpha))
			draw_rect(Rect2(at.round() + Vector2(1, -1), Vector2(1, 1)), Color(TEAL, alpha * 0.5))
