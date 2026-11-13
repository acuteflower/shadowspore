class_name Fireflies
extends Node2D
## Fireflies at night: tiny blinking lights drifting around the glowing flora and over the meadow.
## Only as many as fit the screen, they live where the camera looks, fade in with the evening and
## vanish by day. Purely cosmetic, so every peer runs its own. Unlit, so they shine against the tint.

const COUNT: int = 76
const MARGIN: float = 40.0 ## px outside the screen where a firefly may still live
const NEAR_FLORA: float = 0.7 ## share that hovers around a glowing plant
const COLORS: Array[Color] = [Color("a4fff0"), Color("d6ffe6"), Color("a4fff0"), Color("f6dc8c")]
const WITCH_COLORS: Array[Color] = [Color("a8ff6a"), Color("eaffc4"), Color("a8ff6a"), Color("c690ec")] ## in the Hexenwald: witch green, now and then violet
const DESERT_COLORS: Array[Color] = [Color("e8f2ff"), Color("fff2da"), Color("dceaff"), Color("ffe8c2")] ## in the desert: sparse, faint heat/crystal glimmers over quartz
const WITCH_DUSK: float = 0.45 ## the Hexenwald never gets light: its flies keep this much of the night by day (BiomeBlend at the view's middle)
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
	var night: float = _night_here()
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


func _night_here() -> float:
	return maxf(TimeManager.night_amount(), WITCH_DUSK * BiomeBlend.amount_at(_view_rect().get_center())) * (1.0 - 0.7 * clampf(WeatherManager.rain_now(), 0.0, 1.0)) ## rain puts the little lights out


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
	var arid: float = BiomeBlend.arid_at(fly.home)
	if arid > 0.50:
		var oasis_w: float = BiomeBlend.oasis_at(fly.home)
		if oasis_w > 0.30:
			fly.color = [Color(1.0, 0.85, 0.45), Color(0.45, 0.96, 0.90), Color(0.95, 0.92, 0.65)][randi() % 3]
			return
		for _try_q: int in 5:
			var try_pos: Vector2 = rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)
			if BiomeBlend.is_quartz_surface(try_pos):
				fly.home = try_pos
				break
		fly.color = DESERT_COLORS[randi() % DESERT_COLORS.size()]
		return
	var witch: bool = BiomeBlend.amount_at(fly.home) > 0.5
	if witch != WITCH_COLORS.has(fly.color) or DESERT_COLORS.has(fly.color):
		fly.color = (WITCH_COLORS if witch else COLORS)[randi() % 4]


func _draw() -> void:
	var night: float = _night_here()
	for i: int in _flies.size():
		var fly: Fly = _flies[i]
		if fly.home.x == INF:
			continue
		var arid: float = BiomeBlend.arid_at(fly.home)
		var oasis_w: float = BiomeBlend.oasis_at(fly.home) if arid > 0.20 else 0.0
		var desert_t: float = smoothstep(0.25, 0.68, arid) * (1.0 - 0.85 * oasis_w)
		var sway: Vector2 = Vector2(
			sin(_time * fly.speed_x + fly.phase_x) * fly.radius,
			cos(_time * fly.speed_y + fly.phase_y) * fly.radius * 0.5 - 6.0 + sin(_time * 0.9 + fly.phase_x) * 2.0) * lerpf(1.0, 0.25, desert_t)
		var point: Vector2 = (fly.home + sway).round()
		var on_q: bool = desert_t > 0.30 and BiomeBlend.is_quartz_surface(point)
		if desert_t > 0.05:
			var keep_share: float = lerpf(1.0, 0.18 if on_q else 0.04, desert_t)
			if float(posmod(i * 37 + 11, 100)) / 100.0 >= keep_share:
				continue
		var rate: float = fly.blink_rate * lerpf(1.0, 0.42, desert_t)
		var glow: float = pow(0.5 + 0.5 * sin(_time * rate + fly.blink_phase), 1.7) * night
		if glow < 0.06:
			continue
		var alpha: float = minf(glow * lerpf(1.5, 0.36, desert_t), lerpf(1.0, 0.30 if on_q else 0.16, desert_t))
		if alpha < 0.04:
			continue
		draw_rect(Rect2(point, Vector2.ONE), Color(fly.color, alpha))
		if glow > 0.25 and desert_t < 0.35: ## a bright flash gets a small cross of glow around it, the brightest a soft ring
			for offset: Vector2 in NEIGHBORS:
				draw_rect(Rect2(point + offset, Vector2.ONE), Color(fly.color, (glow - 0.25) * 0.9))
		if glow > 0.6 and desert_t < 0.35:
			for offset: Vector2 in DIAGONALS:
				draw_rect(Rect2(point + offset, Vector2.ONE), Color(fly.color, (glow - 0.6) * 0.6))
