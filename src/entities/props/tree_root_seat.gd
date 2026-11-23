class_name TreeRootSeat
extends SeatSpot
## Cozy mossy clover-and-buttress-root resting hollow at the base of an Ancient Glimmtal Oak (`LivingTree` Stage 5).
## Supports host-confirmed sitting via `RestComponent` (`E -> UNTER DER TAL-EICHE RASTEN`), gentle health regeneration,
## and presses a soft resting impression into nearby `LivingGrass`.

var host_tree: Node2D = null
var custom_label: String = ""


func _ready() -> void:
	label = custom_label if not custom_label.is_empty() else "UNTER DER TAL-EICHE RASTEN"
	radius = 20.0
	height = 34.0


func sit_sector() -> int:
	return 2 ## Facing south out across the sunlit meadow & woodland edge


func seat_position() -> Vector2:
	return global_position


func approach_position() -> Vector2:
	return global_position + Vector2(0.0, 13.0)


func prompt_position() -> Vector2:
	return Vector2(0.0, -28.0)


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, global_position.distance_to(from) - 18.0)


func regen_rate() -> float:
	return 0.70


func usable_by(player: Player) -> bool:
	if host_tree != null and host_tree.has_method("is_depleted") and bool(host_tree.call("is_depleted")):
		return false
	return super.usable_by(player)


func prompt() -> String:
	var player: Player = _local_player()
	if player == null or player.health.current <= 0.0 or player.intro != null or player.story_lock or player.fainting or InputManager.ui_blocking:
		return ""
	if not usable_by(player) or occupied():
		return ""
	return label


func interact(player: Player) -> void:
	if player == null or not player.is_multiplayer_authority() or prompt() == "":
		return
	for gnode: Node in get_tree().get_nodes_in_group("living_grass"):
		var lg: LivingGrass = gnode as LivingGrass
		if lg != null:
			lg.stamp_rest_nest(global_position, 14.0, 0.85, 4.0)
	var rest: RestComponent = player.get_node_or_null("RestComponent") as RestComponent
	if rest != null:
		rest.request_sit(self)
