class_name QuestTab
extends Control
## Native Feldcodex 'AUFGABEN' grimoire rebuilt in the MenuChrome obsidian & smoked-vellum aesthetic.
## Features:
##   - Centered top sub-pills: OFFEN | ARCHIV with live counts
##   - Left obsidian ledger: filter pills (ALLE / GESCHICHTE / AUFTRÄGE), interactive quest cards with focus ribbon,
##     and Ellie's pressed Leuchtfarn botanical keepsake niche with drifting ambient spores
##   - Right smoked-vellum chronicle page: embossed crimson/gold wax seal, live zone+distance compass chip,
##     segmented stage progress pips, current objective card, sub-tasks, Ellie's notes, reward chips, and
##     direct actions (FOKUSSIEREN, AUF ATLAS ZEIGEN, 2-click armed AUFGEBEN) with celebratory burst FX.

signal jump_to_atlas(world_tile: Vector2, zone_id: StringName)

const FERN_TEX: Texture2D = preload("res://assets/ui/journal/pressed_fern.png")
const TURN_WAV: AudioStream = preload("res://assets/audio/board/flip.wav")
const PIN_WAV: AudioStream = preload("res://assets/audio/board/tack.wav")

const FILTER_LABELS: Array[String] = ["ALLE", "GESCHICHTE", "AUFTRÄGE"]

var _player: Node = null
var _tracked: TrackedQuests = null
var _archive: bool = false
var _filter: int = 0
var _selected_id: String = ""
var _rows: Array[Dictionary] = []
var _list_scroll: float = 0.0
var _detail_scroll: float = 0.0
var _time: float = 0.0
var _armed_abandon_id: String = ""
var _armed_t: float = 0.0
var _bursts: Array[Dictionary] = []

# Hover & cached hit rects
var _hover_sub: int = -1
var _hover_filter: int = -1
var _hover_row: int = -1
var _hover_action: String = ""
var _sub_rects: Array[Rect2] = []
var _filter_rects: Array[Rect2] = []
var _row_rects: Array[Dictionary] = [] ## {rect, index, id}
var _action_rects: Dictionary = {} ## "focus" | "atlas" | "abandon" -> Rect2
var _left_r: Rect2 = Rect2()
var _right_r: Rect2 = Rect2()
var _detail_max_scroll: float = 0.0
var _list_max_scroll: float = 0.0


func bind(player: Node) -> void:
	_player = player
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if player != null and is_instance_valid(player):
		_tracked = player.get("tracked") as TrackedQuests
		if _tracked != null and not _tracked.changed.is_connected(_refresh_rows):
			_tracked.changed.connect(_refresh_rows)


func on_tab_opened() -> void:
	if _tracked != null:
		_tracked.journal_opened = true
		_archive = _tracked.journal_archive
		_selected_id = _tracked.journal_page
	_armed_abandon_id = ""
	_armed_t = 0.0
	_detail_scroll = 0.0
	_refresh_rows()
	queue_redraw()


func close_embedded() -> void:
	_armed_abandon_id = ""
	_armed_t = 0.0
	_hover_row = -1
	_hover_action = ""


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _armed_t > 0.0:
		_armed_t = maxf(_armed_t - delta, 0.0)
		if _armed_t <= 0.0:
			_armed_abandon_id = ""
	for i: int in range(_bursts.size() - 1, -1, -1):
		_bursts[i]["age"] = float(_bursts[i]["age"]) + delta
		if float(_bursts[i]["age"]) >= float(_bursts[i]["max_age"]):
			_bursts.remove_at(i)
	queue_redraw()


func _refresh_rows() -> void:
	if _tracked == null:
		_rows.clear()
		return
	var focus_id: String = String(_tracked.focused().get("id", ""))
	_rows = _tracked.archive_entries() if _archive else _tracked.entries()
	if not _archive:
		if _filter != 0:
			var want_src: String = "story" if _filter == 1 else "board"
			_rows = _rows.filter(func(e: Dictionary) -> bool: return String(e.get("source", "")) == want_src)
		_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _row_order(a, focus_id) < _row_order(b, focus_id))
	var found_idx: int = -1
	var focus_idx: int = -1
	for i: int in _rows.size():
		var rid: String = String(_rows[i].get("id", ""))
		if rid == _selected_id:
			found_idx = i
		if rid == focus_id:
			focus_idx = i
	if found_idx < 0 and not _rows.is_empty():
		var pick: int = focus_idx if focus_idx >= 0 else 0
		_selected_id = String(_rows[pick].get("id", ""))
	elif _rows.is_empty():
		_selected_id = ""
	_tracked.journal_page = _selected_id
	_tracked.journal_archive = _archive
	queue_redraw()


static func _row_order(row: Dictionary, focus_id: String) -> int:
	if String(row.get("id", "")) == focus_id:
		return -2
	if bool(row.get("ready", false)):
		return -1
	if bool(row.get("urgent", false)):
		return 0
	return int(row.get("due", 1000000))


func _current_row() -> Dictionary:
	for row: Dictionary in _rows:
		if String(row.get("id", "")) == _selected_id:
			return row
	return _rows[0] if not _rows.is_empty() else {}


# --- Input -----------------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var step: float = -22.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 22.0
			if _left_r.has_point(mb.position):
				_list_scroll = clampf(_list_scroll + step, 0.0, _list_max_scroll)
			elif _right_r.has_point(mb.position):
				_detail_scroll = clampf(_detail_scroll + step, 0.0, _detail_max_scroll)
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _rows.is_empty():
		return
	var ke: InputEventKey = event as InputEventKey
	if ke == null or not ke.pressed or ke.echo:
		return
	if ke.keycode == KEY_UP or ke.keycode == KEY_W:
		_step_selection(-1)
		get_viewport().set_input_as_handled()
	elif ke.keycode == KEY_DOWN or ke.keycode == KEY_S:
		_step_selection(1)
		get_viewport().set_input_as_handled()
	elif ke.keycode == KEY_ENTER or ke.keycode == KEY_SPACE:
		if not _archive and not _selected_id.is_empty():
			_toggle_focus()
			get_viewport().set_input_as_handled()


func _step_selection(dir: int) -> void:
	if _rows.is_empty():
		return
	var cur: int = 0
	for i: int in _rows.size():
		if String(_rows[i].get("id", "")) == _selected_id:
			cur = i
			break
	var nxt: int = posmod(cur + dir, _rows.size())
	_selected_id = String(_rows[nxt].get("id", ""))
	if _tracked != null:
		_tracked.journal_page = _selected_id
	_detail_scroll = 0.0
	_armed_abandon_id = ""
	Sfx.ui(self, "ui_click", -6.0)
	queue_redraw()


func _update_hover(mp: Vector2) -> void:
	_hover_sub = -1
	for i: int in _sub_rects.size():
		if _sub_rects[i].has_point(mp):
			_hover_sub = i
			break
	_hover_filter = -1
	for i: int in _filter_rects.size():
		if _filter_rects[i].has_point(mp):
			_hover_filter = i
			break
	_hover_row = -1
	for d: Dictionary in _row_rects:
		if (d["rect"] as Rect2).has_point(mp):
			_hover_row = int(d["index"])
			break
	_hover_action = ""
	for k: String in _action_rects:
		if (_action_rects[k] as Rect2).has_point(mp):
			_hover_action = k
			break


func _handle_click(mp: Vector2) -> void:
	for i: int in _sub_rects.size():
		if _sub_rects[i].has_point(mp):
			var want_arch: bool = (i == 1)
			if want_arch != _archive:
				_archive = want_arch
				_list_scroll = 0.0
				_detail_scroll = 0.0
				_armed_abandon_id = ""
				Sfx.ui_stream(self, TURN_WAV, -10.0)
				_refresh_rows()
			return
	for i: int in _filter_rects.size():
		if _filter_rects[i].has_point(mp):
			if i != _filter:
				_filter = i
				_list_scroll = 0.0
				Sfx.ui(self, "ui_click", -5.0)
				_refresh_rows()
			return
	for d: Dictionary in _row_rects:
		if (d["rect"] as Rect2).has_point(mp):
			var rid: String = String(d["id"])
			if rid != _selected_id:
				_selected_id = rid
				if _tracked != null:
					_tracked.journal_page = rid
				_detail_scroll = 0.0
				_armed_abandon_id = ""
				Sfx.ui(self, "ui_click", -5.0)
				queue_redraw()
			return
	for k: String in _action_rects:
		if not (_action_rects[k] as Rect2).has_point(mp):
			continue
		match k:
			"focus":
				_toggle_focus()
			"atlas":
				_jump_to_quest_atlas()
			"abandon":
				_trigger_abandon()
		return


func _toggle_focus() -> void:
	if _tracked == null or _archive or _selected_id.is_empty():
		return
	var cur_focus: String = String(_tracked.focused().get("id", ""))
	var becoming_focused: bool = (cur_focus != _selected_id)
	_tracked.focus(_selected_id if becoming_focused else "")
	Sfx.ui_stream(self, PIN_WAV, -14.0)
	if becoming_focused and _right_r.has_area():
		_bursts.append({
			"pos": Vector2(_right_r.end.x - 24.0, _right_r.position.y + 22.0),
			"age": 0.0, "max_age": 0.52, "col": MenuChrome.COL_GOLD_HOT,
		})
	_refresh_rows()


func _jump_to_quest_atlas() -> void:
	var row: Dictionary = _current_row()
	if row.is_empty():
		return
	var loc: Vector2 = MapWindow.quest_location(row)
	if loc == Vector2.INF:
		return
	var wt: Vector2 = loc / 16.0
	var zid: StringName = Atlas.shared().zone_at(&"main", loc)
	Sfx.ui(self, "ui_click", -4.0)
	jump_to_atlas.emit(wt, zid)


func _trigger_abandon() -> void:
	var row: Dictionary = _current_row()
	if row.is_empty() or _archive or String(row.get("source", "")) != "board":
		return
	var rid: String = String(row.get("id", ""))
	if _armed_abandon_id != rid:
		_armed_abandon_id = rid
		_armed_t = 3.5
		Sfx.ui(self, "ui_click", -5.0)
		queue_redraw()
		return
	_armed_abandon_id = ""
	_armed_t = 0.0
	var board: BoardManager = _tracked.board() if _tracked != null else null
	if board != null:
		board.request_abandon(int(row.get("oid", 0)), int(row.get("attempt", 0)))
		Sfx.ui(self, "ui_click", -3.0)
	_refresh_rows()


# --- Drawing ---------------------------------------------------------------------------------------------------------

func _draw() -> void:
	if not visible:
		return
	var vw: float = size.x if size.x > 16.0 else 640.0
	var vh: float = size.y if size.y > 16.0 else 306.0
	_draw_sub_bar(vw)

	var top_y: float = 28.0
	var pan_h: float = vh - top_y - 8.0
	var left_w: float = 232.0
	_left_r = Rect2(12.0, top_y, left_w, pan_h)
	_right_r = Rect2(12.0 + left_w + 8.0, top_y, vw - left_w - 32.0, pan_h)

	_draw_left_ledger(_left_r)
	_draw_right_chronicle(_right_r)
	MenuChrome.draw_burst_rings(self, _bursts)


func _draw_sub_bar(vw: float) -> void:
	_sub_rects.clear()
	var open_n: int = _tracked.entries().size() if _tracked != null else 0
	var arch_n: int = _tracked.archive_entries().size() if _tracked != null else 0
	var labels: Array[String] = ["OFFEN · %d" % open_n, "ARCHIV · %d" % arch_n]
	var widths: Array[float] = []
	var total_w: float = 0.0
	for lbl: String in labels:
		var w: float = float(PixelText.width(lbl)) + 22.0
		widths.append(w)
		total_w += w
	total_w += 6.0
	var x: float = roundf((vw - total_w) * 0.5)
	for i: int in labels.size():
		var r: Rect2 = Rect2(x, 4.0, widths[i], 19.0)
		_sub_rects.append(r)
		var active: bool = (_archive == (i == 1))
		MenuChrome.draw_tab_pill(self, r, active, 1.0 if i == _hover_sub else 0.0)
		if active:
			MenuChrome.draw_shimmer(self, r, _time, MenuChrome.COL_GOLD_HOT)
		MenuChrome.draw_text_centered(self, labels[i], r.get_center().x, r.position.y + 6.0, MenuChrome.COL_GOLD_HOT if active else MenuChrome.COL_TEXT_SOFT)
		x += widths[i] + 6.0


func _draw_left_ledger(r: Rect2) -> void:
	_filter_rects.clear()
	_row_rects.clear()
	MenuChrome.draw_slate(self, r)
	MenuChrome.draw_corners(self, r)

	var x: float = r.position.x + 11.0
	var w: float = r.size.x - 22.0
	MenuChrome.draw_text(self, "ELLIES TAGEBUCH", Vector2(x, r.position.y + 9.0), MenuChrome.COL_GOLD)

	var list_top: float = r.position.y + 24.0
	if not _archive:
		# Filter pills row
		var fx: float = x
		for i: int in FILTER_LABELS.size():
			var flbl: String = FILTER_LABELS[i]
			var fw: float = float(PixelText.width(flbl)) + 12.0
			var fr: Rect2 = Rect2(fx, list_top, fw, 14.0)
			_filter_rects.append(fr)
			var on: bool = (i == _filter)
			var hov: bool = (i == _hover_filter)
			MenuChrome.draw_chip(
				self, fr, flbl,
				Color("2b2348") if on else (Color("211b38") if hov else Color("151126")),
				MenuChrome.COL_GOLD if on else (MenuChrome.COL_TEAL if hov else Color("3b3159")),
				MenuChrome.COL_GOLD_HOT if on else (MenuChrome.COL_TEXT if hov else MenuChrome.COL_TEXT_DIM)
			)
			fx += fw + 4.0
		list_top += 20.0

	# Reserve botanical Leuchtfarn keepsake niche at bottom-left when there's room
	var show_fern: bool = (not _archive and _rows.size() <= 4)
	var fern_h: float = 54.0 if show_fern else 0.0
	var list_bot: float = r.end.y - 10.0 - (fern_h + 6.0 if show_fern else 0.0)
	var view_h: float = maxf(list_bot - list_top, 24.0)
	var card_h: float = 28.0
	var gap: float = 4.0
	var total_h: float = float(_rows.size()) * (card_h + gap)
	_list_max_scroll = maxf(total_h - view_h, 0.0)
	_list_scroll = clampf(_list_scroll, 0.0, _list_max_scroll)

	var focus_id: String = String(_tracked.focused().get("id", "")) if _tracked != null else ""

	if _rows.is_empty():
		var empty_box: Rect2 = Rect2(x, list_top + 6.0, w, 46.0)
		MenuChrome.draw_inset(self, empty_box)
		var emsg: String = "DAS ARCHIV IST NOCH LEER." if _archive else "KEINE OFFENEN EINTRÄGE."
		MenuChrome.draw_text_centered(self, emsg, empty_box.get_center().x, empty_box.position.y + 19.0, MenuChrome.COL_TEXT_DIM)
	else:
		var y: float = list_top - _list_scroll
		for i: int in _rows.size():
			var row: Dictionary = _rows[i]
			var cr: Rect2 = Rect2(x, y, w - (6.0 if _list_max_scroll > 1.0 else 0.0), card_h)
			if cr.position.y >= list_top - 1.0 and cr.end.y <= list_bot + 1.0:
				var rid: String = String(row.get("id", ""))
				var sel: bool = (rid == _selected_id)
				var hov: bool = (i == _hover_row)
				var is_focus: bool = (not _archive and rid == focus_id)
				var is_board: bool = String(row.get("source", "")) == "board"
				var ready: bool = bool(row.get("ready", false))
				var acc: Color = MenuChrome.COL_TEAL if ready else (MenuChrome.COL_ROSE if String(row.get("kind", "")) == BoardRules.KILL else (MenuChrome.COL_GOLD if not is_board else MenuChrome.COL_TEAL))

				if sel:
					MenuChrome.draw_gold(self, cr)
				else:
					MenuChrome.draw_inset(self, cr)
					if hov:
						draw_rect(cr.grow(-2.0), Color(MenuChrome.COL_VIOLET.r, MenuChrome.COL_VIOLET.g, MenuChrome.COL_VIOLET.b, 0.14))
				# Left vertical category bar
				draw_rect(Rect2(cr.position.x + 2.0, cr.position.y + 4.0, 2.0, cr.size.y - 8.0), acc)

				var title_raw: String = String(row.get("title", "")).replace("ß", "SS").to_upper()
				var badge_txt: String = ""
				if is_focus:
					badge_txt = "FOKUS"
				elif ready:
					badge_txt = "BEREIT"
				elif _archive:
					badge_txt = _status_short(row)
				elif not is_board and int(row.get("steps", 0)) > 1:
					badge_txt = "%d/%d" % [int(row.get("step", 0)) + 1, int(row.get("steps", 1))]

				var bw: float = float(PixelText.width(badge_txt)) + 10.0 if not badge_txt.is_empty() else 0.0
				MenuChrome.draw_text(self, MenuChrome.fit_text(title_raw, cr.size.x - 16.0 - bw), Vector2(cr.position.x + 8.0, cr.position.y + 6.0), MenuChrome.COL_GOLD_HOT if sel else MenuChrome.COL_TEXT)

				var sub_txt: String = String(row.get("giver_name", row.get("giver", "AUFTRAG"))).to_upper() if is_board else "HAUPTGESCHICHTE"
				MenuChrome.draw_text(self, MenuChrome.fit_text(sub_txt, cr.size.x - 18.0 - bw), Vector2(cr.position.x + 8.0, cr.position.y + 16.0), acc if (ready or is_focus) else MenuChrome.COL_TEXT_DIM)

				if not badge_txt.is_empty():
					var b_fill: Color = Color("342610") if is_focus else (Color("143634") if ready else Color("1d1730"))
					var b_rim: Color = MenuChrome.COL_GOLD if is_focus else (MenuChrome.COL_TEAL if ready else Color("4a3e6b"))
					var b_txt: Color = MenuChrome.COL_GOLD_HOT if is_focus else (MenuChrome.COL_TEAL if ready else MenuChrome.COL_TEXT_SOFT)
					MenuChrome.draw_chip(self, Rect2(cr.end.x - bw - 4.0, cr.position.y + 8.0, bw, 11.0), badge_txt, b_fill, b_rim, b_txt)

				_row_rects.append({"rect": cr, "index": i, "id": rid})
			y += card_h + gap

		if _list_max_scroll > 1.0:
			var sx: float = r.end.x - 7.0
			var sh: float = view_h - 4.0
			draw_rect(Rect2(sx, list_top + 2.0, 2.0, sh), Color("241d3c"))
			var th: float = maxf(sh * (view_h / maxf(total_h, 1.0)), 14.0)
			var ty: float = list_top + 2.0 + (sh - th) * (_list_scroll / _list_max_scroll)
			draw_rect(Rect2(sx, roundf(ty), 2.0, roundf(th)), MenuChrome.COL_GOLD)

	# Botanical Keepsake Niche (Ellie's pressed Leuchtfarn specimen)
	if show_fern:
		var fern_r: Rect2 = Rect2(x, r.end.y - 10.0 - fern_h, w, fern_h)
		MenuChrome.draw_inset(self, fern_r)
		MenuChrome.draw_panel_spores(self, fern_r, _time, 41, MenuChrome.COL_LEAF, 7, 0.85)
		MenuChrome.draw_text(self, "LEUCHTFARN", Vector2(fern_r.position.x + 9.0, fern_r.position.y + 10.0), MenuChrome.COL_LEAF)
		MenuChrome.draw_text(self, "GEPRESST AM WINDKAP", Vector2(fern_r.position.x + 9.0, fern_r.position.y + 21.0), MenuChrome.COL_TEXT_DIM)
		MenuChrome.draw_text(self, "ELLIES ANDENKEN", Vector2(fern_r.position.x + 9.0, fern_r.position.y + 32.0), MenuChrome.COL_TEXT_DIM)
		if FERN_TEX != null:
			var fw_t: float = float(FERN_TEX.get_width())
			var fh_t: float = float(FERN_TEX.get_height())
			var scale_f: float = minf(74.0 / maxf(fw_t, 1.0), 44.0 / maxf(fh_t, 1.0))
			var dw: float = roundf(fw_t * scale_f)
			var dh: float = roundf(fh_t * scale_f)
			draw_texture_rect(FERN_TEX, Rect2(fern_r.end.x - dw - 8.0, fern_r.get_center().y - dh * 0.5, dw, dh), false, Color(0.95, 1.0, 0.96, 0.92))


func _draw_right_chronicle(r: Rect2) -> void:
	_action_rects.clear()
	MenuChrome.draw_parchment(self, r)
	MenuChrome.draw_corners(self, r)
	MenuChrome.draw_panel_spores(self, r, _time, 73, MenuChrome.COL_GOLD, 6, 0.45)

	var row: Dictionary = _current_row()
	var x: float = r.position.x + 14.0
	var w: float = r.size.x - 28.0

	if row.is_empty():
		MenuChrome.draw_wax_seal(self, Vector2(r.get_center().x - 7.0, r.get_center().y - 28.0), 0.75)
		var msg: String = "KEINE ARCHIVIERTEN EINTRÄGE" if _archive else "KEINE AKTIVEN AUFGABEN"
		MenuChrome.draw_text_centered(self, msg, r.get_center().x, r.get_center().y - 4.0, MenuChrome.COL_TEXT_SOFT)
		var sub: String = "SPRICH MIT BEWOHNERN ODER ERKUNDE ALTMARK FÜR NEUE AUFGABEN."
		var sy: float = r.get_center().y + 12.0
		for ln: String in MenuChrome.wrap_lines(sub, w - 30.0):
			MenuChrome.draw_text_centered(self, ln, r.get_center().x, sy, MenuChrome.COL_TEXT_DIM)
			sy += 10.0
		return

	var is_board: bool = String(row.get("source", "")) == "board"
	var ready: bool = bool(row.get("ready", false))
	var focus_id: String = String(_tracked.focused().get("id", "")) if _tracked != null else ""
	var is_focus: bool = (not _archive and String(row.get("id", "")) == focus_id)
	var giver: String = String(row.get("giver_name", row.get("giver", ""))).to_upper()
	var kicker: String = (giver if not giver.is_empty() else "AUFTRAG") if is_board else "HAUPTGESCHICHTE"
	if _archive or ready:
		kicker += " · " + _status_long(row)

	var y: float = r.position.y + 11.0
	# Top Kicker + Wax Seal on top-right
	MenuChrome.draw_text(self, kicker, Vector2(x, y), MenuChrome.COL_TEAL if ready else MenuChrome.COL_GOLD)

	var seal_pos: Vector2 = Vector2(r.end.x - 28.0, r.position.y + 10.0)
	if is_focus or ready:
		var pulse: float = 0.7 + 0.3 * sin(_time * 3.8)
		draw_rect(Rect2(seal_pos - Vector2(2.0, 2.0), Vector2(18.0, 18.0)), Color(MenuChrome.COL_GOLD.r, MenuChrome.COL_GOLD.g, MenuChrome.COL_GOLD.b, 0.16 * pulse))
	MenuChrome.draw_wax_seal(self, seal_pos, 1.0 if (is_focus or ready or not is_board) else 0.72)

	# Large 2x Title
	y += 12.0
	var title_txt: String = String(row.get("title", "")).replace("ß", "SS").to_upper()
	draw_set_transform(Vector2(x, y), 0.0, Vector2(2.0, 2.0))
	PixelText.draw(self, MenuChrome.fit_text(title_txt, (w - 30.0) * 0.5), Vector2i(0, 1), Color(MenuChrome.COL_OUTLINE, 0.85))
	PixelText.draw(self, MenuChrome.fit_text(title_txt, (w - 30.0) * 0.5), Vector2i.ZERO, MenuChrome.COL_GOLD_HOT if is_focus else MenuChrome.COL_TEXT)
	draw_set_transform(Vector2.ZERO)
	y += 19.0

	# Live Zone + Distance Compass Chip & Story Stage Pips
	var loc: Vector2 = MapWindow.quest_location(row)
	var chip_x: float = x
	if loc != Vector2.INF and _player is Node2D:
		var zid: StringName = Atlas.shared().zone_at(&"main", loc)
		var z_obj: Atlas.Zone = Atlas.shared().zone(zid) if zid != &"" else null
		var z_lbl: String = z_obj.name.to_upper() if z_obj != null else "ALTMARK"
		var dist_m: int = roundi((_player as Node2D).global_position.distance_to(loc) / 16.0)
		var d_txt: String = "%s · %d M" % [z_lbl, dist_m]
		var dw: float = float(PixelText.width(d_txt)) + 12.0
		MenuChrome.draw_chip(self, Rect2(chip_x, y, dw, 12.0), d_txt, Color("142c30"), MenuChrome.COL_TEAL, MenuChrome.COL_TEAL)
		chip_x += dw + 5.0
	var steps_tot: int = int(row.get("steps", 0))
	if not is_board and not _archive and steps_tot > 1:
		var step_cur: int = int(row.get("step", 0)) + 1
		var st_txt: String = "ETAPPE %d/%d" % [step_cur, steps_tot]
		var sw: float = float(PixelText.width(st_txt)) + 12.0
		MenuChrome.draw_chip(self, Rect2(chip_x, y, sw, 12.0), st_txt, Color("241c38"), MenuChrome.COL_GOLD, MenuChrome.COL_GOLD_HOT)
		chip_x += sw + 6.0
		# Mini glowing stage pips
		for si: int in mini(steps_tot, 10):
			var done_s: bool = si < step_cur - 1
			var now_s: bool = si == step_cur - 1
			var pc: Color = MenuChrome.COL_TEAL if done_s else (MenuChrome.COL_GOLD_HOT if now_s else Color("413760"))
			draw_rect(Rect2(chip_x + float(si) * 6.0, y + 4.0, 4.0, 4.0), MenuChrome.COL_OUTLINE)
			draw_rect(Rect2(chip_x + float(si) * 6.0 + 1.0, y + 5.0, 2.0, 2.0), pc)
	y += 17.0
	MenuChrome.draw_divider(self, r.get_center().x, y, w)
	y += 11.0

	# Scrollable body region between divider and bottom actions
	var body_top: float = y
	var act_h: float = 26.0 if not _archive else 0.0
	var body_bot: float = r.end.y - 10.0 - act_h
	var body_view: float = maxf(body_bot - body_top, 24.0)

	# Build structured content lines for exact scroll measurement
	var cur_y: float = body_top - _detail_scroll

	# 1. Objective inset card
	var goal_txt: String = String(row.get("text", "")) if not _archive else ""
	if is_board and not _archive and not ready:
		if String(row.get("kind", "")) == BoardRules.FETCH:
			goal_txt = "Sammle die Lieferung für %s." % giver
		elif String(row.get("kind", "")) == BoardRules.KILL:
			goal_txt = "Erfülle den Jagdauftrag von %s." % giver
	if not goal_txt.is_empty():
		var g_lines: Array[String] = MenuChrome.wrap_lines(goal_txt.replace("ß", "SS"), w - 16.0)
		var g_h: float = float(g_lines.size()) * 10.0 + 12.0
		var g_r: Rect2 = Rect2(x, cur_y, w, g_h)
		if g_r.position.y >= body_top - 1.0 and g_r.end.y <= body_bot + 1.0:
			MenuChrome.draw_inset(self, g_r)
			draw_rect(Rect2(g_r.position.x + 2.0, g_r.position.y + 3.0, 2.0, g_r.size.y - 6.0), MenuChrome.COL_TEAL)
			for li: int in g_lines.size():
				MenuChrome.draw_text(self, g_lines[li], Vector2(g_r.position.x + 9.0, g_r.position.y + 6.0 + float(li) * 10.0), MenuChrome.COL_TEXT)
		cur_y += g_h + 7.0

	# 2. Sub-tasks checklist
	var tasks: Array = row.get("tasks", []) as Array
	if not tasks.is_empty():
		for t_v: Variant in tasks:
			if not (t_v is Dictionary):
				continue
			var td: Dictionary = t_v as Dictionary
			var done_t: bool = bool(td.get("done", false))
			var cnt_t: String = "  %d/%d" % [int(td.get("have", 0)), int(td.get("need", 1))] if bool(td.get("counter", false)) else ""
			var t_str: String = (String(td.get("text", "")).replace("ß", "SS") + cnt_t).to_upper()
			if cur_y >= body_top - 1.0 and cur_y + 11.0 <= body_bot + 1.0:
				draw_rect(Rect2(x + 2.0, cur_y + 1.0, 7.0, 7.0), MenuChrome.COL_OUTLINE)
				draw_rect(Rect2(x + 3.0, cur_y + 2.0, 5.0, 5.0), MenuChrome.COL_TEAL if done_t else Color("241d3c"))
				MenuChrome.draw_text(self, MenuChrome.fit_text(t_str, w - 16.0), Vector2(x + 13.0, cur_y + 1.0), MenuChrome.COL_TEAL if done_t else MenuChrome.COL_TEXT_SOFT)
			cur_y += 12.0
		cur_y += 4.0

	# 3. Board Rewards & Deadline chips
	var deadline_txt: String = TrackedQuests.deadline_text(row) if not _archive else ""
	if not deadline_txt.is_empty():
		if cur_y >= body_top - 1.0 and cur_y + 12.0 <= body_bot + 1.0:
			var urg: bool = bool(row.get("urgent", false)) or int(row.get("days_left", -1)) == 1
			MenuChrome.draw_text(self, deadline_txt.to_upper(), Vector2(x, cur_y), MenuChrome.COL_ROSE if urg else MenuChrome.COL_GOLD)
		cur_y += 12.0
	if String(row.get("window", "")) == "night":
		if cur_y >= body_top - 1.0 and cur_y + 12.0 <= body_bot + 1.0:
			MenuChrome.draw_text(self, "FORTSCHRITT ZÄHLT NUR NACHTS", Vector2(x, cur_y), MenuChrome.COL_VIOLET)
		cur_y += 12.0
	if is_board and not _archive and row.get("reward") is Array:
		var rw_arr: Array = row.get("reward", [0, 0, 0]) as Array
		if rw_arr.size() >= 3 and cur_y >= body_top - 1.0 and cur_y + 14.0 <= body_bot + 1.0:
			var chips: Array[Array] = [
				["%d KUPFER" % int(rw_arr[0]), Color("302512"), MenuChrome.COL_GOLD, MenuChrome.COL_GOLD_HOT],
				["%d EP" % int(rw_arr[1]), Color("182d38"), MenuChrome.COL_TEAL, MenuChrome.COL_TEAL],
				["+%d VERTRAUEN" % int(rw_arr[2]), Color("261a3c"), MenuChrome.COL_VIOLET, MenuChrome.COL_VIOLET],
			]
			var cx: float = x
			for ch: Array in chips:
				var clbl: String = String(ch[0])
				var cw: float = float(PixelText.width(clbl)) + 10.0
				MenuChrome.draw_chip(self, Rect2(cx, cur_y, cw, 12.0), clbl, ch[1] as Color, ch[2] as Color, ch[3] as Color)
				cx += cw + 4.0
		cur_y += 16.0

	# 4. Ellie's Journal Observation / Memory notes
	var qid_clean: String = String(row.get("id", "")).trim_prefix("story:")
	var notes_entry: Dictionary = DataRegistry.get_entry("quest_journal", qid_clean) if not is_board else {}
	var obs: String = String(notes_entry.get("finished", "")) if _archive else String((notes_entry.get("steps", {}) as Dictionary).get(String(row.get("step_id", "")), ""))
	if not obs.is_empty():
		var o_lines: Array[String] = MenuChrome.wrap_lines(("\"" + obs + "\"").replace("ß", "SS"), w - 8.0)
		for ln: String in o_lines:
			if cur_y >= body_top - 1.0 and cur_y + 10.0 <= body_bot + 1.0:
				MenuChrome.draw_text(self, ln, Vector2(x + 2.0, cur_y), MenuChrome.COL_GOLD)
			cur_y += 10.0
		cur_y += 4.0

	var mems: Array = row.get("memories", []) as Array
	if not mems.is_empty():
		if cur_y >= body_top - 1.0 and cur_y + 12.0 <= body_bot + 1.0:
			MenuChrome.draw_section_header(self, Vector2(x, cur_y), w, "ZULETZT NOTIERT", MenuChrome.COL_TEAL)
		cur_y += 13.0
		for mv: Variant in mems:
			for ln: String in MenuChrome.wrap_lines(String(mv).replace("ß", "SS"), w - 8.0):
				if cur_y >= body_top - 1.0 and cur_y + 10.0 <= body_bot + 1.0:
					MenuChrome.draw_text(self, ln, Vector2(x + 2.0, cur_y), MenuChrome.COL_TEXT_SOFT)
				cur_y += 10.0
			cur_y += 3.0

	var content_h: float = (cur_y + _detail_scroll) - body_top
	_detail_max_scroll = maxf(content_h - body_view, 0.0)
	_detail_scroll = clampf(_detail_scroll, 0.0, _detail_max_scroll)

	# Bottom Tactile Action Strip (when viewing open quests)
	if not _archive:
		var ay: float = r.end.y - 29.0
		var ax: float = x
		var foc_lbl: String = "FOKUS LÖSEN" if is_focus else "FOKUSSIEREN"
		var foc_w: float = float(PixelText.width(foc_lbl)) + 18.0
		var foc_r: Rect2 = Rect2(ax, ay, foc_w, 19.0)
		MenuChrome.draw_button(self, foc_r, foc_lbl, _hover_action == "focus", not is_focus)
		_action_rects["focus"] = foc_r
		ax += foc_w + 6.0

		if loc != Vector2.INF:
			var map_lbl: String = "AUF ATLAS ZEIGEN"
			var map_w: float = float(PixelText.width(map_lbl)) + 18.0
			var map_r: Rect2 = Rect2(ax, ay, map_w, 19.0)
			MenuChrome.draw_button(self, map_r, map_lbl, _hover_action == "atlas", false)
			_action_rects["atlas"] = map_r
			ax += map_w + 6.0

		if is_board:
			var armed: bool = (_armed_abandon_id == String(row.get("id", "")))
			var ab_lbl: String = "SICHER? AUFGEBEN" if armed else "AUFGEBEN"
			var ab_w: float = float(PixelText.width(ab_lbl)) + 16.0
			var ab_r: Rect2 = Rect2(r.end.x - 14.0 - ab_w, ay, ab_w, 19.0)
			MenuChrome.draw_button(self, ab_r, ab_lbl, _hover_action == "abandon" or armed, false, true)
			_action_rects["abandon"] = ab_r


static func _status_short(row: Dictionary) -> String:
	match String(row.get("status", "")):
		"finished":
			return "ERLEDIGT"
		"expired":
			return "ABGEL."
		"abandoned":
			return "AUFGEG."
	return "OFFEN"


static func _status_long(row: Dictionary) -> String:
	match String(row.get("status", "")):
		"finished":
			return "ABGESCHLOSSEN"
		"expired":
			return "ABGELAUFEN"
		"abandoned":
			return "AUFGEGEBEN"
	return "BEREIT ZUR ABGABE" if bool(row.get("ready", false)) else "OFFEN"
