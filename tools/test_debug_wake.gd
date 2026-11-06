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
	player.get_node("OpeningGuide").set_process(false)
	var menu: PauseMenu = player._hud.get_node("PauseMenu") as PauseMenu
	player.inventory.give("wood", 3)
	var inventory_before: Array = player.inventory.slots.duplicate(true)
	player.quests.set_flag("developer_test_keep")
	menu._set_open(true)
	menu._select_tab(3)
	var found: bool = false
	for item: Dictionary in menu._items:
		if String(item.get("action", "")) == "return_home": found = true
	check(found, "developer tab has return-home button")
	menu._run_action("return_home")
	await get_tree().process_frame
	check(not get_tree().paused and not menu.visible, "developer menu closes and unpauses")
	check(player.get_node_or_null("WakeScene") == null and player.intro == null and not player.story_lock, "checkpoint is immediately playable without wake scene")
	check(not player.bandaged and not player.wounded and player.health.current == player.health.max_health, "checkpoint restores healed day-two state")
	check(player.quests.is_finished("find_help") and player.quests.is_finished("lumberjack"), "both story quests are complete")
	check(player.quests.current().get("id", "") == "rebuild_hut" and player.quests.current().get("step_id", "") == "rebuild_tasks", "checkpoint starts the hut-renewal follow-up")
	check(player.quests.has_flag("developer_test_keep") and player.quests.has_flag("knows_cooking") and player.quests.has_flag("day2_started"), "checkpoint preserves unrelated flags and unlocks day-two story")
	check(player.inventory.has_item("axe_basic") and player.inventory.has_item("sword_basic"), "checkpoint grants axe and sword")
	for stack: Dictionary in inventory_before:
		if not stack.is_empty(): check(player.inventory.has_item(String(stack.id)), "existing inventory preserved")
	var interiors: Interiors = world.get_node("Interiors") as Interiors
	var hut: Hut = world._hut()
	var quarry: Quarry = world.get_node("Quarry_quarry") as Quarry
	check(interiors.interior_at(player.global_position) == null and player.global_position.distance_to(hut.exit_position) < 60.0, "player is back outside the home hut")
	check(quarry.knight_left and quarry.knight.global_position.distance_to(hut.exit_position) < 40.0, "Valdric waits at home")
	check(world._hut("cabin").board.moved, "cabin board remains moved aside")
	check(world.opening_over and not TimeManager.locked, "opening finishes and clock runs")
	var slots_before: Array = player.inventory.slots.duplicate(true)
	var equipment_before: Dictionary = player.inventory.equipment.duplicate(true)
	menu._run_action("return_home")
	check(player.inventory.slots == slots_before and player.inventory.equipment == equipment_before, "repeating checkpoint does not duplicate equipment")
	player.story_lock = true
	check(not world.debug_can_return_home(), "cannot skip during a story scene")
	player.story_lock = false
	check(world.debug_can_return_home(), "checkpoint can be reused during free play")
	var saved: Dictionary = player.quests.export_data()
	player.quests.import_data(saved)
	world.resume_story(player)
	await get_tree().process_frame
	check(player.quests.is_finished("lumberjack") and player.get_node_or_null("WakeScene") == null, "restoring checkpoint keeps completed story state")
	# Reproduce a save made with the old button: cabin done, follow-up absent.
	(saved.active as Dictionary).erase("rebuild_hut")
	(saved.active_steps as Dictionary).erase("rebuild_hut")
	player.quests.import_data(saved)
	world.resume_story(player)
	check(player.quests.current().get("id", "") == "rebuild_hut", "loading an old checkpoint repairs the missing follow-up")
	player.quests.set_flag("rebuild_wood_delivered")
	var progress_before: Dictionary = player.quests.export_data()
	menu._run_action("return_home")
	check(player.quests.export_data() == progress_before, "repeating checkpoint preserves follow-up progress")
	# A finished follow-up must stay finished rather than restart.
	var completed: Dictionary = player.quests.export_data()
	(completed.active as Dictionary).erase("rebuild_hut")
	(completed.active_steps as Dictionary).erase("rebuild_hut")
	(completed.done as Array).append("rebuild_hut")
	player.quests.import_data(completed)
	world.resume_story(player)
	check(player.quests.is_finished("rebuild_hut") and not player.quests.is_active("rebuild_hut"), "completed follow-up is not restarted")
	print("DEBUG RETURN HOME: %d failures" % failures)
	get_tree().quit(1 if failures else 0)
