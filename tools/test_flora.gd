extends Node
## Regression for the small meadow plants (docs/flora.md): every kind is generated somewhere around the start,
## loads its sheets, can be picked/harvested/regrown and the sun flower turns with the clock.
## Run: Godot --headless --path . tools/test_flora.tscn
const KINDS: Array[String] = ["moonbell", "wound_leaf", "puffseed", "glowfern", "cattail", "sunbloom", "voidbloom", "earth_tuber", "ember_carrot", "night_beet", "mist_lily", "spark_poppy", "ember_morel", "moon_parasol", "moon_iris", "brook_mint", "marsh_gold"]
var failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func _run() -> void:
	var plants: Dictionary = DataRegistry.table("plants")
	var items: Dictionary = DataRegistry.table("items")
	for kind: String in KINDS:
		var spec: Dictionary = plants[kind]
		var tex: Texture2D = load(String(spec.texture)) as Texture2D
		check(tex != null and tex.get_width() == 40 * int(spec.columns) and tex.get_height() == 34 * int(spec.rows), "%s sheet is %d x %d frames" % [kind, spec.columns, spec.rows])
		check(not spec.has("glow") or (load(String(spec.glow)) as Texture2D).get_size() == tex.get_size(), "%s glow sheet matches" % kind)
		check(not spec.has("stripped") or load(String(spec.stripped)) != null, "%s stripped sheet loads" % kind)
		for key: String in ["radius", "height", "weights"]:
			check((spec[key] as Array).size() == int(spec.columns), "%s has %s per variant" % [kind, key])
		if spec.has("pickup"):
			check(items.has(spec.pickup.item) and load(String(items[spec.pickup.item].icon)) != null, "%s pickup item %s exists" % [kind, spec.pickup.item])
	for drop: String in ["fern_frond", "reed", "plant_fiber"]:
		check(items.has(drop), "item %s exists" % drop)
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var counts: Dictionary = {}
	for dx: int in range(-17, 18):
		for dy: int in range(-17, 18):
			var rect: Rect2i = Rect2i((Vector2i(17, 17) + Vector2i(dx, dy)) * WorldLevel.CHUNK, Vector2i(WorldLevel.CHUNK, WorldLevel.CHUNK))
			for entry: Dictionary in world._generator.props_for_chunk(rect):
				counts[entry.kind] = int(counts.get(entry.kind, 0)) + 1
	print("COUNTS ", counts)
	for kind: String in KINDS:
		check(int(counts.get(kind, 0)) > 0, "%s is generated in the world" % kind)
	# a live plant of each kind
	for kind: String in KINDS:
		var thing: Flora = (load(String(plants[kind].scene)) as PackedScene).instantiate() as Flora
		thing.setup(world, Vector2i(5, 5), kind, 0)
		add_child(thing)
		check(thing.prompt() != "" or kind == "cattail" or kind == "sunbloom" or kind == "mist_lily", "%s offers a prompt" % kind)
		thing.apply_state({"p": 3, "k": kind}, "pick")
		check(thing.prompt() == "", "%s is quiet after picking" % kind)
		thing.queue_free()
	var sun: Flora = (load(String(plants.sunbloom.scene)) as PackedScene).instantiate() as Flora
	sun.setup(world, Vector2i(6, 6), "sunbloom", 1)
	add_child(sun)
	var sun_cols: int = int(plants.sunbloom.columns)
	TimeManager.time_of_day = 0.3
	sun._pose()
	check(sun._sprite.frame == 1 + sun_cols * 0, "sun flower looks east in the morning")
	TimeManager.time_of_day = 0.5
	sun._row = -1
	sun._pose()
	check(sun._sprite.frame == 1 + sun_cols * 1, "sun flower looks up at noon")
	TimeManager.time_of_day = 0.95
	sun._row = -1
	sun._pose()
	check(sun._sprite.frame == 1 + sun_cols * 3 and sun.prompt() == "", "sun flower closes at night and cannot be picked")
	var lily: Flora = (load(String(plants.mist_lily.scene)) as PackedScene).instantiate() as Flora
	var lily_cols: int = int(plants.mist_lily.columns)
	lily.setup(world, Vector2i(9, 9), "mist_lily", 1)
	add_child(lily)
	TimeManager.time_of_day = 0.5
	lily._row = -1
	lily._pose()
	check(lily._sprite.frame == 1 + lily_cols and lily.prompt() == "" and (lily._pollen == null or not lily._pollen.emitting), "lily is closed by day and cannot be picked")
	TimeManager.time_of_day = 0.95
	lily._row = -1
	lily._pose()
	check(lily._sprite.frame == 1 and lily.prompt() == "PFLÜCKEN" and lily._pollen != null and lily._pollen.emitting, "lily opens at night, can be picked and sheds pollen")
	var poppy: Flora = (load(String(plants.spark_poppy.scene)) as PackedScene).instantiate() as Flora
	poppy.setup(world, Vector2i(10, 10), "spark_poppy", 1)
	add_child(poppy)
	poppy._puff()
	var sparks: CPUParticles2D = null
	for child: Node in poppy.get_children():
		if child is CPUParticles2D: sparks = child
	check(sparks != null and sparks.amount == 14, "poppy bursts into rising embers")
	var root: Flora = (load(String(plants.ember_carrot.scene)) as PackedScene).instantiate() as Flora
	root.setup(world, Vector2i(8, 8), "ember_carrot", 1)
	add_child(root)
	check(root.prompt() == "AUSZIEHEN", "root vegetable is pulled, not picked")
	root.apply_state({"p": 3, "k": "ember_carrot"}, "pick")
	var clods: int = 0
	for child: Node in root.get_children():
		if child is CPUParticles2D: clods += 1
	check(clods >= 2 and root.prompt() == "", "pulling sprays earth and leaves a hole")
	var hero: Player = world._players.get_child(0) as Player
	check(hero.has_method("begin_pull") and not hero._rig_pull_hand.is_empty() and hero._rig_pull_hand.size() == 96, "Ellie has the pull animation rig")
	var puff: Flora = (load(String(plants.puffseed.scene)) as PackedScene).instantiate() as Flora
	puff.setup(world, Vector2i(7, 7), "puffseed", 1)
	add_child(puff)
	puff._puff()
	var seeds: int = 0
	for child: Node in puff.get_children():
		if child is CPUParticles2D: seeds += 1
	check(seeds == 1, "seed head lets go of seeds")
	for kind: String in ["birch", "ember_morel", "moon_parasol"]:
		check(int(counts.get(kind, 0)) > 50, "%s is generated (%d)" % [kind, int(counts.get(kind, 0))])
	var wind_plant: Flora = (load(String(plants.moonbell.scene)) as PackedScene).instantiate() as Flora
	wind_plant.setup(world, Vector2i(12, 12), "moonbell", 1)
	add_child(wind_plant)
	check(wind_plant._sprite.material is ShaderMaterial and wind_plant._glow.material is ShaderMaterial and wind_plant._sway_rate == 0.0, "small plants bend in WorldWind's wind through flora_wind.gdshader")
	var birch_tree: Node = (load(String(plants.birch.scene)) as PackedScene).instantiate()
	(birch_tree as WorldProp).setup(world, Vector2i(13, 13), "birch", 5)
	add_child(birch_tree)
	check(birch_tree.prompt() == "PFLÜCKEN" and (load(String(plants.birch.texture)) as Texture2D).get_width() == 112 * 6, "moon birch has 6 variants and offers its leaves")
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 7
	rng_b.seed = 8
	var field_a: CloverField = CloverField.new()
	var field_a2: CloverField = CloverField.new()
	var field_b: CloverField = CloverField.new()
	field_a.setup(CloverField.plan(rng_a), Vector2.ZERO)
	rng_a.seed = 7
	field_a2.setup(CloverField.plan(rng_a), Vector2.ZERO)
	field_b.setup(CloverField.plan(rng_b), Vector2.ZERO)
	check(field_a.atlas_image.get_data() == field_a2.atlas_image.get_data(), "a clover field is the same on every peer (same seed, same clumps)")
	check(field_a.atlas_image.get_data() != field_b.atlas_image.get_data(), "every clover field looks different")
	print("DONE failures=", failures)
	get_tree().quit(failures)
