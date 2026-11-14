class_name CaravanRules
extends RefCounted
## The travelling merchant's caravan (docs/haendler_konzept.md), pure: no nodes, no state. Every peer computes the same calendar, the same phase and the
## same offer from the world seed, the day the first visit was set (`first_day`, the host's one saved value) and the clock. Times are "epochs": days since
## day 0 plus the share of the day since sunrise (`WeatherRules.epoch`), so 12.05 is day 12 at 0.30 of the clock.
## Phases of a visit: away, coming (drives in), setup (unfolds the stall), open, night (closed, asleep in the wagon), storm (closed while a storm blows),
## teardown, going (drives off).

const DAY_START: float = 0.25
const DAY_SEC: float = 720.0
const GROUPS: Array[String] = ["curio", "far", "seed", "basic"] ## the order of the WAREN rows (the curiosity first)

static var _cache_key: String = ""
static var _cache: Array[Dictionary] = []
static var _cache_seed: int = 0
static var _cache_next: int = 0 ## the day the visit after the last cached one would start
static var _storm_override: Callable = Callable() ## tests: a Callable(epoch) -> bool instead of the weather
static var _roads: Dictionary = {} ## path id -> PackedVector2Array (world px)


static func cfg() -> Dictionary:
	return DataRegistry.table("caravan")


static func epoch(day: int, time_of_day: float) -> float:
	return float(day) + fposmod(time_of_day - DAY_START, 1.0)


## The clock of an epoch (0..1, 0.25 = sunrise).
static func clock_of(e: float) -> float:
	return fposmod(e - floorf(e) + DAY_START, 1.0)


static func days(seconds: float) -> float:
	return seconds / DAY_SEC


static func _num(key: String, fallback: float) -> float:
	return float(cfg().get(key, fallback))


## A weighted pick from [[value, weight], ...].
static func _weighted(rng: RandomNumberGenerator, table: Array) -> int:
	var total: float = 0.0
	for pair: Variant in table:
		total += float((pair as Array)[1])
	var roll: float = rng.randf() * total
	for pair: Variant in table:
		roll -= float((pair as Array)[1])
		if roll < 0.0:
			return int((pair as Array)[0])
	return int((table[table.size() - 1] as Array)[0]) if not table.is_empty() else 1


## Does a storm blow at this moment (the caravan does not arrive into one, the stall closes)?
static func storm_at(world_seed: int, e: float) -> bool:
	if _storm_override.is_valid():
		return bool(_storm_override.call(e))
	if not WeatherRules.enabled():
		return false
	return WeatherRules.state_at(world_seed, e).storm >= _num("storm", 0.5)


static func set_storm_override(check: Callable) -> void:
	_storm_override = check
	_cache_key = ""


## Every visit that starts before `until_e`, and the one after: [{i, a (arrival epoch), l (leaving epoch), stay (days)}]. The gaps and stays are drawn per visit
## from its own seed; an arrival into a storm moves on by a day (at most `storm_shift_max` times). Cached and extended as the days go on.
static func visits(world_seed: int, first_day: int, until_e: float) -> Array[Dictionary]:
	if first_day < 0:
		return []
	var key: String = "%d:%d:%d" % [world_seed, first_day, cfg().hash()]
	if key != _cache_key:
		_cache_key = key
		_cache.clear()
		_cache_seed = world_seed
		_cache_next = first_day
	var arrive: float = _num("arrive", 0.30)
	var leave: float = _num("leave", 0.62)
	var shift_max: int = int(_num("storm_shift_max", 3.0))
	while _cache.is_empty() or float(_cache[_cache.size() - 1].a) <= until_e:
		var i: int = _cache.size()
		if i > 5000:
			break
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(world_seed, i, 7331))
		var arrive_day: int = _cache_next
		var shifted: int = 0
		while shifted < shift_max and storm_at(world_seed, epoch(arrive_day, arrive)):
			arrive_day += 1
			shifted += 1
		var stay: int = maxi(_weighted(rng, cfg().get("stay", [[1, 1]]) as Array), 1)
		_cache.append({"i": i, "a": epoch(arrive_day, arrive), "l": epoch(arrive_day + stay, leave), "stay": stay, "shift": shifted})
		_cache_next = arrive_day + stay + maxi(_weighted(rng, cfg().get("gap", [[3, 1]]) as Array), 1)
	var out: Array[Dictionary] = []
	for v: Dictionary in _cache:
		out.append(v)
		if float(v.a) > until_e:
			break
	return out


## The whole time the caravan is seen for a visit: from setting off until it has driven out of sight.
static func window(v: Dictionary) -> Vector2:
	var drive: float = days(_num("drive_seconds", 26.0))
	var tear: float = days(_num("teardown_seconds", 10.0))
	return Vector2(float(v.a) - drive, float(v.l) + tear + drive)


## The visit seen at `e` ({} when the caravan is away).
static func visit_at(world_seed: int, first_day: int, e: float) -> Dictionary:
	for v: Dictionary in visits(world_seed, first_day, e + 1.0):
		var w: Vector2 = window(v)
		if e >= w.x and e < w.y:
			return v
	return {}


## The next visit that has not begun to come yet ({} without a calendar).
static func next_visit(world_seed: int, first_day: int, e: float) -> Dictionary:
	for v: Dictionary in visits(world_seed, first_day, e + 30.0):
		if window(v).x > e:
			return v
	return {}


## Where a visit stands at `e`: {state, k (0..1 through a timed state), t (seconds into it)}. `storm` closes an open stall.
static func phase(v: Dictionary, e: float, storm: bool = false) -> Dictionary:
	if v.is_empty():
		return {"state": "away", "k": 0.0, "t": 0.0}
	var a: float = float(v.a)
	var l: float = float(v.l)
	var drive: float = days(_num("drive_seconds", 26.0))
	var setup: float = days(_num("setup_seconds", 14.0))
	var tear: float = days(_num("teardown_seconds", 10.0))
	if e < a - drive:
		return {"state": "away", "k": 0.0, "t": 0.0}
	if e < a:
		return _timed("coming", e - (a - drive), drive)
	if e < a + setup:
		return _timed("setup", e - a, setup)
	if e < l:
		var tod: float = clock_of(e)
		var open: bool = tod >= _num("open", 0.30) and tod < _num("close", 0.78)
		if not open:
			return {"state": "night", "k": 1.0, "t": 0.0}
		return {"state": "storm" if storm else "open", "k": 1.0, "t": 0.0}
	if e < l + tear:
		return _timed("teardown", e - l, tear)
	if e < l + tear + drive:
		return _timed("going", e - (l + tear), drive)
	return {"state": "away", "k": 0.0, "t": 0.0}


static func _timed(state: String, gone: float, length: float) -> Dictionary:
	return {"state": state, "k": clampf(gone / maxf(length, 0.000001), 0.0, 1.0), "t": gone * DAY_SEC}


## Is the stall standing (unfolded or closed) in this state?
static func parked(state: String) -> bool:
	return state in ["setup", "open", "night", "storm", "teardown"]


## Is the caravan anywhere in the town in this state?
static func present(state: String) -> bool:
	return state != "away"


# ---------- the offer ----------

## What visit `i` brings, for a town of level `level`: {"buy": [{item, price (base, before trust), stock, group, trust}], "sell": [{item, price, base, limit
## (0 = no limit), wanted}]}. Pure: every peer draws the same rows.
static func offer(world_seed: int, i: int, level: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(world_seed, i, 9157))
	var jitter: Array = cfg().get("jitter", [1.0, 1.0]) as Array
	var goods: Dictionary = cfg().get("goods", {}) as Dictionary
	var buy: Array[Dictionary] = []
	for group: String in GROUPS:
		var spec: Dictionary = goods.get(group, {}) as Dictionary
		if spec.is_empty():
			continue
		var pool: Array = []
		for raw: Variant in spec.get("items", []) as Array:
			var entry: Dictionary = raw as Dictionary
			if int(entry.get("level", 0)) <= level and not DataRegistry.get_entry("items", String(entry.item)).is_empty():
				pool.append(entry)
		var count_range: Array = spec.get("count", [1, 1]) as Array
		var want: int = rng.randi_range(int(count_range[0]), int(count_range[1]))
		for n: int in mini(want, pool.size()):
			var total: float = 0.0
			for entry: Variant in pool:
				total += float((entry as Dictionary).get("weight", 1.0))
			var roll: float = rng.randf() * total
			var pick: int = pool.size() - 1
			for k: int in pool.size():
				roll -= float((pool[k] as Dictionary).get("weight", 1.0))
				if roll < 0.0:
					pick = k
					break
			var chosen: Dictionary = pool[pick] as Dictionary
			pool.remove_at(pick)
			var stock_range: Array = chosen.get("stock", [1, 1]) as Array
			var factor: float = rng.randf_range(float(jitter[0]), float(jitter[1]))
			buy.append({"item": String(chosen.item), "price": maxi(roundi(float(chosen.price) * factor), 1), "stock": rng.randi_range(int(stock_range[0]), int(stock_range[1])),
				"group": group, "trust": int(chosen.get("trust", 0))})
	var sell: Array[Dictionary] = []
	for raw: Variant in cfg().get("buys", []) as Array:
		var entry: Dictionary = raw as Dictionary
		if not DataRegistry.get_entry("items", String(entry.item)).is_empty():
			sell.append({"item": String(entry.item), "price": int(entry.price), "base": int(entry.price), "limit": 0, "wanted": false})
	var wanted: Dictionary = cfg().get("wanted", {}) as Dictionary
	var wanted_range: Array = wanted.get("count", [0, 0]) as Array
	var free: Array[int] = []
	for k: int in sell.size():
		free.append(k)
	var wanted_rows: Array[Dictionary] = []
	for n: int in mini(rng.randi_range(int(wanted_range[0]), int(wanted_range[1])), free.size()):
		var at: int = rng.randi_range(0, free.size() - 1)
		var row: Dictionary = sell[free[at]]
		free.remove_at(at)
		var factor_range: Array = wanted.get("factor", [1.5, 1.5]) as Array
		var limit_range: Array = wanted.get("limit", [5, 5]) as Array
		row.price = maxi(roundi(float(row.base) * rng.randf_range(float(factor_range[0]), float(factor_range[1]))), int(row.base) + 1)
		row.limit = rng.randi_range(int(limit_range[0]), int(limit_range[1]))
		row.wanted = true
		wanted_rows.append(row)
	var ordered: Array[Dictionary] = wanted_rows.duplicate()
	for row: Dictionary in sell:
		if not bool(row.wanted):
			ordered.append(row)
	return {"buy": buy, "sell": ordered}


## The price of a WAREN row for somebody the merchant trusts this much (up to `trust_discount` off at 100).
static func buy_price(base: int, trust: int) -> int:
	var off: float = _num("trust_discount", 0.1) * clampf(float(trust) / 100.0, 0.0, 1.0)
	return maxi(roundi(float(base) * (1.0 - off)), 1)


## What the merchant pays for `item` when `taken` pieces of a GESUCHT row are already sold to him: the wanted price until its limit, then the plain price.
static func sell_price(row: Dictionary, taken: int) -> int:
	if bool(row.get("wanted", false)) and taken < int(row.get("limit", 0)):
		return int(row.price)
	return int(row.get("base", row.price))


# ---------- the stand ----------

## The wagon's footprint for slot `slot` on a plaza whose feet (the fountain's foot) are at `plaza`.
static func slot_rect(plaza: Vector2, slot: Dictionary) -> Rect2:
	var at: Array = slot.get("at", [0, 0]) as Array
	var foot: Array = slot.get("foot", [64, 22]) as Array
	return Rect2(plaza.x + float(at[0]) - float(foot[0]) / 2.0, plaza.y + float(at[1]) - float(foot[1]), float(foot[0]), float(foot[1]))


## The customers' strip in front of the counter.
static func front_rect(plaza: Vector2, slot: Dictionary) -> Rect2:
	var at: Array = slot.get("at", [0, 0]) as Array
	var front: Array = slot.get("front", [56, 18]) as Array
	return Rect2(plaza.x + float(at[0]) - float(front[0]) / 2.0, plaza.y + float(at[1]), float(front[0]), float(front[1]))


## The first slot whose wagon and front strip stay clear of `solids`; -1 when the square is built in. With `from` (where the road comes in) the
## nearest slot is tried first, else the west side first.
static func pick_slot(plaza: Vector2, solids: Array[Rect2], from: Vector2 = Vector2.INF) -> int:
	var slots: Array = cfg().get("slots", []) as Array
	var order: Array[int] = []
	for k: int in slots.size():
		if int((slots[k] as Dictionary).get("side", -1)) < 0:
			order.append(k)
	for k: int in slots.size():
		if not order.has(k):
			order.append(k)
	if from.is_finite():
		order.sort_custom(func(a: int, b: int) -> bool:
			return slot_rect(plaza, slots[a] as Dictionary).get_center().distance_to(from) < slot_rect(plaza, slots[b] as Dictionary).get_center().distance_to(from))
	for k: int in order:
		var slot: Dictionary = slots[k] as Dictionary
		var body: Rect2 = slot_rect(plaza, slot)
		var front: Rect2 = front_rect(plaza, slot)
		var clear: bool = true
		for r: Rect2 in solids:
			if r.intersects(body) or r.intersects(front):
				clear = false
				break
		if clear:
			return k
	return -1


static func slot(index: int) -> Dictionary:
	var slots: Array = cfg().get("slots", []) as Array
	return slots[index] as Dictionary if index >= 0 and index < slots.size() else {}


# ---------- the road ----------

## A baked path of data/ground.json as world px (points are relative to the start tile's centre), smoothed with the baker's Catmull-Rom (`bake_ground.catmull`)
## and thinned to about every 8 px. Empty when the path does not exist.
static func road(id: String) -> PackedVector2Array:
	if _roads.has(id):
		return _roads[id] as PackedVector2Array
	var out: PackedVector2Array = PackedVector2Array()
	var start: Array = DataRegistry.table("world_map").get("start", [0, 0]) as Array
	var centre: Vector2 = Vector2(float(start[0]) * 16.0 + 8.0, float(start[1]) * 16.0 + 8.0)
	for raw: Variant in DataRegistry.table("ground").get("paths", []) as Array:
		var spec: Dictionary = raw as Dictionary
		if String(spec.get("id", "")) != id:
			continue
		var pts: Array[Vector2] = []
		for p: Variant in spec.get("points", []) as Array:
			pts.append(centre + Vector2(float((p as Array)[0]), float((p as Array)[1])))
		out = catmull(pts, 8.0)
	_roads[id] = out
	return out


static func catmull(points: Array[Vector2], step: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if points.size() < 2:
		for p: Vector2 in points:
			out.append(p)
		return out
	var pts: Array[Vector2] = [points[0]]
	pts.append_array(points)
	pts.append(points[points.size() - 1])
	for i: int in range(1, pts.size() - 2):
		var p0: Vector2 = pts[i - 1]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[i + 2]
		var n: int = maxi(2, int(p1.distance_to(p2) / step))
		for k: int in n:
			var t: float = float(k) / float(n)
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(pts[pts.size() - 2])
	return out
