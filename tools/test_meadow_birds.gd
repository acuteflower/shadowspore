extends Node
## Offline integration: Godot --headless --path . tools/test_meadow_birds.tscn

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


func _make(population: CorvidPopulation, species: String, at: Vector2) -> WildMeadowBird:
	var bird: WildMeadowBird = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildMeadowBird
	bird.name = species.capitalize()
	bird.species = species
	bird.position = at
	bird.home = at
	bird.flock_id = species
	population._birds.add_child(bird)
	bird.set_physics_process(false)
	return bird


func _run() -> void:
	var population: CorvidPopulation = load("res://src/world/corvid_population.tscn").instantiate() as CorvidPopulation
	add_child(population)
	population.setup(4, func(_at: Vector2, _species: String) -> bool: return true)
	population.set_process(false)
	for y: int in range(-3, 4):
		for x: int in range(-3, 4):
			population._active[Vector2i(x, y)] = true
	var owl: WildMeadowBird = _make(population, "owl", Vector2.ZERO)
	var hoopoe: WildMeadowBird = _make(population, "hoopoe", Vector2(90, 0))
	TimeManager.time_of_day = 0.5
	owl._think()
	owl._process(0.0)
	_check(owl.state == WildCorvid.State.ROOST and owl._sprite.frame % 50 < 4, "Daytime owl did not sleep with closed eyes")
	owl._call_pose = 0.0
	owl._request_call(false)
	_check(owl._call_pose == 0.0 and not owl._voice.playing, "Sleeping owl kept calling")
	_check(owl._calls[0] != hoopoe._calls[0], "New species share the wrong voice")
	owl.hear_alarm(Vector2(-40, 0))
	_check(owl.state == WildCorvid.State.WATCH and not owl._moving and owl._panic_delay < 0.0, "Daytime owl blindly joined a corvid flock escape")
	owl._think()
	_check(owl.state == WildCorvid.State.WATCH, "Alarmed owl went straight back to sleep before observing")
	owl._set_mood(WildCorvid.State.ROOST, 30.0)
	TimeManager.time_of_day = 0.97
	owl._think()
	owl._process(0.0)
	_check(owl.state == WildCorvid.State.PECK and owl._sprite.frame % 50 in range(4, 10), "Twilight did not immediately wake the owl into its listening pose")
	_check(not owl._rest_time() and hoopoe._rest_time(), "Owl and hoopoe have identical day/night rhythms")
	_check(owl._preferred_cruise(false, 0.0) < owl._preferred_cruise(true, 0.0), "Quiet nocturnal patrol is not lower than escape flight")

	owl._act(WildCorvid.State.FLY, 3.0, 0.0, Vector2.ZERO, Vector2(320, 0), Vector2(0, 45), 0.0, 0.0, 25.0, "", 0.0)
	var previous: float = -1.0
	for t: float in [0.08, 0.18, 0.4, 0.6, 0.82, 0.94]:
		owl._elapsed = t * owl._duration
		owl._advance()
		owl._process(0.0)
		_check(owl.global_position.x > previous, "Owl contains a stationary vertical flight phase")
		_check(owl._height > 0.0 and owl._height <= 25.0, "Owl's low glide left its planned height arc")
		if t == 0.6:
			_check(owl._sprite.frame % 50 == 34, "Owl lacks its long wings-out glide")
		previous = owl.global_position.x
	owl._finish(Vector2(320, 0), 0.0, "")
	owl._process(0.0)
	_check(owl._sprite.z_index == 0 and owl._sprite.position.y == 0.0, "Landed owl did not rejoin ground depth ordering")

	hoopoe._set_mood(WildCorvid.State.ROOST, 4.0)
	hoopoe._process(0.0)
	_check(hoopoe._sprite.frame % 50 < 4, "Roosting hoopoe did not fold its crest")
	TimeManager.time_of_day = 0.5
	hoopoe._set_mood(WildCorvid.State.PECK, 3.0)
	hoopoe._process(0.0)
	_check(hoopoe._sprite.frame % 50 in range(4, 10), "Hoopoe has no probing animation")
	hoopoe._set_mood(WildCorvid.State.WATCH, 1.2)
	hoopoe._elapsed = 0.2
	hoopoe._process(0.0)
	var opening: int = hoopoe._sprite.frame
	hoopoe._elapsed = 1.0
	hoopoe._process(0.0)
	_check(opening != hoopoe._sprite.frame and hoopoe._sprite.frame % 50 == 25, "Crest did not open and settle into its folded alert pose")
	hoopoe._act(WildCorvid.State.FLY, 3.0, 0.0, Vector2(0, 100), Vector2(300, 100), Vector2(0, 50), 0.0, 0.0, 43.0, "", 1.1)
	hoopoe._advance()
	var actual: float = hoopoe._height
	var t: float = hoopoe._elapsed / hoopoe._duration
	var base: float = lerpf(0.0, 43.0, smoothstep(0.0, 0.42, t))
	_check(absf(actual - base) > 0.1 and absf(actual - base) <= 2.8, "Hoopoe's light undulating flight is missing or too strong")
	hoopoe._finish(Vector2(300, 100), 0.0, "")
	hoopoe._call_pose = 0.0
	var visited: Dictionary = {}
	for step: int in 50:
		hoopoe._elapsed = hoopoe._duration + 0.1
		hoopoe._think()
		visited[hoopoe.state] = true
		if hoopoe._moving:
			hoopoe._elapsed = hoopoe._duration
			hoopoe._advance()
		await get_tree().physics_frame
	_check(visited.has(WildCorvid.State.PECK) and visited.has(WildCorvid.State.WALK), "Hoopoe failed to alternate searching and ground steps")

	# Complete build/direction coverage, without mirroring the head or bill.
	for bird: WildMeadowBird in [owl, hoopoe]:
		for coat: int in 3:
			bird.appearance = coat
			for sector: int in 8:
				bird.facing = sector * PI / 4.0
				bird._set_mood(WildCorvid.State.WATCH, 2.0)
				bird._process(0.0)
				_check(bird._sprite.frame >= 0 and bird._sprite.frame < 2400, "Special bird frame outside atlas")
				_check(bird._sprite.texture.resource_path.ends_with("meadow_birds.png"), "Special species inherited the crow texture")
	owl.queue_free()
	hoopoe.queue_free()
	population.queue_free()
	await get_tree().process_frame

	var world: WorldLevel = load("res://src/world/world_level.tscn").instantiate() as WorldLevel
	world.set_script(EmptyWorld)
	add_child(world)
	for frame: int in 30:
		await get_tree().physics_frame
	population = world.get_node("Wildlife/Corvids") as CorvidPopulation
	population.set_process(false)
	_check(population._birds.get_child_count() <= 11, "New species increased the shared bird budget")
	_check(population._species_count("owl") <= 1 and population._species_count("hoopoe") <= 2, "Rare species exceeded their individual caps")
	var tree: FirTree = get_tree().get_first_node_in_group("bird_perches") as FirTree
	_check(tree != null, "No tree available for daytime owl roost")
	if tree != null:
		owl = _make(population, "owl", tree.global_position + Vector2(30, 30))
		var perch: Dictionary = population.choose_perch(owl, Vector2.INF)
		_check(not perch.is_empty(), "Owl could not reserve a real tree perch")
		if not perch.is_empty():
			owl._finish(perch["position"], perch["height"], perch["path"])
			TimeManager.time_of_day = 0.5
			owl._think()
			owl._process(0.0)
			_check(owl._height > 20.0 and owl.state == WildCorvid.State.ROOST and owl._sprite.z_index == 0, "Sleeping owl lost its branch height or normal tree ordering")
	world.queue_free()
	await get_tree().process_frame
	Terrain.relief = null
	await get_tree().create_timer(0.08).timeout
	print("Owl/hoopoe: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
