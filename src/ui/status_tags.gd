class_name StatusTags
extends Control
## The status effects of the local player in the HUD (vine style): above the left end of the health vine a small tag of bark paper hangs from a thread for every effect
## that is on her, with a flame glyph, its name in the effect's colour and a crack of light under it whose length is the time that is left (it jumps and flares when the
## effect is refreshed and stutters in the last second). Reads `StatusEffects` only; nothing is sent.

const TAG_H: int = 17
const GAP: int = 3
const PAPER: Color = Color("120d22")
const PAPER_VOID: Color = Color("07030f")
const CORE_HOT: Color = Color("fff7ff")
const GLYPH: Array[String] = [
	"..#..",
	".##..",
	".###.",
	"#####",
	"#####",
	".###.",
]

const EYE: Array[String] = [
	".....",
	".###.",
	"#.#.#",
	"#.#.#",
	".###.",
	".....",
]

var _effects: StatusEffects
var _time: float = 0.0
var _shown: Dictionary = {} ## id -> 0..1 (how far its tag has dropped in)
var _flare: Dictionary = {} ## id -> 0..1 (a refresh)
var _last_left: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = Unlit.material()
	visible = false


func bind(effects: StatusEffects) -> void:
	_effects = effects


func _process(delta: float) -> void:
	_time += delta
	if _effects == null:
		return
	var any: bool = false
	var ids: Array[String] = _effects.active()
	for id: String in ids:
		var left: float = _effects.left(id)
		if left > float(_last_left.get(id, 0.0)) + 0.2 and not bool(StatusEffects.definition(id).get("permanent", false)): ## a lasting effect is refreshed all the time
			_flare[id] = 1.0
		_last_left[id] = left
		_shown[id] = minf(float(_shown.get(id, 0.0)) + delta * 4.0, 1.0)
		_flare[id] = maxf(float(_flare.get(id, 0.0)) - delta * 3.0, 0.0)
		any = true
	for id: String in _shown.keys():
		if not ids.has(id):
			_shown[id] = float(_shown[id]) - delta * 5.0
			if float(_shown[id]) <= 0.0:
				_shown.erase(id)
				_flare.erase(id)
				_last_left.erase(id)
			any = true
	visible = any
	if any:
		queue_redraw()


func _draw() -> void:
	if _effects == null:
		return
	var void_level: float = VineStyle.void_amount()
	var x: int = 0
	for id: String in _shown.keys():
		var p: float = float(_shown[id])
		if p <= 0.0:
			continue
		var def: Dictionary = StatusEffects.definition(id)
		var tone: Color = Color(String(def.get("color", "ffffff")))
		var hot: Color = Color(String(def.get("hot", "ffffff")))
		var label: String = String(def.get("name", id.to_upper()))
		var total: float = maxf(_effects.total(id), 0.01)
		var left: float = _effects.left(id)
		var frac: float = clampf(left / total, 0.0, 1.0) if _effects.has(id) else 0.0
		if bool(def.get("permanent", false)) and _effects.has(id):
			frac = 0.8 + 0.2 * sin(_time * 1.3) ## no countdown: it breathes
		var flare: float = float(_flare.get(id, 0.0))
		var urgent: bool = left < 1.0 and _effects.has(id)
		var stutter: float = 1.0 if not urgent or fmod(_time * 13.0, 1.0) > 0.25 else 0.35
		var width: int = PixelText.width(label) + 20
		var y: int = int(roundf((1.0 - VineStyle.back_out(p)) * -8.0))
		var a: float = minf(p * 1.5, 1.0)
		_draw_paper(Rect2i(x, y, width, TAG_H), a, void_level, tone)
		_draw_glyph(Vector2i(x + 4, y + 4), tone.lerp(hot, 0.4 + 0.5 * flare), a * stutter, EYE if String(def.get("glyph", "")) == "eye" else GLYPH)
		PixelText.draw(self, label, Vector2i(x + 13, y + 3), Color(tone.lerp(UiStyle.TEXT, 0.35 + 0.4 * flare), a * stutter), Color(VineStyle.OUTLINE, a))
		_draw_crack(x + 4, y + 12, width - 8, frac, tone, hot, a * stutter, flare)
		VineStyle.leaf(self, Vector2(x + width - 2, y + 2), 1, -1, 3, Color(VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), a), Color(VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level), a))
		x += width + GAP


func _draw_glyph(at: Vector2i, color: Color, a: float, shape: Array[String] = GLYPH) -> void:
	var wob: int = int(_time * 9.0) % 2 if shape == GLYPH else 0
	if shape == EYE and fmod(_time, 3.7) > 3.5: ## it blinks
		draw_rect(Rect2(at.x, at.y + 3, 5, 1), Color(color, a))
		return
	for row: int in shape.size():
		var line: String = shape[row]
		for col: int in line.length():
			if line[col] == "#":
				var shift: int = wob if row < 2 and col % 2 == 0 else 0
				draw_rect(Rect2(at.x + col, at.y + row - shift, 1, 1), Color(color, a * (1.0 - 0.1 * float(row))))
	draw_rect(Rect2(at.x + 2, at.y + (2 if shape == EYE else 4), 1, 2), Color(CORE_HOT, a * 0.8))


func _inset(x: int, bottom: bool, width: int, salt: int) -> int:
	var edge: int = mini(x, width - 1 - x)
	return int(VineStyle.rand(x + (31 if bottom else 0) + salt) * 1.7) + maxi(2 - edge, 0)


func _draw_paper(rect: Rect2i, a: float, void_level: float, tone: Color) -> void:
	var fill: Color = PAPER.lerp(PAPER_VOID, void_level)
	var edge: Color = VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level).lerp(tone, 0.3)
	var last_top: int = 0
	var last_bottom: int = 0
	for x: int in rect.size.x:
		var upper: int = _inset(x, false, rect.size.x, rect.size.x)
		var lower: int = rect.size.y - _inset(x, true, rect.size.x, rect.size.x)
		if lower <= upper:
			continue
		draw_rect(Rect2(rect.position.x + x, rect.position.y + upper, 1, lower - upper), Color(fill, 0.95 * a))
		draw_rect(Rect2(rect.position.x + x, rect.position.y + (mini(upper, last_top) if x > 0 else upper), 1, (absi(upper - last_top) + 1) if x > 0 else 1), Color(edge, a))
		draw_rect(Rect2(rect.position.x + x, rect.position.y + upper + 1, 1, 1), Color(tone, 0.35 * a))
		draw_rect(Rect2(rect.position.x + x, rect.position.y + (mini(lower - 1, last_bottom - 1) if x > 0 else lower - 1), 1, (absi(lower - last_bottom) + 1) if x > 0 else 1), Color(edge.darkened(0.3), a))
		if x == 0 or x == rect.size.x - 1:
			draw_rect(Rect2(rect.position.x + x, rect.position.y + upper, 1, lower - upper), Color(edge, a))
		last_top = upper
		last_bottom = lower


func _draw_crack(x0: int, y: int, span: int, frac: float, tone: Color, hot: Color, a: float, flare: float) -> void:
	var length: int = int(ceilf(float(span) * frac))
	for i: int in length:
		var jag: int = int(roundf((sin(float(i) * 0.9 + 1.0) * 0.5 + 0.5) * 1.0))
		draw_rect(Rect2(x0 + i, y + jag - 1, 1, 3), Color(VineStyle.OUTLINE, 0.8 * a))
	for i2: int in length:
		var jag2: int = int(roundf((sin(float(i2) * 0.9 + 1.0) * 0.5 + 0.5) * 1.0))
		var beat: float = VoidGlow.beat(_time - float(i2) * 0.012, 0.0, 1.0)
		draw_rect(Rect2(x0 + i2, y + jag2, 1, 1), Color(tone.lerp(hot, 0.25 + 0.4 * beat + 0.5 * flare), a * (0.65 + 0.35 * beat)))
	if length > 0:
		draw_rect(Rect2(x0 + length - 1, y - 1, 2, 3), Color(CORE_HOT, a))
