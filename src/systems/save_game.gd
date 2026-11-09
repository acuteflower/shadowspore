class_name SaveGame
extends RefCounted
## One save file (user://save.json) for singleplayer: the clock, the local player (position, health,
## money, XP, bag and equipment) and the state of the world's props (picked, felled, ...). The host
## saves; `load_into` restores it right after the world is built. Enemies and drops are not saved.

const PATH: String = "user://save.json"
const VERSION: int = 1


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func delete(path: String = PATH) -> bool:
	if FileAccess.file_exists(path):
		var err: Error = DirAccess.remove_absolute(path)
		return err == OK
	return true


## When and where the game was last saved: {saved_at, day, time}; empty without a save.
static func info() -> Dictionary:
	var data: Dictionary = _read()
	return {} if data.is_empty() else {"saved_at": int(data.get("saved_at", 0)), "day": int(data.get("day", 0)), "time": float(data.get("time", 0.0))}


static func save(tree: SceneTree, path: String = PATH) -> bool:
	var player: Player = _local_player(tree)
	if player == null or not tree.root.multiplayer.is_server():
		return false
	player.inventory.stow_held() ## a stack on the cursor goes back into the bag first
	var data: Dictionary = {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"time": TimeManager.time_of_day,
		"day": TimeManager.day,
		"player": {
			"pos": [player.position.x, player.position.y],
			"health": player.health.current,
			"copper": player.progress.copper,
			"xp": player.progress.xp,
			"claimed": player.progress.claimed, ## the level whose rewards were collected (Fortschritt window): health, stamina, armor, talisman slots follow it
			"skill_tree": (player.get_node("SkillTreeComponent") as SkillTreeComponent).export_data(),
			"slots": player.inventory.slots,
			"equipment": player.inventory.equipment,
			"bandaged": player.bandaged,
			"quests": player.quests.export_data() if player.quests != null else {},
		},
	}
	var world: Node = tree.get_first_node_in_group("world")
	if world != null and world.has_method("export_things"):
		data["things"] = world.call("export_things")
	if world != null and world.has_method("export_story"):
		data["story"] = world.call("export_story")
	var mines: MineManager = tree.get_first_node_in_group("mines") as MineManager
	if mines != null:
		data["mine"] = mines.export_state() ## opened chests, mended lifts, depth, kills; the mined rocks are in "things"
	var town: TownManager = tree.get_first_node_in_group("town") as TownManager
	if town != null and town.founded:
		data["town"] = town.export_state() ## the pieces, the stock, the ways, the residents (docs/town.md)
	var night: NightDirector = tree.get_first_node_in_group("night_director") as NightDirector
	if night != null:
		data["night"] = night.export_state() ## where the base held and where it gave way (docs/nacht_monster_konzept.md)
	var waystones: Waystones = Waystones.of(tree)
	if waystones != null and waystones.awake_count() > 0:
		data["waystones"] = waystones.export_state() ## the awakened goddess statues (docs/waystones.md)
	var discovery: MapDiscovery = tree.get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		data["map"] = Marshalls.raw_to_base64(discovery.export_data())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true


static func load_into(tree: SceneTree, path: String = PATH) -> bool:
	var data: Dictionary = _read(path)
	var player: Player = _local_player(tree)
	if data.is_empty() or player == null:
		return false
	if not TimeManager.locked: ## the opening holds the clock at midnight
		TimeManager.time_of_day = float(data.get("time", TimeManager.time_of_day))
		TimeManager.day = int(data.get("day", 0))
	var saved: Dictionary = data.get("player", {})
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
	player.set_bandaged(bool(saved.get("bandaged", false)))
	player.sync_wound_visuals()
	if player.quests != null and saved.has("quests"):
		player.quests.import_data(saved.quests as Dictionary)
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
	var discovery: MapDiscovery = tree.get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null and data.has("map"):
		discovery.import_saved(Marshalls.base64_to_raw(String(data["map"])))
	if world != null and world.has_method("resume_story"):
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
