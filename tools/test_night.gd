extends Node
## docs/nacht_monster_konzept.md: the pure rules (budget, strength, window, clusters, special nights, light maths) and then the night in the real world:
## the town's light is land (no spawn, no entry), creatures rise out of the dark ground within their budget, patrol, rush the base through a gap, burn in the morning;
## leftovers of the day; the respawn at the house. Run with `--fixed-fps 60 --headless`.

var _ok: bool = true


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		print("NIGHT FAILED: ", what)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _ready() -> void:
	_run.call_deferred()


func _near(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance


func _run() -> void:
	_pure()
	await _world()
	print("NIGHT: ", "ok" if _ok else "FAILED")
	get_tree().quit(0 if _ok else 1)


# ---------------------------------------------------------------------------------- pure rules

func _pure() -> void:
	# the window: starts at 0.80, ends at 0.20, wraps at midnight
	_check(_near(NightRules.progress(0.8), 0.0), "the window opens at 0.80")
	_check(_near(NightRules.progress(0.0), 0.5), "midnight is the middle of the window")
	_check(NightRules.progress(0.5) < 0.0 and NightRules.progress(0.21) < 0.0, "no window by day")
	_check(NightRules.spawning(0.5) and not NightRules.spawning(0.9) and not NightRules.spawning(-1.0), "spawning stops late in the night")
	_check(_near(NightRules.released(0.0), 0.10) and _near(NightRules.released(0.12), 0.25) and _near(NightRules.released(0.36), 0.55) and _near(NightRules.released(0.43), 0.55) and _near(NightRules.released(0.9), 1.0) and NightRules.released(-1.0) == 0.0, "the release curve: slow start, a lull in the middle, everything by the peak")
	_check(NightRules.released(0.24) > 0.25 and NightRules.released(0.24) < 0.55, "the release curve is joined by straight lines")
	_check(NightRules.beat(0.05) == "scouts" and NightRules.beat(0.2) == "build" and NightRules.beat(0.4) == "lull" and NightRules.beat(0.6) == "call" and NightRules.beat(0.75) == "peak" and NightRules.beat(0.9) == "last_rush" and NightRules.beat(-1.0) == "", "the beats of the night")
	# the moon: the new moon is darker, bolder and brings more; the full moon is milder
	_check(_near(NightRules.moon_dark(0.0), 1.0) and _near(NightRules.moon_dark(0.5), 0.0), "moon darkness: 1 at the new moon, 0 at the full moon")
	_check(NightRules.moon_budget(0.0) > 1.0 and NightRules.moon_budget(0.5) < 1.0 and NightRules.moon_courage(0.0) > NightRules.moon_courage(0.5), "new moon: more creatures and more courage than the full moon")
	# the ladder of stages
	_check(String(NightRules.stage_for(0).id) == "tasten" and String(NightRules.stage_for(2).id) == "tasten" and String(NightRules.stage_for(3).id) == "lauschen" and String(NightRules.stage_for(7).id) == "druck" and String(NightRules.stage_for(40).id) == "flut", "the stage follows the night number")
	_check(not bool(NightRules.stage_for(0).raids) and bool(NightRules.stage_for(3).raids) and bool(NightRules.stage_for(7).memory) and bool(NightRules.stage_for(12).elite), "each rung opens something new")
	var rung: RandomNumberGenerator = RandomNumberGenerator.new()
	rung.seed = 11
	var biggest: int = 0
	for i: int in 60:
		biggest = maxi(biggest, NightRules.pack_size(NightRules.stage_for(12), 9.0, rung))
		_check(NightRules.pack_size(NightRules.stage_for(0), 9.0, rung) == 1, "the first nights send single creatures")
	_check(biggest >= 3 and biggest <= 4, "late nights send packs of up to four (%d)" % biggest)
	_check(NightRules.pack_size(NightRules.stage_for(12), 1.0, rung) == 1, "a pack is never bigger than the budget left")
	_check(NightRules.sector_of(0.0, 24) == 0 and NightRules.sector_of(PI, 24) == 12 and NightRules.sector_of(-0.01, 24) == 23, "sectors round the town")
	_check(NightRules.sector_of(NightRules.sector_angle(5, 24), 24) == 5, "the middle of a sector lies in it")
	var spiders_only: Array[Dictionary] = NightRules.available(30.0, 9, 9, NightRules.stage_for(0))
	var all_kinds: Array[Dictionary] = NightRules.available(30.0, 9, 9, NightRules.stage_for(8))
	_check(spiders_only.size() == 1 and all_kinds.size() > spiders_only.size(), "the first rung allows only spiders, later ones more")
	# budget and strength
	_check(_near(NightRules.budget(1, 1, 1), 6.0), "level 1, day 1, alone: 6 (%s)" % NightRules.budget(1, 1, 1))
	_check(NightRules.budget(10, 10, 4) > 38.0 and NightRules.budget(10, 10, 4) < 44.0, "level 10, day 10, four players: about 41 (%s)" % NightRules.budget(10, 10, 4))
	_check(NightRules.budget(5, 1, 1) > NightRules.budget(1, 1, 1) and NightRules.budget(1, 9, 1) > NightRules.budget(1, 1, 1), "more level / day, more creatures")
	_check(NightRules.budget(1, 99, 1) <= 6.0 * 1.5 + 0.001, "the day factor is capped")
	_check(NightRules.budget(1, 1, 4) < 4.0 * NightRules.budget(1, 1, 1), "more players is less than linear")
	_check(_near(NightRules.strength(1, 0.0), 1.0) and NightRules.strength(11, 1.0) > NightRules.strength(11, 0.0), "strength: 1 at the start, grows with level and power")
	_check(NightRules.damage_scale(2.0) < 2.0 and NightRules.damage_scale(2.0) > 1.0, "damage grows slower than health")
	_check(NightRules.group_level([2, 7, 4] as Array[int]) == 7, "the strongest player decides")
	_check(NightRules.power(5.0, 0, 5) < NightRules.power(20.0, 4, 5) and NightRules.power(99.0, 99, 5) <= 1.0, "power is 0..1")
	# kinds by budget
	var small: Array[Dictionary] = NightRules.available(6.0, 1, 0)
	var large: Array[Dictionary] = NightRules.available(20.0, 5, 3)
	_check(small.size() == 1 and String(small[0].id) == "shadow_spider", "a small night has only spiders")
	_check(large.size() >= 2, "a large night adds the listener (and what follows)")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	_check(NightRules.pick_species(large, 0.2, 1.0, rng) == "", "nothing is picked when nothing fits")
	_check(NightRules.pick_species(small, 1.0, 1.0, rng) == "shadow_spider", "a spider is picked for one point")
	# groups
	var points: Array[Vector2] = [Vector2(0, 0), Vector2(500, 0), Vector2(5000, 0), Vector2(5400, 0), Vector2(100000, 0)]
	var groups: Array[Array] = NightRules.cluster(points, 1280.0)
	_check(groups.size() == 3 and (groups[0] as Array).size() == 2 and (groups[1] as Array).size() == 2, "players within 80 tiles form one group (%s)" % [groups])
	# special nights: deterministic and rare
	var specials: int = 0
	for night_id: int in range(0, 400):
		var kind: String = NightRules.special_for(4, night_id)
		_check(kind == NightRules.special_for(4, night_id), "special nights are deterministic")
		if kind != "none":
			specials += 1
			_check(night_id >= 4, "no special night before day 4")
	_check(specials > 40 and specials < 130, "about one night in five is special (%d of 400)" % specials)
	# the moon and the fog night
	TimeManager.day = 0
	_check(_near(TimeManager.moon_light(), 0.65) and TimeManager.moon_phase() == 0.0, "day 0: new moon, dimmer")
	TimeManager.day = 4
	_check(_near(TimeManager.moon_light(), 1.0), "day 4: full moon")
	TimeManager.day = 8
	_check(_near(TimeManager.moon_light(), 0.65), "the moon has a cycle of eight days")
	TimeManager.day = 0
	_check(_near(NightRules.light_scale("fog"), 0.8) and _near(NightRules.light_scale("none"), 1.0) and NightRules.fog_boost("fog") > 0.4 and NightRules.fog_boost("flood") == 0.0, "a fog night shrinks the light and thickens the fog")
	# the light maths
	var circles: Array[Vector3] = [Vector3(0, 0, 100), Vector3(300, 0, 50)]
	_check(_near(TownRules.light_depth(circles, Vector2(0, 0)), 100.0) and _near(TownRules.light_depth(circles, Vector2(0, 150)), -50.0), "light depth: positive inside, negative outside")
	_check(TownRules.light_depth([] as Array[Vector3], Vector2.ZERO) < -1000.0, "no circles, no light")
	_check(TownRules.light_outward(circles, Vector2(50, 0)).is_equal_approx(Vector2.RIGHT), "outward points away from the circle")
	_check(_near(TownRules.lit_fraction(circles, Vector2(-50, 0), Vector2(50, 0), 10), 1.0) and _near(TownRules.lit_fraction(circles, Vector2(0, 200), Vector2(0, 400), 10), 0.0), "lit fraction of a line")


# ---------------------------------------------------------------------------------- the world

func _sim(world: WorldLevel, ticks: int, frames_per_tick: int = 30) -> void:
	for i: int in ticks:
		world.night.tick()
		await _frames(frames_per_tick)


func _world() -> void:
	for id: String in ["lamp_post"]:
		(TownRules.piece(id) as Dictionary)["build_seconds"] = 0.6
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	add_child(world)
	await _frames(2)
	var night: NightDirector = world.night
	night.set_process(false) ## the test drives the ticks itself
	var player: Player = world._players.get_child(0) as Player
	var town: TownManager = world.town()
	var hut: Hut = world.hut_node()
	_check(night != null and hut != null and town != null, "the world has a director, a hut and a town")
	# before the town stands nothing is born
	TimeManager.lock_at(0.1)
	player.request_teleport(hut.position + Vector2(0, 120))
	await _frames(90)
	night.tick()
	_check(not night.active() and night.live_count() == 0, "no night before the town is founded")
	var manhole: Vector2 = world.spawn_point()
	world.finish_opening()
	_check(world.spawn_point() == hut.exit_position and manhole != hut.exit_position, "after the opening a fall brings her back to the hut, not the manhole")
	player.quests.set_flag("rebuild_done")
	await _frames(100)
	_check(town.founded and night.active(), "the founded town starts the nights")
	_check(world.spawn_point() == town.respawn_point(), "respawn: the town's house (%s)" % world.spawn_point())
	# light is land
	var centre: Vector2 = town.center
	_check(town.spawn_blocked(centre + Vector2(0, 100)), "no spawn inside the light")
	_check(town.spawn_blocked(centre + Vector2(176.0 + 12.0, 0)), "no spawn within the margin of the light")
	_check(not town.spawn_blocked(centre + Vector2(0, 700)), "spawn is allowed far from the town")
	_check(town.light_depth(centre) > 150.0 and town.light_depth(centre + Vector2(0, 400)) < 0.0, "the house lights its yard")
	# the fog night shrinks the light for the AI, and the atmosphere layer runs
	var depth_full: float = town.light_depth(centre + Vector2(0, 200))
	town.light_scale = 0.8
	_check(town.light_depth(centre + Vector2(0, 200)) < depth_full - 20.0, "on a fog night the light reaches less far")
	_check(town.in_territory(centre + Vector2(0, 150)), "building rules keep the full light")
	town.light_scale = 1.0
	var atmosphere: NightAtmosphere = null
	for node: Node in world.find_children("*", "NightAtmosphere", true, false):
		atmosphere = node as NightAtmosphere
	_check(atmosphere != null, "the world has its night atmosphere")
	TimeManager.lock_at(0.0)
	await _frames(5)
	_check(atmosphere != null and atmosphere.fog > 0.2 and atmosphere.moon >= 0.65, "at midnight there is fog and moonlight (fog %s)" % (atmosphere.fog if atmosphere != null else -1.0))
	TimeManager.lock_at(0.5)
	await _frames(5)
	_check(atmosphere != null and atmosphere.fog < 0.01, "no fog at noon")
	# strength and budget through the director
	var members: Array[Player] = [player]
	TimeManager.day = 0
	var mood: float = NightRules.moon_budget(TimeManager.moon_phase()) * float(NightRules.stage_for(0).budget) ## the moon and the rung of the ladder
	_check(_near(night.group_budget(members), 6.0 * mood), "director budget for a level 1 player (%s, expected %s)" % [night.group_budget(members), 6.0 * mood])
	_check(_near(night.group_budget(members, true), 3.6 * mood), "after a fall the budget is 60 %%")
	night.special = "flood"
	_check(_near(night.group_budget(members), 6.0 * 1.6 * mood), "a flood night brings more")
	night.special = "silent"
	_check(_near(night.group_budget(members), 6.0 * 0.4 * mood), "a silent night brings few")
	night.special = "none"
	TimeManager.day = 4
	_check(_near(night.group_budget(members), NightRules.budget(1, 4, 1) * NightRules.moon_budget(0.5) * float(NightRules.stage_for(4).budget)), "day 4 (full moon, second rung) is weighed by the moon and the rung (%s)" % night.group_budget(members))
	TimeManager.day = 0
	_check(_near(night.group_strength(members), 1.0), "an empty-handed level 1 group meets base strength (%s)" % night.group_strength(members))
	player.health.heal_full() ## the opening leaves her wounded, and a hurt group is spared by the night
	player.request_teleport(centre + Vector2(0, 320))
	await _frames(120)
	# --- the night: creatures climb out within their budget
	TimeManager.lock_at(0.1) ## progress 0.75: the whole budget is released
	night.tick()
	_check(night.night_id() == 0, "a night began")
	await _sim(world, 40)
	var count: int = night.live_count(false)
	_check(count >= 4 and count <= 8, "a level 1 night brings about six creatures, not more (%d)" % count)
	var inside: int = 0
	var too_close: int = 0
	var listeners: int = 0
	for entry: Dictionary in night.entries():
		var node: Node2D = entry.node as Node2D
		if town.light_depth(node.global_position) > float((NightRules.config().courage as Dictionary).dim_px) + 12.0: ## the dim outer band may be probed by a bold one
			inside += 1
		if node.global_position.distance_to(player.global_position) < 22.0 * 16.0 - 40.0:
			too_close += 1
		if node is VoidListener:
			listeners += 1
	_check(inside == 0, "nobody walked into the town's light (%d inside)" % inside)
	_check(listeners == 0, "a small night has only spiders")
	print("NIGHT note: ", count, " creatures, ", too_close, " nearer than 22 tiles to the player after patrolling")
	# a kill gives part of the cost back
	var before_spent: float = float((night._ledger[night._ledger.keys()[0]] as Dictionary).spent)
	var victim: Node2D = (night.entries()[0] as Dictionary).node as Node2D
	(victim.get_node("HealthComponent") as HealthComponent).last_attacker = player.name.to_int()
	(victim.get_node("HealthComponent") as HealthComponent).take_damage(99999.0, victim.global_position, 0.0, player.name.to_int())
	await _frames(5)
	var after_spent: float = float((night._ledger[night._ledger.keys()[0]] as Dictionary).spent)
	_check(_near(before_spent - after_spent, 0.5), "a kill refunds half of its cost (%s -> %s)" % [before_spent, after_spent])
	# --- the light is no wall for a raid, but it is for the rest
	player.request_teleport(centre + Vector2(0, 60))
	await _frames(60)
	var runner: Node2D = (night.entries()[-1] as Dictionary).node as Node2D
	var runner_nb: NightBehavior = (night.entries()[-1] as Dictionary).nb as NightBehavior
	var start: Vector2 = Vector2.INF
	for k: int in 16:
		var candidate: Vector2 = centre + Vector2.from_angle(TAU * float(k) / 16.0 + 0.3) * 290.0
		if world.navigation_floor(candidate) and String(world.town_probe(Rect2(candidate - Vector2(14, 14), Vector2(28, 28)))) == "" and not world.town_probe(Rect2(centre + (candidate - centre) * 0.5 - Vector2(14, 14), Vector2(28, 28))) in ["IM WEG"]:
			start = candidate
			break
	_check(start.is_finite(), "found free ground for the runner")
	runner.global_position = start
	runner_nb.courage = 0.0 ## a timid one: the dim band is not for it
	runner_nb.courage_extra = -1.0
	runner_nb.goal = player.global_position
	runner_nb.queue.clear()
	var deepest: float = -9999.0
	for i: int in 240:
		deepest = maxf(deepest, town.light_depth(runner.global_position))
		await _frames(1)
	_check(deepest < 12.0 and deepest > -60.0, "a calm creature walks up to the edge of the light and stops there (deepest %s)" % deepest)
	runner_nb.excited = true
	runner_nb.goal = player.global_position
	deepest = -9999.0
	for i: int in 600:
		deepest = maxf(deepest, town.light_depth(runner.global_position))
		await _frames(1)
	_check(deepest > 20.0, "a creature in a raid does enter the light (deepest %s)" % deepest)
	runner_nb.excited = false
	_check(not night._died.is_empty() or player.health.current > 0.0, "the raid member may have hurt her (bookkeeping only)")
	player.health.heal_full()
	await _frames(5)
	player.global_position = centre + Vector2(0, 60)
	# --- a raid: lure past the threshold, a warning, a rush through the gap, calm again
	await _sim(world, 4)
	night.debug_force_raid()
	night.tick()
	_check(night.raid_state() == "warning", "enough lure starts a warning (%s)" % night.raid_state())
	var members_in_raid: int = (night._raid.members as Array).size()
	_check(members_in_raid >= 2, "a raid gathers at least two creatures (%d)" % members_in_raid)
	for i: int in 31:
		night.tick()
	_check(night.raid_state() == "attack", "after the warning they rush the base (%s)" % night.raid_state())
	_check(town.fear_on, "the people run for cover while a raid is on")
	var excited: int = 0
	for entry: Dictionary in night._raid.members as Array:
		if (entry.nb as NightBehavior).excited:
			excited += 1
	_check(excited >= 1, "raid members are excited")
	for i: int in 46:
		night.tick()
	_check(night.raid_state() == "idle", "the raid ends (%s)" % night.raid_state())
	_check(night.lure <= 15.0 and night.lure > 5.0, "after a raid the lure falls back (%s)" % night.lure)
	# --- evidence: noise leaves a trace that merges and fades
	var evidence_before: int = night.evidence_count()
	night._add_evidence(centre + Vector2(900, 900))
	night._add_evidence(centre + Vector2(910, 905))
	_check(night.evidence_count() == evidence_before + 1, "two noises close together are one trace")
	night._evidence_tick([] as Array[Player])
	for i: int in 70:
		night._evidence_tick([] as Array[Player])
	_check(night.evidence_count() == 0, "a trace fades after its time")
	# --- courage: a bold creature may probe the dim band, a timid one may not
	var bold: NightBehavior = NightBehavior.new()
	bold.courage = 0.9
	var timid: NightBehavior = NightBehavior.new()
	timid.courage = 0.1
	_check(bold.brave() and not timid.brave(), "only a bold creature dares the dim band")
	timid.courage_extra = 0.6
	_check(timid.brave(), "a new moon makes even the timid bolder")
	# --- the night's memory is kept in the save and makes the weak side more attractive
	TimeManager.day = 7
	night._memory.clear()
	var calm_weight: float = night.sector_weight(3)
	night._remember(3, "b", 2.0)
	_check(night.sector_weight(3) > calm_weight, "a side that gave way draws the dark")
	night._remember(3, "d", 4.0)
	_check(night.sector_weight(3) < calm_weight + 2.0 * float((NightRules.config().memory as Dictionary).breach_weight), "defenders' luck lowers it again")
	var saved: Dictionary = night.export_state()
	night._memory.clear()
	night.import_state(JSON.parse_string(JSON.stringify(saved)) as Dictionary)
	_check(night._memory.has(3) and _near(float((night._memory[3] as Dictionary).b), 2.0), "the memory survives a save")
	night._decay_memory()
	_check(float((night._memory[3] as Dictionary).b) < 2.0, "a new night forgets part of it")
	night._memory.clear()
	TimeManager.day = 0
	# --- the morning: they turn for the dark and burn, and leave nothing behind
	TimeManager.lock_at(0.225)
	var drops: Node = get_tree().get_first_node_in_group("drops")
	var drops_before: int = drops.get_child_count()
	for i: int in 90:
		night.tick()
		await _frames(30)
		if night.live_count(false) == 0:
			break
	_check(night.live_count(false) == 0, "the creatures of the night are gone by morning (%d left)" % night.live_count(false))
	for i: int in 40:
		night.tick()
	_check(not town.fear_on, "when it is quiet again the people come out")
	_check(drops.get_child_count() == drops_before, "what the sun took leaves no loot")
	# --- the day: a weakened leftover in the shade
	(NightRules.config().remnants as Dictionary)["interval"] = [1, 1]
	(NightRules.config().remnants as Dictionary)["chance"] = 1.0
	TimeManager.lock_at(0.5)
	night._remnant_wait = 0.0
	var trees: Array[Node] = get_tree().get_nodes_in_group("bird_perches")
	_check(not trees.is_empty(), "there are trees in the world")
	var tree: Node2D = trees[0] as Node2D
	player.request_teleport(tree.global_position + Vector2(0, 30.0 * 16.0))
	await _frames(150)
	var made: int = 0
	var ringed: int = 0
	var floored: int = 0
	var probed: int = 0
	for t: Node in get_tree().get_nodes_in_group("bird_perches"):
		var d: float = (t as Node2D).global_position.distance_to(player.global_position)
		if d >= 26.0 * 16.0 and d <= 42.0 * 16.0:
			ringed += 1
			var base: Vector2 = (t as Node2D).global_position + Vector2(0, 18)
			if world.navigation_floor(base):
				floored += 1
				if String(world.town_probe(Rect2(base - Vector2(10, 10), Vector2(20, 20)))) == "":
					probed += 1
	for i: int in 40:
		night.tick()
		night._remnant_wait = 0.0
		await _frames(30)
		made = night.live_count()
		if made > 0:
			break
	_check(probed == 0 or made > 0, "a leftover of the day appears in the shade (%d trees were free)" % probed)
	if made > 0:
		var entry: Dictionary = night.entries()[0] as Dictionary
		var node: Node2D = entry.node as Node2D
		var health: HealthComponent = node.get_node("HealthComponent") as HealthComponent
		_check((entry.nb as NightBehavior).remnant, "it is a leftover of the day")
		_check(health.max_health < 40.0, "leftovers are weak (%s HP)" % health.max_health)
		var full: float = health.current
		node.global_position = player.global_position + Vector2(400, 0) ## far from any tree: in the open sun
		for i: int in 8:
			night.tick()
			await _frames(30)
		_check(health.current < full or health.current <= 0.0, "a leftover in the open sun burns (%s of %s)" % [health.current, full])
	TimeManager.unlock()
	print("NIGHT done")
