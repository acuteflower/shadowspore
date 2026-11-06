extends Node
var failures: int = 0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error(label)
func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	var guide: OpeningGuide = player.get_node("OpeningGuide") as OpeningGuide
	guide.set_process(false)
	var knight: FallenKnight = world.fallen_knight
	check(player.inventory.equipment.main_hand.is_empty(), "fresh story starts unarmed")
	check(world._relief.flat_around(knight.position, 30), "knight spot lies on flat land")
	print("KNIGHT TILE ",knight.position/16)
	knight._inspect(1)
	check(knight.states.is_empty(), "remote inspection rejected")
	player.position = knight.position + Vector2(-12,12)
	player._camera.reset_smoothing()
	player.quests.import_data({"active":{"find_help":4},"active_steps":{"find_help":"inspect_knight"}})
	knight._inspect(1)
	check(player.quests.has_flag("knight_inspected"), "E inspection advances quest")
	check(world.get_node("Drops").get_child_count() == 1, "one sword drop")
	knight._inspect(1)
	check(world.get_node("Drops").get_child_count() == 1, "inspection cannot duplicate sword")
	var drop: ItemDrop = world.get_node("Drops").get_child(0) as ItemDrop
	for i: int in InventoryComponent.SIZE: player.inventory.slots[i] = {"id":"sword_iron","count":1}
	drop._collect(player)
	check(not bool(knight.states["1"].claimed) and not drop.is_queued_for_deletion(), "full bag preserves pending sword")
	for i: int in InventoryComponent.SIZE: player.inventory.slots[i] = {}
	var path: String = "user://knight_test_only.json"
	check(SaveGame.save(get_tree(),path), "save before taking sword")
	drop._collect(player)
	await get_tree().process_frame
	check(bool(knight.states["1"].claimed) and player.quests.has_flag("knight_sword_taken"), "collect claims loot and advances quest")
	check(SaveGame.load_into(get_tree(),path), "load pre-pickup save")
	check(not bool(knight.states["1"].claimed) and world.get_node("Drops").get_child_count() == 1, "pending drop recreated exactly once")
	drop = world.get_node("Drops").get_child(0) as ItemDrop
	drop._age = 1000
	drop._host_tick()
	check(not drop.is_queued_for_deletion(), "story sword never expires")
	drop._collect(player)
	await get_tree().process_frame
	check(SaveGame.save(get_tree(),path), "save after taking sword")
	check(SaveGame.load_into(get_tree(),path) and world.get_node("Drops").get_child_count() == 0, "claimed sword does not respawn on load")
	DirAccess.remove_absolute(path)
	# Equip through the same inventory operation as right click in the UI.
	for i: int in InventoryComponent.SIZE:
		if String((player.inventory.slots[i] as Dictionary).get("id","")) == "sword_basic":
			player.inventory.request("equip",[i,"main_hand"])
			break
	guide._process(0)
	var dialogue: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	check(dialogue.is_active() and dialogue._lines.size() >= 3, "new Ellie dialogue starts")
	dialogue._end()
	check(player.quests.has_flag("knight_dialogue_done"), "dialogue completion persists")
	check(String(player.quests.current().get("hint","")) == "combo", "equip leads to combo tutorial")
	guide.set_process(true)
	player.attack._server_combo_index = 0
	player.attack._server_swing(Vector2.RIGHT,2)
	await get_tree().process_frame
	check(player.quests.tutorial_combo == 0, "cannot skip to final combo stage")
	for stage: int in 3:
		var deadline: int = Time.get_ticks_msec()+3000
		while not player.attack.can_attack() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
		player.attack.attack(Vector2.RIGHT)
		await get_tree().create_timer(0.18).timeout
		check(player.quests.tutorial_combo == stage+1, "confirmed attack stage %d" % (stage+1))
	check(player.quests.has_flag("sword_combo_done") and String(player.quests.current().get("text","")) == "ERREICHE DIE ABZWEIGUNG", "three attacks finish tutorial and continue quest")
	check(player.wounded and not (player._hud.get_node("Hotbar") as Control).visible, "loot and tutorial do not heal or reveal HUD")
	# Capture before and during the tutorial as well as the final scene.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			player.quests.import_data({"active":{"find_help":7},"active_steps":{"find_help":"sword_combo"},"flags":{"knight_inspected":true,"knight_sword_taken":true,"knight_sword_equipped":true,"knight_dialogue_done":true}})
			player.quests.tutorial_combo = 2
			guide.set_process(false)
	world._stream(true)
	await get_tree().create_timer(2).timeout
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	print("KNIGHT: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
