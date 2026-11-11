extends Node
## Magic (docs/magie_konzept.md): data, rules, sockets in the bag, the recharge, both spells on a real player (Bannlicht burns a dummy,
## Wurzelgrund heals her), the gems, the BANNKREIS light, Glutschwarm (no target = no cast, shards burn), Nebelschleier (a spider cannot pick
## her), Leerenschlund (price, bite, life back), a thrown staff keeping its stones. Headless: prints MAGIC OK.
const PLAYER: PackedScene = preload("res://src/entities/player/player.tscn")
const DUMMY: PackedScene = preload("res://src/entities/enemies/training_dummy.tscn")
const DROP: PackedScene = preload("res://src/entities/drops/item_drop.tscn")
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + label)


func _wait(seconds: float) -> void:
	var until: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame


func _run() -> void:
	# ---- data: the staff, every crystal and gem of every tier, their art
	var items: Dictionary = DataRegistry.table("items")
	var rarities: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]
	check(items.has("staff_hag_elm") and SpellRules.is_staff({"id": "staff_hag_elm", "count": 1}), "the Hexenulmenstab is a staff")
	for base: String in ["crystal_banish", "crystal_roots", "crystal_embers", "crystal_veil", "crystal_maw", "gem_lens", "gem_wild", "gem_tinder", "gem_haze", "gem_hunger"]:
		for tier: int in range(1, 6):
			var id: String = "%s_%d" % [base, tier]
			var def: Dictionary = items.get(id, {}) as Dictionary
			check(not def.is_empty(), "item " + id)
			check(String(def.get("rarity", "")) == rarities[tier - 1], "rarity follows the tier: " + id)
			check(ResourceLoader.exists(String(def.get("icon", ""))), "icon of " + id)
			check(ResourceLoader.exists("res://assets/magic/crystals/%s_big.png" % id), "big picture of " + id)
			check(SpellRules.tier_of(id) == tier, "tier of " + id)
	check(SpellRules.tier_name("crystal_banish_1") == "SPLITTER" and SpellRules.tier_name("crystal_roots_5") == "STERNSTEIN", "spell tier names")
	check(SpellRules.tier_name("gem_lens_1") == "ROHSCHLIFF" and SpellRules.tier_name("gem_wild_5") == "KRONE", "gem tier names")
	check(ResourceLoader.exists("res://assets/magic/staff_stones.png"), "the stones of the staff")
	check(ResourceLoader.exists("res://assets/items/staff_hag_elm_held_rot.png"), "the staff's rotated sheet")
	check(items.has("staff_bone_fork") and SpellRules.is_staff({"id": "staff_bone_fork", "count": 1}) and SpellRules.prongs_of("staff_bone_fork") == 2, "the Bleichgabel is a staff with two prongs")
	check(ResourceLoader.exists("res://assets/items/staff_bone_fork_held_rot.png") and ResourceLoader.exists("res://assets/items/staff_bone_fork.png"), "the Bleichgabel's pictures")
	check(DataRegistry.table("recipes").has("staff_bone_fork"), "the lake witch can make the Bleichgabel")
	var fork_a: Dictionary = {"id": "staff_bone_fork", "count": 1, "sp": "crystal_banish_1", "sp2": "crystal_banish_3"}
	var fork_b: Dictionary = {"id": "staff_bone_fork", "count": 1, "sp": "crystal_banish_1", "sp2": "crystal_maw_1"}
	var fork_c: Dictionary = {"id": "staff_bone_fork", "count": 1, "sp": "crystal_banish_1", "sp2": "crystal_roots_1"}
	check(SpellRules.fork_bond(fork_a) == "harmony" and SpellRules.fork_bond(fork_b) == "tension" and SpellRules.fork_bond(fork_c) == "", "GLEICHKLANG, ZWIESPALT, nothing")
	check(SpellRules.fork_bond({"id": "staff_hag_elm", "count": 1, "sp": "crystal_banish_1"}) == "", "one prong has no bond")
	check(is_equal_approx(float(SpellRules.fork_rules(fork_a)["charge"]), 0.85) and is_equal_approx(float(SpellRules.fork_rules(fork_b)["echo"]), 1.5) and is_equal_approx(float(SpellRules.fork_rules(fork_c)["echo"]), 1.25), "the fork's numbers by bond")
	check(is_equal_approx(float(SpellRules.empower(SpellRules.params("crystal_maw_1"), 1.5)["damage"]), float(SpellRules.params("crystal_maw_1")["damage"]) * 1.5), "GABELSCHLAG strengthens the cast")
	# ---- rules
	var b1: Dictionary = SpellRules.params("crystal_banish_1")
	var b5: Dictionary = SpellRules.params("crystal_banish_5")
	check(float(b5["dps"]) > float(b1["dps"]) and float(b5["radius"]) > float(b1["radius"]) and float(b5["cooldown"]) < float(b1["cooldown"]), "a higher tier is stronger and charges faster")
	check(not bool(b1["perk3"]) and bool(SpellRules.params("crystal_banish_3")["perk3"]) and float(b5["every"]) > 0.0, "milestones at III and V")
	check(SpellRules.fits("crystal_banish_2", "gem_lens_1") and not SpellRules.fits("crystal_roots_2", "gem_lens_1"), "Brennglas fits light, not roots")
	check(SpellRules.fits("crystal_roots_2", "gem_wild_1") and not SpellRules.fits("crystal_banish_2", "gem_wild_1"), "Wildwuchs fits roots, not light")
	var lensed: Dictionary = SpellRules.params("crystal_banish_2", "gem_lens_3")
	check(float(lensed["dps"]) > float(SpellRules.params("crystal_banish_2")["dps"]) and float(lensed["radius"]) > float(SpellRules.params("crystal_banish_2")["radius"]), "Brennglas III burns hotter and wider")
	check(not bool(SpellRules.params("crystal_roots_2", "gem_lens_5")["gem_ok"]), "a gem that does not fit does nothing")
	check(float(SpellRules.params("crystal_roots_1", "gem_wild_2")["seconds"]) > float(SpellRules.params("crystal_roots_1")["seconds"]), "Wildwuchs makes roots last")
	check(float(SpellRules.params("crystal_banish_1", "gem_lens_5")["flare"]) > 0.0 and float(SpellRules.params("crystal_roots_1", "gem_wild_5")["bloom"]) > 0.0, "gem tier V perks")
	check(SpellRules.target_point(Vector2.ZERO, Vector2(500, 0), 110.0).is_equal_approx(Vector2(110, 0)), "ground spells are pulled back to their range")
	var plan: Array = SpellRules.volley_plan(2, 5, 1.5)
	check(plan.size() == 5 and plan.map(func(s: Array) -> int: return int(s[0])) == [0, 1, 0, 1, 0], "Glutschwarm: one shard on each target, then round again")
	check(is_equal_approx(float(plan[0][1]), 1.0) and is_equal_approx(float(plan[1][1]), 1.0) and is_equal_approx(float(plan[2][1]), 1.5), "every further shard on the same target hits x1.5")
	check(SpellRules.volley_plan(0, 3, 1.5).is_empty(), "no target, no shards")
	check(int(SpellRules.params("crystal_embers_1")["shards"]) == 1 and int(SpellRules.params("crystal_embers_5")["shards"]) == 5, "one shard at tier I, five at tier V")
	check(float(SpellRules.params("crystal_embers_3")["jump"]) > 0.0 and float(SpellRules.params("crystal_embers_5")["ring"]) > 0.0 and float(SpellRules.params("crystal_embers_2")["jump"]) == 0.0, "FUNKENSPRUNG at III, GLUTHERZ at V")
	check(float(SpellRules.params("crystal_veil_3")["ghost"]) > 0.0 and float(SpellRules.params("crystal_veil_5")["group"]) > 0.0, "IRRSPUR at III, SCHLEIERKREIS at V")
	check(SpellRules.can_pay(100.0, 100.0, 0.1) and not SpellRules.can_pay(11.0, 100.0, 0.1), "the void's price is never the last of her")
	check(float(SpellRules.params("crystal_maw_5")["devour"]) > 0.0 and int(SpellRules.params("crystal_maw_3")["fed"]) == 3, "LEERER STERN at V, SATTER SCHLUND at III")
	# the three new gem families
	var tindered: Dictionary = SpellRules.params("crystal_embers_3", "gem_tinder_3")
	check(int(tindered["shards"]) == 4 and float(tindered["burn_dps"]) > float(SpellRules.params("crystal_embers_3")["burn_dps"]), "Zunder III: one shard more, a hotter fire")
	check(float(SpellRules.params("crystal_embers_1", "gem_tinder_5")["rekindle"]) == 2.0 and not SpellRules.fits("crystal_veil_1", "gem_tinder_5"), "Zunder V AUFLODERN, and Zunder fits only Glut")
	var hazed: Dictionary = SpellRules.params("crystal_veil_2", "gem_haze_3")
	check(float(hazed["seconds"]) > float(SpellRules.params("crystal_veil_2")["seconds"]) and float(hazed["cooldown"]) < float(SpellRules.params("crystal_veil_2")["cooldown"]), "Dunst: a longer veil, and from III a faster crystal")
	check(float(SpellRules.params("crystal_veil_1", "gem_haze_5")["cloud"]) > 0.0 and float(SpellRules.params("crystal_veil_1", "gem_haze_4")["cloud"]) == 0.0, "Dunst V NEBELWAND")
	var hungry: Dictionary = SpellRules.params("crystal_maw_2", "gem_hunger_3")
	check(float(hungry["refund"]) > float(SpellRules.params("crystal_maw_2")["refund"]) and float(hungry["radius"]) > float(SpellRules.params("crystal_maw_2")["radius"]), "Hunger: more life back, from III a wider pull")
	check(float(SpellRules.params("crystal_maw_1", "gem_hunger_5")["bite2"]) > 0.0 and not SpellRules.fits("crystal_embers_1", "gem_hunger_5"), "Hunger V ZWEITER BISS, fits only Leere")
	# ---- a player, sockets in the bag
	var player: Player = PLAYER.instantiate() as Player
	player.name = "1"
	player.position = Vector2(200, 200)
	add_child(player)
	await get_tree().process_frame
	var inv: InventoryComponent = player.inventory
	inv.clear_all()
	inv.slots[0] = {"id": "staff_hag_elm", "count": 1}
	inv.slots[10] = {"id": "crystal_banish_1", "count": 2}
	inv.slots[11] = {"id": "gem_lens_1", "count": 1}
	inv.slots[12] = {"id": "crystal_roots_1", "count": 1}
	inv.slots[13] = {"id": "gem_wild_5", "count": 1}
	inv.select(0)
	inv.request("click", ["inv", 10]) ## two Bannlicht splinters on the cursor
	inv.request("click", ["inv", 0]) ## laid on the staff: one goes in
	var staff: Dictionary = inv.slots[0]
	check(SpellRules.spell_in(staff) == "crystal_banish_1", "a spell crystal laid on the staff sits in its crown")
	check(int(inv.held.get("count", 0)) == 1, "only one of the stack went in")
	inv.request("click", ["inv", 10]) ## the rest back
	inv.request("click", ["inv", 11])
	inv.request("click", ["inv", 0])
	check(SpellRules.gem_in(staff) == "gem_lens_1" and inv.held.is_empty(), "a gem goes into the knot")
	check(Items.extras(staff).get("sp", "") == "crystal_banish_1" and Items.extras(staff).get("gm", "") == "gem_lens_1", "the stones travel with the staff (extras)")
	check(not SpellRules.can_socket(staff, {"id": "dusk_berry", "count": 1}), "a berry is no stone")
	await get_tree().process_frame
	var spells: SpellComponent = player.spells
	check(spells.staff_held and spells.spell == "crystal_banish_1" and spells.gem == "gem_lens_1", "the host knows what she holds")
	check(spells.charge_left > 0.0 and not spells.is_ready(), "a crystal set in starts empty")
	spells.debug_recharge()
	check(spells.is_ready(), "the dev button fills it")
	# ---- Bannlicht burns a dummy standing in it
	var dummy: Node2D = DUMMY.instantiate() as Node2D
	dummy.position = player.position + Vector2(18, 6)
	add_child(dummy)
	var dummy_health: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	await get_tree().physics_frame
	var full: float = dummy_health.current
	check(spells.try_cast(player.position + Vector2(40, 0)), "LMB with the staff starts a cast")
	check(player.cast_glow() >= 0.0 and player._busy and player._busy_kind == "cast_light", "she plays the light cast")
	await _wait(0.6)
	var light: BanishLight = null
	for child: Node in get_children():
		if child is BanishLight:
			light = child as BanishLight
	check(light != null, "the light stands after the release")
	check(spells.charge_left > 5.0, "the crystal is empty again after the cast (%.1f)" % spells.charge_left)
	check(not spells.try_cast(player.position), "no second cast while it charges")
	await _wait(1.6)
	check(dummy_health.current < full, "the dummy burns in the light (%.1f of %.1f)" % [dummy_health.current, full])
	check(light != null and light.inside(player.global_position) and not light.inside(player.global_position + Vector2(0, 60)), "the light is a flat circle")
	await _wait(5.0)
	check(not is_instance_valid(light), "the light goes out by itself")
	# ---- BANNKREIS: from tier III the night treats the light as a lamp
	inv.held = {"id": "crystal_banish_3", "count": 1}
	inv.request("click", ["inv", 0])
	check(SpellRules.spell_in(staff) == "crystal_banish_3" and String(inv.held.get("id", "")) == "crystal_banish_1", "a new crystal swaps the old one onto the cursor")
	inv.request("stow", [0])
	spells.debug_recharge()
	await get_tree().process_frame
	var lights_before: int = TownManager.magic_lights.size()
	spells.try_cast(player.position)
	await _wait(0.7)
	check(TownManager.magic_lights.size() == lights_before + 1, "BANNKREIS registers its light")
	await _wait(9.0)
	check(TownManager.magic_lights.size() == lights_before, "and takes it away when it goes out")
	# ---- Wurzelgrund heals her, not above full at tier I
	inv.request("rclick", ["inv", 0]) ## the spell crystal comes out first
	check(SpellRules.spell_in(staff) == "" and String(inv.held.get("id", "")) == "crystal_banish_3", "right click takes the spell crystal out")
	inv.request("stow", [0])
	inv.request("rclick", ["inv", 0])
	check(SpellRules.gem_in(staff) == "" and String(inv.held.get("id", "")) == "gem_lens_1", "then the gem")
	inv.request("stow", [0])
	inv.held = {"id": "crystal_roots_1", "count": 1}
	inv.request("click", ["inv", 0])
	inv.held = {"id": "gem_wild_5", "count": 1}
	inv.request("click", ["inv", 0])
	await get_tree().process_frame
	check(spells.spell == "crystal_roots_1" and spells.gem == "gem_wild_5", "roots and Wildwuchs in the staff")
	spells.debug_recharge()
	player.health.set_health(player.health.max_health * 0.5)
	var hurt: float = player.health.current
	check(spells.try_cast(player.position + Vector2(10, 0)), "the root cast starts")
	await _wait(0.5)
	var roots: RootGround = null
	for child: Node in get_children():
		if child is RootGround:
			roots = child as RootGround
	check(roots != null, "the roots break out where she aimed")
	await _wait(3.5)
	check(player.health.current > hurt + 2.0, "standing in the roots heals her (%.1f -> %.1f)" % [hurt, player.health.current])
	check(roots != null and roots.get_children().filter(func(n: Node) -> bool: return n is MagicRoot).size() >= 7, "a ring of roots")
	player.health.set_health(player.health.max_health)
	await _wait(1.2)
	check(player.health.current <= player.health.max_health + 0.01, "tier I heals only up to full")
	# ---- Glutschwarm: nothing to burn, nothing happens; shards fly and set the dummy on fire
	player.health.set_health(player.health.max_health)
	inv.request("rclick", ["inv", 0])
	inv.request("stow", [0])
	inv.held = {"id": "crystal_embers_3", "count": 1}
	inv.request("click", ["inv", 0])
	inv.request("stow", [0])
	await get_tree().process_frame
	spells.debug_recharge()
	dummy.position = player.position + Vector2(900, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(spells.spell == "crystal_embers_3" and spells.is_ready(), "Glutschwarm in the staff")
	check(not spells.try_cast(player.position + Vector2(40, 0)), "Glutschwarm without a creature in reach does nothing")
	check(spells.is_ready(), "and the crystal stays full")
	dummy.position = player.position + Vector2(70, 10)
	await get_tree().physics_frame
	await get_tree().physics_frame
	dummy_health.heal_full()
	full = dummy_health.current
	check(spells.try_cast(dummy.position), "with a creature near it casts")
	check(player._busy_kind == "cast_ember", "she plays the ember cast")
	await _wait(0.45)
	var volley: EmberVolley = null
	for child: Node in get_children():
		if child is EmberVolley:
			volley = child as EmberVolley
	check(volley != null and volley.extra.size() == 3, "three shards, all on the one dummy")
	await _wait(1.0)
	check(dummy_health.current < full - 30.0, "the shards hit hard: 13 + 19.5 + 19.5 (%.1f of %.1f)" % [dummy_health.current, full])
	check(dummy.get_node_or_null("EmberBurn") != null, "the dummy burns")
	var burning: float = dummy_health.current
	await _wait(1.2)
	check(dummy_health.current < burning, "the fire keeps burning it (%.1f -> %.1f)" % [burning, dummy_health.current])
	# ---- Nebelschleier: she veils herself, a spider cannot pick her
	add_to_group("world")
	inv.request("rclick", ["inv", 0])
	inv.request("stow", [0])
	inv.held = {"id": "crystal_veil_3", "count": 1}
	inv.request("click", ["inv", 0])
	inv.request("stow", [0])
	dummy.position = player.position + Vector2(900, 0)
	await get_tree().process_frame
	spells.debug_recharge()
	var spider: ShadowSpider = (load("res://src/entities/enemies/shadow_spider.tscn") as PackedScene).instantiate() as ShadowSpider
	spider.position = player.position + Vector2(50, 0)
	add_child(spider)
	await _wait(0.2)
	check(spider._find_target() == player, "a spider sees her")
	check(spells.try_cast(player.position + Vector2(0, -18)), "the veil cast starts (pointer on herself)")
	check(player._busy_kind == "cast_veil", "she plays the veil cast")
	await _wait(0.6)
	check(player.veiled(), "she is veiled")
	check(player.get_node_or_null("VeilFx") != null, "the mist shows on her")
	check(spider._find_target() == null and not spider._target_valid(), "the spider can neither pick nor keep her")
	check(get_children().any(func(n: Node) -> bool: return n is VeilGhost), "IRRSPUR leaves a mist double")
	var sprite_mat: ShaderMaterial = player.get_node("Sprite2D").material as ShaderMaterial
	check(float(sprite_mat.get_shader_parameter("veil")) > 0.5, "her picture dissolves into mist")
	await _wait(6.0)
	check(not player.veiled() and spider._find_target() == player, "when it ends she can be seen again")
	check(float(sprite_mat.get_shader_parameter("veil")) < 0.01, "and her picture is whole")
	spider.queue_free()
	player.health.set_health(player.health.max_health)
	remove_from_group("world")
	# ---- Leerenschlund: the price, the pull, the bite, life back
	inv.request("rclick", ["inv", 0])
	inv.request("stow", [0])
	inv.held = {"id": "crystal_maw_5", "count": 1}
	inv.request("click", ["inv", 0])
	inv.request("stow", [0])
	await get_tree().process_frame
	spells.debug_recharge()
	player.health.set_health(4.0)
	check(not spells.try_cast(player.position + Vector2(60, 0)), "too weak to pay: no cast")
	player.health.set_health(player.health.max_health * 0.8)
	var before: float = player.health.current
	dummy.position = player.position + Vector2(80, 14)
	dummy_health.heal_full()
	await get_tree().physics_frame
	full = dummy_health.current
	check(spells.try_cast(player.position + Vector2(64, 0)), "the maw cast starts")
	check(player._busy_kind == "cast_maw", "she plays the maw cast")
	await _wait(0.6)
	var maw: VoidMaw = null
	for child: Node in get_children():
		if child is VoidMaw:
			maw = child as VoidMaw
	check(maw != null, "the ground tears open")
	var paid: float = player.health.current
	check(paid <= before - 6.0, "the void took its price (%.1f -> %.1f)" % [before, paid])
	await _wait(3.4)
	check(dummy_health.current < full - 20.0, "the maw bit the dummy (%.1f of %.1f)" % [dummy_health.current, full])
	check(player.health.current > paid + 3.0, "life flowed back to her (%.1f -> %.1f)" % [paid, player.health.current])
	await _wait(1.2)
	check(not is_instance_valid(maw), "the tear closes and is gone")
	# ---- Hunger V: the maw bites twice
	inv.slots[0] = {"id": "staff_hag_elm", "count": 1, "sp": "crystal_maw_1", "gm": "gem_hunger_5"}
	inv.request("select", [0, 0])
	await get_tree().process_frame
	await get_tree().process_frame
	spells.debug_recharge()
	player.health.set_health(player.health.max_health)
	dummy.position = player.position + Vector2(64, 4)
	dummy_health.heal_full()
	await get_tree().physics_frame
	full = dummy_health.current
	check(spells.try_cast(player.position + Vector2(64, 0)), "the hungry maw opens")
	await _wait(0.5 + float(SpellRules.params("crystal_maw_1", "gem_hunger_5")["seconds"]) + 0.25)
	var after_first: float = dummy_health.current
	await _wait(0.6)
	check(after_first < full and dummy_health.current < after_first, "a second bite follows the first (%.1f -> %.1f -> %.1f)" % [full, after_first, dummy_health.current])
	await _wait(1.5)
	# ---- Dunst V: the mist cloud keeps her veiled after the veil itself has run out
	inv.slots[0] = {"id": "staff_hag_elm", "count": 1, "sp": "crystal_veil_1", "gm": "gem_haze_5"}
	inv.request("select", [0, 0])
	await get_tree().process_frame
	await get_tree().process_frame
	spells.debug_recharge()
	dummy.position = player.position + Vector2(900, 0)
	check(spells.try_cast(player.position + Vector2(0, -18)), "the veil with Dunst V")
	await _wait(0.7)
	var cloud_stream: VeilStream = null
	for child: Node in get_children():
		if child is VeilStream:
			cloud_stream = child as VeilStream
	check(cloud_stream != null and cloud_stream.get_node_or_null("Cloud") != null, "NEBELWAND: a mist cloud lies where the veil fell")
	await _wait(float(SpellRules.params("crystal_veil_1", "gem_haze_5")["seconds"]) + 0.4)
	check(player.veiled(), "standing in the cloud she stays veiled after the veil ran out")
	player.position += Vector2(200, 0)
	await _wait(1.6)
	check(not player.veiled(), "out of the cloud the mist leaves her")
	player.position -= Vector2(200, 0)
	# ---- the Bleichgabel: two prongs, socketed by the half of the icon, cast with LMB / RMB, GABELSCHLAG
	dummy.position = player.position + Vector2(900, 0)
	inv.slots[0] = {"id": "staff_bone_fork", "count": 1}
	inv.request("select", [0, 0])
	inv.held = {"id": "crystal_banish_1", "count": 1}
	inv.request("click", ["inv", 0, 1]) ## laid on the lower half: the short prong
	var fork: Dictionary = inv.slots[0]
	check(SpellRules.spell_in(fork, 1) == "crystal_banish_1" and SpellRules.spell_in(fork, 0) == "", "the lower half of the icon fills the short prong")
	inv.held = {"id": "crystal_banish_2", "count": 1}
	inv.request("click", ["inv", 0]) ## no half named: the first empty prong
	check(SpellRules.spell_in(fork, 0) == "crystal_banish_2", "without a half the first empty prong takes it")
	inv.held = {"id": "gem_lens_1", "count": 1}
	inv.request("click", ["inv", 0, 1])
	check(SpellRules.gem_in(fork, 1) == "gem_lens_1" and SpellRules.gem_in(fork, 0) == "", "a gem goes into its prong's bezel")
	check(Items.extras(fork).has("sp2") and Items.extras(fork).has("gm2"), "the second prong travels with the staff")
	inv.request("rclick", ["inv", 0, 1])
	check(String(inv.held.get("id", "")) == "crystal_banish_1" and SpellRules.spell_in(fork, 1) == "", "right click on the lower half takes the short prong's crystal")
	inv.request("click", ["inv", 0, 1])
	check(SpellRules.spell_in(fork, 1) == "crystal_banish_1" and inv.held.is_empty(), "and back in")
	await get_tree().process_frame
	await get_tree().process_frame
	check(spells.prongs == 2 and spells.spell_of(1) == "crystal_banish_1" and spells.gem_of(1) == "gem_lens_1" and spells.bond == "harmony", "the host knows both prongs and their GLEICHKLANG")
	spells.debug_recharge()
	check(spells.is_ready(0) and spells.is_ready(1), "both crystals full")
	check(spells.try_cast(player.position + Vector2(30, 0), 0), "the long prong casts")
	await _wait(0.9)
	check(not spells.is_ready(0) and spells.is_ready(1), "only the long prong is empty")
	check(is_equal_approx(spells.charge_total, float(SpellRules.params("crystal_banish_2")["cooldown"]) * 0.85), "GLEICHKLANG: it charges 15 % faster")
	var struck: Array[float] = [0.0]
	spells.fork_struck.connect(func(_prong: int, power: float) -> void: struck[0] = power)
	check(spells.try_cast(player.position + Vector2(30, 0), 1), "the short prong casts (right button)")
	check(player.cast_prong() == 1, "the cast knows its prong")
	await _wait(0.6)
	check(is_equal_approx(struck[0], 1.25), "GABELSCHLAG: the other prong in time comes out 25 % stronger (%.2f)" % struck[0])
	var strong: BanishLight = null
	for child: Node in get_children():
		if child is BanishLight and float((child as BanishLight).params.get("power", 1.0)) > 1.0:
			strong = child as BanishLight
	check(strong != null and float(strong.params["dps"]) > float(SpellRules.params("crystal_banish_1", "gem_lens_1")["dps"]), "the struck light burns hotter")
	check(not spells.is_ready(0) and not spells.is_ready(1), "both prongs charge")
	await _wait(9.0)
	# ---- a thrown staff keeps its stones
	var drop: ItemDrop = DROP.instantiate() as ItemDrop
	drop.item_id = "staff_hag_elm"
	drop.sockets = {"sp": "crystal_roots_1", "gm": "gem_wild_5"}
	add_child(drop)
	await get_tree().process_frame
	check(String(drop._stack.get("sp", "")) == "crystal_roots_1", "a thrown staff keeps its crystals")
	# ---- the cards
	var card: ItemTooltip = ItemTooltip.new()
	add_child(card)
	card.show_stack(staff, false)
	check(card._rows.any(func(r: Dictionary) -> bool: return String(r["type"]) == "socket"), "the staff's card shows its sockets")
	card.show_stack({"id": "crystal_banish_5", "count": 1}, false)
	check(card._rows.any(func(r: Dictionary) -> bool: return String(r["type"]) == "stone"), "a crystal's card shows its picture")
	if failures == 0:
		print("MAGIC OK (%d checks)" % checks)
	else:
		print("MAGIC FAILED: %d of %d" % [failures, checks])
	get_tree().quit(1 if failures > 0 else 0)
