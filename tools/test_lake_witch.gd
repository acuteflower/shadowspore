extends Node
## The lake witch, step 2 (docs/seehexe_konzept.md 11): ILVA lives in her room (`InteriorResident`, data/settlers.json lake_witch) with a daily plan, her sheet
## and rig are there, talking builds trust, her shop `lake_counter` has KAUFEN / VERKAUFEN / STÄBE / LÄUTERN / SCHLIFF / DEV, SCHLIFF lifts three equal stones
## a tier (`CrystalRules`, crystals from glimmer, gems from moonstone), the DEV tab hands out staves/crystals/gems for free, everything only in reach of her
## room. Prints `LAKE WITCH OK`. `-- --capture=/abs/dir` saves pictures (window, `--rendering-driver opengl3`).
var _ok: bool = true
var _dir: String = ""
var _checks: int = 0


func _check(name: String, value: bool) -> void:
	_checks += 1
	if not value:
		_ok = false
		print("FAILED: ", name)


func _shot(name: String) -> void:
	if _dir == "":
		return
	for _i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_dir = arg.trim_prefix("--capture=")
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _run() -> void:
	# the pure rules first
	_check("tier of a crystal", CrystalRules.tier_of("crystal_banish_2") == 2 and CrystalRules.tier_of("gem_lens_4") == 4 and CrystalRules.tier_of("wood") == 0)
	_check("next tier", CrystalRules.next_of("crystal_maw_1") == "crystal_maw_2" and CrystalRules.next_of("gem_haze_4") == "gem_haze_5")
	_check("no tier above V", CrystalRules.next_of("crystal_roots_5") == "" and CrystalRules.next_of("lake_glimmer") == "")
	var grind: Dictionary = (DataRegistry.get_entry("shops", "lake_counter").get("grind", {})) as Dictionary
	_check("crystals grow from glimmer", ((CrystalRules.cost(grind, "crystal_veil_1").in as Dictionary).has("lake_glimmer")))
	_check("gems are cut from moonstone", ((CrystalRules.cost(grind, "gem_wild_1").in as Dictionary).has("lake_moonstone")))
	_check("three equal stones needed", CrystalRules.block(grind, "crystal_veil_1", {"crystal_veil_1": 2, "lake_glimmer": 9}, 999, 100) != "")
	_check("trust gate", "VERTRAUEN" in CrystalRules.block(grind, "crystal_veil_3", {"crystal_veil_3": 3, "lake_glimmer": 9, "void_splinter": 9}, 999, 0))
	_check("free when all is there", CrystalRules.block(grind, "crystal_veil_1", {"crystal_veil_1": 3, "lake_glimmer": 2}, 40, 0) == "")
	var dev: Dictionary = DataRegistry.get_entry("shops", "lake_counter").get("dev", {}) as Dictionary
	_check("dev lists the staff and every stone", CrystalRules.dev_items(dev).has("staff_hag_elm") and CrystalRules.dev_items(dev).has("crystal_maw_5") and CrystalRules.dev_items(dev).has("gem_hunger_5"))
	_check("raw roll: first kind, tier I", CrystalRules.roll(CrystalRules.hidden_of("lake_glimmer"), 0.0, 0.0) == "crystal_banish_1")
	_check("raw roll: last kind, rare tier", CrystalRules.roll(CrystalRules.hidden_of("lake_moonstone"), 0.999, 0.999) == "gem_hunger_4")
	_check("refresh needs the stone and the fee", CrystalRules.refresh_block({"fee": {"lake_glimmer": 18}}, "lake_glimmer", 1, 0, 99, 0) != ""
		and CrystalRules.refresh_block({"fee": {"lake_glimmer": 18}}, "lake_glimmer", 2, 2, 20, 0) == "ZU WENIG GELD"
		and CrystalRules.refresh_block({"fee": {"lake_glimmer": 18}}, "lake_glimmer", 1, 1, 18, 0) == "")
	_check("dev refuses other things", not CrystalRules.dev_allowed(dev, "sword_basic") and CrystalRules.dev_allowed(dev, "lake_glimmer"))
	# the world, her room
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = get_tree().get_first_node_in_group("town") as TownManager
	var hut: Hut = world.get_node("Hut_lake_hut") as Hut
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	player.global_position = hut.exit_position
	await _frames(60)
	interiors.use_door(player, hut.doorway)
	await get_tree().create_timer(1.8).timeout
	_check("inside her room", Interiors.slot_at(player.global_position) >= 0)
	var ilva: InteriorResident = null
	for node: Node in get_tree().get_nodes_in_group("quest_actors"):
		if node is InteriorResident and (node as InteriorResident).sid == "lake_witch":
			ilva = node as InteriorResident
	_check("she lives there", ilva != null)
	if ilva == null:
		_finish()
		return
	_check("her sheet and rig", ilva._sprite != null and ilva._glow != null and (ilva._rig.clips as Dictionary).has("grind") and (ilva._rig.clips as Dictionary).has("basin"))
	_check("plan: counter in the morning", String(ilva.plan_at(0.35).spot) == "counter")
	_check("plan: the wheel at noon", String(ilva.plan_at(0.47).spot) == "grind")
	_check("plan: the basin at night", String(ilva.plan_at(0.92).spot) == "basin")
	TimeManager.set_time(0.35)
	await _frames(20)
	_check("at her counter", ilva.position.distance_to(Vector2(214, 192)) < 2.0 and ilva._clip == "counter")
	TimeManager.set_time(0.47)
	await _frames(20)
	_check("she grinds at the wheel", ilva._clip == "grind" or ilva._clip == "walk")
	TimeManager.set_time(0.35)
	await _frames(20)
	_check("the town knows her", town.person_node("lake_witch") == ilva)
	player.global_position = ilva.global_position + Vector2(0, 46)
	await _shot("0_counter")
	var trust_before: int = town.trust_of("lake_witch")
	town.request_talk("lake_witch")
	await _frames(2)
	_check("a talk builds trust", town.trust_of("lake_witch") == trust_before + 10)
	_check("the prompt is HANDELN after the talk", ilva.prompt() == "HANDELN")
	# the shop
	var window: ShopWindow = ShopWindow.open(get_tree(), player, town, "lake_counter")
	await _frames(4)
	_check("the shop opens", window != null and window.tabs.size() == 6)
	var names: Array[String] = []
	for t: Dictionary in window.tabs:
		names.append(String(t.name))
	_check("tabs", names == ["KAUFEN", "VERKAUFEN", "STÄBE", "LÄUTERN", "SCHLIFF", "DEV"])
	var counts: Dictionary = {}
	for i: int in window.tabs.size():
		window.tab = i
		window._rebuild()
		counts[String(window.tabs[i].kind) + String(window.tabs[i].get("group", ""))] = window.rows.size()
	_check("buy lists stones", int(counts.get("buy", 0)) >= 20)
	_check("staves tab", int(counts.get("craftstaff", 0)) >= 1) ## the Hexenulmenstab, and any later staff with group "staff"
	_check("no stones tab", not counts.has("craftstone"))
	_check("dev tab lists everything", int(counts.get("dev", 0)) >= 51)
	await _shot("1_shop")
	# DEV: free, one by one
	player.inventory.clear_all()
	town.request_dev_give("lake_counter", "crystal_banish_1", 3)
	town.request_dev_give("lake_counter", "staff_hag_elm", 1)
	town.request_dev_give("lake_counter", "sword_basic", 1)
	await _frames(2)
	_check("dev gave 3 crystals", player.inventory.count_item("crystal_banish_1") == 3)
	_check("dev gave the staff", player.inventory.has_item("staff_hag_elm"))
	_check("dev gives nothing else", not player.inventory.has_item("sword_basic"))
	# SCHLIFF
	town.request_dev_give("lake_counter", "lake_glimmer", 2)
	player.progress.award(500, 0)
	var copper: int = player.progress.copper
	await _frames(2)
	town.request_grind("lake_counter", "crystal_banish_1")
	await _frames(2)
	_check("three became one a tier higher", player.inventory.count_item("crystal_banish_2") == 1 and player.inventory.count_item("crystal_banish_1") == 0)
	_check("the glimmer was used", player.inventory.count_item("lake_glimmer") == 0)
	_check("the copper was paid", player.progress.copper == copper - 40)
	town.request_dev_give("lake_counter", "gem_lens_1", 3)
	town.request_dev_give("lake_counter", "lake_moonstone", 2)
	await _frames(2)
	town.request_grind("lake_counter", "gem_lens_1")
	await _frames(2)
	_check("a gem cut a tier higher from moonstone", player.inventory.count_item("gem_lens_2") == 1 and player.inventory.count_item("lake_moonstone") == 0)
	town.request_grind("lake_counter", "crystal_banish_2")
	await _frames(2)
	_check("one stone alone is not enough", player.inventory.count_item("crystal_banish_2") == 1 and player.inventory.count_item("crystal_banish_3") == 0)
	# LÄUTERN: each raw stone hid its stone from the moment it came into the bag
	town.request_dev_give("lake_counter", "lake_glimmer", 4)
	await _frames(2)
	var rolls: Array = (player.inventory.hidden.get("lake_glimmer", []) as Array).duplicate()
	_check("found = already rolled", rolls.size() == player.inventory.count_item("lake_glimmer") and rolls.size() == 4)
	_check("the rolls are real stones", rolls.all(func(r: Variant) -> bool: return CrystalRules.tier_of(String(r)) >= 1 and String(r).begins_with("crystal_")))
	player.inventory.request("move", [player.inventory.slots.find(player.inventory.slots.filter(func(x: Dictionary) -> bool: return not x.is_empty() and String(x.id) == "lake_glimmer")[0]), 31]) ## moving does not reroll
	await _frames(2)
	_check("moving keeps the rolls", (player.inventory.hidden.get("lake_glimmer", []) as Array) == rolls)
	var revealed: Array = []
	town.refresh_done.connect(func(_raw: String, stones: Array) -> void: revealed.append_array(stones))
	var before_fee: int = player.progress.copper
	if window != null and is_instance_valid(window):
		window.tab = names.find("LÄUTERN")
		window._rebuild()
	var held_first: int = player.inventory.count_item(String(rolls[0]))
	town.request_refresh("lake_counter", "lake_glimmer", 1)
	await _frames(2)
	_check("refresh gives the rolled stone", revealed == [rolls[0]] and player.inventory.count_item(String(rolls[0])) == held_first + 1)
	_check("LÄUTERN is free and takes the raw stone", player.progress.copper == before_fee and player.inventory.count_item("lake_glimmer") == 3)
	_check("the other rolls stay", (player.inventory.hidden.get("lake_glimmer", []) as Array) == rolls.slice(1))
	player.inventory.remove_item("lake_glimmer", 1) ## used up elsewhere (feeding a ward stone, a recipe): its roll goes with it
	await _frames(2)
	_check("a used stone takes its roll", (player.inventory.hidden.get("lake_glimmer", []) as Array).size() == 2)
	if _dir != "":
		await _shot("2_refresh_tab")
		await get_tree().create_timer(1.8).timeout ## the card shows what the stone hid
		await _shot("2_refresh_card")
	town.request_dev_give("lake_counter", "lake_moonstone", 3)
	await _frames(2)
	revealed.clear()
	town.request_refresh("lake_counter", "lake_moonstone", 3)
	await _frames(2)
	_check("ALLE: three gems at once", revealed.size() == 3 and revealed.all(func(r: Variant) -> bool: return String(r).begins_with("gem_")) and player.inventory.count_item("lake_moonstone") == 0)
	_check("no rolls left for spent stones", not player.inventory.hidden.has("lake_moonstone"))
	var saved: Dictionary = player.inventory.hidden.duplicate(true)
	player.inventory.import_hidden(saved)
	_check("the rolls survive a save", player.inventory.hidden == saved)
	for raw: String in ["lake_glimmer"]:
		player.inventory.remove_item(raw, player.inventory.count_item(raw))
	# STÄBE: crafted at her bench (stones are no longer crafted: raw stones are washed free, LÄUTERN)
	town.request_dev_give("lake_counter", "lake_glimmer", 3)
	town.request_dev_give("lake_counter", "hag_wood", 4)
	town.request_dev_give("lake_counter", "curse_silver", 2)
	await _frames(2)
	_check("no stone recipes any more", not town.recipes().has("lake_crystal_banish_1"))
	player.inventory.remove_item("staff_hag_elm", 1)
	town.request_craft("staff_hag_elm")
	await _frames(2)
	_check("she builds the staff", player.inventory.has_item("staff_hag_elm"))
	# KAUFEN
	var before_buy: int = player.progress.copper
	town.request_trade("lake_counter", "buy", "crystal_roots_1", 1)
	await _frames(2)
	_check("buying a splinter", player.inventory.count_item("crystal_roots_1") >= 1 and player.progress.copper == before_buy - 60)
	if window != null and is_instance_valid(window):
		window.queue_free()
	await _frames(2)
	# out of reach: outside the room nothing is ground
	interiors.use_door(player, interiors.interior("lake_hut").door)
	await get_tree().create_timer(1.8).timeout
	town.request_dev_give("lake_counter", "crystal_roots_1", 3)
	town.request_dev_give("lake_counter", "lake_glimmer", 2)
	await _frames(2)
	var held: int = player.inventory.count_item("crystal_roots_1")
	town.request_grind("lake_counter", "crystal_roots_1")
	await _frames(2)
	_check("no grinding outside her room", player.inventory.count_item("crystal_roots_1") == held and player.inventory.count_item("crystal_roots_2") == 0)
	_finish()


func _finish() -> void:
	print("%d checks" % _checks)
	print("LAKE WITCH OK" if _ok else "LAKE WITCH FAILED")
	get_tree().quit(0 if _ok else 1)
