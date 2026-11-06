class_name MineBats
extends Node2D
## A few bats that cross the screen now and then in the upper zones (docs/mine.md section 7: peaceful ambient fauna): one to three little dark shapes with flapping
## wings flying a wobbling line across the view, drawn pixel by pixel. Cosmetic: every peer runs its own, they have no body and nothing reacts to them.

const WINGS: Array[Vector2i] = [Vector2i(-3, -1), Vector2i(-2, -2), Vector2i(-4, 0), Vector2i(3, -1), Vector2i(2, -2), Vector2i(4, 0)]

var active: bool = false ## set by the atmosphere while the local player is in a level with bats
var _bats: Array[Dictionary] = [] ## {pos, vel, phase, age}
var _next: float = 6.0


func _ready() -> void:
	z_index = 3
	top_level = true
	global_position = Vector2.ZERO


func _process(delta: float) -> void:
	if not active:
		_bats.clear()
		queue_redraw()
		return
	var player: Player = (get_parent() as MineAtmosphere)._mines.local_player()
	if player == null:
		return
	_next -= delta
	if _next <= 0.0:
		_next = randf_range(14.0, 34.0)
		var side: float = -1.0 if randf() < 0.5 else 1.0
		for i: int in randi_range(1, 3):
			_bats.append({"pos": player.global_position + Vector2(side * (250.0 + float(i) * 14.0), randf_range(-110.0, 20.0)), "vel": Vector2(-side * randf_range(55.0, 85.0), randf_range(-8.0, 8.0)), "phase": randf() * TAU, "age": 0.0})
	for bat: Dictionary in _bats:
		bat.age = float(bat.age) + delta
		bat.pos = (bat.pos as Vector2) + (bat.vel as Vector2) * delta + Vector2(0.0, sin(float(bat.age) * 3.1 + float(bat.phase)) * 18.0 * delta)
	_bats = _bats.filter(func(b: Dictionary) -> bool: return float(b.age) < 9.0)
	queue_redraw()


func _draw() -> void:
	for bat: Dictionary in _bats:
		var at: Vector2 = (bat.pos as Vector2).round()
		var up: bool = sin(float(bat.age) * 17.0 + float(bat.phase)) > 0.0
		draw_rect(Rect2(at + Vector2(-1, 0), Vector2(2, 2)), Color("0b0710"))
		for w: Vector2i in WINGS:
			draw_rect(Rect2(at + Vector2(float(w.x), float(w.y if up else -w.y + 1)), Vector2.ONE), Color("0b0710"))
		draw_rect(Rect2(at + Vector2(-1, -1), Vector2.ONE), Color("3a2a48")) ## an ear catching the light
