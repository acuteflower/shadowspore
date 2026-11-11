class_name StorySpot
extends Interactable
## A place E can use while the local player has the matching story step (the seats at the hut's fire, the bed at night).
## `use` is called with the player; the spot says nothing at any other time.

var label: String = "SITZEN"
var step: String = ""
var radius: float = 14.0
var height: float = 30.0
var use: Callable = Callable()


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or player.quests == null or player.story_lock or InputManager.ui_blocking:
		return ""
	return label if player.quests.has_active_step(step) else ""


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - radius


func prompt_position() -> Vector2:
	return Vector2(0, -height)


func interact(player: Player) -> void:
	if use.is_valid():
		use.call(player)


func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null
