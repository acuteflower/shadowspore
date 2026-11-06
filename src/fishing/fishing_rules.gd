class_name FishingRules
extends RefCounted
## Pure fishing rules (no nodes, no network): which fish is interested, how long it takes, and the drill
## ("tension and flow"). Numbers live in data/fishing.json. Used by the host-side FishingComponent and by the tests.


static func settings() -> Dictionary:
	return DataRegistry.table("fishing")["settings"] as Dictionary


static func species_table() -> Dictionary:
	return DataRegistry.table("fishing")["species"] as Dictionary


static func rods() -> Dictionary:
	return DataRegistry.table("fishing")["rods"] as Dictionary


static func poses() -> Dictionary:
	return DataRegistry.table("fishing")["poses"] as Dictionary


## How interested every species is right now. ctx: x, y (river field: distance to the bank, depth), flow (0..1),
## night (0..1), light_depth (px, negative = outside every light), bait (item id or ""), pose, scared (Array of ids).
static func weights(ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var table: Dictionary = species_table()
	var pose_def: Dictionary = poses().get(String(ctx.get("pose", "cork")), poses()["cork"]) as Dictionary
	var shy_depth: float = float((settings()["light"] as Dictionary)["shy_depth"])
	var scared: Array = ctx.get("scared", []) as Array
	for id: String in table:
		var s: Dictionary = table[id]
		if scared.has(id):
			continue
		var habitat: Dictionary = s["habitat"] as Dictionary
		var hx: Array = habitat["x"] as Array
		var hy: Array = habitat["y"] as Array
		var x: float = float(ctx.get("x", 0.0))
		var y: float = float(ctx.get("y", 0.0))
		if x < float(hx[0]) or x > float(hx[1]) or y < float(hy[0]) or y > float(hy[1]):
			continue
		var night: float = float(ctx.get("night", 0.0))
		var window: Array = s["night"] as Array
		if night < float(window[0]) or night > float(window[1]):
			continue
		if s.has("calm") and float(ctx.get("flow", 0.0)) > float(s["calm"]):
			continue
		if float(s.get("shy", 0.0)) > 0.0:
			if float(ctx.get("light_depth", -9999.0)) > shy_depth or float(pose_def.get("glow", 0.0)) > 0.0:
				continue ## the deep ones come only in complete darkness, and never to a glowing float
		var baits: Dictionary = s["baits"] as Dictionary
		var bait: String = String(ctx.get("bait", ""))
		var bait_weight: float = float(baits.get(bait, baits.get("", 0.0)))
		if bait_weight <= 0.0:
			continue
		var mult: Dictionary = pose_def.get("mult", {}) as Dictionary
		var w: float = float(s["weight"]) * bait_weight * float(mult.get(id, 1.0))
		if w > 0.0:
			out[id] = w
	return out


static func pick(weights_in: Dictionary, rng: RandomNumberGenerator) -> String:
	var sum: float = total(weights_in)
	if sum <= 0.0:
		return ""
	var roll: float = rng.randf() * sum
	for id: String in weights_in:
		roll -= float(weights_in[id])
		if roll <= 0.0:
			return id
	return String(weights_in.keys()[0])


static func total(weights_in: Dictionary) -> float:
	var sum: float = 0.0
	for id: String in weights_in:
		sum += float(weights_in[id])
	return sum


## Seconds until a fish takes the bait: more interest, faster.
static func bite_delay(interest: float, rng: RandomNumberGenerator) -> float:
	var nib: Dictionary = settings()["nibble"] as Dictionary
	return rng.randf_range(float(nib["min"]), float(nib["max"])) / (0.6 + interest)


static func strike_window(species_id: String, rng: RandomNumberGenerator) -> float:
	var range_a: Array = (species_table()[species_id] as Dictionary)["strike"] as Array
	return rng.randf_range(float(range_a[0]), float(range_a[1]))


static func roll_length(species_id: String, rng: RandomNumberGenerator) -> float:
	var range_a: Array = (species_table()[species_id] as Dictionary)["length"] as Array
	var k: float = pow(rng.randf(), 1.4) ## small ones are common
	return roundf(lerpf(float(range_a[0]), float(range_a[1]), k))


static func new_drill(species_id: String, rod: Dictionary, start_dist: float, rng: RandomNumberGenerator) -> Dictionary:
	var s: Dictionary = species_table()[species_id] as Dictionary
	var flee: Array = s["flee"] as Array
	return {
		"species": species_id, "phase": "flee", "t": 0.0, "time": 0.0,
		"dur": rng.randf_range(float(flee[0]), float(flee[1])),
		"tension": 0.25, "dist": start_dist, "stamina": float(s["stamina"]),
		"snap": 0.0, "tell": false, "fled": 1, "surge": 1.0, "run": 0.0, "pull_in": 0.0,
	}


## One tick of the fight. `give` 0..1: how far she gives way towards the fish, `reel`: the crank. Returns "", "landed",
## "snapped" (line broke) or "escaped" (all the line ran out).
## `integrate` false: the caller (FishingComponent) moves the fish through the water itself, `d["dist"]` is then the real
## distance it measured. `d["run"]` is the swim speed (px/s) of a run, `d["pull_in"]` the reel speed (px/s) of the crank.
static func drill_step(d: Dictionary, give: float, reel: bool, delta: float, rod: Dictionary, rng: RandomNumberGenerator, integrate: bool = true) -> String:
	var cfg: Dictionary = settings()["drill"] as Dictionary
	var s: Dictionary = species_table()[String(d["species"])] as Dictionary
	var pull: float = float(s["pull"])
	var k: float = float(cfg["k"])
	var tension: float = float(d["tension"])
	var dist: float = float(d["dist"])
	d["time"] = float(d["time"]) + delta
	d["t"] = float(d["t"]) + delta
	d["tell"] = false
	if String(d["phase"]) == "flee":
		var target: float = clampf(pull * (1.15 - 0.95 * give) / float(rod["flex"]), 0.0, 1.3)
		tension += (target - tension) * minf(1.0, k * delta)
		if reel:
			tension += float(cfg["reel_in_flee"]) * delta
		var curve: Array = cfg["burst"] as Array ## a run starts with a surge and loses steam
		var surge: float = lerpf(float(curve[0]), float(curve[1]), smoothstep(0.0, 1.0, clampf(float(d["t"]) / maxf(float(d["dur"]), 0.01), 0.0, 1.0)))
		var run: float = float(s["speed"]) * surge * (float(cfg["run_base"]) + float(cfg["run_give"]) * give)
		d["run"] = run
		d["pull_in"] = 0.0
		if integrate:
			dist += run * delta
		d["surge"] = surge
		if dist > float(rod["line"]):
			tension += float(cfg["over_line"]) * delta
		if float(d["t"]) >= float(d["dur"]):
			d["stamina"] = float(d["stamina"]) - float(s["burst"])
			d["phase"] = "tire"
			d["t"] = 0.0
			var tire: Array = s["tire"] as Array
			d["dur"] = rng.randf_range(float(tire[0]), float(tire[1])) if float(d["stamina"]) > 0.0 else 1.0e9
	else:
		var target: float = 0.08 + (0.38 * pull if reel else 0.0)
		tension += (target - tension) * minf(1.0, k * delta)
		d["run"] = 0.0
		var pull_in: float = float(rod["reel"]) * (1.0 - float(cfg["reel_stamina"]) * clampf(float(d["stamina"]), 0.0, 1.0)) if reel else 0.0
		d["pull_in"] = pull_in
		if integrate:
			dist -= pull_in * delta
		if float(d["stamina"]) > 0.0 and float(d["dur"]) - float(d["t"]) <= float(cfg["tell_time"]):
			d["tell"] = true
		if float(d["t"]) >= float(d["dur"]):
			var flee: Array = s["flee"] as Array
			d["phase"] = "flee"
			d["t"] = 0.0
			d["dur"] = rng.randf_range(float(flee[0]), float(flee[1]))
			d["fled"] = int(d["fled"]) + 1 ## the component turns the fish to a new heading
	tension = clampf(tension, 0.0, 1.3)
	d["tension"] = tension
	d["dist"] = dist
	if tension >= 1.0:
		d["snap"] = float(d["snap"]) + delta
	else:
		d["snap"] = maxf(0.0, float(d["snap"]) - delta * 2.0)
	if float(d["snap"]) >= float(cfg["snap_hold"]):
		return "snapped"
	if dist > float(rod["line"]) * float(cfg["escape_factor"]):
		return "escaped"
	if dist <= float(cfg["land_distance"]):
		return "landed"
	return ""


## The colour of the line is the only tension readout: petrol (slack) -> gold (good) -> red (about to break).
static func line_color(tension: float) -> Color:
	var colors: Dictionary = settings()["line_colors"] as Dictionary
	var band: Dictionary = settings()["tension"] as Dictionary
	var slack: Color = Color(String(colors["slack"]))
	var good: Color = Color(String(colors["good"]))
	var danger: Color = Color(String(colors["danger"]))
	if tension < float(band["warn"]):
		return slack.lerp(good, smoothstep(0.1, 0.3, tension))
	return good.lerp(danger, smoothstep(float(band["warn"]), float(band["danger"]), tension))


## How much the line trembles (px): none until the warning band, wild at danger. A coming flight also makes it shiver.
static func line_jitter(tension: float, tell: bool) -> float:
	var band: Dictionary = settings()["tension"] as Dictionary
	var j: float = smoothstep(float(band["warn"]), 1.0, tension) * 1.6
	return maxf(j, 0.7 if tell else 0.0)
