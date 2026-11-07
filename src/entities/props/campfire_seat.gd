class_name CampfireSeat
extends SeatSpot
## The first use belongs to the story; afterwards this is an ordinary resting place.

var hut: Hut
var which: String = "east"
@export_range(-1, 7) var facing_sector: int = -1 ## -1 keeps the original fire-facing direction


func sit_sector() -> int:
	return facing_sector if facing_sector >= 0 else (4 if which == "east" else 5)


func sit_direction() -> Vector2:
	return Vector2.RIGHT.rotated(float(sit_sector()) * PI / 4.0)


func seat_position() -> Vector2:
	return hut.global_position + (KnightFireScene.STUMP + Vector2(0, 3) if which == "east" else KnightFireScene.LOG + Vector2(4, 3))


func approach_position() -> Vector2:
	return seat_position() + (Vector2(10, 14) if which == "east" else Vector2(0, 12))


func occupied() -> bool:
	var world: Node = get_tree().get_first_node_in_group("world")
	var quarry: Quarry = world.get_node_or_null("Quarry_quarry") as Quarry if world != null else null
	if quarry != null and quarry.knight_left and is_instance_valid(quarry.knight) and quarry.knight.visible and quarry.knight.global_position.distance_to(seat_position()) < 18.0:
		return true
	for node: Node in get_tree().get_nodes_in_group("settlers"): ## Valdric on night watch, or anyone else who sits here
		var settler: Node2D = node as Node2D
		if settler != null and settler.visible and settler.global_position.distance_to(seat_position()) < 22.0:
			return true
	for node: Node in get_tree().get_nodes_in_group("players"):
		var player: Player = node as Player
		var rest: RestComponent = player.get_node_or_null("RestComponent") as RestComponent
		if rest != null and rest.seat == self:
			return true
	return false


## The evening circle: a sitter with company at the fire gets warm after a few quiet seconds (`FireCircle`).
func rest_tick(player: Player, seated: float) -> void:
	FireCircle.tick(get_tree().get_first_node_in_group("town") as TownManager, player, seat_position(), seated)


func usable_by(player: Player) -> bool:
	return player != null and player.quests != null and player.quests.has_flag("fire_seated")


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or player.quests == null or player.health.current <= 0.0 or player.intro != null or player.story_lock or player.fainting or InputManager.ui_blocking:
		return ""
	if player.quests.has_flag("fire_seated"):
		return "HINSETZEN" if not occupied() else ""
	return super.prompt()


func interact(player: Player) -> void:
	if not player.is_multiplayer_authority() or prompt() == "":
		return
	if player.quests.has_flag("fire_seated"):
		(player.get_node("RestComponent") as RestComponent).request_sit(self)
	else:
		super.interact(player)
