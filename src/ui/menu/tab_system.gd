class_name SystemTab
extends Control
## Native Feldcodex 'SYSTEM' tab rebuilt from the ground up in the MenuChrome obsidian/gold aesthetic.
## Sub-tabs:
##   0: EINSTELLUNGEN — 2 clean scrollable obsidian cards (AUDIO & GRAFIK | SPIEL & ANZEIGE) with tactile sliders & toggles
##   1: STEUERUNG     — 2 crisp cards with brass/obsidian pixel keycaps for Movement/Combat & Inventory/Feldcodex
##   2: KOOP & SITZUNG — Session status, join code, player name field, title cycler, and live player roster
## Dynamically adapts its width alongside the collapsible right `PauseSocialSidebar` (TAB or '>' toggles).

signal request_close_menu

const SocialSidebarScript := preload("res://src/ui/pause_social_sidebar.gd")
const SUB_LABELS: Array[String] = ["EINSTELLUNGEN", "STEUERUNG", "KOOP & SITZUNG"]

const AUDIO_GFX_ROWS: Array[Dictionary] = [
	{"kind": "section", "label": "AUDIO"},
	{"kind": "slider", "label": "GESAMT", "key": "master"},
	{"kind": "slider", "label": "MUSIK", "key": "music"},
	{"kind": "slider", "label": "EFFEKTE", "key": "sfx"},
	{"kind": "section", "label": "GRAFIK & BILD"},
	{"kind": "toggle", "label": "VOLLBILD", "key": "fullscreen"},
	{"kind": "toggle", "label": "VSYNC", "key": "vsync"},
	{"kind": "cycle", "label": "GRAFIK", "key": "quality"},
	{"kind": "toggle", "label": "ADAPTIVE GRAFIK", "key": "adaptive"},
	{"kind": "cycle", "label": "BILDRATE", "key": "fps_cap"},
	{"kind": "toggle", "label": "PIXEL-AUFLÖSUNG", "key": "pixel_res"},
	{"kind": "slider", "label": "SCHÜTTELN", "key": "shake"},
]

const GAME_ROWS: Array[Dictionary] = [
	{"kind": "section", "label": "ANZEIGE & HUD"},
	{"kind": "toggle", "label": "SCHADENSZAHLEN", "key": "numbers"},
	{"kind": "toggle", "label": "POSITION (DEV)", "key": "position"},
	{"kind": "toggle", "label": "HUD-KONTRAST", "key": "hud_contrast"},
	{"kind": "toggle", "label": "GROSSE SCHRIFT", "key": "hud_big_text"},
	{"kind": "toggle", "label": "ZONEN-TÖNUNG", "key": "hud_tint"},
	{"kind": "slider", "label": "CHAT-SICHTBARKEIT", "key": "chat_opacity", "min": 30, "max": 100},
	{"kind": "toggle", "label": "EIGENER CURSOR", "key": "cursor"},
	{"kind": "section", "label": "ATMOSPHÄRE"},
	{"kind": "cycle", "label": "WETTER-EFFEKTE", "key": "weather_fx"},
	{"kind": "toggle", "label": "BLITZE SANFT", "key": "flash_soft"},
	{"kind": "toggle", "label": "WASSERSPIEGEL", "key": "reflections"},
	{"kind": "toggle", "label": "SONNENSCHATTEN", "key": "sun_shadows"},
	{"kind": "toggle", "label": "TAGEBUCH RUHIG", "key": "journal_still"},
	{"kind": "cycle", "label": "SPIELERTITEL", "key": "player_title"},
]

const SETTING_HINTS: Dictionary = {
	"master": "GESAMTLAUTSTÄRKE ALLER KLÄNGE IM SPIEL",
	"music": "LAUTSTÄRKE DER ATMOSPHÄRISCHEN MUSIK",
	"sfx": "LAUTSTÄRKE VON SCHRITTEN, KAMPF & MENÜ-KLÄNGEN",
	"fullscreen": "WECHSELT ZWISCHEN VOLLBILD UND FENSTERMODUS",
	"vsync": "SYNCHRONISIERT BILDER GEGEN BILDSCHIRMRISSE",
	"quality": "DETAILSTUFE FÜR LICHT, PARTIKEL & EFFEKTE",
	"adaptive": "PASST GRAFIK AUTOMATISCH AN DEINE BILDRATE AN",
	"fps_cap": "MAXIMALE BILDER PRO SEKUNDE BEGRENZEN",
	"pixel_res": "PIXELGENAUE AUFLÖSUNG OHNE SKALIERUNGSFILTER",
	"shake": "STÄRKE VON KAMERASTÖSSEN BEI TREFFERN",
	"numbers": "ZEIGT SCHADENS- & HEILUNGSZAHLEN IM KAMPF",
	"position": "ZEIGT KACHEL-KOORDINATEN UNTER DER UHR",
	"hud_contrast": "ERHÖHT KONTRAST DER ANZEIGEN ÜBER HELLEM BODEN",
	"hud_big_text": "VERGRÖSSERT AUSGEWÄHLTE HUD-EINBLENDUNGEN",
	"hud_tint": "FÄRBT HUD-RANKEN PASSEND ZUR AKTUELLEN ZONE",
	"chat_opacity": "SICHTBARKEIT DES CHAT-HINTERGRUNDS (30 BIS 100 %)",
	"cursor": "NUTZT DEN EIGENEN PIXEL-CURSOR VON SHADOWSPORE",
	"weather_fx": "DICHTE VON REGEN, NEBEL UND WINDSPUREN",
	"flash_soft": "MILDERT BLITZE BEI GEWITTER UND TREFFERN AB",
	"reflections": "SPIEGELUNGEN AUF WASSERFLÄCHEN & BUCHTEN",
	"sun_shadows": "WEICHE SCHATTEN VON BÄUMEN & GEBÄUDEN",
	"journal_still": "DEAKTIVIERT BLÄTTER-ANIMATIONEN IM TAGEBUCH",
	"player_title": "WÄHLT DEINEN ANGEZEIGTEN EHRENTITEL",
}

var _player: Node = null
var _hud: CanvasLayer = null
var _sidebar: PauseSocialSidebar = null
var _sub: int = 0
var _controls_gamepad: bool = false
var _time: float = 0.0
var _scroll: Array[float] = [0.0, 0.0]
var _dirty: bool = false

# Interactive state
var _drag_slider_key: String = ""
var _drag_slider_rect: Rect2 = Rect2()
var _hover_id: String = ""
var _hover_sub: int = -1
var _editing_name: bool = false
var _name_text: String = "ELLIE"
var _armed_action: String = ""
var _armed_t: float = 0.0
var _toast_msg: String = ""
var _toast_t: float = 0.0
var _toast_err: bool = false

# Cached hit rects rebuilt during draw
var _sub_rects: Array[Rect2] = []
var _hits: Array[Dictionary] = [] ## {id, rect, kind, key, arg}
var _left_card_r: Rect2 = Rect2()
var _right_card_r: Rect2 = Rect2()
var _col_max_scroll: Array[float] = [0.0, 0.0]


func bind(player: Node, hud: CanvasLayer = null) -> void:
	_player = player
	_hud = hud
	_name_text = String(GameSettings.get_value("player_name"))
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_sidebar = SocialSidebarScript.new() as PauseSocialSidebar
	_sidebar.name = "SystemSocialSidebar"
	_sidebar.top_inset = 0.0
	_sidebar.bottom_inset = 0.0
	_sidebar.codex_style = true
	_sidebar.request_host_relay.connect(_on_sidebar_host_relay)
	_sidebar.request_join_match.connect(_on_sidebar_join_match)
	add_child(_sidebar)


func show_sub_id(sub_id: String) -> void:
	match sub_id:
		"controls":
			_sub = 1
		"coop":
			_sub = 2
		_:
			_sub = 0
	_scroll = [0.0, 0.0]
	_armed_action = ""
	_editing_name = false
	_drag_slider_key = ""
	if _sidebar != null:
		_sidebar.on_pause_opened(true)
	queue_redraw()


func close_embedded() -> void:
	_editing_name = false
	_drag_slider_key = ""
	_armed_action = ""
	if _dirty:
		GameSettings.save()
		_dirty = false
	if _sidebar != null:
		_sidebar.on_pause_closing()
		_sidebar.visible = false


func is_typing() -> bool:
	return _editing_name or (_sidebar != null and _sidebar.is_typing())


func toggle_sidebar() -> void:
	if _sidebar != null and _sidebar.visible:
		_sidebar.toggle_expanded()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _armed_t > 0.0:
		_armed_t = maxf(_armed_t - delta, 0.0)
		if _armed_t <= 0.0:
			_armed_action = ""
	if _toast_t > 0.0:
		_toast_t = maxf(_toast_t - delta, 0.0)
	if _sidebar != null:
		_sidebar.advance(delta, 1.0, false)
	queue_redraw()


func _avail_width() -> float:
	var vw: float = size.x if size.x > 16.0 else 640.0
	var sb_w: float = _sidebar.occupied_width() if (_sidebar != null and _sidebar.visible) else 0.0
	return maxf(vw - sb_w, 360.0)


# --- Input -----------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var ke: InputEventKey = event as InputEventKey
	if ke == null or not ke.pressed:
		return
	if _sidebar != null and _sidebar.is_typing():
		_sidebar.handle_key_input(ke)
		get_viewport().set_input_as_handled()
		return
	if _editing_name:
		_handle_name_key(ke)
		get_viewport().set_input_as_handled()
		return
	if not ke.echo and ke.physical_keycode == KEY_TAB and _sidebar != null and _sidebar.visible:
		_sidebar.toggle_expanded()
		get_viewport().set_input_as_handled()


func _handle_name_key(ke: InputEventKey) -> void:
	match ke.physical_keycode:
		KEY_ESCAPE:
			_editing_name = false
		KEY_ENTER, KEY_KP_ENTER:
			_apply_player_name()
		KEY_BACKSPACE:
			if not _name_text.is_empty():
				_name_text = _name_text.substr(0, _name_text.length() - 1)
		_:
			var incoming: String = ""
			if ke.ctrl_pressed and ke.physical_keycode == KEY_V:
				incoming = DisplayServer.clipboard_get()
			elif ke.unicode > 0:
				incoming = char(ke.unicode)
			for ch: String in incoming:
				var up: String = ch.to_upper()
				if ((up >= "A" and up <= "Z") or ch in "ÄÖÜäöüß0123456789 -") and _name_text.length() < 18:
					_name_text += up
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = (event as InputEventMouseMotion).position
		if not _drag_slider_key.is_empty():
			_set_slider_from_x(_drag_slider_key, _drag_slider_rect, mp.x)
			accept_event()
			return
		_update_hover(mp)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if not _drag_slider_key.is_empty():
				_drag_slider_key = ""
				if _dirty:
					GameSettings.save()
					_dirty = false
				accept_event()
			return
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var step: float = -24.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 24.0
			if _left_card_r.has_point(mb.position):
				_scroll[0] = clampf(_scroll[0] + step, 0.0, _col_max_scroll[0])
				accept_event()
			elif _right_card_r.has_point(mb.position):
				_scroll[1] = clampf(_scroll[1] + step, 0.0, _col_max_scroll[1])
				accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)
			accept_event()


func _update_hover(mp: Vector2) -> void:
	_hover_sub = -1
	for i: int in _sub_rects.size():
		if _sub_rects[i].has_point(mp):
			_hover_sub = i
			break
	_hover_id = ""
	for h: Dictionary in _hits:
		if (h["rect"] as Rect2).has_point(mp):
			_hover_id = String(h["id"])
			break


func _handle_click(mp: Vector2) -> void:
	_editing_name = false
	if _sidebar != null:
		_sidebar.cancel_typing()
	for i: int in _sub_rects.size():
		if _sub_rects[i].has_point(mp):
			if i != _sub:
				_sub = i
				_scroll = [0.0, 0.0]
				_armed_action = ""
				Sfx.ui(self, "ui_click", -5.0)
				queue_redraw()
			return
	for i: int in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i]
		if not (h["rect"] as Rect2).has_point(mp):
			continue
		var kind: String = String(h["kind"])
		var key: String = String(h.get("key", ""))
		match kind:
			"slider":
				_drag_slider_key = key
				_drag_slider_rect = h["rect"] as Rect2
				_set_slider_from_x(key, _drag_slider_rect, mp.x)
				Sfx.ui(self, "ui_click", -7.0)
			"toggle":
				GameSettings.set_value(key, not bool(GameSettings.get_value(key)))
				GameSettings.save()
				Sfx.ui(self, "ui_click", -5.0)
			"cycle":
				_run_cycle(key)
				Sfx.ui(self, "ui_click", -5.0)
			"name_input":
				_editing_name = true
				Sfx.ui(self, "ui_click", -6.0)
			"action":
				_run_action(String(h.get("arg", "")))
		queue_redraw()
		return


func _slider_bounds(key: String) -> Vector2i:
	if key == "chat_opacity":
		return Vector2i(GameSettings.CHAT_OPACITY_MIN, GameSettings.CHAT_OPACITY_MAX)
	return Vector2i(0, 100)


func _set_slider_from_x(key: String, r: Rect2, mx: float) -> void:
	var bounds: Vector2i = _slider_bounds(key)
	var ratio: float = clampf((mx - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0)
	var span: float = float(maxi(bounds.y - bounds.x, 1))
	var raw_val: float = float(bounds.x) + ratio * span
	var val: int = clampi(roundi(raw_val / 5.0) * 5, bounds.x, bounds.y)
	GameSettings.set_value(key, val)
	_dirty = true


func _run_cycle(key: String) -> void:
	match key:
		"quality", "fps_cap":
			Quality.cycle(key, 1)
			GameSettings.save()
		"weather_fx":
			GameSettings.set_value("weather_fx", (int(GameSettings.get_value("weather_fx")) + 2) % 3)
			GameSettings.save()
		"player_title":
			if _player is Player and (_player as Player).appearance != null:
				var app: AppearanceComponent = (_player as Player).appearance
				if app.unlocked_title_ids().size() > 1:
					app.cycle_title(1)


func _run_action(act: String) -> void:
	match act:
		"save":
			var ok: bool = false
			if CloudSession.is_logged_in() and CloudSession.has_method("save_now"):
				CloudSession.call("save_now")
				ok = true
			elif SaveGame.save(get_tree()):
				ok = true
			_show_toast("WELT GESPEICHERT" if ok else "SPEICHERN NICHT MÖGLICH", not ok)
			Sfx.ui(self, "ui_click", -4.0)
		"main_menu":
			if _armed_action != "main_menu":
				_armed_action = "main_menu"
				_armed_t = 3.5
				Sfx.ui(self, "ui_click", -5.0)
				return
			_armed_action = ""
			if SaveGame.save(get_tree()):
				pass
			request_close_menu.emit()
			GameLauncher.launch(get_tree(), {})
		"quit":
			if _armed_action != "quit":
				_armed_action = "quit"
				_armed_t = 3.5
				Sfx.ui(self, "ui_click", -5.0)
				return
			_armed_action = ""
			if SaveGame.save(get_tree()):
				pass
			CloudSession.graceful_quit()
		"apply_name":
			_apply_player_name()
		"copy_code":
			var code_txt: String = NetworkManager.active_room_code if not NetworkManager.active_room_code.is_empty() else ("%s:%d" % [NetworkManager.primary_ip(), NetworkManager.active_port])
			DisplayServer.clipboard_set(code_txt)
			_show_toast("CODE KOPIERT")
			Sfx.ui(self, "ui_click", -4.0)
		"host_relay":
			_on_sidebar_host_relay()
		"cycle_join_mode":
			var cur: String = NetworkManager.active_join_mode if NetworkManager.is_multiplayer_session() else CloudSession.world_join_mode
			var nxt: String = "ask" if cur == "private" else ("open" if cur == "ask" else "private")
			CloudSession.set_world_join_mode(nxt)
			_show_toast("BEITRITT: %s" % _join_mode_label(nxt))
			Sfx.ui(self, "ui_click", -4.0)
		"toggle_ctrl_mode":
			_controls_gamepad = not _controls_gamepad
			Sfx.ui(self, "ui_click", -5.0)
		"copy_coords":
			if _player is Node2D and is_instance_valid(_player):
				var t: Vector2i = Vector2i(((_player as Node2D).global_position / 16.0).floor())
				DisplayServer.clipboard_set("X %d, Y %d" % [t.x, t.y])
				_show_toast("KOORDINATEN KOPIERT: %d, %d" % [t.x, t.y])
				Sfx.ui(self, "ui_click", -4.0)


func _pause_menu() -> Node:
	if _hud != null:
		return _hud.get_node_or_null("PauseMenu")
	return null


func _on_sidebar_host_relay() -> void:
	if not CloudSession.is_logged_in():
		_show_toast("ÜBER LAUNCHER ANMELDEN", true)
		return
	var pm: Node = _pause_menu()
	if pm != null and pm.has_method("_coop_start_host_relay"):
		pm.call("_coop_start_host_relay")
		_show_toast("KOOP WIRD GEÖFFNET...")
	else:
		_show_toast("KOOP-SITZUNG GESTARTET")


func _on_sidebar_join_match(info: Dictionary) -> void:
	var pm: Node = _pause_menu()
	if pm != null and pm.has_method("_on_sidebar_join_match"):
		request_close_menu.emit()
		pm.call("_on_sidebar_join_match", info)


func _apply_player_name() -> void:
	var clean: String = MultiplayerWorlds.sanitize_name(_name_text, "ELLIE")
	_name_text = clean
	GameSettings.set_value("player_name", clean)
	GameSettings.save()
	NetworkManager.refresh_local_name()
	_editing_name = false
	_show_toast("NAME ÜBERNOMMEN: %s" % clean)
	Sfx.ui(self, "ui_click", -4.0)


func _show_toast(msg: String, err: bool = false) -> void:
	_toast_msg = msg
	_toast_err = err
	_toast_t = 2.6


static func _join_mode_label(mode: String) -> String:
	match mode:
		"private":
			return "PRIVAT"
		"open":
			return "OFFEN"
		_:
			return "AUF ANFRAGE"


# --- Drawing ---------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if not visible:
		return
	_hits.clear()
	var vw: float = size.x if size.x > 16.0 else 640.0
	var vh: float = size.y if size.y > 16.0 else 306.0
	var aw: float = _avail_width()

	_draw_sub_bar(aw)

	var top_y: float = 28.0
	var footer_h: float = 28.0
	var body_h: float = vh - top_y - footer_h - 10.0
	var pad_x: float = 12.0
	var gap: float = 8.0
	var usable_w: float = aw - pad_x * 2.0
	var col_w: float = floorf((usable_w - gap) * 0.5)
	_left_card_r = Rect2(pad_x, top_y, col_w, body_h)
	_right_card_r = Rect2(pad_x + col_w + gap, top_y, usable_w - col_w - gap, body_h)

	match _sub:
		0:
			_draw_settings_col(0, _left_card_r, "AUDIO & GRAFIK", AUDIO_GFX_ROWS)
			_draw_settings_col(1, _right_card_r, "SPIEL & ANZEIGE", GAME_ROWS)
		1:
			_draw_controls_panels(_left_card_r, _right_card_r)
		2:
			_draw_coop_panels(_left_card_r, _right_card_r)

	_draw_bottom_action_bar(Rect2(pad_x, vh - footer_h - 6.0, usable_w, footer_h))


func _draw_sub_bar(aw: float) -> void:
	_sub_rects.clear()
	var widths: Array[float] = []
	var total_w: float = 0.0
	for lbl: String in SUB_LABELS:
		var w: float = float(PixelText.width(lbl)) + 20.0
		widths.append(w)
		total_w += w
	total_w += float(SUB_LABELS.size() - 1) * 5.0
	var x: float = roundf((aw - total_w) * 0.5)
	for i: int in SUB_LABELS.size():
		var r: Rect2 = Rect2(x, 4.0, widths[i], 19.0)
		_sub_rects.append(r)
		var active: bool = (i == _sub)
		MenuChrome.draw_tab_pill(self, r, active, 1.0 if i == _hover_sub else 0.0)
		if active:
			MenuChrome.draw_shimmer(self, r, _time, MenuChrome.COL_GOLD_HOT)
		MenuChrome.draw_text_centered(self, SUB_LABELS[i], r.get_center().x, r.position.y + 6.0, MenuChrome.COL_GOLD_HOT if active else MenuChrome.COL_TEXT_SOFT)
		x += widths[i] + 5.0


# --- Sub 0: EINSTELLUNGEN --------------------------------------------------------------------------------------------

func _draw_settings_col(col_idx: int, card: Rect2, title: String, rows: Array[Dictionary]) -> void:
	MenuChrome.draw_slate(self, card)
	MenuChrome.draw_corners(self, card)
	MenuChrome.draw_text(self, title, card.position + Vector2(11.0, 8.0), MenuChrome.COL_GOLD)

	var clip_top: float = card.position.y + 21.0
	var clip_bot: float = card.end.y - 9.0
	var view_h: float = maxf(clip_bot - clip_top, 20.0)
	var row_h: float = 18.0
	var sec_h: float = 13.0
	var total_h: float = 0.0
	for row: Dictionary in rows:
		total_h += sec_h if String(row["kind"]) == "section" else row_h
	_col_max_scroll[col_idx] = maxf(total_h - view_h, 0.0)
	_scroll[col_idx] = clampf(_scroll[col_idx], 0.0, _col_max_scroll[col_idx])

	if _col_max_scroll[col_idx] > 1.0:
		var arrow: String = "RAD v" if _scroll[col_idx] < _col_max_scroll[col_idx] - 2.0 else "RAD ^"
		MenuChrome.draw_text(self, arrow, Vector2(card.end.x - 11.0 - float(PixelText.width(arrow)), card.position.y + 8.0), MenuChrome.COL_TEXT_DIM)

	var x: float = card.position.x + 11.0
	var w: float = card.size.x - 24.0
	var y: float = clip_top - _scroll[col_idx]

	for idx: int in rows.size():
		var row: Dictionary = rows[idx]
		var kind: String = String(row["kind"])
		var h_this: float = sec_h if kind == "section" else row_h
		if y >= clip_top - 1.0 and y + h_this <= clip_bot + 1.0:
			if kind == "section":
				MenuChrome.draw_section_header(self, Vector2(x, y + 2.0), w, String(row["label"]), MenuChrome.COL_TEAL)
			else:
				var key: String = String(row["key"])
				var lbl: String = String(row["label"])
				var hid: String = "set_%d_%s" % [col_idx, key]
				var hov: bool = (_hover_id == hid)
				var row_r: Rect2 = Rect2(x - 2.0, y, w + 4.0, h_this - 1.0)
				if hov:
					draw_rect(row_r, Color(MenuChrome.COL_VIOLET.r, MenuChrome.COL_VIOLET.g, MenuChrome.COL_VIOLET.b, 0.12))
				MenuChrome.draw_text(self, MenuChrome.fit_text(lbl, w - 82.0), Vector2(x + 1.0, y + 5.0), MenuChrome.COL_TEXT if hov else MenuChrome.COL_TEXT_SOFT)

				if kind == "slider":
					var bounds: Vector2i = _slider_bounds(key)
					var val: int = clampi(int(GameSettings.get_value(key)), bounds.x, bounds.y)
					var ratio: float = float(val - bounds.x) / float(maxi(bounds.y - bounds.x, 1))
					var val_txt: String = "%d%%" % val if key == "chat_opacity" else "%d" % val
					var sl_w: float = clampf(w * 0.34, 50.0, 82.0)
					var sl_r: Rect2 = Rect2(x + w - sl_w - 24.0, y + 2.0, sl_w, 12.0)
					var acc: Color = MenuChrome.COL_TEAL if key == "chat_opacity" else (MenuChrome.COL_GOLD if key != "sfx" else MenuChrome.COL_VIOLET)
					MenuChrome.draw_slider(self, sl_r, ratio, acc, hov or _drag_slider_key == key)
					MenuChrome.draw_text(self, val_txt, Vector2(x + w - float(PixelText.width(val_txt)), y + 5.0), MenuChrome.COL_GOLD_HOT if hov else MenuChrome.COL_TEXT)
					_hits.append({"id": hid, "rect": sl_r.grow(3.0), "kind": "slider", "key": key})
				elif kind == "toggle":
					var on: bool = bool(GameSettings.get_value(key))
					var tog_r: Rect2 = Rect2(x + w - 38.0, y + 2.0, 38.0, 13.0)
					MenuChrome.draw_toggle(self, tog_r, on, hov)
					_hits.append({"id": hid, "rect": row_r, "kind": "toggle", "key": key})
				elif kind == "cycle":
					var val_lbl: String = _cycle_label(key)
					var bw: float = clampf(float(PixelText.width(val_lbl)) + 12.0, 44.0, 96.0)
					var cy_r: Rect2 = Rect2(x + w - bw, y + 2.0, bw, 13.0)
					MenuChrome.draw_button(self, cy_r, MenuChrome.fit_text(val_lbl, bw - 8.0), hov, false)
					_hits.append({"id": hid, "rect": row_r, "kind": "cycle", "key": key})
		y += h_this

	# Crisp thin scrollbar on right edge if scrollable
	if _col_max_scroll[col_idx] > 1.0:
		var sx: float = card.end.x - 6.0
		var sh: float = view_h - 4.0
		draw_rect(Rect2(sx, clip_top + 2.0, 2.0, sh), Color("241d3c"))
		var thumb_h: float = maxf(sh * (view_h / maxf(total_h, 1.0)), 14.0)
		var thumb_y: float = clip_top + 2.0 + (sh - thumb_h) * (_scroll[col_idx] / _col_max_scroll[col_idx])
		draw_rect(Rect2(sx, roundf(thumb_y), 2.0, roundf(thumb_h)), MenuChrome.COL_GOLD)


func _cycle_label(key: String) -> String:
	match key:
		"quality":
			return Quality.label("quality")
		"fps_cap":
			return Quality.label("fps_cap")
		"weather_fx":
			var opts: Array[String] = ["AUS", "REDUZIERT", "VOLL"]
			return opts[clampi(int(GameSettings.get_value("weather_fx")), 0, 2)]
		"player_title":
			if _player is Player and (_player as Player).appearance != null:
				return (_player as Player).appearance.title_label()
			return "KEINER"
	return "-"


# --- Sub 1: STEUERUNG ------------------------------------------------------------------------------------------------

func _draw_controls_panels(left_r: Rect2, right_r: Rect2) -> void:
	_col_max_scroll = [0.0, 0.0]
	var move_rows: Array[Array] = []
	var menu_rows: Array[Array] = []
	if _controls_gamepad:
		move_rows = [
			["BEWEGEN", "L-STICK", []],
			["SPRINTEN", "L3 / LT", []],
			["SCHLEICHEN", "R3", []],
			["SCHATTENSCHRITT", "B", []],
			["ANGRIFF / WERKZEUG", "X / RT", []],
			["NEBENAKTION", "LT", []],
			["INTERAGIEREN", "A", []],
			["HOTBAR WECHSELN", "STEUERKREUZ", []],
		]
		menu_rows = [
			["INVENTAR", "Y / SELECT", []],
			["FELDCODEX", "START", []],
			["ATLAS-KARTE", "SELECT", []],
			["REITER WECHSELN", "LB / RB", []],
			["BESTÄTIGEN", "A", []],
			["ZURÜCK / SCHLIESSEN", "B", []],
		]
	else:
		move_rows = [
			["BEWEGEN", "WASD", [KEY_W, KEY_A, KEY_S, KEY_D]],
			["SPRINTEN", "UMSCHALT", [KEY_SHIFT]],
			["SCHLEICHEN", "STRG / C", [KEY_CTRL, KEY_C]],
			["SCHATTENSCHRITT", VineStyle.key_name("shadow_step", "ALT"), [KEY_ALT]],
			["ANGRIFF / WERKZEUG", "L-KLICK", []],
			["NEBENAKTION", "R-KLICK", []],
			["INTERAGIEREN", VineStyle.key_name("interact", "E"), [KEY_E]],
			["HOTBAR-PLÄTZE", "1 - 8", [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]],
		]
		menu_rows = [
			["INVENTAR", VineStyle.key_name("inventory", "I"), [KEY_I]],
			["FELDCODEX", "TAB", [KEY_TAB]],
			["ATLAS-KARTE", VineStyle.key_name("map", "M"), [KEY_M]],
			["AUFGABENBUCH", VineStyle.key_name("quest_journal", "J"), [KEY_J]],
			["TALENTE / STUFEN", "%s / %s" % [VineStyle.key_name("skills", "F"), VineStyle.key_name("progress", "P")], [KEY_F, KEY_P]],
			["FLUSSBUCH", VineStyle.key_name("fish_book", "N"), [KEY_N]],
			["REITER WECHSELN", "Q / E", [KEY_Q, KEY_E]],
			["SYSTEM / ZURÜCK", "ESC", [KEY_ESCAPE]],
		]
	_draw_key_card(left_r, "BEWEGUNG & KAMPF", move_rows, MenuChrome.COL_TEAL, false)
	_draw_key_card(right_r, "INVENTAR & FELDCODEX", menu_rows, MenuChrome.COL_GOLD, true)


func _draw_key_card(card: Rect2, title: String, rows: Array[Array], accent: Color, show_mode_toggle: bool) -> void:
	MenuChrome.draw_slate(self, card)
	MenuChrome.draw_corners(self, card)
	var x: float = card.position.x + 11.0
	var w: float = card.size.x - 22.0
	var mode_w: float = 0.0
	if show_mode_toggle:
		var mlbl: String = "GAMEPAD" if _controls_gamepad else "TASTATUR"
		mode_w = float(PixelText.width(mlbl)) + 14.0
		var mr: Rect2 = Rect2(card.end.x - 11.0 - mode_w, card.position.y + 6.0, mode_w, 13.0)
		MenuChrome.draw_chip(self, mr, mlbl, Color("19363a") if _controls_gamepad else Color("271f3e"), MenuChrome.COL_TEAL if _controls_gamepad else MenuChrome.COL_GOLD, MenuChrome.COL_TEAL if _controls_gamepad else MenuChrome.COL_GOLD_HOT)
		_hits.append({"id": "act_ctrl_mode", "rect": mr, "kind": "action", "arg": "toggle_ctrl_mode"})
	MenuChrome.draw_section_header(self, card.position + Vector2(11.0, 9.0), w - (mode_w + 6.0 if show_mode_toggle else 0.0), title, accent)
	var y: float = card.position.y + 27.0
	for r: Array in rows:
		var lbl: String = String(r[0])
		var ktxt: String = String(r[1])
		var keys_chk: Array = r[2] as Array
		var is_lit: bool = false
		for kc: Variant in keys_chk:
			if Input.is_physical_key_pressed(int(kc) as Key):
				is_lit = true
				break
		var kw: float = maxf(float(PixelText.width(ktxt)) + 8.0, 18.0)
		MenuChrome.draw_text(self, MenuChrome.fit_text(lbl, w - kw - 8.0), Vector2(x, y + 3.0), MenuChrome.COL_GOLD_HOT if is_lit else MenuChrome.COL_TEXT_SOFT)
		MenuChrome.draw_keycap(self, Vector2(x + w - kw, y), ktxt, 1.0, is_lit)
		y += 22.0


# --- Sub 2: KOOP & SITZUNG -------------------------------------------------------------------------------------------

func _draw_coop_panels(left_r: Rect2, right_r: Rect2) -> void:
	_col_max_scroll = [0.0, 0.0]
	var in_coop: bool = NetworkManager.is_multiplayer_session()
	var logged_in: bool = CloudSession.is_logged_in()
	var jmode: String = NetworkManager.active_join_mode if in_coop else CloudSession.world_join_mode

	# Left Panel: Sitzung & Online-Koop
	MenuChrome.draw_slate(self, left_r)
	MenuChrome.draw_corners(self, left_r)
	var lx: float = left_r.position.x + 11.0
	var lw: float = left_r.size.x - 22.0
	var ly: float = left_r.position.y + 10.0

	if not in_coop:
		MenuChrome.draw_section_header(self, Vector2(lx, ly), lw, "ONLINE-KOOP" if logged_in else "EINZELSPIELER", MenuChrome.COL_GOLD)
		ly += 16.0
		if logged_in:
			MenuChrome.draw_text(self, "DEINE UID", Vector2(lx, ly), MenuChrome.COL_TEXT_DIM)
			var uid_s: String = "#%s" % (CloudSession.uid if not CloudSession.uid.is_empty() else "---")
			MenuChrome.draw_text(self, uid_s, Vector2(lx + lw - float(PixelText.width(uid_s)), ly), MenuChrome.COL_TEAL)
			ly += 16.0
			var jm_r: Rect2 = Rect2(lx, ly, lw, 19.0)
			MenuChrome.draw_button(self, jm_r, "BEITRITT: %s" % _join_mode_label(jmode), _hover_id == "act_jmode")
			_hits.append({"id": "act_jmode", "rect": jm_r, "kind": "action", "arg": "cycle_join_mode"})
			ly += 24.0
			var hr_r: Rect2 = Rect2(lx, ly, lw, 21.0)
			MenuChrome.draw_button(self, hr_r, "WELT FÜR KOOP ÖFFNEN", _hover_id == "act_host", true)
			_hits.append({"id": "act_host", "rect": hr_r, "kind": "action", "arg": "host_relay"})
		else:
			var info_r: Rect2 = Rect2(lx, ly, lw, 58.0)
			MenuChrome.draw_inset(self, info_r)
			var iy: float = info_r.position.y + 8.0
			for line: String in MenuChrome.wrap_lines("AKTUELL LOKALE EINZELSPIELER-SITZUNG. STARTE ÜBER DEN LAUNCHER FÜR FREUNDE & ONLINE-KOOP.", lw - 14.0):
				MenuChrome.draw_text(self, line, Vector2(info_r.position.x + 7.0, iy), MenuChrome.COL_TEXT_SOFT)
				iy += 10.0
			ly += 66.0
			MenuChrome.draw_section_header(self, Vector2(lx, ly), lw, "WELT-STATUS", MenuChrome.COL_TEAL)
			ly += 15.0
			var z_nm: String = "ALTMARK"
			var coord_s: String = "---"
			if _player is Node2D and is_instance_valid(_player):
				var zid: StringName = Atlas.shared().zone_at(&"main", (_player as Node2D).global_position)
				var zo: Atlas.Zone = Atlas.shared().zone(zid) if zid != &"" else null
				if zo != null:
					z_nm = zo.name.to_upper()
				var tp: Vector2i = Vector2i(((_player as Node2D).global_position / 16.0).floor())
				coord_s = "X %d · Y %d" % [tp.x, tp.y]
			for srow: Array in [["ZONE", z_nm], ["TAG", "TAG %d" % (TimeManager.day + 1)], ["POSITION", coord_s]]:
				MenuChrome.draw_text(self, String(srow[0]), Vector2(lx, ly), MenuChrome.COL_TEXT_DIM)
				var sv: String = String(srow[1])
				MenuChrome.draw_text(self, sv, Vector2(lx + lw - float(PixelText.width(sv)), ly), MenuChrome.COL_TEXT)
				ly += 14.0
			ly += 6.0
			var cc_r: Rect2 = Rect2(lx, ly, lw, 18.0)
			MenuChrome.draw_button(self, cc_r, "KOORDINATEN KOPIEREN", _hover_id == "act_coords")
			_hits.append({"id": "act_coords", "rect": cc_r, "kind": "action", "arg": "copy_coords"})
	else:
		MenuChrome.draw_section_header(self, Vector2(lx, ly), lw, MenuChrome.fit_text(NetworkManager.active_world_name, lw), MenuChrome.COL_TEAL)
		ly += 16.0
		var code_s: String = NetworkManager.active_room_code if not NetworkManager.active_room_code.is_empty() else "OFFEN"
		MenuChrome.draw_text(self, "JOIN-CODE", Vector2(lx, ly), MenuChrome.COL_TEXT_DIM)
		MenuChrome.draw_text(self, code_s, Vector2(lx + lw - float(PixelText.width(code_s)), ly), MenuChrome.COL_GOLD_HOT)
		ly += 16.0
		var cp_r: Rect2 = Rect2(lx, ly, lw, 19.0)
		MenuChrome.draw_button(self, cp_r, "CODE KOPIEREN", _hover_id == "act_copy", true)
		_hits.append({"id": "act_copy", "rect": cp_r, "kind": "action", "arg": "copy_code"})
		ly += 24.0
		if multiplayer.is_server() and logged_in:
			var jm2: Rect2 = Rect2(lx, ly, lw, 19.0)
			MenuChrome.draw_button(self, jm2, "BEITRITT: %s" % _join_mode_label(jmode), _hover_id == "act_jmode")
			_hits.append({"id": "act_jmode", "rect": jm2, "kind": "action", "arg": "cycle_join_mode"})

	# Right Panel: Spielername, Titel & Kader
	MenuChrome.draw_slate(self, right_r)
	MenuChrome.draw_corners(self, right_r)
	var rx: float = right_r.position.x + 11.0
	var rw: float = right_r.size.x - 22.0
	var ry: float = right_r.position.y + 10.0

	MenuChrome.draw_section_header(self, Vector2(rx, ry), rw, "IDENTITÄT", MenuChrome.COL_GOLD)
	ry += 15.0
	MenuChrome.draw_text(self, "SPIELERNAME", Vector2(rx, ry), MenuChrome.COL_TEXT_DIM)
	ry += 11.0
	var inp_r: Rect2 = Rect2(rx, ry, rw, 18.0)
	MenuChrome.draw_inset(self, inp_r)
	if _editing_name:
		draw_rect(Rect2(inp_r.position.x + 2.0, inp_r.end.y - 2.0, inp_r.size.x - 4.0, 1.0), MenuChrome.COL_TEAL)
	var shown_n: String = _name_text if not _name_text.is_empty() else "ELLIE"
	MenuChrome.draw_text(self, MenuChrome.fit_text(shown_n, rw - 14.0), Vector2(inp_r.position.x + 6.0, inp_r.position.y + 5.0), MenuChrome.COL_TEXT)
	if _editing_name and int(_time * 2.2) % 2 == 0:
		var cx_n: float = minf(inp_r.position.x + 7.0 + float(PixelText.width(_name_text)), inp_r.end.x - 5.0)
		draw_rect(Rect2(cx_n, inp_r.position.y + 4.0, 1.0, 9.0), MenuChrome.COL_TEAL)
	_hits.append({"id": "name_input", "rect": inp_r, "kind": "name_input"})
	ry += 22.0

	var app_btn: Rect2 = Rect2(rx, ry, rw, 18.0)
	MenuChrome.draw_button(self, app_btn, "NAME ÜBERNEHMEN", _hover_id == "act_apply_name", _editing_name)
	_hits.append({"id": "act_apply_name", "rect": app_btn, "kind": "action", "arg": "apply_name"})
	ry += 24.0

	if _player is Player and (_player as Player).appearance != null:
		MenuChrome.draw_text(self, "TITEL", Vector2(rx, ry + 3.0), MenuChrome.COL_TEXT_DIM)
		var tl: String = (_player as Player).appearance.title_label()
		var tw_b: float = clampf(float(PixelText.width(tl)) + 14.0, 56.0, rw - 42.0)
		var tr_b: Rect2 = Rect2(rx + rw - tw_b, ry, tw_b, 15.0)
		MenuChrome.draw_button(self, tr_b, MenuChrome.fit_text(tl, tw_b - 8.0), _hover_id == "cyc_title")
		_hits.append({"id": "cyc_title", "rect": tr_b, "kind": "cycle", "key": "player_title"})
		ry += 22.0

	# Roster
	var crew: Array[Dictionary] = NetworkManager.roster()
	MenuChrome.draw_section_header(self, Vector2(rx, ry), rw, "KADER %d/%d" % [maxi(crew.size(), 1), NetworkManager.active_max_players], MenuChrome.COL_TEAL)
	ry += 14.0
	if crew.is_empty():
		MenuChrome.draw_text(self, _name_text, Vector2(rx, ry), MenuChrome.COL_TEXT)
		MenuChrome.draw_chip(self, Rect2(rx + rw - 34.0, ry - 1.0, 34.0, 11.0), "HOST", Color("153835"), MenuChrome.COL_TEAL, MenuChrome.COL_TEAL)
	else:
		for entry: Dictionary in crew:
			if ry + 14.0 > right_r.end.y - 6.0:
				break
			var is_h: bool = bool(entry.get("is_host", false))
			var pname: String = MenuChrome.fit_text(String(entry.get("name", "SPIELER")), rw - 46.0)
			MenuChrome.draw_text(self, pname, Vector2(rx, ry), MenuChrome.COL_TEXT)
			MenuChrome.draw_chip(self, Rect2(rx + rw - 38.0, ry - 1.0, 38.0, 11.0), "HOST" if is_h else "ONLINE", Color("153835") if is_h else Color("1d1730"), MenuChrome.COL_TEAL if is_h else MenuChrome.COL_VIOLET, MenuChrome.COL_TEAL if is_h else MenuChrome.COL_TEXT_SOFT)
			ry += 15.0


# --- Bottom Action Bar -----------------------------------------------------------------------------------------------

func _draw_bottom_action_bar(bar: Rect2) -> void:
	MenuChrome.draw_inset(self, bar)

	# Left contextual setting tooltip / save status / toast
	var st_col: Color = MenuChrome.COL_TEXT_DIM
	var st_txt: String = "TAG %d · BEREIT" % (TimeManager.day + 1)
	if _toast_t > 0.0 and not _toast_msg.is_empty():
		st_txt = _toast_msg
		st_col = Color("ff8a96") if _toast_err else MenuChrome.COL_TEAL
	elif _sub == 0 and _hover_id.begins_with("set_"):
		var parts: PackedStringArray = _hover_id.split("_", false, 2)
		if parts.size() >= 3 and SETTING_HINTS.has(parts[2]):
			st_txt = String(SETTING_HINTS[parts[2]])
			st_col = MenuChrome.COL_TEAL
	elif _sub == 1:
		st_txt = "DRÜCKE EINE TASTE ZUM TESTEN" if not _controls_gamepad else "GAMEPAD-LAYOUT · KLICK OBEN ZUM WECHSELN"
		st_col = MenuChrome.COL_TEXT_SOFT
	else:
		var info: Dictionary = SaveGame.info()
		if not info.is_empty():
			st_txt = "GESPEICHERT: TAG %d" % (int(info.get("day", TimeManager.day)) + 1)
	var by: float = bar.position.y + 5.0
	var bh: float = bar.size.y - 10.0

	# Right action buttons: SPEICHERN | HAUPTMENÜ | BEENDEN
	var bx: float = bar.end.x - 6.0
	var quit_lbl: String = "SICHER?" if _armed_action == "quit" else "BEENDEN"
	var qw: float = float(PixelText.width(quit_lbl)) + 16.0
	var qr: Rect2 = Rect2(bx - qw, by, qw, bh)
	MenuChrome.draw_button(self, qr, quit_lbl, _hover_id == "act_quit", false, true)
	_hits.append({"id": "act_quit", "rect": qr, "kind": "action", "arg": "quit"})
	bx = qr.position.x - 5.0

	var menu_lbl: String = "SICHER?" if _armed_action == "main_menu" else "HAUPTMENÜ"
	var mw: float = float(PixelText.width(menu_lbl)) + 16.0
	var mr: Rect2 = Rect2(bx - mw, by, mw, bh)
	MenuChrome.draw_button(self, mr, menu_lbl, _hover_id == "act_menu", false, _armed_action == "main_menu")
	_hits.append({"id": "act_menu", "rect": mr, "kind": "action", "arg": "main_menu"})
	bx = mr.position.x - 5.0

	if multiplayer.is_server():
		var save_lbl: String = "SPEICHERN"
		var sw: float = float(PixelText.width(save_lbl)) + 16.0
		var sr: Rect2 = Rect2(bx - sw, by, sw, bh)
		MenuChrome.draw_button(self, sr, save_lbl, _hover_id == "act_save", true)
		_hits.append({"id": "act_save", "rect": sr, "kind": "action", "arg": "save"})
		bx = sr.position.x - 8.0

	var max_st_w: float = maxf(bx - (bar.position.x + 8.0), 40.0)
	MenuChrome.draw_text(self, MenuChrome.fit_text(st_txt, max_st_w), Vector2(bar.position.x + 8.0, bar.position.y + 10.0), st_col)
