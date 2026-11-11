class_name QuestJournalSkin
extends RefCounted
## Book fittings are tiled pixel strips. The actual buttons keep Godot's mouse,
## keyboard and controller focus, but share the inked edges of the world UI.

const OUTLINE: Color = Color("201525")
const GOLD: Color = Color("e3c184")
const TEAL: Color = Color("8fd3bc")
const ROSE: Color = Color("d49a9c")
const PALE: Color = Color("dfd2df")
const PAPER_INK: Color = Color("3e2b3b")
const MARKS: Dictionary = {
	"story": ["...##....", "..#++#...", "..#+.#...", ".#+.#....", ".#.#.....", ".##......", ".#.......", "#........", "........."],
	"fetch": [".........", "..#####..", ".#+++++#.", ".#.+...#.", ".#+++..#.", ".#.+...#.", ".#.....#.", "..#####..", "........."],
	"kill": [".#..#..#.", "..#..#..#", "..#..#..#", ".#..#..#.", ".#..#..#.", "#..#..#..", ".........", ".........", "........."],
	"focus": ["....#....", "....+....", "..#.+.#..", "...#+#...", "##++#++##", "...#+#...", "..#.+.#..", "....+....", "....#...."],
	"ready": [".........", ".........", ".......#.", "......#+.", ".#...#+..", "..#.#+...", "...#+....", ".........", "........."],
	"expired": ["..#####..", "...#.#...", "...#+#...", "....#....", "....#....", "...#+#...", "...#.#...", "..#####..", "........."],
	"abandoned": [".........", "......#..", ".....#+..", "....#+...", "...#+....", "..#+.....", ".#+......", ".........", "........."],
	"archive": [".........", ".#######.", ".#+++++#.", ".#######.", "..#...#..", "..#+++#..", "..#...#..", "..#####..", "........."],
	"map": [".........", ".##...#..", ".#.#.#.#.", ".#..#..#.", ".#..+..#.", ".#..#..#.", ".#.#.#.#.", "..#...##.", "........."],
	"close": [".........", "..#...#..", "...#.#...", "....#....", "...#.#...", "..#...#..", ".........", ".........", "........."],
}

static var _styles: Dictionary = {}
static var _icons: Dictionary = {}


static func action(button: Button, role: String, glyph: String = "") -> void:
	var paper: bool = role == "filter"
	var ink: Color = PAPER_INK if paper else PALE
	var bright: Color = PAPER_INK if paper else Color("fff1cd")
	var palette: Array[Color] = _palette(role)
	var tone: Color = palette[2]
	button.add_theme_constant_override("h_separation", 3)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, _plate(role, state))
	button.add_theme_stylebox_override("focus", _focus_edge(role))
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", bright)
	button.add_theme_color_override("font_focus_color", bright)
	button.add_theme_color_override("font_pressed_color", bright)
	button.add_theme_color_override("font_hover_pressed_color", bright)
	if glyph != "":
		button.icon = icon(glyph, tone, not paper)


static func list_item(style: String) -> StyleBoxTexture:
	return _plate("selection", style)


static func scroll_track(grab: bool) -> StyleBoxTexture:
	var key: String = "thumb" if grab else "rail"
	if _styles.has(key):
		return _styles[key] as StyleBoxTexture
	var strip: Image = Image.create(5, 11, false, Image.FORMAT_RGBA8)
	if grab:
		strip.fill_rect(Rect2i(1, 0, 3, 11), Color("87655f"))
		strip.fill_rect(Rect2i(0, 2, 5, 7), Color("87655f"))
		strip.fill_rect(Rect2i(1, 2, 3, 7), Color("b09879"))
		for y: int in [3, 6]:
			strip.set_pixel(1, y, Color("d0b48a"))
	else:
		strip.fill_rect(Rect2i(2, 0, 1, 11), Color("8b7164", 0.54))
		strip.fill_rect(Rect2i(3, 0, 1, 11), Color("ede1c8", 0.60))
	var style: StyleBoxTexture = _patch(strip, 1, 4, 3, 4 if grab else 0)
	_styles[key] = style
	return style


static func paper_inset() -> StyleBoxEmpty:
	var inset: StyleBoxEmpty = StyleBoxEmpty.new()
	inset.set_content_margin(SIDE_LEFT, 14)
	inset.set_content_margin(SIDE_RIGHT, 23)
	inset.set_content_margin(SIDE_TOP, 10)
	inset.set_content_margin(SIDE_BOTTOM, 9)
	return inset


static func draw_pinned_paper(panel: Control, paper: Color, wax: Color, mark: String) -> void:
	var width: int = floori(panel.size.x)
	var height: int = floori(panel.size.y)
	if width < 35 or height < 20:
		return
	var rim: Color = paper.darkened(0.20)
	var shine: Color = paper.lightened(0.35)
	for x: int in range(0, width - 2, 2):
		var corner: int = maxi(4 - mini(x, width - 3 - x), 0)
		var top: int = corner + int(VineStyle.rand(x / 6 + 25) > 0.69)
		var bottom: int = height - 2 - corner - 2 * int(VineStyle.rand(x / 4 + 781) > 0.56)
		if x >= width - 13:
			top += (x - width + 13) / 2
		panel.draw_rect(Rect2(x + 2, top + 2, 2, bottom - top), Color(PAPER_INK, 0.25))
		panel.draw_rect(Rect2(x, top, 2, bottom - top), paper)
		panel.draw_rect(Rect2(x, top, 2, 1), shine)
		panel.draw_rect(Rect2(x, bottom - 1, 2, 1), rim)
		if VineStyle.rand(x / 2 + 416) > 0.77:
			var fiber_y: float = top + 3 + floorf(VineStyle.rand(x + 14) * (bottom - top - 6))
			panel.draw_rect(Rect2(x, fiber_y, 2, 1), Color(rim, 0.24))
	for step: int in 4:
		panel.draw_rect(Rect2(width - 13 + step * 2, 1 + step, 2, 5 - step), shine)
		panel.draw_rect(Rect2(width - 13 + step * 2, 6, 2, 1), rim)
	panel.draw_rect(Rect2(5, 4, 4, 4), BoardNotes.PIN.darkened(0.38))
	panel.draw_rect(Rect2(5, 4, 3, 2), BoardNotes.PIN)
	panel.draw_rect(Rect2(5, 4, 1, 1), BoardNotes.PIN.lightened(0.48))
	var stamp: Vector2 = Vector2(width - 18, height - 17)
	panel.draw_rect(Rect2(stamp + Vector2(2, 3), Vector2(13, 11)), Color(PAPER_INK, 0.24))
	panel.draw_rect(Rect2(stamp + Vector2(2, 0), Vector2(10, 14)), wax.darkened(0.37))
	panel.draw_rect(Rect2(stamp + Vector2(0, 3), Vector2(14, 8)), wax.darkened(0.37))
	panel.draw_rect(Rect2(stamp + Vector2(1, 3), Vector2(12, 7)), wax)
	panel.draw_rect(Rect2(stamp + Vector2(3, 1), Vector2(8, 11)), wax)
	panel.draw_rect(Rect2(stamp + Vector2(3, 1), Vector2(6, 1)), wax.lightened(0.27))
	panel.draw_texture(icon(mark, wax.lightened(0.54), true), stamp + Vector2(2, 2))


static func icon(id: String, tone: Color, on_dark: bool = false) -> Texture2D:
	var key: String = "%s:%s:%s" % [id, tone.to_html(), on_dark]
	if not _icons.has(key):
		var image: Image = Image.create(9, 9, false, Image.FORMAT_RGBA8)
		var rows: Array = MARKS.get(id, MARKS.fetch)
		var main: Color = tone if on_dark else tone.darkened(0.25)
		for y: int in rows.size():
			var row: String = rows[y]
			for x: int in row.length():
				if row[x] == "#":
					image.set_pixel(x, y, main)
				elif row[x] == "+":
					image.set_pixel(x, y, main.lightened(0.20))
		_icons[key] = ImageTexture.create_from_image(image)
	return _icons[key] as Texture2D


static func _palette(role: String) -> Array[Color]:
	match role:
		"register": return [Color("3b2c40"), Color("75596b"), GOLD]
		"focus": return [Color("413042"), Color("886548"), GOLD]
		"map": return [Color("2e3940"), Color("56716e"), TEAL]
		"abandon": return [Color("443040"), Color("805560"), ROSE]
		"filter": return [Color("c2aa91", 0.65), Color("9f7f6f"), Color("7a604f")]
		"selection": return [Color("b59b84", 0.44), Color("9e7e6e"), Color("4f7665")]
		_: return [Color("342639"), Color("6d566b"), PALE]


static func _plate(role: String, state: String) -> StyleBoxTexture:
	var key: String = role + ":" + state
	if _styles.has(key):
		return _styles[key] as StyleBoxTexture
	var palette: Array[Color] = _palette(role)
	var fill: Color = palette[0]
	var rim: Color = palette[1]
	var accent: Color = palette[2]
	var active: bool = state in ["pressed", "hover_pressed", "selected", "selected_focus"]
	var light: bool = state in ["hover", "hover_pressed", "selected_focus"]
	var paper: bool = role in ["filter", "selection"]
	if active:
		fill = Color(fill.lerp(accent, 0.22 if paper else 0.16), 0.62 if paper else 1.0)
		rim = rim.lerp(accent, 0.44)
	elif light:
		fill = fill.lightened(0.09)
		rim = rim.lightened(0.14)
	var image: Image = Image.create(29, 19, false, Image.FORMAT_RGBA8)
	for x: int in 29:
		var side: int = mini(x, 28 - x)
		var notch: int = maxi(0, 3 - side)
		var rough: int = int(VineStyle.rand(x / 2 + 17) > 0.67)
		var top: int = 1 + notch + rough
		var bottom: int = 18 - notch - int(VineStyle.rand(x / 3 + 61) > 0.68)
		for y: int in range(top, bottom):
			var color: Color = fill
			if y == top or x in [0, 28]:
				color = Color(rim, 0.56 if paper and not active else 1.0)
			elif y == bottom - 1:
				color = Color(rim.darkened(0.31), 0.43) if paper else OUTLINE
			elif y == top + 1:
				color = Color(rim.lightened(0.14), 0.35 if paper else 0.77)
			elif VineStyle.rand(x / 4 + y * 59 + 37) > 0.87:
				color = fill.lerp(rim, 0.14)
			image.set_pixel(x, y, color)
	if role == "register" or role == "focus":
		for x: int in [4, 22]:
			image.fill_rect(Rect2i(x, 14, 3, 1), Color(accent, 0.85 if active else 0.45))
	if role == "filter" and active:
		image.fill_rect(Rect2i(5, 14, 19, 2), Color("6a8b76", 0.72))
		image.fill_rect(Rect2i(5, 14, 3, 1), Color("a2b89a"))
	if role == "selection" and active:
		image.fill_rect(Rect2i(2, 5, 2, 9), accent if light else rim)
	var style: StyleBoxTexture = _patch(image, 6, 5, 6, 4)
	_styles[key] = style
	return style


static func _focus_edge(role: String) -> StyleBoxTexture:
	var key: String = role + ":key-focus"
	if _styles.has(key):
		return _styles[key] as StyleBoxTexture
	var image: Image = Image.create(15, 15, false, Image.FORMAT_RGBA8)
	var tone: Color = Color("75ae99") if role == "filter" else Color("e7c886")
	for at: Vector2i in [Vector2i(1, 1), Vector2i(11, 1), Vector2i(1, 13), Vector2i(11, 13)]:
		image.fill_rect(Rect2i(at, Vector2i(3, 1)), tone)
	image.fill_rect(Rect2i(1, 2, 1, 2), tone)
	image.fill_rect(Rect2i(13, 2, 1, 2), tone)
	image.fill_rect(Rect2i(1, 11, 1, 2), tone)
	image.fill_rect(Rect2i(13, 11, 1, 2), tone)
	var style: StyleBoxTexture = _patch(image, 4, 4, 0, 0)
	_styles[key] = style
	return style


static func _patch(image: Image, x: int, y: int, h_pad: int, v_pad: int) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		var horizontal: bool = side in [SIDE_LEFT, SIDE_RIGHT]
		style.set_texture_margin(side, x if horizontal else y)
		style.set_content_margin(side, h_pad if horizontal else v_pad)
	return style
