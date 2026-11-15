extends Node
## Captures of the main menu.
## `-- --dir=/abs/folder [--times=1.5,4,8] [--page=settings|confirm] [--tab=0..3] [--seed-save] [--mouse=x,y]`

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir: String = ""
	var times: PackedStringArray = "1.5,4.5,8".split(",")
	var page: String = ""
	var tab: int = 0
	var seed_save: bool = false
	var mouse: Vector2 = Vector2(-1.0, -1.0)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=")
		if arg.begins_with("--times="): times = arg.trim_prefix("--times=").split(",")
		if arg.begins_with("--page="): page = arg.trim_prefix("--page=")
		if arg.begins_with("--tab="): tab = int(arg.trim_prefix("--tab="))
		if arg == "--seed-save": seed_save = true
		if arg.begins_with("--mouse="):
			var parts: PackedStringArray = arg.trim_prefix("--mouse=").split(",")
			mouse = Vector2(float(parts[0]), float(parts[1]))

	var menu: MainMenu = MainMenu.new()
	add_child(menu)
	var ui: MainMenuUi = menu.get("_ui") as MainMenuUi
	if seed_save:
		CloudSession.user_id = "preview-user"
		CloudSession.token = "preview-token"
		CloudSession.uid = "100001"
		CloudSession.username = "PREVIEW"
		CloudSession.has_cloud_save = true
		CloudSession.cloud_save_day = 4
		ui.call("_on_cloud_state_changed", true)
	if not page.is_empty():
		ui.intro = 9.0
		ui.enabled = true
		menu.capture_mode = true
		match page:
			"settings":
				ui.set("_settings_tab", tab)
				ui.call("_open_page", MainMenuUi.Page.SETTINGS)
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

	print("main menu capture done")
	get_tree().quit()
