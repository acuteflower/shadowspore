extends Node
## Entry point. Without arguments the main menu shows (src/ui/main_menu.gd); it hands its choice to `GameLauncher`, which reloads this scene and starts the game.
## Dev flags after `--` skip the menu and start at once:
##   --host            host for up to 4 players
##   --join[=address]  join a host (default 127.0.0.1)
##   --arena           the small movement test arena instead of the world (any mode)
##   --trials          the flat test world with every trial of the Wächterin (never saved)
##   --new             singleplayer without loading the save file (a new game, so the intro plays)
##   --skip-intro      a new game without the intro
##   --skip-menu       singleplayer straight into the game (loads the save)
##   --menu            the menu even when other flags are given


func _ready() -> void:
	GameSettings.apply()
	if not GameGuard.initialized:
		await GameGuard.verify_startup_async()
		if not is_inside_tree():
			return
	if not GameGuard.is_gameplay_allowed():
		if not GameGuard.access_restored.is_connected(_continue_boot):
			GameGuard.access_restored.connect(_continue_boot, CONNECT_ONE_SHOT)
		return
	_continue_boot()


func _continue_boot() -> void:
	if not is_inside_tree() or not GameGuard.is_gameplay_allowed():
		return
	var request: Dictionary = GameLauncher.take()
	if request.is_empty():
		request = GameLauncher.from_args(OS.get_cmdline_user_args())
	if request.is_empty():
		add_child(MainMenu.new())
		return
	GameLauncher.start(self, request)
