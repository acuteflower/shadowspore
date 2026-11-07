extends Node
## Fishing: rules, balance bots, data consistency (headless). More sections are added below by later steps.
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)


var fight_time: float = 0.0 ## seconds of the last bot fight


## A player who reads only what the game shows (the line's colour, its shiver before a run, whether it runs or not) and
## reacts `lag` seconds late. While the fish runs: hold, give way once the line turns red, stop giving once it is gold
## again. While it tires: crank, but stop at the shiver.
static func reader(d: Dictionary, lag_state: Dictionary, lag: float, delta: float) -> Array:
	var fleeing: bool = String(d["phase"]) == "flee"
	var history: Array = lag_state.get("h", []) as Array
	history.append([fleeing, float(d["tension"]), bool(d["tell"])])
	var keep: int = maxi(1, int(round(lag / delta)) + 1)
	while history.size() > keep:
		history.pop_front()
	lag_state["h"] = history
	var seen: Array = history[0] as Array ## what she saw `lag` seconds ago
	var giving: bool = bool(lag_state.get("giving", false))
	if bool(seen[0]):
		if float(seen[1]) > 0.74:
			giving = true
		elif float(seen[1]) < 0.42:
			giving = false
	else:
		giving = false
	lag_state["giving"] = giving
	return [1.0 if giving else 0.0, not bool(seen[0]) and not bool(seen[2])]


func bot(species: String, mode: String, seed_value: int, size: float = -1.0) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var rod: Dictionary = FishingRules.rods()["rod_basic"] as Dictionary
	var big: float = rng.randf() if size < 0.0 else size
	var d: Dictionary = FishingRules.new_drill(species, rod, rng.randf_range(50.0, 110.0), rng, big)
	var lag_state: Dictionary = {}
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	while t < 90.0:
		t += dt
		var give: float = 0.0
		var reel: bool = false
		match mode:
			"skilled":
				var input: Array = reader(d, lag_state, 0.2, dt)
				give = float(input[0])
				reel = bool(input[1])
			"casual":
				var input: Array = reader(d, lag_state, 0.3, dt)
				give = float(input[0])
				reel = bool(input[1])
			"late": ## reacts almost half a second late to everything
				var input: Array = reader(d, lag_state, 0.42, dt)
				give = float(input[0])
				reel = bool(input[1])
			"never_give": ## just holds the button down the whole time
				reel = true
			"always_give":
				give = 1.0
			"idle":
				pass
			"old_perfect": ## the old recipe: always give during a run, always reel otherwise
				give = 1.0 if String(d["phase"]) == "flee" else 0.0
				reel = String(d["phase"]) != "flee" and not bool(d["tell"])
		var result: String = FishingRules.drill_step(d, give, reel, dt, rod, rng)
		if result != "":
			fight_time = t
			return result
	fight_time = t
	return "timeout"


func rate(species: String, mode: String, outcome: String) -> float:
	var n: int = 0
	for i: int in 40:
		if bot(species, mode, 1000 + i) == outcome:
			n += 1
	return float(n) / 40.0


func mean_time(species: String, mode: String) -> float:
	var sum: float = 0.0
	var n: int = 0
	for i: int in 40:
		if bot(species, mode, 2000 + i) == "landed":
			sum += fight_time
			n += 1
	return sum / maxf(1.0, float(n))


func rules_checks() -> void:
	var table: Dictionary = FishingRules.species_table()
	var ids: Array = table.keys()
	var items: Dictionary = DataRegistry.table("items")
	# data consistency: every picture, item and list the game code relies on
	check(FishingView.ORDER == Array(ids, TYPE_STRING, "", null), "FishingView.ORDER follows fishing.json")
	check(FishCard.ORDER == Array(ids, TYPE_STRING, "", null), "FishCard.ORDER follows fishing.json")
	check(RiverBook.ORDER == Array(ids, TYPE_STRING, "", null), "RiverBook.ORDER follows fishing.json")
	check((load("res://assets/fishing/fish_side.png") as Texture2D).get_height() == 24 * ids.size(), "fish_side.png has a row per species")
	check((load("res://assets/fishing/fish_shadow.png") as Texture2D).get_height() == 32 * ids.size(), "fish_shadow.png has a row per species")
	for id: String in ids:
		var spec: Dictionary = table[id]
		var item: String = String(spec["item"])
		check(items.has(item), id + ": item exists")
		check(ResourceLoader.exists(String((items[item] as Dictionary)["icon"])), id + ": icon exists")
		check(["common", "uncommon", "rare", "epic", "legendary"].has(String(spec["rarity"])), id + ": known rarity")
		for bait: String in (spec["baits"] as Dictionary):
			check(bait == "" or items.has(bait), id + ": bait item exists: " + bait)
	for pose: String in FishingRules.poses():
		var needs: String = String((FishingRules.poses()[pose] as Dictionary)["needs"])
		check(needs == "" or items.has(needs), pose + ": needed item exists")
	for rod: String in FishingRules.rods():
		check(items.has(rod) and String((items[rod] as Dictionary)["tool"]) == "rod", rod + ": is a rod item")
		check(ResourceLoader.exists(String((items[rod] as Dictionary)["held"]).replace("_held.png", "_held_rot.png")), rod + ": baked held sheet exists")
	for key: String in ["fish_bait", "fish_pose", "fish_book"]:
		check(InputMap.has_action(key), "input action " + key)
	for wav: String in ["cast", "splash", "tap", "bite", "snap", "landed", "creak"]:
		check(ResourceLoader.exists("res://assets/audio/fishing/%s.wav" % wav), "sound " + wav)
	# the body clips of player_fish.png and their rig
	var rig: Dictionary = DataRegistry.table("hero_rig").get("fish", {}) as Dictionary
	check(not rig.is_empty(), "hero_rig.json has the fishing rig")
	var cols: int = int(rig.get("cols", 0))
	var clip_total: int = 0
	for clip_name: String in ["ready", "cast", "strike", "flee", "brace", "reel", "land", "snap", "sag"]:
		var clip: Dictionary = (rig["clips"] as Dictionary).get(clip_name, {}) as Dictionary
		check(not clip.is_empty() and int(clip["start"]) == clip_total, "clip " + clip_name + " starts where the last ended")
		clip_total += int(clip.get("count", 0))
	check(clip_total == cols and (rig["hand"] as Array).size() == 8 * cols and (rig["shoulder"] as Array).size() == 8 * cols and (rig["rod"] as Array).size() == cols, "rig arrays match 8 views x %d frames" % cols)
	check(int(rig["release"]) < int(((rig["clips"] as Dictionary)["cast"] as Dictionary)["count"]), "the release frame lies inside the cast clip")
	var windup: float = float((FishingRules.settings()["cast"] as Dictionary)["windup"])
	var cast_clip: Dictionary = (rig["clips"] as Dictionary)["cast"] as Dictionary
	check(absf(float(int(rig["release"])) / float(cast_clip["fps"]) - windup) < 0.02, "the host's wind-up equals the release frame's time")
	check((load("res://assets/characters/player_fish.png") as Texture2D).get_width() == cols * 48, "player_fish.png is %d frames wide" % cols)
	for species_id: String in ids:
		check((table[species_id] as Dictionary)["speed"] >= 15.0, species_id + ": a fish that really swims off")
	# which fish are interested
	var shallow: Dictionary = {"x": -20.0, "y": 0.2, "flow": 0.1, "night": 0.0, "light_depth": -9999.0, "bait": "dusk_berry", "pose": "cork"}
	var day: Dictionary = FishingRules.weights(shallow)
	check(day.has("silverling") and not day.has("veil_eel") and not day.has("glimmer_loach"), "day, shallow, berry: silverlings, no night fish")
	var night_shallow: Dictionary = shallow.duplicate()
	night_shallow["night"] = 1.0
	check(not FishingRules.weights(night_shallow).has("silverling") and FishingRules.weights(night_shallow).has("glimmer_loach"), "night: the glimmer loach comes, the silverling is gone")
	var deep: Dictionary = {"x": -30.0, "y": 0.9, "flow": 0.1, "night": 1.0, "light_depth": -200.0, "bait": "glow_cap", "pose": "cork"}
	check(FishingRules.weights(deep).has("veil_eel") and FishingRules.weights(deep).has("abyss_pike"), "deep, night, dark: the veil fish bite")
	var lit: Dictionary = deep.duplicate()
	lit["light_depth"] = 10.0
	check(not FishingRules.weights(lit).has("veil_eel") and not FishingRules.weights(lit).has("abyss_pike"), "inside a light the deep fish do not bite")
	var edge: Dictionary = deep.duplicate()
	edge["light_depth"] = -20.0
	check(not FishingRules.weights(edge).has("veil_eel"), "near the edge of a light (less than 32 px) they still stay away")
	var glow: Dictionary = deep.duplicate()
	glow["pose"] = "glimmer"
	check(not FishingRules.weights(glow).has("veil_eel"), "a glowing float scares the deep fish even in the dark")
	var obsidian: Dictionary = deep.duplicate()
	obsidian["pose"] = "obsidian"
	check(float(FishingRules.weights(obsidian)["veil_eel"]) > float(FishingRules.weights(deep)["veil_eel"]), "the obsidian float favours the deep fish")
	var calm: Dictionary = {"x": -30.0, "y": 0.3, "flow": 0.2, "night": 0.0, "light_depth": -9999.0, "bait": "brook_mint", "pose": "cork"}
	check(FishingRules.weights(calm).has("gold_carp"), "the carp lives in calm water")
	calm["flow"] = 0.7
	check(not FishingRules.weights(calm).has("gold_carp"), "no carp in a strong current")
	var scared: Dictionary = shallow.duplicate()
	scared["scared"] = ["silverling"]
	check(not FishingRules.weights(scared).has("silverling"), "a scared species stays away")
	var no_water: Dictionary = shallow.duplicate()
	no_water["x"] = INF
	check(FishingRules.weights(no_water).is_empty(), "no fish outside the river")
	var bare: Dictionary = {"x": -20.0, "y": 0.5, "flow": 0.1, "night": 0.0, "light_depth": -9999.0, "bait": "", "pose": "cork"}
	var cap: Dictionary = bare.duplicate()
	cap["bait"] = "glow_cap"
	check(float(FishingRules.weights(cap)["copper_loach"]) > float(FishingRules.weights(bare)["copper_loach"]), "the glow cap draws the loach")
	# every kind of water holds something by day and by night (the old tables left the deep channel empty by day)
	for depth: float in [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]:
		for x: float in [-4.0, -8.0, -14.0, -24.0]:
			for n: float in [0.0, 1.0]:
				var any: Dictionary = {"x": x, "y": depth, "flow": FishingRules.current_strength(x, false, false), "night": n, "light_depth": -9999.0, "bait": "", "pose": "cork"}
				check(FishingRules.total(FishingRules.weights(any)) > 0.1, "something lives at x %.0f, depth %.1f, night %.0f (%s)" % [x, depth, n, FishingRules.weights(any)])
	var deep_day: Dictionary = {"x": -22.0, "y": 0.95, "flow": 1.0, "night": 0.0, "light_depth": -9999.0, "bait": "", "pose": "cork"}
	check(FishingRules.weights(deep_day).has("moon_trout") and FishingRules.weights(deep_day).has("copper_loach"), "the deep channel by day: trout and loach")
	check(not FishingRules.weights(deep_day).has("silverling"), "no silverlings out in the deep")
	check(FishingRules.fit(0.5, [0.0, 0.4], 0.25) > 0.0 and FishingRules.fit(0.5, [0.0, 0.4], 0.25) < 1.0 and FishingRules.fit(0.2, [0.0, 0.4], 0.25) == 1.0, "habitats fade softly")
	# the current: slack by the bank, strong in the channel, still in lakes
	check(FishingRules.current_strength(-5.0, false, false) < 0.4 and FishingRules.current_strength(-20.0, false, false) > 0.95, "slack water by the bank, the full current in the channel")
	check(FishingRules.current_strength(-30.0, true, false) < 0.15 and FishingRules.current_strength(-20.0, false, true) < 0.2, "lakes and pools are still")
	var edge_calm: Dictionary = {"x": -7.0, "y": 0.35, "flow": FishingRules.current_strength(-7.0, false, false), "night": 0.0, "light_depth": -9999.0, "bait": "marsh_gold", "pose": "cork"}
	check(FishingRules.weights(edge_calm).has("gold_carp"), "the carp finds the slack water along a real river bank")
	# how lively the fish are: the angler right above them, the hour, a fished-out spot
	var act: Dictionary = {"y": 0.5, "reach": 100.0, "sun": 0.0, "golden": 0.0, "pressure": 0.0}
	var near_act: Dictionary = act.duplicate()
	near_act["reach"] = 30.0
	check(FishingRules.activity(near_act) < FishingRules.activity(act) * 0.6, "fish right under her feet are wary")
	var dusk_act: Dictionary = act.duplicate()
	dusk_act["golden"] = 1.0
	check(FishingRules.activity(dusk_act) > FishingRules.activity(act) * 1.3, "dawn and dusk are feeding time")
	var noon_shallow: Dictionary = act.duplicate()
	noon_shallow["sun"] = 1.0
	noon_shallow["y"] = 0.1
	check(FishingRules.activity(noon_shallow) < FishingRules.activity(act) * 0.8, "noon sun drives the fish out of the shallows")
	var pressed: Dictionary = act.duplicate()
	pressed["pressure"] = 0.6
	check(FishingRules.activity(pressed) < FishingRules.activity(act) * 0.5, "a fished-out spot goes quiet")
	check(FishingRules.refuse_chance("gold_carp", "marsh_gold", 0.0, false) < 0.05 and FishingRules.refuse_chance("gold_carp", "", 0.0, false) > 0.3, "the cautious carp turns away from a bare hook, not from its bait")
	check(FishingRules.refuse_chance("abyss_pike", "", 0.0, true) < FishingRules.refuse_chance("abyss_pike", "", 0.0, false), "a twitch makes a hunter forget its caution")
	# timing, lengths, colours
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var waits: Array[float] = []
	for i: int in 400:
		waits.append(FishingRules.bite_delay(1.0, rng))
	waits.sort()
	check(waits[0] >= 2.5 and waits[200] > 6.0 and waits[200] < 14.0 and waits[380] > 18.0, "a fair spot: never before the fish settle, about ten seconds, sometimes long (%.1f / %.1f / %.1f)" % [waits[0], waits[200], waits[380]])
	var shallow_len: float = 0.0
	var deep_len: float = 0.0
	for i: int in 300:
		shallow_len += FishingRules.roll_length("copper_loach", rng, 0.2)
		deep_len += FishingRules.roll_length("copper_loach", rng, 1.0)
	check(deep_len > shallow_len * 1.08, "the big ones live in deep water")
	var slow: float = 0.0
	var quick: float = 0.0
	for i: int in 200:
		slow += FishingRules.bite_delay(0.3, rng)
		quick += FishingRules.bite_delay(3.0, rng)
	check(quick < slow, "more interest, faster bite")
	for id: String in ids:
		var range_a: Array = (table[id] as Dictionary)["length"] as Array
		var strike: Array = (table[id] as Dictionary)["strike"] as Array
		for i: int in 20:
			var length: float = FishingRules.roll_length(id, rng)
			check(length >= float(range_a[0]) and length <= float(range_a[1]), id + ": length within range")
			var window: float = FishingRules.strike_window(id, rng)
			check(window >= float(strike[0]) and window <= float(strike[1]), id + ": strike window within range")
	var slack: Color = FishingRules.line_color(0.02)
	var good: Color = FishingRules.line_color(0.45)
	var danger: Color = FishingRules.line_color(1.0)
	check(slack != good and good != danger and slack != danger, "slack, good and danger lines have three different colours")
	check(slack.is_equal_approx(Color("3cc0c6")) and danger.is_equal_approx(Color("ff4a63")) and good.is_equal_approx(Color("e6c468")), "line colours are the configured petrol, gold and red")
	check(danger.r > danger.g and slack.b > slack.r, "red is red, petrol is bluish")
	check(FishingRules.line_jitter(0.3, false) == 0.0 and FishingRules.line_jitter(0.95, false) > 0.5 and FishingRules.line_jitter(0.1, true) > 0.5, "the line trembles only near danger or before a run")
	# the river book
	var path: String = "user://fish_book_rules_only.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var book: FishBook = FishBook.new(path)
	check(book.species.is_empty(), "a new book is empty")
	check(book.record("moon_trout", 30, 2), "first catch is a record")
	check(not book.record("moon_trout", 20, 3), "a shorter catch is no record")
	check(book.record("moon_trout", 44, 4), "a longer catch is a record")
	check(not book.record("not_a_fish", 10, 1), "unknown species are ignored")
	var again: FishBook = FishBook.new(path)
	var entry: Dictionary = again.species["moon_trout"] as Dictionary
	check(int(entry["caught"]) == 3 and int(entry["best"]) == 44 and int(entry["first_day"]) == 2, "count, best length and first day survive a reload")
	var broken: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	broken.store_string("{not json")
	broken.close()
	check(FishBook.new(path).species.is_empty(), "a damaged book file is ignored, not fatal")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	var table: Dictionary = FishingRules.species_table()
	var report: String = ""
	var strong_late: float = 0.0
	var strong_n: int = 0
	for id: String in table:
		var skilled: float = rate(id, "skilled", "landed")
		var casual: float = rate(id, "casual", "landed")
		var late: float = rate(id, "late", "landed")
		var yank: float = rate(id, "never_give", "landed")
		var old: float = rate(id, "old_perfect", "landed")
		var lazy: float = rate(id, "always_give", "landed")
		var idle: float = rate(id, "idle", "landed")
		var secs: float = mean_time(id, "skilled")
		report += "%s skilled %.2f (%.1f s) casual %.2f late %.2f yank %.2f old-recipe %.2f give %.2f idle %.2f\n" % [id, skilled, secs, casual, late, yank, old, lazy, idle]
		check(skilled >= 0.85, id + ": someone who reads the line lands it (>=85%%): %.2f" % skilled)
		check(late >= 0.25, id + ": reacting half a second late still lands some: %.2f" % late)
		if float((table[id] as Dictionary)["pull"]) >= 0.6:
			strong_late += late
			strong_n += 1
		check(yank <= 0.2, id + ": holding the button down the whole time rarely lands it: %.2f" % yank)
		check(lazy <= 0.05, id + ": always giving line never lands it: %.2f" % lazy)
		check(idle <= 0.05, id + ": doing nothing never lands it: %.2f" % idle)
		check(secs >= 4.0 and secs <= 40.0, id + ": a fight takes a while (%.1f s)" % secs)
	check(strong_late / maxf(1.0, float(strong_n)) <= 0.8, "with the strong fish, a late hand loses a good share (%.2f landed)" % (strong_late / maxf(1.0, float(strong_n))))
	var small: float = 0.0
	var big: float = 0.0
	for i: int in 30:
		bot("moon_trout", "skilled", 3000 + i, 0.0)
		small += fight_time
		bot("moon_trout", "skilled", 3000 + i, 1.0)
		big += fight_time
	check(big > small * 1.15, "a big trout fights longer than a small one (%.1f vs %.1f s)" % [big / 30.0, small / 30.0])
	var d: Dictionary = FishingRules.new_drill("gold_carp", FishingRules.rods()["rod_basic"] as Dictionary, 80.0, RandomNumberGenerator.new(), 0.5)
	var runs_seen: Array[float] = []
	var rng_runs: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_runs.seed = 5
	var lag: Dictionary = {}
	for i: int in 60 * 60:
		var input: Array = reader(d, lag, 0.2, 1.0 / 60.0)
		if FishingRules.drill_step(d, float(input[0]), bool(input[1]), 1.0 / 60.0, FishingRules.rods()["rod_basic"] as Dictionary, rng_runs, false) != "":
			break
		if String(d["phase"]) == "flee" and float(d["t"]) < 0.02:
			runs_seen.append(float(d["stamina"]))
	check(runs_seen.size() >= 2 and runs_seen[runs_seen.size() - 1] < runs_seen[0], "every run leaves the carp weaker (%s)" % [runs_seen])
	var limp: Dictionary = FishingRules.new_drill("silverling", FishingRules.rods()["rod_basic"] as Dictionary, 80.0, RandomNumberGenerator.new(), 0.5)
	limp["phase"] = "tire"
	limp["dur"] = 99.0
	var limp_result: String = ""
	for i: int in 60 * 4:
		limp_result = FishingRules.drill_step(limp, 1.0, false, 1.0 / 60.0, FishingRules.rods()["rod_basic"] as Dictionary, RandomNumberGenerator.new())
		if limp_result != "":
			break
	check(limp_result == "unhooked", "a slack line lets the fish shake the hook (%s)" % limp_result)
	print(report)
	rules_checks()
	print("Fishing tests: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
