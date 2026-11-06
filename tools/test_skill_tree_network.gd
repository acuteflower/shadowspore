extends Node
## Isolated loopback test, no world or saves. Start host with -- --server, then client.
const PORT: int = 17913
var _host: bool = false
var _done: bool = false
var _remote_owner: int = 0
var _actors: Node
var _signals: int = 0


func _ready() -> void:
	_actors = Node.new()
	_actors.name = "Actors"
	add_child(_actors)
	_host = OS.get_cmdline_user_args().has("--server")
	_run.call_deferred()


func _make(owner_id: int) -> SkillTreeComponent:
	var actor: Node = Node.new()
	actor.name = str(owner_id)
	var component: SkillTreeComponent = SkillTreeComponent.new()
	component.name = "Skills"
	actor.add_child(component)
	actor.set_multiplayer_authority(owner_id)
	_actors.add_child(actor)
	return component


func _run() -> void:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.set_bind_ip("127.0.0.1")
	var error: Error = peer.create_server(PORT, 1) if _host else peer.create_client("127.0.0.1", PORT)
	if error != OK:
		push_error(error_string(error))
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	if _host:
		var own: SkillTreeComponent = _make(1)
		own.request_explore("combat_echo_a")
		multiplayer.peer_connected.connect(func(id: int) -> void:
			_remote_owner = id
			var remote: SkillTreeComponent = _make(id)
			# Seed a host snapshot without sending an RPC before the client node exists.
			remote._discovered.append("shadow_echo_b")
			_spawn.rpc_id(id, id))
		if OS.get_cmdline_user_args().has("--self-test"):
			OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tools/test_skill_tree_network.tscn"]))
		var deadline: int = Time.get_ticks_msec() + 15000
		while not _done and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		await get_tree().create_timer(0.2).timeout
		print("SKILL TREE NETWORK HOST: ", "PASS" if _done else "FAIL / TIMEOUT")
		get_tree().quit(0 if _done else 1)
	else:
		await get_tree().create_timer(12.0).timeout
		if not _done:
			push_error("Skill tree client timed out")
			get_tree().quit(1)


@rpc("authority", "call_remote", "reliable")
func _spawn(owner_id: int) -> void:
	_make(1)
	var own: SkillTreeComponent = _make(owner_id)
	own.explored.connect(func(_id: String) -> void: _signals += 1)
	_client_check.call_deferred(own)


func _client_check(own: SkillTreeComponent) -> void:
	var deadline: int = Time.get_ticks_msec() + 7000
	while not own.is_explored("shadow_echo_b") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var snapshot: bool = own.is_explored("shadow_echo_b") and own.is_visible("shadow_echo_c") and _signals == 0
	var other: SkillTreeComponent = _actors.get_node("1/Skills") as SkillTreeComponent
	# Try to mutate another player and a hidden descendant on our own graph.
	other._request_explore.rpc_id(1, "combat_echo_b")
	own._request_explore.rpc_id(1, "combat_echo_c")
	own.request_explore("combat_echo_a")
	while not own.is_explored("combat_echo_a") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	own.request_explore("combat_echo_a")
	await get_tree().create_timer(0.2).timeout
	var synced: bool = own.is_explored("combat_echo_a") and not own.is_explored("combat_echo_c") and _signals == 1
	_done = snapshot and synced
	print("SKILL TREE NETWORK CLIENT: snapshot=%s, confirmed reveal=%s" % [snapshot, synced])
	_client_done.rpc_id(1, snapshot and synced)
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0 if snapshot and synced else 1)


@rpc("any_peer", "call_remote", "reliable")
func _client_done(ok: bool) -> void:
	if not _host or multiplayer.get_remote_sender_id() != _remote_owner:
		return
	var own: SkillTreeComponent = _actors.get_node("1/Skills") as SkillTreeComponent
	var remote: SkillTreeComponent = _actors.get_node(str(_remote_owner) + "/Skills") as SkillTreeComponent
	_done = ok and not own.is_explored("combat_echo_b") and not remote.is_explored("combat_echo_c") and (remote.export_data().discovered as Array).size() == 2
