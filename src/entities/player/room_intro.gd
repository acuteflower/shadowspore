class_name RoomIntro
extends Node
## The opening of Ellie's room (data/interiors.json "personalraum"). A white screen (later: the main menu); the great crow of the window flies across the screen from the left, so close that it covers it
## from top to bottom, and behind it the world appears: a close-up of the window. The small crow comes flying in and lands on the sill; the camera draws back to the game's zoom while Ellie, at her
## wardrobe, pushes its open door shut (the clip of tools/art_hero_wardrobe.py): zoom-out and wardrobe end together. Then the game is hers, with no HUD but the quest "NIMM DEN BESEN".
## Solo / local only. `start(player, room)`; the scene frees itself at the end. Everything is driven by one clock (`_t`), so a capture at a given time is always the same picture.

signal finished

const CROW: Texture2D = preload("res://assets/fx/intro_crow.png")
const SND_AIR: AudioStream = preload("res://assets/audio/room_intro/white_air.wav")
const SND_PASS: AudioStream = preload("res://assets/audio/room_intro/crow_pass.wav")
const SND_LAND: AudioStream = preload("res://assets/audio/room_intro/wing_land.wav")
const SND_CREAK: AudioStream = preload("res://assets/audio/room_intro/wardrobe_creak.wav")
const SND_THUD: AudioStream = preload("res://assets/audio/room_intro/wardrobe_thud.wav")
const SND_CAW: AudioStream = preload("res://assets/audio/wildlife/crow_1.wav")

const WHITE_HOLD: float = 1.3 ## s of plain white
const PASS_TIME: float = 2.1 ## s the great crow takes to cross
const AFTER_PASS: float = 1.0 ## s of the empty window before the small crow comes
const FLY_IN: float = 2.2 ## s the small crow takes to land
const SETTLE: float = 0.9 ## s it sits there before the camera draws back
const ZOOM_CLOSE: float = 4.0
const WINDOW_FOCUS: Vector2 = Vector2(111, 47) ## room px: the middle of the close-up
const STAND: Vector2 = Vector2(217, 102) ## room px: where she stands at the wardrobe
const FEATHER_TIMES: Array[float] = [0.6, 1.0, 1.35, 1.75, 2.1, 2.5]
const FLAP_FPS: float = 28.0 ## the flap loop has 20 frames: 0.7 s a beat

var _player: Player
var _room: Interior
var _crow: InteriorCrow
var _wardrobe: Sprite2D
var _camera: Camera2D
var _layer: CanvasLayer
var _wipe: Control
var _sprite: Sprite2D
var _edges: Array[PackedInt32Array] = []
var _frame_size: Vector2i = Vector2i(600, 640)
var _frame_center: Vector2i = Vector2i(300, 320)
var _rig: Dictionary
var _clip_len: float = 3.6
var _t: float = 0.0
var _marks: Dictionary = {}
var _fired: Dictionary = {}
var _feathers: Array[Dictionary] = []
var _crow_x: float = -1000.0
var _frame: int = 0
var _zoom_hold: float = ZOOM_CLOSE
var _done: bool = false


func start(player: Player, room: Interior) -> void:
	_player = player
	_room = room
	_camera = player.view_camera()
	for child: Node in room.get_children():
		if child is InteriorCrow:
			_crow = child as InteriorCrow
	_wardrobe = room.props.get("wardrobe") as Sprite2D
	var data: Dictionary = DataRegistry.table("intro_crow")
	_frame_size = Vector2i(int((data.size as Array)[0]), int((data.size as Array)[1]))
	_frame_center = Vector2i(int((data.center as Array)[0]), int((data.center as Array)[1]))
	for frame_edges: Array in data.edge as Array:
		var packed: PackedInt32Array = PackedInt32Array()
		var last: int = 0
		for value: Variant in frame_edges:
			if int(value) >= 0:
				last = int(value)
				break
		for value: Variant in frame_edges:
			if int(value) >= 0:
				last = int(value)
			packed.append(last) ## rows the bird does not cover take the nearest row's edge
		_edges.append(packed)
	_rig = (DataRegistry.table("hero_rig").wardrobe as Dictionary)
	_clip_len = float(_rig.duration)
	_marks = {"pass0": WHITE_HOLD, "pass1": WHITE_HOLD + PASS_TIME}
	_marks["fly"] = float(_marks.pass1) + AFTER_PASS
	_marks["land"] = float(_marks.fly) + FLY_IN
	_marks["clip"] = float(_marks.land) + SETTLE
	_marks["end"] = float(_marks.clip) + _clip_len
	# the scene: she stands at the wardrobe (clip frame 0, the door wide open), the crow is not on its sill, the camera is on the window
	_player.intro = self
	_player.global_position = room.room_to_global(STAND)
	_player.show_wardrobe_frame(0)
	_player.request_heal()
	_player.sync_wound_visuals()
	if _wardrobe != null:
		_wardrobe.frame = 9
	if _crow != null:
		_crow.hide_for_intro()
		_crow.landing.connect(func() -> void: _play(SND_LAND, -6.0))
		_crow.landed.connect(func() -> void: _play(SND_CAW, -12.0))
	_camera.position_smoothing_enabled = false
	_apply_camera()
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_wipe = Control.new()
	_wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wipe.draw.connect(_draw_wipe)
	_layer.add_child(_wipe)
	_sprite = Sprite2D.new()
	_sprite.texture = CROW
	_sprite.hframes = _edges.size()
	_sprite.centered = false
	_sprite.visible = false
	_layer.add_child(_sprite)
	_play(SND_AIR, -14.0)


func elapsed() -> float:
	return _t


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var vp: Vector2 = _vp()
	var pass0: float = _marks.pass0
	var pass1: float = _marks.pass1
	# the great crow
	if _t >= pass0 and _t <= pass1 + 0.05:
		if not _fired.has("pass"):
			_fired["pass"] = true
			_play(SND_PASS, -3.0)
		var k: float = clampf((_t - pass0) / PASS_TIME, 0.0, 1.0)
		var x0: float = -float(_frame_center.x) * 0.5 - 40.0
		var x1: float = vp.x + float(_frame_center.x) * 0.5 + 60.0
		_crow_x = roundf(lerpf(x0, x1, k)) ## one steady speed from edge to edge: it never visibly slows down
		_frame = int((_t - pass0) * FLAP_FPS) % _edges.size()
		var beat: float = 2.0 * PI * float(_frame) / float(_edges.size())
		var top: float = roundf(vp.y / 2.0 - float(_frame_center.y) + 12.0 * sin(PI * k) - 3.0 * sin(beat)) ## a slow arc, and the body rises a little with every beat
		_sprite.visible = true
		_sprite.frame = _frame
		_sprite.position = Vector2(_crow_x - float(_frame_center.x), top)
		_spawn_feathers(vp)
	else:
		_sprite.visible = false
	_step_feathers(delta)
	# the small crow
	if _t >= float(_marks.fly) and not _fired.has("fly") and _crow != null:
		_fired["fly"] = true
		_crow.fly_in(FLY_IN)
	_apply_camera()
	_clip()
	_wipe.queue_redraw()
	if _t >= float(_marks.end):
		_finish()


func _camera_state() -> Array:
	var close: Vector2 = _room.room_to_global(WINDOW_FOCUS)
	var wide: Vector2 = _clamped_base(1.0) ## where the game's own camera rests (it follows her inside the limits of the room and the hallway with its rooms)
	var clip0: float = _marks.clip
	_zoom_hold = ZOOM_CLOSE * (1.0 + 0.05 * clampf(_t / clip0, 0.0, 1.0)) ## a slow push-in while she waits
	if _t < clip0:
		return [_zoom_hold, close]
	var k: float = clampf((_t - clip0) / _clip_len, 0.0, 1.0)
	var e: float = k * k * k * (k * (k * 6.0 - 15.0) + 10.0)
	return [exp(lerpf(log(_zoom_hold), 0.0, e)), close.lerp(wide, e)]


func _apply_camera() -> void:
	var state: Array = _camera_state()
	_camera.zoom = Vector2.ONE * float(state[0])
	_player.view_shift = (state[1] as Vector2) - _clamped_base(float(state[0]))


## Where the camera really looks before its offset: Godot clamps the camera's own position to the limits (for the zoom) and adds the offset afterwards.
func _clamped_base(zoom: float) -> Vector2:
	var base: Vector2 = _player.global_position + _camera.position
	var half: Vector2 = _vp() / zoom / 2.0
	var lo: Vector2 = Vector2(_camera.limit_left, _camera.limit_top) + half
	var hi: Vector2 = Vector2(_camera.limit_right, _camera.limit_bottom) - half
	return Vector2(clampf(base.x, lo.x, hi.x) if lo.x <= hi.x else (lo.x + hi.x) / 2.0, clampf(base.y, lo.y, hi.y) if lo.y <= hi.y else (lo.y + hi.y) / 2.0)


## The wardrobe clip: her frames and the door of the wardrobe follow one clock.
func _clip() -> void:
	var clip0: float = _marks.clip
	var ct: float = maxf(0.0, _t - clip0)
	var frames: int = int(_rig.frames)
	var idx: int = mini(int(ct * float(_rig.fps)), frames - 1)
	_player.show_wardrobe_frame(idx)
	if _wardrobe != null:
		var door: Array = _rig.door as Array
		_wardrobe.frame = clampi(roundi(float(door[idx]) / 10.0), 0, 10)
	if _t >= clip0 + 0.85 and not _fired.has("creak"):
		_fired["creak"] = true
		_play(SND_CREAK, -6.0)
	if _t >= clip0 + float(_rig.thud) and not _fired.has("thud"):
		_fired["thud"] = true
		_play(SND_THUD, -2.0)
		_player.add_shake(2.5)


func _draw_wipe() -> void:
	var vp: Vector2 = _vp()
	var pass0: float = _marks.pass0
	var pass1: float = _marks.pass1
	if _t < pass0:
		_wipe.draw_rect(Rect2(Vector2.ZERO, vp), Color.WHITE)
	elif _t <= pass1:
		var top: int = int(roundf(_sprite.position.y))
		var left: int = int(roundf(_sprite.position.x))
		var edge: PackedInt32Array = _edges[_frame]
		var run_start: int = 0
		var run_x: int = -1
		for y: int in int(vp.y) + 1:
			var x: int = clampi(left + edge[clampi(y - top, 0, edge.size() - 1)], 0, int(vp.x)) if y < int(vp.y) else -2
			if x != run_x:
				if run_x >= 0 and run_x < int(vp.x):
					_wipe.draw_rect(Rect2(run_x, run_start, vp.x - run_x, y - run_start), Color.WHITE)
				run_start = y
				run_x = x
	for feather: Dictionary in _feathers:
		_draw_feather(feather)


func _spawn_feathers(vp: Vector2) -> void:
	for i: int in FEATHER_TIMES.size():
		var key: String = "feather%d" % i
		if _t >= float(_marks.pass0) + FEATHER_TIMES[i] and not _fired.has(key):
			_fired[key] = true
			_feathers.append({
				"pos": Vector2(_crow_x - randf_range(40.0, 150.0), randf_range(vp.y * 0.18, vp.y * 0.82)),
				"vel": Vector2(randf_range(160.0, 260.0), randf_range(-40.0, 30.0)),
				"angle": randf_range(0.0, TAU),
				"spin": randf_range(-2.5, 2.5),
				"phase": randf_range(0.0, TAU),
				"age": 0.0,
				"life": randf_range(4.2, 5.4),
			})


func _step_feathers(delta: float) -> void:
	for feather: Dictionary in _feathers:
		feather.age = float(feather.age) + delta
		var vel: Vector2 = feather.vel as Vector2
		vel.x = move_toward(vel.x, 0.0, 190.0 * delta) ## they are thrown out by the wind of the wings and then float down
		vel.y = move_toward(vel.y, 26.0, 60.0 * delta)
		feather.vel = vel
		var sway: float = sin(float(feather.age) * 2.4 + float(feather.phase)) * 22.0
		feather.pos = (feather.pos as Vector2) + (vel + Vector2(sway, 0.0)) * delta
		feather.angle = float(feather.angle) + float(feather.spin) * delta
	_feathers = _feathers.filter(func(f: Dictionary) -> bool: return float(f.age) < float(f.life))


func _draw_feather(feather: Dictionary) -> void:
	var fade: float = clampf((float(feather.life) - float(feather.age)) / 0.8, 0.0, 1.0)
	var dir: Vector2 = Vector2.from_angle(float(feather.angle))
	var turn: float = cos(float(feather.age) * 3.0 + float(feather.phase)) ## it tumbles: sometimes edge on
	var side: Vector2 = Vector2(-dir.y, dir.x)
	for i: int in 11:
		var p: Vector2 = (feather.pos as Vector2) + dir * float(i - 5)
		var shaft: bool = i < 9
		_wipe.draw_rect(Rect2(p.round(), Vector2.ONE), Color(0.11, 0.14, 0.22, fade))
		if shaft and absf(turn) > 0.35 and i > 1:
			var vane: Vector2 = (p + side * signf(turn)).round()
			_wipe.draw_rect(Rect2(vane, Vector2.ONE), Color(0.2, 0.25, 0.36, fade) if i % 2 == 0 else Color(0.07, 0.08, 0.14, fade))


func _play(stream: AudioStream, volume_db: float) -> void:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _finish() -> void:
	_done = true
	_camera.zoom = Vector2.ONE
	_player.view_shift = Vector2.ZERO
	_camera.position_smoothing_enabled = true
	_player.end_room_intro(_room.room_to_global(STAND))
	if _wardrobe != null:
		_wardrobe.frame = 0
	if _crow != null:
		_crow.scripted = false
	_layer.queue_free()
	_player.quests.start("take_broom")
	finished.emit()
	queue_free()
