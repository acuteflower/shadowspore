class_name PetFeedSpot
extends Interactable
## The "E FÜTTERN" of a wild crow or raven (docs/pet_konzept.md): a child of the bird on every peer. The prompt only shows while the bird itself has made an
## offer to this player (`WildCorvid.offered_peer`: it came up to her, calm, and trusts her with food in her hand), so there is nothing to click at a
## distance; she has to earn the moment. E makes her crouch and hold the food out (`Player.begin_feed`); when the hand is out the host decides
## (`PetBehavior.take`) and everybody sees the result (`_result`): the bird eats from her hand, or turns away.

const SOUNDS: Dictionary = { ## tools/audio_pets.py
	"take": preload("res://assets/audio/pets/take.wav"), "up": preload("res://assets/audio/pets/up.wav"),
	"refuse": preload("res://assets/audio/pets/refuse.wav"), "notice": preload("res://assets/audio/pets/notice.wav"),
}

var _bird: WildCorvid


func _ready() -> void:
	_bird = get_parent() as WildCorvid


func prompt() -> String:
	var me: Player = _local()
	var registry: PetRegistry = PetRegistry.of(get_tree())
	if me != null and _bird != null and registry != null and not me.is_busy() and registry.has_record(_bird.pet_key) and (_bird.state != WildCorvid.State.FLY or _bird.rider != 0):
		var peer: int = me.name.to_int()
		if registry.companion_of(peer) == _bird.pet_key:
			return "HORT"
		if registry.can_take(_bird.pet_key, peer) and _bird.offered_peer == 0:
			return "MITNEHMEN"
	if me == null or _bird == null or _bird.offered_peer != me.name.to_int() or me.is_busy() or _food(me) == "":
		return ""
	return "FÜTTERN"


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, _bird.global_position.distance_to(from) - 30.0) if _bird != null else INF


func prompt_position() -> Vector2:
	return Vector2(0.0, -64.0) ## above the name tag (PetTag hangs at -28..-44)


func interact(player: Player) -> void:
	var registry: PetRegistry = PetRegistry.of(get_tree())
	var word: String = prompt()
	if registry != null and (word == "HORT" or word == "MITNEHMEN"):
		if word == "HORT":
			registry.open_hoard(player, _bird.pet_key)
		else:
			registry.ask("take", _bird.pet_key)
		return
	var item: String = _food(player)
	if item == "" or _bird == null:
		return
	var toward: Vector2 = (_bird.global_position - player.global_position).normalized()
	player.begin_feed(toward, item, func() -> void:
		if multiplayer.is_server():
			_request_feed()
		else:
			_request_feed.rpc_id(1))


## The player's food in hand (the selected hotbar slot), or "" when it is nothing a bird eats.
func _food(player: Player) -> String:
	var stack: Dictionary = player.inventory.slots[player.inventory.selected] as Dictionary
	if stack.is_empty() or _bird == null:
		return ""
	var kind: String = PetRules.reaction(_bird.species, String(stack["id"]), _bird.pet_key)
	return String(stack["id"]) if kind != PetRules.NO_REACTION and kind != "dislikes" else ""


func _local() -> Player:
	for player: Player in Player.all:
		if player.is_multiplayer_authority():
			return player
	return null


@rpc("any_peer", "call_remote", "reliable")
func _request_feed() -> void:
	if not multiplayer.is_server() or _bird == null or _bird._pet == null:
		return
	var peer: int = multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = 1
	var player: Player = null
	for candidate: Player in Player.all:
		if candidate.name.to_int() == peer:
			player = candidate
	if player == null:
		return
	var result: Dictionary = _bird._pet.take(player)
	_result.rpc(peer, bool(result["ok"]), String(result["reaction"]), float(result["gain"]), bool(result["up"]))


@rpc("authority", "call_local", "reliable")
func _result(peer: int, ok: bool, reaction: String, _gain: float, stage_up: bool) -> void:
	if _bird == null or not is_inside_tree():
		return
	if ok:
		PetBondFx.spawn(_bird.get_parent(), _bird.global_position, stage_up)
	_play("up" if ok and stage_up else ("take" if ok else "refuse"), reaction == "")
	for player: Player in Player.all:
		if player.is_multiplayer_authority() and player.name.to_int() == peer:
			player.release_feed()


func _play(sound: String, _quiet: bool) -> void:
	var volume: float = float(GameSettings.get_value("sfx")) / 100.0
	if volume <= 0.0:
		return
	var voice: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	voice.stream = SOUNDS[sound] as AudioStream
	voice.volume_db = -9.0 + linear_to_db(volume)
	voice.max_distance = 260.0
	voice.pitch_scale = randf_range(0.97, 1.04)
	_bird.add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
