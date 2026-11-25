class_name DungeonResultWindow
extends Control
## Post-run Victory & Wipe overlay (docs/dungeon_konzept.md Section 5.4).
## Victory shows Clear Time, "NEUE BESTZEIT!" stamp, full Solo & Coop combat statistics
## (damage, Klangkonter, Taumelbrüche, hits taken, Coop MVP titles), awarded rewards,
## and buttons to Rerun, Look Around, or Leave.
## Wipe shows "SCHLEIERFUNKEN ERLOSCHEN" with Retry-at-Checkpoint or Leave (0 resonance spent).

const BG_SCRIM: Color = Color(0.03, 0.04, 0.08, 0.78)
const PANEL_DARK: Color = Color("111626")
const PANEL_SLATE: Color = Color("1b2438")
const CARD_BG: Color = Color("141b2c")
const INK: Color = Color("05070e")
const TEAL: Color = Color("4df2e0")
const GOLD: Color = Color("ffd98a")
const TEXT: Color = Color("e8f2f7")
const MUTED: Color = Color("8698b2")
const DANGER: Color = Color("ff5c7a")

var _player: Player = null
var _manager: DungeonManager = null
var _mode: String = "" ## "victory" | "wipe"
var _data: Dictionary = {}
var _hover: String = ""
var _open_t: float = 0.0

var _btn_primary: Rect2 = Rect2()
var _btn_secondary: Rect2 = Rect2()
var _btn_tertiary: Rect2 = Rect2()
var _icon_cache: Dictionary = {}


func bind(player: Player) -> void:
	_player = player
	_hook_manager.call_deferred()


func _ready() -> void:
	name = "DungeonResultWindow"
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func _hook_manager() -> void:
	_manager = DungeonManager.of(get_tree())
	if _manager == null:
		return
	if not _manager.run_victory_received.is_connected(_on_victory):
		_manager.run_victory_received.connect(_on_victory)
	if not _manager.run_wiped_received.is_connected(_on_wiped):
		_manager.run_wiped_received.connect(_on_wiped)


func _on_victory(summary: Dictionary) -> void:
	_mode = "victory"
	_data = summary
	_open_t = 0.0
	visible = true
	InputManager.dungeons_open = true
	Sfx.ui(self, "skills/learn", -1.0)
	queue_redraw()


func _on_wiped(payload: Dictionary) -> void:
	_mode = "wipe"
	_data = payload
	_open_t = 0.0
	visible = true
	InputManager.dungeons_open = true
	queue_redraw()


func close_window() -> void:
	visible = false
	_mode = ""
	InputManager.dungeons_open = false


func _process(delta: float) -> void:
	if not visible:
		return
	_open_t = minf(_open_t + delta * 3.5, 1.0)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var pos: Vector2 = (event as InputEventMouseMotion).position
		var prev: String = _hover
		if _btn_primary.has_point(pos):
			_hover = "primary"
		elif _btn_secondary.has_point(pos):
			_hover = "secondary"
		elif _btn_tertiary.has_point(pos):
			_hover = "tertiary"
		else:
			_hover = ""
		if prev != _hover:
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = mb.position
			if _mode == "victory":
				if _btn_primary.has_point(pos) and _manager != null:
					var want_res: bool = _player.dungeons.prefer_resonance if (_player != null and _player.dungeons != null) else true
					close_window()
					_manager.request_rerun_dungeon(want_res)
				elif _btn_secondary.has_point(pos):
					close_window() ## inspect reliquary & walk out through Return Seal
				elif _btn_tertiary.has_point(pos) and _manager != null:
					close_window()
					_manager.request_leave_dungeon()
			elif _mode == "wipe":
				if _btn_primary.has_point(pos) and _manager != null:
					close_window()
					_manager.request_retry_dungeon()
				elif _btn_tertiary.has_point(pos) and _manager != null:
					close_window()
					_manager.request_leave_dungeon()
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _mode == "victory" and event.is_action_pressed("ui_cancel"):
		close_window()
		get_viewport().set_input_as_handled()


func _item_icon(item_id: String) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id] as Texture2D
	var def: Dictionary = DataRegistry.table("items").get(item_id, {}) as Dictionary
	var p: String = String(def.get("icon", ""))
	var tex: Texture2D = load(p) as Texture2D if not p.is_empty() and ResourceLoader.exists(p) else null
	_icon_cache[item_id] = tex
	return tex


func _draw() -> void:
	if not visible:
		return
	var vs: Vector2 = get_viewport_rect().size
	var a: float = smoothstep(0.0, 1.0, _open_t)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(BG_SCRIM, BG_SCRIM.a * a))
	if _mode == "wipe":
		_draw_wipe(vs, a)
	else:
		_draw_victory(vs, a)


func _draw_wipe(vs: Vector2, a: float) -> void:
	var pw: float = 340.0
	var ph: float = 152.0
	var px: float = roundf((vs.x - pw) * 0.5)
	var py: float = roundf((vs.y - ph) * 0.5)
	var rect: Rect2 = Rect2(px, py, pw, ph)
	draw_rect(rect, Color(INK, a))
	draw_rect(rect.grow(-1), Color(PANEL_DARK, a))
	draw_rect(rect.grow(-3), Color(PANEL_SLATE, a))
	draw_rect(Rect2(px + 3, py + 3, pw - 6, 2), Color(DANGER, a))

	draw_set_transform(Vector2(px + 38, py + 18), 0.0, Vector2(2.0, 2.0))
	PixelText.draw(self, "SCHLEIERFUNKEN ERLOSCHEN", Vector2i.ZERO, Color(DANGER, a), Color(INK, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	PixelText.draw(self, "KEINE RESONANZ-LADUNG VERBRAUCHT.", Vector2i(int(px) + 64, int(py) + 48), Color(TEAL, a), Color(INK, a))
	PixelText.draw(self, "DU KANNST AM LETZTEN RASTPUNKT NEU STARTEN.", Vector2i(int(px) + 42, int(py) + 64), Color(MUTED, a), Color(INK, a))

	_btn_primary = Rect2(px + 20, py + ph - 36, 144, 22)
	_btn_secondary = Rect2()
	_btn_tertiary = Rect2(px + pw - 164, py + ph - 36, 144, 22)

	draw_rect(_btn_primary, INK)
	draw_rect(_btn_primary.grow(-1), Color("286c70") if _hover == "primary" else Color("1c4a4e"))
	PixelText.draw(self, "ERNEUT VERSUCHEN", Vector2i(int(_btn_primary.position.x) + 22, int(_btn_primary.position.y) + 7), TEAL, INK)

	draw_rect(_btn_tertiary, INK)
	draw_rect(_btn_tertiary.grow(-1), Color("4a1c2a") if _hover == "tertiary" else Color("301520"))
	PixelText.draw(self, "GEWÖLBE VERLASSEN", Vector2i(int(_btn_tertiary.position.x) + 18, int(_btn_tertiary.position.y) + 7), DANGER, INK)


func _draw_victory(vs: Vector2, a: float) -> void:
	## Backdrop scrim so the arena never bleeds through victory/wipe stats
	draw_rect(Rect2(Vector2.ZERO, vs), Color(Color("05070e"), 0.80 * a))
	var pw: float = 472.0
	var ph: float = 296.0
	var px: float = roundf((vs.x - pw) * 0.5)
	var py: float = roundf((vs.y - ph) * 0.5)
	var rect: Rect2 = Rect2(px, py, pw, ph)
	draw_rect(rect, Color(INK, a))
	draw_rect(rect.grow(-1), Color(PANEL_DARK, a))
	draw_rect(rect.grow(-3), Color(PANEL_SLATE, a))
	draw_rect(Rect2(px + 3, py + 3, pw - 6, 2), Color(GOLD, a))

	## Banner title
	draw_set_transform(Vector2(px + 16, py + 12), 0.0, Vector2(2.0, 2.0))
	PixelText.draw(self, "GEWÖLBE GELÄUTERT", Vector2i.ZERO, Color(GOLD, a), Color(INK, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var dname: String = String(_data.get("name", ""))
	var clear_str: String = DungeonRules.format_time(float(_data.get("clear_sec", 0.0)))
	PixelText.draw(self, "%s  ·  ZEIT %s" % [dname, clear_str], Vector2i(int(px) + 16, int(py) + 34), Color(TEXT, a), Color(INK, a))
	if bool(_data.get("new_best_time", false)):
		var b_rect: Rect2 = Rect2(px + pw - 116, py + 14, 100, 16)
		draw_rect(b_rect, INK)
		draw_rect(b_rect.grow(-1), Color("5e4516"))
		PixelText.draw(self, "NEUE BESTZEIT!", Vector2i(int(b_rect.position.x) + 10, int(b_rect.position.y) + 4), GOLD, INK)

	## Combat Statistics Panel (Solo & Coop + MVP Badges)
	var stat_box: Rect2 = Rect2(px + 14, py + 50, pw - 28, 102)
	draw_rect(stat_box, INK)
	draw_rect(stat_box.grow(-1), CARD_BG)
	PixelText.draw(self, "KAMPFSTATISTIK", Vector2i(int(stat_box.position.x) + 8, int(stat_box.position.y) + 6), TEAL, INK)
	PixelText.draw(self, "SCHADEN", Vector2i(int(stat_box.position.x) + 140, int(stat_box.position.y) + 6), MUTED, INK)
	PixelText.draw(self, "KONTER", Vector2i(int(stat_box.position.x) + 210, int(stat_box.position.y) + 6), MUTED, INK)
	PixelText.draw(self, "TAUMEL", Vector2i(int(stat_box.position.x) + 266, int(stat_box.position.y) + 6), MUTED, INK)
	PixelText.draw(self, "TREFFER", Vector2i(int(stat_box.position.x) + 322, int(stat_box.position.y) + 6), MUTED, INK)
	draw_rect(Rect2(stat_box.position.x + 6, stat_box.position.y + 18, stat_box.size.x - 12, 1), Color("28344c"))

	var party: Array = _data.get("party_stats", []) as Array
	var mvp_map: Dictionary = _data.get("mvp_titles", {}) as Dictionary
	var row_y: int = int(stat_box.position.y) + 23
	for i: int in mini(party.size(), 4):
		var row: Dictionary = party[i] as Dictionary
		var pid: int = int(row.get("peer_id", 0))
		var pname: String = String(row.get("name", "ELLIE")).left(14).to_upper()
		var pcol: Color = MultiplayerHud.PLAYER_TONES[i % MultiplayerHud.PLAYER_TONES.size()]
		draw_rect(Rect2(stat_box.position.x + 8, row_y + 1, 5, 5), pcol)
		PixelText.draw(self, pname, Vector2i(int(stat_box.position.x) + 18, row_y), TEXT, INK)
		PixelText.draw(self, "%d" % int(round(float(row.get("damage", 0.0)))), Vector2i(int(stat_box.position.x) + 140, row_y), GOLD, INK)
		PixelText.draw(self, "%d" % int(row.get("counters", 0)), Vector2i(int(stat_box.position.x) + 210, row_y), TEAL, INK)
		PixelText.draw(self, "%d" % int(row.get("staggers", 0)), Vector2i(int(stat_box.position.x) + 266, row_y), GOLD, INK)
		PixelText.draw(self, "%d" % int(row.get("hits_taken", 0)), Vector2i(int(stat_box.position.x) + 322, row_y), TEXT if int(row.get("hits_taken", 0)) == 0 else MUTED, INK)
		var raw_titles: Variant = mvp_map.get(pid, null)
		var first_title: String = ""
		if raw_titles is Array and not (raw_titles as Array).is_empty():
			first_title = String((raw_titles as Array)[0])
		elif raw_titles is String:
			first_title = String(raw_titles)
		if not first_title.is_empty():
			PixelText.draw(self, first_title.left(16), Vector2i(int(stat_box.position.x) + 368, row_y), GOLD, INK)
		row_y += 17

	var extra_note: String = "FUNKEN ÜBRIG: %d/%d" % [int(_data.get("sparks_left", 0)), int(_data.get("max_sparks", 3))]
	if bool(_data.get("bonus_part_broken", false)):
		extra_note += "  ·  HAFENLATERNE GEBROCHEN (+1 SEEGLIMMER!)"
	PixelText.draw(self, extra_note, Vector2i(int(stat_box.position.x) + 8, int(stat_box.end.y) - 13), TEAL, INK)

	## Rewards Panel
	var rw_box: Rect2 = Rect2(px + 14, py + 160, pw - 28, 88)
	draw_rect(rw_box, INK)
	draw_rect(rw_box.grow(-1), CARD_BG)
	var rw_head: String = "BEUTE"
	if bool(_data.get("first_clear", false)):
		rw_head += " · ERSTLÄUTERUNG!"
	if bool(_data.get("used_resonance", false)):
		rw_head += " · RESONANZ-RELIQUIAR"
	if bool(_data.get("doubled_by_rest", false)):
		rw_head += " (2x RUHENDE GLUT!)"
	PixelText.draw(self, rw_head, Vector2i(int(rw_box.position.x) + 8, int(rw_box.position.y) + 6), GOLD, INK)

	var curr_line: String = "+%d XP   ·   +%d KUPFER   ·   +%d ECHOSPLITTER" % [
		int(_data.get("xp", 0)),
		int(_data.get("copper", 0)),
		int(_data.get("echo_granted", 0)),
	]
	if bool(_data.get("echo_capped", false)):
		curr_line += " (WOCHENCAP)"
	PixelText.draw(self, curr_line, Vector2i(int(rw_box.position.x) + 8, int(rw_box.position.y) + 20), TEAL, INK)

	## Item slots row
	var all_items: Array[Dictionary] = []
	for k: String in ["first_clear_items", "items"]:
		for iv: Variant in _data.get(k, []) as Array:
			if iv is Dictionary:
				all_items.append(iv as Dictionary)
	var ix: float = rw_box.position.x + 10.0
	var iy: float = rw_box.position.y + 38.0
	for idx: int in mini(all_items.size(), 9):
		var it: Dictionary = all_items[idx]
		var iid: String = String(it.get("id", ""))
		var cnt: int = int(it.get("count", 1))
		var srect: Rect2 = Rect2(ix, iy, 38, 38)
		draw_rect(srect, INK)
		draw_rect(srect.grow(-1), PANEL_SLATE)
		var tex: Texture2D = _item_icon(iid)
		if tex != null:
			draw_texture_rect(tex, Rect2(ix + 3, iy + 3, 32, 32), false)
		else:
			PixelText.draw(self, iid.left(4).to_upper(), Vector2i(int(ix) + 6, int(iy) + 15), GOLD, INK)
		if cnt > 1:
			PixelText.draw(self, "x%d" % cnt, Vector2i(int(ix) + 20, int(iy) + 28), GOLD, INK)
		ix += 46.0

	## Bottom action buttons
	var by: float = py + ph - 34.0
	_btn_primary = Rect2(px + 14, by, 140, 22)
	_btn_secondary = Rect2(px + 166, by, 140, 22)
	_btn_tertiary = Rect2(px + pw - 154, by, 140, 22)

	draw_rect(_btn_primary, INK)
	draw_rect(_btn_primary.grow(-1), Color("286c70") if _hover == "primary" else Color("1c4a4e"))
	PixelText.draw(self, "NOCH EINMAL", Vector2i(int(_btn_primary.position.x) + 34, int(by) + 7), TEAL, INK)

	draw_rect(_btn_secondary, INK)
	draw_rect(_btn_secondary.grow(-1), Color("2b3954") if _hover == "secondary" else Color("202a40"))
	PixelText.draw(self, "ARENA ANSEHEN", Vector2i(int(_btn_secondary.position.x) + 26, int(by) + 7), TEXT, INK)

	draw_rect(_btn_tertiary, INK)
	draw_rect(_btn_tertiary.grow(-1), Color("5e4516") if _hover == "tertiary" else Color("3e2e10"))
	PixelText.draw(self, "ZURÜCK (%s)" % String(_data.get("zone_name", "SÜDKAP")).left(8), Vector2i(int(_btn_tertiary.position.x) + 16, int(by) + 7), GOLD, INK)
