extends Node
const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")
## Offline species integration: Godot --headless --path . tools/test_woodland.tscn

class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass

var _checks: int = 0
var _failures: int = 0
var _population: WoodlandPopulation


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _make(species: String, point: Vector2, name_value: String, appearance: int = 0) -> WoodlandMammal:
	var animal: WoodlandMammal = load("res://src/entities/wildlife/woodland_mammal.tscn").instantiate() as WoodlandMammal
	animal.name = name_value
	animal.species = species
	animal.appearance = appearance
	animal.family_id = "test_family"
	animal.position = point
	animal.home = point
	_population._residents.add_child(animal)
	animal.set_physics_process(false)
	return animal


func _run() -> void:
	_population = load("res://src/world/woodland_population.tscn").instantiate() as WoodlandPopulation
	add_child(_population)
	_population.setup(4, func(_point: Vector2, _kind: String) -> bool: return true)
	_population.set_process(false)
	for y: int in range(-3, 4):
		for x: int in range(-3, 4):
			_population._active[Vector2i(x, y)] = true
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	player.position = Vector2(1000, 1000)
	add_child(player)
	player.set_physics_process(false)
	TimeManager.time_of_day = 0.5
	var doe: WoodlandMammal = _make("deer", Vector2.ZERO, "Doe")
	var fawn: WoodlandMammal = _make("deer", Vector2(90, 15), "Fawn", 2)
	await get_tree().physics_frame
	_check(fawn._adult() == doe and fawn.is_fawn(), "Fawn did not identify the adult of its family")
	fawn._deer_life()
	_check(fawn._moving and fawn._end.distance_to(doe.position) < fawn.position.distance_to(doe.position), "Fawn did not follow its adult")
	fawn._settle(fawn.position, WoodlandMammal.Mood.WALK)
	player.position = Vector2(130, 0)
	await get_tree().physics_frame
	doe._sense()
	_check(doe.mood == WoodlandMammal.Mood.ALERT, "Deer did not freeze before fleeing")
	player.stealth.sneaking = true
	doe._issue(WoodlandMammal.Mood.FORAGE, 2.0)
	doe._sense()
	_check(doe.mood == WoodlandMammal.Mood.FORAGE, "Sneaking did not reduce deer detection")
	player.stealth.sneaking = false
	player.position = Vector2(55, 0)
	await get_tree().physics_frame
	doe._sense()
	_check(doe.mood == WoodlandMammal.Mood.FLEE and doe._moving, "Close approach did not trigger deer flight")
	_check(fawn._alarm_delay > 0.0 and fawn.mood == WoodlandMammal.Mood.ALERT, "Family did not receive a staggered alarm")
	doe._elapsed = doe._duration * 0.5
	doe._advance()
	_check(doe.position.x < 0.0, "Deer flight moved toward the threat")
	player.position = Vector2(1000, 1000)
	doe._settle(doe.position, WoodlandMammal.Mood.FLEE)
	doe._danger = false
	doe._safe_time = 4.0
	doe._think()
	_check(doe.mood == WoodlandMammal.Mood.ALERT, "Deer did not recover cautiously after safety")
	doe._elapsed = 2.0
	doe._think()
	_check(doe.mood == WoodlandMammal.Mood.BARK, "Recovered adult deer did not give its warning bark (Schrecken)")
	doe._process(0.0)
	_check(doe._sprite.hframes == 52 and doe._sprite.vframes == 32 and doe._sprite.frame % 52 in range(40, 46), "Deer 52-col Schrecken frame mismatch")
	doe._issue(WoodlandMammal.Mood.SLEEP, 2.0)
	doe._danger = false
	doe.hear_external_alarm(Vector2(60, 0))
	_check(doe.mood == WoodlandMammal.Mood.STAND_UP, "Bedded deer did not rise on external sentinel alarm")
	doe.queue_free()
	fawn.queue_free()
	await get_tree().physics_frame

	var badger: WoodlandMammal = _make("badger", Vector2.ZERO, "Badger")
	badger._elapsed = 20.0
	badger._think()
	badger._process(0.0)
	_check(badger.mood == WoodlandMammal.Mood.HIDDEN and not badger._sprite.visible, "Daytime badger did not rest in its den")
	TimeManager.time_of_day = 0.97
	badger._think()
	_check(badger.mood == WoodlandMammal.Mood.EMERGE and badger._moving, "Dusk did not wake the badger")
	badger._elapsed = badger._duration
	badger._advance()
	badger._forage_visits = 1
	badger._issue(WoodlandMammal.Mood.FORAGE, 0.1)
	badger._elapsed = 0.2
	badger._badger_life()
	_check(badger.mood == WoodlandMammal.Mood.SPECIAL, "Badger did not switch from sniffing to digging")
	TimeManager.time_of_day = 0.5
	badger.position = Vector2(70, 0)
	badger._elapsed = 20.0
	badger._think()
	_check(badger.mood == WoodlandMammal.Mood.RETURN and badger._moving and badger._end.distance_to(badger.home) < 70.0, "Morning badger did not walk back toward its den")
	badger._settle(badger.home, WoodlandMammal.Mood.RETURN)
	badger._elapsed = 1.0
	badger._think()
	_check(badger.mood == WoodlandMammal.Mood.HIDDEN, "Returned badger did not enter its den")
	badger.queue_free()
	await get_tree().physics_frame

	TimeManager.time_of_day = 0.97
	var fox: WoodlandMammal = _make("fox", Vector2.ZERO, "Fox")
	fox._issue(WoodlandMammal.Mood.LISTEN, 0.1)
	fox._elapsed = 0.2
	fox._think()
	_check(fox.mood == WoodlandMammal.Mood.SPECIAL and fox._moving, "Listening fox did not make a short hunting pounce")
	fox._elapsed = fox._duration * 0.5
	fox._advance()
	fox._process(0.0)
	_check(fox._sprite.position.y < 0.0 and fox.position.length() < 20.0, "Fox pounce is not a short visible arc")
	fox._elapsed = fox._duration
	fox._advance()
	fox._process(0.0)
	_check(not fox._moving and fox._sprite.position.y == 0.0, "Fox bounced a second time after landing")
	fox._elapsed = 1.0
	fox._think()
	_check(fox.mood == WoodlandMammal.Mood.FORAGE, "Fox did not inspect the ground after its pounce")
	fox._move_action(WoodlandMammal.Mood.STALK, Vector2(28, 0), 1.2)
	fox._elapsed = 0.5
	fox._advance()
	fox._process(0.0)
	_check(fox._sprite.hframes == 52 and fox._sprite.vframes == 32 and fox._sprite.frame % 52 in range(46, 52), "Fox 52-col crouched stalk frame mismatch")
	fox._elapsed = fox._duration
	fox._advance()
	fox._think()
	_check(fox.mood == WoodlandMammal.Mood.LISTEN, "Stalking fox did not pause to listen before pouncing")
	var rabbit: WildRabbit = load("res://src/entities/player/../wildlife/wild_rabbit.tscn").instantiate() as WildRabbit
	rabbit.name = "ObservingRabbit"
	rabbit.position = fox.position + Vector2(40, 0)
	add_child(rabbit)
	rabbit.set_physics_process(false)
	await get_tree().physics_frame
	rabbit._sense()
	_check(rabbit.state == WildRabbit.State.FLEE, "Rabbit ignored a nearby fox")
	fox.queue_free()
	rabbit.queue_free()
	await get_tree().physics_frame

	var hedgehog: WoodlandMammal = _make("hedgehog", Vector2.ZERO, "Hedgehog")
	player.position = Vector2(22, 0)
	await get_tree().physics_frame
	hedgehog._sense()
	_check(hedgehog.mood == WoodlandMammal.Mood.SPECIAL and not hedgehog._moving, "Hedgehog ran away instead of curling")
	hedgehog._elapsed = hedgehog._duration
	hedgehog._process(0.0)
	_check(hedgehog._sprite.frame % 44 == 43, "Curled hedgehog did not reach the closed-ball pose")
	player.position = Vector2(300, 0)
	await get_tree().physics_frame
	hedgehog._sense()
	hedgehog._safe_time = 4.0
	hedgehog._think()
	_check(hedgehog.mood == WoodlandMammal.Mood.UNROLL, "Safe hedgehog did not cautiously unfold")
	hedgehog._elapsed = hedgehog._duration
	hedgehog._process(0.0)
	_check(hedgehog._sprite.frame % 44 == 38, "Hedgehog unroll is not the reverse curl")
	TimeManager.time_of_day = 0.5
	hedgehog._think()
	_check(hedgehog.mood == WoodlandMammal.Mood.SLEEP, "Daytime hedgehog did not rest")
	player.position = Vector2(20, 0)
	await get_tree().physics_frame
	hedgehog._sense()
	hedgehog._process(0.0)
	_check(hedgehog._sprite.frame % 44 == 43, "Startled sleeping hedgehog briefly opened instead of staying curled")
	hedgehog.queue_free()
	await get_tree().physics_frame

	# Boar sounder: 52x32 sheet, striped piglet queue, rooting, and bluff-charge deterrence against a fox!
	player.position = Vector2(500, 0)
	TimeManager.time_of_day = 0.5
	var sow: WoodlandMammal = _make("boar", Vector2.ZERO, "LeadSow", 0)
	var piglet: WoodlandMammal = _make("boar", Vector2(70, 20), "Piglet", 2)
	await get_tree().physics_frame
	_check(sow._sprite.hframes == 52 and sow._sprite.vframes == 32 and piglet.is_piglet(), "Boar 52x32 sheet or piglet flag mismatch")
	piglet._boar_life()
	_check(piglet._moving and piglet._end.distance_to(sow.position) < piglet.position.distance_to(sow.position), "Piglet did not follow lead sow")
	piglet._settle(piglet.position, WoodlandMammal.Mood.WALK)
	var intruder_fox: WoodlandMammal = _make("fox", Vector2(46, 0), "IntruderFox", 0)
	await get_tree().physics_frame
	sow._sense()
	intruder_fox._sense()
	_check(sow.mood in [WoodlandMammal.Mood.CHASE, WoodlandMammal.Mood.BARK], "Adult boar did not stand/charge against a nearby fox")
	_check(intruder_fox.mood in [WoodlandMammal.Mood.ALERT, WoodlandMammal.Mood.FLEE], "Fox ignored a tough adult boar")
	sow.queue_free()
	piglet.queue_free()
	intruder_fox.queue_free()
	await get_tree().physics_frame

	# Lynx: 52x24 sheet, apex hunter group, triggers roe deer Schrecken & makes fox yield
	var lynx: WoodlandMammal = _make("lynx", Vector2.ZERO, "ApexLynx", 0)
	var wary_doe: WoodlandMammal = _make("deer", Vector2(115, 0), "WaryDoe", 0)
	await get_tree().physics_frame
	_check(lynx._sprite.hframes == 52 and lynx._sprite.vframes == 24 and lynx.is_in_group("apex_hunters"), "Lynx 52x24 sheet or apex_hunters group missing")
	wary_doe._sense()
	_check(wary_doe.mood == WoodlandMammal.Mood.ALERT and wary_doe._bark_pending, "Roe deer did not prepare Schrecken upon sensing apex lynx")
	lynx.queue_free()
	wary_doe.queue_free()
	await get_tree().physics_frame

	# Squirrel: 52x32 sheet, vertical trunk climb height, spruce-cone gnawing, and sentinel alarm broadcast
	var squirrel: WoodlandMammal = _make("squirrel", Vector2.ZERO, "RedSquirrel", 0)
	var listening_doe: WoodlandMammal = _make("deer", Vector2(85, 0), "ListeningDoe", 0)
	await get_tree().physics_frame
	_check(squirrel._sprite.hframes == 52 and squirrel._sprite.vframes == 32, "Squirrel 52x32 sheet mismatch")
	squirrel._climb_action(WoodlandMammal.Mood.CLIMB, Vector2.ZERO, 0.6, 0.0, 28.0)
	squirrel._elapsed = 0.3
	squirrel._process(0.0)
	_check(squirrel._climb_height > 10.0 and squirrel._sprite.position.y < -10.0 and squirrel._sprite.frame % 52 in range(46, 52), "Squirrel vertical trunk climb pose/height failed")
	squirrel._settle(Vector2.ZERO, WoodlandMammal.Mood.CLIMB, 28.0)
	squirrel._issue(WoodlandMammal.Mood.SPECIAL, 2.5)
	squirrel._elapsed = 0.6
	squirrel._process(0.0)
	_check(squirrel._sprite.frame % 52 in range(38, 46), "Squirrel cone-gnaw frame mismatch")
	player.position = Vector2(36, 0)
	await get_tree().physics_frame
	squirrel._sense()
	_check(squirrel.mood == WoodlandMammal.Mood.BARK and listening_doe.mood == WoodlandMammal.Mood.ALERT, "Perched squirrel did not scold and alert nearby deer")
	squirrel.queue_free()
	listening_doe.queue_free()
	await get_tree().physics_frame

	# Hexenwald Billy Goat: 52x32 sheet, eerie watcher stare at medium range, dramatic hind-leg rear-up when crowded
	var goat: WoodlandMammal = _make("hex_goat", Vector2.ZERO, "HexGoat", 0)
	player.position = Vector2(82, 0)
	await get_tree().physics_frame
	goat._sense()
	_check(goat.mood == WoodlandMammal.Mood.ALERT and not goat._moving, "Hexenwald goat fled instead of watching eerily at medium range")
	player.position = Vector2(26, 0)
	await get_tree().physics_frame
	goat._sense()
	goat._process(0.0)
	_check(goat.mood == WoodlandMammal.Mood.REAR and goat._sprite.frame % 52 in range(40, 46), "Crowded Hexenwald billy goat did not rear up onto hind legs")
	goat.queue_free()
	await get_tree().physics_frame

	# Hexenwald Giant Toad: 52x24 sheet, parabolic hop lift, defensive puff-up, vocal sac croak, sticky tongue-lash
	var toad: WoodlandMammal = _make("hex_toad", Vector2.ZERO, "HexToad", 0)
	player.position = Vector2(54, 0)
	await get_tree().physics_frame
	toad._sense()
	toad._process(0.0)
	_check(toad.mood == WoodlandMammal.Mood.ALERT and toad._sprite.frame % 52 in range(18, 22), "Hexenwald toad did not puff up defensively")
	player.position = Vector2(1000, 1000)
	toad._danger = false
	toad._move_action(WoodlandMammal.Mood.WALK, Vector2(14, 0), 0.5)
	toad._elapsed = 0.25
	toad._advance()
	toad._process(0.0)
	_check(toad._sprite.position.y < -1.0 and toad._sprite.frame % 52 in range(10, 18), "Hexenwald toad hop lacks parabolic arc")
	toad._settle(toad.position, WoodlandMammal.Mood.WALK)
	toad._issue(WoodlandMammal.Mood.BARK, 1.2)
	toad._elapsed = 0.5
	toad._process(0.0)
	_check(toad._sprite.frame % 52 in range(38, 44), "Hexenwald toad vocal-sac croak frame mismatch")
	toad._issue(WoodlandMammal.Mood.SPECIAL, 0.85)
	toad._elapsed = 0.4
	toad._process(0.0)
	_check(toad._sprite.frame % 52 in range(44, 52), "Hexenwald toad sticky tongue-lash frame mismatch")
	toad.queue_free()
	player.queue_free()
	await get_tree().physics_frame

	# Eagle-Owl (Uhu): 62x24 64px sheet, daytime camouflage sleep outside vs awake phantom owl in Hexenwald
	var owl: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
	owl.name = "TestEagleOwl"
	owl.species = "owl"
	owl.appearance = 0
	add_child(owl)
	owl.set_physics_process(false)
	TimeManager.time_of_day = 0.5
	owl.state = WildCorvid.State.ROOST
	owl._process(0.0)
	_check(owl._sprite.hframes == 62 and owl._sprite.vframes == 24 and owl._rest_time() and owl._sprite.frame % 62 in range(58, 62), "Daytime Eagle-Owl did not use 62-col bark-camouflage roost")
	owl.witch = true
	owl.appearance = 2
	_check(not owl._rest_time(), "Hexenwald phantom Eagle-Owl should stay awake in eternal twilight")
	owl.queue_free()
	await get_tree().physics_frame

	# Ground movement cannot tunnel through a prop even when a route becomes blocked after planning.
	var animal: WoodlandMammal = _make("deer", Vector2.ZERO, "CollisionDeer")
	animal._move_action(WoodlandMammal.Mood.WALK, Vector2(60, 0), 1.0)
	_check(animal._route_progress(0.02) < 0.004 and animal._route_progress(0.98) > 0.996, "Walking lacks gentle acceleration and braking")
	var last_progress: float = 0.0
	var monotonic: bool = true
	for sample: int in range(1, 101):
		var progress: float = animal._route_progress(float(sample) / 100.0)
		monotonic = monotonic and progress >= last_progress and progress <= 1.00001
		last_progress = progress
	_check(monotonic and is_equal_approx(last_progress, 1.0), "Smooth route overshot or reversed")
	animal._elapsed = 0.4
	animal._advance()
	var phase: float = animal._gait_phase
	animal._move_action(WoodlandMammal.Mood.WALK, animal.position + Vector2(50, 0), 1.0)
	_check(phase > 0.0 and is_equal_approx(animal._gait_start, phase), "A new route reset the walking gait")
	animal._threat = Vector2(-200, 0)
	animal._safe_time = 0.0
	animal._move_action(WoodlandMammal.Mood.FLEE, animal.position + Vector2(80, 0), 1.0)
	var escape_goal: Vector2 = animal._end
	animal._elapsed = 1.0
	animal._advance()
	_check(animal._moving and animal._rolling and animal.position.is_equal_approx(escape_goal) and animal._end.x > escape_goal.x, "Fleeing stopped between route segments")
	_check(animal._route_progress(0.02) > 0.019, "Continuing flight unnecessarily accelerated from rest")
	animal.position = Vector2.ZERO
	animal._settle(animal.position, WoodlandMammal.Mood.REST)
	var wall: StaticBody2D = StaticBody2D.new()
	var collider: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(4, 60)
	collider.shape = box
	wall.position = Vector2(25, 0)
	wall.add_child(collider)
	add_child(wall)
	await get_tree().physics_frame
	animal._move_action(WoodlandMammal.Mood.WALK, Vector2(60, 0), 1.0)
	animal._elapsed = 1.0
	animal._advance()
	_check(animal.position.x < 18.0 and not animal._moving, "Animal crossed a solid world prop")
	animal.queue_free()
	wall.queue_free()
	_population.queue_free()
	await get_tree().physics_frame

	var butterfly: MeadowButterfly = load("res://src/entities/wildlife/meadow_butterfly.tscn").instantiate() as MeadowButterfly
	butterfly.name = "TestButterfly"
	butterfly.flowers = [Vector2.ZERO, Vector2(20, 0), Vector2(45, 10), Vector2(65, 0)]
	butterfly.home = Vector2.ZERO
	add_child(butterfly)
	butterfly.set_physics_process(false)
	TimeManager.time_of_day = 0.5
	butterfly._visit(true, Vector2(-10, 0))
	_check(butterfly._end == Vector2(65, 0) and butterfly.state == MeadowButterfly.State.FLY, "Butterfly did not scatter to a safe flower")
	butterfly._elapsed = butterfly._duration * 0.5
	butterfly._physics_process(0.0)
	_check(butterfly.position.x > 0.0 and butterfly._alt > 4.0, "Butterfly flight has no forward arc")
	butterfly._elapsed = butterfly._duration
	butterfly._physics_process(0.0)
	_check(butterfly.state == MeadowButterfly.State.FEED and butterfly.position == Vector2(65, 0), "Butterfly did not land on its actual flower")
	TimeManager.time_of_day = 0.97
	butterfly._elapsed = 20.0
	butterfly._physics_process(0.0)
	butterfly._process(0.0)
	_check(butterfly.state == MeadowButterfly.State.REST and butterfly._sprite.frame % 8 == 7, "Night butterfly did not fold its wings and rest")
	TimeManager.time_of_day = 0.5
	butterfly._physics_process(0.0)
	_check(butterfly.state == MeadowButterfly.State.FEED, "Daylight did not wake the butterfly")
	butterfly.queue_free()
	await get_tree().process_frame

	# Frozen-world integration: legal habitats, exact blossoms, independent sparse budgets.
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	for frame: int in 35:
		await get_tree().physics_frame
	var population: WoodlandPopulation = world.get_node("Wildlife/Woodland") as WoodlandPopulation
	population.set_process(false)
	var insects: ButterflyPopulation = world.get_node("Wildlife/MeadowInsects") as ButterflyPopulation
	insects.set_process(false)
	print("Initial woodland residents: %d; butterflies: %d" % [population._residents.get_child_count(), insects._butterflies.get_child_count()])
	_check(population._residents.get_child_count() <= 28 and insects._butterflies.get_child_count() == 0, "Curated wildlife budgets exceeded or butterflies still spawning")
	for node: Node in population._residents.get_children():
		var resident: WoodlandMammal = node as WoodlandMammal
		resident.set_physics_process(false)
		_check(resident.species in ["deer", "fox", "boar", "lynx", "squirrel", "badger", "hex_goat", "hex_toad", "oryx", "fennec", "jerboa", "agama"], "Unapproved woodland species spawned in live world: %s" % resident.species)
		_check(world._fauna_habitat(resident.home, resident.species), "Woodland resident spawned outside its habitat")
		if resident.is_fawn():
			_check(resident._adult() != null, "World spawned an orphaned fawn or piglet")
	for node: Node in insects._butterflies.get_children():
		var insect: MeadowButterfly = node as MeadowButterfly
		insect.set_physics_process(false)
		_check(insect.flowers.has(insect.position) or insect.state == MeadowButterfly.State.FLY, "Butterfly spawned away from its flowers")
	var flowers: Array[Vector2] = []
	for cell: Vector2i in world._chunks:
		flowers.append_array(world._flower_targets(cell))
	_check(not flowers.is_empty(), "Meadow flower callback found no real blossoms")
	world.queue_free()
	await get_tree().process_frame
	Terrain.relief = null
	print("Woodland species: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
