class_name AtlasBook
extends Control
## Integrated Chronicle & Exploration Book inside the v2 Atlas (`M` -> click completion flower or press `B` / `C`).
## Renders a two-page bark-paper codex in Shadowspore vine style with `assets/ui/atlas_elements.png` badges,
## live zone progress (explored %, 6 named places, waystones, vistas, chests/puzzles, flora/fauna, x/8 Veil Threads
## with poetic hints for open threads), and claimable 30% / 60% / 100% milestone rewards persisted in `SaveGame`.

signal closed
signal place_selected(world_tile: Vector2)
signal reward_claimed(zone_id: StringName, tier: int, reward_id: StringName)
signal state_changed

const SHEET_TEX: Texture2D = preload("res://assets/ui/atlas_elements.png")
const CHIME_CLAIM: AudioStream = preload("res://assets/audio/waystone/chime_c.wav")

const OPEN_SEC: float = 0.24
const CLOSE_SEC: float = 0.18

const REG_STAMP_WAX: Rect2 = Rect2(4, 4, 32, 32)
const REG_STAMP_MINI: Rect2 = Rect2(76, 4, 16, 16)
const REG_FLOWER_0: Rect2 = Rect2(168, 4, 16, 16)
const REG_FLOWER_1: Rect2 = Rect2(188, 4, 16, 16)
const REG_FLOWER_2: Rect2 = Rect2(208, 4, 16, 16)
const REG_FLOWER_3: Rect2 = Rect2(228, 4, 16, 16)
const REG_VINE_NW: Rect2 = Rect2(4, 44, 24, 24)
const REG_VINE_DIVIDER: Rect2 = Rect2(168, 44, 32, 12)
const REG_ENGRAVE_NW: Rect2 = Rect2(4, 80, 16, 16)
const REG_ENGRAVE_NE: Rect2 = Rect2(24, 80, 16, 16)
const REG_ENGRAVE_SW: Rect2 = Rect2(44, 80, 16, 16)
const REG_ENGRAVE_SE: Rect2 = Rect2(64, 80, 16, 16)
const REG_ENGRAVE_DIVIDER: Rect2 = Rect2(132, 80, 48, 12)
const REG_SEAL_LOCKED: Rect2 = Rect2(184, 80, 16, 16)
const REG_SEAL_UNLOCKED: Rect2 = Rect2(204, 80, 16, 16)
const REG_VEIL_ICON: Rect2 = Rect2(224, 80, 12, 12)
const REG_BADGE_WAYSTONE: Rect2 = Rect2(4, 116, 12, 12)
const REG_BADGE_VISTA: Rect2 = Rect2(20, 116, 12, 12)
const REG_BADGE_CHEST: Rect2 = Rect2(36, 116, 12, 12)
const REG_BADGE_PUZZLE: Rect2 = Rect2(52, 116, 12, 12)
const REG_BADGE_FLORA: Rect2 = Rect2(68, 116, 12, 12)
const REG_TITLE_RIBBON: Rect2 = Rect2(100, 116, 64, 16)

const REWARD_STAMP_ID: StringName = &"coast_wave"
const REWARD_FRAME_ID: StringName = &"silvercoast"
const REWARD_TITLE_ID: String = "kind_der_bucht"

static func _zone_rewards(zone_id: StringName) -> Dictionary:
	if zone_id == &"suedkap":
		return {
			"stamp": &"harbor_anchor",
			"frame": &"stormharbor",
			"title_id": "sturm_laeufer",
			"t30": "30% · ANKER-STEMPEL",
			"d30": "NADEL: STURMHAFEN-ANKER",
			"t60": "60% · MOLEN-RAHMEN",
			"d60": "STURMHAFEN-KARTENRAHMEN",
			"t100": "100% · STURMLÄUFER",
			"d100": "SPIELERTITEL ANLEGEN",
		}
	return {
		"stamp": REWARD_STAMP_ID,
		"frame": REWARD_FRAME_ID,
		"title_id": REWARD_TITLE_ID,
		"t30": "30% · KÜSTEN-STEMPEL",
		"d30": "5. NADEL: WINDKAP-WELLE",
		"t60": "60% · SILBERKÜSTEN-RANKE",
		"d60": "EDLER KARTENRAHMEN",
		"t100": "100% · KIND DER BUCHT",
		"d100": "SPIELERTITEL ANLEGEN",
	}

var _atlas: Atlas = null
var _discovery: MapDiscovery = null
var _director: Node = null
var _player: Player = null
var _zone_id: StringName = &"windkap"
var _preview_reveal_all: bool = false

var _opening: bool = false
var _open_t: float = 0.0
var _time: float = 0.0
var _cursor: Vector2 = Vector2(-100.0, -100.0)
var _flash_tier: int = 0
var _flash_t: float = 0.0

## Persistent reward state (exported/imported via SaveGame)
var _claimed_by_zone: Dictionary = {} ## String zone_id -> Array[int] (e.g. [30, 60, 100])
var _unlocked_stamps: Array[String] = []
var _unlocked_frames: Array[String] = []
var _frame_enabled: bool = true

var _book_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _place_rects: Array[Dictionary] = [] ## [{rect, pos, seen}]
var _reward_rects: Array[Dictionary] = [] ## [{rect, tier, can_claim, claimed}]
var _zone_btn_rects: Array[Dictionary] = [] ## [{rect, zone_id}]
var embedded_in_menu: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(atlas: Atlas, discovery: MapDiscovery, director: Node = null, player: Player = null) -> void:
	_atlas = atlas if atlas != null else Atlas.shared()
	_discovery = discovery
	_director = director
	_player = player


func bind_player(player: Player) -> void:
	_player = player


func set_zone(zone_id: StringName) -> void:
	if zone_id != &"":
		_zone_id = zone_id
		queue_redraw()


func set_preview_reveal_all(reveal_all: bool) -> void:
	_preview_reveal_all = reveal_all
	queue_redraw()


func is_open() -> bool:
	return _opening


func open_book(zone_id: StringName = &"") -> void:
	if zone_id != &"":
		_zone_id = zone_id
	if _opening:
		return
	_opening = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Sfx.ui(self, "map_open", -4.0)
	queue_redraw()


func close_book(instant: bool = false) -> void:
	if not _opening and not visible:
		return
	if _opening:
		Sfx.ui(self, "map_close", -4.0)
	_opening = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if instant:
		_open_t = 0.0
		visible = false
	closed.emit()


func toggle_book(zone_id: StringName = &"") -> void:
	if _opening:
		close_book(false)
	else:
		open_book(zone_id)


# --- Reward Queries for AtlasView / MapMarkers -----------------------------------------------------------------------

func has_stamp_unlocked(stamp_id: StringName = REWARD_STAMP_ID) -> bool:
	return _unlocked_stamps.has(String(stamp_id))


func has_frame_unlocked(frame_id: StringName = REWARD_FRAME_ID) -> bool:
	return _unlocked_frames.has(String(frame_id))


func is_silvercoast_frame_active() -> bool:
	return _frame_enabled and has_frame_unlocked(REWARD_FRAME_ID)


func is_tier_claimed(zone_id: StringName, tier: int) -> bool:
	var arr: Array = _claimed_by_zone.get(String(zone_id), []) as Array
	for v: Variant in arr:
		if int(v) == tier:
			return true
	return false


func has_unclaimed_milestone(zone_id: StringName) -> bool:
	var stats: Dictionary = compute_zone_progress(zone_id)
	var pct: int = int(stats.get("completion_pct", 0))
	for tier: int in [30, 60, 100]:
		if pct >= tier and not is_tier_claimed(zone_id, tier):
			return true
	return false


static func flower_region_for_ratio(ratio: float) -> Rect2:
	if ratio >= 0.995:
		return REG_FLOWER_3
	if ratio >= 0.60:
		return REG_FLOWER_2
	if ratio >= 0.30:
		return REG_FLOWER_1
	return REG_FLOWER_0


# --- Genuine Zone Progress Computation -------------------------------------------------------------------------------

func compute_zone_progress(zone_id: StringName) -> Dictionary:
	var zid: StringName = zone_id if zone_id != &"" else _zone_id
	var z: Atlas.Zone = _atlas.zone(zid) if _atlas != null else null
	if z == null:
		return {
			"zone_id": zid,
			"name": String(zid).to_upper(),
			"subtitle": "",
			"explored_ratio": 0.0,
			"explored_pct": 0,
			"places": [],
			"places_seen": 0,
			"places_total": 0,
			"waystones_done": 0,
			"waystones_total": 0,
			"vistas_done": 0,
			"vistas_total": 0,
			"chests_done": 0,
			"chests_total": 0,
			"puzzles_done": 0,
			"puzzles_total": 0,
			"flora_done": 0,
			"flora_total": 0,
			"threads": [],
			"threads_done": 0,
			"threads_total": 0,
			"completion_ratio": 0.0,
			"completion_pct": 0,
		}

	var all_rev: bool = _preview_reveal_all or (_discovery != null and _discovery.is_reveal_all())
	var tree: SceneTree = get_tree() if is_inside_tree() else null

	# 1. Explored land area %
	var explored_ratio: float = 1.0 if all_rev else (_discovery.zone_explored_ratio(zid) if _discovery != null else 0.0)
	var explored_pct: int = roundi(explored_ratio * 100.0)

	# 2. Named Places (e.g. 6 in Windkap)
	var places_out: Array[Dictionary] = []
	var places_seen: int = 0
	for pl: Atlas.Place in z.places:
		var center_t: Vector2 = pl.bbox.get_center()
		var seen_pl: bool = all_rev
		if not seen_pl and _director != null and _director.has_method(&"seen_place"):
			seen_pl = bool(_director.call(&"seen_place", pl.id))
		if not seen_pl and _discovery != null:
			seen_pl = _discovery.is_seen(center_t)
		if seen_pl:
			places_seen += 1
		places_out.append({
			"id": pl.id,
			"name": pl.name,
			"pos": center_t,
			"seen": seen_pl,
		})

	# 3. Waystones
	var ws_sys: Waystones = Waystones.of(tree) if tree != null else null
	var ws_raw: Array = z.raw.get("waystones", []) as Array if z.raw.get("waystones") is Array else []
	var ws_total: int = ws_raw.size()
	var ws_done: int = 0
	if ws_total > 0:
		for w_v: Variant in ws_raw:
			if w_v is Dictionary:
				var wid: String = String((w_v as Dictionary).get("id", ""))
				if all_rev or (ws_sys != null and ws_sys.is_awake(wid)):
					ws_done += 1
	else:
		for lm: Atlas.Landmark in z.landmarks:
			if lm.kind == &"waystone":
				ws_total += 1
				if all_rev or (ws_sys != null and ws_sys.is_awake(String(lm.id))):
					ws_done += 1

	# 4. Vistas
	var vista_sys: Vistas = Vistas.of(tree) if tree != null else null
	var v_raw: Array = z.raw.get("vistas", []) as Array if z.raw.get("vistas") is Array else []
	var vistas_total: int = v_raw.size()
	var vistas_done: int = 0
	for vv: Variant in v_raw:
		if vv is Dictionary:
			var vid: String = String((vv as Dictionary).get("id", ""))
			if all_rev or (vista_sys != null and vista_sys.is_discovered(vid)):
				vistas_done += 1

	# 5. Chests & Puzzles
	var chest_sys: LootChests = LootChests.of(tree) if tree != null else null
	var c_raw: Array = z.raw.get("chests", []) as Array if z.raw.get("chests") is Array else []
	var chests_total: int = c_raw.size()
	var chests_done: int = 0
	for cv: Variant in c_raw:
		if cv is Dictionary:
			var cid: String = String((cv as Dictionary).get("id", ""))
			if all_rev or (chest_sys != null and chest_sys.is_open(cid)):
				chests_done += 1

	var puz_sys: Puzzles = Puzzles.of(tree) if tree != null else null
	var p_raw: Array = z.raw.get("puzzles", []) as Array if z.raw.get("puzzles") is Array else []
	var puzzles_total: int = p_raw.size()
	var puzzles_done: int = 0
	for pv: Variant in p_raw:
		if pv is Dictionary:
			var pid: String = String((pv as Dictionary).get("id", ""))
			if all_rev or (puz_sys != null and puz_sys.is_solved(pid)):
				puzzles_done += 1

	# 6. Flora & Fauna entries
	var flora_dict: Dictionary = z.raw.get("flora", {}) as Dictionary if z.raw.get("flora") is Dictionary else {}
	var flora_spots: Dictionary = {} ## species_id -> world_tile
	for bv: Variant in flora_dict.get("bushes", []) as Array if flora_dict.get("bushes") is Array else []:
		if bv is Dictionary:
			var bd: Dictionary = bv as Dictionary
			var bkind: String = String(bd.get("kind", ""))
			var btile: Variant = bd.get("tile")
			if not bkind.is_empty() and btile is Array and (btile as Array).size() >= 2 and not flora_spots.has(bkind):
				var ba: Array = btile as Array
				flora_spots[bkind] = Vector2(z.origin) + Vector2(float(ba[0]), float(ba[1]))
	for pat_v: Variant in flora_dict.get("patches", []) as Array if flora_dict.get("patches") is Array else []:
		if pat_v is Dictionary:
			var pd: Dictionary = pat_v as Dictionary
			var pkind: String = String(pd.get("kind", ""))
			var pcenter: Variant = pd.get("center")
			if not pkind.is_empty() and pcenter is Array and (pcenter as Array).size() >= 2 and not flora_spots.has(pkind):
				var pa: Array = pcenter as Array
				flora_spots[pkind] = Vector2(z.origin) + Vector2(float(pa[0]), float(pa[1]))

	var wild_dict: Dictionary = z.raw.get("wildlife", {}) as Dictionary if z.raw.get("wildlife") is Dictionary else {}
	var crow_sites: Array = wild_dict.get("crow_sites", []) as Array if wild_dict.get("crow_sites") is Array else []
	var fauna_spots: Array[Vector2] = []
	for cs_v: Variant in crow_sites:
		if cs_v is Array and (cs_v as Array).size() >= 2:
			var csa: Array = cs_v as Array
			fauna_spots.append(Vector2(z.origin) + Vector2(float(csa[0]), float(csa[1])))

	var flora_total: int = flora_spots.size() + fauna_spots.size()
	var flora_done: int = 0
	var lp: Player = _resolve_local_player(tree)
	var inv: InventoryComponent = lp.inventory if lp != null else null
	for fkey: Variant in flora_spots.keys():
		var fk: String = String(fkey)
		var ftile: Vector2 = flora_spots[fkey] as Vector2
		var known: bool = all_rev
		if not known and inv != null and inv.count_item(fk) > 0:
			known = true
		if not known and _discovery != null and _discovery.is_seen(ftile):
			known = true
		if known:
			flora_done += 1
	for f_tile: Vector2 in fauna_spots:
		if all_rev or (_discovery != null and _discovery.is_seen(f_tile)):
			flora_done += 1

	# 7. Veil Threads (x / 8 in Windkap + poetic hints)
	var vt_sys: VeilThreads = VeilThreads.of(tree) if tree != null else null
	var place_names: Dictionary = {}
	for pl2: Atlas.Place in z.places:
		place_names[pl2.id] = pl2.name
	var threads_out: Array[Dictionary] = []
	var threads_done: int = 0
	if vt_sys != null and vt_sys.total_in_zone(zid) > 0:
		for t_spec: Dictionary in vt_sys.entries_for_zone(zid):
			var col_flag: bool = all_rev or bool(t_spec.get("collected", false))
			if col_flag:
				threads_done += 1
			var pl_id: StringName = t_spec.get("place", &"") as StringName
			threads_out.append({
				"id": String(t_spec.get("id", "")),
				"collected": col_flag,
				"place_name": String(place_names.get(pl_id, String(pl_id).to_upper())),
				"hint": String(t_spec.get("hint", "Ein verborgener Faden des Schleiers")),
			})
	else:
		var raw_vt: Array = z.raw.get("veil_threads", []) as Array if z.raw.get("veil_threads") is Array else []
		for rv: Variant in raw_vt:
			if rv is Dictionary:
				var rd: Dictionary = rv as Dictionary
				var pl_id2: StringName = StringName(String(rd.get("place", "")))
				if all_rev:
					threads_done += 1
				threads_out.append({
					"id": String(rd.get("id", "")),
					"collected": all_rev,
					"place_name": String(place_names.get(pl_id2, String(pl_id2).to_upper())),
					"hint": String(rd.get("hint", "Ein verborgener Faden des Schleiers")),
				})

	var threads_total: int = threads_out.size()

	# Weighted overall completion ratio (normalizes cleanly if a zone omits optional categories)
	var w_sum: float = 0.35
	var c_sum: float = explored_ratio * 0.35
	if not places_out.is_empty():
		w_sum += 0.15
		c_sum += (float(places_seen) / float(places_out.size())) * 0.15
	if ws_total + vistas_total > 0:
		w_sum += 0.15
		c_sum += (float(ws_done + vistas_done) / float(ws_total + vistas_total)) * 0.15
	if chests_total + puzzles_total > 0:
		w_sum += 0.15
		c_sum += (float(chests_done + puzzles_done) / float(chests_total + puzzles_total)) * 0.15
	if threads_total > 0:
		w_sum += 0.20
		c_sum += (float(threads_done) / float(threads_total)) * 0.20

	var completion_ratio: float = clampf(c_sum / maxf(w_sum, 0.01), 0.0, 1.0)
	var completion_pct: int = roundi(completion_ratio * 100.0)

	return {
		"zone_id": zid,
		"name": z.name.to_upper(),
		"subtitle": z.subtitle,
		"explored_ratio": explored_ratio,
		"explored_pct": explored_pct,
		"places": places_out,
		"places_seen": places_seen,
		"places_total": places_out.size(),
		"waystones_done": ws_done,
		"waystones_total": ws_total,
		"vistas_done": vistas_done,
		"vistas_total": vistas_total,
		"chests_done": chests_done,
		"chests_total": chests_total,
		"puzzles_done": puzzles_done,
		"puzzles_total": puzzles_total,
		"flora_done": flora_done,
		"flora_total": flora_total,
		"threads": threads_out,
		"threads_done": threads_done,
		"threads_total": threads_total,
		"completion_ratio": completion_ratio,
		"completion_pct": completion_pct,
	}


func _resolve_local_player(tree: SceneTree) -> Player:
	if _player != null and is_instance_valid(_player):
		return _player
	if tree != null:
		return SaveGame._local_player(tree)
	return null


# --- Claiming & Toggling 30% / 60% / 100% Milestone Rewards ----------------------------------------------------------

func claim_or_activate_tier(zone_id: StringName, tier: int) -> bool:
	var stats: Dictionary = compute_zone_progress(zone_id)
	var pct: int = int(stats.get("completion_pct", 0))
	var claimed: bool = is_tier_claimed(zone_id, tier)
	if not claimed and pct < tier:
		return false

	var tree: SceneTree = get_tree() if is_inside_tree() else null
	var lp: Player = _resolve_local_player(tree)
	var app: AppearanceComponent = lp.appearance if lp != null else null

	var rew: Dictionary = _zone_rewards(zone_id)
	var r_stamp: StringName = rew["stamp"] as StringName
	var r_frame: StringName = rew["frame"] as StringName
	var r_title: String = String(rew["title_id"])

	if not claimed:
		var zkey: String = String(zone_id)
		var arr: Array = (_claimed_by_zone.get(zkey, []) as Array).duplicate()
		arr.append(tier)
		_claimed_by_zone[zkey] = arr
		_flash_tier = tier
		_flash_t = 1.0
		if CHIME_CLAIM != null:
			Sfx.ui_stream(self, CHIME_CLAIM, -2.0, 0.04)
		match tier:
			30:
				if not _unlocked_stamps.has(String(r_stamp)):
					_unlocked_stamps.append(String(r_stamp))
				reward_claimed.emit(zone_id, 30, r_stamp)
			60:
				if not _unlocked_frames.has(String(r_frame)):
					_unlocked_frames.append(String(r_frame))
				_frame_enabled = true
				reward_claimed.emit(zone_id, 60, r_frame)
			100:
				if app != null:
					app.unlock_title(r_title)
					app.request_title(r_title)
				reward_claimed.emit(zone_id, 100, StringName(r_title))
		CloudSession.mark_save_dirty()
		state_changed.emit()
		queue_redraw()
		return true

	# Already claimed -> interactive toggle / select!
	Sfx.ui(self, "ui_click", -3.0)
	match tier:
		30:
			reward_claimed.emit(zone_id, 30, r_stamp)
		60:
			_frame_enabled = not _frame_enabled
		100:
			if app != null:
				if not app.is_title_unlocked(r_title):
					app.unlock_title(r_title)
				var next_t: String = "" if app.title_id == r_title else r_title
				app.request_title(next_t)
	CloudSession.mark_save_dirty()
	state_changed.emit()
	queue_redraw()
	return true


# --- Save / Load State -----------------------------------------------------------------------------------------------

func export_state() -> Dictionary:
	return {
		"version": 1,
		"claimed": _claimed_by_zone.duplicate(true),
		"stamps": _unlocked_stamps.duplicate(),
		"frames": _unlocked_frames.duplicate(),
		"frame_enabled": _frame_enabled,
	}


func import_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	_claimed_by_zone.clear()
	var raw_claimed: Dictionary = SaveGame.as_dict(data.get("claimed"))
	for k: Variant in raw_claimed:
		var clean_tiers: Array[int] = []
		for tv: Variant in SaveGame.as_array(raw_claimed[k]):
			var ti: int = int(tv)
			if ti in [30, 60, 100] and not clean_tiers.has(ti):
				clean_tiers.append(ti)
		if not clean_tiers.is_empty():
			_claimed_by_zone[String(k)] = clean_tiers

	_unlocked_stamps.clear()
	for sv: Variant in SaveGame.as_array(data.get("stamps")):
		var s_id: String = String(sv).strip_edges()
		if not s_id.is_empty() and not _unlocked_stamps.has(s_id):
			_unlocked_stamps.append(s_id)

	_unlocked_frames.clear()
	for fv: Variant in SaveGame.as_array(data.get("frames")):
		var f_id: String = String(fv).strip_edges()
		if not f_id.is_empty() and not _unlocked_frames.has(f_id):
			_unlocked_frames.append(f_id)

	_frame_enabled = bool(data.get("frame_enabled", true))

	# Reconcile unlocked rewards from claimed tiers so nothing can desync
	for z_tiers_v: Variant in _claimed_by_zone.values():
		for tv2: Variant in z_tiers_v as Array:
			var t_val: int = int(tv2)
			if t_val == 30 and not _unlocked_stamps.has(String(REWARD_STAMP_ID)):
				_unlocked_stamps.append(String(REWARD_STAMP_ID))
			elif t_val == 60 and not _unlocked_frames.has(String(REWARD_FRAME_ID)):
				_unlocked_frames.append(String(REWARD_FRAME_ID))
			elif t_val == 100:
				var tree: SceneTree = get_tree() if is_inside_tree() else null
				var lp: Player = _resolve_local_player(tree)
				if lp != null and lp.appearance != null and not lp.appearance.is_title_unlocked(REWARD_TITLE_ID):
					lp.appearance.unlock_title(REWARD_TITLE_ID)
	state_changed.emit()
	queue_redraw()


# --- Frame Update & Input --------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible and not _opening:
		return
	_time += delta
	_flash_t = maxf(_flash_t - delta * 1.8, 0.0)
	_open_t = move_toward(_open_t, 1.0 if _opening else 0.0, delta / (OPEN_SEC if _opening else CLOSE_SEC))
	visible = _open_t > 0.001
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not _opening:
		return
	if event is InputEventMouseMotion:
		_cursor = (event as InputEventMouseMotion).position
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		_cursor = mb.position
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not embedded_in_menu and (_close_rect.grow(3.0).has_point(mb.position) or not _book_rect.grow(4.0).has_point(mb.position)):
				close_book(false)
				accept_event()
				return
			for zr: Dictionary in _zone_btn_rects:
				if (zr["rect"] as Rect2).grow(1.0).has_point(mb.position):
					var nz: StringName = zr["zone_id"] as StringName
					if nz != _zone_id:
						_zone_id = nz
						Sfx.ui(self, "ui_click", -5.0)
						queue_redraw()
					accept_event()
					return
			for pr: Dictionary in _place_rects:
				if (pr["rect"] as Rect2).grow(2.0).has_point(mb.position):
					if bool(pr["seen"]):
						var target_t: Vector2 = pr["pos"] as Vector2
						if not embedded_in_menu:
							close_book(false)
						place_selected.emit(target_t)
					accept_event()
					return
			for rr: Dictionary in _reward_rects:
				if (rr["rect"] as Rect2).grow(2.0).has_point(mb.position):
					claim_or_activate_tier(_zone_id, int(rr["tier"]))
					accept_event()
					return
		accept_event()


# --- Bark-Paper Codex Rendering (`640 x 360`) ------------------------------------------------------------------------

func _view_size() -> Vector2:
	return size if size.x > 16.0 and size.y > 16.0 else Vector2(640.0, 360.0)


func _fit_text(raw: String, max_px: int) -> String:
	var clean: String = raw.strip_edges().to_upper()
	if PixelText.width(clean) <= max_px:
		return clean
	var max_chars: int = maxi((max_px - 8) / PixelText.ADVANCE, 4)
	return clean.left(max_chars).strip_edges() + ".."


func _draw_text(txt: String, pos: Vector2i, col: Color, fade: float) -> void:
	PixelText.draw(self, txt, pos, Color(col, col.a * fade), Color(VineStyle.OUTLINE, 0.92 * fade))


func _draw_text_centered(txt: String, center: Vector2, col: Color, fade: float) -> void:
	_draw_text(txt, Vector2i(roundi(center.x) - PixelText.width(txt) / 2, roundi(center.y)), col, fade)


func _draw_check(at: Vector2, col: Color, fade: float) -> void:
	var p: Vector2 = at.round()
	for pt: Vector2 in [Vector2(0, 3), Vector2(1, 4), Vector2(2, 3), Vector2(3, 2), Vector2(4, 1), Vector2(5, 0)]:
		draw_rect(Rect2(p + pt + Vector2.ONE, Vector2.ONE), Color(VineStyle.OUTLINE, 0.9 * fade))
		draw_rect(Rect2(p + pt, Vector2.ONE), Color(col, fade))


func _chronicle_zones() -> Array[StringName]:
	var out: Array[StringName] = []
	var atlas_ref: Atlas = _atlas if _atlas != null else Atlas.shared()
	if atlas_ref == null:
		return [&"windkap"]
	for zid: StringName in [&"windkap", &"suedkap"]:
		if atlas_ref.zone(zid) != null:
			out.append(zid)
	if not out.has(_zone_id) and atlas_ref.zone(_zone_id) != null:
		out.insert(0, _zone_id)
	return out


func _draw() -> void:
	if _open_t <= 0.001:
		return
	var vs: Vector2 = _view_size()
	var ease_p: float = 1.0 - pow(1.0 - _open_t, 3.0)
	var fade: float = ease_p
	var void_level: float = VineStyle.void_amount()

	_place_rects.clear()
	_reward_rects.clear()
	_zone_btn_rects.clear()

	if not embedded_in_menu:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.01, 0.06, 0.72 * fade))

	if embedded_in_menu:
		# 3-Column Feldcodex Chronicle matching SCHATTENFRÜCHTE's exact visual grid:
		#   Left Sidebar (138px): ALTMARK world completion + clickable Zone list + Welt-Bilanz
		#   Center Panel (230px): Selected Zone Overview, Erschließung, Named Places & Discovery Badges
		#   Right Panel  (236px): Schattenfrüchte & 30/60/100% Milestone Rewards (strictly inside frame!)
		var pad: float = 12.0
		var gap: float = 6.0
		var bw: float = vs.x - pad * 2.0
		var bh: float = vs.y - 36.0
		var by: float = 28.0 + roundf((1.0 - VineStyle.back_out(_open_t)) * 10.0)
		_book_rect = Rect2(pad, by, bw, bh)
		_close_rect = Rect2()

		var side_w: float = 138.0
		var right_w: float = 236.0
		var mid_w: float = maxf(bw - side_w - right_w - gap * 2.0, 200.0)
		var side_r: Rect2 = Rect2(pad, by, side_w, bh)
		var mid_r: Rect2 = Rect2(side_r.end.x + gap, by, mid_w, bh)
		var right_r: Rect2 = Rect2(mid_r.end.x + gap, by, right_w, bh)

		MenuChrome.draw_slate(self, side_r, fade)
		MenuChrome.draw_slate(self, mid_r, fade)
		MenuChrome.draw_corners(self, mid_r, fade)
		MenuChrome.draw_parchment(self, right_r, fade)
		MenuChrome.draw_corners(self, right_r, fade)

		var stats: Dictionary = compute_zone_progress(_zone_id)
		_draw_embedded_sidebar(side_r, fade)
		_draw_left_page(mid_r, stats, fade, void_level)
		_draw_right_page(right_r, stats, fade, void_level)
		return

	var bw: float = 544.0
	var bh: float = 298.0
	var bx: float = roundf((vs.x - bw) * 0.5)
	var by: float = roundf((vs.y - bh) * 0.5) + roundf((1.0 - VineStyle.back_out(_open_t)) * 12.0)
	_book_rect = Rect2(bx, by, bw, bh)

	draw_rect(Rect2(bx - 3.0, by - 3.0, bw + 6.0, bh + 6.0), Color(VineStyle.OUTLINE, 0.96 * fade))
	draw_rect(Rect2(bx - 2.0, by - 2.0, bw + 4.0, bh + 4.0), Color(VineStyle.BARK.darkened(0.32), 0.96 * fade))
	var left_page: Rect2 = Rect2(bx + 4.0, by + 4.0, bw * 0.5 - 7.0, bh - 8.0)
	var right_page: Rect2 = Rect2(bx + bw * 0.5 + 3.0, by + 4.0, bw * 0.5 - 7.0, bh - 8.0)
	VineStyle.paper(self, left_page, fade, void_level * 0.5, 41)
	VineStyle.paper(self, right_page, fade, void_level * 0.5, 83)
	var spine_x: float = bx + bw * 0.5
	draw_rect(Rect2(spine_x - 3.0, by + 2.0, 6.0, bh - 4.0), Color("0a0614", 0.95 * fade))
	draw_rect(Rect2(spine_x - 1.0, by + 6.0, 2.0, bh - 12.0), Color(VineStyle.BARK_LIGHT, 0.55 * fade))
	for sy: int in range(int(by) + 22, int(by + bh) - 18, 28):
		draw_rect(Rect2(spine_x - 4.0, float(sy), 8.0, 3.0), Color(VineStyle.WARM_GLOW.darkened(0.25), 0.78 * fade))
	if SHEET_TEX != null:
		var c_tint: Color = Color(1.0, 1.0, 1.0, 0.88 * fade)
		draw_texture_rect_region(SHEET_TEX, Rect2(left_page.position + Vector2(2, 2), Vector2(16, 16)), REG_ENGRAVE_NW, c_tint)
		draw_texture_rect_region(SHEET_TEX, Rect2(Vector2(right_page.end.x - 18, right_page.position.y + 2), Vector2(16, 16)), REG_ENGRAVE_NE, c_tint)
		draw_texture_rect_region(SHEET_TEX, Rect2(Vector2(left_page.position.x + 2, left_page.end.y - 18), Vector2(16, 16)), REG_ENGRAVE_SW, c_tint)
		draw_texture_rect_region(SHEET_TEX, Rect2(right_page.end - Vector2(18, 18), Vector2(16, 16)), REG_ENGRAVE_SE, c_tint)
	var top_course: Callable = func(x: float) -> float: return by - 1.0 + sin(x * 0.05) * 1.4
	VineStyle.branch(self, bx + 18.0, bx + 148.0, top_course, 3, void_level * 0.5, 25.0, _time, ease_p)
	VineStyle.foliage(self, bx + 18.0, bx + 148.0, top_course, 5, 211, void_level * 0.5, 25.0, _time, ease_p)
	_close_rect = Rect2(right_page.end.x - 20.0, right_page.position.y + 4.0, 15.0, 13.0)
	var close_hov: bool = _close_rect.has_point(_cursor)
	VineStyle.plate(self, _close_rect, "X", VineStyle.WARM_GLOW if close_hov else UiStyle.PANEL_DARK, VineStyle.PETAL if close_hov else UiStyle.TEXT_DIM, fade, void_level * 0.4)

	var stats_st: Dictionary = compute_zone_progress(_zone_id)
	_draw_left_page(left_page, stats_st, fade, void_level)
	_draw_right_page(right_page, stats_st, fade, void_level)
	_draw_text_centered("B / C / ESC: ATLASBUCH SCHLIESSEN   KLICK AUF ORT: AUF KARTE ZEIGEN", Vector2(vs.x * 0.5, by + bh + 8.0), Color(UiStyle.TEXT_DIM, 0.8), fade)


func _draw_embedded_sidebar(rect: Rect2, fade: float) -> void:
	var x: float = rect.position.x + 10.0
	var pw: float = rect.size.x - 20.0
	var y: float = rect.position.y + 10.0

	var zones: Array[StringName] = _chronicle_zones()
	var sum_ratio: float = 0.0
	var sum_places_d: int = 0
	var sum_places_t: int = 0
	var sum_ws_d: int = 0
	var sum_ws_t: int = 0
	var sum_fr_d: int = 0
	var sum_fr_t: int = 0
	var zone_stats_cache: Array[Dictionary] = []
	for zid: StringName in zones:
		var zs: Dictionary = compute_zone_progress(zid)
		zone_stats_cache.append(zs)
		sum_ratio += float(zs.get("completion_ratio", 0.0))
		sum_places_d += int(zs.get("places_seen", 0))
		sum_places_t += int(zs.get("places_total", 0))
		sum_ws_d += int(zs.get("waystones_done", 0))
		sum_ws_t += int(zs.get("waystones_total", 0))
		sum_fr_d += int(zs.get("threads_done", 0))
		sum_fr_t += int(zs.get("threads_total", 0))
	var world_ratio: float = sum_ratio / float(maxi(zones.size(), 1))
	var world_pct: int = roundi(world_ratio * 100.0)

	MenuChrome.draw_icon(self, "world", Vector2(x, y - 2.0), true, fade)
	MenuChrome.draw_text(self, "ALTMARK", Vector2(x + 15.0, y), MenuChrome.COL_GOLD, fade)
	var pct_s: String = "%d%%" % world_pct
	MenuChrome.draw_text(self, pct_s, Vector2(x + pw - float(PixelText.width(pct_s)), y), MenuChrome.COL_TEAL, fade)
	y += 13.0
	MenuChrome.draw_bar(self, Rect2(x, y, pw, 6.0), world_ratio, MenuChrome.COL_TEAL, fade)
	y += 14.0

	MenuChrome.draw_text(self, "ZONEN", Vector2(x, y), MenuChrome.COL_TEXT_DIM, fade)
	y += 11.0

	var max_rows: int = 6
	for i: int in mini(zones.size(), max_rows):
		var zid: StringName = zones[i]
		var zs: Dictionary = zone_stats_cache[i]
		var zr: Rect2 = Rect2(x - 2.0, y, pw + 4.0, 19.0)
		_zone_btn_rects.append({"rect": zr, "zone_id": zid})
		var sel: bool = (zid == _zone_id)
		var hov: bool = zr.has_point(_cursor)
		if sel:
			MenuChrome.draw_parchment(self, zr, fade)
		elif hov:
			MenuChrome.draw_inset(self, zr, fade)
		var zname: String = String(zs.get("name", String(zid).to_upper()))
		var zpct: int = int(zs.get("completion_pct", 0))
		var full: bool = zpct >= 100
		var has_unclaimed: bool = false
		for tier: int in [30, 60, 100]:
			if zpct >= tier and not is_tier_claimed(zid, tier):
				has_unclaimed = true
				break
		var lcol: Color = MenuChrome.COL_GOLD_HOT if full else (MenuChrome.COL_TEXT if sel else MenuChrome.COL_TEXT_SOFT)
		var pref: String = "> " if sel else "  "
		var cnt_s: String = "%d%%" % zpct
		MenuChrome.draw_text(self, _fit_text(pref + zname, int(pw) - PixelText.width(cnt_s) - 10), Vector2(x + 3.0, y + 6.0), lcol, fade)
		MenuChrome.draw_text(self, cnt_s, Vector2(x + pw - float(PixelText.width(cnt_s)) - 2.0, y + 6.0), MenuChrome.COL_GOLD_HOT if has_unclaimed else (MenuChrome.COL_TEAL if full else MenuChrome.COL_TEXT_DIM), fade)
		if has_unclaimed:
			MenuChrome.draw_badge(self, Vector2(zr.end.x - 5.0, zr.position.y - 3.0), _time, fade)
		y += 21.0

	# Bottom section: Welt-Bilanz summary (mirrors SCHATTENFRÜCHTE bottom block!)
	var bil_y: float = rect.end.y - 76.0
	MenuChrome.draw_divider(self, rect.get_center().x, bil_y - 6.0, pw, fade)
	bil_y += 5.0
	MenuChrome.draw_text(self, "WELT-BILANZ", Vector2(x, bil_y), MenuChrome.COL_GOLD, fade)
	bil_y += 13.0
	for row_s: Array in [
		["ORTE", "%d/%d" % [sum_places_d, sum_places_t], MenuChrome.COL_TEAL],
		["WEGSTEINE", "%d/%d" % [sum_ws_d, sum_ws_t], MenuChrome.COL_GOLD],
		["FRÜCHTE", "%d/%d" % [sum_fr_d, sum_fr_t], MenuChrome.COL_VIOLET],
	]:
		var lbl_b: String = String(row_s[0])
		var val_b: String = String(row_s[1])
		var col_b: Color = row_s[2] as Color
		draw_rect(Rect2(x + 1.0, bil_y + 2.0, 3.0, 3.0), Color(col_b.r, col_b.g, col_b.b, 0.9 * fade))
		MenuChrome.draw_text(self, lbl_b, Vector2(x + 8.0, bil_y), MenuChrome.COL_TEXT_SOFT, fade)
		MenuChrome.draw_text(self, val_b, Vector2(x + pw - float(PixelText.width(val_b)), bil_y), col_b, fade)
		bil_y += 14.0


func _draw_left_page(page: Rect2, stats: Dictionary, fade: float, void_level: float) -> void:
	var px: float = page.position.x + 11.0
	var pw: float = page.size.x - 22.0
	var cx: float = page.get_center().x
	var y: float = page.position.y + 10.0

	# Header: Zone Name (2x) + Subtitle + Divider
	var z_title: String = String(stats.get("name", "WINDKAP"))
	var scale_t: float = 2.0 if float(PixelText.width(z_title)) * 2.0 <= pw else 1.0
	draw_set_transform(Vector2(roundf(cx - float(PixelText.width(z_title)) * 0.5 * scale_t), roundf(y)), 0.0, Vector2(scale_t, scale_t))
	PixelText.draw(self, z_title, Vector2i.ZERO, Color(MenuChrome.COL_GOLD_HOT if embedded_in_menu else VineStyle.WARM_GLOW.lerp(VineStyle.PETAL, 0.28), fade), Color(VineStyle.OUTLINE, fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	y += (16.0 if scale_t > 1.5 else 11.0)

	var sub: String = _fit_text(String(stats.get("subtitle", "ZONEN-CHRONIK")), int(pw))
	if not sub.is_empty():
		_draw_text_centered(sub, Vector2(cx, y), UiStyle.TEXT_DIM, fade)
		y += 9.0

	if embedded_in_menu:
		MenuChrome.draw_divider(self, cx, y + 1.0, pw, fade)
		y += 10.0
	else:
		if SHEET_TEX != null:
			draw_texture_rect_region(SHEET_TEX, Rect2(roundf(cx - 24.0), roundf(y), 48.0, 12.0), REG_ENGRAVE_DIVIDER, Color(1, 1, 1, 0.88 * fade))
		y += 14.0

	# Overall Zone Completion Banner + Flower
	var comp_ratio: float = float(stats.get("completion_ratio", 0.0))
	var comp_pct: int = int(stats.get("completion_pct", 0))
	if SHEET_TEX != null:
		draw_texture_rect_region(SHEET_TEX, Rect2(px, y - 3.0, 16.0, 16.0), flower_region_for_ratio(comp_ratio), Color(1, 1, 1, fade))
	_draw_text("ERSCHLIESSUNG", Vector2i(int(px) + 19, int(y) + 1), VineStyle.PETAL, fade)
	var pct_txt: String = "%d%%" % comp_pct
	_draw_text(pct_txt, Vector2i(int(px + pw) - PixelText.width(pct_txt), int(y) + 1), VineStyle.WARM_GLOW, fade)
	y += 13.0

	# Progress bar with 30% / 60% / 100% milestone notches
	var bar_rect: Rect2 = Rect2(px, y, pw, 6.0)
	draw_rect(bar_rect.grow(1.0), Color(VineStyle.OUTLINE, 0.92 * fade))
	draw_rect(bar_rect, Color("140d24", 0.95 * fade))
	var fill_w: float = roundf(pw * comp_ratio)
	if fill_w > 0.0:
		draw_rect(Rect2(px, y, fill_w, 6.0), Color("4fe3c1", 0.92 * fade))
		draw_rect(Rect2(px, y, fill_w, 2.0), Color("b9fff0", 0.72 * fade))
	for mark_pct: float in [0.30, 0.60]:
		var mx: float = roundf(px + pw * mark_pct)
		draw_rect(Rect2(mx, y - 1.0, 1.0, 8.0), Color(VineStyle.WARM_GLOW, 0.85 * fade))
	y += 12.0

	# Explored surface row
	var exp_pct: int = int(stats.get("explored_pct", 0))
	_draw_text("ERKUNDETE FLÄCHE", Vector2i(int(px), int(y)), UiStyle.TEXT, fade)
	var exp_str: String = "%d%%" % exp_pct
	_draw_text(exp_str, Vector2i(int(px + pw) - PixelText.width(exp_str), int(y)), Color("78f4e6"), fade)
	y += 12.0

	# Named Places (6 places in 2 columns)
	var pl_seen: int = int(stats.get("places_seen", 0))
	var pl_tot: int = int(stats.get("places_total", 0))
	_draw_text("BENANNTE ORTE", Vector2i(int(px), int(y)), VineStyle.WARM_GLOW, fade)
	var pl_cnt_s: String = "%d / %d" % [pl_seen, pl_tot]
	_draw_text(pl_cnt_s, Vector2i(int(px + pw) - PixelText.width(pl_cnt_s), int(y)), UiStyle.TEXT, fade)
	y += 11.0

	var places: Array = stats.get("places", []) as Array
	var col_w: float = (pw - 6.0) * 0.5
	for i: int in places.size():
		var pd: Dictionary = places[i] as Dictionary
		var col_i: int = i % 2
		var row_i: int = i / 2
		var rx: float = px + float(col_i) * (col_w + 6.0)
		var ry: float = y + float(row_i) * 11.0
		var r_item: Rect2 = Rect2(rx, ry - 1.0, col_w, 10.0)
		var seen: bool = bool(pd.get("seen", false))
		var hov: bool = seen and r_item.has_point(_cursor)
		if hov:
			draw_rect(r_item, Color(VineStyle.WARM_GLOW, 0.14 * fade))
		draw_rect(Rect2(rx + 1.0, ry + 2.0, 3.0, 3.0), Color("78f4e6" if seen else "4c4363", fade))
		var raw_pname: String = String(pd.get("name", "")).trim_prefix("DIE ").trim_prefix("DER ").trim_prefix("DAS ") if col_w < 116.0 and String(pd.get("name", "")).length() > 14 else String(pd.get("name", ""))
		var disp_p: String = _fit_text(raw_pname, int(col_w) - 8) if seen else "???"
		_draw_text(disp_p, Vector2i(int(rx) + 7, int(ry)), (VineStyle.WARM_GLOW if hov else UiStyle.TEXT) if seen else UiStyle.TEXT_DIM, fade)
		_place_rects.append({"rect": r_item, "pos": pd.get("pos", Vector2.ZERO), "seen": seen})

	var place_rows: int = ceili(float(places.size()) / 2.0)
	y += float(maxi(place_rows, 1)) * 11.0 + 6.0

	# Divider line
	draw_rect(Rect2(px, y, pw, 1.0), Color(VineStyle.BARK_LIGHT, 0.45 * fade))
	y += 7.0

	# Chronicle Badge Counters (Waystones, Vistas, Chests, Puzzles, Flora & Fauna)
	_draw_badge_stat_row(Vector2(px, y), pw, REG_BADGE_WAYSTONE, "WEGSTEINE", int(stats.get("waystones_done", 0)), int(stats.get("waystones_total", 0)), Color("78f4e6"), fade)
	y += 15.0
	_draw_badge_stat_row(Vector2(px, y), pw, REG_BADGE_VISTA, "AUSSICHTSPUNKTE", int(stats.get("vistas_done", 0)), int(stats.get("vistas_total", 0)), Color("ffd98a"), fade)
	y += 15.0
	_draw_badge_stat_row(Vector2(px, y), pw, REG_BADGE_CHEST, "BEUTETRUHEN", int(stats.get("chests_done", 0)), int(stats.get("chests_total", 0)), Color("e6c468"), fade)
	y += 15.0
	_draw_badge_stat_row(Vector2(px, y), pw, REG_BADGE_PUZZLE, "PRÜFUNGEN & RÄTSEL", int(stats.get("puzzles_done", 0)), int(stats.get("puzzles_total", 0)), Color("cbaaff"), fade)
	y += 15.0
	_draw_badge_stat_row(Vector2(px, y), pw, REG_BADGE_FLORA, "FLORA & FAUNA", int(stats.get("flora_done", 0)), int(stats.get("flora_total", 0)), Color("a6e68f"), fade)

	if embedded_in_menu:
		MenuChrome.draw_text_centered(self, "KLICK ORT · AUF ATLAS ZEIGEN", cx, page.end.y - 16.0, MenuChrome.COL_TEXT_DIM, fade)


func _draw_badge_stat_row(at: Vector2, width: float, region: Rect2, label: String, done: int, total: int, accent: Color, fade: float) -> void:
	if SHEET_TEX != null:
		draw_texture_rect_region(SHEET_TEX, Rect2(at.x, at.y - 2.0, 12.0, 12.0), region, Color(1, 1, 1, fade))
	var complete: bool = total > 0 and done >= total
	_draw_text(label, Vector2i(int(at.x) + 16, int(at.y)), accent if complete else UiStyle.TEXT, fade)
	var val_s: String = "%d / %d" % [done, total]
	_draw_text(val_s, Vector2i(int(at.x + width) - PixelText.width(val_s), int(at.y)), accent if complete else UiStyle.TEXT_DIM, fade)


func _draw_right_page(page: Rect2, stats: Dictionary, fade: float, void_level: float) -> void:
	var px: float = page.position.x + 10.0
	var pw: float = page.size.x - 20.0
	var y: float = page.position.y + 9.0

	# 1. Schattenfrüchte Section (`x / 8` + compact 12px stride so milestones NEVER overflow bottom!)
	var t_done: int = int(stats.get("threads_done", 0))
	var t_tot: int = int(stats.get("threads_total", 0))
	if SHEET_TEX != null:
		draw_texture_rect_region(SHEET_TEX, Rect2(px, y - 2.0, 12.0, 12.0), REG_VEIL_ICON, Color(1, 1, 1, fade))
	_draw_text("SCHATTENFRÜCHTE", Vector2i(int(px) + 15, int(y)), Color("cbaaff"), fade)
	var tc_s: String = "%d / %d" % [t_done, t_tot]
	var tc_pad: int = 0 if embedded_in_menu else 18
	_draw_text(tc_s, Vector2i(int(px + pw) - PixelText.width(tc_s) - tc_pad, int(y)), VineStyle.WARM_GLOW if (t_tot > 0 and t_done >= t_tot) else UiStyle.TEXT, fade)
	y += 13.0

	var row_step: float = 12.0 if embedded_in_menu else 13.0
	var threads: Array = stats.get("threads", []) as Array
	if threads.is_empty():
		_draw_text("KEINE SCHATTENFRÜCHTE VERZEICHNET", Vector2i(int(px), int(y) + 6), UiStyle.TEXT_DIM, fade)
		y += 28.0
	else:
		for i: int in mini(threads.size(), 8):
			var td: Dictionary = threads[i] as Dictionary
			var col_ok: bool = bool(td.get("collected", false))
			var ry: float = y + float(i) * row_step
			var tid: String = String(td.get("id", "fruit_%d" % i))
			var traits: Dictionary = ShadowFruitArt.traits_for(tid)
			var accent: Color = traits["accent_bright"] as Color
			if col_ok:
				_draw_check(Vector2(px + 1.0, ry + 1.0), accent, fade)
				var p_lbl: String = _fit_text("%02d · %s" % [i + 1, String(td.get("place_name", "GEPFLÜCKT"))], int(pw) - 12)
				_draw_text(p_lbl, Vector2i(int(px) + 10, int(ry)), accent.lerp(Color.WHITE, 0.25), fade)
			else:
				draw_rect(Rect2(px + 2.0, ry + 2.0, 3.0, 3.0), Color(accent.r, accent.g, accent.b, 0.62 * fade))
				var hint: String = _fit_text(String(td.get("hint", "Verborgene Schattenfrucht")), int(pw) - 10)
				_draw_text(hint, Vector2i(int(px) + 10, int(ry)), Color("b8aed6"), fade * 0.92)
		y += float(mini(threads.size(), 8)) * row_step + 4.0

	# Divider cleanly separating fruits and milestones
	if embedded_in_menu:
		MenuChrome.draw_divider(self, page.get_center().x, y, pw, fade)
		y += 9.0
	else:
		if SHEET_TEX != null:
			draw_texture_rect_region(SHEET_TEX, Rect2(roundf(page.get_center().x - 16.0), roundf(y - 2.0), 32.0, 12.0), REG_VINE_DIVIDER, Color(1, 1, 1, 0.9 * fade))
		y += 11.0

	# 2. Milestone Rewards (30% / 60% / 100%) — strictly clamped inside page.end.y!
	_draw_text("MEILENSTEIN-BELOHNUNGEN", Vector2i(int(px), int(y)), VineStyle.WARM_GLOW, fade)
	y += 10.0

	var comp_pct: int = int(stats.get("completion_pct", 0))
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	var lp: Player = _resolve_local_player(tree)
	var app: AppearanceComponent = lp.appearance if lp != null else null
	var rew_z: Dictionary = _zone_rewards(_zone_id)
	var title_on: bool = app != null and app.title_id == String(rew_z["title_id"])

	var milestones: Array[Dictionary] = [
		{
			"tier": 30,
			"title": String(rew_z["t30"]),
			"desc": String(rew_z["d30"]),
			"claimed_label": "WÄHLEN",
		},
		{
			"tier": 60,
			"title": String(rew_z["t60"]),
			"desc": String(rew_z["d60"]),
			"claimed_label": "AKTIV" if _frame_enabled else "AUS",
		},
		{
			"tier": 100,
			"title": String(rew_z["t100"]),
			"desc": String(rew_z["d100"]),
			"claimed_label": "AKTIV" if title_on else "ANLEGEN",
		},
	]

	var avail_h: float = maxf(page.end.y - 10.0 - y, 90.0)
	var card_gap: float = 4.0
	var card_h: float = minf(34.0, floorf((avail_h - card_gap * 2.0) / 3.0))

	for idx: int in milestones.size():
		var m: Dictionary = milestones[idx]
		var tier: int = int(m["tier"])
		var cy: float = y + float(idx) * (card_h + card_gap)
		var card_r: Rect2 = Rect2(px, cy, pw, card_h)
		var claimed: bool = is_tier_claimed(_zone_id, tier)
		var ready_claim: bool = (not claimed) and (comp_pct >= tier)
		var hov: bool = card_r.has_point(_cursor) and (claimed or ready_claim)

		if embedded_in_menu:
			if ready_claim:
				MenuChrome.draw_gold(self, card_r, fade)
				MenuChrome.draw_shimmer(self, card_r, _time, MenuChrome.COL_GOLD_HOT, fade)
			else:
				MenuChrome.draw_inset(self, card_r, fade)
			if hov and claimed:
				draw_rect(card_r.grow(-2.0), Color(MenuChrome.COL_TEAL.r, MenuChrome.COL_TEAL.g, MenuChrome.COL_TEAL.b, 0.10 * fade))
		else:
			var bg_col: Color = Color("18122b") if (claimed or ready_claim) else Color("0f0a1c")
			if hov:
				bg_col = bg_col.lightened(0.10)
			draw_rect(card_r, Color(VineStyle.OUTLINE, 0.94 * fade))
			draw_rect(card_r.grow(-1.0), Color(bg_col, 0.94 * fade))
			var rim_col: Color = Color("4fe3c1") if claimed else (VineStyle.WARM_GLOW if ready_claim else VineStyle.BARK_LIGHT.darkened(0.2))
			draw_rect(Rect2(card_r.position + Vector2(1, 1), Vector2(card_r.size.x - 2.0, 1.0)), Color(rim_col, (0.85 if (claimed or ready_claim) else 0.35) * fade))

		if _flash_tier == tier and _flash_t > 0.01:
			VineStyle.glow(self, card_r.get_center(), 42.0, VineStyle.WARM_GLOW, _flash_t * 0.65 * fade)

		# Left icon from atlas_elements.png
		var ico_y: float = cy + floorf((card_h - 16.0) * 0.5)
		if SHEET_TEX != null:
			if tier == 30:
				draw_texture_rect_region(SHEET_TEX, Rect2(px + 4.0, ico_y, 16.0, 16.0), REG_STAMP_MINI, Color(1, 1, 1, (1.0 if (claimed or ready_claim) else 0.45) * fade))
			elif tier == 60:
				draw_texture_rect_region(SHEET_TEX, Rect2(px + 4.0, ico_y, 16.0, 16.0), REG_SEAL_UNLOCKED if claimed else REG_SEAL_LOCKED, Color(1, 1, 1, fade))
			else:
				if embedded_in_menu and (claimed or ready_claim):
					MenuChrome.draw_wax_seal(self, Vector2(px + 5.0, ico_y + 1.0), fade)
				else:
					draw_texture_rect_region(SHEET_TEX, Rect2(px + 4.0, ico_y, 16.0, 16.0), REG_SEAL_UNLOCKED if claimed else REG_SEAL_LOCKED, Color(1, 1, 1, fade))

		# Right action button first so title/desc fit cleanly without ever colliding!
		var btn_txt: String = String(m["claimed_label"]) if claimed else ("EINLÖSEN" if ready_claim else ("%d%%" % tier))
		var btn_w: float = maxf(float(PixelText.width(btn_txt) + 12), 46.0)
		var btn_r: Rect2 = Rect2(card_r.end.x - btn_w - 5.0, cy + floorf((card_h - 15.0) * 0.5), btn_w, 15.0)
		var text_max_w: int = int(btn_r.position.x - (px + 23.0) - 4.0)
		_draw_text(_fit_text(String(m["title"]), text_max_w), Vector2i(int(px) + 23, int(cy) + 5), VineStyle.WARM_GLOW if ready_claim else (VineStyle.PETAL if claimed else UiStyle.TEXT_DIM), fade)
		_draw_text(_fit_text(String(m["desc"]), text_max_w), Vector2i(int(px) + 23, int(cy) + 16), Color("78f4e6") if claimed else UiStyle.TEXT_DIM, fade)

		if embedded_in_menu:
			MenuChrome.draw_button(self, btn_r, btn_txt, hov, ready_claim, false, not (claimed or ready_claim), fade)
		else:
			var btn_tone: Color = Color("4fe3c1") if claimed else (VineStyle.WARM_GLOW if ready_claim else UiStyle.PANEL_DARK)
			var btn_tcol: Color = VineStyle.PETAL if (claimed or ready_claim) else UiStyle.TEXT_DIM
			if ready_claim:
				var pulse: float = 0.65 + 0.35 * sin(_time * 4.5 + float(idx))
				VineStyle.glow(self, btn_r.get_center(), 18.0, VineStyle.WARM_GLOW, 0.45 * pulse * fade)
			VineStyle.plate(self, btn_r, btn_txt, btn_tone, btn_tcol, fade * (1.0 if (claimed or ready_claim) else 0.65), void_level * 0.4)
		_reward_rects.append({
			"rect": card_r,
			"tier": tier,
			"can_claim": ready_claim,
			"claimed": claimed,
		})
