class_name DayMotes
extends Node2D
## Daylight counterpart of `Fireflies`: pale gold pollen and light dust floating in the sun. Only inside the
## camera view (+40 px), thickest at midday and in the golden hours (then gold and back-lit), none at night,
## indoors or with the map open. They drift with `WorldWind`. Cosmetic, every peer runs its own, unlit.

const COUNT: int = 40 ## hard safety cap; configured visible population in daylight.json
const MARGIN: float = 40.0
const COLORS: Array[Color] = [Color("fff6d0"), Color("ffe9a0"), Color("ffffff"), Color("ffd98a")]
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
			mote.home = rect.position + Vector2(randf(), randf()) * rect.size
			mote.age = 0.0
		mote.age += delta
		wind = WorldWind.sample(mote.home)
		mote.home += (wind * 14.0 + Vector2(0.0, -1.2)) * delta
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
		var sway: Vector2 = Vector2(sin(_time * mote.speed + mote.phase) * mote.radius, cos(_time * mote.speed * 1.3 + mote.phase) * mote.radius * 0.5)
		var point: Vector2 = (mote.home + sway).round()
		var fade: float = clampf((density - mote.rank) * 6.0, 0.0, 1.0) ## comes and goes with the light
		fade *= smoothstep(0.0, 1.2, mote.age)
		if is_instance_valid(DaylightField.current):
			fade *= pow(DaylightField.current.light_at(point), 1.7)
		var glint: float = pow(0.5 + 0.5 * sin(_time * mote.twinkle_rate + mote.phase * 2.0), 2.0) * fade
		if glint < 0.08:
			continue
		var color: Color = mote.color.lerp(GOLDEN_COLOR, golden)
		var big: bool = mote.rank < 0.10 ## the first half are 2 px motes
		draw_rect(Rect2(point, Vector2(2, 2) if big else Vector2.ONE), Color(color, minf(glint * 1.5, 1.0)))
		if glint > 0.82 and big: ## a bright mote gets a small cross
			for offset: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_rect(Rect2(point + offset, Vector2.ONE), Color(color, (glint - 0.6) * 2.0))
