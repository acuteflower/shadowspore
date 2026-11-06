class_name MineStairs
extends Interactable
## The stairs of a mine level (the sprite is a prop of `MineLevel`): the way up at the entry hall, the way down at the far end. E carries the local player to the
## next level with the iris (`MineManager.travel`): down arrives at the entry of the level below, up at the stairs down of the level above; the stairs up of
## level 1 lead out to the mine's gate.

var level: int = 1
var up: bool = true


func prompt() -> String:
	if up:
		return "NACH DRAUSSEN" if level == 1 else "HINAUF"
	return "" if level >= MineManager.MAX_LEVELS else "HINUNTER"


func reach_distance(from: Vector2) -> float:
	return from.distance_to(global_position) - 20.0


func prompt_position() -> Vector2:
	return Vector2(0, -36)


func interact(player: Player) -> void:
	var mines: MineManager = get_tree().get_first_node_in_group("mines") as MineManager
	if mines == null or prompt() == "":
		return
	if up:
		mines.travel(player, level - 1, "exit")
	else:
		mines.travel(player, level + 1, "entry")
