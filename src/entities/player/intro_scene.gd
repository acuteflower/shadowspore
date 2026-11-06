class_name IntroScene
extends Node
## The start of the story: Ellie is in the sewer, pushes the manhole lid aside from below and crawls out, hurt. Played once on a new game in
## singleplayer, a child of the local player. The player cannot do anything meanwhile (`Player.intro` makes the player skip movement,
## interaction and its own animation); this node plays the frames of assets/characters/player_emerge.png (art: tools/art_hero_emerge.py,
## timeline and events in data/hero_rig.json "emerge"), moves the player node along the baked offsets, grinds the lid aside, sifts dust out of
## the joint, plays the sounds (tools/audio_intro.py) and fades the screen in from black. At the end she stands beside the cover and gets control.

const SHEET: Texture2D = preload("res://assets/characters/player_emerge.png")
const SOUNDS: Dictionary = {
	"knock": preload("res://assets/audio/intro/knock.wav"),
	"scrape": preload("res://assets/audio/intro/lid_scrape.wav"),
	"thud": preload("res://assets/audio/intro/body_thud.wav"),
	"gasp": preload("res://assets/audio/intro/gasp.wav"),
	"cough": preload("res://assets/audio/intro/cough.wav"),
}
const FADE_FROM: float = 0.65 ## seconds: the screen stays black while the lid is struck from below, then fades in
const FADE_TO: float = 1.7
const LID_STEPS: float = 4.0 ## the lid grinds aside in this many jerks

var _player: Player
var _cover: ManholeCover
var _overlay: ColorRect
var _time: float = 0.0
var _fps: float = 10.0
var _frames: int = 1
var _duration: float = 10.0
var _offsets: PackedVector2Array = PackedVector2Array()
var _events: Dictionary = {}
var _fired: Dictionary = {}
var _lid_step: int = -1


## Starts the scene on the local `player` with `cover` as the way out.
func start(player: Player, cover: ManholeCover) -> void:
	_player = player
	_cover = cover
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("emerge", {}) as Dictionary)
	_fps = float(rig.get("fps", 10))
	_frames = int(rig.get("frames", 1))
	_duration = float(rig.get("duration", 10.0))
	_events = rig.get("events", {}) as Dictionary
	for point: Array in rig.get("offset", []):
		_offsets.append(Vector2(float(point[0]), float(point[1])))
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 90
	layer.add_child(_overlay)
	add_child(layer)
	cover.set_open(0.0)
	player.begin_intro(self)
	_place(0.0)


func _process(delta: float) -> void:
	_time += delta
	_place(_time)
	_overlay.color.a = 1.0 - smoothstep(FADE_FROM, FADE_TO, _time)
	for event_name: String in _events:
		if _time >= float(_events[event_name]) and not _fired.has(event_name):
			_fired[event_name] = true
			_fire(event_name)
	_lid(_time)
	if _time >= _duration:
		_finish()


## Where she is and which frame shows at `t`.
func _place(t: float) -> void:
	var key: float = clampf(t * _fps - 0.5, 0.0, float(_frames - 1) - 0.001)
	var i: int = int(key)
	var offset: Vector2 = _offsets[i].lerp(_offsets[mini(i + 1, _frames - 1)], key - float(i)) if _offsets.size() == _frames else Vector2.ZERO
	_player.show_emerge_frame(SHEET, _frames, clampi(int(t * _fps), 0, _frames - 1), _cover.position + offset)


## The lid grinds aside in jerks between lid_start and lid_end, a little dust each time it catches.
func _lid(t: float) -> void:
	var start: float = float(_events.get("lid_start", 1.7))
	var end: float = float(_events.get("lid_end", 2.5))
	if t < start:
		return
	var k: float = clampf((t - start) / (end - start), 0.0, 1.0) * LID_STEPS
	var step: int = mini(int(k), int(LID_STEPS) - 1) if t < end else int(LID_STEPS)
	_cover.set_open((floorf(minf(k, LID_STEPS)) + smoothstep(0.0, 0.5, fposmod(minf(k, LID_STEPS - 0.001), 1.0)) * (1.0 if t < end else 0.0)) / LID_STEPS)
	if step != _lid_step:
		_lid_step = step
		if step > 0:
			_cover.dust(Vector2(-6, -4), 6, 12.0)
			_player.add_shake(0.8)


func _fire(event_name: String) -> void:
	match event_name:
		"knock1", "knock2":
			_play("knock", -6.0 if event_name == "knock1" else -4.0)
			_jolt(1.0)
			_cover.dust(Vector2.ZERO, 5, 14.0)
			_player.add_shake(1.0)
		"jolt":
			_play("knock", 0.0)
			_jolt(2.5)
			_cover.dust(Vector2.ZERO, 14, 16.0)
			_player.add_shake(2.4)
		"lid_start":
			_play("scrape", -2.0)
		"hand":
			_cover.dust(Vector2(14, 4), 6, 6.0)
		"gasp":
			_play("gasp", -3.0)
		"over_rim":
			_player.add_shake(1.6)
			_cover.dust(Vector2(16, 6), 8, 8.0)
		"thud":
			_play("thud", -1.0)
			_player.add_shake(3.0)
			_cover.dust(Vector2(26, 8), 10, 8.0)
		"cough":
			_play("cough", -3.0)
			_player.add_shake(1.0)


## The lid hops up by `px` for a moment (struck from below).
func _jolt(px: float) -> void:
	_cover.set_jolt(Vector2(0.0, -px))
	var tween: Tween = create_tween()
	tween.tween_interval(0.07)
	tween.tween_callback(func() -> void: _cover.set_jolt(Vector2.ZERO))


func _play(sound_name: String, volume_db: float) -> void:
	var sound: AudioStreamPlayer = AudioStreamPlayer.new()
	sound.stream = SOUNDS[sound_name] as AudioStream
	sound.volume_db = volume_db
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()


func _finish() -> void:
	_cover.set_open(1.0)
	_cover.set_jolt(Vector2.ZERO)
	var end: Vector2 = _cover.position + (_offsets[_offsets.size() - 1] if not _offsets.is_empty() else Vector2.ZERO)
	_player.end_intro(end)
	queue_free()
