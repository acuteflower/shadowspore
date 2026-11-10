class_name LightFisher
extends CharacterBody2D
## The Lichtfischer (docs/enemies/lichtfischer.md): the fourth standard shadow creature and the first of the water. It lies under the surface and fishes with a lie, a cold
## teal lantern on a stalk that looks like a lamp or a glowing plant. Whoever steps up to the light is bitten. It lives in the water only (never leaves it), the host
## decides everything, every peer replays the same poses from atomic reliable state packets.
##
## Attacks (all telegraphed on the ground in flowing red pixels, aim locked before release, one hit per target):
##   SCHNAPPLUNGE  the bait dips, goes dark, the head breaks the surface with a gape of glass teeth; a hit drags the victim a step towards the water. Afterwards it hangs open (soft).
##   BLENDLICHT    the lantern swells and bursts: a ring of cold light that dazzles; a victim still in reach is bitten at once (BLENDBISS, shorter windup).
##   IRRLICHTER    three lantern sparks drift out and settle around the target after a long flight: stand still and they land on you.
## The lantern is the weak point: a blow breaks a casting. The maw is only reachable during the bite.

enum State { LURK, NOTICE, STALK, SNAP_WINDUP, SNAP, GAPE, FLASH_WINDUP, FLASH, ORB_CAST, RECOVER, DIVE, SURFACE, HURT, DEAD }
const HURTBOX_MASK: int = 1 << 5
const DEATH_SECONDS: float = 1.5
const SQUASH: float = 0.72
const ZONE_Z: int = -3 ## the water surface lies at z -7..-6: the warnings must be above it

var enemy_id: String = "light_fisher"
var health_scale: float = 1.0
var damage_scale: float = 1.0
var emerge_on_spawn: bool = false ## it surfaces (the lantern unfurls); the night's spawn and the dev key use it
var heading: float = PI / 2.0
var lure_vec: Vector2 = Vector2(0.0, 24.0) ## ground vector from the body to the lantern (replicated; the lantern hangs ahead of it)
var state: State = State.LURK
var attack_dir: Vector2 = Vector2.DOWN
var attack_origin: Vector2
var warning_length: float = 0.0
var aim_points: PackedVector2Array = PackedVector2Array() ## the three landing places of a Irrlicht volley
var combo: bool = false ## the Blendbiss: this bite follows the flash with a short windup
var last_hit: String = "body" ## which hurtbox the last blow came through (host)
var _def: Dictionary
var _target: Player
var _known: Vector2
var _memory: float = 0.0
var _positions: Dictionary = {}
var _state_time: float = 0.0
var _previous: State = State.LURK
var _sense_left: float = 0.0
var _decide_left: float = 0.6
var _anchor: Vector2 = Vector2.INF
var _anchor_clock: float = 0.0
var _snap_cd: float = 0.8
var _flash_cd: float = 2.5
var _orb_cd: float = 4.0
var _dive_cd: float = 0.0
var _flinch_cd: float = 0.0
var _aim_left: float = 0.0
var _aim_locked: bool = false
var _struck: Array[int] = []
var _burst_done: Array[bool] = []
var _burst_heard: Array[bool] = []
var _flash_presented: bool = false
var _dive_pending: bool = false
var _dive_goal: Vector2 = Vector2.INF
var _lure_hits: float = 0.0
var _hit_frame: int = -1
var _hit_source: int = -1
var _health_marks: Array[float] = [0.66, 0.33]
var _wander_left: float = 1.5
var _wander_dir: Vector2 = Vector2.ZERO
var _orbit: float = 1.0
var _stuck: float = 0.0
var _clock: float = 0.0
var _lure_wet: bool = true
var _wet_left: float = 0.0
var _retired: bool = false
var _world: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _rig: FisherRig = $Rig
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurt_body: FisherHurtbox = $Hurtbox
@onready var _hurt_lure: FisherHurtbox = $LureHurtbox
@onready var _zone: Node2D = $Zone
@onready var _fx: Node2D = $Fx
@onready var _light: NightLight = $NightLight
@onready var _trail: ShadowTrailComponent = $ShadowTrail
@onready var _voice: AudioStreamPlayer2D = $Voice
@onready var _sfx: AudioStreamPlayer2D = $Sfx
@onready var _death_fx: CPUParticles2D = $DeathFx


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
		if world.has_method("water_depth"):
			_world = world
			break
	_rig.lure_height = float((_def["lure"] as Dictionary)["height"])
	lure_vec = Vector2.from_angle(heading) * float((_def["lure"] as Dictionary)["reach"]) * 0.8
	_zone.z_index = ZONE_Z
	_zone.draw.connect(_draw_zone)
	_fx.draw.connect(_draw_fx)
	_rig.splashed.connect(func(point: Vector2, power: float) -> void: _splash_sound(point, power))
	if emerge_on_spawn:
		state = State.SURFACE
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.9)
		_snap_cd = 1.8
	_enter_state()
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


func _process(delta: float) -> void:
	_clock += delta
	_wet_left -= delta
	if _wet_left <= 0.0:
		_wet_left = 0.2
		_lure_wet = _depth_at(global_position + lure_vec) >= 0.0
	var aiming: bool = state in [State.SNAP_WINDUP, State.SNAP, State.FLASH_WINDUP, State.FLASH, State.ORB_CAST]
	var aware: float = 0.2 if state in [State.LURK, State.SURFACE] else 1.0
	if state == State.DEAD:
		aware = 0.0
	var light: float = lerpf(0.4, 1.0, TimeManager.night_amount())
	_rig.update_rig(delta, velocity, attack_dir.angle() if aiming else heading, lure_vec, light, aware, _lure_wet)
	_follow_rig()
	if state == State.ORB_CAST:
		_orb_sounds()
	_zone.queue_redraw()
	_fx.queue_redraw()


## The hurtboxes and the lantern's light follow the picture: the lantern hangs where the stalk ends, the maw is where the head is.
func _follow_rig() -> void:
	_hurt_lure.position = _rig.lure_local() + Vector2(0.0, 2.0)
	_hurt_body.position = _rig.head_local()
	var lure_on: int = 16 if state not in [State.DEAD, State.DIVE] and _rig.retract() < 0.6 else 0
	var body_on: int = 16 if state in [State.SNAP, State.GAPE] and _rig.rise() > 0.35 else 0
	if _hurt_lure.collision_layer != lure_on:
		_hurt_lure.collision_layer = lure_on
	if _hurt_body.collision_layer != body_on:
		_hurt_body.collision_layer = body_on
	_light.position = _rig.lure_local()
	_light.base_energy = 0.62 * clampf(_rig.lure_energy(), 0.0, 2.4)
	_light.color = Color("7fe8d0").lerp(Color("ff4fd8"), _rig.danger() * 0.9)


func _physics_process(delta: float) -> void:
	_state_time += delta
	if not multiplayer.is_server() or state == State.DEAD:
		return
	_snap_cd = maxf(0.0, _snap_cd - delta)
	_flash_cd = maxf(0.0, _flash_cd - delta)
	_orb_cd = maxf(0.0, _orb_cd - delta)
	_dive_cd = maxf(0.0, _dive_cd - delta)
	_flinch_cd = maxf(0.0, _flinch_cd - delta)
	_memory = maxf(0.0, _memory - delta)
	_decide_left = maxf(0.0, _decide_left - delta)
	_lure_hits = maxf(0.0, _lure_hits - delta * 0.4)
	_sense_left -= delta
	if _sense_left <= 0.0:
		_sense_left = float(_def["sense_interval"])
		_sense()
	match state:
		State.LURK:
			_lurk(delta)
		State.NOTICE:
			_brake(delta)
			heading = lerp_angle(heading, (_known - global_position).angle(), delta * float(_def["turn_speed"]))
			if _state_time >= float(_def["notice_seconds"]):
				_set_state(State.STALK)
		State.STALK:
			_stalk(delta)
		State.SNAP_WINDUP, State.FLASH_WINDUP:
			_windup(delta)
		State.SNAP:
			_brake(delta)
			_snap_hit()
			if _state_time >= float((_def["snap"] as Dictionary)["strike"]):
				_set_state(State.GAPE)
		State.GAPE:
			_brake(delta)
			if _state_time >= float((_def["snap"] as Dictionary)["gape"]):
				_after_attack()
		State.FLASH:
			_brake(delta)
			if not _flash_presented:
				_flash_presented = true
				_flash_hit()
			if _state_time >= float((_def["flash"] as Dictionary)["strike"]):
				_after_flash()
		State.ORB_CAST:
			_brake(delta)
			heading = lerp_angle(heading, attack_dir.angle(), delta * 6.0)
			_orb_bursts()
			if _state_time >= _orb_total():
				_set_state(State.RECOVER)
		State.RECOVER:
			_brake(delta)
			if _state_time >= _recovery():
				_after_attack()
		State.DIVE:
			_dive(delta)
		State.SURFACE:
			_brake(delta)
			if _state_time >= float((_def["dive"] as Dictionary)["surface"]):
				_after_attack()
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, delta * 300.0)
			if _state_time >= float(_def["hurt_stun"]):
				if _dive_pending and _dive_cd <= 0.0:
					_set_state(State.DIVE)
				else:
					_dive_pending = false
					_after_attack()
	_steer_lure(delta)
	_swim_step(delta)


# ---------------------------------------------------------------------------------------------------- water

func _depth_at(point: Vector2) -> float:
	if is_instance_valid(_world) and _world.has_method("water_depth"):
		return float(_world.call("water_depth", point))
	return -1.0


func _water_ok(point: Vector2) -> bool:
	return _depth_at(point) >= float(_def["min_depth"])


## The way it may swim: `direction` turned until two probes ahead are deep enough water; zero when the water ends.
func _water_dir(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return direction
	var probe: float = float((_def["navigation"] as Dictionary)["probe"])
	for turn: float in [0.0, 0.45 * _orbit, -0.45 * _orbit, 0.9 * _orbit, -0.9 * _orbit, 1.4 * _orbit, -1.4 * _orbit, 2.0 * _orbit]:
		var dir: Vector2 = direction.rotated(turn)
		if _water_ok(global_position + dir * probe) and _water_ok(global_position + dir * probe * 2.0):
			return dir
	return Vector2.ZERO


## Moves by hand: the creature has no collision, the water decides where it may be.
func _swim_step(delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	var next: Vector2 = position + velocity * delta
	if state == State.DIVE or _water_ok(global_position + velocity * delta):
		position = next
	else:
		velocity = Vector2.ZERO


func _brake(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, delta * 160.0)


func _find_anchor(target: Vector2) -> Vector2:
	if _water_ok(target):
		return global_position if global_position.distance_to(target) < 34.0 else target + (global_position - target).normalized() * 28.0
	var best: Vector2 = Vector2.INF
	var best_score: float = INF
	for radius: float in [24.0, 34.0, 46.0, 62.0]:
		for side: int in 16:
			var point: Vector2 = target + Vector2.from_angle(side * TAU / 16.0) * radius
			if not _water_ok(point):
				continue
			var score: float = radius + point.distance_to(global_position) * 0.35
			if score < best_score:
				best_score = score
				best = point
	return best


func _line_clear(from: Vector2, to: Vector2) -> bool:
	var exclude: Array[RID] = []
	for attempt: int in 6:
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from + Vector2(0, -6), to + Vector2(0, -6), 1, exclude)
		var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			return true
		var collider: Object = hit["collider"] as Object
		if collider is CollisionObject2D and (collider as Node).is_in_group("river_depth"):
			exclude.append((collider as CollisionObject2D).get_rid()) ## the river's own deep-water collision is not a wall for it
			continue
		return false
	return false


func _same_floor(from: Vector2, to: Vector2) -> bool:
	return Terrain.relief == null or absf(Terrain.relief.level_at(from) - Terrain.relief.level_at(to)) < 0.45


# ---------------------------------------------------------------------------------------------------- senses

func _sense() -> void:
	var best: Player
	var evidence: float = -INF
	var day_mult: float = lerpf(1.0, float(_def["day_sense"]), 1.0 - TimeManager.night_amount())
	for player: Player in Player.all:
		if player.health.current <= 0.0:
			continue
		var point: Vector2 = player.global_position
		var moved: bool = point.distance_to(_positions.get(player.get_instance_id(), point)) > 0.75 or player.velocity.length() > 8.0
		_positions[player.get_instance_id()] = point
		var hear: float = (player.stealth.alarm_scale() if player != _target else 1.0) * day_mult
		var radius: float = 30.0
		if moved:
			if player.swim != SwimRules.NONE:
				radius = float(_def["hearing_swim"])
			elif player.stealth.sneaking:
				radius = float(_def["hearing_sneak"])
			elif player.sprinting:
				radius = float(_def["hearing_sprint"])
			else:
				radius = float(_def["hearing_walk"])
		radius *= hear
		if player.attack.is_swinging():
			radius = maxf(radius, float(_def["hearing_attack"]) * player.attack.noise_scale() * hear)
		var distance: float = global_position.distance_to(point)
		var sight: float = float(_def["sight_range"]) * (player.stealth.detection_multiplier() * hear if player != _target else day_mult)
		if distance > radius and distance > sight:
			continue
		var strength: float = maxf(radius - distance, sight - distance)
		if player == _target:
			strength += 18.0
		if strength > evidence:
			evidence = strength
			best = player
	if best != null:
		_target = best
		_known = best.global_position
		_memory = float(_def["memory_seconds"])
		if state == State.LURK:
			_set_state(State.NOTICE)


# ---------------------------------------------------------------------------------------------------- behaviour

func _lurk(delta: float) -> void:
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = _rng.randf_range(2.6, 5.6)
		_wander_dir = Vector2.ZERO if _wander_dir != Vector2.ZERO else Vector2.from_angle(heading + _rng.randf_range(-1.4, 1.4))
	var dir: Vector2 = _water_dir(_wander_dir)
	velocity = velocity.move_toward(dir * float(_def["drift_speed"]), delta * 40.0)
	if dir != Vector2.ZERO:
		heading = lerp_angle(heading, dir.angle(), delta * 1.6)


func _stalk(delta: float) -> void:
	if _memory <= 0.0 or (is_instance_valid(_target) and _target.health.current <= 0.0):
		_target = null
		_set_state(State.LURK)
		return
	var toward: Vector2 = _known - global_position
	var distance: float = toward.length()
	heading = lerp_angle(heading, toward.angle(), delta * float(_def["turn_speed"]))
	_anchor_clock -= delta
	if _anchor_clock <= 0.0:
		_anchor_clock = 0.45
		_anchor = _find_anchor(_known)
	var snap: Dictionary = _def["snap"] as Dictionary
	var clear: bool = _same_floor(global_position, _known) and _line_clear(global_position, _known)
	if distance <= float(snap["trigger"]) and _snap_cd <= 0.0 and clear:
		combo = false
		_set_state(State.SNAP_WINDUP)
		return
	if _decide_left <= 0.0 and clear:
		_decide_left = 0.4
		var flash: Dictionary = _def["flash"] as Dictionary
		var orbs: Dictionary = _def["orbs"] as Dictionary
		if _flash_cd <= 0.0 and distance >= float(flash["range_min"]) and distance <= float(flash["range_max"]) and _rng.randf() < 0.5:
			_set_state(State.FLASH_WINDUP)
			return
		if _orb_cd <= 0.0 and distance >= float(orbs["range_min"]) and distance <= float(orbs["range_max"]) and _rng.randf() < 0.5:
			_set_state(State.ORB_CAST)
			return
	var want: Vector2 = Vector2.ZERO
	if _anchor.is_finite() and global_position.distance_to(_anchor) > 5.0:
		want = _water_dir((_anchor - global_position).normalized())
	velocity = velocity.move_toward(want * float(_def["stalk_speed"]), delta * 150.0)
	if want != Vector2.ZERO and velocity.length() < 3.0:
		_stuck += delta
	else:
		_stuck = 0.0
	if _stuck >= float((_def["navigation"] as Dictionary)["stuck_seconds"]) and _dive_cd <= 0.0:
		_stuck = 0.0
		_dive_pending = false
		_set_state(State.DIVE) ## cornered in a pocket of the water: slip away and come up elsewhere


func _after_attack() -> void:
	if _dive_pending and _dive_cd <= 0.0:
		_set_state(State.DIVE)
	else:
		_dive_pending = false
		_set_state(State.STALK if _memory > 0.0 else State.LURK)


func _after_flash() -> void:
	var snap: Dictionary = _def["snap"] as Dictionary
	if _snap_cd <= 0.0 and is_instance_valid(_target) and _target.health.current > 0.0 and global_position.distance_to(_target.global_position) <= float(snap["reach"]) * 0.85:
		_known = _target.global_position
		combo = true ## dazzled and in reach: the bite follows at once
		_set_state(State.SNAP_WINDUP)
	else:
		_set_state(State.RECOVER)


## The lantern hangs ahead of the body towards whoever it wants to lure; during a casting it stays over its spot.
func _steer_lure(delta: float) -> void:
	var spec: Dictionary = _def["lure"] as Dictionary
	var want: Vector2
	if state in [State.FLASH_WINDUP, State.FLASH, State.ORB_CAST]:
		want = attack_origin - global_position
	elif _memory > 0.0 and is_instance_valid(_target) and state in [State.NOTICE, State.STALK, State.SNAP_WINDUP, State.GAPE, State.RECOVER, State.HURT]:
		var to: Vector2 = _known - global_position
		want = to.normalized() * clampf(to.length() - 10.0, float(spec["min_reach"]), float(spec["reach"]))
	else:
		want = Vector2.from_angle(heading + sin(_clock * 0.4) * 0.7) * float(spec["reach"]) * 0.8
	lure_vec = lure_vec.lerp(want, 1.0 - exp(-delta * 5.0))


func _windup(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, delta * 240.0)
	var snap: bool = state == State.SNAP_WINDUP
	var spec: Dictionary = _def["snap"] as Dictionary if snap else _def["flash"] as Dictionary
	var total: float = _windup_time()
	if snap:
		_aim_left -= delta
		var lock: float = float(spec["aim_lock"]) * (total / float(spec["windup"]))
		if _state_time < total - lock:
			if _memory > 0.0 and _known.distance_squared_to(attack_origin) > 0.01:
				attack_dir = (_known - attack_origin).normalized()
			if _aim_left <= 0.0:
				_aim_left = 0.05
				_update_aim.rpc(attack_dir)
		elif not _aim_locked:
			_aim_locked = true
			_update_aim.rpc(attack_dir)
		heading = attack_dir.angle()
	else:
		heading = lerp_angle(heading, (_known - global_position).angle(), delta * 4.0)
	if _state_time >= total:
		_set_state(State.SNAP if snap else State.FLASH)


func _windup_time() -> float:
	if state == State.SNAP_WINDUP:
		var snap: Dictionary = _def["snap"] as Dictionary
		return float(snap["combo_windup"]) if combo else float(snap["windup"])
	return float((_def["flash"] as Dictionary)["windup"])


func _recovery() -> float:
	if _previous == State.ORB_CAST:
		return float((_def["orbs"] as Dictionary)["recover"])
	return float((_def["flash"] as Dictionary)["recover"])


func _dive(delta: float) -> void:
	var spec: Dictionary = _def["dive"] as Dictionary
	if _state_time < float(spec["seconds_under"]) * 0.6:
		velocity = velocity.move_toward(Vector2.ZERO, delta * 200.0) ## it sinks first
		return
	if not _dive_goal.is_finite():
		_dive_goal = _pick_dive_goal()
	var to: Vector2 = _dive_goal - global_position
	if to.length() < 5.0 or _state_time > 6.0 or not _dive_goal.is_finite():
		velocity = Vector2.ZERO
		_set_state(State.SURFACE)
		return
	velocity = velocity.move_toward(to.normalized() * float(spec["speed"]), delta * 260.0)
	heading = lerp_angle(heading, to.angle(), delta * 6.0)


func _pick_dive_goal() -> Vector2:
	var span: Array = (_def["dive"] as Dictionary)["distance"] as Array
	for attempt: int in 16:
		var point: Vector2 = global_position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(float(span[0]), float(span[1]))
		if not _water_ok(point):
			continue
		var clear: bool = true
		for step: int in range(1, 5):
			if not _water_ok(global_position.lerp(point, float(step) / 5.0)):
				clear = false
		if clear:
			return point
	return global_position


# ---------------------------------------------------------------------------------------------------- state and replication

func _set_state(next: State) -> void:
	if next in [State.SNAP_WINDUP, State.FLASH_WINDUP, State.ORB_CAST]:
		var toward: Vector2 = _known - global_position
		attack_dir = toward.normalized() if toward != Vector2.ZERO else Vector2.from_angle(heading)
		attack_origin = global_position if next == State.SNAP_WINDUP else global_position + lure_vec
		warning_length = float((_def["snap"] as Dictionary)["reach"])
		aim_points = _volley_points(attack_origin) if next == State.ORB_CAST else PackedVector2Array()
	if next == State.DIVE:
		_dive_goal = Vector2.INF
		_dive_pending = false
		_dive_cd = float((_def["dive"] as Dictionary)["cooldown"])
	if next in [State.SNAP_WINDUP, State.SNAP, State.GAPE, State.FLASH_WINDUP, State.FLASH, State.ORB_CAST]:
		_anchor_clock = 0.0
	if next not in [State.LURK, State.STALK, State.DIVE]:
		velocity = velocity if next == State.HURT else Vector2.ZERO
	_apply_state.rpc(next, attack_dir, attack_origin, warning_length, 0.0, state, aim_points, combo)


@rpc("authority", "call_local", "reliable")
func _apply_state(next: int, direction: Vector2, origin: Vector2, length: float, elapsed: float, previous: int, points: PackedVector2Array, with_combo: bool) -> void:
	_previous = previous as State
	state = next as State
	attack_dir = direction
	attack_origin = origin
	warning_length = length
	aim_points = points
	combo = with_combo
	_state_time = elapsed
	_aim_left = 0.0
	_aim_locked = false
	_flash_presented = false
	_struck.clear()
	_burst_done.clear()
	_burst_heard.clear()
	for i: int in points.size():
		_burst_done.append(false)
		_burst_heard.append(false)
	_enter_state()


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server():
		_apply_state.rpc_id(multiplayer.get_remote_sender_id(), state, attack_dir, attack_origin, warning_length, _state_time, _previous, aim_points, combo)


@rpc("authority", "call_remote", "reliable")
func _update_aim(dir: Vector2) -> void:
	if state == State.SNAP_WINDUP:
		attack_dir = dir


@rpc("authority", "call_local", "reliable")
func _rpc_lure_struck() -> void:
	_rig.lure_struck()


func _enter_state() -> void:
	var pose: FisherRig.Pose = FisherRig.Pose.LURK
	var duration: float = 1.0
	var cue: String = ""
	match state:
		State.NOTICE:
			pose = FisherRig.Pose.NOTICE
			duration = float(_def["notice_seconds"])
			cue = "twitch"
		State.STALK:
			pose = FisherRig.Pose.STALK
		State.SNAP_WINDUP:
			pose = FisherRig.Pose.SNAP_WINDUP
			duration = _windup_time()
			cue = "snap_windup"
		State.SNAP:
			pose = FisherRig.Pose.SNAP
			duration = float((_def["snap"] as Dictionary)["strike"])
			cue = "snap"
		State.GAPE:
			pose = FisherRig.Pose.GAPE
			duration = float((_def["snap"] as Dictionary)["gape"])
		State.FLASH_WINDUP:
			pose = FisherRig.Pose.FLASH_WINDUP
			duration = _windup_time()
			cue = "flash_windup"
		State.FLASH:
			pose = FisherRig.Pose.FLASH
			duration = float((_def["flash"] as Dictionary)["strike"])
			cue = "flash"
		State.ORB_CAST:
			pose = FisherRig.Pose.ORB_CAST
			duration = _orb_total()
			cue = "orb"
		State.RECOVER:
			pose = FisherRig.Pose.RECOVER
			duration = _recovery()
		State.DIVE:
			pose = FisherRig.Pose.DIVE
			cue = "dive"
		State.SURFACE:
			pose = FisherRig.Pose.SURFACE
			duration = float((_def["dive"] as Dictionary)["surface"])
		State.HURT:
			pose = FisherRig.Pose.HURT
			duration = float(_def["hurt_stun"])
			cue = "hurt"
		State.DEAD:
			pose = FisherRig.Pose.DEAD
			duration = DEATH_SECONDS
			cue = "death"
	_rig.start_pose(pose, duration, _state_time)
	if state == State.FLASH:
		_present_flash()
	if cue.is_empty() or DisplayServer.get_name() == "headless":
		return
	_play(_voice, cue, 0.96 + float(posmod(hash(name), 9)) * 0.01)


func _play(player: AudioStreamPlayer2D, cue: String, pitch: float) -> void:
	var path: String = String((_def["audio"] as Dictionary).get(cue, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	player.stop()
	player.stream = load(path) as AudioStream
	player.volume_db = float((_def["audio"] as Dictionary)["volume_db"])
	player.pitch_scale = pitch
	if _state_time < player.stream.get_length():
		player.play(_state_time if player == _voice else 0.0)


func _splash_sound(_point: Vector2, _power: float) -> void:
	pass


# ---------------------------------------------------------------------------------------------------- the bite

func _snap_hit() -> void:
	var spec: Dictionary = _def["snap"] as Dictionary
	if _state_time < 0.04:
		return
	var reach: float = float(spec["reach"]) * clampf(_state_time / float(spec["hit_time"]), 0.0, 1.0)
	for target: HurtboxComponent in HitScan.fan(self, attack_origin + Vector2(0, -12), attack_dir, reach, deg_to_rad(float(spec["arc"])), HURTBOX_MASK):
		if _struck.has(target.get_instance_id()) or not _same_floor(attack_origin, target.global_position) or not _line_clear(attack_origin, target.global_position):
			continue
		_struck.append(target.get_instance_id())
		target.take_hit(float(spec["damage"]), attack_origin + Vector2(0, -12), float(spec["knockback"]))
		var victim: Player = target.get_parent() as Player
		if victim != null and victim.health.current > 0.0:
			var away: Vector2 = victim.global_position - attack_origin
			var pull: float = minf(float(spec["pull"]), maxf(0.0, away.length() - 12.0))
			victim.launch(victim.global_position - away.normalized() * pull, float(spec["pull_seconds"])) ## dragged a step towards the water
		_trail.leave(attack_origin + attack_dir * reach * 0.8, true)


func _circle_targets(center: Vector2, radius: float) -> Array[HurtboxComponent]:
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, center)
	query.collision_mask = HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var found: Array[HurtboxComponent] = []
	for hit: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 16):
		var target: HurtboxComponent = hit["collider"] as HurtboxComponent
		if target != null and not found.has(target):
			found.append(target)
	return found


func _flash_hit() -> void:
	var spec: Dictionary = _def["flash"] as Dictionary
	for target: HurtboxComponent in _circle_targets(attack_origin + Vector2(0, -12), float(spec["radius"])):
		if _same_floor(attack_origin, target.global_position):
			target.take_hit(float(spec["damage"]), attack_origin + Vector2(0, -12), float(spec["knockback"]))
	_flash_cd = float(spec["cooldown"])


## Everyone's own screen, on their own machine: a white-out and a few false lamps.
func _present_flash() -> void:
	var spec: Dictionary = _def["flash"] as Dictionary
	for player: Player in Player.all:
		if not player.is_multiplayer_authority():
			continue
		var distance: float = player.global_position.distance_to(attack_origin)
		var reach: float = float(spec["radius"]) * 1.25
		var amount: float = 1.0 - smoothstep(float(spec["radius"]) * 0.45, reach, distance)
		if amount > 0.02:
			FisherDazzle.spawn(get_tree(), float(spec["dazzle"]) * (0.5 + 0.5 * amount), amount)
			player.add_shake(2.4 * amount)


# ---------------------------------------------------------------------------------------------------- the Irrlichter

func _volley_points(origin: Vector2) -> PackedVector2Array:
	var spec: Dictionary = _def["orbs"] as Dictionary
	var toward: Vector2 = _known - origin
	var dir: Vector2 = toward.normalized() if toward != Vector2.ZERO else Vector2.from_angle(heading)
	var reach: float = minf(toward.length(), float(spec["range_max"]))
	var center: Vector2 = origin + dir * reach
	var side: Vector2 = dir.orthogonal() * float(spec["spread"])
	return PackedVector2Array([center, center + side, center - side])


func _orb_launch(i: int) -> float:
	var spec: Dictionary = _def["orbs"] as Dictionary
	return float(spec["windup"]) + float(i) * float(spec["stagger"])


func _orb_fly(i: int) -> float:
	return maxf(0.55, attack_origin.distance_to(aim_points[i]) / float((_def["orbs"] as Dictionary)["speed"]))


func _orb_total() -> float:
	var total: float = float((_def["orbs"] as Dictionary)["windup"]) + 1.0
	for i: int in aim_points.size():
		total = maxf(total, _orb_launch(i) + _orb_fly(i) + float((_def["orbs"] as Dictionary)["burst_seconds"]))
	return total


## Where orb `i` is at state time `t` (ground point and height above it) or INF before the launch.
func _orb_at(i: int, t: float) -> Dictionary:
	var launch: float = _orb_launch(i)
	if t < launch:
		return {}
	var fly: float = _orb_fly(i)
	var u: float = clampf((t - launch) / fly, 0.0, 1.0)
	var eased: float = u * u * (3.0 - 2.0 * u)
	var end: Vector2 = aim_points[i]
	var across: Vector2 = (end - attack_origin).orthogonal().normalized()
	var sway: float = sin(u * PI) * 9.0 * (1.0 if i % 2 == 0 else -1.0)
	var ground: Vector2 = attack_origin.lerp(end, eased) + across * sway
	var height: float = lerpf(float(_rig.lure_height) + 6.0, 0.0, pow(u, 2.4)) + sin(u * PI) * 10.0
	return {"ground": ground, "height": height, "u": u}


func _orb_bursts() -> void:
	var spec: Dictionary = _def["orbs"] as Dictionary
	for i: int in aim_points.size():
		if _burst_done[i] or _state_time < _orb_launch(i) + _orb_fly(i):
			continue
		_burst_done[i] = true
		for target: HurtboxComponent in _circle_targets(aim_points[i] + Vector2(0, -12), float(spec["burst_radius"])):
			target.take_hit(float(spec["damage"]), aim_points[i] + Vector2(0, -12), float(spec["knockback"]))
		_orb_cd = float(spec["cooldown"])


func _orb_sounds() -> void:
	for i: int in aim_points.size():
		if i < _burst_heard.size() and not _burst_heard[i] and _state_time >= _orb_launch(i) + _orb_fly(i):
			_burst_heard[i] = true
			if DisplayServer.get_name() != "headless":
				_play(_sfx, "burst", 0.92 + 0.08 * float(i))
			_rig.add_ring(aim_points[i], 1.0, 0.8)


# ---------------------------------------------------------------------------------------------------- hits and death

## Both hurtboxes ask: false when this blow already came through the other one in the same frame (a wide sweep touches both).
func accept_hit(kind: String, source: int) -> bool:
	var frame: int = Engine.get_physics_frames()
	if frame == _hit_frame and source == _hit_source:
		return false
	_hit_frame = frame
	_hit_source = source
	last_hit = kind
	return true


func damage_factor(kind: String) -> float:
	if kind == "lure":
		return float(_def["lure_damage"])
	return float(_def["gape_damage"]) if state == State.GAPE else 1.0


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	_rig.hit_flash()
	var at: Vector2 = _rig.lure_local() if last_hit == "lure" else _rig.head_local()
	DamageNumber.spawn(get_tree().current_scene, global_position + at + Vector2(0, -14), amount, (global_position - from).normalized())
	if not multiplayer.is_server() or _health.current <= 0.0 or state in [State.DEAD, State.DIVE, State.SURFACE, State.FLASH, State.SNAP]:
		return
	for player: Player in Player.all:
		if player.name.to_int() == _health.last_attacker:
			_target = player
			_known = player.global_position
			_memory = float(_def["memory_seconds"])
	var lure_hit: bool = last_hit == "lure"
	if lure_hit:
		_lure_hits += 1.0
		_rpc_lure_struck.rpc()
	var fraction: float = _health.current / maxf(_health.max_health, 1.0)
	while not _health_marks.is_empty() and fraction <= _health_marks[0]:
		_health_marks.remove_at(0)
		_dive_pending = true ## wounded: it slips away to come up somewhere else
	if _lure_hits >= 3.0:
		_lure_hits = 0.0
		_dive_pending = true
	var committed: bool = state in [State.SNAP_WINDUP, State.FLASH_WINDUP, State.ORB_CAST]
	if lure_hit and committed:
		_set_state(State.HURT) ## a blow on the lantern breaks the casting
	elif state == State.GAPE:
		_dive_pending = true
		_set_state(State.HURT)
	elif knockback >= float(_def["heavy_knockback"]) or (not committed and _flinch_cd <= 0.0):
		_flinch_cd = float(_def["flinch_cooldown"])
		_set_state(State.HURT)


func _on_died() -> void:
	if multiplayer.is_server():
		_set_state(State.DEAD)
	_hurt_body.set_deferred("collision_layer", 0)
	_hurt_lure.set_deferred("collision_layer", 0)
	_death_fx.position = _rig.lure_local()
	_death_fx.restart()
	_trail.infest(global_position)
	if multiplayer.is_server():
		await get_tree().create_timer(DEATH_SECONDS + 0.25).timeout
		if is_inside_tree():
			queue_free()


## Host: the morning. It sinks and is gone without loot (the night director calls this at dawn).
func retire() -> void:
	if _retired or not multiplayer.is_server() or state == State.DEAD:
		return
	_retired = true
	set_meta("burned", true)
	_set_state(State.DIVE)
	create_tween().tween_property(self, "modulate:a", 0.0, 1.4)
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree():
		queue_free()


func _exit_tree() -> void:
	for player: AudioStreamPlayer2D in [_voice, _sfx]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


# ---------------------------------------------------------------------------------------------------- warnings and effects

func _flow(i: int, salt: float) -> Vector2:
	return Vector2(fposmod(sin(float(i) * 12.9898 + salt) * 43758.5453, 1.0), fposmod(sin(float(i) * 78.233 + 3.1 + salt) * 19642.349, 1.0))


func _warn_color(wave: float, hot: bool) -> Color:
	return Color("c21f3b").lerp(Color("ffd0d6") if hot else Color("ff4a63"), wave)


func _draw_zone() -> void:
	match state:
		State.SNAP_WINDUP, State.SNAP:
			_zone_fan()
		State.FLASH_WINDUP:
			_zone_disc(attack_origin - global_position, float((_def["flash"] as Dictionary)["radius"]), _state_time / _windup_time())
		State.ORB_CAST:
			var spec: Dictionary = _def["orbs"] as Dictionary
			for i: int in aim_points.size():
				var launched: float = _state_time - _orb_launch(i)
				if launched < 0.0:
					continue
				var progress: float = clampf(launched / _orb_fly(i), 0.0, 1.0)
				if not _burst_done[i] or _state_time < _orb_launch(i) + _orb_fly(i) + 0.12:
					_zone_disc(aim_points[i] - global_position, float(spec["burst_radius"]) + 2.0, 0.3 + 0.7 * progress)


func _zone_fan() -> void:
	var spec: Dictionary = _def["snap"] as Dictionary
	var total: float = _windup_time()
	var locked: bool = state == State.SNAP or _state_time >= total - float(spec["aim_lock"]) * (total / float(spec["windup"]))
	var strength: float = 0.7 + (0.22 * sin(_state_time * 38.0) if locked else 0.0)
	if state == State.SNAP:
		strength = 1.0 - clampf(_state_time / float(spec["strike"]), 0.0, 1.0)
	var origin: Vector2 = attack_origin - global_position
	var length: float = float(spec["reach"]) + 4.0
	for i: int in 520:
		var rnd: Vector2 = _flow(i, 0.0)
		var distance: float = sqrt(rnd.x) * length
		var point: Vector2 = attack_dir.rotated((rnd.y - 0.5) * deg_to_rad(float(spec["arc"]))) * distance
		if distance < 5.0:
			continue
		var wave: float = 0.5 + 0.5 * sin(distance * 0.26 - _state_time * (18.0 if locked else 9.0) + rnd.y * TAU)
		if wave < 0.48:
			continue
		_zone.draw_rect(Rect2((origin + Vector2(point.x, point.y * SQUASH)).round(), Vector2.ONE), Color(_warn_color(wave, state == State.SNAP), strength * (0.35 + wave * 0.45)))


## A disc of flowing red pixels on the water or the ground; `progress` 0..1 how close the moment is.
func _zone_disc(center: Vector2, radius: float, progress: float) -> void:
	var strength: float = 0.35 + 0.6 * clampf(progress, 0.0, 1.0)
	var count: int = int(clampf(radius * radius * 0.2, 60.0, 520.0))
	for i: int in count:
		var rnd: Vector2 = _flow(i, radius)
		var distance: float = sqrt(rnd.x) * radius
		var angle: float = rnd.y * TAU
		var wave: float = 0.5 + 0.5 * sin(distance * 0.3 - _state_time * (10.0 + progress * 16.0) + rnd.y * TAU)
		if wave < 0.46:
			continue
		var point: Vector2 = Vector2(cos(angle), sin(angle) * SQUASH) * distance
		_zone.draw_rect(Rect2((center + point).round(), Vector2.ONE), Color(_warn_color(wave, progress > 0.85), strength * (0.3 + wave * 0.5)))
	for k: int in 36: ## the rim stays clear, so the edge of the danger is readable
		var edge: float = TAU * float(k) / 36.0
		_zone.draw_rect(Rect2((center + Vector2(cos(edge), sin(edge) * SQUASH) * radius).round(), Vector2.ONE), Color("ff4a63", strength * 0.8))


func _draw_fx() -> void:
	_fx_flash()
	_fx_bite()
	_fx_orbs()


func _fx_flash() -> void:
	var age: float = -1.0
	if state == State.FLASH:
		age = _state_time
	elif state == State.RECOVER and _previous == State.FLASH:
		age = _state_time + float((_def["flash"] as Dictionary)["strike"])
	if age < 0.0 or age > 0.9:
		return
	var spec: Dictionary = _def["flash"] as Dictionary
	var radius: float = float(spec["radius"])
	var origin: Vector2 = attack_origin - global_position + Vector2(0, -float(_rig.lure_height))
	var ground: Vector2 = attack_origin - global_position
	var core: float = 1.0 - clampf(age / 0.22, 0.0, 1.0)
	if core > 0.0:
		for ring: int in 6:
			var r: float = (7.0 + float(ring) * 5.0) * (0.6 + core)
			_fx_disc(origin, r, Color(0.85, 1.0, 0.96, 0.1 * core))
	for wave: int in 3:
		var phase: float = (age - float(wave) * 0.07) / 0.3
		if phase < 0.0 or phase > 2.0:
			continue
		var r2: float = radius * minf(1.0, phase)
		var alpha: float = (1.0 - phase / 2.0) * (1.0 - float(wave) * 0.22)
		var steps: int = maxi(30, ceili(r2 * 2.6))
		for i: int in steps:
			var angle: float = TAU * float(i) / float(steps)
			var ripple: float = sin(float(i) * 2.1 + phase * 5.0) * 0.7
			var point: Vector2 = ground + Vector2(cos(angle), sin(angle) * SQUASH) * (r2 + ripple)
			_fx.draw_rect(Rect2(point.round() - Vector2.ONE, Vector2(3, 3)), Color("7ff0d8", alpha * 0.14))
			_fx.draw_rect(Rect2(point.round(), Vector2.ONE * (2 if wave == 0 else 1)), Color("eafff8" if wave == 0 else "b06bff", alpha))
	for i: int in 18: ## false lamps thrown outwards
		var rnd: Vector2 = _flow(i, 4.0)
		var travel: float = clampf(age / 0.5, 0.0, 1.0)
		var spot: Vector2 = ground + Vector2(cos(rnd.y * TAU), sin(rnd.y * TAU) * SQUASH) * radius * (0.35 + 0.65 * rnd.x) * travel - Vector2(0, 8.0 * travel * (0.4 + rnd.x))
		_fx.draw_rect(Rect2(spot.round(), Vector2.ONE * 2), Color("c9fff0", (1.0 - travel) * 0.8))


## A filled ellipse of pixels (rows), flattened by the 3/4 view.
func _fx_disc(center: Vector2, radius: float, color: Color) -> void:
	var rows: int = ceili(radius * SQUASH)
	for row: int in range(-rows, rows + 1):
		var span: float = radius * sqrt(maxf(0.0, 1.0 - pow(float(row) / (radius * SQUASH), 2.0)))
		_fx.draw_rect(Rect2((center + Vector2(-span, float(row))).round(), Vector2(span * 2.0, 1.0)), color)


func _fx_bite() -> void:
	if state != State.SNAP:
		return
	var spec: Dictionary = _def["snap"] as Dictionary
	var age: float = _state_time - float(spec["hit_time"])
	if age < -0.02 or age > 0.14:
		return
	var origin: Vector2 = attack_origin - global_position
	for i: int in 14: ## the clamp: a flick of glass and light in the arc
		var rnd: Vector2 = _flow(i, 9.0)
		var angle: float = (rnd.y - 0.5) * deg_to_rad(float(spec["arc"]))
		var point: Vector2 = origin + attack_dir.rotated(angle) * float(spec["reach"]) * (0.55 + 0.4 * rnd.x)
		var fade: float = 1.0 - clampf(age / 0.14, 0.0, 1.0)
		_fx.draw_rect(Rect2(Vector2(point.x, point.y * SQUASH - 8.0).round(), Vector2.ONE * 2), Color("ecd2ff", fade * 0.8))


func _fx_orbs() -> void:
	if state != State.ORB_CAST:
		return
	var spec: Dictionary = _def["orbs"] as Dictionary
	for i: int in aim_points.size():
		var orb: Dictionary = _orb_at(i, _state_time)
		if orb.is_empty():
			continue
		var u: float = float(orb["u"])
		var ground: Vector2 = (orb["ground"] as Vector2) - global_position
		var height: float = float(orb["height"])
		if u < 1.0:
			for trail: int in 6: ## a faint trail of teal sparks
				var back: Dictionary = _orb_at(i, _state_time - float(trail) * 0.05)
				if back.is_empty():
					continue
				var at: Vector2 = Vector2(((back["ground"] as Vector2) - global_position).x, ((back["ground"] as Vector2) - global_position).y * SQUASH - float(back["height"]))
				_fx.draw_rect(Rect2(at.round(), Vector2.ONE), Color("7ff0d8", 0.5 * (1.0 - float(trail) / 6.0)))
			var at_orb: Vector2 = Vector2(ground.x, ground.y * SQUASH - height)
			var tint: Color = Color("7ff0d8").lerp(Color("ff4fd8"), smoothstep(0.55, 1.0, u))
			VoidGlow.halo(_fx, at_orb, tint, 1.1, 1.0)
			_fx.draw_rect(Rect2(at_orb.round() - Vector2.ONE, Vector2(3, 3)), Color("eafff8"))
			_fx.draw_rect(Rect2((Vector2(ground.x, ground.y * SQUASH)).round(), Vector2(2, 1)), Color(0, 0, 0, 0.35)) ## its shadow on the water
		else:
			var age: float = _state_time - (_orb_launch(i) + _orb_fly(i))
			var burst: float = float(spec["burst_seconds"])
			if age > burst:
				continue
			var k: float = age / burst
			var radius: float = float(spec["burst_radius"]) * (0.4 + 0.8 * k)
			for p: int in 22:
				var angle: float = TAU * float(p) / 22.0
				var point: Vector2 = ground + Vector2(cos(angle), sin(angle) * SQUASH) * radius
				_fx.draw_rect(Rect2(point.round(), Vector2.ONE * 2), Color("c9fff0" if p % 3 else "ff4fd8", (1.0 - k) * 0.85))
			_fx.draw_rect(Rect2((ground - Vector2(6, 3)).round(), Vector2(12, 6)), Color("eafff8", (1.0 - k) * 0.35))
