class_name ZoneCoop
extends Node
## Coop visibility filtering, transient map pings (`MapPingPillar`), and host-authoritative
## "ZU IHM" peer-join travel for the v2 zone world (`docs/v2_zonenwelt_atlas_konzept.md` 6.5, step 9).
## Created automatically by `ZoneDirector.setup()` as child `"Coop"` and registered in group `"zone_coop"`.

signal ping_received(peer_id: int, world_pos: Vector2, zone_id: StringName)
signal join_peer_resolved(ok: bool, target_peer: int, target_zone: StringName, arrival_pos: Vector2, waystone_id: StringName, reason: String)

const PING_DURATION: float = MapPingPillar.DURATION
const PING_RATE_LIMIT_SEC: float = 0.45
const VISIBILITY_TICK: float = 0.25
const WAYSTONE_ARRIVE_OFFSET: Vector2 = Vector2(0.0, 28.0)

var director: ZoneDirector = null

var _world: Node = null
var _tracked_syncs: Array[MultiplayerSynchronizer] = []
var _hooked_containers: Dictionary = {} ## int (instance_id) -> true
var _peer_pocket_sig: Dictionary = {} ## peer_id -> Vector3i(in_pocket, lane, index)
var _vis_tick: float = 0.0
var _active_pings: Array[Dictionary] = [] ## transient {peer_id, color_slot, world_pos, zone_id, age, duration}
var _last_ping_sec: Dictionary = {} ## peer_id -> float (server rate-limit clock)
var _pillars_by_peer: Dictionary = {} ## peer_id -> MapPingPillar


static func of(tree: SceneTree) -> ZoneCoop:
	if tree == null:
		return null
	return tree.get_first_node_in_group("zone_coop") as ZoneCoop


func setup(p_director: ZoneDirector) -> void:
	director = p_director


func _ready() -> void:
	add_to_group("zone_coop")
	if director == null:
		director = get_parent() as ZoneDirector
	if director != null and not director.zone_changed.is_connected(_on_player_zone_changed):
		director.zone_changed.connect(_on_player_zone_changed)
	if not multiplayer.peer_connected.is_connected(_on_peer_changed):
		multiplayer.peer_connected.connect(_on_peer_changed)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not NetworkManager.session_changed.is_connected(_on_session_changed):
		NetworkManager.session_changed.connect(_on_session_changed)
	_bind_world.call_deferred()


func _bind_world() -> void:
	if director == null:
		director = get_parent() as ZoneDirector
	if director == null:
		return
	_world = director.get_parent()
	if _world == null:
		return
	if not _world.child_entered_tree.is_connected(_on_world_child_entered):
		_world.child_entered_tree.connect(_on_world_child_entered)
	for root_name: String in ["Enemies", "EnemyProjectiles", "Drops", "Wildlife"]:
		var container: Node = _world.get_node_or_null(root_name)
		if container != null:
			_hook_container_tree(container)
	_scan_spawners(_world)
	refresh_visibility()


func _on_world_child_entered(child: Node) -> void:
	if child == null:
		return
	if child.name in ["Enemies", "EnemyProjectiles", "Drops", "Wildlife"]:
		_hook_container_tree(child)
	elif child is MultiplayerSpawner:
		_hook_spawner(child as MultiplayerSpawner)


func _scan_spawners(root: Node) -> void:
	if root == null:
		return
	for sp_node: Node in root.find_children("*", "MultiplayerSpawner", true, false):
		_hook_spawner(sp_node as MultiplayerSpawner)


func _hook_spawner(spawner: MultiplayerSpawner) -> void:
	if spawner == null or spawner.spawn_path.is_empty():
		return
	var target: Node = spawner.get_node_or_null(spawner.spawn_path)
	if target == null or target.name == "Players":
		return
	if director != null and target == director.players_root:
		return
	_hook_entity_container(target)


func _hook_container_tree(root: Node) -> void:
	if root == null:
		return
	if root.name != "Wildlife":
		_hook_entity_container(root)
		return
	# `Wildlife` contains `Animals` plus nested sub-populations (`Corvids/Birds`, `Woodland/Residents`, etc.)
	_scan_spawners(root)
	if not root.child_entered_tree.is_connected(_on_wildlife_branch_entered):
		root.child_entered_tree.connect(_on_wildlife_branch_entered)
	for sub: Node in root.get_children():
		_on_wildlife_branch_entered(sub)


func _on_wildlife_branch_entered(node: Node) -> void:
	if node == null:
		return
	if node is MultiplayerSpawner:
		_hook_spawner(node as MultiplayerSpawner)
		return
	for sp_node: Node in node.find_children("*", "MultiplayerSpawner", true, false):
		_hook_spawner(sp_node as MultiplayerSpawner)
	if _find_direct_synchronizer(node) != null:
		_hook_entity(node)


func _hook_entity_container(container: Node) -> void:
	if container == null:
		return
	var cid: int = container.get_instance_id()
	if _hooked_containers.has(cid):
		return
	_hooked_containers[cid] = true
	if not container.child_entered_tree.is_connected(_hook_entity):
		container.child_entered_tree.connect(_hook_entity)
	for existing: Node in container.get_children():
		_hook_entity(existing)


func _find_direct_synchronizer(entity: Node) -> MultiplayerSynchronizer:
	if entity == null:
		return null
	var direct: MultiplayerSynchronizer = entity.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if direct != null:
		return direct
	for child: Node in entity.get_children():
		if child is MultiplayerSynchronizer:
			return child as MultiplayerSynchronizer
	return null


func synchronizer_of(entity: Node) -> MultiplayerSynchronizer:
	return _find_direct_synchronizer(entity)


func _hook_entity(entity: Node) -> void:
	if not multiplayer.is_server():
		return
	var body: Node2D = entity as Node2D
	if body == null:
		return
	var sync: MultiplayerSynchronizer = _find_direct_synchronizer(body)
	if sync == null or sync.has_meta(&"_zone_coop_hooked"):
		return
	sync.set_meta(&"_zone_coop_hooked", true)
	sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
	sync.public_visibility = false
	sync.set_visibility_for(1, true)
	var weak_body: WeakRef = weakref(body)
	sync.add_visibility_filter(func(peer_id: int) -> bool:
		var ent: Node2D = weak_body.get_ref() as Node2D
		return _evaluate_entity_visibility(ent, peer_id)
	)
	_tracked_syncs.append(sync)
	_apply_sync_visibility(sync, body)
	if not sync.is_inside_tree():
		var weak_sync: WeakRef = weakref(sync)
		sync.tree_entered.connect(func() -> void:
			var s: MultiplayerSynchronizer = weak_sync.get_ref() as MultiplayerSynchronizer
			var b: Node2D = weak_body.get_ref() as Node2D
			if s != null and b != null:
				_apply_sync_visibility(s, b)
		, CONNECT_ONE_SHOT)


func _apply_sync_visibility(sync: MultiplayerSynchronizer, entity: Node2D) -> void:
	if not multiplayer.is_server() or sync == null or not is_instance_valid(sync) or entity == null or not is_instance_valid(entity):
		return
	sync.set_visibility_for(1, true)
	for peer: int in multiplayer.get_peers():
		var vis: bool = _evaluate_entity_visibility(entity, peer)
		sync.set_visibility_for(peer, vis)
	if sync.is_inside_tree():
		sync.update_visibility(0)


## Public visibility check for `entity` toward `peer_id` (host truth).
func is_entity_visible_to(entity: Node2D, peer_id: int) -> bool:
	return _evaluate_entity_visibility(entity, peer_id)


func _evaluate_entity_visibility(entity: Node2D, peer_id: int) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	if peer_id <= 1 or peer_id == multiplayer.get_unique_id():
		return true
	if director == null:
		return true
	var peer_body: Node2D = director.player_body(peer_id)
	if peer_body == null:
		return false
	var ppos: Vector2 = peer_body.global_position if peer_body.is_inside_tree() else peer_body.position
	var epos: Vector2 = entity.global_position if entity.is_inside_tree() else entity.position
	var peer_in_pocket: bool = PocketSpace.is_pocket(ppos)
	var entity_in_pocket: bool = PocketSpace.is_pocket(epos)
	if peer_in_pocket != entity_in_pocket:
		return false
	if peer_in_pocket:
		var pid: StringName = PocketSpace.pocket_id_at(ppos)
		var eid: StringName = PocketSpace.pocket_id_at(epos)
		if pid != &"" or eid != &"":
			if pid != &"" and pid == eid:
				return true
		var pslot: Vector2i = PocketSpace.locate(ppos)
		var eslot: Vector2i = PocketSpace.locate(epos)
		return pslot.x >= 0 and pslot == eslot
	var ezone: StringName = director.zone_for_world_pos(epos)
	if ezone == &"":
		return ppos.distance_to(epos) <= ZoneDirector.KEEP_TILES * Atlas.TILE_PX
	return director.is_zone_relevant_for_peer(peer_id, ezone, ZoneDirector.KEEP_TILES)


## Re-evaluates all tracked entity synchronizers immediately (called on zone/pocket transitions and every 0.25 s).
func refresh_visibility() -> void:
	if not multiplayer.is_server():
		return
	for i: int in range(_tracked_syncs.size() - 1, -1, -1):
		var sync: MultiplayerSynchronizer = _tracked_syncs[i]
		if sync == null or not is_instance_valid(sync):
			_tracked_syncs.remove_at(i)
			continue
		var root_node: Node2D = sync.get_node_or_null(sync.root_path) as Node2D if sync.is_inside_tree() else (sync.get_parent() as Node2D)
		if root_node == null or not is_instance_valid(root_node):
			_tracked_syncs.remove_at(i)
			continue
		_apply_sync_visibility(sync, root_node)


func _on_player_zone_changed(_peer_id: int, _zone_id: StringName) -> void:
	if multiplayer.is_server():
		refresh_visibility()


func _on_peer_changed(_peer_id: int) -> void:
	if multiplayer.is_server():
		refresh_visibility()


func _on_peer_disconnected(peer_id: int) -> void:
	_peer_pocket_sig.erase(peer_id)
	_last_ping_sec.erase(peer_id)
	if multiplayer.is_server():
		refresh_visibility()


func _on_session_changed() -> void:
	if multiplayer.is_server() and _world != null:
		for root_name: String in ["Enemies", "EnemyProjectiles", "Drops", "Wildlife"]:
			var container: Node = _world.get_node_or_null(root_name)
			if container != null:
				_hook_container_tree(container)
		_scan_spawners(_world)
		refresh_visibility()


func _process(delta: float) -> void:
	_step_active_pings(delta)
	if not multiplayer.is_server():
		return
	var pocket_changed: bool = _check_pocket_transitions()
	_vis_tick -= delta
	if pocket_changed or _vis_tick <= 0.0:
		_vis_tick = VISIBILITY_TICK
		refresh_visibility()


func _check_pocket_transitions() -> bool:
	if director == null or director.players_root == null:
		return false
	var changed: bool = false
	for child: Node in director.players_root.get_children():
		var body: Node2D = child as Node2D
		if body == null or not child.name.is_valid_int():
			continue
		var peer: int = child.name.to_int()
		var ppos: Vector2 = body.global_position
		var sig: Vector3i = Vector3i.ZERO
		if PocketSpace.is_pocket(ppos):
			var loc: Vector2i = PocketSpace.locate(ppos)
			sig = Vector3i(1, loc.x, loc.y)
		if _peer_pocket_sig.get(peer, Vector3i(-1, -1, -1)) != sig:
			_peer_pocket_sig[peer] = sig
			changed = true
	return changed


func _step_active_pings(delta: float) -> void:
	if _active_pings.is_empty():
		return
	for i: int in range(_active_pings.size() - 1, -1, -1):
		var entry: Dictionary = _active_pings[i]
		var age: float = float(entry.get("age", 0.0)) + delta
		if age >= float(entry.get("duration", PING_DURATION)):
			_active_pings.remove_at(i)
		else:
			entry["age"] = age


# --- Map Ping (Kartenruf, middle-click on Atlas) --------------------------------------------------------------------

func peer_color_slot(peer_id: int) -> int:
	return NetworkManager.player_slot_for(peer_id)


func peer_zone(peer_id: int) -> StringName:
	if director == null:
		return &""
	return director.effective_player_zone(peer_id)


func active_pings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _active_pings:
		out.append(entry.duplicate())
	return out


func request_ping(world_pos: Vector2) -> void:
	if not world_pos.is_finite():
		return
	if multiplayer.is_server():
		_host_handle_ping(multiplayer.get_unique_id(), world_pos)
	elif NetworkManager.rpc_ready(self):
		_rpc_request_ping.rpc_id(1, world_pos)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_ping(world_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_host_handle_ping(multiplayer.get_remote_sender_id(), world_pos)


func _host_handle_ping(sender_peer: int, world_pos: Vector2) -> void:
	if sender_peer <= 0 or not world_pos.is_finite():
		return
	var now_sec: float = float(Time.get_ticks_msec()) * 0.001
	var prev_sec: float = float(_last_ping_sec.get(sender_peer, -999.0))
	if now_sec - prev_sec < PING_RATE_LIMIT_SEC:
		return
	_last_ping_sec[sender_peer] = now_sec
	var zone_id: StringName = &""
	if director != null:
		zone_id = director.zone_for_world_pos(world_pos)
		if zone_id == &"":
			zone_id = director.effective_player_zone(sender_peer)
	var slot: int = peer_color_slot(sender_peer)
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_deliver_ping.rpc(sender_peer, slot, world_pos, String(zone_id))
	else:
		_rpc_deliver_ping(sender_peer, slot, world_pos, String(zone_id))


@rpc("authority", "call_local", "reliable")
func _rpc_deliver_ping(sender_peer: int, color_slot: int, world_pos: Vector2, zone_str: String) -> void:
	var zone_id: StringName = StringName(zone_str)
	for i: int in range(_active_pings.size() - 1, -1, -1):
		if int(_active_pings[i].get("peer_id", 0)) == sender_peer:
			_active_pings.remove_at(i)
	_active_pings.append({
		"peer_id": sender_peer,
		"color_slot": clampi(color_slot, 0, 3),
		"world_pos": world_pos,
		"zone_id": zone_id,
		"age": 0.0,
		"duration": PING_DURATION,
	})
	ping_received.emit(sender_peer, world_pos, zone_id)

	if director == null:
		return
	var local_peer: int = multiplayer.get_unique_id()
	var local_body: Node2D = director.player_body(local_peer)
	if local_body != null and PocketSpace.is_pocket(local_body.global_position) != PocketSpace.is_pocket(world_pos):
		return
	var local_zone: StringName = peer_zone(local_peer)
	if zone_id != &"" and local_zone == zone_id:
		_spawn_ping_pillar(sender_peer, color_slot, world_pos, zone_id)


func _spawn_ping_pillar(sender_peer: int, color_slot: int, world_pos: Vector2, zone_id: StringName) -> void:
	var prev: MapPingPillar = _pillars_by_peer.get(sender_peer) as MapPingPillar
	if prev != null and is_instance_valid(prev):
		prev.queue_free()
	var host_parent: Node = _world if (_world != null and is_instance_valid(_world)) else director
	if host_parent == null:
		return
	var pillar: MapPingPillar = MapPingPillar.new()
	pillar.name = "MapPingPillar_%d" % sender_peer
	pillar.setup(sender_peer, color_slot, world_pos, zone_id)
	host_parent.add_child(pillar)
	_pillars_by_peer[sender_peer] = pillar


# --- "ZU IHM" Peer Join Travel (`request_join_peer`) ----------------------------------------------------------------

func find_awake_waystone_in_zone(zone_id: StringName) -> Dictionary:
	if zone_id == &"" or director == null or director.atlas == null or not is_inside_tree():
		return {}
	var ws: Waystones = Waystones.of(get_tree())
	if ws == null:
		return {}
	for entry: Dictionary in ws.entries():
		if not bool(entry.get("awake", false)):
			continue
		var tile_v: Variant = entry.get("tile")
		if tile_v is Array and (tile_v as Array).size() >= 2:
			var t_arr: Array = tile_v as Array
			var t_vec: Vector2 = Vector2(float(t_arr[0]), float(t_arr[1]))
			if director.atlas.zone_at_tile(director.continent_id, t_vec) == zone_id:
				var ws_id: StringName = StringName(String(entry.get("id", "")))
				var statue: WaystoneStatue = ws.statue_node(String(ws_id))
				var base_pos: Vector2 = statue.global_position if statue != null else Atlas.px_of(t_vec)
				return {"id": ws_id, "pos": base_pos, "arrive_pos": base_pos + WAYSTONE_ARRIVE_OFFSET}
	var z: Atlas.Zone = director.atlas.zone(zone_id)
	if z != null:
		for lm: Atlas.Landmark in z.landmarks:
			if lm.kind == &"waystone" and ws.is_awake(String(lm.id)):
				var statue: WaystoneStatue = ws.statue_node(String(lm.id))
				var base_pos: Vector2 = statue.global_position if statue != null else Atlas.px_of(lm.pos)
				return {"id": lm.id, "pos": base_pos, "arrive_pos": base_pos + WAYSTONE_ARRIVE_OFFSET}
	return {}


## Local query for Atlas UI: whether `target_peer`'s zone currently has an awakened waystone to teleport to.
func can_join_peer(target_peer: int) -> Dictionary:
	var t_zone: StringName = peer_zone(target_peer)
	if t_zone == &"" or target_peer <= 0 or target_peer == multiplayer.get_unique_id():
		return {"ok": false, "zone_id": t_zone, "waystone_id": &"", "arrival_pos": Vector2.INF}
	var ws_info: Dictionary = find_awake_waystone_in_zone(t_zone)
	if ws_info.is_empty():
		return {"ok": false, "zone_id": t_zone, "waystone_id": &"", "arrival_pos": Vector2.INF}
	return {
		"ok": true,
		"zone_id": t_zone,
		"waystone_id": ws_info["id"] as StringName,
		"arrival_pos": ws_info["arrive_pos"] as Vector2,
	}


func request_join_peer(target_peer: int, allow_direct: bool = false) -> void:
	if target_peer <= 0 or target_peer == multiplayer.get_unique_id():
		join_peer_resolved.emit(false, target_peer, &"", Vector2.INF, &"", "UNGÜLTIGES ZIEL")
		return
	if multiplayer.is_server():
		_host_handle_join_peer(multiplayer.get_unique_id(), target_peer, allow_direct)
	elif NetworkManager.rpc_ready(self):
		_rpc_request_join_peer.rpc_id(1, target_peer, allow_direct)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_join_peer(target_peer: int, allow_direct: bool) -> void:
	if not multiplayer.is_server():
		return
	_host_handle_join_peer(multiplayer.get_remote_sender_id(), target_peer, allow_direct)


func _host_handle_join_peer(requester_peer: int, target_peer: int, allow_direct: bool) -> void:
	if director == null or requester_peer <= 0 or requester_peer == target_peer:
		_deliver_join_result(requester_peer, false, target_peer, &"", Vector2.INF, &"", "UNGÜLTIGES ZIEL")
		return
	var req_body: Node2D = director.player_body(requester_peer)
	var target_body: Node2D = director.player_body(target_peer)
	if req_body == null or target_body == null:
		_deliver_join_result(requester_peer, false, target_peer, &"", Vector2.INF, &"", "SPIELER NICHT GEFUNDEN")
		return
	var target_zone: StringName = director.effective_player_zone(target_peer)
	if target_zone == &"":
		_deliver_join_result(requester_peer, false, target_peer, &"", Vector2.INF, &"", "KEINE ZONE")
		return
	var ws_info: Dictionary = find_awake_waystone_in_zone(target_zone)
	var arrival_pos: Vector2 = Vector2.INF
	var waystone_id: StringName = &""
	if not ws_info.is_empty():
		arrival_pos = ws_info["arrive_pos"] as Vector2
		waystone_id = ws_info["id"] as StringName
	elif allow_direct:
		if PocketSpace.is_pocket(target_body.global_position):
			var outer_p: Vector2 = Interiors.outer(get_tree(), target_body.global_position)
			if not PocketSpace.is_pocket(outer_p) and outer_p.is_finite():
				arrival_pos = outer_p + Vector2(0.0, 20.0)
			else:
				var z_obj: Atlas.Zone = director.atlas.zone(target_zone)
				arrival_pos = Atlas.px_of(z_obj.center()) if z_obj != null else Vector2.INF
		else:
			arrival_pos = target_body.global_position + Vector2(20.0, 0.0)
	if not arrival_pos.is_finite():
		_deliver_join_result(requester_peer, false, target_peer, target_zone, Vector2.INF, &"", "KEIN ERWECKTER WEGSTEIN")
		return

	if not director.is_loaded(target_zone):
		director.load_now(target_zone)
	director.set_player_zone(requester_peer, target_zone)
	refresh_visibility()
	_deliver_join_result(requester_peer, true, target_peer, target_zone, arrival_pos, waystone_id, "")


func _deliver_join_result(requester_peer: int, ok: bool, target_peer: int, target_zone: StringName, arrival_pos: Vector2, waystone_id: StringName, reason: String) -> void:
	if requester_peer == multiplayer.get_unique_id():
		_apply_join_result(ok, target_peer, String(target_zone), arrival_pos, String(waystone_id), reason)
	elif NetworkManager.rpc_ready(self):
		_rpc_join_result.rpc_id(requester_peer, ok, target_peer, String(target_zone), arrival_pos, String(waystone_id), reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_result(ok: bool, target_peer: int, target_zone_str: String, arrival_pos: Vector2, waystone_str: String, reason: String) -> void:
	_apply_join_result(ok, target_peer, target_zone_str, arrival_pos, waystone_str, reason)


func _apply_join_result(ok: bool, target_peer: int, target_zone_str: String, arrival_pos: Vector2, waystone_str: String, reason: String) -> void:
	var target_zone: StringName = StringName(target_zone_str)
	var waystone_id: StringName = StringName(waystone_str)
	if ok and director != null and arrival_pos.is_finite():
		if target_zone != &"" and not director.is_loaded(target_zone):
			director.load_now(target_zone)
		var local_player: Player = director.player_body(multiplayer.get_unique_id()) as Player
		if local_player != null:
			local_player.request_teleport(arrival_pos)
	join_peer_resolved.emit(ok, target_peer, target_zone, arrival_pos, waystone_id, reason)
