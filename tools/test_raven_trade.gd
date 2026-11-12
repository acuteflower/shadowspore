extends Node
## The raven trade (docs/raetsel_konzept.md 4, rare) in the real world with the real heroine: it comes down to her, junk goes back into her bag and
## it turns away, a shiny thing is taken as a pawn (the rest of the stack comes back), three feather stations (pick, it flies on), waiting too long
## sends it home and it resumes there, it sits on its mound, E digs out a Mondsiegeltruhe that holds the pawn, three junk offers make it ignore her.
## Run: Godot --headless --path . --fixed-fps 60 tools/test_raven_trade.tscn   (prints RAVEN TRADE OK)

var _ok: bool = true


func check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("RAVEN TRADE FAILED: ", what)


func _ready() -> void:
	_run.call_deferred()


func _until(seconds: float, cond: Callable) -> bool:
	var t: float = 0.0
	while t < seconds:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return bool(cond.call())


func _offer(hoard: CrowHoard, item: String, count: int, player: Player) -> void:
	player.inventory.remove_item(item, count)
	hoard.offer_box().slots[0] = {"id": item, "count": count}
	hoard.offer_box().touch()
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	Engine.time_scale = 3.0
	var world: WorldLevel = (load("res://src/world/world_level.tscn") as PackedScene).instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var puzzles: Puzzles = Puzzles.of(get_tree())
	var id: String = puzzles.first_of("raven_trade") if puzzles != null else ""
	check(id != "", "puzzles.json places a raven trade")
	if id == "":
		_finish()
		return
	var hoard: CrowHoard = puzzles.trial(id) as CrowHoard
	var chests: LootChests = LootChests.of(get_tree())
	var player: Player = world._players.get_child(0) as Player
	var peer: int = player.name.to_int()
	player.intro = null
	player.story_lock = false
	check(hoard.raven and hoard.station_count() == 3, "a raven with three feather stations")
	player.inventory.give("stone", 2)
	player.inventory.give("lake_glimmer", 2)

	# it comes down to her when she stands still near its snag
	player.global_position = hoard.snag_position() + Vector2(0, 70)
	player.velocity = Vector2.ZERO
	var came: bool = await _until(15.0, func() -> bool: return hoard.state == CrowHoard.State.GROUND)
	check(came, "standing still near its snag brings the raven down")
	check(hoard.spot_prompt("crow") == "ANBIETEN", "it waits for an offer")

	# junk: back into the bag, it turns away
	await _offer(hoard, "stone", 2, player)
	check(hoard.state == CrowHoard.State.REFUSE, "it refuses a plain stone")
	check(player.inventory.count_item("stone") == 2, "the stone is back in her bag")
	await _until(4.0, func() -> bool: return hoard.state == CrowHoard.State.GROUND)

	# a shiny thing: one piece taken as a pawn, the rest comes back
	await _offer(hoard, "lake_glimmer", 2, player)
	check(hoard.state == CrowHoard.State.EAT and hoard.pawn == "lake_glimmer", "it takes the glimmer as a pawn")
	check(player.inventory.count_item("lake_glimmer") == 1, "only one piece is taken")

	# the feathers
	for i: int in 3:
		var at: bool = await _until(40.0, func() -> bool: return hoard.state == CrowHoard.State.WAIT and hoard.dropped == i + 1)
		check(at, "it waits at station %d with a feather down" % (i + 1))
		player.global_position = hoard.feather_position(i) + Vector2(0, 20)
		await _until(2.0, func() -> bool: return false)
		check(hoard.spot_prompt("feather%d" % i) == "FEDER AUFHEBEN", "the feather at station %d can be picked" % (i + 1))
		if i == 1: ## waiting too long: it goes home and resumes from there
			var home: bool = await _until(70.0, func() -> bool: return hoard.state == CrowHoard.State.PERCH)
			check(home, "left waiting it flies home")
			player.global_position = hoard.snag_position() + Vector2(0, 40)
			var back: bool = await _until(40.0, func() -> bool: return hoard.state == CrowHoard.State.WAIT)
			check(back and hoard.dropped == 2 and hoard.feathers == 1, "back at its snag it leads on to the same station")
			player.global_position = hoard.feather_position(i) + Vector2(0, 20)
		hoard._host_feather(peer, i)
		check(hoard.feathers == i + 1, "feather %d picked up" % (i + 1))
	var dig: bool = await _until(40.0, func() -> bool: return hoard.state == CrowHoard.State.DIG)
	check(dig and hoard.revealed, "after the last feather it sits on its mound")
	player.global_position = hoard.mound_position() + Vector2(0, 24)
	await _until(1.0, func() -> bool: return false)
	check(hoard.state == CrowHoard.State.DIG, "the raven stays on its hoard while she comes")
	var saved: Dictionary = hoard.export_progress()
	check(String(saved.get("pawn", "")) == "lake_glimmer", "the pawn is kept in the save")

	# dig: a Mondsiegeltruhe with the pawn
	hoard._host_hand_dig(peer)
	await get_tree().process_frame
	check(puzzles.is_solved(id), "digging solves it")
	var chest: LootChest = chests.chest("trial_" + id)
	check(chest != null and chest.tier == "rare" and chest.rise, "a rare chest breaks out of the earth")
	check((chests._extra.get("trial_" + id, []) as Array).size() == 1, "the pawn waits inside the chest")
	await _until(2.0, func() -> bool: return false)
	player.global_position = chest.global_position + Vector2(0, 16)
	await _until(0.5, func() -> bool: return false)
	chests.request_open("trial_" + id)
	await _until(3.0, func() -> bool: return false)
	check(not chests._extra.has("trial_" + id), "opening pays out the pawn")
	var found: bool = false
	for node: Node in get_tree().get_nodes_in_group("drops"):
		for drop: Node in node.get_children():
			if drop is ItemDrop and String((drop as ItemDrop).get("item_id")) == "lake_glimmer":
				found = true
	check(found or player.inventory.count_item("lake_glimmer") >= 2, "the glimmer came back out of the chest")

	# three junk offers in a day: it ignores her
	puzzles.debug_reset(id)
	await get_tree().process_frame
	player.global_position = hoard.snag_position() + Vector2(0, 70)
	for k: int in 3:
		await _until(20.0, func() -> bool: return hoard.state == CrowHoard.State.GROUND)
		await _offer(hoard, "stone", 1, player)
	check(hoard.state == CrowHoard.State.HOME, "the third junk offer sends it home")
	await _until(8.0, func() -> bool: return false)
	check(hoard.state == CrowHoard.State.PERCH and hoard.interest < 0.01, "and it ignores her for the rest of the day")
	Engine.time_scale = 1.0
	_finish()


func _finish() -> void:
	print("RAVEN TRADE OK" if _ok else "RAVEN TRADE FAILED")
	get_tree().quit(0 if _ok else 1)
