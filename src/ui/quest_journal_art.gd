class_name QuestJournalArt
extends Control
## All coordinates are native game pixels. Text and hit targets live on a separate, stationary layer.

const EXTENT: Vector2 = Vector2(640, 360)
const BOOK: Rect2 = Rect2(36, 42, 568, 272)
const SPINE: int = 320
const SHEET: Texture2D = preload("res://assets/ui/journal/spread.png")
const COVER: Texture2D = preload("res://assets/ui/journal/cover.png")
const FERN: Texture2D = preload("res://assets/ui/journal/pressed_fern.png")
const INK: Color = Color("362535")
const FAINT: Color = Color("71565b")
const TEAL: Color = Color("315e55")
const RED: Color = Color("863e51")
const GOLD: Color = Color("d7b575")

var opening: float = 0.0
var turn: float = 1.0
var toward_archive: bool = false
var ribbon: float = 0.0
var ink: float = 1.0
var show_fern: bool = false
var seal_flash: float = 0.0
var night: float = 0.0
var _flip: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_flip = Control.new()
	_flip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flip.z_index = 2
	_flip.draw.connect(_draw_turn)
	add_child(_flip)


func refresh() -> void:
	queue_redraw()
	_flip.queue_redraw()


func _draw() -> void:
	var p: float = opening
	if p <= 0.0:
		return
	var settle: float = roundf(13.0 * (1.0 - smoothstep(0.0, 0.5, p)))
	draw_set_transform(Vector2(0, settle))
	if p >= 0.98:
		_shadow(BOOK, p)
		draw_texture_rect(SHEET, BOOK, false, _paper_light())
	else:
		_unfold(p)
	draw_set_transform(Vector2.ZERO)
	var writing: float = smoothstep(0.60, 0.97, p)
	if writing <= 0.0:
		return
	draw_set_transform(Vector2(78, 62), 0.0, Vector2(2, 2))
	PixelText.draw(self, "ELLIES TAGEBUCH", Vector2i.ZERO, Color(INK, writing))
	draw_set_transform(Vector2.ZERO)
	draw_texture(QuestJournalSkin.icon("story", Color("8d6259")), Vector2(65, 65), Color(1, 1, 1, writing))
	_rule(Vector2(68, 84), 222, writing)
	_rule(Vector2(348, 268), 224, writing)
	_register_stitches(writing)
	if show_fern:
		_pressed_fern(writing)
	_bookmark(writing)
	_controls(writing)
	if ink < 1.0:
		var width: float = roundf(28.0 + 124.0 * smoothstep(0.0, 1.0, ink))
		draw_rect(Rect2(348, 61, width, 1), Color(TEAL, 0.36 * sin(PI * ink) * writing))


func _shadow(rect: Rect2, alpha: float) -> void:
	for pad: int in [11, 7, 3]:
		var shade: Rect2 = rect.grow(pad)
		shade.position.y += 5.0
		var tone: Color = Color("090510", (0.09 if pad > 3 else 0.20) * alpha)
		draw_rect(Rect2(shade.position + Vector2(5, 0), shade.size - Vector2(10, 0)), tone)
		draw_rect(Rect2(shade.position + Vector2(0, 5), Vector2(5, shade.size.y - 10)), tone)
		draw_rect(Rect2(Vector2(shade.end.x - 5, shade.position.y + 5), Vector2(5, shade.size.y - 10)), tone)


func _paper_light() -> Color:
	return Color.WHITE.lerp(Color("d0c3e0"), night * 0.40)


func _unfold(p: float) -> void:
	var half: float = BOOK.size.x / 2.0
	var slide: float = smoothstep(0.0, 0.34, p)
	var cover_x: float = roundf(lerpf(202.0, float(SPINE), slide))
	var cover_width: float = roundf(lerpf(float(COVER.get_width()), half, slide) * (1.0 - smoothstep(0.29, 0.58, p)))
	var left_width: float = roundf(half * smoothstep(0.39, 0.98, p))
	if p >= 0.29:
		var right: Rect2 = Rect2(cover_x, BOOK.position.y, half, BOOK.size.y)
		_shadow(Rect2(cover_x - left_width, BOOK.position.y, half + left_width, BOOK.size.y), slide)
		draw_texture_rect_region(SHEET, right, Rect2(half, 0, half, BOOK.size.y), _paper_light())
	if left_width > 0.0:
		var lift: float = roundf(sin(PI * left_width / half) * 7.0)
		var left: Rect2 = Rect2(cover_x - left_width, BOOK.position.y - lift, left_width, BOOK.size.y + lift)
		draw_texture_rect_region(SHEET, left, Rect2(0, 0, half, BOOK.size.y), _paper_light())
		draw_rect(Rect2(left.end.x - 2.0, left.position.y + 7.0, 2, left.size.y - 14.0), Color(INK, 0.28))
	if cover_width > 0.0:
		var cover: Rect2 = Rect2(cover_x, BOOK.position.y, cover_width, BOOK.size.y)
		if p < 0.29:
			_shadow(cover, smoothstep(0.0, 0.16, p))
		draw_texture_rect(COVER, cover, false, Color(_paper_light(), smoothstep(0.0, 0.12, p)))
		if p < 0.24:
			var title_at: Vector2 = cover.get_center().round() + Vector2(0, -19)
			draw_set_transform(title_at + Vector2(0, roundf(13.0 * (1.0 - smoothstep(0.0, 0.5, p)))), 0.0, Vector2(2, 2))
			var title_fade: float = smoothstep(0.0, 0.13, p) * (1.0 - smoothstep(0.17, 0.24, p))
			PixelText.draw(self, "ELLIES TAGEBUCH", Vector2i(-PixelText.width("ELLIES TAGEBUCH") / 2, 0), Color(GOLD, title_fade), Color(INK, 0.56 * title_fade))


func _rule(at: Vector2, width: int, opacity: float) -> void:
	for x: int in range(0, width, 5):
		var y: int = int(VineStyle.rand(x + int(at.y)) > 0.78)
		draw_rect(Rect2(at + Vector2(x, y), Vector2(3 + x % 2, 1)), Color(FAINT, 0.28 * opacity))
	draw_rect(Rect2(at, Vector2(15, 1)), Color(FAINT, 0.67 * opacity))


func _register_stitches(opacity: float) -> void:
	for x: int in [76, 123, 144, 191]:
		draw_rect(Rect2(x, 46, 3, 7), Color(INK, 0.82 * opacity))
		draw_rect(Rect2(x, 46, 1, 6), Color(GOLD, 0.77 * opacity))
		draw_rect(Rect2(x + 1, 51, 3, 1), Color(Color("8d6c5d"), opacity))


func _pressed_fern(opacity: float) -> void:
	var origin: Vector2 = Vector2(70, 225)
	var fold: Color = Color("8b6d61", 0.36 * opacity)
	# A scrap tucked under the fern keeps a plant from rubbing ink off the facing leaf.
	for x: int in range(0, 137, 2):
		var cut: float = 1.0 + 2.0 * floorf(VineStyle.rand(x / 4 + 51) * 2.0)
		var bevel: float = maxi(5 - mini(x, 136 - x), 0)
		var top: float = floorf(5.0 * sin(x * 0.013)) + cut + bevel
		var bottom: float = 40.0 - bevel - floorf(VineStyle.rand(x / 3 + 72) * 3.0)
		draw_rect(Rect2(origin + Vector2(x + 1, top + 2), Vector2(2, bottom - top + 1)), fold)
		draw_rect(Rect2(origin + Vector2(x, top), Vector2(2, bottom - top)), Color("c9b89d", opacity))
		draw_rect(Rect2(origin + Vector2(x, top), Vector2(2, 1)), Color("e9d9ba", 0.87 * opacity))
		if x % 9 < 4:
			draw_rect(Rect2(origin + Vector2(x, bottom - 1), Vector2(2, 1)), Color("a98a78", 0.68 * opacity))
	PixelText.draw(self, "LEUCHTFARN", Vector2i(origin) + Vector2i(12, 15), Color(TEAL, opacity))
	_rule(origin + Vector2(12, 27), 44, opacity * 0.64)
	draw_texture(FERN, origin + Vector2(65, -9), Color(_paper_light(), opacity))


func _controls(opacity: float) -> void:
	var bar: Rect2 = Rect2(66, 320, 234, 18)
	VineStyle.paper(self, bar, opacity * 0.92, night * 0.5, 142)
	PixelText.draw(self, "Q / E ODER LB / RB  REGISTER WECHSELN", Vector2i(76, 326), Color("ded0df", opacity))


func _bookmark(opacity: float) -> void:
	var x: float = roundf(lerpf(320.0, 561.0, ribbon))
	var bend: float = roundf(8.0 * sin(PI * ribbon))
	var start_y: float = BOOK.position.y + 5.0
	var cloth: Color = Color("514050").lerp(Color("754c38"), ribbon)
	for y: int in 33:
		var drift: float = roundf(bend * y / 32.0)
		var at: Vector2 = Vector2(x + drift, start_y + y)
		var run: int = 7 - mini(maxi(y - 25, 0), 6)
		for side: int in [0, 14 - run]:
			draw_rect(Rect2(at + Vector2(side + 2, 2), Vector2(run, 1)), Color(INK, 0.28 * opacity))
			draw_rect(Rect2(at + Vector2(side, 0), Vector2(run, 1)), Color(cloth.lightened(0.065 * (y % 3)), opacity))
		if y % 2 == 0:
			draw_rect(Rect2(at + Vector2(1, 0), Vector2.ONE), Color(GOLD, 0.75 * opacity))
	if ribbon > 0.03:
		var bud: Vector2 = (Vector2(x + 7 + bend * 0.5, start_y + 14)).round()
		draw_rect(Rect2(bud - Vector2(3, 3), Vector2(7, 7)), Color(INK, opacity * ribbon))
		draw_texture(QuestJournalSkin.icon("focus", GOLD, true), bud - Vector2(4, 4), Color(1, 1, 1, opacity * ribbon))
		VineStyle.bloom(self, bud, (0.35 + 0.65 * seal_flash) * ribbon * opacity, seal_flash * 1.3, 0.0, QuestJournalSkin.GOLD)
		if seal_flash > 0.0:
			for i: int in 5:
				var spread: float = (1.0 - seal_flash) * (10 + i * 2)
				var at: Vector2 = (bud + Vector2(-spread * (0.45 + i * 0.14), -spread * (1.0 - i * 0.17))).round()
				draw_rect(Rect2(at, Vector2.ONE), Color("ffe8a8", seal_flash * ribbon * opacity))


func _draw_turn() -> void:
	if turn >= 1.0 or opening < 0.9:
		return
	var t: float = smoothstep(0.0, 1.0, turn)
	var side: float = cos(t * PI) * (1.0 if toward_archive else -1.0)
	var width: int = roundi(absf(side) * 263.0)
	var sign_x: float = signf(side)
	var alpha: float = smoothstep(0.0, 0.14, turn) * (1.0 - smoothstep(0.75, 1.0, turn))
	var lift: float = 14.0 * sin(PI * turn)
	var fold: float = SPINE + sign_x * float(width)
	_flip.draw_rect(Rect2(fold - 6, 58, 13, 239), Color(INK, 0.19 * alpha))
	for i: int in range(0, width, 3):
		var u: float = float(i) / maxf(float(width), 1.0)
		var bow: float = 2.0 * roundf(lift * sin(u * PI) / 2.0)
		var x: float = SPINE + sign_x * float(i) - (3.0 if sign_x < 0 else 0.0)
		var shade: float = snappedf(0.32 * pow(1.0 - u, 3.0) + 0.18 * pow(u, 8.0), 0.10)
		var texture_x: float = 17.0 + 245.0 * u if sign_x < 0.0 else 294.0 + 245.0 * (1.0 - u)
		var light: Color = _paper_light() * Color(1.04 - shade * 0.43, 1.01 - shade * 0.43, 0.99 - shade * 0.34)
		_flip.draw_texture_rect_region(SHEET, Rect2(x, 57.0 - bow, 3, 239.0 + bow), Rect2(roundf(texture_x), 14, 3, 235), Color(light, alpha))
		_flip.draw_rect(Rect2(x, 57.0 - bow, 3, 1), Color(Color("ede1c6"), alpha))
		if i % 9 == 0:
			_flip.draw_rect(Rect2(x, 294, 3, 1), Color(FAINT, 0.26 * alpha))
