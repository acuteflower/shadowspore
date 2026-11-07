class_name SeatSpot
extends StorySpot
## A place a player can sit (RestComponent plays the poses): the base of the hut's fire seats (`CampfireSeat`) and the benches of the town (`BenchSeat`).
## A seat knows where the sitter stands and looks, whether somebody sits there already, whether this player may use it and what sitting there is worth.

const SETTLER_CLEARANCE: float = 22.0


func sit_sector() -> int:
	return 2


func sit_direction() -> Vector2:
	return Vector2.RIGHT.rotated(float(sit_sector()) * PI / 4.0)


func seat_position() -> Vector2:
	return global_position


func approach_position() -> Vector2:
	return seat_position() + Vector2(0.0, 12.0)


## May this (local) player sit here right now? The fire seats wait for the story.
func usable_by(player: Player) -> bool:
	return player != null and not player.story_lock


## Health a second while seated (host, `RestComponent`); the bench is worth something, a plain seat nothing.
func regen_rate() -> float:
	return 0.0


## Host: called every second while somebody sits here (`seated` = seconds since sitting down).
func rest_tick(_player: Player, _seated: float) -> void:
	pass


func occupied() -> bool:
	for node: Node in get_tree().get_nodes_in_group("settlers"):
		var settler: Node2D = node as Node2D
		if settler != null and settler.visible and settler.global_position.distance_to(seat_position()) < SETTLER_CLEARANCE:
			return true
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Player = node as Player
		var rest: RestComponent = player.get_node_or_null("RestComponent") as RestComponent if player != null else null
		if rest != null and rest.seat == self:
			return true
	return false
