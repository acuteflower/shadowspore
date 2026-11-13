class_name TownEmblems
extends RefCounted
## The town's identity (docs/stadtbau_konzept.md 5.3): eight banner colours and twelve emblems, pixel glyphs drawn straight onto a canvas
## ('#' = the emblem's gold, '+' = its light, an ink outline is added round every pixel). Shown by `TownBanner`, the STADT tab and later on every banner of the town.

const COLORS: Array[Color] = [Color("2f8f86"), Color("7a2434"), Color("2a3a72"), Color("466e34"), Color("b07a22"), Color("5e3482"), Color("cfc3a6"), Color("b4462a")]
const COLOR_NAMES: Array[String] = ["TEAL", "WEINROT", "NACHTBLAU", "MOOS", "BERNSTEIN", "LILA", "KNOCHENWEISS", "GLUT"]
const NAMES: Array[String] = ["LATERNE", "GLIMMKAPPE", "KRÄHE", "TANNE", "MOND", "HAMMER", "ÄHRE", "FISCH", "AUGE", "KNOSPE", "FUCHS", "SCHLÜSSEL"]
const GOLD: Color = Color("ffd27a")
const LIGHT: Color = Color("fff4c8")
const INK: Color = Color("140c1c")
const GLYPHS: Array = [
	["....###....", "...#...#...", "..#######..", "..#.+++.#..", "..#+++++#..", "..#.+++.#..", "..#.+++.#..", "..#######..", "...#...#...", "....###...."],
	["...#####...", ".##+#+#+##.", "#+#######+#", "###########", "....###....", "....#+#....", "....#+#....", "...#####..."],
	["......##...", ".....###+#.", "....######.", "...####....", ".######....", "#######....", "..#####....", "...#.#.....", "..#..#....."],
	[".....#.....", "....###....", "...#####...", "....###....", "..#######..", "...#####...", ".#########.", "..#######..", "###########", ".....#.....", ".....#....."],
	["...#####...", ".####......", ".###....+..", "###.......+", "###...+....", "###........", ".###.......", ".####......", "...#####..."],
	["..#######..", "..###+###..", "..#######..", ".....#.....", ".....#.....", ".....#.....", ".....#.....", ".....#.....", "....###...."],
	[".....#.....", "....#+#....", "...#.#.#...", "....#+#....", "...#.#.#...", "....#+#....", "...#.#.#...", ".....#.....", ".....#.....", ".....#....."],
	["...#####...#", ".#########.#", "##+########.", ".#########.#", "...#####...#"],
	["...#####...", ".##.....##.", "#...###...#", "#..##+##..#", "#...###...#", ".##.....##.", "...#####..."],
	[".....#.....", "...#+#+#...", "..#+++++#..", "..#+++++#..", "...#+++#...", "....###....", ".....#.....", "..##.#.....", "...###.##..", ".....###...", ".....#....."],
	["#.........#", "##.......##", "#+#.....#+#", "#++#####++#", "###########", ".#.#####.#.", ".#########.", "..#######..", "...#####...", "....###....", ".....#....."],
	["..###......", ".#+..#.....", ".#...#.....", "..###......", "...#.......", "...#.......", "...###.....", "...#.......", "...##......"],
]


static func color(index: int) -> Color:
	return COLORS[posmod(index, COLORS.size())]


static func size(index: int) -> Vector2i:
	var rows: Array = GLYPHS[posmod(index, GLYPHS.size())] as Array
	return Vector2i(String(rows[0]).length(), rows.size())


## Draws emblem `index` with its top-left at `at`, every glyph pixel `scale` screen pixels.
static func draw(canvas: CanvasItem, index: int, at: Vector2, scale: float, alpha: float = 1.0, gold: Color = GOLD) -> void:
	var rows: Array = GLYPHS[posmod(index, GLYPHS.size())] as Array
	for pass_index: int in 2:
		for y: int in rows.size():
			var row: String = String(rows[y])
			for x: int in row.length():
				var c: String = row[x]
				if c == ".":
					continue
				var cell: Vector2 = at + Vector2(float(x), float(y)) * scale
				if pass_index == 0:
					canvas.draw_rect(Rect2(cell - Vector2(1, 1), Vector2(scale + 2.0, scale + 2.0)), Color(INK, alpha))
				else:
					canvas.draw_rect(Rect2(cell, Vector2(scale, scale)), Color(LIGHT if c == "+" else gold, alpha))
