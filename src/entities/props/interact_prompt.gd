class_name InteractPrompt
extends Node2D
## The tag that floats above something the player can use, in the vine style: a leaf of dark bark paper with a
## ragged edge (like the item cards) that rises into place, a glowing flower bud holding the key (its petals open
## as the tag appears, then breathe), the verb beside it, a leaf on one corner and a short thread with a bud
## hanging down towards the object. By night the void tints it and creeps over a corner. Unlit, always on top.

const PAPER: Color = Color("120d22")
const PAPER_VOID: Color = Color("07030f")
const HEIGHT: int = 13
const RISE_SECONDS: float = 0.22
const BUD_RADIUS: int = 4
const THREAD: int = 5
const GAMEPAD_KEY: String = "Y"

var _text: String = ""
var _key: String = "E"
var _age: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	z_index = 40
	material = Unlit.material()
	set_process(false)


func show_text(text: String) -> void:
	if text != "" and _text == "":
		_age = 0.0
		_key = _key_label()
	_text = text
	visible = text != ""
	set_process(visible)
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	_time += delta
	queue_redraw()


## The key on the cap: the bound keyboard key, or the gamepad's button while a pad is in use.
func _key_label() -> String:
	if not InputManager.using_mouse:
		return GAMEPAD_KEY
	for event: InputEvent in InputMap.action_get_events("interact"):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			var code: Key = key.keycode if key.keycode != KEY_NONE else DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			return OS.get_keycode_string(code).to_upper().left(1)
	return "E"


func _inset(x: int, bottom: bool, width: int) -> int:
	var edge: int = mini(x, width - 1 - x)
	return int(VineStyle.rand(x + (31 if bottom else 0) + _text.length()) * 1.7) + maxi(2 - edge, 0)


func _draw() -> void:
	if _text == "":
		return
	var rise: float = 1.0 - pow(1.0 - clampf(_age / RISE_SECONDS, 0.0, 1.0), 3.0)
	var void_level: float = VineStyle.void_amount()
	var width: int = PixelText.width(_text) + 2 * BUD_RADIUS + 15
	var bob: float = roundf(sin(_time * 2.2))
	var left: int = -width / 2
	var top: int = -HEIGHT - 3 - THREAD + int(roundf((1.0 - rise) * 5.0 + bob))
	draw_set_transform(Vector2.ZERO)
	var alpha: float = rise
	_draw_thread(top, alpha, void_level)
	_draw_paper(left, top, width, alpha, void_level)
	_draw_bud(Vector2(left + BUD_RADIUS + 3, top + HEIGHT / 2.0), rise, alpha)
	PixelText.draw(self, _text, Vector2i(left + 2 * BUD_RADIUS + 10, top + 3), Color(UiStyle.TEXT, alpha), Color(VineStyle.OUTLINE, alpha))
	VineStyle.leaf(self, Vector2(left + width - 2, top + 2), 1, -1, 3, Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), alpha), Color(VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level), alpha))
	if void_level > 0.3:
		VineStyle.tendril(self, Vector2(left + 1, top + HEIGHT - 2), Vector2(-0.8, 0.6).normalized(), int(2 + 4 * void_level), _time, _text.length())


func _draw_paper(left: int, top: int, width: int, alpha: float, void_level: float) -> void:
	var fill: Color = PAPER.lerp(PAPER_VOID, void_level)
	var edge: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level)
	var last_top: int = 0
	var last_bottom: int = 0
	for x: int in width:
		var upper: int = _inset(x, false, width)
		var lower: int = HEIGHT - _inset(x, true, width)
		if lower <= upper:
			continue
		draw_rect(Rect2(left + x, top + upper, 1, lower - upper), Color(fill, 0.95 * alpha))
		draw_rect(Rect2(left + x, top + mini(upper, last_top) if x > 0 else top + upper, 1, (absi(upper - last_top) + 1) if x > 0 else 1), Color(edge, alpha))
		draw_rect(Rect2(left + x, top + upper + 1, 1, 1), Color(UiStyle.ACCENT, 0.55 * alpha)) ## a lit edge on top
		draw_rect(Rect2(left + x, top + (mini(lower - 1, last_bottom - 1) if x > 0 else lower - 1), 1, (absi(lower - last_bottom) + 1) if x > 0 else 1), Color(edge.darkened(0.3), alpha))
		if x == 0 or x == width - 1:
			draw_rect(Rect2(left + x, top + upper, 1, lower - upper), Color(edge, alpha))
		last_top = upper
		last_bottom = lower


## The key's flower bud: a teal disc with the letter, four petals that open out and then breathe.
func _draw_bud(center: Vector2, rise: float, alpha: float) -> void:
	var open: float = clampf((_age - 0.05) / 0.25, 0.0, 1.0)
	var breathe: float = 0.5 + 0.5 * sin(_time * 3.0)
	VineStyle.glow(self, center, 8.0, UiStyle.ACCENT, (0.55 + 0.3 * breathe) * alpha)
	var reach: float = (BUD_RADIUS + 1.0 + open * 1.0 + breathe * 0.6)
	for offset: Vector2 in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]: ## petals
		draw_rect(Rect2(center + offset * reach - Vector2(0.5, 0.5) + Vector2(0.5, 0.5), Vector2.ONE), Color(VineStyle.PETAL, alpha * open))
	for y: int in range(-BUD_RADIUS, BUD_RADIUS + 1):
		for x: int in range(-BUD_RADIUS, BUD_RADIUS + 1):
			var d: float = x * x + y * y
			if d <= BUD_RADIUS * BUD_RADIUS + 1:
				var lit: float = -(x + y) / float(BUD_RADIUS * 2)
				draw_rect(Rect2(roundf(center.x) + x - 1, roundf(center.y) + y - 1, 1, 1), Color(UiStyle.ACCENT.lightened(0.25 * lit) if d < BUD_RADIUS * BUD_RADIUS - 2 else UiStyle.ACCENT.darkened(0.35), alpha))
	PixelText.draw(self, _key, Vector2i(roundi(center.x) - PixelText.width(_key) / 2 - 1, roundi(center.y) - 4), Color(VineStyle.OUTLINE, alpha))


## A thread with a bud hangs from the tag towards the object, swaying a little.
func _draw_thread(top: int, alpha: float, void_level: float) -> void:
	var sway: float = sin(_time * 1.6) * 1.0
	for y: int in range(top + HEIGHT - 1, top + HEIGHT + THREAD):
		var k: float = float(y - (top + HEIGHT - 1)) / THREAD
		var color: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level) if y % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, void_level)
		draw_rect(Rect2(roundf(sway * k), y, 1, 1), Color(color, alpha))
	var tip: Vector2 = Vector2(roundf(sway), top + HEIGHT + THREAD)
	VineStyle.glow(self, tip, 4.0, UiStyle.ACCENT, 0.6 * alpha)
	draw_rect(Rect2(tip, Vector2.ONE), Color(VineStyle.PETAL, alpha))
