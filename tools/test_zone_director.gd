extends Node
## End-to-end 2-process loopback coop test for `ZoneDirector`, `ZoneCoop`, `MapPingPillar`, and `LivingTree`
## (`docs/v2_zonenwelt_atlas_konzept.md` 6.5, 12.2, step 9) on isolated continent `&"lab"` (`labor_wiese` <-> `labor_wald`).
##
## Supports both:
## 1) Single-command self-orchestrated 2-process run:
##      godot --headless --path . res://tools/test_zone_director.tscn
##    (binds Host on port 17924 and spawns a real `-- --client` OS child process, checking its log & exit code)
## 2) Manual 2-process run:
##      godot --headless --path . res://tools/test_zone_director.tscn -- --server
##      godot --headless --path . res://tools/test_zone_director.tscn -- --client   (or without args while server holds port)

const DEFAULT_PORT: int = 17924
const LAB_SCENE: PackedScene = preload("res://tools/zone_lab.tscn")
const DROP_SCENE: PackedScene = preload("res://src/entities/drops/item_drop.tscn")

const HOST_START_TILE: Vector2 = Vector2(1055.0, 966.0)
const CLIENT_FAR_WEST_TILE: Vector2 = Vector2(1008.0, 950.0)
const HOST_APPROACH_TILE: Vector2 = Vector2(1120.0, 966.0)
const HOST_FOREST_DEEP_TILE: Vector2 = Vector2(1235.0, 975.0)
const ENTITY_FOREST_TILE: Vector2 = Vector2(1212.0, 966.0)
const CLIENT_FOREST_JOIN_TILE: Vector2 = Vector2(1184.0, 966.0)
const PING_FOREST_TILE: Vector2 = Vector2(1196.0, 966.0)

class _RpcErrorLogger:
	extends Logger
	var rpc_errors: PackedStringArray = PackedStringArray()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var combined: String = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		if combined.contains("Node not found") or combined.contains("Cannot get path") or combined.contains("_send_rpc") or combined.contains("process_rpc") or combined.contains("on_despawn_receive"):
			rpc_errors.append(combined)

	func _log_message(message: String, error: bool) -> void:
		if error and (message.contains("Node not found") or message.contains("Cannot get path")):
			rpc_errors.append(message)


var _server: bool = false
var _spawned_pid: int = -1
var _err_logger: _RpcErrorLogger = null
var _lab: Node2D = null
var _director: ZoneDirector = null
var _coop: ZoneCoop = null

var _checks: int = 0
var _fails: int = 0
var _phase: int = 0
var _client_ready_phase: int = 0
var _client_done: bool = false
var _client_checks: int = 0
var _client_fails: int = 0

var _felled_tree_name: String = ""
var _live_hit_tree_name: String = ""
var _spider_name: String = ""
var _drop_name: String = ""

var _last_ping_peer: int = 0
var _last_ping_pos: Vector2 = Vector2.INF
var _last_ping_zone: StringName = &""
var _ping_count: int = 0

var _join_resolved_ok: bool = false
var _join_resolved_zone: StringName = &""


func _role() -> String:
	return "HOST" if _server else "CLIENT"


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		var msg: String = "ZONE DIRECTOR %s FAIL: %s" % [_role(), what]
		push_error(msg)
		print(msg)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(110.0).timeout.connect(func() -> void:
		push_error("ZONE DIRECTOR %s TIMEOUT" % _role())
		print("ZONE DIRECTOR %s TIMEOUT" % _role())
		_cleanup_and_quit(1)
	)
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _until(cond: Callable, seconds: float = 20.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _cleanup_and_quit(code: int) -> void:
	if _spawned_pid > 0 and OS.is_process_running(_spawned_pid):
		OS.kill(_spawned_pid)
		_spawned_pid = -1
	if _lab != null and is_instance_valid(_lab):
		_lab.queue_free()
	NetworkManager.leave(false)
	get_tree().quit(code)


func _run() -> void:
	_err_logger = _RpcErrorLogger.new()
	OS.add_logger(_err_logger)

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = DEFAULT_PORT
	var explicit_server: bool = args.has("--server")
	var explicit_client: bool = args.has("--client")
	for arg: String in args:
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()

	var auto_spawn_client: bool = false
	if explicit_client:
		_server = false
		var jerr: Error = NetworkManager.join("127.0.0.1", port, "", true)
		if jerr != OK:
			print("ZONE DIRECTOR CLIENT: join failed (%d)" % jerr)
			get_tree().quit(1)
			return
	elif explicit_server:
		_server = true
		var herr: Error = NetworkManager.host_multiplayer(port)
		if herr != OK:
			print("ZONE DIRECTOR HOST: bind failed (%d)" % herr)
			get_tree().quit(1)
			return
	else:
		# Auto-detect: try hosting on `port`; if free, spawn the second Godot process as `--client` once `ZoneLab` is ready.
		# If `port` is already bound by an external `--server`, join it as client!
		var try_host: Error = NetworkManager.host_multiplayer(port)
		if try_host == OK:
			_server = true
			auto_spawn_client = true
		else:
			_server = false
			var fallback_join: Error = NetworkManager.join("127.0.0.1", port, "", true)
			if fallback_join != OK:
				print("ZONE DIRECTOR CLIENT: fallback join failed (%d)" % fallback_join)
				get_tree().quit(1)
				return

	_lab = LAB_SCENE.instantiate() as Node2D
	add_child(_lab)
	await _frames(4)

	if not _server:
		var cerr: Error = NetworkManager.connect_pending_guest()
		_check(cerr == OK, "client connect_pending_guest started (%d)" % cerr)
		if cerr != OK:
			_cleanup_and_quit(1)
			return
		# Re-connect ZoneDirector's `connected_to_server` once actual ENet peer is installed
		if _lab.get("director") != null:
			var dir_node: ZoneDirector = _lab.get("director") as ZoneDirector
			if dir_node != null and not multiplayer.connected_to_server.is_connected(dir_node._sync_client_with_host):
				multiplayer.connected_to_server.connect(dir_node._sync_client_with_host)

	if auto_spawn_client:
		var proj_path: String = ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
		var exe_path: String = OS.get_executable_path()
		if exe_path.ends_with("_console.exe"):
			var direct_exe: String = exe_path.trim_suffix("_console.exe") + ".exe"
			if FileAccess.file_exists(direct_exe):
				exe_path = direct_exe
		var child_args: PackedStringArray = PackedStringArray([
			"--headless",
			"--path",
			proj_path,
			"res://tools/test_zone_director.tscn",
			"--",
			"--client",
			"--port=%d" % port,
		])
		_spawned_pid = OS.create_process(exe_path, child_args)
		_check(_spawned_pid > 0, "spawned real second Godot client process (pid=%d)" % _spawned_pid)
		if _spawned_pid <= 0:
			_cleanup_and_quit(1)
			return

	print("ZONE DIRECTOR %s READY (port=%d)" % [_role(), port])

	_director = _lab.get("director") as ZoneDirector
	_check(_director != null, "ZoneLab created ZoneDirector")
	if _director == null:
		_cleanup_and_quit(1)
		return
	_coop = _director.get_node_or_null("Coop") as ZoneCoop
	_check(_coop != null and _coop == ZoneCoop.of(get_tree()) and _coop.is_in_group("zone_coop"), "ZoneDirector.setup created Coop child in group zone_coop")
	if _coop == null:
		_cleanup_and_quit(1)
		return

	_coop.ping_received.connect(_on_ping_received)
	_coop.join_peer_resolved.connect(_on_join_resolved)

	if _server:
		await _run_host()
	else:
		await _run_client()


func _on_ping_received(peer_id: int, world_pos: Vector2, zone_id: StringName) -> void:
	_last_ping_peer = peer_id
	_last_ping_pos = world_pos
	_last_ping_zone = zone_id
	_ping_count += 1


func _on_join_resolved(ok: bool, _target_peer: int, target_zone: StringName, _arrival_pos: Vector2, _waystone_id: StringName, _reason: String) -> void:
	_join_resolved_ok = ok
	_join_resolved_zone = target_zone


# --- RPC coordination between Host and Client test harnesses --------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_set_phase(p: int, felled_tree: String, spider: String, drop: String, live_tree: String) -> void:
	_phase = p
	if not felled_tree.is_empty():
		_felled_tree_name = felled_tree
	if not spider.is_empty():
		_spider_name = spider
	if not drop.is_empty():
		_drop_name = drop
	if not live_tree.is_empty():
		_live_hit_tree_name = live_tree


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_phase(p: int) -> void:
	if multiplayer.is_server():
		_client_ready_phase = p


@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_summary(checks: int, fails: int) -> void:
	if multiplayer.is_server():
		_client_checks = checks
		_client_fails = fails
		_client_done = true


# --- HOST FLOW ------------------------------------------------------------------------------------------------------

func _run_host() -> void:
	var players: Node2D = _lab.get_node("Players") as Node2D
	_check(await _until(func() -> bool: return players.get_child_count() == 2, 25.0), "both Host and Client players spawned")
	if players.get_child_count() < 2:
		_cleanup_and_quit(1)
		return

	var host_player: Player = players.get_node_or_null("1") as Player
	var client_id: int = 0
	for child: Node in players.get_children():
		if child.name.is_valid_int() and child.name.to_int() != 1:
			client_id = child.name.to_int()
	var client_player: Player = players.get_node_or_null(str(client_id)) as Player
	_check(host_player != null and client_player != null and client_id > 1, "host and client Player instances resolved (client=%d)" % client_id)
	if host_player == null or client_player == null:
		_cleanup_and_quit(1)
		return

	host_player.story_lock = true
	host_player.auto_walk = Vector2.INF
	host_player.request_teleport(Atlas.px_of(HOST_START_TILE))

	# 1. Both connect in `labor_wiese`
	_check(await _until(func() -> bool:
		return _director.player_zone.get(1, &"") == &"labor_wiese" and _director.player_zone.get(client_id, &"") == &"labor_wiese"
	, 8.0), "both peers start in labor_wiese (%s)" % str(_director.player_zone))
	_check(_director.is_loaded(&"labor_wiese") and not _director.is_loaded(&"labor_wald"), "only labor_wiese loaded initially on host")

	# Verify PocketSpace parent-zone holding & pocket visibility isolation on host
	var pocket_rect: Rect2 = PocketSpace.slot_rect(PocketSpace.Lane.ROOM, 2)
	var pocket_pos: Vector2 = pocket_rect.position + Vector2(128.0, 128.0)
	PocketSpace.register_pocket(&"test_lab_room", pocket_rect, &"labor_wiese")
	_check(_director.zone_for_world_pos(pocket_pos) == &"labor_wiese", "PocketSpace resolves parent zone labor_wiese")
	var pocket_drop: ItemDrop = DROP_SCENE.instantiate() as ItemDrop
	pocket_drop.name = "PocketDropTest"
	pocket_drop.item_id = "wood"
	pocket_drop.count = 1
	pocket_drop.position = pocket_pos
	(_lab.get_node("Drops") as Node2D).add_child(pocket_drop, true)
	await _frames(4)
	_check(not _coop.is_entity_visible_to(pocket_drop, client_id), "PocketSpace drop is hidden from outer-zone client")
	pocket_drop.queue_free()
	PocketSpace.unregister_pocket(&"test_lab_room")

	_rpc_set_phase.rpc_id(client_id, 1, "", "", "", "")
	_check(await _until(func() -> bool: return _client_ready_phase >= 1, 12.0), "client confirmed Phase 1 in labor_wiese")

	# 2. Host crosses `labor_kronengang` deep into `labor_wald`; Client stays far west in `labor_wiese`
	host_player.request_teleport(Atlas.px_of(HOST_APPROACH_TILE))
	_check(await _until(func() -> bool: return _director.is_loaded(&"labor_wald"), 20.0), "host streams labor_wald on approaching labor_kronengang")
	await _frames(3)
	_check(_director.threshold_open(&"labor_kronengang"), "seamless threshold labor_kronengang opens on host once both sides attach")

	host_player.request_teleport(Atlas.px_of(HOST_FOREST_DEEP_TILE))
	_check(await _until(func() -> bool: return _director.player_zone.get(1, &"") == &"labor_wald", 5.0), "host crosses into labor_wald")
	await get_tree().create_timer(0.8).timeout

	_check(_director.is_loaded(&"labor_wiese") and _director.is_loaded(&"labor_wald"), "host keeps BOTH labor_wiese (for client) and labor_wald (for host) loaded")
	_check(not _director.peer_has_stage_attached(client_id, &"labor_wald"), "host tracks that distant client has NOT attached labor_wald")
	_check(_director.peers_holding_zone(&"labor_wald").is_empty(), "peers_holding_zone(labor_wald) is empty while client is far west")

	# Host fells a choppable tree in `labor_wald` -> 0 RPC/Node errors on Client!
	var wald_stage: ZoneStage = _director.stage(&"labor_wald")
	var chop_tree: LivingTree = null
	var second_tree: LivingTree = null
	for t: LivingTree in wald_stage.trees:
		if is_instance_valid(t) and not t.is_depleted() and t.stage >= 3 and t.stage <= 4:
			if chop_tree == null:
				chop_tree = t
			elif second_tree == null:
				second_tree = t
				break
	_check(chop_tree != null and second_tree != null, "found choppable trees in labor_wald")
	if chop_tree != null:
		_felled_tree_name = String(chop_tree.name)
		for _hit: int in 8:
			if chop_tree.is_depleted():
				break
			chop_tree.strike_with_axe(chop_tree.global_position + Vector2(-18.0, 0.0))
		_check(chop_tree.is_depleted(), "host felled tree %s in labor_wald" % _felled_tree_name)
	if second_tree != null:
		_live_hit_tree_name = String(second_tree.name)

	# Let felling animation & wood drops settle while client is still far away
	await get_tree().create_timer(1.0).timeout

	# 3. Spawn dynamic Enemy & Drop in `labor_wald` -> hidden from distant Client!
	var forest_entity_pos: Vector2 = Atlas.px_of(ENTITY_FOREST_TILE)
	var spider: Node2D = _lab.call("spawn_species", "shadow_spider", forest_entity_pos, 0.0) as Node2D
	_check(spider != null, "host spawned test ShadowSpider in labor_wald")
	if spider != null:
		spider.set_physics_process(false)
		_spider_name = String(spider.name)

	var test_drop: ItemDrop = DROP_SCENE.instantiate() as ItemDrop
	test_drop.item_id = "stone"
	test_drop.count = 2
	test_drop.position = forest_entity_pos + Vector2(20.0, 0.0)
	(_lab.get_node("Drops") as Node2D).add_child(test_drop, true)
	_drop_name = String(test_drop.name)

	await _frames(10)
	var spider_sync: MultiplayerSynchronizer = _coop.synchronizer_of(spider)
	var drop_sync: MultiplayerSynchronizer = _coop.synchronizer_of(test_drop)
	_check(spider_sync != null and not spider_sync.is_visibility_public(), "enemy synchronizer has public_visibility == false")
	_check(drop_sync != null and not drop_sync.is_visibility_public(), "drop synchronizer has public_visibility == false")
	_check(spider_sync != null and not spider_sync.get_visibility_for(client_id) and not _coop.is_entity_visible_to(spider, client_id), "visibility filter hides forest enemy from distant client in labor_wiese")
	_check(drop_sync != null and not drop_sync.get_visibility_for(client_id) and not _coop.is_entity_visible_to(test_drop, client_id), "visibility filter hides forest drop from distant client in labor_wiese")

	# Ask Client to verify Phase 2 & Phase 3a (not loaded, 0 errors, enemy & drop absent on client, distant ping spawns no pillar)
	_coop.request_ping(Atlas.px_of(PING_FOREST_TILE))
	_rpc_set_phase.rpc_id(client_id, 2, _felled_tree_name, _spider_name, _drop_name, _live_hit_tree_name)
	_check(await _until(func() -> bool: return _client_ready_phase >= 2, 15.0), "client verified labor_wald NOT loaded & enemy/drop hidden while far west")

	# Phase 3b: Tell Client to advance into `labor_wald` -> streams zone, gets stump state, enemy & drop become visible!
	_rpc_set_phase.rpc_id(client_id, 3, _felled_tree_name, _spider_name, _drop_name, _live_hit_tree_name)
	_check(await _until(func() -> bool:
		return _director.peer_has_stage_attached(client_id, &"labor_wald") and _director.player_zone.get(client_id, &"") == &"labor_wald"
	, 25.0), "client streamed & entered labor_wald")
	_coop.refresh_visibility()
	await _frames(8)
	_check(spider_sync != null and spider_sync.get_visibility_for(client_id) and _coop.is_entity_visible_to(spider, client_id), "visibility filter reveals forest enemy once client enters labor_wald")
	_check(drop_sync != null and drop_sync.get_visibility_for(client_id) and _coop.is_entity_visible_to(test_drop, client_id), "visibility filter reveals forest drop once client enters labor_wald")
	_check(_director.peers_holding_zone(&"labor_wald").has(client_id), "peers_holding_zone(labor_wald) now includes client")

	# Strike second tree while Client IS holding `labor_wald` -> targeted live `.rpc_id` reaches Client!
	if second_tree != null:
		second_tree.strike_with_axe(second_tree.global_position + Vector2(-16.0, 0.0))

	_check(await _until(func() -> bool: return _client_ready_phase >= 3, 15.0), "client verified enemy/drop replication + felled & live tree sync in labor_wald")

	# 4. Map Ping (`request_ping`) in same zone -> Client pings, Host receives `ping_received` + `MapPingPillar`!
	var prev_pings: int = _ping_count
	for node: Node in get_tree().get_nodes_in_group("map_ping_pillars"):
		node.queue_free()
	await _frames(2)
	await get_tree().create_timer(0.55).timeout ## clear rate limit window
	_rpc_set_phase.rpc_id(client_id, 4, _felled_tree_name, _spider_name, _drop_name, _live_hit_tree_name)
	_check(await _until(func() -> bool: return _ping_count > prev_pings and _last_ping_peer == client_id, 10.0), "host received client's request_ping via ping_received signal")
	_check(_last_ping_zone == &"labor_wald" and _last_ping_pos.distance_to(Atlas.px_of(PING_FOREST_TILE)) < 2.0, "ping carries exact world_pos and zone_id")
	var pillars: Array[Node] = get_tree().get_nodes_in_group("map_ping_pillars")
	_check(not pillars.is_empty(), "MapPingPillar spawned in world when host is in same zone")
	if not pillars.is_empty():
		var p_node: MapPingPillar = pillars[0] as MapPingPillar
		_check(p_node != null and p_node.material == Unlit.material(), "MapPingPillar uses Unlit.material()")
	_check(await _until(func() -> bool: return _client_ready_phase >= 4, 10.0), "client also verified ping_received + MapPingPillar in same zone")

	if spider != null and is_instance_valid(spider):
		spider.queue_free()
	if test_drop != null and is_instance_valid(test_drop):
		test_drop.queue_free()

	# 5. Unload `labor_wald` on BOTH peers, advance 7 days, verify `catch_up(days)` & `request_join_peer`!
	var felled_before: String = str(chop_tree.state) if chop_tree != null else ""
	host_player.request_teleport(Atlas.px_of( Vector2(1012.0, 958.0) ))
	_rpc_set_phase.rpc_id(client_id, 5, _felled_tree_name, "", "", "")
	_check(await _until(func() -> bool: return _client_ready_phase >= 5, 15.0), "client unloaded labor_wald after retreating far west")
	_check(await _until(func() -> bool: return not _director.is_loaded(&"labor_wald"), 10.0), "host unloaded labor_wald once all peers left range")

	TimeManager.day += 7
	host_player.request_teleport(Atlas.px_of(HOST_FOREST_DEEP_TILE))
	_check(await _until(func() -> bool: return _director.is_loaded(&"labor_wald") and _director.player_zone.get(1, &"") == &"labor_wald", 20.0), "host reloaded labor_wald after 7 days")
	var regrown_tree: LivingTree = _director.stage(&"labor_wald").trees_root.get_node_or_null(_felled_tree_name) as LivingTree
	_check(regrown_tree != null and str(regrown_tree.state) != felled_before, "felled stump caught up 7 missed days on reload (%s -> %s)" % [felled_before, str(regrown_tree.state) if regrown_tree != null else "null"])
	_check(not _director.peer_has_stage_attached(client_id, &"labor_wald"), "client still kept labor_wald unloaded during host's reload")

	# Verify `request_join_peer` from Client to Host in `labor_wald`
	_rpc_set_phase.rpc_id(client_id, 6, "", "", "", "")
	_check(await _until(func() -> bool: return _client_done, 20.0), "client completed all coop checks and reported summary")
	_check(_client_fails == 0 and _client_checks >= 12, "client passed all checks (%d checks, %d fails)" % [_client_checks, _client_fails])

	if _spawned_pid > 0:
		var exited: bool = await _until(func() -> bool: return not OS.is_process_running(_spawned_pid), 8.0)
		_check(exited, "spawned client process exited cleanly")
		if exited:
			var exit_code: int = OS.get_process_exit_code(_spawned_pid)
			_check(exit_code == 0, "spawned client process exit code == 0 (got %d)" % exit_code)
			_spawned_pid = -1
	_check(_err_logger == null or _err_logger.rpc_errors.is_empty(), "host recorded 0 RPC/Node errors (%s)" % str(_err_logger.rpc_errors if _err_logger != null else []))

	var total_checks: int = _checks + _client_checks
	if _fails == 0 and _client_fails == 0:
		print("ZONE DIRECTOR COOP OK (%d checks)" % total_checks)
		_cleanup_and_quit(0)
	else:
		print("ZONE DIRECTOR COOP FAILED (host_fails=%d, client_fails=%d)" % [_fails, _client_fails])
		_cleanup_and_quit(1)


# --- CLIENT FLOW ----------------------------------------------------------------------------------------------------

func _run_client() -> void:
	var players: Node2D = _lab.get_node("Players") as Node2D
	var ready_ok: bool = await _until(func() -> bool:
		var uid: int = multiplayer.get_unique_id()
		return uid > 1 and players.has_node(str(uid)) and players.has_node("1")
	, 25.0)
	var my_id: int = multiplayer.get_unique_id()
	var me: Player = players.get_node_or_null(str(my_id)) as Player
	_check(ready_ok and me != null, "client connected and spawned replicated player")
	if not ready_ok or me == null:
		var ch_names: PackedStringArray = PackedStringArray()
		for ch: Node in players.get_children():
			ch_names.append(String(ch.name))
		var p_stat: int = multiplayer.multiplayer_peer.get_connection_status() if multiplayer.multiplayer_peer != null else -1
		print("CLI-DIAG status=%d my_id=%d players=%s join_err=%s path=%s" % [p_stat, my_id, str(ch_names), NetworkManager.last_join_error, str(players.get_path())])
		_cleanup_and_quit(1)
		return

	me.story_lock = true
	me.auto_walk = Vector2.INF
	me.request_teleport(Atlas.px_of(CLIENT_FAR_WEST_TILE))

	# Wait for Phase 1
	_check(await _until(func() -> bool: return _phase >= 1, 15.0), "received Phase 1 from host")
	_check(await _until(func() -> bool:
		return _director.player_zone.get(my_id, &"") == &"labor_wiese" and _director.player_zone.get(1, &"") == &"labor_wiese"
	, 8.0), "client received player_zone for both peers in labor_wiese")
	_check(_director.is_loaded(&"labor_wiese") and not _director.is_loaded(&"labor_wald"), "client has only labor_wiese loaded")
	_rpc_ack_phase.rpc_id(1, 1)

	# Wait for Phase 2 (Host walked deep into `labor_wald`, felled a tree, spawned enemy/drop, and sent a forest ping)
	_check(await _until(func() -> bool: return _phase >= 2, 30.0), "received Phase 2 from host")
	await get_tree().create_timer(0.6).timeout
	_check(_director.is_loaded(&"labor_wiese"), "client keeps labor_wiese loaded")
	_check(not _director.is_loaded(&"labor_wald") and not _director.is_building(), "client did NOT load labor_wald while far west even though host is in labor_wald")
	_check(_director.player_zone.get(1, &"") == &"labor_wald", "client knows host's remote zone_id is labor_wald")
	_check(not (_lab.get_node("Enemies") as Node2D).has_node(_spider_name), "forest enemy is hidden (not spawned) on distant client")
	_check(not (_lab.get_node("Drops") as Node2D).has_node(_drop_name), "forest drop is hidden (not spawned) on distant client")
	_check(_last_ping_peer == 1 and _last_ping_zone == &"labor_wald", "client received host's distant map ping metadata for Atlas")
	_check(get_tree().get_nodes_in_group("map_ping_pillars").is_empty(), "distant map ping in labor_wald did NOT spawn MapPingPillar in labor_wiese")
	_rpc_ack_phase.rpc_id(1, 2)

	# Phase 3: Client advances into `labor_wald` -> streams `labor_wald`, sees felled stump + enemy + drop + live tree hit!
	_check(await _until(func() -> bool: return _phase >= 3, 15.0), "received Phase 3 from host")
	me.request_teleport(Atlas.px_of(CLIENT_FOREST_JOIN_TILE))
	_check(await _until(func() -> bool: return _director.is_loaded(&"labor_wald"), 22.0), "client streamed labor_wald on moving east")
	_check(await _until(func() -> bool: return _director.player_zone.get(my_id, &"") == &"labor_wald", 6.0), "client player_zone updated to labor_wald")
	_check(await _until(func() -> bool:
		return (_lab.get_node("Enemies") as Node2D).has_node(_spider_name) and (_lab.get_node("Drops") as Node2D).has_node(_drop_name)
	, 8.0), "forest enemy and drop became visible and spawned on client after advancing")

	var client_wald: ZoneStage = _director.stage(&"labor_wald")
	var synced_stump: LivingTree = client_wald.trees_root.get_node_or_null(_felled_tree_name) as LivingTree if client_wald != null else null
	_check(await _until(func() -> bool: return synced_stump != null and synced_stump.is_depleted(), 6.0), "client received felled tree state for %s via _rpc_request_zone" % _felled_tree_name)
	var live_tree: LivingTree = client_wald.trees_root.get_node_or_null(_live_hit_tree_name) as LivingTree if client_wald != null else null
	_check(await _until(func() -> bool: return live_tree != null and live_tree.total_axe_hits_taken >= 1, 6.0), "client received live targeted axe_hit RPC while holding labor_wald")
	_rpc_ack_phase.rpc_id(1, 3)

	# Phase 4: Client sends `request_ping` in `labor_wald` -> both peers in `labor_wald` get `ping_received` + `MapPingPillar`!
	_check(await _until(func() -> bool: return _phase >= 4, 15.0), "received Phase 4 from host")
	var p_before: int = _ping_count
	_coop.request_ping(Atlas.px_of(PING_FOREST_TILE))
	_check(await _until(func() -> bool: return _ping_count > p_before and _last_ping_peer == my_id, 6.0), "client received echoed ping_received from host")
	_check(not get_tree().get_nodes_in_group("map_ping_pillars").is_empty(), "MapPingPillar spawned on client in same zone")
	_rpc_ack_phase.rpc_id(1, 4)

	# Phase 5: Client retreats far west into `labor_wiese` -> `labor_wald` unloads cleanly on Client!
	_check(await _until(func() -> bool: return _phase >= 5, 15.0), "received Phase 5 from host")
	me.request_teleport(Atlas.px_of(CLIENT_FAR_WEST_TILE))
	_check(await _until(func() -> bool: return not _director.is_loaded(&"labor_wald"), 10.0), "client unloaded labor_wald after retreating beyond KEEP_TILES")
	_rpc_ack_phase.rpc_id(1, 5)

	# Phase 6: Client tests `request_join_peer` (first without waystone -> rejected cleanly, then `allow_direct = true` -> teleports & loads `labor_wald`)
	_check(await _until(func() -> bool: return _phase >= 6, 25.0), "received Phase 6 from host")
	_join_resolved_ok = true
	_coop.request_join_peer(1, false)
	_check(await _until(func() -> bool: return not _join_resolved_ok and _join_resolved_zone == &"labor_wald", 5.0), "request_join_peer without awakened waystone resolves false with target_zone")
	_coop.request_join_peer(1, true)
	_check(await _until(func() -> bool: return _join_resolved_ok and _director.is_loaded(&"labor_wald"), 15.0), "request_join_peer(1, true) loads target zone & teleports client to host")
	_check(me.global_position.distance_to(Atlas.px_of(HOST_FOREST_DEEP_TILE)) < 64.0, "client arrived near host in labor_wald")

	_check(_err_logger == null or _err_logger.rpc_errors.is_empty(), "client recorded 0 RPC/Node-not-found errors (%s)" % str(_err_logger.rpc_errors if _err_logger != null else []))
	print("ZONE DIRECTOR COOP CLIENT %s (%d checks)" % ["OK" if _fails == 0 else "FAILED", _checks])
	_rpc_client_summary.rpc_id(1, _checks, _fails)
	await get_tree().create_timer(0.35).timeout
	_cleanup_and_quit(0 if _fails == 0 else 1)
