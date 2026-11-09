extends Node
## Godot --headless --path . --fixed-fps 60 tools/test_smithy_shop.tscn
## Torben's forge shop (data/shops.json "torben_forge"): FERTIGEN (ore -> ingot, plain sword), BESTELLEN (plates, forged sword: only he makes them, only while he works), KAUFEN, VERKAUFEN.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("SMITHY SHOP FAILED: ", what)


func _idx(id: String) -> int:
	var p: Player = (get_tree().get_first_node_in_group("world") as WorldLevel)._players.get_child(0) as Player
	for i: int in InventoryComponent.SIZE:
		if String((p.inventory.slots[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(62)
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	world.debug_jump_town(true)
	await _frames(120)
	_check(town.has_built("smithy") and town.residents.has("torben"), "the smithy stands and Torben lives there")
	var torben: Settler = town.settler_node("torben")
	_check(torben != null, "Torben's figure exists")
	var smithy_id: int = town.built_ids("smithy")[0]
	player.request_teleport(town.rect_of(smithy_id).get_center() + Vector2(0, 90))
	await _frames(30)
	TimeManager.locked = true
	TimeManager.time_of_day = 0.4 ## the work hours: he stands at the anvil
	await _frames(240)
	_check(torben.is_working(), "he works at the anvil in the day (%s)" % torben._spot)
	torben.interact(player) ## E at him while he works opens the forge, no chat line
	await _frames(30)
	var shop: ShopWindow = get_tree().get_first_node_in_group("shop_window") as ShopWindow
	_check(shop != null and shop.shop_id == "torben_forge", "E at the working smith opens his shop")
	_check(shop != null and shop.tabs.size() == 5 and shop.speaker == torben and String(shop.tabs[4].kind) == "refine", "five tabs, the fifth is VERFEINERN, Torben answers")
	# --- FERTIGEN
	var ids: Array[String] = []
	for row: Dictionary in shop.rows:
		ids.append(String(row.recipe))
	_check(ids == ["iron_ingot", "sword_basic"], "FERTIGEN lists only the smithy's own recipes (%s)" % str(ids))
	player.inventory.give("iron_ore", 4)
	player.inventory.give("wood", 2)
	town.request_craft("iron_ingot")
	await _frames(3)
	_check(player.inventory.count_item("iron_ingot") >= 1 and player.inventory.count_item("iron_ore") == 2, "two ore and a log became an ingot")
	town.request_craft("iron_ingot")
	await _frames(3)
	player.inventory.give("plank", 1)
	town.request_craft("sword_basic")
	await _frames(3)
	_check(player.inventory.has_item("sword_basic"), "ingots and a plank became a plain sword")
	# --- BESTELLEN
	shop._set_tab(1)
	var ordered: Array[String] = []
	for row: Dictionary in shop.rows:
		ordered.append(String(row.recipe))
	_check(ordered == ["iron_plate", "sword_iron"], "BESTELLEN lists plates and the forged sword (%s)" % str(ordered))
	player.inventory.give("iron_ingot", 3)
	_check(town.order_block("iron_plate", player) == "", "plates can be ordered (%s)" % town.order_block("iron_plate", player))
	town.request_order("iron_plate")
	await _frames(3)
	_check(town.orders.size() == 1 and town.maker_of(town.orders[0] as Dictionary) == "torben", "the order is Torben's")
	var left_a: float = float((town.orders[0] as Dictionary).left)
	await _frames(120)
	_check(float((town.orders[0] as Dictionary).left) < left_a - 1.0, "he works on it at the anvil")
	(town.orders[0] as Dictionary).left = 0.1
	await _frames(60)
	shop._on_town_changed()
	_check(String(shop.rows[0].kind) == "queue" and String(shop.rows[0].tag) == "ABHOLEN", "the finished plates wait on the bench")
	shop.focus = 0
	shop._press("collect", false)
	await _frames(3)
	_check(player.inventory.count_item("iron_plate") == 2 and town.orders.is_empty(), "collecting gives two plates")
	_check(town.order_block("sword_iron", player) != "", "the forged sword needs more than a plain sword (%s)" % town.order_block("sword_iron", player))
	player.inventory.give("iron_ingot", 2)
	player.inventory.give("void_splinter", 1)
	(town.residents["torben"] as Dictionary).trust = 0
	_check("TRAUT" in town.order_block("sword_iron", player), "it wants his trust")
	(town.residents["torben"] as Dictionary).trust = 30
	_check(town.order_block("sword_iron", player) == "", "with trust and material the forged sword can be ordered (%s)" % town.order_block("sword_iron", player))
	var swords: int = player.inventory.count_item("sword_basic")
	town.request_order("sword_iron")
	await _frames(3)
	_check(player.inventory.count_item("sword_basic") == swords - 1 and town.orders.size() == 1, "sword, plates, ingots and splinter are handed over")
	# --- KAUFEN / VERKAUFEN
	player.progress.award(500, 0)
	shop._set_tab(2)
	var copper: int = player.progress.copper
	var ingots: int = player.inventory.count_item("iron_ingot")
	for i: int in shop.rows.size():
		if String(shop.rows[i].item) == "iron_ingot":
			shop.focus = i
	shop._press("buy", false)
	await _frames(3)
	_check(player.inventory.count_item("iron_ingot") == ingots + 1 and player.progress.copper == copper - 40, "an ingot costs 40 copper")
	shop._set_tab(3)
	player.inventory.give("iron_ore", 3)
	await _frames(2)
	for i: int in shop.rows.size():
		if String(shop.rows[i].item) == "iron_ore":
			shop.focus = i
	copper = player.progress.copper
	var ore: int = player.inventory.count_item("iron_ore")
	shop._press("sell_all", false)
	await _frames(3)
	_check(player.inventory.count_item("iron_ore") == 0 and player.progress.copper == copper + 8 * ore, "ore sells for 8 copper")
	# --- VERFEINERN (5th tab)
	var answers: Array = []
	town.refine_done.connect(func(before: Dictionary, after: Dictionary, ok: bool, refund: Dictionary) -> void: answers.append([before, after, ok, refund]))
	town.orders.clear() ## the forged sword of the order test is still on the bench
	var iron: Dictionary = {"id": "sword_iron", "count": 1}
	for i: int in InventoryComponent.SIZE:
		player.inventory.slots[i] = {}
	player.inventory.equipment["main_hand"] = {}
	player.inventory.slots[InventoryComponent.HOTBAR_SIZE] = iron.duplicate()
	player.inventory.slots[InventoryComponent.HOTBAR_SIZE + 1] = {"id": "stone", "count": 4}
	player.inventory.give("iron_plate", 6)
	player.inventory.give("iron_ingot", 6)
	player.progress.award(1000 - player.progress.copper, 0)
	(town.residents["torben"] as Dictionary).trust = 60
	TimeManager.time_of_day = 0.4
	await _frames(60)
	shop._set_tab(4)
	await _frames(5)
	_check(shop.rows.size() == 1 and String(shop.rows[0].kind) == "refine" and String(shop.rows[0].tag) == "100 %" and int(shop.rows[0].state) == BoardWindow.OK, "one weapon is listed, +0 > +1, 100 %% (%s)" % str(shop.rows.map(func(r: Dictionary) -> String: return String(r.get("tag", "")))))
	_check(String(shop.rows[0].sub) == "+0 > +1", "the row says +0 > +1")
	var ingots_before: int = player.inventory.count_item("iron_ingot")
	var copper_before: int = player.progress.copper
	shop.focus = 0
	shop._press("refine", false)
	await _frames(5)
	_check(town.orders.size() == 1 and TownManager.is_refine(town.orders[0] as Dictionary) and town.maker_of(town.orders[0] as Dictionary) == "torben", "the weapon is on Torben's anvil")
	_check(player.inventory.count_item("sword_iron") == 0 and player.inventory.count_item("iron_ingot") == ingots_before - 1 and player.progress.copper == copper_before - RefineRules.copper(iron, 1), "weapon, one ingot and the copper are paid")
	_check(bool((town.orders[0] as Dictionary).ok) and int((town.orders[0] as Dictionary).to) == 1, "a +1 attempt cannot fail")
	shop._set_tab(1)
	_check(shop.rows.filter(func(r: Dictionary) -> bool: return String(r.kind) == "queue").is_empty(), "the order tab does not list the refinement")
	shop._set_tab(4)
	await _frames(3)
	_check(shop.rows.size() == 1 and String(shop.rows[0].kind) == "queue" and String(shop.rows[0].name) == "Geschmiedetes Schwert", "the refine tab shows the weapon on the anvil")
	var wait_a: float = float((town.orders[0] as Dictionary).left)
	await _frames(120)
	_check(float((town.orders[0] as Dictionary).left) < wait_a - 1.0, "he works on it at the anvil")
	town.request_collect(0)
	await _frames(2)
	_check(town.orders.size() == 1, "an unfinished weapon cannot be collected")
	(town.orders[0] as Dictionary).left = 0.1
	await _frames(60)
	shop._on_town_changed()
	shop.focus = 0
	shop._press("collect", false)
	await _frames(3)
	var back: Dictionary = {}
	for i: int in InventoryComponent.SIZE:
		if String((player.inventory.slots[i] as Dictionary).get("id", "")) == "sword_iron":
			back = player.inventory.slots[i]
	_check(Items.refine(back) == 1 and town.orders.is_empty(), "collecting returns the weapon as +1")
	_check(answers.size() == 1 and bool(answers[0][2]) and Items.refine(answers[0][0]) == 0 and Items.refine(answers[0][1]) == 1, "the collection tells the reveal: success, +0 -> +1")
	await _frames(5)
	var reveal: RefineReveal = get_tree().get_first_node_in_group("refine_reveal") as RefineReveal
	_check(reveal != null and not reveal._revealed, "the card opens in its heating phase")
	await _frames(70)
	_check(reveal._revealed and reveal._sparks.size() > 10 and not reveal._milestone.is_empty() == false, "after the heat the answer comes with sparks (+1 is no milestone)")
	var press: InputEventKey = InputEventKey.new()
	press.pressed = true
	press.keycode = KEY_E
	Input.parse_input_event(press)
	await _frames(3)
	_check(reveal._closing < 0.0, "the card cannot be closed before the answer has sunk in")
	await _frames(100)
	Input.parse_input_event(press)
	await _frames(3)
	_check(reveal._closing >= 0.0, "afterwards a key closes it")
	await _frames(30)
	_check(not is_instance_valid(reveal) or reveal.is_queued_for_deletion(), "and it goes away")
	# a hard step: the result is decided when it is handed in, a failure keeps the level, adds Glut, and gives iron back
	back["r"] = 8
	back.erase("rp")
	player.inventory.give("void_splinter", 4)
	player.inventory.give("iron_plate", 6)
	player.progress.award(2000, 0)
	var try_block: String = town.refine_block(back, player)
	_check(try_block == "", "+9 can be ordered with trust, material and money (%s)" % try_block)
	(town.residents["torben"] as Dictionary).trust = 10
	_check("TRAUT" in town.refine_block(back, player), "+9 wants Torben's trust 20")
	(town.residents["torben"] as Dictionary).trust = 60
	var seeded: int = 0
	for s: int in 400:
		if not RefineRules.roll(back, 9, s):
			seeded = s
			break
	var stack_slot: int = -1
	for i: int in InventoryComponent.SIZE:
		if String((player.inventory.slots[i] as Dictionary).get("id", "")) == "sword_iron":
			stack_slot = i
	player.inventory.slots[stack_slot] = back
	town.request_refine("inv", stack_slot)
	await _frames(3)
	_check(town.orders.size() == 1, "the +9 attempt is on the anvil")
	_check(town.refine_heat("torben") == 9, "Torben's anvil is hot for a +9 attempt")
	(town.orders[0] as Dictionary).ok = false ## decide the failure (the roll is rolled at the hand-in)
	(town.orders[0] as Dictionary).left = 0.0
	(town.orders[0] as Dictionary).done = true
	var export: Dictionary = town.export_state()
	_check(bool(((export.orders as Array)[0] as Dictionary).has("w")) and int((((export.orders as Array)[0] as Dictionary).w as Dictionary).r) == 8, "the weapon on the anvil is part of the saved town")
	town.import_state(export)
	_check(town.orders.size() == 1 and TownManager.is_refine(town.orders[0] as Dictionary) and Items.refine(town.orders[0].w) == 8 and typeof((town.orders[0].w as Dictionary).r) == TYPE_INT, "and comes back after loading")
	shop._on_town_changed()
	var plates_pre: int = player.inventory.count_item("iron_plate")
	town.request_collect(0)
	await _frames(3)
	var failed: Dictionary = {}
	for i: int in InventoryComponent.SIZE:
		if String((player.inventory.slots[i] as Dictionary).get("id", "")) == "sword_iron":
			failed = player.inventory.slots[i]
	_check(Items.refine(failed) == 8 and int(failed.get("rp", 0)) == 1, "a failure keeps +8 and adds one Glut (%s)" % str(failed))
	_check(answers.size() == 2 and not bool(answers[1][2]) and (answers[1][3] as Dictionary).has("iron_plate") and int(answers[1][1].get("rp", 0)) == 1, "the failure tells the reveal: Glut 1 and the iron that comes back (%s)" % str(answers[1][3]))
	for old: Node in get_tree().get_nodes_in_group("refine_reveal"):
		old.free() ## the failure's card
	var milestone_card: RefineReveal = RefineReveal.present(get_tree(), {"id": "sword_iron", "count": 1, "r": 9}, {"id": "sword_iron", "count": 1, "r": 10}, true, {})
	await _frames(70)
	_check(milestone_card != null and not milestone_card._milestone.is_empty() and String(milestone_card._milestone.name) == "LEERENFEST", "+10 shows its milestone LEERENFEST")
	milestone_card.queue_free()
	await _frames(3)
	town.orders.clear()
	var smith: Settler = town.settler_node("torben") ## the loading of the town built him anew
	var sparks_before: int = smith.get_child_count()
	smith._anvil_sparks(12, {"face": [0, -1]})
	_check(smith.get_child_count() == sparks_before + 1 and town.refine_heat("torben") == 0, "Torben's hammer throws sparks, no heat without an order")
	_check(player.inventory.count_item("iron_plate") == plates_pre + RefineRules.refund(back, 9).get("iron_plate", 0), "half of the iron comes back")
	_check(is_equal_approx(RefineRules.chance(failed), RefineRules.chance({"id": "sword_iron", "count": 1, "r": 8}) + 0.03), "the next attempt is 3 %% likelier")
	# the one at the anvil limits the queue, other things are refused
	player.inventory.slots[stack_slot] = {"id": "sword_basic", "count": 1, "r": 10}
	_check(town.refine_block(player.inventory.slots[stack_slot], player) != "", "a weapon at its cap cannot be refined")
	# a refined weapon is never sold by accident
	for i: int in InventoryComponent.SIZE:
		if String((player.inventory.slots[i] as Dictionary).get("id", "")) == "sword_basic":
			player.inventory.slots[i] = {}
	player.inventory.give("sword_basic", 1, {"r": 5})
	var purse: int = player.progress.copper
	town.request_trade("torben_forge", "sell", "sword_basic", 1)
	await _frames(3)
	_check(player.inventory.count_item("sword_basic") == 1 and player.inventory.count_plain("sword_basic") == 0 and player.progress.copper == purse, "a refined sword is not sold, only plain ones")
	player.inventory.give("sword_basic", 1)
	town.request_trade("torben_forge", "sell", "sword_basic", 2)
	await _frames(3)
	_check(player.inventory.count_item("sword_basic") == 1 and Items.refine(player.inventory.slots[_idx("sword_basic")]) == 5 and player.progress.copper == purse + 30, "a plain sword is, and the refined one stays")
	shop._close()
	await _frames(40)
	# Gustav's bench shows none of it
	var bench: ShopWindow = ShopWindow.open(get_tree(), player, town, "gustav_bench")
	await _frames(10)
	player.request_teleport(town.rect_of(town.built_ids("workshop")[0]).get_center() + Vector2(0, 80))
	await _frames(20)
	bench._rebuild()
	var gustav_ids: Array[String] = []
	for row: Dictionary in bench.rows:
		gustav_ids.append(String(row.recipe))
	_check(not gustav_ids.has("iron_ingot") and not gustav_ids.has("sword_basic") and gustav_ids.has("plank"), "Gustav's bench lists his own recipes only")
	print("SMITHY SHOP: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)
