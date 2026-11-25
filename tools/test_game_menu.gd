extends Node
## Automated regression test + optional GPU visual capture for:
##   - Schattenfrüchte 2.0 & CampSporeBed
##   - Standalone InventoryWindow on `I` (detached from GameMenu)
##   - Redesigned 6-tab unified GameMenu ('Der Feldcodex') including native MenuChrome PFAD, WELT & SYSTEM tabs!

const HudTestWorld := preload("res://tools/hud_test_world.gd")

var _shots_dir: String = ""
var _checks: int = 0
var _fails: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
	if not _shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	_run.call_deferred()


func _assert(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("GAME MENU TEST FAIL: " + msg)
		print("FAIL: ", msg)


func _wait_frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _save_shot(filename: String, upscale: int = 2) -> void:
	if _shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_assert(false, "empty screenshot for " + filename)
		return
	if upscale > 1 and img.get_width() <= 640:
		img.resize(img.get_width() * upscale, img.get_height() * upscale, Image.INTERPOLATE_NEAREST)
	var err: Error = img.save_png(_shots_dir.path_join(filename))
	_assert(err == OK, "saved " + filename)
	print("SHOT: ", filename, " (", img.get_width(), "x", img.get_height(), ")")


func _run() -> void:
	var player: Player = await HudTestWorld.open(self)
	_assert(player != null, "ZoneWorld loaded with player")
	if player == null:
		get_tree().quit(1)
		return

	var hud: CanvasLayer = player.get("_hud") as CanvasLayer
	_assert(hud != null, "HUD attached to player")
	var menu: GameMenu = hud.get_node_or_null("GameMenu") as GameMenu
	_assert(menu != null, "GameMenu attached to HUD")
	_assert(GameMenu.TABS.size() == 6, "GameMenu has 6 focused tabs (Inventory detached)")
	_assert(String(GameMenu.TABS[2]["label"]) == "CHARAKTER" and String(GameMenu.TABS[3]["label"]) == "SCHATTENFRÜCHTE", "Renamed tabs CHARAKTER & SCHATTENFRÜCHTE active")
	_assert(PathTab.MEDALLIONS_TEX != null, "Hand-crafted skill_medallions.png loaded in PathTab")

	var inv_win: Control = hud.get_node_or_null("InventoryWindow") as Control
	_assert(inv_win != null and not bool(inv_win.get("embedded_in_menu")), "InventoryWindow stays standalone (embedded_in_menu == false)")
	GameCursor.visible = false

	# Stock inventory, XP/level, quests, and one caught fish to showcase RiverBook record crown + water tank
	for id: String in ["sickle_basic", "pickaxe_basic", "axe_basic", "rod_basic"]:
		player.inventory.give(id, 1)
	player.inventory.give("dusk_berry", 6)
	player.inventory.give("glimmer", 3)
	player.progress.copper = 485
	player.progress.award(0, 180) ## pushes to Level 3 with unclaimed rewards + free skill points!
	if player.quests != null:
		player.quests.start("lumberjack")
	if player.fishing != null and player.fishing.book != null:
		player.fishing.book.species["moon_trout"] = {"caught": 3, "best": 38, "first_day": 2}

	var vt: VeilThreads = VeilThreads.of(get_tree())
	_assert(vt != null, "VeilThreads system present")
	var entries: Array[Dictionary] = vt.entries_for_zone(&"windkap")
	_assert(entries.size() == 8, "Windkap has 8 Schattenfrüchte")
	var seed_ids: Array[String] = []
	for i: int in 6:
		seed_ids.append(String(entries[i]["id"]))

	TimeManager.day = 2
	TimeManager.set_time(0.45)
	vt.import_state({
		"version": 2,
		"collected": seed_ids,
		"claimed_milestones": [],
		"endless_claimed": 0,
		"bed_gift_day": 0,
	})
	_assert(vt.collected_count() == 6, "v2 import restores 6 fruits")
	_assert(vt.has_unclaimed_milestone(), "unclaimed milestones detected at 6 fruits")
	_assert(vt.bed_gift_ready(), "SporeBed morning gift ready")

	var base_slots: int = player.inventory.active_size()
	vt.request_claim_milestone("bag_1")
	_assert(player.inventory.bonus_slots == 4, "bag_1 grants +4 bonus slots")
	_assert(player.inventory.active_size() == base_slots + 4, "inventory active_size grew by 4")
	player.inventory.slots[32] = {"id": "glimmer", "count": 2}

	# 0. Verify Standalone InventoryWindow opens independently with 28 bag slots & closes cleanly
	inv_win.call("_set_open", true)
	await _wait_frames(32)
	_assert(inv_win.visible and not menu.is_open(), "Standalone InventoryWindow opens without GameMenu")
	await _save_shot("v2_00_inventory_standalone.png", 2)
	inv_win.call("_set_open", false)
	await _wait_frames(18)

	# 1. ATLAS (harmonized obsidian/gold cartographer HUD!)
	menu.open_tab("atlas", true)
	await _wait_frames(20)
	_assert(menu.is_open() and InputManager.ui_blocking, "GameMenu opened on ATLAS")
	await _save_shot("v3_01_atlas.png", 2)

	# 2. Brand-new native AUFGABEN (QuestTab grimoire)
	menu.open_tab("quests", true)
	await _wait_frames(16)
	_assert(menu._quest_tab != null and menu._quest_tab.visible, "Native Feldcodex QuestTab active on AUFGABEN")
	await _save_shot("v3_02_aufgaben.png", 2)

	# 3. Upgraded PFAD (TALENTE + STUFEN)
	menu.open_tab("path", true, "skills")
	await _wait_frames(16)
	await _save_shot("v3_03_pfad_talente.png", 2)
	# Verify Echo exploration updates cleanly & doesn't break state
	var skills_c: SkillTreeComponent = player.get_node_or_null("SkillTreeComponent") as SkillTreeComponent
	if skills_c != null and skills_c.can_explore("combat_echo_b"):
		skills_c.request_explore("combat_echo_b")
		await _wait_frames(4)
		_assert(skills_c.is_explored("combat_echo_b"), "PFAD/TALENTE explores combat_echo_b cleanly")
	menu.open_tab("path", true, "progress")
	await _wait_frames(16)
	await _save_shot("v3_03_pfad_stufen.png", 2)

	# Verify claiming levels directly via ProgressComponent works!
	var prev_claimed: int = player.progress.claimed
	player.progress.request_claim(player.progress.level)
	await _wait_frames(4)
	_assert(player.progress.claimed == player.progress.level and player.progress.claimed > prev_claimed, "PFAD/STUFEN claims level rewards cleanly")

	# 4. FRÜCHTE
	menu.open_tab("fruits", true)
	await _wait_frames(18)
	await _save_shot("v3_04_fruechte.png", 2)

	# 5. Upgraded WELT (CHRONIK with 3-column sidebar, STADT, VÖGEL, FLUSSBUCH)
	menu.open_tab("world", true, "chronicle")
	await _wait_frames(16)
	if menu._world_tab != null and menu._world_tab._atlas_book != null:
		var ab: AtlasBook = menu._world_tab._atlas_book
		_assert(ab._zone_btn_rects.size() >= 2, "CHRONIK renders clickable zone sidebar rows")
		var all_inside: bool = ab._reward_rects.size() == 3
		for rr: Dictionary in ab._reward_rects:
			var r_card: Rect2 = rr["rect"] as Rect2
			if r_card.end.y > ab._book_rect.end.y - 4.0:
				all_inside = false
		_assert(all_inside, "All 3 CHRONIK milestone cards stay strictly inside book frame (zero overflow)")
	await _save_shot("v3_05_welt_chronik.png", 2)
	menu.open_tab("world", true, "town")
	await _wait_frames(12)
	await _save_shot("v3_05_welt_stadt.png", 2)
	menu.open_tab("world", true, "pets")
	await _wait_frames(12)
	await _save_shot("v3_05_welt_voegel.png", 2)
	menu.open_tab("world", true, "river")
	var rb: RiverBook = hud.get_node_or_null("RiverBook") as RiverBook
	if rb != null:
		rb.selected = 2 ## moon_trout (caught record showcase!)
	await _wait_frames(16)
	await _save_shot("v3_05_welt_flussbuch.png", 2)

	# 6. Upgraded SYSTEM (EINSTELLUNGEN, STEUERUNG, KOOP & SITZUNG)
	menu.open_tab("system", true, "settings")
	await _wait_frames(22)
	await _save_shot("v3_06_system_settings.png", 2)
	menu.open_tab("system", true, "controls")
	await _wait_frames(14)
	await _save_shot("v3_06_system_controls.png", 2)
	menu.open_tab("system", true, "coop")
	await _wait_frames(14)
	await _save_shot("v3_06_system_coop.png", 2)

	# Test collapsing SocialSidebar inside SystemTab & verify dynamic width expansion!
	if menu._system_tab != null:
		menu._system_tab.toggle_sidebar()
		await _wait_frames(22)
		menu.open_tab("system", true, "settings")
		await _wait_frames(12)
		await _save_shot("v3_06_system_settings_wide.png", 2)

	# Verify ATLAS -> CHRONIK signal routing & bidirectional save sync!
	var mw_chk: MapWindow = hud.get_node_or_null("MapWindow") as MapWindow
	if mw_chk != null and mw_chk.atlas_view() != null:
		mw_chk.atlas_view().open_chronicle_requested.emit(&"suedkap")
		await _wait_frames(6)
		_assert(menu._active_tab == 4 and menu._world_tab != null and menu._world_tab._sub == 0 and menu._world_tab._atlas_book._zone_id == &"suedkap", "ATLAS open_chronicle_requested routes to WELT/CHRONIK on target zone")
		# Mutate a stamp in WorldTab._atlas_book and verify MapWindow.export_atlas_ui_state() receives it
		menu._world_tab._atlas_book.import_state({"claimed": {"windkap": [30]}, "stamps": ["coast_wave"], "frames": [], "frame_enabled": true})
		menu._world_tab._atlas_book.state_changed.emit()
		var exp_ui: Dictionary = mw_chk.export_atlas_ui_state()
		var exp_book: Dictionary = exp_ui.get("book", {}) as Dictionary
		var exp_stamps: Array = exp_book.get("stamps", []) as Array
		_assert(exp_stamps.has("coast_wave"), "WELT/CHRONIK state_changed syncs into MapWindow SaveGame export")
		# Reset clean before screenshots
		menu._world_tab._atlas_book.import_state({"claimed": {}, "stamps": [], "frames": [], "frame_enabled": true})
		menu._world_tab._atlas_book.state_changed.emit()

	# Close via embedded MapWindow travel finish & verify full GameMenu cleanup!
	if mw_chk != null:
		menu.open_tab("atlas", true)
		await _wait_frames(4)
		mw_chk._close_after_travel()
		await _wait_frames(6)
		_assert(not menu.is_open() and not InputManager.ui_blocking and not get_tree().paused, "Embedded MapWindow fast-travel closes GameMenu cleanly")
	else:
		menu.close(true)
		await _wait_frames(8)
		_assert(not menu.is_open() and not InputManager.ui_blocking and not get_tree().paused, "GameMenu closed cleanly")

	# Verify claiming stamina_1 & bed gift
	var old_stam: float = player.stamina.max_stamina
	vt.request_claim_milestone("stamina_1")
	_assert(player.stamina.max_stamina >= old_stam + 14.5, "stamina_1 increased max_stamina by +15")
	vt.request_harvest_bed_gift()
	_assert(not vt.bed_gift_ready(), "SporeBed morning gift consumed")

	print("GAME MENU TEST: ", _checks, " checks, ", _fails, " failures")
	if _fails == 0:
		print("GAME MENU TEST OK")
	get_tree().quit(0 if _fails == 0 else 1)
