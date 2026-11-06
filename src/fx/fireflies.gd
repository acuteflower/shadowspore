class_name Fireflies
extends Node2D
## Fireflies at night: tiny blinking lights drifting around the glowing flora and over the meadow.
## Only as many as fit the screen, they live where the camera looks, fade in with the evening and
## vanish by day. Purely cosmetic, so every peer runs its own. Unlit, so they shine against the tint.

const COUNT: int = 56
const MARGIN: float = 40.0 ## px outside the screen where a firefly may still live
const NEAR_FLORA: float = 0.7 ## share that hovers around a glowing plant
const COLORS: Array[Color] = [Color("a4fff0"), Color("d6ffe6"), Color("a4fff0"), Color("f6dc8c")]
const NEIGHBORS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
const DIAGONALS: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]


class Fly:
	var home: Vector2 = Vector2(INF, INF)
	var radius: float = 16.0
	var speed_x: float = 0.4
	var speed_y: float = 0.5
	var phase_x: float = 0.0
	var phase_y: float = 0.0
	var blink_rate: float = 1.6
	var blink_phase: float = 0.0
	var color: Color = Color.WHITE


var _flies: Array[Fly] = []
var _time: float = 0.0
var _flora: Array[Vector2] = [] ## glowing plants near the screen, refreshed twice a second
var _flora_timer: float = 0.0


func _ready() -> void:
	material = Unlit.material()
	z_index = 3
	for i: int in COUNT:
		var fly: Fly = Fly.new()
		fly.radius = randf_range(10.0, 30.0)
		fly.speed_x = randf_range(0.25, 0.7)
		fly.speed_y = randf_range(0.3, 0.8)
		fly.phase_x = randf() * TAU
		fly.phase_y = randf() * TAU
		fly.blink_rate = randf_range(1.0, 2.4)
		fly.blink_phase = randf() * TAU
		fly.color = COLORS[randi() % COLORS.size()]
		_flies.append(fly)


func _process(delta: float) -> void:
	var interiors: Interiors = get_parent().get_node_or_null("Interiors") as Interiors
	var mines: MineManager = get_parent().get_node_or_null("Mines") as MineManager
	visible = (interiors == null or not interiors.local_inside()) and (mines == null or not mines.local_inside())
	if not visible:
		return
	var night: float = TimeManager.night_amount()
	visible = night > 0.02
	if not visible:
		return
	_time += delta
	var rect: Rect2 = _view_rect()
	_flora_timer -= delta
	if _flora_timer <= 0.0:
		_flora_timer = 0.5
		_refresh_flora(rect)
	for fly: Fly in _flies:
		if not rect.grow(MARGIN).has_point(fly.home):
			_respawn(fly, rect)
	queue_redraw()


func _view_rect() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	return Rect2(inverse * Vector2.ZERO, get_viewport_rect().size)


func _refresh_flora(rect: Rect2) -> void:
	_flora.clear()
	var area: Rect2 = rect.grow(MARGIN)
	for node: Node in get_tree().get_nodes_in_group("flora_glow"):
		var light: Node2D = node as Node2D
		if light != null and area.has_point(light.global_position):
			_flora.append(light.global_position)


func _respawn(fly: Fly, rect: Rect2) -> void:
	if not _flora.is_empty() and randf() < NEAR_FLORA:
		fly.home = _flora[randi() % _flora.size()] + Vector2(randf_range(-12.0, 12.0), randf_range(-10.0, 4.0))
	else:
		fly.home = rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)


func _draw() -> void:
	var night: float = TimeManager.night_amount()
	for fly: Fly in _flies:
		if fly.home.x == INF:
			continue
		var sway: Vector2 = Vector2(
			sin(_time * fly.speed_x + fly.phase_x) * fly.radius,
			cos(_time * fly.speed_y + fly.phase_y) * fly.radius * 0.5 - 6.0 + sin(_time * 0.9 + fly.phase_x) * 2.0)
		var point: Vector2 = (fly.home + sway).round()
		var glow: float = pow(0.5 + 0.5 * sin(_time * fly.blink_rate + fly.blink_phase), 1.7) * night
		if glow < 0.06:
			continue
		draw_rect(Rect2(point, Vector2.ONE), Color(fly.color, minf(glow * 1.5, 1.0)))
		if glow > 0.25: ## a bright flash gets a small cross of glow around it, the brightest a soft ring
			for offset: Vector2 in NEIGHBORS:
				draw_rect(Rect2(point + offset, Vector2.ONE), Color(fly.color, (glow - 0.25) * 0.9))
		if glow > 0.6:
			for offset: Vector2 in DIAGONALS:
				draw_rect(Rect2(point + offset, Vector2.ONE), Color(fly.color, (glow - 0.6) * 0.6))
