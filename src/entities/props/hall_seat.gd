class_name HallSeat
extends SeatSpot
## A place on a bench of the hallway (data `seats` of the bench prop: [dx, dy, sector, approach dx, approach dy], from the prop's feet). E sits her down with the poses of `RestComponent`
## (approach, sitting down, breathing, the gestures, getting up); a bench of the hallway heals nothing. Built by `Interior` on every peer, so the host finds the seat a remote player asks for.

var sector: int = 6
var approach: Vector2 = Vector2(0.0, -14.0)


func setup(at: Vector2, facing_sector: int, approach_offset: Vector2) -> void:
	position = at
	sector = facing_sector
	approach = approach_offset
	label = "HINSETZEN"
	radius = 14.0
	height = 30.0


func sit_sector() -> int:
	return sector


func approach_position() -> Vector2:
	return global_position + approach


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or player.health.current <= 0.0 or player.intro != null or player.story_lock or player.fainting or InputManager.ui_blocking:
		return ""
	return label if not occupied() else ""


func interact(player: Player) -> void:
	if not player.is_multiplayer_authority() or prompt() == "":
		return
	(player.get_node("RestComponent") as RestComponent).request_sit(self)
