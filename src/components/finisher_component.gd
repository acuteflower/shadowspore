class_name FinisherComponent
extends Node
## Shadowspore 2.0 — Host-Authoritative V2 Finisher Controller (`T1`..`T7`, `V1`..`V5`).
## Orchestrates lethal melee sword hit interception, reliable ENet pair-synchronization across 1–4 peers,
## 3-beat choreography (`Plunge` -> `Second Deep Press` -> `Rip-Out`), multi-stage hit-stops,
## subtle local `LivingCamera` micro-zoom, `LivingGrass`/`WaterField`/`ShadowTrail` world impulses,
## and fail-safe `1-HP` Death-Hold completion on rip-out or scene exit.

signal finisher_started(move_id: String, target: Node2D)
signal finisher_beat(move_id: String, beat_index: int)
signal finisher_completed(move_id: String)

static var _window_player: Player = null
static var _window_stack: Dictionary = {}

var _player: Player = null
var _active: bool = false
var _move_id: String = ""
var _cfg: Dictionary = {}
var _elapsed: float = 0.0
var _freeze_left: float = 0.0
var _watchdog_left: float = 0.0

var _start_pos: Vector2 = Vector2.ZERO
var _stand_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _strike_dir: Vector2 = Vector2.RIGHT
var _sector: int = 0
var _weapon_id: String = ""
var _refine_level: int = 0

var _target: Node2D = null
var _fx: FinisherFx = null
var _beat_mask: int = 0 ## bit 1 = plunge, bit 2 = press, bit 4 = rip
var _kill_committed: bool = false
var _cam_zoom_bonus: float = 0.0
var _cam_shift_bonus: Vector2 = Vector2.ZERO
var _base_cam_zoom: Vector2 = Vector2.ONE
var _cam_zoom_captured: bool = false


func setup(player: Player) -> void:
	_player = player


func _exit_tree() -> void:
	if _window_player == _player:
		_window_player = null
		_window_stack = {}
	_restore_camera()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_force_commit_pending_kill()


## Host only: opened around `AttackComponent._hit_scan` so lethal melee sword blows can trigger a Finisher.
func open_melee_hit_window(stack: Dictionary) -> void:
	if _player == null or _active:
		return
	_window_player = _player
	_window_stack = stack


func close_melee_hit_window() -> void:
	if _window_player == _player:
		_window_player = null
		_window_stack = {}


## Host only: called from `HealthComponent.take_damage` right when a melee hit would drop `target_health` to `<= 0`.
static func try_intercept_lethal(target_health: HealthComponent, final_damage: float, from_pos: Vector2, source_peer: int) -> bool:
	var p: Player = _window_player
	if p == null or not is_instance_valid(p) or p.finisher == null or p.finisher.active():
		return false
	if not p.is_inside_tree() or not p.is_physics_processing():
		return false
	if source_peer != 0 and source_peer != p.get_multiplayer_authority():
		return false
	if p.health.current <= 0.0 or p.intro != null or p.story_lock or p.fainting or p.stumbling:
		return false
	if p.swim > 0 or p.climb.active() or p.carry_stone != 0 or (p.agile != null and p.agile.active()):
		return false

	var eff_stack: Dictionary = _window_stack
	if not eff_stack.has("id") and p.inventory != null:
		eff_stack = p.inventory.active_stack()
	if eff_stack.is_empty() and p.attack != null and p.attack.held_weapon != "":
		eff_stack = {"id": p.attack.held_weapon, "count": 1}
	if not FinisherRules.weapon_supports_finisher(eff_stack):
		return false

	var target: Node2D = target_health.get_parent() as Node2D
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if target.has_method("can_accept_finisher") and not bool(target.call("can_accept_finisher")):
		return false

	var move_id: String = FinisherRules.pick_move_for_target(target)
	if move_id == "":
		return false
	var move_cfg: Dictionary = FinisherRules.move_config(move_id)
	if move_cfg.is_empty():
		return false

	# Core V2 Eligibility Rule (`T2`): Boss target OR no other living enemy in combat with Ellie!
	var is_boss: bool = FinisherRules.is_target_boss(target)
	if not is_boss and not FinisherRules.is_last_engaged_threat(p, [target]):
		return false

	var pair: Dictionary = FinisherRules.resolve_pair_positions(p, target, move_cfg)
	if not bool(pair.get("valid", false)):
		return false

	# Intercept lethal blow -> hold target at 1.0 HP until Beat 3 (`t_rip`)!
	var survivable_dmg: float = maxf(target_health.current - 1.0, 0.0)
	if survivable_dmg > 0.01:
		target_health.take_survivable(survivable_dmg, from_pos, 0.0, p.get_multiplayer_authority())
	else:
		target_health.last_attacker = p.get_multiplayer_authority()
		target_health.hitters[p.get_multiplayer_authority()] = true
	target_health.grant_grace(float(move_cfg.get("duration", 1.02)) + 1.0)

	if is_boss:
		_push_back_nearby_minions(p, target)

	var w_id: String = String(eff_stack.get("id", p.attack.held_weapon))
	var ref_lvl: int = int(eff_stack.get(RefineRules.KEY_LEVEL, p.attack.held_refine))
	_window_player = null
	_window_stack = {}
	var _unused_dmg: float = final_damage
	p.finisher._host_launch(move_id, target, pair, w_id, ref_lvl)
	return true


static func _push_back_nearby_minions(player: Player, boss_target: Node2D) -> void:
	var cfg: Dictionary = FinisherRules.settings()
	var rad: float = float(cfg.get("boss_minion_push_radius", 140.0))
	var push_spd: float = float(cfg.get("boss_minion_push_speed", 92.0))
	for node: Node in player.get_tree().get_nodes_in_group("predators"):
		var other: Node2D = node as Node2D
		if other == null or other == boss_target or not is_instance_valid(other):
			continue
		if other.global_position.distance_to(boss_target.global_position) > rad:
			continue
		if other.has_method("on_pack_ally_slain"):
			other.call("on_pack_ally_slain", boss_target.global_position)
		if other is CharacterBody2D:
			var away: Vector2 = (other.global_position - boss_target.global_position).normalized()
			if away.length_squared() < 0.01:
				away = Vector2.UP
			(other as CharacterBody2D).velocity = away * push_spd


func active() -> bool:
	return _active


func sector() -> int:
	return _sector


func strike_dir() -> Vector2:
	return _strike_dir


## Normalized progress `0..1` across the active Finisher clip.
func progress() -> float:
	if not _active:
		return 0.0
	return clampf(_elapsed / maxf(float(_cfg.get("duration", 1.02)), 0.01), 0.0, 1.0)


## Exact continuous keyframe index `0 .. frames - 1` on `player_finisher.png` for 60–144 Hz arm blending!
func frame_key() -> float:
	var total: int = maxi(int(_cfg.get("frames", 16)), 2)
	var u: float = progress()
	var dur: float = maxf(float(_cfg.get("duration", 1.02)), 0.01)
	var t_plunge: float = float(_cfg.get("t_plunge", 0.24)) / dur
	var t_press: float = float(_cfg.get("t_press", 0.52)) / dur
	var t_rip: float = float(_cfg.get("t_rip", 0.78)) / dur
	# Map real beat timestamps strictly onto sculpted sheet columns:
	#   0..4   -> Approach hop & plunge impact (`0 .. t_plunge`)
	#   4..8   -> Tension hold & 2nd deep press impact (`t_plunge .. t_press`)
	#   8..11  -> Grinding core twist & brace (`t_press .. t_rip`)
	#   11..15 -> Violent rip-out & combat guard settle (`t_rip .. 1.0`)
	var key: float = 0.0
	if u < t_plunge:
		key = lerpf(0.0, 4.0, clampf(u / maxf(t_plunge, 0.01), 0.0, 1.0))
	elif u < t_press:
		key = lerpf(4.0, 8.2, clampf((u - t_plunge) / maxf(t_press - t_plunge, 0.01), 0.0, 1.0))
	elif u < t_rip:
		key = lerpf(8.2, 11.0, clampf((u - t_press) / maxf(t_rip - t_press, 0.01), 0.0, 1.0))
	else:
		key = lerpf(11.0, float(total - 1), clampf((u - t_rip) / maxf(1.0 - t_rip, 0.01), 0.0, 1.0))
	return clampf(key, 0.0, float(total - 1) - 0.001)


## Airborne hop arc during Beat 1A (`0.03 .. 0.24 s`) so Ellie springs slightly upward into the plunge!
func air_height() -> float:
	if not _active:
		return 0.0
	var t0: float = float(_cfg.get("hop_start", 0.03))
	var t1: float = float(_cfg.get("hop_end", 0.24))
	if _elapsed <= t0 or _elapsed >= t1:
		return 0.0
	var k: float = (_elapsed - t0) / maxf(t1 - t0, 0.01)
	return sin(k * PI) * float(_cfg.get("hop_height", 5.5))


## True once Beat 3 (`t_rip`) has already fired AND `_elapsed >= move_cancel_at`, letting responsive movement take over early!
func can_move_cancel() -> bool:
	if not _active or (_beat_mask & 4) == 0:
		return false
	return _elapsed >= float(FinisherRules.settings().get("move_cancel_at", 0.90))


## Computes the 3D sword orientation (`dir`: Vector3) & visible penetration length (`embed`: 0..0.48)
## for `AttackComponent` so any equipped sword plunges vertically into the carapace, sinks 4 px deeper
## on Beat 2, and rips upward in a wide crescent on Beat 3 (`T5`, `V1`, `V4`).
func blade_pose(swing_from: Vector3, rest_dir: Vector3) -> Dictionary:
	if not _active:
		return {}
	var forward: Vector2 = _strike_dir
	var dur: float = maxf(float(_cfg.get("duration", 1.02)), 0.01)
	var t1: float = float(_cfg.get("t_plunge", 0.24))
	var t2: float = float(_cfg.get("t_press", 0.52))
	var t3: float = float(_cfg.get("t_rip", 0.78))

	var apex_dir: Vector3 = GripRig.body_dir(forward, -0.14, deg_to_rad(106.0))
	var impale_dir: Vector3 = GripRig.body_dir(forward, 0.02, deg_to_rad(-82.0))
	var press_dir: Vector3 = GripRig.body_dir(forward, 0.16, deg_to_rad(-85.0))
	var rip_high_dir: Vector3 = GripRig.body_dir(forward, 0.92, deg_to_rad(58.0))

	var out_dir: Vector3 = impale_dir
	var embed: float = 0.0 ## 0 = full blade shown .. 0.46 = buried halfway to crossguard inside carapace!
	var emit_motes: int = 0
	var track_ribbon: bool = false

	if _elapsed < t1 * 0.62:
		var u_up: float = clampf(_elapsed / maxf(t1 * 0.62, 0.01), 0.0, 1.0)
		out_dir = AttackComponent._turn(swing_from, apex_dir, AttackComponent._smooth(u_up))
	elif _elapsed < t1:
		var u_down: float = clampf((_elapsed - t1 * 0.62) / maxf(t1 * 0.38, 0.01), 0.0, 1.0)
		var fast_down: float = u_down * u_down
		out_dir = AttackComponent._turn(apex_dir, impale_dir, fast_down)
		embed = lerpf(0.0, 0.24, smoothstep(0.65, 1.0, u_down))
		emit_motes = 2
		track_ribbon = true
	elif _elapsed < t2:
		var u_p: float = clampf((_elapsed - t1) / maxf(t2 - t1, 0.01), 0.0, 1.0)
		# Slight coil at 0.34..0.44s (`u_p ~ 0.35..0.65`), then slam 4 px deeper into the core!
		var drive_k: float = smoothstep(0.42, 0.96, u_p)
		var lift_pre: float = sin(clampf(u_p / 0.42, 0.0, 1.0) * PI) * 0.06
		embed = clampf(0.24 - lift_pre + drive_k * 0.22, 0.14, 0.46)
		var shiver: float = sin(_elapsed * 58.0) * 0.025 * (1.0 - drive_k * 0.5)
		out_dir = impale_dir.slerp(press_dir, drive_k).normalized()
		out_dir = (out_dir + Vector3(shiver, -shiver, 0.0)).normalized()
		if drive_k > 0.5:
			emit_motes = 2
	elif _elapsed < t3:
		var u_hold: float = clampf((_elapsed - t2) / maxf(t3 - t2, 0.01), 0.0, 1.0)
		# Intense buried core vibration before wrenching free!
		var vib: float = sin(_elapsed * 74.0) * 0.035 * (1.0 - u_hold * 0.4)
		embed = lerpf(0.46, 0.38, smoothstep(0.65, 1.0, u_hold))
		out_dir = (press_dir + Vector3(vib, vib * 0.5, 0.0)).normalized()
	else:
		var u_rip: float = clampf((_elapsed - t3) / maxf(dur - t3, 0.01), 0.0, 1.0)
		if u_rip < 0.48:
			var kr: float = 1.0 - pow(1.0 - (u_rip / 0.48), 2.6)
			out_dir = AttackComponent._turn(press_dir, rip_high_dir, kr)
			embed = lerpf(0.38, 0.0, clampf(kr * 2.2, 0.0, 1.0))
			emit_motes = 1
			track_ribbon = true
		else:
			var ks: float = (u_rip - 0.48) / 0.52
			out_dir = AttackComponent._turn(rip_high_dir, rest_dir, AttackComponent._smooth(ks))
			embed = 0.0

	var behind: bool = forward.y < -0.45 and _elapsed >= t1 * 0.75 and _elapsed <= t3 + 0.04
	return {
		"dir": out_dir,
		"embed": embed,
		"emit_motes": emit_motes,
		"track_ribbon": track_ribbon,
		"behind": behind,
	}


func _host_launch(move_id: String, target: Node2D, pair: Dictionary, weapon_id: String, refine_lvl: int) -> void:
	if _player == null:
		return
	var cfg: Dictionary = FinisherRules.move_config(move_id)
	var dur: float = float(cfg.get("duration", 1.02))
	var pad: float = float(FinisherRules.settings().get("grace_padding", 0.35))
	_player.health.grant_grace(dur + pad)
	if _player.effects != null and _player.effects.has("webbed"):
		_player.effects.clear("webbed")
	var t_path: NodePath = target.get_path()
	var s_pos: Vector2 = _player.global_position
	var stand_p: Vector2 = pair["stand_pos"] as Vector2
	var targ_p: Vector2 = pair["target_pos"] as Vector2
	var sec: int = int(pair["sector"])
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_begin_finisher.rpc(move_id, t_path, s_pos, stand_p, targ_p, sec, weapon_id, refine_lvl)
	else:
		_rpc_begin_finisher(move_id, t_path, s_pos, stand_p, targ_p, sec, weapon_id, refine_lvl)


@rpc("any_peer", "call_local", "reliable")
func _rpc_begin_finisher(
	move_id: String,
	target_path: NodePath,
	start_pos: Vector2,
	stand_pos: Vector2,
	target_pos: Vector2,
	sec: int,
	weapon_id: String,
	refine_lvl: int
) -> void:
	var sender: int = multiplayer.get_remote_sender_id() if multiplayer.has_multiplayer_peer() else 0
	if sender != 0 and sender != 1:
		return
	if _player == null:
		return
	var cfg: Dictionary = FinisherRules.move_config(move_id)
	if cfg.is_empty():
		return

	_active = true
	_move_id = move_id
	_cfg = cfg
	_elapsed = 0.0
	_freeze_left = 0.0
	_watchdog_left = float(cfg.get("duration", 1.02)) + float(FinisherRules.settings().get("watchdog_padding", 0.28))
	_start_pos = start_pos
	_stand_pos = stand_pos
	_target_pos = target_pos
	_sector = posmod(sec, 8)
	_strike_dir = Vector2.from_angle(float(_sector) * (PI / 4.0))
	_weapon_id = weapon_id
	_refine_level = refine_lvl
	_beat_mask = 0
	_kill_committed = false

	_target = get_node_or_null(target_path) as Node2D
	_player.velocity = Vector2.ZERO
	_player.sprinting = false
	if _player.stealth != null:
		_player.stealth.sneaking = false
	_player.facing = _strike_dir
	if _player.attack != null:
		_player.attack.prepare_for_finisher(_strike_dir, weapon_id, refine_lvl)

	var dur: float = float(cfg.get("duration", 1.02))
	if _target != null and is_instance_valid(_target) and _target.has_method("begin_finisher_impale"):
		_target.call("begin_finisher_impale", stand_pos, target_pos, _sector, dur)

	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else _player.get_parent()
	if scene_root != null:
		_fx = FinisherFx.new()
		scene_root.add_child(_fx)
		var edge_c: Color = _player.attack.trail_edge_color() if _player.attack != null else Color("aac8ff")
		var core_c: Color = _player.attack.trail_core_color() if _player.attack != null else Color("f2f7ff")
		_fx.setup(_target_pos, _strike_dir, edge_c, core_c)

	if _player.is_multiplayer_authority():
		var cam: Camera2D = _player.view_camera()
		if cam != null and not _cam_zoom_captured:
			_base_cam_zoom = cam.zoom
			_cam_zoom_captured = true

	finisher_started.emit(move_id, _target)


func step_physics(delta: float) -> void:
	if not _active or _player == null:
		return

	if multiplayer.is_server() and not _kill_committed:
		_watchdog_left -= delta
		if _watchdog_left <= 0.0:
			_force_commit_pending_kill()

	# Smooth magnetic glide onto the 8-sector strike anchor during the Beat-1A hop (`0 .. slide_duration`)!
	var slide_dur: float = maxf(float(_cfg.get("slide_duration", 0.12)), 0.02)
	if _elapsed < slide_dur:
		var sk: float = clampf((_elapsed + delta) / slide_dur, 0.0, 1.0)
		var eased_s: float = 1.0 - (1.0 - sk) * (1.0 - sk)
		_player.global_position = _start_pos.lerp(_stand_pos, eased_s)
	elif _elapsed < float(_cfg.get("t_rip", 0.78)):
		_player.global_position = _stand_pos
	_player.velocity = Vector2.ZERO
	_player.facing = _strike_dir

	# Local responsive movement cancel in the final settle frames (`>= 0.90 s`) after Beat 3 has fired
	if _player.is_multiplayer_authority() and can_move_cancel():
		if InputManager.move_vector() != Vector2.ZERO or InputManager.shadow_step_pressed():
			_finish_sequence()
			return

	if _freeze_left > 0.0:
		_freeze_left = maxf(_freeze_left - delta, 0.0)
		_update_camera(delta)
		return

	_elapsed += delta
	var t_plunge: float = float(_cfg.get("t_plunge", 0.24))
	var t_press: float = float(_cfg.get("t_press", 0.52))
	var t_rip: float = float(_cfg.get("t_rip", 0.78))
	var dur: float = float(_cfg.get("duration", 1.02))

	if (_beat_mask & 1) == 0 and _elapsed >= t_plunge:
		_beat_mask |= 1
		_on_beat_plunge()
	if (_beat_mask & 2) == 0 and _elapsed >= t_press:
		_beat_mask |= 2
		_on_beat_press()
	if (_beat_mask & 4) == 0 and _elapsed >= t_rip:
		_beat_mask |= 4
		_on_beat_rip()

	_update_camera(delta)

	if _elapsed >= dur:
		_finish_sequence()


func _on_beat_plunge() -> void:
	_freeze_left = float(_cfg.get("hitstop_plunge", 0.045))
	if _player.is_multiplayer_authority():
		_player.add_shake(float(_cfg.get("shake_plunge", 3.2)))
	Sfx.at(_player, "finisher_plunge", _target_pos, -1.0, 0.04)
	if _fx != null and is_instance_valid(_fx):
		_fx.trigger_plunge()
	if _target != null and is_instance_valid(_target) and _target.has_method("on_finisher_beat"):
		_target.call("on_finisher_beat", 1)
	_stamp_world_burst(_target_pos, 22.0, 0.78, false)
	finisher_beat.emit(_move_id, 1)


func _on_beat_press() -> void:
	_freeze_left = float(_cfg.get("hitstop_press", 0.055))
	if _player.is_multiplayer_authority():
		_player.add_shake(float(_cfg.get("shake_press", 4.0)))
	Sfx.at(_player, "finisher_press", _target_pos, -0.5, 0.04)
	if _fx != null and is_instance_valid(_fx):
		_fx.trigger_press()
	if _target != null and is_instance_valid(_target) and _target.has_method("on_finisher_beat"):
		_target.call("on_finisher_beat", 2)
	_stamp_world_burst(_target_pos, 26.0, 0.90, false)
	finisher_beat.emit(_move_id, 2)


func _on_beat_rip() -> void:
	_freeze_left = float(_cfg.get("hitstop_rip", 0.035))
	if _player.is_multiplayer_authority():
		_player.add_shake(float(_cfg.get("shake_rip", 4.8)))
	Sfx.at(_player, "finisher_rip", _target_pos, 0.0, 0.04)
	var rip_vec: Vector2 = (-_strike_dir + Vector2(0.0, -0.65)).normalized()
	if _fx != null and is_instance_valid(_fx):
		_fx.trigger_rip(rip_vec)
	if _target != null and is_instance_valid(_target) and _target.has_method("on_finisher_beat"):
		_target.call("on_finisher_beat", 3)
	_stamp_world_burst(_target_pos, 38.0, 1.0, true)
	if multiplayer.is_server():
		_force_commit_pending_kill()
	finisher_beat.emit(_move_id, 3)


func _force_commit_pending_kill() -> void:
	if _kill_committed:
		return
	_kill_committed = true
	if _target == null or not is_instance_valid(_target):
		return
	var peer_id: int = _player.get_multiplayer_authority() if _player != null else 1
	if _target.has_method("complete_finisher_kill"):
		_target.call("complete_finisher_kill", peer_id)
	else:
		var hp: HealthComponent = _target.get_node_or_null("HealthComponent") as HealthComponent
		if hp != null and hp.current > 0.0:
			hp.hitters[peer_id] = true
			hp.kill(_stand_pos, peer_id)


func _stamp_world_burst(at: Vector2, radius: float, strength: float, with_slash: bool) -> void:
	if _player == null or not _player.is_inside_tree():
		return
	for grass_node: Node in _player.get_tree().get_nodes_in_group("living_grass"):
		if grass_node != null and grass_node.has_method("stamp_burst"):
			grass_node.call("stamp_burst", at, radius, strength)
		if with_slash and grass_node != null and grass_node.has_method("stamp_slash"):
			grass_node.call("stamp_slash", at, -_strike_dir, 28.0, 0.92)
	for patch: Node in Terrain.patches:
		if patch != null and patch.has_method("water_field_at"):
			var wf: Dictionary = patch.call("water_field_at", at) as Dictionary
			if bool(wf.get("in_bounds", false)) and float(wf.get("depth", 0.0)) > 0.02 and patch.has_method("add_ripple"):
				patch.call("add_ripple", at, radius * 0.45, strength)


func _update_camera(delta: float) -> void:
	if _player == null or not _player.is_multiplayer_authority():
		return
	var cam: Camera2D = _player.view_camera()
	if cam == null or not _cam_zoom_captured:
		return
	var t_plunge: float = float(_cfg.get("t_plunge", 0.24))
	var t_press: float = float(_cfg.get("t_press", 0.52))
	var t_rip: float = float(_cfg.get("t_rip", 0.78))
	var z1: float = float(_cfg.get("zoom_plunge", 1.08)) - 1.0
	var z2: float = float(_cfg.get("zoom_press", 1.11)) - 1.0

	var goal_bonus: float = 0.0
	var goal_shift: Vector2 = Vector2.ZERO
	if _elapsed < t_plunge:
		goal_bonus = z1 * smoothstep(0.05, t_plunge, _elapsed)
		goal_shift = _strike_dir * float(_cfg.get("view_shift_px", 5.0)) * 0.7
	elif _elapsed < t_press:
		goal_bonus = lerpf(z1, z2, smoothstep(t_plunge, t_press, _elapsed))
		goal_shift = _strike_dir * float(_cfg.get("view_shift_px", 5.0))
	elif _elapsed < t_rip:
		goal_bonus = z2
		goal_shift = _strike_dir * float(_cfg.get("view_shift_px", 5.0))
	else:
		var release_k: float = smoothstep(t_rip, float(_cfg.get("duration", 1.02)), _elapsed)
		goal_bonus = z2 * (1.0 - release_k)
		goal_shift = _strike_dir * float(_cfg.get("view_shift_px", 5.0)) * (1.0 - release_k)

	var rate: float = 16.0 if goal_bonus >= _cam_zoom_bonus else 11.0
	_cam_zoom_bonus = lerpf(_cam_zoom_bonus, goal_bonus, 1.0 - exp(-rate * delta))
	var prev_shift: Vector2 = _cam_shift_bonus
	_cam_shift_bonus = _cam_shift_bonus.lerp(goal_shift, 1.0 - exp(-14.0 * delta))
	cam.zoom = _base_cam_zoom * (1.0 + _cam_zoom_bonus)
	_player.view_shift += (_cam_shift_bonus - prev_shift)


func _restore_camera() -> void:
	if _player != null and _cam_zoom_captured:
		var cam: Camera2D = _player.view_camera()
		if cam != null:
			cam.zoom = _base_cam_zoom
		_player.view_shift -= _cam_shift_bonus
	_cam_zoom_bonus = 0.0
	_cam_shift_bonus = Vector2.ZERO
	_cam_zoom_captured = false


func _finish_sequence() -> void:
	if not _active:
		return
	if multiplayer.is_server() and not _kill_committed:
		_force_commit_pending_kill()
	var finished_id: String = _move_id
	_active = false
	_beat_mask = 0
	_freeze_left = 0.0
	_restore_camera()
	if _player != null and _player.attack != null:
		_player.attack.end_finisher()
	finisher_completed.emit(finished_id)
