class_name SaveGame
extends RefCounted
## Separate solo and hosted saves: the clock, the local player (position, health,
## money, XP, bag and equipment) and the state of the world's props (picked, felled, ...). The host
## saves; `load_into` restores it right after the world is built. Enemies and drops are not saved.

const PATH: String = "user://save.json"
const COOP_PATH: String = "user://coop_save.json"
const VERSION: int = 1


static func path_for(tree: SceneTree) -> String:
	return COOP_PATH if tree.root.multiplayer.multiplayer_peer is ENetMultiplayerPeer else PATH


static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func delete(path: String = PATH) -> bool:
	if FileAccess.file_exists(path):
		var err: Error = DirAccess.remove_absolute(path)
		return err == OK
	return true


## When and where the game was last saved: {saved_at, day, time}; empty without a save.
static func info(path: String = PATH) -> Dictionary:
	var data: Dictionary = _read(path)
	return {} if data.is_empty() else {"saved_at": int(data.get("saved_at", 0)), "day": int(data.get("day", 0)), "time": float(data.get("time", 0.0))}


static func save(tree: SceneTree, path: String = "") -> bool:
	var player: Player = _local_player(tree)
	if player == null or not tree.root.multiplayer.is_server():
		return false
	var target: String = path if path != "" else path_for(tree)
	player.inventory.stow_held() ## a stack on the cursor goes back into the bag first
	var position: Vector2 = player.climb.save_position()
	var data: Dictionary = {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"time": TimeManager.time_of_day,
		"day": TimeManager.day,
		"player": {
			"pos": [position.x, position.y],
			"health": player.health.current,
			"copper": player.progress.copper,
			"xp": player.progress.xp,
			"claimed": player.progress.claimed, ## the level whose rewards were collected (Fortschritt window): health, stamina, armor, talisman slots follow it
			"skill_tree": (player.get_node("SkillTreeComponent") as SkillTreeComponent).export_data(),
			"slots": player.inventory.slots,
			"equipment": player.inventory.equipment,
			"raw_rolls": player.inventory.hidden, ## what the raw stones in the bag hide (Ilva's LÄUTERN)
			"bandaged": player.bandaged,
			"quests": player.quests.export_data() if player.quests != null else {},
			"board_local": player.tracked.export_data() if player.tracked != null else {}, ## journal focus, page and read notices
		},
	}
	var world: Node = tree.get_first_node_in_group("world")
	if world != null and world.get("opening_over") != null:
		data["opening_over"] = bool(world.get("opening_over")) ## the clock stays locked at midnight until the opening is over
	if world != null and world.has_method("export_things"):
		data["things"] = world.call("export_things")
	if world != null and world.has_method("export_story"):
		data["story"] = world.call("export_story")
	var mines: MineManager = tree.get_first_node_in_group("mines") as MineManager
	if mines != null:
		data["mine"] = mines.export_state() ## opened chests, mended lifts, depth, kills; the mined rocks are in "things"
	var town: TownManager = tree.get_first_node_in_group("town") as TownManager
	if town != null and (town.founded or tree.root.multiplayer.multiplayer_peer is ENetMultiplayerPeer):
		data["town"] = town.export_state() ## the pieces, the stock, the ways, the residents (docs/town.md)
	var night: NightDirector = tree.get_first_node_in_group("night_director") as NightDirector
	if night != null:
		data["night"] = night.export_state() ## where the base held and where it gave way (docs/nacht_monster_konzept.md)
	var waystones: Waystones = Waystones.of(tree)
	if waystones != null and waystones.awake_count() > 0:
		data["waystones"] = waystones.export_state() ## the awakened goddess statues (docs/waystones.md)
	var rings: Dictionary = {}
	for node: Node in tree.get_nodes_in_group("ward_rings"):
		rings[(node as WardRing).id] = (node as WardRing).export_state()
	if not rings.is_empty():
		data["ward_rings"] = rings ## the ward stones round the lake witch's house: awake or out (docs/seehexe_konzept.md)
	var witch: WitchArena = tree.get_first_node_in_group("witch_arena") as WitchArena
	if witch != null and (witch.released or witch.opened):
		data["witch"] = witch.export_state() ## Morwenna was released: the Rabenbaum stays free (docs/enemies/boss_mora.md)
	var relics: BossRelics = BossRelics.of(tree)
	if relics != null:
		data["relics"] = relics.export_state() ## boss kills per player and the relics not picked up yet (docs/rissfeder.md)
	var chests: LootChests = LootChests.of(tree)
	if chests != null:
		data["chests"] = chests.export_state() ## opened loot chests and the bosses' chests not opened yet (docs/beutetruhen_konzept.md)
	var puzzles: Puzzles = Puzzles.of(tree)
	if puzzles != null and not puzzles.is_blank():
		data["puzzles"] = puzzles.export_state() ## the solved trials of the Wächterin (docs/raetsel_konzept.md)
	var pets: PetRegistry = PetRegistry.of(tree)
	if pets != null and not (pets.export_state()["bonds"] as Dictionary).is_empty():  ## (the birds' records only exist with a bond)
		data["pets"] = pets.export_state() ## the bonds with wild birds (docs/pet_konzept.md)
	var discovery: MapDiscovery = tree.get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		data["map"] = Marshalls.raw_to_base64(discovery.export_data())
		if discovery.is_reveal_all():
			data["map_before"] = Marshalls.raw_to_base64(discovery.export_before()) ## the fog from before the developer's whole-map reveal
	var pending: String = target + ".tmp"
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var written: bool = file.get_error() == OK
	file.close()
	return written and DirAccess.rename_absolute(pending, target) == OK


static func load_into(tree: SceneTree, path: String = "", resume: bool = true) -> bool:
	var data: Dictionary = _read(path if path != "" else path_for(tree))
	var player: Player = _local_player(tree)
	if data.is_empty() or player == null:
		return false
	var saved: Dictionary = data.get("player", {})
	## A save made after the opening (she woke up in the hut) must not start with the opening's midnight lock: WorldLevel._ready locks the
	## clock at 00:00 until `finish_opening`, and `opening_over` is not a node state that survives a reload. Older saves have no
	## "opening_over" key, so the flag `woke_up` in the quest block counts too.
	var world_node: Node = tree.get_first_node_in_group("world")
	var quest_flags: Dictionary = (saved.get("quests", {}) as Dictionary).get("flags", {}) as Dictionary
	var opening_done: bool = bool(data.get("opening_over", false)) or bool(quest_flags.get("woke_up", false))
	if opening_done and world_node != null and world_node.has_method("finish_opening"):
		world_node.call("finish_opening") ## sets opening_over and unlocks the clock
	if not TimeManager.locked: ## the opening holds the clock at midnight
		TimeManager.time_of_day = float(data.get("time", TimeManager.time_of_day))
		TimeManager.day = int(data.get("day", 0))
	var pos: Array = saved.get("pos", [])
	if pos.size() == 2:
		player.position = Vector2(float(pos[0]), float(pos[1]))
		(player.get_node("Camera2D") as Camera2D).reset_smoothing()
	player.progress.xp = int(saved.get("xp", 0))
	player.progress.restore_claimed(int(saved.get("claimed", 1))) ## before the health: the maximum depends on it
	var health: float = float(saved.get("health", player.health.max_health))
	player.health.current = health if health > 0.0 else player.health.max_health
	player.sync_wound_visuals()
	player.progress.copper = int(saved.get("copper", 0))
	player.progress.xp = int(saved.get("xp", 0))
	player.progress.award(0, 0)
	(player.get_node("SkillTreeComponent") as SkillTreeComponent).import_data(saved.get("skill_tree", {}) as Dictionary)
	_restore_stacks(player.inventory, saved)
	player.inventory.import_hidden(saved.get("raw_rolls", {}) as Dictionary)
	player.set_bandaged(bool(saved.get("bandaged", false)))
	player.sync_wound_visuals()
	if player.quests != null and saved.has("quests"):
		player.quests.import_data(saved.quests as Dictionary)
	if player.tracked != null and saved.has("board_local"):
		player.tracked.import_data(saved.board_local as Dictionary)
	var world: Node = tree.get_first_node_in_group("world")
	if world != null and world.has_method("import_things"):
		world.call("import_things", data.get("things", {}))
	if world != null and world.has_method("import_story"):
		world.call("import_story", data.get("story", {}))
	var mines: MineManager = tree.get_first_node_in_group("mines") as MineManager
	if mines != null:
		mines.import_state(data.get("mine", {}) as Dictionary)
	var town: TownManager = tree.get_first_node_in_group("town") as TownManager
	if town != null and data.has("town"):
		town.import_state(data.town as Dictionary)
	var night: NightDirector = tree.get_first_node_in_group("night_director") as NightDirector
	if night != null and data.has("night"):
		night.import_state(data.night as Dictionary)
	var waystones: Waystones = Waystones.of(tree)
	if waystones != null and data.has("waystones"):
		waystones.import_state(data.waystones as Dictionary)
	for ring_id: Variant in (data.get("ward_rings", {}) as Dictionary):
		var ring: WardRing = WardRing.by_id(tree, String(ring_id))
		if ring != null:
			ring.import_state(bool((data.ward_rings as Dictionary)[ring_id]))
	var witch: WitchArena = tree.get_first_node_in_group("witch_arena") as WitchArena
	if witch != null and data.has("witch"):
		witch.import_state(data.witch as Dictionary)
	var relics: BossRelics = BossRelics.of(tree)
	if relics != null and data.has("relics"):
		relics.import_state(data.relics as Dictionary)
	var chests: LootChests = LootChests.of(tree)
	if chests != null and data.has("chests"):
		chests.import_state(data.chests as Dictionary)
	var puzzles: Puzzles = Puzzles.of(tree)
	if puzzles != null and data.has("puzzles"):
		puzzles.import_state(data.puzzles as Dictionary)
	var pets: PetRegistry = PetRegistry.of(tree)
	if pets != null and data.has("pets"):
		pets.import_state(data.pets as Dictionary)
	var discovery: MapDiscovery = tree.get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null and data.has("map"):
		discovery.import_saved(Marshalls.base64_to_raw(String(data["map"])))
		discovery.import_before(Marshalls.base64_to_raw(String(data.get("map_before", "")))) ## empty = no whole-map reveal active
	if resume and world != null and world.has_method("resume_story"):
		world.call_deferred("resume_story", player) ## a save that stopped in the middle of the wake-up plays it again
	return true


static func _restore_stacks(inventory: InventoryComponent, saved: Dictionary) -> void:
	var slots: Array = saved.get("slots", [])
	for i: int in mini(slots.size(), inventory.slots.size()):
		inventory.slots[i] = _stack(slots[i])
	var equipment: Dictionary = saved.get("equipment", {})
	for slot_name: String in inventory.equipment:
		inventory.equipment[slot_name] = _stack(equipment.get(slot_name, {}))
	inventory.changed.emit()


## Host-side guest state used by board delivery and rewards. A joining client requests
## the restored inventory and balances through the normal player-component snapshots.
static func guest_economy(player: Player) -> Dictionary:
	var skills: SkillTreeComponent = player.get_node("SkillTreeComponent") as SkillTreeComponent
	return {
		"slots": player.inventory.slots.duplicate(true), "equipment": player.inventory.equipment.duplicate(true),
		"held": player.inventory.held.duplicate(true), "raw_rolls": player.inventory.hidden.duplicate(true), "xp": player.progress.xp, "copper": player.progress.copper,
		"claimed": player.progress.claimed, "skill_tree": skills.export_data(),
	}


static func restore_guest_economy(player: Player, saved: Dictionary) -> void:
	player.progress.xp = int(saved.get("xp", 0))
	player.progress.copper = int(saved.get("copper", 0))
	player.progress.claimed = clampi(int(saved.get("claimed", 1)), 1, maxi(player.progress.level, 1))
	player.progress.apply_stats(false)
	player.progress.changed.emit()
	var skills: SkillTreeComponent = player.get_node("SkillTreeComponent") as SkillTreeComponent
	skills.import_data(saved.get("skill_tree", {}) as Dictionary)
	player.inventory.held = _stack(saved.get("held", {}))
	_restore_stacks(player.inventory, saved)
	player.inventory.import_hidden(saved.get("raw_rolls", {}) as Dictionary)


## JSON turns counts into floats: back to a clean stack.
static func _stack(raw: Variant) -> Dictionary:
	var stack: Dictionary = raw as Dictionary
	if stack == null or stack.is_empty():
		return {}
	var clean: Dictionary = stack.duplicate()
	clean["count"] = int(stack.get("count", 1))
	for key: String in [RefineRules.KEY_LEVEL, RefineRules.KEY_PITY]:
		if clean.has(key):
			clean[key] = int(clean[key]) ## the refinement of a weapon, also back from JSON floats
	return clean


static func _local_player(tree: SceneTree) -> Player:
	for node: Node in tree.get_nodes_in_group("players"):
		if node.is_multiplayer_authority():
			return node as Player
	return null


static func _read(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
