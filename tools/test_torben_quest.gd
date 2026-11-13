extends Node
## End-to-end test for quest order, board gating, overhead speech bubbles vs Act I
## cutscenes, Torben's overworld quest (`torben_smithy`, NO mine), and progression into
## Esma (Lv 5 + all prior main quests), Mornath (Lv 8), and Ilva (Lv 10).

var _ok: bool = true
var _checks: int = 0


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_ok = false
		print("TORBEN QUEST FAILED: ", what)


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _until(cond: Callable, max_frames: int) -> bool:
	for _i: int in max_frames:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _site(town: TownManager, piece: String, near: Vector2) -> Vector2:
	for ring: int in range(0, 14):
		var step: float = float(ring) * 24.0
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				var p: Vector2 = TownRules.snapped_position(piece, near + Vector2(float(dx) * 24.0, float(dy) * 24.0 + step * 0.1))
				if town.check_site(piece, p) == "":
					return p
	return Vector2.INF


func _skip_bubbles(player: Player) -> void:
	var runner: BubbleRunner = BubbleRunner.find(player)
	if runner != null and runner.is_active():
		runner.skip_all()
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	if box != null and box.is_active():
		box._end()


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	## --- 1. Board Gating Rules (BoardRules.story_due) ---
	var quests_tbl: Dictionary = DataRegistry.table("quests")
	var notices: Dictionary = {}
	for raw: Variant in BoardRules.story_entries():
		var e: Dictionary = raw as Dictionary
		notices[String(e.id)] = e
	_check(notices.has("torben_notice") and notices.has("spiegelhexe_notice") and notices.has("mornath_notice") and notices.has("lake_witch_notice"), "all four main story notices are defined")

	var no_done: Callable = func(_q: String) -> bool: return false
	var no_flag: Callable = func(_f: String) -> bool: return false
	var done_until_board: Callable = func(q: String) -> bool:
		return q in ["find_help", "lumberjack", "rebuild_hut", "town_start", "gustav_rescue", "town_workshop", "town_board"]
	var done_all_torben: Callable = func(q: String) -> bool:
		return done_until_board.call(q) or q == "torben_smithy"
	var done_missing_lumber: Callable = func(q: String) -> bool:
		return done_all_torben.call(q) and q != "lumberjack"
	var done_after_esma: Callable = func(q: String) -> bool:
		return done_all_torben.call(q) or q == "spiegelhexe"

	var n_torben: Dictionary = notices.get("torben_notice", {}) as Dictionary
	var n_esma: Dictionary = notices.get("spiegelhexe_notice", {}) as Dictionary
	var n_mornath: Dictionary = notices.get("mornath_notice", {}) as Dictionary
	var n_ilva: Dictionary = notices.get("lake_witch_notice", {}) as Dictionary

	_check(not BoardRules.story_due(n_torben, quests_tbl, no_done, no_flag, 1), "torben_notice waits for town_board")
	_check(BoardRules.story_due(n_torben, quests_tbl, done_until_board, no_flag, 1), "torben_notice unlocks right after town_board")
	_check(not BoardRules.story_due(n_esma, quests_tbl, done_all_torben, no_flag, 4), "spiegelhexe_notice blocked below Lv 5")
	_check(not BoardRules.story_due(n_esma, quests_tbl, done_missing_lumber, no_flag, 5), "spiegelhexe_notice blocked if any prior main quest is missing")
	_check(BoardRules.story_due(n_esma, quests_tbl, done_all_torben, no_flag, 5), "spiegelhexe_notice unlocks at Lv 5 with all prior main quests done")
	_check(not BoardRules.story_due(n_mornath, quests_tbl, done_after_esma, no_flag, 7), "mornath_notice blocked below Lv 8")
	_check(BoardRules.story_due(n_mornath, quests_tbl, done_after_esma, no_flag, 8), "mornath_notice unlocks at Lv 8 after spiegelhexe")
	_check(not BoardRules.story_due(n_ilva, quests_tbl, done_all_torben, no_flag, 10), "lake_witch_notice blocked before spiegelhexe")
	_check(not BoardRules.story_due(n_ilva, quests_tbl, done_after_esma, no_flag, 9), "lake_witch_notice blocked below Lv 10")
	_check(BoardRules.story_due(n_ilva, quests_tbl, done_after_esma, no_flag, 10), "lake_witch_notice unlocks at Lv 10 after spiegelhexe")

	## --- 2. Fullscreen vs Overhead Bubbles & Torben Word Budget ---
	for fs_id: String in ["ambush_start", "rescue", "wake_inner", "wake_day2", "knight_meet_a", "knight_meet_b", "fire_a", "fire_b", "fire_c", "finale_outside", "finale_inside", "finale_work", "finale_end"]:
		var d: Dictionary = DataRegistry.get_entry("dialogue", fs_id)
		_check(not d.is_empty() and bool(d.get("fullscreen", false)), "Act I cutscene %s stays fullscreen" % fs_id)
	for bubble_id: String in ["knight_sword", "sign_crossroad", "waystone_discover", "town_intro", "gustav_welcome", "workshop_done", "board_intro", "tb_meet", "esma_valdric", "ilva_meet", "mornath_inspect"]:
		var d2: Dictionary = DataRegistry.get_entry("dialogue", bubble_id)
		_check(not d2.is_empty() and not bool(d2.get("fullscreen", false)), "dialogue %s runs via overhead bubble" % bubble_id)
	var dlg_tbl: Dictionary = DataRegistry.table("dialogue")
	for did: String in dlg_tbl:
		var lines: Array = (dlg_tbl[did] as Dictionary).get("lines", []) as Array
		for raw_l: Variant in lines:
			var l: Dictionary = raw_l as Dictionary
			if String(l.get("speaker", "")).to_upper() == "TORBEN":
				var wc: int = String(l.get("text", "")).split(" ", false).size()
				_check(wc <= 5, "Torben line in %s has <= 5 words (%d): %s" % [did, wc, String(l.get("text", ""))])

	## --- 3. Live World: Overworld TorbenCamp & Quest Progression ---
	(TownRules.piece("plaza") as Dictionary)["build_seconds"] = 0.5
	(TownRules.piece("workshop") as Dictionary)["build_seconds"] = 0.5
	(TownRules.piece("quest_board") as Dictionary)["build_seconds"] = 0.5
	(TownRules.piece("smithy") as Dictionary)["build_seconds"] = 0.5
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(4)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	var camp: TorbenCamp = world.get_node_or_null("TorbenCamp_torben") as TorbenCamp
	_check(camp != null and camp.torben != null, "overworld TorbenCamp + StoryTorben spawned")
	if camp != null:
		_check(camp.position.distance_to(Vector2(791.0, 639.0) * 16.0 + Vector2(8.0, 8.0)) < 2.0, "TorbenCamp stands at [791, 639]")
		_check(world._relief.flat_around(camp.global_position, 84.0), "TorbenCamp terrain is flat")
		_check(Terrain.surface_at(camp.global_position) == "grass", "TorbenCamp sits on dry grass")
		_check(world._rivers.clear_for_prop(camp.global_position, 5), "TorbenCamp is clear of rivers")
		var has_mine: bool = false
		for ch: Node in camp.get_children():
			if ch.get_script() != null and String(ch.get_script().resource_path).contains("mine"):
				has_mine = true
		_check(not has_mine, "TorbenCamp has NO mine entrance")

	## Set up town cleanly at ws_pickaxe (without pre-building quest_board)
	world.debug_jump_gustav()
	await _frames(30)
	player.inventory.give("wood", 90)
	player.inventory.give("stone", 90)
	player.inventory.give("plant_fiber", 20)
	player.inventory.give("plank", 12)
	player.inventory.give("iron_ore", 16)
	player.inventory.give("glow_cap", 2)
	if not town.has_built("plaza"):
		player.request_teleport(hut.position + Vector2(-140, 40))
		await _frames(3)
		var plaza_at: Vector2 = _site(town, "plaza", hut.position + Vector2(0, 150))
		_check(plaza_at != Vector2.INF, "plaza site found")
		player.request_teleport(plaza_at + Vector2(0, 28))
		await _frames(3)
		town.request_place("plaza", plaza_at, false)
		_check(await _until(func() -> bool: return town.has_built("plaza"), 180), "plaza built")
	player.request_teleport(hut.position + Vector2(-140, 40))
	await _frames(3)
	var shop_at: Vector2 = _site(town, "workshop", hut.position + Vector2(40, 140))
	_check(shop_at != Vector2.INF, "workshop site found")
	player.request_teleport(shop_at + Vector2(0, 28))
	await _frames(3)
	town.request_place("workshop", shop_at, false)
	_check(await _until(func() -> bool: return town.has_built("workshop"), 180), "workshop built")
	var saved: Dictionary = player.quests.export_data()
	var flags: Dictionary = saved.flags as Dictionary
	world._quest_to_step(saved, "town_workshop", "ws_pickaxe")
	flags["built_workshop"] = true
	flags["workshop_done"] = true
	player.quests.import_data(saved)
	await _frames(4)
	_check(player.quests.active_step_id("town_workshop") == "ws_pickaxe", "at ws_pickaxe before board")
	player.quests.set_flag("crafted_pickaxe")
	await _frames(6)
	_check(player.quests.is_finished("town_workshop") and player.quests.active_step_id("town_board") == "bd_intro", "town_workshop chains into town_board (bd_intro)")
	_skip_bubbles(player)
	player.quests.set_flag("board_intro_done")
	await _frames(4)
	_check(player.quests.active_step_id("town_board") in ["bd_gather", "bd_build"], "board materials recognized -> bd_build")
	player.request_teleport(hut.position + Vector2(-140, 40))
	await _frames(3)
	var bd_at: Vector2 = _site(town, "quest_board", shop_at + Vector2(-80, 0))
	_check(bd_at != Vector2.INF, "quest_board site found")
	player.request_teleport(bd_at + Vector2(0, 28))
	await _frames(3)
	town.request_place("quest_board", bd_at, false)
	_check(await _until(func() -> bool: return town.has_built("quest_board"), 180), "quest_board built")
	await _frames(6)
	_check(player.quests.active_step_id("town_board") == "bd_open", "built quest_board advances to bd_open (%s)" % player.quests.active_step_id("town_board"))

	var win: QuestBoardWindow = QuestBoardWindow.open(get_tree(), player, town)
	await _frames(6)
	_check(player.quests.has_flag("opened_quest_board") and player.quests.is_finished("town_board"), "opening quest board finishes town_board")
	if win != null and is_instance_valid(win):
		win._close()
	await _frames(6)
	var torben_offer_id: int = -1
	for offer: Dictionary in town.board.offers:
		if String(offer.get("q", "")) == "torben_smithy":
			torben_offer_id = int(offer.id)
	_check(torben_offer_id >= 0, "torben_notice is posted on Quest Board right after town_board")
	var bd_id: int = -1
	for sid: int in town.structures:
		if String((town.structures[sid] as Dictionary).p) == "quest_board":
			bd_id = sid
	player.request_teleport(town.rect_of(bd_id).get_center() + Vector2(0, 20))
	await _frames(4)
	town.board.request_accept(torben_offer_id)
	await _frames(4)
	_check(player.quests.is_active("torben_smithy") and player.quests.active_step_id("torben_smithy") == "tb_find", "accepting notice starts torben_smithy at tb_find")

	## Ambush at overworld TorbenCamp
	player.request_teleport(camp.global_position + Vector2(0, 60))
	_check(await _until(func() -> bool: return player.quests.active_step_id("torben_smithy") == "tb_fight", 90), "approaching TorbenCamp triggers ambush (tb_fight)")
	_check(camp._enemies.size() == 3, "3 overworld shadow spiders spawned (%d)" % camp._enemies.size())
	_skip_bubbles(player)
	await _frames(4)
	for s: ShadowSpider in camp._enemies.duplicate():
		if is_instance_valid(s):
			var h: HealthComponent = s.get_node_or_null("HealthComponent") as HealthComponent
			if h != null:
				h.kill(player.global_position, player.name.to_int())
	_check(await _until(func() -> bool: return player.quests.active_step_id("torben_smithy") == "tb_meet", 90), "defeating ambush advances to tb_meet")
	_skip_bubbles(player)
	await _frames(4)
	_check(camp.torben.prompt() == "ANSPRECHEN", "StoryTorben offers ANSPRECHEN (%s)" % camp.torben.prompt())

	camp.torben.interact(player)
	await _frames(6)
	var runner: BubbleRunner = BubbleRunner.find(player)
	_check(runner != null and runner.is_active(), "tb_meet plays via overhead BubbleRunner")
	if runner != null:
		runner.skip_all()
	_check(await _until(func() -> bool: return town.residents.has("torben"), 240), "Torben joins town after Man-Handling scene")
	_check(world.torben_taken and not camp.torben.visible and player.quests.has_flag("tb_met"), "StoryTorben hidden and tb_met set")
	_check(town.is_unlocked("smithy"), "smithy is unlocked after Torben joins")
	_check(player.quests.active_step_id("torben_smithy") == "tb_build", "having materials skips tb_gather to tb_build (%s)" % player.quests.active_step_id("torben_smithy"))

	player.request_teleport(hut.position + Vector2(-140, 40))
	await _frames(3)
	var sm_at: Vector2 = _site(town, "smithy", shop_at + Vector2(130, 0))
	_check(sm_at != Vector2.INF, "smithy site found")
	player.request_teleport(sm_at + Vector2(0, 28))
	await _frames(3)
	town.request_place("smithy", sm_at, false)
	_check(await _until(func() -> bool: return town.has_built("smithy"), 180), "smithy built")
	await _frames(6)
	_skip_bubbles(player)
	_check(player.quests.active_step_id("torben_smithy") == "tb_ingot", "built smithy advances to tb_ingot")

	player.request_teleport(sm_at + Vector2(0, 30))
	await _frames(4)
	town.request_craft("iron_ingot")
	_check(await _until(func() -> bool: return player.quests.is_finished("torben_smithy"), 300), "smelting iron_ingot finishes torben_smithy")
	_skip_bubbles(player)

	## Lv 5 -> Esma notice appears automatically on Quest Board
	player.progress.award(0, 100000)
	_check(await _until(func() -> bool:
		for offer: Dictionary in town.board.offers:
			if String(offer.get("q", "")) == "spiegelhexe":
				return true
		return false
	, 90), "spiegelhexe_notice posts automatically on Quest Board at Lv >= 5 after torben_smithy")

	print("TORBEN QUEST %s (%d checks)" % ["OK" if _ok else "FAILED", _checks])
	get_tree().quit(0 if _ok else 1)
