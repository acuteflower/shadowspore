class_name MainMenuUi
extends Control
## The pages of the main menu (docs/hauptmenue_konzept.md): the five entries hang as name tags from one vine across the bottom of the camp, the other pages
## (new game, multiplayer, join, settings) are bark-paper cards. Draws everything itself in the vine style; the controller (`MainMenu`) owns the world, the dark and the launch.
## Mouse, keyboard (arrows, Enter/Space/E, Esc) and gamepad (ui_* actions) all work. `chosen(id, data)` fires for what leaves the menu: continue, new, host, join, quit.

signal chosen(id: String, data: Dictionary)

enum Page { MAIN, CONFIRM_NEW, MULTI, JOIN, SETTINGS }

const VIEW: Vector2 = Vector2(640.0, 360.0)
const BRANCH_Y: float = 290.0
const CARD_W: float = 262.0
const ROW_H: float = 15.0
const ADDRESS_CHARS: String = "0123456789.:-abcdefghijklmnopqrstuvwxyz"
const HINTS: Dictionary = {
	"continue": "DORT WEITER, WO DU AUFGEHÖRT HAST",
	"new": "EINE NEUE GESCHICHTE BEGINNT IM DUNKELN",
	"multi": "ZU VIERT DURCH DIE NACHT",
	"settings": "TON, BILD UND STEUERUNG",
	"quit": "DAS FEUER BLEIBT AN",
}
const SLIDERS: Array = [["master", "GESAMT"], ["music", "MUSIK"], ["sfx", "EFFEKTE"], ["shake", "SCHÜTTELN"]]
const TOGGLES: Array = [["fullscreen", "VOLLBILD"], ["vsync", "VSYNC"], ["cursor", "EIGENER CURSOR"], ["numbers", "SCHADENSZAHLEN"], ["position", "POSITION"]]

var page: Page = Page.MAIN
var intro: float = 0.0 ## seconds since the vine started to grow; the tags drop in one after the other
var enabled: bool = false ## input is accepted
var address: String = "127.0.0.1"
var status: String = "" ## a line under the card (e.g. why a join failed)

var _time: float = 0.0
var _rows: Array[Dictionary] = []
var _rects: Array[Rect2] = []
var _sel: int = 0
var _hover: int = -1
var _last_mouse: Vector2 = Vector2(-1.0, -1.0)
var _page_age: float = 0.0
var _save_day: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_day = int(SaveGame.info().get("day", -1)) if SaveGame.exists() else -1
	_open_page(Page.MAIN)


func _exit_tree() -> void:
	GameCursor.set_hint(self, &"")


## Where the light of the menu rests when the mouse is not used: the middle of the chosen entry.
func focus_point() -> Vector2:
	if _sel >= 0 and _sel < _rects.size():
		return _rects[_sel].get_center()
	return VIEW * 0.5


func _open_page(next: Page) -> void:
	page = next
	_page_age = 0.0
	_rows.clear()
	match page:
		Page.MAIN:
			if SaveGame.exists():
				_rows.append({"id": "continue", "label": "WEITER"})
			_rows.append_array([{"id": "new", "label": "NEUES SPIEL"}, {"id": "multi", "label": "MEHRSPIELER"}, {"id": "settings", "label": "EINSTELLUNGEN"}, {"id": "quit", "label": "BEENDEN"}])
		Page.CONFIRM_NEW:
			_rows.append_array([{"id": "new_yes", "label": "JA, NEU BEGINNEN"}, {"id": "back", "label": "ZURÜCK"}])
		Page.MULTI:
			_rows.append_array([{"id": "host", "label": "SPIEL HOSTEN"}, {"id": "join_page", "label": "BEITRETEN"}, {"id": "back", "label": "ZURÜCK"}])
		Page.JOIN:
			_rows.append_array([{"id": "addr", "label": "ADRESSE", "kind": "field"}, {"id": "join", "label": "VERBINDEN"}, {"id": "back", "label": "ZURÜCK"}])
		Page.SETTINGS:
			for pair: Array in SLIDERS:
				_rows.append({"id": pair[0], "label": pair[1], "kind": "slider"})
			for pair: Array in TOGGLES:
				_rows.append({"id": pair[0], "label": pair[1], "kind": "toggle"})
			_rows.append({"id": "back", "label": "FERTIG"})
	_sel = 0
	if page == Page.MAIN and SaveGame.exists():
		_sel = 0
	elif page == Page.MAIN:
		_sel = 0
	_hover = -1
	_rects.clear()
	status = ""


func _title() -> String:
	match page:
		Page.CONFIRM_NEW: return "NEUES SPIEL"
		Page.MULTI: return "MEHRSPIELER"
		Page.JOIN: return "BEITRETEN"
		Page.SETTINGS: return "EINSTELLUNGEN"
	return ""


func _lines() -> PackedStringArray:
	match page:
		Page.CONFIRM_NEW: return PackedStringArray(["DEIN SPIELSTAND WIRD BEIM", "NÄCHSTEN SPEICHERN ÜBERSCHRIEBEN."])
		Page.MULTI: return PackedStringArray(["BIS ZU VIER SPIELER, PORT %d." % NetworkManager.DEFAULT_PORT])
		Page.JOIN: return PackedStringArray(["ADRESSE DES HOSTS, ZUM BEISPIEL", "192.168.0.12 ODER 192.168.0.12:7777"])
	return PackedStringArray()


func _process(delta: float) -> void:
	_time += delta
	_page_age += delta
	if not enabled:
		GameCursor.set_hint(self, &"")
		queue_redraw()
		return
	var mouse: Vector2 = get_local_mouse_position()
	var moved: bool = mouse.distance_to(_last_mouse) > 0.5
	_last_mouse = mouse
	var over: int = -1
	for i: int in _rects.size():
		if _rects[i].grow(2.0).has_point(mouse):
			over = i
			break
	_hover = over
	if moved and over >= 0:
		_sel = over
	GameCursor.set_hint(self, &"click" if over >= 0 else &"")
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if _hover >= 0:
			_sel = _hover
			_press(_rows[_sel], get_local_mouse_position())
			get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and _sel < _rows.size() and String(_rows[_sel].get("kind", "")) == "field":
		if _type(key):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if page != Page.MAIN:
			_open_page(Page.MULTI if page == Page.JOIN else Page.MAIN)
			get_viewport().set_input_as_handled()
		return
	var horizontal: bool = page == Page.MAIN
	var back: StringName = &"ui_left" if horizontal else &"ui_up"
	var forward: StringName = &"ui_right" if horizontal else &"ui_down"
	if event.is_action_pressed(back) or (horizontal and event.is_action_pressed(&"ui_up")):
		_sel = posmod(_sel - 1, maxi(_rows.size(), 1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(forward) or (horizontal and event.is_action_pressed(&"ui_down")):
		_sel = posmod(_sel + 1, maxi(_rows.size(), 1))
		get_viewport().set_input_as_handled()
	elif not horizontal and (event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right")):
		if _sel < _rows.size():
			var kind: String = String(_rows[_sel].get("kind", ""))
			if kind == "slider":
				_step_slider(String(_rows[_sel].id), -10 if event.is_action_pressed(&"ui_left") else 10)
			elif kind == "toggle":
				_flip(String(_rows[_sel].id))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept") or (event.is_action_pressed(&"interact") and key != null):
		if _sel < _rows.size():
			_press(_rows[_sel], Vector2(-1.0, -1.0))
		get_viewport().set_input_as_handled()


## Typing into the address field. True when the key was used.
func _type(key: InputEventKey) -> bool:
	if key.keycode == KEY_BACKSPACE:
		address = address.substr(0, maxi(address.length() - 1, 0))
		return true
	if key.keycode == KEY_V and key.ctrl_pressed:
		for c: String in DisplayServer.clipboard_get().strip_edges().to_lower():
			if ADDRESS_CHARS.contains(c) and address.length() < 40:
				address += c
		return true
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_ESCAPE or key.keycode == KEY_UP or key.keycode == KEY_DOWN:
		return false
	if key.unicode > 31 and not key.ctrl_pressed:
		var c: String = char(key.unicode).to_lower()
		if ADDRESS_CHARS.contains(c) and address.length() < 40:
			address += c
		return true
	return false


func _step_slider(id: String, step: int) -> void:
	GameSettings.set_value(id, clampi(int(GameSettings.get_value(id)) + step, 0, 100))
	GameSettings.save()


func _flip(id: String) -> void:
	GameSettings.set_value(id, not bool(GameSettings.get_value(id)))
	GameSettings.save()


func _press(row: Dictionary, at: Vector2) -> void:
	Sfx.ui(self, "ui_confirm", -3.0)
	var id: String = String(row.id)
	var kind: String = String(row.get("kind", ""))
	if kind == "slider":
		var rect: Rect2 = _rects[_sel] if _sel < _rects.size() else Rect2()
		if at.x >= 0.0 and rect.size.x > 0.0:
			var bar_x: float = rect.end.x - 66.0
			if at.x >= bar_x - 4.0:
				GameSettings.set_value(id, clampi(roundi((at.x - bar_x) / 60.0 * 10.0) * 10, 0, 100))
				GameSettings.save()
			else:
				_step_slider(id, -10)
		else:
			_step_slider(id, 10)
		return
	if kind == "toggle":
		_flip(id)
		return
	match id:
		"continue":
			chosen.emit("continue", {})
		"new":
			if SaveGame.exists():
				_open_page(Page.CONFIRM_NEW)
			else:
				chosen.emit("new", {})
		"new_yes":
			chosen.emit("new", {})
		"multi":
			_open_page(Page.MULTI)
		"host":
			chosen.emit("host", {})
		"join_page":
			_open_page(Page.JOIN)
		"addr":
			pass
		"join":
			var parts: PackedStringArray = address.strip_edges().split(":")
			var host: String = parts[0]
			if host.is_empty():
				status = "KEINE ADRESSE"
				return
			var port: int = int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else NetworkManager.DEFAULT_PORT
			chosen.emit("join", {"address": host, "port": port})
		"settings":
			_open_page(Page.SETTINGS)
		"quit":
			chosen.emit("quit", {})
		"back":
			GameSettings.save()
			_open_page(Page.MULTI if page == Page.JOIN else Page.MAIN)


# ---------------------------------------------------------------------------------------------- drawing

func _draw() -> void:
	var void_level: float = VineStyle.void_amount()
	if page == Page.MAIN:
		_draw_main(void_level)
	else:
		_draw_card(void_level)


func _branch_y(x: float) -> float:
	return BRANCH_Y + sin(x * 0.021 + 1.3) * 2.5 + sin(x * 0.007) * 3.0


func _draw_main(void_level: float) -> void:
	var reach: float = clampf(intro / 1.3, 0.0, 1.0)
	if reach <= 0.0:
		return
	var y_of: Callable = _branch_y
	VineStyle.branch(self, -4.0, VIEW.x + 4.0, y_of, 4, void_level, 0.0, _time, reach)
	VineStyle.foliage(self, -4.0, VIEW.x + 4.0, y_of, 26, 11, void_level, 0.0, _time, reach)
	var widths: Array[float] = []
	var total: float = 0.0
	for row: Dictionary in _rows:
		var w: float = float(PixelText.width(String(row.label)) + 10)
		widths.append(w)
		total += w
	var gap: float = 18.0
	total += gap * float(maxi(_rows.size() - 1, 0))
	var x: float = (VIEW.x - total) / 2.0
	_rects.clear()
	for i: int in _rows.size():
		var anchor: Vector2 = Vector2(x + widths[i] / 2.0, _branch_y(x + widths[i] / 2.0) + 1.0)
		var p: float = clampf((intro - 0.5 - 0.14 * float(i)) / 0.7, 0.0, 1.0)
		var active: bool = i == _sel and enabled
		var lift: float = 3.0 if active else 0.0
		var tone: Color = VineStyle.ACCENT_WARM
		var rect: Rect2 = VineStyle.tab(self, String(_rows[i].label), anchor, p, lift, void_level * 0.6, _time, i, active, i == _hover, tone)
		_rects.append(rect if p > 0.6 else Rect2())
		if active:
			VineStyle.bloom(self, Vector2(anchor.x, anchor.y - 3.0), p, _time, void_level * 0.6, tone)
		x += widths[i] + gap
	if enabled and _sel < _rows.size():
		var text: String = String(HINTS.get(String(_rows[_sel].id), ""))
		if String(_rows[_sel].id) == "continue" and _save_day >= 0:
			text = "TAG %d - %s" % [_save_day + 1, text]
		var hint_alpha: float = clampf(intro - 1.8, 0.0, 1.0)
		PixelText.draw(self, text, Vector2i(int((VIEW.x - PixelText.width(text)) / 2.0), 331), Color(UiStyle.TEXT, 0.85 * hint_alpha), Color(VineStyle.OUTLINE, hint_alpha))
	if not status.is_empty():
		PixelText.draw(self, status, Vector2i(int((VIEW.x - PixelText.width(status)) / 2.0), 344), Color("ff7a7a"), Color(VineStyle.OUTLINE))


func _draw_card(void_level: float) -> void:
	var lines: PackedStringArray = _lines()
	var height: float = 30.0 + float(lines.size()) * 9.0 + float(_rows.size()) * (ROW_H + 2.0) + 12.0 + (10.0 if not status.is_empty() else 0.0)
	var grow: float = VineStyle.back_out(clampf(_page_age / 0.35, 0.0, 1.0))
	var rect: Rect2 = Rect2(Vector2(roundf((VIEW.x - CARD_W) / 2.0), roundf((VIEW.y - height) / 2.0 + 14.0)), Vector2(CARD_W, height))
	rect.position.y += (1.0 - clampf(grow, 0.0, 1.2)) * 14.0
	var fade: float = clampf(_page_age / 0.2, 0.0, 1.0)
	VineStyle.paper(self, rect, fade, void_level * 0.5, 3)
	var title: String = _title()
	PixelText.draw(self, title, Vector2i(int(rect.position.x + (CARD_W - PixelText.width(title)) / 2.0), int(rect.position.y + 9.0)), Color(VineStyle.ACCENT_WARM, fade), Color(VineStyle.OUTLINE, fade))
	var y: float = rect.position.y + 24.0
	for line: String in lines:
		PixelText.draw(self, line, Vector2i(int(rect.position.x + (CARD_W - PixelText.width(line)) / 2.0), int(y)), Color(UiStyle.TEXT, 0.8 * fade), Color(VineStyle.OUTLINE, fade))
		y += 9.0
	y += 5.0
	_rects.clear()
	for i: int in _rows.size():
		var row_rect: Rect2 = Rect2(rect.position.x + 14.0, y, CARD_W - 28.0, ROW_H)
		_rects.append(row_rect)
		var active: bool = i == _sel
		var tone: Color = VineStyle.ACCENT_WARM
		if active:
			VineStyle.glow(self, row_rect.get_center(), 30.0, tone, 0.4 * fade)
		var kind: String = String(_rows[i].get("kind", ""))
		var label: String = String(_rows[i].label)
		VineStyle.plate(self, row_rect, "" if not kind.is_empty() else label, tone if active else tone * 0.35, VineStyle.PETAL if active else UiStyle.TEXT, fade, void_level * 0.5)
		var ink: Color = Color(VineStyle.PETAL if active else UiStyle.TEXT, fade)
		var outline: Color = Color(VineStyle.OUTLINE, fade)
		if not kind.is_empty():
			PixelText.draw(self, label, Vector2i(int(row_rect.position.x + 6.0), int(row_rect.position.y + 3.0)), ink, outline)
		match kind:
			"slider":
				var value: int = int(GameSettings.get_value(String(_rows[i].id)))
				var bar_x: float = row_rect.end.x - 66.0
				for k: int in 10:
					var filled: bool = value >= (k + 1) * 10 - 4
					self.draw_rect(Rect2(bar_x + float(k) * 6.0, row_rect.position.y + 4.0, 5, 6), Color(VineStyle.OUTLINE, fade))
					self.draw_rect(Rect2(bar_x + float(k) * 6.0 + 1.0, row_rect.position.y + 5.0, 3, 4), Color(VineStyle.LEAF_LIGHT if filled else VineStyle.BARK, fade))
			"toggle":
				var on: bool = bool(GameSettings.get_value(String(_rows[i].id)))
				var word: String = "AN" if on else "AUS"
				PixelText.draw(self, word, Vector2i(int(row_rect.end.x - 8.0 - PixelText.width(word)), int(row_rect.position.y + 3.0)), Color(VineStyle.LEAF_LIGHT if on else Color("8a7f9c"), fade), outline)
			"field":
				var shown: String = address.to_upper() + ("_" if int(_time * 2.0) % 2 == 0 and active else " ")
				PixelText.draw(self, shown, Vector2i(int(row_rect.position.x + 6.0 + PixelText.width(label) + 8.0), int(row_rect.position.y + 3.0)), Color(VineStyle.WARM_GLOW, fade), outline)
		y += ROW_H + 2.0
	if not status.is_empty():
		PixelText.draw(self, status, Vector2i(int(rect.position.x + (CARD_W - PixelText.width(status)) / 2.0), int(y + 2.0)), Color("ff7a7a", fade), Color(VineStyle.OUTLINE, fade))
