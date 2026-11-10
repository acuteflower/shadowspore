class_name BoardWindow
extends CanvasLayer
## The one look of every window you use *with somebody* or *at something* in the town (workbench and trades: `ShopWindow`, the stockpile: `StockWindow`, later the
## forge, the kitchen, the market ...). A subclass only says what the tabs, the rows, the detail and the buttons are; this class does the staging:
##  - the camera draws close (zoom 2, pixel clean) and frames the person or the thing on the LEFT of the screen, so you talk *to* somebody and watch them;
##  - a branch grows in from the right edge with leaves, a board of bark paper hangs from it on threads (the skill graph's and the dialogue's own pieces: `VineStyle`),
##    the tabs hang as name tags on the branch like the Escape menu's, the rows are item cells with rarity rings (`ItemSlot` look), the hover card is `ItemTooltip`;
##  - the person answers in a speech bubble above their head (`say`), the world stays visible and keeps moving on the left, a dark gradient only where the board is;
##  - W S / arrows / stick choose, A D / shoulders / click change tab, E or A acts, mouse wheel scrolls, Escape leaves. Sprint (Shift) makes an action act on the whole stack.
## The host decides everything that has consequences; a window only asks (`TownManager.request_*`).

const CARD: Rect2 = Rect2(296.0, 46.0, 332.0, 296.0) ## the position and width; the height follows the rows (`_card`)
const ZOOM: float = 2.0
const ROW_H: float = 22.0
const VISIBLE_ROWS: int = 5
const MIN_ROWS: int = 3 ## the board never gets shorter than this many rows, so it does not flap about
const LIST_Y: float = 48.0
const TEXT: Color = Color("e9dcff")
const DIM: Color = Color("8f7fb0")
const LIT: Color = Color("78f4e6")
const GOLD: Color = Color("d9b25f")
const BAD: Color = Color("e0556e")
const SHADOW: Color = Color("0a0612")
const OK: int = 0
const MISSING: int = 1 ## cannot be done right now (the reason is in `row.why`)
const LOCKED: int = 2 ## not yet (trust, level)

var player: Player
var town: TownManager
var title: String = ""
var tabs: Array[Dictionary] = [] ## {id, name}
var tab: int = 0
var rows: Array[Dictionary] = [] ## {item, count, name, sub, tag, tag_color, state, why, bar, ...}
var focus: int = 0
var scroll: int = 0
var focus_world: Vector2 = Vector2.ZERO ## what the camera frames on the left
var speaker: Node2D ## the person who answers (bubble above them)

var _canvas: Control
var _tip: ItemTooltip
var _time: float = 0.0
var _open_t: float = 0.0
var _closing: bool = false
var _view_tween: Tween
var _note: String = ""
var _note_good: bool = false
var _note_left: float = 0.0
var _bubble: String = ""
var _bubble_age: float = 99.0
var _tab_rects: Array[Rect2] = []
var _tab_lift: Array[float] = [] ## how far each tag is raised: the open one 3 px, the hovered one 2
var _button_rects: Array[Rect2] = []
var _sounds: Dictionary = {}
var _vis: float = float(MIN_ROWS) ## rows the board is tall for (eased)


# ---------- for subclasses ----------

func _setup_board() -> void:
	pass


## Fill `rows` for the open tab.
func _rebuild() -> void:
	rows.clear()


## The detail under the list for `row` (a Rect2 the size of the detail area).
func _detail(_area: Rect2, _row: Dictionary) -> void:
	pass


## Buttons, right to left: {id, label, ready, progress (0..1, -1 none)}. The first is the main one (E / A / double click).
func _buttons() -> Array[Dictionary]:
	return []


func _press(_id: String, _bulk: bool) -> void:
	pass


func _persona() -> PackedStringArray:
	return PackedStringArray()


func _subtitle() -> String:
	return ""


func _header_right(_right: float, _y: float) -> void:
	pass


func _hint() -> String:
	return "W S WÄHLEN   A D REITER   E TUN   ESC ZURÜCK"


func _empty_text() -> String:
	return "NICHTS DA"


func _tab_changed() -> void:
	pass


# ---------- opening and closing ----------

func setup_board(for_player: Player, for_town: TownManager) -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = for_player
	town = for_town
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw)
	_canvas.gui_input.connect(_on_gui_input)
	add_child(_canvas)
	_tip = ItemTooltip.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_tip)
	for sound: String in ["coin", "tick", "done", "page"]:
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.stream = load("res://assets/audio/shop/%s.wav" % sound) as AudioStream
		voice.volume_db = -9.0
		add_child(voice)
		_sounds[sound] = voice
	var open_voice: AudioStreamPlayer = AudioStreamPlayer.new()
	open_voice.stream = load("res://assets/audio/skills/open.wav") as AudioStream
	open_voice.volume_db = -14.0
	add_child(open_voice)
	open_voice.play()
	add_to_group("board_window")
	player.story_lock = true
	InputManager.ui_blocking = true
	town.changed.connect(_on_town_changed)
	town.notice.connect(_on_notice)
	_setup_board()
	_rebuild()
	_clamp_focus()
	_vis = float(clampi(rows.size(), MIN_ROWS, VISIBLE_ROWS))
	_frame_view(true)


func _on_town_changed() -> void:
	var keep: int = focus
	_rebuild()
	focus = keep
	_clamp_focus()


func _on_notice(text: String, good: bool) -> void:
	_note = text
	_note_good = good
	_note_left = 2.4
	_sound("done" if good else "tick")


func _sound(name: String) -> void:
	if _sounds.has(name):
		(_sounds[name] as AudioStreamPlayer).play()


## Words of the person (bubble above them, typed out).
func say(text: String) -> void:
	_bubble = text
	_bubble_age = 0.0


func _frame_view(into: bool) -> void:
	var camera: Camera2D = player.view_camera()
	if _view_tween != null:
		_view_tween.kill()
	_view_tween = player.create_tween().set_parallel(true) ## on the player: it goes on after this window is gone
	_view_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if into:
		var mid: Vector2 = focus_world.lerp(player.global_position, 0.25)
		var centre: Vector2 = mid + Vector2(74.0, -22.0) ## the thing sits at about a quarter of the screen, a little below the middle
		_view_tween.tween_property(camera, "zoom", Vector2(ZOOM, ZOOM), 0.7)
		_view_tween.tween_property(player, "view_shift", (centre - camera.global_position).round(), 0.7)
	else:
		_view_tween.tween_property(camera, "zoom", Vector2.ONE, 0.5)
		_view_tween.tween_property(player, "view_shift", Vector2.ZERO, 0.5)


func _close() -> void:
	if _closing:
		return
	_closing = true
	_tip.hide()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(player):
		player.story_lock = false
		_frame_view(false)
	InputManager.ui_blocking = false
	if town.changed.is_connected(_on_town_changed):
		town.changed.disconnect(_on_town_changed)
	if town.notice.is_connected(_on_notice):
		town.notice.disconnect(_on_notice)


func _exit_tree() -> void:
	if not _closing:
		if is_instance_valid(player):
			player.story_lock = false
			player.view_shift = Vector2.ZERO
			player.view_camera().zoom = Vector2.ONE
		InputManager.ui_blocking = false


func _process(delta: float) -> void:
	_time += delta
	_note_left = maxf(_note_left - delta, 0.0)
	_bubble_age += delta
	_open_t = move_toward(_open_t, 0.0 if _closing else 1.0, delta * (3.0 if _closing else 1.4))
	_vis = move_toward(_vis, float(clampi(rows.size(), MIN_ROWS, VISIBLE_ROWS)), delta * 16.0)
	while _tab_lift.size() < tabs.size():
		_tab_lift.append(0.0)
	for i: int in tabs.size():
		var over: bool = InputManager.using_mouse and i < _tab_rects.size() and _tab_rects[i].has_point(_canvas.get_local_mouse_position())
		_tab_lift[i] = lerpf(_tab_lift[i], 3.0 if i == tab else (2.0 if over else 0.0), 1.0 - exp(-14.0 * delta))
	if _closing and _open_t <= 0.0:
		queue_free()
		return
	_canvas.queue_redraw()


# ---------- geometry ----------

func _slide() -> float:
	var p: float = clampf((_open_t - 0.15) / 0.7, 0.0, 1.0)
	return (1.0 - VineStyle.back_out(p)) * 96.0


func _card() -> Rect2:
	var height: float = LIST_Y + ROW_H * _vis + 6.0 + 72.0 + 8.0 + 22.0 + 8.0 + 18.0 ## list, detail, buttons, hint
	return Rect2(CARD.position + Vector2(_slide(), 0.0), Vector2(CARD.size.x, height))


func _row_rect(visible_index: int) -> Rect2:
	var card: Rect2 = _card()
	return Rect2(card.position.x + 12.0, card.position.y + LIST_Y + ROW_H * float(visible_index), card.size.x - 32.0, ROW_H - 2.0)


func _detail_rect() -> Rect2:
	var card: Rect2 = _card()
	return Rect2(card.position.x + 12.0, card.position.y + LIST_Y + ROW_H * _vis + 6.0, card.size.x - 24.0, 72.0)


func _clamp_focus() -> void:
	focus = clampi(focus, 0, maxi(rows.size() - 1, 0))
	scroll = clampi(scroll, 0, maxi(rows.size() - VISIBLE_ROWS, 0))
	if focus < scroll:
		scroll = focus
	elif focus >= scroll + VISIBLE_ROWS:
		scroll = focus - VISIBLE_ROWS + 1


func _focused() -> Dictionary:
	return rows[focus] if focus >= 0 and focus < rows.size() else {}


# ---------- drawing ----------

func _text(pos: Vector2, text: String, color: Color, scale: float = 1.0) -> void:
	if scale == 1.0:
		PixelText.draw(_canvas, text, Vector2i(int(pos.x), int(pos.y)), color, SHADOW)
		return
	_canvas.draw_set_transform(pos, 0.0, Vector2(scale, scale))
	PixelText.draw(_canvas, text, Vector2i.ZERO, color, SHADOW)
	_canvas.draw_set_transform(Vector2.ZERO)


func _wrap(text: String, width: int) -> Array[String]:
	var lines: Array[String] = []
	var line: String = ""
	for word: String in text.split(" "):
		var attempt: String = word if line == "" else line + " " + word
		if PixelText.width(attempt) > width and line != "":
			lines.append(line)
			line = word
		else:
			line = attempt
	if line != "":
		lines.append(line)
	return lines


## The item cell: outline, rarity ring, dark ground, the icon (like `ItemSlot`), optionally big and with a count.
func draw_cell(at: Vector2, item: String, count: int, big: bool = false, dim: bool = false, level: int = 0) -> void:
	var cell: int = 36 if big else ItemSlot.SIZE
	var stack: Dictionary = {"id": item, "count": count}
	var ring: Color = Items.rarity_color(stack) if item != "" else UiStyle.RIM
	_canvas.draw_rect(Rect2(at, Vector2(cell, cell)), UiStyle.OUTLINE)
	_canvas.draw_rect(Rect2(at + Vector2(1, 1), Vector2(cell - 2, cell - 2)), Color(ring, 0.55 if dim else 1.0))
	_canvas.draw_rect(Rect2(at + Vector2(2, 2), Vector2(cell - 4, cell - 4)), UiStyle.SLOT_BG)
	var icon: Texture2D = Items.icon(stack) if item != "" else null
	if icon != null:
		var tint: Color = Color(1, 1, 1, 0.45 if dim else 1.0)
		if big:
			_canvas.draw_texture_rect(icon, Rect2(at + Vector2(2, 2), Vector2(32, 32)), false, tint)
		else:
			_canvas.draw_texture_rect(icon, Rect2(at + Vector2(2, 2), Vector2(16, 16)), false, tint)
	if count > 1:
		var label: String = str(count)
		_text(at + Vector2(cell - 2 - PixelText.width(label), cell - 9), label, TEXT)
	RefineStyle.draw_badge(_canvas, level, int(at.x) + cell - 2, int(at.y) + cell - 2) ## a refined weapon's "+7"


## "3/2" chips: an item's icon with what is there and what is needed (red when short).
func draw_chip(at: Vector2, item: String, have: int, need: int) -> float:
	var ok: bool = have >= need
	_canvas.draw_rect(Rect2(at, Vector2(18, 18)), UiStyle.OUTLINE)
	_canvas.draw_rect(Rect2(at + Vector2(1, 1), Vector2(16, 16)), UiStyle.SLOT_BG)
	var icon: Texture2D = Items.icon({"id": item})
	if icon != null:
		_canvas.draw_texture_rect(icon, Rect2(at + Vector2(1, 1), Vector2(16, 16)), false, Color(1, 1, 1, 1.0 if ok else 0.6))
	var label: String = "%d/%d" % [mini(have, 99), need]
	_text(at + Vector2(21, 6), label, LIT if ok else BAD)
	return 21.0 + float(PixelText.width(label)) + 8.0


## Width draw_purse needs for this amount.
func purse_width(copper: int) -> float:
	var parts: Vector3i = Currency.split(copper)
	var w: float = 0.0
	for i: int in [2, 1, 0]:
		if parts[i] <= 0 and not (i == 2 and copper == 0):
			continue
		w += float(PixelText.width(str(parts[i]))) + 14.0
	return w


## Same as draw_purse, but starting at the left edge.
func draw_purse_left(left: float, y: float, copper: int, tone: Color = TEXT) -> void:
	draw_purse(left + purse_width(copper), y, copper, tone)


## `tone` colours the numbers (BAD = cannot afford it).
func draw_purse(right: float, y: float, copper: int, tone: Color = TEXT) -> void:
	var parts: Vector3i = Currency.split(copper)
	var x: float = right
	for i: int in [2, 1, 0]:
		var amount: int = parts[i]
		if amount <= 0 and not (i == 2 and copper == 0):
			continue
		var label: String = str(amount)
		x -= float(PixelText.width(label))
		_text(Vector2(x, y), label, tone)
		x -= 8.0
		var colors: Array = PurseVine.COINS[i]
		for row: int in PurseVine.COIN.size():
			for col: int in (PurseVine.COIN[row] as String).length():
				var ch: String = (PurseVine.COIN[row] as String)[col]
				if ch != ".":
					_canvas.draw_rect(Rect2(x + float(col), y + 1.0 + float(row), 1, 1), colors[1] if ch == "L" else colors[0])
		x -= 6.0


func draw_trust(right: float, y: float, npc: String) -> void:
	var trust: int = town.trust_of(npc)
	var label: String = "VERTRAUEN"
	var x: float = right - 5.0 * 7.0
	for k: int in 5:
		var on: bool = trust >= (k + 1) * 20 - 10
		_canvas.draw_rect(Rect2(x + float(k) * 7.0, y + 1.0, 5, 5), UiStyle.OUTLINE)
		_canvas.draw_rect(Rect2(x + float(k) * 7.0 + 1.0, y + 2.0, 3, 3), LIT if on else Color(DIM, 0.35))
	_text(Vector2(x - 6.0 - float(PixelText.width(label)), y), label, DIM)


func _draw() -> void:
	var size: Vector2 = _canvas.size
	var p: float = clampf(_open_t, 0.0, 1.0)
	var void_level: float = VineStyle.void_amount()
	# the dark falls from the right, where the board hangs; the left stays the living scene
	var strips: int = int(size.x / 4.0)
	for i: int in strips:
		var x: float = float(i) * 4.0
		var alpha: float = smoothstep(0.3, 0.85, x / size.x) * 0.82 * p
		if alpha > 0.01:
			_canvas.draw_rect(Rect2(x, 0.0, 4.0, size.y), Color(0.02, 0.01, 0.06, alpha))
	var bar: float = 16.0 * smoothstep(0.0, 0.6, p)
	_canvas.draw_rect(Rect2(0.0, 0.0, size.x, bar), Color(0.02, 0.01, 0.05, 0.95))
	_canvas.draw_rect(Rect2(0.0, size.y - bar, size.x, bar), Color(0.02, 0.01, 0.05, 0.95))
	_canvas.draw_rect(Rect2(0.0, bar, size.x, 1.0), Color(VineStyle.BARK_LIGHT, 0.6))
	_canvas.draw_rect(Rect2(0.0, size.y - bar - 1.0, size.x, 1.0), Color(VineStyle.BARK_LIGHT, 0.6))
	var card: Rect2 = _card()
	var reach: float = clampf((_open_t - 0.1) / 0.6, 0.0, 1.0)
	var course: Callable = func(x: float) -> float: return card.position.y - 28.0 + 2.0 * sin((size.x - x) * 0.05) ## the branch runs above the board, the tags hang free from it
	for x: float in [card.position.x + 26.0, card.end.x - 30.0]:
		_canvas.draw_line(Vector2(x, float(course.call(x)) + 2.0), Vector2(x, card.position.y + 3.0), VineStyle.BARK_LIGHT, 1.0)
	VineStyle.paper(_canvas, card, minf(p * 1.6, 1.0), void_level, 71)
	VineStyle.branch(_canvas, size.x, card.position.x - 4.0, course, 6, void_level, 40.0, _time, reach)
	VineStyle.foliage(_canvas, size.x, card.position.x - 4.0, course, 18, 330, void_level, 40.0, _time, reach)
	if p < 0.5:
		return
	_draw_tabs(card, void_level)
	_text(card.position + Vector2(14, 18), title, GOLD, 2.0)
	var sub: String = _subtitle()
	if sub != "":
		_text(card.position + Vector2(14, 36), sub, DIM)
	_header_right(card.end.x - 16.0, card.position.y + 37.0)
	_draw_list(card)
	var area: Rect2 = _detail_rect()
	_canvas.draw_rect(Rect2(area.position.x, area.position.y - 5.0, area.size.x, 1.0), Color(VineStyle.BARK_LIGHT, 0.7))
	var row: Dictionary = _focused()
	if not row.is_empty():
		_detail(area, row)
	_draw_buttons(card)
	_draw_persona(card)
	var foot: String = _note if _note_left > 0.0 else ""
	if foot != "":
		_text(Vector2(card.position.x + 14.0, card.end.y - 34.0), foot, LIT if _note_good else BAD)
	_text(Vector2(card.position.x + 14.0, card.end.y - 14.0), _hint(), DIM)
	_draw_bubble()
	_update_tip(card)


func _draw_tabs(card: Rect2, void_level: float) -> void:
	var old_rects: Array[Rect2] = _tab_rects.duplicate()
	_tab_rects.clear()
	var total: float = 0.0
	for entry: Dictionary in tabs:
		total += float(PixelText.width(String(entry.name)) + 10) + 6.0
	var x: float = card.end.x - 22.0 - (total - 6.0) ## top right, free above the board
	for i: int in tabs.size():
		var label: String = String(tabs[i].name)
		var width: float = float(PixelText.width(label) + 10)
		var drop: float = clampf((_open_t - 0.35 - 0.07 * float(i)) / 0.4, 0.0, 1.0)
		var middle: float = x + width / 2.0
		var at: Vector2 = Vector2(middle, card.position.y - 28.0 + 2.0 * sin((_canvas.size.x - middle) * 0.05))
		var over: bool = InputManager.using_mouse and i < old_rects.size() and old_rects[i].has_point(_canvas.get_local_mouse_position())
		var rect: Rect2 = VineStyle.tab(_canvas, label, at, drop, _tab_lift[i] if i < _tab_lift.size() else 0.0, void_level, _time, i, i == tab, over)
		_tab_rects.append(rect.grow(2.0))
		if i == tab and drop > 0.9:
			VineStyle.bloom(_canvas, Vector2(middle, roundf(at.y) - 4.0), 1.0, _time, void_level)
		x += width + 6.0


## The person behind the board, big on the free ground at the bottom left of the screen, in front of the scene: their name large, beside it and smaller what they do (`_persona`: [name, role];
## nothing for a board without one). It fades in with the board and stays clear of the card.
func _draw_persona(_card_rect: Rect2) -> void:
	var lines: PackedStringArray = _persona()
	if lines.size() < 2:
		return
	var fade: float = clampf((_open_t - 0.6) / 0.3, 0.0, 1.0)
	var x: float = 26.0
	var y: float = _canvas.size.y - 136.0
	_text(Vector2(x, y), lines[0], Color(GOLD, fade), 4.0)
	var name_width: float = float(PixelText.width(lines[0])) * 4.0
	_text(Vector2(x + name_width + 10.0, y + 10.0), lines[1], Color(TEXT, fade * 0.85), 2.0) ## smaller, beside the name, on its baseline


func _draw_list(card: Rect2) -> void:
	if rows.is_empty():
		_text(Vector2(card.position.x + 16.0, card.position.y + LIST_Y + 12.0), _empty_text(), DIM)
		return
	for v: int in VISIBLE_ROWS:
		var index: int = scroll + v
		if index >= rows.size() or float(v) + 0.5 > _vis:
			break
		var row: Dictionary = rows[index]
		var rect: Rect2 = _row_rect(v)
		var on: bool = index == focus
		var state: int = int(row.get("state", OK))
		_canvas.draw_rect(rect, Color(0.06, 0.03, 0.12, 0.72))
		if on:
			_canvas.draw_rect(rect, Color(LIT, 0.12 + 0.05 * sin(_time * 4.0)))
			_canvas.draw_rect(Rect2(rect.position, Vector2(2, rect.size.y)), LIT)
		draw_cell(rect.position + Vector2(4, 0), String(row.get("item", "")), int(row.get("count", 1)), false, state != OK, int(row.get("level", 0)))
		var name_color: Color = TEXT if state == OK else (DIM if on else Color(DIM, 0.75))
		var sub: String = String(row.get("sub", ""))
		_text(rect.position + Vector2(30, 4 if sub != "" else 7), String(row.get("name", "")), name_color)
		if sub != "":
			_text(rect.position + Vector2(30, 12), sub, Color(DIM, 0.85))
		var tag: String = String(row.get("tag", ""))
		if tag != "":
			_text(Vector2(rect.end.x - 6.0 - float(PixelText.width(tag)), rect.position.y + 7.0), tag, row.get("tag_color", GOLD) as Color)
		if row.has("coins"):
			draw_purse(rect.end.x - 6.0, rect.position.y + 7.0, int(row.coins), BAD if bool(row.get("poor", false)) else TEXT)
		var bar: float = float(row.get("bar", -1.0))
		if bar >= 0.0:
			_canvas.draw_rect(Rect2(rect.position.x + 30.0, rect.end.y - 3.0, rect.size.x - 36.0, 2.0), Color(0, 0, 0, 0.5))
			_canvas.draw_rect(Rect2(rect.position.x + 30.0, rect.end.y - 3.0, (rect.size.x - 36.0) * clampf(bar, 0.0, 1.0), 2.0), LIT)
	if rows.size() > VISIBLE_ROWS: ## a thin vine on the right is the scroll bar
		var top: float = card.position.y + LIST_Y
		var span: float = ROW_H * float(VISIBLE_ROWS) - 2.0
		var x: float = card.end.x - 14.0
		_canvas.draw_rect(Rect2(x, top, 1.0, span), Color(VineStyle.BARK_LIGHT, 0.6))
		var handle: float = span * float(VISIBLE_ROWS) / float(rows.size())
		var at: float = (span - handle) * float(scroll) / float(maxi(rows.size() - VISIBLE_ROWS, 1))
		_canvas.draw_rect(Rect2(x - 1.0, top + at, 3.0, handle), VineStyle.BARK)
		_canvas.draw_rect(Rect2(x, top + at, 1.0, handle), LIT)


func _draw_buttons(card: Rect2) -> void:
	_button_rects.clear()
	var over_button: bool = false ## for the cursor: it sparkles over a button that can be pressed
	var list: Array[Dictionary] = _buttons()
	var x: float = card.end.x - 14.0
	for i: int in list.size():
		var button: Dictionary = list[i]
		var label: String = String(button.label)
		var width: float = float(PixelText.width(label) + 22)
		var rect: Rect2 = Rect2(x - width, card.end.y - 42.0, width, 22.0)
		x -= width + 8.0
		_button_rects.append(rect)
		var ready: bool = bool(button.get("ready", true))
		var main: bool = i == 0
		var hover: bool = rect.has_point(_canvas.get_local_mouse_position()) and InputManager.using_mouse
		over_button = over_button or (hover and ready)
		_canvas.draw_rect(rect, UiStyle.OUTLINE)
		_canvas.draw_rect(rect.grow(-1.0), VineStyle.BARK if ready else Color(VineStyle.BARK, 0.5))
		_canvas.draw_rect(Rect2(rect.position + Vector2(1, 1), Vector2(rect.size.x - 2.0, 1)), VineStyle.BARK_LIGHT)
		var progress: float = float(button.get("progress", -1.0))
		if progress >= 0.0:
			_canvas.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2((rect.size.x - 4.0) * clampf(progress, 0.0, 1.0), rect.size.y - 4.0)), Color(LIT, 0.45))
		elif ready and (main or hover):
			_canvas.draw_rect(rect.grow(-2.0), Color(LIT, 0.12 + (0.08 if hover else 0.0) + 0.05 * sin(_time * 4.0)))
		if ready and main:
			VineStyle.glow(_canvas, Vector2(rect.position.x + 6.0, rect.get_center().y), 6.0, LIT, 0.7)
		_text(rect.position + Vector2(11, 8), label, TEXT if ready else DIM)
	GameCursor.set_hint(_canvas, &"click" if over_button else &"")


func _draw_bubble() -> void:
	if speaker == null or not is_instance_valid(speaker) or _bubble == "" or _bubble_age > 6.0:
		return
	var anchor: Vector2 = get_viewport().get_canvas_transform() * (speaker.global_position + Vector2(0, -56))
	var shown: int = mini(int(_bubble_age * 34.0), _bubble.length())
	var lines: Array[String] = _wrap(_bubble, 120)
	var fade: float = clampf((6.0 - _bubble_age) / 0.6, 0.0, 1.0) * clampf(_bubble_age / 0.15, 0.0, 1.0)
	var width: float = 16.0
	for line: String in lines:
		width = maxf(width, float(PixelText.width(line)) + 16.0)
	var rect: Rect2 = Rect2(anchor.x - width / 2.0, anchor.y - 16.0 - 9.0 * float(lines.size()), width, 12.0 + 9.0 * float(lines.size()))
	rect.position.x = clampf(rect.position.x, 8.0, 280.0 - width)
	VineStyle.paper(_canvas, rect, fade, VineStyle.void_amount(), 19)
	_canvas.draw_rect(Rect2(anchor.x - 1.0, rect.end.y - 1.0, 3.0, 3.0), Color(VineStyle.BARK_LIGHT, fade)) ## a little tail towards the speaker
	_canvas.draw_rect(Rect2(anchor.x, rect.end.y + 2.0, 1.0, 2.0), Color(VineStyle.BARK_LIGHT, fade))
	var left: int = shown
	for i: int in lines.size():
		var part: String = lines[i].substr(0, left)
		left = maxi(left - lines[i].length() - 1, 0)
		PixelText.draw(_canvas, part, Vector2i(int(rect.position.x) + 8, int(rect.position.y) + 6 + 9 * i), Color(TEXT, fade), Color(SHADOW, fade))


func _update_tip(card: Rect2) -> void:
	var row: Dictionary = _focused()
	var hovering: bool = false
	for v: int in VISIBLE_ROWS:
		if scroll + v < rows.size() and _row_rect(v).has_point(_canvas.get_local_mouse_position()) and InputManager.using_mouse:
			hovering = true
	var item: String = String(row.get("item", ""))
	if item == "" or _closing or not (hovering or not InputManager.using_mouse):
		_tip.hide()
		return
	var shown: Dictionary = row.get("stack", {"id": item, "count": 1}) as Dictionary ## a refined weapon shows its own card
	var tip_key: String = "%s:%d:%d" % [item, Items.refine(shown), RefineRules.pity(shown)]
	if not _tip.visible or String(_tip.get_meta("item", "")) != tip_key:
		_tip.set_meta("item", tip_key)
		_tip.show_stack(shown, false)
		_tip.show()
	var y: float = card.position.y + LIST_Y + ROW_H * float(focus - scroll)
	_tip.position = Vector2(maxf(card.position.x - _tip.size.x - 10.0, 4.0), clampf(y, 24.0, 330.0 - _tip.size.y))


# ---------- input ----------

func _step_tab(step: int) -> void:
	if tabs.size() < 2:
		return
	_set_tab(posmod(tab + step, tabs.size()))


func _set_tab(index: int) -> void:
	if index == tab or index < 0 or index >= tabs.size():
		return
	tab = index
	focus = 0
	scroll = 0
	_sound("page")
	_tab_changed()
	_rebuild()
	_clamp_focus()


func _move(step: int) -> void:
	if rows.is_empty():
		return
	focus = posmod(focus + step, rows.size())
	_clamp_focus()
	_sound("tick")


func _primary(bulk: bool) -> void:
	var list: Array[Dictionary] = _buttons()
	if not list.is_empty() and bool(list[0].get("ready", true)):
		_press(String(list[0].id), bulk)
	elif not list.is_empty():
		var why: String = String(_focused().get("why", ""))
		if why != "":
			_on_notice(why, false)


func _input(event: InputEvent) -> void:
	if _closing:
		return
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if event.is_action_pressed("ui_cancel"):
		_close()
	elif pad != null and pad.pressed and pad.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_step_tab(-1 if pad.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_step_tab(-1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_step_tab(1)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		_move(1)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		_move(-1)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_primary(Input.is_action_pressed("sprint"))
	else:
		return
	get_viewport().set_input_as_handled()


func _on_gui_input(event: InputEvent) -> void:
	if _closing:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	var click: InputEventMouseButton = event as InputEventMouseButton
	if motion != null:
		for v: int in VISIBLE_ROWS:
			if scroll + v < rows.size() and _row_rect(v).has_point(motion.position) and focus != scroll + v:
				focus = scroll + v
				_sound("tick")
	elif click != null and click.pressed:
		if click.button_index == MOUSE_BUTTON_WHEEL_DOWN or click.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll = clampi(scroll + (1 if click.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, maxi(rows.size() - VISIBLE_ROWS, 0))
			focus = clampi(focus, scroll, scroll + VISIBLE_ROWS - 1)
			return
		var left: bool = click.button_index == MOUSE_BUTTON_LEFT
		if not left and click.button_index != MOUSE_BUTTON_RIGHT:
			return
		for i: int in _tab_rects.size():
			if _tab_rects[i].has_point(click.position):
				_set_tab(i)
				return
		var list: Array[Dictionary] = _buttons()
		for i: int in _button_rects.size():
			if i < list.size() and _button_rects[i].has_point(click.position):
				if bool(list[i].get("ready", true)):
					_press(String(list[i].id), click.shift_pressed or not left)
				else:
					var why: String = String(_focused().get("why", ""))
					if why != "":
						_on_notice(why, false)
				return
		for v: int in VISIBLE_ROWS:
			if scroll + v < rows.size() and _row_rect(v).has_point(click.position):
				focus = scroll + v
				if click.double_click or not left:
					_primary(not left or click.shift_pressed)
				return
		if not _card().has_point(click.position) and click.position.x > CARD.position.x - 40.0:
			_close()
