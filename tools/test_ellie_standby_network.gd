extends Node
## Run twice with --server and --client to verify the Player's reliable RPCs.
var ready_peer: bool = false
var started_peer: bool = false
var stopped_peer: bool = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var server: bool = OS.get_cmdline_user_args().has("--server")
	var err: Error = NetworkManager._host(1, "127.0.0.1", 17931) if server else NetworkManager.join("127.0.0.1", 17931)
	if err != OK:
		push_error("Cannot create local test peer: %s" % err)
		get_tree().quit(1)
		return
	var deadline: int = Time.get_ticks_msec() + 20000
	if not server:
		while multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			push_error("Could not connect to test host")
			get_tree().quit(1)
			return
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	if server:
		while not ready_peer and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if not ready_peer:
			push_error("Client did not connect")
			get_tree().quit(1)
			return
		player._start_standby.rpc(1)
		while not started_peer and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if not started_peer:
			push_error("Client did not receive gesture")
			get_tree().quit(1)
			return
		player._cancel_standby()
		while not stopped_peer and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if stopped_peer:
			await get_tree().create_timer(0.35).timeout
		print("STANDBY NETWORK HOST: ", "PASS" if stopped_peer else "FAIL")
		get_tree().quit(0 if stopped_peer else 1)
		return
	_peer_ready.rpc_id(1)
	while player._standby_clip != 1 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if player._standby_clip != 1:
		push_error("Authority gesture was not received")
		get_tree().quit(1)
		return
	_peer_started.rpc_id(1)
	while player._standby_clip != -1 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ok: bool = player._standby_clip == -1
	if ok:
		_peer_stopped.rpc_id(1)
		await get_tree().create_timer(0.2).timeout
	print("STANDBY NETWORK CLIENT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

@rpc("any_peer", "call_remote", "reliable")
func _peer_ready() -> void:
	ready_peer = multiplayer.is_server()

@rpc("any_peer", "call_remote", "reliable")
func _peer_started() -> void:
	started_peer = multiplayer.is_server()

@rpc("any_peer", "call_remote", "reliable")
func _peer_stopped() -> void:
	stopped_peer = multiplayer.is_server()
