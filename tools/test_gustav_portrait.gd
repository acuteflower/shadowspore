extends Node
## Gustav's speaking dialogue portrait (SpeechPortrait + DialogueBox): mouth shapes follow the typed letter, blinks, silhouette for the unknown stranger.
## Godot --path . tools/test_gustav_portrait.tscn [-- --capture=/abs/folder]   (no networking, no save writes; use --rendering-driver opengl3 for captures)
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


func _frame(p: SpeechPortrait) -> Vector2i:
	var region: Rect2 = (p.frame() as AtlasTexture).region
	return Vector2i(int(region.position.x) / 103, int(region.position.y) / 153)


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var talker: SpeechPortrait = SpeechPortrait.create()
	check(talker != null and DialogueArt.valid_portrait(talker.frame()), "sheet loads and a frame is 103 x 153")
	if talker == null:
		get_tree().quit(1)
		return
	var sheet: Texture2D = load("res://assets/ui/portrait_gustav_talk.png") as Texture2D
	check(sheet.get_size() == Vector2(103 * 5, 153 * 2), "sheet is 5 mouth shapes x eyes open / closed")
	check(DialogueArt.valid_portrait(load("res://assets/ui/portrait_gustav.png") as Texture2D), "still portrait obeys the contract")
	check(_frame(talker) == Vector2i(0, 0), "rests with closed mouth, eyes open")
	var expected: Dictionary = {"a": 3, "e": 2, "i": 2, "o": 4, "u": 4, "m": 0, "k": 1, " ": 0}
	for letter: String in expected:
		talker.speaking = true
		talker.talk_char = letter
		talker._viseme_hold = 0.0
		talker._next_blink = 99.0
		talker.advance(0.01)
		check(_frame(talker).x == int(expected[letter]), "letter '%s' -> mouth shape %d" % [letter, int(expected[letter])])
	talker.talk_char = "a"
	talker._viseme_hold = 0.0
	talker.advance(0.01)
	talker.talk_char = "o"
	talker.advance(0.01)
	check(_frame(talker).x == 3, "a mouth shape is held for a moment")
	talker.speaking = false
	talker.advance(0.2)
	check(_frame(talker).x == 0, "silent mouth closes")
	talker._next_blink = 0.0
	talker.advance(0.01)
	check(_frame(talker).y == 1, "blink shows the closed-eye row")
	talker.advance(0.2)
	check(_frame(talker).y == 0, "blink ends")

	# the real dialogue box
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var dialogue: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	check(dialogue != null, "local HUD contains the dialogue")
	if dialogue == null:
		get_tree().quit(1)
		return
	dialogue.start("gustav_rescue_b")
	for frame: int in 70:
		await get_tree().process_frame
	var npc: TextureRect = dialogue._npc
	check(npc.visible and npc.texture is AtlasTexture, "Gustav is drawn from the speech sheet")
	check(not dialogue._portrait.visible, "Ellie's portrait is hidden while he speaks")
	var seen: Dictionary = {}
	for frame: int in 40:
		await get_tree().process_frame
		seen[_frame_of(npc)] = true
	check(seen.size() >= 3, "the mouth changes while text is typed (%d shapes seen)" % seen.size())
	dialogue._typed = 9999.0
	for frame: int in 20:
		await get_tree().process_frame
	check(_frame_of(npc).x == 0, "mouth is closed when the line is fully typed")
	var capture: String = ""
	for arg: String in args:
		if arg.begins_with("--capture="):
			capture = arg.trim_prefix("--capture=")
	if not capture.is_empty():
		DirAccess.make_dir_recursive_absolute(capture)
		dialogue.set_process(false)
		dialogue._open = 1.0
		for shape: int in [0, 2, 3, 4]:
			var t: SpeechPortrait = dialogue._talker_for("GUSTAV")
			(t.frame() as AtlasTexture).region = Rect2(shape * 103, 0, 103, 153)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture.path_join("gustav_%d.png" % shape))
	dialogue._end()
	get_tree().paused = false
	print("GUSTAV PORTRAIT: %d failures" % failures)
	get_tree().quit(1 if failures else 0)


func _frame_of(npc: TextureRect) -> Vector2i:
	var region: Rect2 = (npc.texture as AtlasTexture).region
	return Vector2i(int(region.position.x) / 103, int(region.position.y) / 153)
