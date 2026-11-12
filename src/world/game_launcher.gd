class_name GameLauncher
extends RefCounted
## The one place that starts a game (docs/hauptmenue_konzept.md): the main menu and the developer arguments both end here.
## A request is {mode, address}; modes: "continue" (load the save if there is one, else a new game), "new", "host" (up to 4 players), "join".
## The menu (and the pause menu's "Neu beginnen") puts a request in `pending` and reloads main.tscn; `main.gd` takes it and calls `start`.

const WORLD_PATH: String = "res://src/world/world_level.tscn" ## loaded at run time: a preload makes a cycle (World -> pause menu -> launcher -> World)
const ARENA_PATH: String = "res://src/world/test_level.tscn"
const MAIN: String = "res://src/world/main.tscn"
const MODES: PackedStringArray = ["continue", "new", "host", "join"]

static var pending: Dictionary = {}


## The request the developer arguments ask for; empty when there are none (then the main menu shows).
static func from_args(args: PackedStringArray) -> Dictionary:
	if args.has("--menu"):
		return {}
	if args.has("--host"):
		return {"mode": "host"}
	if not args.is_empty() and args[0].begins_with("--join"):
		return {"mode": "join", "address": args[0].get_slice("=", 1) if "=" in args[0] else "127.0.0.1"}
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
	pending = request
	tree.paused = false
	Engine.time_scale = 1.0
	InputManager.ui_blocking = false
	InputManager.menu_open = false
	InputManager.build_open = false
	InputManager.map_open = false
	InputManager.journal_open = false
	InputManager.skills_open = false
	InputManager.progress_open = false
	Terrain.relief = null
	var mode: String = String(request.get("mode", "continue"))
	var keep: bool = tree.root.multiplayer.multiplayer_peer is ENetMultiplayerPeer and tree.root.multiplayer.is_server() and tree.root.multiplayer.get_peers().is_empty()
	if mode == "join" or mode == "host" or not keep:
		NetworkManager.leave()
	tree.change_scene_to_file.call_deferred(MAIN)


## Builds the world under `main` and starts what `request` asks for (what main.gd did on its own before the menu existed).
static func start(main: Node, request: Dictionary) -> void:
	var tree: SceneTree = main.get_tree()
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(layer)
	var screen: LoadingScreen = LoadingScreen.new()
	layer.add_child(screen)
	InputManager.ui_blocking = true
	tree.paused = true
	await tree.process_frame
	await tree.process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = String(request.get("mode", "continue"))
	var path: String = ARENA_PATH if args.has("--arena") else WORLD_PATH
	var load_error: Error = ResourceLoader.load_threaded_request(path)
	if load_error != OK:
		_loading_failed(main, screen, "WELT KONNTE NICHT GELADEN WERDEN")
		return
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
		_loading_failed(main, screen, "WELT KONNTE NICHT GELADEN WERDEN")
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	var err: Error = OK
	match mode:
		"host":
			err = NetworkManager.host_multiplayer()
		"join":
			err = NetworkManager.join(String(request.get("address", "127.0.0.1")), int(request.get("port", NetworkManager.DEFAULT_PORT)))
		_:
			err = NetworkManager.host_singleplayer()
	if err != OK:
		push_error("Network setup failed: %s" % error_string(err))
		_loading_failed(main, screen, "VERBINDUNG FEHLGESCHLAGEN")
		return
	var level: Node = packed.instantiate()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	if level.has_method("loading_step"):
		level.set("loading_in_steps", true)
	main.add_child(level)
	if mode == "join":
		var deadline: int = Time.get_ticks_msec() + 30000
		while level.get_node_or_null("Players/%s" % main.multiplayer.get_unique_id()) == null:
			if Time.get_ticks_msec() >= deadline or main.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
				_loading_failed(main, screen, "VERBINDUNG FEHLGESCHLAGEN")
				return
			await tree.process_frame
	if level.has_method("loading_step"):
		while not bool(level.call("loading_step")):
			await tree.process_frame
	var loaded: bool = false
	if mode == "continue" or mode == "host":
		loaded = SaveGame.load_into(main.get_tree(), "", false)
	# Saves may move Ellie to another region. Do not reveal half-built terrain there.
	await tree.process_frame
	if level.has_method("loading_step"):
		while not bool(level.call("loading_step")):
			await tree.process_frame
		level.set("loading_in_steps", false)
	screen.complete()
	await screen.finished
	tree.paused = false
	InputManager.ui_blocking = false
	if loaded and level.has_method("resume_story"):
		level.call("resume_story", SaveGame._local_player(tree))
	elif mode != "join" and not loaded and not args.has("--skip-intro") and level.has_method("start_intro"):
		level.call("start_intro") ## a new game begins in the sewer
	elif mode != "join" and not loaded and level.has_method("begin_story"):
		level.call("begin_story") ## without the intro the first quest starts at once
	await screen.reveal_world()
	layer.queue_free()


static func _loading_failed(main: Node, screen: LoadingScreen, message: String) -> void:
	screen.error_text = message
	var back: Button = Button.new()
	back.text = "Zurück zum Hauptmenü"
	back.position = Vector2(220, 274)
	back.size = Vector2(200, 30)
	screen.add_child(back)
	back.grab_focus()
	back.pressed.connect(func() -> void:
		NetworkManager.leave()
		launch(main.get_tree(), {})
	)
