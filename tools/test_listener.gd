extends Node
## Offline combat/evidence/projectile regression. No save writes or game socket.
const ARENA: PackedScene = preload("res://src/world/test_level.tscn")

class EmptyArena:
	extends TestLevel
	func _spawn_player(_id: int) -> void:
		pass
	func _fill_ground() -> void:
		pass

class SplitHeight:
	extends Relief
	func level_at(point: Vector2) -> float:
		return 1.0 if point.y < -20.0 else 0.0

var _checks: int = 0
var _failed: int = 0
var _arena: TestLevel
var _actor: VoidListener
var _player: Player


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error(message)


func _wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	var collider: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size
	collider.shape = shape
	body.position = at
	body.add_child(collider)
	_arena.add_child(body)
	return body


func _reset_player(at: Vector2) -> void:
	_player.position = at
	_player.velocity = Vector2.ZERO
	_player.stealth.sneaking = false
	_player.sprinting = false
	_player.health.max_health = 1000.0
	_player.health.current = 1000.0
	_player.health.invulnerable_seconds = 0.0
	_player.health._invulnerable_until_msec = 0


func _wave() -> ResonanceWave:
	var wave: ResonanceWave = _arena.spawn_resonance(Vector2.ZERO, Vector2.RIGHT, Vector2(4, -34))
	wave.set_physics_process(false)
	return wave


func _run() -> void:
	Terrain.relief = null
	_arena = ARENA.instantiate() as TestLevel
	_arena.set_script(EmptyArena)
	add_child(_arena)
	_player = load("res://src/entities/player/player.tscn").instantiate() as Player
	_player.name = "2"
	_arena.get_node("Players").add_child(_player)
	_player.set_physics_process(false)
	_actor = _arena._spawn_listener(Vector2.ZERO)
	_actor.set_physics_process(false)
	_actor.set_process(false)
	await get_tree().physics_frame
	_check(_actor._health.current == 38.0 and _actor._world == _arena, "Listener did not load its own definition/world")
	var f2: InputEventKey = InputMap.action_get_events("debug_spawn_listener")[0] as InputEventKey
	var f3: InputEventKey = InputMap.action_get_events("debug_spawn_crusher")[0] as InputEventKey
	var f4: InputEventKey = InputMap.action_get_events("debug_time")[0] as InputEventKey
	_check(f2.physical_keycode == KEY_F2 and f3.physical_keycode == KEY_F3 and f4.physical_keycode == KEY_F4, "F2/F3 spawn keys conflict with the clock binding")
	_check((_arena.get_node("EnemySpawner") as MultiplayerSpawner).get_spawnable_scene_count() == 3, "Enemy spawner does not register all enemy species")
	# Quiet sneaking behind its head avoids detection; sprinting there is audible.
	_reset_player(Vector2(-120, 0))
	_actor.heading = 0.0
	_actor._target = null
	_actor._memory = 0.0
	_player.velocity = Vector2.RIGHT * 30
	_player.stealth.sneaking = true
	_actor._sense()
	_check(_actor._target == null, "Listener detected distant quiet sneaking behind its head")
	_player.stealth.sneaking = false
	_player.sprinting = true
	_player.velocity = Vector2.RIGHT * 120
	_actor._sense()
	_check(_actor._target == _player and _actor.state == VoidListener.State.NOTICE, "Listener ignored loud movement behind it")
	var known: Vector2 = _actor._known
	_reset_player(Vector2(-300, 0))
	_actor._sense()
	_check(_actor._known == known and _actor._memory > 0.0, "Listener tracks a hidden player's live coordinates instead of evidence")
	_actor._memory = 0.0
	_actor._hunt(0.01)
	_check(_actor.state == VoidListener.State.SEARCH, "Lost evidence did not trigger an investigation")
	# Both attacks lock the last quarter second; a finisher interrupts the charge.
	_reset_player(Vector2(110, 0))
	_actor._known = _player.position
	_actor._memory = 8.0
	_actor._set_state(VoidListener.State.WAVE_WINDUP)
	_actor._state_time = 0.56
	_actor._windup(0.01)
	var locked: Vector2 = _actor.attack_dir
	_actor._known = Vector2(0, 110)
	_actor._state_time = 0.68
	_actor._windup(0.01)
	_check(_actor.attack_dir.is_equal_approx(locked), "Wave retargeted after its direction lock")
	_actor._health.take_damage(3.0, _player.position, 30.0)
	_check(_actor.state == VoidListener.State.WAVE_WINDUP, "Light hit cancelled a committed charge")
	_actor._health.take_damage(3.0, _player.position, 80.0)
	_check(_actor.state == VoidListener.State.HURT and _arena.get_node("EnemyProjectiles").get_child_count() == 0, "Interrupted charge still fired a projectile")
	_actor.position = Vector2(-200, 150)
	# A real moving wave cannot hit at launch, cannot tunnel on a long frame, hits once.
	_reset_player(Vector2(70, 0))
	await get_tree().physics_frame
	var wave: ResonanceWave = _wave()
	_check(wave._visual_at(0).is_equal_approx(Vector2(4, -34)), "White projectile was not emitted at the supplied throat point")
	wave._physics_process(0.1)
	_check(_player.health.current == 1000.0 and wave.travelled > 20.0, "Projectile hit before travelling to its target")
	wave._physics_process(0.28)
	_check(_player.health.current == 986.0, "Travelling wave tunneled over its target on a long frame")
	wave._physics_process(0.1)
	_check(_player.health.current == 986.0, "Wave hit the same player twice")
	_check(wave._visual_at(100).y > wave.emission_point.y, "Projectile never descended from the throat into the target plane")
	wave.queue_free()
	await get_tree().physics_frame
	# Body-sized cover stops the entire pressure front, including grazing hits.
	_reset_player(Vector2(70, 0))
	var wall: StaticBody2D = _wall(Vector2(35, 0), Vector2(4, 50))
	await get_tree().physics_frame
	wave = _wave()
	wave._physics_process(0.5)
	_check(wave.stopped and wave.travelled < 29.0 and _player.health.current == 1000.0, "Projectile passed through solid cover")
	wave.queue_free()
	wall.queue_free()
	await get_tree().physics_frame
	# Defensive pulse has a readable delay, one hit and an open back/flank.
	_actor.position = Vector2.ZERO
	_actor._known = Vector2(30, 0)
	_actor._memory = 8.0
	_reset_player(Vector2(30, 0))
	await get_tree().physics_frame
	_actor._set_state(VoidListener.State.SCREAM_WINDUP)
	_actor._set_state(VoidListener.State.SCREAM)
	_actor._state_time = 0.05
	_actor._scream_hit()
	_check(_player.health.current == 1000.0, "Shockwave hit before its pressure front expanded")
	_actor._state_time = 0.14
	_actor._scream_hit()
	_actor._scream_hit()
	_check(_player.health.current == 991.0, "Defensive pulse missed or dealt repeated damage")
	_reset_player(Vector2(-28, 0))
	await get_tree().physics_frame
	_actor._set_state(VoidListener.State.SCREAM)
	_actor._state_time = 0.14
	_actor._scream_hit()
	_check(_player.health.current == 1000.0, "Defensive pulse hit behind the announced fan")
	_actor._set_state(VoidListener.State.RECOVER)
	_check(_actor._recovery() >= 1.0 and _actor._scream_age() >= 0.22, "Defensive pulse lacks a punish window or surviving echo rings")
	# Walls and height differences block the close attack as well.
	_reset_player(Vector2(30, 0))
	wall = _wall(Vector2(15, 0), Vector2(3, 50))
	await get_tree().physics_frame
	_actor._set_state(VoidListener.State.SCREAM)
	_actor._state_time = 0.14
	_actor._scream_hit()
	_check(_player.health.current == 1000.0, "Defensive scream hit through cover")
	wall.queue_free()
	await get_tree().physics_frame
	Terrain.relief = SplitHeight.new()
	_reset_player(Vector2(0, -35))
	_actor._known = _player.position
	_actor._set_state(VoidListener.State.SCREAM_WINDUP)
	_actor._set_state(VoidListener.State.SCREAM)
	_actor._state_time = 0.14
	await get_tree().physics_frame
	_actor._scream_hit()
	_check(_player.health.current == 1000.0, "Scream damaged a player on another height")
	wave = _arena.spawn_resonance(Vector2.ZERO, Vector2.UP)
	wave.set_physics_process(false)
	wave._physics_process(0.5)
	_check(wave.stopped and _player.health.current == 1000.0, "Projectile travelled across a height discontinuity")
	wave.queue_free()
	Terrain.relief = null
	# Rig: charge is a real opening, and the close attack has its own compression/recoil.
	var rig: ListenerRig = _actor._rig
	rig.start_pose(ListenerRig.Pose.CHARGE, 0.8)
	rig.update_rig(0.79, Vector2.ZERO, 0.0)
	var opening: float = rig._opening
	var height: float = rig._head.y
	rig.start_pose(ListenerRig.Pose.BRACE, 0.6)
	rig.update_rig(0.59, Vector2.ZERO, 0.0)
	var compressed: float = rig._head.y
	rig.start_pose(ListenerRig.Pose.SCREAM, 0.22)
	rig.update_rig(0.09, Vector2.ZERO, 0.0)
	_check(opening > 0.9 and rig._opening > opening and compressed > height and rig._head.y < compressed - 5.0, "Close attack does not compress, snap open and recoil")
	var intact: bool = true
	for limb: ListenerRig.Limb in rig._limbs:
		intact = intact and limb.points[-1].distance_to(limb.foot - rig.global_position - Vector2(0, limb.lift)) < 0.01
	_check(intact, "Morph limb endpoints disconnected from their contacts")
	# Run the real state machine: medium-range pressure, then a close approach.
	_actor.position = Vector2(-190, 80)
	_actor.velocity = Vector2.ZERO
	_actor.heading = 0.0
	_actor._target = null
	_actor._memory = 0.0
	_actor._wave_cd = 0.0
	_actor._scream_cd = 0.0
	_actor._health.current = 38.0
	_actor._set_state(VoidListener.State.LISTEN)
	_reset_player(_actor.position + Vector2(112, 0))
	var visited: Dictionary = {}
	for frame: int in 480:
		_player.position = _actor.position + Vector2(112 if frame < 250 else 30, 0)
		_player.velocity = Vector2.RIGHT * 40
		await get_tree().physics_frame
		_actor._physics_process(1.0 / 60.0)
		_actor._process(1.0 / 60.0)
		visited[_actor.state] = true
	for expected: int in [VoidListener.State.NOTICE, VoidListener.State.HUNT, VoidListener.State.WAVE_WINDUP, VoidListener.State.WAVE_RELEASE, VoidListener.State.SCREAM_WINDUP, VoidListener.State.SCREAM, VoidListener.State.RECOVER]:
		_check(visited.has(expected), "Live listener fight never reached %s" % VoidListener.State.keys()[expected])
	_check(_player.health.current < 980.0, "Live listener never connected its attacks")
	# This offline target has no connected peer/inventory recipient. Keep death
	# loot from trying to award a random nearby drop to the synthetic peer2.
	_player.remove_from_group("players")
	_actor._health.take_damage(100.0, Vector2(30, 0), 80.0)
	_check(_actor.state == VoidListener.State.DEAD and _actor.velocity == Vector2.ZERO, "Death failed to stop the listener")
	print("Listener: %d checks, %d failures" % [_checks, _failed])
	await get_tree().create_timer(1.4).timeout
	_arena.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)
