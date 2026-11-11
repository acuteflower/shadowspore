class_name TownCritters
extends Node
## Animals that come to the town (host only, a child of TownManager). Cosmetic life, nothing is won from it, nothing replicates but the animals themselves (the populations spawn them
## like any wild animal). **Birds:** in daylight, while somebody is about, one to three crows (now and then a raven) come in from outside the view and land on the roofs, lamp arms,
## benches and fences (`RoofPerch`, data `perches`), stay a few minutes and go on with their lives. **The fox:** once on most nights, when a stockpile stands, a fox walks up to its
## front, sniffs along it (ground, a listening pause, ground again) and trots off; if anyone comes near it gives up (WoodlandMammal `visit`). Both ask the existing populations to spawn
## them (`CorvidPopulation.spawn_visitor`, `WoodlandPopulation.spawn_visitor`), so every cap and rule of ordinary wildlife holds.

const TICK: float = 6.0
const BIRD_LIFE: Vector2 = Vector2(200.0, 420.0) ## seconds a visiting bird stays (then it is freed when nobody watches)
const FOX_LIFE: float = 170.0
const SPAWN_RING: Vector2 = Vector2(300.0, 380.0) ## how far from its goal a visitor appears (outside the view)

var town: TownManager
var _clock: float = 0.0
var _next_bird: float = 20.0
var _fox_night: int = -1
var _board_bird: float = -1.0 ## seconds until the crow for the board's fallen papers is sent (-1 = none)
var _ages: Dictionary = {} ## instance id -> seconds alive
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	set_process(multiplayer.is_server())


func _process(delta: float) -> void:
	_clock += delta
	if _clock < TICK:
		return
	var step: float = _clock
	_clock = 0.0
	if town == null or not town.founded or InputManager.ui_blocking:
		return
	_age(step)
	if _board_bird >= 0.0:
		_board_bird -= step
		if _board_bird < 0.0:
			_board_bird = -1.0
			_board_visit_now()
	var night: float = TimeManager.night_amount()
	_next_bird -= step
	if night < 0.15 and _next_bird <= 0.0:
		_next_bird = _rng.randf_range(25.0, 70.0)
		_bird_visit()
	if night > 0.6 and _fox_night != TimeManager.day:
		_fox_night = TimeManager.day
		if _rng.randf() < 0.7:
			_fox_visit()


func _world() -> Node:
	return get_tree().get_first_node_in_group("world")


func _population(kind: String) -> Node:
	var world: Node = _world()
	if world == null:
		return null
	var found: Array[Node] = world.find_children("*", kind, true, false)
	return found[0] if not found.is_empty() else null


## Is somebody close enough to the town to see anything (the visitors are for them)?
func _watched() -> bool:
	for player: Player in Player.all:
		if player.health.current > 0.0 and player.global_position.distance_to(town.center) < 420.0:
			return true
	return false


func _alive_players_far(point: Vector2, distance: float) -> bool:
	for player: Player in Player.all:
		if player.global_position.distance_to(point) < distance:
			return false
	return true


func _age(step: float) -> void:
	var birds: CorvidPopulation = _population("CorvidPopulation") as CorvidPopulation
	if birds != null:
		for bird: WildCorvid in birds.visitors():
			_expire(bird, step, _rng.randf_range(BIRD_LIFE.x, BIRD_LIFE.y), 300.0, birds)
	var woods: WoodlandPopulation = _population("WoodlandPopulation") as WoodlandPopulation
	if woods != null:
		for animal: WoodlandMammal in woods.visitors():
			_expire(animal, step, FOX_LIFE if TimeManager.night_amount() > 0.15 else 0.0, 250.0, woods)


## Frees a visitor that has stayed long enough (or whose night is over) once nobody is looking.
func _expire(animal: Node2D, step: float, limit: float, unseen: float, population: Node) -> void:
	var key: int = animal.get_instance_id()
	var age: float = float(_ages.get(key, 0.0)) + step
	_ages[key] = age
	if age < limit and limit > 0.0:
		return
	if not _alive_players_far(animal.global_position, unseen):
		return
	_ages.erase(key)
	if population.has_method("release_perch") and animal is WildCorvid:
		population.call("release_perch", animal)
	animal.queue_free()


func _perches() -> Array[RoofPerch]:
	var out: Array[RoofPerch] = []
	for node: Node in get_tree().get_nodes_in_group("town_perches"):
		var perch: RoofPerch = node as RoofPerch
		if perch != null and not perch.is_depleted():
			out.append(perch)
	return out


func _bird_visit() -> void:
	if not _watched():
		return
	var birds: CorvidPopulation = _population("CorvidPopulation") as CorvidPopulation
	var perches: Array[RoofPerch] = _perches()
	if birds == null or perches.is_empty():
		return
	var wanted: int = clampi(1 + perches.size() / 4, 1, 3)
	if birds.visitors().size() >= wanted:
		return
	var goal: Vector2 = perches[_rng.randi() % perches.size()].global_position
	for attempt: int in 14:
		var point: Vector2 = goal + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(SPAWN_RING.x, SPAWN_RING.y)
		if not _alive_players_far(point, 340.0):
			continue
		var species: String = "raven" if _rng.randf() < 0.15 else "crow"
		var bird: WildCorvid = birds.spawn_visitor(species, point, "town")
		if bird != null:
			bird._take_wing(false, false, false, true) ## straight to a roof
			return


## A notice of the quest board ran out at sunrise: a crow is sent for it a little later (the board pieces carry a perch on their roof, `BoardNotes` lets it take the paper).
## Only in daylight and when somebody is about to see it; the notice is gone in the table either way.
func board_visit(_papers: int) -> void:
	_board_bird = _rng.randf_range(35.0, 110.0)


func _board_visit_now() -> void:
	if not _watched() or TimeManager.night_amount() > 0.15:
		return
	var birds: CorvidPopulation = _population("CorvidPopulation") as CorvidPopulation
	if birds == null or birds.visitors().size() >= 3:
		return
	var targets: Array[RoofPerch] = []
	for perch: RoofPerch in _perches():
		if perch.host != null and perch.host.is_in_group("quest_board_piece"):
			targets.append(perch)
	if targets.is_empty():
		return
	var goal: Vector2 = targets[_rng.randi() % targets.size()].global_position
	for attempt: int in 14:
		var point: Vector2 = goal + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(SPAWN_RING.x - 120.0, SPAWN_RING.y - 120.0)
		if not _alive_players_far(point, 260.0):
			continue
		var bird: WildCorvid = birds.spawn_visitor("crow", point, "town")
		if bird != null:
			bird._take_wing(false, false, false, true)
			return


func _fox_visit() -> void:
	var stores: Array[int] = town.built_ids("stockpile")
	var woods: WoodlandPopulation = _population("WoodlandPopulation") as WoodlandPopulation
	if stores.is_empty() or woods == null or not _watched() or not woods.visitors().is_empty():
		return
	var store: Vector2 = town.position_of(stores[_rng.randi() % stores.size()])
	var spot: Vector2 = town.stand_point(store + Vector2(_rng.randf_range(-14.0, 14.0), 14.0)) ## in front of it, a little off its door
	for attempt: int in 14:
		var point: Vector2 = spot + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(SPAWN_RING.x - 60.0, SPAWN_RING.y)
		if not _alive_players_far(point, 300.0):
			continue
		if woods.spawn_visitor("fox", point, spot, store + Vector2(0.0, -10.0)) != null:
			return


## Dev / tests: a visit right now, whatever the time (night rules and chances skipped).
func debug_visit(kind: String) -> Node:
	if kind == "fox":
		var stores: Array[int] = town.built_ids("stockpile")
		var woods: WoodlandPopulation = _population("WoodlandPopulation") as WoodlandPopulation
		if stores.is_empty() or woods == null:
			return null
		var store: Vector2 = town.position_of(stores[0])
		var spot: Vector2 = town.stand_point(store + Vector2(0.0, 14.0))
		for attempt: int in 16:
			var point: Vector2 = spot + Vector2.from_angle(_rng.randf() * TAU) * 120.0
			var fox: WoodlandMammal = woods.spawn_visitor("fox", point, spot, store + Vector2(0.0, -10.0))
			if fox != null:
				return fox
		return null
	var birds: CorvidPopulation = _population("CorvidPopulation") as CorvidPopulation
	var perches: Array[RoofPerch] = _perches()
	if birds == null or perches.is_empty():
		return null
	for attempt: int in 16:
		var bird: WildCorvid = birds.spawn_visitor("crow", perches[0].global_position + Vector2.from_angle(_rng.randf() * TAU) * 160.0, "town")
		if bird != null:
			bird._take_wing(false, false, false, true)
			return bird
	return null
