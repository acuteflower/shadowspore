extends Node
## Godot --headless --path . tools/test_hexenwald_mist.tscn
## The Hexenwald's mist (docs/hexenwald_nebel_konzept.md): the host keeps HALLUZINIERT on a heroine in the wood and nowhere else, the Ohrringe der Klarheit clear
## it, a hallucinating heroine draws no map, what she sees (eyes, false finds, a lying vine, the phantom spider) never costs her anything and falls apart.
const CENTRE: Vector2 = Vector2(821, 892) * 16.0
const HUT: Vector2 = Vector2(786, 676) * 16.0
var failures: int = 0
var checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MIST: " + label)


func _run() -> void:
	var item: Dictionary = DataRegistry.get_entry("items", "clarity_earrings")
	check(String(item.get("jewelry", "")) == "earrings" and String(item.get("rarity", "")) == "rare" and (item.get("perks", []) as Array).has("clear_sight"), "the Ohrringe der Klarheit are rare earrings with the perk")
	check(float((item["bonus"] as Dictionary)["absorb"]) <= 0.05 and ResourceLoader.exists(String(item["icon"])), "weak stats, an icon")
	check(TalismanRules.perks([{"id": "clarity_earrings", "count": 1}]).has("clear_sight"), "the catalogue knows the perk")
	var def: Dictionary = StatusEffects.definition("hallucinated")
	check(bool(def.get("permanent", false)) and float(def["damage_ratio"]) == 0.0 and int(def["min_damage"]) == 0, "the effect lasts and does no damage")
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var hero: Player = world._players.get_child(0) as Player
	hero.progress.claimed = 25
	hero.progress.apply_stats(false)
	var effects: StatusEffects = hero.effects
	# where the mist is
	hero.global_position = HUT
	effects._breathe_mist()
	check(not effects.has("hallucinated"), "no effect at the town")
	hero.global_position = CENTRE
	effects._breathe_mist()
	check(effects.has("hallucinated"), "the wood's mist puts the effect on her")
	var seen: Hallucinations = hero.get_node_or_null("Hallucinations") as Hallucinations
	check(seen != null, "her own machine makes the hallucinations")
	var health: float = hero.health.current
	effects._physics_process(120.0) ## far past its time without a refresh
	check(not effects.has("hallucinated") and hero.health.current == health, "it fades by itself and never ticks damage")
	await get_tree().process_frame
	check(hero.get_node_or_null("Hallucinations") == null, "the hallucinations go with it")
	# the map
	effects._breathe_mist()
	var discovery: MapDiscovery = world.get_node("MapDiscovery") as MapDiscovery
	var before: int = discovery.seen_count()
	discovery._timer = 0.0
	discovery._process(1.0)
	check(discovery.seen_count() == before, "a hallucinating heroine draws no map")
	# what she sees
	seen = hero.get_node("Hallucinations") as Hallucinations
	seen._process(45.0)
	check(seen.trug > 0.45 and seen.trug <= 1.0, "trug grows with the time in the mist (%.2f)" % seen.trug)
	seen._see_eyes(hero)
	seen._see_decoy(hero)
	seen._see_whisper(hero)
	check(seen._eye_left.size() >= 1 and is_instance_valid(seen._decoy), "eyes open and a false find lies there")
	seen._decoy.global_position = hero.global_position
	seen._tend(hero, 0.1)
	check(seen._decoy == null, "the false find falls apart when she reaches for it")
	var vines: Array[Node] = get_tree().get_nodes_in_group("sap_vines")
	seen._see_lie(hero)
	var lying: int = 0
	for vine: Node in vines:
		lying += 1 if (vine as SapVine).lie >= 0.0 else 0
	check(vines.is_empty() or lying == 1, "one vine lies (%d of %d)" % [lying, vines.size()])
	seen._tend(hero, 5.0)
	lying = 0
	for vine: Node in vines:
		lying += 1 if (vine as SapVine).lie >= 0.0 else 0
	check(lying == 0, "and tells the truth again")
	# the phantom
	seen._see_phantom(hero)
	var phantom: PhantomSpider = seen.phantom
	check(is_instance_valid(phantom) and phantom.get_node_or_null("Hurtbox") == null and not phantom.is_in_group("predators"), "a phantom spider with no body to hit")
	var steps: Array[int] = []
	var gone: Array[bool] = [false]
	phantom.vanished.connect(func() -> void: gone[0] = true)
	for i: int in 400:
		if not is_instance_valid(phantom) or gone[0]:
			break
		if steps.is_empty() or steps[steps.size() - 1] != int(phantom.step):
			steps.append(int(phantom.step))
		phantom._process(0.05)
	check(steps == [0, 1, 2, 3, 4] and gone[0], "it rises, stalks, winds up, strikes and is gone (%s)" % str(steps))
	check(hero.health.current == health, "its blow costs nothing")
	await get_tree().process_frame
	# the earrings
	hero.inventory.give("clarity_earrings", 1)
	for i: int in InventoryComponent.SIZE:
		if String((hero.inventory.slots[i] as Dictionary).get("id", "")) == "clarity_earrings":
			hero.inventory.request("equip", [i, ""])
	check(hero.talismans.perks.has("clear_sight"), "she wears the Ohrringe der Klarheit")
	effects._breathe_mist()
	check(not effects.has("hallucinated"), "they clear her head at once")
	effects._breathe_mist()
	check(not effects.has("hallucinated"), "and the mist cannot take it again")
	discovery._timer = 0.0
	discovery._process(1.0)
	check(discovery.seen_count() > before, "with a clear head the wood is drawn on the map")
	world.queue_free()
	await get_tree().process_frame
	print("MIST: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
