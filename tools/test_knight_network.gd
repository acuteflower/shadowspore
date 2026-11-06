extends Node
var _server: bool
var _done: bool = false
var _world: WorldLevel
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	_server = OS.get_cmdline_user_args().has("--server")
	var err: Error = NetworkManager.host_multiplayer(17903) if _server else NetworkManager.join("127.0.0.1",17903)
	if err != OK:
		get_tree().quit(1)
		return
	_world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(_world)
	var deadline: int = Time.get_ticks_msec()+20000
	if _server:
		while not _done and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
		print("KNIGHT NETWORK HOST: ", "PASS" if _done else "TIMEOUT")
		get_tree().quit(0 if _done else 1)
		return
	var id: String = ""
	while Time.get_ticks_msec()<deadline:
		id = str(multiplayer.get_unique_id())
		if _world._players.has_node(id): break
		await get_tree().process_frame
	var player: Player = _world._players.get_node_or_null(id) as Player
	if player == null:
		get_tree().quit(1)
		return
	player.get_node("OpeningGuide").set_process(false)
	player.position = _world.fallen_knight.position + Vector2(0,24)
	await get_tree().create_timer(0.6).timeout
	_world.fallen_knight.interact(player)
	await get_tree().create_timer(0.2).timeout
	_world.fallen_knight.interact(player)
	while not player.quests.has_flag("knight_sword_taken") and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	var count: int = 0
	for stack: Dictionary in player.inventory.slots:
		if String(stack.get("id","")) == "sword_basic": count += int(stack.count)
	var ok: bool = count == 1 and player.quests.has_flag("knight_inspected") and player.quests.has_flag("knight_sword_taken")
	print("KNIGHT NETWORK CLIENT: ", "PASS" if ok else "FAIL", " swords=",count)
	if ok: _client_done.rpc_id(1)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if ok else 1)
@rpc("any_peer", "call_remote", "reliable")
func _client_done() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id()>1: _done = true
