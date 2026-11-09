class_name ShadowSpider
extends CharacterBody2D
## Host-owned void predator: observe, stalk, anchor-and-surge, then commit to a readable attack.
## Reliable state packets carry the entire attack frame atomically; local rigs own cosmetic motion.

enum State { IDLE, CHASE, WINDUP, STRIKE, RECOVER, HURT, DEAD, GRAPPLE_WINDUP, GRAPPLE_THROW, GRAPPLE_PULL, NOTICE, CLIMB_WINDUP, CLIMB, CLIMB_RETREAT, EMERGE }

const ZONE_PAD: float = 3.0
const PLAYER_HURTBOX_MASK: int = 1 << 5
const DEATH_SECONDS: float = 1.0
const ZONE_DARK: Color = Color("c21f3b")
const ZONE_HOT: Color = Color("ff4a63")
const ZONE_FLASH: Color = Color("ffd0d6")

@export var enemy_id: String = "shadow_spider"
@export var emerge_on_spawn: bool = false
var health_scale: float = 1.0 ## set by the spawner before it enters the tree (replicated on spawn): the mine makes its enemies tougher with depth
var damage_scale: float = 1.0
var night: NightBehavior = null ## host only: set by the NightDirector for creatures of the night (patrol, light, raids); null for all others
var _birth: ShadowBirth

var heading: float = PI / 2.0
var anchor: Vector2 = Vector2.ZERO
var state: State = State.IDLE
var attack_dir: Vector2 = Vector2.DOWN
var attack_origin: Vector2 = Vector2.ZERO
var attack_side: float = 1.0

var _def: Dictionary = {}
var _previous_state: State = State.IDLE
var _target: Player
var _state_time: float = 0.0
var _state_msec: int = 0
var _search_timer: float = 0.0
var _wander_timer: float = 1.0
var _wander_dir: Vector2 = Vector2.ZERO
var _hunt_clock: float = 0.0
var _orbit_side: float = 1.0
var _grapple_cd: float = 1.4
var _flinch_left: float = 0.0
var _hit_scored: bool = false
var _aim_sync_left: float = 0.0
var _aim_locked: bool = false
var _strike_progress: float = 0.0
var _struck: Array[int] = []
var _climb_cd: float = 0.0
var _climb_retry: float = 0.0
var _climb_safe_origin: Vector2
var _climb_walls: Array[PhysicsBody2D] = []
var _world: Node
var _home: Vector2 ## guard spiders (`post` in enemies.json) stay where they were put
var _post_heading: float = 0.0

@onready var _rig: SpiderRig = $Rig
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _death_fx: CPUParticles2D = $DeathFx
@onready var _zone: Node2D = $Zone
@onready var _trail: ShadowTrailComponent = $ShadowTrail
@onready var _navigation: EnemyNavigation = $Navigation


func _ready() -> void:
	add_to_group("predators")
	_def = EnemyScaling.scaled(DataRegistry.get_entry("enemies", enemy_id), health_scale, damage_scale)
	_home = global_position
	_post_heading = heading
	_health.max_health = float(_def["max_health"])
	_health.current = _health.max_health
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_rig.strike_reach = float(_def["reach"])
	_rig.strike_arc = deg_to_rad(float(_def["arc"]))
	_rig.strike_hit_fraction = float(_def["strike_hit_time"]) / float(_def["strike"])
	_zone.draw.connect(_draw_zone)
	if Interiors.slot_at(global_position) >= 0 or MineManager.in_mine(global_position):
		_zone.z_index = -3 ## inside a room: above the floor sprite (z -6), below the furniture, so the attack warning shows
	_rig.foot_landed.connect(func(point: Vector2) -> void: _trail.leave(point))
	_orbit_side = 1.0 if hash(name) % 2 == 0 else -1.0
	for world: Node in get_tree().get_nodes_in_group("world"):
		if world.has_method("navigation_floor"):
			_world = world
			break
	_navigation.configure(self, _body_shape, _def["navigation"], _navigation_floor, _climb_link)
	if emerge_on_spawn:
		state = State.EMERGE
	_enter_state()
	if state == State.EMERGE:
		_begin_emergence()
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


func _process(delta: float) -> void:
	_rig.emergence = clampf(_state_time / ShadowBirth.DURATION, 0.0, 1.0) if state == State.EMERGE else 1.0
	_rig.set_aim(attack_dir if state in [State.WINDUP, State.STRIKE, State.GRAPPLE_WINDUP, State.GRAPPLE_THROW, State.GRAPPLE_PULL, State.RECOVER, State.CLIMB_WINDUP, State.CLIMB, State.CLIMB_RETREAT] else Vector2.from_angle(heading))
	_rig.set_anchor(anchor)
	_rig.attack_side = attack_side
	_rig.update_rig(delta, velocity, heading)
	_zone.queue_redraw()


func _physics_process(delta: float) -> void:
	_state_time += delta
	if not multiplayer.is_server() or state == State.DEAD:
		return
	if state == State.EMERGE:
		velocity = Vector2.ZERO
		if _state_time >= ShadowBirth.DURATION:
			_set_state(State.IDLE)
		return
	_grapple_cd = maxf(0.0, _grapple_cd - delta)
	_climb_cd = maxf(0.0, _climb_cd - delta)
	_climb_retry = maxf(0.0, _climb_retry - delta)
	_flinch_left = maxf(0.0, _flinch_left - delta)
	_aim_sync_left -= delta
	match state:
		State.IDLE:
			_idle(delta)
		State.NOTICE:
			velocity = Vector2.ZERO
			if _target_valid():
				heading = lerp_angle(heading, (_target.global_position - global_position).angle(), 4.0 * delta)
			if _state_time >= float(_def["notice_seconds"]):
				_set_state(State.CHASE if _target_valid() else State.IDLE)
		State.CHASE:
			_chase(delta)
		State.WINDUP, State.GRAPPLE_WINDUP:
			_windup()
		State.STRIKE:
			if not _hit_scored:
				_strike()
			if _state_time >= float(_def["strike"]):
				_set_state(State.RECOVER)
		State.GRAPPLE_THROW:
			if _state_time >= float(_grapple()["throw"]):
				_grapple_hit()
				_set_state(State.GRAPPLE_PULL)
		State.GRAPPLE_PULL:
			_grapple_pull(delta)
		State.CLIMB_WINDUP:
			velocity = Vector2.ZERO
			if _state_time >= float(_def["climb"]["windup"]):
				_set_state(State.CLIMB if _can_climb(global_position, anchor, true) else State.RECOVER)
		State.CLIMB, State.CLIMB_RETREAT:
			_climb_move(delta)
			return
		State.RECOVER:
			velocity = Vector2.ZERO
			if _state_time >= _recover_time():
				_set_state(State.CHASE if _target_valid() else State.IDLE)
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 500.0 * delta)
			if _state_time >= float(_def["hurt_stun"]):
				_set_state(State.CHASE if _target_valid() else State.IDLE)
	if night != null:
		velocity = night.limit(self, velocity, delta)
	move_and_slide()
	if state == State.GRAPPLE_PULL and get_slide_collision_count() > 0:
		_set_state(State.RECOVER)


func _set_state(new_state: State) -> void:
	if new_state == State.CHASE:
		_hunt_clock = 0.0
	if new_state in [State.CHASE, State.IDLE, State.DEAD]:
		_navigation.invalidate()
	if new_state in [State.WINDUP, State.GRAPPLE_WINDUP]:
		attack_origin = global_position
		attack_dir = (_target.global_position - global_position).normalized()
		attack_side *= -1.0
		anchor = _grapple_anchor() if new_state == State.GRAPPLE_WINDUP else global_position
	if new_state not in [State.CHASE, State.IDLE, State.HURT]:
		velocity = Vector2.ZERO
	_apply_state.rpc(new_state, attack_dir, anchor, attack_origin, attack_side, 0.0, state)


@rpc("authority", "call_local", "reliable")
func _apply_state(next: int, direction: Vector2, point: Vector2, origin: Vector2, side: float, elapsed: float, previous: int) -> void:
	_previous_state = previous as State
	attack_dir = direction
	anchor = point
	attack_origin = origin
	attack_side = side
	state = next as State
	_state_time = elapsed
	_state_msec = Time.get_ticks_msec() - int(elapsed * 1000.0)
	_hit_scored = false
	_aim_locked = false
	_aim_sync_left = 0.0
	_strike_progress = 0.0
	_struck.clear()
	_enter_state()
	if state == State.EMERGE:
		_begin_emergence()
	elif is_instance_valid(_birth):
		_hurtbox.set_deferred("monitorable", state != State.DEAD)
		_body_shape.set_deferred("disabled", state == State.DEAD)
		# A late join receives the live AI state; don't replay a birth under a running enemy.
		if _state_time > 0.0 and _previous_state != State.EMERGE:
			_birth.queue_free()


func _begin_emergence() -> void:
	if not is_instance_valid(_birth):
		_birth = ShadowBirth.new()
		add_child(_birth)
		_rig.emergence_seed = _birth._seed
	_birth.age = _state_time
	_rig.emergence = clampf(_state_time / ShadowBirth.DURATION,0.0,1.0)
	_hurtbox.set_deferred("monitorable", false)
	_body_shape.set_deferred("disabled", true)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server():
		_apply_state.rpc_id(multiplayer.get_remote_sender_id(), state, attack_dir, anchor, attack_origin, attack_side, _state_time, _previous_state)


func _idle(delta: float) -> void:
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = 0.2
		_target = _find_target()
		if _target != null:
			_set_state(State.NOTICE)
			return
	if night != null and night.goal.is_finite(): ## a creature of the night walks its patrol goal
		var way: Vector2 = _steer(night.walk_dir(self, _navigation, delta))
		velocity = velocity.move_toward(way * float(_def["wander_speed"]) * night.speed_factor(), 140.0 * delta)
		if way != Vector2.ZERO:
			heading = lerp_angle(heading, way.angle(), float(_def["turn_speed"]) * 0.5 * delta)
		return
	if bool(_def.get("post", false)): ## a guard: it shifts a little where it stands, turns its head and sways, and goes back to its post
		var t: float = Time.get_ticks_msec() * 0.001 + float(absi(hash(name)) % 100)
		heading = lerp_angle(heading, _post_heading + sin(t * 0.7) * 0.4, 2.0 * delta)
		var pull: Vector2 = _home - global_position
		var sway: Vector2 = Vector2.from_angle(_post_heading + PI / 2.0) * sin(t * 0.9) * 7.0 + Vector2.from_angle(_post_heading) * sin(t * 1.7) * 2.5
		velocity = velocity.move_toward((sway + pull * 2.5).limit_length(40.0 if pull.length() > 20.0 else 11.0), 90.0 * delta)
		return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_dir = Vector2.from_angle(randf() * TAU) if _wander_dir == Vector2.ZERO else Vector2.ZERO
		_wander_timer = randf_range(1.0, 2.6)
	var direction: Vector2 = _steer(_wander_dir)
	velocity = velocity.move_toward(direction * float(_def["wander_speed"]), 120.0 * delta)
	if direction != Vector2.ZERO:
		heading = lerp_angle(heading, direction.angle(), float(_def["turn_speed"]) * 0.5 * delta)


func _chase(delta: float) -> void:
	if not _target_valid():
		_target = null
		_set_state(State.IDLE)
		return
	var toward: Vector2 = _target.global_position - global_position
	var distance: float = toward.length()
	var clear: bool = _same_floor(global_position, _target.global_position) and _clear_path(global_position, _target.global_position)
	heading = lerp_angle(heading, toward.angle(), float(_def["turn_speed"]) * delta)
	_hunt_clock += delta
	var stalk: float = float(_def["stalk_seconds"])
	if clear and distance <= float(_def["attack_range"]):
		_set_state(State.WINDUP)
		return
	if clear and _grapple_cd <= 0.0 and _hunt_clock >= stalk and distance >= float(_grapple()["min_range"]) and distance <= float(_grapple()["max_range"]):
		_grapple_cd = float(_grapple()["cooldown"])
		_set_state(State.GRAPPLE_WINDUP)
		return
	if not _navigation.segment_clear(global_position, _target.global_position):
		var route: Vector2 = _navigation.direction_to(_target.global_position, delta)
		if _navigation.climb_target.is_finite():
			_prepare_climb(_navigation.climb_target)
			return
		if route != Vector2.ZERO:
			heading = lerp_angle(heading, route.angle(), float(_def["turn_speed"]) * delta)
		velocity = velocity.move_toward(route * float(_def["chase_speed"]) * 0.8, 650.0 * delta)
		return
	elif _navigation.searching or not _navigation.path.is_empty():
		_navigation.invalidate()
	var speed: float = float(_def["stalk_speed"])
	var direction: Vector2 = toward.normalized()
	if _hunt_clock < stalk:
		direction = (direction * 0.45 + direction.orthogonal() * _orbit_side * 0.8).normalized()
	else:
		var phase: float = fposmod(_hunt_clock - stalk, float(_def["surge_seconds"]) + float(_def["settle_seconds"]))
		if phase < float(_def["surge_seconds"]):
			speed = float(_def["chase_speed"])
		else:
			speed = float(_def["settle_speed"])
		if distance < float(_def["orbit_distance"]):
			direction = (direction + direction.orthogonal() * _orbit_side * float(_def["orbit_weight"])).normalized()
	velocity = velocity.move_toward(_steer(direction) * speed, 650.0 * delta)


## Short obstacle feelers; attack paths additionally require a clear world ray.
func _steer(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return direction
	for angle: float in [0.0, 0.55 * _orbit_side, -0.55 * _orbit_side, 1.1 * _orbit_side, -1.1 * _orbit_side, 1.55 * _orbit_side]:
		var candidate: Vector2 = direction.rotated(angle)
		if not test_move(global_transform, candidate * 24.0):
			return candidate
	return Vector2.ZERO


func _clear_path(from: Vector2, to: Vector2) -> bool:
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from + Vector2(0, -4), to + Vector2(0, -4), 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _navigation_floor(point: Vector2) -> bool:
	if is_instance_valid(_world):
		return bool(_world.call("navigation_floor", point))
	return Terrain.relief == null or Terrain.relief.is_land(floori(point.x / Relief.TILE), floori(point.y / Relief.TILE))


func _height_at(point: Vector2) -> float:
	return Terrain.relief.level_at(point) if Terrain.relief != null else 0.0


func _same_floor(from: Vector2, to: Vector2) -> bool:
	return absf(_height_at(from) - _height_at(to)) < 0.45


func _cliff_rids() -> Array[RID]:
	var out: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("relief_walls"):
		if node is PhysicsBody2D:
			out.append((node as PhysicsBody2D).get_rid())
	return out


func _sees_over_cliff(point: Vector2) -> bool:
	if _same_floor(global_position, point):
		return false
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -4), point + Vector2(0, -4), 1)
	ray.exclude = _cliff_rids()
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


## A special A* edge, only across real relief collision. Trees, buildings and the
## void never become climbable merely because movement happens to be blocked.
func _climb_link(from: Vector2, step: Vector2) -> Vector2:
	if Terrain.relief == null or _climb_cd > 0.0:
		return Vector2.INF
	var probe: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from + _body_shape.position, from + _body_shape.position + step.normalized() * (step.length() + 6.0), 1)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(probe)
	var collider: Node = hit.get("collider") as Node
	if collider == null or not collider.is_in_group("relief_walls"):
		return Vector2.INF
	var count: int = floori(float(_def["climb"]["max_span"]) / step.length())
	for i: int in range(2, count + 1):
		var to: Vector2 = from + step * i
		if _navigation.can_occupy(to - step.normalized() * 10.0) and _can_climb(from, to):
			return to
	return Vector2.INF


func _can_climb(from: Vector2, to: Vector2, include_players: bool = false) -> bool:
	if Terrain.relief == null or from.distance_to(to) > float(_def["climb"]["max_span"]) + 0.01:
		return false
	var height_from: float = _height_at(from)
	var height_to: float = _height_at(to)
	var change: float = absf(height_to - height_from)
	if change < 0.9 or change > float(_def["climb"]["max_levels"]) + 0.05:
		return false
	if absf(height_from - roundf(height_from)) > 0.05 or absf(height_to - roundf(height_to)) > 0.05:
		return false
	if not _navigation.can_occupy(from) or not _navigation.can_occupy(to, [], 3 if include_players else 1):
		return false
	# A real cliff must intersect this route. Excluding its separate bodies must
	# then leave a clear corridor; props, players and void collision remain solid.
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from + _body_shape.position, to + _body_shape.position, 1)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(ray)
	var collider: Node = hit.get("collider") as Node
	if collider == null or not collider.is_in_group("relief_walls"):
		return false
	var samples: int = maxi(2, ceili(from.distance_to(to) / 4.0))
	for i: int in range(samples + 1):
		var point: Vector2 = from.lerp(to, float(i) / samples)
		var height: float = _height_at(point)
		if not _navigation_floor(point) or height < minf(height_from, height_to) - 0.05 or height > maxf(height_from, height_to) + 0.05:
			return false
	return _navigation.segment_clear(from, to, _cliff_rids(), 3 if include_players else 1)


func _prepare_climb(point: Vector2) -> void:
	if _climb_cd > 0.0 or not _can_climb(global_position, point, true):
		_navigation.invalidate()
		velocity = Vector2.ZERO
		return
	attack_origin = global_position
	anchor = point
	attack_dir = (point - global_position).normalized()
	heading = attack_dir.angle()
	_climb_cd = float(_def["climb"]["cooldown"])
	_navigation.invalidate()
	_set_state(State.CLIMB_WINDUP)


func _climb_duration() -> float:
	return maxf(float(_def["climb"]["min_duration"]), attack_origin.distance_to(anchor) / float(_def["climb"]["speed"]))


func _set_climb_exceptions(active: bool) -> void:
	if active:
		for node: Node in get_tree().get_nodes_in_group("relief_walls"):
			var wall: PhysicsBody2D = node as PhysicsBody2D
			if wall != null and not _climb_walls.has(wall):
				add_collision_exception_with(wall)
				_climb_walls.append(wall)
	else:
		for wall: PhysicsBody2D in _climb_walls:
			if is_instance_valid(wall):
				remove_collision_exception_with(wall)
		_climb_walls.clear()


func _begin_climb_retreat() -> void:
	# A moving player or a newly placed prop can occupy the landing. Pull back
	# along the traversed corridor to safe ground instead of snapping through it.
	var end: Vector2 = _climb_safe_origin
	var found: bool = false
	_climb_retry = 0.3
	for radius: float in [0.0, 12.0, 24.0]:
		for sector: int in 8:
			var candidate: Vector2 = _climb_safe_origin + Vector2.from_angle(sector * PI / 4.0) * radius
			if _same_floor(candidate, _climb_safe_origin) and _navigation.can_occupy(candidate, [], 3) and _navigation.segment_clear(global_position, candidate, _cliff_rids(), 3):
				end = candidate
				found = true
				break
		if found:
			break
	if not found:
		return
	_apply_state.rpc(State.CLIMB_RETREAT, (end - global_position).normalized(), end, global_position, attack_side, 0.0, state)


func _climb_move(delta: float) -> void:
	if not _navigation.can_occupy(anchor, [], 3):
		_state_time -= delta
		velocity = Vector2.ZERO
		if _climb_retry <= 0.0:
			_begin_climb_retreat()
		return
	var t: float = clampf(_state_time / _climb_duration(), 0.0, 1.0)
	var point: Vector2 = attack_origin.lerp(anchor, smoothstep(0.0, 1.0, t))
	var before: Vector2 = global_position
	var hit: KinematicCollision2D = move_and_collide(point - global_position)
	velocity = (global_position - before) / maxf(delta, 0.001)
	if hit != null:
		_state_time -= delta
		velocity = Vector2.ZERO
		if _climb_retry <= 0.0:
			_begin_climb_retreat()
	elif t >= 1.0:
		_set_state(State.RECOVER)


func _exit_tree() -> void:
	_set_climb_exceptions(false)


func _windup() -> void:
	var grapple: bool = state == State.GRAPPLE_WINDUP
	var duration: float = float(_grapple()["windup"] if grapple else _def["windup"])
	if _state_time < duration - float(_def["aim_lock_seconds"]):
		if _target_valid():
			attack_dir = (_target.global_position - attack_origin).normalized()
			if grapple:
				anchor = _grapple_anchor()
		if _aim_sync_left <= 0.0:
			_aim_sync_left = 0.05
			_update_aim.rpc(attack_dir, anchor)
	elif not _aim_locked:
		_aim_locked = true
		_update_aim.rpc(attack_dir, anchor)
	heading = attack_dir.angle()
	if _state_time >= duration:
		_set_state(State.GRAPPLE_THROW if grapple else State.STRIKE)


@rpc("authority", "call_remote", "reliable")
func _update_aim(direction: Vector2, point: Vector2) -> void:
	# Shares the state packet's reliable channel: the final locked aim arrives before the strike.
	if state in [State.WINDUP, State.GRAPPLE_WINDUP]:
		attack_dir = direction
		anchor = point


func _recover_time() -> float:
	if _previous_state in [State.CLIMB, State.CLIMB_RETREAT, State.CLIMB_WINDUP]:
		return float(_def["climb"]["recover"])
	return float(_grapple()["recover"]) if _previous_state == State.GRAPPLE_PULL else float(_def["recover"])


func _grapple() -> Dictionary:
	return _def.get("grapple", {})


func _grapple_anchor() -> Vector2:
	var reach: float = minf(global_position.distance_to(_target.global_position), float(_grapple()["hit_range"]))
	var point: Vector2 = attack_origin + attack_dir * reach
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(attack_origin + Vector2(0, -4), point + Vector2(0, -4), 1)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(ray)
	return (hit["position"] as Vector2) - Vector2(0, -4) - attack_dir * 8.0 if not hit.is_empty() else point


func _grapple_hit() -> bool:
	var landed: bool = false
	for target: HurtboxComponent in HitScan.circle(self, anchor + Vector2(0, -12), float(_grapple()["radius"]), PLAYER_HURTBOX_MASK):
		if _same_floor(attack_origin, target.global_position) and _clear_path(attack_origin, target.global_position):
			target.take_hit(float(_grapple()["damage"]), attack_origin + Vector2(0, -10), -float(_grapple()["pull"]))
			landed = true
	return landed


func _grapple_pull(delta: float) -> void:
	var toward: Vector2 = anchor - global_position
	if toward.length() <= float(_grapple()["stop"]) or _state_time >= 0.65:
		_set_state(State.RECOVER)
		return
	velocity = velocity.move_toward(toward.normalized() * float(_grapple()["pull_speed"]), 2200.0 * delta)


func _strike() -> void:
	var hit_time: float = float(_def["strike_hit_time"])
	var progress: float = smoothstep(hit_time * 0.35, hit_time, _state_time)
	if progress <= _strike_progress:
		return
	var arc: float = deg_to_rad(float(_def["arc"]))
	var start_angle: float = lerpf(attack_side * arc * 0.5, -attack_side * arc * 0.5, _strike_progress)
	var end_angle: float = lerpf(attack_side * arc * 0.5, -attack_side * arc * 0.5, progress)
	var direction: Vector2 = attack_dir.rotated((start_angle + end_angle) * 0.5)
	var origin: Vector2 = attack_origin + Vector2(0, -10)
	for target: HurtboxComponent in HitScan.fan(self, origin, direction, float(_def["reach"]), absf(end_angle - start_angle), PLAYER_HURTBOX_MASK):
		if not _struck.has(target.get_instance_id()) and _same_floor(attack_origin, target.global_position) and _clear_path(attack_origin, target.global_position):
			_struck.append(target.get_instance_id())
			target.take_hit(float(_def["damage"]), origin, float(_def["knockback"]))
	_strike_progress = progress
	_hit_scored = progress >= 1.0


func _target_valid() -> bool:
	return is_instance_valid(_target) and _target.health.current > 0.0 and global_position.distance_to(_target.global_position) <= float(_def["lose_range"]) * _target.stealth.detection_multiplier()


func _find_target() -> Player:
	var best: Player = null
	var nearest: float = INF
	for player: Player in Player.all:
		if player.health.current <= 0.0:
			continue
		var distance: float = global_position.distance_to(player.global_position)
		if distance < nearest and distance <= float(_def["sight_range"]) * player.stealth.detection_multiplier() * player.stealth.alarm_scale() and (_clear_path(global_position, player.global_position) or _sees_over_cliff(player.global_position)):
			best = player
			nearest = distance
	return best


## Red pixels suddenly well up on the ground where the strike will land and flow outward:
## sparse while the spider still aims, dense and fast once the direction is locked, a last surge
## at the strike. No outline: the field just fades out at its edges.
func _draw_zone() -> void:
	match state:
		State.WINDUP, State.STRIKE:
			_zone_fan()
		State.GRAPPLE_WINDUP, State.GRAPPLE_THROW:
			_zone_line()


## Same red pixel flow along the path of the grapple: a band to the anchor and a disc where it lands.
func _zone_line() -> void:
	var grapple: Dictionary = _grapple()
	var elapsed: float = (Time.get_ticks_msec() - _state_msec) / 1000.0
	var density: float = 0.38
	var strength: float = 0.75
	var flow: float = 7.0
	var color_hot: Color = ZONE_HOT
	if state == State.GRAPPLE_WINDUP:
		if elapsed >= float(grapple["windup"]) - float(_def["aim_lock_seconds"]):
			density = 0.6
			strength = 1.0 * (0.8 + 0.2 * signf(sin(elapsed * 40.0)))
			flow = 13.0
	else:
		density = 0.9
		strength = 1.0 - clampf(elapsed / float(grapple["throw"]), 0.0, 1.0)
		flow = 26.0
		color_hot = ZONE_FLASH
	var end: Vector2 = anchor - global_position
	var length: float = end.length()
	if length < 4.0:
		return
	var dir: Vector2 = end / length
	var half_width: float = 2.0
	var radius: float = float(grapple["radius"]) + ZONE_PAD
	var low: Vector2 = Vector2(minf(0.0, end.x), minf(0.0, end.y)) - Vector2(radius, radius)
	var high: Vector2 = Vector2(maxf(0.0, end.x), maxf(0.0, end.y)) + Vector2(radius, radius)
	for y: int in range(floori(low.y), ceili(high.y) + 1):
		for x: int in range(floori(low.x), ceili(high.x) + 1):
			var point: Vector2 = Vector2(x, y)
			var along: float = clampf(point.dot(dir), 0.0, length)
			var line_distance: float = point.distance_to(dir * along)
			var anchor_distance: float = point.distance_to(end)
			var in_circle: bool = anchor_distance <= radius
			var in_line: bool = line_distance <= half_width and along > 6.0
			if not in_circle and not in_line:
				continue
			var h: float = fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
			if h > density * (1.6 if in_circle else 0.7):
				continue
			var wave: float = 0.5 + 0.5 * sin(along * 0.3 - elapsed * flow + h * TAU)
			var edge: float = 0.0
			if in_circle:
				edge = 1.0 - smoothstep(radius * 0.7, radius, anchor_distance)
			if in_line:
				edge = maxf(edge, (1.0 - smoothstep(half_width * 0.5, half_width, line_distance)) * smoothstep(6.0, 14.0, along) * 0.22)
			var alpha: float = strength * (0.4 + 0.6 * wave) * edge * 0.9
			if alpha > 0.04:
				_zone.draw_rect(Rect2(point, Vector2.ONE), Color(ZONE_DARK.lerp(color_hot, wave), alpha))


func _zone_fan() -> void:
	var elapsed: float = (Time.get_ticks_msec() - _state_msec) / 1000.0
	var density: float = 0.38
	var strength: float = 0.75
	var flow: float = 7.0
	var color_hot: Color = ZONE_HOT
	if state == State.WINDUP:
		if elapsed >= float(_def["windup"]) - float(_def["aim_lock_seconds"]): ## direction locked: it will land here
			density = 0.6
			strength = 1.0 * (0.8 + 0.2 * signf(sin(elapsed * 40.0)))
			flow = 13.0
	else:
		var fade: float = 1.0 - clampf(elapsed / float(_def["strike"]), 0.0, 1.0)
		density = 0.9
		strength = 1.0 * fade
		flow = 26.0
		color_hot = ZONE_FLASH
	var reach: float = float(_def["reach"]) + ZONE_PAD
	var half_arc: float = deg_to_rad(float(_def["arc"])) / 2.0
	var origin: Vector2 = attack_origin - global_position + Vector2(0, 2) ## where a hit player's feet would be, matching the hit fan
	var span: int = ceili(reach)
	for y: int in range(-span, span + 1):
		for x: int in range(-span, span + 1):
			var offset: Vector2 = Vector2(x, y)
			var distance: float = offset.length()
			if distance < 3.0 or distance > reach:
				continue
			var off_axis: float = absf(angle_difference(attack_dir.angle(), offset.angle()))
			if off_axis > half_arc:
				continue
			var h: float = fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
			if h > density:
				continue
			var wave: float = 0.5 + 0.5 * sin(distance * 0.3 - elapsed * flow + h * TAU) ## ripples travelling outward
			var edge: float = minf(smoothstep(3.0, 9.0, distance), 1.0 - smoothstep(reach - 7.0, reach, distance))
			edge *= 1.0 - smoothstep(half_arc * 0.7, half_arc, off_axis)
			var alpha: float = strength * (0.4 + 0.6 * wave) * edge * 0.9
			if alpha > 0.04:
				var color: Color = ZONE_DARK.lerp(color_hot, wave)
				_zone.draw_rect(Rect2(origin + offset, Vector2.ONE), Color(color, alpha))
				if wave > 0.55: ## a faint tail toward the spider makes the outward flow readable
					_zone.draw_rect(Rect2(origin + (offset - offset / distance * 1.5).round(), Vector2.ONE), Color(color, alpha * 0.5))


func _enter_state() -> void:
	_set_climb_exceptions(state in [State.CLIMB, State.CLIMB_RETREAT])
	var pose: SpiderRig.Pose = SpiderRig.Pose.LOCOMOTION
	var duration: float = 1.0
	match state:
		State.NOTICE:
			pose = SpiderRig.Pose.OBSERVE
			duration = float(_def["notice_seconds"])
		State.WINDUP:
			pose = SpiderRig.Pose.WINDUP
			duration = float(_def["windup"])
		State.STRIKE:
			pose = SpiderRig.Pose.STRIKE
			duration = float(_def["strike"])
		State.RECOVER:
			pose = SpiderRig.Pose.RECOVER
			duration = _recover_time()
		State.GRAPPLE_WINDUP:
			pose = SpiderRig.Pose.COIL
			duration = float(_grapple()["windup"])
		State.GRAPPLE_THROW:
			pose = SpiderRig.Pose.THROW
			duration = float(_grapple()["throw"])
		State.GRAPPLE_PULL:
			pose = SpiderRig.Pose.PULL
		State.CLIMB_WINDUP:
			pose = SpiderRig.Pose.CLIMB_REACH
			duration = float(_def["climb"]["windup"])
		State.CLIMB, State.CLIMB_RETREAT:
			pose = SpiderRig.Pose.CLIMB
			duration = _climb_duration()
			if state == State.CLIMB:
				_climb_safe_origin = attack_origin
		State.DEAD:
			pose = SpiderRig.Pose.DEAD
			duration = DEATH_SECONDS
	_rig.attack_side = attack_side
	if state in [State.CLIMB_WINDUP, State.CLIMB, State.CLIMB_RETREAT]:
		_rig.set_climb(attack_origin, anchor, _height_at(anchor) > _height_at(attack_origin))
	_rig.start_pose(pose, duration, _state_time)
	if state == State.GRAPPLE_PULL:
		var across: Vector2 = attack_dir.orthogonal() * 8.0
		_trail.leave(anchor + across, true)
		_trail.leave(anchor - across, true)


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	_rig.hit_flash()
	var away: Vector2 = (global_position - from).normalized()
	if amount < 5000.0: ## a story kill is no number
		DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -28), amount, away)
	if not multiplayer.is_server() or _health.current <= 0.0 or state in [State.DEAD, State.STRIKE, State.GRAPPLE_THROW, State.GRAPPLE_PULL, State.CLIMB, State.CLIMB_RETREAT]:
		return
	var heavy: bool = knockback >= float(_def["heavy_knockback"])
	var committed: bool = state in [State.WINDUP, State.GRAPPLE_WINDUP, State.RECOVER]
	if heavy or (not committed and _flinch_left <= 0.0):
		_flinch_left = float(_def["flinch_cooldown"])
		velocity = away * knockback * float(_def["knockback_resistance"])
		_set_state(State.HURT)


## Story: something cuts it down in one blow (host only).
func cut_down(from: Vector2) -> void:
	if multiplayer.is_server():
		_health.take_damage(_health.current, from, 240.0)


func _on_died() -> void:
	if multiplayer.is_server():
		_set_state(State.DEAD)
	_hurtbox.set_deferred("collision_layer", 0)
	_body_shape.set_deferred("disabled", true)
	_death_fx.restart()
	_trail.infest(global_position)
	if multiplayer.is_server():
		await get_tree().create_timer(DEATH_SECONDS + 0.3).timeout
		if is_inside_tree():
			queue_free()
