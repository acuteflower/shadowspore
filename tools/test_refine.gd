extends Node
## Godot --headless --path . tools/test_refine.tscn
## Verfeinern, steps 1 and 2 (docs/refinement_konzept.md): the pure rules of RefineRules (chances, Glut, material ladders by rarity, cost, time, gains, results, seeded roll,
## agreement with tools/sim_refine.py) and the refinement staying on the stack through every inventory operation, a throw, a pick-up and a save.
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


func near(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps


func weapon(id: String, level: int, pity: int = 0) -> Dictionary:
	var s: Dictionary = {"id": id, "count": 1}
	if level > 0:
		s["r"] = level
	if pity > 0:
		s["rp"] = pity
	return s


func _index_of(id: String) -> int:
	for i: int in InventoryComponent.SIZE:
		if String((bag.slots[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func clear() -> void:
	for i: int in InventoryComponent.SIZE:
		bag.slots[i] = {}
	for slot_name: String in bag.equipment:
		bag.equipment[slot_name] = {}
	bag.held = {}


func _run() -> void:
	_rules()
	await _inventory()
	await _combat()
	_tooltip()
	print("DONE failures=", failures)
	get_tree().quit(failures)


func _rules() -> void:
	var basic: Dictionary = weapon("sword_basic", 0)
	var iron: Dictionary = weapon("sword_iron", 0)
	var void_sword: Dictionary = weapon("sword_void", 0)
	check(RefineRules.is_refinable(basic) and RefineRules.is_refinable(iron) and RefineRules.is_refinable(void_sword), "the three swords are refinable")
	check(not RefineRules.is_refinable({"id": "stone", "count": 1}) and not RefineRules.is_refinable({}), "stone and nothing are not")
	check(RefineRules.cap(basic) == 5 and RefineRules.cap(iron) == 10 and RefineRules.cap(void_sword) == 15, "the cap follows the rarity: common +5, uncommon +10, rare and above +15")
	check(RefineRules.can_refine(weapon("sword_basic", 4)) and not RefineRules.can_refine(weapon("sword_basic", 5)) and RefineRules.can_refine(weapon("sword_iron", 9)) and not RefineRules.can_refine(weapon("sword_iron", 10)) and RefineRules.can_refine(weapon("sword_void", 14)) and not RefineRules.can_refine(weapon("sword_void", 15)), "a weapon at its cap cannot be refined")

	# chances: +1..+5 safe, then falling; rarity makes it harder
	var all_safe: bool = true
	for lv: int in range(1, 6):
		all_safe = all_safe and RefineRules.chance(iron, lv) == 1.0 and RefineRules.chance(void_sword, lv) == 1.0
	check(all_safe, "up to +5 nothing can fail, whatever the rarity")
	var straight: bool = true
	for lv: int in range(7, 16):
		straight = straight and near(RefineRules.base_chance(lv - 1) - RefineRules.base_chance(lv), RefineRules.base_chance(6) - RefineRules.base_chance(7), 0.002)
	check(straight and near(RefineRules.base_chance(6), 0.85) and near(RefineRules.base_chance(15), 0.08), "the base chance falls on a straight line from 85 %% at +6 to 8 %% at +15")
	check(near(RefineRules.chance(weapon("sword_iron", 5)), 0.85 * 0.97) and near(RefineRules.chance(weapon("sword_iron", 9)), RefineRules.base_chance(10) * 0.97), "the forged sword is hardly harder than plain steel (97 %% of the line)")
	check(near(RefineRules.chance(weapon("sword_basic", 5)), 0.85) and near(RefineRules.chance(weapon("sword_void", 14)), 0.08 * 0.65) and near(RefineRules.chance(weapon("sword_void", 5)), 0.85 * 0.65), "common stays on the line, the legendary blade falls far below it (%f)" % RefineRules.chance(weapon("sword_void", 14)))
	var ordered: bool = true
	for lv: int in range(6, 16):
		var last: float = 2.0
		for id: String in ["sword_basic", "sword_iron", "sword_void"]:
			var odds: float = RefineRules.chance(weapon(id, 0), lv)
			ordered = ordered and odds <= last + 0.0001
			last = odds
	check(ordered, "the rarer the weapon, the lower the chance at every step")
	check(near(RefineRules.chance(weapon("sword_iron", 5, 3)), 0.85 * 0.97 + 0.09), "three failures at +6 add 9 % Glut")
	check(near(RefineRules.chance(weapon("sword_void", 5, 99)), 0.85 * 0.65 + 0.15) and near(RefineRules.chance(weapon("sword_iron", 5, 9)), 0.95), "Glut is capped at 15 %% (and a chance at 95 %%)")
	check(near(RefineRules.chance(weapon("sword_void", 10, 4)), RefineRules.base_chance(11) * 0.65 + 0.08) and near(RefineRules.chance(weapon("sword_void", 10, 99)), RefineRules.base_chance(11) * 0.65 + 0.12), "at +11 Glut gives 2 % per failure, at most 12 %")
	check(near(RefineRules.chance(weapon("sword_iron", 5, 3), 8), RefineRules.base_chance(8) * 0.97), "Glut only counts for the step the weapon stands before")
	check(RefineRules.pity_bonus(weapon("sword_void", 10, 4)) > 0.079 and RefineRules.pity_bonus(weapon("sword_iron", 2, 5)) == 0.0, "the gold segment of the window")

	# materials: rarity decides the ladder
	check(RefineRules.materials(basic, 1) == {"iron_ingot": 1} and RefineRules.materials(weapon("sword_basic", 4), 5) == {"iron_ingot": 3}, "plain steel is forged from iron ingots")
	check(RefineRules.materials(iron, 1) == RefineRules.materials(basic, 1) and RefineRules.materials(iron, 5) == RefineRules.materials(basic, 5), "the forged sword shares the ladder of plain steel up to +5: the two are close")
	check(RefineRules.materials(iron, 6) == {"iron_plate": 1, "void_splinter": 1} and RefineRules.materials(iron, 10) == {"iron_plate": 3, "void_splinter": 2}, "and goes on with iron plates and a few void splinters: %s" % str(RefineRules.materials(iron, 10)))
	check(RefineRules.materials(weapon("sword_void", 0), 1) == {"shadow_core": 2} and RefineRules.materials(void_sword, 6) == {"void_slag": 1, "shadow_core": 1}, "the legendary blade starts with shadow cores and soon wants slag: %s / %s" % [str(RefineRules.materials(void_sword, 1)), str(RefineRules.materials(void_sword, 6))])
	check(RefineRules.materials(void_sword, 15) == {"void_slag": 1, "shadow_core": 3}, "and ends on slag (few, it is the scarcest loot): %s" % str(RefineRules.materials(void_sword, 15)))
	var pool: Array = ["iron_ingot", "iron_plate", "void_splinter", "shadow_core", "void_slag"]
	var grades_rise: bool = true
	for lv: int in [1, 6, 11]:
		var prev: int = -1
		for id: String in ["sword_basic", "sword_iron", "sword_void"]:
			var main: int = 0
			for item: String in RefineRules.materials(weapon(id, 0), lv):
				main = maxi(main, pool.find(item))
			grades_rise = grades_rise and main >= prev
			prev = main
	check(grades_rise, "at every step the rarer weapon needs the rarer main material")
	var dearer: bool = true
	var longer: bool = true
	for lv: int in range(1, 16):
		dearer = dearer and RefineRules.copper(basic, lv) <= RefineRules.copper(iron, lv) and RefineRules.copper(iron, lv) < RefineRules.copper(void_sword, lv)
		longer = longer and RefineRules.work_seconds(basic, lv) <= RefineRules.work_seconds(iron, lv) and RefineRules.work_seconds(iron, lv) <= RefineRules.work_seconds(void_sword, lv)
	check(dearer and longer, "the rarer the weapon, the dearer and the longer every attempt")
	var rising: bool = true
	for lv: int in range(2, 16):
		rising = rising and RefineRules.copper(iron, lv) > RefineRules.copper(iron, lv - 1)
	var line: bool = true
	for lv: int in range(2, 16):
		line = line and absi((RefineRules.copper(iron, lv) - RefineRules.copper(iron, lv - 1)) - roundi(5.5 * 1.15)) <= 1
	check(rising and line and RefineRules.copper(iron, 1) == 6 and RefineRules.copper(iron, 15) == 95, "copper rises on a straight line (6 .. 95 for the forged sword)")
	check(RefineRules.trust_needed(5) == 0 and RefineRules.trust_needed(6) == 20 and RefineRules.trust_needed(11) == 50, "Torben's trust gates the three tiers")
	check(RefineRules.refund(iron, 6).is_empty() and RefineRules.refund(iron, 9) == {"iron_plate": 1} and RefineRules.refund(iron, 12).is_empty() and RefineRules.refund(iron, 3).is_empty(), "a failed hardening gives half of the iron back, nothing else does: %s" % str(RefineRules.refund(iron, 9)))

	# what a level gives
	check(near(RefineRules.gain(5), 0.25) and near(RefineRules.gain(10), 0.50) and near(RefineRules.gain(15), 0.75), "gain: 5 %% a level, +25 / +50 / +75 %%")
	check(near(Items.stat(weapon("sword_iron", 10), "damage"), 8.0 * 1.5) and near(Items.stat(weapon("sword_iron", 0), "damage"), 8.0), "damage of the forged sword at its cap +10: 12")
	check(near(Items.stat(weapon("sword_void", 15), "damage"), 52.5) and near(Items.stat(weapon("sword_basic", 5), "damage"), 5.0 * 1.25), "damage of the legendary blade 52.5, of plain steel at its cap +5 6.25")
	check(near(Items.stat(weapon("sword_iron", 4), "reach"), 30.0) and near(Items.stat(weapon("sword_iron", 5), "reach"), 31.0) and near(Items.stat(weapon("sword_iron", 15), "reach"), 33.0), "reach: +1 at +5, +10, +15")
	check(near(Items.stat(weapon("sword_void", 14), "speed"), 1.15) and near(Items.stat(weapon("sword_void", 15), "speed"), 1.15 * 1.05), "speed only at +15")
	check(near(Items.stat(weapon("sword_iron", 10), "knockback"), 50.0 * (1.0 + 0.5 * 0.5)), "knockback follows half of the gain")
	check(Items.stat({"id": "stone", "count": 1}, "damage", 3.0) == 3.0, "an item without that stat gives the fallback")
	check(Items.title(weapon("sword_iron", 7)) == "Geschmiedetes Schwert +7" and Items.title(iron) == "Geschmiedetes Schwert", "the name carries the level")
	check(Items.stat(weapon("sword_basic", 5), "damage") < Items.stat(iron, "damage"), "plain steel at its cap (6.25) stays below a new forged sword (8)")

	# results and the roll
	var up: Dictionary = RefineRules.result(weapon("sword_iron", 6, 3), true)
	check(Items.refine(up) == 7 and not up.has("rp") and int(up.count) == 1, "a success is one level more and the Glut is gone")
	var down: Dictionary = RefineRules.result(weapon("sword_iron", 6, 3), false)
	check(Items.refine(down) == 6 and int(down.rp) == 4, "a failure keeps the level and adds a piece of Glut")
	check(Items.refine(RefineRules.result(weapon("sword_basic", 5), true)) == 5 and Items.refine(RefineRules.result(weapon("sword_iron", 10), true)) == 10, "the cap holds")
	check(RefineRules.roll(weapon("sword_iron", 2), 3, 7) and RefineRules.roll(weapon("sword_iron", 2), 3, 8), "a safe step always succeeds")
	var same: bool = true
	for s: int in 200:
		same = same and RefineRules.roll(weapon("sword_iron", 10), 11, s) == RefineRules.roll(weapon("sword_iron", 10), 11, s)
	check(same, "the same seed gives the same answer")
	var wins: int = 0
	for s: int in 10000:
		wins += 1 if RefineRules.roll(weapon("sword_iron", 10), 11, s * 7919 + 13) else 0
	var wanted: float = RefineRules.chance(weapon("sword_iron", 10), 11)
	check(absf(float(wins) / 10000.0 - wanted) < 0.02, "the seeded roll hits the chance (%f -> %f)" % [wanted, float(wins) / 10000.0])
	check(RefineRules.verdict(0.9) == 0 and RefineRules.verdict(0.5) == 1 and RefineRules.verdict(0.2) == 2, "Torben's verdict: good, risky, bad")

	# agreement with tools/sim_refine.py (forged sword, +0 to its cap +10: 12.6 attempts on average)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242
	var total: int = 0
	var runs: int = 3000
	for r: int in runs:
		var s: Dictionary = weapon("sword_iron", 0)
		while RefineRules.can_refine(s):
			total += 1
			s = RefineRules.result(s, RefineRules.roll(s, RefineRules.next_level(s), rng.randi()))
	check(absf(float(total) / float(runs) - 12.6) < 0.8, "the Monte Carlo of the rules agrees with sim_refine.py (%.1f attempts to +10)" % (float(total) / float(runs)))


func _inventory() -> void:
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var hero: Player = world._players.get_child(0) as Player
	bag = hero.inventory
	drops = get_tree().get_first_node_in_group("drops")
	check(hero != null and drops != null and bag != null, "there is a player, a bag and a drops container")
	var hb: int = InventoryComponent.HOTBAR_SIZE
	var refined: Dictionary = weapon("sword_iron", 7, 2)

	clear()
	bag.slots[hb] = refined.duplicate()
	bag.request("click", ["inv", hb])
	check(Items.refine(bag.held) == 7 and int(bag.held.rp) == 2, "LMB takes the weapon with its level")
	bag.request("click", ["inv", hb + 3])
	check(bag.slots[hb + 3] == refined and bag.held.is_empty(), "and puts it down with its level")
	bag.slots[hb + 4] = weapon("sword_iron", 0)
	bag.request("click", ["inv", hb + 3])
	bag.request("click", ["inv", hb + 4])
	check(bag.held == weapon("sword_iron", 0) and bag.slots[hb + 4] == refined, "a swap keeps both weapons as they were")
	bag.request("click", ["inv", hb + 5])
	check(bag.slots[hb + 5] == weapon("sword_iron", 0), "the plain one goes down unchanged")

	clear()
	bag.slots[hb + 1] = refined.duplicate()
	bag.request("equip", [hb + 1, ""])
	check(bag.equipment["main_hand"] == refined and (bag.slots[hb + 1] as Dictionary).is_empty(), "equipping keeps the level")
	check(Items.refine(bag.active_stack()) == 7, "the weapon in her hand is the refined one")
	bag.request("unequip", ["main_hand", hb + 2])
	check(bag.slots[hb + 2] == refined and (bag.equipment["main_hand"] as Dictionary).is_empty(), "taking it off keeps the level")
	bag.request("quick", ["inv", hb + 2])
	check(bag.equipment["main_hand"] == refined, "shift-click to the hand keeps it")
	bag.request("quick", ["equip", "main_hand"])
	var at: int = _index_of("sword_iron")
	check(at >= hb and bag.slots[at] == refined, "shift-click back keeps it")
	bag.request("rclick", ["inv", at])
	check(bag.equipment["main_hand"] == refined, "a right click equips it with the level")
	bag.request("rclick", ["equip", "main_hand"])
	at = _index_of("sword_iron")
	check(at >= hb and bag.slots[at] == refined, "and takes it off with the level")
	bag.request("click", ["inv", at])
	bag.request("rclick", ["inv", hb + 6]) ## the full hand puts ONE piece down: the single weapon is its own piece
	check(bag.slots[hb + 6] == refined and bag.held.is_empty(), "RMB with a full hand puts the single weapon down with its level")

	# sorting and merging
	clear()
	bag.slots[hb + 9] = weapon("sword_iron", 7, 2)
	bag.slots[hb + 3] = weapon("sword_iron", 0)
	bag.slots[hb + 5] = weapon("sword_iron", 12)
	bag.slots[hb + 7] = {"id": "stone", "count": 5}
	bag.request("sort", [0])
	var levels: Array[int] = []
	for i: int in range(hb, InventoryComponent.SIZE):
		if String((bag.slots[i] as Dictionary).get("id", "")) == "sword_iron":
			levels.append(Items.refine(bag.slots[i]))
	levels.sort()
	check(levels == [0, 7, 12], "sorting keeps three separate weapons with their own levels (%s)" % str(levels))

	# add_item / give: a refined stack is its own piece; remove_item gives up the plain one first
	clear()
	bag.slots[hb] = weapon("sword_basic", 0)
	check(bag.give("sword_basic", 1, {"r": 4}) == 0, "give with a level finds a free slot")
	var found: int = 0
	for i: int in InventoryComponent.SIZE:
		var s2: Dictionary = bag.slots[i]
		if String(s2.get("id", "")) == "sword_basic":
			found += 1
	check(found == 2 and bag.count_item("sword_basic") == 2, "it did not merge into the plain sword")
	check(bag.remove_item("sword_basic", 1), "one plain sword is taken ...")
	var left: Dictionary = {}
	for i: int in InventoryComponent.SIZE:
		if String((bag.slots[i] as Dictionary).get("id", "")) == "sword_basic":
			left = bag.slots[i]
	check(Items.refine(left) == 4, "... and the refined one stays")
	check(bag.has_room("sword_iron") and bag.add_item("stone", 3) == 0 and bag.count_item("stone") == 3, "plain stacks are unaffected")

	# throw, pick up
	clear()
	bag.slots[hb + 2] = refined.duplicate()
	var before: int = drops.get_child_count()
	bag.request("dropslot", ["inv", hb + 2, false])
	check(drops.get_child_count() == before + 1 and (bag.slots[hb + 2] as Dictionary).is_empty(), "the refined weapon is thrown out")
	var drop: ItemDrop = drops.get_child(drops.get_child_count() - 1) as ItemDrop
	check(drop.item_id == "sword_iron" and drop.refine == 7 and drop.refine_pity == 2, "the drop carries level and Glut (%d / %d)" % [drop.refine, drop.refine_pity])
	check(drop._label == "Geschmiedetes Schwert +7", "and shows it in its label (%s)" % drop._label)
	var twin: ItemDrop = (load("res://src/entities/drops/item_drop.tscn") as PackedScene).instantiate() as ItemDrop
	twin.item_id = "sword_iron"
	twin.count = 1
	drops.add_child(twin)
	drop._landed = true
	twin._landed = true
	twin.global_position = drop.global_position
	check(not drop._try_merge() and not twin._try_merge(), "a refined weapon and a plain one never merge")
	drop._collect(hero)
	var back: Dictionary = {}
	for i: int in InventoryComponent.SIZE:
		if String((bag.slots[i] as Dictionary).get("id", "")) == "sword_iron":
			back = bag.slots[i]
	check(back == refined, "picking it up gives the weapon back as it was (%s)" % str(back))
	twin.queue_free()

	# the cursor stack goes back into the bag (stow)
	clear()
	bag.held = refined.duplicate()
	bag.request("stow", [0])
	var stowed: Dictionary = {}
	for i: int in InventoryComponent.SIZE:
		if String((bag.slots[i] as Dictionary).get("id", "")) == "sword_iron":
			stowed = bag.slots[i]
	check(stowed == refined and bag.held.is_empty(), "stowing the cursor stack keeps the level")

	# the save
	var text: String = JSON.stringify({"slots": [refined], "equipment": {"main_hand": refined}})
	var parsed: Dictionary = JSON.parse_string(text) as Dictionary
	var restored: Dictionary = SaveGame._stack((parsed.slots as Array)[0])
	check(restored == refined and typeof(restored.r) == TYPE_INT and typeof(restored.rp) == TYPE_INT, "a saved and loaded stack is the same (level and Glut are ints again)")
	SaveGame._restore_stacks(bag, parsed)
	check(bag.equipment["main_hand"] == refined and bag.slots[0] == refined, "loading puts the equipped weapon back with its level")


## A dummy with a hurtbox `distance` px in front of the hero (the fan starts at her body centre).
func _dummy(hero: Player, distance: float) -> HealthComponent:
	var holder: Node2D = Node2D.new()
	holder.process_mode = Node.PROCESS_MODE_ALWAYS ## the world of this test is switched off, the dummy's hurtbox must stay in the physics space
	holder.global_position = hero.global_position + AttackComponent.BODY_CENTER + Vector2(distance, 0)
	var health: HealthComponent = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 1000.0
	holder.add_child(health)
	var hurtbox: HurtboxComponent = HurtboxComponent.new()
	hurtbox.collision_layer = AttackComponent.HURTBOX_MASK
	hurtbox.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 1.0
	shape.shape = circle
	hurtbox.add_child(shape)
	holder.add_child(hurtbox)
	get_tree().get_first_node_in_group("world").add_child(holder)
	return health


func _combat() -> void:
	var world: Node = get_tree().get_first_node_in_group("world")
	var hero: Player = (world as WorldLevel)._players.get_child(0) as Player
	var attack: AttackComponent = hero.attack
	var plain: Dictionary = weapon("sword_iron", 0)
	var best: Dictionary = weapon("sword_iron", 15)
	var step_plain: Dictionary = attack._step_data(plain, 0)
	var step_best: Dictionary = attack._step_data(best, 0)
	check(near(float(step_best.windup), float(step_plain.windup) / 1.05, 0.0001), "at +15 the swing is 5 %% quicker (%f / %f)" % [float(step_best.windup), float(step_plain.windup)])
	check(attack._stack_of("sword_iron", 15) == {"id": "sword_iron", "count": 1, "r": 15} and attack._stack_of("sword_iron", 0) == plain, "peers rebuild the stack from item id and level")
	var near_dummy: HealthComponent = _dummy(hero, 12.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	attack._hit_scan(Vector2.RIGHT, step_plain, plain)
	var damage_plain: float = 1000.0 - near_dummy.current
	near_dummy.current = 1000.0
	attack._hit_scan(Vector2.RIGHT, step_plain, best)
	var damage_best: float = 1000.0 - near_dummy.current
	check(damage_plain > 0.0 and near(damage_plain, 8.0 * float(step_plain.damage), 0.01), "a plain forged sword hits for 8 x the step (%f)" % damage_plain)
	check(near(damage_best, damage_plain * 1.75, 0.01), "at +15 it hits 1.75 times as hard (%f)" % damage_best)
	var far_dummy: HealthComponent = _dummy(hero, 30.0 * float(step_plain.reach) + 1.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	attack._hit_scan(Vector2.RIGHT, step_plain, plain)
	check(far_dummy.current == 1000.0, "a target just beyond the plain reach is missed")
	attack._hit_scan(Vector2.RIGHT, step_plain, best)
	check(far_dummy.current < 1000.0, "the +3 px of reach at +15 reach it")
	# the owner's synced level reaches the attack component
	hero.inventory.slots[InventoryComponent.HOTBAR_SIZE] = weapon("sword_iron", 7)
	hero.inventory.request("equip", [InventoryComponent.HOTBAR_SIZE, ""])
	check(attack.held_weapon == "sword_iron" and attack.held_refine == 7, "the equipped weapon's level is what the hand shows (%d)" % attack.held_refine)
	check(hero.inventory.debug_set_refine(15) and Items.refine(hero.inventory.active_stack()) == 10 and attack.held_refine == 10, "the dev cheat WAFFE +15 sets the forged sword to its cap +10")
	check(hero.inventory.debug_set_refine(0) and Items.refine(hero.inventory.active_stack()) == 0 and attack.held_refine == 0, "and +0 takes it away again")
	hero.inventory.equipment["main_hand"] = weapon("sword_basic", 0)
	check(hero.inventory.debug_set_refine(15) and Items.refine(hero.inventory.active_stack()) == 5, "plain steel stops at its cap +5")
	hero.inventory.equipment["main_hand"] = {}
	check(not hero.inventory.debug_set_refine(5), "nothing in the hand: nothing to refine")


func _tooltip() -> void:
	var tip: ItemTooltip = ItemTooltip.new()
	add_child(tip)
	tip.show_stack(weapon("sword_iron", 7), false)
	var kinds: Array[String] = []
	for row: Dictionary in tip._rows:
		kinds.append(String(row.type))
	check(int(tip._rows[0].refine) == 7 and kinds.has("refine"), "the card has the +7 and the pearl row")
	var refine_row: Dictionary = tip._rows[kinds.find("refine")]
	check(int(refine_row.level) == 7 and int(refine_row.cap) == 10 and String(refine_row.text) == "7/10", "the pearls say 7/10")
	var damage_row: Dictionary = {}
	var reach_row: Dictionary = {}
	for row: Dictionary in tip._rows:
		if String(row.type) == "stat" and String(row.text) == "Schaden":
			damage_row = row
		if String(row.type) == "stat" and String(row.text) == "Reichweite":
			reach_row = row
	check(String(damage_row.value) == "10.8" and String(damage_row.bonus) == "+2.8", "damage shows 10.8 (+2.8): %s %s" % [damage_row.value, damage_row.bonus])
	check(String(reach_row.value) == "31" and String(reach_row.bonus) == "+1", "reach shows 31 (+1)")
	var reached: int = 0
	var open: int = 0
	for row: Dictionary in tip._rows:
		if String(row.type) == "mile":
			if bool(row.on):
				reached += 1
			else:
				open += 1
	check(reached == 1 and open == 1, "one milestone reached (+5), +10 dim, +15 not offered to a weapon that stops at +10 (%d / %d)" % [reached, open])
	tip.show_stack(weapon("sword_iron", 0), false)
	var plain_bonus: bool = false
	for row: Dictionary in tip._rows:
		plain_bonus = plain_bonus or (String(row.type) == "stat" and String(row.bonus) != "")
	check(not plain_bonus and tip.size.x > 0.0, "a plain weapon shows no bonus, but the empty pearls")
	tip.show_stack(weapon("sword_basic", 5), false)
	var milestones_basic: int = 0
	for row: Dictionary in tip._rows:
		milestones_basic += 1 if String(row.type) == "mile" else 0
	check(milestones_basic == 1, "plain steel shows only the milestone it can reach (+5)")
	tip.show_stack({"id": "stone", "count": 3}, false)
	var has_refine: bool = false
	for row: Dictionary in tip._rows:
		has_refine = has_refine or String(row.type) in ["refine", "mile"]
	check(not has_refine, "stone has no refinement rows")
	check(RefineStyle.pearls_width() == 63 and RefineStyle.color(3) == RefineStyle.STEEL and RefineStyle.color(8) == RefineStyle.TEAL and RefineStyle.color(12) == RefineStyle.GOLD, "pearl row width and tier colours")
	tip.queue_free()
