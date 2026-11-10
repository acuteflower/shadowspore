extends Node
## Two processes on loopback (port 17899): the host swims (tread -> crawl -> out) and the client must see the synced `swim` state and play the
## matching swim clips on its own copy of the player. Server first with `-- --server`, then the client without it.

var _joined: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var server: bool = OS.get_cmdline_user_args().has("--server")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error
	if server:
		peer.set_bind_ip("127.0.0.1")
		error = peer.create_server(17899, 1)
	else:
		error = peer.create_client("127.0.0.1", 17899)
	if error != OK:
		push_error(error_string(error))
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(_id: int) -> void: _joined = true)
	var player: Player = load("res://src/entities/player/player.tscn").instantiate() as Player
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	if server:
		for frame: int in 900:
			if _joined:
				break
			await get_tree().physics_frame
		await get_tree().create_timer(0.8).timeout
		player.swim = SwimRules.TREAD
		player.swimmer.blend = 1.0
		await get_tree().create_timer(1.2).timeout
		player.swim = SwimRules.CRAWL
		await get_tree().create_timer(1.5).timeout
		player.swim = SwimRules.NONE
		await get_tree().create_timer(1.2).timeout
		print("Swim network server complete")
		get_tree().quit()
	else:
		var seen: Dictionary = {}
		for frame: int in 900:
			await get_tree().physics_frame
			player._animate(1.0 / 60.0)
			if player.swim == SwimRules.TREAD:
				seen["tread"] = true
				if player._sheet == 13:
					seen["tread_sheet"] = true
			if player.swim == SwimRules.CRAWL and player._sheet == 13 and player._swim_level == 2:
				seen["crawl_clip"] = true
			if seen.has("crawl_clip") and player.swim == SwimRules.NONE:
				seen["out"] = true
			if seen.size() >= 4:
				break
		var ok: bool = seen.size() >= 4
		print("Swim network client ", "OK" if ok else "FAILED %s" % str(seen))
		get_tree().quit(0 if ok else 1)
