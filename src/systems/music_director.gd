class_name MusicDirector
extends Node
## The game's music: looping or multi-track rotating playlists for meadow day, Hexenwald day,
## quartz-desert day, global night, combat, and boss fights, smoothly cross-faded.
## Local and cosmetic, every peer runs its own. `DayNight` creates it and updates
## `night`, `gloom`, `arid` and `indoors` every frame.
## Tracks live in `assets/audio/music/<name>.(ogg|mp3)`, with optional playlist companions
## `<name>_2.(ogg|mp3)`, `<name>_3.(ogg|mp3)`, ... (when 2+ tracks exist for a slot, they
## alternate end-to-end with a short breathing pause; single tracks loop seamlessly).
## Missing biome tracks fall back gracefully (`hexenwald -> night`, `desert -> day`).
## Plays on the bus "Music" (made by `GameSettings.apply`, volume = the MUSIK slider).

const FOLDER: String = "res://assets/audio/music/"
const NAMES: Array[String] = ["day", "hexenwald", "desert", "night", "combat", "boss"]
const DAY: int = 0
const HEXENWALD: int = 1
const DESERT: int = 2
const NIGHT: int = 3
const COMBAT: int = 4
const BOSS: int = 5
const MAX_PLAYLIST: int = 8
const PLAYLIST_GAP: float = 2.5 ## seconds of calm air between two full biome playlist tracks
const LEVEL_DB: Array[float] = [-11.5, -11.5, -11.5, -11.0, -9.0, -8.0]
const INDOOR_DB: float = -7.0 ## rooms and the mine: the outdoor biome track, further away
const FADE_IN: Array[float] = [5.0, 5.0, 5.0, 5.0, 1.2, 0.8] ## seconds
const FADE_OUT: Array[float] = [3.5, 3.5, 3.5, 3.5, 4.0, 5.0]
const BIOME_ENTER: float = 0.45 ## BiomeBlend weight above which a biome track takes over
const COMBAT_RANGE: float = 160.0 ## a shadow creature this close to the camera's middle = a fight
const BOSS_RANGE: float = 620.0
const COMBAT_HOLD: float = 6.0 ## seconds the fight track stays after the last creature left or fell
const CHECK_SECONDS: float = 0.25

var night: float = 0.0 ## 0 day .. 1 night (true clock night from TimeManager)
var gloom: float = 0.0 ## 0 meadow .. 1 Hexenwald (preserved while indoors)
var arid: float = 0.0 ## 0 meadow .. 1 Sonnenquarz-Öde (preserved while indoors)
var indoors: bool = false
var vista_mode: bool = false ## local player is seated at a panoramic VistaPoint

const VISTA_DUCK_DB: float = -5.5
const VISTA_BREEZE_DB: float = -13.5

var _vista_blend: float = 0.0
var _vista_breeze: AudioStreamPlayer


var _players: Array[AudioStreamPlayer] = []
var _playlists: Array = [] ## Array[Array[AudioStream]] per slot
var _track_idx: Array[int] = [0, 0, 0, 0, 0, 0]
var _gap_left: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _amount: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] ## 0..1 share of each track
var _current: int = DAY
var _hold: float = 0.0
var _check: float = 0.0
var _threat: int = -1 ## COMBAT, BOSS or -1


func _ready() -> void:
	add_to_group("music_director")
	process_mode = Node.PROCESS_MODE_ALWAYS ## the music plays on in the pause menu
	GameSettings.apply() ## makes sure the bus exists
	for i: int in NAMES.size():
		var list: Array[AudioStream] = _load_playlist(NAMES[i])
		_playlists.append(list)
		var start_idx: int = randi() % list.size() if list.size() > 1 else 0
		_track_idx[i] = start_idx
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.stream = list[start_idx] if not list.is_empty() else null
		p.bus = &"Music"
		p.volume_db = -80.0
		p.finished.connect(_on_track_finished.bind(i))
		add_child(p)
		_players.append(p)
	if ResourceLoader.exists("res://assets/audio/vistas/wind_high.wav"):
		var breeze: AudioStreamWAV = (load("res://assets/audio/vistas/wind_high.wav") as AudioStreamWAV).duplicate() as AudioStreamWAV
		if breeze != null:
			breeze.loop_mode = AudioStreamWAV.LOOP_FORWARD
			breeze.loop_begin = 0
			breeze.loop_end = int(breeze.data.size() / 2)
			_vista_breeze = AudioStreamPlayer.new()
			_vista_breeze.stream = breeze
			_vista_breeze.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
			_vista_breeze.volume_db = -80.0
			add_child(_vista_breeze)


func _load_single(stem: String, should_loop: bool) -> AudioStream:
	for ext: String in ["ogg", "mp3"]:
		var path: String = FOLDER + stem + "." + ext
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = should_loop
			elif stream is AudioStreamMP3:
				(stream as AudioStreamMP3).loop = should_loop
			return stream
	return null


func _load_playlist(base_name: String) -> Array[AudioStream]:
	var stems: Array[String] = []
	for idx: int in range(1, MAX_PLAYLIST + 1):
		var stem: String = base_name if idx == 1 else "%s_%d" % [base_name, idx]
		var found: bool = false
		for ext: String in ["ogg", "mp3"]:
			if ResourceLoader.exists(FOLDER + stem + "." + ext):
				found = true
				break
		if found:
			stems.append(stem)
		elif idx >= 2:
			break
	var loop_single: bool = stems.size() <= 1
	var out: Array[AudioStream] = []
	for stem: String in stems:
		var s: AudioStream = _load_single(stem, loop_single)
		if s != null:
			out.append(s)
	return out


func _on_track_finished(slot: int) -> void:
	var list: Array[AudioStream] = _playlists[slot] as Array[AudioStream]
	if list.size() <= 1:
		return
	_track_idx[slot] = (_track_idx[slot] + 1) % list.size()
	_players[slot].stream = list[_track_idx[slot]]
	_gap_left[slot] = 0.0 if slot >= COMBAT else PLAYLIST_GAP


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_SECONDS
		_threat = _sense()
	if _threat >= 0:
		_hold = COMBAT_HOLD
	elif not get_tree().paused:
		_hold = maxf(_hold - delta, 0.0)
	var has_hex: bool = not (_playlists[HEXENWALD] as Array[AudioStream]).is_empty()
	var has_desert: bool = not (_playlists[DESERT] as Array[AudioStream]).is_empty()
	var want: int = wanted_biome(night, gloom, arid, has_hex, has_desert, _threat, _hold, _current)
	_current = want
	var calm_vista: bool = vista_mode and _threat < 0 and _hold <= 0.0 and not indoors
	_vista_blend = move_toward(_vista_blend, 1.0 if calm_vista else 0.0, delta / (1.8 if calm_vista else 0.9))
	if _vista_breeze != null:
		if _vista_blend <= 0.001:
			if _vista_breeze.playing:
				_vista_breeze.stop()
		else:
			if not _vista_breeze.playing:
				_vista_breeze.play()
			_vista_breeze.volume_db = VISTA_BREEZE_DB + linear_to_db(_vista_blend * _vista_blend)
	for i: int in _players.size():
		if _gap_left[i] > 0.0:
			_gap_left[i] = maxf(_gap_left[i] - delta, 0.0)
		var target: float = 1.0 if i == want else 0.0
		var seconds: float = FADE_IN[i] if target > _amount[i] else FADE_OUT[i]
		_amount[i] = move_toward(_amount[i], target, delta / seconds)
		_apply(i)


## Pure: which track should play given clock night, biome weights, available streams, and combat state.
static func wanted_biome(
	night_amount: float,
	gloom_amount: float,
	arid_amount: float,
	has_hex: bool,
	has_desert: bool,
	threat: int,
	hold: float,
	current: int
) -> int:
	if threat >= 0:
		return threat
	if hold > 0.0 and (current == COMBAT or current == BOSS):
		return current
	if night_amount > 0.5:
		return NIGHT
	if gloom_amount >= BIOME_ENTER:
		return HEXENWALD if has_hex else NIGHT
	if arid_amount >= BIOME_ENTER:
		return DESERT if has_desert else DAY
	return DAY


## Backwards-compatible pure helper for meadow day vs night.
static func wanted(night_amount: float, threat: int, hold: float, current: int) -> int:
	return wanted_biome(night_amount, 0.0, 0.0, false, false, threat, hold, current)


func _apply(i: int) -> void:
	var p: AudioStreamPlayer = _players[i]
	if p.stream == null:
		return
	var amount: float = _amount[i]
	if amount <= 0.001:
		if i >= COMBAT:
			p.stop() ## a fight always starts from its first bar
		elif p.playing:
			p.stream_paused = true ## world tracks go on where they paused
		return
	if _gap_left[i] > 0.0:
		return
	if p.stream_paused:
		p.stream_paused = false
	elif not p.playing:
		p.play()
	var vista_duck: float = VISTA_DUCK_DB * _vista_blend if i < COMBAT else 0.0
	var level: float = LEVEL_DB[i] + (INDOOR_DB if indoors and i < COMBAT else 0.0) + vista_duck
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
