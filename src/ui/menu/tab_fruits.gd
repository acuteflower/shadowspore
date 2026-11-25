class_name FruitCodexTab
extends Control
## Dedicated 'FRÜCHTE' page of the unified GameMenu ('Der Feldcodex').
## 3-column Shadowspore Herbarium & Spore Blessings layout (fits 640x306 stage):
##  - Left (148 px): Global count, selectable Zone list, and 5 Bioluminescent Family tallies
##  - Center (256 px): Interactive moss-niche grid of real procedural `ShadowFruitArt` sprites + live
##    2x waking/blinking preview card (plays each fruit's pentatonic chime on click!) + 'AUF ATLAS' jump
##  - Right (192 px): Global Sporen-Schwellen milestones (directly claimable!) + active Zone Blessings

signal jump_to_atlas(world_tile: Vector2, zone_id: StringName)

const CHIME_WAV: AudioStream = preload("res://assets/audio/waystone/chime_b.wav")
const CLAIM_WAV: AudioStream = preload("res://assets/audio/sfx/item_pickup.wav")

var _player: Node = null
var _vt: VeilThreads = null
var _selected_zone: StringName = &"windkap"
var _selected_idx: int = 0
var _hover_zone: int = -1
var _hover_slot: int = -1
var _hover_claim_id: String = ""
var _hover_atlas_btn: bool = false
var _milestone_scroll: int = 0

var _time: float = 0.0
var _wake_t: float = 0.0 ## lively waking wiggle timer when selecting a collected fruit
var _claim_flash_t: float = 0.0
var _bursts: Array[Dictionary] = []

# Cached hit rects rebuilt during draw
var _zone_rects: Array[Dictionary] = [] ## {rect, zone_id}
var _slot_rects: Array[Dictionary] = [] ## {rect, index, entry}
var _claim_rects: Array[Dictionary] = [] ## {rect, id, endless}
var _atlas_btn_rect: Rect2 = Rect2()
var _ms_up_rect: Rect2 = Rect2()
var _ms_dn_rect: Rect2 = Rect2()


func bind(player: Node) -> void:
	_player = player
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh_vt()


func on_tab_opened() -> void:
	_refresh_vt()
	_wake_t = 0.7
	if _vt != null:
		var zones: Array[StringName] = _vt.zones_with_fruits()
		if not zones.is_empty() and not zones.has(_selected_zone):
			_selected_zone = zones[0]
	queue_redraw()


func _refresh_vt() -> void:
	if is_inside_tree():
		_vt = VeilThreads.of(get_tree())
		if _vt != null and not _vt.changed.is_connected(queue_redraw):
			_vt.changed.connect(queue_redraw)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _wake_t > 0.0:
		_wake_t = maxf(_wake_t - delta, 0.0)
	if _claim_flash_t > 0.0:
		_claim_flash_t = maxf(_claim_flash_t - delta, 0.0)
	for i: int in range(_bursts.size() - 1, -1, -1):
		_bursts[i]["age"] = float(_bursts[i]["age"]) + delta
		if float(_bursts[i]["age"]) >= float(_bursts[i]["max_age"]):
			_bursts.remove_at(i)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = (event as InputEventMouseMotion).position
		_update_hover(mp)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_milestone_scroll = maxi(0, _milestone_scroll - 1)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_milestone_scroll += 1
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_click(mb.position)
			accept_event()


func _update_hover(mp: Vector2) -> void:
	_hover_zone = -1
	for i: int in _zone_rects.size():
		if (_zone_rects[i]["rect"] as Rect2).has_point(mp):
			_hover_zone = i
			break
	_hover_slot = -1
	for i: int in _slot_rects.size():
		if (_slot_rects[i]["rect"] as Rect2).has_point(mp):
			_hover_slot = i
			break
	_hover_claim_id = ""
	for d: Dictionary in _claim_rects:
		if (d["rect"] as Rect2).has_point(mp):
			_hover_claim_id = String(d["id"])
			break
	_hover_atlas_btn = _atlas_btn_rect.has_area() and _atlas_btn_rect.has_point(mp)


func _handle_click(mp: Vector2) -> void:
	for d: Dictionary in _zone_rects:
		if (d["rect"] as Rect2).has_point(mp):
			_selected_zone = d["zone_id"] as StringName
			_selected_idx = 0
			_wake_t = 0.65
			queue_redraw()
			return
	for d: Dictionary in _slot_rects:
		if (d["rect"] as Rect2).has_point(mp):
			_selected_idx = int(d["index"])
			var entry: Dictionary = d["entry"] as Dictionary
			if bool(entry.get("collected", false)):
				_wake_t = 0.95
				var art: Dictionary = ShadowFruitArt.build(String(entry.get("id", "")))
				_play_ui_sound(CHIME_WAV, -8.0, float(art.get("pitch", 1.0)))
			queue_redraw()
			return
	if _atlas_btn_rect.has_area() and _atlas_btn_rect.has_point(mp):
		if _selected_idx >= 0 and _selected_idx < _slot_rects.size():
			var entry: Dictionary = _slot_rects[_selected_idx]["entry"] as Dictionary
			var wt: Vector2 = entry.get("tile", Vector2.ZERO) as Vector2
			if wt != Vector2.ZERO:
				jump_to_atlas.emit(wt, _selected_zone)
		return
	if _ms_up_rect.has_area() and _ms_up_rect.has_point(mp):
		_milestone_scroll = maxi(0, _milestone_scroll - 1)
		queue_redraw()
		return
	if _ms_dn_rect.has_area() and _ms_dn_rect.has_point(mp):
		_milestone_scroll += 1
		queue_redraw()
		return
	for d: Dictionary in _claim_rects:
		if (d["rect"] as Rect2).has_point(mp) and _vt != null:
			if bool(d.get("endless", false)):
				_vt.request_claim_endless()
			else:
				_vt.request_claim_milestone(String(d["id"]))
			_claim_flash_t = 0.55
			_bursts.append({"pos": (d["rect"] as Rect2).get_center(), "age": 0.0, "max_age": 0.62, "col": MenuChrome.COL_GOLD_HOT})
			_play_ui_sound(CHIME_WAV, -5.0, 1.15)
			_play_ui_sound(CLAIM_WAV, -5.0, 1.06)
			queue_redraw()
			return


func _play_ui_sound(stream: AudioStream, vol_db: float, pitch: float) -> void:
	if stream == null or not is_inside_tree():
		return
	var a: AudioStreamPlayer = AudioStreamPlayer.new()
	a.stream = stream
	a.volume_db = vol_db
	a.pitch_scale = pitch
	a.finished.connect(a.queue_free)
	add_child(a)
	a.play()


func _draw() -> void:
	_zone_rects.clear()
	_slot_rects.clear()
	_claim_rects.clear()
	_atlas_btn_rect = Rect2()
	_ms_up_rect = Rect2()
	_ms_dn_rect = Rect2()

	if _vt == null:
		_refresh_vt()

	var w: float = size.x
	var h: float = size.y
	if w < 100.0 or h < 80.0:
		return

	var pad: float = 12.0
	var gap: float = 8.0
	var col1_w: float = 148.0
	var col3_w: float = 196.0
	var col2_w: float = maxf(w - pad * 2.0 - gap * 2.0 - col1_w - col3_w, 180.0)
	var top_y: float = 8.0
	var col_h: float = h - 16.0

	var r_left: Rect2 = Rect2(pad, top_y, col1_w, col_h)
	var r_mid: Rect2 = Rect2(r_left.end.x + gap, top_y, col2_w, col_h)
	var r_right: Rect2 = Rect2(r_mid.end.x + gap, top_y, col3_w, col_h)

	_draw_left_zones(r_left)
	_draw_center_herbarium(r_mid)
	_draw_right_rewards(r_right)
	MenuChrome.draw_burst_rings(self, _bursts)


func _draw_left_zones(rect: Rect2) -> void:
	MenuChrome.draw_slate(self, rect)
	var x: float = rect.position.x + 10.0
	var pw: float = rect.size.x - 20.0
	var y: float = rect.position.y + 10.0

	var total_done: int = _vt.collected_count() if _vt != null else 0
	var total_all: int = maxi(_vt.total_count() if _vt != null else 8, 1)

	MenuChrome.draw_icon(self, "fruits", Vector2(x, y - 2.0), true)
	MenuChrome.draw_text(self, "GESAMT", Vector2(x + 16.0, y), MenuChrome.COL_GOLD)
	var tot_s: String = "%d / %d" % [total_done, total_all]
	MenuChrome.draw_text(self, tot_s, Vector2(x + pw - float(PixelText.width(tot_s)), y), MenuChrome.COL_TEAL)
	y += 13.0
	MenuChrome.draw_bar(self, Rect2(x, y, pw, 6.0), float(total_done) / float(total_all), MenuChrome.COL_TEAL)
	y += 13.0

	MenuChrome.draw_text(self, "ZONEN", Vector2(x, y), MenuChrome.COL_TEXT_DIM)
	y += 11.0

	var zones: Array[StringName] = _vt.zones_with_fruits() if _vt != null else [&"windkap"]
	if zones.is_empty():
		zones = [&"windkap"]
	var max_zone_rows: int = 5
	for i: int in mini(zones.size(), max_zone_rows):
		var zid: StringName = zones[i]
		var zr: Rect2 = Rect2(x - 2.0, y, pw + 4.0, 18.0)
		_zone_rects.append({"rect": zr, "zone_id": zid})
		var sel: bool = zid == _selected_zone
		var hov: bool = i == _hover_zone
		if sel:
			MenuChrome.draw_parchment(self, zr)
		elif hov:
			MenuChrome.draw_inset(self, zr)
		var z_obj: Atlas.Zone = Atlas.shared().zone(zid)
		var zname: String = z_obj.name.to_upper() if (z_obj != null and not z_obj.name.is_empty()) else String(zid).to_upper()
		var zd: int = _vt.collected_in_zone(zid) if _vt != null else 0
		var zt: int = _vt.total_in_zone(zid) if _vt != null else 8
		var full: bool = zt > 0 and zd >= zt
		var label_col: Color = MenuChrome.COL_GOLD_HOT if full else (MenuChrome.COL_TEXT if sel else MenuChrome.COL_TEXT_SOFT)
		var prefix: String = "> " if sel else "  "
		MenuChrome.draw_text(self, _fit(prefix + zname, int(pw) - 34), Vector2(x + 3.0, y + 5.0), label_col)
		var cnt_s: String = "%d/%d" % [zd, zt]
		MenuChrome.draw_text(self, cnt_s, Vector2(x + pw - float(PixelText.width(cnt_s)) - 2.0, y + 5.0), MenuChrome.COL_TEAL if full else MenuChrome.COL_TEXT_DIM)
		y += 20.0

	# Bottom section: 5 Bioluminescent Families
	var fam_y: float = rect.end.y - 96.0
	MenuChrome.draw_divider(self, rect.get_center().x, fam_y - 6.0, pw)
	fam_y += 5.0
	MenuChrome.draw_text(self, "5 SPOREN-FAMILIEN", Vector2(x, fam_y), MenuChrome.COL_GOLD)
	fam_y += 12.0
	var f_counts: Dictionary = _vt.family_counts() if _vt != null else {}
	for fi: int in ShadowFruitArt.FAMILY_IDS.size():
		var fid: String = ShadowFruitArt.FAMILY_IDS[fi]
		var fname: String = ShadowFruitArt.FAMILY_NAMES[fi]
		var fcol: Color = (ShadowFruitArt.ACCENTS[fi])[2] as Color
		var fc: int = int(f_counts.get(fid, 0))
		draw_rect(Rect2(x + 1.0, fam_y + 1.0, 5.0, 5.0), MenuChrome.COL_OUTLINE)
		draw_rect(Rect2(x + 2.0, fam_y + 2.0, 3.0, 3.0), fcol if fc > 0 else fcol.darkened(0.55))
		MenuChrome.draw_text(self, _fit(fname, int(pw) - 24), Vector2(x + 10.0, fam_y), MenuChrome.COL_TEXT_SOFT if fc > 0 else MenuChrome.COL_TEXT_DIM)
		var cs: String = str(fc)
		MenuChrome.draw_text(self, cs, Vector2(x + pw - float(PixelText.width(cs)), fam_y), fcol if fc > 0 else MenuChrome.COL_TEXT_DIM)
		fam_y += 14.0


func _draw_center_herbarium(rect: Rect2) -> void:
	MenuChrome.draw_slate(self, rect)
	MenuChrome.draw_corners(self, rect, 0.72)
	var x: float = rect.position.x + 12.0
	var pw: float = rect.size.x - 24.0
	var y: float = rect.position.y + 10.0

	var z_obj: Atlas.Zone = Atlas.shared().zone(_selected_zone)
	var zname: String = z_obj.name.to_upper() if (z_obj != null and not z_obj.name.is_empty()) else String(_selected_zone).to_upper()
	var entries: Array[Dictionary] = _vt.entries_for_zone(_selected_zone) if _vt != null else []
	var zd: int = _vt.collected_in_zone(_selected_zone) if _vt != null else 0
	var zt: int = entries.size()

	MenuChrome.draw_text(self, "%s · HERBARIUM" % zname, Vector2(x, y), MenuChrome.COL_GOLD)
	var prog_s: String = "%d / %d" % [zd, zt]
	MenuChrome.draw_text(self, prog_s, Vector2(x + pw - float(PixelText.width(prog_s)), y), MenuChrome.COL_TEAL)
	y += 14.0

	# Moss-niche grid (4 columns x up to 3 rows -> fits 8..12 fruits with generous breathing room)
	var cols: int = 4
	var cell: float = 42.0
	var cell_gap: float = 8.0
	var grid_w: float = float(cols) * cell + float(cols - 1) * cell_gap
	var gx0: float = roundf(rect.get_center().x - grid_w * 0.5)
	var shown: int = mini(entries.size(), 12)
	for i: int in shown:
		var entry: Dictionary = entries[i]
		var col_i: int = i % cols
		var row_i: int = i / cols
		var cr: Rect2 = Rect2(gx0 + float(col_i) * (cell + cell_gap), y + float(row_i) * (cell + 6.0), cell, cell)
		_slot_rects.append({"rect": cr, "index": i, "entry": entry})
		var fid: String = String(entry.get("id", "fruit_%d" % i))
		var art: Dictionary = ShadowFruitArt.build(fid)
		var accent: Color = art["accent"] as Color
		var is_col: bool = bool(entry.get("collected", false))
		var is_sel: bool = i == _selected_idx
		var is_hov: bool = i == _hover_slot
		MenuChrome.draw_moss_niche(self, cr, is_sel, is_hov, accent if is_col else MenuChrome.COL_VIOLET)

		if is_col:
			var bodies: Array = art["fruit_bodies"] as Array
			var glows: Array = art["fruit_glows"] as Array
			var ph: float = fposmod(float(i) * 1.13, TAU)
			var fr: int = 0
			if is_sel and _wake_t > 0.0:
				fr = [1, 2, 3, 2, 0][int(_time * 10.0) % 5]
			elif is_hov:
				fr = 2 if sin(_time * 8.0) > 0.2 else 0
			elif fposmod(_time * 0.35 + ph, 1.0) > 0.92:
				fr = 2
			var hop: float = -absf(sin(_time * 9.0)) * 3.0 if (is_sel and _wake_t > 0.0) else roundf(sin(_time * 2.2 + ph) * 1.0)
			var b_tex: Texture2D = bodies[fr] as Texture2D
			var g_tex: Texture2D = glows[fr] as Texture2D
			# Soft family-tinted bioluminescent pedestal glow beneath the specimen (no bright green bar)
			draw_rect(Rect2(roundf(cr.get_center().x - 8.0), roundf(cr.end.y - 6.0), 16.0, 2.0), Color(accent.r, accent.g, accent.b, 0.24))
			draw_rect(Rect2(roundf(cr.get_center().x - 5.0), roundf(cr.end.y - 5.0), 10.0, 1.0), Color(accent.r, accent.g, accent.b, 0.42))
			var dpos: Vector2 = Vector2(roundf(cr.get_center().x - 10.0), roundf(cr.get_center().y - 10.0 + hop))
			draw_texture(b_tex, dpos)
			draw_texture(g_tex, dpos)
			MenuChrome.draw_text(self, "%02d" % (i + 1), Vector2(cr.position.x + 3.0, cr.position.y + 3.0), accent)
		else:
			# Buried mysterious silhouette mound
			var pb: Texture2D = art["planted_body"] as Texture2D
			var dpos2: Vector2 = Vector2(roundf(cr.get_center().x - 12.0), roundf(cr.get_center().y - 9.0))
			draw_texture(pb, dpos2, Color(0.32, 0.28, 0.45, 0.65))
			MenuChrome.draw_text(self, "%02d" % (i + 1), Vector2(cr.position.x + 3.0, cr.position.y + 3.0), MenuChrome.COL_TEXT_DIM)
			MenuChrome.draw_text(self, "?", Vector2(cr.end.x - 9.0, cr.position.y + 3.0), MenuChrome.COL_VIOLET, 0.7)

	# Selected Fruit Detail Card at bottom of center column
	var detail_h: float = 114.0
	var detail_r: Rect2 = Rect2(x, rect.end.y - detail_h - 10.0, pw, detail_h)
	MenuChrome.draw_parchment(self, detail_r)

	if entries.is_empty():
		MenuChrome.draw_text(self, "KEINE SCHATTENFRÜCHTE IN DIESER ZONE", detail_r.position + Vector2(10, 48), MenuChrome.COL_TEXT_DIM)
		return

	var idx: int = clampi(_selected_idx, 0, entries.size() - 1)
	var sel_e: Dictionary = entries[idx]
	var sel_id: String = String(sel_e.get("id", ""))
	var sel_col: bool = bool(sel_e.get("collected", false))
	var sel_trait: String = String(sel_e.get("trait", "calm"))
	var sel_art: Dictionary = ShadowFruitArt.build(sel_id)
	var sel_acc: Color = sel_art["accent"] as Color

	# Live 2x fruit preview well on the left of the detail card
	var well: Rect2 = Rect2(detail_r.position.x + 10.0, detail_r.position.y + 12.0, 58.0, 68.0)
	MenuChrome.draw_cosmos(self, well)
	MenuChrome.draw_panel_spores(self, well, _time, 37 + idx, sel_acc if sel_col else MenuChrome.COL_VIOLET, 7, 0.85)
	if sel_col:
		var bodies2: Array = sel_art["fruit_bodies"] as Array
		var glows2: Array = sel_art["fruit_glows"] as Array
		var fr2: int = [1, 2, 3, 2, 0][int(_time * 9.0) % 5] if _wake_t > 0.0 else (2 if fposmod(_time * 0.45, 1.0) > 0.88 else 0)
		var hop2: float = -absf(sin(_time * 10.0)) * 5.0 if _wake_t > 0.0 else sin(_time * 2.4) * 1.5
		var dst: Rect2 = Rect2(roundf(well.get_center().x - 20.0), roundf(well.get_center().y - 24.0 + hop2), 40.0, 48.0)
		draw_texture_rect(bodies2[fr2] as Texture2D, dst, false)
		draw_texture_rect(glows2[fr2] as Texture2D, dst, false)
	else:
		var dst_u: Rect2 = Rect2(roundf(well.get_center().x - 24.0), roundf(well.get_center().y - 24.0), 48.0, 48.0)
		draw_texture_rect(sel_art["planted_body"] as Texture2D, dst_u, false, Color(0.45, 0.40, 0.62, 0.72))
		MenuChrome.draw_lock(self, Vector2(well.get_center().x - 6.0, well.get_center().y - 6.0), 0.75)

	# Metadata on right of preview well
	var tx: float = well.end.x + 10.0
	var tw: float = detail_r.end.x - tx - 10.0
	var ty: float = detail_r.position.y + 12.0
	var header: String = "SCHATTENFRUCHT %02d" % (idx + 1)
	MenuChrome.draw_text(self, header, Vector2(tx, ty), sel_acc if sel_col else MenuChrome.COL_TEXT_SOFT)
	ty += 12.0

	var fam_str: String = String(sel_art["family_name"]) if sel_col else "NOCH VERBORGEN"
	MenuChrome.draw_text(self, fam_str, Vector2(tx, ty), MenuChrome.COL_GOLD if sel_col else MenuChrome.COL_TEXT_DIM)
	ty += 11.0
	MenuChrome.draw_text(self, ShadowFruitArt.trait_label(sel_trait), Vector2(tx, ty), MenuChrome.COL_TEAL if sel_col else MenuChrome.COL_VIOLET)
	ty += 13.0

	var hint_s: String = String(sel_e.get("hint", "Verborgene Schattenfrucht"))
	for line: String in _wrap(hint_s, int(tw)):
		MenuChrome.draw_text(self, line, Vector2(tx, ty), MenuChrome.COL_TEXT_SOFT)
		ty += 10.0
		if ty > detail_r.end.y - 24.0:
			break

	# Bottom-right button: 'AUF ATLAS ZEIGEN' (only for collected fruits so unfound ones stay an adventure!)
	if sel_col:
		var btn_w: float = 110.0
		var btn_r: Rect2 = Rect2(detail_r.end.x - btn_w - 10.0, detail_r.end.y - 22.0, btn_w, 16.0)
		_atlas_btn_rect = btn_r
		MenuChrome.draw_tab_pill(self, btn_r, _hover_atlas_btn, 1.0 if _hover_atlas_btn else 0.0)
		var lbl: String = "AUF ATLAS ZEIGEN"
		MenuChrome.draw_text(self, lbl, Vector2(btn_r.get_center().x - float(PixelText.width(lbl)) * 0.5, btn_r.position.y + 4.0), MenuChrome.COL_GOLD_HOT if _hover_atlas_btn else MenuChrome.COL_TEAL)


func _draw_right_rewards(rect: Rect2) -> void:
	MenuChrome.draw_slate(self, rect)
	var x: float = rect.position.x + 10.0
	var pw: float = rect.size.x - 20.0
	var y: float = rect.position.y + 10.0

	MenuChrome.draw_text(self, "SPOREN-SCHWELLEN", Vector2(x, y), MenuChrome.COL_GOLD)
	# Tiny scroll arrows if list > 4
	var ms_list: Array[Dictionary] = _vt.milestones_status() if _vt != null else []
	var max_vis: int = 4
	var max_scroll: int = maxi(0, ms_list.size() - max_vis)
	_milestone_scroll = clampi(_milestone_scroll, 0, max_scroll)
	if max_scroll > 0:
		var up_r: Rect2 = Rect2(x + pw - 26.0, y - 2.0, 12.0, 11.0)
		var dn_r: Rect2 = Rect2(x + pw - 12.0, y - 2.0, 12.0, 11.0)
		_ms_up_rect = up_r
		_ms_dn_rect = dn_r
		MenuChrome.draw_text(self, "^", up_r.position + Vector2(3, 2), MenuChrome.COL_GOLD if _milestone_scroll > 0 else MenuChrome.COL_TEXT_DIM)
		MenuChrome.draw_text(self, "v", dn_r.position + Vector2(3, 2), MenuChrome.COL_GOLD if _milestone_scroll < max_scroll else MenuChrome.COL_TEXT_DIM)
	y += 13.0

	var total_done: int = _vt.collected_count() if _vt != null else 0
	for i: int in range(_milestone_scroll, mini(_milestone_scroll + max_vis, ms_list.size())):
		var m: Dictionary = ms_list[i]
		var mid: String = String(m.get("id", ""))
		var req: int = int(m.get("count", 0))
		var reached: bool = bool(m.get("reached", false))
		var claimed: bool = bool(m.get("claimed", false))
		var claimable: bool = reached and not claimed
		var card: Rect2 = Rect2(x, y, pw, 36.0)

		if claimable:
			MenuChrome.draw_gold(self, card)
			MenuChrome.draw_shimmer(self, card, _time, MenuChrome.COL_GOLD_HOT)
			_claim_rects.append({"rect": card, "id": mid, "endless": false})
		elif claimed:
			MenuChrome.draw_parchment(self, card, 0.90)
		else:
			MenuChrome.draw_inset(self, card, 0.92)

		var title_col: Color = MenuChrome.COL_GOLD_HOT if claimable else (MenuChrome.COL_TEAL if claimed else MenuChrome.COL_TEXT_SOFT)
		MenuChrome.draw_text(self, _fit(String(m.get("title", "")), int(pw) - 42), Vector2(x + 7.0, y + 6.0), title_col)
		var status_s: String = "EINLÖSEN!" if claimable else ("AKTIV" if claimed else "%d/%d" % [mini(total_done, req), req])
		var st_col: Color = MenuChrome.COL_GOLD_HOT if claimable else (MenuChrome.COL_TEAL if claimed else MenuChrome.COL_TEXT_DIM)
		MenuChrome.draw_text(self, status_s, Vector2(x + pw - float(PixelText.width(status_s)) - 6.0, y + 6.0), st_col)

		MenuChrome.draw_text(self, _fit(String(m.get("desc", "")), int(pw) - 14), Vector2(x + 7.0, y + 17.0), MenuChrome.COL_TEXT_SOFT if (claimed or claimable) else MenuChrome.COL_TEXT_DIM)
		if not claimed:
			MenuChrome.draw_bar(self, Rect2(x + 7.0, y + 27.0, pw - 14.0, 4.0), float(total_done) / float(maxi(req, 1)), MenuChrome.COL_GOLD if claimable else MenuChrome.COL_VIOLET)
		y += 40.0

	# Bottom section: Active Zone Blessings (50% & 100%)
	var bz_y: float = rect.end.y - 84.0
	MenuChrome.draw_divider(self, rect.get_center().x, bz_y - 5.0, pw)
	bz_y += 6.0
	var zb: Dictionary = _vt.zone_blessing_status(_selected_zone) if _vt != null else {}
	MenuChrome.draw_text(self, "ZONEN-SEGEN", Vector2(x, bz_y), MenuChrome.COL_GOLD)
	bz_y += 12.0

	var half_ok: bool = bool(zb.get("half_unlocked", false))
	var full_ok: bool = bool(zb.get("full_unlocked", false))
	MenuChrome.draw_text(self, ("* 50%% · " if half_ok else "o 50%% · ") + _fit(String(zb.get("half_name", "ERWACHTER BODEN")), int(pw) - 38), Vector2(x, bz_y), MenuChrome.COL_TEAL if half_ok else MenuChrome.COL_TEXT_DIM)
	bz_y += 10.0
	MenuChrome.draw_text(self, _fit(String(zb.get("half_desc", "")), int(pw) - 4), Vector2(x + 6.0, bz_y), MenuChrome.COL_TEXT_SOFT if half_ok else MenuChrome.COL_TEXT_DIM)
	bz_y += 14.0

	MenuChrome.draw_text(self, ("* 100%% · " if full_ok else "o 100%% · ") + _fit(String(zb.get("full_name", "GEHEILTER BODEN")), int(pw) - 44), Vector2(x, bz_y), MenuChrome.COL_GOLD_HOT if full_ok else MenuChrome.COL_TEXT_DIM)
	bz_y += 10.0
	MenuChrome.draw_text(self, _fit(String(zb.get("full_desc", "")), int(pw) - 4), Vector2(x + 6.0, bz_y), MenuChrome.COL_TEXT_SOFT if full_ok else MenuChrome.COL_TEXT_DIM)


func _fit(text: String, max_px: int) -> String:
	if PixelText.width(text) <= max_px:
		return text
	var s: String = text
	while s.length() > 3 and PixelText.width(s + "...") > max_px:
		s = s.left(s.length() - 1)
	return s + "..."


func _wrap(text: String, max_px: int) -> Array[String]:
	var lines: Array[String] = []
	var words: PackedStringArray = text.split(" ", false)
	var cur: String = ""
	for word: String in words:
		var cand: String = word if cur.is_empty() else (cur + " " + word)
		if PixelText.width(cand) <= max_px:
			cur = cand
		else:
			if not cur.is_empty():
				lines.append(cur)
			cur = word
	if not cur.is_empty():
		lines.append(cur)
	return lines
