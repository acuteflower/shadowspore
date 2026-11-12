class_name HoardSpot
extends Interactable
## The E of the crow's hoard (`CrowHoard`): on the crow ("FÜTTERN", only while it stands in front of this player and she holds food it likes) and on
## the earth mound ("GRABEN", greyed out without a hoe in hand: the hoe digs by swinging). Everything is asked of the trial.

var trial: CrowHoard
var kind: String = "crow" ## "crow" | "mound"


func prompt() -> String:
	return trial.spot_prompt(kind) if trial != null else ""


func prompt_hint() -> String:
	return trial.spot_hint(kind) if trial != null else ""


func reach_distance(from: Vector2) -> float:
	return maxf(0.0, global_position.distance_to(from) - (26.0 if kind == "crow" else 14.0))


func prompt_position() -> Vector2:
	return Vector2(0, -34) if kind == "crow" else Vector2(0, -22)


func interact(player: Player) -> void:
	if trial != null:
		trial.spot_used(kind, player)
