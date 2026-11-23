class_name WaterAmbience
extends Node2D
## Ambient water audio controller for Water System v2 (T12 / R4).
## Plays seamless AudioStreamWAV loops (runtime LOOP_FORWARD + loop_end) on the
## `"Ambience"` bus: positional AudioStreamPlayer2D for Square -1's brook (plus a
## phase-offset ambient brook bed), swash-modulated coastal surf (`WaterRules.swash_phase`),
## and storm/wind-coupled open ocean swell. Safe in `--headless` and standalone.

const BUS_AMBIENCE: StringName = &"Ambience"
const BROOK_WAV_PATH: String = "res://assets/audio/water/brook_loop.wav"
const SURF_WAV_PATH: String = "res://assets/audio/water/surf_wash_loop.wav"
const OCEAN_WAV_PATH: String = "res://assets/audio/water/ocean_swell_loop.wav"

const BROOK_DEFAULT_POS: Vector2 = Vector2(-384.0, 0.0)
const COAST_SHORE_DEFAULT_X: float = -748.0
const OCEAN_SHELF_DEFAULT_X: float = -960.0

var brook_pos: Vector2 = BROOK_DEFAULT_POS
var coast_shore_x: float = COAST_SHORE_DEFAULT_X
var ocean_shelf_x: float = OCEAN_SHELF_DEFAULT_X

var _bus: StringName = &"Master"
var _brook_2d: AudioStreamPlayer2D = null
var _brook_bed: AudioStreamPlayer = null
var _surf_player: AudioStreamPlayer = null
var _ocean_player: AudioStreamPlayer = null
var _bound_field: Node = null
var _fallback_time: float = 0.0
var _ready_done: bool = false


func _ready() -> void:
	name = "WaterAmbience"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_bus = _ensure_ambience_bus()

	var brook_wav_2d: AudioStreamWAV = _load_loop_wav(BROOK_WAV_PATH)
	if brook_wav_2d != null:
		_brook_2d = AudioStreamPlayer2D.new()
		_brook_2d.name = "BrookPlayer2D"
		_brook_2d.stream = brook_wav_2d
		_brook_2d.bus = _bus
		_brook_2d.max_distance = 280.0
		_brook_2d.attenuation = 1.4
		_brook_2d.volume_db = -80.0
		_brook_2d.position = to_local(brook_pos) if is_inside_tree() else brook_pos
		add_child(_brook_2d)

	var brook_wav_bed: AudioStreamWAV = _load_loop_wav(BROOK_WAV_PATH)
	if brook_wav_bed != null:
		_brook_bed = AudioStreamPlayer.new()
		_brook_bed.name = "BrookBedPlayer"
		_brook_bed.stream = brook_wav_bed
		_brook_bed.bus = _bus
		_brook_bed.volume_db = -80.0
		add_child(_brook_bed)

	var surf_wav: AudioStreamWAV = _load_loop_wav(SURF_WAV_PATH)
	if surf_wav != null:
		_surf_player = AudioStreamPlayer.new()
		_surf_player.name = "SurfWashPlayer"
		_surf_player.stream = surf_wav
		_surf_player.bus = _bus
		_surf_player.volume_db = -80.0
		add_child(_surf_player)

	var ocean_wav: AudioStreamWAV = _load_loop_wav(OCEAN_WAV_PATH)
	if ocean_wav != null:
		_ocean_player = AudioStreamPlayer.new()
		_ocean_player.name = "OceanSwellPlayer"
		_ocean_player.stream = ocean_wav
		_ocean_player.bus = _bus
		_ocean_player.volume_db = -80.0
		add_child(_ocean_player)

	_ready_done = true
	_update_mix(0.016)


func bind_water_field(water_field: Node) -> void:
	_bound_field = water_field


func _ensure_ambience_bus() -> StringName:
	var idx: int = AudioServer.get_bus_index(BUS_AMBIENCE)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		if idx >= 0:
			AudioServer.set_bus_name(idx, BUS_AMBIENCE)
			AudioServer.set_bus_send(idx, &"Master")
	return BUS_AMBIENCE if AudioServer.get_bus_index(BUS_AMBIENCE) >= 0 else &"Master"


func _load_loop_wav(path: String) -> AudioStreamWAV:
	if not ResourceLoader.exists(path):
		return null
	var src: AudioStreamWAV = load(path) as AudioStreamWAV
	if src == null:
		return null
	var stream: AudioStreamWAV = src.duplicate() as AudioStreamWAV
	if stream == null:
		return null
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	var bytes_per_sample: int = 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var channels: int = 2 if stream.stereo else 1
	var frame_bytes: int = maxi(1, bytes_per_sample * channels)
	stream.loop_end = maxi(1, stream.data.size() / frame_bytes)
	return stream


func _find_water_field() -> Node:
	if _bound_field != null and is_instance_valid(_bound_field):
		return _bound_field
	for patch: Node in Terrain.patches:
		if is_instance_valid(patch) and patch.has_method(&"water_field_at"):
			_bound_field = patch
			return patch
	return null


func _listener_position() -> Vector2:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_inside_tree() and p.is_multiplayer_authority():
			return p.global_position
	if is_inside_tree():
		var vp: Viewport = get_viewport()
		if vp != null:
			var cam: Camera2D = vp.get_camera_2d()
			if cam != null:
				return cam.get_screen_center_position()
		return global_position
	return position


func _water_time(wf: Node, dt: float) -> float:
	if wf != null and is_instance_valid(wf):
		var ft: Variant = wf.get(&"_frame_water_time")
		if ft is float or ft is int:
			return float(ft)
	_fallback_time += dt
	return _fallback_time


func _process(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.05)
	if not _ready_done:
		_fallback_time += dt
		return
	_update_mix(dt)


func _update_mix(dt: float) -> void:
	var wf: Node = _find_water_field()
	var listener: Vector2 = _listener_position()
	var wtime: float = _water_time(wf, dt)

	var ww: WorldWind = WorldWind.current
	var wind_dir: Vector2 = ww.direction if ww != null and is_instance_valid(ww) else Vector2.RIGHT
	var wind_gust: float = ww.gust if ww != null and is_instance_valid(ww) else 0.15
	var wm: WeatherManager = WeatherManager.current
	var storm: float = wm.storm if wm != null and is_instance_valid(wm) else 0.0

	var y_dist: float = maxf(absf(listener.y) - 144.0, 0.0)
	var y_fade: float = 1.0 - smoothstep(0.0, 220.0, y_dist)
	if wf != null and is_instance_valid(wf):
		var b_v: Variant = wf.get(&"bounds")
		if b_v is Rect2:
			var b: Rect2 = b_v as Rect2
			var dx_b: float = maxf(maxf(b.position.x - listener.x, listener.x - b.end.x), 0.0)
			var dy_b: float = maxf(maxf(b.position.y - listener.y, listener.y - b.end.y), 0.0)
			var dist_bounds: float = sqrt(dx_b * dx_b + dy_b * dy_b)
			y_fade *= (1.0 - smoothstep(40.0, 320.0, dist_bounds))

	# 1. Square -1 Forest Brook (positional 2D + phase-offset ambient bed)
	var brook_nearest: Vector2 = Vector2(brook_pos.x, clampf(listener.y, -110.0, 110.0))
	var brook_dist: float = listener.distance_to(brook_nearest)
	var brook_prox: float = (1.0 - smoothstep(24.0, 260.0, brook_dist)) * y_fade
	var brook_rip: float = 0.88 + 0.12 * sin(wtime * 0.75)
	var brook_lin: float = clampf(brook_prox * brook_rip * 0.42, 0.0, 1.0)
	if _brook_2d != null and is_instance_valid(_brook_2d):
		if is_inside_tree():
			_brook_2d.global_position = brook_nearest
		var b2d_db: float = clampf(-12.0 + linear_to_db(maxf(brook_prox * 0.65, 0.0001)), -80.0, 0.0) if brook_prox > 0.01 else -80.0
		_sync_player_2d(_brook_2d, b2d_db, dt)
	if _brook_bed != null and is_instance_valid(_brook_bed):
		var bbed_db: float = clampf(-9.0 + linear_to_db(maxf(brook_lin, 0.0001)), -80.0, 0.0) if brook_prox > 0.01 else -80.0
		_sync_player_1d(_brook_bed, bbed_db, dt, 6.0)

	# 2. Square -2 Coastal Surf Wash (live WaterRules.swash_phase modulation)
	var coast_dist: float = absf(listener.x - coast_shore_x)
	var coast_prox: float = (1.0 - smoothstep(28.0, 260.0, coast_dist)) * y_fade
	var p01: float = WaterRules.swash_phase(listener.y, wtime, wind_dir, wind_gust, storm)
	var swash_env: float = 0.22
	if p01 < WaterRules.SWASH_SURGE_END:
		var surge_t: float = p01 / WaterRules.SWASH_SURGE_END
		swash_env = 0.22 + 0.78 * sin(surge_t * PI * 0.5)
	else:
		var back_t: float = (p01 - WaterRules.SWASH_SURGE_END) / (1.0 - WaterRules.SWASH_SURGE_END)
		swash_env = 0.22 + 0.78 * pow(clampf(1.0 - back_t, 0.0, 1.0), 1.35)
	var surf_weather: float = 1.0 + clampf(storm, 0.0, 1.0) * 0.35 + clampf(wind_gust, 0.0, 2.0) * 0.08
	var surf_lin: float = clampf(coast_prox * swash_env * surf_weather * 0.72, 0.0, 1.0)
	if _surf_player != null and is_instance_valid(_surf_player):
		var surf_db: float = clampf(-10.0 + linear_to_db(maxf(surf_lin, 0.0001)), -80.0, 0.0) if coast_prox > 0.01 else -80.0
		_sync_player_1d(_surf_player, surf_db, dt, 0.0)

	# 3. Square -3 Open Ocean Swell (distance + storm/wind modulation)
	var ocean_dist: float = maxf(listener.x - ocean_shelf_x, 0.0)
	var ocean_prox: float = (1.0 - smoothstep(0.0, 280.0, ocean_dist)) * y_fade
	var swell_h: float = WaterRules.swell_height(listener, wtime, wind_dir, wind_gust, storm)
	var swell_mod: float = 0.70 + 0.30 * clampf(absf(swell_h), 0.0, 1.2)
	var ocean_weather: float = 0.80 + 0.45 * clampf(storm, 0.0, 1.0) + 0.12 * clampf(wind_gust, 0.0, 2.0)
	var ocean_lin: float = clampf(ocean_prox * swell_mod * ocean_weather * 0.70, 0.0, 1.0)
	if _ocean_player != null and is_instance_valid(_ocean_player):
		var ocean_db: float = clampf(-11.0 + linear_to_db(maxf(ocean_lin, 0.0001)), -80.0, 0.0) if ocean_prox > 0.01 else -80.0
		_sync_player_1d(_ocean_player, ocean_db, dt, 0.0)


func _sync_player_1d(player: AudioStreamPlayer, target_db: float, dt: float, start_pos: float) -> void:
	var clamped_target: float = clampf(target_db, -80.0, 0.0)
	if clamped_target > -79.0 and not player.playing:
		player.volume_db = clamped_target
		player.play(start_pos)
		return
	player.volume_db = clampf(move_toward(player.volume_db, clamped_target, 60.0 * dt), -80.0, 0.0)
	if player.playing and player.volume_db <= -79.0:
		player.stop()


func _sync_player_2d(player: AudioStreamPlayer2D, target_db: float, dt: float) -> void:
	var clamped_target: float = clampf(target_db, -80.0, 0.0)
	if clamped_target > -79.0 and not player.playing:
		player.volume_db = clamped_target
		player.play()
		return
	player.volume_db = clampf(move_toward(player.volume_db, clamped_target, 60.0 * dt), -80.0, 0.0)
	if player.playing and player.volume_db <= -79.0:
		player.stop()
