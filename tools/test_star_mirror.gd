extends Node
## The star mirror (Sternenspiegel, docs/raetsel_konzept.md 6b) in the trials' test world with the real heroine: the reflection mirrors and turns,
## faint stars and lines follow the moon, E lifts a stone (her carry sheet, slow, no sprint), a stone set down near a free star settles on it,
## one beside nothing or in the water does not, a carrier who falls drops it, progress survives export/import, every figure solves (decoys stay
## over) and brings its chest.
## Run: Godot --headless --path . --fixed-fps 60 tools/test_star_mirror.tscn   (prints STAR MIRROR OK)

var _ok: bool = true


func check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("STAR MIRROR FAILED: ", what)


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


func _wait(seconds: float) -> void:
	await _until(seconds, func() -> bool: return false)


## She walks up to stone `i`, lifts it, carries it to `to` and sets it down there (through the host's checks, as E would).
func _carry(m: StarMirror, player: Player, i: int, to: Vector2) -> void:
	var stone: StarStone = m._stones[i]
	player.global_position = stone.global_position + Vector2(0, 14)
	await get_tree().process_frame
	m.stone_used(stone, player)
	await _until(3.0, func() -> bool: return player.carry_stone != 0 and player._carry_anim < 0.0)
	player.global_position = to + Vector2(0, 14)
	await get_tree().process_frame
	m._ask("drop", i, to)
	await _until(3.0, func() -> bool: return player.carry_stone == 0)


func _run() -> void:
	Engine.time_scale = 3.0
	var world: Node2D = (load("res://src/world/trial_level.tscn") as PackedScene).instantiate() as Node2D
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var puzzles: Puzzles = Puzzles.of(get_tree())
	var player: Player = (world.get("_players") as Node).get_child(0) as Player
	player.intro = null
	player.story_lock = false
	var ids: Array = ["stars_sichel", "stars_rabe", "stars_waechterin"]
	var mirrors: Array[StarMirror] = []
	for id: String in ids:
		var m: StarMirror = puzzles.trial(id) as StarMirror
		check(m != null, "%s is built" % id)
		if m == null:
			_finish()
			return
		mirrors.append(m)
		check(m._stones.size() >= m.stars.size(), "%s has a stone for every star" % id)
	check(mirrors[2]._stones.size() - mirrors[2].stars.size() >= 2, "the legendary figure has decoys")

	# the reflection: mirrored, turning with the night
	TimeManager.set_time(TimeManager.NIGHT_START + 0.001)
	var s0: StarMirror = mirrors[0]
	var r: Vector2 = s0.reflect_point(Vector2(0.2, 0.3))
	check(r.x > 0.0 and r.y < 0.0, "x mirror: a star on the left of the field lies on the right in the water (%s)" % r)
	var leg: StarMirror = mirrors[2]
	var d0: Vector2 = leg.reflect_point(Vector2(0.2, 0.8))
	check(d0.x > 0.0 and d0.y < 0.0, "diag mirror swaps the axes at dusk (%s)" % d0)
	TimeManager.set_time(0.0)
	var d1: Vector2 = leg.reflect_point(Vector2(0.2, 0.8))
	check(d0.angle_to(d1) != 0.0 and absf(d0.length() / 1.0 - d1.length()) < 40.0, "the reflection has turned by midnight")
	TimeManager.day = 0
	check(not leg.lines_visible() and not leg.star_visible(4), "new moon: no lines, faint stars hidden")
	TimeManager.day = 4
	check(leg.lines_visible() and leg.star_visible(4), "full moon: lines and every star")
	check(s0.star_visible(0) and s0.lines_visible(), "the common figure always shows")

	# carrying: lift, slow, no sprint, set down
	var stone: StarStone = s0._stones[0]
	player.global_position = stone.global_position + Vector2(0, 14)
	await get_tree().process_frame
	check(s0.stone_prompt(stone) == "AUFHEBEN", "a lying stone offers AUFHEBEN")
	s0.stone_used(stone, player)
	await get_tree().process_frame
	check(player.carry_stone != 0 and stone.carrier == player.name.to_int(), "E lifts it into her arms")
	await _until(2.0, func() -> bool: return player._carry_anim < 0.0)
	check(player._sheet == Player.CARRY_STONE_ID, "she shows the carry sheet")
	check(s0.stone_prompt(stone) == "ABLEGEN", "the carried stone offers ABLEGEN")
	check(not player.attack.visible, "no weapon while she carries")
	s0._ask("drop", 0, s0._pond + Vector2(0, 4))
	await get_tree().process_frame
	check(stone.carrier != 0, "not into the water")
	var near: Vector2 = s0.star_position(2) + Vector2(6, -5)
	player.global_position = near + Vector2(0, 14)
	await get_tree().process_frame
	s0._ask("drop", 0, near)
	await _until(3.0, func() -> bool: return player.carry_stone == 0)
	check(stone.on_star == 2 and stone.global_position == s0.star_position(2), "set down near a free star it settles on it")
	check(player._sheet != Player.CARRY_STONE_ID, "she lets go and the normal sheet comes back")
	await _carry(s0, player, 1, s0.star_position(2) + Vector2(3, 2))
	check(s0._stones[1].on_star == -1, "a star already taken takes no second stone")
	await _carry(s0, player, 1, s0._field + Vector2(-70, -70))
	check(s0._stones[1].on_star == -1, "beside nothing a stone stays dark")

	# a carrier who falls drops it
	s0.stone_used(s0._stones[3], player)
	player.global_position = s0._stones[3].global_position + Vector2(0, 14)
	await get_tree().process_frame
	s0.stone_used(s0._stones[3], player)
	await _until(2.0, func() -> bool: return player.carry_stone != 0)
	player.health.current = 0.0
	await _until(2.0, func() -> bool: return s0._stones[3].carrier == 0)
	check(s0._stones[3].carrier == 0, "a carrier who falls drops the stone")
	player.health.current = player.health.max_health
	await _until(3.0, func() -> bool: return player.carry_stone == 0)

	# progress survives export/import
	var saved: Dictionary = s0.export_progress()
	s0.reset_trial()
	check(s0._stones[0].on_star == -1, "reset takes the stones back")
	s0.import_progress(saved)
	check(s0._stones[0].on_star == 2, "import puts a stone back on its star")

	# every figure: cover its stars (the decoys stay where they are)
	var chests: LootChests = LootChests.of(get_tree())
	for m: StarMirror in mirrors:
		m.reset_trial()
		await get_tree().process_frame
		for i: int in m.stars.size():
			await _carry(m, player, i, m.star_position(i) + Vector2(4, 3))
			check(m._stones[i].on_star == i, "%s: stone %d on star %d" % [m.id, i, i])
		check(m.done, "%s: every star covered solves it" % m.id)
		var came: bool = await _until(10.0, func() -> bool: return puzzles.is_solved(m.id) and chests.chest("trial_" + m.id) != null)
		check(came, "%s brings its chest" % m.id)
		check(m.stone_prompt(m._stones[m._stones.size() - 1]) == "", "%s: a solved mirror offers nothing" % m.id)
	_finish()


func _finish() -> void:
	print("STAR MIRROR OK" if _ok else "STAR MIRROR FAILED")
	Engine.time_scale = 1.0
	get_tree().quit(0 if _ok else 1)
