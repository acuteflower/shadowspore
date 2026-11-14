extends Node
## Captures of the main menu.
## `-- --dir=/abs/folder [--times=1.5,4,8] [--page=settings|multi|create|join|confirm] [--tab=0..3] [--seed-mp] [--mouse=x,y]`

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir: String = ""
	var times: PackedStringArray = "1.5,4.5,8".split(",")
	var page: String = ""
	var tab: int = 0
	var seed_mp: bool = false
	var mouse: Vector2 = Vector2(-1.0, -1.0)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=")
		if arg.begins_with("--times="): times = arg.trim_prefix("--times=").split(",")
		if arg.begins_with("--page="): page = arg.trim_prefix("--page=")
		if arg.begins_with("--tab="): tab = int(arg.trim_prefix("--tab="))
		if arg == "--seed-mp": seed_mp = true
		if arg.begins_with("--mouse="):
			var parts: PackedStringArray = arg.trim_prefix("--mouse=").split(",")
			mouse = Vector2(float(parts[0]), float(parts[1]))

	var prev_worlds_idx: String = "user://preview_mp_worlds.json"
	var prev_worlds_dir: String = "user://preview_mp_dir"
	if seed_mp:
		MultiplayerWorlds.set_test_paths(prev_worlds_idx, prev_worlds_dir)
		var w1: Dictionary = MultiplayerWorlds.create_world("WALDLICHTUNG", 4, 7777, "K7M4XP")
		MultiplayerWorlds.touch_save(String(w1["id"]), 3, 0.58, 2)
		MultiplayerWorlds.create_world("NEBELKAMM", 3, 7778, "R9P2QT")
		MultiplayerWorlds.add_recent_host("192.168.178.24", 7777, "H4V8WN", "SUMPFLAGER")

	var menu: MainMenu = MainMenu.new()
	add_child(menu)
	var ui: MainMenuUi = menu.get("_ui") as MainMenuUi
	if not page.is_empty():
		ui.intro = 9.0
		ui.enabled = true
		menu.capture_mode = true
		match page:
			"settings":
				ui.set("_settings_tab", tab)
				ui.call("_open_page", MainMenuUi.Page.SETTINGS)
			"multi":
				ui.call("_open_page", MainMenuUi.Page.MULTI)
			"create":
				ui.set("_creating_world", true)
				ui.set("_new_world_name", "GLUTTAL")
				ui.set("_new_world_code", "K7M4XP")
				ui.call("_open_page", MainMenuUi.Page.MULTI, false)
			"join":
				ui.address = "192.168.178.24"
				ui.join_code = "H4V8WN"
				ui.call("_open_page", MainMenuUi.Page.JOIN)
			"confirm":
				ui.call("_open_page", MainMenuUi.Page.CONFIRM_NEW)
	var start: int = Time.get_ticks_msec()
	for t: String in times:
		while float(Time.get_ticks_msec() - start) / 1000.0 < float(t):
			if mouse.x >= 0.0:
				Input.warp_mouse(mouse)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if dir.is_empty():
			continue
		get_viewport().get_texture().get_image().save_png("%s/t%s.png" % [dir, t])

	if seed_mp:
		if FileAccess.file_exists(prev_worlds_idx):
			DirAccess.remove_absolute(prev_worlds_idx)
		MultiplayerWorlds.set_test_paths("", "")
	print("main menu capture done")
	get_tree().quit()
