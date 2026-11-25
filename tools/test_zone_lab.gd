extends Node
## Headless test of the zone lab (docs/v2_zonenwelt_atlas_konzept.md 13, step 3): builds zones from data/world/,
## streams the forest in the background while the player walks up, opens the seamless threshold, hands the player to
## the next zone, unloads a zone with its tree state, catches up missed days and round-trips the save block.
##   Godot --headless --path . tools/test_zone_lab.tscn      (prints "ZONE LAB OK (n checks)")

const LAB: String = "res://tools/zone_lab.tscn"

var _checks: int = 0
var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("FAIL: " + what)
		print("FAIL: ", what)


func _ready() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


## Wait until `cond` is true (or `seconds` pass); returns whether it came true. Tracks the longest frame meanwhile.
func _until(cond: Callable, seconds: float) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _run() -> void:
	var t_all: int = Time.get_ticks_msec()
	var atlas: Atlas = Atlas.shared()
	_check(atlas.problems.is_empty(), "atlas data has no problems: %s" % [atlas.problems])
	var wiese: Atlas.Zone = atlas.zone(&"labor_wiese")
	var wald: Atlas.Zone = atlas.zone(&"labor_wald")
	_check(wiese != null and wald != null, "both lab zones exist")
	if wiese == null or wald == null:
		_finish(t_all)
		return

	# --- pure stage build: deterministic, trees inside, grass only on the footprint -------------------------------------
	var tiles: TileSet = load("res://src/world/tileset.tres") as TileSet
	var t0: int = Time.get_ticks_msec()
	var a: ZoneStage = ZoneStage.build(atlas, wald, tiles, null, {})
	var build_ms: int = Time.get_ticks_msec() - t0
	var b: ZoneStage = ZoneStage.build(atlas, wald, tiles, null, {})
	_check(a.trees.size() >= 150, "the forest has its planned wood (%d trees)" % a.trees.size())
	_check(ZoneStage.sheet_paths(wald).size() >= 4, "the forest names its tree sheets for warming")
	var same: bool = a.trees.size() == b.trees.size()
	var inside: bool = true
	for i: int in mini(a.trees.size(), b.trees.size()):
		same = same and a.trees[i].position == b.trees[i].position and a.trees[i].species_id == b.trees[i].species_id
		var tile: Vector2 = Atlas.tile_of(a.trees[i].position)
		inside = inside and (wald.contains(tile) or Atlas.edge_distance(tile, wald.footprint) <= Landscape.BELT_OUT + 0.7)
	_check(same, "two builds of one zone place the same trees")
	_check(inside, "every tree stands inside the footprint or in its belt just beyond it")
	_check(a.forest_at(Vector2(1240, 1000)) > 0.8, "forest floor deep in the Kronenwald")
	_check(a.backdrop != null and a.backdrop.sample(Vector2(1240, 1000)).x == 0.0, "no canopy backdrop over the playable forest")
	_check(a.backdrop != null and a.backdrop.sample(Vector2(1240, 862)).x > 0.9, "the canopy sea closes beyond the forest's north edge (%s)" % str(a.backdrop.sample(Vector2(1240, 862)) if a.backdrop != null else "-"))
	_check(a.veil(&"labor_kronengang") != null and a.veil(&"labor_kronengang").shut, "a fresh forest veils its closed threshold")
	_check(a.grass_habitat_at(Atlas.px_of(Vector2(1220, 950)))["style"] == "meadow", "grass inside the footprint")
	_check(a.grass_habitat_at(Atlas.px_of(Vector2(1300, 1020)))["style"] == "none", "no grass outside the footprint")
	_check(a.ground_cells().size() > 15000, "ground tiles painted (%d)" % a.ground_cells().size())
	_check(a.has_gate(&"labor_kronengang"), "the forest has a gate on the threshold line")
	var wiese_cells: Dictionary = {}
	var wb: ZoneStage = ZoneStage.build(atlas, wiese, tiles, null, {})
	for cell: Vector2i in wb.ground_cells():
		wiese_cells[cell] = true
	var shared: int = 0
	for cell: Vector2i in a.ground_cells():
		if wiese_cells.has(cell):
			shared += 1
	_check(shared == 0, "neighbouring zones never paint the same ground tile (%d shared)" % shared)
	_check(wb.forest_at(Vector2(1132, 938)) > 0.5, "the Kronenwald reaches into the meadow as a tongue")
	_check(wb.forest_at(Vector2(1060, 960)) < 0.2, "open meadow in the middle")
	var spots: Dictionary = {}
	for tree: LivingTree in wb.trees:
		spots[Vector2i(tree.position.round())] = true
	var twice: int = 0
	for tree: LivingTree in a.trees:
		if spots.has(Vector2i(tree.position.round())):
			twice += 1
	_check(twice == 0, "no tree belongs to two zones (%d)" % twice)
	var land: Landscape = Landscape.of(atlas, &"lab")
	var gate_line: PackedVector2Array = atlas.thresholds[&"labor_kronengang"].line
	var in_mouth: int = 0
	var on_way: int = 0
	for tree: Dictionary in land.trees:
		if ZoneMath.polyline_distance(tree["pos"] as Vector2, gate_line) < Landscape.MOUTH_CLEAR * 0.9:
			in_mouth += 1
		for way: Dictionary in land.ways:
			if String(tree["kind"]) != "hand" and ZoneMath.polyline_distance(tree["pos"] as Vector2, Atlas.smooth_open(way["pts"] as PackedVector2Array, 1.0)) < Landscape.WAY_GAP * 0.9:
				on_way += 1
	_check(in_mouth == 0, "the threshold's mouth is clear of trees (%d)" % in_mouth)
	_check(on_way == 0, "no tree stands on a way (%d)" % on_way)
	var belt: int = 0
	for tree: Dictionary in land.trees_of(&"labor_wiese"):
		if String(tree["kind"]) == "belt":
			belt += 1
	_check(belt > 40, "the meadow is closed by a forest belt (%d trees)" % belt)
	print("zone build (main thread): %d ms %s" % [build_ms, str(a.build_ms)])
	a.free()
	b.free()
	wb.free()

	# --- the lab: start zone, background build, threshold --------------------------------------------------------------
	var lab: Node2D = (load(LAB) as PackedScene).instantiate() as Node2D
	add_child(lab)
	await _frames(4)
	var director: ZoneDirector = lab.get("director") as ZoneDirector
	_check(director != null, "lab has a ZoneDirector")
	if director == null:
		_finish(t_all)
		return
	_check(director.is_loaded(&"labor_wiese"), "start zone is loaded at once")
	_check(not director.is_loaded(&"labor_wald"), "the forest is not loaded while the player is far away")
	var player: Player = lab.get_node("Players").get_child(0) as Player
	_check(player != null, "player spawned")
	if player == null:
		_finish(t_all)
		return
	player.set_physics_process(false) ## the test moves her by hand
	await _until(func() -> bool: return director.player_zone.get(1, &"") == &"labor_wiese", 2.0)
	_check(director.player_zone.get(1, &"") == &"labor_wiese", "host puts the player into the meadow")
	_check(not director.threshold_open(&"labor_kronengang"), "threshold is shut while the forest is not loaded")

	# --- step 5: mood and arrival ---------------------------------------------------------------------------------------
	var arrive: Dictionary = director.arrival.state()
	_check(director.seen_zone(&"labor_wiese"), "the meadow counts as entered")
	_check(arrive.zone == "labor_wiese" and bool(arrive.big), "first entry writes the big inscription (%s)" % str(arrive))
	var zm: ZoneMood = director.mood
	var deep: Dictionary = zm.profile_at(Vector2(1240.0, 1000.0))
	_check(float(zm.weights.get(&"labor_wald", 0.0)) > 0.99 and absf(float(deep.sun) - 0.62) < 0.01, "deep in the forest its own mood holds (sun %.2f)" % float(deep.sun))
	var open_mood: Dictionary = zm.profile_at(Vector2(1060.0, 960.0))
	_check(absf(float(open_mood.sun) - 1.0) < 0.01 and float(open_mood.wind) > 1.2, "the open meadow is sunny and windy")
	zm.profile_at(Vector2(1150.0, 947.0))
	var share_w: float = float(zm.weights.get(&"labor_wiese", 0.0))
	_check(share_w > 0.35 and share_w < 0.65, "on the seam both moods share the picture (%.2f)" % share_w)
	var glade: Dictionary = zm.profile_at(Vector2(1222.0, 955.0))
	_check(zm.place_lean > 0.5 and float(glade.motes) > float(deep.motes) + 0.4, "the Moosgrund leans its glade mood (%.2f, motes %.2f)" % [zm.place_lean, float(glade.motes)])
	var faded: bool = true
	var last_sun: float = 1.0
	for t: int in 12: ## walking across the seam: the sun falls step by step, never in one jump
		var s: float = float(zm.profile_at(Vector2(1120.0 + 6.0 * float(t), 966.0)).sun)
		faded = faded and absf(s - last_sun) < 0.1
		last_sun = s
	_check(faded, "the mood changes gently over the seam")
	var t_mood: int = Time.get_ticks_usec()
	for t: int in 100:
		zm.profile_at(Vector2(1150.0, 940.0 + 0.1 * float(t)))
	var mood_us: float = float(Time.get_ticks_usec() - t_mood) / 100.0
	print("mood at the camera: %.0f us per frame" % mood_us)
	_check(mood_us < 1500.0, "the mood is cheap to blend (%.0f us)" % mood_us)
	await _frames(3)
	_check(not ZoneMood.now.is_empty(), "the blended mood is published for the world's systems")

	# The meadow's own edge blocks (not the threshold): walking north out of the footprint.
	var edge_from: Vector2 = Atlas.px_of(Vector2(1060.0, 914.0))
	_check(director.atlas.zone_at(&"lab", edge_from) == &"labor_wiese", "the edge probe starts in the meadow")
	_check(player.test_move(Transform2D(0.0, edge_from), Vector2(0.0, -220.0)), "footprint edge blocks the way out")
	var seam_wall: Vector2 = Atlas.px_of(Vector2(1144.0, 930.0)) ## the closed part of the seam, north of the threshold
	_check(player.test_move(Transform2D(0.0, seam_wall), Vector2(160.0, 0.0)), "the seam is a wall outside the threshold")

	# Walk up to the threshold: the forest is built in the background, frames stay smooth.
	player.global_position = Atlas.px_of(Vector2(1120.0, 966.0))
	var worst: int = 0
	var last: int = Time.get_ticks_usec()
	var built: bool = false
	var end: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		if director.is_building():
			worst = maxi(worst, now - last)
			if now - last > 20000:
				print("  slow frame %.1f ms (job %s, attaching %s)" % [float(now - last) / 1000.0, str(director._job != null), str(director._attaching != null)])
		last = now
		if director.is_loaded(&"labor_wald"):
			built = true
			break
	_check(built, "the forest streams in when the player comes near")
	print("forest stream: worst frame while building %.1f ms, build %s" % [float(worst) / 1000.0, str(director.build_log)])
	_check(Jobs.threaded == false or worst < 50000, "no long hitch while the forest builds and attaches (%.1f ms)" % (float(worst) / 1000.0))
	var forest_log: Dictionary = {}
	for entry: Dictionary in director.build_log:
		if entry["zone"] == &"labor_wald":
			forest_log = entry
	_check(int(forest_log.get("attach_frames", 0)) > 1, "the forest is attached over several frames (%s)" % str(forest_log))
	_check(float(forest_log.get("attach_worst_ms", 999.0)) < 30.0, "no attach slice is long (%s)" % str(forest_log))
	var steady: Array[int] = []
	var tick: int = Time.get_ticks_usec()
	for _i: int in 120:
		await get_tree().process_frame
		var now_t: int = Time.get_ticks_usec()
		steady.append(now_t - tick)
		tick = now_t
	steady.sort()
	print("steady frames at the seam: median %.1f ms, worst %.1f ms" % [float(steady[60]) / 1000.0, float(steady[119]) / 1000.0])
	await _physics(3)
	_check(director.threshold_open(&"labor_kronengang"), "threshold opens once both sides are there")
	var meadow_veil: ZoneVeil = director.stage(&"labor_wiese").veil(&"labor_kronengang")
	_check(meadow_veil != null and not meadow_veil.shut, "the veil lifts when the threshold opens")
	var seam_from: Vector2 = Atlas.px_of(Vector2(1147.0, 966.0))
	_check(not player.test_move(Transform2D(0.0, seam_from), Vector2(96.0, 0.0)), "the seam can be walked through")
	var stage_wald: ZoneStage = director.stage(&"labor_wald")
	var trail_at_seam: bool = false
	if stage_wald != null:
		for i: int in 60: ## a vertical line across the trail, just behind the seam
			if stage_wald.surfaces.surface_at(Atlas.px_of(Vector2(1156.0, 958.0 + float(i) * 0.25))) != "":
				trail_at_seam = true
				break
	_check(trail_at_seam, "forest ground has its trail surface at the seam")

	# Into the forest: the host hands her over.
	player.global_position = Atlas.px_of(Vector2(1200.0, 960.0))
	var moved: bool = await _until(func() -> bool: return director.player_zone.get(1, &"") == &"labor_wald", 2.0)
	_check(moved, "the player is in the forest zone after crossing")
	var in_forest: Dictionary = director.arrival.state()
	var forest_big: bool = (in_forest.zone == "labor_wald" and bool(in_forest.big)) or (in_forest.waiting as Array).has("labor_wald:big")
	_check(director.seen_zone(&"labor_wald") and forest_big, "first time in the forest: its big inscription (%s)" % str(in_forest))
	player.global_position = Atlas.px_of(Vector2(1222.0, 955.0))
	var found: bool = await _until(func() -> bool: return director.seen_place(&"moosgrund"), 2.0)
	_check(found, "walking into the Moosgrund discovers it")

	# --- unload with state, catch-up, save round trip ------------------------------------------------------------------
	stage_wald = director.stage(&"labor_wald")
	var felled: LivingTree = stage_wald.trees[0]
	var stump: Dictionary = felled.state.duplicate(true)
	stump["f"] = 1
	stump["c"] = 0
	stump["s"] = 0
	stump["d"] = TimeManager.day
	felled.state = stump
	var tree_name: String = String(felled.name)
	player.global_position = Atlas.px_of(Vector2(1004.0, 940.0)) ## far west in the meadow
	var gone: bool = await _until(func() -> bool: return not director.is_loaded(&"labor_wald"), 4.0)
	_check(gone, "the forest unloads when nobody is near")
	var home: Dictionary = director.arrival.state()
	_check((home.zone == "labor_wiese" and not bool(home.big)) or (home.waiting as Array).has("labor_wiese:small"), "back in the meadow: only the slim line (%s)" % str(home))
	var saved: Dictionary = director.export_state()
	var kept: Dictionary = ((saved["zones"] as Dictionary).get("labor_wald", {}) as Dictionary)
	_check(int(((kept.get("trees", {}) as Dictionary).get(tree_name, {}) as Dictionary).get("f", 0)) == 1, "the felled tree is kept while the zone is away")
	_check((saved["zones"] as Dictionary).has("labor_wiese"), "the save holds the loaded meadow too")

	TimeManager.day += 7
	player.global_position = Atlas.px_of(Vector2(1140.0, 966.0))
	var back: bool = await _until(func() -> bool: return director.is_loaded(&"labor_wald"), 15.0)
	_check(back, "the forest comes back")
	if back:
		var again: LivingTree = director.stage(&"labor_wald").trees_root.get_node(tree_name) as LivingTree
		_check(again != null and str(again.state) != str(stump), "the stump caught up on its missed days (%s)" % (str(again.state) if again != null else "gone"))

	var other: ZoneDirector = ZoneDirector.new()
	other.import_state(saved)
	_check(str(other.export_state()) == str(saved), "save block round-trips (incl. what was seen)")
	_check(other.seen_place(&"moosgrund"), "the save remembers discovered places")
	other.free()

	lab.queue_free()
	await _frames(2)
	_finish(t_all)


func _finish(t_all: int) -> void:
	print("zone lab test: %d ms" % (Time.get_ticks_msec() - t_all))
	if _fails == 0:
		print("ZONE LAB OK (%d checks)" % _checks)
	else:
		print("ZONE LAB FAILED (%d of %d)" % [_fails, _checks])
	get_tree().quit(0 if _fails == 0 else 1)
