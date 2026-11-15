class_name ZoneMapView
extends RefCounted
## Two-tier Lost-Ark-style map renderer for ZoneWorld:
## Tier 1 = organic sculpted Zone detail map; Tier 2 = seamless Voronoi-partitioned Main Continent overview.

const PANEL_MARGIN: Vector2 = Vector2(26.0, 20.0)
const HEADER_H: float = 28.0
const FOOTER_H: float = 24.0

var mode: String = "zone" ## "zone" or "continent"
var inspected_zone_id: String = "start_path"
var hovered_zone_id: String = ""
var cursor_pos: Vector2 = Vector2.ZERO
var _toggle_rect: Rect2 = Rect2()
var _last_continent_rect: Rect2 = Rect2()

static var _zone_tex_cache: Dictionary = {} ## zone_id -> ImageTexture
static var _continent_base_tex: ImageTexture
var _state_tex: ImageTexture
var _state_sig: String = ""


static func clear_cache() -> void:
	_zone_tex_cache.clear()
	_continent_base_tex = null


func on_open(zone_world: Variant, local_player: Player) -> void:
	mode = "zone"
	hovered_zone_id = ""
	var zid: String = ""
	if local_player != null and is_instance_valid(local_player):
		zid = ZoneCatalog.zone_id_at(Interiors.outer(local_player.get_tree(), local_player.global_position))
	if zid.is_empty() and zone_world != null and zone_world.has_method("player_zone") and local_player != null:
		zid = String(zone_world.call("player_zone", local_player.name.to_int()))
	if zid.is_empty():
		zid = ZoneCatalog.start_zone_id()
	inspected_zone_id = zid


func set_mode(new_mode: String, zone_id: String = "") -> void:
	mode = "continent" if new_mode == "continent" else "zone"
	if not zone_id.is_empty() and not ZoneCatalog.zone_spec(zone_id).is_empty():
		inspected_zone_id = zone_id


func handle_input(event: InputEvent, view_size: Vector2, zone_world: Variant, local_player: Player) -> bool:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		cursor_pos = motion.position
		if mode == "continent":
			hovered_zone_id = _hit_zone_at(cursor_pos)
		return true

	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_TAB or key.keycode == KEY_SPACE:
			_toggle_mode(zone_world, local_player)
			return true

	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return false
	cursor_pos = button.position

	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if mode == "zone":
			set_mode("continent")
		return true
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		if mode == "continent":
			var target: String = hovered_zone_id
			if target.is_empty() or ZoneCatalog.zone_spec(target).is_empty():
				target = _current_player_zone(zone_world, local_player)
			set_mode("zone", target)
		return true
	if button.button_index == MOUSE_BUTTON_LEFT:
		if _toggle_rect.has_point(button.position):
			_toggle_mode(zone_world, local_player)
			return true
		if mode == "continent":
			var hit: String = _hit_zone_at(button.position)
			if not hit.is_empty():
				if not ZoneCatalog.zone_spec(hit).is_empty() and ZoneCatalog.is_zone_playable(hit):
					set_mode("zone", hit)
				hovered_zone_id = hit
				return true
	return _card_rect(view_size).has_point(button.position)


func draw(canvas: Control, view_size: Vector2, fade: float, time_sec: float, zone_world: Variant, local_player: Player) -> void:
	if fade <= 0.01:
		return
	var card: Rect2 = _card_rect(view_size)
	_draw_card_frame(canvas, card, fade)
	var header: Rect2 = Rect2(card.position, Vector2(card.size.x, HEADER_H))
	var map_rect: Rect2 = Rect2(
		Vector2(card.position.x + 10.0, card.position.y + HEADER_H + 4.0),
		Vector2(card.size.x - 20.0, card.size.y - HEADER_H - FOOTER_H - 8.0)
	)
	var footer: Rect2 = Rect2(Vector2(card.position.x, card.end.y - FOOTER_H), Vector2(card.size.x, FOOTER_H))

	_draw_header(canvas, header, fade)
	if mode == "continent":
		_draw_continent_tier(canvas, map_rect, fade, time_sec, zone_world, local_player)
	else:
		_draw_zone_tier(canvas, map_rect, fade, time_sec, zone_world, local_player)
	_draw_footer(canvas, footer, fade)


func _card_rect(view_size: Vector2) -> Rect2:
	return Rect2(PANEL_MARGIN, view_size - PANEL_MARGIN * 2.0)


func _toggle_mode(zone_world: Variant, local_player: Player) -> void:
	if mode == "zone":
		set_mode("continent")
	else:
		set_mode("zone", _current_player_zone(zone_world, local_player))


func _current_player_zone(zone_world: Variant, local_player: Player) -> String:
	if local_player != null and is_instance_valid(local_player):
		var z: String = ZoneCatalog.zone_id_at(Interiors.outer(local_player.get_tree(), local_player.global_position))
		if not z.is_empty():
			return z
	if zone_world != null and zone_world.has_method("player_zone") and local_player != null:
		return String(zone_world.call("player_zone", local_player.name.to_int()))
	return inspected_zone_id


func _hit_zone_at(pos: Vector2) -> String:
	if not _last_continent_rect.has_area() or not _last_continent_rect.has_point(pos):
		return ""
	var uv: Vector2 = (pos - _last_continent_rect.position) / _last_continent_rect.size
	return ZoneCatalog.continent_zone_at_uv(uv, "main")


func _draw_card_frame(canvas: Control, card: Rect2, fade: float) -> void:
	canvas.draw_rect(card.grow(3.0), Color(0.02, 0.02, 0.04, 0.85 * fade), true)
	canvas.draw_rect(card, Color(0.08, 0.07, 0.12, 0.96 * fade), true)
	canvas.draw_rect(card, Color(0.45, 0.40, 0.34, 0.85 * fade), false, 2.0)
	canvas.draw_rect(card.grow(-3.0), Color(0.24, 0.21, 0.28, 0.65 * fade), false, 1.0)


func _draw_header(canvas: Control, header: Rect2, fade: float) -> void:
	canvas.draw_rect(header, Color(0.11, 0.10, 0.16, 0.92 * fade), true)
	canvas.draw_line(Vector2(header.position.x, header.end.y), header.end, Color(0.35, 0.31, 0.38, 0.8 * fade), 1.0)
	var title: String = "WELTKARTE: GRÜNLAND-KONTINENT"
	var sub: String = "STANDARD-BIOM & HEXENWALD"
	if mode == "zone":
		var spec: Dictionary = ZoneCatalog.zone_spec(inspected_zone_id)
		var summary: Dictionary = ZoneCatalog.zone_summary(inspected_zone_id)
		var zname: String = String(spec.get("name", summary.get("name", inspected_zone_id.to_upper())))
		title = "ZONE: %s" % zname
		sub = String(spec.get("subtitle", summary.get("subtitle", "")))
	_text(canvas, title, Vector2i(int(header.position.x + 12.0), int(header.position.y + 6.0)), Color("f2e8cf"), fade)
	if not sub.is_empty():
		var tw: int = PixelText.width(title)
		_text(canvas, sub, Vector2i(int(header.position.x + 24.0) + tw, int(header.position.y + 7.0)), Color("8ea8b0"), fade)

	var btn_label: String = "ZUR ZONE +" if mode == "continent" else "KONTINENT -"
	var btn_w: float = float(PixelText.width(btn_label) + 18)
	_toggle_rect = Rect2(header.end.x - btn_w - 8.0, header.position.y + 4.0, btn_w, HEADER_H - 8.0)
	var btn_hover: bool = _toggle_rect.has_point(cursor_pos)
	canvas.draw_rect(_toggle_rect, Color(0.20, 0.32, 0.34, fade) if btn_hover else Color(0.15, 0.21, 0.25, fade), true)
	canvas.draw_rect(_toggle_rect, Color(Color("7cf4de"), fade) if btn_hover else Color(0.46, 0.62, 0.60, 0.85 * fade), false, 1.0)
	_text(canvas, btn_label, Vector2i(int(_toggle_rect.position.x + 9.0), int(_toggle_rect.position.y + 5.0)), Color("dffbf4"), fade)


func _draw_footer(canvas: Control, footer: Rect2, fade: float) -> void:
	canvas.draw_line(footer.position, Vector2(footer.end.x, footer.position.y), Color(0.30, 0.27, 0.34, 0.7 * fade), 1.0)
	var hint: String = "MAUSRAD: KONTINENT   -   TAB: WECHSELN   -   ESC / M: SCHLIESSEN" if mode == "zone" else "KLICK AUF ZONE: DETAILS   -   MAUSRAD / TAB: ZURÜCK   -   ESC / M: SCHLIESSEN"
	_text(canvas, hint, Vector2i(int(footer.position.x + 12.0), int(footer.position.y + 7.0)), Color("9aa3ad"), fade)


# ------------------------------------------------------------------ Tier 1: Organic Zone Detail Map

func _zone_texture(zone_id: String, spec: Dictionary) -> ImageTexture:
	if _zone_tex_cache.has(zone_id):
		return _zone_tex_cache[zone_id] as ImageTexture
	var shape: Dictionary = ZoneBuilder.compute_zone_shape(spec)
	var w: int = int(shape["w"])
	var h: int = int(shape["h"])
	var walkable: PackedByteArray = shape["walkable"] as PackedByteArray
	var water: PackedFloat32Array = shape["water"] as PackedFloat32Array

	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = int(spec.get("world_seed", zone_id.hash())) ^ 0x51C3
	noise.frequency = 0.08
	noise.fractal_octaves = 2

	var ta_rect: Rect2i = Rect2i()
	if spec.has("town_area"):
		var tr: Array = (spec.get("town_area", {}) as Dictionary).get("tile_rect", []) as Array
		if tr.size() >= 4:
			ta_rect = Rect2i(int(tr[0]), int(tr[1]), int(tr[2]), int(tr[3]))

	var col_forest_deep: Color = Color(0.08, 0.13, 0.12, 1.0)
	var col_forest_mid: Color = Color(0.13, 0.21, 0.16, 1.0)
	var col_cliff_rim: Color = Color(0.32, 0.42, 0.34, 1.0)
	var col_meadow_base: Color = Color(0.24, 0.39, 0.27, 1.0)
	var col_meadow_hi: Color = Color(0.30, 0.47, 0.31, 1.0)
	var col_town_tint: Color = Color(0.33, 0.46, 0.32, 1.0)
	var col_water_shallow: Color = Color(0.18, 0.44, 0.50, 1.0)
	var col_water_deep: Color = Color(0.11, 0.29, 0.38, 1.0)

	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for ly: int in range(h):
		for lx: int in range(w):
			var idx: int = ly * w + lx
			var land: bool = walkable[idx] == 1
			var nv: float = noise.get_noise_2d(float(lx), float(ly)) * 0.5 + 0.5
			if not land:
				## Check 1px rim next to land for organic forest canopy edge highlight
				var near_land: bool = (lx > 0 and walkable[idx - 1] == 1) or (lx + 1 < w and walkable[idx + 1] == 1) or (ly > 0 and walkable[idx - w] == 1) or (ly + 1 < h and walkable[idx + w] == 1)
				if near_land:
					img.set_pixel(lx, ly, col_cliff_rim)
				else:
					img.set_pixel(lx, ly, col_forest_deep.lerp(col_forest_mid, smoothstep(0.32, 0.72, nv)))
				continue

			var wd: float = water[idx]
			if wd > 0.0:
				var shoreline: bool = wd < 0.25
				var wc: Color = Color(0.42, 0.76, 0.78, 1.0) if shoreline else col_water_shallow.lerp(col_water_deep, clampf(wd, 0.0, 1.0))
				img.set_pixel(lx, ly, wc)
				continue

			var near_wall: bool = (lx > 0 and walkable[idx - 1] == 0) or (lx + 1 < w and walkable[idx + 1] == 0) or (ly > 0 and walkable[idx - w] == 0) or (ly + 1 < h and walkable[idx + w] == 0)
			var mc: Color = col_meadow_base.lerp(col_meadow_hi, smoothstep(0.35, 0.78, nv))
			if ta_rect.has_point(Vector2i(lx, ly)):
				mc = mc.lerp(col_town_tint, 0.38)
			if near_wall:
				mc = mc.lerp(col_forest_mid, 0.42)
			img.set_pixel(lx, ly, mc)

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_zone_tex_cache[zone_id] = tex
	return tex


func _draw_zone_tier(canvas: Control, rect: Rect2, fade: float, time_sec: float, _zone_world: Variant, local_player: Player) -> void:
	canvas.draw_rect(rect, Color(0.05, 0.06, 0.09, fade), true)
	var spec: Dictionary = ZoneCatalog.zone_spec(inspected_zone_id)
	if spec.is_empty():
		_text_center(canvas, "KEINE ZONENDATEN", rect.get_center(), Color("d98a7c"), fade)
		return
	var zw: float = float(spec.get("width", 104))
	var zh: float = float(spec.get("height", 130))
	var pad: float = 14.0
	var avail: Vector2 = rect.size - Vector2(pad * 2.0, pad * 2.0)
	var px_per_tile: float = minf(avail.x / maxf(zw, 1.0), avail.y / maxf(zh, 1.0))
	var map_px: Vector2 = Vector2(zw, zh) * px_per_tile
	var origin: Vector2 = rect.position + (rect.size - map_px) * 0.5
	var zone_rect: Rect2 = Rect2(origin, map_px)

	var to_screen: Callable = func(local_tile: Vector2) -> Vector2:
		return origin + local_tile * px_per_tile

	## Render sculpted organic zone terrain texture (trees, alcoves, meadow, irregular water)
	var tex: ImageTexture = _zone_texture(inspected_zone_id, spec)
	canvas.draw_texture_rect(tex, zone_rect, false, Color(1.0, 1.0, 1.0, fade))
	canvas.draw_rect(zone_rect, Color(0.32, 0.38, 0.34, 0.55 * fade), false, 1.0)

	## Path patches & start_path road spine
	for pp_v: Variant in spec.get("path_patches", []) as Array:
		if not (pp_v is Dictionary):
			continue
		var pts_raw: Array = (pp_v as Dictionary).get("points", []) as Array
		if pts_raw.size() < 2:
			continue
		var s_pts: PackedVector2Array = PackedVector2Array()
		for pt_v: Variant in pts_raw:
			if pt_v is Array and (pt_v as Array).size() >= 2:
				var p: Array = pt_v as Array
				s_pts.append(to_screen.call(Vector2(float(p[0]), float(p[1]))))
		canvas.draw_polyline(s_pts, Color(0.62, 0.52, 0.39, 0.85 * fade), maxf(2.0, px_per_tile * 1.4), true)
	if inspected_zone_id == "start_path":
		var spine: PackedVector2Array = PackedVector2Array([
			to_screen.call(Vector2(17, 16)),
			to_screen.call(Vector2(25, 23)),
			to_screen.call(Vector2(30, 50)),
			to_screen.call(Vector2(48, 78)),
			to_screen.call(Vector2(63, 105)),
			to_screen.call(Vector2(72, 119)),
		])
		var branch: PackedVector2Array = PackedVector2Array([
			to_screen.call(Vector2(63, 105)),
			to_screen.call(Vector2(96, 103)),
		])
		canvas.draw_polyline(spine, Color(0.62, 0.52, 0.39, 0.85 * fade), maxf(2.0, px_per_tile * 1.5), true)
		canvas.draw_polyline(branch, Color(0.62, 0.52, 0.39, 0.85 * fade), maxf(2.0, px_per_tile * 1.5), true)

	## Landmarks
	if spec.has("manhole"):
		var mp: Array = (spec.get("manhole", {}) as Dictionary).get("pos", [262, 240]) as Array
		var m_pt: Vector2 = to_screen.call(Vector2(float(mp[0]), float(mp[1])) / 16.0)
		canvas.draw_circle(m_pt, 3.5, Color(Color("5fd9d0"), fade))
		_text(canvas, "SCHACHT", Vector2i(int(m_pt.x + 6.0), int(m_pt.y - 4.0)), Color("a8e8e2"), fade)

	if spec.has("fallen_knight"):
		var kt: Array = (spec.get("fallen_knight", {}) as Dictionary).get("tile", [55, 91]) as Array
		var k_pt: Vector2 = to_screen.call(Vector2(float(kt[0]), float(kt[1])))
		canvas.draw_circle(k_pt, 3.0, Color(Color("d4c4e8"), fade))
		_text(canvas, "RITTER", Vector2i(int(k_pt.x + 6.0), int(k_pt.y - 4.0)), Color("d4c4e8"), fade)

	if spec.has("signpost"):
		var st: Array = (spec.get("signpost", {}) as Dictionary).get("tile", [63, 105]) as Array
		var s_pt: Vector2 = to_screen.call(Vector2(float(st[0]), float(st[1])))
		canvas.draw_rect(Rect2(s_pt - Vector2(2, 2), Vector2(4, 4)), Color(Color("e3c27d"), fade))

	if spec.has("hut"):
		var ht: Array = (spec.get("hut", {}) as Dictionary).get("tile", [88, 68]) as Array
		var h_pt: Vector2 = to_screen.call(Vector2(float(ht[0]), float(ht[1])))
		canvas.draw_rect(Rect2(h_pt - Vector2(4, 4), Vector2(8, 8)), Color(Color("d69d5c"), fade))
		canvas.draw_rect(Rect2(h_pt - Vector2(4, 4), Vector2(8, 8)), Color(Color("fff1cf"), fade), false, 1.0)
		_text_center(canvas, "VALDRICS HÜTTE", h_pt + Vector2(0.0, -11.0), Color("f6e6ba"), fade)

	for ws_v: Variant in spec.get("waystones", []) as Array:
		if ws_v is Dictionary:
			var wt: Array = (ws_v as Dictionary).get("tile", [76, 66]) as Array
			var w_pt: Vector2 = to_screen.call(Vector2(float(wt[0]), float(wt[1])))
			_draw_diamond(canvas, w_pt, 5.0, Color("6df2e2"), Color("d9fff9"), fade)
			var ws_w: int = PixelText.width("WEGSTEIN")
			_text(canvas, "WEGSTEIN", Vector2i(int(w_pt.x) - ws_w - 7, int(w_pt.y - 4.0)), Color("94fbf0"), fade)

	## Portals positioned with outward non-overlapping labels
	for p_v: Variant in spec.get("portals", []) as Array:
		if not (p_v is Dictionary):
			continue
		var p: Dictionary = p_v as Dictionary
		var pt: Array = p.get("tile", [0, 0]) as Array
		var p_pos: Vector2 = to_screen.call(Vector2(float(pt[0]), float(pt[1])))
		var locked: bool = bool(p.get("locked", false))
		var p_col: Color = Color("d96b6b") if locked else Color("6ef5c8")
		_draw_diamond(canvas, p_pos, 4.5, p_col, Color.WHITE, fade)
		var lbl: String = String(p.get("target_zone", p.get("label", ""))).to_upper()
		var sum_t: Dictionary = ZoneCatalog.zone_summary(String(p.get("target_zone", "")))
		if not sum_t.is_empty():
			lbl = String(sum_t.get("name", lbl))
		if locked:
			lbl += ": SPERRE"
		var p_dir: String = String(p.get("dir", ""))
		var lw: int = PixelText.width(lbl)
		var lx_off: int = -lw / 2
		var ly_off: int = -4
		if p_dir == "west":
			lx_off = -lw - 8
		elif p_dir == "east":
			lx_off = 8
		elif p_dir == "north":
			ly_off = -14
		elif p_dir == "south":
			ly_off = 8
		_text(canvas, lbl, Vector2i(int(p_pos.x) + lx_off, int(p_pos.y) + ly_off), p_col, fade)

	## Active Quest Goal inside this zone
	if local_player != null and is_instance_valid(local_player):
		var tracked: TrackedQuests = local_player.get("tracked") as TrackedQuests
		if tracked != null:
			var focused: Dictionary = tracked.focused()
			var q_target: Variant = focused.get("target", Vector2.INF)
			if q_target is Vector2 and (q_target as Vector2) != Vector2.INF:
				var q_pos: Vector2 = q_target as Vector2
				if ZoneCatalog.zone_id_at(q_pos) == inspected_zone_id:
					var q_local_tile: Vector2 = (q_pos - ZoneCatalog.slot_origin_px(inspected_zone_id)) / 16.0
					var q_scr: Vector2 = to_screen.call(q_local_tile)
					var pulse: float = 5.0 + 2.5 * sin(time_sec * 4.0)
					canvas.draw_arc(q_scr, pulse, 0.0, TAU, 16, Color(1.0, 0.85, 0.35, 0.9 * fade), 1.5)
					canvas.draw_circle(q_scr, 2.5, Color(1.0, 0.9, 0.45, fade))

	## Live Co-op Players inside inspected zone
	var z_origin_px: Vector2 = ZoneCatalog.slot_origin_px(inspected_zone_id)
	for p: Player in Player.all:
		if not is_instance_valid(p):
			continue
		var outer_pos: Vector2 = Interiors.outer(p.get_tree(), p.global_position)
		if ZoneCatalog.zone_id_at(outer_pos) != inspected_zone_id:
			continue
		var p_local_tile: Vector2 = (outer_pos - z_origin_px) / 16.0
		var p_scr: Vector2 = to_screen.call(p_local_tile)
		var is_me: bool = (p == local_player)
		var p_col: Color = Color("ffe680") if is_me else Color("8ce6ff")
		_draw_diamond(canvas, p_scr, 5.5, p_col, Color("1a1524"), fade)
		var tag: String = "DU" if is_me else ("P" + p.name)
		_text(canvas, tag, Vector2i(int(p_scr.x + 7.0), int(p_scr.y - 4.0)), p_col, fade)


# ------------------------------------------------------------------ Tier 2: Seamless Organic Continent Overview

func _ensure_continent_base_texture() -> ImageTexture:
	if _continent_base_tex != null:
		return _continent_base_tex
	var layout: Dictionary = ZoneCatalog.continent_layout("main")
	var lw: int = int(layout["width"])
	var lh: int = int(layout["height"])
	var owner_grid: PackedInt32Array = layout["owner_grid"] as PackedInt32Array
	var sdf_grid: PackedFloat32Array = layout["sdf_grid"] as PackedFloat32Array
	var z_biomes: Array[String] = layout["zone_biomes"] as Array[String]

	var scale: int = 2
	var iw: int = lw * scale
	var ih: int = lh * scale
	var tex_noise: FastNoiseLite = FastNoiseLite.new()
	tex_noise.seed = 91823
	tex_noise.frequency = 0.09
	tex_noise.fractal_octaves = 2

	var ocean_deep: Color = Color(0.04, 0.09, 0.15, 1.0)
	var ocean_mid: Color = Color(0.07, 0.16, 0.24, 1.0)
	var ocean_shallow: Color = Color(0.14, 0.34, 0.42, 1.0)
	var surf_foam: Color = Color(0.45, 0.72, 0.74, 1.0)
	var meadow_low: Color = Color(0.16, 0.28, 0.21, 1.0)
	var meadow_high: Color = Color(0.24, 0.39, 0.27, 1.0)
	var witch_low: Color = Color(0.21, 0.14, 0.28, 1.0)
	var witch_high: Color = Color(0.32, 0.21, 0.41, 1.0)
	var coast_ink: Color = Color(0.55, 0.72, 0.60, 1.0)
	var border_col: Color = Color(0.10, 0.12, 0.15, 1.0)

	var img: Image = Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	for py: int in range(ih):
		var cy: int = py / scale
		for px: int in range(iw):
			var cx: int = px / scale
			var idx: int = cy * lw + cx
			var owner: int = owner_grid[idx]
			var sdf: float = sdf_grid[idx]
			var grain: float = tex_noise.get_noise_2d(float(px), float(py)) * 0.5 + 0.5

			if owner < 0:
				## Sea depth & shallow coastal shelf glow around organic shoreline
				var c: Color = ocean_deep
				if sdf > -0.015:
					c = ocean_shallow.lerp(surf_foam, smoothstep(-0.015, 0.0, sdf) * 0.55)
				elif sdf > -0.055:
					c = ocean_mid.lerp(ocean_shallow, smoothstep(-0.055, -0.015, sdf))
				elif sdf > -0.13:
					c = ocean_deep.lerp(ocean_mid, smoothstep(-0.13, -0.055, sdf))
				## Subtle bathymetry scanline wave texture
				if ((py + int(grain * 3.0)) % 9) == 0 and sdf < -0.03:
					c = c.lightened(0.06)
				img.set_pixel(px, py, c)
				continue

			var is_witch: bool = z_biomes[owner] == "witch_forest"
			var base_land: Color = (witch_low.lerp(witch_high, grain)) if is_witch else (meadow_low.lerp(meadow_high, grain))
			## Soft relief shading toward continent interior
			var interior_lift: float = clampf(sdf * 5.0, 0.0, 1.0) * 0.14
			base_land = base_land.lightened(interior_lift)

			## Sample 1-cell neighbors in layout grid for crisp coastlines & province borders
			var left_o: int = owner_grid[idx - 1] if cx > 0 else -1
			var right_o: int = owner_grid[idx + 1] if cx + 1 < lw else -1
			var up_o: int = owner_grid[idx - lw] if cy > 0 else -1
			var down_o: int = owner_grid[idx + lw] if cy + 1 < lh else -1

			var on_coast: bool = left_o < 0 or right_o < 0 or up_o < 0 or down_o < 0
			var on_seam: bool = not on_coast and (left_o != owner or right_o != owner or up_o != owner or down_o != owner)
			if on_coast:
				var rim: Color = Color(0.68, 0.44, 0.84, 1.0) if is_witch else coast_ink
				base_land = base_land.lerp(rim, 0.78)
			elif on_seam:
				base_land = base_land.lerp(border_col, 0.62)

			img.set_pixel(px, py, base_land)

	_continent_base_tex = ImageTexture.create_from_image(img)
	return _continent_base_tex


func _ensure_state_overlay(zones: Array[Dictionary], discovered: Dictionary, current_zid: String) -> ImageTexture:
	var disc_keys: PackedStringArray = PackedStringArray()
	for k: Variant in discovered:
		disc_keys.append(String(k))
	disc_keys.sort()
	var sig: String = "%s|%s|%s" % [hovered_zone_id, current_zid, ",".join(disc_keys)]
	if _state_tex != null and _state_sig == sig:
		return _state_tex
	_state_sig = sig

	var layout: Dictionary = ZoneCatalog.continent_layout("main")
	var lw: int = int(layout["width"])
	var lh: int = int(layout["height"])
	var owner_grid: PackedInt32Array = layout["owner_grid"] as PackedInt32Array

	var img: Image = Image.create(lw, lh, false, Image.FORMAT_RGBA8)
	for y: int in range(lh):
		for x: int in range(lw):
			var idx: int = y * lw + x
			var owner: int = owner_grid[idx]
			if owner < 0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var z: Dictionary = zones[owner]
			var zid: String = String(z.get("id", ""))
			var unlocked: bool = bool(z.get("unlocked", false))
			var seen: bool = discovered.has(zid)
			var is_hov: bool = (zid == hovered_zone_id)
			var is_cur: bool = (zid == current_zid)

			var on_edge: bool = false
			if is_cur or is_hov:
				var lo: int = owner_grid[idx - 1] if x > 0 else -1
				var ro: int = owner_grid[idx + 1] if x + 1 < lw else -1
				var uo: int = owner_grid[idx - lw] if y > 0 else -1
				var do_n: int = owner_grid[idx + lw] if y + 1 < lh else -1
				on_edge = (lo != owner or ro != owner or uo != owner or do_n != owner)

			var overlay: Color = Color(0, 0, 0, 0)
			if not unlocked:
				overlay = Color(0.03, 0.04, 0.07, 0.42 if not is_hov else 0.14)
			elif not seen:
				overlay = Color(0.04, 0.06, 0.08, 0.22)
			elif is_cur:
				overlay = Color(0.98, 0.88, 0.45, 0.92 if on_edge else 0.18)

			if is_hov and not is_cur:
				overlay = Color(0.55, 0.92, 0.82, 0.85 if on_edge else 0.22)
			img.set_pixel(x, y, overlay)

	if _state_tex == null:
		_state_tex = ImageTexture.create_from_image(img)
	else:
		_state_tex.update(img)
	return _state_tex


func _draw_continent_tier(canvas: Control, rect: Rect2, fade: float, time_sec: float, zone_world: Variant, local_player: Player) -> void:
	canvas.draw_rect(rect, Color(0.04, 0.09, 0.15, fade), true)
	var cont: Dictionary = ZoneCatalog.main_continent()
	var layout: Dictionary = ZoneCatalog.continent_layout("main")
	var zones: Array[Dictionary] = ZoneCatalog.zone_summaries("main")
	var m_rect: Rect2 = rect.grow(-4.0)
	_last_continent_rect = m_rect

	var to_norm: Callable = func(uv: Vector2) -> Vector2:
		return m_rect.position + Vector2(uv.x * m_rect.size.x, uv.y * m_rect.size.y)

	var discovered: Dictionary = (zone_world.call("discovered_zones") as Dictionary) if zone_world != null and zone_world.has_method("discovered_zones") else {"start_path": true}
	var current_zid: String = _current_player_zone(zone_world, local_player)

	## 1. Base seamless continent & Voronoi province raster + dynamic hover/lock overlay
	var base_tex: ImageTexture = _ensure_continent_base_texture()
	var state_tex: ImageTexture = _ensure_state_overlay(zones, discovered, current_zid)
	canvas.draw_texture_rect(base_tex, m_rect, false, Color(1.0, 1.0, 1.0, fade))
	canvas.draw_texture_rect(state_tex, m_rect, false, Color(1.0, 1.0, 1.0, fade))

	## 2. Void corruption rifts along outer rim
	for edge_v: Variant in cont.get("void_edges", []) as Array:
		if not (edge_v is Array):
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		for pt_v: Variant in edge_v as Array:
			if pt_v is Array and (pt_v as Array).size() >= 2:
				var a: Array = pt_v as Array
				pts.append(to_norm.call(Vector2(float(a[0]), float(a[1]))))
		if pts.size() >= 2:
			canvas.draw_polyline(pts, Color(0.55, 0.20, 0.72, (0.32 + 0.18 * sin(time_sec * 2.0)) * fade), 6.0, true)
			canvas.draw_polyline(pts, Color(0.76, 0.42, 0.94, 0.65 * fade), 1.5, true)

	## 3. Zone centers from true province centroids & travel routes
	var centers_uv: Dictionary = layout.get("zone_centers", {}) as Dictionary
	var zone_pos_map: Dictionary = {}
	for z: Dictionary in zones:
		var zid: String = String(z.get("id", ""))
		var uv_c: Vector2 = centers_uv.get(zid, Vector2(0.5, 0.5)) as Vector2
		zone_pos_map[zid] = to_norm.call(uv_c)

	var drawn_edges: Dictionary = {}
	for z: Dictionary in zones:
		var a_id: String = String(z.get("id", ""))
		if not zone_pos_map.has(a_id):
			continue
		var a_pt: Vector2 = zone_pos_map[a_id] as Vector2
		var a_open: bool = bool(z.get("unlocked", false))
		for b_v: Variant in z.get("connections", []) as Array:
			var b_id: String = String(b_v)
			if not zone_pos_map.has(b_id):
				continue
			var ek: String = a_id + ":" + b_id if a_id < b_id else b_id + ":" + a_id
			if drawn_edges.has(ek):
				continue
			drawn_edges[ek] = true
			var b_pt: Vector2 = zone_pos_map[b_id] as Vector2
			var b_open: bool = bool(ZoneCatalog.zone_summary(b_id).get("unlocked", false))
			var col: Color = Color("e8d9a6") if (a_open and b_open) else Color(0.64, 0.68, 0.74, 0.34)
			canvas.draw_line(a_pt, b_pt, Color(col, col.a * fade), 2.0 if (a_open and b_open) else 1.0)

	## 4. Subtle Start Area (~13% x ~17% bottom-left) & Biome Region Headings
	var sab: Array = cont.get("start_area_bounds", [0.03, 0.79, 0.16, 0.96]) as Array
	if sab.size() >= 4:
		var sa_p0: Vector2 = to_norm.call(Vector2(float(sab[0]), float(sab[1])))
		var sa_p1: Vector2 = to_norm.call(Vector2(float(sab[2]), float(sab[3])))
		var sa_rect: Rect2 = Rect2(sa_p0, sa_p1 - sa_p0)
		canvas.draw_rect(sa_rect, Color(0.95, 0.84, 0.48, 0.25 * fade), false, 1.0)
		_text(canvas, "STARTBEREICH", Vector2i(int(sa_rect.position.x), int(sa_rect.end.y + 3.0)), Color("e6d49c"), fade)

	_text(canvas, "HEXENWALD", Vector2i(int(to_norm.call(Vector2(0.75, 0.04)).x), int(to_norm.call(Vector2(0.75, 0.04)).y)), Color("c59ee8"), fade)

	## 5. Non-overlapping Zone Names, Waystone & Icons
	for z: Dictionary in zones:
		var zid: String = String(z.get("id", ""))
		var unlocked: bool = bool(z.get("unlocked", false))
		var ctr: Vector2 = zone_pos_map.get(zid, rect.get_center()) as Vector2
		if z.has("waystone") and unlocked:
			var ws: Dictionary = z.get("waystone", {}) as Dictionary
			var wa: Array = ws.get("pos", [0.5, 0.5]) as Array
			var wpt: Vector2 = to_norm.call(Vector2(float(wa[0]), float(wa[1])))
			_draw_diamond(canvas, wpt, 3.8, Color("6df2e2"), Color.WHITE, fade)
		if unlocked:
			if zid == "start_path":
				_text(canvas, "ABSTIEG", Vector2i(int(ctr.x) - 42, int(ctr.y) - 24), Color("f0ebdc"), fade)
			elif zid == "home_valley":
				_text(canvas, "VALDRICS TAL", Vector2i(int(ctr.x) + 12, int(ctr.y) - 22), Color("f0ebdc"), fade)
				_text(canvas, "HEIMAT", Vector2i(int(ctr.x) + 12, int(ctr.y) + 8), Color("ffe680"), fade)
			else:
				_text_center(canvas, String(z.get("name", zid)), ctr - Vector2(0, 12), Color("f0ebdc"), fade)
		elif zid == hovered_zone_id:
			_text_center(canvas, String(z.get("name", zid)), ctr - Vector2(0, 12), Color("cfd8de"), fade)

	## 6. Harbors snapped to actual coastline & Future Quarzwüste Ship Route
	var harbor_uvs: Dictionary = layout.get("harbor_uvs", {}) as Dictionary
	var south_harbor_uv: Vector2 = harbor_uvs.get("harbor_south", Vector2(0.25, 0.90)) as Vector2
	for h_v: Variant in cont.get("harbors", []) as Array:
		if h_v is Dictionary:
			var hid: String = String((h_v as Dictionary).get("id", ""))
			var h_pos_arr: Array = (h_v as Dictionary).get("pos", [0.22, 0.94]) as Array
			var h_uv: Vector2 = harbor_uvs.get(hid, Vector2(float(h_pos_arr[0]), float(h_pos_arr[1]))) as Vector2
			var h_pt: Vector2 = to_norm.call(h_uv)
			canvas.draw_circle(h_pt, 3.2, Color(Color("76b8d9"), fade))
			canvas.draw_arc(h_pt, 4.8, 0.0, TAU, 12, Color(Color("d9f4ff"), 0.7 * fade), 1.0)

	var qd: Dictionary = ZoneCatalog.continent("quartz_desert")
	if not qd.is_empty():
		var q_pos_arr: Array = qd.get("pos", [0.87, 0.90]) as Array
		var q_pt: Vector2 = to_norm.call(Vector2(float(q_pos_arr[0]), float(q_pos_arr[1])))
		var h_pt_src: Vector2 = to_norm.call(south_harbor_uv)
		canvas.draw_line(h_pt_src, q_pt - Vector2(44, 0), Color(0.55, 0.76, 0.88, 0.50 * fade), 1.2)
		var q_card: Rect2 = Rect2(q_pt - Vector2(54, 16), Vector2(108, 32))
		canvas.draw_rect(q_card, Color(0.18, 0.15, 0.12, 0.90 * fade), true)
		canvas.draw_rect(q_card, Color(0.68, 0.56, 0.36, 0.75 * fade), false, 1.0)
		_text_center(canvas, "QUARZWÜSTE", q_pt + Vector2(0, -8), Color("deb878"), fade)
		_text_center(canvas, "SCHIFFSROUTE", q_pt + Vector2(0, 3), Color("8ea8b0"), fade)

	## 7. Live Co-op Option B player markers per zone
	var zone_buckets: Dictionary = {}
	if zone_world != null and zone_world.has_method("players_in_zones"):
		var pz: Dictionary = zone_world.call("players_in_zones") as Dictionary
		for pid_v: Variant in pz:
			var z_key: String = String(pz[pid_v])
			if not zone_buckets.has(z_key):
				zone_buckets[z_key] = []
			(zone_buckets[z_key] as Array).append(int(pid_v))
	elif local_player != null:
		zone_buckets[current_zid] = [local_player.name.to_int()]

	var local_id: int = local_player.name.to_int() if local_player != null else -1
	for zid_b: Variant in zone_buckets:
		var z_str: String = String(zid_b)
		if not zone_pos_map.has(z_str):
			continue
		var base_c: Vector2 = zone_pos_map[z_str] as Vector2
		var list: Array = zone_buckets[z_str] as Array
		for idx: int in range(list.size()):
			var pid: int = int(list[idx])
			var spread_x: float = (float(idx) - float(list.size() - 1) * 0.5) * 12.0
			var m_pos: Vector2 = base_c + Vector2(spread_x, 0.0)
			var col: Color = Color("ffe680") if pid == local_id else Color("7cf4de")
			_draw_diamond(canvas, m_pos, 5.0, col, Color("14101e"), fade)

	## 8. Hover Info Box
	if not hovered_zone_id.is_empty():
		var hz: Dictionary = ZoneCatalog.zone_summary(hovered_zone_id)
		if not hz.is_empty():
			var box: Rect2 = Rect2(rect.position + Vector2(10.0, 10.0), Vector2(215.0, 44.0))
			canvas.draw_rect(box, Color(0.06, 0.06, 0.10, 0.92 * fade), true)
			canvas.draw_rect(box, Color(Color("9fc4b6"), fade), false, 1.0)
			var status: String = "OFFEN - KLICKEN" if bool(hz.get("unlocked", false)) else "NOCH GESPERRT"
			var st_col: Color = Color("7cf4de") if bool(hz.get("unlocked", false)) else Color("d98a7c")
			_text(canvas, String(hz.get("name", hovered_zone_id)), Vector2i(int(box.position.x + 8.0), int(box.position.y + 6.0)), Color("f2e8cf"), fade)
			_text(canvas, String(hz.get("subtitle", "")), Vector2i(int(box.position.x + 8.0), int(box.position.y + 18.0)), Color("9aa3ad"), fade)
			_text(canvas, "%s - %s" % [String(hz.get("tier", "")), status], Vector2i(int(box.position.x + 8.0), int(box.position.y + 30.0)), st_col, fade)


func _draw_diamond(canvas: Control, center: Vector2, r: float, fill: Color, rim: Color, fade: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(0, -r),
		center + Vector2(r, 0),
		center + Vector2(0, r),
		center + Vector2(-r, 0),
	])
	canvas.draw_colored_polygon(pts, Color(fill, fill.a * fade))
	pts.append(pts[0])
	canvas.draw_polyline(pts, Color(rim, rim.a * fade), 1.0, true)


func _text(canvas: Control, text: String, pos: Vector2i, col: Color, fade: float) -> void:
	PixelText.draw(canvas, text, pos, Color(col, col.a * fade), Color(VineStyle.OUTLINE, 0.9 * fade))


func _text_center(canvas: Control, text: String, center: Vector2, col: Color, fade: float) -> void:
	var w: int = PixelText.width(text)
	_text(canvas, text, Vector2i(roundi(center.x) - w / 2, roundi(center.y) - 4), col, fade)
