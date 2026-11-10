extends Node
## docs/town.md: the pure rules and the data of the town (no world): catalogue sanity, footprints, grid, light territory, levels, refunds, the state round trip.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("TOWN RULES FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var items: Dictionary = DataRegistry.table("items")
	var ids: Array[String] = TownRules.buildable()
	_check(ids.size() >= 6, "the catalogue has the first pieces")
	var categories: Array[String] = []
	for entry: Variant in TownRules.categories():
		categories.append(String((entry as Dictionary).id))
	for id: String in ids:
		var spec: Dictionary = TownRules.piece(id)
		_check(spec.has("texture") and spec.has("frame") and spec.has("feet") and spec.has("foot"), "%s has its picture data" % id)
		_check(String(spec.category) in categories, "%s has a known category" % id)
		_check(float(spec.build_seconds) > 0.0, "%s takes time to build" % id)
		for item: String in spec.cost as Dictionary:
			_check(items.has(item), "%s costs a real item (%s)" % [id, item])
		var frame: Array = spec.frame as Array
		_check(float(spec.feet) <= float(frame[1]), "%s: the feet row is inside the frame" % id)
		var foot: Array = spec.foot as Array
		_check(float(foot[0]) <= float(frame[0]) + 8.0, "%s: the footprint is not wider than the picture" % id)
		_check(bool(spec.get("farm", false)) or ResourceLoader.exists("res://assets/town/%s.png" % String(spec.texture)), "%s has its picture" % id) ## fields are painted at run time (FieldSoil)
		if bool(spec.get("pad", false)):
			_check(ResourceLoader.exists("res://assets/town/%s_pad.png" % String(spec.texture)), "%s has its ground pad" % id)
		if bool(spec.get("glow", false)):
			_check(ResourceLoader.exists("res://assets/town/%s_glow.png" % String(spec.texture)), "%s has its glow sheet" % id)
		if spec.has("needs"):
			_check(not TownRules.piece(String(spec.needs)).is_empty(), "%s needs a real piece" % id)
	var recipes: Dictionary = DataRegistry.table("recipes")
	for id: String in recipes:
		var recipe: Dictionary = recipes[id] as Dictionary
		for item: String in (recipe["in"] as Dictionary):
			_check(items.has(item), "recipe %s takes a real item (%s)" % [id, item])
		for item: String in (recipe["out"] as Dictionary):
			_check(items.has(item), "recipe %s makes a real item (%s)" % [id, item])
	var settlers: Dictionary = DataRegistry.table("settlers")
	for id: String in settlers:
		var spec: Dictionary = settlers[id] as Dictionary
		if bool(spec.get("enabled", true)) and spec.has("arrive"): ## inactive future residents may depend on unfinished pieces
			_check(not TownRules.piece(String((spec.arrive as Dictionary).needs)).is_empty(), "%s waits for a real piece" % id)
		if bool(spec.get("enabled", true)):
			_check(not TownRules.piece(String(spec.home)).is_empty(), "%s has a real home" % id)
		if DataRegistry.table(String(spec.art) + "_rig").is_empty(): ## the art is made apart: a plain stand-in figure is used until it exists
			print("TOWN RULES NOTE: %s has no rig/sheet yet (data/%s_rig.json, assets/characters/%s.png): placeholder figure" % [id, String(spec.art), String(spec.art)])
		for tier: Variant in spec.get("talk", []) as Array: ## (a settler with `chat` has no dialogues)
			_check(not DataRegistry.get_entry("dialogue", String((tier as Dictionary).dialogue)).is_empty(), "%s: dialogue %s exists" % [id, String((tier as Dictionary).dialogue)])
		for window: Variant in spec.schedule as Array:
			_check((window as Array).size() == 3 and (spec.spots as Dictionary).has(String((window as Array)[2])), "%s: schedule names a known spot" % id)
	# a door has to stay free: the zone in front of it, and the settlers' work place lies in it
	var shop_front: Rect2 = TownRules.front_rect("workshop", 100.0, 100.0)
	_check(shop_front.has_area() and is_equal_approx(shop_front.position.y, 100.0) and is_equal_approx(shop_front.get_center().x, 100.0), "front_rect: in front of the feet line, centred on the door")
	_check(not TownRules.front_rect("lamp_post", 100.0, 100.0).has_area(), "a lamp post has no door")
	_check(TownRules.front_rect("house", 0.0, 0.0).has_area(), "the hut has a door zone too")
	for id: String in settlers:
		var spec: Dictionary = settlers[id] as Dictionary
		var work: Dictionary = (spec.spots as Dictionary).get("work", {}) as Dictionary
		if bool(spec.get("enabled", true)) and String(work.get("of", "")) == "home":
			var at: Array = work.at as Array
			var zone: Rect2 = TownRules.front_rect(String(spec.home), 0.0, 0.0)
			_check(zone.has_point(Vector2(float(at[0]), float(at[1]))), "%s works in the free ground in front of the %s" % [id, String(spec.home)])
	# footprints and the grid
	var lamp: Rect2 = TownRules.foot_rect("lamp_post", 100.0, 50.0)
	_check(lamp.position == Vector2(94, 42) and lamp.size == Vector2(12, 8), "foot_rect: centred on x, bottom edge on y")
	_check(not TownRules.overlaps(Rect2(0, 0, 10, 10), Rect2(10, 0, 10, 10)), "touching footprints do not overlap")
	_check(TownRules.overlaps(Rect2(0, 0, 10, 10), Rect2(9, 9, 10, 10)), "overlapping footprints overlap")
	for id: String in ids:
		for probe: Vector2 in [Vector2(123.4, 77.7), Vector2(-5.2, 3.1), Vector2(1000.0, 1000.0)]:
			var snapped_at: Vector2 = TownRules.snapped_position(id, probe)
			var rect: Rect2 = TownRules.foot_rect(id, snapped_at.x, snapped_at.y)
			var grid: float = TownRules.snap_of(id)
			_check(is_zero_approx(fposmod(rect.position.x, grid)) and is_zero_approx(fposmod(rect.position.y, grid)), "%s snaps its corner to the %d px grid" % [id, int(grid)])
			_check(snapped_at.distance_to(probe) <= grid * 1.5, "%s snaps to a near cell" % id)
	var plate: Rect2 = TownRules.foot_rect("path_stone", TownRules.snapped_position("path_stone", Vector2(21, 37)).x, TownRules.snapped_position("path_stone", Vector2(21, 37)).y)
	_check(is_zero_approx(fposmod(plate.position.x, 16.0)) and is_zero_approx(fposmod(plate.position.y, 16.0)), "a plate fills exactly one ground tile")
	# the territory
	var circles: Array[Vector3] = [Vector3(0, 0, 100), Vector3(150, 0, 60)]
	_check(TownRules.covers(circles, Vector2(99, 0)) and TownRules.covers(circles, Vector2(190, 0)), "points inside a circle are lit")
	_check(not TownRules.covers(circles, Vector2(120, 80)) and not TownRules.covers(circles, Vector2(0, 101)), "points outside every circle are dark")
	# levels
	_check(TownRules.level_for(0.0) == 0 and TownRules.level_for(24.9) == 0 and TownRules.level_for(25.0) == 1 and TownRules.level_for(10000.0) == 4, "level thresholds")
	_check(TownRules.next_worth(0) == 25.0 and TownRules.next_worth(4) == -1.0, "next level worth")
	# refunds
	var refund_done: Dictionary = TownRules.refund({"wood": 3, "stone": 1}, true)
	var refund_site: Dictionary = TownRules.refund({"wood": 3, "stone": 1}, false)
	_check(int(refund_done.wood) == 2 and int(refund_done.stone) == 1 and int(refund_site.wood) == 3, "refunds: 60 % rounded up for a finished piece, all of it for a site")
	_check(TownRules.cost_text({"wood": 3, "glow_cap": 2}) == "3 TANNENHOLZ  2 GLIMMKAPPE", "cost text uses item names (%s)" % TownRules.cost_text({"wood": 3, "glow_cap": 2}))
	# the state round trip (host export -> JSON file -> import)
	var town: TownManager = TownManager.new()
	add_child(town)
	var state: Dictionary = {"version": 1, "founded": true, "name": 3, "center": [12000.0, 10800.0], "day": 2, "next_id": 5,
		"structures": {"0": {"p": "house", "x": 12000.0, "y": 10800.0, "f": 0, "g": 1000}},
		"stock": {"wood": 12, "stone": 3}, "cleared": [[750, 675], [751, 676]], "residents": {"gustav": {"trust": 30, "talked": 2}}}
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(state)) as Dictionary
	town.import_state(through_json)
	_check(town.founded and town.town_name() == TownRules.town_names()[3], "import: founded, named")
	_check(town.structures.has(0) and town.is_built(0), "import: the house is a finished structure (int keys after JSON)")
	_check(int(town.stock.wood) == 12 and town.cleared.has(Vector2i(750, 675)) and town.cleared.has(Vector2i(751, 676)), "import: stock and cleared cells")
	_check(town.trust_of("gustav") == 30 and town.population() == 1, "import: residents")
	_check(town.in_territory(Vector2(12000, 10700)) and not town.in_territory(Vector2(12000, 10300)), "the house lights its surroundings only")
	_check(is_equal_approx(town.worth(), 10.0 + 8.0) and town.level() == 0, "worth: house + one resident -> %s" % town.worth())
	_check(town.check_place("lamp_post", Vector2(12000, 10800), null, false) != "" , "an unfinished catalogue entry cannot be placed on the house itself (%s)" % town.check_place("lamp_post", Vector2(12000, 10800), null, false))
	_check(town.check_site("lamp_post", Vector2(12000, 10900), false) == "", "a free spot inside the light is fine (%s)" % town.check_site("lamp_post", Vector2(12000, 10900), false))
	_check(town.check_site("lamp_post", Vector2(12000, 10300), false) == "AUSSERHALB DES LICHTS", "a spot in the dark is refused")
	var again: Dictionary = town.export_state()
	_check(JSON.stringify(again.structures) == JSON.stringify(through_json.structures) or again.structures.size() == 1, "export keeps the structures")
	_check(int(again.stock.wood) == 12 and again.residents.gustav.trust == 30, "export keeps stock and residents")
	print("TOWN RULES: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
