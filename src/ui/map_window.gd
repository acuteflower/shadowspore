class_name MapWindow
extends Control
## The Shadowspore 2.0 Atlas window (`M`).
## Hosts the living 4-level `AtlasView` (`ORT -> ZONE -> KONTINENT -> WELT`), `MapMarkers`,
## `16 px/tile` Match-Cut opening/closing, cross-zone waystone travel, co-op `"ZU IHM"` travel,
## quest preview focus, and the integrated `AtlasBook`.

const PIN_KINDS: Array[Dictionary] = [
	{"name": "WEGZEICHEN", "color": Color("b9f3ee"), "rows": ["..X..", ".X.X.", "X...X", ".X.X.", "..X.."]},
	{"name": "GEFAHR", "color": Color("ff5f8a"), "rows": ["..X..", "..X..", "..X..", ".....", "..X.."]},
	{"name": "ZIEL", "color": Color("ffd98a"), "rows": ["X...X", ".X.X.", "..X..", ".X.X.", "X...X"]},
	{"name": "LAGER", "color": Color("a6e68f"), "rows": ["..X..", ".XXX.", "XXXXX", "X...X", "X...X"]},
]
const PLAYER_TONES: Array[Color] = [Color("b9f3ee"), Color("ffd98a"), Color("ff7fd8"), Color("a6e68f")]

signal travel_chosen(from_id: String, to_id: String)
signal travel_cancelled
signal quest_preview_closed
signal open_chronicle_requested(zone_id: StringName)

var _player: Node2D
var _discovery: MapDiscovery
var _loaded: bool = false
var _opening: bool = false
var _quest_preview: String = ""
var _travel_from: String = ""
var _present_left: float = 0.0
var _present_age: float = 0.0
var _present_ring: float = 0.0
var _present_tile: Vector2 = Vector2.ZERO

var _v2_mode: bool = false
var _v2_director: Node = null
var _atlas_view: AtlasView = null
var _v2_markers: MapMarkers = null
var _v2_handled_waystone_travel: bool = false
var _v2_traveling: bool = false
var _pending_atlas_ui: Dictionary = {}


static func clear_cache() -> void:
	pass


func _ready() -> void:
	add_to_group("map_window")
	visible = false
	z_index = 30
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `player` is untyped on purpose (the player scene preloads the HUD).
func bind(player: Node) -> void:
	_player = player as Node2D
	if _player != null and _player.has_meta("pending_atlas_ui"):
		var pending: Variant = _player.get_meta("pending_atlas_ui")
		_player.remove_meta("pending_atlas_ui")
		if pending is Dictionary:
			import_atlas_ui_state(pending as Dictionary)
	if _atlas_view != null and _atlas_view.atlas_book() != null:
		_atlas_view.atlas_book().setup(Atlas.shared(), _discovery, _v2_director, _player)


func _find_zone_director() -> Node:
	if not is_inside_tree():
		return null
	var d: Node = get_tree().get_first_node_in_group("zone_director")
	if d != null:
		return d
	var w: Node = get_tree().get_first_node_in_group("world")
	if w != null and w.has_method("director"):
		var w_dir: Variant = w.call("director")
		if w_dir is Node:
			return w_dir as Node
	return null


func _is_v2_continent_unlocked() -> bool:
	if _discovery != null and _discovery.is_continent_unlocked():
		return true
	if _player is Player and (_player as Player).quests != null and (_player as Player).quests.has_flag("atlas_continent_unlocked"):
		return true
	return false


func _ensure_v2_atlas() -> bool:
	if _v2_mode and _atlas_view != null:
		if _discovery == null and is_inside_tree():
			_discovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
			if _discovery != null:
				_atlas_view.setup(Atlas.shared(), _discovery, _v2_markers, _v2_director)
				if not _discovery.continent_unlocked_changed.is_connected(_on_v2_continent_unlocked_changed):
					_discovery.continent_unlocked_changed.connect(_on_v2_continent_unlocked_changed)
		return true
	var dir: Node = _find_zone_director()
	if dir == null:
		return false
	_v2_director = dir
	_discovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery if is_inside_tree() else null
	if _v2_markers == null:
		_v2_markers = MapMarkers.new()
		_v2_markers.register_default_providers()
	if _atlas_view == null:
		_atlas_view = AtlasView.new()
		_atlas_view.name = "AtlasView"
		add_child(_atlas_view)
		_atlas_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_atlas_view.visible = false
		_atlas_view.waystone_travel_requested.connect(_on_v2_waystone_travel_requested)
		_atlas_view.join_peer_requested.connect(_on_v2_join_peer_requested)
		_atlas_view.open_chronicle_requested.connect(func(zid: StringName) -> void:
			open_chronicle_requested.emit(zid))
	_atlas_view.setup(Atlas.shared(), _discovery, _v2_markers, _v2_director)
	_atlas_view.embedded_top_inset = GameMenu.RAIL_H if embedded_in_menu else 0.0
	_atlas_view.embedded_bottom_inset = GameMenu.FOOTER_H if embedded_in_menu else 0.0
	if _atlas_view.atlas_book() != null:
		_atlas_view.atlas_book().setup(Atlas.shared(), _discovery, _v2_director, _player)
	if _discovery != null and not _discovery.continent_unlocked_changed.is_connected(_on_v2_continent_unlocked_changed):
		_discovery.continent_unlocked_changed.connect(_on_v2_continent_unlocked_changed)
	_atlas_view.set_continent_unlocked(_is_v2_continent_unlocked(), false)
	_v2_mode = true
	_loaded = true
	if not _pending_atlas_ui.is_empty():
		var copy_ui: Dictionary = _pending_atlas_ui.duplicate(true)
		_pending_atlas_ui.clear()
		import_atlas_ui_state(copy_ui)
	if _player != null and _player.has_meta("pending_atlas_ui"):
		var p_ui: Variant = _player.get_meta("pending_atlas_ui")
		_player.remove_meta("pending_atlas_ui")
		if p_ui is Dictionary:
			import_atlas_ui_state(p_ui as Dictionary)
	return true


func _on_v2_continent_unlocked_changed(unlocked: bool) -> void:
	if _atlas_view != null:
		if unlocked and _player is Player and (_player as Player).quests != null:
			(_player as Player).quests.set_flag("atlas_continent_unlocked")
		if _atlas_view.is_continent_unlocked() != unlocked:
			_atlas_view.set_continent_unlocked(unlocked, false)


func warm() -> void:
	if not _loaded:
		_ensure_v2_atlas()


func warm_step(_deadline_usec: int) -> bool:
	if _loaded:
		return true
	_ensure_v2_atlas()
	return true


func _process(delta: float) -> void:
	if not _v2_mode and _find_zone_director() != null:
		_ensure_v2_atlas()
	if not _v2_mode:
		visible = false
		return
	if _player != null and _player.has_meta("pending_atlas_ui"):
		var p_ui: Variant = _player.get_meta("pending_atlas_ui")
		_player.remove_meta("pending_atlas_ui")
		if p_ui is Dictionary:
			import_atlas_ui_state(p_ui as Dictionary)
	if not embedded_in_menu and InputManager.map_pressed():
		if _opening:
			if _v2_traveling:
				pass
			elif _atlas_view != null and _atlas_view.is_book_open():
				_atlas_view.atlas_book().close_book(false)
			elif _atlas_view != null and _atlas_view.is_match_cut_animating():
				_atlas_view.skip_match_cut_to_zone()
			else:
				_set_open(false)
		elif not InputManager.ui_blocking:
			_set_open(true)
	if _present_left > 0.0 and _opening:
		_present_left -= delta
		_present_age += delta
		if _present_left <= 0.0:
			_set_open(false)
	visible = _opening or (_atlas_view != null and _atlas_view.is_closing())


func open_travel(from_id: String) -> bool:
	if _opening or _v2_traveling:
		return false
	if not _ensure_v2_atlas() or _atlas_view == null:
		return false
	_v2_handled_waystone_travel = false
	_travel_from = from_id
	_set_open(true)
	if not _opening:
		_travel_from = ""
		return false
	var awake_zones: Dictionary = {}
	var wm_v2: Waystones = Waystones.of(get_tree())
	if wm_v2 != null:
		for entry_v2: Dictionary in wm_v2.entries():
			if bool(entry_v2.get("awake", false)):
				awake_zones[String(entry_v2.get("zone", ""))] = true
	_atlas_view.skip_match_cut_to_zone()
	if awake_zones.size() >= 2 and _atlas_view.is_continent_unlocked():
		_atlas_view.jump_to_level(AtlasView.LEVEL_CONTINENT, Vector2.ZERO, 0.5)
	return true


func present(tile: Vector2, seconds: float, ring_tiles: float = 0.0) -> void:
	if _opening or not _ensure_v2_atlas() or _atlas_view == null:
		return
	_set_open(true)
	if not _opening:
		return
	_atlas_view.skip_match_cut_to_zone()
	_atlas_view.set_center_tile(tile)
	_atlas_view.trigger_ping_pulse(tile, Color("78f4e6"))
	_present_left = seconds
	_present_age = 0.0
	_present_ring = ring_tiles
	_present_tile = tile


static func quest_location(entry: Dictionary) -> Vector2:
	var area: Vector3 = entry.get("area", Vector3.INF) as Vector3
	if area != Vector3.INF:
		return Vector2(area.x, area.y)
	var target: Vector2 = entry.get("target", Vector2.INF) as Vector2
	return Interiors.to_world(target)


func open_quest_preview(entry: Dictionary) -> void:
	var location: Vector2 = quest_location(entry)
	if _opening or location == Vector2.INF or not InputManager.journal_open:
		return
	if not _ensure_v2_atlas() or _atlas_view == null:
		return
	_set_open(true)
	if _opening:
		_quest_preview = String(entry.id)
		var q_tile: Vector2 = location / 16.0
		_atlas_view.skip_match_cut_to_zone()
		_atlas_view.set_center_tile(q_tile)
		_atlas_view.trigger_ping_pulse(q_tile, VineStyle.WARM_GLOW)


func cancel_quest_preview() -> void:
	if _quest_preview != "":
		_set_open(false, false)


func unlock_continent_solemn() -> void:
	_ensure_v2_atlas()
	if _player is Player and (_player as Player).quests != null:
		(_player as Player).quests.set_flag("atlas_continent_unlocked")
	if _discovery == null and is_inside_tree():
		_discovery = get_tree().get_first_node_in_group("map_discovery") as MapDiscovery
	if _discovery != null:
		_discovery.request_continent_unlocked(true)
	if _atlas_view != null:
		_atlas_view.set_continent_unlocked(true, false)
		if not _opening:
			_set_open(true)
		_atlas_view.play_solemn_unlock_rollout()
		Sfx.ui(self, "waystone_wake", -2.0)


func set_continent_unlocked_instant(unlocked: bool) -> void:
	_ensure_v2_atlas()
	if _atlas_view != null:
		_atlas_view.set_continent_unlocked(unlocked, false)


func did_handle_v2_waystone_travel() -> bool:
	return _v2_handled_waystone_travel


func atlas_view() -> AtlasView:
	_ensure_v2_atlas()
	return _atlas_view


func sync_book_reward_claimed(zone_id: StringName, tier: int, reward_id: StringName) -> void:
	if _atlas_view != null:
		_atlas_view._on_book_reward_claimed(zone_id, tier, reward_id)


func _close_after_travel() -> void:
	if embedded_in_menu and get_parent() != null:
		var gm: Node = get_parent().get_node_or_null("GameMenu")
		if gm != null and gm.has_method("close"):
			gm.call("close", true)
			return
	_set_open(false)


func export_atlas_ui_state() -> Dictionary:
	_ensure_v2_atlas()
	return {
		"pins": _v2_markers.export_pins() if _v2_markers != null else {},
		"book": _atlas_view.atlas_book().export_state() if (_atlas_view != null and _atlas_view.atlas_book() != null) else {},
	}


func import_atlas_ui_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	if not _ensure_v2_atlas():
		_pending_atlas_ui = data.duplicate(true)
		return
	if data.get("pins") is Dictionary and _v2_markers != null:
		_v2_markers.import_pins(data["pins"] as Dictionary)
	if data.get("book") is Dictionary and _atlas_view != null and _atlas_view.atlas_book() != null:
		_atlas_view.atlas_book().import_state(data["book"] as Dictionary)
	elif (data.has("claimed") or data.has("stamps") or data.has("claimed_milestones") or data.has("unlocked_stamps")) and _atlas_view != null and _atlas_view.atlas_book() != null:
		_atlas_view.atlas_book().import_state(data)
	if _atlas_view != null:
		_atlas_view.queue_redraw()


func _set_open(open: bool, return_to_journal: bool = true) -> void:
	_present_left = 0.0
	_present_ring = 0.0
	if not open and _travel_from != "":
		_travel_from = ""
		travel_cancelled.emit()
	if open and not _ensure_v2_atlas():
		return
	var live_cap: ImageTexture = null
	var cam_info: Dictionary = {}
	if _v2_mode and open and not _opening:
		cam_info = _live_camera_tile_and_scale()
		if bool(cam_info.get("outer", false)):
			live_cap = _capture_live_viewport()
	elif _v2_mode and not open and _opening:
		cam_info = _live_camera_tile_and_scale()
	if open and InputManager.journal_open:
		var journal: QuestJournal = get_parent().get_node_or_null("QuestJournal") as QuestJournal
		if journal != null:
			journal.close()
	if open != _opening:
		Sfx.ui(self, "map_open" if open else "map_close", -2.0)
	_opening = open
	InputManager.map_open = open
	var health: HealthComponent = _player.get("health") as HealthComponent if is_instance_valid(_player) else null
	InputManager.ui_blocking = open or InputManager.menu_open or (health != null and health.current <= 0.0)
	if _atlas_view == null:
		return
	if open:
		_v2_handled_waystone_travel = false
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		_atlas_view.mouse_filter = Control.MOUSE_FILTER_STOP
		_atlas_view.set_continent_unlocked(_is_v2_continent_unlocked(), false)
		var p_tile: Vector2 = _v2_player_outer_tile()
		var p_zone: StringName = _v2_player_zone(p_tile)
		var cap_tile: Vector2 = cam_info.get("tile", Vector2.INF) as Vector2
		var cap_scale: float = float(cam_info.get("scale", -1.0))
		_atlas_view.begin_open(live_cap, p_tile, p_zone, false, cap_tile, cap_scale)
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_atlas_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var close_tile: Vector2 = cam_info.get("tile", _v2_player_outer_tile()) as Vector2
		var close_scale: float = float(cam_info.get("scale", AtlasView.MATCH_CUT_START_ZOOM))
		_atlas_view.begin_close(false, close_tile, close_scale)
		if _quest_preview != "":
			_quest_preview = ""
			if return_to_journal:
				quest_preview_closed.emit()


var embedded_in_menu: bool = false


func set_embedded_active(open: bool, with_match_cut: bool = false) -> void:
	if open:
		if not _ensure_v2_atlas() or _atlas_view == null:
			return
		_atlas_view.embedded_top_inset = GameMenu.RAIL_H if embedded_in_menu else 0.0
		_atlas_view.embedded_bottom_inset = GameMenu.FOOTER_H if embedded_in_menu else 0.0
		var live_cap: ImageTexture = null
		var cam_info: Dictionary = {}
		if with_match_cut:
			cam_info = _live_camera_tile_and_scale()
			if bool(cam_info.get("outer", false)):
				live_cap = _capture_live_viewport()
		_opening = true
		InputManager.map_open = true
		_v2_handled_waystone_travel = false
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		_atlas_view.mouse_filter = Control.MOUSE_FILTER_STOP
		_atlas_view.set_continent_unlocked(_is_v2_continent_unlocked(), false)
		var p_tile: Vector2 = _v2_player_outer_tile()
		var p_zone: StringName = _v2_player_zone(p_tile)
		var cap_tile: Vector2 = cam_info.get("tile", Vector2.INF) as Vector2
		var cap_scale: float = float(cam_info.get("scale", -1.0))
		_atlas_view.begin_open(live_cap, p_tile, p_zone, not with_match_cut, cap_tile, cap_scale)
	else:
		_opening = false
		InputManager.map_open = false
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _atlas_view != null:
			_atlas_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_atlas_view.begin_close(true)


func focus_world_tile(tile: Vector2, _zone_id: StringName) -> void:
	if _atlas_view != null:
		_atlas_view.skip_match_cut_to_zone()
		_atlas_view.set_center_tile(tile)
		_atlas_view.trigger_ping_pulse(tile, Color("78f4e6"))


func _unhandled_input(event: InputEvent) -> void:
	if _v2_mode and _v2_traveling:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
		return
	if _v2_mode and _atlas_view != null and _atlas_view.is_book_open() and event.is_action_pressed("ui_cancel"):
		_atlas_view.atlas_book().close_book(false)
		get_viewport().set_input_as_handled()
		return
	if embedded_in_menu:
		return
	if _opening and (event.is_action_pressed("ui_cancel") or (_quest_preview != "" and event.is_action_pressed("quest_journal"))):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _capture_live_viewport() -> ImageTexture:
	if DisplayServer.get_name() == "headless":
		return null
	var vp: Viewport = get_viewport()
	if vp == null:
		return null
	var vtex: ViewportTexture = vp.get_texture()
	if vtex == null:
		return null
	var img: Image = vtex.get_image()
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _live_camera_tile_and_scale() -> Dictionary:
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d() if vp != null else null
	if cam != null and is_instance_valid(cam):
		var cam_px: Vector2 = cam.get_screen_center_position()
		if cam_px.is_finite() and not PocketSpace.is_pocket(cam_px) and not Interiors.is_pocket(cam_px):
			return {
				"outer": true,
				"tile": cam_px / 16.0,
				"scale": clampf(16.0 * cam.zoom.x, 4.0, 48.0),
			}
	var fallback_t: Vector2 = _v2_player_outer_tile()
	return {
		"outer": false,
		"tile": fallback_t,
		"scale": AtlasView.MATCH_CUT_START_ZOOM,
	}


func _v2_player_outer_tile() -> Vector2:
	if _player != null and is_instance_valid(_player):
		var raw_px: Vector2 = _player.global_position
		var outer_px: Vector2 = Interiors.outer(get_tree(), raw_px)
		if outer_px.is_finite() and not PocketSpace.is_pocket(outer_px) and not ((PocketSpace.is_pocket(raw_px) or Interiors.is_pocket(raw_px)) and outer_px == Vector2.ZERO):
			return outer_px / 16.0
		var pzone: StringName = PocketSpace.parent_zone_at(raw_px)
		if pzone != &"" and Atlas.shared().zone(pzone) != null:
			return Atlas.shared().zone(pzone).center()
	var def_z: Atlas.Zone = Atlas.shared().zone(&"windkap")
	return def_z.center() if def_z != null else Vector2(1079.0, 961.0)


func _v2_player_zone(fallback_tile: Vector2) -> StringName:
	if _v2_director != null and _player != null and is_instance_valid(_player):
		var pid: int = _player.name.to_int()
		var pz_var: Variant = _v2_director.get("player_zone")
		if pz_var is Dictionary and (pz_var as Dictionary).has(pid):
			var z_sn: StringName = StringName(str((pz_var as Dictionary)[pid]))
			if z_sn != &"":
				return z_sn
		var raw_px: Vector2 = _player.global_position
		if PocketSpace.is_pocket(raw_px):
			var parent_z: StringName = PocketSpace.parent_zone_at(raw_px)
			if parent_z != &"":
				return parent_z
	var cid: StringName = &"main"
	if _v2_director != null and _v2_director.get("continent_id") is StringName:
		cid = _v2_director.get("continent_id") as StringName
	return Atlas.shared().zone_at_tile(cid, fallback_tile)


func _on_v2_waystone_travel_requested(waystone_id: String, zone_id: StringName, target_tile: Vector2) -> void:
	if _v2_traveling or _atlas_view == null or _player == null or not is_instance_valid(_player):
		return
	if _player is Player:
		var p_obj: Player = _player as Player
		if p_obj.story_lock or p_obj.intro != null or (p_obj.health != null and p_obj.health.current <= 0.0):
			return
	var wm: Waystones = Waystones.of(get_tree())
	if wm != null and not wm.is_awake(waystone_id):
		return
	if wm != null:
		wm.request_prepare_zone(waystone_id)
	_v2_traveling = true
	Sfx.ui(self, "waystone_wake", -3.0)
	_atlas_view.fly_to_zone_via_veil(zone_id, target_tile, func() -> void:
		_finish_v2_waystone_arrival(waystone_id, zone_id, target_tile))


func _finish_v2_waystone_arrival(waystone_id: String, zone_id: StringName, target_tile: Vector2) -> void:
	_v2_traveling = false
	var wm: Waystones = Waystones.of(get_tree()) if is_inside_tree() else null
	var dest_px: Vector2 = wm.arrival_position(waystone_id) if wm != null else Vector2.INF
	if not dest_px.is_finite() and is_inside_tree():
		var w_node: Node = get_tree().get_first_node_in_group("world")
		if w_node != null and w_node.has_method("respawn_point_for") and _player != null:
			var r_v: Variant = w_node.call("respawn_point_for", _player.name.to_int(), StringName(waystone_id))
			if r_v is Vector2:
				dest_px = r_v as Vector2
	if not dest_px.is_finite():
		dest_px = Atlas.px_of(target_tile) + Vector2(8.0, 28.0)
	if _player != null and is_instance_valid(_player) and _player.has_method("request_teleport"):
		_player.call("request_teleport", dest_px)
	if wm != null:
		var st_node: WaystoneStatue = wm.statue_node(waystone_id)
		if st_node != null and st_node.has_method("flare"):
			st_node.call("flare")
	if _atlas_view != null:
		_atlas_view._live_capture = null
		_atlas_view._player_tile = Atlas.tile_of(dest_px)
		if zone_id != &"":
			_atlas_view._player_zone = zone_id
	if _travel_from != "":
		var from_id: String = _travel_from
		_travel_from = ""
		_v2_handled_waystone_travel = true
		_close_after_travel()
		travel_chosen.emit(from_id, waystone_id)
	else:
		_close_after_travel()


func _on_v2_join_peer_requested(peer_id: int, target_zone: StringName, waystone_id: String, target_tile: Vector2) -> void:
	if _v2_traveling or _atlas_view == null or _player == null or not is_instance_valid(_player):
		return
	if _player is Player:
		var p_obj: Player = _player as Player
		if p_obj.story_lock or p_obj.intro != null or (p_obj.health != null and p_obj.health.current <= 0.0):
			return
	var wm: Waystones = Waystones.of(get_tree()) if is_inside_tree() else null
	if wm != null and not waystone_id.is_empty():
		wm.request_prepare_zone(waystone_id)
	_v2_traveling = true
	Sfx.ui(self, "waystone_wake", -3.0)
	_atlas_view.fly_to_zone_via_veil(target_zone, target_tile, func() -> void:
		_finish_v2_join_peer_arrival(peer_id, target_zone, waystone_id, target_tile))


func _finish_v2_join_peer_arrival(peer_id: int, target_zone: StringName, waystone_id: String, target_tile: Vector2) -> void:
	_v2_traveling = false
	var coop: Node = get_tree().get_first_node_in_group("zone_coop") if is_inside_tree() else null
	if coop != null and coop.has_method(&"request_join_peer"):
		coop.call(&"request_join_peer", peer_id, false)
	else:
		var wm: Waystones = Waystones.of(get_tree()) if is_inside_tree() else null
		var dest_px: Vector2 = wm.arrival_position(waystone_id) if (wm != null and not waystone_id.is_empty()) else (Atlas.px_of(target_tile) + Vector2(8.0, 28.0))
		if _player != null and is_instance_valid(_player) and _player.has_method("request_teleport") and dest_px.is_finite():
			_player.call("request_teleport", dest_px)
	if _atlas_view != null:
		_atlas_view._live_capture = null
		_atlas_view._player_tile = target_tile
		if target_zone != &"":
			_atlas_view._player_zone = target_zone
	_close_after_travel()
