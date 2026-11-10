extends Node
## Godot --headless --path . tools/test_talismans.tscn
## Talismane, steps 1 to 4 (docs/talisman_konzept.md): the pure rules (kinds, one of each kind, sums, limits, lines), the inventory (swap, refusal, sealed slots, the
## cursor), the effects (health and armor without healing, swallowed damage, damage and charge speed, the alarm of the three shadow creatures), the save and the card.
var failures: int = 0
var world: WorldLevel
var hero: Player
var bag: InventoryComponent


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps


func piece(id: String) -> Dictionary:
	return {"id": id, "count": 1}


func clear() -> void:
	for i: int in InventoryComponent.SIZE:
		bag.slots[i] = {}
	for slot_name: String in bag.equipment:
		bag.equipment[slot_name] = {}
	bag.held = {}
	bag.changed.emit()


func index_of(id: String) -> int:
	for i: int in InventoryComponent.SIZE:
		if String((bag.slots[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func wear(id: String) -> void:
	if index_of(id) < 0:
		bag.give(id, 1)
	bag.request("equip", [index_of(id), ""])


func unwear(id: String) -> void:
	for slot_name: String in bag.equipment:
		if String((bag.equipment[slot_name] as Dictionary).get("id", "")) == id:
			bag.request("unequip", [slot_name, -1])


func _run() -> void:
	var items: Dictionary = DataRegistry.table("items")
	items["test_chain2"] = {"name": "Testkette", "kind": "talisman", "slot": "talisman", "jewelry": "necklace", "rarity": "uncommon", "max_stack": 1, "bonus": {"health": 5}}
	items["test_chain_big"] = {"name": "Riesenkette", "kind": "talisman", "slot": "talisman", "jewelry": "necklace", "rarity": "epic", "max_stack": 1, "bonus": {"health": 999, "absorb": 0.9}}
	items["test_reif2"] = {"name": "Testreif", "kind": "talisman", "slot": "talisman", "jewelry": "bracelet", "rarity": "uncommon", "max_stack": 1, "bonus": {"damage": 0.04, "alarm": -0.5}}
	_rules()
	world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	hero = world._players.get_child(0) as Player
	bag = hero.inventory
	check(hero != null and bag != null and hero.talismans != null, "there is a hero with a bag and a TalismanComponent")
	hero.progress.claimed = 25 ## all three talisman slots open
	hero.progress.apply_stats(false)
	_inventory()
	await _effects()
	await _enemies()
	await _rissfeder()
	_save_and_card()
	await _art()
	print("DONE failures=", failures)
	get_tree().quit(failures)


# ---------------------------------------------------------------- the pure rules
func _rules() -> void:
	check(TalismanRules.type_of(piece("silver_chain")) == "necklace" and TalismanRules.type_of(piece("wuchtreif")) == "bracelet" and TalismanRules.type_of(piece("schweigtropfen")) == "earrings", "the three kinds of jewellery")
	check(TalismanRules.type_of(piece("sword_iron")) == "" and not TalismanRules.is_talisman(piece("stone")) and not TalismanRules.is_talisman({}), "a sword, a stone and nothing are no talismans")
	var all: Dictionary = TalismanRules.combine([piece("silver_chain"), piece("wuchtreif"), piece("schweigtropfen")])
	check(near(float(all.health), 12.0) and near(float(all.armor), 2.0), "the chain gives +12 health, +2 armor")
	check(near(float(all.damage), 0.08) and near(float(all.heavy_damage), 0.15) and near(float(all.charge_speed), 0.25), "the bracelet: +8 %% damage, +15 %% heavy, +25 %% charge speed")
	check(near(float(all.alarm), -0.5) and near(float(all.absorb), 0.25), "the earrings: alarm -50 %%, absorb 25 %%")
	check(near(TalismanRules.damage_factor(all, false), 1.08) and near(TalismanRules.damage_factor(all, true), 1.08 * 1.15), "damage factor: 1.08, heavy 1.08 x 1.15")
	check(near(TalismanRules.charge_rate(all), 1.25) and near(TalismanRules.alarm_scale(all), 0.5) and near(TalismanRules.absorb(all), 0.25), "charge rate 1.25, alarm scale 0.5, absorb 0.25")
	check(TalismanRules.combine([]).is_empty(), "nothing worn adds up to nothing")
	var twin: Dictionary = TalismanRules.combine([piece("silver_chain"), piece("test_chain2")])
	check(near(float(twin.health), 12.0), "of two necklaces only the first counts (a damaged save cannot stack a kind)")
	var capped: Dictionary = TalismanRules.combine([piece("test_chain_big")])
	check(near(float(capped.health), 60.0) and near(float(capped.absorb), 0.5), "sums stay inside the catalogue limits (60 health, 50 %% swallowed)")
	var alarm: Dictionary = TalismanRules.combine([piece("schweigtropfen"), piece("test_reif2")])
	check(near(float(alarm.alarm), -0.75) and near(TalismanRules.alarm_scale(alarm), 0.25), "alarm multiplies: two halves are a quarter (-75 %%), never zero")
	check(TalismanRules.line("damage", 0.08) == "+8 % SCHADEN" and TalismanRules.line("health", 12.0) == "+12 LEBEN" and TalismanRules.line("alarm", -0.5) == "-50 % ALARMREICHWEITE", "card lines read like the design")
	check(TalismanRules.better("damage", 0.1, 0.08) == 1 and TalismanRules.better("alarm", -0.5, 0.0) == 1 and TalismanRules.better("alarm", 0.0, -0.5) == -1 and TalismanRules.better("armor", 2.0, 2.0) == 0, "comparison: more damage and less alarm are better")
	var table: Dictionary = {"talisman_1": piece("wuchtreif"), "talisman_2": {}, "talisman_3": {}, "head": {}}
	check(TalismanRules.conflict(table, "talisman_2", piece("test_reif2")) == "talisman_1" and TalismanRules.conflict(table, "talisman_1", piece("test_reif2")) == "", "a second bracelet clashes with the worn one, but not in its own slot")
	check(TalismanRules.conflict(table, "talisman_2", piece("silver_chain")) == "" and TalismanRules.conflict(table, "talisman_2", piece("sword_iron")) == "", "other kinds and non-jewellery never clash")
	check(TalismanRules.refusal(table, "talisman_2", piece("test_reif2")) == "SCHON EIN ARMBAND ANGELEGT", "the refusal reads: %s" % TalismanRules.refusal(table, "talisman_2", piece("test_reif2")))
	var cfg: Dictionary = (DataRegistry.get_entry("weapon_classes", "sword_1h") as Dictionary).get("secondary", {}) as Dictionary
	check(near(HeavyRules.scaled_time(0.4, cfg, 1.25), 0.5) and near(HeavyRules.scaled_time(0.8, cfg, 1.25), 1.0) and near(HeavyRules.scaled_time(1.5, cfg, 1.25), 1.7) and near(HeavyRules.scaled_time(0.7, cfg, 1.0), 0.7), "charge clock: 1.25x up to the full charge, then in real time")


# ---------------------------------------------------------------- the inventory
func _inventory() -> void:
	clear()
	for id: String in ["silver_chain", "wuchtreif", "schweigtropfen"]:
		bag.give(id, 1)
		bag.request("equip", [index_of(id), ""])
	check(bag.equipment["talisman_1"].get("id") == "silver_chain" and bag.equipment["talisman_2"].get("id") == "wuchtreif" and bag.equipment["talisman_3"].get("id") == "schweigtropfen", "one of each kind goes into the three open slots")
	check(hero.talismans.worn == PackedStringArray(["silver_chain", "wuchtreif", "schweigtropfen"]) and hero.talismans.bonus == TalismanRules.combine(TalismanRules.stacks_of(hero.talismans.worn)), "the synced list of worn ids and the bonus agree")
	clear()
	check(hero.talismans.worn.is_empty() and hero.talismans.bonus.is_empty(), "taking everything off empties the list and the bonus")

	# a second piece of the same kind
	bag.give("silver_chain", 1)
	bag.give("test_chain2", 1)
	bag.request("equip", [index_of("silver_chain"), ""])
	bag.request("equip", [index_of("test_chain2"), ""])
	check(bag.equipment["talisman_1"].get("id") == "test_chain2" and index_of("silver_chain") >= 0 and (bag.equipment["talisman_2"] as Dictionary).is_empty(), "right-click: the new necklace REPLACES the worn one although slots are free")
	bag.request("equip", [index_of("silver_chain"), "talisman_3"])
	check((bag.equipment["talisman_3"] as Dictionary).is_empty() and index_of("silver_chain") >= 0, "equipping into a chosen slot is refused while the kind is worn")
	check(bag.refusal("talisman_3", piece("silver_chain")) == "SCHON EINE KETTE ANGELEGT" and bag.refusal("talisman_1", piece("silver_chain")) == "", "the window can ask why (and own slot is fine)")
	bag.held = piece("silver_chain")
	bag.request("click", ["equip", "talisman_2"])
	check(bag.held.get("id") == "silver_chain" and (bag.equipment["talisman_2"] as Dictionary).is_empty(), "cursor stack onto the wrong slot: refused, still in hand")
	bag.request("click", ["equip", "talisman_1"])
	check(bag.equipment["talisman_1"].get("id") == "silver_chain" and bag.held.get("id") == "test_chain2", "cursor stack onto the slot of its own kind swaps")
	bag.request("stow", [0])

	# swapping out of a slot must not bring a second piece of a worn kind in
	clear()
	bag.give("silver_chain", 1)
	bag.give("wuchtreif", 1)
	bag.give("test_chain2", 1)
	bag.request("equip", [index_of("silver_chain"), ""])
	bag.request("equip", [index_of("wuchtreif"), ""])
	var other: int = index_of("test_chain2")
	bag.request("unequip", ["talisman_2", other])
	check(bag.equipment["talisman_2"].get("id") == "wuchtreif" and bag.slots[other].get("id") == "test_chain2", "unequipping the bracelet onto a second necklace cannot put that necklace into its slot (a necklace is worn)")
	bag.request("unequip", ["talisman_1", other])
	check(bag.equipment["talisman_1"].get("id") == "test_chain2" and bag.slots[other].get("id") == "silver_chain", "... but swapping the necklace for another necklace is fine")

	# slots open with the level
	clear()
	hero.progress.claimed = 1
	bag.give("silver_chain", 1)
	bag.request("equip", [index_of("silver_chain"), ""])
	check((bag.equipment["talisman_1"] as Dictionary).is_empty(), "before level 5 no talisman slot is open")
	hero.progress.claimed = 5
	bag.request("equip", [index_of("silver_chain"), ""])
	bag.give("wuchtreif", 1)
	bag.request("equip", [index_of("wuchtreif"), ""])
	check(bag.equipment["talisman_1"].get("id") == "wuchtreif" and (bag.equipment["talisman_2"] as Dictionary).is_empty() and index_of("silver_chain") >= 0, "at level 5 there is one slot: the second piece swaps with the first (the necklace goes back into the bag)")
	hero.progress.claimed = 25
	clear()


# ---------------------------------------------------------------- the effects
func _dummy(distance: float) -> HealthComponent:
	var holder: Node2D = Node2D.new()
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	holder.global_position = hero.global_position + AttackComponent.BODY_CENTER + Vector2(distance, 0)
	var health: HealthComponent = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = 100000.0
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
	world.add_child(holder)
	return health


func _effects() -> void:
	var health: HealthComponent = hero.health
	clear()
	var base_max: float = health.max_health
	var base_armor: float = health.armor
	check(near(health.absorb, 0.0), "nothing swallowed without jewellery")

	# health and armor, never healed
	health.current = base_max
	wear("silver_chain")
	check(near(health.max_health, base_max + 12.0) and near(health.armor, base_armor + 2.0), "the chain: maximum +12 (%f), armor +2 (%f)" % [health.max_health, health.armor])
	check(near(health.current, base_max), "putting it on at full health does not heal (%f of %f)" % [health.current, health.max_health])
	health.current = base_max - 5.0
	for round_index: int in 5:
		unwear("silver_chain")
		wear("silver_chain")
	check(near(health.current, base_max - 5.0), "taking it off and on again five times heals nothing (%f)" % health.current)
	health.current = health.ceiling()
	var before: float = health.current
	unwear("silver_chain")
	check(near(health.max_health, base_max) and health.current <= health.ceiling() + 0.001 and health.current < before, "taking it off cuts the health above the new maximum (%f < %f)" % [health.current, before])
	wear("silver_chain")

	# swallowed damage
	wear("schweigtropfen")
	check(near(health.absorb, 0.25), "the earrings swallow a quarter")
	health.current = health.max_health
	health._invulnerable_until_msec = 0
	var blow: float = roundf(20.0 * LevelRewards.damage_factor(health.armor) * 10.0) / 10.0
	var expected: float = roundf(blow * 0.75 * 10.0) / 10.0
	health.take_damage(20.0, Vector2.ZERO, 0.0)
	check(near(health.max_health - health.current, expected), "a 20 hit costs %f after armor and a quarter swallowed (%f)" % [expected, health.max_health - health.current])
	health.current = health.max_health
	health.take_tick(10.0)
	check(near(health.max_health - health.current, 7.5), "damage over time is swallowed too (7.5 of 10)")
	unwear("schweigtropfen")
	check(near(health.absorb, 0.0), "taking the earrings off ends it")
	wear("schweigtropfen")

	# damage and charge speed (host: from its own copy of her bag)
	var weapon: Dictionary = piece("sword_iron")
	var light: Dictionary = hero.attack._step_data(weapon, 0)
	var def: Dictionary = Items.definition(weapon)
	var heavy: Dictionary = HeavyRules.step(HeavyRules.config(def), def, 1.0)
	var target: HealthComponent = _dummy(12.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var results: Array[float] = []
	for worn_bracelet: bool in [false, true]:
		if worn_bracelet:
			wear("wuchtreif")
		for step: Dictionary in [light, heavy]:
			target.current = target.max_health
			hero.attack._hit_scan(Vector2.RIGHT, step, weapon)
			results.append(target.max_health - target.current)
	check(results[0] > 0.0 and near(results[0], 8.0 * float(light.damage), 0.01) and near(results[1], 8.0 * float(heavy.damage), 0.01), "without the bracelet the hits are 8 x the step (%s)" % str(results))
	check(near(results[2], results[0] * 1.08, 0.01) and near(results[3], results[1] * 1.08 * 1.15, 0.01), "with it: +8 %% on a light hit, +8 %% and +15 %% on the heavy blow (%s)" % str(results))
	var cfg: Dictionary = HeavyRules.config(def)
	hero.attack._charge_cfg = cfg
	hero.attack._charge_time = 0.4
	check(near(hero.attack._charge_rate(), 1.25), "the charge runs 1.25 times as fast up to the full charge")
	hero.attack._charge_time = float(cfg.get("charge_full", 1.0))
	check(near(hero.attack._charge_rate(), 1.0), "past the full charge the hold is real time")
	unwear("wuchtreif")
	hero.attack._charge_time = 0.4
	check(near(hero.attack._charge_rate(), 1.0), "without the bracelet it charges normally")
	hero.attack._charge_time = 0.0
	check(near(HeavyRules.host_charge(1.0, HeavyRules.scaled_time(0.8, cfg, 1.25), cfg), 1.0), "the host accepts a charge the owner reached 0.8 s after starting")


## One shadow creature at `distance` in a free direction round the hero, facing her.
func _creature(id: String, distance: float) -> Node2D:
	for angle: float in [0.0, PI, PI / 2.0, -PI / 2.0, PI / 4.0, -PI / 4.0, 3.0 * PI / 4.0, -3.0 * PI / 4.0]:
		var at: Vector2 = hero.global_position + Vector2.from_angle(angle) * distance
		var enemy: Node2D = world.spawn_species(id, at, angle + PI)
		if enemy != null:
			enemy.set("heading", angle + PI)
			enemy.process_mode = Node.PROCESS_MODE_DISABLED
			return enemy
	return null


func _enemies() -> void:
	clear()
	hero.velocity = Vector2.ZERO
	var spider_range: float = float(DataRegistry.get_entry("enemies", "shadow_spider")["sight_range"])
	var seen_plain: bool = false
	var spider: ShadowSpider = _creature("shadow_spider", spider_range * 0.7) as ShadowSpider
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(spider != null, "a spider stands near her")
	if spider != null:
		seen_plain = spider._find_target() == hero
		check(seen_plain, "a spider at 70 %% of its sight range sees her without jewellery")
		wear("schweigtropfen")
		check(near(hero.stealth.alarm_scale(), 0.5), "the earrings halve the alarm scale")
		check(spider._find_target() == null, "with the Schweigtropfen it no longer sees her at 70 %% (sight 50 %%)")
		hero.global_position += Vector2.ZERO
		spider.global_position = hero.global_position + (spider.global_position - hero.global_position).normalized() * spider_range * 0.4
		check(spider._find_target() == hero, "... but still at 40 %%")
		spider.queue_free()
		unwear("schweigtropfen")
	for id: String in ["void_listener", "void_crusher"]:
		var def: Dictionary = DataRegistry.get_entry("enemies", id)
		var reach: float = maxf(float(def["sight_range"]), float(def["hearing_walk"]))
		var enemy: Node2D = _creature(id, reach * 0.7)
		await get_tree().physics_frame
		await get_tree().physics_frame
		check(enemy != null, "%s stands near her" % id)
		if enemy == null:
			continue
		hero.velocity = Vector2(60, 0) ## she walks: sound counts
		enemy.set("_target", null)
		enemy.call("_sense")
		var heard_plain: bool = enemy.get("_target") == hero
		enemy.set("_target", null)
		wear("schweigtropfen")
		enemy.call("_sense")
		var heard_worn: bool = enemy.get("_target") == hero
		check(heard_plain, "%s notices her at 70 %% of its range" % id)
		check(not heard_worn, "%s does not with the Schweigtropfen (sight and hearing halved)" % id)
		unwear("schweigtropfen")
		hero.velocity = Vector2.ZERO
		enemy.queue_free()


# ---------------------------------------------------------------- save and card
func _save_and_card() -> void:
	clear()
	SaveGame._restore_stacks(bag, {"slots": [], "equipment": {"talisman_2": {"id": "wuchtreif", "count": 1.0}}})
	check(bag.equipment["talisman_2"].get("id") == "wuchtreif" and near(float(hero.talismans.bonus.get("damage", 0.0)), 0.08), "a loaded save brings the worn bracelet and its bonus back")
	clear()
	var card: ItemTooltip = ItemTooltip.new()
	add_child(card)
	card.show_stack(piece("wuchtreif"), true)
	var texts: Array[String] = []
	for row: Dictionary in card._rows:
		texts.append(String(row.get("text", "")))
	check("+8 % SCHADEN" in texts and "+15 % WUCHTSCHLAG" in texts and "+25 % AUFLADETEMPO" in texts, "the card lists the three effects: %s" % str(texts))
	check(texts[1].to_lower().contains("armband") and texts[1].to_lower().contains("angriff"), "the card names kind and field (%s)" % texts[1])
	card.show_stack(piece("test_reif2"), true, piece("wuchtreif"))
	var tones: Dictionary = {}
	for row: Dictionary in card._rows:
		if String(row["type"]) == "bonus":
			tones[String(row["text"])] = int(row["tone"])
	check(tones.get("+4 % SCHADEN") == -1 and tones.get("-50 % ALARMREICHWEITE") == 1 and tones.get("OHNE WUCHTSCHLAG") == -1, "compared with the worn bracelet: worse damage red, less alarm green, lost lines red (%s)" % str(tones))
	card.free()


# ---------------------------------------------------------------- how it looks
func _art() -> void:
	# the exported points fit the sheets the game plays
	var sheets: Dictionary = {"main": "player.png", "attack": "player_attack.png", "pick": "player_pick.png", "eat": "player_eat.png", "pull": "player_pull.png", "touch": "player_touch.png", "heavy": "player_heavy.png", "fish": "player_fish.png", "standby": "player_standby.png"}
	var table: Dictionary = (DataRegistry.table("hero_jewelry").get("sheets", {}) as Dictionary)
	for key: String in sheets:
		var texture: Texture2D = load("res://assets/characters/" + String(sheets[key])) as Texture2D
		var entry: Dictionary = table.get(key, {}) as Dictionary
		var cols: int = int(entry.get("cols", 0))
		var rows: int = int(entry.get("rows", 0))
		check(cols > 0 and texture != null and texture.get_width() == cols * 48 and texture.get_height() == rows * 56 and (entry.get("data", []) as Array).size() == cols * rows * TalismanArt.STRIDE, "%s: %d x %d frames of points match the sheet" % [key, cols, rows])
	var main: Texture2D = load("res://assets/characters/player.png") as Texture2D
	var south: PackedInt32Array = TalismanArt.frame_data(main, 2 * 16 + 12) ## sector S, idle
	var north: PackedInt32Array = TalismanArt.frame_data(main, 6 * 16 + 12)
	var west: PackedInt32Array = TalismanArt.frame_data(main, 4 * 16 + 12)
	check(south.size() == 16 and south[10] > 80 and south[11] > 80 and north[10] < -80 and north[11] < -80, "facing: the torso and head face the camera from the south, away from it from the north")
	check(west[12] * west[13] < 0 and absi(west[12] - west[13]) > 100, "from the side one ear faces the camera, the other away")
	check(south[4] / 10 == 0 and south[5] < south[1] * -1 + 400, "the pendant hangs on the chest (below the collar points)")
	check(TalismanArt.frame_data(load("res://assets/characters/player_faint.png") as Texture2D, 0).is_empty(), "a cutscene sheet carries no jewellery")
	# the pieces have pictures
	check(TalismanArt.metal(TalismanArt.look_of("schweigtropfen")).size() == 4 and (TalismanArt.look_of("silver_chain").get("pendant", []) as Array).size() > 0 and (TalismanArt.look_of("schweigtropfen").get("drop", []) as Array).size() > 0, "chain and earrings have their shapes")
	# the layer draws them on her sprite, the bracelet sits on the sword arm
	clear()
	for id: String in ["silver_chain", "wuchtreif", "schweigtropfen"]:
		wear(id)
	await get_tree().process_frame
	var layer: TalismanLayer = hero.get_node("Sprite2D").get_child(hero.get_node("Sprite2D").get_child_count() - 1) as TalismanLayer
	if layer == null:
		for node: Node in hero.get_node("Sprite2D").get_children():
			if node is TalismanLayer:
				layer = node as TalismanLayer
	check(layer != null, "her sprite carries a TalismanLayer")
	check(hero.talismans.worn_id("bracelet") == "wuchtreif" and hero.talismans.worn_id("earrings") == "schweigtropfen" and hero.talismans.worn_id("necklace") == "silver_chain", "the component names the worn piece of each kind")
	var flashes: Array[int] = [0]
	hero.talismans.absorbed.connect(func() -> void: flashes[0] += 1)
	hero.health.current = hero.health.max_health
	hero.health._invulnerable_until_msec = 0
	hero.health.take_damage(10.0, Vector2.ZERO, 0.0)
	check(flashes[0] == 1, "a swallowed blow tells the earrings to flash")
	clear()


# ---------------------------------------------------------------- the Rissfeder (docs/rissfeder.md)
func _rissfeder() -> void:
	var feather: Dictionary = piece("rissfeder")
	check(Items.definition(feather).get("rarity") == "legendary" and TalismanRules.type_of(feather) == "necklace", "the Rissfeder is a legendary necklace")
	var bonus: Dictionary = TalismanRules.combine([feather])
	check(near(float(bonus.health), 20.0) and near(float(bonus.armor), 3.0) and near(float(bonus.blink_cooldown), -0.3) and near(float(bonus.corvid_calm), 0.7), "its stats: +20 health, +3 armor, -30 %% blink cooldown, 70 %% calmer crows")
	check(near(TalismanRules.blink_scale(bonus), 0.7) and near(TalismanRules.corvid_calm(bonus), 0.7) and near(TalismanRules.blink_scale({}), 1.0) and near(TalismanRules.corvid_calm({}), 0.0), "blink scale 0.7, crow calm 0.7, neutral without it")
	check(TalismanRules.better("blink_cooldown", -0.3, 0.0) == 1 and TalismanRules.better("blink_cooldown", 0.0, -0.3) == -1, "comparison: a shorter blink cooldown is better")
	var perks: Dictionary = TalismanRules.perks([feather, piece("silver_chain")])
	check(perks.has("ward") and perks.has("dive") and perks.size() == 2 and TalismanRules.perks([piece("silver_chain")]).is_empty(), "the feather carries two special abilities, a plain chain none")
	check(TalismanRules.perk_ids(feather) == ["ward", "dive"] and TalismanRules.perk_name("ward") == "LETZTER FLÜGELSCHLAG", "perk names: %s" % str(TalismanRules.perk_ids(feather)))
	var text: String = TalismanRules.perk_text("ward")
	check(text.contains("30") and text.contains("240") and not text.contains("{"), "the ward text names the numbers and leaves no token: %s" % text)
	check(TalismanRules.perk_text("dive").contains("40") and not TalismanRules.perk_text("dive").contains("{"), "the dive text names +40 %%")
	check(TalismanArt.metal(TalismanArt.look_of("rissfeder")).size() == 4 and (TalismanArt.look_of("rissfeder").get("pendant", []) as Array).size() > 0, "the feather has its shape and ravensteel")
	check(load("res://assets/items/rissfeder.png") != null and load("res://assets/audio/talisman/ward.wav") != null and load("res://assets/audio/talisman/ward_ready.wav") != null and load("res://assets/audio/talisman/equip_ravensteel.wav") != null, "icon and the three sounds exist")

	# worn: the ward catches a lethal blow once
	clear()
	var health: HealthComponent = hero.health
	health._invulnerable_until_msec = 0
	health.current = health.max_health
	wear("rissfeder")
	check(hero.talismans.perks.has("ward") and health.ward.is_valid() and hero.talismans.ward_ready, "worn: the ward is hooked and ready")
	health.current = 3.0
	health.take_damage(500.0, Vector2.ZERO, 0.0)
	await get_tree().process_frame
	check(health.current > 0.0 and near(health.current, health.max_health * 0.3, 0.6), "a lethal blow leaves 30 %% of the health (%f of %f)" % [health.current, health.max_health])
	check(not hero.talismans.ward_ready, "the ward is spent")
	var hp: float = health.current
	health.take_damage(500.0, Vector2.ZERO, 0.0)
	check(near(health.current, hp), "the blow right after is ignored (2.5 s grace)")
	health._invulnerable_until_msec = 0
	health.take_damage(500.0, Vector2.ZERO, 0.0)
	await get_tree().process_frame
	check(health.current <= 0.0, "a second lethal blow within the cooldown kills her (%f)" % health.current)
	health.current = health.max_health
	hero.talismans._ward_left = 0.0
	hero.talismans._ward_state(true, Vector2.ZERO)
	health._invulnerable_until_msec = 0
	health.current = 2.0
	health.take_tick(50.0)
	await get_tree().process_frame
	check(health.current > 2.0, "damage over time is caught as well (%f)" % health.current)
	hero.talismans._ward_left = 0.0
	hero.talismans._ward_state(true, Vector2.ZERO)
	unwear("rissfeder")
	check(not health.ward.is_valid() and hero.talismans.perks.is_empty(), "taking it off removes the ward and the abilities")
	health.current = health.max_health
	health._invulnerable_until_msec = 0

	# the blink cooldown and the dive
	var plain: float = hero.blink.cooldown
	hero.blink.start_cooldown()
	check(near(hero.blink.total, plain), "without the feather the blink cooldown is %f" % plain)
	wear("rissfeder")
	hero.blink.start_cooldown()
	check(near(hero.blink.total, plain * 0.7), "with it the blink cooldown is 70 %% (%f)" % hero.blink.total)
	check(near(hero.talismans.dive_factor(), 1.0), "no dive window before a blink")
	hero.talismans.note_blink()
	check(near(hero.talismans.dive_factor(), 1.4) and hero.talismans.dive_left > 2.9, "after a blink the next blow does +40 %%")
	var weapon: Dictionary = piece("sword_iron")
	var step: Dictionary = hero.attack._step_data(weapon, 0)
	var target: HealthComponent = _dummy(12.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	hero.talismans.dive_left = 0.0
	target.current = target.max_health
	hero.attack._hit_scan(Vector2.RIGHT, step, weapon)
	var normal: float = target.max_health - target.current
	hero.talismans.note_blink()
	target.current = target.max_health
	hero.attack._hit_scan(Vector2.RIGHT, step, weapon)
	var dived: float = target.max_health - target.current
	await get_tree().process_frame
	check(normal > 0.0 and near(dived, normal * 1.4, 0.05), "the dive blow hurts 40 %% more (%f -> %f)" % [normal, dived])
	check(near(hero.talismans.dive_factor(), 1.0) and hero.talismans.dive_left <= 0.0, "the dive is used up by one blow")
	unwear("rissfeder")
	hero.talismans.note_blink()
	check(near(hero.talismans.dive_factor(), 1.0), "without the feather a blink opens no dive window")
	await _boss_relics()
	clear()


## What the boss leaves behind: certain at the first kill of a player, 10 % after (BossRelics).
func _boss_relics() -> void:
	var ledger: BossRelics = BossRelics.of(get_tree())
	check(ledger != null, "the level has a BossRelics ledger")
	var relics: Array = ((DataRegistry.get_entry("enemies", "boss_sky_cleaver") as Dictionary).get("loot", {}) as Dictionary).get("relics", []) as Array
	check(relics.size() == 1 and String(relics[0]["id"]) == "rissfeder" and near(float(relics[0]["first"]), 1.0) and near(float(relics[0]["chance"]), 0.1), "Mornath's loot lists the Rissfeder: 100 %% first, 10 %% after")
	var owner: int = hero.name.to_int()
	ledger.forget("boss_sky_cleaver")
	check(ledger.kills_of(owner, "boss_sky_cleaver") == 0, "no kills counted yet")
	var given: Array[int] = ledger.roll("boss_sky_cleaver", relics, [hero], hero.global_position)
	check(given == [owner] and ledger.kills_of(owner, "boss_sky_cleaver") == 1 and ledger.owed_count(owner) == 1, "the first kill drops the feather for her, certainly")
	var drops: Array[ItemDrop] = _relic_drops()
	check(drops.size() == 1 and drops[0].story_owner == owner and drops[0].item_id == "rissfeder" and drops[0].story_id == "relic:rissfeder", "it lies there as her own drop")
	# saved and loaded while it still lies on the ground
	var json: Dictionary = JSON.parse_string(JSON.stringify(ledger.export_state())) as Dictionary
	ledger.import_state(json)
	await get_tree().process_frame
	await get_tree().process_frame
	check(_relic_drops().size() == 1 and ledger.kills_of(owner, "boss_sky_cleaver") == 1 and ledger.owed_count(owner) == 1, "after a save and load the feather still lies there once and the kill is counted")
	ledger.collected(String(_relic_drops()[0].name))
	check(ledger.owed_count(owner) == 0, "picked up: nothing is owed any more")
	for drop: ItemDrop in _relic_drops():
		drop.queue_free()
	await get_tree().process_frame
	# later kills: 10 %, measured over many rolls
	var hits: int = 0
	var rounds: int = 400
	for i: int in rounds:
		hits += ledger.roll("boss_sky_cleaver", relics, [hero], hero.global_position).size()
	check(hits > rounds * 0.04 and hits < rounds * 0.18, "later kills drop it about every tenth time (%d of %d)" % [hits, rounds])
	check(ledger.kills_of(owner, "boss_sky_cleaver") == rounds + 1, "every kill is counted")
	ledger.forget("boss_sky_cleaver")
	check(ledger.roll("boss_sky_cleaver", relics, [hero], hero.global_position).size() == 1, "after forgetting, the next kill is a first kill again")
	for drop: ItemDrop in _relic_drops():
		drop.queue_free()
	await get_tree().process_frame
	ledger.import_state({})
	ledger.forget("boss_sky_cleaver")


func _relic_drops() -> Array[ItemDrop]:
	var found: Array[ItemDrop] = []
	for container: Node in get_tree().get_nodes_in_group("drops"):
		for drop: Node in container.get_children():
			if drop is ItemDrop and (drop as ItemDrop).story_id.begins_with(BossRelics.PREFIX) and not drop.is_queued_for_deletion():
				found.append(drop as ItemDrop)
	return found
