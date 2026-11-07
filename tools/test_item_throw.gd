extends Node
## Regression for the inventory cursor-stack model (InventoryComponent: click, rclick, quick, hotkey, throw, dropslot, sort, stow).
## Run: Godot --headless --path . tools/test_item_throw.tscn
var failures: int = 0
var bag: InventoryComponent
var drops: Node


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func clear() -> void:
	for i: int in InventoryComponent.SIZE:
		bag.slots[i] = {}
	for slot_name: String in bag.equipment:
		bag.equipment[slot_name] = {}
	bag.held = {}


func stack(id: String, count: int) -> Dictionary:
	return {"id": id, "count": count}


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var hero: Player = world._players.get_child(0) as Player
	bag = hero.inventory
	drops = get_tree().get_first_node_in_group("drops")
	check(hero != null and drops != null and bag != null, "there is a player, a bag and a drops container")
	var limit: int = Items.max_stack(stack("stone", 1))
	check(limit > 3, "stone stacks (%d)" % limit)
	var hb: int = InventoryComponent.HOTBAR_SIZE

	# ---- left click: take, put down, top up, swap
	clear()
	bag.slots[hb] = stack("stone", 7)
	bag.request("click", ["inv", hb])
	check(bag.held == stack("stone", 7) and (bag.slots[hb] as Dictionary).is_empty(), "LMB takes the whole stack")
	bag.request("click", ["inv", hb + 3])
	check(bag.held.is_empty() and bag.slots[hb + 3] == stack("stone", 7), "LMB on an empty slot puts it down")
	bag.slots[hb + 4] = stack("stone", 5)
	bag.request("click", ["inv", hb + 3])
	bag.request("click", ["inv", hb + 4])
	check(bag.slots[hb + 4] == stack("stone", 12) and bag.held.is_empty(), "LMB on the same item tops the stack up")
	bag.slots[hb + 5] = stack("stone", limit - 2)
	bag.request("click", ["inv", hb + 4])
	bag.request("click", ["inv", hb + 5])
	check(int(bag.slots[hb + 5].count) == limit and int(bag.held.count) == 10, "a full stack takes only what fits, the rest stays on the cursor (%d)" % int(bag.held.get("count", 0)))
	bag.slots[hb + 6] = stack("plant_fiber", 2)
	bag.request("click", ["inv", hb + 6])
	check(bag.slots[hb + 6] == stack("stone", 10) and bag.held == stack("plant_fiber", 2), "LMB on another item swaps them")
	bag.request("click", ["inv", hb + 7])
	check(bag.held.is_empty(), "the cursor is empty again")

	# ---- the hotbar only takes tools and food
	clear()
	bag.slots[hb] = stack("stone", 3)
	bag.request("click", ["inv", hb])
	bag.request("click", ["inv", 2])
	check(bag.held == stack("stone", 3) and (bag.slots[2] as Dictionary).is_empty(), "a stone cannot be put into the hotbar")
	check(not bag.can_place("inv", 2) and bag.can_place("inv", hb + 1), "can_place agrees")
	bag.request("stow", [0])
	check(bag.held.is_empty() and bag.count_item("stone") == 3, "stow puts the cursor stack back into the bag")

	# ---- right click: half, one
	clear()
	bag.slots[hb] = stack("stone", 9)
	bag.request("rclick", ["inv", hb])
	check(bag.held == stack("stone", 5) and bag.slots[hb] == stack("stone", 4), "RMB takes half (rounded up)")
	bag.request("rclick", ["inv", hb + 1])
	check(bag.held == stack("stone", 4) and bag.slots[hb + 1] == stack("stone", 1), "RMB with a full hand puts ONE down")
	bag.request("rclick", ["inv", hb + 1])
	check(bag.slots[hb + 1] == stack("stone", 2) and int(bag.held.count) == 3, "RMB on the same item adds one")
	bag.request("rclick", ["inv", hb])
	check(bag.slots[hb] == stack("stone", 5), "RMB on the stack you took from adds one back")
	clear()
	bag.slots[hb] = stack("stone", 1)
	bag.request("rclick", ["inv", hb])
	check(bag.held == stack("stone", 1) and (bag.slots[hb] as Dictionary).is_empty(), "RMB on a single stackable piece takes it")

	# ---- gear: RMB equips, worn gear comes off
	clear()
	bag.slots[hb] = stack("sword_basic", 1)
	bag.request("rclick", ["inv", hb])
	check(bag.held.is_empty() and not (bag.equipment["main_hand"] as Dictionary).is_empty(), "RMB equips a single piece of gear")
	bag.request("rclick", ["equip", "main_hand"])
	check((bag.equipment["main_hand"] as Dictionary).is_empty() and bag.count_item("sword_basic") == 1, "RMB on worn gear takes it off")
	for i: int in InventoryComponent.SIZE:
		if not (bag.slots[i] as Dictionary).is_empty():
			bag.request("quick", ["inv", i])
			break
	check(not (bag.equipment["main_hand"] as Dictionary).is_empty(), "shift-click equips gear")
	bag.request("quick", ["equip", "main_hand"])
	check((bag.equipment["main_hand"] as Dictionary).is_empty() and bag.count_item("sword_basic") == 1, "shift-click on worn gear takes it off")
	clear()
	bag.slots[hb] = stack("sword_basic", 1)
	bag.request("click", ["inv", hb])
	bag.request("click", ["equip", "main_hand"])
	check(not (bag.equipment["main_hand"] as Dictionary).is_empty() and bag.held.is_empty(), "LMB puts gear into its slot")
	bag.request("click", ["equip", "chest"])
	check(not bag.can_place("equip", "chest"), "no slot takes a thing it does not accept")

	# ---- shift-click between hotbar and rucksack
	clear()
	bag.slots[hb + 2] = stack("sickle_basic", 1)
	bag.request("quick", ["inv", hb + 2])
	check((bag.slots[hb + 2] as Dictionary).is_empty() and bag.slots[0] == stack("sickle_basic", 1), "shift-click sends a tool from the rucksack to the hotbar")
	bag.request("quick", ["inv", 0])
	check((bag.slots[0] as Dictionary).is_empty() and bag.slots[hb] == stack("sickle_basic", 1), "and back to the rucksack")
	bag.slots[hb + 1] = stack("stone", 4)
	bag.request("quick", ["inv", hb + 1])
	check(bag.slots[hb + 1] == stack("stone", 4), "a stone has no place in the hotbar: nothing moves")

	# ---- number keys
	clear()
	bag.slots[hb + 5] = stack("pickaxe_basic", 1)
	bag.slots[3] = stack("sickle_basic", 1)
	bag.request("hotkey", ["inv", hb + 5, 3])
	check(bag.slots[3] == stack("pickaxe_basic", 1) and bag.slots[hb + 5] == stack("sickle_basic", 1), "a number key over a slot swaps it with that hotbar slot")
	bag.slots[hb + 6] = stack("stone", 2)
	bag.request("hotkey", ["inv", hb + 6, 4])
	check(bag.slots[hb + 6] == stack("stone", 2), "a number key never puts a stone into the hotbar")
	bag.request("hotkey", ["inv", 3, 6])
	check((bag.slots[3] as Dictionary).is_empty() and bag.slots[6] == stack("pickaxe_basic", 1), "from the hotbar into an empty hotbar slot")
	bag.request("click", ["inv", hb + 5])
	bag.request("hotkey", ["held", 0, 1])
	check(bag.held.is_empty() and bag.slots[1] == stack("sickle_basic", 1), "with a stack on the cursor a number key puts it into the hotbar")

	# ---- throwing
	clear()
	var before: int = drops.get_child_count()
	bag.slots[hb] = stack("stone", 7)
	bag.request("dropslot", ["inv", hb, false])
	check(bag.slots[hb] == stack("stone", 6) and drops.get_child_count() == before + 1, "Q over a slot throws one piece")
	var one: ItemDrop = drops.get_child(drops.get_child_count() - 1) as ItemDrop
	check(one.item_id == "stone" and one.count == 1 and one.launch.length() > ItemDrop.MAGNET_RADIUS * 2.0, "it is a single stone thrown out of the magnet's reach")
	bag.request("dropslot", ["inv", hb, true])
	check((bag.slots[hb] as Dictionary).is_empty() and (drops.get_child(drops.get_child_count() - 1) as ItemDrop).count == 6, "Ctrl+Q throws the whole stack")
	bag.held = stack("stone", 4)
	before = drops.get_child_count()
	bag.request("throw", [false])
	check(int(bag.held.count) == 3 and drops.get_child_count() == before + 1, "a click on nothing with RMB throws one piece of the cursor stack")
	bag.request("throw", [true])
	check(bag.held.is_empty() and (drops.get_child(drops.get_child_count() - 1) as ItemDrop).count == 3, "LMB on nothing throws the rest")
	before = drops.get_child_count()
	bag.request("throw", [true])
	bag.request("dropslot", ["inv", 9999, true])
	bag.request("dropslot", ["equip", "nonsense", true])
	check(drops.get_child_count() == before, "nothing to throw, nothing thrown")

	# ---- sorting
	clear()
	bag.slots[hb] = stack("stone", 10)
	bag.slots[hb + 5] = stack("plant_fiber", 3)
	bag.slots[hb + 9] = stack("stone", 20)
	bag.slots[hb + 12] = stack("sickle_basic", 1)
	bag.request("sort", [0])
	check(bag.slots[hb] == stack("sickle_basic", 1), "sort puts tools first")
	check(bag.count_item("stone") == 30 and bag.count_item("plant_fiber") == 3, "sort keeps everything")
	var stone_stacks: int = 0
	for i: int in range(hb, InventoryComponent.SIZE):
		if not (bag.slots[i] as Dictionary).is_empty() and String(bag.slots[i].id) == "stone":
			stone_stacks += 1
	check(stone_stacks == (1 if limit >= 30 else 2), "sort merges equal stacks (%d)" % stone_stacks)

	# ---- the slot control turns clicks into ops (only while the window is open)
	clear()
	bag.slots[hb] = stack("stone", 6)
	var slot: ItemSlot = ItemSlot.new()
	slot.kind = "inv"
	slot.ref = hb
	slot.inventory = bag
	add_child(slot)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	InputManager.inventory_open = false
	slot._gui_input(press)
	check(bag.held.is_empty(), "a closed inventory takes no clicks")
	InputManager.inventory_open = true
	slot._gui_input(press)
	check(bag.held == stack("stone", 3), "a right click on the slot takes half")
	press.button_index = MOUSE_BUTTON_LEFT
	press.shift_pressed = true
	slot._gui_input(press)
	check(bag.held == stack("stone", 3), "shift-click is ignored while the cursor holds something")
	press.shift_pressed = false
	slot._gui_input(press)
	check(bag.held.is_empty() and bag.slots[hb] == stack("stone", 6), "a left click puts the stack back and tops up")
	InputManager.item_keys_claimed = true
	check(InputManager.hotbar_pick() == -1, "the hotbar does not select on a number key the inventory used")
	InputManager.item_keys_claimed = false
	InputManager.inventory_open = false

	# ---- clear_all drops the cursor stack too
	bag.held = stack("stone", 1)
	bag.clear_all()
	check(bag.held.is_empty(), "clear_all empties the cursor")
	print("DONE failures=", failures)
	get_tree().quit(failures)
