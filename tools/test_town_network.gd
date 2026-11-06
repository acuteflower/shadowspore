extends Node
## docs/town.md over the wire. Two processes on loopback (port 17896): the host founds the town and builds a lamp post before anyone joins; the client joins late, gets the whole town in
## the snapshot, orders a bench (the host validates and pays from the client's bag), helps it up, renames the town and tears the bench down again. Host: `-- --server`, then the client.

var _server: bool = false
var _world: WorldLevel
var _client_done: bool = false
var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TOWN NETWORK %s FAILED: %s" % ["HOST" if _server else "CLIENT", what])


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 16):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 10.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


func _run() -> void:
	_server = OS.get_cmdline_user_args().has("--server")
	var err: Error = NetworkManager.host_multiplayer(17896) if _server else NetworkManager.join("127.0.0.1", 17896)
	if err != OK:
		get_tree().quit(1)
		return
	for id: String in ["lamp_post", "bench"]:
		(TownRules.piece(id) as Dictionary)["build_seconds"] = 0.6
	_world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(_world)
	await _frames(2)
	var town: TownManager = _world.town()
	var hut: Hut = _world.hut_node()
	var deadline: int = Time.get_ticks_msec() + 60000
	if _server:
		await _host(town, hut, deadline)
	else:
		await _client(town, hut, deadline)


func _host(town: TownManager, hut: Hut, deadline: int) -> void:
	var me: Player = _world._players.get_child(0) as Player
	me.request_teleport(hut.position + Vector2(0, 120))
	await _frames(100)
	me.quests.set_flag("rebuild_done")
	await _frames(80)
	_check(town.founded, "the host founds the town")
	me.inventory.give("wood", 20)
	me.inventory.give("glow_cap", 4)
	var lamp: Vector2 = _site(town, "lamp_post", hut.position + Vector2(50, 110))
	town.request_place("lamp_post", lamp, false)
	for i: int in 300:
		await get_tree().process_frame
		if town.has_built("lamp_post"):
			break
	_check(town.has_built("lamp_post"), "the host's lamp post stands")
	print("TOWN NETWORK HOST: waiting for the client")
	var client: Player = null
	while client == null and Time.get_ticks_msec() < deadline:
		for node: Node in _world._players.get_children():
			if node.get_multiplayer_authority() != 1:
				client = node as Player
		await get_tree().process_frame
	_check(client != null, "a client joined")
	if client == null:
		get_tree().quit(1)
		return
	client.inventory.give("wood", 10)
	var seen_bench: bool = false
	var seen_built: bool = false
	var seen_gone: bool = false
	while not _client_done and Time.get_ticks_msec() < deadline:
		for id: int in town.structures:
			if String((town.structures[id] as Dictionary).p) == "bench":
				seen_bench = true
				if town.is_built(id):
					seen_built = true
		if seen_built and town.count_of("bench") == 0:
			seen_gone = true
		await get_tree().process_frame
	_check(seen_bench and seen_built, "the host saw the client's bench go up and finish (%s %s)" % [seen_bench, seen_built])
	_check(seen_gone and int(town.stock.get("wood", 0)) >= 2, "and come down again, the refund in the stock (%s)" % str(town.stock))
	_check(town.name_index == 3, "the town's new name reached the host")
	_check(client.inventory.count_item("wood") == 7, "the bench was paid from the client's bag (wood %d)" % client.inventory.count_item("wood"))
	print("TOWN NETWORK HOST: ", "PASS" if _ok and _client_done else "FAIL")
	await get_tree().create_timer(0.6).timeout
	get_tree().quit(0 if _ok and _client_done else 1)


func _client(town: TownManager, hut: Hut, deadline: int) -> void:
	var me: Player = null
	while me == null and Time.get_ticks_msec() < deadline:
		me = _world._players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		await get_tree().process_frame
	if me == null:
		get_tree().quit(1)
		return
	while not town.founded and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(town.founded and town.is_built(0) and town.has_built("lamp_post") and town.structures.size() == 2, "the snapshot brings the whole town (%d pieces)" % town.structures.size())
	_check(town.center.distance_to(hut.position) < 1.0 and town.town_name() == TownRules.town_names()[0], "centre and name")
	me.request_teleport(hut.position + Vector2(0, 120))
	await _frames(120)
	var lamp_id: int = town.built_ids("lamp_post")[0]
	_check(town.view_of(lamp_id) != null, "the lamp post's picture stands near the client")
	while me.inventory.count_item("wood") < 10 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(me.inventory.count_item("wood") == 10, "the host's gift of wood reached the client's bag")
	var site: Vector2 = _site(town, "bench", hut.position + Vector2(-40, 100))
	_check(site != Vector2.INF and town.check_place("bench", site, me) == "", "the client sees a valid site (%s)" % town.check_place("bench", site, me))
	town.request_place("bench", site, false)
	var bench_id: int = -1
	while bench_id < 0 and Time.get_ticks_msec() < deadline:
		for id: int in town.structures:
			if String((town.structures[id] as Dictionary).p) == "bench":
				bench_id = id
		await get_tree().process_frame
	_check(bench_id >= 0, "the host's answer arrives: the bench is a structure on the client")
	while bench_id >= 0 and not town.is_built(bench_id) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(bench_id >= 0 and town.is_built(bench_id), "the progress of the site reaches the client until it is finished")
	_check(me.inventory.count_item("wood") == 7, "the client's bag was charged by the host (wood %d)" % me.inventory.count_item("wood"))
	town.request_name(3)
	for i: int in 200:
		await get_tree().process_frame
		if town.name_index == 3:
			break
	_check(town.name_index == 3, "the new name comes back from the host")
	town.request_demolish(bench_id)
	for i: int in 200:
		await get_tree().process_frame
		if town.count_of("bench") == 0:
			break
	_check(town.count_of("bench") == 0 and town.view_of(bench_id) == null, "the demolition reaches the client")
	_check(int(town.stock.get("wood", 0)) >= 2, "and the refund shows in the client's stock (%s)" % str(town.stock))
	print("TOWN NETWORK CLIENT: ", "PASS" if _ok else "FAIL")
	if _ok:
		_done.rpc_id(1)
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0 if _ok else 1)


@rpc("any_peer", "call_remote", "reliable")
func _done() -> void:
	if multiplayer.is_server():
		_client_done = true
