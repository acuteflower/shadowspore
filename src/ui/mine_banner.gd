class_name MineBanner
extends CanvasLayer
## The title that fades in when the local player arrives on a level of the mine: "EBENE 3" and the zone's name below it, a thin line growing out of the middle.
## Local and cosmetic; `MineAtmosphere` calls `show_level` whenever the level under her changes.

const FADE_IN: float = 0.9
const HOLD: float = 2.4
const FADE_OUT: float = 1.4
const GOLD: Color = Color("d9b25f")
const SHADOW: Color = Color("0a0612")

var _canvas: Control
var _age: float = 99.0
var _title: String = ""
var _zone: String = ""


func _ready() -> void:
	layer = 20
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)


func show_level(level: int) -> void:
	_title = "EBENE %d" % level
	_zone = String(MineManager.zone(level).get("name", "")).to_upper()
	_age = 0.0


func is_showing() -> bool:
	return _age < FADE_IN + HOLD + FADE_OUT


func _process(delta: float) -> void:
	if not is_showing():
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
	PixelText.draw(_canvas, _zone, Vector2i(int(middle) - PixelText.width(_zone) / 2, int(y) + 32), Color(0.78, 0.7, 0.92, fade), Color(SHADOW, fade))
