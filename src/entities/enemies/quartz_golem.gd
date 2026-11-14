class_name QuartzGolem
extends CharacterBody2D
## Small arcane sandstone-and-quartz desert guardian ("Quarzwächter") of Sonnenquarz-Öde.
## Spawns day and night exclusively on white ground-quartz outcrops (`BiomeBlend.is_quartz_surface`).
## Peaceful / camouflaged by default; awakens when a player harvests, mines, or breaks anything nearby, or attacks it.

enum State {
	DORMANT,
	PEACEFUL,
	AWAKEN,
	COMBAT,
	BLADE_WINDUP,
	BLADE_SLASH,
	SHARD_WINDUP,
	SHARD_RELEASE,
	SHOCK_WINDUP,
	SHOCK_SLAM,
	RECOVER,
	HURT,
	DEAD,
}

const HURTBOX_MASK: int = 1 << 5
const DEATH_SECONDS: float = 1.05
const ZONE_PAD: float = 3.0
const ERUPT_DURATION: float = 0.62

var enemy_id: String = "quartz_golem"
var health_scale: float = 1.0
var damage_scale: float = 1.0
var emerge_on_spawn: bool = false
var variant: int = 0 ## 0 = Sun-Quartz/Ochre, 1 = Mesa-Terracotta/Amber, 2 = Prisma/Ruin-Stone
var start_dormant: bool = false
var home_pos: Vector2 = Vector2.INF
var night: NightBehavior = null ## always null in natural desert spawns (day & night independent)
var heading: float = PI * 0.5
var state: State = State.PEACEFUL

var attack_dir: Vector2 = Vector2.DOWN
var attack_origin: Vector2 = Vector2.ZERO
var shock_target: Vector2 = Vector2.ZERO
var _shard_lengths: Array[float] = [140.0, 140.0, 140.0]

var _def: Dictionary
var _target: Player
var _known: Vector2 = Vector2.ZERO
var _memory: float = 0.0
var _state_time: float = 0.0
var _previous: State = State.PEACEFUL
var _blade_cd: float = 0.0
var _shard_cd: float = 0.5
var _shock_cd: float = 1.2
var _flinch_cd: float = 0.0
var _aim_left: float = 0.0
var _aim_locked: bool = false
var _fired: bool = false
var _shock_triggered: bool = false
var _struck: Array[int] = []
var _wander_left: float = 1.6
var _wander_dir: Vector2 = Vector2.ZERO
var _peace_cycle_left: float = 8.0
var _orbit: float = 1.0
var _arcane_boost: float = 0.0
var _erupt_pos: Vector2 = Vector2.ZERO
var _erupt_age: float = -1.0
var _dust_motes: Array[Dictionary] = [] ## {pos, vel, life, max_life, col, size}
var _world: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _rig: QuartzGolemRig = $Rig
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _body: CollisionShape2D = $CollisionShape2D
@onready var _navigation: EnemyNavigation = $Navigation
@onready var _zone: Node2D = $Zone
@onready var _ground_fx: Node2D = $GroundFx
@onready var _fx: Node2D = $Fx
@onready var _voice: AudioStreamPlayer2D = $Voice
@onready var _death_fx: CPUParticles2D = $DeathFx


func _ready() -> void:
	add_to_group("quartz_golems")
	add_to_group("desert_arcane_listeners")
	_def = EnemyScaling.scaled(DataRegistry.get_entry("enemies", enemy_id), health_scale, damage_scale)
	_health.max_health = float(_def["max_health"])
	_health.current = _health.max_health
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_rng.seed = hash(name) ^ int(roundi(global_position.x * 13.0 + global_position.y * 37.0))
	_orbit = -1.0 if (_rng.randi() % 2 == 0) else 1.0
	if not home_pos.is_finite():
		home_pos = global_position
	_known = global_position
	_rig.variant = clampi(variant, 0, 2)
	for world_node: Node in get_tree().get_nodes_in_group("world"):
		if world_node.has_method("navigation_floor") or world_node.has_method("spawn_quartz_shard"):
			_world = world_node
			break
	_navigation.configure(self, _body, _def["navigation"], _floor_available)
	_zone.draw.connect(_draw_zone)
	if Interiors.slot_at(global_position) >= 0 or MineManager.in_mine(global_position):
		_zone.z_index = -3
	_ground_fx.draw.connect(_draw_ground_fx)
	_fx.draw.connect(_draw_fx)
	_rig.foot_landed.connect(_on_foot_landed)
	if multiplayer.is_server():
		state = State.DORMANT if start_dormant else State.PEACEFUL
		_peace_cycle_left = _rng.randf_range(6.5, 13.0)
	_sync_predator_group()
	_enter_state()
	if emerge_on_spawn:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.9)
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


func is_provoked() -> bool:
	return state not in [State.DORMANT, State.PEACEFUL, State.DEAD]


func pickaxe_multiplier() -> float:
	return float(_def.get("pickaxe_multiplier", 1.35))


func note_pickaxe_hit(from: Vector2) -> void:
	_spawn_fracture_fx.rpc((global_position - from).normalized())


@rpc("authority", "call_local", "unreliable")
func _spawn_fracture_fx(away: Vector2) -> void:
	var base_dir: Vector2 = away if away != Vector2.ZERO else Vector2.UP
	for i: int in 9:
		var ang: float = base_dir.angle() + randf_range(-0.95, 0.95)
		var spd: float = randf_range(26.0, 68.0)
		_dust_motes.append({
			"pos": global_position + Vector2(randf_range(-4.0, 4.0), randf_range(-18.0, -8.0)),
			"vel": Vector2.from_angle(ang) * spd + Vector2(0.0, randf_range(-28.0, -8.0)),
			"life": 0.42,
			"max_life": 0.42,
			"col": Color("ffffff") if i % 2 == 0 else Color("78f4e6"),
			"size": 2.0 if i % 3 == 0 else 1.0,
		})


func on_arcane_lightning(strike_pos: Vector2, _info: Dictionary = {}) -> void:
	if global_position.distance_to(strike_pos) <= 160.0 and state != State.DEAD:
		_arcane_boost = 6.0


## Host-only entry point called when a player mines, harvests, cuts, or hits a prop/plant near this golem.
func provoke(player: Player, disturbance_pos: Vector2, is_rustle: bool = false, cascade: bool = true) -> void:
	if not multiplayer.is_server() or state == State.DEAD or _health.current <= 0.0:
		return
	if player == null or not is_instance_valid(player) or player.health.current <= 0.0:
		return
	var max_dist: float = float(_def["rustle_provoke_range"] if is_rustle else _def["provoke_range"])
	if global_position.distance_to(disturbance_pos) > max_dist and global_position.distance_to(player.global_position) > max_dist:
		return
	if not _same_floor(global_position, disturbance_pos) and not _same_floor(global_position, player.global_position):
		return
	_target = player
	_known = player.global_position
	_memory = float(_def["memory_seconds"])
	if state in [State.DORMANT, State.PEACEFUL]:
		attack_dir = (_known - global_position).normalized()
		if attack_dir == Vector2.ZERO:
			attack_dir = Vector2.from_angle(heading)
		heading = attack_dir.angle()
		_set_state(State.AWAKEN)
	if cascade:
		var ally_range: float = float(_def.get("wake_ally_range", 130.0))
		for node: Node in get_tree().get_nodes_in_group("quartz_golems"):
			if node == self or not (node is QuartzGolem):
				continue
			var sibling: QuartzGolem = node as QuartzGolem
			if sibling.global_position.distance_to(global_position) <= ally_range:
				sibling.provoke_ally(player)


func provoke_ally(player: Player) -> void:
	if not multiplayer.is_server() or state == State.DEAD or _health.current <= 0.0:
		return
	if player == null or not is_instance_valid(player) or player.health.current <= 0.0:
		return
	if not _same_floor(global_position, player.global_position):
		return
	_target = player
	_known = player.global_position
	_memory = float(_def["memory_seconds"])
	if state in [State.DORMANT, State.PEACEFUL]:
		attack_dir = (_known - global_position).normalized()
		if attack_dir == Vector2.ZERO:
			attack_dir = Vector2.from_angle(heading)
		heading = attack_dir.angle()
		_set_state(State.AWAKEN)


func _sync_predator_group() -> void:
	if is_provoked():
		if not is_in_group("predators"):
			add_to_group("predators")
	else:
		if is_in_group("predators"):
			remove_from_group("predators")


func _weather_resonance() -> float:
	var res: float = clampf(_arcane_boost / 3.0, 0.0, 1.0)
	if WeatherManager.current != null:
		res = maxf(res, clampf(WeatherManager.current.desert_resonance * 0.75 + WeatherManager.current.desert_arcane_storm, 0.0, 1.0))
	return res


func _process(delta: float) -> void:
	_arcane_boost = maxf(0.0, _arcane_boost - delta)
	if _erupt_age >= 0.0:
		_erupt_age += delta
		if _erupt_age >= ERUPT_DURATION:
			_erupt_age = -1.0
	for m: Dictionary in _dust_motes:
		m["life"] = float(m["life"]) - delta
		var v: Vector2 = m["vel"] as Vector2
		v.y += 95.0 * delta
		m["vel"] = v
		m["pos"] = (m["pos"] as Vector2) + v * delta
	if not _dust_motes.is_empty():
		_dust_motes = _dust_motes.filter(func(m: Dictionary) -> bool: return float(m["life"]) > 0.0)

	var attack_pose: bool = state in [
		State.BLADE_WINDUP, State.BLADE_SLASH,
		State.SHARD_WINDUP, State.SHARD_RELEASE,
		State.SHOCK_WINDUP, State.SHOCK_SLAM,
		State.RECOVER,
	]
	_rig.variant = clampi(variant, 0, 2)
	_rig.update_rig(delta, velocity, attack_dir.angle() if attack_pose else heading, is_provoked(), _weather_resonance())
	_zone.queue_redraw()
	_ground_fx.queue_redraw()
	_fx.queue_redraw()


func _physics_process(delta: float) -> void:
	_state_time += delta
	if not multiplayer.is_server() or state == State.DEAD:
		return
	var cd_rate: float = 1.0 + _weather_resonance() * 0.22
	_blade_cd = maxf(0.0, _blade_cd - delta * cd_rate)
	_shard_cd = maxf(0.0, _shard_cd - delta * cd_rate)
	_shock_cd = maxf(0.0, _shock_cd - delta * cd_rate)
	_flinch_cd = maxf(0.0, _flinch_cd - delta)
	_memory = maxf(0.0, _memory - delta)
	if is_provoked():
		_refresh_target()

	match state:
		State.DORMANT:
			velocity = Vector2.ZERO
			_peace_cycle_left -= delta
			if _peace_cycle_left <= 0.0:
				_peace_cycle_left = _rng.randf_range(8.0, 15.0)
				_set_state(State.PEACEFUL)
		State.PEACEFUL:
			_peaceful_wander(delta)
		State.AWAKEN:
			velocity = Vector2.ZERO
			if _memory > 0.0:
				heading = lerp_angle(heading, (_known - global_position).angle(), delta * float(_def["turn_speed"]))
			if _state_time >= float(_def["awaken_seconds"]):
				_set_state(State.COMBAT)
		State.COMBAT:
			_combat(delta)
		State.BLADE_WINDUP:
			_windup_blade(delta)
		State.BLADE_SLASH:
			velocity = Vector2.ZERO
			_blade_hit()
			if _state_time >= float(_def["blade"]["strike"]):
				_set_state(State.RECOVER)
		State.SHARD_WINDUP:
			_windup_shards(delta)
		State.SHARD_RELEASE:
			velocity = Vector2.ZERO
			if not _fired:
				_fired = true
				_launch_shards()
			if _state_time >= float(_def["shards"]["release"]):
				_set_state(State.RECOVER)
		State.SHOCK_WINDUP:
			_windup_shock(delta)
		State.SHOCK_SLAM:
			velocity = Vector2.ZERO
			_shock_hit()
			if _state_time >= float(_def["shock"]["strike"]):
				_set_state(State.RECOVER)
		State.RECOVER:
			velocity = Vector2.ZERO
			if _state_time >= _recovery():
				if _memory > 0.0 and is_instance_valid(_target) and _target.health.current > 0.0:
					_set_state(State.COMBAT)
				else:
					_target = null
					_set_state(State.PEACEFUL)
		State.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, delta * 480.0)
			if _state_time >= float(_def["hurt_stun"]):
				_set_state(State.COMBAT if _memory > 0.0 else State.PEACEFUL)
	move_and_slide()


func _refresh_target() -> void:
	if not is_instance_valid(_target) or _target.health.current <= 0.0:
		_memory = 0.0
		_target = null
		return
	if _target.veiled():
		_memory = minf(_memory, 1.4)
		return
	var dist: float = global_position.distance_to(_target.global_position)
	if dist <= float(_def["lose_range"]) and _same_floor(global_position, _target.global_position):
		_known = _target.global_position
		if _line_clear(global_position, _known) or dist < 95.0:
			_memory = float(_def["memory_seconds"])


func _peaceful_wander(delta: float) -> void:
	_peace_cycle_left -= delta
	if _peace_cycle_left <= 0.0 and global_position.distance_to(home_pos) <= 36.0:
		_peace_cycle_left = _rng.randf_range(9.0, 18.0)
		velocity = Vector2.ZERO
		_set_state(State.DORMANT)
		return
	_wander_left -= delta
	if _wander_left <= 0.0:
		_wander_left = _rng.randf_range(1.8, 3.6)
		if global_position.distance_to(home_pos) > float(_def.get("home_radius", 92.0)) * 0.65:
			_wander_dir = (home_pos - global_position).normalized()
		elif _wander_dir != Vector2.ZERO:
			_wander_dir = Vector2.ZERO
		else:
			var cand: Vector2 = Vector2.from_angle(heading + _rng.randf_range(-1.4, 1.4))
			var probe: Vector2 = global_position + cand * 24.0
			# Prefer staying right on its white ground-quartz patch when in the real world
			if BiomeBlend.is_quartz_surface(global_position) and not BiomeBlend.is_quartz_surface(probe):
				cand = (home_pos - global_position).normalized() if home_pos.distance_to(global_position) > 8.0 else -cand
			_wander_dir = cand
	var dir: Vector2 = _safe_direction(_wander_dir)
	velocity = velocity.move_toward(dir * float(_def["wander_speed"]), delta * 95.0)
	if dir != Vector2.ZERO:
		heading = lerp_angle(heading, dir.angle(), delta * 2.4)


func _combat(delta: float) -> void:
	if _memory <= 0.0 or not is_instance_valid(_target) or _target.health.current <= 0.0:
		_target = null
		_set_state(State.PEACEFUL)
		return
	var toward: Vector2 = _known - global_position
	var distance: float = toward.length()
	var dir: Vector2 = toward.normalized() if distance > 0.01 else Vector2.from_angle(heading)
	heading = lerp_angle(heading, dir.angle(), delta * float(_def["turn_speed"]))
	var same_lvl: bool = _same_floor(global_position, _known)
	var clear: bool = same_lvl and _line_clear(global_position, _known)
	var aligned: bool = absf(angle_difference(heading, dir.angle())) < 0.35

	# Attack 3: Fast close-range Sun-Quartz Crystal Arm-Blade
	if clear and distance <= float(_def["blade"]["trigger_range"]) and _blade_cd <= 0.0:
		_blade_cd = float(_def["blade"]["cooldown"])
		_set_state(State.BLADE_WINDUP)
		return

	# Attack 2: Subterranean Sandstone & Quartz Shock directly beneath Ellie
	var shock_spec: Dictionary = _def["shock"]
	if same_lvl and distance >= float(shock_spec["min_range"]) and distance <= float(shock_spec["max_range"]) and _shock_cd <= 0.0 and aligned:
		_shock_cd = float(shock_spec["cooldown"])
		_set_state(State.SHOCK_WINDUP)
		return

	# Attack 1: 3-Spike Magical Sun-Quartz Volley
	var shard_spec: Dictionary = _def["shards"]
	if clear and distance >= float(shard_spec["min_range"]) and distance <= float(shard_spec["max_range"]) and _shard_cd <= 0.0 and aligned:
		_shard_cd = float(shard_spec["cooldown"])
		_set_state(State.SHARD_WINDUP)
		return

	var speed: float = float(_def["move_speed"])
	var move_dir: Vector2 = dir
	if not clear or not _navigation.segment_clear(global_position, _known):
		move_dir = _navigation.direction_to(_known, delta)
	else:
		_navigation.invalidate()
		# If Crystal Blade is ready and ranged spells are cooling down, dart into melee range!
		if _blade_cd <= 0.0 and _shard_cd > 0.35 and _shock_cd > 0.35 and distance < 92.0:
			move_dir = _safe_direction(dir)
			speed = float(_def["move_speed"]) * 1.12
		elif distance < float(_def["preferred_min"]):
			move_dir = _safe_direction((-dir + dir.orthogonal() * _orbit * 0.4).normalized())
			speed = float(_def["retreat_speed"])
		elif distance <= float(_def["preferred_max"]):
			move_dir = _safe_direction(dir.orthogonal() * _orbit)
			speed = float(_def["strafe_speed"])
		else:
			move_dir = _safe_direction(dir)
	velocity = velocity.move_toward(move_dir * speed, delta * 280.0)


func _shard_dirs(center_dir: Vector2) -> Array[Vector2]:
	var base: Vector2 = center_dir.normalized()
	if base == Vector2.ZERO:
		base = Vector2.DOWN
	var step_rad: float = deg_to_rad(float(_def["shards"]["spread_deg"])) * 0.5
	return [base.rotated(-step_rad), base, base.rotated(step_rad)]


func _recompute_shard_lengths() -> void:
	var shard_spec: Dictionary = _def["shards"]
	var dirs: Array[Vector2] = _shard_dirs(attack_dir)
	_shard_lengths.resize(3)
	for i: int in 3:
		_shard_lengths[i] = QuartzShard.clip_distance(self, attack_origin, dirs[i], float(shard_spec["range"]), float(shard_spec["radius"]))


func _clamp_shock_spot(raw_target: Vector2) -> Vector2:
	var max_r: float = float(_def["shock"]["max_range"])
	var delta_v: Vector2 = raw_target - attack_origin
	var candidate: Vector2 = attack_origin + delta_v.limit_length(max_r)
	if _same_floor(attack_origin, candidate) and _floor_available(candidate):
		return candidate
	for frac: float in [0.75, 0.5, 0.3]:
		var fallback: Vector2 = attack_origin.lerp(candidate, frac)
		if _same_floor(attack_origin, fallback) and _floor_available(fallback):
			return fallback
	return attack_origin + attack_dir * 36.0


func _set_state(next: State) -> void:
	if next in [State.BLADE_WINDUP, State.SHARD_WINDUP, State.SHOCK_WINDUP]:
		attack_origin = global_position
		attack_dir = (_known - global_position).normalized()
		if attack_dir == Vector2.ZERO:
			attack_dir = Vector2.from_angle(heading)
		if next == State.SHARD_WINDUP:
			_recompute_shard_lengths()
		elif next == State.SHOCK_WINDUP:
			shock_target = _clamp_shock_spot(_known)
	if next not in [State.COMBAT, State.PEACEFUL, State.HURT]:
		velocity = Vector2.ZERO
	if next in [State.DORMANT, State.AWAKEN, State.DEAD]:
		_navigation.invalidate()
	_apply_state.rpc(next, attack_dir, attack_origin, shock_target, PackedFloat32Array(_shard_lengths), 0.0, state, variant)


@rpc("authority", "call_local", "reliable")
func _apply_state(next: int, direction: Vector2, origin: Vector2, shock_spot: Vector2, lengths: PackedFloat32Array, elapsed: float, previous: int, golem_variant: int) -> void:
	_previous = previous as State
	state = next as State
	variant = golem_variant
	attack_dir = direction
	attack_origin = origin
	shock_target = shock_spot
	if lengths.size() == 3:
		_shard_lengths = [lengths[0], lengths[1], lengths[2]]
	_state_time = elapsed
	_aim_left = 0.0
	_aim_locked = false
	_fired = false
	_shock_triggered = false
	_struck.clear()
	_sync_predator_group()
	_enter_state()


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server():
		_apply_state.rpc_id(
			multiplayer.get_remote_sender_id(),
			state,
			attack_dir,
			attack_origin,
			shock_target,
			PackedFloat32Array(_shard_lengths),
			_state_time,
			_previous,
			variant
		)


func _windup_blade(delta: float) -> void:
	velocity = Vector2.ZERO
	var spec: Dictionary = _def["blade"]
	_aim_left -= delta
	if _state_time < float(spec["windup"]) - float(spec["aim_lock"]):
		if _memory > 0.0 and _known.distance_squared_to(attack_origin) > 0.01:
			attack_dir = (_known - attack_origin).normalized()
		if _aim_left <= 0.0:
			_aim_left = 0.05
			_update_blade_aim.rpc(attack_dir)
	elif not _aim_locked:
		_aim_locked = true
		_update_blade_aim.rpc(attack_dir)
	heading = attack_dir.angle()
	if _state_time >= float(spec["windup"]):
		_set_state(State.BLADE_SLASH)


func _windup_shards(delta: float) -> void:
	velocity = Vector2.ZERO
	var spec: Dictionary = _def["shards"]
	_aim_left -= delta
	if _state_time < float(spec["windup"]) - float(spec["aim_lock"]):
		if _memory > 0.0 and _known.distance_squared_to(attack_origin) > 0.01:
			attack_dir = (_known - attack_origin).normalized()
		if _aim_left <= 0.0:
			_aim_left = 0.05
			_recompute_shard_lengths()
			_update_shard_aim.rpc(attack_dir, PackedFloat32Array(_shard_lengths))
	elif not _aim_locked:
		_aim_locked = true
		_recompute_shard_lengths()
		_update_shard_aim.rpc(attack_dir, PackedFloat32Array(_shard_lengths))
	heading = attack_dir.angle()
	if _state_time >= float(spec["windup"]):
		_set_state(State.SHARD_RELEASE)


func _windup_shock(delta: float) -> void:
	velocity = Vector2.ZERO
	var spec: Dictionary = _def["shock"]
	_aim_left -= delta
	if _state_time < float(spec["windup"]) - float(spec["aim_lock"]):
		if _memory > 0.0:
			shock_target = _clamp_shock_spot(_known)
			if shock_target.distance_squared_to(attack_origin) > 0.01:
				attack_dir = (shock_target - attack_origin).normalized()
		if _aim_left <= 0.0:
			_aim_left = 0.05
			_update_shock_aim.rpc(attack_dir, shock_target)
	elif not _aim_locked:
		_aim_locked = true
		_update_shock_aim.rpc(attack_dir, shock_target)
	heading = attack_dir.angle()
	if _state_time >= float(spec["windup"]):
		_set_state(State.SHOCK_SLAM)


@rpc("authority", "call_remote", "reliable")
func _update_blade_aim(dir: Vector2) -> void:
	if state == State.BLADE_WINDUP:
		attack_dir = dir


@rpc("authority", "call_remote", "reliable")
func _update_shard_aim(dir: Vector2, lengths: PackedFloat32Array) -> void:
	if state == State.SHARD_WINDUP:
		attack_dir = dir
		if lengths.size() == 3:
			_shard_lengths = [lengths[0], lengths[1], lengths[2]]


@rpc("authority", "call_remote", "reliable")
func _update_shock_aim(dir: Vector2, spot: Vector2) -> void:
	if state == State.SHOCK_WINDUP:
		attack_dir = dir
		shock_target = spot


func _blade_hit() -> void:
	var spec: Dictionary = _def["blade"]
	if _state_time < 0.02:
		return
	var reach: float = float(spec["reach"]) * clampf(_state_time / float(spec["hit_time"]), 0.0, 1.0)
	for target: HurtboxComponent in HitScan.fan(self, attack_origin + Vector2(0.0, -12.0), attack_dir, reach, deg_to_rad(float(spec["arc"])), HURTBOX_MASK):
		if not _struck.has(target.get_instance_id()) and _same_floor(attack_origin, target.global_position) and _line_clear(attack_origin, target.global_position):
			_struck.append(target.get_instance_id())
			target.take_hit(float(spec["damage"]), attack_origin + Vector2(0.0, -12.0), float(spec["knockback"]))


func _launch_shards() -> void:
	if is_instance_valid(_world) and _world.has_method("spawn_quartz_shard"):
		var dirs: Array[Vector2] = _shard_dirs(attack_dir)
		for i: int in 3:
			_world.call("spawn_quartz_shard", attack_origin, dirs[i], _rig.shard_launch_point(i), variant, damage_scale)
	get_tree().call_group("desert_spell_listeners", "on_spell_cast", attack_origin, attack_origin + attack_dir * 72.0, "quartz_shards")


func _shock_hit() -> void:
	var spec: Dictionary = _def["shock"]
	if _shock_triggered or _state_time < float(spec["hit_time"]):
		return
	_shock_triggered = true
	_present_shock_eruption.rpc(shock_target)
	for target: HurtboxComponent in HitScan.circle(self, shock_target + Vector2(0.0, -12.0), float(spec["radius"]), HURTBOX_MASK):
		if not _struck.has(target.get_instance_id()) and _same_floor(shock_target, target.global_position):
			_struck.append(target.get_instance_id())
			target.take_hit(float(spec["damage"]), shock_target + Vector2(0.0, -12.0), float(spec["knockback"]))
	get_tree().call_group("desert_spell_listeners", "on_spell_cast", attack_origin, shock_target, "sandstone_shock")


@rpc("authority", "call_local", "reliable")
func _present_shock_eruption(spot: Vector2) -> void:
	_erupt_pos = spot
	_erupt_age = 0.0
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			var shake: float = 2.6 * (1.0 - smoothstep(24.0, 150.0, player.global_position.distance_to(spot)))
			if shake > 0.05:
				player.add_shake(shake)
	for i: int in 14:
		var ang: float = float(i) / 14.0 * TAU + randf_range(-0.2, 0.2)
		var spd: float = randf_range(22.0, 62.0)
		_dust_motes.append({
			"pos": spot + Vector2.from_angle(ang) * randf_range(3.0, 16.0) + Vector2(0.0, -4.0),
			"vel": Vector2.from_angle(ang) * spd + Vector2(0.0, randf_range(-44.0, -14.0)),
			"life": 0.52,
			"max_life": 0.52,
			"col": Color("f2cf88") if i % 2 == 0 else Color("dceaf8"),
			"size": 2.0 if i % 3 == 0 else 1.0,
		})


func _recovery() -> float:
	match _previous:
		State.BLADE_SLASH:
			return float(_def["blade"]["recover"])
		State.SHOCK_SLAM:
			return float(_def["shock"]["recover"])
		_:
			return float(_def["shards"]["recover"])


func _enter_state() -> void:
	var pose: QuartzGolemRig.Pose = QuartzGolemRig.Pose.PEACEFUL
	var duration: float = 1.0
	var cue: String = ""
	match state:
		State.DORMANT:
			pose = QuartzGolemRig.Pose.DORMANT
		State.PEACEFUL:
			pose = QuartzGolemRig.Pose.PEACEFUL
		State.AWAKEN:
			pose = QuartzGolemRig.Pose.AWAKEN
			duration = float(_def["awaken_seconds"])
			cue = "awaken"
		State.COMBAT:
			pose = QuartzGolemRig.Pose.MOVE
		State.BLADE_WINDUP:
			pose = QuartzGolemRig.Pose.BLADE_WINDUP
			duration = float(_def["blade"]["windup"])
			cue = "charge"
		State.BLADE_SLASH:
			pose = QuartzGolemRig.Pose.BLADE_SLASH
			duration = float(_def["blade"]["strike"])
			cue = "blade_slash"
		State.SHARD_WINDUP:
			pose = QuartzGolemRig.Pose.SHARD_WINDUP
			duration = float(_def["shards"]["windup"])
			cue = "charge"
		State.SHARD_RELEASE:
			pose = QuartzGolemRig.Pose.SHARD_RELEASE
			duration = float(_def["shards"]["release"])
			cue = "shard_cast"
		State.SHOCK_WINDUP:
			pose = QuartzGolemRig.Pose.SHOCK_WINDUP
			duration = float(_def["shock"]["windup"])
			cue = "charge"
		State.SHOCK_SLAM:
			pose = QuartzGolemRig.Pose.SHOCK_SLAM
			duration = float(_def["shock"]["strike"])
			cue = "shock_erupt"
		State.RECOVER:
			pose = QuartzGolemRig.Pose.RECOVER
			duration = _recovery()
		State.HURT:
			pose = QuartzGolemRig.Pose.HURT
			duration = float(_def["hurt_stun"])
		State.DEAD:
			pose = QuartzGolemRig.Pose.DEAD
			duration = DEATH_SECONDS
			cue = "death"
	_rig.start_pose(pose, duration, _state_time)
	if not cue.is_empty() and DisplayServer.get_name() != "headless":
		_voice.stop()
		var audio_map: Dictionary = _def.get("audio", {}) as Dictionary
		if audio_map.has(cue):
			_voice.stream = load(String(audio_map[cue])) as AudioStream
			_voice.volume_db = float(audio_map.get("volume_db", -7.0))
			_voice.pitch_scale = 0.95 + float(posmod(hash(name), 9)) * 0.012
			if _voice.stream != null and _state_time < _voice.stream.get_length():
				_voice.play(_state_time)
	elif state == State.HURT:
		_voice.stop()


func _on_foot_landed(world_pt: Vector2) -> void:
	for i: int in 3:
		_dust_motes.append({
			"pos": world_pt + Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0)),
			"vel": Vector2(randf_range(-10.0, 10.0), randf_range(-14.0, -5.0)),
			"life": 0.28,
			"max_life": 0.28,
			"col": Color("dceaf8") if BiomeBlend.is_quartz_surface(world_pt) else Color("f2cf88"),
			"size": 1.0,
		})


func _zone_rune_px(pt: Vector2, col: Color, shadow_alpha: float) -> void:
	var p: Vector2 = pt.round()
	if shadow_alpha > 0.01:
		_zone.draw_rect(Rect2(p + Vector2(0.0, 1.0), Vector2.ONE), Color("4a061c", shadow_alpha))
		_zone.draw_rect(Rect2(p + Vector2(1.0, 0.0), Vector2.ONE), Color("4a061c", shadow_alpha * 0.55))
	_zone.draw_rect(Rect2(p, Vector2.ONE), col)


func _zone_rune_line(a: Vector2, b: Vector2, col: Color, shadow_alpha: float, step_px: float = 1.5) -> void:
	var dist: float = a.distance_to(b)
	var steps: int = maxi(1, roundi(dist / maxf(step_px, 1.0)))
	if shadow_alpha > 0.01:
		for i: int in range(steps + 1):
			var ps: Vector2 = a.lerp(b, float(i) / float(steps)).round()
			_zone.draw_rect(Rect2(ps + Vector2(0.0, 1.0), Vector2.ONE), Color("4a061c", shadow_alpha))
	for i: int in range(steps + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(steps)).round()
		_zone.draw_rect(Rect2(p, Vector2.ONE), col)


func _zone_diamond(center: Vector2, rad: float, angle: float, col: Color, shadow_alpha: float) -> void:
	var pts: Array[Vector2] = []
	for i: int in 4:
		var a: float = angle + float(i) * PI * 0.5
		pts.append(center + Vector2(cos(a) * rad, sin(a) * rad * 0.82))
	for i: int in 4:
		_zone_rune_line(pts[i], pts[(i + 1) % 4], col, shadow_alpha, 1.5)


func _draw_zone() -> void:
	# 1) CRYSTAL_BLADE — Arcane Crescent Rune Cleave Fan
	if state in [State.BLADE_WINDUP, State.BLADE_SLASH]:
		var bspec: Dictionary = _def["blade"]
		var locked_b: bool = state == State.BLADE_SLASH or _state_time >= float(bspec["windup"]) - float(bspec["aim_lock"])
		var strength_b: float = 0.84 + (0.16 * sin(_state_time * 38.0) if locked_b else 0.0)
		if state == State.BLADE_SLASH:
			strength_b = 1.0 - clampf(_state_time / float(bspec["strike"]), 0.0, 1.0)
		var orig_b: Vector2 = attack_origin - global_position
		var reach_b: float = float(bspec["reach"]) + ZONE_PAD
		var arc_rad: float = deg_to_rad(float(bspec["arc"]))
		var shadow_a_b: float = 0.58 * strength_b
		var rim_col_b: Color = Color("ffe0e8" if (locked_b or state == State.BLADE_SLASH) else "ff2e5f", 0.96 * strength_b)
		var sub_col_b: Color = Color("e01b4c", 0.85 * strength_b)

		# Rich ruby-crimson magical shimmer inside the cleave fan + sweeping slash waves
		for i: int in 460:
			var u: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
			var v: float = fposmod(sin(float(i) * 78.233 + 3.1) * 19642.349, 1.0)
			var dist: float = sqrt(u) * (reach_b - 1.5)
			if dist < 6.0:
				continue
			var ang_off: float = (v - 0.5) * arc_rad
			var pt: Vector2 = attack_dir.rotated(ang_off) * dist
			var sweep_wave: float = 0.5 + 0.5 * sin(ang_off * 5.0 - _state_time * (22.0 if locked_b else 11.0) + dist * 0.16)
			if sweep_wave < 0.42:
				continue
			var p_int: Vector2 = (orig_b + pt).round()
			_zone.draw_rect(Rect2(p_int + Vector2(0.0, 1.0), Vector2.ONE), Color("45061a", strength_b * 0.36))
			var col_b: Color = Color("b81438").lerp(Color("ffd6e0") if state == State.BLADE_SLASH else Color("ff3b6b"), sweep_wave)
			_zone.draw_rect(Rect2(p_int, Vector2.ONE), Color(col_b, strength_b * (0.44 + sweep_wave * 0.42)))

		# Left & right radial rune-spoke borders
		var edge_l: Vector2 = attack_dir.rotated(-arc_rad * 0.5)
		var edge_r: Vector2 = attack_dir.rotated(arc_rad * 0.5)
		_zone_rune_line(orig_b + edge_l * 6.0, orig_b + edge_l * reach_b, rim_col_b, shadow_a_b, 1.8)
		_zone_rune_line(orig_b + edge_r * 6.0, orig_b + edge_r * reach_b, rim_col_b, shadow_a_b, 1.8)

		# Inner harmonic rune arc + double outer crescent rim with arcane rune teeth!
		var arc_steps: int = 38
		for s_i: int in range(arc_steps + 1):
			var frac: float = float(s_i) / float(arc_steps) - 0.5
			var dir_s: Vector2 = attack_dir.rotated(frac * arc_rad)
			_zone_rune_px(orig_b + dir_s * (reach_b * 0.56), sub_col_b, shadow_a_b * 0.65)
			_zone_rune_px(orig_b + dir_s * (reach_b - 3.0), sub_col_b, shadow_a_b * 0.75)
			_zone_rune_px(orig_b + dir_s * reach_b, rim_col_b, shadow_a_b)
			if s_i % 6 == 0:
				# Arcane rune tooth jutting outward along the crescent rim
				_zone_rune_line(orig_b + dir_s * (reach_b - 3.0), orig_b + dir_s * (reach_b + 3.0), Color("ffe6ec", 0.95 * strength_b), shadow_a_b, 1.2)

		# 3 inscribed diamond rune sigils inside the cleave arc
		for d_idx: int in [-1, 0, 1]:
			var sig_dir: Vector2 = attack_dir.rotated(float(d_idx) * arc_rad * 0.28)
			_zone_diamond(orig_b + sig_dir * (reach_b * 0.78), 3.5, _state_time * 3.0 + float(d_idx), Color("ffd6e0", 0.92 * strength_b), shadow_a_b * 0.8)
		return

	# 2) SHARD_VOLLEY — 3 Magical Arcane Rune Corridors + Chevrons + Reticles
	if state == State.SHARD_WINDUP or (state == State.SHARD_RELEASE and _state_time < 0.14):
		var sspec: Dictionary = _def["shards"]
		var locked_s: bool = state == State.SHARD_RELEASE or _state_time >= float(sspec["windup"]) - float(sspec["aim_lock"])
		var strength_s: float = 0.84 + (0.16 * sin(_state_time * 36.0) if locked_s else 0.0)
		if state == State.SHARD_RELEASE:
			strength_s = (1.0 - _state_time / 0.14) * 0.95
		var orig_s: Vector2 = attack_origin - global_position
		var dirs: Array[Vector2] = _shard_dirs(attack_dir)
		var half_band: float = float(sspec["radius"]) + ZONE_PAD
		var shadow_a_s: float = 0.56 * strength_s
		var rail_col: Color = Color("ffe0e8" if locked_s else "ff2e5f", 0.95 * strength_s)
		var chev_col: Color = Color("ffd8e2", 0.95 * strength_s)

		# Caster rune arc in front of the golem's feet
		for c_i: int in 19:
			var c_frac: float = float(c_i) / 18.0 - 0.5
			var c_dir: Vector2 = attack_dir.rotated(c_frac * 1.25)
			_zone_rune_px(orig_s + c_dir * 11.0, rail_col, shadow_a_s)

		# Clean outer boundary rails of the 3-shard fan (no cluttered overlapping inner box rails!)
		var d_left: Vector2 = dirs[0]
		var d_right: Vector2 = dirs[2]
		var left_n: Vector2 = -d_left.orthogonal()
		var right_n: Vector2 = d_right.orthogonal()
		_zone_rune_line(orig_s + d_left * 11.0 + left_n * half_band, orig_s + d_left * (_shard_lengths[0] + half_band) + left_n * half_band, Color("ff3b6b", 0.86 * strength_s), shadow_a_s, 1.8)
		_zone_rune_line(orig_s + d_right * 11.0 + right_n * half_band, orig_s + d_right * (_shard_lengths[2] + half_band) + right_n * half_band, Color("ff3b6b", 0.86 * strength_s), shadow_a_s, 1.8)

		for k: int in 3:
			var d_k: Vector2 = dirs[k]
			var across_k: Vector2 = d_k.orthogonal()
			var len_k: float = _shard_lengths[k] + half_band
			# Luminous crimson-rose shimmer inside corridor
			for i: int in 130:
				var u: float = fposmod(sin(float(i + k * 311) * 12.9898) * 43758.5453, 1.0)
				var v: float = fposmod(sin(float(i + k * 197) * 78.233 + 1.7) * 19642.349, 1.0)
				var dist_k: float = 11.0 + u * maxf(4.0, len_k - 13.0)
				var pt_k: Vector2 = d_k * dist_k + across_k * (v - 0.5) * (half_band * 1.7)
				var wave_k: float = 0.5 + 0.5 * sin(dist_k * 0.24 - _state_time * (22.0 if locked_s else 11.0))
				if wave_k < 0.52:
					continue
				var pk: Vector2 = (orig_s + pt_k).round()
				_zone.draw_rect(Rect2(pk, Vector2.ONE), Color(Color("d91b49").lerp(Color("ff5c86"), wave_k), strength_s * (0.36 + wave_k * 0.36)))

			# Sleek central arcane ley-beam line down each shard trajectory!
			_zone_rune_line(orig_s + d_k * 11.0, orig_s + d_k * len_k, rail_col, shadow_a_s, 2.0)

			# Animated arcane rune chevrons (`>>>`) racing forward down each lane!
			var scroll: float = fposmod(_state_time * (52.0 if locked_s else 28.0), 20.0)
			var d_chev: float = 15.0 + scroll
			while d_chev < len_k - 7.0:
				var tip: Vector2 = orig_s + d_k * d_chev
				var wing_l: Vector2 = tip - d_k * 4.5 + across_k * (half_band * 0.62)
				var wing_r: Vector2 = tip - d_k * 4.5 - across_k * (half_band * 0.62)
				_zone_rune_line(wing_l, tip, chev_col, shadow_a_s * 0.85, 1.2)
				_zone_rune_line(wing_r, tip, chev_col, shadow_a_s * 0.85, 1.2)
				d_chev += 20.0

			# Spinning crimson-white diamond rune reticle at the focus/end of each lane
			_zone_diamond(orig_s + d_k * len_k, 4.2, _state_time * 3.2 + float(k), chev_col, shadow_a_s)
		return

	# 3) SANDSTONE_SHOCK — Subterranean Ley-Fissure + Inscribed Rotating Arcane Danger Seal!
	if state in [State.SHOCK_WINDUP, State.SHOCK_SLAM]:
		var kspec: Dictionary = _def["shock"]
		var locked_k: bool = state == State.SHOCK_SLAM or _state_time >= float(kspec["windup"]) - float(kspec["aim_lock"])
		var strength_k: float = 0.86 + (0.14 * sin(_state_time * 40.0) if locked_k else 0.0)
		if state == State.SHOCK_SLAM:
			strength_k = 1.0 - clampf(_state_time / float(kspec["strike"]), 0.0, 1.0)
		var center_k: Vector2 = shock_target - global_position
		var from_k: Vector2 = attack_origin - global_position
		var rad_k: float = float(kspec["radius"]) + ZONE_PAD
		var shadow_a_k: float = 0.60 * strength_k
		var seal_bright: Color = Color("ffe2ea" if (locked_k or state == State.SHOCK_SLAM) else "ff2e5f", 0.96 * strength_k)
		var seal_mid: Color = Color("e01b4c", 0.88 * strength_k)

		# Subterranean crackling crimson-amber arcane ley-fissure from golem to shock_target
		var seam_progress: float = clampf(_state_time / maxf(float(kspec["windup"]) * 0.65, 0.1), 0.0, 1.0) if state == State.SHOCK_WINDUP else 1.0
		var seam_dir: Vector2 = (center_k - from_k).normalized()
		var seam_perp: Vector2 = seam_dir.orthogonal()
		var seam_steps: int = maxi(6, roundi(from_k.distance_to(center_k) * seam_progress / 3.0))
		var prev_sp: Vector2 = from_k
		for s: int in range(1, seam_steps + 1):
			var f_s: float = float(s) / float(maxi(1, seam_steps)) * seam_progress
			var zig: float = sin(float(s) * 1.9 + _state_time * 16.0) * 2.4
			var sp: Vector2 = from_k.lerp(center_k, f_s) + seam_perp * zig
			_zone_rune_line(prev_sp, sp, Color("ff5c78" if s % 2 == 0 else "ffb36b", 0.88 * strength_k), shadow_a_k * 0.75, 1.6)
			if s % 4 == 0:
				var branch: Vector2 = sp + (seam_perp * (4.0 if s % 8 == 0 else -4.0) + seam_dir * 2.0)
				_zone_rune_line(sp, branch, Color("ff2e5f", 0.72 * strength_k), shadow_a_k * 0.5, 1.5)
			prev_sp = sp

		# Rich ruby-crimson pulsing floor wash inside the seal circle
		for i: int in 360:
			var u: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
			var v: float = fposmod(sin(float(i) * 78.233 + 5.3) * 19642.349, 1.0)
			var r_here: float = sqrt(u) * (rad_k - 2.0)
			var ang: float = v * TAU
			var pt_c: Vector2 = Vector2.from_angle(ang) * r_here
			var wave_c: float = 0.5 + 0.5 * sin(r_here * 0.34 - _state_time * (22.0 if locked_k else 11.0) + ang * 2.0)
			if wave_c < 0.46:
				continue
			var pc: Vector2 = (center_k + pt_c).round()
			_zone.draw_rect(Rect2(pc + Vector2(0.0, 1.0), Vector2.ONE), Color("45061a", strength_k * 0.35))
			_zone.draw_rect(Rect2(pc, Vector2.ONE), Color(Color("b81438").lerp(Color("ff4a6e"), wave_c), strength_k * (0.40 + wave_c * 0.38)))

		# Double outer Arcane Seal Circle + 8 rotating exterior rune teeth!
		var ring_steps: int = 56
		for r_idx: int in ring_steps:
			var ang_r: float = float(r_idx) / float(ring_steps) * TAU
			var dir_r: Vector2 = Vector2.from_angle(ang_r)
			_zone_rune_px(center_k + dir_r * (rad_k - 3.5), seal_mid, shadow_a_k * 0.7)
			_zone_rune_px(center_k + dir_r * rad_k, seal_bright, shadow_a_k)
		for tooth_i: int in 8:
			var t_ang: float = float(tooth_i) / 8.0 * TAU + _state_time * 1.15
			var t_dir: Vector2 = Vector2.from_angle(t_ang)
			_zone_rune_line(center_k + t_dir * (rad_k - 3.0), center_k + t_dir * (rad_k + 3.2), Color("ffe6ec", 0.95 * strength_k), shadow_a_k, 1.2)

		# Inscribed counter-rotating Arcane Octagram (two interlocking rune squares) inside the circle!
		var sq_r: float = rad_k * 0.68
		for sq_idx: int in 2:
			var base_rot: float = _state_time * (1.3 if sq_idx == 0 else -1.3) + float(sq_idx) * (PI * 0.25)
			var verts: Array[Vector2] = []
			for vi: int in 4:
				verts.append(center_k + Vector2.from_angle(base_rot + float(vi) * PI * 0.5) * sq_r)
			for vi: int in 4:
				_zone_rune_line(verts[vi], verts[(vi + 1) % 4], Color("ff5c82" if sq_idx == 0 else "ffd0dc", 0.82 * strength_k), shadow_a_k * 0.55, 2.2)

		# Shrinking crimson countdown ring tightening to the center eruption point!
		if state == State.SHOCK_WINDUP:
			var count_t: float = clampf(_state_time / maxf(float(kspec["windup"]), 0.05), 0.0, 1.0)
			var count_r: float = lerpf(rad_k - 1.0, 3.0, count_t)
			var c_steps: int = maxi(14, roundi(count_r * 1.8))
			for ci: int in c_steps:
				var c_ang: float = float(ci) / float(c_steps) * TAU
				_zone_rune_px(center_k + Vector2.from_angle(c_ang) * count_r, Color("ffe8ee", 0.94 * strength_k), shadow_a_k * 0.7)

		# Center diamond target sigil
		_zone_diamond(center_k, 4.5, -_state_time * 2.5, Color("ffffff", 0.92 * strength_k), shadow_a_k)


func _draw_ground_fx() -> void:
	# Lit sandstone slabs, glowing arcane ground seal & rune-veined Sun-Quartz spires erupting at `_erupt_pos`
	if _erupt_age >= 0.0:
		var t: float = clampf(_erupt_age / ERUPT_DURATION, 0.0, 1.0)
		var rise: float = smoothstep(0.0, 0.16, t) * (1.0 - smoothstep(0.55, 1.0, t))
		var fade: float = 1.0 - smoothstep(0.65, 1.0, t)
		var center: Vector2 = (_erupt_pos - global_position).round()
		# Glowing turquoise-amber cracked arcane seal ring on the desert floor
		for r_i: int in 28:
			var r_ang: float = float(r_i) / 28.0 * TAU
			var rp: Vector2 = (center + Vector2(cos(r_ang) * 20.0, sin(r_ang) * 14.0)).round()
			_ground_fx.draw_rect(Rect2(rp - Vector2.ONE, Vector2(3, 3)), Color("2b191d", 0.72 * fade))
			_ground_fx.draw_rect(Rect2(rp, Vector2.ONE), Color("78f4e6" if r_i % 2 == 0 else "ffe488", 0.92 * fade))
		# Cracked sandstone ring on the sand
		for i: int in 8:
			var ang: float = float(i) / 8.0 * TAU + 0.2
			var slab_p: Vector2 = (center + Vector2(cos(ang) * 15.0, sin(ang) * 10.5)).round()
			_ground_fx.draw_rect(Rect2(slab_p - Vector2(3, 2), Vector2(6, 4)), Color("2b191d", 0.85 * fade))
			_ground_fx.draw_rect(Rect2(slab_p - Vector2(2, 1), Vector2(4, 2)), Color("d8a35c" if i % 2 == 0 else "9e6844", fade))
		# 5 jagged rune-veined Sun-Quartz spires thrusting upward out of the shock crater
		var offsets: Array[Vector2] = [
			Vector2(-11.0, -2.0),
			Vector2(11.0, -1.0),
			Vector2(-5.0, 4.0),
			Vector2(6.0, 5.0),
			Vector2(0.0, 1.0),
		]
		var heights: Array[float] = [14.0, 13.0, 16.0, 15.0, 21.0]
		var tilts: Array[Vector2] = [
			Vector2(-0.32, -0.95),
			Vector2(0.34, -0.94),
			Vector2(-0.18, -0.98),
			Vector2(0.20, -0.98),
			Vector2(0.0, -1.0),
		]
		for k: int in 5:
			var spire_len: float = heights[k] * rise
			if spire_len < 2.0:
				continue
			var vein_c: Color = Color("ffe488" if k == 4 else "78f4e6", 0.95 * fade)
			_rig._draw_quartz_crystal(_ground_fx, center + offsets[k], tilts[k], spire_len, 3.0 if k == 4 else 2.3, _rig._palette(), 0.0, vein_c)

	for m: Dictionary in _dust_motes:
		var a: float = clampf(float(m["life"]) / float(m["max_life"]), 0.0, 1.0)
		var mp: Vector2 = ((m["pos"] as Vector2) - global_position).round()
		var sz: float = float(m["size"])
		_ground_fx.draw_rect(Rect2(mp, Vector2.ONE * sz), Color(m["col"] as Color, a))


func _draw_fx() -> void:
	# 1) Additive luminous shockwave ring, upward arcane light pillars & star-glints on Sandstone Shock eruption
	if _erupt_age >= 0.0 and _erupt_age < 0.46:
		var p: float = _erupt_age / 0.46
		var center: Vector2 = (_erupt_pos - global_position).round()
		var r: float = lerpf(6.0, 29.0, p)
		var alpha: float = (1.0 - p) * 0.62
		for i: int in 24:
			var ang: float = float(i) / 24.0 * TAU + p * 1.4
			var pt: Vector2 = (center + Vector2(cos(ang) * r, sin(ang) * r * 0.72)).round()
			_fx.draw_rect(Rect2(pt - Vector2.ONE, Vector2(3, 3)), Color("78f4e6" if i % 2 == 0 else "ffe488", alpha * 0.65))
			_fx.draw_rect(Rect2(pt, Vector2.ONE), Color("ffffff", alpha * 0.9))
		# Vertical arcane light pillars shooting out of the shock seal
		var pillar_a: float = (1.0 - smoothstep(0.15, 0.95, p)) * 0.52
		var pillar_xs: Array[float] = [-10.0, 0.0, 10.0]
		var pillar_hs: Array[float] = [20.0, 30.0, 19.0]
		for pk: int in 3:
			var px: float = center.x + pillar_xs[pk]
			var ph: float = pillar_hs[pk] * smoothstep(0.0, 0.25, p)
			_fx.draw_rect(Rect2(Vector2(px - 2.0, center.y - ph).round(), Vector2(4.0, ph)), Color("78f4e6", pillar_a * 0.45))
			_fx.draw_rect(Rect2(Vector2(px - 1.0, center.y - ph).round(), Vector2(2.0, ph)), Color("ffe488" if pk == 1 else "d0fff8", pillar_a * 0.85))

	# 2) Sweeping turquoise-gold-white Arcane Crescent Sword-Wave during CRYSTAL_BLADE!
	var slash_t: float = -1.0
	if state == State.BLADE_SLASH:
		slash_t = clampf(_state_time / maxf(float(_def["blade"]["strike"]), 0.05), 0.0, 1.0) * 0.65
	elif state == State.RECOVER and _previous == State.BLADE_SLASH and _state_time < 0.20:
		slash_t = 0.65 + (_state_time / 0.20) * 0.35
	if slash_t >= 0.0:
		var orig_fx: Vector2 = (attack_origin - global_position) + Vector2(0.0, -10.0)
		var arc_rad_fx: float = deg_to_rad(float(_def["blade"]["arc"]))
		var reach_fx: float = float(_def["blade"]["reach"])
		var fade_fx: float = 1.0 - smoothstep(0.45, 1.0, slash_t)
		for s_i: int in 28:
			var frac_s: float = float(s_i) / 27.0
			if frac_s > clampf(slash_t * 1.75, 0.15, 1.0):
				continue
			var ang_s: float = attack_dir.angle() + lerpf(-arc_rad_fx * 0.5, arc_rad_fx * 0.5, frac_s)
			var dir_s: Vector2 = Vector2(cos(ang_s), sin(ang_s) * 0.85)
			var outer_p: Vector2 = (orig_fx + dir_s * reach_fx).round()
			var inner_p: Vector2 = (orig_fx + dir_s * (reach_fx - 7.0)).round()
			_fx.draw_rect(Rect2(outer_p - Vector2.ONE, Vector2(3, 3)), Color("78f4e6", fade_fx * 0.52))
			_fx.draw_rect(Rect2(outer_p, Vector2(2, 2)), Color("ffffff", fade_fx * 0.85))
			_fx.draw_rect(Rect2(inner_p, Vector2(2, 2)), Color("ffe488", fade_fx * 0.55))
			if s_i % 5 == 0:
				# 4-point star sparkle floating in the sword wake
				var star_p: Vector2 = (orig_fx + dir_s * (reach_fx - 3.0)).round()
				_fx.draw_rect(Rect2(star_p + Vector2(-2, 0), Vector2(5, 1)), Color("d0fff8", fade_fx * 0.85))
				_fx.draw_rect(Rect2(star_p + Vector2(0, -2), Vector2(1, 5)), Color("d0fff8", fade_fx * 0.85))


func _floor_available(point: Vector2) -> bool:
	if is_instance_valid(_world) and _world.has_method("navigation_floor"):
		return bool(_world.call("navigation_floor", point))
	return Terrain.relief == null or Terrain.relief.is_land(floori(point.x / 16.0), floori(point.y / 16.0))


func _same_floor(from: Vector2, to: Vector2) -> bool:
	return Terrain.relief == null or absf(Terrain.relief.level_at(from) - Terrain.relief.level_at(to)) < 0.45


func _line_clear(from: Vector2, to: Vector2) -> bool:
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from + Vector2(0.0, -4.0), to + Vector2(0.0, -4.0), 1)
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func _safe_direction(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return direction
	for turn: float in [0.0, 0.5 * _orbit, -0.5 * _orbit, 1.0 * _orbit, -1.0 * _orbit, 1.55 * _orbit]:
		var dir: Vector2 = direction.rotated(turn)
		if _navigation.segment_clear(global_position, global_position + dir * 22.0) and not test_move(global_transform, dir * 18.0):
			return dir
	return Vector2.ZERO


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	_rig.hit_flash()
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0.0, -36.0), amount, (global_position - from).normalized())
	if not multiplayer.is_server() or _health.current <= 0.0 or state == State.DEAD:
		return
	var attacker_player: Player = null
	for player: Player in Player.all:
		if player.name.to_int() == _health.last_attacker and not player.veiled():
			attacker_player = player
			_target = player
			_known = player.global_position
			_memory = float(_def["memory_seconds"])
			break
	if state in [State.DORMANT, State.PEACEFUL]:
		if attacker_player != null:
			provoke(attacker_player, global_position, false, true)
		else:
			_memory = float(_def["memory_seconds"])
			_set_state(State.AWAKEN)
		return
	var in_release: bool = state in [State.BLADE_SLASH, State.SHARD_RELEASE, State.SHOCK_SLAM]
	var committed: bool = state in [State.BLADE_WINDUP, State.SHARD_WINDUP, State.SHOCK_WINDUP, State.AWAKEN]
	if not in_release and (knockback >= float(_def["heavy_knockback"]) or (not committed and _flinch_cd <= 0.0)):
		_flinch_cd = float(_def["flinch_cooldown"])
		velocity = (global_position - from).normalized() * knockback * float(_def["knockback_resistance"])
		_set_state(State.HURT)


func _on_died() -> void:
	if multiplayer.is_server():
		_set_state(State.DEAD)
	_sync_predator_group()
	_hurtbox.set_deferred("collision_layer", 0)
	_body.set_deferred("disabled", true)
	_death_fx.restart()
	if multiplayer.is_server():
		await get_tree().create_timer(DEATH_SECONDS + 0.25).timeout
		if is_inside_tree():
			queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_voice):
		_voice.stop()
		_voice.stream = null
