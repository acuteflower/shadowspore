class_name SettlerBubble
extends Node2D
## The small speech bubble over a settler's head for what the people of the town say among themselves (docs/town_ausbau.md C16): a ragged bark-paper card with a tail,
## the words in pixel text. No input, nothing pauses; the story's own lines stay in the `SpeechBox`. Unlit, so it reads at night.

signal finished

const WRAP: int = 24
const MAX_WIDTH_PX: int = 168
const LINE_STEP: int = 8
const FADE_IN: float = 0.22
const FADE_OUT: float = 0.35
const TYPE_RATE: float = 48.0

var _lines: PackedStringArray = PackedStringArray()
var _speaker: String = ""
var _age: float = 99.0
var _life: float = 3.0
var _hold_age: float = 0.0
var _salt: int = 0
var _instant: bool = true
var _typed: float = 0.0
var _full_len: int = 0
var _type_done: bool = true
var _done_emitted: bool = true


func _ready() -> void:
	z_index = 30
	material = Unlit.material()
	set_process(false)


func is_showing() -> bool:
	return not _lines.is_empty()


func show_text(text: String, seconds: float) -> void:
	_lines = wrap_text(text)
	_speaker = ""
	_age = 0.0
	_life = seconds
	_hold_age = 0.0
	_salt = text.length() * 7 + int(Time.get_ticks_msec() / 1000)
	_instant = true
	_type_done = true
	_full_len = 0
	for row: String in _lines:
		_full_len += row.length()
	_typed = float(_full_len)
	_done_emitted = false
	set_process(true)
	queue_redraw()


func show_speech(speaker: String, text: String, seconds: float = -1.0) -> void:
	_lines = wrap_px(text, MAX_WIDTH_PX)
	_speaker = speaker.to_upper()
	_age = 0.0
	_life = seconds if seconds >= 0.0 else clampf(1.5 + float(text.length()) * 0.045, 1.9, 6.8)
	_hold_age = 0.0
	_salt = text.length() * 7 + int(Time.get_ticks_msec() / 1000)
	_instant = false
	_full_len = 0
	for row: String in _lines:
		_full_len += row.length()
	_typed = 0.0
	_type_done = _full_len == 0
	_done_emitted = false
	set_process(true)
	queue_redraw()


func finish_or_advance() -> bool:
	if _lines.is_empty():
		return false
	if not _type_done:
		_typed = float(_full_len)
		_type_done = true
		queue_redraw()
		return true
	clear_now()
	return true


func clear_now() -> void:
	_lines.clear()
	_speaker = ""
	_instant = true
	_type_done = true
	set_process(false)
	if not _done_emitted:
		_done_emitted = true
		finished.emit()
	queue_redraw()


## Pixel-width word wrap for story bubbles (keeps each row within `max_px`).
static func wrap_px(text: String, max_px: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var row: String = ""
	for word: String in text.split(" ", false):
		var tryout: String = word if row == "" else row + " " + word
		if PixelText.width(tryout) > max_px and row != "":
			out.append(row)
			row = word
		else:
			row = tryout
	if row != "":
		out.append(row)
	return out


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
	if _instant:
		if _age > _life + FADE_OUT:
			_lines.clear()
			set_process(false)
			if not _done_emitted:
				_done_emitted = true
				finished.emit()
	else:
		if not _type_done:
			_typed = minf(_typed + TYPE_RATE * delta, float(_full_len))
			if int(_typed) >= _full_len:
				_type_done = true
		else:
			_hold_age += delta
			if _hold_age >= _life + FADE_OUT:
				_lines.clear()
				_speaker = ""
				set_process(false)
				if not _done_emitted:
					_done_emitted = true
					finished.emit()
	queue_redraw()


func _draw() -> void:
	if _lines.is_empty():
		return
	var fade_out_t: float = (_life + FADE_OUT - _age) if _instant else (_life + FADE_OUT - _hold_age)
	var fade: float = clampf(_age / FADE_IN, 0.0, 1.0) * clampf(fade_out_t / FADE_OUT, 0.0, 1.0)
	if fade <= 0.0:
		return
	var width: int = 0
	if _speaker != "":
		width = maxi(width, PixelText.width(_speaker))
	for line: String in _lines:
		width = maxi(width, PixelText.width(line))
	var header_h: int = 10 if _speaker != "" else 0
	var w: int = width + 10
	var h: int = _lines.size() * LINE_STEP + 4 + header_h
	var rect: Rect2 = Rect2(Vector2(-w / 2, -h - 5), Vector2(w, h))
	VineStyle.paper(self, rect, fade, VineStyle.void_amount(), _salt)
	for k: int in 3: ## the tail points down at the speaker
		draw_rect(Rect2(Vector2(-2 + k, -5 + k), Vector2(5 - 2 * k, 1)), Color(VineStyle.BARK_LIGHT, fade))
	if _speaker != "":
		PixelText.draw(self, _speaker, Vector2i(int(rect.position.x) + 5, int(rect.position.y) + 3), Color(VineStyle.WARM_GLOW, fade), Color(VineStyle.OUTLINE, fade * 0.85))
	var remaining: int = _full_len if _instant else int(_typed)
	for i: int in _lines.size():
		var part: String = _lines[i].left(remaining) if remaining > 0 else ""
		if part != "":
			PixelText.draw(self, part, Vector2i(int(rect.position.x) + 5, int(rect.position.y) + 3 + header_h + i * LINE_STEP), Color(VineStyle.PETAL, fade), Color(VineStyle.OUTLINE, fade * 0.8))
		remaining = maxi(remaining - _lines[i].length(), 0)
