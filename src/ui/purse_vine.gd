class_name PurseVine
extends Control
## Money, top right: a branch grows out of the right side of the screen, with the
## money hanging from it as glowing seed-coins on threads (gold, silver, copper; zero amounts fade
## away). Numbers roll up on a gain, the coin yanks its thread, sparks fly and "+1S 20K" floats up.
## At night the void creeps in from the branch's tip like on every vine.

const LENGTH: float = 96.0
const BASE_Y: float = 10.0
const FIRST_X: float = 24.0
const GAP: float = 26.0
const COIN: PackedStringArray = [
	".XXXX.",
	"XLXXXX",
	"XLXXXX",
	"XXXXXX",
	"XXXXXX",
	".XXXX.",
]
const COINS: Array[Array] = [
	[Color("f2c14e"), Color("fff3b0")], # gold: body, shine
	[Color("b8c4d8"), Color("f4f8ff")], # silver
	[Color("d6874a"), Color("ffcf9a")], # copper
]
const FLIP_WIDTHS: Array[int] = [6, 4, 2, 4, 6]

var _progress: ProgressComponent
var _time: float = 0.0
var _last: Vector3i = Vector3i.ZERO
var _last_total: int = 0
var _shown: Array[float] = [0.0, 0.0, 0.0]
var _x: Array[float] = [FIRST_X, FIRST_X, FIRST_X]
var _alpha: Array[float] = [0.0, 0.0, 0.0]
var _pop: Array[float] = [0.0, 0.0, 0.0]
var _gain_text: String = ""
var _gain_age: float = 9.0


func _ready() -> void:
	custom_minimum_size = Vector2(LENGTH + 56, 68)
	size = Vector2(LENGTH + 56, 68)


func bind(progress: ProgressComponent) -> void:
	_progress = progress
	_last = Currency.split(progress.copper)
	_last_total = progress.copper
	for i: int in 3:
		_shown[i] = _last[i]
		_alpha[i] = 1.0 if _visible(i, _last) else 0.0
	_place(true)
	progress.changed.connect(_on_changed)


func _on_changed() -> void:
	var now: Vector3i = Currency.split(_progress.copper)
	for i: int in 3:
		if now[i] != _last[i]:
			_pop[i] = 1.0
	if _progress.copper > _last_total:
		_gain_text = "+" + Currency.short_text(_progress.copper - _last_total)
		_gain_age = 0.0
	_last = now
	_last_total = _progress.copper


func _visible(i: int, parts: Vector3i) -> bool:
	return parts[i] > 0 or (i == 2 and parts.x == 0 and parts.y == 0)


## Visible amounts sit next to each other from the root; the others fade out of the way.
func _place(snap: bool = false, delta: float = 0.0) -> void:
	var slot: int = 0
	for i: int in 3:
		var shown: bool = _visible(i, _last)
		if shown:
			var target: float = FIRST_X + slot * GAP
			_x[i] = target if snap else lerpf(_x[i], target, 1.0 - exp(-10.0 * delta))
			slot += 1
		_alpha[i] = (1.0 if shown else 0.0) if snap else move_toward(_alpha[i], 1.0 if shown else 0.0, 3.0 * delta)


func _process(delta: float) -> void:
	_time += delta
	_gain_age += delta
	if _progress != null:
		_place(false, delta)
		for i: int in 3:
			_pop[i] = maxf(_pop[i] - 1.8 * delta, 0.0)
			_shown[i] = move_toward(_shown[i], _last[i], maxf(absf(_last[i] - _shown[i]) * 6.0, 6.0) * delta)
	queue_redraw()


static func branch_y(x: float) -> float:
	return BASE_Y + 7.0 * pow(x / LENGTH, 1.4) + sin(x * 0.11) * 1.2


func _a(color: Color, alpha: float) -> Color:
	return Color(color, color.a * alpha)


func _draw() -> void:
	if _progress == null:
		return
	draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1, 1)) ## drawn growing right, mirrored so it grows from the right edge
	var void_level: float = VineStyle.void_amount()

	for xi: int in int(LENGTH) + 1: ## the branch, thick at the screen edge, thin at the tip
		var u: float = xi / LENGTH
		var thick: int = 5 if u < 0.1 else (4 if u < 0.3 else (3 if u < 0.6 else (2 if u < 0.88 else 1)))
		var y: float = roundf(branch_y(xi)) - thick / 2
		var taken: float = VineStyle.infection(LENGTH - xi, void_level, xi / 2)
		draw_rect(Rect2(xi, y - 1, 1, thick + 2), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		draw_rect(Rect2(xi, y, 1, thick), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if xi % 3 != 1:
			draw_rect(Rect2(xi, y, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		if taken > 0.5 and VineStyle.rand(xi * 3 + int(_time * 2.0)) < 0.07:
			draw_rect(Rect2(xi, y + thick / 2, 1, 1), VineStyle.VOID_GLOW)

	for k: int in 6: ## leaves
		var x: float = 14.0 + k * 14.0 + VineStyle.rand(k + 800) * 6.0
		if VineStyle.rand(k + 850) < 0.2 or x > LENGTH - 6.0:
			continue
		var taken: float = VineStyle.infection(LENGTH - x, void_level, k)
		var up: int = -1 if k % 2 == 0 else 1
		VineStyle.leaf(self, Vector2(x, roundf(branch_y(x))) + Vector2(0, up * 2), 1, up, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, taken))

	var tip: Vector2 = Vector2(LENGTH, roundf(branch_y(LENGTH))) ## a bud at the tip
	var tip_taken: float = VineStyle.infection(0.0, void_level, 3)
	VineStyle.glow(self, tip, 5.0, VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, tip_taken), 0.7)
	draw_rect(Rect2(tip, Vector2.ONE), VineStyle.PETAL)
	if void_level > 0.05:
		for k: int in 3:
			VineStyle.tendril(self, Vector2(LENGTH * (0.55 + 0.18 * k), branch_y(LENGTH * (0.55 + 0.18 * k))), Vector2(0.4, 0.9 if k % 2 == 0 else -0.9).normalized(), int(3 + 6 * void_level), _time, k)

	for i: int in 3:
		if _alpha[i] > 0.02:
			_draw_coin(i, void_level)

	if _gain_age < 1.6: ## "+1S 20K" floats up from the tip
		var fade: float = 1.0 - _gain_age / 1.6
		_text(_gain_text, Vector2i(int(LENGTH) + 8, int(tip.y) - 4 - int(_gain_age * 8.0)), Color(VineStyle.WARM_GLOW, fade), Color(VineStyle.OUTLINE, fade))


## Text is not mirrored: `pos` is where its left edge would be in the unmirrored drawing.
func _text(text: String, pos: Vector2i, color: Color, outline: Color) -> void:
	draw_set_transform(Vector2.ZERO)
	PixelText.draw(self, text, Vector2i(int(size.x) - pos.x - PixelText.width(text), pos.y), color, outline)
	draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1, 1))


func _draw_coin(i: int, void_level: float) -> void:
	var a: float = _alpha[i]
	var x: float = _x[i]
	var taken: float = VineStyle.infection(LENGTH - x, void_level, i)
	var colors: Array = COINS[i]
	var anchor: Vector2 = Vector2(roundf(x), roundf(branch_y(x)))
	var yank: float = sin(_pop[i] * PI) * 3.0
	var center: Vector2 = Vector2(anchor.x + roundf(sin(_time * 1.2 + i * 1.9) * 1.2), anchor.y + 9.0 + VineStyle.rand(i + 90) * 4.0 + yank)

	var steps: int = int(center.y - 3.0 - anchor.y)
	for s: int in range(1, steps): ## thread
		var tx: float = anchor.x + (center.x - anchor.x) * float(s) / steps
		draw_rect(Rect2(roundf(tx), anchor.y + s, 1, 1), _a(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if s % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), a))
	draw_rect(Rect2(center.x - 1, center.y - 4, 3, 1), _a(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, taken), a)) ## leaf cap holds the coin

	var halo: Color = (colors[0] as Color).lerp(VineStyle.VOID_GLOW, taken * 0.6)
	VineStyle.glow(self, center, 9.0, halo, (0.45 + _pop[i] * 0.6) * a)

	var flip: float = fposmod(_time * 0.2 + i * 0.31, 1.0) ## now and then the coin turns on its thread
	var width: int = FLIP_WIDTHS[int(flip / 0.08 * FLIP_WIDTHS.size())] if flip < 0.08 else 6
	var left: float = center.x - width / 2.0
	for cx: int in width:
		var source: int = mini(int(float(cx) * 6.0 / width), 5)
		for cy: int in 6:
			var cell: String = COIN[cy][source]
			if cell != ".":
				var base: Color = colors[1] if cell == "L" else colors[0]
				draw_rect(Rect2(floorf(left) + cx, center.y - 3.0 + cy, 1, 1), _a(base.lerp(VineStyle.LEAF_VOID_LIGHT, taken * 0.3), a))

	if _pop[i] > 0.0: ## sparks
		for k: int in 5:
			var angle: float = k * TAU / 5.0 + _time * 3.0
			var r: float = (1.0 - _pop[i]) * 9.0 + 4.0
			draw_rect(Rect2(roundf(center.x + cos(angle) * r), roundf(center.y + sin(angle) * r), 1, 1), _a(colors[1], _pop[i] * a))

	var text: String = str(roundi(_shown[i]))
	_text(text, Vector2i(roundi(center.x) - PixelText.width(text) / 2, roundi(center.y) + 5), _a(UiStyle.TEXT.lerp(VineStyle.LEAF_VOID_LIGHT, taken * 0.5), a), _a(VineStyle.OUTLINE, a))
