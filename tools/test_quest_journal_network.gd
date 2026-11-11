extends Node
## Run two instances with distinct user data directories. Add -- --server to the host.

const PORT: int = 17942
const WORLD: String = "res://src/world/world_level.tscn"
const FETCH: int = 1
const HUNT: int = 2
const EXPIRES: int = 3

var _world: WorldLevel
var _deadline: int
var _ok: bool = true
var _first_peer: int = 0
var _returning_peer: int = 0
var _verified: bool = false
var _rejoin: bool = false
var _client_done: bool = false


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_ok = false
		print("JOURNAL NETWORK FAIL: ", message)


func _wait_for(condition: Callable, message: String) -> bool:
	while not condition.call() and Time.get_ticks_msec() < _deadline:
		await get_tree().process_frame
	var passed: bool = bool(condition.call())
	_check(passed, message)
	return passed


func _run() -> void:
	_deadline = Time.get_ticks_msec() + 90000
	var host: bool = OS.get_cmdline_user_args().has("--server")
	var error: Error = NetworkManager._host(1, "127.0.0.1", PORT) if host else NetworkManager.join("127.0.0.1", PORT)
	if error != OK:
		_check(false, error_string(error))
		get_tree().quit(1)
		return
	_make_world()
	if host:
		await _host()
	else:
		await _client()


func _make_world() -> void:
	_world = load(WORLD).instantiate() as WorldLevel
	add_child(_world)


func _host() -> void:
	var town: TownManager = _world.town()
	var board: BoardManager = town.board
	_world.finish_opening()
	TimeManager.lock_at(0.42)
	TimeManager.day = 3
	town.request_found()
	var at: Vector2 = town.center + Vector2(48, 100)
	var town_save: Dictionary = town.export_state()
	town_save.structures["1"] = {"p": "quest_board", "x": at.x, "y": at.y, "g": TownManager.PROGRESS_FULL}
	town_save["next_id"] = 2
	town.import_state(town_save)
	town.add_story_resident("gustav", false)
	var spot: Vector2 = town.rect_of(1).get_center() + Vector2(0, 20)
	var me: Player = town.local_player()
	me.request_teleport(spot)
	_check(board.is_ready(), "the host fixture has a quest board")
	_check(board.debug_post("gustav_wood", "gustav") == FETCH, "the fetch is posted")
	_check(board.debug_post("valdric_spider", "valdric") == HUNT, "the hunt is posted")
	_check(board.debug_post("valdric_spider", "valdric") == EXPIRES, "the second hunt is posted")
	board.offer_of(HUNT)["e"] = TimeManager.day + 7
	board.offer_of(EXPIRES)["e"] = TimeManager.day + 1
	board.request_accept(FETCH)
	board.request_accept(HUNT)
	print("JOURNAL NETWORK READY")
	if not await _wait_for(func() -> bool: return not multiplayer.get_peers().is_empty(), "a guest connects"):
		get_tree().quit(1)
		return
	_first_peer = multiplayer.get_peers()[0]
	var owner: String = NetworkManager.guest_owner(_first_peer)
	_check(owner.begins_with("guest:"), "the connection has a durable host-side owner")
	var guest: Player = _world._players.get_node_or_null(str(_first_peer)) as Player
	if guest == null:
		get_tree().quit(1)
		return
	_move_guest.rpc_id(_first_peer, spot)
	await _wait_for(func() -> bool: return board._near_board(guest), "the guest reaches the board")
	_take_jobs.rpc_id(_first_peer)
	await _wait_for(func() -> bool: return not board.entry_of(EXPIRES, _first_peer).is_empty(), "all three guest requests are accepted")

	board.note_kill(guest, "shadow_spider")
	board.request_abandon(HUNT, 1)
	_check(board.entry_of(HUNT, 1).is_empty() and int(board.entry_of(HUNT, _first_peer).get("n", 0)) == 1, "the host can abandon a hunt without affecting the guest")
	var due: int = int(board.entry_of(EXPIRES, _first_peer).get("due", -1))
	var price: int = int(board.offer_of(FETCH).c)
	var need: int = int(board.offer_of(FETCH).n)
	var guest_coins: int = guest.progress.copper
	var host_coins: int = me.progress.copper
	guest.inventory.give("wood", need)
	me.inventory.give("wood", need)
	var gustav: Node2D = town.person_node("gustav")
	if gustav == null:
		_check(false, "Gustav is loaded")
		get_tree().quit(1)
		return
	var giver: Vector2 = gustav.global_position
	me.request_teleport(giver)
	_move_guest.rpc_id(_first_peer, giver)
	await _wait_for(func() -> bool: return board._near_giver(guest, "gustav"), "both players are at Gustav")
	_deliver.rpc_id(_first_peer)
	board.request_finish(FETCH)
	board.request_finish(FETCH)
	await _wait_for(func() -> bool: return bool(board.entry_of(FETCH, _first_peer).get("done", false)), "the guest can deliver the same posted notice")
	_check(me.progress.copper == host_coins + price and guest.progress.copper == guest_coins + price, "each player's duplicate hand-in pays once")
	_check(not JSON.stringify(board.export_state(true)).contains("guest:"), "the wire snapshot uses connection IDs only")
	_leave_once.rpc_id(_first_peer)
	await _wait_for(func() -> bool: return not multiplayer.get_peers().has(_first_peer), "the guest disconnects")

	TimeManager.day = due
	board._on_day_started(due)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(board.export_state())) as Dictionary
	_check((saved.guest_players as Dictionary).has(owner), "the saved world has the departed guest's economy")
	_check(_has_archive((saved.archive as Dictionary).get(owner, []), EXPIRES, "expired"), "the disconnected guest's deadline still expires")
	board.import_state(saved)
	_check(SaveGame.path_for(get_tree()) == SaveGame.COOP_PATH and SaveGame.save(get_tree()), "the host writes the cooperative slot")
	board.import_state({"guest_players": {}, "world": ""})
	_check(SaveGame.load_into(get_tree()) and board.world_id == String(saved.world), "the host reloads the saved world and its journal identity")
	await _wait_for(func() -> bool: return not multiplayer.get_peers().is_empty() and multiplayer.get_peers()[0] != _first_peer, "the guest reconnects with a new connection ID")
	if not multiplayer.get_peers().is_empty():
		_returning_peer = multiplayer.get_peers()[0]
		_check(NetworkManager.guest_owner(_returning_peer) == owner, "the new connection maps to the same guest")
		_check(int(board.entry_of(HUNT, _returning_peer).get("n", 0)) == 1, "the saved hunt is attached to the returning player")
		await _wait_for(func() -> bool: return _verified, "the returning client verifies its journal")
	_complete.rpc(_ok)
	print("JOURNAL NETWORK HOST: ", "PASS" if _ok else "FAIL")
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if _ok else 1)


func _client() -> void:
	if not await _wait_for(func() -> bool: return _rejoin, "the first session asks the guest to reconnect"):
		get_tree().quit(1)
		return
	NetworkManager.leave()
	_world.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	if NetworkManager.join("127.0.0.1", PORT) != OK:
		get_tree().quit(1)
		return
	_make_world()
	var town: TownManager = _world.town()
	var board: BoardManager = town.board
	await _wait_for(func() -> bool:
		var player: Player = town.local_player()
		return player != null and player.tracked.board() == board and bool(board.entry_of(FETCH, multiplayer.get_unique_id()).get("done", false)),
		"the client sees its completed fetch again")
	var me: Player = town.local_player()
	if me == null:
		get_tree().quit(1)
		return
	var peer: int = multiplayer.get_unique_id()
	var focused: Dictionary = me.tracked.focused()
	_check(String(focused.get("id", "")) == "board:2" and int(focused.get("have", 0)) == 1, "the active hunt and its focus survive reconnect")
	_check(me.tracked.journal_page == "board:2", "the last-read page survives reconnect")
	_check(_has_archive(board.archived_for(peer), FETCH, "finished") and _has_archive(board.archived_for(peer), EXPIRES, "expired"), "completion and offline expiry are both in the archive")
	await _wait_for(func() -> bool: return me.progress.copper == int(board.offer_of(FETCH).get("c", -1)), "the reward balance survives reconnect")
	var journal: QuestJournal = me._hud.get_node("QuestJournal") as QuestJournal
	journal.open()
	_check(InputManager.journal_open and not get_tree().paused, "guests can read the journal without pausing the world")
	journal.close()
	_client_verified.rpc_id(1, _ok)
	await _wait_for(func() -> bool: return _client_done, "the host confirms completion")
	print("JOURNAL NETWORK CLIENT: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


@rpc("authority", "call_remote", "reliable")
func _move_guest(at: Vector2) -> void:
	var town: TownManager = _world.town()
	if await _wait_for(func() -> bool: return town.local_player() != null and town.board.is_ready(), "the town snapshot arrives"):
		town.local_player().request_teleport(at)


@rpc("authority", "call_remote", "reliable")
func _take_jobs() -> void:
	for id: int in [FETCH, HUNT, EXPIRES]:
		_world.town().board.request_accept(id)


@rpc("authority", "call_remote", "reliable")
func _deliver() -> void:
	var board: BoardManager = _world.town().board
	board.request_finish(FETCH)
	board.request_finish(FETCH)


@rpc("authority", "call_remote", "reliable")
func _leave_once() -> void:
	var journal: TrackedQuests = _world.town().local_player().tracked
	journal.focus("board:2")
	journal.journal_page = "board:2"
	_rejoin = true


@rpc("any_peer", "call_remote", "reliable")
func _client_verified(ok: bool) -> void:
	if multiplayer.get_remote_sender_id() == _returning_peer:
		_verified = true
		_check(ok, "the client checks passed")


@rpc("authority", "call_remote", "reliable")
func _complete(ok: bool) -> void:
	_client_done = true
	_check(ok, "the host checks passed")


func _has_archive(rows: Array, id: int, status: String) -> bool:
	for row: Dictionary in rows:
		if int(row.oid) == id and String(row.status) == status:
			return true
	return false
