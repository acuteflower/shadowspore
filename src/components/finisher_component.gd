class_name FinisherComponent
extends Node
## Shadowspore 2.0 — Host-Authoritative V2 Finisher Controller (`T1`..`T7`, `V1`..`V5`), extended by docs/finisher_v2_konzept.md.
## Orchestrates lethal melee sword hit interception (and, Finisher V2, the E request on an exposed core), reliable ENet pair-synchronization
## across 1–4 peers, and the choreography: take-off -> apex hang -> plunge -> grinding second press -> rip-out (the core is torn out) ->
## settle or blade flick (story flag). Multi-stage hit stops, local `FinisherStage` (dusk, focus, bars, shock, ducking), a solo-only slow
## motion over the apex, the Kern-Bruch death, the reward (stamina + `shadow_rush`) and a one-time name card. Fail-safe `1-HP` death hold
## completion on rip-out, watchdog or scene exit. Timeline and numbers: data/finishers.json.

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
var _stage: FinisherStage = null
var _beat_mask: int = 0 ## bit 1 = plunge, bit 2 = press, bit 4 = rip, bit 8 = apex, bit 16 = settle
var _kill_committed: bool = false
var _flick: bool = false ## the ending: false = back into the guard, true = the blade flick (owner's story flag, sent to all)
var _slowmo_owned: bool = false
var _cam_zoom_bonus: float = 0.0
var _cam_shift_bonus: Vector2 = Vector2.ZERO
var _cam_punch: Vector2 = Vector2.ZERO
var _base_cam_zoom: Vector2 = Vector2.ONE
var _cam_zoom_captured: bool = false


func setup(player: Player) -> void:
	_player = player


func _exit_tree() -> void:
	if _window_player == _player:
		_window_player = null
		_window_stack = {}
	_restore_camera()
	_release_slowmo()
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


## Host: true while a sword blow of some player is being dealt (inside `open/close_melee_hit_window`).
static func melee_window_open() -> bool:
	return _window_player != null and is_instance_valid(_window_player)


## Host only: called from `HealthComponent.take_damage` right when a melee hit would drop `target_health` to `<= 0`.
static func try_intercept_lethal(target_health: HealthComponent, final_damage: float, from_pos: Vector2, source_peer: int) -> bool:
	var p: Player = _window_player
	if not FinisherRules.player_can_finish(p):
		return false
	if source_peer != 0 and source_peer != p.get_multiplayer_authority():
		return false
	var eff_stack: Dictionary = _window_stack
	if not eff_stack.has("id") and p.inventory != null:
		eff_stack = p.inventory.active_stack()
	if eff_stack.is_empty() and p.attack != null and p.attack.held_weapon != "":
		eff_stack = {"id": p.attack.held_weapon, "count": 1}
	var target: Node2D = target_health.get_parent() as Node2D
	var _unused_dmg: float = final_damage
	return _host_try_begin(p, target, target_health, eff_stack, from_pos)


## Host: the shared start of every finisher (lethal blow or E request). Checks weapon, target, eligibility and room, holds the target at 1 HP and launches.
static func _host_try_begin(p: Player, target: Node2D, target_health: HealthComponent, eff_stack: Dictionary, from_pos: Vector2) -> bool:
	if not FinisherRules.weapon_supports_finisher(eff_stack):
		return false
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or target_health == null:
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

	# Hold the target at 1.0 HP until the rip-out.
	var survivable_dmg: float = maxf(target_health.current - 1.0, 0.0)
	if survivable_dmg > 0.01:
		target_health.take_survivable(survivable_dmg, from_pos, 0.0, p.get_multiplayer_authority())
	else:
		target_health.last_attacker = p.get_multiplayer_authority()
		target_health.hitters[p.get_multiplayer_authority()] = true
	target_health.grant_grace(float(move_cfg.get("duration", 1.25)) + 1.0)

	if is_boss:
		_push_back_nearby_minions(p, target)

	var w_id: String = String(eff_stack.get("id", p.attack.held_weapon))
	var ref_lvl: int = int(eff_stack.get(RefineRules.KEY_LEVEL, p.attack.held_refine))
	_window_player = null
	_window_stack = {}
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


# --- Finisher V2: E on an exposed core -----------------------------------------------------------------------------


## Local owner: E on a target whose core is exposed (`SpiderFinisherPrompt`). The host decides.
func request_finisher(target: Node2D) -> void:
	if _player == null or _active or target == null or not is_instance_valid(target):
		return
	if multiplayer.is_server():
		_host_request(target)
	elif NetworkManager.rpc_ready(self):
		_rpc_request_finisher.rpc_id(1, target.get_path())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_finisher(target_path: NodePath) -> void:
	if not multiplayer.is_server() or _player == null:
		return
	if multiplayer.get_remote_sender_id() != _player.get_multiplayer_authority():
		return
	_host_request(get_node_or_null(target_path) as Node2D)


func _host_request(target: Node2D) -> void:
	if target == null or not is_instance_valid(target) or not FinisherRules.player_can_finish(_player):
		return
	if not target.has_method("finisher_prompt_text") or String(target.call("finisher_prompt_text")) == "":
		return
	var reach: float = float(FinisherRules.settings().get("exposed_trigger_reach", 34.0)) + 18.0 ## slack for lag
	if _player.global_position.distance_to(target.global_position) > reach:
		return
	var hp: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	var stack: Dictionary = _player.inventory.active_stack() if _player.inventory != null else {}
	_host_try_begin(_player, target, hp, stack, _player.global_position)


# --- state for the rig, the sword and the stage --------------------------------------------------------------------


func active() -> bool:
	return _active


func sector() -> int:
	return _sector


func strike_dir() -> Vector2:
	return _strike_dir


## Seconds into the running finisher (its own clock: hit stops hold it, the solo slow motion slows it).
func elapsed() -> float:
	return _elapsed


func config() -> Dictionary:
	return _cfg


func flick_ending() -> bool:
	return _flick


## Normalized progress `0..1` across the active Finisher clip.
func progress() -> float:
	if not _active:
		return 0.0
	return clampf(_elapsed / maxf(float(_cfg.get("duration", 1.25)), 0.01), 0.0, 1.0)


## Continuous keyframe index `0 .. frames - 1` on `player_finisher.png` (sheet columns, see tools/art_hero_finisher.py).
## Data `keys` = [[time, column], ...] piecewise linear; with the flick ending `flick_keys` take over from `t_settle`.
func frame_key() -> float:
	var total: int = maxi(int(_cfg.get("frames", 16)), 2)
	var keys: Array = _cfg.get("keys", []) as Array
	var flick_keys: Array = _cfg.get("flick_keys", []) as Array
	var key: float = 0.0
	if _flick and flick_keys.size() >= 2 and _elapsed >= float((flick_keys[0] as Array)[0]):
		key = _sample_keys(flick_keys, _elapsed)
	elif keys.size() >= 2:
		key = _sample_keys(keys, _elapsed)
	else:
		key = progress() * float(total - 1)
	return clampf(key, 0.0, float(total) - 0.001)


static func _sample_keys(keys: Array, t: float) -> float:
	var first: Array = keys[0] as Array
	if t <= float(first[0]):
		return float(first[1])
	for i: int in range(1, keys.size()):
		var b: Array = keys[i] as Array
		if t <= float(b[0]):
			var a: Array = keys[i - 1] as Array
			var span: float = maxf(float(b[0]) - float(a[0]), 0.0001)
			return lerpf(float(a[1]), float(b[1]), (t - float(a[0])) / span)
	return float((keys[keys.size() - 1] as Array)[1])


## Height of the jump: up fast, a hang at the apex (a breath of drift), then a hard drop into the plunge.
func air_height() -> float:
	if not _active:
		return 0.0
	var t0: float = float(_cfg.get("hop_start", 0.04))
	var ta: float = float(_cfg.get("apex_start", 0.16))
	var tb: float = float(_cfg.get("apex_end", 0.30))
	var t1: float = float(_cfg.get("hop_end", 0.34))
	var h: float = float(_cfg.get("hop_height", 13.0))
	var e: float = _elapsed
	if e <= t0 or e >= t1:
		return 0.0
	if e < ta:
		var k: float = (e - t0) / maxf(ta - t0, 0.01)
		return h * (1.0 - (1.0 - k) * (1.0 - k))
	if e < tb:
		var kh: float = (e - ta) / maxf(tb - ta, 0.01)
		return h + sin(kh * PI) * 1.0
	var kd: float = (e - tb) / maxf(t1 - tb, 0.01)
	return h * (1.0 - kd * kd)


## True once the rip has fired AND `_elapsed >= move_cancel_at`, letting responsive movement take over early.
func can_move_cancel() -> bool:
	if not _active or (_beat_mask & 4) == 0:
		return false
	return _elapsed >= float(FinisherRules.settings().get("move_cancel_at", 1.08))


## The 3D sword orientation (`dir`) and how deep it is buried (`embed`: 0..0.48) for `AttackComponent`:
## raised and turned point-down on the way up, held still over the apex, driven in, pressed deeper, ripped out in a rising crescent,
## then back to rest or the flick (snapped down and out to her side).
func blade_pose(swing_from: Vector3, rest_dir: Vector3) -> Dictionary:
	if not _active:
		return {}
	var forward: Vector2 = _strike_dir
	var ta: float = float(_cfg.get("apex_start", 0.16))
	var tb: float = float(_cfg.get("apex_end", 0.30))
	var t1: float = float(_cfg.get("t_plunge", 0.34))
	var t2: float = float(_cfg.get("t_press", 0.62))
	var t3: float = float(_cfg.get("t_rip", 0.80))
	var ts: float = float(_cfg.get("t_settle", 0.95))
	var dur: float = maxf(float(_cfg.get("duration", 1.25)), ts + 0.01)

	var impale_dir: Vector3 = GripRig.body_dir(forward, 0.02, deg_to_rad(-82.0))
	var press_dir: Vector3 = GripRig.body_dir(forward, 0.16, deg_to_rad(-85.0))
	var rip_high_dir: Vector3 = GripRig.body_dir(forward, 0.92, deg_to_rad(58.0))
	var flick_dir: Vector3 = GripRig.body_dir(forward, 1.45, deg_to_rad(-38.0))
	var low_ready_dir: Vector3 = GripRig.body_dir(forward, 1.05, deg_to_rad(-52.0))

	var out_dir: Vector3 = impale_dir
	var embed: float = 0.0
	var emit_motes: int = 0
	var track_ribbon: bool = false
	var e: float = _elapsed

	if e < ta:
		# Up: the blade turns point-down while she rises.
		var u_up: float = clampf(e / maxf(ta, 0.01), 0.0, 1.0)
		out_dir = AttackComponent._turn(swing_from, impale_dir, AttackComponent._smooth(u_up))
	elif e < tb:
		# Apex hang: held still, a faint tremor of tension.
		var trem: float = sin(e * 61.0) * 0.012
		out_dir = (impale_dir + Vector3(trem, -trem, 0.0)).normalized()
		emit_motes = 1
	elif e < t1:
		# The drop: driven in.
		var u_down: float = clampf((e - tb) / maxf(t1 - tb, 0.01), 0.0, 1.0)
		embed = lerpf(0.0, 0.24, smoothstep(0.55, 1.0, u_down))
		emit_motes = 2
		track_ribbon = true
	elif e < t2:
		var u_p: float = clampf((e - t1) / maxf(t2 - t1, 0.01), 0.0, 1.0)
		# Grinding press: a slight coil, then slam deeper into the core.
		var drive_k: float = smoothstep(0.42, 0.96, u_p)
		var lift_pre: float = sin(clampf(u_p / 0.42, 0.0, 1.0) * PI) * 0.06
		embed = clampf(0.24 - lift_pre + drive_k * 0.22, 0.14, 0.46)
		var shiver: float = sin(e * 58.0) * (0.015 + 0.03 * u_p) * (1.0 - drive_k * 0.5)
		out_dir = impale_dir.slerp(press_dir, drive_k).normalized()
		out_dir = (out_dir + Vector3(shiver, -shiver, 0.0)).normalized()
		if drive_k > 0.5:
			emit_motes = 2
	elif e < t3:
		var u_hold: float = clampf((e - t2) / maxf(t3 - t2, 0.01), 0.0, 1.0)
		# Buried core vibration before wrenching free.
		var vib: float = sin(e * 74.0) * 0.035 * (1.0 - u_hold * 0.4)
		embed = lerpf(0.46, 0.38, smoothstep(0.65, 1.0, u_hold))
		out_dir = (press_dir + Vector3(vib, vib * 0.5, 0.0)).normalized()
	elif e < ts:
		var u_rip: float = clampf((e - t3) / maxf(ts - t3, 0.01), 0.0, 1.0)
		var kr: float = 1.0 - pow(1.0 - u_rip, 2.6)
		out_dir = AttackComponent._turn(press_dir, rip_high_dir, kr)
		embed = lerpf(0.38, 0.0, clampf(kr * 2.2, 0.0, 1.0))
		emit_motes = 1
		track_ribbon = true
	elif _flick:
		var u_f: float = clampf((e - ts) / maxf(dur - ts, 0.01), 0.0, 1.0)
		if u_f < 0.3:
			var snap: float = 1.0 - pow(1.0 - u_f / 0.3, 3.0)
			out_dir = AttackComponent._turn(rip_high_dir, flick_dir, snap)
			track_ribbon = true
		else:
			var settle_k: float = AttackComponent._smooth((u_f - 0.3) / 0.7)
			out_dir = AttackComponent._turn(flick_dir, low_ready_dir, settle_k)
	else:
		var ks: float = clampf((e - ts) / maxf(dur - ts, 0.01), 0.0, 1.0)
		out_dir = AttackComponent._turn(rip_high_dir, rest_dir, AttackComponent._smooth(ks))

	var behind: bool = forward.y < -0.45 and e >= tb and e <= t3 + 0.04
	return {
		"dir": out_dir,
		"embed": embed,
		"emit_motes": emit_motes,
		"track_ribbon": track_ribbon,
		"behind": behind,
	}


# --- start ---------------------------------------------------------------------------------------------------------


func _host_launch(move_id: String, target: Node2D, pair: Dictionary, weapon_id: String, refine_lvl: int) -> void:
	if _player == null:
		return
	var cfg: Dictionary = FinisherRules.move_config(move_id)
	var dur: float = float(cfg.get("duration", 1.25))
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
	_watchdog_left = float(cfg.get("duration", 1.25)) + float(FinisherRules.settings().get("watchdog_padding", 0.28)) + 1.0 ## + slack for the solo slow motion
	_start_pos = start_pos
	_stand_pos = stand_pos
	_target_pos = target_pos
	_sector = posmod(sec, 8)
	_strike_dir = Vector2.from_angle(float(_sector) * (PI / 4.0))
	_weapon_id = weapon_id
	_refine_level = refine_lvl
	_beat_mask = 0
	_kill_committed = false
	_flick = false
	_cam_punch = Vector2.ZERO

	_target = get_node_or_null(target_path) as Node2D
	_player.velocity = Vector2.ZERO
	_player.sprinting = false
	if _player.stealth != null:
		_player.stealth.sneaking = false
	_player.facing = _strike_dir
	if _player.attack != null:
		_player.attack.prepare_for_finisher(_strike_dir, weapon_id, refine_lvl)

	var dur: float = float(cfg.get("duration", 1.25))
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
		_announce_ending()

	if _local_viewer_near() and DisplayServer.get_name() != "headless":
		_stage = FinisherStage.play(self, _target_pos)

	finisher_started.emit(move_id, _target)


## Owner: the ending depends on her story (flag `flick_flag`: she has seen the knight shake his blade clean). Sent to every peer.
func _announce_ending() -> void:
	var flag: String = String(FinisherRules.settings().get("flick_flag", "rescued"))
	var flick: bool = _player.quests != null and (flag == "" or _player.quests.has_flag(flag))
	if NetworkManager.rpc_ready(self) and not multiplayer.get_peers().is_empty():
		_rpc_set_ending.rpc(flick)
	else:
		_rpc_set_ending(flick)


@rpc("authority", "call_local", "reliable")
func _rpc_set_ending(flick: bool) -> void:
	if _active:
		_flick = flick


## True when the local player of this machine watches: it is her own finisher or she stands within `stage_radius`.
func _local_viewer_near() -> bool:
	if _player.is_multiplayer_authority():
		return true
	var radius: float = float(FinisherRules.settings().get("stage_radius", 220.0))
	for node: Node in get_tree().get_nodes_in_group("players"):
		var p: Player = node as Player
		if p != null and p.is_multiplayer_authority():
			return p.global_position.distance_to(_target_pos) <= radius
	return false


# --- the clock -----------------------------------------------------------------------------------------------------


func step_physics(delta: float) -> void:
	if not _active or _player == null:
		return

	if multiplayer.is_server() and not _kill_committed:
		_watchdog_left -= delta
		if _watchdog_left <= 0.0:
			_force_commit_pending_kill()

	# Glide onto the 8-sector strike anchor while airborne.
	var slide_dur: float = maxf(float(_cfg.get("slide_duration", 0.3)), 0.02)
	if _elapsed < slide_dur:
		var sk: float = clampf((_elapsed + delta) / slide_dur, 0.0, 1.0)
		var eased_s: float = 1.0 - (1.0 - sk) * (1.0 - sk)
		_player.global_position = _start_pos.lerp(_stand_pos, eased_s)
	elif _elapsed < float(_cfg.get("t_rip", 0.80)):
		_player.global_position = _stand_pos
	_player.velocity = Vector2.ZERO
	_player.facing = _strike_dir

	# Local responsive movement cancel in the final settle frames after the rip.
	if _player.is_multiplayer_authority() and can_move_cancel():
		if InputManager.move_vector() != Vector2.ZERO or InputManager.shadow_step_pressed():
			_finish_sequence()
			return

	if _freeze_left > 0.0:
		_freeze_left = maxf(_freeze_left - delta, 0.0)
		_update_camera(delta)
		return

	_elapsed += delta
	var t_apex: float = float(_cfg.get("apex_start", 0.16))
	var t_plunge: float = float(_cfg.get("t_plunge", 0.34))
	var t_press: float = float(_cfg.get("t_press", 0.62))
	var t_rip: float = float(_cfg.get("t_rip", 0.80))
	var t_settle: float = float(_cfg.get("t_settle", 0.95))
	var dur: float = float(_cfg.get("duration", 1.25))

	if (_beat_mask & 8) == 0 and _elapsed >= t_apex:
		_beat_mask |= 8
		_on_apex()
	if (_beat_mask & 1) == 0 and _elapsed >= t_plunge:
		_beat_mask |= 1
		_on_beat_plunge()
	if (_beat_mask & 2) == 0 and _elapsed >= t_press:
		_beat_mask |= 2
		_on_beat_press()
	if (_beat_mask & 4) == 0 and _elapsed >= t_rip:
		_beat_mask |= 4
		_on_beat_rip()
	if (_beat_mask & 16) == 0 and _elapsed >= t_settle:
		_beat_mask |= 16
		_on_settle()

	_update_slowmo()
	_update_camera(delta)

	if _elapsed >= dur:
		_finish_sequence()


## Solo only (a host without peers): the world slows over the apex. With peers `Engine.time_scale` would slow everybody, so hit stops and the stage carry it.
func _update_slowmo() -> void:
	var solo: bool = multiplayer.is_server() and multiplayer.get_peers().is_empty()
	if not solo or DisplayServer.get_name() == "headless":
		_release_slowmo()
		return
	var cfg: Dictionary = FinisherRules.settings()
	var a: float = float(cfg.get("slowmo_from", 0.14))
	var b: float = float(cfg.get("slowmo_to", 0.32))
	if _elapsed <= a or _elapsed >= b:
		_release_slowmo()
		return
	var k: float = (_elapsed - a) / maxf(b - a, 0.01)
	var w: float = smoothstep(0.0, 0.25, k) * (1.0 - smoothstep(0.7, 1.0, k))
	Engine.time_scale = lerpf(1.0, float(cfg.get("slowmo_scale", 0.35)), w)
	_slowmo_owned = true


func _release_slowmo() -> void:
	if _slowmo_owned:
		Engine.time_scale = 1.0
		_slowmo_owned = false


# --- beats ---------------------------------------------------------------------------------------------------------


func _on_apex() -> void:
	Sfx.at(_player, "finisher_apex", _target_pos, -3.0, 0.03)
	if _fx != null and is_instance_valid(_fx):
		_fx.trigger_apex_glint()


func _on_beat_plunge() -> void:
	_freeze_left = float(_cfg.get("hitstop_plunge", 0.09))
	if _player.is_multiplayer_authority():
		_player.add_shake(float(_cfg.get("shake_plunge", 3.6)))
	Sfx.at(_player, "finisher_plunge", _target_pos, -1.0, 0.04)
	if _fx != null and is_instance_valid(_fx):
		_fx.trigger_plunge()
	if _stage != null and is_instance_valid(_stage):
		_stage.punch(0.8)
	if _target != null and is_instance_valid(_target) and _target.has_method("on_finisher_beat"):
		_target.call("on_finisher_beat", 1)
	_stamp_world_burst(_target_pos, 22.0, 0.78, false)
	finisher_beat.emit(_move_id, 1)


func _on_beat_press() -> void:
	_freeze_left = float(_cfg.get("hitstop_press", 0.06))
	if _player.is_multiplayer_authority():
		_player.add_shake(float(_cfg.get("shake_press", 4.0)))
	Sfx.at(_player, "finisher_press", _target_pos, -0.5, 0.04)
	if _fx != null and is_instance_valid(_fx):
		_fx.trigger_press()
	if _stage != null and is_instance_valid(_stage):
		_stage.punch(0.45)
	if _target != null and is_instance_valid(_target) and _target.has_method("on_finisher_beat"):
		_target.call("on_finisher_beat", 2)
	_stamp_world_burst(_target_pos, 26.0, 0.90, false)
	finisher_beat.emit(_move_id, 2)


func _on_beat_rip() -> void:
	_freeze_left = float(_cfg.get("hitstop_rip", 0.12))
	if _player.is_multiplayer_authority():
		_player.add_shake(float(_cfg.get("shake_rip", 5.4)))
	Sfx.at(_player, "finisher_rip", _target_pos, 0.0, 0.04)
	Sfx.at(_player, "finisher_core", _target_pos, -1.5, 0.02)
	var rip_vec: Vector2 = (-_strike_dir + Vector2(0.0, -0.65)).normalized()
	_cam_punch = rip_vec * float(_cfg.get("rip_punch_px", 6.0))
	if _fx != null and is_instance_valid(_fx):
		_fx.trigger_rip(rip_vec)
		_fx.trigger_core_tear(rip_vec, _player)
		_fx.trigger_core_break()
	if _stage != null and is_instance_valid(_stage):
		_stage.punch(1.0, 1.0)
	if _target != null and is_instance_valid(_target) and _target.has_method("on_finisher_beat"):
		_target.call("on_finisher_beat", 3)
	_stamp_world_burst(_target_pos, 38.0, 1.0, true)
	_leave_scar()
	if multiplayer.is_server():
		_force_commit_pending_kill()
		_grant_reward()
	finisher_beat.emit(_move_id, 3)


func _on_settle() -> void:
	if _flick:
		Sfx.at(_player, "finisher_flick", _player.global_position, -2.0, 0.05)
	_maybe_show_name_card()


func _leave_scar() -> void:
	var scene_root: Node = get_tree().current_scene if get_tree().current_scene != null else _player.get_parent()
	if scene_root == null or DisplayServer.get_name() == "headless":
		return
	var scar: FinisherScar = FinisherScar.new()
	scar.setup(_target_pos, _strike_dir)
	scene_root.add_child(scar)


## Host: the core's sparks fly into her: stamina back and Schattenrausch (data/finishers.json settings, data/status_effects.json `shadow_rush`).
func _grant_reward() -> void:
	if _player == null or _player.health.current <= 0.0:
		return
	var cfg: Dictionary = FinisherRules.settings()
	if _player.stamina != null:
		_player.stamina.restore(_player.stamina.max_stamina * float(cfg.get("reward_stamina_ratio", 0.35)))
	var effect: String = String(cfg.get("reward_effect", "shadow_rush"))
	if effect != "" and _player.effects != null:
		_player.effects.apply(effect)


## Owner, once per save: the name of the move condenses on screen (`FinisherCard`), the flag remembers it.
func _maybe_show_name_card() -> void:
	if not _player.is_multiplayer_authority() or _player.quests == null:
		return
	var flag: String = String(FinisherRules.settings().get("name_card_flag", ""))
	if flag == "" or _player.quests.has_flag(flag):
		return
	_player.quests.set_flag(flag)
	if DisplayServer.get_name() != "headless":
		FinisherCard.play(_player, String(_cfg.get("card", _cfg.get("name", ""))))


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
	var t_plunge: float = float(_cfg.get("t_plunge", 0.34))
	var t_press: float = float(_cfg.get("t_press", 0.62))
	var t_rip: float = float(_cfg.get("t_rip", 0.80))
	var z1: float = float(_cfg.get("zoom_plunge", 1.06)) - 1.0
	var z2: float = float(_cfg.get("zoom_press", 1.08)) - 1.0
	var shift_px: float = float(_cfg.get("view_shift_px", 5.0))

	var goal_bonus: float = 0.0
	var goal_shift: Vector2 = Vector2.ZERO
	if _elapsed < t_plunge:
		goal_bonus = z1 * smoothstep(0.05, t_plunge, _elapsed)
		goal_shift = _strike_dir * shift_px * 0.7
	elif _elapsed < t_press:
		goal_bonus = lerpf(z1, z2, smoothstep(t_plunge, t_press, _elapsed))
		goal_shift = _strike_dir * shift_px
	elif _elapsed < t_rip:
		goal_bonus = z2
		goal_shift = _strike_dir * shift_px
	else:
		var release_k: float = smoothstep(t_rip, float(_cfg.get("duration", 1.25)), _elapsed)
		goal_bonus = z2 * (1.0 - release_k)
		goal_shift = _strike_dir * shift_px * (1.0 - release_k)
	_cam_punch = _cam_punch.move_toward(Vector2.ZERO, 40.0 * delta)
	goal_shift += _cam_punch

	var rate: float = 16.0 if goal_bonus >= _cam_zoom_bonus else 11.0
	_cam_zoom_bonus = lerpf(_cam_zoom_bonus, goal_bonus, 1.0 - exp(-rate * delta))
	var prev_shift: Vector2 = _cam_shift_bonus
	_cam_shift_bonus = _cam_shift_bonus.lerp(goal_shift, 1.0 - exp(-18.0 * delta))
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
	_cam_punch = Vector2.ZERO
	_cam_zoom_captured = false


func _finish_sequence() -> void:
	if not _active:
		return
	if multiplayer.is_server() and not _kill_committed:
		_force_commit_pending_kill()
	if (_beat_mask & 16) == 0:
		_beat_mask |= 16
		_maybe_show_name_card()
	var finished_id: String = _move_id
	_active = false
	_beat_mask = 0
	_freeze_left = 0.0
	_release_slowmo()
	_restore_camera()
	if _player != null and _player.attack != null:
		_player.attack.end_finisher()
	finisher_completed.emit(finished_id)
