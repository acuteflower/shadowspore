extends Node
## Two-process loopback check, port 17888. First process: -- --server; second: no flag.

const PORT: int = 17888
var _server: bool = false
var _failed: bool = false
var _saw_hop: bool = false
var _saw_snapshot: bool = false


func _ready() -> void:
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
	var population: Node = load("res://src/world/wildlife_population.tscn").instantiate()
	add_child(population)
	_run.call_deferred()


func _run() -> void:
	if _server:
		var rabbit: WildRabbit = load("res://src/entities/wildlife/wild_rabbit.tscn").instantiate() as WildRabbit
		rabbit.name = "NetworkRabbit"
		rabbit.position = Vector2(20, 0)
		rabbit.home = Vector2(20, 0)
		rabbit.appearance = 5
		rabbit.temperament = 1.07
		get_node("Wildlife/Animals").add_child(rabbit)
		rabbit._set_state(WildRabbit.State.ALERT, 20.0)
		rabbit._begin_hop.rpc(Vector2(20, 0), Vector2(120, 0), 2.5, 7.0, 0.0)
		await get_tree().create_timer(5.0).timeout
		print("Wildlife network server: complete")
		get_tree().quit()
	else:
		for frame: int in 600:
			await get_tree().physics_frame
			var rabbit: WildRabbit = get_node_or_null("Wildlife/Animals/NetworkRabbit") as WildRabbit
			if rabbit == null:
				continue
			if rabbit.appearance != 5 or rabbit.home != Vector2(20, 0) or absf(rabbit.temperament - 1.07) > 0.001:
				_failed = true
			if rabbit._hopping:
				_saw_hop = true
				_saw_snapshot = _saw_snapshot or rabbit._hop_time > 0.15
			if _saw_hop and not rabbit._hopping:
				_failed = _failed or rabbit.position.distance_to(Vector2(120, 0)) > 0.01
				break
		print("Wildlife network client: appearance=%s, mid-hop snapshot=%s, landing=%s" % [not _failed, _saw_snapshot, _saw_hop and not _failed])
		get_tree().quit(0 if _saw_hop and _saw_snapshot and not _failed else 1)
