class_name LocomotionComponent
extends Node
## Shadowspore 2.0 player locomotion brain (`T1..T5`, `T7`, `T9..T12`, `V3`, `V9`, `V10`):
## - 130 ms `FluidActionBuffer` for zero swallowed inputs across landings, drinks, swings & steps
## - Non-linear acceleration, `Sprint Surge`, carving turns & 180-degree `Hard Pivot`
## - Dual-ray `CornerNudge` obstacle feelers around trees, stones, fences & cliff edges
## - `Relief` slope gradient speed modulation + stair micro-bobbing
## - Out-of-combat `Reisetritt` travel stride (zero stamina on roads, -65 % in wilderness)
## - Adaptive `LivingCamera 2.0` (comfort deadzone + sprint lead + combat/aim cursor framing)
## - 20 Hz `Hermite`/exponential remote-peer smoothing + packed `sync_flags`
## - `LocomotionImpulse` dispatch to `LivingGrass`, `StealthComponent`, and night `Flora` resonance

signal impulse_emitted(world_pos: Vector2, dir: Vector2, kind: String)

const WORLD_LAYER_MASK: int = 1

@export var sync_flags: int = 0 ## Replicated ON_CHANGE: bits 0..1 quadrant, bit 2 reisetritt, bit 3 pivot, bit 4 brake

var move_age: float = 0.0
var sprint_age: float = 0.0
var surge_left: float = 0.0
var pivot_left: float = 0.0
var brake_left: float = 0.0
var start_left: float = 0.0
var crouch_bridge_left: float = 0.0
var crouch_going_down: bool = true
var step_exit_left: float = 0.0
var step_exit_speed: float = 0.0
var reisetritt: bool = false
var on_road_surface: bool = false
var quadrant: int = MovementRules.Quadrant.FORWARD
var stair_bob: float = 0.0
var prowl_shade: float = 0.0
var idle_wind_px: float = 0.0
var headwind_lean: float = 0.0

var _player: Player
var _shape: CollisionShape2D
var _buffers: Dictionary = {} ## action_name -> float seconds remaining
var _was_sprinting: bool = false
var _was_moving: bool = false
var _was_sneaking: bool = false
var _cam_anchor: Vector2 = Vector2.ZERO
var _cam_lead: Vector2 = Vector2.ZERO
var _cam_ready: bool = false
var _threat_timer: float = 0.0
var _near_threat: bool = false
var _flora_timer: float = 0.0
var _shade_timer: float = 0.0
var _shade_target: float = 0.0

var _remote_ready: bool = false
var _expected_pos: Vector2 = Vector2.ZERO
var _visual_offset: Vector2 = Vector2.ZERO


func setup(owner_player: Player) -> void:
	_player = owner_player
	_shape = _player.get_node_or_null("CollisionShape2D") as CollisionShape2D


func poll_action_buffer(delta: float) -> void:
	for k_v: Variant in _buffers.keys():
		var k: String = String(k_v)
		var rem: float = float(_buffers[k]) - delta
		if rem <= 0.0:
			_buffers.erase(k)
		else:
			_buffers[k] = rem

	var win: float = float(MovementRules.section("buffer").get("window_seconds", 0.13))
	if InputManager.shadow_step_pressed():
		_buffers["shadow_step"] = win
	if InputManager.attack_just_pressed():
		_buffers["attack"] = win
	if InputManager.secondary_pressed():
		_buffers["secondary"] = win
	if InputManager.interact_pressed():
		_buffers["interact"] = win
	if InputManager.sprint_pressed():
		_buffers["sprint"] = win


func peek_buffered(action: String) -> bool:
	return float(_buffers.get(action, 0.0)) > 0.0


func consume_buffered(action: String) -> bool:
	if float(_buffers.get(action, 0.0)) <= 0.0:
		return false
	_buffers.erase(action)
	return true


func clear_buffer(action: String = "") -> void:
	if action.is_empty():
		_buffers.clear()
	else:
		_buffers.erase(action)


func can_movement_cancel_busy(busy_kind: String, busy_time: float, busy_len: float) -> bool:
	if busy_kind.begins_with("cast_") or busy_kind == "touch" or busy_kind == "feed":
		return false
	var tail: float = float(MovementRules.section("buffer").get("cancel_tail_seconds", 0.17))
	return busy_len > 0.35 and busy_time >= busy_len - tail


func step_ground_locomotion(
	delta: float,
	raw_dir: Vector2,
	surface_id: String,
	surface_data: Dictionary,
	can_sprint: bool,
	want_sprint: bool,
	winded_in: bool,
	in_combat: bool,
	aim_dir: Vector2,
	charging: bool
) -> Dictionary:
	if _player == null:
		return {"velocity": Vector2.ZERO, "sprinting": false, "winded": winded_in}

	_tick_threat_and_world(delta)

	var moving_input: bool = raw_dir.length_squared() > 0.001
	if moving_input:
		if not _was_moving and _player.velocity.length() < 18.0:
			start_left = 0.16
		move_age += delta
		brake_left = 0.0
	else:
		move_age = 0.0
		start_left = 0.0

	start_left = maxf(start_left - delta, 0.0)
	pivot_left = maxf(pivot_left - delta, 0.0)
	brake_left = maxf(brake_left - delta, 0.0)
	surge_left = maxf(surge_left - delta, 0.0)
	step_exit_left = maxf(step_exit_left - delta, 0.0)

	var rt_info: Dictionary = MovementRules.reisetritt_state(in_combat or charging, _near_threat, surface_id, sprint_age)
	on_road_surface = bool(rt_info.get("on_road", false))
	var stamina_scale: float = float(rt_info.get("stamina_scale", 1.0))

	var winded: bool = winded_in
	if not InputManager.sprint_held() or _player.stamina.current >= Player.SPRINT_RECOVER or (not in_combat and not _near_threat):
		winded = false

	var now_sprinting: bool = false
	if want_sprint and can_sprint and not winded:
		var drain_rate: float = _player.sprint_cost_per_sec * _player.stamina.sprint_scale() * stamina_scale
		if drain_rate <= 0.001:
			now_sprinting = true
		elif _player.stamina.current > 0.0:
			now_sprinting = _player.stamina.drain(drain_rate, delta)
			if not now_sprinting and (in_combat or _near_threat):
				winded = true

	if now_sprinting:
		var is_webbed: bool = _player.effects != null and _player.effects.has("webbed")
		if not is_webbed and not _was_sprinting and (_player.velocity.length() < _player.sprint_speed * 0.92 or consume_buffered("sprint")):
			var curves: Dictionary = MovementRules.section("curves")
			surge_left = float(curves.get("sprint_surge_seconds", 0.18))
			emit_world_impulse(_player.global_position, raw_dir.normalized(), 18.0, 0.78, 5.2, "surge")
		elif is_webbed:
			surge_left = 0.0
		sprint_age += delta
		reisetritt = bool(rt_info.get("active", false))
	else:
		reisetritt = false
		if moving_input:
			sprint_age = 0.0

	var sneaking_now: bool = _player.stealth.sneaking
	if sneaking_now != _was_sneaking:
		crouch_bridge_left = 0.11
		crouch_going_down = sneaking_now
		_was_sneaking = sneaking_now
	crouch_bridge_left = maxf(crouch_bridge_left - delta, 0.0)

	if in_combat and not now_sprinting and moving_input and aim_dir.length_squared() > 0.01:
		quadrant = MovementRules.combat_quadrant(raw_dir, aim_dir)
	else:
		quadrant = MovementRules.Quadrant.FORWARD

	var base_speed: float = _player.sprint_speed if now_sprinting else (_player.sneak_speed if sneaking_now else _player.max_speed)
	var surf_mult: float = float(surface_data.get("speed", 1.0))
	if not sneaking_now and surf_mult >= 1.0:
		surf_mult *= MovementRules.road_speed_bonus(surface_id)
	if now_sprinting:
		surf_mult *= float(rt_info.get("speed_mult", 1.0))
	var slope_mult: float = _sample_slope_factor(raw_dir) if moving_input else 1.0
	var combat_mult: float = MovementRules.combat_speed_scale(quadrant) if (in_combat and not now_sprinting) else 1.0
	var step_glide_mult: float = float(MovementRules.section("spore_step").get("exit_glide_mult", 1.14)) if step_exit_left > 0.0 else 1.0
	var target_speed: float = (
		base_speed
		* surf_mult
		* slope_mult
		* combat_mult
		* step_glide_mult
		* _player._slow_factor()
		* (Player.WOUND_SPEED if _player.wounded else 1.0)
		* _player.attack.charge_move_factor()
	)

	if step_exit_left > 0.0:
		var exit_dur: float = maxf(float(MovementRules.section("spore_step").get("exit_glide_seconds", 0.15)), 0.01)
		target_speed = maxf(target_speed, step_exit_speed * lerpf(0.88, 1.0, clampf(step_exit_left / exit_dur, 0.0, 1.0)))

	var puddle_amt: float = WeatherManager.current.puddle if WeatherManager.current != null else 0.0
	var traction: float = MovementRules.surface_traction(surface_id, _player._wet, puddle_amt)

	var steered_input: Vector2 = _apply_corner_nudge(raw_dir) if moving_input else Vector2.ZERO

	var res: Dictionary = MovementRules.step_velocity(
		_player.velocity,
		steered_input,
		target_speed,
		delta,
		move_age,
		surge_left,
		sprint_age,
		traction,
		pivot_left > 0.0
	)
	var next_vel: Vector2 = res["velocity"] as Vector2

	if not moving_input:
		sprint_age = 0.0

	if bool(res.get("pivoted", false)):
		var turn_cfg: Dictionary = MovementRules.section("turn")
		pivot_left = float(turn_cfg.get("pivot_seconds", 0.14))
		_player.stealth.impulse_bonus = 0.18
		emit_world_impulse(_player.global_position, raw_dir.normalized(), 22.0, 0.92, 6.8, "pivot")
	elif bool(res.get("braking", false)) and _was_moving and brake_left <= 0.0:
		brake_left = 0.24

	_update_stair_and_weather_posture(delta, next_vel)

	_was_sprinting = now_sprinting
	_was_moving = moving_input
	_pack_sync_flags()

	return {
		"velocity": next_vel,
		"sprinting": now_sprinting,
		"winded": winded,
	}


func trigger_step_exit_glide(carry_speed: float = 0.0) -> void:
	step_exit_left = float(MovementRules.section("spore_step").get("exit_glide_seconds", 0.15))
	step_exit_speed = carry_speed


func _apply_corner_nudge(input_vec: Vector2) -> Vector2:
	if _player == null or _shape == null or input_vec.length_squared() < 0.04:
		return input_vec
	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	if space == null:
		return input_vec
	var cfg: Dictionary = MovementRules.section("corner_nudge")
	var reach: float = float(cfg.get("feeler_reach", 8.5))
	var spread: float = float(cfg.get("feeler_spread", 4.8))
	var mag: float = input_vec.length()
	var dir: Vector2 = input_vec / mag
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var origin: Vector2 = _shape.global_position
	var excl: Array[RID] = [_player.get_rid()]

	var q_mid: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, origin + dir * (reach * 0.9), WORLD_LAYER_MASK, excl)
	if not space.intersect_ray(q_mid).is_empty():
		return input_vec

	var q_l: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin - perp * spread, origin - perp * spread + dir * reach, WORLD_LAYER_MASK, excl)
	var q_r: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin + perp * spread, origin + perp * spread + dir * reach, WORLD_LAYER_MASK, excl)
	var hit_l: Dictionary = space.intersect_ray(q_l)
	var hit_r: Dictionary = space.intersect_ray(q_r)
	if hit_l.is_empty() == hit_r.is_empty():
		return input_vec

	var push_side: float = 1.0 if not hit_l.is_empty() else -1.0
	var blended: Vector2 = (dir + perp * (push_side * 0.52)).normalized()
	return blended * mag


func _sample_slope_factor(input_vec: Vector2) -> float:
	var relief: Relief = Terrain.relief
	if relief == null or _player == null or input_vec.length_squared() < 0.01:
		return 1.0
	var probe: float = float(MovementRules.section("topography").get("probe_px", 8.0))
	var pos: Vector2 = _player.global_position
	var h0: float = relief.level_at(pos)
	var h1: float = relief.level_at(pos + input_vec.normalized() * probe)
	return MovementRules.slope_factor(h0, h1, probe)


func _update_stair_and_weather_posture(delta: float, vel: Vector2) -> void:
	var target_bob: float = 0.0
	var relief: Relief = Terrain.relief
	if relief != null and vel.length() > 14.0:
		var tx: int = floori(_player.global_position.x / Relief.TILE)
		var ty: int = floori(_player.global_position.y / Relief.TILE)
		var k: int = relief.kind(tx, ty)
		if k == Relief.STAIRS or k == Relief.STEPS:
			var step_wave: float = absf(sin(_player.global_position.y * (PI / 4.0)))
			target_bob = -float(MovementRules.section("topography").get("stair_bob_px", 1.0)) * step_wave
	stair_bob = move_toward(stair_bob, target_bob, 14.0 * delta)

	var target_lean: float = 0.0
	if WorldWind.current != null and vel.length() > 45.0 and Interiors.slot_at(_player.global_position) < 0:
		var wind_v: Vector2 = WorldWind.sample_soft(_player.global_position)
		var against: float = clampf(-vel.normalized().dot(wind_v), 0.0, 1.5)
		if against > 0.35:
			target_lean = clampf((against - 0.35) * 0.045, 0.0, 0.035) * signf(vel.x)
	headwind_lean = lerpf(headwind_lean, target_lean, minf(1.0, 8.0 * delta))


func _tick_threat_and_world(delta: float) -> void:
	_player.stealth.impulse_bonus = move_toward(_player.stealth.impulse_bonus, 0.0, 0.85 * delta)
	var surf_id: String = Terrain.surface_at(_player.global_position)
	_player.stealth.surface_noise_mult = MovementRules.surface_noise_scale(surf_id)

	_threat_timer -= delta
	if _threat_timer <= 0.0:
		_threat_timer = 0.25
		_near_threat = false
		var r: float = float(MovementRules.section("reisetritt").get("threat_radius", 150.0))
		var r2: float = r * r
		for node: Node in get_tree().get_nodes_in_group("predators"):
			var enemy: Node2D = node as Node2D
			if enemy != null and enemy.is_inside_tree() and enemy.global_position.distance_squared_to(_player.global_position) <= r2:
				_near_threat = true
				break

	_shade_timer -= delta
	if _shade_timer <= 0.0:
		_shade_timer = 0.12
		_shade_target = _compute_shadow_cover()
	var want_prowl: float = _shade_target if _player.stealth.sneaking else 0.0
	_player.stealth.shadow_cover = _shade_target if _player.stealth.sneaking else 0.0
	if absf(prowl_shade - want_prowl) > 0.004:
		prowl_shade = move_toward(prowl_shade, want_prowl, 3.2 * delta)
		(_player._sprite.material as ShaderMaterial).set_shader_parameter("prowl_shade", prowl_shade)

	var want_wind: float = 0.0
	if _player.velocity.length_squared() < 9.0 and not _player.is_busy() and _player.swim == 0 and WorldWind.current != null and Interiors.slot_at(_player.global_position) < 0:
		var wv: Vector2 = WorldWind.sample_soft(_player.global_position)
		if absf(wv.x) > 0.42:
			want_wind = clampf(roundf(wv.x * 1.35), -1.0, 1.0)
	if want_wind != idle_wind_px:
		idle_wind_px = want_wind
		(_player._sprite.material as ShaderMaterial).set_shader_parameter("idle_wind_px", idle_wind_px)

	_flora_timer -= delta
	if _flora_timer <= 0.0:
		_flora_timer = 0.16
		_pulse_nearby_night_flora()


func _compute_shadow_cover() -> float:
	if _player == null:
		return 0.0
	var night_k: float = TimeManager.night_amount()
	var cover: float = night_k * 0.72
	for grass_node: Node in get_tree().get_nodes_in_group("living_grass"):
		var lg: LivingGrass = grass_node as LivingGrass
		if lg != null and lg._bounds.has_point(_player.global_position):
			cover = maxf(cover, 0.45)
			break
	for tree_node: Node in get_tree().get_nodes_in_group("bird_perches"):
		var tree: Node2D = tree_node as Node2D
		if tree != null and tree.global_position.distance_squared_to(_player.global_position) < 42.0 * 42.0:
			cover = maxf(cover, 0.65)
			break
	return clampf(cover, 0.0, 1.0)


func _pulse_nearby_night_flora() -> void:
	if _player == null or TimeManager.night_amount() < 0.30 or _player.sprinting:
		return
	var pos: Vector2 = _player.global_position
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		var flora: Flora = node as Flora
		if flora == null or not flora.is_inside_tree() or flora._glow == null:
			continue
		var d2: float = flora.global_position.distance_squared_to(pos)
		if d2 > 48.0 * 48.0 or d2 < 4.0:
			continue
		var k: float = 1.0 - sqrt(d2) / 48.0
		var toward_x: float = signf(pos.x - flora.global_position.x)
		flora._sprite.skew = lerpf(flora._sprite.skew, -toward_x * 0.045 * k, 0.35)
		flora._glow.self_modulate.a = clampf(maxf(flora._glow.self_modulate.a, 0.85 + 0.15 * k), 0.0, 1.0)


func emit_world_impulse(world_pos: Vector2, dir: Vector2, radius: float, crush: float, wobble: float, kind: String) -> void:
	for node: Node in get_tree().get_nodes_in_group("living_grass"):
		var lg: LivingGrass = node as LivingGrass
		if lg != null:
			lg.apply_locomotion_impulse(world_pos, dir, radius, crush, wobble, kind)
	impulse_emitted.emit(world_pos, dir, kind)


func compute_camera_offset(delta: float, active_control: bool) -> Vector2:
	if _player == null or not active_control:
		_cam_lead = _cam_lead.lerp(Vector2.ZERO, 1.0 - exp(-4.0 * delta))
		return _cam_lead

	var cam_cfg: Dictionary = MovementRules.section("camera")
	var dz: float = float(cam_cfg.get("deadzone_px", 9.0))
	var pos: Vector2 = _player.global_position
	if not _cam_ready:
		_cam_anchor = pos
		_cam_ready = true

	var drift: Vector2 = pos - _cam_anchor
	var drift_len: float = drift.length()
	var dz_exc: float = 0.0
	if drift_len > dz:
		_cam_anchor = pos - (drift / drift_len) * dz
		dz_exc = clampf((drift_len - dz) / 8.0, 0.35, 1.0)
	elif _player.velocity.length() > 52.0:
		dz_exc = clampf((_player.velocity.length() - 52.0) / 40.0, 0.0, 1.0)

	var aim_framing: bool = false
	var aim_delta: Vector2 = Vector2.ZERO
	if InputManager.using_mouse and not InputManager.ui_blocking and not InputManager.mod_menu_open:
		var combat_now: bool = _player.attack.is_in_combat(2.2) or _player.attack.is_charging() or (_player.spells != null and _player.spells.staff_held and _player.attack.holds_staff())
		if combat_now:
			aim_framing = true
			aim_delta = InputManager.aim_world_position() - (pos + Player.BODY_CENTER)

	var goal: Vector2 = MovementRules.camera_lead_target(_player.velocity, dz_exc, _player.sprinting, reisetritt, aim_delta, aim_framing)
	var ease_spd: float = float(cam_cfg.get("ease_speed", 3.8))
	_cam_lead = _cam_lead.lerp(goal, 1.0 - exp(-ease_spd * delta))
	return _cam_lead


func reset_camera_anchor() -> void:
	if _player != null:
		_cam_anchor = _player.global_position
	_cam_lead = Vector2.ZERO
	_cam_ready = true
	_remote_ready = false
	_visual_offset = Vector2.ZERO


func step_remote_smoothing(delta: float) -> Vector2:
	if _player == null or _player.is_multiplayer_authority():
		return Vector2.ZERO
	var net_cfg: Dictionary = MovementRules.section("network")
	var decay: float = float(net_cfg.get("hermite_decay", 18.0))
	var snap_d: float = float(net_cfg.get("snap_distance", 42.0))

	if not _remote_ready:
		_expected_pos = _player.global_position
		_visual_offset = Vector2.ZERO
		_remote_ready = true

	var packet_jump: Vector2 = _player.global_position - _expected_pos
	if packet_jump.length_squared() > 0.04:
		if packet_jump.length() > snap_d:
			_visual_offset = Vector2.ZERO
		else:
			_visual_offset -= packet_jump

	_player.position += _player.velocity * delta
	_expected_pos = _player.global_position
	_visual_offset = _visual_offset.lerp(Vector2.ZERO, 1.0 - exp(-decay * delta))

	quadrant = sync_flags & 3
	reisetritt = (sync_flags & 4) != 0
	if (sync_flags & 8) != 0 and pivot_left <= 0.0:
		pivot_left = 0.12
	if (sync_flags & 16) != 0 and brake_left <= 0.0:
		brake_left = 0.20
	pivot_left = maxf(pivot_left - delta, 0.0)
	brake_left = maxf(brake_left - delta, 0.0)
	return _visual_offset


func _pack_sync_flags() -> void:
	var packed: int = (quadrant & 3)
	if reisetritt:
		packed |= 4
	if pivot_left > 0.0:
		packed |= 8
	if brake_left > 0.0:
		packed |= 16
	if sync_flags != packed:
		sync_flags = packed
