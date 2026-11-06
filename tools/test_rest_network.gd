extends Node
var _server: bool
var _world: WorldLevel
var _observed_sitting: bool = false
var _observed_gesture: bool = false
var _done: bool = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_server = OS.get_cmdline_user_args().has("--server")
	var err: Error = NetworkManager._host(1, "127.0.0.1", 17919) if _server else NetworkManager.join("127.0.0.1", 17919)
	if err != OK:
		get_tree().quit(1)
		return
	_world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(_world)
	var deadline: int = Time.get_ticks_msec() + 45000
	if _server:
		while not _done and Time.get_ticks_msec() < deadline:
			for node: Node in _world._players.get_children():
				var rest: RestComponent = node.get_node("RestComponent") as RestComponent
				if node.get_multiplayer_authority() != 1 and rest.state == RestComponent.State.IDLE:
					_observed_sitting = true
				if node.get_multiplayer_authority() != 1 and rest.state in RestComponent.GESTURE_STATES:
					_observed_gesture = true
			await get_tree().process_frame
		await get_tree().create_timer(0.6).timeout
		print("REST NETWORK HOST: ", "PASS" if _done and _observed_sitting and _observed_gesture else "FAIL")
		get_tree().quit(0 if _done and _observed_sitting and _observed_gesture else 1)
		return
	var player: Player
	while Time.get_ticks_msec() < deadline:
		player = _world._players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		if player != null: break
		await get_tree().process_frame
	if player == null:
		get_tree().quit(1)
		return
	player.get_node("OpeningGuide").set_process(false)
	player.quests.set_flag("fire_seated")
	var spot: CampfireSeat = _world._hut().get_node("Seat_east") as CampfireSeat
	var rest: RestComponent = player.get_node("RestComponent") as RestComponent
	player.request_teleport(spot.approach_position())
	await get_tree().create_timer(0.5).timeout
	print("REST CLIENT REQUEST: ", spot.prompt(), " position=", player.global_position, " lock=", player.story_lock)
	spot.interact(player)
	while is_instance_valid(rest) and rest.state != RestComponent.State.IDLE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(rest):
		get_tree().quit(1)
		return
	var ok: bool = rest.state == RestComponent.State.IDLE and player.story_lock and player.fainting
	while is_instance_valid(rest) and rest.state not in RestComponent.GESTURE_STATES and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	ok = ok and is_instance_valid(rest) and rest.state in RestComponent.GESTURE_STATES
	rest._request_snapshot.rpc_id(1)
	await get_tree().create_timer(0.2).timeout
	ok = ok and rest.state in RestComponent.GESTURE_STATES
	rest.request_stand()
	while rest.state != RestComponent.State.FREE and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	ok = ok and rest.state == RestComponent.State.FREE and not player.story_lock and not player.fainting
	print("REST NETWORK CLIENT: ", "PASS" if ok else "FAIL")
	if ok: _client_done.rpc_id(1)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if ok else 1)

@rpc("any_peer", "call_remote", "reliable")
func _client_done() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() > 1:
		var player: Player = _world._players.get_node(str(multiplayer.get_remote_sender_id())) as Player
		_done = (player.get_node("RestComponent") as RestComponent).state == RestComponent.State.FREE
