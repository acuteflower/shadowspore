extends Node
## Two real ENet peers, existing player replication, late map opening and disconnect cleanup.
## Host: ... tools/test_map_network.tscn -- --server ; then same command without --server.

const PORT: int = 17898
const HOST_AT: Vector2 = Vector2(140, 120)
const CLIENT_AT: Vector2 = Vector2(220, 160)
const CLIENT_MOVED: Vector2 = Vector2(280, 200)
var _ok: bool = true
var _verified: bool = false
var _world: TestLevel


func _check(condition: bool, message: String) -> void:
	if not condition:
		_ok = false
		push_error("MAP NETWORK: " + message)


func _ready() -> void:
	_run.call_deferred()


func _until(condition: Callable, seconds: float = 20.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(condition.call())


func _at(map: MapWindow, id: int, target: Vector2) -> bool:
	for marker: Dictionary in map._live_markers():
		if String(marker.id) == str(id):
			return (marker.tile as Vector2).distance_to(target / 16.0) < 0.1
	return false


@rpc("authority", "call_remote", "reliable")
func _confirm() -> void:
	_verified = true


func _run() -> void:
	var server: bool = OS.get_cmdline_user_args().has("--server")
	var error: Error = NetworkManager.host_multiplayer(PORT) if server else NetworkManager.join("127.0.0.1", PORT)
	if error != OK:
		get_tree().quit(1)
		return
	_world = load("res://src/world/test_level.tscn").instantiate() as TestLevel
	add_child(_world)
	var mine: int = multiplayer.get_unique_id()
	var ready: bool = await _until(func() -> bool: return _world._players.has_node(str(mine)))
	_check(ready, "local replicated player appears")
	if not ready:
		get_tree().quit(1)
		return
	var player: Player = _world._players.get_node(str(mine)) as Player
	var map: MapWindow = player.get_node("Hud/MapWindow") as MapWindow
	player.request_teleport(HOST_AT if server else CLIENT_AT)
	player.story_lock = true
	player.auto_walk = Vector2.INF
	if server:
		print("MAP NETWORK HOST READY")
		_check(await _until(func() -> bool: return Player.all.size() == 2), "client joins after host map exists")
		var client: int = 0
		for other: Player in Player.all:
			if other.name.to_int() != mine:
				client = other.name.to_int()
		_check(client != 0, "connected peer has a marker identity")
		_check(await _until(func() -> bool: return _at(map, client, CLIENT_AT)), "host map sees client's replicated initial position")
		_check(await _until(func() -> bool: return _at(map, client, CLIENT_MOVED)), "host map follows the moving client")
		if client != 0:
			_confirm.rpc_id(client)
		_check(await _until(func() -> bool: return map._live_markers().size() == 1), "host removes marker after client disconnect")
	else:
		_check(await _until(func() -> bool: return _at(map, 1, HOST_AT)), "late client map sees the host's current position")
		await get_tree().create_timer(0.5).timeout
		player.request_teleport(CLIENT_MOVED)
		_check(await _until(func() -> bool: return _verified), "host confirmed live marker movement")
		NetworkManager.leave()
	print("MAP NETWORK %s: %s" % ["HOST" if server else "CLIENT", "PASS" if _ok else "FAIL"])
	_world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _ok else 1)
