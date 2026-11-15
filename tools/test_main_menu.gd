extends Node
## Main menu check (headless): the menu builds, its pages open, ABENTEUER BEGINNEN leaves through GameLauncher and a real new game (world + local player) starts in a
## fresh main scene. Never writes the save file. `Godot --headless --path . tools/test_main_menu.tscn`

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var launcher_args: Dictionary = GameLauncher.from_args(PackedStringArray(["--new"]))
	_check(String(launcher_args.get("mode", "")) == "new", "--new -> mode new")
	_check(GameLauncher.from_args(PackedStringArray([])).is_empty(), "no arguments -> the menu")
	_check(String(GameLauncher.from_args(PackedStringArray(["--join=10.0.0.2"])).get("address", "")) == "10.0.0.2", "--join address")
	var host: Node = Node.new() ## the "current scene": it is freed by the scene change, this test node (a plain child of root) survives
	host.name = "Host"
	get_tree().root.add_child(host)
	get_tree().current_scene = host
	var menu: MainMenu = MainMenu.new()
	host.add_child(menu)
	var ui: MainMenuUi = menu.get("_ui") as MainMenuUi
	_check(ui != null, "menu has its ui")
	ui.intro = 5.0
	ui.enabled = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ui.page == MainMenuUi.Page.MAIN, "starts on the main page")
	var main_ids: Array = []
	var main_labels: Dictionary = {}
	for row: Dictionary in ui.get("_rows"):
		main_ids.append(String(row.id))
		main_labels[String(row.id)] = String(row.label)
	_check(main_ids == ["start", "settings", "quit"], "main entries: %s" % [main_ids])
	var expected_start: String = "ABENTEUER FORTSETZEN" if SaveGame.exists() else "ABENTEUER BEGINNEN"
	_check(String(main_labels.get("start", "")) == expected_start, "start label matches save state: %s" % String(main_labels.get("start", "")))
	CloudSession.user_id = "test_u"
	CloudSession.token = "test_t"
	CloudSession.has_cloud_save = true
	CloudSession.cloud_save_day = 3
	CloudSession.save_info_changed.emit()
	await get_tree().process_frame
	_check(String((ui.get("_rows") as Array)[0].get("label", "")) == "ABENTEUER FORTSETZEN", "cloud save switches label to ABENTEUER FORTSETZEN")
	CloudSession.has_cloud_save = false
	CloudSession.save_info_changed.emit()
	await get_tree().process_frame
	_check(String((ui.get("_rows") as Array)[0].get("label", "")) == "ABENTEUER BEGINNEN", "no cloud save switches label to ABENTEUER BEGINNEN")
	CloudSession.user_id = ""
	CloudSession.token = ""
	CloudSession.cloud_save_day = -1
	for page_id: String in ["settings", "back"]:
		for row: Dictionary in ui.get("_rows"):
			if String(row.id) == page_id:
				ui.call("_press", row, Vector2(-1.0, -1.0))
				break
		await get_tree().process_frame
	_check(ui.page == MainMenuUi.Page.MAIN, "pages open and close")
	ui.call("_open_page", MainMenuUi.Page.SETTINGS)
	ui.set("_settings_tab", 2)
	ui.call("_open_page", MainMenuUi.Page.SETTINGS, false)
	ui.set("_editing_id", "player_name")
	ui.set("_player_name_buf", "")
	for c: int in "ELLIE".length():
		var key: InputEventKey = InputEventKey.new()
		key.pressed = true
		key.unicode = "ELLIE".unicode_at(c)
		_check(bool(ui.call("_type", key)), "typed char accepted")
	_check(String(ui.get("_player_name_buf")) == "ELLIE", "player name typed")
	ui.call("_open_page", MainMenuUi.Page.MAIN)
	# leave through ABENTEUER BEGINNEN / new mode: needs the save absent to skip the confirm page, so ask the controller directly
	menu.call("_on_chosen", "new", {})
	var waited: float = 0.0
	var world: Node = null
	var started: bool = false
	while waited < 60.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		world = get_tree().get_first_node_in_group("world")
		if world != null:
			var players: Node = world.get("_players") as Node
			if players != null and players.get_child_count() > 0:
				started = true
				break
	_check(started, "a new game started in the fresh main scene (world + local player), %.1f s" % waited)
	_check(get_tree().current_scene != null and get_tree().current_scene.get_node_or_null("MainMenu") == null, "the menu is gone")
	print("test_main_menu: ", "OK" if _fails == 0 else "%d FAILED" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
