class_name AurelithFight
extends Node
## Host-authoritative 3-stage pinnacle boss choreography for `Aurelith, Herz des Sonnenquarzes`
## (`docs/enemies/boss_aurelith.md`, Pakete 3, 4 & 5).
##
## Architecture:
## - Lives as a child of `Aurelith` on every peer; drives `AurelithField` (ground transformations,
##   standing sintered-quartz pillars, unlit 3/4 telegraphs, beams, tethers, tsunami crests & `Resonanz-Kerne`).
## - Host decides acts & targets and broadcasts deterministic RPCs (`@rpc("authority", "call_local", "reliable")`).
## - Pure weapon & spell parity (`pickaxe_override = 1.0` on every battle `QuartzGolem`, layer-5 `Resonanz-Kern`
##   reflection for all weapons & wand spells).
## - Stage 1 (`100%..66%`): `GAUNTLET_SLAM`, `FAULT_SLAM`, `SINKHOLE_CAST`, `BLADE_CLEAVE`, `GEODE_TETHER`.
## - Stage 2 (`66%..33%`, `DER MANTEL BRICHT`): `SOLAR_BEAM` (with 3-way golem prism refraction & pillar cover),
##   `TEMPLE_PRESS`, `GUARDIAN_TRIAD`, `MELT_NOVA`, `SAND_MIRAGE`.
## - Stage 3 (`33%..0%`, `DIE SONNENSCHMELZE`): `DUNE_TSUNAMI` (wind-shadow cover), `TWIN_BLADES`,
##   `ARMILLARY_COURT`, `ZENITH_NOVA` (interrupted by 3 reflected `Resonanz-Kerne` -> `OVERHEAT STAGGER`!).

enum SubMode {
	HOVER,
	ACT,
	TRANSITION,
	STAGGER,
	DEAD,
}

enum Act {
	NONE,
	# Stage 1
	GAUNTLET_SLAM,
	FAULT_SLAM,
	SINKHOLE_CAST,
	BLADE_CLEAVE,
	GEODE_TETHER,
	# Stage 2
	SOLAR_BEAM,
	TEMPLE_PRESS,
	GUARDIAN_TRIAD,
	MELT_NOVA,
	SAND_MIRAGE,
	# Stage 3
	DUNE_TSUNAMI,
	TWIN_BLADES,
	ARMILLARY_COURT,
	ZENITH_NOVA,
}

const SQUASH: float = 0.72
const PLAYER_HURT_LAYER: int = 1 << 5

var boss: Aurelith
var field: AurelithField
var sub_mode: SubMode = SubMode.HOVER
var act: Act = Act.NONE
var phase: int = 0 ## 0 = Stage 1 (100..66%), 1 = Stage 2 (66..33%), 2 = Stage 3 (33..0%)

var _host: bool = false
var _center: Vector2 = Vector2.ZERO
var _radii: Vector2 = Vector2(290.0, 210.0)
var _aura: BossAura
var _sfx_pool: Array[AudioStreamPlayer2D] = []
var _sfx_idx: int = 0
var _audio_cache: Dictionary = {}

var _t: float = 0.0
var _gap: float = 1.85
var _last_act: Act = Act.NONE
var _step_done: Dictionary = {}
var _act_p0: Vector2 = Vector2.ZERO
var _act_p1: Vector2 = Vector2.ZERO
var _act_f0: float = 0.0
var _act_seed: int = 1
var _transition_target: int = 1
var _transition_scream_at: float = 1.45
var _transition_end_at: float = 4.15
var _phase_screen: BossPhaseScreen = null

var _next_pillar_id: int = 0
var _next_core_id: int = 0
var _armor_crack_left: float = 0.0
var _zenith_cd: float = 5.0
var _zenith_cores_hit: int = 0
var _beam_plate_cd: float = 0.0
var _triad_left: float = 0.0
var _tether_left: float = 0.0
var _summon_cd: float = 0.0

var _battle_golems: Array[Node2D] = []
var _delayed_xbombs: Array[Dictionary] = [] ## {pos, ang, detonate_at}
var _delayed_bolts: Array[Dictionary] = [] ## {pos, hit_at}
var _tick_grace: Dictionary = {} ## peer_id_key -> seconds remaining


func setup(p_boss: Aurelith, p_field: AurelithField) -> void:
	boss = p_boss
	field = p_field
	_host = multiplayer.is_server()
	_center = boss.centre()
	_radii = field.arena_radii
	name = "AurelithFight"

	for i: int in 4:
		var sp: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		sp.max_distance = 880.0
		sp.attenuation = 1.35
		add_child(sp)
		_sfx_pool.append(sp)

	if field != null and not field.core_struck_boss.is_connected(_on_core_struck_boss):
		field.core_struck_boss.connect(_on_core_struck_boss)

	_aura = BossAura.begin(self)
	_apply_phase_floor()


func _exit_tree() -> void:
	if is_instance_valid(_phase_screen):
		_phase_screen._finish()
		_phase_screen = null
	_clear_battle_golems()
	if is_instance_valid(field):
		field.clear_all()


func aura_level() -> float:
	if boss == null or boss.mode != Aurelith.Mode.ACTIVE or sub_mode == SubMode.DEAD:
		return 0.0
	if phase >= 2:
		return 1.12
	if phase == 1:
		return 0.68
	return 0.28


func active_battle_golem_count() -> int:
	_prune_battle_golems()
	return _battle_golems.size()


func zenith_cores_reflected() -> int:
	return _zenith_cores_hit


func on_boss_died() -> void:
	sub_mode = SubMode.DEAD
	act = Act.NONE
	if is_instance_valid(_phase_screen):
		_phase_screen._finish()
		_phase_screen = null
	if boss != null and boss.rig() != null:
		boss.rig().set_detached_fist(false, false)
		boss.rig().set_detached_fist(true, false)
		boss.rig().twin_blades = false
		boss.rig().charge_intensity = 0.0
		boss.rig().modulate.a = 1.0
	_clear_battle_golems()
	if is_instance_valid(field):
		field.clear_all()


# --- Main Frame & Host Combat Loop ---------------------------------------------------------------------------------


func step_visuals(delta: float) -> void:
	if sub_mode == SubMode.DEAD or boss == null or boss.mode != Aurelith.Mode.ACTIVE:
		return
	_update_live_tether_visuals()
	if sub_mode == SubMode.TRANSITION and is_instance_valid(field):
		field.set_zenith_seal(true, boss.global_position, clampf(_t / maxf(_transition_scream_at, 0.2), 0.0, 1.0))
	elif sub_mode == SubMode.ACT and act == Act.SOLAR_BEAM:
		_step_solar_beam_shared(delta, false)
	elif sub_mode == SubMode.ACT and act == Act.DUNE_TSUNAMI:
		_step_tsunami_shared(false)
	elif sub_mode == SubMode.ACT and act == Act.SAND_MIRAGE and _t < 1.05 and is_instance_valid(field):
		field.step_mirage_trail(boss.global_position, delta)
	elif sub_mode == SubMode.ACT and act in [Act.ARMILLARY_COURT, Act.ZENITH_NOVA] and is_instance_valid(field):
		var dur_z: float = 4.0 if act == Act.ARMILLARY_COURT else 9.2
		field.set_zenith_seal(true, boss.global_position, clampf(_t / dur_z, 0.0, 1.0))


func step_host(delta: float) -> void:
	if not _host or boss == null or boss.mode != Aurelith.Mode.ACTIVE or sub_mode == SubMode.DEAD:
		return

	_zenith_cd = maxf(0.0, _zenith_cd - delta)
	_summon_cd = maxf(0.0, _summon_cd - delta)
	_triad_left = maxf(0.0, _triad_left - delta)
	_tether_left = maxf(0.0, _tether_left - delta)
	if _armor_crack_left > 0.0:
		_armor_crack_left = maxf(0.0, _armor_crack_left - delta)
	_tick_cooldowns(delta)
	_prune_battle_golems()
	_step_delayed_hazards()
	_step_tether_and_triad_damage()

	# Update armor multiplier (1.65 in Overheat Stagger, 1.35 after Resonance Core hit, 1.0 normal)
	if sub_mode == SubMode.STAGGER:
		boss.armour = 1.65
	elif _armor_crack_left > 0.0:
		boss.armour = 1.35
	else:
		boss.armour = 1.0

	# Track leash / wipe reset clock across ALL combat sub-modes (even mid-act or mid-stagger)
	var leash_target: Player = boss._nearest_living_player(float(boss._arena_spec.get("leash", 640.0)))
	if leash_target == null:
		boss._away_clock += delta
		if boss._away_clock >= float(boss._arena_spec.get("reset_seconds", 8.0)):
			boss.request_reset()
			return
	else:
		boss._away_clock = 0.0

	# Check phase health floors (66% -> Stage 2, 33% -> Stage 3) whenever not already transitioning
	if sub_mode in [SubMode.HOVER, SubMode.STAGGER] or (sub_mode == SubMode.ACT and act != Act.SAND_MIRAGE):
		var hp_ratio: float = boss.health_now() / maxf(boss.max_health(), 1.0)
		if phase == 0 and hp_ratio <= 0.6605:
			_begin_transition_host(1)
			return
		elif phase == 1 and hp_ratio <= 0.3305:
			_begin_transition_host(2)
			return

	match sub_mode:
		SubMode.HOVER:
			_step_hover_host(delta)
		SubMode.ACT:
			_step_act_host(delta)
		SubMode.TRANSITION:
			_step_transition_host(delta)
		SubMode.STAGGER:
			_step_stagger_host(delta)


func step_client(delta: float) -> void:
	if _host or boss == null or boss.mode != Aurelith.Mode.ACTIVE or sub_mode == SubMode.DEAD:
		return
	if sub_mode in [SubMode.ACT, SubMode.TRANSITION, SubMode.STAGGER]:
		_t += delta


func _step_hover_host(delta: float) -> void:
	var target: Player = boss._nearest_living_player(float(boss._arena_spec.get("leash", 640.0)))
	if target == null:
		boss.velocity = boss.velocity.move_toward(Vector2.ZERO, delta * 180.0)
		return
	_hover_toward_combat_ring(target.global_position, delta, 1.0)

	_gap -= delta
	if _gap <= 0.0:
		var chosen: Act = _pick_next_act(target)
		_start_act_host(chosen, target)


func _hover_toward_combat_ring(goal_pos: Vector2, delta: float, speed_mul: float) -> void:
	var to_t: Vector2 = goal_pos - boss.global_position
	var dist: float = to_t.length()
	if dist > 1.0:
		boss.heading = lerp_angle(boss.heading, to_t.angle(), delta * 3.1)
	var hover_spd: float = float(boss._def.get("hover_speed", 54.0)) * (1.0 + 0.08 * float(phase)) * speed_mul
	var want_vel: Vector2 = Vector2.ZERO
	if dist > 148.0:
		want_vel = to_t.normalized() * hover_spd
	elif dist < 86.0 and dist > 1.0:
		want_vel = -to_t.normalized() * (hover_spd * 0.62)
	boss.velocity = boss.velocity.move_toward(want_vel, delta * 145.0)
	_move_boss_clamped(boss.global_position + boss.velocity * delta)
	var want_pose: AurelithRig.Pose = AurelithRig.Pose.MOVE if boss.velocity.length() > 10.0 else AurelithRig.Pose.IDLE
	if boss.rig()._pose != want_pose and boss.rig()._pose in [AurelithRig.Pose.IDLE, AurelithRig.Pose.MOVE]:
		boss._sync_pose.rpc(int(want_pose))


func _glide_boss_toward(goal_pos: Vector2, speed: float, delta: float) -> void:
	var next_p: Vector2 = boss.global_position.move_toward(goal_pos, speed * delta)
	boss.velocity = (next_p - boss.global_position) / maxf(delta, 0.001)
	_move_boss_clamped(next_p)


func _move_boss_clamped(next_pos: Vector2) -> void:
	var lim: Vector2 = _radii * 0.76
	var rel: Vector2 = (next_pos - _center) / lim
	if rel.length_squared() > 1.0:
		next_pos = _center + rel.normalized() * lim
		boss.velocity = Vector2.ZERO
	boss.global_position = next_pos


# --- Act Selection & Public Test/Dev Controls ----------------------------------------------------------------------


func _pick_next_act(target: Player) -> Act:
	var dist: float = boss.global_position.distance_to(target.global_position)
	var pool: Array[Act] = []
	var cores_n: int = field.active_core_ids().size() if is_instance_valid(field) else 0
	if phase == 0:
		pool = [Act.GAUNTLET_SLAM, Act.FAULT_SLAM, Act.SINKHOLE_CAST, Act.BLADE_CLEAVE]
		if dist <= 118.0:
			pool.append(Act.BLADE_CLEAVE)
		if _summon_cd <= 0.0 and active_battle_golem_count() == 0 and cores_n < 2:
			pool.append(Act.GEODE_TETHER)
	elif phase == 1:
		pool = [Act.SOLAR_BEAM, Act.TEMPLE_PRESS, Act.MELT_NOVA, Act.SAND_MIRAGE]
		if _summon_cd <= 0.0 and active_battle_golem_count() <= 1 and cores_n < 2:
			pool.append(Act.GUARDIAN_TRIAD)
	else:
		if _zenith_cd <= 0.0:
			return Act.ZENITH_NOVA
		pool = [Act.DUNE_TSUNAMI, Act.TWIN_BLADES, Act.ARMILLARY_COURT]
		if field.pillar_positions().size() < 2:
			pool.append(Act.DUNE_TSUNAMI)

	var filtered: Array[Act] = []
	for cand: Act in pool:
		if cand != _last_act:
			filtered.append(cand)
	if filtered.is_empty():
		filtered = pool
	return filtered[randi() % filtered.size()]


func force_act(act_id: Act) -> void:
	if not _host or boss == null or sub_mode == SubMode.DEAD:
		return
	var target: Player = boss._nearest_living_player(900.0)
	_start_act_host(act_id, target)


func force_phase(target_phase: int, skip_transition: bool = false) -> void:
	if not _host or boss == null or sub_mode == SubMode.DEAD:
		return
	var clamped_p: int = clampi(target_phase, 0, 2)
	if skip_transition:
		var target_ratio: float = 1.0 if clamped_p == 0 else (0.64 if clamped_p == 1 else 0.31)
		boss._health.floor_value = 0.0
		if boss._health.current > boss._health.max_health * target_ratio:
			boss._health.current = boss._health.max_health * target_ratio
		_rpc_set_phase_direct.rpc(clamped_p)
	else:
		var ratio_t: float = 0.66 if clamped_p == 1 else 0.33
		boss._health.floor_value = boss._health.max_health * ratio_t
		if boss._health.current > boss._health.floor_value:
			boss._health.current = boss._health.floor_value
		_begin_transition_host(clamped_p)


@rpc("authority", "call_local", "reliable")
func _rpc_set_phase_direct(new_phase: int) -> void:
	phase = clampi(new_phase, 0, 2)
	sub_mode = SubMode.HOVER
	act = Act.NONE
	_gap = 0.45
	if boss != null:
		boss.act_hittable = true
		boss.rig().set_detached_fist(true, false)
		boss.rig().twin_blades = (phase >= 2)
		boss.rig().charge_intensity = 0.0
		boss.rig().modulate.a = 1.0
		boss.rig().prism_release = 1.0 if phase >= 1 else 0.0
		boss.rig().storm_ascension = 1.0 if phase >= 2 else 0.0
		boss.rig().start_pose(AurelithRig.Pose.IDLE, 1.0)
	_apply_phase_floor()


func _apply_phase_floor() -> void:
	if boss == null or boss._health == null:
		return
	if phase == 0:
		boss._health.floor_value = boss._health.max_health * 0.66
	elif phase == 1:
		boss._health.floor_value = boss._health.max_health * 0.33
	else:
		boss._health.floor_value = 0.0


# --- Phase Transitions (66% `DER MANTEL BRICHT` & 33% `DIE SONNENSCHMELZE`) ----------------------------------------


func _transition_cfg(next_phase: int) -> Dictionary:
	var fight_cfg: Dictionary = (boss._def.get("fight", {}) as Dictionary) if boss != null else {}
	var key: String = "transition1" if next_phase == 1 else "transition2"
	var cfg: Dictionary = fight_cfg.get(key, {}) as Dictionary
	if not cfg.is_empty():
		return cfg
	if next_phase == 1:
		return {"text": "MANTELBRUCH", "scream_at": 1.45, "title_at": 1.95, "leave_at": 3.55, "end": 4.15, "hot": 0.0}
	return {"text": "SONNENSCHMELZE", "scream_at": 1.55, "title_at": 2.05, "leave_at": 3.75, "end": 4.35, "hot": 0.15}


func _begin_transition_host(next_phase: int) -> void:
	_clear_battle_golems()
	_triad_left = 0.0
	_tether_left = 0.0
	_summon_cd = maxf(_summon_cd, 8.0)
	_zenith_cd = 7.5 if next_phase == 2 else _zenith_cd
	_rpc_begin_transition.rpc(next_phase)


@rpc("authority", "call_local", "reliable")
func _rpc_begin_transition(next_phase: int) -> void:
	sub_mode = SubMode.TRANSITION
	act = Act.NONE
	_transition_target = next_phase
	_t = 0.0
	_triad_left = 0.0
	_tether_left = 0.0
	_step_done.clear()
	_delayed_xbombs.clear()
	_delayed_bolts.clear()
	var tr: Dictionary = _transition_cfg(next_phase)
	_transition_scream_at = float(tr.get("scream_at", 1.45 if next_phase == 1 else 1.55))
	_transition_end_at = float(tr.get("end", 4.15 if next_phase == 1 else 4.35))
	# Wipe all lingering hazards & clutter so the entire arena focuses cleanly on Aurelith's transformation
	if is_instance_valid(field):
		field.clear_all()
		if boss != null:
			field.set_zenith_seal(true, boss.global_position, 0.25)
	if boss != null:
		boss.act_hittable = false
		boss.velocity = Vector2.ZERO
		boss.rig().set_detached_fist(false, false)
		boss.rig().set_detached_fist(true, false)
		boss.rig().modulate.a = 1.0
		boss.rig().charge_intensity = 0.90
		boss.rig().start_pose(AurelithRig.Pose.SINKHOLE_CAST if next_phase == 1 else AurelithRig.Pose.ZENITH_CHARGE, _transition_end_at)
	if DisplayServer.get_name() != "headless" and boss != null:
		if is_instance_valid(_phase_screen):
			_phase_screen._finish()
			_phase_screen = null
		for player: Player in Player.all:
			if player != null and is_instance_valid(player) and player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(_center) < 720.0:
				_phase_screen = BossPhaseScreen.play(boss, player, String(tr.get("text", "DER MANTEL BRICHT")), tr)
				break
	_play_cue("geode" if next_phase == 1 else "zenith", -1.5, 0.90)


func _step_transition_host(delta: float) -> void:
	_t += delta
	_glide_boss_toward(_center, 185.0, delta)
	boss.heading = lerp_angle(boss.heading, PI * 0.5, delta * 4.5)

	if not _step_done.has(1) and _t >= _transition_scream_at:
		_step_done[1] = true
		_rpc_transition_burst.rpc(_transition_target)
		# Non-lethal radial shockwave pushing nearby players safely clear of the core
		for p: Player in _living_players():
			if p.global_position.distance_to(boss.global_position) <= 165.0:
				p.health.take_survivable(4.0, boss.global_position, 220.0)

	if _t >= _transition_end_at:
		_rpc_finish_transition.rpc(_transition_target)


@rpc("authority", "call_local", "reliable")
func _rpc_transition_burst(next_phase: int) -> void:
	phase = next_phase
	_apply_phase_floor()
	if _aura != null:
		_aura.kick(0.92 if next_phase == 1 else 1.0)
	if is_instance_valid(field) and boss != null:
		var bpos: Vector2 = boss.global_position
		ShockRing.burst(field, bpos - _center, 185.0 if next_phase == 1 else 225.0, 0.92)
		ShockRing.burst(field, bpos - _center, 95.0 if next_phase == 1 else 115.0, 0.72)
		field.spawn_burst(bpos + Vector2(0.0, -48.0), 22, AurelithField.VIOLET_ARC if next_phase == 1 else AurelithField.GOLD_WARN)
		field.spawn_shrapnel(bpos + Vector2(0.0, -24.0), 12, 1.08)
		if next_phase == 1:
			for arm_i: int in 2:
				var sa: float = float(arm_i) * PI * 0.5 + PI * 0.25
				var sd: Vector2 = Vector2(cos(sa) * 74.0, sin(sa) * 74.0 * SQUASH)
				field.add_crystal_seam(bpos - sd, bpos + sd, 1.9)
		else:
			field.add_quartz_plate(bpos, 48.0, 12.0)
			for b_i: int in 3:
				var ba: float = TAU * float(b_i) / 3.0 - PI * 0.5
				var bp: Vector2 = bpos + Vector2(cos(ba) * 62.0, sin(ba) * 62.0 * SQUASH)
				field.spawn_sky_bolt(bp, AurelithField.GOLD_WARN if b_i != 1 else AurelithField.TURQ_SAFE, 0.68)
	if boss != null:
		boss.shake_near(boss.global_position, 2.9 if next_phase == 1 else 3.5)
		boss.rig().hit_flash()
		boss.rig().twin_blades = (next_phase >= 2)
		boss.rig().start_pose(AurelithRig.Pose.BLADE_CLEAVE if next_phase == 1 else AurelithRig.Pose.ZENITH_CHARGE, 1.8)
	_play_cue("mantle" if next_phase == 1 else "meltdown", 0.0, 0.94)


@rpc("authority", "call_local", "reliable")
func _rpc_finish_transition(next_phase: int) -> void:
	phase = next_phase
	_apply_phase_floor()
	sub_mode = SubMode.HOVER
	act = Act.NONE
	_gap = 2.15
	if is_instance_valid(field):
		field.set_zenith_seal(false)
	if boss != null:
		boss.act_hittable = true
		boss.rig().charge_intensity = 0.0
		boss.rig().twin_blades = (phase >= 2)
		boss.rig().start_pose(AurelithRig.Pose.IDLE, 1.0)


# --- Act Dispatch & Shared Execution -------------------------------------------------------------------------------


func _start_act_host(act_id: Act, target: Player) -> void:
	_last_act = act_id
	var t_pos: Vector2 = target.global_position if target != null else (_center + Vector2(0.0, 96.0))
	var seed_v: int = (randi() & 0x7fffffff)
	var p0: Vector2 = boss.global_position
	var p1: Vector2 = field.clamp_in_arena(t_pos, 0.82)
	var f0: float = (p1 - p0).angle()
	if p1.distance_to(p0) < 4.0:
		f0 = boss.heading

	match act_id:
		Act.GEODE_TETHER, Act.GUARDIAN_TRIAD:
			_summon_cd = 24.0
		Act.SOLAR_BEAM:
			var sweep_sign: float = 1.0 if (seed_v % 2 == 0) else -1.0
			f0 = (p1 - p0).angle() - sweep_sign * 0.68
			p1 = Vector2(sweep_sign, 0.0)
		Act.TEMPLE_PRESS:
			var perp_a: float = (p1 - p0).angle() + PI * 0.5
			f0 = perp_a
		Act.SAND_MIRAGE:
			var behind: Vector2 = t_pos + (t_pos - p0).normalized() * 68.0
			p1 = field.clamp_in_arena(behind, 0.76)
			f0 = (t_pos - p1).angle()
		Act.DUNE_TSUNAMI:
			var cardinal: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]
			var d1: Vector2 = cardinal[seed_v % 2]
			var d2: Vector2 = cardinal[2 + ((seed_v / 2) % 2)]
			p0 = d1
			p1 = d2
			_ensure_tsunami_breakwaters_host()
		Act.ZENITH_NOVA:
			_zenith_cd = 26.0
			_zenith_cores_hit = 0

	_rpc_begin_act.rpc(int(act_id), seed_v, p0, p1, f0)


@rpc("authority", "call_local", "reliable")
func _rpc_begin_act(act_id: int, seed_v: int, p0: Vector2, p1: Vector2, f0: float) -> void:
	if sub_mode == SubMode.DEAD or boss == null:
		return
	sub_mode = SubMode.ACT
	act = act_id as Act
	_t = 0.0
	_step_done.clear()
	_act_seed = seed_v
	_act_p0 = p0
	_act_p1 = p1
	_act_f0 = f0
	boss.velocity = Vector2.ZERO

	match act:
		Act.GAUNTLET_SLAM:
			boss.heading = f0
			boss.rig().start_pose(AurelithRig.Pose.GAUNTLET_SLAM, 1.50)
			boss.rig().set_detached_fist(true, true, p0.lerp(p1, 0.35), 34.0)
			field.warn_circle(p1, 56.0, 1.05)
			_play_cue("charge", -2.0, 0.94)
		Act.FAULT_SLAM:
			boss.heading = f0
			boss.rig().start_pose(AurelithRig.Pose.FAULT_SLAM, 1.85)
			for k: int in [-1, 0, 1]:
				var a_k: float = f0 + float(k) * 0.48
				var tip: Vector2 = field.clamp_in_arena(p0 + Vector2(cos(a_k) * 212.0, sin(a_k) * 212.0 * SQUASH), 0.90)
				field.warn_box(p0 + Vector2(cos(a_k) * 26.0, sin(a_k) * 26.0 * SQUASH), tip, 18.0, 1.10)
			_play_cue("charge", -3.0, 0.86)
		Act.SINKHOLE_CAST:
			boss.heading = f0
			boss.rig().start_pose(AurelithRig.Pose.SINKHOLE_CAST, 1.85)
			field.add_quicksand(p1, 88.0, 6.2, 40.0)
			field.warn_circle(p1, 44.0, 1.45, 0.0, AurelithField.GOLD_WARN)
			_play_cue("quicksand", -1.5, 0.96)
		Act.BLADE_CLEAVE:
			boss.heading = f0
			boss.rig().start_pose(AurelithRig.Pose.BLADE_CLEAVE, 1.45)
			field.warn_cone(p0, f0, 1.22, 98.0, 0.92)
			_play_cue("blade", -1.5, 0.94)
		Act.GEODE_TETHER:
			boss.heading = f0
			boss.rig().start_pose(AurelithRig.Pose.SINKHOLE_CAST, 1.50)
			_play_cue("geode", -1.5, 0.98)
		Act.SOLAR_BEAM:
			boss.heading = f0
			boss.rig().start_pose(AurelithRig.Pose.CHEST_BEAM, 3.65)
			boss.rig().charge_intensity = 0.85
			var aim_end: Vector2 = p0 + Vector2.from_angle(f0) * 310.0
			field.warn_box(p0, aim_end, 11.0, 1.18, AurelithField.GOLD_WARN)
			_play_cue("beam", -1.0, 0.96)
		Act.TEMPLE_PRESS:
			boss.heading = (p1 - boss.global_position).angle()
			boss.rig().start_pose(AurelithRig.Pose.CLAP_PREP, 1.32)
			var axis: Vector2 = Vector2.from_angle(f0)
			var tang: Vector2 = Vector2(-axis.y, axis.x)
			field.add_temple_press_visual(p1, axis, 118.0, 56.0, 1.32)
			field.warn_box(p1 - tang * 59.0, p1 + tang * 59.0, 52.0, 1.32)
			_play_cue("press", -1.5, 0.94)
		Act.GUARDIAN_TRIAD:
			boss.rig().start_pose(AurelithRig.Pose.SINKHOLE_CAST, 1.65)
			_play_cue("geode", -1.5, 0.92)
		Act.MELT_NOVA:
			boss.rig().start_pose(AurelithRig.Pose.SINKHOLE_CAST, 2.95)
			field.warn_circle(boss.global_position, 82.0, 1.05)
			_play_cue("charge", -2.0, 1.02)
		Act.SAND_MIRAGE:
			boss.act_hittable = false
			boss.rig().modulate.a = 0.28
			boss.rig().start_pose(AurelithRig.Pose.MOVE, 1.05)
			field.warn_circle(p1, 84.0, 1.05, 0.0, AurelithField.GOLD_WARN)
			_play_cue("mirage", -1.0, 0.98)
		Act.DUNE_TSUNAMI:
			boss.rig().start_pose(AurelithRig.Pose.SINKHOLE_CAST, 5.1)
			_play_cue("tsunami", 0.0, 0.94)
		Act.TWIN_BLADES:
			boss.rig().twin_blades = true
			boss.rig().start_pose(AurelithRig.Pose.BLADE_CLEAVE, 0.90)
			_play_cue("blade", -1.0, 1.02)
		Act.ARMILLARY_COURT:
			boss.rig().start_pose(AurelithRig.Pose.ZENITH_CHARGE, 4.1)
			field.warn_armillary(4.0, float(seed_v % 628) * 0.01)
			_play_cue("surge", -1.5, 0.94)
		Act.ZENITH_NOVA:
			boss.rig().start_pose(AurelithRig.Pose.ZENITH_CHARGE, 9.5)
			boss.rig().charge_intensity = 1.0
			field.warn_circle(_center, 278.0, 9.2, 0.0, AurelithField.GOLD_WARN)
			_play_cue("zenith", 0.0, 0.94)


func _step_act_host(delta: float) -> void:
	_t += delta
	match act:
		Act.GAUNTLET_SLAM:
			_host_gauntlet_slam()
		Act.FAULT_SLAM:
			_host_fault_slam()
		Act.SINKHOLE_CAST:
			_host_sinkhole_cast()
		Act.BLADE_CLEAVE:
			_host_blade_cleave(delta)
		Act.GEODE_TETHER:
			_host_geode_tether()
		Act.SOLAR_BEAM:
			_host_solar_beam(delta)
		Act.TEMPLE_PRESS:
			_host_temple_press()
		Act.GUARDIAN_TRIAD:
			_host_guardian_triad()
		Act.MELT_NOVA:
			_host_melt_nova(delta)
		Act.SAND_MIRAGE:
			_host_sand_mirage(delta)
		Act.DUNE_TSUNAMI:
			_host_dune_tsunami()
		Act.TWIN_BLADES:
			_host_twin_blades(delta)
		Act.ARMILLARY_COURT:
			_host_armillary_court(delta)
		Act.ZENITH_NOVA:
			_host_zenith_nova(delta)


func _finish_act_host(recover_gap: float) -> void:
	_rpc_end_act.rpc(recover_gap)


@rpc("authority", "call_local", "reliable")
func _rpc_end_act(recover_gap: float) -> void:
	if sub_mode == SubMode.DEAD or boss == null:
		return
	sub_mode = SubMode.HOVER
	act = Act.NONE
	_gap = recover_gap
	if is_instance_valid(field):
		field.set_solar_beam(false)
		field.set_gauntlet_anchor(false)
		field.set_tsunami_wave(false)
		field.set_zenith_seal(false)
	boss.act_hittable = true
	boss.rig().set_detached_fist(true, false)
	boss.rig().twin_blades = (phase >= 2)
	boss.rig().charge_intensity = 0.0
	boss.rig().modulate.a = 1.0
	boss.rig().start_pose(AurelithRig.Pose.IDLE, 1.0)


# --- Stage 1 Acts --------------------------------------------------------------------------------------------------


func _host_gauntlet_slam() -> void:
	if not _step_done.has(1) and _t >= 1.05:
		_step_done[1] = true
		_rpc_gauntlet_impact.rpc(_act_p1)
		_hit_players_ellipse(_act_p1, 56.0, 0.0, 26.0, 175.0)
		for pid: int in field.find_pillars_near(_act_p1, 38.0):
			_rpc_shatter_pillar.rpc(pid, true)
	if not _step_done.has(2) and _t >= 1.85:
		_step_done[2] = true
		_rpc_gauntlet_warn_yank.rpc(_act_p1, boss.global_position)
	if not _step_done.has(3) and _t >= 2.63:
		_step_done[3] = true
		_rpc_gauntlet_yank.rpc(boss.global_position)
		_hit_players_box(_act_p1, boss.global_position, 22.0, 22.0, -180.0)
	if _t >= 3.05:
		_finish_act_host(2.30)


@rpc("authority", "call_local", "reliable")
func _rpc_gauntlet_impact(at_pos: Vector2) -> void:
	if boss != null:
		boss.rig().set_detached_fist(true, true, at_pos, 0.0)
		boss.shake_near(at_pos, 2.2)
	if is_instance_valid(field):
		field.set_gauntlet_anchor(true, boss.global_position if boss != null else _center, at_pos, 2.05)
		field.add_quartz_plate(at_pos, 24.0, 8.5)
		field.spawn_burst(at_pos, 10, AurelithField.GOLD_WARN)
		field.spawn_shrapnel(at_pos, 5, 1.0)
		ShockRing.burst(field, at_pos - _center, 56.0, 0.72)
	_play_cue("slam", 0.0, 0.90)


@rpc("authority", "call_local", "reliable")
func _rpc_gauntlet_warn_yank(from_pos: Vector2, to_pos: Vector2) -> void:
	if is_instance_valid(field):
		field.warn_box(from_pos, to_pos, 22.0, 0.78)


@rpc("authority", "call_local", "reliable")
func _rpc_gauntlet_yank(to_pos: Vector2) -> void:
	if is_instance_valid(field):
		field.trigger_gauntlet_yank(to_pos, 0.34)
	if boss != null:
		boss.rig().set_detached_fist(true, false)
	_play_cue("yank", -1.0, 1.0)


func _host_fault_slam() -> void:
	if not _step_done.has(0) and _t >= 1.10:
		_step_done[0] = true
		for pid: int in field.find_pillars_near(_act_p0, 54.0):
			_rpc_shatter_pillar.rpc(pid, true)
		_rpc_fault_step.rpc(0, _act_p0, _act_f0, -1, -1)
	for step_i: int in range(1, 5):
		var at_t: float = 1.10 + float(step_i) * 0.20
		if not _step_done.has(step_i) and _t >= at_t:
			_step_done[step_i] = true
			var pid_l: int = -1
			var pid_r: int = -1
			if step_i == 4:
				var cur_pillars: int = field.pillar_positions().size() if is_instance_valid(field) else 0
				if cur_pillars < 2:
					_next_pillar_id += 1
					pid_l = _next_pillar_id
			_rpc_fault_step.rpc(step_i, _act_p0, _act_f0, pid_l, pid_r)
			var dist_k: float = float(step_i) * 51.0
			for branch: int in [-1, 0, 1]:
				var ang: float = _act_f0 + float(branch) * 0.48
				var pt: Vector2 = field.clamp_in_arena(_act_p0 + Vector2(cos(ang) * dist_k, sin(ang) * dist_k * SQUASH), 0.88)
				_hit_players_ellipse(pt, 26.0, 0.0, 22.0, 130.0)
	if _t >= 2.20:
		_finish_act_host(2.35)


@rpc("authority", "call_local", "reliable")
func _rpc_fault_step(step_i: int, origin: Vector2, base_ang: float, pid_l: int, pid_r: int) -> void:
	if step_i == 0:
		if boss != null:
			boss.shake_near(origin, 2.3)
		_play_cue("slam", 0.0, 0.88)
		return
	var dist_k: float = float(step_i) * 51.0
	var prev_k: float = maxf(16.0, float(step_i - 1) * 51.0)
	for branch: int in [-1, 0, 1]:
		var ang: float = base_ang + float(branch) * 0.48
		var prev_pt: Vector2 = field.clamp_in_arena(origin + Vector2(cos(ang) * prev_k, sin(ang) * prev_k * SQUASH), 0.88)
		var pt: Vector2 = field.clamp_in_arena(origin + Vector2(cos(ang) * dist_k, sin(ang) * dist_k * SQUASH), 0.88)
		if is_instance_valid(field):
			field.add_crystal_seam(prev_pt, pt, 0.95)
			if step_i == 4:
				field.add_quartz_plate(pt, 24.0, 9.0)
			field.spawn_burst(pt, 4, AurelithField.TURQ_SAFE)
			field.spawn_shrapnel(pt, 2, 0.82)
			if step_i == 4 and branch == -1 and pid_l > 0:
				field.spawn_pillar(pid_l, pt, 20.0)
			elif step_i == 4 and branch == 1 and pid_r > 0:
				field.spawn_pillar(pid_r, pt, 20.0)
	_play_cue("erupt", -3.0, 0.92 + float(step_i) * 0.06)


func _host_sinkhole_cast() -> void:
	if not _step_done.has(1) and _t >= 1.45:
		_step_done[1] = true
		_next_pillar_id += 1
		_rpc_sinkhole_erupt.rpc(_next_pillar_id, _act_p1)
		_hit_players_ellipse(_act_p1, 46.0, 0.0, 28.0, 195.0)
	if _t >= 1.95:
		_finish_act_host(2.25)


@rpc("authority", "call_local", "reliable")
func _rpc_sinkhole_erupt(pillar_id: int, pos: Vector2) -> void:
	if is_instance_valid(field):
		field.spawn_pillar(pillar_id, pos, 22.0)
		ShockRing.burst(field, pos - _center, 52.0, 0.72)
	if boss != null:
		boss.shake_near(pos, 2.0)
	_play_cue("erupt", -0.5, 0.88)


func _host_blade_cleave(delta: float) -> void:
	if not _step_done.has(1) and _t >= 0.92:
		_step_done[1] = true
		var cleave_ang: float = _act_f0
		_hit_players_cone(boss.global_position, cleave_ang, 1.22, 98.0, 25.0, 165.0)
		var target: Player = boss._nearest_living_player(640.0)
		var line_ang: float = (target.global_position - boss.global_position).angle() if target != null else cleave_ang
		_act_f0 = line_ang
		var line_end: Vector2 = field.clamp_in_arena(boss.global_position + Vector2.from_angle(line_ang) * 138.0, 0.88)
		_act_p1 = line_end
		_rpc_blade_followup_warn.rpc(boss.global_position, line_end, line_ang, cleave_ang)
	if _t >= 0.92 and _t < 1.68:
		_glide_boss_toward(boss.global_position + Vector2.from_angle(_act_f0) * 14.0, 56.0, delta)
	if not _step_done.has(2) and _t >= 1.72:
		_step_done[2] = true
		_rpc_blade_overhead_slam.rpc(boss.global_position, _act_p1)
		_hit_players_box(boss.global_position, _act_p1, 20.0, 28.0, 185.0)
	if _t >= 2.15:
		_finish_act_host(2.30)


@rpc("authority", "call_local", "reliable")
func _rpc_blade_followup_warn(from_pos: Vector2, to_pos: Vector2, ang: float, cleave_ang: float) -> void:
	if boss != null:
		boss.heading = ang
		boss.rig().start_pose(AurelithRig.Pose.BLADE_CLEAVE, 0.85)
	if is_instance_valid(field):
		field.spawn_slash_arc(from_pos + Vector2(0.0, -28.0), cleave_ang, 1.18, 0.42, false)
		field.spawn_shrapnel(from_pos + Vector2.from_angle(cleave_ang) * 56.0, 4, 0.95)
		field.warn_box(from_pos, to_pos, 20.0, 0.78, AurelithField.GOLD_WARN)
		field.spawn_burst(from_pos + Vector2.from_angle(ang) * 48.0, 6, AurelithField.TURQ_SAFE)
	_play_cue("blade", -1.5, 1.05)


@rpc("authority", "call_local", "reliable")
func _rpc_blade_overhead_slam(from_pos: Vector2, to_pos: Vector2) -> void:
	if is_instance_valid(field):
		field.add_crystal_seam(from_pos, to_pos, 1.05)
		field.spawn_slash_arc(from_pos.lerp(to_pos, 0.55) + Vector2(0.0, -18.0), (to_pos - from_pos).angle(), 0.96, 0.36, true)
		field.spawn_shrapnel(to_pos, 5, 1.0)
		field.add_quartz_plate(from_pos.lerp(to_pos, 0.75), 24.0, 9.0)
		field.spawn_burst(to_pos, 6, AurelithField.GOLD_WARN)
	if boss != null:
		boss.shake_near(to_pos, 2.1)
	_play_cue("slam", -0.5, 0.95)


func _host_geode_tether() -> void:
	if not _step_done.has(1):
		_step_done[1] = true
		var max_g: int = 3 if _living_players().size() >= 3 else 2
		var count: int = clampi(max_g - active_battle_golem_count(), 0, max_g)
		var spots: PackedVector2Array = PackedVector2Array()
		for i: int in count:
			var ang: float = _act_f0 + (float(i) - float(count - 1) * 0.5) * 1.15
			var pt: Vector2 = field.clamp_in_arena(_center + Vector2(cos(ang) * 136.0, sin(ang) * 136.0 * SQUASH), 0.78)
			spots.append(pt)
		if not spots.is_empty():
			_rpc_geode_warn.rpc(spots)
		_step_done["spots"] = spots
	if not _step_done.has(2) and _t >= 1.08:
		_step_done[2] = true
		var spots_hit: PackedVector2Array = _step_done.get("spots", PackedVector2Array()) as PackedVector2Array
		_tether_left = 5.5
		for i: int in spots_hit.size():
			var sp: Vector2 = spots_hit[i]
			_hit_players_ellipse(sp, 34.0, 0.0, 18.0, 135.0)
			_spawn_battle_golem_host(sp, i % 3)
		if not spots_hit.is_empty():
			_rpc_geode_hatch.rpc(spots_hit)
	if _t >= 1.60:
		_finish_act_host(2.45)


@rpc("authority", "call_local", "reliable")
func _rpc_geode_warn(spots: PackedVector2Array) -> void:
	if is_instance_valid(field):
		var launch_from: Vector2 = (boss.global_position if boss != null else _center) + Vector2(0.0, -48.0)
		for sp: Vector2 in spots:
			field.warn_circle(sp, 34.0, 1.08)
			field.spawn_geode_pod(launch_from, sp, 1.06)


@rpc("authority", "call_local", "reliable")
func _rpc_geode_hatch(spots: PackedVector2Array) -> void:
	_tether_left = 5.5
	if is_instance_valid(field):
		for sp: Vector2 in spots:
			field.add_quartz_plate(sp, 25.0, 9.0)
			field.spawn_burst(sp, 8, AurelithField.TURQ_SAFE)
			field.spawn_shrapnel(sp, 4, 0.95)
	_play_cue("slam", -2.0, 1.06)


# --- Stage 2 Acts --------------------------------------------------------------------------------------------------


func _host_solar_beam(delta: float) -> void:
	if _t >= 1.18 and _t <= 3.53:
		_step_solar_beam_shared(delta, true)
	if _t >= 3.68:
		_finish_act_host(2.45)


func _step_solar_beam_shared(delta: float, apply_damage: bool) -> void:
	if _t < 1.18 or _t > 3.53 or boss == null or not is_instance_valid(field):
		field.set_solar_beam(false)
		return
	var q: float = clampf((_t - 1.18) / 2.35, 0.0, 1.0)
	var sweep_sign: float = 1.0 if _act_p1.x >= 0.0 else -1.0
	var cur_ang: float = _act_f0 + sweep_sign * 1.42 * q
	boss.heading = cur_ang
	var origin: Vector2 = boss.global_position + Vector2(0.0, -24.0)
	var dir: Vector2 = Vector2.from_angle(cur_ang)
	var clip: Dictionary = field.clip_beam_against_pillars(origin, dir, 310.0, delta)
	var beam_len: float = float(clip["dist"])

	# Check living battle QuartzGolems in the beam -> 3-way prism split (`-42°, 0°, +42°`)!
	var splits: Array[Dictionary] = []
	for g_node: Node in get_tree().get_nodes_in_group("quartz_golems"):
		var g2d: Node2D = g_node as Node2D
		if g2d == null or not is_instance_valid(g2d):
			continue
		var hc: HealthComponent = g2d.get_node_or_null("HealthComponent") as HealthComponent
		if hc == null or hc.current <= 0.0:
			continue
		var rel_g: Vector2 = g2d.global_position - origin
		var proj_g: float = rel_g.dot(dir)
		if proj_g > 18.0 and proj_g < beam_len + 8.0:
			var perp_g: float = absf(rel_g.x * (-dir.y) + rel_g.y * dir.x)
			if perp_g <= 22.0:
				for k: int in [-1, 0, 1]:
					var s_ang: float = cur_ang + float(k) * 0.73
					var s_to: Vector2 = g2d.global_position + Vector2.from_angle(s_ang) * 165.0
					splits.append({
						"from": g2d.global_position + Vector2(0.0, -10.0),
						"to": s_to,
						"col": AurelithField.TURQ_SAFE if k != 0 else AurelithField.GOLD_WARN,
					})

	field.set_solar_beam(true, origin, cur_ang, beam_len, splits)

	_beam_plate_cd -= delta
	if _beam_plate_cd <= 0.0:
		_beam_plate_cd = 0.55
		if int(clip["pillar_id"]) < 0:
			field.add_quartz_plate(origin + dir * minf(beam_len, 220.0), 20.0, 8.0)

	if apply_damage:
		var beam_end: Vector2 = origin + dir * beam_len
		_hit_players_segment_tick(origin, beam_end, 13.0, 18.0, 95.0, "beam", 0.38)
		for sp: Dictionary in splits:
			_hit_players_segment_tick(sp["from"] as Vector2, sp["to"] as Vector2, 9.0, 15.0, 80.0, "split", 0.38)


func _host_temple_press() -> void:
	if not _step_done.has(1) and _t >= 1.32:
		_step_done[1] = true
		_next_pillar_id += 1
		var pid: int = _next_pillar_id
		_rpc_temple_crush.rpc(_act_p1, _act_f0, pid)
		var axis: Vector2 = Vector2.from_angle(_act_f0)
		var tang: Vector2 = Vector2(-axis.y, axis.x)
		_hit_players_box(_act_p1 - tang * 59.0, _act_p1 + tang * 59.0, 32.0, 32.0, 190.0)
	if _t >= 1.90:
		_finish_act_host(2.35)


@rpc("authority", "call_local", "reliable")
func _rpc_temple_crush(pos: Vector2, axis_ang: float, pillar_id: int) -> void:
	if boss != null:
		boss.rig().start_pose(AurelithRig.Pose.CLAP_CRUSH, 0.65)
		boss.shake_near(pos, 2.4)
	if is_instance_valid(field):
		var tang: Vector2 = Vector2(sin(axis_ang), -cos(axis_ang))
		field.add_quartz_plate(pos - tang * 28.0, 22.0, 9.0)
		field.spawn_pillar(pillar_id, pos, 18.0)
		ShockRing.burst(field, pos - _center, 58.0, 0.7)
	_play_cue("slam", 0.0, 0.86)


func _host_guardian_triad() -> void:
	if not _step_done.has(1):
		_step_done[1] = true
		var max_g: int = 3 if _living_players().size() >= 3 else 2
		var need: int = clampi(max_g - active_battle_golem_count(), 0, max_g)
		var base_a: float = float(_act_seed % 628) * 0.01
		var spawned_pts: PackedVector2Array = PackedVector2Array()
		for i: int in need:
			var ang: float = base_a + TAU * float(i) / float(maxi(need, 1))
			var pt: Vector2 = field.clamp_in_arena(_center + Vector2(cos(ang) * 126.0, sin(ang) * 126.0 * SQUASH), 0.78)
			_spawn_battle_golem_host(pt, i % 3)
			spawned_pts.append(pt)
		_triad_left = 3.6
		_rpc_triad_activate.rpc(spawned_pts)
	if not _step_done.has(2) and _t >= 1.25:
		_step_done[2] = true
		var target: Player = boss._nearest_living_player(640.0)
		var world_node: Node = _world_spawner()
		if world_node != null:
			for g: Node2D in _battle_golems:
				if not is_instance_valid(g):
					continue
				var aim_p: Vector2 = target.global_position if target != null else _center
				var base_dir: Vector2 = (aim_p - g.global_position).normalized()
				if base_dir == Vector2.ZERO:
					base_dir = Vector2.DOWN
				for ang_off: float in [-0.16, 0.16]:
					var s_dir: Vector2 = base_dir.rotated(ang_off)
					world_node.call("spawn_quartz_shard", g.global_position, s_dir, g.global_position + Vector2(0, -10), 2, boss.damage_scale)
		_rpc_cue_only.rpc("chime", -2.0, 1.08)
	if _t >= 1.80:
		_finish_act_host(2.45)


@rpc("authority", "call_local", "reliable")
func _rpc_triad_activate(pts: PackedVector2Array) -> void:
	_triad_left = 3.6
	if is_instance_valid(field):
		for p: Vector2 in pts:
			field.warn_circle(p, 26.0, 1.22, 0.0, AurelithField.VIOLET_ARC)
			field.add_quartz_plate(p, 24.0, 9.0)
			field.spawn_burst(p, 7, AurelithField.VIOLET_ARC)
			field.spawn_shrapnel(p, 3, 0.92)
	_play_cue("chime", -3.0, 0.94)


func _host_melt_nova(delta: float) -> void:
	_glide_boss_toward(_center, 95.0, delta)
	if not _step_done.has(1) and _t >= 1.05:
		_step_done[1] = true
		_hit_players_ellipse(boss.global_position, 82.0, 0.0, 26.0, 165.0)
		_rpc_melt_ring.rpc(boss.global_position, 1)
	if not _step_done.has(2) and _t >= 1.93:
		_step_done[2] = true
		_hit_players_ellipse(boss.global_position, 244.0, 148.0, 26.0, 175.0)
		_rpc_melt_ring.rpc(boss.global_position, 2)
	if not _step_done.has(3) and _t >= 2.81:
		_step_done[3] = true
		_hit_players_ellipse(boss.global_position, 154.0, 78.0, 26.0, 175.0)
		_rpc_melt_ring.rpc(boss.global_position, 3)
	if _t >= 3.20:
		_finish_act_host(2.40)


@rpc("authority", "call_local", "reliable")
func _rpc_melt_ring(origin: Vector2, step_idx: int) -> void:
	if is_instance_valid(field):
		field.spawn_shrapnel(origin, 4, 0.95 + 0.12 * float(step_idx))
		if step_idx == 1:
			ShockRing.burst(field, origin - _center, 82.0, 0.72)
			field.warn_circle(origin, 244.0, 0.88, 148.0)
		elif step_idx == 2:
			ShockRing.burst(field, origin - _center, 220.0, 0.72)
			field.warn_circle(origin, 154.0, 0.88, 78.0)
		else:
			ShockRing.burst(field, origin - _center, 148.0, 0.72)
	if boss != null:
		boss.shake_near(origin, 1.9)
	_play_cue("erupt", -1.0, 0.88 + float(step_idx) * 0.08)


func _host_sand_mirage(delta: float) -> void:
	if _t < 1.05:
		_glide_boss_toward(_act_p1, 310.0, delta)
	if not _step_done.has(1) and _t >= 1.05:
		_step_done[1] = true
		boss.global_position = _act_p1
		_rpc_mirage_emerge.rpc(_act_p1, _act_f0)
		_hit_players_ellipse(_act_p1, 84.0, 0.0, 26.0, 185.0)
		var world_node: Node = _world_spawner()
		if world_node != null:
			for i: int in 4:
				var s_dir: Vector2 = Vector2.from_angle(TAU * float(i) / 4.0 + PI * 0.25)
				world_node.call("spawn_quartz_shard", _act_p1, s_dir, _act_p1 + Vector2(0, -18), 1, boss.damage_scale)
	if _t >= 1.65:
		_finish_act_host(2.30)


@rpc("authority", "call_local", "reliable")
func _rpc_mirage_emerge(at_pos: Vector2, face_ang: float) -> void:
	if boss != null:
		boss.act_hittable = true
		boss.heading = face_ang
		boss.rig().modulate.a = 1.0
		boss.rig().start_pose(AurelithRig.Pose.FAULT_SLAM, 0.65, 0.45)
		boss.shake_near(at_pos, 2.3)
	if is_instance_valid(field):
		field.add_quartz_plate(at_pos, 34.0, 9.0)
		field.spawn_slash_arc(at_pos + Vector2(0.0, -26.0), face_ang, 1.15, 0.38, false)
		field.spawn_slash_arc(at_pos + Vector2(0.0, -26.0), face_ang + PI, 1.05, 0.38, true)
		field.spawn_burst(at_pos, 10, AurelithField.GOLD_WARN)
		field.spawn_shrapnel(at_pos, 5, 1.05)
		ShockRing.burst(field, at_pos - _center, 84.0, 0.72)
	_play_cue("slam", 0.0, 0.94)


# --- Stage 3 Acts & `ZENITH_NOVA` / `OVERHEAT STAGGER` -------------------------------------------------------------


func _ensure_tsunami_breakwaters_host() -> void:
	var existing: Array[Vector2] = field.pillar_positions()
	var needed: int = 2 - existing.size()
	if needed <= 0:
		return
	for i: int in needed:
		_next_pillar_id += 1
		var ang: float = PI * float(i) + 0.45
		var pt: Vector2 = _center + Vector2(cos(ang) * 112.0, sin(ang) * 112.0 * SQUASH)
		_rpc_spawn_pillar.rpc(_next_pillar_id, pt, 22.0)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_pillar(pillar_id: int, pt: Vector2, dur: float) -> void:
	if is_instance_valid(field):
		field.spawn_pillar(pillar_id, pt, dur)


@rpc("authority", "call_local", "reliable")
func _rpc_shatter_pillar(pillar_id: int, shrapnel: bool) -> void:
	if is_instance_valid(field):
		field.shatter_pillar(pillar_id, shrapnel)


func _host_dune_tsunami() -> void:
	if not _step_done.has(2) and _t >= 2.85:
		_step_done[2] = true
		_rpc_cue_only.rpc("tsunami", 0.0, 1.04)
	_step_tsunami_shared(true)
	if _t >= 5.35:
		_finish_act_host(2.45)


func _step_tsunami_shared(apply_damage: bool) -> void:
	if not is_instance_valid(field):
		return
	var wave_dir: Vector2 = Vector2.ZERO
	var prog: float = 0.0
	var active_w: bool = false
	if _t >= 0.15 and _t < 1.10:
		wave_dir = _act_p0.normalized()
	elif _t >= 1.10 and _t <= 2.75:
		active_w = true
		wave_dir = _act_p0.normalized()
		prog = lerpf(-1.05, 1.05, (_t - 1.10) / 1.65)
	elif _t >= 2.80 and _t < 3.55:
		wave_dir = _act_p1.normalized()
	elif _t >= 3.55 and _t <= 5.20:
		active_w = true
		wave_dir = _act_p1.normalized()
		prog = lerpf(-1.05, 1.05, (_t - 3.55) / 1.65)

	field.set_tsunami_wave(active_w, wave_dir, prog)
	if not active_w or not apply_damage:
		return

	var span_r: float = maxf(_radii.x, _radii.y)
	var crest_proj: float = prog * span_r
	for p: Player in _living_players():
		var rel_p: Vector2 = p.global_position - _center
		var p_proj: float = rel_p.dot(wave_dir)
		if absf(p_proj - crest_proj) <= 22.0:
			if field.is_sheltered_behind_pillar(p.global_position, wave_dir):
				continue
			var key: String = "tsunami_%d" % p.get_instance_id()
			if _can_tick_player(key, 0.70):
				_damage_player(p, 30.0, p.global_position - wave_dir * 32.0, 210.0)


func _host_twin_blades(delta: float) -> void:
	for k: int in 2:
		var slash_t: float = 0.82 + float(k) * 1.00
		if not _step_done.has(k + 1) and _t >= slash_t:
			_step_done[k + 1] = true
			var target: Player = boss._nearest_living_player(640.0)
			var dest: Vector2 = field.clamp_in_arena(target.global_position if target != null else _center, 0.76)
			boss.global_position = boss.global_position.lerp(dest, 0.58)
			var ang: float = float(k) * 0.62 + 0.35
			_rpc_twin_slash.rpc(boss.global_position, ang)
			_hit_players_ellipse(boss.global_position, 74.0, 0.0, 24.0, 155.0)
			_delayed_xbombs.append({
				"pos": boss.global_position,
				"ang": ang,
				"at": field.now() + 0.95,
			})
	if _t < 1.85:
		var target_m: Player = boss._nearest_living_player(640.0)
		if target_m != null:
			_glide_boss_toward(target_m.global_position, 128.0, delta)
	if _t >= 2.65:
		_finish_act_host(2.40)


@rpc("authority", "call_local", "reliable")
func _rpc_twin_slash(at_pos: Vector2, base_ang: float) -> void:
	if boss != null:
		boss.rig().twin_blades = true
		boss.rig().start_pose(AurelithRig.Pose.BLADE_CLEAVE, 0.68)
		boss.shake_near(at_pos, 1.8)
	if is_instance_valid(field):
		for arm: int in 2:
			var a: float = base_ang + float(arm) * PI * 0.5 + PI * 0.25
			var d: Vector2 = Vector2(cos(a) * 62.0, sin(a) * 62.0 * SQUASH)
			field.warn_box(at_pos - d, at_pos + d, 14.0, 0.95, AurelithField.GOLD_WARN)
			field.add_crystal_seam(at_pos - d * 0.88, at_pos + d * 0.88, 0.95)
			field.spawn_slash_arc(at_pos + Vector2(0.0, -24.0), a, 1.05, 0.38, arm == 1)
		field.spawn_burst(at_pos, 7, AurelithField.GOLD_WARN)
		field.spawn_shrapnel(at_pos, 4, 0.92)
	_play_cue("blade", -0.5, 1.02)


func _host_armillary_court(delta: float) -> void:
	_glide_boss_toward(_center, 150.0, delta)
	var base_s: float = float(_act_seed % 628) * 0.01
	if _t >= 1.05 and _t <= 3.95:
		for p: Player in _living_players():
			if AurelithField.is_in_armillary_danger(p.global_position, _center, base_s, _t):
				var key: String = "arm_%d" % p.get_instance_id()
				if _can_tick_player(key, 0.48):
					_damage_player(p, 16.0, _center, 65.0)

	for b_idx: int in 2:
		var warn_t: float = 1.10 + float(b_idx) * 1.25
		if not _step_done.has(10 + b_idx) and _t >= warn_t:
			_step_done[10 + b_idx] = true
			var players: Array[Player] = _living_players()
			var bolt_pos: Vector2 = _center + Vector2.from_angle(float(b_idx) * PI + 0.5) * 96.0
			if not players.is_empty():
				bolt_pos = field.clamp_in_arena(players[b_idx % players.size()].global_position, 0.84)
			_rpc_warn_sky_bolt.rpc(bolt_pos)
			_delayed_bolts.append({"pos": bolt_pos, "at": field.now() + 0.95})

	if _t >= 4.15:
		_finish_act_host(2.40)


@rpc("authority", "call_local", "reliable")
func _rpc_warn_sky_bolt(at_pos: Vector2) -> void:
	if is_instance_valid(field):
		field.warn_circle(at_pos, 40.0, 0.95, 0.0, AurelithField.GOLD_WARN)


func _host_zenith_nova(delta: float) -> void:
	_glide_boss_toward(_center, 180.0, delta)
	if not _step_done.has(1) and _t >= 0.45:
		_step_done[1] = true
		var want_golems: int = clampi(3 - active_battle_golem_count(), 0, 3)
		for i: int in want_golems:
			var ang: float = TAU * float(i) / float(maxi(want_golems, 1)) + 0.35
			var sp: Vector2 = field.clamp_in_arena(_center + Vector2(cos(ang) * 188.0, sin(ang) * 188.0 * SQUASH), 0.84)
			_spawn_battle_golem_host(sp, i % 3)

	if not _step_done.has(2) and _t >= 9.20:
		_step_done[2] = true
		# Uninterrupted Zenith Meltdown! Pillars provide vital emergency cover (`has_pillar_cover_from`).
		for p: Player in _living_players():
			var shielded: bool = field.has_pillar_cover_from(boss.global_position, p.global_position)
			_damage_player(p, 14.0 if shielded else 68.0, boss.global_position, 110.0 if shielded else 280.0)
		var all_pids: Array[int] = field.find_pillars_near(_center, 400.0)
		for pid_s: int in all_pids:
			_rpc_shatter_pillar.rpc(pid_s, true)
		_rpc_zenith_detonate.rpc(boss.global_position)

	if _t >= 9.80:
		_finish_act_host(2.80)


@rpc("authority", "call_local", "reliable")
func _rpc_zenith_detonate(origin: Vector2) -> void:
	if _aura != null:
		_aura.kick(1.0)
	if is_instance_valid(field):
		ShockRing.burst(field, origin - _center, 275.0, 0.88)
		field.spawn_sky_bolt(origin, AurelithField.GOLD_WARN, 0.72)
		field.spawn_burst(origin + Vector2(0.0, -40.0), 32, AurelithField.GOLD_WARN)
	if boss != null:
		boss.shake_near(origin, 3.6)
	_play_cue("meltdown", 0.0, 0.90)


@rpc("authority", "call_local", "reliable")
func _rpc_enter_stagger(duration: float) -> void:
	sub_mode = SubMode.STAGGER
	act = Act.NONE
	_t = 0.0
	_step_done.clear()
	if _aura != null:
		_aura.kick(0.95)
	if is_instance_valid(field):
		field.set_solar_beam(false)
		field.set_tsunami_wave(false)
		field.set_gauntlet_anchor(false)
		field.set_zenith_seal(false)
		if boss != null:
			ShockRing.burst(field, boss.global_position - _center, 130.0, 0.75)
			field.spawn_burst(boss.global_position + Vector2(0.0, -42.0), 24, AurelithField.TURQ_SAFE)
	if boss != null:
		boss.act_hittable = true
		boss.armour = 1.65
		boss.velocity = Vector2.ZERO
		boss.rig().set_detached_fist(true, false)
		boss.rig().charge_intensity = 0.0
		boss.rig().twin_blades = false
		boss.rig().hit_flash()
		boss.rig().start_pose(AurelithRig.Pose.STAGGER, duration)
		boss.shake_near(boss.global_position, 3.0)
	_play_cue("stagger", 0.0, 0.96)


func _step_stagger_host(delta: float) -> void:
	_t += delta
	if _t >= 4.2:
		_rpc_end_act.rpc(1.85)


# --- Battle `QuartzGolem` Summons & `Resonanz-Kern` Counterplay ----------------------------------------------------


func _spawn_battle_golem_host(world_pos: Vector2, variant_id: int) -> Node2D:
	var world_node: Node = _world_spawner()
	if world_node == null:
		return null
	var players_n: int = maxi(_living_players().size(), 1)
	var hp_scale: float = 0.76 * (1.0 + 0.25 * float(players_n - 1))
	var target: Player = boss._nearest_living_player(640.0)
	var face_a: float = (target.global_position - world_pos).angle() if target != null else PI * 0.5
	var golem: Node2D = world_node.call(
		"spawn_quartz_golem",
		world_pos,
		face_a,
		variant_id,
		false,
		hp_scale,
		boss.damage_scale * 0.85,
		true
	) as Node2D
	if golem == null:
		return null
	golem.set("pickaxe_override", 1.0) ## Pure 1.0x weapon & spell parity!
	var drop_comp: Node = golem.get_node_or_null("DropComponent")
	if drop_comp != null:
		drop_comp.queue_free()
	if golem.has_method("boost_basin_aggression"):
		golem.call("boost_basin_aggression", 0.75, target)
	var hc: HealthComponent = golem.get_node_or_null("HealthComponent") as HealthComponent
	if hc != null:
		hc.died.connect(_on_battle_golem_died.bind(golem), CONNECT_ONE_SHOT)
	_battle_golems.append(golem)
	return golem


func _on_battle_golem_died(golem: Node2D) -> void:
	if not _host or sub_mode == SubMode.DEAD:
		return
	var at_pos: Vector2 = golem.global_position if is_instance_valid(golem) else _center
	_battle_golems.erase(golem)
	_next_core_id += 1
	_rpc_spawn_core.rpc(_next_core_id, at_pos, 7.0)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_core(core_id: int, at_pos: Vector2, lifetime: float) -> void:
	if is_instance_valid(field):
		field.spawn_resonance_core(core_id, at_pos, lifetime)


func host_reflect_core(core_id: int, source_peer: int) -> void:
	if not _host or sub_mode == SubMode.DEAD:
		return
	_rpc_launch_core.rpc(core_id, source_peer)


@rpc("authority", "call_local", "reliable")
func _rpc_launch_core(core_id: int, source_peer: int) -> void:
	if is_instance_valid(field):
		field.launch_core_at_boss(core_id, source_peer)
	_play_cue("core", -0.5, 1.0)


func _on_core_struck_boss(damage: float, source_peer: int) -> void:
	if not _host or boss == null or sub_mode == SubMode.DEAD:
		return
	if sub_mode == SubMode.ACT and act == Act.ZENITH_NOVA:
		_zenith_cores_hit += 1
		boss._health.take_damage(95.0 * boss.health_scale, _center + Vector2(0, 40), 0.0, source_peer)
		_rpc_cue_only.rpc("slam", -1.0, 1.04 + 0.08 * float(_zenith_cores_hit))
		if _zenith_cores_hit >= 3:
			_rpc_enter_stagger.rpc(4.2)
		return

	_armor_crack_left = 3.2
	boss._health.take_damage(damage * boss.health_scale, _center + Vector2(0, 40), 0.0, source_peer)
	_rpc_cue_only.rpc("slam", -1.5, 1.12)


func _prune_battle_golems() -> void:
	if _battle_golems.is_empty():
		return
	_battle_golems = _battle_golems.filter(func(g: Node2D) -> bool:
		if g == null or not is_instance_valid(g) or g.is_queued_for_deletion():
			return false
		var hc: HealthComponent = g.get_node_or_null("HealthComponent") as HealthComponent
		return hc == null or hc.current > 0.0
	)


func _clear_battle_golems() -> void:
	for g: Node2D in _battle_golems:
		if g != null and is_instance_valid(g):
			g.queue_free()
	_battle_golems.clear()


func _update_live_tether_visuals() -> void:
	if not is_instance_valid(field) or boss == null:
		return
	var links: Array[Dictionary] = []
	if _triad_left <= 0.0 and _tether_left <= 0.0:
		if not field._tether_links.is_empty():
			field.set_tether_links(links)
		return
	var live_golems: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group("quartz_golems"):
		var g2d: Node2D = node as Node2D
		if g2d == null or not is_instance_valid(g2d) or g2d.global_position.distance_to(_center) > 330.0:
			continue
		var hc: HealthComponent = g2d.get_node_or_null("HealthComponent") as HealthComponent
		if hc != null and hc.current > 0.0:
			live_golems.append(g2d)

	if _triad_left > 0.0 and live_golems.size() >= 2:
		for i: int in live_golems.size():
			var a_g: Node2D = live_golems[i]
			var b_g: Node2D = live_golems[(i + 1) % live_golems.size()]
			if i == 1 and live_golems.size() == 2:
				break
			links.append({
				"a": a_g.global_position + Vector2(0.0, -14.0),
				"b": b_g.global_position + Vector2(0.0, -14.0),
				"col": AurelithField.VIOLET_ARC,
			})
	elif _tether_left > 0.0 and not live_golems.is_empty():
		for g_t: Node2D in live_golems:
			links.append({
				"a": boss.global_position + Vector2(0.0, -42.0),
				"b": g_t.global_position + Vector2(0.0, -14.0),
				"col": AurelithField.TURQ_SAFE,
			})
	field.set_tether_links(links)


func _step_tether_and_triad_damage() -> void:
	if _triad_left <= 0.0 and _tether_left <= 0.0:
		return
	if _triad_left > 0.0 and _battle_golems.size() >= 2:
		for i: int in _battle_golems.size():
			var a_g: Node2D = _battle_golems[i]
			var b_g: Node2D = _battle_golems[(i + 1) % _battle_golems.size()]
			if i == 1 and _battle_golems.size() == 2:
				break
			_hit_players_segment_tick(a_g.global_position, b_g.global_position, 10.0, 16.0, 90.0, "triad", 0.45)
	elif _tether_left > 0.0:
		for g_t: Node2D in _battle_golems:
			_hit_players_segment_tick(boss.global_position, g_t.global_position, 10.0, 14.0, 80.0, "tether", 0.48)


func _step_delayed_hazards() -> void:
	var cur_now: float = field.now()
	if not _delayed_xbombs.is_empty():
		var rem_x: Array[Dictionary] = []
		for xb: Dictionary in _delayed_xbombs:
			if cur_now >= float(xb["at"]):
				var xp: Vector2 = xb["pos"] as Vector2
				var xa: float = float(xb["ang"])
				for arm: int in 2:
					var a: float = xa + float(arm) * PI * 0.5 + PI * 0.25
					var d: Vector2 = Vector2(cos(a) * 62.0, sin(a) * 62.0 * SQUASH)
					_hit_players_box(xp - d, xp + d, 14.0, 26.0, 150.0)
				_rpc_detonate_xbomb.rpc(xp)
			else:
				rem_x.append(xb)
		_delayed_xbombs = rem_x

	if not _delayed_bolts.is_empty():
		var rem_b: Array[Dictionary] = []
		for sb: Dictionary in _delayed_bolts:
			if cur_now >= float(sb["at"]):
				var bp: Vector2 = sb["pos"] as Vector2
				_hit_players_ellipse(bp, 40.0, 0.0, 24.0, 140.0)
				_rpc_strike_sky_bolt.rpc(bp)
			else:
				rem_b.append(sb)
		_delayed_bolts = rem_b


@rpc("authority", "call_local", "reliable")
func _rpc_detonate_xbomb(at_pos: Vector2) -> void:
	if is_instance_valid(field):
		field.add_quartz_plate(at_pos, 26.0, 12.0)
		field.spawn_burst(at_pos, 16, AurelithField.GOLD_WARN)
		field.spawn_shrapnel(at_pos, 12, 1.08)
		ShockRing.burst(field, at_pos - _center, 54.0, 0.68)
	_play_cue("erupt", -1.5, 1.08)


@rpc("authority", "call_local", "reliable")
func _rpc_strike_sky_bolt(at_pos: Vector2) -> void:
	if is_instance_valid(field):
		field.spawn_sky_bolt(at_pos, AurelithField.GOLD_WARN, 0.42)
		field.add_quartz_plate(at_pos, 24.0, 12.0)
	if boss != null:
		boss.shake_near(at_pos, 1.6)
	_play_cue("erupt", -1.5, 1.15)


@rpc("authority", "call_local", "reliable")
func _rpc_cue_only(cue: String, db_offset: float, pitch: float) -> void:
	_play_cue(cue, db_offset, pitch)


# --- Geometry Hit-Tests & Audio Pool -------------------------------------------------------------------------------


func _living_players() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in Player.all:
		if p == null or not is_instance_valid(p) or p.health.current <= 0.0:
			continue
		if Interiors.slot_at(p.global_position) >= 0 or MineManager.in_mine(p.global_position):
			continue
		if p.global_position.distance_to(_center) <= 680.0:
			out.append(p)
	return out


func _damage_player(p: Player, raw_damage: float, from_pos: Vector2, knockback: float) -> void:
	var hb: HurtboxComponent = p.get_node_or_null("Hurtbox") as HurtboxComponent
	if hb == null or (hb.collision_layer & PLAYER_HURT_LAYER) == 0:
		return
	var final_dmg: float = maxf(1.0, roundf(raw_damage * boss.damage_scale))
	var origin: Vector2 = from_pos
	if knockback < 0.0:
		# Pull knockback toward boss
		origin = p.global_position + (p.global_position - boss.global_position).normalized() * 16.0
		knockback = absf(knockback)
	hb.take_hit(final_dmg, origin, knockback)


func _hit_players_ellipse(center_pos: Vector2, outer_r: float, inner_r: float, raw_dmg: float, knockback: float) -> void:
	for p: Player in _living_players():
		var rel: Vector2 = p.global_position - center_pos
		var d: float = Vector2(rel.x, rel.y / SQUASH).length()
		if d <= outer_r and d >= inner_r:
			_damage_player(p, raw_dmg, center_pos, knockback)


func _hit_players_box(a: Vector2, b: Vector2, half_width: float, raw_dmg: float, knockback: float) -> void:
	var ab: Vector2 = b - a
	var len_ab: float = ab.length()
	if len_ab <= 1.0:
		return
	var dir: Vector2 = ab / len_ab
	for p: Player in _living_players():
		var rel: Vector2 = p.global_position - a
		var proj: float = rel.dot(dir)
		if proj >= -6.0 and proj <= len_ab + 6.0:
			var perp: float = absf(rel.x * (-dir.y) + rel.y * dir.x)
			if perp <= half_width:
				_damage_player(p, raw_dmg, a + dir * clampf(proj, 0.0, len_ab), knockback)


func _hit_players_cone(origin: Vector2, base_ang: float, half_arc: float, radius: float, raw_dmg: float, knockback: float) -> void:
	for p: Player in _living_players():
		var rel: Vector2 = p.global_position - origin
		var unsq: Vector2 = Vector2(rel.x, rel.y / SQUASH)
		if unsq.length() <= radius:
			var da: float = absf(wrapf(unsq.angle() - base_ang, -PI, PI))
			if da <= half_arc:
				_damage_player(p, raw_dmg, origin, knockback)


func _hit_players_segment_tick(a: Vector2, b: Vector2, half_width: float, raw_dmg: float, knockback: float, tag: String, grace_sec: float) -> void:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 <= 1.0:
		return
	for p: Player in _living_players():
		var u: float = clampf((p.global_position - a).dot(ab) / l2, 0.0, 1.0)
		var closest: Vector2 = a + ab * u
		if p.global_position.distance_to(closest) <= half_width:
			var key: String = "%s_%d" % [tag, p.get_instance_id()]
			if _can_tick_player(key, grace_sec):
				_damage_player(p, raw_dmg, closest, knockback)


func _can_tick_player(key: String, cooldown: float) -> bool:
	if float(_tick_grace.get(key, 0.0)) > 0.0:
		return false
	_tick_grace[key] = cooldown
	return true


func _tick_cooldowns(delta: float) -> void:
	if _tick_grace.is_empty():
		return
	var expired: Array[String] = []
	for k: String in _tick_grace:
		var left: float = float(_tick_grace[k]) - delta
		if left <= 0.0:
			expired.append(k)
		else:
			_tick_grace[k] = left
	for ek: String in expired:
		_tick_grace.erase(ek)


func _world_spawner() -> Node:
	for node: Node in get_tree().get_nodes_in_group("world"):
		if node.has_method("spawn_quartz_golem"):
			return node
	return null


func _play_cue(cue: String, db_offset: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless" or boss == null or _sfx_pool.is_empty():
		return
	var audio_cfg: Dictionary = boss._def.get("audio", {}) as Dictionary
	var path: String = String(audio_cfg.get(cue, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	if not _audio_cache.has(path):
		_audio_cache[path] = load(path)
	var stream: AudioStream = _audio_cache[path] as AudioStream
	if stream == null:
		return
	var player: AudioStreamPlayer2D = _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	player.global_position = boss.global_position
	player.stream = stream
	player.volume_db = float(audio_cfg.get("volume_db", -4.5)) + db_offset
	player.pitch_scale = pitch
	player.play()
