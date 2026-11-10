class_name Hallucinations
extends Node2D
## What a hallucinating heroine sees in the Hexenwald's mist (docs/hexenwald_nebel_konzept.md). A child of the LOCAL player only, made by `StatusEffects` while the
## effect `hallucinated` is on her and freed with it: everything here is cosmetic and hers alone (nothing replicated, nothing saved, no damage, no cost).
## `trug` (0..1) grows with the time in the mist and opens three stages: whispers and eyes in the mist (0.15), false finds, a dark figure and a health or stamina
## vine that lies for a moment (0.45), and phantom shadow spiders that fall apart in the middle of their blow (0.7). Numbers: data/status_effects.json `hallucinated`.

const SOUNDS: String = "res://assets/audio/hexenwald/"
const STAGE: Dictionary = {"eyes": 0.15, "whisper": 0.15, "decoy": 0.45, "lie": 0.45, "phantom": 0.7}
const FINDS: Array[String] = ["shadow_core", "void_splinter", "iron_ingot", "curse_silver", "dusk_berry"]
const FIGURE: Texture2D = preload("res://assets/characters/adventurer.png")

var trug: float = 0.0
var phantom: PhantomSpider

var _def: Dictionary
var _wait: Dictionary = {} ## kind -> seconds until the next one
var _eyes: AmbushEyes
var _eye_left: Dictionary = {} ## slot -> seconds
var _eye_at: Dictionary = {} ## slot -> world position
var _decoy: Sprite2D
var _decoy_left: float = 0.0
var _decoy_reach: float = 12.0
var _lie_left: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_def = StatusEffects.definition("hallucinated")
	for kind: String in STAGE:
		_wait[kind] = _pause(kind) * 0.5
	_eyes = AmbushEyes.new()
	_eyes.modulate = Color(0.72, 2.6, 0.45) ## the eyes of the ambush, in the wood's green
	add_child(_eyes)
	get_tree().call_group("hint_card", "notify_mist")


func _pause(kind: String) -> float:
	var span: Array = _def.get(kind, [20.0, 40.0]) as Array
	return randf_range(float(span[0]), float(span[1])) * lerpf(1.3, 0.8, trug) * lerpf(1.0, 0.7, TimeManager.night_amount())


func _process(delta: float) -> void:
	var player: Player = get_parent() as Player
	if player == null:
		return
	_time += delta
	trug = minf(trug + delta / float(_def.get("trug_seconds", 90.0)), 1.0)
	_tend(player, delta)
	if InputManager.ui_blocking or player.story_lock or player.intro != null or player.health.current <= 0.0:
		return ## nothing new while a scene, a window or death owns her
	for kind: String in STAGE:
		_wait[kind] = float(_wait[kind]) - delta
		if float(_wait[kind]) <= 0.0 and trug >= float(STAGE[kind]):
			_wait[kind] = _pause(kind)
			call("_see_" + kind, player)


## Keeps what is already there: eyes close when she comes near, a false find falls apart in her hand, a lying vine tells the truth again.
func _tend(player: Player, delta: float) -> void:
	for slot: int in _eye_left.keys():
		_eye_left[slot] = float(_eye_left[slot]) - delta
		if float(_eye_left[slot]) <= 0.0 or (_eye_at[slot] as Vector2).distance_to(player.global_position) < 58.0:
			_eyes.close(slot)
			_eye_left.erase(slot)
	if is_instance_valid(_decoy):
		_decoy_left -= delta
		_decoy.position.y += sin(_time * 3.0) * 0.04
		if _decoy_left <= 0.0 or _decoy.global_position.distance_to(player.global_position) < _decoy_reach:
			PhantomSpider.puff(player.get_parent(), _decoy.global_position, -14.0)
			_fade(_decoy)
			_decoy = null
	if _lie_left > 0.0:
		_lie_left -= delta
		if _lie_left <= 0.0:
			_set_lie(-1.0)


## What is false thins out and is gone.
func _fade(node: CanvasItem) -> void:
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "modulate:a", 0.0, 0.6)
	tween.tween_callback(node.queue_free)


func _spot(player: Player, near: float, far: float) -> Vector2:
	return player.global_position + Vector2.from_angle(randf() * TAU) * randf_range(near, far) * Vector2(1.0, 0.7)


func _see_eyes(player: Player) -> void:
	var slot: int = randi()
	_eye_at[slot] = _spot(player, 95.0, 160.0)
	_eye_left[slot] = randf_range(3.0, 6.5)
	_eyes.open(slot, _eye_at[slot] as Vector2)


func _see_whisper(player: Player) -> void:
	var path: String = SOUNDS + "whisper_%s.wav" % ["a", "b", "c"][randi() % 3]
	if not ResourceLoader.exists(path):
		return
	var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.stream = load(path) as AudioStream
	voice.volume_db = lerpf(-20.0, -11.0, trug)
	voice.pitch_scale = randf_range(0.8, 1.15)
	voice.max_distance = 500.0
	voice.position = Vector2(-150.0 if randf() < 0.5 else 150.0, randf_range(-40.0, 40.0)) ## from one side, close to the ear
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()


## Something that is not there: a find that glints on the ground, or (more rarely) a dark figure standing between the trunks.
func _see_decoy(player: Player) -> void:
	if is_instance_valid(_decoy):
		return
	_decoy = Sprite2D.new()
	if randf() < 0.3:
		_decoy.texture = FIGURE
		_decoy.region_enabled = true
		_decoy.region_rect = Rect2(0, 200, 84, 100) ## the knight's idle frame, facing her (south)
		_decoy.offset = Vector2(0, -34)
		_decoy.modulate = Color(0.05, 0.08, 0.09, 0.9) ## only a shape
		_decoy.global_position = _spot(player, 170.0, 210.0)
		_decoy_reach = 84.0
		_decoy_left = 22.0
	else:
		_decoy.texture = Items.icon({"id": FINDS[randi() % FINDS.size()], "count": 1})
		_decoy.offset = Vector2(0, -6)
		_decoy.material = Unlit.material()
		_decoy.global_position = _spot(player, 60.0, 115.0)
		_decoy_reach = 12.0
		_decoy_left = 28.0
	_decoy.top_level = false
	var at: Vector2 = _decoy.global_position
	player.get_parent().add_child(_decoy) ## beside her, so it sorts with the trees
	_decoy.global_position = at


## The health or the stamina vine suddenly shows almost nothing, and switches back.
func _see_lie(_player: Player) -> void:
	_set_lie(-1.0)
	var vines: Array[Node] = get_tree().get_nodes_in_group("sap_vines")
	if vines.is_empty():
		return
	(vines[randi() % vines.size()] as SapVine).lie = randf_range(0.05, 0.2)
	_lie_left = randf_range(1.2, 2.6)


func _set_lie(value: float) -> void:
	for vine: Node in get_tree().get_nodes_in_group("sap_vines"):
		(vine as SapVine).lie = value


func _see_phantom(player: Player) -> void:
	if is_instance_valid(phantom):
		return
	for hunter: Node in get_tree().get_nodes_in_group("predators"):
		if hunter is Node2D and (hunter as Node2D).global_position.distance_to(player.global_position) < 240.0:
			return ## something real is at her: that must stay readable
	phantom = PhantomSpider.new()
	phantom.target = player
	player.get_parent().add_child(phantom)
	phantom.global_position = _spot(player, 110.0, 160.0)


## Her head clears (she left the wood, or put the Ohrringe der Klarheit on): everything false falls apart at once.
func _exit_tree() -> void:
	if is_inside_tree():
		_set_lie(-1.0)


## Called by `StatusEffects` when the effect ends (not when the whole scene is torn down).
func end() -> void:
	if is_instance_valid(phantom):
		phantom.dissolve(true)
	if is_instance_valid(_decoy):
		_fade(_decoy)
	var player: Player = get_parent() as Player
	if player != null and player.talismans != null and player.talismans.perks.has("clear_sight") and ResourceLoader.exists(SOUNDS + "clear.wav"):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.stream = load(SOUNDS + "clear.wav") as AudioStream
		voice.volume_db = -8.0
		player.add_child(voice)
		voice.finished.connect(voice.queue_free)
		voice.play()
