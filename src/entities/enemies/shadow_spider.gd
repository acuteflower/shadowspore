class_name ShadowSpider
extends CharacterBody2D
## Shadowspore 2.0 — Reference V2 Void-Mycelium Arachnid Predator (`T1`..`T7`, `V1`..`V7`).
## Host-authoritative ENet controller with atomic state RPCs and peer-local 8-legged `SpiderRig` + `EnemyWorldBridge`.
## Combines 3-channel perception (`EnemySenseComponent`: 8-eye cone + substrate biotremor + "Ellie = Shadowspore" kinship hesitation),
## ecological ambushes (`CREVICE_CROUCH`, `CANOPY_DROP`, `MYCELIUM_TETHER`), 4 combat maneuvers (`SCYTHE_SLASH`,
## `SILK_GRAPPLE` w/ breakable `webbed` silk, `SILK_BACKSTEP`, `VENOM_LUNGE`), directional Opisthosoma weakpoint &
## `EXPOSED` knockdown (`EnemyPostureComponent`), and pack flanking/token coordination (`CombatCoordinator`).

enum State {
	IDLE,
	CHASE,
	WINDUP,
	STRIKE,
	RECOVER,
	HURT,
	DEAD,
	GRAPPLE_WINDUP,
	GRAPPLE_THROW,
	GRAPPLE_PULL,
	NOTICE,
	CLIMB_WINDUP,
	CLIMB,
	CLIMB_RETREAT,
	EMERGE,
	HESITATE,
	INVESTIGATE,
	SILK_BACKSTEP,
	VENOM_WINDUP,
	VENOM_LUNGE,
	EXPOSED,
	PACK_RECOIL,
	CANOPY_WAIT,
	CANOPY_DROP,
	FINISHED_IMPALED
}

enum AmbushKind { NONE = 0, CREVICE_CROUCH = 1, CANOPY_DROP = 2, MYCELIUM_TETHER = 3 }

const ZONE_PAD: float = 3.0
const PLAYER_HURTBOX_MASK: int = 1 << 5
const DEATH_SECONDS: float = 1.05
const ZONE_DARK: Color = Color("c21f3b")
const ZONE_HOT: Color = Color("ff4a63")
const ZONE_FLASH: Color = Color("ffd0d6")

@export var enemy_id: String = "shadow_spider"
@export var emerge_on_spawn: bool = false
@export var brood_variant: int = 0 ## 0 = Common (1.0x), 1 = Scout (0.88x, fast), 2 = Thorn Elder (1.14x, barbed + venom)
@export var ambush_mode: int = AmbushKind.NONE

var health_scale: float = 1.0
var damage_scale: float = 1.0
var night: NightBehavior = null
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
var _venom_cd: float = 2.0
var _backstep_cd: float = 0.0
var _flinch_left: float = 0.0
var _hit_scored: bool = false
var _slash_grass_done: bool = false
var _aim_sync_left: float = 0.0
var _aim_locked: bool = false
var _strike_progress: float = 0.0
var _struck: Array[int] = []
var _venom_landed: bool = false
var _recent_front_hits: int = 0
var _front_hit_window: float = 0.0
var _variant_speed_mult: float = 1.0
var _climb_cd: float = 0.0
var _climb_retry: float = 0.0
var _climb_safe_origin: Vector2
var _climb_walls: Array[PhysicsBody2D] = []
var _world: Node
var _home: Vector2
var _post_heading: float = 0.0
var _zone_active: bool = false
var _phase_slot: int = 0
var _steer_dir: Vector2 = Vector2.ZERO
var _steer_in: Vector2 = Vector2.ZERO
var _steer_ttl: int = 0
var _chase_clear: bool = false
var _chase_nav_clear: bool = false
var _chase_next_check: int = -1
var _chase_last_pos: Vector2 = Vector2(INF, INF)
var _tether: MyceliumTether = null
var finisher_ready_kind: int = 0 ## Finisher V2 (docs/finisher_v2_konzept.md): 0 = no, 1 = the next sword blow is lethal and finishes, 2 = EXPOSED (E finishes); host decides, RPC on change
var _ready_scan_left: float = 0.0
var _finisher_prompt: SpiderFinisherPrompt = null

static var _cliff_cache: Array[RID] = []
static var _cliff_cache_msec: int = -1000
static var _ray_query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.new()

@onready var _rig: SpiderRig = $Rig
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _death_fx: CPUParticles2D = $DeathFx
@onready var _zone: Node2D = $Zone
@onready var _trail: ShadowTrailComponent = $ShadowTrail
@onready var _navigation: EnemyNavigation = $Navigation
@onready var _senses: EnemySenseComponent = $Senses
@onready var _posture: EnemyPostureComponent = $Posture
@onready var _bridge: EnemyWorldBridge = $WorldBridge


func _ready() -> void:
	add_to_group("predators")
	_def = EnemyScaling.scaled(DataRegistry.get_entry("enemies", enemy_id), health_scale, damage_scale)
	_home = global_position
	_post_heading = heading

	_apply_brood_stats()
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)

	_rig.strike_reach = float(_def["reach"])
	_rig.strike_arc = deg_to_rad(float(_def["arc"]))
	_rig.strike_hit_fraction = float(_def["strike_hit_time"]) / float(_def["strike"])
	_rig.apply_brood_variant(brood_variant)

	_senses.configure(self, _def)
	_posture.configure(_def, health_scale)
	_posture.posture_broken.connect(_on_posture_broken)

	_zone.draw.connect(_draw_zone)
	_zone.visible = false
	_phase_slot = absi(hash(name)) % 3
	_bridge.configure(self, _zone)

	_rig.foot_landed.connect(_on_rig_foot_landed)
	_orbit_side = 1.0 if hash(name) % 2 == 0 else -1.0
	for world: Node in get_tree().get_nodes_in_group("world"):
		if world.has_method("navigation_floor"):
			_world = world
			break
	_navigation.configure(self, _body_shape, _def["navigation"], _navigation_floor, _climb_link)

	if emerge_on_spawn:
		state = State.EMERGE
	elif ambush_mode == AmbushKind.CANOPY_DROP:
		state = State.CANOPY_WAIT
	elif ambush_mode == AmbushKind.MYCELIUM_TETHER:
		_spawn_ambush_tether.call_deferred()

	_enter_state()
	if state == State.EMERGE:
		_begin_emergence()
	_finisher_prompt = SpiderFinisherPrompt.new()
	_finisher_prompt.name = "FinisherPrompt"
	_finisher_prompt.spider = self
	add_child(_finisher_prompt)
	if not multiplayer.is_server():
		_request_state.rpc_id(1)


func _apply_brood_stats() -> void:
	var variants: Array = _def.get("variants", []) as Array
	var base_hp: float = float(_def["max_health"])
	_variant_speed_mult = 1.0
	if brood_variant >= 0 and brood_variant < variants.size():
		var vspec: Dictionary = variants[brood_variant] as Dictionary
		_variant_speed_mult = float(vspec.get("speed_mult", 1.0))
		if brood_variant == 1: ## Scout
			base_hp = roundf(base_hp * 0.82)
		elif brood_variant == 2: ## Thorn Elder
			base_hp = roundf(base_hp * 1.32)
	_health.max_health = base_hp
	_health.current = _health.max_health


func _on_rig_foot_landed(point: Vector2) -> void:
	if state == State.CANOPY_WAIT:
		return
	if state != State.IDLE or ambush_mode != AmbushKind.CREVICE_CROUCH:
		_trail.leave(point)
	if _bridge != null:
		_bridge.on_claw_landed(point, state in [State.STRIKE, State.GRAPPLE_PULL, State.VENOM_LUNGE])


func _spawn_ambush_tether() -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var perp: Vector2 = Vector2.from_angle(heading).orthogonal()
	var span_half: float = 22.0
	var center_ahead: Vector2 = global_position + Vector2.from_angle(heading) * 26.0
	var a_pt: Vector2 = center_ahead - perp * span_half
	var b_pt: Vector2 = center_ahead + perp * span_half
	var tether: MyceliumTether = MyceliumTether.new()
	tether.name = "Tether_%s" % name
	get_parent().add_child(tether)
	tether.setup(a_pt, b_pt, self)
	tether.tripped.connect(_on_tether_tripped)
	_tether = tether


func _on_tether_tripped(world_pos: Vector2, player: Player) -> void:
	if not multiplayer.is_server() or state == State.DEAD:
		return
	_target = player
	_senses.remember(world_pos, EnemySenseComponent.TriggerKind.TETHER)
	ambush_mode = AmbushKind.NONE
	if state in [State.IDLE, State.INVESTIGATE, State.HESITATE]:
		heading = (world_pos - global_position).angle()
		_set_state(State.CHASE)


func _process(delta: float) -> void:
	_rig.finisher_ready = finisher_ready_kind > 0 and state not in [State.DEAD, State.FINISHED_IMPALED]
	_rig.emergence = clampf(_state_time / ShadowBirth.DURATION, 0.0, 1.0) if state == State.EMERGE else 1.0
	_rig.health_ratio = _health.current / maxf(_health.max_health, 1.0)
	if state == State.CANOPY_WAIT:
		_rig.air_height = 58.0
	elif state == State.CANOPY_DROP:
		var drop_dur: float = 0.42
		_rig.air_height = lerpf(58.0, 0.0, pow(clampf(_state_time / drop_dur, 0.0, 1.0), 1.7))
	else:
		_rig.air_height = 0.0

	var use_attack_aim: bool = state in [
		State.WINDUP, State.STRIKE, State.GRAPPLE_WINDUP, State.GRAPPLE_THROW, State.GRAPPLE_PULL,
		State.VENOM_WINDUP, State.VENOM_LUNGE, State.SILK_BACKSTEP, State.RECOVER,
		State.CLIMB_WINDUP, State.CLIMB, State.CLIMB_RETREAT, State.HESITATE
	]
	_rig.set_aim(attack_dir if use_attack_aim else Vector2.from_angle(heading))
	_rig.set_anchor(anchor)
	_rig.attack_side = attack_side
	_rig.update_rig(delta, velocity, heading)

	if state == State.STRIKE and not _slash_grass_done and _state_time >= float(_def["strike_hit_time"]) * 0.45:
		_slash_grass_done = true
		if _bridge != null:
			_bridge.on_scythe_slash(attack_origin, attack_dir, float(_def["reach"]))

	var zone_needed: bool = state in [
		State.WINDUP, State.STRIKE, State.GRAPPLE_WINDUP, State.GRAPPLE_THROW,
		State.VENOM_WINDUP, State.VENOM_LUNGE, State.CANOPY_WAIT, State.CANOPY_DROP
	]
	if zone_needed != _zone_active:
		_zone_active = zone_needed
		_zone.visible = zone_needed
		_zone.queue_redraw()
	elif zone_needed:
		_zone.queue_redraw()


func _physics_process(delta: float) -> void:
	_state_time += delta
	if not multiplayer.is_server() or state in [State.DEAD, State.FINISHED_IMPALED]:
		return
	_ready_scan_left -= delta
	if _ready_scan_left <= 0.0:
		_ready_scan_left = float(FinisherRules.settings().get("ready_scan_seconds", 0.1))
		_set_finisher_ready(FinisherRules.ready_kind_for(self, _health, state == State.EXPOSED))
	if state == State.EMERGE:
		velocity = Vector2.ZERO
		if _state_time >= ShadowBirth.DURATION:
			_set_state(State.IDLE)
		return

	_grapple_cd = maxf(0.0, _grapple_cd - delta)
	_venom_cd = maxf(0.0, _venom_cd - delta)
	_backstep_cd = maxf(0.0, _backstep_cd - delta)
	_climb_cd = maxf(0.0, _climb_cd - delta)
	_climb_retry = maxf(0.0, _climb_retry - delta)
	_flinch_left = maxf(0.0, _flinch_left - delta)
	_aim_sync_left -= delta
	if _front_hit_window > 0.0:
		_front_hit_window = maxf(0.0, _front_hit_window - delta)
		if _front_hit_window <= 0.0:
			_recent_front_hits = 0

	_senses.tick_memory(delta)
	_posture.tick(delta, state == State.EXPOSED)

	match state:
		State.CANOPY_WAIT:
			velocity = Vector2.ZERO
			_canopy_wait_tick(delta)
			return
		State.CANOPY_DROP:
			velocity = Vector2.ZERO
			if _state_time >= 0.42:
				ambush_mode = AmbushKind.NONE
				_set_state(State.CHASE if _target_valid() else State.IDLE)
			return
		State.IDLE:
			_idle(delta)
		State.HESITATE:
			velocity = Vector2.ZERO
			if _target_valid():
				attack_dir = (_target.global_position - global_position).normalized()
				heading = lerp_angle(heading, attack_dir.angle(), 4.5 * delta)
			var hes_dur: float = float((_def.get("senses", {}) as Dictionary).get("hesitate_seconds", 0.45))
			if _state_time >= hes_dur:
				_set_state(State.NOTICE if _target_valid() else State.IDLE)
		State.NOTICE:
			velocity = Vector2.ZERO
			if _target_valid():
				heading = lerp_angle(heading, (_target.global_position - global_position).angle(), 4.5 * delta)
			if _state_time >= float(_def["notice_seconds"]):
				_set_state(State.CHASE if _target_valid() else State.IDLE)
		State.INVESTIGATE:
			_investigate(delta)
		State.CHASE:
			_chase(delta)
		State.WINDUP, State.GRAPPLE_WINDUP, State.VENOM_WINDUP:
			_windup()
		State.STRIKE:
			if not _hit_scored:
				_strike()
			if _state_time >= float(_def["strike"]):
				CombatCoordinator.release_melee_token(self, _target)
				_set_state(State.RECOVER)
		State.VENOM_LUNGE:
			_venom_lunge_step(delta)
		State.SILK_BACKSTEP:
			_backstep_move(delta)
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
		State.EXPOSED:
			velocity = velocity.move_toward(Vector2.ZERO, 420.0 * delta)
			if _state_time >= _posture.exposed_seconds:
				_posture.restore_full()
				_set_state(State.CHASE if _target_valid() else State.IDLE)
		State.PACK_RECOIL:
			velocity = velocity.move_toward(Vector2.ZERO, 520.0 * delta)
			if _state_time >= float(_def.get("pack_recoil_seconds", 0.35)):
				_set_state(State.CHASE if _target_valid() else State.IDLE)
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
	if velocity.length_squared() > 0.0001 or state in [State.GRAPPLE_PULL, State.VENOM_LUNGE, State.SILK_BACKSTEP]:
		move_and_slide()
	if state == State.GRAPPLE_PULL and get_slide_collision_count() > 0:
		_set_state(State.RECOVER)


func _set_state(new_state: State) -> void:
	if state in [State.WINDUP, State.STRIKE, State.VENOM_WINDUP, State.VENOM_LUNGE] and new_state not in [State.STRIKE, State.VENOM_LUNGE]:
		CombatCoordinator.release_melee_token(self, _target)
	if new_state == State.CHASE:
		_hunt_clock = 0.0
		if ambush_mode == AmbushKind.CREVICE_CROUCH:
			ambush_mode = AmbushKind.NONE
	if new_state in [State.CHASE, State.IDLE, State.DEAD, State.INVESTIGATE]:
		_navigation.invalidate()
	if new_state in [State.WINDUP, State.GRAPPLE_WINDUP, State.VENOM_WINDUP]:
		attack_origin = global_position
		if _target != null and is_instance_valid(_target):
			attack_dir = (_target.global_position - global_position).normalized()
		if new_state == State.WINDUP:
			attack_side *= -1.0
		anchor = _grapple_anchor() if new_state == State.GRAPPLE_WINDUP else (attack_origin + attack_dir * _venom_cfg_float("distance", 46.0) if new_state == State.VENOM_WINDUP else global_position)
	elif new_state == State.HESITATE and _target != null and is_instance_valid(_target):
		attack_origin = global_position
		attack_dir = (_target.global_position - global_position).normalized()
	elif new_state == State.SILK_BACKSTEP:
		attack_origin = global_position
		if _target != null and is_instance_valid(_target):
			attack_dir = (_target.global_position - global_position).normalized()
		else:
			attack_dir = Vector2.from_angle(heading)
		var back_dist: float = float((_def.get("backstep", {}) as Dictionary).get("distance", 32.0))
		anchor = _compute_backstep_anchor(back_dist)
	if new_state not in [State.CHASE, State.IDLE, State.INVESTIGATE, State.HURT, State.EXPOSED, State.PACK_RECOIL]:
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
	_slash_grass_done = false
	_venom_landed = false
	_aim_locked = false
	_aim_sync_left = 0.0
	_strike_progress = 0.0
	_struck.clear()
	_enter_state()
	if state == State.EMERGE:
		_begin_emergence()
	elif state == State.CANOPY_WAIT:
		_hurtbox.set_deferred("monitorable", false)
		_body_shape.set_deferred("disabled", true)
	else:
		if _previous_state == State.CANOPY_WAIT or is_instance_valid(_birth):
			_hurtbox.set_deferred("monitorable", state != State.DEAD)
			_body_shape.set_deferred("disabled", state == State.DEAD)
		if is_instance_valid(_birth) and _state_time > 0.0 and _previous_state != State.EMERGE:
			_birth.queue_free()


func _begin_emergence() -> void:
	if not is_instance_valid(_birth):
		_birth = ShadowBirth.new()
		add_child(_birth)
		_rig.emergence_seed = _birth._seed
	_birth.age = _state_time
	_rig.emergence = clampf(_state_time / ShadowBirth.DURATION, 0.0, 1.0)
	_hurtbox.set_deferred("monitorable", false)
	_body_shape.set_deferred("disabled", true)


@rpc("any_peer", "call_remote", "reliable")
func _request_state() -> void:
	if multiplayer.is_server():
		_apply_state.rpc_id(multiplayer.get_remote_sender_id(), state, attack_dir, anchor, attack_origin, attack_side, _state_time, _previous_state)


func _canopy_wait_tick(delta: float) -> void:
	_search_timer -= delta
	if _search_timer > 0.0:
		return
	_search_timer = 0.14
	for player: Player in Player.all:
		if not is_instance_valid(player) or player.health.current <= 0.0 or player.veiled():
			continue
		var d: float = global_position.distance_to(player.global_position)
		var trigger_r: float = 54.0 if (player.stealth != null and player.stealth.sneaking) else 74.0
		if d <= trigger_r and _same_floor(global_position, player.global_position):
			_target = player
			heading = (player.global_position - global_position).angle()
			_set_state(State.CANOPY_DROP)
			return


func _idle(delta: float) -> void:
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = 0.16
		var shade_bonus: float = 0.86 if (_bridge != null and _bridge.in_canopy_shade) else 1.0
		var sensed: Dictionary = _senses.scan(heading, _clear_path, _sees_over_cliff, shade_bonus)
		var found: Player = sensed["player"] as Player
		var trig: int = int(sensed["trigger"])
		if found != null:
			_target = found
			if trig == EnemySenseComponent.TriggerKind.VISION:
				if _senses.consume_hesitation(found, global_position):
					_set_state(State.HESITATE)
				else:
					_set_state(State.NOTICE)
			else:
				# Biotremor felt through the substrate -> orient & investigate the vibration source!
				anchor = sensed["pos"] as Vector2
				_set_state(State.INVESTIGATE)
			return

	if ambush_mode == AmbushKind.CREVICE_CROUCH:
		velocity = velocity.move_toward(Vector2.ZERO, 160.0 * delta)
		return

	if night != null and night.goal.is_finite():
		var way: Vector2 = _steer(night.walk_dir(self, _navigation, delta))
		velocity = velocity.move_toward(way * float(_def["wander_speed"]) * night.speed_factor(), 140.0 * delta)
		if way != Vector2.ZERO:
			heading = lerp_angle(heading, way.angle(), float(_def["turn_speed"]) * 0.5 * delta)
		return

	if bool(_def.get("post", false)):
		var t_p: float = Time.get_ticks_msec() * 0.001 + float(absi(hash(name)) % 100)
		heading = lerp_angle(heading, _post_heading + sin(t_p * 0.7) * 0.4, 2.0 * delta)
		var pull: Vector2 = _home - global_position
		var sway: Vector2 = Vector2.from_angle(_post_heading + PI / 2.0) * sin(t_p * 0.9) * 7.0 + Vector2.from_angle(_post_heading) * sin(t_p * 1.7) * 2.5
		velocity = velocity.move_toward((sway + pull * 2.5).limit_length(40.0 if pull.length() > 20.0 else 11.0), 90.0 * delta)
		return

	# Ecological daytime canopy-shade seeking (`T4`): exposed daytime spiders drift back toward nearby shade!
	if _bridge != null and _bridge.sun_glare > 0.5 and night == null:
		var shade_dir: Vector2 = _seek_nearby_shade_dir()
		if shade_dir != Vector2.ZERO:
			var steered_sh: Vector2 = _steer(shade_dir)
			velocity = velocity.move_toward(steered_sh * float(_def["wander_speed"]) * 1.35, 130.0 * delta)
			if steered_sh != Vector2.ZERO:
				heading = lerp_angle(heading, steered_sh.angle(), float(_def["turn_speed"]) * 0.6 * delta)
			return

	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_dir = Vector2.from_angle(randf() * TAU) if _wander_dir == Vector2.ZERO else Vector2.ZERO
		_wander_timer = randf_range(1.0, 2.6)
	var direction: Vector2 = _steer(_wander_dir)
	velocity = velocity.move_toward(direction * float(_def["wander_speed"]), 120.0 * delta)
	if direction != Vector2.ZERO:
		heading = lerp_angle(heading, direction.angle(), float(_def["turn_speed"]) * 0.5 * delta)


func _seek_nearby_shade_dir() -> Vector2:
	if _bridge == null:
		return Vector2.ZERO
	for sector_i: int in 8:
		var dir_c: Vector2 = Vector2.from_angle(float(sector_i) * PI * 0.25)
		if _bridge.is_position_shaded(global_position + dir_c * 52.0):
			return dir_c
	return Vector2.ZERO


func _investigate(delta: float) -> void:
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = 0.14
		var sensed: Dictionary = _senses.scan(heading, _clear_path, _sees_over_cliff, 1.0)
		var found: Player = sensed["player"] as Player
		if found != null and int(sensed["trigger"]) == EnemySenseComponent.TriggerKind.VISION:
			_target = found
			_set_state(State.NOTICE)
			return
		elif found != null:
			anchor = sensed["pos"] as Vector2

	var inv_dur: float = float((_def.get("senses", {}) as Dictionary).get("investigate_seconds", 2.8))
	if _state_time >= inv_dur or _senses.memory_left <= 0.0:
		_set_state(State.IDLE)
		return

	var to_goal: Vector2 = anchor - global_position
	if to_goal.length() <= 14.0:
		velocity = velocity.move_toward(Vector2.ZERO, 220.0 * delta)
		heading += sin(_state_time * 5.2) * 1.8 * delta ## Sweeping palps & ocelli searching the spot!
		return

	var step_dir: Vector2 = _steer(to_goal.normalized())
	if step_dir != Vector2.ZERO:
		heading = lerp_angle(heading, step_dir.angle(), float(_def["turn_speed"]) * 0.85 * delta)
	var surf_mult: float = _bridge.surface_speed_mult(global_position) if _bridge != null else 1.0
	velocity = velocity.move_toward(step_dir * float(_def["stalk_speed"]) * 1.15 * surf_mult, 420.0 * delta)


func _chase(delta: float) -> void:
	if not _target_valid():
		if _senses.memory_left > 0.5 and _target != null and is_instance_valid(_target) and _target.health.current > 0.0 and not _target.veiled():
			anchor = _senses.known_pos
			_target = null
			CombatCoordinator.unregister(self)
			_set_state(State.INVESTIGATE)
			return
		_target = null
		CombatCoordinator.unregister(self)
		_senses.reset_calm()
		_set_state(State.IDLE)
		return

	var tpos: Vector2 = _target.global_position
	_senses.remember(tpos, EnemySenseComponent.TriggerKind.VISION)
	var toward: Vector2 = tpos - global_position
	var distance: float = toward.length()
	var frame: int = Engine.get_physics_frames()
	if _state_time <= delta * 1.5 or frame >= _chase_next_check or tpos.distance_squared_to(_chase_last_pos) > 576.0:
		_chase_next_check = frame + 3
		_chase_last_pos = tpos
		_chase_clear = _same_floor(global_position, tpos) and _clear_path(global_position, tpos)
		_chase_nav_clear = _navigation.segment_clear(global_position, tpos)
	var clear: bool = _chase_clear

	var surf_mult: float = _bridge.surface_speed_mult(global_position) if _bridge != null else 1.0
	var glare_mult: float = (0.88 if (_bridge != null and _bridge.sun_glare > 0.55) else 1.0)
	var turn_rate: float = float(_def["turn_speed"]) * surf_mult
	heading = lerp_angle(heading, toward.angle(), turn_rate * delta)
	_hunt_clock += delta
	var stalk: float = float(_def["stalk_seconds"])

	# 1. Venom Lunge against webbed prey or by Thorn Elder brood (`T5`)!
	var target_webbed: bool = _target.effects != null and _target.effects.has("webbed")
	if clear and _venom_cd <= 0.0 and (target_webbed or brood_variant == 2) and distance >= _venom_cfg_float("min_range", 26.0) and distance <= _venom_cfg_float("max_range", 62.0):
		if CombatCoordinator.request_melee_token(self, _target, 0.95):
			_venom_cd = _venom_cfg_float("cooldown", 5.8)
			_set_state(State.VENOM_WINDUP)
			return

	# 2. Scythe Slash (gated by pack melee token when hunting in a pack!)
	if clear and distance <= float(_def["attack_range"]):
		if CombatCoordinator.request_melee_token(self, _target, 0.90):
			_set_state(State.WINDUP)
			return

	# 3. Silk Grapple Snare
	if clear and _grapple_cd <= 0.0 and _hunt_clock >= stalk and distance >= float(_grapple()["min_range"]) and distance <= float(_grapple()["max_range"]):
		_grapple_cd = float(_grapple()["cooldown"])
		_set_state(State.GRAPPLE_WINDUP)
		return

	if not _chase_nav_clear:
		var route: Vector2 = _navigation.direction_to(tpos, delta)
		if _navigation.climb_target.is_finite():
			_prepare_climb(_navigation.climb_target)
			return
		if route != Vector2.ZERO:
			heading = lerp_angle(heading, route.angle(), turn_rate * delta)
		velocity = velocity.move_toward(route * float(_def["chase_speed"]) * 0.82 * _variant_speed_mult * surf_mult * glare_mult, 650.0 * delta)
		return
	elif _navigation.searching or not _navigation.path.is_empty():
		_navigation.invalidate()

	var flank_angle: float = CombatCoordinator.claim_flank_angle(self, _target)
	var speed: float = float(_def["stalk_speed"])
	var direction: Vector2 = toward.normalized()
	if absf(flank_angle) > 0.05 and distance > 28.0:
		var flank_blend: float = clampf((distance - 24.0) / 72.0, 0.22, 0.68)
		direction = direction.lerp(direction.rotated(flank_angle), flank_blend).normalized()

	var surging: bool = false
	if _hunt_clock < stalk:
		direction = (direction * 0.45 + direction.orthogonal() * _orbit_side * 0.8).normalized()
	else:
		var phase: float = fposmod(_hunt_clock - stalk, float(_def["surge_seconds"]) + float(_def["settle_seconds"]))
		if phase < float(_def["surge_seconds"]):
			speed = float(_def["chase_speed"])
			surging = true
		else:
			speed = float(_def["settle_speed"])
		if distance < float(_def["orbit_distance"]) and absf(flank_angle) < 0.05:
			direction = (direction + direction.orthogonal() * _orbit_side * float(_def["orbit_weight"])).normalized()
	if not surging:
		speed *= _skitter() * 1.6
	speed *= _variant_speed_mult * surf_mult * glare_mult
	velocity = velocity.move_toward(_steer(direction) * speed, 650.0 * delta)


func _skitter() -> float:
	var seed_offset: float = float(absi(hash(name)) % 97) * 0.37
	var wave: float = sin(_hunt_clock * 6.4 + seed_offset) + 0.55 * sin(_hunt_clock * 2.3 + seed_offset * 1.7)
	return clampf(wave * 1.4 + 0.45, 0.0, 1.0)


func _steer(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return direction
	if _steer_ttl > 0 and get_slide_collision_count() == 0 and direction.dot(_steer_in) > 0.94:
		_steer_ttl -= 1
		return _steer_dir
	_steer_in = direction
	_steer_ttl = 3
	for angle: float in [0.0, 0.55 * _orbit_side, -0.55 * _orbit_side, 1.1 * _orbit_side, -1.1 * _orbit_side, 1.55 * _orbit_side]:
		var candidate: Vector2 = direction.rotated(angle)
		var probe_to: Vector2 = global_position + candidate * 24.0
		if (_bridge == null or not _bridge.is_deep_water(probe_to)) and not test_move(global_transform, candidate * 24.0):
			_steer_dir = candidate
			return candidate
	_steer_dir = Vector2.ZERO
	return Vector2.ZERO


func _clear_path(from: Vector2, to: Vector2) -> bool:
	_ray_query.from = from + Vector2(0, -4)
	_ray_query.to = to + Vector2(0, -4)
	_ray_query.collision_mask = 1
	_ray_query.exclude = []
	return get_world_2d().direct_space_state.intersect_ray(_ray_query).is_empty()


func _navigation_floor(point: Vector2) -> bool:
	if _bridge != null and _bridge.is_deep_water(point):
		return false
	if is_instance_valid(_world):
		return bool(_world.call("navigation_floor", point))
	return Terrain.relief == null or Terrain.relief.is_land(floori(point.x / Relief.TILE), floori(point.y / Relief.TILE))


func _height_at(point: Vector2) -> float:
	return Terrain.relief.level_at(point) if Terrain.relief != null else 0.0


func _same_floor(from: Vector2, to: Vector2) -> bool:
	return absf(_height_at(from) - _height_at(to)) < 0.45


func _cliff_rids() -> Array[RID]:
	var now: int = Time.get_ticks_msec()
	if now - _cliff_cache_msec >= 400:
		_cliff_cache_msec = now
		_cliff_cache.clear()
		for node: Node in get_tree().get_nodes_in_group("relief_walls"):
			if node is PhysicsBody2D:
				_cliff_cache.append((node as PhysicsBody2D).get_rid())
	return _cliff_cache


func _sees_over_cliff(point: Vector2) -> bool:
	if _same_floor(global_position, point):
		return false
	_ray_query.from = global_position + Vector2(0, -4)
	_ray_query.to = point + Vector2(0, -4)
	_ray_query.collision_mask = 1
	_ray_query.exclude = _cliff_rids()
	return get_world_2d().direct_space_state.intersect_ray(_ray_query).is_empty()


func _climb_link(from: Vector2, step: Vector2) -> Vector2:
	if Terrain.relief == null or _climb_cd > 0.0:
		return Vector2.INF
	_ray_query.from = from + _body_shape.position
	_ray_query.to = from + _body_shape.position + step.normalized() * (step.length() + 6.0)
	_ray_query.collision_mask = 1
	_ray_query.exclude = []
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(_ray_query)
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
	_ray_query.from = from + _body_shape.position
	_ray_query.to = to + _body_shape.position
	_ray_query.collision_mask = 1
	_ray_query.exclude = []
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(_ray_query)
	var collider: Node = hit.get("collider") as Node
	if collider == null or not collider.is_in_group("relief_walls"):
		return false
	var samples: int = maxi(2, ceili(from.distance_to(to) / 4.0))
	for i: int in range(samples + 1):
		var point: Vector2 = from.lerp(to, float(i) / float(samples))
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
	CombatCoordinator.unregister(self)
	if _tether != null and is_instance_valid(_tether):
		_tether.queue_free()


func _venom_cfg_float(key: String, default_val: float) -> float:
	var vc: Dictionary = _def.get("venom_lunge", {}) as Dictionary
	return float(vc.get(key, default_val))


func _windup() -> void:
	var grapple: bool = state == State.GRAPPLE_WINDUP
	var venom: bool = state == State.VENOM_WINDUP
	var duration: float = float(_grapple()["windup"]) if grapple else (_venom_cfg_float("windup", 0.52) if venom else float(_def["windup"]))
	var lock_sec: float = _venom_cfg_float("aim_lock", 0.26) if venom else float(_def["aim_lock_seconds"])
	if _state_time < duration - lock_sec:
		if _target_valid():
			attack_dir = (_target.global_position - attack_origin).normalized()
			if grapple:
				anchor = _grapple_anchor()
			elif venom:
				anchor = attack_origin + attack_dir * _venom_cfg_float("distance", 46.0)
		if _aim_sync_left <= 0.0:
			_aim_sync_left = 0.05
			_update_aim.rpc(attack_dir, anchor)
	elif not _aim_locked:
		_aim_locked = true
		_update_aim.rpc(attack_dir, anchor)
	heading = attack_dir.angle()
	if _state_time >= duration:
		if grapple:
			_set_state(State.GRAPPLE_THROW)
		elif venom:
			_set_state(State.VENOM_LUNGE)
		else:
			_set_state(State.STRIKE)


@rpc("authority", "call_remote", "reliable")
func _update_aim(direction: Vector2, point: Vector2) -> void:
	if state in [State.WINDUP, State.GRAPPLE_WINDUP, State.VENOM_WINDUP]:
		attack_dir = direction
		anchor = point


func _recover_time() -> float:
	if _previous_state in [State.CLIMB, State.CLIMB_RETREAT, State.CLIMB_WINDUP]:
		return float(_def["climb"]["recover"])
	if _previous_state == State.VENOM_LUNGE:
		return _venom_cfg_float("recover", 0.76)
	return float(_grapple()["recover"]) if _previous_state == State.GRAPPLE_PULL else float(_def["recover"])


func _grapple() -> Dictionary:
	return _def.get("grapple", {}) as Dictionary


func _grapple_anchor() -> Vector2:
	var target_dist: float = global_position.distance_to(_target.global_position) if (_target != null and is_instance_valid(_target)) else float(_grapple()["hit_range"])
	var reach: float = minf(target_dist, float(_grapple()["hit_range"]))
	var point: Vector2 = attack_origin + attack_dir * reach
	_ray_query.from = attack_origin + Vector2(0, -4)
	_ray_query.to = point + Vector2(0, -4)
	_ray_query.collision_mask = 1
	_ray_query.exclude = []
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(_ray_query)
	return (hit["position"] as Vector2) - Vector2(0, -4) - attack_dir * 8.0 if not hit.is_empty() else point


func _grapple_hit() -> bool:
	var landed: bool = false
	var web_dur: float = float(_def.get("web_seconds", 1.35))
	for target: HurtboxComponent in HitScan.circle(self, anchor + Vector2(0, -12), float(_grapple()["radius"]), PLAYER_HURTBOX_MASK):
		var hit_player: Player = target.get_parent() as Player
		if hit_player != null and hit_player.air_height > 6.5:
			continue
		if _same_floor(attack_origin, target.global_position) and _clear_path(attack_origin, target.global_position):
			target.take_hit(float(_grapple()["damage"]), attack_origin + Vector2(0, -10), -float(_grapple()["pull"]))
			if hit_player != null and hit_player.effects != null:
				hit_player.effects.apply("webbed", web_dur)
			landed = true
	return landed


func _grapple_pull(delta: float) -> void:
	var toward: Vector2 = anchor - global_position
	if toward.length() <= float(_grapple()["stop"]) or _state_time >= 0.65:
		_set_state(State.RECOVER)
		return
	velocity = velocity.move_toward(toward.normalized() * float(_grapple()["pull_speed"]), 2200.0 * delta)


func _compute_backstep_anchor(max_dist: float) -> Vector2:
	var retreat_dir: Vector2 = -attack_dir.normalized()
	if retreat_dir.length_squared() < 0.01:
		retreat_dir = -Vector2.from_angle(heading)
	for step_d: float in [max_dist, max_dist * 0.72, max_dist * 0.45]:
		var cand: Vector2 = global_position + retreat_dir * step_d
		if (_bridge == null or not _bridge.is_deep_water(cand)) and _same_floor(global_position, cand) and not test_move(global_transform, retreat_dir * step_d):
			return cand
	return global_position + retreat_dir * 8.0


func _backstep_move(delta: float) -> void:
	var dur: float = float((_def.get("backstep", {}) as Dictionary).get("duration", 0.22))
	var toward: Vector2 = anchor - global_position
	if _state_time >= dur or toward.length() <= 3.5 or get_slide_collision_count() > 0:
		velocity = Vector2.ZERO
		_set_state(State.CHASE if _target_valid() else State.IDLE)
		return
	var spd: float = attack_origin.distance_to(anchor) / maxf(dur, 0.05)
	velocity = toward.normalized() * spd * (1.35 - 0.5 * (_state_time / dur))


func _venom_lunge_step(_delta: float) -> void:
	var dur: float = _venom_cfg_float("duration", 0.19)
	var dist_total: float = _venom_cfg_float("distance", 46.0)
	var half_w: float = _venom_cfg_float("width", 10.0) * 0.5
	var dmg: float = _venom_cfg_float("damage", 15.0) * damage_scale
	var knock: float = _venom_cfg_float("knockback", 78.0)
	var v_sec: float = _venom_cfg_float("venom_seconds", 4.0)

	var spd: float = dist_total / maxf(dur, 0.05)
	velocity = attack_dir * spd * (1.25 - 0.55 * clampf(_state_time / dur, 0.0, 1.0))
	if _bridge != null and _bridge.is_deep_water(global_position + attack_dir * 10.0):
		velocity = Vector2.ZERO

	var origin: Vector2 = global_position + Vector2(0, -10)
	for target: HurtboxComponent in HitScan.circle(self, origin + attack_dir * 14.0, half_w + 5.0, PLAYER_HURTBOX_MASK):
		var iid: int = target.get_instance_id()
		if _struck.has(iid):
			continue
		var hit_player: Player = target.get_parent() as Player
		if hit_player != null and hit_player.air_height > 6.5:
			continue
		if _same_floor(attack_origin, target.global_position) and _clear_path(global_position, target.global_position):
			_struck.append(iid)
			_venom_landed = true
			target.take_hit(dmg, origin, knock)
			if hit_player != null and hit_player.effects != null:
				hit_player.effects.apply("shadow_venom", v_sec, damage_scale)

	if _state_time >= dur or get_slide_collision_count() > 0:
		velocity = Vector2.ZERO
		CombatCoordinator.release_melee_token(self, _target)
		# Reward nimble Movement-2.0 sidesteps / ShadowSteps: a whiffed Venom Lunge skids into EXPOSED!
		if not _venom_landed:
			_posture.exposed_seconds = 0.88
			_set_state(State.EXPOSED)
			_posture.exposed_seconds = float((_def.get("posture", {}) as Dictionary).get("exposed_seconds", 1.1))
		else:
			_set_state(State.RECOVER)


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
		var hit_player: Player = target.get_parent() as Player
		# Movement 2.0 3D height fairness (`T5`): vaulting over a log or hopping a ledge clears low ground sweeps!
		if hit_player != null and hit_player.air_height > 6.0:
			continue
		if not _struck.has(target.get_instance_id()) and _same_floor(attack_origin, target.global_position) and _clear_path(attack_origin, target.global_position):
			_struck.append(target.get_instance_id())
			target.take_hit(float(_def["damage"]), origin, float(_def["knockback"]))
	_strike_progress = progress
	_hit_scored = progress >= 1.0


func _target_valid() -> bool:
	var sun_lose_scale: float = 0.82 if (_bridge != null and _bridge.sun_glare > 0.55) else 1.0
	return is_instance_valid(_target) and _target.health.current > 0.0 and not _target.veiled() and global_position.distance_to(_target.global_position) <= float(_def["lose_range"]) * _target.stealth.detection_multiplier() * sun_lose_scale


func _find_target() -> Player:
	var sensed: Dictionary = _senses.scan(heading, _clear_path, _sees_over_cliff, 1.0)
	return sensed["player"] as Player


func _draw_zone() -> void:
	match state:
		State.WINDUP, State.STRIKE:
			_zone_fan()
		State.GRAPPLE_WINDUP, State.GRAPPLE_THROW:
			_zone_line()
		State.VENOM_WINDUP, State.VENOM_LUNGE:
			_zone_venom()
		State.CANOPY_WAIT, State.CANOPY_DROP:
			_zone_canopy_drip()


func _zone_canopy_drip() -> void:
	var elapsed: float = (Time.get_ticks_msec() - _state_msec) / 1000.0
	var dropping: bool = state == State.CANOPY_DROP
	var r: float = 13.0 if dropping else (5.5 + 1.5 * sin(elapsed * 2.6))
	var strength: float = 0.85 if dropping else 0.34
	VoidZoneStyle.sinuous_rim_arc(_zone, Vector2.ZERO, Vector2.DOWN, r, TAU, SQUASH_ZONE(), elapsed, strength, dropping, -0.6 if dropping else 0.0, 6 if dropping else 0)


static func SQUASH_ZONE() -> float:
	return 0.78


func _zone_venom() -> void:
	var elapsed: float = (Time.get_ticks_msec() - _state_msec) / 1000.0
	var windup_dur: float = _venom_cfg_float("windup", 0.52)
	var lock_sec: float = _venom_cfg_float("aim_lock", 0.26)
	var locked: bool = state != State.VENOM_WINDUP or elapsed >= windup_dur - lock_sec
	var hot: bool = state == State.VENOM_LUNGE
	var strength: float = 0.82
	if state == State.VENOM_WINDUP and locked:
		strength = 0.88 + 0.12 * sin(elapsed * 42.0)
	elif hot:
		strength = 1.0 - clampf(elapsed / _venom_cfg_float("duration", 0.19), 0.0, 1.0)
	if strength <= 0.02:
		return

	var dist_v: float = _venom_cfg_float("distance", 46.0) + 4.0
	var half_w: float = _venom_cfg_float("width", 10.0) * 0.5 + 1.5
	var origin: Vector2 = attack_origin - global_position + Vector2(0, 2)
	var perp: Vector2 = attack_dir.orthogonal()
	var rail_col: Color = Color(ZONE_FLASH if (hot or locked) else VoidZoneStyle.HOT_CRIMSON, 0.94 * strength)
	var venom_col: Color = Color(VoidZoneStyle.VOID_MAGENTA, 0.88 * strength)

	VoidZoneStyle.fill_void_lane(_zone, origin, attack_dir, dist_v, half_w, elapsed, strength, locked, hot, 220)
	# Twin razor chelicera fang-tracks along left & right corridor borders!
	VoidZoneStyle.jagged_vein(_zone, origin + perp * half_w, origin + attack_dir * dist_v + perp * (half_w * 0.45), elapsed, 0.9, rail_col, venom_col, 0.65 * strength, 1.1, false)
	VoidZoneStyle.jagged_vein(_zone, origin - perp * half_w, origin + attack_dir * dist_v - perp * (half_w * 0.45), elapsed, 0.9, rail_col, venom_col, 0.65 * strength, 3.7, false)


func _zone_line() -> void:
	var grapple: Dictionary = _grapple()
	var elapsed: float = (Time.get_ticks_msec() - _state_msec) / 1000.0
	var locked: bool = state != State.GRAPPLE_WINDUP or elapsed >= float(grapple["windup"]) - float(_def["aim_lock_seconds"])
	var hot: bool = state != State.GRAPPLE_WINDUP
	var strength: float = 0.78
	if state == State.GRAPPLE_WINDUP and locked:
		strength = 0.85 + 0.15 * sin(elapsed * 40.0)
	elif hot:
		strength = 1.0 - clampf(elapsed / float(grapple["throw"]), 0.0, 1.0)
	var end: Vector2 = anchor - global_position
	var length: float = end.length()
	if length < 4.0 or strength <= 0.02:
		return
	var dir: Vector2 = end / length
	var perp: Vector2 = dir.orthogonal()
	var radius: float = float(grapple["radius"]) + ZONE_PAD
	var abyss_a: float = 0.62 * strength
	var silk_hot: Color = Color(ZONE_FLASH if hot else VoidZoneStyle.HOT_CRIMSON, 0.94 * strength)
	var silk_void: Color = Color(VoidZoneStyle.VOID_MAGENTA, 0.86 * strength)

	VoidZoneStyle.jagged_vein(_zone, dir * 6.0, end, elapsed, 2.2, silk_hot, silk_void, abyss_a, 1.3, true)
	VoidZoneStyle.jagged_vein(_zone, dir * 6.0 + perp * 1.2, end - perp * 1.2, elapsed + 0.6, 1.6, Color(ZONE_DARK, 0.82 * strength), Color(VoidZoneStyle.VOID_VIOLET, 0.78 * strength), abyss_a * 0.6, 4.9, false)
	VoidZoneStyle.fill_void_fan(_zone, end, dir, radius, TAU, 1.0, elapsed, strength, locked, hot, 260)

	for leg_i: int in 4:
		var a_leg: float = float(leg_i) * PI * 0.25 + sin(elapsed * 3.0 + float(leg_i)) * 0.06
		var d_leg: Vector2 = Vector2.from_angle(a_leg)
		VoidZoneStyle.jagged_vein(_zone, end - d_leg * (radius * 0.82), end + d_leg * (radius * 0.82), elapsed, 1.1, Color(ZONE_HOT, 0.72 * strength), silk_void, abyss_a * 0.5, float(leg_i) * 2.1, false)
	VoidZoneStyle.sinuous_rim_arc(_zone, end, dir, radius * 0.52, TAU, 1.0, -elapsed * 1.2, strength * 0.72, hot, 0.0, 0)
	VoidZoneStyle.sinuous_rim_arc(_zone, end, dir, radius - 0.8, TAU, 1.0, elapsed, strength, hot, -0.85 if locked else 0.75, 8)


func _zone_fan() -> void:
	var elapsed: float = (Time.get_ticks_msec() - _state_msec) / 1000.0
	var locked: bool = state != State.WINDUP or elapsed >= float(_def["windup"]) - float(_def["aim_lock_seconds"])
	var hot: bool = state != State.WINDUP
	var strength: float = 0.78
	if state == State.WINDUP and locked:
		strength = 0.86 + 0.14 * sin(elapsed * 40.0)
	elif hot:
		strength = 1.0 - clampf(elapsed / float(_def["strike"]), 0.0, 1.0)
	if strength <= 0.02:
		return
	var reach: float = float(_def["reach"]) + ZONE_PAD
	var arc_rad: float = deg_to_rad(float(_def["arc"]))
	var half_arc: float = arc_rad * 0.5
	var origin: Vector2 = attack_origin - global_position + Vector2(0, 2)
	var abyss_a: float = 0.60 * strength
	var fang_col: Color = Color(ZONE_FLASH if (hot or locked) else VoidZoneStyle.HOT_CRIMSON, 0.94 * strength)
	var web_col: Color = Color(VoidZoneStyle.VOID_MAGENTA, 0.84 * strength)

	VoidZoneStyle.fill_void_fan(_zone, origin, attack_dir, reach, arc_rad, 1.0, elapsed, strength, locked, hot, 420)

	for sp_i: int in 5:
		var frac_sp: float = float(sp_i) / 4.0 - 0.5
		var sp_dir: Vector2 = attack_dir.rotated(frac_sp * arc_rad)
		var is_edge: bool = (sp_i == 0 or sp_i == 4)
		VoidZoneStyle.jagged_vein(
			_zone,
			origin + sp_dir * 4.0,
			origin + sp_dir * (reach - 0.6),
			elapsed,
			0.55 if (is_edge and locked) else (1.1 if is_edge else 1.6),
			fang_col if is_edge else Color(ZONE_HOT, 0.78 * strength),
			web_col,
			abyss_a * (0.95 if is_edge else 0.55),
			float(sp_i) * 1.9,
			false
		)

	for ring_k: int in [1, 2]:
		var r_web: float = reach * (0.44 if ring_k == 1 else 0.73)
		for seg_i: int in 4:
			var a0: float = -half_arc + float(seg_i) * (arc_rad / 4.0)
			var a1: float = -half_arc + float(seg_i + 1) * (arc_rad / 4.0)
			var p0: Vector2 = origin + attack_dir.rotated(a0) * r_web
			var p1: Vector2 = origin + attack_dir.rotated(a1) * r_web
			var steps_w: int = maxi(4, roundi(p0.distance_to(p1) / 1.8))
			for wi: int in range(steps_w + 1):
				var wf: float = float(wi) / float(steps_w)
				var sag: float = sin(wf * PI) * (1.1 if locked else 2.4)
				var mid_dir: Vector2 = attack_dir.rotated(lerpf(a0, a1, wf))
				var wp: Vector2 = p0.lerp(p1, wf) - mid_dir * sag
				VoidZoneStyle.rift_px(_zone, wp, web_col if wi % 3 == 0 else Color(ZONE_HOT, 0.80 * strength), abyss_a * 0.55)

	VoidZoneStyle.sinuous_rim_arc(_zone, origin, attack_dir, reach - 0.8, arc_rad, 1.0, elapsed, strength, hot or locked, -0.95, 7)


func _enter_state() -> void:
	_set_climb_exceptions(state in [State.CLIMB, State.CLIMB_RETREAT])
	if _bridge != null:
		_bridge.sync_zone_z(_zone, global_position)
		_bridge.set_crouched_stealth(state == State.IDLE and ambush_mode == AmbushKind.CREVICE_CROUCH, _rig._body_scale_mult)

	var pose: SpiderRig.Pose = SpiderRig.Pose.LOCOMOTION
	var duration: float = 1.0
	match state:
		State.IDLE:
			if ambush_mode == AmbushKind.CREVICE_CROUCH:
				pose = SpiderRig.Pose.CROUCH
		State.CANOPY_WAIT:
			pose = SpiderRig.Pose.CANOPY_HANG
			_hurtbox.set_deferred("monitorable", false)
			_body_shape.set_deferred("disabled", true)
		State.CANOPY_DROP:
			pose = SpiderRig.Pose.CANOPY_DROP
			duration = 0.42
			if _bridge != null:
				_bridge.impulse_overhead_canopy(global_position)
		State.HESITATE:
			pose = SpiderRig.Pose.HESITATE
			duration = float((_def.get("senses", {}) as Dictionary).get("hesitate_seconds", 0.45))
		State.NOTICE:
			pose = SpiderRig.Pose.OBSERVE
			duration = float(_def["notice_seconds"])
		State.WINDUP:
			pose = SpiderRig.Pose.WINDUP
			duration = float(_def["windup"])
		State.STRIKE:
			pose = SpiderRig.Pose.STRIKE
			duration = float(_def["strike"])
		State.VENOM_WINDUP:
			pose = SpiderRig.Pose.VENOM_WINDUP
			duration = _venom_cfg_float("windup", 0.52)
		State.VENOM_LUNGE:
			pose = SpiderRig.Pose.VENOM_LUNGE
			duration = _venom_cfg_float("duration", 0.19)
		State.SILK_BACKSTEP:
			pose = SpiderRig.Pose.BACKSTEP
			duration = float((_def.get("backstep", {}) as Dictionary).get("duration", 0.22))
		State.EXPOSED:
			pose = SpiderRig.Pose.EXPOSED
			duration = _posture.exposed_seconds
		State.PACK_RECOIL:
			pose = SpiderRig.Pose.RECOIL
			duration = float(_def.get("pack_recoil_seconds", 0.35))
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
		State.FINISHED_IMPALED:
			pose = SpiderRig.Pose.IMPALED
			duration = 1.05

	match state:
		State.HESITATE:
			Sfx.at(self, "spider_hesitate", global_position, -5.0)
		State.NOTICE:
			Sfx.at(self, "spider_notice", global_position, -4.0)
		State.STRIKE:
			Sfx.at(self, "spider_attack", global_position, -2.0)
		State.VENOM_LUNGE:
			Sfx.at(self, "spider_venom", global_position, -2.0)
		State.SILK_BACKSTEP:
			Sfx.at(self, "spider_backstep", global_position, -3.0)
		State.EXPOSED:
			Sfx.at(self, "spider_exposed", global_position, -2.0)
		State.CANOPY_DROP:
			Sfx.at(self, "spider_grapple", global_position, -4.0)
		State.GRAPPLE_THROW:
			Sfx.at(self, "spider_grapple", global_position, -2.0)
		State.HURT, State.PACK_RECOIL:
			Sfx.at(self, "spider_hurt", global_position, -3.0)
		State.DEAD:
			Sfx.at(self, "spider_death", global_position, -1.0)

	_rig.attack_side = attack_side
	if state in [State.CLIMB_WINDUP, State.CLIMB, State.CLIMB_RETREAT]:
		_rig.set_climb(attack_origin, anchor, _height_at(anchor) > _height_at(attack_origin))
	_rig.start_pose(pose, duration, _state_time)

	if state == State.GRAPPLE_PULL:
		var across: Vector2 = attack_dir.orthogonal() * 8.0
		_trail.leave(anchor + across, true)
		_trail.leave(anchor - across, true)
		if _bridge != null:
			_bridge.on_ground_burst(anchor, 20.0, 0.85)
	elif state == State.EXPOSED and _bridge != null:
		_bridge.on_ground_burst(global_position, 22.0, 0.90)
	elif _previous_state == State.CANOPY_DROP and _bridge != null:
		_bridge.on_ground_burst(global_position, 24.0, 0.95)
		_trail.leave(global_position, true)


## Called by `SpiderHurtbox.take_hit` before `HealthComponent.take_damage`:
## Evaluates directional Opisthosoma weakpoint (`1.25x`), front guard (`0.85x`), `EXPOSED` (`1.35x`), & posture break!
func evaluate_hurtbox_hit(damage: float, from_pos: Vector2, knockback: float) -> float:
	var front_guarded: bool = (state == State.IDLE and ambush_mode != AmbushKind.NONE) or state in [State.NOTICE, State.GRAPPLE_WINDUP]
	var can_break: bool = state not in [State.DEAD, State.EXPOSED, State.CLIMB, State.CLIMB_RETREAT, State.CANOPY_WAIT]
	var scaled_dmg: float = _posture.evaluate_incoming_hit(
		damage,
		from_pos,
		knockback,
		global_position,
		heading,
		front_guarded,
		state == State.EXPOSED,
		can_break,
		multiplayer.is_server()
	)
	if multiplayer.is_server() and state not in [State.DEAD, State.EXPOSED]:
		var to_att: Vector2 = from_pos - global_position
		if to_att.length_squared() > 1.0 and absf(angle_difference(heading, to_att.angle())) <= deg_to_rad(75.0):
			_recent_front_hits += 1
			_front_hit_window = 2.2
	# Finisher V2: "Kern entblößt" is a promise. While the core beats (kind 1), any sword blow of the eligible player finishes, even a guarded one.
	if multiplayer.is_server() and finisher_ready_kind == 1 and FinisherComponent.melee_window_open():
		scaled_dmg = maxf(scaled_dmg, _health.current)
	return scaled_dmg


func _on_posture_broken(from_pos: Vector2) -> void:
	if not multiplayer.is_server() or _health.current <= 0.0 or state in [State.DEAD, State.CLIMB, State.CLIMB_RETREAT]:
		return
	var away: Vector2 = (global_position - from_pos).normalized()
	velocity = away * 64.0
	_set_state(State.EXPOSED)


func on_pack_ally_slain(fallen_pos: Vector2) -> void:
	if not multiplayer.is_server() or _health.current <= 0.0:
		return
	if state in [State.CHASE, State.IDLE, State.INVESTIGATE, State.NOTICE]:
		var away: Vector2 = (global_position - fallen_pos).normalized()
		if away.length_squared() < 0.01:
			away = -Vector2.from_angle(heading)
		velocity = away * 54.0
		_set_state(State.PACK_RECOIL)


func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	var away: Vector2 = (global_position - from).normalized()
	var heavy: bool = knockback >= float(_def["heavy_knockback"])
	_rig.hit_flash(away, heavy)
	if _bridge != null:
		_bridge.on_hit_splatter(global_position, from, heavy)
	if amount < 5000.0:
		DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -28), amount, away)
	if not multiplayer.is_server() or _health.current <= 0.0 or state in [State.DEAD, State.EXPOSED, State.STRIKE, State.VENOM_LUNGE, State.SILK_BACKSTEP, State.GRAPPLE_THROW, State.GRAPPLE_PULL, State.CLIMB, State.CLIMB_RETREAT]:
		return

	if ambush_mode == AmbushKind.CREVICE_CROUCH:
		ambush_mode = AmbushKind.NONE

	# Evasive Silk Backstep (`T5`): after 2 rapid close frontal hits, snap backward out of combo reach!
	var bs_cfg: Dictionary = _def.get("backstep", {}) as Dictionary
	if not heavy and _backstep_cd <= 0.0 and _recent_front_hits >= int(bs_cfg.get("trigger_hits", 2)) and global_position.distance_to(from) <= float(bs_cfg.get("trigger_range", 40.0)):
		if state in [State.CHASE, State.IDLE, State.RECOVER, State.HURT]:
			_recent_front_hits = 0
			_backstep_cd = float(bs_cfg.get("cooldown", 5.4))
			attack_dir = (from - global_position).normalized()
			heading = attack_dir.angle()
			_set_state(State.SILK_BACKSTEP)
			return

	var committed: bool = state in [State.WINDUP, State.GRAPPLE_WINDUP, State.VENOM_WINDUP, State.RECOVER]
	if heavy or (not committed and _flinch_left <= 0.0):
		_flinch_left = float(_def["flinch_cooldown"])
		velocity = away * knockback * float(_def["knockback_resistance"])
		_set_state(State.HURT)


func cut_down(from: Vector2) -> void:
	if multiplayer.is_server():
		_health.take_damage(_health.current, from, 240.0)


func can_accept_finisher() -> bool:
	return _health.current > 0.0 and state not in [State.DEAD, State.FINISHED_IMPALED, State.CANOPY_WAIT, State.EMERGE, State.CLIMB, State.CLIMB_RETREAT]


func is_being_finished() -> bool:
	return state == State.FINISHED_IMPALED


## Host: Finisher V2 readiness changed -> every peer (the core glow and the E prompt read it).
func _set_finisher_ready(kind: int) -> void:
	if kind == finisher_ready_kind:
		return
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_finisher_ready.rpc(kind)
	else:
		_rpc_finisher_ready(kind)


@rpc("authority", "call_local", "reliable")
func _rpc_finisher_ready(kind: int) -> void:
	var was: int = finisher_ready_kind
	finisher_ready_kind = kind
	if was == 0 and kind > 0 and state not in [State.DEAD, State.FINISHED_IMPALED]:
		Sfx.at(self, "finisher_ready", global_position, -8.0, 0.03)


## The spider where E would finish it (the prompt's reach).
func finisher_prompt_text() -> String:
	if finisher_ready_kind <= 0 or state in [State.DEAD, State.FINISHED_IMPALED]:
		return ""
	return "Finisher"


## Synchronized Finisher lock (`T3`, `V2`): pins the spider at `target_pos` for Ellie's 3-beat impale!
func begin_finisher_impale(stand_pos: Vector2, target_pos: Vector2, _sec: int, duration: float) -> void:
	CombatCoordinator.release_melee_token(self, _target)
	if _tether != null and is_instance_valid(_tether):
		_tether.sever()
	global_position = target_pos
	velocity = Vector2.ZERO
	attack_origin = stand_pos
	var to_attacker: Vector2 = stand_pos - target_pos
	if to_attacker.length_squared() > 0.25:
		heading = to_attacker.angle()
		attack_dir = to_attacker.normalized()
	state = State.FINISHED_IMPALED
	finisher_ready_kind = 0
	_state_time = 0.0
	_zone.visible = false
	_zone_active = false
	_hurtbox.set_deferred("monitorable", false)
	_body_shape.set_deferred("disabled", true)
	_rig.finisher_stage = 0
	_rig.start_pose(SpiderRig.Pose.IMPALED, duration, 0.0)


func on_finisher_beat(beat_idx: int) -> void:
	if state != State.FINISHED_IMPALED:
		return
	_rig.finisher_stage = beat_idx
	if beat_idx == 1:
		_rig.hit_flash(-attack_dir, true)
		_trail.leave(global_position, true)
		if _bridge != null:
			_bridge.on_hit_splatter(global_position, attack_origin, true)
	elif beat_idx == 2:
		_rig.hit_flash(-attack_dir, true)
		var perp: Vector2 = attack_dir.orthogonal() * 6.0
		_trail.leave(global_position + perp, true)
		_trail.leave(global_position - perp, true)
		if _bridge != null:
			_bridge.on_hit_splatter(global_position, attack_origin, true)
	elif beat_idx == 3:
		_rig.hit_flash(attack_dir, true)
		_rig.core_break = true


func complete_finisher_kill(attacker_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _health.current > 0.0:
		_health.hitters[attacker_peer_id] = true
		_health.kill(attack_origin, attacker_peer_id)


func _on_died() -> void:
	if multiplayer.is_server():
		CombatCoordinator.notify_ally_death(self, get_tree())
		_set_state(State.DEAD)
	if _tether != null and is_instance_valid(_tether):
		_tether.sever()
	_hurtbox.set_deferred("collision_layer", 0)
	_body_shape.set_deferred("disabled", true)
	if not _rig.core_break:
		_death_fx.restart() ## the finisher's Kern-Bruch brings its own (FinisherFx)
	_trail.infest(global_position)
	if _bridge != null:
		_bridge.on_ground_burst(global_position, 28.0, 1.0)
	if multiplayer.is_server():
		await get_tree().create_timer(DEATH_SECONDS + 0.3).timeout
		if is_inside_tree():
			queue_free()
