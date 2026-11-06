extends Node
var _rivers: WorldRivers
var _joined: bool = false
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var server: bool = OS.get_cmdline_user_args().has("--server")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error
	if server:
		peer.set_bind_ip("127.0.0.1")
		error = peer.create_server(17895, 1)
	else: error = peer.create_client("127.0.0.1", 17895)
	if error != OK:
		push_error(error_string(error))
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	_rivers = WorldRivers.new()
	add_child(_rivers)
	multiplayer.peer_connected.connect(func(_id: int) -> void: _joined = true)
	if server:
		for frame: int in 600:
			if _joined: break
			await get_tree().physics_frame
		await get_tree().create_timer(0.25).timeout
		var data: Dictionary = DataRegistry.table("rivers_baked")
		var samples: Array = []
		for basin: Dictionary in data["basins"]:
			var point: Vector2 = Vector2(float(basin["outlet"][0]), float(basin["outlet"][1]))
			samples.append([point, _rivers.field_at(point), _rivers.surface_at(point)])
		for lake: Dictionary in DataRegistry.table("lakes_baked")["lakes"]:
			for key: String in ["shore", "deep"]:
				var at: Array = lake[key]
				var point: Vector2 = Vector2(float(at[0]), float(at[1]))
				samples.append([point, _rivers.field_at(point), _rivers.surface_at(point)])
		_verify.rpc(FileAccess.get_sha256("res://data/rivers_baked.json"), FileAccess.get_sha256("res://data/lakes_baked.json"), samples)
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
	else:
		await get_tree().create_timer(10).timeout
		push_error("River network timed out")
		get_tree().quit(1)

@rpc("authority", "call_remote", "reliable")
func _verify(digest: String, lake_digest: String, samples: Array) -> void:
	var ok: bool = digest == FileAccess.get_sha256("res://data/rivers_baked.json")
	ok = ok and lake_digest == FileAccess.get_sha256("res://data/lakes_baked.json")
	for sample: Array in samples:
		ok = ok and _rivers.field_at(sample[0] as Vector2).is_equal_approx(sample[1] as Vector2) and _rivers.surface_at(sample[0] as Vector2) == String(sample[2])
	print("Water network: same river/lake bakes, depth, exclusions and surfaces on both peers: ", ok)
	get_tree().quit(0 if ok else 1)
