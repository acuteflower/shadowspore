class_name ZoneWorld
extends "res://src/world/test_level.gd"
## Lost-Ark-style zoned semi-open world host/client controller supporting Option B Co-op.

const RABBIT_SCENE_PATH: String = "res://src/entities/animals/rabbit.tscn"
const BIRD_SCENE_PATH: String = "res://src/entities/animals/bird.tscn"
const HUT_ENTER_WAIT: float = 0.2

class _ZoneMapStub:
	var world_seed: int = 104130
	var start_region: String = "start_path"

var _map: _ZoneMapStub = _ZoneMapStub.new()
var opening_over: bool = false
var _hut_renewed: bool = false
var fallen_knight: FallenKnight
var cover_node: ManholeCover
var night: NightDirector

var _zones_root: Node2D
var _props: Node2D
var _town_node: TownManager
var _interiors: Interiors
var _waystones: Waystones

var _zones: Dictionary = {} ## zone_id -> ZoneInstance
var _player_zones: Dictionary = {} ## peer_id (int) -> zone_id (String)
var _discovered: Dictionary = {"start_path": true} ## zone_id -> true
var _thing_states: Dictionary = {} ## Vector2i global_tile -> Dictionary
var _harvest_states: Dictionary = {} ## String key -> Dictionary
var _things: Dictionary = {} ## Vector2i global_tile -> WorldProp
var _hut_node: Hut
var _portal_cooldown_until: Dictionary = {} ## peer_id (int) -> float msec

var _banner_layer: CanvasLayer
var _banner_label: Label
var _banner_sub: Label
var _banner_tween: Tween
var _wipe_layer: CanvasLayer
var _wipe_rect: ColorRect
var _night_spawn_accum: float = 0.0
var _loading_done: bool = false
var _last_local_zone: String = ""


func _fill_ground() -> void:
	RenderingServer.set_default_clear_color(Color("120e1f"))
	LightTexture.prewarm(PackedInt32Array([24, 26, 28, 34, 36, 40]))
	add_to_group("story_world")
	add_to_group("zone_world")

	_props = Node2D.new()
	_props.name = "Props"
	_props.y_sort_enabled = true
	add_child(_props)

	_zones_root = Node2D.new()
	_zones_root.name = "Zones"
	_zones_root.y_sort_enabled = true
	add_child(_zones_root)

	_interiors = Interiors.new()
	_interiors.name = "Interiors"
	add_child(_interiors)

	_waystones = Waystones.new()
	_waystones.name = "Waystones"
	add_child(_waystones)

	var goddess: GoddessSystem = GoddessSystem.new()
	goddess.name = "GoddessSystem"
	add_child(goddess)

	_town_node = TownManager.new()
	_town_node.name = "TownManager"
	_town_node.setup(self)
	add_child(_town_node)

	night = NightDirector.new()
	night.name = "NightDirector"
	night.setup(self)
	add_child(night)

	_build_banner_ui()

	_players.child_entered_tree.connect(_on_player_node_entered)
	ensure_zone_loaded(ZoneCatalog.start_zone_id())
	_loading_done = true

	if multiplayer.is_server():
		if not opening_over:
			TimeManager.lock_at(0.0)
		TimeManager.day_started.connect(_grow_things)
		multiplayer.peer_connected.connect(_on_peer_connected_sync)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected_cleanup)


func _process(delta: float) -> void:
	var local_p: Player = _find_local_player()
	if local_p != null:
		var outer_pos: Vector2 = Interiors.outer(get_tree(), local_p.global_position)
		var zid: String = ZoneCatalog.zone_id_at(outer_pos)
		if not zid.is_empty() and zid != _last_local_zone and _zones.has(zid):
			_last_local_zone = zid
			apply_camera_bounds(local_p)
			_show_zone_banner(zid)

	if multiplayer.is_server():
		_night_spawn_accum += delta
		if _night_spawn_accum >= 8.0:
			_night_spawn_accum = 0.0
			_tick_zone_night_spawns()


func loading_init_step() -> bool:
	return false


func loading_step() -> bool:
	return _loading_done


func loading_warmup_step() -> bool:
	return false


# ------------------------------------------------------------------ Zone Slot Management

func ensure_zone_loaded(zone_id: String) -> ZoneInstance:
	if _zones.has(zone_id):
		return _zones[zone_id] as ZoneInstance
	var spec: Dictionary = ZoneCatalog.zone_spec(zone_id)
	if spec.is_empty():
		return null
	var slot_idx: int = ZoneCatalog.slot_index_for(zone_id)
	var zone: ZoneInstance = ZoneBuilder.build(self, zone_id, spec, slot_idx)
	_zones_root.add_child(zone)
	_zones[zone_id] = zone
	_discovered[zone_id] = true

	if multiplayer.is_server():
		_spawn_zone_guards(zone, spec)
		_spawn_zone_wildlife(zone, spec)

	var dn: Node = get_node_or_null("DayNight")
	if dn != null and dn.has_method("set_night"):
		dn.call("set_night", TimeManager.night_amount())
	return zone


func unload_unused_zones(keep_zones: Array[String] = []) -> void:
	var occupied: Dictionary = {}
	for kz: String in keep_zones:
		if not kz.is_empty():
			occupied[kz] = true
	for pid: Variant in _player_zones:
		var pz: String = String(_player_zones[pid])
		if not pz.is_empty():
			occupied[pz] = true
	for p: Player in Player.all:
		if not is_instance_valid(p):
			continue
		var pid: int = p.name.to_int()
		if _player_zones.has(pid):
			continue
		var outer_pos: Vector2 = Interiors.outer(get_tree(), p.global_position)
		var zid: String = ZoneCatalog.zone_id_at(outer_pos)
		if not zid.is_empty():
			occupied[zid] = true
	if occupied.is_empty():
		occupied[ZoneCatalog.start_zone_id()] = true

	for zid: Variant in _zones.keys():
		var z_key: String = String(zid)
		if occupied.has(z_key):
			continue
		var zone: ZoneInstance = _zones[z_key] as ZoneInstance
		_zones.erase(z_key)
		if zone == null or not is_instance_valid(zone):
			continue
		if zone.hut_node == _hut_node:
			_hut_node = null
		if zone.fallen_knight == fallen_knight:
			fallen_knight = null
		if zone.cover_node == cover_node:
			cover_node = null
		zone.unload_from_world(_ground, _glow, _things, _props)


func active_zones() -> Dictionary:
	return _zones


func discovered_zones() -> Dictionary:
	return _discovered


func players_in_zones() -> Dictionary:
	return _player_zones


func player_zone(peer_id: int) -> String:
	return String(_player_zones.get(peer_id, ZoneCatalog.start_zone_id()))


func has_player_in_zone(zone_id: String) -> bool:
	for pid: Variant in _player_zones:
		if String(_player_zones[pid]) == zone_id:
			return true
	for p: Player in Player.all:
		if is_instance_valid(p):
			var z: String = ZoneCatalog.zone_id_at(Interiors.outer(get_tree(), p.global_position))
			if z == zone_id:
				return true
	return false


func raids_allowed() -> bool:
	return has_player_in_zone(ZoneCatalog.home_zone_id())


# ------------------------------------------------------------------ Zone Travel & Respawn

func spawn_point() -> Vector2:
	return spawn_point_for(0)


func spawn_point_for(id: int = 0) -> Vector2:
	if id > 0 and _player_zones.has(id):
		var saved_zone_id: String = String(_player_zones[id])
		var sz: ZoneInstance = ensure_zone_loaded(saved_zone_id)
		if sz != null:
			var saved_spawn: String = "respawn" if (saved_zone_id == ZoneCatalog.home_zone_id() and opening_over) else "default"
			return sz.spawn_position(saved_spawn)
	if opening_over:
		var home_id: String = ZoneCatalog.home_zone_id()
		var home_zone: ZoneInstance = ensure_zone_loaded(home_id)
		if id > 0:
			_player_zones[id] = home_id
		return home_zone.spawn_position("respawn") if home_zone != null else Vector2(9600.0, 1100.0)
	var start_id: String = ZoneCatalog.start_zone_id()
	var start_zone: ZoneInstance = ensure_zone_loaded(start_id)
	if id > 0:
		_player_zones[id] = start_id
	return start_zone.spawn_position("default") if start_zone != null else Vector2(408.0, 360.0)


func respawn_point_for(_id: int = 0) -> Vector2:
	var target_zone: String = ZoneCatalog.home_zone_id() if opening_over else ZoneCatalog.start_zone_id()
	var dest: ZoneInstance = ensure_zone_loaded(target_zone)
	if dest != null:
		return dest.spawn_position("respawn" if opening_over else "default")
	return Vector2(9600.0, 1100.0) if opening_over else Vector2(408.0, 360.0)


func on_player_respawned(player: Player) -> void:
	if not is_instance_valid(player):
		return
	var peer_id: int = player.name.to_int()
	var target_zone: String = ZoneCatalog.home_zone_id() if opening_over else ZoneCatalog.start_zone_id()
	var dest: ZoneInstance = ensure_zone_loaded(target_zone)
	if peer_id > 0:
		_player_zones[peer_id] = target_zone
	_portal_cooldown_until[peer_id] = float(Time.get_ticks_msec()) + 1400.0
	if dest != null and ZoneCatalog.zone_id_at(player.global_position) != target_zone:
		player.request_teleport(dest.spawn_position("respawn" if opening_over else "default"))
	if player.is_multiplayer_authority():
		_last_local_zone = target_zone
		apply_camera_bounds(player)
		_show_zone_banner(target_zone)
	unload_unused_zones([target_zone])
	if multiplayer.is_server():
		_rpc_sync_zone_presence.rpc(_player_zones, _discovered)


func request_portal_travel(source_zone: String, portal_id: String, player: Player) -> void:
	if player == null or not is_instance_valid(player):
		return
	var peer_id: int = player.name.to_int()
	var now: float = float(Time.get_ticks_msec())
	if now < float(_portal_cooldown_until.get(peer_id, 0.0)):
		return
	if multiplayer.is_server():
		_host_process_portal(peer_id, source_zone, portal_id)
	else:
		_rpc_request_portal.rpc_id(1, source_zone, portal_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_portal(source_zone: String, portal_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_host_process_portal(sender, source_zone, portal_id)


func _host_process_portal(peer_id: int, source_zone: String, portal_id: String) -> void:
	var now: float = float(Time.get_ticks_msec())
	if now < float(_portal_cooldown_until.get(peer_id, 0.0)):
		return
	var src: ZoneInstance = _zones.get(source_zone) as ZoneInstance
	if src == null or not src.portals.has(portal_id):
		return
	var portal: ZonePortal = src.portals[portal_id] as ZonePortal
	if portal == null or portal.locked:
		return
	if not ZoneCatalog.is_zone_playable(portal.target_zone_id):
		return
	var p_node: Player = _find_player_by_id(peer_id)
	if p_node == null or p_node.health.current <= 0.0:
		return
	if p_node.global_position.distance_to(portal.global_position) > maxf(portal.portal_size.x, portal.portal_size.y) + 64.0:
		return
	travel_to_zone(peer_id, portal.target_zone_id, portal.target_spawn)


func request_waystone_travel(target_zone_id: String, _waystone_id: String = "") -> void:
	var local_p: Player = _find_local_player()
	if local_p == null:
		return
	if multiplayer.is_server():
		_host_waystone_travel(local_p.name.to_int(), target_zone_id)
	else:
		_rpc_request_waystone_zone.rpc_id(1, target_zone_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_waystone_zone(target_zone_id: String) -> void:
	if multiplayer.is_server():
		_host_waystone_travel(multiplayer.get_remote_sender_id(), target_zone_id)


func _host_waystone_travel(peer_id: int, target_zone_id: String) -> void:
	if not ZoneCatalog.is_zone_playable(target_zone_id):
		return
	travel_to_zone(peer_id, target_zone_id, "default")


func travel_to_zone(peer_id: int, target_zone: String, spawn_name: String = "default", instant: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var dest_zone: ZoneInstance = ensure_zone_loaded(target_zone)
	if dest_zone == null:
		return
	_player_zones[peer_id] = target_zone
	_discovered[target_zone] = true
	_portal_cooldown_until[peer_id] = float(Time.get_ticks_msec()) + 1600.0
	var dest_pos: Vector2 = dest_zone.spawn_position(spawn_name)
	_rpc_execute_zone_travel.rpc(peer_id, target_zone, dest_pos, _player_zones, _discovered, instant)


@rpc("authority", "call_local", "reliable")
func _rpc_execute_zone_travel(peer_id: int, target_zone: String, dest_pos: Vector2, new_player_zones: Dictionary, new_discovered: Dictionary, instant: bool) -> void:
	_player_zones = new_player_zones.duplicate()
	_discovered = new_discovered.duplicate()
	ensure_zone_loaded(target_zone)

	var mover: Player = _find_player_by_id(peer_id)
	if mover != null and mover.is_multiplayer_authority():
		_portal_cooldown_until[peer_id] = float(Time.get_ticks_msec()) + 1600.0
		if instant or DisplayServer.get_name() == "headless":
			mover.request_teleport(dest_pos)
			_last_local_zone = target_zone
			apply_camera_bounds(mover)
			_show_zone_banner(target_zone)
			unload_unused_zones([target_zone])
		else:
			_run_zone_wipe(mover, target_zone, dest_pos)
	else:
		unload_unused_zones()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_zone_presence(new_player_zones: Dictionary, new_discovered: Dictionary) -> void:
	_player_zones = new_player_zones.duplicate()
	_discovered = new_discovered.duplicate()
	for z_v: Variant in _player_zones.values():
		var z_id: String = String(z_v)
		if not z_id.is_empty():
			ensure_zone_loaded(z_id)
	unload_unused_zones()


func _run_zone_wipe(mover: Player, target_zone: String, dest_pos: Vector2) -> void:
	if _wipe_layer == null:
		_wipe_layer = CanvasLayer.new()
		_wipe_layer.layer = 94
		_wipe_rect = ColorRect.new()
		_wipe_rect.color = Color(0.05, 0.04, 0.09, 0.0)
		_wipe_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_wipe_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wipe_layer.add_child(_wipe_rect)
		add_child(_wipe_layer)
	mover.story_lock = true
	var t_out: Tween = create_tween().set_ignore_time_scale(true)
	t_out.tween_property(_wipe_rect, "color:a", 1.0, 0.16)
	await t_out.finished
	if is_instance_valid(mover):
		mover.request_teleport(dest_pos)
		_last_local_zone = target_zone
		apply_camera_bounds(mover)
	unload_unused_zones([target_zone])
	var t_in: Tween = create_tween().set_ignore_time_scale(true)
	t_in.tween_property(_wipe_rect, "color:a", 0.0, 0.22)
	await t_in.finished
	if is_instance_valid(mover):
		mover.story_lock = false
		_show_zone_banner(target_zone)


# ------------------------------------------------------------------ Camera & UI Banner

func camera_bounds_for(world_pos: Vector2) -> Rect2:
	var outer_pos: Vector2 = Interiors.outer(get_tree(), world_pos)
	var zid: String = ZoneCatalog.zone_id_at(outer_pos)
	if zid.is_empty() or not _zones.has(zid):
		return Rect2()
	return (_zones[zid] as ZoneInstance).bounds_px


func apply_camera_bounds(player: Player) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	var camera: Camera2D = player.get("_camera") as Camera2D
	if camera == null:
		return
	if Interiors.slot_at(player.global_position) >= 0:
		return ## Interiors.apply_view handles room clamping
	var bounds: Rect2 = camera_bounds_for(player.global_position)
	if bounds.has_area():
		camera.limit_left = int(bounds.position.x)
		camera.limit_top = int(bounds.position.y)
		camera.limit_right = int(bounds.end.x)
		camera.limit_bottom = int(bounds.end.y)
		camera.reset_smoothing()


func _build_banner_ui() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_banner_layer = CanvasLayer.new()
	_banner_layer.layer = 18
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.offset_top = 24.0
	root.offset_bottom = 84.0
	_banner_layer.add_child(root)

	_banner_label = Label.new()
	_banner_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 18)
	_banner_label.add_theme_color_override("font_color", Color("f2e8cf"))
	_banner_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.04, 0.08, 0.9))
	_banner_label.add_theme_constant_override("shadow_offset_x", 1)
	_banner_label.add_theme_constant_override("shadow_offset_y", 2)
	_banner_label.modulate.a = 0.0
	root.add_child(_banner_label)

	_banner_sub = Label.new()
	_banner_sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner_sub.offset_top = 22.0
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_font_size_override("font_size", 10)
	_banner_sub.add_theme_color_override("font_color", Color("a8cfc6"))
	_banner_sub.add_theme_color_override("font_shadow_color", Color(0.05, 0.04, 0.08, 0.9))
	_banner_sub.modulate.a = 0.0
	root.add_child(_banner_sub)

	add_child(_banner_layer)


func _show_zone_banner(zone_id: String) -> void:
	if _banner_label == null or DisplayServer.get_name() == "headless":
		return
	var spec: Dictionary = ZoneCatalog.zone_spec(zone_id)
	var title: String = String(spec.get("name", zone_id.to_upper()))
	var subtitle: String = String(spec.get("subtitle", ""))
	_banner_label.text = title
	_banner_sub.text = subtitle
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_label.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner_label, "modulate:a", 1.0, 0.35)
	_banner_tween.tween_property(_banner_sub, "modulate:a", 1.0, 0.35)
	_banner_tween.set_parallel(false)
	_banner_tween.tween_interval(1.8)
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner_label, "modulate:a", 0.0, 0.55)
	_banner_tween.tween_property(_banner_sub, "modulate:a", 0.0, 0.55)


# ------------------------------------------------------------------ Guards, Wildlife & Night

func _spawn_zone_guards(zone: ZoneInstance, spec: Dictionary) -> void:
	for g_v: Variant in spec.get("guards", []) as Array:
		if not (g_v is Dictionary):
			continue
		var g: Dictionary = g_v as Dictionary
		var pos_arr: Array = g.get("pos", [0, 0]) as Array
		var face_arr: Array = g.get("face", [1, 0]) as Array
		if pos_arr.size() < 2:
			continue
		var enemy_kind: String = String(g.get("enemy", "guard_spider"))
		var at: Vector2 = zone.slot_origin_px + Vector2(float(pos_arr[0]), float(pos_arr[1]))
		var face: Vector2 = Vector2(float(face_arr[0]), float(face_arr[1])).normalized() if face_arr.size() >= 2 else Vector2.RIGHT
		var mob: Node2D = spawn_species(enemy_kind, at, face.angle())
		if mob != null:
			zone.enemies.append(mob)


func _spawn_zone_wildlife(zone: ZoneInstance, spec: Dictionary) -> void:
	var cap: int = int(spec.get("wildlife_cap", 10))
	if cap <= 0:
		return
	var rabbit_scene: PackedScene = load(RABBIT_SCENE_PATH) as PackedScene if ResourceLoader.exists(RABBIT_SCENE_PATH) else null
	var bird_scene: PackedScene = load(BIRD_SCENE_PATH) as PackedScene if ResourceLoader.exists(BIRD_SCENE_PATH) else null
	if rabbit_scene == null and bird_scene == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(spec.get("world_seed", zone.zone_id.hash())) ^ TimeManager.day * 9137
	var w: int = zone.size_tiles.x
	var h: int = zone.size_tiles.y
	var spawned: int = 0
	var tries: int = 0
	while spawned < cap and tries < cap * 8:
		tries += 1
		var lx: int = rng.randi_range(10, w - 11)
		var ly: int = rng.randi_range(10, h - 11)
		var wpos: Vector2 = zone.slot_origin_px + Vector2(lx, ly) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
		if not zone.navigation_floor_at(wpos):
			continue
		if _things.has(zone.slot_origin_tile + Vector2i(lx, ly)):
			continue
		var use_bird: bool = bird_scene != null and (rabbit_scene == null or rng.randf() < 0.45)
		var critter: Node2D = (bird_scene if use_bird else rabbit_scene).instantiate() as Node2D
		critter.position = wpos
		_props.add_child(critter)
		zone.wildlife.append(critter)
		spawned += 1


func _tick_zone_night_spawns() -> void:
	if TimeManager.night_amount() < 0.45:
		return
	for zid_v: Variant in _zones.keys():
		var zid: String = String(zid_v)
		if not has_player_in_zone(zid):
			continue
		var zone: ZoneInstance = _zones[zid] as ZoneInstance
		var cfg: Dictionary = zone.spec.get("night_spawns", {}) as Dictionary
		if not bool(cfg.get("enabled", true)):
			continue
		if bool(cfg.get("require_opening_over", false)) and not opening_over:
			continue
		## Prune freed entries
		var alive: Array[Node2D] = []
		for e: Node2D in zone.enemies:
			if is_instance_valid(e):
				alive.append(e)
		zone.enemies = alive
		var max_e: int = int(cfg.get("max_enemies", 8))
		if alive.size() >= max_e:
			continue
		var candidate: Vector2 = _pick_night_spawn_pos(zone, cfg)
		if candidate != Vector2.INF:
			var kind: String = "shadow_spider" if randf() < 0.72 else "void_listener"
			var spawned: Node2D = spawn_species(kind, candidate, randf() * TAU)
			if spawned != null:
				zone.enemies.append(spawned)


func _pick_night_spawn_pos(zone: ZoneInstance, cfg: Dictionary) -> Vector2:
	var w: int = zone.size_tiles.x
	var h: int = zone.size_tiles.y
	var safe_town_radius: float = float(cfg.get("town_safe_radius", 240.0))
	for _attempt: int in range(16):
		var lx: int = randi_range(10, w - 11)
		var ly: int = randi_range(10, h - 11)
		var pos: Vector2 = zone.slot_origin_px + Vector2(lx, ly) * ZoneCatalog.TILE_PX + Vector2(8.0, 8.0)
		if not zone.navigation_floor_at(pos):
			continue
		if zone.hut_node != null and pos.distance_to(zone.hut_node.global_position) < safe_town_radius:
			continue
		var too_close: bool = false
		for p: Player in Player.all:
			if is_instance_valid(p) and p.global_position.distance_to(pos) < 220.0:
				too_close = true
				break
		if too_close:
			continue
		return pos
	return Vector2.INF


# ------------------------------------------------------------------ Shared WorldLevel Contracts

func water_depth(point: Vector2) -> float:
	if Interiors.slot_at(point) >= 0 or MineManager.in_mine(point):
		return -1.0
	var zid: String = ZoneCatalog.zone_id_at(point)
	if zid.is_empty() or not _zones.has(zid):
		return -1.0
	return (_zones[zid] as ZoneInstance).water_depth_at(point)


func navigation_floor(point: Vector2) -> bool:
	if Interiors.slot_at(point) >= 0:
		return true
	var zid: String = ZoneCatalog.zone_id_at(point)
	if zid.is_empty() or not _zones.has(zid):
		return false
	return (_zones[zid] as ZoneInstance).navigation_floor_at(point)


func coast_tiles(_point: Vector2 = Vector2.ZERO) -> float:
	return 999.0


func starting_health_ratio() -> float:
	return float(DataRegistry.get_entry("ground", "story_start").get("health_ratio", 0.1))


func is_hut_renewed() -> bool:
	return _hut_renewed


func set_hut_node(hut: Node2D) -> void:
	_hut_node = hut as Hut


func hut_node() -> Hut:
	return _hut_node


func town() -> TownManager:
	return _town_node


func register_zone_waystone(statue: WaystoneStatue, ws_spec: Dictionary, global_tile: Vector2i) -> void:
	if _waystones == null or statue == null:
		return
	var spec: Dictionary = ws_spec.duplicate()
	spec["tile"] = [global_tile.x, global_tile.y]
	spec["zone_id"] = ZoneCatalog.zone_id_at(statue.position)
	_waystones.register_spec(statue.id, spec)


func town_probe(rect: Rect2, exclude: Array[RID] = []) -> String:
	var home_id: String = ZoneCatalog.home_zone_id()
	var home: ZoneInstance = _zones.get(home_id) as ZoneInstance
	if home == null:
		return "KEIN LAND"
	var wide: Rect2 = rect.grow(8.0)
	for y: int in range(floori(wide.position.y / 16.0), floori(wide.end.y / 16.0) + 1):
		for x: int in range(floori(wide.position.x / 16.0), floori(wide.end.x / 16.0) + 1):
			var gt: Vector2i = Vector2i(x, y)
			if not home.is_land_global(gt):
				return "KEIN LAND"
	if not home.clear_world_pos_clear_for_prop(rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.5):
		return "ZU NAH AM WASSER"
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = rect.size - Vector2(2.0, 2.0)
	query.shape = box
	query.transform = Transform2D(0.0, rect.get_center())
	query.collision_mask = 1
	query.exclude = exclude
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return "IM WEG"
	return ""


func town_level_at(_point: Vector2) -> int:
	return 0


func town_walkable(point: Vector2, _level: int) -> bool:
	var home: ZoneInstance = _zones.get(ZoneCatalog.home_zone_id()) as ZoneInstance
	if home == null:
		return false
	if not home.navigation_floor_at(point):
		return false
	if not home.clear_world_pos_clear_for_prop(point, 4.0):
		return false
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 5.0
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _town_soft(thing: WorldProp) -> bool:
	if thing.kind in (TownRules.config().get("soft_kinds", []) as Array):
		return true
	if thing.kind in PropGenerator.TREE_KINDS:
		return thing.state.has("f")
	return thing.kind in ["rock", "iron_rock", "curse_rock", "sun_quartz_rock", "prism_vein", "ruin_sandstone"] and thing.is_depleted()


func town_soft_cells(rect: Rect2) -> Array:
	var out: Array = []
	for cell: Vector2i in _things:
		var thing: WorldProp = _things[cell] as WorldProp
		if is_instance_valid(thing) and _town_soft(thing) and rect.grow(thing._radius * 0.8).has_point(thing.position):
			out.append(cell)
	return out


func town_wave_cells(center: Vector2, radius: float, circles: Array[Vector3]) -> Array:
	var out: Array = []
	for cell: Vector2i in _things:
		var thing: WorldProp = _things[cell] as WorldProp
		if not is_instance_valid(thing):
			continue
		if thing.position.distance_to(center) > radius or not (_town_soft(thing) or (thing is Bush and not thing.kind in PropGenerator.TREE_KINDS)):
			continue
		if TownRules.light_depth(circles, thing.position) > 0.0:
			out.append(cell)
	return out


func prop_node(cell: Vector2i) -> WorldProp:
	return _things.get(cell) as WorldProp


func prop_position(cell: Vector2i) -> Vector2:
	var thing: WorldProp = _things.get(cell) as WorldProp
	return thing.position if is_instance_valid(thing) else PropGenerator.position_of(cell)


func town_wave_yield(cell: Vector2i) -> String:
	var thing: WorldProp = _things.get(cell) as WorldProp
	if not is_instance_valid(thing) or thing.is_depleted():
		return ""
	var pickup: Dictionary = thing._spec.get("pickup", {}) as Dictionary
	if pickup.has("item") and not thing.state.has("p"):
		return String(pickup.item)
	for drop: Variant in ((thing._spec.get("harvest", {}) as Dictionary).get("drops", []) as Array):
		if randf() < float((drop as Dictionary).get("chance", 0.0)) * 1.4:
			return String((drop as Dictionary).id)
	return ""


func town_uproot(cells: Array, _origin: Vector2, _speed: float, _delay: float) -> void:
	town_clear_cells(cells)


func town_clear_clover(_at: Vector2, _radius: float) -> Array:
	return []


func town_clear_cells(cells: Array) -> void:
	for raw: Variant in cells:
		var cell: Vector2i = raw as Vector2i
		_thing_states.erase(cell)
		if not _things.has(cell):
			continue
		var thing: WorldProp = _things[cell] as WorldProp
		_things.erase(cell)
		for zone: ZoneInstance in _zones.values():
			zone.things.erase(cell)
		if is_instance_valid(thing):
			thing.queue_free()


# ------------------------------------------------------------------ Harvest & Props State

func thing_state(cell: Vector2i) -> Dictionary:
	return (_thing_states.get(cell, {}) as Dictionary)


func request_pick(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_pick_cell(cell, multiplayer.get_unique_id())
	else:
		_rpc_request_pick.rpc_id(1, cell)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pick(cell: Vector2i) -> void:
	if multiplayer.is_server():
		_pick_cell(cell, multiplayer.get_remote_sender_id())


func _pick_cell(cell: Vector2i, peer_id: int) -> void:
	var thing: WorldProp = _things.get(cell) as WorldProp
	if not is_instance_valid(thing):
		return
	var pickup: Dictionary = thing._spec.get("pickup", {}) as Dictionary
	if pickup.is_empty() or thing.state.has("p"):
		return
	var who: Player = _find_player_by_id(peer_id)
	if who == null or who.global_position.distance_to(thing.global_position) > 60.0:
		return
	var st: Dictionary = (_thing_states.get(cell, {}) as Dictionary).duplicate()
	st["p"] = 1
	st["k"] = thing.kind
	_thing_states[cell] = st
	who.inventory.give(String(pickup.item), int(pickup.get("count", 1)))
	_rpc_apply_thing_state.rpc(cell, st, "pick")


func harvest_hit(thing: WorldProp, _source: int) -> void:
	if not multiplayer.is_server() or not is_instance_valid(thing):
		return
	var cell: Vector2i = thing.cell
	var harvest: Dictionary = thing._spec.get("harvest", {}) as Dictionary
	if harvest.is_empty() or thing.is_depleted():
		return
	var st: Dictionary = (_thing_states.get(cell, {}) as Dictionary).duplicate()
	st["k"] = thing.kind
	var hits_needed: int = int(harvest.get("hits", 3))
	var cur_hits: int = int(st.get("h", 0)) + 1
	st["h"] = cur_hits
	for d_v: Variant in harvest.get("drops", []) as Array:
		var d: Dictionary = d_v as Dictionary
		if randf() < float(d.get("chance", 0.0)):
			_spawn_harvest_drop(thing.global_position, String(d.id), randi_range(int(d.get("min", 1)), int(d.get("max", 1))))
	if cur_hits >= hits_needed:
		if thing.kind in PropGenerator.TREE_KINDS:
			st["f"] = 1
		else:
			st["d"] = 1
		for fd_v: Variant in harvest.get("final_drops", []) as Array:
			var fd: Dictionary = fd_v as Dictionary
			if randf() < float(fd.get("chance", 1.0)):
				_spawn_harvest_drop(thing.global_position, String(fd.id), randi_range(int(fd.get("min", 1)), int(fd.get("max", 1))))
	_thing_states[cell] = st
	_rpc_apply_thing_state.rpc(cell, st, "hit")


func _spawn_harvest_drop(pos: Vector2, item_id: String, count: int) -> void:
	var drop_scene: PackedScene = load("res://src/entities/drops/item_drop.tscn") as PackedScene
	if drop_scene == null:
		return
	var drops_node: Node = get_node_or_null("Drops")
	if drops_node == null:
		return
	for _i: int in range(maxi(count, 1)):
		var drop: Node2D = drop_scene.instantiate() as Node2D
		drop.set("item_id", item_id)
		drop.set("count", 1)
		drop.position = pos + Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 10.0))
		drops_node.add_child(drop)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_thing_state(cell: Vector2i, st: Dictionary, reason: String) -> void:
	_thing_states[cell] = st
	var thing: WorldProp = _things.get(cell) as WorldProp
	if is_instance_valid(thing):
		thing.apply_state(st, reason)


func _grow_things(_day: int) -> void:
	if not multiplayer.is_server():
		return
	for cell: Variant in _thing_states.keys():
		var c: Vector2i = cell as Vector2i
		var st: Dictionary = _thing_states[c] as Dictionary
		if st.has("p"):
			st.erase("p")
		if st.has("d") and int(st.get("d", 0)) > 0:
			st.erase("d")
			st.erase("h")
		_rpc_apply_thing_state.rpc(c, st, "")


# ------------------------------------------------------------------ Story & Quest Hooks

func finish_opening() -> void:
	opening_over = true
	if multiplayer.is_server():
		TimeManager.paused = false
		ensure_zone_loaded(ZoneCatalog.home_zone_id())


func start_intro() -> void:
	var p: Player = _find_local_player()
	if p == null or cover_node == null:
		return
	if p.get_node_or_null("IntroScene") != null:
		return
	var scene: IntroScene = IntroScene.new()
	scene.name = "IntroScene"
	p.add_child(scene)
	scene.start(p, cover_node)


func start_wake(player: Player) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	if player.get_node_or_null("WakeScene") != null:
		return
	var scene: WakeScene = WakeScene.new()
	scene.name = "WakeScene"
	player.add_child(scene)
	scene.start(player, self)


func start_ambush(player: Player) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	if player.get_node_or_null("AmbushScene") != null:
		return
	ensure_zone_loaded(ZoneCatalog.home_zone_id())
	var home_id: String = ZoneCatalog.home_zone_id()
	_player_zones[player.name.to_int()] = home_id
	var scene: AmbushScene = AmbushScene.new()
	scene.name = "AmbushScene"
	player.add_child(scene)
	scene.start(player, self)


func spawn_story_spider(species_id: String, at: Vector2, heading: float) -> ShadowSpider:
	return spawn_species(species_id, at, heading) as ShadowSpider


func take_knight() -> Vector2:
	return Vector2.INF


func take_torben() -> Vector2:
	for node: Node in get_tree().get_nodes_in_group("torben_camp"):
		var camp: TorbenCamp = node as TorbenCamp
		if camp != null:
			return camp.take_torben()
	return Vector2.INF


func place_knight(_where: String) -> void:
	pass


func is_waiting_in_bed(_player: Player) -> bool:
	return false


func request_bed_leave(_player: Player) -> void:
	pass


func request_bed_sleep(player: Player) -> void:
	start_sleep(player, true)


func start_fire_scene(_player: Player, _seat: String) -> void:
	pass


func start_sleep(player: Player, rest: bool = false) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	if player.get_node_or_null("SleepScene") != null:
		return
	var scene: SleepScene = SleepScene.new()
	scene.name = "SleepScene"
	player.add_child(scene)
	scene.start(player, self, rest)


func resume_story(player: Player) -> void:
	if player == null or player.quests == null:
		return
	if player.quests.active_step_id("find_help") == "wake":
		start_wake(player)
	if player.quests.has_flag("rebuild_done"):
		_hut_renewed = true
		if is_instance_valid(_hut_node):
			_hut_node.set_renewed(true)


func resolve_quest_tile(old_tile: Vector2i) -> Vector2i:
	## Maps WorldLevel data/quests.json coordinates cleanly into active ZoneWorld slots.
	if old_tile.x >= 430 and old_tile.x <= 555 and old_tile.y >= 590 and old_tile.y <= 735:
		var spec_s: Dictionary = ZoneCatalog.zone_spec("start_path")
		var off_s: Array = spec_s.get("old_world_tile_offset", [438, 594]) as Array
		return (old_tile - Vector2i(int(off_s[0]), int(off_s[1]))) + ZoneCatalog.slot_origin_tile("start_path")
	if old_tile.x >= 735 and old_tile.x <= 845 and old_tile.y >= 625 and old_tile.y <= 735:
		var spec_h: Dictionary = ZoneCatalog.zone_spec("home_valley")
		var off_h: Array = spec_h.get("old_world_tile_offset", [698, 608]) as Array
		return (old_tile - Vector2i(int(off_h[0]), int(off_h[1]))) + ZoneCatalog.slot_origin_tile("home_valley")
	return old_tile


# ------------------------------------------------------------------ Save / Load Persistence

func export_things() -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in _thing_states:
		out["%d,%d" % [cell.x, cell.y]] = _thing_states[cell]
	return out


func import_things(saved: Dictionary) -> void:
	_thing_states.clear()
	for key_v: Variant in saved:
		var key: String = String(key_v)
		if key.begins_with("s:") or key.begins_with("r:") or key.begins_with("h:") or not (saved[key_v] is Dictionary):
			continue
		var parts: PackedStringArray = key.split(",")
		if parts.size() < 2:
			continue
		var raw_entry: Dictionary = saved[key_v] as Dictionary
		var state: Dictionary = {}
		for field: Variant in raw_entry:
			var v: Variant = raw_entry[field]
			state[String(field)] = int(v) if v is float else v
		_thing_states[Vector2i(int(parts[0]), int(parts[1]))] = state
	for cell: Vector2i in _things:
		var thing: WorldProp = _things[cell] as WorldProp
		if is_instance_valid(thing):
			thing.apply_state(thing_state(cell), "")


func export_story() -> Dictionary:
	return {"hut_renewed": _hut_renewed}


func import_story(data: Dictionary) -> void:
	_hut_renewed = bool(data.get("hut_renewed", false))


func export_zone_state() -> Dictionary:
	var pz: Dictionary = {}
	for k: Variant in _player_zones:
		pz[str(k)] = String(_player_zones[k])
	return {
		"player_zones": pz,
		"discovered": _discovered.keys(),
		"opening_over": opening_over,
	}


func import_zone_state(data: Dictionary) -> void:
	opening_over = bool(data.get("opening_over", false))
	_discovered = {"start_path": true}
	for z_v: Variant in SaveGame.as_array(data.get("discovered")):
		var zid: String = String(z_v)
		if not zid.is_empty():
			_discovered[zid] = true
	var pz: Dictionary = SaveGame.as_dict(data.get("player_zones"))
	for k: Variant in pz:
		var zid: String = String(pz[k])
		if not zid.is_empty():
			var pid: int = String(k).to_int()
			_player_zones[pid] = zid
			ensure_zone_loaded(zid)


# ------------------------------------------------------------------ Helpers

func _on_player_node_entered(node: Node) -> void:
	if not (node is Player):
		return
	var p: Player = node as Player
	var pid: int = p.name.to_int()
	if not _player_zones.has(pid):
		var start_z: String = ZoneCatalog.zone_id_at(Interiors.outer(get_tree(), p.position))
		if start_z.is_empty():
			start_z = ZoneCatalog.home_zone_id() if opening_over else ZoneCatalog.start_zone_id()
		_player_zones[pid] = start_z
	if p.is_multiplayer_authority():
		call_deferred("_post_local_player_ready", p)


func _post_local_player_ready(p: Player) -> void:
	if not is_instance_valid(p):
		return
	var zid: String = String(_player_zones.get(p.name.to_int(), ZoneCatalog.start_zone_id()))
	ensure_zone_loaded(zid)
	_last_local_zone = zid
	apply_camera_bounds(p)
	_show_zone_banner(zid)


func _on_peer_connected_sync(peer_id: int) -> void:
	_rpc_sync_zone_presence.rpc_id(peer_id, _player_zones, _discovered)


func _on_peer_disconnected_cleanup(peer_id: int) -> void:
	_player_zones.erase(peer_id)
	unload_unused_zones()


func _find_local_player() -> Player:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority():
			return p
	return null


func _find_player_by_id(peer_id: int) -> Player:
	var key: String = str(peer_id)
	for p: Player in Player.all:
		if is_instance_valid(p) and p.name == key:
			return p
	return null
