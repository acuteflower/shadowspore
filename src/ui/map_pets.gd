class_name MapPets
extends RefCounted
## The registered crows and ravens on the map (M), drawn for `MapWindow` (docs/pet_konzept.md 9.2). Each bird is a small pixel feather in its own ring
## colour where it was last seen, inside a dashed ring that marks its territory (home and favourite spots). The one under the mouse gets a card: name,
## kind, the stage of the bond, when it was last seen and how far away it is. Read-only, nothing to press.

const FEATHER: Array[Vector2i] = [Vector2i(2, -4), Vector2i(3, -4), Vector2i(1, -3), Vector2i(2, -3), Vector2i(3, -3), Vector2i(0, -2), Vector2i(1, -2), Vector2i(2, -2),
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(-2, 1), Vector2i(-3, 2)]
const SPINE: Array[Vector2i] = [Vector2i(1, -1), Vector2i(0, 0), Vector2i(-1, 1), Vector2i(-2, 2), Vector2i(-3, 3)]
const INK: Color = Color("1b1a2e")
const GOLD: Color = Color("e6c468")

var hover: String = "" ## key of the bird the mouse is over
var _screen: Dictionary = {} ## key -> screen position
var _entries: Array[Dictionary] = []


## Every frame the map is visible. `to_screen` maps a tile to the screen.
func update(tree: SceneTree, cursor: Vector2, to_screen: Callable) -> void:
	_entries.clear()
	_screen.clear()
	hover = ""
	var registry: PetRegistry = PetRegistry.of(tree)
	if registry == null:
		return
	var best: float = 11.0
	for entry: Dictionary in registry.records():
		var seen: Vector3 = registry.seen_of(String(entry["key"]))
		var at: Vector2 = to_screen.call(Vector2(seen.x, seen.y) / 16.0) as Vector2
		_entries.append(entry)
		_screen[String(entry["key"])] = at
		var gap: float = at.distance_to(cursor)
		if gap < best:
			best = gap
			hover = String(entry["key"])


func draw(canvas: CanvasItem, scale: float, fade: float, time: float, size: Vector2, tree: SceneTree) -> void:
	var registry: PetRegistry = PetRegistry.of(tree)
	if registry == null or _entries.is_empty():
		return
	var rings: Array = (PetRules.table()["register"] as Dictionary)["ring_colors"] as Array
	var radius: float = (float(((PetRules.table()["territory"] as Dictionary)["radius"] as Array)[1]) + float((PetRules.table()["territory"] as Dictionary)["jitter"])) / 16.0 * scale
	for entry: Dictionary in _entries:
		var key: String = String(entry["key"])
		var at: Vector2 = _screen[key] as Vector2
		if at.x < -40.0 or at.y < -40.0 or at.x > size.x + 40.0 or at.y > size.y + 40.0:
			continue
		var tone: Color = Color(String(rings[int(entry["ring"]) % rings.size()]))
		var home: Array = entry["home"] as Array
		var home_screen: Vector2 = Vector2(float(home[0]), float(home[1])) / 16.0
		var lit: bool = key == hover
		_draw_territory(canvas, (_to_screen_of(at, registry, key, scale, home_screen)), radius, tone, fade, time, lit)
		canvas.draw_set_transform(at.round(), 0.0, Vector2.ONE)
		_feather(canvas, tone, fade, lit, time)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if scale > 0.45 or lit:
			var label: String = String(entry["n"])
			PixelText.draw(canvas, label, Vector2i(roundi(at.x) - PixelText.width(label) / 2, roundi(at.y) + 7), Color(tone.lerp(Color("f1e6ff"), 0.35 if lit else 0.1), 0.95 * fade), Color(INK, 0.9 * fade))
	if hover != "":
		var rec: Dictionary = registry.record(hover)
		var home_h: Array = rec["home"] as Array if not rec.is_empty() else [0.0, 0.0]
		var centre: Vector2 = _to_screen_of(_screen[hover] as Vector2, registry, hover, scale, Vector2(float(home_h[0]), float(home_h[1])) / 16.0)
		_draw_card(canvas, registry, hover, fade, size, centre, radius)


## The screen position of the territory's centre: the home, offset from where the bird was last seen by the difference in world position.
func _to_screen_of(seen_screen: Vector2, registry: PetRegistry, key: String, scale: float, home_tile: Vector2) -> Vector2:
	var seen: Vector3 = registry.seen_of(key)
	return seen_screen + (home_tile - Vector2(seen.x, seen.y) / 16.0) * scale


func _feather(canvas: CanvasItem, tone: Color, fade: float, lit: bool, time: float) -> void:
	var bob: float = roundf(sin(time * 2.4) * (1.0 if lit else 0.0))
	for off: Vector2i in FEATHER:
		for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			canvas.draw_rect(Rect2(Vector2(off + d) + Vector2(0, bob), Vector2.ONE), Color(INK, 0.95 * fade))
	for off: Vector2i in FEATHER:
		canvas.draw_rect(Rect2(Vector2(off) + Vector2(0, bob), Vector2.ONE), Color(tone.lerp(Color.WHITE, 0.15 if lit else 0.0), fade))
	for off: Vector2i in SPINE:
		canvas.draw_rect(Rect2(Vector2(off) + Vector2(0, bob), Vector2.ONE), Color(tone.darkened(0.45), fade))


func _draw_territory(canvas: CanvasItem, centre: Vector2, radius: float, tone: Color, fade: float, time: float, lit: bool) -> void:
	if radius < 4.0:
		return
	var steps: int = clampi(int(radius * 1.6), 36, 160)
	var bright: Color = tone.lerp(Color.WHITE, 0.3)
	for i: int in steps:
		if (i + int(time * 2.0)) % 3 == 0:
			continue ## marching dashes, two of every three points
		var angle: float = float(i) / steps * TAU
		var point: Vector2 = (centre + Vector2.from_angle(angle) * radius).round()
		canvas.draw_rect(Rect2(point - Vector2.ONE, Vector2(4, 4)), Color(INK, 0.55 * fade)) ## dark edge so it reads on every ground
		canvas.draw_rect(Rect2(point, Vector2(2, 2)), Color(bright if lit else tone, (1.0 if lit else 0.85) * fade))
	if lit:
		for i: int in 90: ## the territory is lightly dithered inside while the bird is chosen
			var q: Vector2 = centre + Vector2.from_angle(float(i) * 2.399) * radius * sqrt(float(i) / 90.0)
			canvas.draw_rect(Rect2(q.round(), Vector2.ONE), Color(tone, 0.3 * fade))


func _draw_card(canvas: CanvasItem, registry: PetRegistry, key: String, fade: float, size: Vector2, centre: Vector2, radius: float) -> void:
	var entry: Dictionary = registry.record(key)
	if entry.is_empty():
		return
	var at: Vector2 = _screen[key] as Vector2
	var title: String = String(entry["n"])
	var bp: float = registry.bp_of(key, canvas.multiplayer.get_unique_id())
	var stage_line: String = PetRules.stage_name(PetRules.stage_of(bp))
	var species: String = "KRÄHE" if String(entry["sp"]) == "crow" else "RABE"
	var ago: int = maxi(0, TimeManager.day - int(entry["sd"]))
	var seen_line: String = "HEUTE GESEHEN" if ago == 0 else "VOR %d TAGEN GESEHEN" % ago
	var width: float = maxf(maxf(PixelText.width(title) * 2.0, float(PixelText.width(seen_line))), 104.0) + 24.0
	var box: Rect2 = Rect2(Vector2(at.x - width / 2.0, centre.y + radius + 8.0), Vector2(width, 50.0)) ## below the territory ring, so the ring stays visible
	if box.end.y > size.y - 40.0:
		box.position.y = centre.y - radius - 8.0 - box.size.y ## ...or above it
	if box.position.y < 44.0 or box.end.y > size.y - 40.0:
		box.position.y = at.y + 16.0 ## a ring too big for the screen: beside the bird as before
	box.position = box.position.clamp(Vector2(10, 44), size - box.size - Vector2(10, 40)).round()
	var salt: int = absi(key.hash()) % 997
	VineStyle.paper(canvas, Rect2(box.position + Vector2(2, 3), box.size), fade * 0.35, 1.0, salt)
	VineStyle.paper(canvas, box, fade, VineStyle.void_amount(), salt)
	canvas.draw_set_transform(box.position + Vector2(box.size.x / 2.0 - PixelText.width(title), 6.0), 0.0, Vector2(2, 2))
	PixelText.draw(canvas, title, Vector2i.ZERO, Color(GOLD.lerp(Color("f1e6ff"), 0.3), fade), Color(INK, fade))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mid: int = roundi(box.position.x + box.size.x / 2.0)
	var line: String = "%s  %s" % [species, stage_line]
	PixelText.draw(canvas, line, Vector2i(mid - PixelText.width(line) / 2, roundi(box.position.y + 23.0)), Color(UiStyle.TEXT, 0.95 * fade), Color(INK, 0.9 * fade))
	PixelText.draw(canvas, seen_line, Vector2i(mid - PixelText.width(seen_line) / 2, roundi(box.position.y + 34.0)), Color(UiStyle.TEXT_DIM, 0.95 * fade), Color(INK, 0.9 * fade))
