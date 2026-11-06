extends Node
## Two processes on isolated loopback port 17890; first uses -- --server.

const PORT: int = 17890
var _server: bool = false


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
	var population: CorvidPopulation = load("res://src/world/corvid_population.tscn").instantiate() as CorvidPopulation
	add_child(population)
	population.setup(4, func(_at: Vector2, _kind: String) -> bool: return true)
	population._active[Vector2i.ZERO] = true
	_run.call_deferred()


func _run() -> void:
	if _server:
		for i: int in 2:
			var bird: WildCorvid = load("res://src/entities/wildlife/wild_meadow_bird.tscn").instantiate() as WildCorvid
			bird.name = "Bird%d" % i
			bird.species = "hoopoe" if i == 0 else "owl"
			bird.appearance = 2
			bird.flock_id = "network_flock"
			bird.home = Vector2(30, 80 * i)
			bird.position = bird.home
			get_node("Corvids/Birds").add_child(bird)
			if i == 0:
				bird._act.rpc(WildCorvid.State.FLY, 2.7, 0.0, bird.position, Vector2(180, 0), Vector2(0, 10), 0.0, 0.0, 100.0, "", 0.0)
			else:
				bird._set_mood(WildCorvid.State.WATCH, 20.0)
		await get_tree().create_timer(5.0).timeout
		print("Meadow bird network server: complete")
		get_tree().quit()
	else:
		var failed: bool = false
		var saw_flight: bool = false
		var saw_idle: bool = false
		var saw_landing: bool = false
		for frame: int in 600:
			await get_tree().physics_frame
			var crow: WildCorvid = get_node_or_null("Corvids/Birds/Bird0") as WildCorvid
			var raven: WildCorvid = get_node_or_null("Corvids/Birds/Bird1") as WildCorvid
			if crow == null or raven == null:
				continue
			failed = failed or crow.species != "hoopoe" or raven.species != "owl" or int(raven._spec["build_offset"]) != 0
			failed = failed or not (crow is WildMeadowBird) or not (raven is WildMeadowBird)
			failed = failed or not crow._sprite.texture.resource_path.ends_with("meadow_birds.png") or not raven._sprite.texture.resource_path.ends_with("meadow_birds.png")
			failed = failed or crow.appearance != 2 or raven.appearance != 2 or raven.flock_id != "network_flock"
			saw_idle = saw_idle or (raven.state == WildCorvid.State.WATCH and raven.position.distance_to(Vector2(30, 80)) < 0.1)
			if crow.state == WildCorvid.State.FLY:
				saw_flight = saw_flight or (crow._elapsed > 0.15 and crow._cruise == 100.0 and crow._height > 0.0)
			if saw_flight and crow.state != WildCorvid.State.FLY:
				saw_landing = crow.position.distance_to(Vector2(180, 0)) < 0.1 and crow._height == 0.0
				break
		print("Meadow bird network client: species=%s, idle snapshot=%s, mid-flight=%s, landing=%s" % [not failed, saw_idle, saw_flight, saw_landing])
		get_tree().quit(0 if not failed and saw_idle and saw_flight and saw_landing else 1)
