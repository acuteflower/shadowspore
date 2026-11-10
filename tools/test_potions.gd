extends Node
## Special potions (docs/alchemie_konzept.md section 11): data, rules, brewing conditions and the real effects on a player. Headless: prints POTIONS OK.
const PLAYER: PackedScene = preload("res://src/entities/player/player.tscn")
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + label)


func _run() -> void:
	# ---- data: every tier of every type is an item with a recipe whose ingredients exist
	var items: Dictionary = DataRegistry.table("items")
	for type: String in AlchemyRules.TYPES:
		check(AlchemyRules.tier_count(type) == (3 if AlchemyRules.is_special(type) else 5), "tier count of " + type)
		for level: int in range(1, AlchemyRules.tier_count(type) + 1):
			var id: String = AlchemyRules.item_id(type, level)
			check(items.has(id), "item " + id)
			check(FileAccess.file_exists(String((items.get(id, {}) as Dictionary).get("icon", "")).replace("res://", "res://")), "icon of " + id)
			for ingredient: String in AlchemyRules.ingredients(type, level):
				check(items.has(ingredient), "%s needs %s which exists" % [id, ingredient])
			check(AlchemyRules.of(id).get("type", "") == type and int(AlchemyRules.of(id).get("tier", 0)) == level, "potion block of " + id)
			check(AlchemyRules.unlock_block(type, level, 100, {AlchemyRules.key(type, level - 1): 1}) == "", "unlockable " + id)
	check(AlchemyRules.tier_name(3, "ashen") == "MEISTERSUD" and AlchemyRules.tier_name(3) == "LEUCHTEND", "special tier names")
	check(AlchemyRules.pause_effect(items["potion_wisp_2"] as Dictionary) == "special_pause", "special pause")
	check(AlchemyRules.pause_effect(items["potion_stamina_2"] as Dictionary) == "", "Glutatem has no pause")
	# ---- own ways of brewing
	check(AlchemyRules.condition_block("ashen", false, 0.0, 0.0) != "" and AlchemyRules.condition_block("ashen", true, 0.0, 0.0) == "", "Aschenhaut needs the forge")
	check(AlchemyRules.condition_block("clarity", true, 0.0, 1.0) != "" and AlchemyRules.condition_block("clarity", false, 0.5, 0.0) == "", "Klarblick needs the dew")
	check(AlchemyRules.condition_block("wisp", true, 1.0, 0.1) != "" and AlchemyRules.condition_block("wisp", false, 0.0, 0.9) == "", "Irrlichtsud needs night")
	check(AlchemyRules.condition_block("heal", false, 0.0, 0.0) == "", "Wundtau has no condition")
	# ---- Glutatem really gives stamina during the pause (the first complaint)
	var player: Player = PLAYER.instantiate() as Player
	player.name = "1"
	add_child(player)
	await get_tree().process_frame
	player.stamina.spend(60.0)
	var before: float = player.stamina.current
	player.effects.apply("glutatem", 30.0, 5.0)
	for i: int in 70:
		await get_tree().physics_frame
	check(player.stamina.current >= before + 11.0, "Glutatem adds its pulse while the pause runs (%.1f -> %.1f)" % [before, player.stamina.current])
	player.effects.clear("glutatem")
	# ---- Aschenhaut
	player.effects.apply("ashen", 60.0, 3.0)
	await get_tree().process_frame
	check(player.effects.has("ashen") and player.effects.scale_of("ashen") == 3.0, "ashen applies")
	player.effects.apply("burn", 4.0, 1.0)
	await get_tree().process_frame
	check(not player.effects.has("burn"), "Aschenhaut III cannot be set alight")
	player.effects.clear("ashen")
	player.effects.apply("ashen", 60.0, 1.0)
	await get_tree().process_frame
	player.effects.apply("burn", 10.0, 1.0)
	var health: float = player.health.current
	for i: int in 70:
		await get_tree().physics_frame
	var with_skin: float = health - player.health.current
	player.effects.clear("ashen")
	player.effects.clear("burn")
	player.health.set_health(health)
	player.effects.apply("burn", 10.0, 1.0)
	for i: int in 70:
		await get_tree().physics_frame
	var bare: float = health - player.health.current
	check(bare > 0.0 and with_skin < bare, "Aschenhaut I takes burn damage down (%.0f against %.0f)" % [with_skin, bare])
	player.effects.clear("burn")
	# ---- Klarblick: the mist's hallucination goes and does not come back
	player.effects.apply("hallucinated")
	await get_tree().process_frame
	check(player.effects.has("hallucinated"), "hallucinated applies without the potion")
	player.effects.apply("clear_vision", 60.0, 2.0)
	player.effects.clear("hallucinated")
	await get_tree().process_frame
	player.effects._breathe_mist()
	await get_tree().process_frame
	check(player.effects.has("clear_vision") and not player.effects.has("hallucinated"), "Klarblick clears and holds off the hallucination")
	# ---- Irrlichtsud: the light slows a creature, tier III pushes it back
	var behavior: NightBehavior = NightBehavior.new()
	behavior.top_speed = 100.0
	var creature: Node2D = Node2D.new()
	add_child(creature)
	creature.global_position = player.global_position + Vector2(20.0, 0.0)
	var free: Vector2 = behavior.limit(creature, Vector2(-100.0, 0.0), 0.016)
	check(free.length() > 99.0, "without a wisp the creature walks freely")
	player.effects.apply("wisp", 45.0, 1.0)
	await get_tree().process_frame
	var slowed: Vector2 = behavior.limit(creature, Vector2(-100.0, 0.0), 0.016)
	check(slowed.length() < 70.0, "the wisp slows a creature in its radius (%.0f)" % slowed.length())
	player.effects.clear("wisp")
	player.effects.apply("wisp", 45.0, 3.0)
	await get_tree().process_frame
	var pushed: Vector2 = behavior.limit(creature, Vector2(-100.0, 0.0), 0.016)
	check(pushed.x > -20.0, "Irrlichtsud III pushes it back (%.0f)" % pushed.x)
	print("POTIONS %s (%d checks)" % ["OK" if failures == 0 else "FAILED", checks])
	get_tree().quit(1 if failures > 0 else 0)
