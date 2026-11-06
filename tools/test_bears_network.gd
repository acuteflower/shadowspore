extends Node
const WORLD: PackedScene = preload("res://src/world/world_level.tscn")
var _pop: BearPopulation
var _joined: bool = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var server: bool = OS.get_cmdline_user_args().has("--server")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error
	if server:
		peer.set_bind_ip("127.0.0.1")
		error = peer.create_server(17894, 1)
	else:
		error = peer.create_client("127.0.0.1", 17894)
	if error != OK:
		push_error(error_string(error))
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(_id: int) -> void: _joined = true)
	_pop = load("res://src/world/bear_population.tscn").instantiate() as BearPopulation
	add_child(_pop)
	_pop.set_process(false)
	if server:
		var mother: WildBear = load("res://src/entities/wildlife/wild_bear.tscn").instantiate() as WildBear
		mother.name = "Mother"
		mother.family_id = "net_family"
		mother.position = Vector2(100, 100)
		mother.home = mother.position
		_pop._residents.add_child(mother)
		mother.set_physics_process(false)
		mother._command(WoodlandMammal.Mood.REAR, 2.0, 0.5, mother.position, mother.position, 1.4)
		var cub: WildBear = load("res://src/entities/wildlife/wild_bear.tscn").instantiate() as WildBear
		cub.name = "Cub"
		cub.family_id = mother.family_id
		cub.appearance = 2
		cub.position = Vector2(140, 100)
		cub.home = mother.home
		_pop._residents.add_child(cub)
		cub.set_physics_process(false)
		cub._command(WoodlandMammal.Mood.PLAY, 3.0, -0.5, cub.position, cub.position, 0.8)
		for frame: int in 600:
			if _joined: break
			await get_tree().physics_frame
		await get_tree().create_timer(0.7).timeout
		mother._issue(WoodlandMammal.Mood.LOWER, 0.65)
		await get_tree().create_timer(0.7).timeout
		mother._issue(WoodlandMammal.Mood.SWIPE, 1.15)
		await get_tree().create_timer(0.7).timeout
		mother._gait_phase = 1.75
		mother._move_action(WoodlandMammal.Mood.CHASE, Vector2(160, 100), 1.5)
		await get_tree().create_timer(0.7).timeout
		mother.queue_free()
		cub.queue_free()
		await get_tree().create_timer(0.5).timeout
		print("Bear network server complete")
		get_tree().quit()
	else:
		var seen: Dictionary = {}
		for frame: int in 600:
			await get_tree().physics_frame
			var mother: WildBear = _pop.get_node_or_null("Residents/Mother") as WildBear
			var cub: WildBear = _pop.get_node_or_null("Residents/Cub") as WildBear
			if mother != null and cub != null:
				if cub.is_cub() and cub._adult() == mother and cub.home == mother.home:
					seen["family"] = true
				if mother.mood == WoodlandMammal.Mood.REAR and mother._elapsed >= 1.4 and mother._sprite.frame % 44 == 43:
					seen["late_rear"] = true
				if cub.mood == WoodlandMammal.Mood.PLAY and cub._sprite.hframes == 6:
					seen["play"] = true
				if mother.mood == WoodlandMammal.Mood.LOWER:
					seen["lower"] = true
				if mother.mood == WoodlandMammal.Mood.SWIPE and mother._sprite.hframes == 8:
					seen["swipe"] = true
				if mother.mood == WoodlandMammal.Mood.CHASE and mother._moving and mother.position.x > 100.0 and mother._gait_phase > 1.75:
					seen["chase"] = true
			elif seen.size() >= 6:
				seen["cleanup"] = true
				break
		print("Bear network: ", seen)
		get_tree().quit(0 if seen.size() == 7 else 1)
