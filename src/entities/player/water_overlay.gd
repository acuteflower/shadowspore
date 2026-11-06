class_name WaterOverlay
extends Node2D
## Translucent water drawn over the player's lower body so they look submerged.

const FILL: Color = Color("438780")
const RIM: Color = Color("91bbae")
const HALF_WIDTH: int = 8
const EASE_SPEED: float = 30.0 ## px/s
const SORT_SHIFT: float = 6.0 ## node sits this far below the feet so it is drawn after the sprite

var submerge: float = 0.0 ## target depth in px, set by the player from the surface data

var _current: float = 0.0


func _process(delta: float) -> void:
	var previous: float = _current
	_current = move_toward(_current, submerge, EASE_SPEED * delta)
	if _current > 0.0 or previous != _current:
		queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, -SORT_SHIFT))
	var depth: int = roundi(_current)
	if depth < 1:
		return
	var fill: Color = Color(FILL, minf(0.48, 0.26 + 0.02 * depth))
	var top: int = 1 - depth
	# Narrow the edges at the feet so the tint sits inside the little waterline.
	if depth > 1:
		draw_rect(Rect2(-HALF_WIDTH + 1, top + 1, HALF_WIDTH * 2 - 2, depth - 1), fill)
	var shimmer: int = floori(Time.get_ticks_msec() / 220.0)
	for x: int in range(-HALF_WIDTH, HALF_WIDTH):
		var rise: int = 1 if posmod(x + shimmer, 7) == 0 else 0
		var lit: bool = posmod(x + shimmer, 8) < 4
		var alpha: float = 0.58 if lit else 0.32
		draw_rect(Rect2(x, top - rise, 1, 1), Color(RIM, alpha))
