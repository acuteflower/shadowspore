extends Node
var failures: int = 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func check(ok: bool,label: String) -> void:
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	check(DialogueArt.valid_portrait(DialogueBox.NPC_PORTRAITS["???"]),"knight uses shared 103x153 grid")
	box.start("rescue")
	for i: int in 60: await get_tree().process_frame
	box._open = 1.0
	box._typed = 999
	box._process(0.0)
	check(box._npc.visible and bool(box._npc_ink.get_shader_parameter("unknown")),"rescue stranger is silhouetted")
	check(box._npc.size == box._portrait.size,"all speakers use identical display size")
	check(not box._speaker_unknown({"speaker":"ELLIE"}),"Ellie remains visible")
	check(box._speaker_unknown({"speaker":"SOMEONE","unknown":true}),"metadata can conceal another speaker")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/ritter-unbekannt-dialog.png")
	var quests: QuestComponent = player.quests
	var previous: Dictionary = quests.export_data()
	quests.set_flag("knows_adventurer")
	box._process(0.0)
	check(not bool(box._npc_ink.get_shader_parameter("unknown")),"identity flag reveals portrait")
	var saved: Dictionary = quests.export_data()
	quests.import_data(previous)
	check(box._speaker_unknown(box._lines[0]),"unknown save retains silhouette")
	quests.import_data(saved)
	check(not box._speaker_unknown(box._lines[0]),"known identity persists through save data")
	box._end()
	# Equal-size production comparison: normal knight, stranger, Ellie.
	var view: SubViewport = SubViewport.new()
	view.size = Vector2i(700,360)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(700,360)
	bg.color = Color("171322")
	view.add_child(bg)
	for i: int in 3:
		var label: Label = Label.new()
		label.text = ["RITTER","UNBEKANNT","ELLIE"][i]
		label.position = Vector2(24+230*i,14)
		label.add_theme_font_size_override("font_size",16)
		view.add_child(label)
		if i < 2:
			var art: TextureRect = TextureRect.new()
			art.texture = DialogueBox.NPC_PORTRAITS["???"]
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			art.position = Vector2(15+230*i,45)
			art.size = DialogueArt.DISPLAY_SIZE
			view.add_child(art)
			if i == 1:
				var ink: ShaderMaterial = ShaderMaterial.new()
				ink.shader = DialogueBox.UNKNOWN_SHADER
				art.material = ink
		else:
			var art: ElliePortrait = ElliePortrait.new()
			art.position = Vector2(15+230*i,45)
			art.size = DialogueArt.DISPLAY_SIZE
			view.add_child(art)
			art.advance(0.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("/tmp/dialogportraits-v2-vergleich.png")
	print("DIALOGUE ART: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
