class_name SpiritStag
extends Node2D
## Der Weiße Kronenhirsch — a peaceful, gently shimmering nocturnal spirit beast in meadow clearings (`docs/wiesenbiom_ausbau_konzept.md` Stufe 6).
## Strictly carries ZERO `HurtboxComponent` / `HealthComponent` and cannot be harmed.
## Walking or running upright nearby startles it (`ALERT` -> `FLEE_VANISH` into silver mist).
## Approaching calmly while sneaking (`player.stealth.sneaking`) lets it paw a hidden relic (`antler_talisman`) out of the moss (`PAWING` -> `BLESS_VANISH`).
## Sprite: `spirit_stag.png` + `spirit_stag_glow.png` (`384x128`, `6 cols x 2 rows` of `64x64`, hoof anchor `(32, 56)` -> `offset = (0, -24)`, Row `0` East / Row `1` West).

enum State { IDLE = 0, ALERT = 1, PAWING = 2, BLESS_VANISH = 3, FLEE_VANISH = 4 }

const STAG_TEX: String = "res://assets/wildlife/spirit_stag.png"
const STAG_GLOW: String = "res://assets/wildlife/spirit_stag_glow.png"
const CHIME_WAV: String = "res://assets/audio/meadow_wonders/stag_chime.wav"
const PAW_WAV: String = "res://assets/audio/meadow_wonders/stag_paw.wav"

const ALERT_RADIUS: float = 185.0
const FLEE_RADIUS: float = 135.0
const SNEAK_RADIUS: float = 88.0
const SNEAK_HOLD_SEC: float = 0.95
const PAW_DURATION_SEC: float = 0.95
const VANISH_DURATION_SEC: float = 0.85

var stag_id: int = 0
var wonders: Node
var state: int = State.IDLE
var face_west: bool = false

var _body: Sprite2D
var _glow: Sprite2D
var _light: NightLight
var _fx: Node2D
var _motes: Array[Dictionary] = []

var _time: float = 0.0
var _state_time: float = 0.0
var _sneak_hold: float = 0.0
var _blessed_peer: int = 0
var _blessing_done: bool = false


func setup(owner_wonders: Node, sid: int, pos_px: Vector2) -> void:
	wonders = owner_wonders
	stag_id = sid
	position = pos_px.round()


func _ready() -> void:
	add_to_group("flora_glow")
	_build_visuals()
	_init_motes()
	_update_frame()


func _build_visuals() -> void:
	var off: Vector2 = Vector2(0.0, -24.0) ## hooves/ground anchor (32, 56) in 64x64 -> -(56 - 32)
	if ResourceLoader.exists(STAG_TEX):
		_body = Sprite2D.new()
		_body.texture = load(STAG_TEX) as Texture2D
		_body.hframes = 6
		_body.vframes = 2
		_body.offset = off
		_body.flip_h = false ## row 1 is true hand-lit West-facing art, never mirror!
		add_child(_body)
	if ResourceLoader.exists(STAG_GLOW):
		_glow = Sprite2D.new()
		_glow.texture = load(STAG_GLOW) as Texture2D
		_glow.hframes = 6
		_glow.vframes = 2
		_glow.offset = off
		_glow.flip_h = false
		_glow.material = Unlit.material()
		add_child(_glow)

	_light = NightLight.new()
	_light.position = Vector2(0.0, -20.0)
	_light.radius = 68
	_light.base_energy = 0.48
	_light.pulse = 0.14
	_light.glow_color = Color("8ef8f0")
	add_child(_light)

	_fx = Node2D.new()
	_fx.z_index = 2
	_fx.material = Unlit.material()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


func _init_motes() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = stag_id * 6311 + 193
	for i: int in 16:
		_motes.append({
			"ang": rng.randf() * TAU,
			"rad": rng.randf_range(10.0, 26.0),
			"y_off": rng.randf_range(-34.0, -6.0),
			"speed": rng.randf_range(0.45, 0.95),
			"phase": rng.randf() * TAU,
		})


func apply_state(new_state: int, west: bool, peer_id: int) -> void:
	var entered: bool = new_state != state
	state = new_state
	face_west = west
	if peer_id != 0:
		_blessed_peer = peer_id
	if entered:
		_state_time = 0.0
		if state == State.PAWING:
			_play_sfx(PAW_WAV, -3.0)
		elif state == State.BLESS_VANISH or state == State.FLEE_VANISH:
			_play_sfx(CHIME_WAV, -2.5)
	_update_frame()


func _play_sfx(wav_path: String, vol_db: float) -> void:
	if not ResourceLoader.exists(wav_path):
		return
	var snd: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	snd.stream = load(wav_path) as AudioStream
	snd.bus = "SFX"
	snd.volume_db = vol_db
	snd.max_distance = 520.0
	snd.finished.connect(snd.queue_free)
	add_child(snd)
	snd.play()


func _process(delta: float) -> void:
	_time += delta
	_state_time += delta

	if multiplayer.is_server():
		_host_tick(delta)

	if state == State.FLEE_VANISH or state == State.BLESS_VANISH:
		var k: float = clampf(_state_time / VANISH_DURATION_SEC, 0.0, 1.0)
		modulate.a = 1.0 - k
		if state == State.FLEE_VANISH:
			position += Vector2(-26.0 if face_west else 26.0, -10.0) * delta
		else:
			position += Vector2(0.0, -8.0) * delta
		if _light != null:
			_light.base_energy = 0.48 * (1.0 - k)
			_light.energy = _light.base_energy * TimeManager.night_amount()
		if _state_time >= VANISH_DURATION_SEC:
			queue_free()
			return

	if delta > 0.0:
		var vp: Viewport = get_viewport()
		var cam: Camera2D = vp.get_camera_2d() if vp != null else null
		if cam != null and global_position.distance_squared_to(cam.get_screen_center_position()) > 560.0 * 560.0:
			return
	_update_frame()
	if _glow != null:
		var night: float = TimeManager.night_amount()
		var pulse: float = 0.82 + 0.18 * sin(_time * 2.5)
		_glow.modulate.a = clampf(lerpf(0.32, 0.96, night) * pulse, 0.0, 1.0)
	if _fx != null:
		_fx.queue_redraw()


func _host_tick(delta: float) -> void:
	if wonders == null or state == State.BLESS_VANISH or state == State.FLEE_VANISH:
		return

	if state == State.PAWING:
		if not _blessing_done and _state_time >= PAW_DURATION_SEC:
			_blessing_done = true
			wonders.host_complete_stag_blessing(stag_id, _blessed_peer)
		return

	if not TimeManager.is_night():
		wonders.host_set_stag_state(stag_id, State.FLEE_VANISH, face_west, 0)
		return

	var nearest_dist: float = INF
	var nearest_p: Player = null
	var noisy_flee: bool = false
	var noisy_alert: bool = false
	var quiet_close: Player = null
	var quiet_dist: float = INF

	for p: Player in Player.all:
		if not is_instance_valid(p) or p.health == null or p.health.current <= 0.0:
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest_p = p
		var noisy: bool = not p.stealth.sneaking or p.sprinting or p.attack.is_swinging() or p.attack.is_charging()
		if noisy:
			if d <= FLEE_RADIUS:
				noisy_flee = true
			elif d <= ALERT_RADIUS:
				noisy_alert = true
		elif d <= SNEAK_RADIUS and d < quiet_dist:
			quiet_dist = d
			quiet_close = p

	if nearest_p != null:
		face_west = nearest_p.global_position.x < global_position.x

	if noisy_flee:
		_sneak_hold = 0.0
		wonders.host_set_stag_state(stag_id, State.FLEE_VANISH, face_west, 0)
		return

	if noisy_alert:
		_sneak_hold = 0.0
		if state != State.ALERT:
			wonders.host_set_stag_state(stag_id, State.ALERT, face_west, 0)
		return

	if quiet_close != null:
		_sneak_hold += delta
		if _sneak_hold >= SNEAK_HOLD_SEC:
			wonders.host_set_stag_state(stag_id, State.PAWING, face_west, quiet_close.name.to_int())
		return

	_sneak_hold = move_toward(_sneak_hold, 0.0, delta * 0.6)
	if state == State.ALERT and nearest_dist > ALERT_RADIUS + 10.0:
		wonders.host_set_stag_state(stag_id, State.IDLE, face_west, 0)


func _update_frame() -> void:
	var col: int = 0
	match state:
		State.IDLE:
			col = int(_time * 1.4) % 2
		State.ALERT:
			col = 2
		State.PAWING:
			col = 3 + (int(_state_time * 7.0) % 2)
		State.BLESS_VANISH, State.FLEE_VANISH:
			col = 5
	var row: int = 1 if face_west else 0
	var coords: Vector2i = Vector2i(col, row)
	if _body != null:
		_body.frame_coords = coords
	if _glow != null:
		_glow.frame_coords = coords


func _draw_fx() -> void:
	for m: Dictionary in _motes:
		var a: float = float(m.ang) + _time * float(m.speed)
		var r: float = float(m.rad)
		var bob: float = sin(_time * 2.2 + float(m.phase)) * 2.5
		var pt: Vector2 = Vector2(cos(a) * r, float(m.y_off) + bob).round()
		var alpha: float = (0.35 + 0.45 * sin(_time * 3.1 + float(m.phase))) * modulate.a
		_fx.draw_rect(Rect2(pt, Vector2(1.0, 1.0)), Color(0.62, 0.98, 0.94, maxf(0.0, alpha)))

	if state == State.BLESS_VANISH or state == State.FLEE_VANISH:
		var frac: float = clampf(_state_time / VANISH_DURATION_SEC, 0.0, 1.0)
		var ring_r: float = lerpf(10.0, 38.0, frac)
		var ring_a: float = (1.0 - frac) * 0.72
		var pts: PackedVector2Array = PackedVector2Array()
		for s: int in 25:
			var ang: float = float(s) / 24.0 * TAU
			pts.append(Vector2(cos(ang) * ring_r, sin(ang) * ring_r * 0.55 - 12.0))
		_fx.draw_polyline(pts, Color(0.70, 1.0, 0.95, ring_a), 1.4)
