extends Node
## Main menu check (headless): the menu builds, its pages open, NEUES SPIEL leaves through GameLauncher and a real new game (world + local player) starts in a
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
	for row: Dictionary in ui.get("_rows"):
		main_ids.append(String(row.id))
	_check(main_ids.has("new") and main_ids.has("multi") and main_ids.has("settings") and main_ids.has("quit"), "main entries: %s" % [main_ids])
	_check(main_ids.has("continue") == SaveGame.exists(), "WEITER only with a save")
	for page_id: String in ["multi", "join_page", "back", "settings", "back"]:
		for row: Dictionary in ui.get("_rows"):
			if String(row.id) == page_id:
				ui.call("_press", row, Vector2(-1.0, -1.0))
				break
		await get_tree().process_frame
	_check(ui.page == MainMenuUi.Page.MAIN, "pages open and close")
	# the typed address
	ui.call("_open_page", MainMenuUi.Page.JOIN)
	ui.address = ""
	for c: int in "192.168.0.5:7777".length():
		var key: InputEventKey = InputEventKey.new()
		key.pressed = true
		key.unicode = "192.168.0.5:7777".unicode_at(c)
		_check(bool(ui.call("_type", key)), "typed char accepted")
	_check(ui.address == "192.168.0.5:7777", "address typed: %s" % ui.address)
	ui.call("_open_page", MainMenuUi.Page.MAIN)
	# leave through NEUES SPIEL: needs the save absent to skip the confirm page, so ask the controller directly
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
