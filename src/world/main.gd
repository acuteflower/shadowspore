extends Node
## Entry point. Default: singleplayer (local host). Dev flags after `--`:
##   --host            host for up to 4 players
##   --join[=address]  join a host (default 127.0.0.1)
##   --arena           the small movement test arena instead of the world (any mode)
##   --new             singleplayer without loading the save file (a new game, so the intro plays)
##   --skip-intro      a new game without the intro

const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
const ARENA: PackedScene = preload("res://src/world/test_level.tscn")


func _ready() -> void:
	GameSettings.apply()
	var err: Error = OK
	var solo: bool = false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--host"):
		err = NetworkManager.host_multiplayer()
	elif not args.is_empty() and args[0].begins_with("--join"):
		err = NetworkManager.join(args[0].get_slice("=", 1) if "=" in args[0] else "127.0.0.1")
	else:
		err = NetworkManager.host_singleplayer()
		solo = true
	if err != OK:
		push_error("Network setup failed: %s" % error_string(err))
		return
	var level: Node = (ARENA if args.has("--arena") else WORLD).instantiate()
	add_child(level)
	var loaded: bool = false
	if solo and not args.has("--new"):
		loaded = SaveGame.load_into(get_tree())
	if solo and not loaded and not args.has("--skip-intro") and level.has_method("start_intro"):
		level.call("start_intro") ## a new game begins in the sewer
	elif solo and not loaded and level.has_method("begin_story"):
		level.call("begin_story") ## without the intro the first quest starts at once
