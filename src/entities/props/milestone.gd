class_name Milestone
extends Interactable
## A milestone of the Westweg (docs/stadt_westen_konzept.md 2.4, art: tools/art_milestone.py): a squat stele with the distance to Hallgrat
## chiselled in and a small crystal in its crown. Far out the stone is old and its crystal dead; from 150 on the crystal glints violet, the last
## one (50) flickers teal at night. E reads it: the inscription and one of Ellie's thoughts appear in the speech box, and the crystal answers
## with its note of the town's four-note motif (a dead one only knocks). Placed by `Hallgrat` from data/hallgrat.json "milestones".
## Nothing is decided by the host: reading is local and changes nothing.
const ART: Texture2D = preload("res://assets/props/milestone.png")
const GLOW: Texture2D = preload("res://assets/props/milestone_glow.png")
const FRAME: Vector2i = Vector2i(40, 52)
const GROUND: int = 46 ## the ground row of a frame
const FIRST: int = 50 ## the number of frame 0; every frame is 50 more (art_milestone.py NUMBERS)
const STEP: int = 50
const TONES: Array[String] = ["res://assets/audio/hallgrat/tone_0.wav", "res://assets/audio/hallgrat/tone_1.wav",
	"res://assets/audio/hallgrat/tone_2.wav", "res://assets/audio/hallgrat/tone_3.wav"]

var number: int = 50
var _glow: Sprite2D
var _light: NightLight
var _time: float = 0.0
var _rang: float = 0.0 ## seconds since the crystal last answered (it brightens when read)


func _ready() -> void:
	_time = fposmod(position.x * 0.013 + position.y * 0.007, 10.0)
	var frame: int = clampi((number - FIRST) / STEP, 0, ART.get_width() / FRAME.x - 1)
	for tex: Texture2D in [ART, GLOW]:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		sprite.hframes = tex.get_width() / FRAME.x
		sprite.frame = frame
		sprite.offset = Vector2(0, -(GROUND - FRAME.y / 2))
		if tex == GLOW:
			sprite.material = Unlit.material()
			_glow = sprite
		add_child(sprite)
	if lit():
		_light = NightLight.new()
		_light.position = Vector2(0, -34)
		_light.radius = 22 if number <= 50 else 14
		_light.base_energy = 0.55 if number <= 50 else 0.25
		_light.glow_color = Color("78f4e6") if number <= 50 else Color("b99bff")
		add_child(_light)
	var body: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var box: RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(16, 6)
	shape.shape = box
	shape.position = Vector2(0, -3)
	body.add_child(shape)
	add_child(body)
	_rang = 99.0


## The crystal still holds some light (from 150 on).
func lit() -> bool:
	return number <= 150


## The note of the motif this stone carries (0..3): the stones count the motif down towards the town.
func tone() -> int:
	return (number / STEP) % 4


func _process(delta: float) -> void:
	_time += delta
	_rang += delta
	var night: float = TimeManager.night_amount()
	var answer: float = clampf(1.0 - _rang / 2.4, 0.0, 1.0)
	if number <= 50: ## the last stone: alive, but uneven, like a lamp that is not sure of itself
		var flicker: float = 0.75 + 0.25 * sin(_time * 7.3) * sin(_time * 2.1 + 1.3)
		if fposmod(_time, 5.7) < 0.12:
			flicker *= 0.35
		_glow.modulate.a = clampf(lerpf(0.4, 1.0, night) * flicker + answer, 0.0, 1.0)
	elif lit():
		_glow.modulate.a = clampf(lerpf(0.15, 0.55, night) * (0.8 + 0.2 * sin(_time * 0.9)) + answer * 0.8, 0.0, 1.0)
	else:
		_glow.modulate.a = 0.0
	if _light != null:
		_light.base_energy = (0.55 if number <= 50 else 0.25) * (1.0 + answer)


func prompt() -> String:
	return "LESEN"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 10.0


func prompt_position() -> Vector2:
	return Vector2(0, -44)


func interact(_player: Player) -> void:
	_rang = 0.0
	_sound(TONES[tone()] if lit() else "res://assets/audio/hallgrat/tone_dead.wav", -6.0)
	_sound("res://assets/audio/hallgrat/touch.wav", -12.0)
	var box: SpeechBox = get_tree().get_first_node_in_group("speech_box") as SpeechBox
	if box == null:
		return
	var town: Dictionary = DataRegistry.table("hallgrat")
	var texts: Dictionary = town.get("milestone_text", {}) as Dictionary
	box.speak(String(texts.get("speaker", "MEILENSTEIN")), String(texts.get("inscription", "HALLGRAT %d")) % number, 2.6)
	var band: String = "last" if number <= 50 else ("near" if number <= 150 else ("mid" if number <= 400 else "far"))
	var pool: Array = (texts.get("thoughts", {}) as Dictionary).get(band, []) as Array
	if not pool.is_empty():
		box.speak("ELLIE", String(pool[(number / STEP) % pool.size()]))


func _sound(path: String, db: float) -> void:
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = load(path) as AudioStream
	player.bus = "SFX"
	player.volume_db = db
	player.position = Vector2(0, -34)
	player.max_distance = 420.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()
