class_name DungeonManager
extends Node2D
## Host-authoritative Dungeon orchestrator inside `ZoneWorld` (docs/dungeon_konzept.md Section 6).
## Mounts each dungeon's standalone `.tscn` scene into `PocketSpace.Lane.DUNGEON` (4 slots x 8192 px),
## manages 1-4 player Coop Ready-Checks, tracks the 3 shared Group Veil Sparks, records combat stats
## (damage, counters, staggers, hits taken), awards Resonanz-Reliquiar / First-Clear / Echo Shards
## on victory, and unloads the scene cleanly once the last participant leaves.

signal gate_window_requested(dungeon_id: String, at_gate: bool)
signal ready_check_opened(payload: Dictionary)
signal ready_check_updated(payload: Dictionary)
signal ready_check_closed(reason: String)
signal hud_state_changed(state: Dictionary)
signal run_victory_received(summary: Dictionary)
signal run_wiped_received(payload: Dictionary)
signal local_dungeon_changed(active: bool, dungeon_id: String)

const WIPE_SHADER: Shader = preload("res://assets/shaders/dungeon_wipe.gdshader")
const WIPE_TIME: float = 0.42
const RESPAWN_DELAY_SEC: float = 3.0

## Host-only active instances: slot_index (0..3) -> Dictionary
## {dungeon_id, scene: DungeonScene, seed, peers: Array[int], return_map: Dictionary,
##  use_res: Dictionary, sparks: int, elapsed: float, stats: Dictionary, objective: String,
##  progress: float, parent_zone: StringName, entrance_pos: Vector2, completed: bool, wiped: bool}
var _instances: Dictionary = {}
## Local mounted scenes (both host & participating clients): slot_index -> DungeonScene
var _mounted: Dictionary = {}
## Local cached metadata per slot (for ambient, bounds, world_position on clients)
var _slot_meta: Dictionary = {}

## Host-only active Ready-Check lobby
var _lobby: Dictionary = {}
var _next_lobby_id: int = 1

## Local UI transition & state
var _wipe_layer: CanvasLayer = null
var _wipe_mat: ShaderMaterial = null
var _local_hud_state: Dictionary = {}
var _was_local_inside: bool = false
var _local_dungeon_id: String = ""
var respawn_delay_sec: float = RESPAWN_DELAY_SEC
var instant_transitions: bool = false


func is_player_in_dungeon(peer_id: int) -> bool:
	return _slot_of_peer(peer_id) >= 0


func active_scene_for_peer(peer_id: int) -> DungeonScene:
	var slot: int = _slot_of_peer(peer_id)
	if slot < 0 or not _instances.has(slot):
		return null
	return (_instances[slot] as Dictionary).get("scene") as DungeonScene


static func of(tree: SceneTree) -> DungeonManager:
	if tree == null:
		return null
	return tree.get_first_node_in_group("dungeons") as DungeonManager


static func slot_at(pos: Vector2) -> int:
	var hit: Vector2i = PocketSpace.locate(pos)
	if hit.x == PocketSpace.Lane.DUNGEON and hit.y >= 0 and hit.y < PocketSpace.capacity(PocketSpace.Lane.DUNGEON):
		return hit.y
	return -1


static func in_dungeon(pos: Vector2) -> bool:
	return slot_at(pos) >= 0


func _ready() -> void:
	name = "Dungeons"
	add_to_group("dungeons")
	y_sort_enabled = true
	Terrain.patches.append(self)
	_build_wipe_layer()
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _exit_tree() -> void:
	Terrain.patches.erase(self)
	for slot_v: Variant in _mounted.keys():
		var s: int = int(slot_v)
		PocketSpace.unregister_pocket(StringName("dungeon_%d" % s))


func _build_wipe_layer() -> void:
	_wipe_layer = CanvasLayer.new()
	_wipe_layer.name = "DungeonWipeLayer"
	_wipe_layer.layer = 82
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe_mat = ShaderMaterial.new()
	_wipe_mat.shader = WIPE_SHADER
	_wipe_mat.set_shader_parameter("cover", 0.0)
	rect.material = _wipe_mat
	_wipe_layer.add_child(rect)
	_wipe_layer.visible = false
	add_child(_wipe_layer)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		_tick_lobby(delta)
		_tick_instances(delta)
	_check_local_presence()


func _check_local_presence() -> void:
	var lp: Player = SaveGame._local_player(get_tree())
	var inside: bool = lp != null and in_dungeon(lp.global_position)
	var cur_id: String = ""
	if inside:
		var s: int = slot_at(lp.global_position)
		var meta: Dictionary = _slot_meta.get(s, {}) as Dictionary
		cur_id = String(meta.get("dungeon_id", ""))
	if inside != _was_local_inside or cur_id != _local_dungeon_id:
		_was_local_inside = inside
		_local_dungeon_id = cur_id
		local_dungeon_changed.emit(inside, cur_id)
		if not inside:
			_local_hud_state = {}
			hud_state_changed.emit({})


# ==============================================================================
# World Queries (DayNight, Interiors.outer, Terrain.patches, Camera, Navigation)
# ==============================================================================

func ambient_color() -> Color:
	var lp: Player = SaveGame._local_player(get_tree())
	if lp == null:
		return Color(0, 0, 0, 0)
	var s: int = slot_at(lp.global_position)
	if s < 0:
		return Color(0, 0, 0, 0)
	var sc: DungeonScene = _mounted.get(s) as DungeonScene
	if sc != null and is_instance_valid(sc):
		return sc.ambient
	return Color(0.32, 0.44, 0.56, 1.0)


func world_position(pos: Vector2) -> Vector2:
	var s: int = slot_at(pos)
	if s < 0:
		return pos
	var meta: Dictionary = _slot_meta.get(s, {}) as Dictionary
	var ent: Variant = meta.get("entrance_pos", Vector2.ZERO)
	if ent is Vector2 and (ent as Vector2) != Vector2.ZERO:
		return ent as Vector2
	return Vector2(12000.0, 22000.0)


func camera_rect_at(pos: Vector2) -> Rect2:
	var s: int = slot_at(pos)
	if s < 0:
		return Rect2()
	var sc: DungeonScene = _mounted.get(s) as DungeonScene
	if sc != null and is_instance_valid(sc):
		return sc.world_bounds()
	return Rect2()


func surface_at(pos: Vector2) -> String:
	var s: int = slot_at(pos)
	if s < 0:
		return ""
	var sc: DungeonScene = _mounted.get(s) as DungeonScene
	if sc != null and is_instance_valid(sc):
		return sc.surface_at_local(pos - sc.global_position)
	return "stone"


func navigation_floor(pos: Vector2) -> bool:
	var s: int = slot_at(pos)
	if s < 0:
		return false
	var sc: DungeonScene = _mounted.get(s) as DungeonScene
	if sc != null and is_instance_valid(sc):
		return sc.navigation_floor_local(pos - sc.global_position)
	return false


func local_hud_state() -> Dictionary:
	return _local_hud_state


func open_gate_window(dungeon_id: String, _gate_pos: Vector2 = Vector2.ZERO) -> void:
	gate_window_requested.emit(dungeon_id, true)


func open_global_window() -> void:
	gate_window_requested.emit("", false)


# ==============================================================================
# Entry & Coop Ready-Check (Host-Authoritative)
# ==============================================================================

func request_enter_solo(dungeon_id: String, use_resonance: bool) -> void:
	if multiplayer.is_server():
		_host_enter_solo(multiplayer.get_unique_id(), dungeon_id, use_resonance)
	elif NetworkManager.rpc_ready(self):
		_rpc_request_enter_solo.rpc_id(1, dungeon_id, use_resonance)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_enter_solo(dungeon_id: String, use_resonance: bool) -> void:
	if multiplayer.is_server():
		_host_enter_solo(multiplayer.get_remote_sender_id(), dungeon_id, use_resonance)


func _host_enter_solo(peer_id: int, dungeon_id: String, use_resonance: bool) -> bool:
	var def: Dictionary = DungeonRules.by_id(dungeon_id)
	var player: Player = _player_by_peer(peer_id)
	if player == null:
		return false
	var check: Dictionary = DungeonRules.can_enter(player.progress.level, def)
	if not bool(check.get("ok", false)):
		return false
	var peers: Array[int] = [peer_id]
	var res_map: Dictionary = {peer_id: use_resonance}
	return _host_launch_instance(dungeon_id, peers, res_map) >= 0


## Starts a Lost-Ark Coop Ready-Check pulling eligible peers across all ALTMARK zones.
func request_start_ready_check(dungeon_id: String, use_resonance: bool) -> void:
	if multiplayer.is_server():
		_host_start_ready_check(multiplayer.get_unique_id(), dungeon_id, use_resonance)
	elif NetworkManager.rpc_ready(self):
		_rpc_start_ready_check.rpc_id(1, dungeon_id, use_resonance)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_start_ready_check(dungeon_id: String, use_resonance: bool) -> void:
	if multiplayer.is_server():
		_host_start_ready_check(multiplayer.get_remote_sender_id(), dungeon_id, use_resonance)


func _host_start_ready_check(initiator_peer: int, dungeon_id: String, use_resonance: bool) -> void:
	if not _lobby.is_empty():
		return
	var def: Dictionary = DungeonRules.by_id(dungeon_id)
	var init_p: Player = _player_by_peer(initiator_peer)
	if init_p == null or not bool(DungeonRules.can_enter(init_p.progress.level, def).get("ok", false)):
		return
	var eligible: Array[int] = []
	var blocked: Array[Dictionary] = []
	var names: Dictionary = {}
	var min_lv: int = int(def.get("min_level", 1))
	for p: Player in Player.all:
		var pid: int = p.get_multiplayer_authority()
		if in_dungeon(p.global_position):
			continue
		var pname: String = NetworkManager.player_name_for(pid)
		names[pid] = pname
		if p.progress.level >= min_lv:
			eligible.append(pid)
		else:
			blocked.append({"peer_id": pid, "name": pname, "level": p.progress.level, "need": min_lv})
	if eligible.size() <= 1:
		_host_enter_solo(initiator_peer, dungeon_id, use_resonance)
		return
	var lid: int = _next_lobby_id
	_next_lobby_id += 1
	var timeout: float = float(ResonanceRules.config().get("ready_check_seconds", 20.0))
	_lobby = {
		"id": lid,
		"dungeon_id": dungeon_id,
		"initiator": initiator_peer,
		"eligible": eligible,
		"blocked": blocked,
		"names": names,
		"responses": {initiator_peer: true},
		"use_res": {initiator_peer: use_resonance},
		"time_left": timeout,
		"duration": timeout,
	}
	var payload: Dictionary = _lobby_payload()
	for pid: int in eligible:
		if pid == multiplayer.get_unique_id():
			_rpc_ready_check_open(payload)
		elif NetworkManager.rpc_ready(self):
			_rpc_ready_check_open.rpc_id(pid, payload)


func respond_ready_check(lobby_id: int, accept: bool, use_resonance: bool) -> void:
	if multiplayer.is_server():
		_host_respond_ready_check(multiplayer.get_unique_id(), lobby_id, accept, use_resonance)
	elif NetworkManager.rpc_ready(self):
		_rpc_respond_ready_check.rpc_id(1, lobby_id, accept, use_resonance)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_respond_ready_check(lobby_id: int, accept: bool, use_resonance: bool) -> void:
	if multiplayer.is_server():
		_host_respond_ready_check(multiplayer.get_remote_sender_id(), lobby_id, accept, use_resonance)


func _host_respond_ready_check(peer_id: int, lobby_id: int, accept: bool, use_resonance: bool) -> void:
	if _lobby.is_empty() or int(_lobby.get("id", 0)) != lobby_id:
		return
	var eligible: Array = _lobby.get("eligible", []) as Array
	if not eligible.has(peer_id):
		return
	(_lobby["responses"] as Dictionary)[peer_id] = accept
	(_lobby["use_res"] as Dictionary)[peer_id] = use_resonance
	var payload: Dictionary = _lobby_payload()
	for pid: int in eligible:
		if pid == multiplayer.get_unique_id():
			_rpc_ready_check_update(payload)
		elif NetworkManager.rpc_ready(self):
			_rpc_ready_check_update.rpc_id(pid, payload)
	if not accept:
		_host_close_lobby("ABGEBROCHEN VON %s" % String((_lobby["names"] as Dictionary).get(peer_id, "SPIELER")))
		return
	var responses: Dictionary = _lobby["responses"] as Dictionary
	var all_ready: bool = true
	for pid: int in eligible:
		if not bool(responses.get(pid, false)):
			all_ready = false
			break
	if all_ready:
		_host_finalize_lobby()


func _tick_lobby(delta: float) -> void:
	if _lobby.is_empty():
		return
	_lobby["time_left"] = float(_lobby["time_left"]) - delta
	if float(_lobby["time_left"]) <= 0.0:
		_host_finalize_lobby()


func _host_finalize_lobby() -> void:
	var eligible: Array = _lobby.get("eligible", []) as Array
	var responses: Dictionary = _lobby.get("responses", {}) as Dictionary
	var use_res: Dictionary = _lobby.get("use_res", {}) as Dictionary
	var dungeon_id: String = String(_lobby.get("dungeon_id", ""))
	var accepted: Array[int] = []
	for pid_v: Variant in eligible:
		var pid: int = int(pid_v)
		if bool(responses.get(pid, false)):
			accepted.append(pid)
	_host_close_lobby("START")
	if not accepted.is_empty():
		_host_launch_instance(dungeon_id, accepted, use_res)


func _host_close_lobby(reason: String) -> void:
	var eligible: Array = _lobby.get("eligible", []) as Array
	_lobby.clear()
	for pid_v: Variant in eligible:
		var pid: int = int(pid_v)
		if pid == multiplayer.get_unique_id():
			_rpc_ready_check_closed(reason)
		elif NetworkManager.rpc_ready(self):
			_rpc_ready_check_closed.rpc_id(pid, reason)


func _lobby_payload() -> Dictionary:
	return {
		"id": int(_lobby.get("id", 0)),
		"dungeon_id": String(_lobby.get("dungeon_id", "")),
		"initiator": int(_lobby.get("initiator", 1)),
		"eligible": (_lobby.get("eligible", []) as Array).duplicate(),
		"blocked": (_lobby.get("blocked", []) as Array).duplicate(true),
		"names": (_lobby.get("names", {}) as Dictionary).duplicate(true),
		"responses": (_lobby.get("responses", {}) as Dictionary).duplicate(true),
		"time_left": float(_lobby.get("time_left", 0.0)),
		"duration": float(_lobby.get("duration", 20.0)),
	}


@rpc("authority", "call_local", "reliable")
func _rpc_ready_check_open(payload: Dictionary) -> void:
	ready_check_opened.emit(payload)


@rpc("authority", "call_local", "reliable")
func _rpc_ready_check_update(payload: Dictionary) -> void:
	ready_check_updated.emit(payload)


@rpc("authority", "call_local", "reliable")
func _rpc_ready_check_closed(reason: String) -> void:
	ready_check_closed.emit(reason)


# ==============================================================================
# Instance Mounting, Launching & Unloading
# ==============================================================================

func _find_free_slot() -> int:
	var cap: int = PocketSpace.capacity(PocketSpace.Lane.DUNGEON)
	for i: int in cap:
		if not _instances.has(i):
			return i
	return -1


func _entrance_pos_for(dungeon_id: String, fallback: Vector2) -> Vector2:
	for node: Node in get_tree().get_nodes_in_group("dungeon_entrances"):
		var ent: DungeonEntrance = node as DungeonEntrance
		if ent != null and ent.dungeon_id == dungeon_id:
			return ent.global_position + Vector2(0.0, 26.0)
	var def: Dictionary = DungeonRules.by_id(dungeon_id)
	var z_id: StringName = StringName(String(def.get("zone", "")))
	var tile_arr: Array = def.get("entrance_tile", []) as Array
	if z_id != &"" and tile_arr.size() >= 2:
		var atlas: Atlas = Atlas.shared()
		var z: Atlas.Zone = atlas.zone(z_id)
		if z != null:
			return Atlas.px_of(Vector2(z.origin) + Vector2(float(tile_arr[0]), float(tile_arr[1]))) + Vector2(0.0, 26.0)
	return fallback


func _host_launch_instance(dungeon_id: String, peers: Array[int], use_res: Dictionary) -> int:
	var def: Dictionary = DungeonRules.by_id(dungeon_id)
	var scene_path: String = String(def.get("scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("DungeonManager: missing scene '%s' for dungeon '%s'" % [scene_path, dungeon_id])
		return -1
	var slot: int = _find_free_slot()
	if slot < 0:
		push_error("DungeonManager: all %d dungeon slots busy" % PocketSpace.capacity(PocketSpace.Lane.DUNGEON))
		return -1
	var run_seed: int = int(Time.get_ticks_usec() ^ (slot * 7919) ^ hash(dungeon_id))
	var parent_zone: StringName = StringName(String(def.get("zone", "suedkap")))
	var first_p: Player = _player_by_peer(peers[0])
	var entrance_pos: Vector2 = _entrance_pos_for(dungeon_id, first_p.global_position if first_p != null else Vector2.ZERO)

	var return_map: Dictionary = {}
	var stats: Dictionary = {}
	for pid: int in peers:
		var p: Player = _player_by_peer(pid)
		var ret_pos: Vector2 = p.global_position if p != null else entrance_pos
		if in_dungeon(ret_pos):
			ret_pos = entrance_pos
		return_map[pid] = ret_pos
		stats[pid] = {
			"peer_id": pid,
			"name": NetworkManager.player_name_for(pid),
			"damage": 0.0,
			"counters": 0,
			"staggers": 0,
			"hits_taken": 0,
		}

	var packed_peers: PackedInt32Array = PackedInt32Array(peers)
	## Mount locally on host first
	var inst: DungeonScene = _mount_local_scene(slot, dungeon_id, scene_path, run_seed, packed_peers, entrance_pos, parent_zone)
	if inst == null:
		return -1

	_instances[slot] = {
		"dungeon_id": dungeon_id,
		"scene": inst,
		"seed": run_seed,
		"peers": peers.duplicate(),
		"return_map": return_map,
		"use_res": use_res.duplicate(),
		"sparks": ResonanceRules.group_sparks(),
		"max_sparks": ResonanceRules.group_sparks(),
		"elapsed": 0.0,
		"stats": stats,
		"objective": "",
		"progress": -1.0,
		"parent_zone": parent_zone,
		"entrance_pos": entrance_pos,
		"completed": false,
		"wiped": false,
		"hud_clock": 0.0,
	}

	## Mount on participating remote peers & teleport each participant in
	for i: int in peers.size():
		var pid: int = peers[i]
		var spawn_world: Vector2 = inst.start_spawn_world(i)
		if pid != multiplayer.get_unique_id() and NetworkManager.rpc_ready(self):
			_rpc_mount_and_enter.rpc_id(pid, slot, dungeon_id, scene_path, run_seed, packed_peers, entrance_pos, String(parent_zone), spawn_world)
		else:
			_enter_local_player(spawn_world)

	inst.start_run()
	_broadcast_hud_state(slot)
	return slot


func _mount_local_scene(slot: int, dungeon_id: String, scene_path: String, run_seed: int, packed_peers: PackedInt32Array, entrance_pos: Vector2, parent_zone: StringName) -> DungeonScene:
	if _mounted.has(slot):
		_unmount_local_scene(slot)
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var sc: DungeonScene = packed.instantiate() as DungeonScene
	if sc == null:
		return null
	var origin: Vector2 = PocketSpace.slot_origin(PocketSpace.Lane.DUNGEON, slot)
	sc.position = origin
	sc.dungeon_id = dungeon_id
	sc.setup_instance(self, slot, run_seed, packed_peers)
	add_child(sc)
	_mounted[slot] = sc
	_slot_meta[slot] = {
		"dungeon_id": dungeon_id,
		"entrance_pos": entrance_pos,
		"parent_zone": parent_zone,
	}
	PocketSpace.register_pocket(StringName("dungeon_%d" % slot), PocketSpace.slot_rect(PocketSpace.Lane.DUNGEON, slot), parent_zone)
	return sc


func _unmount_local_scene(slot: int) -> void:
	var sc: DungeonScene = _mounted.get(slot) as DungeonScene
	_mounted.erase(slot)
	_slot_meta.erase(slot)
	PocketSpace.unregister_pocket(StringName("dungeon_%d" % slot))
	if sc != null and is_instance_valid(sc):
		sc.cleanup_instance()
		sc.queue_free()


@rpc("authority", "call_remote", "reliable")
func _rpc_mount_and_enter(slot: int, dungeon_id: String, scene_path: String, run_seed: int, packed_peers: PackedInt32Array, entrance_pos: Vector2, parent_zone_str: String, spawn_world: Vector2) -> void:
	_mount_local_scene(slot, dungeon_id, scene_path, run_seed, packed_peers, entrance_pos, StringName(parent_zone_str))
	_enter_local_player(spawn_world)


func _enter_local_player(target_world: Vector2) -> void:
	var lp: Player = SaveGame._local_player(get_tree())
	if lp == null:
		return
	_play_wipe_teleport(lp, target_world)


func _play_wipe_teleport(player: Player, target_world: Vector2) -> void:
	if DisplayServer.get_name() == "headless" or instant_transitions:
		player.request_teleport(target_world)
		var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
		if interiors != null:
			interiors.apply_view(player)
		return
	if _wipe_layer != null and _wipe_mat != null:
		_wipe_layer.visible = true
		var tw: Tween = create_tween()
		tw.tween_method(func(v: float) -> void: _wipe_mat.set_shader_parameter("cover", v), 0.0, 1.0, WIPE_TIME * 0.5)
		await tw.finished
	if is_instance_valid(player):
		player.request_teleport(target_world)
		var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
		if interiors != null:
			interiors.apply_view(player)
	if _wipe_layer != null and _wipe_mat != null:
		var tw2: Tween = create_tween()
		tw2.tween_method(func(v: float) -> void: _wipe_mat.set_shader_parameter("cover", v), 1.0, 0.0, WIPE_TIME * 0.65)
		await tw2.finished
		_wipe_layer.visible = false


# ==============================================================================
# Live Combat Stats, Sparks, Death, Wipe & Victory (Host-Authoritative)
# ==============================================================================

func _tick_instances(delta: float) -> void:
	for slot_v: Variant in _instances.keys():
		var slot: int = int(slot_v)
		var inst: Dictionary = _instances[slot] as Dictionary
		if not bool(inst.get("completed", false)) and not bool(inst.get("wiped", false)):
			inst["elapsed"] = float(inst["elapsed"]) + delta
			inst["hud_clock"] = float(inst["hud_clock"]) + delta
			if float(inst["hud_clock"]) >= 0.5:
				inst["hud_clock"] = 0.0
				_broadcast_hud_state(slot)


func host_update_objective(slot: int, text: String, progress: float) -> void:
	if not multiplayer.is_server() or not _instances.has(slot):
		return
	var inst: Dictionary = _instances[slot] as Dictionary
	inst["objective"] = text
	inst["progress"] = progress
	_broadcast_hud_state(slot)


func _broadcast_hud_state(slot: int) -> void:
	if not _instances.has(slot):
		return
	var inst: Dictionary = _instances[slot] as Dictionary
	var def: Dictionary = DungeonRules.by_id(String(inst.get("dungeon_id", "")))
	var payload: Dictionary = {
		"slot": slot,
		"dungeon_id": String(inst.get("dungeon_id", "")),
		"name": String(def.get("name", "")),
		"archetype": String(def.get("archetype", "expedition")),
		"sparks": int(inst.get("sparks", 0)),
		"max_sparks": int(inst.get("max_sparks", 3)),
		"elapsed": float(inst.get("elapsed", 0.0)),
		"objective": String(inst.get("objective", "")),
		"progress": float(inst.get("progress", -1.0)),
		"completed": bool(inst.get("completed", false)),
	}
	for pid_v: Variant in inst.get("peers", []) as Array:
		var pid: int = int(pid_v)
		if pid == multiplayer.get_unique_id():
			_rpc_hud_state(payload)
		elif NetworkManager.rpc_ready(self):
			_rpc_hud_state.rpc_id(pid, payload)


@rpc("authority", "call_local", "reliable")
func _rpc_hud_state(payload: Dictionary) -> void:
	_local_hud_state = payload
	hud_state_changed.emit(payload)


func _slot_of_peer(peer_id: int) -> int:
	for slot_v: Variant in _instances:
		var s: int = int(slot_v)
		var peers: Array = (_instances[s] as Dictionary).get("peers", []) as Array
		if peers.has(peer_id):
			return s
	return -1


## Called via group `"dungeons"` by `HealthComponent.take_damage` (host-only).
func note_damage_event(target: Node, amount: float, source_peer: int) -> void:
	if not multiplayer.is_server() or target == null or amount <= 0.0:
		return
	if target is Player:
		var p: Player = target as Player
		var pid: int = p.get_multiplayer_authority()
		var s: int = _slot_of_peer(pid)
		if s >= 0:
			var st_map: Dictionary = (_instances[s] as Dictionary)["stats"] as Dictionary
			if st_map.has(pid):
				(st_map[pid] as Dictionary)["hits_taken"] = int((st_map[pid] as Dictionary)["hits_taken"]) + 1
	elif source_peer > 0:
		var s: int = _slot_of_peer(source_peer)
		if s >= 0:
			var st_map: Dictionary = (_instances[s] as Dictionary)["stats"] as Dictionary
			if st_map.has(source_peer):
				(st_map[source_peer] as Dictionary)["damage"] = float((st_map[source_peer] as Dictionary)["damage"]) + amount


func note_player_counter(source_peer: int) -> void:
	if not multiplayer.is_server() or source_peer <= 0:
		return
	var s: int = _slot_of_peer(source_peer)
	if s >= 0:
		var st_map: Dictionary = (_instances[s] as Dictionary)["stats"] as Dictionary
		if st_map.has(source_peer):
			(st_map[source_peer] as Dictionary)["counters"] = int((st_map[source_peer] as Dictionary)["counters"]) + 1


func note_player_stagger(source_peer: int) -> void:
	if not multiplayer.is_server() or source_peer <= 0:
		return
	var s: int = _slot_of_peer(source_peer)
	if s >= 0:
		var st_map: Dictionary = (_instances[s] as Dictionary)["stats"] as Dictionary
		if st_map.has(source_peer):
			(st_map[source_peer] as Dictionary)["staggers"] = int((st_map[source_peer] as Dictionary)["staggers"]) + 1


## Host-only: handles a player dying inside a dungeon using the 3 shared Group Veil Sparks.
func host_handle_player_death(player: Player) -> bool:
	if not multiplayer.is_server() or player == null:
		return false
	var pid: int = player.get_multiplayer_authority()
	var slot: int = _slot_of_peer(pid)
	if slot < 0:
		return false
	var inst: Dictionary = _instances[slot] as Dictionary
	var sparks: int = int(inst.get("sparks", 0))
	if sparks > 0:
		inst["sparks"] = sparks - 1
		_broadcast_hud_state(slot)
		_respawn_in_dungeon_after_delay(slot, player)
		return true
	## 0 sparks left: check if all participants in this dungeon are dead -> WIPE
	var any_alive: bool = false
	for other_v: Variant in inst.get("peers", []) as Array:
		var op: Player = _player_by_peer(int(other_v))
		if op != null and op.health.current > 0.0:
			any_alive = true
			break
	if not any_alive:
		inst["wiped"] = true
		var wipe_payload: Dictionary = {
			"slot": slot,
			"dungeon_id": String(inst.get("dungeon_id", "")),
			"elapsed": float(inst.get("elapsed", 0.0)),
		}
		for peer_v: Variant in inst.get("peers", []) as Array:
			var p_id: int = int(peer_v)
			if p_id == multiplayer.get_unique_id():
				_rpc_run_wiped(wipe_payload)
			elif NetworkManager.rpc_ready(self):
				_rpc_run_wiped.rpc_id(p_id, wipe_payload)
	return true


func _respawn_in_dungeon_after_delay(slot: int, player: Player) -> void:
	if respawn_delay_sec > 0.0:
		await get_tree().create_timer(respawn_delay_sec).timeout
	if not is_inside_tree() or not is_instance_valid(player) or not _instances.has(slot):
		return
	var inst: Dictionary = _instances[slot] as Dictionary
	if bool(inst.get("wiped", false)):
		return
	var sc: DungeonScene = inst.get("scene") as DungeonScene
	if sc == null or not is_instance_valid(sc):
		return
	var cp: Vector2 = sc.checkpoint_world()
	player.health.heal_full()
	player.health.grant_grace(1.5)
	var pid: int = player.get_multiplayer_authority()
	if pid == multiplayer.get_unique_id():
		player.request_teleport(cp)
	elif NetworkManager.rpc_ready(self):
		_rpc_teleport_peer.rpc_id(pid, cp)


@rpc("authority", "call_remote", "reliable")
func _rpc_teleport_peer(world_pos: Vector2) -> void:
	var lp: Player = SaveGame._local_player(get_tree())
	if lp != null:
		lp.request_teleport(world_pos)


@rpc("authority", "call_local", "reliable")
func _rpc_run_wiped(payload: Dictionary) -> void:
	run_wiped_received.emit(payload)


func request_retry_dungeon() -> void:
	if multiplayer.is_server():
		_host_retry_dungeon(multiplayer.get_unique_id())
	elif NetworkManager.rpc_ready(self):
		_rpc_request_retry.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_retry() -> void:
	if multiplayer.is_server():
		_host_retry_dungeon(multiplayer.get_remote_sender_id())


func _host_retry_dungeon(peer_id: int) -> void:
	var slot: int = _slot_of_peer(peer_id)
	if slot < 0:
		return
	var inst: Dictionary = _instances[slot] as Dictionary
	var sc: DungeonScene = inst.get("scene") as DungeonScene
	if sc == null or not is_instance_valid(sc):
		return
	inst["sparks"] = int(inst.get("max_sparks", 3))
	inst["wiped"] = false
	sc.on_boss_reset()
	var cp: Vector2 = sc.checkpoint_world()
	for pid_v: Variant in inst.get("peers", []) as Array:
		var pid: int = int(pid_v)
		var p: Player = _player_by_peer(pid)
		if p != null:
			p.health.heal_full()
			p.health.grant_grace(1.5)
			if pid == multiplayer.get_unique_id():
				p.request_teleport(cp)
			elif NetworkManager.rpc_ready(self):
				_rpc_teleport_peer.rpc_id(pid, cp)
	_broadcast_hud_state(slot)


## Host-only: awards completion loot, Resonance / Rest Bonus / First-Clear / Echo Shards,
## spawns the exit seal + reliquary chest, and broadcasts Solo/Coop Victory & MVP stats!
func host_complete_run(slot: int, reliquary_world_pos: Vector2, exit_local_pos: Vector2, bonus_part_broken: bool = false) -> void:
	if not multiplayer.is_server() or not _instances.has(slot):
		return
	var inst: Dictionary = _instances[slot] as Dictionary
	if bool(inst.get("completed", false)):
		return
	inst["completed"] = true
	var dungeon_id: String = String(inst.get("dungeon_id", ""))
	var def: Dictionary = DungeonRules.by_id(dungeon_id)
	var clear_sec: float = float(inst.get("elapsed", 0.0))
	var peers: Array = inst.get("peers", []) as Array
	var use_res_map: Dictionary = inst.get("use_res", {}) as Dictionary
	var stats_map: Dictionary = inst.get("stats", {}) as Dictionary

	## Spawn visual reliquary chest & return seal on all participating peers
	var chests: LootChests = LootChests.of(get_tree())
	if chests != null:
		chests.appear("dungeon_clear_%d_%d" % [slot, int(Time.get_ticks_msec() % 100000)], "rare", reliquary_world_pos, false, false)
	for pid_v: Variant in peers:
		var pid: int = int(pid_v)
		if pid == multiplayer.get_unique_id():
			_rpc_spawn_exit_seal(slot, exit_local_pos)
		elif NetworkManager.rpc_ready(self):
			_rpc_spawn_exit_seal.rpc_id(pid, slot, exit_local_pos)

	var party_rows: Array[Dictionary] = []
	for pid_v: Variant in peers:
		var pid: int = int(pid_v)
		if stats_map.has(pid):
			party_rows.append(stats_map[pid] as Dictionary)
	var mvp_map: Dictionary = DungeonRules.assign_mvp_titles(party_rows)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(inst.get("seed", 1)) ^ int(Time.get_ticks_usec())

	for pid_v: Variant in peers:
		var pid: int = int(pid_v)
		var p: Player = _player_by_peer(pid)
		if p == null or p.dungeons == null:
			continue
		var want_res: bool = bool(use_res_map.get(pid, true))
		var row: Dictionary = stats_map.get(pid, {}) as Dictionary
		var was_first: bool = p.dungeons.clear_count(dungeon_id) <= 0
		var has_charge: bool = p.dungeons.charges() >= 1
		var will_use_res: bool = want_res and has_charge
		var will_double: bool = will_use_res and ResonanceRules.rest_doubles_ready(p.dungeons.resonance) >= 1

		var rolled: Dictionary = DungeonRules.roll_victory_rewards(def, rng, was_first, will_use_res, will_double, bonus_part_broken)
		var apply_res: Dictionary = p.dungeons.apply_victory(
			dungeon_id,
			want_res,
			clear_sec,
			int(row.get("counters", 0)),
			int(row.get("staggers", 0)),
			float(row.get("damage", 0.0)),
			int(row.get("hits_taken", 0)),
			int(rolled.get("echo_shards", 0))
		)
		p.progress.award(int(rolled.get("copper", 0)), int(rolled.get("xp", 0)))
		for it_list_key: String in ["first_clear_items", "items"]:
			for it_v: Variant in rolled.get(it_list_key, []) as Array:
				if it_v is Dictionary:
					var it: Dictionary = it_v as Dictionary
					var iid: String = String(it.get("id", ""))
					var icnt: int = int(it.get("count", 1))
					if not iid.is_empty() and icnt > 0 and p.inventory != null:
						var left: int = p.inventory.give(iid, icnt)
						if left > 0:
							DropComponent.spawn_drops(get_tree(), [{"id": iid, "count": left}], p.global_position)

		var summary: Dictionary = {
			"slot": slot,
			"dungeon_id": dungeon_id,
			"name": String(def.get("name", "")),
			"zone_name": String(def.get("zone_name", "SÜDKAP")),
			"clear_sec": clear_sec,
			"new_best_time": bool(apply_res.get("new_best_time", false)),
			"first_clear": bool(apply_res.get("first_clear", false)),
			"used_resonance": bool(apply_res.get("consumed_resonance", false)),
			"doubled_by_rest": bool(apply_res.get("consumed_rest_double", false)),
			"sparks_left": int(inst.get("sparks", 0)),
			"max_sparks": int(inst.get("max_sparks", 3)),
			"bonus_part_broken": bonus_part_broken,
			"xp": int(rolled.get("xp", 0)),
			"copper": int(rolled.get("copper", 0)),
			"echo_granted": int(apply_res.get("echo_granted", 0)),
			"echo_capped": bool(apply_res.get("echo_capped", false)),
			"items": rolled.get("items", []),
			"first_clear_items": rolled.get("first_clear_items", []),
			"self_stats": row.duplicate(true),
			"party_stats": party_rows.duplicate(true),
			"mvp_titles": mvp_map.duplicate(true),
		}
		if pid == multiplayer.get_unique_id():
			_rpc_run_victory(summary)
		elif NetworkManager.rpc_ready(self):
			_rpc_run_victory.rpc_id(pid, summary)
	_broadcast_hud_state(slot)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_exit_seal(slot: int, exit_local_pos: Vector2) -> void:
	var sc: DungeonScene = _mounted.get(slot) as DungeonScene
	if sc != null and is_instance_valid(sc):
		sc.spawn_exit_seal(exit_local_pos)


@rpc("authority", "call_local", "reliable")
func _rpc_run_victory(summary: Dictionary) -> void:
	run_victory_received.emit(summary)


# ==============================================================================
# Leaving & Re-running a Dungeon
# ==============================================================================

func request_leave_dungeon() -> void:
	if multiplayer.is_server():
		_host_leave_dungeon(multiplayer.get_unique_id())
	elif NetworkManager.rpc_ready(self):
		_rpc_request_leave.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_leave() -> void:
	if multiplayer.is_server():
		_host_leave_dungeon(multiplayer.get_remote_sender_id())


func _host_leave_dungeon(peer_id: int) -> void:
	var slot: int = _slot_of_peer(peer_id)
	if slot < 0:
		return
	var inst: Dictionary = _instances[slot] as Dictionary
	var ret_map: Dictionary = inst.get("return_map", {}) as Dictionary
	var ret_pos: Vector2 = ret_map.get(peer_id, inst.get("entrance_pos", Vector2.ZERO)) as Vector2
	var peers: Array = inst.get("peers", []) as Array
	peers.erase(peer_id)
	var p: Player = _player_by_peer(peer_id)
	if p != null and p.health.current <= 0.0:
		p.health.heal_full()
	if peer_id == multiplayer.get_unique_id():
		_rpc_exit_and_unmount(slot, ret_pos, peers.is_empty())
	elif NetworkManager.rpc_ready(self):
		_rpc_exit_and_unmount.rpc_id(peer_id, slot, ret_pos, true)
	if peers.is_empty():
		_instances.erase(slot)
		_unmount_local_scene(slot)


@rpc("authority", "call_local", "reliable")
func _rpc_exit_and_unmount(slot: int, return_pos: Vector2, unmount_local: bool) -> void:
	var lp: Player = SaveGame._local_player(get_tree())
	if lp != null:
		await _play_wipe_teleport(lp, return_pos)
	if is_inside_tree():
		get_tree().call_group("boss_bar", "release")
	if unmount_local and not multiplayer.is_server():
		_unmount_local_scene(slot)
	elif unmount_local and multiplayer.is_server() and not _instances.has(slot):
		_unmount_local_scene(slot)


func request_rerun_dungeon(use_resonance: bool) -> void:
	if multiplayer.is_server():
		_host_rerun_dungeon(multiplayer.get_unique_id(), use_resonance)
	elif NetworkManager.rpc_ready(self):
		_rpc_request_rerun.rpc_id(1, use_resonance)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_rerun(use_resonance: bool) -> void:
	if multiplayer.is_server():
		_host_rerun_dungeon(multiplayer.get_remote_sender_id(), use_resonance)


func _host_rerun_dungeon(peer_id: int, use_resonance: bool) -> void:
	var slot: int = _slot_of_peer(peer_id)
	if slot < 0:
		return
	var inst: Dictionary = _instances[slot] as Dictionary
	var dungeon_id: String = String(inst.get("dungeon_id", ""))
	var peers_copy: Array[int] = []
	for pv: Variant in inst.get("peers", []) as Array:
		peers_copy.append(int(pv))
	var ret_copy: Dictionary = (inst.get("return_map", {}) as Dictionary).duplicate(true)
	var use_map: Dictionary = (inst.get("use_res", {}) as Dictionary).duplicate(true)
	use_map[peer_id] = use_resonance
	## Clean old slot first
	_instances.erase(slot)
	_unmount_local_scene(slot)
	var new_slot: int = _host_launch_instance(dungeon_id, peers_copy, use_map)
	if new_slot >= 0 and _instances.has(new_slot):
		(_instances[new_slot] as Dictionary)["return_map"] = ret_copy


func _on_peer_disconnected(peer_id: int) -> void:
	var slot: int = _slot_of_peer(peer_id)
	if slot >= 0:
		var inst: Dictionary = _instances[slot] as Dictionary
		var peers: Array = inst.get("peers", []) as Array
		peers.erase(peer_id)
		if peers.is_empty():
			_instances.erase(slot)
			_unmount_local_scene(slot)
	if not _lobby.is_empty():
		var eligible: Array = _lobby.get("eligible", []) as Array
		if eligible.has(peer_id):
			_host_close_lobby("MITSPIELER GETRENNT")


func _player_by_peer(peer_id: int) -> Player:
	for p: Player in Player.all:
		if p != null and is_instance_valid(p) and p.get_multiplayer_authority() == peer_id:
			return p
	return null
