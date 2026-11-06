extends Node
## Run twice: Godot --headless --path . tools/test_void_predator_network.tscn -- --server
## then the same scene without --server. Isolated loopback port, no saves or game session.

const PORT: int = 17887
var _server: bool = false
var _seen: Dictionary = {}
var _failed: bool = false
var _joined: bool = false
var _actor: ShadowSpider


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
		push_error("Network test could not connect: " + error_string(error))
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	var enemies: Node2D = Node2D.new()
	enemies.name = "Enemies"
	add_child(enemies)
	var spawner: MultiplayerSpawner = MultiplayerSpawner.new()
	spawner.name = "Spawner"
	spawner.spawn_path = NodePath("../Enemies")
	spawner.add_spawnable_scene("res://src/entities/enemies/shadow_spider.tscn")
	add_child(spawner)
	multiplayer.peer_connected.connect(func(_id: int) -> void: _joined = true)
	_run.call_deferred()


func _run() -> void:
	if _server:
		_actor = load("res://src/entities/enemies/shadow_spider.tscn").instantiate() as ShadowSpider
		_actor.name = "Predator"
		get_node("Enemies").add_child(_actor)
		_actor.set_physics_process(false)
		# Joining midway through a climb must restore endpoints and elapsed leg pose.
		_actor._apply_state(ShadowSpider.State.CLIMB, Vector2.RIGHT, Vector2(110, 0), Vector2.ZERO, -1.0, 0.35, ShadowSpider.State.CLIMB_WINDUP)
		for frame: int in 600:
			if _joined:
				break
			await get_tree().physics_frame
		await get_tree().create_timer(0.5).timeout
		var sequence: Array[int] = [ShadowSpider.State.WINDUP, ShadowSpider.State.STRIKE, ShadowSpider.State.RECOVER, ShadowSpider.State.GRAPPLE_WINDUP, ShadowSpider.State.GRAPPLE_THROW, ShadowSpider.State.GRAPPLE_PULL, ShadowSpider.State.CLIMB_WINDUP, ShadowSpider.State.CLIMB, ShadowSpider.State.CLIMB_RETREAT, ShadowSpider.State.RECOVER]
		for next: int in sequence:
			_actor._apply_state.rpc(next, Vector2.RIGHT, Vector2(110, 0), Vector2.ZERO, -1.0, 0.0, _actor.state)
			await get_tree().create_timer(0.22).timeout
		await get_tree().create_timer(0.4).timeout
		print("Predator network server: finished")
		get_tree().quit()
	else:
		var joined_climb: bool = false
		for frame: int in 600:
			await get_tree().physics_frame
			_actor = get_node_or_null("Enemies/Predator") as ShadowSpider
			if _actor == null:
				continue
			_actor.set_physics_process(false)
			if _actor.state == ShadowSpider.State.IDLE:
				continue
			_seen[_actor.state] = true
			if _actor.state == ShadowSpider.State.CLIMB and _actor._state_time >= 0.35 and _actor._rig._pose == SpiderRig.Pose.CLIMB:
				joined_climb = true
			if _actor.attack_dir != Vector2.RIGHT or _actor.anchor != Vector2(110, 0) or _actor.attack_side != -1.0:
				_failed = true
				push_error("Torn attack frame received")
			if _seen.size() == 9 and _actor.state == ShadowSpider.State.RECOVER:
				break
		print("Predator network client: %d/9 states, atomic frames: %s, late climb: %s" % [_seen.size(), not _failed, joined_climb])
		get_tree().quit(0 if _seen.size() == 9 and not _failed and joined_climb else 1)
