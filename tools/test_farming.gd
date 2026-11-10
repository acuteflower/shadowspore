extends Node
## docs/farming.md: the pure rules (tools, growth, harvest), the data, the soil painter (edge, neighbours), and the real world: unlock, placing a field, hoe, can, sowing,
## the night's growth, harvesting, saving and loading, demolishing. Run with `--fixed-fps 60`; prints `FARMING OK`.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("FARMING FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _find_site(town: TownManager, piece: String, around: Vector2) -> Vector2:
	for ring: int in range(0, 16):
		for k: int in 24:
			var p: Vector2 = TownRules.snapped_position(piece, around + Vector2.from_angle(TAU * float(k) / 24.0) * float(ring) * 10.0)
			if town.check_site(piece, p) == "":
				return p
	return Vector2.INF


func _select(player: Player, item: String) -> void:
	var inv: InventoryComponent = player.inventory
	for slot: int in inv.slots.size():
		if String((inv.slots[slot] as Dictionary).get("id", "")) == item:
			if slot >= 8:
				inv.request("move", [slot, 7])
				slot = 7
			inv.select(slot)
			return


func _rules() -> void:
	var cfg: Dictionary = FarmRules.config()
	_check(not cfg.is_empty() and FarmRules.crops().size() >= 4, "farming.json holds the crops")
	for id: String in FarmRules.crops():
		var spec: Dictionary = FarmRules.crop(id)
		_check(not Items.definition({"id": String(spec.seed)}).is_empty(), "seed item of %s exists" % id)
		_check(not Items.definition({"id": String((spec.yield as Dictionary).item)}).is_empty(), "yield item of %s exists" % id)
		_check(ResourceLoader.exists("res://assets/props/crops/crop_%s.png" % id), "sheet of %s exists" % id)
		_check(FarmRules.crop_for_seed(String(spec.seed)) == id, "seed -> crop for %s" % id)
	var wild_seeds: Dictionary = cfg.wild_seeds as Dictionary
	for wild: String in wild_seeds:
		_check(FarmRules.crop_for_seed(String((wild_seeds[wild] as Dictionary).seed)) != "", "wild seed of %s plants something" % wild)
	_check(String(Items.definition({"id": "hoe_basic"}).get("tool", "")) == "hoe" and String(Items.definition({"id": "watering_can"}).get("tool", "")) == "can", "hoe and can are tools")
	var day: int = 5
	var rough: Dictionary = {}
	_check(FarmRules.tool_wanted(rough, day) == "hoe", "rough ground wants the hoe")
	var tilled: Dictionary = FarmRules.apply_tool(rough, "hoe", day)
	var hoed: Dictionary = tilled.cell
	_check(bool(hoed.t) and tilled.fx == "till", "the hoe breaks the ground")
	_check(FarmRules.apply_tool(rough, "can", day).fx == "", "the can does nothing on rough ground")
	_check(FarmRules.apply_tool(hoed, "hoe", day).fx == "scrape", "the hoe rakes an empty bed again")
	_check(FarmRules.plant_block(rough, "tuber_seed") == "ERST HACKEN", "no sowing on rough ground")
	_check(FarmRules.plant_block(hoed, "wood") == "KEIN SAMEN", "wood is no seed")
	_check(FarmRules.plant_block(hoed, "tuber_seed") == "", "a seed fits a bed")
	var planted: Dictionary = FarmRules.plant(hoed, "tuber_seed", day)
	_check(FarmRules.plant_block(planted, "tuber_seed") == "SCHON BEPFLANZT", "a bed holds one crop")
	_check(FarmRules.tool_wanted(planted, day) == "can", "a dry crop wants the can")
	var watered: Dictionary = FarmRules.apply_tool(planted, "can", day).cell
	_check(FarmRules.tool_wanted(watered, day) == "" and FarmRules.is_wet(watered, day), "a watered bed wants nothing")
	_check(not FarmRules.is_wet(watered, day + 1), "the sun dries it")
	# growth: a tuber grows [1,1,2] = 4 watered nights
	var cell: Dictionary = planted
	var nights: int = 0
	var d: int = day
	while not FarmRules.is_ripe(cell) and nights < 12:
		cell = FarmRules.apply_tool(cell, "can", d).cell
		d += 1
		cell = FarmRules.sunrise(cell, d, false)
		nights += 1
	_check(FarmRules.is_ripe(cell) and nights == 4, "a tuber is ripe after 4 watered nights (%d)" % nights)
	_check(int(cell.m) == 0, "never missed a night")
	var dry: Dictionary = FarmRules.sunrise(planted, day + 1, false)
	_check(int(dry.a) == 0 and int(dry.m) == 1, "an unwatered night does not grow it")
	var rained: Dictionary = FarmRules.sunrise(planted, day + 1, true)
	_check(int(rained.a) == 1 and int(rained.get("m", 0)) == 0, "rain waters")
	var result: Dictionary = FarmRules.harvest(cell, 0.0, d)
	var drops: Array = result.drops
	_check(int((drops[0] as Dictionary).min) == 3 and int((drops[0] as Dictionary).max) == 4, "a well cared for crop gives one more")
	_check(drops.size() == 2 and String((drops[1] as Dictionary).id) == "tuber_seed", "a seed may come back")
	_check(not (result.cell as Dictionary).has("c") and bool((result.cell as Dictionary).t), "the bed stays, the crop is gone")
	var neglected: Dictionary = cell.duplicate()
	neglected.m = 2
	_check(int((FarmRules.harvest(neglected, 0.9, d).drops[0] as Dictionary).min) == 2, "no bonus for a neglected crop")
	var leaf: Dictionary = FarmRules.plant(hoed, "wound_leaf_seed", day)
	leaf.a = FarmRules.ripe_stage("wound_leaf")
	var again: Dictionary = FarmRules.harvest(leaf, 0.5, day).cell
	_check(String(again.c) == "wound_leaf" and int(again.a) == 2, "a wound leaf grows back")
	var idle: Dictionary = {"t": 1, "u": 2}
	_check(FarmRules.sunrise(idle, 3, false).has("t") and FarmRules.sunrise(idle, 2 + FarmRules.fallow_days(), false).is_empty(), "unused beds grow over")
	_check(FarmRules.cell_coords(7, 3) == Vector2i(1, 2) and FarmRules.cell_index(1, 2, 3) == 7, "cell index maths")
	_check(String(FarmRules.wild_seed("earth_tuber").get("id", "")) == "tuber_seed" and FarmRules.wild_seed("oak").is_empty(), "wild seeds")
	var recipes: Dictionary = DataRegistry.table("recipes")
	_check(String((recipes.get("hoe_basic", {}) as Dictionary).get("unlocks", "")) == "farming" and String((recipes.get("watering_can", {}) as Dictionary).get("unlocks", "")) == "farming", "hoe and can open the fields")
	_check(not TownRules.piece("field").is_empty() and bool(TownRules.piece("field").farm), "the field is a piece")


func _soil() -> void:
	var a: Rect2 = Rect2(100.0, 100.0, 48.0, 48.0)
	var b: Rect2 = Rect2(148.0, 100.0, 48.0, 48.0) ## right next to it
	var lone: Image = FieldSoil.render([a], a, 3, {}, 1)
	var joined: Image = FieldSoil.render([a, b], a, 3, {}, 1)
	var m: int = FieldSoil.MARGIN
	_check(lone.get_width() == 48 + m * 2 and lone.get_height() == 48 + m * 2, "the picture has a margin round the footprint")
	_check(lone.get_pixel(m + 24, m + 24).a > 0.99, "the middle is soil")
	_check(lone.get_pixel(0, 0).a == 0.0, "the corner of the margin is empty")
	var crumbs: int = 0
	for x: int in lone.get_width():
		if lone.get_pixel(x, m - 2).a > 0.0:
			crumbs += 1
	_check(crumbs > 0 and crumbs < lone.get_width(), "the edge crumbles outwards (%d of %d)" % [crumbs, lone.get_width()])
	var seam_lone: int = 0
	var seam_joined: int = 0
	for y: int in range(m + 4, m + 44):
		if lone.get_pixel(m + 47, y).a > 0.0:
			seam_lone += 1
		if joined.get_pixel(m + 47, y).a > 0.0:
			seam_joined += 1
	_check(seam_lone > 0, "alone the field has an edge on the right")
	_check(seam_joined == 40, "joined fields leave the shared seam to the neighbour or paint it as soil (%d)" % seam_joined)
	var tilled: Image = FieldSoil.render([a], a, 3, {4: {"t": 1}}, 1)
	var wet: Image = FieldSoil.render([a], a, 3, {4: {"t": 1, "w": 2}}, 1)
	var differ: int = 0
	var differ_wet: int = 0
	for y: int in range(m + 16, m + 32):
		for x: int in range(m + 16, m + 32):
			if tilled.get_pixel(x, y) != lone.get_pixel(x, y):
				differ += 1
			if tilled.get_pixel(x, y) != wet.get_pixel(x, y):
				differ_wet += 1
	_check(differ > 150, "a hoed cell looks different from rough ground (%d)" % differ)
	_check(differ_wet > 150, "a watered cell is darker than a dry bed (%d)" % differ_wet)
	_check(FieldSoil.render([a], a, 3, {4: {"t": 1}}, 1).get_data() == tilled.get_data(), "painting is deterministic")


func _run() -> void:
	_rules()
	_soil()
	(TownRules.piece("field") as Dictionary)["build_seconds"] = 0.5
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	player.request_teleport(hut.position + Vector2(0, 120))
	await _frames(90)
	player.quests.set_flag("rebuild_done")
	await _frames(100)
	_check(town.founded and town.farm != null, "the town is founded and has a farm manager")
	player.inventory.give("wood", 40)
	player.inventory.give("plant_fiber", 20)
	_check(not town.is_unlocked("field") and town.lock_reason("field") != "", "fields are locked before the first hoe (%s)" % town.lock_reason("field"))
	town.unlock("farming")
	await _frames(2)
	_check(town.is_unlocked("field") and town.unlocks.has("farming"), "the first hoe unlocks the fields")
	var at: Vector2 = _find_site(town, "field", hut.position + Vector2(70, 120))
	_check(at != Vector2.INF, "there is a free site for a field")
	town.request_place("field", at, false)
	await _frames(3)
	var field_id: int = town.next_id - 1
	for i: int in 300:
		await get_tree().process_frame
		if town.is_built(field_id):
			break
	_check(town.is_built(field_id), "the field is finished")
	var view: FarmField = town.view_of(field_id) as FarmField
	_check(view != null and view._cells.size() == 9, "the field has nine beds")
	_check(town.surface_at(town.rect_of(field_id).get_center()) == "field", "the ground is field soil (%s)" % town.surface_at(town.rect_of(field_id).get_center()))
	var farm: FarmManager = town.farm
	player.global_position = farm.cell_center(field_id, 4) + Vector2(0, 14)
	await _frames(2)
	player.inventory.give("hoe_basic", 1)
	player.inventory.give("watering_can", 1)
	player.inventory.give("tuber_seed", 3)
	var peer: int = player.get_multiplayer_authority()
	_select(player, "hoe_basic")
	farm.host_hit(field_id, 4, peer)
	await _frames(2)
	_check(bool(farm.cell_state(field_id, 4).get("t", 0)), "the hoe tills the bed")
	_select(player, "watering_can")
	farm.host_hit(field_id, 4, peer)
	await _frames(2)
	_check(FarmRules.is_wet(farm.cell_state(field_id, 4), TimeManager.day), "empty beds can be watered")
	var cell: FieldCell = view._cells[4]
	_check(String(cell.spec().get("tool", "x")) == "", "a watered empty bed wants no tool")
	_select(player, "tuber_seed")
	_check(cell.prompt() == "SÄEN", "a seed in the hand offers sowing (%s)" % cell.prompt())
	farm.request_plant(field_id, 4)
	await _frames(2)
	_check(String(farm.cell_state(field_id, 4).get("c", "")) == "tuber" and player.inventory.count_item("tuber_seed") == 2, "sowing uses a seed")
	farm.request_plant(field_id, 4)
	_check(player.inventory.count_item("tuber_seed") == 2, "a bed holds one crop")
	farm.request_plant(field_id, 0)
	_check(String(farm.cell_state(field_id, 0).get("c", "")) == "", "no sowing on rough ground")
	# the night: the table is updated by the host's sunrise function
	var day: int = TimeManager.day
	farm._on_day_started(day + 1)
	await _frames(2)
	_check(int(farm.cell_state(field_id, 4).get("p", 0)) + int(farm.cell_state(field_id, 4).get("a", 0)) >= 1, "the watered crop grew overnight")
	# make it ripe by hand (the clock does not run here)
	var state: Dictionary = farm.cell_state(field_id, 4).duplicate()
	state["a"] = FarmRules.ripe_stage("tuber")
	farm._rpc_cell(field_id, 4, state, "grow")
	await _frames(2)
	_select(player, "")
	_check(cell.prompt() == "ERNTEN", "a ripe crop offers harvesting (%s) state %s cellstate %s ui %s" % [cell.prompt(), str(cell.state), str(farm.cell_state(field_id, 4)), str(InputManager.ui_blocking)])
	farm.request_harvest(field_id, 4)
	await _frames(3)
	_check(String(farm.cell_state(field_id, 4).get("c", "")) == "" and bool(farm.cell_state(field_id, 4).get("t", 0)), "harvest empties the bed")
	_check(get_tree().get_nodes_in_group("drops").size() > 0 or player.inventory.count_item("earth_tuber") > 0, "the harvest drops something")
	# save and load
	farm._set_cell(field_id, 2, {"t": 1, "c": "ember_carrot", "a": 2, "p": 1, "m": 0, "u": day})
	var snap: Dictionary = farm.export_state()
	farm.fields.clear()
	farm.import_state(snap)
	await _frames(2)
	_check(String(farm.cell_state(field_id, 2).get("c", "")) == "ember_carrot" and int(farm.cell_state(field_id, 2).get("a", 0)) == 2, "state survives a save round trip")
	var full: Dictionary = town.export_state()
	_check(full.has("farm") and full.has("unlocks"), "the town save holds farm and unlocks")
	town.request_demolish(field_id)
	await _frames(3)
	_check(not farm.fields.has(field_id) and town.view_of(field_id) == null, "demolishing a field takes its beds along")
	print("FARMING OK" if _ok else "FARMING FAILED")
	get_tree().quit(0 if _ok else 1)
