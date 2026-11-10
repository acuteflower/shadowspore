extends Node
## Godot --headless --path . --fixed-fps 60 tools/test_rissklinge.tscn
## Das Himmelsriss (docs/rissklinge.md): Daten (Klasse, Item, Rezept, Dateien), die Regeln des Rechtsklicks (zwei diagonale Hiebe, `HeavyRules.rift_step`), die
## Kette (erster Hieb, zweiter Hieb im Fenster, vorgemerkter Druck), Schaden von Klinge und Federsalve gegen echte Hurtboxen, der Spitzenriss des Stoßes, der
## Federbund mit der Rissfeder, die Effekte (RiftFx, FeatherVolley) und die Karte.
var failures: int = 0
var world: WorldLevel
var hero: Player
var bag: InventoryComponent
var stack: Dictionary = {"id": "sword_rift", "count": 1}


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func _run() -> void:
	_data()
	_rules()
	world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	hero = world._players.get_child(0) as Player
	bag = hero.inventory
	check(hero != null and bag != null, "there is a hero with a bag")
	await _combat()
	await _chain()
	await _bond()
	await _fx_and_card()
	print("DONE failures=", failures)
	get_tree().quit(failures)


# ---------------------------------------------------------------- data and files
func _data() -> void:
	var def: Dictionary = DataRegistry.get_entry("items", "sword_rift")
	check(not def.is_empty() and String(def.get("rarity")) == "legendary" and String(def.get("weapon_class")) == "sword_rift" and String(def.get("slot")) == "main_hand", "the Himmelsriss is a legendary main-hand sword of its own class")
	var stats: Dictionary = def.get("stats", {}) as Dictionary
	var void_stats: Dictionary = (DataRegistry.get_entry("items", "sword_void").get("stats", {}) as Dictionary)
	check(float(stats["damage"]) > float(void_stats["damage"]) and float(stats["reach"]) > float(void_stats["reach"]), "it is stronger than the Leerenklinge (%s)" % str(stats))
	check(bool(def.get("refinable", false)) and int(def.get("enchant_slots", 0)) >= 3, "refinable, three enchant slots")
	for key: String in ["icon", "held"]:
		check(ResourceLoader.exists(String(def[key])), "%s exists" % key)
	check(ResourceLoader.exists(String(def["held"]).replace("_held.png", "_held_rot.png")), "the pre-rotated sheet exists")
	for sound: String in ["swing", "line", "volley"]:
		check(ResourceLoader.exists(String((def.get("fx", {}) as Dictionary).get("sounds", "")) + sound + ".wav"), "sound %s exists" % sound)
	check((def.get("specials", []) as Array).size() == 4, "four specials are listed for the card")
	var cls: Dictionary = DataRegistry.get_entry("weapon_classes", "sword_rift")
	var base: Dictionary = DataRegistry.get_entry("weapon_classes", "sword_1h")
	check((cls["combo"] as Array).size() == (base["combo"] as Array).size(), "the same combo as the sword, with the same upgrade steps")
	check(String(((cls["combo"] as Array)[2] as Dictionary).get("rift", "")) == "line" and String(((base["combo"] as Array)[2] as Dictionary).get("rift", "")) == "", "only the Himmelsriss's thrust throws a lane")
	var recipe: Dictionary = DataRegistry.get_entry("recipes", "sword_rift")
	check(String(recipe.get("npc")) == "torben" and String(recipe.get("by")) == "npc" and int((recipe["in"] as Dictionary).get("rissfeder", 0)) == 1 and (recipe["out"] as Dictionary).has("sword_rift"), "Torben forges it from one Rissfeder (%s)" % str(recipe.get("in")))
	check(int(recipe.get("trust", 0)) > int(DataRegistry.get_entry("recipes", "sword_iron").get("trust", 0)), "it needs more of his trust than the forged sword")


# ---------------------------------------------------------------- the pure rules
func _rules() -> void:
	var item: Dictionary = DataRegistry.get_entry("items", "sword_rift")
	var cfg: Dictionary = HeavyRules.config(item)
	check(HeavyRules.is_rift_slash(cfg) and not HeavyRules.has_secondary(item) and HeavyRules.rift_steps(cfg) == 2, "its right click is a chain of two slashes, no charge")
	var iron: Dictionary = DataRegistry.get_entry("items", "sword_iron")
	check(HeavyRules.has_secondary(iron) and not HeavyRules.is_rift_slash(HeavyRules.config(iron)), "the plain sword keeps its charged blow")
	check(HeavyRules.rift_cost(cfg, 1) == 20.0 and HeavyRules.rift_cost(cfg, 2) == 15.0 and near(HeavyRules.rift_window(cfg), 0.6), "stamina 20 and 15, a window of 0.6 s")
	var one: Dictionary = HeavyRules.rift_step(cfg, item, 1)
	var two: Dictionary = HeavyRules.rift_step(cfg, item, 2)
	check(int(one["stage"]) == 1 and int(two["stage"]) == 2 and String(one["name"]) == "RISSSCHNITT" and String(two["name"]) == "HIMMELSKREUZ", "the steps are named")
	check(float(one["sweep"]) == -float(two["sweep"]), "the two slashes come from opposite sides")
	var d1: Dictionary = one["diag"] as Dictionary
	var d2: Dictionary = two["diag"] as Dictionary
	check(float(d1["pitch0"]) > float(d1["pitch1"]) and float(d2["pitch0"]) > float(d2["pitch1"]), "both cut from high to low")
	check(float(d1["yaw0"]) > 0.0 and float(d1["yaw1"]) < 0.0 and float(d2["yaw0"]) < 0.0 and float(d2["yaw1"]) > 0.0, "and cross each other like an X")
	check(float(two["damage"]) > float(one["damage"]) and int((two["volley"] as Dictionary)["count"]) > int((one["volley"] as Dictionary)["count"]) and float((two["volley"] as Dictionary)["spread"]) > float((one["volley"] as Dictionary)["spread"]), "the second slash is stronger and fans wider")
	check(not bool(one.get("heavy", false)) and bool(one["alt"]) and not one.has("rift_stage"), "it is an ordinary swing step, not a heavy blow")
	var slow: Dictionary = HeavyRules.rift_step(cfg, {"stats": {"speed": 1.0}}, 1)
	var fast: Dictionary = HeavyRules.rift_step(cfg, {"stats": {"speed": 2.0}}, 1)
	check(near(float(fast["windup"]) * 2.0, float(slow["windup"]), 0.0001) and float(fast["recovery"]) < float(slow["recovery"]), "its times follow the weapon's speed")
	check(HeavyRules.rift_step(HeavyRules.config(iron), iron, 1).is_empty(), "a weapon without the chain has no steps")
	var passive: Dictionary = HeavyRules.rift_data(cfg, "passive")
	check(int(passive["length"]) == 72 and near(float(passive["ratio"]), 0.45), "the thrust's lane is 72 px and 45 %%")
	# the card's numbers are the data's numbers
	var text: String = ""
	for special: Variant in item["specials"] as Array:
		text += String((special as Dictionary)["text"]) + "\n"
	var v1: Dictionary = one["volley"] as Dictionary
	var v2: Dictionary = two["volley"] as Dictionary
	for needle: String in ["72 Pixel", "%d leuchtende Rissfedern" % int(v1["count"]), "%d Pixel weit (je %d %%" % [int(v1["length"]), roundi(float(v1["ratio"]) * 100.0)], "%d leuchtende Federn" % int(v2["count"]), "%d Pixel weit (je %d %%" % [int(v2["length"]), roundi(float(v2["ratio"]) * 100.0)], "um %d s" % int(v2["ward_refund"]), "höchstens %d s" % int(v2["ward_cap"]), "bis zu %d" % int(v1["max_hits"])]:
		check(text.contains(needle), "the card text says '%s'" % needle)


# ---------------------------------------------------------------- a dummy to cut
func _dummy(offset: Vector2) -> HealthComponent:
	var holder: Node2D = Node2D.new()
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	holder.global_position = hero.global_position + AttackComponent.BODY_CENTER + offset
	holder.add_to_group("rift_test_dummy")
	var health: HealthComponent = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100000.0
	holder.add_child(health)
	var hurtbox: HurtboxComponent = HurtboxComponent.new()
	hurtbox.collision_layer = AttackComponent.HURTBOX_MASK
	hurtbox.collision_mask = 0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 2.0
	shape.shape = circle
	hurtbox.add_child(shape)
	holder.add_child(hurtbox)
	world.add_child(holder)
	health.current = health.max_health
	return health


func _lost(health: HealthComponent) -> float:
	var lost: float = health.max_health - health.current
	health.current = health.max_health
	return lost


func _clear_dummies() -> void:
	for node: Node in get_tree().get_nodes_in_group("rift_test_dummy"):
		node.free()


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _combat() -> void:
	bag.clear_all()
	bag.give("sword_rift", 1)
	for i: int in InventoryComponent.SIZE:
		if String((bag.slots[i] as Dictionary).get("id", "")) == "sword_rift":
			bag.request("equip", [i, ""])
	check(String(bag.active_stack().get("id", "")) == "sword_rift", "she holds the Himmelsriss")
	hero.attack.held_weapon = "sword_rift"
	var unit: float = float(DataRegistry.get_entry("items", "sword_rift")["stats"]["damage"])
	var one: Dictionary = hero.attack._alt_step(stack, 1)
	var two: Dictionary = hero.attack._alt_step(stack, 2)
	var v1: Dictionary = one["volley"] as Dictionary
	var v2: Dictionary = two["volley"] as Dictionary
	var tip: float = float(DataRegistry.get_entry("items", "sword_rift")["stats"]["reach"]) * float(one["reach"]) * 0.8 ## where the feathers start

	# stage 1
	var near_one: HealthComponent = _dummy(Vector2(20, 0)) ## inside the blade's reach
	var close_one: HealthComponent = _dummy(Vector2(tip + 13.0, 0)) ## just beyond the blade: the fan is still narrow here
	var far_one: HealthComponent = _dummy(Vector2(tip + 60.0, 0)) ## in the feathers' reach
	var out_one: HealthComponent = _dummy(Vector2(tip + 150.0, 0)) ## beyond it
	var wide_one: HealthComponent = _dummy(Vector2(55, 18)) ## 39 degrees off the aim: only the second fan reaches it
	var behind_one: HealthComponent = _dummy(Vector2(-60, 0))
	await _settle()
	hero.attack._hit_scan(Vector2.RIGHT, one, stack)
	var blade: float = _lost(near_one)
	check(near(blade, unit * float(one["damage"]), 0.5), "the first slash cuts the near one for 150 %% of the weapon's damage (%f)" % blade)
	var shotgun: float = _lost(close_one)
	check(near(shotgun, unit * float(v1["ratio"]) * float(v1["max_hits"]), 0.5), "right beyond the blade the fan is a shotgun: capped at %d feathers (%f)" % [int(v1["max_hits"]), shotgun])
	var far_hit: float = _lost(far_one)
	var one_feather: float = unit * float(v1["ratio"])
	check(far_hit > 0.0 and far_hit <= one_feather * float(v1["max_hits"]) + 0.5 and near(fmod(far_hit, one_feather), 0.0, 0.5), "farther out it is whole feathers (%f)" % far_hit)
	check(_lost(out_one) == 0.0 and _lost(wide_one) == 0.0 and _lost(behind_one) == 0.0, "nothing beyond the reach, outside the narrow fan or behind her is hit")

	# stage 2
	hero.attack._hit_scan(Vector2.RIGHT, two, stack)
	check(near(_lost(near_one), unit * float(two["damage"]), 0.5), "the second slash cuts deeper (%f)" % (unit * float(two["damage"])))
	check(_lost(wide_one) > 0.0, "its wider fan reaches the one at 39 degrees")
	check(_lost(far_one) > 0.0 and _lost(out_one) == 0.0, "and flies %d px, not more" % int(v2["length"]))
	var out_two: HealthComponent = _dummy(Vector2(tip + 100.0, 0)) ## between the two lengths
	await _settle()
	hero.attack._hit_scan(Vector2.RIGHT, one, stack)
	check(_lost(out_two) == 0.0, "the first slash's feathers do not reach 100 px ...")
	hero.attack._hit_scan(Vector2.RIGHT, two, stack)
	check(_lost(out_two) > 0.0, "... the second slash's do")
	_clear_dummies()

	# the thrust of the combo: a short lane, the other steps none
	var thrust: Dictionary = hero.attack._step_data(stack, 2)
	var slash: Dictionary = hero.attack._step_data(stack, 0)
	check(String(thrust["rift"]) == "line" and String(slash["rift"]) == "", "the third combo step carries the lane, the first does not")
	var lane_one: HealthComponent = _dummy(Vector2(60, 0)) ## inside the passive's 72, beyond the thrust's reach
	var stab_one: HealthComponent = _dummy(Vector2(15, 0))
	await _settle()
	hero.attack._hit_scan(Vector2.RIGHT, slash, stack)
	_lost(stab_one)
	check(_lost(lane_one) == 0.0, "a slash of the combo throws no lane")
	hero.attack._hit_scan(Vector2.RIGHT, thrust, stack)
	var thrust_cut: float = _lost(stab_one)
	var spit: float = _lost(lane_one)
	check(thrust_cut > 0.0 and near(spit, unit * 0.45, 0.5), "the thrust cuts the near one and its lane hits the one at 60 px for 45 %% of the weapon's damage (%f, %f)" % [thrust_cut, spit])
	_clear_dummies()
	await get_tree().process_frame


# ---------------------------------------------------------------- the chain of the two slashes
func _chain() -> void:
	var attack: AttackComponent = hero.attack
	var cfg: Dictionary = HeavyRules.config(DataRegistry.get_entry("items", "sword_rift"))
	hero.stamina.current = hero.stamina.max_stamina
	check(attack.can_alt() and not attack.can_charge(), "she may start a slash, and there is nothing to charge")
	attack._phase = AttackComponent.Phase.IDLE
	attack._alt_stage = 0
	attack.alt_press(Vector2.RIGHT)
	check(attack.is_swinging() and int(attack._step.get("stage", 0)) == 1 and attack._alt_stage == 1, "the first right click starts the first slash")
	check(near(hero.stamina.current, hero.stamina.max_stamina - HeavyRules.rift_cost(cfg, 1), 0.01), "and costs 20 stamina")
	check(attack._is_diag() and attack.animation_state().x == 0.0 and not attack.is_heavy_swing(), "the body plays the forehand, the blade follows its diagonal")
	attack._advance(5.0) ## windup, active, recovery in one go: the chain waits for the second
	attack._advance(5.0)
	attack._advance(5.0)
	check(not attack.is_swinging(), "the first slash is over")
	check(attack._alt_deadline_msec > Time.get_ticks_msec(), "its window for the second one is open")
	attack.alt_press(Vector2.RIGHT)
	check(attack.is_swinging() and int(attack._step.get("stage", 0)) == 2 and attack.animation_state().x == 1.0, "a second click inside it makes the second slash, the backhand")
	check(near(hero.stamina.current, hero.stamina.max_stamina - 35.0, 0.01), "that one costs 15")
	for k: int in 3:
		attack._advance(5.0)
	attack.alt_press(Vector2.RIGHT)
	check(int(attack._step.get("stage", 0)) == 1, "after the second the chain starts over with the first")
	for k: int in 3:
		attack._advance(5.0)
	attack._alt_deadline_msec = Time.get_ticks_msec() - 1
	attack.alt_press(Vector2.RIGHT)
	check(int(attack._step.get("stage", 0)) == 1, "a second click after the window starts the first slash again")
	# a click during the first slash's recovery waits and starts the second one by itself
	for k: int in 3:
		attack._advance(5.0)
	attack._alt_stage = 0
	hero.stamina.current = hero.stamina.max_stamina ## (the earlier slashes used it up; nothing regenerates in this paused world)
	attack.alt_press(Vector2.RIGHT)
	attack._advance(float(attack._step["windup"]) + 0.001)
	attack._advance(float(attack._step["active"]) + 0.001)
	check(attack._phase == AttackComponent.Phase.RECOVERY, "in the recovery of the first slash ...")
	attack.alt_press(Vector2.RIGHT)
	check(int(attack._step.get("stage", 0)) == 1, "... a click does not interrupt it ...")
	attack._advance(float(attack._step["recovery"]) + 0.001)
	check(attack.is_swinging() and int(attack._step.get("stage", 0)) == 2, "... but is kept and makes the second slash when it ends")
	for k: int in 3:
		attack._advance(5.0)
	# without stamina nothing starts
	hero.stamina.current = 5.0
	attack._alt_stage = 0
	check(not attack.can_alt(), "with 5 stamina she cannot start")
	attack.alt_press(Vector2.RIGHT)
	check(not attack.is_swinging(), "and a click does nothing")
	hero.stamina.current = hero.stamina.max_stamina
	# the plain sword's right click is not a chain
	attack.held_weapon = "sword_iron"
	check(not attack.can_alt(), "a plain sword has no chain")
	attack.alt_press(Vector2.RIGHT)
	check(not attack.is_swinging(), "and a click does not swing it")
	attack.held_weapon = "sword_rift"
	attack._step = {}
	await get_tree().process_frame


# ---------------------------------------------------------------- the Federbund
func _bond() -> void:
	var def: Dictionary = DataRegistry.get_entry("items", "sword_rift")
	var two: Dictionary = hero.attack._alt_step(stack, 2)
	var one: Dictionary = hero.attack._alt_step(stack, 1)
	var v2: Dictionary = two["volley"] as Dictionary
	hero.progress.claimed = 5 ## the first talisman slot opens at level 5
	bag.give("rissfeder", 1)
	for i: int in InventoryComponent.SIZE:
		if String((bag.slots[i] as Dictionary).get("id", "")) == "rissfeder":
			bag.request("equip", [i, ""])
	check(hero.talismans.perks.has("ward"), "the Rissfeder is worn")
	var reach: float = float(def["stats"]["reach"]) * float(two["reach"]) * 0.8
	var targets: Array[HealthComponent] = []
	for k: int in 5:
		targets.append(_dummy(Vector2(reach + 25.0, -12.0 + 6.0 * k)))
	await _settle()
	hero.talismans._ward_left = 100.0
	hero.attack._hit_scan(Vector2.RIGHT, one, stack)
	check(hero.talismans._ward_left == 100.0, "the first slash shortens nothing")
	hero.attack._hit_scan(Vector2.RIGHT, two, stack)
	check(near(hero.talismans._ward_left, 100.0 - float(v2["ward_cap"]), 0.01), "five enemies shorten the pause by the cap, 32 s (%f left of 100)" % hero.talismans._ward_left)
	_clear_dummies()
	var lone: HealthComponent = _dummy(Vector2(reach + 25.0, 0))
	await _settle()
	hero.talismans._ward_left = 100.0
	hero.attack._hit_scan(Vector2.RIGHT, two, stack)
	check(near(hero.talismans._ward_left, 100.0 - float(v2["ward_refund"]), 0.01), "one enemy shortens it by 8 s (%f)" % hero.talismans._ward_left)
	hero.talismans._ward_left = 0.0
	hero.attack._hit_scan(Vector2.RIGHT, two, stack)
	check(hero.talismans._ward_left == 0.0, "a ready wing beat is not touched")
	check(lone.current < lone.max_health, "(the feathers did hit)")
	# without the feather there is no bond
	for slot_name: String in bag.equipment:
		if String((bag.equipment[slot_name] as Dictionary).get("id", "")) == "rissfeder":
			bag.request("unequip", [slot_name, -1])
	hero.talismans._ward_left = 100.0
	hero.attack._hit_scan(Vector2.RIGHT, two, stack)
	check(hero.talismans._ward_left >= 99.0 or not hero.talismans.perks.has("ward"), "without the feather the slash shortens nothing")
	_clear_dummies()


# ---------------------------------------------------------------- how it looks
func _fx_and_card() -> void:
	var holder: Node2D = Node2D.new()
	add_child(holder)
	RiftFx.lane(holder, Vector2(100, 100), Vector2.RIGHT, 72.0, 0.45)
	FeatherVolley.shoot(holder, Vector2(100, 100), Vector2.RIGHT, 5, 0.7, 430.0, PackedFloat32Array([90.0, 90.0, 40.0, 90.0, 90.0]))
	check(holder.get_child_count() == 2, "a lane and a volley appear")
	await get_tree().create_timer(0.4).timeout
	check(holder.get_child_count() == 2, "the feathers are still in the air or stuck after 0.4 s")
	await get_tree().create_timer(1.3).timeout
	check(holder.get_child_count() == 0, "everything cleaned up after itself (%d left)" % holder.get_child_count())
	holder.queue_free()
	var card: ItemTooltip = ItemTooltip.new()
	add_child(card)
	card.show_stack({"id": "sword_rift", "count": 1}, true)
	var perks: Array[String] = []
	for row: Dictionary in card._rows:
		if String(row["type"]) == "perk":
			perks.append(String(row["text"]))
	check(perks == ["SPITZENRISS", "RISSSCHNITT", "HIMMELSKREUZ", "FEDERBUND"], "the card lists the four specials (%s)" % str(perks))
	check(card.size.y <= float(ItemTooltip.MAX_HEIGHT) and card._col_x.size() >= 2, "the long card flows into columns (%s, %d columns)" % [str(card.size), card._col_x.size()])
	var short: ItemTooltip = ItemTooltip.new()
	add_child(short)
	short.show_stack({"id": "silver_chain", "count": 1}, true)
	check(short._col_x.size() == 1 and short.size.y < card.size.y, "a short card stays one column")
	card.free()
	short.free()
