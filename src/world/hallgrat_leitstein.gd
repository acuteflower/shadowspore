class_name HallgratLeitstein
extends Interactable
## A guide stone (Leitstein) of Hallgrat (docs/stadt_westen_konzept.md 8.1, stage 3c; art by tools/art_hallgrat_houses.py `leitstein`): a slender
## post of the Glaskamm's stone with a crystal of Klangstein in its head. The town still sleeps, so the crystal only remembers its light (a dim
## violet that comes and goes at night); the stone of the lost quarter is dead. E strikes it: it sounds its note of the town's four-note motif
## (`tone` 0..3 in data/hallgrat.json `leitsteine`) and the crystal flares for a moment. Local only, changes nothing; the awakening (stage 4)
## will light them for good.
const DIR: String = "res://assets/town/hallgrat/"
const TONES: Array[String] = ["res://assets/audio/hallgrat/tone_0.wav", "res://assets/audio/hallgrat/tone_1.wav",
	"res://assets/audio/hallgrat/tone_2.wav", "res://assets/audio/hallgrat/tone_3.wav"]

var tone: int = 0
var dead: bool = false
var _glow: Sprite2D
var _time: float = 0.0
var _struck: float = 99.0


func _ready() -> void:
	var type: String = "leitstein_tot" if dead else "leitstein"
	var info: Dictionary = (DataRegistry.table("hallgrat_art").get("types", {}) as Dictionary).get(type, {}) as Dictionary
	var feet: Vector2 = Vector2(float((info.get("feet", [9, 26]) as Array)[0]), float((info.get("feet", [9, 26]) as Array)[1]))
	for glow: bool in [false, true]:
		var path: String = DIR + type + ("_glow.png" if glow else ".png")
		if not ResourceLoader.exists(path):
			continue
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = load(path) as Texture2D
		sprite.centered = false
		sprite.offset = -feet
		if glow:
			sprite.material = Unlit.material()
			_glow = sprite
		add_child(sprite)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(8, 4)
	shape.shape = box
	shape.position = Vector2(0, -2)
	body.add_child(shape)
	add_child(body)
	_time = fposmod(position.x * 0.017 + position.y * 0.011, 9.0)


func _process(delta: float) -> void:
	_time += delta
	_struck += delta
	if _glow == null:
		return
	var night: float = TimeManager.night_amount()
	var remember: float = 0.12 + 0.18 * maxf(0.0, sin(_time * 0.7 + tone)) * maxf(0.0, sin(_time * 1.9))  # it comes and goes, never steady
	var flare: float = clampf(1.0 - _struck / 2.2, 0.0, 1.0)
	_glow.modulate.a = clampf(remember * lerpf(0.3, 1.0, night) + flare, 0.0, 1.0)


func prompt() -> String:
	return "ANSCHLAGEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 8.0


func prompt_position() -> Vector2:
	return Vector2(0, -36)


func interact(_player: Player) -> void:
	_struck = 0.0
	var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	sound.stream = load("res://assets/audio/hallgrat/tone_dead.wav" if dead else TONES[tone % 4]) as AudioStream
	sound.bus = "SFX"
	sound.volume_db = -4.0
	sound.position = Vector2(0, -24)
	sound.max_distance = 600.0
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()
