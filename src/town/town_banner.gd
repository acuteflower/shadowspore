class_name TownBanner
extends CanvasLayer
## The town's banner (docs/stadtbau_konzept.md 5.1): a cloth in the town's colour with its emblem unrolls from a branch at the top of the screen, sways in
## the wind in whole pixels, carries a gold border and a swallowtail, and rolls up again. Used when she walks into the town, for its founding, a settler moving
## in and (big) a new level; `show_text` is the plain dark variant for the night's messages. Local and cosmetic; `TownManager` shows it. Waits while a dialogue
## or the pause menu is open.

const UNROLL: float = 0.6
const HOLD: float = 3.0
const HOLD_BIG: float = 4.6
const ROLL: float = 0.5
const GOLD: Color = Color("ffd27a")
const GOLD_DIM: Color = Color("b08a4a")
const INK: Color = Color("0a0612")
const NIGHT_CLOTH: Color = Color("1c1430")
const TAIL: float = 12.0

var _canvas: Control
var _age: float = 99.0
var _now: Dictionary = {}
var _queue: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)


## The plain banner (the night, warnings): a dark cloth without an emblem.
func show_text(title: String, sub: String = "") -> void:
	show_banner({"title": title, "sub": sub, "color": NIGHT_CLOTH, "emblem": -1})


## `info`: title, sub, header (small line over the emblem), color, emblem (-1 none), big (the level), sound ("" = the cloth only).
func show_banner(info: Dictionary) -> void:
	if is_showing() or not _queue.is_empty():
		_queue.append(info)
		return
	_now = info
	_age = 0.0
	_play("banner_unroll", -6.0)
	if String(info.get("sound", "")) != "":
		_play(String(info.sound), -4.0)


func is_showing() -> bool:
	return _age < UNROLL + _hold() + ROLL


func _hold() -> float:
	return HOLD_BIG if bool(_now.get("big", false)) else HOLD


func _play(file: String, db: float) -> void:
	var path: String = "res://assets/audio/town/%s.wav" % file
	if not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = load(path) as AudioStream
	player.volume_db = db
	player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _blocked() -> bool:
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	return get_tree().paused or (box != null and box.is_active())


func _process(delta: float) -> void:
	_time += delta
	if not is_showing():
		if not _queue.is_empty() and not _blocked():
			show_banner(_queue.pop_front())
		return
	if _age > UNROLL and _age < UNROLL + _hold() - 0.1 and _blocked():
		_canvas.queue_redraw()
		return ## hold while something covers the screen
	_age += delta
	_canvas.queue_redraw()


## 0..1 how far the cloth hangs down.
func _open() -> float:
	if _age < UNROLL:
		var k: float = _age / UNROLL
		return 1.0 - pow(1.0 - k, 3.0) + sin(k * PI) * 0.06
	var back: float = _age - UNROLL - _hold()
	if back > 0.0:
		var k2: float = clampf(back / ROLL, 0.0, 1.0)
		return 1.0 - k2 * k2
	return 1.0


func _draw() -> void:
	if not is_showing() or _now.is_empty():
		return
	var big: bool = bool(_now.get("big", false))
	var title: String = String(_now.get("title", ""))
	var sub: String = String(_now.get("sub", ""))
	var header: String = String(_now.get("header", ""))
	var emblem: int = int(_now.get("emblem", -1))
	var cloth: Color = _now.get("color", NIGHT_CLOTH) as Color
	var title_scale: float = 3.0 if big else 2.0
	var content_w: float = maxf(float(PixelText.width(title)) * title_scale, maxf(float(PixelText.width(sub)), float(PixelText.width(header))))
	var w: float = roundf(maxf(content_w + 44.0, 150.0) / 2.0) * 2.0
	var h: float = (40.0 if emblem >= 0 else 14.0) + title_scale * 6.0 + (14.0 if sub != "" else 2.0) + (10.0 if header != "" else 0.0) + TAIL + 8.0
	var mid: float = roundf(_canvas.size.x / 2.0)
	var left: float = mid - w / 2.0
	var top: float = 14.0
	var open: float = _open()
	var shown: float = roundf(h * open)
	var fade: float = clampf(open * 3.0, 0.0, 1.0)
	_draw_cloth(left, top, w, h, shown, cloth, fade)
	var y: float = top + 8.0
	if header != "":
		_text(header, mid, y, 1.0, Color(GOLD_DIM.lerp(GOLD, 0.4), fade), top + shown)
		y += 10.0
	if emblem >= 0:
		var size: Vector2i = TownEmblems.size(emblem)
		var at: Vector2 = Vector2(mid - float(size.x), y + 2.0)
		if at.y + float(size.y) * 2.0 < top + shown:
			VineStyle.glow(_canvas, at + Vector2(size) , 22.0, Color(GOLD, 0.5), 0.35 * fade)
			TownEmblems.draw(_canvas, emblem, at.round(), 2.0, fade)
		y += 40.0 - 8.0
	_text(title, mid, y + 2.0, title_scale, Color(GOLD, fade), top + shown)
	y += title_scale * 6.0 + 6.0
	if sub != "":
		_text(sub, mid, y, 1.0, Color(0.86, 0.8, 0.96, fade), top + shown)
	_draw_rod(left - 14.0, w + 28.0, top - 3.0, fade)


func _text(text: String, mid: float, y: float, scale: float, color: Color, limit: float) -> void:
	if text == "" or y + 5.0 * scale > limit:
		return
	var width: float = float(PixelText.width(text)) * scale
	_canvas.draw_set_transform(Vector2(roundf(mid - width / 2.0), roundf(y)), 0.0, Vector2(scale, scale))
	PixelText.draw(_canvas, text, Vector2i.ZERO, color, Color(INK, color.a))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The cloth row by row: swaying more towards the bottom, shaded under the rod and at the folds, a gold border inside the edge, the swallowtail cut into the
## bottom; while it unrolls the bottom edge is the roll itself.
func _draw_cloth(left: float, top: float, w: float, h: float, shown: float, cloth: Color, fade: float) -> void:
	var rolling: bool = shown < h - 0.5
	var dark: Color = cloth.darkened(0.45)
	var light: Color = cloth.lightened(0.18)
	for r: int in int(shown):
		var y: float = top + float(r)
		var depth: float = float(r) / h
		var shift: float = roundf(sin(_time * 1.7 + float(r) * 0.11) * 1.6 * depth + sin(_time * 3.1 + float(r) * 0.3) * 0.4 * depth)
		var notch: float = 0.0
		if not rolling and float(r) > h - TAIL:
			notch = (float(r) - (h - TAIL)) / TAIL * (w * 0.5 - 6.0)
		var x0: float = left + shift
		_canvas.draw_rect(Rect2(x0 + 2.0, y + 2.0, w, 1.0), Color(0, 0, 0, 0.3 * fade)) ## its shadow
		for half: int in 2:
			var a: float = x0 if half == 0 else x0 + w / 2.0 + notch
			var b: float = x0 + w / 2.0 - notch if half == 0 else x0 + w
			if b - a < 1.0:
				continue
			var tone: Color = cloth.lerp(dark, clampf(0.55 - float(r) * 0.08, 0.0, 0.55)) ## shadow right under the rod
			_canvas.draw_rect(Rect2(a, y, b - a, 1.0), Color(tone, fade))
			if half == 0 or notch > 0.0: ## ink only on the outer edges and the swallowtail's cut, not down the middle
				_canvas.draw_rect(Rect2(a, y, 1.0, 1.0), Color(INK, fade))
			if half == 1 or notch > 0.0:
				_canvas.draw_rect(Rect2(b - 1.0, y, 1.0, 1.0), Color(INK, fade))
		# folds: two soft vertical bands of light and shade that move with the sway
		for k: int in 3:
			var fx: float = x0 + w * (0.22 + 0.28 * float(k)) + roundf(sin(_time * 1.2 + float(k)) * 2.0)
			if absf(fx - (x0 + w / 2.0)) < notch:
				continue
			_canvas.draw_rect(Rect2(fx, y, 2.0, 1.0), Color(light, 0.35 * fade))
			_canvas.draw_rect(Rect2(fx + 2.0, y, 1.0, 1.0), Color(dark, 0.3 * fade))
		# the gold border, 3 px inside the edge, dotted where the cloth is still rolling in
		if float(r) > 3.0 and (rolling or float(r) < h - TAIL):
			_canvas.draw_rect(Rect2(x0 + 3.0, y, 1.0, 1.0), Color(GOLD, 0.85 * fade))
			_canvas.draw_rect(Rect2(x0 + w - 4.0, y, 1.0, 1.0), Color(GOLD, 0.85 * fade))
		if not rolling and float(r) > h - TAIL - 1.0:
			var ax: float = x0 + w / 2.0 - notch
			_canvas.draw_rect(Rect2(ax - 4.0, y, 1.0, 1.0), Color(GOLD, 0.85 * fade))
			_canvas.draw_rect(Rect2(x0 + w / 2.0 + notch + 3.0, y, 1.0, 1.0), Color(GOLD, 0.85 * fade))
		if r == 3:
			_canvas.draw_rect(Rect2(x0 + 3.0, y, w - 6.0, 1.0), Color(GOLD, 0.85 * fade))
	if rolling and shown > 0.0:
		var y2: float = top + shown
		var shift2: float = roundf(sin(_time * 1.7 + shown * 0.11) * 1.6 * shown / h)
		_canvas.draw_rect(Rect2(left + shift2 - 1.0, y2 - 1.0, w + 2.0, 5.0), Color(INK, fade))
		_canvas.draw_rect(Rect2(left + shift2, y2, w, 3.0), Color(cloth.darkened(0.2), fade))
		_canvas.draw_rect(Rect2(left + shift2, y2, w, 1.0), Color(light, fade))


## The branch the cloth hangs from: bark with a lit top, knots and a leaf at each end.
func _draw_rod(x: float, w: float, y: float, fade: float) -> void:
	var void_level: float = VineStyle.void_amount()
	_canvas.draw_rect(Rect2(x, y - 1.0, w, 5.0), Color(VineStyle.OUTLINE, fade))
	_canvas.draw_rect(Rect2(x + 1.0, y, w - 2.0, 3.0), Color(VineStyle.BARK.lerp(VineStyle.BARK_VOID, void_level * 0.6), fade))
	for i: int in int(w - 2.0):
		if i % 3 != 1:
			_canvas.draw_rect(Rect2(x + 1.0 + float(i), y, 1.0, 1.0), Color(VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level * 0.6), fade))
	for k: float in [0.18, 0.5, 0.82]:
		_canvas.draw_rect(Rect2(roundf(x + w * k), y + 1.0, 2.0, 2.0), Color(VineStyle.OUTLINE, fade))
	for end: float in [x - 2.0, x + w - 2.0]:
		_canvas.draw_rect(Rect2(end, y - 2.0, 4.0, 7.0), Color(VineStyle.OUTLINE, fade))
		_canvas.draw_rect(Rect2(end + 1.0, y - 1.0, 2.0, 5.0), Color(VineStyle.BARK_LIGHT, fade))
	VineStyle.leaf(_canvas, Vector2(x + 6.0, y + 4.0), -1, 1, 4, Color(VineStyle.LEAF, fade), Color(VineStyle.LEAF_LIGHT, fade))
	VineStyle.leaf(_canvas, Vector2(x + w - 6.0, y + 4.0), 1, 1, 4, Color(VineStyle.LEAF, fade), Color(VineStyle.LEAF_LIGHT, fade))
