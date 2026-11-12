class_name InteriorCrow
extends Node2D
## A crow on the sill of a room's window (data/interiors.json `crows`: {perch, exit}, built by `Interior`). It sits there, looks about, preens, now and then calls. When somebody
## comes near it looks at them, caws and flies out through the window (the wall hides it as it passes the opening: while it is outside the plane it sorts behind the wall); once everybody
## has been away for a few seconds it flies back in and lands on the sill. Purely cosmetic: every peer runs its own, nothing is synced. Frames of the wild crow's sheet
## (tools/art_corvid.py): idle 0-3, preen 16-21, watch 22-25, call 26-29, flight 30-37, landing 38-43, takeoff 44-49; rows = build * 8 + facing (E SE S SW W NW N NE).

signal landing ## the flight in has come to the landing frames (RoomIntro plays the wing beats)
signal landed

enum State { PERCHED, ALERT, LEAVING, AWAY, RETURNING }

const SHEET: Texture2D = preload("res://assets/wildlife/corvid.png")
const CALLS: Array[AudioStream] = [preload("res://assets/audio/wildlife/crow_0.wav"), preload("res://assets/audio/wildlife/crow_1.wav")]
const SCARE_RADIUS: float = 66.0 ## px from the perch: somebody this close and it goes
const CALM_RADIUS: float = 104.0 ## px: everybody farther than this for `_wait` seconds and it comes back
const ACTIVE_RANGE: float = 600.0 ## px: with nobody near, the crow is not animated at all
const ALERT_TIME: float = 0.4
const FLIGHT_TIME: float = 1.5
const SOUTH: int = 2
const NORTH: int = 6
const SIDE: int = 3 ## south-west: it sits on the sill with its head turned into the room, so the bill and the eye show (from the front it is only a dark oval)

var scripted: bool = false ## a cutscene flies it (RoomIntro): it neither flees nor comes back by itself
var _flight: float = FLIGHT_TIME
var _announced: bool = false
var _perch: Vector2 = Vector2.ZERO
var _exit: Vector2 = Vector2.ZERO
var _state: State = State.PERCHED
var _t: float = 0.0
var _wait: float = 0.0
var _build: int = 0
var _sector: int = SIDE
var _look: int = SIDE
var _behaviour: int = 0 ## 0 sits, 1 looks about, 2 preens, 3 calls
var _behaviour_left: float = 1.0
var _threat: Vector2 = Vector2.INF
var _sprite: Sprite2D
var _voice: AudioStreamPlayer2D


func setup(perch: Vector2, exit_point: Vector2) -> void:
	_perch = perch
	_exit = exit_point
	position = perch


func _ready() -> void:
	_build = 0 ## the same crow every time: the great one of the opening is drawn in its plumage
	_sprite = Sprite2D.new()
	_sprite.texture = SHEET
	_sprite.hframes = 62
	_sprite.vframes = 48
	_sprite.centered = false
	_sprite.offset = Vector2(-24, -35)
	add_child(_sprite)
	_voice = AudioStreamPlayer2D.new()
	_voice.volume_db = -21.0
	_voice.max_distance = 400.0
	_voice.position = Vector2(0, -7)
	add_child(_voice)
	_show(0)


func _draw() -> void:
	if _state == State.PERCHED or _state == State.ALERT:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, 4.5, Color(0.03, 0.025, 0.07, 0.3))


func _process(delta: float) -> void:
	_threat = _nearest()
	var gap: float = INF if _threat == Vector2.INF else _threat.distance_to(_home())
	if gap > ACTIVE_RANGE:
		return
	_t += delta
	match _state:
		State.PERCHED:
			_sit(delta, gap)
		State.ALERT:
			_look = 3 if _threat.x < _home().x - 6.0 else (1 if _threat.x > _home().x + 6.0 else SIDE) ## towards whoever is coming
			_show(22 + int(_t * 6.0) % 4, _look)
			if _t >= ALERT_TIME:
				_voice.stream = CALLS[randi() % CALLS.size()]
				_voice.pitch_scale = randf_range(0.95, 1.12)
				_voice.play()
				_go(State.LEAVING)
		State.LEAVING:
			var f: float = _t / _flight
			if f >= 1.0:
				_go(State.AWAY)
				_wait = randf_range(4.0, 9.0)
				_sprite.visible = false
				return
			position = _perch.lerp(_exit, f * f)
			_show(44 + mini(5, int(f / 0.2 * 6.0)) if f < 0.2 else 30 + int(_t * 10.0) % 8, NORTH)
		State.AWAY:
			if not scripted and gap > CALM_RADIUS:
				_wait -= delta
				if _wait <= 0.0:
					position = _exit
					_sprite.visible = true
					_announced = false
					_go(State.RETURNING)
		State.RETURNING:
			var f: float = _t / _flight
			if f > 0.62 and not _announced:
				_announced = true
				landing.emit()
			if f >= 1.0:
				position = _perch
				_go(State.PERCHED)
				_behaviour_left = 1.0
				_flight = FLIGHT_TIME
				landed.emit()
				return
			position = _exit.lerp(_perch, 1.0 - (1.0 - f) * (1.0 - f))
			_show(38 + mini(5, int((f - 0.62) / 0.38 * 6.0)) if f > 0.62 else 30 + int(_t * 10.0) % 8, SIDE if f > 0.5 else SOUTH)
	## in flight it is outside the wall's plane: behind the wall, seen only through the opening (wings wider than the window are cut by its frame); on the sill and at takeoff / landing it is in front
	z_index = -6 if (_state == State.LEAVING and _t > 0.12) or (_state == State.RETURNING and _t < _flight * 0.93) else 0


## The opening of the room: the crow is not on its sill yet (the great one has just flown past).
func hide_for_intro() -> void:
	scripted = true
	_go(State.AWAY)
	_sprite.visible = false


## The small crow comes in through the window and lands on the sill in `seconds`.
func fly_in(seconds: float) -> void:
	_flight = seconds
	_announced = false
	position = _exit
	_sprite.visible = true
	_go(State.RETURNING)


func _go(state: State) -> void:
	_state = state
	_t = 0.0
	queue_redraw()


func _home() -> Vector2:
	return (get_parent() as Node2D).to_global(_perch)


## The nearest player's position, or Vector2.INF without players.
func _nearest() -> Vector2:
	var best: Vector2 = Vector2.INF
	var best_d: float = INF
	for player: Player in Player.all:
		if not is_instance_valid(player):
			continue
		var d: float = player.global_position.distance_squared_to(_home())
		if d < best_d:
			best_d = d
			best = player.global_position
	return best


func _sit(delta: float, gap: float) -> void:
	if gap < SCARE_RADIUS and _t > 0.6 and not scripted:
		_go(State.ALERT)
		return
	_behaviour_left -= delta
	if _behaviour_left <= 0.0:
		var roll: float = randf()
		_behaviour = 0 if roll < 0.45 else (1 if roll < 0.7 else (2 if roll < 0.9 else 3))
		var spans: Array[float] = [randf_range(1.5, 3.5), randf_range(2.0, 4.0), randf_range(2.0, 3.5), 0.8]
		_behaviour_left = spans[_behaviour]
		var looks: Array[int] = [SIDE]
		if _behaviour == 1:
			looks = [3, 3, 1, SOUTH]
		elif _behaviour == 2:
			looks = [SIDE, 1, 3]
		_look = looks[randi() % looks.size()]
		if _behaviour == 3 and randf() < 0.6:
			_voice.stream = CALLS[randi() % CALLS.size()]
			_voice.pitch_scale = randf_range(0.95, 1.12)
			_voice.play()
	var col: int = int(_t * 2.5) % 4
	match _behaviour:
		1:
			col = 22 + int(_t * 2.2) % 4
		2:
			col = 16 + int(_t * 4.5) % 6
		3:
			col = 26 + int(_t * 10.0) % 4
	_show(col, _look)


func _show(col: int, sector: int = SIDE) -> void:
	_sector = sector
	_sprite.frame = (_build * 8 + sector) * 62 + col
