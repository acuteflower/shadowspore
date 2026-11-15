class_name Aurelith
extends Node2D
## Aurelith, Herz des Sonnenquarzes (`boss_aurelith`, docs/enemies/boss_aurelith.md):
## Colossal floating sun-quartz & sandstone desert titan in the Singing Basin (`Tile 626, 69`).
##
## Host-authoritative shell replicated via `WorldLevel/EnemySpawner`:
## - 100% silent & sublime (zero dialogue lines; communicates purely through monumentality, runes & sound).
## - Pure weapon & spell parity (`pickaxe_multiplier() == 1.0`, zero extra pickaxe bonus).
## - Casts real daytime desert shade (`day_canopies`) beneath its hovering monolith bulk.
## - Plays the self-assembly & double-fist ground slam (`Pose.AWAKEN` -> `Pose.FAULT_SLAM`), sealing
##   `AurelithArena`'s 36-tooth sintered-quartz & sandstorm perimeter right on the impact beat.

signal touched_down
signal reset_requested
signal defeated

enum Mode {
	ENTRANCE,
	ACTIVE,
	DEAD,
}

const TITLE: String = "AURELITH"
const HURTBOX_LAYER: int = 1 << 4
const BODY_LAYER: int = 1 << 2

var enemy_id: String = "boss_aurelith"
var health_scale: float = 1.0
var damage_scale: float = 1.0
var emerge_on_spawn: bool = false
var skip_awaken: bool = false
var heading: float = PI * 0.5
var velocity: Vector2 = Vector2.ZERO
var mode: Mode = Mode.ENTRANCE
var act_hittable: bool = false
var armour: float = 1.0
var field: AurelithField
var fight: AurelithFight

var _def: Dictionary = {}
var _arena_spec: Dictionary = {}
var _basin_center: Vector2 = Vector2.ZERO
var _arena_radii: Vector2 = Vector2(290.0, 210.0)
var _t: float = 0.0
var _rise_len: float = 1.35
var _slam_len: float = 1.55
var _slam_at: float = 2.25
var _slam_started: bool = false
var _slammed: bool = false
var _idle_started: bool = false
var _hittable: bool = false
var _bar_shown: bool = false
var _intro: BossIntro
var _away_clock: float = 0.0
var _reset_asked: bool = false
var _shock_age: float = -1.0
var _dust_motes: Array[Dictionary] = []
var _audio_cache: Dictionary = {}
var _death_age: float = -1.0
var _death_beats: Dictionary = {}
var _death_mote_cd: float = 0.0
var _ground_fx_was_active: bool = false

@onready var _rig: AurelithRig = $Rig
@onready var _health: HealthComponent = $HealthComponent
@onready var _hurtbox: HurtboxComponent = $Hurtbox
@onready var _body_col: StaticBody2D = $BodyCollider
@onready var _ground_fx: Node2D = $GroundFx
@onready var _light: NightLight = $NightLight
@onready var _voice: AudioStreamPlayer2D = $Voice


func _ready() -> void:
	add_to_group("predators")
	add_to_group("bosses")
	add_to_group("day_canopies")
	_def = EnemyScaling.scaled(DataRegistry.get_entry("enemies", enemy_id), health_scale, damage_scale)
	_arena_spec = DataRegistry.table("aurelith_arena")
	var tile: Array = _arena_spec.get("tile", [626, 69]) as Array
	_basin_center = Vector2(float(tile[0]) * 16.0 + 8.0, float(tile[1]) * 16.0 + 8.0)
	_arena_radii = Vector2(
		float(_arena_spec.get("arena_rx", 290.0)),
		float(_arena_spec.get("arena_ry", 210.0))
	)
	var entrance: Dictionary = ((_def.get("fight", {}) as Dictionary).get("entrance", {}) as Dictionary)
	_rise_len = float(entrance.get("rise", 1.35))
	_slam_len = float(entrance.get("slam", 1.55))
	_slam_at = _rise_len + _slam_len * float(entrance.get("slam_hit", 0.58))

	_health.max_health = float(_def.get("max_health", 2500.0))
	_health.current = _health.max_health
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_ground_fx.draw.connect(_draw_ground_fx)

	field = AurelithField.new()
	field.setup(self, _basin_center, _arena_radii)
	if get_parent() != null:
		get_parent().add_child.call_deferred(field)
	else:
		add_child(field)

	fight = AurelithFight.new()
	add_child(fight)
	fight.setup(self, field)

	_set_hittable(false)
	_rig.soul_charge = 1.0
	if skip_awaken:
		_enter_active_immediately()
	else:
		_begin_entrance(0.0)
		if multiplayer.is_server():
			_start_intro(0.0)
		else:
			_ask_entrance.rpc_id(1)


func pickaxe_multiplier() -> float:
	return 1.0


func day_canopy() -> Vector4:
	return Vector4(global_position.x + 10.0, global_position.y + 6.0, 56.0, 38.0)


func centre() -> Vector2:
	return _basin_center


func chest_spot() -> Vector2:
	return _basin_center + Vector2(0.0, 46.0)


func is_storm_stage() -> bool:
	return mode == Mode.ACTIVE and ((fight != null and fight.phase >= 2) or (_rig != null and _rig.storm_ascension > 0.35))


func debug_force_phase(target_phase: int, skip_transition: bool = false) -> void:
	if fight != null:
		fight.force_phase(target_phase, skip_transition)


func landing_spot() -> Vector2:
	return global_position + Vector2(0.0, -48.0)


func eye_position() -> Vector2:
	return _rig.head_world_pos() if _rig != null else global_position + Vector2(0.0, -114.0)


func intro_running() -> bool:
	return _intro != null


func max_health() -> float:
	return _health.max_health


func health_now() -> float:
	return _health.current


func rig() -> AurelithRig:
	return _rig


func _enter_active_immediately() -> void:
	mode = Mode.ACTIVE
	_slam_started = true
	_slammed = true
	_idle_started = true
	act_hittable = true
	_rig.start_pose(AurelithRig.Pose.IDLE, 1.0)
	_rig.update_rig(0.016, Vector2.ZERO, heading)
	get_tree().call_group("aurelith_arena", "on_boss_fist_slam")


func _begin_entrance(elapsed: float) -> void:
	mode = Mode.ENTRANCE
	_t = elapsed
	act_hittable = false
	_rig.soul_charge = 1.0
	_rig.start_pose(AurelithRig.Pose.AWAKEN, _rise_len, minf(elapsed, _rise_len))
	_rig.update_rig(0.016, Vector2.ZERO, heading)
	if elapsed < 0.15:
		_play_sound("awaken", -3.0, 0.78)
		_spawn_sand_column(22)


@rpc("any_peer", "call_remote", "reliable")
func _ask_entrance() -> void:
	if multiplayer.is_server() and mode == Mode.ENTRANCE and not _slammed:
		_rpc_entrance.rpc_id(multiplayer.get_remote_sender_id(), _t)


@rpc("authority", "call_remote", "reliable")
func _rpc_entrance(elapsed: float) -> void:
	_t = maxf(_t, elapsed)
	_start_intro(elapsed)


func _start_intro(skip: float) -> void:
	if _intro != null or DisplayServer.get_name() == "headless":
		return
	var shown: Dictionary = _def.get("intro", {}) as Dictionary
	if shown.is_empty():
		return
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(centre()) < float(shown.get("range", 720.0)):
			_intro = BossIntro.play(self, player, String(shown["name"]), String(shown["epithet"]), skip)
			_intro.finished.connect(func() -> void: _intro = null)
			return


func _process(delta: float) -> void:
	if _shock_age >= 0.0:
		_shock_age += delta
		if _shock_age >= 0.95:
			_shock_age = -1.0
	for m: Dictionary in _dust_motes:
		m["life"] = float(m["life"]) - delta
		var vel_m: Vector2 = m["vel"] as Vector2
		vel_m.y += float(m["grav"]) * delta
		m["vel"] = vel_m
		m["pos"] = (m["pos"] as Vector2) + vel_m * delta
	if not _dust_motes.is_empty():
		_dust_motes = _dust_motes.filter(func(m: Dictionary) -> bool: return float(m["life"]) > 0.0)

	if mode == Mode.DEAD and _death_age >= 0.0:
		_step_death_fx(delta)

	if fight != null:
		fight.step_visuals(delta)
	_sync_stage_visuals(delta)
	_rig.update_rig(delta, velocity, heading)
	var gfx_active: bool = (_shock_age >= 0.0 and _shock_age < 0.95) or not _dust_motes.is_empty()
	if gfx_active or _ground_fx_was_active:
		_ground_fx_was_active = gfx_active
		_ground_fx.queue_redraw()
	_update_bar()


func _physics_process(delta: float) -> void:
	_set_hittable(mode == Mode.ACTIVE and act_hittable and _health.current > 0.0)
	match mode:
		Mode.ENTRANCE:
			_step_entrance(delta)
		Mode.ACTIVE:
			if fight != null:
				if multiplayer.is_server():
					fight.step_host(delta)
				else:
					fight.step_client(delta)
			elif multiplayer.is_server():
				_step_active_host(delta)


func _step_entrance(delta: float) -> void:
	_t += delta
	if not _slam_started and _t >= _rise_len:
		_slam_started = true
		_rig.start_pose(AurelithRig.Pose.FAULT_SLAM, _slam_len, _t - _rise_len)
		_play_sound("charge", -5.0, 0.86)
	if not _slammed and _t >= _slam_at:
		_slammed = true
		_shock_age = 0.0
		_spawn_slam_burst()
		_play_sound("slam", 0.0, 0.72)
		shake_near(global_position, 2.5)
		get_tree().call_group("aurelith_arena", "on_boss_fist_slam")
		touched_down.emit()
	if not _idle_started and _t >= _rise_len + _slam_len:
		_idle_started = true
		_rig.start_pose(AurelithRig.Pose.IDLE, 1.0)
	if _slammed and _t >= _rise_len + _slam_len and not intro_running():
		if multiplayer.is_server():
			_rpc_enter_active.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_enter_active() -> void:
	if mode == Mode.DEAD:
		return
	mode = Mode.ACTIVE
	act_hittable = true
	if not _idle_started:
		_idle_started = true
		_rig.start_pose(AurelithRig.Pose.IDLE, 1.0)


func _step_active_host(delta: float) -> void:
	var target: Player = _nearest_living_player(float(_arena_spec.get("leash", 640.0)))
	if target == null:
		velocity = velocity.move_toward(Vector2.ZERO, delta * 180.0)
		_away_clock += delta
		if _away_clock >= float(_arena_spec.get("reset_seconds", 8.0)):
			request_reset()
		return
	_away_clock = 0.0
	var to_target: Vector2 = target.global_position - global_position
	var dist: float = to_target.length()
	if dist > 1.0:
		heading = lerp_angle(heading, to_target.angle(), delta * 3.4)
	var fight_cfg: Dictionary = _def.get("fight", {}) as Dictionary
	var pref_min: float = float(fight_cfg.get("preferred_min", 84.0))
	var pref_max: float = float(fight_cfg.get("preferred_max", 148.0))
	var hover_spd: float = float(_def.get("hover_speed", 68.0))
	var want_vel: Vector2 = Vector2.ZERO
	if dist > pref_max:
		want_vel = to_target.normalized() * hover_spd
	elif dist < pref_min and dist > 1.0:
		want_vel = -to_target.normalized() * (hover_spd * 0.65)
	velocity = velocity.move_toward(want_vel, delta * 160.0)
	var next_pos: Vector2 = global_position + velocity * delta
	# Clamp inside 78% of the 3/4 arena ellipse so his colossal hovering body never clips the outer tooth wall
	var rel: Vector2 = (next_pos - _basin_center) / (_arena_radii * 0.76)
	if rel.length_squared() > 1.0:
		next_pos = _basin_center + rel.normalized() * (_arena_radii * 0.76)
		velocity = Vector2.ZERO
	global_position = next_pos
	var want_pose: AurelithRig.Pose = AurelithRig.Pose.MOVE if velocity.length() > 10.0 else AurelithRig.Pose.IDLE
	if _rig._pose != want_pose and _rig._pose in [AurelithRig.Pose.IDLE, AurelithRig.Pose.MOVE]:
		_sync_pose.rpc(int(want_pose))


@rpc("authority", "call_local", "unreliable")
func _sync_pose(pose_id: int) -> void:
	if mode == Mode.ACTIVE and _rig != null:
		_rig.start_pose(pose_id as AurelithRig.Pose, 1.0)


func _sync_stage_visuals(delta: float) -> void:
	if mode == Mode.DEAD or _health == null or _health.max_health <= 0.0:
		return
	var ratio: float = _health.current / _health.max_health
	var p1_on: bool = (fight != null and fight.phase >= 1) or (fight == null and ratio <= 0.66)
	var p2_on: bool = (fight != null and fight.phase >= 2) or (fight == null and ratio <= 0.33)
	var want_prism: float = 1.0 if p1_on else 0.0
	var want_storm: float = 1.0 if p2_on else 0.0
	_rig.prism_release = move_toward(_rig.prism_release, want_prism, delta * 1.8)
	_rig.storm_ascension = move_toward(_rig.storm_ascension, want_storm, delta * 1.6)
	if _light != null:
		if _rig.storm_ascension > 0.4:
			_light.glow_color = Color("ffe088")
			_light.base_energy = 0.88
		elif _rig.prism_release > 0.4:
			_light.glow_color = Color("c58cff")
			_light.base_energy = 0.80
		else:
			_light.glow_color = Color("78f4e6")
			_light.base_energy = 0.72


func _nearest_living_player(max_dist: float) -> Player:
	var best: Player = null
	var best_d: float = max_dist
	for player: Player in Player.all:
		if player == null or not is_instance_valid(player) or player.health.current <= 0.0:
			continue
		if Interiors.slot_at(player.global_position) >= 0 or MineManager.in_mine(player.global_position):
			continue
		var d: float = player.global_position.distance_to(_basin_center)
		if d <= max_dist:
			var dp: float = player.global_position.distance_to(global_position)
			if best == null or dp < best_d:
				best = player
				best_d = dp
	return best


func _update_bar() -> void:
	var near: bool = false
	var range_px: float = float(_def.get("bar_range", 420.0)) * (1.25 if _bar_shown else 1.0)
	if _health.current > 0.0 and mode == Mode.ACTIVE and _intro == null:
		for player: Player in Player.all:
			if player.is_multiplayer_authority() and player.health.current > 0.0 and player.global_position.distance_to(centre()) < range_px:
				near = true
				break
	if near and not _bar_shown:
		_bar_shown = true
		get_tree().call_group("boss_bar", "track", TITLE, _health)
	elif not near and _bar_shown:
		_bar_shown = false
		if _health.current > 0.0:
			get_tree().call_group("boss_bar", "release")


func _set_hittable(on: bool) -> void:
	if on == _hittable:
		return
	_hittable = on
	_hurtbox.set_deferred("collision_layer", HURTBOX_LAYER if on else 0)
	_body_col.set_deferred("collision_layer", BODY_LAYER if (mode != Mode.DEAD) else 0)


func _on_damaged(amount: float, from: Vector2, _knockback: float) -> void:
	var away: Vector2 = (global_position - from).normalized()
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0.0, -118.0), amount, away)
	_rig.hit_flash()


func _on_died() -> void:
	mode = Mode.DEAD
	_death_age = 0.0
	_death_beats.clear()
	_death_mote_cd = 0.0
	act_hittable = false
	velocity = Vector2.ZERO
	_set_hittable(false)
	if _bar_shown:
		_bar_shown = false
		get_tree().call_group("boss_bar", "release")
	if fight != null:
		fight.on_boss_died()
	_rig.hit_flash()
	_rig.start_pose(AurelithRig.Pose.DEAD, 3.80)
	if is_instance_valid(field):
		field.set_zenith_seal(true, global_position, 0.35)
		field.spawn_burst(global_position + Vector2(0.0, -56.0), 20, AurelithField.TURQ_SAFE)
	_play_sound("stagger", 0.0, 0.90)
	_spawn_sand_column(24)
	shake_near(global_position, 2.2)
	defeated.emit()
	get_tree().call_group("aurelith_arena", "on_released")
	if multiplayer.is_server():
		await get_tree().create_timer(3.92).timeout
		if is_inside_tree():
			queue_free()


func _step_death_fx(delta: float) -> void:
	_death_age += delta
	# Beat 1 (`0.00..2.16 s`): Critical Resonance Overload & Rising Solar Seal
	if _death_age < 2.16:
		var q_over: float = clampf(_death_age / 2.16, 0.0, 1.0)
		if is_instance_valid(field):
			field.set_zenith_seal(true, global_position, lerpf(0.35, 1.0, q_over))
		if _light != null:
			_light.glow_color = Color("ffe488")
			_light.base_energy = lerpf(0.95, 1.48, q_over)
		_death_mote_cd -= delta
		if _death_mote_cd <= 0.0:
			_death_mote_cd = 0.11
			_spawn_sand_column(3)

	# Beat 2A (`1.06 s`): Right Ley-Tether Snaps & Right Colossus Gauntlet Crashes into Sand!
	if not _death_beats.has(1) and _death_age >= 1.06:
		_death_beats[1] = true
		var r_crash: Vector2 = _rig.fist_world_pos(true) if _rig != null else (global_position + Vector2(64.0, 8.0))
		if is_instance_valid(field):
			ShockRing.burst(field, r_crash - _basin_center, 58.0, 0.72)
			field.add_quartz_plate(r_crash, 26.0, 2.8)
			field.spawn_shrapnel(r_crash, 10, 1.05)
			field.spawn_burst(r_crash, 14, AurelithField.GOLD_WARN)
		shake_near(r_crash, 2.0)
		_play_sound("slam", -1.0, 0.92)

	# Beat 2B (`1.46 s`): Left Ley-Tether Snaps & Left Colossus Gauntlet Crashes into Sand!
	if not _death_beats.has(2) and _death_age >= 1.46:
		_death_beats[2] = true
		var l_crash: Vector2 = _rig.fist_world_pos(false) if _rig != null else (global_position + Vector2(-64.0, 8.0))
		if is_instance_valid(field):
			ShockRing.burst(field, l_crash - _basin_center, 62.0, 0.75)
			field.add_quartz_plate(l_crash, 26.0, 2.4)
			field.spawn_shrapnel(l_crash, 10, 1.08)
			field.spawn_burst(l_crash, 14, AurelithField.TURQ_SAFE)
		shake_near(l_crash, 2.2)
		_play_sound("slam", -0.5, 0.84)

	# Beat 2C (`1.84 s`): Canyon Shoulders Tear Loose & Crystal Wing-Blades Shatter!
	if not _death_beats.has(3) and _death_age >= 1.84:
		_death_beats[3] = true
		if is_instance_valid(field):
			field.add_crystal_seam(global_position + Vector2(-68.0, -18.0), global_position + Vector2(68.0, 18.0), 1.45)
			field.add_crystal_seam(global_position + Vector2(-64.0, 20.0), global_position + Vector2(64.0, -20.0), 1.45)
			field.spawn_shrapnel(global_position + Vector2(0.0, -24.0), 12, 1.12)
		shake_near(global_position, 2.4)
		_play_sound("erupt", -1.0, 0.95)

	# Beat 3 (`2.17 s`): SUN-PRISM HEART SUPERNOVA & SPLIT-OBELISK VISAGE CLEAVE CLIMAX!
	if not _death_beats.has(4) and _death_age >= 2.17:
		_death_beats[4] = true
		_shock_age = 0.0
		if is_instance_valid(field):
			field.set_zenith_seal(false)
			ShockRing.burst(field, global_position - _basin_center, 235.0, 0.92)
			ShockRing.burst(field, (global_position - _basin_center) + Vector2(0.0, -48.0), 125.0, 0.85)
			field.spawn_sky_bolt(global_position + Vector2(0.0, -20.0), AurelithField.GOLD_WARN, 0.68)
			field.spawn_sky_bolt(global_position + Vector2(-54.0, 8.0), AurelithField.TURQ_SAFE, 0.52)
			field.spawn_sky_bolt(global_position + Vector2(54.0, 8.0), AurelithField.TURQ_SAFE, 0.52)
			field.spawn_shrapnel(global_position + Vector2(0.0, -44.0), 24, 1.35)
			field.spawn_burst(global_position + Vector2(0.0, -56.0), 28, AurelithField.GOLD_WARN)
			field.add_quartz_plate(global_position, 44.0, 1.65)
		_spawn_sand_column(32)
		shake_near(global_position, 3.8)
		_play_sound("collapse", 0.8, 0.92)

	# Beat 4 (`2.92..3.80 s`): Harmonic Golden Sand & Singing-Quartz Dissolution -> Glutreliquiar!
	if not _death_beats.has(5) and _death_age >= 2.92:
		_death_beats[5] = true
		_spawn_sand_column(24)
		if _light != null:
			_light.glow_color = Color("78f4e6")
		_play_sound("chime", -2.0, 0.86)
	if _death_age >= 2.92 and _light != null:
		_light.base_energy = lerpf(1.15, 0.0, clampf((_death_age - 2.92) / 0.88, 0.0, 1.0))


func request_reset() -> void:
	if multiplayer.is_server() and not _reset_asked:
		_reset_asked = true
		reset_requested.emit()


func shake_near(point: Vector2, amount: float) -> void:
	var radius: float = float(_def.get("shake_radius", 340.0))
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			player.add_shake(amount * (1.0 - smoothstep(36.0, radius, player.global_position.distance_to(point))))


func _spawn_sand_column(count: int) -> void:
	for i: int in count:
		var ang: float = float(i) / float(maxi(count, 1)) * TAU + randf_range(-0.2, 0.2)
		var rad: float = randf_range(10.0, 46.0)
		_dust_motes.append({
			"pos": global_position + Vector2(cos(ang) * rad, sin(ang) * rad * 0.72),
			"vel": Vector2(cos(ang) * randf_range(6.0, 22.0), -randf_range(34.0, 78.0)),
			"grav": 28.0,
			"life": randf_range(0.55, 1.05),
			"max_life": 1.05,
			"col": Color("78f4e6") if i % 3 == 0 else (Color("ffe488") if i % 3 == 1 else Color("e6be78")),
			"size": 2.0 if i % 2 == 0 else 1.0,
		})


func _spawn_slam_burst() -> void:
	for side_s: float in [-1.0, 1.0]:
		var impact: Vector2 = global_position + Vector2(side_s * 36.0, 14.0)
		for i: int in 16:
			var ang: float = randf_range(0.0, TAU)
			var spd: float = randf_range(32.0, 118.0)
			_dust_motes.append({
				"pos": impact + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0)),
				"vel": Vector2(cos(ang) * spd, sin(ang) * spd * 0.72 - randf_range(24.0, 64.0)),
				"grav": 135.0,
				"life": randf_range(0.45, 0.85),
				"max_life": 0.85,
				"col": Color("ffffff") if i % 4 == 0 else (Color("78f4e6") if i % 2 == 0 else Color("e6be78")),
				"size": 2.0 if i % 3 != 0 else 3.0,
			})


func _draw_ground_fx() -> void:
	if _shock_age >= 0.0 and _shock_age < 0.95:
		var p: float = _shock_age / 0.95
		var rx: float = lerpf(28.0, _arena_radii.x * 0.98, 1.0 - pow(1.0 - p, 2.2))
		var ry: float = lerpf(20.0, _arena_radii.y * 0.98, 1.0 - pow(1.0 - p, 2.2))
		var alpha: float = (1.0 - p) * 0.75
		var center: Vector2 = _basin_center - global_position
		var steps: int = 56
		for i: int in steps:
			var ang: float = float(i) / float(steps) * TAU
			var pt: Vector2 = (center + Vector2(cos(ang) * rx, sin(ang) * ry)).round()
			var c_outer: Color = Color("78f4e6" if i % 2 == 0 else "ffe488", alpha * 0.75)
			_ground_fx.draw_rect(Rect2(pt - Vector2.ONE, Vector2(3.0, 2.0)), c_outer)
			_ground_fx.draw_rect(Rect2(pt, Vector2.ONE), Color("ffffff", alpha * 0.92))
	for m: Dictionary in _dust_motes:
		var a: float = clampf(float(m["life"]) / maxf(float(m["max_life"]), 0.05), 0.0, 1.0)
		var mp: Vector2 = ((m["pos"] as Vector2) - global_position).round()
		var sz: float = float(m["size"])
		_ground_fx.draw_rect(Rect2(mp, Vector2.ONE * sz), Color(m["col"] as Color, a))


func _play_sound(cue: String, db_offset: float = 0.0, pitch: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless" or _voice == null:
		return
	var audio_cfg: Dictionary = _def.get("audio", {}) as Dictionary
	var path: String = String(audio_cfg.get(cue, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	if not _audio_cache.has(path):
		_audio_cache[path] = load(path)
	var stream: AudioStream = _audio_cache[path] as AudioStream
	if stream == null:
		return
	_voice.stream = stream
	_voice.volume_db = float(audio_cfg.get("volume_db", -5.0)) + db_offset
	_voice.pitch_scale = pitch
	_voice.play()


func _exit_tree() -> void:
	if _bar_shown and is_inside_tree() and _health != null and _health.current > 0.0:
		get_tree().call_group("boss_bar", "release")
	if is_instance_valid(_voice):
		_voice.stop()
	if is_instance_valid(field):
		field.queue_free()
