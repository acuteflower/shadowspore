class_name DrinkEffect
extends Node2D
## What surrounds the quick drinking animation (docs/alchemie_konzept.md; the sheet `player_drink.png` and the right arm do the body): the vial in her right hand
## (pulled from the belt, the cork flicked off with a pop, tipped to her mouth), the potion's light when it takes effect (Wundtau: rose light runs down her body;
## Glutatem: amber sparks rise from her feet), then the empty vial tossed over her shoulder that shatters on the ground behind her. The body part follows the
## animation time the player hands in (`show_state`); the tossed vial and its shards keep their own clock and stay where they fell, so they outlive the
## 0.6 s animation. Every peer runs it from the replicated action. Unlit: it glows at night. Sounds: tools/audio_alchemy.py.

const DURATION: float = 0.6 ## the animation (Player.DRINK_SECONDS)
const PULL: float = 0.07 ## the vial leaves the belt
const CORK: float = 0.14 ## the thumb flicks the cork off
const SIP: float = 0.21 ## the vial is at her lips
const EFFECT: float = 0.30 ## the draught: the potion takes effect (Player.DRINK_USE_TIME)
const TOSS: float = 0.44 ## the empty vial leaves the hand
const FLIGHT: float = 0.32 ## seconds of its flight
const SHARDS: float = 0.55 ## seconds the shards glint
const GLASS: Color = Color("cfe6f2")
const GLASS_DARK: Color = Color("6a7a96")
const CORK_COLOR: Color = Color("8a5a3a")
const INK: Color = Color("1b1a2e")
const SOUNDS: Dictionary = {
	"cork": preload("res://assets/audio/alchemy/cork.wav"), "gulp": preload("res://assets/audio/alchemy/gulp.wav"),
	"glass": preload("res://assets/audio/alchemy/glass.wav"), "heal": preload("res://assets/audio/alchemy/heal.wav"),
	"stamina": preload("res://assets/audio/alchemy/stamina.wav"),
}

var _type: String = "" ## "heal" / "stamina", "" = idle
var _tier: int = 1
var _t: float = -1.0 ## animation time while she holds the vial
var _hand: Vector2 = Vector2.ZERO
var _mouth: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.DOWN
var _played: Dictionary = {}
var _thrown: Array[Dictionary] = [] ## {from (global), to (global), age, color} - a tossed vial and then its shards
var _cork_from: Vector2 = Vector2.ZERO


func _ready() -> void:
	z_index = 6
	material = Unlit.material()
	set_process(false)


## The animation starts: which potion she drinks.
func begin(type: String, tier: int) -> void:
	_type = type
	_tier = clampi(tier, 1, 5)
	_t = 0.0
	_played.clear()
	set_process(true)
	queue_redraw()


## Called every frame of the animation with its time, the hand and the mouth (px from the feet) and where she faces.
func show_state(time: float, hand: Vector2, mouth: Vector2, facing: Vector2) -> void:
	if _type == "":
		return
	if time >= CORK and _t < CORK:
		_cork_from = hand + Vector2(0, -4)
	_t = time
	_hand = hand
	_mouth = mouth
	if facing != Vector2.ZERO:
		_facing = facing.normalized()
	_cue("cork", CORK, -10.0)
	_cue("gulp", SIP + 0.02, -9.0)
	_cue(_type, EFFECT, -8.0)
	if time >= TOSS and not _played.has("toss"):
		_played["toss"] = true
		var from: Vector2 = to_global(hand)
		var back: Vector2 = -_facing * 26.0 + Vector2(_facing.y, -_facing.x) * 8.0
		_thrown.append({"from": from, "to": global_position + back, "age": 0.0, "color": AlchemyRules.color(_type)})
	queue_redraw()


## The animation is over (or broke off): the vial leaves her hand; what is already flying finishes on its own.
func clear() -> void:
	if _t >= 0.0:
		_t = -1.0
		_type = "" if _thrown.is_empty() else _type
		queue_redraw()


func _cue(id: String, at: float, volume: float) -> void:
	if _t >= at and not _played.has(id) and SOUNDS.has(id):
		_played[id] = true
		if DisplayServer.get_name() == "headless":
			return
		var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		voice.stream = SOUNDS[id] as AudioStream
		voice.volume_db = volume
		voice.pitch_scale = randf_range(0.94, 1.06)
		voice.max_distance = 320.0
		add_child(voice)
		voice.finished.connect(voice.queue_free)
		voice.play()


func _process(delta: float) -> void:
	for i: int in range(_thrown.size() - 1, -1, -1):
		var v: Dictionary = _thrown[i]
		v.age = float(v.age) + delta
		if float(v.age) >= FLIGHT and not bool(v.get("broke", false)):
			v.broke = true
			_shatter_sound(v.to as Vector2)
		if float(v.age) > FLIGHT + SHARDS:
			_thrown.remove_at(i)
	if _t < 0.0 and _thrown.is_empty():
		_type = ""
		set_process(false)
	queue_redraw()


func _shatter_sound(at: Vector2) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.stream = SOUNDS["glass"] as AudioStream
	voice.volume_db = -12.0
	voice.pitch_scale = randf_range(0.92, 1.1)
	voice.max_distance = 320.0
	get_tree().current_scene.add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	voice.play()


func _draw() -> void:
	var tone: Color = AlchemyRules.color(_type) if _type != "" else Color.WHITE
	var shine: Color = AlchemyRules.light(_type) if _type != "" else Color.WHITE
	if _t >= PULL and _t < TOSS:
		var tilt: float = 0.0
		if _t >= SIP:
			tilt = clampf((_t - SIP) / 0.06, 0.0, 1.0) * (1.0 - clampf((_t - 0.36) / 0.06, 0.0, 1.0)) ## tipped up to the lips
		var fill: float = 1.0 - clampf((_t - SIP) / (EFFECT + 0.04 - SIP), 0.0, 1.0) ## it empties in one draught
		_vial(_hand + Vector2(0, -2), tilt, fill, tone, shine, _t < CORK, 1.0)
	if _t >= CORK and _t < CORK + 0.3: ## the cork flies off and tumbles
		var age: float = _t - CORK
		var at: Vector2 = _cork_from + Vector2(-_facing.x * 14.0 * age + 9.0 * age, -40.0 * age + 140.0 * age * age)
		_dot(at, CORK_COLOR)
		_dot(at + Vector2(1, 0), Color(CORK_COLOR.lightened(0.25), 0.9))
	if _t >= SIP and _t < EFFECT + 0.05: ## drops at her lips
		for k: int in 3:
			var phase: float = fposmod(_t * 9.0 + k * 0.33, 1.0)
			_dot(_mouth + Vector2(-1 + k, 1 + phase * 4.0), Color(shine, 0.8 * (1.0 - phase)))
	if _t >= EFFECT:
		_draw_effect(_t - EFFECT, tone, shine)
	for v: Dictionary in _thrown:
		_draw_thrown(v)


## The potion takes effect: Wundtau = rose light runs down from her mouth to her feet with a soft ring at the end; Glutatem = amber sparks rise round her.
func _draw_effect(since: float, tone: Color, shine: Color) -> void:
	var strength: float = 0.6 + 0.1 * float(_tier)
	if since < 0.12: ## a flash at the mouth
		var size: int = 1 + int((1.0 - since / 0.12) * 3.0)
		for d: int in range(-size, size + 1):
			_dot(_mouth + Vector2(d, 0), Color(shine, 1.0 - since / 0.12))
			_dot(_mouth + Vector2(0, d), Color(shine, 1.0 - since / 0.12))
	if _type == "heal":
		var front: float = since / 0.28 ## 0 at the mouth .. 1 at the feet
		if front <= 1.3:
			var y: float = lerpf(_mouth.y, 0.0, clampf(front, 0.0, 1.0))
			for x: int in range(-6, 7):
				var a: float = (1.0 - absf(float(x)) / 7.0) * strength * (1.0 - clampf(front - 1.0, 0.0, 0.3) / 0.3)
				_dot(Vector2(x, y), Color(tone.lerp(shine, 0.4), a))
				_dot(Vector2(x, y - 2), Color(tone, a * 0.4))
		var ring_age: float = since - 0.24
		if ring_age > 0.0 and ring_age < 0.4:
			var k: float = ring_age / 0.4
			var radius: float = 6.0 + 12.0 * k
			for i: int in 28:
				var angle: float = i * TAU / 28.0
				draw_rect(Rect2(Vector2(cos(angle) * radius, sin(angle) * radius * 0.4 - 1.0).round(), Vector2(2, 1)), Color(shine, (1.0 - k) * strength))
	else:
		for i: int in 10 + 2 * _tier:
			var start: float = float(i % 5) * 0.05
			var age: float = since - start
			if age < 0.0 or age > 0.6:
				continue
			var angle: float = float(i) * 2.399
			var x: float = cos(angle) * (6.0 + float(i % 3) * 3.0) + sin(age * 14.0 + i) * 1.5
			var y: float = -2.0 - age * (40.0 + float(i % 4) * 8.0)
			_dot(Vector2(x, y), Color(tone.lerp(shine, float(i % 2) * 0.6), (1.0 - age / 0.6) * strength))
		if since < 0.3:
			var k2: float = since / 0.3
			for i: int in 24:
				var a2: float = i * TAU / 24.0
				_dot(Vector2(cos(a2) * (5.0 + 10.0 * k2), sin(a2) * (2.0 + 4.0 * k2) - 1.0), Color(tone, (1.0 - k2) * strength))


## The tossed vial: an arc backwards, a little spin; on landing a splash of shards that glint and fade where it fell.
func _draw_thrown(v: Dictionary) -> void:
	var age: float = float(v.age)
	var from: Vector2 = to_local(v.from as Vector2)
	var to: Vector2 = to_local(v.to as Vector2)
	var color: Color = v.color as Color
	if age < FLIGHT:
		var u: float = age / FLIGHT
		var at: Vector2 = from.lerp(to, u) + Vector2(0, -sin(u * PI) * 16.0)
		_vial(at, u * 5.0, 0.0, color, color, false, 1.0)
		return
	var since: float = age - FLIGHT
	var fade: float = 1.0 - since / SHARDS
	for i: int in 9:
		var angle: float = float(i) * 0.7 + 0.3
		var reach: float = (5.0 + float(i % 3) * 3.0) * minf(since * 9.0, 1.0)
		var at2: Vector2 = to + Vector2(cos(angle) * reach, sin(angle) * reach * 0.45)
		var glint: bool = fposmod(since * 7.0 + float(i) * 0.37, 1.0) < 0.3
		_dot(at2, Color(GLASS if glint else GLASS_DARK, fade))
	if since < 0.2: ## the last drops splash
		for i: int in 5:
			var a: float = float(i) * TAU / 5.0
			_dot(to + Vector2(cos(a), sin(a) * 0.5) * (2.0 + since * 30.0) + Vector2(0, -since * 10.0), Color(color, 1.0 - since / 0.2))


## A small vial (3 wide, 6 tall), `tilt` in radians (0 = upright), `fill` 0..1 of the potion, with or without its cork.
func _vial(at: Vector2, tilt: float, fill: float, tone: Color, shine: Color, corked: bool, alpha: float) -> void:
	var up: Vector2 = Vector2(sin(tilt), -cos(tilt))
	var side: Vector2 = Vector2(-up.y, up.x)
	var base: Vector2 = at.round()
	for row: int in 6:
		var half: int = 0 if row >= 4 else 1 ## a round body below, a narrow neck on top
		for col: int in range(-half, half + 1):
			var p: Vector2 = base + up * float(row) + side * float(col)
			var liquid: bool = row < 4 and float(row) / 4.0 < fill
			var c: Color = tone if liquid else GLASS_DARK
			if liquid and col == -1 and row == 2:
				c = shine
			if row == 0 or absi(col) == half and row < 4 and not liquid:
				c = c.darkened(0.25)
			_dot(p, Color(c, alpha))
	_dot(base + up * 1.0 + side * -1.0, Color(GLASS, 0.85 * alpha)) ## a glint on the glass
	if corked:
		_dot(base + up * 6.0, Color(CORK_COLOR, alpha))
	_dot(base + up * -1.0, Color(INK, 0.6 * alpha))


func _dot(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at.round(), Vector2.ONE), color)
