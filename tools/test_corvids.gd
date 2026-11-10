extends Node
const WORLD_SCENE: PackedScene = preload("res://src/world/world_level.tscn")
## Godot --headless --path . tools/test_corvids.tscn (offline, no save access).

class EmptyWorld:
	extends WorldLevel
	func _spawn_player(_id: int) -> void:
		pass

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)


func _bird(population: CorvidPopulation, species: String, at: Vector2, id: String) -> WildCorvid:
	var bird: WildCorvid = load("res://src/entities/wildlife/wild_corvid.tscn").instantiate() as WildCorvid
	bird.name = id
	bird.species = species
	bird.home = at
	bird.position = at
	bird.flock_id = "test_flock"
	population._birds.add_child(bird)
	bird.set_physics_process(false)
	return bird


func _run() -> void:
	TimeManager.time_of_day = 0.5
	var population: CorvidPopulation = load("res://src/world/corvid_population.tscn").instantiate() as CorvidPopulation
	add_child(population)
	population.setup(4, func(_at: Vector2, _species: String) -> bool: return true)
	population.set_process(false)
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			population._active[Vector2i(x, y)] = true
	var crow: WildCorvid = _bird(population, "crow", Vector2.ZERO, "Crow")
	var companion: WildCorvid = _bird(population, "crow", Vector2(25, 35), "Companion")
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "2"
	player.position = Vector2(105, 0)
	add_child(player)
	player.set_physics_process(false)
	await get_tree().physics_frame
	crow._sense()
	_check(crow.state == WildCorvid.State.WATCH, "A quiet approach should first attract attention")
	crow._set_mood(WildCorvid.State.PECK, 3.0)
	player.stealth.sneaking = true
	crow._sense()
	_check(crow.state == WildCorvid.State.PECK, "Sneaking should allow closer observation")
	player.stealth.sneaking = false
	player.sprinting = true
	player.position = Vector2(85, 0)
	await get_tree().physics_frame
	crow._sense()
	_check(crow.state == WildCorvid.State.FLY, "Sprint within danger range did not flush the crow")
	_check(companion._panic_delay >= 0.12 and companion._panic_delay <= 0.42, "Flock alarm has no staggered reaction")
	_check(companion._rally.is_equal_approx(crow._end), "Flock did not share a rally destination")
	_check(crow._end.distance_to(player.position) >= float(crow._spec["safe_landing_range"]), "Escape ended too close to danger")
	player.position = Vector2(900, 900)
	await get_tree().physics_frame
	crow._elapsed = crow._duration * 0.5
	crow._advance()
	crow._process(0.0)
	_check(crow._height >= crow._cruise * 0.85 and crow._sprite.z_index == 5, "Cruising bird did not clear ground objects")
	crow._elapsed = crow._duration
	crow._advance()
	crow._process(0.0)
	_check(not crow._moving and crow._height == 0.0 and crow._sprite.z_index == 0, "Landing did not restore feet-based depth ordering")

	# The entire flight route advances while climbing AND descending: no drone-like vertical legs.
	crow._act(WildCorvid.State.FLY, 3.0, 0.0, Vector2.ZERO, Vector2(300, 0), Vector2(0, 60), 0.0, 0.0, 64.0, "", 0.0)
	var earlier: Vector2 = crow.position
	for t: float in [0.08, 0.16, 0.3, 0.5, 0.7, 0.86, 0.94]:
		crow._elapsed = t * crow._duration
		crow._advance()
		_check(crow.position.x > earlier.x, "Flight contains a stationary vertical climb/descent")
		_check(crow._height > 0.0 and crow._height <= 64.0, "Flight altitude outside its planned arc")
		earlier = crow.position
	_check(crow.facing < 0.0, "Bird did not turn into the tangent of its curved approach")
	crow._finish(Vector2(300, 0), 0.0, "")

	# A landing blocked after takeoff is re-planned; if none is legal, circle rather than hover.
	population._habitat = func(_at: Vector2, _kind: String) -> bool: return false
	crow._act(WildCorvid.State.FLY, 1.0, 0.0, Vector2.ZERO, Vector2(120, 0), Vector2.ZERO, 0.0, 0.0, 60.0, "", 1.0)
	crow._advance()
	_check(crow.state == WildCorvid.State.FLY and crow._end.distance_to(crow._start) > 20.0, "Rejected landing produced a stationary hover")
	population._habitat = func(_at: Vector2, _kind: String) -> bool: return true
	crow._finish(Vector2(300, 0), 0.0, "")

	crow._danger = false
	crow._caution_left = 0.0
	crow._set_mood(WildCorvid.State.IDLE, 0.1)
	companion._panic_delay = -1.0
	companion.position = crow.position + Vector2(30, 0)
	companion._set_mood(WildCorvid.State.IDLE, 0.1)
	_check(crow._socialise([companion]), "Pair did not perform a social/preening interaction")
	_check(crow.state == WildCorvid.State.SOCIAL and companion.state == WildCorvid.State.SOCIAL, "Social interaction did not reach both birds")
	crow._set_mood(WildCorvid.State.IDLE, 1.0)
	companion._set_mood(WildCorvid.State.IDLE, 1.0)
	var flock: Array[WildCorvid] = [crow, companion]
	population._flocks[Vector2i.ZERO] = flock
	population._maintain()
	_check(crow.state == WildCorvid.State.WATCH, "Flock did not assign its first watch turn")
	crow._set_mood(WildCorvid.State.IDLE, 1.0)
	population._maintain()
	_check(companion.state == WildCorvid.State.WATCH, "Watch duty did not rotate")
	_check(population.authorize_call("voice_test") and not population.authorize_call("voice_test"), "Flock calls have no density limit")

	# No perches in this isolated plane: night roosting must not become endless random flight.
	TimeManager.time_of_day = 0.96
	crow._panic_delay = -1.0
	crow._set_mood(WildCorvid.State.IDLE, 0.1)
	crow._elapsed = 1.0
	crow._think()
	_check(crow.state == WildCorvid.State.ROOST and not crow._moving, "Bird without a night perch kept flying")
	TimeManager.time_of_day = 0.5

	# Every species/build/state/facing stays within the atlas; the raven uses a distinct build block.
	for species: String in ["crow", "raven"]:
		crow.species = species
		for coat: int in 3:
			crow.appearance = coat
			for sector: int in 8:
				crow.facing = sector * PI / 4.0
				for mood: int in WildCorvid.State.values():
					crow.state = mood as WildCorvid.State
					crow._process(0.0)
					_check(crow._sprite.frame >= 0 and crow._sprite.frame < 2400, "Bird frame outside atlas")
					_check(crow._sprite.frame / 400 >= (3 if species == "raven" else 0), "Wrong species build")
	crow.queue_free()
	companion.queue_free()
	player.queue_free()
	population.queue_free()
	await get_tree().process_frame

	# Real world integration: population, reservations, cut trees and streamed cross-border flights.
	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	for frame: int in 35:
		await get_tree().physics_frame
	population = world.get_node("Wildlife/Corvids") as CorvidPopulation
	population.set_process(false)
	print("Initial corvid population: ", population._birds.get_child_count())
	_check(population._birds.get_child_count() > 0, "Starting meadow contains no corvids")
	_check(population._birds.get_child_count() <= 11, "Corvid population budget exceeded")
	for node: Node in population._birds.get_children():
		var bird: WildCorvid = node as WildCorvid
		bird.set_physics_process(false)
		_check(world._bird_habitat(bird.home, bird.species), "Bird flock started outside habitat")
	var tree: FirTree = null
	for node: Node in get_tree().get_nodes_in_group("bird_perches"):
		if (node as FirTree).variant >= 1:
			tree = node as FirTree
			break
	_check(tree != null, "Loaded tree perches missing")
	if tree != null:
		var raven: WildCorvid = _bird(population, "raven", tree.position + Vector2(-20, 20), "PerchRaven")
		var offer: Dictionary = population.choose_perch(raven, Vector2.INF)
		_check(not offer.is_empty(), "No perch offered on a loaded uncut tree")
		if not offer.is_empty():
			var perch_tree: FirTree = get_node(NodePath(String(offer["path"]))) as FirTree
			_check((offer["position"] as Vector2).y > perch_tree.position.y, "Perched bird would sort behind its own crown")
			raven._finish(offer["position"], offer["height"], offer["path"])
			raven._process(0.0)
			_check(raven._height > 20.0 and raven._sprite.z_index == 0, "Perch has no elevated feet or lost normal scene depth")
			perch_tree.state = {"f": 1}
			raven._sense()
			_check(raven.state == WildCorvid.State.FLY, "Bird stayed on a felled tree")
		population.release_perch(raven)
		_check(not population._claims.values().has(raven), "Perch reservation leaked")
	world.queue_free()
	await get_tree().process_frame
	Terrain.relief = null
	await get_tree().create_timer(0.08).timeout
	print("Corvids: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
