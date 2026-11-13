extends Node
## The root weave (Wurzelgeflecht, docs/raetsel_konzept.md 6a) in the trials' test world (TrialLevel) with the real heroine: the rules agree with
## tools/check_root_weave.py (shortest 3 / 7 / 12), a thorn cannot be pressed, a touch with Ellie's palms switches the cube and its root ends, a seed
## grows its cubes, withdrawing takes everything back, every weave is solved by its shortest solution and brings its chest, progress survives
## export/import, the test world is never saved and the kit is in the bag.
## Run: Godot --headless --path . --fixed-fps 60 tools/test_root_weave.tscn   (prints ROOT WEAVE OK)

var _ok: bool = true


func check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("ROOT WEAVE FAILED: ", what)


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


func _idle(w: RootWeave) -> bool:
	return w._events.is_empty() and w._lock <= 0.0


func _run() -> void:
	Engine.time_scale = 4.0
	var world: Node2D = (load("res://src/world/trial_level.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var puzzles: Puzzles = Puzzles.of(get_tree())
	var player: Player = (world.get("_players") as Node).get_child(0) as Player
	player.intro = null
	player.story_lock = false
	check(not SaveGame.save(get_tree(), "user://test_root_weave_save.json"), "the test world is never saved")
	check(player.inventory.has_item("hoe_basic") and player.inventory.count_item("dusk_berry") >= 12, "the kit is in her bag")
	for kind: String in ["wisp", "crow_hoard", "raven_trade", "root_weave"]:
		check(puzzles.first_of(kind) != "", "the test world holds a %s" % kind)
	var want: Dictionary = {"weave_keimling": 3, "weave_geflecht": 7, "weave_altes_geflecht": 12}
	var weaves: Dictionary = {}
	for id: String in want:
		var w: RootWeave = puzzles.trial(id) as RootWeave
		check(w != null, "weave %s is built" % id)
		if w == null:
			continue
		weaves[id] = w
		var path: Array = w.rules.solution()
		check(path.size() == int(want[id]), "%s: shortest solution %d, wanted %d (%s)" % [id, path.size(), int(want[id]), path])
		check(not w.active and w.cube_prompt(w.rules.heart) == "LÖSCHEN", "%s sleeps: the heart offers LÖSCHEN" % id)
	if not _ok:
		_finish()
		return

	# the rare weave: start, a thorn, Ellie's touch, a seed growing, withdrawing
	var rare: RootWeave = weaves["weave_geflecht"] as RootWeave
	rare._ask("start", -1)
	check(rare.active and rare._cubes[rare.rules.heart].shown == 1, "LÖSCHEN puts the heart out")
	await _until(8.0, func() -> bool: return _idle(rare))
	var a: int = rare.rules.bit_of("A")
	check(rare._cubes[a].rise >= 1.0 and rare.cube_prompt(a) == "BERÜHREN", "the first cubes rose and can be touched")
	var t: int = rare.rules.bit_of("T")
	var before: int = rare.lit
	rare._ask("press", t)
	check(rare.lit == before, "a thorn cannot be pressed")
	check(rare.cube_hint(t) == "DORNEN", "a thorn says why")
	player.global_position = rare.global_position + rare._cubes[a].position + Vector2(0, 18)
	await get_tree().process_frame
	var expect: int = before
	for j: int in rare.rules.reach(a, rare.pres):
		expect ^= 1 << j
	rare.cube_used(a, player)
	await _until(4.0, func() -> bool: return rare.lit != before)
	check(rare.lit == expect, "her palms switch A and the cubes its roots reach")
	await _until(6.0, func() -> bool: return _idle(rare) and not player.is_busy())
	var f: int = rare.rules.bit_of("F")
	var g: int = rare.rules.bit_of("G")
	if not WeaveRules.has(rare.lit, f):
		rare._ask("press", f)
		await _until(8.0, func() -> bool: return _idle(rare))
	check(WeaveRules.has(rare.pres, g) and rare._cubes[g].rise >= 1.0 and rare._cubes[f].opened, "the lit seed F grew G and the thorn I, and opened")
	rare._ask("withdraw", -1)
	await _until(4.0, func() -> bool: return not rare.active)
	check(not rare.active and rare.pres == 0 and rare._cubes[a].rise <= 0.0 and rare._cubes[rare.rules.heart].shown == 0, "ZURÜCKZIEHEN takes the weave back")

	# progress survives export/import
	rare._ask("start", -1)
	await _until(8.0, func() -> bool: return _idle(rare))
	rare._ask("press", rare.rules.bit_of("B"))
	await _until(6.0, func() -> bool: return _idle(rare))
	var saved: Dictionary = rare.export_progress()
	rare.reset_trial()
	rare.import_progress(saved)
	check(rare.active and rare.lit == int(saved["l"]) and rare.pres == int(saved["p"]), "export/import keeps the weave")
	rare._ask("withdraw", -1)
	await _until(4.0, func() -> bool: return not rare.active)

	# every weave by its shortest solution: solved, a chest out of the earth
	var chests: LootChests = LootChests.of(get_tree())
	for id: String in want:
		var w: RootWeave = weaves[id] as RootWeave
		w._ask("start", -1)
		await _until(10.0, func() -> bool: return _idle(w))
		for cid: Variant in w.rules.solution():
			w._ask("press", w.rules.bit_of(String(cid)))
			check(w._lock > 0.0, "%s: press %s accepted" % [id, cid])
			await _until(10.0, func() -> bool: return _idle(w))
		check(w.done and w.rules.solved(w.lit, w.pres), "%s is solved by its shortest solution" % id)
		var came: bool = await _until(8.0, func() -> bool: return puzzles.is_solved(id) and chests.chest("trial_" + id) != null)
		check(came, "%s brings its chest" % id)
		check(w._cubes[w.rules.heart].shown == 2, "%s: the heart turned gold" % id)
		check(w.cube_prompt(w.rules.heart) == "", "%s: a solved weave offers nothing" % id)
		if w.rules.crown >= 0:
			check(w._cubes[w.rules.crown].shown == 4, "%s: the crown blooms" % id)
	_finish()


func _finish() -> void:
	print("ROOT WEAVE OK" if _ok else "ROOT WEAVE FAILED")
	Engine.time_scale = 1.0
	get_tree().quit(0 if _ok else 1)
