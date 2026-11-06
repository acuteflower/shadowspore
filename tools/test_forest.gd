extends Node
## Regression for the forest demography (docs/forest_and_slopes.md): forest floors under the trees of woods, dense canopies, saplings that
## grow with the days, fallen trunks tied to stands, Krummholz on high ground, slope-dependent plants and shade moss.
## Run: Godot --headless --path . tools/test_forest.tscn
var failures: int = 0

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _ready() -> void:
	_run.call_deferred()

func _crown(entry: Dictionary, plants: Dictionary) -> float:
	return float((plants[entry.kind].crown_half_width as Array)[int(entry.variant)]) * float(entry.get("scale", 1.0))

func _run() -> void:
	var plants: Dictionary = DataRegistry.table("plants")
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var trees: Array[Dictionary] = []
	var beds: Array[Dictionary] = []
	var young: int = 0
	var firs: int = 0
	var scaled: int = 0
	var unscaled_high: int = 0
	var bad_scaled: int = 0
	for dx: int in range(-17, 18):
		for dy: int in range(-17, 18):
			var rect: Rect2i = Rect2i((Vector2i(17, 17) + Vector2i(dx, dy)) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			for entry: Dictionary in world._generator.props_for_chunk(rect):
				if String(entry.kind) == "forestbed":
					beds.append(entry)
				elif PropGenerator.TREE_KINDS.has(String(entry.kind)):
					trees.append(entry)
					if String(entry.kind) == "tree":
						firs += 1
					if entry.has("young"):
						young += 1
						if int(entry.variant) > 1: bad_scaled += 1
					var level: float = world._relief.level_at(entry.pos as Vector2)
					if entry.has("scale"):
						scaled += 1
						if int(entry.variant) > 1 or float(entry.scale) < 0.75 or float(entry.scale) > 0.85 or level < PropGenerator.KRUMMHOLZ_LEVEL - 0.01: bad_scaled += 1
					elif level >= PropGenerator.KRUMMHOLZ_LEVEL and not entry.has("young") and int(entry.variant) > 1 and (entry.pos as Vector2).distance_to(Vector2(463, 616) * 16.0) > 700.0:
						unscaled_high += 1 ## (the hand-placed terrace trees at the start, data/ground.json "props", are meant to win)
	print("trees %d (firs %d, young %d, krummholz %d), forest beds %d" % [trees.size(), firs, young, scaled, beds.size()])
	check(beds.size() > 500, "forest floors are generated (%d)" % beds.size())
	check(young > 0 and float(young) / float(firs) > 0.03 and float(young) / float(firs) < 0.2, "saplings are 3-20 %% of all firs, woods and groves only (%.1f %%)" % (100.0 * young / maxf(firs, 1)))
	check(scaled > 0, "Krummholz exists on the high levels (%d)" % scaled)
	check(bad_scaled == 0, "every stunted tree is variant 0/1, scaled 0.75-0.85 and on a high level; every sapling is variant 0/1")
	check(unscaled_high == 0, "no tall tree stands on a high level unscaled (%d)" % unscaled_high)
	# every forest floor lies under a tree
	var grid: Dictionary = {}
	for tree: Dictionary in trees:
		var pos: Vector2 = tree.pos
		(grid.get_or_add(Vector2i(floori(pos.x / 128.0), floori(pos.y / 128.0)), []) as Array).append(tree)
	var orphan: int = 0
	for bed: Dictionary in beds:
		var found: bool = false
		var pos: Vector2 = (bed.pos as Vector2) - Vector2(0, -5)
		var key: Vector2i = Vector2i(floori(pos.x / 128.0), floori(pos.y / 128.0))
		for ox: int in range(-1, 2):
			for oy: int in range(-1, 2):
				for tree: Dictionary in grid.get(key + Vector2i(ox, oy), []):
					if (tree.pos as Vector2).distance_to(pos) < 1.0: found = true
		if not found: orphan += 1
	check(orphan == 0, "every forest floor lies under a standing tree (%d without)" % orphan)
	# crowns: never closer than the dense limit, and some pairs really do overlap past the old limit
	var closest: float = 9.0
	var overlapping: int = 0
	for key: Vector2i in grid:
		for a: Dictionary in grid[key]:
			for ox: int in range(-1, 2):
				for oy: int in range(-1, 2):
					for b: Dictionary in grid.get(key + Vector2i(ox, oy), []):
						if a == b or (a.pos as Vector2) >= (b.pos as Vector2): continue
						var sum: float = _crown(a, plants) + _crown(b, plants)
						var ratio: float = (a.pos as Vector2).distance_to(b.pos as Vector2) / sum
						closest = minf(closest, ratio)
						if ratio < PropGenerator.CROWN_OVERLAP - 0.02: overlapping += 1
	check(closest >= PropGenerator.DENSE_CROWN_OVERLAP - 0.02, "no two crowns closer than the dense limit (%.2f)" % closest)
	check(overlapping > 100, "crowns of woods reach into each other (%d pairs past the old limit)" % overlapping)
	# slopes
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var north: int = 0
	var south: int = 0
	var out: int = 0
	for _i: int in 3000:
		var at: Vector2 = Vector2(rng.randf_range(60, 1040), rng.randf_range(60, 1040))
		var a: float = world._generator.aspect(at)
		if a < -0.35: north += 1
		elif a > 0.35: south += 1
		if absf(a) > 1.0001: out += 1
	check(north > 20 and south > 20 and out == 0, "slopes face both ways (north %d, south %d of 3000)" % [north, south])
	# saplings: stage follows the day, matures, cannot be chopped meanwhile
	var cell: Vector2i = Vector2i(3, 3)
	world._young[cell] = {"age": 0, "variant": 1}
	TimeManager.day = 1
	var first: Dictionary = world.thing_state(cell)
	check(first.has("f") and int(first.h) >= 1 and int(first.h) < 6, "a new sapling is never a bare stump (sapling state): %s" % [first])
	TimeManager.day = 5
	var later: Dictionary = world.thing_state(cell)
	check(later.has("f") and int(later.h) < int(first.h), "it has grown by day 5")
	TimeManager.day = 12
	check(world.thing_state(cell).is_empty() and not world._young.has(cell), "it is a fir by day 12 and forgotten")
	TimeManager.day = 1
	# fallen trunks: most lie in or at a wood
	var near: int = 0
	var logs: int = 0
	var open_field: int = 0
	for cx: int in range(14, 21):
		for cy: int in range(16, 23):
			var c: Vector2i = Vector2i(cx, cy)
			var build: WorldLevel.ChunkBuild = world._begin_chunk(c)
			build.query.advance()
			for i: int in 16:
				var spec: Dictionary = FallenLogScatter.candidate(world, c, i, build.query.outer)
				if spec.is_empty(): continue
				logs += 1
				if FallenLogScatter._trees_near(spec.pos as Vector2, build.query.outer) > 0: near += 1
				else: open_field += 1
	check(logs > 5 and float(near) / float(logs) > 0.8, "fallen trunks lie at trees (%d of %d, %d in the open)" % [near, logs, open_field])
	# art
	var atlas: Image = MeadowDetails._make_atlas().get_image()
	check(atlas.get_width() == MeadowDetails.COUNT * 16 and MeadowDetails.COUNT == 26, "26 ground cover variants")
	for v: int in [24, 25]:
		var filled: int = 0
		for y: int in 20:
			for x: int in 16:
				if atlas.get_pixel(v * 16 + x, y).a > 0.5: filled += 1
		check(filled > 25, "shade moss %d is drawn (%d px)" % [v, filled])
	var bed_tex: Texture2D = load("res://assets/props/forestbed.png") as Texture2D
	check(bed_tex.get_width() == 192 * PropGenerator.FOREST_BED_RX.size() and bed_tex.get_height() == 128, "forest floor sheet has one 192x128 frame per size")
	print("DONE failures=", failures)
	get_tree().quit(failures)
