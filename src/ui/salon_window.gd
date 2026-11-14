class_name SalonWindow
extends BoardWindow
## The open-air salon's look window (`docs/salon_konzept.md`, `SalonSeat`): opens on the right like NPC shops while framing Ellie and the glowing mirror
## on the left. Tabs:
##  - FRISUR: unlocked hairstyles (currently Ellie's base cut, with world-found hairstyles plugging in cleanly)
##  - OUTFIT: unlocked outfits (currently her active Reisegewand, with world-found outfits plugging in cleanly)
##  - FÄRBEN: categorized list of Hair and Outfit dyes with live mirror preview and host-authoritative commits.

const INK: Color = Color("100716")

var seat: BenchSeat

var _last_focus: int = -1
var _last_tab: int = -1
var _dye_collapsed: Dictionary = {} ## String section ("hair" / "outfit") -> bool
var _icon_cache: Dictionary = {} ## String cache key -> ImageTexture


static func open(tree: SceneTree, for_player: Player, for_town: TownManager, for_seat: BenchSeat) -> SalonWindow:
	if tree.get_first_node_in_group("board_window") != null or for_player == null or for_town == null or for_seat == null:
		return null
	var window: SalonWindow = SalonWindow.new()
	window.seat = for_seat
	tree.root.add_child(window)
	window.setup_board(for_player, for_town)
	return window


func _setup_board() -> void:
	add_to_group("salon_window")
	title = "FREILUFTSALON"
	tabs.append({"id": "hair", "name": "FRISUR", "kind": "hair"})
	tabs.append({"id": "outfit", "name": "OUTFIT", "kind": "outfit"})
	tabs.append({"id": "dye", "name": "FÄRBEN", "kind": "dye"})
	var seat_mid: Vector2 = seat.seat_position() + Vector2(0.0, -18.0)
	var mirror_at: Vector2 = seat.call("mirror_point") as Vector2 if seat.has_method("mirror_point") else seat_mid
	focus_world = seat_mid.lerp(mirror_at, 0.45) + Vector2(-6.0, 2.0)
	var app: AppearanceComponent = _appearance()
	if app != null:
		app.changed.connect(_on_appearance_changed)


func setup_board(for_player: Player, for_town: TownManager) -> void:
	super.setup_board(for_player, for_town)
	_ensure_selectable_focus()
	_sync_preview_from_focus()


func _exit_tree() -> void:
	var app: AppearanceComponent = _appearance()
	if app != null:
		app.clear_preview()
		if app.changed.is_connected(_on_appearance_changed):
			app.changed.disconnect(_on_appearance_changed)
	super._exit_tree()


func _appearance() -> AppearanceComponent:
	return player.appearance if is_instance_valid(player) else null


func _kind() -> String:
	return String(tabs[tab].kind) if not tabs.is_empty() else "hair"


func _subtitle() -> String:
	var app: AppearanceComponent = _appearance()
	if app == null:
		return ""
	var h_parts: Dictionary = app.parse_hair_id(app.hair_id)
	var o_parts: Dictionary = app.parse_outfit_id(app.outfit_id)
	var hair_style_name: String = String(app.hair_style_entry(String(h_parts.get("style", "default"))).get("name", "SILBERWELLEN")).to_upper()
	var hair_color_name: String = String(app.hair_color_entry(String(h_parts.get("color", "default"))).get("name", "SILBERFLIEDER")).to_upper()
	var outfit_style_name: String = String(app.outfit_style_entry(String(o_parts.get("style", "default"))).get("name", "REISEGEWAND")).to_upper()
	var outfit_color_name: String = String(app.outfit_color_entry(String(o_parts.get("color", "default"))).get("name", "ORIGINAL")).to_upper()
	match _kind():
		"outfit":
			return "%s - %s" % [outfit_style_name, outfit_color_name]
		"dye":
			var row: Dictionary = _focused()
			if String(row.get("kind", "")) == "outfit_color":
				return "OUTFIT: %s - %s" % [outfit_style_name, outfit_color_name]
			return "HAARE: %s - %s" % [hair_style_name, hair_color_name]
	return "%s - %s" % [hair_style_name, hair_color_name]


func _header_right(right: float, y: float) -> void:
	var label: String = "VORSCHAU" if _has_pending_change() else "IM SPIEGEL"
	var color: Color = GOLD if _has_pending_change() else LIT
	_text(Vector2(right - float(PixelText.width(label)), y), label, color)


func _empty_text() -> String:
	return "NICHTS FREIGESCHALTET"


func _hint() -> String:
	return "W S WÄHLEN   A D REITER   E ÜBERNEHMEN   ESC AUFSTEHEN"


func _on_appearance_changed() -> void:
	_on_town_changed()
	_ensure_selectable_focus()
	_sync_preview_from_focus()


func _preview_pair_for_row(row: Dictionary) -> Dictionary:
	var app: AppearanceComponent = _appearance()
	if app == null:
		return {"outfit": "default", "hair": "default"}
	var eq_hair: Dictionary = app.parse_hair_id(app.hair_id)
	var eq_outfit: Dictionary = app.parse_outfit_id(app.outfit_id)
	var out_outfit: String = app.outfit_id
	var out_hair: String = app.hair_id
	match String(row.get("kind", "")):
		"hair_style":
			out_hair = app.compose_hair_id(String(row.style_id), String(eq_hair.get("color", "default")))
		"hair_color":
			out_hair = app.compose_hair_id(String(eq_hair.get("style", "default")), String(row.color_id))
		"outfit_style":
			out_outfit = app.compose_outfit_id(String(row.style_id), String(eq_outfit.get("color", "default")))
		"outfit_color":
			out_outfit = app.compose_outfit_id(String(eq_outfit.get("style", "default")), String(row.color_id))
	return {"outfit": out_outfit, "hair": out_hair}


func _has_pending_change() -> bool:
	var app: AppearanceComponent = _appearance()
	if app == null:
		return false
	var row: Dictionary = _focused()
	if row.is_empty() or String(row.get("kind", "")) == "section":
		return false
	var target: Dictionary = _preview_pair_for_row(row)
	return String(target.outfit) != app.outfit_id or String(target.hair) != app.hair_id


func _rebuild() -> void:
	rows.clear()
	var app: AppearanceComponent = _appearance()
	if app == null:
		return
	var eq_hair: Dictionary = app.parse_hair_id(app.hair_id)
	var eq_hair_style: String = String(eq_hair.get("style", "default"))
	var eq_hair_color: String = String(eq_hair.get("color", "default"))
	var eq_outfit: Dictionary = app.parse_outfit_id(app.outfit_id)
	var eq_outfit_style: String = String(eq_outfit.get("style", "default"))
	var eq_outfit_color: String = String(eq_outfit.get("color", "default"))

	var focused_hair_tint: Color = Color.html(String(app.hair_color_entry(eq_hair_color).get("tint", "#ffffff")))
	var focused_outfit_tint: Color = Color.html(String(app.outfit_color_entry(eq_outfit_color).get("tint", "#ffffff")))

	match _kind():
		"hair":
			var styles: PackedStringArray = app.salon_hair_styles()
			for style_id: String in styles:
				var cfg: Dictionary = app.hair_style_entry(style_id)
				var is_active: bool = style_id == eq_hair_style
				rows.append({
					"kind": "hair_style",
					"style_id": style_id,
					"name": String(cfg.get("name", style_id)).to_upper(),
					"sub": "FRISUR  -  STANDARD" if bool(cfg.get("starter", false)) else "FRISUR  -  GEFUNDEN",
					"tag": "AKTIV" if is_active else "",
					"tag_color": LIT if is_active else GOLD,
					"icon": _hair_style_icon(focused_hair_tint),
					"ring": LIT if is_active else Color("4a4180"),
					"info": String(cfg.get("info", "")),
					"style_count": styles.size(),
					"state": OK,
					"why": "BEREITS ANGELEGT",
				})
		"outfit":
			var outfits: PackedStringArray = app.salon_outfit_styles()
			for outfit_key: String in outfits:
				var cfg: Dictionary = app.outfit_style_entry(outfit_key)
				var is_active: bool = outfit_key == eq_outfit_style
				rows.append({
					"kind": "outfit_style",
					"style_id": outfit_key,
					"name": String(cfg.get("name", outfit_key)).to_upper(),
					"sub": "OUTFIT  -  STANDARD" if bool(cfg.get("starter", false)) else "OUTFIT  -  GEFUNDEN",
					"tag": "AKTIV" if is_active else "",
					"tag_color": LIT if is_active else GOLD,
					"icon": _outfit_icon(focused_outfit_tint),
					"ring": LIT if is_active else Color("4a4180"),
					"info": String(cfg.get("info", "")),
					"outfit_count": outfits.size(),
					"state": OK,
					"why": "BEREITS ANGELEGT",
				})
		"dye":
			var hair_colors: PackedStringArray = app.salon_hair_colors()
			var eq_hc_cfg: Dictionary = app.hair_color_entry(eq_hair_color)
			var hair_collapsed: bool = bool(_dye_collapsed.get("hair", false))
			rows.append({
				"kind": "section",
				"section": "hair",
				"name": "HAARE",
				"active_name": String(eq_hc_cfg.get("name", eq_hair_color)).to_upper(),
				"count": hair_colors.size(),
				"swatch": eq_hc_cfg.get("swatch", []) as Array,
				"accent": LIT,
				"icon": _hair_style_icon(focused_hair_tint),
				"collapsed": hair_collapsed,
				"state": OK,
				"why": "",
			})
			if not hair_collapsed:
				for color_id: String in hair_colors:
					var cfg: Dictionary = app.hair_color_entry(color_id)
					var swatch: Array = cfg.get("swatch", ["#3e3152", "#8e79a8", "#d6cbe6", "#f4f0ff"]) as Array
					var is_active: bool = color_id == eq_hair_color
					var ring_col: Color = Color.html(String(swatch[2])) if swatch.size() >= 3 else Color.WHITE
					rows.append({
						"kind": "hair_color",
						"section": "hair",
						"color_id": color_id,
						"name": String(cfg.get("name", color_id)).to_upper(),
						"sub": "HAARFARBE  -  ORIGINAL" if color_id == "default" else "HAARFARBE",
						"tag": "AKTIV" if is_active else "",
						"tag_color": LIT if is_active else GOLD,
						"icon": _dye_bottle_icon(color_id, swatch),
						"ring": ring_col,
						"swatch": swatch,
						"info": String(cfg.get("info", "")),
						"state": OK,
						"why": "BEREITS ANGELEGT",
					})

			var outfit_colors: PackedStringArray = app.salon_outfit_colors()
			var eq_oc_cfg: Dictionary = app.outfit_color_entry(eq_outfit_color)
			var outfit_collapsed: bool = bool(_dye_collapsed.get("outfit", false))
			rows.append({
				"kind": "section",
				"section": "outfit",
				"name": "OUTFIT",
				"active_name": String(eq_oc_cfg.get("name", eq_outfit_color)).to_upper(),
				"count": outfit_colors.size(),
				"swatch": eq_oc_cfg.get("swatch", []) as Array,
				"accent": GOLD,
				"icon": _outfit_icon(focused_outfit_tint),
				"collapsed": outfit_collapsed,
				"state": OK,
				"why": "",
			})
			if not outfit_collapsed:
				for color_id: String in outfit_colors:
					var cfg: Dictionary = app.outfit_color_entry(color_id)
					var swatch: Array = cfg.get("swatch", ["#281d3d", "#4a3870", "#7c64a8", "#f0c878"]) as Array
					var is_active: bool = color_id == eq_outfit_color
					var ring_col: Color = Color.html(String(swatch[2])) if swatch.size() >= 3 else Color.WHITE
					rows.append({
						"kind": "outfit_color",
						"section": "outfit",
						"color_id": color_id,
						"name": String(cfg.get("name", color_id)).to_upper(),
						"sub": "OUTFITFARBE  -  ORIGINAL" if color_id == "default" else "OUTFITFARBE",
						"tag": "AKTIV" if is_active else "",
						"tag_color": LIT if is_active else GOLD,
						"icon": _outfit_dye_icon(color_id, swatch),
						"ring": ring_col,
						"swatch": swatch,
						"info": String(cfg.get("info", "")),
						"state": OK,
						"why": "BEREITS ANGELEGT",
					})
	_ensure_selectable_focus()
	_refresh_preview_tags()


func _refresh_preview_tags() -> void:
	var app: AppearanceComponent = _appearance()
	if app == null:
		return
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		if String(row.get("kind", "")) == "section":
			continue
		var target: Dictionary = _preview_pair_for_row(row)
		var active: bool = String(target.outfit) == app.outfit_id and String(target.hair) == app.hair_id
		if active:
			row["tag"] = "AKTIV"
			row["tag_color"] = LIT
		elif i == focus:
			row["tag"] = "VORSCHAU"
			row["tag_color"] = GOLD
		else:
			row["tag"] = ""
			row["tag_color"] = GOLD


func _is_selectable(index: int) -> bool:
	return index >= 0 and index < rows.size() and String(rows[index].get("kind", "")) != "section"


func _ensure_selectable_focus(preferred_section: String = "") -> void:
	if rows.is_empty():
		focus = 0
		scroll = 0
		return
	if _is_selectable(focus):
		_clamp_focus()
		_reveal_section_header_if_adjacent()
		return
	if preferred_section != "":
		for i: int in rows.size():
			if _is_selectable(i) and String(rows[i].get("section", "")) == preferred_section:
				focus = i
				_clamp_focus()
				_reveal_section_header_if_adjacent()
				return
	for i: int in rows.size():
		if _is_selectable(i):
			focus = i
			_clamp_focus()
			_reveal_section_header_if_adjacent()
			return
	focus = 0
	scroll = 0


func _reveal_section_header_if_adjacent() -> void:
	if focus > 0 and focus - 1 < rows.size() and String(rows[focus - 1].get("kind", "")) == "section":
		if focus - 1 < scroll:
			scroll = focus - 1


func _sync_preview_from_focus() -> void:
	var app: AppearanceComponent = _appearance()
	if app == null:
		return
	_ensure_selectable_focus()
	var row: Dictionary = _focused()
	if row.is_empty() or String(row.get("kind", "")) == "section":
		app.clear_preview()
		_refresh_preview_tags()
		_last_focus = focus
		_last_tab = tab
		return
	var target: Dictionary = _preview_pair_for_row(row)
	var preview_outfit: String = String(target.outfit) if String(target.outfit) != app.outfit_id else ""
	var preview_hair: String = String(target.hair) if String(target.hair) != app.hair_id else ""
	app.set_preview(preview_outfit, preview_hair)
	_refresh_preview_tags()
	_last_focus = focus
	_last_tab = tab


func _process(delta: float) -> void:
	super._process(delta)
	if not _closing and (focus != _last_focus or tab != _last_tab):
		_sync_preview_from_focus()


func _move(step: int) -> void:
	if rows.is_empty():
		return
	var next: int = focus
	for _attempt: int in rows.size():
		next = posmod(next + step, rows.size())
		if _is_selectable(next):
			focus = next
			_clamp_focus()
			_reveal_section_header_if_adjacent()
			_sound("tick")
			_sync_preview_from_focus()
			return


func _set_tab(index: int) -> void:
	super._set_tab(index)
	_ensure_selectable_focus()
	_sync_preview_from_focus()


func _tab_changed() -> void:
	super._tab_changed()
	_last_tab = tab
	_last_focus = -1


func _toggle_section(section: String) -> void:
	var was_collapsed: bool = bool(_dye_collapsed.get(section, false))
	_dye_collapsed[section] = not was_collapsed
	_sound("page")
	_rebuild()
	var fallback_section: String = section if was_collapsed else ""
	_ensure_selectable_focus(fallback_section)
	_sync_preview_from_focus()


func _on_gui_input(event: InputEvent) -> void:
	if _closing:
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _kind() == "dye":
		for v: int in VISIBLE_ROWS:
			var idx: int = scroll + v
			if idx < rows.size() and _row_rect(v).has_point(motion.position):
				if not _is_selectable(idx):
					return
				break
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and _kind() == "dye":
		for v: int in VISIBLE_ROWS:
			var idx: int = scroll + v
			if idx < rows.size() and _row_rect(v).has_point(click.position) and String(rows[idx].get("kind", "")) == "section":
				_toggle_section(String(rows[idx].get("section", "")))
				_canvas.accept_event()
				return
	super._on_gui_input(event)
	if not _closing:
		_ensure_selectable_focus()
		if focus != _last_focus:
			_sync_preview_from_focus()


func _draw_list(card: Rect2) -> void:
	if _kind() != "dye":
		super._draw_list(card)
		return
	if rows.is_empty():
		_text(Vector2(card.position.x + 16.0, card.position.y + LIST_Y + 12.0), _empty_text(), DIM)
		return
	for v: int in VISIBLE_ROWS:
		var index: int = scroll + v
		if index >= rows.size() or float(v) + 0.5 > _vis:
			break
		var row: Dictionary = rows[index]
		var rect: Rect2 = _row_rect(v)
		if String(row.get("kind", "")) == "section":
			_draw_section_row(rect, row)
		else:
			_draw_dye_row(rect, row, index == focus)
	if rows.size() > VISIBLE_ROWS:
		var top: float = card.position.y + LIST_Y
		var span: float = ROW_H * float(VISIBLE_ROWS) - 2.0
		var x: float = card.end.x - 14.0
		_canvas.draw_rect(Rect2(x, top, 1.0, span), Color(VineStyle.BARK_LIGHT, 0.6))
		var handle: float = span * float(VISIBLE_ROWS) / float(rows.size())
		var at: float = (span - handle) * float(scroll) / float(maxi(rows.size() - VISIBLE_ROWS, 1))
		_canvas.draw_rect(Rect2(x - 1.0, top + at, 3.0, handle), VineStyle.BARK)
		_canvas.draw_rect(Rect2(x, top + at, 1.0, handle), LIT)


func _draw_section_row(rect: Rect2, row: Dictionary) -> void:
	var accent: Color = row.get("accent", LIT) as Color
	var collapsed: bool = bool(row.get("collapsed", false))
	var hover: bool = InputManager.using_mouse and rect.has_point(_canvas.get_local_mouse_position())
	_canvas.draw_rect(rect, Color(0.11, 0.06, 0.20, 0.96 if hover else 0.90))
	_canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1.0)), Color(accent, 0.45))
	_canvas.draw_rect(Rect2(rect.position.x, rect.end.y - 1.0, rect.size.x, 1.0), Color(accent, 0.25))
	_canvas.draw_rect(Rect2(rect.position, Vector2(2.0, rect.size.y)), accent)
	# Crisp pixel chevron ('>' when collapsed, 'v' when expanded)
	var cx: float = rect.position.x + 8.0
	var cy: float = rect.position.y + 8.0
	if collapsed:
		_canvas.draw_rect(Rect2(cx, cy, 1.0, 5.0), accent)
		_canvas.draw_rect(Rect2(cx + 1.0, cy + 1.0, 1.0, 3.0), accent)
		_canvas.draw_rect(Rect2(cx + 2.0, cy + 2.0, 1.0, 1.0), accent)
	else:
		_canvas.draw_rect(Rect2(cx - 1.0, cy + 1.0, 5.0, 1.0), accent)
		_canvas.draw_rect(Rect2(cx, cy + 2.0, 3.0, 1.0), accent)
		_canvas.draw_rect(Rect2(cx + 1.0, cy + 3.0, 1.0, 1.0), accent)
	var icon: Texture2D = row.get("icon") as Texture2D
	if icon != null:
		_canvas.draw_texture_rect(icon, Rect2(rect.position + Vector2(15.0, 3.0), Vector2(14.0, 14.0)), false)
	_text(rect.position + Vector2(32.0, 7.0), String(row.get("name", "")), accent)
	# Right side: active swatch tones + equipped color name
	var swatch: Array = row.get("swatch", []) as Array
	var right_x: float = rect.end.x - 6.0
	if not swatch.is_empty():
		var sw_w: float = float(swatch.size()) * 4.0 + 2.0
		right_x -= sw_w
		_canvas.draw_rect(Rect2(right_x, rect.position.y + 7.0, sw_w, 6.0), UiStyle.OUTLINE)
		for idx: int in swatch.size():
			_canvas.draw_rect(Rect2(right_x + 1.0 + float(idx) * 4.0, rect.position.y + 8.0, 4.0, 4.0), Color.html(String(swatch[idx])))
		right_x -= 6.0
	var active_name: String = String(row.get("active_name", ""))
	if active_name != "":
		var nw: float = float(PixelText.width(active_name))
		_text(Vector2(right_x - nw, rect.position.y + 7.0), active_name, DIM if collapsed else TEXT)


func _draw_dye_row(rect: Rect2, row: Dictionary, on: bool) -> void:
	var accent: Color = LIT if String(row.get("section", "hair")) == "hair" else GOLD
	_canvas.draw_rect(rect, Color(0.06, 0.03, 0.12, 0.72))
	_canvas.draw_rect(Rect2(rect.position, Vector2(2.0, rect.size.y)), accent if on else Color(accent, 0.30))
	if on:
		_canvas.draw_rect(rect, Color(LIT, 0.12 + 0.05 * sin(_time * 4.0)))
	draw_cell(rect.position + Vector2(6.0, 0.0), "", 1, false, false, 0, row.get("icon") as Texture2D, row.get("ring", Color(0, 0, 0, 0)) as Color)
	var sub: String = String(row.get("sub", ""))
	_text(rect.position + Vector2(32.0, 4.0 if sub != "" else 7.0), String(row.get("name", "")), TEXT)
	if sub != "":
		_text(rect.position + Vector2(32.0, 12.0), sub, Color(DIM, 0.85))
	var tag: String = String(row.get("tag", ""))
	if tag != "":
		_text(Vector2(rect.end.x - 6.0 - float(PixelText.width(tag)), rect.position.y + 7.0), tag, row.get("tag_color", GOLD) as Color)


func _detail(area: Rect2, row: Dictionary) -> void:
	var app: AppearanceComponent = _appearance()
	if app == null or String(row.get("kind", "")) == "section":
		return
	var icon: Texture2D = row.get("icon") as Texture2D
	var ring: Color = row.get("ring", LIT) as Color
	draw_cell(area.position + Vector2(0, 2), "", 1, true, false, 0, icon, ring)
	var x: float = area.position.x + 46.0
	_text(Vector2(x, area.position.y + 2.0), String(row.get("name", "")), GOLD)
	var status: String = String(row.get("tag", ""))
	if status == "":
		status = "BEREIT"
	_text(Vector2(area.end.x - float(PixelText.width(status)), area.position.y + 2.0), status, LIT if status == "AKTIV" else GOLD)
	var y: float = area.position.y + 13.0
	for line: String in _wrap(String(row.get("info", "")), int(area.size.x) - 52).slice(0, 2):
		_text(Vector2(x, y), line, DIM)
		y += 9.0
	var row_kind: String = String(row.get("kind", ""))
	if row_kind == "hair_color" or row_kind == "outfit_color":
		var swatch: Array = row.get("swatch", []) as Array
		var sx: float = area.position.x
		var sy: float = area.position.y + 46.0
		for tone: Variant in swatch:
			_canvas.draw_rect(Rect2(sx, sy, 10, 10), UiStyle.OUTLINE)
			_canvas.draw_rect(Rect2(sx + 1, sy + 1, 8, 8), Color.html(String(tone)))
			sx += 12.0
		var base_name: String = ""
		if row_kind == "hair_color":
			var h_parts: Dictionary = app.parse_hair_id(app.hair_id)
			base_name = String(app.hair_style_entry(String(h_parts.get("style", "default"))).get("name", "SILBERWELLEN")).to_upper()
		else:
			var o_parts: Dictionary = app.parse_outfit_id(app.outfit_id)
			base_name = String(app.outfit_style_entry(String(o_parts.get("style", "default"))).get("name", "REISEGEWAND")).to_upper()
		_text(Vector2(sx + 6.0, sy + 2.0), "%s + %s" % [base_name, String(row.get("name", ""))], TEXT)
	elif row_kind == "hair_style":
		var style_count: int = int(row.get("style_count", 1))
		_text(Vector2(area.position.x, area.position.y + 48.0), "VERFÜGBARE FRISUREN: %d" % style_count, LIT if style_count > 1 else DIM)
	elif row_kind == "outfit_style":
		var outfit_count: int = int(row.get("outfit_count", 1))
		_text(Vector2(area.position.x, area.position.y + 48.0), "VERFÜGBARE OUTFITS: %d" % outfit_count, LIT if outfit_count > 1 else DIM)
	var action_note: String = "VORSCHAU IM SPIEGEL - E ZUM ÜBERNEHMEN" if _has_pending_change() else "AKTUELL IM SPIEGEL ANGELEGT"
	_text(Vector2(area.position.x, area.position.y + 60.0), action_note, GOLD if _has_pending_change() else DIM)


func _buttons() -> Array[Dictionary]:
	var pending: bool = _has_pending_change()
	var list: Array[Dictionary] = [{"id": "apply", "label": "ÜBERNEHMEN", "ready": pending}]
	if pending:
		list.append({"id": "reset", "label": "ZURÜCKSETZEN", "ready": true})
	else:
		list.append({"id": "stand", "label": "AUFSTEHEN", "ready": true})
	return list


func _press(id: String, _bulk: bool) -> void:
	var app: AppearanceComponent = _appearance()
	match id:
		"apply":
			if app == null:
				return
			var row: Dictionary = _focused()
			var target: Dictionary = _preview_pair_for_row(row)
			var applied: bool = false
			if String(target.hair) != app.hair_id:
				app.clear_preview()
				app.request_hair(String(target.hair))
				_on_notice("HAARFARBE ÜBERNOMMEN" if String(row.get("kind", "")) == "hair_color" else "FRISUR ÜBERNOMMEN", true)
				applied = true
			elif String(target.outfit) != app.outfit_id:
				app.clear_preview()
				app.request_outfit(String(target.outfit))
				_on_notice("OUTFITFARBE ÜBERNOMMEN" if String(row.get("kind", "")) == "outfit_color" else "OUTFIT ÜBERNOMMEN", true)
				applied = true
			if applied and is_instance_valid(seat) and seat.has_method("sparkle_burst"):
				seat.call("sparkle_burst")
			var keep: int = focus
			_rebuild()
			focus = keep
			_ensure_selectable_focus()
			_sync_preview_from_focus()
		"reset":
			if app == null:
				return
			app.clear_preview()
			_sound("tick")
			var active_section: String = String(_focused().get("section", ""))
			for i: int in rows.size():
				var row: Dictionary = rows[i]
				if String(row.get("kind", "")) == "section":
					continue
				if active_section != "" and String(row.get("section", "")) != active_section:
					continue
				var pair: Dictionary = _preview_pair_for_row(row)
				if String(pair.outfit) == app.outfit_id and String(pair.hair) == app.hair_id:
					focus = i
					break
			_clamp_focus()
			_reveal_section_header_if_adjacent()
			_refresh_preview_tags()
			_last_focus = focus
		"stand":
			_close()


func _close() -> void:
	if _closing:
		return
	remove_from_group("board_window")
	remove_from_group("salon_window")
	var app: AppearanceComponent = _appearance()
	if app != null:
		app.clear_preview()
	super._close()
	if is_instance_valid(player):
		var rest: RestComponent = player.get_node_or_null("RestComponent") as RestComponent
		if rest != null and rest.seat == seat and rest.state != RestComponent.State.FREE:
			player.story_lock = true ## RestComponent clears story_lock after standing up
			if rest.state != RestComponent.State.UP:
				rest.request_stand()


## Called by `SalonSeat` when sitting ends externally (e.g., interrupted by damage).
func close_from_seat() -> void:
	_close()


# ---------- procedural 16x16 icons ----------

func _hair_style_icon(tint: Color) -> ImageTexture:
	var key: String = "style:%s" % tint.to_html(false)
	if _icon_cache.has(key):
		return _icon_cache[key] as ImageTexture
	var base: Color = Color("c8b4e4") if tint == Color.WHITE else tint
	var c0: Color = base.darkened(0.55)
	var c1: Color = base.darkened(0.18)
	var c2: Color = base.lightened(0.25)
	var c3: Color = base.lightened(0.65)
	var grid: PackedStringArray = [
		"................",
		".....OOOOOO.....",
		"...OO223322OO...",
		"..O1233222211O..",
		"..O1221111221O..",
		".O011......110O.",
		".O01........10O.",
		".O01........10O.",
		".O012......210O.",
		".O012......210O.",
		"..O011....110O..",
		"..O001....100O..",
		"...O0......0O...",
		"................",
		"................",
		"................",
	]
	var tex: ImageTexture = _raster_icon(grid, {"O": INK, "0": c0, "1": c1, "2": c2, "3": c3})
	_icon_cache[key] = tex
	return tex


func _dye_bottle_icon(color_id: String, swatch: Array) -> ImageTexture:
	var key: String = "hair_dye:%s" % color_id
	if _icon_cache.has(key):
		return _icon_cache[key] as ImageTexture
	var c0: Color = Color.html(String(swatch[0])) if swatch.size() >= 1 else Color("3e3152")
	var c1: Color = Color.html(String(swatch[1])) if swatch.size() >= 2 else Color("8e79a8")
	var c2: Color = Color.html(String(swatch[2])) if swatch.size() >= 3 else Color("d6cbe6")
	var c3: Color = Color.html(String(swatch[3])) if swatch.size() >= 4 else Color("f4f0ff")
	var cork: Color = Color("c89d54")
	var cork_d: Color = Color("7d592c")
	var glass: Color = Color("9cd6dc")
	var grid: PackedStringArray = [
		"................",
		"......OOOO......",
		".....OKKKkO.....",
		"......OOOO......",
		".....OGGGGGO....",
		"....OG23221GO...",
		"...OG2332211GO..",
		"...O233221110O..",
		"...O222211100O..",
		"...O122111000O..",
		"...O111100000O..",
		"....O1100000O...",
		".....OOOOOOO....",
		"................",
		"................",
		"................",
	]
	var tex: ImageTexture = _raster_icon(grid, {"O": INK, "K": cork, "k": cork_d, "G": glass, "0": c0, "1": c1, "2": c2, "3": c3})
	_icon_cache[key] = tex
	return tex


func _outfit_dye_icon(color_id: String, swatch: Array) -> ImageTexture:
	var key: String = "outfit_dye:%s" % color_id
	if _icon_cache.has(key):
		return _icon_cache[key] as ImageTexture
	var c0: Color = Color.html(String(swatch[0])) if swatch.size() >= 1 else Color("281d3d")
	var c1: Color = Color.html(String(swatch[1])) if swatch.size() >= 2 else Color("4a3870")
	var c2: Color = Color.html(String(swatch[2])) if swatch.size() >= 3 else Color("7c64a8")
	var c3: Color = Color.html(String(swatch[3])) if swatch.size() >= 4 else Color("f0c878")
	var grid: PackedStringArray = [
		"................",
		"....OOOOOOOO....",
		"...O32222221O...",
		"..O2332211110O..",
		"..O2322111100O..",
		"..O1221111000O..",
		"..O1111100000O..",
		"..O1110000000O..",
		"...O11000000O...",
		"....O100000O....",
		"....OOOOOOOO....",
		"......O23O......",
		".....O1232O.....",
		"......OOOO......",
		"................",
		"................",
	]
	var tex: ImageTexture = _raster_icon(grid, {"O": INK, "0": c0, "1": c1, "2": c2, "3": c3})
	_icon_cache[key] = tex
	return tex


func _outfit_icon(tint: Color) -> ImageTexture:
	var key: String = "outfit:%s" % tint.to_html(false)
	if _icon_cache.has(key):
		return _icon_cache[key] as ImageTexture
	var base: Color = Color("6b5694") if tint == Color.WHITE else tint
	var c0: Color = base.darkened(0.45)
	var c1: Color = base
	var c2: Color = base.lightened(0.28)
	var clasp: Color = Color("f0c878")
	var grid: PackedStringArray = [
		"................",
		"....OO....OO....",
		"...O21OOOO12O...",
		"..O211CCCC112O..",
		".O111112211111O.",
		".O110O1211O011O.",
		"..OO.O1111O.OO..",
		".....O1111O.....",
		"....O112211O....",
		"....O112211O....",
		"...O01122110O...",
		"...O01111110O...",
		"...O00111100O...",
		"....OOOOOOOO....",
		"................",
		"................",
	]
	var tex: ImageTexture = _raster_icon(grid, {"O": INK, "0": c0, "1": c1, "2": c2, "C": clasp})
	_icon_cache[key] = tex
	return tex


func _raster_icon(grid: PackedStringArray, palette: Dictionary) -> ImageTexture:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in mini(grid.size(), 16):
		var line: String = grid[y]
		for x: int in mini(line.length(), 16):
			var ch: String = line[x]
			if palette.has(ch):
				img.set_pixel(x, y, palette[ch] as Color)
	return ImageTexture.create_from_image(img)
