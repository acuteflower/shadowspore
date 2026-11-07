class_name VineStyle
extends RefCounted
## Shared look of the vine HUD (hotbar, sap vines, skill crystal): living bark and leaves by day,
## taken over by the void at night. The void creeps in from the outer tips of the whole
## composition (health tip, stamina tip) towards the middle of the hotbar.

const OUTLINE: Color = Color("120c1c")
const BARK: Color = Color("3b2c40")
const BARK_LIGHT: Color = Color("65506b")
const BARK_VOID: Color = Color("0b0614")
const BARK_VOID_LIGHT: Color = Color("3a1f66")
const LEAF: Color = Color("4f9a62")
const LEAF_LIGHT: Color = Color("a6e68f")
const LEAF_VOID: Color = Color("6a35c8")
const LEAF_VOID_LIGHT: Color = Color("c9a0ff")
const VOID_GLOW: Color = Color("9b5cff")
const PETAL: Color = Color("f1e6ff")
const WARM_GLOW: Color = Color("ffd98a")
const ACCENT_WARM: Color = Color("ffd98a") ## the open tab's glow

const TIP_SPAN: float = 116.0 + 112.0 ## the longer sap vine from its tip to the middle of the hotbar


static var _glow_spans: Dictionary = {} ## radius -> exact unrounded scanline widths


static func void_amount() -> float:
	return TimeManager.night_amount()


## Deterministic noise 0..1 from an integer, so the "random" layout never jitters.
static func rand(seed_value: int) -> float:
	return fposmod(sin(float(seed_value) * 12.9898 + 4.1414) * 43758.5453, 1.0)


## How taken over by the void a spot is (0..1). `tip_distance` = distance along the vine from
## the nearest outer tip; the front advances with `void_level` and has a ragged edge.
static func infection(tip_distance: float, void_level: float, salt: int = 0) -> float:
	if void_level <= 0.001:
		return 0.0
	var front: float = void_level * (TIP_SPAN + 10.0)
	return clampf((front - tip_distance + rand(salt) * 7.0) / 6.0, 0.0, 1.0)


## Soft banded glow (three nested ellipses), cheap and pixel-friendly.
static func glow(canvas: CanvasItem, center: Vector2, radius: float, color: Color, strength: float) -> void:
	if strength <= 0.01:
		return
	if not _glow_spans.has(radius):
		var spans: PackedFloat64Array = PackedFloat64Array()
		for layer: int in 3:
			var r: float = radius * (1.0 - layer * 0.3)
			var half: int = int(r)
			for y: int in range(-half, half + 1):
				var w: float = sqrt(maxf(r * r - y * y, 0.0))
				spans.append_array(PackedFloat64Array([float(y), w, roundf(w * 2.0)]))
		if _glow_spans.size() >= 64: _glow_spans.clear()
		_glow_spans[radius] = spans
	var spans: PackedFloat64Array = _glow_spans[radius]
	var tint: Color = Color(color, strength * 0.15)
	for i: int in range(0, spans.size(), 3):
		canvas.draw_rect(Rect2(roundf(center.x - spans[i + 1]), roundf(center.y) + spans[i], spans[i + 2], 1), tint)


## A tiny pointed leaf reaching sideways (`dx` -1/1) and up (`up` -1/1).
static func leaf(canvas: CanvasItem, pos: Vector2, dx: int, up: int, size: int, color: Color, light: Color) -> void:
	var cells: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, -1), Vector2i(3, -1)]
	for i: int in mini(size, cells.size()):
		var c: Vector2i = cells[i]
		canvas.draw_rect(Rect2(pos.x + c.x * dx, pos.y + c.y * up, 1, 1), light if i == size - 1 else color)


## A creeping void tendril: dark stalk, writhing, with a glowing tip.
static func tendril(canvas: CanvasItem, origin: Vector2, heading: Vector2, length: int, time: float, salt: int) -> void:
	var side: Vector2 = Vector2(-heading.y, heading.x)
	for i: int in length:
		var k: float = float(i) / maxf(length, 1)
		var p: Vector2 = origin + heading * i + side * sin(i * 0.8 + time * 2.2 + salt) * 1.6 * k
		var tip: bool = i >= length - 2
		canvas.draw_rect(Rect2(roundf(p.x), roundf(p.y), 1, 1), VOID_GLOW if tip else BARK_VOID)
		if i % 3 == 2 and not tip:
			canvas.draw_rect(Rect2(roundf(p.x), roundf(p.y) - 1, 1, 1), BARK_VOID_LIGHT)


## A branch of bark from `x0` to `x1` (`x1` < `x0` grows leftwards), thick at the root and thin
## at the tip, along `y_of(x)`. `reach` 0..1 grows it out of its root; `tip_extra` shifts how soon
## the void reaches it. Returns nothing: callers add `foliage`.
static func branch(canvas: CanvasItem, x0: float, x1: float, y_of: Callable, thick: int, void_level: float, tip_extra: float, time: float, reach: float = 1.0) -> void:
	var span: float = absf(x1 - x0)
	var dir: float = signf(x1 - x0)
	for i: int in int(span * reach) + 1:
		var x: float = x0 + dir * i
		var t: float = i / span
		var th: int = maxi(roundi(lerpf(thick, 1.0, smoothstep(0.05, 1.0, t))), 1)
		var y: float = roundf(float(y_of.call(x))) - floorf(th / 2.0)
		var taken: float = infection(span - i + tip_extra, void_level, i / 2)
		canvas.draw_rect(Rect2(x, y - 1, 1, th + 2), OUTLINE.lerp(BARK_VOID_LIGHT, taken))
		canvas.draw_rect(Rect2(x, y, 1, th), BARK.lerp(BARK_VOID, taken))
		if i % 3 != 1:
			canvas.draw_rect(Rect2(x, y, 1, 1), BARK_LIGHT.lerp(BARK_VOID_LIGHT, taken))
		if taken > 0.5 and rand(i * 3 + int(time * 2.0)) < 0.07:
			canvas.draw_rect(Rect2(x, y + floorf(th / 2.0), 1, 1), VOID_GLOW)


## Leaves along a branch (and void tendrils at night), within what has grown (`reach`).
static func foliage(canvas: CanvasItem, x0: float, x1: float, y_of: Callable, count: int, salt: int, void_level: float, tip_extra: float, time: float, reach: float = 1.0) -> void:
	var span: float = absf(x1 - x0)
	var dir: float = signf(x1 - x0)
	for k: int in count:
		var d: float = (k + 0.3 + rand(k + salt) * 0.5) * span / count
		if d > span * reach - 4.0 or d > span - 6.0 or rand(k * 5 + salt) < 0.2:
			continue
		var taken: float = infection(span - d + tip_extra, void_level, k + salt)
		var up: int = -1 if k % 2 == 0 else 1
		leaf(canvas, Vector2(x0 + dir * d, roundf(float(y_of.call(x0 + dir * d)))) + Vector2(0, up * 2), int(dir), up, 3, LEAF.lerp(LEAF_VOID, taken), LEAF_LIGHT.lerp(LEAF_VOID_LIGHT, taken))
	if void_level > 0.05:
		for k: int in 3:
			var d: float = span * (0.5 + 0.17 * k) + rand(k + salt + 9) * 6.0
			if d > span * reach or infection(span - d + tip_extra, void_level, k) < 0.5:
				continue
			var x: float = x0 + dir * d
			tendril(canvas, Vector2(x, float(y_of.call(x))), Vector2(0.4 * dir, 0.9 if k % 2 == 0 else -0.9).normalized(), int(3 + 6 * void_level), time, k + salt)


## A pixel circle outline; `dash` < 1 breaks it into dashes.
static func ring(canvas: CanvasItem, center: Vector2, radius: int, color: Color, dash: float = 1.0) -> void:
	var steps: int = radius * 8
	for s: int in steps:
		if float(s % 6) / 6.0 > dash:
			continue
		var angle: float = s * TAU / steps
		canvas.draw_rect(Rect2(roundf(center.x + cos(angle) * radius), roundf(center.y + sin(angle) * radius), 1, 1), color)


## The dark room behind full-screen menus: a radial vignette.
static func make_vignette() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.25, 1.0])
	gradient.colors = PackedColorArray([Color(0.02, 0.01, 0.06, 0.55), Color(0.02, 0.01, 0.06, 0.92)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.45, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 160
	texture.height = 90
	return texture


## Spores drifting up through a room (stateless: positions come from `time`).
static func motes(canvas: CanvasItem, area: Vector2, time: float, fade: float, void_level: float) -> void:
	for k: int in 36:
		var phase: float = fposmod(time * (0.02 + rand(k) * 0.03) + rand(k + 50), 1.0)
		var x: float = rand(k + 100) * area.x + sin(time * 0.7 + k) * 6.0
		var y: float = area.y - phase * (area.y + 20.0)
		var tone: Color = WARM_GLOW.lerp(VOID_GLOW, maxf(void_level, 0.35))
		canvas.draw_rect(Rect2(roundf(x), roundf(y), 1, 1), Color(tone, (0.25 + 0.5 * (0.5 + 0.5 * sin(time * 2.0 + k))) * fade * minf(phase * 6.0, 1.0)))


## 0..1 with an overshoot: things on threads drop in and bounce.
static func back_out(p: float) -> float:
	var c: float = 2.2
	return 1.0 + (c + 1.0) * pow(p - 1.0, 3.0) + c * pow(p - 1.0, 2.0)


## A name plate swinging on a thread from `at` (`p` 0..1 lets it drop in, `taken` = void takeover).
static func tag(canvas: CanvasItem, text: String, at: Vector2, p: float, taken: float, time: float, tone: Color = UiStyle.TEXT) -> void:
	if p <= 0.0:
		return
	var swing: float = sin(time * 1.3 + at.x) * 1.0
	var length: float = 9.0 * back_out(p)
	var width: int = PixelText.width(text) + 8
	for y: int in int(length):
		canvas.draw_rect(Rect2(at.x + roundf(swing * y / 9.0), at.y + y, 1, 1), BARK_LIGHT.lerp(BARK_VOID_LIGHT, taken) if y % 2 == 0 else BARK.lerp(BARK_VOID, taken))
	var plate: Rect2 = Rect2(roundf(at.x + swing - width / 2.0), at.y + length, width, 11)
	canvas.draw_rect(plate, Color(OUTLINE, p))
	canvas.draw_rect(plate.grow(-1), Color(BARK.lerp(BARK_VOID, taken), p))
	canvas.draw_rect(Rect2(plate.position + Vector2(1, 1), Vector2(width - 2, 1)), Color(BARK_LIGHT.lerp(BARK_VOID_LIGHT, taken), p))
	PixelText.draw(canvas, text, Vector2i(int(plate.position.x) + 4, int(plate.position.y) + 2), Color(tone.lerp(LEAF_VOID_LIGHT, taken), p), Color(OUTLINE, p))


## A tab tag as the Escape menu hangs them: a slanted thread from the branch point `anchor`, the plate swaying a little on its own beat (`index`), dropping in with an overshoot
## (`p` 0..1), lifted when it is the open one (`lift` 3 px) or hovered (2 px) and glowing warm (or in `tone`), the open one with its text in petal white. Returns its rectangle (for clicks).
static func tab(canvas: CanvasItem, text: String, anchor: Vector2, p: float, lift: float, taken: float, time: float, index: int, active: bool, hover: bool, tone: Color = ACCENT_WARM) -> Rect2:
	var width: float = float(PixelText.width(text) + 10)
	var rect: Rect2 = Rect2(roundf(anchor.x - width / 2.0 + sin(time * 1.2 + float(index) * 1.5) * 0.8), roundf(anchor.y + 10.0 * back_out(p) - lift), width, 13.0)
	if p <= 0.0:
		return rect
	for y: int in range(int(anchor.y) + 1, int(rect.position.y)): ## the thread
		canvas.draw_rect(Rect2(anchor.x + roundf((rect.get_center().x - anchor.x) * float(y - int(anchor.y)) / maxf(rect.position.y - anchor.y, 1.0)), y, 1, 1), Color(BARK_LIGHT.lerp(BARK_VOID_LIGHT, taken) if y % 2 == 0 else BARK.lerp(BARK_VOID, taken), p))
	var glow_tone: Color = tone.lerp(VOID_GLOW, taken)
	if active:
		glow(canvas, rect.get_center(), 24.0, glow_tone, 0.55 * p)
	elif hover:
		glow(canvas, rect.get_center(), 20.0, glow_tone, 0.3 * p)
	plate(canvas, rect, text, glow_tone if active else glow_tone * 0.35, PETAL if active else UiStyle.TEXT, p, taken)
	return rect


## The plate of a tab: ink edge, bark tinted by `tone`, a lit top edge, the text with its outline.
static func plate(canvas: CanvasItem, rect: Rect2, text: String, tone: Color, text_color: Color, alpha: float, taken: float) -> void:
	canvas.draw_rect(rect, Color(OUTLINE, alpha))
	canvas.draw_rect(rect.grow(-1.0), Color(BARK.lerp(BARK_VOID, taken).lerp(tone, 0.3), alpha))
	canvas.draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(rect.size.x - 2.0, 1)), Color(BARK_LIGHT.lerp(BARK_VOID_LIGHT, taken).lerp(tone, 0.55), alpha))
	var left: float = rect.position.x + (rect.size.x - PixelText.width(text)) / 2.0
	PixelText.draw(canvas, text, Vector2i(int(left), int(rect.position.y) + 2), Color(text_color, alpha), Color(OUTLINE, alpha))


## The bloom that opens on the branch above the open tab.
static func bloom(canvas: CanvasItem, at: Vector2, p: float, time: float, taken: float, tone: Color = ACCENT_WARM) -> void:
	var open: int = 1 + int(1.5 + 1.5 * sin(time * 3.0))
	var warm: Color = tone.lerp(VOID_GLOW, taken)
	glow(canvas, at, 9.0, warm, 0.9 * p)
	for o: Vector2 in [Vector2(-open, 0), Vector2(open, 0), Vector2(0, -open), Vector2(0, open)]:
		canvas.draw_rect(Rect2(at + o, Vector2.ONE), Color(PETAL, p))
	canvas.draw_rect(Rect2(at, Vector2.ONE), Color(warm, p))


## Dark bark paper used by dialogue cards, following the item tooltip's pixel edges.
static func paper(canvas: CanvasItem, rect: Rect2, fade: float, void_level: float, salt: int = 0) -> void:
	var fill: Color = Color("120d22").lerp(Color("07030f"), void_level)
	var edge: Color = BARK_LIGHT.lerp(BARK_VOID_LIGHT, void_level)
	var width: int = int(rect.size.x)
	var height: int = int(rect.size.y)
	var previous_top: int = 0
	var previous_bottom: int = height
	for x: int in width:
		var d: int = mini(x, width - 1 - x)
		var top: int = int(rand(x / 2 + salt) * 2.4) + maxi(4 - d, 0)
		var bottom: int = height - int(rand(x / 2 + salt + 97) * 2.4) - maxi(4 - d, 0)
		canvas.draw_rect(Rect2(rect.position + Vector2(x, top), Vector2(1, bottom - top)), Color(fill, 0.97 * fade))
		canvas.draw_rect(Rect2(rect.position + Vector2(x, mini(top, previous_top) if x > 0 else top), Vector2(1, absi(top - previous_top) + 1 if x > 0 else 1)), Color(edge, fade))
		canvas.draw_rect(Rect2(rect.position + Vector2(x, top + 1), Vector2(1, 1)), Color(edge.lightened(0.12), fade * 0.5))
		canvas.draw_rect(Rect2(rect.position + Vector2(x, mini(bottom, previous_bottom) - 1), Vector2(1, absi(bottom - previous_bottom) + 1)), Color(edge.darkened(0.3), fade))
		if x == 0 or x == width - 1:
			canvas.draw_rect(Rect2(rect.position + Vector2(x, top), Vector2(1, bottom - top)), Color(edge, fade))
		previous_top = top
		previous_bottom = bottom


# ---------------------------------------------------------------------------------------------- key caps
## Every key the HUD shows is drawn by `key_cap`, so they all look the same: a little polished seed-stone set in bark.

const KEY_NAMES: Dictionary = {"Ctrl": "STRG", "Shift": "UMSCH", "Alt": "ALT", "Space": "LEER", "Tab": "TAB", "Escape": "ESC", "Enter": "ENTER"}
const CAP_HEIGHT: int = 12
const MOUSE_LEFT: String = "LMT"
const MOUSE_RIGHT: String = "RMT"


## The label of the first key (or mouse button) bound to `action`, in the game's words ("STRG", "LEER", "LMT").
static func key_name(action: String, fallback: String = "?") -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button != null:
			return MOUSE_LEFT if button.button_index == MOUSE_BUTTON_LEFT else MOUSE_RIGHT
		var key: InputEventKey = event as InputEventKey
		if key != null:
			var code: Key = key.keycode if key.keycode != KEY_NONE else DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			var label: String = OS.get_keycode_string(code)
			return String(KEY_NAMES.get(label, label.to_upper()))
	return fallback


## How wide `key_cap` draws `key`.
static func cap_width(key: String) -> int:
	if key == MOUSE_LEFT or key == MOUSE_RIGHT:
		return CAP_HEIGHT - 1
	return maxi(CAP_HEIGHT - 1, PixelText.width(key) + 7)


## A key cap with its top-left at `at`: ink outline with cut corners, a stone face lit from the top left, a darker lip
## below that gives it depth, a sprig of moss on one shoulder and the key in petal white. `lit` 0..1 (held, or the
## key to press now): it sinks a pixel, the face fills with the teal of life and glows. By night the void tints it.
## Mouse buttons ("LMT", "RMT") are drawn as a small mouse with that half lit. Returns the cap's width.
static func key_cap(canvas: CanvasItem, at: Vector2, key: String, fade: float = 1.0, lit: float = 0.0, void_level: float = 0.0) -> int:
	var w: int = cap_width(key)
	var h: int = CAP_HEIGHT
	var o: Vector2 = at.round()
	var press: int = 1 if lit > 0.5 else 0
	var ink: Color = Color(OUTLINE, fade)
	var face_dark: Color = Color("2a2340").lerp(Color("120a24"), void_level)
	var face: Color = Color("3d3358").lerp(Color("24164a"), void_level).lerp(UiStyle.ACCENT.darkened(0.25), lit)
	var shine: Color = BARK_LIGHT.lerp(BARK_VOID_LIGHT, void_level).lerp(UiStyle.ACCENT.lightened(0.45), lit)
	var lip: Color = Color("17112a").lerp(UiStyle.ACCENT.darkened(0.6), lit * 0.6)
	if lit > 0.0:
		glow(canvas, o + Vector2(w / 2.0, h / 2.0 + 1), maxf(8.0, w * 0.6), UiStyle.ACCENT, 0.55 * lit * fade)
	# outline and lip (the cap's depth), corners cut
	canvas.draw_rect(Rect2(o + Vector2(1, 0), Vector2(w - 2, h)), ink)
	canvas.draw_rect(Rect2(o + Vector2(0, 1), Vector2(w, h - 2)), ink)
	canvas.draw_rect(Rect2(o + Vector2(1, h - 3), Vector2(w - 2, 2)), Color(lip, fade))
	var top: float = o.y + 1 + press
	var face_h: int = h - 4 - press
	if key == MOUSE_LEFT or key == MOUSE_RIGHT:
		_mouse_face(canvas, Vector2(o.x, top), w, face_h, key == MOUSE_LEFT, fade, lit, face_dark, face, shine)
		return w
	canvas.draw_rect(Rect2(o.x + 1, top, w - 2, face_h), Color(face_dark, fade))
	canvas.draw_rect(Rect2(o.x + 2, top, w - 4, face_h - 1), Color(face, fade)) ## the dished face
	canvas.draw_rect(Rect2(o.x + 2, top, w - 4, 1), Color(shine, fade)) ## light from the top left
	canvas.draw_rect(Rect2(o.x + 1, top + 1, 1, face_h - 2), Color(shine, 0.55 * fade))
	var moss: Color = LEAF.lerp(LEAF_VOID, void_level)
	canvas.draw_rect(Rect2(o.x + w - 3, o.y - 1 + press, 2, 1), Color(moss, fade)) ## a sprig of moss on the shoulder
	canvas.draw_rect(Rect2(o.x + w - 2, o.y - 2 + press, 1, 1), Color(LEAF_LIGHT.lerp(LEAF_VOID_LIGHT, void_level), fade))
	var text_color: Color = PETAL.lerp(OUTLINE, smoothstep(0.4, 0.9, lit))
	PixelText.draw(canvas, key, Vector2i(int(o.x) + (w - PixelText.width(key) + 1) / 2, int(top) - 1), Color(text_color, fade))
	return w


static func _mouse_face(canvas: CanvasItem, at: Vector2, w: int, h: int, left: bool, fade: float, lit: float, dark: Color, face: Color, shine: Color) -> void:
	canvas.draw_rect(Rect2(at.x + 1, at.y, w - 2, h), Color(dark, fade))
	canvas.draw_rect(Rect2(at.x + 2, at.y, w - 4, h - 1), Color(face, fade))
	canvas.draw_rect(Rect2(at.x + 2, at.y, w - 4, 1), Color(shine, fade))
	## a small mouse drawn in petal white on the face, the button in question filled with teal
	var glyph: Array[String] = [".###.", "#ab.#", "#ab.#", "#####", "#...#", "#...#", ".###."]
	var ox: float = at.x + floorf((w - 5) / 2.0)
	var oy: float = at.y + maxf(0.0, floorf((h - 7) / 2.0))
	var button: Color = UiStyle.ACCENT.lerp(Color.WHITE, 0.3 * lit)
	for y: int in glyph.size():
		for x: int in 5:
			var cell: String = glyph[y][x]
			var gx: int = x if left else 4 - x
			if cell == "#":
				canvas.draw_rect(Rect2(ox + gx, oy + y, 1, 1), Color(PETAL, fade))
			elif cell == "a" or cell == "b":
				canvas.draw_rect(Rect2(ox + gx, oy + y, 1, 1), Color(button, fade))
