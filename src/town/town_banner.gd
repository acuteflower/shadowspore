class_name TownBanner
extends CanvasLayer
## The title that fades in at the top of the screen for the big moments of the town (founding, a settler moving in, the next level): the line in gold, a thin
## line growing out of the middle, the second line in lilac. Local and cosmetic; `TownManager` shows it.

const FADE_IN: float = 0.9
const HOLD: float = 2.8
const FADE_OUT: float = 1.4
const GOLD: Color = Color("d9b25f")
const SHADOW: Color = Color("0a0612")

var _canvas: Control
var _age: float = 99.0
var _title: String = ""
var _sub: String = ""
var _queue: Array[Array] = []


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)


func show_text(title: String, sub: String = "") -> void:
	if is_showing():
		_queue.append([title, sub])
		return
	_title = title
	_sub = sub
	_age = 0.0


func is_showing() -> bool:
	return _age < FADE_IN + HOLD + FADE_OUT


func _process(delta: float) -> void:
	if not is_showing():
		if not _queue.is_empty():
			var next: Array = _queue.pop_front()
			show_text(String(next[0]), String(next[1]))
		return
	_age += delta
	_canvas.queue_redraw()


func _draw() -> void:
	if not is_showing():
		return
	var fade: float = clampf(_age / FADE_IN, 0.0, 1.0) * clampf((FADE_IN + HOLD + FADE_OUT - _age) / FADE_OUT, 0.0, 1.0)
	var middle: float = _canvas.size.x / 2.0
	var y: float = 52.0
	var scale: float = 3.0
	var width: float = float(PixelText.width(_title)) * scale
	_canvas.draw_set_transform(Vector2(middle - width / 2.0, y), 0.0, Vector2(scale, scale))
	PixelText.draw(_canvas, _title, Vector2i.ZERO, Color(GOLD, fade), Color(SHADOW, fade))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var line: float = 70.0 * clampf(_age / (FADE_IN * 1.4), 0.0, 1.0)
	_canvas.draw_rect(Rect2(middle - line, y + 26.0, line * 2.0, 1.0), Color(GOLD, fade * 0.7))
	PixelText.draw(_canvas, _sub, Vector2i(int(middle) - PixelText.width(_sub) / 2, int(y) + 32), Color(0.78, 0.7, 0.92, fade), Color(SHADOW, fade))
