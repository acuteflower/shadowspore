extends Node
## Two actual arena spawners: late attack/projectile, client F2 request, death/despawn.
## Host -- --server, then client without flags. Loopback only, port17892, no saves.
const ARENA: PackedScene = preload("res://src/world/test_level.tscn")
const PORT: int = 17892

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
		var actor: VoidListener = _arena._spawn_listener(Vector2.ZERO)
		actor.set_physics_process(false)
		actor._apply_state(VoidListener.State.WAVE_WINDUP, Vector2.RIGHT, Vector2(3, 5), 128.0, 0.43, VoidListener.State.HUNT)
		var wave: ResonanceWave = _arena.spawn_resonance(Vector2(30, 20), Vector2.RIGHT, Vector2(33, -14))
		wave.travelled = 25.0
		wave.position = wave.origin + wave.direction * wave.travelled
		wave.set_physics_process(false)
		for frame: int in 600:
			if _joined:
				break
			await get_tree().physics_frame
		await get_tree().create_timer(0.4).timeout
		wave.set_physics_process(true)
		for next: int in [VoidListener.State.WAVE_RELEASE, VoidListener.State.RECOVER, VoidListener.State.SCREAM_WINDUP, VoidListener.State.SCREAM, VoidListener.State.RECOVER, VoidListener.State.HURT, VoidListener.State.HUNT, VoidListener.State.SEARCH]:
			actor._apply_state.rpc(next, Vector2.RIGHT, Vector2(3, 5), 128.0, 0.12 if next == VoidListener.State.SCREAM else 0.0, actor.state)
			await get_tree().create_timer(0.2).timeout
		actor._health.take_damage(100.0, Vector2(30, 0), 80.0)
		await get_tree().create_timer(1.5).timeout
		var second: VoidListener = _arena.get_node_or_null("Enemies/Listener2") as VoidListener
		print("Listener network server: client spawn=", second != null)
		get_tree().quit(0 if second != null else 1)
	else:
		var seen: Dictionary = {}
		var atomic: bool = true
		var late_charge: bool = false
		var saw_wave: bool = false
		var wave_gone: bool = false
		var requested: bool = false
		var second_seen: bool = false
		var died: bool = false
		var gone: bool = false
		for frame: int in 600:
			await get_tree().physics_frame
			var actor: VoidListener = _arena.get_node_or_null("Enemies/Listener1") as VoidListener
			if actor != null:
				actor.set_physics_process(false)
				if actor.state != VoidListener.State.LISTEN:
					seen[actor.state] = true
					atomic = atomic and actor.attack_dir == Vector2.RIGHT and actor.attack_origin == Vector2(3, 5) and actor.warning_length == 128.0
					if actor.state == VoidListener.State.WAVE_WINDUP and actor._state_time >= 0.43 and actor._rig._pose == ListenerRig.Pose.CHARGE:
						late_charge = true
					died = died or actor.state == VoidListener.State.DEAD
				if not requested:
					_arena._rpc_spawn_listener.rpc_id(1, Vector2(150, 100))
					requested = true
			elif died:
				gone = true
			var wave: ResonanceWave = _arena.get_node_or_null("EnemyProjectiles/Resonance1") as ResonanceWave
			if wave != null:
				saw_wave = wave.direction == Vector2.RIGHT and wave.emission_point == Vector2(33, -14) and wave.travelled >= 25.0 and wave._visual_at(0).is_equal_approx(wave.emission_point)
			elif saw_wave:
				wave_gone = true
			second_seen = second_seen or _arena.has_node("Enemies/Listener2")
			if gone and wave_gone and second_seen:
				break
		var ok: bool = atomic and late_charge and saw_wave and wave_gone and second_seen and gone and seen.size() == 9
		print("Listener network client: %d/9 states, atomic=%s, late charge=%s, projectile=%s, client spawn=%s, death=%s" % [seen.size(), atomic, late_charge, saw_wave and wave_gone, second_seen, gone])
		get_tree().quit(0 if ok else 1)
