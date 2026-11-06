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


func bot(species: String, mode: String, seed_value: int) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var rod: Dictionary = FishingRules.rods()["rod_basic"] as Dictionary
	var d: Dictionary = FishingRules.new_drill(species, rod, rng.randf_range(50.0, 110.0), rng)
	var t: float = 0.0
	while t < 40.0:
		t += 1.0 / 60.0
		var fleeing: bool = String(d["phase"]) == "flee"
		var give: float = 0.0
		var reel: bool = false
		match mode:
			"perfect":
				give = 1.0 if fleeing else 0.0
				reel = not fleeing and not bool(d["tell"])
			"never_give":
				reel = true
			"always_give":
				give = 1.0
			"late":  ## reacts a quarter second late to every change of phase
				var lag_flee: bool = fleeing and float(d["t"]) > 0.25
				give = 1.0 if lag_flee else 0.0
				reel = not fleeing and float(d["t"]) > 0.25 and not bool(d["tell"])
		var result: String = FishingRules.drill_step(d, give, reel, 1.0 / 60.0, rod, rng)
		if result != "":
			return result
	return "timeout"


func rate(species: String, mode: String, outcome: String) -> float:
	var n: int = 0
	for i: int in 30:
		if bot(species, mode, 1000 + i) == outcome:
			n += 1
	return float(n) / 30.0


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
	# timing, lengths, colours
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
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
	for id: String in table:
		var perfect: float = rate(id, "perfect", "landed")
		var late: float = rate(id, "late", "landed")
		var yank: float = rate(id, "never_give", "snapped")
		var lazy: float = rate(id, "always_give", "escaped")
		report += "%s perfect %.2f late %.2f yank-snap %.2f give-escape %.2f\n" % [id, perfect, late, yank, lazy]
		check(perfect >= 0.9, id + ": a good fighter lands it (>=90%%): %.2f" % perfect)
		check(late >= 0.6, id + ": a slightly late fighter still often lands it: %.2f" % late)
		if float((table[id] as Dictionary)["pull"]) >= 0.7:
			check(yank >= 0.8, id + ": a strong fish snaps the line of someone who never gives way: %.2f" % yank)
		check(rate(id, "always_give", "landed") <= 0.1, id + ": never reeling never lands it")
	print(report)
	rules_checks()
	print("Fishing tests: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
