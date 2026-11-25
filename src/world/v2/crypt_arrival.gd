class_name CryptArrival
extends Node
## Der Story-Start (neues Spiel): Schwarzblende mit drei Texttafeln (Ende der Kanalflucht, docs/storyboard.md 4.5), dann zieht sich
## Ellie verwundet aus dem Kanalschacht in der Krypta unter dem Sternenauge (Innenraum `sternenauge_krypta`). Kind des lokalen Spielers,
## nur Host/Solo (GameLauncher -> ZoneWorld.start_intro). Spielt die Bilder von assets/characters/player_emerge.png nach der Zeitleiste
## in data/hero_rig.json "emerge" (ohne den Deckel-Teil: das Gitter liegt schon neben dem Schacht), blendet aus dem Schwarz auf und gibt
## am Ende die Steuerung zurück (`Player.end_wake`: HUD wächst ein, keine Quest). Taste E / Angriff überspringt die Texttafeln.

const SHEET: Texture2D = preload("res://assets/characters/player_emerge.png")
const SOUNDS: Dictionary = {
	"gasp": preload("res://assets/audio/intro/gasp.wav"),
	"thud": preload("res://assets/audio/intro/body_thud.wav"),
	"cough": preload("res://assets/audio/intro/cough.wav"),
	"heartbeat": preload("res://assets/audio/intro/heartbeat.wav"),
}
const LINES: Array[String] = [
	"ICH WEISS NICHT, WIE LANGE ICH GELAUFEN BIN.",
	"IRGENDWANN BIN ICH NUR NOCH GEKROCHEN.",
	"DANN WAR ÜBER MIR STEIN. UND LICHT.",
]
const LINE_TIME: float = 2.8 ## Sekunden je Tafel (ein-, stehen, ausblenden)
const SKIP_TO: float = 1.65 ## ab hier spielt die Kletterzeitleiste (Klopfen & Deckel entfallen)
const FADE: float = 1.5
const HINT_DELAY: float = 1.2

var _player: Player
var _anchor: Vector2 = Vector2.ZERO ## Weltpunkt im Schacht, aus dem sie steigt
var _layer: CanvasLayer
var _overlay: ColorRect
var _text: Control
var _cards: bool = true
var _card_time: float = 0.0
var _time: float = SKIP_TO
var _fps: float = 12.0
var _frames: int = 1
var _duration: float = 6.5
var _offsets: PackedVector2Array = PackedVector2Array()
var _events: Dictionary = {}
var _fired: Dictionary = {}


## Startet die Szene am lokalen `player`; `anchor` = Weltpunkt im Schacht (Raum-px "shaft" der Krypta).
func start(player: Player, anchor: Vector2) -> void:
	name = "CryptArrival"
	_player = player
	_anchor = anchor
	var rig: Dictionary = DataRegistry.table("hero_rig").get("emerge", {}) as Dictionary
	_fps = float(rig.get("fps", 12))
	_frames = int(rig.get("frames", 1))
	_duration = float(rig.get("duration", 6.5))
	_events = rig.get("events", {}) as Dictionary
	for point: Variant in rig.get("offset", []) as Array:
		var p: Array = point as Array
		_offsets.append(Vector2(float(p[0]), float(p[1])))
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_overlay)
	_text = Control.new()
	_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.draw.connect(_draw_card)
	_layer.add_child(_text)
	player.begin_intro(self)
	_place(SKIP_TO)
	_play("heartbeat", -8.0)


func _unhandled_input(event: InputEvent) -> void:
	if _cards and _card_time > 0.6 and (event.is_action_pressed("interact") or event.is_action_pressed("action_primary") or event.is_action_pressed("ui_accept")):
		_card_time = float(LINES.size()) * LINE_TIME
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _cards:
		_card_time += delta
		_text.queue_redraw()
		if _card_time >= float(LINES.size()) * LINE_TIME:
			_cards = false
			_text.visible = false
		return
	_time += delta
	_place(_time)
	_overlay.color.a = 1.0 - smoothstep(SKIP_TO, SKIP_TO + FADE, _time)
	for event_name: String in _events:
		var at: float = float(_events[event_name])
		if at >= SKIP_TO and _time >= at and not _fired.has(event_name):
			_fired[event_name] = true
			_fire(event_name)
	if _time >= _duration:
		_finish()


func _draw_card() -> void:
	var idx: int = int(_card_time / LINE_TIME)
	if idx >= LINES.size():
		return
	var local: float = fmod(_card_time, LINE_TIME)
	var a: float = smoothstep(0.0, 0.6, local) * (1.0 - smoothstep(LINE_TIME - 0.6, LINE_TIME, local))
	var line: String = LINES[idx]
	var view: Vector2 = _text.get_viewport_rect().size
	var w: float = HudText.width(line)
	HudText.draw(_text, line, Vector2((view.x - w) * 0.5, view.y * 0.5 - 4.0), Color(0.86, 0.80, 0.96), a)


## Wo sie steht und welches Bild zu `t` gehört.
func _place(t: float) -> void:
	var key: float = clampf(t * _fps - 0.5, 0.0, float(_frames - 1) - 0.001)
	var i: int = int(key)
	var offset: Vector2 = Vector2.ZERO
	if _offsets.size() == _frames:
		offset = _offsets[i].lerp(_offsets[mini(i + 1, _frames - 1)], key - float(i))
	_player.show_emerge_frame(SHEET, _frames, clampi(int(t * _fps), 0, _frames - 1), _anchor + offset)


func _fire(event_name: String) -> void:
	match event_name:
		"gasp":
			_play("gasp", -3.0)
		"over_rim":
			_player.add_shake(1.6)
		"thud":
			_play("thud", -1.0)
			_player.add_shake(3.0)
		"cough":
			_play("cough", -3.0)
			_player.add_shake(1.0)


func _play(sound_name: String, volume_db: float) -> void:
	var sound: AudioStreamPlayer = AudioStreamPlayer.new()
	sound.stream = SOUNDS[sound_name] as AudioStream
	sound.volume_db = volume_db
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()


func _finish() -> void:
	var end: Vector2 = _anchor + (_offsets[_offsets.size() - 1] if not _offsets.is_empty() else Vector2.ZERO)
	_player.end_wake(end)
	var tree: SceneTree = get_tree()
	tree.create_timer(HINT_DELAY).timeout.connect(func() -> void:
		HudNotices.post(tree, "medium", "crypt_stairs", {"header": "DIE KRYPTA", "text": "STEIG DIE TREPPE HINAUF", "color": Color("9fd8ff")}))
	queue_free()
