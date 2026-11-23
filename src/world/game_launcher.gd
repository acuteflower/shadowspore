class_name GameLauncher
extends RefCounted
## The one place that starts a game (docs/hauptmenue_konzept.md): the main menu and the developer arguments both end here.
## A request is {mode, address}; modes: "continue" (load the save if there is one, else a new game), "new", "host" (up to 4 players), "join".
## The menu (and the pause menu's "Neu beginnen") puts a request in `pending` and reloads main.tscn; `main.gd` takes it and calls `start`.

const WORLD_PATH: String = "res://src/world/world_level.tscn" ## loaded at run time: a preload makes a cycle (World -> pause menu -> launcher -> World)
const ARENA_PATH: String = "res://src/world/test_level.tscn"
const TRIALS_PATH: String = "res://src/world/trial_level.tscn" ## the flat test world with every trial (`--trials`, request `world` "trials")
const ZONES_PATH: String = "res://src/world/zones/zone_world.tscn" ## EXPERIMENTAL TEST SYSTEM ONLY (not in the official game): Lost-Ark-style zoned world (`--zones`, request `world` "zones")
const MAIN: String = "res://src/world/main.tscn"
const PREWARMER_SCRIPT: GDScript = preload("res://src/systems/shader_prewarmer.gd")
const RelayPeer: GDScript = preload("res://src/autoload/nakama_relay_peer.gd")
const MODES: PackedStringArray = ["continue", "new", "host", "join", "host_relay", "join_relay"]

static var pending: Dictionary = {}
static var menu_return: Dictionary = {}
static var _transition_layer: CanvasLayer = null
static var _transition_screen: LoadingScreen = null
static var _transitioning: bool = false
static var _join_handshake_active: bool = false
static var _boot_args_consumed: bool = false


static func take_boot_args() -> Dictionary:
	if _boot_args_consumed:
		return {}
	_boot_args_consumed = true
	return from_args(OS.get_cmdline_user_args())


static func is_transitioning() -> bool:
	return _transitioning


static func is_join_handshake_active() -> bool:
	return _join_handshake_active


static func take_menu_return() -> Dictionary:
	var ret: Dictionary = menu_return
	menu_return = {}
	return ret


static func _arg_value(args: PackedStringArray, prefix: String, fallback: String = "") -> String:
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback


## The request the developer arguments ask for; in Release only authenticated Launcher coop links are allowed.
static func from_args(args: PackedStringArray) -> Dictionary:
	var strict: bool = not OS.is_debug_build() or CloudSession.strict_override
	if args.has("--menu"):
		return {}
	if args.has("--host-coop") and (not strict or GameGuard.is_gameplay_allowed()):
		var req: Dictionary = {"mode": "host_relay"}
		var wname: String = _arg_value(args, "--world-name=")
		var jmode: String = _arg_value(args, "--join-mode=")
		var rcode: String = _arg_value(args, "--room-code=")
		if not wname.is_empty():
			req["world_name"] = wname
		if not jmode.is_empty():
			req["join_mode"] = jmode
		if not rcode.is_empty():
			req["code"] = rcode
		return req
	var join_match: String = _arg_value(args, "--join-match=")
	if not join_match.is_empty() and (not strict or GameGuard.is_gameplay_allowed()):
		return {
			"mode": "join_relay",
			"match_id": join_match,
			"code": _arg_value(args, "--room-code="),
			"world_name": _arg_value(args, "--world-name=", "KOOP-WELT"),
		}
	var join_code: String = _arg_value(args, "--join-code=")
	if not join_code.is_empty() and (not strict or GameGuard.is_gameplay_allowed()):
		return {"mode": "join_relay", "code": join_code}
	if strict:
		return {}
	if args.has("--host"):
		return {"mode": "host"}
	if not args.is_empty() and args[0].begins_with("--join"):
		return {"mode": "join", "address": args[0].get_slice("=", 1) if "=" in args[0] else "127.0.0.1"}
	if args.has("--trials"):
		return {"mode": "new", "world": "trials"}
	if args.has("--zones-continue"):
		return {"mode": "continue", "world": "zones"}
	if args.has("--zones"):
		return {"mode": "new", "world": "zones"}
	if args.has("--new"):
		return {"mode": "new"}
	for flag: String in ["--arena", "--skip-intro", "--skip-menu"]:
		if args.has(flag):
			return {"mode": "continue"}
	return {}


## Takes the request left by the menu (empty when there is none).
static func take() -> Dictionary:
	var request: Dictionary = pending
	pending = {}
	return request


## Leaves the menu (or a running game) for a fresh main scene that starts `request`. Puts the autoload state back the way a first start finds it.
static func launch(tree: SceneTree, request: Dictionary) -> void:
	_boot_args_consumed = true
	if not bool(request.get("skip_autosave", false)):
		CloudSession.capture_live_snapshot(tree, tree.root.multiplayer.is_server())
	Engine.time_scale = 1.0
	InputManager.menu_open = false
	InputManager.build_open = false
	InputManager.map_open = false
	InputManager.journal_open = false
	InputManager.skills_open = false
	InputManager.progress_open = false
	var to_menu: bool = request.is_empty() or bool(request.get("to_menu", false))
	if to_menu:
		pending = {}
		tree.paused = false
		InputManager.ui_blocking = false
		if is_instance_valid(_transition_layer):
			_transition_layer.queue_free()
		_transition_layer = null
		_transition_screen = null
		var old_world: Node = tree.get_first_node_in_group("world")
		if old_world != null and old_world.has_method("teardown_step") and not _transitioning:
			_transitioning = true
			_transition_to_main(tree, {})
			return
		_transitioning = false
		TimeManager.unlock()
		WeatherManager.current = null
		Terrain.relief = null
		MapWindow.clear_cache()
		NetworkManager.leave()
		tree.change_scene_to_file.call_deferred(MAIN)
		return
	if _transitioning:
		return
	_transitioning = true
	pending = request
	tree.paused = true
	InputManager.ui_blocking = true
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 120
	_transition_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_transition_screen = LoadingScreen.new()
	_transition_layer.add_child(_transition_screen)
	tree.root.add_child(_transition_layer)
	_transition_to_main(tree, request)


static func _transition_to_main(tree: SceneTree, request: Dictionary) -> void:
	await tree.process_frame
	if not is_instance_valid(tree):
		_transitioning = false
		return
	var old_world: Node = tree.get_first_node_in_group("world")
	if old_world != null and old_world.has_method("teardown_step"):
		while is_instance_valid(old_world) and not bool(old_world.call("teardown_step", Time.get_ticks_usec() + 4500)):
			await tree.process_frame
			if not is_instance_valid(tree):
				_transitioning = false
				return
	TimeManager.unlock()
	WeatherManager.current = null
	Terrain.relief = null
	MapWindow.clear_cache()
	if request.is_empty():
		NetworkManager.leave()
		_transitioning = false
		tree.change_scene_to_file.call_deferred(MAIN)
		return
	var mode: String = String(request.get("mode", "continue"))
	var keep: bool = NetworkManager.is_multiplayer_session() and tree.root.multiplayer.is_server() and tree.root.multiplayer.get_peers().is_empty() and String(request.get("world_id", "")) == NetworkManager.active_world_id
	if mode in ["join", "host", "host_relay", "join_relay", "continue", "new"] or not keep:
		NetworkManager.leave()
	_transitioning = false
	tree.change_scene_to_file.call_deferred(MAIN)


static func _alive(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree()


static func peer_ready_spawned(level: Node, main: Node, peer_connected_ok: bool) -> bool:
	if not peer_connected_ok or not is_instance_valid(level) or not _alive(main):
		return false
	var uid: int = main.multiplayer.get_unique_id()
	if uid <= 0:
		return false
	var player: Node = level.get_node_or_null("Players/%s" % uid)
	if player == null:
		return false
	return bool(player.get("spawn_synced"))


## Builds the world under `main` and starts what `request` asks for (what main.gd did on its own before the menu existed).
static func start(main: Node, request: Dictionary) -> void:
	var tree: SceneTree = main.get_tree()
	var layer: CanvasLayer
	var screen: LoadingScreen
	if is_instance_valid(_transition_layer) and is_instance_valid(_transition_screen):
		layer = _transition_layer
		screen = _transition_screen
		_transition_layer = null
		_transition_screen = null
		layer.reparent(main)
	else:
		layer = CanvasLayer.new()
		layer.layer = 120
		layer.process_mode = Node.PROCESS_MODE_ALWAYS
		main.add_child(layer)
		screen = LoadingScreen.new()
		layer.add_child(screen)
	InputManager.ui_blocking = true
	tree.paused = true
	await tree.process_frame
	if not _alive(main):
		return
	if GameGuard.is_strict_mode() and not GameGuard.is_gameplay_allowed():
		var block_msg: String = GameGuard.lock_reason if not GameGuard.lock_reason.is_empty() else "ZUGANG GESPERRT: BITTE UEBER LAUNCHER STARTEN"
		_loading_failed(main, screen, block_msg)
		return
	var args: PackedStringArray = PackedStringArray() if GameGuard.is_strict_mode() else OS.get_cmdline_user_args()
	var mode: String = String(request.get("mode", "continue"))
	var path: String = ARENA_PATH if args.has("--arena") else WORLD_PATH
	if not GameGuard.is_strict_mode():
		if String(request.get("world", "")) == "trials":
			path = TRIALS_PATH
		elif String(request.get("world", "")) == "zones" or args.has("--zones") or args.has("--zones-continue"):
			path = ZONES_PATH
	var load_error: Error = ResourceLoader.load_threaded_request(path)
	if load_error != OK:
		_loading_failed(main, screen, "WELT KONNTE NICHT GELADEN WERDEN")
		return
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
		if not _alive(main):
			return
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		_loading_failed(main, screen, "WELT KONNTE NICHT GELADEN WERDEN")
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	if not CloudSession.is_logged_in() and not CloudSession.is_strict_release() and DisplayServer.get_name() != "headless" and FileAccess.file_exists(CloudSession.SESSION_PATH):
		await CloudSession.try_restore_session()
		if not _alive(main):
			return
	if CloudSession.is_logged_in() and CloudSession.uid.is_empty():
		await CloudSession.fetch_my_profile()
		if not _alive(main):
			return
	var is_test_sandbox: bool = (path == TRIALS_PATH or path == ZONES_PATH)
	var open_live_relay: bool = mode == "host_relay" or ((mode == "continue" or mode == "new") and CloudSession.is_logged_in() and not is_test_sandbox)
	var err: Error = OK
	if open_live_relay:
		if not CloudSession.is_logged_in():
			menu_return = {"page": "multi", "error": "CLOUD-ANMELDUNG ERFORDERLICH"}
			err = ERR_UNAUTHORIZED
		else:
			var raw_wname: String = String(request.get("world_name", "")).strip_edges()
			if raw_wname.is_empty():
				if mode == "host_relay":
					raw_wname = "KOOP-WELT"
				else:
					var owner_label: String = CloudSession.display_name if not CloudSession.display_name.is_empty() else (CloudSession.username if not CloudSession.username.is_empty() else String(GameSettings.get_value("player_name")))
					var clean_owner: String = owner_label.strip_edges().to_upper()
					raw_wname = ("%s WELT" % clean_owner) if not clean_owner.is_empty() else "MEINE WELT"
			var relay_wname: String = MultiplayerWorlds.sanitize_name(raw_wname, "KOOP-WELT")
			var relay_jmode: String = String(request.get("join_mode", CloudSession.world_join_mode))
			var relay_code: String = String(request.get("code", ""))
			var relay_max: int = int(request.get("max_players", NetworkManager.MAX_PLAYERS))
			var open_res: Dictionary = await CloudSession.coop_open_world(relay_wname, relay_jmode, relay_max, true, relay_code)
			if not _alive(main):
				return
			if not bool(open_res.get("ok", false)):
				menu_return = {"page": "multi" if mode == "host_relay" else "main", "error": String(open_res.get("error", "WELT KONNTE NICHT LIVE GEÖFFNET WERDEN"))}
				err = FAILED
			else:
				var mid: String = String(open_res.get("match_id", ""))
				var rcode: String = String(open_res.get("room_code", relay_code))
				var rmode: String = String(open_res.get("join_mode", relay_jmode))
				err = NetworkManager.host_relay(mid, rcode, relay_max, relay_wname, rmode)
				if err == OK:
					NetworkManager.explicit_coop_hud = (mode == "host_relay")
					var host_deadline: int = Time.get_ticks_msec() + 10000
					while main.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING and Time.get_ticks_msec() < host_deadline:
						main.multiplayer.multiplayer_peer.poll()
						await tree.process_frame
						if not _alive(main):
							return
					if main.multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
						var relay_p: RelayPeer = main.multiplayer.multiplayer_peer as RelayPeer
						var r_err: String = relay_p.last_error if relay_p != null and not relay_p.last_error.is_empty() else "NAKAMA-RELAY VERBINDUNG FEHLGESCHLAGEN"
						NetworkManager.leave()
						menu_return = {"page": "multi" if mode == "host_relay" else "main", "error": r_err}
						err = FAILED
	else:
		match mode:
			"host":
				if GameGuard.is_strict_mode():
					menu_return = {"page": "multi", "error": "OFFLINE/LAN-HOST IN RELEASE DEAKTIVIERT"}
					err = ERR_UNAUTHORIZED
				else:
					var host_port: int = int(request.get("port", NetworkManager.DEFAULT_PORT))
					var host_code: String = String(request.get("code", ""))
					var host_max: int = int(request.get("max_players", NetworkManager.MAX_PLAYERS))
					var host_wid: String = String(request.get("world_id", ""))
					var host_wname: String = String(request.get("world_name", "KOOP-WELT"))
					var host_save: String = String(request.get("save_path", ""))
					err = NetworkManager.host_multiplayer(host_port, host_code, host_max, host_wid, host_wname, host_save)
					if err != OK:
						menu_return = {"page": "multi", "error": "PORT %d BEREITS BELEGT" % host_port}
			"join":
				if GameGuard.is_strict_mode():
					menu_return = {"page": "join", "error": "OFFLINE/LAN-BEITRITT IN RELEASE DEAKTIVIERT"}
					err = ERR_UNAUTHORIZED
				else:
					var join_addr: String = String(request.get("address", "127.0.0.1"))
					var join_port: int = int(request.get("port", NetworkManager.DEFAULT_PORT))
					var join_code: String = String(request.get("code", ""))
					if CloudSession.is_logged_in():
						var ticket_res: Dictionary = await CloudSession.coop_issue_ticket()
						if not _alive(main):
							return
						if bool(ticket_res.get("ok", false)):
							NetworkManager.set_pending_ticket(ticket_res)
					err = NetworkManager.join(join_addr, join_port, join_code, true)
					if err == OK:
						CloudSession.reset_autosave_state()
					else:
						var msg: String = NetworkManager.last_join_error if not NetworkManager.last_join_error.is_empty() else "VERBINDUNG FEHLGESCHLAGEN"
						menu_return = {"page": "join", "address": join_addr, "port": join_port, "code": join_code, "error": msg}
			"join_relay":
				if not CloudSession.is_logged_in():
					menu_return = {"page": "join", "error": "CLOUD-ANMELDUNG ERFORDERLICH"}
					err = ERR_UNAUTHORIZED
				else:
					var target_mid: String = String(request.get("match_id", ""))
					var target_code: String = String(request.get("code", ""))
					var target_wname: String = String(request.get("world_name", "KOOP-WELT"))
					if target_mid.is_empty() and not target_code.is_empty():
						var req_res: Dictionary = await CloudSession.coop_request_join("", target_code)
						if not _alive(main):
							return
						if not bool(req_res.get("ok", false)):
							menu_return = {"page": "join", "error": String(req_res.get("error", "CODE UNGÜLTIG"))}
							err = FAILED
						elif String(req_res.get("status", "")) == "requested":
							menu_return = {"page": "join", "error": "BEITRITTSANFRAGE AN %s GESENDET" % String(req_res.get("host_name", "HOST"))}
							err = FAILED
						else:
							target_mid = String(req_res.get("match_id", ""))
							target_wname = String(req_res.get("world_name", target_wname))
					if err == OK:
						err = NetworkManager.join_relay(target_mid, target_code, target_wname, true)
						if err == OK:
							CloudSession.reset_autosave_state()
							NetworkManager.explicit_coop_hud = true
						else:
							var msg: String = NetworkManager.last_join_error if not NetworkManager.last_join_error.is_empty() else "RELAY-BEITRITT FEHLGESCHLAGEN"
							menu_return = {"page": "join", "error": msg}
			_:
				if GameGuard.is_strict_mode() and not CloudSession.is_entitled():
					menu_return = {"page": "main", "error": "GUELTIGE LIZENZ & ONLINE-VERBINDUNG ERFORDERLICH"}
					err = ERR_UNAUTHORIZED
				else:
					err = NetworkManager.host_singleplayer()
	if err != OK:
		push_error("Network setup failed: %s" % error_string(err))
		var fail_msg: String = String(menu_return.get("error", "VERBINDUNG FEHLGESCHLAGEN"))
		_loading_failed(main, screen, fail_msg)
		return
	var level: Node = packed.instantiate()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	if level.has_method("loading_step"):
		level.set("loading_in_steps", true)
	main.add_child(level)
	if level.has_method("loading_init_step"):
		while not bool(level.call("loading_init_step")):
			await tree.process_frame
			if not _alive(main):
				return
	if mode == "join" or mode == "join_relay":
		_join_handshake_active = true
		var rejected: Array[String] = [""]
		var on_rejected: Callable = func(reason: String) -> void:
			rejected[0] = reason
		NetworkManager.join_rejected.connect(on_rejected)
		var conn_err: Error = NetworkManager.connect_pending_guest()
		if conn_err != OK:
			_join_handshake_active = false
			if NetworkManager.join_rejected.is_connected(on_rejected):
				NetworkManager.join_rejected.disconnect(on_rejected)
			var conn_reason: String = NetworkManager.last_join_error if not NetworkManager.last_join_error.is_empty() else "VERBINDUNG FEHLGESCHLAGEN"
			menu_return = {
				"page": "join",
				"address": String(request.get("address", "")),
				"port": int(request.get("port", NetworkManager.DEFAULT_PORT)),
				"code": String(request.get("code", "")),
				"error": conn_reason,
			}
			_loading_failed(main, screen, conn_reason)
			return
		var deadline: int = Time.get_ticks_msec() + 18000
		while true:
			var join_peer: MultiplayerPeer = main.multiplayer.multiplayer_peer
			if join_peer != null:
				join_peer.poll()
			var peer_connected_ok: bool = join_peer != null and join_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
			if peer_ready_spawned(level, main, peer_connected_ok):
				break
			var disconn: bool = join_peer == null or join_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
			if not rejected[0].is_empty() or disconn or Time.get_ticks_msec() >= deadline:
				_join_handshake_active = false
				if NetworkManager.join_rejected.is_connected(on_rejected):
					NetworkManager.join_rejected.disconnect(on_rejected)
				var reason: String = rejected[0]
				if reason.is_empty():
					if main.multiplayer.multiplayer_peer is RelayPeer:
						reason = (main.multiplayer.multiplayer_peer as RelayPeer).last_error
					if reason.is_empty():
						reason = NetworkManager.last_join_error if not NetworkManager.last_join_error.is_empty() else "VERBINDUNG FEHLGESCHLAGEN"
				menu_return = {
					"page": "join",
					"address": String(request.get("address", "")),
					"port": int(request.get("port", NetworkManager.DEFAULT_PORT)),
					"code": String(request.get("code", "")),
					"error": reason,
				}
				_loading_failed(main, screen, reason)
				return
			await tree.process_frame
			if not _alive(main):
				_join_handshake_active = false
				if NetworkManager.join_rejected.is_connected(on_rejected):
					NetworkManager.join_rejected.disconnect(on_rejected)
				return
		_join_handshake_active = false
		if NetworkManager.join_rejected.is_connected(on_rejected):
			NetworkManager.join_rejected.disconnect(on_rejected)
	var loaded: bool = false
	if mode == "continue" or mode == "host_relay":
		if CloudSession.is_logged_in():
			loaded = await CloudSession.load_cloud_into(tree, false)
		elif not GameGuard.is_strict_mode():
			loaded = SaveGame.load_into(tree, "", false)
	elif mode == "host" and not GameGuard.is_strict_mode():
		loaded = SaveGame.load_into(tree, "", false)
	if level.has_method("loading_step"):
		while not bool(level.call("loading_step")):
			await tree.process_frame
			if not _alive(main):
				return
	await tree.physics_frame
	if not _alive(main):
		return
	if level.has_method("loading_warmup_step"):
		while not bool(level.call("loading_warmup_step")):
			await tree.process_frame
			if not _alive(main):
				return
	if level.has_method("loading_step"):
		level.set("loading_in_steps", false)
	if DisplayServer.get_name() != "headless":
		while screen.age < LoadingScreen.OPEN_SECONDS:
			await tree.process_frame
			if not _alive(main):
				return
		var prewarmer: CanvasLayer = PREWARMER_SCRIPT.new() as CanvasLayer
		main.add_child(prewarmer)
		screen.begin_gpu_warmup()
		await tree.process_frame
		if not _alive(main):
			return
		await tree.process_frame
		if not _alive(main):
			return
		if is_instance_valid(prewarmer):
			prewarmer.queue_free()
		await tree.process_frame
		if not _alive(main):
			return
	screen.complete()
	await screen.finished
	if not _alive(main):
		return
	tree.paused = false
	InputManager.ui_blocking = false
	if loaded and level.has_method("resume_story"):
		level.call("resume_story", SaveGame._local_player(tree))
	elif mode != "join" and mode != "join_relay" and not loaded and not args.has("--skip-intro") and level.has_method("start_intro"):
		level.call("start_intro") ## a new game begins in the sewer
	elif mode != "join" and mode != "join_relay" and not loaded and level.has_method("begin_story"):
		level.call("begin_story") ## without the intro the first quest starts at once
	await tree.process_frame
	if not _alive(main):
		return
	await screen.reveal_world()
	if is_instance_valid(layer):
		layer.queue_free()
	CloudSession.on_world_entered(tree, mode)


static func _loading_failed(main: Node, screen: LoadingScreen, message: String) -> void:
	screen.error_text = message
	var back: Control = _LoadingBackButton.new()
	back.pressed.connect(func() -> void:
		NetworkManager.leave()
		launch(main.get_tree(), {})
	)
	screen.add_child(back)


class _LoadingBackButton extends Control:
	signal pressed()
	var _hover: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP
		position = Vector2(236.0, 266.0)
		size = Vector2(168.0, 26.0)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		var tone: Color = Color("ffb4a8") if _hover else Color("7fe3da")
		var ink: Color = Color("2a2548") if _hover else Color("f3eef8")
		VineStyle.plate(self, Rect2(Vector2.ZERO, size), "ZURÜCK ZUM MENÜ", tone, ink, 1.0, 1.0 if _hover else 0.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var over: bool = Rect2(Vector2.ZERO, size).has_point((event as InputEventMouseMotion).position)
			if over != _hover:
				_hover = over
				queue_redraw()
		elif event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				pressed.emit()
				accept_event()

	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey:
			var key: InputEventKey = event as InputEventKey
			if key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
				pressed.emit()
				get_viewport().set_input_as_handled()
