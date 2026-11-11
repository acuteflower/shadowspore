class_name VoidCrusher
extends CharacterBody2D
## Host-owned juggernaut. It is slow to turn and nearly immune from the front (horn collar), but its back is open: a hit there deals triple damage and breaks any action.
## Three attacks, each telegraphed on the ground and locked before the hit: a cleaving slam (the club arm sticks in the ground afterwards), a straight bull rush
## (stuns it against rocks, trees and walls) and a back-hand sweep against anyone who lingers behind it. Same replication and fairness rules as the listener.

enum State { IDLE, NOTICE, CHASE, SEARCH, SLAM_WINDUP, SLAM, SLAM_RECOVER, RUSH_WINDUP, RUSH, RUSH_RECOVER, SWEEP_WINDUP, SWEEP, SWEEP_RECOVER, STUN, HURT, DEAD }
const HURTBOX_MASK: int = 1 << 5
const DEATH_SECONDS: float = 1.5
const ZONE_PAD: float = 4.0
const BODY_RADIUS: float = 9.0
const CHEST: Vector2 = Vector2(0, -12)

var enemy_id: String = "void_crusher"
var health_scale: float = 1.0 ## see ShadowSpider
var damage_scale: float = 1.0
var emerge_on_spawn: bool = false ## the night: it rises out of a crack
var night: NightBehavior = null ## see ShadowSpider
var heading: float = PI / 2.0
var state: State = State.IDLE
var attack_dir: Vector2 = Vector2.DOWN
var attack_origin: Vector2
var warning_length: float = 0.0
var _def: Dictionary
var _target: Player
var _known: Vector2
var _memory: float = 0.0
var _positions: Dictionary = {}
var _state_time: float = 0.0
var _previous: State = State.IDLE
var _sense_left: float = 0.0
var _slam_cd: float = 0.8
var _rush_cd: float = 2.0
var _sweep_cd: float = 0.0
var _flinch_cd: float = 0.0
var _behind_time: float = 0.0
var _aim_left: float = 0.0
var _aim_locked: bool = false
var _fired: bool = false
var _presented: bool = false
var _struck: Array[int] = []
var _travelled: float = 0.0
var _last_position: Vector2
var _spin: float = 1.0
var _step_sound_at: int = 0
var _wander_left: float = 1.5
var _wander_dir: Vector2 = Vector2.ZERO
var _orbit: float = 1.0
var _world: Node
var _step_stream: AudioStream
var _base_amounts: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _rig: CrusherRig = $Rig
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _body: CollisionShape2D = $CollisionShape2D
@onready var _navigation: EnemyNavigation = $Navigation
@onready var _zone: Node2D = $Zone
@onready var _fx: Node2D = $Fx
@onready var _trail: ShadowTrailComponent = $ShadowTrail
@onready var _voice: AudioStreamPlayer2D = $Voice
@onready var _impact: AudioStreamPlayer2D = $Impact
@onready var _steps: AudioStreamPlayer2D = $Steps
@onready var _death_fx: CPUParticles2D = $DeathFx
@onready var _chips: CPUParticles2D = $Chips
@onready var _step_chips: CPUParticles2D = $StepChips
@onready var _hit_fx: CPUParticles2D = $HitFx


func _ready() -> void:
	add_to_group("predators")
	_def = EnemyScaling.scaled(DataRegistry.get_entry("enemies", enemy_id), health_scale, damage_scale)
	_health.max_health = float(_def["max_health"])
	_health.current = _health.max_health
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_rng.seed = hash(name)
	_orbit = -1.0 if hash(name) % 2 == 0 else 1.0
	_known = global_position
	_last_position = global_position
	for world: Node in get_tree().get_nodes_in_group("world"):
		if world.has_method("navigation_floor") or world.has_method("spawn_resonance"):
			_world = world
			break
	_navigation.configure(self, _body, _def["navigation"], _floor_available)
	_zone.draw.connect(_draw_zone)
	if Interiors.slot_at(global_position) >= 0 or MineManager.in_mine(global_position):
		_zone.z_index = -3 ## the ground of rooms and of the mine is painted at z -6: the attack warning must lie above it
	_fx.draw.connect(_draw_fx)
	for emitter: CPUParticles2D in [_chips, _step_chips, _hit_fx]:
		_base_amounts[emitter] = emitter.amount
	_rig.slam_hit_frac = float(_def["slam"]["hit_time"]) / float(_def["slam"]["strike"])
	_rig.foot_landed.connect(_on_foot_landed)
	_enter_state()
	if emerge_on_spawn: ## the night: it rises out of the crack, a dark birth mark stays on the ground
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 1.4)
		_trail.infest(global_position)
		_slam_cd = 1.6
		_rush_cd = 3.0
		_sense_left = 1.4
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


func _process(delta: float) -> void:
	var attack_pose: bool = state in [State.SLAM_WINDUP, State.SLAM, State.SLAM_RECOVER, State.RUSH_WINDUP, State.RUSH, State.RUSH_RECOVER, State.SWEEP_WINDUP, State.SWEEP, State.SWEEP_RECOVER]
	_rig.update_rig(delta, velocity, heading, attack_dir.angle() if attack_pose else heading)
	_zone.queue_redraw()
	_fx.queue_redraw()
	if state == State.SLAM and not _presented and _state_time >= float(_def["slam"]["hit_time"]):
		_presented = true
		_present_slam()


func _physics_process(delta: float) -> void:
	_state_time += delta
	if not multiplayer.is_server() or state == State.DEAD:
		return
	_slam_cd = maxf(0.0, _slam_cd - delta)
	_rush_cd = maxf(0.0, _rush_cd - delta)
	_sweep_cd = maxf(0.0, _sweep_cd - delta)
	_flinch_cd = maxf(0.0, _flinch_cd - delta)
	_memory = maxf(0.0, _memory - delta)
	_sense_left -= delta
	if _sense_left <= 0.0:
		_sense_left = float(_def["sense_interval"])
		_sense()
	_track_behind(delta)
	match state:
		State.IDLE:
			_idle(delta)
		State.NOTICE:
			velocity = Vector2.ZERO
			_turn_toward((_known - global_position).angle(), delta)
			if _state_time >= float(_def["notice_seconds"]):
				_set_state(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.SEARCH:
			velocity = Vector2.ZERO
			heading += sin(_state_time * 1.6) * delta * 0.9
			if _memory > 0.0:
				_set_state(State.CHASE)
			elif _state_time >= float(_def["search_seconds"]):
				_target = null
				_set_state(State.IDLE)
		State.SLAM_WINDUP, State.RUSH_WINDUP, State.SWEEP_WINDUP:
			_windup(delta)
		State.SLAM:
			velocity = Vector2.ZERO
			if not _fired and _state_time >= float(_def["slam"]["hit_time"]):
				_fired = true
				_hit_fan(_def["slam"], deg_to_rad(float(_def["slam"]["arc"])), float(_def["slam"]["reach"]))
			if _state_time >= float(_def["slam"]["strike"]):
				_set_state(State.SLAM_RECOVER)
		State.SWEEP:
			velocity = Vector2.ZERO
			heading = lerp_angle(heading, attack_dir.angle(), 1.0 - exp(-18.0 * delta))
			if not _fired and _state_time >= float(_def["sweep"]["hit_time"]):
				_fired = true
				_hit_fan(_def["sweep"], deg_to_rad(float(_def["sweep"]["arc"])), float(_def["sweep"]["reach"]))
			if _state_time >= float(_def["sweep"]["strike"]):
				heading = attack_dir.angle()
				_set_state(State.SWEEP_RECOVER)
		State.RUSH:
			_rush(delta)
		State.SLAM_RECOVER, State.RUSH_RECOVER, State.SWEEP_RECOVER, State.STUN:
			velocity = Vector2.ZERO
			if _state_time >= _duration_of(state):
				_set_state(State.CHASE if _memory > 0.0 else State.SEARCH)
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, delta * 500.0)
			if _state_time >= float(_def["hurt_stun"]):
				_set_state(State.CHASE if _memory > 0.0 else State.SEARCH)
	if night != null:
		velocity = night.limit(self, velocity, delta)
	move_and_slide()
	if state == State.RUSH:
		_rush_after_move()


func _duration_of(s: State) -> float:
	match s:
		State.SLAM_RECOVER:
			return float(_def["slam"]["recover"])
		State.RUSH_RECOVER:
			return float(_def["rush"]["recover"])
		State.SWEEP_RECOVER:
			return float(_def["sweep"]["recover"])
		State.STUN:
			return float(_def["rush"]["stun"])
	return 1.0


func damage_factor(from: Vector2) -> float:
	if state == State.DEAD:
		return 1.0
	return float(_def["rear_damage"]) if is_rear_hit(from) else float(_def["front_damage"])


## True when the attacker stands in the half-plane behind the crusher.
func is_rear_hit(from: Vector2) -> bool:
	return Vector2.from_angle(heading).dot((from - global_position).normalized()) < 0.0


func _floor_available(point: Vector2) -> bool:
	if is_instance_valid(_world) and _world.has_method("navigation_floor"):
		return bool(_world.call("navigation_floor", point))
	return Terrain.relief == null or Terrain.relief.is_land(floori(point.x / 16.0), floori(point.y / 16.0))


func _same_floor(from: Vector2, to: Vector2) -> bool:
	return Terrain.relief == null or absf(Terrain.relief.level_at(from) - Terrain.relief.level_at(to)) < 0.45


func _line_clear(from: Vector2, to: Vector2) -> bool:
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from + Vector2(0, -4), to + Vector2(0, -4), 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _turn_toward(angle: float, delta: float) -> void:
	var diff: float = angle_difference(heading, angle)
	heading += clampf(diff * float(_def["turn_speed"]), -float(_def["max_turn"]), float(_def["max_turn"])) * delta


## Hearing is coarse (it is a brute), sight is frontal; remembered evidence, never a hidden player's live coordinates.
func _sense() -> void:
	var best: Player
	var evidence: float = -INF
	if is_instance_valid(_target) and _target.veiled(): ## Nebelschleier: it loses her, goes to where it last saw her and searches there
		_memory = minf(_memory, 1.6)
	for player: Player in Player.all:
		if player.health.current <= 0.0 or player.veiled():
			continue
		var point: Vector2 = player.global_position
		var moved: bool = point.distance_to(_positions.get(player.get_instance_id(), point)) > 0.75 or player.velocity.length() > 8.0
		_positions[player.get_instance_id()] = point
		var hear: float = player.stealth.alarm_scale() if player != _target else 1.0 ## talismans (Schweigtropfen): she is noticed only from a shorter distance, until she is chased
		var radius: float = float(_def["personal_range"])
		if moved:
			radius = float(_def["hearing_sneak"] if player.stealth.sneaking else (_def["hearing_sprint"] if player.sprinting else _def["hearing_walk"])) * hear
		if player.attack.is_swinging():
			radius = maxf(radius, float(_def["hearing_attack"]) * player.attack.noise_scale() * hear)
		var distance: float = global_position.distance_to(point)
		var clear: bool = _line_clear(global_position, point)
		if not clear:
			radius *= float(_def["sound_occlusion"])
		var forward: bool = Vector2.from_angle(heading).dot((point - global_position).normalized()) > (0.0 if player == _target else 0.3)
		var visible: bool = clear and forward and distance < float(_def["sight_range"]) * (player.stealth.detection_multiplier() * hear if player != _target else 1.0)
		if distance > radius and not visible:
			continue
		var strength: float = maxf(radius - distance, float(_def["sight_range"]) - distance if visible else -INF)
		if player == _target:
			strength += 18.0
		if strength > evidence:
			evidence = strength
			best = player
	if best != null:
		_target = best
		_known = best.global_position
		_memory = float(_def["memory_seconds"])
		if state in [State.IDLE, State.SEARCH]:
			_set_state(State.NOTICE)


## Anyone who lingers behind it gets the back-hand sweep: the crusher cannot turn fast, so it swats the flank instead.
func _track_behind(delta: float) -> void:
	var spec: Dictionary = _def["sweep"]
	var best: Player
	for player: Player in Player.all:
		if player.health.current <= 0.0 or player.veiled():
			continue
		var offset: Vector2 = player.global_position - global_position
		if offset.length() < float(spec["behind_range"]) and Vector2.from_angle(heading).dot(offset.normalized()) < -0.2 and _same_floor(global_position, player.global_position) and _line_clear(global_position, player.global_position):
			best = player
			break
	if best == null:
		_behind_time = maxf(0.0, _behind_time - delta * 2.0)
		return
	_behind_time += delta
	if _behind_time >= float(spec["behind_seconds"]) and _sweep_cd <= 0.0 and state in [State.IDLE, State.NOTICE, State.CHASE, State.SEARCH]:
		_target = best
		_known = best.global_position
		_memory = float(_def["memory_seconds"])
		_behind_time = 0.0
		_set_state(State.SWEEP_WINDUP)


func _idle(delta: float) -> void:
	if night != null and night.goal.is_finite(): ## a creature of the night walks its patrol goal
		var way: Vector2 = _safe_direction(night.walk_dir(self, _navigation, delta))
		velocity = velocity.move_toward(way * float(_def["wander_speed"]) * night.speed_factor(), delta * 80.0)
		if way != Vector2.ZERO:
			_turn_toward(way.angle(), delta)
		return
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = _rng.randf_range(2.4, 4.2)
		_wander_dir = Vector2.ZERO if _wander_dir != Vector2.ZERO else Vector2.from_angle(heading + _rng.randf_range(-1.2, 1.2))
	var dir: Vector2 = _safe_direction(_wander_dir)
	velocity = velocity.move_toward(dir * float(_def["wander_speed"]), delta * 60.0)
	if dir != Vector2.ZERO:
		_turn_toward(dir.angle(), delta)


func _safe_direction(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return direction
	for turn: float in [0.0, 0.5 * _orbit, -0.5 * _orbit, 1.0 * _orbit, -1.0 * _orbit, 1.55 * _orbit]:
		var dir: Vector2 = direction.rotated(turn)
		if _navigation.segment_clear(global_position, global_position + dir * 24.0) and not test_move(global_transform, dir * 18.0):
			return dir
	return Vector2.ZERO


func _chase(delta: float) -> void:
	if _memory <= 0.0 or (is_instance_valid(_target) and _target.health.current <= 0.0):
		_set_state(State.SEARCH)
		return
	var toward: Vector2 = _known - global_position
	var distance: float = toward.length()
	var clear: bool = _same_floor(global_position, _known) and _line_clear(global_position, _known)
	var off: float = absf(angle_difference(heading, toward.angle()))
	var slam: Dictionary = _def["slam"]
	var rush: Dictionary = _def["rush"]
	if clear and distance <= float(slam["trigger_range"]) and _slam_cd <= 0.0 and off < 0.6:
		_set_state(State.SLAM_WINDUP)
		return
	if clear and distance >= float(rush["min_range"]) and distance <= float(rush["max_range"]) and _rush_cd <= 0.0 and off < 0.25:
		_set_state(State.RUSH_WINDUP)
		return
	var dir: Vector2 = toward.normalized()
	if not clear or not _navigation.segment_clear(global_position, _known):
		dir = _navigation.direction_to(_known, delta)
	else:
		_navigation.invalidate()
		dir = _safe_direction(dir)
	var want: float = toward.angle() if (clear and distance < 90.0) or dir == Vector2.ZERO else dir.angle()
	_turn_toward(want, delta)
	var aligned: float = clampf(1.0 - absf(angle_difference(heading, want)) / 1.2, 0.15, 1.0)
	var speed: float = float(_def["chase_speed"]) * aligned if distance > float(_def["stop_distance"]) and dir != Vector2.ZERO else 0.0
	velocity = velocity.move_toward(Vector2.from_angle(heading) * speed, delta * 160.0)


func _spec_for(s: State) -> Dictionary:
	if s in [State.SLAM_WINDUP, State.SLAM]:
		return _def["slam"]
	if s in [State.RUSH_WINDUP, State.RUSH]:
		return _def["rush"]
	return _def["sweep"]


func _windup(delta: float) -> void:
	velocity = Vector2.ZERO
	var spec: Dictionary = _spec_for(state)
	var sweep: bool = state == State.SWEEP_WINDUP
	_aim_left -= delta
	if _state_time < float(spec["windup"]) - float(spec["aim_lock"]):
		if _memory > 0.0 and _known.distance_squared_to(attack_origin) > 0.01:
			var desired: float = (_known - attack_origin).angle()
			var diff: float = angle_difference(attack_dir.angle(), desired)
			attack_dir = attack_dir.rotated(clampf(diff * float(_def["turn_speed"]), -float(_def["max_turn"]), float(_def["max_turn"])) * delta)
		if _aim_left <= 0.0:
			_aim_left = 0.05
			if state == State.RUSH_WINDUP:
				warning_length = _lane_length()
			_update_aim.rpc(attack_dir, warning_length)
	elif not _aim_locked:
		_aim_locked = true
		_update_aim.rpc(attack_dir, warning_length)
	if sweep:
		heading -= _spin * 0.6 * delta ## it winds up against the direction of the swing
	else:
		heading = attack_dir.angle()
	if _state_time >= float(spec["windup"]):
		match state:
			State.SLAM_WINDUP:
				_set_state(State.SLAM)
			State.RUSH_WINDUP:
				_set_state(State.RUSH)
			_:
				_set_state(State.SWEEP)


@rpc("authority", "call_remote", "reliable")
func _update_aim(dir: Vector2, length: float) -> void:
	if state in [State.SLAM_WINDUP, State.RUSH_WINDUP, State.SWEEP_WINDUP]:
		attack_dir = dir
		warning_length = length


func _lane_length() -> float:
	var spec: Dictionary = _def["rush"]
	return minf(float(spec["distance"]), ResonanceWave.clip_distance(self, attack_origin, attack_dir, float(spec["distance"]), BODY_RADIUS))


func _rush(delta: float) -> void:
	var spec: Dictionary = _def["rush"]
	velocity = attack_dir * float(spec["speed"])
	heading = attack_dir.angle()
	var circle: Vector2 = global_position + CHEST + attack_dir * 12.0
	for target: HurtboxComponent in HitScan.circle(self, circle, float(spec["width"]) * 0.5, HURTBOX_MASK):
		if not _struck.has(target.get_instance_id()) and _same_floor(global_position, target.global_position):
			_struck.append(target.get_instance_id())
			target.take_hit(float(spec["damage"]), global_position + CHEST, float(spec["knockback"]))
	if _travelled >= warning_length - 0.5 and warning_length < float(spec["distance"]) - 1.0:
		_hit_wall()
	elif _travelled >= float(spec["distance"]) or _state_time >= float(spec["max_time"]):
		_set_state(State.RUSH_RECOVER)


func _rush_after_move() -> void:
	_travelled += global_position.distance_to(_last_position)
	_last_position = global_position
	if state != State.RUSH:
		return
	for i: int in get_slide_collision_count():
		var hit: KinematicCollision2D = get_slide_collision(i)
		var collider: CollisionObject2D = hit.get_collider() as CollisionObject2D
		if collider != null and collider.collision_layer & 1 != 0 and hit.get_normal().dot(attack_dir) < -0.5:
			_hit_wall()
			return


## Rocks, trunks and walls stop the rush dead: the crusher is dazed with its collar down.
func _hit_wall() -> void:
	velocity = Vector2.ZERO
	_set_state(State.STUN)


## A fan wider than half a circle would be concave (a convex query shape cannot hold it), so the sweep is two overlapping halves; `_struck` keeps it to one hit each.
func _hit_fan(spec: Dictionary, arc: float, reach: float) -> void:
	var origin: Vector2 = global_position + CHEST
	var fans: Array[Array] = [[attack_dir, arc]]
	if arc > PI * 0.95:
		fans = [[attack_dir.rotated(-arc * 0.25), arc * 0.5], [attack_dir.rotated(arc * 0.25), arc * 0.5]]
	for fan: Array in fans:
		for target: HurtboxComponent in HitScan.fan(self, origin, fan[0] as Vector2, reach, float(fan[1]), HURTBOX_MASK):
			if not _struck.has(target.get_instance_id()) and _same_floor(global_position, target.global_position) and _line_clear(global_position, target.global_position):
				_struck.append(target.get_instance_id())
				target.take_hit(float(spec["damage"]), origin, float(spec["knockback"]))


func _set_state(next: State) -> void:
	if next in [State.SLAM_WINDUP, State.RUSH_WINDUP, State.SWEEP_WINDUP]:
		attack_origin = global_position
		attack_dir = (_known - global_position).normalized()
		if attack_dir == Vector2.ZERO:
			attack_dir = Vector2.from_angle(heading)
		match next:
			State.SLAM_WINDUP:
				_slam_cd = float(_def["slam"]["cooldown"])
				warning_length = float(_def["slam"]["reach"])
			State.RUSH_WINDUP:
				_rush_cd = float(_def["rush"]["cooldown"])
				warning_length = _lane_length()
			_:
				_sweep_cd = float(_def["sweep"]["cooldown"])
				warning_length = float(_def["sweep"]["reach"])
	if next == State.RUSH:
		_travelled = 0.0
		_last_position = global_position
	if next not in [State.CHASE, State.IDLE, State.HURT, State.RUSH]:
		velocity = Vector2.ZERO
	if next in [State.NOTICE, State.SEARCH, State.IDLE, State.DEAD]:
		_navigation.invalidate()
	_apply_state.rpc(next, attack_dir, attack_origin, warning_length, 0.0, state)


@rpc("authority", "call_local", "reliable")
func _apply_state(next: int, direction: Vector2, origin: Vector2, length: float, elapsed: float, previous: int) -> void:
	_previous = previous as State
	state = next as State
	attack_dir = direction
	attack_origin = origin
	warning_length = length
	_state_time = elapsed
	_aim_left = 0.0
	_aim_locked = false
	_fired = false
	_presented = false
	_struck.clear()
	_enter_state()


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server():
		_apply_state.rpc_id(multiplayer.get_remote_sender_id(), state, attack_dir, attack_origin, warning_length, _state_time, _previous)


func _enter_state() -> void:
	var pose: CrusherRig.Pose = CrusherRig.Pose.IDLE
	var duration: float = 1.0
	var cue: String = ""
	match state:
		State.NOTICE:
			pose = CrusherRig.Pose.NOTICE
			duration = float(_def["notice_seconds"])
			cue = "notice"
		State.CHASE:
			pose = CrusherRig.Pose.MOVE
		State.SLAM_WINDUP:
			pose = CrusherRig.Pose.SLAM_WINDUP
			duration = float(_def["slam"]["windup"])
			cue = "charge"
		State.SLAM:
			pose = CrusherRig.Pose.SLAM
			duration = float(_def["slam"]["strike"])
			cue = "slam"
		State.SLAM_RECOVER:
			pose = CrusherRig.Pose.SLAM_RECOVER
			duration = float(_def["slam"]["recover"])
		State.RUSH_WINDUP:
			pose = CrusherRig.Pose.RUSH_WINDUP
			duration = float(_def["rush"]["windup"])
			cue = "charge"
		State.RUSH:
			pose = CrusherRig.Pose.RUSH
			duration = float(_def["rush"]["max_time"])
			cue = "rush"
		State.RUSH_RECOVER:
			pose = CrusherRig.Pose.RUSH_RECOVER
			duration = float(_def["rush"]["recover"])
		State.SWEEP_WINDUP:
			pose = CrusherRig.Pose.SWEEP_WINDUP
			duration = float(_def["sweep"]["windup"])
			cue = "charge"
			_spin = 1.0 if angle_difference(heading, attack_dir.angle()) >= 0.0 else -1.0
		State.SWEEP:
			pose = CrusherRig.Pose.SWEEP
			duration = float(_def["sweep"]["strike"])
			cue = "sweep"
		State.SWEEP_RECOVER:
			pose = CrusherRig.Pose.SWEEP_RECOVER
			duration = float(_def["sweep"]["recover"])
		State.STUN:
			pose = CrusherRig.Pose.STUN
			duration = float(_def["rush"]["stun"])
			cue = "stun"
			_present_wall()
		State.HURT:
			pose = CrusherRig.Pose.HURT
			duration = float(_def["hurt_stun"])
		State.DEAD:
			pose = CrusherRig.Pose.DEAD
			duration = DEATH_SECONDS
			cue = "death"
	_rig.start_pose(pose, duration, _state_time)
	_play(_voice, cue, _state_time)
	if state == State.HURT:
		_voice.stop()


## Dedicated/headless peers replicate cues but have no spatial listener to play them to; avoid unmanaged dummy-driver playbacks there.
func _play(player: AudioStreamPlayer2D, cue: String, from: float = 0.0, pitch: float = 1.0) -> void:
	if cue.is_empty() or DisplayServer.get_name() == "headless":
		return
	player.stop()
	player.stream = load(String(_def["audio"][cue])) as AudioStream
	player.volume_db = float(_def["audio"]["volume_db"])
	player.pitch_scale = pitch * (0.96 + float(posmod(hash(name), 9)) * 0.01)
	if from < player.stream.get_length():
		player.play(from)


func _shake_near(point: Vector2, amount: float) -> void:
	var radius: float = float(_def["shake_radius"])
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			player.add_shake(amount * (1.0 - smoothstep(30.0, radius, player.global_position.distance_to(point))))


func _burst(point: Vector2, emitter: CPUParticles2D, scale_by: float = 1.0) -> void:
	emitter.global_position = point
	emitter.amount = maxi(1, roundi(float(_base_amounts[emitter]) * clampf(scale_by, 0.2, 1.0)))
	emitter.restart()


## The club lands: stone shards, three shadow cracks in the ground and a tremor (the glowing cracks are the rig's).
func _present_slam() -> void:
	var impact: Vector2 = attack_origin + attack_dir * 34.0
	_shake_near(attack_origin, 3.0)
	_burst(impact + Vector2(0, -4), _chips)
	for i: int in int(_def["slam"]["cracks"]):
		var point: Vector2 = attack_origin + attack_dir.rotated((float(i) - 1.0) * 0.45) * (30.0 + float(i % 2) * 14.0)
		if _floor_available(point) and _same_floor(attack_origin, point) and _line_clear(attack_origin, point):
			_trail.leave(point, true)


func _present_wall() -> void:
	if _state_time > 0.3:
		return
	_shake_near(global_position, 2.4)
	_burst(global_position + attack_dir * 12.0 + Vector2(0, -14), _chips)
	_trail.leave(global_position + attack_dir * 14.0, true)


func _on_foot_landed(point: Vector2, heavy: bool) -> void:
	if state == State.DEAD:
		return
	_trail.leave(point, heavy)
	_burst(point, _step_chips, 1.0 if heavy else 0.5)
	if heavy and state in [State.CHASE, State.IDLE, State.NOTICE]:
		_shake_near(point, 0.5)
	var now: int = Time.get_ticks_msec()
	if now - _step_sound_at > 140 and DisplayServer.get_name() != "headless":
		_step_sound_at = now
		if _step_stream == null:
			_step_stream = load(String(_def["audio"]["step"])) as AudioStream
		_steps.stream = _step_stream
		_steps.volume_db = float(_def["audio"]["volume_db"]) - (0.0 if heavy else 7.0)
		_steps.pitch_scale = randf_range(0.88, 1.08)
		_steps.play()


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	var rear: bool = is_rear_hit(from)
	var away: Vector2 = (global_position - from).normalized()
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -66), amount, away)
	_hit_fx.global_position = global_position + Vector2(0, -26) - away * 15.0
	_hit_fx.direction = -away if not rear else Vector2.UP
	_hit_fx.modulate = Color.WHITE if rear else Color(0.7, 0.7, 0.9)
	_hit_fx.amount = roundi(float(_base_amounts[_hit_fx]) * (1.0 if rear else 0.6))
	_hit_fx.restart()
	if rear: ## the open core: white flash, the whole body jerks
		_rig.hit_flash()
		_play(_impact, "core_hit")
	else: ## the collar shrugs it off: a spark and the ring of steel, nothing moves
		_play(_impact, "front_hit", 0.0, randf_range(0.9, 1.15))
	if not multiplayer.is_server() or _health.current <= 0.0 or state in [State.DEAD, State.SLAM, State.SWEEP, State.STUN, State.HURT]:
		return
	for player: Player in Player.all:
		if player.name.to_int() == _health.last_attacker and not player.veiled():
			_target = player
			_known = player.global_position
			_memory = float(_def["memory_seconds"])
	if rear and _flinch_cd <= 0.0:
		_flinch_cd = float(_def["flinch_cooldown"]) + float(_def["hurt_stun"])
		velocity = away * knockback * (1.0 - float(_def["knockback_resistance"]))
		_set_state(State.HURT)


func _on_died() -> void:
	if multiplayer.is_server():
		_set_state(State.DEAD)
	_hurtbox.set_deferred("collision_layer", 0)
	_body.set_deferred("disabled", true)
	_death_fx.restart()
	await get_tree().create_timer(DEATH_SECONDS * 0.28).timeout
	if not is_inside_tree():
		return
	_burst(global_position + Vector2(10, -24), _chips) ## the club arm snaps off
	_shake_near(global_position, 1.6)
	await get_tree().create_timer(DEATH_SECONDS * 0.3).timeout
	if not is_inside_tree():
		return
	_trail.infest(global_position)
	_burst(global_position + Vector2(0, -8), _step_chips)
	if multiplayer.is_server():
		await get_tree().create_timer(DEATH_SECONDS * 0.42 + 0.25).timeout
		if is_inside_tree():
			queue_free()


func _exit_tree() -> void:
	for player: AudioStreamPlayer2D in [_voice, _impact, _steps]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


# --- warnings and effects ------------------------------------------------------------------------------------------


func _draw_zone() -> void:
	var winding: bool = state in [State.SLAM_WINDUP, State.RUSH_WINDUP, State.SWEEP_WINDUP]
	if not winding and state not in [State.SLAM, State.RUSH, State.SWEEP]:
		return
	var spec: Dictionary = _spec_for(state)
	var lane: bool = state in [State.RUSH_WINDUP, State.RUSH]
	var locked: bool = winding and _state_time >= float(spec["windup"]) - float(spec["aim_lock"])
	var strength: float = 0.75 + (0.2 * sin(_state_time * 38.0) if locked else 0.0)
	if not winding:
		strength = 1.0 - clampf(_state_time / float(spec["max_time"] if lane else spec["strike"]), 0.0, 1.0)
	var origin: Vector2 = attack_origin - global_position
	var across: Vector2 = attack_dir.orthogonal()
	var arc: float = deg_to_rad(float(spec["arc"])) if not lane else 0.0
	var width: float = (float(spec["width"]) + ZONE_PAD * 2.0) if lane else 0.0
	var length: float = (warning_length + float(spec["width"]) * 0.5 + 12.0 + ZONE_PAD) if lane else float(spec["reach"]) + ZONE_PAD
	# Stable sparse pixels flow outward like cracking lava; the area drawn is the area that hurts.
	for i: int in (420 if lane else 560):
		var u: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var v: float = fposmod(sin(float(i) * 78.233 + 3.1) * 19642.349, 1.0)
		var point: Vector2
		var distance: float
		if lane:
			distance = u * length
			point = attack_dir * distance + across * (v - 0.5) * width
		else:
			distance = sqrt(u) * length
			point = attack_dir.rotated((v - 0.5) * arc) * distance
		if distance < 5.0:
			continue
		var wave: float = 0.5 + 0.5 * sin(distance * 0.26 - _state_time * (18.0 if locked or not winding else 9.0) + v * TAU)
		if wave < 0.48:
			continue
		var color: Color = Color("c21f3b").lerp(Color("ffd0d6") if not winding else Color("ff4a63"), wave)
		_zone.draw_rect(Rect2((origin + point).round(), Vector2.ONE), Color(color, strength * (0.35 + wave * 0.45)))


func _draw_fx() -> void:
	if state == State.SWEEP or (state == State.SWEEP_RECOVER and _state_time < 0.25):
		var progress: float = clampf(_state_time / float(_def["sweep"]["strike"]), 0.0, 1.0) if state == State.SWEEP else 1.0
		var fade: float = 1.0 if state == State.SWEEP else 1.0 - _state_time / 0.25
		var aim: float = attack_dir.angle()
		var count: int = 34
		for i: int in count:
			var k: float = float(i) / float(count - 1)
			var angle: float = aim - _spin * (1.9 - 2.0 * progress * k)
			var radius: float = 36.0 + sin(k * 7.0) * 1.2
			var point: Vector2 = Vector2(cos(angle), sin(angle) * CrusherRig.SQUASH) * radius + Vector2(0, -12.0 + 4.0 * k)
			var alpha: float = k * k * fade
			_fx.draw_rect(Rect2(point.round() - Vector2.ONE, Vector2(3, 3)), Color(Color("8a4dff"), alpha * 0.2))
			_fx.draw_rect(Rect2(point.round(), Vector2.ONE * (2 if k > 0.7 else 1)), Color(Color("ecd2ff") if k > 0.8 else Color("b06bff"), alpha))
	if state == State.RUSH:
		var back: Vector2 = -attack_dir
		for i: int in 14:
			var u: float = fposmod(sin(float(i) * 4.37) * 9371.17, 1.0)
			var v: float = fposmod(sin(float(i) * 9.11 + 1.3) * 5113.91, 1.0)
			var point: Vector2 = back * (8.0 + fposmod(u * 60.0 + _state_time * 150.0, 46.0)) + attack_dir.orthogonal() * (v - 0.5) * 24.0 + Vector2(0, -6.0 - v * 22.0)
			_fx.draw_rect(Rect2(point.round(), Vector2(2, 1)), Color(Color("8a4dff"), 0.55 * (1.0 - u * 0.6)))
