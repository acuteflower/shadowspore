extends Node
## Loopback integration of families, den state, pouncing fox, curled hedgehog and flower flight.
## First process: -- --server; second: no flag. Separate port 17891, no save access.

const PORT: int = 17891
var _server: bool = false
var _population: WoodlandPopulation
var _insects: ButterflyPopulation


func _ready() -> void:
	TimeManager.time_of_day = 0.97
	_server = OS.get_cmdline_user_args().has("--server")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error
	if _server:
		peer.set_bind_ip("127.0.0.1")
		error = peer.create_server(PORT, 1)
	else:
		error = peer.create_client("127.0.0.1", PORT)
	if error != OK:
		push_error(error_string(error))
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	_population = load("res://src/world/woodland_population.tscn").instantiate() as WoodlandPopulation
	add_child(_population)
	_population.setup(4, func(_point: Vector2, _species: String) -> bool: return true)
	_population._active[Vector2i.ZERO] = true
	_insects = load("res://src/world/butterfly_population.tscn").instantiate() as ButterflyPopulation
	add_child(_insects)
	_run.call_deferred()


func _make(species: String, id: String, at: Vector2, appearance: int = 0) -> WoodlandMammal:
	var animal: WoodlandMammal = load("res://src/entities/wildlife/woodland_mammal.tscn").instantiate() as WoodlandMammal
	animal.name = id
	animal.species = species
	animal.appearance = appearance
	animal.family_id = "network_family" if species == "deer" else species
	animal.position = at
	animal.home = at
	_population._residents.add_child(animal)
	animal.set_physics_process(false)
	return animal


func _run() -> void:
	if _server:
		var doe: WoodlandMammal = _make("deer", "Doe", Vector2(20, 40))
		doe._issue(WoodlandMammal.Mood.FORAGE, 20.0)
		var fawn: WoodlandMammal = _make("deer", "Fawn", Vector2(90, 40), 2)
		fawn._gait_phase = 2.375
		fawn._move_action(WoodlandMammal.Mood.WALK, Vector2(45, 45), 2.7)
		fawn.set_physics_process(true)
		var badger: WoodlandMammal = _make("badger", "Badger", Vector2(20, 320), 1)
		badger._issue(WoodlandMammal.Mood.HIDDEN, 20.0)
		var fox: WoodlandMammal = _make("fox", "Fox", Vector2(220, 160), 2)
		fox._move_action(WoodlandMammal.Mood.SPECIAL, Vector2(238, 160), 2.7)
		fox.set_physics_process(true)
		var hedgehog: WoodlandMammal = _make("hedgehog", "Hedgehog", Vector2(20, 240), 1)
		hedgehog._issue(WoodlandMammal.Mood.SPECIAL, 0.8, INF, 0.8)
		var den: WildlifeShelter = load("res://src/entities/wildlife/wildlife_shelter.tscn").instantiate() as WildlifeShelter
		den.name = "Den"
		den.position = Vector2(20, 320)
		_population.get_node("Shelters").add_child(den)
		var butterfly: MeadowButterfly = load("res://src/entities/wildlife/meadow_butterfly.tscn").instantiate() as MeadowButterfly
		butterfly.name = "Butterfly"
		butterfly.appearance = 3
		butterfly.home = Vector2(220, 20)
		butterfly.position = butterfly.home
		butterfly.flowers = [butterfly.home, Vector2(290, 50), Vector2(250, 70)]
		_insects._butterflies.add_child(butterfly)
		butterfly._act.rpc(MeadowButterfly.State.FLY, 2.7, butterfly.home, Vector2(290, 50), Vector2(0, 15), 10.0, 0.0)
		await get_tree().create_timer(5.0).timeout
		print("Woodland network server: complete")
		get_tree().quit()
	else:
		var seen: Dictionary = {}
		var saw_motion: bool = false
		var landed: bool = false
		for frame: int in 600:
			await get_tree().physics_frame
			var doe: WoodlandMammal = _population.get_node_or_null("Residents/Doe") as WoodlandMammal
			var fawn: WoodlandMammal = _population.get_node_or_null("Residents/Fawn") as WoodlandMammal
			var badger: WoodlandMammal = _population.get_node_or_null("Residents/Badger") as WoodlandMammal
			var fox: WoodlandMammal = _population.get_node_or_null("Residents/Fox") as WoodlandMammal
			var hedgehog: WoodlandMammal = _population.get_node_or_null("Residents/Hedgehog") as WoodlandMammal
			var insect: MeadowButterfly = _insects.get_node_or_null("Butterflies/Butterfly") as MeadowButterfly
			var den: Node2D = _population.get_node_or_null("Shelters/Den") as Node2D
			if doe == null or fawn == null or badger == null or fox == null or hedgehog == null or insect == null:
				continue
			if doe.species == "deer" and fawn.is_fawn() and fawn.family_id == doe.family_id:
				seen["family"] = true
			if fawn._moving and is_equal_approx(fawn._gait_start, 2.375) and fawn._gait_phase > 2.375:
				seen["late_join_gait"] = true
			if badger.species == "badger" and badger.appearance == 1 and badger.mood == WoodlandMammal.Mood.HIDDEN and not badger._sprite.visible:
				seen["den_rest"] = true
			if hedgehog.species == "hedgehog" and hedgehog._sprite.frame % 44 == 43:
				seen["curl"] = true
			if den != null and den.position == Vector2(20, 320):
				seen["shelter"] = true
			if fox.species == "fox" and fox.appearance == 2 and fox._moving and fox._elapsed > 0.2 and fox._sprite.position.y < 0.0:
				saw_motion = true
				seen["fox_pounce"] = true
			if insect.appearance == 3 and insect.state == MeadowButterfly.State.FLY and insect._elapsed > 0.2 and insect._alt > 4.0:
				seen["flower_flight"] = true
			if saw_motion and not fox._moving:
				landed = fox.position.distance_to(Vector2(238, 160)) < 0.1
				if seen.size() == 7:
					break
		print("Woodland network client: %d/7 replicated behaviours, landing=%s" % [seen.size(), landed])
		get_tree().quit(0 if seen.size() == 7 and landed else 1)
