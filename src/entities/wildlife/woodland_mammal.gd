class_name WoodlandMammal
extends CharacterBody2D
## Host-owned ground wildlife. Every species has its own life, gaits and threat response;
## reliable actions carry mood, route, facing and elapsed time atomically to all peers.

enum Mood { REST, FORAGE, WALK, ALERT, FLEE, GROOM, SLEEP, SPECIAL, RETURN, HIDDEN, UNROLL, EMERGE, LISTEN, REAR, SWIPE, PLAY, CHASE, LOWER }

var species: String = "deer":
	set(value):
		species = value
		if is_node_ready():
			_load_species()
var appearance: int = 0:
	set(value):
		appearance = value
		if is_node_ready():
			_load_species()
var family_id: String = ""
var home: Vector2
var facing: float = 0.0
var ambient_event: bool = false
var visit: Vector2 = Vector2.INF ## a visitor of the town (TownCritters, host only): where it goes to sniff, and what it looks at there
var visit_look: Vector2 = Vector2.ZERO
var _visit_stage: int = 0
var _visit_sniffs: int = 0
var _leave_hops: int = 0
var _step_limit: float = INF
var mood: Mood = Mood.REST
var _spec: Dictionary
var _population: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _duration: float = 2.0
var _moving: bool = false
var _start: Vector2
var _end: Vector2
var _sense_left: float = 0.0
var _danger: bool = false
var _threat: Vector2
var _safe_time: float = 0.0
var _alarm_delay: float = -1.0
var _forage_visits: int = 0
var _gait_phase: float = 0.0
var _gait_start: float = 0.0
var _rolling: bool = false
var _visual_facing: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("wild_animals") ## the cursor shrinks to a dot over animals (GameCursor)
	_load_species()
	_population = get_parent().get_parent()
	_rng.seed = hash(name) + hash(family_id)
	_start = global_position
	_end = global_position
	_visual_facing = facing
	add_to_group("woodland_mammals")
	if species == "fox":
		add_to_group("wildlife_hunters")
	if multiplayer.is_server():
		_duration = _range("rest_seconds")
		_sense_left = _rng.randf_range(0.0, float(_spec["sense_interval"]))
	else:
		_request_snapshot.rpc_id(1)


func _load_species() -> void:
	_spec = DataRegistry.get_entry("wildlife", species)
	_sprite.texture = load(String(_spec["texture"])) as Texture2D
	var body: CircleShape2D = CircleShape2D.new()
	body.radius = float(_spec["body_radius"]) * (0.7 if is_fawn() else 1.0)
	($CollisionShape2D as CollisionShape2D).shape = body


func is_fawn() -> bool:
	return species == "deer" and appearance == 2


func _range(key: String) -> float:
	var bounds: Array = _spec[key]
	return _rng.randf_range(float(bounds[0]), float(bounds[1]))


func _rest_hours() -> bool:
	return bool(_spec["nocturnal"]) and TimeManager.night_amount() < 0.4


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if multiplayer.is_server():
		_sense_left -= delta
		if _sense_left <= 0.0:
			_sense_left = float(_spec["sense_interval"])
			_sense()
		_safe_time = 0.0 if _danger else _safe_time + delta
		if _alarm_delay >= 0.0:
			_alarm_delay -= delta
			if _alarm_delay <= 0.0:
				_alarm_delay = -1.0
				_step((global_position - _threat).normalized(), Mood.FLEE)
		if not _moving and (not ambient_event or _danger):
			_think()
	if _moving:
		_advance()


func _process(delta: float) -> void:
	_visual_facing += clampf(angle_difference(_visual_facing, facing), -delta * 7.0, delta * 7.0)
	_sprite.visible = mood != Mood.HIDDEN
	var col: int = int(_elapsed * 2.5) % 4
	match mood:
		Mood.FORAGE:
			if species == "deer":
				# Lower once, graze gently, then raise the head before moving on.
				var remaining: float = _duration - _elapsed
				if _elapsed < 0.6:
					col = 4 + mini(1, int(_elapsed / 0.3))
				elif remaining < 0.6:
					col = 4 if remaining < 0.3 else 5
				else:
					col = 6 + int(_elapsed * 2.0) % 3
			else:
				col = 4 + int(_elapsed * 5.0) % 6
		Mood.WALK, Mood.RETURN, Mood.EMERGE:
			col = 10 + int(_gait_phase * 8.0) % 8
		Mood.ALERT, Mood.LISTEN:
			col = 18 + int(_elapsed * 2.0) % 4
		Mood.FLEE:
			col = 22 + int(_gait_phase * 8.0) % 8
		Mood.GROOM:
			col = 30 + int(_elapsed * 3.0) % 4
		Mood.SLEEP:
			col = 34 + int(_elapsed * 1.4) % 4
		Mood.SPECIAL:
			col = 38 + (mini(5, int(_elapsed / float(_spec["curl_seconds"]) * 6.0)) if species == "hedgehog" else int(_elapsed / _duration * 6.0) % 6)
		Mood.UNROLL:
			col = 43 - mini(5, int(_elapsed / _duration * 6.0))
	var sector: int = posmod(roundi(_visual_facing / (PI / 4.0)), 8)
	_sprite.frame = (clampi(appearance, 0, 2) * 8 + sector) * 44 + col
	_sprite.modulate.a = smoothstep(0.0, 0.7, _elapsed / _duration) if mood == Mood.EMERGE else 1.0
	_sprite.position.y = -roundf(sin(clampf(_elapsed / _duration, 0.0, 1.0) * PI) * float(_spec["pounce_height"])) if species == "fox" and mood == Mood.SPECIAL and _moving else 0.0
	queue_redraw()


func _draw() -> void:
	if mood == Mood.HIDDEN:
		return
	var radius: float = float(_spec.get("body_radius", 4.0)) * (0.7 if is_fawn() else 1.0)
	draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.3, 0.4))
	draw_circle(Vector2.ZERO, radius, Color(0.035, 0.025, 0.065, 0.24))
	draw_set_transform(Vector2.ZERO)
	if species == "badger" and mood == Mood.SPECIAL:
		for i: int in 3:
			var t: float = fposmod(_elapsed * 2.0 + i * 0.3, 1.0)
			draw_rect(Rect2(Vector2((i - 1) * (2.0 + t * 4.0), -2.0 - sin(t * PI) * 4.0).round(), Vector2.ONE), Color("8b7163"))


func _sense() -> void:
	_danger = false
	if mood == Mood.HIDDEN or mood == Mood.EMERGE:
		return
	var nearest: float = INF
	var close: bool = false
	var candidates: Array[Node] = []
	candidates.append_array(Player.all)
	candidates.append_array(get_tree().get_nodes_in_group("predators"))
	if species in ["deer", "hedgehog"]:
		candidates.append_array(get_tree().get_nodes_in_group("wildlife_hunters"))
	for node: Node in candidates:
		var actor: Node2D = node as Node2D
		if actor == null:
			continue
		var alert: float = float(_spec["alert_range"])
		var flee: float = float(_spec["flee_range"])
		if mood == Mood.FLEE:
			alert = float(_spec["safe_range"])
		var noisy: bool = false
		if actor is Player:
			var player: Player = actor as Player
			if player.health.current <= 0.0:
				continue
			var calm: float = TownManager.calm_at(get_tree(), global_position) ## used to the town's people
			alert *= calm
			flee *= calm
			if player.stealth.sneaking:
				alert *= float(_spec["sneak_multiplier"])
				flee *= float(_spec["sneak_multiplier"])
			if player.sprinting:
				alert *= float(_spec["sprint_multiplier"])
				flee *= float(_spec["sprint_multiplier"])
			noisy = player.attack.is_swinging() and global_position.distance_to(actor.global_position) < float(_spec["swing_range"]) * player.attack.noise_scale()
		elif node.is_in_group("wildlife_hunters"):
			alert = 95.0 if is_fawn() else 65.0
			flee = 55.0 if is_fawn() else 25.0
		else:
			var health: HealthComponent = actor.get_node_or_null("HealthComponent") as HealthComponent
			if health != null and health.current <= 0.0:
				continue
		var distance: float = global_position.distance_to(actor.global_position)
		if distance > alert and not noisy:
			continue
		var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, actor.global_position, 1)
		if not noisy and not get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		_danger = true
		close = close or noisy or distance < flee
		if distance < nearest:
			nearest = distance
			_threat = actor.global_position
	if not _danger:
		return
	if species == "hedgehog":
		if close and mood != Mood.SPECIAL:
			var already_curled: bool = mood == Mood.SLEEP
			_issue(Mood.SPECIAL, float(_spec["curl_seconds"]), INF, float(_spec["curl_seconds"]) if already_curled else 0.0)
		elif not close and mood not in [Mood.SPECIAL, Mood.SLEEP]:
			_issue(Mood.ALERT, 1.0, (_threat - global_position).angle())
	elif close:
		if mood != Mood.FLEE:
			_step((global_position - _threat).normalized(), Mood.FLEE)
			if species == "deer":
				_alarm_family()
	elif not _moving and mood not in [Mood.ALERT, Mood.FLEE] and not (species == "hedgehog" and mood == Mood.SPECIAL):
		_issue(Mood.ALERT, 1.3, (_threat - global_position).angle())


func _adult() -> WoodlandMammal:
	for node: Node in get_tree().get_nodes_in_group("woodland_mammals"):
		var animal: WoodlandMammal = node as WoodlandMammal
		if animal != self and animal.species == "deer" and animal.family_id == family_id and animal.appearance == 0:
			return animal
	return null


func _alarm_family() -> void:
	for node: Node in get_tree().get_nodes_in_group("woodland_mammals"):
		var other: WoodlandMammal = node as WoodlandMammal
		if other != self and other.species == "deer" and other.family_id == family_id and other.mood != Mood.FLEE and other._alarm_delay < 0.0:
			other._threat = _threat
			other._issue(Mood.ALERT, 0.6)
			other._alarm_delay = _rng.randf_range(0.12, 0.4)


func _think() -> void:
	if _alarm_delay >= 0.0:
		return
	if species == "hedgehog" and mood == Mood.SPECIAL:
		if not _danger and _safe_time >= float(_spec["safe_seconds"]) and _elapsed >= _duration:
			_issue(Mood.UNROLL, float(_spec["uncurl_seconds"]))
		return
	if _danger and mood != Mood.FLEE:
		return
	if mood == Mood.FLEE and visit.is_finite(): ## scared off: it gives the visit up and leaves
		visit = Vector2.INF
		_leave_hops = 3
	if mood == Mood.FLEE:
		if _safe_time >= float(_spec["safe_seconds"]):
			_issue(Mood.ALERT, 1.5)
		elif _elapsed >= _duration:
			_step((global_position - _threat).normalized(), Mood.FLEE)
		return
	if not _rest_hours() and mood == Mood.HIDDEN:
		_move_action(Mood.EMERGE, global_position + Vector2(0, 9), float(_spec["emerge_seconds"]))
		return
	if not _rest_hours() and mood == Mood.SLEEP:
		_issue(Mood.UNROLL, float(_spec["uncurl_seconds"])) if species == "hedgehog" else _issue(Mood.ALERT, 1.0)
		return
	if _elapsed < _duration:
		return
	if _rest_hours():
		var home_loaded: bool = bool(_population.call("home_loaded", home)) if _population.has_method("home_loaded") else true
		if home_loaded and global_position.distance_to(home) > 8.0:
			_step((home - global_position).normalized(), Mood.RETURN)
		elif species == "badger" and home_loaded:
			_issue(Mood.HIDDEN, _range("sleep_seconds"))
		elif species == "fox" and mood == Mood.SLEEP and _rng.randf() < 0.2:
			_issue(Mood.GROOM, _range("groom_seconds"))
		else:
			_issue(Mood.SLEEP, _range("sleep_seconds"))
		return
	if mood == Mood.HIDDEN:
		_move_action(Mood.EMERGE, global_position + Vector2(0, 9), float(_spec["emerge_seconds"]))
		return
	if species == "deer":
		_deer_life()
	elif species == "badger":
		_badger_life()
	elif species == "fox":
		_fox_life()
	else:
		_hedgehog_life()


func _deer_life() -> void:
	if is_fawn():
		var parent: WoodlandMammal = _adult()
		if parent != null and global_position.distance_to(parent.global_position) > float(_spec["family_range"]):
			_step((parent.global_position + Vector2(15, 12) - global_position).normalized(), Mood.WALK)
			return
	var roll: float = _rng.randf()
	if roll < 0.52:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	elif roll < 0.78:
		_roam()
	elif roll < 0.9:
		_issue(Mood.ALERT, _range("rest_seconds"), facing + _rng.randf_range(-0.6, 0.6))
	else:
		_issue(Mood.GROOM, _range("groom_seconds"))


func _badger_life() -> void:
	if mood == Mood.FORAGE:
		_forage_visits += 1
		if _forage_visits % 2 == 0:
			_issue(Mood.SPECIAL, _range("dig_seconds"))
			return
	var roll: float = _rng.randf()
	if roll < 0.1:
		_issue(Mood.GROOM, _range("groom_seconds"))
	elif roll < 0.65:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	else:
		_roam()


func _fox_life() -> void:
	if _leave_hops > 0: ## on its way out of the town
		_leave_hops -= 1
		_step((global_position - (visit_look if visit_look != Vector2.ZERO else global_position - Vector2.from_angle(facing))).normalized(), Mood.WALK)
		return
	if visit.is_finite():
		_visit_life()
		return
	if mood == Mood.LISTEN:
		var point: Vector2 = global_position + Vector2.from_angle(facing) * _range("pounce_distance")
		if _can_step(point) and not test_move(global_transform, point - global_position):
			_move_action(Mood.SPECIAL, point, float(_spec["pounce_seconds"]))
			return
	if mood == Mood.SPECIAL:
		_issue(Mood.FORAGE, _range("forage_seconds"))
		return
	var roll: float = _rng.randf()
	if roll < 0.38:
		var target: Vector2 = global_position + Vector2.from_angle(facing) * 30.0
		for node: Node in get_tree().get_nodes_in_group("wildlife"):
			if node is WildRabbit and global_position.distance_to((node as Node2D).global_position) < 100.0:
				target = (node as Node2D).global_position
				break
		_issue(Mood.LISTEN, _range("listen_seconds"), (target - global_position).angle())
	elif roll < 0.78:
		_roam()
	else:
		_issue(Mood.FORAGE, _range("forage_seconds"))


## A visit to the town: walk up to the spot (in hops that never overshoot it), then sniff along the stockpile: ground, a listening pause, ground again, looking at it; then off.
func _visit_life() -> void:
	var to: Vector2 = visit - global_position
	if _visit_stage == 0:
		if to.length() > 14.0:
			_step_limit = to.length() ## a hop that never overshoots the spot
			_step(to.normalized(), Mood.WALK)
			_step_limit = INF
			return
		_visit_stage = 1
	if _visit_stage == 1 and _visit_sniffs < 4:
		_visit_sniffs += 1
		var look: float = (visit_look - global_position).angle() + (0.0 if _visit_sniffs % 2 == 1 else _rng.randf_range(-0.5, 0.5))
		_issue(Mood.LISTEN if _visit_sniffs == 3 else Mood.FORAGE, _range("forage_seconds") * (0.7 if _visit_sniffs == 3 else 1.2), look)
		return
	visit = Vector2.INF
	_leave_hops = 5


func _hedgehog_life() -> void:
	var roll: float = _rng.randf()
	if roll < 0.15:
		_issue(Mood.REST, _range("rest_seconds"))
	elif roll < 0.75:
		_issue(Mood.FORAGE, _range("forage_seconds"))
	else:
		_roam()


func _roam() -> void:
	var direction: Vector2 = Vector2.from_angle(facing + _rng.randf_range(-1.15, 1.15))
	if global_position.distance_to(home) > float(_spec["home_radius"]):
		direction = (home - global_position).normalized()
	_step(direction, Mood.WALK)


func _can_step(point: Vector2) -> bool:
	if _population.has_method("can_stand"):
		return bool(_population.call("can_stand", point, self))
	return Terrain.relief == null or Terrain.relief.flat_around(point, float(_spec["body_radius"]))


func _step(direction: Vector2, action: Mood) -> void:
	var fleeing: bool = action == Mood.FLEE
	var distance: float = _range("run_distance" if fleeing else "walk_distance")
	var speed: float = float(_spec["run_speed"] if fleeing else _spec["walk_speed"])
	if is_fawn():
		speed *= float(_spec["fawn_speed_factor"])
		var parent: WoodlandMammal = _adult()
		if fleeing and parent != null and global_position.distance_to(parent.global_position) > 35.0:
			direction = ((parent._end if parent._moving else parent.global_position) - global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	for fraction: float in [1.0, 0.6, 0.3]:
		for angle: float in [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.65, -1.65, 2.1, -2.1, PI]:
			var step: Vector2 = direction.rotated(angle) * distance * fraction
			if action == Mood.RETURN:
				step = step.limit_length(global_position.distance_to(home))
			var point: Vector2 = global_position + step
			if not test_move(global_transform, step) and _can_step(point) and _can_step(global_position + step * 0.5):
				var rolling: bool = _moving and mood == action and action in [Mood.FLEE, Mood.RETURN, Mood.CHASE]
				var ramp_in: float = 0.0 if rolling else float(_spec["motion_ramp"])
				var ramp_out: float = 0.0 if fleeing or (action == Mood.RETURN and point.distance_to(home) > 8.0) else float(_spec["motion_ramp"])
				_move_action(action, point, maxf(0.2, step.length() / speed / (1.0 - (ramp_in + ramp_out) * 0.5)))
				return
	_issue(Mood.ALERT if fleeing else Mood.REST, 0.6)


func _issue(action: Mood, duration: float, direction: float = INF, elapsed: float = 0.0) -> void:
	_command.rpc(action, duration, facing if is_inf(direction) else direction, global_position, global_position, elapsed, _gait_phase, false)


func _move_action(action: Mood, point: Vector2, duration: float) -> void:
	_command.rpc(action, duration, (point - global_position).angle(), global_position, point, 0.0, _gait_phase, _moving and mood == action and action in [Mood.FLEE, Mood.RETURN, Mood.CHASE])


@rpc("authority", "call_local", "reliable")
func _command(action: int, duration: float, direction: float, start: Vector2, end: Vector2, elapsed: float, gait: float = 0.0, rolling: bool = false) -> void:
	mood = action as Mood
	_duration = maxf(0.1, duration)
	_elapsed = elapsed
	facing = direction
	_start = start
	_end = end
	_gait_start = gait
	_gait_phase = gait
	_rolling = rolling
	_moving = start.distance_squared_to(end) > 0.01 and mood in [Mood.WALK, Mood.FLEE, Mood.RETURN, Mood.SPECIAL, Mood.EMERGE, Mood.CHASE]
	if not _moving:
		global_position = end


func _route_progress(t: float) -> float:
	# Integral of a smooth velocity ramp, with constant cruise in the middle.
	# Flee/return routes carry cruise through their next segment without a stop.
	if mood == Mood.SPECIAL:
		return smoothstep(0.0, 1.0, t)
	var ramp_in: float = 0.0 if _rolling else float(_spec["motion_ramp"])
	var ramp_out: float = 0.0 if mood in [Mood.FLEE, Mood.CHASE] or (mood == Mood.RETURN and _end.distance_to(home) > 8.0) else float(_spec["motion_ramp"])
	var area: float = 1.0 - (ramp_in + ramp_out) * 0.5
	if ramp_in > 0.0 and t < ramp_in:
		var u: float = t / ramp_in
		return ramp_in * (u * u * u - 0.5 * u * u * u * u) / area
	if ramp_out > 0.0 and t > 1.0 - ramp_out:
		var u: float = (1.0 - t) / ramp_out
		return 1.0 - ramp_out * (u * u * u - 0.5 * u * u * u * u) / area
	return (t - ramp_in * 0.5) / area


func _advance() -> void:
	var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
	var point: Vector2 = _start.lerp(_end, _route_progress(t))
	if multiplayer.is_server():
		var hit: KinematicCollision2D = move_and_collide(point - global_position)
		_gait_phase = _gait_start + _start.distance_to(global_position) / float(_spec["run_stride"] if mood in [Mood.FLEE, Mood.CHASE] else _spec["walk_stride"])
		if hit == null and t >= 1.0:
			if mood == Mood.FLEE and _safe_time < float(_spec["safe_seconds"]):
				_step((global_position - _threat).normalized(), Mood.FLEE)
				return
			if mood == Mood.RETURN and _rest_hours() and global_position.distance_to(home) > 8.0:
				_step((home - global_position).normalized(), Mood.RETURN)
				return
		if hit != null or t >= 1.0:
			_settle.rpc(global_position, mood)
	else:
		global_position = point
		_gait_phase = _gait_start + _start.distance_to(global_position) / float(_spec["run_stride"] if mood in [Mood.FLEE, Mood.CHASE] else _spec["walk_stride"])
		if t >= 1.0:
			_moving = false


@rpc("authority", "call_local", "reliable")
func _settle(at: Vector2, previous: int) -> void:
	global_position = at
	_start = at
	_end = at
	_moving = false
	_elapsed = 0.0
	mood = previous as Mood if previous in [Mood.FLEE, Mood.RETURN, Mood.SPECIAL, Mood.CHASE] else Mood.REST
	_duration = 0.7 if mood == Mood.SPECIAL else 0.0


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server():
		_command.rpc_id(multiplayer.get_remote_sender_id(), mood, _duration, facing, _start, _end, _elapsed, _gait_start, _rolling)
