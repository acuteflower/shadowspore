extends Node2D
## Contact sheet of refinement in the UI: cards of a plain, a +7, a +15 and a capped weapon, and slots with their "+N" badges.
## Godot --rendering-driver opengl3 --path . tools/preview_refine.tscn -- --capture=/abs.png [--night]

const CARDS: Array = [["sword_iron", 0], ["sword_iron", 7], ["sword_void", 15], ["sword_basic", 5], ["sword_void", 12]]


func _ready() -> void:
	var inventory: InventoryComponent = InventoryComponent.new()
	add_child(inventory)
	var x: float = 8.0
	for entry: Array in CARDS:
		var stack: Dictionary = {"id": String(entry[0]), "count": 1}
		if int(entry[1]) > 0:
			stack["r"] = int(entry[1])
		var tip: ItemTooltip = ItemTooltip.new()
		tip.position = Vector2(x, 8)
		add_child(tip)
		tip.show_stack(stack, false)
		await get_tree().process_frame
		x += tip.size.x + 8.0
	var slot_x: float = 12.0
	for i: int in CARDS.size():
		var stack: Dictionary = {"id": String(CARDS[i][0]), "count": 1}
		if int(CARDS[i][1]) > 0:
			stack["r"] = int(CARDS[i][1])
		inventory.slots[InventoryComponent.HOTBAR_SIZE + i] = stack
		var slot: ItemSlot = ItemSlot.new()
		slot.inventory = inventory
		slot.ref = InventoryComponent.HOTBAR_SIZE + i
		slot.position = Vector2(slot_x, 300)
		add_child(slot)
		slot_x += 26.0
	_capture.call_deferred()


func _capture() -> void:
	for i: int in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color("4f7d4a"))
	for y: int in range(0, 360, 4):
		for x: int in range(0, 640, 4):
			if VineStyle.rand(x * 7 + y * 13) > 0.7:
				draw_rect(Rect2(x, y, 1, 2), Color("6f9c5a"))
