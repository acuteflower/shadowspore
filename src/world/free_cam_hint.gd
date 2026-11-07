class_name FreeCamHint
extends Control
## What the free camera shows: a bark-paper card at the bottom with the keys, the tile coordinates under the camera and a
## teal ring on the ground where she will stand when she lands (the spot below the middle of the screen).

const GOLD: Color = Color("ffd98a")
const RING: Color = Color("7fe3da")
const DANGER: Color = Color("e0556e")
const KEYS: Array[Array] = [["WASD", "FLIEGEN"], ["UMSCH", "SCHNELL"], ["RAD", "ZOOM"], ["L", "HIER LANDEN"]]

var feet: Vector2 = Vector2.ZERO ## world px where she would stand
var zoom: float = 1.0
var _time: float = 0.0
var _fade: float = 0.0
var _complaint: String = ""
var _complaint_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func complain(text: String) -> void:
	_complaint = text
	_complaint_left = 2.0


func _process(delta: float) -> void:
	_time += delta
	_fade = minf(_fade + delta * 4.0, 1.0)
	_complaint_left = maxf(_complaint_left - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var centre: Vector2 = (size / 2.0).round()
	# The ring: where her feet will be (the player's camera looks 22 px above them).
	var ring_at: Vector2 = centre + Vector2(0.0, 22.0 * zoom)
	var bad: bool = _complaint_left > 0.0
	var tone: Color = DANGER if bad else RING
	for i: int in 24:
		if i % 2 == 0:
			var a: float = TAU * float(i) / 24.0 + _time * 0.6
			draw_rect(Rect2((ring_at + Vector2(cos(a) * 9.0, sin(a) * 4.5 * 1.0)).round(), Vector2.ONE), Color(tone, 0.9 * _fade))
	draw_rect(Rect2(ring_at.round() - Vector2(1, 0), Vector2(3, 1)), Color(tone, _fade))
	draw_rect(Rect2(ring_at.round() - Vector2(0, 1), Vector2(1, 3)), Color(tone, _fade))
	# The card.
	var width: float = 290.0
	var rect: Rect2 = Rect2(((size.x - width) / 2.0), size.y - 82.0, width, 36.0).abs()
	VineStyle.paper(self, rect, _fade, VineStyle.void_amount(), 7)
	var tile: Vector2i = Vector2i(int(floorf(feet.x / 16.0)), int(floorf(feet.y / 16.0)))
	var title: String = "FREIE KAMERA   X %d  Y %d" % [tile.x, tile.y]
	if bad:
		title = _complaint
	PixelText.draw(self, title, Vector2i(int(rect.position.x + (width - PixelText.width(title)) / 2.0), int(rect.position.y + 5)), Color(DANGER.lightened(0.3) if bad else GOLD, _fade), Color(VineStyle.OUTLINE, _fade))
	var total: int = 0
	for pair: Array in KEYS:
		total += VineStyle.cap_width(String(pair[0])) + 3 + PixelText.width(String(pair[1])) + 10
	var x: float = rect.position.x + (width - (total - 10)) / 2.0
	var y: float = rect.position.y + 17.0
	for pair: Array in KEYS:
		var w: int = VineStyle.key_cap(self, Vector2(x, y), String(pair[0]), _fade)
		x += w + 3
		PixelText.draw(self, String(pair[1]), Vector2i(int(x), int(y) + 3), Color(UiStyle.TEXT_DIM, _fade), Color(VineStyle.OUTLINE, _fade))
		x += PixelText.width(String(pair[1])) + 10
