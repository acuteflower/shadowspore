class_name HallgratPeople
extends Node2D
## Hallgrat's people (docs/hallgrat_bewohner_konzept.md, step 1: the walking net and the daily plans with stand-in figures). Child of
## `Hallgrat`. Where someone is, is a pure function of the clock, their plan (data/hallgrat_people.json) and the town's walking net
## (`HallgratWays`): no network object, nothing saved, every peer sees the same. The net is built once on a `Jobs` worker (it only reads
## immutable data), which also warms every route the plans need; until then, and while no local player is near the town, no figure exists.
## Step 4 (the town's life): Pim's lamp round over every street lantern (`lamp_round` in his plan; the lanterns light when he reaches them,
## `lamp_lit`), every outdoor spot has a shelter (a door or a market stall) people walk to in the rain and through which they go in during
## a storm, people standing close turn to each other and talk (meeting places). All on top of the plan (`_view`): the plan's place is never
## changed, a short local walk (the "follower") only carries a figure smoothly to where the weather sends it and back.

const DAY: float = TimeManager.DAY_LENGTH_SEC
const LAMP_STOP: float = 2.2 ## seconds Pim stands at a lantern with his pole raised
const FOLLOW_SPEED: float = 38.0 ## px/s of the local walk to a shelter and back
const MEET_RANGE: float = 30.0 ## people standing this close turn to each other and talk
const SHELTER_REACH: float = 260.0
const STAY_OUT: Array[String] = ["guard", "work"] ## clips of people who keep their place in the rain (the gate, the stalls)

## Lantern (rounded px) -> the time of day Pim lights it; filled when the plans are built.
static var lamp_times: Dictionary = {}

var ways: HallgratWays
var walk_speed: float = 30.0
var plans: Dictionary = {} ## id -> {spots: {name -> {pos, inside, face, clip}}, schedule: [[from, spot]], spec}
var residents: Dictionary = {} ## id -> HallgratResident (only while a local player is near; on the host while any player is: trades and board hand-ins are checked there)
var _bounds: Rect2 = Rect2()
var _job: Jobs.Job
var _check: float = 0.0
var _data: Dictionary = {}
var _follow: Dictionary = {} ## id -> {pos, route, d, target}: the local walk on top of the plan
var _rain: bool = false
var _storm: bool = false
var murmur: AudioStreamPlayer2D ## the evening crowd outside the inn (data `sounds.murmur`), louder the more stand there
var crowd: int = 0 ## people outside the inn right now (tests)


func setup() -> void:
	name = "People"
	y_sort_enabled = true
	_data = DataRegistry.table("hallgrat_people")
	walk_speed = float(_data.get("walk_speed", 30.0))
	var b: Array = DataRegistry.table("hallgrat").get("bounds", [0, 0, 0, 0]) as Array
	var margin: float = float(_data.get("load_margin", 40)) * 16.0
	_bounds = Rect2(Vector2(float(b[0]), float(b[1])) * 16.0, Vector2(float(b[2]) - float(b[0]), float(b[3]) - float(b[1])) * 16.0).grow(margin)


## Builds the net and the plans now, on this thread (tests, or a caller that wants them at once).
func build_now() -> void:
	if ways != null:
		return
	if _job != null:
		_take(Jobs.wait(_job))
		return
	_take(_build(Terrain.relief))


func _exit_tree() -> void:
	if _job != null:
		Jobs.cancel(_job)
		_job = null


func ready_to_walk() -> bool:
	return ways != null


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		var near: bool = _player_near()
		if near and ways == null and _job == null:
			var relief: Relief = Terrain.relief
			_job = Jobs.run(func() -> Variant: return _build(relief), _take, Jobs.Prio.LOW)
		if near and ways != null and residents.is_empty():
			_spawn()
		elif not near and not residents.is_empty():
			_despawn()
	if residents.is_empty():
		return
	var t: float = TimeManager.time_of_day
	_rain = WeatherManager.sky_wet()
	_storm = WeatherManager.storm_now() > 0.4
	var views: Dictionary = {}
	for id: String in residents:
		views[id] = _view(id, state_at(id, t), delta)
	_meet(views, t)
	for id: String in residents:
		(residents[id] as HallgratResident).apply(views[id] as Dictionary, delta)
	_murmur(views, delta)


## The inn's murmur: a loop at the inn that fades in with three or more people outside it and out when they go.
func _murmur(views: Dictionary, delta: float) -> void:
	var cfg: Dictionary = (_data.get("sounds", {}) as Dictionary).get("murmur", {}) as Dictionary
	if cfg.is_empty():
		return
	var at: Vector2 = spot_raw({"building": String(cfg.get("building", "gasthaus"))})
	if not at.is_finite():
		return
	crowd = 0
	for id: String in views:
		var v: Dictionary = views[id] as Dictionary
		if not bool(v.get("inside", false)) and (v.pos as Vector2).is_finite() and (v.pos as Vector2).distance_to(at) < float(cfg.get("radius", 110.0)):
			crowd += 1
	var want: float = clampf(float(crowd - int(cfg.get("min", 3)) + 1) / 4.0, 0.0, 1.0)
	if murmur == null:
		if want <= 0.0:
			return
		murmur = AudioStreamPlayer2D.new()
		murmur.stream = load(String((_data.get("sounds", {}) as Dictionary).get("folder", "")) + String(cfg.get("file", "murmur")) + ".wav") as AudioStream
		murmur.bus = "SFX"
		murmur.max_distance = float(cfg.get("range", 360.0))
		murmur.position = at + Vector2(0, 30)
		murmur.volume_db = -60.0
		murmur.set_meta("level", 0.0)
		murmur.finished.connect(murmur.play)
		add_child(murmur)
		murmur.play()
	var level: float = move_toward(float(murmur.get_meta("level")), want, delta * 0.25)
	murmur.set_meta("level", level)
	murmur.volume_db = float(cfg.get("db", -12.0)) + linear_to_db(maxf(level, 0.001))
	if level <= 0.0 and want <= 0.0:
		murmur.queue_free()
		murmur = null


## Tests: the weather as the figures see it.
func set_weather(rain: bool, storm: bool) -> void:
	_rain = rain
	_storm = storm


## A figure's state with the weather on top: in the rain people standing outside walk to their spot's shelter, in a storm they go in through
## it (the watch stays out). The walk there and back is local and smooth; the plan's own walking is followed exactly.
func _view(id: String, state: Dictionary, delta: float) -> Dictionary:
	var plan: Dictionary = plans.get(id, {}) as Dictionary
	var spot: Dictionary = (plan.get("spots", {}) as Dictionary).get(String(state.get("spot", "")), {}) as Dictionary
	var watch: bool = bool((plan.get("spec", {}) as Dictionary).get("night", false)) or String(state.get("clip", "")) == "guard"
	var target: Vector2 = state.pos as Vector2
	var sheltering: bool = false
	if not bool(state.moving) and not bool(state.inside) and (_rain or _storm) and not watch and spot.has("shelter"):
		target = spot.shelter as Vector2
		sheltering = true
	var f: Dictionary = _follow.get(id, {}) as Dictionary
	if f.is_empty() or bool(state.inside) or not target.is_finite() or not (f.pos as Vector2).is_finite():
		_follow[id] = {"pos": target, "route": PackedVector2Array(), "d": 0.0, "target": target}
		return state
	var at: Vector2 = f.pos as Vector2
	var out: Dictionary = state.duplicate()
	if at.distance_to(target) < 1.0:
		f.pos = target
		f.route = PackedVector2Array()
		if sheltering:
			out.pos = target
			out.face = Vector2.DOWN
			out.clip = "idle"
			out.sheltered = true
			if _storm: ## in through the door
				out.inside = true
		return out
	if bool(state.moving): ## the plan walks on: catch up straight and quickly (only after a shelter, a short way)
		f.pos = at.move_toward(target, FOLLOW_SPEED * 2.0 * delta)
		out.pos = f.pos
		return out
	if (f.target as Vector2) != target or (f.route as PackedVector2Array).size() < 2:
		var route: PackedVector2Array = ways.route(at, target) if ways != null else PackedVector2Array()
		f.route = route if route.size() >= 2 else PackedVector2Array([at, target])
		f.d = 0.0
		f.target = target
	var r: PackedVector2Array = f.route as PackedVector2Array
	f.d = float(f.d) + FOLLOW_SPEED * delta
	var length: float = HallgratWays.length_of(r)
	if float(f.d) >= length:
		f.pos = target
		f.route = PackedVector2Array()
		out.pos = target
		return out
	var pos: Vector2 = HallgratWays.point_along(r, float(f.d))
	var ahead: Vector2 = HallgratWays.point_along(r, float(f.d) + 6.0)
	f.pos = pos
	out.pos = pos
	out.moving = true
	out.inside = false
	out.dir = (ahead - pos).normalized() if ahead != pos else Vector2.DOWN
	out.fast = _rain or _storm
	return out


## Meeting places: two people standing (idle or talking) close together turn to each other and talk in turns. A function of their places and
## the clock, so every peer shows the same pairs.
func _meet(views: Dictionary, t: float) -> void:
	var standing: Array[String] = []
	for id: String in views:
		var v: Dictionary = views[id] as Dictionary
		if not bool(v.inside) and not bool(v.moving) and String(v.clip) in ["idle", "talk"] and not bool(v.get("sheltered", false)):
			standing.append(id)
	for id: String in standing:
		var v: Dictionary = views[id] as Dictionary
		var best: String = ""
		var best_d: float = MEET_RANGE
		for other: String in standing:
			if other == id:
				continue
			var dd: float = (v.pos as Vector2).distance_to((views[other] as Dictionary).pos as Vector2)
			if dd < best_d:
				best_d = dd
				best = other
		if best == "":
			continue
		var them: Vector2 = (views[best] as Dictionary).pos as Vector2
		v.face = (them - (v.pos as Vector2)).normalized() if them != v.pos else Vector2.DOWN
		var beat: int = int(t * DAY / 2.6) + (hash(id) & 7)
		v.clip = "talk" if beat % 3 != 0 else "idle"
		v.partner = best


func _player_near() -> bool:
	for p: Player in Player.all:
		if is_instance_valid(p) and (p.is_multiplayer_authority() or multiplayer.is_server()) and _bounds.has_point(p.global_position):
			return true
	return false


## Worker: the net, every resolved spot and every route the plans use. Reads only immutable data.
func _build(relief: Relief) -> Dictionary:
	var w: HallgratWays = HallgratWays.build(relief, DataRegistry.table("hallgrat"), DataRegistry.table("hallgrat_art"), DataRegistry.table("ground_baked"))
	var out_plans: Dictionary = {}
	var specs: Dictionary = (_data.get("residents", {}) as Dictionary).duplicate()
	specs.merge(HallgratExtras.plans(_data)) ## the townsfolk: plans in the same format, made from the seed
	var taken: Dictionary = {} ## cells already given to a spot: nobody stands in somebody else (the core figures choose first)
	var lamps: Dictionary = {}
	for id: String in specs:
		var spec: Dictionary = specs[id] as Dictionary
		var spots: Dictionary = {}
		for spot_id: String in (spec.get("spots", {}) as Dictionary):
			var s: Dictionary = (spec.spots as Dictionary)[spot_id] as Dictionary
			var raw: Vector2 = spot_raw(s)
			var face: Array = s.get("face", [0, 1]) as Array
			spots[spot_id] = {
				"pos": _free_spot(w, raw, taken) if raw.is_finite() else Vector2.INF,
				"inside": bool(s.get("inside", false)),
				"face": Vector2(float(face[0]), float(face[1])),
				"clip": String(s.get("clip", "idle")),
			}
		var schedule: Array = []
		for entry: Array in spec.get("schedule", []) as Array:
			schedule.append([float(entry[0]), String(entry[2])])
		schedule.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		if spec.has("lamp_round"):
			_lamp_round(w, spec, spots, schedule, taken, lamps)
		out_plans[id] = {"spots": spots, "schedule": schedule, "spec": spec}
		for k: int in schedule.size(): ## warm the routes: from the spot before to this one
			var prev: String = String((schedule[(k - 1 + schedule.size()) % schedule.size()] as Array)[1])
			var here: String = String((schedule[k] as Array)[1])
			var a: Vector2 = (spots[prev] as Dictionary).pos as Vector2
			var b: Vector2 = (spots[here] as Dictionary).pos as Vector2
			if a.is_finite() and b.is_finite():
				w.route(a, b)
	_shelters(w, out_plans)
	return {"ways": w, "plans": out_plans, "lamps": lamps}


## Pim's lamp round (`lamp_round` [from, to] in his plan): one stop at every street lantern, nearest first from where he stands before it,
## timed so the round fits; the time he reaches each lantern goes into `lamps` (rounded px -> time of day).
func _lamp_round(w: HallgratWays, spec: Dictionary, spots: Dictionary, schedule: Array, taken: Dictionary, lamps: Dictionary) -> void:
	var window: Array = spec.lamp_round as Array
	var t0: float = float(window[0])
	var t1: float = float(window[1])
	var start: Vector2 = Vector2.INF
	for entry: Array in schedule: ## where he is right before the round
		if float(entry[0]) <= t0:
			start = (spots[String(entry[1])] as Dictionary).pos as Vector2
	var left: Array[Vector2] = []
	for d: Dictionary in DataRegistry.table("hallgrat").get("deco", []) as Array:
		if String(d.get("type", "")) == "deko_laterne":
			left.append(Vector2(float((d.px as Array)[0]), float((d.px as Array)[1])))
	if left.is_empty() or not start.is_finite():
		return
	var order: Array[Vector2] = []
	var stands: Array[Vector2] = []
	var lengths: Array[float] = []
	var here: Vector2 = start
	while not left.is_empty():
		var best: int = 0
		for i: int in left.size():
			if left[i].distance_to(here) < left[best].distance_to(here):
				best = i
		var lamp: Vector2 = left[best]
		left.remove_at(best)
		var stand: Vector2 = _free_spot(w, lamp + Vector2(0, 10), taken)
		if not stand.is_finite():
			continue
		var route: PackedVector2Array = w.route(here, stand)
		if route.size() < 2 and here.distance_to(stand) > 4.0: ## a lantern he cannot reach: it lights at nightfall
			continue
		order.append(lamp)
		stands.append(stand)
		lengths.append(HallgratWays.length_of(route))
		here = stand
	var total: float = 0.0
	for l: float in lengths:
		total += l
	var budget: float = (t1 - t0) * DAY - LAMP_STOP * stands.size()
	var v: float = maxf(walk_speed * 1.2, total / maxf(budget * 0.8, 1.0)) ## he hurries a little: it is getting dark
	var t: float = t0
	for k: int in stands.size():
		var span: float = (lengths[k] / v + LAMP_STOP) / DAY
		var spot_id: String = "lamp_%d" % k
		spots[spot_id] = {"pos": stands[k], "inside": false, "face": (order[k] - stands[k]).normalized(), "clip": "light"}
		schedule.append([t, spot_id])
		var speed: float = maxf(walk_speed, lengths[k] / maxf(1.0, span * DAY * 0.8))
		lamps[Vector2i(order[k].round())] = fposmod(t + lengths[k] / speed / DAY, 1.0)
		t += span
	schedule.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))


## Every outdoor spot's shelter: the nearest door or market stall within reach (each gets its own cell), unless it already is one.
func _shelters(w: HallgratWays, out_plans: Dictionary) -> void:
	var town: Dictionary = DataRegistry.table("hallgrat")
	var roofs: Array[Vector2] = []
	for b: Dictionary in town.get("placed", []) as Array:
		var kind: String = String(b.get("type", ""))
		if kind.begins_with("verlassen") or kind.begins_with("stall"):
			continue
		var d: Array = b.get("door", b.px) as Array
		roofs.append(Vector2(float(d[0]), float(d[1]) + (6.0 if not kind.begins_with("stand") else 10.0)))
	var taken: Dictionary = {}
	for id: String in out_plans:
		var spots: Dictionary = (out_plans[id] as Dictionary).spots as Dictionary
		for spot_id: String in spots:
			var s: Dictionary = spots[spot_id] as Dictionary
			var at: Vector2 = s.pos as Vector2
			if bool(s.inside) or not at.is_finite() or String(s.clip) in STAY_OUT or String(s.clip) == "light":
				continue
			var best: Vector2 = Vector2.INF
			for roof: Vector2 in roofs:
				if roof.distance_to(at) < SHELTER_REACH and (not best.is_finite() or roof.distance_to(at) < best.distance_to(at)):
					best = roof
			if not best.is_finite() or best.distance_to(at) < 28.0:
				continue
			var cell: Vector2 = _free_spot(w, best, taken)
			if cell.is_finite() and w.route(at, cell).size() >= 2:
				s.shelter = cell


## Whether the street lantern at `at` burns at time `t`: from when Pim lights it until dawn. Before the plans are built, simply at night.
static func lamp_lit(at: Vector2, t: float) -> bool:
	var key: Vector2i = Vector2i(at.round())
	if not lamp_times.has(key):
		return true
	var lit: float = float(lamp_times[key])
	return fposmod(t - lit, 1.0) < fposmod(0.2 - lit, 1.0)


## The spot on the net nearest to `raw` whose cell no other spot has (within three cells; else the snapped one).
static func _free_spot(w: HallgratWays, raw: Vector2, taken: Dictionary) -> Vector2:
	var p: Vector2 = w.snap(raw)
	if not p.is_finite():
		return p
	var c: Vector2i = w.cell_of(p)
	if not taken.has(c):
		taken[c] = true
		return p
	for ring: int in range(1, 4):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var nc: Vector2i = c + Vector2i(dx, dy)
				if w.inside(nc) and not taken.has(nc) and w.open_at(w.center_of(nc)):
					taken[nc] = true
					return w.center_of(nc)
	return p


func _take(result: Variant) -> void:
	_job = null
	var built: Dictionary = result as Dictionary
	ways = built.ways as HallgratWays
	plans = built.plans as Dictionary
	lamp_times = built.get("lamps", {}) as Dictionary


## Where a spot of the data points to before snapping onto the net (px), INF when its anchor is missing.
static func spot_raw(s: Dictionary) -> Vector2:
	var town: Dictionary = DataRegistry.table("hallgrat")
	if s.has("px"):
		var p: Array = s.px as Array
		return Vector2(float(p[0]), float(p[1]))
	if s.has("door") or s.has("building"):
		var want: String = String(s.get("door", s.get("building", "")))
		for b: Dictionary in town.get("placed", []) as Array:
			if String(b.id) != want:
				continue
			if s.has("door"):
				var d: Array = b.get("door", b.px) as Array
				return Vector2(float(d[0]), float(d[1]) + 6.0)
			var f: Array = b.px as Array
			var at: Array = s.get("at", [0, 0]) as Array
			return Vector2(float(f[0]) + float(at[0]), float(f[1]) + float(at[1]))
		return Vector2.INF
	if s.has("place"):
		for pl: Dictionary in town.get("places", []) as Array:
			if String(pl.id) != String(s.place):
				continue
			var r: Array = pl.rect as Array
			var at2: Array = s.get("at", [0, 0]) as Array
			return (Vector2(float(r[0]) + float(r[2]) / 2.0 + float(at2[0]), float(r[1]) + float(r[3]) / 2.0 + float(at2[1]))) * 16.0
	return Vector2.INF


## The state of one resident at time of day `t`: {pos, inside, moving, dir, spot, face, clip}. The entry that began last before `t` holds;
## at its start they set off from the spot before it, along the net, at `walk_speed` (quicker when the way would not fit the entry).
func state_at(id: String, t: float) -> Dictionary:
	var plan: Dictionary = plans.get(id, {}) as Dictionary
	var schedule: Array = plan.get("schedule", []) as Array
	if schedule.is_empty() or ways == null:
		return {"pos": Vector2.INF, "inside": true, "moving": false, "dir": Vector2.DOWN, "spot": "", "face": Vector2.DOWN, "clip": "idle"}
	var k: int = 0
	var best: float = INF
	for i: int in schedule.size():
		var since: float = fposmod(t - float((schedule[i] as Array)[0]), 1.0)
		if since < best:
			best = since
			k = i
	var n: int = schedule.size()
	var spot_id: String = String((schedule[k] as Array)[1])
	var prev_id: String = String((schedule[(k - 1 + n) % n] as Array)[1])
	var span: float = fposmod(float((schedule[(k + 1) % n] as Array)[0]) - float((schedule[k] as Array)[0]), 1.0)
	if span <= 0.0:
		span = 1.0
	var spots: Dictionary = plan.spots as Dictionary
	var here: Dictionary = spots.get(spot_id, {}) as Dictionary
	var there: Dictionary = spots.get(prev_id, here) as Dictionary
	var route: PackedVector2Array = ways.route(there.pos as Vector2, here.pos as Vector2) if (there.pos as Vector2).is_finite() and (here.pos as Vector2).is_finite() else PackedVector2Array()
	var length: float = HallgratWays.length_of(route)
	var speed: float = maxf(walk_speed, length / maxf(1.0, span * DAY * 0.8))
	var walked: float = best * DAY * speed
	var state: Dictionary = {"spot": spot_id, "face": here.get("face", Vector2.DOWN), "clip": here.get("clip", "idle"), "dir": here.get("face", Vector2.DOWN)}
	if route.size() >= 2 and walked < length:
		var pos: Vector2 = HallgratWays.point_along(route, walked)
		var ahead: Vector2 = HallgratWays.point_along(route, walked + 6.0)
		state.pos = pos
		state.moving = true
		state.inside = false
		state.dir = (ahead - pos).normalized() if ahead != pos else Vector2.DOWN
		state.fast = speed > walk_speed * 1.15
		return state
	state.pos = here.get("pos", Vector2.INF)
	state.moving = false
	state.inside = bool(here.get("inside", false))
	return state


func _spawn() -> void:
	for id: String in plans:
		var r: HallgratResident = HallgratExtra.new() if bool(((plans[id] as Dictionary).spec as Dictionary).get("extra", false)) else HallgratResident.new()
		r.setup(id, (plans[id] as Dictionary).spec as Dictionary)
		add_child(r)
		residents[id] = r
		r.apply(state_at(id, TimeManager.time_of_day))


func _despawn() -> void:
	for id: String in residents:
		(residents[id] as Node).queue_free()
	residents.clear()
	_follow.clear()
	if murmur != null:
		murmur.queue_free()
		murmur = null
