class_name WispTrail
extends WorldTrial
## The wisp trail (Irrlichtspur, docs/raetsel_konzept.md section 1): a wisp sleeps in the moss of an old stone bowl. Come close and it wakes, rises and
## darts off along a fixed route of the data (`data/puzzles.json` `placed`), hovering at its stops until somebody follows close enough, then darting on
## (a little faster than her walk, slower than her sprint). Falling behind makes it halt and call; coming too close, sprinting or swinging near it
## frightens it: it flashes violet and darts on to the next stop (shy +1). Too shy, or left alone too long, and it goes out and is back in its bowl a few
## seconds later. Sneaking calms it (she may come closer; it slows to just above her sneaking pace). At the end it climbs, circles, plunges into the ground, a ring of light
## flowers blooms and a Wurzelkiste comes down in a pillar of light (`Puzzles.solve` -> `LootChests.appear`).
## Host-authoritative: the host runs the state machine and sends the arc position along the route (`_rpc_motion`, unreliable) and every change of state
## (`_rpc_state`, reliable); every peer draws everything itself from those (the route is the same smooth curve everywhere). `followers` can be replaced
## (tests): a Callable returning [{pos, sneak, loud}].

enum State { SLEEP, WAKE, HOP, HOVER, LINGER, DART, LOST, GONE, DIVE, SOLVED }

const ART: String = "res://assets/props/puzzles/wisp_bowl"
const SOUND_DIR: String = "res://assets/audio/wisp/"
const TEAL: Color = Color("78f4e6")
const TEAL_DEEP: Color = Color("2fb8b0")
const WHITE: Color = Color("eafffb")
const GOLD: Color = Color("ffb347")
const GOLD_LIGHT: Color = Color("fff2cc")
const VIOLET: Color = Color("9468ee")
const INK: Color = Color("1b1a2e")
const BAYER: Array = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
const DIVE_IMPACT: float = 1.55 ## seconds into the dive when it hits the ground
const DIVE_LEN: float = 2.4
const MAX_SPARKS: int = 320
const TAIL_LIFE: float = 0.8 ## seconds a point of the comet tail lasts
const FEET: Vector2 = Vector2(22, 46) ## the bowl's feet in its frame (tools/art_wisp.py)

var cfg: Dictionary = {}
var followers: Callable = Callable()

var state: int = State.SLEEP
var s: float = 0.0 ## arc length along the route (px)
var shy: int = 0
var calling: bool = false
var target: int = 0 ## index into `_stop_s` the wisp flies to / hovers at

var _curve: Curve2D = Curve2D.new()
var _stop_s: PackedFloat32Array = PackedFloat32Array()
var _linger: Dictionary = {} ## index into _stop_s -> true
var _bowl_pos: Vector2 = Vector2.ZERO
var _end_pos: Vector2 = Vector2.ZERO
var _nest_h: float = 23.5
var _speed: float = 0.0
var _timer: float = 0.0
var _far_time: float = 0.0
var _scare_cool: float = 0.0
var _sync_t: float = 0.0
var _greeted: bool = false

# what every peer draws
var _shown_s: float = 0.0
var _state_t: float = 0.0 ## seconds in the current state (local clock)
var _time: float = 0.0
var _fright: float = 0.0
var _gold: float = 0.0
var _vel: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _height: float = 23.5
var _look: Vector2 = Vector2.ZERO
var _tail: Array = [] ## [world point with height, age]
var _sparks: Array = [] ## [world pos, age, life, colour, rise]
var _spark_t: float = 0.0
var _call_t: float = 0.0
var _blooms: Array = [] ## [offset, delay, size, hue]
var _bloom_t: float = -1.0
var _fade: float = 1.0 ## the wisp's own visibility (goes out, comes back)

var _bowl: Node2D
var _bowl_sprite: Sprite2D
var _bowl_glow: Sprite2D
var _home_light: NightLight
var _end_light: NightLight
var _wisp: Node2D
var _wisp_light: NightLight
var _ground: Node2D
var _audio: AudioStreamPlayer2D
var _night: float = 0.0


func setup(entry: Dictionary, tuning: Dictionary) -> void:
	super.setup(entry, tuning)
	cfg = tuning
	var pts: Array[Vector2] = []
	for t: Variant in entry.get("route", []) as Array:
		var a: Array = t as Array
		pts.append(Vector2(float(a[0]), float(a[1])) * 16.0 + Vector2(8, 8))
	if pts.size() < 2:
		pts = [Vector2.ZERO, Vector2(64, 0)]
	_bowl_pos = pts[0]
	_end_pos = pts[pts.size() - 1]
	_curve.bake_interval = 3.0
	for i: int in pts.size(): ## Catmull-Rom handles: a smooth line through every point, no corners
		var prev: Vector2 = pts[maxi(i - 1, 0)]
		var next: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var tan: Vector2 = (next - prev) / 6.0
		_curve.add_point(pts[i], -tan if i > 0 else Vector2.ZERO, tan if i < pts.size() - 1 else Vector2.ZERO)
	var stops: Array = entry.get("stops", [pts.size() - 1]) as Array
	for k: Variant in stops:
		_stop_s.append(_curve.get_closest_offset(pts[clampi(int(k), 0, pts.size() - 1)]))
	_stop_s[_stop_s.size() - 1] = _curve.get_baked_length()
	var lingers: Array = entry.get("linger", []) as Array
	for i: int in stops.size():
		if lingers.has(stops[i]):
			_linger[i] = true
	var art: Dictionary = DataRegistry.table("puzzle_art").get("wisp_bowl", {}) as Dictionary
	var nest: Array = art.get("nest", [-1.0, -23.5]) as Array
	_nest_h = -float(nest[1])
	_height = _nest_h
	_build_blooms()


func bowl_position() -> Vector2:
	return _bowl_pos


func end_position() -> Vector2:
	return _end_pos


func start_position() -> Vector2:
	return _bowl_pos + Vector2(0, 72)


func route_length() -> float:
	return _curve.get_baked_length()


func stop_count() -> int:
	return _stop_s.size()


func ground_position() -> Vector2:
	if state == State.SLEEP or state == State.WAKE or state == State.GONE:
		return _bowl_pos + Vector2(-1, 1)
	if state == State.DIVE or state == State.SOLVED:
		return _end_pos
	return _curve.sample_baked(_shown_s)


func _ready() -> void:
	y_sort_enabled = true
	_bowl = Node2D.new()
	_bowl.name = "Bowl"
	_bowl.position = _bowl_pos
	add_child(_bowl)
	_bowl_sprite = Sprite2D.new()
	_bowl_sprite.texture = load(ART + ".png") as Texture2D
	_bowl_sprite.hframes = 2
	_bowl_sprite.centered = false
	_bowl_sprite.offset = -FEET
	_bowl.add_child(_bowl_sprite)
	if ResourceLoader.exists(ART + "_glow.png"):
		_bowl_glow = Sprite2D.new()
		_bowl_glow.texture = load(ART + "_glow.png") as Texture2D
		_bowl_glow.hframes = 2
		_bowl_glow.centered = false
		_bowl_glow.offset = -FEET
		_bowl_glow.material = Unlit.material()
		_bowl_sprite.add_child(_bowl_glow)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(16, 7)
	shape.shape = rect
	shape.position = Vector2(0, -2)
	body.add_child(shape)
	_bowl.add_child(body)
	_home_light = _light(TEAL, 22, 0.55)
	_home_light.position = Vector2(0, -6)
	_bowl.add_child(_home_light)

	_ground = Node2D.new()
	_ground.name = "WispGround"
	_ground.z_index = -5
	_ground.material = Unlit.material()
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_wisp = Node2D.new()
	_wisp.name = "Wisp"
	_wisp.z_index = 0 ## sorted like everything else by its ground point: it hides behind trunks, crowns and bushes it flies behind
	_wisp.material = Unlit.material()
	_wisp.draw.connect(_draw_wisp)
	add_child(_wisp)
	_wisp_light = _light(TEAL, 42, 0.9)
	_wisp.add_child(_wisp_light)
	_end_light = _light(GOLD_LIGHT, 34, 0.0)
	_end_light.position = _end_pos
	add_child(_end_light)
	_audio = AudioStreamPlayer2D.new()
	_audio.max_distance = 420.0
	_audio.attenuation = 1.6
	_wisp.add_child(_audio)
	add_to_group("night_lights")
	_last_pos = ground_position()
	_wisp.position = _last_pos.round()
	_apply_look()
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(func(peer: int) -> void: _rpc_state.rpc_id(peer, state, s, shy, target, -1.0))


func _light(color: Color, radius: int, energy: float) -> NightLight:
	var l: NightLight = NightLight.new()
	l.radius = radius
	l.squash = 0.55
	l.glow_color = color
	l.base_energy = energy
	l.pulse = 0.2
	return l


func set_night(amount: float) -> void:
	_night = amount


# ------------------------------------------------------------------ host

func _process(delta: float) -> void:
	_time += delta
	_state_t += delta
	if multiplayer.is_server():
		_host_step(delta)
		_sync_t -= delta
		if _sync_t <= 0.0 and _moving():
			_sync_t = 0.08
			if not multiplayer.get_peers().is_empty():
				_rpc_motion.rpc(s, calling)
		_shown_s = s
	else:
		_shown_s = lerpf(_shown_s, s, 1.0 - exp(-12.0 * delta))
	_animate(delta)


func _moving() -> bool:
	return state == State.HOP or state == State.DART or state == State.HOVER or state == State.LINGER


func _host_step(delta: float) -> void:
	_scare_cool = maxf(0.0, _scare_cool - delta)
	var f: Dictionary = _nearest(ground_position())
	var d: float = float(f.get("d", INF))
	match state:
		State.SLEEP:
			if d < float(cfg.get("wake_range", 58.0)):
				_set_state(State.WAKE)
				_timer = 1.5
		State.WAKE:
			_timer -= delta
			if _timer <= 0.0:
				target = 0
				_speed = 0.0
				_set_state(State.HOP)
		State.HOP, State.DART:
			if _host_alarms(f, d, delta):
				return
			_host_fly(f, d, delta)
		State.HOVER:
			if _host_alarms(f, d, delta):
				return
			calling = d > float(cfg.get("wait_range", 150.0))
			if d < float(cfg.get("beckon", 92.0)):
				_timer -= delta
				if _timer <= 0.0:
					if target >= _stop_s.size() - 1:
						_set_state(State.DIVE)
					else:
						target += 1
						_set_state(State.HOP)
			else:
				_timer = 0.35
		State.LINGER:
			if _host_alarms(f, d, delta):
				return
			_timer -= delta
			if _timer <= 0.0:
				_timer = 0.35
				_set_state(State.HOVER)
		State.LOST:
			_timer -= delta
			if _timer <= 0.0:
				_timer = float(cfg.get("respawn", 7.0))
				_set_state(State.GONE)
		State.GONE:
			_timer -= delta
			if _timer <= 0.0:
				s = 0.0
				shy = 0
				target = 0
				_set_state(State.SLEEP)
		State.DIVE:
			if _state_t >= DIVE_LEN:
				_set_state(State.SOLVED)
				solved.emit(id, _end_pos)


## Fright and loneliness. True when the state changed.
func _host_alarms(f: Dictionary, d: float, delta: float) -> bool:
	if d > float(cfg.get("lost_range", 340.0)):
		_far_time += delta
		if _far_time > float(cfg.get("lost_time", 12.0)):
			_go_out()
			return true
	else:
		_far_time = 0.0
	if f.is_empty() or _scare_cool > 0.0:
		return false
	var near: float = float(cfg.get("scare_range_sneak", 18.0)) if bool(f.get("sneak", false)) else float(cfg.get("scare_range", 30.0))
	if d < near or (bool(f.get("loud", false)) and d < float(cfg.get("loud_range", 70.0))):
		_scare_cool = 1.6
		shy += 1
		if shy >= int(cfg.get("shy_limit", 3)):
			_go_out()
			return true
		var last_open: int = maxi(_stop_s.size() - 2, 0) ## never frightened onto the last stop: she must still follow it there
		var passed: int = target if s >= _stop_s[target] - 1.0 else target - 1 ## the last stop it already reached
		target = maxi(target, mini(passed + 1 + int(cfg.get("dart_skip", 1)), last_open))
		_speed = maxf(_speed, 30.0)
		calling = false
		_set_state(State.DART)
		return true
	return false


func _go_out() -> void:
	calling = false
	_timer = 1.1
	_set_state(State.LOST)


func _host_fly(f: Dictionary, d: float, delta: float) -> void:
	var goal: float = _stop_s[target]
	var remaining: float = goal - s
	var cruise: float = float(cfg.get("cruise", 68.0)) ## a little faster than her walk (62 px/s), well below her sprint (124)
	var accel: float = float(cfg.get("accel", 90.0))
	if bool(f.get("sneak", false)):
		cruise *= float(cfg.get("sneak_factor", 0.68)) ## she sneaks at 42 px/s: it slows to just above that
	var dart: bool = state == State.DART
	if dart:
		cruise *= float(cfg.get("dart", 1.4))
		accel *= 2.0
		calling = false
	else:
		calling = d > float(cfg.get("wait_range", 150.0))
		var beckon: float = float(cfg.get("beckon", 92.0))
		cruise *= 1.0 + float(cfg.get("press_boost", 0.1)) * clampf((beckon - d) / beckon, 0.0, 1.0) ## she presses on: it keeps its lead
	var want: float = 0.0 if calling else minf(cruise, sqrt(2.0 * accel * maxf(remaining, 0.0)) + 6.0)
	_speed = move_toward(_speed, want, accel * delta)
	s = minf(s + _speed * delta, goal)
	if s >= goal - 0.5:
		s = goal
		_speed = 0.0
		calling = false
		if _linger.has(target) and state == State.HOP:
			_linger.erase(target) ## once per run is enough (restored by `_reset_lingers` when it goes out)
			_timer = float(cfg.get("linger_time", 2.6))
			_set_state(State.LINGER)
		else:
			_timer = 0.35
			_set_state(State.HOVER)


func _nearest(at: Vector2) -> Dictionary:
	var list: Array = followers.call() if followers.is_valid() else _living_players()
	var best: Dictionary = {}
	var best_d: float = INF
	for e: Variant in list:
		var entry: Dictionary = e as Dictionary
		var dd: float = (entry.get("pos", Vector2.ZERO) as Vector2).distance_to(at)
		if dd < best_d:
			best_d = dd
			best = entry
	if not best.is_empty():
		best["d"] = best_d
	return best


func _living_players() -> Array:
	var out: Array = []
	for p: Player in Player.all:
		if not is_instance_valid(p) or p.health == null or p.health.current <= 0.0:
			continue
		var loud: bool = (p.sprinting and p.velocity.length() > p.max_speed * 1.1) or (p.attack != null and p.attack.is_swinging())
		out.append({"pos": p.global_position, "sneak": p.stealth != null and p.stealth.sneaking, "loud": loud})
	return out


func _set_state(next: int) -> void:
	if next == State.LOST or next == State.SLEEP:
		_reset_lingers()
	if multiplayer.get_peers().is_empty():
		_rpc_state(next, s, shy, target, calling)
	else:
		_rpc_state.rpc(next, s, shy, target, calling)


func _reset_lingers() -> void:
	_linger.clear()
	var stops: Array = info.get("stops", []) as Array
	var lingers: Array = info.get("linger", []) as Array
	for i: int in stops.size():
		if lingers.has(stops[i]):
			_linger[i] = true


## Puzzles: the trial was solved before (save file, snapshot): the bowl is cold, the flowers stand, no wisp.
func set_solved_instant() -> void:
	state = State.SOLVED
	s = _curve.get_baked_length()
	_shown_s = s
	_bloom_t = 99.0
	_apply_look()


## Dev: back to the start (the bowl lit, the wisp asleep, the flowers gone).
func reset_trial() -> void:
	state = State.SLEEP
	s = 0.0
	_shown_s = 0.0
	shy = 0
	target = 0
	calling = false
	_bloom_t = -1.0
	_sparks.clear()
	_tail.clear()
	_reset_lingers()
	_state_t = 0.0
	_fade = 1.0
	_apply_look()


# ------------------------------------------------------------------ network

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_motion(arc: float, is_calling: bool) -> void:
	s = arc
	calling = is_calling


@rpc("authority", "call_local", "reliable")
func _rpc_state(next: int, arc: float, shyness: int, aim: int, is_calling: Variant) -> void:
	var old: int = state
	state = next
	s = arc
	shy = shyness
	target = aim
	if is_calling is bool:
		calling = bool(is_calling)
	if old == next and next != State.DART:
		return
	_state_t = 0.0
	_enter_fx(old, next)
	_apply_look()


func _enter_fx(old: int, next: int) -> void:
	match next:
		State.WAKE:
			_sound("wake", 0.0)
			_burst(ground_position(), 14, TEAL, 0.9)
			_greet()
		State.HOP:
			if old != State.HOP:
				_sound("hop", -6.0)
		State.DART:
			_sound("scare", -2.0)
			_fright = 1.0
			_burst(_last_pos, 16, VIOLET, 1.1)
		State.LOST:
			_sound("fizzle", 0.0)
			_fright = 1.0
		State.SLEEP:
			_fade = 0.0
			_shown_s = 0.0
			_tail.clear()
			if old == State.GONE:
				_burst(_bowl_pos + Vector2(0, -20), 10, TEAL, 0.7)
		State.DIVE:
			_sound("dive", 0.0)
		State.SOLVED:
			if _bloom_t < 0.0:
				_bloom_t = 99.0


func _greet() -> void:
	if _greeted:
		return
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority() and p.global_position.distance_to(_bowl_pos) < 140.0:
			_greeted = true
			var box: Node = get_tree().get_first_node_in_group("speech_box")
			if box != null and box.has_method("speak"):
				box.call("speak", "ELLIE", "EIN IRRLICHT ... ES WILL MIR ETWAS ZEIGEN. LEISE JETZT.") ## placeholder line for the dialogue writer
			return


func _apply_look() -> void:
	var home: bool = state == State.SLEEP or state == State.WAKE
	if _bowl_sprite != null:
		_bowl_sprite.frame = 0 if home else 1
		if _bowl_glow != null:
			_bowl_glow.frame = _bowl_sprite.frame
	if _home_light != null:
		_home_light.base_energy = 0.55 if home else 0.0
		_home_light.visible = home
	if _end_light != null:
		_end_light.visible = state == State.SOLVED or (state == State.DIVE and _state_t > DIVE_IMPACT)
		_end_light.base_energy = 0.7
	if _wisp_light != null:
		_wisp_light.visible = state != State.GONE and state != State.SOLVED


func _sound(name: String, db: float, at: Vector2 = Vector2.INF) -> void:
	var path: String = SOUND_DIR + name + ".wav"
	if not ResourceLoader.exists(path) or not is_inside_tree():
		return
	var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	p.stream = load(path) as AudioStream
	p.volume_db = db
	p.pitch_scale = randf_range(0.97, 1.03)
	p.max_distance = 420.0
	p.attenuation = 1.6
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	p.position = _last_pos + Vector2(0, -_height) if at == Vector2.INF else at
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ------------------------------------------------------------------ animation (every peer)

func _animate(delta: float) -> void:
	var pos: Vector2 = ground_position()
	var want_h: float = float(cfg.get("height", 15.0))
	match state:
		State.SLEEP, State.GONE:
			want_h = _nest_h - 1.0
		State.WAKE:
			want_h = _nest_h + 5.0 * clampf(_state_t / 0.8, 0.0, 1.0)
		State.HOP, State.DART, State.HOVER, State.LINGER:
			want_h = lerpf(_nest_h + 5.0, want_h, clampf(_shown_s / 50.0, 0.0, 1.0))
		State.LOST:
			want_h += _state_t * 6.0
	if state == State.LINGER: ## it circles something curious on the ground
		var a: float = _state_t * 3.4
		pos += Vector2(cos(a) * 11.0, sin(a) * 5.0)
		want_h = 7.0 + sin(a * 2.0) * 2.0
	if state == State.DIVE:
		var t: float = _state_t
		if t < 1.2:
			var r: float = 14.0 * (1.0 - t / 1.2) + 2.0
			var a2: float = t * 7.5
			pos = _end_pos + Vector2(cos(a2) * r, sin(a2) * r * 0.5)
			want_h = 15.0 + 22.0 * smoothstep(0.0, 1.0, t / 1.2)
		elif t < DIVE_IMPACT:
			var k: float = (t - 1.2) / (DIVE_IMPACT - 1.2)
			want_h = 37.0 * (1.0 - k * k)
		else:
			want_h = 0.0
	# hover: breathing bob and a lazy sideways drift, more while it waits
	var moving: float = clampf((pos - _last_pos).length() / maxf(delta, 0.001) / 60.0, 0.0, 1.0)
	var bob: float = sin(_time * 2.6) * (1.6 - moving * 0.8) + sin(_time * 4.3 + 1.0) * 0.5
	if state == State.SLEEP:
		bob = sin(_time * 1.3) * 0.5
	if state != State.DIVE and state != State.SOLVED:
		pos += Vector2(sin(_time * 1.7) * (1.2 + (1.0 - moving) * 1.6), 0.0)
	_height = lerpf(_height, want_h, 1.0 - exp(-(9.0 if state == State.DIVE else 4.0) * delta))
	var draw_h: float = _height + (bob if state != State.DIVE else 0.0)
	_vel = (pos - _last_pos) / maxf(delta, 0.001)
	# the wisp turns to whoever is nearest while it waits or wakes
	var f: Dictionary = _nearest(pos)
	var look: Vector2 = Vector2.ZERO
	if not f.is_empty() and (state == State.HOVER or state == State.WAKE or calling):
		look = ((f.pos as Vector2) - pos).normalized()
		if state == State.WAKE and _state_t < 0.25:
			look *= 2.0 ## the startled flick towards her
	_look = _look.lerp(look, 1.0 - exp(-6.0 * delta))
	_fright = maxf(0.0, _fright - delta * (0.9 if state != State.LOST else 0.0))
	_gold = move_toward(_gold, 1.0 if state == State.DIVE else 0.0, delta * 2.0)
	var vis: float = 1.0
	match state:
		State.LOST:
			vis = clampf(1.0 - _state_t / 1.0, 0.0, 1.0)
		State.GONE, State.SOLVED:
			vis = 0.0
		State.DIVE:
			vis = 1.0 if _state_t < DIVE_IMPACT else 0.0
	_fade = move_toward(_fade, vis, delta * (4.0 if vis > _fade else 6.0))
	_last_pos = pos
	_wisp.position = pos.round()
	_wisp.set_meta("h", draw_h)
	if _wisp_light != null:
		_wisp_light.position = Vector2(0, 2)
		_wisp_light.base_energy = 0.9 * _fade
	# the comet tail and the sparks it leaves on the ground
	var head: Vector2 = pos + Vector2(0, -draw_h)
	_tail.push_front([head, 0.0])
	for e: Array in _tail:
		e[1] = float(e[1]) + delta
	while not _tail.is_empty() and float((_tail.back() as Array)[1]) > TAIL_LIFE:
		_tail.pop_back()
	var speed: float = _vel.length()
	if _fade > 0.3 and speed > 12.0 and state != State.SLEEP:
		_spark_t -= delta * clampf(speed / 50.0, 0.4, 2.5)
		if _spark_t <= 0.0:
			_spark_t = 0.045
			var col: Color = TEAL if randf() < 0.7 else WHITE
			if _fright > 0.4:
				col = VIOLET
			_sparks.append([pos + Vector2(randf_range(-6, 6), randf_range(-3, 3)), 0.0, randf_range(4.5, 6.5), col, 0.0, randf() < 0.3])
	for i: int in range(_sparks.size() - 1, -1, -1):
		var sp: Array = _sparks[i]
		sp[1] = float(sp[1]) + delta
		if float(sp[1]) > float(sp[2]):
			_sparks.remove_at(i)
	while _sparks.size() > MAX_SPARKS:
		_sparks.pop_front()
	# it calls when she falls behind
	if calling and _fade > 0.5:
		_call_t -= delta
		if _call_t <= 0.0:
			_call_t = 2.3
			_sound("call", -4.0)
	else:
		_call_t = 0.4
	if state == State.DIVE and _state_t >= DIVE_IMPACT and _bloom_t < 0.0:
		_bloom_t = 0.0
		_sound("bloom", 1.0, _end_pos)
		_burst(_end_pos, 30, GOLD_LIGHT, 1.6)
		_burst(_end_pos, 20, TEAL, 1.2)
		_shake()
		_apply_look()
	if _bloom_t >= 0.0 and _bloom_t < 99.0:
		_bloom_t += delta
	if _bowl_glow != null:
		_bowl_glow.modulate.a = 0.35 + 0.65 * _night
	_wisp.queue_redraw()
	_ground.queue_redraw()


func _shake() -> void:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_multiplayer_authority() and p.global_position.distance_to(_end_pos) < 220.0 and p.has_method("add_shake"):
			p.call("add_shake", 1.0)


func _burst(at: Vector2, n: int, col: Color, life: float) -> void:
	for i: int in n:
		var a: float = randf() * TAU
		var r: float = randf_range(2.0, 10.0)
		_sparks.append([at + Vector2(cos(a) * r, sin(a) * r * 0.55), 0.0, life * randf_range(0.6, 1.2), col, randf_range(8.0, 26.0)])


func _build_blooms() -> void:
	_blooms.clear()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(id)
	var n: int = 18
	for i: int in n:
		var a: float = TAU * float(i) / float(n) + rng.randf_range(-0.15, 0.15)
		var r: float = rng.randf_range(20.0, 27.0)
		_blooms.append([Vector2(cos(a) * r, sin(a) * r * 0.55).round(), 0.05 * i + rng.randf_range(0.0, 0.25), rng.randi_range(0, 2), rng.randf()])
	for i: int in 5: ## a few smaller ones inside
		var a: float = rng.randf() * TAU
		var r: float = rng.randf_range(14.0, 18.0)
		_blooms.append([Vector2(cos(a) * r, sin(a) * r * 0.55).round(), 0.5 + rng.randf_range(0.0, 0.4), 0, rng.randf()])


# ------------------------------------------------------------------ drawing

func _dot(canvas: Node2D, p: Vector2, c: Color) -> void:
	canvas.draw_rect(Rect2(p.round(), Vector2.ONE), c)


func _tint() -> Color:
	var c: Color = TEAL.lerp(VIOLET, clampf(_fright, 0.0, 1.0))
	return c.lerp(GOLD, _gold)


func _draw_wisp() -> void:
	if _fade <= 0.01:
		return
	var h: float = float(_wisp.get_meta("h", 15.0))
	var c: Vector2 = Vector2(0, -h).round() + (_look * 1.2).round()
	var tint: Color = _tint()
	var breath: float = 0.82 + 0.18 * sin(_time * 2.4)
	if state == State.SLEEP:
		breath = 0.55 + 0.12 * sin(_time * 1.3)
	if calling:
		breath = 1.0
	var a: float = _fade
	var small: float = 0.7 if state == State.SLEEP else 1.0
	# comet tail
	var origin: Vector2 = _wisp.position
	for e: Array in _tail:
		var age: float = float(e[1])
		var k: float = 1.0 - age / TAIL_LIFE
		if k <= 0.0:
			continue
		var tp: Vector2 = ((e[0] as Vector2) - origin).round()
		var col: Color = Color(tint.lerp(WHITE, 0.25 * k), 0.75 * k * a)
		_dot(_wisp, tp, col)
		if k > 0.35: ## thick near the head, a thread at the end
			_dot(_wisp, tp + Vector2(1, 0), Color(tint, 0.5 * k * a))
			_dot(_wisp, tp + Vector2(0, 1), Color(tint, 0.5 * k * a))
		if k > 0.7:
			_dot(_wisp, tp + Vector2(-1, 0), Color(tint, 0.4 * k * a))
			_dot(_wisp, tp + Vector2(0, -1), Color(tint, 0.4 * k * a))
	# dithered halo
	var R: float = 11.0 * small * (1.15 if calling else 1.0)
	for dy: int in range(-13, 14):
		for dx: int in range(-13, 14):
			var r: float = Vector2(dx, dy * 1.1).length()
			if r > R or r < 3.0:
				continue
			var k: float = pow(1.0 - r / R, 1.6) * breath
			var thr: float = (float(BAYER[(dy + 8) & 3][(dx + 8) & 3]) + 0.5) / 16.0
			if k * 1.6 > thr:
				_dot(_wisp, c + Vector2(dx, dy), Color(tint, clampf(0.25 + k * 0.6, 0.0, 0.8) * a))
	# flame tongue: licks up and away from where it flies
	var away: Vector2 = Vector2(0, -1)
	if _vel.length() > 8.0:
		away = (Vector2(0, -1) - _vel.normalized() * 0.9).normalized()
	var flick: int = int(_time * 12.0) % 3
	var tongue: int = 5 + flick * 2
	for i: int in tongue:
		var p: Vector2 = c + away * (3.0 + i) + Vector2(sin(_time * 9.0 + i * 0.8) * (0.4 + i * 0.15), 0)
		var fa: float = (1.0 - float(i) / float(tongue)) * a
		_dot(_wisp, p, Color(tint.lerp(WHITE, 0.35), fa))
		if i < tongue / 2: ## two pixels wide at its root
			_dot(_wisp, p + Vector2(-away.y, away.x).round(), Color(tint, fa * 0.7))
	# body: a disc of colour round a white heart
	var white: Color = WHITE.lerp(GOLD_LIGHT, _gold)
	for dy: int in range(-4, 5):
		for dx: int in range(-4, 5):
			var r: float = Vector2(dx, dy).length()
			if r <= 2.2:
				_dot(_wisp, c + Vector2(dx, dy), Color(white, a))
			elif r <= 3.3:
				_dot(_wisp, c + Vector2(dx, dy), Color(tint.lerp(WHITE, 0.45), a))
			elif r <= 4.2:
				_dot(_wisp, c + Vector2(dx, dy), Color(tint, 0.85 * a))
	if fmod(_time, 2.7) < 0.14: ## a glint
		for p: Vector2 in [Vector2(-2, -2), Vector2(-3, -3), Vector2(-1, -3), Vector2(-3, -1)]:
			_dot(_wisp, c + p, Color(1, 1, 1, a))
	# motes circling it, dimmer behind
	for i: int in 3:
		var ang: float = _time * (2.2 + 0.4 * i) + TAU * i / 3.0
		var rr: float = 11.0 + sin(_time * 1.3 + i) * 2.0
		var mp: Vector2 = c + Vector2(cos(ang) * rr, sin(ang) * rr * 0.45 - 1.0)
		var front: bool = sin(ang) > 0.0
		_dot(_wisp, mp, Color(WHITE if front else tint, (0.95 if front else 0.5) * a))
		if front:
			_dot(_wisp, mp + Vector2(1, 0), Color(tint, 0.6 * a))
	# the call: rings that swell out of it
	if calling:
		var t: float = fmod(_time, 1.15) / 1.15
		var rad: float = 8.0 + t * 18.0
		var steps: int = 40
		for i: int in steps:
			if i % 2 == 1:
				continue
			var an: float = TAU * float(i) / float(steps)
			_dot(_wisp, c + Vector2(cos(an) * rad, sin(an) * rad * 0.7), Color(tint, (1.0 - t) * 0.7 * a))
	# the dive: a gold streak behind the plunge
	if state == State.DIVE and _state_t > 1.2 and _state_t < DIVE_IMPACT:
		for i: int in int(h):
			_dot(_wisp, Vector2(0, -i), Color(GOLD_LIGHT, 0.7 * (1.0 - float(i) / maxf(h, 1.0))))


func _draw_ground() -> void:
	# light pool under the wisp
	if _fade > 0.02 and state != State.SOLVED:
		var g: Vector2 = _last_pos.round()
		var h: float = float(_wisp.get_meta("h", 15.0))
		var near: float = clampf(1.0 - h / 40.0, 0.25, 1.0) * _fade
		var tint: Color = _tint()
		for dy: int in range(-5, 6):
			for dx: int in range(-13, 14):
				var r: float = Vector2(dx / 13.0, dy / 5.0).length()
				if r > 1.0:
					continue
				var thr: float = (float(BAYER[(dy + 8) & 3][(dx + 8) & 3]) + 0.5) / 16.0
				var k: float = (1.0 - r * r) * near
				if k > thr * 1.4: ## a soft, round pool: solid in the middle, a few dither pixels at the rim
					_dot(_ground, g + Vector2(dx, dy), Color(tint, 0.05 + 0.13 * k))
	# the sparks it leaves (and bursts)
	for sp: Array in _sparks:
		var age: float = float(sp[1])
		var life: float = float(sp[2])
		var k: float = 1.0 - age / life
		var rise: float = float(sp[4]) * minf(age, 1.0) * (1.0 - minf(age, 1.0) * 0.5)
		var p: Vector2 = (sp[0] as Vector2) + Vector2(0, -rise)
		var tw: float = 0.6 + 0.4 * sin(_time * 7.0 + (sp[0] as Vector2).x)
		var sc: Color = Color(sp[3] as Color, clampf(k * tw, 0.0, 1.0))
		_dot(_ground, p, sc)
		if sp.size() > 5 and bool(sp[5]) and k > 0.3: ## the bigger ones: a little cross of light
			var side: Color = Color(sc, sc.a * 0.55)
			for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				_dot(_ground, p + d, side)
	# the bloom at the end
	if _bloom_t >= 0.0:
		_draw_bloom()


func _draw_bloom() -> void:
	var t: float = _bloom_t
	var e: Vector2 = _end_pos.round()
	# the shock ring and the cracks of light, only right after the plunge
	if t < 1.0:
		var rad: float = 4.0 + t * 30.0
		for i: int in 48:
			var an: float = TAU * float(i) / 48.0
			_dot(_ground, e + Vector2(cos(an) * rad, sin(an) * rad * 0.55), Color(GOLD_LIGHT.lerp(TEAL, t), (1.0 - t) * 0.9))
	if t < 2.2:
		var k: float = clampf(t / 0.35, 0.0, 1.0)
		var fade: float = clampf((2.2 - t) / 1.2, 0.0, 1.0)
		for i: int in 7:
			var an: float = TAU * float(i) / 7.0 + 0.4
			var length: float = 22.0 * k
			var dir: Vector2 = Vector2(cos(an), sin(an) * 0.55)
			var j: int = 0
			while j < int(length):
				var wob: float = sin(j * 0.9 + i * 2.0) * 0.8
				_dot(_ground, e + dir * j + Vector2(-dir.y, dir.x) * wob, Color(GOLD.lerp(TEAL, float(j) / 22.0), fade * (1.0 - float(j) / 26.0)))
				j += 1
	# a glowing seal where it went in
	var pulse: float = 0.6 + 0.4 * sin(_time * 2.0)
	for dy: int in range(-2, 3):
		for dx: int in range(-4, 5):
			if Vector2(dx / 4.0, dy / 2.0).length() <= 1.0:
				_dot(_ground, e + Vector2(dx, dy), Color(TEAL_DEEP.lerp(GOLD_LIGHT, 0.3 * pulse), 0.35 * pulse))
	# the ring of light flowers
	for b: Array in _blooms:
		var grow: float = clampf((t - float(b[1])) / 0.6, 0.0, 1.0)
		if grow <= 0.0:
			continue
		var at: Vector2 = e + (b[0] as Vector2)
		var size: int = int(b[2])
		var hue: float = float(b[3])
		var stem: int = int(round(lerpf(0.0, 2.0 + size, grow)))
		for i: int in stem:
			_dot(_ground, at + Vector2(0, -i), Color("4a7d58"))
		if grow < 0.5:
			continue
		var head: Vector2 = at + Vector2(0, -stem)
		var petal: Color = TEAL.lerp(Color("c9b8ff"), hue * 0.6)
		var glow: float = (0.75 + 0.25 * sin(_time * 2.2 + hue * 6.0)) * (0.55 + 0.45 * _night)
		for p: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			_dot(_ground, head + p, Color(petal, glow))
		if size >= 2:
			for p: Vector2 in [Vector2(-1, -1), Vector2(1, -1)]:
				_dot(_ground, head + p, Color(petal.darkened(0.25), glow * 0.8))
		_dot(_ground, head, Color(GOLD_LIGHT, glow))
