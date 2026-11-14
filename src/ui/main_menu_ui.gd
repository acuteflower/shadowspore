class_name MainMenuUi
extends Control
## The pages of the main menu (docs/hauptmenue_konzept.md):
## - MAIN: ember words rising from Valdric's campfire clearing into the left shadow.
## - Left-Sanctuary Hub (`CONFIRM_NEW`, `MULTI`, `JOIN`, `SETTINGS`): living vine branch & hanging tabs,
##   keeping both the TitleLogo above and the campfire clearing on the bottom-right unobstructed.
## Mouse (click, hover, drag, wheel), keyboard (arrows, Tab/Q/E, Enter, Backspace, Esc, Ctrl+V)
## and gamepad (ui_* / L1/R1) all work.

signal chosen(id: String, data: Dictionary)

enum Page { MAIN, CONFIRM_NEW, MULTI, JOIN, SETTINGS }

const VIEW: Vector2 = Vector2(640.0, 360.0)
const MENU_X: float = 50.0
const MENU_Y: float = 186.0
const ROW_GAP: float = 23.0
const TEXT_SCALE: float = 2.0
const ROW_DELAY: float = 0.16
const CHAR_DELAY: float = 0.032
const FLIGHT: float = 0.85
const INTRO_DONE: float = 2.0
const IDLE_INK: Color = Color("a497c4")
const HOT_INK: Color = Color("fff0b0")
const DANGER: Color = Color("e86c7a")

## Left-sanctuary panel geometry: leaves x=368..640 campfire clearing and y=0..118 logo/tabs clear.
const PANEL_RECT: Rect2 = Rect2(20.0, 144.0, 344.0, 200.0)
const BRANCH_Y: float = 118.0
const CONTENT_TOP: float = 174.0
const CONTENT_BOTTOM: float = 314.0
const FOOTER_Y: float = 320.0
const SLIDER_W: float = 96.0
const ICONS_PATH: String = "res://assets/ui/menu_icons.png"
const ICONS_GLOW_PATH: String = "res://assets/ui/menu_icons_glow.png"

const ADDRESS_CHARS: String = "0123456789.:-abcdefghijklmnopqrstuvwxyz"
const HINTS: Dictionary = {
	"continue": "DORT WEITER, WO DU AUFGEHÖRT HAST",
	"new": "EINE NEUE GESCHICHTE BEGINNT IM DUNKELN",
	"multi": "EIGENE KOOP-WELTEN, CODE & LAN-BEITRITT",
	"settings": "TON, BILD, SPIEL UND STEUERUNG",
	"quit": "DIE LEERE WARTET SCHON",
}
const SETTINGS_TABS: Array[Dictionary] = [
	{"id": 0, "name": "TON", "x": 62.0, "icon": 0},
	{"id": 1, "name": "BILD", "x": 132.0, "icon": 1},
	{"id": 2, "name": "SPIEL", "x": 204.0, "icon": 2},
	{"id": 3, "name": "TASTEN", "x": 286.0, "icon": 3},
]
const MULTI_TABS: Array[Dictionary] = [
	{"id": "multi", "name": "WELTEN", "x": 86.0, "icon": 5},
	{"id": "join_page", "name": "BEITRETEN", "x": 182.0, "icon": 13},
]
const CONTROLS_LIST: Array[Array] = [
	["BEWEGEN", "", "WASD"],
	["SPRINTEN", "sprint", "SHIFT"],
	["SCHATTENSCHRITT", "shadow_step", "LEER"],
	["SCHLEICHEN", "sneak", "STRG"],
	["BENUTZEN", "interact", "E"],
	["ANGRIFF", "action_primary", "LMT"],
	["ZWEITHAND", "action_secondary", "RMT"],
	["INVENTAR", "inventory", "I"],
	["KARTE", "map", "M"],
	["TAGEBUCH", "quest_journal", "J"],
	["FÄHIGKEITEN", "skills", "F"],
	["FORTSCHRITT", "progress", "P"],
]

var page: Page = Page.MAIN
var intro: float = 0.0
var enabled: bool = false
var address: String = "127.0.0.1"
var join_code: String = ""
var status: String = ""
var fire_point: Vector2 = Vector2(468.0, 282.0)

var _time: float = 0.0
var _rows: Array[Dictionary] = []
var _rects: Array[Rect2] = []
var _hitboxes: Array[Dictionary] = [] ## {rect, action, payload}
var _sel: int = 0
var _hover: int = -1
var _hover_sub: String = ""
var _last_mouse: Vector2 = Vector2(-1.0, -1.0)
var _page_age: float = 0.0
var _save_day: int = -1
var _slide: Array[float] = []
var _last_sel: int = -1
var _sel_age: float = 0.0
var _scroll: float = 0.0
var _content_h: float = 0.0
var _drag_slider: String = ""
var _settings_tab: int = 0
var _creating_world: bool = false
var _new_world_name: String = "WALDLICHTUNG"
var _new_world_code: String = ""
var _new_world_max: int = 4
var _new_world_port: String = "7777"
var _worlds_cache: Array[Dictionary] = []
var _recent_cache: Array[Dictionary] = []
var _armed_delete_id: String = ""
var _armed_left: float = 0.0
var _editing_id: String = ""
var _status_timer: float = 0.0
var _status_is_error: bool = false
var _player_name_buf: String = "ELLIE"
var _icons: Texture2D = null
var _icons_glow: Texture2D = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_save_day = int(SaveGame.info().get("day", -1)) if SaveGame.exists() else -1
	_player_name_buf = MultiplayerWorlds.sanitize_name(String(GameSettings.get_value("player_name")), "ELLIE")
	_new_world_code = MultiplayerWorlds.generate_code()
	_reload_icons()
	_open_page(Page.MAIN)


func _reload_icons() -> void:
	if _icons == null and ResourceLoader.exists(ICONS_PATH):
		_icons = load(ICONS_PATH) as Texture2D
	if _icons_glow == null and ResourceLoader.exists(ICONS_GLOW_PATH):
		_icons_glow = load(ICONS_GLOW_PATH) as Texture2D


func apply_return_state(ret: Dictionary) -> void:
	if ret.is_empty():
		return
	var target: String = String(ret.get("page", ""))
	if target == "join":
		var ret_addr: String = String(ret.get("address", "127.0.0.1"))
		var ret_port: int = int(ret.get("port", NetworkManager.DEFAULT_PORT))
		address = ret_addr if ret_port == NetworkManager.DEFAULT_PORT else ("%s:%d" % [ret_addr, ret_port])
		join_code = MultiplayerWorlds.normalize_code(String(ret.get("code", "")))
		_open_page(Page.JOIN)
		_set_status(String(ret.get("error", "VERBINDUNG FEHLGESCHLAGEN")), true, 6.0)
	elif target == "multi":
		_open_page(Page.MULTI)
		_set_status(String(ret.get("error", "HOST FEHLGESCHLAGEN")), true, 6.0)


func _exit_tree() -> void:
	GameCursor.set_hint(self, &"")


func focus_point() -> Vector2:
	if _sel >= 0 and _sel < _rects.size() and _rects[_sel].size.x > 0.0:
		return _rects[_sel].get_center()
	if page != Page.MAIN:
		return PANEL_RECT.get_center()
	return VIEW * 0.5


func _set_status(msg: String, is_error: bool = false, duration: float = 3.2) -> void:
	status = msg
	_status_is_error = is_error
	_status_timer = duration


func _open_page(next: Page, reset_sub: bool = true) -> void:
	page = next
	_page_age = 0.0
	_scroll = 0.0
	_drag_slider = ""
	_armed_delete_id = ""
	_editing_id = ""
	if reset_sub:
		_creating_world = false
		status = ""
		_status_timer = 0.0
	_player_name_buf = MultiplayerWorlds.sanitize_name(String(GameSettings.get_value("player_name")), "ELLIE")
	_rebuild_rows()
	_sel = 0
	for i: int in _rows.size():
		if _row_selectable(_rows[i]):
			_sel = i
			break
	if page == Page.JOIN:
		_editing_id = "addr"
	elif page == Page.MULTI and _creating_world:
		_editing_id = "new_world_name"
	_hover = -1
	_hover_sub = ""
	_rects.clear()
	_slide.clear()
	_slide.resize(_rows.size())
	_slide.fill(0.0)
	_last_sel = -1


func _rebuild_rows() -> void:
	_rows.clear()
	match page:
		Page.MAIN:
			if SaveGame.exists():
				_rows.append({"id": "continue", "label": "WEITER"})
			_rows.append_array([
				{"id": "new", "label": "NEUES SPIEL"},
				{"id": "multi", "label": "MEHRSPIELER"},
				{"id": "settings", "label": "EINSTELLUNGEN"},
				{"id": "quit", "label": "BEENDEN"},
			])
		Page.CONFIRM_NEW:
			_rows.append_array([
				{"id": "new_yes", "label": "JA, NEU BEGINNEN"},
				{"id": "back", "label": "ABBRECHEN"},
			])
		Page.MULTI:
			_worlds_cache = MultiplayerWorlds.list()
			if _creating_world:
				_rows.append_array([
					{"id": "new_world_name", "label": "WELTNAME", "kind": "field"},
					{"id": "new_world_code", "label": "JOIN-CODE", "kind": "field"},
					{"id": "new_world_max", "label": "MAX. SPIELER", "kind": "stepper"},
					{"id": "new_world_port", "label": "PORT", "kind": "field"},
					{"id": "create_confirm", "label": "ERSTELLEN & STARTEN", "kind": "action"},
					{"id": "create_cancel", "label": "ABBRECHEN", "kind": "action"},
				])
			else:
				_rows.append({"id": "create_mode", "label": "NEUE KOOP-WELT ERSTELLEN", "kind": "create_btn"})
				for i: int in _worlds_cache.size():
					_rows.append({"id": "world:%d" % i, "label": String(_worlds_cache[i].get("name", "KOOP-WELT")), "kind": "world_card", "index": i})
				_rows.append({"id": "join_page", "label": "BEITRETEN", "kind": "footer"})
				_rows.append({"id": "back", "label": "ZURÜCK", "kind": "footer"})
		Page.JOIN:
			_recent_cache = MultiplayerWorlds.recent_hosts()
			_rows.append_array([
				{"id": "addr", "label": "IP-ADRESSE", "kind": "field"},
				{"id": "join_code", "label": "JOIN-CODE", "kind": "field"},
				{"id": "join", "label": "VERBINDEN", "kind": "action"},
			])
			for i: int in mini(_recent_cache.size(), 3):
				_rows.append({"id": "recent:%d" % i, "label": String(_recent_cache[i].get("label", "")), "kind": "recent", "index": i})
			_rows.append({"id": "back", "label": "ZURÜCK", "kind": "footer"})
		Page.SETTINGS:
			match _settings_tab:
				0:
					_rows.append_array([
						{"id": "master", "label": "GESAMT", "kind": "slider"},
						{"id": "music", "label": "MUSIK", "kind": "slider"},
						{"id": "sfx", "label": "EFFEKTE", "kind": "slider"},
					])
				1:
					_rows.append_array([
						{"id": "fullscreen", "label": "VOLLBILD", "kind": "toggle"},
						{"id": "vsync", "label": "VSYNC", "kind": "toggle"},
						{"id": "shake", "label": "KAMERA-SCHÜTTELN", "kind": "slider"},
						{"id": "flash_soft", "label": "BLITZE SANFT", "kind": "toggle"},
					])
				2:
					_rows.append_array([
						{"id": "player_name", "label": "SPIELERNAME", "kind": "field"},
						{"id": "weather_fx", "label": "WETTER-EFFEKTE", "kind": "weather"},
						{"id": "cursor", "label": "EIGENER CURSOR", "kind": "toggle"},
						{"id": "numbers", "label": "SCHADENSZAHLEN", "kind": "toggle"},
						{"id": "position", "label": "POSITION", "kind": "toggle"},
						{"id": "journal_still", "label": "TAGEBUCH OHNE BEWEGUNG", "kind": "toggle"},
					])
				3:
					for row: Array in CONTROLS_LIST:
						_rows.append({"id": "ctrl:" + String(row[0]), "label": String(row[0]), "action": String(row[1]), "fallback": String(row[2]), "kind": "control"})
			_rows.append({"id": "back", "label": "FERTIG", "kind": "footer"})


func _row_selectable(row: Dictionary) -> bool:
	return String(row.get("kind", "")) != "control"


func _process(delta: float) -> void:
	_time += delta
	_page_age += delta
	_sel_age += delta
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			status = ""
	if not _armed_delete_id.is_empty():
		_armed_left -= delta
		if _armed_left <= 0.0:
			_armed_delete_id = ""
	if _sel != _last_sel:
		if _last_sel >= 0 and enabled:
			Sfx.ui(self, "ui_click", -12.0, 0.08)
		_last_sel = _sel
		_sel_age = 0.0
	for i: int in _slide.size():
		_slide[i] = move_toward(_slide[i], 1.0 if i == _sel and enabled else 0.0, delta * 7.0)
	if not enabled:
		GameCursor.set_hint(self, &"")
		queue_redraw()
		return
	var mouse: Vector2 = get_local_mouse_position()
	var moved: bool = mouse.distance_to(_last_mouse) > 0.5
	_last_mouse = mouse
	if not _drag_slider.is_empty():
		_apply_slider_drag(_drag_slider, mouse)
	var over: int = -1
	for i: int in _rects.size():
		if _rects[i].size.x > 0.0 and _rects[i].grow(2.0).has_point(mouse):
			over = i
			break
	_hover = over
	_hover_sub = ""
	for hb: Dictionary in _hitboxes:
		if (hb["rect"] as Rect2).grow(1.0).has_point(mouse):
			_hover_sub = String(hb["action"])
			break
	if moved and over >= 0 and over < _rows.size() and _row_selectable(_rows[over]):
		_sel = over
	GameCursor.set_hint(self, &"click" if (over >= 0 or not _hover_sub.is_empty()) else &"")
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			if not button.pressed:
				_drag_slider = ""
				return
			var mpos: Vector2 = get_local_mouse_position()
			for hb: Dictionary in _hitboxes:
				if (hb["rect"] as Rect2).grow(1.0).has_point(mpos):
					_handle_sub_action(String(hb["action"]), hb.get("payload", null))
					get_viewport().set_input_as_handled()
					return
			if _hover >= 0 and _hover < _rows.size():
				_sel = _hover
				_press(_rows[_sel], mpos)
				get_viewport().set_input_as_handled()
			else:
				_editing_id = ""
			return
		elif button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if page != Page.MAIN:
				var dir: float = -1.0 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				var max_scroll: float = maxf(_content_h - (CONTENT_BOTTOM - CONTENT_TOP), 0.0)
				_scroll = clampf(_scroll + dir * 22.0, 0.0, max_scroll)
				get_viewport().set_input_as_handled()
				return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed:
		if _active_field_id() != "":
			if _type(key):
				get_viewport().set_input_as_handled()
				return
		if page == Page.SETTINGS and not key.echo and key.physical_keycode in [KEY_Q, KEY_E, KEY_TAB]:
			var dir: int = -1 if key.physical_keycode == KEY_Q else 1
			_settings_tab = posmod(_settings_tab + dir, SETTINGS_TABS.size())
			Sfx.ui(self, "ui_click", -3.0)
			_open_page(Page.SETTINGS, false)
			get_viewport().set_input_as_handled()
			return
		if (page == Page.MULTI or page == Page.JOIN) and not _creating_world and _editing_id.is_empty() and not key.echo and key.physical_keycode in [KEY_Q, KEY_E]:
			var next_page: Page = Page.JOIN if page == Page.MULTI else Page.MULTI
			Sfx.ui(self, "ui_click", -3.0)
			_open_page(next_page)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if page != Page.MAIN:
			Sfx.ui(self, "ui_back", -4.0)
			if _creating_world:
				_creating_world = false
				_open_page(Page.MULTI)
			else:
				GameSettings.save()
				_open_page(Page.MAIN)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_up"):
		_step_sel(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down"):
		_step_sel(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		if _sel >= 0 and _sel < _rows.size():
			var row: Dictionary = _rows[_sel]
			var kind: String = String(row.get("kind", ""))
			var dir: int = -1 if event.is_action_pressed(&"ui_left") else 1
			if kind == "slider":
				_step_slider(String(row.id), dir * 5)
			elif kind == "toggle":
				_flip(String(row.id))
			elif kind == "weather":
				_cycle_weather(dir)
			elif kind == "stepper":
				_new_world_max = clampi(_new_world_max + dir, 2, 4)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept") or (event.is_action_pressed(&"interact") and key != null and _active_field_id().is_empty()):
		if _sel >= 0 and _sel < _rows.size():
			_press(_rows[_sel], Vector2(-1.0, -1.0))
		get_viewport().set_input_as_handled()


func _step_sel(dir: int) -> void:
	if _rows.is_empty():
		return
	var start: int = _sel
	for _k: int in _rows.size():
		start = posmod(start + dir, _rows.size())
		if _row_selectable(_rows[start]):
			_sel = start
			_editing_id = String(_rows[_sel].id) if String(_rows[_sel].get("kind", "")) == "field" else ""
			_ensure_visible(_sel)
			return


func _ensure_visible(idx: int) -> void:
	if idx < 0 or idx >= _rects.size() or page == Page.MAIN:
		return
	var r: Rect2 = _rects[idx]
	if r.size.y <= 0.0:
		return
	if r.position.y < CONTENT_TOP:
		_scroll = maxf(_scroll - (CONTENT_TOP - r.position.y) - 6.0, 0.0)
	elif r.end.y > CONTENT_BOTTOM and String(_rows[idx].get("kind", "")) != "footer":
		var max_scroll: float = maxf(_content_h - (CONTENT_BOTTOM - CONTENT_TOP), 0.0)
		_scroll = clampf(_scroll + (r.end.y - CONTENT_BOTTOM) + 6.0, 0.0, max_scroll)


func _active_field_id() -> String:
	if not _editing_id.is_empty():
		return _editing_id
	if _sel >= 0 and _sel < _rows.size() and String(_rows[_sel].get("kind", "")) == "field":
		return String(_rows[_sel].id)
	return ""


## Typing into whichever text field is focused (`addr`, `join_code`, `new_world_name`, `new_world_code`, `new_world_port`, `player_name`).
func _type(key: InputEventKey) -> bool:
	var field_id: String = _active_field_id()
	if field_id.is_empty():
		return false
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		if _editing_id == "player_name":
			_editing_id = ""
			return true
		return false
	if key.keycode == KEY_ESCAPE or key.keycode == KEY_UP or key.keycode == KEY_DOWN:
		return false
	if key.keycode == KEY_TAB:
		_step_sel(1)
		return true
	match field_id:
		"addr":
			return _type_addr(key)
		"join_code":
			return _type_code(key, true)
		"new_world_code":
			return _type_code(key, false)
		"new_world_name":
			return _type_name(key, false)
		"player_name":
			return _type_name(key, true)
		"new_world_port":
			return _type_port(key)
	return false


func _type_addr(key: InputEventKey) -> bool:
	if key.keycode == KEY_BACKSPACE:
		address = address.substr(0, maxi(address.length() - 1, 0))
		return true
	if key.keycode == KEY_V and key.ctrl_pressed:
		_paste_join_clipboard(DisplayServer.clipboard_get())
		return true
	if key.unicode > 31 and not key.ctrl_pressed:
		var c: String = char(key.unicode).to_lower()
		if ADDRESS_CHARS.contains(c) and address.length() < 40:
			address += c
		return true
	return false


func _paste_join_clipboard(raw: String) -> void:
	var trimmed: String = raw.strip_edges()
	if " " in trimmed or "|" in trimmed:
		var norm: String = trimmed.replace("|", " ")
		var parts: PackedStringArray = norm.split(" ", false)
		if parts.size() >= 2:
			address = _filter_addr(parts[0])
			join_code = MultiplayerWorlds.normalize_code(parts[1])
			return
	address = _filter_addr(trimmed)


func _filter_addr(raw: String) -> String:
	var out: String = ""
	for c: String in raw.to_lower():
		if ADDRESS_CHARS.contains(c) and out.length() < 40:
			out += c
	return out


func _type_code(key: InputEventKey, for_join: bool) -> bool:
	var buf: String = join_code if for_join else _new_world_code
	if key.keycode == KEY_BACKSPACE:
		buf = buf.substr(0, maxi(buf.length() - 1, 0))
	elif key.keycode == KEY_V and key.ctrl_pressed:
		var clip: String = DisplayServer.clipboard_get().strip_edges()
		if for_join and (" " in clip or "|" in clip):
			_paste_join_clipboard(clip)
			return true
		buf = MultiplayerWorlds.normalize_code(clip)
	elif key.unicode > 31 and not key.ctrl_pressed:
		var c: String = char(key.unicode).to_upper()
		if buf.length() < 6:
			buf = MultiplayerWorlds.normalize_code(buf + c)
	else:
		return false
	if for_join:
		join_code = buf
	else:
		_new_world_code = buf
	return true


func _type_name(key: InputEventKey, is_player_name: bool) -> bool:
	var buf: String = _player_name_buf if is_player_name else _new_world_name
	if key.keycode == KEY_BACKSPACE:
		buf = buf.substr(0, maxi(buf.length() - 1, 0))
	elif key.keycode == KEY_V and key.ctrl_pressed:
		buf = MultiplayerWorlds.sanitize_name(DisplayServer.clipboard_get(), "")
	elif key.unicode > 31 and not key.ctrl_pressed:
		var c: String = char(key.unicode).to_upper()
		var ok: bool = (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c in "ÄÖÜ -"
		if ok and buf.length() < 16:
			buf += c
	else:
		return false
	if is_player_name:
		_player_name_buf = buf
		if not buf.strip_edges().is_empty():
			GameSettings.set_value("player_name", MultiplayerWorlds.sanitize_name(buf, "ELLIE"))
			GameSettings.save()
	else:
		_new_world_name = buf
	return true


func _type_port(key: InputEventKey) -> bool:
	if key.keycode == KEY_BACKSPACE:
		_new_world_port = _new_world_port.substr(0, maxi(_new_world_port.length() - 1, 0))
		return true
	if key.unicode > 31 and not key.ctrl_pressed:
		var c: String = char(key.unicode)
		if c >= "0" and c <= "9" and _new_world_port.length() < 5:
			_new_world_port += c
		return true
	return false


func _step_slider(id: String, step: int) -> void:
	GameSettings.set_value(id, clampi(int(GameSettings.get_value(id)) + step, 0, 100))
	GameSettings.save()


func _flip(id: String) -> void:
	GameSettings.set_value(id, not bool(GameSettings.get_value(id)))
	GameSettings.save()


func _cycle_weather(dir: int) -> void:
	var cur: int = clampi(int(GameSettings.get_value("weather_fx")), 0, 2)
	GameSettings.set_value("weather_fx", posmod(cur + dir, 3))
	GameSettings.save()


func _apply_slider_drag(id: String, mouse: Vector2) -> void:
	for i: int in _rows.size():
		if String(_rows[i].id) == id and i < _rects.size():
			var r: Rect2 = _rects[i]
			var bar_x: float = r.end.x - SLIDER_W - 28.0
			var ratio: float = clampf((mouse.x - bar_x) / SLIDER_W, 0.0, 1.0)
			GameSettings.set_value(id, clampi(roundi(ratio * 20.0) * 5, 0, 100))
			GameSettings.save()
			return


func _handle_sub_action(action: String, payload: Variant) -> void:
	Sfx.ui(self, "ui_confirm", -4.0)
	if action == "settings_tab":
		_settings_tab = int(payload)
		_open_page(Page.SETTINGS, false)
		return
	if action == "multi_tab":
		_creating_world = false
		_open_page(Page.MULTI if String(payload) == "multi" else Page.JOIN)
		return
	if action == "edit_player_name":
		_editing_id = "player_name"
		return
	if action == "copy_host_ip":
		var ip_str: String = "%s:%d" % [NetworkManager.primary_ip(), NetworkManager.DEFAULT_PORT]
		DisplayServer.clipboard_set(ip_str)
		_set_status("IP KOPIERT: %s" % ip_str, false, 2.5)
		return
	if action == "reroll_code":
		_new_world_code = MultiplayerWorlds.generate_code()
		_set_status("NEUER CODE: %s" % _new_world_code, false, 2.0)
		return
	if action.begins_with("world_host:"):
		var idx: int = int(action.trim_prefix("world_host:"))
		if idx >= 0 and idx < _worlds_cache.size():
			_launch_world(_worlds_cache[idx])
		return
	if action.begins_with("world_copy:"):
		var idx: int = int(action.trim_prefix("world_copy:"))
		if idx >= 0 and idx < _worlds_cache.size():
			var w: Dictionary = _worlds_cache[idx]
			var inv: String = "%s:%d %s" % [NetworkManager.primary_ip(), int(w.get("port", 7777)), String(w.get("code", ""))]
			DisplayServer.clipboard_set(inv)
			_set_status("EINLADUNG KOPIERT", false, 2.5)
		return
	if action.begins_with("world_del:"):
		var wid: String = action.trim_prefix("world_del:")
		if _armed_delete_id != wid:
			_armed_delete_id = wid
			_armed_left = 2.6
			_set_status("NOCHMAL KLICKEN ZUM LÖSCHEN", true, 2.6)
		else:
			_armed_delete_id = ""
			MultiplayerWorlds.delete_world(wid)
			_set_status("WELT GELÖSCHT", false, 2.2)
			_open_page(Page.MULTI, false)
		return
	if action.begins_with("recent_fill:"):
		var idx: int = int(action.trim_prefix("recent_fill:"))
		if idx >= 0 and idx < _recent_cache.size():
			var rh: Dictionary = _recent_cache[idx]
			var rport: int = int(rh.get("port", NetworkManager.DEFAULT_PORT))
			var raddr: String = String(rh.get("address", "127.0.0.1"))
			address = raddr if rport == NetworkManager.DEFAULT_PORT else ("%s:%d" % [raddr, rport])
			join_code = String(rh.get("code", ""))
			_set_status("DATEN ÜBERNOMMEN", false, 2.0)
		return


func _launch_world(w: Dictionary) -> void:
	chosen.emit("host", {
		"world_id": String(w.get("id", "")),
		"world_name": String(w.get("name", "KOOP-WELT")),
		"code": String(w.get("code", "")),
		"port": int(w.get("port", NetworkManager.DEFAULT_PORT)),
		"max_players": int(w.get("max_players", NetworkManager.MAX_PLAYERS)),
		"save_path": String(w.get("save_path", "")),
	})


func _press(row: Dictionary, at: Vector2) -> void:
	Sfx.ui(self, "ui_confirm", -3.0)
	var id: String = String(row.id)
	var kind: String = String(row.get("kind", ""))
	if kind == "slider":
		var rect: Rect2 = _rects[_sel] if _sel < _rects.size() else Rect2()
		if at.x >= 0.0 and rect.size.x > 0.0:
			var bar_x: float = rect.end.x - SLIDER_W - 28.0
			if at.x >= bar_x - 6.0:
				_drag_slider = id
				_apply_slider_drag(id, at)
			else:
				_step_slider(id, -10)
		else:
			_step_slider(id, 10)
		return
	if kind == "toggle":
		_flip(id)
		return
	if kind == "weather":
		_cycle_weather(1)
		return
	if kind == "stepper":
		_new_world_max = 2 if _new_world_max >= 4 else _new_world_max + 1
		return
	if kind == "field":
		_editing_id = id
		return
	if kind == "world_card":
		var idx: int = int(row.get("index", -1))
		if idx >= 0 and idx < _worlds_cache.size():
			_launch_world(_worlds_cache[idx])
		return
	if kind == "recent":
		_handle_sub_action("recent_fill:%d" % int(row.get("index", 0)), null)
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
		"create_mode":
			_creating_world = true
			_new_world_name = "WALDLICHTUNG"
			_new_world_code = MultiplayerWorlds.generate_code()
			_new_world_port = str(NetworkManager.DEFAULT_PORT)
			_open_page(Page.MULTI, false)
		"create_cancel":
			_creating_world = false
			_open_page(Page.MULTI)
		"create_confirm":
			var port_num: int = clampi(_new_world_port.to_int() if _new_world_port.is_valid_int() else NetworkManager.DEFAULT_PORT, 1024, 65535)
			var created: Dictionary = MultiplayerWorlds.create_world(_new_world_name, _new_world_max, port_num, _new_world_code)
			_creating_world = false
			_launch_world(created)
		"host":
			var worlds: Array[Dictionary] = MultiplayerWorlds.list()
			if worlds.is_empty():
				var created: Dictionary = MultiplayerWorlds.create_world("KOOP-WELT", 4, NetworkManager.DEFAULT_PORT)
				_launch_world(created)
			else:
				_launch_world(worlds[0])
		"join_page":
			_open_page(Page.JOIN)
		"join":
			var parsed: Dictionary = MultiplayerWorlds.parse_address_port(address, NetworkManager.DEFAULT_PORT)
			var host: String = String(parsed.get("address", ""))
			if host.is_empty():
				_set_status("KEINE IP-ADRESSE ANGEGEBEN", true, 3.0)
				return
			var clean_code: String = MultiplayerWorlds.normalize_code(join_code)
			chosen.emit("join", {"address": host, "port": int(parsed.get("port", NetworkManager.DEFAULT_PORT)), "code": clean_code})
		"settings":
			_open_page(Page.SETTINGS)
		"quit":
			chosen.emit("quit", {})
		"back":
			GameSettings.save()
			if _creating_world:
				_creating_world = false
				_open_page(Page.MULTI)
			else:
				_open_page(Page.MAIN)


# ---------------------------------------------------------------------------------------------- drawing

func _draw() -> void:
	_reload_icons()
	var void_level: float = VineStyle.void_amount()
	if page == Page.MAIN:
		_draw_main(void_level)
	else:
		_draw_sanctuary(void_level)


func _row_y(i: int) -> float:
	return MENU_Y + float(i) * ROW_GAP


func _glyph(ch: String, at: Vector2, ink: Color, outline: Color) -> void:
	var zoom: Vector2 = Vector2(TEXT_SCALE, TEXT_SCALE)
	if outline.a > 0.0:
		for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
			draw_set_transform(at + o, 0.0, zoom)
			PixelText.draw(self, ch, Vector2i.ZERO, outline)
	draw_set_transform(at, 0.0, zoom)
	PixelText.draw(self, ch, Vector2i.ZERO, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _bezier(a: Vector2, c: Vector2, b: Vector2, u: float) -> Vector2:
	return a.lerp(c, u).lerp(c.lerp(b, u), u)


func _spore_mark(center: Vector2, alpha: float) -> void:
	var beat: float = TitleLogo.beat(_time * 0.9)
	var r: int = 2 + (1 if beat > 0.35 else 0)
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var d: int = absi(dx) + absi(dy)
			if d > r:
				continue
			var c: Color = MenuEmbers.SPORE_CORE if d == 0 else (MenuEmbers.SPORE if d == 1 else MenuEmbers.SPORE_DIM)
			draw_rect(Rect2(center + Vector2(dx, dy), Vector2.ONE), Color(c, alpha * (1.0 if d < r else 0.7)))
	VineStyle.glow(self, center + Vector2(0.5, 0.5), 10.0, MenuEmbers.SPORE, alpha * (0.5 + 0.5 * beat))


func _draw_main(_void_level: float) -> void:
	_hitboxes.clear()
	if intro <= 0.0:
		return
	var advance: float = float(PixelText.ADVANCE) * TEXT_SCALE
	_rects.clear()
	for i: int in _rows.size():
		var label: String = String(_rows[i].label)
		var slide: float = _slide[i] if i < _slide.size() else 0.0
		var eased: float = slide * slide * (3.0 - 2.0 * slide)
		var x0: float = MENU_X + roundf(9.0 * eased)
		var y: float = _row_y(i)
		var w: float = float(label.length()) * advance
		var mid_y: float = y + 9.0
		if eased > 0.01:
			VineStyle.glow(self, Vector2(x0 + w * 0.45, mid_y), 46.0, VineStyle.ACCENT_WARM, 0.18 * eased)
			_spore_mark(Vector2(x0 - 11.0, mid_y).round(), eased)
			var line_w: int = int(w * eased)
			for k: int in range(0, line_w, 2):
				var fall: float = 1.0 - float(k) / maxf(w, 1.0)
				draw_rect(Rect2(x0 + float(k), y + 17.0, 2.0, 1.0), Color(VineStyle.ACCENT_WARM, 0.7 * fall * eased))
		var shimmer: float = fmod(_sel_age * 16.0, float(label.length()) + 10.0) - 2.0 if eased > 0.5 else -99.0
		var row_done: bool = true
		for j: int in label.length():
			var ch: String = label[j]
			var target: Vector2 = Vector2(x0 + float(j) * advance, y)
			var delay: float = ROW_DELAY * float(i) + CHAR_DELAY * float(j)
			var p: float = clampf((intro - delay) / FLIGHT, 0.0, 1.0)
			if p < 1.0:
				row_done = false
			if ch == " " or p <= 0.0:
				continue
			if p < 1.0:
				var u: float = p * p * (3.0 - 2.0 * p)
				var seed_value: float = float(i * 31 + j * 7)
				var start: Vector2 = fire_point + Vector2(sin(seed_value) * 6.0, cos(seed_value * 1.7) * 3.0)
				var land: Vector2 = target + Vector2(3.0, 8.0)
				var ctrl: Vector2 = Vector2(lerpf(start.x, land.x, 0.55), minf(start.y, land.y) - 60.0 - 24.0 * sin(seed_value * 0.9))
				for k: int in 4:
					var tu: float = u - float(k) * 0.045
					if tu <= 0.0:
						break
					var at: Vector2 = _bezier(start, ctrl, land, tu).round()
					var c: Color = MenuEmbers.EMBER_HOT if k == 0 else MenuEmbers.EMBER_MID.lerp(MenuEmbers.EMBER_COOL, float(k) / 3.0)
					var sz: float = 2.0 if k == 0 else 1.0
					draw_rect(Rect2(at, Vector2(sz, sz)), Color(c, (1.0 - float(k) * 0.25) * (1.0 - smoothstep(0.85, 1.0, p))))
			var a: float = smoothstep(0.78, 1.0, p)
			if a <= 0.0:
				continue
			var landed: float = intro - delay - FLIGHT
			var ink: Color = IDLE_INK.lerp(VineStyle.ACCENT_WARM, eased)
			if absf(float(j) - shimmer) < 1.0:
				ink = HOT_INK
			if landed >= 0.0 and landed < 0.35:
				ink = HOT_INK.lerp(ink, landed / 0.35)
			_glyph(ch, target, Color(ink, a), Color(VineStyle.OUTLINE, a))
		_rects.append(Rect2(MENU_X - 20.0, y - 2.0, w + 40.0, ROW_GAP - 2.0) if row_done else Rect2())
	if enabled and _sel < _rows.size():
		var text: String = String(HINTS.get(String(_rows[_sel].id), ""))
		if String(_rows[_sel].id) == "continue" and _save_day >= 0:
			text = "TAG %d - %s" % [_save_day + 1, text]
		var shown: String = text.substr(0, int(_sel_age * 70.0))
		var hint_y: float = _row_y(_rows.size()) + 6.0
		draw_rect(Rect2(MENU_X, hint_y - 5.0, 18.0, 1.0), Color(IDLE_INK, 0.5))
		PixelText.draw(self, shown, Vector2i(int(MENU_X), int(hint_y)), Color(IDLE_INK, 0.9), Color(VineStyle.OUTLINE, 0.9))
		if not status.is_empty():
			PixelText.draw(self, status, Vector2i(int(MENU_X), int(hint_y + 11.0)), Color(DANGER if _status_is_error else Color("7fe3da")), Color(VineStyle.OUTLINE))


func _draw_sanctuary(void_level: float) -> void:
	_hitboxes.clear()
	var grow: float = VineStyle.back_out(clampf(_page_age / 0.32, 0.0, 1.0))
	var fade: float = clampf(_page_age / 0.2, 0.0, 1.0)
	var dy: float = (1.0 - clampf(grow, 0.0, 1.15)) * 12.0
	var rect: Rect2 = Rect2(PANEL_RECT.position + Vector2(0.0, dy), PANEL_RECT.size)
	if page == Page.CONFIRM_NEW:
		rect = Rect2(Vector2(PANEL_RECT.position.x, 174.0 + dy), Vector2(PANEL_RECT.size.x, 126.0))

	# Hanging vine branch across the left-sanctuary header (Settings & Multiplayer tabs)
	var has_tabs: bool = page == Page.SETTINGS or ((page == Page.MULTI or page == Page.JOIN) and not _creating_world)
	if has_tabs:
		var branch_fn: Callable = func(x: float) -> float:
			return BRANCH_Y + dy + sin(x * 0.03) * 1.4
		VineStyle.branch(self, 0.0, rect.end.x + 18.0, branch_fn, 5, void_level * 0.4, 18.0, _time, fade)
		VineStyle.foliage(self, 0.0, rect.end.x + 14.0, branch_fn, 9, 211, void_level * 0.4, 14.0, _time, fade)
		_draw_header_tabs(fade, dy, void_level)

	# Panel body with soft aura
	VineStyle.glow(self, rect.get_center(), 150.0, Color("7fe3da") if page in [Page.MULTI, Page.JOIN] else VineStyle.ACCENT_WARM, 0.07 * fade)
	VineStyle.paper(self, rect, fade, void_level * 0.45, 7)
	draw_rect(Rect2(rect.position.x + 4.0, rect.position.y + 3.0, rect.size.x - 8.0, 1.0), Color("7fe3da" if page in [Page.MULTI, Page.JOIN] else "ffd98a", 0.25 * fade))

	# Panel header line
	var title: String = _page_title()
	var icon_idx: int = 5 if page == Page.MULTI else (13 if page == Page.JOIN else (int(SETTINGS_TABS[_settings_tab]["icon"]) if page == Page.SETTINGS else 10))
	_draw_icon(icon_idx, Vector2(rect.position.x + 12.0, rect.position.y + 8.0), fade)
	PixelText.draw(self, title, Vector2i(int(rect.position.x + 28.0), int(rect.position.y + 11.0)), Color(VineStyle.ACCENT_WARM, fade), Color(VineStyle.OUTLINE, fade))

	# Player name badge on MP header
	if page in [Page.MULTI, Page.JOIN] and not _creating_world:
		var name_disp: String = _player_name_buf if not _player_name_buf.is_empty() else "ELLIE"
		var pill_txt: String = "NAME: " + name_disp
		var editing_name: bool = _editing_id == "player_name"
		var pw: float = float(PixelText.width(pill_txt)) + (18.0 if editing_name else 12.0)
		var pr: Rect2 = Rect2(rect.end.x - pw - 10.0, rect.position.y + 8.0, pw, 13.0)
		var nhot: bool = _hover_sub == "edit_player_name" or editing_name
		draw_rect(pr, Color("7fe3da" if editing_name else VineStyle.OUTLINE, fade))
		draw_rect(pr.grow(-1.0), Color("241e42" if nhot else "1a1630", fade))
		PixelText.draw(self, pill_txt, Vector2i(int(pr.position.x + 6.0), int(pr.position.y + 3.0)), Color("b9f3ee" if nhot else "c8c3df", fade), Color(VineStyle.OUTLINE, fade))
		if editing_name and int(_time * 2.4) % 2 == 0:
			var cx: float = pr.position.x + 6.0 + float(PixelText.width(pill_txt)) + 1.0
			draw_rect(Rect2(cx, pr.position.y + 2.0, 1.0, 8.0), Color("7fe3da", fade))
		_hitboxes.append({"rect": pr, "action": "edit_player_name"})

	draw_rect(Rect2(rect.position.x + 12.0, rect.position.y + 26.0, rect.size.x - 24.0, 1.0), Color("4a4180", 0.5 * fade))

	_rects.clear()
	_rects.resize(_rows.size())
	_rects.fill(Rect2())

	if page == Page.CONFIRM_NEW:
		_draw_confirm_body(rect, fade)
		return
	if page == Page.SETTINGS and _settings_tab == 3:
		_draw_controls_grid(rect, fade, void_level)
		_draw_footer_bar(rect, fade)
		return

	var y: float = CONTENT_TOP + dy - _scroll
	var top_y: float = rect.position.y + 30.0
	var bot_y: float = rect.end.y - 28.0
	var start_y: float = y
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		var kind: String = String(row.get("kind", ""))
		if kind == "footer":
			continue
		var row_h: float = _row_height(kind)
		var row_rect: Rect2 = Rect2(rect.position.x + 12.0, y, rect.size.x - 24.0, row_h)
		var visible_in_view: bool = row_rect.position.y >= top_y - 2.0 and row_rect.end.y <= bot_y + 2.0
		if visible_in_view:
			_rects[i] = row_rect
			_draw_row_widget(i, row, row_rect, fade, void_level)
		y += row_h + 4.0
	_content_h = y - start_y

	# Scrollbar indicator if overflow
	var max_scroll: float = maxf(_content_h - (bot_y - top_y), 0.0)
	if max_scroll > 2.0:
		var track_h: float = bot_y - top_y - 4.0
		var thumb_h: float = maxf(track_h * clampf((bot_y - top_y) / _content_h, 0.2, 1.0), 14.0)
		var thumb_y: float = top_y + (_scroll / max_scroll) * (track_h - thumb_h)
		draw_rect(Rect2(rect.end.x - 7.0, top_y, 2.0, track_h), Color("171329", 0.7 * fade))
		draw_rect(Rect2(rect.end.x - 7.0, thumb_y, 2.0, thumb_h), Color("7fe3da", 0.75 * fade))

	_draw_footer_bar(rect, fade)


func _draw_header_tabs(fade: float, dy: float, void_level: float) -> void:
	if page == Page.SETTINGS:
		for i: int in SETTINGS_TABS.size():
			var t: Dictionary = SETTINGS_TABS[i]
			var ax: float = float(t["x"])
			var active: bool = i == _settings_tab
			var tab_act: String = "settings_tab_%d" % i
			var hover: bool = _hover_sub == tab_act
			var tab_rect: Rect2 = VineStyle.tab(self, String(t["name"]), Vector2(ax, BRANCH_Y + dy), fade, 3.0 if active else (1.5 if hover else 0.0), void_level * 0.4, _time, i, active, hover, VineStyle.ACCENT_WARM)
			_hitboxes.append({"rect": tab_rect, "action": "settings_tab", "payload": i})
			if active:
				VineStyle.bloom(self, Vector2(ax, BRANCH_Y + dy), fade, _time, void_level * 0.4, VineStyle.ACCENT_WARM)
	else:
		for i: int in MULTI_TABS.size():
			var t: Dictionary = MULTI_TABS[i]
			var ax: float = float(t["x"])
			var tid: String = String(t["id"])
			var active: bool = (tid == "multi" and page == Page.MULTI) or (tid == "join_page" and page == Page.JOIN)
			var tab_act: String = "multi_tab_%s" % tid
			var hover: bool = _hover_sub == tab_act
			var tab_rect: Rect2 = VineStyle.tab(self, String(t["name"]), Vector2(ax, BRANCH_Y + dy), fade, 3.0 if active else (1.5 if hover else 0.0), void_level * 0.4, _time, i, active, hover, Color("7fe3da"))
			_hitboxes.append({"rect": tab_rect, "action": "multi_tab", "payload": tid})
			if active:
				VineStyle.bloom(self, Vector2(ax, BRANCH_Y + dy), fade, _time, void_level * 0.4, Color("7fe3da"))


func _row_height(kind: String) -> float:
	match kind:
		"world_card": return 34.0
		"create_btn": return 20.0
		"action": return 19.0
		"recent": return 15.0
	return 17.0


func _draw_row_widget(idx: int, row: Dictionary, rect: Rect2, fade: float, void_level: float) -> void:
	var id: String = String(row.id)
	var kind: String = String(row.get("kind", ""))
	var label: String = String(row.label)
	var active: bool = idx == _sel
	var editing: bool = _editing_id == id
	var tone: Color = Color("7fe3da") if (page in [Page.MULTI, Page.JOIN]) else VineStyle.ACCENT_WARM
	var outline: Color = Color(VineStyle.OUTLINE, fade)
	var ink: Color = Color(VineStyle.PETAL if (active or editing) else UiStyle.TEXT, fade)

	if kind == "world_card":
		var w: Dictionary = _worlds_cache[int(row.get("index", 0))]
		var wid: String = String(w.get("id", ""))
		draw_rect(rect, Color(VineStyle.OUTLINE, fade))
		draw_rect(rect.grow(-1.0), Color("292347" if active else "1c1733", fade))
		if active:
			draw_rect(Rect2(rect.position.x + 1.0, rect.position.y + 1.0, 2.0, rect.size.y - 2.0), Color("7fe3da", fade))
		_draw_icon(5, Vector2(rect.position.x + 6.0, rect.position.y + 5.0), fade)
		PixelText.draw(self, label, Vector2i(int(rect.position.x + 22.0), int(rect.position.y + 5.0)), Color(VineStyle.PETAL if active else Color("e8e4f4"), fade), outline)
		var day_str: String = "NEUE WELT"
		if bool(w.get("has_save", false)):
			var mins: int = int(float(w.get("time", 0.3)) * 1440.0)
			day_str = "TAG %d · %02d:%02d" % [int(w.get("day", 0)) + 1, mins / 60, mins % 60]
		var info_line: String = "%s · MAX %d" % [day_str, int(w.get("max_players", 4))]
		PixelText.draw(self, info_line, Vector2i(int(rect.position.x + 22.0), int(rect.position.y + 18.0)), Color("8a84ad", fade), outline)

		# Code chip
		var code_str: String = String(w.get("code", "------"))
		var code_w: float = float(PixelText.width(code_str)) + 20.0
		var code_rect: Rect2 = Rect2(rect.end.x - 102.0 - code_w, rect.position.y + 4.0, code_w, 13.0)
		draw_rect(code_rect, Color(VineStyle.OUTLINE, fade))
		draw_rect(code_rect.grow(-1.0), Color("161226", fade))
		_draw_icon(6, Vector2(code_rect.position.x + 2.0, code_rect.position.y), fade)
		PixelText.draw(self, code_str, Vector2i(int(code_rect.position.x + 16.0), int(code_rect.position.y + 3.0)), Color("ffd98a", fade), outline)

		# Action pills inside world card: ÖFFNEN, COPY, DELETE
		var open_r: Rect2 = Rect2(rect.end.x - 96.0, rect.position.y + 4.0, 52.0, 14.0)
		var copy_r: Rect2 = Rect2(rect.end.x - 40.0, rect.position.y + 4.0, 18.0, 14.0)
		var del_r: Rect2 = Rect2(rect.end.x - 20.0, rect.position.y + 4.0, 16.0, 14.0)
		var open_act: String = "world_host:%d" % int(row.get("index", 0))
		var copy_act: String = "world_copy:%d" % int(row.get("index", 0))
		var del_act: String = "world_del:%s" % wid
		VineStyle.plate(self, open_r, "ÖFFNEN", Color("7fe3da") if (_hover_sub == open_act or active) else Color("4a4180"), Color("171329") if _hover_sub == open_act else VineStyle.PETAL, fade, void_level * 0.4)
		draw_rect(copy_r, Color(VineStyle.OUTLINE, fade))
		draw_rect(copy_r.grow(-1.0), Color("2f2854" if _hover_sub == copy_act else "1e1a36", fade))
		_draw_icon(7, Vector2(copy_r.position.x + 3.0, copy_r.position.y + 1.0), fade)
		var armed: bool = _armed_delete_id == wid
		draw_rect(del_r, Color(VineStyle.OUTLINE, fade))
		draw_rect(del_r.grow(-1.0), Color(DANGER if (armed or _hover_sub == del_act) else Color("2b1929"), fade))
		_draw_icon(10, Vector2(del_r.position.x + 2.0, del_r.position.y + 1.0), fade)
		_hitboxes.append({"rect": open_r, "action": open_act})
		_hitboxes.append({"rect": copy_r, "action": copy_act})
		_hitboxes.append({"rect": del_r, "action": del_act})
		return

	if kind == "create_btn":
		if active:
			VineStyle.glow(self, rect.get_center(), 38.0, Color("a6e68f"), 0.28 * fade)
		draw_rect(rect, Color(VineStyle.OUTLINE, fade))
		draw_rect(rect.grow(-1.0), Color("3c6244" if active else "2a4534", fade))
		draw_rect(Rect2(rect.position + Vector2(1.0, 1.0), Vector2(rect.size.x - 2.0, 1.0)), Color("a6e68f" if active else "5d9364", fade))
		var tw: float = float(PixelText.width(label))
		PixelText.draw(self, label, Vector2i(int(rect.position.x + (rect.size.x - tw) * 0.5 + 6.0), int(rect.position.y + 6.0)), Color(VineStyle.PETAL if active else Color("d8f8cc"), fade), outline)
		_draw_icon(11, Vector2(rect.position.x + 8.0, rect.position.y + 4.0), fade)
		return

	if kind == "action":
		var ac_tone: Color = Color("7fe3da") if id in ["join", "create_confirm"] else tone * 0.6
		if active:
			VineStyle.glow(self, rect.get_center(), 36.0, ac_tone, 0.3 * fade)
		VineStyle.plate(self, rect, label, ac_tone if active else ac_tone * 0.5, VineStyle.PETAL if active else UiStyle.TEXT, fade, void_level * 0.4)
		if id == "join":
			_draw_icon(13, Vector2(rect.position.x + 8.0, rect.position.y + 3.0), fade)
		elif id == "create_confirm":
			_draw_icon(4, Vector2(rect.position.x + 8.0, rect.position.y + 3.0), fade)
		return

	if kind == "recent":
		var rh: Dictionary = _recent_cache[int(row.get("index", 0))]
		draw_rect(rect, Color(VineStyle.OUTLINE, 0.85 * fade))
		draw_rect(rect.grow(-1.0), Color("262040" if active else "19152b", 0.9 * fade))
		var rname: String = String(rh.get("label", ""))
		var raddr: String = String(rh.get("address", ""))
		var rcode: String = String(rh.get("code", ""))
		var rx: float = rect.position.x + 8.0
		PixelText.draw(self, rname, Vector2i(int(rx), int(rect.position.y + 4.0)), Color("e8e4f4" if active else "b4aed0", fade), outline)
		rx += float(PixelText.width(rname)) + 10.0
		PixelText.draw(self, raddr, Vector2i(int(rx), int(rect.position.y + 4.0)), Color("7fe3da", fade), outline)
		if not rcode.is_empty():
			var cw: float = float(PixelText.width(rcode))
			PixelText.draw(self, rcode, Vector2i(int(rect.end.x - cw - 8.0), int(rect.position.y + 4.0)), Color("ffd98a", fade), outline)
		return

	# Standard row (slider, toggle, weather, stepper, field)
	if active or editing:
		draw_rect(rect, Color("241f3f", 0.55 * fade))
	PixelText.draw(self, label, Vector2i(int(rect.position.x + 6.0), int(rect.position.y + 5.0)), ink, outline)
	var ctrl_x: float = rect.end.x - SLIDER_W - 28.0
	var mid_y: float = rect.position.y + rect.size.y * 0.5

	match kind:
		"slider":
			_draw_vine_slider(id, Vector2(ctrl_x, mid_y), fade, tone, active or _drag_slider == id)
		"toggle":
			var on: bool = bool(GameSettings.get_value(id))
			_draw_flower_toggle(Vector2(rect.end.x - 42.0, mid_y), on, fade, tone, active)
			var word: String = "AN" if on else "AUS"
			PixelText.draw(self, word, Vector2i(int(rect.end.x - 28.0), int(rect.position.y + 5.0)), Color(Color("a6e68f") if on else Color("8a84ad"), fade), outline)
		"weather":
			var idx_w: int = clampi(int(GameSettings.get_value("weather_fx")), 0, 2)
			var wtxt: String = ["AUS", "REDUZIERT", "VOLL"][idx_w]
			var box: Rect2 = Rect2(rect.end.x - 76.0, rect.position.y + 2.0, 72.0, 13.0)
			VineStyle.plate(self, box, wtxt, tone if active else tone * 0.35, VineStyle.PETAL if active else UiStyle.TEXT, fade, void_level * 0.3)
		"stepper":
			var stxt: String = "%d SPIELER" % _new_world_max
			var box: Rect2 = Rect2(rect.end.x - 76.0, rect.position.y + 2.0, 72.0, 13.0)
			VineStyle.plate(self, box, stxt, tone if active else tone * 0.35, VineStyle.PETAL if active else UiStyle.TEXT, fade, void_level * 0.3)
		"field":
			var box_w: float = 166.0 if id != "new_world_code" else 144.0
			var box: Rect2 = Rect2(rect.end.x - box_w - (22.0 if id == "new_world_code" else 4.0), rect.position.y + 2.0, box_w, 13.0)
			draw_rect(box, outline)
			draw_rect(box.grow(-1.0), Color("161228", fade))
			if editing or active:
				draw_rect(Rect2(box.position.x + 1.0, box.end.y - 2.0, box.size.x - 2.0, 1.0), Color(tone, fade))
			var val: String = _field_value(id)
			var disp: String = val.to_upper()
			PixelText.draw(self, disp, Vector2i(int(box.position.x + 5.0), int(box.position.y + 3.0)), Color(HOT_INK if (editing or active) else Color("ffd98a"), fade), outline)
			if (editing or active) and int(_time * 2.4) % 2 == 0:
				var cx: float = box.position.x + 5.0 + float(PixelText.width(disp)) + 1.0
				draw_rect(Rect2(cx, box.position.y + 2.0, 1.0, 8.0), Color(tone, fade))
			if id == "new_world_code":
				var rr: Rect2 = Rect2(rect.end.x - 20.0, rect.position.y + 2.0, 16.0, 13.0)
				draw_rect(rr, outline)
				draw_rect(rr.grow(-1.0), Color("24304c" if _hover_sub == "reroll_code" else "1a1732", fade))
				_draw_icon(12, Vector2(rr.position.x + 2.0, rr.position.y + 1.0), fade)
				_hitboxes.append({"rect": rr, "action": "reroll_code"})


func _field_value(id: String) -> String:
	match id:
		"addr": return address
		"join_code": return join_code
		"new_world_name": return _new_world_name
		"new_world_code": return _new_world_code
		"new_world_port": return _new_world_port
		"player_name": return _player_name_buf
	return ""


func _draw_vine_slider(id: String, at: Vector2, fade: float, tone: Color, focused: bool) -> void:
	var value: float = float(clampi(int(GameSettings.get_value(id)), 0, 100)) / 100.0
	for x: int in int(SLIDER_W) + 1:
		draw_rect(Rect2(at.x + float(x), at.y, 1.0, 1.0), Color(VineStyle.BARK, fade))
		if x % 4 == 0:
			draw_rect(Rect2(at.x + float(x), at.y + 1.0, 1.0, 1.0), Color(VineStyle.OUTLINE, 0.7 * fade))
	var fill: int = roundi(SLIDER_W * value)
	for x: int in fill + 1:
		var phase: float = fposmod(_time * 30.0 - float(x), 40.0)
		var col: Color = tone.lerp(VineStyle.PETAL, 1.0 - phase / 4.0 if phase < 4.0 else 0.0)
		draw_rect(Rect2(at.x + float(x), at.y - 1.0, 1.0, 2.0), Color(col, fade))
	var bud: Vector2 = Vector2(at.x + float(fill), at.y)
	VineStyle.glow(self, bud, 7.0 + (3.0 if focused else 0.0), tone, (0.75 if focused else 0.45) * fade)
	for o: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_rect(Rect2(bud + o, Vector2.ONE), Color(VineStyle.PETAL, fade))
	draw_rect(Rect2(bud, Vector2.ONE), Color(tone, fade))
	var num: String = str(roundi(value * 100.0))
	PixelText.draw(self, num, Vector2i(int(at.x + SLIDER_W + 8.0), int(at.y - 3.0)), Color(UiStyle.TEXT if focused else UiStyle.TEXT_DIM, fade), Color(VineStyle.OUTLINE, fade))


func _draw_flower_toggle(at: Vector2, on: bool, fade: float, tone: Color, focused: bool) -> void:
	if not on:
		draw_rect(Rect2(at + Vector2(-1, -1), Vector2(3, 4)), Color(VineStyle.BARK_VOID, fade))
		draw_rect(Rect2(at + Vector2(0, -1), Vector2(1, 2)), Color(VineStyle.BARK_LIGHT, fade))
		if focused:
			VineStyle.glow(self, at, 6.0, tone, 0.25 * fade)
		return
	VineStyle.glow(self, at, 8.0, tone, 0.7 * fade)
	for k: int in 6:
		var angle: float = _time * 0.8 + float(k) * TAU / 6.0
		draw_rect(Rect2(roundf(at.x + cos(angle) * 3.0), roundf(at.y + sin(angle) * 3.0), 1.0, 1.0), Color(VineStyle.PETAL, fade))
	draw_rect(Rect2(at + Vector2(-1, -1), Vector2(2, 2)), Color(tone, fade))


func _draw_controls_grid(rect: Rect2, fade: float, void_level: float) -> void:
	var outline: Color = Color(VineStyle.OUTLINE, fade)
	var col_w: float = (rect.size.x - 28.0) * 0.5
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		if String(row.get("kind", "")) != "control":
			continue
		var col: int = i % 2
		var row_idx: int = i / 2
		var x: float = rect.position.x + 14.0 + float(col) * (col_w + 6.0)
		var y: float = rect.position.y + 31.0 + float(row_idx) * 18.0
		var action_name: String = String(row.get("action", ""))
		var use_fallback: bool = action_name.is_empty() or DisplayServer.get_name() == "headless"
		var key_label: String = String(row.get("fallback", "?")) if use_fallback else VineStyle.key_name(action_name, String(row.get("fallback", "?")))
		PixelText.draw(self, String(row.label), Vector2i(int(x), int(y + 3.0)), Color(UiStyle.TEXT, 0.9 * fade), outline)
		var kw: int = VineStyle.cap_width(key_label)
		VineStyle.key_cap(self, Vector2(x + col_w - float(kw) - 4.0, y), key_label, fade, 0.0, void_level * 0.4)


func _draw_confirm_body(rect: Rect2, fade: float) -> void:
	var outline: Color = Color(VineStyle.OUTLINE, fade)
	var lines: PackedStringArray = ["DEIN AKTUELLER SPIELSTAND WIRD BEIM", "NÄCHSTEN SPEICHERN ÜBERSCHRIEBEN."]
	var y: float = rect.position.y + 38.0
	for line: String in lines:
		PixelText.draw(self, line, Vector2i(int(rect.position.x + (rect.size.x - float(PixelText.width(line))) * 0.5), int(y)), Color(UiStyle.TEXT, 0.9 * fade), outline)
		y += 11.0
	y += 10.0
	for i: int in _rows.size():
		var row_rect: Rect2 = Rect2(rect.position.x + 24.0 + float(i) * 150.0, y, 142.0, 20.0)
		_rects[i] = row_rect
		var active: bool = i == _sel
		var tone: Color = DANGER if i == 0 else VineStyle.ACCENT_WARM
		if active:
			VineStyle.glow(self, row_rect.get_center(), 30.0, tone, 0.35 * fade)
		VineStyle.plate(self, row_rect, String(_rows[i].label), tone if active else tone * 0.35, VineStyle.PETAL if active else UiStyle.TEXT, fade, 0.2)


func _draw_footer_bar(rect: Rect2, fade: float) -> void:
	var outline: Color = Color(VineStyle.OUTLINE, fade)
	var bar_y: float = rect.end.y - 24.0
	draw_rect(Rect2(rect.position.x + 12.0, bar_y - 3.0, rect.size.x - 24.0, 1.0), Color("4a4180", 0.45 * fade))

	# Show LAN IP badge on bottom-left of Multiplayer Worlds / Create
	if page == Page.MULTI:
		var ip_str: String = "DEINE IP: %s:%d" % [NetworkManager.primary_ip(), NetworkManager.DEFAULT_PORT]
		var ip_r: Rect2 = Rect2(rect.position.x + 12.0, bar_y + 2.0, float(PixelText.width(ip_str)) + 20.0, 14.0)
		draw_rect(ip_r, Color("1a1630", fade))
		_draw_icon(4, Vector2(ip_r.position.x + 2.0, ip_r.position.y + 1.0), fade)
		PixelText.draw(self, ip_str, Vector2i(int(ip_r.position.x + 16.0), int(ip_r.position.y + 4.0)), Color("b9f3ee" if _hover_sub == "copy_host_ip" else "8a84ad", fade), outline)
		_hitboxes.append({"rect": ip_r, "action": "copy_host_ip"})

	# Status feedback toast if any
	if not status.is_empty():
		var scol: Color = DANGER if _status_is_error else Color("7fe3da")
		var sx: int = int(rect.position.x + 14.0) if page != Page.MULTI else int(rect.position.x + 14.0)
		var sy: int = int(bar_y - 13.0)
		draw_rect(Rect2(float(sx - 3), float(sy - 2), float(PixelText.width(status) + 6), 11.0), Color("161226", 0.92 * fade))
		PixelText.draw(self, status, Vector2i(sx, sy), Color(scol, fade), outline)

	# Draw footer buttons right-aligned inside footer bar
	var right_x: float = rect.end.x - 12.0
	for i: int in range(_rows.size() - 1, -1, -1):
		var row: Dictionary = _rows[i]
		if String(row.get("kind", "")) != "footer":
			continue
		var bw: float = maxf(float(PixelText.width(String(row.label))) + 18.0, 66.0)
		var br: Rect2 = Rect2(right_x - bw, bar_y + 1.0, bw, 16.0)
		_rects[i] = br
		var active: bool = i == _sel
		var tone: Color = Color("7fe3da") if String(row.id) == "join_page" else VineStyle.ACCENT_WARM
		if active:
			VineStyle.glow(self, br.get_center(), 24.0, tone, 0.3 * fade)
		VineStyle.plate(self, br, String(row.label), tone if active else tone * 0.35, VineStyle.PETAL if active else UiStyle.TEXT, fade, 0.25)
		right_x = br.position.x - 8.0


func _page_title() -> String:
	match page:
		Page.CONFIRM_NEW: return "NEUES SPIEL"
		Page.MULTI: return "NEUE KOOP-WELT" if _creating_world else "MEHRSPIELER-WELTEN"
		Page.JOIN: return "WELT BEITRETEN"
		Page.SETTINGS: return "EINSTELLUNGEN"
	return ""


func _draw_icon(frame: int, pos: Vector2, alpha: float = 1.0) -> void:
	if _icons == null:
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2(8, 8)), Color("ffd98a", alpha))
		return
	var src: Rect2 = Rect2(float(frame * 12), 0.0, 12.0, 12.0)
	var dst: Rect2 = Rect2(pos.round(), Vector2(12.0, 12.0))
	draw_texture_rect_region(_icons, dst, src, Color(1.0, 1.0, 1.0, alpha))
	if _icons_glow != null:
		draw_texture_rect_region(_icons_glow, dst, src, Color(1.0, 1.0, 1.0, alpha * 0.85))
