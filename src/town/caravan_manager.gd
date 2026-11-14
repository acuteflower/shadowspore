class_name CaravanManager
extends Node2D
## The travelling merchant's caravan in the town (docs/haendler_konzept.md, step 1). A child `Caravan` of `TownManager` on every peer.
## What is pure (`CaravanRules`): the calendar, the phase, where it drives, the offer of a visit. What the host decides and saves (town state key `caravan`):
## `first_day` (set once the fountain square stands), the record of the running visit {i, a, l, slot, lv, sold {item: n}, took {item: n}} and a developer
## override `force`. Joiners get it with the town's snapshot; a purchase or sale sends the counters again (`_rpc_counts`).
## The figures: `CaravanView` (the wagon and its ox, placeholder drawing until the art exists) and `CaravanMerchant` (Jorun, E: ANSPRECHEN / HANDELN).

signal stock_changed ## the counters of the running visit changed (the shop window refreshes)
signal phase_changed(state: String)

const FORCE_BASE: int = 100000 ## developer visits count from here (their offer is drawn like any other)

var town: TownManager
var first_day: int = -1
var visit: Dictionary = {} ## the running visit (see the header); {} while the caravan is away
var force: Dictionary = {} ## a developer visit {i, a, l} that replaces the calendar until it is over
var phase: Dictionary = {"state": "away", "k": 0.0, "t": 0.0}
var view: CaravanView
var merchant: CaravanMerchant
var _forced_count: int = 0
var skip_until: float = -1.0 ## calendar visits that began to come before this epoch are skipped (a developer visit took their place)
var _offer_key: String = ""
var _offer: Dictionary = {}
var _route: PackedVector2Array = PackedVector2Array()
var _route_key: String = ""
var _storm_clock: float = 0.0
var _storm: bool = false
var _tick: float = 0.0


func setup(owner_town: TownManager) -> void:
	town = owner_town
	name = "Caravan"
	y_sort_enabled = true
	view = CaravanView.new()
	view.name = "Wagon"
	add_child(view)
	view.setup(self)
	merchant = CaravanMerchant.new()
	merchant.name = "Jorun"
	add_child(merchant)
	merchant.setup(self)


static func of(tree: SceneTree) -> CaravanManager:
	var t: TownManager = tree.get_first_node_in_group("town") as TownManager
	return t.caravan if t != null else null


func cfg() -> Dictionary:
	return CaravanRules.cfg()


func world_seed() -> int:
	return Moisture.world_seed


func now() -> float:
	return CaravanRules.epoch(TimeManager.day, TimeManager.time_of_day)


func merchant_id() -> String:
	return String(cfg().get("merchant", "jorun"))


func shop_id() -> String:
	return String(cfg().get("shop", "caravan"))


func state() -> String:
	return String(phase.state)


func is_open() -> bool:
	return state() == "open"


# ---------- every frame ----------

func _process(delta: float) -> void:
	if town == null:
		return
	_tick += delta
	var e: float = now()
	if multiplayer.is_server():
		_host_step(e)
	_storm_clock -= delta
	if _storm_clock <= 0.0:
		_storm_clock = 1.0
		_storm = CaravanRules.storm_at(world_seed(), e)
	var was: String = state()
	phase = CaravanRules.phase(visit, e, _storm) if not visit.is_empty() and plaza_ok() else {"state": "away", "k": 0.0, "t": 0.0}
	if state() != was:
		_on_state(was, state())
	view.follow()
	merchant.follow()


## Host: set the first visit once the square stands, start the record of a visit when its window opens, drop it when it has driven off.
func _host_step(e: float) -> void:
	if first_day < 0 and town.founded and town.has_heart() and (town.world == null or town.world.opening_over):
		first_day = TimeManager.day + int(cfg().get("first_delay", 1))
		_send_state()
	var v: Dictionary = current(e)
	if v.is_empty():
		if not visit.is_empty():
			visit = {}
			_send_state()
		return
	if visit.is_empty() or int(visit.i) != int(v.i):
		var line: PackedVector2Array = road()
		var slot: int = CaravanRules.pick_slot(plaza(), _solids(), line[0] if not line.is_empty() else Vector2.INF)
		visit = {"i": int(v.i), "a": float(v.a), "l": float(v.l), "slot": slot, "lv": town.level(), "sold": {}, "took": {}}
		_send_state()


## The visit of the calendar (or the developer's) whose window holds `e`.
func current(e: float) -> Dictionary:
	if not force.is_empty():
		if e < CaravanRules.window(force).y:
			return force
		skip_until = maxf(skip_until, CaravanRules.window(force).y)
		force = {}
	var v: Dictionary = CaravanRules.visit_at(world_seed(), first_day, e)
	if not v.is_empty() and CaravanRules.window(v).x < skip_until:
		return {} ## overlapped by a developer visit: this one does not come
	return v


func _on_state(was: String, to: String) -> void:
	phase_changed.emit(to)
	_route_key = ""
	if CaravanRules.parked(to):
		town.register_outpost("caravan", merchant_point())
	else:
		town.clear_outpost("caravan")
	if to == "open" and was in ["setup", "coming", "away"]:
		town.event.emit("caravan_arrived", {}) ## every peer sees the change itself
		if town.local_player() != null and town.local_player().global_position.distance_to(stall()) < 600.0:
			town.town_banner({"header": "AUF DEM %s" % String(TownRules.piece("plaza").get("name", "PLATZ")), "title": "DIE KARAWANE IST DA",
				"sub": String(town.settler_spec(merchant_id()).get("name", "")) if town.has_met(merchant_id()) else "EIN FREMDER HÄNDLER", "sound": "level_bells"})
	if to == "teardown":
		town.event.emit("caravan_leaving", {})
	stock_changed.emit()


# ---------- where ----------

## The fountain square's feet (the caravan stands round it); Vector2.INF without one.
func plaza() -> Vector2:
	var ids: Array[int] = town.built_ids("plaza")
	return town.position_of(ids[0]) if not ids.is_empty() else Vector2.INF


func plaza_ok() -> bool:
	return plaza() != Vector2.INF


func slot_spec() -> Dictionary:
	return CaravanRules.slot(int(visit.get("slot", -1)))


## Where the wagon stands (the feet of its middle): on its slot, or, with the square built in, at the square's west edge outside.
func stall() -> Vector2:
	var p: Vector2 = plaza()
	if p == Vector2.INF:
		return town.heart()
	var spec: Dictionary = slot_spec()
	if spec.is_empty():
		return p + Vector2(-140.0, 30.0)
	var at: Array = spec.get("at", [0, 0]) as Array
	return p + Vector2(float(at[0]), float(at[1]))


## Which way the stall opens towards the fountain: +1 east, -1 west.
func side() -> int:
	return int(slot_spec().get("side", -1))


## Where Jorun stands while the stall is open: at the inner end of the counter.
func merchant_point() -> Vector2:
	return stall() + Vector2(-float(side()) * 50.0, 8.0)


## Where customers stand: the middle of the strip in front of the counter.
func customer_point() -> Vector2:
	return stall() + Vector2(0.0, 24.0)


## May the settlers walk over to the stall (spot `of: "caravan"`)? From the moment it unfolds until it has driven off, so a settler already there is never
## yanked away in the middle of a break.
func visitable() -> bool:
	return not visit.is_empty() and state() in ["setup", "open", "storm", "teardown", "going"]


## The wagon's footprint while it stands ({} while it drives).
func footprint() -> Rect2:
	if not CaravanRules.present(state()):
		return Rect2()
	var spec: Dictionary = slot_spec()
	if spec.is_empty():
		return Rect2(stall() - Vector2(32.0, 22.0), Vector2(64.0, 22.0))
	return CaravanRules.slot_rect(plaza(), spec)


## The baked cart road (data/ground.json path `road`, world px, from the town end out into the distance), smoothed like the baker draws it.
static func road() -> PackedVector2Array:
	return CaravanRules.road(String(CaravanRules.cfg().get("road", "caravan_road")))


## Where the caravan comes from and goes to: the far end of the cart road (without one: a point west of the square).
func far_point() -> Vector2:
	var line: PackedVector2Array = road()
	if line.size() >= 2:
		return line[line.size() - 1]
	return town.heart() + Vector2(-float(cfg().get("come_from", 340.0)), 36.0)


## The way in (reversed for going): down the cart road to its town end, then a town walk round the pieces to the stall (a straight line where none is found).
func route() -> PackedVector2Array:
	var key: String = "%s>%s" % [far_point().round(), stall().round()]
	if key != _route_key:
		_route_key = key
		_route = PackedVector2Array()
		var line: PackedVector2Array = road()
		var town_end: Vector2 = far_point()
		for k: int in range(line.size() - 1, -1, -1):
			_route.append(line[k])
		if not line.is_empty():
			town_end = line[0]
		var last: PackedVector2Array = town.walk_route(town_end, stall()) if town.world != null else PackedVector2Array()
		if last.size() < 2:
			last = PackedVector2Array([town_end, stall()])
		if _route.is_empty():
			_route.append(town_end)
		for k: int in range(1 if _route[_route.size() - 1].distance_to(last[0]) < 1.0 else 0, last.size()):
			_route.append(last[k])
		if _route[_route.size() - 1].distance_to(stall()) > 0.5: ## the walk ends on a free spot near the stall: the last step goes onto the slot itself
			_route.append(stall())
	return _route


## The wagon's feet and its heading now: {pos, dir}.
func wagon_pose() -> Dictionary:
	var s: String = state()
	if s == "coming" or s == "going":
		var line: PackedVector2Array = route()
		var length: float = Settler._length(line)
		var k: float = float(phase.k)
		var d: float = (k if s == "coming" else 1.0 - k) * length
		var pos: Vector2 = Settler._along(line, d)
		var ahead: Vector2 = Settler._along(line, d + 6.0) - Settler._along(line, d - 6.0)
		if s == "going":
			ahead = -ahead
		return {"pos": pos, "dir": ahead.normalized() if ahead.length() > 0.01 else Vector2.RIGHT}
	return {"pos": stall(), "dir": Vector2(float(side()), 0.0)}


func _solids() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for id: int in town.structures:
		if not bool(TownRules.piece(String((town.structures[id] as Dictionary).p)).get("walk", false)):
			out.append(town.rect_of(id))
	var p: Vector2 = plaza()
	if p != Vector2.INF: ## the fountain itself
		var solid: Array = ((TownRules.piece("plaza").get("stand", {}) as Dictionary).get("solid", [40, 14])) as Array
		out.append(Rect2(p.x - float(solid[0]) / 2.0, p.y - float(solid[1]), float(solid[0]), float(solid[1])))
	return out


## The build check: no foundation where the caravan stands ("" = fine).
func blocks(rect: Rect2) -> String:
	var foot: Rect2 = footprint()
	if foot.has_area() and (foot.intersects(rect) or _front().intersects(rect)):
		return "DIE KARAWANE STEHT HIER"
	return ""


func _front() -> Rect2:
	var spec: Dictionary = slot_spec()
	return CaravanRules.front_rect(plaza(), spec) if not spec.is_empty() else Rect2()


# ---------- the offer ----------

## The rows of the running visit (cached per visit).
func offer() -> Dictionary:
	if visit.is_empty():
		var none_buy: Array[Dictionary] = []
		var none_sell: Array[Dictionary] = []
		return {"buy": none_buy, "sell": none_sell}
	var key: String = "%d:%d" % [int(visit.i), int(visit.get("lv", 0))]
	if key != _offer_key:
		_offer_key = key
		_offer = CaravanRules.offer(world_seed(), int(visit.i), int(visit.get("lv", 0)))
	return _offer


func _list(mode: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Variant in offer().get(mode, []) as Array:
		out.append(row as Dictionary)
	return out


func _row(mode: String, item: String) -> Dictionary:
	for row: Dictionary in _list(mode):
		if String(row.item) == item:
			return row
	return {}


## How many of a WAREN row are left this visit.
func left(item: String) -> int:
	var row: Dictionary = _row("buy", item)
	return maxi(int(row.get("stock", 0)) - int((visit.get("sold", {}) as Dictionary).get(item, 0)), 0) if not row.is_empty() else 0


## How many of a row he has already bought this visit.
func taken(item: String) -> int:
	return int((visit.get("took", {}) as Dictionary).get(item, 0))


func price_buy(item: String) -> int:
	var row: Dictionary = _row("buy", item)
	return CaravanRules.buy_price(int(row.get("price", 0)), town.trust_of(merchant_id())) if not row.is_empty() else 0


func price_sell(item: String) -> int:
	var row: Dictionary = _row("sell", item)
	return CaravanRules.sell_price(row, taken(item)) if not row.is_empty() else 0


## The shop window's rows for WAREN ("buy") or ANKAUF ("sell"), with what stops each one.
func rows(mode: String, player: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var trust: int = town.trust_of(merchant_id())
	for row: Dictionary in _list(mode):
		var item: String = String(row.item)
		if mode == "buy":
			var price: int = price_buy(item)
			var rest: int = left(item)
			var locked: bool = trust < int(row.get("trust", 0))
			var poor: bool = player.progress.copper < price
			var why: String = "VERTRAUEN %d NÖTIG" % int(row.trust) if locked else ("AUSVERKAUFT" if rest <= 0 else ("ZU WENIG GELD" if poor else ""))
			var sub: String = "VERTRAUEN %d" % int(row.trust) if locked else ("AUSVERKAUFT" if rest <= 0 else "NOCH %d" % rest)
			if String(row.group) == "curio":
				sub = "KURIOSITÄT · " + sub
			out.append({"kind": "buy", "item": item, "count": maxi(rest, 1), "sub": sub, "coins": price, "poor": poor, "price": price, "left": rest,
				"curio": String(row.group) == "curio", "state": BoardWindow.LOCKED if locked else (BoardWindow.OK if why == "" else BoardWindow.MISSING), "why": why})
		else:
			var have: int = player.inventory.count_plain(item)
			var price: int = price_sell(item)
			var wanted_left: int = int(row.limit) - taken(item) if bool(row.wanted) else 0
			var sub: String = ("GESUCHT · NIMMT NOCH %d" % wanted_left) if bool(row.wanted) and wanted_left > 0 else ("IM RUCKSACK" if have > 0 else "DU HAST KEINS")
			out.append({"kind": "sell", "item": item, "count": have, "sub": sub, "coins": price, "price": price, "wanted": bool(row.wanted) and wanted_left > 0,
				"state": BoardWindow.OK if have > 0 else BoardWindow.MISSING, "why": "DU HAST KEIN %s" % _item_name(item)})
	if mode == "sell": ## what she carries first, the wanted ones on top
		var with_bag: Array[Dictionary] = []
		for row: Dictionary in out:
			if bool(row.wanted):
				with_bag.append(row)
		for row: Dictionary in out:
			if not bool(row.wanted) and int(row.count) > 0:
				with_bag.append(row)
		for row: Dictionary in out:
			if not bool(row.wanted) and int(row.count) <= 0:
				with_bag.append(row)
		out = with_bag
	return out


static func _item_name(item: String) -> String:
	return String(DataRegistry.get_entry("items", item).get("name", item)).to_upper()


# ---------- trade (host decides) ----------

func request_trade(mode: String, item: String, amount: int) -> void:
	if multiplayer.is_server():
		_host_trade(mode, item, amount, multiplayer.get_unique_id())
	else:
		_rpc_trade.rpc_id(1, mode, item, amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_trade(mode: String, item: String, amount: int) -> void:
	if multiplayer.is_server():
		_host_trade(mode, item, amount, multiplayer.get_remote_sender_id())


## The reason a trade is refused right now ("" = it may go on). Shared by the host's check and the tests.
func trade_block(player: Player) -> String:
	if visit.is_empty() or not CaravanRules.present(state()):
		return "DIE KARAWANE IST NICHT DA"
	if state() == "storm":
		return "GESCHLOSSEN · STURM"
	if state() != "open":
		return "DER STAND IST ZU"
	var shop: Dictionary = town.shop(shop_id())
	if player.global_position.distance_to(merchant_point()) > float(shop.get("reach", 150.0)):
		return "ZU WEIT WEG"
	return ""


func _host_trade(mode: String, item: String, amount: int, peer: int) -> void:
	var player: Player = town.player_of(peer)
	if player == null or mode not in ["buy", "sell"] or amount < 1 or amount > 99:
		return
	var why: String = trade_block(player)
	if why != "":
		town._tell(peer, why, false)
		return
	var row: Dictionary = _row(mode, item)
	if row.is_empty():
		return
	var name_text: String = _item_name(item)
	if mode == "buy":
		if town.trust_of(merchant_id()) < int(row.get("trust", 0)):
			town._tell(peer, "%s TRAUT DIR NOCH NICHT" % String(town.settler_spec(merchant_id()).get("name", "ER")), false)
			return
		var price: int = price_buy(item)
		var wanted: int = mini(mini(amount, left(item)), player.progress.copper / maxi(price, 1))
		if left(item) <= 0:
			town._tell(peer, "AUSVERKAUFT", false)
			return
		if wanted <= 0:
			town._tell(peer, "ZU WENIG GELD", false)
			return
		var rest: int = player.inventory.give(item, wanted)
		var got: int = wanted - rest
		if got <= 0:
			town._tell(peer, "KEIN PLATZ IM RUCKSACK", false)
			return
		player.progress.award(-price * got, 0)
		var sold: Dictionary = visit.sold as Dictionary
		sold[item] = int(sold.get(item, 0)) + got
		town._tell(peer, "%d X %s GEKAUFT" % [got, name_text], true)
	else:
		var count: int = mini(amount, player.inventory.count_plain(item))
		if count <= 0:
			town._tell(peer, "DU HAST KEIN %s" % name_text, false)
			return
		var pay: int = 0
		for n: int in count: ## the wanted price until its limit, then the plain one
			pay += CaravanRules.sell_price(row, taken(item) + n)
		player.inventory.remove_item(item, count)
		player.progress.award(pay, 0)
		var took: Dictionary = visit.took as Dictionary
		took[item] = int(took.get(item, 0)) + count
		town._tell(peer, "%d X %s VERKAUFT" % [count, name_text], true)
	_rpc_counts.rpc(int(visit.i), (visit.sold as Dictionary).duplicate(), (visit.took as Dictionary).duplicate())


@rpc("authority", "call_local", "reliable")
func _rpc_counts(i: int, sold: Dictionary, took: Dictionary) -> void:
	if visit.is_empty() or int(visit.i) != i:
		return
	visit.sold = sold
	visit.took = took
	stock_changed.emit()


# ---------- state ----------

func _send_state() -> void:
	if is_inside_tree() and multiplayer.has_multiplayer_peer():
		_rpc_state.rpc(export_state())
	else:
		stock_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_state(data: Dictionary) -> void:
	import_state(data)


func export_state() -> Dictionary:
	return {"first": first_day, "visit": visit.duplicate(true), "force": force.duplicate(), "forced": _forced_count, "skip": skip_until}


func import_state(data: Dictionary) -> void:
	first_day = int(data.get("first", -1))
	var v: Dictionary = data.get("visit", {}) as Dictionary
	visit = {}
	if not v.is_empty():
		var sold: Dictionary = {}
		for item: String in v.get("sold", {}) as Dictionary:
			sold[item] = int((v.sold as Dictionary)[item])
		var took: Dictionary = {}
		for item: String in v.get("took", {}) as Dictionary:
			took[item] = int((v.took as Dictionary)[item])
		visit = {"i": int(v.get("i", 0)), "a": float(v.get("a", 0.0)), "l": float(v.get("l", 0.0)), "slot": int(v.get("slot", -1)), "lv": int(v.get("lv", 0)), "sold": sold, "took": took}
	var f: Dictionary = data.get("force", {}) as Dictionary
	force = {"i": int(f.i), "a": float(f.a), "l": float(f.l)} if f.has("i") else {}
	_forced_count = int(data.get("forced", 0))
	skip_until = float(data.get("skip", -1.0))
	_offer_key = ""
	_route_key = ""
	stock_changed.emit()


# ---------- developer ----------

## Host: the caravan comes now (a visit of `stay` days; it drives in at once) or, with `leave`, packs up now.
func debug_come(stay: int = 1) -> void:
	if not multiplayer.is_server():
		return
	var e: float = now()
	var drive: float = CaravanRules.days(float(cfg().get("drive_seconds", 26.0)))
	var leave_e: float = CaravanRules.epoch(TimeManager.day + stay, float(cfg().get("leave", 0.62)))
	_forced_count += 1
	force = {"i": FORCE_BASE + _forced_count, "a": e + drive, "l": maxf(leave_e, e + drive + 0.2)}
	if first_day < 0:
		first_day = TimeManager.day + 1
	_send_state()


func debug_leave() -> void:
	if not multiplayer.is_server() or visit.is_empty():
		return
	var e: float = now()
	var setup: float = CaravanRules.days(float(cfg().get("setup_seconds", 14.0)))
	var v: Dictionary = {"i": int(visit.i), "a": minf(float(visit.a), e - setup - 0.001), "l": e}
	force = v
	visit.a = v.a
	visit.l = v.l
	_send_state()


## Host: the next calendar visit (`first_day` kept); for the STADT tab and tests.
func next_arrival_days() -> Vector2i:
	var v: Dictionary = CaravanRules.next_visit(world_seed(), first_day, now())
	if v.is_empty():
		return Vector2i(-1, -1)
	var days_left: int = maxi(int(floorf(float(v.a))) - TimeManager.day, 0)
	return Vector2i(days_left, int(v.get("stay", 1)))
