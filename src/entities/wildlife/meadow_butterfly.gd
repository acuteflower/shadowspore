class_name MeadowButterfly
extends Node2D
## Flower-bound daytime life. Only the host chooses flowers; all peers replay the same curved
## flight. No light emission, collision damage, item consumption or free-floating particle swarm.

enum State { FLY, FEED, REST }
var appearance: int = 0
var home: Vector2
var flowers: Array[Vector2] = [] ## host-only targets, actual flower tiles supplied by the world
var state: State = State.FEED
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spec: Dictionary
var _elapsed: float = 0.0
var _duration: float = 2.0
var _start: Vector2
var _end: Vector2
var _bend: Vector2
var _height: float = 5.0
var _alt: float = 4.0
var _sense_left: float = 0.0
var _facing: float = 0.0

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("wild_animals") ## the cursor shrinks to a dot over animals (GameCursor)
	_spec = DataRegistry.get_entry("wildlife", "butterfly")
	_rng.seed = hash(name) + int(home.x) * 13 + int(home.y) * 7
	_start = global_position
	_end = global_position
	if multiplayer.is_server():
		_duration = _range("feed_seconds")
	else:
		_request_snapshot.rpc_id(1)


func _range(key: String) -> float:
	var bounds: Array = _spec[key]
	return _rng.randf_range(float(bounds[0]), float(bounds[1]))


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if multiplayer.is_server():
		_sense_left -= delta
		if _sense_left <= 0.0:
			_sense_left = 0.25
			if state != State.FLY:
				for player: Player in Player.all:
					if player.health.current > 0.0 and global_position.distance_to(player.global_position) < (float(_spec["swing_range"]) if player.attack.is_swinging() else float(_spec["scatter_range"])):
						_visit(true, player.global_position)
						break
	if state == State.FLY:
		var t: float = clampf(_elapsed / _duration, 0.0, 1.0)
		var p: float = smoothstep(0.0, 1.0, t)
		var flutter: Vector2 = (_end - _start).orthogonal().normalized() * sin(t * TAU * 2.0) * sin(t * PI) * 2.0
		global_position = _start.lerp(_end, p) + _bend * (4.0 * p * (1.0 - p)) + flutter
		_alt = 4.0 + sin(t * PI) * _height + sin(t * TAU * 2.0) * sin(t * PI) * 1.0
		var tangent: Vector2 = _end - _start + _bend * (4.0 * (1.0 - 2.0 * p))
		_facing = tangent.angle()
		if multiplayer.is_server() and t >= 1.0:
			_act.rpc(State.REST if TimeManager.night_amount() > 0.6 or WeatherManager.sky_wet() else State.FEED, _range("feed_seconds"), _end, _end, Vector2.ZERO, 4.0, 0.0)
	elif multiplayer.is_server():
		if state == State.REST and TimeManager.night_amount() < 0.5 and not WeatherManager.sky_wet():
			_act.rpc(State.FEED, _range("feed_seconds"), global_position, global_position, Vector2.ZERO, 4.0, 0.0)
		elif _elapsed >= _duration:
			if TimeManager.night_amount() > 0.6 or WeatherManager.sky_wet(): ## rain: wings folded under a leaf
				_act.rpc(State.REST, _range("rest_seconds"), global_position, global_position, Vector2.ZERO, 4.0, 0.0)
			else:
				_visit(false)


func _process(_delta: float) -> void:
	var col: int = int(_elapsed * 22.0) % 7 if state == State.FLY else (7 if state == State.REST else [0, 1, 0, 6][int(_elapsed * 1.3) % 4])
	var sector: int = posmod(roundi(_facing / (PI / 4.0)), 8)
	_sprite.frame = (clampi(appearance, 0, 3) * 8 + sector) * 8 + col
	_sprite.position.y = -roundf(_alt)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 1.5, Color(0.04, 0.03, 0.07, 0.15))


func _visit(scatter: bool, danger: Vector2 = Vector2.ZERO) -> void:
	if flowers.is_empty():
		return
	var choices: Array[Vector2] = []
	for point: Vector2 in flowers:
		if point.distance_to(home) <= float(_spec["patch_radius"]) and point.distance_to(global_position) > 6.0:
			choices.append(point)
	if choices.is_empty():
		return
	var goal: Vector2 = choices[_rng.randi_range(0, choices.size() - 1)]
	if scatter:
		for point: Vector2 in choices:
			if point.distance_to(danger) > goal.distance_to(danger):
				goal = point
	var direction: Vector2 = goal - global_position
	var bend: Vector2 = direction.orthogonal().normalized() * _rng.randf_range(-12.0, 12.0)
	_act.rpc(State.FLY, 0.8 if scatter else _range("flight_seconds"), global_position, goal, bend, 12.0 if scatter else _range("flight_height"), 0.0)


@rpc("authority", "call_local", "reliable")
func _act(next: int, duration: float, start: Vector2, end: Vector2, bend: Vector2, height: float, elapsed: float) -> void:
	state = next as State
	_duration = maxf(0.1, duration)
	_elapsed = elapsed
	_start = start
	_end = end
	_bend = bend
	_height = height
	if state != State.FLY:
		global_position = end
		_alt = 4.0


@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server():
		_act.rpc_id(multiplayer.get_remote_sender_id(), state, _duration, _start, _end, _bend, _height, _elapsed)
