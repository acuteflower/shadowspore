extends Control
## Blink skill: a void crystal hanging from the end of the hotbar vine. It fills with violet
## light from the bottom while recharging (shards orbit it, the seconds left glow inside), and
## the bound key hangs under it. Pressing punches it down; becoming ready sends a ring of
## sparks outwards and makes it glow and breathe.

const WIDTH: int = 28
const HEIGHT: int = 44
const ANCHOR_X: float = 14.0
const ACTION: String = "blink"

const DIM: Color = Color("3a1f66")
const BRIGHT: Color = Color("9b5cff")
const CORE: Color = Color("e7c8ff")
const GLYPH: PackedStringArray = [
	"...X...",
	"..XXX..",
	".XXLXX.",
	"XXXLXXX",
	"XXXLXXX",
	".XXLXX.",
	"..XXX..",
	"...X...",
]

var _blink: BlinkComponent
var _key: String = ""
var _press: float = 0.0
var _ring: float = 0.0 ## 1 -> 0 after becoming ready
var _was_ready: bool = true
var _time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)


func bind(blink: BlinkComponent) -> void:
	_blink = blink
	_key = _hotkey()
	blink.cooldown_changed.connect(_on_cooldown)


func _on_cooldown(_left: float, _total: float) -> void:
	var now_ready: bool = _blink.is_ready()
	if _was_ready and not now_ready:
		_press = 1.0
	elif now_ready and not _was_ready:
		_ring = 1.0
	_was_ready = now_ready


func _process(delta: float) -> void:
	_time += delta
	_press = maxf(_press - 4.0 * delta, 0.0)
	_ring = maxf(_ring - 1.8 * delta, 0.0)
	queue_redraw()


func _hotkey() -> String:
	return VineStyle.key_name(ACTION, "?")


func _draw() -> void:
	if _blink == null:
		return
	var ready_now: bool = _blink.is_ready()
	var charged: float = 1.0 - _blink.cooldown_left / _blink.cooldown
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.5)
	var taken: float = VineStyle.infection(SapVine.STAMINA_LEN + 12.0, VineStyle.void_amount(), 77)
	var anchor: Vector2 = Vector2(ANCHOR_X, Hotbar.vine_y(Hotbar.SKILL_X))
	var bob: float = sin(_time * 1.6) * 1.2
	var top: float = roundf(anchor.y + 8.0 + bob + _press * 3.0)
	var center: Vector2 = Vector2(ANCHOR_X, top + GLYPH.size() / 2.0)

	for y: int in range(int(anchor.y) + 1, int(top)): ## thread
		draw_rect(Rect2(ANCHOR_X, y, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken) if y % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))

	VineStyle.glow(self, center, 13.0 if ready_now else 8.0, BRIGHT, (0.55 + 0.35 * pulse if ready_now else 0.2 + 0.3 * charged) + _press * 0.5)

	var origin: Vector2 = Vector2(ANCHOR_X - GLYPH[0].length() / 2.0, top).floor()
	for y: int in GLYPH.size():
		var lit: bool = float(y) + 1.0 > GLYPH.size() * (1.0 - charged)
		for x: int in GLYPH[y].length():
			var cell: String = GLYPH[y][x]
			if cell == ".":
				continue
			var color: Color = VineStyle.BARK_VOID.lerp(DIM, 0.8)
			if lit:
				color = CORE if cell == "L" else BRIGHT
				if ready_now and cell == "L":
					color = color.lerp(Color.WHITE, pulse)
				if _press > 0.0:
					color = color.lerp(Color.WHITE, _press)
			draw_rect(Rect2(origin + Vector2(x, y), Vector2.ONE), color)
	draw_rect(Rect2(origin + Vector2(-1, 3), Vector2.ONE), VineStyle.OUTLINE) ## dark rim around the widest rows
	draw_rect(Rect2(origin + Vector2(7, 3), Vector2.ONE), VineStyle.OUTLINE)

	if not ready_now:
		for k: int in 2: ## shards orbit the recharging crystal
			var angle: float = _time * 2.4 + k * PI
			draw_rect(Rect2(roundf(center.x + cos(angle) * 8.0), roundf(center.y + sin(angle) * 5.0), 1, 1), Color(CORE, 0.4 + 0.6 * charged))
		var seconds: String = str(ceili(_blink.cooldown_left))
		PixelText.draw(self, seconds, Vector2i(roundi(center.x) - PixelText.width(seconds) / 2, roundi(center.y) - 4), UiStyle.TEXT, VineStyle.OUTLINE)

	if _ring > 0.0: ## sparks fly outwards on becoming ready
		var radius: float = (1.0 - _ring) * 14.0 + 4.0
		for k: int in 12:
			var angle: float = k * TAU / 12.0 + 0.3
			draw_rect(Rect2(roundf(center.x + cos(angle) * radius), roundf(center.y + sin(angle) * radius * 0.8), 1, 1), Color(CORE, _ring))

	var key_color: Color = UiStyle.TEXT.lerp(Color.WHITE, _press) if ready_now else UiStyle.TEXT_DIM ## plain label like the hotbar numbers, no cap
	PixelText.draw(self, _key, Vector2i(roundi(ANCHOR_X - PixelText.width(_key) / 2.0), int(top) + GLYPH.size() + 5), key_color, VineStyle.OUTLINE)
