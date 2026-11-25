class_name DungeonWindow
extends Control
## Fullscreen "Steinsetzer-Prüfungstafel" (docs/dungeon_konzept.md Section 5.1).
## Opened by pressing G (remote overview: records, resonance, Echo Exchange, "WEG ZEIGEN / WEGSTEIN")
## or by pressing E at a physical DungeonEntrance (direct Solo / Coop Ready-Check launch).

const BG_OUTER: Color = Color(0.03, 0.04, 0.08, 0.86)
const SLATE_DEEP: Color = Color("0e1320")
const SLATE_MID: Color = Color("172034")
const SLATE_CARD: Color = Color("1f2b42")
const SLATE_HOVER: Color = Color("283854")
const SLATE_SEL: Color = Color("223a4c")
const INK: Color = Color("05070e")
const RIM_STONE: Color = Color("3a4d6b")
const TEAL: Color = Color("4df2e0")
const TEAL_DIM: Color = Color("277c7e")
const GOLD: Color = Color("ffd98a")
const GOLD_DEEP: Color = Color("99742a")
const TEXT: Color = Color("e8f2f7")
const MUTED: Color = Color("8295b0")
const DANGER: Color = Color("ff5c7a")
const OK_GREEN: Color = Color("8ee69c")

const FRAME_PAD_X: float = 18.0
const FRAME_PAD_Y: float = 12.0
const LIST_W: float = 192.0
const ROW_H: float = 34.0

var _player: Player = null
var _manager: DungeonManager = null
var _at_gate: bool = false
var _gate_dungeon_id: String = ""
var _selected_id: String = "suedkap_gezeitenkammern"
var _tab: int = 0 ## 0 = PRÜFUNGEN, 1 = ECHOTAUSCH
var _list_scroll: float = 0.0
var _ex_scroll: float = 0.0
var _open_t: float = 0.0
var _time: float = 0.0
var _mouse: Vector2 = Vector2.ZERO
var _toast_text: String = ""
var _toast_color: Color = TEAL
var _toast_left: float = 0.0

## Clickable hitboxes rebuilt in _draw
var _tab_trials_rect: Rect2 = Rect2()
var _tab_exchange_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _row_rects: Array[Dictionary] = [] ## {rect: Rect2, id: String}
var _res_toggle_rect: Rect2 = Rect2()
var _btn_solo_rect: Rect2 = Rect2()
var _btn_coop_rect: Rect2 = Rect2()
var _btn_route_rect: Rect2 = Rect2()
var _exchange_btn_rects: Array[Dictionary] = [] ## {rect: Rect2, offer_id: String, enabled: bool}
var _preview_item_rects: Array[Dictionary] = [] ## {rect: Rect2, item_id: String}

var _icon_cache: Dictionary = {}
var _banner_cache: Dictionary = {}


func bind(player: Player) -> void:
	_player = player
	if _player != null and _player.dungeons != null:
		if not _player.dungeons.changed.is_connected(_on_profile_changed):
			_player.dungeons.changed.connect(_on_profile_changed)
		if not _player.dungeons.exchange_result.is_connected(_on_exchange_result):
			_player.dungeons.exchange_result.connect(_on_exchange_result)
	_hook_manager.call_deferred()


func _ready() -> void:
	name = "DungeonWindow"
	add_to_group("dungeon_window")
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _hook_manager() -> void:
	_manager = DungeonManager.of(get_tree())
	if _manager != null and not _manager.gate_window_requested.is_connected(_on_gate_requested):
		_manager.gate_window_requested.connect(_on_gate_requested)


func _on_gate_requested(dungeon_id: String, at_gate: bool) -> void:
	open_window(dungeon_id, at_gate)


func _on_profile_changed() -> void:
	if visible:
		queue_redraw()


func _on_exchange_result(ok: bool, msg: String, item_id: String, count: int) -> void:
	if ok:
		var idef: Dictionary = DataRegistry.table("items").get(item_id, {}) as Dictionary
		var iname: String = String(idef.get("name", item_id)).to_upper()
		_show_toast("ERHALTEN: %dx %s" % [count, iname], OK_GREEN)
		Sfx.ui(self, "coin_pickup", -2.0)
	else:
		_show_toast(msg, DANGER)
		Sfx.ui(self, "ui/deny", -3.0)
	queue_redraw()


func _show_toast(msg: String, col: Color) -> void:
	_toast_text = msg
	_toast_color = col
	_toast_left = 2.8


func is_open() -> bool:
	return visible


func open_window(focus_dungeon_id: String = "", at_gate: bool = false) -> void:
	if _player == null or _player.intro != null or _player.story_lock or _player.health.current <= 0.0:
		return
	if InputManager.menu_open or InputManager.chat_open:
		return
	_close_conflicting_windows()
	_at_gate = at_gate
	_gate_dungeon_id = focus_dungeon_id if at_gate else ""
	if not focus_dungeon_id.is_empty():
		_selected_id = focus_dungeon_id
		_tab = 0
	elif _selected_id.is_empty():
		var all_d: Array[Dictionary] = DungeonRules.all()
		if not all_d.is_empty():
			_selected_id = String(all_d[0].get("id", ""))
	if _player.dungeons != null:
		_player.dungeons.refresh_clock()
	_open_t = 0.0
	visible = true
	InputManager.dungeons_open = true
	Sfx.ui(self, "skills/reveal", -5.0)
	queue_redraw()


func close_window() -> void:
	if not visible:
		return
	visible = false
	_at_gate = false
	_gate_dungeon_id = ""
	InputManager.dungeons_open = false


func _close_conflicting_windows() -> void:
	var hud: Node = get_parent()
	if hud == null:
		return
	for wn: String in ["MapWindow", "SkillTreeWindow", "ProgressWindow", "QuestJournal", "InventoryWindow"]:
		var node: Node = hud.get_node_or_null(wn)
		if node != null and node.visible:
			if node.has_method("close_window"):
				node.call("close_window")
			elif node.has_method("close"):
				node.call("close")
			else:
				node.visible = false
	InputManager.map_open = false
	InputManager.skills_open = false
	InputManager.progress_open = false
	InputManager.journal_open = false
	InputManager.inventory_open = false


func _process(delta: float) -> void:
	_time += delta
	if _toast_left > 0.0:
		_toast_left = maxf(_toast_left - delta, 0.0)
	if InputManager.dungeons_pressed():
		if visible:
			close_window()
		elif not InputManager.menu_open and not InputManager.ui_blocking:
			open_window("", false)
	if not visible:
		return
	_open_t = minf(_open_t + delta * 4.5, 1.0)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_window()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				if _tab == 0:
					_list_scroll = maxf(_list_scroll - 28.0, 0.0)
				else:
					_ex_scroll = maxf(_ex_scroll - 34.0, 0.0)
				queue_redraw()
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if _tab == 0:
					var max_s: float = maxf(float(DungeonRules.all().size()) * (ROW_H + 3.0) - 240.0, 0.0)
					_list_scroll = minf(_list_scroll + 28.0, max_s)
				else:
					var rows_ex: int = ceili(float(DungeonRules.exchange_offers().size()) / 2.0)
					var max_ex: float = maxf(float(rows_ex) * 58.0 - 210.0, 0.0)
					_ex_scroll = minf(_ex_scroll + 34.0, max_ex)
				queue_redraw()
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_handle_click(mb.position)
				accept_event()


func _handle_click(pos: Vector2) -> void:
	if _close_rect.has_point(pos):
		close_window()
		return
	if _tab_trials_rect.has_point(pos):
		_tab = 0
		queue_redraw()
		return
	if _tab_exchange_rect.has_point(pos):
		_tab = 1
		queue_redraw()
		return
	if _tab == 0:
		for entry: Dictionary in _row_rects:
			if (entry["rect"] as Rect2).has_point(pos):
				_selected_id = String(entry["id"])
				queue_redraw()
				return
		if _res_toggle_rect.has_point(pos) and _player != null and _player.dungeons != null:
			_player.dungeons.prefer_resonance = not _player.dungeons.prefer_resonance
			queue_redraw()
			return
		var can_launch_here: bool = _at_gate and _selected_id == _gate_dungeon_id
		if can_launch_here:
			if _btn_solo_rect.has_point(pos):
				_try_launch(false)
				return
			if _btn_coop_rect.has_point(pos):
				_try_launch(true)
				return
		else:
			if _btn_route_rect.has_point(pos):
				_jump_or_show_route()
				return
	else:
		for ex: Dictionary in _exchange_btn_rects:
			if bool(ex["enabled"]) and (ex["rect"] as Rect2).has_point(pos):
				if _player != null and _player.dungeons != null:
					_player.dungeons.request_exchange(String(ex["offer_id"]))
				return


func _try_launch(coop: bool) -> void:
	if _player == null or _manager == null:
		return
	var def: Dictionary = DungeonRules.by_id(_selected_id)
	var chk: Dictionary = DungeonRules.can_enter(_player.progress.level, def)
	if not bool(chk.get("ok", false)):
		_show_toast(String(chk.get("reason", "GESPERRT")), DANGER)
		return
	var want_res: bool = _player.dungeons.prefer_resonance if _player.dungeons != null else true
	close_window()
	if coop:
		_manager.request_start_ready_check(_selected_id, want_res)
	else:
		_manager.request_enter_solo(_selected_id, want_res)


func _jump_or_show_route() -> void:
	var def: Dictionary = DungeonRules.by_id(_selected_id)
	if def.is_empty():
		return
	var wid: String = String(def.get("waystone_id", ""))
	var waystones: Waystones = Waystones.of(get_tree())
	if not wid.is_empty() and waystones != null and waystones.is_awake(wid) and _player != null:
		close_window()
		waystones.request_travel(_player, wid)
		return
	## Otherwise open the Atlas map so the player sees the zone & route to the gate
	close_window()
	var hud: Node = get_parent()
	if hud != null:
		var mw: Node = hud.get_node_or_null("MapWindow")
		if mw != null and mw.has_method("toggle_open"):
			mw.call("toggle_open")


func _item_icon(item_id: String) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id] as Texture2D
	var def: Dictionary = DataRegistry.table("items").get(item_id, {}) as Dictionary
	var p: String = String(def.get("icon", ""))
	var tex: Texture2D = load(p) as Texture2D if not p.is_empty() and ResourceLoader.exists(p) else null
	_icon_cache[item_id] = tex
	return tex


func _banner_tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _banner_cache.has(path):
		return _banner_cache[path] as Texture2D
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_banner_cache[path] = tex
	return tex


func _draw() -> void:
	if not visible:
		return
	var vs: Vector2 = get_viewport_rect().size
	var a: float = smoothstep(0.0, 1.0, _open_t)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(BG_OUTER, BG_OUTER.a * a))

	var frame: Rect2 = Rect2(FRAME_PAD_X, FRAME_PAD_Y, vs.x - FRAME_PAD_X * 2.0, vs.y - FRAME_PAD_Y * 2.0)
	## Outer carved Steinsetzer frame
	draw_rect(frame, Color(INK, a))
	draw_rect(frame.grow(-1), Color(RIM_STONE, a))
	draw_rect(frame.grow(-2), Color(SLATE_DEEP, a))
	## Subtle turquoise corner brackets
	for corner: Vector2 in [frame.position, Vector2(frame.end.x - 10, frame.position.y), Vector2(frame.position.x, frame.end.y - 10), frame.end - Vector2(10, 10)]:
		draw_rect(Rect2(corner, Vector2(10, 2)), Color(TEAL, 0.8 * a))
		draw_rect(Rect2(corner, Vector2(2, 10)), Color(TEAL, 0.8 * a))

	_draw_header(frame, a)
	if _tab == 0:
		_draw_trials_tab(frame, a)
	else:
		_draw_exchange_tab(frame, a)

	if _toast_left > 0.0:
		var tw: float = 240.0
		var tr: Rect2 = Rect2(roundf((vs.x - tw) * 0.5), frame.end.y - 26.0, tw, 18.0)
		draw_rect(tr, INK)
		draw_rect(tr.grow(-1), SLATE_CARD)
		PixelText.draw(self, _toast_text.left(36), Vector2i(int(tr.position.x) + 10, int(tr.position.y) + 5), _toast_color, INK)


func _draw_header(frame: Rect2, a: float) -> void:
	var hx: float = frame.position.x + 8.0
	var hy: float = frame.position.y + 8.0
	var hw: float = frame.size.x - 16.0
	draw_rect(Rect2(hx, hy, hw, 38.0), Color(SLATE_MID, a))
	draw_rect(Rect2(hx, hy + 37.0, hw, 1.0), Color(RIM_STONE, 0.8 * a))

	## Tabs: PRÜFUNGEN | ECHOTAUSCH
	_tab_trials_rect = Rect2(hx + 6.0, hy + 6.0, 96.0, 24.0)
	_tab_exchange_rect = Rect2(hx + 108.0, hy + 6.0, 126.0, 24.0)
	var echo_bal: int = _player.dungeons.echo_shards() if (_player != null and _player.dungeons != null) else 0

	_draw_tab_button(_tab_trials_rect, "PRÜFUNGEN", _tab == 0, TEAL)
	_draw_tab_button(_tab_exchange_rect, "ECHOTAUSCH (%d)" % echo_bal, _tab == 1, GOLD)

	## Right side: 4 glowing Resonance Seals + refresh countdown + Rest Bonus pips
	var charges: int = _player.dungeons.charges() if (_player != null and _player.dungeons != null) else 4
	var rest_u: int = _player.dungeons.rest_units() if (_player != null and _player.dungeons != null) else 0
	var now_u: int = DungeonProfileComponent._now_unix()
	var sec_left: int = ResonanceRules.seconds_until_next_refresh(now_u)
	var pulse: float = 0.78 + 0.22 * sin(_time * 3.8)

	var rx: float = hx + hw - 266.0
	for i: int in 4:
		var sx: float = rx + float(i) * 16.0
		var sy: float = hy + 6.0
		var lit: bool = i < charges
		draw_rect(Rect2(sx, sy, 12, 12), INK)
		draw_rect(Rect2(sx + 1, sy + 1, 10, 10), Color(TEAL, 0.85 * pulse) if lit else Color("141b2c"))
		if lit:
			draw_rect(Rect2(sx + 3, sy + 3, 6, 6), Color("e8ffff"))
		else:
			draw_rect(Rect2(sx + 4, sy + 4, 4, 4), Color("28344c"))

	PixelText.draw(self, "%d/4 · +2 IN %s" % [charges, ResonanceRules.format_countdown(sec_left)], Vector2i(int(rx) + 68, int(hy) + 8), TEAL, INK)

	## Rest Bonus bar (Ruhende Glut — 8 half-units -> up to 4x double rewards)
	PixelText.draw(self, "RUHENDE GLUT", Vector2i(int(rx), int(hy) + 24), MUTED, INK)
	var rest_max: int = ResonanceRules.rest_max_units()
	for i: int in rest_max:
		var px: float = rx + 72.0 + float(i) * 8.0
		var py: float = hy + 24.0
		draw_rect(Rect2(px, py, 6, 7), INK)
		draw_rect(Rect2(px + 1, py + 1, 4, 5), GOLD if i < rest_u else Color("182032"))
	var d_ready: int = ResonanceRules.rest_doubles_ready({"rest_units": rest_u})
	if d_ready > 0:
		PixelText.draw(self, "%dx DOPPELT!" % d_ready, Vector2i(int(rx) + 140, int(hy) + 24), GOLD, INK)

	## Close [X]
	_close_rect = Rect2(hx + hw - 24.0, hy + 6.0, 20.0, 20.0)
	draw_rect(_close_rect, INK)
	draw_rect(_close_rect.grow(-1), Color("4a1c2a") if _close_rect.has_point(_mouse) else SLATE_CARD)
	PixelText.draw(self, "X", Vector2i(int(_close_rect.position.x) + 7, int(_close_rect.position.y) + 6), TEXT, INK)


func _draw_tab_button(r: Rect2, label: String, active: bool, accent: Color) -> void:
	draw_rect(r, INK)
	var bg: Color = SLATE_SEL if active else (SLATE_HOVER if r.has_point(_mouse) else SLATE_CARD)
	draw_rect(r.grow(-1), bg)
	if active:
		draw_rect(Rect2(r.position.x + 1, r.end.y - 3, r.size.x - 2, 2), accent)
	PixelText.draw(self, label, Vector2i(int(r.position.x) + 8, int(r.position.y) + 8), accent if active else MUTED, INK)


func _draw_trials_tab(frame: Rect2, a: float) -> void:
	var body_x: float = frame.position.x + 8.0
	var body_y: float = frame.position.y + 52.0
	var body_h: float = frame.size.y - 60.0
	var body_w: float = frame.size.x - 16.0

	## Left Rail: ALTMARK Dungeon List
	var list_rect: Rect2 = Rect2(body_x, body_y, LIST_W, body_h)
	draw_rect(list_rect, INK)
	draw_rect(list_rect.grow(-1), Color(SLATE_MID, a))
	PixelText.draw(self, "ALTMARK · GEWÖLBE (ST. 5–30)", Vector2i(int(list_rect.position.x) + 8, int(list_rect.position.y) + 6), GOLD, INK)
	draw_rect(Rect2(list_rect.position.x + 6, list_rect.position.y + 18, LIST_W - 12, 1), RIM_STONE)

	_row_rects.clear()
	var plv: int = _player.progress.level if _player != null else 1
	var all_d: Array[Dictionary] = DungeonRules.all()
	var y_top: float = list_rect.position.y + 23.0
	var y_bot: float = list_rect.end.y - 6.0

	for idx: int in all_d.size():
		var d: Dictionary = all_d[idx]
		var did: String = String(d.get("id", ""))
		var ry: float = y_top + float(idx) * (ROW_H + 3.0) - _list_scroll
		if ry + ROW_H < y_top or ry > y_bot:
			continue
		var r: Rect2 = Rect2(list_rect.position.x + 6.0, ry, LIST_W - 12.0, ROW_H)
		var clipped: Rect2 = r.intersection(Rect2(list_rect.position.x, y_top, LIST_W, y_bot - y_top))
		if clipped.size.y < ROW_H - 2.0:
			continue
		_row_rects.append({"rect": clipped, "id": did})

		var sel: bool = did == _selected_id
		var playable: bool = bool(d.get("playable", false))
		var disc: bool = _player != null and _player.dungeons != null and _player.dungeons.is_discovered(did)
		var clears: int = _player.dungeons.clear_count(did) if (_player != null and _player.dungeons != null) else 0
		var min_lv: int = int(d.get("min_level", 1))
		var arch: Dictionary = DungeonRules.archetype_info(String(d.get("archetype", "expedition")))
		var acol: Color = Color.from_string(String(arch.get("color", "4df2e0")), TEAL)

		var bg: Color = SLATE_SEL if sel else (SLATE_HOVER if clipped.has_point(_mouse) else SLATE_CARD)
		if not playable:
			bg = bg.darkened(0.32)
		draw_rect(clipped, INK)
		draw_rect(clipped.grow(-1), bg)
		if sel:
			draw_rect(Rect2(clipped.position.x + 1, clipped.position.y + 1, 2, clipped.size.y - 2), acol)

		var code: String = "[%s]" % String(arch.get("code", "?"))
		PixelText.draw(self, code, Vector2i(int(r.position.x) + 6, int(r.position.y) + 6), acol if playable else MUTED, INK)
		var dtitle: String = String(d.get("name", did)).left(19) if (playable or disc) else "??? (VERSIEGELT)"
		PixelText.draw(self, dtitle, Vector2i(int(r.position.x) + 28, int(r.position.y) + 6), TEXT if playable else MUTED, INK)
		var lv_col: Color = OK_GREEN if (playable and plv >= min_lv) else (DANGER if playable else MUTED)
		PixelText.draw(self, "%s · ST.%d" % [String(d.get("zone_name", "")).left(11), min_lv], Vector2i(int(r.position.x) + 28, int(r.position.y) + 20), lv_col, INK)
		if clears > 0:
			PixelText.draw(self, "OK", Vector2i(int(r.end.x) - 18, int(r.position.y) + 20), GOLD, INK)

	## Right Detail Panel
	var det_x: float = body_x + LIST_W + 8.0
	var det_w: float = body_w - LIST_W - 8.0
	var det_rect: Rect2 = Rect2(det_x, body_y, det_w, body_h)
	draw_rect(det_rect, INK)
	draw_rect(det_rect.grow(-1), Color(SLATE_MID, a))
	_draw_dungeon_detail(det_rect)


func _draw_dungeon_detail(det: Rect2) -> void:
	var def: Dictionary = DungeonRules.by_id(_selected_id)
	if def.is_empty():
		return
	var playable: bool = bool(def.get("playable", false))
	var min_lv: int = int(def.get("min_level", 1))
	var plv: int = _player.progress.level if _player != null else 1
	var arch: Dictionary = DungeonRules.archetype_info(String(def.get("archetype", "expedition")))
	var accent: Color = Color.from_string(String(def.get("accent", "4df2e0")), TEAL)

	## Scene Artwork Banner
	var ban: Rect2 = Rect2(det.position.x + 8.0, det.position.y + 8.0, det.size.x - 16.0, 74.0)
	draw_rect(ban, INK)
	var btex: Texture2D = _banner_tex(String(def.get("banner", "")))
	if btex != null:
		draw_texture_rect(btex, ban.grow(-1), false)
		draw_rect(ban.grow(-1), Color(0.04, 0.06, 0.12, 0.42))
	else:
		_draw_procedural_banner(ban.grow(-1), accent, playable)

	## Title & Pills on top of Banner
	draw_set_transform(Vector2(ban.position.x + 10.0, ban.position.y + 10.0), 0.0, Vector2(2.0, 2.0))
	PixelText.draw(self, String(def.get("name", "")).left(24), Vector2i.ZERO, GOLD if playable else MUTED, INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	PixelText.draw(self, String(def.get("subtitle", "")).left(56), Vector2i(int(ban.position.x) + 10, int(ban.position.y) + 32), TEXT if playable else MUTED, INK)

	var pills: String = "%s  ·  AB STUFE %d  ·  1–4 SPIELER  ·  3 FUNKEN" % [String(arch.get("name", "")), min_lv]
	PixelText.draw(self, pills, Vector2i(int(ban.position.x) + 10, int(ban.end.y) - 16), accent if playable else MUTED, INK)

	## Record Strip (Bestzeit, Siege, Konter, Erstläuterung)
	var rec_y: float = ban.end.y + 8.0
	var rec_box: Rect2 = Rect2(det.position.x + 8.0, rec_y, det.size.x - 16.0, 24.0)
	draw_rect(rec_box, INK)
	draw_rect(rec_box.grow(-1), SLATE_CARD)
	var rec: Dictionary = _player.dungeons.record_for(_selected_id) if (_player != null and _player.dungeons != null) else {}
	var best_s: float = float(rec.get("best_sec", 0.0))
	var best_txt: String = DungeonRules.format_time(best_s) if best_s > 0.0 else "--:--"
	var clears: int = int(rec.get("clears", 0))
	var best_cnt: int = int(rec.get("best_counters", 0))
	var fc_txt: String = "ERLEDIGT" if clears > 0 else "OFFEN (BONUS!)"
	PixelText.draw(self, "BESTZEIT: %s   ·   SIEGE: %d   ·   KONTER: %d   ·   ERSTLAUF: %s" % [best_txt, clears, best_cnt, fc_txt], Vector2i(int(rec_box.position.x) + 8, int(rec_box.position.y) + 8), GOLD if clears > 0 else TEAL, INK)

	## Description (wrapped lines)
	var desc_y: int = int(rec_box.end.y) + 8
	var lines: PackedStringArray = _wrap_text(String(def.get("description", "")), 60)
	for i: int in mini(lines.size(), 3):
		PixelText.draw(self, lines[i], Vector2i(int(det.position.x) + 10, desc_y + i * 11), TEXT if playable else MUTED, INK)

	## Loot Preview Row
	var loot_y: float = float(desc_y) + 38.0
	PixelText.draw(self, "BEUTE-VORSCHAU (ERSTLÄUTERUNG & RESONANZ-RELIQUIAR):", Vector2i(int(det.position.x) + 10, int(loot_y)), MUTED, INK)
	_preview_item_rects.clear()
	var prev_items: Array = def.get("preview_items", []) as Array
	var ix: float = det.position.x + 10.0
	var iy: float = loot_y + 13.0
	var hover_item: String = ""
	for i: int in mini(prev_items.size(), 7):
		var iid: String = String(prev_items[i])
		var srect: Rect2 = Rect2(ix, iy, 34.0, 34.0)
		_preview_item_rects.append({"rect": srect, "item_id": iid})
		draw_rect(srect, INK)
		draw_rect(srect.grow(-1), SLATE_HOVER if srect.has_point(_mouse) else SLATE_CARD)
		var tex: Texture2D = _item_icon(iid)
		if tex != null:
			draw_texture_rect(tex, Rect2(ix + 3, iy + 3, 28, 28), false)
		else:
			PixelText.draw(self, iid.left(4).to_upper(), Vector2i(int(ix) + 5, int(iy) + 13), GOLD, INK)
		if srect.has_point(_mouse):
			hover_item = iid
		ix += 40.0
	if not hover_item.is_empty():
		var idef: Dictionary = DataRegistry.table("items").get(hover_item, {}) as Dictionary
		var hname: String = String(idef.get("name", hover_item)).to_upper()
		PixelText.draw(self, hname, Vector2i(int(ix) + 6, int(iy) + 12), GOLD, INK)

	## Resonance Opt-In Checkbox
	var chk_y: float = det.end.y - 52.0
	_res_toggle_rect = Rect2(det.position.x + 10.0, chk_y, det.size.x - 20.0, 16.0)
	var charges: int = _player.dungeons.charges() if (_player != null and _player.dungeons != null) else 0
	var want_res: bool = _player.dungeons.prefer_resonance if (_player != null and _player.dungeons != null) else true
	var d_ready: int = ResonanceRules.rest_doubles_ready(_player.dungeons.resonance) if (_player != null and _player.dungeons != null) else 0
	draw_rect(Rect2(det.position.x + 10.0, chk_y + 2.0, 11.0, 11.0), INK)
	draw_rect(Rect2(det.position.x + 11.0, chk_y + 3.0, 9.0, 9.0), SLATE_HOVER if _res_toggle_rect.has_point(_mouse) else SLATE_DEEP)
	if want_res and charges > 0:
		draw_rect(Rect2(det.position.x + 13.0, chk_y + 5.0, 5.0, 5.0), TEAL)
	var res_txt: String = "SCHLEIERRESONANZ EINLÖSEN (%d/4)" % charges
	if want_res and charges > 0 and d_ready > 0:
		res_txt += "  ·  2x RUHENDE GLUT AKTIV!"
	elif not want_res or charges <= 0:
		res_txt = "OHNE RESONANZ LAUFEN (0 LADUNGEN · BASISBEUTE + ECHOSPLITTER)"
	PixelText.draw(self, res_txt, Vector2i(int(det.position.x) + 26, int(chk_y) + 4), TEAL if (want_res and charges > 0) else MUTED, INK)

	## Bottom Action Row (At physical Gate vs Remote G Overview)
	var btn_y: float = det.end.y - 30.0
	var at_this_gate: bool = _at_gate and _selected_id == _gate_dungeon_id
	_btn_solo_rect = Rect2()
	_btn_coop_rect = Rect2()
	_btn_route_rect = Rect2()

	if not playable:
		var lock_r: Rect2 = Rect2(det.position.x + 10.0, btn_y, det.size.x - 20.0, 22.0)
		draw_rect(lock_r, INK)
		draw_rect(lock_r.grow(-1), Color("161a28"))
		PixelText.draw(self, "NOCH VOM SCHLEIER VERSIEGELT (KOMMENDE ZONE)", Vector2i(int(lock_r.position.x) + 56, int(btn_y) + 7), MUTED, INK)
		return

	if at_this_gate:
		var chk: Dictionary = DungeonRules.can_enter(plv, def)
		var ok: bool = bool(chk.get("ok", false))
		var bw: float = (det.size.x - 28.0) * 0.5
		_btn_solo_rect = Rect2(det.position.x + 10.0, btn_y, bw, 22.0)
		_btn_coop_rect = Rect2(det.position.x + 18.0 + bw, btn_y, bw, 22.0)

		draw_rect(_btn_solo_rect, INK)
		var s_bg: Color = (Color("286c70") if _btn_solo_rect.has_point(_mouse) else Color("1c4a4e")) if ok else Color("3a1824")
		draw_rect(_btn_solo_rect.grow(-1), s_bg)
		var s_lbl: String = "ALLEIN BETRETEN" if ok else String(chk.get("reason", "GESPERRT"))
		PixelText.draw(self, s_lbl, Vector2i(int(_btn_solo_rect.position.x) + 38, int(btn_y) + 7), TEAL if ok else DANGER, INK)

		draw_rect(_btn_coop_rect, INK)
		var c_bg: Color = (Color("5e4516") if _btn_coop_rect.has_point(_mouse) else Color("3e2e10")) if ok else Color("241a24")
		draw_rect(_btn_coop_rect.grow(-1), c_bg)
		PixelText.draw(self, "GRUPPE RUFEN (KOOP)", Vector2i(int(_btn_coop_rect.position.x) + 28, int(btn_y) + 7), GOLD if ok else MUTED, INK)
	else:
		_btn_route_rect = Rect2(det.position.x + 10.0, btn_y, 200.0, 22.0)
		draw_rect(_btn_route_rect, INK)
		draw_rect(_btn_route_rect.grow(-1), Color("286c70") if _btn_route_rect.has_point(_mouse) else Color("1c4a4e"))
		var wid: String = String(def.get("waystone_id", ""))
		var ws: Waystones = Waystones.of(get_tree())
		var can_tp: bool = not wid.is_empty() and ws != null and ws.is_awake(wid)
		PixelText.draw(self, "ZUM WEGSTEIN REISEN" if can_tp else "WEG IM ATLAS ZEIGEN", Vector2i(int(_btn_route_rect.position.x) + 26, int(btn_y) + 7), TEAL, INK)
		PixelText.draw(self, "START AM TOR IN %s" % String(def.get("zone_name", "SÜDKAP")), Vector2i(int(_btn_route_rect.end.x) + 12, int(btn_y) + 7), MUTED, INK)


func _draw_exchange_tab(frame: Rect2, a: float) -> void:
	var bx: float = frame.position.x + 8.0
	var by: float = frame.position.y + 52.0
	var bw: float = frame.size.x - 16.0
	var bh: float = frame.size.y - 60.0
	var box: Rect2 = Rect2(bx, by, bw, bh)
	draw_rect(box, INK)
	draw_rect(box.grow(-1), Color(SLATE_MID, a))

	var shards: int = _player.dungeons.echo_shards() if (_player != null and _player.dungeons != null) else 0
	var earned: int = _player.dungeons.echo_week_earned() if (_player != null and _player.dungeons != null) else 0
	var wcap: int = ResonanceRules.weekly_echo_cap()
	PixelText.draw(self, "STEINSETZER-ECHOTAUSCH  ·  GUTHABEN: %d ECHOSPLITTER" % shards, Vector2i(int(bx) + 10, int(by) + 8), GOLD, INK)
	PixelText.draw(self, "WOCHENLIMIT VERDIENT: %d / %d" % [earned, wcap], Vector2i(int(bx + bw) - 180, int(by) + 8), TEAL, INK)
	draw_rect(Rect2(bx + 8, by + 22, bw - 16, 1), RIM_STONE)

	_exchange_btn_rects.clear()
	var offers: Array[Dictionary] = DungeonRules.exchange_offers()
	var cleared_map: Dictionary = _player.dungeons.cleared if (_player != null and _player.dungeons != null) else {}
	var bought_map: Dictionary = (_player.dungeons.resonance.get("exchange_bought", {}) as Dictionary) if (_player != null and _player.dungeons != null) else {}

	var col_w: float = (bw - 28.0) * 0.5
	var card_h: float = 52.0
	var y_top: float = by + 28.0
	var y_bot: float = box.end.y - 10.0

	for i: int in offers.size():
		var off: Dictionary = offers[i]
		var col_i: int = i % 2
		var row_i: int = i / 2
		var cx: float = bx + 10.0 + float(col_i) * (col_w + 8.0)
		var cy: float = y_top + float(row_i) * (card_h + 6.0) - _ex_scroll
		if cy + card_h < y_top or cy > y_bot:
			continue
		var cr: Rect2 = Rect2(cx, cy, col_w, card_h)
		draw_rect(cr, INK)
		draw_rect(cr.grow(-1), SLATE_CARD)

		var iid: String = String(off.get("item_id", ""))
		var cnt: int = int(off.get("count", 1))
		var cost: int = int(off.get("cost", 10))
		var oid: String = String(off.get("id", ""))
		var limit: int = int(off.get("weekly_limit", 0))
		var done: int = int(bought_map.get(oid, 0))
		var req_clear: String = String(off.get("requires_clear", ""))
		var clear_ok: bool = req_clear.is_empty() or int(cleared_map.get(req_clear, 0)) > 0
		var stock_ok: bool = limit <= 0 or done < limit
		var afford: bool = shards >= cost
		var can_buy: bool = clear_ok and stock_ok and afford

		## Item icon
		var ir: Rect2 = Rect2(cx + 8.0, cy + 9.0, 34.0, 34.0)
		draw_rect(ir, INK)
		draw_rect(ir.grow(-1), SLATE_DEEP)
		var tex: Texture2D = _item_icon(iid)
		if tex != null:
			draw_texture_rect(tex, Rect2(cx + 11.0, cy + 12.0, 28.0, 28.0), false)
		else:
			PixelText.draw(self, iid.left(4).to_upper(), Vector2i(int(cx) + 12, int(cy) + 21), GOLD, INK)
		if cnt > 1:
			PixelText.draw(self, "x%d" % cnt, Vector2i(int(cx) + 26, int(cy) + 34), GOLD, INK)

		var idef: Dictionary = DataRegistry.table("items").get(iid, {}) as Dictionary
		var iname: String = String(idef.get("name", iid)).to_upper().left(22)
		PixelText.draw(self, iname, Vector2i(int(cx) + 48, int(cy) + 8), TEXT if clear_ok else MUTED, INK)
		PixelText.draw(self, String(off.get("tag", "")).left(24), Vector2i(int(cx) + 48, int(cy) + 21), TEAL if clear_ok else MUTED, INK)
		var stock_lbl: String = "WOCHE: %d/%d" % [maxi(limit - done, 0), limit] if limit > 0 else "UNBEGRENZT"
		PixelText.draw(self, stock_lbl, Vector2i(int(cx) + 48, int(cy) + 35), MUTED, INK)

		## Buy button
		var br: Rect2 = Rect2(cr.end.x - 86.0, cy + 14.0, 78.0, 24.0)
		_exchange_btn_rects.append({"rect": br, "offer_id": oid, "enabled": can_buy})
		draw_rect(br, INK)
		var b_bg: Color = Color("286c70") if (can_buy and br.has_point(_mouse)) else (Color("1c4a4e") if can_buy else Color("181d2c"))
		draw_rect(br.grow(-1), b_bg)
		var blbl: String = "%d SPL." % cost if (clear_ok and stock_ok) else ("GESPERRT" if not clear_ok else "AUSVERK.")
		PixelText.draw(self, blbl, Vector2i(int(br.position.x) + 10, int(br.position.y) + 8), GOLD if can_buy else (DANGER if not afford and clear_ok and stock_ok else MUTED), INK)


func _draw_procedural_banner(r: Rect2, accent: Color, playable: bool) -> void:
	## Atmospheric Steinsetzer arch + tide water horizon fallback before custom art banner loads
	draw_rect(r, Color("0a101d") if playable else Color("0b0c14"))
	var water_y: float = r.position.y + r.size.y * 0.64
	draw_rect(Rect2(r.position.x, water_y, r.size.x, r.end.y - water_y), Color("102234") if playable else Color("11121e"))
	## Distant stone arches
	for i: int in 6:
		var ax: float = r.position.x + 28.0 + float(i) * 64.0
		draw_rect(Rect2(ax, r.position.y + 12.0, 14.0, r.size.y - 12.0), Color("182438"))
		draw_rect(Rect2(ax + 14.0, r.position.y + 12.0, 50.0, 8.0), Color("1f2e46"))
	## Shimmering water reflections
	for i: int in 9:
		var wx: float = r.position.x + 20.0 + float(i) * 40.0 + sin(_time * 1.8 + float(i)) * 4.0
		draw_rect(Rect2(wx, water_y + 6.0 + float(i % 3) * 6.0, 18.0, 2.0), Color(accent, 0.35 if playable else 0.14))


func _wrap_text(text: String, max_chars: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var words: PackedStringArray = text.split(" ", false)
	var line: String = ""
	for w: String in words:
		if line.is_empty():
			line = w
		elif line.length() + 1 + w.length() <= max_chars:
			line += " " + w
		else:
			out.append(line)
			line = w
	if not line.is_empty():
		out.append(line)
	return out
