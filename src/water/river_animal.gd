class_name RiverAnimal
extends Node2D
## Host-owned ecological actions, replayed atomically on every peer and late join.
enum Mode { REST, TRAVEL, FLEE, HOP, DIVE, PERCH, FLY, STRIKE, DABBLE, PLUNGE }
const NEW_KINDS: Array[String] = ["heron", "kingfisher", "duck"] ## the waterside animals with their own sheets (the frog has one too)
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
		if kind == "duck" and member > 0 and school.begins_with("duckfamily"):
			_sprite.scale = Vector2(0.8, 0.8)
	if not multiplayer.is_server(): _request.rpc_id(1)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if multiplayer.is_server():
		_fear_left = maxf(0.0, _fear_left - delta)
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
		var wet: bool = _population.rivers.field_at(player.global_position).x <= 0.0
		if kind in ["shoal", "brook"]:
			radius *= (1.35 if wet and player.velocity.length() > 30 else 0.65)
		if player.stealth.sneaking: radius *= 0.55
		if player.swim > 0: radius *= 1.5 if player.swim == SwimRules.CRAWL else 1.15 ## swimmers churn the water
		if position.distance_to(player.global_position) < radius:
			_threat = player.global_position
			_fear_left = 2.5
			if mode not in [Mode.FLEE, Mode.HOP, Mode.DIVE, Mode.FLY]: _choose()
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

@rpc("any_peer", "call_remote", "reliable")
func _request() -> void:
	if multiplayer.is_server(): _act.rpc_id(multiplayer.get_remote_sender_id(), mode, _start, _end, _curve, _duration, facing, _elapsed, _aux)

## Waterside animals: what they do besides moving (host: the heron's strike frightens fish; every peer: wake ripples and voices).
func _new_life(delta: float) -> void:
	var ratio: float = clampf(_elapsed / _duration, 0.0, 1.0)
	if multiplayer.is_server() and kind == "heron" and mode == Mode.STRIKE and not _hit_done and ratio > 0.55:
		_hit_done = true
		_population.scare_fish(global_position + Vector2.from_angle(facing) * 12.0, 46.0)
		_ripples.add(global_position + Vector2.from_angle(facing) * 10.0, 1.0)
	if _moving and _wake_wait <= 0.0 and kind in ["duck", "heron"] and mode in [Mode.TRAVEL, Mode.FLEE] and _population.rivers.field_at(position).x < 0.0:
		_wake_wait = 0.55 if kind == "duck" else 0.7
		_ripples.add(global_position, 0.22 if kind == "duck" else 0.3)
	if _sound_wait <= 0.0 and _spec.has("sound"):
		_sound_wait = _rng.randf_range(SOUND_COOLDOWN, SOUND_COOLDOWN * 2.2)
		var calls: bool = false
		match kind:
			"frog": calls = _aux == 1 and mode == Mode.REST
			"duck": calls = mode in [Mode.REST, Mode.TRAVEL] and _rng.randf() < 0.5
			"heron": calls = mode in [Mode.FLY] or (mode == Mode.REST and _rng.randf() < 0.15)
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
	_voice.stream = load("res://assets/audio/wildlife/%s_%d.wav" % [String(_spec.sound), _rng.randi() % 2]) as AudioStream
	_voice.pitch_scale = _rng.randf_range(0.92, 1.1) * (1.25 if kind == "duck" and member > 0 and school.begins_with("duckfamily") else 1.0)
	_voice.play()


## Which of the sheet's builds this animal wears (heron/frog by school, duck: drake / hen / duckling).
func _build() -> int:
	match kind:
		"duck":
			if member > 0 and school.begins_with("duckfamily"):
				return 2
			return 1 if school.begins_with("duckfamily") else 0
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
				Mode.REST: return 4 + int(loop * 2.0) % 4 if _aux == 2 else (26 + int(loop * 3.0) % 4 if _aux == 3 else int(loop * 2.5) % 4)
				Mode.TRAVEL, Mode.FLEE: return 8 + int(loop * 4.0) % 8
				Mode.STRIKE: return 16 + mini(5, int(maxf(0.0, ratio - 0.15) / 0.85 * 6.0)) if ratio < 0.72 or _aux == 0 else 22 + int(loop * 4.0) % 4
				Mode.FLY: return 38 + mini(5, int(loop / 0.12)) if loop < 0.7 else (44 + mini(5, int((loop - (_duration - 0.7)) / 0.12)) if loop > _duration - 0.7 else 30 + int(loop * 7.0) % 8)
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
			match mode:
				Mode.REST: return 16 + int(loop * 3.0) % 4 if _aux == 3 else int(loop * 3.0) % 4
				Mode.TRAVEL, Mode.FLEE: return 4 + int(loop * 8.0) % 6
				Mode.DABBLE: return 10 + mini(5, int(ratio * 6.0))
				Mode.FLY: return 28 + mini(5, int(loop / 0.1)) if loop < 0.6 else 20 + int(loop * 14.0) % 8
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
		_sprite.position.y = -roundf(lift)
		z_index = 0 if flying or (kind == "kingfisher") or not wet_here else -6
		_sprite.modulate = Color(0.86, 0.95, 0.95) if kind == "duck" and wet_here and depth_here > 0.0 else Color.WHITE
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
			var roll: float = _rng.randf()
			if roll < 0.2 and here.x < 0.0 and here.y < 0.5:
				var fish: RiverAnimal = _population.nearest_fish(position, 42.0)
				if fish != null:
					var toward: float = (fish.position - position).angle()
					_act.rpc(Mode.STRIKE, position, position, Vector2.ZERO, 1.9, toward, 0.0, 1 if _rng.randf() < 0.5 else 0)
					return
			if roll < 0.5:
				for attempt: int in 14:
					var point: Vector2 = position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, 34.0)
					if _population.valid_route(self, point, Vector2.ZERO):
						_act.rpc(Mode.TRAVEL, position, point, Vector2.ZERO, maxf(0.8, position.distance_to(point) / float(_spec.speed)), (point - position).angle(), 0.0, 0)
						return
			_act.rpc(Mode.REST, position, position, Vector2.ZERO, rest_time, facing + (_rng.randf_range(-0.8, 0.8) if _rng.randf() < 0.4 else 0.0), 0.0, [0, 0, 0, 2, 2, 3][_rng.randi() % 6])
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


func _choose_duck(rest_time: float, here: Vector2) -> void:
	var family: bool = school.begins_with("duckfamily")
	var young: bool = family and member > 0
	if _fear_left > 0.0:
		if family:
			var away: Vector2 = position + (position - _threat).normalized() * 34.0
			for attempt: int in 12:
				var point: Vector2 = away if attempt == 0 else position + (away - position).rotated(_rng.randf_range(-1.6, 1.6)).limit_length(_rng.randf_range(14.0, 36.0))
				if _population.valid_route(self, point, Vector2.ZERO):
					_act.rpc(Mode.FLEE, position, point, Vector2.ZERO, maxf(0.4, position.distance_to(point) / float(_spec.flee_speed)), (point - position).angle(), 0.0, 0)
					return
		else:
			_fly_from_threat(0)
			return
	if young: ## ducklings follow their mother in a loose line
		var mother: RiverAnimal = _population.leader(school)
		if mother != null:
			var spot: Vector2 = mother.position - Vector2.from_angle(mother.facing) * (7.0 + 5.0 * float(member)) + Vector2.from_angle(float(member) * 2.1) * 4.0
			if position.distance_to(spot) > 6.0 and _population.valid_route(self, spot, Vector2.ZERO):
				_act.rpc(Mode.TRAVEL, position, spot, Vector2.ZERO, maxf(0.4, position.distance_to(spot) / (float(_spec.speed) * 1.3)), (spot - position).angle(), 0.0, 0)
				return
		_act.rpc(Mode.REST, position, position, Vector2.ZERO, _rng.randf_range(0.8, 1.6), facing, 0.0, 0)
		return
	var roll: float = _rng.randf()
	if roll < 0.28 and here.y < 0.55:
		_act.rpc(Mode.DABBLE, position, position, Vector2.ZERO, 2.4, facing, 0.0, 0)
		return
	if roll < 0.6:
		for attempt: int in 14:
			var point: Vector2 = position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(12.0, 40.0)
			if _population.valid_route(self, point, Vector2.ZERO):
				_act.rpc(Mode.TRAVEL, position, point, Vector2.ZERO, maxf(0.8, position.distance_to(point) / float(_spec.speed)), (point - position).angle(), 0.0, 0)
				return
	_act.rpc(Mode.REST, position, position, Vector2.ZERO, rest_time, facing, 0.0, 3 if _rng.randf() < 0.3 else 0)


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
