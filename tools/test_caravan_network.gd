extends Node
## The travelling merchant's caravan over the wire (docs/haendler_konzept.md 11, step 5). Two processes on loopback (port 17905): the host founds the town,
## builds the fountain square and calls the caravan in before anyone joins; the client joins late while the stall is open, gets the visit with the town's
## snapshot (same slot, same stall, same goods, stall open on its side too), buys and sells through the host (stock and wanted counters come back to
## both), and then sees the caravan pack up and drive off when the host sends it away. Drive, setup and teardown are shortened for the test.
## Host: `-- --server`, then the client without it. Both print `CARAVAN NETWORK ... PASS`.

const PORT: int = 17905
var _server: bool = false
var _world: WorldLevel
var _client_traded: bool = false
var _client_done: bool = false
var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("CARAVAN NETWORK %s FAILED: %s" % ["HOST" if _server else "CLIENT", what])


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 24):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 10.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


func _run() -> void:
	_server = OS.get_cmdline_user_args().has("--server")
	var err: Error = NetworkManager.host_multiplayer(PORT) if _server else NetworkManager.join("127.0.0.1", PORT)
	if err != OK:
		get_tree().quit(1)
		return
	(TownRules.piece("plaza") as Dictionary)["build_seconds"] = 0.6
	var cfg: Dictionary = CaravanRules.cfg()
	cfg["drive_seconds"] = 6.0
	cfg["setup_seconds"] = 2.0
	cfg["teardown_seconds"] = 2.0
	CaravanRules.set_storm_override(func(_e: float) -> bool: return false)
	_world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(_world)
	await _frames(2)
	var town: TownManager = _world.town()
	var hut: Hut = _world.hut_node()
	var deadline: int = Time.get_ticks_msec() + 120000
	if _server:
		await _host(town, hut, deadline)
	else:
		await _client(town, deadline)


func _wait_state(caravan: CaravanManager, want: String, deadline: int) -> bool:
	while caravan.state() != want and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return caravan.state() == want


func _host(town: TownManager, hut: Hut, deadline: int) -> void:
	var me: Player = _world._players.get_child(0) as Player
	me.request_teleport(hut.position + Vector2(0, 120))
	await _frames(100)
	me.quests.set_flag("rebuild_done")
	await _frames(80)
	_check(town.founded, "the host founds the town")
	me.inventory.give("stone", 12)
	me.inventory.give("wood", 4)
	var square: Vector2 = _site(town, "plaza", hut.position + Vector2(0, 150))
	_check(square != Vector2.INF, "a place for the fountain square")
	town.request_place("plaza", square, false)
	for i: int in 400:
		await get_tree().process_frame
		if town.has_heart():
			break
	_check(town.has_heart(), "the fountain square stands")
	TimeManager.unlock() ## a fresh world holds the clock still for the opening: the caravan's phases need it running
	TimeManager.set_time(0.40)
	await _frames(10)
	var caravan: CaravanManager = town.caravan
	caravan.debug_come(1)
	_check(await _wait_state(caravan, "open", deadline), "the caravan drives in and opens (%s)" % caravan.state())
	print("CARAVAN NETWORK HOST: open, waiting for the client")
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
	client.progress.award(5000, 0) ## money and a wanted item for the client's trades
	var want: Dictionary = {}
	for row: Dictionary in caravan._list("sell"):
		if bool(row.wanted):
			want = row
			break
	client.inventory.give(String(want.item), 3)
	_ready_to_trade.rpc_id(client.get_multiplayer_authority())
	while not _client_traded and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var sold_total: int = 0
	for item: String in caravan.visit.sold as Dictionary:
		sold_total += int((caravan.visit.sold as Dictionary)[item])
	_check(sold_total == 1, "the host recorded the client's purchase (%s)" % str(caravan.visit.sold))
	_check(caravan.taken(String(want.item)) == 3, "and the three wanted pieces he bought from the client (%d)" % caravan.taken(String(want.item)))
	caravan.debug_leave()
	_check(await _wait_state(caravan, "away", deadline), "the host's caravan drives off (%s)" % caravan.state())
	while not _client_done and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	print("CARAVAN NETWORK HOST: ", "PASS" if _ok and _client_done else "FAIL")
	await get_tree().create_timer(0.6).timeout
	get_tree().quit(0 if _ok and _client_done else 1)


var _may_trade: bool = false


@rpc("authority", "call_remote", "reliable")
func _ready_to_trade() -> void:
	_may_trade = true


func _client(town: TownManager, deadline: int) -> void:
	var me: Player = null
	while me == null and Time.get_ticks_msec() < deadline:
		me = _world._players.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		await get_tree().process_frame
	if me == null:
		get_tree().quit(1)
		return
	var caravan: CaravanManager = town.caravan
	while (caravan.visit.is_empty() or not town.has_heart()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not caravan.visit.is_empty() and int(caravan.visit.i) >= CaravanManager.FORCE_BASE, "the snapshot brings the running visit (%s)" % str(caravan.visit))
	await _frames(30)
	## the host's clock reaches a joiner within a sync (2 s): until then the visit may still look far away
	_check(await _wait_state(caravan, "open", Time.get_ticks_msec() + 6000), "the stall is open on the client too (%s)" % caravan.state())
	_check(caravan.view.visible and caravan.view.global_position.distance_to(caravan.stall()) < 1.0, "the wagon stands on its slot on the client")
	_check(caravan.plaza().distance_to(caravan.stall()) < 110.0, "the slot is on the square")
	_check(caravan._list("buy").size() >= 7, "the client draws the same offer (%d rows)" % caravan._list("buy").size())
	me.request_teleport(caravan.merchant_point() + Vector2(0, 22))
	while not _may_trade and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await _frames(30)
	_check(me.global_position.distance_to(caravan.merchant_point()) < 60.0, "the client stands at the counter")
	## buy one piece of a plain row
	var row: Dictionary = {}
	for r: Dictionary in caravan._list("buy"):
		if int(r.trust) == 0 and String(r.group) != "curio":
			row = r
			break
	var item: String = String(row.item)
	var before_left: int = caravan.left(item)
	var copper: int = me.progress.copper
	var had: int = me.inventory.count_item(item)
	var price: int = caravan.price_buy(item)
	caravan.request_trade("buy", item, 1)
	for i: int in 300:
		await get_tree().process_frame
		if caravan.left(item) == before_left - 1 and me.inventory.count_item(item) == had + 1:
			break
	_check(caravan.left(item) == before_left - 1, "the host's stock counter comes back to the client (%d -> %d)" % [before_left, caravan.left(item)])
	_check(me.inventory.count_item(item) == had + 1 and me.progress.copper == copper - price, "the piece is in the client's bag and paid (%d copper)" % (copper - me.progress.copper))
	## sell the three wanted pieces
	var want: Dictionary = {}
	for r: Dictionary in caravan._list("sell"):
		if bool(r.wanted):
			want = r
			break
	copper = me.progress.copper
	var expected: int = 0
	for n: int in 3:
		expected += CaravanRules.sell_price(want, n)
	caravan.request_trade("sell", String(want.item), 3)
	for i: int in 300:
		await get_tree().process_frame
		if caravan.taken(String(want.item)) == 3:
			break
	await _frames(20)
	_check(caravan.taken(String(want.item)) == 3 and me.progress.copper == copper + expected, "selling into a wanted row pays the wanted price (%d vs %d)" % [me.progress.copper - copper, expected])
	_traded.rpc_id(1)
	_check(await _wait_state(caravan, "teardown", deadline), "the client sees the stall taken down (%s)" % caravan.state())
	_check(await _wait_state(caravan, "away", deadline), "and the caravan drive off (%s)" % caravan.state())
	await _frames(30)
	_check(caravan.visit.is_empty() and not caravan.view.visible, "the visit is over on the client too")
	print("CARAVAN NETWORK CLIENT: ", "PASS" if _ok else "FAIL")
	if _ok:
		_done.rpc_id(1)
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0 if _ok else 1)


@rpc("any_peer", "call_remote", "reliable")
func _traded() -> void:
	if multiplayer.is_server():
		_client_traded = true


@rpc("any_peer", "call_remote", "reliable")
func _done() -> void:
	if multiplayer.is_server():
		_client_done = true
