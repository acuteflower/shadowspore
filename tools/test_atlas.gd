extends Node
## Tests of the 2.0 atlas core (docs/v2_zonenwelt_atlas_konzept.md, step 2): `Atlas` (zones in real continent
## coordinates, places, thresholds, routes, checks of the data) and `PocketSpace`, plus the real data in data/world/.
## Headless: Godot --headless --path . tools/test_atlas.tscn   (prints ATLAS OK)

var _checks: int = 0
var _failed: int = 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


func _ready() -> void:
	_run.call_deferred()


static func _rect(w: int, h: int) -> Array:
	return [[0, 0], [w, 0], [w, h], [0, h]]


static func _zone(id: String, origin: Array, size: Array, extra: Dictionary = {}) -> Dictionary:
	var data: Dictionary = {
		"id": id, "name": id.to_upper(), "continent": "t", "kind": "field", "size_class": "S",
		"origin": origin, "size": size, "danger": "ruhig",
		"footprint": _rect(int(size[0]), int(size[1])),
	}
	data.merge(extra, true)
	return data


static func _fixture_zones() -> Array[Dictionary]:
	return [
		_zone("a", [100, 100], [120, 120], {"places": [{"id": "hain", "name": "HAIN", "poly": [[10, 10], [50, 10], [50, 50], [10, 50]]}],
			"landmarks": [{"id": "eiche", "kind": "lighthouse", "pos": [60, 60]}]}),
		_zone("b", [224, 100], [120, 120], {"danger": "rau"}),
		_zone("c", [348, 100], [120, 120], {"danger": "wild"}),
		_zone("d", [100, 224], [120, 120], {"unlock": {"flag": "d_open"}}),
		_zone("e", [600, 600], [100, 100]),
	] as Array[Dictionary]


static func _fixture_thresholds() -> Array[Dictionary]:
	return [
		{"id": "ab", "kind": "path", "a": "a", "b": "b", "line": [[222, 150], [222, 166]]},
		{"id": "bc", "kind": "jump", "a": "b", "b": "c", "one_way": true, "line": [[346, 150], [346, 166]]},
		{"id": "ad", "kind": "pass", "a": "a", "b": "d", "open": {"flag": "pass_free"}, "line": [[150, 222], [166, 222]]},
		{"id": "ae", "kind": "tunnel", "a": "a", "b": "e", "line": [[120, 120], [121, 120]]},
	] as Array[Dictionary]


static func _fixture_continents() -> Array[Dictionary]:
	return [{"id": "t", "name": "TEST", "size": [1000, 800], "chart": [0.1, 0.1, 0.5, 0.4]}] as Array[Dictionary]


static func _ids(path: Array[Atlas.Threshold]) -> Array[String]:
	var out: Array[String] = []
	for t: Atlas.Threshold in path:
		out.append(String(t.id))
	return out


static func _has_problem(atlas: Atlas, part: String) -> bool:
	for problem: String in atlas.problems:
		if problem.contains(part):
			return true
	return false


func _run() -> void:
	_test_fixture()
	_test_problems()
	_test_pockets()
	_test_real_data()
	await _test_workers()
	if _failed == 0:
		print("ATLAS OK (%d checks)" % _checks)
	else:
		print("ATLAS FAILED: %d of %d checks" % [_failed, _checks])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_fixture() -> void:
	var atlas: Atlas = Atlas.from_data(_fixture_continents(), _fixture_zones(), _fixture_thresholds())
	_check(atlas.problems.is_empty(), "clean fixture has no problems: %s" % [atlas.problems])
	_check(atlas.zones.size() == 5 and atlas.thresholds.size() == 4, "fixture counts")
	_check(atlas.continent(&"t").chart == Rect2(0.1, 0.1, 0.5, 0.4), "continent chart")
	var t: StringName = &"t"
	# zones in real continent coordinates
	_check(atlas.zone_at(t, Atlas.px_of(Vector2(150, 150))) == &"a", "zone_at a")
	_check(atlas.zone_at(t, Atlas.px_of(Vector2(300, 150))) == &"b", "zone_at b")
	_check(atlas.zone_at(t, Atlas.px_of(Vector2(400, 210))) == &"c", "zone_at c")
	_check(atlas.zone_at(t, Atlas.px_of(Vector2(222, 158))) == &"", "the gap between zones is borderland")
	_check(atlas.zone_at(t, Atlas.px_of(Vector2(5000, 150))) == &"", "off the continent")
	_check(atlas.zone_at(&"nowhere", Vector2(1600, 1600)) == &"", "unknown continent")
	_check(atlas.zone_at(t, PocketSpace.slot_origin(PocketSpace.Lane.ROOM, 3) + Vector2(40, 40)) == &"", "pockets are no zone")
	_check(atlas.is_playable(t, Atlas.px_of(Vector2(650, 650))), "is_playable e")
	_check(not atlas.is_playable(t, Atlas.px_of(Vector2(580, 650))), "not playable beside e")
	var a: Atlas.Zone = atlas.zone(&"a")
	_check(a.origin == Vector2i(100, 100) and a.bbox == Rect2(100, 100, 120, 120), "zone shifted by its origin")
	_check(a.landmarks.size() == 1 and a.landmarks[0].pos == Vector2(160, 160), "landmark shifted by origin")
	_check(a.center().is_equal_approx(Vector2(160, 160)), "zone centre")
	# places
	_check(atlas.place_at(t, Atlas.px_of(Vector2(130, 130))) == &"hain", "place_at hain")
	_check(atlas.place_at(t, Atlas.px_of(Vector2(200, 200))) == &"", "outside every place")
	# thresholds and story gates
	_check(atlas.thresholds_of(&"a").size() == 3 and atlas.thresholds_of(&"c").size() == 1, "thresholds per zone")
	var ab: Atlas.Threshold = atlas.thresholds[&"ab"] as Atlas.Threshold
	var ad: Atlas.Threshold = atlas.thresholds[&"ad"] as Atlas.Threshold
	_check(ab.seamless() and not (atlas.thresholds[&"ae"] as Atlas.Threshold).seamless(), "seamless and hard kinds")
	_check(Atlas.is_threshold_open(ab, {}) and not Atlas.is_threshold_open(ad, {}), "threshold gates")
	_check(Atlas.is_threshold_open(ad, {"pass_free": true}), "gate opens with its flag")
	_check(atlas.is_zone_open(&"a", {}) and not atlas.is_zone_open(&"d", {}) and atlas.is_zone_open(&"d", {"d_open": true}), "zone unlock flags")
	_check(Atlas.crossed(ab, Atlas.px_of(Vector2(220, 158)), Atlas.px_of(Vector2(224, 158))), "crossing the line")
	_check(not Atlas.crossed(ab, Atlas.px_of(Vector2(220, 158)), Atlas.px_of(Vector2(220, 170))), "walking beside the line")
	_check(not Atlas.crossed(ab, Atlas.px_of(Vector2(220, 180)), Atlas.px_of(Vector2(224, 180))), "passing below the line")
	# routes
	_check(_ids(atlas.route(&"a", &"c", {})) == ["ab", "bc"], "route a -> c over b: %s" % [_ids(atlas.route(&"a", &"c", {}))])
	_check(atlas.route(&"c", &"a", {}).is_empty() and not atlas.reachable(&"c", &"a", {}), "a jump is one way")
	_check(_ids(atlas.route(&"b", &"a", {})) == ["ab"], "a path works both ways")
	_check(atlas.route(&"a", &"d", {}).is_empty(), "a closed pass blocks the route")
	_check(_ids(atlas.route(&"a", &"d", {"pass_free": true})) == ["ad"], "the open pass carries it")
	_check(_ids(atlas.route(&"b", &"e", {})) == ["ab", "ae"], "hard thresholds route too")
	_check(atlas.route(&"a", &"a", {}).is_empty() and atlas.reachable(&"a", &"a", {}), "same zone")
	_check(not atlas.reachable(&"a", &"zz", {}), "unknown target")
	# danger and size classes
	_check(is_equal_approx(atlas.danger_scale(&"a"), 1.0) and is_equal_approx(atlas.danger_scale(&"b"), 1.2) and is_equal_approx(atlas.danger_scale(&"c"), 1.4), "danger grades")
	_check(Atlas.size_class_for(Vector2i(120, 90)) == "S" and Atlas.size_class_for(Vector2i(10, 200)) == "M", "size classes S / M")
	_check(Atlas.size_class_for(Vector2i(300, 300)) == "L" and Atlas.size_class_for(Vector2i(500, 40)) == "XL", "size classes L / XL")
	_check(Atlas.size_class_for(Vector2i(50, 50)) == "" and Atlas.size_class_for(Vector2i(700, 10)) == "", "too small / too big")
	# a shortest way when there are two
	var zones: Array[Dictionary] = _fixture_zones()
	var links: Array[Dictionary] = _fixture_thresholds()
	links.append({"id": "ab_far", "kind": "path", "a": "a", "b": "b", "line": [[222, 104], [222, 110]]})
	var two: Atlas = Atlas.from_data(_fixture_continents(), zones, links)
	_check(_ids(two.route(&"a", &"b", {}, Vector2(210, 106))) == ["ab_far"], "the nearer of two thresholds from the start point")
	_check(_ids(two.route(&"a", &"b", {}, Vector2(210, 160))) == ["ab"], "the other from another start point")


func _test_problems() -> void:
	var zones: Array[Dictionary] = _fixture_zones()
	zones.append(_zone("overlap", [150, 150], [120, 120]))
	zones.append(_zone("too_big", [600, 100], [200, 120]))
	zones.append(_zone("outside", [950, 100], [120, 120]))
	zones.append(_zone("odd", [480, 300], [120, 120], {"kind": "castle", "danger": "deadly", "continent": "nope"}))
	zones.append(_zone("a", [700, 700], [100, 100]))
	zones.append(_zone("stray", [100, 500], [120, 120], {"places": [{"id": "far", "poly": [[500, 500], [510, 500], [510, 510]]}], "landmarks": [{"id": "lost", "pos": [900, 900]}]}))
	var links: Array[Dictionary] = _fixture_thresholds()
	links.append({"id": "far", "kind": "path", "a": "a", "b": "c", "line": [[300, 300], [300, 310]]})
	links.append({"id": "ghost", "kind": "path", "a": "a", "b": "nowhere", "line": [[1, 1], [2, 2]]})
	links.append({"id": "weird", "kind": "teleport", "a": "a", "b": "e", "line": [[1, 1], [2, 2]]})
	links.append({"id": "self", "kind": "tunnel", "a": "e", "b": "e"})
	links.append({"id": "ab", "kind": "path", "a": "a", "b": "b", "line": [[222, 150], [222, 166]]})
	var atlas: Atlas = Atlas.from_data(_fixture_continents(), zones, links)
	for part: String in ["zones a and overlap overlap", "too_big: size (200, 120) does not fit class 'S'", "outside reaches outside",
			"odd: unknown continent", "odd: unknown kind", "odd: unknown danger", "zone a twice", "place far lies outside",
			"landmark lost lies outside", "far: its line is not at the edge of a", "ghost joins unknown", "weird: unknown kind",
			"self joins zone e with itself", "threshold ab twice", "zone stray has no threshold"]:
		_check(_has_problem(atlas, part), "problem found: " + part)
	_check(atlas.zone(&"a").origin == Vector2i(100, 100), "a duplicate does not replace the first zone")
	var bent: Array[Dictionary] = [_zone("x", [100, 100], [100, 100], {"footprint": [[0, 0], [130, 0], [130, 100], [0, 100]]})]
	_check(_has_problem(Atlas.from_data(_fixture_continents(), bent, [] as Array[Dictionary]), "footprint is larger"), "footprint beyond size")
	var bare: Dictionary = _zone("bare", [100, 100], [100, 110])
	bare.erase("footprint")
	var plain: Atlas = Atlas.from_data(_fixture_continents(), [bare] as Array[Dictionary], [] as Array[Dictionary])
	_check(plain.problems.is_empty() and plain.zone_at_tile(&"t", Vector2(150, 205)) == &"bare", "no footprint = its size rectangle")


func _test_pockets() -> void:
	var room0: Vector2 = PocketSpace.slot_origin(PocketSpace.Lane.ROOM, 0)
	_check(room0 == PocketSpace.ROOM_ORIGIN, "first room slot")
	_check(PocketSpace.locate(PocketSpace.slot_origin(PocketSpace.Lane.ROOM, 17) + Vector2(5, 5)) == Vector2i(PocketSpace.Lane.ROOM, 17), "locate a room")
	_check(PocketSpace.locate(PocketSpace.slot_origin(PocketSpace.Lane.LARGE, 13) + Vector2(5000, 10)) == Vector2i(PocketSpace.Lane.LARGE, 13), "locate a large slot")
	_check(PocketSpace.locate(Vector2(320, 320)) == Vector2i(-1, -1) and not PocketSpace.is_pocket(Vector2(-20000, 500)), "the continent is no pocket")
	var rects: Array[Rect2] = []
	for lane: PocketSpace.Lane in [PocketSpace.Lane.ROOM, PocketSpace.Lane.LARGE]:
		for i: int in PocketSpace.capacity(lane):
			var r: Rect2 = PocketSpace.slot_rect(lane, i)
			_check(r.end.x <= PocketSpace.LIMIT and r.end.y <= PocketSpace.LIMIT, "slot %d/%d stays in pocket space" % [lane, i])
			rects.append(r)
	var clash: bool = false
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				clash = true
	_check(not clash, "no two pocket slots overlap")
	_check(PocketSpace.capacity(PocketSpace.Lane.ROOM) == 64 and PocketSpace.capacity(PocketSpace.Lane.LARGE) == 36, "capacities")
	_check(PocketSpace.LARGE_SLOT >= 304.0 * Atlas.TILE_PX, "a large slot holds the deepest mine level")
	PocketSpace.clear_pockets()
	var r0: Rect2 = PocketSpace.slot_rect(PocketSpace.Lane.ROOM, 0)
	PocketSpace.register_pocket(&"test_hut", r0, &"windkap")
	_check(PocketSpace.pocket_id_at(r0.position + Vector2(32.0, 32.0)) == &"test_hut", "pocket_id_at finds registered pocket")
	_check(PocketSpace.parent_zone_at(r0.position + Vector2(32.0, 32.0)) == &"windkap", "parent_zone_at resolves parent zone")
	_check(PocketSpace.parent_zone_at(Vector2(1600.0, 1600.0)) == &"", "parent_zone_at empty outside pockets")
	_check(PocketSpace.pockets_of_zone(&"windkap").has(&"test_hut"), "pockets_of_zone lists zone pockets")
	PocketSpace.unregister_pocket(&"test_hut")
	_check(PocketSpace.parent_zone_at(r0.position + Vector2(32.0, 32.0)) == &"", "unregister_pocket clears pocket")
	PocketSpace.register_pocket(&"bad_positive", Rect2(100.0, 100.0, 500.0, 500.0), &"windkap")
	_check(not PocketSpace.pockets_of_zone(&"windkap").has(&"bad_positive"), "register_pocket rejects non-pocket rect")


func _test_real_data() -> void:
	Atlas.forget()
	var atlas: Atlas = Atlas.shared()
	_check(atlas.problems.is_empty(), "data/world has no problems: %s" % [atlas.problems])
	_check(atlas == Atlas.shared(), "shared() is cached")
	_check(atlas.continents.has(&"lab") and atlas.zones.has(&"labor_wiese") and atlas.zones.has(&"labor_wald"), "lab zones loaded")
	var meadow: Atlas.Zone = atlas.zone(&"labor_wiese")
	var oak: Vector2 = Atlas.px_of(meadow.landmarks[0].pos)
	_check(atlas.zone_at(&"lab", oak) == &"labor_wiese", "the oak stands in the meadow")
	_check(atlas.place_at(&"lab", Atlas.px_of(Vector2(1050, 960))) == &"bluetenmulde", "the hollow of blossoms")
	_check(_ids(atlas.route(&"labor_wiese", &"labor_wald", {})) == ["labor_kronengang"], "meadow -> wood over the canopy path")
	_check(Atlas.size_class_for(meadow.size) == meadow.size_class, "meadow size class")
	_check(atlas.continents.has(&"main"), "main continent loaded")
	var main_size: Vector2 = Atlas.px_of(Vector2(atlas.continent(&"main").size))
	_check(main_size.x < 65536.0 and main_size.y < 65536.0, "the continent stays inside precise float range")
	if atlas.zones.has(&"windkap"):
		_check(atlas.zone(&"windkap").continent == &"main" and not atlas.zones_of(&"main").is_empty(), "ALTMARK windkap registered on main")


func _test_workers() -> void:
	var atlas: Atlas = Atlas.shared()
	var count: int = 4096
	var answers: Array[String] = []
	answers.resize(count)
	Jobs.parallel_for(count, func(i: int) -> void:
		var tile: Vector2 = Vector2(990.0 + float(i % 64) * 5.0, 870.0 + float(i >> 6) * 3.0)
		answers[i] = String(atlas.zone_at_tile(&"lab", tile)))
	var same: bool = true
	for i: int in count:
		var tile: Vector2 = Vector2(990.0 + float(i % 64) * 5.0, 870.0 + float(i >> 6) * 3.0)
		if answers[i] != String(atlas.zone_at_tile(&"lab", tile)):
			same = false
	_check(same, "workers get the same answers as the main thread")
	var started: int = Time.get_ticks_usec()
	var hits: int = 0
	for i: int in 100000:
		if atlas.zone_at_tile(&"lab", Vector2(990.0 + float(i % 330), 860.0 + float(i % 170))) != &"":
			hits += 1
	var usec: float = float(Time.get_ticks_usec() - started) / 100000.0
	print("zone_at_tile: %.2f us per query (%d hits)" % [usec, hits])
	_check(usec < 20.0, "zone_at is cheap")
	await get_tree().process_frame
