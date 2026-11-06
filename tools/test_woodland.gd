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
	player.queue_free()
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
	_check(population._residents.get_child_count() <= 8 and insects._butterflies.get_child_count() <= 10, "New wildlife budgets exceeded")
	for node: Node in population._residents.get_children():
		var resident: WoodlandMammal = node as WoodlandMammal
		resident.set_physics_process(false)
		_check(world._fauna_habitat(resident.home, resident.species), "Woodland resident spawned outside its habitat")
		if resident.is_fawn():
			_check(resident._adult() != null, "World spawned an orphaned fawn")
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
