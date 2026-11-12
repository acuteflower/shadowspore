extends Node
## The crow's hoard (docs/raetsel_konzept.md 4) in the real world with the real heroine: no food = no interest, a sprint spooks it, sneaking with
## sun seeds lures it down, feeding takes one seed, it flies to its mound and scratches, she comes and it flies home, only the hoe digs, three
## blows bring a chest out of the earth, save/load and the dev reset.
## Run: Godot --headless --path . --fixed-fps 60 tools/test_crow_hoard.tscn   (prints CROW HOARD OK)

var _ok: bool = true


func check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("CROW HOARD FAILED: ", what)


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


func _put(player: Player, slot: int, item: String, count: int) -> void:
	player.inventory.slots[slot] = {"id": item, "count": count} if item != "" else {}
	player.inventory.selected = slot


func _run() -> void:
	Engine.time_scale = 3.0
	var world: WorldLevel = (load("res://src/world/world_level.tscn") as PackedScene).instantiate() as WorldLevel
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var puzzles: Puzzles = Puzzles.of(get_tree())
	var id: String = puzzles.first_of("crow_hoard") if puzzles != null else ""
	check(id != "", "puzzles.json places a crow's hoard")
	if id == "":
		_finish()
		return
	var hoard: CrowHoard = puzzles.trial(id) as CrowHoard
	var player: Player = world._players.get_child(0) as Player
	var peer: int = player.name.to_int()
	var snag: Vector2 = hoard.snag_position()
	check(snag.distance_to(hoard.mound_position()) > 20.0 * 16.0, "the mound lies at least 20 tiles away")
	player.intro = null
	player.story_lock = false

	# no food: nothing happens
	_put(player, 5, "", 0)
	player.global_position = snag + Vector2(0, 70)
	player.velocity = Vector2.ZERO
	await _until(2.0, func() -> bool: return false)
	check(hoard.state == CrowHoard.State.PERCH and hoard.interest < 0.01, "without food in hand it stays on its snag")

	# with seeds, standing still, sneaking: it comes down
	_put(player, 5, "sun_seed", 5)
	player.stealth.sneaking = true
	var came: bool = await _until(12.0, func() -> bool: return hoard.state == CrowHoard.State.GROUND)
	check(came, "sneaking with sun seeds lures it down (interest %.2f, state %d)" % [hoard.interest, hoard.state])
	check(hoard.target_peer == peer, "it offers itself to her")
	check(hoard.crow_position().distance_to(player.global_position) < 40.0, "it lands in front of her")

	# rushing right up to it sends it home
	var spot: Vector2 = player.global_position
	player.global_position = hoard.crow_position() + Vector2(0, 4)
	await get_tree().process_frame
	await get_tree().process_frame
	check(hoard.state == CrowHoard.State.HOME, "rushing up to it sends it back to its snag (state %d, d %.1f, crow %s, her %s)" % [hoard.state, player.global_position.distance_to(hoard.crow_position()), hoard.crow_position(), player.global_position])
	player.global_position = spot
	await _until(12.0, func() -> bool: return hoard.state == CrowHoard.State.GROUND)
	check(hoard.state == CrowHoard.State.GROUND, "after the fright it can be lured again")

	# feeding
	hoard._host_feed(peer)
	check(player.inventory.count_item("sun_seed") == 4, "feeding takes one seed")
	check(hoard.state == CrowHoard.State.EAT, "it eats")
	var led: bool = await _until(25.0, func() -> bool: return hoard.state == CrowHoard.State.DIG)
	check(led, "it caws and flies to its mound")
	check(hoard.revealed, "the mound is shown")
	check(hoard.crow_position().distance_to(hoard.mound_position()) < 20.0, "it scratches at the mound")

	# she comes: it flies home
	player.global_position = hoard.mound_position() + Vector2(0, 30)
	var home: bool = await _until(20.0, func() -> bool: return hoard.state == CrowHoard.State.DONE)
	check(home, "when she comes it flies home and rests")
	check(hoard.spot_prompt("mound") == "AUSGRABEN" and hoard.spot_hint("mound") == "", "E at the mound digs it out")
	hoard._host_hand_dig(peer)
	await get_tree().process_frame
	check(hoard.digs == 3 and puzzles.is_solved(id), "digging by hand solves it at once")
	var chests: LootChests = LootChests.of(get_tree())
	var chest: LootChest = chests.chest("trial_" + id)
	check(chest != null and chest.rise, "a chest breaks out of the earth")
	await _until(3.0, func() -> bool: return false)
	if chest != null:
		check(is_equal_approx(chest._body.scale.y, 1.0), "the chest stands full height after rising")

	# save, reset, load
	var saved: Dictionary = puzzles.export_state()
	puzzles.debug_reset(id)
	await get_tree().process_frame
	check(not hoard.revealed and hoard.state == CrowHoard.State.PERCH and chests.chest("trial_" + id) == null, "dev reset hides the hoard again")
	puzzles.import_state(saved)
	await get_tree().process_frame
	check(puzzles.is_solved(id) and chests.chest("trial_" + id) != null, "a save keeps it solved with its chest")
	puzzles.debug_reset(id)
	await get_tree().process_frame
	puzzles.import_state({"solved": [], "progress": {id: {"revealed": true}}})
	await get_tree().process_frame
	check(hoard.revealed and hoard.state == CrowHoard.State.DONE, "a shown but undug hoard stays shown after loading")
	Engine.time_scale = 1.0
	_finish()


func _finish() -> void:
	print("CROW HOARD OK" if _ok else "CROW HOARD FAILED")
	get_tree().quit(0 if _ok else 1)
