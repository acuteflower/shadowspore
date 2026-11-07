class_name SettlerBubble
extends Node2D
## The small speech bubble over a settler's head for what the people of the town say among themselves (docs/town_ausbau.md C16): a ragged bark-paper card with a tail,
## the words in pixel text. No input, nothing pauses; the story's own lines stay in the `SpeechBox`. Unlit, so it reads at night.

const WRAP: int = 24
const LINE_STEP: int = 8
const FADE_IN: float = 0.25
const FADE_OUT: float = 0.5

var _lines: PackedStringArray = PackedStringArray()
var _age: float = 99.0
var _life: float = 3.0
var _salt: int = 0


func _ready() -> void:
	z_index = 30
	material = Unlit.material()
	set_process(false)


func is_showing() -> bool:
	return not _lines.is_empty()


func show_text(text: String, seconds: float) -> void:
	_lines = wrap_text(text)
	_age = 0.0
	_life = seconds
	_salt = text.length() * 7 + int(Time.get_ticks_msec() / 1000)
	set_process(true)
	queue_redraw()


## Greedy wrap at `WRAP` characters (a long word keeps its own line).
static func wrap_text(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var line: String = ""
	for word: String in text.split(" ", false):
		if line != "" and line.length() + 1 + word.length() > WRAP:
			out.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	if line != "":
		out.append(line)
	return out


func _process(delta: float) -> void:
	_age += delta
	if _age > _life + FADE_OUT:
		_lines.clear()
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _lines.is_empty():
		return
	var fade: float = clampf(_age / FADE_IN, 0.0, 1.0) * clampf((_life + FADE_OUT - _age) / FADE_OUT, 0.0, 1.0)
	var width: int = 0
	for line: String in _lines:
		width = maxi(width, PixelText.width(line))
	var w: int = width + 10
	var h: int = _lines.size() * LINE_STEP + 4
	var rect: Rect2 = Rect2(Vector2(-w / 2, -h - 5), Vector2(w, h))
	VineStyle.paper(self, rect, fade, VineStyle.void_amount(), _salt)
	for k: int in 3: ## the tail points down at the speaker
		draw_rect(Rect2(Vector2(-2 + k, -5 + k), Vector2(5 - 2 * k, 1)), Color(VineStyle.BARK_LIGHT, fade))
	for i: int in _lines.size():
		PixelText.draw(self, _lines[i], Vector2i(int(rect.position.x) + 5, int(rect.position.y) + 3 + i * LINE_STEP), Color(VineStyle.PETAL, fade), Color(VineStyle.OUTLINE, fade * 0.8))
