extends Node
## Look study of the inventory window in the real world.
## `Godot --rendering-driver opengl3 --path . tools/preview_inventory.tscn -- --dir=/abs/folder [--night] [--level=N] [--empty]`
## Writes inventory_open.png (grown in), inventory_grow.png (half way), inventory_hover.png (tooltip), inventory_held.png (stack on the cursor).

var folder: String = ""
var night: bool = false
var level: int = 16 ## talisman slots open at 5 / 15 / 25
var empty: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			folder = arg.trim_prefix("--dir=")
		elif arg == "--night":
			night = true
		elif arg == "--empty":
			empty = true
		elif arg.begins_with("--level="):
			level = arg.trim_prefix("--level=").to_int()
	_run.call_deferred()


func _shot(file: String) -> void:
	if folder == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(file))
	print("saved ", file)


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	var player: Player = world._players.get_child(0) as Player
	player.quests.set_flag("hud_unlocked")
	world.finish_opening()
	TimeManager.set_time(0.0 if night else 0.5)
	var bag: InventoryComponent = player.inventory
	player.progress.award(0, 60000)
	await get_tree().process_frame
	player.progress.request_claim(mini(level, player.progress.level))
	if not empty:
		for entry: Array in [["sword_basic", 1], ["sickle_basic", 1], ["pickaxe_basic", 1], ["axe_basic", 1], ["dusk_berry", 14], ["wood", 37], ["stone", 22],
				["iron_ore", 9], ["glow_cap", 6], ["void_splinter", 4], ["shadow_core", 2], ["sword_rift", 1], ["rissfeder", 1], ["silver_chain", 1],
				["wuchtreif", 1], ["schweigtropfen", 1], ["ember_berry", 5], ["willow_thread", 3], ["staff_hag_elm", 1], ["void_slag", 2]]:
			bag.give(String(entry[0]), int(entry[1]))
		await get_tree().process_frame
		for id: String in ["sword_basic", "silver_chain", "wuchtreif"]:
			for i: int in bag.slots.size():
				if not bag.slots[i].is_empty() and String(bag.slots[i]["id"]) == id:
					bag.request("equip", [i, ""])
					break
	await get_tree().create_timer(3.0).timeout
	var window: Control = player._hud.get_node("InventoryWindow") as Control
	window.call("_set_open", true)
	await get_tree().create_timer(0.38).timeout
	await _shot("inventory_grow.png")
	await get_tree().create_timer(1.6).timeout
	await _shot("inventory_open.png")
	var slots: Array = window.get("_slots") as Array
	for slot: ItemSlot in slots: ## the first filled rucksack slot: its tooltip
		if slot.kind == "inv" and not slot.stack().is_empty():
			get_viewport().warp_mouse(slot.global_position + Vector2(10, 10))
			var motion: InputEventMouseMotion = InputEventMouseMotion.new()
			motion.position = slot.global_position * get_viewport().get_screen_transform().get_scale() + Vector2(20, 20)
			motion.global_position = motion.position
			Input.parse_input_event(motion)
			slot.hovered.emit(slot)
			break
	await get_tree().create_timer(0.8).timeout
	await _shot("inventory_hover.png")
	for slot: ItemSlot in slots: ## a talisman on the cursor: the slots that take it ring up
		if slot.kind == "inv" and TalismanRules.is_talisman(slot.stack()):
			bag.request("click", [slot.kind, slot.ref, 0])
			break
	await get_tree().create_timer(0.6).timeout
	await _shot("inventory_held.png")
	get_tree().quit()
