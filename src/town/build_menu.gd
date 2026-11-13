class_name BuildMenu
extends CanvasLayer
## The build mode's menu ("Der Bauplan", docs/stadtbau_konzept.md 1; first version docs/town.md), grown like the hotbar: a branch above the hotbar with the categories hanging from it as name tags (the same tags as the Escape
## menu's, the last one is the demolish tool), under them a thinner vine out of the branch with the pieces of the open category hanging from it as pendants (number keys
## on them, the chosen one lifts and glows, a bloom opens on the vine above it) and beside the pendants a small leaf of bark paper: name, build time, what it is for (or
## what stops it right now, in red) and the cost as chips (red where the stock and the bag fall short). In the demolish tool the leaf says what the piece under the
## cursor gives back. Everything is see-through except the tags, the pendants and the leaf, and the whole thing dims while the piece to be set lies behind it, so the
## ground you aim at stays visible. `BuildMode` owns it and calls `over_card` / `click`.

const STRIDE: float = 46.0 ## between the cards
const PEND: float = 40.0 ## a card's width
const CARD_H: float = 50.0
const FIRST: float = 28.0 ## the first card's middle, from the branch's left end
const INFO_MIN: float = 206.0 ## the big card's least width
const MIN_W: float = 300.0
const HEIGHT: float = 112.0
const BOTTOM: float = 40.0 ## free ground between the menu and the screen's lower edge (the hotbar's vine)
const PREVIEW: Shader = preload("res://assets/shaders/build_preview.gdshader")
const PLAN: Shader = preload("res://assets/shaders/blueprint.gdshader")
const TAG_GAP: float = 5.0
const OPEN_SECONDS: float = 0.9
const DEMOLISH_LABEL: String = "X ABRISS"
const TEXT: Color = Color("e9dcff")
const DIM: Color = Color("8f7fb0")
const LIT: Color = Color("78f4e6")
const GOLD: Color = Color("d9b25f")
const BAD: Color = Color("e0556e")
const SHADOW: Color = Color("0a0612")

var mode: BuildMode
var _canvas: Control
var _time: float = 0.0
var _open: float = 0.0 ## 0..1 while the branch grows in
var _was_shown: bool = false
var _fade: float = 1.0
var _toast_text: String = ""
var _toast_good: bool = false
var _toast_left: float = 0.0
var _tags: Array[Rect2] = [] ## the categories, then the demolish tool
var _slots: Array[Rect2] = [] ## the pendants of the open category
var _hit: Array[Rect2] = [] ## everything that catches the mouse
var _bounds: Rect2 = Rect2()
var _lift: Dictionary = {} ## piece id -> how far its pendant is raised
var _tab_lift: Dictionary = {} ## tag index -> how far it is raised (open 3, hovered 2)
var _plans: Control ## draws the locked cards' pictures as blueprints (its own material)
var _plan_list: Array = [] ## [texture, rect, alpha]
var _mini: Control ## draws the big card's picture building itself up in a loop (build_preview.gdshader)
var _mini_draw: Array = [] ## [texture, rect, alpha] or empty
var _mini_mat: ShaderMaterial
var _mini_clock: float = 0.0
var _last_piece: String = ""
var _flip: Dictionary = {} ## piece id -> 0..1 how far its card has turned in (a new category deals them out)


func setup(owner_mode: BuildMode) -> void:
	mode = owner_mode
	layer = 26
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw)
	add_child(_canvas)
	_plans = Control.new()
	_plans.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plans.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plan: ShaderMaterial = ShaderMaterial.new()
	plan.shader = PLAN
	plan.set_shader_parameter("tint", Color(0.62, 0.55, 0.95, 0.9))
	plan.set_shader_parameter("scan_speed", 0.35)
	_plans.material = plan
	_plans.draw.connect(func() -> void:
		for entry: Array in _plan_list:
			_plans.draw_texture_rect(entry[0] as Texture2D, entry[1] as Rect2, false, Color(1, 1, 1, float(entry[2]))))
	_canvas.add_child(_plans)
	_mini = Control.new()
	_mini.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_mat = ShaderMaterial.new()
	_mini_mat.shader = PREVIEW
	_mini.material = _mini_mat
	_mini.draw.connect(func() -> void:
		if not _mini_draw.is_empty():
			_mini.draw_texture_rect(_mini_draw[0] as Texture2D, _mini_draw[1] as Rect2, false, Color(1, 1, 1, float(_mini_draw[2]))))
	_canvas.add_child(_mini)


func toast(text: String, good: bool) -> void:
	_toast_text = text
	_toast_good = good
	_toast_left = 2.6


func _process(delta: float) -> void:
	_time += delta
	_toast_left = maxf(_toast_left - delta, 0.0)
	if visible != _was_shown:
		_was_shown = visible
		_open = 0.0
	if visible:
		_open = minf(_open + delta / OPEN_SECONDS, 1.0)
		_fade = lerpf(_fade, 0.3 if _ghost_behind() else 1.0, 1.0 - exp(-8.0 * delta))
		var at: Vector2 = _canvas.get_local_mouse_position()
		for i: int in _tags.size():
			var open: bool = (i == mode.category and not mode.demolish) if i < mode.categories().size() else mode.demolish
			var over: bool = InputManager.using_mouse and _tags[i].has_point(at)
			_tab_lift[i] = lerpf(float(_tab_lift.get(i, 0.0)), 3.0 if open else (2.0 if over else 0.0), 1.0 - exp(-14.0 * delta))
		var list: Array[String] = mode.pieces_here()
		for i: int in list.size():
			var id: String = list[i]
			_lift[id] = lerpf(float(_lift.get(id, 0.0)), 5.0 if id == mode.piece and not mode.demolish else 0.0, 1.0 - exp(-14.0 * delta))
			var was: float = float(_flip.get(id, 0.0))
			_flip[id] = minf(was + delta * 5.0, 1.0) if _open > 0.4 + 0.07 * float(i) else was
			if was < 0.5 and float(_flip[id]) >= 0.5:
				_ui_sound("card_in", -16.0)
		if mode.piece != _last_piece:
			_last_piece = mode.piece
			_mini_clock = 0.0
			if visible and _open >= 1.0:
				_ui_sound("card_flip", -10.0)
		_mini_clock += delta
	else:
		_fade = 1.0
	_canvas.modulate.a = _fade
	if visible or _toast_left > 0.0:
		_canvas.queue_redraw()


## True while the piece that would be set (or the one to be torn down) lies behind the menu on the screen: then it steps back.
func _ghost_behind() -> bool:
	if over_card():
		return false
	var world: Rect2 = Rect2()
	if mode.demolish:
		if mode.target_id < 0 or not mode.town.structures.has(mode.target_id):
			return false
		world = mode.town.rect_of(mode.target_id)
	elif mode.piece != "":
		world = TownRules.foot_rect(mode.piece, mode.pos.x, mode.pos.y)
	else:
		return false
	var view: Transform2D = get_viewport().get_canvas_transform()
	return Rect2(view * world.position, world.size * view.get_scale()).grow(6.0).intersects(_bounds)


## Forget how the cards lay: a new category deals its cards out again.
func deal() -> void:
	_flip.clear()


func _ui_sound(file: String, db: float) -> void:
	var path: String = "res://assets/audio/town/%s.wav" % file
	if not ResourceLoader.exists(path):
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = load(path) as AudioStream
	player.volume_db = db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _widest() -> int:
	var widest: int = 1
	for cat: Dictionary in mode.categories():
		widest = maxi(widest, TownRules.in_category(String(cat.id)).size())
	return widest


## The branch's rectangle: wide enough for all tags and for the widest category's pendants beside the leaf, the same size in every category.
func _frame() -> Rect2:
	var tags: float = 0.0
	for cat: Dictionary in mode.categories():
		tags += float(PixelText.width(String(cat.name)) + 10) + TAG_GAP
	tags += float(PixelText.width(DEMOLISH_LABEL) + 10) + 26.0
	var width: float = roundf(maxf(MIN_W, maxf(26.0 + tags + 8.0, FIRST + float(_widest()) * STRIDE + INFO_MIN + 14.0)))
	return Rect2(roundf((_canvas.size.x - width) / 2.0), _canvas.size.y - BOTTOM - HEIGHT, width, HEIGHT)


func over_card() -> bool:
	if not visible or not InputManager.using_mouse:
		return false
	var at: Vector2 = _canvas.get_local_mouse_position()
	for rect: Rect2 in _hit:
		if rect.has_point(at):
			return true
	return false


func click() -> void:
	var at: Vector2 = _canvas.get_local_mouse_position()
	var list: Array[String] = mode.pieces_here()
	for i: int in _slots.size():
		if _slots[i].has_point(at) and i < list.size():
			mode.select(list[i])
			return
	var cats: int = mode.categories().size()
	for i: int in _tags.size():
		if not _tags[i].has_point(at):
			continue
		if i >= cats:
			mode.set_demolish(not mode.demolish)
			return
		mode.category = i
		deal()
		var here: Array[String] = mode.pieces_here()
		mode.select(here[0] if not here.is_empty() else "")
		return


# ---------- drawing ----------

func _draw() -> void:
	if not visible:
		if _toast_left > 0.0:
			_draw_toast(Vector2(_canvas.size.x / 2.0, _canvas.size.y - 70.0))
		return
	var frame: Rect2 = _frame()
	_bounds = frame
	_hit.clear()
	_tags.clear()
	_slots.clear()
	var void_level: float = VineStyle.void_amount()
	var x0: float = frame.position.x
	var x1: float = frame.end.x
	var y0: float = frame.position.y + 6.0
	var grow: float = clampf(_open / 0.55, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return y0 + 3.0 * (1.0 - pow(2.0 * (x - x0) / frame.size.x - 1.0, 2.0)) + sin(x * 0.13) * 0.7
	_draw_branch(x0, x1, course, grow, void_level)
	VineStyle.foliage(_canvas, x0, x1, course, 30, 330, void_level, 60.0, _time, grow)
	_hit.append(Rect2(x0, y0 - 3.0, frame.size.x, 8.0))
	var cats: Array[Dictionary] = mode.categories()
	var x: float = x0 + 26.0
	for i: int in cats.size():
		var label: String = String(cats[i].name)
		var on: bool = i == mode.category and not mode.demolish
		x = _hang_tag(label, x, course, i, on, GOLD if on else TEXT, GOLD, void_level)
	var demolish_width: float = float(PixelText.width(DEMOLISH_LABEL) + 10)
	_hang_tag(DEMOLISH_LABEL, x1 - 14.0 - demolish_width, course, cats.size(), mode.demolish, BAD if mode.demolish else DIM, BAD, void_level)

	var y1: float = y0 + 31.0
	var pend_right: float = x0 + FIRST + float(_widest() - 1) * STRIDE + PEND / 2.0 + 10.0
	var course2: Callable = func(xx: float) -> float: return y1 + 1.5 * sin(xx * 0.09)
	var reach2: float = clampf((_open - 0.3) / 0.5, 0.0, 1.0)
	_draw_stem(x0 + 10.0, float(course.call(x0 + 10.0)), y1, reach2, void_level)
	VineStyle.branch(_canvas, x0 + 10.0, pend_right - 2.0, course2, 4, void_level, 60.0, _time, reach2)
	VineStyle.foliage(_canvas, x0 + 10.0, pend_right - 2.0, course2, 9, 410, void_level, 60.0, _time, reach2)
	_plan_list.clear()
	_mini_draw = []
	_draw_pendants(x0 + FIRST, course2, void_level)
	var leaf: Rect2 = Rect2(pend_right, y1 - 4.0, x1 - 8.0 - pend_right, 74.0)
	var reveal: float = clampf((_open - 0.5) / 0.3, 0.0, 1.0)
	VineStyle.paper(_canvas, leaf, reveal, void_level, 63)
	_hit.append(leaf)
	if reveal > 0.5:
		if mode.demolish:
			_draw_demolish(leaf, reveal)
		else:
			_draw_info(leaf, reveal)
	_draw_town_strip(Rect2(x1 - 160.0, frame.position.y - 12.0, 156.0, 14.0), reveal)
	_plans.queue_redraw()
	_mini.queue_redraw()
	var controls: String = "LMT SETZEN  R SPIEGELN  V KATEGORIE  X ABRISS  B ENDE" if not mode.demolish else "LMT ABREISSEN  X ZURÜCK ZUM BAUEN  B ENDE"
	PixelText.draw(_canvas, controls, Vector2i(int(frame.get_center().x) - PixelText.width(controls) / 2, int(leaf.end.y) + 4), Color(DIM, reveal), SHADOW)
	if _toast_left > 0.0:
		_draw_toast(Vector2(frame.get_center().x, frame.position.y - 24.0))


## Over the branch, right: the town's level and the vine of its worth up to the next level; the chosen piece shows in gold how far it would carry it.
func _draw_town_strip(rect: Rect2, fade: float) -> void:
	var town: TownManager = mode.town
	if fade <= 0.0 or town == null:
		return
	var levels: Array = TownRules.config().get("levels", []) as Array
	var level: int = town.level()
	var worth: float = town.worth()
	var next: float = TownRules.next_worth(level)
	var base: float = float((levels[level] as Dictionary).get("worth", 0)) if level < levels.size() else 0.0
	var label: String = TownRules.level_name(level)
	PixelText.draw(_canvas, label, Vector2i(int(rect.position.x), int(rect.position.y)), Color(GOLD, fade), SHADOW)
	var bar: Rect2 = Rect2(rect.position.x + float(PixelText.width(label)) + 6.0, rect.position.y + 1.0, rect.size.x - float(PixelText.width(label)) - 6.0, 3.0)
	if next < 0.0:
		_canvas.draw_rect(bar, Color(GOLD, 0.8 * fade))
		return
	var k: float = clampf((worth - base) / maxf(next - base, 1.0), 0.0, 1.0)
	var gain: float = 0.0
	if not mode.demolish and mode.piece != "":
		gain = float(TownRules.piece(mode.piece).get("worth", 0.0))
	var k2: float = clampf((worth + gain - base) / maxf(next - base, 1.0), 0.0, 1.0)
	_canvas.draw_rect(bar.grow(1.0), Color(SHADOW, 0.9 * fade))
	_canvas.draw_rect(bar, Color(0.12, 0.08, 0.2, fade))
	_canvas.draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * k2), bar.size.y)), Color(GOLD, (0.35 + 0.25 * sin(_time * 5.0)) * fade))
	_canvas.draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * k), bar.size.y)), Color(LIT, fade))
	var after: String = "STADTWERT %d VON %d, DANN %s" % [int(worth), int(next), TownRules.level_name(level + 1)]
	if k2 >= 1.0 and gain > 0.0:
		after = "DIESES TEIL MACHT EUCH ZUM %s" % TownRules.level_name(level + 1)
	PixelText.draw(_canvas, after, Vector2i(int(bar.end.x) - PixelText.width(after), int(rect.position.y) + 6), Color(GOLD if k2 >= 1.0 and gain > 0.0 else DIM, fade), SHADOW)


func _draw_branch(x0: float, x1: float, y_of: Callable, reach: float, void_level: float) -> void:
	var span: float = x1 - x0
	for i: int in int(span * reach) + 1:
		var x: float = x0 + float(i)
		var y: float = roundf(float(y_of.call(x)))
		var taken: float = VineStyle.infection(minf(float(i), span - float(i)) + 60.0, void_level, i / 2)
		_canvas.draw_rect(Rect2(x, y - 2.0, 1, 5), VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		_canvas.draw_rect(Rect2(x, y - 1.0, 1, 3), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if i % 3 != 1:
			_canvas.draw_rect(Rect2(x, y - 1.0, 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))
		if taken > 0.5 and VineStyle.rand(i * 3 + int(_time * 2.0)) < 0.06:
			_canvas.draw_rect(Rect2(x, y, 1, 1), VineStyle.VOID_GLOW)


## The short strand that lets the pendants' vine grow out of the branch.
func _draw_stem(x: float, top: float, bottom: float, reach: float, void_level: float) -> void:
	var length: int = int((bottom - top) * reach)
	for s: int in length:
		var xx: float = x + roundf(sin(float(s) * 0.45) * 0.8)
		var taken: float = VineStyle.infection(60.0 + float(length - s), void_level, s)
		_canvas.draw_rect(Rect2(xx, top + float(s), 2, 1), VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken))
		if s % 2 == 0:
			_canvas.draw_rect(Rect2(xx, top + float(s), 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, taken))
	if length > 8:
		VineStyle.leaf(_canvas, Vector2(x + 2.0, top + float(length) * 0.5), 1, -1, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level))


func _bloom(at: Vector2, void_level: float) -> void:
	var open: float = 1.0 + float(int(1.5 + 1.5 * sin(_time * 3.0)))
	VineStyle.glow(_canvas, at, 8.0, VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, void_level), 0.9)
	for o: Vector2 in [Vector2(-open, 0), Vector2(open, 0), Vector2(0, -open), Vector2(0, open)]:
		_canvas.draw_rect(Rect2(at + o, Vector2.ONE), VineStyle.PETAL)
	_canvas.draw_rect(Rect2(at, Vector2.ONE), VineStyle.WARM_GLOW)


## One name tag on the branch, drawn like the Escape menu's (`VineStyle.tab`); returns where the next one starts. `index` staggers the drop, `mark` tints the open one's glow.
func _hang_tag(label: String, x: float, course: Callable, index: int, on: bool, _tone: Color, mark: Color, void_level: float) -> float:
	var width: float = float(PixelText.width(label) + 10)
	var drop: float = clampf((_open - 0.25 - 0.07 * float(index)) / 0.4, 0.0, 1.0)
	var middle: float = x + width / 2.0
	var at: Vector2 = Vector2(middle, float(course.call(middle)) + 1.0)
	var over: bool = not on and float(_tab_lift.get(index, 0.0)) > 1.0 ## hovered (the lift follows the mouse)
	var rect: Rect2 = VineStyle.tab(_canvas, label, at, drop, float(_tab_lift.get(index, 0.0)), void_level, _time, index, on, over, mark)
	_tags.append(rect.grow(2.0))
	if drop > 0.0:
		_hit.append(rect.grow(2.0))
	if on and drop > 0.9 and index < mode.categories().size():
		VineStyle.bloom(_canvas, Vector2(middle, roundf(float(course.call(middle))) - 4.0), 1.0, _time, void_level, mark)
	return x + width + TAG_GAP


## The pieces of the open category as cards hanging from the vine: the real picture of the piece, the number key, a pip (teal = ready, red = material
## missing); a locked piece shows as a violet blueprint (`_plans`) with an X, the chosen card is lifted and lit. They are dealt out one after the other.
func _draw_pendants(left: float, course: Callable, void_level: float) -> void:
	var list: Array[String] = mode.pieces_here()
	for i: int in list.size():
		var id: String = list[i]
		var cx: float = left + float(i) * STRIDE
		var anchor_y: float = roundf(float(course.call(cx)))
		var drop: float = clampf(float(_flip.get(id, 0.0)), 0.0, 1.0)
		if drop <= 0.0:
			continue
		var on: bool = id == mode.piece and not mode.demolish
		var thread: float = (3.0 + VineStyle.rand(i * 7 + 1) * 3.0) * VineStyle.back_out(drop)
		var sway: float = roundf(sin(_time * 1.1 + float(i) * 1.7))
		var width: float = roundf(PEND * drop)
		var plate: Rect2 = Rect2(roundf(cx + sway - width / 2.0), roundf(anchor_y + thread - float(_lift.get(id, 0.0))), width, CARD_H)
		var alpha: float = minf(drop * 2.0, 1.0) * (0.4 if mode.demolish else 1.0)
		var open: bool = mode.town.is_unlocked(id)
		var short: bool = false
		var cost: Dictionary = TownRules.piece(id).get("cost", {}) as Dictionary
		for item: String in cost:
			short = short or mode.town.available(item, mode.town.local_player()) < int(cost[item])
		var steps: int = int(plate.position.y - anchor_y)
		for s: int in range(1, steps):
			_canvas.draw_rect(Rect2(roundf(lerpf(cx, plate.get_center().x, float(s) / float(maxi(steps, 1)))), anchor_y + float(s), 1, 1), VineStyle.BARK_LIGHT.lerp(VineStyle.BARK_VOID_LIGHT, void_level) if s % 2 == 0 else VineStyle.BARK.lerp(VineStyle.BARK_VOID, void_level))
		var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, void_level)
		if on:
			VineStyle.glow(_canvas, plate.get_center(), 30.0, tone, 0.75 * alpha * (0.85 + 0.15 * sin(_time * 2.5)))
		_canvas.draw_rect(plate, Color(VineStyle.OUTLINE, alpha))
		_canvas.draw_rect(plate.grow(-1.0), Color(0.07, 0.04, 0.13, 0.94 * alpha))
		_canvas.draw_rect(Rect2(plate.position + Vector2(1, 1), Vector2(plate.size.x - 2.0, 1)), Color(VineStyle.BARK_LIGHT, alpha))
		_canvas.draw_rect(Rect2(plate.position + Vector2(1, plate.size.y - 9.0), Vector2(plate.size.x - 2.0, 8.0)), Color(0.12, 0.08, 0.2, alpha))
		if on:
			_canvas.draw_rect(plate.grow(-1.0), Color(LIT, (0.1 + 0.05 * sin(_time * 4.0)) * alpha))
			_canvas.draw_rect(plate, Color(LIT, 0.9 * alpha), false, 1.0)
		var tex: Texture2D = mode.texture_of(id)
		if tex != null and drop > 0.6:
			var room: Vector2 = Vector2(plate.size.x - 6.0, CARD_H - 14.0)
			var size_px: Vector2 = _fit(tex.get_size(), room)
			var at: Rect2 = Rect2((Vector2(plate.get_center().x, plate.position.y + 3.0 + room.y / 2.0) - size_px / 2.0).round(), size_px)
			if open:
				_canvas.draw_texture_rect(tex, at, false, Color(1, 1, 1, alpha))
			else:
				_plan_list.append([tex, at, alpha])
		PixelText.draw(_canvas, str(i + 1), Vector2i(int(plate.position.x) + 3, int(plate.end.y) - 7), Color(TEXT if on else DIM, alpha), SHADOW)
		if not open:
			PixelText.draw(_canvas, "X", Vector2i(int(plate.end.x) - 7, int(plate.end.y) - 7), Color(0.72, 0.62, 1.0, alpha), SHADOW)
		elif short:
			_canvas.draw_rect(Rect2(plate.end.x - 7.0, plate.end.y - 6.0, 3.0, 3.0), Color(BAD, alpha))
		else:
			_canvas.draw_rect(Rect2(plate.end.x - 7.0, plate.end.y - 6.0, 3.0, 3.0), Color(LIT, alpha * (0.6 + 0.4 * sin(_time * 3.0 + float(i)))))
		_slots.append(plate.grow(2.0))
		_hit.append(plate.grow(2.0))


## The size a picture is drawn at to fit `room`: whole fractions (1/2, 1/3 ...) or up to 2x, so the pixels stay even.
func _fit(size: Vector2, room: Vector2) -> Vector2:
	var need: float = maxf(size.x / room.x, size.y / room.y)
	if need <= 0.5:
		return size * 2.0
	if need <= 1.0:
		return size
	return size / ceilf(need)


## The big card of the chosen piece: its picture putting itself together in a loop (or its blueprint while it is locked), name, what it is for or what
## stops it, build time, the light it brings, its worth, whether it clears the ground round it, and the cost as chips.
func _draw_info(leaf: Rect2, fade: float) -> void:
	if mode.piece == "":
		return
	var spec: Dictionary = TownRules.piece(mode.piece)
	var open: bool = mode.town.is_unlocked(mode.piece)
	var art: Rect2 = Rect2(leaf.position + Vector2(7, 7), Vector2(64, leaf.size.y - 14.0))
	_canvas.draw_rect(art, Color(0.05, 0.03, 0.1, 0.8 * fade))
	_canvas.draw_rect(art, Color(VineStyle.BARK, 0.7 * fade), false, 1.0)
	var tex: Texture2D = mode.texture_of(mode.piece)
	if tex != null:
		var size_px: Vector2 = _fit(tex.get_size(), art.size - Vector2(6, 6))
		var at: Rect2 = Rect2(Vector2(art.get_center().x - size_px.x / 2.0, art.end.y - 3.0 - size_px.y).round(), size_px)
		VineStyle.glow(_canvas, at.get_center(), 30.0, LIT, 0.18 * fade)
		if open:
			var t: float = fmod(_mini_clock, 3.4)
			_mini_mat.set_shader_parameter("progress", clampf(t / 2.4, 0.0, 1.0))
			_mini_mat.set_shader_parameter("time", _time)
			_mini_mat.set_shader_parameter("seed", float(absi(mode.piece.hash()) % 97))
			_mini_draw = [tex, at, fade]
		else:
			_plan_list.append([tex, at, fade])
	var x: int = int(art.end.x) + 8
	var right: int = int(leaf.end.x) - 8
	var y: int = int(leaf.position.y) + 7
	PixelText.draw(_canvas, String(spec.name).to_upper(), Vector2i(x, y), Color(GOLD, fade), SHADOW)
	var seconds: String = "%d S" % int(spec.get("build_seconds", 0))
	PixelText.draw(_canvas, seconds, Vector2i(right - PixelText.width(seconds), y), Color(DIM, fade), SHADOW)
	var text: String = mode.reason if mode.reason != "" else String(spec.get("info", ""))
	var color: Color = BAD if mode.reason != "" else DIM
	if not open:
		text = "GESPERRT: " + mode.town.lock_reason(mode.piece)
		color = Color(0.72, 0.62, 1.0)
	var row: int = 0
	for line: String in _wrap(text, right - x):
		if row < 2:
			PixelText.draw(_canvas, line, Vector2i(x, y + 9 + row * 7), Color(color, fade), SHADOW)
		row += 1
	var facts: Array[String] = [] ## said plainly: what the piece does for the town
	var reach: float = float(spec.get("reach", 0.0)) * mode.town.light_grow()
	if reach > 0.0:
		facts.append("LEUCHTET %d FELDER WEIT" % int(roundf(reach / 16.0)))
	if float(spec.get("worth", 0.0)) >= 1.0:
		facts.append("STADTWERT +%d" % int(roundf(float(spec.worth))))
	var sweep: float = TownManager.wave_radius(mode.piece)
	if sweep > 0.0:
		facts.append("RÄUMT %d FELDER RUNDUM FREI" % int(roundf(sweep / 16.0)))
	var line_y: int = y + 24
	var fx: int = x
	for fact: String in facts:
		if fx > x and fx + PixelText.width(fact) > right:
			fx = x
			line_y += 7
		PixelText.draw(_canvas, fact, Vector2i(fx, line_y), Color(LIT, fade), SHADOW)
		fx += PixelText.width(fact) + 10
	var cost: Dictionary = spec.get("cost", {}) as Dictionary
	var cx: float = float(x)
	for item: String in cost:
		var have: int = mode.town.available(item, mode.town.local_player())
		var need: int = int(cost[item])
		cx += _chip(Vector2(cx, float(line_y) + 10.0), item, "%d/%d" % [mini(have, 99), need], LIT if have >= need else BAD, 1.0 if have >= need else 0.6, fade)


## Splits `text` into lines no wider than `width` pixels.
func _wrap(text: String, width: int) -> Array[String]:
	var out: Array[String] = []
	var line: String = ""
	for word: String in text.split(" ", false):
		var trial: String = word if line == "" else line + " " + word
		if PixelText.width(trial) > width and line != "":
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


func _draw_demolish(leaf: Rect2, fade: float) -> void:
	var x: int = int(leaf.position.x) + 9
	var y: int = int(leaf.position.y) + 7
	if mode.target_id < 0 or not mode.town.structures.has(mode.target_id):
		PixelText.draw(_canvas, "ZIEL AUF EIN TEIL", Vector2i(x, y), Color(TEXT, fade), SHADOW)
		PixelText.draw(_canvas, "DAS HAUS BLEIBT STEHEN", Vector2i(x, y + 9), Color(DIM, fade), SHADOW)
		return
	var data: Dictionary = mode.town.structures[mode.target_id] as Dictionary
	var spec: Dictionary = TownRules.piece(String(data.p))
	PixelText.draw(_canvas, String(spec.name), Vector2i(x, y), Color(GOLD, fade), SHADOW)
	var finished: bool = int(data.g) >= TownManager.PROGRESS_FULL
	var state: String = "FERTIG" if finished else "BAUSTELLE"
	PixelText.draw(_canvas, state, Vector2i(int(leaf.end.x) - 9 - PixelText.width(state), y), Color(DIM, fade), SHADOW)
	PixelText.draw(_canvas, "GIBT ZURÜCK, LANDET IM STADTLAGER", Vector2i(x, y + 9), Color(DIM, fade), SHADOW)
	var back: Dictionary = TownRules.refund(spec.get("cost", {}) as Dictionary, finished)
	var cx: float = float(x)
	for item: String in back:
		cx += _chip(Vector2(cx, float(y) + 18.0), item, "+%d" % int(back[item]), LIT, 1.0, fade)


## An item's icon with a label beside it, like the workbench's cost chips; returns its width including the gap.
func _chip(at: Vector2, item: String, label: String, color: Color, icon_alpha: float, fade: float) -> float:
	_canvas.draw_rect(Rect2(at, Vector2(18, 18)), Color(UiStyle.OUTLINE, fade))
	_canvas.draw_rect(Rect2(at + Vector2(1, 1), Vector2(16, 16)), Color(UiStyle.SLOT_BG, fade))
	var icon: Texture2D = Items.icon({"id": item})
	if icon != null:
		_canvas.draw_texture_rect(icon, Rect2(at + Vector2(1, 1), Vector2(16, 16)), false, Color(1, 1, 1, icon_alpha * fade))
	PixelText.draw(_canvas, label, Vector2i(int(at.x) + 21, int(at.y) + 6), Color(color, fade), SHADOW)
	return 21.0 + float(PixelText.width(label)) + 8.0


func _draw_toast(at: Vector2) -> void:
	var fade: float = clampf(_toast_left / 0.5, 0.0, 1.0)
	var width: int = PixelText.width(_toast_text)
	PixelText.draw(_canvas, _toast_text, Vector2i(int(at.x) - width / 2, int(at.y)), Color(LIT if _toast_good else BAD, fade), Color(SHADOW, fade))
