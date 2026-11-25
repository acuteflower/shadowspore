extends Node
## Launch --host, --mira and --kai concurrently for the three-peer ENet check.
const ChatWindow := preload("res://src/ui/game_chat.gd")
var failed: bool = false


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failed = true
		printerr("CHAT FAIL: ", what)


func _received(body: String) -> bool:
	for row: Dictionary in Chat.lines:
		if row.text == body:
			return true
	return false


func _wait_for(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 120000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(condition.call())


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var chat := ChatWindow.new()
	add_child(chat)
	chat.open_chat()
	_check(InputManager.ui_blocking and InputManager.move_vector() == Vector2.ZERO, "composer owns input")
	if args.has("--host") or args.has("--mira") or args.has("--kai"):
		var host: bool = args.has("--host")
		var mira: bool = args.has("--mira")
		GameSettings.set_value("player_name", "Ellie" if host else ("Mira" if mira else "Kai"))
		NetworkManager._identity = Crypto.new().generate_random_bytes(NetworkManager.IDENTITY_BYTES)
		var err: Error = NetworkManager.host_multiplayer(18372) if host else NetworkManager.join("127.0.0.1", 18372)
		_check(err == OK, "enet startup")
		print("CHAT ENET READY ", args, " ", err)
		if await _wait_for(func() -> bool: return NetworkManager.roster().size() == 3):
			if host:
				await Chat.send("group", "Treffpunkt am Lagerfeuer")
			_check(await _wait_for(_received.bind("Treffpunkt am Lagerfeuer")), "group delivered")
			if mira:
				await chat._submit("/msg Kai")
				_check(chat._key.begins_with("peer/"), "open by name")
				await chat._submit("/mesage Kai Unter vier Augen")
				_check(await _wait_for(_received.bind("Bis gleich")), "DM reply")
				await Chat.send("group", "Fertig")
			elif not host:
				_check(await _wait_for(_received.bind("Unter vier Augen")), "incoming DM")
				await chat._submit("/r Bis gleich")
			_check(await _wait_for(_received.bind("Fertig")), "group finish")
			if host:
				_check(not _received("Unter vier Augen") and not _received("Bis gleich"), "host transcript excludes guest DMs")
		else:
			_check(false, "three peers connected")
	else:
		await chat._submit("/r")
		_check(chat._hint.text.contains("keine Direktnachricht"), "empty reply")
		NetworkManager._roster.assign([{"id": 2, "name": "Mira Mond"}])
		for alias: String in ["/dm", "/message", "/mesage", "/msg"]:
			await chat._submit(alias + " Mira Mond")
			_check(chat._key == "peer/2", alias + " opens the named conversation")
		NetworkManager._roster.clear()
		var sidebar := PauseSocialSidebar.new()
		add_child(sidebar)
		CloudSession.friends_cache.assign([{"user_id": "mira", "username": "Mira"}])
		sidebar._dispatch_action("friend_dm", "mira")
		_check(chat._key == "dm/mira" and chat._field.has_focus(), "friend button opens the composer")
		var row: Dictionary = {"sender_id": "mira", "username": "Mira", "message_id": "1", "content": JSON.stringify({"text": "Kommst du mit zur Lichtung?"})}
		Chat._channels["dm/mira"] = "private-channel"
		row.channel_id = "private-channel"
		CloudSession._handle_ws_envelope({"channel_message": row})
		Chat._cloud_line("dm/mira", row, false)
		_check(Chat.lines.size() == 1 and Chat.reply_to == "dm/mira", "deduplication and reply recipient")
		chat._select(Chat.reply_to)
		_check(chat._log.get_parsed_text().contains("Kommst du mit"), "private transcript")
		chat._select("game")
		_check(not chat._log.get_parsed_text().contains("Kommst du mit"), "game transcript isolates DM")
		chat._select(Chat.reply_to)
		# --- Whisper Vine 2.0 feature & ESC regression checks ---
		chat._field.text = "/"
		chat._on_field_changed("/")
		_check(chat._suggestions.size() >= 5, "slash autocomplete lists commands")
		chat._accept_suggestion(0)
		_check(chat._field.text.begins_with("/msg "), "accepting first suggestion fills /msg")
		NetworkManager._roster.assign([{"id": 2, "name": "Mira Mond", "slot": 1}])
		chat._field.text = "/msg Mi"
		chat._on_field_changed("/msg Mi")
		_check(chat._suggestions.size() >= 1 and String(chat._suggestions[0]["label"]) == "Mira Mond", "player autocomplete matches roster")
		chat._accept_suggestion(0)
		_check(chat._field.text == "/msg Mira Mond ", "accepting player suggestion fills name")
		NetworkManager._roster.clear()
		await chat._submit("/help")
		_check(chat._log.get_parsed_text().contains("/ort") and chat._log.get_parsed_text().contains("ESC"), "/help posts command guide")
		await chat._submit("/clear")
		_check(not chat._log.get_parsed_text().contains("Kommst du mit"), "/clear hides local channel lines")
		await chat._submit("/s")
		_check(chat._key == "game", "/s switches to game channel")
		await chat._submit("/g")
		_check(chat._key == "group", "/g switches to group channel")
		chat._cycle_channel(1)
		_check(chat._key != "group", "Tab channel cycle advances channel")
		_check(String(chat._current_location_text()).begins_with("[Ort] "), "/ort formats location")
		await chat._submit("/me")
		_check(chat._hint.text.contains("/me"), "empty /me shows usage hint")
		# Sent history Up/Down + draft restore
		chat._field.text = "Entwurf"
		chat._step_history(-1)
		_check(chat._field.text == "/me", "Up recalls last sent entry")
		chat._step_history(1)
		_check(chat._field.text == "Entwurf", "Down restores unsent draft")
		# ESC closes chat via _input and guards same-frame menu polling
		var esc: InputEventKey = InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = true
		chat._input(esc)
		_check(not InputManager.chat_open and InputManager.chat_closed_recently(), "ESC closes chat and arms menu bleed guard")
		# Incoming message while closed feeds ambient whisper list & unread badge
		Chat._record("group", "Kai", "Komm zur Lichtung!", false, "amb-1", "2026-11-25T21:44:00Z", true)
		_check(chat._ambient_rows.size() >= 1 and chat._unread_priority_count() >= 1, "closed chat records ambient whisper and unread bud")
		chat.open_chat()
		chat._select(Chat.reply_to)
		for arg: String in args:
			if arg.begins_with("--capture="):
				await RenderingServer.frame_post_draw
				_check(get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture=")) == OK, "capture")
	chat.close_chat()
	_check(not InputManager.chat_open, "close releases chat input")
	print("CHAT TEST ", "FAIL" if failed else "PASS", " ", args)
	get_tree().quit(1 if failed else 0)
