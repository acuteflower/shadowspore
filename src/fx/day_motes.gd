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
const RESONANCE_COLORS: Array[Color] = [Color("78f4e6"), Color("d0fff8"), Color("ffd86b"), Color("ffeaa0")]
const ARCANE_STORM_COLORS: Array[Color] = [Color("cbaaff"), Color("9468ee"), Color("78f4e6"), Color("ffb84a")]


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
	var base: float = clampf(0.9 * TimeManager.sun_amount() + 0.9 * TimeManager.golden_amount(), 0.0, 1.0)
	var magic_desert: float = maxf(WeatherManager.resonance_now() * 0.88, WeatherManager.arcane_storm_now() * 0.96)
	return maxf(base, magic_desert)


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
		var res_m: float = maxf(WeatherManager.resonance_now(), WeatherManager.arcane_storm_now()) * desert_m
		wind = WorldWind.sample(mote.home) if desert_m <= 0.001 else WorldWind.sample_soft(mote.home)
		var wind_mul: float = lerpf(lerpf(14.0, 1.4, desert_m), 18.0, res_m)
		var rise_y: float = lerpf(lerpf(-1.2, 0.0, desert_m), -3.2, res_m)
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
		var res_now: float = WeatherManager.resonance_now() * desert_t
		var arc_now: float = WeatherManager.arcane_storm_now() * desert_t
		var magic_t: float = clampf(maxf(res_now, arc_now), 0.0, 1.0)
		var on_q: bool = desert_t > 0.25 and BiomeBlend.is_quartz_surface(point)
		var eff_density: float = density * lerpf(lerpf(1.0, 0.28 if on_q else 0.10, desert_t), 0.95 if on_q else 0.72, magic_t)
		if mote.rank > eff_density:
			continue
		var fade: float = clampf((eff_density - mote.rank) * 6.0, 0.0, 1.0) ## comes and goes with the light
		fade *= smoothstep(0.0, 1.2, mote.age)
		if is_instance_valid(DaylightField.current) and magic_t < 0.25:
			fade *= pow(DaylightField.current.light_at(point), 1.7)
		var rate: float = mote.twinkle_rate * lerpf(lerpf(1.0, 0.45, desert_t), 1.65, magic_t)
		var glint: float = pow(0.5 + 0.5 * sin(_time * rate + mote.phase * 2.0), 2.0) * fade
		if glint < 0.08:
			continue
		var base_col: Color = mote.color.lerp(DESERT_COLOR, desert_t)
		var color: Color = base_col.lerp(GOLDEN_COLOR, golden * (1.0 - 0.45 * desert_t))
		if magic_t > 0.08:
			var idx_c: int = int(roundf(mote.rank * 37.0)) % 4
			var spark_col: Color = ARCANE_STORM_COLORS[idx_c] if arc_now > res_now else RESONANCE_COLORS[idx_c]
			color = color.lerp(spark_col, clampf(magic_t * 1.25, 0.0, 1.0))
		var big: bool = (mote.rank < 0.10 and desert_t < 0.30) or (magic_t > 0.35 and mote.rank < 0.18 and on_q)
		var alpha_cap: float = lerpf(lerpf(1.0, 0.28 if on_q else 0.15, desert_t), 0.88 if on_q else 0.68, magic_t)
		var alpha: float = minf(glint * lerpf(lerpf(1.5, 0.38, desert_t), 1.35, magic_t), alpha_cap)
		if alpha < 0.04:
			continue
		draw_rect(Rect2(point, Vector2(2, 2) if big else Vector2.ONE), Color(color, alpha))
		if glint > 0.82 and big: ## a bright mote gets a small cross
			for offset: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_rect(Rect2(point + offset, Vector2.ONE), Color(color, (glint - 0.6) * 2.0))
