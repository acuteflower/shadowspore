extends Node
## Automated Stage 6 & Meadow Explorer verification (`docs/wiesenbiom_ausbau_konzept.md`):
##  - All 36 placed Meadow explorer `LootChest`s (`data/loot_chests.json`: 2 legendary, 10 rare, 24 common) on valid
##    dry meadow tiles with `blocked_cells` obstacle clearance around every chest.
##  - Stage 3/5/6 item & talisman registry + art + `TalismanRules` stacking (`order_signet`, `bell_chime_talisman`,
##    `antler_talisman`, `star_shard`).
##  - `NightWonders` Starfall sky streak -> glowing `StarCrater` (`WARMES STERNERZ BERGEN`) -> harvesting (`+18 XP`,
##    `3x star_shard`) -> unharvested dawn cooling (`state_mode == 2`, light & glow off).
##  - `NightWonders` `SpiritStag` (*Der Weiße Kronenhirsch*): strictly ZERO `HurtboxComponent` / `HealthComponent`,
##    upright `ALERT` -> `FLEE_VANISH`, calm sneaking `PAWING` -> `antler_talisman` + `star_shard` + `+24 XP` -> `BLESS_VANISH`.
## Optional `-- --capture=/abs/dir` saves real-world screenshots when run with `--rendering-driver opengl3`.

var _checks: int = 0
var _failures: int = 0
var _capture_dir: String = ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("NIGHT WONDERS TEST FAILED: " + label)
		print("FAILED: ", label)


func _shot(shot_name: String) -> void:
	if _capture_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_capture_dir.path_join(shot_name + ".png"))


func _hide_ui_overlays(nw: NightWonders) -> void:
	if nw != null and nw._banner != null:
		nw._banner.visible = false
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.skip_all()
		box.visible = false


func _stream_around(world: WorldLevel, tile: Vector2i) -> void:
	var c: Vector2i = tile / WorldLevel.CHUNK
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			world._load_chunk(c + Vector2i(dx, dy))
	await get_tree().physics_frame
	await get_tree().physics_frame


func _find_flat_meadow_px(world: WorldLevel, center_tile: Vector2i, radius_tiles: int = 24) -> Vector2:
	for r: int in range(0, radius_tiles + 1, 2):
		for dy: int in range(-r, r + 1, 2):
			for dx: int in range(-r, r + 1, 2):
				var tile: Vector2i = center_tile + Vector2i(dx, dy)
				if world._biome_at(tile) != "meadow":
					continue
				var px: Vector2 = Vector2(tile) * 16.0 + Vector2(8.0, 8.0)
				if world._rivers != null and (world._rivers.depth_amount(px) >= 0.0 or not world._rivers.clear_for_prop(px, 28.0)):
					continue
				if world._relief != null and not world._relief.flat_around(px, 26.0):
					continue
				if world._generator != null and world._generator.blocked_cells.has(tile):
					continue
				return px
	return Vector2(center_tile) * 16.0 + Vector2(8.0, 8.0)


func _clear_nearby_enemies(center: Vector2, radius: float) -> void:
	for e_node: Node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e_node) and e_node is Node2D and (e_node as Node2D).global_position.distance_to(center) <= radius:
			e_node.queue_free()


func _count_item_world_and_bag(player: Player, item_id: String) -> int:
	var total: int = 0
	if player != null and player.inventory != null:
		total += player.inventory.count_item(item_id)
	var container: Node = get_tree().get_first_node_in_group("drops")
	if container != null:
		for child: Node in container.get_children():
			if is_instance_valid(child) and child is ItemDrop:
				var d: ItemDrop = child as ItemDrop
				if d.item_id == item_id:
					total += d.count
	return total


func _wait_seconds(sec: float) -> void:
	var elapsed: float = 0.0
	while elapsed < sec:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	world.finish_opening()

	var player: Player = world._players.get_child(0) as Player
	if player.intro != null:
		player.intro.queue_free()
		player.intro = null
	player.story_lock = false
	player.health.heal_full()
	player.stamina.refill()
	player.stamina._delay_left = 5.0

	var nw: NightWonders = NightWonders.of(get_tree())
	_check(nw != null, "NightWonders node exists in group 'night_wonders'")

	# ------------------------------------------------------------------
	# 1. 36 Placed Meadow Explorer Chests
	# ------------------------------------------------------------------
	var chests: LootChests = LootChests.of(get_tree())
	var placed: Array = DataRegistry.table("loot_chests").get("placed", []) as Array
	_check(placed.size() == 36, "data/loot_chests.json defines 36 placed meadow explorer chests (got %d)" % placed.size())
	_check(chests != null and chests.count() == 36, "LootChests initialized all 36 placed chests")

	var tier_counts: Dictionary = {"legendary": 0, "rare": 0, "common": 0}
	var all_in_meadow: bool = true
	var all_dry: bool = true
	var all_cleared: bool = true
	for entry_v: Variant in placed:
		var entry: Dictionary = entry_v as Dictionary
		var t_arr: Array = entry.get("tile", []) as Array
		var c_tile: Vector2i = Vector2i(int(t_arr[0]), int(t_arr[1]))
		var tier_name: String = String(entry.get("tier", "common"))
		tier_counts[tier_name] = int(tier_counts.get(tier_name, 0)) + 1
		if world._biome_at(c_tile) != "meadow":
			all_in_meadow = false
		var px: Vector2 = Vector2(c_tile) * 16.0 + Vector2(8.0, 8.0)
		if world._rivers != null and world._rivers.depth_amount(px) >= 0.0:
			all_dry = false
		if world._generator == null or not world._generator.blocked_cells.has(c_tile):
			all_cleared = false
	_check(int(tier_counts.get("legendary", 0)) == 2 and int(tier_counts.get("rare", 0)) == 10 and int(tier_counts.get("common", 0)) == 24,
		"Placed chest tiers are 2 legendary, 10 rare, 24 common")
	_check(all_in_meadow, "Every placed explorer chest lies in meadow biome")
	_check(all_dry, "Every placed explorer chest lies outside deep water")
	_check(all_cleared, "WorldLevel marks blocked_cells clearance around all 36 placed chests")

	# ------------------------------------------------------------------
	# 2. Items, Icons & Talismans (Stages 3 / 5 / 6)
	# ------------------------------------------------------------------
	var items_tbl: Dictionary = DataRegistry.table("items")
	for new_id: String in ["star_shard", "antler_talisman", "bell_chime_talisman", "order_signet"]:
		var item_def: Dictionary = items_tbl.get(new_id, {}) as Dictionary
		var icon_path: String = String(item_def.get("icon", ""))
		_check(not item_def.is_empty() and ResourceLoader.exists(icon_path) and load(icon_path) is Texture2D,
			"Item '%s' defined with valid Texture2D icon" % new_id)

	for tal_id: String in ["order_signet", "bell_chime_talisman", "antler_talisman"]:
		var look: Dictionary = TalismanArt.look_of(tal_id)
		_check(not look.is_empty() and TalismanArt.metal(look).size() == 4, "TalismanArt renders '%s'" % tal_id)

	var combo: Dictionary = TalismanRules.combine(TalismanRules.stacks_of(PackedStringArray(["order_signet", "bell_chime_talisman", "antler_talisman"])))
	_check(is_equal_approx(float(combo.get("health", 0.0)), 18.0) and is_equal_approx(float(combo.get("armor", 0.0)), 3.0) and is_equal_approx(float(combo.get("heavy_damage", 0.0)), 0.1),
		"Order signet bonuses combine via TalismanRules")
	_check(is_equal_approx(float(combo.get("blink_cooldown", 0.0)), -0.22) and is_equal_approx(float(combo.get("absorb", 0.0)), 0.1),
		"Bell chime talisman bonuses combine via TalismanRules")
	_check(is_equal_approx(float(combo.get("alarm", 0.0)), -0.35) and is_equal_approx(float(combo.get("charge_speed", 0.0)), 0.18) and is_equal_approx(float(combo.get("corvid_calm", 0.0)), 0.25),
		"Antler talisman bonuses combine via TalismanRules")

	# ------------------------------------------------------------------
	# 3. Starfall & StarCrater (Streak -> Warm Core -> Harvest -> Dawn Cool)
	# ------------------------------------------------------------------
	TimeManager.set_time(0.95)
	if WeatherManager.current != null:
		WeatherManager.current.force("clear")

	var star_anchor: Vector2 = _find_flat_meadow_px(world, Vector2i(356, 206))
	var crater1_pos: Vector2 = _find_flat_meadow_px(world, Vector2i((star_anchor / 16.0).floor()) + Vector2i(5, -1), 10)
	player.request_teleport(crater1_pos + Vector2(-92.0, 26.0))
	await _stream_around(world, Vector2i((crater1_pos / 16.0).floor()))
	_clear_nearby_enemies(crater1_pos, 320.0)
	_hide_ui_overlays(nw)

	var launched_pos: Vector2 = nw.trigger_starfall(crater1_pos)
	var cid1: int = nw._next_crater_id
	_check(launched_pos.is_finite() and nw.active_streak_count() == 1, "trigger_starfall launches bright sky streak")
	await _wait_seconds(0.45)
	await _shot("01_starfall_streak_night")

	var wait_t: float = 0.0
	var crater1: StarCrater = null
	while wait_t < 1.5:
		await _wait_seconds(0.05)
		wait_t += 0.05
		crater1 = nw.crater_node(cid1)
		if crater1 != null and nw.active_streak_count() == 0:
			break

	_check(crater1 != null and crater1.state_mode == 0, "StarCrater lands in warm state_mode == 0")
	if crater1 != null:
		_check(crater1.prompt() == "WARMES STERNERZ BERGEN", "Warm StarCrater exposes harvest prompt")
		player.request_teleport(crater1.global_position + Vector2(-34.0, 6.0))
		await _wait_seconds(0.18)
		_clear_nearby_enemies(crater1.global_position, 280.0)
		_hide_ui_overlays(nw)
		await _shot("02_star_crater_warm_night")

		var xp_before_crater: int = player.progress.xp
		var shards_before_crater: int = _count_item_world_and_bag(player, "star_shard")
		crater1.interact(player)
		var pick_t: float = 0.0
		while pick_t < 1.6 and crater1.state_mode == 0:
			await _wait_seconds(0.05)
			pick_t += 0.05
		await _wait_seconds(0.10)
		_check(crater1.state_mode == 1 and crater1.prompt() == "", "Harvested StarCrater transitions to hollow state_mode == 1")
		_check(player.progress.xp == xp_before_crater + 18, "Harvesting StarCrater awards +18 XP")
		_check(_count_item_world_and_bag(player, "star_shard") == shards_before_crater + 3,
			"Harvesting StarCrater yields 3 warm star_shard pieces")

	# Second crater left unharvested -> cools at sunrise
	var crater2_pos: Vector2 = _find_flat_meadow_px(world, Vector2i((crater1_pos / 16.0).floor()) + Vector2i(14, 4), 10)
	nw.trigger_starfall(crater2_pos)
	var cid2: int = nw._next_crater_id
	var wait2: float = 0.0
	var crater2: StarCrater = null
	while wait2 < 1.5:
		await _wait_seconds(0.05)
		wait2 += 0.05
		crater2 = nw.crater_node(cid2)
		if crater2 != null and nw.active_streak_count() == 0:
			break
	_check(crater2 != null and crater2.state_mode == 0, "Second StarCrater lands warm before dawn")
	if crater2 != null:
		player.request_teleport(crater2.global_position + Vector2(-36.0, 8.0))
		await _wait_seconds(0.12)
		TimeManager.set_time(0.30)
		TimeManager.day_started.emit(TimeManager.day + 1)
		await _wait_seconds(0.15)
		_check(crater2.state_mode == 2 and crater2.prompt() == "", "Unharvested StarCrater cools to state_mode == 2 on dawn signal")
		_check(not crater2._light.visible and not crater2._glow.visible, "Cooled dawn StarCrater disables NightLight & glow sprite")
		_hide_ui_overlays(nw)
		await _shot("03_star_crater_cooled_dawn")

	# ------------------------------------------------------------------
	# 4. SpiritStag (Der Weiße Kronenhirsch): Peaceful, Noisy Flee, Sneak Blessing
	# ------------------------------------------------------------------
	TimeManager.set_time(0.96)
	player.health.heal_full()
	player.stamina.refill()
	player.stamina._delay_left = 5.0

	var stag1_pos: Vector2 = _find_flat_meadow_px(world, Vector2i(392, 240), 14)
	await _stream_around(world, Vector2i((stag1_pos / 16.0).floor()))
	_clear_nearby_enemies(stag1_pos, 320.0)
	var stag1: SpiritStag = nw.spawn_spirit_stag(stag1_pos)
	_check(stag1 != null, "spawn_spirit_stag spawns SpiritStag entity")

	if stag1 != null:
		_check(stag1.find_children("*", "HurtboxComponent", true, false).is_empty(), "SpiritStag has strictly ZERO HurtboxComponent")
		_check(stag1.find_children("*", "HealthComponent", true, false).is_empty(), "SpiritStag has strictly ZERO HealthComponent")

		# Keep Ellie calm & sneaking just outside SNEAK_RADIUS for clean idle night capture
		Input.action_press("sneak")
		player.stealth.sneaking = true
		player.sprinting = false
		player.request_teleport(stag1_pos + Vector2(-110.0, 8.0))
		await _wait_seconds(0.22)
		_check(stag1.state == SpiritStag.State.IDLE, "Sneaking outside SNEAK_RADIUS keeps SpiritStag calm IDLE")
		_hide_ui_overlays(nw)
		await _shot("04_spirit_stag_idle_night")

		# Upright noisy alert -> flee into silver mist
		Input.action_release("sneak")
		player.stealth.sneaking = false
		player.request_teleport(stag1_pos + Vector2(-158.0, 0.0))
		await _wait_seconds(0.22)
		_check(stag1.state == SpiritStag.State.ALERT, "Standing upright inside ALERT_RADIUS triggers ALERT")

		player.request_teleport(stag1_pos + Vector2(-95.0, 0.0))
		await _wait_seconds(0.20)
		_check(stag1.state == SpiritStag.State.FLEE_VANISH, "Walking upright inside FLEE_RADIUS triggers FLEE_VANISH")
		await _wait_seconds(SpiritStag.VANISH_DURATION_SEC + 0.25)
		_check(not is_instance_valid(stag1), "FLEE_VANISH dissolves SpiritStag cleanly")

	# Second SpiritStag: patient stealth approach -> PAWING -> antler_talisman relic
	var stag2_pos: Vector2 = _find_flat_meadow_px(world, Vector2i(412, 248), 14)
	await _stream_around(world, Vector2i((stag2_pos / 16.0).floor()))
	_clear_nearby_enemies(stag2_pos, 320.0)
	var stag2: SpiritStag = nw.spawn_spirit_stag(stag2_pos)
	_check(stag2 != null, "Second SpiritStag spawned for stealth blessing test")

	if stag2 != null:
		var xp_before_stag: int = player.progress.xp
		var relic_before: int = _count_item_world_and_bag(player, "antler_talisman")
		var shards_before_stag: int = _count_item_world_and_bag(player, "star_shard")
		player.request_teleport(stag2_pos + Vector2(-54.0, 8.0))
		Input.action_press("sneak")
		player.stealth.sneaking = true
		player.sprinting = false

		var paw_wait: float = 0.0
		while paw_wait < 1.6 and stag2.state != SpiritStag.State.PAWING:
			await _wait_seconds(0.05)
			paw_wait += 0.05
		_check(stag2.state == SpiritStag.State.PAWING, "Holding sneak inside SNEAK_RADIUS triggers PAWING")

		await _wait_seconds(0.28)
		_hide_ui_overlays(nw)
		await _shot("05_spirit_stag_pawing_relic")

		var bless_wait: float = 0.0
		while bless_wait < 1.5 and is_instance_valid(stag2) and stag2.state == SpiritStag.State.PAWING:
			await _wait_seconds(0.05)
			bless_wait += 0.05

		_check(not is_instance_valid(stag2) or stag2.state == SpiritStag.State.BLESS_VANISH,
			"Completed PAWING transitions into BLESS_VANISH")
		_check(player.progress.xp == xp_before_stag + 24, "SpiritStag blessing awards +24 XP")
		_check(_count_item_world_and_bag(player, "antler_talisman") == relic_before + 1,
			"SpiritStag paws out hidden antler_talisman relic")
		_check(_count_item_world_and_bag(player, "star_shard") == shards_before_stag + 1,
			"SpiritStag gift includes bonus star_shard")

	Input.action_release("sneak")
	player.stealth.sneaking = false
	print("NIGHT WONDERS TEST: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
