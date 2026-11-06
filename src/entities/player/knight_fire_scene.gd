class_name KnightFireScene
extends Node
## The evening at the fire (quest step `sit_fire`: E at either of the two places, the stump east of the fire or the log south of it; `Hut` puts a `StorySpot` on each). A child of the player,
## solo / host only for now. What happens:
##  1. she sits down (`Player.show_sit_frame`, with the actual fire-facing sector); he walks to the hut's door and goes in;
##  2. the camera swings to the door while the day runs on to the evening (`EVENING`); the door opens, he comes out with a mug of brew (clip `walk_mug`, steam), walks round the fire to her
##     and gives it to her (`give`; her `take`), then sits down at the other place (`sit_down`, `sit`);
##  3. dialogue `fire_a`, she sips (the brew mends her: `HealthComponent.heal`, the bandage is off, she stops limping), `fire_b`, her sword is given back (equipped), `fire_c` (he says a fire
##     is for cooking too: flag `knows_cooking`; the cooking itself is not built yet); she sets the mug down and gets up, the camera returns, his closing line `fire_end`;
##  4. the flag `fire_seated` finishes the step; the next one is to go into the hut and sleep (`SleepScene`). He stays sitting at the fire.
## All texts are placeholders.

const STUMP: Vector2 = Vector2(84.0, 64.0) ## the seats' feet, from the hut's feet (data/ground.json seat_e, seat_s)
const LOG: Vector2 = Vector2(34.0, 92.0)
const EVENING: float = 0.80
const SIT_FPS: float = 24.0
const SPEED: float = 46.0
const DOOR_OPEN: AudioStream = preload("res://assets/audio/hut/door_open.wav")
const DOOR_CLOSE: AudioStream = preload("res://assets/audio/hut/door_close.wav")

enum Mode { NONE, DOWN, LOOP, UP, TAKE, HOLD, SIP }

var _player: Player
var _quarry: Quarry
var _hut: Hut
var _knight: Adventurer
var _rig: Dictionary
var _rest_rig: Dictionary
var _sit_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sit_gesture: int = -1
var _sit_last: int = -1
var _sit_time: float = 0.0
var _sit_wait: float = 0.0
var _east: bool = true ## she sits on the stump (else on the log)
var _mode: Mode = Mode.NONE
var _t: float = 0.0
var _look: Vector2 = Vector2.INF ## the world point the camera looks at (INF = her)
var _look_knight: bool = false
var _steam: CPUParticles2D
var _clip: String = ""
var _cam_base: Vector2 = Vector2.ZERO ## the camera's usual place on her


func start(player: Player, quarry: Quarry, hut: Hut, seat: String) -> void:
	_player = player
	_quarry = quarry
	_hut = hut
	_knight = quarry.knight
	_east = seat == "east"
	_rig = DataRegistry.table("hero_rig").get("sit", {}) as Dictionary
	_rest_rig = DataRegistry.table("hero_rig").get("rest", {}) as Dictionary
	_sit_rng.randomize()
	_cam_base = player._camera.position
	if not quarry.knight_left:
		quarry.hand_over_knight(quarry.get_parent())
		_knight.global_position = hut.exit_position + Vector2(-26.0, 22.0)
	_run()


# ---------------------------------------------------------------- places

func _at(point: Vector2) -> Vector2:
	return _hut.global_position + point


func _her_seat() -> Vector2:
	return _at(STUMP + Vector2(0.0, 3.0)) if _east else _at(LOG + Vector2(4.0, 3.0))


func _his_seat() -> Vector2:
	return _at(LOG + Vector2(4.0, 3.0)) if _east else _at(STUMP + Vector2(0.0, 3.0))


func _his_dir() -> Vector2:
	return Vector2(1.0, -1.0) if _east else Vector2(-1.0, 1.0)


## Where he stands when he gives her the mug, and the way there from the door.
func _hand_over_route() -> Array[Vector2]:
	if _east:
		return [_at(Vector2(0, 30)), _at(Vector2(6, 76)), _at(STUMP + Vector2(-18, 14))]
	return [_at(Vector2(0, 30)), _at(Vector2(6, 76)), _at(Vector2(8, 104)), _at(LOG + Vector2(-12, 14))]


func _her_approach() -> Vector2:
	return _her_seat() + (Vector2(10, 14) if _east else Vector2(0, 12))


# ---------------------------------------------------------------- helpers

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _dialogue(id: String) -> void:
	for child: Node in _player.get_children():
		var box: DialogueBox = child.get_node_or_null("DialogueBox") as DialogueBox
		if box != null:
			box.start(id)
			await box.finished
			return


func _sound(stream: AudioStream, at: Vector2, volume: float = -4.0) -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume
	player.max_distance = 400.0
	player.global_position = at
	player.finished.connect(player.queue_free)
	_hut.add_child(player)
	player.play()


func _door(open: bool) -> void:
	_sound(DOOR_OPEN if open else DOOR_CLOSE, _hut.global_position + Vector2(0, 4))
	var door: Doorway = _hut.doorway
	create_tween().tween_method(func(v: float) -> void: door.set_open(v), 0.0 if open else 1.0, 1.0 if open else 0.0, 0.4)


func _play(clip: String, toward: Vector2) -> void:
	if clip != _clip:
		_clip = clip
		_knight.play(clip, toward)
	else:
		_knight.face(toward)


func _walk_knight(point: Vector2, clip: String = "walk") -> void:
	while _knight.global_position.distance_to(point) > 1.5:
		var step: Vector2 = point - _knight.global_position
		_play(clip, step)
		_knight.global_position += step.normalized() * minf(SPEED * get_physics_process_delta_time(), step.length())
		_quarry.sync_knight_body()
		await get_tree().physics_frame


func _route(points: Array[Vector2], clip: String = "walk") -> void:
	for point: Vector2 in points:
		await _walk_knight(point, clip)


func _walk_player(point: Vector2) -> void:
	_player.auto_walk = point
	var waited: float = 0.0
	while waited < 5.0 and _player.global_position.distance_to(point) > 4.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if _player.global_position.distance_to(point) > 14.0:
		_player.global_position = point
	_player.auto_walk = Vector2.INF


func _make_steam(parent: Node2D, at: Vector2) -> void:
	if _steam != null:
		_steam.queue_free()
	_steam = CPUParticles2D.new()
	_steam.position = at
	_steam.z_index = 3
	_steam.amount = 6
	_steam.lifetime = 1.6
	_steam.preprocess = 1.6
	_steam.direction = Vector2(0.15, -1.0)
	_steam.spread = 14.0
	_steam.gravity = Vector2(1.0, -4.0)
	_steam.initial_velocity_min = 5.0
	_steam.initial_velocity_max = 9.0
	_steam.scale_amount_min = 0.8
	_steam.scale_amount_max = 1.6
	var fade: Gradient = Gradient.new()
	fade.colors = PackedColorArray([Color(0.7, 0.95, 0.95, 0.0), Color(0.7, 0.95, 0.95, 0.4), Color(0.6, 0.8, 0.9, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	_steam.color_ramp = fade
	_steam.material = Unlit.material()
	parent.add_child(_steam)


# ---------------------------------------------------------------- frames and camera

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var camera: Camera2D = _player._camera
	if _look != Vector2.INF or _look_knight:
		var target: Vector2 = (_knight.global_position + Vector2(0, -16)) if _look_knight else _look
		camera.position = camera.position.lerp(_cam_base + target - _player.global_position, 1.0 - exp(-delta * 3.0))
	elif camera.position != _cam_base:
		camera.position = camera.position.lerp(_cam_base, 1.0 - exp(-delta * 3.0))
		if camera.position.distance_to(_cam_base) < 0.5:
			camera.position = _cam_base
	if _mode == Mode.NONE:
		return
	_t += delta
	var down: int = int(_rig.get("down", 18))
	var loop: int = int(_rig.get("loop", 6))
	var take: int = int(_rig.get("take", 6))
	var hold: int = int(_rig.get("hold", 6))
	var sip: int = int(_rig.get("sip", 10))
	var sector: int = 4 if _east else 5
	var frame: int = 0
	match _mode:
		Mode.DOWN:
			frame = mini(int(_t * SIT_FPS), down - 1)
		Mode.LOOP:
			frame = down + int(_t * float(_rig.get("loop_fps", 5))) % loop
			if _sit_gesture >= 0:
				var names: Array = _rest_rig.get("gesture_names", []) as Array
				if _sit_gesture < names.size():
					var clip: Array = _rest_rig.get(String(names[_sit_gesture]), []) as Array
					if clip.size() >= 2:
						var fps: float = float(_rest_rig.get("gesture_fps", 12.0))
						_sit_time += delta
						_player.show_rest_frame(int(clip[0]) + mini(int(_sit_time * fps), int(clip[1]) - 1), sector)
						if _sit_time >= float(clip[1]) / fps:
							_sit_gesture = -1
							_t = 0.0
							_schedule_sit_gesture()
						return
				_sit_gesture = -1
			_sit_wait -= delta
			if _sit_wait <= 0.0 and frame == down:
				var names: Array = _rest_rig.get("gesture_names", []) as Array
				if names.size() > 1:
					var choice: int = _sit_rng.randi_range(0, names.size() - 1) if _sit_last < 0 else _sit_rng.randi_range(0, names.size() - 2)
					if _sit_last >= 0 and choice >= _sit_last: choice += 1
					_sit_gesture = choice
					_sit_last = choice
					_sit_time = 0.0
		Mode.UP:
			frame = maxi(down - 1 - int(_t * SIT_FPS), 0)
		Mode.TAKE:
			frame = down + loop + mini(int(_t * 8.0), take - 1)
		Mode.HOLD:
			frame = down + loop + take + int(_t * 5.0) % hold
		Mode.SIP:
			frame = down + loop + take + hold + mini(int(_t * 10.0), sip - 1)
	_player.show_sit_frame(frame, sector)


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_t = 0.0
	_sit_gesture = -1
	_sit_time = 0.0
	if mode == Mode.LOOP: _schedule_sit_gesture()


func _schedule_sit_gesture() -> void:
	_sit_wait = _sit_rng.randf_range(float(_rest_rig.get("gesture_wait_min", 5.0)), float(_rest_rig.get("gesture_wait_max", 10.0)))


# ---------------------------------------------------------------- the story

func _run() -> void:
	_player.story_lock = true
	InputManager.ui_blocking = true
	_clip = ""
	_knight_to_door.call_deferred() ## he goes in to fetch the brew while she sits down
	await _walk_player(_her_approach())
	_player.global_position = _her_seat()
	_player.facing = Vector2.LEFT if _east else Vector2(-1.0, -1.0).normalized()
	_set_mode(Mode.DOWN)
	await _wait(float(_rig.get("down", 18)) / SIT_FPS)
	_set_mode(Mode.LOOP)
	while not _inside:
		await get_tree().physics_frame
	# the camera swings to the door while the evening comes
	_look = _at(Vector2(0.0, -14.0))
	_to_evening()
	await _wait(3.2)
	_door(true)
	await _wait(0.9)
	_knight.visible = true
	_knight.modulate.a = 0.0
	_knight.global_position = _at(Vector2(0.0, 6.0))
	create_tween().tween_property(_knight, "modulate:a", 1.0, 0.3)
	_make_steam(_knight, Vector2(6.0, -26.0))
	_look_knight = true
	_look = Vector2.INF
	var out: Array[Vector2] = _hand_over_route()
	await _walk_knight(out[0], "walk_mug")
	_door(false)
	for i: int in range(1, out.size()):
		await _walk_knight(out[i], "walk_mug")
	# he gives her the brew
	var toward: Vector2 = _her_seat() - _knight.global_position
	_play("give", toward)
	await _wait(0.5)
	_set_mode(Mode.TAKE)
	await _wait(0.8)
	_make_steam(_player, Vector2(-6.0 if _east else 6.0, -22.0))
	_set_mode(Mode.HOLD)
	await _wait(0.5)
	_look_knight = false
	_look = (_her_seat() + _his_seat()) * 0.5 + Vector2(0.0, -10.0)
	# he sits down at the other place
	await _knight_sits()
	await _wait(0.9)
	await _dialogue("fire_a")
	_set_mode(Mode.SIP)
	await _wait(1.0)
	_player.set_bandaged(false)
	_player.health.heal(_player.health.max_health * 0.7)
	_set_mode(Mode.HOLD)
	await _wait(0.7)
	await _dialogue("fire_b")
	_give_sword()
	await _dialogue("fire_c")
	_player.quests.set_flag("knows_cooking")
	await _wait(0.4)
	await _get_up()
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		await box.play("fire_end")
	_player.story_lock = false
	InputManager.ui_blocking = false
	_player.quests.set_flag("fire_seated")
	queue_free()


var _inside: bool = false


## He walks to the door, opens it, goes in and shuts it behind him.
func _knight_to_door() -> void:
	_quarry.set_knight_solid(false)
	await _walk_knight(_at(Vector2(0.0, 30.0)))
	await _walk_knight(_at(Vector2(0.0, 12.0)))
	_door(true)
	await _walk_knight(_at(Vector2(0.0, 6.0)))
	var fade: Tween = create_tween()
	fade.tween_property(_knight, "modulate:a", 0.0, 0.25)
	await fade.finished
	_knight.visible = false
	_door(false)
	await _wait(0.5)
	_inside = true


func _knight_sits() -> void:
	var seat: Vector2 = _his_seat()
	var front: Vector2 = seat + (Vector2(-14.0, 11.0) if not _east else Vector2(-12.0, 12.0))
	await _walk_knight(front)
	await _walk_knight(seat)
	_clip = ""
	_knight.play("sit_down", _his_dir())
	await _knight.clip_done
	_clip = "sit"
	_knight.play("sit", _his_dir())
	_quarry.set_knight_solid(true)


func _to_evening() -> void:
	var from: float = TimeManager.time_of_day
	if from >= EVENING - 0.01 and from <= 0.99:
		return
	var tween: Tween = create_tween()
	tween.tween_method(func(v: float) -> void: TimeManager.time_of_day = v, from, EVENING, 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: TimeManager.set_time(EVENING))


func _give_sword() -> void:
	if String((_player.inventory.equipment.get("main_hand", {}) as Dictionary).get("id", "")) == "":
		_player.inventory.equipment["main_hand"] = {"id": "sword_basic", "count": 1}
		_player.inventory._commit()


func _get_up() -> void:
	if _steam != null:
		_steam.queue_free()
		_steam = null
	_set_mode(Mode.LOOP) ## the mug is set down
	await _wait(0.6)
	_set_mode(Mode.UP)
	_look = Vector2.INF
	await _wait(float(_rig.get("down", 18)) / SIT_FPS)
	_set_mode(Mode.NONE)
	_player.end_faint()
	_player.global_position = _her_approach()
	_player.facing = Vector2.LEFT if _east else Vector2.UP
	_clip = "sit"
