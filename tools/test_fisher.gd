extends Node
## Offline regression of the Lichtfischer (docs/enemies/lichtfischer.md): data, F5 water-only spawn, staying in the water, senses, the three attacks, the weak point, dive, dawn.
## No save writes, no game socket. Run: Godot --headless --path . --fixed-fps 60 tools/test_fisher.tscn
const ARENA: PackedScene = preload("res://src/world/test_level.tscn")
const POND: float = 220.0 ## radius of the test pond in px; depth 1.0 at 110 px from the shore

class PondArena:
	extends TestLevel
	func _spawn_player(_id: int) -> void:
		pass
	func _fill_ground() -> void:
		pass
	func water_depth(point: Vector2) -> float:
		var distance: float = point.length()
		return -1.0 if distance > POND else (POND - distance) / 110.0

var _checks: int = 0
var _failed: int = 0
var _arena: TestLevel
var _actor: LightFisher
var _player: Player
var _def: Dictionary


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error(message)


func _reset_player(at: Vector2) -> void:
	_player.position = at
	_player.velocity = Vector2.ZERO
	_player.stealth.sneaking = false
	_player.sprinting = false
	_player.health.max_health = 1000.0
	_player.health.current = 1000.0
	_player.health.invulnerable_seconds = 0.0
	_player.health._invulnerable_until_msec = 0


func _step(frames: int, follow: bool = false) -> void:
	for i: int in frames:
		await get_tree().physics_frame
		_actor._physics_process(1.0 / 60.0)
		_actor._process(1.0 / 60.0)


func _run() -> void:
	Terrain.relief = null
	_def = DataRegistry.get_entry("enemies", "light_fisher")
	_arena = ARENA.instantiate() as TestLevel
	_arena.set_script(PondArena)
	add_child(_arena)
	_player = load("res://src/entities/player/player.tscn").instantiate() as Player
	_player.name = "2"
	_arena.get_node("Players").add_child(_player)
	_player.set_multiplayer_authority(1) ## the offline peer: `Player.launch` and friends ask the authority
	_player.set_physics_process(false)
	_reset_player(Vector2(300, 0))
	# --- data, keys, registration
	_check(float(_def["max_health"]) == 54.0 and not (_def["audio"] as Dictionary).is_empty(), "light_fisher data missing")
	var f4: InputEventKey = InputMap.action_get_events("debug_time")[0] as InputEventKey
	var f5: InputEventKey = InputMap.action_get_events("debug_spawn_fisher")[0] as InputEventKey
	_check(f5.physical_keycode == KEY_F5 and f4.physical_keycode == KEY_F4, "F5 fisher key missing or clashing with the clock")
	_check((_arena.get_node("EnemySpawner") as MultiplayerSpawner).get_spawnable_scene_count() == 4, "Enemy spawner does not register the fisher")
	var night_water: Dictionary = DataRegistry.table("night").get("water", {}) as Dictionary
	_check(String(night_water.get("id", "")) == "light_fisher" and float(night_water.get("cost", 0.0)) > 0.0, "night.json has no water block for the fisher")
	# --- water-only spawn
	var nothing: LightFisher = _arena._spawn_fisher(Vector2(600, 0))
	_check(nothing == null, "F5 spawned a fisher on dry land far from water")
	_actor = _arena._spawn_fisher(Vector2(POND + 30.0, 0.0))
	_check(_actor != null, "F5 next to the shore did not find the water")
	if _actor == null:
		get_tree().quit(1)
		return
	_actor.set_physics_process(false)
	_actor.set_process(false)
	await get_tree().physics_frame
	_check(_arena.water_depth(_actor.position) >= float(_def["min_depth"]), "Fisher was born outside deep enough water")
	_check(_actor._health.current == 54.0 and _actor._world == _arena, "Fisher did not load its definition/world")
	# --- the water confines it: pushed towards the shore it never leaves
	_actor.position = Vector2(POND - 40.0, 0.0)
	_actor._set_state(LightFisher.State.LURK)
	_actor._wander_dir = Vector2.RIGHT
	_actor._wander_left = 99.0
	var outside: int = 0
	for i: int in 240:
		_actor.heading = 0.0
		await _step(1)
		if _arena.water_depth(_actor.position) < float(_def["min_depth"]):
			outside += 1
	_check(outside == 0, "Fisher left the water while drifting towards the shore (%d frames)" % outside)
	# --- senses: a sneaking player on the shore is not heard, a sprinting one is
	_actor.position = Vector2(60, 0)
	_actor._set_state(LightFisher.State.LURK)
	_actor._target = null
	_actor._memory = 0.0
	_reset_player(Vector2(300, 0))
	_player.velocity = Vector2.RIGHT * 120
	_player.sprinting = true
	_actor._sense()
	_check(_actor._target == null, "Fisher heard a sprinting player 240 px away")
	_reset_player(Vector2(60 + 100, 0))
	_player.velocity = Vector2.RIGHT * 120
	_player.sprinting = true
	_actor._sense()
	_check(_actor._target == _player and _actor.state == LightFisher.State.NOTICE, "Fisher ignored a sprinting player at 100 px")
	_actor._target = null
	_actor._memory = 0.0
	_actor._set_state(LightFisher.State.LURK)
	_reset_player(Vector2(60 + 100, 0))
	_player.velocity = Vector2.RIGHT * 30
	_player.stealth.sneaking = true
	_actor._sense()
	_check(_actor._target == null, "Fisher noticed a sneaking player at 100 px")
	# --- the bite: windup lock, one hit, pull towards the water, gape is soft
	_actor.position = Vector2(0, 0)
	_actor.velocity = Vector2.ZERO
	_actor._health.current = 54.0
	_reset_player(Vector2(45, 0))
	await get_tree().physics_frame
	_actor._known = _player.position
	_actor._memory = 8.0
	_actor._snap_cd = 0.0
	_actor._set_state(LightFisher.State.SNAP_WINDUP)
	_actor._state_time = 0.45
	_actor._windup(0.01)
	var locked: Vector2 = _actor.attack_dir
	_actor._known = Vector2(0, 80)
	_actor._state_time = 0.66
	_actor._windup(0.01)
	_check(_actor.attack_dir.is_equal_approx(locked), "Bite retargeted after its aim lock")
	_actor._health.take_damage(3.0, _player.position, 30.0)
	_check(_actor.state == LightFisher.State.SNAP_WINDUP, "A light body hit cancelled a committed bite")
	_actor._set_state(LightFisher.State.SNAP)
	_actor._state_time = 0.05
	_actor._snap_hit()
	_check(_player.health.current == 1000.0, "Bite hit before its jaws closed")
	_actor._state_time = 0.14
	_actor._snap_hit()
	_actor._snap_hit()
	_check(_player.health.current == 980.0, "Bite missed or dealt repeated damage (%f)" % _player.health.current)
	_reset_player(Vector2(-45, 0))
	await get_tree().physics_frame
	_actor._set_state(LightFisher.State.SNAP_WINDUP)
	_actor.attack_dir = Vector2.RIGHT
	_actor._set_state(LightFisher.State.SNAP)
	_actor.attack_dir = Vector2.RIGHT
	_actor._state_time = 0.14
	_actor._snap_hit()
	_check(_player.health.current == 1000.0, "Bite hit behind the announced fan")
	# --- the weak point: lantern takes 150 %, the open maw only while gaping, a blow on the lantern breaks a casting
	_actor._health.current = 54.0
	_actor._set_state(LightFisher.State.STALK)
	_actor._flinch_cd = 5.0
	_actor._hurt_lure.take_hit(10.0, Vector2(80, 0), 10.0, 7)
	_check(is_equal_approx(_actor._health.current, 39.0), "Lantern hit did not take 150 %% (%f)" % _actor._health.current)
	await get_tree().physics_frame
	_actor._health.current = 54.0
	_actor._set_state(LightFisher.State.GAPE)
	await get_tree().physics_frame
	_actor._hurt_body.take_hit(10.0, Vector2(80, 0), 10.0, 7)
	_check(is_equal_approx(_actor._health.current, 38.0) and _actor.state == LightFisher.State.HURT, "A gaping maw is not soft and flinching (%f)" % _actor._health.current)
	await get_tree().physics_frame
	_actor._health.current = 54.0
	_actor._flinch_cd = 0.0
	_actor._set_state(LightFisher.State.FLASH_WINDUP)
	_actor._known = Vector2(60, 0)
	await get_tree().physics_frame
	_actor._health.take_damage(2.0, Vector2(80, 0), 10.0)
	_check(_actor.state == LightFisher.State.FLASH_WINDUP, "Body damage broke a casting that only the lantern may break")
	_actor._hurt_lure.take_hit(2.0, Vector2(80, 0), 10.0, 9)
	_check(_actor.state == LightFisher.State.HURT, "A blow on the lantern did not break the casting")
	# a wide sweep that touches both boxes in one frame counts once
	await get_tree().physics_frame
	_actor._health.current = 54.0
	_actor._set_state(LightFisher.State.GAPE)
	await get_tree().physics_frame
	_actor._hurt_lure.take_hit(10.0, Vector2(80, 0), 10.0, 11)
	var after_one: float = _actor._health.current
	_actor._hurt_body.take_hit(10.0, Vector2(80, 0), 10.0, 11)
	_check(is_equal_approx(_actor._health.current, after_one), "One sweep hurt the lantern and the maw twice")
	# --- the flash: a ring that hurts inside, not outside; the dazzle is local
	_actor.position = Vector2.ZERO
	_actor._health.current = 54.0
	_actor.lure_vec = Vector2(30, 0)
	_actor._set_state(LightFisher.State.FLASH_WINDUP)
	_actor._set_state(LightFisher.State.FLASH)
	var origin: Vector2 = _actor.attack_origin
	_reset_player(origin + Vector2(float(_def["flash"]["radius"]) * 0.5, 0))
	await get_tree().physics_frame
	_actor._flash_hit()
	_check(_player.health.current == 994.0, "Flash ring missed a player inside it (%f)" % _player.health.current)
	_reset_player(origin + Vector2(float(_def["flash"]["radius"]) + 40.0, 0))
	await get_tree().physics_frame
	_actor._flash_hit()
	_check(_player.health.current == 1000.0, "Flash ring hurt a player outside it")
	# --- the Irrlichter: three landing places, hits only where they land
	_actor._health.current = 54.0
	_actor._known = Vector2(110, 0)
	_actor._memory = 8.0
	_actor.lure_vec = Vector2(30, 0)
	_actor._set_state(LightFisher.State.ORB_CAST)
	_check(_actor.aim_points.size() == 3 and _actor._burst_done.size() == 3, "Orb volley does not aim three lights")
	_reset_player(_actor.aim_points[1])
	await get_tree().physics_frame
	_actor._state_time = _actor._orb_launch(1) + _actor._orb_fly(1) * 0.5
	_actor._orb_bursts()
	_check(_player.health.current == 1000.0, "An orb burst before it landed")
	_actor._state_time = _actor._orb_total()
	_actor._orb_bursts()
	_actor._orb_bursts()
	_check(_player.health.current == 992.0, "Orb burst missed or hit twice (%f)" % _player.health.current)
	var orb: Dictionary = _actor._orb_at(0, _actor._orb_launch(0) + _actor._orb_fly(0) * 0.5)
	_check(not orb.is_empty() and float(orb["height"]) > 0.0 and _actor._orb_at(0, 0.1).is_empty(), "Orb flight is not deterministic or comes too early")
	# --- the live state machine: a player stands on the shore, the fisher fights from the water and never leaves it
	_actor._health.current = 54.0
	_actor.position = Vector2(POND - 120.0, 0.0)
	_actor.velocity = Vector2.ZERO
	_actor._target = null
	_actor._memory = 0.0
	_actor._snap_cd = 0.0
	_actor._flash_cd = 0.0
	_actor._orb_cd = 0.0
	_actor._set_state(LightFisher.State.LURK)
	_reset_player(Vector2(POND + 30.0, 0.0))
	var visited: Dictionary = {}
	var out_frames: int = 0
	for frame: int in 900:
		_player.position = Vector2(POND + 30.0, 0.0) if frame % 300 < 180 else Vector2(POND - 20.0, 0.0)
		_player.velocity = Vector2.RIGHT * 100
		_player.sprinting = true
		_player.health.current = 1000.0
		await _step(1)
		visited[_actor.state] = true
		if _arena.water_depth(_actor.position) < float(_def["min_depth"]) and _actor.state != LightFisher.State.DIVE:
			out_frames += 1
	for expected: int in [LightFisher.State.NOTICE, LightFisher.State.STALK]:
		_check(visited.has(expected), "Live fisher fight never reached %s" % LightFisher.State.keys()[expected])
	_check(visited.has(LightFisher.State.SNAP_WINDUP) or visited.has(LightFisher.State.FLASH_WINDUP) or visited.has(LightFisher.State.ORB_CAST), "Live fisher never attacked")
	_check(out_frames == 0, "Live fisher left the water in %d frames" % out_frames)
	# --- the dive: it picks a place in the water and comes up there
	_actor._health.current = 54.0
	_actor.position = Vector2(0, 0)
	_actor._dive_cd = 0.0
	_actor._set_state(LightFisher.State.DIVE)
	var start: Vector2 = _actor.position
	_reset_player(Vector2(POND + 100.0, 0.0))
	await _step(300)
	_check(_actor.position.distance_to(start) > 40.0 and _arena.water_depth(_actor.position) >= float(_def["min_depth"]), "Dive did not move it to another place in the water")
	_check(_actor.state != LightFisher.State.DIVE, "Dive never ended")
	# --- the morning: it sinks without loot
	_actor.retire()
	_check(bool(_actor.get_meta("burned", false)) and _actor.state == LightFisher.State.DIVE, "Retire did not send it away without loot")
	await get_tree().create_timer(0.1).timeout
	# --- the rig draws all poses without errors and moves its hurtboxes with the picture
	var rig: FisherRig = _actor._rig
	for pose: int in FisherRig.Pose.size():
		rig.start_pose(pose as FisherRig.Pose, 0.5)
		rig.update_rig(0.25, Vector2(20, 0), 0.4, Vector2(26, 8), 1.0, 1.0, true)
	rig.start_pose(FisherRig.Pose.SNAP, 0.24)
	rig.update_rig(0.2, Vector2.ZERO, 0.0, Vector2(30, 0), 1.0, 1.0, true)
	var lure_open: Vector2 = rig.lure_local()
	rig.start_pose(FisherRig.Pose.DIVE, 0.6)
	rig.update_rig(0.5, Vector2.ZERO, 0.0, Vector2(30, 0), 1.0, 1.0, true)
	_check(rig.retract() > 0.3, "The stalk does not fold into the water when it dives")
	_check(lure_open.y < 0.0, "The lantern does not hang above the water")
	# --- the real kill: dies once, drops its infestation, is removed
	_actor.set_meta("burned", false)
	_actor._retired = false
	_actor._set_state(LightFisher.State.STALK)
	_player.remove_from_group("players")
	_actor._health.take_damage(500.0, Vector2(30, 0), 80.0)
	_check(_actor.state == LightFisher.State.DEAD, "Death failed to put the fisher into the dead state")
	print("Fisher: %d checks, %d failures" % [_checks, _failed])
	await get_tree().create_timer(2.0).timeout
	_arena.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failed == 0 else 1)
