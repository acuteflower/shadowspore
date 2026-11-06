extends Node
## Two actual arena spawners: late-join snapshot of a windup, every state replicated atomically, client F3 request, death/despawn.
## Host -- --server, then client without flags. Loopback only, port 17897, no saves.
const ARENA: PackedScene = preload("res://src/world/test_level.tscn")
const PORT: int = 17897

class EmptyArena:
	extends TestLevel
	func _spawn_player(_id: int) -> void:
		pass
	func _fill_ground() -> void:
		pass

var _arena: TestLevel
var _server: bool
var _joined: bool = false


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
	multiplayer.peer_connected.connect(func(_id: int) -> void: _joined = true)
	_arena = ARENA.instantiate() as TestLevel
	_arena.set_script(EmptyArena)
	_arena.name = "Arena"
	add_child(_arena)
	_run.call_deferred()


func _run() -> void:
	if _server:
		var actor: VoidCrusher = _arena._spawn_crusher(Vector2.ZERO)
		actor.set_physics_process(false)
		actor._apply_state(VoidCrusher.State.SLAM_WINDUP, Vector2.RIGHT, Vector2(3, 5), 54.0, 0.5, VoidCrusher.State.CHASE)
		for frame: int in 600:
			if _joined:
				break
			await get_tree().physics_frame
		await get_tree().create_timer(0.4).timeout
		for next: int in [VoidCrusher.State.SLAM, VoidCrusher.State.SLAM_RECOVER, VoidCrusher.State.RUSH_WINDUP, VoidCrusher.State.RUSH, VoidCrusher.State.RUSH_RECOVER, VoidCrusher.State.SWEEP_WINDUP, VoidCrusher.State.SWEEP, VoidCrusher.State.SWEEP_RECOVER, VoidCrusher.State.STUN, VoidCrusher.State.HURT, VoidCrusher.State.CHASE, VoidCrusher.State.SEARCH]:
			actor._apply_state.rpc(next, Vector2.RIGHT, Vector2(3, 5), 54.0, 0.0, actor.state)
			await get_tree().create_timer(0.2).timeout
		actor._health.take_damage(1000.0, Vector2(-30, 0), 80.0)
		await get_tree().create_timer(2.5).timeout
		var second: VoidCrusher = _arena.get_node_or_null("Enemies/Crusher2") as VoidCrusher
		print("Crusher network server: client spawn=", second != null)
		get_tree().quit(0 if second != null else 1)
	else:
		var seen: Dictionary = {}
		var atomic: bool = true
		var late_windup: bool = false
		var requested: bool = false
		var second_seen: bool = false
		var died: bool = false
		var gone: bool = false
		for frame: int in 900:
			await get_tree().physics_frame
			var actor: VoidCrusher = _arena.get_node_or_null("Enemies/Crusher1") as VoidCrusher
			if actor != null:
				actor.set_physics_process(false)
				if actor.state != VoidCrusher.State.IDLE:
					seen[actor.state] = true
					atomic = atomic and actor.attack_dir == Vector2.RIGHT and actor.attack_origin == Vector2(3, 5) and actor.warning_length == 54.0
					if actor.state == VoidCrusher.State.SLAM_WINDUP and actor._state_time >= 0.5 and actor._rig._pose == CrusherRig.Pose.SLAM_WINDUP:
						late_windup = true
					died = died or actor.state == VoidCrusher.State.DEAD
				if not requested:
					_arena._rpc_spawn_crusher.rpc_id(1, Vector2(150, 100))
					requested = true
			elif died:
				gone = true
			second_seen = second_seen or _arena.has_node("Enemies/Crusher2")
			if gone and second_seen:
				break
		var ok: bool = atomic and late_windup and second_seen and gone and seen.size() == 14
		print("Crusher network client: %d/14 states, atomic=%s, late windup=%s, client spawn=%s, death=%s" % [seen.size(), atomic, late_windup, second_seen, gone])
		get_tree().quit(0 if ok else 1)
