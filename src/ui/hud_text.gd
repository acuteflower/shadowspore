class_name HudText
extends RefCounted
## Readable HUD text (docs/hud_v2_konzept.md 3.H, step 8): `PixelText` with an ink shadow (`1b1a2e` at 55 %, the
## setting HUD-KONTRAST raises it to a full ink rim) and the optional larger 5x7 face (setting GROSSE SCHRIFT, default
## off). Every HUD part that writes words goes through `draw` / `width`, so the switches reach all of them.
## The settings are read by `refresh()` (the HUD calls it on bind and whenever the settings change).

const INK: Color = Color("1b1a2e")
const SHADOW: float = 0.55
const BIG_ADVANCE: int = 6
const BIG_HEIGHT: int = 7
const BIG: Dictionary = {
	"A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
	"B": ["XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."],
	"C": [".XXX.", "X...X", "X....", "X....", "X....", "X...X", ".XXX."],
	"D": ["XXXX.", "X...X", "X...X", "X...X", "X...X", "X...X", "XXXX."],
	"E": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
	"F": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...."],
	"G": [".XXX.", "X...X", "X....", "X.XXX", "X...X", "X...X", ".XXXX"],
	"H": ["X...X", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"],
	"I": [".XXX.", "..X..", "..X..", "..X..", "..X..", "..X..", ".XXX."],
	"J": ["..XXX", "...X.", "...X.", "...X.", "...X.", "X..X.", ".XX.."],
	"K": ["X...X", "X..X.", "X.X..", "XX...", "X.X..", "X..X.", "X...X"],
	"L": ["X....", "X....", "X....", "X....", "X....", "X....", "XXXXX"],
	"M": ["X...X", "XX.XX", "X.X.X", "X.X.X", "X...X", "X...X", "X...X"],
	"N": ["X...X", "XX..X", "X.X.X", "X..XX", "X...X", "X...X", "X...X"],
	"O": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
	"P": ["XXXX.", "X...X", "X...X", "XXXX.", "X....", "X....", "X...."],
	"Q": [".XXX.", "X...X", "X...X", "X...X", "X.X.X", "X..X.", ".XX.X"],
	"R": ["XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"],
	"S": [".XXXX", "X....", "X....", ".XXX.", "....X", "....X", "XXXX."],
	"T": ["XXXXX", "..X..", "..X..", "..X..", "..X..", "..X..", "..X.."],
	"U": ["X...X", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
	"V": ["X...X", "X...X", "X...X", "X...X", "X...X", ".X.X.", "..X.."],
	"W": ["X...X", "X...X", "X...X", "X.X.X", "X.X.X", "X.X.X", ".X.X."],
	"X": ["X...X", "X...X", ".X.X.", "..X..", ".X.X.", "X...X", "X...X"],
	"Y": ["X...X", "X...X", ".X.X.", "..X..", "..X..", "..X..", "..X.."],
	"Z": ["XXXXX", "....X", "...X.", "..X..", ".X...", "X....", "XXXXX"],
	"0": [".XXX.", "X...X", "X..XX", "X.X.X", "XX..X", "X...X", ".XXX."],
	"1": ["..X..", ".XX..", "..X..", "..X..", "..X..", "..X..", ".XXX."],
	"2": [".XXX.", "X...X", "....X", "...X.", "..X..", ".X...", "XXXXX"],
	"3": ["XXXX.", "....X", "....X", ".XXX.", "....X", "....X", "XXXX."],
	"4": ["...X.", "..XX.", ".X.X.", "X..X.", "XXXXX", "...X.", "...X."],
	"5": ["XXXXX", "X....", "XXXX.", "....X", "....X", "X...X", ".XXX."],
	"6": [".XXX.", "X....", "X....", "XXXX.", "X...X", "X...X", ".XXX."],
	"7": ["XXXXX", "....X", "...X.", "..X..", ".X...", ".X...", ".X..."],
	"8": [".XXX.", "X...X", "X...X", ".XXX.", "X...X", "X...X", ".XXX."],
	"9": [".XXX.", "X...X", "X...X", ".XXXX", "....X", "....X", ".XXX."],
	".": [".....", ".....", ".....", ".....", ".....", ".....", "..X.."],
	",": [".....", ".....", ".....", ".....", ".....", "..X..", ".X..."],
	":": [".....", "..X..", ".....", ".....", ".....", "..X..", "....."],
	"!": ["..X..", "..X..", "..X..", "..X..", "..X..", ".....", "..X.."],
	"?": [".XXX.", "X...X", "....X", "...X.", "..X..", ".....", "..X.."],
	"-": [".....", ".....", ".....", ".XXX.", ".....", ".....", "....."],
	"+": [".....", "..X..", "..X..", "XXXXX", "..X..", "..X..", "....."],
	"/": ["....X", "....X", "...X.", "..X..", ".X...", "X....", "X...."],
	"%": ["XX..X", "XX..X", "...X.", "..X..", ".X...", "X..XX", "X..XX"],
	"'": ["..X..", "..X..", ".....", ".....", ".....", ".....", "....."],
	"(": ["...X.", "..X..", ".X...", ".X...", ".X...", "..X..", "...X."],
	")": [".X...", "..X..", "...X.", "...X.", "...X.", "..X..", ".X..."],
	"·": [".....", ".....", ".....", "..X..", ".....", ".....", "....."],
	"→": [".....", "..X..", "...X.", "XXXXX", "...X.", "..X..", "....."],
	"✝": ["..X..", "..X..", "XXXXX", "..X..", "..X..", "..X..", "....."],
}
const ACCENTS: Dictionary = {"Ä": "A", "Ö": "O", "Ü": "U"}

static var shadow: bool = true
static var contrast: bool = false
static var big: bool = false
static var _runs: Dictionary = {} ## glyph -> Array[Rect2] (horizontal runs of the 5x7 face)


## Read the switches from the settings (HUD-KONTRAST, GROSSE SCHRIFT).
static func refresh() -> void:
	contrast = bool(GameSettings.get_value("hud_contrast"))
	big = bool(GameSettings.get_value("hud_big_text"))


static func width(text: String, scale: float = 1.0) -> float:
	if big and scale <= 1.0:
		return float(maxi(text.length() * BIG_ADVANCE - 1, 0))
	return float(PixelText.width(text)) * scale


## Height of one line of text in px (the small face has 5 rows, the big one 7).
static func height(scale: float = 1.0) -> float:
	return float(BIG_HEIGHT) if big and scale <= 1.0 else 5.0 * scale


## `text` with its top-left at `pos` (whole pixels), in `color`; `fade` scales the shadow with the text.
static func draw(canvas: CanvasItem, text: String, pos: Vector2, color: Color, fade: float = 1.0, scale: float = 1.0) -> void:
	if text == "" or color.a <= 0.01:
		return
	var at: Vector2 = pos.round()
	var ink_alpha: float = (0.85 if contrast else SHADOW) * fade * minf(color.a * 1.4, 1.0)
	if big and scale <= 1.0:
		var top: Vector2 = at - Vector2(0.0, 1.0) ## the 7-row face sits one row higher than the 5-row one
		if shadow or contrast:
			_draw_big(canvas, text, top + Vector2(1.0, 1.0), Color(INK, ink_alpha))
			if contrast:
				for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1)]:
					_draw_big(canvas, text, top + d, Color(INK, ink_alpha * 0.8))
		_draw_big(canvas, text, top, color)
		return
	if scale != 1.0:
		canvas.draw_set_transform(at, 0.0, Vector2(scale, scale))
		if shadow or contrast:
			PixelText.draw(canvas, text, Vector2i(1, 1), Color(INK, ink_alpha), Color(INK, ink_alpha * 0.8) if contrast else Color(0, 0, 0, 0))
		PixelText.draw(canvas, text, Vector2i.ZERO, color)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if shadow or contrast:
		PixelText.draw(canvas, text, Vector2i(at) + Vector2i(1, 1), Color(INK, ink_alpha), Color(INK, ink_alpha * 0.8) if contrast else Color(0, 0, 0, 0))
	PixelText.draw(canvas, text, Vector2i(at), color)


## Drop-in for `PixelText.draw` in HUD parts (same arguments): adds the ink shadow (and the contrast rim) but keeps the
## small face, so it is safe under a scaled transform (the clock's big digits).
static func ink(canvas: CanvasItem, text: String, pos: Vector2i, color: Color, outline: Color = Color(0, 0, 0, 0)) -> void:
	if text == "" or color.a <= 0.01:
		return
	if shadow or contrast:
		var ink_alpha: float = (0.85 if contrast else SHADOW) * minf(color.a * 1.4, 1.0)
		PixelText.draw(canvas, text, pos + Vector2i(1, 1), Color(INK, ink_alpha))
	if contrast and outline.a < color.a * 0.8:
		outline = Color(INK, color.a * 0.85)
	PixelText.draw(canvas, text, pos, color, outline)


static func _draw_big(canvas: CanvasItem, text: String, pos: Vector2, color: Color) -> void:
	var x: float = pos.x
	for character: String in text.replace("ß", "SS").to_upper():
		var base: String = String(ACCENTS.get(character, character))
		for run: Rect2 in _glyph_runs(base):
			canvas.draw_rect(Rect2(run.position + Vector2(x, pos.y), run.size), color)
		if ACCENTS.has(character):
			canvas.draw_rect(Rect2(x + 1.0, pos.y - 2.0, 1.0, 1.0), color)
			canvas.draw_rect(Rect2(x + 3.0, pos.y - 2.0, 1.0, 1.0), color)
		x += float(BIG_ADVANCE)


static func _glyph_runs(character: String) -> Array:
	if _runs.has(character):
		return _runs[character] as Array
	var out: Array = []
	var rows: Array = BIG.get(character, []) as Array
	for y: int in rows.size():
		var row: String = String(rows[y])
		var start: int = -1
		for x: int in row.length() + 1:
			var on: bool = x < row.length() and row[x] == "X"
			if on and start < 0:
				start = x
			elif not on and start >= 0:
				out.append(Rect2(float(start), float(y), float(x - start), 1.0))
				start = -1
	_runs[character] = out
	return out
