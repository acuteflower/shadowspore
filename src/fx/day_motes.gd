class_name DayMotes
extends Node2D
## Daylight counterpart of `Fireflies`: pale gold pollen and light dust floating in the sun. Only inside the
## camera view (+40 px), thickest at midday and in the golden hours (then gold and back-lit), none at night,
## indoors or with the map open. They drift with `WorldWind`. Cosmetic, every peer runs its own, unlit.

const COUNT: int = 40 ## hard safety cap; configured visible population in daylight.json
const MARGIN: float = 40.0
const COLORS: Array[Color] = [Color("fff6d0"), Color("ffe9a0"), Color("ffffff"), Color("ffd98a")]
const DESERT_COLOR: Color = Color("fff2d8")
const GOLDEN_COLOR: Color = Color("ffb55e")


class Mote:
	var age: float = 0.0
	var home: Vector2 = Vector2(INF, INF)
	var rank: float = 0.0 ## shows up once the day's density passes this
	var radius: float = 10.0
	var speed: float = 0.4
	var phase: float = 0.0
	var twinkle_rate: float = 0.8
	var color: Color = Color.WHITE


var _motes: Array[Mote] = []
var _time: float = 0.0


func _ready() -> void:
	material = Unlit.material()
	z_index = 3
	var count: int = clampi(int(DataRegistry.table("daylight").get("motes", 38)), 0, COUNT)
	for i: int in count:
		var mote: Mote = Mote.new()
		mote.rank = float(i) / float(count)
		mote.radius = randf_range(6.0, 20.0)
		mote.speed = randf_range(0.25, 0.6)
		mote.phase = randf() * TAU
		mote.twinkle_rate = randf_range(0.5, 1.2)
		mote.color = COLORS[randi() % COLORS.size()]
		_motes.append(mote)


func _density() -> float:
	return clampf(0.9 * TimeManager.sun_amount() + 0.9 * TimeManager.golden_amount(), 0.0, 1.0)


func _process(delta: float) -> void:
	var interiors: Interiors = get_parent().get_node_or_null("Interiors") as Interiors
	var mines: MineManager = get_parent().get_node_or_null("Mines") as MineManager
	visible = (interiors == null or not interiors.local_inside()) and (mines == null or not mines.local_inside()) \
		and not DaylightField.air_blocked() and _density() > 0.02
	if not visible:
		return
	_time += delta
	var rect: Rect2 = _view_rect().grow(MARGIN)
	var wind: Vector2 = Vector2.ZERO
	for mote: Mote in _motes:
		if not rect.has_point(mote.home):
			var candidate: Vector2 = rect.position + Vector2(randf(), randf()) * rect.size
			if BiomeBlend.arid_at(candidate) > 0.55:
				for _try_q: int in 5:
					var try_pos: Vector2 = rect.position + Vector2(randf(), randf()) * rect.size
					if BiomeBlend.is_quartz_surface(try_pos):
						candidate = try_pos
						break
			mote.home = candidate
			mote.age = 0.0
		mote.age += delta
		var arid_m: float = BiomeBlend.arid_at(mote.home)
		var desert_m: float = smoothstep(0.20, 0.65, arid_m)
		wind = WorldWind.sample(mote.home) if desert_m <= 0.001 else WorldWind.sample_soft(mote.home)
		var wind_mul: float = lerpf(14.0, 1.4, desert_m)
		var rise_y: float = lerpf(-1.2, 0.0, desert_m)
		mote.home += (wind * wind_mul + Vector2(0.0, rise_y)) * delta
	queue_redraw()


func _view_rect() -> Rect2:
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	return inverse * get_viewport_rect()


func _draw() -> void:
	var density: float = _density()
	var golden: float = TimeManager.golden_amount()
	for mote: Mote in _motes:
		if mote.home.x == INF or mote.rank > density:
			continue
		var sway_scale: float = lerpf(1.0, 0.35, smoothstep(0.20, 0.65, BiomeBlend.arid_at(mote.home)))
		var sway: Vector2 = Vector2(sin(_time * mote.speed + mote.phase) * mote.radius, cos(_time * mote.speed * 1.3 + mote.phase) * mote.radius * 0.5) * sway_scale
		var point: Vector2 = (mote.home + sway).round()
		var arid: float = BiomeBlend.arid_at(point)
		var desert_t: float = smoothstep(0.20, 0.65, arid)
		var on_q: bool = desert_t > 0.25 and BiomeBlend.is_quartz_surface(point)
		var eff_density: float = density * lerpf(1.0, 0.28 if on_q else 0.10, desert_t)
		if mote.rank > eff_density:
			continue
		var fade: float = clampf((eff_density - mote.rank) * 6.0, 0.0, 1.0) ## comes and goes with the light
		fade *= smoothstep(0.0, 1.2, mote.age)
		if is_instance_valid(DaylightField.current):
			fade *= pow(DaylightField.current.light_at(point), 1.7)
		var rate: float = mote.twinkle_rate * lerpf(1.0, 0.45, desert_t)
		var glint: float = pow(0.5 + 0.5 * sin(_time * rate + mote.phase * 2.0), 2.0) * fade
		if glint < 0.08:
			continue
		var base_col: Color = mote.color.lerp(DESERT_COLOR, desert_t)
		var color: Color = base_col.lerp(GOLDEN_COLOR, golden * (1.0 - 0.45 * desert_t))
		var big: bool = mote.rank < 0.10 and desert_t < 0.30 ## 2 px + cross only in vegetated/meadow air, never in the desert
		var alpha_cap: float = lerpf(1.0, 0.28 if on_q else 0.15, desert_t)
		var alpha: float = minf(glint * lerpf(1.5, 0.38, desert_t), alpha_cap)
		if alpha < 0.04:
			continue
		draw_rect(Rect2(point, Vector2(2, 2) if big else Vector2.ONE), Color(color, alpha))
		if glint > 0.82 and big: ## a bright mote gets a small cross
			for offset: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_rect(Rect2(point + offset, Vector2.ONE), Color(color, (glint - 0.6) * 2.0))
