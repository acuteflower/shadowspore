class_name WorldHealthBar
extends Node2D
## Small health bar above a body. Only visible while damaged and alive.

const FILL: Array[Color] = [Color("f2a58b"), Color("e0755f"), Color("a8453b")] ## highlight, main, shade
const BACKGROUND: Color = Color("2a2548")
const WIDTH: int = 22

@export var health: HealthComponent


func _ready() -> void:
	if health == null:
		health = get_node("../HealthComponent") as HealthComponent
	material = Unlit.material()
	health.changed.connect(func(_c: float, _m: float) -> void: queue_redraw())


func _draw() -> void:
	if health.current >= health.max_health or health.current <= 0.0:
		return
	var x: int = -WIDTH / 2
	draw_rect(Rect2(x - 1, -1, WIDTH + 2, 5), UiStyle.OUTLINE)
	draw_rect(Rect2(x, 0, WIDTH, 3), BACKGROUND)
	var fill: int = ceili(WIDTH * health.current / health.max_health)
	draw_rect(Rect2(x, 0, fill, 1), FILL[0])
	draw_rect(Rect2(x, 1, fill, 1), FILL[1])
	draw_rect(Rect2(x, 2, fill, 1), FILL[2])
