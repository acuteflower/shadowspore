extends Node
## Headless check of the first phase of the fight with Mornath (docs/boss_sky_cleaver.md): the opening (feathers in the ways down, solid), the coverage of the rain,
## the damage of every act, the end of the phase (the health holds at the third, the boss rests on the pillar, the pillar breaks, he falls, the finisher, the next phase),
## and the reset when nobody is left. `Godot --headless --path . --fixed-fps 60 tools/test_boss_fight.tscn`
var _world: WorldLevel
var _player: Player
var _boss: SkyCleaver
var _fight: MornathFight
var _origin: Vector2
var _hurt: int = 0
var _failed: bool = false


func _ready() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	print("BOSS FIGHT: FAILED - ", message)
	get_tree().quit(1)


func _check(ok: bool, message: String) -> bool:
	if not ok and not _failed:
		_failed = true
		_fail(message)
	return ok


## Waits until `cond` is true (at most `frames` physics frames).
func _until(cond: Callable, frames: int) -> bool:
	for i: int in frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _wait(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame


func _idle() -> bool:
	return _fight.mode == MornathFight.Mode.IDLE and _boss.state == SkyCleaver.State.PERCHED


func _force(kind: int, a: Vector2 = Vector2.ZERO, b: Vector2 = Vector2.ZERO, n: int = 0) -> void:
	_fight._gap = 99.0
	_fight._rpc_act.rpc(kind, 11, a, b, n, 1.0)


func _run() -> void:
	_world = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(_world)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = _world._players.get_child(0) as Player
	var spec: Dictionary = (DataRegistry.table("ground").get("arenas", []) as Array)[0] as Dictionary
	var tile: Array = spec.tile as Array
	_origin = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
	_player.health.floor_value = 1.0
	_player.health.damaged.connect(func(_a: float, _f: Vector2, _k: float) -> void: _hurt += 1)
	for i: int in 30:
		await get_tree().physics_frame
	_player.global_position = _origin + Vector2(20, -40)
	if not await _until(func() -> bool: return not get_tree().get_nodes_in_group("bosses").is_empty(), 120):
		return _fail("no boss")
	_boss = get_tree().get_nodes_in_group("bosses")[0] as SkyCleaver
	_fight = _boss.fight
	if not _check(_fight != null and _boss.field != null, "no fight node"):
		return

	# --- the opening: feathers in the ways down
	if not await _until(func() -> bool: return _fight.barrier_done, 60 * 25):
		return _fail("the opening never finished (mode %d state %d)" % [_fight.mode, _boss.state])
	var stuck: Array[StuckFeather] = []
	for node: Node in _boss.get_parent().get_children():
		if node is StuckFeather:
			stuck.append(node as StuckFeather)
	if not _check(stuck.size() == 16, "expected 16 stuck feathers, found %d" % stuck.size()):
		return
	var space: PhysicsDirectSpaceState2D = _boss.get_world_2d().direct_space_state
	for line: Array in [[Vector2(-16, 140), Vector2(-16, 70)], [Vector2(-34, 138), Vector2(-34, 80)], [Vector2(-2, 140), Vector2(-2, 80)], [Vector2(-180, -128), Vector2(-132, -128)], [Vector2(-180, -150), Vector2(-132, -150)], [Vector2(-180, -108), Vector2(-132, -108)]]:
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(_origin + (line[0] as Vector2), _origin + (line[1] as Vector2), 1)
		if not _check(not space.intersect_ray(query).is_empty(), "a way down is open: ray %s -> %s" % [line[0], line[1]]):
			return
	print("opening: ", stuck.size(), " feathers, ways blocked")

	# --- the coverage of the rain: about 60 % of the floor, never all of it
	for script_index: int in MornathFight.RAIN_SCRIPTS.size():
		for wave: Array in MornathFight.RAIN_SCRIPTS[script_index] as Array:
			var cover: float = _fight.wave_coverage(String(wave[0]), int(wave[1]), float(wave[2]))
			print("  rain script ", script_index, " ", wave, " covers ", snappedf(cover, 0.01))
			if not _check(cover > 0.4 and cover < 0.75, "rain wave %s covers %f of the floor" % [wave, cover]):
				return

	# --- the field hurts exactly what it announces
	await _until(_idle, 60 * 6)
	_fight._gap = 99.0
	var before: int = _hurt
	var spot: Vector2 = _player.global_position
	var now: float = _boss.field.now()
	_boss.field.add_ring(spot + Vector2(120, 0), 20.0, 0.0, now, now + 0.2, 10.0) ## far from her
	_boss.field.add_ring(spot, 20.0, 0.0, now, now + 0.2, 10.0)
	await _until(func() -> bool: return _hurt > before, 60)
	if not _check(_hurt == before + 1, "a zone round her hurt %d times" % (_hurt - before)):
		return
	print("field: hurts what it announces")
	_player.health.heal_full()
	await _wait(60)

	# --- every act hurts someone who stands still in it
	for entry: Array in [["shot", MornathFight.Act.SHOT], ["line", MornathFight.Act.LINE], ["chase", MornathFight.Act.CHASE], ["rain", MornathFight.Act.RAIN]]:
		await _until(_idle, 60 * 30)
		_player.global_position = _origin + Vector2(20, -40)
		await _wait(20)
		_hurt = 0
		_force(int(entry[1]), _player.global_position, Vector2.ZERO, int(_player.name))
		if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.ACTING, 60):
			return _fail("%s never started" % entry[0])
		if not await _until(_idle, 60 * 40):
			return _fail("%s never ended (mode %d state %d)" % [entry[0], _fight.mode, _boss.state])
		print("act ", entry[0], ": hurt ", _hurt, " times")
		if entry[0] != "rain" and not _check(_hurt >= 1, "%s did not hurt somebody who stood still" % entry[0]):
			return
		_player.health.heal_full()
	# the wing blast: she clings to the pillar
	await _until(_idle, 60 * 30)
	_player.global_position = _boss.global_position + Vector2(0, 24)
	_hurt = 0
	_force(MornathFight.Act.BLAST)
	await _until(_idle, 60 * 12)
	print("act blast: hurt ", _hurt, " times")
	if not _check(_hurt >= 1, "the blast did not hurt somebody at the pillar"):
		return
	_player.health.heal_full()

	# --- the end of the phase
	await _until(_idle, 60 * 12)
	_player.global_position = _origin + Vector2(20, -40)
	var floor_value: float = _boss.health_floor()
	_boss._health.take_damage(100000.0, _player.global_position, 0.0, int(_player.name))
	await _wait(5)
	if not _check(absf(_boss.health_now() - floor_value) < 0.01 and floor_value > 0.6667 * _boss.max_health(), "the health did not hold at the third: %f (floor %f)" % [_boss.health_now(), floor_value]):
		return
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.REST, 60 * 12):
		return _fail("never rested (mode %d state %d)" % [_fight.mode, _boss.state])
	var pillar: ArenaPillar = _boss.pillar(1)
	if not _check(_boss.perched_on() == 1 and pillar.is_armed() and _boss.invulnerable, "not resting on the right pillar"):
		return
	_boss._health.take_damage(50.0, _player.global_position, 0.0, 1)
	_boss._hurtbox.take_hit(50.0, _player.global_position, 0.0, 1)
	await _wait(5)
	if not _check(_fight.mode == MornathFight.Mode.REST, "a blow on the resting boss ended the rest"):
		return
	print("rest: on pillar 1, health ", _boss.health_now())
	var hits: int = 0
	while not pillar.broken and hits < 30:
		pillar.take_hit(9.0, _player.global_position)
		hits += 1
		await _wait(6)
	if not _check(pillar.broken or _fight.mode != MornathFight.Mode.REST, "the pillar never broke after %d hits" % hits):
		return
	print("pillar broke after ", hits, " hits")
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.DOWNED, 60 * 5):
		return _fail("never fell (mode %d)" % _fight.mode)
	if not _check(_boss.state == SkyCleaver.State.ACT and _boss.puppet_height < 1.0 and _boss.act_hittable, "not down on the ground"):
		return
	_boss._hurtbox.take_hit(5.0, _player.global_position, 0.0, 1)
	var cut_to: float = 0.64 * _boss.max_health()
	if not await _until(func() -> bool: return _fight.phase == 1, 60 * 6):
		return _fail("the finisher never led to the next phase (mode %d)" % _fight.mode)
	if not _check(_fight.mode == MornathFight.Mode.TRANSITION, "no transition after the finisher (mode %d)" % _fight.mode):
		return
	if not await _until(func() -> bool: return _boss.health_now() < 0.6667 * _boss.max_health(), 60 * 6):
		return _fail("the transition never cut the health")
	if not _check(absf(_boss.health_now() - cut_to) < 1.0, "the transition left the health at %f" % _boss.health_now()):
		return
	if not _check(absf(_boss.health_floor() - (0.3333 * _boss.max_health() + 0.5)) < 0.01, "the next third is not held: floor %f" % _boss.health_floor()):
		return
	print("finisher: health ", _boss.health_now(), " floor ", _boss.health_floor())
	if not await _until(func() -> bool: return _fight.rift != null and is_instance_valid(_fight.rift), 60 * 6):
		return _fail("the rift never opened")
	if not _check(_boss.corruption() > 0.99, "the look did not turn: %f" % _boss.corruption()):
		return
	print("transition: rift open, corruption ", _boss.corruption())
	if not await _until(_idle, 60 * 14):
		return _fail("never went on after the finisher (mode %d state %d)" % [_fight.mode, _boss.state])
	if not _check(not _boss.invulnerable and _boss.pillar_broken(1) and _boss.perched_on() != 1, "after the finisher: invulnerable %s, perched on %d" % [_boss.invulnerable, _boss.perched_on()]):
		return
	_fight._gap = 0.2
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.ACTING or _fight.mode == MornathFight.Mode.MOVING, 60 * 8):
		return _fail("the fight did not go on in the second phase")
	print("second phase goes on")
	if not await _phase_two():
		return

	# --- everybody gone: the fight resets
	var boss_id: int = _boss.get_instance_id()
	_player.global_position = _origin + Vector2(1800, 1800)
	if not await _until(func() -> bool: return not is_instance_valid(instance_from_id(boss_id)) or (instance_from_id(boss_id) as Node).is_queued_for_deletion(), 60 * 14):
		return _fail("the boss was not removed when everybody left")
	await _wait(10)
	var leftover: int = 0
	for node: Node in _world._enemies.get_children():
		if node is StuckFeather:
			leftover += 1
	if not _check(leftover == 0, "%d stuck feathers left after the reset" % leftover):
		return
	var pillar1: ArenaPillar = null
	for node: Node in get_tree().get_nodes_in_group("arena_pillars"):
		if (node as ArenaPillar).index == 1:
			pillar1 = node as ArenaPillar
	if not _check(pillar1 != null and not pillar1.broken, "the pillar did not stand again"):
		return
	_player.health.heal_full()
	await _wait(5)
	_player.global_position = _origin + Vector2(20, -40)
	if not await _until(func() -> bool: return not get_tree().get_nodes_in_group("bosses").is_empty(), 60 * 3):
		return _fail("the arena did not wake again")
	var again: SkyCleaver = get_tree().get_nodes_in_group("bosses")[0] as SkyCleaver
	if not _check(again.start_phase == 1 and again.corruption() > 0.99, "the new fight did not start at phase 2 (start_phase %d)" % again.start_phase):
		return
	if not _check(again.health_now() < 0.66 * again.max_health(), "the new fight starts with health %f" % again.health_now()):
		return
	print("reset: the arena is armed again, the fight restarts at phase 2")
	print("BOSS FIGHT: ok")
	get_tree().quit(0)


## Phase 2: the rift is solid and hurts, the new acts hurt who stands still, the judgement kills on failure and ends in success when the pillar breaks.
func _phase_two() -> bool:
	var rift: RiftWall = _fight.rift
	var a: Vector2 = rift.middle()
	var normal: Vector2 = rift.normal()
	var side_a: Vector2 = a + normal * 40.0
	var side_b: Vector2 = a - normal * 40.0
	# solid: a segment from one side to the other is blocked, and a gap opens it
	if not _check(rift.blocks(side_a, side_b), "the rift does not block"):
		return false
	_fight._rpc_rift_gap.rpc(0.5)
	await _wait(int(60.0 * 1.4))
	if not _check(not rift.blocks(side_a, side_b), "the gap did not open the rift"):
		return false
	await _wait(60 * 5)
	if not _check(rift.blocks(side_a, side_b), "the gap did not close again"):
		return false
	print("rift: solid, breathes")
	# the new acts
	for entry: Array in [["pincer", MornathFight.Act.PINCER], ["hands", MornathFight.Act.HANDS], ["cage", MornathFight.Act.CAGE], ["rain", MornathFight.Act.RAIN], ["chase", MornathFight.Act.CHASE], ["blast", MornathFight.Act.BLAST]]:
		if not await _until(_idle, 60 * 30):
			_fail("not idle before %s (mode %d state %d)" % [entry[0], _fight.mode, _boss.state])
			return false
		_player.health.heal_full()
		_player.global_position = (_boss.global_position + Vector2(0, 26)) if entry[0] == "blast" else (_origin + Vector2(20, -40))
		await _wait(20)
		_hurt = 0
		_force(int(entry[1]), _player.global_position, Vector2.ZERO, int(_player.name))
		if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.ACTING, 60):
			_fail("%s never started" % entry[0])
			return false
		if not await _until(_idle, 60 * 40):
			_fail("%s never ended (mode %d state %d)" % [entry[0], _fight.mode, _boss.state])
			return false
		print("p2 act ", entry[0], ": hurt ", _hurt, " times")
		if entry[0] in ["pincer", "cage", "blast"] and not _check(_hurt >= 1, "%s did not hurt somebody who stood still" % entry[0]):
			return false
	# the end of the phase: the judgement
	if not await _until(_idle, 60 * 30):
		_fail("not idle before the judgement")
		return false
	_player.health.heal_full()
	_player.global_position = _origin + Vector2(20, -40)
	_boss._health.take_damage(100000.0, _player.global_position, 0.0, int(_player.name))
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.JUDGEMENT, 60 * 14):
		_fail("the judgement never began (mode %d)" % _fight.mode)
		return false
	var pillar: ArenaPillar = _boss.pillar(_fight._break_pillar)
	if not _check(_boss.perched_on() == 0 and pillar.is_armed(), "the judgement is not on the northern pillar"):
		return false
	if not _check(absf(pillar.max_integrity - 240.0) < 1.0, "pillar integrity %f" % pillar.max_integrity):
		return false
	print("judgement: began, pillar ", pillar.max_integrity)
	if OS.get_cmdline_user_args().has("--success"):
		return await _judgement_success(pillar)
	# failure: let the time run out by skipping ahead
	_fight._t = _fight.judge_total() - 0.05
	var died: bool = await _until(func() -> bool: return _player.health.current <= 0.0, 60 * 5)
	if not _check(died and _fight.judge_failed, "everybody should die when the time runs out"):
		return false
	print("judgement failed: the player died")
	return true


## The pillar of the judgement breaks in time: he falls, the finisher follows, the third phase is next, nobody died.
func _judgement_success(pillar: ArenaPillar) -> bool:
	var hits: int = 0
	while not pillar.broken and hits < 80:
		pillar.take_hit(9.0, _player.global_position)
		hits += 1
		await _wait(4)
	if not _check(pillar.broken and not _fight.judge_failed, "the judgement pillar did not break (hits %d)" % hits):
		return false
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.DOWNED, 60 * 5):
		_fail("he never fell after the judgement (mode %d)" % _fight.mode)
		return false
	if not _check(_player.health.current > 0.0, "somebody died although the pillar broke in time"):
		return false
	_boss._hurtbox.take_hit(5.0, _player.global_position, 0.0, 1)
	if not await _until(func() -> bool: return _fight.phase == 2, 60 * 6):
		_fail("the finisher did not lead to the third phase (mode %d)" % _fight.mode)
		return false
	if not await _until(func() -> bool: return _boss.health_now() < 0.32 * _boss.max_health(), 60 * 4):
		_fail("the finisher left the health at %f" % _boss.health_now())
		return false
	print("judgement: broken in time after ", hits, " hits, third phase next, health ", _boss.health_now())
	print("BOSS FIGHT: ok (success)")
	get_tree().quit(0)
	return false
