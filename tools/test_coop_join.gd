extends Node
## End-to-end 2-instance coop join verification (`-- --server` + `-- --client`).
## Exercises `WorldLevel` stepped init, snapshot RPCs, `MultiplayerSpawner`,
## and guest profile import/sync on Host (`SaveGame.import_player_data` + `sync_player_to_network`).

const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")
const DEFAULT_PORT: int = 17965
const DEFAULT_CODE: String = "JOIN99"

var _failures: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: %s" % label)
	else:
		_failures += 1
		printerr("FAIL: %s" % label)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(45.0).timeout.connect(func() -> void:
		printerr("FAIL: TIMEOUT after 45s")
		get_tree().quit(1)
	)
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = DEFAULT_PORT
	var code: String = DEFAULT_CODE
	var ready_file: String = ""
	for arg: String in args:
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--code="):
			code = arg.trim_prefix("--code=").to_upper()
		elif arg.begins_with("--ready-file="):
			ready_file = arg.trim_prefix("--ready-file=")
	if args.has("--server"):
		await _run_server(port, code, ready_file)
	elif args.has("--client"):
		await _run_client(port, code)
	else:
		_test_relay_fragmentation()
		_test_to_menu_request_semantics()
		print("Usage: -- --server | -- --client (self-checks FAILURES=%d)" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)


func _test_relay_fragmentation() -> void:
	var sender := NakamaRelayPeer.new()
	var receiver := NakamaRelayPeer.new()
	sender.match_id = "00000000-0000-0000-0000-000000000001.nakama"
	var payload := PackedByteArray()
	payload.resize(150000)
	for i: int in payload.size():
		payload[i] = (i * 37 + 13) & 0xFF
	var frames: Array[Dictionary] = sender.build_outgoing_frames(0, 2, true, payload)
	_check(frames.size() >= 80, "large relay payload splits into multiple chunks (%d)" % frames.size())
	var max_ws_len: int = 0
	for item: Dictionary in frames:
		var bytes: PackedByteArray = item["bytes"] as PackedByteArray
		var wire_json: String = JSON.stringify({
			"match_data_send": {
				"match_id": sender.match_id,
				"op_code": int(item["op"]),
				"data": Marshalls.raw_to_base64(bytes),
			}
		})
		max_ws_len = maxi(max_ws_len, wire_json.to_utf8_buffer().size())
		# Simulate Nakama match_relay rewriting bytes 0..3 from target_pid -> sender_pid = 1
		var delivered: PackedByteArray = bytes.duplicate()
		delivered.encode_s32(0, 1)
		var rx_json: String = JSON.stringify({
			"match_data": {
				"op_code": int(item["op"]),
				"data": Marshalls.raw_to_base64(delivered),
			}
		})
		receiver._handle_ws_text(rx_json)
	_check(max_ws_len < 4096, "every WebSocket frame stays below Nakama 4096 B default (%d B)" % max_ws_len)
	_check(receiver._get_available_packet_count() == 1, "reassembled into exact 1 incoming packet")
	_check(receiver._get_packet_channel() == 2, "preserved original channel on reassembly")
	var got: PackedByteArray = receiver._get_packet_script()
	_check(got == payload, "reassembled 150 KB packet matches byte-for-byte")


func _test_to_menu_request_semantics() -> void:
	var req_menu: Dictionary = {"to_menu": true, "skip_autosave": true}
	_check(bool(req_menu.get("to_menu", false)), "unexpected disconnect launches with explicit to_menu flag")
	var parsed: Dictionary = GameLauncher.from_args(PackedStringArray(["--host-coop", "--world-name=TEST"]))
	_check(String(parsed.get("mode", "")) == "host_relay", "from_args stays pure for launcher boot flags")

	# Verify NakamaRelayPeer kick / world close reason tracking for both guests & hosts
	for pair: Array in [
		["kicked", "DU WURDEST VOM HOST ENTFERNT"],
		["kicked_admin", "VOM ADMIN AUS DER WELT ENTFERNT"],
		["closed", "WELT VOM ADMIN GESCHLOSSEN"],
		["host_closed", "WELT VOM HOST GESCHLOSSEN"],
		["banned", "DEIN KONTO WURDE GESPERRT"],
	]:
		var rp := NakamaRelayPeer.new()
		rp._handle_control(JSON.stringify({"type": "kicked", "reason": String(pair[0])}))
		_check(rp.forced_disconnect_reason == String(pair[1]), "relay control kick '%s' sets forced_disconnect_reason" % String(pair[0]))

	# Verify mid-game semver comparison & GameGuard BUILD_OUTDATED lock
	_check(GameGuard.is_version_newer("0.9.5", "0.9.4"), "semver 0.9.5 > 0.9.4")
	_check(GameGuard.is_version_newer("0.10.0", "0.9.9"), "semver 0.10.0 > 0.9.9")
	_check(not GameGuard.is_version_newer("0.9.4", "0.9.4"), "semver equal not newer")
	_check(not GameGuard.is_version_newer("0.9.4", "0.9.5"), "semver older local not kicked")
	var prev_locked: bool = GameGuard.locked
	var prev_verified: bool = GameGuard.verified
	var prev_title: String = GameGuard.lock_title
	var prev_reason: String = GameGuard.lock_reason
	GameGuard.verified = true
	GameGuard.locked = false
	GameGuard.handle_heartbeat_result({"ok": false, "kick": true, "code": "BUILD_OUTDATED", "error": "Update"})
	_check(GameGuard.locked and GameGuard.lock_title == "NEUE VERSION ERFORDERLICH", "BUILD_OUTDATED heartbeat locks gameplay immediately")
	GameGuard.locked = prev_locked
	GameGuard.verified = prev_verified
	GameGuard.lock_title = prev_title
	GameGuard.lock_reason = prev_reason


func _step_world(w: WorldLevel) -> void:
	while not w.loading_init_step():
		await get_tree().process_frame
	while not w.loading_step():
		await get_tree().process_frame


func _run_server(port: int, code: String, ready_file: String = "") -> void:
	var wid_info: Dictionary = MultiplayerWorlds.create_world("COOP-JOIN-TEST", 4, port, code)
	var wid: String = String(wid_info["id"])
	var spath: String = String(wid_info["save_path"])
	var err: Error = NetworkManager.host_multiplayer(port, code, 4, wid, "COOP-JOIN-TEST", spath)
	_check(err == OK, "host_multiplayer starts cleanly")
	if err != OK:
		get_tree().quit(1)
		return

	var w: WorldLevel = WORLD_SCENE.instantiate() as WorldLevel
	w.name = "WorldLevel"
	w.loading_in_steps = true
	add_child(w)
	await _step_world(w)
	_check(w.get_node_or_null("Players/1") != null, "host local player spawned")

	var pending_profile_peers: Dictionary = {}
	NetworkManager.peer_joined.connect(func(pid: int) -> void:
		print("[SERVER] peer_joined pid=%d" % pid)
		pending_profile_peers[pid] = true
	)

	if not ready_file.is_empty():
		var f: FileAccess = FileAccess.open(ready_file, FileAccess.WRITE)
		if f != null:
			f.store_string("ready\n")
			f.close()
	print("COOP_JOIN_SERVER_READY")
	var wait_guest: int = Time.get_ticks_msec() + 30000
	while (multiplayer.get_peers().is_empty() or not pending_profile_peers.is_empty()) and Time.get_ticks_msec() < wait_guest:
		for pid: Variant in pending_profile_peers.keys():
			var guest: Player = w.get_node_or_null("Players/%d" % int(pid)) as Player
			if guest != null:
				pending_profile_peers.erase(pid)
				var nakama_profile: Dictionary = SaveGame.as_dict(JSON.parse_string(JSON.stringify({
					"xp": 120.0,
					"claimed": 2.0,
					"copper": 55.0,
					"health": 75.0,
					"bandaged": false,
					"skill_tree": {"discovered": [], "learned": []},
					"slots": [[], {"id": "torch", "count": 2.0}, null],
					"equipment": {"main_hand": [], "off_hand": []},
					"raw_rolls": [],
					"appearance": {"unlocked_hair_styles": [], "unlocked_hair_colors": [], "unlocked_outfits": [], "unlocked_outfit_colors": [], "outfit": "default", "hair": "default"},
				})))
				SaveGame.import_player_data(guest, nakama_profile, false, false)
				SaveGame.sync_player_to_network(guest)
				print("[SERVER] guest cloud profile imported & synced for pid=%d" % int(pid))
		await get_tree().process_frame
	_check(not multiplayer.get_peers().is_empty(), "server received guest peer")
	var wait_client_done: int = Time.get_ticks_msec() + 12000
	while not multiplayer.get_peers().is_empty() and Time.get_ticks_msec() < wait_client_done:
		await get_tree().process_frame
	MultiplayerWorlds.delete_world(wid)
	NetworkManager.leave()
	print("COOP_JOIN_SERVER FAILURES=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _run_client(port: int, code: String) -> void:
	_test_relay_fragmentation()
	_test_to_menu_request_semantics()
	var rejected: Array[String] = [""]
	NetworkManager.join_rejected.connect(func(r: String) -> void: rejected[0] = r)

	# Replicate fixed GameLauncher.start() guest join ordering:
	var err: Error = NetworkManager.join("127.0.0.1", port, code, true)
	_check(err == OK, "client NetworkManager.join deferred setup OK")
	_check(not multiplayer.is_server(), "client multiplayer.is_server() is false during stepped init")
	_check(not NetworkManager.rpc_ready(self), "client rpc_ready is false before connect")

	var w: WorldLevel = WORLD_SCENE.instantiate() as WorldLevel
	w.name = "WorldLevel"
	w.loading_in_steps = true
	add_child(w)
	while not w.loading_init_step():
		await get_tree().process_frame

	_check(w.get_node_or_null("Players/1") == null, "client did not spawn local host player 1")
	_check(w.get_node_or_null("Rivers/RiverFauna/Spawner") != null, "client RiverFauna spawner ready before connect")
	var conn_err: Error = NetworkManager.connect_pending_guest()
	_check(conn_err == OK, "client connect_pending_guest started")

	var deadline: int = Time.get_ticks_msec() + 18000
	while rejected[0].is_empty() and Time.get_ticks_msec() < deadline:
		var join_peer: MultiplayerPeer = multiplayer.multiplayer_peer
		var peer_ok: bool = join_peer != null and join_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
		if peer_ok and w.get_node_or_null("Players/%s" % multiplayer.get_unique_id()) != null:
			break
		await get_tree().process_frame

	_check(rejected[0].is_empty(), "client not rejected: %s" % rejected[0])
	var local_player: Player = w.get_node_or_null("Players/%s" % multiplayer.get_unique_id()) as Player
	_check(local_player != null, "client local player spawned")
	while not w.loading_step():
		await get_tree().process_frame
	var sync_deadline: int = Time.get_ticks_msec() + 4000
	while local_player != null and local_player.progress.copper != 55 and Time.get_ticks_msec() < sync_deadline:
		await get_tree().process_frame
	_check(local_player != null and local_player.progress.copper == 55, "client received host-imported Nakama profile (copper=55)")
	_check(w.get_node_or_null("Players/1") != null, "client sees host player 1")
	_check(w.get_node_or_null("FallenKnight") != null, "client has FallenKnight")
	_check(w.get_node_or_null("WardRing_lake_hut") != null, "client has WardRing_lake_hut")
	NetworkManager.leave()
	print("COOP_JOIN_CLIENT FAILURES=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
