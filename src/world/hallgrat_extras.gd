class_name HallgratExtras
extends RefCounted
## Hallgrat's townsfolk (docs/hallgrat_bewohner_konzept.md 3): turns data/hallgrat_people.json `extras` into plans in the same format as the
## core figures' (`spots` + `schedule`), so `HallgratPeople` resolves, routes and moves them alike. Pure: a function of the data and
## `extras.seed` only (every peer makes the same townspeople), reads only immutable data, safe on a `Jobs` worker.
## Each extra gets a role (weights), a kind (body sheet), a palette (cloth a / cloth b / hair), a home (a lived-in house: it vanishes there),
## and its role's day with every place picked from that role's pools and every time shifted a little.

const SKIP_HOMES: Array[String] = ["verlassen", "stand", "stall", "halle", "torhaus"]


static func plans(data: Dictionary) -> Dictionary:
	var cfg: Dictionary = data.get("extras", {}) as Dictionary
	var out: Dictionary = {}
	if cfg.is_empty():
		return out
	var town: Dictionary = DataRegistry.table("hallgrat")
	var homes: Array[String] = []
	for b: Dictionary in town.get("placed", []) as Array:
		var kind: String = String(b.get("type", ""))
		var lived: bool = true
		for skip: String in SKIP_HOMES:
			if kind.begins_with(skip):
				lived = false
		if lived:
			homes.append(String(b.id))
	var roles: Dictionary = cfg.get("roles", {}) as Dictionary
	var pool: Array[String] = []
	for role: String in roles:
		if int((roles[role] as Dictionary).get("fixed", 0)) > 0:
			continue
		for i: int in int((roles[role] as Dictionary).get("weight", 1)):
			pool.append(role)
	pool.sort()
	var picks: Array[String] = []
	for role: String in roles: ## roles with a fixed number first (the guards)
		for i: int in int((roles[role] as Dictionary).get("fixed", 0)):
			picks.append(role)
	var seed: int = int(cfg.get("seed", 1))
	var count: int = int(cfg.get("count", 24))
	var n: int = 0
	while picks.size() < count and not pool.is_empty():
		picks.append(pool[_rng(seed, 9000 + n).randi() % pool.size()])
		n += 1
	var palettes: Dictionary = cfg.get("palettes", {}) as Dictionary
	for i: int in picks.size():
		var role: String = picks[i]
		var r: RandomNumberGenerator = _rng(seed, i)
		var def: Dictionary = roles[role] as Dictionary
		var kinds: Array = def.get("kinds", [0]) as Array
		var spec: Dictionary = {
			"extra": true,
			"role": role,
			"kind": int(kinds[r.randi() % kinds.size()]),
			"pal": [r.randi() % maxi((palettes.get("a", [[]]) as Array).size(), 1), r.randi() % maxi((palettes.get("b", [[]]) as Array).size(), 1),
					r.randi() % maxi((palettes.get("h", [[]]) as Array).size(), 1)],
			"night": bool(def.get("night", false)),
		}
		var home: String = homes[r.randi() % homes.size()] if not homes.is_empty() else ""
		var spots: Dictionary = {}
		var schedule: Array = []
		var k: int = 0
		var last_t: float = -1.0
		for entry: Array in def.get("day", []) as Array:
			if entry.size() > 3 and r.randf() > float(entry[3]): ## a stop only some make (the evening at the inn)
				continue
			var t: float = clampf(float(entry[0]) + r.randf_range(-1.0, 1.0) * float(cfg.get("jitter", 0.012)), last_t + 0.004, 0.999)
			last_t = t
			var spot_id: String = "s%d" % k
			var spot: Dictionary = _spot(String(entry[1]), r, town, home, i)
			spot["clip"] = String(entry[2]) if entry.size() > 2 else "idle"
			spots[spot_id] = spot
			schedule.append([t, 0, spot_id])
			k += 1
		spec["spots"] = spots
		spec["schedule"] = schedule
		out["extra_%d" % i] = spec
	return out


static func _rng(seed: int, n: int) -> RandomNumberGenerator:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash([seed, n, "hallgrat_extra"])
	return r


## One place of a role's day: home | place:<id> | door:<id> | inn | bench | well | stall | deco:<type> | gate:<id>.
static func _spot(what: String, r: RandomNumberGenerator, town: Dictionary, home: String, i: int) -> Dictionary:
	var parts: PackedStringArray = what.split(":")
	match parts[0]:
		"home":
			return {"door": home, "inside": true, "face": [0, 1]}
		"door":
			return {"door": parts[1], "face": [0, 1]}
		"inn": ## the evening outside the inn: a loose crowd in front of it
			return {"building": "gasthaus", "at": [r.randf_range(-70.0, 40.0), r.randf_range(16.0, 52.0)], "face": [r.randf_range(-1, 1), -1]}
		"place":
			for pl: Dictionary in town.get("places", []) as Array:
				if String(pl.id) == parts[1]:
					var rect: Array = pl.rect as Array
					var at: Array = [r.randf_range(-0.3, 0.3) * float(rect[2]), r.randf_range(-0.3, 0.3) * float(rect[3])]
					return {"place": parts[1], "at": at, "face": [r.randf_range(-1, 1), r.randf_range(-1, 1)]}
			return {"px": [0, 0]}
		"gate":
			for g: Dictionary in town.get("gates", []) as Array:
				if String(g.id) == parts[1]:
					var tile: Array = g.tile as Array
					return {"px": [(float(tile[0]) + 0.5) * 16.0 + r.randf_range(-20, 20), (float(tile[1]) + 0.5) * 16.0 + r.randf_range(-12, 12)], "face": [1, 0]}
			return {"px": [0, 0]}
		"stall":
			var forum: Array = town.get("forum", [0, 0]) as Array
			var middle: Vector2 = Vector2(float(forum[0]), float(forum[1])) * 16.0
			var stalls: Array = []
			for b: Dictionary in town.get("placed", []) as Array:
				if String(b.id).begins_with("stand_"):
					stalls.append(b)
			if stalls.is_empty():
				return {"px": [0, 0]}
			var s: Dictionary = stalls[(i + r.randi() % 2) % stalls.size()] as Dictionary
			var p: Vector2 = Vector2(float((s.px as Array)[0]), float((s.px as Array)[1]))
			var out_dir: Vector2 = (p - middle).normalized() if p != middle else Vector2.DOWN
			var at2: Vector2 = p + out_dir * 14.0 + out_dir.orthogonal() * r.randf_range(-12.0, 12.0)
			return {"px": [at2.x, at2.y], "face": [-out_dir.x, -out_dir.y]}
		_: ## bench, well, deco:<type>
			var want: String = "deko_bank_ew" if parts[0] == "bench" else ("deko_brunnen" if parts[0] == "well" else parts[1] if parts.size() > 1 else "")
			var found: Array = []
			for d: Dictionary in town.get("deco", []) as Array:
				if String(d.get("type", "")) == want:
					found.append(d)
			if found.is_empty():
				return {"px": [0, 0]}
			var d2: Dictionary = found[(i * 3 + r.randi() % 2) % found.size()] as Dictionary ## spread over the benches and wash lines
			var a: float = r.randf() * TAU
			var reach: float = 10.0 if parts[0] == "bench" else 22.0
			var q: Vector2 = Vector2(float((d2.px as Array)[0]), float((d2.px as Array)[1])) + Vector2(cos(a) * reach, 6.0 + absf(sin(a)) * reach * 0.5)
			return {"px": [q.x, q.y], "face": [0, -1] if parts[0] != "bench" else [0, 1]}
