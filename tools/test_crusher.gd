extends Node
## Offline regression for the Void Crusher: data, F3 spawn key, directional armour, the three telegraphed attacks, wall stun, rig poses, death and loot. No saves, no game socket.
## Run: Godot --headless --path . --fixed-fps 60 tools/test_crusher.tscn
const ARENA: PackedScene = preload("res://src/world/test_level.tscn")

class EmptyArena:
	extends TestLevel
	func _spawn_player(_id: int) -> void:
		pass
	func _fill_ground() -> void:
		pass

var _checks: int = 0
var _failed: int = 0
var _arena: TestLevel
var _actor: VoidCrusher
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
	_player.set_physics_process(false)


func _reset_actor(heading: float = 0.0) -> void:
	_actor.position = Vector2.ZERO
	_actor.velocity = Vector2.ZERO
	_actor.heading = heading
	_actor.attack_dir = Vector2.from_angle(heading)
	_actor._memory = 0.0
	_actor._flinch_cd = 0.0
	_actor._behind_time = 0.0
	_actor._slam_cd = 0.0
	_actor._rush_cd = 0.0
	_actor._sweep_cd = 0.0
	_actor._set_state(VoidCrusher.State.IDLE)


func _run() -> void:
	Terrain.relief = null
	_arena = ARENA.instantiate() as TestLevel
	_arena.set_script(EmptyArena)
	add_child(_arena)
	_player = load("res://src/entities/player/player.tscn").instantiate() as Player
	_player.name = "2"
	_arena.get_node("Players").add_child(_player)
	_player.set_physics_process(false)
	_actor = _arena._spawn_crusher(Vector2.ZERO)
	_check(_actor != null, "F3 spawn path did not create a crusher")
	_actor.set_physics_process(false)
	_actor.set_process(false)
	await get_tree().physics_frame
	var spec: Dictionary = DataRegistry.get_entry("enemies", "void_crusher")
	_check(_actor._health.current == 80.0 and _actor._world == _arena, "Crusher did not load its own definition/world")
	_check(float(spec["max_health"]) > float(DataRegistry.get_entry("enemies", "shadow_spider")["max_health"]), "Crusher must be tougher than the spider")
	var f3: InputEventKey = InputMap.action_get_events("debug_spawn_crusher")[0] as InputEventKey
	_check(f3.physical_keycode == KEY_F3, "Crusher spawn is not on F3")
	_check((_arena.get_node("EnemySpawner") as MultiplayerSpawner).get_spawnable_scene_count() == 3, "Spawner does not register the crusher")
	var world_spawn: Node2D = _arena.spawn_species("void_crusher", Vector2(200, 100), 0.0, 2.0, 1.5)
	_check(world_spawn is VoidCrusher and (world_spawn as VoidCrusher)._def["max_health"] == 160.0 and float((world_spawn as VoidCrusher)._def["slam"]["damage"]) == 27.0, "spawn_species does not build a scaled crusher")
	world_spawn.queue_free()
	# Directional armour: front a quarter, rear triple, only the rear breaks actions.
	_reset_actor(0.0)
	_actor._hurtbox.take_hit(10.0, Vector2(30, 0), 30.0)
	_check(is_equal_approx(_actor._health.current, 77.0) and _actor.state == VoidCrusher.State.IDLE, "Front hit was not reduced to 25 percent without flinch")
	_actor._hurtbox.take_hit(4.0, Vector2(-30, 0), 30.0)
	_check(is_equal_approx(_actor._health.current, 65.0) and _actor.state == VoidCrusher.State.HURT, "Rear hit was not tripled and did not stagger it")
	_reset_actor(PI / 2.0)
	_actor._set_state(VoidCrusher.State.SLAM_WINDUP)
	_actor._hurtbox.take_hit(6.0, Vector2(0, 30), 100.0)
	_check(_actor.state == VoidCrusher.State.SLAM_WINDUP, "A heavy frontal hit interrupted a committed slam")
	_actor._hurtbox.take_hit(6.0, Vector2(0, -30), 10.0)
	_check(_actor.state == VoidCrusher.State.HURT, "A rear hit did not break the slam windup")
	# Chase: it walks to a distant target at its slow pace and keeps its distance rules.
	_reset_actor(0.0)
	_actor.position = Vector2(-300, 150) ## the arena's origin has props of its own
	_reset_player(Vector2(100, 150))
	_actor.set_physics_process(true)
	_actor._rush_cd = 99.0
	_actor._known = _player.position
	_actor._memory = 8.0
	_actor._set_state(VoidCrusher.State.CHASE)
	for i: int in 120:
		_actor._memory = 8.0
		_actor._known = _player.position
		await get_tree().physics_frame
	_check(_actor.position.x > -260.0 and _actor.position.x < -200.0 and absf(_actor.position.y - 150.0) < 6.0, "The crusher did not walk toward a distant target at its pace: %s" % _actor.position)
	_actor.set_physics_process(false)
	# Slam: slow aim, lock before the strike, one hit inside the fan, none behind.
	_actor._health.current = 80.0
	_reset_actor(0.0)
	_reset_player(Vector2(30, 0))
	await get_tree().physics_frame
	_actor._known = _player.position
	_actor._memory = 8.0
	_actor._set_state(VoidCrusher.State.SLAM_WINDUP)
	_check(_actor.attack_dir.is_equal_approx(Vector2.RIGHT) and is_equal_approx(_actor.warning_length, 54.0), "Slam did not aim at its target")
	_actor._state_time = 0.2
	_actor._known = Vector2(0, 60)
	_actor._windup(0.1)
	_check(absf(angle_difference(_actor.attack_dir.angle(), 0.0)) < 0.3, "The crusher turned faster than its turn cap while aiming")
	_actor._state_time = 0.7
	var locked: Vector2 = _actor.attack_dir
	_actor._known = Vector2(-60, 0)
	_actor._windup(0.05)
	_check(_actor.attack_dir.is_equal_approx(locked), "Slam retargeted after its aim lock")
	_actor._set_state(VoidCrusher.State.SLAM)
	_actor.attack_dir = Vector2.RIGHT
	_actor._hit_fan(_actor._def["slam"], deg_to_rad(120.0), 54.0)
	_actor._hit_fan(_actor._def["slam"], deg_to_rad(120.0), 54.0)
	_check(_player.health.current == 982.0, "Slam missed or hit twice")
	_reset_player(Vector2(-30, 0))
	await get_tree().physics_frame
	_actor._struck.clear()
	_actor._hit_fan(_actor._def["slam"], deg_to_rad(120.0), 54.0)
	_check(_player.health.current == 1000.0, "Slam hit behind the announced fan")
	_reset_player(Vector2(30, 0))
	_actor._struck.clear()
	var blocker: StaticBody2D = _wall(Vector2(15, 0), Vector2(3, 50))
	await get_tree().physics_frame
	_actor._hit_fan(_actor._def["slam"], deg_to_rad(120.0), 54.0)
	_check(_player.health.current == 1000.0, "Slam hit through cover")
	blocker.queue_free()
	await get_tree().physics_frame
	# Rush: the lane is clipped by solid cover, the corridor hits once, a wall stuns for 1.4 s.
	_reset_actor(0.0)
	_actor.set_physics_process(true)
	_reset_player(Vector2(30, 0))
	_actor._known = Vector2(100, 0)
	_actor._memory = 8.0
	_actor._set_state(VoidCrusher.State.RUSH_WINDUP)
	_check(is_equal_approx(_actor.warning_length, 64.0), "Open ground clipped the rush lane")
	_actor._set_state(VoidCrusher.State.RUSH)
	for i: int in 40:
		await get_tree().physics_frame
	_check(_player.health.current == 984.0, "Rush corridor missed the target or hit repeatedly: %s" % _player.health.current)
	_reset_actor(0.0)
	_reset_player(Vector2(500, 500))
	_actor.set_physics_process(true)
	_actor._known = Vector2(100, 0)
	_actor._memory = 8.0
	_actor._set_state(VoidCrusher.State.RUSH_WINDUP)
	_actor._set_state(VoidCrusher.State.RUSH)
	for i: int in 40:
		await get_tree().physics_frame
	_check(_actor.state == VoidCrusher.State.RUSH_RECOVER and _actor.position.x > 58.0 and _actor.position.x < 72.0, "Rush did not run its 64 px and recover: %s %s" % [_actor.state, _actor.position])
	_reset_actor(0.0)
	_reset_player(Vector2(500, 500))
	_actor.set_physics_process(true)
	var tree_rock: StaticBody2D = _wall(Vector2(50, 0), Vector2(8, 40))
	await get_tree().physics_frame
	_actor._known = Vector2(120, 0)
	_actor._memory = 8.0
	_actor._set_state(VoidCrusher.State.RUSH_WINDUP)
	_check(_actor.warning_length < 64.0 and _actor.warning_length > 10.0, "The warning lane ignored a rock in the way")
	_actor._set_state(VoidCrusher.State.RUSH)
	for i: int in 40:
		await get_tree().physics_frame
	_check(_actor.state == VoidCrusher.State.STUN, "Ramming a rock did not stun the crusher")
	_check(is_equal_approx(_actor._duration_of(VoidCrusher.State.STUN), 1.4), "Stun is not 1.4 seconds")
	tree_rock.queue_free()
	_actor.set_physics_process(false)
	# Sweep: loitering behind it for 1.2 s triggers the back-hand, which hits the flank/back and not the front.
	_reset_actor(0.0)
	_reset_player(Vector2(-30, 0))
	_actor.set_physics_process(false)
	await get_tree().physics_frame
	for i: int in 3:
		_actor._track_behind(0.5)
	_check(_actor.state == VoidCrusher.State.SWEEP_WINDUP and _actor.attack_dir.x < -0.9, "Lingering behind it did not trigger the sweep")
	_actor._set_state(VoidCrusher.State.SWEEP)
	_actor._hit_fan(_actor._def["sweep"], deg_to_rad(210.0), 40.0)
	_check(_player.health.current == 989.0, "Sweep missed a target behind it")
	_reset_player(Vector2(30, 0))
	await get_tree().physics_frame
	_actor._struck.clear()
	_actor._hit_fan(_actor._def["sweep"], deg_to_rad(210.0), 40.0)
	_check(_player.health.current == 1000.0, "Sweep hit in front of the crusher")
	# Rig: arm up in the windup, fist in the ground after the slam, core only from behind, the arm breaks off in death.
	var rig: CrusherRig = _actor._rig
	rig.update_rig(0.0, Vector2.ZERO, 0.0, 0.0)
	rig.start_pose(CrusherRig.Pose.SLAM_WINDUP, 0.95)
	for i: int in 70:
		rig.update_rig(0.0136, Vector2.ZERO, 0.0, 0.0)
	_check(rig._fist.z > 55.0, "The club arm did not rise above the head in the slam windup")
	rig.start_pose(CrusherRig.Pose.SLAM, 0.18)
	rig.update_rig(0.17, Vector2.ZERO, 0.0, 0.0)
	_check(rig._fist.z < 4.0 and rig._fist.x > 25.0, "The fist did not reach the ground in front of it in the strike")
	rig.start_pose(CrusherRig.Pose.SLAM_RECOVER, 0.95)
	rig.update_rig(0.3, Vector2.ZERO, 0.0, 0.0)
	_check(rig._fist.z < 3.0, "The fist is not stuck in the ground during recovery")
	rig.update_rig(0.0, Vector2.ZERO, -PI / 2.0, 0.0)
	_check(rig._back_visibility() > 0.9, "The core is hidden from behind")
	rig.update_rig(0.0, Vector2.ZERO, PI / 2.0, 0.0)
	_check(rig._back_visibility() < 0.05, "The core shines through the front")
	rig.start_pose(CrusherRig.Pose.DEAD, 1.5)
	for i: int in 120:
		rig.update_rig(0.0125, Vector2.ZERO, 0.0, 0.0)
	_check(rig._arm_broken and rig._debris.size() == 6 and rig._alpha < 0.2, "Death did not break the club arm into debris and fade the body")
	# Stage and loot: the rare drop exists, night/mine know the species, death frees the hurtbox.
	var items: Dictionary = DataRegistry.table("items")
	for entry: Dictionary in spec["loot"]["items"]:
		_check(items.has(String(entry["id"])), "Loot names an unknown item %s" % entry["id"])
	var night_ids: Array[String] = []
	for entry: Dictionary in NightRules.config().species:
		night_ids.append(String(entry.id))
	_check(night_ids.has("void_crusher") and NightRules.cost_of("void_crusher") == 3.0, "The night does not know the crusher")
	_check(float(DataRegistry.table("mine")["enemies"]["costs"]["void_crusher"]) > 0.0, "The mine does not know the crusher")
	_reset_actor(0.0)
	_actor.night = NightBehavior.new()
	_actor.night.goal = Vector2(200, 0)
	_actor._idle(0.1)
	_check(_actor.velocity.x > 0.0 and _actor.velocity.x <= float(spec["wander_speed"]) * 3.0, "A creature of the night did not walk its patrol goal")
	_actor._health.take_damage(1000.0, Vector2(-30, 0), 50.0)
	await get_tree().physics_frame
	_check(_actor.state == VoidCrusher.State.DEAD and _actor._hurtbox.collision_layer == 0, "Death did not leave a dead, unhittable body")
	print("Crusher tests: ", _checks - _failed, "/", _checks, " passed")
	get_tree().quit(1 if _failed > 0 else 0)
