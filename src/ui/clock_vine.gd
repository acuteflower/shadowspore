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
const SLEEP_SEPAL_DARK: Color = Color("233b45")
const SLEEP_SEPAL: Color = Color("3b616b")
const SLEEP_BUD_DARK: Color = Color("463980")
const SLEEP_BUD_MID: Color = Color("6d5eb5")
const SLEEP_BUD_LIGHT: Color = Color("aba0eb")
const SLEEP_PETAL_SHADE: Color = Color("c79846")
const SLEEP_PETAL_GOLD: Color = Color("e0b864")
const SLEEP_PETAL_CREAM: Color = Color("f7e4b2")
const SLEEP_PETAL_LIGHT: Color = Color("fff7df")
const SLEEP_CORE_WARM: Color = Color("e6b95c")
const SLEEP_CORE_HOT: Color = Color("fffbe8")
const SLEEP_BUD_CLOSED: Array[String] = [
	"..L..",
	".LMD.",
	".sMd.",
	".sdd.",
	"..d..",
]
const SLEEP_BUD_OPEN: Array[String] = [
	"LL.LM",
	"LMgMD",
	".gCg.",
	"LMgDD",
	"MD.DS",
]
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


var _redraw_wait: float = 0.0
var _last_step: int = -1


func _process(delta: float) -> void:
	_time += delta
	var pop_active: bool = _day_pop > 0.0
	if pop_active:
		_day_pop = maxf(_day_pop - 0.5 * delta, 0.0)
	_redraw_wait -= delta
	var step: int = int(TimeManager.time_of_day * 512.0) + TimeManager.day * 1024
	if pop_active or _redraw_wait <= 0.0 or step != _last_step:
		_redraw_wait = 0.18
		_last_step = step
		queue_redraw()


static func arc_y(x: float) -> float:
	return BASE_Y + 7.0 * pow(x / WIDTH, 1.4) + sin(x * 0.09 + 1.0) * 1.4 ## the same easy branch course as the other vines


func _phase_word(t: float) -> String:
	if t >= TimeManager.NIGHT_START or t < TimeManager.NIGHT_END:
		return "NACHT"
	if t < 0.28:
		return "MORGEN"
	if t < 0.78:
		return "TAG"
	return "ABEND"


func _draw() -> void:
	var now: float = TimeManager.time_of_day
	var night: float = TimeManager.night_amount()
	var tone: Color = SUN.lerp(VineStyle.VOID_GLOW, night)
	var bud_x: float = clampf(roundf(TimeManager.sleep_unlock_time() * WIDTH), 6.0, WIDTH - 4.0)
	var can_sleep: bool = TimeManager.can_sleep_now()

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
		if up == -1 and absf(x - bud_x) < 6.0:
			continue
		VineStyle.leaf(self, Vector2(x, roundf(arc_y(x))) + Vector2(0, up * 2), 1, up, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, n), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, n))

	for hour: float in [0.25, 0.5, 0.75]: ## buds at 06:00, noon and 18:00
		var x: float = hour * WIDTH
		if absf(x - bud_x) < 5.0:
			continue
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

	if not can_sleep:
		_draw_sleep_bud(bud_x, false)
	_draw_bead(now, night)
	if can_sleep:
		_draw_sleep_bud(bud_x, true)
	_draw_text(now, night, tone)


## Schlaf-Knospe: closed cool-indigo moonflower bud until tired enough, blooming into a warm 4-petal moonflower when sleep unlocks.
func _draw_sleep_bud(bud_x: float, open: bool) -> void:
	var cx: int = int(bud_x)
	var cy: int = int(roundf(arc_y(bud_x))) - 3
	var pulse: float = 0.5 + 0.5 * sin(_time * 2.6)
	if open:
		VineStyle.glow(self, Vector2(float(cx), float(cy)), 8.0, SUN, 0.55 + 0.3 * pulse)
	var rows: Array[String] = SLEEP_BUD_OPEN if open else SLEEP_BUD_CLOSED
	var row_offset: int = -2 if open else -3
	for pass_i: int in 2:
		for row: int in rows.size():
			var line: String = rows[row]
			for col: int in line.length():
				var ch: String = line[col]
				if ch == ".":
					continue
				var px: int = cx + col - 2
				var py: int = cy + row + row_offset
				if pass_i == 0:
					for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						draw_rect(Rect2(float(px + d.x), float(py + d.y), 1.0, 1.0), VineStyle.OUTLINE)
				else:
					draw_rect(Rect2(float(px), float(py), 1.0, 1.0), _sleep_bud_pixel(ch, open, pulse))


func _sleep_bud_pixel(ch: String, open: bool, pulse: float) -> Color:
	match ch:
		"s":
			return SLEEP_SEPAL
		"d":
			return SLEEP_SEPAL_DARK
		"L":
			return SLEEP_PETAL_LIGHT if open else SLEEP_BUD_LIGHT
		"M":
			return SLEEP_PETAL_CREAM if open else SLEEP_BUD_MID
		"D":
			return SLEEP_PETAL_GOLD if open else SLEEP_BUD_DARK
		"S":
			return SLEEP_PETAL_SHADE
		"g":
			return SLEEP_CORE_WARM.lerp(SUN_LIGHT, pulse)
		"C":
			return SUN.lerp(SLEEP_CORE_HOT, 0.4 + 0.6 * pulse)
	return VineStyle.PETAL


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
	_draw_weather(night, word)


## The weather as a little pixel picture right of the phase word (always shown): sun or moon, clouds, rain that falls by its amount, bolt, wind, fog.
func _draw_weather(night: float, word: String) -> void:
	var sky: WeatherManager = WeatherManager.current
	var id: String = sky.state_id if sky != null else "clear"
	var rain: float = sky.rain if sky != null else 0.0
	var storm: float = sky.storm if sky != null else 0.0
	var gloom: float = clampf((sky.cloud if sky != null else 0.0) * 0.7 + storm * 0.4, 0.0, 1.0)
	var o: Vector2 = Vector2(float(int(CLOCK_POS.x) + 19 + PixelText.width(word) / 2 + 7), 40.0)
	var light: Color = Color("eef3ff").lerp(Color("8c93b8"), gloom).lerp(Color("a7a4d4"), night * 0.6)
	var shade: Color = Color("b3c3e0").lerp(Color("5d6488"), gloom).lerp(Color("6e6ca0"), night * 0.6)
	var sun_up: bool = night < 0.5
	match id:
		"clear", "fair":
			_icon_sun_or_moon(o + Vector2(4, 4), night, sun_up)
			if id == "fair":
				_icon_cloud(o + Vector2(4, 4), light, shade, 0.55)
		"broken":
			_icon_sun_or_moon(o + Vector2(2, 3), night, sun_up, 0.7)
			_icon_cloud(o + Vector2(1, 2), light, shade)
		"fog":
			for k: int in 4:
				var shift: float = roundf(sin(_time * 0.8 + float(k) * 1.7) * 1.0)
				draw_rect(Rect2(o.x + 1.0 + (k % 2) * 2.0 + shift, o.y + 1.0 + k * 2.0, 6, 1), Color(light, 0.9 - 0.1 * k))
		"gale":
			for k: int in 3:
				var run: float = fmod(_time * 7.0 + float(k) * 3.0, 14.0)
				draw_rect(Rect2(o.x + run - 3.0, o.y + 1.0 + k * 3.0, 4 if k != 1 else 3, 1), Color(light, 0.9 * clampf(1.0 - absf(run - 6.0) / 8.0, 0.0, 1.0)))
		_:
			_icon_cloud(o + Vector2(1, 0), light, shade)
			if rain > 0.02:
				var drops: int = clampi(1 + int(rain * 5.0), 1, 5) ## more drops, and quicker, the harder it rains
				for k: int in drops:
					var fall: float = fmod(_time * (3.0 + 7.0 * rain) + VineStyle.rand(k + 50) * 6.0 + float(k) * 1.3, 4.0)
					draw_rect(Rect2(o.x + 1.0 + k * 2.0, o.y + 5.0 + floorf(fall), 1, 1), Color(0.62, 0.82, 1.0, 1.0 - fall / 4.5))
			if storm > 0.35 and fmod(_time, 2.3) < 0.9:
				var bolt: Color = Color(1.0, 0.92, 0.5)
				for p: Vector2i in [Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5), Vector2i(4, 6), Vector2i(3, 7)]:
					draw_rect(Rect2(o.x + p.x, o.y + p.y, 1, 1), bolt)


func _icon_sun_or_moon(c: Vector2, night: float, sun_up: bool, big: float = 1.0) -> void:
	if sun_up:
		var r: int = 2 if big > 0.9 else 1
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r + 1:
					draw_rect(Rect2(c.x + dx, c.y + dy, 1, 1), (SUN_LIGHT if dx + dy < 0 else SUN) * Color(1, 1, 1, 1.0 - night))
		for k: int in 8:
			var angle: float = _time * 0.8 + k * TAU / 8.0
			var reach: float = (r + 2.0) + (0.5 if k % 2 == 0 else 0.0)
			draw_rect(Rect2(roundf(c.x + cos(angle) * reach), roundf(c.y + sin(angle) * reach), 1, 1), Color(SUN_LIGHT, (0.9 if big > 0.9 else 0.6) * (1.0 - night)))
	else:
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				if dx * dx + dy * dy <= 5 and (dx - 1) * (dx - 1) + (dy + 1) * (dy + 1) > 3:
					draw_rect(Rect2(c.x + dx, c.y + dy, 1, 1), Color(MOON, night))
		var tw: float = 0.5 + 0.5 * sin(_time * 3.0)
		draw_rect(Rect2(c.x + 3.0, c.y - 3.0, 1, 1), Color(MOON, night * tw))


## A 9 x 4 pixel cloud with an ink outline, lit on top; `puff` < 1 draws a smaller puff of it.
func _icon_cloud(p: Vector2, light: Color, shade: Color, puff: float = 1.0) -> void:
	var rows: PackedStringArray = PackedStringArray(["..XXX....", ".XXXXXX..", "XXXXXXXXX", ".XXXXXXX."])
	if puff < 0.9:
		rows = PackedStringArray([".XX..", "XXXXX", ".XXX."])
		p += Vector2(2, 3)
	for pass_i: int in 2:
		for y: int in rows.size():
			for x: int in rows[y].length():
				if rows[y][x] != "X":
					continue
				if pass_i == 0:
					for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						draw_rect(Rect2(p.x + x + d.x, p.y + y + d.y, 1, 1), Color(VineStyle.OUTLINE, 0.9))
				else:
					draw_rect(Rect2(p.x + x, p.y + y, 1, 1), light if y < rows.size() - 2 else shade)
