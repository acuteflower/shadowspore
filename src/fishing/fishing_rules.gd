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


## 1 inside [lo, hi], falling to 0 over `soft` outside: habitats have soft edges, a trout may stray into the shallows.
static func fit(value: float, range_a: Array, soft: float) -> float:
	var lo: float = float(range_a[0])
	var hi: float = float(range_a[1])
	if value < lo:
		return clampf(1.0 - (lo - value) / maxf(soft, 0.0001), 0.0, 1.0)
	if value > hi:
		return clampf(1.0 - (value - hi) / maxf(soft, 0.0001), 0.0, 1.0)
	return 1.0


## How strong the current is (0..1) at a point `x` px inside the water (negative = in the water): slack along the
## banks, fastest in the channel, almost still in lakes and the collecting pools.
static func current_strength(x: float, lake: bool, pool: bool) -> float:
	var c: Dictionary = settings()["current"] as Dictionary
	if not is_finite(x) or x > 0.0:
		return 0.0
	if lake:
		return float(c["lake"])
	var strength: float = lerpf(float(c["edge"]), 1.0, smoothstep(-4.0, float(c["deep_x"]), x))
	return minf(strength, float(c["pool"])) if pool else strength


## How interested every species is right now. ctx: x, y (river field: distance to the bank, depth), flow (0..1 current
## strength), night (0..1), light_depth (px, negative = outside every light), bait (item id or ""), pose,
## scared (Array of ids). Habitat, current and the time window fade out softly instead of ending at a wall.
static func weights(ctx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var table: Dictionary = species_table()
	var pose_def: Dictionary = poses().get(String(ctx.get("pose", "cork")), poses()["cork"]) as Dictionary
	var shy_depth: float = float((settings()["light"] as Dictionary)["shy_depth"])
	var base_soft: Dictionary = settings()["soft"] as Dictionary
	var scared: Array = ctx.get("scared", []) as Array
	var x: float = float(ctx.get("x", 0.0))
	var y: float = float(ctx.get("y", 0.0))
	var night: float = float(ctx.get("night", 0.0))
	var flow: float = float(ctx.get("flow", 0.0))
	if not is_finite(x):
		return out
	for id: String in table:
		var s: Dictionary = table[id]
		if scared.has(id):
			continue
		var soft: Dictionary = base_soft.merged(s.get("soft", {}) as Dictionary, true)
		var habitat: Dictionary = s["habitat"] as Dictionary
		var place: float = fit(x, habitat["x"] as Array, float(soft["x"])) * fit(y, habitat["y"] as Array, float(soft["y"]))
		place *= fit(night, s["night"] as Array, float(soft["night"]))
		if s.has("flow"):
			place *= fit(flow, s["flow"] as Array, float(soft["flow"]))
		if place <= 0.0:
			continue
		if float(s.get("shy", 0.0)) > 0.0:
			if float(ctx.get("light_depth", -9999.0)) > shy_depth or float(pose_def.get("glow", 0.0)) > 0.0:
				continue ## the deep ones come only in complete darkness, and never to a glowing float
		var bait_weight: float = bait_appeal(id, String(ctx.get("bait", "")))
		if bait_weight <= 0.0:
			continue
		var mult: Dictionary = pose_def.get("mult", {}) as Dictionary
		var w: float = float(s["weight"]) * bait_weight * float(mult.get(id, 1.0)) * place
		if w > 0.005:
			out[id] = w
	return out


## How much a species likes a bait (the table value; "" = no bait).
static func bait_appeal(species_id: String, bait: String) -> float:
	var baits: Dictionary = (species_table()[species_id] as Dictionary)["baits"] as Dictionary
	return float(baits.get(bait, baits.get("", 0.0)))


## How lively the fish are at this cast (multiplies the interest): busy at dawn and dusk, lazy in sunny shallows at noon,
## wary of the angler standing right above them (ctx `reach`: px from her feet to the float) and of a spot that was
## fished out or stirred up a moment ago (ctx `pressure` 0..1). ctx `sun` / `golden`: TimeManager.sun_amount/golden_amount.
static func activity(ctx: Dictionary) -> float:
	var a: Dictionary = settings()["activity"] as Dictionary
	var y: float = clampf(float(ctx.get("y", 0.5)), 0.0, 1.0)
	var mood: float = 1.0 + float(a["golden"]) * float(ctx.get("golden", 0.0)) - float(a["noon_shallow"]) * float(ctx.get("sun", 0.0)) * (1.0 - y)
	var wary: float = lerpf(float(a["wary_min"]), 1.0, smoothstep(float(a["wary_near"]), float(a["wary_far"]), float(ctx.get("reach", 999.0))))
	var cap: float = float((settings()["pressure"] as Dictionary)["cap"])
	var calm: float = 1.0 - clampf(float(ctx.get("pressure", 0.0)), 0.0, cap)
	var g: Dictionary = (WeatherRules.cfg().get("gameplay", {}) as Dictionary)
	var rain: float = clampf(float(ctx.get("rain", 0.0)), 0.0, 1.0)
	var storm: float = clampf(float(ctx.get("storm", 0.0)), 0.0, 1.0)
	## light rain wakes the fish (the surface hides the angler), a storm drives them down (docs/wetter_konzept.md 9)
	var weather: float = (1.0 + float(g.get("fish_light_rain", 0.30)) * rain * (1.0 - storm)) * lerpf(1.0, float(g.get("fish_storm", 0.85)), storm)
	return maxf(0.02, mood * wary * calm * weather)


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


## Seconds until a fish reaches the bait. Fish arrive at random (an exponential wait, mean `bite.mean / interest`), so
## two casts never feel the same; `settle`: after a splash the fish first come back (a few seconds of nothing).
static func bite_delay(interest: float, rng: RandomNumberGenerator, settle: bool = true) -> float:
	var b: Dictionary = settings()["bite"] as Dictionary
	var calm: Array = b["settle"] as Array
	var first: float = rng.randf_range(float(calm[0]), float(calm[1])) if settle else 0.0
	if interest <= 0.0:
		return float(b["max"])
	var wait: float = -log(1.0 - rng.randf() * 0.999) * float(b["mean"]) / interest
	return clampf(first + wait, 0.6, float(b["max"]))


## The chance that a fish looks at the bait and turns away: cautious species, a bait they do not care for, a spot that
## was fished hard. A twitch (`lured`) makes a hunter forget its caution.
static func refuse_chance(species_id: String, bait: String, pressure: float, lured: bool) -> float:
	var r: Dictionary = settings()["refuse"] as Dictionary
	var s: Dictionary = species_table()[species_id] as Dictionary
	var best: float = 0.0
	for key: String in (s["baits"] as Dictionary):
		best = maxf(best, float((s["baits"] as Dictionary)[key]))
	var liking: float = bait_appeal(species_id, bait) / maxf(best, 0.001)
	var p: float = float(s.get("caution", 0.0)) * (1.0 - liking) * float(r["base"]) + clampf(pressure, 0.0, 1.0) * float(r["pressure"])
	if lured:
		p *= 1.0 - float(r["lure"])
	return clampf(p, 0.0, 0.9)


static func strike_window(species_id: String, rng: RandomNumberGenerator) -> float:
	var range_a: Array = (species_table()[species_id] as Dictionary)["strike"] as Array
	return rng.randf_range(float(range_a[0]), float(range_a[1]))


## The length of a hooked fish: small ones are common, deep water (`depth` 0..1) holds the big ones.
static func roll_length(species_id: String, rng: RandomNumberGenerator, depth: float = 0.5) -> float:
	var range_a: Array = (species_table()[species_id] as Dictionary)["length"] as Array
	var k: float = pow(rng.randf(), lerpf(1.8, 0.9, clampf(depth, 0.0, 1.0)))
	return roundf(lerpf(float(range_a[0]), float(range_a[1]), k))


## 0 (smallest of its kind) .. 1 (the biggest).
static func size_of(species_id: String, length: float) -> float:
	var range_a: Array = (species_table()[species_id] as Dictionary)["length"] as Array
	return clampf(inverse_lerp(float(range_a[0]), float(range_a[1]), length), 0.0, 1.0)


## A fresh fight. `size` 0..1: a big one pulls harder and lasts longer.
static func new_drill(species_id: String, rod: Dictionary, start_dist: float, rng: RandomNumberGenerator, size: float = 0.5) -> Dictionary:
	var s: Dictionary = species_table()[species_id] as Dictionary
	var cfg: Dictionary = settings()["drill"] as Dictionary
	var flee: Array = s["flee"] as Array
	var size_pull: float = float(cfg["size_pull"])
	return {
		"species": species_id, "phase": "flee", "t": 0.0, "time": 0.0,
		"dur": rng.randf_range(float(flee[0]), float(flee[1])),
		"tension": float(cfg["start_tension"]), "dist": start_dist, "stamina": 1.0,
		"pull": float(s["pull"]) * (1.0 - size_pull * 0.5 + size_pull * size),
		"endurance": float(s["endurance"]) * (0.8 + float(cfg["size_endurance"]) * size),
		"snap": 0.0, "slack": 0.0, "tell": false, "fled": 1, "surge": 1.0, "run": 0.0, "pull_in": 0.0,
		"shake": 0.0, "shake_to": 0.0, "shake_t": 0.0, "last": false,
	}


## One tick of the fight. `give` 0..1: how far she gives way towards the fish, `reel`: the crank. Returns "", "landed",
## "snapped" (the line broke), "torn" (the hook tore out of a soft small mouth: species `mouth` < 1), "unhooked" (the line hung slack, the fish shook the hook) or "escaped"
## (all the line ran out).
## The fish has one store of strength (`stamina` 1 -> 0). A tight line (gold) wears it down, a run costs extra, a slack
## line lets it rest. Its runs and its pull weaken with it; an exhausted fish makes no more runs, except one last
## panicked rush when it first sees the bank.
## `integrate` false: the caller (FishingComponent) moves the fish through the water itself, `d["dist"]` is then the real
## distance it measured. `d["run"]` is the swim speed (px/s) away from her, `d["pull_in"]` the reel speed (px/s) of the crank.
static func drill_step(d: Dictionary, give: float, reel: bool, delta: float, rod: Dictionary, rng: RandomNumberGenerator, integrate: bool = true) -> String:
	var cfg: Dictionary = settings()["drill"] as Dictionary
	var s: Dictionary = species_table()[String(d["species"])] as Dictionary
	var pull: float = float(d["pull"])
	var k: float = float(cfg["k"])
	var tension: float = float(d["tension"])
	var dist: float = float(d["dist"])
	var stamina: float = float(d["stamina"])
	var exhausted: bool = stamina <= float(cfg["exhausted"])
	var vigor: float = lerpf(float(cfg["vigor"]), 1.0, stamina)
	d["time"] = float(d["time"]) + delta
	d["t"] = float(d["t"]) + delta
	d["tell"] = false
	# head shakes: the load jerks a little all the time, more with lively fish
	d["shake_t"] = float(d["shake_t"]) - delta
	if float(d["shake_t"]) <= 0.0:
		var gap: Array = cfg["shake_gap"] as Array
		d["shake_t"] = rng.randf_range(float(gap[0]), float(gap[1]))
		d["shake_to"] = rng.randf_range(-1.0, 1.0)
	d["shake"] = move_toward(float(d["shake"]), float(d["shake_to"]), delta * 6.0)
	var jerk: float = float(d["shake"]) * float(s.get("shake", 0.0)) * vigor
	var wear: Array = cfg["pressure"] as Array
	var drain: float = smoothstep(float(wear[0]), float(wear[1]), tension) ## a tight line tires the fish
	var run: float = 0.0
	var pull_in: float = 0.0
	if String(d["phase"]) == "flee":
		var curve: Array = cfg["burst"] as Array ## a run starts with a surge and loses steam
		var surge: float = lerpf(float(curve[0]), float(curve[1]), smoothstep(0.0, 1.0, clampf(float(d["t"]) / maxf(float(d["dur"]), 0.01), 0.0, 1.0)))
		var target: float = pull * (0.55 + 0.45 * vigor) * (1.15 - 0.95 * give) / float(rod["flex"]) + jerk
		if reel: ## cranking against a running fish: the load climbs fast, hardest at the start of the surge
			target += float(cfg["reel_in_flee"]) * (0.5 + pull) * surge
		tension += (clampf(target, 0.0, 1.3) - tension) * minf(1.0, k * (float(cfg["lock_k"]) if reel else 1.0) * delta) ## a locked reel takes the load at once
		run = float(s["speed"]) * surge * vigor * (float(cfg["run_base"]) + float(cfg["run_give"]) * give)
		drain += float(cfg["run_cost"]) * surge
		d["surge"] = surge
		if dist > float(rod["line"]):
			tension += float(cfg["over_line"]) * delta
		if float(d["t"]) >= float(d["dur"]):
			d["phase"] = "tire"
			d["t"] = 0.0
			var tire: Array = s["tire"] as Array
			d["dur"] = rng.randf_range(float(tire[0]), float(tire[1]))
			var warn: Array = s.get("tell", [cfg["tell_time"], cfg["tell_time"]]) as Array ## how early the line shivers before the next run
			d["tell_time"] = rng.randf_range(float(warn[0]), float(warn[1]))
	else:
		var hold: Array = cfg["hold_tension"] as Array
		var target: float = float(hold[0]) + float(hold[1]) * pull * vigor + jerk * 0.5
		if reel:
			var load: Array = cfg["reel_tension"] as Array
			target = float(load[0]) + float(load[1]) * pull * vigor + jerk * 0.5
			pull_in = float(rod["reel"]) * (1.0 - float(cfg["reel_weight"]) * pull) * lerpf(0.55, 1.0, 1.0 - stamina)
		elif give > 0.3: ## giving line to a fish that does not pull: the line goes slack
			target = 0.02
			run = 0.0 if exhausted else float(s["speed"]) * float(cfg["swim_off"]) * vigor * 1.5
		else: ## she only holds the rod: the fish gets its breath back and edges away
			run = 0.0 if exhausted else float(s["speed"]) * float(cfg["swim_off"]) * vigor
			stamina += float(cfg["recover"]) * delta
		tension += (target - tension) * minf(1.0, k * delta)
		var last_rush: bool = bool(s.get("last_run", false)) and not bool(d["last"]) and not exhausted and stamina > 0.2 and dist < float(cfg["last_run"])
		if not exhausted and float(d["dur"]) - float(d["t"]) <= float(d.get("tell_time", cfg["tell_time"])):
			d["tell"] = true
		if last_rush or (not exhausted and float(d["t"]) >= float(d["dur"])):
			var flee: Array = s["flee"] as Array
			d["phase"] = "flee"
			d["t"] = 0.0
			d["dur"] = rng.randf_range(float(flee[0]), float(flee[1])) * (0.6 if last_rush else 1.0)
			d["fled"] = int(d["fled"]) + 1 ## the component turns the fish to a new heading
			if last_rush:
				d["last"] = true
	stamina = clampf(stamina - drain * delta / maxf(float(d["endurance"]), 0.1), 0.0, 1.0)
	d["stamina"] = stamina
	d["run"] = run
	d["pull_in"] = pull_in
	if integrate:
		dist += (run - pull_in) * delta
	tension = clampf(tension, 0.0, 1.3)
	d["tension"] = tension
	d["dist"] = dist
	var limit: float = minf(1.0, float(s.get("mouth", 1.0)))
	if tension >= limit:
		d["snap"] = float(d["snap"]) + delta
	else:
		d["snap"] = maxf(0.0, float(d["snap"]) - delta * 2.0)
	if tension < float(cfg["slack"]):
		d["slack"] = float(d["slack"]) + delta
	else:
		d["slack"] = maxf(0.0, float(d["slack"]) - delta * 2.0)
	if float(d["snap"]) >= float(cfg["snap_hold"]):
		return "torn" if limit < 1.0 else "snapped"
	if float(d["slack"]) >= float(s.get("hold", 1.2)):
		return "unhooked"
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
