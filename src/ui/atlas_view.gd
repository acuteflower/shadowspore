class_name AtlasView
extends Control
## Unified 4-level living world atlas (`ORT`, `ZONE`, `KONTINENT`, `WELT`) with
## 16 px/tile Match-Cut, Stone-Setter unlock gate, bark-paper hover cards,
## MapMarkers clustering/routes, and live SunShadows/WeatherField/Night shaders.

signal level_changed(level: StringName)
signal zone_hovered(zone_id: StringName, card_data: Dictionary)
signal zone_double_clicked(zone_id: StringName)
signal unlock_limit_hit()
signal match_cut_finished()
signal marker_clicked(marker: Dictionary)
signal waystone_travel_requested(waystone_id: String, zone_id: StringName, target_tile: Vector2)
signal join_peer_requested(peer_id: int, target_zone: StringName, waystone_id: String, target_tile: Vector2)
signal open_chronicle_requested(zone_id: StringName)

const SHADER_ZONE: Shader = preload("res://assets/shaders/atlas_zone.gdshader")
const SHADER_CONTINENT: Shader = preload("res://assets/shaders/atlas_continent.gdshader")
const SHADER_WORLD: Shader = preload("res://assets/shaders/atlas_world.gdshader")
const ATLAS_ELEMENTS_TEX: Texture2D = preload("res://assets/ui/atlas_elements.png")

const LEVEL_ORT: StringName = &"ort"
const LEVEL_ZONE: StringName = &"zone"
const LEVEL_CONTINENT: StringName = &"continent"
const LEVEL_WORLD: StringName = &"world"

const ZOOM_MIN: float = 0.02
const ZOOM_MAX: float = 6.0
const ZOOM_UNCHARTED_MAX: float = 2.4
const ZOOM_WORLD_MAX: float = 0.08
const ZOOM_CONTINENT_MAX: float = 0.6
const ZOOM_ZONE_MAX: float = 2.0

const ZOOM_DEFAULT_ORT: float = 3.2
const ZOOM_DEFAULT_ZONE: float = 1.1
const ZOOM_DEFAULT_CONTINENT: float = 0.22
const ZOOM_DEFAULT_WORLD: float = 0.05

const MATCH_CUT_START_ZOOM: float = 16.0
const MATCH_CUT_DISSOLVE_SEC: float = 0.25
const MATCH_CUT_ZOOM_SEC: float = 0.50
const CLOSE_SECONDS: float = 0.30
const SOLEMN_ROLLOUT_SEC: float = 2.6

const WHEEL_STEP: float = 1.28
const PAN_SPEED: float = 300.0
const ZOOM_X: float = 618.0
const ZOOM_TOP: float = 100.0
const ZOOM_BOTTOM: float = 326.0

const LEVEL_ORDER: Array[StringName] = [LEVEL_ORT, LEVEL_ZONE, LEVEL_CONTINENT, LEVEL_WORLD]
const LEVEL_LABELS: Dictionary = {
	&"ort": "ORT",
	&"zone": "ZONE",
	&"continent": "KONTINENT",
	&"world": "WELT",
}

const DEFAULT_FILTER_CATS: Array[Dictionary] = [
	{"id": &"quests", "label": "QUESTS", "color": Color("ffd98a")},
	{"id": &"waystones", "label": "WEGSTEINE", "color": Color("78f4e6")},
	{"id": &"chests_puzzles", "label": "TRUHEN & RÄTSEL", "color": Color("e6c468")},
	{"id": &"nature", "label": "ORTE & NATUR", "color": Color("a6ceae")},
	{"id": &"players", "label": "SPIELER", "color": Color("b9f3ee")},
	{"id": &"pins", "label": "NADELN", "color": Color("ff7fd8")},
]

const PIN_KIND_LIST: Array[Dictionary] = [
	{"id": &"mark", "name": "WEGZEICHEN", "color": Color("b9f3ee"), "rows": ["..X..", ".X.X.", "X...X", ".X.X.", "..X.."]},
	{"id": &"danger", "name": "GEFAHR", "color": Color("ff5f8a"), "rows": ["..X..", "..X..", "..X..", ".....", "..X.."]},
	{"id": &"loot", "name": "FUNDSTELLE", "color": Color("ffd98a"), "rows": ["X...X", ".X.X.", "..X..", ".X.X.", "X...X"]},
	{"id": &"camp", "name": "LAGER", "color": Color("a6e68f"), "rows": ["..X..", ".XXX.", "XXXXX", "X...X", "X...X"]},
	{"id": &"coast_wave", "name": "WINDKAP-WELLE", "color": Color("4fe3c1"), "unlock": &"coast_wave", "stamp_rect": Rect2(76, 4, 16, 16), "rows": ["..X..", ".XXX.", "X.X.X", "XXXXX", ".XXX."]},
]

const BIOME_COLORS: Dictionary = {
	"meadow": Color("3e7d56"),
	"forest": Color("254d3e"),
	"coast": Color("7f9478"),
	"beach": Color("c8b48a"),
	"cliff": Color("5b5369"),
	"highland": Color("4c5663"),
	"void": Color("2a1a42"),
}

# Core data & external hooks
var _atlas: Atlas
var _discovery: MapDiscovery
var _markers: MapMarkers
var _director: Node
var _continent_id: StringName = &"main"

# Layer hierarchy
var _continent_rect: ColorRect
var _zone_rect: ColorRect
var _world_rect: ColorRect
var _overlay: Control
var _zone_mat: ShaderMaterial = ShaderMaterial.new()
var _continent_mat: ShaderMaterial = ShaderMaterial.new()
var _world_mat: ShaderMaterial = ShaderMaterial.new()

# Camera & view state (continent tiles)
var _center_tile: Vector2 = Vector2(1079.0, 961.0)
var _zoom: float = ZOOM_DEFAULT_ZONE
var _zoom_target: float = ZOOM_DEFAULT_ZONE
var _anchor_screen: Vector2 = Vector2(320.0, 180.0)
var _velocity: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _slider_drag: bool = false
var _last_drag_pos: Vector2 = Vector2.ZERO
var _cursor: Vector2 = Vector2(320.0, 180.0)

# Open / Match-Cut / Close / Transition state
var _is_open: bool = false
var _closing: bool = false
var _open_t: float = 0.0
var _time: float = 0.0
var _match_cut_active: bool = false
var _match_cut_elapsed: float = 0.0
var _match_cut_zooming: bool = false
var _match_cut_start_zoom: float = MATCH_CUT_START_ZOOM
var _capture_center: Vector2 = Vector2.ZERO
var _capture_scale: float = MATCH_CUT_START_ZOOM
var _live_capture: Texture2D
var _player_tile: Vector2 = Vector2(1079.0, 961.0)
var _player_zone: StringName = &""
var _active_zone_id: StringName = &""
var _close_start_zoom: float = ZOOM_DEFAULT_ZONE
var _close_start_center: Vector2 = Vector2(1079.0, 961.0)
var _close_target_center: Vector2 = Vector2(1079.0, 961.0)
var _close_target_scale: float = MATCH_CUT_START_ZOOM
var _close_elapsed: float = 0.0
var _compass_spin_t: float = 1.0

# Tweens for smooth fly / level jump / solemn rollout / veil travel
var _tween_active: bool = false
var _tween_elapsed: float = 0.0
var _tween_duration: float = 0.6
var _tween_start_center: Vector2 = Vector2.ZERO
var _tween_end_center: Vector2 = Vector2.ZERO
var _tween_start_zoom: float = 1.0
var _tween_end_zoom: float = 1.0
var _tween_focus: Vector2 = Vector2.ZERO

var _continent_unlocked: bool = false
var _solemn_active: bool = false
var _solemn_t: float = 0.0
var _unlock_wave: float = 1.0
var _limit_bump_t: float = 0.0
var _limit_emit_cd: float = 0.0
var _veil_progress: float = 0.0

var _veil_fly_active: bool = false
var _veil_fly_stage: int = 0
var _veil_fly_t: float = 0.0
var _veil_fly_target_zone: StringName = &""
var _veil_fly_target_tile: Vector2 = Vector2.ZERO
var _veil_fly_start_tile: Vector2 = Vector2.ZERO
var _veil_fly_cb: Callable = Callable()

# Preview overrides & standalone WeatherField
var _preview_time: float = -1.0
var _preview_weather: Dictionary = {}
var _local_weather_field: WeatherField
var _preview_flash: float = 0.0
var _preview_flash_timer: float = 0.0
var _preview_flash_uv: Vector2 = Vector2(0.5, 0.5)
var _preview_reveal_all: bool = false

# Cached zone & continent textures
var _zone_textures: Dictionary = {} ## zone_id -> {map, light, meta, fog}
var _continent_textures: Dictionary = {} ## continent_id -> {map, light, engraving, zone_id, meta, zone_order}
var _fallback_fog_tex: ImageTexture
var _fallback_white_tex: ImageTexture

# Dynamic UI & interaction state
var _current_level: StringName = LEVEL_ZONE
var _level_tag_rects: Dictionary = {} ## StringName -> Rect2
var _place_hit_rects: Array[Dictionary] = [] ## [{rect, pos, seen}]
var _filter_open: bool = false
var _filter_branch_rect: Rect2 = Rect2()
var _filter_hit_rects: Array[Dictionary] = [] ## [{rect, id}]
var _local_filter_disabled: Dictionary = {}
var _marker_hit_rects: Array[Dictionary] = [] ## [{rect, marker}]
var _pings: Array[Dictionary] = [] ## [{tile, color, age, max_age}]
var _hovered_zone_id: StringName = &""
var _hover_zone_t: float = 0.0
var _hover_zone_card: Dictionary = {}
var _focused_locked_zone_id: StringName = &""
var _focused_locked_zone_t: float = 0.0
var _continent_label_rects: Array[Rect2] = []
var _placed_overlay_rects: Array[Rect2] = []
var _placed_world_rects: Array[Rect2] = []
var _hovered_marker: Dictionary = {}
var _pin_kind_idx: int = 0
var _local_pins: Dictionary = {} ## fallback pins if _markers == null: zone_id -> Array[Dictionary]
var _local_land_counts: Dictionary = {} ## zone_id -> {land: int, seen: int}
var _book: AtlasBook
var _flower_hit_rect: Rect2 = Rect2()
var _home_btn_rect: Rect2 = Rect2()
var _pin_slot_rects: Array[Dictionary] = [] ## [{rect, idx}]
var _selected_peer_marker: Dictionary = {}
var _peer_join_rect: Rect2 = Rect2()
var _peer_route_pts: PackedVector2Array = PackedVector2Array()
var _peer_route_timer: float = 0.0
var _toast_msg: String = ""
var _toast_timer: float = 0.0
var _coop_node: Node = null
var embedded_top_inset: float = 0.0
var embedded_bottom_inset: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layers()


func _build_layers() -> void:
	if _continent_rect != null:
		return
	_zone_mat.shader = SHADER_ZONE
	_continent_mat.shader = SHADER_CONTINENT
	_world_mat.shader = SHADER_WORLD

	_continent_rect = ColorRect.new()
	_continent_rect.name = "ContinentLayer"
	_continent_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_continent_rect.material = _continent_mat
	_continent_rect.visible = false
	add_child(_continent_rect)
	_continent_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_zone_rect = ColorRect.new()
	_zone_rect.name = "ZoneLayer"
	_zone_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_rect.material = _zone_mat
	add_child(_zone_rect)
	_zone_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_world_rect = ColorRect.new()
	_world_rect.name = "WorldLayer"
	_world_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_rect.material = _world_mat
	_world_rect.visible = false
	add_child(_world_rect)
	_world_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_overlay = Control.new()
	_overlay.name = "AtlasOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_book = AtlasBook.new()
	_book.name = "AtlasBook"
	_book.z_index = 10
	add_child(_book)
	_book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_book.place_selected.connect(func(wt: Vector2) -> void:
		_start_camera_tween(wt, maxf(_zoom_target, ZOOM_DEFAULT_ZONE), Vector2.ZERO, 0.45))
	_book.reward_claimed.connect(_on_book_reward_claimed)
	_book.state_changed.connect(func() -> void:
		if _overlay != null:
			_overlay.queue_redraw())

	var white_img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	white_img.fill(Color(0.5, 0.5, 0.5, 1.0))
	_fallback_white_tex = ImageTexture.create_from_image(white_img)
	var fog_img: Image = Image.create(4, 4, false, Image.FORMAT_R8)
	fog_img.fill(Color(1.0, 0.0, 0.0, 1.0))
	_fallback_fog_tex = ImageTexture.create_from_image(fog_img)


func _on_book_reward_claimed(_zid: StringName, tier: int, _reward_id: StringName) -> void:
	if tier == 30:
		for i: int in PIN_KIND_LIST.size():
			if (PIN_KIND_LIST[i]["id"] as StringName) == &"coast_wave":
				_pin_kind_idx = i
				break
	if _overlay != null:
		_overlay.queue_redraw()


# =========================================================================
# Public Interface Contract (SCOPE.md §4)
# =========================================================================

func setup(atlas: Atlas, discovery: MapDiscovery, markers: MapMarkers = null, director: Node = null) -> void:
	_build_layers()
	_atlas = atlas if atlas != null else Atlas.shared()
	_discovery = discovery
	_markers = markers
	_director = director
	if _director != null and _director.get("continent_id") != null:
		var cid: Variant = _director.get("continent_id")
		if cid is StringName and (cid as StringName) != &"":
			_continent_id = cid as StringName
	if not _atlas.continents.has(_continent_id) and not _atlas.continents.is_empty():
		_continent_id = _atlas.continents.keys()[0] as StringName
	var zones_list: Array[Atlas.Zone] = _atlas.zones_of(_continent_id)
	if not zones_list.is_empty():
		var default_z: Atlas.Zone = _atlas.zone(&"windkap")
		if default_z == null:
			default_z = zones_list[0]
		_active_zone_id = default_z.id
		_center_tile = default_z.center()
		_player_tile = _center_tile
		_player_zone = default_z.id
	if _book != null:
		_book.setup(_atlas, _discovery, _director, null)
		_book.set_zone(_active_zone_id)
	_try_bind_coop()
	_ensure_continent_textures(_continent_id)
	_update_level_state(false)


func begin_open(live_capture: Texture2D, player_tile: Vector2, player_zone: StringName, instant: bool = false, capture_center_override: Vector2 = Vector2.INF, capture_scale_override: float = -1.0) -> void:
	if _atlas == null:
		setup(Atlas.shared(), _discovery, _markers, _director)
	_try_bind_coop()
	_is_open = true
	_closing = false
	_close_elapsed = 0.0
	visible = true
	_velocity = Vector2.ZERO
	_dragging = false
	_slider_drag = false
	_tween_active = false
	_selected_peer_marker.clear()
	if _book != null:
		_book.close_book(true)
	_player_tile = player_tile
	if player_zone != &"":
		_player_zone = player_zone
		_active_zone_id = player_zone
	elif _atlas != null:
		var detected: StringName = _atlas.zone_at_tile(_continent_id, player_tile)
		if detected != &"":
			_player_zone = detected
			_active_zone_id = detected
	if _active_zone_id == &"" and _atlas != null:
		var zs: Array[Atlas.Zone] = _atlas.zones_of(_continent_id)
		if not zs.is_empty():
			_active_zone_id = zs[0].id
	if _book != null:
		_book.set_zone(_active_zone_id)
	var start_center: Vector2 = capture_center_override if capture_center_override.is_finite() else _player_tile
	var start_scale: float = capture_scale_override if capture_scale_override > 0.05 else MATCH_CUT_START_ZOOM
	_center_tile = _clamp_center(start_center if not instant else _player_tile)
	_live_capture = live_capture
	_capture_center = start_center
	_capture_scale = start_scale
	_anchor_screen = _view_size() * 0.5
	if instant:
		_open_t = 1.0
		_compass_spin_t = 1.0
		_match_cut_active = false
		_match_cut_zooming = false
		_match_cut_elapsed = MATCH_CUT_DISSOLVE_SEC + MATCH_CUT_ZOOM_SEC
		_zoom = ZOOM_DEFAULT_ZONE
		_zoom_target = ZOOM_DEFAULT_ZONE
	else:
		_open_t = 1.0 if live_capture != null else 0.0
		_compass_spin_t = 0.0
		_match_cut_elapsed = 0.0
		_match_cut_active = live_capture != null
		_match_cut_zooming = true
		_match_cut_start_zoom = start_scale
		_zoom = start_scale
		_zoom_target = start_scale if live_capture != null else ZOOM_DEFAULT_ZONE
	_ensure_zone_textures(_active_zone_id)
	if instant:
		var uargs: PackedStringArray = OS.get_cmdline_user_args()
		if uargs.has("--preview-silvercoast") and _book != null:
			_book.import_state({"claimed": {String(_active_zone_id): [30, 60]}, "stamps": ["coast_wave"], "frames": ["silvercoast_frame"], "frame_enabled": true})
			_pin_kind_idx = 4
			if _markers != null and _markers.has_method(&"add_pin"):
				_markers.call(&"add_pin", _active_zone_id, _player_tile + Vector2(-18.0, -14.0), &"coast_wave", "WELLENBUCHT")
		if uargs.has("--preview-book") and _book != null:
			if is_inside_tree() and get_tree().get_first_node_in_group("veil_threads") == null:
				var vt_prev: VeilThreads = VeilThreads.new()
				get_tree().root.add_child(vt_prev)
				var wk_t: Array[Dictionary] = vt_prev.entries_for_zone(_active_zone_id)
				var c_ids: Array[String] = []
				for ti: int in mini(wk_t.size(), 5):
					c_ids.append(String(wk_t[ti]["id"]))
				vt_prev.import_state({"collected": c_ids})
			_book.import_state({"claimed": {String(_active_zone_id): [30]}, "stamps": ["coast_wave"], "frames": [], "frame_enabled": true})
			_book.open_book(_active_zone_id)
			_book._open_t = 1.0
	_update_level_state(true)
	_push_shader_uniforms()
	if _overlay != null:
		_overlay.queue_redraw()


func begin_close(instant: bool = false, target_center_override: Vector2 = Vector2.INF, target_scale_override: float = -1.0) -> void:
	_dragging = false
	_slider_drag = false
	_tween_active = false
	_match_cut_active = false
	_match_cut_zooming = false
	_solemn_active = false
	_selected_peer_marker.clear()
	if _book != null:
		_book.close_book(true)
	if instant:
		_is_open = false
		_closing = false
		_close_elapsed = 0.0
		_open_t = 0.0
		visible = false
	else:
		_closing = true
		_is_open = false
		_close_elapsed = 0.0
		_close_start_zoom = _zoom
		_close_start_center = _center_tile
		_close_target_center = target_center_override if target_center_override.is_finite() else _player_tile
		_close_target_scale = target_scale_override if target_scale_override > 0.05 else MATCH_CUT_START_ZOOM


func is_closing() -> bool:
	return _closing


func is_match_cut_animating() -> bool:
	return _match_cut_active or _match_cut_zooming


func skip_match_cut_to_zone() -> void:
	if not _match_cut_active and not _match_cut_zooming:
		return
	_match_cut_active = false
	_match_cut_zooming = false
	_center_tile = _clamp_center(_player_tile)
	_zoom = ZOOM_DEFAULT_ZONE
	_zoom_target = ZOOM_DEFAULT_ZONE
	_open_t = 1.0
	_update_level_state(true)
	match_cut_finished.emit()


func interrupt_match_cut() -> void:
	if not _match_cut_active and not _match_cut_zooming:
		return
	_match_cut_active = false
	_match_cut_zooming = false
	_zoom_target = clampf(_zoom, _min_allowed_zoom(), ZOOM_MAX)
	match_cut_finished.emit()


func atlas_book() -> AtlasBook:
	_build_layers()
	return _book


func is_book_open() -> bool:
	return _book != null and _book.is_open()


func open_book(zone_id: StringName = &"") -> void:
	_build_layers()
	var target_z: StringName = zone_id if zone_id != &"" else _active_zone_id
	_book.open_book(target_z)


func toggle_book(zone_id: StringName = &"") -> void:
	_build_layers()
	var target_z: StringName = zone_id if zone_id != &"" else _active_zone_id
	_book.toggle_book(target_z)


func set_center_tile(tile_pos: Vector2) -> void:
	_tween_active = false
	_center_tile = _clamp_center(tile_pos)
	_refresh_active_zone_from_center()


func get_center_tile() -> Vector2:
	return _center_tile


func set_zoom(px_per_tile: float, focus_screen: Vector2 = Vector2.ZERO) -> void:
	interrupt_match_cut()
	_tween_active = false
	var target: float = clampf(px_per_tile, ZOOM_MIN, ZOOM_MAX)
	if not _continent_unlocked and target < ZOOM_CONTINENT_MAX:
		target = ZOOM_CONTINENT_MAX
		_trigger_unlock_limit()
	var anchor: Vector2 = _view_size() * 0.5 if focus_screen == Vector2.ZERO else focus_screen
	var before: float = maxf(_zoom, 0.001)
	_zoom = target
	_zoom_target = target
	if focus_screen != Vector2.ZERO:
		_center_tile += (anchor - _view_size() * 0.5) * (1.0 / before - 1.0 / maxf(_zoom, 0.001))
		_center_tile = _clamp_center(_center_tile)
	_update_level_state(true)


func get_zoom() -> float:
	return _zoom


func current_level() -> StringName:
	return _current_level


func jump_to_level(level: StringName, focus_screen: Vector2 = Vector2.ZERO, duration: float = 0.6) -> void:
	if (level == LEVEL_CONTINENT or level == LEVEL_WORLD) and not _continent_unlocked:
		_trigger_unlock_limit()
		return
	interrupt_match_cut()
	var dest_zoom: float = _default_zoom_for(level)
	var dest_center: Vector2 = _center_tile
	if level == LEVEL_WORLD or level == LEVEL_CONTINENT:
		var cont: Atlas.Continent = _atlas.continent(_continent_id) if _atlas != null else null
		if cont != null and level == LEVEL_WORLD:
			dest_center = _continent_overview_center()
		elif cont != null and level == LEVEL_CONTINENT and focus_screen == Vector2.ZERO:
			dest_center = _continent_overview_center()
	elif (level == LEVEL_ORT or level == LEVEL_ZONE) and _active_zone_id != &"" and _atlas != null:
		var az: Atlas.Zone = _atlas.zone(_active_zone_id)
		if az != null and not az.bbox.grow(60.0).has_point(_center_tile):
			dest_center = az.center()
	_start_camera_tween(dest_center, dest_zoom, focus_screen, duration)


func cycle_level(delta: int, focus_screen: Vector2 = Vector2.ZERO) -> void:
	var idx: int = LEVEL_ORDER.find(_current_level)
	if idx < 0:
		idx = 1
	var next_idx: int = clampi(idx + delta, 0, LEVEL_ORDER.size() - 1)
	var target: StringName = LEVEL_ORDER[next_idx]
	if (target == LEVEL_CONTINENT or target == LEVEL_WORLD) and not _continent_unlocked:
		_trigger_unlock_limit()
		return
	if target != _current_level:
		jump_to_level(target, focus_screen, 0.6)


func set_continent_unlocked(unlocked: bool, solemn_rollout: bool = false) -> void:
	_continent_unlocked = unlocked
	if not unlocked:
		_solemn_active = false
		_unlock_wave = 0.0
		if _zoom_target < ZOOM_CONTINENT_MAX:
			_zoom_target = ZOOM_CONTINENT_MAX
		if _zoom < ZOOM_CONTINENT_MAX:
			_zoom = ZOOM_CONTINENT_MAX
		_update_level_state(true)
	elif solemn_rollout:
		play_solemn_unlock_rollout()
	else:
		_solemn_active = false
		_unlock_wave = 1.0


func play_solemn_unlock_rollout() -> void:
	_continent_unlocked = true
	interrupt_match_cut()
	_solemn_active = true
	_solemn_t = 0.0
	_unlock_wave = 0.0
	var start_c: Vector2 = _player_tile
	if _active_zone_id != &"" and _atlas != null:
		var az: Atlas.Zone = _atlas.zone(_active_zone_id)
		if az != null:
			start_c = az.center()
	_center_tile = _clamp_center(start_c)
	_zoom = maxf(_zoom, ZOOM_DEFAULT_ZONE)
	_zoom_target = _zoom
	var dest_center: Vector2 = _continent_overview_center()
	_start_camera_tween(dest_center, ZOOM_DEFAULT_WORLD, Vector2.ZERO, SOLEMN_ROLLOUT_SEC)


func is_continent_unlocked() -> bool:
	return _continent_unlocked


func set_veil_progress(ratio: float) -> void:
	_veil_progress = clampf(ratio, 0.0, 1.0)


func set_preview_overrides(time_of_day: float = -1.0, weather: Dictionary = {}) -> void:
	_preview_time = time_of_day
	_preview_weather = weather.duplicate()
	if not _preview_weather.is_empty():
		_ensure_local_weather_field()


func set_preview_reveal_all(reveal_all: bool) -> void:
	_preview_reveal_all = reveal_all
	if _book != null:
		_book.set_preview_reveal_all(reveal_all)
	for z_val: Variant in _zone_textures.values():
		if z_val is Dictionary:
			(z_val as Dictionary).erase("fallback_fog")


func fly_to_zone_via_veil(zone_id: StringName, target_tile: Vector2, on_arrived: Callable = Callable()) -> void:
	_selected_peer_marker.clear()
	if _book != null:
		_book.close_book(true)
	_veil_fly_active = true
	_veil_fly_stage = 0
	_veil_fly_t = 0.0
	_veil_fly_start_tile = _center_tile
	_veil_fly_target_zone = zone_id
	_veil_fly_target_tile = target_tile
	_veil_fly_cb = on_arrived
	_tween_active = false
	interrupt_match_cut()


func trigger_ping_pulse(world_tile: Vector2, color: Color = Color(0.5, 0.9, 0.85)) -> void:
	_pings.append({
		"tile": world_tile,
		"color": color,
		"age": 0.0,
		"max_age": 3.5,
	})


func highlight_route_to_tile(to_zone: StringName, to_tile: Vector2, msg: String = "") -> void:
	_peer_route_pts.clear()
	if _atlas == null or _player_zone == &"":
		return
	var flags: Dictionary = _director_flags()
	var chain: Array[Atlas.Threshold] = _atlas.route(_player_zone, to_zone, flags, _player_tile)
	if chain.is_empty():
		# Fallback: compute geometric/topological route ignoring closed gates so the player sees which threshold leads there
		var open_all: Dictionary = flags.duplicate()
		for th_v: Variant in _atlas.thresholds.values():
			var th_obj: Atlas.Threshold = th_v as Atlas.Threshold
			if th_obj != null and not th_obj.open.is_empty():
				var flg: String = String(th_obj.open.get("flag", ""))
				if not flg.is_empty():
					open_all[flg] = true
		for z_obj: Atlas.Zone in _atlas.zones_of(_continent_id):
			if not z_obj.unlock.is_empty():
				var zflg: String = String(z_obj.unlock.get("flag", ""))
				if not zflg.is_empty():
					open_all[zflg] = true
		chain = _atlas.route(_player_zone, to_zone, open_all, _player_tile)
	var pts: PackedVector2Array = PackedVector2Array([_player_tile])
	for th_step: Atlas.Threshold in chain:
		pts.append(th_step.midpoint())
	pts.append(to_tile)
	_peer_route_pts = pts
	_peer_route_timer = 8.0
	if not msg.is_empty():
		_toast_msg = msg
		_toast_timer = 3.6


func _try_bind_coop() -> void:
	if _coop_node != null and is_instance_valid(_coop_node):
		return
	if not is_inside_tree():
		return
	var coop: Node = get_tree().get_first_node_in_group("zone_coop")
	if coop == null and _director != null:
		coop = _director.get_node_or_null("Coop")
	if coop == null:
		return
	_coop_node = coop
	if coop.has_signal(&"ping_received") and not coop.is_connected(&"ping_received", _on_coop_ping_received):
		coop.connect(&"ping_received", _on_coop_ping_received)


func _on_coop_ping_received(peer_id: int, world_pos: Vector2, _zone_id: StringName) -> void:
	var slot: int = 0
	if _coop_node != null and is_instance_valid(_coop_node) and _coop_node.has_method(&"peer_color_slot"):
		slot = int(_coop_node.call(&"peer_color_slot", peer_id))
	else:
		slot = NetworkManager.player_slot_for(peer_id)
	var tones: Array[Color] = MapMarkers.PLAYER_TONES
	var col: Color = tones[clampi(slot, 0, tones.size() - 1)]
	trigger_ping_pulse(Atlas.tile_of(world_pos), col)
	if visible and _is_open:
		Sfx.ui(self, "ui_click", -5.0)


func _emit_map_ping(world_tile: Vector2) -> void:
	_try_bind_coop()
	if _coop_node != null and is_instance_valid(_coop_node) and _coop_node.has_method(&"request_ping"):
		_coop_node.call(&"request_ping", Atlas.px_of(world_tile) + Vector2(8.0, 8.0))
	else:
		trigger_ping_pulse(world_tile, Color("78f4e6"))
		Sfx.ui(self, "ui_click", -4.0)


# =========================================================================
# Frame Update & Input
# =========================================================================

func _process(delta: float) -> void:
	if not visible and not _closing:
		return
	_try_bind_coop()
	_time += delta
	_limit_bump_t = maxf(_limit_bump_t - delta * 2.5, 0.0)
	_limit_emit_cd = maxf(_limit_emit_cd - delta, 0.0)
	_focused_locked_zone_t = maxf(_focused_locked_zone_t - delta, 0.0)
	_peer_route_timer = maxf(_peer_route_timer - delta, 0.0)
	_toast_timer = maxf(_toast_timer - delta, 0.0)
	_compass_spin_t = minf(_compass_spin_t + delta / 0.65, 1.0)
	_update_preview_lightning(delta)
	_update_open_close(delta)
	_update_match_cut(delta)
	_update_solemn_rollout(delta)
	_update_veil_fly(delta)
	_update_camera(delta)
	_update_pings(delta)
	_update_hover(delta)
	_push_shader_uniforms()
	if _overlay != null:
		_overlay.queue_redraw()


func _update_preview_lightning(delta: float) -> void:
	if _preview_weather.is_empty():
		return
	var storm: float = float(_preview_weather.get("storm", 0.0))
	if storm < 0.35:
		_preview_flash = 0.0
		return
	_preview_flash = maxf(_preview_flash - delta * 2.4, 0.0)
	_preview_flash_timer -= delta
	if _preview_flash_timer <= 0.0:
		_preview_flash_timer = randf_range(1.6, 4.2) / maxf(storm, 0.4)
		_preview_flash = 0.85 * storm
		_preview_flash_uv = Vector2(randf_range(0.15, 0.85), randf_range(0.2, 0.7))


func _update_open_close(delta: float) -> void:
	if _closing:
		_close_elapsed += delta
		var u: float = clampf(_close_elapsed / CLOSE_SECONDS, 0.0, 1.0)
		var zoom_e: float = u * u * (3.0 - 2.0 * u)
		_center_tile = _close_start_center.lerp(_close_target_center, zoom_e)
		_zoom = exp(lerpf(log(maxf(_close_start_zoom, 0.02)), log(maxf(_close_target_scale, 1.0)), zoom_e))
		_zoom_target = _zoom
		# Keep map crisp while rushing to 16 px/tile, then dissolve cleanly into live game world
		if u < 0.58:
			_open_t = lerpf(1.0, 0.88, u / 0.58)
		else:
			_open_t = lerpf(0.88, 0.0, (u - 0.58) / 0.42)
		_update_level_state(false)
		if u >= 1.0:
			_open_t = 0.0
			_closing = false
			visible = false
	elif _is_open and _open_t < 1.0:
		_open_t = minf(_open_t + delta / MATCH_CUT_DISSOLVE_SEC, 1.0)


func _update_match_cut(delta: float) -> void:
	if not _match_cut_active and not _match_cut_zooming:
		return
	_match_cut_elapsed += delta
	var dissolve_sec: float = MATCH_CUT_DISSOLVE_SEC if _live_capture != null else 0.0
	if _match_cut_active:
		if _match_cut_elapsed < dissolve_sec:
			_zoom = _match_cut_start_zoom
			_zoom_target = _match_cut_start_zoom
			return
		_match_cut_active = false
	if _match_cut_zooming:
		var zoom_elapsed: float = maxf(_match_cut_elapsed - dissolve_sec, 0.0)
		var u: float = clampf(zoom_elapsed / MATCH_CUT_ZOOM_SEC, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - u, 3.0)
		var log_start: float = log(maxf(_match_cut_start_zoom, 0.1))
		var log_end: float = log(ZOOM_DEFAULT_ZONE)
		_zoom = exp(lerpf(log_start, log_end, eased))
		_zoom_target = _zoom
		_update_level_state(true)
		if u >= 1.0:
			_match_cut_zooming = false
			_match_cut_active = false
			_zoom = ZOOM_DEFAULT_ZONE
			_zoom_target = ZOOM_DEFAULT_ZONE
			_update_level_state(true)
			match_cut_finished.emit()


func _update_solemn_rollout(delta: float) -> void:
	if not _solemn_active:
		return
	_solemn_t = minf(_solemn_t + delta / SOLEMN_ROLLOUT_SEC, 1.0)
	_unlock_wave = smoothstep(0.05, 0.85, _solemn_t)
	if _solemn_t >= 1.0:
		_solemn_active = false
		_unlock_wave = 1.0


func _update_veil_fly(delta: float) -> void:
	if not _veil_fly_active:
		return
	_veil_fly_t += delta
	if _veil_fly_stage == 0:
		var u: float = clampf(_veil_fly_t / 0.45, 0.0, 1.0)
		var e: float = u * u * (3.0 - 2.0 * u)
		_zoom = exp(lerpf(log(maxf(_zoom, 0.05)), log(0.06 if _continent_unlocked else 0.6), e))
		_zoom_target = _zoom
		if u >= 1.0:
			_veil_fly_stage = 1
			_veil_fly_t = 0.0
	elif _veil_fly_stage == 1:
		var u: float = clampf(_veil_fly_t / 0.70, 0.0, 1.0)
		var e: float = u * u * (3.0 - 2.0 * u)
		_center_tile = _veil_fly_start_tile.lerp(_veil_fly_target_tile, e)
		if u >= 1.0:
			_veil_fly_stage = 2
			_veil_fly_t = 0.0
			if _veil_fly_target_zone != &"":
				_active_zone_id = _veil_fly_target_zone
				_ensure_zone_textures(_active_zone_id)
	else:
		var u: float = clampf(_veil_fly_t / 0.50, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - u, 3.0)
		var start_z: float = 0.06 if _continent_unlocked else 0.6
		_zoom = exp(lerpf(log(start_z), log(ZOOM_DEFAULT_ZONE), e))
		_zoom_target = _zoom
		if u >= 1.0:
			_veil_fly_active = false
			_update_level_state(true)
			if _veil_fly_cb.is_valid():
				_veil_fly_cb.call()


func _update_camera(delta: float) -> void:
	if _tween_active:
		_tween_elapsed += delta
		var u: float = clampf(_tween_elapsed / maxf(_tween_duration, 0.01), 0.0, 1.0)
		var e: float = u * u * (3.0 - 2.0 * u)
		_zoom = exp(lerpf(log(maxf(_tween_start_zoom, 0.005)), log(maxf(_tween_end_zoom, 0.005)), e))
		_zoom_target = _zoom
		var base_c: Vector2 = _tween_start_center.lerp(_tween_end_center, e)
		if _tween_focus != Vector2.ZERO:
			var anchor_off: Vector2 = (_tween_focus - _view_size() * 0.5) * (1.0 / maxf(_tween_start_zoom, 0.001) - 1.0 / maxf(_zoom, 0.001))
			base_c += anchor_off
		_center_tile = _clamp_center(base_c)
		if u >= 1.0:
			_tween_active = false
		_update_level_state(true)
		return

	if not _is_open or _match_cut_zooming or _veil_fly_active or is_book_open():
		return

	# Keyboard / Stick pan
	var pan: Vector2 = InputManager.map_pan_vector()
	if pan.length_squared() > 0.001:
		_center_tile += pan * (PAN_SPEED / maxf(_zoom, 0.02)) * delta
		_velocity = Vector2.ZERO
	elif not _dragging and _velocity.length_squared() > 0.01:
		_center_tile += _velocity * delta
		_velocity *= exp(-5.0 * delta)
	_center_tile = _clamp_center(_center_tile)

	# Continuous Q/E zoom
	var zoom_step: int = InputManager.map_zoom_step()
	if zoom_step != 0:
		_apply_zoom_step(zoom_step, _view_size() * 0.5)
	elif Input.is_action_pressed("map_zoom_in"):
		_apply_zoom_factor(pow(WHEEL_STEP, delta * 3.0), _view_size() * 0.5)
	elif Input.is_action_pressed("map_zoom_out"):
		_apply_zoom_factor(pow(1.0 / WHEEL_STEP, delta * 3.0), _view_size() * 0.5)

	if InputManager.map_center_pressed():
		_start_camera_tween(_player_tile, _zoom_target, Vector2.ZERO, 0.4)

	# Smooth exponential zoom toward _anchor_screen
	if absf(_zoom - _zoom_target) > 0.0005:
		var before: float = maxf(_zoom, 0.001)
		_zoom = lerpf(_zoom, _zoom_target, 1.0 - exp(-14.0 * delta))
		_center_tile += (_anchor_screen - _view_size() * 0.5) * (1.0 / before - 1.0 / maxf(_zoom, 0.001))
		_center_tile = _clamp_center(_center_tile)
		_update_level_state(true)
	else:
		_zoom = _zoom_target
		_update_level_state(true)

	_refresh_active_zone_from_center()


func _update_pings(delta: float) -> void:
	for i: int in range(_pings.size() - 1, -1, -1):
		var p: Dictionary = _pings[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["max_age"]):
			_pings.remove_at(i)


func _update_hover(delta: float) -> void:
	if _current_level == LEVEL_CONTINENT and _zoom >= 0.12 and not _dragging and not _slider_drag and _atlas != null:
		var tile: Vector2 = _tile_at(_cursor)
		var zid: StringName = _atlas.zone_at_tile(_continent_id, tile)
		if zid != _hovered_zone_id:
			_hovered_zone_id = zid
			_hover_zone_t = 0.0
			if zid != &"":
				_hover_zone_card = _build_zone_card_data(zid)
				zone_hovered.emit(zid, _hover_zone_card)
			else:
				_hover_zone_card = {}
		elif zid != &"":
			_hover_zone_t = minf(_hover_zone_t + delta / 0.16, 1.0)
	else:
		_hovered_zone_id = &""
		_hover_zone_t = 0.0
		_hover_zone_card = {}


func _gui_input(event: InputEvent) -> void:
	if not _is_open or _closing or is_book_open():
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_cursor = mm.position
		if _slider_drag:
			_set_zoom_from_slider(_cursor.y)
			accept_event()
			return
		if _dragging:
			interrupt_match_cut()
			_tween_active = false
			var dt_tile: Vector2 = -mm.relative / maxf(_zoom, 0.02)
			_center_tile = _clamp_center(_center_tile + dt_tile)
			_velocity = dt_tile / maxf(get_process_delta_time(), 0.008)
			_refresh_active_zone_from_center()
			accept_event()
			return
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		_cursor = mb.position
		if mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			_emit_map_ping(_tile_at(mb.position))
			accept_event()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			interrupt_match_cut()
			_tween_active = false
			_apply_zoom_step(1, mb.position)
			accept_event()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			interrupt_match_cut()
			_tween_active = false
			_apply_zoom_step(-1, mb.position)
			accept_event()
			return
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click and _current_level == LEVEL_CONTINENT and _hovered_zone_id != &"":
					zone_double_clicked.emit(_hovered_zone_id)
					_enter_zone_from_continent(_hovered_zone_id)
					accept_event()
					return
				if _handle_left_click(mb.position):
					accept_event()
					return
				var zb: Vector3 = _zoom_rail_bounds()
				if absf(mb.position.x - zb.x) < 12.0 and mb.position.y >= zb.y - 12.0 and mb.position.y <= zb.z + 12.0:
					_slider_drag = true
					interrupt_match_cut()
					_set_zoom_from_slider(mb.position.y)
					accept_event()
					return
				_dragging = true
				_last_drag_pos = mb.position
				_velocity = Vector2.ZERO
				accept_event()
			else:
				_dragging = false
				_slider_drag = false
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click(mb.position)
			accept_event()
			return


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or _closing or not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if is_book_open():
		if event.is_action_pressed("ui_cancel"):
			_book.close_book(false)
			get_viewport().set_input_as_handled()
			return
		if key != null and key.pressed and not key.echo and (key.keycode == KEY_B or key.keycode == KEY_C):
			_book.close_book(false)
			get_viewport().set_input_as_handled()
			return
		return
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_B or key.keycode == KEY_C:
			if embedded_top_inset > 0.0:
				open_chronicle_requested.emit(_active_zone_id)
			else:
				toggle_book(_active_zone_id)
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_TAB:
			cycle_level(-1 if key.shift_pressed else 1, _view_size() * 0.5)
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_F:
			_filter_open = not _filter_open
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_SPACE:
			_recenter_on_player()
			get_viewport().set_input_as_handled()


func _unlocked_pin_count() -> int:
	return 5 if (_book != null and _book.has_stamp_unlocked()) else 4


func _handle_left_click(pos: Vector2) -> bool:
	# 0a. Top exploration flower / Feldcodex Chronicle pill -> unified WELT->CHRONIK when embedded, else modal AtlasBook
	if _flower_hit_rect.size.x > 0.0 and _flower_hit_rect.grow(4.0).has_point(pos):
		if embedded_top_inset > 0.0:
			open_chronicle_requested.emit(_active_zone_id)
		else:
			toggle_book(_active_zone_id)
		return true
	# 0a2. Home Recenter Crystal -> glide back to player
	if _home_btn_rect.size.x > 0.0 and _home_btn_rect.grow(3.0).has_point(pos):
		_recenter_on_player()
		return true
	# 0b. "ZU IHM" teammate popup button
	if not _selected_peer_marker.is_empty() and _peer_join_rect.size.x > 0.0 and _peer_join_rect.grow(3.0).has_point(pos):
		_activate_selected_peer_join()
		return true
	# 0c. Pin kind palette strip
	for slot_item: Dictionary in _pin_slot_rects:
		var sr: Rect2 = slot_item["rect"] as Rect2
		if sr.grow(2.0).has_point(pos):
			_pin_kind_idx = clampi(int(slot_item["idx"]), 0, _unlocked_pin_count() - 1)
			Sfx.ui(self, "ui_move", -6.0)
			return true
	# 1. Left-edge level tags
	for lvl: StringName in _level_tag_rects:
		var r: Rect2 = _level_tag_rects[lvl] as Rect2
		if r.grow(2.0).has_point(pos):
			jump_to_level(lvl, Vector2.ZERO, 0.6)
			return true
	# 2. Bottom filter branch toggle & categories
	if _filter_branch_rect.grow(3.0).has_point(pos):
		_filter_open = not _filter_open
		return true
	if _filter_open:
		for item: Dictionary in _filter_hit_rects:
			var r: Rect2 = item["rect"] as Rect2
			if r.grow(2.0).has_point(pos):
				_toggle_filter_cat(item["id"] as StringName)
				return true
	# 3. Right-edge place list
	for item: Dictionary in _place_hit_rects:
		var r: Rect2 = item["rect"] as Rect2
		if r.grow(2.0).has_point(pos):
			if bool(item["seen"]):
				var p_tile: Vector2 = item["pos"] as Vector2
				_start_camera_tween(p_tile, maxf(_zoom_target, ZOOM_DEFAULT_ZONE), Vector2.ZERO, 0.45)
			return true
	# 4. Interactive markers (Waystones, Teammates, Quests, Pins)
	for item: Dictionary in _marker_hit_rects:
		var r: Rect2 = item["rect"] as Rect2
		if r.grow(3.0).has_point(pos):
			var clicked_m: Dictionary = item["marker"] as Dictionary
			marker_clicked.emit(clicked_m)
			var m_kind: StringName = StringName(clicked_m.get("kind", &""))
			var m_data: Dictionary = clicked_m.get("data", {}) as Dictionary if clicked_m.get("data") is Dictionary else {}
			if m_kind == &"waystone":
				var wid: String = String(m_data.get("waystone_id", String(clicked_m.get("id", "")).trim_prefix("waystone_")))
				var wz: StringName = StringName(String(clicked_m.get("zone", "")))
				var m_pos: Vector2 = clicked_m.get("pos", _center_tile) as Vector2
				if wz == &"" and _atlas != null:
					wz = _atlas.zone_at_tile(_continent_id, m_pos)
				_selected_peer_marker.clear()
				waystone_travel_requested.emit(wid, wz, m_pos)
				return true
			elif m_kind == &"waystone_sleeping":
				_toast_msg = "WEGSTEIN NOCH NICHT ERWECKT"
				_toast_timer = 2.4
				Sfx.ui(self, "ui_cancel", -5.0)
				return true
			elif m_kind == &"player":
				_selected_peer_marker = clicked_m.duplicate(true)
				Sfx.ui(self, "ui_click", -5.0)
				return true
			_selected_peer_marker.clear()
			return true
	_selected_peer_marker.clear()
	return false


func _activate_selected_peer_join() -> void:
	if _selected_peer_marker.is_empty():
		return
	var m_data: Dictionary = _selected_peer_marker.get("data", {}) as Dictionary if _selected_peer_marker.get("data") is Dictionary else {}
	var peer_id: int = int(m_data.get("peer_id", -1))
	var peer_pos: Vector2 = _selected_peer_marker.get("pos", _center_tile) as Vector2
	var target_zone: StringName = StringName(String(_selected_peer_marker.get("zone", "")))
	if target_zone == &"" and _atlas != null:
		target_zone = _atlas.zone_at_tile(_continent_id, peer_pos)
	_try_bind_coop()
	if _coop_node != null and is_instance_valid(_coop_node) and _coop_node.has_method(&"can_join_peer"):
		var check_v: Variant = _coop_node.call(&"can_join_peer", peer_id)
		if check_v is Dictionary and bool((check_v as Dictionary).get("ok", false)):
			var cd: Dictionary = check_v as Dictionary
			var cz: StringName = StringName(String(cd.get("zone_id", target_zone)))
			var cws: String = String(cd.get("waystone_id", ""))
			var arr_v: Variant = cd.get("arrival_pos", Vector2.INF)
			var dest_tile: Vector2 = Atlas.tile_of(arr_v as Vector2) if (arr_v is Vector2 and (arr_v as Vector2).is_finite()) else peer_pos
			_selected_peer_marker.clear()
			join_peer_requested.emit(peer_id, cz, cws, dest_tile)
			return
	var wm: Waystones = Waystones.of(get_tree()) if is_inside_tree() else null
	if wm != null and target_zone != &"":
		var ws_spec: Dictionary = wm.awake_waystone_in_zone(target_zone)
		if not ws_spec.is_empty():
			var wid: String = String(ws_spec.get("id", ""))
			var t_arr: Array = ws_spec.get("tile", []) as Array
			var ws_tile: Vector2 = Vector2(float(t_arr[0]), float(t_arr[1])) if t_arr.size() >= 2 else peer_pos
			_selected_peer_marker.clear()
			join_peer_requested.emit(peer_id, target_zone, wid, ws_tile)
			return
	_selected_peer_marker.clear()
	if target_zone == _player_zone and target_zone != &"":
		_peer_route_pts = PackedVector2Array([_player_tile, peer_pos])
		_peer_route_timer = 8.0
		_toast_msg = "WEGSTEIN RUHT NOCH - PFAD ZU MITSPIELER MARKIERT"
		_toast_timer = 3.4
	else:
		highlight_route_to_tile(target_zone, peer_pos, "WEGSTEIN DORT NOCH SCHLAFEND - ROUTE MARKIERT")
	_start_camera_tween((_player_tile + peer_pos) * 0.5, minf(_zoom_target, ZOOM_DEFAULT_ZONE), Vector2.ZERO, 0.45)
	Sfx.ui(self, "ui_click", -4.0)


func _handle_right_click(pos: Vector2) -> void:
	var tile: Vector2 = _tile_at(pos)
	var zid: StringName = _atlas.zone_at_tile(_continent_id, tile) if _atlas != null else _active_zone_id
	if zid == &"":
		zid = _active_zone_id
	if zid == &"":
		return
	_pin_kind_idx = clampi(_pin_kind_idx, 0, _unlocked_pin_count() - 1)
	var max_dist_tiles: float = maxf(8.0 / maxf(_zoom, 0.05), 4.0)
	if _markers != null and _markers.has_method(&"remove_nearest_pin") and _markers.has_method(&"add_pin"):
		var removed: bool = bool(_markers.call(&"remove_nearest_pin", zid, tile, max_dist_tiles))
		if not removed:
			var pk: StringName = PIN_KIND_LIST[_pin_kind_idx]["id"] as StringName
			_markers.call(&"add_pin", zid, tile, pk, "")
		Sfx.ui(self, "ui_click", -5.0)
	else:
		var list: Array = _local_pins.get(zid, []) as Array
		var removed: bool = false
		for i: int in range(list.size() - 1, -1, -1):
			var pin: Dictionary = list[i] as Dictionary
			if (pin["pos"] as Vector2).distance_to(tile) <= max_dist_tiles:
				list.remove_at(i)
				removed = true
				break
		if not removed:
			var pk: StringName = PIN_KIND_LIST[_pin_kind_idx]["id"] as StringName
			list.append({"pos": tile, "kind": pk, "zone": zid, "born": _time})
			_local_pins[zid] = list
		Sfx.ui(self, "ui_click", -5.0)


func _enter_zone_from_continent(zone_id: StringName) -> void:
	var z: Atlas.Zone = _atlas.zone(zone_id) if _atlas != null else null
	if z == null:
		return
	var st: int = _zone_status_int(zone_id)
	_active_zone_id = zone_id
	_ensure_zone_textures(zone_id)
	var dest_z: float = ZOOM_DEFAULT_ZONE if st >= 2 else 1.25
	_start_camera_tween(z.center(), dest_z, Vector2.ZERO, 0.58)
	if st < 2:
		var old_lbl: String = String(z.raw.get("old_name", z.name)).to_upper()
		_toast_msg = "%s · STEINSETZER-GRAVUR" % old_lbl
		_toast_timer = 2.6


# =========================================================================
# Zoom, Bounds & Coordinate Helpers
# =========================================================================

func _view_size() -> Vector2:
	return size if size.x > 16.0 and size.y > 16.0 else Vector2(640.0, 360.0)


func _min_allowed_zoom() -> float:
	return ZOOM_MIN if _continent_unlocked else ZOOM_CONTINENT_MAX


func _is_center_on_entered_zone() -> bool:
	if not _continent_unlocked or _preview_reveal_all:
		return true
	if _atlas == null:
		return true
	var zid: StringName = _atlas.zone_at_tile(_continent_id, _center_tile)
	if zid == &"":
		return false
	return _zone_status_int(zid) >= 2


func _max_allowed_zoom() -> float:
	return ZOOM_MAX if _is_center_on_entered_zone() else ZOOM_UNCHARTED_MAX


func _continent_land_bounds() -> Rect2:
	if _atlas == null:
		return Rect2(400.0, 230.0, 1600.0, 1340.0)
	var cont: Atlas.Continent = _atlas.continent(_continent_id)
	var zs: Array[Atlas.Zone] = _atlas.zones_of(_continent_id)
	if zs.is_empty():
		var csz: Vector2 = Vector2(cont.size) if cont != null else Vector2(2400.0, 1800.0)
		return Rect2(csz * 0.16, csz * 0.68)
	var rect: Rect2 = zs[0].bbox
	for i: int in range(1, zs.size()):
		rect = rect.merge(zs[i].bbox)
	return rect


func _continent_overview_center() -> Vector2:
	var cont: Atlas.Continent = _atlas.continent(_continent_id) if _atlas != null else null
	var zs: Array[Atlas.Zone] = _atlas.zones_of(_continent_id) if _atlas != null else ([] as Array[Atlas.Zone])
	if zs.size() >= 3:
		return _continent_land_bounds().get_center()
	if cont != null:
		return Vector2(cont.size) * 0.5
	return Vector2(1200.0, 900.0)


func _continent_overview_zoom() -> float:
	var zs: Array[Atlas.Zone] = _atlas.zones_of(_continent_id) if _atlas != null else ([] as Array[Atlas.Zone])
	if zs.size() < 3:
		return ZOOM_DEFAULT_CONTINENT
	var land: Rect2 = _continent_land_bounds()
	var vs: Vector2 = _view_size()
	var fit_x: float = (vs.x - 148.0) / maxf(land.size.x, 200.0)
	var fit_y: float = (vs.y - 62.0) / maxf(land.size.y, 200.0)
	return clampf(minf(fit_x, fit_y), 0.16, 0.28)


func _default_zoom_for(level: StringName) -> float:
	match level:
		LEVEL_ORT: return ZOOM_DEFAULT_ORT
		LEVEL_ZONE: return ZOOM_DEFAULT_ZONE
		LEVEL_CONTINENT: return _continent_overview_zoom()
		LEVEL_WORLD: return ZOOM_DEFAULT_WORLD
	return ZOOM_DEFAULT_ZONE


func _level_for_zoom(px_per_tile: float) -> StringName:
	if px_per_tile >= ZOOM_ZONE_MAX:
		return LEVEL_ORT
	if px_per_tile >= ZOOM_CONTINENT_MAX:
		return LEVEL_ZONE
	if px_per_tile >= ZOOM_WORLD_MAX:
		return LEVEL_CONTINENT
	return LEVEL_WORLD


func _update_level_state(emit_signal: bool) -> void:
	var next_lvl: StringName = _level_for_zoom(_zoom)
	if not _continent_unlocked and (next_lvl == LEVEL_CONTINENT or next_lvl == LEVEL_WORLD):
		next_lvl = LEVEL_ZONE
	if next_lvl != _current_level:
		_current_level = next_lvl
		if emit_signal:
			level_changed.emit(_current_level)


func _apply_zoom_step(step: int, anchor: Vector2) -> void:
	var factor: float = WHEEL_STEP if step > 0 else 1.0 / WHEEL_STEP
	_apply_zoom_factor(factor, anchor)


func _apply_zoom_factor(factor: float, anchor: Vector2) -> void:
	_anchor_screen = anchor
	var next_z: float = _zoom_target * factor
	if not _continent_unlocked and next_z < ZOOM_CONTINENT_MAX:
		_zoom_target = ZOOM_CONTINENT_MAX
		_zoom = maxf(_zoom, ZOOM_CONTINENT_MAX - 0.03)
		_trigger_unlock_limit()
		return
	var max_z: float = _max_allowed_zoom()
	if factor > 1.0 and next_z > max_z and max_z < ZOOM_MAX:
		_zoom_target = max_z
		if _toast_timer <= 0.1:
			_toast_msg = "GEBIET NOCH UNERKUNDET · STEINSETZER-GRAVUR"
			_toast_timer = 2.0
		return
	_zoom_target = clampf(next_z, _min_allowed_zoom(), max_z)


func _trigger_unlock_limit() -> void:
	_limit_bump_t = 1.0
	if _limit_emit_cd <= 0.0:
		_limit_emit_cd = 0.45
		unlock_limit_hit.emit()


func _zoom_rail_bounds() -> Vector3:
	if embedded_top_inset > 0.0:
		var vs: Vector2 = _view_size()
		return Vector3(vs.x - 19.0, 184.0, vs.y - embedded_bottom_inset - 26.0)
	return Vector3(ZOOM_X, ZOOM_TOP, ZOOM_BOTTOM)


func _recenter_on_player() -> void:
	interrupt_match_cut()
	var dest_z: float = maxf(_zoom_target, ZOOM_DEFAULT_ZONE)
	_start_camera_tween(_player_tile, dest_z, Vector2.ZERO, 0.45)
	Sfx.ui(self, "ui_click", -5.0)


func _set_zoom_from_slider(screen_y: float) -> void:
	var zb: Vector3 = _zoom_rail_bounds()
	var u: float = clampf((zb.z - screen_y) / maxf(zb.z - zb.y, 1.0), 0.0, 1.0)
	var min_z: float = _min_allowed_zoom()
	var max_z: float = _max_allowed_zoom()
	var next_z: float = exp(lerpf(log(min_z), log(max_z), u))
	_anchor_screen = _view_size() * 0.5
	_zoom_target = next_z
	_zoom = next_z
	_update_level_state(true)


func _zoom_u() -> float:
	var min_z: float = _min_allowed_zoom()
	var max_z: float = _max_allowed_zoom()
	return clampf((log(maxf(_zoom_target, min_z)) - log(min_z)) / maxf(log(max_z) - log(min_z), 0.01), 0.0, 1.0)


func _start_camera_tween(dest_center: Vector2, dest_zoom: float, focus_screen: Vector2, duration: float) -> void:
	var clamped_zoom: float = clampf(dest_zoom, _min_allowed_zoom(), ZOOM_MAX)
	if duration <= 0.01:
		_tween_active = false
		var adj_center: Vector2 = dest_center
		if focus_screen != Vector2.ZERO:
			adj_center += (focus_screen - _view_size() * 0.5) * (1.0 / maxf(_zoom, 0.001) - 1.0 / maxf(clamped_zoom, 0.001))
		_center_tile = _clamp_center(adj_center)
		_zoom = clamped_zoom
		_zoom_target = clamped_zoom
		_update_level_state(true)
		return
	_tween_active = true
	_tween_elapsed = 0.0
	_tween_duration = duration
	_tween_start_center = _center_tile
	_tween_end_center = _clamp_center(dest_center)
	_tween_start_zoom = _zoom
	_tween_end_zoom = clamped_zoom
	_tween_focus = focus_screen


func _clamp_center(tile: Vector2) -> Vector2:
	if _atlas == null:
		return tile
	var cont: Atlas.Continent = _atlas.continent(_continent_id)
	if cont == null:
		return tile
	var pad: float = 240.0 if _zoom >= ZOOM_CONTINENT_MAX else 900.0
	return Vector2(
		clampf(tile.x, -pad, float(cont.size.x) + pad),
		clampf(tile.y, -pad, float(cont.size.y) + pad)
	)


func _to_screen(tile: Vector2) -> Vector2:
	return (tile - _center_tile) * _zoom + _view_size() * 0.5


func _tile_at(screen_pos: Vector2) -> Vector2:
	return _center_tile + (screen_pos - _view_size() * 0.5) / maxf(_zoom, 0.001)


func _refresh_active_zone_from_center() -> void:
	if _atlas == null:
		return
	var zid: StringName = _atlas.zone_at_tile(_continent_id, _center_tile)
	if zid != &"" and zid != _active_zone_id:
		_active_zone_id = zid
		_ensure_zone_textures(_active_zone_id)


func _resolve_render_zone_id() -> StringName:
	if _atlas == null:
		return _active_zone_id
	if _active_zone_id != &"" and _zone_status_int(_active_zone_id) >= 2:
		return _active_zone_id
	if _continent_unlocked and _zoom >= 0.42:
		var vs: Vector2 = _view_size()
		var half_t: Vector2 = vs / maxf(_zoom * 2.0, 0.02)
		var view_tiles: Rect2 = Rect2(_center_tile - half_t, half_t * 2.0).grow(12.0)
		var best_entered: StringName = &""
		var best_dist: float = INF
		for z: Atlas.Zone in _atlas.zones_of(_continent_id):
			if _zone_status_int(z.id) < 2:
				continue
			if z.bbox.intersects(view_tiles):
				var d: float = z.center().distance_squared_to(_center_tile)
				if z.id == _player_zone:
					d *= 0.25
				if d < best_dist:
					best_dist = d
					best_entered = z.id
		if best_entered != &"":
			return best_entered
	return _active_zone_id


# =========================================================================
# Shader Parameter Synchronization (Live Singletons + Preview Overrides)
# =========================================================================

func _push_shader_uniforms() -> void:
	var vs: Vector2 = _view_size()
	var tod: float = _preview_time if _preview_time >= 0.0 else TimeManager.time_of_day
	var night_amt: float = TimeManager.night_at(tod)
	var golden_amt: float = TimeManager.golden_at(tod)
	var sun_amt: float = TimeManager.sun_at(tod)
	var sun_dir: Vector2 = SunShadows.sun_cast(tod)
	if _preview_time < 0.0 and SunShadows.current != null and is_instance_valid(SunShadows.current):
		sun_dir = SunShadows.current.cast

	# Weather state
	var cloud_cov: float = 0.25
	var rain_amt: float = 0.0
	var storm_amt: float = 0.0
	var wind_spd: float = 0.25
	var wind_ang: float = 0.26
	var flash_amt: float = 0.0
	var flash_uv: Vector2 = Vector2(0.5, 0.5)
	var flash_col: Color = Color(0.80, 0.84, 1.0)
	var cloud_tex_val: Texture2D = null
	var has_cloud_tex: bool = false
	var cloud_drift: Vector2 = Vector2(_time * 14.0, _time * 4.0)
	var cloud_thresh: float = 2.0
	var cloud_bonus: float = 0.0
	var cloud_shadow: float = 0.74

	if not _preview_weather.is_empty():
		cloud_cov = float(_preview_weather.get("cloud", 0.25))
		rain_amt = float(_preview_weather.get("rain", 0.0))
		storm_amt = float(_preview_weather.get("storm", 0.0))
		wind_spd = float(_preview_weather.get("wind", 0.25))
		wind_ang = float(_preview_weather.get("dir", 0.26))
		flash_amt = _preview_flash
		flash_uv = _preview_flash_uv
		if _local_weather_field != null and _local_weather_field.ready_now and _local_weather_field.texture != null:
			cloud_tex_val = _local_weather_field.texture
			has_cloud_tex = true
			cloud_thresh = _local_weather_field.threshold(cloud_cov)
		else:
			cloud_thresh = lerpf(0.95, 0.10, clampf(cloud_cov, 0.0, 1.0)) if cloud_cov > 0.02 else 2.0
		cloud_bonus = maxf(cloud_cov - 0.75, 0.0) * 1.4
	elif WeatherManager.current != null and is_instance_valid(WeatherManager.current):
		var wm: Node = WeatherManager.current
		cloud_cov = float(wm.get("cloud"))
		rain_amt = float(wm.get("rain"))
		storm_amt = float(wm.get("storm"))
		wind_spd = float(wm.get("wind"))
		wind_ang = float(wm.get("dir"))
		flash_amt = float(wm.get("flash"))
		var wf: WeatherField = wm.get("field") as WeatherField
		if wf != null and wf.ready_now and wf.texture != null:
			cloud_tex_val = wf.texture
			has_cloud_tex = true
			cloud_drift = wf.drift
			cloud_thresh = wf.thresh
			cloud_bonus = wf.bonus
		var fi: Dictionary = wm.get("flash_info") as Dictionary
		if not fi.is_empty():
			flash_uv = Vector2(float(fi.get("x", 0.5)), float(fi.get("y", 0.5)))
			var fc: Variant = fi.get("color")
			if fc is Color:
				flash_col = fc as Color
	else:
		cloud_thresh = 0.58

	var wind_vec: Vector2 = Vector2.from_angle(wind_ang)
	var wind_clock: float = _time * (0.8 + wind_spd * 2.2)

	# Determine active layers & top-pass frame ownership
	var cont_blend: float = 0.0
	var int_blend: float = 0.0
	var show_continent: bool = false
	var show_zone: bool = true
	var show_world: bool = false
	var cloud_fly: float = 0.0
	var world_alpha: float = 0.0

	if _continent_unlocked:
		if _zoom < 0.72:
			show_continent = true
			cont_blend = clampf((0.72 - _zoom) / 0.24, 0.0, 1.0)
			int_blend = clampf((0.56 - _zoom) / 0.14, 0.0, 1.0)
		if _zoom < 0.42:
			show_zone = false
		if _zoom < 0.14:
			show_world = true
			var fly_peak: float = 1.0 - absf((_zoom - 0.090) / 0.028)
			cloud_fly = clampf(fly_peak, 0.0, 1.0)
			if _zoom <= 0.08:
				world_alpha = 1.0
				show_continent = false
			else:
				world_alpha = clampf((0.10 - _zoom) / 0.02, 0.0, 1.0)
	if _veil_fly_active and _veil_fly_stage == 1:
		cloud_fly = maxf(cloud_fly, 0.85)

	_continent_rect.visible = show_continent
	_zone_rect.visible = show_zone
	_world_rect.visible = show_world

	# Determine single topmost visible layer for veil_frame & veil_opening
	var top_layer: StringName = &"world" if show_world else (&"continent" if show_continent else &"zone")
	var zone_frame: float = 1.0 if top_layer == &"zone" else 0.0
	var cont_frame: float = 1.0 if top_layer == &"continent" else 0.0
	var world_frame: float = 1.0 if top_layer == &"world" else 0.0
	var zone_open: float = _open_t if top_layer == &"zone" else 1.0
	var cont_open: float = _open_t if top_layer == &"continent" else 1.0
	var world_open: float = _open_t if top_layer == &"world" else 1.0

	var focus_px: Vector2 = _to_screen(_player_tile).clamp(Vector2.ZERO, vs)

	for mat: ShaderMaterial in [_zone_mat, _continent_mat, _world_mat]:
		mat.set_shader_parameter("view_size", vs)
		mat.set_shader_parameter("center", _center_tile)
		mat.set_shader_parameter("map_scale", _zoom)
		mat.set_shader_parameter("time", _time)
		mat.set_shader_parameter("night", night_amt)
		mat.set_shader_parameter("golden", golden_amt)
		mat.set_shader_parameter("sun_strength", sun_amt)
		mat.set_shader_parameter("sun_cast_dir", sun_dir)
		mat.set_shader_parameter("has_cloud_tex", has_cloud_tex)
		if has_cloud_tex:
			mat.set_shader_parameter("cloud_tex", cloud_tex_val)
		mat.set_shader_parameter("cloud_drift", cloud_drift)
		mat.set_shader_parameter("cloud_thresh", cloud_thresh)
		mat.set_shader_parameter("cloud_bonus", cloud_bonus)
		mat.set_shader_parameter("cloud_shadow", cloud_shadow)
		mat.set_shader_parameter("rain_rate", rain_amt)
		mat.set_shader_parameter("storm_rate", storm_amt)
		mat.set_shader_parameter("flash_amt", flash_amt)
		mat.set_shader_parameter("flash_col", Vector3(flash_col.r, flash_col.g, flash_col.b))
		mat.set_shader_parameter("flash_uv", flash_uv)
		mat.set_shader_parameter("wind_dir", wind_vec)
		mat.set_shader_parameter("wind_gust", wind_spd)
		mat.set_shader_parameter("wind_clock", wind_clock)
		mat.set_shader_parameter("water_time", _time)
		mat.set_shader_parameter("focus", focus_px)

	# Zone layer uniforms (keep entered zone bound while on-screen so it never snaps grey across seams!)
	var render_zid: StringName = _resolve_render_zone_id()
	var render_z_status: int = _zone_status_int(render_zid) if render_zid != &"" else 0
	var z_data: Dictionary = _ensure_zone_textures(render_zid)
	if not z_data.is_empty():
		_zone_mat.set_shader_parameter("map_tex", z_data["map"])
		_zone_mat.set_shader_parameter("light_tex", z_data["light"])
		_zone_mat.set_shader_parameter("fog_tex", _resolve_zone_fog_tex(render_zid))
		_zone_mat.set_shader_parameter("zone_origin", z_data["origin"])
		_zone_mat.set_shader_parameter("zone_size", z_data["size"])
		_zone_mat.set_shader_parameter("active_zone_status", render_z_status)
		var cf_arr: PackedVector2Array = z_data["campfires"] as PackedVector2Array
		_zone_mat.set_shader_parameter("campfires", _pad_vec2_array(cf_arr, 16))
		_zone_mat.set_shader_parameter("campfire_count", mini(cf_arr.size(), 16))
		var st_arr: PackedVector3Array = z_data["settlements"] as PackedVector3Array
		_zone_mat.set_shader_parameter("settlements", _pad_vec3_array(st_arr, 16))
		_zone_mat.set_shader_parameter("settlement_count", mini(st_arr.size(), 16))
		var gl_arr: PackedVector3Array = z_data["glows"] as PackedVector3Array
		_zone_mat.set_shader_parameter("glow_spots", _pad_vec3_array(gl_arr, 32))
		_zone_mat.set_shader_parameter("glow_spot_count", mini(gl_arr.size(), 32))
	else:
		_zone_mat.set_shader_parameter("map_tex", _fallback_white_tex)
		_zone_mat.set_shader_parameter("light_tex", _fallback_white_tex)
		_zone_mat.set_shader_parameter("fog_tex", _fallback_fog_tex)
		_zone_mat.set_shader_parameter("active_zone_status", 0)

	var lit_arr: PackedVector3Array = _gather_town_lit_circles()
	_zone_mat.set_shader_parameter("lit_circles", _pad_vec3_array(lit_arr, 24))
	_zone_mat.set_shader_parameter("lit_circle_count", mini(lit_arr.size(), 24))

	_zone_mat.set_shader_parameter("match_cut_active", _match_cut_active and _live_capture != null)
	if _live_capture != null:
		_zone_mat.set_shader_parameter("live_capture", _live_capture)
	_zone_mat.set_shader_parameter("match_cut_t", clampf(_match_cut_elapsed / MATCH_CUT_DISSOLVE_SEC, 0.0, 1.0))
	_zone_mat.set_shader_parameter("capture_center", _capture_center)
	_zone_mat.set_shader_parameter("capture_scale", _capture_scale)
	_zone_mat.set_shader_parameter("continent_blend", cont_blend)
	_zone_mat.set_shader_parameter("interior_blend", int_blend)
	_zone_mat.set_shader_parameter("frame_amount", zone_frame)
	_zone_mat.set_shader_parameter("open_amount", zone_open)

	# Sync Caelia's Veil density from shared VeilThreads + awakened Waystones in live gameplay
	if _preview_time < 0.0 and is_inside_tree():
		var vt_node: VeilThreads = get_tree().get_first_node_in_group("veil_threads") as VeilThreads
		var wm_node: Waystones = get_tree().get_first_node_in_group("waystones") as Waystones
		if vt_node != null or wm_node != null:
			var thread_r: float = vt_node.veil_progress_ratio() if vt_node != null else 0.0
			var ws_r: float = 0.0
			if wm_node != null:
				var ws_all: Array[Dictionary] = wm_node.entries()
				if not ws_all.is_empty():
					var awake_n: int = 0
					for w_e: Dictionary in ws_all:
						if bool(w_e.get("awake", false)):
							awake_n += 1
					ws_r = clampf(float(awake_n) / float(maxi(ws_all.size(), 1)), 0.0, 1.0)
					if awake_n > 0:
						ws_r = maxf(ws_r, 0.28)
			_veil_progress = clampf(thread_r * 0.78 + ws_r * 0.22, 0.0, 1.0)

	# Continent & World shared uniforms
	var c_data: Dictionary = _ensure_continent_textures(_continent_id)
	if not c_data.is_empty():
		var c_size: Vector2 = c_data["size"] as Vector2
		var rift_pos: Vector2 = c_data["rift_pos"] as Vector2
		var rift_rad: float = float(c_data["rift_radius"])
		var statuses: PackedInt32Array = PackedInt32Array()
		var reveals: PackedFloat32Array = PackedFloat32Array()
		statuses.resize(32)
		reveals.resize(32)
		statuses.fill(0)
		reveals.fill(0.0)
		var zone_order: Array = c_data["zone_order"] as Array
		for i: int in mini(zone_order.size(), 32):
			var zid: StringName = zone_order[i] as StringName
			var st: int = _zone_status_int(zid)
			statuses[i] = st
			reveals[i] = 1.0 if st == 2 else (0.55 if st == 1 else 0.0)

		for cmat: ShaderMaterial in [_continent_mat, _world_mat]:
			cmat.set_shader_parameter("continent_map_tex", c_data["map"])
			cmat.set_shader_parameter("continent_light_tex", c_data["light"])
			cmat.set_shader_parameter("engraving_tex", c_data["engraving"])
			cmat.set_shader_parameter("zone_id_tex", c_data["zone_id"])
			cmat.set_shader_parameter("continent_size", c_size)
			cmat.set_shader_parameter("zone_status", statuses)
			cmat.set_shader_parameter("rift_pos", rift_pos)
			cmat.set_shader_parameter("rift_radius", rift_rad)
			cmat.set_shader_parameter("veil_progress", _veil_progress)

		# Also feed Stone-Setter Engraving, Zone Status & Continent Sea to ZoneLayer so zooming into uncharted
		# territory or panning across zone seams stays 100% harmonized with KONTINENT view!
		_zone_mat.set_shader_parameter("continent_unlocked", _continent_unlocked or _preview_reveal_all)
		_zone_mat.set_shader_parameter("continent_map_tex", c_data["map"])
		_zone_mat.set_shader_parameter("continent_light_tex", c_data["light"])
		_zone_mat.set_shader_parameter("engraving_tex", c_data["engraving"])
		_zone_mat.set_shader_parameter("zone_id_tex", c_data["zone_id"])
		_zone_mat.set_shader_parameter("zone_status", statuses)
		_zone_mat.set_shader_parameter("zone_reveal", reveals)
		_zone_mat.set_shader_parameter("continent_size", c_size)
		_zone_mat.set_shader_parameter("rift_pos", rift_pos)
		_zone_mat.set_shader_parameter("rift_radius", rift_rad)

		_continent_mat.set_shader_parameter("zone_reveal", reveals)
		_continent_mat.set_shader_parameter("unlock_wave", _unlock_wave)
		_continent_mat.set_shader_parameter("frame_amount", cont_frame)
		_continent_mat.set_shader_parameter("open_amount", cont_open)

		# Zone -> Continent dithered ink wave from active zone's thresholds
		var wave_t: float = clampf((0.68 - _zoom) / 0.30, 0.0, 1.0) if show_continent else 0.0
		_continent_mat.set_shader_parameter("transition_t", wave_t)
		var th_pts: PackedVector2Array = PackedVector2Array()
		if _atlas != null and _active_zone_id != &"":
			var az: Atlas.Zone = _atlas.zone(_active_zone_id)
			_continent_mat.set_shader_parameter("active_zone_center", az.center() if az != null else c_size * 0.5)
			for th: Atlas.Threshold in _atlas.thresholds_of(_active_zone_id):
				th_pts.append(th.midpoint())
		_continent_mat.set_shader_parameter("active_thresholds", _pad_vec2_array(th_pts, 8))
		_continent_mat.set_shader_parameter("active_threshold_count", mini(th_pts.size(), 8))

		# World veil links & nodes (connect actual waystone positions when available)
		var v_links: Array[Vector4] = []
		var v_nodes: PackedVector2Array = PackedVector2Array()
		var zone_ws: Dictionary = {}
		if _atlas != null:
			var zs: Array[Atlas.Zone] = _atlas.zones_of(_continent_id)
			for z: Atlas.Zone in zs:
				var ws_pos: Vector2 = z.center()
				for lm: Atlas.Landmark in z.landmarks:
					if lm.kind == &"waystone":
						ws_pos = lm.pos
						break
				zone_ws[z.id] = ws_pos
				v_nodes.append(ws_pos)
			for th: Atlas.Threshold in _atlas.thresholds.values():
				var za: Atlas.Zone = _atlas.zone(th.a)
				var zb: Atlas.Zone = _atlas.zone(th.b)
				if za != null and zb != null and za.continent == _continent_id and zb.continent == _continent_id:
					var pa: Vector2 = zone_ws.get(za.id, za.center()) as Vector2
					var pb: Vector2 = zone_ws.get(zb.id, zb.center()) as Vector2
					v_links.append(Vector4(pa.x, pa.y, pb.x, pb.y))
		_world_mat.set_shader_parameter("veil_links", _pad_vec4_array(v_links, 24))
		_world_mat.set_shader_parameter("veil_link_count", mini(v_links.size(), 24))
		_world_mat.set_shader_parameter("veil_nodes", _pad_vec2_array(v_nodes, 16))
		_world_mat.set_shader_parameter("veil_node_count", mini(v_nodes.size(), 16))
		_world_mat.set_shader_parameter("cloud_flythrough", cloud_fly)
		_world_mat.set_shader_parameter("world_alpha", world_alpha)
		_world_mat.set_shader_parameter("frame_amount", world_frame)
		_world_mat.set_shader_parameter("open_amount", world_open)


func _gather_town_lit_circles() -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	if not is_inside_tree():
		return out
	var town: Node = get_tree().get_first_node_in_group("town")
	if town == null or not bool(town.get("founded")):
		return out
	if town.has_method(&"lit_circles"):
		var raw: Array = town.call(&"lit_circles") as Array
		for v: Variant in raw:
			if v is Vector3:
				var c: Vector3 = v as Vector3
				out.append(Vector3(c.x / 16.0, c.y / 16.0, c.z / 16.0))
	return out


func _pad_vec2_array(src: PackedVector2Array, target_len: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(target_len)
	out.fill(Vector2.ZERO)
	for i: int in mini(src.size(), target_len):
		out[i] = src[i]
	return out


func _pad_vec3_array(src: PackedVector3Array, target_len: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(target_len)
	out.fill(Vector3.ZERO)
	for i: int in mini(src.size(), target_len):
		out[i] = src[i]
	return out


func _pad_vec4_array(src: Array[Vector4], target_len: int) -> Array[Vector4]:
	var out: Array[Vector4] = []
	out.resize(target_len)
	for i: int in target_len:
		out[i] = src[i] if i < src.size() else Vector4.ZERO
	return out


func _ensure_local_weather_field() -> void:
	if _local_weather_field != null:
		return
	_local_weather_field = WeatherField.new()
	var bytes: PackedByteArray = _local_weather_field._generate(42)
	_local_weather_field._finish(bytes, Callable())


# =========================================================================
# Discovery & Status Helpers (v2 + Phase A v1 Fallbacks)
# =========================================================================

func _resolve_zone_fog_tex(zone_id: StringName) -> ImageTexture:
	if zone_id == &"":
		return _fallback_fog_tex
	if _preview_reveal_all or (_discovery != null and _discovery.is_reveal_all()):
		return _fallback_fog_tex
	if _discovery != null and _discovery.has_method(&"zone_fog_texture"):
		var tex: ImageTexture = _discovery.call(&"zone_fog_texture", zone_id) as ImageTexture
		if tex != null:
			return tex
	var z: Atlas.Zone = _atlas.zone(zone_id) if _atlas != null else null
	if z == null:
		return _fallback_fog_tex
	var z_entry: Dictionary = _zone_textures.get(zone_id, {}) as Dictionary
	if z_entry.has("fallback_fog") and _discovery == null:
		return z_entry["fallback_fog"] as ImageTexture
	var fw: int = maxi(ceili(float(z.size.x) * 0.5), 4)
	var fh: int = maxi(ceili(float(z.size.y) * 0.5), 4)
	var pixels: PackedByteArray = PackedByteArray()
	pixels.resize(fw * fh)
	var all_seen: bool = _preview_reveal_all or (_discovery != null and _discovery.is_reveal_all())
	if all_seen:
		pixels.fill(255)
	elif _discovery != null:
		var any_seen: bool = false
		for fy: int in fh:
			for fx: int in fw:
				var wt: Vector2 = Vector2(z.origin) + Vector2(fx * 2 + 1, fy * 2 + 1)
				if _discovery.is_seen(wt):
					pixels[fy * fw + fx] = 255
					any_seen = true
		if not any_seen and zone_id == _player_zone:
			for fy: int in fh:
				for fx: int in fw:
					var wt: Vector2 = Vector2(z.origin) + Vector2(fx * 2 + 1, fy * 2 + 1)
					if wt.distance_to(_player_tile) <= 32.0:
						pixels[fy * fw + fx] = 255
	else:
		pixels.fill(255)
	var img: Image = Image.create_from_data(fw, fh, false, Image.FORMAT_R8, pixels)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	if not z_entry.is_empty():
		z_entry["fallback_fog"] = tex
	return tex


func _zone_status_int(zone_id: StringName) -> int:
	if _preview_reveal_all:
		return 2
	if _discovery != null:
		if _discovery.is_reveal_all():
			return 2
		if _discovery.has_method(&"zone_status"):
			var st: StringName = _discovery.call(&"zone_status", zone_id) as StringName
			if st == &"betreten":
				return 2
			if st == &"gesichtet":
				return 1
			return 0
	if zone_id == _player_zone or zone_id == _active_zone_id:
		return 2
	if _director != null and _director.has_method(&"seen_zone") and bool(_director.call(&"seen_zone", zone_id)):
		return 2
	if _atlas != null and _player_zone != &"":
		for th: Atlas.Threshold in _atlas.thresholds_of(_player_zone):
			if th.other(_player_zone) == zone_id:
				return 1
	return 0


func _zone_explored_ratio(zone_id: StringName) -> float:
	if _preview_reveal_all:
		return 1.0
	if _discovery != null:
		if _discovery.is_reveal_all():
			return 1.0
		if _discovery.has_method(&"zone_explored_ratio"):
			return float(_discovery.call(&"zone_explored_ratio", zone_id))
	var st: int = _zone_status_int(zone_id)
	return 0.45 if st == 2 else (0.05 if st == 1 else 0.0)


# =========================================================================
# Baked Texture Loading + Clean Procedural Fallbacks (Zero #000000)
# =========================================================================

func _load_texture_any(res_path: String) -> Texture2D:
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img: Image = Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(res_path):
		var res: Texture2D = load(res_path) as Texture2D
		if res != null:
			return res
	return null


func _load_json_any(res_path: String) -> Dictionary:
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return {}
	var txt: String = FileAccess.get_file_as_string(abs_path)
	if txt.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	return parsed as Dictionary if parsed is Dictionary else {}


func _ensure_zone_textures(zone_id: StringName) -> Dictionary:
	if zone_id == &"" or _atlas == null:
		return {}
	if _zone_textures.has(zone_id):
		return _zone_textures[zone_id] as Dictionary
	var z: Atlas.Zone = _atlas.zone(zone_id)
	if z == null:
		return {}
	var base: String = "res://data/world/zones/%s/baked/" % String(zone_id)
	var map_tex: Texture2D = _load_texture_any(base + "map.png")
	var light_tex: Texture2D = _load_texture_any(base + "map_light.png")
	var meta: Dictionary = _load_json_any(base + "meta.json")

	var campfires: PackedVector2Array = PackedVector2Array()
	var settlements: PackedVector3Array = PackedVector3Array()
	var glows: PackedVector3Array = PackedVector3Array()

	if map_tex == null or light_tex == null:
		var synth: Dictionary = _synthesize_zone_maps(z)
		if map_tex == null:
			map_tex = synth["map"] as Texture2D
		if light_tex == null:
			light_tex = synth["light"] as Texture2D
		campfires = synth["campfires"] as PackedVector2Array
		settlements = synth["settlements"] as PackedVector3Array
		glows = synth["glows"] as PackedVector3Array

	var orig: Vector2 = Vector2(z.origin)
	var local_rect: Rect2 = Rect2(Vector2(-4.0, -4.0), Vector2(z.size) + Vector2(8.0, 8.0))
	var cont_rect: Rect2 = z.bbox.grow(4.0)

	for cf: Variant in meta.get("campfires", []) as Array:
		if cf is Array and (cf as Array).size() >= 2:
			var pt: Vector2 = Vector2(float((cf as Array)[0]), float((cf as Array)[1]))
			if not cont_rect.has_point(pt) and local_rect.has_point(pt):
				pt += orig
			campfires.append(pt)
	for st: Variant in meta.get("settlements", []) as Array:
		if st is Array and (st as Array).size() >= 3:
			var pt: Vector2 = Vector2(float((st as Array)[0]), float((st as Array)[1]))
			if not cont_rect.has_point(pt) and local_rect.has_point(pt):
				pt += orig
			settlements.append(Vector3(pt.x, pt.y, float((st as Array)[2])))
	for gl: Variant in meta.get("glow_spots", []) as Array:
		if gl is Array and (gl as Array).size() >= 3:
			var pt: Vector2 = Vector2(float((gl as Array)[0]), float((gl as Array)[1]))
			if not cont_rect.has_point(pt) and local_rect.has_point(pt):
				pt += orig
			glows.append(Vector3(pt.x, pt.y, float((gl as Array)[2])))

	# Include camp.campfire_tile from zone.json (e.g., WINDKAP Silberbucht campfire)
	var camp_raw: Variant = z.raw.get("camp", {})
	if camp_raw is Dictionary:
		var cf_raw: Variant = (camp_raw as Dictionary).get("campfire_tile", (camp_raw as Dictionary).get("tile"))
		if cf_raw is Array and (cf_raw as Array).size() >= 2:
			var cf_pt: Vector2 = Vector2(float((cf_raw as Array)[0]), float((cf_raw as Array)[1]))
			if not cont_rect.has_point(cf_pt) and local_rect.has_point(cf_pt):
				cf_pt += orig
			var has_cf: bool = false
			for existing: Vector2 in campfires:
				if existing.distance_squared_to(cf_pt) < 1.0:
					has_cf = true
					break
			if not has_cf:
				campfires.append(cf_pt)

	# Ensure landmarks (campfires, settlements, waystones, ruins) always emit/smoke if meta omitted them
	for lm: Atlas.Landmark in z.landmarks:
		if lm.kind == &"campfire" or lm.kind == &"camp":
			var has_cf: bool = false
			for existing: Vector2 in campfires:
				if existing.distance_squared_to(lm.pos) < 1.0:
					has_cf = true
					break
			if not has_cf:
				campfires.append(lm.pos)
		elif lm.kind == &"waystone" or lm.kind == &"veil_thread" or lm.kind == &"crystal":
			glows.append(Vector3(lm.pos.x, lm.pos.y, 0.0 if lm.kind == &"waystone" else 1.0))
		elif lm.kind == &"lighthouse" or lm.kind == &"ruin" or lm.kind == &"settlement":
			settlements.append(Vector3(lm.pos.x, lm.pos.y, 8.0))

	var entry: Dictionary = {
		"map": map_tex,
		"light": light_tex,
		"meta": meta,
		"origin": Vector2(z.origin),
		"size": Vector2(z.size),
		"campfires": campfires,
		"settlements": settlements,
		"glows": glows,
	}
	_zone_textures[zone_id] = entry
	return entry


func _synthesize_zone_maps(z: Atlas.Zone) -> Dictionary:
	var scale_px: int = 2
	var w: int = maxi(z.size.x * scale_px, 16)
	var h: int = maxi(z.size.y * scale_px, 16)
	var map_img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var light_img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var base_biome: String = z.biomes[0] if not z.biomes.is_empty() else "meadow"
	var base_col: Color = BIOME_COLORS.get(base_biome, Color("3e7d56")) as Color
	var border_col: Color = Color("1f3b32")
	var shore_col: Color = Color("c8b48a")
	var water_col: Color = Color("1e5162")
	var cliff_col: Color = Color("524a62")
	var path_col: Color = Color("b8a484")
	var canopy_dark: Color = Color("22483c")
	var canopy_light: Color = Color("55985f")

	var landscape: Landscape = Landscape.of(_atlas, _continent_id)
	var campfires: PackedVector2Array = PackedVector2Array()
	var settlements: PackedVector3Array = PackedVector3Array()
	var glows: PackedVector3Array = PackedVector3Array()

	var is_coast: bool = z.kind == &"coast" or String(z.id).contains("windkap")
	for py: int in h:
		for px: int in w:
			var tile: Vector2 = Vector2(z.origin) + Vector2(float(px) / float(scale_px), float(py) / float(scale_px))
			var inside: bool = z.contains(tile)
			var edge_d: float = Atlas.edge_distance(tile, z.footprint) if not z.footprint.is_empty() else 10.0
			var n_val: float = fposmod(sin(tile.x * 12.9898 + tile.y * 78.233) * 43758.5453, 1.0)
			var col: Color = base_col
			var elev: float = 0.45
			var fmask: int = 128

			if not inside:
				if is_coast and tile.y > float(z.origin.y + z.size.y) * 0.72:
					col = water_col
					elev = 0.05
					fmask = 128 + 1
				else:
					col = border_col.lerp(canopy_dark, 0.45 if n_val > 0.5 else 0.1)
					elev = 0.55
			else:
				var meadow_shift: float = sin(tile.x * 0.08) * cos(tile.y * 0.08)
				col = base_col.lerp(canopy_light, clampf(meadow_shift * 0.35 + 0.15, 0.0, 0.45))
				if edge_d < 3.5:
					col = col.lerp(shore_col if is_coast and tile.y > z.center().y else cliff_col, 0.55)
				if base_biome == "meadow":
					fmask = 128 + 2

			# Guarantee no #000000 pixel
			col = Color(maxf(col.r, 0.03), maxf(col.g, 0.02), maxf(col.b, 0.04), 1.0)
			map_img.set_pixel(px, py, col)
			light_img.set_pixel(px, py, Color(0.5, 0.5, elev, float(fmask) / 255.0))

	# Stamp landscape stands (forests) & ways
	if landscape != null:
		for st: Landscape.Stand in landscape.stands:
			var s_bbox: Rect2 = st.bbox.grow(4.0)
			if not z.bbox.intersects(s_bbox):
				continue
			var x0: int = clampi(int((s_bbox.position.x - z.origin.x) * scale_px), 0, w - 1)
			var y0: int = clampi(int((s_bbox.position.y - z.origin.y) * scale_px), 0, h - 1)
			var x1: int = clampi(int((s_bbox.end.x - z.origin.x) * scale_px), 0, w - 1)
			var y1: int = clampi(int((s_bbox.end.y - z.origin.y) * scale_px), 0, h - 1)
			for py: int in range(y0, y1 + 1):
				for px: int in range(x0, x1 + 1):
					var tile: Vector2 = Vector2(z.origin) + Vector2(float(px) / float(scale_px), float(py) / float(scale_px))
					if Geometry2D.is_point_in_polygon(tile, st.outline):
						map_img.set_pixel(px, py, canopy_dark.lerp(base_col, 0.25))
						light_img.set_pixel(px, py, Color(0.42, 0.42, 0.62, float(128 + 4) / 255.0))
		for way: Dictionary in landscape.ways:
			var pts: PackedVector2Array = way.get("pts", PackedVector2Array()) as PackedVector2Array
			for i: int in pts.size() - 1:
				var a: Vector2 = (pts[i] - Vector2(z.origin)) * scale_px
				var b: Vector2 = (pts[i + 1] - Vector2(z.origin)) * scale_px
				var steps: int = maxi(int(a.distance_to(b)), 1)
				for s: int in steps + 1:
					var p: Vector2i = Vector2i(a.lerp(b, float(s) / float(steps)).round())
					for oy: int in range(-1, 2):
						for ox: int in range(-1, 2):
							var q: Vector2i = p + Vector2i(ox, oy)
							if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
								map_img.set_pixelv(q, path_col)
								light_img.set_pixelv(q, Color(0.5, 0.5, 0.44, float(128 + 64) / 255.0))
		for tree: Dictionary in landscape.trees_of(z.id):
			var tp: Vector2i = Vector2i(((tree["pos"] as Vector2) - Vector2(z.origin)) * scale_px)
			if tp.x >= 1 and tp.y >= 1 and tp.x < w - 1 and tp.y < h - 1:
				map_img.set_pixel(tp.x, tp.y, canopy_light)
				map_img.set_pixel(tp.x + 1, tp.y + 1, canopy_dark)
				light_img.set_pixel(tp.x, tp.y, Color(0.35, 0.35, 0.78, float(128 + 4) / 255.0))

	# Sample places & landmarks so zone feels hand-illustrated
	for pl: Atlas.Place in z.places:
		if pl.id == &"silberbucht" or pl.id == &"kuestenlager":
			campfires.append(pl.bbox.get_center())
	for lm: Atlas.Landmark in z.landmarks:
		var lp: Vector2i = Vector2i((lm.pos - Vector2(z.origin)) * scale_px)
		if lp.x >= 2 and lp.y >= 2 and lp.x < w - 2 and lp.y < h - 2:
			var lm_bit: int = 16 if (lm.kind == &"waystone" or lm.kind == &"veil_thread" or lm.kind == &"crystal") else 8
			for oy: int in range(-1, 2):
				for ox: int in range(-1, 2):
					map_img.set_pixel(lp.x + ox, lp.y + oy, Color("e6c468"))
					light_img.set_pixel(lp.x + ox, lp.y + oy, Color(0.45, 0.45, 0.75, float(128 + lm_bit) / 255.0))

	if campfires.is_empty():
		campfires.append(z.center() + Vector2(-12.0, 8.0))
	if glows.is_empty():
		glows.append(Vector3(z.center().x + 14.0, z.center().y - 10.0, 0.0))

	return {
		"map": ImageTexture.create_from_image(map_img),
		"light": ImageTexture.create_from_image(light_img),
		"campfires": campfires,
		"settlements": settlements,
		"glows": glows,
	}


func _ensure_continent_textures(continent_id: StringName) -> Dictionary:
	if continent_id == &"" or _atlas == null:
		return {}
	if _continent_textures.has(continent_id):
		return _continent_textures[continent_id] as Dictionary
	var cont: Atlas.Continent = _atlas.continent(continent_id)
	if cont == null:
		return {}
	var base: String = "res://data/world/continents/baked/%s/" % String(continent_id)
	var map_tex: Texture2D = _load_texture_any(base + "continent_map.png")
	var light_tex: Texture2D = _load_texture_any(base + "continent_light.png")
	var engr_tex: Texture2D = _load_texture_any(base + "engraving.png")
	var meta: Dictionary = _load_json_any(base + "continent_meta.json")

	var zones_list: Array[Atlas.Zone] = _atlas.zones_of(continent_id)
	var zone_order: Array[StringName] = []
	for z: Atlas.Zone in zones_list:
		zone_order.append(z.id)

	var c_size: Vector2 = Vector2(cont.size)
	var synth: Dictionary = _synthesize_continent_maps(cont, zones_list, map_tex == null or light_tex == null or engr_tex == null)
	if map_tex == null:
		map_tex = synth["map"] as Texture2D
	if light_tex == null:
		light_tex = synth["light"] as Texture2D
	if engr_tex == null:
		engr_tex = synth["engraving"] as Texture2D

	var raw_rift: Variant = meta.get("rift_pos")
	var rift_pos: Vector2 = Vector2(c_size.x * 0.84, c_size.y * 0.52)
	if raw_rift is Array and (raw_rift as Array).size() >= 2:
		var rift_arr: Array = raw_rift as Array
		rift_pos = Vector2(float(rift_arr[0]), float(rift_arr[1]))
	var default_rift_r: float = 0.0 if (meta.has("rift_pos") and raw_rift == null) else (125.0 if continent_id == &"main" else 0.0)
	var rift_rad: float = float(meta.get("rift_radius", default_rift_r))

	var entry: Dictionary = {
		"map": map_tex,
		"light": light_tex,
		"engraving": engr_tex,
		"zone_id": synth["zone_id"] as Texture2D,
		"size": c_size,
		"zone_order": zone_order,
		"meta": meta,
		"rift_pos": rift_pos,
		"rift_radius": rift_rad,
	}
	_continent_textures[continent_id] = entry
	return entry


func _synthesize_continent_maps(cont: Atlas.Continent, zones_list: Array[Atlas.Zone], need_art: bool) -> Dictionary:
	# 4 tiles per texel -> 600x450 for 2400x1800 ALTMARK using O(1) bucketed zone_at_tile
	var step: float = 4.0
	var tw: int = maxi(ceili(float(cont.size.x) / step), 16)
	var th: int = maxi(ceili(float(cont.size.y) / step), 16)
	var zid_img: Image = Image.create(tw, th, false, Image.FORMAT_R8)
	var map_img: Image = Image.create(tw, th, false, Image.FORMAT_RGBA8) if need_art else null
	var light_img: Image = Image.create(tw, th, false, Image.FORMAT_RGBA8) if need_art else null
	var engr_img: Image = Image.create(tw, th, false, Image.FORMAT_RGBA8) if need_art else null

	var zone_idx_by_id: Dictionary = {}
	for i: int in mini(zones_list.size(), 31):
		zone_idx_by_id[zones_list[i].id] = i + 1

	# Build overall organic island hull around all zones
	var min_p: Vector2 = Vector2(float(cont.size.x) * 0.16, float(cont.size.y) * 0.16)
	var max_p: Vector2 = Vector2(float(cont.size.x) * 0.86, float(cont.size.y) * 0.86)
	if zones_list.size() > 2:
		min_p = Vector2(1e6, 1e6)
		max_p = Vector2(-1e6, -1e6)
		for z: Atlas.Zone in zones_list:
			min_p = min_p.min(z.bbox.position - Vector2(60.0, 60.0))
			max_p = max_p.max(z.bbox.end + Vector2(60.0, 60.0))
	var island_c: Vector2 = (min_p + max_p) * 0.5
	var island_r: Vector2 = ((max_p - min_p) * 0.5).max(Vector2(420.0, 320.0))

	for py: int in th:
		for px: int in tw:
			var tile: Vector2 = Vector2((float(px) + 0.5) * step, (float(py) + 0.5) * step)
			var zid_name: StringName = _atlas.zone_at_tile(cont.id, tile) if _atlas != null else &""
			var zid_idx: int = int(zone_idx_by_id.get(zid_name, 0))
			zid_img.set_pixel(px, py, Color(float(zid_idx) / 255.0, 0.0, 0.0, 1.0))
			if not need_art:
				continue
			var z_match: Atlas.Zone = _atlas.zone(zid_name) if (zid_idx > 0 and _atlas != null) else null
			var rel: Vector2 = (tile - island_c) / island_r
			var wobble: float = sin(tile.x * 0.012) * 0.08 + cos(tile.y * 0.015) * 0.08 + sin((tile.x + tile.y) * 0.007) * 0.06
			var land: bool = z_match != null or (rel.length() + wobble < 0.96)
			if not land:
				map_img.set_pixel(px, py, Color(0.0, 0.0, 0.0, 0.0))
				light_img.set_pixel(px, py, Color(0.5, 0.5, 0.0, 1.0))
				engr_img.set_pixel(px, py, Color(0.18, 0.16, 0.24, 0.0))
			else:
				var biome_key: String = z_match.biomes[0] if (z_match != null and not z_match.biomes.is_empty()) else "meadow"
				var col: Color = BIOME_COLORS.get(biome_key, Color("3e7d56")) as Color
				var ridge: float = 0.5 + 0.5 * sin(tile.x * 0.018 + tile.y * 0.014)
				col = col.lerp(Color("4f8c5a"), ridge * 0.25)
				if rel.length() + wobble > 0.89:
					col = col.lerp(Color("c8b48a"), 0.55)
				var lum: float = 0.28 + 0.18 * ridge
				var engr_c: Color = Color(lum * 0.95, lum * 0.90, lum * 1.10, 1.0)
				if (px + py) % 7 == 0 and ridge > 0.65:
					engr_c = engr_c.lightened(0.18)
				map_img.set_pixel(px, py, Color(maxf(col.r, 0.03), maxf(col.g, 0.03), maxf(col.b, 0.05), 1.0))
				light_img.set_pixel(px, py, Color(0.5 + 0.15 * cos(tile.x * 0.02), 0.5 + 0.15 * sin(tile.y * 0.02), 0.45 + 0.25 * ridge, 1.0))
				engr_img.set_pixel(px, py, engr_c)

	var out: Dictionary = {"zone_id": ImageTexture.create_from_image(zid_img)}
	if need_art:
		out["map"] = ImageTexture.create_from_image(map_img)
		out["light"] = ImageTexture.create_from_image(light_img)
		out["engraving"] = ImageTexture.create_from_image(engr_img)
	return out


# =========================================================================
# Vector / Pixel Overlay Rendering (`_draw_overlay`)
# =========================================================================

func _draw_overlay() -> void:
	if _overlay == null or (not visible and not _closing):
		return
	var fade: float = clampf((_open_t - 0.15) / 0.55, 0.0, 1.0)
	if fade <= 0.01:
		return
	var void_level: float = VineStyle.void_amount()
	if _preview_time >= 0.0:
		void_level = TimeManager.night_at(_preview_time)

	_place_hit_rects.clear()
	_filter_hit_rects.clear()
	_marker_hit_rects.clear()
	_pin_slot_rects.clear()
	_flower_hit_rect = Rect2()
	_peer_join_rect = Rect2()
	_continent_label_rects.clear()
	_placed_overlay_rects.clear()
	_placed_world_rects.clear()
	_seed_ui_safe_rects()

	# 1. World-space cartography (locked outline, routes, POI plaques, region/zone/place watermarks, pings)
	_draw_focused_locked_zone_outline(fade)
	_draw_quest_routes_and_arrows(fade)
	_draw_peer_route(fade)
	if _current_level == LEVEL_CONTINENT or _current_level == LEVEL_WORLD:
		_draw_continent_zone_labels(fade)
		_draw_markers_and_pins(fade)
	else:
		_draw_markers_and_pins(fade)
		_draw_zone_place_watermarks(fade)
	_draw_pings(fade)

	# 2. Hover bark-paper card on KONTINENT or "ZU IHM" peer popup
	if not _selected_peer_marker.is_empty():
		_draw_peer_join_card(fade, void_level)
	elif _current_level == LEVEL_CONTINENT and _zoom >= 0.12 and _hovered_zone_id != &"" and _hover_zone_t > 0.01:
		_draw_zone_hover_card(_hover_zone_card, fade)

	# 3. Vine border lock indicator when hitting 0.6 px/tile
	if not _continent_unlocked and _limit_bump_t > 0.01:
		_draw_vine_lock_flash(fade, void_level)

	# 3b. 60% Chronicle Reward: Silberkuesten-Rahmenranke
	if _book != null and _book.is_silvercoast_frame_active():
		_draw_silvercoast_frame(fade)

	# 4. Frame UI (Tags, Header, Place List, Zoom Vine, Filter Branch, Scale Bar, Compass)
	var book_dim: float = 1.0 - clampf(_book._open_t * 1.25, 0.0, 1.0) if _book != null else 1.0
	if book_dim > 0.01:
		_draw_frame_ui(fade * book_dim, void_level)


func _seed_ui_safe_rects() -> void:
	var vs: Vector2 = _view_size()
	var top_h: float = 44.0 if (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE) else 24.0
	_placed_overlay_rects.append(Rect2(vs.x * 0.5 - 66.0, 0.0, 132.0, top_h))
	_placed_overlay_rects.append(Rect2(0.0, 44.0, 68.0, 132.0))
	_placed_overlay_rects.append(Rect2(vs.x - 42.0, 82.0, 42.0, 256.0))
	_placed_overlay_rects.append(Rect2(0.0, vs.y - 34.0, vs.x, 34.0))
	if (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE) and _atlas != null and _active_zone_id != &"":
		var z: Atlas.Zone = _atlas.zone(_active_zone_id)
		if z != null and not z.places.is_empty():
			_placed_overlay_rects.append(Rect2(vs.x - 118.0, 24.0, 118.0, float(z.places.size()) * 11.0 + 8.0))


func _rect_overlaps_placed(candidate: Rect2, pad: float = 2.0) -> bool:
	var grown: Rect2 = candidate.grow(pad)
	var vs: Vector2 = _view_size()
	if grown.position.x < 4.0 or grown.position.y < 4.0 or grown.end.x > vs.x - 4.0 or grown.end.y > vs.y - 4.0:
		return true
	for used: Rect2 in _placed_overlay_rects:
		if grown.intersects(used):
			return true
	return false


func _world_rect_overlaps(candidate: Rect2, pad: float = 2.0) -> bool:
	var grown: Rect2 = candidate.grow(pad)
	for used: Rect2 in _placed_world_rects:
		if grown.intersects(used):
			return true
	return false


func _world_label_fade(rect: Rect2) -> float:
	var vs: Vector2 = _view_size()
	var d_l: float = rect.position.x - 10.0
	var d_r: float = (vs.x - 10.0) - rect.end.x
	var d_t: float = rect.position.y - 12.0
	var d_b: float = (vs.y - 20.0) - rect.end.y
	var min_d: float = minf(minf(d_l, d_r), minf(d_t, d_b))
	if min_d <= 0.0:
		return 0.0
	return clampf(min_d / 14.0, 0.0, 1.0)


const CARTO_ACCENTS: Dictionary = {"Ä": "A", "Ö": "O", "Ü": "U"}
const CARTO_PLAQUE_GLYPHS: Dictionary = {
	"A": [".XX.", "X..X", "XXXX", "X..X", "X..X"],
	"B": ["XXX.", "X..X", "XXX.", "X..X", "XXX."],
	"C": [".XXX", "X...", "X...", "X...", ".XXX"],
	"D": ["XXX.", "X..X", "X..X", "X..X", "XXX."],
	"E": ["XXXX", "X...", "XXX.", "X...", "XXXX"],
	"F": ["XXXX", "X...", "XXX.", "X...", "X..."],
	"G": [".XXX", "X...", "X.XX", "X..X", ".XXX"],
	"H": ["X..X", "X..X", "XXXX", "X..X", "X..X"],
	"I": ["XXX", ".X.", ".X.", ".X.", "XXX"],
	"J": ["..XX", "...X", "...X", "X..X", ".XX."],
	"K": ["X..X", "X.X.", "XX..", "X.X.", "X..X"],
	"L": ["X...", "X...", "X...", "X...", "XXXX"],
	"M": ["X...X", "XX.XX", "X.X.X", "X...X", "X...X"],
	"N": ["X...X", "XX..X", "X.X.X", "X..XX", "X...X"],
	"O": [".XX.", "X..X", "X..X", "X..X", ".XX."],
	"P": ["XXX.", "X..X", "XXX.", "X...", "X..."],
	"Q": [".XX.", "X..X", "X..X", "X.XX", ".XXX"],
	"R": ["XXX.", "X..X", "XXX.", "X.X.", "X..X"],
	"S": [".XXX", "X...", ".XX.", "...X", "XXX."],
	"T": ["XXXXX", "..X..", "..X..", "..X..", "..X.."],
	"U": ["X..X", "X..X", "X..X", "X..X", ".XX."],
	"V": ["X...X", "X...X", "X...X", ".X.X.", "..X.."],
	"W": ["X...X", "X...X", "X.X.X", "XX.XX", "X...X"],
	"X": ["X...X", ".X.X.", "..X..", ".X.X.", "X...X"],
	"Y": ["X...X", ".X.X.", "..X..", "..X..", "..X.."],
	"Z": ["XXXX", "..X.", ".X..", "X...", "XXXX"],
	"0": [".XX.", "X..X", "X..X", "X..X", ".XX."],
	"1": [".X.", "XX.", ".X.", ".X.", "XXX"],
	"2": ["XXX.", "...X", ".XX.", "X...", "XXXX"],
	"3": ["XXX.", "...X", ".XX.", "...X", "XXX."],
	"4": ["X..X", "X..X", "XXXX", "...X", "...X"],
	"5": ["XXXX", "X...", "XXX.", "...X", "XXX."],
	"6": [".XXX", "X...", "XXX.", "X..X", ".XX."],
	"7": ["XXXX", "...X", "..X.", ".X..", ".X.."],
	"8": [".XX.", "X..X", ".XX.", "X..X", ".XX."],
	"9": [".XX.", "X..X", ".XXX", "...X", "XXX."],
	".": [".", ".", ".", ".", "X"],
	",": ["..", "..", "..", ".X", "X."],
	":": [".", "X", ".", "X", "."],
	"·": [".", ".", "X", ".", "."],
	"-": ["...", "...", "XXX", "...", "..."],
	"&": [".XX.", "X.X.", ".XX.", "X..X", ".XX."],
	"/": ["...X", "..X.", ".X..", "X...", "X..."],
	"%": ["X..X", "..X.", ".X..", "X...", "X..X"],
	"!": ["X", "X", "X", ".", "X"],
	"?": ["XXX.", "...X", ".XX.", "....", ".X.."],
	"(": [".X", "X.", "X.", "X.", ".X"],
	")": ["X.", ".X", ".X", ".X", "X."],
}

const CARTO_DISPLAY_GLYPHS: Dictionary = {
	"A": [".XXXX.", "XX..XX", "XX..XX", "XXXXXX", "XX..XX", "XX..XX", "XX..XX"],
	"B": ["XXXXX.", "XX..XX", "XX..XX", "XXXXX.", "XX..XX", "XX..XX", "XXXXX."],
	"C": [".XXXXX", "XX....", "XX....", "XX....", "XX....", "XX....", ".XXXXX"],
	"D": ["XXXXX.", "XX..XX", "XX..XX", "XX..XX", "XX..XX", "XX..XX", "XXXXX."],
	"E": ["XXXXX", "XX...", "XX...", "XXXX.", "XX...", "XX...", "XXXXX"],
	"F": ["XXXXX", "XX...", "XX...", "XXXX.", "XX...", "XX...", "XX..."],
	"G": [".XXXXX", "XX....", "XX....", "XX.XXX", "XX..XX", "XX..XX", ".XXXXX"],
	"H": ["XX..XX", "XX..XX", "XX..XX", "XXXXXX", "XX..XX", "XX..XX", "XX..XX"],
	"I": ["XXXX", ".XX.", ".XX.", ".XX.", ".XX.", ".XX.", "XXXX"],
	"J": ["..XXX", "...XX", "...XX", "...XX", "X..XX", "XX.XX", ".XXX."],
	"K": ["XX..XX", "XX.XX.", "XXXX..", "XXXX..", "XX.XX.", "XX..XX", "XX..XX"],
	"L": ["XX...", "XX...", "XX...", "XX...", "XX...", "XX...", "XXXXX"],
	"M": ["XX...XX", "XXX.XXX", "XXXXXXX", "XX.X.XX", "XX...XX", "XX...XX", "XX...XX"],
	"N": ["XX..XX", "XXX.XX", "XXXXXX", "XX.XXX", "XX..XX", "XX..XX", "XX..XX"],
	"O": [".XXXX.", "XX..XX", "XX..XX", "XX..XX", "XX..XX", "XX..XX", ".XXXX."],
	"P": ["XXXXX.", "XX..XX", "XX..XX", "XXXXX.", "XX....", "XX....", "XX...."],
	"Q": [".XXXX.", "XX..XX", "XX..XX", "XX..XX", "XX.XXX", "XX..XX", ".XXXXX"],
	"R": ["XXXXX.", "XX..XX", "XX..XX", "XXXXX.", "XX.XX.", "XX..XX", "XX..XX"],
	"S": [".XXXXX", "XX....", "XX....", ".XXXX.", "....XX", "....XX", "XXXXX."],
	"T": ["XXXXXX", "..XX..", "..XX..", "..XX..", "..XX..", "..XX..", "..XX.."],
	"U": ["XX..XX", "XX..XX", "XX..XX", "XX..XX", "XX..XX", "XX..XX", ".XXXX."],
	"V": ["XX..XX", "XX..XX", "XX..XX", "XX..XX", ".XXXX.", ".XXXX.", "..XX.."],
	"W": ["XX...XX", "XX...XX", "XX...XX", "XX.X.XX", "XXXXXXX", "XXX.XXX", "XX...XX"],
	"X": ["XX..XX", "XX..XX", ".XXXX.", "..XX..", ".XXXX.", "XX..XX", "XX..XX"],
	"Y": ["XX..XX", "XX..XX", ".XXXX.", "..XX..", "..XX..", "..XX..", "..XX.."],
	"Z": ["XXXXXX", "...XX.", "..XX..", ".XX...", "XX....", "XX....", "XXXXXX"],
	"0": [".XXXX.", "XX..XX", "XX.XXX", "XXX.XX", "XX..XX", "XX..XX", ".XXXX."],
	"1": [".XX.", "XXX.", ".XX.", ".XX.", ".XX.", ".XX.", "XXXX"],
	"2": [".XXXX.", "XX..XX", "....XX", "..XXX.", ".XX...", "XX....", "XXXXXX"],
	"3": ["XXXXX.", "....XX", "..XXX.", "....XX", "....XX", "XX..XX", ".XXXX."],
	"4": ["XX..XX", "XX..XX", "XX..XX", "XXXXXX", "....XX", "....XX", "....XX"],
	"5": ["XXXXXX", "XX....", "XXXXX.", "....XX", "....XX", "XX..XX", ".XXXX."],
	"6": [".XXXX.", "XX....", "XXXXX.", "XX..XX", "XX..XX", "XX..XX", ".XXXX."],
	"7": ["XXXXXX", "....XX", "...XX.", "..XX..", ".XX...", ".XX...", ".XX..."],
	"8": [".XXXX.", "XX..XX", "XX..XX", ".XXXX.", "XX..XX", "XX..XX", ".XXXX."],
	"9": [".XXXX.", "XX..XX", "XX..XX", ".XXXXX", "....XX", "....XX", ".XXXX."],
	".": ["..", "..", "..", "..", "..", "XX", "XX"],
	":": ["..", "XX", "..", "..", "..", "XX", ".."],
	"·": ["..", "..", "..", "XX", "..", "..", ".."],
	"-": ["....", "....", "....", "XXXX", "....", "....", "...."],
	"&": [".XXX..", "XX.XX.", ".XXX..", "XX.X.X", "XX..XX", "XX.XX.", ".XXX.X"],
	"/": ["....X", "...X.", "..X..", ".X...", ".X...", "X....", "X...."],
}

static var _carto_mesh_cache: Dictionary = {}


static func _build_carto_entry(norm: String, is_display: bool, gap_px: int) -> Dictionary:
	var key: String = "%s|%d|%s" % ["D" if is_display else "P", gap_px, norm]
	if _carto_mesh_cache.has(key):
		return _carto_mesh_cache[key] as Dictionary
	if _carto_mesh_cache.size() >= 384:
		_carto_mesh_cache.clear()
	var table: Dictionary = CARTO_DISPLAY_GLYPHS if is_display else CARTO_PLAQUE_GLYPHS
	var rows_h: int = 7 if is_display else 5
	var space_w: int = (4 if is_display else 3) + gap_px
	var verts: PackedVector3Array = PackedVector3Array()
	var idxs: PackedInt32Array = PackedInt32Array()
	var cur_x: int = 0
	for i: int in norm.length():
		var ch: String = norm.substr(i, 1)
		if ch == " ":
			cur_x += space_w
			continue
		var base: String = String(CARTO_ACCENTS.get(ch, ch))
		if not table.has(base):
			cur_x += space_w
			continue
		var rows: Array = table[base] as Array
		var gw: int = String(rows[0]).length()
		for ry: int in rows_h:
			var rstr: String = String(rows[ry])
			for rx: int in gw:
				if rstr.substr(rx, 1) == "X":
					var f0: int = verts.size()
					var fx: float = float(cur_x + rx)
					var fy: float = float(2 + ry)
					verts.append_array(PackedVector3Array([Vector3(fx, fy, 0.0), Vector3(fx + 1.0, fy, 0.0), Vector3(fx + 1.0, fy + 1.0, 0.0), Vector3(fx, fy + 1.0, 0.0)]))
					idxs.append_array(PackedInt32Array([f0, f0 + 1, f0 + 2, f0, f0 + 2, f0 + 3]))
		if CARTO_ACCENTS.has(ch):
			var u0: int = 1 if gw >= 6 else 0
			var u1: int = gw - 2 if gw >= 6 else maxi(gw - 1, 1)
			var dot_w: float = 2.0 if is_display else 1.0
			for ux: int in [u0, u1 - (1 if is_display else 0)]:
				var f1: int = verts.size()
				var fxu: float = float(cur_x + maxi(ux, 0))
				verts.append_array(PackedVector3Array([Vector3(fxu, 0.0, 0.0), Vector3(fxu + dot_w, 0.0, 0.0), Vector3(fxu + dot_w, 1.0, 0.0), Vector3(fxu, 1.0, 0.0)]))
				idxs.append_array(PackedInt32Array([f1, f1 + 1, f1 + 2, f1, f1 + 2, f1 + 3]))
		cur_x += gw + gap_px
	var total_w: int = maxi(cur_x - gap_px, 0)
	var mesh: ArrayMesh = ArrayMesh.new()
	if not verts.is_empty():
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_INDEX] = idxs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var entry: Dictionary = {"mesh": mesh, "width": total_w, "height": rows_h + 2}
	_carto_mesh_cache[key] = entry
	return entry


func _carto_text_width(text: String, is_display: bool, gap_px: int) -> int:
	var norm: String = text.replace("ß", "SS").to_upper()
	if norm.is_empty():
		return 0
	var entry: Dictionary = _build_carto_entry(norm, is_display, gap_px)
	return int(entry["width"])


func _draw_carto_text(text: String, top_left: Vector2, is_display: bool, gap_px: int, fill: Color, outline: Color, wide_halo: bool = false) -> void:
	var norm: String = text.replace("ß", "SS").to_upper()
	if norm.is_empty():
		return
	var entry: Dictionary = _build_carto_entry(norm, is_display, gap_px)
	var mesh: ArrayMesh = entry["mesh"] as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	# Retain mesh RID for the current frame just like PixelText.draw
	var retained: Dictionary = _overlay.get_meta(&"_carto_text_draw", {})
	var frame: int = Engine.get_process_frames()
	if int(retained.get("frame", -1)) != frame:
		retained = {"frame": frame, "meshes": {}}
		_overlay.set_meta(&"_carto_text_draw", retained)
	(retained["meshes"] as Dictionary)[mesh.get_instance_id()] = mesh

	var pos: Vector2 = top_left.round()
	if wide_halo:
		# Soft outer 2px ink aura + solid 8-neighbor 1px ink stroke (zero rectangular boxes!)
		var outer_aura: Color = Color(outline.r, outline.g, outline.b, outline.a * 0.48)
		for off2: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(2, 2), Vector2(1, 2), Vector2(2, 1)]:
			_overlay.draw_mesh(mesh, null, Transform2D(0.0, pos + off2), outer_aura)
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				_overlay.draw_mesh(mesh, null, Transform2D(0.0, pos + Vector2(float(dx), float(dy))), outline)
	elif outline.a > 0.0:
		for off1: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
			_overlay.draw_mesh(mesh, null, Transform2D(0.0, pos + off1), outline)
	_overlay.draw_mesh(mesh, null, Transform2D(0.0, pos), fill)


func _draw_carto_plaque(text: String, center_pos: Vector2, text_col: Color, border_col: Color, fade: float, emphasize: bool = false, track_override: int = -1) -> Rect2:
	var norm: String = text.replace("ß", "SS").to_upper()
	if norm.is_empty():
		return Rect2(center_pos, Vector2.ZERO)
	var gap_px: int = (1 + maxi(track_override, 0)) if track_override >= 0 else (2 if norm.length() <= 13 else 1)
	var tw: int = _carto_text_width(norm, false, gap_px)
	var pad_x: int = 6 if emphasize else 5
	var w: float = float(tw + pad_x * 2)
	var h: float = 13.0 if emphasize else 12.0
	var rx: float = roundf(center_pos.x - w * 0.5)
	var ry: float = roundf(center_pos.y - h * 0.5)
	var rect: Rect2 = Rect2(rx, ry, w, h)

	# 1px obsidian drop shadow + dark inner plaque + fine inlaid border (Website-Map drawCartoPill style)
	_overlay.draw_rect(Rect2(rx + 1.0, ry + 1.0, w, h), Color(0.025, 0.012, 0.055, 0.80 * fade))
	_overlay.draw_rect(rect, Color("0b0715", (0.95 if emphasize else 0.89) * fade))
	_overlay.draw_rect(rect.grow(-1.0), Color("110b20", (0.94 if emphasize else 0.87) * fade))

	var b_alpha: float = (0.86 if emphasize else 0.58) * fade
	_overlay.draw_rect(Rect2(rx + 1.0, ry, w - 2.0, 1.0), Color(border_col, b_alpha))
	_overlay.draw_rect(Rect2(rx + 1.0, ry + h - 1.0, w - 2.0, 1.0), Color(border_col.darkened(0.18), b_alpha))
	_overlay.draw_rect(Rect2(rx, ry + 1.0, 1.0, h - 2.0), Color(border_col, b_alpha * 0.88))
	_overlay.draw_rect(Rect2(rx + w - 1.0, ry + 1.0, 1.0, h - 2.0), Color(border_col.darkened(0.15), b_alpha * 0.88))
	if w >= 12.0:
		_overlay.draw_rect(Rect2(rx + 3.0, ry, w - 6.0, 1.0), Color(border_col.lightened(0.24), b_alpha))

	var t_fill: Color = Color(Color.WHITE if emphasize else text_col, fade)
	var t_out: Color = Color("080410", 0.96 * fade)
	_draw_carto_text(norm, Vector2(rx + float(pad_x), ry + 2.0), false, gap_px, t_fill, t_out, false)
	return rect


func _draw_region_watermark(title: String, subtitle: String, center_pos: Vector2, use_display: bool, title_col: Color, sub_col: Color, rule_col: Color, fade: float) -> Rect2:
	var t_gap: int = 3 if use_display else 2
	var s_gap: int = 2 if subtitle.length() <= 18 else 1
	var tw: int = _carto_text_width(title, use_display, t_gap)
	var sw: int = _carto_text_width(subtitle, false, s_gap) if not subtitle.is_empty() else 0
	var max_w: float = float(maxi(tw, sw))
	var th_px: float = 9.0 if use_display else 7.0
	var total_h: float = th_px + (12.0 if not subtitle.is_empty() else 3.0)
	var top_y: float = roundf(center_pos.y - total_h * 0.5)
	var cx: float = roundf(center_pos.x)
	var full_rect: Rect2 = Rect2(cx - max_w * 0.5 - 5.0, top_y - 2.0, max_w + 10.0, total_h + 4.0)

	var out_col: Color = Color("080410", 0.96 * fade)
	_draw_carto_text(title, Vector2(cx - float(tw) * 0.5, top_y), use_display, t_gap, Color(title_col, fade), out_col, true)

	# Delicate cartographer horizontal rule with center diamond jewel
	var rule_y: float = top_y + th_px + 2.0
	var rule_w: float = clampf(max_w * 0.78, 24.0, 92.0)
	var rx0: float = roundf(cx - rule_w * 0.5)
	_overlay.draw_rect(Rect2(rx0, rule_y + 1.0, rule_w, 1.0), Color("080410", 0.85 * fade))
	_overlay.draw_rect(Rect2(rx0 + 4.0, rule_y, rule_w - 8.0, 1.0), Color(rule_col, 0.76 * fade))
	_overlay.draw_rect(Rect2(rx0, rule_y, 4.0, 1.0), Color(rule_col, 0.36 * fade))
	_overlay.draw_rect(Rect2(rx0 + rule_w - 4.0, rule_y, 4.0, 1.0), Color(rule_col, 0.36 * fade))
	_overlay.draw_rect(Rect2(cx - 1.0, rule_y - 1.0, 3.0, 3.0), Color("080410", 0.92 * fade))
	_overlay.draw_rect(Rect2(cx, rule_y, 1.0, 1.0), Color(title_col.lightened(0.15), 0.96 * fade))

	if not subtitle.is_empty():
		_draw_carto_text(subtitle, Vector2(cx - float(sw) * 0.5, rule_y + 2.0), false, s_gap, Color(sub_col, 0.94 * fade), out_col, true)
	return full_rect


func _draw_citadel_crest(at: Vector2, active: bool, fade: float) -> void:
	var px: float = roundf(at.x)
	var py: float = roundf(at.y)
	VineStyle.glow(_overlay, Vector2(px, py), 12.0 if active else 9.0, Color("c4b3f5"), (0.45 if active else 0.28) * fade)
	_overlay.draw_rect(Rect2(px - 6.0, py - 5.0, 13.0, 11.0), Color("0d071a", 0.96 * fade))
	_overlay.draw_rect(Rect2(px - 5.0, py - 6.0, 11.0, 13.0), Color("0d071a", 0.96 * fade))
	var stone: Color = Color("e6dcff" if active else "c4b3f5", fade)
	var shade: Color = Color("8f7bc8", fade)
	# Three citadel towers + curtain base (matching map.mjs drawHallgratCrest)
	_overlay.draw_rect(Rect2(px - 4.0, py - 2.0, 2.0, 6.0), stone)
	_overlay.draw_rect(Rect2(px - 1.0, py - 4.0, 3.0, 8.0), stone)
	_overlay.draw_rect(Rect2(px + 3.0, py - 2.0, 2.0, 6.0), shade)
	_overlay.draw_rect(Rect2(px - 4.0, py + 2.0, 9.0, 2.0), shade)
	_overlay.draw_rect(Rect2(px - 4.0, py + 2.0, 5.0, 1.0), stone)
	# Luminous turquoise spire window
	_overlay.draw_rect(Rect2(px, py - 1.0, 1.0, 2.0), Color("7bf5e2", fade))


func _draw_hearth_beacon(at: Vector2, active: bool, fade: float) -> void:
	var px: float = roundf(at.x)
	var py: float = roundf(at.y)
	var pulse: float = 0.80 + 0.20 * sin(_time * 3.0 + px * 0.05)
	VineStyle.glow(_overlay, Vector2(px, py), 13.0 if active else 10.0, Color("f2c36b"), 0.45 * pulse * fade)
	for dy: int in range(-5, 6):
		var hw: int = int(floor(sqrt(maxf(27.0 - float(dy * dy), 0.0))))
		_overlay.draw_rect(Rect2(px - float(hw), py + float(dy), float(hw * 2 + 1), 1.0), Color("120a1c", 0.96 * fade))
	for dy: int in range(-4, 5):
		var hw: int = int(floor(sqrt(maxf(17.0 - float(dy * dy), 0.0))))
		_overlay.draw_rect(Rect2(px - float(hw), py + float(dy), float(hw * 2 + 1), 1.0), Color("331d10", 0.96 * fade))
	# Pixel-art amber hearth flame + bright core
	_overlay.draw_rect(Rect2(px, py - 3.0, 1.0, 1.0), Color("ff9a42", fade))
	_overlay.draw_rect(Rect2(px - 1.0, py - 2.0, 3.0, 2.0), Color("ff9a42", fade))
	_overlay.draw_rect(Rect2(px - 2.0, py, 5.0, 2.0), Color("ff9a42", fade))
	_overlay.draw_rect(Rect2(px - 1.0, py - 1.0, 2.0, 2.0), Color("fff0b0", fade))


func _draw_rift_arena_sigil(at: Vector2, active: bool, fade: float, is_rift: bool = false) -> void:
	var px: float = roundf(at.x)
	var py: float = roundf(at.y)
	var pulse: float = 0.78 + 0.22 * sin(_time * 2.8 + py * 0.04)
	var rim_col: Color = Color("ff5fd2") if is_rift else Color("ff6b7b")
	var core_col: Color = Color("f6d4ff") if is_rift else Color("ffd0d6")
	VineStyle.glow(_overlay, Vector2(px, py), 13.0 if active else 10.0, rim_col, 0.40 * pulse * fade)
	for dy: int in range(-5, 6):
		var hw: int = 5 - maxi(0, absi(dy) - 2)
		_overlay.draw_rect(Rect2(px - float(hw), py + float(dy), float(hw * 2 + 1), 1.0), Color("160714", 0.96 * fade))
	for dy: int in range(-4, 5):
		var hw: int = 4 - maxi(0, absi(dy) - 2)
		_overlay.draw_rect(Rect2(px - float(hw), py + float(dy), float(hw * 2 + 1), 1.0), Color(rim_col, 0.92 * fade))
	for dy: int in range(-3, 4):
		var hw: int = 3 - maxi(0, absi(dy) - 1)
		_overlay.draw_rect(Rect2(px - float(hw), py + float(dy), float(hw * 2 + 1), 1.0), Color("280c1c", 0.96 * fade))
	_overlay.draw_rect(Rect2(px - 1.0, py - 1.0, 3.0, 3.0), Color(core_col, fade))


func _draw_star_crest(at: Vector2, fill_col: Color, fade: float) -> void:
	var px: float = roundf(at.x)
	var py: float = roundf(at.y)
	var pulse: float = 0.80 + 0.20 * sin(_time * 2.6 + px * 0.05)
	VineStyle.glow(_overlay, Vector2(px, py), 10.0, fill_col, 0.36 * pulse * fade)
	# 9x9 4-point star with dark ink outline + turquoise center spark
	var spans_out: Array[int] = [1, 2, 2, 5, 5, 5, 2, 2, 1]
	var spans_in: Array[int] = [0, 1, 1, 2, 4, 2, 1, 1, 0]
	for idx: int in 9:
		var dy: int = idx - 4
		var ho: int = spans_out[idx]
		_overlay.draw_rect(Rect2(px - float(ho), py + float(dy), float(ho * 2 + 1), 1.0), Color("140b18", 0.96 * fade))
	for idx: int in 9:
		var dy: int = idx - 4
		var hi: int = spans_in[idx]
		if absi(dy) == 4:
			_overlay.draw_rect(Rect2(px, py + float(dy), 1.0, 1.0), Color(fill_col, fade))
		elif hi > 0:
			_overlay.draw_rect(Rect2(px - float(hi), py + float(dy), float(hi * 2 + 1), 1.0), Color(fill_col, fade))
	_overlay.draw_rect(Rect2(px, py, 1.0, 1.0), Color("7bf5e2", fade))


func _draw_waystone_diamond(at: Vector2, awake: bool, active: bool, fade: float) -> void:
	var px: float = roundf(at.x)
	var py: float = roundf(at.y)
	var col: Color = Color("4fe3c1") if awake else Color("8a7ea6")
	if awake or active:
		var pulse: float = 0.78 + 0.22 * sin(_time * 2.5 + px * 0.04)
		VineStyle.glow(_overlay, Vector2(px, py), 11.0 if active else 8.0, col, 0.36 * pulse * fade)
	var rad: int = 5 if active else 4
	for dy: int in range(-rad, rad + 1):
		var ho: int = rad - absi(dy)
		_overlay.draw_rect(Rect2(px - float(ho), py + float(dy), float(ho * 2 + 1), 1.0), Color("10091e", 0.96 * fade))
	for dy: int in range(-(rad - 1), rad):
		var hi: int = (rad - 1) - absi(dy)
		_overlay.draw_rect(Rect2(px - float(hi), py + float(dy), float(hi * 2 + 1), 1.0), Color(col, fade))
	_overlay.draw_rect(Rect2(px, py, 1.0, 1.0), Color("e6fff9" if awake else "d8d0ec", fade))


func _poly_boundary_distance(point: Vector2, poly: PackedVector2Array) -> float:
	var best: float = INF
	var n: int = poly.size()
	for i: int in n:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, poly[i], poly[(i + 1) % n])
		best = minf(best, point.distance_to(closest))
	return best


func _polygon_visual_center(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var bbox: Rect2 = Rect2(poly[0], Vector2.ZERO)
	var avg: Vector2 = Vector2.ZERO
	for pt: Vector2 in poly:
		bbox = bbox.expand(pt)
		avg += pt
	avg /= float(poly.size())
	var best_pt: Vector2 = avg if Geometry2D.is_point_in_polygon(avg, poly) else bbox.get_center()
	var best_score: float = _poly_boundary_distance(avg, poly) if Geometry2D.is_point_in_polygon(avg, poly) else -1.0
	for gy: int in 7:
		for gx: int in 7:
			var cand: Vector2 = bbox.position + Vector2(bbox.size.x * (float(gx) + 0.5) / 7.0, bbox.size.y * (float(gy) + 0.5) / 7.0)
			if Geometry2D.is_point_in_polygon(cand, poly):
				var d: float = _poly_boundary_distance(cand, poly)
				if d > best_score:
					best_score = d
					best_pt = cand
	return best_pt


func _region_display_pair(reg: Dictionary, max_st: int) -> Dictionary:
	var rid: String = String(reg.get("id", ""))
	var raw_name: String = String(reg.get("name", rid)).to_upper()
	var old_name: String = String(reg.get("old_name", "")).to_upper()
	if max_st <= 0:
		var engr_title: String = old_name if not old_name.is_empty() else raw_name
		return {"title": engr_title, "sub": "STEINSETZER-GRAVUR"}
	match rid:
		"suedwestkueste":
			return {"title": "SÜDWESTKÜSTE", "sub": "SILBERBUCHT & KAPS"}
		"gruenland":
			return {"title": "GRÜNLAND", "sub": "WIESENLANDE & ZINNEN"}
		"glaskamm":
			return {"title": "DER GLASKAMM", "sub": "KLANGSTEIN-HÖHEN"}
		"hexenwald":
			return {"title": "HEXENWALD", "sub": "SCHATTENWALD"}
		"leerenbluehen":
			return {"title": "LEERENBLÜHEN", "sub": "ÖSTLICHER SAUM"}
	return {"title": raw_name, "sub": old_name}


func _place_continent_crest_plaque(icon_kind: StringName, sp: Vector2, label: String, text_col: Color, border_col: Color, fade: float, active: bool) -> bool:
	var icon_rect: Rect2 = Rect2(sp.x - 7.0, sp.y - 7.0, 14.0, 14.0)
	var icon_vis: float = _world_label_fade(icon_rect)
	if icon_vis <= 0.01:
		return false
	var norm: String = label.replace("ß", "SS").to_upper()
	var gap_px: int = 2 if norm.length() <= 13 else 1
	var pw: float = float(_carto_text_width(norm, false, gap_px) + (12 if active else 10))
	var ph: float = 13.0 if active else 12.0
	var chosen_center: Vector2 = sp + Vector2(0.0, 14.0)
	var cand: Rect2 = Rect2(roundf(chosen_center.x - pw * 0.5), roundf(chosen_center.y - ph * 0.5), pw, ph)
	var lbl_vis: float = _world_label_fade(cand)
	var show_plaque: bool = lbl_vis > 0.01 and not _world_rect_overlaps(cand, 2.0)
	var ic_fade: float = fade * icon_vis
	match icon_kind:
		&"citadel": _draw_citadel_crest(sp, active, ic_fade)
		&"hearth": _draw_hearth_beacon(sp, active, ic_fade)
		&"arena": _draw_rift_arena_sigil(sp, active, ic_fade, false)
		&"rift": _draw_rift_arena_sigil(sp, active, ic_fade, true)
		&"star": _draw_star_crest(sp, text_col, ic_fade)
		_: _draw_waystone_diamond(sp, true, active, ic_fade)
	_placed_world_rects.append(icon_rect)
	if show_plaque:
		var prect: Rect2 = _draw_carto_plaque(norm, chosen_center, text_col, border_col, fade * lbl_vis, active, gap_px - 1)
		_placed_world_rects.append(prect)
		_continent_label_rects.append(prect.merge(icon_rect))
	else:
		_continent_label_rects.append(icon_rect)
	return true


func _draw_focused_locked_zone_outline(fade: float) -> void:
	if _atlas == null or _current_level != LEVEL_CONTINENT or _focused_locked_zone_t <= 0.01 or _focused_locked_zone_id == &"":
		return
	var z: Atlas.Zone = _atlas.zone(_focused_locked_zone_id)
	if z == null or z.footprint.size() < 3:
		return
	var pulse: float = clampf(_focused_locked_zone_t, 0.0, 1.0) * (0.65 + 0.35 * sin(_time * 8.0)) * fade
	var pts: PackedVector2Array = PackedVector2Array()
	for fp: Vector2 in z.footprint:
		pts.append(_to_screen(fp))
	pts.append(pts[0])
	_overlay.draw_polyline(pts, Color(VineStyle.VOID_GLOW, 0.9 * pulse), 2.0)


func _draw_continent_zone_labels(fade: float) -> void:
	if _atlas == null or (_current_level != LEVEL_CONTINENT and _current_level != LEVEL_WORLD):
		return
	var cont: Atlas.Continent = _atlas.continent(_continent_id)
	if cont == null:
		return

	if _current_level == LEVEL_WORLD:
		var land_b: Rect2 = _continent_land_bounds()
		var sp_world: Vector2 = _to_screen(Vector2(land_b.get_center().x, land_b.end.y + 85.0))
		var est_wr: Rect2 = Rect2(sp_world.x - 36.0, sp_world.y - 7.0, 72.0, 14.0)
		var w_vis: float = _world_label_fade(est_wr)
		if w_vis > 0.01:
			var wrect: Rect2 = _draw_carto_plaque(cont.name.to_upper(), sp_world, Color("f4eeff"), Color("9b84e8"), fade * 0.92 * w_vis, true, 1)
			_placed_world_rects.append(wrect)
			_continent_label_rects.append(wrect)
		return

	var fly_fade: float = 1.0
	if _zoom < 0.14:
		var fp: float = clampf(1.0 - absf((_zoom - 0.090) / 0.028), 0.0, 1.0)
		fly_fade = 1.0 - smoothstep(0.25, 0.72, fp)
	if _veil_fly_active and _veil_fly_stage == 1:
		fly_fade = 0.0
	var vis: float = fade * 0.96 * fly_fade
	if vis <= 0.02:
		return
	var zones_all: Array[Atlas.Zone] = _atlas.zones_of(_continent_id)
	var crest_labeled_zones: Dictionary = {}
	var c_data: Dictionary = _ensure_continent_textures(_continent_id)
	var rift_tile: Vector2 = c_data.get("rift_pos", Vector2(2050.0, 950.0)) as Vector2
	var rift_rad: float = float(c_data.get("rift_radius", 0.0))

	# 1. Iconic Website-Style Continent Landmark Crests & Framed Plaques
	#    a) Active Player / Camp Hearth Beacon (e.g. Windkap Silberbucht camp or Glimmrast home)
	if _player_zone != &"" and _zone_status_int(_player_zone) >= 2:
		var pz: Atlas.Zone = _atlas.zone(_player_zone)
		if pz != null:
			var camp_tile: Vector2 = _player_tile
			var zd_p: Dictionary = _ensure_zone_textures(_player_zone)
			var cfs: PackedVector2Array = zd_p.get("campfires", PackedVector2Array()) as PackedVector2Array
			if not cfs.is_empty():
				camp_tile = cfs[0]
			var hearth_lbl: String = "%s · LAGER" % pz.name.to_upper()
			if _player_zone == &"glimmrast":
				hearth_lbl = "DEIN HOF · TAG %d" % maxi(1, int(TimeManager.day) if TimeManager.get("day") != null else 1)
			var h_act: bool = (_hovered_zone_id == _player_zone)
			if _place_continent_crest_plaque(&"hearth", _to_screen(camp_tile), hearth_lbl, Color("f7d98b"), Color("d8a955"), vis, h_act):
				crest_labeled_zones[_player_zone] = true

	#    b) Hallgrat Citadel Crest, Schieferkessel / Boss Arena, Kristallgrat Wonder
	for z: Atlas.Zone in zones_all:
		var st_z: int = _zone_status_int(z.id)
		if st_z <= 0:
			continue
		var z_act: bool = (_hovered_zone_id == z.id)
		if z.id == &"hallgrat" or z.kind == &"settlement":
			var cit_name: String = "HALLGRAT" if z.id == &"hallgrat" else z.name.to_upper()
			if _place_continent_crest_plaque(&"citadel", _to_screen(z.center()), cit_name, Color("e6dcff"), Color("a490e8"), vis, z_act):
				crest_labeled_zones[z.id] = true
		elif z.id == &"glimmrast" and _player_zone != &"glimmrast" and st_z >= 2:
			if _place_continent_crest_plaque(&"hearth", _to_screen(z.center()), "GLIMMRAST · HEIMSTATT", Color("f7d98b"), Color("d8a955"), vis, z_act):
				crest_labeled_zones[z.id] = true
		elif z.id == &"hexenwald_kern" and st_z >= 2:
			var arena_pos: Vector2 = z.center()
			var arena_lbl: String = "DER SCHIEFERKESSEL"
			for lm: Atlas.Landmark in z.landmarks:
				if lm.kind != &"veil_thread":
					arena_pos = lm.pos
					if not lm.name.is_empty() and lm.name.length() <= 24:
						arena_lbl = lm.name.to_upper()
					break
			if _place_continent_crest_plaque(&"arena", _to_screen(arena_pos), arena_lbl, Color("ffa6b2"), Color("d95b72"), vis, z_act):
				crest_labeled_zones[z.id] = true
		elif (z.id == &"kristallgrat" or z.kind == &"wonder") and st_z >= 2:
			var won_pos: Vector2 = z.center()
			for lm: Atlas.Landmark in z.landmarks:
				if lm.kind == &"vista" or lm.kind == &"crystal" or lm.kind == &"waystone":
					won_pos = lm.pos
					break
			if _place_continent_crest_plaque(&"star", _to_screen(won_pos), z.name.to_upper(), Color("ffe08a"), Color("caa24e"), vis, z_act):
				crest_labeled_zones[z.id] = true

	#    c) The Great Rift Sigil on eastern Varnholm (when Varnholm sighted/entered)
	if rift_rad > 10.0 and (_zone_status_int(&"varnholm") >= 1 or _preview_reveal_all):
		var rift_sp: Vector2 = _to_screen(rift_tile + Vector2(-8.0, 26.0))
		_place_continent_crest_plaque(&"rift", rift_sp, "DER GROSSE RISS", Color("f5b0ff"), Color("c850df"), vis, _hovered_zone_id == &"varnholm")

	# 2. Grand Landstrich / Region Watermarks (DIE LICHTUNG / WIESENLANDE & HEXENWALD / SCHATTENWALD style!)
	var c_meta: Dictionary = c_data.get("meta", {}) as Dictionary if c_data.get("meta") is Dictionary else {}
	var has_engraved_old_names: bool = (c_meta.get("old_names") is Array) and not (c_meta.get("old_names") as Array).is_empty()
	var use_display_reg: bool = _zoom >= 0.16
	for reg_v: Variant in cont.regions:
		if not (reg_v is Dictionary):
			continue
		var reg: Dictionary = reg_v as Dictionary
		var rid_sn: StringName = StringName(String(reg.get("id", "")))
		var weighted_sum: Vector2 = Vector2.ZERO
		var total_w: float = 0.0
		var max_st: int = 0
		var reg_hovered: bool = false
		var reg_zones: Dictionary = {}
		var zone_centers: Array[Vector2] = []
		for z: Atlas.Zone in zones_all:
			if z.region == rid_sn:
				reg_zones[z.id] = true
				zone_centers.append(_to_screen(z.center()))
				var w_area: float = maxf(z.bbox.get_area(), 100.0)
				weighted_sum += z.center() * w_area
				total_w += w_area
				max_st = maxi(max_st, _zone_status_int(z.id))
				if z.id == _hovered_zone_id:
					reg_hovered = true
		if total_w <= 0.0:
			continue
		# Avoid duplicating Stone-Setter old_names carved into engraving.png until a zone in the region is entered
		if max_st < 2 and has_engraved_old_names:
			continue
		var reg_tile: Vector2 = weighted_sum / total_w
		if _atlas.zone_at_tile(_continent_id, reg_tile) == &"":
			var best_d: float = INF
			for z: Atlas.Zone in zones_all:
				if z.region == rid_sn:
					var zc_t: Vector2 = _polygon_visual_center(z.footprint) if z.footprint.size() >= 3 else z.center()
					var d_z: float = zc_t.distance_squared_to(reg_tile)
					if d_z < best_d:
						best_d = d_z
						reg_tile = zc_t
		var reg_sp: Vector2 = _to_screen(reg_tile)

		var pair: Dictionary = _region_display_pair(reg, max_st)
		var r_title: String = String(pair["title"])
		var r_sub: String = String(pair["sub"])
		var is_disp: bool = use_display_reg and (max_st >= 1)
		var est_tw: int = _carto_text_width(r_title, is_disp, 3 if is_disp else 2)
		var est_sw: int = _carto_text_width(r_sub, false, 2 if r_sub.length() <= 18 else 1)
		var est_w: float = float(maxi(est_tw, est_sw) + 10)
		var est_h: float = float((9 if is_disp else 7) + 14)
		var cand_r: Rect2 = Rect2(reg_sp.x - est_w * 0.5, reg_sp.y - est_h * 0.5, est_w, est_h)
		var reg_vis: float = _world_label_fade(cand_r)
		if reg_vis <= 0.01 or _world_rect_overlaps(cand_r, 3.0):
			continue

		var t_col: Color = Color("ffe29a") if reg_hovered else (Color("f6f0ff") if max_st >= 2 else (Color("dfd6f5") if max_st == 1 else Color("b4abd2")))
		var s_col: Color = Color("f0c978") if reg_hovered else (Color("c2b6ea") if max_st >= 1 else Color("857ca6"))
		var r_col: Color = Color("e6bd68") if reg_hovered else (Color("9684ce") if max_st >= 1 else Color("635a82"))
		var r_fade: float = (vis if max_st >= 1 else (vis * 0.84)) * reg_vis
		var wm_rect: Rect2 = _draw_region_watermark(r_title, r_sub, reg_sp, is_disp, t_col, s_col, r_col, r_fade)
		_placed_world_rects.append(wm_rect)
		_continent_label_rects.append(wm_rect)

	# 3. Individual Discovered Zone Plaques (strictly world-fixed — never slide at screen edges!)
	var show_all_zone_plaques: bool = _zoom >= 0.27
	var ordered: Array[Atlas.Zone] = zones_all.duplicate()
	ordered.sort_custom(func(a: Atlas.Zone, b: Atlas.Zone) -> bool:
		return _zone_status_int(a.id) > _zone_status_int(b.id)
	)
	for z: Atlas.Zone in ordered:
		var st: int = _zone_status_int(z.id)
		if st <= 0 or crest_labeled_zones.has(z.id):
			continue
		if not show_all_zone_plaques and st == 2 and _preview_reveal_all:
			if z.id != _hovered_zone_id:
				continue
		var z_tile: Vector2 = _polygon_visual_center(z.footprint) if z.footprint.size() >= 3 else z.center()
		var at: Vector2 = _to_screen(z_tile)
		var z_lbl: String = z.name.to_upper()
		var z_emph: bool = (z.id == _hovered_zone_id)
		var z_tcol: Color = Color("f2ecff") if st == 2 else Color("cbc2e6")
		var z_bcol: Color = Color("9682dc") if st == 2 else Color("6e629c")
		var pw_est: float = float(_carto_text_width(z_lbl, false, 2 if z_lbl.length() <= 13 else 1) + 12)
		var cr: Rect2 = Rect2(at.x - pw_est * 0.5, at.y - 6.0, pw_est, 12.0)
		var z_vis: float = _world_label_fade(cr)
		if z_vis <= 0.01 or _world_rect_overlaps(cr, 2.0):
			continue
		var prect_z: Rect2 = _draw_carto_plaque(z_lbl, at, z_tcol, z_bcol, vis * (0.96 if st == 2 else 0.86) * z_vis, z_emph)
		_placed_world_rects.append(prect_z)
		_continent_label_rects.append(prect_z)

	# 4. Crisp 1:1 Screen-Space Stone-Setter old_names (strictly world-fixed — fade cleanly when panned off screen!)
	var old_names_arr: Array = c_meta.get("old_names", []) as Array if c_meta.get("old_names") is Array else []
	if not old_names_arr.is_empty():
		var region_old_lookup: Dictionary = {}
		var region_max_status: Dictionary = {}
		for reg_v2: Variant in cont.regions:
			if reg_v2 is Dictionary:
				var rd: Dictionary = reg_v2 as Dictionary
				var rid2: StringName = StringName(String(rd.get("id", "")))
				var oname: String = String(rd.get("old_name", "")).strip_edges().to_upper()
				if not oname.is_empty():
					region_old_lookup[oname] = rid2
				var mst: int = 0
				for zz: Atlas.Zone in zones_all:
					if zz.region == rid2:
						mst = maxi(mst, _zone_status_int(zz.id))
				region_max_status[rid2] = mst

		for pass_reg_only: bool in [true, false]:
			for on_v: Variant in old_names_arr:
				if not (on_v is Dictionary):
					continue
				var od: Dictionary = on_v as Dictionary
				var o_txt: String = String(od.get("text", "")).strip_edges().to_upper()
				var pos_v: Variant = od.get("pos", [])
				if o_txt.is_empty() or not (pos_v is Array) or (pos_v as Array).size() < 2:
					continue
				var is_reg_old: bool = region_old_lookup.has(o_txt)
				if is_reg_old != pass_reg_only:
					continue
				var pa: Array = pos_v as Array
				var o_tile: Vector2 = Vector2(float(pa[0]), float(pa[1]))
				var z_at: StringName = _atlas.zone_at_tile(_continent_id, o_tile)
				if is_reg_old:
					var own_rid: StringName = region_old_lookup[o_txt] as StringName
					if int(region_max_status.get(own_rid, 0)) >= 2:
						continue
					if z_at != &"" and _zone_status_int(z_at) >= 2:
						continue
				else:
					if z_at != &"" and _zone_status_int(z_at) >= 1:
						continue
				var o_sp: Vector2 = _to_screen(o_tile)
				var disp_txt: String = o_txt
				var tw_px: int = PixelText.width(disp_txt)
				var th_px: int = PixelText.HEIGHT + (4 if is_reg_old else 0)
				var pad_x: float = 5.0 if is_reg_old else 3.0
				var cr_o: Rect2 = Rect2(o_sp.x - float(tw_px) * 0.5 - pad_x, o_sp.y - float(th_px) * 0.5 - 2.0, float(tw_px) + pad_x * 2.0, float(th_px) + 4.0)
				var o_vis_edge: float = _world_label_fade(cr_o)
				if o_vis_edge <= 0.01 or _world_rect_overlaps(cr_o, 3.0):
					continue
				var eff_vis: float = vis * o_vis_edge
				var draw_pos: Vector2i = Vector2i(roundi(o_sp.x - float(tw_px) * 0.5), roundi(o_sp.y - float(th_px) * 0.5))
				var ink_shadow: Color = Color("080412", (0.94 if is_reg_old else 0.88) * eff_vis)
				var stone_col: Color = Color("cfc6ea", 0.92 * eff_vis) if is_reg_old else Color("9e94bf", 0.80 * eff_vis)
				PixelText.draw(_overlay, disp_txt, draw_pos + Vector2i(1, 1), ink_shadow)
				PixelText.draw(_overlay, disp_txt, draw_pos, stone_col, ink_shadow)
				if is_reg_old:
					var rw: float = clampf(float(tw_px) * 0.76, 18.0, 62.0)
					var rx: float = roundf(o_sp.x - rw * 0.5)
					var ry: float = float(draw_pos.y + PixelText.HEIGHT + 1)
					_overlay.draw_rect(Rect2(rx, ry + 1.0, rw, 1.0), Color("080412", 0.82 * eff_vis))
					_overlay.draw_rect(Rect2(rx, ry, rw, 1.0), Color("796ea1", 0.64 * eff_vis))
					_overlay.draw_rect(Rect2(roundf(o_sp.x), ry, 1.0, 1.0), Color("d6cef0", 0.86 * eff_vis))
				var rec_o: Rect2 = Rect2(float(draw_pos.x) - 3.0, float(draw_pos.y) - 1.0, float(tw_px) + 6.0, float(th_px) + 2.0)
				_placed_world_rects.append(rec_o)
				_continent_label_rects.append(rec_o)


func _draw_zone_place_watermarks(fade: float) -> void:
	if _atlas == null or (_current_level != LEVEL_ZONE and _current_level != LEVEL_ORT):
		return
	var is_disp: bool = _current_level == LEVEL_ORT
	# 1. Draw carved Stone-Setter territory watermark on any visible unentered zone (world-fixed, zero duplicate header!)
	if _continent_unlocked and _active_zone_id != &"":
		var az: Atlas.Zone = _atlas.zone(_active_zone_id)
		if az != null and _zone_status_int(az.id) < 2:
			var zc_tile: Vector2 = _polygon_visual_center(az.footprint) if az.footprint.size() >= 3 else az.center()
			var zc_sp: Vector2 = _to_screen(zc_tile)
			var engr_name: String = az.name.to_upper() if _zone_status_int(az.id) == 1 else String(az.raw.get("old_name", az.name)).to_upper()
			var engr_sub: String = "GESICHTETES GRENZLAND" if _zone_status_int(az.id) == 1 else "STEINSETZER-GRAVUR"
			var etw: int = _carto_text_width(engr_name, true, 3)
			var esw: int = _carto_text_width(engr_sub, false, 2)
			var erw: float = float(maxi(etw, esw) + 12)
			var erh: float = 24.0
			var er_box: Rect2 = Rect2(zc_sp.x - erw * 0.5, zc_sp.y - erh * 0.5, erw, erh)
			var evis: float = _world_label_fade(er_box)
			if evis > 0.01 and not _world_rect_overlaps(er_box, 3.0):
				var t_c: Color = Color("dfd6f5") if _zone_status_int(az.id) == 1 else Color("cfc6ea")
				var wmr: Rect2 = _draw_region_watermark(engr_name, engr_sub, zc_sp, true, t_c, Color("948ab8"), Color("6a6091"), fade * 0.90 * evis)
				_placed_world_rects.append(wmr)

	# 2. Draw discovered place watermarks for the rendered entered zone (e.g. WINDKAP stays labeled even near seams!)
	var render_zid: StringName = _resolve_render_zone_id()
	var z: Atlas.Zone = _atlas.zone(render_zid) if render_zid != &"" else null
	if z == null or (_continent_unlocked and _zone_status_int(z.id) < 2):
		return

	var vis: float = fade * (0.94 if is_disp else 0.90)
	for pl: Atlas.Place in z.places:
		if not _is_place_seen(pl.id):
			continue
		var center_tile: Vector2 = _polygon_visual_center(pl.poly) if pl.poly.size() >= 3 else pl.bbox.get_center()
		if not _preview_reveal_all and _discovery != null and not _discovery.is_reveal_all():
			if not _discovery.is_seen(center_tile) and center_tile.distance_to(_player_tile) > 64.0:
				continue
		var sp: Vector2 = _to_screen(center_tile)
		var p_name: String = pl.name.to_upper()
		var gap_p: int = 3 if is_disp else 2
		var tw: int = _carto_text_width(p_name, is_disp, gap_p)
		var th_glyph: int = 9 if is_disp else 7
		var th: int = th_glyph + 5
		var cand_r: Rect2 = Rect2(sp.x - float(tw) * 0.5 - 4.0, sp.y - float(th) * 0.5, float(tw) + 8.0, float(th))
		var p_vis: float = _world_label_fade(cand_r)
		if p_vis <= 0.01 or _world_rect_overlaps(cand_r, 3.0):
			continue
		var eff_p: float = vis * p_vis
		var top_y: float = roundf(sp.y - float(th) * 0.5)
		var cx: float = roundf(sp.x)
		_draw_carto_text(p_name, Vector2(cx - float(tw) * 0.5, top_y), is_disp, gap_p, Color("f2ecff", eff_p), Color("080410", 0.96 * eff_p), true)
		var rule_w: float = clampf(float(tw) * 0.68, 18.0, 78.0)
		var ry: float = top_y + float(th_glyph) + 1.0
		_overlay.draw_rect(Rect2(roundf(cx - rule_w * 0.5), ry + 1.0, rule_w, 1.0), Color("080410", 0.80 * eff_p))
		_overlay.draw_rect(Rect2(roundf(cx - rule_w * 0.5), ry, rule_w, 1.0), Color("9482cc", 0.58 * eff_p))
		_placed_world_rects.append(Rect2(cx - float(tw) * 0.5 - 4.0, top_y, float(tw) + 8.0, float(th)))


func _draw_quest_routes_and_arrows(fade: float) -> void:
	if _atlas == null or _markers == null or not _markers.has_method(&"compute_quest_routes"):
		return
	var raw_markers: Array = _collect_markers()
	var quest_markers: Array[Dictionary] = []
	for m: Variant in raw_markers:
		if m is Dictionary and StringName((m as Dictionary).get("category", &"")) == &"quests":
			quest_markers.append(m as Dictionary)
	if quest_markers.is_empty():
		return
	var flags: Dictionary = _director_flags()
	var routes: Array = _markers.call(&"compute_quest_routes", _atlas, _player_zone, _player_tile, quest_markers, flags) as Array
	for r_var: Variant in routes:
		if not (r_var is Dictionary):
			continue
		var r: Dictionary = r_var as Dictionary
		var pts: PackedVector2Array = r.get("path", PackedVector2Array()) as PackedVector2Array
		if pts.size() >= 2:
			for i: int in pts.size() - 1:
				var a: Vector2 = _to_screen(pts[i])
				var b: Vector2 = _to_screen(pts[i + 1])
				var dist: float = a.distance_to(b)
				var steps: int = maxi(int(dist / 5.0), 1)
				for s: int in steps:
					if s % 2 == 0:
						var p: Vector2 = a.lerp(b, float(s) / float(steps)).round()
						if _on_screen(p, 4.0):
							_overlay.draw_rect(Rect2(p, Vector2(2, 2)), Color(VineStyle.WARM_GLOW, 0.85 * fade))
		var edge_dir: Vector2 = r.get("edge_dir", Vector2.ZERO) as Vector2
		if edge_dir.length_squared() > 0.01:
			var next_th: Dictionary = r.get("next_threshold", {}) as Dictionary
			var anchor_tile: Vector2 = next_th.get("pos", _player_tile + edge_dir * 40.0) as Vector2
			var sp: Vector2 = _to_screen(anchor_tile)
			var dir: Vector2 = edge_dir.normalized()
			var tip: Vector2 = sp + dir * (7.0 + sin(_time * 4.0) * 1.5)
			var side: Vector2 = Vector2(-dir.y, dir.x)
			_overlay.draw_colored_polygon(PackedVector2Array([tip, sp + side * 4.0 - dir * 3.0, sp - side * 4.0 - dir * 3.0]), Color(VineStyle.WARM_GLOW, 0.9 * fade))


func _draw_peer_route(fade: float) -> void:
	if _peer_route_timer <= 0.01 or _peer_route_pts.size() < 2:
		return
	var r_fade: float = fade * clampf(_peer_route_timer / 1.2, 0.0, 1.0)
	var march: int = int(_time * 10.0)
	for i: int in _peer_route_pts.size() - 1:
		var a: Vector2 = _to_screen(_peer_route_pts[i])
		var b: Vector2 = _to_screen(_peer_route_pts[i + 1])
		var dist: float = a.distance_to(b)
		var steps: int = maxi(int(dist / 4.5), 1)
		for s: int in steps + 1:
			if (s + march) % 3 == 0:
				var p: Vector2 = a.lerp(b, float(s) / float(steps)).round()
				if _on_screen(p, 6.0):
					_overlay.draw_rect(Rect2(p - Vector2.ONE, Vector2(4.0, 4.0)), Color(VineStyle.OUTLINE, 0.85 * r_fade))
					_overlay.draw_rect(Rect2(p, Vector2(2.0, 2.0)), Color("ffe28a", 0.96 * r_fade))
	var end_sp: Vector2 = _to_screen(_peer_route_pts[_peer_route_pts.size() - 1]).round()
	if _on_screen(end_sp, 14.0):
		VineStyle.glow(_overlay, end_sp, 13.0, Color("ffd98a"), 0.50 * r_fade)
		VineStyle.ring(_overlay, end_sp, 6 + int(fposmod(_time * 1.5, 1.0) * 8.0), Color("ffe28a", 0.75 * r_fade), 0.7)


func _collect_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _markers != null and _markers.has_method(&"collect"):
		var ctx: Dictionary = {
			"atlas": _atlas,
			"continent": _continent_id,
			"zone": _resolve_render_zone_id(),
			"player_zone": _player_zone,
			"player_tile": _player_tile,
			"discovery": _discovery,
			"director": _director,
			"level": _current_level,
			"zoom": _zoom,
			"tree": get_tree() if is_inside_tree() else null,
		}
		var collected: Array = _markers.call(&"collect", ctx) as Array
		if _markers.has_method(&"cluster_for_level"):
			collected = _markers.call(&"cluster_for_level", collected, _current_level, _zoom, 20.0) as Array
		for item: Variant in collected:
			if item is Dictionary:
				out.append(item as Dictionary)
		return out

	# Phase A fallback markers from Atlas + local pins + player
	out.append({
		"id": &"player_self",
		"kind": &"self",
		"category": &"players",
		"pos": _player_tile,
		"zone": _player_zone,
		"levels": 15,
		"priority": 100,
		"label": "DU",
		"anim": &"pulse",
		"color": Color("b9f3ee"),
		"data": {},
	})
	if _atlas != null and _active_zone_id != &"":
		var z: Atlas.Zone = _atlas.zone(_active_zone_id)
		if z != null:
			for lm: Atlas.Landmark in z.landmarks:
				out.append({
					"id": lm.id,
					"kind": lm.kind,
					"category": &"waystones" if lm.kind == &"waystone" else &"nature",
					"pos": lm.pos,
					"zone": z.id,
					"levels": 7,
					"priority": 50,
					"label": lm.name,
					"anim": &"",
					"color": Color("7fe3da") if lm.kind == &"waystone" else Color("ffd98a"),
					"data": {},
				})
		var pins: Array = _local_pins.get(_active_zone_id, []) as Array
		for p: Variant in pins:
			if p is Dictionary:
				var pd: Dictionary = p as Dictionary
				var pk_f: StringName = StringName(String(pd.get("kind", "mark")))
				var pk_spec: Dictionary = MapMarkers.pin_kind_spec(pk_f)
				out.append({
					"id": &"pin",
					"kind": &"pin",
					"category": &"pins",
					"pos": pd.get("pos", Vector2.ZERO),
					"zone": _active_zone_id,
					"levels": 7,
					"priority": 60,
					"label": String(pk_spec.get("name", "")),
					"anim": &"",
					"color": pk_spec.get("color", Color("cbaaff")) as Color,
					"data": {"pin_kind": pk_f, "spec": pk_spec},
				})
	return out


func _draw_markers_and_pins(fade: float) -> void:
	var markers: Array[Dictionary] = _collect_markers()
	var bit: int = 1 if _current_level == LEVEL_ORT else (2 if _current_level == LEVEL_ZONE else (4 if _current_level == LEVEL_CONTINENT else 8))
	for m: Dictionary in markers:
		var levels_mask: int = int(m.get("levels", 15))
		if (levels_mask & bit) == 0:
			continue
		var cat: StringName = StringName(m.get("category", &"pins"))
		if not _is_filter_cat_enabled(cat):
			continue
		var pos_tile: Vector2 = m.get("pos", Vector2.ZERO) as Vector2
		var at: Vector2 = _to_screen(pos_tile).round()
		if not _on_screen(at, 12.0):
			if StringName(m.get("kind", &"")) == &"self" or cat == &"players":
				_draw_edge_pointer(at, m.get("color", Color("b9f3ee")) as Color, fade)
			continue
		var col: Color = m.get("color", UiStyle.ACCENT) as Color
		var kind: StringName = StringName(m.get("kind", &""))
		var lbl: String = String(m.get("label", ""))
		var d: Dictionary = m.get("data", {}) as Dictionary if m.get("data") is Dictionary else {}
		var count: int = int(d.get("count", d.get("cluster_count", 1)))
		if kind == &"cluster" and count <= 1 and not lbl.is_empty() and lbl.is_valid_int():
			count = lbl.to_int()
		var is_cluster: bool = kind == &"cluster" or count > 1

		# On KONTINENT / WELT, keep overview clean like the Website Reference (major landmark plaques own overview)
		if _current_level == LEVEL_CONTINENT or _current_level == LEVEL_WORLD:
			if kind == &"self":
				continue
			if is_cluster and _zoom < 0.34:
				continue
			var full_w: float = 26.0 if is_cluster else 14.0
			var test_icon: Rect2 = Rect2(at - Vector2(7.0, 7.0), Vector2(full_w, 14.0))
			if _rect_overlaps_placed(test_icon, 2.0):
				continue

		var hit_r: Rect2 = Rect2(at - Vector2(7.0, 7.0), Vector2(14.0, 14.0))
		var hovered_m: bool = hit_r.has_point(_cursor)

		# Website-style pixel-art icon per marker kind
		if kind == &"self" or kind == &"player":
			_draw_hero_diamond(at, col, fade)
		elif kind == &"waystone":
			_draw_waystone_diamond(at, true, hovered_m, fade)
		elif kind == &"waystone_sleeping" or cat == &"waystones":
			_draw_waystone_diamond(at, false, hovered_m, fade)
		elif kind == &"pin" or cat == &"pins":
			_draw_pin_marker(at, d, col, hovered_m, fade)
		elif kind == &"campfire" or kind == &"camp" or kind == &"settlement":
			_draw_hearth_beacon(at, hovered_m, fade)
		elif kind == &"hallgrat":
			_draw_citadel_crest(at, hovered_m, fade)
		elif kind == &"arena" or kind == &"danger":
			_draw_rift_arena_sigil(at, hovered_m, fade, false)
		elif kind == &"quest" or cat == &"quests" or kind == &"vista" or kind == &"lighthouse" or kind == &"ruin" or kind == &"wonder":
			_draw_star_crest(at, col, fade)
		else:
			_draw_waystone_diamond(at, false, hovered_m, fade)
			_overlay.draw_rect(Rect2(at - Vector2(2.0, 2.0), Vector2(5.0, 5.0)), Color(col, fade))
			_overlay.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, fade))

		_placed_overlay_rects.append(Rect2(at - Vector2(6.0, 6.0), Vector2(12.0, 12.0)))

		if is_cluster:
			var badge_txt: String = str(maxi(count, 2))
			var bw: float = float(PixelText.width(badge_txt) + 6)
			var bx: float = roundf(at.x + 5.0)
			var by: float = roundf(at.y - 7.0)
			var brect: Rect2 = Rect2(bx, by, bw, 10.0)
			_overlay.draw_rect(Rect2(bx + 1.0, by + 1.0, bw, 10.0), Color("06030d", 0.80 * fade))
			_overlay.draw_rect(brect, Color("0b0715", 0.95 * fade))
			_overlay.draw_rect(Rect2(bx, by, bw, 1.0), Color(col, 0.80 * fade))
			_overlay.draw_rect(Rect2(bx, by + 9.0, bw, 1.0), Color(col.darkened(0.25), 0.75 * fade))
			_text(badge_txt, Vector2i(int(bx) + 3, int(by) + 2), VineStyle.PETAL, fade)
			_placed_overlay_rects.append(brect)
		elif not lbl.is_empty() and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE):
			var show_lbl: bool = hovered_m or _current_level == LEVEL_ORT or kind == &"waystone" or kind == &"quest" or cat == &"quests" or kind == &"campfire" or kind == &"ruin" or kind == &"vista"
			if kind == &"self" and not hovered_m and _current_level != LEVEL_ORT:
				show_lbl = false
			if show_lbl:
				var p_text: Color = col.lightened(0.22)
				var p_bord: Color = col
				var norm_l: String = lbl.replace("ß", "SS").to_upper()
				var gap_l: int = 2 if norm_l.length() <= 13 else 1
				var pw_l: float = float(_carto_text_width(norm_l, false, gap_l) + (12 if hovered_m else 10))
				var cm: Vector2 = at + Vector2(0.0, 13.0)
				var cr_m: Rect2 = Rect2(roundf(cm.x - pw_l * 0.5), roundf(cm.y - 6.0), pw_l, 12.0)
				var m_vis: float = _world_label_fade(cr_m)
				if m_vis > 0.01 and not _world_rect_overlaps(cr_m, 2.0):
					var prect_m: Rect2 = _draw_carto_plaque(norm_l, cm, p_text, p_bord, fade * m_vis, hovered_m, gap_l - 1)
					_placed_world_rects.append(prect_m)
					hit_r = hit_r.merge(prect_m)
		_marker_hit_rects.append({"rect": hit_r, "marker": m})


func _draw_pin_marker(at: Vector2, d: Dictionary, col: Color, hovered: bool, fade: float) -> void:
	var pk: StringName = StringName(String(d.get("pin_kind", "mark")))
	if pk == &"coast_wave" and ATLAS_ELEMENTS_TEX != null:
		VineStyle.glow(_overlay, at, 11.0 if hovered else 8.0, col, (0.45 if hovered else 0.28) * fade)
		_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(at - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), Rect2(76.0, 4.0, 16.0, 16.0), Color(1.0, 1.0, 1.0, fade))
		return
	var spec: Dictionary = MapMarkers.pin_kind_spec(pk)
	var rows: Array = spec.get("rows", PIN_KIND_LIST[0]["rows"]) as Array
	VineStyle.glow(_overlay, at, 9.0 if hovered else 7.0, col, (0.40 if hovered else 0.24) * fade)
	_draw_pin_glyph(rows, at, col, fade)


func _draw_pin_glyph(rows: Array, at: Vector2, col: Color, fade: float) -> void:
	var origin: Vector2 = (at - Vector2(2.0, 2.0)).round()
	for pass_i: int in 2:
		for ry: int in mini(rows.size(), 5):
			var r_str: String = String(rows[ry])
			for rx: int in mini(r_str.length(), 5):
				if r_str.substr(rx, 1) != "X":
					continue
				if pass_i == 0:
					for off_p: Vector2 in [Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]:
						_overlay.draw_rect(Rect2(origin + Vector2(float(rx), float(ry)) + off_p, Vector2.ONE), Color(VineStyle.OUTLINE, 0.92 * fade))
				else:
					_overlay.draw_rect(Rect2(origin + Vector2(float(rx), float(ry)), Vector2.ONE), Color(col, fade))


func _draw_peer_join_card(fade: float, void_level: float) -> void:
	if _selected_peer_marker.is_empty():
		return
	var pos_tile: Vector2 = _selected_peer_marker.get("pos", _center_tile) as Vector2
	var anchor: Vector2 = _to_screen(pos_tile).round()
	var m_data: Dictionary = _selected_peer_marker.get("data", {}) as Dictionary if _selected_peer_marker.get("data") is Dictionary else {}
	var peer_id: int = int(m_data.get("peer_id", -1))
	var pname: String = String(m_data.get("player_name", String(_selected_peer_marker.get("label", "MITSPIELER")))).to_upper()
	var ptitle: String = String(m_data.get("title", "")).to_upper()
	var t_zone: StringName = StringName(String(_selected_peer_marker.get("zone", "")))
	if t_zone == &"" and _atlas != null:
		t_zone = _atlas.zone_at_tile(_continent_id, pos_tile)
	var z_obj: Atlas.Zone = _atlas.zone(t_zone) if (_atlas != null and t_zone != &"") else null
	var z_name: String = z_obj.name.to_upper() if z_obj != null else "UNBEKANNT"
	var ws_awake: bool = false
	if _coop_node != null and is_instance_valid(_coop_node) and _coop_node.has_method(&"can_join_peer"):
		var cv: Variant = _coop_node.call(&"can_join_peer", peer_id)
		if cv is Dictionary and bool((cv as Dictionary).get("ok", false)):
			ws_awake = true
	if not ws_awake and is_inside_tree() and t_zone != &"":
		var wm_chk: Waystones = Waystones.of(get_tree())
		if wm_chk != null and not wm_chk.awake_waystone_in_zone(t_zone).is_empty():
			ws_awake = true
	var sub_txt: String = "WEGSTEIN ERWACHT" if ws_awake else "GOLDENE ROUTE"
	var card_w: float = maxf(138.0, float(maxi(PixelText.width(pname), PixelText.width(ptitle)) + 24))
	card_w = maxf(card_w, float(PixelText.width(z_name + " - " + sub_txt) + 20))
	var card_h: float = 64.0 if not ptitle.is_empty() else 54.0
	var vs: Vector2 = _view_size()
	var at: Vector2 = (anchor + Vector2(14.0, -card_h * 0.5)).clamp(Vector2(66.0, 44.0), vs - Vector2(card_w + 26.0, card_h + 36.0)).round()
	var box: Rect2 = Rect2(at, Vector2(card_w, card_h))
	var tone: Color = _selected_peer_marker.get("color", Color("b9f3ee")) as Color
	if embedded_top_inset > 0.0:
		MenuChrome.draw_slate(_overlay, box, fade)
		MenuChrome.draw_corners(_overlay, box, fade)
	else:
		VineStyle.paper(_overlay, Rect2(box.position + Vector2(2.0, 3.0), box.size), fade * 0.35, 1.0, 137)
		VineStyle.paper(_overlay, box, fade, void_level, 137)
	_text(pname, Vector2i(int(at.x) + 8, int(at.y) + 7), tone.lightened(0.2), fade)
	var info_y: int = int(at.y) + 17
	if not ptitle.is_empty():
		_text("- %s -" % ptitle, Vector2i(int(at.x) + 8, info_y), Color("ffd98a"), fade)
		info_y += 10
	_text("%s - %s" % [z_name, sub_txt], Vector2i(int(at.x) + 8, info_y), UiStyle.TEXT_DIM, fade)
	var btn_rect: Rect2 = Rect2(at.x + 8.0, at.y + card_h - 19.0, card_w - 16.0, 13.0)
	var hov_btn: bool = btn_rect.has_point(_cursor)
	var btn_col: Color = Color("4fe3c1") if ws_awake else Color("ffd98a")
	if embedded_top_inset > 0.0:
		MenuChrome.draw_button(_overlay, btn_rect, "ZU IHM", hov_btn, true, false, false, fade)
	else:
		if hov_btn:
			VineStyle.glow(_overlay, btn_rect.get_center(), 18.0, btn_col, 0.35 * fade)
		VineStyle.plate(_overlay, btn_rect, "ZU IHM", btn_col if hov_btn else btn_col.darkened(0.28), VineStyle.PETAL, fade, void_level * 0.4)
	_peer_join_rect = btn_rect


func _draw_silvercoast_frame(fade: float) -> void:
	if ATLAS_ELEMENTS_TEX == null:
		return
	var vs: Vector2 = _view_size()
	var shimmer: float = 0.88 + 0.12 * sin(_time * 1.8)
	var tint: Color = Color(0.94, 0.99, 1.0, 0.92 * shimmer * fade)
	var x_left_end: float = vs.x * 0.5 - 86.0
	var x_pos: float = 26.0
	while x_pos + 32.0 <= x_left_end:
		_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(x_pos, 3.0, 32.0, 12.0), Rect2(116.0, 44.0, 32.0, 12.0), tint)
		_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(vs.x - x_pos - 32.0, 3.0, 32.0, 12.0), Rect2(116.0, 44.0, 32.0, 12.0), tint)
		x_pos += 32.0
	var y_pos: float = 28.0
	while y_pos + 32.0 <= vs.y - 32.0:
		_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(2.0, y_pos, 12.0, 32.0), Rect2(152.0, 44.0, 12.0, 32.0), Color(tint, tint.a * 0.72))
		_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(vs.x - 14.0, y_pos, 12.0, 32.0), Rect2(152.0, 44.0, 12.0, 32.0), Color(tint, tint.a * 0.72))
		y_pos += 40.0
	_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(2.0, 2.0, 24.0, 24.0), Rect2(4.0, 44.0, 24.0, 24.0), tint)
	_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(vs.x - 26.0, 2.0, 24.0, 24.0), Rect2(32.0, 44.0, 24.0, 24.0), tint)
	_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(2.0, vs.y - 26.0, 24.0, 24.0), Rect2(60.0, 44.0, 24.0, 24.0), tint)
	_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2(vs.x - 26.0, vs.y - 26.0, 24.0, 24.0), Rect2(88.0, 44.0, 24.0, 24.0), tint)


func _draw_hero_diamond(at: Vector2, tone: Color, fade: float) -> void:
	var pulse: float = fposmod(_time * 0.8, 1.0)
	VineStyle.glow(_overlay, at, 11.0, tone, 0.55 * fade)
	VineStyle.ring(_overlay, at, 3 + int(pulse * 8.0), Color(tone, (1.0 - pulse) * 0.8 * fade), 0.7)
	for pass_i: int in 2:
		for dy: int in range(-4, 5):
			var half: int = (4 if pass_i == 0 else 3) - absi(dy)
			if half < 0 or (pass_i == 1 and absi(dy) > 3):
				continue
			_overlay.draw_rect(Rect2(at.x - half, at.y + dy, half * 2 + 1, 1), Color(VineStyle.OUTLINE, fade) if pass_i == 0 else Color(tone.lerp(VineStyle.PETAL, 0.4), fade))
	_overlay.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, fade))


func _draw_edge_pointer(target: Vector2, tone: Color, fade: float) -> void:
	var vs: Vector2 = _view_size()
	var middle: Vector2 = vs * 0.5
	var dir: Vector2 = (target - middle).normalized()
	var half: Vector2 = middle - Vector2(30, 30)
	var k: float = minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at: Vector2 = (middle + dir * k).round()
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var tip: Vector2 = at + dir * (6.0 + sin(_time * 4.0) * 1.5)
	_overlay.draw_colored_polygon(PackedVector2Array([tip + dir * 2.0, at + side * 6.0 - dir * 4.0, at - side * 6.0 - dir * 4.0]), Color(VineStyle.OUTLINE, fade))
	_overlay.draw_colored_polygon(PackedVector2Array([tip, at + side * 4.0 - dir * 3.0, at - side * 4.0 - dir * 3.0]), Color(tone, fade))


func _draw_pings(fade: float) -> void:
	for p: Dictionary in _pings:
		var age: float = float(p["age"])
		var max_age: float = float(p["max_age"])
		var u: float = clampf(age / max_age, 0.0, 1.0)
		var at: Vector2 = _to_screen(p["tile"] as Vector2)
		var col: Color = p["color"] as Color
		var r1: int = 4 + int(fposmod(u * 2.0, 1.0) * 20.0)
		var r2: int = 4 + int(fposmod(u * 2.0 + 0.5, 1.0) * 20.0)
		VineStyle.glow(_overlay, at, 14.0, col, (1.0 - u) * 0.7 * fade)
		VineStyle.ring(_overlay, at, r1, Color(col, (1.0 - u) * 0.9 * fade), 0.75)
		VineStyle.ring(_overlay, at, r2, Color(VineStyle.PETAL, (1.0 - u) * 0.65 * fade), 0.55)


func _build_zone_card_data(zone_id: StringName) -> Dictionary:
	var z: Atlas.Zone = _atlas.zone(zone_id) if _atlas != null else null
	if z == null:
		return {}
	var st: int = _zone_status_int(zone_id)
	var status_label: String = "BETRETEN" if st == 2 else ("GESICHTET" if st == 1 else "UNBEKANNT")
	var pct: int = roundi(_zone_explored_ratio(zone_id) * 100.0)
	var ws_count: int = 0
	for lm: Atlas.Landmark in z.landmarks:
		if lm.kind == &"waystone":
			ws_count += 1
	var weather_name: String = "HEITER"
	if not _preview_weather.is_empty():
		weather_name = String(_preview_weather.get("name", WeatherRules.display_name(String(_preview_weather.get("id", "fair")))))
	elif WeatherManager.current != null and WeatherManager.current.has_method(&"display_name"):
		weather_name = String(WeatherManager.current.call(&"display_name"))

	var tod: float = _preview_time if _preview_time >= 0.0 else TimeManager.time_of_day
	var night_amt: float = TimeManager.night_at(tod)
	var moon_str: String = "VOLLMOND" if NightRules.moon_dark(TimeManager.moon_phase()) < 0.25 else ("NEUMOND" if NightRules.moon_dark(TimeManager.moon_phase()) > 0.75 else "MOND")
	var night_str: String = "%s · %s" % [z.danger.to_upper(), moon_str if night_amt > 0.2 else "TAG"]

	var closed_reason: String = ""
	var flags: Dictionary = _director_flags()
	if not _atlas.is_zone_open(zone_id, flags):
		for th: Atlas.Threshold in _atlas.thresholds_of(zone_id):
			if not th.closed_reason.is_empty():
				closed_reason = th.closed_reason
				break
		if closed_reason.is_empty():
			closed_reason = "SCHWELLE NOCH VERSCHLOSSEN"

	return {
		"id": zone_id,
		"name": z.name.to_upper() if st > 0 else "UNERKUNDETES GEBIET",
		"subtitle": z.subtitle if st > 0 else "Steinsetzer-Gravur",
		"kind": String(z.kind).to_upper(),
		"size_class": z.size_class,
		"explored_pct": pct,
		"status": status_label,
		"waystones": ws_count,
		"weather": weather_name.to_upper(),
		"night": night_str,
		"danger": z.danger.to_upper(),
		"closed_reason": closed_reason.to_upper(),
	}


func _draw_zone_hover_card(card: Dictionary, fade: float) -> void:
	if card.is_empty():
		return
	var ease_t: float = 1.0 - pow(1.0 - _hover_zone_t, 3.0)
	var alpha: float = fade * ease_t
	var void_level: float = VineStyle.void_amount() if _preview_time < 0.0 else TimeManager.night_at(_preview_time)
	var title: String = String(card.get("name", ""))
	var subtitle: String = String(card.get("subtitle", ""))
	var line1: String = "%s · KLASSE %s · %s %d%%" % [String(card.get("kind", "")), String(card.get("size_class", "M")), String(card.get("status", "")), int(card.get("explored_pct", 0))]
	var line2: String = "WEGSTEINE: %d · WETTER: %s" % [int(card.get("waystones", 0)), String(card.get("weather", ""))]
	var line3: String = "NACHT: %s" % String(card.get("night", ""))
	var closed: String = String(card.get("closed_reason", ""))

	var w: float = maxf(168.0, float(PixelText.width(title) * 2 + 24))
	w = maxf(w, float(maxi(PixelText.width(line1), PixelText.width(line2)) + 24))
	if not closed.is_empty():
		w = maxf(w, float(PixelText.width(closed) + 24))
	var h: float = 82.0 + (12.0 if not closed.is_empty() else 0.0)
	var vs: Vector2 = _view_size()
	var at: Vector2 = (_cursor + Vector2(16.0, -h * 0.5)).clamp(Vector2(68.0, 46.0), vs - Vector2(w + 26.0, h + 38.0)).round()
	var box: Rect2 = Rect2(at, Vector2(w, h))
	var salt: int = absi(title.hash()) % 997

	if embedded_top_inset > 0.0:
		MenuChrome.draw_slate(_overlay, box, alpha)
		MenuChrome.draw_corners(_overlay, box, alpha)
	else:
		VineStyle.paper(_overlay, Rect2(box.position + Vector2(2, 3), box.size), alpha * 0.35, 1.0, salt)
		VineStyle.paper(_overlay, box, alpha, void_level, salt)

	_overlay.draw_set_transform(at + Vector2(10, 8), 0.0, Vector2(2.0, 2.0))
	PixelText.draw(_overlay, title, Vector2i.ZERO, Color(MenuChrome.COL_GOLD_HOT if embedded_top_inset > 0.0 else VineStyle.WARM_GLOW.lerp(VineStyle.PETAL, 0.3), alpha), Color(VineStyle.OUTLINE, alpha))
	_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_text(subtitle.to_upper(), Vector2i(at + Vector2(10, 24)), Color(UiStyle.TEXT_DIM, 0.95), alpha)
	if embedded_top_inset > 0.0:
		MenuChrome.draw_divider(_overlay, box.get_center().x, at.y + 31.0, w - 20.0, alpha)
	else:
		for x: int in range(10, int(w) - 10):
			_overlay.draw_rect(Rect2(at + Vector2(x, 34), Vector2.ONE), Color(VineStyle.BARK_LIGHT, (0.42 if x % 3 == 0 else 0.18) * alpha))

	_text(line1, Vector2i(at + Vector2(10, 40)), Color(UiStyle.TEXT, 0.95), alpha)
	_text(line2, Vector2i(at + Vector2(10, 51)), Color(UiStyle.ACCENT, 0.92), alpha)
	_text(line3, Vector2i(at + Vector2(10, 62)), Color(VineStyle.LEAF_VOID_LIGHT, 0.90), alpha)
	if not closed.is_empty():
		_text(closed, Vector2i(at + Vector2(10, 73)), Color("ff5f8a"), alpha)
	if embedded_top_inset <= 0.0:
		VineStyle.leaf(_overlay, at + Vector2(w - 6, 8), -1, -1, 3, Color(VineStyle.LEAF, alpha), Color(VineStyle.LEAF_LIGHT, alpha))


func _draw_vine_lock_flash(fade: float, void_level: float) -> void:
	var vs: Vector2 = _view_size()
	var a: float = _limit_bump_t * fade
	var col: Color = VineStyle.LEAF.lerp(VineStyle.VOID_GLOW, void_level)
	_overlay.draw_rect(Rect2(0, 0, vs.x, 3), Color(col, 0.75 * a))
	_overlay.draw_rect(Rect2(0, vs.y - 3, vs.x, 3), Color(col, 0.75 * a))
	_text_centered("STEINSETZER-TAFEL AM WINDKAP NOETIG", Vector2(vs.x * 0.5, 52.0), Color(VineStyle.WARM_GLOW, a), 1.0)


func _draw_frame_ui(fade: float, void_level: float) -> void:
	var vs: Vector2 = _view_size()
	var reach: float = clampf((_open_t - 0.15) / 0.55, 0.0, 1.0)

	# Top tag & active zone header + exploration flower
	var z: Atlas.Zone = _atlas.zone(_active_zone_id) if (_atlas != null and _active_zone_id != &"") else null
	var center_zid: StringName = _atlas.zone_at_tile(_continent_id, _center_tile) if _atlas != null else _active_zone_id
	var over_open_sea: bool = _continent_unlocked and center_zid == &"" and (z == null or not z.bbox.grow(28.0).has_point(_center_tile))
	var unentered_zone: bool = z != null and _continent_unlocked and _zone_status_int(z.id) < 2
	var header_name: String = z.name.to_upper() if z != null else "ATLAS"
	var cont_obj: Atlas.Continent = _atlas.continent(_continent_id) if _atlas != null else null
	if _current_level == LEVEL_WORLD or _current_level == LEVEL_CONTINENT:
		header_name = cont_obj.name.to_upper() if cont_obj != null else "ALTMARK"
	elif over_open_sea:
		header_name = "DAS WEITE MEER"
	elif unentered_zone and z != null:
		# Show Landstrich / Region in top tag so the territory's own carved Stone-Setter name never duplicates on screen!
		header_name = cont_obj.name.to_upper() if cont_obj != null else "ALTMARK"
		if cont_obj != null:
			for reg_h: Variant in cont_obj.regions:
				if reg_h is Dictionary and StringName(String((reg_h as Dictionary).get("id", ""))) == z.region:
					var rh_name: String = String((reg_h as Dictionary).get("name", "")).strip_edges().to_upper()
					if not rh_name.is_empty():
						header_name = rh_name
					break
	var top_y: float = embedded_top_inset
	var codex_hud: bool = embedded_top_inset > 0.0
	_home_btn_rect = Rect2()
	if codex_hud:
		# Sleek Obsidian/Gold Cartographer Header Banner
		var sub_txt: String = ""
		if over_open_sea and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE):
			sub_txt = "UMSPÜLT DIE ALTE MARK"
		elif unentered_zone and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE):
			sub_txt = "GESICHTETES GRENZLAND · STEINSETZER-GRAVUR" if _zone_status_int(z.id) == 1 else "STEINSETZER-GRAVUR · NOCH UNERKUNDET"
		elif z != null and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE) and not z.subtitle.is_empty():
			sub_txt = z.subtitle.to_upper()
		var hdr_w: float = maxf(float(PixelText.width(header_name)) + 34.0, (float(PixelText.width(sub_txt)) + 24.0) if not sub_txt.is_empty() else 110.0)
		var hdr_h: float = 29.0 if not sub_txt.is_empty() else 18.0
		var hdr_r: Rect2 = Rect2(roundf(vs.x * 0.5 - hdr_w * 0.5), top_y + 6.0, roundf(hdr_w), hdr_h)
		MenuChrome.draw_slate(_overlay, hdr_r, 0.92 * fade)
		_overlay.draw_rect(Rect2(hdr_r.position.x + 2.0, hdr_r.position.y + 1.0, hdr_r.size.x - 4.0, 1.0), Color(MenuChrome.COL_GOLD, 0.72 * fade))
		MenuChrome.draw_text_centered(_overlay, header_name, hdr_r.get_center().x, hdr_r.position.y + 5.0, MenuChrome.COL_GOLD_HOT, fade)
		if not sub_txt.is_empty():
			MenuChrome.draw_text_centered(_overlay, sub_txt, hdr_r.get_center().x, hdr_r.position.y + 16.0, MenuChrome.COL_TEXT_SOFT, 0.90 * fade)
		# Clickable Exploration Flower + Progress Pill right underneath header
		if z != null and not unentered_zone and not over_open_sea and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE):
			var ratio_c: float = float(_book.compute_zone_progress(z.id).get("completion_ratio", 0.0)) if _book != null else _zone_explored_ratio(z.id)
			var pct_c: int = roundi(ratio_c * 100.0)
			var has_unclaimed_c: bool = _book != null and _book.has_unclaimed_milestone(z.id)
			var b_tag: String = "%d%% · CHRONIK!" % pct_c if has_unclaimed_c else "%d%% · B CHRONIK" % pct_c
			var pill_w: float = float(PixelText.width(b_tag)) + 26.0
			var pill_r: Rect2 = Rect2(roundf(vs.x * 0.5 - pill_w * 0.5), hdr_r.end.y + 3.0, pill_w, 16.0)
			_flower_hit_rect = pill_r
			var flower_hov_c: bool = pill_r.has_point(_cursor)
			if has_unclaimed_c:
				MenuChrome.draw_gold(_overlay, pill_r, fade)
			else:
				MenuChrome.draw_slate(_overlay, pill_r, 0.92 * fade)
			if flower_hov_c:
				_overlay.draw_rect(Rect2(pill_r.position.x + 2.0, pill_r.position.y + 1.0, pill_r.size.x - 4.0, 1.0), Color(MenuChrome.COL_TEAL, 0.85 * fade))
			_draw_completion_flower(Vector2(pill_r.position.x + 11.0, pill_r.get_center().y), ratio_c, fade, void_level, flower_hov_c, has_unclaimed_c)
			var pcol_c: Color = MenuChrome.COL_GOLD_HOT if (flower_hov_c or has_unclaimed_c) else MenuChrome.COL_TEAL
			MenuChrome.draw_text(_overlay, b_tag, Vector2(pill_r.position.x + 21.0, pill_r.position.y + 5.0), pcol_c, fade)
		elif _book != null and _active_zone_id != &"":
			_flower_hit_rect = hdr_r
	else:
		VineStyle.tag(_overlay, header_name, Vector2(vs.x * 0.5, top_y), reach, void_level * 0.5, _time, VineStyle.WARM_GLOW)
		if over_open_sea and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE):
			_text_centered("UMSPÜLT DIE ALTE MARK", Vector2(vs.x * 0.5, top_y + 25.0), Color(UiStyle.TEXT_DIM, 0.9), fade)
		elif unentered_zone and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE):
			var sub_u: String = "GESICHTETES GRENZLAND · STEINSETZER-GRAVUR" if _zone_status_int(z.id) == 1 else "STEINSETZER-GRAVUR · NOCH UNERKUNDET"
			_text_centered(sub_u, Vector2(vs.x * 0.5, top_y + 25.0), Color("b8b0d8", 0.9), fade)
		elif z != null and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE):
			if not z.subtitle.is_empty():
				_text_centered(z.subtitle.to_upper(), Vector2(vs.x * 0.5, top_y + 25.0), Color(UiStyle.TEXT_DIM, 0.9), fade)
			var ratio: float = float(_book.compute_zone_progress(z.id).get("completion_ratio", 0.0)) if _book != null else _zone_explored_ratio(z.id)
			var pct: int = roundi(ratio * 100.0)
			var pct_str: String = "%d%%" % pct
			var pw: int = PixelText.width(pct_str)
			var fx: float = roundf(vs.x * 0.5 - float(pw) * 0.5 - 8.0)
			var fy: float = top_y + 37.0
			_flower_hit_rect = Rect2(fx - 10.0, fy - 9.0, float(pw) + 34.0, 18.0)
			var flower_hov: bool = _flower_hit_rect.has_point(_cursor)
			var has_unclaimed: bool = _book != null and _book.has_unclaimed_milestone(z.id)
			_draw_completion_flower(Vector2(fx, fy), ratio, fade, void_level, flower_hov, has_unclaimed)
			var pct_col: Color = Color("ffe28a") if (flower_hov or has_unclaimed) else Color(UiStyle.ACCENT, 0.92)
			_text(pct_str, Vector2i(int(fx) + 10, int(top_y) + 34), pct_col, fade)
			if flower_hov or has_unclaimed:
				var b_lbl: String = "(B) CHRONIK!" if has_unclaimed else "(B)"
				_text(b_lbl, Vector2i(int(fx) + 13 + pw, int(top_y) + 34), Color("ffd98a" if has_unclaimed else "c2b6ea"), fade * 0.95)
		elif _book != null and _active_zone_id != &"":
			_flower_hit_rect = Rect2(vs.x * 0.5 - 48.0, top_y, 96.0, 22.0)

	# Left-edge level dock (Obsidian pills when in Feldcodex, hanging vines standalone)
	_level_tag_rects.clear()
	if codex_hud:
		var dock_x: float = 10.0
		var dock_y: float = top_y + 10.0
		var dock_w: float = 68.0
		var dock_r: Rect2 = Rect2(dock_x - 2.0, dock_y - 3.0, dock_w + 4.0, 92.0)
		MenuChrome.draw_slate(_overlay, dock_r, 0.88 * fade)
		for i: int in LEVEL_ORDER.size():
			var lvl: StringName = LEVEL_ORDER[i]
			var locked: bool = (lvl == LEVEL_CONTINENT or lvl == LEVEL_WORLD) and not _continent_unlocked
			var lbl: String = String(LEVEL_LABELS[lvl])
			var pr: Rect2 = Rect2(dock_x + 2.0, dock_y + float(i) * 22.0, dock_w - 4.0, 19.0)
			var active: bool = _current_level == lvl
			var hover: bool = pr.has_point(_cursor)
			MenuChrome.draw_tab_pill(_overlay, pr, active, 1.0 if (hover and not locked) else 0.0, fade * (0.65 if locked else 0.96))
			if active:
				MenuChrome.draw_shimmer(_overlay, pr, _time, MenuChrome.COL_GOLD_HOT, fade)
			var tc: Color = MenuChrome.COL_TEXT_DIM if locked else (MenuChrome.COL_GOLD_HOT if active else (MenuChrome.COL_TEXT if hover else MenuChrome.COL_TEXT_SOFT))
			if locked:
				MenuChrome.draw_text(_overlay, lbl, Vector2(pr.position.x + 5.0, pr.position.y + 6.0), tc, fade)
				MenuChrome.draw_lock(_overlay, Vector2(pr.end.x - 14.0, pr.position.y + 3.0), fade * 0.85)
			else:
				MenuChrome.draw_text_centered(_overlay, lbl, pr.get_center().x, pr.position.y + 6.0, tc, fade)
			_level_tag_rects[lvl] = pr
	else:
		var stem_x: float = 34.0
		var stem_y: float = 52.0
		for i: int in LEVEL_ORDER.size():
			var lvl: StringName = LEVEL_ORDER[i]
			var locked: bool = (lvl == LEVEL_CONTINENT or lvl == LEVEL_WORLD) and not _continent_unlocked
			var lbl: String = String(LEVEL_LABELS[lvl])
			if locked:
				lbl += " *"
			var anchor: Vector2 = Vector2(stem_x + sin(_time * 0.9 + float(i)) * 0.5, stem_y + float(i) * 28.0)
			var active: bool = _current_level == lvl
			var hover: bool = false
			var r_est: Rect2 = Rect2(anchor.x - 24.0, anchor.y + 6.0, 48.0, 13.0)
			if r_est.has_point(_cursor):
				hover = true
			var tone: Color = UiStyle.TEXT_DIM if locked else (VineStyle.ACCENT_WARM if active else UiStyle.ACCENT)
			var rect: Rect2 = VineStyle.tab(_overlay, lbl, anchor, reach, 2.0 if active else (1.0 if hover else 0.0), void_level * 0.5, _time, i, active, hover, tone)
			if active:
				VineStyle.bloom(_overlay, anchor, reach, _time, void_level * 0.5, tone)
			_level_tag_rects[lvl] = rect

	# Left-edge pin & coastal stamp palette (only on entered zones in ORT / ZONE)
	if not unentered_zone and not over_open_sea and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE) and (_preview_time < 0.0 or (_book != null and _book.has_stamp_unlocked())):
		_draw_pin_palette(fade, void_level)

	# Right-edge place list (sleek obsidian glass card when in Feldcodex, NEVER collides with lower-right zoom rail!)
	if z != null and not unentered_zone and not over_open_sea and (_current_level == LEVEL_ORT or _current_level == LEVEL_ZONE) and not z.places.is_empty():
		if codex_hud:
			var max_pw: float = 64.0
			for pl0: Atlas.Place in z.places:
				var s0: bool = _is_place_seen(pl0.id)
				var t0: String = pl0.name.to_upper() if s0 else "???"
				max_pw = maxf(max_pw, float(PixelText.width(t0)))
			var card_w_p: float = minf(max_pw + 22.0, 132.0)
			var card_h_p: float = 20.0 + float(z.places.size()) * 11.0
			var card_r_p: Rect2 = Rect2(vs.x - card_w_p - 10.0, top_y + 10.0, card_w_p, card_h_p)
			MenuChrome.draw_slate(_overlay, card_r_p, 0.88 * fade)
			MenuChrome.draw_text(_overlay, "ORTE", Vector2(card_r_p.position.x + 8.0, card_r_p.position.y + 6.0), MenuChrome.COL_GOLD, fade)
			var seen_cnt: int = 0
			for pl1: Atlas.Place in z.places:
				if _is_place_seen(pl1.id):
					seen_cnt += 1
			var sc_txt: String = "%d/%d" % [seen_cnt, z.places.size()]
			MenuChrome.draw_text(_overlay, sc_txt, Vector2(card_r_p.end.x - 8.0 - float(PixelText.width(sc_txt)), card_r_p.position.y + 6.0), MenuChrome.COL_TEAL, fade)
			_overlay.draw_rect(Rect2(card_r_p.position.x + 7.0, card_r_p.position.y + 15.0, card_r_p.size.x - 14.0, 1.0), Color(MenuChrome.COL_GOLD, 0.30 * fade))
			for i: int in z.places.size():
				var pl: Atlas.Place = z.places[i]
				var seen: bool = _is_place_seen(pl.id)
				var txt: String = MenuChrome.fit_text(pl.name, card_w_p - 18.0) if seen else "???"
				var py: float = card_r_p.position.y + 19.0 + float(i) * 11.0
				var prect: Rect2 = Rect2(card_r_p.position.x + 5.0, py - 1.0, card_r_p.size.x - 10.0, 10.0)
				var hovered_p: bool = prect.has_point(_cursor)
				if hovered_p and seen:
					_overlay.draw_rect(prect, Color(MenuChrome.COL_GOLD.r, MenuChrome.COL_GOLD.g, MenuChrome.COL_GOLD.b, 0.14 * fade))
				_overlay.draw_rect(Rect2(card_r_p.position.x + 8.0, py + 2.0, 2.0, 2.0), Color(MenuChrome.COL_TEAL if seen else MenuChrome.COL_TEXT_DIM, 0.85 * fade))
				var pcol: Color = (MenuChrome.COL_GOLD_HOT if hovered_p else MenuChrome.COL_TEXT) if seen else MenuChrome.COL_TEXT_DIM
				MenuChrome.draw_text(_overlay, txt, Vector2(card_r_p.position.x + 13.0, py), pcol, fade * (0.96 if seen else 0.72))
				_place_hit_rects.append({"rect": prect, "pos": pl.bbox.get_center(), "seen": seen})
		else:
			var list_y: float = top_y + 28.0
			for i: int in z.places.size():
				var pl: Atlas.Place = z.places[i]
				var seen: bool = _is_place_seen(pl.id)
				var txt: String = pl.name.to_upper() if seen else "???"
				var py: float = list_y + float(i) * 11.0
				var pw: int = PixelText.width(txt)
				var rx: float = vs.x - 18.0 - float(pw)
				var prect: Rect2 = Rect2(rx - 4.0, py - 1.0, float(pw) + 8.0, 9.0)
				var hovered_p: bool = prect.has_point(_cursor)
				var pcol: Color = (VineStyle.WARM_GLOW if hovered_p else UiStyle.TEXT) if seen else UiStyle.TEXT_DIM
				_text(txt, Vector2i(int(rx), int(py)), pcol, fade * (0.95 if seen else 0.7))
				_place_hit_rects.append({"rect": prect, "pos": pl.bbox.get_center(), "seen": seen})

	# Right-edge vertical zoom rail (collision-free lower-right obsidian rail in Feldcodex!)
	_draw_zoom_vine(fade, void_level)

	# Bottom-left filter bar (`F`)
	_draw_filter_branch(fade, void_level)

	# Bottom-right metric scale bar, Home Recenter Crystal & Compass Medallion
	_draw_scale_bar(fade)
	_draw_compass(fade)
	if codex_hud:
		_draw_home_crystal_btn(fade)

	# Toast feedback banner
	if _toast_timer > 0.01 and not _toast_msg.is_empty():
		var t_alpha: float = fade * clampf(_toast_timer / 0.4, 0.0, 1.0)
		_draw_carto_plaque(_toast_msg, Vector2(vs.x * 0.5, top_y + 62.0), Color("ffe28a"), Color("d8a955"), t_alpha, true, 0)

	# Bottom controls line (omitted when embedded inside GameMenu's unified footer)
	if embedded_bottom_inset <= 0.0:
		var hint: String = "TAB: EBENE   B: CHRONIK   F: FILTER   RAD: ZOOM   R-KLICK: ZEICHEN   MMB: RUF"
		_text_centered(hint, Vector2(vs.x * 0.5, vs.y - 12.0), Color(UiStyle.TEXT_DIM, 0.72), fade)


func _draw_home_crystal_btn(fade: float) -> void:
	var vs: Vector2 = _view_size()
	var btn_r: Rect2 = Rect2(vs.x - 58.0, vs.y - embedded_bottom_inset - 32.0, 20.0, 20.0)
	_home_btn_rect = btn_r
	var hov: bool = btn_r.has_point(_cursor)
	if hov:
		MenuChrome.draw_gold(_overlay, btn_r, fade)
	else:
		MenuChrome.draw_slate(_overlay, btn_r, 0.92 * fade)
	MenuChrome.draw_home_beacon(_overlay, btn_r.position + Vector2(4.0, 4.0), fade)
	if hov:
		var tip: String = "ZU MIR (LEER)"
		var tw: float = float(PixelText.width(tip)) + 10.0
		var tip_r: Rect2 = Rect2(btn_r.position.x - tw - 4.0, btn_r.position.y + 3.0, tw, 13.0)
		MenuChrome.draw_chip(_overlay, tip_r, tip, Color("161228"), MenuChrome.COL_TEAL, MenuChrome.COL_TEAL, fade)


func _draw_pin_palette(fade: float, _void_level: float) -> void:
	var count: int = _unlocked_pin_count()
	var codex_hud: bool = embedded_top_inset > 0.0
	var base_x: float = 12.0 if codex_hud else 14.0
	var base_y: float = (embedded_top_inset + 114.0) if codex_hud else 178.0
	if codex_hud:
		var tray_r: Rect2 = Rect2(base_x - 4.0, base_y - 4.0, 24.0, float(count) * 19.0 + 6.0)
		MenuChrome.draw_slate(_overlay, tray_r, 0.88 * fade)
	for k: int in count:
		var spec: Dictionary = PIN_KIND_LIST[k]
		var sy: float = base_y + float(k) * 19.0
		var srect: Rect2 = Rect2(base_x, sy, 16.0, 16.0)
		var chosen: bool = (_pin_kind_idx == k)
		var hov: bool = srect.has_point(_cursor)
		var col: Color = spec["color"] as Color
		if chosen or hov:
			VineStyle.glow(_overlay, srect.get_center(), 12.0 if chosen else 9.0, col, (0.48 if chosen else 0.25) * fade)
		_overlay.draw_rect(srect, Color("0b0716", 0.92 * fade))
		_overlay.draw_rect(srect.grow(-1.0), Color("1f1936" if chosen else "141026", 0.95 * fade))
		var b_col: Color = MenuChrome.COL_GOLD_HOT if (codex_hud and chosen) else (col if chosen else (col.lightened(0.15) if hov else Color("4a4172")))
		_overlay.draw_rect(Rect2(srect.position.x, srect.position.y, srect.size.x, 1.0), Color(b_col, 0.90 * fade))
		_overlay.draw_rect(Rect2(srect.position.x, srect.end.y - 1.0, srect.size.x, 1.0), Color(b_col.darkened(0.2), 0.80 * fade))
		if (spec["id"] as StringName) == &"coast_wave" and ATLAS_ELEMENTS_TEX != null:
			_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, srect, Rect2(76.0, 4.0, 16.0, 16.0), Color(1.0, 1.0, 1.0, fade * (1.0 if chosen or hov else 0.85)))
		else:
			_draw_pin_glyph(spec["rows"] as Array, srect.get_center(), col, fade * (1.0 if chosen or hov else 0.80))
		if hov:
			var pnm: String = String(spec["name"])
			if codex_hud:
				var pw: float = float(PixelText.width(pnm)) + 10.0
				MenuChrome.draw_chip(_overlay, Rect2(srect.end.x + 6.0, srect.position.y + 1.0, pw, 13.0), pnm, Color("161228"), col, col.lightened(0.2), fade)
			else:
				_text(pnm, Vector2i(int(srect.end.x) + 5, int(srect.position.y) + 5), col.lightened(0.2), fade)
		_pin_slot_rects.append({"rect": srect, "idx": k})


func _is_place_seen(place_id: StringName) -> bool:
	if _preview_reveal_all or (_discovery != null and _discovery.is_reveal_all()):
		return true
	if _director != null and _director.has_method(&"seen_place"):
		return bool(_director.call(&"seen_place", place_id))
	return true


func _draw_zoom_vine(fade: float, void_level: float) -> void:
	var reach: float = clampf((_open_t - 0.15) / 0.55, 0.0, 1.0)
	var zb: Vector3 = _zoom_rail_bounds()
	if embedded_top_inset > 0.0:
		# Sleek Obsidian Vertical Zoom Tube docked safely on lower-right edge (zero Place-list overlap!)
		var track_r: Rect2 = Rect2(zb.x - 8.0, zb.y - 16.0, 16.0, (zb.z - zb.y) + 32.0)
		MenuChrome.draw_slate(_overlay, track_r, 0.88 * fade * reach)
		MenuChrome.draw_text_centered(_overlay, "+", zb.x, zb.y - 12.0, MenuChrome.COL_GOLD, fade * reach)
		MenuChrome.draw_text_centered(_overlay, "-", zb.x, zb.z + 5.0, MenuChrome.COL_TEXT_SOFT, fade * reach)
		var groove: Rect2 = Rect2(zb.x - 1.0, zb.y, 3.0, zb.z - zb.y)
		_overlay.draw_rect(groove, Color("0b0716", 0.9 * fade * reach))
		var u: float = _zoom_u()
		var bead_y: float = roundf(lerpf(zb.z, zb.y, u))
		_overlay.draw_rect(Rect2(zb.x, bead_y, 1.0, maxf(zb.z - bead_y, 0.0)), Color(MenuChrome.COL_TEAL, 0.85 * fade * reach))
		var knob: Rect2 = Rect2(zb.x - 4.0, bead_y - 3.0, 9.0, 7.0)
		_overlay.draw_rect(knob, Color(MenuChrome.COL_OUTLINE, fade * reach))
		_overlay.draw_rect(knob.grow(-1.0), Color(MenuChrome.COL_GOLD_HOT if _slider_drag else MenuChrome.COL_GOLD, fade * reach))
		_overlay.draw_rect(Rect2(knob.position + Vector2(1.0, 1.0), Vector2(7.0, 1.0)), Color(1.0, 1.0, 1.0, 0.75 * fade * reach))
		return

	var top: float = ZOOM_BOTTOM - (ZOOM_BOTTOM - ZOOM_TOP) * reach
	var y: float = ZOOM_BOTTOM
	while y > top:
		var t: float = (ZOOM_BOTTOM - y) / (ZOOM_BOTTOM - ZOOM_TOP)
		var x: float = ZOOM_X + sin(y * 0.06) * 1.5
		var thick: int = maxi(roundi(lerpf(3.0, 1.0, t)), 1)
		var taken: float = VineStyle.infection((ZOOM_BOTTOM - y) * 0.5 + 40.0, void_level, int(y / 3.0))
		_overlay.draw_rect(Rect2(x - 1, y, thick + 2, 1), Color(VineStyle.OUTLINE.lerp(VineStyle.BARK_VOID_LIGHT, taken), fade))
		_overlay.draw_rect(Rect2(x, y, thick, 1), Color(VineStyle.BARK.lerp(VineStyle.BARK_VOID, taken), fade))
		y -= 1.0
	for k: int in 4:
		var ky: float = lerpf(ZOOM_BOTTOM, ZOOM_TOP, float(k) / 3.0)
		if ky >= top:
			VineStyle.leaf(_overlay, Vector2(ZOOM_X - 2.0, ky), -1, -1 if k % 2 == 0 else 1, 3, VineStyle.LEAF.lerp(VineStyle.LEAF_VOID, void_level), VineStyle.LEAF_LIGHT.lerp(VineStyle.LEAF_VOID_LIGHT, void_level))
	var u2: float = _zoom_u()
	var bead: Vector2 = Vector2(ZOOM_X + sin(lerpf(ZOOM_BOTTOM, ZOOM_TOP, u2) * 0.06) * 1.5 + 1.0, lerpf(ZOOM_BOTTOM, ZOOM_TOP, u2))
	var tone: Color = VineStyle.WARM_GLOW.lerp(VineStyle.VOID_GLOW, maxf(void_level, 0.3))
	VineStyle.glow(_overlay, bead, 11.0, tone, 0.6 * fade * reach)
	_overlay.draw_rect(Rect2(bead - Vector2(2, 2), Vector2(5, 5)), Color(VineStyle.OUTLINE, fade * reach))
	_overlay.draw_rect(Rect2(bead - Vector2(1, 1), Vector2(3, 3)), Color(tone, fade * reach))
	_overlay.draw_rect(Rect2(bead, Vector2.ONE), Color(VineStyle.PETAL, fade * reach))
	_text("+", Vector2i(int(ZOOM_X) - 1, int(ZOOM_TOP) - 16), Color(UiStyle.TEXT_DIM, 0.8), fade * reach)
	_text("-", Vector2i(int(ZOOM_X) - 1, int(ZOOM_BOTTOM) + 6), Color(UiStyle.TEXT_DIM, 0.8), fade * reach)


func _filter_categories() -> Array[Dictionary]:
	if _markers != null and _markers.has_method(&"filter_categories"):
		var raw: Array = _markers.call(&"filter_categories") as Array
		var out: Array[Dictionary] = []
		for c: Variant in raw:
			if c is Dictionary:
				out.append(c as Dictionary)
		if not out.is_empty():
			return out
	return DEFAULT_FILTER_CATS


func _is_filter_cat_enabled(cat_id: StringName) -> bool:
	if _markers != null and _markers.has_method(&"is_filter_enabled"):
		return bool(_markers.call(&"is_filter_enabled", cat_id))
	return not bool(_local_filter_disabled.get(cat_id, false))


func _toggle_filter_cat(cat_id: StringName) -> void:
	if _markers != null and _markers.has_method(&"toggle_filter"):
		_markers.call(&"toggle_filter", cat_id)
	else:
		_local_filter_disabled[cat_id] = not bool(_local_filter_disabled.get(cat_id, false))


func _draw_filter_branch(fade: float, void_level: float) -> void:
	var vs: Vector2 = _view_size()
	if embedded_top_inset > 0.0:
		var by: float = vs.y - embedded_bottom_inset - 28.0
		var btn_r: Rect2 = Rect2(10.0, by, 68.0, 19.0)
		_filter_branch_rect = btn_r
		var hov_f: bool = btn_r.has_point(_cursor)
		if _filter_open:
			MenuChrome.draw_gold(_overlay, btn_r, fade)
		else:
			MenuChrome.draw_slate(_overlay, btn_r, 0.92 * fade)
		MenuChrome.draw_keycap(_overlay, Vector2(btn_r.position.x + 4.0, btn_r.position.y + 3.0), "F", fade, _filter_open)
		MenuChrome.draw_text(_overlay, "FILTER", Vector2(btn_r.position.x + 22.0, btn_r.position.y + 6.0), MenuChrome.COL_GOLD_HOT if (_filter_open or hov_f) else MenuChrome.COL_TEXT, fade)
		if _filter_open:
			var cats: Array[Dictionary] = _filter_categories()
			var cx: float = btn_r.end.x + 6.0
			for cat: Dictionary in cats:
				var cid: StringName = StringName(cat.get("id", &""))
				var lbl: String = String(cat.get("label", String(cid))).to_upper()
				var col: Color = cat.get("color", UiStyle.ACCENT) as Color
				var on: bool = _is_filter_cat_enabled(cid)
				var w: float = float(PixelText.width(lbl)) + 12.0
				var rect: Rect2 = Rect2(cx, by + 2.0, w, 15.0)
				MenuChrome.draw_chip(_overlay, rect, lbl, Color("1d1734") if on else Color("110d1f"), col if on else Color("3c3258"), col.lightened(0.18) if on else MenuChrome.COL_TEXT_DIM, fade)
				_filter_hit_rects.append({"rect": rect, "id": cid})
				cx += w + 4.0
		return

	var base_y: float = vs.y - 26.0
	var course: Callable = func(x: float) -> float: return base_y + sin(x * 0.08) * 1.2
	var span_x: float = 82.0
	VineStyle.branch(_overlay, 0.0, span_x, course, 3, void_level, 20.0, _time, 1.0)
	VineStyle.foliage(_overlay, 0.0, span_x, course, 5, 311, void_level, 20.0, _time, 1.0)
	var cap_w: int = VineStyle.key_cap(_overlay, Vector2(10.0, base_y - 16.0), "F", fade, 1.0 if _filter_open else 0.0, void_level)
	_text("FILTER", Vector2i(14 + cap_w, int(base_y) - 13), Color(VineStyle.WARM_GLOW if _filter_open else UiStyle.TEXT, 0.92), fade)
	_filter_branch_rect = Rect2(8.0, base_y - 18.0, 68.0, 18.0)

	if _filter_open:
		var cats2: Array[Dictionary] = _filter_categories()
		var cx2: float = 88.0
		for cat2: Dictionary in cats2:
			var cid2: StringName = StringName(cat2.get("id", &""))
			var lbl2: String = String(cat2.get("label", String(cid2))).to_upper()
			var col2: Color = cat2.get("color", UiStyle.ACCENT) as Color
			var on2: bool = _is_filter_cat_enabled(cid2)
			var w2: float = float(PixelText.width(lbl2) + 10)
			var rect2: Rect2 = Rect2(cx2, base_y - 17.0, w2, 12.0)
			VineStyle.plate(_overlay, rect2, lbl2, col2 if on2 else UiStyle.PANEL_DARK, VineStyle.PETAL if on2 else UiStyle.TEXT_DIM, fade * (0.95 if on2 else 0.65), void_level * 0.5)
			_filter_hit_rects.append({"rect": rect2, "id": cid2})
			cx2 += w2 + 4.0


func _draw_scale_bar(fade: float) -> void:
	var vs: Vector2 = _view_size()
	var candidates: Array[int] = [5, 10, 25, 50, 100, 250, 500, 1000]
	var chosen_m: int = 50
	for m: int in candidates:
		var px: float = float(m) * _zoom
		if px >= 22.0 and px <= 68.0:
			chosen_m = m
			break
		if px < 22.0:
			chosen_m = m
	var bar_px: float = clampf(float(chosen_m) * _zoom, 14.0, 76.0)
	var right_x: float = vs.x - (68.0 if embedded_top_inset > 0.0 else 80.0)
	var left_x: float = roundf(right_x - bar_px)
	var y: float = vs.y - (embedded_bottom_inset + 16.0 if embedded_top_inset > 0.0 else 24.0)
	_overlay.draw_rect(Rect2(left_x - 1, y - 3, bar_px + 2, 5), Color(VineStyle.OUTLINE, 0.85 * fade))
	_overlay.draw_rect(Rect2(left_x, y, bar_px, 1), Color(MenuChrome.COL_GOLD if embedded_top_inset > 0.0 else VineStyle.PETAL, 0.92 * fade))
	_overlay.draw_rect(Rect2(left_x, y - 2, 1, 4), Color(MenuChrome.COL_GOLD if embedded_top_inset > 0.0 else VineStyle.PETAL, 0.92 * fade))
	_overlay.draw_rect(Rect2(left_x + bar_px - 1, y - 2, 1, 4), Color(MenuChrome.COL_GOLD if embedded_top_inset > 0.0 else VineStyle.PETAL, 0.92 * fade))
	_text_centered("%d M" % chosen_m, Vector2(left_x + bar_px * 0.5, y - 10.0), Color(UiStyle.TEXT, 0.92), fade)


func _draw_completion_flower(at: Vector2, ratio: float, fade: float, void_level: float, hovered: bool = false, has_unclaimed: bool = false) -> void:
	if hovered or has_unclaimed:
		var pulse_g: float = 0.72 + 0.28 * sin(_time * 4.5)
		VineStyle.glow(_overlay, at, 13.0 if hovered else 10.0, Color("ffd98a"), (0.55 if hovered else 0.38 * pulse_g) * fade)
	if ATLAS_ELEMENTS_TEX != null:
		var reg: Rect2 = AtlasBook.flower_region_for_ratio(ratio)
		_overlay.draw_texture_rect_region(ATLAS_ELEMENTS_TEX, Rect2((at - Vector2(8.0, 8.0)).round(), Vector2(16.0, 16.0)), reg, Color(1.0, 1.0, 1.0, fade))
		return
	var lit_petals: int = clampi(ceili(ratio * 5.0), 0, 5)
	var petal_offsets: Array[Vector2] = [
		Vector2(0, -3), Vector2(3, -1), Vector2(2, 2), Vector2(-2, 2), Vector2(-3, -1)
	]
	for i: int in 5:
		var p_pos: Vector2 = (at + petal_offsets[i]).round()
		var lit: bool = i < lit_petals
		var p_col: Color = VineStyle.PETAL.lerp(VineStyle.LEAF_VOID_LIGHT, void_level * 0.4) if lit else UiStyle.TEXT_DIM
		_overlay.draw_rect(Rect2(p_pos - Vector2.ONE, Vector2(3, 3)), Color(VineStyle.OUTLINE, 0.8 * fade))
		_overlay.draw_rect(Rect2(p_pos, Vector2.ONE), Color(p_col, (0.95 if lit else 0.45) * fade))
	_overlay.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.WARM_GLOW, fade))


func _draw_compass(fade: float) -> void:
	var vs: Vector2 = _view_size()
	var at: Vector2 = Vector2(vs.x - 48.0, vs.y - embedded_bottom_inset - 60.0) if embedded_top_inset > 0.0 else Vector2(582.0, 280.0)
	if embedded_top_inset > 0.0:
		var med: Rect2 = Rect2(at - Vector2(13.0, 13.0), Vector2(26.0, 26.0))
		MenuChrome.draw_slate(_overlay, med, 0.88 * fade)
	var glow_val: float = 0.7 + 0.3 * sin(_time * 1.6)
	VineStyle.glow(_overlay, at, 14.0, MenuChrome.COL_TEAL if embedded_top_inset > 0.0 else VineStyle.VOID_GLOW, 0.28 * fade * glow_val)
	VineStyle.ring(_overlay, at, 9, Color(MenuChrome.COL_GOLD if embedded_top_inset > 0.0 else VineStyle.BARK_LIGHT, 0.75 * fade), 0.5)
	var spin_ease: float = 1.0 - pow(1.0 - _compass_spin_t, 3.0)
	var spin_ang: float = (1.0 - spin_ease) * TAU
	var ca: float = cos(spin_ang)
	var sa: float = sin(spin_ang)
	for i: int in range(-7, 8):
		var arm: float = 1.0 - absf(float(i)) / 7.0
		var light: Color = (MenuChrome.COL_TEAL if i < 0 else MenuChrome.COL_GOLD) if embedded_top_inset > 0.0 else (VineStyle.VOID_GLOW if i < 0 else VineStyle.BARK_LIGHT)
		var vy: Vector2 = Vector2(-sa * float(i), ca * float(i)).round()
		_overlay.draw_rect(Rect2(at.x + vy.x, at.y + vy.y, 1, 1), Color(light.lerp(VineStyle.PETAL, arm * 0.4 if i < 0 else 0.0), fade * (0.5 + 0.5 * arm)))
		if absi(i) <= 4:
			var vx: Vector2 = Vector2(ca * float(i), sa * float(i)).round()
			_overlay.draw_rect(Rect2(at.x + vx.x, at.y + vx.y, 1, 1), Color(MenuChrome.COL_GOLD if embedded_top_inset > 0.0 else VineStyle.BARK_LIGHT, fade * (0.4 + 0.4 * arm)))
	_overlay.draw_rect(Rect2(at - Vector2(1, 1), Vector2(3, 3)), Color(VineStyle.OUTLINE, fade))
	_overlay.draw_rect(Rect2(at, Vector2.ONE), Color(VineStyle.PETAL, fade))
	_text_centered("N", at + Vector2(0, -20), Color(MenuChrome.COL_GOLD_HOT if embedded_top_inset > 0.0 else VineStyle.LEAF_VOID_LIGHT, 0.95), fade)


func _director_flags() -> Dictionary:
	if _director != null and _director.has_method(&"_flags"):
		return _director.call(&"_flags") as Dictionary
	return {}


func _on_screen(at: Vector2, margin: float = 12.0) -> bool:
	var vs: Vector2 = _view_size()
	return at.x > -margin and at.y > -margin and at.x < vs.x + margin and at.y < vs.y + margin


func _text(text: String, pos: Vector2i, color: Color, fade: float) -> void:
	PixelText.draw(_overlay, text, pos, Color(color, color.a * fade), Color(VineStyle.OUTLINE, 0.9 * fade))


func _text_centered(text: String, at: Vector2, color: Color, fade: float) -> void:
	_text(text, Vector2i(roundi(at.x) - PixelText.width(text) / 2, roundi(at.y)), color, fade)
