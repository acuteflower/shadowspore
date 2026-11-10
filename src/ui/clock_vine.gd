extends Control
## Top left: the day as a vine branch growing out of the left screen edge, left = midnight, middle = noon, right =
## midnight. The sun (by day) or moon (by night) slides along it like a bead, lighting the path it
## has travelled. Both ends of the day lie in the void: black bark, violet veins, tendrils. The
## clock hangs underneath, with the day number and the phase of the day, and under it where she is
## (tile X and Y of the 1100 x 1100 world; switch it off in the settings).

const WIDTH: float = 150.0
const BASE_Y: float = 14.0
const SUN: Color = Color("ffd98a")
const SUN_LIGHT: Color = Color("fff3c4")
const MOON: Color = Color("dcd3ff")
const HANG_X: float = 28.0
const CLOCK_POS: Vector2 = Vector2(56, 27)

var _time: float = 0.0
var _day_pop: float = 0.0 ## 1 -> 0 after a new day begins
var _shown_day: int = 0
var _player: Node2D
var _arc: PackedFloat64Array = PackedFloat64Array()
var _night_profile: PackedFloat64Array = PackedFloat64Array()


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH + 12, 66)
	size = Vector2(WIDTH + 12, 66)
	_arc.resize(int(WIDTH) + 1)
	_night_profile.resize(int(WIDTH) + 1)
	for xi: int in int(WIDTH) + 1:
		_arc[xi] = roundf(arc_y(xi))
		_night_profile[xi] = TimeManager.night_at(xi / WIDTH)
	_shown_day = TimeManager.day
	TimeManager.day_started.connect(func(_d: int) -> void: _day_pop = 1.0)


## `player` is untyped on purpose (the player scene preloads the HUD).
func bind(player: Node) -> void:
	_player = player as Node2D


func _process(delta: float) -> void:
	_time += delta
	_day_pop = maxf(_day_pop - 0.5 * delta, 0.0)
	queue_redraw()


static func arc_y(x: float) -> float:
	return BASE_Y + 7.0 * pow(x / WIDTH, 1.4) + sin(x * 0.09 + 1.0) * 1.4 ## the same easy branch course as the other vines


func _phase_word(t: float) -> String:
	if t >= TimeManager.NIGHT_START or t < TimeManager.NIGHT_END:
		return "NACHT"
	if t < 0.28:
		return "MORGEN"
	if t < 0.72:
		return "TAG"
	return "ABEND"


func _draw() -> void:
	var now: float = TimeManager.time_of_day
	var night: float = TimeManager.night_amount()
	var tone: Color = SUN.lerp(VineStyle.VOID_GLOW, night)

	for xi: int in int(WIDTH) + 1: ## the vine: lit where the day has been, black where the void lies
		var u: float = xi / WIDTH
		var y: float = _arc[xi]
		var n: float = _night_profile[xi]
		var rim: Color = VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, n)
		var extra: int = 1 if xi < 16 else 0 ## thick root at the screen edge, thin tip
		var thin: bool = xi > WIDTH - 14.0
		draw_rect(Rect2(xi, y - 2 - extra + (1 if thin else 0), 1, 5 + 2 * extra - (2 if thin else 0)), rim)
		var body: Color = VineStyle.BARK.lerp(VineStyle.BARK_VOID, n)
		if u <= now:
			body = body.lerp(tone, 0.4)
		draw_rect(Rect2(xi, y - 1 - extra + (1 if thin else 0), 1, 3 + 2 * extra - (2 if thin else 0)), body)
		if xi % 3 != 1:
			draw_rect(Rect2(xi, y - 1, 1, 1), (VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, n)).lerp(tone, 0.35 if u <= now else 0.0))
		if n > 0.5 and VineStyle.rand(xi * 3 + int(_time * 2.0)) < 0.07:
			draw_rect(Rect2(xi, y, 1, 1), VineStyle.VOID_GLOW)

	for k: int in 9: ## leaves, like on the hotbar vine
		var x: float = 6.0 + k * 14.0 + VineStyle.rand(k + 200) * 6.0
		if VineStyle.rand(k + 300) < 0.2 or x > WIDTH - 4.0:
			continue
		var n: float = TimeManager.night_at(x / WIDTH)
		var up: int = -1 if k % 2 == 0 else 1
		VineStyle.leaf(self, Vector2(x, roundf(arc_y(x))) + Vector2(0, up * 2), 1, up, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, n), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, n))

	for hour: float in [0.25, 0.5, 0.75]: ## buds at 06:00, noon and 18:00
		var x: float = hour * WIDTH
		var y: float = roundf(arc_y(x)) - 3.0
		var reached: bool = now >= hour
		draw_rect(Rect2(x, y, 1, 1), VineStyle.PETAL if reached else VineStyle.BARK_LIGHT)
		if reached:
			draw_rect(Rect2(x, y - 1, 1, 1), Color(tone, 0.6))

	for k: int in 4: ## void tendrils at the ends of the day
		var x: float = VineStyle.rand(k + 400) * WIDTH
		var n: float = TimeManager.night_at(x / WIDTH)
		if n > 0.8:
			VineStyle.tendril(self, Vector2(x, arc_y(x)), Vector2(0.3 * (k % 2 * 2 - 1), 0.9 if k % 2 == 0 else -0.9).normalized(), 4 + k % 3 * 2, _time, k)

	_draw_bead(now, night)
	_draw_text(now, night, tone)


func _draw_bead(now: float, night: float) -> void:
	var bead_x: float = clampf(roundf(now * WIDTH), 6.0, WIDTH - 4.0)
	var c: Vector2 = Vector2(bead_x, roundf(arc_y(bead_x)) - 3.0)
	VineStyle.glow(self, c, 12.0, SUN.lerp(VineStyle.VOID_GLOW, night), 0.9 + _day_pop)
	var sun_a: float = 1.0 - night
	if sun_a > 0.02: ## sun: a disc with turning rays
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				if dx * dx + dy * dy <= 9:
					draw_rect(Rect2(c.x + dx, c.y + dy, 1, 1), (SUN_LIGHT if dx + dy < 0 else SUN) * Color(1, 1, 1, sun_a))
		for k: int in 8:
			var angle: float = _time * 0.8 + k * TAU / 8.0
			var reach: float = 5.5 + (1.5 if k % 2 == 0 else 0.0) * (0.6 + 0.4 * sin(_time * 3.0 + k))
			draw_rect(Rect2(roundf(c.x + cos(angle) * reach), roundf(c.y + sin(angle) * reach), 1, 1), Color(SUN_LIGHT, sun_a))
	if night > 0.02: ## moon: a crescent, with stars twinkling around it
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				if dx * dx + dy * dy <= 9 and (dx - 2) * (dx - 2) + (dy + 1) * (dy + 1) > 7:
					draw_rect(Rect2(c.x + dx, c.y + dy, 1, 1), Color(MOON, night))
		for k: int in 5:
			var angle: float = _time * 0.3 + k * 1.3
			var spot: Vector2 = c + Vector2(cos(angle), sin(angle)) * (8.0 + k * 1.5)
			var twinkle: float = 0.5 + 0.5 * sin(_time * 4.0 + k * 2.0)
			draw_rect(Rect2(roundf(spot.x), roundf(spot.y), 1, 1), Color(MOON, night * twinkle))


func _draw_text(now: float, night: float, tone: Color) -> void:
	var clock: String = TimeManager.clock_text()
	if fmod(_time, 1.0) > 0.5: ## the colon blinks
		clock = clock.replace(":", " ")
	var color: Color = VineStyle.PETAL.lerp(VineStyle.LEAF_VOID_LIGHT, night)
	draw_set_transform(CLOCK_POS, 0.0, Vector2(2, 2))
	PixelText.draw(self, clock, Vector2i.ZERO, color, Color(VineStyle.OUTLINE, 1.0).lerp(VineStyle.BARK_VOID_LIGHT, night))
	draw_set_transform(Vector2.ZERO)

	var bounce: float = roundf(sin(_day_pop * PI) * 2.0)
	var day_text: String = "TAG %d" % (TimeManager.day + 1)
	var hang_x: float = HANG_X + roundf(sin(_time * 1.1) * 1.0) ## the day number hangs from the vine like the hotbar pendants
	var hang_n: float = TimeManager.night_at(HANG_X / WIDTH)
	for y: int in range(int(arc_y(HANG_X)) + 2, 37):
		draw_rect(Rect2(HANG_X + roundf(sin(_time * 1.1) * float(y - 33) / 33.0), y, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, hang_n) if y % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, hang_n))
	PixelText.draw(self, day_text, Vector2i(int(hang_x) - PixelText.width(day_text) / 2, 37 - int(bounce)), UiStyle.TEXT_DIM.lerp(SUN_LIGHT, _day_pop).lerp(VineStyle.LEAF_VOID_LIGHT, hang_n * 0.6), VineStyle.OUTLINE)
	if _day_pop > 0.0: ## sparks around the new day
		for k: int in 6:
			var angle: float = k * TAU / 6.0 + _day_pop * 2.0
			var r: float = (1.0 - _day_pop) * 12.0 + 3.0
			draw_rect(Rect2(roundf(hang_x + cos(angle) * r), roundf(41 + sin(angle) * r * 0.6), 1, 1), Color(SUN_LIGHT, _day_pop))
	var word: String = _phase_word(now)
	PixelText.draw(self, word, Vector2i(int(CLOCK_POS.x) + 19 - PixelText.width(word) / 2, 43), Color(tone, 0.85), VineStyle.OUTLINE)
	if _player != null and bool(GameSettings.get_value("position")):
		var tile: Vector2i = Vector2i((_player.global_position / 16.0).floor())
		var where: String = "X %d  Y %d" % [tile.x, tile.y]
		PixelText.draw(self, where, Vector2i(int(CLOCK_POS.x) + 19 - PixelText.width(where) / 2, 54), Color(UiStyle.TEXT_DIM.lerp(VineStyle.LEAF_VOID_LIGHT, night * 0.6), 0.75), VineStyle.OUTLINE)
	var sky: WeatherManager = WeatherManager.current ## the weather, only when it is not plain sunshine
	if sky != null and not (sky.state_id in ["clear", "fair"]):
		var sky_word: String = sky.display_name()
		var row: int = 65 if bool(GameSettings.get_value("position")) and _player != null else 54
		PixelText.draw(self, sky_word, Vector2i(int(CLOCK_POS.x) + 19 - PixelText.width(sky_word) / 2, row), Color(Color(0.66, 0.80, 0.95).lerp(VineStyle.LEAF_VOID_LIGHT, night * 0.5), 0.85), VineStyle.OUTLINE)
