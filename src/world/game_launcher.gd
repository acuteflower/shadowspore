class_name GameLauncher
extends RefCounted
## The one place that starts a game (docs/hauptmenue_konzept.md): the main menu and the developer arguments both end here.
## A request is {mode, address}; modes: "continue" (load the save if there is one, else a new game), "new", "host" (up to 4 players), "join".
## The menu (and the pause menu's "Neu beginnen") puts a request in `pending` and reloads main.tscn; `main.gd` takes it and calls `start`.

const WORLD_PATH: String = "res://src/world/world_level.tscn" ## loaded at run time: a preload makes a cycle (World -> pause menu -> launcher -> World)
const ARENA_PATH: String = "res://src/world/test_level.tscn"
const TRIALS_PATH: String = "res://src/world/trial_level.tscn" ## the flat test world with every trial (`--trials`, request `world` "trials")
const MAIN: String = "res://src/world/main.tscn"
const PREWARMER_SCRIPT: GDScript = preload("res://src/systems/shader_prewarmer.gd")
const MODES: PackedStringArray = ["continue", "new", "host", "join"]

static var pending: Dictionary = {}
static var menu_return: Dictionary = {}
static var _transition_layer: CanvasLayer = null
static var _transition_screen: LoadingScreen = null
static var _transitioning: bool = false


static func take_menu_return() -> Dictionary:
	var ret: Dictionary = menu_return
	menu_return = {}
	return ret


## The request the developer arguments ask for; empty when there are none (then the main menu shows).
static func from_args(args: PackedStringArray) -> Dictionary:
	if args.has("--menu"):
		return {}
	if args.has("--host"):
		return {"mode": "host"}
	if not args.is_empty() and args[0].begins_with("--join"):
		return {"mode": "join", "address": args[0].get_slice("=", 1) if "=" in args[0] else "127.0.0.1"}
	if args.has("--trials"):
		return {"mode": "new", "world": "trials"}
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
	Engine.time_scale = 1.0
	InputManager.menu_open = false
	InputManager.build_open = false
	InputManager.map_open = false
	InputManager.journal_open = false
	InputManager.skills_open = false
	InputManager.progress_open = false
	if request.is_empty():
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
	var keep: bool = tree.root.multiplayer.multiplayer_peer is ENetMultiplayerPeer and tree.root.multiplayer.is_server() and tree.root.multiplayer.get_peers().is_empty() and String(request.get("world_id", "")) == NetworkManager.active_world_id
	if mode == "join" or mode == "host" or not keep:
		NetworkManager.leave()
	_transitioning = false
	tree.change_scene_to_file.call_deferred(MAIN)


static func _alive(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree()


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
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = String(request.get("mode", "continue"))
	var path: String = ARENA_PATH if args.has("--arena") else WORLD_PATH
	if String(request.get("world", "")) == "trials":
		path = TRIALS_PATH
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
	var err: Error = OK
	match mode:
		"host":
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
			var join_addr: String = String(request.get("address", "127.0.0.1"))
			var join_port: int = int(request.get("port", NetworkManager.DEFAULT_PORT))
			var join_code: String = String(request.get("code", ""))
			err = NetworkManager.join(join_addr, join_port, join_code)
			if err != OK:
				var msg: String = NetworkManager.last_join_error if not NetworkManager.last_join_error.is_empty() else "VERBINDUNG FEHLGESCHLAGEN"
				menu_return = {"page": "join", "address": join_addr, "port": join_port, "code": join_code, "error": msg}
		_:
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
	if mode == "join":
		var rejected: Array[String] = [""]
		var on_rejected: Callable = func(reason: String) -> void:
			rejected[0] = reason
		NetworkManager.join_rejected.connect(on_rejected)
		var deadline: int = Time.get_ticks_msec() + 18000
		while level.get_node_or_null("Players/%s" % main.multiplayer.get_unique_id()) == null:
			var disconn: bool = main.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED
			if not rejected[0].is_empty() or disconn or Time.get_ticks_msec() >= deadline:
				if NetworkManager.join_rejected.is_connected(on_rejected):
					NetworkManager.join_rejected.disconnect(on_rejected)
				var reason: String = rejected[0]
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
				if NetworkManager.join_rejected.is_connected(on_rejected):
					NetworkManager.join_rejected.disconnect(on_rejected)
				return
		if NetworkManager.join_rejected.is_connected(on_rejected):
			NetworkManager.join_rejected.disconnect(on_rejected)
	var loaded: bool = false
	if mode == "continue" or mode == "host":
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
	elif mode != "join" and not loaded and not args.has("--skip-intro") and level.has_method("start_intro"):
		level.call("start_intro") ## a new game begins in the sewer
	elif mode != "join" and not loaded and level.has_method("begin_story"):
		level.call("begin_story") ## without the intro the first quest starts at once
	await tree.process_frame
	if not _alive(main):
		return
	await screen.reveal_world()
	if is_instance_valid(layer):
		layer.queue_free()


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
