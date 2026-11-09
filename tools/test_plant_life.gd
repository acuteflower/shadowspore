extends Node
## Regression for the plant-life additions (docs/plant_life.md): wet and dry, the Fangblume, seed flight, the Void's blight at the
## world's edge and the undergrowth animals. Run: Godot --headless --path . tools/test_plant_life.tscn
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func check_quiet(ok: bool) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: determinism")


func _run() -> void:
	var plants: Dictionary = DataRegistry.table("plants")
	var items: Dictionary = DataRegistry.table("items")
	# ---- data and art
	var snapper: Dictionary = plants.snapper
	var sheet: Texture2D = load(String(snapper.texture)) as Texture2D
	check(sheet.get_size() == Vector2(120, 102) and (load(String(snapper.glow)) as Texture2D).get_size() == sheet.get_size(), "snapper sheet is 3 x 3 frames of 40 x 34 with a matching glow sheet")
	check((load(String(snapper.stripped)) as Texture2D).get_size() == Vector2(120, 34), "snapper has cut stalks")
	for item: String in ["shimmer_beetle", "leaf_caterpillar", "leaf_snail"]:
		check(items.has(item) and (load(String(items[item].icon)) as Texture2D).get_size() == Vector2(16, 16), "%s is an item with a 16x16 icon" % item)
		check((DataRegistry.table("fishing").baits as Dictionary).has(item), "%s is river bait" % item)
	for kind: String in ["puffseed", "spark_poppy", "moonbell", "mist_lily", "sunbloom", "wound_leaf"]:
		check((plants[kind] as Dictionary).has("sow"), "%s scatters seeds" % kind)
	for kind: String in ["bush", "berry_bush", "ember_bush", "grass", "glowfern", "cattail"]:
		check((plants[kind] as Dictionary).has("critters"), "%s can carry an undergrowth animal" % kind)

	# ---- wet and dry: pure and deterministic, about a third of the days are damp
	Moisture.world_seed = 4242
	var wet_days: int = 0
	for day: int in range(1, 301):
		var a: bool = Moisture.is_wet_day(day)
		check_quiet(a == Moisture.is_wet_day(day))
		wet_days += 1 if a else 0
	check(wet_days > 60 and wet_days < 150, "a good third of the days are damp (%d of 300)" % wet_days)
	var wet_day: int = 1
	while not Moisture.is_wet_day(wet_day):
		wet_day += 1
	TimeManager.day = wet_day
	TimeManager.time_of_day = 0.26
	var morning: float = Moisture.wetness()
	TimeManager.time_of_day = 0.78
	var evening: float = Moisture.wetness()
	check(morning > 0.9 and evening < morning and evening > 0.2, "a damp day is soaked at dawn and dries out toward evening (%.2f -> %.2f)" % [morning, evening])
	var dry_day: int = 1
	while Moisture.is_wet_day(dry_day):
		dry_day += 1
	TimeManager.day = dry_day
	TimeManager.time_of_day = 0.4
	check(Moisture.wetness() == 0.0, "a dry day is dry")

	# ---- the world
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var counts: Dictionary = {}
	var damp_sum: float = 0.0
	var damp_n: int = 0
	var shroom_damp: float = 0.0
	var shroom_n: int = 0
	var low: float = 1.0
	var high: float = 0.0
	for dx: int in range(-6, 7):
		for dy: int in range(-6, 7):
			var rect: Rect2i = Rect2i((Vector2i(17, 17) + Vector2i(dx, dy)) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			for entry: Dictionary in world._generator.props_for_chunk(rect):
				counts[entry.kind] = int(counts.get(entry.kind, 0)) + 1
				if entry.kind == "mushroom" or entry.kind == "ember_morel":
					shroom_damp += world._generator.damp_at((entry.pos as Vector2) / 16.0)
					shroom_n += 1
			for sample: int in 6:
				var at: Vector2 = Vector2(rect.position) + Vector2(sample * 5 + 2, sample * 4 + 3)
				var d: float = world._generator.damp_at(at)
				low = minf(low, d)
				high = maxf(high, d)
				if world._generator._near_water(at) < 0.01: ## mushrooms keep away from the water itself: compare with dry-footed ground
					damp_sum += d
					damp_n += 1
	check(high - low > 0.35, "the ground varies from dry to damp (%.2f .. %.2f)" % [low, high])
	check(shroom_n > 30 and shroom_damp / float(shroom_n) > damp_sum / float(damp_n), "mushrooms stand on damper ground than average (%.2f vs %.2f)" % [shroom_damp / float(maxi(shroom_n, 1)), damp_sum / float(maxi(damp_n, 1))])
	check(int(counts.get("snapper", 0)) > 3, "snappers are generated in the dark shade (%d)" % int(counts.get("snapper", 0)))

	# ---- the Fangblume
	var thing: Snapper = (load(String(snapper.scene)) as PackedScene).instantiate() as Snapper
	thing.setup(world, Vector2i(5, 5), "snapper", 0)
	add_child(thing)
	TimeManager.time_of_day = 0.5
	thing._process(0.1)
	check(thing._sprite.frame == 0 + 3 * 2 and not thing._open, "the Fangblume is a closed bud by day")
	TimeManager.time_of_day = 0.95
	thing._process(0.1)
	check(thing._sprite.frame == 0 and thing._open, "the Fangblume opens at night")
	thing.play_fx("snap", thing.global_position)
	thing._process(0.05)
	check(thing._snap_t > 0.0 and thing._sprite.frame == 3, "the jaws begin to shut when it snaps")
	for _i: int in 30:
		thing._process(0.05)
	check(thing._snap_t < 0.0 and thing._sprite.frame == 0, "after the snap it opens again")
	thing.apply_state({"h": 2, "k": "snapper"}, "strip")
	thing._process(0.1)
	check(not thing._open and thing.is_depleted(), "a cut Fangblume stays shut")
	TimeManager.time_of_day = 0.95
	var biter: Snapper = (load(String(snapper.scene)) as PackedScene).instantiate() as Snapper
	biter.setup(world, Vector2i(30, 30), "snapper", 0)
	biter.position = Vector2(480, 480)
	add_child(biter)
	var hero: Player = world._players.get_child(0) as Player if world._players.get_child_count() > 0 else null
	check(hero != null, "the test world has a player")
	if hero != null:
		hero.health.current = hero.health.max_health
		hero.health._invulnerable_until_msec = 0
		hero.global_position = biter.position + Vector2(90, 0)
		for _i: int in 20:
			biter._process(0.05)
		check(hero.health.current == hero.health.max_health, "a Fangblume does not bite from afar")
		hero.global_position = biter._head() + Vector2(4, 0)
		for _i: int in 4:
			biter._process(0.05)
		check(hero.health.current == hero.health.max_health and biter._alert > 0.0, "the lure flares first, the sting waits for the warning")
		for _i: int in 12:
			biter._process(0.05)
		check(hero.health.current < hero.health.max_health, "someone who stays too close is stung (%.0f of %.0f)" % [hero.health.current, hero.health.max_health])
		var after: float = hero.health.current
		hero.health._invulnerable_until_msec = 0
		for _i: int in 20:
			biter._process(0.05)
		check(hero.health.current == after, "the sting has a cooldown")
	TimeManager.time_of_day = 0.5

	# ---- seed flight
	var sowing: PlantSowing = world.sowing
	check(sowing != null, "the level has seed flight")
	var home: Vector2i = Vector2i((world.spawn_point() / 16.0).floor())
	var target: Vector2i = Vector2i.ZERO
	for dy: int in range(-14, 15):
		for dx: int in range(-14, 15):
			if target == Vector2i.ZERO and sowing.cell_ok(home + Vector2i(dx, dy)):
				target = home + Vector2i(dx, dy)
	check(target != Vector2i.ZERO, "there is free ground for a seed near the start")
	if target != Vector2i.ZERO:
		sowing._rpc_sow(target, "puffseed", 1, TimeManager.day, Vector2.ZERO, false)
		await get_tree().create_timer(0.3).timeout
		check(world._things.has(target) and (world._things[target] as WorldProp).kind == "puffseed", "a sown puffseed stands where the seed landed")
		check(not sowing.cell_ok(target), "that spot is taken now")
		var saved: Dictionary = sowing.export()
		sowing.sown.clear()
		sowing.import_saved(JSON.parse_string(JSON.stringify(saved)) as Dictionary)
		check(sowing.sown.has(target) and int(sowing.sown[target].v) == 1, "sown plants survive a save (JSON round trip)")
		sowing._rpc_wither(target)
		check(not sowing.sown.has(target) and not world._things.has(target), "a withered plant is gone")
		var today: int = TimeManager.day
		sowing._rpc_sow(target, "moonbell", 0, today - 20, Vector2.ZERO, false)
		await get_tree().create_timer(0.3).timeout
		var old: WorldProp = world._things.get(target) as WorldProp
		check(old != null and old.scale.x == 1.0, "an old sown plant is full size")
		sowing._wither_round(today)
		check(not sowing.sown.has(target), "a plant older than its lifespan withers at sunrise")

	# ---- the Void's blight
	var coast_cell: Vector2i = Vector2i.ZERO
	var inland_cell: Vector2i = Vector2i.ZERO
	for y: int in range(0, 1100, 6):
		for x: int in range(0, 1100, 6):
			var tiles: float = world.coast_tiles(Vector2(x, y) * 16.0)
			if coast_cell == Vector2i.ZERO and tiles > 1.0 and tiles < 3.0:
				coast_cell = Vector2i(x, y)
			if inland_cell == Vector2i.ZERO and tiles > 15.0:
				inland_cell = Vector2i(x, y)
	check(coast_cell != Vector2i.ZERO and inland_cell != Vector2i.ZERO, "found a coast tile and an inland tile")
	var blighted: Bush = (load(String(plants.moonbell.scene)) as PackedScene).instantiate() as Bush
	blighted.setup(world, coast_cell, "moonbell", 0)
	blighted.position = PropGenerator.position_of(coast_cell)
	add_child(blighted)
	var healthy: Bush = (load(String(plants.moonbell.scene)) as PackedScene).instantiate() as Bush
	healthy.setup(world, inland_cell, "moonbell", 0)
	healthy.position = PropGenerator.position_of(inland_cell)
	add_child(healthy)
	check(blighted.blight > 0.5 and healthy.blight == 0.0, "plants at the coast are blighted, inland ones are not (%.2f / %.2f)" % [blighted.blight, healthy.blight])
	check(blighted._sprite.self_modulate != Color.WHITE and healthy._sprite.self_modulate == Color.WHITE, "a blighted plant is greyed and violet")
	blighted.set_night(1.0)
	var glow_tint: Color = blighted._glow.self_modulate
	check(glow_tint.b >= glow_tint.g, "its glow turns violet at night")
	var plain: Bush = (load(String(plants.cattail.scene)) as PackedScene).instantiate() as Bush
	plain.setup(world, coast_cell + Vector2i(1, 0), "cattail", 0)
	plain.position = PropGenerator.position_of(coast_cell + Vector2i(1, 0))
	add_child(plain)
	plain.set_night(1.0)
	check(plain._blight_glow != null and plain._blight_glow.modulate.a > 0.0, "a plant without a glow sheet gets a violet shimmer")

	# ---- undergrowth animals
	var seen: Dictionary = {}
	var host: Bush = null
	var bushes: Array[WorldProp] = []
	for i: int in 1600:
		var b: Bush = (load(String(plants.bush.scene)) as PackedScene).instantiate() as Bush
		b.setup(world, Vector2i(2000 + i, 5), "bush", 0)
		add_child(b)
		bushes.append(b)
	LeafCritter.settle_chunk(bushes)
	for prop: WorldProp in bushes:
		var b: Bush = prop as Bush
		var animal: String = LeafCritter.today(b)
		check_quiet(animal == LeafCritter.today(b))
		seen[animal] = int(seen.get(animal, 0)) + 1
		if animal != "" and host == null:
			host = b
		else:
			b.queue_free()
	check(int(seen.get("beetle", 0)) > 5 and int(seen.get("caterpillar", 0)) > 5 and int(seen.get("snail", 0)) > 3, "all three animals turn up on bushes (%s)" % [seen])
	check(int(seen.get("", 0)) > 1450, "more than 90 percent of bushes carry nothing")
	check(host != null and host.prompt() == "ABLESEN", "a bush with an animal on it offers ABLESEN")
	if host != null:
		host.apply_state({"c": TimeManager.day + 1, "k": "bush"}, "catch")
		check(LeafCritter.today(host) == "" and host.prompt() == "", "a taken animal is gone for the day")
		host.apply_state({"h": 3, "k": "bush"}, "")
		check(LeafCritter.today(host) == "", "a stripped bush carries nothing")
	print("DONE failures=", failures)
	get_tree().quit(failures)
