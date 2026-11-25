class_name WorldTab
extends Control
## Unified 'WELT' ledger tab uniting 4 cohesive Feldcodex books under centered top sub-pills:
##  0: CHRONIK   (AtlasBook zone completion & milestone rewards)
##  1: STADT     (Native MenuChrome Town & Farm settlement overview + direct build/manage actions)
##  2: VÖGEL     (Native MenuChrome bonded Crow & Raven companion codex + rename & call controls)
##  3: FLUSSBUCH (Harmonized RiverBook fish codex)

signal request_close_menu
signal jump_to_atlas(world_tile: Vector2, zone_id: StringName)

const SUB_TABS: Array[Dictionary] = [
	{"id": "chronicle", "label": "CHRONIK"},
	{"id": "town", "label": "STADT"},
	{"id": "pets", "label": "VÖGEL"},
	{"id": "river", "label": "FLUSSBUCH"},
]

var _player: Node = null
var _river: Control = null
var _atlas_book: AtlasBook = null
var _requested_zone: StringName = &""
var _syncing_book: bool = false
var _sub: int = 0
var _hover_sub: int = -1
var _hover_id: String = ""
var _pill_rects: Array[Rect2] = []
var _hits: Array[Dictionary] = [] ## {id, rect, action, arg}
var _bar: Control = null
var _time: float = 0.0

# Vögel state
var _pet_sel: String = ""
var _editing_pet: bool = false
var _pet_text: String = ""


func bind(player: Node, river_book: Control) -> void:
	_player = player
	_river = river_book
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_atlas_book = AtlasBook.new()
	_atlas_book.name = "EmbeddedAtlasBook"
	_atlas_book.embedded_in_menu = true
	_atlas_book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_atlas_book.visible = false
	_atlas_book.place_selected.connect(func(wt: Vector2) -> void:
		jump_to_atlas.emit(wt, _atlas_book._zone_id))
	_atlas_book.state_changed.connect(_push_book_state_to_map)
	_atlas_book.reward_claimed.connect(_on_book_reward_claimed)
	add_child(_atlas_book)

	_bar = Control.new()
	_bar.name = "WorldSubBar"
	_bar.position = Vector2(14.0, 4.0)
	_bar.size = Vector2(360.0, 22.0)
	_bar.z_index = 45
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bar.draw.connect(_draw_bar)
	_bar.gui_input.connect(_on_bar_input)
	add_child(_bar)
	resized.connect(_center_bar)
	_center_bar()


func _center_bar() -> void:
	if _bar == null:
		return
	var total_w: float = 0.0
	for i: int in SUB_TABS.size():
		total_w += float(PixelText.width(String(SUB_TABS[i]["label"]))) + 18.0
		if i < SUB_TABS.size() - 1:
			total_w += 5.0
	var vw: float = size.x if size.x > 16.0 else 640.0
	_bar.size = Vector2(total_w, 22.0)
	_bar.position = Vector2(roundf((vw - total_w) * 0.5), 4.0)


func show_sub(index: int) -> void:
	_sub = clampi(index, 0, SUB_TABS.size() - 1)
	_editing_pet = false
	_sync_sub(true)
	if _bar != null:
		_bar.queue_redraw()
	queue_redraw()


func show_sub_id(sub_id: String) -> void:
	for i: int in SUB_TABS.size():
		if String(SUB_TABS[i]["id"]) == sub_id:
			show_sub(i)
			return
	show_sub(0)


func set_chronicle_zone(zone_id: StringName) -> void:
	_requested_zone = zone_id
	if _atlas_book != null and zone_id != &"":
		_atlas_book.set_zone(zone_id)


func close_embedded() -> void:
	_editing_pet = false
	_sync_sub(false)


func is_typing() -> bool:
	return _editing_pet


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _bar != null:
		_bar.queue_redraw()
	if _sub == 1 or _sub == 2:
		queue_redraw()


func _sync_sub(active: bool) -> void:
	# 0: Chronicle (AtlasBook)
	if _atlas_book != null:
		if active and _sub == 0:
			var disc: MapDiscovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery if is_inside_tree() else null
			var dir: Node = get_tree().get_first_node_in_group("zone_director") if is_inside_tree() else null
			if dir == null and is_inside_tree():
				var w_node: Node = get_tree().get_first_node_in_group("world")
				if w_node != null and w_node.has_method("director"):
					dir = w_node.call("director") as Node
			_atlas_book.setup(Atlas.shared(), disc, dir, _player as Player)
			_pull_book_state_from_map()
			var zid: StringName = _requested_zone if _requested_zone != &"" else _current_zone_id()
			_requested_zone = &""
			_atlas_book.open_book(zid)
			_atlas_book._open_t = 1.0
			_atlas_book.visible = true
			_atlas_book.queue_redraw()
		else:
			_atlas_book.close_book(true)
			_atlas_book.visible = false

	# 3: RiverBook
	if _river != null and _river.has_method("set_embedded_active"):
		_river.call("set_embedded_active", active and _sub == 3)

	# Pass clicks through when RiverBook (on Hud layer below) or AtlasBook is active
	mouse_filter = Control.MOUSE_FILTER_STOP if (active and (_sub == 1 or _sub == 2)) else Control.MOUSE_FILTER_IGNORE


func _canonical_map_book() -> AtlasBook:
	if not is_inside_tree():
		return null
	var mw: MapWindow = get_tree().get_first_node_in_group("map_window") as MapWindow
	if mw == null:
		return null
	var av: AtlasView = mw.atlas_view()
	return av.atlas_book() if av != null else null


func _pull_book_state_from_map() -> void:
	if _atlas_book == null or _syncing_book:
		return
	var canon: AtlasBook = _canonical_map_book()
	if canon == null:
		return
	_syncing_book = true
	_atlas_book.import_state(canon.export_state())
	_syncing_book = false


func _push_book_state_to_map() -> void:
	if _atlas_book == null or _syncing_book:
		return
	var canon: AtlasBook = _canonical_map_book()
	if canon == null:
		return
	_syncing_book = true
	canon.import_state(_atlas_book.export_state())
	_syncing_book = false


func _on_book_reward_claimed(zone_id: StringName, tier: int, reward_id: StringName) -> void:
	_push_book_state_to_map()
	if not is_inside_tree():
		return
	var mw: MapWindow = get_tree().get_first_node_in_group("map_window") as MapWindow
	if mw != null:
		mw.sync_book_reward_claimed(zone_id, tier, reward_id)


func _current_zone_id() -> StringName:
	if _player != null and is_instance_valid(_player):
		var z_id: StringName = Atlas.shared().zone_at(&"main", (_player as Node2D).global_position)
		if z_id != &"":
			return z_id
	return &"windkap"


# --- Input -----------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible or not _editing_pet:
		return
	var ke: InputEventKey = event as InputEventKey
	if ke == null or not ke.pressed:
		return
	match ke.physical_keycode:
		KEY_ESCAPE:
			_editing_pet = false
		KEY_ENTER, KEY_KP_ENTER:
			_commit_pet_rename()
		KEY_BACKSPACE:
			if not _pet_text.is_empty():
				_pet_text = _pet_text.substr(0, _pet_text.length() - 1)
		_:
			var incoming: String = ""
			if ke.ctrl_pressed and ke.physical_keycode == KEY_V:
				incoming = DisplayServer.clipboard_get()
			elif ke.unicode > 0:
				incoming = char(ke.unicode)
			var max_len: int = int(((PetRules.table()["register"] as Dictionary)["max_name"]))
			for ch: String in incoming:
				var up: String = ch.to_upper()
				if ((up >= "A" and up <= "Z") or ch in "ÄÖÜäöüß0123456789 -") and _pet_text.length() < max_len:
					_pet_text += up
	queue_redraw()
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not visible or (_sub != 1 and _sub != 2):
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = (event as InputEventMouseMotion).position
		_hover_id = ""
		for h: Dictionary in _hits:
			if (h["rect"] as Rect2).has_point(mp):
				_hover_id = String(h["id"])
				break
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_editing_pet = false
			for i: int in range(_hits.size() - 1, -1, -1):
				var h: Dictionary = _hits[i]
				if (h["rect"] as Rect2).has_point(mb.position):
					_run_action(String(h["action"]), String(h.get("arg", "")))
					accept_event()
					return


func _run_action(act: String, arg: String) -> void:
	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager if is_inside_tree() else null
	var reg: PetRegistry = PetRegistry.of(get_tree()) if is_inside_tree() else null
	match act:
		"town_build", "town_demolish", "town_move":
			var builder: BuildMode = town.build_mode() if town != null else null
			if builder != null and _player != null and town.founded:
				request_close_menu.emit()
				if not builder.active:
					builder.toggle(_player)
				if builder.active and act == "town_demolish":
					builder.set_demolish(true)
				elif builder.active and act == "town_move":
					builder.set_moving(true)
				Sfx.ui(self, "ui_click", -4.0)
		"town_name":
			if town != null:
				town.request_name(posmod(town.name_index + 1, TownRules.town_names().size()))
				Sfx.ui(self, "ui_click", -5.0)
		"town_color":
			if town != null:
				town.request_look(town.look_color + 1, town.look_emblem)
				Sfx.ui(self, "ui_click", -5.0)
		"town_emblem":
			if town != null:
				town.request_look(town.look_color, town.look_emblem + 1)
				Sfx.ui(self, "ui_click", -5.0)
		"pet_sel":
			_pet_sel = arg
			_pet_text = ""
			Sfx.ui(self, "ui_click", -5.0)
		"pet_take", "pet_release", "pet_mode":
			if reg != null and not _pet_sel.is_empty():
				reg.ask({"pet_take": "take", "pet_release": "release", "pet_mode": "mode"}[act], _pet_sel)
				Sfx.ui(self, "ui_click", -4.0)
		"pet_input":
			_editing_pet = true
			Sfx.ui(self, "ui_click", -6.0)
		"pet_rename":
			_commit_pet_rename()
	queue_redraw()


func _commit_pet_rename() -> void:
	var reg: PetRegistry = PetRegistry.of(get_tree()) if is_inside_tree() else null
	if reg != null and not _pet_sel.is_empty() and PetRegistry.clean_name(_pet_text) != "":
		reg.request_rename(_pet_sel, _pet_text)
		_pet_text = ""
		_editing_pet = false
		Sfx.ui(self, "ui_click", -4.0)


# --- Top Sub-Bar -----------------------------------------------------------------------------------------------------

func _draw_bar() -> void:
	_pill_rects.clear()
	var x: float = 0.0
	for i: int in SUB_TABS.size():
		var lbl: String = String(SUB_TABS[i]["label"])
		var w: float = float(PixelText.width(lbl)) + 18.0
		var r: Rect2 = Rect2(x, 0.0, w, 19.0)
		_pill_rects.append(r)
		MenuChrome.draw_tab_pill(_bar, r, i == _sub, 1.0 if i == _hover_sub else 0.0)
		if i == _sub:
			MenuChrome.draw_shimmer(_bar, r, _time, MenuChrome.COL_GOLD_HOT)
		MenuChrome.draw_text(_bar, lbl, Vector2(r.position.x + 9.0, r.position.y + 6.0), MenuChrome.COL_GOLD_HOT if i == _sub else MenuChrome.COL_TEXT_SOFT)
		x += w + 5.0


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mp: Vector2 = (event as InputEventMouseMotion).position
		var old: int = _hover_sub
		_hover_sub = -1
		for i: int in _pill_rects.size():
			if _pill_rects[i].has_point(mp):
				_hover_sub = i
				break
		if _hover_sub != old:
			_bar.queue_redraw()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			for i: int in _pill_rects.size():
				if _pill_rects[i].has_point(mb.position):
					if i != _sub:
						show_sub(i)
						Sfx.ui(self, "ui_click", -5.0)
					_bar.accept_event()
					return


# --- Native MenuChrome Drawing for STADT (1) & VÖGEL (2) -------------------------------------------------------------

func _draw() -> void:
	if not visible:
		return
	_hits.clear()
	var vw: float = size.x if size.x > 16.0 else 640.0
	var vh: float = size.y if size.y > 16.0 else 306.0
	if _sub == 1:
		_draw_town(vw, vh)
	elif _sub == 2:
		_draw_pets(vw, vh)


func _draw_town(vw: float, vh: float) -> void:
	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager if is_inside_tree() else null
	var top_y: float = 28.0
	var pan_h: float = vh - top_y - 8.0

	if town == null or not town.founded:
		var card: Rect2 = Rect2(roundf((vw - 392.0) * 0.5), top_y + 24.0, 392.0, 196.0)
		MenuChrome.draw_slate(self, card)
		MenuChrome.draw_corners(self, card)
		MenuChrome.draw_panel_spores(self, card, _time, 11, MenuChrome.COL_GOLD, 9, 0.65)
		var med: Rect2 = Rect2(roundf(card.get_center().x - 16.0), card.position.y + 16.0, 32.0, 32.0)
		MenuChrome.draw_cosmos(self, med)
		MenuChrome.draw_hearth_crest(self, med.position + Vector2(7.0, 7.0))
		MenuChrome.draw_text_centered(self, "SIEDLUNG & HOF", card.get_center().x, card.position.y + 56.0, MenuChrome.COL_GOLD_HOT)
		MenuChrome.draw_divider(self, card.get_center().x, card.position.y + 70.0, card.size.x - 56.0)
		MenuChrome.draw_text_centered(self, "NOCH KEINE SIEDLUNG GEGRÜNDET", card.get_center().x, card.position.y + 88.0, MenuChrome.COL_TEXT)
		var iy: float = card.position.y + 110.0
		for line: String in MenuChrome.wrap_lines("ERNEUERE DIE ALTE HÜTTE UND ERRICHTE DEN BRUNNENPLATZ, UM DEINE EIGENE SIEDLUNG AUF ALTMARK ZU GRÜNDEN. SOBALD DIE ERSTEN MAUERN STEHEN, ERWACHT DIESER REITER ZUM LEBEN.", card.size.x - 48.0):
			MenuChrome.draw_text_centered(self, line, card.get_center().x, iy, MenuChrome.COL_TEXT_SOFT)
			iy += 11.0
		return

	var left_r: Rect2 = Rect2(16.0, top_y, 300.0, pan_h)
	var right_r: Rect2 = Rect2(324.0, top_y, vw - 340.0, pan_h)
	MenuChrome.draw_slate(self, left_r)
	MenuChrome.draw_corners(self, left_r)
	MenuChrome.draw_slate(self, right_r)
	MenuChrome.draw_corners(self, right_r)

	# Left: Town Status
	var lx: float = left_r.position.x + 12.0
	var lw: float = left_r.size.x - 24.0
	var ly: float = left_r.position.y + 10.0
	TownEmblems.draw(self, town.look_emblem, Vector2(lx, ly - 1.0), 1.0, 1.0)
	MenuChrome.draw_text(self, town.town_name(), Vector2(lx + 18.0, ly + 1.0), MenuChrome.COL_GOLD)
	var lv_lbl: String = town.level_label()
	MenuChrome.draw_chip(self, Rect2(left_r.end.x - float(PixelText.width(lv_lbl)) - 22.0, ly - 1.0, float(PixelText.width(lv_lbl)) + 12.0, 13.0), lv_lbl, Color("163634"), MenuChrome.COL_TEAL, MenuChrome.COL_TEAL)
	ly += 20.0

	var next_w: float = TownRules.next_worth(town.level())
	var ratio: float = clampf(town.worth() / maxf(next_w, 1.0), 0.0, 1.0) if next_w > 0.0 else 1.0
	MenuChrome.draw_bar(self, Rect2(lx, ly, lw, 6.0), ratio, MenuChrome.COL_GOLD)
	ly += 14.0

	var finished: int = 0
	var sites: int = 0
	for sid: int in town.structures:
		var sdata: Dictionary = town.structures[sid] as Dictionary
		if bool(TownRules.piece(String(sdata.p)).get("builtin", false)):
			continue
		if int(sdata.g) >= TownManager.PROGRESS_FULL:
			finished += 1
		else:
			sites += 1
	var reach: float = 0.0
	for c: Vector3 in town.circles():
		reach = maxf(reach, Vector2(c.x, c.y).distance_to(town.center) + c.z)

	var stat_rows: Array[Array] = [
		["SIEDLUNGSWERT", "%d / %d" % [int(town.worth()), int(next_w)] if next_w >= 0.0 else str(int(town.worth()))],
		["EINWOHNER", str(town.population())],
		["BAUTEN", "%d" % finished + (" (+%d BAU)" % sites if sites > 0 else "")],
		["LICHTRADIUS", "%d KACHELN" % int(reach / 16.0)],
		["GEGRÜNDET", "TAG %d" % (town.founded_day + 1)],
	]
	for sr: Array in stat_rows:
		MenuChrome.draw_text(self, String(sr[0]), Vector2(lx, ly), MenuChrome.COL_TEXT_DIM)
		var vt: String = String(sr[1])
		MenuChrome.draw_text(self, vt, Vector2(lx + lw - float(PixelText.width(vt)), ly), MenuChrome.COL_TEXT)
		ly += 15.0

	# Right: Management & Emblem
	var rx: float = right_r.position.x + 12.0
	var rw: float = right_r.size.x - 24.0
	var ry: float = right_r.position.y + 10.0
	MenuChrome.draw_section_header(self, Vector2(rx, ry), rw, "BAUMODUS & VERWALTUNG", MenuChrome.COL_GOLD)
	ry += 18.0

	var btn_specs: Array[Array] = [
		["BAUEN ÖFFNEN", "town_build", true, false],
		["GEBÄUDE VERSETZEN", "town_move", false, false],
		["ABREISSEN", "town_demolish", false, true],
	]
	for bs: Array in btn_specs:
		var br: Rect2 = Rect2(rx, ry, rw, 20.0)
		var aid: String = String(bs[1])
		MenuChrome.draw_button(self, br, String(bs[0]), _hover_id == aid, bool(bs[2]), bool(bs[3]))
		_hits.append({"id": aid, "rect": br, "action": aid})
		ry += 25.0

	ry += 6.0
	MenuChrome.draw_section_header(self, Vector2(rx, ry), rw, "BANNER & NAME", MenuChrome.COL_TEAL)
	ry += 16.0
	var choices: Array[Array] = [
		["NAME", town.town_name(), "town_name"],
		["FARBE", TownEmblems.COLOR_NAMES[town.look_color], "town_color"],
		["WAPPEN", TownEmblems.NAMES[town.look_emblem], "town_emblem"],
	]
	for ch: Array in choices:
		var cid: String = String(ch[2])
		MenuChrome.draw_text(self, String(ch[0]), Vector2(rx, ry + 4.0), MenuChrome.COL_TEXT_DIM)
		var val_s: String = MenuChrome.fit_text(String(ch[1]), rw - 66.0)
		var cr: Rect2 = Rect2(rx + rw - 110.0, ry, 110.0, 16.0)
		MenuChrome.draw_button(self, cr, val_s, _hover_id == cid)
		_hits.append({"id": cid, "rect": cr, "action": cid})
		ry += 22.0


func _draw_pets(vw: float, vh: float) -> void:
	var reg: PetRegistry = PetRegistry.of(get_tree()) if is_inside_tree() else null
	var top_y: float = 28.0
	var pan_h: float = vh - top_y - 8.0

	if reg == null or reg.records().is_empty():
		var card: Rect2 = Rect2(roundf((vw - 392.0) * 0.5), top_y + 24.0, 392.0, 196.0)
		MenuChrome.draw_slate(self, card)
		MenuChrome.draw_corners(self, card)
		MenuChrome.draw_panel_spores(self, card, _time, 29, MenuChrome.COL_VIOLET, 9, 0.65)
		var med: Rect2 = Rect2(roundf(card.get_center().x - 16.0), card.position.y + 16.0, 32.0, 32.0)
		MenuChrome.draw_cosmos(self, med)
		MenuChrome.draw_raven_crest(self, med.position + Vector2(7.0, 7.0))
		MenuChrome.draw_text_centered(self, "GEFIEDERTE GEFÄHRTEN", card.get_center().x, card.position.y + 56.0, MenuChrome.COL_GOLD_HOT)
		MenuChrome.draw_divider(self, card.get_center().x, card.position.y + 70.0, card.size.x - 56.0)
		MenuChrome.draw_text_centered(self, "NOCH KEINE KRÄHE ODER RABE BEKANNT", card.get_center().x, card.position.y + 88.0, MenuChrome.COL_TEXT)
		var iy: float = card.position.y + 110.0
		for line: String in MenuChrome.wrap_lines("SCHLEICH DICH MIT FUTTER IN DER HAND LEISE AN WILDE KRÄHEN UND RABEN HERAN UND FÜTTERE SIE. MIT WACHSENDER BINDUNG MERKEN SIE SICH DICH UND BEGLEITEN DICH AUF REISEN.", card.size.x - 48.0):
			MenuChrome.draw_text_centered(self, line, card.get_center().x, iy, MenuChrome.COL_TEXT_SOFT)
			iy += 11.0
		return

	var list: Array[Dictionary] = reg.records()
	var found: bool = false
	for e: Dictionary in list:
		if String(e["key"]) == _pet_sel:
			found = true
			break
	if not found:
		_pet_sel = String(list[0]["key"])

	var left_r: Rect2 = Rect2(16.0, top_y, 212.0, pan_h)
	var right_r: Rect2 = Rect2(236.0, top_y, vw - 252.0, pan_h)
	MenuChrome.draw_slate(self, left_r)
	MenuChrome.draw_corners(self, left_r)
	MenuChrome.draw_slate(self, right_r)
	MenuChrome.draw_corners(self, right_r)

	# Left: Bird list
	var lx: float = left_r.position.x + 10.0
	var lw: float = left_r.size.x - 20.0
	MenuChrome.draw_section_header(self, Vector2(lx, left_r.position.y + 10.0), lw, "BEKANNTE (%d)" % list.size(), MenuChrome.COL_GOLD)
	var me: int = multiplayer.get_unique_id()
	var ly: float = left_r.position.y + 26.0
	for e: Dictionary in list:
		if ly + 26.0 > left_r.end.y - 8.0:
			break
		var pkey: String = String(e["key"])
		var sel: bool = (pkey == _pet_sel)
		var is_comp: bool = (reg.companion_of(me) == pkey)
		var er: Rect2 = Rect2(lx, ly, lw, 24.0)
		if sel:
			MenuChrome.draw_gold(self, er)
		else:
			MenuChrome.draw_inset(self, er)
		var nm: String = MenuChrome.fit_text(String(e["n"]), lw - 54.0)
		MenuChrome.draw_text(self, nm, Vector2(er.position.x + 7.0, er.position.y + 8.0), MenuChrome.COL_GOLD_HOT if sel else MenuChrome.COL_TEXT)
		var tag: String = "BEI DIR" if is_comp else ("KRÄHE" if String(e["sp"]) == "crow" else "RABE")
		MenuChrome.draw_chip(self, Rect2(er.end.x - 42.0, er.position.y + 6.0, 36.0, 12.0), tag, Color("153835") if is_comp else Color("1a152e"), MenuChrome.COL_TEAL if is_comp else Color("4a3e6b"), MenuChrome.COL_TEAL if is_comp else MenuChrome.COL_TEXT_DIM)
		_hits.append({"id": "pet_" + pkey, "rect": er, "action": "pet_sel", "arg": pkey})
		ly += 27.0

	# Right: Bird Detail
	var rec: Dictionary = reg.record(_pet_sel)
	var bp: float = reg.bp_of(_pet_sel, me)
	var stage: int = PetRules.stage_of(bp)
	var seen: Vector3 = reg.seen_of(_pet_sel)
	var ago: int = maxi(0, TimeManager.day - int(seen.z))
	var rings: Array = (PetRules.table()["register"] as Dictionary)["ring_names"] as Array
	var rx: float = right_r.position.x + 12.0
	var rw: float = right_r.size.x - 24.0
	var ry: float = right_r.position.y + 10.0

	MenuChrome.draw_text(self, String(rec["n"]).to_upper(), Vector2(rx, ry), MenuChrome.COL_GOLD)
	var sp_lbl: String = "KRÄHE" if String(rec["sp"]) == "crow" else "RABE"
	MenuChrome.draw_chip(self, Rect2(right_r.end.x - 54.0, ry - 1.0, 42.0, 13.0), sp_lbl, Color("1f1836"), MenuChrome.COL_VIOLET, MenuChrome.COL_VIOLET)
	ry += 16.0

	var next_bp: float = float(PetRules.stage_start(stage + 1)) if stage < 5 else maxf(bp, 1.0)
	MenuChrome.draw_text(self, "BINDUNG · %s" % PetRules.stage_name(stage), Vector2(rx, ry), MenuChrome.COL_TEAL)
	var bp_s: String = "%d" % int(bp) if stage >= 5 else "%d / %d" % [int(bp), int(next_bp)]
	MenuChrome.draw_text(self, bp_s, Vector2(rx + rw - float(PixelText.width(bp_s)), ry), MenuChrome.COL_TEXT)
	ry += 11.0
	MenuChrome.draw_bar(self, Rect2(rx, ry, rw, 6.0), clampf(bp / maxf(next_bp, 1.0), 0.0, 1.0), MenuChrome.COL_TEAL)
	ry += 14.0

	var info_rows: Array[Array] = [
		["RINGFARBE", String(rings[int(rec["ring"]) % rings.size()])],
		["BEKANNT SEIT", "TAG %d" % (int(rec["rd"]) + 1)],
		["ZULETZT GESEHEN", "HEUTE" if ago == 0 else "VOR %d TAGEN" % ago],
		["POSITION", "%d, %d" % [int(seen.x / 16.0), int(seen.y / 16.0)]],
	]
	for ir: Array in info_rows:
		MenuChrome.draw_text(self, String(ir[0]), Vector2(rx, ry), MenuChrome.COL_TEXT_DIM)
		var iv: String = String(ir[1])
		MenuChrome.draw_text(self, iv, Vector2(rx + rw - float(PixelText.width(iv)), ry), MenuChrome.COL_TEXT)
		ry += 14.0

	var companion_cfg: Dictionary = PetRules.table()["companion"] as Dictionary
	if stage >= int(companion_cfg["stage"]):
		ry += 4.0
		if reg.companion_of(me) == _pet_sel:
			var m_btn: Rect2 = Rect2(rx, ry, floorf(rw * 0.54), 19.0)
			var r_btn: Rect2 = Rect2(m_btn.end.x + 6.0, ry, rw - m_btn.size.x - 6.0, 19.0)
			MenuChrome.draw_button(self, m_btn, "MODUS: %s" % reg.mode_name(me), _hover_id == "pet_mode", true)
			MenuChrome.draw_button(self, r_btn, "ENTLASSEN", _hover_id == "pet_release", false, true)
			_hits.append({"id": "pet_mode", "rect": m_btn, "action": "pet_mode"})
			_hits.append({"id": "pet_release", "rect": r_btn, "action": "pet_release"})
		elif reg.peer_of_companion(_pet_sel) == 0:
			var t_btn: Rect2 = Rect2(rx, ry, rw, 19.0)
			MenuChrome.draw_button(self, t_btn, "ALS GEFÄHRTE MITNEHMEN", _hover_id == "pet_take", true)
			_hits.append({"id": "pet_take", "rect": t_btn, "action": "pet_take"})
		ry += 25.0

	# Rename bar at bottom
	var ren_y: float = right_r.end.y - 34.0
	var inp_w: float = rw - 92.0
	var inp_r: Rect2 = Rect2(rx, ren_y, inp_w, 19.0)
	MenuChrome.draw_inset(self, inp_r)
	if _editing_pet:
		draw_rect(Rect2(inp_r.position.x + 2.0, inp_r.end.y - 2.0, inp_r.size.x - 4.0, 1.0), MenuChrome.COL_TEAL)
	var p_shown: String = _pet_text if (not _pet_text.is_empty() or _editing_pet) else "NEUER NAME..."
	MenuChrome.draw_text(self, MenuChrome.fit_text(p_shown, inp_w - 10.0), Vector2(inp_r.position.x + 6.0, inp_r.position.y + 6.0), MenuChrome.COL_TEXT if not _pet_text.is_empty() else MenuChrome.COL_TEXT_DIM)
	_hits.append({"id": "pet_input", "rect": inp_r, "action": "pet_input"})

	var ok_r: Rect2 = Rect2(inp_r.end.x + 6.0, ren_y, 86.0, 19.0)
	MenuChrome.draw_button(self, ok_r, "UMBENENNEN", _hover_id == "pet_rename", not _pet_text.is_empty())
	_hits.append({"id": "pet_rename", "rect": ok_r, "action": "pet_rename"})
