extends Node
## Free camera (L) and the developer tab's teleport field.
var failures: int = 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(3)
	var player: Player = world._players.get_child(0) as Player
	player.get_node("OpeningGuide").set_process(false)
	var fc: FreeCam = player.get_node("FreeCam") as FreeCam
	check(fc != null, "player carries a FreeCam")
	var home: Vector2 = player.global_position
	check(fc._can_enter(), "can enter on free ground")
	fc._enter()
	check(InputManager.freecam_open and fc.active() and InputManager.move_vector() == Vector2.ZERO, "entering stops her and flags the input")
	check(world.editor_camera == fc._cam, "world streams round the camera")
	check(not InputManager.attack_pressed() and not InputManager.interact_pressed(), "world actions are blocked")
	# Fly 30 tiles east onto land and land there.
	var target: Vector2 = home + Vector2(480.0, 0.0)
	fc._pos = target
	await _frames(90)
	check(fc._loaded_at(target + Vector2(0, 22)), "chunks stream round the camera")
	fc._leave()
	check(not fc.active() and not InputManager.freecam_open, "L again lands her")
	check(player.global_position.distance_to(target + Vector2(0, 22)) <= 70.0, "she stands where the camera looked (%s vs %s)" % [player.global_position, target])
	check(player.get_node("Camera2D").is_current() and world.editor_camera == null, "her camera is back and the hook is released")
	# Flying over the void refuses to land.
	fc._enter()
	fc._pos = Vector2(8.0, 8.0)
	fc._leave()
	check(fc.active(), "no landing in the void")
	fc._cancel()
	check(not fc.active(), "cancel leaves the camera mode")
	# Teleport field of the developer tab.
	var menu: PauseMenu = player._hud.get_node("PauseMenu") as PauseMenu
	menu._set_open(true)
	menu._select_tab(3)
	var field: Dictionary = {}
	for item: Dictionary in menu._items:
		if String(item.get("kind", "")) == "field": field = item
	check(not field.is_empty() and menu._tp_text != "", "developer tab has a prefilled coordinate field")
	menu._activate(field)
	check(menu._editing, "activating the field takes the keys")
	menu._tp_text = ""
	for ch: String in "420, 610x":
		var key: InputEventKey = InputEventKey.new()
		key.pressed = true
		key.unicode = ch.unicode_at(0)
		key.physical_keycode = KEY_UNKNOWN
		menu._type_into_field(key)
	check(menu._tp_text == "420, 610", "only digits, comma, space are typed (%s)" % menu._tp_text)
	menu._run_action("teleport")
	check(not menu.visible and not get_tree().paused, "teleport closes the menu")
	var tile: Vector2 = player.global_position / 16.0
	check(absf(tile.x - 420.0) <= 17.0 and absf(tile.y - 610.0) <= 17.0, "she stands near tile 420, 610 (%s)" % tile)
	menu._set_open(true)
	menu._select_tab(3)
	menu._tp_text = "abc"
	menu._run_action("teleport")
	check(menu._failed_flash > 0.0, "garbage input fails")
	# The developer page is taller than the screen: it scrolls.
	menu._set_open(true)
	menu._select_tab(3)
	menu.size = Vector2(640, 360)
	menu._build_items()
	check(menu._max_scroll() > 0.0, "developer page is taller than the screen (%s)" % menu._max_scroll())
	var last: Dictionary = menu._items[0]
	for item: Dictionary in menu._items: ## the lowest row of the page
		if float(item["y"]) > float(last["y"]): last = item
	check(not menu._row_visible(last), "the last row starts off screen")
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	for i: int in 30:
		menu._gui_input(wheel)
	check(is_equal_approx(menu._scroll, menu._max_scroll()), "wheel scrolls down to the end")
	check(menu._row_visible(last), "the last row is reachable after scrolling")
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i: int in 30:
		menu._gui_input(wheel)
	check(menu._scroll == 0.0, "wheel scrolls back to the top")
	menu._select_tab(0)
	check(menu._scroll == 0.0, "changing tab resets the scroll")
	print("FREECAM: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
