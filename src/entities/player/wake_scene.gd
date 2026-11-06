class_name WakeScene
extends Node
## The morning after the rescue: Ellie wakes up in the old bed of the hut (the first interior, `Interiors`). Started by the quest step "wake" (`WorldLevel.start_wake`,
## solo / host), a child of the local player; she cannot act meanwhile (`Player.intro`), the HUD stays away.
##  1. black, the room's sounds (wind through the cracks, the fire, a few birds, the wood), the clock jumps to morning; she lies asleep (a breathing loop);
##  2. the eyes open three times, each a bit further (`wake_eyes.gdshader`: ragged black lid silhouettes, a smear of big pixels that sharpens); she turns her head (awake loop),
##     thinks aloud (dialogue `wake_inner`);
##  3. "E AUFSTEHEN" hangs over the bed (an `InteractPrompt`); E gets her up: the sheet assets/characters/player_wake.png (art: tools/art_hero_wake.py, timeline
##     and events in data/hero_rig.json "wake"): head up, on the elbows, sitting, the blanket slides off, she scoots to the foot end, the legs swing over the edge,
##     she sits gasping, pushes up, stands, swaying; the bed creaks, straw rustles; the bed prop keeps the blanket as a heap;
##  4. she stands: the HUD grows in, the opening is over (`WorldLevel.finish_opening`: the clock has run since she woke at 08:00), the flag "woke_up" lets the quest carry on.
## She is bandaged now (`Player.set_bandaged`): no blood, no red border, no heartbeat; she still limps.

const SHEET: Texture2D = preload("res://assets/characters/player_wake.png")
const BLOOD: Texture2D = preload("res://assets/characters/player_wake_blood.png")
const EYES: Shader = preload("res://assets/shaders/wake_eyes.gdshader")
const SOUNDS: Dictionary = {
	"creak_a": preload("res://assets/audio/hut/creak_a.wav"),
	"creak_b": preload("res://assets/audio/hut/creak_b.wav"),
	"groan": preload("res://assets/audio/hut/groan.wav"),
	"rustle": preload("res://assets/audio/hut/rustle.wav"),
	"gasp": preload("res://assets/audio/intro/gasp.wav"),
	"cough": preload("res://assets/audio/intro/cough.wav"),
}
const MORNING: float = 8.0 / 24.0 ## 08:00
const SPRITE_OFFSET: Vector2 = Vector2(0.0, -19.0) ## the frames are 64 high, the floor row is 51
## (seconds, how far the eyes are open 0..1.7, how blurred 1..0): the three attempts
const EYE_KEYS: Array[Vector3] = [Vector3(0.0, 0.0, 1.0), Vector3(1.6, 0.0, 1.0), Vector3(2.4, 0.22, 1.0), Vector3(3.0, 0.04, 0.95), Vector3(4.2, 0.5, 0.8), Vector3(4.8, 0.12, 0.8),
		Vector3(6.2, 0.95, 0.45), Vector3(7.0, 0.7, 0.4), Vector3(8.2, 1.75, 0.0)]
const ZOOM_IN: float = 2.1
const AWAKE_AT: float = 4.2 ## the head turns to the room
const DIALOGUE_AT: float = 8.4

enum State { OPENING, SPEAKING, WAITING, GETUP, DONE }

var _player: Player
var _world: WorldLevel
var _interiors: Interiors
var _interior: Interior
var _black: ColorRect
var _eyes: ColorRect
var _eye_material: ShaderMaterial = ShaderMaterial.new()
var _prompt: InteractPrompt
var _state: State = State.OPENING
var _clock: float = 0.0
var _rig: Dictionary = {}
var _fps: float = 12.0
var _frames: int = 1
var _sleep: Array = [0, 8]
var _awake: Array = [8, 8]
var _getup: Array = [16, 1]
var _offsets: PackedVector2Array = PackedVector2Array()
var _events: Dictionary = {}
var _fired: Dictionary = {}
var _getup_time: float = 0.0
var _bed: Vector2 = Vector2.ZERO ## the bed's anchor in the room
var _spoke: bool = false
var _rest: bool = false ## a later night's sleep: no thoughts, the knight and the flags stay as they are
var _second: bool = false ## the morning after the first night in the hut (nothing is cleared, no bandage, other thoughts)
var _blanket: Sprite2D ## the blanket over her, fixed to the bed (its own sheet: the same frame as hers)


func start(player: Player, world: WorldLevel, ready_to_get_up: bool = false, second_morning: bool = false, rest: bool = false) -> void:
	_second = second_morning
	_rest = rest
	_spoke = rest
	_player = player
	_world = world
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interiors = world.get_node("Interiors") as Interiors
	_interior = _interiors.interior("hut")
	_rig = DataRegistry.table("hero_rig").get("wake", {}) as Dictionary
	_fps = float(_rig.get("fps", 12))
	_frames = int(_rig.get("frames", 1))
	_sleep = _rig.get("sleep", [0, 8]) as Array
	_awake = _rig.get("awake", [8, 8]) as Array
	_getup = _rig.get("getup", [16, 1]) as Array
	_events = _rig.get("events", {}) as Dictionary
	for point: Array in _rig.get("offset", []):
		_offsets.append(Vector2(float(point[0]), float(point[1])))
	var anchor: Array = _interior.spec.bed_anchor as Array
	_bed = Vector2(float(anchor[0]), float(anchor[1]))
	var black_layer: CanvasLayer = CanvasLayer.new() ## above the HUD and the other overlays
	black_layer.layer = 96
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_layer.add_child(_black)
	add_child(black_layer)
	var eyes_layer: CanvasLayer = CanvasLayer.new() ## the lids and the blur: over the world, under the black
	eyes_layer.layer = 94
	_eyes = ColorRect.new()
	_eyes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_eyes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_material.shader = EYES
	_eyes.material = _eye_material
	eyes_layer.add_child(_eyes)
	add_child(eyes_layer)
	_blanket = Sprite2D.new()
	_blanket.texture = load("res://assets/interior/hut/blanket.png") as Texture2D
	_blanket.hframes = _frames
	_blanket.centered = false
	_blanket.position = _bed - Vector2(44, 66) ## the bed's frames are 88 x 76 with the floor row at 66
	_blanket.z_index = 2
	_interior.add_child(_blanket)
	player.begin_intro(self)
	if not _second:
		player.set_bandaged(true)
	player.z_index = 1 ## above the bed she lies on
	TimeManager.set_time(MORNING)
	TimeManager.unlock() ## the day runs normally from the moment she wakes up
	if not _second:
		player.inventory.clear_all() ## whatever she carried (the knight's sword) is gone: she starts again with empty hands
	_interiors.place_player(player, "hut", _bed)
	_interior.set_bed_frame(0)
	_set_eyes(0.0, 1.0)
	_place(0)
	_player._camera.zoom = Vector2.ONE * ZOOM_IN ## the camera is close to the bed, and draws back as she gets up
	_set_limits(_room_limits())
	_black.color.a = 1.0
	if ready_to_get_up:
		_clock = DIALOGUE_AT
		_spoke = true
		_black.color.a = 0.0
		_eyes.get_parent().visible = false
		_idle_frames()
		_wait_for_e()
	else:
		create_tween().set_ignore_time_scale(true).tween_property(_black, "color:a", 0.0, 1.4).set_delay(0.6) ## the black gives way to the lids


func _process(delta: float) -> void:
	_clock += delta
	_eye_material.set_shader_parameter("time", _clock)
	_eye_material.set_shader_parameter("view_size", _eyes.size)
	match _state:
		State.OPENING:
			_idle_frames()
			var key: Vector2 = _eye_key(_clock)
			_set_eyes(key.x, key.y)
			if _clock >= float((EYE_KEYS[EYE_KEYS.size() - 1] as Vector3).x):
				_eyes.get_parent().visible = false
				_state = State.SPEAKING
				_speak()
		State.SPEAKING:
			_idle_frames()
		State.WAITING:
			_idle_frames()
			if InputManager.interact_pressed():
				_begin_getup()
		State.GETUP:
			_run_getup(delta)


## How far the eyes are open and how blurred the picture is at `t` (eased between the keys).
func _eye_key(t: float) -> Vector2:
	for i: int in EYE_KEYS.size() - 1:
		var a: Vector3 = EYE_KEYS[i]
		var b: Vector3 = EYE_KEYS[i + 1]
		if t <= b.x:
			var k: float = clampf((t - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)
			return Vector2(lerpf(a.y, b.y, k), lerpf(a.z, b.z, k))
	var last: Vector3 = EYE_KEYS[EYE_KEYS.size() - 1]
	return Vector2(last.y, last.z)


func _set_eyes(_open: float, blur: float) -> void:
	_eye_material.set_shader_parameter("open", 2.0) ## no lids, no blinking: only the pixelated smear that sharpens
	_eye_material.set_shader_parameter("blur", blur)


## Asleep until the head turns, then awake: the breathing loops.
func _idle_frames() -> void:
	var loop: Array = _sleep if _clock < AWAKE_AT else _awake
	_place(int(loop[0]) + int(_clock * 6.0) % int(loop[1]))


func _place(frame: int, offset: Vector2 = Vector2.ZERO) -> void:
	if _blanket != null:
		_blanket.frame = clampi(frame, 0, _frames - 1)
	_player.show_emerge_frame(SHEET, _frames, clampi(frame, 0, _frames - 1), _interior.room_to_global(_bed + offset), BLOOD, SPRITE_OFFSET)


func _speak() -> void:
	var box: DialogueBox = get_tree().get_first_node_in_group("dialogue") as DialogueBox
	if box == null or _spoke:
		_wait_for_e()
		return
	_spoke = true
	box.start("wake_day2" if _second else "wake_inner")
	await box.finished
	_wait_for_e()


func _wait_for_e() -> void:
	_state = State.WAITING
	_prompt = InteractPrompt.new()
	_prompt.position = _bed + Vector2(0, -50)
	_interior.add_child(_prompt)
	_prompt.show_text("AUFSTEHEN")


## The camera limits hug the room while the camera is close (so the bed is not at the edge of a black margin) and spread to the usual view as it draws back.
func _room_limits() -> Rect2:
	return Rect2(_interior.global_position, _interior.size)


func _set_limits(rect: Rect2) -> void:
	var camera: Camera2D = _player._camera
	camera.limit_left = int(rect.position.x)
	camera.limit_top = int(rect.position.y)
	camera.limit_right = int(rect.end.x)
	camera.limit_bottom = int(rect.end.y)


func _begin_getup() -> void:
	_state = State.GETUP
	var tween: Tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	tween.tween_property(_player._camera, "zoom", Vector2.ONE, 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(1.2)
	var from: Rect2 = _room_limits()
	var to: Rect2 = _interior.view_rect(get_viewport().get_visible_rect().size)
	tween.tween_method(func(k: float) -> void: _set_limits(Rect2(from.position.lerp(to.position, k), from.size.lerp(to.size, k))), 0.0, 1.0, 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(1.2)
	_getup_time = 0.0
	_fired.clear()
	if _prompt != null:
		_prompt.show_text("")
		_prompt.queue_free()


func _run_getup(delta: float) -> void:
	_getup_time += delta
	var count: int = int(_getup[1])
	var index: int = int(_getup_time * _fps)
	for event_name: String in _events:
		if _getup_time >= float(_events[event_name]) and not _fired.has(event_name):
			_fired[event_name] = true
			_fire(event_name)
	if index >= count:
		_finish()
		return
	var frame: int = int(_getup[0]) + index
	var key: float = clampf(_getup_time * _fps - 0.5, 0.0, float(count - 1) - 0.001)
	var i: int = int(key) + int(_getup[0])
	var offset: Vector2 = _offsets[i].lerp(_offsets[mini(i + 1, _offsets.size() - 1)], key - floorf(key)) if _offsets.size() == _frames else Vector2.ZERO
	_place(frame, offset)


func _fire(event_name: String) -> void:
	match event_name:
		"groan":
			_play("groan", -4.0)
			_player.add_shake(0.8)
		"creak_a":
			_play("creak_a", -4.0)
			_play("rustle", -10.0)
		"sit":
			_play("gasp", -6.0)
		"slide":
			_play("rustle", -4.0)
		"legs":
			_play("rustle", -8.0)
		"creak_b":
			_play("creak_b", -3.0)
			_player.add_shake(1.0)
		"breath":
			_play("cough", -7.0)
		"push":
			_play("creak_a", -5.0)
			_play("groan", -9.0)
		"stand":
			_player.add_shake(1.6)


func _play(sound_name: String, volume_db: float) -> void:
	var sound: AudioStreamPlayer = AudioStreamPlayer.new()
	sound.stream = SOUNDS[sound_name] as AudioStream
	sound.volume_db = volume_db
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()


func _finish() -> void:
	_state = State.DONE
	var end: Vector2 = _interior.room_to_global(_bed + (_offsets[_offsets.size() - 1] if not _offsets.is_empty() else Vector2.ZERO))
	_interior.set_bed_frame(1) ## the blanket stays behind as a heap (the same as the last frame of its sheet)
	_blanket.queue_free()
	_player._camera.zoom = Vector2.ONE
	_interiors.apply_view(_player)
	_player.end_wake(end)
	if _rest:
		pass ## the town quest's night: Valdric is where he was
	elif _second:
		_world.place_knight("door") ## he waits in front of the door
		if _player.quests != null:
			_player.quests.set_flag("day2_started")
	else:
		if _player.quests != null:
			_player.quests.set_flag("woke_up")
		_world.finish_opening() ## the clock runs again
	queue_free()
