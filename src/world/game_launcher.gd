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
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = String(request.get("mode", "continue"))
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
		return
	var level: Node = (load(ARENA_PATH if args.has("--arena") else WORLD_PATH) as PackedScene).instantiate()
	main.add_child(level)
	var loaded: bool = false
	if mode == "continue" or mode == "host":
		loaded = SaveGame.load_into(main.get_tree())
	if mode != "join" and not loaded and not args.has("--skip-intro") and level.has_method("start_intro"):
		level.call("start_intro") ## a new game begins in the sewer
	elif mode != "join" and not loaded and level.has_method("begin_story"):
		level.call("begin_story") ## without the intro the first quest starts at once
