class_name RestComponent
extends Node
## Reusable, host-confirmed sitting. The owner asks; all peers play the same poses.
## The quest lives on the owner, so the seat checks its story unlock before requesting.

const SHEET: Texture2D = preload("res://assets/characters/player_rest.png")
const BLOOD: Texture2D = preload("res://assets/characters/player_rest_blood.png")

enum State { FREE, APPROACH, DOWN, IDLE, WARM, STRETCH, UP, HAIR, LOOK, SETTLE }
const GESTURE_STATES: Array[int] = [State.WARM, State.STRETCH, State.HAIR, State.LOOK, State.SETTLE]
const GESTURE_NAMES: PackedStringArray = ["warm", "stretch", "hair", "look", "settle"]

var seat: CampfireSeat
var state: State = State.FREE
var _player: Player
var _rig: Dictionary
var _time: float = 0.0
var _rest_time: float = 0.0
var _gesture: int = -1
var _next_gesture: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _prompt: InteractPrompt
var _requested_up: bool = false
var _input_guard: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player
	_rng.randomize()
	_rig = DataRegistry.table("hero_rig").get("rest", {}) as Dictionary
	_player.health.damaged.connect(func(_amount: float, _from: Vector2, _knockback: float) -> void:
		if multiplayer.is_server() and state != State.FREE: _finish.rpc())

	if not multiplayer.is_server():
		_request_snapshot.rpc_id(1)


## A peer joining while someone rests also needs the active pose, not just position.
@rpc("any_peer", "call_remote", "reliable")
func _request_snapshot() -> void:
	if multiplayer.is_server() and state != State.FREE and is_instance_valid(seat):
		_restore.rpc_id(multiplayer.get_remote_sender_id(), seat.get_path(), state, _time, _rest_time, _gesture)


@rpc("any_peer", "call_remote", "reliable")
func _restore(path: NodePath, next: State, elapsed: float, rested: float, gesture: int) -> void:
	if not _from_host(): return
	_begin(path)
	if not is_instance_valid(seat): return
	state = next
	_time = elapsed
	_rest_time = rested
	_gesture = gesture
	if state != State.APPROACH:
		_player.auto_walk = Vector2.INF
		_player.global_position = seat.seat_position()
		_player.facing = seat.sit_direction()
		if _player.is_multiplayer_authority() and state != State.DOWN and state != State.UP:
			_show_prompt()


func request_sit(spot: CampfireSeat) -> void:
	if not _player.is_multiplayer_authority() or _player.quests == null or not _player.quests.has_flag("fire_seated"):
		return
	if multiplayer.is_server():
		_request_sit(spot.get_path())
	else:
		_request_sit.rpc_id(1, spot.get_path())


func _owner_request() -> bool:
	return multiplayer.is_server() and multiplayer.get_remote_sender_id() in [0, _player.get_multiplayer_authority()]


@rpc("any_peer", "call_remote", "reliable")
func _request_sit(path: NodePath) -> void:
	if not _owner_request() or state != State.FREE or _player.health.current <= 0.0 or _player.story_lock or _player.intro != null or _player.fainting or _player.stumbling or _player.attack.is_swinging():
		return
	var spot: CampfireSeat = get_node_or_null(path) as CampfireSeat
	if spot == null or spot.occupied() or spot.reach_distance(_player.global_position) > Interactable.INTERACT_RANGE + 4.0:
		return
	_begin.rpc(path)


func _from_host() -> bool:
	return multiplayer.get_remote_sender_id() == 1 or (multiplayer.is_server() and multiplayer.get_remote_sender_id() == 0)


@rpc("any_peer", "call_local", "reliable")
func _begin(path: NodePath) -> void:
	if not _from_host(): return
	seat = get_node_or_null(path) as CampfireSeat
	if seat == null: return
	_player.story_lock = true
	_player.sprinting = false
	_player.stealth.sneaking = false
	_player.auto_walk = seat.approach_position()
	_player.velocity = Vector2.ZERO
	_requested_up = false
	_input_guard = 0.15
	_gesture = -1
	_rest_time = 0.0
	if multiplayer.is_server(): _schedule_gesture()
	_set_state(State.APPROACH)


@rpc("any_peer", "call_local", "reliable")
func _sit_down() -> void:
	if not _from_host() or not is_instance_valid(seat): return
	_player.auto_walk = Vector2.INF
	_player.global_position = seat.seat_position()
	_player.facing = seat.sit_direction()
	_set_state(State.DOWN)


func request_stand() -> void:
	if not _player.is_multiplayer_authority() or _requested_up or state == State.FREE or state == State.UP:
		return
	_requested_up = true
	if multiplayer.is_server():
		_request_stand()
	else:
		_request_stand.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_stand() -> void:
	if not _owner_request() or state == State.FREE or state == State.UP: return
	if state == State.APPROACH:
		_finish.rpc()
	else:
		_stand.rpc()


@rpc("any_peer", "call_local", "reliable")
func _stand() -> void:
	if not _from_host(): return
	# Reversing the current down frame avoids jumping when E interrupts sitting down.
	var elapsed: float = _time if state == State.DOWN else _down_duration()
	_set_state(State.UP)
	_time = maxf(0.0, _down_duration() - elapsed)
	if _prompt != null: _prompt.show_text("")


func _down_duration() -> float:
	return float((_rig.down as Array)[1]) / float(_rig.fps)


func _set_state(next: State) -> void:
	state = next
	_time = 0.0


func _schedule_gesture() -> void:
	_rest_time = 0.0
	_next_gesture = _rng.randf_range(float(_rig.get("gesture_wait_min", 5.0)), float(_rig.get("gesture_wait_max", 10.0)))


func _choose_gesture() -> int:
	var choice: int = _rng.randi_range(0, GESTURE_STATES.size() - 1) if _gesture < 0 else _rng.randi_range(0, GESTURE_STATES.size() - 2)
	return choice + 1 if _gesture >= 0 and choice >= _gesture else choice


@rpc("any_peer", "call_local", "reliable")
func _start_gesture(gesture: int) -> void:
	if not _from_host() or state != State.IDLE or gesture < 0 or gesture >= GESTURE_STATES.size(): return
	_gesture = gesture
	_rest_time = 0.0
	_set_state(GESTURE_STATES[gesture])


func _physics_process(delta: float) -> void:
	if state == State.FREE: return
	if not is_instance_valid(seat) or _player.health.current <= 0.0 or _player.intro != null:
		if multiplayer.is_server(): _finish.rpc()
		return
	_time += delta
	_input_guard = maxf(0.0, _input_guard - delta)
	if _input_guard <= 0.0 and _player.is_multiplayer_authority() and not InputManager.ui_blocking and not InputManager.menu_open and not InputManager.map_open and not InputManager.skills_open:
		if InputManager.interact_pressed() or InputManager.move_vector().length() > 0.1:
			request_stand()
	if state == State.FREE: return
	if state == State.APPROACH:
		if multiplayer.is_server() and (_player.global_position.distance_to(seat.approach_position()) < 5.0 or _time > 4.0):
			_sit_down.rpc()
		return
	if _player.global_position.distance_to(seat.seat_position()) > 48.0:
		if multiplayer.is_server(): _finish.rpc()
		return
	var clip: Array = _rig.idle as Array
	var fps: float = float(_rig.idle_fps)
	var frame: int
	match state:
		State.DOWN:
			clip = _rig.down as Array
			frame = int(clip[0]) + mini(int(_time * float(_rig.fps)), int(clip[1]) - 1)
			if _time >= _down_duration():
				_set_state(State.IDLE)
				if _player.is_multiplayer_authority(): _show_prompt()
		State.UP:
			frame = maxi(int((_rig.down as Array)[1]) - 1 - int(_time * float(_rig.fps)), 0)
			if multiplayer.is_server() and _time >= _down_duration():
				_finish.rpc()
				return
		_:
			if state in GESTURE_STATES:
				clip = _rig.get(GESTURE_NAMES[_gesture], _rig.idle) as Array
				fps = float(_rig.gesture_fps)
				frame = int(clip[0]) + mini(int(_time * fps), int(clip[1]) - 1)
				if _time >= float(clip[1]) / fps:
					_set_state(State.IDLE)
					if multiplayer.is_server(): _schedule_gesture()
			else:
				frame = int(clip[0]) + int(_time * fps) % int(clip[1])
				_rest_time += delta
				if multiplayer.is_server() and _rest_time >= _next_gesture and frame == int(clip[0]):
					_start_gesture.rpc(_choose_gesture())
	_player.show_rest_frame(frame, seat.sit_sector())


func _show_prompt() -> void:
	if _prompt == null:
		_prompt = InteractPrompt.new()
		_prompt.position = Vector2(0, -46)
		_player.add_child(_prompt)
	_prompt.show_text("AUFSTEHEN")


@rpc("any_peer", "call_local", "reliable")
func _finish() -> void:
	if not _from_host(): return
	_clear(true)


func _clear(move_to_front: bool) -> void:
	if state == State.FREE: return
	if move_to_front and state != State.APPROACH and is_instance_valid(seat) and _player.global_position.distance_to(seat.seat_position()) < 48.0:
		_player.global_position = seat.approach_position()
	_player.auto_walk = Vector2.INF
	_player.velocity = Vector2.ZERO
	_player.story_lock = false
	_player.end_faint()
	if _prompt != null:
		_prompt.queue_free()
		_prompt = null
	seat = null
	state = State.FREE


func _exit_tree() -> void:
	if is_instance_valid(_player): _clear(false)
