class_name MapMarkers
extends RefCounted
## Unified marker registry, filtering, clustering/fanning, persistent pins, and quest route computation
## for the v2 Atlas & Zone Map (`SCOPE.md` §3). Operates in continent tile coordinates (`1 tile = 16 px`).

const LEVEL_ORT: int = 1
const LEVEL_ZONE: int = 2
const LEVEL_KONTINENT: int = 4
const LEVEL_WELT: int = 8
const LEVEL_ALL: int = 15

const CAT_QUESTS: StringName = &"quests"
const CAT_WAYSTONES: StringName = &"waystones"
const CAT_CHESTS_PUZZLES: StringName = &"chests_puzzles"
const CAT_NATURE: StringName = &"nature"
const CAT_PLAYERS: StringName = &"players"
const CAT_PINS: StringName = &"pins"

const MAX_PINS_PER_ZONE: int = 40
const MAX_PIN_NOTE_LEN: int = 80
const FAN_START_PX: float = 0.35
const FAN_END_PX: float = 0.60

const PLAYER_TONES: Array[Color] = [
	Color("b9f3ee"),
	Color("ffd98a"),
	Color("ff7fd8"),
	Color("a6e68f"),
]

const PIN_KINDS: Array[Dictionary] = [
	{"id": &"mark", "name": "WEGZEICHEN", "color": Color("b9f3ee"), "rows": ["..X..", ".X.X.", "X...X", ".X.X.", "..X.."]},
	{"id": &"danger", "name": "GEFAHR", "color": Color("ff5f8a"), "rows": ["..X..", "..X..", "..X..", ".....", "..X.."]},
	{"id": &"loot", "name": "FUNDSTELLE", "color": Color("ffd98a"), "rows": ["X...X", ".X.X.", "..X..", ".X.X.", "X...X"]},
	{"id": &"camp", "name": "LAGER", "color": Color("a6e68f"), "rows": ["..X..", ".XXX.", "XXXXX", "X...X", "X...X"]},
	{"id": &"coast_wave", "name": "WINDKAP-WELLE", "color": Color("4fe3c1"), "unlock": &"coast_wave", "stamp_rect": Rect2(76, 4, 16, 16), "rows": ["..X..", ".XXX.", "X.X.X", "XXXXX", ".XXX."]},
]

const FILTER_DEFS: Array[Dictionary] = [
	{"id": CAT_QUESTS, "label": "QUESTS", "color": Color("ffd98a")},
	{"id": CAT_WAYSTONES, "label": "WEGSTEINE", "color": Color("78f4e6")},
	{"id": CAT_CHESTS_PUZZLES, "label": "TRUHEN & RÄTSEL", "color": Color("e6c468")},
	{"id": CAT_NATURE, "label": "ORTE & NATUR", "color": Color("a6ceae")},
	{"id": CAT_PLAYERS, "label": "SPIELER", "color": Color("b9f3ee")},
	{"id": CAT_PINS, "label": "NADELN", "color": Color("ff7fd8")},
]

var _providers: Dictionary = {} ## StringName -> Callable
var _filters: Dictionary = {} ## StringName -> bool
var _pins_by_zone: Dictionary = {} ## StringName -> Array[Dictionary]
var _next_pin_seq: int = 1


func _init() -> void:
	for fdef: Dictionary in FILTER_DEFS:
		_filters[fdef["id"] as StringName] = true
	register_provider(&"pins", Callable(self, "_provide_pins"))


# --- provider registry -----------------------------------------------------------------------------------------------

func register_provider(id: StringName, provider: Callable) -> void:
	if id == &"" or not provider.is_valid():
		return
	_providers[id] = provider


func unregister_provider(id: StringName) -> void:
	_providers.erase(id)


func has_provider(id: StringName) -> bool:
	return _providers.has(id)


func register_default_providers() -> void:
	register_provider(&"players", Callable(self, "_provide_players"))
	register_provider(&"quests", Callable(self, "_provide_quests"))
	register_provider(&"waystones", Callable(self, "_provide_waystones"))
	register_provider(&"chests_puzzles", Callable(self, "_provide_chests_puzzles"))
	register_provider(&"vistas", Callable(self, "_provide_vistas"))
	register_provider(&"pets", Callable(self, "_provide_pets"))
	register_provider(&"landmarks", Callable(self, "_provide_landmarks"))
	register_provider(&"actors_town", Callable(self, "_provide_actors_town"))
	register_provider(&"dungeons", Callable(self, "_provide_dungeons"))


func collect(context: Dictionary) -> Array[Dictionary]:
	var keys: Array[StringName] = []
	for k: Variant in _providers.keys():
		keys.append(k as StringName)
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))

	var by_id: Dictionary = {} ## StringName -> Dictionary
	var apply_filters: bool = _to_bool(context.get("apply_filters", true), true)
	for pid: StringName in keys:
		var cb: Callable = _providers[pid] as Callable
		if not cb.is_valid():
			continue
		var raw_result: Variant = cb.call(context)
		if not (raw_result is Array):
			continue
		for item: Variant in raw_result as Array:
			if not (item is Dictionary):
				continue
			var marker: Dictionary = _normalize_marker(item as Dictionary, context)
			if marker.is_empty():
				continue
			var cat: StringName = marker["category"] as StringName
			if apply_filters and not is_filter_enabled(cat):
				continue
			var mid: StringName = marker["id"] as StringName
			if by_id.has(mid):
				var prev: Dictionary = by_id[mid] as Dictionary
				if int(marker["priority"]) > int(prev["priority"]):
					by_id[mid] = marker
			else:
				by_id[mid] = marker

	var out: Array[Dictionary] = []
	for m: Variant in by_id.values():
		out.append(m as Dictionary)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a["priority"])
		var pb: int = int(b["priority"])
		if pa != pb:
			return pa > pb
		return String(a["id"]) < String(b["id"]))
	return out


func _normalize_marker(raw: Dictionary, context: Dictionary) -> Dictionary:
	var pos_val: Variant = raw.get("pos")
	var pos: Vector2 = Vector2.INF
	if pos_val is Vector2:
		pos = pos_val as Vector2
	elif pos_val is Vector2i:
		pos = Vector2(pos_val as Vector2i)
	if not pos.is_finite():
		return {}

	var kind_str: String = _dict_str(raw, "kind", "mark")
	var kind: StringName = StringName(kind_str) if not kind_str.is_empty() else &"mark"

	var id_str: String = _dict_str(raw, "id", "")
	var id: StringName = StringName(id_str) if not id_str.is_empty() else StringName("%s_%d_%d" % [String(kind), roundi(pos.x), roundi(pos.y)])

	var cat_str: String = _dict_str(raw, "category", "")
	var category: StringName = StringName(cat_str) if not cat_str.is_empty() else _default_category_for_kind(kind)

	var zone_str: String = _dict_str(raw, "zone", "")
	var zone: StringName = StringName(zone_str)
	var atlas_v: Variant = context.get("atlas")
	var atlas: Atlas = atlas_v as Atlas if atlas_v is Atlas else null
	if zone == &"" and atlas != null:
		var cont: StringName = _context_continent_id(context)
		zone = atlas.zone_at_tile(cont, pos)

	var levels: int = _to_int(raw.get("levels", LEVEL_ORT | LEVEL_ZONE), LEVEL_ORT | LEVEL_ZONE)
	var priority: int = _to_int(raw.get("priority", 50), 50)
	var label: String = _dict_str(raw, "label", "")
	var anim: StringName = StringName(_dict_str(raw, "anim", ""))

	var color: Color = Color("f1e6ff")
	var col_val: Variant = raw.get("color")
	if col_val is Color:
		color = col_val as Color
	else:
		var col_str: String = _dict_str(raw, "color", "").strip_edges()
		if not col_str.is_empty():
			color = Color.from_string(col_str, color)

	var data: Dictionary = (raw.get("data") as Dictionary).duplicate() if raw.get("data") is Dictionary else {}

	return {
		"id": id,
		"kind": kind,
		"category": category,
		"pos": pos,
		"zone": zone,
		"levels": levels,
		"priority": priority,
		"label": label,
		"anim": anim,
		"color": color,
		"data": data,
	}


static func _dict_str(d: Dictionary, key: String, fallback: String = "") -> String:
	var v: Variant = d.get(key)
	if v == null:
		return fallback
	if v is String or v is StringName:
		return str(v)
	if v is int or v is float or v is bool:
		return str(v)
	return fallback


static func _to_float(v: Variant, fallback: float = 0.0) -> float:
	if v is float:
		var f: float = v as float
		return f if is_finite(f) else fallback
	if v is int:
		return float(v as int)
	if v is String or v is StringName:
		var s: String = str(v).strip_edges()
		if s.is_valid_float():
			var f: float = s.to_float()
			return f if is_finite(f) else fallback
	return fallback


static func _to_int(v: Variant, fallback: int = 0) -> int:
	if v is int:
		return v as int
	if v is float:
		var f: float = v as float
		if is_finite(f) and absf(f) <= 2147483647.0:
			return int(f)
		return fallback
	if v is String or v is StringName:
		var s: String = str(v).strip_edges()
		if s.is_valid_int():
			return s.to_int()
	return fallback


static func _to_bool(v: Variant, fallback: bool = false) -> bool:
	if v is bool:
		return v as bool
	if v is int:
		return (v as int) != 0
	if v is float:
		var f: float = v as float
		return (f != 0.0) if is_finite(f) else fallback
	if v is String or v is StringName:
		var s: String = str(v).strip_edges().to_lower()
		if s == "true" or s == "1":
			return true
		if s == "false" or s == "0":
			return false
		return fallback
	return fallback


static func _context_continent_id(context: Dictionary) -> StringName:
	var cid: String = _dict_str(context, "continent_id", "")
	if not cid.is_empty():
		return StringName(cid)
	var cont: String = _dict_str(context, "continent", "")
	if not cont.is_empty():
		return StringName(cont)
	return &"main"


static func _parse_pin_seq(pid: String) -> int:
	if not pid.begins_with("pin_"):
		return 0
	var tail: String = pid.substr(4)
	if tail.is_valid_int():
		return maxi(0, tail.to_int())
	return 0


static func _default_category_for_kind(kind: StringName) -> StringName:
	var k: String = String(kind)
	if k.begins_with("quest") or k == "board_notice":
		return CAT_QUESTS
	if k.begins_with("waystone"):
		return CAT_WAYSTONES
	if k == "chest" or k == "puzzle":
		return CAT_CHESTS_PUZZLES
	if k == "self" or k == "player":
		return CAT_PLAYERS
	if k.begins_with("pin"):
		return CAT_PINS
	return CAT_NATURE


# --- filters (bottom branch F) ---------------------------------------------------------------------------------------

func set_filter(category: StringName, enabled: bool) -> void:
	_filters[category] = enabled


func is_filter_enabled(category: StringName) -> bool:
	return bool(_filters.get(category, true))


func toggle_filter(category: StringName) -> void:
	_filters[category] = not is_filter_enabled(category)


func filter_categories() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fdef: Dictionary in FILTER_DEFS:
		var cid: StringName = fdef["id"] as StringName
		out.append({
			"id": cid,
			"label": String(fdef["label"]),
			"color": fdef["color"] as Color,
			"enabled": is_filter_enabled(cid),
		})
	return out


# --- clustering & zoom fanning ---------------------------------------------------------------------------------------

func cluster_for_level(markers: Array[Dictionary], level: StringName, px_per_tile: float, threshold_px: float = 20.0) -> Array[Dictionary]:
	var bit: int = _level_bit(level)
	var filtered: Array[Dictionary] = []
	for m: Dictionary in markers:
		if not _marker_pos(m).is_finite():
			continue
		if (_to_int(m.get("levels", LEVEL_ORT | LEVEL_ZONE), LEVEL_ORT | LEVEL_ZONE) & bit) != 0:
			filtered.append(m)

	if bit == LEVEL_ORT or bit == LEVEL_ZONE:
		return _fan_overlapping(filtered, px_per_tile, threshold_px * 0.7)

	var exempt: Array[Dictionary] = []
	var clusterable: Array[Dictionary] = []
	for m: Dictionary in filtered:
		var d: Dictionary = m.get("data", {}) as Dictionary if m.get("data") is Dictionary else {}
		var nc_v: Variant = d.get("no_cluster", false)
		var no_cluster: bool = (nc_v as bool) if nc_v is bool else ((nc_v as int) != 0 if nc_v is int else false)
		var kind_str: String = _dict_str(m, "kind", "mark")
		var m_kind: StringName = StringName(kind_str) if not kind_str.is_empty() else &"mark"
		if no_cluster or m_kind == &"self":
			exempt.append(m.duplicate(true))
		else:
			clusterable.append(m)

	var fan_t: float = 0.0
	if bit == LEVEL_KONTINENT:
		fan_t = clampf((px_per_tile - FAN_START_PX) / (FAN_END_PX - FAN_START_PX), 0.0, 1.0)

	var used: Array[bool] = []
	used.resize(clusterable.size())
	var out: Array[Dictionary] = []

	for i: int in clusterable.size():
		if used[i]:
			continue
		used[i] = true
		var seed_m: Dictionary = clusterable[i]
		var seed_zone: StringName = StringName(_dict_str(seed_m, "zone", ""))
		var seed_pos: Vector2 = _marker_pos(seed_m)
		var members: Array[Dictionary] = [seed_m]
		for j: int in range(i + 1, clusterable.size()):
			if used[j]:
				continue
			var cand: Dictionary = clusterable[j]
			var cand_zone: StringName = StringName(_dict_str(cand, "zone", ""))
			var cand_pos: Vector2 = _marker_pos(cand)
			var screen_dist: float = seed_pos.distance_to(cand_pos) * maxf(px_per_tile, 0.001)
			var group_hit: bool = false
			if bit == LEVEL_KONTINENT and seed_zone != &"" and seed_zone == cand_zone:
				group_hit = fan_t < 0.25 or screen_dist <= threshold_px * 1.5
			else:
				group_hit = screen_dist <= threshold_px
			if group_hit:
				used[j] = true
				members.append(cand)

		if members.size() == 1:
			out.append(members[0].duplicate(true))
			continue

		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa: int = _to_int(a.get("priority", 50), 50)
			var pb: int = _to_int(b.get("priority", 50), 50)
			if pa != pb:
				return pa > pb
			return _dict_str(a, "id", "") < _dict_str(b, "id", ""))

		var center_tile: Vector2 = Vector2.ZERO
		for m: Dictionary in members:
			center_tile += _marker_pos(m)
		center_tile /= float(members.size())

		if fan_t <= 0.01:
			var top: Dictionary = members[0]
			var top_data: Dictionary = (top.get("data", {}) as Dictionary).duplicate() if top.get("data") is Dictionary else {}
			var rep_kind_str: String = _dict_str(top, "kind", "mark")
			top_data["cluster"] = true
			top_data["count"] = members.size()
			top_data["cluster_count"] = members.size()
			top_data["rep_kind"] = StringName(rep_kind_str) if not rep_kind_str.is_empty() else &"mark"
			top_data["members"] = members
			top_data["cluster_t"] = 0.0
			out.append({
				"id": StringName("cluster_%s_%s" % [String(seed_zone), _dict_str(top, "id", "")]),
				"kind": &"cluster",
				"category": top.get("category", CAT_NATURE),
				"pos": center_tile,
				"zone": seed_zone,
				"levels": bit,
				"priority": _to_int(top.get("priority", 50), 50),
				"label": str(members.size()),
				"anim": &"pulse",
				"color": top.get("color", Color("f1e6ff")),
				"data": top_data,
			})
		else:
			var u: float = fan_t * fan_t * (3.0 - 2.0 * fan_t)
			var min_ring_tiles: float = (threshold_px * 0.85) / maxf(px_per_tile, 0.01)
			for idx: int in members.size():
				var member: Dictionary = members[idx].duplicate(true)
				var orig_pos: Vector2 = _marker_pos(member)
				if not orig_pos.is_finite():
					orig_pos = center_tile
				var target_pos: Vector2 = orig_pos
				if orig_pos.distance_to(center_tile) < min_ring_tiles:
					target_pos = center_tile + Vector2.from_angle(TAU * float(idx) / float(members.size())) * min_ring_tiles
				member["pos"] = center_tile.lerp(target_pos, u)
				var mdata: Dictionary = member.get("data", {}) as Dictionary if member.get("data") is Dictionary else {}
				mdata["anchor_pos"] = center_tile
				mdata["orig_pos"] = orig_pos
				mdata["fanned"] = true
				mdata["cluster_t"] = u
				member["data"] = mdata
				out.append(member)

	for ex: Dictionary in exempt:
		out.append(ex)
	return out


static func _marker_pos(m: Dictionary) -> Vector2:
	var pos_v: Variant = m.get("pos")
	if pos_v is Vector2:
		return pos_v as Vector2
	if pos_v is Vector2i:
		return Vector2(pos_v as Vector2i)
	return Vector2.INF


static func _level_bit(level: StringName) -> int:
	match String(level).to_lower():
		"ort":
			return LEVEL_ORT
		"zone":
			return LEVEL_ZONE
		"continent", "kontinent":
			return LEVEL_KONTINENT
		"world", "welt":
			return LEVEL_WELT
	return LEVEL_ZONE


static func _fan_overlapping(markers: Array[Dictionary], px_per_tile: float, min_dist_px: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var placed_px: Array[Vector2] = []
	var scale_px: float = maxf(px_per_tile, 0.01)
	for m: Dictionary in markers:
		var orig_pos: Vector2 = _marker_pos(m)
		if not orig_pos.is_finite():
			continue
		var item: Dictionary = m.duplicate(true)
		var anchor_px: Vector2 = orig_pos * scale_px
		var d: Dictionary = item.get("data", {}) as Dictionary if item.get("data") is Dictionary else {}
		var nc_v: Variant = d.get("no_cluster", false)
		var no_cluster: bool = (nc_v as bool) if nc_v is bool else ((nc_v as int) != 0 if nc_v is int else false)
		var kind_str: String = _dict_str(item, "kind", "mark")
		var kind: StringName = StringName(kind_str) if not kind_str.is_empty() else &"mark"
		if no_cluster or kind == &"self":
			placed_px.append(anchor_px)
			out.append(item)
			continue
		var chosen_px: Vector2 = anchor_px
		var found_spot: bool = false
		for ring: int in 5:
			var steps: int = 1 if ring == 0 else 8
			for k: int in steps:
				var offset_px: Vector2 = Vector2.ZERO if ring == 0 else Vector2.from_angle(TAU * float(k) / float(steps)) * float(ring) * min_dist_px
				var cand_px: Vector2 = anchor_px + offset_px
				var clear: bool = true
				for prev_px: Vector2 in placed_px:
					if cand_px.distance_to(prev_px) < min_dist_px:
						clear = false
						break
				if clear:
					chosen_px = cand_px
					found_spot = true
					break
			if found_spot:
				break
		placed_px.append(chosen_px)
		if chosen_px.distance_to(anchor_px) > 0.5:
			item["pos"] = chosen_px / scale_px
			d["anchor_pos"] = orig_pos
			d["fanned"] = true
			item["data"] = d
		out.append(item)
	return out


# --- persistent per-zone pins ----------------------------------------------------------------------------------------

static func pin_kind_from_index(idx: int) -> StringName:
	var clamped: int = posmod(idx, PIN_KINDS.size())
	return PIN_KINDS[clamped]["id"] as StringName


static func pin_kind_spec(kind: StringName) -> Dictionary:
	for spec: Dictionary in PIN_KINDS:
		if (spec["id"] as StringName) == kind:
			return spec
	return PIN_KINDS[0]


func add_pin(zone_id: StringName, tile_pos: Vector2, kind: StringName, note: String = "") -> Dictionary:
	if not tile_pos.is_finite():
		return {}
	var list: Array[Dictionary] = _pins_by_zone.get(zone_id, [] as Array[Dictionary]) as Array[Dictionary]
	if list.size() >= MAX_PINS_PER_ZONE:
		list.pop_front()
	var spec: Dictionary = pin_kind_spec(kind)
	var clean_kind: StringName = spec["id"] as StringName
	var clean_note: String = note.strip_edges().left(MAX_PIN_NOTE_LEN)
	var pin_id: StringName = StringName("pin_%d" % _next_pin_seq)
	_next_pin_seq += 1
	var pin: Dictionary = {
		"id": pin_id,
		"zone": zone_id,
		"pos": tile_pos,
		"kind": clean_kind,
		"note": clean_note,
		"created_at": int(Time.get_unix_time_from_system()),
	}
	list.append(pin)
	_pins_by_zone[zone_id] = list
	return pin.duplicate()


func remove_nearest_pin(zone_id: StringName, tile_pos: Vector2, max_dist_tiles: float) -> bool:
	if not tile_pos.is_finite() or not _pins_by_zone.has(zone_id):
		return false
	var list: Array[Dictionary] = _pins_by_zone[zone_id] as Array[Dictionary]
	var best_idx: int = -1
	var best_dist: float = max_dist_tiles
	for i: int in list.size():
		var d: float = (list[i]["pos"] as Vector2).distance_to(tile_pos)
		if d <= best_dist:
			best_dist = d
			best_idx = i
	if best_idx < 0:
		return false
	list.remove_at(best_idx)
	if list.is_empty():
		_pins_by_zone.erase(zone_id)
	return true


func pins_for_zone(zone_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _pins_by_zone.has(zone_id):
		return out
	for p: Dictionary in _pins_by_zone[zone_id] as Array[Dictionary]:
		out.append(p.duplicate())
	return out


func export_pins() -> Dictionary:
	var zones_out: Dictionary = {}
	for zid: StringName in _pins_by_zone:
		var arr: Array[Dictionary] = []
		for p: Dictionary in _pins_by_zone[zid] as Array[Dictionary]:
			var pos: Vector2 = p["pos"] as Vector2
			arr.append({
				"id": String(p["id"]),
				"pos": [pos.x, pos.y],
				"kind": String(p["kind"]),
				"note": String(p.get("note", "")),
				"created_at": int(p.get("created_at", 0)),
			})
		if not arr.is_empty():
			zones_out[String(zid)] = arr
	return {"version": 1, "seq": _next_pin_seq, "zones": zones_out}


func import_pins(data: Dictionary) -> void:
	_pins_by_zone.clear()
	_next_pin_seq = maxi(1, _to_int(data.get("seq", 1), 1))
	var zones_in: Variant = data.get("zones", {})
	if not (zones_in is Dictionary):
		return
	var max_seen_seq: int = 0
	for raw_zid_scan: Variant in zones_in as Dictionary:
		var raw_arr_scan: Variant = (zones_in as Dictionary)[raw_zid_scan]
		if not (raw_arr_scan is Array):
			continue
		for item_scan: Variant in raw_arr_scan as Array:
			if item_scan is Dictionary:
				var pid_scan: String = _dict_str(item_scan as Dictionary, "id", "").strip_edges()
				max_seen_seq = maxi(max_seen_seq, _parse_pin_seq(pid_scan))
	_next_pin_seq = maxi(_next_pin_seq, max_seen_seq + 1)

	for raw_zid: Variant in zones_in as Dictionary:
		var zid_str: String = str(raw_zid) if (raw_zid is String or raw_zid is StringName) else ""
		if zid_str.is_empty():
			continue
		var zid: StringName = StringName(zid_str)
		var raw_arr: Variant = (zones_in as Dictionary)[raw_zid]
		if not (raw_arr is Array):
			continue
		var list: Array[Dictionary] = []
		for item: Variant in raw_arr as Array:
			if not (item is Dictionary):
				continue
			var pd: Dictionary = item as Dictionary
			var raw_pos: Variant = pd.get("pos")
			if not (raw_pos is Array) or (raw_pos as Array).size() < 2:
				continue
			var pos_arr: Array = raw_pos as Array
			var px: float = _to_float(pos_arr[0], INF)
			var py: float = _to_float(pos_arr[1], INF)
			var pos: Vector2 = Vector2(px, py)
			if not pos.is_finite():
				continue
			var kind_str: String = _dict_str(pd, "kind", "mark")
			var spec: Dictionary = pin_kind_spec(StringName(kind_str) if not kind_str.is_empty() else &"mark")
			var pid_str: String = _dict_str(pd, "id", "").strip_edges()
			if pid_str.is_empty():
				pid_str = "pin_%d" % _next_pin_seq
				_next_pin_seq += 1
			var pid: StringName = StringName(pid_str)
			list.append({
				"id": pid,
				"zone": zid,
				"pos": pos,
				"kind": spec["id"] as StringName,
				"note": _dict_str(pd, "note", "").strip_edges().left(MAX_PIN_NOTE_LEN),
				"created_at": _to_int(pd.get("created_at", 0), 0),
			})
			if list.size() >= MAX_PINS_PER_ZONE:
				break
		if not list.is_empty():
			_pins_by_zone[zid] = list


func _provide_pins(_context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for zid: StringName in _pins_by_zone:
		for p: Dictionary in _pins_by_zone[zid] as Array[Dictionary]:
			var kind: StringName = p["kind"] as StringName
			var spec: Dictionary = pin_kind_spec(kind)
			var note: String = String(p.get("note", ""))
			var label: String = note if not note.is_empty() else String(spec["name"])
			out.append({
				"id": p["id"] as StringName,
				"kind": &"pin",
				"category": CAT_PINS,
				"pos": p["pos"] as Vector2,
				"zone": zid,
				"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
				"priority": 65,
				"label": label,
				"anim": &"bounce",
				"color": spec["color"] as Color,
				"data": {"pin_kind": kind, "note": note, "spec": spec, "created_at": int(p.get("created_at", 0))},
			})
	return out


# --- off-zone quest routing & threshold arrows -----------------------------------------------------------------------

func compute_quest_routes(atlas: Atlas, from_zone: StringName, from_tile: Vector2, quest_markers: Array[Dictionary], flags: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if atlas == null or from_zone == &"":
		return out
	var origin_zone: Atlas.Zone = atlas.zone(from_zone)
	if origin_zone == null:
		return out
	var start_tile: Vector2 = from_tile if from_tile.is_finite() else origin_zone.center()
	var continent_id: StringName = origin_zone.continent

	for qm: Dictionary in quest_markers:
		var q_pos_raw: Variant = qm.get("pos", Vector2.INF)
		var q_pos: Vector2 = q_pos_raw as Vector2 if q_pos_raw is Vector2 else (Vector2(q_pos_raw as Vector2i) if q_pos_raw is Vector2i else Vector2.INF)
		var to_zone: StringName = StringName(_dict_str(qm, "zone", ""))
		if to_zone == &"" and q_pos.is_finite():
			to_zone = atlas.zone_at_tile(continent_id, q_pos)
		if to_zone == &"" or to_zone == from_zone:
			continue
		var dest_zone: Atlas.Zone = atlas.zone(to_zone)
		if dest_zone == null:
			continue
		var chain: Array[Atlas.Threshold] = atlas.route(from_zone, to_zone, flags, start_tile)
		if chain.is_empty():
			continue
		var end_tile: Vector2 = q_pos if q_pos.is_finite() else dest_zone.center()
		var path: PackedVector2Array = PackedVector2Array([start_tile])
		for t: Atlas.Threshold in chain:
			path.append(t.midpoint())
		path.append(end_tile)
		var first_t: Atlas.Threshold = chain[0]
		var mid: Vector2 = first_t.midpoint()
		var dir_vec: Vector2 = mid - start_tile
		if dir_vec.length_squared() <= 0.0001:
			dir_vec = end_tile - start_tile
		var edge_dir: Vector2 = dir_vec.normalized() if dir_vec.length_squared() > 0.0001 else Vector2.RIGHT
		var next_threshold: Dictionary = {
			"id": first_t.id,
			"kind": first_t.kind,
			"pos": mid,
			"to_zone": first_t.other(from_zone),
			"seamless": first_t.seamless(),
			"open": Atlas.is_threshold_open(first_t, flags),
			"closed_reason": first_t.closed_reason,
		}
		out.append({
			"marker": qm.duplicate(true),
			"path": path,
			"next_threshold": next_threshold,
			"edge_dir": edge_dir,
		})
	return out


# --- built-in game providers -----------------------------------------------------------------------------------------

static func _context_tree(context: Dictionary) -> SceneTree:
	var tree_val: Variant = context.get("tree")
	if tree_val is SceneTree:
		return tree_val as SceneTree
	return Engine.get_main_loop() as SceneTree


static func _is_tile_seen(context: Dictionary, tile: Vector2) -> bool:
	var disc: Variant = context.get("discovery")
	if disc == null or not (disc is Object):
		return true
	var obj: Object = disc as Object
	if obj.has_method("is_reveal_all") and bool(obj.call("is_reveal_all")):
		return true
	if obj.has_method("is_seen"):
		return bool(obj.call("is_seen", tile))
	return true


static func _outer_px(tree: SceneTree, world_px: Vector2) -> Vector2:
	if tree != null:
		return Interiors.outer(tree, world_px)
	return Interiors.to_world(world_px)


static func _local_player(context: Dictionary) -> Player:
	var lp: Variant = context.get("local_player")
	if lp is Player:
		return lp as Player
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority():
			return p
	return null


func _provide_players(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree: SceneTree = _context_tree(context)
	var atlas_v: Variant = context.get("atlas")
	var atlas: Atlas = atlas_v as Atlas if atlas_v is Atlas else null
	var cont_id: StringName = _context_continent_id(context)
	var lp: Player = _local_player(context)

	var peers: Array[int] = []
	var by_peer: Dictionary = {}
	for p: Player in Player.all:
		if not is_instance_valid(p):
			continue
		var pid: int = p.name.to_int()
		peers.append(pid)
		by_peer[pid] = p
	peers.sort()

	var emitted_peers: Dictionary = {}
	for idx: int in peers.size():
		var pid: int = peers[idx]
		var p: Player = by_peer[pid] as Player
		var raw_px: Vector2 = p.global_position
		var outer_px: Vector2 = _outer_px(tree, raw_px)
		var inside: bool = PocketSpace.is_pocket(raw_px) or Interiors.is_pocket(raw_px)
		var tile: Vector2 = Vector2.INF
		var z_id: StringName = &""
		if outer_px.is_finite() and not PocketSpace.is_pocket(outer_px) and not (inside and outer_px == Vector2.ZERO):
			tile = Atlas.tile_of(outer_px)
			if atlas != null:
				z_id = atlas.zone_at_tile(cont_id, tile)
		elif atlas != null:
			var pzone: StringName = PocketSpace.parent_zone_at(raw_px)
			if pzone != &"" and atlas.zone(pzone) != null:
				z_id = pzone
				tile = atlas.zone(pzone).center()
		if not tile.is_finite():
			continue
		var is_self: bool = (p == lp) or (lp == null and p.is_multiplayer_authority())
		var pname: String = NetworkManager.player_name_for(pid)
		var ptitle: String = p.appearance.title_text() if p.appearance != null else ""
		var disp_lbl: String = "DU" if is_self else (pname if not pname.is_empty() else "SPIELER %d" % (idx + 1))
		if not ptitle.is_empty():
			disp_lbl = "%s · %s" % [disp_lbl, ptitle]
		emitted_peers[pid] = true
		out.append({
			"id": StringName("player_%d" % pid),
			"kind": &"self" if is_self else &"player",
			"category": CAT_PLAYERS,
			"pos": tile,
			"zone": z_id,
			"levels": LEVEL_ALL,
			"priority": 120 if is_self else 100,
			"label": disp_lbl,
			"anim": &"pulse",
			"color": PLAYER_TONES[idx % PLAYER_TONES.size()],
			"data": {"peer_id": pid, "inside": inside, "no_cluster": is_self, "player_name": pname, "title": ptitle},
		})

	var director: Variant = context.get("director")
	if atlas != null and director is Object:
		var pz_var: Variant = (director as Object).get("player_zone")
		if pz_var is Dictionary:
			var pz_dict: Dictionary = pz_var as Dictionary
			for raw_peer: Variant in pz_dict:
				var pid: int = _to_int(raw_peer, -1)
				if pid < 0 or emitted_peers.has(pid):
					continue
				var pz_val: Variant = pz_dict[raw_peer]
				var z_id: StringName = StringName(str(pz_val)) if (pz_val is String or pz_val is StringName) else &""
				var z: Atlas.Zone = atlas.zone(z_id)
				if z == null:
					continue
				var rname: String = NetworkManager.player_name_for(pid)
				out.append({
					"id": StringName("player_%d" % pid),
					"kind": &"player",
					"category": CAT_PLAYERS,
					"pos": z.center(),
					"zone": z_id,
					"levels": LEVEL_ALL,
					"priority": 100,
					"label": rname if not rname.is_empty() else ("SPIELER %d" % pid),
					"anim": &"pulse",
					"color": PLAYER_TONES[posmod(pid, PLAYER_TONES.size())],
					"data": {"peer_id": pid, "inside": false, "no_cluster": false, "unloaded_zone": true, "player_name": rname, "title": ""},
				})
	return out


func _provide_quests(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lp: Player = _local_player(context)
	if lp == null:
		return out
	var tracked: TrackedQuests = lp.get("tracked") as TrackedQuests
	if tracked == null:
		return out
	var tree: SceneTree = _context_tree(context)

	var focused: Dictionary = tracked.focused()
	if not focused.is_empty():
		var m: Dictionary = _quest_entry_to_marker(focused, tree, false)
		if not m.is_empty():
			out.append(m)

	var notice: Dictionary = tracked.story_board_notice()
	if not notice.is_empty():
		var nm: Dictionary = _quest_entry_to_marker(notice, tree, true)
		if not nm.is_empty():
			out.append(nm)
	return out


func _quest_entry_to_marker(entry: Dictionary, tree: SceneTree, is_notice: bool) -> Dictionary:
	var src: String = _dict_str(entry, "source", "story")
	var target_val: Variant = entry.get("target", Vector2.INF)
	var target_px: Vector2 = target_val as Vector2 if target_val is Vector2 else Vector2.INF
	var inside: bool = target_px.is_finite() and (PocketSpace.is_pocket(target_px) or Interiors.is_pocket(target_px))
	var outer_px: Vector2 = _outer_px(tree, target_px) if target_px.is_finite() else Vector2.INF
	var area_val: Variant = entry.get("area", Vector3.INF)
	var area: Vector3 = area_val as Vector3 if area_val is Vector3 else Vector3.INF

	var pos_tile: Vector2 = Vector2.INF
	if outer_px.is_finite() and not PocketSpace.is_pocket(outer_px) and not (inside and outer_px == Vector2.ZERO):
		pos_tile = Atlas.tile_of(outer_px)
	elif area != Vector3.INF and area.is_finite():
		pos_tile = Vector2(area.x, area.y) / Atlas.TILE_PX
	if not pos_tile.is_finite():
		return {}

	var kind: StringName = &"board_notice" if is_notice else (&"quest_board" if src == "board" else &"quest")
	var color: Color = Color("78f4e6") if (src == "board" or is_notice) else Color("ffd98a")
	var label: String = _dict_str(entry, "title", _dict_str(entry, "area_name", "QUEST"))
	if src == "board" and bool(entry.get("ready", false)):
		label = "MELDEN %s" % _dict_str(entry, "giver_name", "")
	elif is_notice:
		label = _dict_str(entry, "title", "AUFTRAG")

	var data: Dictionary = {
		"source": src,
		"search_tiles": _to_float(entry.get("search", 0.0), 0.0),
		"inside": inside,
		"urgent": bool(entry.get("urgent", false)),
		"bounty": bool(entry.get("bounty", false)),
		"ready": bool(entry.get("ready", false)),
	}
	if area != Vector3.INF and area.is_finite():
		data["area_tile"] = Vector2(area.x, area.y) / Atlas.TILE_PX
		data["area_radius_tiles"] = area.z / Atlas.TILE_PX

	return {
		"id": StringName("quest_%s" % _dict_str(entry, "id", src)),
		"kind": kind,
		"category": CAT_QUESTS,
		"pos": pos_tile,
		"zone": StringName(_dict_str(entry, "zone", "")),
		"levels": LEVEL_ALL,
		"priority": 110 if not is_notice else 95,
		"label": label,
		"anim": &"ring",
		"color": color,
		"data": data,
	}


func _provide_waystones(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree: SceneTree = _context_tree(context)
	var manager: Waystones = Waystones.of(tree) if tree != null else null
	if manager == null:
		return out
	for spec: Dictionary in manager.entries():
		var wid: String = _dict_str(spec, "id", "")
		var tile_arr: Variant = spec.get("tile")
		if wid.is_empty() or not (tile_arr is Array) or (tile_arr as Array).size() < 2:
			continue
		var pair: Array = tile_arr as Array
		var pos: Vector2 = Vector2(_to_float(pair[0], INF), _to_float(pair[1], INF))
		if not pos.is_finite():
			continue
		var awake: bool = bool(spec.get("awake", false))
		var seen: bool = _is_tile_seen(context, pos)
		if not awake and not seen:
			continue
		out.append({
			"id": StringName("waystone_%s" % wid),
			"kind": &"waystone" if awake else &"waystone_sleeping",
			"category": CAT_WAYSTONES,
			"pos": pos,
			"zone": StringName(_dict_str(spec, "zone", "")),
			"levels": LEVEL_ALL if awake else (LEVEL_ORT | LEVEL_ZONE),
			"priority": 85 if awake else 55,
			"label": _dict_str(spec, "name", wid),
			"anim": &"pulse" if awake else &"",
			"color": Color("78f4e6") if awake else Color("9a94b8"),
			"data": {"waystone_id": wid, "awake": awake, "seen": seen},
		})
	return out


func _provide_chests_puzzles(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree: SceneTree = _context_tree(context)
	if tree == null:
		return out

	var atlas_v: Variant = context.get("atlas")
	var atlas: Atlas = atlas_v as Atlas if atlas_v is Atlas else null
	var cont_id: StringName = _context_continent_id(context)
	var chests: LootChests = LootChests.of(tree)
	var puzzles: Puzzles = Puzzles.of(tree)

	if atlas != null:
		for z: Atlas.Zone in atlas.zones_of(cont_id):
			for raw_c: Variant in z.raw.get("chests", []) as Array if z.raw.get("chests") is Array else []:
				if not (raw_c is Dictionary):
					continue
				var spec_c: Dictionary = raw_c as Dictionary
				var cid_z: String = _dict_str(spec_c, "id", "")
				if cid_z.is_empty() or (chests != null and chests.is_open(cid_z)):
					continue
				var ta_z: Variant = spec_c.get("tile")
				if not (ta_z is Array) or (ta_z as Array).size() < 2:
					continue
				var pair_c: Array = ta_z as Array
				var pos_c: Vector2 = Vector2(_to_float(pair_c[0], INF), _to_float(pair_c[1], INF))
				if not pos_c.is_finite():
					continue
				if not z.bbox.grow(2.0).has_point(pos_c):
					pos_c += Vector2(z.origin)
				if not _is_tile_seen(context, pos_c):
					continue
				var tier_z: String = _dict_str(spec_c, "tier", "common")
				out.append({
					"id": StringName("chest_%s" % cid_z),
					"kind": &"chest",
					"category": CAT_CHESTS_PUZZLES,
					"pos": pos_c,
					"zone": z.id,
					"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
					"priority": 45,
					"label": "TRUHE",
					"anim": &"",
					"color": Color("ffd98a") if tier_z != "common" else Color("e6c468"),
					"data": {"chest_id": cid_z, "tier": tier_z},
				})
			for raw_p: Variant in z.raw.get("puzzles", []) as Array if z.raw.get("puzzles") is Array else []:
				if not (raw_p is Dictionary):
					continue
				var spec_p: Dictionary = raw_p as Dictionary
				var pid_z: String = _dict_str(spec_p, "id", "")
				if pid_z.is_empty() or (puzzles != null and puzzles.is_solved(pid_z)):
					continue
				var ta_p: Variant = spec_p.get("tile")
				if not (ta_p is Array) or (ta_p as Array).size() < 2:
					continue
				var pair_p: Array = ta_p as Array
				var pos_p: Vector2 = Vector2(_to_float(pair_p[0], INF), _to_float(pair_p[1], INF))
				if not pos_p.is_finite():
					continue
				if not z.bbox.grow(2.0).has_point(pos_p):
					pos_p += Vector2(z.origin)
				if not _is_tile_seen(context, pos_p):
					continue
				out.append({
					"id": StringName("puzzle_%s" % pid_z),
					"kind": &"puzzle",
					"category": CAT_CHESTS_PUZZLES,
					"pos": pos_p,
					"zone": z.id,
					"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
					"priority": 55,
					"label": "PRÜFUNG",
					"anim": &"pulse",
					"color": Color("b99bff"),
					"data": {"puzzle_id": pid_z, "trial_kind": _dict_str(spec_p, "kind", ""), "solved": false},
				})
		return out

	if chests != null:
		var table: Dictionary = DataRegistry.table("loot_chests")
		var placed: Variant = table.get("placed", [])
		if placed is Array:
			for raw: Variant in placed as Array:
				if not (raw is Dictionary):
					continue
				var spec: Dictionary = raw as Dictionary
				var cid: String = _dict_str(spec, "id", "")
				if cid.is_empty() or chests.is_open(cid):
					continue
				var node: LootChest = chests.chest(cid)
				var pos: Vector2 = Vector2.INF
				if node != null and is_instance_valid(node):
					pos = Atlas.tile_of(node.global_position)
				elif spec.get("tile") is Array and (spec.get("tile") as Array).size() >= 2:
					var ta: Array = spec.get("tile") as Array
					pos = Vector2(_to_float(ta[0], INF), _to_float(ta[1], INF))
				if not pos.is_finite() or not _is_tile_seen(context, pos):
					continue
				var tier_name: String = _dict_str(spec, "tier", "common")
				out.append({
					"id": StringName("chest_%s" % cid),
					"kind": &"chest",
					"category": CAT_CHESTS_PUZZLES,
					"pos": pos,
					"zone": StringName(_dict_str(spec, "zone", "")),
					"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
					"priority": 45,
					"label": "TRUHE",
					"anim": &"",
					"color": Color("ffd98a") if tier_name != "common" else Color("e6c468"),
					"data": {"chest_id": cid, "tier": tier_name},
				})

	if puzzles != null:
		for pid_var: Variant in puzzles.ids():
			var pid: String = str(pid_var) if pid_var != null else ""
			if pid.is_empty() or puzzles.is_solved(pid):
				continue
			var spot_px: Vector2 = puzzles.trial_spot(pid)
			if not spot_px.is_finite():
				continue
			var pos: Vector2 = Atlas.tile_of(spot_px)
			if not _is_tile_seen(context, pos):
				continue
			var trial_node: WorldTrial = puzzles.trial(pid)
			var trial_kind: String = ""
			if trial_node != null:
				var direct_kind: Variant = trial_node.get("kind")
				if direct_kind is String or direct_kind is StringName:
					trial_kind = str(direct_kind)
				else:
					var info_var: Variant = trial_node.get("info")
					if info_var is Dictionary:
						trial_kind = _dict_str(info_var as Dictionary, "kind", "")
			out.append({
				"id": StringName("puzzle_%s" % pid),
				"kind": &"puzzle",
				"category": CAT_CHESTS_PUZZLES,
				"pos": pos,
				"zone": &"",
				"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
				"priority": 55,
				"label": "PRÜFUNG",
				"anim": &"pulse",
				"color": Color("b99bff"),
				"data": {"puzzle_id": pid, "trial_kind": trial_kind, "solved": false},
			})
	return out


func _provide_vistas(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree: SceneTree = _context_tree(context)
	var manager: Vistas = Vistas.of(tree) if tree != null else null
	if manager == null:
		return out
	for spec: Dictionary in manager.entries():
		if not bool(spec.get("seen", false)):
			continue
		var vid: String = _dict_str(spec, "id", "")
		var tile_arr: Variant = spec.get("tile")
		if vid.is_empty() or not (tile_arr is Array) or (tile_arr as Array).size() < 2:
			continue
		var pair: Array = tile_arr as Array
		var pos: Vector2 = Vector2(_to_float(pair[0], INF), _to_float(pair[1], INF))
		if not pos.is_finite():
			continue
		out.append({
			"id": StringName("vista_%s" % vid),
			"kind": &"vista",
			"category": CAT_NATURE,
			"pos": pos,
			"zone": StringName(_dict_str(spec, "zone", "")),
			"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
			"priority": 60,
			"label": _dict_str(spec, "name", "AUSSICHT"),
			"anim": &"",
			"color": Color("e6c468"),
			"data": {"vista_id": vid, "sub": _dict_str(spec, "sub", "")},
		})
	return out


func _provide_pets(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree: SceneTree = _context_tree(context)
	var registry: PetRegistry = PetRegistry.of(tree) if tree != null else null
	if registry == null:
		return out
	for rec: Dictionary in registry.records():
		var key: String = _dict_str(rec, "key", "")
		if key.is_empty():
			continue
		var seen: Vector3 = registry.seen_of(key)
		var pos: Vector2 = Vector2(seen.x, seen.y) / Atlas.TILE_PX
		var home_arr: Variant = rec.get("home")
		var home_tile: Vector2 = pos
		if home_arr is Array and (home_arr as Array).size() >= 2:
			var ha: Array = home_arr as Array
			var hx: float = _to_float(ha[0], INF)
			var hy: float = _to_float(ha[1], INF)
			if is_finite(hx) and is_finite(hy):
				home_tile = Vector2(hx, hy) / Atlas.TILE_PX
		out.append({
			"id": StringName("pet_%s" % key),
			"kind": &"pet",
			"category": CAT_NATURE,
			"pos": pos,
			"zone": &"",
			"levels": LEVEL_ORT | LEVEL_ZONE,
			"priority": 50,
			"label": _dict_str(rec, "n", "KRÄHE"),
			"anim": &"",
			"color": Color("c8b8ed"),
			"data": {"key": key, "species": _dict_str(rec, "sp", "crow"), "home_tile": home_tile, "sd": _to_int(rec.get("sd", 0), 0)},
		})
	return out


func _provide_landmarks(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var atlas_v: Variant = context.get("atlas")
	var atlas: Atlas = atlas_v as Atlas if atlas_v is Atlas else null
	if atlas == null:
		return out
	var cont_id: StringName = _context_continent_id(context)
	for z: Atlas.Zone in atlas.zones_of(cont_id):
		for lm: Atlas.Landmark in z.landmarks:
			if lm.kind == &"waystone":
				continue
			if not _is_tile_seen(context, lm.pos):
				continue
			out.append({
				"id": StringName("landmark_%s_%s" % [String(z.id), String(lm.id)]),
				"kind": &"landmark",
				"category": CAT_NATURE,
				"pos": lm.pos,
				"zone": z.id,
				"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
				"priority": 48,
				"label": lm.name,
				"anim": &"",
				"color": Color("d8c4a0"),
				"data": {"landmark_id": lm.id, "landmark_kind": lm.kind},
			})
	return out


func _provide_actors_town(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree: SceneTree = _context_tree(context)
	if tree == null:
		return out

	var town: TownManager = tree.get_first_node_in_group("town") as TownManager
	if town != null and town.founded:
		out.append({
			"id": &"town_heart",
			"kind": &"town",
			"category": CAT_NATURE,
			"pos": Atlas.tile_of(town.heart()),
			"zone": &"",
			"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
			"priority": 80,
			"label": town.town_name(),
			"anim": &"",
			"color": Color("78f4e6"),
			"data": {},
		})

	var styles: Dictionary = DataRegistry.table("map_markers")
	var lp: Player = _local_player(context)
	var quests: QuestComponent = (lp.get("quests") as QuestComponent) if lp != null else null
	for actor: Node in tree.get_nodes_in_group("quest_actors"):
		if not actor.has_method("map_marker"):
			continue
		var raw_m: Variant = actor.call("map_marker")
		if not (raw_m is Dictionary) or (raw_m as Dictionary).is_empty():
			continue
		var marker: Dictionary = raw_m as Dictionary
		var mid: String = _dict_str(marker, "id", "")
		var style_raw: Variant = styles.get(mid, styles.get("resident", {}))
		var style: Dictionary = style_raw as Dictionary if style_raw is Dictionary else {}
		var requires: String = _dict_str(style, "requires", "")
		if not requires.is_empty() and (quests == null or not quests.has_flag(requires)):
			continue
		var world_val: Variant = marker.get("position")
		if not (world_val is Vector2):
			continue
		var world_px: Vector2 = world_val as Vector2
		var outer_px: Vector2 = _outer_px(tree, world_px)
		var tile: Vector2 = Atlas.tile_of(outer_px)
		if not tile.is_finite() or PocketSpace.is_pocket(outer_px) or not _is_tile_seen(context, tile):
			continue
		var kind_str: String = _dict_str(style, "kind", "npc")
		if kind_str.is_empty():
			kind_str = "npc"
		var inside: bool = PocketSpace.is_pocket(world_px) or Interiors.slot_at(world_px) >= 0 or MineManager.in_mine(world_px) or DungeonManager.in_dungeon(world_px)
		var actor_label: String = _dict_str(style, "name", _dict_str(marker, "name", mid))
		var actor_title: String = _dict_str(style, "title", _dict_str(marker, "title", "BEWOHNER"))
		var actor_color: Color = Color.from_string(_dict_str(style, "color", "a6ceae"), Color("a6ceae"))
		out.append({
			"id": StringName("actor_%s" % mid),
			"kind": StringName(kind_str),
			"category": CAT_NATURE,
			"pos": tile,
			"zone": &"",
			"levels": LEVEL_ORT | LEVEL_ZONE,
			"priority": 70 if kind_str == "boss" else 52,
			"label": actor_label,
			"anim": &"pulse" if kind_str == "boss" else &"",
			"color": actor_color,
			"data": {
				"actor_id": mid,
				"title": actor_title,
				"extra": _dict_str(style, "extra", ""),
				"resting": _to_bool(marker.get("resting", false), false),
				"inside": inside,
				"style": style,
			},
		})
	return out


func _provide_dungeons(context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var atlas: Atlas = Atlas.shared()
	var tree: SceneTree = _context_tree(context)
	var lp: Player = SaveGame._local_player(tree) if tree != null else null
	for ddef: Dictionary in DungeonRules.all():
		if not bool(ddef.get("playable", false)):
			continue
		var did: String = String(ddef.get("id", ""))
		var z_id: StringName = StringName(String(ddef.get("zone", "")))
		var tile_arr: Variant = ddef.get("entrance_tile")
		if did.is_empty() or z_id == &"" or not (tile_arr is Array) or (tile_arr as Array).size() < 2:
			continue
		var z: Atlas.Zone = atlas.zone(z_id)
		if z == null:
			continue
		var pair: Array = tile_arr as Array
		var pos: Vector2 = Vector2(z.origin) + Vector2(_to_float(pair[0], 0.0), _to_float(pair[1], 0.0))
		var disc: bool = lp != null and lp.dungeons != null and lp.dungeons.is_discovered(did)
		if not disc and not _is_tile_seen(context, pos):
			continue
		var arch: Dictionary = DungeonRules.archetype_info(String(ddef.get("archetype", "expedition")))
		var col: Color = Color.from_string(String(ddef.get("accent", "4df2e0")), Color("4df2e0"))
		var min_lv: int = int(ddef.get("min_level", 1))
		out.append({
			"id": StringName("dungeon_%s" % did),
			"kind": &"landmark",
			"category": CAT_WAYSTONES,
			"pos": pos,
			"zone": z_id,
			"levels": LEVEL_ORT | LEVEL_ZONE | LEVEL_KONTINENT,
			"priority": 78,
			"label": "%s (ST. %d)" % [String(ddef.get("name", did)), min_lv],
			"anim": &"pulse",
			"color": col,
			"data": {
				"dungeon_id": did,
				"archetype": String(arch.get("name", "")),
				"min_level": min_lv,
				"discovered": disc,
			},
		})
	return out
