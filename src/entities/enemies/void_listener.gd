class_name VoidListener
extends CharacterBody2D
## Host-owned auditory ranged hunter. Senses update remembered evidence, never a
## hidden player's live coordinates. Attacks commit to a direction before release.

enum State { LISTEN, NOTICE, HUNT, SEARCH, WAVE_WINDUP, WAVE_RELEASE, SCREAM_WINDUP, SCREAM, RECOVER, HURT, DEAD }
const HURTBOX_MASK: int = 1 << 5
const DEATH_SECONDS: float = 1.05
const ZONE_PAD: float = 4.0

var enemy_id: String = "void_listener"
var health_scale: float = 1.0 ## see ShadowSpider
var damage_scale: float = 1.0
var emerge_on_spawn: bool = false ## the night: it rises out of a crack (fades in, asleep for a moment)
var night: NightBehavior = null ## see ShadowSpider
var heading: float = PI / 2.0
var state: State = State.LISTEN
var attack_dir: Vector2 = Vector2.DOWN
var attack_origin: Vector2
var warning_length: float = 0.0
var _def: Dictionary
var _target: Player
var _known: Vector2
var _memory: float = 0.0
var _positions: Dictionary = {}
var _state_time: float = 0.0
var _previous: State = State.LISTEN
var _sense_left: float = 0.0
var _wave_cd: float = 0.6
var _scream_cd: float = 0.0
var _flinch_cd: float = 0.0
var _aim_left: float = 0.0
var _aim_locked: bool = false
var _fired: bool = false
var _scream_presented: bool = false
var _struck: Array[int] = []
var _wander_left: float = 1.5
var _wander_dir: Vector2 = Vector2.ZERO
var _orbit: float = 1.0
var _world: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _rig: ListenerRig = $Rig
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _body: CollisionShape2D = $CollisionShape2D
@onready var _navigation: EnemyNavigation = $Navigation
@onready var _zone: Node2D = $Zone
@onready var _trail: ShadowTrailComponent = $ShadowTrail
@onready var _voice: AudioStreamPlayer2D = $Voice
@onready var _death_fx: CPUParticles2D = $DeathFx
@onready var _scream_fx: Node2D = $ScreamFx
@onready var _pressure: ColorRect = $Pressure


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
	for world: Node in get_tree().get_nodes_in_group("world"):
		if world.has_method("navigation_floor") or world.has_method("spawn_resonance"):
			_world = world
			break
	_navigation.configure(self, _body, _def["navigation"], _floor_available)
	_zone.draw.connect(_draw_zone)
	if Interiors.slot_at(global_position) >= 0 or MineManager.in_mine(global_position):
		_zone.z_index = -3 ## the ground of rooms and of the mine is painted at z -6: the attack warning must lie above it
	_scream_fx.draw.connect(_draw_scream)
	_rig.foot_landed.connect(func(point: Vector2) -> void: _trail.leave(point))
	_enter_state()
	if emerge_on_spawn: ## the night: it rises out of the crack, a dark birth mark stays on the ground
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 1.4)
		_trail.infest(global_position)
		_wave_cd = 1.6
		_sense_left = 1.4
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


func _process(delta: float) -> void:
	var attack_pose: bool = state in [State.WAVE_WINDUP, State.WAVE_RELEASE, State.SCREAM_WINDUP, State.SCREAM, State.RECOVER]
	_rig.update_rig(delta, velocity, attack_dir.angle() if attack_pose else heading)
	var age: float = _scream_age()
	_pressure.visible = age >= 0.0 and age < 0.32
	if _pressure.visible:
		var material: ShaderMaterial = _pressure.material as ShaderMaterial
		material.set_shader_parameter("direction", attack_dir)
		material.set_shader_parameter("reach", float(_def["scream"]["reach"]))
		material.set_shader_parameter("half_arc", deg_to_rad(float(_def["scream"]["arc"])) * 0.5)
		material.set_shader_parameter("phase", age / float(_def["scream"]["hit_time"]))
		material.set_shader_parameter("world_to_uv", get_global_transform_with_canvas().get_scale() / get_viewport_rect().size)
	if state == State.SCREAM and not _scream_presented and _state_time >= float(_def["scream"]["hit_time"]) * 0.7:
		_scream_presented = true
		_present_scream()
	_zone.queue_redraw()
	_scream_fx.queue_redraw()


func _physics_process(delta: float) -> void:
	_state_time += delta
	if not multiplayer.is_server() or state == State.DEAD:
		return
	_wave_cd = maxf(0.0, _wave_cd - delta)
	_scream_cd = maxf(0.0, _scream_cd - delta)
	_flinch_cd = maxf(0.0, _flinch_cd - delta)
	_memory = maxf(0.0, _memory - delta)
	_sense_left -= delta
	if _sense_left <= 0.0:
		_sense_left = float(_def["sense_interval"])
		_sense()
	match state:
		State.LISTEN:
			_idle(delta)
		State.NOTICE:
			velocity = Vector2.ZERO
			heading = lerp_angle(heading, (_known - global_position).angle(), delta * float(_def["turn_speed"]))
			if _state_time >= float(_def["notice_seconds"]):
				_set_state(State.HUNT)
		State.HUNT:
			_hunt(delta)
		State.SEARCH:
			velocity = Vector2.ZERO
			heading += sin(_state_time * 2.0) * delta * 1.2
			if _memory > 0.0:
				_set_state(State.HUNT)
			elif _state_time >= float(_def["search_seconds"]):
				_target = null
				_set_state(State.LISTEN)
		State.WAVE_WINDUP, State.SCREAM_WINDUP:
			_windup(delta)
		State.WAVE_RELEASE:
			velocity = Vector2.ZERO
			if not _fired:
				_fired = true
				_launch_wave()
			if _state_time >= float(_def["wave"]["release"]):
				_set_state(State.RECOVER)
		State.SCREAM:
			velocity = Vector2.ZERO
			_scream_hit()
			if _state_time >= float(_def["scream"]["strike"]):
				_set_state(State.RECOVER)
		State.RECOVER:
			velocity = Vector2.ZERO
			if _state_time >= _recovery():
				_set_state(State.HUNT if _memory > 0.0 else State.SEARCH)
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, delta * 500.0)
			if _state_time >= float(_def["hurt_stun"]):
				_wave_cd = maxf(_wave_cd, 0.3)
				_set_state(State.HUNT if _memory > 0.0 else State.SEARCH)
	if night != null:
		velocity = night.limit(self, velocity, delta)
	move_and_slide()


func _floor_available(point: Vector2) -> bool:
	if is_instance_valid(_world) and _world.has_method("navigation_floor"):
		return bool(_world.call("navigation_floor", point))
	return Terrain.relief == null or Terrain.relief.is_land(floori(point.x / 16.0), floori(point.y / 16.0))


func _same_floor(from: Vector2, to: Vector2) -> bool:
	return Terrain.relief == null or absf(Terrain.relief.level_at(from) - Terrain.relief.level_at(to)) < 0.45


func _line_clear(from: Vector2, to: Vector2) -> bool:
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from + Vector2(0, -4), to + Vector2(0, -4), 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _sense() -> void:
	var best: Player
	var evidence: float = -INF
	for player: Player in Player.all:
		if player.health.current <= 0.0:
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
		var forward: bool = Vector2.from_angle(heading).dot((point - global_position).normalized()) > (0.0 if player == _target else 0.35)
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
		if state in [State.LISTEN, State.SEARCH]:
			_set_state(State.NOTICE)


func _idle(delta: float) -> void:
	if night != null and night.goal.is_finite(): ## a creature of the night walks its patrol goal
		var way: Vector2 = _safe_direction(night.walk_dir(self, _navigation, delta))
		velocity = velocity.move_toward(way * float(_def["wander_speed"]) * night.speed_factor(), delta * 120.0)
		if way != Vector2.ZERO:
			heading = lerp_angle(heading, way.angle(), delta * 2.0)
		return
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = _rng.randf_range(1.8, 3.3)
		_wander_dir = Vector2.ZERO if _wander_dir != Vector2.ZERO else Vector2.from_angle(heading + _rng.randf_range(-1.2, 1.2))
	var dir: Vector2 = _safe_direction(_wander_dir)
	velocity = velocity.move_toward(dir * float(_def["wander_speed"]), delta * 90.0)
	if dir != Vector2.ZERO:
		heading = lerp_angle(heading, dir.angle(), delta * 2.0)


func _safe_direction(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return direction
	for turn: float in [0.0, 0.5 * _orbit, -0.5 * _orbit, 1.0 * _orbit, -1.0 * _orbit, 1.55 * _orbit]:
		var dir: Vector2 = direction.rotated(turn)
		if _navigation.segment_clear(global_position, global_position + dir * 22.0) and not test_move(global_transform, dir * 18.0):
			return dir
	return Vector2.ZERO


func _hunt(delta: float) -> void:
	if _memory <= 0.0 or (is_instance_valid(_target) and _target.health.current <= 0.0):
		_set_state(State.SEARCH)
		return
	var toward: Vector2 = _known - global_position
	var distance: float = toward.length()
	var dir: Vector2 = toward.normalized()
	heading = lerp_angle(heading, toward.angle(), delta * float(_def["turn_speed"]))
	var clear: bool = _same_floor(global_position, _known) and _line_clear(global_position, _known)
	if clear and distance <= float(_def["scream"]["trigger_range"]) and _scream_cd <= 0.0:
		_scream_cd = float(_def["scream"]["cooldown"])
		_set_state(State.SCREAM_WINDUP)
		return
	if clear and distance > 45.0 and distance <= float(_def["wave"]["range"]) and _wave_cd <= 0.0 and absf(angle_difference(heading, toward.angle())) < 0.2:
		_wave_cd = float(_def["wave"]["cooldown"])
		_set_state(State.WAVE_WINDUP)
		return
	var speed: float = float(_def["move_speed"])
	if not clear or not _navigation.segment_clear(global_position, _known):
		dir = _navigation.direction_to(_known, delta)
	else:
		_navigation.invalidate()
		if distance < float(_def["preferred_min"]):
			dir = _safe_direction((-dir + dir.orthogonal() * _orbit * 0.35).normalized())
			speed = float(_def["retreat_speed"])
		elif distance <= float(_def["preferred_max"]):
			dir = _safe_direction(dir.orthogonal() * _orbit)
			speed = float(_def["strafe_speed"])
		else:
			dir = _safe_direction(dir)
	velocity = velocity.move_toward(dir * speed, delta * 280.0)


func _set_state(next: State) -> void:
	if next in [State.WAVE_WINDUP, State.SCREAM_WINDUP]:
		attack_origin = global_position
		attack_dir = (_known - global_position).normalized()
		if attack_dir == Vector2.ZERO:
			attack_dir = Vector2.from_angle(heading)
		warning_length = ResonanceWave.clip_distance(self, attack_origin, attack_dir, float(_def["wave"]["range"]), float(_def["wave"]["radius"]))
	if next not in [State.HUNT, State.LISTEN, State.HURT]:
		velocity = Vector2.ZERO
	if next in [State.NOTICE, State.SEARCH, State.LISTEN, State.DEAD]:
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
	_scream_presented = false
	_struck.clear()
	_enter_state()


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server():
		_apply_state.rpc_id(multiplayer.get_remote_sender_id(), state, attack_dir, attack_origin, warning_length, _state_time, _previous)


func _windup(delta: float) -> void:
	velocity = Vector2.ZERO
	var spec: Dictionary = _def["wave"] if state == State.WAVE_WINDUP else _def["scream"]
	_aim_left -= delta
	if _state_time < float(spec["windup"]) - float(spec["aim_lock"]):
		if _memory > 0.0 and _known.distance_squared_to(attack_origin) > 0.01:
			attack_dir = (_known - attack_origin).normalized()
		if _aim_left <= 0.0:
			_aim_left = 0.05
			warning_length = ResonanceWave.clip_distance(self, attack_origin, attack_dir, float(_def["wave"]["range"]), float(_def["wave"]["radius"]))
			_update_aim.rpc(attack_dir, warning_length)
	elif not _aim_locked:
		_aim_locked = true
		_update_aim.rpc(attack_dir, warning_length)
	heading = attack_dir.angle()
	if _state_time >= float(spec["windup"]):
		_set_state(State.WAVE_RELEASE if state == State.WAVE_WINDUP else State.SCREAM)


@rpc("authority", "call_remote", "reliable")
func _update_aim(dir: Vector2, length: float) -> void:
	if state in [State.WAVE_WINDUP, State.SCREAM_WINDUP]:
		attack_dir = dir
		warning_length = length


func _launch_wave() -> void:
	if is_instance_valid(_world) and _world.has_method("spawn_resonance"):
		_world.call("spawn_resonance", attack_origin, attack_dir, _rig.mouth_position(), damage_scale)


func _scream_hit() -> void:
	var spec: Dictionary = _def["scream"]
	if _state_time < 0.02:
		return
	var reach: float = float(spec["reach"]) * clampf(_state_time / float(spec["hit_time"]), 0.0, 1.0)
	for target: HurtboxComponent in HitScan.fan(self, attack_origin + Vector2(0, -12), attack_dir, reach, deg_to_rad(float(spec["arc"])), HURTBOX_MASK):
		if not _struck.has(target.get_instance_id()) and _same_floor(attack_origin, target.global_position) and _line_clear(attack_origin, target.global_position):
			_struck.append(target.get_instance_id())
			target.take_hit(float(spec["damage"]), attack_origin + Vector2(0, -12), float(spec["knockback"]))


func _recovery() -> float:
	return float(_def["scream"]["recover"]) if _previous == State.SCREAM else float(_def["wave"]["recover"])


func _enter_state() -> void:
	var pose: ListenerRig.Pose = ListenerRig.Pose.LISTEN
	var duration: float = 1.0
	var cue: String = ""
	match state:
		State.NOTICE:
			pose = ListenerRig.Pose.NOTICE
			duration = float(_def["notice_seconds"])
		State.HUNT:
			pose = ListenerRig.Pose.MOVE
		State.WAVE_WINDUP, State.SCREAM_WINDUP:
			pose = ListenerRig.Pose.CHARGE if state == State.WAVE_WINDUP else ListenerRig.Pose.BRACE
			duration = float(_def["wave"]["windup"] if state == State.WAVE_WINDUP else _def["scream"]["windup"])
			cue = "charge"
		State.WAVE_RELEASE:
			pose = ListenerRig.Pose.RELEASE
			duration = float(_def["wave"]["release"])
			cue = "wave"
		State.SCREAM:
			pose = ListenerRig.Pose.SCREAM
			duration = float(_def["scream"]["strike"])
			cue = "scream"
		State.RECOVER:
			pose = ListenerRig.Pose.RECOVER
			duration = _recovery()
		State.HURT:
			pose = ListenerRig.Pose.HURT
			duration = float(_def["hurt_stun"])
		State.DEAD:
			pose = ListenerRig.Pose.DEAD
			duration = DEATH_SECONDS
			cue = "death"
	_rig.start_pose(pose, duration, _state_time)
	# Dedicated/headless peers replicate cues but have no spatial listener to play
	# them to. Avoid creating unmanaged dummy-driver WAV playbacks there.
	if not cue.is_empty() and DisplayServer.get_name() != "headless":
		_voice.stop()
		_voice.stream = load(String(_def["audio"][cue])) as AudioStream
		_voice.volume_db = float(_def["audio"]["volume_db"])
		_voice.pitch_scale = 0.96 + float(posmod(hash(name), 9)) * 0.01
		if _state_time < _voice.stream.get_length():
			_voice.play(_state_time)
	elif state == State.HURT:
		_voice.stop()


func _draw_zone() -> void:
	if state not in [State.WAVE_WINDUP, State.SCREAM_WINDUP, State.SCREAM]:
		return
	var scream: bool = state != State.WAVE_WINDUP
	var spec: Dictionary = _def["scream"] if scream else _def["wave"]
	var locked: bool = _state_time >= float(spec["windup"]) - float(spec["aim_lock"])
	var strength: float = 0.75 + (0.2 * sin(_state_time * 38) if locked else 0.0)
	if state == State.SCREAM:
		strength = 1.0 - clampf(_state_time / float(spec["strike"]), 0.0, 1.0)
	var origin: Vector2 = attack_origin - global_position
	var length: float = float(spec["reach"]) + ZONE_PAD if scream else warning_length + float(spec["radius"]) + ZONE_PAD
	var across: Vector2 = attack_dir.orthogonal()
	# Stable sparse pixels flow outward. The band matches the moving hurtbox
	# footprint; the defensive field is a forward fan with an open rear flank.
	for i: int in (550 if scream else 650):
		var u: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var v: float = fposmod(sin(float(i) * 78.233 + 3.1) * 19642.349, 1.0)
		var point: Vector2
		var distance: float
		if scream:
			distance = sqrt(u) * length
			point = attack_dir.rotated((v - 0.5) * deg_to_rad(float(spec["arc"]))) * distance
		else:
			distance = u * length
			point = attack_dir * distance + across * (v - 0.5) * (float(spec["radius"]) + ZONE_PAD) * 2.0
		if distance < 5.0:
			continue
		var wave: float = 0.5 + 0.5 * sin(distance * 0.26 - _state_time * (18 if locked else 9) + v * TAU)
		if wave < 0.48:
			continue
		var color: Color = Color("c21f3b").lerp(Color("ffd0d6") if state == State.SCREAM else Color("ff4a63"), wave)
		_zone.draw_rect(Rect2((origin + point).round(), Vector2.ONE), Color(color, strength * (0.35 + wave * 0.45)))


func _scream_age() -> float:
	if state == State.SCREAM:
		return _state_time
	if state == State.RECOVER and _previous == State.SCREAM:
		return _state_time + float(_def["scream"]["strike"])
	return -1.0


func _present_scream() -> void:
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			var amount: float = 2.8 * (1.0 - smoothstep(30.0, 145.0, player.global_position.distance_to(attack_origin)))
			player.add_shake(amount)
	for i: int in 5:
		var point: Vector2 = attack_origin + attack_dir.rotated((i - 2) * 0.3) * float(_def["scream"]["reach"]) * 0.7
		if _floor_available(point) and _same_floor(attack_origin, point) and _line_clear(attack_origin, point):
			_trail.leave(point)


func _draw_scream() -> void:
	var age: float = _scream_age()
	if age < 0.0 or age > 0.5:
		return
	var spec: Dictionary = _def["scream"]
	var origin: Vector2 = attack_origin - global_position + Vector2(0, -12)
	for arc: int in 4:
		var phase: float = (age - arc * 0.055) / float(spec["hit_time"])
		if phase < 0.0 or phase > 2.3:
			continue
		var radius: float = float(spec["reach"]) * minf(1.0, phase)
		var alpha: float = (1.0 - phase / 2.3) * (1.0 - arc * 0.17)
		var count: int = maxi(24, ceili(radius * 2.2))
		for i: int in count:
			var angle: float = (float(i) / (count - 1) - 0.5) * deg_to_rad(float(spec["arc"]))
			var ripple: float = sin(i * 2.1 + phase * 5.0) * 0.6
			var point: Vector2 = origin + attack_dir.rotated(angle) * (radius + ripple)
			_scream_fx.draw_rect(Rect2(point.round() - Vector2(2, 2), Vector2(5, 5)), Color(Color("8a4dff"), alpha * 0.1))
			_scream_fx.draw_rect(Rect2(point.round() - Vector2.ONE, Vector2(3, 3)), Color(Color("b06bff"), alpha * 0.42))
			var core: Color = Color("fff7ff") if arc == 0 else Color("8a4dff")
			_scream_fx.draw_rect(Rect2(point.round(), Vector2.ONE * (2 if arc == 0 else 1)), Color(core, alpha))
	for i: int in 14:
		var k: float = float(i) / 13.0
		var angle: float = (k - 0.5) * deg_to_rad(float(spec["arc"]))
		var radius: float = float(spec["reach"]) * clampf(age / float(spec["hit_time"]), 0.0, 1.0)
		var point: Vector2 = origin + attack_dir.rotated(angle) * (radius + sin(i * 5.7) * 3.0)
		var fade: float = 1.0 - clampf(age / 0.4, 0.0, 1.0)
		_scream_fx.draw_rect(Rect2(point.round(), Vector2.ONE * 2), Color(Color("ecd2ff"), fade * 0.65))


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	_rig.hit_flash()
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -48), amount, (global_position - from).normalized())
	if not multiplayer.is_server() or _health.current <= 0.0 or state in [State.DEAD, State.WAVE_RELEASE, State.SCREAM]:
		return
	for player: Player in Player.all:
		if player.name.to_int() == _health.last_attacker:
			_target = player
			_known = player.global_position
			_memory = float(_def["memory_seconds"])
	var committed: bool = state in [State.WAVE_WINDUP, State.SCREAM_WINDUP]
	if knockback >= float(_def["heavy_knockback"]) or (not committed and _flinch_cd <= 0.0):
		_flinch_cd = float(_def["flinch_cooldown"])
		velocity = (global_position - from).normalized() * knockback * float(_def["knockback_resistance"])
		_set_state(State.HURT)


func _on_died() -> void:
	if multiplayer.is_server():
		_set_state(State.DEAD)
	_hurtbox.set_deferred("collision_layer", 0)
	_body.set_deferred("disabled", true)
	_death_fx.restart()
	_trail.infest(global_position)
	if multiplayer.is_server():
		await get_tree().create_timer(DEATH_SECONDS + 0.25).timeout
		if is_inside_tree():
			queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_voice):
		_voice.stop()
		_voice.stream = null
