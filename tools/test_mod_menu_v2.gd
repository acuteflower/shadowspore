extends Node
## The mod menu (O) in the v2 main world (ZoneWorld): an admin host opens it with O, its tabs and cheats work there,
## Escape closes it. `Godot --headless --path . tools/test_mod_menu_v2.tscn` (prints `MOD MENU V2 OK`).

const HudTestWorld = preload("res://tools/hud_test_world.gd")

var player: Player
var checks: int = 0
var failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	CloudSession.token = "test"
	CloudSession.user_id = "test"
	CloudSession.role = "admin"
	player = await HudTestWorld.open(self)
	if player == null:
		push_error("MOD MENU V2: the world did not load")
		get_tree().quit(1)
		return
	await _frames(20)
	var menu: Control = player._hud.get_node_or_null("ModMenu") as Control
	_check(menu != null, "the HUD has the mod menu")
	if menu == null:
		_finish()
		return
	print("gates: gameplay=%s admin=%s server=%s hud=%s alive=%s intro=%s story_lock=%s blocking=%s build=%s freecam=%s paused=%s" % [
		GameGuard.is_gameplay_allowed(), CloudSession.is_admin(), multiplayer.is_server(), player._hud.visible,
		player.health.current > 0.0, player.intro != null, player.story_lock, InputManager.ui_blocking,
		InputManager.build_open, InputManager.freecam_open, get_tree().paused])
	_press("mod_menu")
	await _frames(3)
	_check(menu.visible, "O opens the mod menu in the v2 world")
	_check(InputManager.mod_menu_open, "the open menu holds the hero's input")
	if menu.visible:
		var hp_before: bool = player.health.god_mode
		menu.call("_toggle_god_mode")
		_check(player.health.god_mode != hp_before, "a cheat works in the v2 world")
		menu.call("_toggle_god_mode")
		menu.call("_set_time", 0.5)
		_check(absf(TimeManager.time_of_day - 0.5) < 0.02, "the time buttons set the clock")
		menu.call("_toggle_map")
		var fog: Node = get_tree().get_first_node_in_group("map_discovery")
		_check(fog != null, "the v2 world has a map discovery for the map cheat")
		if fog != null and fog.has_method("is_reveal_all"):
			_check(bool(fog.call("is_reveal_all")), "the map cheat reveals the map")
			menu.call("_toggle_map")
	_press("ui_cancel")
	await _frames(3)
	_check(not menu.visible, "Escape closes the mod menu")
	_check(not InputManager.mod_menu_open and not InputManager.ui_blocking, "closing releases the input")
	_press("mod_menu")
	await _frames(3)
	_check(menu.visible, "O opens it again")
	_press("mod_menu")
	await _frames(3)
	_check(not menu.visible, "O closes it again")
	_finish()


func _finish() -> void:
	print("MOD MENU V2: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("MOD MENU V2 OK")
	get_tree().quit(1 if failures > 0 else 0)


func _press(action: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	var up: InputEventAction = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame
