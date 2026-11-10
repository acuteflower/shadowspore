class_name MusicDirector
extends Node
## The game's music: one looping track each for the day, the night, a fight and a boss fight, cross-faded.
## Local and cosmetic, every peer runs its own. `DayNight` creates it and sets `night` / `indoors` every frame.
## Tracks are `assets/audio/music/<day|night|combat|boss>.(ogg|mp3)`; a missing file is simply silent.
## Plays on the bus "Music" (made by `GameSettings.apply`, volume = the MUSIK slider).

const FOLDER: String = "res://assets/audio/music/"
const NAMES: Array[String] = ["day", "night", "combat", "boss"]
const DAY: int = 0
const NIGHT: int = 1
const COMBAT: int = 2
const BOSS: int = 3
const LEVEL_DB: Array[float] = [-12.0, -11.0, -9.0, -8.0]
const INDOOR_DB: float = -7.0 ## rooms and the mine: the same track, further away
const FADE_IN: Array[float] = [5.0, 5.0, 1.2, 0.8] ## seconds
const FADE_OUT: Array[float] = [3.0, 3.0, 4.0, 5.0]
const COMBAT_RANGE: float = 160.0 ## a shadow creature this close to the camera's middle = a fight
const BOSS_RANGE: float = 620.0
const COMBAT_HOLD: float = 6.0 ## seconds the fight track stays after the last creature left or fell
const CHECK_SECONDS: float = 0.25

var night: float = 0.0 ## 0 day .. 1 night (the Hexenwald's gloom counts as night)
var indoors: bool = false

var _players: Array[AudioStreamPlayer] = []
var _amount: Array[float] = [0.0, 0.0, 0.0, 0.0] ## 0..1 share of each track
var _current: int = DAY
var _hold: float = 0.0
var _check: float = 0.0
var _threat: int = -1 ## COMBAT, BOSS or -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS ## the music plays on in the pause menu
	GameSettings.apply() ## makes sure the bus exists
	for i: int in NAMES.size():
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.stream = _load(NAMES[i])
		p.bus = &"Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


func _load(track: String) -> AudioStream:
	for ext: String in ["ogg", "mp3"]:
		var path: String = FOLDER + track + "." + ext
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			elif stream is AudioStreamMP3:
				(stream as AudioStreamMP3).loop = true
			return stream
	return null


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_SECONDS
		_threat = _sense()
	if _threat >= 0:
		_hold = COMBAT_HOLD
	elif not get_tree().paused:
		_hold = maxf(_hold - delta, 0.0)
	var want: int = wanted(night, _threat, _hold, _current)
	_current = want
	for i: int in _players.size():
		var target: float = 1.0 if i == want else 0.0
		var seconds: float = FADE_IN[i] if target > _amount[i] else FADE_OUT[i]
		_amount[i] = move_toward(_amount[i], target, delta / seconds)
		_apply(i)


## Pure: which track should play. `threat` = BOSS, COMBAT or -1; a fight track lingers for `hold` seconds.
static func wanted(night_amount: float, threat: int, hold: float, current: int) -> int:
	if threat >= 0:
		return threat
	if hold > 0.0 and (current == COMBAT or current == BOSS):
		return current
	return NIGHT if night_amount > 0.5 else DAY


func _apply(i: int) -> void:
	var p: AudioStreamPlayer = _players[i]
	if p.stream == null:
		return
	var amount: float = _amount[i]
	if amount <= 0.001:
		if i >= COMBAT:
			p.stop() ## a fight always starts from its first bar
		elif p.playing:
			p.stream_paused = true ## day and night go on where they stopped
		return
	if p.stream_paused:
		p.stream_paused = false
	elif not p.playing:
		p.play()
	var level: float = LEVEL_DB[i] + (INDOOR_DB if indoors and i < COMBAT else 0.0)
	p.volume_db = level + linear_to_db(amount * amount)


## A living boss near the camera, else a living shadow creature close to it. Duck typed: no enemy classes named here.
func _sense() -> int:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return -1
	var at: Vector2 = camera.get_screen_center_position()
	for node: Node in get_tree().get_nodes_in_group("bosses"):
		if _alive(node) and (node as Node2D).global_position.distance_to(at) < BOSS_RANGE:
			return BOSS
	for node: Node in get_tree().get_nodes_in_group("predators"):
		if node.get("enemy_id") == null: ## bears are predators too, but no fight music for wildlife
			continue
		if _alive(node) and (node as Node2D).global_position.distance_to(at) < COMBAT_RANGE:
			return COMBAT
	return -1


func _alive(node: Node) -> bool:
	if not (node is Node2D) or not (node as Node2D).is_visible_in_tree():
		return false
	var health: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
	return health == null or health.current > 0.0
