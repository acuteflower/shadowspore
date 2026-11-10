class_name WeatherRules
extends RefCounted
## The weather as a PURE function of the world seed and the world time (docs/wetter_konzept.md), like `Moisture` and `NightRules.special_for`: every peer
## computes the same sky from the clock it already shares, nothing is sent or saved. Data: data/weather.json.
##
## The weather is a chain of segments (a state, a length in days, a wind direction), drawn one after the other from a seeded Markov table and cached
## per seed. `state_at(seed, epoch)` blends the neighbouring segments over `blend` days, `drift_at` is the integral of the cloud velocity (closed form,
## so the clouds travel exactly as the wind blows, and time jumps just jump the sample). The world time `epoch` counts days and runs on through the
## night: see `epoch()`.

const DAY_SEC: float = 720.0 ## TimeManager.DAY_LENGTH_SEC
const DAY_START: float = 0.25 ## TimeManager.DAY_START
const WIND_BASE: float = 0.26 ## radians: the prevailing wind blows from the west, a little downwards

static var _cfg: Dictionary = {}
static var _chains: Dictionary = {}
static var _wet_cache: Dictionary = {}
static var _storm_cache: Dictionary = {}


## What the weather looks like: all values 0..1 except `dir` (radians). `id` = the dominant named state.
class State extends RefCounted:
	var cloud: float = 0.0
	var rain: float = 0.0
	var wind: float = 0.25
	var storm: float = 0.0
	var fog: float = 0.0
	var dir: float = 0.26
	var id: String = "fair"

	func copy() -> State:
		var out: State = State.new()
		out.cloud = cloud
		out.rain = rain
		out.wind = wind
		out.storm = storm
		out.fog = fog
		out.dir = dir
		out.id = id
		return out

	func mix(other: State, w: float) -> State:
		var out: State = State.new()
		out.cloud = lerpf(cloud, other.cloud, w)
		out.rain = lerpf(rain, other.rain, w)
		out.wind = lerpf(wind, other.wind, w)
		out.storm = lerpf(storm, other.storm, w)
		out.fog = lerpf(fog, other.fog, w)
		out.dir = lerp_angle(dir, other.dir, w)
		out.id = other.id if w >= 0.5 else id
		return out


## One cached chain of segments for a seed.
class Chain extends RefCounted:
	var world_seed: int = 0
	var starts: PackedFloat64Array = PackedFloat64Array()
	var lens: PackedFloat64Array = PackedFloat64Array()
	var ids: PackedStringArray = PackedStringArray()
	var dirs: PackedFloat64Array = PackedFloat64Array()
	var vels: PackedVector2Array = PackedVector2Array()
	var drift0: PackedVector2Array = PackedVector2Array() ## where the clouds were at the start of each segment
	var end: float = 0.0


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = DataRegistry.table("weather")
	return _cfg


## Tests and tools hand in a table (or reload the file).
static func reset(table: Dictionary = {}) -> void:
	_cfg = table
	_chains.clear()
	_wet_cache.clear()
	_storm_cache.clear()


static func enabled() -> bool:
	return bool(cfg().get("enabled", true))


## World time in days: the day count plus the part since sunrise, so the small hours still belong to the day before (continuous over midnight).
static func epoch(day: int, time_of_day: float) -> float:
	return float(day) + fposmod(time_of_day - DAY_START, 1.0)


static func state_def(id: String) -> Dictionary:
	return (cfg().get("states", {}) as Dictionary).get(id, {}) as Dictionary


static func _from_def(id: String, def: Dictionary, dir: float) -> State:
	var s: State = State.new()
	s.cloud = float(def.get("cloud", 0.0))
	s.rain = float(def.get("rain", 0.0))
	s.wind = float(def.get("wind", 0.25))
	s.storm = float(def.get("storm", 0.0))
	s.fog = float(def.get("fog", 0.0))
	s.dir = dir
	s.id = id
	return s


## The state a name stands for (dev menu, story): constant, with the prevailing wind direction.
static func named(id: String) -> State:
	return _from_def(id, state_def(id), WIND_BASE)


static func ids() -> Array:
	return (cfg().get("states", {}) as Dictionary).keys()


static func velocity(dir: float, wind: float) -> Vector2:
	var speed: Array = cfg().get("speed", [6.0, 34.0]) as Array
	return Vector2.from_angle(dir) * lerpf(float(speed[0]), float(speed[1]), clampf(wind, 0.0, 1.0))


static func _chain(world_seed: int) -> Chain:
	var chain: Chain = _chains.get(world_seed) as Chain
	if chain == null:
		chain = Chain.new()
		chain.world_seed = world_seed
		_chains[world_seed] = chain
	return chain


static func _hour_bias(id: String, tod: float) -> float:
	var factor: float = 1.0
	for entry: Variant in ((cfg().get("hour_bias", {}) as Dictionary).get(id, []) as Array):
		var row: Array = entry as Array
		if tod >= float(row[0]) and tod < float(row[1]):
			factor *= float(row[2])
	return factor


static func _pick_next(rng: RandomNumberGenerator, current: String, start: float) -> String:
	var table: Dictionary = (cfg().get("next", {}) as Dictionary).get(current, {}) as Dictionary
	var tod: float = fposmod(fposmod(start, 1.0) + DAY_START, 1.0)
	var calm: bool = start < float(cfg().get("calm_until", 0.0))
	var weights: Dictionary = {}
	var total: float = 0.0
	for id: String in table:
		var def: Dictionary = state_def(id)
		if calm and (float(def.get("rain", 0.0)) > 0.0 or float(def.get("storm", 0.0)) > 0.0 or float(def.get("cloud", 0.0)) > 0.6):
			continue ## the first days are fair: nothing wet, nothing dark
		var w: float = float(table[id]) * _hour_bias(id, tod)
		weights[id] = w
		total += w
	if weights.is_empty():
		return String(cfg().get("start", "fair"))
	var roll: float = rng.randf() * total
	for id: String in weights:
		roll -= float(weights[id])
		if roll <= 0.0:
			return id
	return String(weights.keys()[0])


static func _extend(chain: Chain, until: float) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var guard: int = 0
	while chain.end <= until and guard < 100000:
		guard += 1
		var k: int = chain.ids.size()
		rng.seed = hash([chain.world_seed, k, 8123])
		var id: String
		var start: float = chain.end
		if k == 0:
			id = String(cfg().get("start", "fair"))
			start = 0.0
		else:
			id = _pick_next(rng, chain.ids[k - 1], start)
		var def: Dictionary = state_def(id)
		var span: Array = def.get("len", [0.2, 0.4]) as Array
		var length: float = rng.randf_range(float(span[0]), float(span[1]))
		var spread: float = 1.2 if float(def.get("storm", 0.0)) > 0.5 else 0.85
		var dir: float = WIND_BASE + rng.randf_range(-spread, spread)
		var vel: Vector2 = velocity(dir, float(def.get("wind", 0.25)))
		var drift_start: Vector2 = Vector2.ZERO
		if k > 0:
			drift_start = _drift_in(chain, k - 1, chain.lens[k - 1])
		chain.starts.append(start)
		chain.lens.append(length)
		chain.ids.append(id)
		chain.dirs.append(dir)
		chain.vels.append(vel)
		chain.drift0.append(drift_start)
		chain.end = start + length


## Index of the segment that holds `e`.
static func _locate(chain: Chain, e: float) -> int:
	var lo: int = 0
	var hi: int = chain.starts.size() - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		if chain.starts[mid] <= e:
			lo = mid
		else:
			hi = mid - 1
	return lo


## Where the clouds are `t` days into segment `i` (closed form: the velocity eases from the last segment's to this one's over `blend`).
static func _drift_in(chain: Chain, i: int, t_days: float) -> Vector2:
	var v_cur: Vector2 = chain.vels[i]
	var v_prev: Vector2 = chain.vels[i - 1] if i > 0 else v_cur
	var blend: float = float(cfg().get("blend", 0.035)) * DAY_SEC
	var t: float = t_days * DAY_SEC
	var base: Vector2 = chain.drift0[i]
	if t < blend:
		var u: float = t / blend
		return base + v_prev * t + (v_cur - v_prev) * blend * (u * u * u - u * u * u * u * 0.5)
	return base + v_prev * blend + (v_cur - v_prev) * blend * 0.5 + v_cur * (t - blend)


static func _segment_state(chain: Chain, i: int) -> State:
	return _from_def(chain.ids[i], state_def(chain.ids[i]), chain.dirs[i])


## The weather at a world time. A storm night overrides it (see `storm_night`).
static func state_at(world_seed: int, e: float) -> State:
	e = maxf(e, 0.0)
	var chain: Chain = _chain(world_seed)
	_extend(chain, e + 0.001)
	var i: int = _locate(chain, e)
	var state: State = _segment_state(chain, i)
	var blend: float = float(cfg().get("blend", 0.035))
	var t: float = e - chain.starts[i]
	if i > 0 and t < blend:
		state = _segment_state(chain, i - 1).mix(state, smoothstep(0.0, 1.0, t / blend))
	var storm_w: float = storm_night(world_seed, e)
	if storm_w > 0.0:
		var storm: State = named("storm")
		storm.dir = state.dir
		state = state.mix(storm, storm_w)
	return state


static func drift_at(world_seed: int, e: float) -> Vector2:
	e = maxf(e, 0.0)
	var chain: Chain = _chain(world_seed)
	_extend(chain, e + 0.001)
	var i: int = _locate(chain, e)
	return _drift_in(chain, i, e - chain.starts[i])


## 0..1: how much a special "storm" night holds the weather at this time (the night belongs to the day that began at sunrise).
static func storm_night(world_seed: int, e: float) -> float:
	var day: int = floori(e)
	var key: int = hash([world_seed, day])
	var is_storm: bool
	if _storm_cache.has(key):
		is_storm = bool(_storm_cache[key])
	else:
		is_storm = day >= 1 and NightRules.special_for(world_seed, day) == "storm"
		_storm_cache[key] = is_storm
	if not is_storm:
		return 0.0
	var window: Dictionary = cfg().get("storm_night", {}) as Dictionary
	var f: float = e - float(day)
	var ramp: float = maxf(0.001, float(window.get("ramp", 0.04)))
	return smoothstep(float(window.get("from", 0.55)) - ramp, float(window.get("from", 0.55)) + ramp, f) * (1.0 - smoothstep(float(window.get("to", 0.95)) - ramp, float(window.get("to", 0.95)) + ramp, f))


## The ground's wetness (0 dry .. 1 soaked) at a world time: rain soaks it, it dries over `dry_days` (a sum over the last stretch of weather,
## so it needs no history). Global: a rain cell on the screen is local, the soil is not.
static func ground_wet(world_seed: int, e: float) -> float:
	var key: int = hash([world_seed, roundi(e * 400.0)])
	if _wet_cache.has(key):
		return float(_wet_cache[key])
	var g: Dictionary = cfg().get("ground", {}) as Dictionary
	var steps: int = int(g.get("steps", 14))
	var step_days: float = float(g.get("step_days", 0.1))
	var dry: float = maxf(0.02, float(g.get("dry_days", 0.35)))
	var sum: float = 0.0
	for k: int in steps:
		var t: float = e - float(k) * step_days
		if t < 0.0:
			break
		var s: State = state_at(world_seed, t)
		var wet_in: float = s.rain + 0.35 * s.fog
		sum += wet_in * exp(-float(k) * step_days / dry) * step_days / dry
	var value: float = clampf(sum * float(g.get("gain", 1.25)), 0.0, 1.0)
	if _wet_cache.size() > 512:
		_wet_cache.clear()
	_wet_cache[key] = value
	return value


## Was the morning of this day damp (plants, mushrooms and snails ask this once a day)?
static func wet_day(world_seed: int, day: int) -> bool:
	return ground_wet(world_seed, float(day) + 0.02) >= 0.28


## The lightning of one time slice (`slice` = world seconds / `lightning.slice`): {} or {at (seconds into the slice), x, y (screen fractions of the
## strike), far (0 near .. 1 far), seed, double, bolt}. Pure, so every peer flashes at the same moment.
static func lightning(world_seed: int, slice: int, storm: float) -> Dictionary:
	var l: Dictionary = cfg().get("lightning", {}) as Dictionary
	if storm < float(l.get("min_storm", 0.35)):
		return {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([world_seed, slice, 5531])
	if rng.randf() >= float(l.get("chance", 0.11)) * storm:
		return {}
	return {"at": rng.randf() * 0.85, "x": rng.randf_range(0.1, 0.9), "y": rng.randf_range(0.42, 0.92), "far": rng.randf(), "seed": rng.randi(),
		"double": rng.randf() < float(l.get("double", 0.35)), "bolt": rng.randf() < 0.72}


## A name for the display: the state whose numbers are closest.
static func nearest_id(s: State) -> String:
	var best: String = "fair"
	var best_d: float = 1e9
	for id: String in (cfg().get("states", {}) as Dictionary):
		var def: Dictionary = state_def(id)
		var d: float = absf(float(def.get("cloud", 0.0)) - s.cloud) * 1.2 + absf(float(def.get("rain", 0.0)) - s.rain) * 2.0 + absf(float(def.get("storm", 0.0)) - s.storm) * 1.5 \
			+ absf(float(def.get("wind", 0.0)) - s.wind) * 0.4 + absf(float(def.get("fog", 0.0)) - s.fog) * 1.0
		if d < best_d:
			best_d = d
			best = id
	return best


static func display_name(id: String) -> String:
	return String(state_def(id).get("name", id.to_upper()))
