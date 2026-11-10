class_name Sfx
extends RefCounted
## The one place for the sound set of assets/audio/sfx (tools/sfx_manifest.json, made with Higgsfield and
## levelled by tools/sfx_process.py). Positional sounds for the world, flat sounds for menus. A sound that
## does not exist yet is skipped silently, so hooks can be added before the file.

const DIR: String = "res://assets/audio/sfx/"
const WORLD_RANGE: float = 320.0

static var _cache: Dictionary = {}
static var _last: Dictionary = {} ## per group of variants: the one played last, so it never repeats


static func stream(id: String) -> AudioStream:
	if not _cache.has(id):
		var path: String = DIR + id + ".mp3" ## raw Mirelo clips come as mp3, processed ones as wav
		if not ResourceLoader.exists(path):
			path = DIR + id + ".wav"
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[id] as AudioStream


## A seamless bed (a sound with `loop: true` in the manifest) that repeats by itself.
static func loop(id: String) -> AudioStream:
	var s: AudioStream = stream(id)
	if s is AudioStreamWAV:
		var l: AudioStreamWAV = (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		l.loop_mode = AudioStreamWAV.LOOP_FORWARD
		l.loop_begin = 0
		l.loop_end = l.data.size() / (2 if l.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if l.stereo else 1)
		return l
	return s


static func has(id: String) -> bool:
	return stream(id) != null


## One of several variants, never the same twice in a row.
static func pick(ids: Array) -> String:
	if ids.size() <= 1:
		return String(ids[0]) if not ids.is_empty() else ""
	var key: String = String(ids[0])
	var last: int = int(_last.get(key, -1))
	var index: int = (last + 1 + randi() % (ids.size() - 1)) % ids.size() if last >= 0 else randi() % ids.size()
	_last[key] = index
	return String(ids[index])


## A sound at a point in the world; `parent` is any node in the tree (the sound lives on the current scene).
static func at(parent: Node, id: String, position: Vector2, db: float = 0.0, pitch_spread: float = 0.05, range_px: float = WORLD_RANGE) -> void:
	var s: AudioStream = stream(id)
	if s == null or parent == null or not parent.is_inside_tree():
		return
	var scene: Node = parent.get_tree().current_scene
	if scene == null:
		scene = parent
	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = s
	player.volume_db = db
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.max_distance = range_px
	scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


## Several variants: picks one (see `pick`) and plays it at the point.
static func at_any(parent: Node, ids: Array, position: Vector2, db: float = 0.0, pitch_spread: float = 0.05, range_px: float = WORLD_RANGE) -> void:
	at(parent, pick(ids), position, db, pitch_spread, range_px)


## A flat sound for the interface; keeps playing while the game is paused.
static func ui(parent: Node, id: String, db: float = 0.0, pitch_spread: float = 0.03) -> void:
	var s: AudioStream = stream(id)
	if s == null or parent == null or not parent.is_inside_tree():
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = s
	player.volume_db = db
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
