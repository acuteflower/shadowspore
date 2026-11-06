class_name WildMeadowBird
extends WildCorvid
## Species-specific lives over the established shared flight/perch/network controller.
## Owl: daylight sleep, listening pauses and low nocturnal glides. Hoopoe: probe, crest display,
## short ground steps and a buoyant flight; neither joins corvid watch rotations.


func _init() -> void:
	species = "owl"


func _rest_time() -> bool:
	if species == "owl":
		return TimeManager.night_amount() < float(_spec["awake_threshold"])
	return super._rest_time()


func _process(delta: float) -> void:
	super._process(delta)
	var col: int = _sprite.frame % 50
	if species == "owl":
		if state == State.ROOST and _rest_time():
			col = int(_elapsed * 1.2) % 4
		elif state in [State.IDLE, State.ROOST]:
			col = 22 + int(_elapsed * 0.8) % 4
	elif species == "hoopoe" and state == State.ROOST:
		col = int(_elapsed * 1.4) % 4
	elif species == "hoopoe" and state == State.WATCH and _call_pose <= 0.0:
		# A quick fan-out followed by a partial fold, rather than endlessly flashing the crest.
		col = 22 + mini(3, int(_elapsed * 6.0))
	_sprite.frame = (_sprite.frame / 50) * 50 + col


func _preferred_cruise(panic: bool, goal_height: float) -> float:
	if species == "owl" and not panic and not _rest_time() and _height <= 1.0 and goal_height <= 1.0:
		return float(_spec["night_flight_height"])
	return super._preferred_cruise(panic, goal_height)


func _advance() -> void:
	super._advance()
	if species == "hoopoe" and _moving and state == State.FLY:
		var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
		_height += sin(_elapsed * TAU * float(_spec["flight_bob_hz"])) * float(_spec["flight_bob"]) * sin(t * PI)


func _think() -> void:
	if _panic_delay >= 0.0:
		return
	if _danger or _caution_left > 0.0:
		super._think()
		return
	if species == "owl":
		_owl_life()
	else:
		_hoopoe_life()


func _owl_life() -> void:
	if _rest_time():
		if state in [State.ROOST, State.WATCH] and _elapsed < _duration:
			return
		if _perch_path.is_empty() and _take_wing(false):
			return
		_set_mood(State.ROOST, _range("sleep_seconds"))
		return
	# Twilight wakes a sleeping owl immediately, without waiting for its sleep timer to run out.
	if state == State.ROOST:
		_set_mood(State.PECK, _range("listen_seconds"))
		return
	if _elapsed < _duration:
		return
	if state == State.PECK:
		if _take_wing(false, false, _rng.randf() < 0.5):
			return
	if _rng.randf() < 0.22:
		_set_mood(State.PREEN, _range("preen_seconds"))
	else:
		# PECK uses the owl's head-tilt/listening frames, never a grass-pecking animation.
		_set_mood(State.PECK, _range("listen_seconds"))


func _hoopoe_life() -> void:
	if _rest_time():
		super._think()
		return
	if _elapsed < _duration:
		return
	if not _perch_path.is_empty():
		if not _take_wing(false, false, true):
			_set_mood(State.PREEN, _range("preen_seconds"))
		return
	for node: Node in get_tree().get_nodes_in_group("corvids"):
		var bird: WildCorvid = node as WildCorvid
		if bird != self and bird.species in ["crow", "raven"] and bird.state != State.FLY and bird._height < 1.0 and bird.global_position.distance_to(global_position) < float(_spec["personal_space"]) * 1.4:
			_walk((global_position - bird.global_position).normalized())
			return
	var roll: float = _rng.randf()
	if state == State.PECK and roll < 0.6:
		_walk(Vector2.from_angle(_rng.randf() * TAU))
	elif roll < 0.09 and _take_wing(false, false, true):
		return
	elif roll < 0.25:
		_set_mood(State.WATCH, 1.2)
	elif roll < 0.82:
		_set_mood(State.PECK, _range("peck_seconds"))
	else:
		_set_mood(State.PREEN, _range("preen_seconds"))


func hear_alarm(source: Vector2, rally: Vector2 = Vector2.INF) -> void:
	if species == "owl" and _rest_time():
		if multiplayer.is_server() and state != State.FLY:
			_threat = source
			_set_mood(State.WATCH, _range("listen_seconds"))
		return
	super.hear_alarm(source, rally)


func _request_call(alarm: bool) -> void:
	if species == "owl" and _rest_time() and state == State.ROOST and not alarm:
		_call_left = _range("call_seconds") * 3.0
		return
	super._request_call(alarm)
