extends Node2D
## Density, habitat contact, pause, daily absence and streaming-order regression.
var failures: int = 0
var bushes: Array[WorldProp] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
	else: print("PASS: ", label)

func _ready() -> void:
	run.call_deferred()

func plant(cell: Vector2i, species: String = "bush", variant: int = 1, saved: Dictionary = {}) -> Bush:
	var spec: Dictionary = DataRegistry.get_entry("plants", species)
	var bush: Bush = (load(String(spec.scene)) as PackedScene).instantiate() as Bush
	bush.setup(null, cell, species, variant)
	bush.position = PropGenerator.position_of(cell)
	add_child(bush)
	if not saved.is_empty(): bush.apply_state(saved, "")
	bush.set_process(false)
	bush._critter.set_process(false)
	return bush

func residents() -> Dictionary:
	var found: Dictionary = {}
	for bush: WorldProp in bushes:
		var animal: String = LeafCritter.today(bush)
		if animal != "": found[bush.cell] = animal
	return found

func run() -> void:
	Moisture.world_seed = 4242
	TimeManager.day = 3
	TimeManager.time_of_day = 0.5
	TimeManager.locked = true
	for y: int in range(3, 96, 4):
		for x: int in range(3, 96, 4):
			bushes.append(plant(Vector2i(x, y)))
	LeafCritter.settle_chunk(bushes)
	var before: Dictionary = residents()
	check(before.size() > 6 and before.size() < bushes.size() * 0.08, "sparse population: %d of %d plants" % [before.size(), bushes.size()])
	var spacing: bool = true
	var one_per_square: bool = true
	var squares: Dictionary = {}
	for cell: Vector2i in before:
		var square: Vector2i = Vector2i(floori(float(cell.x) / 16), floori(float(cell.y) / 16))
		if squares.has(square): one_per_square = false
		squares[square] = true
		for other: Vector2i in before:
			if cell != other and Vector2(cell).distance_to(Vector2(other)) < 4: spacing = false
	check(one_per_square and spacing, "one animal per square and at least four tiles between neighboring squares")

	var geometry_ok: bool = true
	var species_count: Dictionary = {}
	for bush: WorldProp in bushes:
		var bug: LeafCritter = (bush as Bush)._critter
		if bug.kind == "": continue
		species_count[bug.kind] = true
		var spec: Dictionary = LeafCritter.config().species[bug.kind]
		var period: float = float(spec.rest_seconds) + float(spec.move_seconds)
		for second: int in range(0, 150):
			TimeManager.time_of_day = TimeManager.DAY_START + (200.0 + second * 0.17) / TimeManager.DAY_LENGTH_SEC
			bug._pose(0.0)
			var point: Vector2 = (bush.get_node("Sprite") as Sprite2D).transform.affine_inverse() * bug.position
			if not LeafCritter.sites_for(bush, bug.kind).has(point.round()): geometry_ok = false
			if bug._anchor.distance_to(bug._end) > float(spec.step_pixels) + 0.01: geometry_ok = false
		# At least 79% of each behavior cycle is quiet.
		if float(spec.rest_seconds) / period < 0.79: geometry_ok = false
	check(geometry_ok and species_count.size() == 3, "all species stay wholly supported during short routes and spend most of the cycle resting")

	# Every eligible image is scanned: tiny variants may legitimately have no habitat.
	var checked: int = 0
	var habitat_ok: bool = true
	for id: String in ["bush", "berry_bush", "ember_bush", "grass", "glowfern", "cattail"]:
		var spec: Dictionary = DataRegistry.get_entry("plants", id)
		for variant: int in int(spec.columns):
			var bush: Bush = plant(Vector2i(5000 + checked * 16, 5), id, variant)
			var sprite: Sprite2D = bush.get_node("Sprite") as Sprite2D
			var image: Image = sprite.texture.get_image()
			var size: Vector2i = Vector2i(image.get_width() / sprite.hframes, image.get_height() / sprite.vframes)
			for species: String in ["beetle", "caterpillar", "snail"]:
				for point: Vector2 in LeafCritter.sites_for(bush, species):
					var local: Vector2i = Vector2i(point - sprite.offset)
					for y: int in range(-4, 1):
						for x: int in range(-4, 5):
							if image.get_pixelv(Vector2i(variant * size.x, 0) + local + Vector2i(x, y)).a < 0.9: habitat_ok = false
			bush.free()
			checked += 1
	check(habitat_ok, "full-body contact checked on every variant of all six plant types (%d)" % checked)

	var snail: LeafCritter = null
	for prop: WorldProp in bushes:
		if (prop as Bush)._critter.kind == "snail":
			snail = (prop as Bush)._critter
			break
	if snail != null:
		snail._near = true
		snail._sense = 10.0
		snail._pose(0.15)
		var halfway: float = snail._withdraw
		var resting: Vector2 = snail.position
		TimeManager.time_of_day += 0.5 / TimeManager.DAY_LENGTH_SEC
		snail._pose(0.15)
		check(halfway > 0.0 and halfway < 1.0 and snail.position == resting, "snail retracts gradually and its shell stops moving")
		snail._near = false
		snail._pose(0.15)
		check(snail._withdraw > 0.0 and snail._withdraw < 0.9, "snail extends cautiously instead of popping out")

	var dry_count: int = 0
	var wet_count: int = 0
	var dry_snails: int = 0
	var wet_snails: int = 0
	for day: int in range(1, 31):
		TimeManager.day = day
		var wet: bool = Moisture.is_wet_day(day)
		for prop: WorldProp in bushes:
			var species: String = LeafCritter._raw_kind(prop)
			if species.is_empty(): continue
			if wet:
				wet_count += 1
				if species == "snail": wet_snails += 1
			else:
				dry_count += 1
				if species == "snail": dry_snails += 1
	check(float(wet_snails) / wet_count > float(dry_snails) / dry_count * 2.0, "wet weather changes species balance toward snails")
	TimeManager.day = 3
	LeafCritter.settle_chunk(bushes)

	# The CPU leaf attachment follows the shader's whole-pixel wind displacement.
	var fern: Bush = plant(Vector2i(6000, 5), "glowfern", 0)
	var wind: WorldWind = WorldWind.new()
	add_child(wind)
	wind.set_process(false)
	wind.gust = 1.0
	wind.direction = Vector2.RIGHT
	var sites: PackedVector2Array = LeafCritter.sites_for(fern, "beetle")
	var wind_ok: bool = not sites.is_empty()
	if not sites.is_empty():
		var point: Vector2 = sites[0]
		var shift: Vector2 = (fern as Flora).critter_wind_offset(point)
		wind_ok = shift.x == roundf(shift.x) and shift.y == 0.0
		fern._critter.kind = "beetle"
		fern._critter._pose(0.0)
		var sprite: Sprite2D = fern.get_node("Sprite") as Sprite2D
		point = fern._critter._rest_point
		var expected: Vector2 = sprite.transform * (point + (fern as Flora).critter_wind_offset(point))
		wind_ok = wind_ok and fern._critter.position == expected
	check(wind_ok, "flora residents follow row-dependent whole-pixel wind")
	fern.free()
	wind.free()

	TimeManager.time_of_day = 0.5
	var chosen: Bush = null
	for bush: WorldProp in bushes:
		if before.has(bush.cell):
			chosen = bush as Bush
			break
	if chosen != null:
		var bug: LeafCritter = chosen._critter
		bug.refresh("")
		var sprite: Sprite2D = chosen.get_node("Sprite") as Sprite2D
		var base: Vector2 = sprite.transform.affine_inverse() * bug.position
		sprite.skew = 0.15
		sprite.scale.y = 0.86
		bug._pose(0.0)
		check(bug.position.distance_to(sprite.transform * base) < 0.01, "resident follows rustle and blight transforms")
		var clock: float = bug._clock
		get_tree().paused = true
		await get_tree().process_frame
		await get_tree().process_frame
		check(bug._clock == clock, "paused game freezes animal animation")
		get_tree().paused = false
		TimeManager.time_of_day = 0.95
		bug._process(0.1)
		check(not bug.visible and chosen.prompt() == "" and not LeafCritter.can_catch(chosen), "night hides resident and disables hand/sickle catching")
		TimeManager.time_of_day = 0.5
		bug._process(0.1)
		chosen.apply_state({"c": TimeManager.day + 1, "k": chosen.kind}, "catch")
		check(not LeafCritter.can_catch(chosen) and chosen.prompt() == "", "catch removes the interaction immediately during its animation")
		bug._process(1.0)
		var after: Dictionary = residents()
		check(after.size() == before.size() - 1 and not after.has(chosen.cell), "caught resident is not replaced by another plant in its square")
		chosen.apply_state({"h": 3, "k": chosen.kind}, "")

	var saved: Dictionary = {}
	for bush: WorldProp in bushes: saved[bush.cell] = bush.state.duplicate()
	for bush: WorldProp in bushes: bush.free()
	bushes.clear()
	var cells: Array = saved.keys()
	cells.reverse()
	for cell: Vector2i in cells: bushes.append(plant(cell, "bush", 1, saved[cell]))
	LeafCritter.settle_chunk(bushes)
	var reloaded: Dictionary = residents()
	var consistent: bool = reloaded.size() == before.size() - 1
	for cell: Vector2i in reloaded:
		if not before.has(cell) or reloaded[cell] != before[cell]: consistent = false
	check(consistent, "reverse reload preserves species, winners and absence even for a stripped winner")
	TimeManager.day += 1
	TimeManager.day_started.emit(TimeManager.day)
	var tomorrow: Dictionary = residents()
	check(not tomorrow.is_empty() and tomorrow != reloaded, "sunrise makes a new sparse daily population")

	for bush: WorldProp in bushes: bush.free()
	bushes.clear()
	await get_tree().process_frame
	check(LeafCritter._colonies.is_empty() and LeafCritter._winners.is_empty(), "unloading releases all world population references")
	print("LEAF CRITTERS failures=", failures)
	get_tree().quit(failures)
