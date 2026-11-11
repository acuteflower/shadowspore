extends Node
## Loot chests (docs/beutetruhen_konzept.md): the pure rolls, opening on the host (reach, once only, copper/XP, loot springing out),
## the hold prompts, a boss's chest (arrives, holds exactly its spoils and the relic, kept in the save until opened), save export/import.
## Run: Godot --headless --path . tools/test_loot_chests.tscn   (prints LOOT CHESTS OK)

var _ok: bool = true


func check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("LOOT CHESTS FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _drops() -> Array[ItemDrop]:
	var out: Array[ItemDrop] = []
	var box: Node = get_tree().get_first_node_in_group("drops")
	if box != null:
		for node: Node in box.get_children():
			if node is ItemDrop and not (node as ItemDrop).is_queued_for_deletion():
				out.append(node as ItemDrop)
	return out


func _run() -> void:
	_rules()
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var chests: LootChests = LootChests.of(get_tree())
	check(chests != null, "the world has a LootChests node")
	if chests == null:
		get_tree().quit(1)
		return
	check(chests.count() == 0, "no chest lies in the world yet (placed is empty)")
	chests.rng.seed = 7
	var player: Player = world._players.get_child(0) as Player
	var home: Vector2 = player.global_position
	# --- a common chest: too far, then near
	chests.request_dev("common", home + Vector2(300, 0))
	await get_tree().process_frame
	var chest: LootChest = chests.chest("dev_1")
	check(chest != null, "a dev chest was placed")
	if chest == null:
		get_tree().quit(1)
		return
	check(chest.prompt() == "ÖFFNEN", "a common chest opens with a tap: '%s'" % chest.prompt())
	chests.request_open("dev_1")
	await get_tree().process_frame
	check(not chests.is_open("dev_1"), "a far player cannot open it")
	player.request_teleport(chest.global_position + Vector2(0, 16))
	await _wait(0.3)
	var copper: int = int(player.progress.get("copper"))
	var before: int = _drops().size()
	chests.request_open("dev_1")
	await get_tree().process_frame
	check(chests.is_open("dev_1"), "near, it opens")
	check(chest.prompt() == "", "an open chest offers nothing")
	await _wait(1.4)
	check(int(player.progress.get("copper")) > copper, "copper was paid (%d -> %d)" % [copper, int(player.progress.get("copper"))])
	var sprung: int = _drops().size() - before
	check(sprung >= 2, "at least two pieces sprang out (%d)" % sprung)
	var high: bool = false
	for drop: ItemDrop in _drops():
		if drop.life > 200.0 and drop.pop > 0.0:
			high = true
	check(high, "chest loot springs high and lies long")
	var paid: int = int(player.progress.get("copper"))
	chests.request_open("dev_1")
	await _wait(1.0)
	check(int(player.progress.get("copper")) == paid, "a chest pays only once")
	# --- rare and legendary want a hold
	chests.request_dev("rare", player.global_position + Vector2(-60, 0))
	chests.request_dev("legendary", player.global_position + Vector2(-140, 0))
	await get_tree().process_frame
	check(chests.chest("dev_2").prompt() == "SIEGEL BRECHEN", "the moon chest wants its seal broken")
	check(chests.chest("dev_3").prompt() == "FESSELN LÖSEN", "the reliquary wants its chains loosed")
	check(not chests.export_state().opened.has("dev_1"), "test chests are never saved")
	# --- a boss's chest: comes down, holds the boss's spoils and its relic, waits in the save until opened
	var ledger: BossRelics = BossRelics.of(get_tree())
	ledger.forget("boss_sky_cleaver")
	var spot: Vector2 = player.global_position + Vector2(0, 60)
	var held: Dictionary = {"copper": 77, "xp": 40, "winners": [player.name.to_int()], "items": [{"id": "void_splinter", "count": 5}, {"id": "shadow_core", "count": 1}], "relics": [{"id": "rissfeder", "first": 1.0, "chance": 0.15}]}
	var bid: String = chests.boss_chest("boss_sky_cleaver", "legendary", spot, held, 0.2)
	check(bid != "", "a boss chest got an id")
	await _wait(0.4)
	var boss: LootChest = chests.chest(bid)
	check(boss != null and boss.arrive, "the boss chest came down out of the light")
	check(boss != null and boss.prompt() == "", "it cannot be used while it is still falling")
	await _wait(1.3)
	check(boss != null and boss.prompt() == "FESSELN LÖSEN", "landed, it offers to be opened")
	var saved: Dictionary = chests.export_state()
	check((saved.boss as Dictionary).has(bid), "an unopened boss chest is kept in the save")
	chests.import_state(saved) ## loading the same state again must not double it
	check(chests.count() == 4, "importing does not double the chests (%d)" % chests.count())
	player.request_teleport(spot + Vector2(0, 18))
	await _wait(0.3)
	copper = int(player.progress.get("copper"))
	chests.request_open(bid)
	await _wait(3.4)
	check(int(player.progress.get("copper")) - copper == 77, "the boss's copper came out of the chest (%d)" % (int(player.progress.get("copper")) - copper))
	var ids: Array[String] = []
	for drop: ItemDrop in _drops():
		ids.append(drop.story_id if drop.story_id != "" else drop.item_id)
	check(ids.has("void_splinter") and ids.has("shadow_core"), "the boss's items sprang out: %s" % [ids])
	check(ids.has(BossRelics.PREFIX + "rissfeder"), "the first kill's relic came out of the chest")
	check(not (chests.export_state().boss as Dictionary).has(bid), "an opened boss chest leaves the save")
	print("LOOT CHESTS ", "OK" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


func _rules() -> void:
	var table: Dictionary = DataRegistry.table("loot_chests")
	var pools: Dictionary = table.pools as Dictionary
	for pool: String in pools:
		for entry: Dictionary in pools[pool] as Array:
			check(not DataRegistry.get_entry("items", String(entry.id)).is_empty(), "item %s of pool %s exists" % [entry.id, pool])
	for tname: String in ["common", "rare", "legendary"]:
		check(ResourceLoader.exists("res://assets/props/chests/chest_%s.png" % tname), "art of %s" % tname)
		check((DataRegistry.table("loot_chest_art") as Dictionary).has(tname), "anchors of %s" % tname)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var mins: Dictionary = {"common": 0, "rare": 2, "legendary": 3}
	for tname: String in mins:
		var spec: Dictionary = (table.tiers as Dictionary)[tname] as Dictionary
		var low: int = 99
		var sorted_ok: bool = true
		var legends: int = 0
		for i: int in 300:
			var got: Array[Dictionary] = LootRules.roll(spec, pools, rng, 1)
			low = mini(low, got.size())
			for k: int in range(1, got.size()):
				if LootRules.rarity_rank(String(got[k - 1].id)) > LootRules.rarity_rank(String(got[k].id)):
					sorted_ok = false
			check(LootRules.best_rank(got) >= int(mins[tname]), "%s holds something of rank %d or better" % [tname, mins[tname]])
			if LootRules.best_rank(got) >= 4:
				legends += 1
		check(low >= 2, "%s always gives at least two pieces (%d)" % [tname, low])
		check(sorted_ok, "%s: the best piece comes last" % tname)
		if tname == "legendary":
			check(legends > 60 and legends < 160, "about a third of the reliquaries hold a legendary piece (%d / 300)" % legends)
	var solo: int = LootRules.roll((table.tiers as Dictionary).common as Dictionary, pools, rng, 1).size()
	var four: int = 0
	for i: int in 50:
		four += LootRules.roll((table.tiers as Dictionary).common as Dictionary, pools, rng, 4).size()
	check(four / 50.0 > solo, "more players near, more pieces")
	var bosses: Dictionary = DataRegistry.table("enemies")
	for boss: String in ["boss_sky_cleaver", "boss_morwenna"]:
		check(((bosses[boss] as Dictionary).loot as Dictionary).has("chest"), "%s leaves a chest" % boss)
	check(DropComponent.roll_entries([{"id": "stone", "chance": 1.0, "min": 2, "max": 2}]) == [{"id": "stone", "count": 2}], "roll_entries rolls without dropping")
