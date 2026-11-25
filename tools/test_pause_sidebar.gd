extends Node
## Automated test + optional D3D12 visual capture for PauseMenu's expandable right SocialSidebar.
## Pass `-- --dir=<abs_path>` to save PNG screenshots of expanded, collapsed & offline states.

const SocialSidebarScript := preload("res://src/ui/pause_social_sidebar.gd")

var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: %s" % msg)
	else:
		_failures += 1
		printerr("FAIL: %s" % msg)


func _send_key(keycode: Key, unicode_ch: String = "") -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.pressed = true
	ev.physical_keycode = keycode
	ev.keycode = keycode
	if not unicode_ch.is_empty():
		ev.unicode = unicode_ch.unicode_at(0)
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _send_click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var screen_pos: Vector2 = get_viewport().get_screen_transform() * pos
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = screen_pos
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.pressed = true
	press.button_index = button
	press.position = screen_pos
	Input.parse_input_event(press)
	await get_tree().process_frame
	var rel: InputEventMouseButton = InputEventMouseButton.new()
	rel.pressed = false
	rel.button_index = button
	rel.position = screen_pos
	Input.parse_input_event(rel)
	await get_tree().process_frame


func _find_hit(hits: Array[Dictionary], id_prefix: String) -> Rect2:
	for entry: Dictionary in hits:
		if String(entry.get("id", "")).begins_with(id_prefix):
			return entry["rect"] as Rect2
	return Rect2()


func _run() -> void:
	var capture_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			capture_dir = arg.trim_prefix("--dir=")

	# Deterministic logged-in profile + mixed friends/notifications dataset (in-memory only)
	CloudSession.token = "test-sidebar-token"
	CloudSession.user_id = "local-tester-uid"
	CloudSession._notif_ws_token = CloudSession.token
	CloudSession._notif_ws_retry_t = 999.0
	CloudSession.username = "levin_dev"
	CloudSession.display_name = "Levin"
	CloudSession.uid = "482910"
	CloudSession.role = "admin"
	CloudSession.avatar_url = "ellie_lichtung"
	CloudSession.world_join_mode = "ask"
	CloudSession.has_cloud_save = true
	CloudSession.cloud_save_day = 2
	CloudSession.friends_cache = [
		{
			"user_id": "u-mira", "uid": "104521", "username": "mira", "display_name": "Mira",
			"online": true, "state": 0, "role": "moderator", "avatar_url": "ellie_leere",
			"coop_active": true, "coop_world_name": "Mooslichtung", "coop_join_mode": "open",
			"coop_players": 2, "coop_max_players": 4,
		},
		{
			"user_id": "u-kai", "uid": "229840", "username": "kai_w", "display_name": "Kai",
			"online": true, "state": 0, "role": "tester", "avatar_url": "ellie_lichtung",
			"coop_active": true, "coop_world_name": "Nachtwald", "coop_join_mode": "ask",
			"coop_players": 1, "coop_max_players": 4,
		},
		{
			"user_id": "u-sven", "uid": "774120", "username": "sven", "display_name": "Sven",
			"online": true, "state": 0, "role": "player", "avatar_url": "",
			"coop_active": false,
		},
		{
			"user_id": "u-nora", "uid": "338119", "username": "nora", "display_name": "Nora",
			"online": false, "state": 0, "role": "player", "avatar_url": "ellie_leere",
			"coop_active": false,
		},
		{
			"user_id": "u-lenny", "uid": "551029", "username": "lenny", "display_name": "Lenny",
			"online": false, "state": 0, "role": "player", "avatar_url": "",
			"coop_active": false,
		},
		{
			"user_id": "u-req", "uid": "660312", "username": "alicia", "display_name": "Alicia",
			"online": true, "state": 2, "role": "player", "avatar_url": "ellie_lichtung",
		},
		{
			"user_id": "u-out", "uid": "889123", "username": "finn", "display_name": "Finn",
			"online": false, "state": 1, "role": "player", "avatar_url": "",
		},
	]
	CloudSession.notifications = [
		{
			"id": "notif-1",
			"code": 101,
			"content": {"match_id": "m-preview-1", "room_code": "K9LM2P", "host_name": "Mira", "world_name": "Mooslichtung"},
		}
	]

	var level: Node2D = load("res://src/world/test_level.tscn").instantiate() as Node2D
	add_child(level)
	var player: Player = null
	for _i: int in 120:
		player = level.get_node_or_null("Players/1") as Player
		if player != null:
			break
		await get_tree().process_frame
	_check(player != null, "test player spawns")
	if player == null:
		get_tree().quit(1)
		return

	var hud: CanvasLayer = player.get("_hud") as CanvasLayer
	var gm_node: Node = hud.get_node_or_null("GameMenu")
	if gm_node != null:
		gm_node.set_process(false)
		gm_node.set_process_input(false)
		gm_node.set_process_unhandled_input(false)
	InputManager.unified_menu = false
	var pause: PauseMenu = hud.get_node("PauseMenu") as PauseMenu
	pause.embedded_in_menu = false
	pause._coop_last_fetch_msec = Time.get_ticks_msec()
	var sidebar: SocialSidebarScript = pause.get("_sidebar") as SocialSidebarScript
	_check(sidebar != null, "PauseMenu creates SocialSidebar child")
	if sidebar == null:
		get_tree().quit(1)
		return

	# Open via Escape key (real PauseMenu open flow)
	await _send_key(KEY_ESCAPE)
	for _f: int in 45:
		await get_tree().process_frame
	_check(pause._opening and pause.visible, "ESC opens PauseMenu")
	_check(sidebar.visible and sidebar.is_expanded(), "SocialSidebar starts expanded on ESC")
	_check(sidebar.occupied_width() > 180.0, "SocialSidebar expanded width matches drawer spec (got %.1f)" % sidebar.occupied_width())

	# Verify footer buttons are shifted cleanly left of drawer edge (no overlap)
	var drawer_x: float = float(sidebar.call("_drawer_x"))
	var foot0: Rect2 = pause._foot_rect(0)
	var foot1: Rect2 = pause._foot_rect(1)
	_check(foot1.end.x < drawer_x - 4.0 and foot0.end.x < drawer_x - 4.0, "PauseMenu footer buttons stay left of open sidebar (foot1.end=%.1f, drawer_x=%.1f)" % [foot1.end.x, drawer_x])

	if not capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/pause_sidebar_expanded.png" % capture_dir)

	# Copy UID click check
	var uid_rect: Rect2 = _find_hit(sidebar._fixed_hits, "prof_uid")
	_check(uid_rect.has_area(), "profile UID copy chip hit rect present")
	if uid_rect.has_area():
		await _send_click(uid_rect.get_center())
		for _f: int in 4:
			await get_tree().process_frame
		_check(sidebar._toast.contains("482910"), "clicking UID copies & shows toast (toast=%s)" % sidebar._toast)

	# Add-friend input focus & keyboard safety (Q/E must NOT switch PauseMenu tabs, ESC only unfocuses field)
	var add_rect: Rect2 = _find_hit(sidebar._fixed_hits, "add_input")
	_check(add_rect.has_area(), "add-friend input hit rect present")
	if add_rect.has_area():
		await _send_click(add_rect.get_center())
		_check(sidebar.is_typing(), "clicking add-friend box focuses typing")
		var tab_before: int = pause._tab
		await _send_key(KEY_Q, "q")
		await _send_key(KEY_E, "e")
		await _send_key(KEY_1, "1")
		_check(pause._tab == tab_before, "typing Q/E inside sidebar does not switch PauseMenu tabs")
		_check(sidebar._add_text == "qe1", "typing captured into add-friend input (got %s)" % sidebar._add_text)
		await _send_key(KEY_ESCAPE)
		_check(not sidebar.is_typing(), "ESC exits sidebar typing focus")
		_check(pause._opening, "ESC while typing does not close PauseMenu")

	# Scroll wheel check inside feed (include matching release event so Viewport clears mouse_focus)
	var feed_rect: Rect2 = sidebar.call("_feed_clip_rect") as Rect2
	var wheel_pos: Vector2 = get_viewport().get_screen_transform() * feed_rect.get_center()
	var wheel_down: InputEventMouseButton = InputEventMouseButton.new()
	wheel_down.pressed = true
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.position = wheel_pos
	Input.parse_input_event(wheel_down)
	await get_tree().process_frame
	var wheel_rel: InputEventMouseButton = InputEventMouseButton.new()
	wheel_rel.pressed = false
	wheel_rel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_rel.position = wheel_pos
	Input.parse_input_event(wheel_rel)
	for _f: int in 4:
		await get_tree().process_frame
	if sidebar._content_h > feed_rect.size.y:
		_check(sidebar._scroll_y > 0.0, "mouse wheel scrolls social feed (scroll_y=%.1f)" % sidebar._scroll_y)
	else:
		print("INFO: feed fits viewport height in headless/large window (content_h=%.1f <= feed_h=%.1f)" % [sidebar._content_h, feed_rect.size.y])

	# Collapse via header ">" button click & verify PauseMenu click-through works outside rail
	var collapse_rect: Rect2 = _find_hit(sidebar._fixed_hits, "hdr_collapse")
	_check(collapse_rect.has_area(), "header collapse button hit rect present")
	if collapse_rect.has_area():
		await _send_click(collapse_rect.get_center())
		for _f: int in 25:
			await get_tree().process_frame
	_check(not sidebar.is_expanded() and is_equal_approx(sidebar.occupied_width(), 28.0), "clicking collapse button docks sidebar to 28px rail (got %.1f)" % sidebar.occupied_width())

	var col_drawer_x: float = float(sidebar.call("_drawer_x"))
	var col_foot1: Rect2 = pause._foot_rect(1)
	_check(col_foot1.end.x < col_drawer_x - 4.0, "PauseMenu footer buttons clear 28px collapsed rail (foot1.end=%.1f, drawer_x=%.1f)" % [col_foot1.end.x, col_drawer_x])

	if not capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/pause_sidebar_collapsed.png" % capture_dir)

	# Click PauseMenu KOOP tab while sidebar collapsed to confirm outside clicks go to PauseMenu
	var koop_rect: Rect2 = pause._tab_rect(4)
	await _send_click(koop_rect.get_center())
	for _f: int in 4:
		await get_tree().process_frame
	_check(pause._tab == 4, "clicks outside collapsed rail reach PauseMenu KOOP tab (tab=%d)" % pause._tab)

	# Re-expand via clicking collapsed rail, then toggle via TAB shortcut
	var rail_rect: Rect2 = _find_hit(sidebar._fixed_hits, "toggle_drawer")
	_check(rail_rect.has_area(), "collapsed rail hit rect present")
	if rail_rect.has_area():
		await _send_click(rail_rect.get_center())
		for _f: int in 25:
			await get_tree().process_frame
	_check(sidebar.is_expanded() and sidebar.occupied_width() > 180.0, "clicking collapsed rail re-expands sidebar (got %.1f)" % sidebar.occupied_width())

	await _send_key(KEY_TAB)
	for _f: int in 25:
		await get_tree().process_frame
	_check(not sidebar.is_expanded(), "TAB key collapses expanded sidebar")

	await _send_key(KEY_TAB)
	for _f: int in 25:
		await get_tree().process_frame
	_check(sidebar.is_expanded() and sidebar.occupied_width() > 180.0, "TAB key re-expands sidebar smoothly")

	# Logged-out fallback check + optional offline screenshot
	CloudSession.token = ""
	CloudSession.user_id = ""
	CloudSession._notif_ws_token = ""
	CloudSession.uid = ""
	CloudSession.friends_cache = []
	CloudSession.notifications = []
	sidebar.mark_dirty()
	for _f: int in 6:
		await get_tree().process_frame
	_check(not sidebar._has_point(Vector2(100.0, 120.0)) and sidebar._has_point(Vector2(600.0, 120.0)), "_has_point cleanly isolates sidebar hit region")
	if not capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/pause_sidebar_offline.png" % capture_dir)

	# Clean close via PauseMenu
	pause._set_open(false)
	CloudSession.token = ""
	CloudSession.user_id = ""
	CloudSession._notif_ws_token = ""
	print("PAUSE SIDEBAR TEST FAILURES=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
