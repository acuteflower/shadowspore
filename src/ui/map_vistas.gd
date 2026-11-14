class_name MapVistas
extends RefCounted
## Discovered panoramic cliff vistas on the world map (M), drawn for `MapWindow` (`docs/wiesenbiom_ausbau_konzept.md` Stufe 1).
## Each discovered `VistaPoint` appears as a warm-gold mountain-horizon pixel emblem with a soft teal-gold horizon arc.
## Hovering a vista reveals a living bark card with its name, subtitle and distance from the player.

const GOLD: Color = Color("e6c468")
const TEAL: Color = Color("78f4e6")
const INK: Color = Color("1b1a2e")
const PEAKS: Array[Vector2i] = [
	Vector2i(-1, -2),
	Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(2, -1),
	Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(-4, 1), Vector2i(-3, 1), Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
]
const RIDGE_LIGHT: Array[Vector2i] = [
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-3, 0), Vector2i(2, -1), Vector2i(1, 0),
]
const SUN_RAYS: Array[Vector2i] = [
	Vector2i(-3, -4), Vector2i(0, -5), Vector2i(3, -4),
]

var hover: String = "" ## id of the discovered vista under the cursor
var _entries: Array[Dictionary] = []
var _screen: Dictionary = {} ## id -> Vector2
var _tile: Dictionary = {} ## id -> Vector2


func update(tree: SceneTree, cursor: Vector2, to_screen: Callable) -> void:
	_entries.clear()
	_screen.clear()
	_tile.clear()
	hover = ""
	var manager: Vistas = Vistas.of(tree)
	if manager == null:
		return
	var best: float = 12.0
	for spec: Dictionary in manager.entries():
		if not bool(spec.get("seen", false)):
			continue
		var id: String = String(spec.id)
		var tile_arr: Array = spec.tile as Array
		var tile: Vector2 = Vector2(float(tile_arr[0]), float(tile_arr[1]))
		var at: Vector2 = to_screen.call(tile) as Vector2
		_entries.append(spec)
		_tile[id] = tile
		_screen[id] = at
		var gap: float = at.distance_to(cursor)
		if gap < best:
			best = gap
			hover = id


func draw(canvas: CanvasItem, scale: float, fade: float, time: float, size: Vector2, player_tile: Vector2) -> void:
	if _entries.is_empty():
		return
	for spec: Dictionary in _entries:
		var id: String = String(spec.id)
		var at: Vector2 = _screen[id] as Vector2
		if at.x < -32.0 or at.y < -32.0 or at.x > size.x + 32.0 or at.y > size.y + 32.0:
			continue
		var lit: bool = id == hover
		var tile: Vector2 = _tile[id] as Vector2
		var phase: float = 0.5 + 0.5 * sin(time * 1.9 + tile.x * 0.07 + tile.y * 0.05)
		VineStyle.glow(canvas, at, 11.0 + (3.0 if lit else 1.5 * phase), GOLD.lerp(TEAL, 0.28), (0.48 if lit else 0.3) * fade)
		if lit:
			var wave: float = fposmod(time * 0.55, 1.0)
			VineStyle.ring(canvas, at, 8 + int(wave * 11.0), Color(GOLD.lerp(TEAL, 0.35), (1.0 - wave) * 0.75 * fade), 0.6)
		canvas.draw_set_transform(at.round(), 0.0, Vector2.ONE)
		_emblem(canvas, fade, phase, lit)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if scale > 0.55 or lit:
			var label: String = String(spec.get("name", "AUSSICHT"))
			PixelText.draw(
				canvas,
				label,
				Vector2i(roundi(at.x) - PixelText.width(label) / 2, roundi(at.y) + 6),
				Color(GOLD.lerp(Color("f1e6ff"), 0.3 if lit else 0.08), 0.92 * fade),
				Color(INK, 0.9 * fade)
			)
	if hover != "":
		for spec: Dictionary in _entries:
			if String(spec.id) == hover:
				_draw_card(canvas, spec, fade, size, player_tile)
				break


func _emblem(canvas: CanvasItem, fade: float, phase: float, lit: bool) -> void:
	for pass_index: int in 2:
		for cell: Vector2i in PEAKS:
			if pass_index == 0:
				for edge: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					canvas.draw_rect(Rect2(Vector2(cell + edge), Vector2.ONE), Color(INK, 0.92 * fade))
			else:
				var col: Color = Color("7b7699")
				if RIDGE_LIGHT.has(cell):
					col = GOLD.lerp(Color("fff2be"), 0.35 + 0.35 * phase if lit else 0.2 * phase)
				elif cell.y >= 1:
					col = Color("58547a")
				canvas.draw_rect(Rect2(Vector2(cell), Vector2.ONE), Color(col, fade))
	for ray: Vector2i in SUN_RAYS:
		for edge: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			canvas.draw_rect(Rect2(Vector2(ray + edge), Vector2.ONE), Color(INK, 0.8 * fade))
		canvas.draw_rect(Rect2(Vector2(ray), Vector2.ONE), Color(GOLD.lerp(TEAL, 0.25), (0.95 if lit else 0.65 + 0.25 * phase) * fade))
	canvas.draw_rect(Rect2(Vector2(0, -3), Vector2.ONE), Color(Color("fff4c8"), (1.0 if lit else 0.85) * fade))


func _draw_card(canvas: CanvasItem, spec: Dictionary, fade: float, size: Vector2, player_tile: Vector2) -> void:
	var id: String = String(spec.id)
	var at: Vector2 = _screen[id] as Vector2
	var tile: Vector2 = _tile[id] as Vector2
	var title: String = String(spec.get("name", "AUSSICHTSPUNKT"))
	var sub: String = String(spec.get("sub", "AUSSICHTSPUNKT")).to_upper()
	var distance: int = roundi(player_tile.distance_to(tile))
	var dist_line: String = "AUSSICHTSPUNKT  ·  HIER" if distance <= 3 else "AUSSICHTSPUNKT  ·  %d M ENTFERNT" % distance
	var width: float = maxf(maxf(PixelText.width(title) * 2.0, float(PixelText.width(sub))), float(PixelText.width(dist_line))) + 26.0
	width = maxf(width, 120.0)
	var box: Rect2 = Rect2(Vector2(at.x - width / 2.0, at.y + 14.0), Vector2(width, 50.0))
	if box.end.y > size.y - 40.0:
		box.position.y = at.y - 14.0 - box.size.y
	box.position = box.position.clamp(Vector2(10.0, 44.0), size - box.size - Vector2(10.0, 40.0)).round()
	var salt: int = absi(id.hash()) % 997
	VineStyle.paper(canvas, Rect2(box.position + Vector2(2, 3), box.size), fade * 0.35, 1.0, salt)
	VineStyle.paper(canvas, box, fade, VineStyle.void_amount(), salt)
	canvas.draw_set_transform(box.position + Vector2(box.size.x / 2.0 - PixelText.width(title), 6.0), 0.0, Vector2(2, 2))
	PixelText.draw(canvas, title, Vector2i.ZERO, Color(GOLD.lerp(Color("f1e6ff"), 0.28), fade), Color(INK, fade))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mid: int = roundi(box.position.x + box.size.x / 2.0)
	PixelText.draw(canvas, sub, Vector2i(mid - PixelText.width(sub) / 2, roundi(box.position.y + 23.0)), Color(TEAL.lerp(UiStyle.TEXT, 0.45), 0.95 * fade), Color(INK, 0.9 * fade))
	PixelText.draw(canvas, dist_line, Vector2i(mid - PixelText.width(dist_line) / 2, roundi(box.position.y + 34.0)), Color(UiStyle.TEXT_DIM, 0.95 * fade), Color(INK, 0.9 * fade))
