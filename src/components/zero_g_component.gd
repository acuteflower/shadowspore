class_name ZeroGComponent
extends Node
## Manages weightless interstellar floating for `Player` (docs/caelia_interstellar_konzept.md):
##   - Activates deterministically on every peer whenever `_surface.get("zero_g", false)` is true.
##   - Runs `ZeroGRules.step_motion` for the local authority (360-degree inertia, Shift Boost-Glide
##     with zero stamina drain, Ctrl/C Hover-Brake & precision hover, Soft Veil Horizon curve-back).
##   - Drives elastic Zero-G camera astral-lead + gentle framing pull when hovering near Caelia.
##   - Emits stardust wake trails into `StarHallRoom` and velocity-linked ethereal glide audio.

const AUDIO_DIR: String = "res://assets/audio/zero_g/"
const ARRIVE_DURATION: float = 1.12
const STANDBY_WAIT_MIN: float = 9.0
const STANDBY_WAIT_MAX: float = 14.0

var active: bool = false
var arrive_left: float = 0.0
var float_time: float = 0.0
var bob_time: float = 0.0
var horizon_amt: float = 0.0
var boost_cd: float = 0.0
var standby_active: bool = false
var standby_time: float = 0.0

var _player: Player
var _was_active: bool = false
var _was_glide: bool = false
var _was_brake: bool = false
var _cam_lead: Vector2 = Vector2.ZERO
var _trail_acc: float = 0.0
var _standby_wait: float = 10.5
var _idle_quiet: float = 0.0
var _hint_sent: bool = false

var _glide_loop: AudioStreamPlayer
var _sfx_boost: AudioStream
var _sfx_brake: AudioStream
var _sfx_arrive: AudioStream
var _star_rim_light: PointLight2D


func setup(owner_player: Player) -> void:
	_player = owner_player
	name = "ZeroGComponent"
	_load_audio()
	if _player != null:
		_star_rim_light = PointLight2D.new()
		_star_rim_light.name = "ZeroGStarRim"
		_star_rim_light.position = Vector2(0.0, -18.0)
		_star_rim_light.color = Color("b6dcff")
		_star_rim_light.energy = 0.34
		_star_rim_light.enabled = false
		LightTexture.apply(_star_rim_light, 88, 0.86, 0)
		_player.add_child(_star_rim_light)


func _load_audio() -> void:
	if _player == null or not _player.is_multiplayer_authority():
		return
	var loop_path: String = AUDIO_DIR + "glide_loop.wav"
	if ResourceLoader.exists(loop_path):
		_glide_loop = AudioStreamPlayer.new()
		_glide_loop.stream = load(loop_path) as AudioStream
		_glide_loop.volume_db = -80.0
		_glide_loop.finished.connect(func() -> void:
			if active and is_instance_valid(_glide_loop):
				_glide_loop.play())
		add_child(_glide_loop)
	if ResourceLoader.exists(AUDIO_DIR + "boost.wav"):
		_sfx_boost = load(AUDIO_DIR + "boost.wav") as AudioStream
	if ResourceLoader.exists(AUDIO_DIR + "brake.wav"):
		_sfx_brake = load(AUDIO_DIR + "brake.wav") as AudioStream
	if ResourceLoader.exists(AUDIO_DIR + "arrive.wav"):
		_sfx_arrive = load(AUDIO_DIR + "arrive.wav") as AudioStream


func _play_local_sfx(stream: AudioStream, vol_db: float, pitch: float = 1.0) -> void:
	if stream == null or _player == null or not _player.is_multiplayer_authority():
		return
	var ap: AudioStreamPlayer = AudioStreamPlayer.new()
	ap.stream = stream
	ap.volume_db = vol_db
	ap.pitch_scale = pitch
	ap.finished.connect(ap.queue_free)
	add_child(ap)
	ap.play()


func trigger_arrive() -> void:
	arrive_left = ARRIVE_DURATION
	standby_active = false
	standby_time = 0.0
	_idle_quiet = 0.0
	_play_local_sfx(_sfx_arrive, -9.0)


func reset() -> void:
	active = false
	_was_active = false
	arrive_left = 0.0
	horizon_amt = 0.0
	boost_cd = 0.0
	standby_active = false
	standby_time = 0.0
	_idle_quiet = 0.0
	_cam_lead = Vector2.ZERO
	if _glide_loop != null and _glide_loop.playing:
		_glide_loop.stop()
	if _star_rim_light != null:
		_star_rim_light.enabled = false


## Called every physics frame on EVERY peer to keep `active` and subtle visual clocks in step.
func sync_presence(in_zero_g: bool, delta: float) -> void:
	active = in_zero_g
	if _star_rim_light != null:
		_star_rim_light.enabled = active
	if active and not _was_active:
		_was_active = true
		arrive_left = ARRIVE_DURATION
		standby_active = false
		standby_time = 0.0
		_idle_quiet = 0.0
		_play_local_sfx(_sfx_arrive, -10.0)
		if _player != null and _player.is_multiplayer_authority() and not _hint_sent:
			_hint_sent = true
			get_tree().call_group("hint_card", "notify_zero_g")
	elif not active and _was_active:
		reset()
		return

	if not active:
		return

	bob_time += delta
	boost_cd = maxf(boost_cd - delta, 0.0)
	if arrive_left > 0.0:
		arrive_left = maxf(arrive_left - delta, 0.0)

	# Continuous phase shared by float_idle / drift / glide so hair & coat never jump
	var spd: float = _player.velocity.length() if _player != null else 0.0
	var rate: float = lerpf(1.0, 1.55, clampf(spd / 150.0, 0.0, 1.0))
	float_time += delta * rate

	# Gentle standby floating gesture after quiet hovering
	if _player != null:
		var quiet: bool = _player.zero_g_state == ZeroGRules.State.IDLE and spd < 10.0 and arrive_left <= 0.0 and not _player.story_lock and not _player.is_busy()
		if quiet:
			if standby_active:
				standby_time += delta
				if standby_time >= 2.0:
					standby_active = false
					standby_time = 0.0
					_idle_quiet = 0.0
					_standby_wait = randf_range(STANDBY_WAIT_MIN, STANDBY_WAIT_MAX)
			else:
				_idle_quiet += delta
				if _idle_quiet >= _standby_wait:
					standby_active = true
					standby_time = 0.0
		else:
			standby_active = false
			standby_time = 0.0
			_idle_quiet = 0.0

		# Stardust trail behind boost-gliding or braking players (visible for all peers in space)
		if _player.zero_g_state == ZeroGRules.State.GLIDE or (spd > 95.0):
			_trail_acc += delta * (20.0 if _player.zero_g_state == ZeroGRules.State.GLIDE else 9.0)
			while _trail_acc >= 1.0:
				_trail_acc -= 1.0
				_spawn_trail_mote(false)
		elif _player.zero_g_state == ZeroGRules.State.BRAKE and spd > 36.0:
			_trail_acc += delta * 12.0
			while _trail_acc >= 1.0:
				_trail_acc -= 1.0
				_spawn_trail_mote(true)

	# Velocity-linked ethereal glide audio (local player only)
	if _glide_loop != null and _player != null and _player.is_multiplayer_authority():
		var spd_k: float = clampf((spd - 14.0) / 145.0, 0.0, 1.0)
		var target_db: float = lerpf(-44.0, -14.0, spd_k) if spd_k > 0.02 else -80.0
		_glide_loop.volume_db = move_toward(_glide_loop.volume_db, target_db, 48.0 * delta)
		_glide_loop.pitch_scale = lerpf(0.88, 1.18, spd_k)
		if target_db > -78.0 and not _glide_loop.playing:
			_glide_loop.play()
		elif target_db <= -79.0 and _glide_loop.playing and _glide_loop.volume_db <= -78.0:
			_glide_loop.stop()


## Runs Fluid Zero-G movement for the owning player; returns the next velocity & synced state.
func step_owner_motion(delta: float, input_dir: Vector2, want_glide: bool, want_brake: bool) -> Dictionary:
	if _player == null:
		return {"velocity": Vector2.ZERO, "state": ZeroGRules.State.NONE}

	# Allow moving right out of the tail of the arrival animation smoothly
	if input_dir.length_squared() > 0.01 and arrive_left < ARRIVE_DURATION * 0.65:
		arrive_left = 0.0

	var center_world: Vector2 = _space_center_world()
	var rel_pos: Vector2 = _player.global_position - center_world
	var boost_ready: bool = want_glide and not _was_glide and boost_cd <= 0.0

	var res: Dictionary = ZeroGRules.step_motion(
		_player.velocity,
		input_dir,
		want_glide,
		want_brake,
		rel_pos,
		delta,
		boost_ready
	)

	var next_vel: Vector2 = res["velocity"] as Vector2
	var next_state: int = int(res["state"])
	horizon_amt = float(res["horizon"])
	var braking_now: bool = bool(res["braking"])

	if bool(res["boost_fired"]):
		boost_cd = float(ZeroGRules.section("motion").get("boost_cooldown", 0.42))
		_play_local_sfx(_sfx_boost, -9.0, randf_range(0.96, 1.05))
		for _i: int in 6:
			_spawn_trail_mote(_player.light_step)

	if braking_now and not _was_brake and _player.velocity.length() > 48.0:
		_play_local_sfx(_sfx_brake, -13.0, randf_range(0.94, 1.06))

	_was_glide = want_glide and input_dir.length_squared() > 0.01 and not want_brake
	_was_brake = braking_now

	if arrive_left > 0.0 and next_vel.length() < 12.0:
		next_state = ZeroGRules.State.ARRIVE

	# Safety tether well past hard_radius so extreme spikes never leave the cosmos band
	var r_hard: float = float(ZeroGRules.section("horizon").get("hard_radius", 1040.0)) + 36.0
	if rel_pos.length() > r_hard:
		_player.global_position = center_world + rel_pos.normalized() * r_hard

	return {
		"velocity": next_vel,
		"state": next_state,
	}


## Elastic Zero-G camera lead with gentle framing pull toward Caelia when hovering near her.
func compute_camera_offset(delta: float, active_cam: bool) -> Vector2:
	if _player == null or not active_cam:
		_cam_lead = _cam_lead.lerp(Vector2.ZERO, 1.0 - exp(-3.5 * delta))
		return _cam_lead

	var ccfg: Dictionary = ZeroGRules.section("camera")
	var lead_px: float = float(ccfg.get("lead_px", 22.0))
	var glide_lead_px: float = float(ccfg.get("glide_lead_px", 40.0))
	var lag_rate: float = float(ccfg.get("lag_rate", 3.0))
	var pull_r: float = float(ccfg.get("caelia_pull_radius", 240.0))
	var pull_w: float = float(ccfg.get("caelia_pull_weight", 0.22))

	var spd: float = _player.velocity.length()
	var max_l: float = glide_lead_px if _player.zero_g_state == ZeroGRules.State.GLIDE else lead_px
	var vel_lead: Vector2 = (_player.velocity / maxf(spd, 1.0)) * minf(spd * 0.26, max_l) if spd > 4.0 else Vector2.ZERO

	# Subtle poetic framing toward Caelia when hovering in her clearing
	var caelia_pull: Vector2 = Vector2.ZERO
	var room: StarHallRoom = _star_hall_room()
	if room != null and is_instance_valid(room.goddess):
		var to_caelia: Vector2 = room.goddess.global_position - _player.global_position
		var dist: float = to_caelia.length()
		if dist < pull_r and dist > 12.0:
			var w: float = smoothstep(pull_r, 42.0, dist) * pull_w
			caelia_pull = to_caelia * w

	var goal: Vector2 = vel_lead + caelia_pull
	_cam_lead = _cam_lead.lerp(goal, 1.0 - exp(-lag_rate * delta))
	return _cam_lead


func bob_offset() -> Vector2:
	if not active or _player == null:
		return Vector2.ZERO
	return ZeroGRules.idle_bob_offset(bob_time, _player.velocity.length())


func _spawn_trail_mote(golden: bool) -> void:
	var room: StarHallRoom = _star_hall_room()
	if room == null or _player == null:
		return
	var back_dir: Vector2 = -_player.velocity.normalized() if _player.velocity.length_squared() > 9.0 else -_player.facing.normalized()
	var jitter: Vector2 = Vector2(randf_range(-7.0, 7.0), randf_range(-10.0, 6.0))
	var spawn_at: Vector2 = _player.global_position + Vector2(0.0, -18.0) + back_dir * randf_range(5.0, 12.0) + jitter
	var drift: Vector2 = back_dir * randf_range(8.0, 22.0) + Vector2(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	room.emit_trail_mote(spawn_at, drift, golden)


func _star_hall_room() -> StarHallRoom:
	var interiors: Interiors = get_tree().get_first_node_in_group("interiors") as Interiors
	if interiors == null:
		return null
	var hall: Interior = interiors.interior(GoddessSystem.STARHALL_ID)
	if hall == null:
		return null
	return hall.get_node_or_null("StarHallRoom") as StarHallRoom


func _space_center_world() -> Vector2:
	var room: StarHallRoom = _star_hall_room()
	if room != null:
		return room.center_global()
	return Vector2(Interiors.COSMOS_X0, Interiors.COSMOS_Y0) + ZeroGRules.room_center() ## Lane.LARGE slot 35 negative-quadrant fallback
