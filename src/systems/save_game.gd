class_name SaveGame
extends RefCounted
## Separate solo and hosted saves: the clock, the local player (position, health,
## money, XP, bag and equipment) and the state of the world's props (picked, felled, ...). The host
## saves; `load_into` restores it right after the world is built. Enemies and drops are not saved.

const PATH: String = "user://save.json"
const COOP_PATH: String = "user://coop_save.json"
const ZONES_PATH: String = "user://save_zones.json"
const COOP_ZONES_PATH: String = "user://coop_save_zones.json"
const VERSION: int = 1
const MAX_CLOUD_WORLD_BYTES: int = 16777216

static var _io_mutex: Mutex = Mutex.new()


## Coerces JSON/Nakama-decoded Variant values safely (Nakama Lua serializes `{}` as `[]`).
static func as_dict(raw: Variant) -> Dictionary:
	return raw as Dictionary if raw is Dictionary else {}


## Coerces JSON-decoded Variant values safely to Array.
static func as_array(raw: Variant) -> Array:
	return raw as Array if raw is Array else []


static func is_zones_world(tree: SceneTree) -> bool:
	return tree.get_first_node_in_group("zone_world") != null


static func path_for(tree: SceneTree) -> String:
	var zones: bool = is_zones_world(tree)
	if NetworkManager.is_coop_session():
		if not NetworkManager.active_save_path.is_empty():
			return NetworkManager.active_save_path
		return COOP_ZONES_PATH if zones else COOP_PATH
	return ZONES_PATH if zones else PATH


static func _local_saves_blocked() -> bool:
	return not OS.is_debug_build() or CloudSession.strict_override


static func exists(path: String = PATH) -> bool:
	if _local_saves_blocked():
		return false
	return FileAccess.file_exists(path)


static func delete(path: String = PATH) -> bool:
	if _local_saves_blocked():
		return false
	if FileAccess.file_exists(path):
		var err: Error = DirAccess.remove_absolute(path)
		return err == OK
	return true


## When and where the game was last saved: {saved_at, day, time}; empty without a save.
static func info(path: String = PATH) -> Dictionary:
	if _local_saves_blocked():
		return {}
	var data: Dictionary = _read(path)
	return {} if data.is_empty() else {"saved_at": int(data.get("saved_at", 0)), "day": int(data.get("day", 0)), "time": float(data.get("time", 0.0))}


static func export_player_data(player: Player, stow_live: bool = false) -> Dictionary:
	if stow_live:
		player.inventory.stow_held() ## optional live stow for explicit close/save paths
	var position: Vector2 = player.climb.save_position()
	return {
		"pos": [position.x, position.y],
		"health": player.health.current,
		"copper": player.progress.copper,
		"xp": player.progress.xp,
		"claimed": player.progress.claimed, ## the level whose rewards were collected (Fortschritt window): health, stamina, armor, talisman slots follow it
		"skill_tree": (player.get_node("SkillTreeComponent") as SkillTreeComponent).export_data(),
		"slots": player.inventory.slots.duplicate(true) if stow_live else player.inventory.export_slots(),
		"equipment": player.inventory.equipment.duplicate(true),
		"raw_rolls": player.inventory.hidden.duplicate(true), ## what the raw stones in the bag hide (Ilva's LÄUTERN)
		"bandaged": player.bandaged,
		"appearance": player.appearance.export_data() if player.appearance != null else {},
		"quests": player.quests.export_data() if player.quests != null else {},
		"board_local": player.tracked.export_data() if player.tracked != null else {}, ## journal focus, page and read notices
	}


static func export_world_data(tree: SceneTree) -> Dictionary:
	var data: Dictionary = {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"time": TimeManager.time_of_day,
		"day": TimeManager.day,
		"sleep": TimeManager.export_sleep_state(),
	}
	var world: Node = tree.get_first_node_in_group("world")
	if world != null and world.get("opening_over") != null:
		data["opening_over"] = bool(world.get("opening_over")) ## the clock stays locked at midnight until the opening is over
	if world != null and world.has_method("export_things"):
		data["things"] = world.call("export_things")
	if world != null and world.has_method("export_story"):
		data["story"] = world.call("export_story")
	if world != null and world.has_method("export_zone_state"):
		data["zone_world"] = world.call("export_zone_state")
	var mines: MineManager = tree.get_first_node_in_group("mines") as MineManager
	if mines != null:
		data["mine"] = mines.export_state() ## opened chests, mended lifts, depth, kills; the mined rocks are in "things"
	var town: TownManager = tree.get_first_node_in_group("town") as TownManager
	if town != null and (town.founded or NetworkManager.is_coop_session()):
		data["town"] = town.export_state() ## the pieces, the stock, the ways, the residents (docs/town.md)
	var night: NightDirector = tree.get_first_node_in_group("night_director") as NightDirector
	if night != null:
		data["night"] = night.export_state() ## where the base held and where it gave way (docs/nacht_monster_konzept.md)
	var waystones: Waystones = Waystones.of(tree)
	if waystones != null and waystones.awake_count() > 0:
		data["waystones"] = waystones.export_state() ## the awakened goddess statues (docs/waystones.md)
	var goddess: GoddessSystem = GoddessSystem.of(tree)
	if goddess != null:
		var g_state: Dictionary = goddess.export_state()
		if not as_dict(g_state.get("introduced")).is_empty() or not as_dict(g_state.get("light_step")).is_empty():
			data["goddess"] = g_state
	var rings: Dictionary = {}
	for node: Node in tree.get_nodes_in_group("ward_rings"):
		rings[(node as WardRing).id] = (node as WardRing).export_state()
	if not rings.is_empty():
		data["ward_rings"] = rings ## the ward stones round the lake witch's house: awake or out (docs/seehexe_konzept.md)
	var witch: WitchArena = tree.get_first_node_in_group("witch_arena") as WitchArena
	if witch != null and (witch.released or witch.opened):
		data["witch"] = witch.export_state() ## Morwenna was released: the Rabenbaum stays free (docs/enemies/boss_mora.md)
	var aurelith: AurelithArena = tree.get_first_node_in_group("aurelith_arena") as AurelithArena
	if aurelith != null and aurelith.released:
		data["aurelith"] = aurelith.export_state() ## Aurelith was defeated in the Singing Basin (docs/enemies/boss_aurelith.md)
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
	if pets != null and not as_dict(pets.export_state().get("bonds")).is_empty():  ## (the birds' records only exist with a bond)
		data["pets"] = pets.export_state() ## the bonds with wild birds (docs/pet_konzept.md)
	var vistas: Vistas = Vistas.of(tree)
	if vistas != null and vistas.discovered_count() > 0:
		data["vistas"] = vistas.export_state() ## discovered meadow cliff vistas (docs/wiesenbiom_ausbau_konzept.md)
	var m_landmarks: MeadowLandmarks = MeadowLandmarks.of(tree)
	if m_landmarks != null and m_landmarks.blessed_count() > 0:
		data["meadow_landmarks"] = m_landmarks.export_state() ## blessed Urforst shrines (docs/wiesenbiom_ausbau_konzept.md)
	var m_pois: MeadowPois = MeadowPois.of(tree)
	if m_pois != null and m_pois.has_progress():
		data["meadow_pois"] = m_pois.export_state() ## Red Order inscriptions, unjammed watermills & rowboats (docs/wiesenbiom_ausbau_konzept.md)
	var m_wonders: MeadowWonders = MeadowWonders.of(tree)
	if m_wonders != null and m_wonders.has_progress():
		data["meadow_wonders"] = m_wonders.export_state() ## awakened BellPond, SleepingGuardians & FlowerAmphitheater (docs/wiesenbiom_ausbau_konzept.md)
	var discovery: MapDiscovery = tree.get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null:
		data["map"] = Marshalls.raw_to_base64(discovery.export_data())
		if discovery.is_reveal_all():
			data["map_before"] = Marshalls.raw_to_base64(discovery.export_before()) ## the fog from before the developer's whole-map reveal
	return data


static func _write_json_file(target: String, payload_json: String) -> bool:
	if target.is_empty() or payload_json.is_empty():
		return false
	var pending: String = target + ".tmp"
	var backup: String = target + ".bak"
	var target_dir: String = target.get_base_dir()
	_io_mutex.lock()
	if not target_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(target_dir)
	var file: FileAccess = FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		_io_mutex.unlock()
		return false
	file.store_string(payload_json)
	file.flush()
	var written: bool = file.get_error() == OK
	file.close()
	if written and FileAccess.file_exists(target):
		var prev_raw: String = FileAccess.get_file_as_string(target)
		if not prev_raw.is_empty():
			var bak_file: FileAccess = FileAccess.open(backup, FileAccess.WRITE)
			if bak_file != null:
				bak_file.store_string(prev_raw)
				bak_file.flush()
				bak_file.close()
	var saved_ok: bool = written and DirAccess.rename_absolute(pending, target) == OK
	_io_mutex.unlock()
	return saved_ok


static func _touch_coop_if_needed(saved_ok: bool, is_coop: bool, world_id: String, day: int, time_val: float, guest_count: int) -> void:
	if saved_ok and is_coop and not world_id.is_empty():
		MultiplayerWorlds.touch_save(world_id, day, time_val, guest_count)


static func save(tree: SceneTree, path: String = "", pre_world: Dictionary = {}, pre_player: Dictionary = {}) -> bool:
	if _local_saves_blocked():
		return false
	if tree.get_first_node_in_group("sandbox") != null: ## the trials' test world is never saved
		return false
	var player: Player = _local_player(tree)
	if player == null or not tree.root.multiplayer.is_server():
		return false
	var target: String = path if path != "" else path_for(tree)
	var data: Dictionary = pre_world.duplicate() if not pre_world.is_empty() else export_world_data(tree)
	data["player"] = pre_player if not pre_player.is_empty() else export_player_data(player)
	var saved_ok: bool = _write_json_file(target, JSON.stringify(data))
	var is_coop: bool = NetworkManager.is_coop_session()
	var world_id: String = NetworkManager.active_world_id
	var guest_count: int = maxi(tree.root.multiplayer.get_peers().size(), 0)
	_touch_coop_if_needed(saved_ok, is_coop, world_id, TimeManager.day, TimeManager.time_of_day, guest_count)
	return saved_ok


static func save_async(tree: SceneTree, on_done: Callable = Callable(), path: String = "", pre_world: Dictionary = {}, pre_player: Dictionary = {}) -> bool:
	if _local_saves_blocked() or tree == null:
		if on_done.is_valid():
			on_done.call(false)
		return false
	if tree.get_first_node_in_group("sandbox") != null:
		if on_done.is_valid():
			on_done.call(false)
		return false
	var player: Player = _local_player(tree)
	if player == null or not tree.root.multiplayer.is_server():
		if on_done.is_valid():
			on_done.call(false)
		return false
	var target: String = path if path != "" else path_for(tree)
	var data: Dictionary = pre_world.duplicate() if not pre_world.is_empty() else export_world_data(tree)
	data["player"] = pre_player if not pre_player.is_empty() else export_player_data(player)
	var json_text: String = JSON.stringify(data)
	var is_coop: bool = NetworkManager.is_coop_session()
	var world_id: String = NetworkManager.active_world_id
	var day_val: int = TimeManager.day
	var time_val: float = TimeManager.time_of_day
	var guest_count: int = maxi(tree.root.multiplayer.get_peers().size(), 0)
	Jobs.run(
		func() -> bool:
			return _write_json_file(target, json_text),
		func(ok_v: Variant) -> void:
			var saved_ok: bool = bool(ok_v)
			_touch_coop_if_needed(saved_ok, is_coop, world_id, day_val, time_val, guest_count)
			if on_done.is_valid():
				on_done.call(saved_ok),
		Jobs.Prio.LOW,
		func() -> void:
			if on_done.is_valid():
				on_done.call(false),
		"save_game_async"
	)
	return true


static func compress_json(data: Dictionary) -> String:
	var raw: PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	if raw.is_empty():
		return ""
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_GZIP)
	return Marshalls.raw_to_base64(compressed)


static func decompress_json(encoded: String) -> Dictionary:
	if encoded.is_empty():
		return {}
	var compressed: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if compressed.is_empty():
		return {}
	var raw: PackedByteArray = compressed.decompress_dynamic(MAX_CLOUD_WORLD_BYTES, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	return parsed as Dictionary if parsed is Dictionary else {}


static func import_player_data(player: Player, saved: Dictionary, apply_pos: bool = true, load_quests: bool = true) -> void:
	if apply_pos:
		var pos: Array = as_array(saved.get("pos"))
		if pos.size() == 2 and (pos[0] is float or pos[0] is int) and (pos[1] is float or pos[1] is int):
			var px: float = float(pos[0])
			var py: float = float(pos[1])
			if is_finite(px) and is_finite(py):
				player.position = Vector2(px, py)
				(player.get_node("Camera2D") as Camera2D).reset_smoothing()
	player.progress.xp = int(saved.get("xp", 0))
	player.progress.restore_claimed(int(saved.get("claimed", 1))) ## before the health: the maximum depends on it
	var health: float = float(saved.get("health", player.health.max_health))
	player.health.current = health if is_finite(health) and health > 0.0 else player.health.max_health
	player.sync_wound_visuals()
	player.progress.copper = int(saved.get("copper", 0))
	player.progress.xp = int(saved.get("xp", 0))
	player.progress.award(0, 0)
	(player.get_node("SkillTreeComponent") as SkillTreeComponent).import_data(as_dict(saved.get("skill_tree")))
	_restore_stacks(player.inventory, saved)
	player.inventory.import_hidden(as_dict(saved.get("raw_rolls")))
	player.set_bandaged(bool(saved.get("bandaged", false)))
	if player.appearance != null:
		player.appearance.import_data(as_dict(saved.get("appearance")))
	player.sync_wound_visuals()
	if load_quests:
		if player.quests != null and saved.has("quests"):
			player.quests.import_data(as_dict(saved.get("quests")))
		if player.tracked != null and saved.has("board_local"):
			player.tracked.import_data(as_dict(saved.get("board_local")))


static func sync_player_to_network(player: Player) -> void:
	if player == null or not player.is_inside_tree():
		return
	var mp: MultiplayerAPI = player.multiplayer
	if not mp.is_server():
		return
	var owner_id: int = player.get_multiplayer_authority()
	player.inventory._commit()
	player.progress.award(0, 0)
	var can_rpc: bool = NetworkManager.rpc_ready(player)
	if owner_id != mp.get_unique_id() and can_rpc:
		player.progress._rpc_claimed.rpc_id(owner_id, player.progress.claimed, false)
	var skills: SkillTreeComponent = player.get_node_or_null("SkillTreeComponent") as SkillTreeComponent
	if skills != null:
		skills._sync()
	if player.appearance != null and can_rpc:
		player.appearance._rpc_apply_all.rpc(player.appearance.export_data())
	if player.health != null and owner_id != mp.get_unique_id() and can_rpc:
		player.health._set_value.rpc(player.health.current)


static func import_world_data(tree: SceneTree, data: Dictionary, player: Player, resume: bool = true) -> bool:
	if tree.get_first_node_in_group("sandbox") != null or data.is_empty() or player == null:
		return false
	var world_node: Node = tree.get_first_node_in_group("world")
	var quest_flags: Dictionary = {}
	if player.quests != null:
		quest_flags = as_dict(player.quests.export_data().get("flags"))
	var opening_done: bool = bool(data.get("opening_over", false)) or bool(quest_flags.get("woke_up", false))
	if opening_done and world_node != null and world_node.has_method("finish_opening"):
		world_node.call("finish_opening") ## sets opening_over and unlocks the clock
	if not TimeManager.locked: ## the opening holds the clock at midnight
		TimeManager.time_of_day = float(data.get("time", TimeManager.time_of_day))
		TimeManager.day = int(data.get("day", 0))
	TimeManager.import_sleep_state(as_dict(data.get("sleep")))
	var world: Node = tree.get_first_node_in_group("world")
	if world != null and world.has_method("import_zone_state") and data.has("zone_world"):
		world.call("import_zone_state", as_dict(data.get("zone_world")))
	if world != null and world.has_method("import_things"):
		world.call("import_things", as_dict(data.get("things")))
	if world != null and world.has_method("import_story"):
		world.call("import_story", as_dict(data.get("story")))
	var mines: MineManager = tree.get_first_node_in_group("mines") as MineManager
	if mines != null:
		mines.import_state(as_dict(data.get("mine")))
	var town: TownManager = tree.get_first_node_in_group("town") as TownManager
	if town != null and data.has("town"):
		town.import_state(as_dict(data.get("town")))
	var night: NightDirector = tree.get_first_node_in_group("night_director") as NightDirector
	if night != null and data.has("night"):
		night.import_state(as_dict(data.get("night")))
	var waystones: Waystones = Waystones.of(tree)
	if waystones != null and data.has("waystones"):
		waystones.import_state(as_dict(data.get("waystones")))
	var goddess: GoddessSystem = GoddessSystem.of(tree)
	if goddess != null and data.has("goddess"):
		goddess.import_state(as_dict(data.get("goddess")))
	var ward_rings: Dictionary = as_dict(data.get("ward_rings"))
	for ring_id: Variant in ward_rings:
		var ring: WardRing = WardRing.by_id(tree, String(ring_id))
		if ring != null:
			ring.import_state(bool(ward_rings[ring_id]))
	var witch: WitchArena = tree.get_first_node_in_group("witch_arena") as WitchArena
	if witch != null and data.has("witch"):
		witch.import_state(as_dict(data.get("witch")))
	var aurelith: AurelithArena = tree.get_first_node_in_group("aurelith_arena") as AurelithArena
	if aurelith != null and data.has("aurelith"):
		aurelith.import_state(as_dict(data.get("aurelith")))
	var relics: BossRelics = BossRelics.of(tree)
	if relics != null and data.has("relics"):
		relics.import_state(as_dict(data.get("relics")))
	var chests: LootChests = LootChests.of(tree)
	if chests != null and data.has("chests"):
		chests.import_state(as_dict(data.get("chests")))
	var puzzles: Puzzles = Puzzles.of(tree)
	if puzzles != null and data.has("puzzles"):
		puzzles.import_state(as_dict(data.get("puzzles")))
	var pets: PetRegistry = PetRegistry.of(tree)
	if pets != null and data.has("pets"):
		pets.import_state(as_dict(data.get("pets")))
	var vistas: Vistas = Vistas.of(tree)
	if vistas != null and data.has("vistas"):
		vistas.import_state(data.get("vistas"))
	var m_landmarks: MeadowLandmarks = MeadowLandmarks.of(tree)
	if m_landmarks != null and data.has("meadow_landmarks"):
		m_landmarks.import_state(data.get("meadow_landmarks"))
	var m_pois: MeadowPois = MeadowPois.of(tree)
	if m_pois != null and data.has("meadow_pois"):
		m_pois.import_state(data.get("meadow_pois"))
	var m_wonders: MeadowWonders = MeadowWonders.of(tree)
	if m_wonders != null and data.has("meadow_wonders"):
		m_wonders.import_state(data.get("meadow_wonders"))
	var discovery: MapDiscovery = tree.get_first_node_in_group("map_discovery") as MapDiscovery
	if discovery != null and data.has("map"):
		var map_b64: Variant = data.get("map")
		var map_before_b64: Variant = data.get("map_before")
		discovery.import_saved(Marshalls.base64_to_raw(map_b64 as String if map_b64 is String else ""))
		discovery.import_before(Marshalls.base64_to_raw(map_before_b64 as String if map_before_b64 is String else "")) ## empty = no whole-map reveal active
	if resume and world != null and world.has_method("resume_story"):
		world.call_deferred("resume_story", player) ## a save that stopped in the middle of the wake-up plays it again
	if TimeManager.nights_awake >= 1 and world != null and world.has_method("apply_tiredness_to_players"):
		world.call_deferred("apply_tiredness_to_players")
	return true


static func load_into(tree: SceneTree, path: String = "", resume: bool = true) -> bool:
	if _local_saves_blocked():
		return false
	if tree.get_first_node_in_group("sandbox") != null:
		return false
	var data: Dictionary = _read(path if path != "" else path_for(tree))
	var player: Player = _local_player(tree)
	if data.is_empty() or player == null:
		return false
	var saved: Dictionary = as_dict(data.get("player"))
	import_player_data(player, saved, true)
	return import_world_data(tree, data, player, resume)


static func _restore_stacks(inventory: InventoryComponent, saved: Dictionary) -> void:
	var slots: Array = as_array(saved.get("slots"))
	for i: int in mini(slots.size(), inventory.slots.size()):
		inventory.slots[i] = _stack(slots[i])
	var equipment: Dictionary = as_dict(saved.get("equipment"))
	for slot_name: String in inventory.equipment:
		inventory.equipment[slot_name] = _stack(equipment.get(slot_name))
	inventory.changed.emit()


## Host-side guest state used by board delivery and rewards. A joining client requests
## the restored inventory and balances through the normal player-component snapshots.
static func guest_economy(player: Player) -> Dictionary:
	var skills: SkillTreeComponent = player.get_node("SkillTreeComponent") as SkillTreeComponent
	return {
		"slots": player.inventory.slots.duplicate(true), "equipment": player.inventory.equipment.duplicate(true),
		"held": player.inventory.held.duplicate(true), "raw_rolls": player.inventory.hidden.duplicate(true), "xp": player.progress.xp, "copper": player.progress.copper,
		"claimed": player.progress.claimed, "skill_tree": skills.export_data(),
		"appearance": player.appearance.export_data() if player.appearance != null else {},
	}


static func restore_guest_economy(player: Player, saved: Dictionary) -> void:
	player.progress.xp = int(saved.get("xp", 0))
	player.progress.copper = int(saved.get("copper", 0))
	player.progress.claimed = clampi(int(saved.get("claimed", 1)), 1, maxi(player.progress.level, 1))
	player.progress.apply_stats(false)
	player.progress.changed.emit()
	var skills: SkillTreeComponent = player.get_node("SkillTreeComponent") as SkillTreeComponent
	skills.import_data(as_dict(saved.get("skill_tree")))
	if player.appearance != null:
		player.appearance.import_data(as_dict(saved.get("appearance")))
	player.inventory.held = _stack(saved.get("held"))
	_restore_stacks(player.inventory, saved)
	player.inventory.import_hidden(as_dict(saved.get("raw_rolls")))


## JSON turns counts into floats: back to a clean stack.
static func _stack(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var stack: Dictionary = raw as Dictionary
	if stack.is_empty():
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
	for candidate: String in [path, path + ".bak"]:
		if FileAccess.file_exists(candidate):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
			if parsed is Dictionary and not (parsed as Dictionary).is_empty():
				return parsed as Dictionary
	return {}
