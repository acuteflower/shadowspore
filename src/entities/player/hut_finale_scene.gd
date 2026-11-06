class_name HutFinaleScene
extends Node
## The end of the quest "renew the hut" (step `rebuild_finale`, event `finale:hut`): all three jobs are done, Valdric says it is time and they build the first boards together. A child of
## the player; solo / host only for now. Two ways in: she finished outside (the last job was handing him the wood: he is next to her, dialogue `finale_outside`), or inside the hut (the
## last mushroom, the tree: he comes in through the door, walks up to her, dialogue `finale_inside`, they step out through a short black).
##  1. beams lie ready on the yard (`yard_beams.png`); he takes one on his shoulder (`carry_beam`), she a plank (the carry sheet, tools/art_hero_carry.py); they carry them to the wall left
##     of the door; 2. he hammers (`hammer`: every blow sounds, dust, a nudge of the camera), she holds the plank, a few words (`finale_work`); 3. a time-lapse: the screen goes black while
##     the hammering fades, the clock moves on, the hut is mended (`Hut.set_renewed`, `Interior.set_renewed`: new boards over the roof hole and over the hole in the floor);
##  4. they stand in front of it, dialogue `finale_end`, the flag `rebuild_done` ends the quest, he rests by the door again.

const BEAMS_AT: Vector2 = Vector2(96.0, 92.0) ## from the hut's feet
const WORK_KNIGHT: Vector2 = Vector2(-38.0, 22.0)
const WORK_ELLIE: Vector2 = Vector2(-20.0, 22.0)
const VIA: Array[Vector2] = [Vector2(60.0, 80.0), Vector2(34.0, 77.0), Vector2(4.0, 72.0)] ## round the south of the fire pit
const KNIGHT_SPEED: float = 40.0
const CARRY_SPEED: float = 30.0
const BLOWS: int = 9
const HAMMER_FILES: Array[String] = ["res://assets/audio/hut/hammer_a.wav", "res://assets/audio/hut/hammer_b.wav", "res://assets/audio/hut/hammer_c.wav"]

var _player: Player
var _world: WorldLevel
var _quarry: Quarry
var _hut: Hut
var _knight: Adventurer
var _room: Interior
var _beams: Sprite2D
var _black: ColorRect
var _clip: String = ""
var _cam_base: Vector2 = Vector2.ZERO
var _look: Vector2 = Vector2.INF
var _blows: int = 0
var HAMMER: Array[AudioStream] = [] ## loaded when the scene starts (the sounds are not preloaded, so the script compiles before they are imported)
var DROP_SOUND: AudioStream
var DOOR_OPEN: AudioStream


func start(player: Player, world: WorldLevel, quarry: Quarry, hut: Hut) -> void:
	for file: String in HAMMER_FILES:
		HAMMER.append(load(file) as AudioStream)
	DROP_SOUND = load("res://assets/audio/hut/beam_drop.wav") as AudioStream
	DOOR_OPEN = load("res://assets/audio/hut/door_open.wav") as AudioStream
	_player = player
	_world = world
	_quarry = quarry
	_hut = hut
	_knight = quarry.knight
	_room = (world.get_node("Interiors") as Interiors).interior("hut")
	_cam_base = player._camera.position
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 95
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_black)
	add_child(layer)
	_run()


func _at(point: Vector2) -> Vector2:
	return _hut.global_position + point


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _dialogue(id: String) -> void:
	for child: Node in _player.get_children():
		var box: DialogueBox = child.get_node_or_null("DialogueBox") as DialogueBox
		if box != null:
			box.start(id)
			await box.finished
			return


func _fade(to: float, seconds: float) -> void:
	var tween: Tween = create_tween().set_ignore_time_scale(true)
	tween.tween_property(_black, "color:a", to, seconds)
	await tween.finished


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
		_knight.global_position += step.normalized() * minf(KNIGHT_SPEED * get_physics_process_delta_time(), step.length())
		_quarry.sync_knight_body()
		await get_tree().physics_frame


func _route_knight(points: Array[Vector2], clip: String) -> void:
	for point: Vector2 in points:
		await _walk_knight(point, clip)


## She walks (her own slow, healthy walk) to `point`.
func _walk_player(point: Vector2) -> void:
	_player.auto_walk = point
	var waited: float = 0.0
	while waited < 8.0 and _player.global_position.distance_to(point) > 4.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	if _player.global_position.distance_to(point) > 14.0:
		_player.global_position = point
	_player.auto_walk = Vector2.INF


## She walks with the plank in her hands (carry sheet, separately rendered east and west views) along `points`.
func _carry_player(points: Array[Vector2], rig: Dictionary) -> void:
	var lift: int = int(rig.get("lift", 8))
	var walk: int = int(rig.get("walk", 8))
	var t: float = 0.0
	for point: Vector2 in points:
		while _player.global_position.distance_to(point) > 1.5:
			var dt: float = get_process_delta_time()
			var step: Vector2 = point - _player.global_position
			t += dt
			_player.global_position += step.normalized() * minf(CARRY_SPEED * dt, step.length())
			_player.show_carry_frame(lift + int(t * float(rig.get("walk_fps", 10))) % walk, step.x < 0.0)
			await get_tree().process_frame


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var camera: Camera2D = _player._camera
	if _look != Vector2.INF:
		camera.position = camera.position.lerp(_cam_base + _look - _player.global_position, 1.0 - exp(-delta * 2.5))
	elif camera.position != _cam_base:
		camera.position = camera.position.lerp(_cam_base, 1.0 - exp(-delta * 3.0))
		if camera.position.distance_to(_cam_base) < 0.5:
			camera.position = _cam_base


func _sound(stream: AudioStream, at: Vector2, volume: float = -2.0) -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume
	player.max_distance = 420.0
	player.global_position = at
	player.finished.connect(player.queue_free)
	_hut.add_child(player)
	player.play()


# ---------------------------------------------------------------- the story

func _run() -> void:
	_player.story_lock = true
	InputManager.ui_blocking = true
	_quarry.set_knight_solid(false)
	if Interiors.slot_at(_player.global_position) >= 0:
		await _inside_intro()
	else:
		_look = (_knight.global_position + _player.global_position) * 0.5
		await _dialogue("finale_outside")
	await _build()
	await _lapse()
	_look = _hut.exit_position + Vector2(-8.0, -6.0)
	await _dialogue("finale_end")
	_look = Vector2.INF
	_world.place_knight("door") ## he rests in front of the door again
	_player.story_lock = false
	InputManager.ui_blocking = false
	_player.quests.set_flag("rebuild_done")
	queue_free()


## Inside: he comes in through the door, walks up to her, they talk, and both step outside (a short black).
func _inside_intro() -> void:
	var door: Doorway = _room.door
	_knight.global_position = _room.room_to_global(Vector2(320.0, 270.0))
	_knight.visible = false
	_knight.modulate.a = 0.0
	_look = _room.room_to_global(Vector2(300.0, 200.0))
	_sound(DOOR_OPEN, door.global_position)
	create_tween().tween_method(func(v: float) -> void: door.set_open(v), 0.0, 1.0, 0.35)
	await _wait(0.5)
	_knight.visible = true
	create_tween().tween_property(_knight, "modulate:a", 1.0, 0.25)
	var goal: Vector2 = _player.global_position + Vector2(34.0, 18.0)
	await _walk_knight(_room.room_to_global(Vector2(320.0, 240.0)))
	create_tween().tween_method(func(v: float) -> void: door.set_open(v), 1.0, 0.0, 0.35)
	await _walk_knight(goal)
	_play("stand", _player.global_position - _knight.global_position)
	_look = (_knight.global_position + _player.global_position) * 0.5
	await _dialogue("finale_inside")
	await _fade(1.0, 0.6)
	var interiors: Interiors = _world.get_node("Interiors") as Interiors
	_player.request_teleport(_hut.exit_position + Vector2(26.0, 18.0))
	_player.facing = Vector2.DOWN
	interiors.apply_view(_player)
	_knight.global_position = _hut.exit_position + Vector2(-20.0, 16.0)
	_play("stand", Vector2(1.0, 0.3))
	_look = _hut.exit_position
	await _wait(0.4)
	await _fade(0.0, 0.7)


## Beams are fetched, carried to the wall and nailed on.
func _build() -> void:
	var rig: Dictionary = DataRegistry.table("hero_rig").get("carry", {}) as Dictionary
	_beams = Sprite2D.new()
	_beams.texture = load("res://assets/interior/hut/yard_beams.png") as Texture2D
	_beams.offset = Vector2(0.0, _beams.texture.get_height() / 2.0 - 36.0)
	_beams.position = BEAMS_AT
	_hut.add_child(_beams)
	_look = _at(BEAMS_AT + Vector2(-30.0, -20.0))
	_clip = ""
	# both walk to the stack: he from the door, she round the fire
	_walk_player_task(_at(BEAMS_AT + Vector2(24.0, 8.0)))
	await _route_knight([_at(Vector2(-20.0, 52.0)), _at(Vector2(4.0, 72.0)), _at(Vector2(34.0, 77.0)), _at(Vector2(60.0, 80.0)), _at(BEAMS_AT + Vector2(-16.0, 6.0))], "walk")
	while _player.auto_walk != Vector2.INF:
		await get_tree().physics_frame
	# he takes a beam on his shoulder, she lifts a plank
	_play("stand", Vector2.RIGHT)
	await _wait(0.5)
	_sound(DROP_SOUND, _beams.global_position, -8.0)
	_player.facing = Vector2.LEFT
	for i: int in int(rig.get("lift", 8)):
		_player.show_carry_frame(i, true)
		await _wait(1.0 / float(rig.get("lift_fps", 12)))
	_clip = ""
	# the way home: he in front, she behind
	var route: Array[Vector2] = []
	for v: Vector2 in VIA:
		route.append(_at(v))
	var knight_route: Array[Vector2] = route.duplicate()
	knight_route.append(_at(WORK_KNIGHT + Vector2(14.0, 14.0)))
	var carry_route: Array[Vector2] = route.duplicate()
	carry_route.append(_at(WORK_ELLIE + Vector2(2.0, 10.0)))
	carry_route.append(_at(WORK_ELLIE))
	_carry_route_task(carry_route, rig)
	_look = _at(Vector2(30.0, 50.0))
	await _route_knight(knight_route, "carry_beam")
	await _walk_knight(_at(WORK_KNIGHT))
	_sound(DROP_SOUND, _at(WORK_KNIGHT), -8.0)
	_clip = ""
	while _carrying:
		await get_tree().process_frame
	_look = _at((WORK_KNIGHT + WORK_ELLIE) * 0.5 + Vector2(0.0, -10.0))
	# she holds the plank against the wall, he hammers
	_player.show_carry_frame(int(rig.get("lift", 8)) - 1, true)
	_play("hammer", Vector2.UP)
	_knight.strike.connect(_on_blow)
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box != null:
		box.play("finale_work")
	while _blows < BLOWS:
		await get_tree().physics_frame
	_knight.strike.disconnect(_on_blow)
	_play("stand", Vector2.DOWN)
	_beams.queue_free()
	await _wait(0.5)


var _carrying: bool = false


func _walk_player_task(point: Vector2) -> void:
	_walk_player(point)


func _carry_route_task(points: Array[Vector2], rig: Dictionary) -> void:
	_carrying = true
	await _carry_player(points, rig)
	_carrying = false


func _on_blow() -> void:
	_blows += 1
	_sound(HAMMER[randi() % HAMMER.size()], _knight.global_position, -1.0)
	ShockRing.burst(_hut, _knight.global_position - _hut.global_position + Vector2(0.0, -16.0), 9.0, 0.15)
	_player.add_shake(0.35)


## The hours go by: black, the last blows fading, the clock moves on, the hut is mended; they stand in front of it.
func _lapse() -> void:
	await _fade(1.0, 0.9)
	_player.end_faint()
	for k: int in 3:
		_sound(HAMMER[k % HAMMER.size()], _at(WORK_KNIGHT), -9.0 - 3.0 * k)
		await _wait(0.55)
	TimeManager.set_time(TimeManager.time_of_day + 0.1) ## about two hours
	_world.apply_renewed()
	_knight.global_position = _hut.exit_position + Vector2(-22.0, 22.0)
	_play("stand", Vector2(0.5, -0.6))
	_player.global_position = _hut.exit_position + Vector2(20.0, 26.0)
	_player.facing = Vector2(-0.5, -0.8)
	_look = _hut.exit_position + Vector2(-8.0, -30.0)
	_player._camera.reset_smoothing()
	await _wait(0.8)
	await _fade(0.0, 1.4)
