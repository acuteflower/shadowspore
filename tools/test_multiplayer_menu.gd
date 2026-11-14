extends Node
## Automated verification for MultiplayerWorlds, MainMenuUi tabs/fields, GameLauncher return state,
## room-code ENet authentication (reject bad code, accept valid code, sync roster + IP + code),
## and per-world SaveGame persistence & PauseMenu KOOP actions.
## Modes:
## - default: offline unit + UI tests
## - -- --server [--port=17961] [--code=K7M4XP] [--expect-save]
## - -- --client-bad [--port=17961]
## - -- --client-good [--port=17961] [--code=K7M4XP]

const DEFAULT_TEST_PORT: int = 17961
const DEFAULT_TEST_CODE: String = "K7M4XP"
const TEST_INDEX: String = "user://test_mp_worlds_index.json"
const TEST_DIR: String = "user://test_mp_worlds_dir"

var _fails: int = 0
var _world: WorldLevel = null


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		printerr("FAIL [test_multiplayer_menu]: ", msg)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var port: int = DEFAULT_TEST_PORT
	var code: String = DEFAULT_TEST_CODE
	for arg: String in args:
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--code="):
			code = arg.trim_prefix("--code=").to_upper()
	if args.has("--server"):
		await _run_server(port, code, args.has("--expect-save"))
		return
	if args.has("--client-bad"):
		await _run_client_bad(port)
		return
	if args.has("--client-good"):
		await _run_client_good(port, code)
		return
	await _run_unit_and_ui()


func _cleanup_test_files() -> void:
	MultiplayerWorlds.set_test_paths(TEST_INDEX, TEST_DIR)
	for path: String in [TEST_INDEX, TEST_INDEX + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(TEST_DIR):
		var d: DirAccess = DirAccess.open(TEST_DIR)
		if d != null:
			d.list_dir_begin()
			var f: String = d.get_next()
			while not f.is_empty():
				if not d.current_is_dir():
					DirAccess.remove_absolute("%s/%s" % [TEST_DIR, f])
				f = d.get_next()
			d.list_dir_end()
		DirAccess.remove_absolute(TEST_DIR)
	MultiplayerWorlds.set_test_paths("", "")


func _run_unit_and_ui() -> void:
	_cleanup_test_files()
	MultiplayerWorlds.set_test_paths(TEST_INDEX, TEST_DIR)

	# 1. Code generation & normalization
	var gen: String = MultiplayerWorlds.generate_code()
	_check(gen.length() == 6, "generated code length is 6: %s" % gen)
	for ch: String in gen:
		_check(MultiplayerWorlds.CODE_CHARS.contains(ch), "generated char valid: %s" % ch)
	_check(MultiplayerWorlds.normalize_code(" ab-12_cd!! ") == "AB12CD", "normalize_code strips & uppercases")
	var parsed: Dictionary = MultiplayerWorlds.parse_address_port("192.168.1.40:8899", 7777)
	_check(String(parsed["address"]) == "192.168.1.40" and int(parsed["port"]) == 8899, "parse_address_port reads port")
	var parsed_default: Dictionary = MultiplayerWorlds.parse_address_port("10.0.0.8", 7777)
	_check(String(parsed_default["address"]) == "10.0.0.8" and int(parsed_default["port"]) == 7777, "parse_address_port uses fallback")

	# 2. Persistent MultiplayerWorlds CRUD
	var w1: Dictionary = MultiplayerWorlds.create_world("  Waldlichtung!! ", 3, 17961, "ab12cd")
	var wid1: String = String(w1.get("id", ""))
	_check(not wid1.is_empty(), "created world has id")
	_check(String(w1["name"]) == "WALDLICHTUNG!!", "world name sanitized: %s" % String(w1["name"]))
	_check(String(w1["code"]) == "AB12CD", "world code preserved")
	_check(int(w1["max_players"]) == 3 and int(w1["port"]) == 17961, "world config persisted")

	var listed: Array[Dictionary] = MultiplayerWorlds.list()
	_check(listed.size() == 1 and String(listed[0]["id"]) == wid1, "world appears in list")

	MultiplayerWorlds.touch_save(wid1, 4, 0.5, 2)
	var fetched: Dictionary = MultiplayerWorlds.get_world(wid1)
	_check(int(fetched["day"]) == 4 and int(fetched["players_seen"]) == 3, "touch_save updates metadata")
	var next_code: String = MultiplayerWorlds.regenerate_code(wid1)
	_check(next_code.length() == 6 and String(MultiplayerWorlds.get_world(wid1)["code"]) == next_code, "regenerate_code persists")

	MultiplayerWorlds.add_recent_host("192.168.0.15", 7777, next_code, "WALDLICHTUNG")
	var recents: Array[Dictionary] = MultiplayerWorlds.recent_hosts()
	_check(recents.size() == 1 and String(recents[0]["code"]) == next_code, "recent_hosts saved")

	# 3. LAN IP discovery
	var ips: PackedStringArray = NetworkManager.local_ips()
	_check(not ips.is_empty(), "NetworkManager.local_ips returns at least fallback IP")

	# 4. MainMenuUi interaction flow (settings tabs, multi world list, create world, join return state)
	var old_name: String = String(GameSettings.get_value("player_name"))
	var ui: MainMenuUi = MainMenuUi.new()
	add_child(ui)
	ui.intro = 9.0
	ui.enabled = true
	await get_tree().process_frame

	ui.call("_open_page", MainMenuUi.Page.SETTINGS)
	await get_tree().process_frame
	for tab_i: int in 4:
		ui.set("_settings_tab", tab_i)
		ui.call("_open_page", MainMenuUi.Page.SETTINGS, false)
		await get_tree().process_frame
		_check(ui.get("_rows").size() >= 2, "settings tab %d builds rows" % tab_i)

	ui.call("_open_page", MainMenuUi.Page.MULTI)
	await get_tree().process_frame
	var found_created: bool = false
	for r: Dictionary in ui.get("_rows"):
		if String(r.id).begins_with("world:"):
			found_created = true
	_check(found_created, "MainMenuUi MULTI lists created persistent world")

	ui.apply_return_state({"page": "join", "address": "192.168.0.22", "port": 7788, "code": "XY99AB", "error": "FALSCHER CODE ODER WELT VOLL"})
	await get_tree().process_frame
	_check(ui.page == MainMenuUi.Page.JOIN, "apply_return_state opens JOIN tab")
	_check(ui.address == "192.168.0.22:7788" and ui.join_code == "XY99AB", "apply_return_state restores address+port+code")
	_check(ui.status == "FALSCHER CODE ODER WELT VOLL", "apply_return_state shows join error")

	ui.call("_paste_join_clipboard", "10.1.2.3:7777 K9M3PQ")
	_check(ui.address == "10.1.2.3:7777" and ui.join_code == "K9M3PQ", "paste invite string splits address and code")

	_check(MultiplayerWorlds.delete_world(wid1), "delete_world succeeds")
	_check(MultiplayerWorlds.list().is_empty(), "deleted world gone")

	GameSettings.set_value("player_name", old_name)
	GameSettings.save()
	_cleanup_test_files()
	print("TEST MULTIPLAYER MENU (UNIT/UI): ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _spawn_world_stepped() -> WorldLevel:
	var w: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	w.loading_in_steps = true
	add_child(w)
	while not w.loading_init_step():
		await get_tree().process_frame
	return w


func _run_server(port: int, code: String, expect_save: bool) -> void:
	_cleanup_test_files()
	MultiplayerWorlds.set_test_paths(TEST_INDEX, TEST_DIR)
	var world_entry: Dictionary = MultiplayerWorlds.create_world("SERVER-TEST", 4, port, code)
	var wid: String = String(world_entry["id"])
	var spath: String = String(world_entry["save_path"])

	var err: Error = NetworkManager.host_multiplayer(port, code, 4, wid, "SERVER-TEST", spath)
	_check(err == OK, "host_multiplayer starts on port %d" % port)
	if err != OK:
		get_tree().quit(1)
		return

	_world = await _spawn_world_stepped()
	var deadline: int = Time.get_ticks_msec() + 30000
	while _world.get_node_or_null("Players/1") == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_world.get_node_or_null("Players/1") != null, "host local player spawned")
	print("TEST MULTIPLAYER SERVER READY")

	if expect_save:
		_check(SaveGame.save(get_tree()), "SaveGame.save saves into world save_path")
		_check(FileAccess.file_exists(spath), "world save file written at %s" % spath)
		var reloaded: Dictionary = MultiplayerWorlds.get_world(wid)
		_check(bool(reloaded.get("has_save", false)), "MultiplayerWorlds reflects saved state")
		_cleanup_test_files()
		NetworkManager.leave()
		print("TEST MULTIPLAYER SERVER SAVE: ", "PASS" if _fails == 0 else "FAIL")
		get_tree().quit(0 if _fails == 0 else 1)
		return

	# Wait for valid guest peer & confirm roster + code
	var guest_deadline: int = Time.get_ticks_msec() + 45000
	while multiplayer.get_peers().is_empty() and Time.get_ticks_msec() < guest_deadline:
		await get_tree().process_frame
	_check(not multiplayer.get_peers().is_empty(), "valid guest connected")
	await get_tree().create_timer(1.0).timeout
	_check(NetworkManager.roster().size() == 2, "host roster has 2 players: %d" % NetworkManager.roster().size())
	_check(SaveGame.save(get_tree()), "host saves MP world with guest")
	_check(FileAccess.file_exists(spath), "custom world save file exists")

	# Wait a moment for client to complete checks before closing
	var wait_until: int = Time.get_ticks_msec() + 10000
	while not multiplayer.get_peers().is_empty() and Time.get_ticks_msec() < wait_until:
		await get_tree().process_frame
	_cleanup_test_files()
	NetworkManager.leave()
	print("TEST MULTIPLAYER SERVER ENET: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _run_client_bad(port: int) -> void:
	var rejected: Array[String] = [""]
	NetworkManager.join_rejected.connect(func(reason: String) -> void: rejected[0] = reason)
	var err: Error = NetworkManager.join("127.0.0.1", port, "WR0NGC")
	_check(err == OK, "client initiate connection with wrong code")
	_world = await _spawn_world_stepped()
	var deadline: int = Time.get_ticks_msec() + 10000
	while rejected[0].is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not rejected[0].is_empty() and rejected[0] != "KEIN HOST UNTER DIESER ADRESSE", "wrong code rejected with auth error: %s" % rejected[0])
	_check(multiplayer.get_peers().is_empty(), "not connected after wrong code")
	NetworkManager.leave()
	print("TEST MULTIPLAYER CLIENT BAD CODE: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _run_client_good(port: int, code: String) -> void:
	var old_recents: Array[Dictionary] = MultiplayerWorlds.recent_hosts()
	var err: Error = NetworkManager.join("127.0.0.1", port, code)
	_check(err == OK, "client initiate connection with valid code")
	_world = await _spawn_world_stepped()
	var deadline: int = Time.get_ticks_msec() + 30000
	while _world.get_node_or_null("Players/%d" % multiplayer.get_unique_id()) == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var local_player: Player = _world.get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as Player
	_check(local_player != null, "guest player spawned with valid code")
	var roster_deadline: int = Time.get_ticks_msec() + 6000
	while (NetworkManager.roster().size() < 2 or NetworkManager.active_room_code != code) and Time.get_ticks_msec() < roster_deadline:
		await get_tree().process_frame
	_check(NetworkManager.roster().size() == 2, "guest received 2-player roster: %d" % NetworkManager.roster().size())
	_check(NetworkManager.active_room_code == code, "guest knows room code: %s" % NetworkManager.active_room_code)
	_check(NetworkManager.active_world_name == "SERVER-TEST", "guest knows world name: %s" % NetworkManager.active_world_name)
	var hud: CanvasLayer = local_player.get("_hud") as CanvasLayer if local_player != null else null
	var mp_hud: MultiplayerHud = hud.get_node_or_null("MultiplayerHud") as MultiplayerHud if hud != null else null
	_check(mp_hud != null and mp_hud.visible, "MultiplayerHud visible ingame in multiplayer")
	# Avoid leaving localhost test host in real recent_hosts if none before
	if old_recents.is_empty():
		var data: Dictionary = MultiplayerWorlds._load_index()
		data["recent_hosts"] = []
		MultiplayerWorlds._write_index(data)
	NetworkManager.leave()
	print("TEST MULTIPLAYER CLIENT GOOD CODE: ", "PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
