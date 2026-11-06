class_name KnightWalkScene
extends Node
## Story step `follow_knight` (event `follow:knight`, started when the meeting is over or by a save that stopped there): the knight walks back to the hut and she follows,
## free to steer. He finds his way with the same `EnemyNavigation` the enemies use (short legs towards the hut, so only loaded ground is asked for), at a pace that
## suits her (a wounded Ellie is slower), and waits when she falls behind (a call now and then). Along the way the speech box lines `walk_a` .. `walk_d` play at fixed
## shares of the route. At the hut he stands by the fire; when she comes up the lines `walk_end` play and the flag `knight_arrived` ends the step. Solo / host only.

const LEGS: float = 190.0 ## px: how far ahead of him the next waypoint is asked for
const WAIT_FAR: float = 150.0 ## he stops when she is farther than this ...
const GO_NEAR: float = 95.0 ## ... and walks on when she is nearer than this
const ARRIVE: float = 26.0
const NAV: Dictionary = {"cell_size": 12, "nodes_per_frame": 72, "usec_per_frame": 1600, "max_nodes": 5200, "search_margin": 272, "target_repath_distance": 24,
		"refresh_seconds": 2.5, "retry_seconds": 0.5, "climb_penalty": 135}
const BARKS: Array[Array] = [[0.1, "walk_a"], [0.36, "walk_b"], [0.6, "walk_c"], [0.82, "walk_d"]]
const WAITS: Array[String] = ["walk_wait_a", "walk_wait_b", "walk_wait_c"]

var _player: Player
var _quarry: Quarry
var _level: Node2D
var _knight: Adventurer
var _walker: CharacterBody2D
var _nav: EnemyNavigation
var _goal: Vector2
var _leg: Vector2 = Vector2.INF
var _total: float = 1.0
var _bark: int = 0
var _waiting: bool = false
var _wait_time: float = 0.0
var _wait_calls: int = 0
var _stuck: float = 0.0
var _best: float = INF
var _clip: String = ""
var _sector: int = -1
var _arrived: bool = false
var _ending: bool = false


func start(player: Player, quarry: Quarry, hut: Hut) -> void:
	_player = player
	_quarry = quarry
	_level = quarry.get_parent() as Node2D
	_knight = quarry.knight
	_goal = _spot_by_fire(hut)
	quarry.hand_over_knight(_level)
	quarry.show_pick(true)
	_walker = CharacterBody2D.new()
	_walker.collision_layer = 0
	_walker.collision_mask = 1
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	_walker.add_child(shape)
	_nav = EnemyNavigation.new()
	_walker.add_child(_nav)
	_walker.global_position = _knight.global_position
	_level.add_child(_walker)
	_nav.configure(_walker, shape, NAV, Callable(_level, "navigation_floor"))
	_total = maxf(_knight.global_position.distance_to(_goal), 1.0)
	if _player.global_position.distance_to(_knight.global_position) > 320.0: ## a save that was loaded far away: he is already there
		_walker.global_position = _goal
		_knight.global_position = _goal
		_arrive()


## A free spot near the door where the fire is (he waits beside it).
func _spot_by_fire(hut: Hut) -> Vector2:
	return hut.exit_position + Vector2(-26.0, 22.0)


func _move_knight_to(point: Vector2) -> void:
	_knight.global_position = point
	_quarry.sync_knight_body()


func _speed() -> float:
	return _player.max_speed * (Player.WOUND_SPEED if _player.wounded else 1.0) * 0.92


func _play(clip: String, toward: Vector2) -> void:
	var sector: int = Adventurer.sector_of(toward) if toward != Vector2.ZERO else _sector
	if clip != _clip:
		_clip = clip
		_knight.play(clip, toward)
	elif sector != _sector:
		_knight.face(toward) ## keep the current stride phase when changing direction
	_sector = sector


func _physics_process(delta: float) -> void:
	if _ending or not is_instance_valid(_player):
		return
	if _arrived:
		_at_the_fire()
		return
	var to_her: Vector2 = _player.global_position - _knight.global_position
	if _waiting and to_her.length() < GO_NEAR:
		_waiting = false
	elif not _waiting and to_her.length() > WAIT_FAR:
		_waiting = true
		_wait_time = 0.0
	if _waiting:
		_play("stand", to_her)
		_wait_time += delta
		if _wait_time > 7.0 and _wait_calls < WAITS.size() * 3:
			_wait_time = 0.0
			_say(WAITS[_wait_calls % WAITS.size()])
			_wait_calls += 1
		return
	_barks()
	if _knight.global_position.distance_to(_goal) < ARRIVE:
		_arrive()
		return
	_steer(delta)


func _barks() -> void:
	if _bark >= BARKS.size():
		return
	var done: float = 1.0 - _knight.global_position.distance_to(_goal) / _total
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if done >= float(BARKS[_bark][0]) and box != null and not box.is_speaking():
		_say(String(BARKS[_bark][1]))
		_bark += 1


func _say(id: String) -> void:
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.play(id)


func _steer(delta: float) -> void:
	var at: Vector2 = _walker.global_position
	if _leg == Vector2.INF or at.distance_to(_leg) < 14.0:
		_leg = _next_leg(at)
		_nav.invalidate()
	var direction: Vector2 = _nav.direction_to(_leg, delta)
	_walker.velocity = direction * _speed()
	_walker.move_and_slide()
	_move_knight_to(_walker.global_position)
	if direction != Vector2.ZERO:
		_play("walk", direction)
		_knight.walk_speed_scale = clampf(_walker.get_real_velocity().length() / 50.0, 0.4, 1.3)
	else:
		_play("stand", _sector_dir())
	# no progress for a long while (a tangle of trees): he steps to a free spot nearer the hut
	var left: float = _walker.global_position.distance_to(_goal)
	if left < _best - 8.0:
		_best = left
		_stuck = 0.0
	else:
		_stuck += delta
		if _stuck > 9.0:
			_unstick()


func _sector_dir() -> Vector2:
	return Vector2.from_angle(float(maxi(_sector, 0)) * PI / 4.0)


## The next waypoint: up to LEGS px towards the hut, bent aside when that spot is blocked.
func _next_leg(from: Vector2) -> Vector2:
	var to: Vector2 = _goal - from
	if to.length() <= LEGS and _nav.can_occupy(_goal):
		return _goal
	var dir: Vector2 = to.normalized()
	for fraction: float in [1.0, 0.65, 0.4]:
		for turn: float in [0.0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05]:
			var spot: Vector2 = from + dir.rotated(turn) * minf(LEGS * fraction, to.length())
			if _nav.can_occupy(spot):
				return spot
	return _goal


func _unstick() -> void:
	_stuck = 0.0
	_leg = Vector2.INF
	_nav.invalidate()
	var from: Vector2 = _walker.global_position
	var dir: Vector2 = (_goal - from).normalized()
	for reach: float in [90.0, 70.0, 50.0]:
		for turn: float in [0.0, 0.5, -0.5, 1.0, -1.0]:
			var spot: Vector2 = from + dir.rotated(turn) * reach
			if _nav.can_occupy(spot):
				_walker.global_position = spot
				_move_knight_to(spot)
				return


func _arrive() -> void:
	_arrived = true
	_walker.velocity = Vector2.ZERO
	_move_knight_to(_walker.global_position)
	_quarry.set_knight_solid(true)
	_play("stand", _player.global_position - _knight.global_position)


## He stands by the fire; once she is near, the last lines and the step is done.
func _at_the_fire() -> void:
	var to_her: Vector2 = _player.global_position - _knight.global_position
	_play("stand", to_her)
	if to_her.length() < 70.0 and not _ending:
		_ending = true
		_finish()


func _finish() -> void:
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		await box.play("walk_end")
	if is_instance_valid(_player):
		_player.quests.set_flag("knight_arrived")
	_walker.queue_free()
	queue_free()
