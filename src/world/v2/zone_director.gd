class_name ZoneDirector
extends Node2D
## Streams the zones of one continent around the players (docs/v2_zonenwelt_atlas_konzept.md 6.1-6.5, 13 steps 3 & 9).
##
## * Host (`multiplayer.is_server()`): streams around EVERY connected player (every occupied zone, including outer zones
##   held while a player is inside `PocketSpace`, plus announced neighbour zones within `PRELOAD_TILES`, hysteresis
##   `KEEP_TILES`).
## * Client (`not multiplayer.is_server()`): streams ONLY around its own local player (`multiplayer.get_unique_id()`),
##   unloading zones beyond `KEEP_TILES` even when other players stand in distant zones (concept 6.5).
## * A zone is built by `ZoneStage.build` on ONE `Jobs` worker at a time (2-6 s for a small zone) while its tree sheets
##   load in the background (`Jobs.request_warm`), then attached on the main thread in slices of `ATTACH_BUDGET_USEC`
##   per frame (`ZoneStage.attach_step`): no frame stalls. `Terrain.patches` is only changed (attach/unload) while no
##   build runs: `LivingGrass` reads it on the worker.
## * A seamless threshold is open only while BOTH sides are attached and its story flag allows it; until then a gate
##   segment on its line holds the player back (normally never felt: the neighbour is ready long before).
## * The host decides which zone each player is in (`player_zone`, signal `zone_changed`) and broadcasts it.
## * Unloaded zones keep their state in `_saved` {id: {trees, day}}; on attach the host catches up the missed days.
##   `export_state`/`import_state` are the save block. A client asks the host for the live state of a zone it attaches.

signal zone_changed(peer_id: int, zone_id: StringName)
signal stage_attached(zone_id: StringName)
signal stage_detached(zone_id: StringName)

const PRELOAD_TILES: float = 48.0
const KEEP_TILES: float = 64.0
const XL_PRELOAD_TILES: float = 78.0 ## XL zones (e.g. Suedkap) preload earlier so seamless crossings never pause!
const XL_KEEP_TILES: float = 96.0
const TICK: float = 0.25
const ATTACH_BUDGET_USEC: int = 4000 ## main-thread time per frame for attaching a zone

var atlas: Atlas
var continent_id: StringName = &"main"
var tileset: TileSet
var ground_material: Material
var players_root: Node2D
var flags_source: Callable = Callable() ## () -> Dictionary of story flags; empty = no flags
var stages: Dictionary = {} ## zone id -> ZoneStage (attached)
var player_zone: Dictionary = {} ## peer id -> zone id (host truth, mirrored)
var build_log: Array[Dictionary] = [] ## {zone, msec (build on the worker), attach_frames, attach_worst_ms} per zone (tests, status)
var _saved: Dictionary = {} ## zone id -> {"trees": {...}, "day": int}
var _peer_stages: Dictionary = {} ## host-only: peer id (int) -> {zone_id (StringName): true}
var _job: Jobs.Job = null
var _job_zone: StringName = &""
var _job_started: int = 0
var _job_sheets: Array[String] = []
var _attaching: ZoneStage = null ## added, being attached slice by slice
var _attach_msec: int = 0
var _tick: float = 0.0
var mood: ZoneMood ## the blended mood at the camera (step 5)
var arrival: ZoneArrival ## the inscriptions on entering a zone or a place (step 5)
var coop: ZoneCoop ## visibility filter, map pings & peer-join RPCs (step 9)
var seen: Dictionary = {"zones": {}, "places": {}} ## what the local player has entered (saved)


func _ready() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_sync_client_with_host):
		multiplayer.connected_to_server.connect(_sync_client_with_host)
	if not multiplayer.is_server():
		_sync_client_with_host.call_deferred()


func setup(p_atlas: Atlas, p_continent: StringName, p_tileset: TileSet, p_material: Material, p_players: Node2D) -> void:
	atlas = p_atlas
	continent_id = p_continent
	tileset = p_tileset
	ground_material = p_material
	players_root = p_players
	name = "Zones"
	y_sort_enabled = true
	Jobs.warm([ZoneStage.TREE_SCENE_PATH])
	Landscape.of(atlas, continent_id) ## planned once here, on the main thread: builds on workers only read it
	mood = ZoneMood.new()
	mood.name = "Mood"
	mood.setup(atlas, continent_id)
	add_child(mood)
	arrival = ZoneArrival.new()
	arrival.setup(self)
	add_child(arrival)
	coop = ZoneCoop.new()
	coop.name = "Coop"
	coop.setup(self)
	add_child(coop)


func _is_host() -> bool:
	return not is_inside_tree() or multiplayer.multiplayer_peer == null or multiplayer.is_server()


func is_loaded(zone_id: StringName) -> bool:
	return stages.has(zone_id)


## A zone is being built or attached.
func is_building() -> bool:
	return _job != null or _attaching != null


func stage(zone_id: StringName) -> ZoneStage:
	return stages.get(zone_id) as ZoneStage


func player_body(peer_id: int) -> Node2D:
	if players_root == null or peer_id <= 0:
		return null
	return players_root.get_node_or_null(str(peer_id)) as Node2D


## Resolves the continent zone owning `world_pos` (including PocketSpace parent zone and near borderland).
func zone_for_world_pos(world_pos: Vector2) -> StringName:
	if atlas == null or not world_pos.is_finite():
		return &""
	if PocketSpace.is_pocket(world_pos):
		var pz: StringName = PocketSpace.parent_zone_at(world_pos)
		if pz != &"" and atlas.zone(pz) != null and atlas.zone(pz).continent == continent_id:
			return pz
		if is_inside_tree():
			var outer_p: Vector2 = Interiors.outer(get_tree(), world_pos)
			if not PocketSpace.is_pocket(outer_p) and outer_p.is_finite():
				var oz: StringName = atlas.zone_at(continent_id, outer_p)
				if oz != &"":
					return oz
		return &""
	var direct: StringName = atlas.zone_at(continent_id, world_pos)
	if direct != &"":
		return direct
	var tile: Vector2 = Atlas.tile_of(world_pos)
	var best_id: StringName = &""
	var best_d: float = ZoneStage.BORDER_TILES + 4.0
	for z: Atlas.Zone in atlas.zones_of(continent_id):
		if not z.bbox.grow(best_d).has_point(tile):
			continue
		var d: float = Atlas.edge_distance(tile, z.footprint)
		if d <= best_d:
			best_d = d
			best_id = z.id
	return best_id


## Effective outer continent zone of `peer_id` (resolves `PocketSpace.parent_zone_at` or last `player_zone[peer]`).
func effective_player_zone(peer_id: int) -> StringName:
	var body: Node2D = player_body(peer_id)
	if body != null and atlas != null:
		var pos: Vector2 = body.global_position if body.is_inside_tree() else body.position
		if PocketSpace.is_pocket(pos):
			var pz: StringName = PocketSpace.parent_zone_at(pos)
			if pz != &"" and atlas.zone(pz) != null and atlas.zone(pz).continent == continent_id:
				return pz
			if is_inside_tree():
				var outer_p: Vector2 = Interiors.outer(get_tree(), pos)
				if not PocketSpace.is_pocket(outer_p) and outer_p.is_finite():
					var oz: StringName = atlas.zone_at(continent_id, outer_p)
					if oz != &"":
						return oz
			return player_zone.get(peer_id, &"") as StringName
		var here: StringName = atlas.zone_at(continent_id, pos)
		if here != &"":
			return here
	return player_zone.get(peer_id, &"") as StringName


## Build and attach a zone right now on the main thread (the start zone, before the players spawn).
func load_now(zone_id: StringName) -> ZoneStage:
	if stages.has(zone_id):
		return stages[zone_id] as ZoneStage
	_finish_job() ## never two builds against Terrain.patches
	var zone: Atlas.Zone = atlas.zone(zone_id)
	if zone == null:
		push_error("ZoneDirector: unknown zone %s" % zone_id)
		return null
	var t0: int = Time.get_ticks_msec()
	var built: ZoneStage = ZoneStage.build(atlas, zone, tileset, ground_material, _saved.get(zone_id, {}) as Dictionary)
	if built == null:
		return null
	built.sheets = ZoneStage.sheet_paths(zone)
	add_child(built)
	built.attach_step(0)
	_complete(built, Time.get_ticks_msec() - t0)
	return built


func _process(delta: float) -> void:
	if _attaching != null:
		var growing: ZoneStage = _attaching
		if growing.attach_step(Time.get_ticks_usec() + ATTACH_BUDGET_USEC):
			_attaching = null
			_complete(growing, _attach_msec)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	if _is_host():
		_update_player_zones()
	_stream()
	_update_gates()


# --- which zone a player is in (host) ------------------------------------------------------------------------------

func set_player_zone(peer: int, zone_id: StringName) -> void:
	if not _is_host() or peer <= 0 or zone_id == &"":
		return
	if player_zone.get(peer, &"") == zone_id:
		return
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_player_zone.rpc(peer, String(zone_id))
	else:
		_rpc_player_zone(peer, String(zone_id))


func _update_player_zones() -> void:
	if players_root == null or atlas == null:
		return
	for child: Node in players_root.get_children():
		var body: Node2D = child as Node2D
		if body == null or not child.name.is_valid_int():
			continue
		var peer: int = child.name.to_int()
		var pos: Vector2 = body.global_position
		var here: StringName = &""
		if PocketSpace.is_pocket(pos):
			var pz: StringName = PocketSpace.parent_zone_at(pos)
			if pz != &"" and atlas.zone(pz) != null and atlas.zone(pz).continent == continent_id:
				here = pz
			elif is_inside_tree():
				var outer_p: Vector2 = Interiors.outer(get_tree(), pos)
				if not PocketSpace.is_pocket(outer_p) and outer_p.is_finite():
					here = atlas.zone_at(continent_id, outer_p)
			if here == &"":
				here = player_zone.get(peer, &"") as StringName
		else:
			here = atlas.zone_at(continent_id, pos)
		if here == &"" or player_zone.get(peer, &"") == here:
			continue ## the borderland / pocket keeps the last zone
		set_player_zone(peer, here)


@rpc("authority", "call_local", "reliable")
func _rpc_player_zone(peer: int, zone_id: String) -> void:
	var zid: StringName = StringName(zone_id)
	player_zone[peer] = zid
	zone_changed.emit(peer, zid)


@rpc("authority", "call_remote", "reliable")
func _rpc_player_zone_snapshot(snapshot: Dictionary) -> void:
	for k: Variant in snapshot:
		var peer: int = int(k)
		var zid: StringName = StringName(String(snapshot[k]))
		if peer > 0 and zid != &"" and player_zone.get(peer, &"") != zid:
			player_zone[peer] = zid
			zone_changed.emit(peer, zid)


@rpc("authority", "call_local", "reliable")
func _rpc_peer_removed(peer: int) -> void:
	player_zone.erase(peer)


func _on_peer_connected(_peer: int) -> void:
	pass ## client calls `_rpc_sync_client_director` once its `ZoneDirector` is inside the scene tree


func _on_peer_disconnected(peer: int) -> void:
	_peer_stages.erase(peer)
	if _is_host():
		if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
			_rpc_peer_removed.rpc(peer)
		else:
			_rpc_peer_removed(peer)


func _sync_client_with_host() -> void:
	if _is_host() or not NetworkManager.rpc_ready(self):
		return
	var loaded_ids: PackedStringArray = PackedStringArray()
	for zid: StringName in stages:
		loaded_ids.append(String(zid))
	_rpc_sync_client_director.rpc_id(1, loaded_ids)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_sync_client_director(loaded_ids: PackedStringArray) -> void:
	if not _is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 1:
		return
	var set_dict: Dictionary = {}
	for raw_id: String in loaded_ids:
		var zid: StringName = StringName(raw_id)
		set_dict[zid] = true
		var own: ZoneStage = stages.get(zid) as ZoneStage
		if own != null:
			_rpc_zone_state.rpc_id(sender, raw_id, own.export_state())
	_peer_stages[sender] = set_dict
	var snap: Dictionary = {}
	for p: Variant in player_zone:
		snap[int(p)] = String(player_zone[p])
	if not snap.is_empty():
		_rpc_player_zone_snapshot.rpc_id(sender, snap)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_stage_detached(zone_id: String) -> void:
	if not _is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _peer_stages.has(sender):
		(_peer_stages[sender] as Dictionary).erase(StringName(zone_id))


# --- per-peer streaming & relevance ---------------------------------------------------------------------------------

func _preload_tiles(zone: Atlas.Zone) -> float:
	return XL_PRELOAD_TILES if (zone != null and zone.size_class == "XL") else PRELOAD_TILES


func _keep_tiles(zone: Atlas.Zone) -> float:
	return XL_KEEP_TILES if (zone != null and zone.size_class == "XL") else KEEP_TILES


func _has_open_seamless_link(from_zone: StringName, to_zone: StringName, flags: Dictionary) -> bool:
	if atlas == null:
		return false
	for t: Atlas.Threshold in atlas.thresholds_of(to_zone):
		if not t.seamless() or not Atlas.is_threshold_open(t, flags):
			continue
		if from_zone == &"" or t.touches(from_zone):
			return true
	return false


## True when `zone_id` is `peer_id`'s current/held zone or an adjacent zone within `max_tiles`.
func is_zone_relevant_for_peer(peer_id: int, zone_id: StringName, max_tiles: float = KEEP_TILES) -> bool:
	if zone_id == &"" or atlas == null:
		return false
	if peer_id == 1 and _is_host():
		return stages.has(zone_id)
	var body: Node2D = player_body(peer_id)
	if body == null:
		return false
	var pos: Vector2 = body.global_position if body.is_inside_tree() else body.position
	if PocketSpace.is_pocket(pos):
		return effective_player_zone(peer_id) == zone_id
	var pzone: StringName = effective_player_zone(peer_id)
	if pzone == zone_id:
		return true
	var z: Atlas.Zone = atlas.zone(zone_id)
	if z == null or z.continent != continent_id:
		return false
	var eff_max: float = maxf(max_tiles, _keep_tiles(z)) if is_equal_approx(max_tiles, KEEP_TILES) else max_tiles
	var ptile: Vector2 = Atlas.tile_of(pos)
	if not z.bbox.grow(eff_max).has_point(ptile):
		return false
	if Atlas.edge_distance(ptile, z.footprint) > eff_max:
		return false
	var peer_loaded: Dictionary = _peer_stages.get(peer_id, {}) as Dictionary
	return peer_loaded.has(zone_id) or _has_open_seamless_link(pzone, zone_id, _flags())


## Remote client peer IDs that currently have `zone_id` attached and remain within range (safe targets for `LivingTree` RPCs).
func peers_holding_zone(zone_id: StringName) -> Array[int]:
	var out: Array[int] = []
	if not _is_host() or not is_inside_tree() or multiplayer.multiplayer_peer == null:
		return out
	var z: Atlas.Zone = atlas.zone(zone_id) if atlas != null else null
	var hold_tiles: float = _keep_tiles(z) - 1.5
	for peer: int in multiplayer.get_peers():
		var peer_loaded: Dictionary = _peer_stages.get(peer, {}) as Dictionary
		if peer_loaded.has(zone_id) and is_zone_relevant_for_peer(peer, zone_id, hold_tiles):
			out.append(peer)
	return out


func peer_has_stage_attached(peer_id: int, zone_id: StringName) -> bool:
	if peer_id == 1 and _is_host():
		return stages.has(zone_id)
	return (_peer_stages.get(peer_id, {}) as Dictionary).has(zone_id)


## Collects streaming anchors `{tile, zone}` and held zones `{zone_id: true}`:
## - Host: around ALL connected players (including outer parent zones of players inside `PocketSpace`).
## - Client: ONLY around the local player (`multiplayer.get_unique_id()`).
func _collect_stream_state() -> Dictionary:
	var anchors: Array[Dictionary] = []
	var held: Dictionary = {}
	if players_root == null or atlas == null:
		return {"anchors": anchors, "held": held}
	var host_mode: bool = _is_host()
	var local_id: int = multiplayer.get_unique_id() if is_inside_tree() and multiplayer.multiplayer_peer != null else 1
	for child: Node in players_root.get_children():
		var body: Node2D = child as Node2D
		if body == null or not child.name.is_valid_int():
			continue
		var peer: int = child.name.to_int()
		if not host_mode and peer != local_id:
			continue
		var pos: Vector2 = body.global_position
		if PocketSpace.is_pocket(pos):
			var held_z: StringName = effective_player_zone(peer)
			if held_z != &"":
				held[held_z] = true
			if is_inside_tree():
				var outer_p: Vector2 = Interiors.outer(get_tree(), pos)
				if not PocketSpace.is_pocket(outer_p) and outer_p.is_finite():
					anchors.append({"tile": Atlas.tile_of(outer_p), "zone": held_z})
			continue
		var tile: Vector2 = Atlas.tile_of(pos)
		var here_z: StringName = atlas.zone_at_tile(continent_id, tile)
		var own_z: StringName = here_z
		if own_z != &"":
			held[own_z] = true
		else:
			var last_z: StringName = player_zone.get(peer, &"") as StringName
			if last_z != &"":
				var lz_obj: Atlas.Zone = atlas.zone(last_z)
				if lz_obj != null and lz_obj.continent == continent_id and Atlas.edge_distance(tile, lz_obj.footprint) <= _keep_tiles(lz_obj):
					own_z = last_z
					held[last_z] = true
		anchors.append({"tile": tile, "zone": own_z})
	return {"anchors": anchors, "held": held}


func _stream_distance(zone: Atlas.Zone, anchors: Array[Dictionary], held: Dictionary, flags: Dictionary, require_open_link: bool) -> float:
	if held.has(zone.id):
		return 0.0
	var keep_t: float = _keep_tiles(zone)
	var best: float = INF
	for anc: Dictionary in anchors:
		var tile: Vector2 = anc["tile"] as Vector2
		if not zone.bbox.grow(keep_t).has_point(tile):
			continue
		if zone.contains(tile):
			return 0.0
		if require_open_link:
			var from_z: StringName = anc["zone"] as StringName
			if not _has_open_seamless_link(from_z, zone.id, flags):
				continue
		best = minf(best, Atlas.edge_distance(tile, zone.footprint))
	return best


func _stream() -> void:
	var st: Dictionary = _collect_stream_state()
	var anchors: Array[Dictionary] = st["anchors"] as Array[Dictionary]
	var held: Dictionary = st["held"] as Dictionary
	if anchors.is_empty() and held.is_empty():
		return
	var flags: Dictionary = _flags()
	var wanted: Array[Dictionary] = [] ## {zone, d}
	for zone: Atlas.Zone in atlas.zones_of(continent_id):
		if stages.has(zone.id):
			var d_keep: float = _stream_distance(zone, anchors, held, flags, false)
			if d_keep > _keep_tiles(zone) and not is_building():
				_unload(zone.id)
			continue
		var d_pre: float = _stream_distance(zone, anchors, held, flags, true)
		if d_pre <= _preload_tiles(zone) and zone.id != _job_zone and (_attaching == null or _attaching.zone.id != zone.id):
			wanted.append({"zone": zone, "d": d_pre})
	if is_building() or wanted.is_empty():
		return
	wanted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	_start_build(wanted[0]["zone"] as Atlas.Zone)


func _start_build(zone: Atlas.Zone) -> void:
	var p_atlas: Atlas = atlas
	var p_tiles: TileSet = tileset
	var p_mat: Material = ground_material
	var p_saved: Dictionary = (_saved.get(zone.id, {}) as Dictionary).duplicate(true)
	_job_zone = zone.id
	_job_started = Time.get_ticks_msec()
	_job_sheets = ZoneStage.sheet_paths(zone)
	Jobs.request_warm(_job_sheets) ## loads in the background while the zone is built
	_job = Jobs.run(
		func() -> Variant: return ZoneStage.build(p_atlas, zone, p_tiles, p_mat, p_saved),
		_on_built,
		Jobs.Prio.HIGH,
		_on_discard,
		"zone:" + String(zone.id))


func _on_built(result: Variant) -> void:
	var built: ZoneStage = result as ZoneStage
	var msec: int = Time.get_ticks_msec() - _job_started
	_job = null
	_job_zone = &""
	if built == null:
		return
	var st: Dictionary = _collect_stream_state()
	var anchors: Array[Dictionary] = st["anchors"] as Array[Dictionary]
	var held: Dictionary = st["held"] as Dictionary
	if stages.has(built.zone.id) or _stream_distance(built.zone, anchors, held, _flags(), false) > _keep_tiles(built.zone):
		built.free() ## nobody on this peer needs it any more
		return
	built.sheets = _job_sheets
	add_child(built)
	_attaching = built ## `_process` attaches it slice by slice from this frame on
	_attach_msec = msec


func _on_discard(result: Variant) -> void:
	var built: ZoneStage = result as ZoneStage
	if built != null:
		built.free()


## Finish a running build and attach (main thread computes it if it has not started).
func _finish_job() -> void:
	if _job != null:
		Jobs.wait(_job) ## delivers through `_on_built`
	if _attaching != null:
		var growing: ZoneStage = _attaching
		_attaching = null
		growing.attach_step(0)
		_complete(growing, _attach_msec)


## The zone is fully attached: it counts as loaded, catches up (host) or asks for the live state (client).
func _complete(built: ZoneStage, msec: int) -> void:
	var zone_id: StringName = built.zone.id
	stages[zone_id] = built
	build_log.append({"zone": zone_id, "msec": msec, "attach_frames": built.attach_frames, "attach_worst_ms": snappedf(built.attach_worst_ms, 0.1)})
	var kept: Dictionary = _saved.get(zone_id, {}) as Dictionary
	if _is_host():
		if kept.has("day"):
			built.catch_up(TimeManager.day - int(kept["day"]))
	elif NetworkManager.rpc_ready(self):
		_rpc_request_zone.rpc_id(1, String(zone_id))
	_saved.erase(zone_id)
	# Never flash a redundant dark veil on the brand-new stage for thresholds whose neighbor is already attached & open!
	var open_flags: Dictionary = _flags()
	for t: Atlas.Threshold in atlas.thresholds_of(zone_id):
		if t.seamless() and stages.has(t.other(zone_id)) and Atlas.is_threshold_open(t, open_flags):
			var bv: ZoneVeil = built.veil(t.id)
			if bv != null:
				bv.set_shut(false, true)
	stage_attached.emit(zone_id)
	_update_gates()


func _unload(zone_id: StringName) -> void:
	var gone: ZoneStage = stages.get(zone_id) as ZoneStage
	stages.erase(zone_id)
	if gone == null:
		return
	if _is_host():
		var kept: Dictionary = gone.export_state()
		kept["day"] = TimeManager.day
		_saved[zone_id] = kept
	elif NetworkManager.rpc_ready(self):
		_rpc_client_stage_detached.rpc_id(1, String(zone_id))
	remove_child(gone) ## leaves Terrain.patches / layers right now, not at the end of the frame
	gone.queue_free()
	stage_detached.emit(zone_id)
	_update_gates()


# --- thresholds -----------------------------------------------------------------------------------------------------

## The story flags thresholds and zones wait for (HUD routing, docs/hud_v2_konzept.md 3.B).
func flags() -> Dictionary:
	return _flags()


func _flags() -> Dictionary:
	if flags_source.is_valid():
		var raw: Variant = flags_source.call()
		if raw is Dictionary:
			return raw as Dictionary
	return {}


func _update_gates() -> void:
	var flags: Dictionary = _flags()
	for zone_id: StringName in stages:
		var own: ZoneStage = stages[zone_id] as ZoneStage
		for t: Atlas.Threshold in atlas.thresholds_of(zone_id):
			if not t.seamless():
				continue
			var passable: bool = stages.has(t.other(zone_id)) and Atlas.is_threshold_open(t, flags)
			own.set_gate(t.id, not passable)


## Is a seamless threshold currently passable (both sides attached, flag allows)?
func threshold_open(threshold_id: StringName) -> bool:
	for zone_id: StringName in stages:
		var own: ZoneStage = stages[zone_id] as ZoneStage
		if own.has_gate(threshold_id):
			return not own.gate_closed(threshold_id)
	return false


# --- what the local player has seen (arrival inscriptions) ----------------------------------------------------------

func seen_zone(zone_id: StringName) -> bool:
	return (seen.zones as Dictionary).has(zone_id)


func mark_zone(zone_id: StringName) -> void:
	(seen.zones as Dictionary)[zone_id] = true


func seen_place(place_id: StringName) -> bool:
	return (seen.places as Dictionary).has(place_id)


func mark_place(place_id: StringName) -> void:
	(seen.places as Dictionary)[place_id] = true


# --- state (save, late joiners) -------------------------------------------------------------------------------------

## Host: the whole zone world's state for the save file. Attached zones are written live.
func export_state() -> Dictionary:
	var zones: Dictionary = {}
	for key: StringName in _saved:
		zones[String(key)] = (_saved[key] as Dictionary).duplicate(true)
	for zone_id: StringName in stages:
		var kept: Dictionary = (stages[zone_id] as ZoneStage).export_state()
		kept["day"] = TimeManager.day
		zones[String(zone_id)] = kept
	return {"version": 1, "zones": zones, "seen": {"zones": (seen.zones as Dictionary).keys(), "places": (seen.places as Dictionary).keys()}}


## Before any zone is loaded (after loading a save). Zones loaded later pick up their state when they are built.
func import_state(data: Dictionary) -> void:
	_saved.clear()
	seen = {"zones": {}, "places": {}}
	var seen_data: Dictionary = data.get("seen", {}) as Dictionary
	for key: String in ["zones", "places"]:
		for id: Variant in seen_data.get(key, []) as Array:
			(seen[key] as Dictionary)[StringName(String(id))] = true
	var zones: Dictionary = data.get("zones", {}) as Dictionary
	for key: Variant in zones:
		if zones[key] is Dictionary:
			_saved[StringName(String(key))] = (zones[key] as Dictionary).duplicate(true)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_zone(zone_id: String) -> void:
	if not _is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var zid: StringName = StringName(zone_id)
	if sender > 1:
		if not _peer_stages.has(sender):
			_peer_stages[sender] = {}
		(_peer_stages[sender] as Dictionary)[zid] = true
	var own: ZoneStage = stages.get(zid) as ZoneStage
	if own == null:
		return
	_rpc_zone_state.rpc_id(sender, zone_id, own.export_state())


@rpc("authority", "call_remote", "reliable")
func _rpc_zone_state(zone_id: String, data: Dictionary) -> void:
	var own: ZoneStage = stages.get(StringName(zone_id)) as ZoneStage
	if own == null:
		return
	own.apply_state(data)
