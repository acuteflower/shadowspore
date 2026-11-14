extends Node
## The travelling merchant's caravan, step 1 (docs/haendler_konzept.md): the pure calendar, phases, offer and stand choice (`CaravanRules`), then in the real
## world after FERTIGE STADT: the first visit is set, a developer visit drives in, unfolds, trades (buy, stock, wanted, reach, night), blocks building,
## survives save/load, closes at night and drives off. Run with `--fixed-fps 60`; prints `CARAVAN OK`.

var _ok: bool = true
var _count: int = 0


func _check(cond: bool, what: String) -> void:
	_count += 1
	if not cond:
		_ok = false
		print("CARAVAN FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_rules()
	await _world()
	print("CARAVAN: %d checks, %s" % [_count, "CARAVAN OK" if _ok else "FAILED"])
	get_tree().quit(0 if _ok else 1)


# ---------- pure ----------

func _rules() -> void:
	var cfg: Dictionary = CaravanRules.cfg()
	_check(not cfg.is_empty(), "data/caravan.json is loaded")
	CaravanRules.set_storm_override(func(_e: float) -> bool: return false)
	var seed_a: int = 4
	var list: Array[Dictionary] = CaravanRules.visits(seed_a, 10, 80.0)
	var again: Array[Dictionary] = CaravanRules.visits(seed_a, 10, 80.0)
	_check(list.size() >= 8, "a calendar of many visits (%d)" % list.size())
	_check(str(list) == str(again), "the calendar is the same every time")
	_check(is_equal_approx(float(list[0].a), CaravanRules.epoch(10, float(cfg.arrive))), "the first visit arrives on the first day at the arrival time")
	var other: Array[Dictionary] = CaravanRules.visits(seed_a + 1, 10, 80.0)
	_check(str(list) != str(other), "another world has another calendar")
	for k: int in range(1, list.size()):
		var gap: int = int(floorf(float(list[k].a))) - int(floorf(float(list[k - 1].l)))
		_check(gap >= 2 and gap <= 5, "the gap between visits is 2..5 days (%d)" % gap)
		_check(int(list[k].stay) >= 1 and int(list[k].stay) <= 2, "a stay is 1 or 2 days")
	## a storm on the first arrival moves it on by a day
	var storm_day: int = 10
	CaravanRules.set_storm_override(func(e: float) -> bool: return int(floorf(e)) == storm_day)
	var shifted: Array[Dictionary] = CaravanRules.visits(seed_a, 10, 30.0)
	_check(int(floorf(float(shifted[0].a))) == 11 and int(shifted[0].shift) == 1, "an arrival into a storm comes a day later")
	CaravanRules.set_storm_override(func(_e: float) -> bool: return false)
	## phases
	var v: Dictionary = list[0]
	var a: float = float(v.a)
	var l: float = float(v.l)
	var drive: float = CaravanRules.days(float(cfg.drive_seconds))
	var setup: float = CaravanRules.days(float(cfg.setup_seconds))
	var tear: float = CaravanRules.days(float(cfg.teardown_seconds))
	_check(String(CaravanRules.phase(v, a - drive - 0.01).state) == "away", "away before it sets off")
	_check(String(CaravanRules.phase(v, a - drive * 0.5).state) == "coming", "coming while it drives in")
	_check(String(CaravanRules.phase(v, a + setup * 0.5).state) == "setup", "setup right after the arrival")
	var noon: float = floorf(a) + 0.25
	_check(String(CaravanRules.phase(v, noon).state) == "open", "open at noon")
	_check(String(CaravanRules.phase(v, noon, true).state) == "storm", "closed in a storm")
	_check(String(CaravanRules.phase(v, floorf(a) + 0.65).state) == "night", "closed at night")
	_check(String(CaravanRules.phase(v, l + tear * 0.5).state) == "teardown", "teardown when it leaves")
	_check(String(CaravanRules.phase(v, l + tear + drive * 0.5).state) == "going", "going after the teardown")
	_check(String(CaravanRules.phase(v, l + tear + drive + 0.01).state) == "away", "away again")
	_check(CaravanRules.visit_at(seed_a, 10, noon).get("i", -1) == v.i, "visit_at finds the running visit")
	_check(CaravanRules.visit_at(seed_a, 10, l + tear + drive + 0.01).is_empty() or int(CaravanRules.visit_at(seed_a, 10, l + tear + drive + 0.01).i) != int(v.i), "visit_at is empty between visits")
	## the offer
	var offer: Dictionary = CaravanRules.offer(seed_a, 3, 0)
	_check(str(offer) == str(CaravanRules.offer(seed_a, 3, 0)), "the offer of a visit is the same every time")
	var curios: int = 0
	var buy_ok: bool = true
	for row: Dictionary in offer.buy as Array[Dictionary]:
		curios += 1 if String(row.group) == "curio" else 0
		buy_ok = buy_ok and not DataRegistry.get_entry("items", String(row.item)).is_empty() and int(row.price) > 0 and int(row.stock) > 0
	_check(curios == 1, "exactly one curiosity (%d)" % curios)
	_check(buy_ok and (offer.buy as Array).size() >= 7, "WAREN rows are real items with price and stock (%d rows)" % (offer.buy as Array).size())
	var wanted: int = 0
	var wanted_ok: bool = true
	for row: Dictionary in offer.sell as Array[Dictionary]:
		if bool(row.wanted):
			wanted += 1
			wanted_ok = wanted_ok and int(row.price) > int(row.base) and int(row.limit) > 0
	_check(wanted >= 2 and wanted <= 3 and wanted_ok, "2..3 GESUCHT rows pay more up to a limit (%d)" % wanted)
	_check(bool((offer.sell as Array[Dictionary])[0].wanted), "the wanted rows come first")
	var level_ok: bool = true
	for k: int in 40:
		for row: Dictionary in CaravanRules.offer(seed_a, k, 0).buy as Array[Dictionary]:
			level_ok = level_ok and String(row.item) not in ["sun_quartz", "lake_moonstone", "potion_heal_2", "gem_lens_2"]
	_check(level_ok, "a young town gets no goods of higher levels")
	var wanted_row: Dictionary = {"price": 10, "base": 4, "limit": 3, "wanted": true}
	_check(CaravanRules.sell_price(wanted_row, 2) == 10 and CaravanRules.sell_price(wanted_row, 3) == 4, "the wanted price holds until the limit")
	_check(CaravanRules.buy_price(100, 0) == 100 and CaravanRules.buy_price(100, 100) == 90, "trust lowers the price by up to 10 %")
	## the stand
	var plaza: Vector2 = Vector2(1000, 1000)
	var none: Array[Rect2] = []
	_check(int(CaravanRules.slot(CaravanRules.pick_slot(plaza, none)).side) == -1, "an empty square: the west side first")
	var west: Array[Rect2] = [Rect2(plaza + Vector2(-100, -70), Vector2(80, 140))]
	_check(int(CaravanRules.slot(CaravanRules.pick_slot(plaza, west)).side) == 1, "the west side built in: the east side")
	var all: Array[Rect2] = [Rect2(plaza + Vector2(-120, -80), Vector2(240, 160))]
	_check(CaravanRules.pick_slot(plaza, all) == -1, "a square built in all round: no slot")
	var east: Array[Rect2] = []
	_check(int(CaravanRules.slot(CaravanRules.pick_slot(plaza, east, plaza + Vector2(300, -200))).side) == 1, "the slot nearest to where the road comes in")
	## the cart road
	var line: PackedVector2Array = CaravanRules.road("caravan_road")
	var length: float = 0.0
	for k: int in range(1, line.size()):
		length += line[k - 1].distance_to(line[k])
	_check(line.size() > 100 and length > 3000.0, "the cart road is baked and long (%d px)" % int(length))
	_check(line[0].distance_to(Vector2(798 * 16 + 8, 668 * 16 + 8)) < 24.0, "it starts beside the hut")
	_check(line[line.size() - 1].distance_to(Vector2(766 * 16 + 8, 428 * 16 + 8)) < 24.0, "it runs north into the distance")
	var decal: bool = false
	for d: Variant in DataRegistry.table("ground_baked").get("decals", []) as Array:
		decal = decal or String((d as Dictionary).get("id", "")) == "caravan_road"
	_check(decal and ResourceLoader.exists("res://assets/world/ground/caravan_road.png"), "the road decal is baked")
	CaravanRules.set_storm_override(Callable())


# ---------- in the world ----------

func _world() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	await _frames(60)
	world.debug_jump_town()
	await _frames(120)
	var caravan: CaravanManager = town.caravan
	_check(caravan != null, "the town has a caravan")
	_check(town.has_heart(), "the fountain square stands")
	_check(caravan.first_day > TimeManager.day - 1, "the first visit is set once the square stands (day %d, now %d)" % [caravan.first_day, TimeManager.day])
	CaravanRules.set_storm_override(func(_e: float) -> bool: return false)
	TimeManager.set_time(0.40)
	await _frames(5)
	caravan.debug_come(1)
	await _frames(30)
	_check(caravan.state() == "coming", "a developer visit drives in (%s)" % caravan.state())
	_check(caravan.view.visible and caravan.merchant.visible, "wagon and merchant are seen")
	_check(caravan.merchant.prompt() == "", "no trade while it drives")
	var way: PackedVector2Array = caravan.route()
	_check(way[0].distance_to(caravan.far_point()) < 1.0 and way[way.size() - 1].distance_to(caravan.stall()) < 1.0, "the way runs from the far end of the road to the stall")
	_check(caravan.view.global_position.distance_to(caravan.stall()) > 2000.0, "it sets off far away on the road")
	var marker: Dictionary = caravan.merchant.map_marker()
	_check(not marker.is_empty() and String(marker.title) == "KARAWANE UNTERWEGS", "the map shows the caravan on the road")
	var stall: Vector2 = caravan.stall()
	_check(caravan.plaza().distance_to(stall) < 100.0, "the stall is on the square")
	await _frames(int((float(CaravanRules.cfg().drive_seconds) + float(CaravanRules.cfg().setup_seconds)) * 60.0) + 60)
	_check(caravan.state() == "open", "the stall opens after driving in and unfolding (%s)" % caravan.state())
	_check(caravan.view.fold() > 0.99, "the counter is down")
	_check(caravan.view.global_position.distance_to(stall) < 1.0, "the wagon stands on its slot")
	_check(town.check_site("lamp_post", stall + Vector2(0, -6), false) == "DIE KARAWANE STEHT HIER", "no building where the caravan stands")
	## life at the stall (step 4): settlers spend their break there, crows may land on the canvas, Jorun has his own figure
	var gustav: Settler = town.settler_node("gustav")
	_check(gustav != null and gustav.resolve_spot("caravan") == "caravan" and gustav.spot_position("caravan").distance_to(caravan.customer_point()) < 30.0, "Gustav's break spot is the stall while it stands")
	var perched: int = 0
	for node: Node in get_tree().get_nodes_in_group("town_perches"):
		if node is RoofPerch and (node as RoofPerch).host == caravan.view and not (node as RoofPerch).is_depleted():
			perched += 1
	_check(perched == 2, "two perches on the canvas while it stands (%d)" % perched)
	_check(caravan.merchant._sprite != null and ResourceLoader.exists("res://assets/characters/jorun.png"), "Jorun has his own figure")
	var sounds_ok: bool = true
	for sound: String in ["bell_a", "bell_b", "wheels", "ox_snort", "ox_low", "ox_bells", "flap", "cloth", "chain", "knock"]:
		sounds_ok = sounds_ok and ResourceLoader.exists("res://assets/audio/caravan/%s.wav" % sound)
	_check(sounds_ok, "the caravan's sounds exist")
	## talk: he is known, trusted a little, and hangs no notices
	player.global_position = caravan.merchant_point() + Vector2(0, 22)
	await _frames(3)
	_check(caravan.merchant.prompt() == "ANSPRECHEN", "E: ANSPRECHEN first (%s)" % caravan.merchant.prompt())
	town.request_talk("jorun")
	await _frames(3)
	_check(town.residents.has("jorun") and town.trust_of("jorun") == 10, "a talk builds trust")
	_check(town.has_met("jorun") and not town.met_residents().has("jorun"), "known, but he hangs no notices")
	_check(caravan.merchant.prompt() == "HANDELN", "E: HANDELN after the talk")
	## buying
	player.progress.award(20000, 0)
	await _frames(2)
	var row: Dictionary = {}
	for r: Dictionary in caravan._list("buy"):
		if int(r.trust) == 0 and String(r.group) != "curio":
			row = r
			break
	var item: String = String(row.item)
	var price: int = caravan.price_buy(item)
	_check(price == CaravanRules.buy_price(int(row.price), 10), "the price carries the trust")
	var copper: int = player.progress.copper
	var had: int = player.inventory.count_item(item)
	var stock: int = caravan.left(item)
	caravan.request_trade("buy", item, 1)
	await _frames(3)
	_check(player.progress.copper == copper - price and player.inventory.count_item(item) == had + 1 and caravan.left(item) == stock - 1, "buying one piece")
	caravan.request_trade("buy", item, 99)
	await _frames(3)
	_check(caravan.left(item) == 0 and player.inventory.count_item(item) == had + stock, "buying more than he has takes the rest")
	copper = player.progress.copper
	caravan.request_trade("buy", item, 1)
	await _frames(3)
	_check(player.progress.copper == copper, "sold out: nothing is paid")
	## selling into a wanted row
	var want: Dictionary = {}
	for r: Dictionary in caravan._list("sell"):
		if bool(r.wanted):
			want = r
			break
	var want_item: String = String(want.item)
	player.inventory.give(want_item, int(want.limit) + 3)
	await _frames(2)
	copper = player.progress.copper
	var count: int = player.inventory.count_plain(want_item)
	caravan.request_trade("sell", want_item, count)
	await _frames(3)
	var expected: int = 0
	for n: int in count:
		expected += CaravanRules.sell_price(want, n)
	_check(player.progress.copper == copper + expected, "the wanted price until its limit, then the plain one (%d vs %d)" % [player.progress.copper - copper, expected])
	_check(caravan.price_sell(want_item) == int(want.base), "after the limit he pays the plain price")
	## the shop window lists his rows
	var window: ShopWindow = ShopWindow.open(get_tree(), player, town, "caravan")
	await _frames(10)
	_check(window != null and window.rows.size() == caravan._list("buy").size(), "the window shows the visit's goods")
	if window != null:
		window._close()
	await _frames(60)
	## reach
	player.global_position = caravan.merchant_point() + Vector2(0, 400)
	await _frames(3)
	_check(caravan.trade_block(player) == "ZU WEIT WEG", "too far away to trade")
	player.global_position = caravan.merchant_point() + Vector2(0, 22)
	## save and load keep the visit and its counters
	var sold_before: Dictionary = (caravan.visit.sold as Dictionary).duplicate()
	var saved: Dictionary = town.export_state()
	town.import_state(saved)
	await _frames(3)
	_check(str(caravan.visit.sold) == str(sold_before) and caravan.state() == "open", "save/load keep the visit and what was sold")
	## night: closed, E knocks
	TimeManager.set_time(0.90)
	await _frames(5)
	_check(caravan.state() == "night", "closed at night (%s)" % caravan.state())
	_check(caravan.trade_block(player) == "DER STAND IST ZU", "no trade at night")
	_check(caravan.merchant.prompt() == "KLOPFEN" and not caravan.merchant.visible, "asleep in the wagon: E knocks")
	TimeManager.set_time(0.45)
	await _frames(5)
	_check(caravan.state() == "open", "open again in the morning (%s)" % caravan.state())
	## leaving
	caravan.debug_leave()
	await _frames(5)
	_check(caravan.state() == "teardown", "the stall is taken down (%s)" % caravan.state())
	await _frames(int((float(CaravanRules.cfg().teardown_seconds) + float(CaravanRules.cfg().drive_seconds)) * 60.0) + 90)
	_check(caravan.state() == "away" and not caravan.view.visible, "it has driven off (%s)" % caravan.state())
	_check(caravan.visit.is_empty() and caravan.footprint() == Rect2(), "the visit is over, the square free again")
	gustav = town.settler_node("gustav") ## the save/load above made the settlers anew
	_check(gustav != null and gustav.resolve_spot("caravan") == "fire", "without the caravan Gustav's break is at the fire again")
	var free_perches: bool = true
	for node: Node in get_tree().get_nodes_in_group("town_perches"):
		if node is RoofPerch and (node as RoofPerch).host == caravan.view:
			free_perches = free_perches and (node as RoofPerch).is_depleted()
	_check(free_perches, "no birds on a wagon that has gone")
	_check(town.check_site("lamp_post", stall + Vector2(0, -6), false) != "DIE KARAWANE STEHT HIER", "building is allowed there again")
	CaravanRules.set_storm_override(Callable())
