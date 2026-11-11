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
	_world.request_arena_boss(String(spec.id), _player.global_position) ## the story (knight / hologram) calls him; stepping onto the floor no longer does
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
	# --- Nebelschleier: a veiled player cannot be picked, but still counts as alive (no reset)
	_player.effects.apply("veil", 3.0, 1.0)
	await _wait(8)
	if not _check(_player.veiled() and _fight._seen().is_empty() and _fight._living().size() == 1 and _fight._pick_target() == null, "a veiled player can still be aimed at (seen %d living %d)" % [_fight._seen().size(), _fight._living().size()]):
		return
	_player.effects.clear("veil")
	await _wait(8)
	if not _check(_fight._pick_target() == _player, "the boss does not find her again after the veil"):
		return
	print("veil: the boss loses a veiled player and finds her again")

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
	_world.request_arena_boss(String(spec.id), _player.global_position)
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
	print("judgement: broken in time after ", hits, " hits, third phase next")
	return await _third_phase()


## The start of the third phase: he flies to the middle, the wave throws everybody to the end of the floor and takes a quarter of the health (never the last point),
## the scream turns the look and sets the floor and the last pillar on fire.
func _third_phase() -> bool:
	# a blow that cannot kill
	_player.health.set_health(10.0)
	_player.health.take_survivable(25.0, _origin, 0.0)
	await _wait(3)
	if not _check(absf(_player.health.current - 1.0) < 0.01, "a survivable blow left %f of 10 health" % _player.health.current):
		return false
	_player.health.take_survivable(25.0, _origin, 0.0)
	await _wait(3)
	if not _check(absf(_player.health.current - 1.0) < 0.01, "a survivable blow killed or changed health %f" % _player.health.current):
		return false
	_player.health.heal_full()
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.TRANSITION and _fight._final, 60 * 4):
		_fail("the third phase's transition never began (mode %d)" % _fight.mode)
		return false
	_player.global_position = _boss.arena_middle() + Vector2(30, 14)
	_player.health.heal_full()
	await _wait(2)
	var before: float = _player.global_position.distance_to(_boss.arena_middle())
	if not await _until(func() -> bool: return _fight._t > 2.05, 60 * 4):
		_fail("the transition's clock did not run")
		return false
	if not _check(_boss.puppet_pos.distance_to(_boss.arena_middle()) < 4.0, "he is not in the middle of the arena: %s" % _boss.puppet_pos):
		return false
	await _wait(60)
	var after: float = _player.global_position.distance_to(_boss.arena_middle())
	if not _check(after > before + 60.0, "the wave did not throw her to the end of the floor (%f -> %f)" % [before, after]):
		return false
	var left: float = _player.health.current
	if not _check(absf(left - 75.0) < 0.6 and left >= 1.0, "a quarter of the health should be gone: %f" % left):
		return false
	print("third phase: pushed ", snappedf(before, 0.1), " -> ", snappedf(after, 0.1), " px, health ", left)
	if not await _until(func() -> bool: return _fight._t > _fight._t3_scream + 1.7, 60 * 8):
		_fail("the scream never came")
		return false
	if not _check(_boss.fury() > 0.99, "the look did not turn: fury %f" % _boss.fury()):
		return false
	var last: ArenaPillar = _boss.pillar(2)
	if not _check(last != null and not last.broken and last.fury() > 0.99, "the last pillar does not burn"):
		return false
	var burning: int = 0
	for node: Node in get_tree().get_nodes_in_group("ground_glow"):
		var decal: GroundDecal = node as GroundDecal
		if decal != null and decal.decal_id == _boss.arena + "_arena" and decal.fury() > 0.99:
			burning += 1
	if not _check(burning == 1, "the floor does not burn (%d decals)" % burning):
		return false
	if not await _until(func() -> bool: return _fight.mode != MornathFight.Mode.TRANSITION, 60 * 8):
		_fail("the transition never ended")
		return false
	if not await _until(func() -> bool: return _boss.health_now() < 0.32 * _boss.max_health(), 60 * 2): ## cut when the card ends
		_fail("the transition left the health at %f" % _boss.health_now())
		return false
	if not _check(_boss.health_now() < 0.32 * _boss.max_health(), "health after the card: %f" % _boss.health_now()):
		return false
	print("third phase: the fire burns (floor, last pillar, look), health ", _boss.health_now())
	return await _third_phase_attacks()


## The attacks of phase 3: the long rain (seven waves, each covering a part of the floor), burning, the dive that finds a player who stands still and the dive that
## finds nobody (he is left open for longer).
func _third_phase_attacks() -> bool:
	var waves: Array = _fight._rain_waves_final()
	if not _check(waves.size() == 7, "the long rain has %d waves" % waves.size()):
		return false
	var kinds: PackedStringArray = PackedStringArray()
	for wave: Array in waves:
		var cover: float = _fight.wave_coverage(String(wave[0]), int(wave[1]), float(wave[2]), wave[3] as Vector2)
		kinds.append("%s %.2f" % [wave[0], cover])
		if not _check(cover > 0.3 and cover < 0.8, "wave %s covers %f of the floor" % [wave[0], cover]):
			return false
	print("long rain: ", ", ".join(kinds))
	# burning: a tick of damage every half second, nothing else happens to her, it can be put out
	if not await _until(_idle, 60 * 30):
		_fail("not idle before burning")
		return false
	_player.health.heal_full()
	await _wait(3)
	_player.effects.apply("burn", 0.0, 1.0, 0)
	await _wait(6)
	if not _check(_player.effects.has("burn"), "burn did not start"):
		return false
	var before: float = _player.health.current
	await _wait(75)
	if not _check(_player.health.current <= before - 3.0, "burning did not hurt: %f -> %f" % [before, _player.health.current]):
		return false
	_player.effects.clear("burn")
	await _wait(4)
	if not _check(not _player.effects.has("burn"), "burn could not be put out"):
		return false
	print("burn: ", before, " -> ", _player.health.current, " in 1.25 s")
	# the dive finds a player who stands still: damage and fire
	for round_name: String in ["hit", "miss"]:
		if not await _until(_idle, 60 * 30):
			_fail("not idle before the %s dive" % round_name)
			return false
		_player.health.heal_full()
		_player.effects.clear("burn")
		_player.global_position = _boss.arena_middle() + Vector2(70, 10)
		await _wait(10)
		_hurt = 0
		_force(MornathFight.Act.DIVE, _player.global_position, Vector2.ZERO, int(_player.name))
		var flags: Dictionary = {"burned": false}
		if round_name == "miss":
			if not await _until(func() -> bool: return bool(_fight._dive.get("committed", false)), 60 * 8):
				_fail("the dive never reached her")
				return false
			_player.global_position += Vector2(0, -120) ## a blink out of the grab
		var finished: bool = await _until(func() -> bool:
			if _player.effects.has("burn"):
				flags["burned"] = true
			return _fight.mode == MornathFight.Mode.IDLE and _boss.state == SkyCleaver.State.PERCHED and _fight.act == MornathFight.Act.NONE, 60 * 30)
		if not _check(finished, "the %s dive never ended (mode %d)" % [round_name, _fight.mode]):
			return false
		if round_name == "hit":
			if not _check(_hurt >= 1 and bool(flags["burned"]), "the grab did not hurt and burn her (hurt %d, burned %s)" % [_hurt, flags["burned"]]):
				return false
			if not _check(not bool(_fight._dive["whiff"]), "a grab that hit counted as a miss"):
				return false
		else:
			if not _check(_hurt == 0 and not bool(flags["burned"]), "the grab hit although she had gone (hurt %d)" % _hurt):
				return false
			if not _check(bool(_fight._dive["whiff"]), "a grab that found nobody did not leave him open"):
				return false
		print("dive ", round_name, ": hurt ", _hurt, ", burned ", flags["burned"])
	# the long rain itself
	if not await _until(_idle, 60 * 30):
		_fail("not idle before the long rain")
		return false
	_player.health.heal_full()
	_player.global_position = _boss.arena_middle() + Vector2(10, 10)
	await _wait(10)
	_hurt = 0
	_force(MornathFight.Act.RAIN, Vector2.ZERO, Vector2.ZERO, 0)
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.IDLE and _fight.act == MornathFight.Act.NONE and _boss.state == SkyCleaver.State.PERCHED, 60 * 40):
		_fail("the long rain never ended")
		return false
	if not _check(_hurt >= 1, "the long rain did not hurt somebody who stood still"):
		return false
	print("long rain: hurt ", _hurt, " times")
	return await _third_phase_new()


## One act of phase 3 against a player who stands at `at`; `watch` is called every frame and the act ends when he is idle again.
func _run_act(kind: int, at: Vector2, watch: Callable) -> bool:
	if not await _until(_idle, 60 * 40):
		_fail("not idle before act %d (mode %d)" % [kind, _fight.mode])
		return false
	_fight._gap = 99.0 ## (he must not choose an act of his own while she gets into place)
	_fight.blaze.clear_all()
	_player.health.heal_full()
	_player.effects.clear("burn")
	_player.global_position = at
	await _wait(70) ## (the trail needs a second of her standing there)
	_hurt = 0
	_force(kind, _player.global_position, Vector2.ZERO, int(_player.name))
	var done: bool = await _until(func() -> bool:
		watch.call()
		return _fight.mode == MornathFight.Mode.IDLE and _fight.act == MornathFight.Act.NONE and _boss.state == SkyCleaver.State.PERCHED, 60 * 40)
	if not done:
		_fail("act %d never ended (mode %d act %d)" % [kind, _fight.mode, _fight.act])
	return done


## The three new attacks (fire feathers, sky splinters, the brand mark), the burning rim and the last judgement.
func _third_phase_new() -> bool:
	var middle: Vector2 = _boss.arena_middle()
	var flags: Dictionary = {"fires": 0, "burned": false, "marked": false, "locked": false}
	# Glutfeld: three fields, the floor round the feather catches fire and sets her alight
	var glut_watch: Callable = func() -> void:
		flags["fires"] = maxi(int(flags["fires"]), _fight.blaze._fires.size())
		if _player.effects.has("burn"):
			flags["burned"] = true
	if not await _run_act(MornathFight.Act.GLUT, middle + Vector2(55, 10), glut_watch):
		return false
	if not _check(int(flags["fires"]) >= 3 and bool(flags["burned"]), "fire feathers: %d fields, burned %s" % [flags["fires"], flags["burned"]]):
		return false
	print("glut: ", flags["fires"], " fields, she burned: ", flags["burned"])
	# Himmelssplitter: five columns, a player who stands still is hit, the floor burns for a moment
	flags["fires"] = 0
	var split_watch: Callable = func() -> void:
		flags["fires"] = maxi(int(flags["fires"]), _fight.blaze._fires.size())
	if not await _run_act(MornathFight.Act.SPLITTER, middle + Vector2(-50, 30), split_watch):
		return false
	if not _check(_hurt >= 1 and int(flags["fires"]) >= 1, "sky splinters: hurt %d, fires %d" % [_hurt, flags["fires"]]):
		return false
	print("splitter: hurt ", _hurt, ", embers ", flags["fires"])
	# Brandmal: she stands still and is hit by the burst; the second time she leaves the ring after the lock and is not
	for round_name: String in ["stays", "runs"]:
		flags["marked"] = false
		flags["locked"] = false
		flags["burned"] = false
		var mark_watch: Callable = func() -> void:
			if _player.effects.has("brandmark"):
				flags["marked"] = true
			if _player.effects.has("burn"):
				flags["burned"] = true
			if round_name == "runs" and not bool(flags["locked"]) and (_fight._mark.get("point", Vector2.INF) as Vector2).is_finite():
				flags["locked"] = true
				var away: Vector2 = Vector2(0, -140)
				if not _boss.field.on_floor(_player.global_position + away):
					away = Vector2(0, 140)
				_player.global_position += away
		if not await _run_act(MornathFight.Act.MARK, middle + Vector2(0, 40), mark_watch):
			return false
		if not _check(bool(flags["marked"]), "the brand mark never showed as an effect"):
			return false
		if round_name == "stays":
			if not _check(_hurt >= 1 and bool(flags["burned"]), "the burst did not hurt and burn her (hurt %d)" % _hurt):
				return false
		else:
			if not _check(bool(flags["locked"]) and _hurt == 0, "she left the ring and was hurt anyway (hurt %d, locked %s)" % [_hurt, flags["locked"]]):
				return false
		if not _check(not _player.effects.has("brandmark"), "the mark was not taken off"):
			return false
		print("mark ", round_name, ": hurt ", _hurt)
	# the rim of the arena burns in the last fifth of his health
	_fight._gap = 99.0 ## (no acts of his own: their fire would burn in the middle)
	_fight.blaze.clear_all()
	_player.effects.clear("burn")
	_boss._health.set_health(_boss.max_health() * 0.15)
	if not await _until(func() -> bool: return _fight._edge_lit, 60 * 3):
		_fail("the rim did not catch fire at 15 % health")
		return false
	await _wait(60 * 2)
	var rect: Rect2 = _boss.field.floor_rect()
	var rim: Vector2 = Vector2.INF
	var inner: Vector2 = Vector2.INF
	var y: float = rect.position.y
	while y < rect.end.y:
		var x: float = rect.position.x
		while x < rect.end.x:
			var q: Vector2 = Vector2(x, y)
			if _boss.field.on_floor(q):
				if _fight.blaze.in_edge_band(q):
					if not rim.is_finite() or q.distance_to(middle) < rim.distance_to(middle):
						rim = q
				elif not inner.is_finite() or q.distance_to(middle) < inner.distance_to(middle):
					inner = q
			x += 6.0
		y += 6.0
	if not _check(rim.is_finite() and inner.is_finite(), "no rim or inner point found"):
		return false
	_player.global_position = rim
	await _wait(60 * 2)
	if not _check(_player.effects.has("burn"), "standing on the burning rim did not set her alight (edge %f host %s at %s, player %s, band %s)" % [_fight.blaze._edge, _fight.blaze.host, rim, _player.global_position, _fight.blaze.in_edge_band(_player.global_position)]):
		return false
	_player.effects.clear("burn")
	_player.global_position = inner
	await _wait(60 * 3)
	if not _check(not _player.effects.has("burn"), "she burns in the middle of the arena (at %s, band %s, edge %f, floor %f, fields %d, cold %d, left %f)" % [_player.global_position, _fight.blaze.in_edge_band(_player.global_position), _fight.blaze._edge, _fight.blaze._floor, _fight.blaze._fires.size(), _fight.blaze._cold.size(), _player.effects.left("burn")]):
		return false
	print("rim: burns at ", rim, ", not at ", inner)
	# the last judgement
	if not await _until(_idle, 60 * 40):
		_fail("not idle before the last judgement")
		return false
	_player.health.heal_full()
	_boss._health.take_damage(100000.0, _player.global_position, 0.0, int(_player.name))
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.JUDGEMENT, 60 * 14):
		_fail("the last judgement never began (mode %d)" % _fight.mode)
		return false
	var pillar: ArenaPillar = _boss.pillar(_fight._break_pillar)
	if not _check(pillar != null and pillar.is_armed() and _fight._break_pillar == 2, "the last judgement is not on the last pillar"):
		return false
	if not _check(absf(pillar.max_integrity - 420.0) < 1.0 and absf(_fight.judge_total() - 22.0) < 0.01, "judgement II: pillar %f, time %f" % [pillar.max_integrity, _fight.judge_total()]):
		return false
	if not _check(_fight.blaze.floor_on() and _fight.blaze.edge_on(), "the floor does not burn in the last judgement"):
		return false
	await _wait(60 * 3)
	var islands: Array = _fight.blaze._cold
	if not _check(islands.size() >= 2, "only %d cold islands" % islands.size()):
		return false
	var island: Vector2 = (islands[0] as Dictionary)["c"] as Vector2
	var hot_spot: Vector2 = middle + Vector2(0, 8)
	if _fight.blaze.cold_at(hot_spot):
		hot_spot = middle + Vector2(40, 8)
	_player.global_position = hot_spot
	_player.health.heal_full()
	var burned_floor: bool = await _until(func() -> bool: return _player.effects.has("burn"), 60 * 3)
	if not _check(burned_floor, "the burning floor did not set her alight in the last judgement"):
		return false
	_player.global_position = island
	var put_out: bool = await _until(func() -> bool: return not _player.effects.has("burn"), 60 * 2)
	if not _check(put_out and _fight.blaze.cold_at(island), "a cold island did not put the burning out"):
		return false
	print("judgement II: pillar ", pillar.max_integrity, ", time ", _fight.judge_total(), ", floor burns, ", islands.size(), " cold islands")
	var hits: int = 0
	while not pillar.broken and hits < 120:
		pillar.take_hit(9.0, _player.global_position)
		_player.health.heal_full()
		hits += 1
		await _wait(4)
	if not _check(pillar.broken and not _fight.judge_failed, "the last pillar did not break (hits %d)" % hits):
		return false
	if not await _until(func() -> bool: return _fight.mode == MornathFight.Mode.DOWNED, 60 * 5):
		_fail("he never fell after the last judgement (mode %d)" % _fight.mode)
		return false
	if not _check(_fight._last_stand and not _fight.blaze.floor_on() and _boss.health_floor() < 1.0, "the last stand is not set"):
		return false
	await _wait(60)
	_boss._hurtbox.take_hit(40.0, _player.global_position, 0.0, int(_player.name))
	await _wait(10)
	if not _check(_fight.mode == MornathFight.Mode.DOWNED, "a blow on the last stand started a finisher (mode %d)" % _fight.mode):
		return false
	_boss._health.take_damage(100000.0, _player.global_position, 0.0, int(_player.name))
	if not await _until(func() -> bool: return _boss._health.current <= 0.0, 60 * 2):
		_fail("he could not be killed in the last stand")
		return false
	print("last stand: he fell and died")
	print("BOSS FIGHT: ok (success)")
	get_tree().quit(0)
	return false
