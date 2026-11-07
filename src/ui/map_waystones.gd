class_name MapWaystones
extends RefCounted
## The waystones on the map (M), drawn and operated for `MapWindow` (docs/waystones.md). Awakened statues stand there as a small pixel emblem: a halo ring with
## crystal rays over a crystal on its plinth, breathing teal and gold. Normally they are just marks with a name. In TRAVEL mode (the map was opened at a statue,
## `MapWindow.open_travel`) every other awakened statue is highlighted: bigger, with rings that pulse outwards, the one the mouse is over (or the arrow keys
## selected) with a dotted route from here and a card; HOLDING the left mouse button (or E) on it fills a ring of light, and when it closes `update` returns its id.

const HOLD_SECONDS: float = 1.15
const TEAL: Color = Color("78f4e6")
const GOLD: Color = Color("e6c468")
const VIOLET: Color = Color("b99bff")
const CRYSTAL: Array[Vector2i] = [Vector2i(0, -4), Vector2i(0, -3), Vector2i(-1, -2), Vector2i(0, -2), Vector2i(1, -2), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2)]
const RAYS: Array[Vector2i] = [Vector2i(-5, -2), Vector2i(-4, -4), Vector2i(-2, -6), Vector2i(0, -7), Vector2i(2, -6), Vector2i(4, -4), Vector2i(5, -2)]
const PLINTH: Array[Vector2i] = [Vector2i(-3, 4), Vector2i(-2, 4), Vector2i(-1, 4), Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(-2, 5), Vector2i(-1, 5),
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5)]

var travel_from: String = "" ## the statue she stands at; "" = the map is just looked at
var hover: String = "" ## the awakened statue the mouse is over
var selected: String = "" ## chosen with the arrow keys
var target: String = "" ## what holding would travel to right now
var hold: float = 0.0 ## 0..1 the ring of light closing round the target
var _ids: Array[String] = []
var _screen: Dictionary = {} ## id -> screen position
var _tile: Dictionary = {} ## id -> tile
var _name: Dictionary = {} ## id -> name
var _awake: Dictionary = {} ## id -> bool
var _age: float = 0.0


## Everything of a statue the map needs, for the one with `id` (tile in tile units).
func tile_of(id: String) -> Vector2:
	return _tile.get(id, Vector2.ZERO) as Vector2


func destinations() -> Array[String]:
	var list: Array[String] = []
	for id: String in _ids:
		if bool(_awake[id]) and id != travel_from:
			list.append(id)
	if travel_from != "":
		var origin: Vector2 = tile_of(travel_from)
		list.sort_custom(func(a: String, b: String) -> bool: return tile_of(a).distance_to(origin) < tile_of(b).distance_to(origin))
	return list


## Called every frame while the map is visible. `to_screen` maps a tile to the screen. Returns the id of the statue the player finished holding on ("" otherwise).
func update(delta: float, tree: SceneTree, cursor: Vector2, to_screen: Callable, mouse_hold: bool, key_hold: bool, key_step: int) -> String:
	_age += delta
	var manager: Waystones = Waystones.of(tree)
	_ids.clear()
	if manager != null:
		for entry: Dictionary in manager.entries():
			var id: String = String(entry.id)
			var tile: Array = entry.tile as Array
			_ids.append(id)
			_tile[id] = Vector2(float(tile[0]), float(tile[1]))
			_name[id] = String(entry.name)
			_awake[id] = bool(entry.awake)
			_screen[id] = to_screen.call(_tile[id]) as Vector2
	hover = ""
	var best: float = 15.0
	for id: String in _ids:
		if not bool(_awake[id]):
			continue
		var distance: float = (_screen[id] as Vector2).distance_to(cursor)
		if distance < best:
			best = distance
			hover = id
	if travel_from == "":
		target = ""
		hold = 0.0
		return ""
	var list: Array[String] = destinations()
	if not list.has(selected):
		selected = list[0] if not list.is_empty() else ""
	if key_step != 0 and not list.is_empty():
		selected = list[posmod(list.find(selected) + key_step, list.size())]
	if list.has(hover):
		selected = hover
	target = selected
	var holding: bool = target != "" and ((mouse_hold and hover == target) or key_hold)
	hold = move_toward(hold, 1.0 if holding else 0.0, delta / HOLD_SECONDS if holding else delta * 2.5)
	if hold >= 1.0 and target != "":
		var chosen: String = target
		hold = 0.0
		return chosen
	return ""


## True while the mouse is over a statue the player could travel to (the press then starts the hold instead of a drag).
func can_press() -> bool:
	return travel_from != "" and hover != "" and hover != travel_from and bool(_awake.get(hover, false))


## `ring`: the fog-lifting ring of a statue that has just woken (`MapWindow.present`): [statue tile, radius in tiles, age in seconds].
func draw(canvas: CanvasItem, scale: float, fade: float, time: float, size: Vector2, ring: Array) -> void:
	var traveling: bool = travel_from != ""
	if traveling:
		_draw_route(canvas, fade, time)
	for id: String in _ids:
		if not bool(_awake[id]):
			continue
		var at: Vector2 = _screen[id] as Vector2
		if not ring.is_empty() and (_tile[id] as Vector2).distance_to(ring[0] as Vector2) < 2.0:
			_draw_wake_rings(canvas, at, float(ring[1]) * scale, float(ring[2]), fade)
		if at.x < -30.0 or at.y < -30.0 or at.x > size.x + 30.0 or at.y > size.y + 30.0:
			continue
		var here: bool = traveling and id == travel_from
		var choice: bool = traveling and not here
		var lit: bool = id == target and choice
		_draw_marker(canvas, at, id, here, choice, lit, scale, fade, time)
	if traveling and target != "":
		_draw_card(canvas, target, fade, size, time)


func _draw_marker(canvas: CanvasItem, at: Vector2, id: String, here: bool, choice: bool, lit: bool, scale: float, fade: float, time: float) -> void:
	var tone: Color = GOLD if here else TEAL
	var phase: float = 0.5 + 0.5 * sin(time * 2.2 + (_tile[id] as Vector2).x)
	var big: float = 2.0 if choice else 1.0
	var glow: float = 13.0 * big
	VineStyle.glow(canvas, at, glow + 3.0 * phase, tone, (0.55 if choice else 0.4) * fade * (0.8 + 0.2 * phase))
	if choice: # the invitation: two rings that pulse outwards, a third on the one the mouse is over
		for k: int in (3 if lit else 2):
			var t: float = fposmod(time * 0.55 + k * (0.34 if lit else 0.5), 1.0)
			VineStyle.ring(canvas, at, 12 + int(t * (24.0 if lit else 17.0)), Color(tone, (1.0 - t) * (0.85 if lit else 0.5) * fade), 0.6)
	canvas.draw_set_transform(at.round(), 0.0, Vector2(big, big))
	_emblem(canvas, tone, fade, phase, lit, here)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if lit:
		_draw_hold(canvas, at, fade, time)
	if scale > 0.45 or choice or here:
		var label: String = "HIER" if here else String(_name[id])
		var y: float = 9.0 + (9.0 * big if choice else 0.0) * 0.5
		PixelText.draw(canvas, label, Vector2i(roundi(at.x) - PixelText.width(label) / 2, roundi(at.y + y)), Color(tone.lerp(Color("f1e6ff"), 0.25 if lit else 0.0), 0.95 * fade), Color(VineStyle.OUTLINE, 0.9 * fade))


## The emblem in local pixels (0,0 = the middle of the crystal): crown rays over a halo ring, a crystal, a plinth. Outline first, then the colour.
func _emblem(canvas: CanvasItem, tone: Color, fade: float, phase: float, lit: bool, here: bool) -> void:
	var shapes: Array[Array] = [PLINTH, CRYSTAL, RAYS]
	for pass_index: int in 2:
		for shape: Array in shapes:
			for cell: Vector2i in shape:
				if pass_index == 0:
					for edge: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						canvas.draw_rect(Rect2(Vector2(cell + edge), Vector2.ONE), Color(VineStyle.OUTLINE, 0.9 * fade))
				else:
					var color: Color = Color("6d6a9a") if shape == PLINTH else (tone if shape == CRYSTAL else GOLD)
					if shape == CRYSTAL and cell.x <= 0 and cell.y <= 0:
						color = color.lerp(Color("f1e6ff"), 0.45 + 0.25 * phase)
					elif shape == RAYS:
						color = GOLD.lerp(Color("fff0b0"), phase * (0.8 if lit else 0.3))
					canvas.draw_rect(Rect2(Vector2(cell), Vector2.ONE), Color(color, fade))
	for i: int in 12: # the halo ring behind the head
		var a: float = TAU * i / 12.0
		var p: Vector2 = Vector2(roundf(cos(a) * 5.0), roundf(sin(a) * 5.0) - 3.0)
		if p.y < -1.0 or absf(p.x) > 3.0:
			canvas.draw_rect(Rect2(p, Vector2.ONE), Color(GOLD, (0.9 if i % 2 == 0 else 0.5) * fade))


## The hold: a ring of gold-white pixels closing round the emblem, with sparks at its tip.
func _draw_hold(canvas: CanvasItem, at: Vector2, fade: float, time: float) -> void:
	if hold <= 0.01:
		return
	var steps: int = 40
	var done: int = int(hold * steps)
	for i: int in done:
		var a: float = -PI / 2.0 + TAU * i / float(steps)
		var p: Vector2 = at + Vector2(cos(a), sin(a)) * 19.0
		canvas.draw_rect(Rect2(p.round() - Vector2.ONE, Vector2(3, 3)), Color(VineStyle.OUTLINE, 0.8 * fade))
	for i: int in done:
		var a2: float = -PI / 2.0 + TAU * i / float(steps)
		var q: Vector2 = at + Vector2(cos(a2), sin(a2)) * 19.0
		canvas.draw_rect(Rect2(q.round(), Vector2.ONE), Color(GOLD.lerp(Color("ffffff"), float(i) / steps), fade))
	var tip: float = -PI / 2.0 + TAU * hold
	VineStyle.glow(canvas, at + Vector2(cos(tip), sin(tip)) * 19.0, 6.0, Color("fff0b0"), 0.8 * fade)
	VineStyle.glow(canvas, at, 14.0 + 10.0 * hold, TEAL, 0.35 * hold * fade)


## A dotted route from here to the chosen statue (it marches), curved a little.
func _draw_route(canvas: CanvasItem, fade: float, time: float) -> void:
	if target == "" or not _screen.has(travel_from) or not _screen.has(target):
		return
	var a: Vector2 = _screen[travel_from] as Vector2
	var b: Vector2 = _screen[target] as Vector2
	var mid: Vector2 = (a + b) / 2.0 + Vector2(0, -a.distance_to(b) * 0.18)
	var length: float = a.distance_to(b)
	var count: int = clampi(int(length / 4.0), 8, 300)
	var march: float = time * 14.0
	for i: int in count:
		var t: float = float(i) / count
		var p: Vector2 = a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		if (i + int(march)) % 3 != 0:
			continue
		canvas.draw_rect(Rect2(p.round(), Vector2.ONE), Color(TEAL.lerp(GOLD, t), (0.35 + 0.45 * (1.0 - absf(t - 0.5) * 1.4)) * fade))


## What has just woken: rings of light running out of the statue as the fog clears.
func _draw_wake_rings(canvas: CanvasItem, at: Vector2, radius: float, age: float, fade: float) -> void:
	if age < 0.9:
		return
	var run: float = clampf((age - 0.9) / 2.6, 0.0, 1.0)
	for k: int in 3:
		var rk: float = clampf(run * 1.25 - k * 0.14, 0.0, 1.0)
		if rk <= 0.0 or rk >= 1.0:
			continue
		var r: float = radius * (1.0 - pow(1.0 - rk, 2.2))
		VineStyle.ring(canvas, at, int(r), Color(Color("9ff5ec") if k != 1 else VineStyle.LEAF_VOID_LIGHT, (1.0 - rk) * 0.8 * fade), 0.55)


## The card of the chosen destination: bark paper with the name, how far it is and what to hold.
func _draw_card(canvas: CanvasItem, id: String, fade: float, size: Vector2, time: float) -> void:
	var at: Vector2 = _screen[id] as Vector2
	var title: String = String(_name[id])
	var distance: int = roundi(tile_of(id).distance_to(tile_of(travel_from)))
	var line: String = "%d M ENTFERNT" % distance
	var width: float = maxf(PixelText.width(title) * 2.0, 112.0) + 24.0
	var box: Rect2 = Rect2(at + Vector2(-width / 2.0, 30.0), Vector2(width, 49.0))
	if box.end.y > size.y - 40.0:
		box.position.y = at.y - 30.0 - box.size.y - 14.0
	box.position = box.position.clamp(Vector2(10, 44), size - box.size - Vector2(10, 40)).round()
	var salt: int = absi(id.hash()) % 997
	VineStyle.paper(canvas, Rect2(box.position + Vector2(2, 3), box.size), fade * 0.35, 1.0, salt)
	VineStyle.paper(canvas, box, fade, VineStyle.void_amount(), salt)
	canvas.draw_set_transform(box.position + Vector2(box.size.x / 2.0 - PixelText.width(title), 7.0), 0.0, Vector2(2, 2))
	PixelText.draw(canvas, title, Vector2i.ZERO, Color(TEAL.lerp(Color("f1e6ff"), 0.3), fade), Color(VineStyle.OUTLINE, fade))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	PixelText.draw(canvas, line, Vector2i(roundi(box.position.x + box.size.x / 2.0) - PixelText.width(line) / 2, roundi(box.position.y + 26.0)), Color(UiStyle.TEXT_DIM, 0.95 * fade), Color(VineStyle.OUTLINE, 0.9 * fade))
	var verb: String = "HALTEN: REISEN"
	var cap: String = VineStyle.MOUSE_LEFT
	var cap_w: int = VineStyle.cap_width(cap)
	var total: int = cap_w + 4 + PixelText.width(verb)
	var x0: float = box.position.x + box.size.x / 2.0 - total / 2.0
	VineStyle.key_cap(canvas, Vector2(x0, box.position.y + 34.0), cap, fade, clampf(hold * 2.0, 0.0, 1.0), VineStyle.void_amount())
	PixelText.draw(canvas, verb, Vector2i(roundi(x0) + cap_w + 4, roundi(box.position.y + 37.0)), Color(UiStyle.TEXT, 0.9 * fade), Color(VineStyle.OUTLINE, 0.9 * fade))
