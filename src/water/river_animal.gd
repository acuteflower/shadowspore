class_name RiverAnimal
extends Node2D
## Host-owned ecological actions, replayed atomically on every peer and late join.
enum Mode { REST, TRAVEL, FLEE, HOP, DIVE, PERCH, FLY, STRIKE, DABBLE, PLUNGE }
const NEW_KINDS: Array[String] = ["heron", "otter", "kingfisher", "duck"] ## the waterside animals with their own sheets (the frog has one too)
const SOUND_COOLDOWN: float = 14.0
var kind: String = "shoal"
var home: Vector2
var school: String = ""
var member: int = 0
var facing: float = 0.0
var mode: Mode = Mode.REST
var _start: Vector2
var _end: Vector2
var _curve: Vector2
var _elapsed: float = 0.0
var _duration: float = 1.0
var _sense: float = 0.0
var _fear_left: float = 0.0
var _alert_left: float = 0.0
var _lift: float = 0.0
var _threat: Vector2
var _moving: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spec: Dictionary
var _population: RiverFauna
var _aux: int = 0 ## a small extra of the current action: heron 0 idle 1 caught a fish 2 hunch 3 preen; frog 1 croak; kingfisher 1 look 2 holds a fish; duck 3 preen
var _hit_done: bool = false ## the strike's moment (the fish scatter) already happened
var _sound_wait: float = 0.0
var _wake_wait: float = 0.0
var _voice: AudioStreamPlayer2D
@onready var _sprite: Sprite2D = $Sprite
@onready var _ripples: WaterRipples = $Ripples

func _ready() -> void:
	add_to_group("wild_animals") ## the cursor shrinks to a dot over animals (GameCursor)
	_population = get_parent().get_parent() as RiverFauna
	_spec = DataRegistry.get_entry("river_animals", kind)
	_rng.seed = hash(name) + member * 173
	_start = position
	_end = position
	_duration = _rng.randf_range(0.4, 2.0)
	add_to_group("river_animals")
	_sound_wait = _rng.randf_range(2.0, SOUND_COOLDOWN)
	if _spec.has("sheet"):
		_sprite.texture = load(String(_spec.sheet)) as Texture2D
		_sprite.hframes = int(_spec.cols)
		_sprite.vframes = int(_spec.builds) * 8
		_sprite.offset = -Vector2(float(_spec.feet[0]), float(_spec.feet[1]))
	if not multiplayer.is_server(): _request.rpc_id(1)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if multiplayer.is_server():
		_fear_left = maxf(0.0, _fear_left - delta)
		_alert_left = maxf(0.0, _alert_left - delta)
		_sense -= delta
		if _sense <= 0.0:
			_sense = float(DataRegistry.table("river_animals")["sense_interval"])
			_sense_players()
	_wake_wait -= delta
	_sound_wait -= delta
	if kind in NEW_KINDS or kind == "frog":
		_new_life(delta)
	if _moving:
		var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
		var u: float = smoothstep(0.0, 1.0, t) if kind in ["frog", "strider"] else t
		var p: Vector2 = _start.lerp(_end, u) + _curve * sin(u * PI)
		facing = (p - position).angle() if p.distance_to(position) > 0.01 else facing
		position = p
		if t >= 1.0:
			_moving = false
			if mode == Mode.PLUNGE: _ripples.add(global_position, 1.2)
			if kind == "heron" and mode == Mode.FLY and _population.rivers.field_at(position).x <= 0.0: _ripples.add(global_position, 0.75)
			if kind in ["frog", "strider"]: _ripples.add(global_position, 0.3 if kind == "strider" else 0.8)
	if multiplayer.is_server() and _elapsed >= _duration: _choose()

## Host: something nearby frightened it (the heron's strike): it bolts like at a threat.
func startle(from: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_threat = from
	_fear_left = 2.5
	if mode not in [Mode.FLEE, Mode.HOP, Mode.DIVE, Mode.FLY]:
		_choose()


func _sense_players() -> void:
	for player: Player in Player.all:
		if player.health.current <= 0.0 or player.story_lock or player.fainting: continue
		var radius: float = float(_spec["fear"])
		var alert_radius: float = float(_spec.get("alert_range", radius))
		var wet: bool = _population.rivers.field_at(player.global_position).x <= 0.0
		if kind in ["shoal", "brook"]:
			radius *= (1.35 if wet and player.velocity.length() > 30 else 0.65)
		if player.stealth.sneaking:
			radius *= 0.55
			alert_radius *= 0.58
		if player.sprinting:
			alert_radius *= 1.25
		if player.swim > 0:
			var swim_mult: float = 1.5 if player.swim == SwimRules.CRAWL else 1.15 ## swimmers churn the water
			radius *= swim_mult
			alert_radius *= swim_mult
		var dist: float = position.distance_to(player.global_position)
		if dist < radius:
			_threat = player.global_position
			_fear_left = 2.5
			if mode not in [Mode.FLEE, Mode.HOP, Mode.DIVE, Mode.FLY]: _choose()
			return
		if kind in ["heron", "otter"] and dist < alert_radius:
			_threat = player.global_position
			_alert_left = 1.8
			if mode == Mode.REST and _aux != 4:
				_act.rpc(Mode.REST, position, position, Vector2.ZERO, 1.5, (_threat - position).angle(), 0.0, 4)
			return

func _choose() -> void:
	if kind in NEW_KINDS:
		_choose_waterside()
		return
	var wet: bool = _population.rivers.field_at(position).x <= 0.0
	if kind == "dragonfly" and TimeManager.is_night():
		if position.distance_to(home) > 3.0 and _population.valid_route(self, home, Vector2.ZERO):
			_act.rpc(Mode.TRAVEL, position, home, Vector2.ZERO, maxf(0.5, position.distance_to(home) / float(_spec["speed"])), (home - position).angle(), 0.0, 0)
		else: _act.rpc(Mode.PERCH, position, position, Vector2.ZERO, 3.0, facing, 0.0, 0)
		return
	if kind == "frog" and wet and mode in [Mode.HOP, Mode.FLEE]:
		_act.rpc(Mode.DIVE, position, position, Vector2.ZERO, _rng.randf_range(1.5, 3.0), facing, 0.0, 0)
		return
	var rest: Array = _spec["rest"]
	if _fear_left <= 0.0 and mode not in [Mode.REST, Mode.PERCH, Mode.DIVE]:
		var heading: float = (-_population.flow_at(position)).angle() if kind == "brook" else facing
		var croak: int = 1 if kind == "frog" and _rng.randf() < (0.55 if TimeManager.night_amount() > 0.4 else 0.12) else 0
		_act.rpc(Mode.PERCH if kind == "dragonfly" and not wet else Mode.REST, position, position, Vector2.ZERO, _rng.randf_range(float(rest[0]), float(rest[1])) * (0.5 if croak == 1 else 1.0), heading, 0.0, croak)
		return
	var desired: Vector2 = home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(12.0, float(_spec["range"]))
	if _fear_left > 0.0: desired = position + (position - _threat).normalized() * 35.0
	elif kind == "shoal" and member > 0:
		var leader: RiverAnimal = _population.leader(school)
		if leader != null: desired = leader._end + Vector2.from_angle(member * 2.4) * 9.0
	elif kind == "dragonfly" and _rng.randf() < 0.4: desired = home
	elif kind == "frog": desired = _population.shore_target(home, not wet, _rng)
	elif kind == "brook": desired = _population.cover_target(home) + Vector2.from_angle(_rng.randf() * TAU) * 8.0
	for attempt: int in 18:
		var point: Vector2 = desired if attempt == 0 else position + (desired - position).rotated(_rng.randf_range(-2.5, 2.5)).limit_length(_rng.randf_range(10, 38))
		var curve: Vector2 = Vector2(-(point - position).y, (point - position).x).normalized() * (3.0 if kind in ["shoal", "brook", "frog"] else 8.0)
		if not _population.valid_route(self, point, curve): continue
		var next: Mode = Mode.FLEE if _fear_left > 0.0 else Mode.TRAVEL
		if kind == "frog" and not wet: next = Mode.HOP
		if kind == "frog" and _fear_left > 0.0 and not wet:
			if _population.rivers.field_at(point).x >= 0.0: continue
		var speed: float = float(_spec["flee_speed"] if _fear_left > 0.0 else _spec["speed"])
		_act.rpc(next, position, point, curve, maxf(0.35, position.distance_to(point) / speed), (point - position).angle(), 0.0, 0)
		return
	_act.rpc(Mode.REST, position, position, Vector2.ZERO, 0.7, facing, 0.0, 0)

@rpc("authority", "call_local", "reliable")
func _act(next: int, start: Vector2, end: Vector2, curve: Vector2, seconds: float, heading: float, elapsed: float, aux: int) -> void:
	mode = next as Mode
	_aux = aux
	_hit_done = false
	_start = start
	_end = end
	_curve = curve
	_duration = maxf(0.1, seconds)
	_elapsed = elapsed
	facing = heading
	_moving = start.distance_to(end) > 0.01
	if not _moving: position = end
	if kind in ["frog", "strider"] and _moving and elapsed == 0.0: _ripples.add(start, 0.25)
	if kind == "heron" and mode == Mode.FLY and elapsed == 0.0 and _population != null and _population.rivers.field_at(start).x <= 0.0:
		_ripples.add(start, 0.85)
	if kind == "otter" and elapsed == 0.0 and _population != null and _population.rivers.field_at(start).x <= 0.5:
		if mode in [Mode.PLUNGE, Mode.DIVE]:
			_ripples.add(start, 0.95)
		elif mode == Mode.STRIKE:
			_ripples.add(start, 0.78)
	if kind == "duck" and elapsed == 0.0 and _population != null and _population.rivers.field_at(start).x <= 0.0:
		if mode == Mode.FLY:
			_ripples.add(start, 0.82)
		elif mode == Mode.DABBLE:
			_ripples.add(start, 0.42)

@rpc("any_peer", "call_remote", "reliable")
func _request() -> void:
	if multiplayer.is_server(): _act.rpc_id(multiplayer.get_remote_sender_id(), mode, _start, _end, _curve, _duration, facing, _elapsed, _aux)

## Waterside animals: what they do besides moving (host: the heron's strike frightens fish; every peer: wake ripples and voices).
func _new_life(_delta: float) -> void:
	var ratio: float = clampf(_elapsed / _duration, 0.0, 1.0)
	if kind == "heron" and mode == Mode.STRIKE and not _hit_done and ratio > 0.36:
		_hit_done = true
		if multiplayer.is_server():
			_population.scare_fish(global_position + Vector2.from_angle(facing) * 12.0, 46.0)
		_ripples.add(global_position + Vector2.from_angle(facing) * 12.0, 1.05)
	if _moving and _wake_wait <= 0.0 and kind in ["duck", "heron", "otter"] and mode in [Mode.TRAVEL, Mode.FLEE, Mode.DIVE] and _population.rivers.field_at(position).x < 0.0:
		_wake_wait = 0.26 if (kind == "otter" and mode == Mode.DIVE) else (0.36 if kind == "otter" else (0.55 if kind == "duck" else 0.7))
		_ripples.add(global_position, 0.16 if (kind == "otter" and mode == Mode.DIVE) else (0.28 if kind == "otter" else (0.22 if kind == "duck" else 0.3)))
	if _sound_wait <= 0.0 and _spec.has("sound"):
		_sound_wait = _rng.randf_range(SOUND_COOLDOWN, SOUND_COOLDOWN * 2.2)
		var calls: bool = false
		match kind:
			"frog": calls = _aux == 1 and mode == Mode.REST
			"duck": calls = mode in [Mode.REST, Mode.TRAVEL] and _rng.randf() < 0.5
			"heron": calls = mode in [Mode.FLY] or (mode == Mode.REST and _rng.randf() < 0.15)
			"otter": calls = (mode == Mode.REST and _aux == 4) or (mode in [Mode.TRAVEL, Mode.STRIKE] and _rng.randf() < 0.35)
			"kingfisher": calls = mode in [Mode.FLY, Mode.PERCH] and _rng.randf() < 0.6
		if calls:
			_call()


func _call() -> void:
	if _voice == null:
		_voice = AudioStreamPlayer2D.new()
		_voice.max_distance = 240.0
		_voice.volume_db = -20.0
		_voice.bus = &"Master"
		add_child(_voice)
	if _voice.playing:
		return
	var stream_idx: int = _rng.randi() % 2
	if kind == "duck":
		stream_idx = 1 if _build() == 0 else 0
	_voice.stream = load("res://assets/audio/wildlife/%s_%d.wav" % [String(_spec.sound), stream_idx]) as AudioStream
	_voice.pitch_scale = _rng.randf_range(0.92, 1.1) * (1.42 if kind == "duck" and member > 0 and school.begins_with("duckfamily") else 1.0)
	_voice.play()


## Which of the sheet's builds this animal wears (heron/frog by school, duck: drake / hen / duckling).
func _build() -> int:
	match kind:
		"duck":
			if member > 0 and school.begins_with("duckfamily"):
				return 2
			if school.begins_with("duckfamily") or member == 1:
				return 1
			return 0
		"otter":
			if member > 0:
				return 2
			return absi(hash(school)) % 2
		"heron", "frog":
			return absi(hash(school)) % int(_spec.builds)
	return 0


## The sheet column for the current action (see art_water_animals.py for the blocks).
func _column() -> int:
	var ratio: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var loop: float = _elapsed
	match kind:
		"heron":
			match mode:
				Mode.REST:
					if _aux == 5:
						return 4 + int(loop * 1.6) % 4
					if _aux == 2:
						return 8 + int(loop * 2.0) % 4
					if _aux == 3:
						return 30 + int(loop * 2.8) % 4
					if _aux == 4:
						return 34 + int(loop * 2.2) % 4
					return int(loop * 2.0) % 4
				Mode.TRAVEL, Mode.FLEE:
					return 12 + int(loop * 4.2) % 8
				Mode.STRIKE:
					if ratio < 0.65 or _aux == 0:
						return 20 + mini(5, int(maxf(0.0, ratio - 0.08) / 0.57 * 6.0))
					return 26 + mini(3, int((ratio - 0.65) / 0.35 * 4.0))
				Mode.FLY:
					if loop < 0.52:
						return 50 + mini(3, int(loop / 0.13))
					if loop > _duration - 0.52:
						return 54 + mini(3, int((loop - (_duration - 0.52)) / 0.13))
					if ratio > 0.38 and ratio < 0.66:
						return 46 + int(loop * 4.0) % 4
					return 38 + int(loop * 6.2) % 8
		"otter":
			var wet_col: bool = _population != null and _population.rivers.field_at(position).x <= -0.8
			match mode:
				Mode.REST:
					if _aux == 4:
						return 8 + int(loop * 2.4) % 4
					if _aux == 1 and wet_col:
						return 44 + int(loop * 4.5) % 8
					if _aux == 3 and not wet_col:
						return 34 + int(loop * 3.6) % 4
					if _aux == 5 and not wet_col:
						return 52 + int(loop * 1.4) % 6
					return (4 + int(loop * 2.0) % 4) if wet_col else (int(loop * 2.2) % 4)
				Mode.TRAVEL, Mode.FLEE:
					return (20 + int(loop * 7.2) % 8) if wet_col else (12 + int(loop * 8.0) % 8)
				Mode.PLUNGE:
					return 28 + mini(5, int(ratio * 6.0))
				Mode.STRIKE:
					if ratio < 0.36:
						return 38 + mini(5, int(ratio / 0.36 * 6.0))
					return 44 + int((loop - _duration * 0.36) * 5.0) % 8
		"frog":
			match mode:
				Mode.REST: return 4 + int(loop * 7.0) % 4 if _aux == 1 else int(loop * 3.0) % 4
				Mode.HOP: return 8 + mini(5, int(ratio * 6.0))
				Mode.TRAVEL, Mode.FLEE: return 14 + int(loop * 9.0) % 6
			return 0
		"kingfisher":
			match mode:
				Mode.PERCH, Mode.REST: return 20 + int(loop * 3.0) % 4 if _aux == 2 else (4 + int(loop * 3.0) % 4 if _aux == 1 else int(loop * 2.5) % 4)
				Mode.PLUNGE: return 8 + mini(5, int(ratio * 6.0))
				Mode.FLY, Mode.TRAVEL, Mode.FLEE: return 14 + int(loop * 16.0) % 6
		"duck":
			var duck_wet: bool = _population == null or _population.rivers.field_at(position).x <= -0.6
			match mode:
				Mode.REST:
					if not duck_wet and int(_spec.cols) >= 58:
						if _aux == 5:
							return 52 + int(loop * 1.6) % 6
						if _aux == 4:
							return 46 + mini(5, int(ratio * 6.0))
						return 34 + int(loop * 2.2) % 4
					return 16 + int(loop * 3.0) % 4 if _aux == 3 else int(loop * 2.5) % 4
				Mode.TRAVEL, Mode.FLEE:
					if not duck_wet and int(_spec.cols) >= 58:
						return 38 + int(loop * 8.2) % 8
					return 4 + int(loop * 7.6) % 6
				Mode.DABBLE:
					return 10 + mini(5, int(ratio * 6.0))
				Mode.FLY:
					return 28 + mini(5, int(loop / 0.095)) if loop < 0.57 else 20 + int(loop * 12.5) % 8
	return 0


func _process(_delta: float) -> void:
	if _spec.has("sheet"):
		var flying: bool = mode == Mode.FLY
		var ratio: float = clampf(_elapsed / _duration, 0.0, 1.0)
		var depth_here: float = _population.rivers.field_at(position).y
		var wet_here: bool = _population.rivers.field_at(position).x <= 0.0
		_sprite.frame = (_build() * 8 + posmod(roundi(facing / (PI / 4.0)), 8)) * int(_spec.cols) + _column()
		_sprite.visible = mode != Mode.DIVE
		var lift: float = 0.0
		if flying:
			lift = float(_spec.get("altitude", 14.0)) * sin(ratio * PI) ** 0.6 + (2.0 if kind == "kingfisher" else 0.0)
		elif kind == "kingfisher":
			lift = float(_spec.perch_height) * (1.0 - ratio) if mode == Mode.PLUNGE else (float(_spec.perch_height) if mode in [Mode.PERCH, Mode.REST] else 0.0)
		_lift = lift
		_sprite.position.y = -roundf(lift)
		z_index = 0 if flying or (kind == "kingfisher") or not wet_here else -6
		_sprite.modulate = Color(0.86, 0.95, 0.95) if kind in ["duck", "otter"] and wet_here and depth_here > 0.0 else Color.WHITE
		if kind in ["heron", "otter", "duck"]:
			queue_redraw()
		return
	var types: Array[String] = ["shoal", "brook", "frog", "dragonfly", "strider"]
	var row: int = types.find(kind) * 8 + posmod(roundi(facing / (PI / 4.0)), 8)
	var frame: int = int(_elapsed * (16.0 if kind == "dragonfly" else 8.0)) % 8
	if kind == "frog": frame = 1 + mini(4, int(_elapsed / _duration * 5)) if mode == Mode.HOP else (6 + int(_elapsed * 4) % 2 if _population.rivers.field_at(position).x <= 0.0 else 0)
	if kind == "dragonfly" and mode == Mode.PERCH or kind == "strider" and mode == Mode.REST: frame = 0
	_sprite.frame = row * 8 + frame
	var depth: float = _population.rivers.field_at(position).y
	_sprite.modulate = Color(0.64, 0.85, 0.80, lerpf(0.88, 0.43, depth)) if kind in ["shoal", "brook"] else Color.WHITE
	_sprite.visible = mode != Mode.DIVE
	_sprite.position.y = -5.0 - sin(_elapsed * 4.0) if kind == "dragonfly" and mode != Mode.PERCH else (-9.0 if kind == "dragonfly" else 0.0)
	z_index = -6 if kind in ["shoal", "brook", "strider"] or kind == "frog" and depth > 0.0 else 0


func _draw() -> void:
	if kind not in ["heron", "otter", "duck"] or mode == Mode.DIVE:
		return
	if kind == "duck" and mode != Mode.FLY and _population != null and _population.rivers.field_at(position).x <= -0.6:
		return
	var fade: float = clampf(1.0 - _lift / 42.0, 0.18, 1.0)
	var radius: float = 4.6 if kind == "heron" else (2.6 if kind == "duck" and _build() == 2 else (3.8 if kind == "duck" else (3.6 if member > 0 else 4.4)))
	draw_set_transform(Vector2(0.0, -1.0), 0.0, Vector2(1.25 - minf(_lift / 80.0, 0.35), 0.38))
	draw_circle(Vector2.ZERO, radius, Color(0.03, 0.025, 0.065, 0.22 * fade))
	draw_set_transform(Vector2.ZERO)


# ------------------------------------------------------------------------------------ the waterside animals (host decisions)
func _choose_waterside() -> void:
	var rest: Array = _spec["rest"]
	var rest_time: float = _rng.randf_range(float(rest[0]), float(rest[1]))
	var here: Vector2 = _population.rivers.field_at(position)
	match kind:
		"heron":
			if _fear_left > 0.0:
				_fly_from_threat(1)
				return
			if _alert_left > 0.0:
				_act.rpc(Mode.REST, position, position, Vector2.ZERO, 1.4, (_threat - position).angle(), 0.0, 4)
				return
			var roll: float = _rng.randf()
			var was_hunched: bool = mode == Mode.REST and _aux == 2
			if (was_hunched or roll < 0.28) and here.x < 4.5 and here.y < 0.5:
				var strike_dir: float = INF
				var fish: RiverAnimal = _population.nearest_fish(position, 44.0)
				if fish != null:
					strike_dir = (fish.position - position).angle()
				else:
					for attempt: int in 10:
						var angle: float = facing + _rng.randf_range(-1.1, 1.1)
						var spot: Vector2 = position + Vector2.from_angle(angle) * _rng.randf_range(11.0, 18.0)
						var spot_field: Vector2 = _population.rivers.field_at(spot)
						if spot_field.x < -0.8 and spot_field.y < 0.55:
							strike_dir = angle
							break
				if not is_inf(strike_dir):
					if not was_hunched and _rng.randf() < 0.52:
						_act.rpc(Mode.REST, position, position, Vector2.ZERO, _rng.randf_range(1.4, 2.5), strike_dir, 0.0, 2)
					else:
						_act.rpc(Mode.STRIKE, position, position, Vector2.ZERO, 2.1, strike_dir, 0.0, 1 if _rng.randf() < 0.55 else 0)
					return
			if roll < 0.56:
				for attempt: int in 14:
					var point: Vector2 = position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(12.0, 36.0)
					if _population.valid_route(self, point, Vector2.ZERO):
						_act.rpc(Mode.TRAVEL, position, point, Vector2.ZERO, maxf(0.9, position.distance_to(point) / float(_spec.speed)), (point - position).angle(), 0.0, 0)
						return
			if roll < 0.62:
				for attempt: int in 12:
					var wing_point: Vector2 = home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(55.0, float(_spec.range))
					if wing_point.distance_to(position) > 48.0 and _population.valid_flight(self, wing_point) and _population.valid_landing(self, wing_point):
						_act.rpc(Mode.FLY, position, wing_point, Vector2.ZERO, maxf(1.4, position.distance_to(wing_point) / float(_spec.flee_speed)) + 0.7, (wing_point - position).angle(), 0.0, 0)
						return
			var weather_node: Node = get_tree().get_first_node_in_group("weather")
			var rainy: bool = weather_node != null and float(weather_node.get("rain")) >= 0.35
			var rest_poses: Array[int] = [0, 0, 2, 3, 5]
			if rainy or TimeManager.night_amount() >= 0.35:
				rest_poses = [5, 5, 5, 0, 3]
			_act.rpc(Mode.REST, position, position, Vector2.ZERO, rest_time, facing + (_rng.randf_range(-0.7, 0.7) if _rng.randf() < 0.4 else 0.0), 0.0, rest_poses[_rng.randi() % rest_poses.size()])
		"kingfisher":
			if _fear_left > 0.0:
				_fly_from_threat(0)
				return
			if mode == Mode.PLUNGE: ## back to the perch with a fish (or without one)
				var caught: int = 1 if _rng.randf() < 0.55 else 0
				_act.rpc(Mode.FLY, position, home, Vector2.ZERO, maxf(0.6, position.distance_to(home) / float(_spec.speed)), (home - position).angle(), 0.0, caught)
				return
			if mode == Mode.FLY and _aux == 1: ## landed with a fish: holds it for a moment
				_act.rpc(Mode.PERCH, home, home, Vector2.ZERO, 2.6, facing, 0.0, 2)
				return
			if _rng.randf() < 0.4:
				for attempt: int in 14:
					var point: Vector2 = home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(14.0, float(_spec.range) * 0.5)
					var field: Vector2 = _population.rivers.field_at(point)
					if field.x < -3.0 and field.y < 0.65 and _population.valid_flight(self, point):
						_act.rpc(Mode.PLUNGE, position, point, Vector2.ZERO, maxf(0.7, position.distance_to(point) / 55.0), (point - position).angle(), 0.0, 0)
						return
			_act.rpc(Mode.PERCH, home, home, Vector2.ZERO, rest_time, facing, 0.0, 1 if _rng.randf() < 0.3 else 0)
		"duck":
			_choose_duck(rest_time, here)
		"otter":
			_choose_otter(rest_time, here)


func _choose_otter(rest_time: float, here: Vector2) -> void:
	var wet_now: bool = here.x <= -0.8
	if _fear_left > 0.0:
		var away: Vector2 = (position - _threat).normalized()
		for attempt: int in 16:
			var target: Vector2 = position + away.rotated(_rng.randf_range(-1.3, 1.3)) * _rng.randf_range(34.0, 74.0)
			if attempt > 6:
				target = _population.shore_target(home, true, _rng)
			var f: Vector2 = _population.rivers.field_at(target)
			if _population.valid_route(self, target, Vector2.ZERO):
				var next_mode: Mode = Mode.DIVE if (wet_now and f.x < -2.0) else Mode.FLEE
				if next_mode == Mode.DIVE:
					_population.disturb_herons(position, 44.0)
				_act.rpc(next_mode, position, target, Vector2.ZERO, maxf(0.45, position.distance_to(target) / float(_spec.flee_speed)), (target - position).angle(), 0.0, 0)
				return
		_act.rpc(Mode.REST, position, position, Vector2.ZERO, 0.8, facing, 0.0, 4)
		return
	if _alert_left > 0.0:
		_act.rpc(Mode.REST, position, position, Vector2.ZERO, 1.5, (_threat - position).angle(), 0.0, 4)
		return
	if mode == Mode.PLUNGE:
		for attempt: int in 14:
			var flow: Vector2 = _population.flow_at(position)
			var dive_end: Vector2 = position + (flow * _rng.randf_range(22.0, 44.0)).rotated(_rng.randf_range(-0.9, 0.9))
			if _population.rivers.field_at(dive_end).x < -2.5 and _population.valid_route(self, dive_end, Vector2.ZERO):
				_population.scare_fish(position, 42.0)
				_population.disturb_herons(position, 42.0)
				_act.rpc(Mode.DIVE, position, dive_end, Vector2.ZERO, _rng.randf_range(1.1, 1.8), (dive_end - position).angle(), 0.0, 1 if _rng.randf() < 0.72 else 0)
				return
		_act.rpc(Mode.STRIKE, position, position, Vector2.ZERO, 2.8, facing, 0.0, 1)
		return
	if mode == Mode.DIVE and _aux == 1:
		_act.rpc(Mode.STRIKE, position, position, Vector2.ZERO, _rng.randf_range(2.6, 3.6), facing, 0.0, 1)
		return
	if member > 0:
		var lead: RiverAnimal = _population.leader(school)
		if lead != null:
			var trail: Vector2 = lead.position - Vector2.from_angle(lead.facing) * 14.0 + Vector2.from_angle(float(member) * 1.9) * 5.0
			if position.distance_to(trail) > 9.0 and _population.valid_route(self, trail, Vector2.ZERO):
				var curve_f: Vector2 = Vector2(-(trail - position).y, (trail - position).x).normalized() * 4.5
				if not _population.valid_route(self, trail, curve_f):
					curve_f = Vector2.ZERO
				_act.rpc(Mode.TRAVEL, position, trail, curve_f, maxf(0.55, position.distance_to(trail) / (float(_spec.speed) * 1.15)), (trail - position).angle(), 0.0, 0)
				return
	var roll: float = _rng.randf()
	if wet_now and here.x < -2.5 and roll < 0.30:
		_act.rpc(Mode.PLUNGE, position, position, Vector2.ZERO, 0.56, facing, 0.0, 1)
		return
	if roll < 0.68:
		var go_wet: bool = true if not wet_now and _rng.randf() < 0.65 else (false if wet_now and _rng.randf() < 0.28 else wet_now)
		for attempt: int in 16:
			var goal: Vector2 = _population.shore_target(home, go_wet, _rng) if attempt < 6 else (home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(16.0, float(_spec.range) * 0.65))
			if attempt == 0 and go_wet:
				goal = _population.cover_target(home)
			var curve: Vector2 = Vector2(-(goal - position).y, (goal - position).x).normalized() * (6.5 if wet_now else 3.0)
			if not _population.valid_route(self, goal, curve):
				curve = Vector2.ZERO
			if goal.distance_to(position) > 10.0 and _population.valid_route(self, goal, curve):
				_act.rpc(Mode.TRAVEL, position, goal, curve, maxf(0.65, position.distance_to(goal) / float(_spec.speed)), (goal - position).angle(), 0.0, 0)
				return
	var aux_choice: int = 0
	if not wet_now:
		if TimeManager.night_amount() > 0.65 and _rng.randf() < 0.45:
			aux_choice = 5
		elif _rng.randf() < 0.48:
			aux_choice = 3
	elif _rng.randf() < 0.25:
		aux_choice = 4
	_act.rpc(Mode.REST, position, position, Vector2.ZERO, rest_time, facing + _rng.randf_range(-0.6, 0.6), 0.0, aux_choice)


func _choose_duck(rest_time: float, here: Vector2) -> void:
	var family: bool = school.begins_with("duckfamily")
	var young: bool = family and member > 0
	var wet_now: bool = here.x <= -0.6
	if _fear_left > 0.0:
		if family or not wet_now:
			var away: Vector2 = position + (position - _threat).normalized() * 38.0
			for attempt: int in 14:
				var point: Vector2 = away if attempt == 0 else (_population.shore_target(home, true, _rng) if attempt > 6 else position + (away - position).rotated(_rng.randf_range(-1.6, 1.6)).limit_length(_rng.randf_range(16.0, 38.0)))
				if _population.valid_route(self, point, Vector2.ZERO):
					if wet_now and _rng.randf() < 0.4:
						_call()
					_act.rpc(Mode.FLEE, position, point, Vector2.ZERO, maxf(0.4, position.distance_to(point) / float(_spec.flee_speed)), (point - position).angle(), 0.0, 0)
					return
		_call()
		_fly_from_threat(0)
		return
	if young: ## ducklings follow their mother in a neat single-file wake line
		var mother: RiverAnimal = _population.leader(school)
		if mother != null:
			var spot: Vector2 = mother.position - Vector2.from_angle(mother.facing) * (8.5 + 6.0 * float(member)) + Vector2.from_angle(float(member) * 2.1) * 2.5
			if position.distance_to(spot) > 5.5 and _population.valid_route(self, spot, Vector2.ZERO):
				_act.rpc(Mode.TRAVEL, position, spot, Vector2.ZERO, maxf(0.38, position.distance_to(spot) / (float(_spec.speed) * 1.32)), (spot - position).angle(), 0.0, 0)
				return
		_act.rpc(Mode.REST, position, position, Vector2.ZERO, _rng.randf_range(0.8, 1.6), facing, 0.0, 5 if (not wet_now and TimeManager.night_amount() > 0.5) else 0)
		return
	if not family and member == 1: ## paired hen stays companionably near her drake
		var drake: RiverAnimal = _population.leader(school)
		if drake != null and position.distance_to(drake.position) > 22.0:
			var mate_spot: Vector2 = drake.position - Vector2.from_angle(drake.facing) * 10.0 + Vector2.from_angle(drake.facing + PI * 0.5) * 8.0
			if _population.valid_route(self, mate_spot, Vector2.ZERO):
				_act.rpc(Mode.TRAVEL, position, mate_spot, Vector2.ZERO, maxf(0.55, position.distance_to(mate_spot) / float(_spec.speed)), (mate_spot - position).angle(), 0.0, 0)
				return
	var roll: float = _rng.randf()
	if wet_now and roll < 0.30 and here.x < -2.5 and here.y < 0.62:
		_act.rpc(Mode.DABBLE, position, position, Vector2.ZERO, _rng.randf_range(2.1, 2.8), facing, 0.0, 0)
		return
	if roll < 0.66:
		var want_shore: bool = (not family) and ((TimeManager.night_amount() > 0.55 and wet_now) or (wet_now and _rng.randf() < 0.22))
		var want_water: bool = not wet_now and TimeManager.night_amount() < 0.45 and _rng.randf() < 0.62
		for attempt: int in 16:
			var point: Vector2 = position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(14.0, 42.0)
			if attempt < 6 and (want_shore or want_water):
				point = _population.shore_target(home, want_water, _rng)
			var curve: Vector2 = Vector2(-(point - position).y, (point - position).x).normalized() * (4.0 if wet_now else 1.5)
			if not _population.valid_route(self, point, curve):
				curve = Vector2.ZERO
			if point.distance_to(position) > 8.0 and _population.valid_route(self, point, curve):
				_act.rpc(Mode.TRAVEL, position, point, curve, maxf(0.75, position.distance_to(point) / float(_spec.speed)), (point - position).angle(), 0.0, 0)
				return
	var rest_aux: int = 0
	if not wet_now:
		if TimeManager.night_amount() > 0.45 or _rng.randf() < 0.38:
			rest_aux = 5
		elif _rng.randf() < 0.45:
			rest_aux = 4
	elif _rng.randf() < 0.34:
		rest_aux = 3
	_act.rpc(Mode.REST, position, position, Vector2.ZERO, rest_time, facing + _rng.randf_range(-0.45, 0.45), 0.0, rest_aux)


## Takes off away from `_threat` to a spot of its own kind of ground (aux 1: nothing special for the heron / 0 for the others).
func _fly_from_threat(aux: int) -> void:
	var away: Vector2 = (position - _threat).normalized()
	for attempt: int in 16:
		var point: Vector2 = position + away.rotated(_rng.randf_range(-1.2, 1.2)) * _rng.randf_range(70.0, float(_spec.range) + 30.0)
		if kind == "kingfisher":
			point = _population.perch_near(position, point, home)
		if _population.valid_flight(self, point) and _population.valid_landing(self, point):
			_act.rpc(Mode.FLY, position, point, Vector2.ZERO, maxf(1.2, position.distance_to(point) / float(_spec.flee_speed)) + 0.8, (point - position).angle(), 0.0, 0)
			if kind == "kingfisher":
				home = point
			return
	_act.rpc(Mode.REST, position, position, Vector2.ZERO, 1.0, facing, 0.0, 0)
