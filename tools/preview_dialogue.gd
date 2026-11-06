extends Node
## Actual in-game dialogue view, no networking or save writes.
## Godot --path . tools/preview_dialogue.tscn -- --capture=/tmp/ellie.png [--healthy] [--blink]
var failures: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	TimeManager.time_of_day = 0.4
	await get_tree().process_frame
	var dialogue: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	check(dialogue != null, "local HUD contains dialogue")
	if dialogue == null:
		get_tree().quit(1)
		return
	if args.has("--inventory"):
		var inventory: Control = dialogue.get_parent().get_node("InventoryWindow") as Control
		inventory.call("_set_open", true)
		for frame: int in 150:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		for arg: String in args:
			if arg.begins_with("--capture="):
				get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
		get_tree().quit()
		return
	dialogue.start("spiders_intro")
	check(dialogue.is_active() and get_tree().paused and InputManager.ui_blocking, "dialogue owns pause and input")
	check(InputManager.menu_open, "inventory stays closed during dialogue")
	dialogue._portrait._next_blink = 0
	dialogue._portrait.advance(0.01)
	check(dialogue._portrait._blink_left > 0 and bool(dialogue._portrait._ink.get_shader_parameter("blinking")), "blink selects actual eyelid frame")
	dialogue._portrait.advance(0.2)
	check(dialogue._portrait._blink_left == 0, "blink returns to open eyes")
	var pages: Array = dialogue._paginate([{"speaker": "ELLIE", "text": "WORT ".repeat(120)}])
	check(pages.size() > 2, "long dialogue paginates")
	for page: Dictionary in pages:
		check(String(page.text).split("\n").size() <= 3, "page fits reading area")
	var long_word: PackedStringArray = dialogue._wrap("A".repeat(140), 40)
	check(long_word.size() == 4 and long_word[0].length() == 40, "long words stay inside panel")
	for frame: int in 65:
		await get_tree().process_frame
	dialogue._open = 1.0
	dialogue._typed = 999
	if args.has("--healthy"):
		for page: Dictionary in dialogue._lines:
			page["mood"] = ""
	dialogue._process(0.01)
	if args.has("--blink"):
		dialogue._portrait._blink_left = 0.12
		dialogue._portrait.advance(0)
	var capture: String = ""
	for arg: String in args:
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	if not capture.is_empty():
		# Freeze a deterministic portrait pose while the renderer finishes.
		dialogue.set_process(false)
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(capture) == OK, "rendered dialogue capture")
		dialogue.set_process(true)
	for arg: String in args:
		if arg.begins_with("--record="):
			var folder: String = arg.trim_prefix("--record=")
			DirAccess.make_dir_recursive_absolute(folder)
			dialogue.set_process(false)
			dialogue._portrait._clock = 0
			dialogue._portrait._next_blink = 2.0
			dialogue._portrait._blink_left = 0
			for frame: int in 40:
				dialogue._portrait.advance(0.1)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder.path_join("%03d.png" % frame))
			dialogue.set_process(true)
	if not args.has("--test") and capture.is_empty():
		return
	var event: InputEventAction = InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	dialogue._armed_at = 0
	dialogue._typed = 0
	dialogue._input(event)
	check(dialogue._typed == float(String(dialogue._lines[0].text).length()), "first input completes text")
	dialogue._input(event)
	check(dialogue._page == 1, "second input advances page")
	dialogue._armed_at = 0
	dialogue._typed = 999
	dialogue._input(event)
	dialogue._process(1)
	check(not dialogue.is_active() and not get_tree().paused and not InputManager.ui_blocking and not InputManager.menu_open, "close restores game state")
	get_tree().paused = true
	InputManager.ui_blocking = true
	dialogue.start("spiders_intro")
	dialogue._end()
	check(get_tree().paused and InputManager.ui_blocking, "preexisting pause and blocking are preserved")
	get_tree().paused = false
	InputManager.ui_blocking = false
	print("ELLIE DIALOGUE: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
