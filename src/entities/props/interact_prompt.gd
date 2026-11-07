class_name InteractPrompt
extends Node2D
## The tag that floats above something the player can use, in the vine style: a leaf of dark bark paper with a
## ragged edge (like the item cards) that rises into place, the shared key cap (`VineStyle.key_cap`, breathing teal,
## two petals open on its shoulders), the verb beside it, a leaf on one corner and a short thread with a bud
## hanging down towards the object. By night the void tints it and creeps over a corner. Unlit, always on top.

const PAPER: Color = Color("120d22")
const PAPER_VOID: Color = Color("07030f")
const HEIGHT: int = 13
const RISE_SECONDS: float = 0.22
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
	return VineStyle.key_name("interact", "E")


func _inset(x: int, bottom: bool, width: int) -> int:
	var edge: int = mini(x, width - 1 - x)
	return int(VineStyle.rand(x + (31 if bottom else 0) + _text.length()) * 1.7) + maxi(2 - edge, 0)


func _draw() -> void:
	if _text == "":
		return
	var rise: float = 1.0 - pow(1.0 - clampf(_age / RISE_SECONDS, 0.0, 1.0), 3.0)
	var void_level: float = VineStyle.void_amount()
	var width: int = PixelText.width(_text) + VineStyle.cap_width(_key) + 10
	var bob: float = roundf(sin(_time * 2.2))
	var left: int = -width / 2
	var top: int = -HEIGHT - 3 - THREAD + int(roundf((1.0 - rise) * 5.0 + bob))
	draw_set_transform(Vector2.ZERO)
	var alpha: float = rise
	_draw_thread(top, alpha, void_level)
	_draw_paper(left, top, width, alpha, void_level)
	_draw_key(Vector2(left + 3, top + 1), alpha, void_level)
	PixelText.draw(self, _text, Vector2i(left + VineStyle.cap_width(_key) + 6, top + 3), Color(UiStyle.TEXT, alpha), Color(VineStyle.OUTLINE, alpha))
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


## The key cap (the same as everywhere in the HUD), breathing with a soft teal light; a few petals open around it.
func _draw_key(at: Vector2, alpha: float, void_level: float) -> void:
	var open: float = clampf((_age - 0.05) / 0.25, 0.0, 1.0)
	var breathe: float = 0.5 + 0.5 * sin(_time * 3.0)
	var w: int = VineStyle.key_cap(self, at, _key, alpha, 0.2 + 0.25 * breathe, void_level)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(w, -1)]: ## two petals on its shoulders
		draw_rect(Rect2(at + corner, Vector2.ONE), Color(VineStyle.PETAL, alpha * open * (0.5 + 0.5 * breathe)))


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
