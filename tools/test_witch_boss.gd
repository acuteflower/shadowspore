extends Node
## Headless check of Morwenna's fight (docs/enemies/boss_mora.md): she falls out of the crown, every act of every phase runs to its end and back to
## idle, both phase turns bring a clone, a blow can make her swap with a clone, a struck clone crumbles and forms again, heavy damage breaks the leech,
## her death frees the tree, and an empty hollow resets the fight.
## `Godot --headless --path . --fixed-fps 60 tools/test_witch_boss.tscn` (prints `WITCH BOSS OK`)

const ACTS: Array = [["resin", "tide", "prowl", "lance", "spray", "feint"], ["pincer", "shards", "burrow", "cage"], ["carousel", "leech", "frenzy", "split", "swarm"]]

var _world: WorldLevel
var _player: Player
var _arena: WitchArena
var _boss: MirrorWitch
var _fight: MirrorWitchFight
var _hurt: int = 0
var _failed: bool = false
var _checks: int = 0
var _phantom_marks: int = 0 ## frames in which a clone's cracked warning was on the floor


func _ready() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	print("WITCH BOSS: FAILED - ", message)
	get_tree().quit(1)


func _check(ok: bool, message: String) -> bool:
	_checks += 1
	if not ok:
		_fail(message)
	return ok


func _until(cond: Callable, frames: int) -> bool:
	for i: int in frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame


func _seen_phantom() -> bool:
	for z: Dictionary in _fight.field._zones:
		if int(z["kind"]) == MirrorWitchFight.PHANTOM:
			_phantom_marks += 1
			break
	return true


func _calm() -> bool:
	return _fight.mode == MirrorWitchFight.Mode.IDLE


func _hit(amount: float, knock: float = 0.0) -> void:
	_boss.get_node("HealthComponent").take_damage(amount, _player.global_position, knock, _player.name.to_int())


## Lets only `act` be chosen next and waits for it to start and end.
func _play_act(act: String) -> bool:
	if not await _until(_calm, 60 * 12):
		_fail("not idle before %s (mode %d)" % [act, _fight.mode])
		return false
	_fight._spec["rotation"] = [[act], [act], [act]]
	_fight._gap = 0.0
	var want: int = int(MirrorWitchFight.ACT_NAMES[act])
	if not await _until(func() -> bool: return _fight.mode == MirrorWitchFight.Mode.ACT and int(_fight.act) == want, 60 * 4):
		_fail("%s did not start (mode %d act %d, clones %d)" % [act, _fight.mode, _fight.act, _fight.clones_on()])
		return false
	if act == "leech": ## enough damage while she drinks: she staggers
		await _wait(60)
		_hit(_boss.max_health() * 0.08)
		if not await _until(func() -> bool: return _fight.mode == MirrorWitchFight.Mode.STAGGER, 30):
			_fail("the leech was not broken")
			return false
	if not await _until(func() -> bool: return _seen_phantom() and _fight.mode in [MirrorWitchFight.Mode.RECOVER, MirrorWitchFight.Mode.IDLE, MirrorWitchFight.Mode.STAGGER] and _fight.act == MirrorWitchFight.Act.NONE, 60 * 16):
		_fail("%s never ended (mode %d)" % [act, _fight.mode])
		return false
	_checks += 1
	print("  act %-9s ok  (hits on her so far: %d)" % [act, _hurt])
	return true


## Takes her down to the next third and waits for the phase turn.
func _turn(to_phase: int) -> bool:
	await _until(_calm, 60 * 10)
	var floor_hp: float = _boss.health_floor()
	_hit(_boss.health_now() - floor_hp + 50.0)
	if not _check(absf(_boss.health_now() - floor_hp) < 1.0, "health did not hold at the third (%.1f vs %.1f)" % [_boss.health_now(), floor_hp]):
		return false
	if not await _until(func() -> bool: return _fight.phase == to_phase and _fight.mode == MirrorWitchFight.Mode.IDLE, 60 * 8):
		_fail("no turn to phase %d (phase %d mode %d)" % [to_phase, _fight.phase, _fight.mode])
		return false
	await _wait(40)
	return _check(_fight.clones_on() == to_phase, "phase %d has %d clones" % [to_phase, _fight.clones_on()])


func _run() -> void:
	_world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _world._players.get_child(0) as Player
	_player.health.floor_value = 1.0
	_player.health.damaged.connect(func(_a: float, _f: Vector2, _k: float) -> void: _hurt += 1)
	_arena = _world.witch_arena
	if not _check(_arena != null, "no WitchArena in the world"):
		return
	_player.global_position = _arena.tree_position() + Vector2(0, 150)
	# locked: before Esma's request nothing happens at the tree
	await _wait(150)
	_check(_arena.stage == WitchArena.Stage.CALM and not _arena.opened, "the tree woke before the quest opened the hollow")
	var quests: QuestComponent = _player.quests
	_check(not quests.is_active("spiegelhexe"), "the quest started without the workshop / level 5")
	quests._done.append("town_workshop")
	_player.progress.award(0, 100000)
	if not await _until(func() -> bool: return quests.active_step_id("spiegelhexe") == "sh_valdric", 90):
		return _fail("the quest did not start at level %d" % _player.progress.level)
	print("  quest start ok (level %d)" % _player.progress.level)
	var steps: Array = (DataRegistry.get_entry("quests", "spiegelhexe").steps as Array)
	for k: int in steps.size():
		var ev: String = String((steps[k] as Dictionary).get("event", ""))
		if ev.contains(":") and not ev.begins_with("story:") and not ev.begins_with("bark:"):
			_check(false, "unknown event %s" % ev)
		if ev.begins_with("story:") or ev.begins_with("bark:"):
			_check(not DataRegistry.get_entry("dialogue", ev.get_slice(":", 1)).is_empty(), "missing dialogue %s" % ev)
		if String((steps[k] as Dictionary).id) == "sh_tree":
			quests._active["spiegelhexe"] = k ## Esma has asked
	for item: String in ["mora_shard", "clarity_earrings"]:
		_check(not DataRegistry.get_entry("items", item).is_empty(), "missing item %s" % item)
	# the prelude: now stepping near the tree wakes three spiders and seals the hollow
	if not await _until(func() -> bool: return _arena.stage == WitchArena.Stage.PRELUDE, 240):
		return _fail("no prelude near the tree after Esma's request (opened %s)" % _arena.opened)
	await _wait(2)
	_check(quests.active_step_id("spiegelhexe") == "sh_fight", "finding the tree did not advance the quest (%s)" % quests.active_step_id("spiegelhexe"))
	_check(_arena.sealed, "the gates did not close")
	_check(_arena._spiders.size() == 3, "%d spiders instead of 3" % _arena._spiders.size())
	_check(not _arena._bodies.is_empty(), "no gate colliders")
	await _wait(10)
	_check(_arena._bodies[0].collision_layer == 1, "a gate is not solid while sealed")
	_check(_arena.blocks_climb(_player.global_position, _player.global_position + Vector2(0, 40)), "a climb is not refused while sealed")
	print("  prelude ok: 3 spiders, %d gates sealed" % _arena._bodies.size())
	await _wait(60)
	for spider: Node in _arena._spiders.duplicate():
		(spider.get_node("HealthComponent") as HealthComponent).kill(_player.global_position, _player.name.to_int())
	if not await _until(func() -> bool: return _arena.boss_present(), 60 * 8):
		return _fail("the spiders died but she never came (stage %d)" % _arena.stage)
	_check(_arena.stage == WitchArena.Stage.BOSS and _arena.sealed, "not sealed during the fight")
	print("  threshold ok: she comes after the last spider")
	_boss = _arena.boss
	_fight = _boss.fight
	_fight._spec = _fight._spec.duplicate(true) ## the test changes the rotation; never the shared data
	_check(_fight.mode == MirrorWitchFight.Mode.ENTRANCE, "not in the entrance")
	_check(_fight.field.on_floor(_player.global_position), "the player's spot is not on the hollow's floor")
	var landed: Array[bool] = [false]
	_boss.touched_down.connect(func() -> void: landed[0] = true)
	if not await _until(_calm, 60 * 12):
		return _fail("the entrance never ended (mode %d)" % _fight.mode)
	_check(landed[0], "touched_down never fired")
	_check(_fight.clones_on() == 0, "a clone in phase 1")
	print("  entrance ok")

	for act: String in ACTS[0]:
		if not await _play_act(act):
			return
	if not await _turn(1):
		return
	print("  turn 1 ok: DER SPIEGEL ZERBRICHT, one clone")

	# the swap: struck while idle, she may change places with the clone
	_fight._spec["swap"] = {"chance": 1.0, "cooldown": 7.0}
	_fight._swap_cd = 0.0
	await _until(_calm, 60 * 10)
	_fight._gap = 99.0
	var before: Vector2 = _fight._pos[0]
	var clone_at: Vector2 = _fight._pos[1]
	_hit(5.0)
	await _wait(1)
	_check(_fight._pos[0].distance_to(clone_at) < 14.0 and _fight._pos[1].distance_to(before) < 14.0, "no swap with the clone")
	print("  swap ok")
	# a blade through the clone: it crumbles and forms again
	await _wait(60)
	_fight.clone_struck(1, _player.global_position)
	await _wait(2)
	_check(_fight.clones_on() == 0, "the struck clone did not crumble")
	if not await _until(func() -> bool: return _fight.clones_on() == 1, 60 * 6):
		return _fail("the clone never formed again")
	print("  clone poof + return ok")
	_fight._gap = 0.5

	for act: String in ACTS[1]:
		if not await _play_act(act):
			return
	if not await _turn(2):
		return
	_check(is_instance_valid(_boss.tree) and _boss.tree.hour > 0.5, "the tree did not turn to the witch hour")
	print("  turn 2 ok: DIE HEXENSTUNDE, two clones")
	for act: String in ACTS[2]:
		if not await _play_act(act):
			return
	_check(_hurt > 0, "no act ever hurt the player")
	_check(_phantom_marks > 60, "the clones hardly ever attacked on their own (%d frames with a cracked warning)" % _phantom_marks)
	print("  clone attacks ok (%d frames with a cracked warning)" % _phantom_marks)

	# the end: she is released, the tree is free
	await _until(_calm, 60 * 10)
	_hit(_boss.health_now() + 10.0)
	if not await _until(func() -> bool: return not is_instance_valid(_boss) or _boss.is_queued_for_deletion(), 60 * 10):
		return _fail("she never went (mode %d)" % _fight.mode)
	_check(_arena.released, "the arena does not know she was released")
	_check(not _arena.sealed, "the gates stayed closed after the release")
	_check(_player.quests.active_step_id("spiegelhexe") == "sh_shard", "the release did not advance the quest (%s)" % _player.quests.active_step_id("spiegelhexe"))
	_player.inventory.give("mora_shard", 1)
	if not await _until(func() -> bool: return _player.quests.active_step_id("spiegelhexe") == "sh_back", 60 * 2):
		return _fail("the shard did not advance the quest")
	print("  quest ok: tree found, Mora released, shard -> back to Esma")
	_check(bool(_arena.export_state().get("released", false)), "the release is not saved")
	await _wait(60 * 2)
	_check(_arena.stage == WitchArena.Stage.FREE and get_tree().get_nodes_in_group("bosses").is_empty(), "something woke again after the release")
	_check(_world.get_node("CrowTree").liberated, "the tree is not liberated")
	print("  release ok")

	# the hologram: it stands after the release, E calls her back (no spiders), the tree darkens while she fights
	if not await _until(func() -> bool: return _arena._hologram.active and _arena._hologram.prompt() != "", 60 * 6):
		return _fail("no hologram after the release")
	_check(not _arena._hologram.map_marker().is_empty(), "the hologram has no map marker")
	_arena._hologram.interact(_player)
	if not await _until(func() -> bool: return _arena.boss_present(), 60 * 4):
		return _fail("the hologram did not call her back")
	_check(_arena._spiders.is_empty(), "the rematch woke spiders")
	_check(not _world.get_node("CrowTree").liberated, "the tree is still free during the rematch")
	_check(bool(_arena.export_state().get("released", false)), "a rematch lost the saved release")
	await _wait(30)
	_check(not _arena._hologram.active and _arena.sealed, "hologram still there / not sealed in the rematch")
	print("  hologram + rematch ok")
	# reset: nobody is left in the hollow
	_player.global_position = _arena.tree_position() + Vector2(0, 900)
	if not await _until(func() -> bool: return not _arena.boss_present(), 60 * 14):
		return _fail("the empty hollow did not reset the fight")
	await _wait(10)
	_check(not _arena.sealed and _arena.stage == WitchArena.Stage.FREE, "the reset did not open the gates (stage %d)" % _arena.stage)
	_check(_world.get_node("CrowTree").liberated, "the tree was not freed again after the reset")
	_player.global_position = _arena.tree_position() + Vector2(0, 150)
	if not await _until(func() -> bool: return _arena._hologram.active, 60 * 3):
		return _fail("the hologram did not come back after the reset")
	print("  reset ok")
	print("WITCH BOSS OK (%d checks, %d hits taken)" % [_checks, _hurt])
	get_tree().quit(0)
