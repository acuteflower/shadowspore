class_name StumbleGuide
extends Node
## The story's footpath hurts: while she is badly wounded and walking, she trips at a few places (data/ground.json "stumbles": tile + radius in
## tiles) and has to get up again with E (`Player.begin_stumble`). Inside a place there is a chance on every step; leaving it without a stumble
## trips her at the far edge, so it happens at a different spot each time but always once. Each place trips her once; the flags `stumble_0` ... are saved with the quests.
## Not near spiders, not while a dialogue is open or she stands still.

const SPIDER_AVOID: float = 240.0

const ROLL_EVERY: float = 0.32 ## about one step
const CHANCE: float = 0.22 ## per step inside the place

var _player: Player
var _spots: Array = []
var _roll: float = 0.0
var _inside: int = -1 ## the place she is walking through (-1 = none)


func _ready() -> void:
	_player = get_parent() as Player
	_spots = DataRegistry.table("ground").get("stumbles", []) as Array


func _physics_process(delta: float) -> void:
	if _player == null or _player.quests == null or not _player.wounded or _player.velocity.length() < 25.0 or InputManager.ui_blocking:
		return
	_roll -= delta
	for i: int in _spots.size():
		var flag: String = "stumble_%d" % i
		if _player.quests.has_flag(flag):
			continue
		var spot: Dictionary = _spots[i] as Dictionary
		var tile: Array = spot.tile as Array
		var at: Vector2 = Vector2(float(tile[0]), float(tile[1])) * 16.0 + Vector2(8, 8)
		var reach: float = float(spot.get("radius", 4.0)) * 16.0
		var distance: float = _player.global_position.distance_to(at)
		if distance > reach:
			if _inside == i: ## she walked through the whole place without a stumble: the foot catches now
				_inside = -1
				_trip(flag)
			continue
		_inside = i
		if _roll <= 0.0 and not _near_spider():
			_roll = ROLL_EVERY
			if randf() < CHANCE:
				_trip(flag)
		return


func _trip(flag: String) -> void:
	if not _near_spider() and _player.begin_stumble():
		_player.quests.set_flag(flag)


func _near_spider() -> bool:
	for node: Node in get_tree().get_nodes_in_group("predators"):
		if node is Node2D and (node as Node2D).global_position.distance_to(_player.global_position) < SPIDER_AVOID:
			return true
	return false
